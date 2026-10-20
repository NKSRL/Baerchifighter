--!strict
-- EpilogCameraPath.luau
-- ReplicatedStorage/Modules/EpilogCameraPath.luau
--
-- Einzige Zustaendigkeit (Prompt 5, Final-Epilog):
--   - Der Kameraweg der 34-Sekunden-Sequenz als REINE Funktion: Sequenzzeit +
--     Bezugspunkte (Avatar, Gipfel, Weg, Insel, Terminal) -> Kameralage, Blickziel,
--     FOV und Phase. Kein Zufall, keine Roblox-Typen (Zahlen-Tabellen {x, y, z}),
--     deshalb ohne Studio testbar; der EpilogController setzt nur noch das Ergebnis.
--
-- Zeitlupe: `warp` bildet die reale Zeit auf die Kamerazeit ab (Hit-Freeze, 0,4x, 0,5x
-- beim Insel-Reveal, danach Aufholen). Alles andere (Effekte, Server) laeuft in realer
-- Zeit; die Kamera trifft bei 2 s und 12 s wieder genau die reale Zeit.
--
-- Masse und Keyframes stehen in Config/EpilogConfig.CAMERA / .TIME_WARP / .SEQUENCE.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EpilogConfig = require(ReplicatedStorage.Config.EpilogConfig)
local EpilogRoute  = require(ReplicatedStorage.Modules.EpilogRoute)

local EpilogCameraPath = {}

export type V3 = { number }

export type Pose = { pos : V3, look : V3, fov : number }

export type Context = {
	cam0     : V3,        -- Kamera beim Start (Phase 1 geht von hier aus)
	fov0     : number,
	summit   : { center : V3, dir : V3 },        -- Avatar-Mitte nach dem Teleport, Bruecken-Richtung (waagrecht, Einheitsvektor)
	route    : EpilogRoute.Route,                -- Weg Gipfel -> Insel (Fusspunkte)
	avatar   : V3,        -- Avatar jetzt (Wurzel)
	progress : number,    -- Bogenlaenge des Avatars auf dem Weg
	island   : { center : V3 },                  -- Mitte der Wiesenoberkante
	terminal : { pos : V3, look : V3 },          -- Fusspunkt und Blickziel (zur Bruecke hin)
	default  : Pose,      -- Standardansicht, in die am Ende geblendet wird
	reduced  : boolean,   -- "reduced": kein Dolly-Zoom
}

--------------------------------------------------------------------------------
-- Kleine Vektor- und Easing-Helfer
--------------------------------------------------------------------------------

local function lerp(a: number, b: number, t: number): number return a + (b - a) * t end
local function lerpV(a: V3, b: V3, t: number): V3
	return { lerp(a[1], b[1], t), lerp(a[2], b[2], t), lerp(a[3], b[3], t) }
end
local function add(a: V3, b: V3): V3 return { a[1] + b[1], a[2] + b[2], a[3] + b[3] } end
local function scale(a: V3, k: number): V3 return { a[1] * k, a[2] * k, a[3] * k } end
local function sub(a: V3, b: V3): V3 return { a[1] - b[1], a[2] - b[2], a[3] - b[3] } end
local function unit(a: V3): V3
	local l = math.sqrt(a[1] * a[1] + a[2] * a[2] + a[3] * a[3])
	if l < 1e-9 then return { 0, 0, 1 } end
	return { a[1] / l, a[2] / l, a[3] / l }
end

local function clamp01(t: number): number return math.clamp(t, 0, 1) end
local function easeSine(t: number): number return 0.5 - 0.5 * math.cos(math.pi * clamp01(t)) end
local function easeOutQuad(t: number): number
	local u = clamp01(t)
	return 1 - (1 - u) * (1 - u)
end
local function easeInOutQuad(t: number): number
	local u = clamp01(t)
	return if u < 0.5 then 2 * u * u else 1 - 2 * (1 - u) * (1 - u)
end
EpilogCameraPath.easeSine = easeSine
EpilogCameraPath.easeOutQuad = easeOutQuad

local function blend(a: Pose, b: Pose, w: number): Pose
	return { pos = lerpV(a.pos, b.pos, w), look = lerpV(a.look, b.look, w), fov = lerp(a.fov, b.fov, w) }
end
EpilogCameraPath.blend = blend

local UP: V3 = { 0, 1, 0 }

--------------------------------------------------------------------------------
-- Zeit
--------------------------------------------------------------------------------

-- Phase der realen Sequenzzeit: 1 Sieg, 2 Flash+Gipfel, 3 Aufstieg, 4 Lauf, 5 Ankunft, 6 danach.
function EpilogCameraPath.phaseAt(t: number): number
	local T = EpilogConfig.TIMELINE
	if t < T.VICTORY_END then return 1 end
	if t < T.TELEPORT_END then return 2 end
	if t < T.REVEAL_END then return 3 end
	if t < T.BRIDGE_END then return 4 end
	if t < T.ARRIVAL_END then return 5 end
	return 6
end

-- Reale Zeit -> Kamerazeit (stueckweise linear, monoton nicht fallend).
function EpilogCameraPath.warp(t: number): number
	local pts = EpilogConfig.TIME_WARP
	if t <= pts[1][1] then return pts[1][2] end
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		if t <= b[1] then
			local span = b[1] - a[1]
			local w = if span > 1e-9 then (t - a[1]) / span else 1
			return lerp(a[2], b[2], w)
		end
	end
	local last = pts[#pts]
	return last[2] + (t - last[1])   -- danach 1:1
end

--------------------------------------------------------------------------------
-- Phasen
--------------------------------------------------------------------------------

local function phase1(c: number, t: number, ctx: Context): Pose
	local C = EpilogConfig.CAMERA
	local head = add(ctx.avatar, { 0, C.headHeight, 0 })
	local push = C.pushFraction * easeInOutQuad(c / EpilogConfig.TIMELINE.VICTORY_END)
	local pos = lerpV(ctx.cam0, head, push)
	-- Der Zoom-Ruck laeuft in REALER Zeit (nach dem Freeze), nicht in der Zeitlupe.
	local fov = ctx.fov0
	if t >= C.jerkAt then
		fov = lerp(ctx.fov0, C.jerkFov, easeOutQuad((t - C.jerkAt) / C.jerkSeconds))
	end
	return { pos = pos, look = add(head, { 0, 0.4, 0 }), fov = fov }
end

local function avatarLook(ctx: Context): V3
	return add(ctx.summit.center, { 0, EpilogConfig.CAMERA.start.lookUp, 0 })
end

local function phase2(c: number, ctx: Context): Pose
	local S = EpilogConfig.CAMERA.start
	local cut = EpilogConfig.SEQUENCE.teleportAt
	local u = clamp01((c - cut) / (EpilogConfig.SEQUENCE.bridgeAt - cut))
	local e = easeSine(u)
	local front = lerp(S.front0, S.front1, e)
	local height = lerp(S.height0, S.height1, e)
	local pos = add(add(ctx.summit.center, scale(ctx.summit.dir, front)), scale(UP, height))
	return { pos = pos, look = avatarLook(ctx), fov = lerp(S.fov0, S.fov1, e) }
end

local function islandLook(ctx: Context): V3
	return add(ctx.island.center, { 0, EpilogConfig.CAMERA.spiral.islandLookUp, 0 })
end

local function phase3(c: number, ctx: Context): Pose
	local S = EpilogConfig.CAMERA.spiral
	local T = EpilogConfig.TIMELINE
	local u = clamp01((c - EpilogConfig.SEQUENCE.bridgeAt) / (T.REVEAL_END - EpilogConfig.SEQUENCE.bridgeAt))
	local e = easeSine(u)
	local theta0 = math.atan2(ctx.summit.dir[3], ctx.summit.dir[1])
	local theta = theta0 + e * S.turns * 2 * math.pi
	local radius = lerp(S.radius0, S.radius1, e)
	local height = lerp(S.height0, S.height1, e)
	local c0 = ctx.summit.center
	local pos = { c0[1] + math.cos(theta) * radius, c0[2] + height, c0[3] + math.sin(theta) * radius }
	local pan = easeSine((c - S.panFrom) / (S.panTo - S.panFrom))
	local look = lerpV(avatarLook(ctx), islandLook(ctx), pan)
	local fov: number
	if c <= S.fovPeakAt then
		fov = lerp(S.fov0, S.fovPeak, easeSine((c - EpilogConfig.SEQUENCE.bridgeAt) / (S.fovPeakAt - EpilogConfig.SEQUENCE.bridgeAt)))
	else
		fov = lerp(S.fovPeak, S.fov1, easeSine((c - S.fovPeakAt) / (T.REVEAL_END - S.fovPeakAt)))
	end
	return { pos = pos, look = look, fov = fov }
end

-- Phase 4: Keyframes relativ zum Avatar (hinter/seitlich/ueber ihm), weich ueberblendet.
local function phase4(c: number, ctx: Context): Pose
	local C = EpilogConfig.CAMERA
	local keys = C.follow
	local fwd = EpilogRoute.directionAt(ctx.route, ctx.progress)
	local side: V3 = { -fwd[3], 0, fwd[1] }
	local a, b = keys[1], keys[#keys]
	local w = 0
	if c >= keys[#keys].t then
		a, b, w = keys[#keys], keys[#keys], 0
	else
		for i = 2, #keys do
			if c <= keys[i].t then
				a, b = keys[i - 1], keys[i]
				w = easeSine((c - a.t) / math.max(b.t - a.t, 1e-6))
				break
			end
		end
	end
	local back = lerp(a.back, b.back, w)
	local sideOff = lerp(a.side, b.side, w)
	local up = lerp(a.up, b.up, w)
	local ahead = lerp(a.ahead, b.ahead, w)
	local lookUp = lerp(a.look, b.look, w)
	local fov = lerp(a.fov, b.fov, w)
	local av = ctx.avatar
	local pos = add(add(add(av, scale(fwd, -back)), scale(side, sideOff)), scale(UP, up))
	local lookAhead = add(add(av, scale(fwd, ahead)), scale(UP, lookUp))
	-- Der Blick gleitet in den ersten Sekunden von der Insel (Ende Phase 3) zum Weg voraus.
	local follow = easeSine((c - keys[1].t) / EpilogConfig.CAMERA.spiral.followBlend)
	return { pos = pos, look = lerpV(islandLook(ctx), lookAhead, follow), fov = fov }
end

local function orbitPose(t: number, ctx: Context): Pose
	local O = EpilogConfig.CAMERA.orbit
	local u = clamp01((t - O.from) / (O.to - O.from))
	local e = easeSine(u)
	local theta0 = math.atan2(-ctx.summit.dir[3], -ctx.summit.dir[1])   -- Bruecken-Seite der Insel
	local theta = theta0 + math.rad(O.sweepDeg) * e
	local radius = lerp(O.radius0, O.radius1, e)
	local height = lerp(O.height0, O.height1, e)
	local c0 = ctx.island.center
	return {
		pos = { c0[1] + math.cos(theta) * radius, c0[2] + height, c0[3] + math.sin(theta) * radius },
		look = add(c0, { 0, O.lookUp, 0 }),
		fov = 70,
	}
end

-- Dolly-Zoom: FOV sinkt, die Kamera faehrt zurueck, das Terminal bleibt gleich gross
-- (Abstand * tan(FOV/2) = const). "reduced": FOV bleibt, die Kamera ruecken nur sanft heran.
local function dollyPose(t: number, ctx: Context): Pose
	local D = EpilogConfig.CAMERA.dolly
	local u = clamp01((t - D.from) / (D.to - D.from))
	local e = easeSine(u)
	local fov, dist
	if ctx.reduced then
		fov = D.fov0
		dist = D.distance0 * (1 - 0.1 * e)
	else
		fov = lerp(D.fov0, D.fov1, e)
		local k = D.distance0 * math.tan(math.rad(D.fov0) / 2)
		dist = k / math.tan(math.rad(fov) / 2)
	end
	local front = unit({ ctx.terminal.look[1] - ctx.terminal.pos[1], 0, ctx.terminal.look[3] - ctx.terminal.pos[3] })
	local target = add(ctx.terminal.pos, { 0, D.targetUp, 0 })
	local pos = add(add(ctx.terminal.pos, scale(front, dist)), { 0, D.height, 0 })
	return { pos = pos, look = target, fov = fov }
end

local function phase5(t: number, ctx: Context): Pose
	local O = EpilogConfig.CAMERA.orbit
	local D = EpilogConfig.CAMERA.dolly
	-- Anfang: weich aus dem Ende von Phase 4 (Kamera hinter dem Avatar)
	local from = phase4(EpilogConfig.TIMELINE.BRIDGE_END, ctx)
	local pose: Pose
	if t < D.from then
		pose = orbitPose(t, ctx)
	else
		local orbitEnd = orbitPose(D.from, ctx)
		pose = blend(orbitEnd, dollyPose(t, ctx), easeSine((t - D.from) / D.crossFade))
	end
	local w = easeSine((t - O.from) / O.crossFade)
	if w < 1 then pose = blend(from, pose, w) end
	return pose
end

--------------------------------------------------------------------------------
-- Gesamtweg
--------------------------------------------------------------------------------

-- Kameralage zur realen Sequenzzeit t (Sekunden). Nach endAt wird in die Standard-
-- ansicht geblendet (blendBackSeconds); danach liefert die Funktion `default`.
function EpilogCameraPath.sample(t: number, ctx: Context): (Pose, number)
	local Q = EpilogConfig.SEQUENCE
	local T = EpilogConfig.TIMELINE
	local phase = EpilogCameraPath.phaseAt(t)
	local c = EpilogCameraPath.warp(t)
	local pose: Pose
	if phase == 1 or (phase == 2 and t < Q.teleportAt) then
		pose = phase1(math.min(c, T.VICTORY_END), math.min(t, T.VICTORY_END), ctx)
	elseif phase == 2 then
		pose = phase2(c, ctx)
	elseif phase == 3 then
		pose = phase3(c, ctx)
	elseif phase == 4 then
		pose = phase4(c, ctx)
	else
		pose = phase5(math.min(t, T.ARRIVAL_END), ctx)
		if t > T.ARRIVAL_END then
			local w = easeSine((t - T.ARRIVAL_END) / Q.blendBackSeconds)
			pose = blend(pose, ctx.default, w)
		end
	end
	return pose, phase
end

return EpilogCameraPath
