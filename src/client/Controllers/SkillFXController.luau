--!strict
-- SkillFXController.luau
-- StarterPlayerScripts/Controllers/SkillFXController.luau
--
-- v14 (Mega Egg Tree, WP8): der SkillFX-Baukasten.
--
-- Spielt die Show einer Faehigkeit ab, wenn der Server sie im PIT meldet
-- (Remotes.SkillFXPlay, gefeuert von PitArenaService). WAS gezeigt wird,
-- steht als reine Daten in Config/SkillFXConfig — hier stehen nur die
-- Bausteine (aura, ring, pillar, ...) und der Ablauf.
--
-- Alles hier ist rein CLIENTSEITIG: die Teile entstehen nur auf diesem
-- Rechner, beruehren keine Physik und verschwinden nach ihrer Dauer selbst.
-- Der Server wartet waehrend der vollen Show einfach (SkillFXConfig.getDuration),
-- damit Kampf und Show zusammenpassen.
--
-- WER sieht was:
--   * Besitzer: alles — Welt-Effekte, Farbfilter, Blitz, Wackeln, Kamerafahrt.
--   * Andere Spieler in der Naehe: nur die Effekte in der Welt. Ihr Bild und
--     ihre Kamera gehoeren ihnen.
--
-- Partikel-Budget: alle Stueckzahlen werden mit dem Faktor der Grafikstufe
-- multipliziert (SkillFXConfig.PARTICLE_BUDGET), damit Handys nicht ruckeln.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local Lighting          = game:GetService("Lighting")
local Debris            = game:GetService("Debris")

local Remotes       = require(ReplicatedStorage.Network.Remotes)
local SkillFXConfig = require(ReplicatedStorage.Config.SkillFXConfig)

local SkillFXController = {}

local player = Players.LocalPlayer

-- Wie weit weg ein Zuschauer noch Effekte sieht (Studs).
local SPECTATOR_DISTANCE = 260

local _folder: Folder? = nil

local function folder(): Folder
	if _folder and _folder.Parent then
		return _folder
	end
	local f = Instance.new("Folder")
	f.Name = "SkillFXLocal"
	f.Parent = workspace
	_folder = f
	return f
end

--------------------------------------------------------------------------------
-- Budget
--------------------------------------------------------------------------------

local function budgetFactor(): number
	local ok, level = pcall(function()
		local settingsObj = UserSettings():GetService("UserGameSettings")
		return (settingsObj :: any).SavedQualityLevel
	end)
	local b = SkillFXConfig.PARTICLE_BUDGET
	if not ok or level == nil or level == Enum.SavedQualitySetting.Automatic then
		return b.medium
	end
	local n = tonumber(string.match(tostring(level), "(%d+)$")) or 5
	if n <= 3 then return b.low end
	if n <= 6 then return b.medium end
	return b.high
end

local function scaled(count: number?, factor: number): number
	return math.max(SkillFXConfig.PARTICLE_BUDGET.MIN_COUNT, math.floor((count or 6) * factor + 0.5))
end

--------------------------------------------------------------------------------
-- Kleine Werkzeuge
--------------------------------------------------------------------------------

local function newPart(shape: Enum.PartType?, size: Vector3, color: Color3, cf: CFrame, transparency: number?): Part
	local p = Instance.new("Part")
	p.Shape        = shape or Enum.PartType.Block
	p.Size         = size
	p.Color        = color
	p.Material     = Enum.Material.Neon
	p.Anchored     = true
	p.CanCollide   = false
	p.CanQuery     = false
	p.CanTouch     = false
	p.CastShadow   = false
	p.CFrame       = cf
	p.Transparency = transparency or 0
	p.Parent       = folder()
	return p
end

local function tween(inst: Instance, seconds: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local t = TweenService:Create(inst, TweenInfo.new(math.max(0.01, seconds), style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function fadeAndDestroy(p: BasePart, seconds: number, extra: { [string]: any }?)
	local props: { [string]: any } = { Transparency = 1 }
	if extra then
		for k, v in extra do props[k] = v end
	end
	tween(p, seconds, props)
	Debris:AddItem(p, seconds + 0.1)
end

local function centerOf(model: Model?): Vector3?
	if not model or not model.Parent then return nil end
	local ok, cf = pcall(function()
		return (model :: Model):GetBoundingBox()
	end)
	if not ok or typeof(cf) ~= "CFrame" then return nil end
	return (cf :: CFrame).Position
end

local RAINBOW = {
	Color3.fromRGB(255, 60, 60), Color3.fromRGB(255, 160, 40), Color3.fromRGB(255, 240, 60),
	Color3.fromRGB(80, 230, 90), Color3.fromRGB(60, 180, 255), Color3.fromRGB(150, 90, 255),
}

local function pickColor(step: { [string]: any }, fx: SkillFXConfig.SkillFX, i: number?): Color3
	if step.rainbow then
		return RAINBOW[((i or 1) - 1) % #RAINBOW + 1]
	end
	if step.dark then
		return fx.color2
	end
	if i and i % 2 == 0 then
		return fx.color2
	end
	return fx.color
end

--------------------------------------------------------------------------------
-- Kontext einer Show
--------------------------------------------------------------------------------

type Ctx = {
	fx       : SkillFXConfig.SkillFX,
	selfPos  : Vector3,
	targetPos: Vector3,
	arena    : Vector3,
	isOwner  : boolean,
	factor   : number,
	cc       : ColorCorrectionEffect?,
	sounds   : { [string]: boolean },
}

local function at(ctx: Ctx, where: string?): Vector3
	if where == "target" then return ctx.targetPos end
	if where == "arena" then return ctx.arena end
	return ctx.selfPos
end

--------------------------------------------------------------------------------
-- Bausteine
--------------------------------------------------------------------------------

local BLOCKS: { [string]: (Ctx, { [string]: any }) -> () } = {}

BLOCKS.aura = function(ctx, s)
	local pos = at(ctx, s.at)
	local size = s.size or 4
	local dur = s.dur or 0.6
	local ball = newPart(Enum.PartType.Ball, Vector3.one * size * 0.4, pickColor(s, ctx.fx), CFrame.new(pos), 0.35)
	local light = Instance.new("PointLight")
	light.Color = ball.Color
	light.Range = size * 3
	light.Brightness = 3
	light.Parent = ball
	tween(ball, dur * 0.5, { Size = Vector3.one * size }, Enum.EasingStyle.Back)
	if s.rainbow then
		task.spawn(function()
			local t0 = os.clock()
			while ball.Parent and os.clock() - t0 < dur do
				ball.Color = Color3.fromHSV(((os.clock() - t0) * 1.5) % 1, 0.8, 1)
				light.Color = ball.Color
				task.wait(0.05)
			end
		end)
	end
	task.delay(dur * 0.5, function()
		if ball.Parent then fadeAndDestroy(ball, dur * 0.5, { Size = Vector3.one * size * 1.3 }) end
	end)
end

BLOCKS.ring = function(ctx, s)
	local pos = at(ctx, s.at) - Vector3.new(0, 1.2, 0)
	local r = s.radius or 6
	local dur = s.dur or 0.6
	local startD = if s.shrink then r * 2 else 0.5
	local endD   = if s.shrink then 0.5 else r * 2
	local ring = newPart(Enum.PartType.Cylinder, Vector3.new(0.25, startD, startD), pickColor(s, ctx.fx),
		CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), 0.2)
	if s.rainbow or s.glyphs or s.infinity or s.clock then
		task.spawn(function()
			local t0 = os.clock()
			while ring.Parent and os.clock() - t0 < dur do
				local k = os.clock() - t0
				if s.rainbow then ring.Color = Color3.fromHSV((k * 1.2) % 1, 0.8, 1) end
				ring.CFrame = CFrame.new(pos) * CFrame.Angles(0, k * (if s.clock then -6 else 4), math.rad(90))
				task.wait(0.03)
			end
		end)
	end
	tween(ring, dur, { Size = Vector3.new(0.25, endD, endD) })
	task.delay(dur * 0.6, function()
		if ring.Parent then fadeAndDestroy(ring, dur * 0.4) end
	end)
end

BLOCKS.pillar = function(ctx, s)
	local pos = at(ctx, s.at)
	local h = s.height or 16
	local w = s.width or 3
	local dur = s.dur or 0.8
	local base = pos - Vector3.new(0, 1.5, 0)
	local startCf = if s.fromSky
		then CFrame.new(base + Vector3.new(0, h * 1.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
		else CFrame.new(base) * CFrame.Angles(0, 0, math.rad(90))
	local col = newPart(Enum.PartType.Cylinder, Vector3.new(0.2, w, w), pickColor(s, ctx.fx), startCf, 0.15)
	tween(col, dur * 0.35, {
		Size = Vector3.new(h, w, w),
		CFrame = CFrame.new(base + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
	}, Enum.EasingStyle.Quart)
	if s.beacon then
		task.spawn(function()
			local t0 = os.clock()
			while col.Parent and os.clock() - t0 < dur do
				col.Transparency = 0.15 + 0.5 * (0.5 + 0.5 * math.sin((os.clock() - t0) * 12))
				task.wait(0.03)
			end
		end)
	end
	task.delay(dur * 0.6, function()
		if col.Parent then fadeAndDestroy(col, dur * 0.4, { Size = Vector3.new(h, w * 0.2, w * 0.2) }) end
	end)
end

local function shootOne(ctx: Ctx, s: { [string]: any }, delaySeconds: number, offset: Vector3)
	task.delay(delaySeconds, function()
		local from = ctx.selfPos + Vector3.new(0, 0.5, 0) + offset
		local to = ctx.targetPos + Vector3.new(0, 0.5, 0)
		local size = s.size or 1
		local ball = newPart(Enum.PartType.Ball, Vector3.one * size, pickColor(s, ctx.fx), CFrame.new(from), 0)
		local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, size * 0.3, 0); a0.Parent = ball
		local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -size * 0.3, 0); a1.Parent = ball
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Color = ColorSequence.new(ball.Color, ctx.fx.color2)
		trail.Lifetime = 0.25
		trail.LightEmission = 1
		trail.Transparency = NumberSequence.new(0, 1)
		trail.Parent = ball
		if s.flame then
			local fire = Instance.new("Fire")
			fire.Size = size * 2
			fire.Color = ctx.fx.color
			fire.SecondaryColor = ctx.fx.color2
			fire.Parent = ball
		end
		local dur = s.dur or 0.3
		tween(ball, dur, { CFrame = CFrame.new(to) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		task.delay(dur, function()
			if ball.Parent then fadeAndDestroy(ball, 0.15, { Size = Vector3.one * size * 2.5 }) end
		end)
	end)
end

BLOCKS.projectile = function(ctx, s)
	local n = s.count or 1
	for i = 1, n do
		local off = if n > 1 then Vector3.new(0, (i - (n + 1) / 2) * 0.9, 0) else Vector3.zero
		shootOne(ctx, s, (i - 1) * 0.07, off)
	end
end

BLOCKS.meteor = function(ctx, s)
	local to = at(ctx, s.at or "target")
	local h = s.height or 20
	local size = s.size or 2
	local dur = s.dur or 0.5
	local from = to + Vector3.new(h * 0.35, h, -h * 0.2)
	local rock = newPart(Enum.PartType.Ball, Vector3.one * size, pickColor(s, ctx.fx), CFrame.new(from), 0)
	if s.fist then
		rock.Shape = Enum.PartType.Block
		rock.Size = Vector3.new(size, size * 1.2, size * 0.9)
		rock.Material = Enum.Material.Slate
	end
	if s.tail or s.fist then
		local fire = Instance.new("Fire")
		fire.Size = size * 3
		fire.Heat = 25
		fire.Color = ctx.fx.color
		fire.SecondaryColor = ctx.fx.color2
		fire.Parent = rock
	end
	local light = Instance.new("PointLight")
	light.Range = size * 6
	light.Brightness = 4
	light.Color = rock.Color
	light.Parent = rock
	tween(rock, dur, { CFrame = CFrame.new(to) }, if s.slow then Enum.EasingStyle.Sine else Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(dur, function()
		if rock.Parent then fadeAndDestroy(rock, if s.dark then 1.2 else 0.25, { Size = rock.Size * 1.6 }) end
	end)
end

BLOCKS.beam = function(ctx, s)
	local from = ctx.selfPos + Vector3.new(0, 0.5, 0)
	local to = ctx.targetPos + Vector3.new(0, 0.5, 0)
	if s.curtain then
		from = ctx.selfPos + Vector3.new(-6, 9, 0)
		to = ctx.targetPos + Vector3.new(6, 9, 0)
	end
	local dist = (to - from).Magnitude
	local w = s.width or 1
	local dur = s.dur or 0.6
	local mid = (from + to) / 2
	local cf = CFrame.lookAt(mid, to)
	if s.cross then
		cf = cf * CFrame.Angles(0, 0, math.rad(90))
	end
	local beam = newPart(Enum.PartType.Block, Vector3.new(w * 0.2, w * 0.2, 0.2), pickColor(s, ctx.fx), cf, 0.05)
	if s.slash or s.rift then
		beam.Color = if s.rift then Color3.new(0, 0, 0) else ctx.fx.color2
		beam.Size = Vector3.new(w, 0.1, 0.1)
		beam.CFrame = CFrame.lookAt(ctx.targetPos, ctx.targetPos + Vector3.new(0, 1, 0.001)) * CFrame.Angles(0, 0, if s.cross then math.rad(-35) else math.rad(35))
		tween(beam, dur * 0.4, { Size = Vector3.new(w, 9, 0.1) }, Enum.EasingStyle.Quart)
	else
		tween(beam, dur * 0.3, { Size = Vector3.new(w, if s.curtain then w * 3 else w, dist) }, Enum.EasingStyle.Quart)
	end
	if s.rainbow or s.curtain then
		task.spawn(function()
			local t0 = os.clock()
			while beam.Parent and os.clock() - t0 < dur do
				beam.Color = Color3.fromHSV(((os.clock() - t0) * (if s.curtain then 0.4 else 1.5) + 0.35) % 1, 0.7, 1)
				task.wait(0.04)
			end
		end)
	end
	task.delay(dur * 0.65, function()
		if beam.Parent then fadeAndDestroy(beam, dur * 0.35) end
	end)
end

BLOCKS.wave = function(ctx, s)
	local pos = at(ctx, s.at)
	local r = s.radius or 10
	local dur = s.dur or 0.6
	local ball = newPart(Enum.PartType.Ball, Vector3.one, pickColor(s, ctx.fx), CFrame.new(pos), 0.3)
	ball.Material = if s.cloud then Enum.Material.SmoothPlastic else Enum.Material.ForceField
	tween(ball, dur, { Size = Vector3.one * r * 2, Transparency = 1 }, Enum.EasingStyle.Quart)
	Debris:AddItem(ball, dur + 0.1)
end

BLOCKS.shards = function(ctx, s)
	local pos = at(ctx, s.at)
	local n = scaled(s.count, ctx.factor)
	local size = s.size or 0.6
	local dur = s.dur or 0.6
	for i = 1, n do
		local dir = Vector3.new(math.random() - 0.5, math.random() * 0.8 + 0.1, math.random() - 0.5).Unit
		local from = if s.inward then pos + dir * 6 else pos
		local to = if s.inward then pos else pos + dir * (5 + math.random() * 6)
		local p = newPart(Enum.PartType.Block, Vector3.new(size, size * 1.6, size * 0.5), pickColor(s, ctx.fx, i),
			CFrame.new(from) * CFrame.Angles(math.random() * 6, math.random() * 6, 0), 0)
		if s.stone then
			p.Material = Enum.Material.Slate
			p.Color = Color3.fromRGB(120, 110, 100):Lerp(ctx.fx.color, 0.25)
		end
		if s.glyphs then
			p.Shape = Enum.PartType.Ball
		end
		tween(p, dur, { CFrame = CFrame.new(to) * CFrame.Angles(math.random() * 6, math.random() * 6, 0) })
		task.delay(dur * 0.5, function()
			if p.Parent then fadeAndDestroy(p, dur * 0.5) end
		end)
	end
end

BLOCKS.sparks = function(ctx, s)
	local pos = at(ctx, s.at)
	local n = scaled(s.count, ctx.factor)
	local dur = s.dur or 0.6
	for i = 1, n do
		local dir = Vector3.new(math.random() - 0.5, math.random() - 0.2, math.random() - 0.5).Unit
		local size = if s.stars then 0.35 else 0.22
		local p = newPart(Enum.PartType.Ball, Vector3.one * size, pickColor(s, ctx.fx, i), CFrame.new(pos), 0)
		local reach = (if s.stars then 14 else 6) * (0.5 + math.random())
		local endPos = pos + dir * reach + (if s.ember then Vector3.new(0, 3, 0) else Vector3.zero)
		tween(p, dur, { CFrame = CFrame.new(endPos), Transparency = 1 }, Enum.EasingStyle.Quad)
		Debris:AddItem(p, dur + 0.1)
	end
end

BLOCKS.bubble = function(ctx, s)
	local pos = at(ctx, s.at)
	local size = s.size or 6
	local dur = s.dur or 1
	local b = newPart(Enum.PartType.Ball, Vector3.one * 0.5, pickColor(s, ctx.fx), CFrame.new(pos), 0.55)
	b.Material = Enum.Material.ForceField
	tween(b, dur * 0.25, { Size = Vector3.one * size }, Enum.EasingStyle.Back)
	if s.hex then
		local inner = newPart(Enum.PartType.Ball, Vector3.one * 0.5, ctx.fx.color2, CFrame.new(pos), 0.8)
		inner.Material = Enum.Material.Glass
		tween(inner, dur * 0.3, { Size = Vector3.one * size * 0.92 })
		task.delay(dur * 0.7, function() if inner.Parent then fadeAndDestroy(inner, dur * 0.3) end end)
	end
	task.delay(dur * 0.7, function()
		if b.Parent then fadeAndDestroy(b, dur * 0.3) end
	end)
end

BLOCKS.rise = function(ctx, s)
	local pos = at(ctx, s.at)
	local n = scaled(s.count, ctx.factor)
	local dur = s.dur or 0.8
	for i = 1, n do
		task.delay((i / n) * dur * 0.5, function()
			local off = Vector3.new((math.random() - 0.5) * 4, -1, (math.random() - 0.5) * 4)
			if s.wings then
				local side = if i % 2 == 0 then 1 else -1
				off = Vector3.new(side * (1 + math.random() * 5), math.random() * 2, (math.random() - 0.5) * 2)
			end
			local p = newPart(Enum.PartType.Ball, Vector3.one * 0.35, pickColor(s, ctx.fx, i), CFrame.new(pos + off), 0)
			local goal = pos + off + Vector3.new(0, 4 + math.random() * 3, 0)
			if s.toSelf then goal = ctx.selfPos + Vector3.new(0, 1, 0) end
			tween(p, dur * 0.6, { CFrame = CFrame.new(goal), Transparency = 1 }, Enum.EasingStyle.Sine)
			Debris:AddItem(p, dur * 0.6 + 0.1)
		end)
	end
end

BLOCKS.spiral = function(ctx, s)
	local center = at(ctx, s.at)
	local n = scaled(s.count, ctx.factor)
	local r = s.radius or 8
	local dur = s.dur or 1
	for i = 1, n do
		local angle = (i / n) * math.pi * 2
		local startR = if s.outward then 0.5 else r
		local endR = if s.outward then r else 0.3
		local size = if s.cloud then 1.4 else (if s.snow then 0.3 else 0.4)
		local p = newPart(Enum.PartType.Ball, Vector3.one * size, pickColor(s, ctx.fx, i),
			CFrame.new(center + Vector3.new(math.cos(angle) * startR, (math.random() - 0.3) * 3, math.sin(angle) * startR)),
			if s.cloud then 0.5 else 0)
		task.spawn(function()
			local t0 = os.clock()
			while p.Parent and os.clock() - t0 < dur do
				local k = (os.clock() - t0) / dur
				local rr = startR + (endR - startR) * k
				local a = angle + k * math.pi * 3
				p.CFrame = CFrame.new(center + Vector3.new(math.cos(a) * rr, (1 - k) * 2, math.sin(a) * rr))
				task.wait(0.03)
			end
			if p.Parent then fadeAndDestroy(p, 0.15) end
		end)
	end
end

BLOCKS.frost = function(ctx, s)
	local pos = at(ctx, s.at)
	local n = scaled(s.count, ctx.factor)
	local dur = s.dur or 0.8
	for i = 1, n do
		local off = Vector3.new((math.random() - 0.5) * 3, (math.random() - 0.3) * 2.5, (math.random() - 0.5) * 3)
		local p = newPart(Enum.PartType.Block, Vector3.new(0.1, 0.1, 0.1), ctx.fx.color,
			CFrame.new(pos + off) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6), 0.1)
		p.Material = Enum.Material.Ice
		tween(p, dur * 0.3, { Size = Vector3.new(0.3, 1.2 + math.random(), 0.3) }, Enum.EasingStyle.Back)
		task.delay(dur * 0.7, function() if p.Parent then fadeAndDestroy(p, dur * 0.3) end end)
	end
end

BLOCKS.starfield = function(ctx, s)
	local center = ctx.arena
	local n = scaled(s.count, ctx.factor)
	local dur = s.dur or 3
	for i = 1, n do
		local a = math.random() * math.pi * 2
		local r = 10 + math.random() * 35
		local pos = center + Vector3.new(math.cos(a) * r, 18 + math.random() * 30, math.sin(a) * r)
		local col = if s.nebula then pickColor({ rainbow = false }, ctx.fx, i) else Color3.new(1, 1, 1)
		local p = newPart(Enum.PartType.Ball, Vector3.one * (0.2 + math.random() * 0.4), col, CFrame.new(pos), 1)
		tween(p, 0.4 + math.random() * 0.6, { Transparency = 0.1 })
		task.delay(dur * 0.75, function() if p.Parent then fadeAndDestroy(p, dur * 0.25) end end)
	end
end

-- Ab hier: nur fuer den Besitzer (Bildschirm und Kamera gehoeren ihm).

local function ensureCC(ctx: Ctx): ColorCorrectionEffect
	if ctx.cc and ctx.cc.Parent then return ctx.cc end
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "SkillFX_Sky"
	cc.Parent = Lighting
	ctx.cc = cc
	return cc
end

BLOCKS.sky = function(ctx, s)
	if not ctx.isOwner then return end
	local cc = ensureCC(ctx)
	local dur = s.dur or 2
	tween(cc, 0.35, {
		TintColor = s.tint or Color3.new(1, 1, 1),
		Brightness = s.brightness or 0,
		Saturation = s.saturation or 0,
	})
	task.delay(math.max(0.4, dur - 0.5), function()
		if cc.Parent then
			tween(cc, 0.5, { TintColor = Color3.new(1, 1, 1), Brightness = 0, Saturation = 0, Contrast = 0 })
		end
	end)
end

BLOCKS.spectrum = function(ctx, s)
	if not ctx.isOwner then return end
	local cc = ensureCC(ctx)
	local dur = s.dur or 1.5
	task.spawn(function()
		local t0 = os.clock()
		while cc.Parent and os.clock() - t0 < dur do
			cc.TintColor = Color3.fromHSV(((os.clock() - t0) / dur) % 1, 0.45, 1)
			cc.Saturation = 0.6
			task.wait(0.03)
		end
		if cc.Parent then
			tween(cc, 0.3, { TintColor = Color3.new(1, 1, 1), Saturation = 0 })
		end
	end)
end

BLOCKS.hitstop = function(ctx, s)
	-- Den Server-Kampf kann der Client nicht anhalten. "Zeitlupe" heisst hier:
	-- Bild entsaettigt, Kontrast hoch, Sichtfeld zieht kurz zusammen.
	local dur = s.dur or 0.3
	if ctx.isOwner then
		local cc = ensureCC(ctx)
		local before = { Saturation = cc.Saturation, Contrast = cc.Contrast }
		cc.Saturation = -0.8
		cc.Contrast = 0.35
		task.delay(dur, function()
			if cc.Parent then tween(cc, 0.25, before) end
		end)
		local cam = workspace.CurrentCamera
		if cam then
			local fov = cam.FieldOfView
			tween(cam, dur * 0.4, { FieldOfView = math.max(30, fov - 12) })
			task.delay(dur, function() tween(cam, 0.3, { FieldOfView = fov }) end)
		end
	end
end

local _flashGui: ScreenGui? = nil
BLOCKS.flash = function(ctx, s)
	if not ctx.isOwner then return end
	local gui = _flashGui
	if not gui or not gui.Parent then
		local g = Instance.new("ScreenGui")
		g.Name = "SkillFXFlash"
		g.IgnoreGuiInset = true
		g.DisplayOrder = 50
		g.ResetOnSpawn = false
		g.Parent = player:WaitForChild("PlayerGui")
		_flashGui = g
		gui = g
	end
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	f.BackgroundTransparency = 0.05
	f.BorderSizePixel = 0
	f.Parent = gui
	tween(f, s.dur or 0.3, { BackgroundTransparency = 1 })
	Debris:AddItem(f, (s.dur or 0.3) + 0.1)
end

local _shakeUntil = 0
local _shakePower = 0
local _shakeBound = false
BLOCKS.shake = function(ctx, s)
	if not ctx.isOwner then return end
	_shakeUntil = math.max(_shakeUntil, os.clock() + (s.dur or 0.3))
	_shakePower = math.max(_shakePower, s.power or 0.5)
	if _shakeBound then return end
	_shakeBound = true
	RunService:BindToRenderStep("SkillFXShake", Enum.RenderPriority.Camera.Value + 1, function()
		local cam = workspace.CurrentCamera
		local left = _shakeUntil - os.clock()
		if left <= 0 or not cam then
			RunService:UnbindFromRenderStep("SkillFXShake")
			_shakeBound = false
			_shakePower = 0
			return
		end
		local p = _shakePower * math.min(1, left * 3) * 0.6
		cam.CFrame = cam.CFrame * CFrame.new((math.random() - 0.5) * p, (math.random() - 0.5) * p, 0)
	end)
end

local _cinematic = false
BLOCKS.cinematic = function(ctx, s)
	if not ctx.isOwner or not SkillFXConfig.CINEMATIC_CAMERA or _cinematic then return end
	if not SkillFXConfig.TIERS[ctx.fx.tier].cinematic then return end
	local cam = workspace.CurrentCamera
	if not cam then return end
	_cinematic = true
	local dur = math.min(2.5, s.dur or 2)
	local center = (ctx.selfPos + ctx.targetPos) / 2
	local oldType = cam.CameraType
	local oldCf = cam.CFrame
	cam.CameraType = Enum.CameraType.Scriptable
	local style = s.style or "orbit"
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		local k = math.clamp((os.clock() - t0) / dur, 0, 1)
		local eye: Vector3
		if style == "up" then
			eye = center + Vector3.new(14 - 4 * k, 2 + 4 * k, 14 - 4 * k)
			cam.CFrame = CFrame.lookAt(eye, center + Vector3.new(0, 6 + 20 * (1 - k), 0))
		elseif style == "low" then
			eye = center + Vector3.new(-10 + 6 * k, 1.2, 8)
			cam.CFrame = CFrame.lookAt(eye, ctx.targetPos)
		elseif style == "side" then
			eye = center + Vector3.new(0, 4, 18 - 6 * k)
			cam.CFrame = CFrame.lookAt(eye, center)
		else
			local a = k * math.pi * 0.9
			eye = center + Vector3.new(math.cos(a) * 16, 6, math.sin(a) * 16)
			cam.CFrame = CFrame.lookAt(eye, center)
		end
		if k >= 1 then
			if conn then conn:Disconnect() end
			cam.CFrame = oldCf
			cam.CameraType = if oldType == Enum.CameraType.Scriptable then Enum.CameraType.Custom else oldType
			_cinematic = false
		end
	end)
end

BLOCKS.sound = function(ctx, s)
	local slot = s.slot or "strike"
	local key = (ctx.fx.sounds :: any)[slot]
	if not key then return end
	local id = SkillFXConfig.SOUND_LIBRARY[key] or key
	local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.1, Color3.new(), CFrame.new(ctx.selfPos), 1)
	local snd = Instance.new("Sound")
	snd.SoundId = if tonumber(id) then "rbxassetid://" .. id else id
	-- v15: leiser, Echo noch leiser, nach MAX_SECONDS ausgeblendet
	-- (SkillFXConfig.SOUND) — die eingebauten Klaenge sind sonst sehr hart.
	local cfg = SkillFXConfig.SOUND
	local volume = if ctx.isOwner then cfg.OWNER_VOLUME else cfg.SPECTATOR_VOLUME
	if s.echo then
		volume *= cfg.ECHO_FACTOR
	end
	snd.Volume = volume
	snd.PlaybackSpeed = (ctx.fx.pitch or 1) * (if slot == "charge" then 0.9 elseif slot == "impact" then 0.8 else 1)
	snd.RollOffMode = Enum.RollOffMode.InverseTapered
	snd.RollOffMinDistance = cfg.ROLLOFF_MIN
	snd.RollOffMaxDistance = cfg.ROLLOFF_MAX
	snd.Parent = anchor
	snd:Play()
	task.delay(cfg.MAX_SECONDS, function()
		if snd.Parent ~= nil and snd.IsPlaying then
			tween(snd, cfg.FADE_SECONDS, { Volume = 0 })
		end
	end)
	Debris:AddItem(anchor, cfg.MAX_SECONDS + cfg.FADE_SECONDS + 0.2)
end

--------------------------------------------------------------------------------
-- Abspielen
--------------------------------------------------------------------------------

export type PlayRequest = {
	owner    : number,     -- UserId des Besitzers
	skillId  : string,
	full     : boolean,    -- volle Show (erster Einsatz im Lauf) oder kurzes Echo
	attacker : Model?,     -- die Figur des Baerchis
	target   : Model?,     -- der Gegner
	center   : Vector3?,   -- Arena-Mitte (Fallback fuer Positionen)
}

function SkillFXController.play(req: PlayRequest)
	local fx = SkillFXConfig.get(req.skillId)
	local selfPos = centerOf(req.attacker) or req.center
	if not selfPos then return end
	local targetPos = centerOf(req.target) or (selfPos + Vector3.new(0, 0, -8))
	local isOwner = req.owner == player.UserId

	if not isOwner then
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or (root.Position - selfPos).Magnitude > SPECTATOR_DISTANCE then
			return
		end
	end

	local ctx: Ctx = {
		fx = fx,
		selfPos = selfPos,
		targetPos = targetPos,
		arena = req.center or (selfPos + targetPos) / 2,
		isOwner = isOwner,
		factor = budgetFactor() * (if isOwner then 1 else 0.6),
		cc = nil,
		sounds = {},
	}

	if not req.full then
		-- Echo: die ersten zwei Welt-Effekte der Show, stark verkuerzt.
		local shown = 0
		for _, step in fx.steps do
			local block = BLOCKS[step.fx]
			if block and step.fx ~= "sound" and step.fx ~= "sky" and step.fx ~= "cinematic"
				and step.fx ~= "spectrum" and step.fx ~= "hitstop" and step.fx ~= "starfield"
				and step.fx ~= "flash" and step.fx ~= "shake"
			then
				local short = table.clone(step)
				short.dur = math.min(step.dur or 0.4, SkillFXConfig.TIERS[fx.tier].echo)
				task.spawn(block, ctx, short)
				shown += 1
				if shown >= 2 then break end
			end
		end
		BLOCKS.sound(ctx, { slot = "strike", echo = true })
		return
	end

	local maxDur = SkillFXConfig.getDuration(req.skillId, true)
	for _, step in fx.steps do
		local block = BLOCKS[step.fx]
		if block then
			local t = math.min(step.t or 0, maxDur)
			task.delay(t, function()
				local ok, err = pcall(block, ctx, step)
				if not ok then
					warn("[SkillFX]", req.skillId, step.fx, err)
				end
			end)
		end
	end

	-- Farbfilter am Ende sicher entfernen.
	task.delay(maxDur + 1, function()
		if ctx.cc and ctx.cc.Parent then
			tween(ctx.cc, 0.3, { TintColor = Color3.new(1, 1, 1), Brightness = 0, Saturation = 0, Contrast = 0 })
			Debris:AddItem(ctx.cc, 0.4)
		end
	end)
end

function SkillFXController.init()
	Remotes.SkillFXPlay.OnClientEvent:Connect(function(req: any)
		if typeof(req) ~= "table" or typeof(req.skillId) ~= "string" then return end
		local ok, err = pcall(SkillFXController.play, req)
		if not ok then
			warn("[SkillFXController] Show fehlgeschlagen:", err)
		end
	end)
	print("[SkillFXController] Bereit")
end

return SkillFXController
