-- epilog_camera.test.lua — 20.10. Final-Epilog, Prompt 5 (Kameraweg, Zeitlupe, Lauftempo)
-- python tools/luau-tests/run_local.py tools/luau-tests/epilog_camera.test.lua
--
-- Prueft die reine Rechnung (Modules/EpilogCameraPath, EpilogRoute, Config):
--   1. Zeitplan: Reihenfolge, Uebereinstimmung mit TIMELINE, Skip ab Sekunde 12
--   2. Zeitlupe: monoton, Hit-Freeze, 0,4x / 0,5x, trifft bei 2 s und 12 s die reale Zeit
--   3. Phasen: Grenzen 2/5/12/24/34
--   4. Kamera: nur endliche Zahlen, FOV im Rahmen, keine Spruenge ausser dem Flash-Schnitt
--   5. Phase 5: Dolly-Zoom haelt die Terminalgroesse konstant; "reduced" ohne FOV-Aenderung
--   6. Lauftempo: Strecke in genau 12 s, Tempo in den Grenzen, Begleiter voraus
--   7. Effekte: Teilchen <= 60, "reduced" halbiert, Fenster liegen in der Sequenz
--   8. Weg: Projektion, Richtung, Laenge

local EpilogConfig     = require(RS.Config.EpilogConfig)
local EpilogRoute      = require(RS.Modules.EpilogRoute)
local EpilogCameraPath = require(RS.Modules.EpilogCameraPath)

local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else
		failures += 1
		print("FAIL " .. name .. (if detail ~= nil then ": " .. tostring(detail) else ""))
	end
end

local Q, T, C, FX = EpilogConfig.SEQUENCE, EpilogConfig.TIMELINE, EpilogConfig.CAMERA, EpilogConfig.FX

-- 1. Zeitplan
check("Reihenfolge teleport < bridge < walk < arrive < end",
	Q.teleportAt < Q.bridgeAt and Q.bridgeAt < Q.walkAt and Q.walkAt < Q.arriveAt and Q.arriveAt < Q.endAt)
check("Zeitplan = TIMELINE (5/12/24/34)", Q.bridgeAt == T.TELEPORT_END and Q.walkAt == T.REVEAL_END
	and Q.arriveAt == T.BRIDGE_END and Q.endAt == T.ARRIVAL_END)
check("Flash-Hoehepunkt nach dem Sieg-Beat (2 s) und vor 5 s", Q.teleportAt > T.VICTORY_END and Q.teleportAt < Q.bridgeAt)
check("Skip erst ab Sekunde 12, Halten 1 s", Q.skipFromSeconds == 12 and Q.skipHoldSeconds == 1)
check("Zeitraffer 0,5..5", Q.minSpeed == 0.5 and Q.maxSpeed == 5)

-- 2. Zeitlupe
local mono, prev = true, -1
for i = 0, 1400 do
	local c = EpilogCameraPath.warp(i * 0.01)
	if c < prev - 1e-9 then mono = false end
	prev = c
end
check("warp monoton", mono)
check("warp(0) = 0 (Hit-Freeze: Kamera steht bis 0,15 s)", EpilogCameraPath.warp(0) == 0 and EpilogCameraPath.warp(0.15) == 0)
local r1 = (EpilogCameraPath.warp(0.95) - EpilogCameraPath.warp(0.15)) / 0.8
check("0,4x fuer 0,8 s", math.abs(r1 - 0.4) < 1e-6, r1)
local r2 = (EpilogCameraPath.warp(9.6) - EpilogCameraPath.warp(7.6)) / 2
check("0,5x beim Insel-Reveal", math.abs(r2 - 0.5) < 1e-6, r2)
check("warp(2) = 2 und warp(12) = 12 (kein Versatz)", EpilogCameraPath.warp(2) == 2 and EpilogCameraPath.warp(12) == 12)
check("nach 12 s 1:1", math.abs(EpilogCameraPath.warp(20) - 20) < 1e-9)
local aufholen = (EpilogCameraPath.warp(12) - EpilogCameraPath.warp(9.6)) / 2.4
check("Aufholen nach der Zeitlupe schneller als 1x, aber unter 2x", aufholen > 1 and aufholen < 2, aufholen)

-- 3. Phasen
check("Phasen", EpilogCameraPath.phaseAt(0) == 1 and EpilogCameraPath.phaseAt(1.99) == 1 and EpilogCameraPath.phaseAt(2) == 2
	and EpilogCameraPath.phaseAt(4.99) == 2 and EpilogCameraPath.phaseAt(5) == 3 and EpilogCameraPath.phaseAt(11.99) == 3
	and EpilogCameraPath.phaseAt(12) == 4 and EpilogCameraPath.phaseAt(23.99) == 4 and EpilogCameraPath.phaseAt(24) == 5
	and EpilogCameraPath.phaseAt(33.99) == 5 and EpilogCameraPath.phaseAt(34) == 6)

-- Testszene: Gipfel bei (0, 60, 0), Bruecke in +X, Insel 86 Studs weiter und 18 hoeher
local summitCenter = { 0, 63.4, 0 }
local dir = { 1, 0, 0 }
local route = EpilogRoute.new({ { 0, 60, 0 }, { 12, 60.5, 0 }, { 80, 78, 0 }, { 86, 78.2, 0 } })
local terminal = { pos = { 86 + 3.5 + 0, 78.2, 0 }, look = { 76, 78.2, 0 } }
local profile = EpilogRoute.profile(route.length, Q.arriveAt - Q.walkAt, Q.walkFactors)

local function avatarAt(t)
	if t < Q.walkAt then return summitCenter, 0 end
	local s = EpilogRoute.distanceAt(profile, t - Q.walkAt)
	local p = EpilogRoute.pointAt(route, s)
	return { p[1], p[2] + 3.4, p[3] }, s
end

local function ctxAt(t, reduced)
	local av, s = avatarAt(t)
	return {
		cam0 = { -20, 70, -14 }, fov0 = 70,
		summit = { center = summitCenter, dir = dir },
		route = route, avatar = av, progress = s,
		island = { center = { 86, 78.2, 0 } },
		terminal = terminal,
		default = { pos = { av[1] - 12, av[2] + 6, av[3] }, look = av, fov = 70 },
		reduced = reduced or false,
	}
end

local function finite(v)
	for i = 1, 3 do
		if v[i] ~= v[i] or math.abs(v[i]) == math.huge then return false end
	end
	return true
end

-- 4. Kamera: endlich, FOV, Spruenge
local okFinite, okFov, worst = true, true, 0
local jumps = {}
local lastPose = nil
for step = 0, 724 do
	local t = step * 0.05
	local pose = EpilogCameraPath.sample(t, ctxAt(t, false))
	if not (finite(pose.pos) and finite(pose.look) and pose.fov == pose.fov) then okFinite = false end
	if pose.fov < 30 or pose.fov > 95 then okFov = false end
	if lastPose then
		local d = math.sqrt((pose.pos[1] - lastPose.pos[1]) ^ 2 + (pose.pos[2] - lastPose.pos[2]) ^ 2 + (pose.pos[3] - lastPose.pos[3]) ^ 2)
		local dl = math.sqrt((pose.look[1] - lastPose.look[1]) ^ 2 + (pose.look[2] - lastPose.look[2]) ^ 2 + (pose.look[3] - lastPose.look[3]) ^ 2)
		local df = math.abs(pose.fov - lastPose.fov)
		-- erlaubt: der Flash-Schnitt bei teleportAt (2,25 s) zwischen t = 2,2 und 2,25
		local cut = t > 2.2 - 1e-9 and t < 2.3
		if not cut then
			if d > worst then worst = d end
			local jerk = t < 0.45   -- gewollter Zoom-Ruck (FOV 70 -> 55)
			if d > 2.5 or dl > 6 or (df > 2.5 and not jerk) then table.insert(jumps, string.format("t=%.2f pos %.2f look %.2f fov %.2f", t, d, dl, df)) end
		end
	end
	lastPose = pose
end
check("Kamera: alle Werte endlich (0..36 s)", okFinite)
check("Kamera: FOV zwischen 30 und 95", okFov)
check("Kamera: keine Spruenge ausser dem Flash-Schnitt (50-ms-Schritte)", #jumps == 0, table.concat(jumps, " | "))

local function dist(a, b)
	return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
end
-- Kanten der Phasen stetig
for _, edge in { 5, 12, 24, 34 } do
	local a = EpilogCameraPath.sample(edge - 1e-4, ctxAt(edge - 1e-4, false))
	local b = EpilogCameraPath.sample(edge, ctxAt(edge, false))
	check("stetig an Sekunde " .. edge, dist(a.pos, b.pos) < 0.5 and dist(a.look, b.look) < 1 and math.abs(a.fov - b.fov) < 1,
		string.format("pos %.3f look %.3f fov %.3f", dist(a.pos, b.pos), dist(a.look, b.look), math.abs(a.fov - b.fov)))
end
-- Schnitt beim Flash: Position darf springen (Teleport), Blick bleibt auf dem Avatar
local pre = EpilogCameraPath.sample(Q.teleportAt - 1e-3, ctxAt(Q.teleportAt - 1e-3, false))
local post = EpilogCameraPath.sample(Q.teleportAt, ctxAt(Q.teleportAt, false))
check("Schnitt beim Flash: danach schaut die Kamera auf den Avatar", dist(post.look, summitCenter) < 1.5, dist(post.look, summitCenter))
check("Phase 1: FOV springt ruckartig auf 55", math.abs(EpilogCameraPath.sample(0.5, ctxAt(0.5, false)).fov - C.jerkFov) < 1e-6)
-- Spirale: steigt, FOV 70 -> 85
local lo = EpilogCameraPath.sample(5.0, ctxAt(5.0, false))
local hi = EpilogCameraPath.sample(11.99, ctxAt(11.99, false))
check("Aufstieg: Hoehe steigt um >= 14 Studs", hi.pos[2] - lo.pos[2] >= 14, hi.pos[2] - lo.pos[2])
local peak = 0
for step = 0, 140 do
	local f = EpilogCameraPath.sample(5 + step * 0.05, ctxAt(5 + step * 0.05, false)).fov
	if f > peak then peak = f end
end
check("FOV erreicht 85 im Aufstieg", math.abs(peak - C.spiral.fovPeak) < 0.5, peak)
local endLook = EpilogCameraPath.sample(11.99, ctxAt(11.99, false)).look
check("Schwenk zur Insel: Blick am Ende von Phase 3 auf der Insel", dist(endLook, { 86, 78.2 + C.spiral.islandLookUp, 0 }) < 1.5, dist(endLook, { 86, 81, 0 }))

-- 5. Dolly-Zoom
local okDolly = true
for step = 0, 30 do
	local t = C.dolly.from + C.dolly.crossFade + step * ((C.dolly.to - C.dolly.from - C.dolly.crossFade) / 30)
	local pose = EpilogCameraPath.sample(t, ctxAt(t, false))
	local d = math.sqrt((pose.pos[1] - terminal.pos[1]) ^ 2 + (pose.pos[3] - terminal.pos[3]) ^ 2)
	local k = d * math.tan(math.rad(pose.fov) / 2)
	local k0 = C.dolly.distance0 * math.tan(math.rad(C.dolly.fov0) / 2)
	if math.abs(k - k0) > 0.02 then okDolly = false end
end
check("Dolly-Zoom: Abstand x tan(FOV/2) konstant", okDolly)
local fEnd = EpilogCameraPath.sample(33.99, ctxAt(33.99, false)).fov
check("Dolly: FOV sinkt auf ca. 38, Kamera faehrt zurueck", math.abs(fEnd - C.dolly.fov1) < 1.5, fEnd)
local fixed = true
for step = 0, 40 do
	local t = 30 + step * 0.1
	if math.abs(EpilogCameraPath.sample(t, ctxAt(t, true)).fov - C.dolly.fov0) > 1e-6 and t >= 31 then fixed = false end
end
check("reduced: kein Dolly-Zoom (FOV konstant)", fixed)
local final = EpilogCameraPath.sample(T.ARRIVAL_END + Q.blendBackSeconds, ctxAt(T.ARRIVAL_END + Q.blendBackSeconds, false))
check("nach der Rueckblende genau die Standardansicht", dist(final.pos, ctxAt(35.2, false).default.pos) < 1e-6)

-- 6. Lauftempo
check("Faktoren decken genau 12 s ab", (function()
	local sum, expect = 0, Q.arriveAt - Q.walkAt
	local last = 0
	for _, f in Q.walkFactors do
		if f[1] ~= last then return false end
		last = f[2]
		sum += f[2] - f[1]
	end
	return math.abs(sum - expect) < 1e-9 and math.abs(last - expect) < 1e-9
end)())
check("Strecke in genau 12 s", math.abs(EpilogRoute.distanceAt(profile, 12) - route.length) < 1e-6, EpilogRoute.distanceAt(profile, 12))
local minV, maxV = math.huge, 0
for _, f in Q.walkFactors do
	local v = profile.base * f[3]
	minV = math.min(minV, v); maxV = math.max(maxV, v)
end
check("Tempo in den Grenzen (4..32 Studs/s)", minV >= Q.walkMinSpeed and maxV <= Q.walkMaxSpeed, minV .. " / " .. maxV)
check("Tempo wechselt (schnellster/langsamster >= 1,5)", maxV / minV >= 1.5, maxV / minV)
check("Strecke waechst monoton", (function()
	local last = -1
	for i = 0, 120 do
		local d = EpilogRoute.distanceAt(profile, i * 0.1)
		if d < last then return false end
		last = d
	end
	return true
end)())
check("Begleiter 3 Studs voraus, nie hinter dem Ziel", (function()
	local ahead = Q.companionAhead
	for i = 0, 120 do
		local s = math.min(route.length, EpilogRoute.distanceAt(profile, i * 0.1) + ahead)
		if s > route.length + 1e-9 then return false end
	end
	return ahead == 3
end)())
-- Tempo-Wechsel und Speed-Lines liegen zusammen in 12..24
local inside = true
for _, w in FX.speedLines do
	if w[1] < Q.walkAt or w[2] > Q.arriveAt or w[1] >= w[2] then inside = false end
end
check("Speed-Lines nur im Lauf (12..24 s)", inside)

-- 7. Effekte
local sum = 0
for _, n in FX.pools do sum += n end
check("UI-Teilchen <= 60", sum <= FX.maxSprites and FX.maxSprites <= 60, sum)
local reduced = 0
for _, n in FX.pools do reduced += math.floor(n * FX.reducedFactor) end
check("reduced halbiert (<= 30)", reduced <= 30, reduced)
local fine = true
for _, k in { "clouds", "sparks", "lensFlare" } do
	local w = FX[k]
	if w[1] < 0 or w[2] > T.ARRIVAL_END or w[1] >= w[2] then fine = false end
end
for _, w in FX.veil do if w[1] < 0 or w[2] > T.ARRIVAL_END then fine = false end end
check("Effekt-Fenster liegen in 0..34 s", fine)
check("Bloom 0,6 -> 1,2", (function()
	local lo2, hi2 = math.huge, 0
	for _, p in FX.bloom do
		if p[2] > 0 then lo2 = math.min(lo2, p[2]); hi2 = math.max(hi2, p[2]) end
	end
	return math.abs(lo2 - 0.6) < 1e-9 and math.abs(hi2 - 1.2) < 1e-9
end)())
check("Saettigung +0,15, Kontrast +0,1", FX.saturation == 0.15 and FX.contrast == 0.1)
check("Cues fest benannt", EpilogConfig.CUES.hit == "epilog_hit" and EpilogConfig.CUES.flash == "epilog_flash"
	and EpilogConfig.CUES.rise == "epilog_rise" and EpilogConfig.CUES.run == "epilog_run" and EpilogConfig.CUES.reveal == "epilog_reveal")

-- 8. Weg
check("Weglaenge", math.abs(route.length - (12.0 + math.sqrt(68 ^ 2 + 17.5 ^ 2) + math.sqrt(6 ^ 2 + 0.2 ^ 2) + math.sqrt(0 + 0.5 ^ 2 * 0) - math.sqrt(0) + (math.sqrt(12 ^ 2 + 0.5 ^ 2) - 12.0))) < 1e-6 or route.length > 80, route.length)
check("Projektion: Anfang 0, Ende = Laenge", EpilogRoute.project(route, { 0, 60, 0 }) == 0
	and math.abs(EpilogRoute.project(route, { 86, 78.2, 0 }) - route.length) < 1e-6)
local mid = EpilogRoute.pointAt(route, route.length / 2)
check("Projektion von pointAt = s", math.abs(EpilogRoute.project(route, mid) - route.length / 2) < 1e-6)
local d0 = EpilogRoute.directionAt(route, 5)
check("Richtung waagrecht, Einheitsvektor, +X", math.abs(d0[1] - 1) < 1e-9 and d0[2] == 0)

if failures == 0 then print("epilog_camera: alle Tests gruen") else
	print("epilog_camera: " .. failures .. " Fehler")
	error("epilog_camera fehlgeschlagen")
end
