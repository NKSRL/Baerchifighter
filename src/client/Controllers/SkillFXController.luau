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
local MapConfig     = require(ReplicatedStorage.Config.MapConfig)

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

-- Groesse der Figur (Bounding-Box). Fallback: ein normaler Baerchi.
local function sizeOf(model: Model?): Vector3
	if model and model.Parent then
		local ok, _, size = pcall(function()
			return (model :: Model):GetBoundingBox()
		end)
		if ok and typeof(size) == "Vector3" and (size :: Vector3).Y > 0.5 then
			return size :: Vector3
		end
	end
	return Vector3.new(3, 3.5, 3)
end

-- Gleiche Regeln wie newPart, fuer andere Teil-Klassen (CornerWedgePart ...).
local function prepPart(p: BasePart, color: Color3, cf: CFrame, transparency: number?)
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
end

-- Tween mit Startverzoegerung: so braucht eine Reihe von Teilen (Dornen,
-- Riss-Stuecke) keinen eigenen Thread pro Teil.
local function tweenLater(inst: Instance, delaySeconds: number, seconds: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local info = TweenInfo.new(math.max(0.01, seconds), style or Enum.EasingStyle.Quad,
		dir or Enum.EasingDirection.Out, 0, false, math.max(0, delaySeconds))
	local t = TweenService:Create(inst, info, props)
	t:Play()
	return t
end

local RAINBOW = {
	Color3.fromRGB(255, 60, 60), Color3.fromRGB(255, 160, 40), Color3.fromRGB(255, 240, 60),
	Color3.fromRGB(80, 230, 90), Color3.fromRGB(60, 180, 255), Color3.fromRGB(150, 90, 255),
}

local function pickColor(step: { [string]: any }, fx: SkillFXConfig.SkillFX, i: number?): Color3
	if step.rainbow then
		return RAINBOW[((i or 1) - 1) % #RAINBOW + 1]
	end
	if step.dark or step.second then
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
	id       : string,
	selfPos  : Vector3,
	targetPos: Vector3,
	arena    : Vector3,
	isOwner  : boolean,
	factor   : number,
	cc       : ColorCorrectionEffect?,
	sounds   : { [string]: boolean },
	-- v16 (Gletscher-Show): Fuesse, Groesse und Blickrichtung der Kaempfer.
	-- Alles relativ zu den Figuren, nie zur Arena-Bodenhoehe (Tower!).
	selfModel  : Model?,
	targetModel: Model?,
	selfSize   : Vector3,
	targetSize : Vector3,
	selfFeet   : Vector3,
	targetFeet : Vector3,
	fwd        : Vector3,       -- waagerecht von self zu target, Laenge 1
	path       : { Vector3 }?,  -- Zickzack-Linie des letzten `crack`
	cometHead  : BasePart?,     -- Kopf des laufenden `comet` (Kamera "chase")
}

local function at(ctx: Ctx, where: string?): Vector3
	if where == "target" then return ctx.targetPos end
	if where == "arena" then return ctx.arena end
	return ctx.selfPos
end

-- Bodenpunkt unter einer Figur (Fuesse).
local function groundAt(ctx: Ctx, where: string?): Vector3
	if where == "target" then return ctx.targetFeet end
	if where == "arena" then return (ctx.selfFeet + ctx.targetFeet) / 2 end
	return ctx.selfFeet
end

local function sizeAt(ctx: Ctx, where: string?): Vector3
	if where == "target" then return ctx.targetSize end
	return ctx.selfSize
end

-- Textur-ID aus SkillFXConfig.TEXTURES[<Faehigkeit>][key] oder nil (dann
-- laeuft der Rueckfall mit Neon-Teilen bzw. Standard-Partikeln).
local function texOf(ctx: Ctx, key: string?): string?
	if not key then return nil end
	local set = SkillFXConfig.TEXTURES[ctx.id]
	local id = set and set[key]
	if typeof(id) == "number" and id > 0 then
		return "rbxassetid://" .. tostring(id)
	end
	return nil
end

local function addDecal(p: BasePart, texture: string, face: Enum.NormalId, color: Color3?): Decal
	local d = Instance.new("Decal")
	d.Texture = texture
	d.Face = face
	if color then d.Color3 = color end
	d.Parent = p
	return d
end

-- Beiwerk (Schritte mit `extra = true`, Adern, Glitzer) faellt auf
-- niedriger Grafikstufe weg; der Kernmoment bleibt.
local function extrasOn(ctx: Ctx): boolean
	return ctx.factor >= SkillFXConfig.PARTICLE_BUDGET.EXTRAS_MIN
end

-- v16: Radius als Zahl oder als Name: "tower" = Turmspitze/Kampfflaeche
-- (MapConfig.PIT_TOWER_RADIUS), "fence" = bis zum Arena-Zaun. Beide gemessen
-- ab der Arena-Mitte (req.center = Mitte zwischen den Kaempfern = Turmmitte).
local function radiusOf(v: any, default: number): number
	if v == "tower" then return MapConfig.PIT_TOWER_RADIUS end
	if v == "fence" then return MapConfig.PIT_RADIUS - MapConfig.PIT_FENCE_INSET end
	return if typeof(v) == "number" then v else default
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
	-- `ground = true`: flach auf dem Boden unter der Figur (v16).
	local pos = if s.ground then groundAt(ctx, s.at) + Vector3.new(0, 0.1, 0) else at(ctx, s.at) - Vector3.new(0, 1.2, 0)
	if s.lift then
		-- v16: `lift` = so viele Studs ueber der Figur (z. B. Wolkenloch)
		pos = at(ctx, s.at) + Vector3.new(0, s.lift, 0)
	end
	local r = radiusOf(s.radius, 6)
	local dur = s.dur or 0.6
	-- `toArena` (v16): der Bodenring startet an der Figur und waechst um die
	-- Arena-Mitte herum (z. B. Schockwelle bis zum Zaun).
	local endPos = if s.toArena and s.ground then groundAt(ctx, "arena") + Vector3.new(0, 0.1, 0) else pos
	local startD = if s.shrink then r * 2 else 0.5
	local endD   = if s.shrink then 0.5 else r * 2
	-- `ground` + `tex`: das Bild liegt als Decal auf einer flachen, unsichtbaren
	-- Platte (quadratisches PNG mit rundem Motiv).
	local texture = if s.ground or s.lift then texOf(ctx, s.tex) else nil
	if texture then
		local plate = newPart(Enum.PartType.Block, Vector3.new(startD, 0.05, startD), pickColor(s, ctx.fx), CFrame.new(pos), 1)
		local d = addDecal(plate, texture, Enum.NormalId.Top, plate.Color)
		tween(plate, dur, { Size = Vector3.new(endD, 0.05, endD), CFrame = CFrame.new(endPos) })
		tweenLater(d, dur * 0.6, dur * 0.4, { Transparency = 1 })
		if s.lift then
			-- von unten sichtbar
			local under = addDecal(plate, texture, Enum.NormalId.Bottom, plate.Color)
			tweenLater(under, dur * 0.6, dur * 0.4, { Transparency = 1 })
		end
		Debris:AddItem(plate, dur + 0.1)
		return
	end
	local ring = newPart(Enum.PartType.Cylinder, Vector3.new(if s.ground or s.lift then 0.08 else 0.25, startD, startD), pickColor(s, ctx.fx),
		CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), 0.2)
	if s.ground or s.lift then
		-- flacher Ring: Dicke bleibt, nur der Durchmesser waechst
		tween(ring, dur, { Size = Vector3.new(0.08, endD, endD),
			CFrame = CFrame.new(endPos) * CFrame.Angles(0, 0, math.rad(90)) })
		task.delay(dur * 0.6, function()
			if ring.Parent then fadeAndDestroy(ring, dur * 0.4) end
		end)
		return
	end
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
	if s.feet then
		-- v16: Fuss der Saeule genau unter der Figur (Tower in jeder Hoehe)
		base = groundAt(ctx, s.at)
	end
	local texture = texOf(ctx, s.tex)
	if texture then
		-- v16: Saeule als Beam mit Bild (weicher Verlauf). Zwei unsichtbare
		-- Anker; bei `fromSky` faellt der untere Anker von oben herab.
		local topPart = newPart(Enum.PartType.Block, Vector3.one * 0.2, Color3.new(1, 1, 1), CFrame.new(base + Vector3.new(0, h, 0)), 1)
		local lowPart = newPart(Enum.PartType.Block, Vector3.one * 0.2, Color3.new(1, 1, 1),
			CFrame.new(if s.fromSky then base + Vector3.new(0, h, 0) else base), 1)
		local a0 = Instance.new("Attachment"); a0.Parent = topPart
		local a1 = Instance.new("Attachment"); a1.Parent = lowPart
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Texture = texture
		beam.TextureMode = Enum.TextureMode.Stretch
		beam.FaceCamera = true
		beam.LightEmission = 1
		beam.Color = ColorSequence.new(pickColor(s, ctx.fx))
		beam.Width0 = w
		beam.Width1 = w
		beam.Parent = topPart
		tween(lowPart, dur * 0.35, { CFrame = CFrame.new(base) }, Enum.EasingStyle.Quart)
		tweenLater(beam, dur * 0.6, dur * 0.4, { Width0 = w * 0.2, Width1 = w * 0.2 })
		Debris:AddItem(topPart, dur + 0.1)
		Debris:AddItem(lowPart, dur + 0.1)
		return
	end
	local startCf = if s.fromSky
		then CFrame.new(base + Vector3.new(0, h * 1.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
		else CFrame.new(base) * CFrame.Angles(0, 0, math.rad(90))
	local col = newPart(Enum.PartType.Cylinder, Vector3.new(0.2, w, w), pickColor(s, ctx.fx), startCf, if s.soft then 0.5 else 0.15)
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

-- v16: Truemmer fliegen im Bogen nach aussen und fallen auf den Boden
-- (`arc`). Hoch und runter sind zwei Tweens; der zweite startet fuer ALLE
-- Brocken aus EINEM verzoegerten Aufruf (kein Thread pro Brocken).
local function shardsArc(ctx: Ctx, s: { [string]: any })
	local pos = at(ctx, s.at)
	local floorY = groundAt(ctx, s.at).Y
	local n = scaled(s.count, ctx.factor)
	local size = s.size or 0.8
	local dur = s.dur or 1.0
	local texture = texOf(ctx, s.tex)
	local half = dur * 0.45
	local down: { { part: BasePart, goal: CFrame } } = {}
	for i = 1, n do
		local a = math.random() * math.pi * 2
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local reach = 5 + math.random() * 8
		local apex = pos + out * reach * 0.5 + Vector3.new(0, 2.5 + math.random() * 3.5, 0)
		local land = Vector3.new(pos.X, floorY + size * 0.3, pos.Z) + out * reach
		local p = newPart(Enum.PartType.Block, Vector3.new(size, size * 0.8, size * 0.7), pickColor(s, ctx.fx, i),
			CFrame.new(pos) * CFrame.Angles(math.random() * 6, math.random() * 6, 0), 0)
		if s.stone then
			p.Material = Enum.Material.Slate
			p.Color = Color3.fromRGB(80, 70, 90):Lerp(ctx.fx.color, 0.2)
		end
		if texture then
			addDecal(p, texture, Enum.NormalId.Top)
			addDecal(p, texture, Enum.NormalId.Front)
		end
		tween(p, half, { CFrame = CFrame.new(apex) * CFrame.Angles(math.random() * 6, math.random() * 6, 0) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		table.insert(down, { part = p, goal = CFrame.new(land) * CFrame.Angles(math.random() * 6, math.random() * 6, 0) })
		Debris:AddItem(p, dur + 0.1)
	end
	task.delay(half, function()
		for _, d in down do
			if d.part.Parent then
				tween(d.part, half, { CFrame = d.goal }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				tweenLater(d.part, half, dur - 2 * half, { Transparency = 1 })
			end
		end
	end)
end

BLOCKS.shards = function(ctx, s)
	if s.arc then shardsArc(ctx, s) return end
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

-- v16: Kristalle von den Fuessen bis zur Huefte (`legs`). Waechst von unten
-- nach oben: jeder Kristall startet per Tween-Verzoegerung, kein Thread.
local function frostLegs(ctx: Ctx, s: { [string]: any })
	local feet = groundAt(ctx, s.at)
	local size = sizeAt(ctx, s.at)
	local hip = size.Y * 0.55
	local radius = math.max(size.X, size.Z) * 0.42
	local n = math.max(6, scaled(s.count, ctx.factor))
	local dur = s.dur or 1.2
	local grow = dur * 0.45
	for i = 1, n do
		local k = (i - 1) / math.max(1, n - 1)          -- 0 = Fuesse, 1 = Huefte
		local a = i * 2.39996                            -- goldener Winkel: gleichmaessig rundum
		local r = radius * (1.05 - 0.25 * k)
		local base = feet + Vector3.new(math.cos(a) * r, 0.1 + k * hip, math.sin(a) * r)
		local outward = Vector3.new(math.cos(a), 0, math.sin(a))
		local h = 0.9 + 0.6 * (1 - k) + math.random() * 0.4
		local rot = CFrame.lookAt(Vector3.zero, outward).Rotation * CFrame.Angles(math.rad(25 + math.random() * 20), 0, 0)
		local p = newPart(Enum.PartType.Block, Vector3.new(0.05, 0.05, 0.05), if i % 3 == 0 then ctx.fx.color2 else ctx.fx.color,
			CFrame.new(base) * rot, 0.1)
		p.Material = Enum.Material.Ice
		local w = 0.28 + 0.12 * (1 - k)
		tweenLater(p, k * grow, grow * 0.6, {
			Size = Vector3.new(w, h, w),
			CFrame = CFrame.new(base) * rot * CFrame.new(0, h * 0.35, 0),
		}, Enum.EasingStyle.Back)
		tweenLater(p, dur * 0.75, dur * 0.25, { Transparency = 1 })
		Debris:AddItem(p, dur + 0.1)
	end
end

-- v16: kleine Kristalle auf Ohren und Schultern (`perch`), ein Glitzern.
local function frostPerch(ctx: Ctx, s: { [string]: any })
	local model = if s.at == "target" then ctx.targetModel else ctx.selfModel
	local center = at(ctx, s.at)
	local size = sizeAt(ctx, s.at)
	local spots: { Vector3 } = {}
	for _, name in { "ear_left", "ear_right" } do
		local ear = model and model:FindFirstChild(name, true)
		if ear and ear:IsA("BasePart") then
			table.insert(spots, ear.Position + Vector3.new(0, ear.Size.Y * 0.4, 0))
		end
	end
	if #spots == 0 then
		-- Rueckfall: Ohren oben links/rechts am Kopf schaetzen.
		local side = ctx.fwd:Cross(Vector3.yAxis)
		table.insert(spots, center + side * size.X * 0.28 + Vector3.new(0, size.Y * 0.48, 0))
		table.insert(spots, center - side * size.X * 0.28 + Vector3.new(0, size.Y * 0.48, 0))
	end
	local side = ctx.fwd:Cross(Vector3.yAxis)
	table.insert(spots, center + side * size.X * 0.42 + Vector3.new(0, size.Y * 0.05, 0))  -- Schultern
	table.insert(spots, center - side * size.X * 0.42 + Vector3.new(0, size.Y * 0.05, 0))
	local dur = s.dur or 1.4
	local per = math.max(1, math.floor(scaled(s.count, ctx.factor) / #spots + 0.5))
	for si, spot in spots do
		for j = 1, per do
			local rot = CFrame.Angles(math.random() - 0.5, math.random() * 6, math.random() - 0.5)
			local p = newPart(Enum.PartType.Block, Vector3.new(0.05, 0.05, 0.05), ctx.fx.color,
				CFrame.new(spot) * rot, 0.05)
			p.Material = Enum.Material.Ice
			local h = 0.35 + math.random() * 0.35
			tweenLater(p, (si + j) * 0.06, dur * 0.3, { Size = Vector3.new(0.14, h, 0.14) }, Enum.EasingStyle.Back)
			if s.glint and extrasOn(ctx) then
				-- EIN kurzes Aufleuchten der Kante (weiss, hin und zurueck), kein Flackern.
				TweenService:Create(p, TweenInfo.new(0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, true,
					dur * 0.35 + si * 0.08), { Color = Color3.new(1, 1, 1) }):Play()
			end
			tweenLater(p, dur * 0.8, dur * 0.2, { Transparency = 1 })
			Debris:AddItem(p, dur + 0.1)
		end
	end
end

BLOCKS.frost = function(ctx, s)
	if s.legs then frostLegs(ctx, s) return end
	if s.perch then frostPerch(ctx, s) return end
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

--------------------------------------------------------------------------------
-- v16 (Gletscher-Show): Boden, Riss, Dornen, Atem, Schneefall. Wiederverwendbar
-- fuer jede Faehigkeit; Doku in SkillFXConfig ("BAUSTEINE").
--------------------------------------------------------------------------------

-- Ein flaches Teil auf dem Boden, das von `from` nach `to` waechst (Riss,
-- Adern). Kein Thread: Wachsen und Ausblenden sind verzoegerte Tweens.
local function groundStroke(ctx: Ctx, from: Vector3, to: Vector3, width: number, color: Color3,
	delaySeconds: number, growSeconds: number, fadeAt: number, texture: string?): BasePart?
	local len = (to - from).Magnitude
	if len < 0.05 then return nil end
	local rot = CFrame.lookAt(from, to).Rotation
	local p = newPart(Enum.PartType.Block, Vector3.new(width, 0.04, 0.01), color, CFrame.new(from) * rot, 0)
	tweenLater(p, delaySeconds, growSeconds, {
		Size = Vector3.new(width, 0.04, len),
		CFrame = CFrame.new((from + to) / 2) * rot,
	}, Enum.EasingStyle.Linear)
	if texture then
		p.Transparency = 1
		local d = addDecal(p, texture, Enum.NormalId.Top, color)
		tweenLater(d, fadeAt, 0.4, { Transparency = 1 })
	else
		tweenLater(p, fadeAt, 0.4, { Transparency = 1 })
	end
	Debris:AddItem(p, fadeAt + 0.5)
	return p
end

-- breath: Atemwolke vor dem Maul. EIN Emitter, zwei Atemstoesse.
--   at, dur, count (Teilchen je Stoss)
BLOCKS.breath = function(ctx, s)
	local center = at(ctx, s.at)
	local size = sizeAt(ctx, s.at)
	local dir = if s.at == "target" then -ctx.fwd else ctx.fwd
	local mouth = center + dir * size.Z * 0.45 + Vector3.new(0, size.Y * 0.2, 0)
	local dur = s.dur or 1.0
	local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, Color3.new(1, 1, 1), CFrame.lookAt(mouth, mouth + dir), 1)
	local em = Instance.new("ParticleEmitter")
	em.Texture = texOf(ctx, s.tex) or "rbxasset://textures/particles/smoke_main.dds"
	em.EmissionDirection = Enum.NormalId.Front
	em.Rate = 0
	em.Speed = NumberRange.new(1.5, 2.5)
	em.SpreadAngle = Vector2.new(18, 12)
	em.Drag = 2.5
	em.Lifetime = NumberRange.new(0.8, 1.1)
	em.Acceleration = Vector3.new(0, 0.6, 0)
	em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1.6) })
	em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	em.Color = ColorSequence.new(Color3.new(1, 1, 1), ctx.fx.color)
	em.LightEmission = 0.2
	em.Rotation = NumberRange.new(0, 360)
	em.RotSpeed = NumberRange.new(-30, 30)
	em.Parent = anchor
	local n = scaled(s.count, ctx.factor)
	em:Emit(n)
	task.delay(dur * 0.5, function()
		if em.Parent then em:Emit(n) end
	end)
	Debris:AddItem(anchor, dur * 0.5 + 1.3)
end

-- groundmark: Boden friert in einem Kreis, Adern kriechen nach aussen.
--   at, radius, dur, veins (Zahl der Adern; Beiwerk), tex (Bodenbild)
BLOCKS.groundmark = function(ctx, s)
	local feet = groundAt(ctx, s.at) + Vector3.new(0, 0.06, 0)
	local r = s.radius or 6
	local dur = s.dur or 2
	local grow = dur * 0.3
	local disc = newPart(Enum.PartType.Cylinder, Vector3.new(0.05, 0.5, 0.5), ctx.fx.color,
		CFrame.new(feet) * CFrame.Angles(0, 0, math.rad(90)), 0.45)
	disc.Material = Enum.Material.Ice
	tween(disc, grow, { Size = Vector3.new(0.05, r * 1.2, r * 1.2) }, Enum.EasingStyle.Sine)
	local texture = texOf(ctx, s.tex)
	if texture then
		-- Mit Bodenbild: das Bild (auf einer flachen Platte) traegt Kreis UND
		-- Adern; die Eisscheibe bleibt als blasser Grund darunter.
		local plate = newPart(Enum.PartType.Block, Vector3.new(0.5, 0.05, 0.5), ctx.fx.color, CFrame.new(feet + Vector3.new(0, 0.03, 0)), 1)
		local d = addDecal(plate, texture, Enum.NormalId.Top)
		tween(plate, grow * 1.6, { Size = Vector3.new(r * 2, 0.05, r * 2) }, Enum.EasingStyle.Sine)
		tweenLater(d, dur * 0.8, dur * 0.2, { Transparency = 1 })
		tweenLater(disc, dur * 0.8, dur * 0.2, { Transparency = 1 })
		Debris:AddItem(plate, dur + 0.1)
	else
		tweenLater(disc, dur * 0.8, dur * 0.2, { Transparency = 1 })
		if extrasOn(ctx) then
			-- Rueckfall: Reif-Adern als duenne Neon-Striche, je Ader ein Ast.
			local n = scaled(s.veins or 6, ctx.factor)
			for i = 1, n do
				local a = (i / n) * math.pi * 2 + math.random() * 0.4
				local dir = Vector3.new(math.cos(a), 0, math.sin(a))
				local mainEnd = feet + dir * r * (0.75 + math.random() * 0.25)
				groundStroke(ctx, feet, mainEnd, 0.09, ctx.fx.color2, i * 0.03, grow * 1.4, dur * 0.8, nil)
				local fork = feet + dir * r * 0.45
				local turn = (if i % 2 == 0 then 1 else -1) * math.rad(35)
				local bdir = Vector3.new(math.cos(a + turn), 0, math.sin(a + turn))
				groundStroke(ctx, fork, fork + bdir * r * 0.35, 0.06, ctx.fx.color2, grow * 0.8, grow * 0.8, dur * 0.8, nil)
			end
		end
	end
	Debris:AddItem(disc, dur + 0.1)
end

-- crack: Zickzack-Riss am Boden von self zu target. Merkt sich die Linie in
-- ctx.path (fuer `spikes`).
--   dur (Wachsen), linger (sichtbar bis), segments, amp (Zickzack-Breite), width, tex
BLOCKS.crack = function(ctx, s)
	local from = ctx.selfFeet + ctx.fwd * ctx.selfSize.Z * 0.3 + Vector3.new(0, 0.07, 0)
	local to = ctx.targetFeet - ctx.fwd * ctx.targetSize.Z * 0.15 + Vector3.new(0, 0.07, 0)
	local k = s.segments or 7
	local amp = s.amp or 0.9
	local side = ctx.fwd:Cross(Vector3.yAxis)
	local pts: { Vector3 } = { from }
	for j = 1, k - 1 do
		local sign = if j % 2 == 0 then 1 else -1
		table.insert(pts, from:Lerp(to, j / k) + side * sign * amp * (0.6 + math.random() * 0.4))
	end
	table.insert(pts, to)
	ctx.path = pts
	local dur = s.dur or 0.5
	local linger = s.linger or (dur + 1)
	local step = dur / k
	local texture = texOf(ctx, s.tex)
	for j = 1, k do
		groundStroke(ctx, pts[j], pts[j + 1], s.width or 0.28, ctx.fx.color2, (j - 1) * step, step, linger, texture)
	end
end

-- spikes: schraege Eisdornen brechen nacheinander entlang ctx.path (oder der
-- Linie self -> target) aus dem Boden, jeder hoeher als der vorige.
--   count, dur (vom ersten bis zum letzten Dorn), minHeight, maxHeight, linger, tex
BLOCKS.spikes = function(ctx, s)
	local pts = ctx.path or { ctx.selfFeet, ctx.targetFeet }
	-- Gesamtlaenge und Punkt bei Anteil k entlang der Linie
	local lens: { number } = {}
	local total = 0
	for j = 1, #pts - 1 do
		local l = (pts[j + 1] - pts[j]).Magnitude
		lens[j] = l
		total += l
	end
	local function pointAt(k: number): Vector3
		local want = total * k
		for j = 1, #pts - 1 do
			if want <= lens[j] or j == #pts - 1 then
				return pts[j]:Lerp(pts[j + 1], math.clamp(want / math.max(lens[j], 0.001), 0, 1))
			end
			want -= lens[j]
		end
		return pts[#pts]
	end
	local n = math.max(4, scaled(s.count, ctx.factor))   -- Kernmoment: nie unter 4
	local dur = s.dur or 0.8
	local rise = s.rise or 0.18
	local linger = s.linger or (dur + 1)
	local lo, hi = s.minHeight or 1.0, s.maxHeight or 3.2
	local tilt = CFrame.lookAt(Vector3.zero, ctx.fwd).Rotation * CFrame.Angles(math.rad(-28), 0, 0)
	local texture = texOf(ctx, s.tex)
	local tips = extrasOn(ctx)
	for i = 1, n do
		local k = i / n
		local base = pointAt(0.2 + 0.8 * k)
		local h = lo + (hi - lo) * k
		local w = 0.55 + 0.35 * k
		local delaySeconds = (i - 1) * (dur / n)
		local rot = tilt * CFrame.Angles(0, math.random() * 0.6 - 0.3, 0)
		local spike = Instance.new("CornerWedgePart")
		spike.Size = Vector3.new(w, 0.05, w)
		prepPart(spike, if i % 2 == 0 then ctx.fx.color else ctx.fx.color:Lerp(Color3.fromRGB(40, 170, 180), 0.35), CFrame.new(base) * rot, 0.05)
		spike.Material = Enum.Material.Ice
		if texture then
			local d = addDecal(spike, texture, Enum.NormalId.Front)
			tweenLater(d, linger, 0.35, { Transparency = 1 })
		end
		tweenLater(spike, delaySeconds, rise, {
			Size = Vector3.new(w, h, w),
			CFrame = CFrame.new(base) * rot * CFrame.new(0, h / 2, 0),
		}, Enum.EasingStyle.Back)
		tweenLater(spike, linger, 0.35, { Transparency = 1 })
		Debris:AddItem(spike, linger + 0.45)
		if tips then
			-- Reines Weiss als scharfes Licht: jeder Dorn leuchtet nach dem
			-- Ausbrechen EINMAL kurz auf (laeuft als Welle mit, kein Flackern).
			TweenService:Create(spike, TweenInfo.new(0.16, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 0, true,
				delaySeconds + rise * 0.8), { Color = Color3.new(1, 1, 1) }):Play()
		end
	end
end

-- snowfall: Nachgluehen. Leichter Reifschimmer um die Figur und einzelne
-- Schneeflocken, die langsam herabsinken. EIN Emitter.
--   at, count, dur, tex (Flocke)
BLOCKS.snowfall = function(ctx, s)
	local center = at(ctx, s.at)
	local size = sizeAt(ctx, s.at)
	local dur = s.dur or 1.2
	local top = center + Vector3.new(0, size.Y * 0.5 + (s.lift or 1.5), 0)
	local w = math.max(size.X, size.Z) * 1.6
	local anchor = newPart(Enum.PartType.Block, Vector3.new(w, 0.2, w), Color3.new(1, 1, 1), CFrame.new(top), 1)
	local em = Instance.new("ParticleEmitter")
	em.Texture = texOf(ctx, s.tex) or "rbxasset://textures/particles/sparkles_main.dds"
	em.Shape = Enum.ParticleEmitterShape.Box
	em.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	em.EmissionDirection = Enum.NormalId.Bottom
	em.Rate = 0
	em.Speed = NumberRange.new(0.6, 1.2)
	em.Acceleration = Vector3.new(0, -0.4, 0)
	em.Drag = 0.5
	em.Lifetime = NumberRange.new(dur * 0.8, dur * 1.2)
	em.Size = NumberSequence.new(s.size or 0.22)
	em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.7, 0.3), NumberSequenceKeypoint.new(1, 1) })
	em.Color = ColorSequence.new(Color3.new(1, 1, 1), ctx.fx.color)
	em.LightEmission = 0.5
	em.Rotation = NumberRange.new(0, 360)
	em.RotSpeed = NumberRange.new(-40, 40)
	em.Parent = anchor
	em:Emit(scaled(s.count, ctx.factor))
	Debris:AddItem(anchor, dur * 1.2 + 0.2)
	-- Reifschimmer: eine fast durchsichtige Huelle, blendet langsam aus.
	-- `noShell` (v16, z. B. rieselnde Federn): nur der Emitter.
	if s.noShell then return end
	local shell = newPart(Enum.PartType.Ball, size * 1.15, ctx.fx.color, CFrame.new(center), 0.82)
	shell.Material = Enum.Material.ForceField
	tweenLater(shell, dur * 0.4, dur * 0.6, { Transparency = 1 }, Enum.EasingStyle.Sine)
	Debris:AddItem(shell, dur + 0.1)
end

--------------------------------------------------------------------------------
-- v16 (Seraph-Show): Fluegel, Heiligenschein, Wabenmuster. Wiederverwendbar;
-- Doku in SkillFXConfig ("BAUSTEINE").
--------------------------------------------------------------------------------

-- Haelt Teile an einer Figur fest, waehrend sie sich bewegt (Wippen, Anlauf
-- zum Stoss). EINE RenderStepped-Verbindung pro Effekt, endet nach `seconds`
-- oder wenn die Figur weg ist. `place(center, k)` setzt die Teile.
local function followModel(model: Model?, fallback: Vector3, seconds: number, place: (Vector3, number) -> ())
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		local k = os.clock() - t0
		if k >= seconds then
			if conn then conn:Disconnect() end
			return
		end
		local c = centerOf(model) or fallback
		local ok = pcall(place, c, k)
		if not ok and conn then conn:Disconnect() end
	end)
end

-- wings: zwei Fluegel aus langen Lichtfedern entfalten sich hinter der Figur,
-- Feder fuer Feder von innen nach aussen; bei `foldAt` falten sie sich
-- zusammen und zerfallen in Funken (EIN Emitter).
--   at, count (Federn je Fluegel), span (Laenge), dur, foldAt, tex (Feder), sparkTex
BLOCKS.wings = function(ctx, s)
	local center = at(ctx, s.at)
	local size = sizeAt(ctx, s.at)
	local fwd = if s.at == "target" then -ctx.fwd else ctx.fwd
	local side = fwd:Cross(Vector3.yAxis)
	local n = math.max(4, scaled(s.count or 7, ctx.factor))
	local span = s.span or 2.6
	local dur = s.dur or 3
	local foldAt = s.foldAt or (dur - 0.4)
	local unfold = math.min(0.9, dur * 0.3)
	local texture = texOf(ctx, s.tex)
	for _, sgn in { 1, -1 } do
		local origin = center - fwd * size.Z * 0.3 + Vector3.new(0, size.Y * 0.18, 0) + side * sgn * size.X * 0.12
		for i = 1, n do
			local k = (i - 1) / math.max(1, n - 1)                  -- 0 = innen (oben), 1 = aussen (unten)
			local a = math.rad(18 + 92 * k)
			local dir = (Vector3.yAxis * math.cos(a) + side * sgn * math.sin(a) - fwd * 0.3).Unit
			local len = span * (1.05 - 0.35 * k)
			local p = newPart(Enum.PartType.Block, Vector3.new(0.34, 0.06, 0.05), if i % 2 == 0 then ctx.fx.color else ctx.fx.color2,
				CFrame.lookAt(origin, origin + dir, fwd), 0.25)
			if texture then
				p.Transparency = 1
				for _, face in { Enum.NormalId.Top, Enum.NormalId.Bottom } do
					local d = addDecal(p, texture, face, p.Color)
					tweenLater(d, foldAt, 0.35, { Transparency = 1 })
				end
			end
			tweenLater(p, k * unfold, 0.3, {
				Size = Vector3.new(0.34, 0.06, len),
				CFrame = CFrame.lookAt(origin + dir * len / 2, origin + dir * len, fwd),
			}, Enum.EasingStyle.Sine)
			-- zusammenfalten (aussen zuerst) und verblassen
			tweenLater(p, foldAt + (1 - k) * 0.12, 0.3, {
				Size = Vector3.new(0.34, 0.06, 0.05),
				CFrame = CFrame.lookAt(origin, origin + dir, fwd),
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			tweenLater(p, foldAt, 0.42, { Transparency = 1 })
			Debris:AddItem(p, foldAt + 0.5)
		end
	end
	-- Funken beim Zerfallen (Beiwerk)
	if extrasOn(ctx) then
		local back = center - fwd * size.Z * 0.35 + Vector3.new(0, size.Y * 0.3, 0)
		local anchor = newPart(Enum.PartType.Block, Vector3.new(span * 2, span, 0.2), Color3.new(1, 1, 1),
			CFrame.lookAt(back, back + fwd), 1)
		local em = Instance.new("ParticleEmitter")
		em.Texture = texOf(ctx, s.sparkTex) or "rbxasset://textures/particles/sparkles_main.dds"
		em.Shape = Enum.ParticleEmitterShape.Box
		em.Rate = 0
		em.Speed = NumberRange.new(0.5, 1.5)
		em.SpreadAngle = Vector2.new(180, 180)
		em.Acceleration = Vector3.new(0, -1, 0)
		em.Drag = 1
		em.Lifetime = NumberRange.new(0.6, 1.0)
		em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
		em.Color = ColorSequence.new(ctx.fx.color2, ctx.fx.color)
		em.LightEmission = 1
		em.Parent = anchor
		task.delay(foldAt + 0.15, function()
			if em.Parent then em:Emit(scaled(s.sparks or 24, ctx.factor)) end
		end)
		Debris:AddItem(anchor, foldAt + 1.3)
	end
end

-- halo: Heiligenschein ueber dem Kopf, dreht sich langsam und bleibt an der
-- Figur. Ohne Bild: Perlen im Kreis; mit Bild: eine flache Scheibe.
--   at, radius, lift (ueber dem Kopf), count (Perlen), dur, tex
BLOCKS.halo = function(ctx, s)
	local model = if s.at == "target" then ctx.targetModel else ctx.selfModel
	local start = at(ctx, s.at)
	local size = sizeAt(ctx, s.at)
	local up = size.Y * 0.5 + (s.lift or 0.7)
	local r = s.radius or 0.9
	local dur = s.dur or 2.5
	local texture = texOf(ctx, s.tex)
	local parts: { BasePart } = {}
	if texture then
		local plate = newPart(Enum.PartType.Block, Vector3.new(r * 2.4, 0.05, r * 2.4), ctx.fx.color, CFrame.new(start + Vector3.new(0, up, 0)), 1)
		for _, face in { Enum.NormalId.Top, Enum.NormalId.Bottom } do
			local d = addDecal(plate, texture, face, ctx.fx.color)
			d.Transparency = 1
			tween(d, 0.4, { Transparency = 0 })
			tweenLater(d, dur - 0.4, 0.4, { Transparency = 1 })
		end
		table.insert(parts, plate)
	else
		local n = math.max(8, scaled(s.count or 14, ctx.factor))
		for i = 1, n do
			local p = newPart(Enum.PartType.Ball, Vector3.one * 0.26, if i % 4 == 0 then ctx.fx.color2 else ctx.fx.color,
				CFrame.new(start + Vector3.new(0, up, 0)), 1)
			tween(p, 0.4, { Transparency = 0.05 })
			tweenLater(p, dur - 0.4, 0.4, { Transparency = 1 })
			table.insert(parts, p)
		end
	end
	for _, p in parts do Debris:AddItem(p, dur + 0.1) end
	local n = #parts
	local cfs = table.create(n) :: { CFrame }
	followModel(model, start, dur, function(c, k)
		local spin = k * 0.8                    -- langsam: etwa eine Umdrehung in 8 s
		local mid = c + Vector3.new(0, up, 0)
		if texture then
			cfs[1] = CFrame.new(mid) * CFrame.Angles(0, spin, 0)
		else
			for i = 1, n do
				local a = spin + (i / n) * math.pi * 2
				cfs[i] = CFrame.new(mid + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
			end
		end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end)
end

-- honeycomb: feines Wabenmuster laeuft von den Fuessen bis zum Kopf ueber die
-- Figur (`sweep`), zieht dann in sie ein (`pull`) und laesst einen warmen
-- Schein zurueck, der `hold` Sekunden an der Figur bleibt, auch wenn sie sich
-- bewegt (z. B. bis der HP-Balken die Heilung zeigt).
--   at, cols, rows, sweep, pull, hold, tex (Wabe)
BLOCKS.honeycomb = function(ctx, s)
	local model = if s.at == "target" then ctx.targetModel else ctx.selfModel
	local center = at(ctx, s.at)
	local feet = groundAt(ctx, s.at)
	local size = sizeAt(ctx, s.at)
	local radius = math.max(size.X, size.Z) * 0.58
	local cols = math.max(5, scaled(s.cols or 9, ctx.factor))
	local rows = math.max(4, scaled(s.rows or 6, ctx.factor))
	local sweep = s.sweep or 0.5
	local pull = s.pull or 0.35
	local hold = s.hold or 0.8
	local tile = math.min(0.7, (2 * math.pi * radius) / cols * 0.8)
	local texture = texOf(ctx, s.tex)
	for row = 1, rows do
		local y = (row - 0.5) / rows * size.Y
		local appear = (row - 1) / rows * sweep
		for col = 1, cols do
			-- jede zweite Reihe um eine halbe Wabe versetzt (Bienenwaben)
			local a = (col + (if row % 2 == 0 then 0.5 else 0)) / cols * math.pi * 2
			local out = Vector3.new(math.cos(a), 0, math.sin(a))
			local pos = feet + Vector3.new(0, y, 0) + out * radius
			local face = CFrame.lookAt(pos, pos + out)
			local p: BasePart
			if texture then
				p = newPart(Enum.PartType.Block, Vector3.new(0.05, 0.05, 0.04), ctx.fx.color, face, 1)
				local d = addDecal(p, texture, Enum.NormalId.Front, ctx.fx.color)  -- Front = -Z = nach aussen
				tweenLater(d, sweep + pull * 0.5, pull * 0.5, { Transparency = 1 })
			else
				-- Rueckfall: flache Neon-Scheibe (Zylinder-Achse zeigt nach aussen)
				p = newPart(Enum.PartType.Cylinder, Vector3.new(0.04, 0.05, 0.05), if (row + col) % 3 == 0 then ctx.fx.color2 else ctx.fx.color,
					face * CFrame.Angles(0, math.rad(90), 0), 0.2)
			end
			local full = if texture then Vector3.new(tile, tile, 0.04) else Vector3.new(0.04, tile, tile)
			tweenLater(p, appear, 0.12, { Size = full }, Enum.EasingStyle.Back)
			-- einziehen: zur Mitte der Figur, dabei klein werden
			local inPos = center + Vector3.new(0, y - size.Y * 0.5, 0) * 0.3
			tweenLater(p, sweep, pull, {
				CFrame = CFrame.new(inPos) * (p.CFrame - p.CFrame.Position),
				Size = if texture then Vector3.new(0.05, 0.05, 0.04) else Vector3.new(0.04, 0.05, 0.05),
			}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			if not texture then
				tweenLater(p, sweep + pull * 0.5, pull * 0.5, { Transparency = 1 })
			end
			Debris:AddItem(p, sweep + pull + 0.05)
		end
	end
	-- Der warme Schein bleibt an der Figur.
	task.delay(sweep + pull * 0.7, function()
		local now = centerOf(model) or center
		local glowPart = newPart(Enum.PartType.Ball, size * 1.25, ctx.fx.color, CFrame.new(now), 0.45)
		glowPart.Material = Enum.Material.ForceField
		tween(glowPart, 0.25, { Size = size * 0.95 }, Enum.EasingStyle.Quad)
		tweenLater(glowPart, hold * 0.55, hold * 0.45, { Transparency = 1 }, Enum.EasingStyle.Sine)
		Debris:AddItem(glowPart, hold + 0.1)
		followModel(model, now, hold, function(c)
			glowPart.CFrame = CFrame.new(c)
		end)
	end)
end

--------------------------------------------------------------------------------
-- v16 (Kometen-Show): Schattenkreis, Komet, Krater, Sternstaub.
-- Doku in SkillFXConfig ("BAUSTEINE").
--------------------------------------------------------------------------------

-- shadow: dunkler Kreis am Boden, waechst beschleunigt (wie etwas, das von
-- oben naeherkommt). Mit `toArena` wandert seine Mitte zur Arena-Mitte, damit
-- er bei radius = "tower" genau die Turmspitze bedeckt.
--   at, from (Startradius), radius (Zahl | "tower" | "fence"), dur, fadeOut, toArena
BLOCKS.shadow = function(ctx, s)
	local start = groundAt(ctx, s.at) + Vector3.new(0, 0.05, 0)
	local finish = if s.toArena then groundAt(ctx, "arena") + Vector3.new(0, 0.05, 0) else start
	local r0 = s.from or 1.5
	local r1 = radiusOf(s.radius, 8)
	local dur = s.dur or 2
	local fadeOut = s.fadeOut or 0.3
	local disc = newPart(Enum.PartType.Cylinder, Vector3.new(0.05, r0 * 2, r0 * 2), Color3.fromRGB(12, 10, 30),
		CFrame.new(start) * CFrame.Angles(0, 0, math.rad(90)), 0.7)
	disc.Material = Enum.Material.SmoothPlastic
	tween(disc, dur, {
		Size = Vector3.new(0.05, r1 * 2, r1 * 2),
		CFrame = CFrame.new(finish) * CFrame.Angles(0, 0, math.rad(90)),
		Transparency = 0.35,
	}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	-- verschwindet im Einschlag (Transparenz-Tween ersetzt den obigen erst
	-- nach dessen Ende: gleiche Eigenschaft, spaeter gestartet)
	task.delay(dur, function()
		if disc.Parent then tween(disc, fadeOut, { Transparency = 1 }) end
	end)
	Debris:AddItem(disc, dur + fadeOut + 0.1)
end

-- comet: ein Punkt funkelt hoch ueber dem Gegner und wird groesser
-- (`charge` s), dann faellt der Komet mit gluehendem Kopf, weissem Kern und
-- langem Schweif auf den Gegner (`fall` s; die letzten 30 % langsamer =
-- Zeitlupe). Funken loesen sich vom Schweif (EIN Emitter). Bricht er durch
-- die Wolkendecke (`cloudY` Studs ueber dem Gegner), stieben Wolkenfetzen.
-- Der Kopf steht in ctx.cometHead (Kamera "chase").
-- EINE RenderStepped-Verbindung fuer den ganzen Kometen.
--   height, size, charge, fall, cloudY, tex (Glut), tailTex (Schweif)
BLOCKS.comet = function(ctx, s)
	local to = ctx.targetPos
	local h = s.height or 80
	local size = s.size or 3
	local charge = s.charge or 0
	local fall = s.fall or 0.8
	local side = ctx.fwd:Cross(Vector3.yAxis)
	local from = to - ctx.fwd * h * 0.4 + side * h * 0.2 + Vector3.new(0, h, 0)
	local slowAt = to + (from - to) * 0.18     -- ab hier Zeitlupe
	local dir = (to - from).Unit

	local head = newPart(Enum.PartType.Ball, Vector3.one * 0.3, ctx.fx.color, CFrame.lookAt(from, from + dir), 0)
	local core = newPart(Enum.PartType.Ball, Vector3.one * 0.15, Color3.new(1, 1, 1), CFrame.new(from), 0)
	local glowTex = texOf(ctx, s.tex)
	local halo: BasePart? = nil
	if glowTex then
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromScale(size * 3.2, size * 3.2)
		bb.LightInfluence = 0
		bb.AlwaysOnTop = false
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Size = UDim2.fromScale(1, 1)
		img.Image = glowTex
		img.ImageColor3 = ctx.fx.color
		img.Parent = bb
		bb.Parent = head
	else
		halo = newPart(Enum.PartType.Ball, Vector3.one * 0.6, ctx.fx.color, CFrame.new(from), 0.65)
	end
	ctx.cometHead = head

	-- Schweif
	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, size * 0.45, 0); a0.Parent = head
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -size * 0.45, 0); a1.Parent = head
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.5
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.25, ctx.fx.color),
		ColorSequenceKeypoint.new(1, ctx.fx.color2),
	})
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.15) })
	local tailTex = texOf(ctx, s.tailTex)
	if tailTex then
		trail.Texture = tailTex
		trail.TextureMode = Enum.TextureMode.Stretch
	end
	trail.Enabled = false
	trail.Parent = head

	-- Funken vom Schweif (ein Emitter, Rate erst im Fall)
	local em = Instance.new("ParticleEmitter")
	em.Texture = texOf(ctx, s.sparkTex) or "rbxasset://textures/particles/sparkles_main.dds"
	em.EmissionDirection = Enum.NormalId.Back
	em.Rate = 0
	em.Speed = NumberRange.new(2, 6)
	em.SpreadAngle = Vector2.new(25, 25)
	em.Lifetime = NumberRange.new(0.3, 0.6)
	em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.18), NumberSequenceKeypoint.new(1, 0) })
	em.Color = ColorSequence.new(ctx.fx.color, ctx.fx.color2)
	em.LightEmission = 1
	em.Parent = head

	local parts: { BasePart } = { head, core }
	if halo then table.insert(parts, halo) end
	local cfs = table.create(#parts) :: { CFrame }
	local cloudY = s.cloudY
	local cloudDone = cloudY == nil or not extrasOn(ctx)
	local t0 = os.clock()
	local total = charge + fall
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local pos: Vector3
		local sz: number
		if t < charge then
			-- Funkeln: waechst, Helligkeit pulsiert 2x pro Sekunde (unter 3/s)
			local k = t / charge
			pos = from
			sz = 0.3 + (size * 0.55 - 0.3) * k * k
			head.Transparency = 0.1 + 0.3 * (0.5 + 0.5 * math.sin(t * math.pi * 4))
		else
			local k = math.clamp((t - charge) / fall, 0, 1)
			if not trail.Enabled then
				trail.Enabled = true
				head.Transparency = 0
				em.Rate = 45 * ctx.factor
			end
			if k < 0.7 then
				local q = k / 0.7
				pos = from:Lerp(slowAt, q * q)
			else
				pos = slowAt:Lerp(to, (k - 0.7) / 0.3)
			end
			sz = size * (0.55 + 0.45 * math.min(1, k * 1.5))
			if not cloudDone and pos.Y <= to.Y + cloudY then
				cloudDone = true
				-- Wolkenfetzen stieben auseinander (Beiwerk)
				for i = 1, 6 do
					local a = i / 6 * math.pi * 2
					local out = Vector3.new(math.cos(a), 0.15, math.sin(a))
					local puff = newPart(Enum.PartType.Ball, Vector3.one * 3, Color3.fromRGB(200, 205, 230), CFrame.new(pos), 0.45)
					puff.Material = Enum.Material.SmoothPlastic
					tween(puff, 0.7, { CFrame = CFrame.new(pos + out * 7), Size = Vector3.one * 5, Transparency = 1 })
					Debris:AddItem(puff, 0.8)
				end
			end
		end
		cfs[1] = CFrame.lookAt(pos, pos + dir)
		cfs[2] = CFrame.new(pos)
		if halo then cfs[3] = CFrame.new(pos) end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		head.Size = Vector3.one * sz
		core.Size = Vector3.one * sz * 0.5
		if halo then halo.Size = Vector3.one * sz * 2 end
		if t >= total or not head.Parent then
			if conn then conn:Disconnect() end
			em.Rate = 0
			trail.Enabled = false
			if ctx.cometHead == head then ctx.cometHead = nil end
			for _, p in parts do
				if p.Parent then fadeAndDestroy(p, 0.08) end
			end
		end
	end)
	Debris:AddItem(head, total + 1)
	Debris:AddItem(core, total + 1)
	if halo then Debris:AddItem(halo, total + 1) end
end

-- crater: im Boden gluehen strahlenfoermige Risse auf (Orange), kuehlen
-- langsam nach Violett ab und verblassen; dunkle Brandflaeche darunter.
--   at, radius, count (Risse), dur, tex (Krater-Bild)
BLOCKS.crater = function(ctx, s)
	local feet = groundAt(ctx, s.at) + Vector3.new(0, 0.07, 0)
	local r = radiusOf(s.radius, 6)
	local dur = s.dur or 2
	local fadeAt = math.max(0.2, dur - 0.45)
	local scorch = newPart(Enum.PartType.Cylinder, Vector3.new(0.05, 0.5, 0.5), Color3.fromRGB(28, 18, 36),
		CFrame.new(feet - Vector3.new(0, 0.02, 0)) * CFrame.Angles(0, 0, math.rad(90)), 0.25)
	scorch.Material = Enum.Material.SmoothPlastic
	tween(scorch, 0.15, { Size = Vector3.new(0.05, r * 1.1, r * 1.1) })
	tweenLater(scorch, fadeAt, 0.45, { Transparency = 1 })
	Debris:AddItem(scorch, dur + 0.1)
	local texture = texOf(ctx, s.tex)
	if texture then
		local plate = newPart(Enum.PartType.Block, Vector3.new(r * 2, 0.05, r * 2), ctx.fx.color, CFrame.new(feet), 1)
		local d = addDecal(plate, texture, Enum.NormalId.Top, ctx.fx.color)
		tweenLater(d, 0.2, dur * 0.6, { Color3 = ctx.fx.color2 }, Enum.EasingStyle.Sine)
		tweenLater(d, fadeAt, 0.45, { Transparency = 1 })
		Debris:AddItem(plate, dur + 0.1)
		return
	end
	-- Rueckfall: Risse als Neon-Striche mit einem Knick.
	local n = math.max(6, scaled(s.count or 10, ctx.factor))
	for i = 1, n do
		local a = (i / n) * math.pi * 2 + (math.random() - 0.5) * 0.3
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local bend = Vector3.new(math.cos(a + 0.35), 0, math.sin(a + 0.35))
		local len = r * (0.6 + math.random() * 0.4)
		local knee = feet + dir * len * 0.55
		local tip = knee + bend * len * 0.45
		local inner = groundStroke(ctx, feet + dir * 0.4, knee, 0.3, ctx.fx.color, 0, 0.12, fadeAt, nil)
		local outer = groundStroke(ctx, knee, tip, 0.18, ctx.fx.color, 0.1, 0.12, fadeAt, nil)
		for _, p in { inner, outer } do
			-- Glut kuehlt ab: Orange -> Violett
			if p then tweenLater(p, 0.25, dur * 0.6, { Color = ctx.fx.color2 }, Enum.EasingStyle.Sine) end
		end
	end
end

-- dust: Sternstaub fliegt im Bogen nach aussen (Schwerkraft am Emitter).
-- EIN Emitter, ein Stoss.
--   at, count, speed, dur, tex
BLOCKS.dust = function(ctx, s)
	local pos = at(ctx, s.at)
	local dur = s.dur or 1.0
	local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.5, Color3.new(1, 1, 1), CFrame.new(pos), 1)
	local em = Instance.new("ParticleEmitter")
	em.Texture = texOf(ctx, s.tex) or "rbxasset://textures/particles/sparkles_main.dds"
	em.EmissionDirection = Enum.NormalId.Top
	em.Rate = 0
	em.SpreadAngle = Vector2.new(65, 65)
	local sp = s.speed or 14
	em.Speed = NumberRange.new(sp * 0.6, sp)
	em.Acceleration = Vector3.new(0, -sp * 1.8, 0)
	em.Lifetime = NumberRange.new(dur * 0.7, dur)
	em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	em.Color = ColorSequence.new(Color3.new(1, 1, 1), ctx.fx.color2)
	em.LightEmission = 1
	em.Rotation = NumberRange.new(0, 360)
	em.Parent = anchor
	em:Emit(scaled(s.count, ctx.factor))
	Debris:AddItem(anchor, dur + 0.2)
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
	tween(cc, s.fade or 0.35, {
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
	local chaseEye: Vector3? = nil
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
		elseif style == "chase" then
			-- v16: schraeg hinter dem laufenden `comet` her; nach dem Aufprall
			-- bleibt das Auge stehen und schaut auf den Gegner.
			local head = ctx.cometHead
			if head and head.Parent then
				local cp = head.Position
				local toTarget = ctx.targetPos - cp
				local d = if toTarget.Magnitude > 0.1 then toTarget.Unit else Vector3.new(0, -1, 0)
				local sideV = d:Cross(Vector3.yAxis)
				if sideV.Magnitude < 0.1 then sideV = Vector3.xAxis else sideV = sideV.Unit end
				eye = cp - d * 16 + Vector3.new(0, 4, 0) + sideV * 7
				chaseEye = eye
				cam.CFrame = CFrame.lookAt(eye, cp + d * 6)
			else
				eye = chaseEye or (ctx.targetPos + Vector3.new(10, 8, 10))
				cam.CFrame = CFrame.lookAt(eye, ctx.targetPos)
			end
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

	local selfSize = sizeOf(req.attacker)
	local targetSize = sizeOf(req.target)
	local flat = Vector3.new(targetPos.X - selfPos.X, 0, targetPos.Z - selfPos.Z)
	local ctx: Ctx = {
		fx = fx,
		id = req.skillId,
		selfPos = selfPos,
		targetPos = targetPos,
		arena = req.center or (selfPos + targetPos) / 2,
		isOwner = isOwner,
		factor = budgetFactor() * (if isOwner then 1 else 0.6),
		cc = nil,
		sounds = {},
		selfModel = req.attacker,
		targetModel = req.target,
		selfSize = selfSize,
		targetSize = targetSize,
		selfFeet = selfPos - Vector3.new(0, selfSize.Y / 2, 0),
		targetFeet = targetPos - Vector3.new(0, targetSize.Y / 2, 0),
		fwd = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1),
		path = nil,
		cometHead = nil,
	}

	-- Schritte abspielen (volle Show oder eigenes Echo), je Schritt EIN
	-- verzoegerter Aufruf; Fehler eines Bausteins stoppen die Show nicht.
	local function run(steps: { SkillFXConfig.Step }, limit: number, echo: boolean)
		for _, step in steps do
			local block = BLOCKS[step.fx]
			if block and not (step.extra and not extrasOn(ctx)) and not (step.ownerOnly and not ctx.isOwner) then
				local st = step
				if echo and step.fx == "sound" then
					st = table.clone(step)
					st.echo = true
				end
				task.delay(math.min(step.t or 0, limit), function()
					local ok, err = pcall(block, ctx, st)
					if not ok then
						warn("[SkillFX]", req.skillId, step.fx, err)
					end
				end)
			end
		end
	end

	local echoSteps = fx.echo
	if not req.full and echoSteps then
		-- v16: eigenes Echo der Show (SkillFXConfig: `echo`).
		run(echoSteps, SkillFXConfig.TIERS[fx.tier].echo, true)
		return
	end

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
	run(fx.steps, maxDur, false)

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
