--!strict
-- EpilogRoute.luau
-- ReplicatedStorage/Modules/EpilogRoute.luau
--
-- Einzige Zustaendigkeit (Prompt 5, Final-Epilog):
--   - Reine Geometrie fuer den Weg Gipfel -> Insel: Laenge, Punkt/Richtung bei
--     Bogenlaenge s, Projektion einer Position auf den Weg, und das Lauftempo
--     (Tempo-Wechsel, auf die Wegstrecke normiert).
--
-- Punkte sind Zahlen-Tabellen {x, y, z} (kein Vector3), damit die Tests ohne Roblox
-- laufen. Server (Begleiter) und Client (Kamera, Lauf) rechnen mit denselben Funktionen.

local EpilogRoute = {}

export type V3 = { number }

export type Route = {
	points : { V3 },
	cum    : { number },   -- Bogenlaenge am Punkt i (cum[1] = 0)
	length : number,
}

local function sub(a: V3, b: V3): V3 return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
local function dot(a: V3, b: V3): number return a[1] * b[1] + a[2] * b[2] + a[3] * b[3] end
local function len(a: V3): number return math.sqrt(dot(a, a)) end

function EpilogRoute.new(points: { V3 }): Route
	local cum: { number } = { 0 }
	local total = 0
	for i = 2, #points do
		total += len(sub(points[i], points[i - 1]))
		cum[i] = total
	end
	return { points = points, cum = cum, length = total }
end

local function segmentAt(route: Route, s: number): (number, number)
	local n = #route.points
	if n < 2 then return 1, 0 end
	local clamped = math.clamp(s, 0, route.length)
	for i = 2, n do
		if clamped <= route.cum[i] or i == n then
			local segLen = route.cum[i] - route.cum[i - 1]
			local t = if segLen > 1e-9 then (clamped - route.cum[i - 1]) / segLen else 0
			return i - 1, math.clamp(t, 0, 1)
		end
	end
	return n - 1, 1
end

-- Punkt bei Bogenlaenge s (ausserhalb 0..length begrenzt).
function EpilogRoute.pointAt(route: Route, s: number): V3
	local n = #route.points
	if n == 0 then return { 0, 0, 0 } end
	if n == 1 then return { route.points[1][1], route.points[1][2], route.points[1][3] } end
	local i, t = segmentAt(route, s)
	local a, b = route.points[i], route.points[i + 1]
	return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t }
end

-- Waagrechte Laufrichtung (Einheitsvektor, y = 0) bei Bogenlaenge s. Ueber einem
-- senkrechten Stueck bleibt die Richtung des letzten gueltigen Stuecks.
function EpilogRoute.directionAt(route: Route, s: number): V3
	local n = #route.points
	if n < 2 then return { 1, 0, 0 } end
	local i = segmentAt(route, s)
	for k = i, 1, -1 do
		local d = sub(route.points[k + 1], route.points[k])
		local h = math.sqrt(d[1] * d[1] + d[3] * d[3])
		if h > 1e-6 then return { d[1] / h, 0, d[3] / h } end
	end
	for k = i + 1, n - 1 do
		local d = sub(route.points[k + 1], route.points[k])
		local h = math.sqrt(d[1] * d[1] + d[3] * d[3])
		if h > 1e-6 then return { d[1] / h, 0, d[3] / h } end
	end
	return { 1, 0, 0 }
end

-- Bogenlaenge des dem Punkt `p` naechsten Wegpunkts (3D-Abstand zum Streckenzug).
function EpilogRoute.project(route: Route, p: V3): number
	local n = #route.points
	if n < 2 then return 0 end
	local bestS, bestD = 0, math.huge
	for i = 1, n - 1 do
		local a, b = route.points[i], route.points[i + 1]
		local ab = sub(b, a)
		local ap = sub(p, a)
		local l2 = dot(ab, ab)
		local t = if l2 > 1e-9 then math.clamp(dot(ap, ab) / l2, 0, 1) else 0
		local q = { a[1] + ab[1] * t, a[2] + ab[2] * t, a[3] + ab[3] * t }
		local d = len(sub(p, q))
		if d < bestD then
			bestD = d
			bestS = route.cum[i] + (route.cum[i + 1] - route.cum[i]) * t
		end
	end
	return bestS
end

--------------------------------------------------------------------------------
-- Lauftempo
--------------------------------------------------------------------------------

export type Factor = { number }   -- { von, bis, Faktor } in Sekunden

export type Profile = {
	base     : number,        -- Studs/s bei Faktor 1
	duration : number,
	factors  : { Factor },
}

-- Mittleres Tempo so, dass die Strecke `length` in genau `duration` Sekunden
-- geschafft wird, wenn die Faktoren jeweils im Zeitabschnitt gelten. Die Faktoren
-- muessen 0..duration luckenlos abdecken (sonst gilt Faktor 1 in der Luecke).
function EpilogRoute.profile(length: number, duration: number, factors: { Factor }): Profile
	local weighted = 0
	local covered = 0
	for _, f in factors do
		local d = math.max(0, math.min(f[2], duration) - math.max(f[1], 0))
		weighted += d * f[3]
		covered += d
	end
	weighted += math.max(0, duration - covered)   -- Luecken: Faktor 1
	local base = if weighted > 1e-9 then length / weighted else 0
	return { base = base, duration = duration, factors = factors }
end

function EpilogRoute.factorAt(profile: Profile, tau: number): number
	for _, f in profile.factors do
		if tau >= f[1] and tau < f[2] then return f[3] end
	end
	return 1
end

function EpilogRoute.speedAt(profile: Profile, tau: number): number
	return profile.base * EpilogRoute.factorAt(profile, tau)
end

-- Zurueckgelegte Strecke nach tau Sekunden (stueckweise Integration, begrenzt auf die Dauer).
function EpilogRoute.distanceAt(profile: Profile, tau: number): number
	local t = math.clamp(tau, 0, profile.duration)
	local total = 0
	local last = 0
	local sorted = profile.factors
	for _, f in sorted do
		local a, b = math.max(f[1], 0), math.min(f[2], t)
		if b > a then total += (b - a) * f[3] * profile.base end
		last = math.max(last, f[2])
	end
	-- Luecken (Faktor 1)
	local covered = 0
	for _, f in sorted do
		covered += math.max(0, math.min(f[2], t) - math.max(f[1], 0))
	end
	total += math.max(0, t - covered) * profile.base
	return total
end

return EpilogRoute
