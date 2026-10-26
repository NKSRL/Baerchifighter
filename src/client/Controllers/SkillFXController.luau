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
local Audio           = require(ReplicatedStorage.Audio)
local AudioController = require(script.Parent.AudioController)

-- Audio-Rework 16.10.: letzter Start je Skill-Klang (Cooldown)
local _skillSoundAt: { [string]: number } = {}
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
	if typeof(step.color) == "Color3" then
		return step.color                          -- v16: feste Farbe je Schritt
	end
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
	far        : boolean,       -- Zuschauer ausserhalb SPECTATOR_DISTANCE: nur `global`-Schritte
	bonus      : boolean,       -- Finisher/Opener hat gegriffen (Server: SkillFXPlay.bonus)
	-- 23.10. (Leerenkrone): Lage und Groesse des tanzenden Klons aus `ascend`
	-- (Fusspunkt inkl. Drehung). crown, voidorb und Kamera "lowHero" folgen ihm.
	avatarCf   : CFrame?,
	avatarScale: number?,
	-- 25.10. (Sternenfall): Ebene des Unendlichkeitszeichens aus `starfall`
	-- (Mitte, rechts, Richtung zur Kamera, halbe Breite). shootingstars und
	-- Kamera "infinity" richten sich danach.
	infCenter  : Vector3?,
	infRight   : Vector3?,
	infNormal  : Vector3?,
	infSpan    : number?,
	-- 25.10. (Weltenende): Mitte, Kamera-Seite und Radius des Planeten aus
	-- `worldsend` (Kamera "worldsEnd").
	worldCenter: Vector3?,
	worldNormal: Vector3?,
	worldRadius: number?,
	-- 25.10. (Weltkugel): Start (os.clock), Mitte und Radius der Weltkugel
	-- aus `worldglobe` (Kamera "worldsEnd" faehrt dann zurueck).
	globeT0    : number?,
	globeCenter: Vector3?,
	globeRadius: number?,
	-- 25.10. (Fragenlawine): Luecke (waagerecht, zu Angreifer und Kamera) und
	-- Ringmitte aus `questionmarks`; Hutspitze, Landepunkt und Landezeit
	-- (os.clock) aus `riddler` (Kamera "riddle").
	riddleGap   : Vector3?,
	riddleRing  : Vector3?,
	riddleHatTop: Vector3?,
	riddleLand  : Vector3?,
	riddleLandT : number?,
	-- 25.10. (Hoellensiegel): Dreizackspitze des Teufel-Klons (hellwings),
	-- Mitte des Siegels unter dem Gegner (hellsigil), Lage und Kern-Teil der
	-- schwarzen Sonne (blacksun, fuer den Impact-Frame).
	hellTip    : Vector3?,
	hellCircle : Vector3?,
	hellSun    : Vector3?,
	hellSunPart: BasePart?,



	-- 25.10. (Pulsar-Nova): Schwebepunkt und Kamera-Seite (waagerecht) aus
	-- `pulsar`; Start (os.clock), Mitte und Radius der Feuerkuppel aus
	-- `firedome` (Kamera "pulsar" faehrt dann zurueck).
	pulsarHover: Vector3?,
	pulsarCam  : Vector3?,
	novaT0     : number?,
	novaCenter : Vector3?,
	novaRadius : number?,
	-- 25.10.2026 (Erste Baerchis): der tanzende Klon aus `moves` (fuer Lupe, Kopfhoerer).
	avatarModel: Model?,
	-- 26.10.2026 (Himmelsgericht): Mitte und Radius des Himmelstors aus `halogate`,
	-- Einschlagpunkt des Speers aus `seraphspear` (Kamera "seraph", `seraphmark`,
	-- `lightnuke`, Fall der Torringe).
	seraphGate : Vector3?,
	seraphGateR: number?,
	seraphHit  : Vector3?,
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
	local shardTex = texOf(ctx, s.tex)
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
		if shardTex then
			-- v16: Bild auf beiden grossen Flaechen (z. B. Schattenfetzen)
			p.Transparency = 1
			for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
				local d = addDecal(p, shardTex, face, p.Color)
				tweenLater(d, dur * 0.5, dur * 0.5, { Transparency = 1 })
			end
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

--------------------------------------------------------------------------------
-- v16 (Schemen-Show): Tinten-Klone des Baerchis, Verblassen, Stille, Schnitt.
-- Doku in SkillFXConfig ("BAUSTEINE").
--------------------------------------------------------------------------------

-- Was an einem Klon nichts zu suchen hat (Aussehen, Leben, Ton, Licht).
local CLONE_STRIP: { [string]: boolean } = {
	Decal = true, Texture = true, SurfaceAppearance = true, BillboardGui = true, SurfaceGui = true,
	Script = true, LocalScript = true, ModuleScript = true, Sound = true, ParticleEmitter = true,
	PointLight = true, SpotLight = true, SurfaceLight = true, Highlight = true, Humanoid = true,
	Fire = true, Smoke = true, Sparkles = true, Trail = true, Beam = true,
	Weld = true, WeldConstraint = true, Motor6D = true,
}

-- Ein tintenschwarzer Klon der Figur (lokal, nur auf diesem Rechner). Ohne
-- klonbares Modell: ein einfacher Kugel-Baerchi in derselben Groesse.
-- `feet` + `fwd` geben die Lage vor; `flat` (0..1) staucht die Tiefe
-- (flache Silhouette). Rueckgabe: Modell und Pivot relativ zu den Fuessen.
local function inkBear(source: Model?, size: Vector3, color: Color3, transparency: number,
	feet: Vector3, fwd: Vector3, flat: number?): (Model, CFrame)
	local frame = CFrame.lookAt(feet, feet + fwd)
	local m: Model? = nil
	if source and source.Parent then
		local ok, c = pcall(function() return (source :: Model):Clone() end)
		if ok and c then m = c end
	end
	if m then
		for _, d in m:GetDescendants() do
			if CLONE_STRIP[d.ClassName] then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.CastShadow = false
				d.Material = Enum.Material.SmoothPlastic
				d.Color = color
				d.Transparency = transparency
				d.LocalTransparencyModifier = 0
				if d:IsA("MeshPart") then
					pcall(function() (d :: any).TextureID = "" end)
				end
			end
		end
	else
		-- Rueckfall: Koerper, Kopf, zwei Ohren
		local bear = Instance.new("Model")
		local function ball(d: number, off: Vector3)
			local p = Instance.new("Part")
			p.Shape = Enum.PartType.Ball
			p.Size = Vector3.one * d
			prepPart(p, color, frame * CFrame.new(off), transparency)
			p.Material = Enum.Material.SmoothPlastic
			p.Parent = bear
		end
		ball(size.X * 0.8, Vector3.new(0, size.Y * 0.32, 0))
		ball(size.X * 0.55, Vector3.new(0, size.Y * 0.74, 0))
		ball(size.X * 0.2, Vector3.new(size.X * 0.2, size.Y * 0.95, 0))
		ball(size.X * 0.2, Vector3.new(-size.X * 0.2, size.Y * 0.95, 0))
		bear.WorldPivot = frame
		m = bear
	end
	local model = m :: Model
	if flat and flat < 1 then
		-- Tiefe (entlang der Blickrichtung) stauchen: Positionen und die
		-- Teil-Achse, die am ehesten nach vorn zeigt.
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				local rel = frame:ToObjectSpace(d.CFrame)
				d.CFrame = frame * (CFrame.new(rel.X, rel.Y, rel.Z * flat) * rel.Rotation)
				local look = frame.LookVector
				local ax = math.abs(d.CFrame.RightVector:Dot(look))
				local ay = math.abs(d.CFrame.UpVector:Dot(look))
				local az = math.abs(d.CFrame.LookVector:Dot(look))
				local sz = d.Size
				if ax >= ay and ax >= az then
					d.Size = Vector3.new(math.max(0.05, sz.X * flat), sz.Y, sz.Z)
				elseif ay >= az then
					d.Size = Vector3.new(sz.X, math.max(0.05, sz.Y * flat), sz.Z)
				else
					d.Size = Vector3.new(sz.X, sz.Y, math.max(0.05, sz.Z * flat))
				end
			end
		end
	end
	model.Name = "SkillFXInk"
	model.Parent = folder()
	return model, frame:ToObjectSpace(model:GetPivot())
end

local function fadeModel(model: Model, delaySeconds: number, seconds: number)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			tweenLater(d, delaySeconds, seconds, { Transparency = 1 }, Enum.EasingStyle.Sine)
		elseif d:IsA("Decal") then
			tweenLater(d, delaySeconds, seconds, { Transparency = 1 }, Enum.EasingStyle.Sine)
		end
	end
	Debris:AddItem(model, delaySeconds + seconds + 0.1)
end

-- Rauch-Emitter (EIN Emitter pro Effekt); `puff(pos, n)` stoesst an pos aus.
local function smokeAt(ctx: Ctx, texKey: string?, life: number): (Vector3, number) -> ()
	local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.3, Color3.new(), CFrame.new(ctx.selfPos), 1)
	local em = Instance.new("ParticleEmitter")
	em.Texture = texOf(ctx, texKey) or "rbxasset://textures/particles/smoke_main.dds"
	em.Rate = 0
	em.EmissionDirection = Enum.NormalId.Top
	em.Speed = NumberRange.new(0.6, 1.6)
	em.SpreadAngle = Vector2.new(60, 60)
	em.Drag = 1.5
	em.Lifetime = NumberRange.new(0.6, 1.0)
	em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 2.2) })
	em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	em.Color = ColorSequence.new(ctx.fx.color, ctx.fx.color2)
	em.LightEmission = 0
	em.Rotation = NumberRange.new(0, 360)
	em.RotSpeed = NumberRange.new(-25, 25)
	em.Parent = anchor
	Debris:AddItem(anchor, life + 1.2)
	local on = extrasOn(ctx)
	return function(pos: Vector3, n: number)
		if not on or not anchor.Parent then return end
		anchor.CFrame = CFrame.new(pos)
		em:Emit(scaled(n, ctx.factor))
	end
end

-- silhouette: der Schatten der Figur loest sich vom Boden und richtet sich
-- als flache, tintenschwarze Silhouette hinter ihr auf; zerfaellt dann in Rauch.
--   at, behind, rise, hold, dissolve, tex (Silhouette), smokeTex
BLOCKS.silhouette = function(ctx, s)
	local size = sizeAt(ctx, s.at)
	local fwd = if s.at == "target" then -ctx.fwd else ctx.fwd
	local feet = groundAt(ctx, s.at) - fwd * (s.behind or 1.4)
	local rise = s.rise or 1.0
	local hold = s.hold or 0.4
	local dissolve = s.dissolve or 0.4
	local model: Model
	local offset: CFrame
	local texture = texOf(ctx, s.tex)
	if texture then
		-- Bild-Silhouette: flache Platte mit dem Umriss (vorn und hinten).
		model = Instance.new("Model")
		local frame = CFrame.lookAt(feet, feet + fwd)
		local plate = Instance.new("Part")
		plate.Size = Vector3.new(size.X * 1.3, size.Y * 1.3, 0.05)
		prepPart(plate, ctx.fx.color, frame * CFrame.new(0, size.Y * 0.65, 0), 1)
		plate.Parent = model
		addDecal(plate, texture, Enum.NormalId.Front, ctx.fx.color)
		addDecal(plate, texture, Enum.NormalId.Back, ctx.fx.color)
		model.WorldPivot = frame
		model.Parent = folder()
		offset = CFrame.new()
	else
		model, offset = inkBear(if s.at == "target" then ctx.targetModel else ctx.selfModel, size,
			ctx.fx.color, 0.08, feet, fwd, 0.12)
	end
	local footFrame = CFrame.lookAt(feet, feet + fwd)
	-- liegt zuerst flach nach hinten auf dem Boden (wie ein Schatten)
	model:PivotTo(footFrame * CFrame.Angles(math.rad(90), 0, 0) * offset)
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		local k = math.clamp((os.clock() - t0) / rise, 0, 1)
		local e = 1 - (1 - k) ^ 3
		if model.Parent then
			model:PivotTo(footFrame * CFrame.Angles(math.rad(90) * (1 - e), 0, 0) * offset)
		end
		if k >= 1 or not model.Parent then
			if conn then conn:Disconnect() end
		end
	end)
	fadeModel(model, rise + hold, dissolve)
	local puff = smokeAt(ctx, s.smokeTex, rise + hold + dissolve)
	task.delay(rise + hold, function()
		puff(feet + Vector3.new(0, size.Y * 0.5, 0), 14)
	end)
end

-- shades: dunkle Pfuetzen rund um die Figur, aus jeder steigt gleichzeitig
-- ein Schatten-Baerchi aus Rauch (Tinten-Klon), der sie anschaut; nach
-- `fadeAt` loesen sie sich auf. EINE Verbindung fuer alle, EIN Emitter.
--   at, count, distance, pool, rise, fadeAt, dissolve, tex (Pfuetze), smokeTex
BLOCKS.shades = function(ctx, s)
	local center = groundAt(ctx, s.at)
	local size = ctx.selfSize                              -- Klone des eigenen Baerchis
	local n = s.count or 3
	local dist = s.distance or 3.4
	local poolR = s.pool or 1.7
	local rise = s.rise or 0.5
	local fadeAt = s.fadeAt or 1.2
	local dissolve = s.dissolve or 0.35
	local poolTex = texOf(ctx, s.tex)
	local puff = smokeAt(ctx, s.smokeTex, fadeAt + dissolve)
	local models: { Model } = {}
	local finals: { CFrame } = {}
	local offsets: { CFrame } = {}
	local spin = math.random() * math.pi * 2
	for i = 1, n do
		local a = spin + (i / n) * math.pi * 2
		local spot = center + Vector3.new(math.cos(a) * dist, 0, math.sin(a) * dist)
		-- Pfuetze
		local pool: BasePart
		if poolTex then
			pool = newPart(Enum.PartType.Block, Vector3.new(0.1, 0.04, 0.1), ctx.fx.color, CFrame.new(spot + Vector3.new(0, 0.05, 0)), 1)
			local d = addDecal(pool, poolTex, Enum.NormalId.Top, ctx.fx.color)
			tweenLater(d, fadeAt, dissolve, { Transparency = 1 })
			tween(pool, 0.15, { Size = Vector3.new(poolR * 2, 0.04, poolR * 2) })
		else
			pool = newPart(Enum.PartType.Cylinder, Vector3.new(0.04, 0.1, 0.1), ctx.fx.color,
				CFrame.new(spot + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)), 0.15)
			pool.Material = Enum.Material.SmoothPlastic
			tween(pool, 0.15, { Size = Vector3.new(0.04, poolR * 2, poolR * 2) })
			tweenLater(pool, fadeAt, dissolve, { Transparency = 1 })
		end
		Debris:AddItem(pool, fadeAt + dissolve + 0.1)
		-- Schatten-Baerchi, blickt zur Mitte
		local look = (center - spot)
		local fwd = if look.Magnitude > 0.1 then Vector3.new(look.X, 0, look.Z).Unit else ctx.fwd
		local m, off = inkBear(ctx.selfModel, size, ctx.fx.color, 0.25, spot, fwd, nil)
		local final = CFrame.lookAt(spot, spot + fwd)
		m:PivotTo(final * CFrame.new(0, -size.Y * 1.1, 0) * off)   -- noch unter dem Boden
		table.insert(models, m)
		table.insert(finals, final)
		table.insert(offsets, off)
		fadeModel(m, fadeAt, dissolve)
	end
	local t0 = os.clock()
	local start = 0.15                                     -- erst die Pfuetzen
	local puffed = false
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0 - start
		if t < 0 then return end
		if not puffed then
			puffed = true
			for i = 1, #models do puff(finals[i].Position, 6) end
		end
		local k = math.clamp(t / rise, 0, 1)
		local e = 1 - (1 - k) ^ 2
		for i, m in models do
			if m.Parent then
				m:PivotTo(finals[i] * CFrame.new(0, -size.Y * 1.1 * (1 - e), 0) * offsets[i])
			end
		end
		if k >= 1 then
			if conn then conn:Disconnect() end
		end
	end)
	task.delay(fadeAt, function()
		for i = 1, #models do puff(finals[i].Position + Vector3.new(0, size.Y * 0.5, 0), 8) end
	end)
end

-- vanish: die Figur wird blasser bis fast durchsichtig (LocalTransparency-
-- Modifier: nur auf diesem Rechner, nie zum Server repliziert) und steht bei
-- `back` Sekunden schlagartig wieder voll da. EINE Verbindung.
--   at, to (0..1), fadeIn, back
BLOCKS.vanish = function(ctx, s)
	local model = if s.at == "target" then ctx.targetModel else ctx.selfModel
	if not model then return end
	local goal = s.to or 0.85
	local fadeIn = s.fadeIn or 1.0
	local back = s.back or 2.0
	local parts: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then table.insert(parts, d) end
	end
	local function set(v: number)
		for _, p in parts do
			if p.Parent then p.LocalTransparencyModifier = v end
		end
	end
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t >= back or not model.Parent then
			if conn then conn:Disconnect() end
			set(0)                                         -- als waere er nie weg gewesen
			return
		end
		set(goal * math.clamp(t / fadeIn, 0, 1))
	end)
end

-- cut: ein einziger duenner, weisser Schnitt quer durch das Bild (jeder Client
-- richtet ihn an SEINER Kamera aus) durch den Gegner. Er bleibt `tearAt` s
-- stehen, dann reisst er auf: zwei Raender weichen auseinander, dazwischen
-- dunkles Violett.
--   at, length, width, draw, tearAt, tex (ausgefranste Schnittlinie)
-- Farbe des Schnitts, wenn der Finisher-Bonus gegriffen hat (helles Violett,
-- hebt sich vom Tintenschwarz der Show ab).
local BONUS_VIOLET = Color3.fromRGB(175, 115, 255)

BLOCKS.cut = function(ctx, s)
	local cam = workspace.CurrentCamera
	local pos = at(ctx, s.at or "target") + Vector3.new(0, 0.3, 0)
	local view = if cam then cam.CFrame else CFrame.lookAt(pos + Vector3.new(0, 4, 12), pos)
	local tilt = math.rad(s.angle or 18)
	local dir = (view.RightVector * math.cos(tilt) + view.UpVector * math.sin(tilt)).Unit
	local across = view.LookVector:Cross(dir).Unit             -- quer zur Linie, im Bild
	local len = s.length or 20
	local w = s.width or 0.12
	local draw = s.draw or 0.08
	local tearAt = s.tearAt or 0.4
	local fromPt = pos - dir * len / 2
	-- Y der Linie zeigt zur Kamera: die sichtbare Breite ist X
	local function frame(c: Vector3): CFrame
		return CFrame.lookAt(c, c + dir, view.LookVector)
	end
	local texture = texOf(ctx, s.tex)
	local line = newPart(Enum.PartType.Block, Vector3.new(w, 0.02, 0.05), Color3.new(1, 1, 1), frame(fromPt), if texture then 1 else 0)
	if texture then
		addDecal(line, texture, Enum.NormalId.Top)
		addDecal(line, texture, Enum.NormalId.Bottom)
	end
	tween(line, draw, { Size = Vector3.new(w, 0.02, len), CFrame = frame(pos) }, Enum.EasingStyle.Linear)
	Debris:AddItem(line, tearAt + 0.6)
	-- Finisher-Bonus (ctx.bonus): der Schnitt reisst violett auf statt weiss.
	local edgeColor = if ctx.bonus then (s.bonusColor or BONUS_VIOLET) else Color3.new(1, 1, 1)
	task.delay(tearAt, function()
		if not line.Parent then return end
		if ctx.bonus then line.Color = edgeColor end
		-- dunkler Spalt in der Mitte
		tween(line, 0.3, { Size = Vector3.new(w * 6, 0.02, len), Color = ctx.fx.color2, Transparency = 1 })
		for _, d in line:GetChildren() do
			if d:IsA("Decal") then tween(d, 0.2, { Transparency = 1 }) end
		end
		-- zwei weisse Raender weichen auseinander
		for _, sgn in { 1, -1 } do
			local edge = newPart(Enum.PartType.Block, Vector3.new(w * 0.6, 0.02, len), edgeColor, frame(pos), 0)
			tween(edge, 0.35, { CFrame = frame(pos + across * sgn * 0.9), Transparency = 1, Size = Vector3.new(w * 0.3, 0.02, len * 0.85) },
				Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			Debris:AddItem(edge, 0.45)
		end
	end)
end

--------------------------------------------------------------------------------
-- v16 (Omega-Show): Omega-Zeichen, Lichtpunkte aus vier Richtungen.
-- Doku in SkillFXConfig ("BAUSTEINE").
--------------------------------------------------------------------------------

-- Punkte eines Omega (Kreisbogen mit Luecke unten + zwei Fuesse) in der
-- Ebene (u, v) um c. Rueckgabe: Liste von Strecken {a, b}.
local function omegaStrokes(c: Vector3, u: Vector3, v: Vector3, r: number, n: number): { { Vector3 } }
	local out: { { Vector3 } } = {}
	local t0, t1 = math.rad(-48), math.rad(228)
	local prev = c + u * math.cos(t0) * r + v * math.sin(t0) * r
	local first = prev
	for i = 1, n do
		local t = t0 + (t1 - t0) * i / n
		local p = c + u * math.cos(t) * r + v * math.sin(t) * r
		table.insert(out, { prev, p })
		prev = p
	end
	-- Fuesse: von den Bogen-Enden waagerecht nach aussen
	table.insert(out, { first, first + u * r * 0.55 })
	table.insert(out, { prev, prev - u * r * 0.55 })
	return out
end

-- omega: ein leuchtendes Omega (Ω), Strich fuer Strich gezeichnet.
--   sky   : hoch ueber der Arena (`lift`), zur Kamera DIESES Clients gedreht;
--           bei `pullAt` zieht es sich mit einem Ruck auf die Pfote des
--           Baerchis zusammen (`jerk` s) und endet in einem weissen Punkt.
--   brand : flach auf dem Boden unter `at` eingebrannt, gluehend weiss ->
--           Zweitfarbe, verblasst langsam (`fade` s ab `burnFor`).
--   mode ("sky"|"brand"), at, radius, lift, segments, draw, pullAt, jerk, burnFor, fade, width, tex
BLOCKS.omega = function(ctx, s)
	local mode = s.mode or "sky"
	local r = s.radius or 6
	local n = math.max(10, scaled(s.segments or 18, ctx.factor))
	local draw = s.draw or 0.8
	local w = s.width or r * 0.12
	local th = if mode == "brand" then 0.04 else w          -- Brandzeichen: flach
	local center: Vector3
	local u: Vector3
	local v: Vector3
	if mode == "brand" then
		center = groundAt(ctx, s.at or "target") + Vector3.new(0, 0.08, 0)
		u = ctx.fwd:Cross(Vector3.yAxis)
		v = ctx.fwd
	else
		center = at(ctx, s.at or "arena") + Vector3.new(0, s.lift or 34, 0)
		local cam = workspace.CurrentCamera
		local look = if cam then cam.CFrame.LookVector else ctx.fwd
		local flatLook = Vector3.new(look.X, 0, look.Z)
		local f = if flatLook.Magnitude > 0.05 then flatLook.Unit else ctx.fwd
		u = f:Cross(Vector3.yAxis)            -- waagerecht, quer zum Blick
		v = Vector3.yAxis
	end
	local normal = u:Cross(v)
	local col = pickColor(s, ctx.fx)
	local parts: { BasePart } = {}
	local texture = texOf(ctx, s.tex)
	if texture then
		-- Mit Bild: EINE Platte mit dem Omega (beidseitig). Beim Brandzeichen
		-- liegt sie flach (u, v waagerecht), sonst steht sie senkrecht.
		local plate = newPart(Enum.PartType.Block, Vector3.new(0.05, 0.05, 0.05), col,
			CFrame.fromMatrix(center, u, v), 1)
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			local d = addDecal(plate, texture, face, col)
			if mode == "brand" then
				tweenLater(d, s.burnFor or 0.4, s.fade or 1.5, { Transparency = 1 }, Enum.EasingStyle.Sine)
			end
		end
		tween(plate, draw, { Size = Vector3.new(r * 2.7, r * 2.7, 0.05) }, Enum.EasingStyle.Sine)
		table.insert(parts, plate)
	else
		for i, seg in omegaStrokes(center, u, v, r, n) do
			local a, b = seg[1], seg[2]
			local len = (b - a).Magnitude
			local rot = CFrame.lookAt(a, b, normal).Rotation
			local p = newPart(Enum.PartType.Block, Vector3.new(w, th, 0.05), col, CFrame.new(a) * rot, 0)
			tweenLater(p, (i - 1) / (n + 2) * draw, draw / (n + 2) + 0.05, {
				Size = Vector3.new(w, th, len + w * 0.6),
				CFrame = CFrame.new((a + b) / 2) * rot,
			}, Enum.EasingStyle.Linear)
			if mode == "brand" then
				tweenLater(p, s.burnFor or 0.4, s.fade or 1.5, { Color = ctx.fx.color2 }, Enum.EasingStyle.Sine)
				tweenLater(p, s.burnFor or 0.4, s.fade or 1.5, { Transparency = 1 }, Enum.EasingStyle.Sine)
			end
			table.insert(parts, p)
		end
	end
	if mode == "brand" then
		for _, p in parts do Debris:AddItem(p, (s.burnFor or 0.4) + (s.fade or 1.5) + 0.1) end
		return
	end
	-- Ruck auf die Pfote
	local pullAt = s.pullAt or (draw + 1)
	local jerk = s.jerk or 0.22
	local size = ctx.selfSize
	local paw = ctx.selfPos + ctx.fwd * size.Z * 0.45 + Vector3.new(0, size.Y * 0.05, 0)
	for _, p in parts do Debris:AddItem(p, pullAt + jerk + 0.1) end
	task.delay(pullAt, function()
		for _, p in parts do
			if p.Parent then
				tween(p, jerk, { CFrame = CFrame.new(paw) * (p.CFrame - p.CFrame.Position), Size = Vector3.one * 0.08 },
					Enum.EasingStyle.Quart, Enum.EasingDirection.In)
				for _, d in p:GetChildren() do
					if d:IsA("Decal") then tween(d, jerk, { Transparency = 0.3 }) end
				end
			end
		end
		-- reines Weiss als hellster Punkt an der Pfote
		local core = newPart(Enum.PartType.Ball, Vector3.one * 0.2, Color3.new(1, 1, 1), CFrame.new(paw), 0)
		tweenLater(core, jerk * 0.8, 0.12, { Size = Vector3.one * 2.4 }, Enum.EasingStyle.Quad)
		tweenLater(core, jerk * 0.8 + 0.12, 0.25, { Transparency = 1 })
		Debris:AddItem(core, jerk + 0.5)
	end)
end

-- converge: Lichtpunkte fliegen aus vier Himmelsrichtungen in einen Punkt
-- hoch ueber der Arena (`lift`, wie `omega`). Eine Farbe je Richtung
-- (`colors`), Schweif per Trail; Starts per Tween-Verzoegerung.
--   colors, perSide, from (Abstand), lift, flight, stagger, tex
BLOCKS.converge = function(ctx, s)
	local goal = at(ctx, s.at or "arena") + Vector3.new(0, s.lift or 34, 0)
	local colors: { Color3 } = s.colors or { ctx.fx.color, ctx.fx.color2 }
	local per = math.max(2, scaled(s.perSide or 4, ctx.factor))
	local dist = s.from or 45
	local flight = s.flight or 0.9
	local stagger = s.stagger or 0.18
	local texture = texOf(ctx, s.tex)
	local base = at(ctx, "arena")
	for side = 1, 4 do
		local col = colors[(side - 1) % #colors + 1]
		local a = (side - 1) * math.pi / 2
		for j = 1, per do
			local aj = a + (math.random() - 0.5) * 0.35
			local from = base + Vector3.new(math.cos(aj) * dist, 10 + math.random() * 14, math.sin(aj) * dist)
			local orb = newPart(Enum.PartType.Ball, Vector3.one * 0.7, col, CFrame.new(from), 0)
			local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0, 0.3, 0); a0.Parent = orb
			local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0, -0.3, 0); a1.Parent = orb
			local trail = Instance.new("Trail")
			trail.Attachment0 = a0
			trail.Attachment1 = a1
			trail.Lifetime = 0.35
			trail.LightEmission = 1
			trail.FaceCamera = true
			trail.Color = ColorSequence.new(col)
			trail.Transparency = NumberSequence.new(0.1, 1)
			trail.Parent = orb
			if texture then
				local bb = Instance.new("BillboardGui")
				bb.Size = UDim2.fromScale(2.2, 2.2)
				bb.LightInfluence = 0
				local img = Instance.new("ImageLabel")
				img.BackgroundTransparency = 1
				img.Size = UDim2.fromScale(1, 1)
				img.Image = texture
				img.ImageColor3 = col
				img.Parent = bb
				bb.Parent = orb
			end
			local delaySeconds = (j - 1) * stagger + (side - 1) * 0.05
			tweenLater(orb, delaySeconds, flight, { CFrame = CFrame.new(goal) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			tweenLater(orb, delaySeconds + flight, 0.12, { Transparency = 1 })
			Debris:AddItem(orb, delaySeconds + flight + 0.25)
		end
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

-- silence: der Ton geht fuer `dur` Sekunden ganz aus (nur Besitzer). Alle
-- gerade spielenden Klaenge werden lokal stumm und danach auf ihre
-- Lautstaerke zurueckgesetzt (ausser der Server hat sie inzwischen geaendert).
BLOCKS.silence = function(ctx, s)
	if not ctx.isOwner then return end
	local dur = s.dur or 0.3
	local level = math.clamp(s.level or 0, 0, 1)          -- v16: 0 = stumm, 0.15 = ganz leise
	local muted: { { snd: Sound, vol: number } } = {}
	local roots: { Instance } = { workspace, game:GetService("SoundService") }
	local gui = player:FindFirstChildOfClass("PlayerGui")
	if gui then table.insert(roots, gui) end
	for _, root in roots do
		for _, d in root:GetDescendants() do
			if d:IsA("Sound") and d.IsPlaying and d.Volume > 0 then
				table.insert(muted, { snd = d, vol = d.Volume })
				d.Volume = d.Volume * level
			end
		end
	end
	task.delay(dur, function()
		for _, m in muted do
			if m.snd.Parent and math.abs(m.snd.Volume - m.vol * level) < 1e-3 then
				m.snd.Volume = m.vol
			end
		end
	end)
end

-- spotlight: die eigene Figur leuchtet, waehrend die Welt entfaerbt ist
-- (Highlight, lokal, nur Besitzer). Roblox kann einzelne Objekte NICHT vom
-- Farbfilter ausnehmen — das Leuchten haelt die Figur aber klar heller als
-- die graue Welt.
--   at, dur, fill (Farbe), strength (0..1)
BLOCKS.spotlight = function(ctx, s)
	if not ctx.isOwner then return end
	local model = if s.at == "target" then ctx.targetModel else ctx.selfModel
	if not model then return end
	local dur = s.dur or 2
	local h = Instance.new("Highlight")
	h.Adornee = model
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.FillColor = s.fill or Color3.fromRGB(255, 245, 225)
	h.OutlineColor = Color3.new(1, 1, 1)
	h.FillTransparency = 1
	h.OutlineTransparency = 1
	h.Parent = folder()
	local strength = s.strength or 0.35
	tween(h, 0.5, { FillTransparency = 1 - strength, OutlineTransparency = 0.3 })
	tweenLater(h, math.max(0.5, dur - 0.4), 0.4, { FillTransparency = 1, OutlineTransparency = 1 })
	Debris:AddItem(h, dur + 0.1)
end

-- wipe: ein Farbspektrum laeuft als Welle durchs Bild; dahinter bekommt die
-- Welt ihre Farbe zurueck (Farbfilter -> neutral). Nur Besitzer.
--   dur, tex (Spektrum-Verlauf; ohne Bild: UIGradient)
BLOCKS.wipe = function(ctx, s)
	if not ctx.isOwner then return end
	local dur = s.dur or 0.9
	local gui = Instance.new("ScreenGui")
	gui.Name = "SkillFXWipe"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 49
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	local texture = texOf(ctx, s.tex)
	local band: GuiObject
	if texture then
		local img = Instance.new("ImageLabel")
		img.Image = texture
		img.BackgroundTransparency = 1
		img.ImageTransparency = 0.35
		img.ScaleType = Enum.ScaleType.Stretch
		band = img
	else
		local f = Instance.new("Frame")
		f.BackgroundColor3 = Color3.new(1, 1, 1)
		f.BackgroundTransparency = 0.35
		f.BorderSizePixel = 0
		local g = Instance.new("UIGradient")
		local keys = {}
		for i, c in RAINBOW do
			table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#RAINBOW - 1), c))
		end
		g.Color = ColorSequence.new(keys)
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.2),
			NumberSequenceKeypoint.new(0.75, 0.2), NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = f
		band = f
	end
	band.AnchorPoint = Vector2.new(0.5, 0.5)
	band.Size = UDim2.fromScale(0.45, 1.6)
	band.Rotation = 12
	band.Position = UDim2.fromScale(-0.3, 0.5)
	band.Parent = gui
	tween(band, dur, { Position = UDim2.fromScale(1.3, 0.5) }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	Debris:AddItem(gui, dur + 0.1)
	-- Farbe kommt hinter der Welle zurueck
	local cc = ensureCC(ctx)
	tweenLater(cc, dur * 0.2, dur * 0.8, { Saturation = 0, Brightness = 0, Contrast = 0, TintColor = Color3.new(1, 1, 1) })
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
	f.BackgroundColor3 = if typeof(s.tint) == "Color3" then s.tint else Color3.new(1, 1, 1)  -- 25.10.: `tint` (Hoellensiegel: pink)
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
	local seraphSide = 0   -- 26.10. (Himmelsgericht): Kamera-Seite, einmal beim Start
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
		elseif style == "orbitSelf" then
			-- v16: langsamer Halbkreis um den eigenen Baerchi, Blick leicht
			-- nach oben (Baerchi und Himmel im Bild)
			local a = math.pi * 0.25 + k * math.pi
			local me = ctx.selfPos
			eye = me + Vector3.new(math.cos(a) * 13, 3.5, math.sin(a) * 13)
			cam.CFrame = CFrame.lookAt(eye, me + Vector3.new(0, 4 + 3 * k, 0))
		elseif style == "lowHero" then
			-- 23.10. (Leerenkrone): Untersicht von vorn-seitlich auf den
			-- aufsteigenden Baerchi (folgt dem `ascend`-Klon), faehrt langsam heran.
			local f = ctx.avatarCf or CFrame.lookAt(ctx.selfFeet, ctx.selfFeet + ctx.fwd)
			local head = f.Position + Vector3.new(0, ctx.selfSize.Y * (ctx.avatarScale or 1) * 0.75, 0)
			local sideV = ctx.fwd:Cross(Vector3.yAxis)
			sideV = if sideV.Magnitude < 0.1 then Vector3.xAxis else sideV.Unit
			eye = ctx.selfFeet + ctx.fwd * (6 - 2 * k) + sideV * (10 - 3 * k) + Vector3.new(0, 1.0 + 1.4 * k, 0)
			cam.CFrame = CFrame.lookAt(eye, head + Vector3.new(0, 1.2, 0))
		elseif style == "beamUp" then
			-- 25.10. (Entfuehrungsstrahl): tief neben dem Gegner, Blick schraeg
			-- nach oben auf Strahl und UFO (folgt dem `saucer`-Klon), faehrt heran.
			local tf = ctx.targetFeet
			local sideV = ctx.fwd:Cross(Vector3.yAxis)
			sideV = if sideV.Magnitude < 0.1 then Vector3.xAxis else sideV.Unit
			local ufo = if ctx.avatarCf then ctx.avatarCf.Position else tf + Vector3.new(0, 8, 0)
			eye = tf + sideV * (13 - 3 * k) - ctx.fwd * (3 - k) + Vector3.new(0, 1.0 + 1.0 * k, 0)
			cam.CFrame = CFrame.lookAt(eye, (tf + Vector3.new(0, 1.5, 0)):Lerp(ufo, 0.5))
		elseif style == "infinity" then
			-- 25.10. (Sternenfall): tief vor dem Unendlichkeitszeichen (auf der
			-- Seite der Spielkamera, `starfall` legt die Ebene fest), faehrt etwas
			-- zurueck; der Blick wandert vom Zeichen zum Gegner (Sturz).
			local c = ctx.infCenter or (center + Vector3.new(0, 10, 0))
			local n = ctx.infNormal or Vector3.new(0, 0, 1)
			local base = (ctx.selfFeet + ctx.targetFeet) / 2
			eye = base + n * (24 + 5 * k) + Vector3.new(0, 2.2 + 1.3 * k, 0)
			local w = math.clamp((k - 0.55) / 0.25, 0, 1)
			w = 0.5 - 0.5 * math.cos(math.pi * w)
			cam.CFrame = CFrame.lookAt(eye, c:Lerp(ctx.targetPos + Vector3.new(0, 1.5, 0), w * 0.75))
		elseif style == "worldsEnd" then
			-- 25.10. (Weltenende): tief auf der Seite der Spielkamera (die
			-- Richtung legt `worldsend` beim Start fest), Blick schraeg hoch zu
			-- Planet und Baerchi; folgt dem Planeten beim Sturz, faehrt heran.
			local n = ctx.worldNormal or Vector3.new(0, 0, 1)
			local sideV = Vector3.yAxis:Cross(n)
			sideV = if sideV.Magnitude < 0.1 then Vector3.xAxis else sideV.Unit
			local base = (ctx.selfFeet + ctx.targetFeet) / 2
			local c = ctx.worldCenter or (base + Vector3.new(0, 11, 0))
			local r = ctx.worldRadius or 3.4
			eye = base + n * (26 - 7 * k) + sideV * (4 - 2 * k) + Vector3.new(0, 2.4 + 1.6 * k, 0)
			local look = c + Vector3.new(0, r * 0.8, 0)
			-- Weltkugel (`worldglobe`): zurueck und hoch, bis die ganze Kugel im Bild ist
			local g0 = ctx.globeT0
			if g0 then
				local q = math.clamp((os.clock() - g0) / 0.38, 0, 1)
				q = 1 - (1 - q) ^ 3
				local gc = ctx.globeCenter or base
				local gr = ctx.globeRadius or 20
				eye = eye:Lerp(gc + n * (gr * 1.85) + sideV * 4 + Vector3.new(0, gr * 0.5, 0), q)
				look = look:Lerp(gc + Vector3.new(0, gr * 0.12, 0), q)
			end
			cam.CFrame = CFrame.lookAt(eye, look)


		elseif style == "riddle" then
			-- 25.10. (Fragenlawine): tief auf der Seite der Luecke (Angreifer +
			-- Spielkamera, `questionmarks` legt sie beim Start fest), Blick hoch
			-- auf den Fragezeichen-Wirbel, kreist langsam; ab dem "Aha" zum
			-- `riddler`-Klon und mit ihm herab; nach der Landung zurueck und
			-- hoch, bis das riesige "!" samt Kaefig im Bild ist.
			local g = ctx.riddleGap or -ctx.fwd
			local sideV = Vector3.yAxis:Cross(g)
			sideV = if sideV.Magnitude < 0.1 then Vector3.xAxis else sideV.Unit
			local ring = ctx.riddleRing or ctx.targetFeet
			local a = math.rad(24 - 40 * k)
			local dir = g * math.cos(a) + sideV * math.sin(a)
			eye = ring + dir * (15.5 - 2.5 * k) + Vector3.new(0, 1.4 + 1.2 * k, 0)
			local look = ring + Vector3.new(0, 4.4, 0)
			local av = ctx.avatarCf
			if av then
				local body = av.Position + Vector3.new(0, ctx.selfSize.Y * (ctx.avatarScale or 1) * 0.5, 0)
				local w = math.clamp((k - 0.4) / 0.2, 0, 1)
				w = 1 - (1 - w) ^ 3
				look = look:Lerp(body, w * 0.7)
			end
			local lt = ctx.riddleLandT
			if lt then
				local q = math.clamp((os.clock() - lt) / 0.45, 0, 1)
				q = 1 - (1 - q) ^ 3
				local landP = ctx.riddleLand or ring
				eye = eye:Lerp(landP + g * 21 + sideV * 3 + Vector3.new(0, 5.5, 0), q)
				look = look:Lerp(landP + Vector3.new(0, 5.2, 0), q)
			end
			cam.CFrame = CFrame.lookAt(eye, look)

		elseif style == "pulsar" then
			-- 25.10. (Pulsar-Nova): tief auf der Seite der Spielkamera (`pulsar`
			-- legt sie beim Start fest), Blick hoch auf den kreisenden
			-- Leuchtturm - die Lichtkegel fegen ueber die Kamera; folgt dem
			-- Neutronenstern im Flug; nach dem Einschlag (`firedome`) zurueck
			-- und hoch auf die ganze Feuerkuppel.
			local n = ctx.pulsarCam or Vector3.new(0, 0, 1)
			local sideV = Vector3.yAxis:Cross(n)
			sideV = if sideV.Magnitude < 0.1 then Vector3.xAxis else sideV.Unit
			local hv = ctx.pulsarHover or (ctx.selfFeet + Vector3.new(0, 7, 0))
			eye = hv + n * (12.5 - 2 * k) + sideV * (2.5 + 3 * k) + Vector3.new(0, -3.6 + 1.2 * k, 0)
			local look = hv + Vector3.new(0, 0.8, 0)
			local av = ctx.avatarCf
			if av then
				local w = math.clamp((k - 0.5) / 0.14, 0, 1)
				w = 1 - (1 - w) ^ 3
				look = look:Lerp(av.Position, w)
				eye = eye:Lerp((hv + ctx.targetPos) / 2 + n * 15 + Vector3.new(0, 2.5, 0), w * 0.85)
			end
			local d0 = ctx.novaT0
			if d0 then
				local q = math.clamp((os.clock() - d0) / 0.42, 0, 1)
				q = 1 - (1 - q) ^ 3
				local dc = ctx.novaCenter or ctx.targetPos
				local dr = ctx.novaRadius or 8
				eye = eye:Lerp(dc + n * (dr * 3.1) + sideV * 3 + Vector3.new(0, dr * 0.9, 0), q)
				look = look:Lerp(dc + Vector3.new(0, dr * 0.25, 0), q)
			end
			cam.CFrame = CFrame.lookAt(eye, look)

		elseif style == "seraph" then
			-- 26.10. (Himmelsgericht): tief vorn-seitlich beim Seraph (auf der Seite
			-- der Spielkamera, aus `oldCf`), folgt dem `moves`-Klon in die Hoehe -
			-- der Blick kippt hoch, das Himmelstor rueckt ins Bild; waehrend des
			-- Zielens langsamer Push-in; im Sturz schwenkt der Blick mit dem Klon
			-- zum Gegner (Peitsche); am Einschlag harter Schnitt in eine tiefe
			-- Untersicht neben dem Speer (Hitstop, Beben), dann zurueck (Custom).
			local sideV = ctx.fwd:Cross(Vector3.yAxis)
			sideV = if sideV.Magnitude < 0.1 then Vector3.xAxis else sideV.Unit
			if seraphSide == 0 then
				seraphSide = if (oldCf.Position - center):Dot(sideV) >= 0 then 1 else -1
			end
			local sv = sideV * seraphSide
			local f = ctx.avatarCf or CFrame.lookAt(ctx.selfFeet, ctx.selfFeet + ctx.fwd)
			local sc = ctx.avatarScale or 1
			local body = f.Position + Vector3.new(0, ctx.selfSize.Y * sc * 0.5, 0)
			local hitP = ctx.seraphHit or ctx.targetFeet
			local look: Vector3
			if k < 0.89 then
				-- Aufstieg (k 0..0,34): Auge steigt mit, Blick kippt hoch; Zielen (0,34..0,79): Push-in
				local q1 = math.clamp(k / 0.34, 0, 1)
				local q2 = math.clamp((k - 0.34) / 0.45, 0, 1)
				local dist = 9 - 2 * q1 - 1.5 * q2
				local high = 1.2 + 2.6 * q1 + 1.4 * q2
				eye = ctx.selfFeet + ctx.fwd * (6 - 1.5 * q1) + sv * dist + Vector3.new(0, high, 0)
				look = body + Vector3.new(0, 0.6, 0)
				-- Sturz (0,79..0,89): der Blick peitscht mit dem Klon zum Gegner
				local q3 = math.clamp((k - 0.79) / 0.1, 0, 1)
				if q3 > 0 then
					look = look:Lerp(hitP + Vector3.new(0, 1.5, 0), q3 * q3)
				end
			else
				-- Einschlag (ab 0,89): harter Schnitt, tiefe Untersicht neben dem Speer
				eye = hitP + sv * 6.5 - ctx.fwd * 4 + Vector3.new(0, 0.9, 0)
				look = hitP + Vector3.new(0, 3.2 + 6 * (k - 0.89), 0)
			end
			cam.CFrame = CFrame.lookAt(eye, look)
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
	-- Audio-Rework 16.10.: Bibliotheksname → Audio.SFX (weiche, selbst erzeugte
	-- Klaenge). Cooldown, Stimmen-Limit und Tonhoehen-Fenster verhindern, dass
	-- viele Faehigkeiten gleichzeitig zu Rauschen werden.
	local libraryName = SkillFXConfig.SOUND_LIBRARY[key]
	local def = if libraryName then Audio.SFX[libraryName] else nil
	local id = if libraryName then Audio.sfxId(libraryName) else (if tonumber(key) then "rbxassetid://" .. key else key)
	if id == "" then return end
	if def then
		local now = os.clock()
		local last = _skillSoundAt[libraryName :: string]
		if last and now - last < def.cooldown then return end
		if not AudioController.takeWorldSlot() then return end
		_skillSoundAt[libraryName :: string] = now
	end
	local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.1, Color3.new(), CFrame.new(ctx.selfPos), 1)
	local snd = Instance.new("Sound")
	snd.SoundId = id
	-- v15: leiser, Echo noch leiser, nach MAX_SECONDS ausgeblendet
	-- (SkillFXConfig.SOUND). Die Grundlautstaerke kommt aus Audio.SFX.
	local cfg = SkillFXConfig.SOUND
	local volume = (if def then def.volume else 0.3) * (if ctx.isOwner then cfg.OWNER_VOLUME else cfg.SPECTATOR_VOLUME)
	if s.echo then
		volume *= cfg.ECHO_FACTOR
	end
	snd.Volume = volume
	snd.SoundGroup = AudioController.sfxGroup()
	local rawPitch = (ctx.fx.pitch or 1) * (if slot == "charge" then 0.9 elseif slot == "impact" then 0.8 else 1)
	snd.PlaybackSpeed = AudioController.clampWorldPitch(rawPitch) * (1 + (math.random() * 2 - 1) * (if def then def.pitch else 0))
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
-- 23.10. Krone der Leere (VoidCrown). Der Baerchi holt aus, steigt gekroent
-- in die Luft, ueber ihm waechst eine Kugel aus Leere, rundherum oeffnen sich
-- Augen; dann stuerzt er sich kopfueber auf den Gegner und Obsidian-Dornen
-- brechen aus dem Boden. Doku in SkillFXConfig ("BAUSTEINE", Leerenkrone).
--------------------------------------------------------------------------------

local TAU = math.pi * 2
local VOID_OBSIDIAN = Color3.fromRGB(18, 10, 32)
local PARK = CFrame.new(0, 2000, 0)              -- Ablage fuer noch unsichtbare Teile
local SPARK_TEX = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEX = "rbxasset://textures/particles/smoke_main.dds"

local function lerpN(a: number, b: number, k: number): number
	return a + (b - a) * k
end

local function easeOutBack(k: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	return 1 + c3 * (k - 1) ^ 3 + c1 * (k - 1) ^ 2
end

local function easeOutCubic(k: number): number
	return 1 - (1 - k) ^ 3
end

-- Fusslage (mit Drehung) des tanzenden Klons aus `ascend`; ohne ihn die
-- eigenen Fuesse mit Blick zum Gegner.
local function avatarFrame(ctx: Ctx): CFrame
	return ctx.avatarCf or CFrame.lookAt(ctx.selfFeet, ctx.selfFeet + ctx.fwd)
end

-- Bild-Schleife, die sich bei einem Fehler selbst beendet (statt in jedem
-- Bild neu zu werfen) und `cleanup` in jedem Fall genau einmal ausfuehrt.
-- `step(t, dt)` gibt true zurueck, wenn sie fertig ist.
local function runLoop(name: string, step: (number, number) -> boolean, cleanup: (() -> ())?)
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	local finished = false
	local function finish()
		if finished then return end
		finished = true
		if conn then conn:Disconnect() end
		if cleanup then
			local ok, err = pcall(cleanup)
			if not ok then warn("[SkillFX]", name, "Aufraeumen:", err) end
		end
	end
	conn = RunService.RenderStepped:Connect(function(dt: number)
		local ok, res = pcall(step, os.clock() - t0, dt)
		if not ok then
			warn("[SkillFX]", name, res)
			finish()
		elseif res then
			finish()
		end
	end)
end

-- Ein kurzer Partikel-Stoss an `pos` (EIN Emitter, danach weg).
local function burstAt(ctx: Ctx, pos: Vector3, n: number, speed: number, color: Color3, smoke: boolean?)
	local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, color, CFrame.new(pos), 1)
	local em = Instance.new("ParticleEmitter")
	em.Texture = if smoke then SMOKE_TEX else SPARK_TEX
	em.Rate = 0
	em.Speed = NumberRange.new(speed * 0.4, speed)
	em.SpreadAngle = Vector2.new(180, 180)
	em.Lifetime = NumberRange.new(0.4, 0.9)
	em.Drag = if smoke then 3 else 1.5
	em.Size = if smoke
		then NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3.4) })
		else NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, if smoke then 0.35 else 0), NumberSequenceKeypoint.new(1, 1) })
	em.Color = if smoke then ColorSequence.new(color, ctx.fx.color2) else ColorSequence.new(Color3.fromRGB(240, 225, 255), color)
	em.LightEmission = if smoke then 0.3 else 1
	em.Rotation = NumberRange.new(0, 360)
	em.RotSpeed = NumberRange.new(-40, 40)
	em.Parent = anchor
	em:Emit(scaled(n, ctx.factor))
	Debris:AddItem(anchor, 1.6)
end

-- "Rig": Teile, die von unten wachsen (Wuchs g = 0..1, Grundlinie bleibt).
-- `frame` = Lage der Grundlinie relativ zum Pivot, `size` = volle Groesse.
type RigPart = {
	p: BasePart, frame: CFrame, size: Vector3, delay: number, tr: number, g: number,
	fixed: boolean?, lt: number?,
	w: CFrame?, v: Vector3?, axis: Vector3?, spin: number?,
}

local function rigPart(rig: { RigPart }, p: BasePart, frame: CFrame, size: Vector3, delay: number, tr: number, fixed: boolean?)
	p.Size = if fixed then size else Vector3.new(size.X, 0.05, size.Z)
	p.Transparency = 1
	table.insert(rig, { p = p, frame = frame, size = size, delay = delay, tr = tr, g = -1, fixed = fixed, lt = 1 })
end

local function rigTr(r: RigPart, v: number)
	if r.lt ~= v then
		r.lt = v
		r.p.Transparency = v
	end
end

-- Ein Dorn als Klinge aus zwei Keilen, Spitze oben. `frame` = Mitte der
-- Grundlinie; Klingenebene = lokale Y/Z-Ebene, Dicke entlang X.
local function addBlade(rig: { RigPart }, frame: CFrame, thick: number, height: number, halfBase: number,
	color: Color3, material: Enum.Material, delay: number)
	for side = -1, 1, 2 do
		local w = Instance.new("WedgePart")
		prepPart(w, color, PARK, 1)
		w.Material = material
		local f = frame * CFrame.new(0, 0, side * halfBase / 2)
			* (if side > 0 then CFrame.Angles(0, math.pi, 0) else CFrame.identity)
		rigPart(rig, w, f, Vector3.new(thick, height, halfBase), delay, 0)
	end
end

-- Alle Teile auf einmal setzen (BulkMoveTo). `gOf(r)` = Wuchs, `alpha` = Sichtbarkeit.
local function rigApply(rig: { RigPart }, pivot: CFrame, gOf: (RigPart) -> number, alpha: number)
	local parts: { BasePart } = table.create(#rig)
	local cfs: { CFrame } = table.create(#rig)
	for i, r in rig do
		local g = math.clamp(gOf(r), 0, 1.25)
		if math.abs(g - r.g) > 0.002 then
			r.g = g
			if not r.fixed then
				r.p.Size = Vector3.new(r.size.X, math.max(0.05, r.size.Y * g), r.size.Z)
			end
		end
		local shown = alpha > 0.01 and (if r.fixed then g > 0.6 else g > 0.03)
		rigTr(r, if shown then 1 - (1 - r.tr) * alpha else 1)
		parts[i] = r.p
		cfs[i] = if r.fixed then pivot * r.frame else pivot * r.frame * CFrame.new(0, r.size.Y * g / 2, 0)
	end
	workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Zerspringen: jedes Teil fliegt von `center` weg, dreht sich, faellt.
local function rigShatter(rig: { RigPart }, center: Vector3, power: number)
	for _, r in rig do
		local w = r.p.CFrame
		local away = w.Position - center
		local dir = if away.Magnitude > 0.05 then away.Unit else Vector3.yAxis
		r.w = w
		r.v = dir * power * (0.6 + math.random() * 0.8) + Vector3.new(0, power * (0.3 + math.random() * 0.5), 0)
		local ax = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
		r.axis = if ax.Magnitude > 0.01 then ax.Unit else Vector3.xAxis
		r.spin = (math.random() * 2 - 1) * 14
	end
end

local function rigFly(rig: { RigPart }, dt: number, alpha: number)
	local parts: { BasePart } = table.create(#rig)
	local cfs: { CFrame } = table.create(#rig)
	for i, r in rig do
		local v = (r.v :: Vector3) + Vector3.new(0, -45 * dt, 0)
		r.v = v
		local w = ((r.w :: CFrame) + v * dt) * CFrame.fromAxisAngle(r.axis :: Vector3, (r.spin :: number) * dt)
		r.w = w
		parts[i] = r.p
		cfs[i] = w
		local shown = alpha > 0.01 and (if r.fixed then r.g > 0.6 else r.g > 0.03)
		rigTr(r, if shown then 1 - (1 - r.tr) * alpha else 1)
	end
	workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Was an einem ECHTEN Klon (Aussehen bleibt) nichts zu suchen hat.
local AVATAR_STRIP: { [string]: boolean } = {
	BillboardGui = true, SurfaceGui = true, Script = true, LocalScript = true, ModuleScript = true,
	Sound = true, Humanoid = true, ProximityPrompt = true, ClickDetector = true, Highlight = true,
	Weld = true, WeldConstraint = true, Motor6D = true,
}

local function figureClone(source: Model): Model?
	local ok, c = pcall(function()
		local was = source.Archivable
		source.Archivable = true
		local m = source:Clone()
		source.Archivable = was
		return m
	end)
	if not ok or not c then return nil end
	local m = c :: Model
	for _, d in m:GetDescendants() do
		if AVATAR_STRIP[d.ClassName] then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
			d.LocalTransparencyModifier = 0
		end
	end
	m.Name = "SkillFXAvatar"
	return m
end

-- ascend: der Baerchi SELBST. Holt aus (lehnt sich zurueck), steigt mit
-- Drehung in die Luft und waechst dabei, schwebt bebend, holt ein zweites Mal
-- aus, stuerzt kopfueber auf den Gegner, landet und springt mit einem
-- Rueckwaerts-Salto nach Hause. Der Server bewegt die echte Figur (Idle) -
-- deshalb tanzt ein echter Klon, das Original ist so lange LOKAL unsichtbar.
--   height, crouch, rise, spins, grow, diveAt, dive, hold, back
BLOCKS.ascend = function(ctx, s)
	local source = ctx.selfModel
	if not source or not source.Parent then return end
	local clone = figureClone(source)
	if not clone then return end
	local H = ctx.selfSize.Y
	local home = CFrame.lookAt(ctx.selfFeet, ctx.selfFeet + ctx.fwd)
	local offset = home:ToObjectSpace(clone:GetPivot())
	local okScale, got = pcall(function() return clone:GetScale() end)
	local baseScale: number = if okScale and typeof(got) == "number" then got else 1
	local height = s.height or 7
	local crouch = s.crouch or 0.35
	local rise = s.rise or 0.9
	local spins = s.spins or 1
	local grow = s.grow or 1.25
	local diveAt = s.diveAt or 2.5
	local dive = s.dive or 0.25
	local hold = s.hold or 0.4
	local back = s.back or 0.55
	local total = diveAt + dive + hold + back
	local gap = (ctx.selfSize.Z + ctx.targetSize.Z) * 0.4 + 0.4
	local landFeet = ctx.targetFeet - ctx.fwd * gap
	local land = CFrame.lookAt(landFeet, landFeet + ctx.fwd)

	-- Original lokal ausblenden, seine eigenen Partikel anhalten
	local hidden: { Instance } = {}
	local paused: { ParticleEmitter } = {}
	for _, d in source:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			table.insert(hidden, d)
		elseif d:IsA("ParticleEmitter") and d.Enabled then
			table.insert(paused, d)
		end
	end
	local function hide(v: number)
		for _, d in hidden do
			pcall(function() (d :: any).LocalTransparencyModifier = v end)
		end
		for _, e in paused do
			if e.Parent then e.Enabled = v < 0.5 end
		end
	end

	-- Leuchtumriss, Rauch-Aura, Funken, Sturz-Schweif
	local hl = Instance.new("Highlight")
	hl.Adornee = clone
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.FillColor = ctx.fx.color
	hl.FillTransparency = 0.8
	hl.OutlineColor = Color3.fromRGB(220, 185, 255)
	hl.OutlineTransparency = 0.05
	hl.Parent = clone

	local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, ctx.fx.color, home, 1)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = SMOKE_TEX
	smoke.Rate = 0
	smoke.Speed = NumberRange.new(0.5, 2.5)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Lifetime = NumberRange.new(0.5, 0.9)
	smoke.Drag = 2
	smoke.Acceleration = Vector3.new(0, 1.5, 0)
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, H * 0.25), NumberSequenceKeypoint.new(1, H * 0.6) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	smoke.Color = ColorSequence.new(ctx.fx.color, ctx.fx.color2)
	smoke.LightEmission = 0.5
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-30, 30)
	smoke.Parent = anchor
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARK_TEX
	sparks.Rate = 0
	sparks.Speed = NumberRange.new(4, 9)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Lifetime = NumberRange.new(0.35, 0.7)
	sparks.Drag = 2
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	sparks.Color = ColorSequence.new(Color3.fromRGB(240, 225, 255), ctx.fx.color)
	sparks.LightEmission = 1
	sparks.Parent = anchor
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, H * 0.4, 0)
	a0.Parent = anchor
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -H * 0.4, 0)
	a1.Parent = anchor
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.28
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(Color3.fromRGB(235, 210, 255), ctx.fx.color)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
	trail.Enabled = false
	trail.Parent = anchor

	local lastScale = 1
	-- Pose: Fuesse `feet`, gedreht um die KOERPERMITTE (Salto sieht echt aus)
	local function place(feet: CFrame, pitch: number, yaw: number, roll: number, sc: number)
		if math.abs(sc - lastScale) > 0.008 then
			lastScale = sc
			pcall(function() clone:ScaleTo(baseScale * sc) end)
		end
		local half = H * sc * 0.5
		local pose = feet * CFrame.new(0, half, 0) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll) * CFrame.new(0, -half, 0)
		ctx.avatarCf = pose
		ctx.avatarScale = sc
		clone:PivotTo(pose * CFrame.new(offset.Position * sc) * offset.Rotation)
		anchor.CFrame = pose * CFrame.new(0, half, 0)
	end
	place(home, 0, 0, 0, 1)
	clone.Parent = folder()
	hide(1)
	smoke:Emit(scaled(14, ctx.factor))

	local hover = home.Position + Vector3.new(0, height, 0)
	local burstRise, burstLand = false, false
	local hoverRate = if extrasOn(ctx) then 22 * ctx.factor else 0
	runLoop("ascend", function(t)
		if t >= total or not clone.Parent then return true end
		if t < crouch then
			-- 1. ausholen: zuruecklehnen, kleiner werden
			local e = math.sin((t / crouch) * math.pi * 0.5)
			place(home, 0.3 * e, 0, 0, 1 - 0.1 * e)
		elseif t < crouch + rise then
			-- 2. aufsteigen mit Drehung, wachsen
			local k = (t - crouch) / rise
			if not burstRise then
				burstRise = true
				sparks:Emit(scaled(26, ctx.factor))
				smoke:Emit(scaled(18, ctx.factor))
			end
			local e = easeOutCubic(k)
			place(home + Vector3.new(0, height * easeOutBack(k), 0), 0.3 * (1 - e), spins * TAU * e, 0, lerpN(0.9, grow, e))
		elseif t < diveAt then
			-- 3. schweben; die letzten 0,7 s beben und weit zurueckholen
			local h = t - crouch - rise
			local tension = math.clamp(1 - (diveAt - t) / 0.7, 0, 1)
			smoke.Rate = hoverRate
			local bob = math.sin(h * 3.2) * 0.3 * (1 - tension)
			local jitter = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 0.22 * tension
			local feet = home + Vector3.new(0, height + bob, 0) + jitter
			hover = feet.Position
			place(feet, 0.4 * tension, 0, math.sin(h * 2.1) * 0.05 * (1 - tension), grow * (1 + 0.035 * math.sin(h * 10)))
		elseif t < diveAt + dive then
			-- 4. Sturz: kopfueber, immer schneller
			local k = (t - diveAt) / dive
			smoke.Rate = 0
			trail.Enabled = true
			local e = k * k
			local pos = hover:Lerp(landFeet, e)
			place(CFrame.lookAt(pos, pos + ctx.fwd), lerpN(0.4, -0.95, math.min(1, k * 2.2)), 0, 0, lerpN(grow, 1.12, e))
		elseif t < diveAt + dive + hold then
			-- 5. Landung: gebueckt, richtet sich auf
			local k = (t - diveAt - dive) / hold
			if not burstLand then
				burstLand = true
				trail.Enabled = false
				smoke:Emit(scaled(30, ctx.factor))
				sparks:Emit(scaled(40, ctx.factor))
			end
			place(land, lerpN(-0.55, 0, easeOutCubic(k)), 0, 0, lerpN(1.12, 1, k))
		else
			-- 6. Rueckwaerts-Salto nach Hause
			local k = (t - diveAt - dive - hold) / back
			local e = 0.5 - 0.5 * math.cos(math.pi * k)
			local pos = landFeet:Lerp(home.Position, e) + Vector3.new(0, math.sin(math.pi * k) * 3, 0)
			place(CFrame.lookAt(pos, pos + ctx.fwd), TAU * e, 0, 0, 1)
		end
		return false
	end, function()
		hide(0)
		ctx.avatarCf = nil
		ctx.avatarScale = nil
		clone:Destroy()
		smoke.Rate = 0
		Debris:AddItem(anchor, 1)
	end)
end

-- crown: Dornenkrone aus Obsidian mit leuchtendem Reif ueber dem Kopf (folgt
-- dem `ascend`-Klon). Erst der Reif, dann waechst Dorn fuer Dorn (abwechselnd
-- gross/klein, nach aussen gekippt, leuchtender Kern, Juwelen); dreht sich
-- langsam. Nach `dur` zerspringt sie in Splitter.
--   count, radius, lift, height, grow, dur, spin, shatter
BLOCKS.crown = function(ctx, s)
	local H = ctx.selfSize.Y
	local n = s.count or 10
	local r = s.radius or math.max(1.0, ctx.selfSize.X * 0.4)
	local lift = s.lift or 0.5
	local spikeH = s.height or r * 1.9
	local grow = s.grow or 0.9
	local dur = s.dur or 3
	local spinRate = s.spin or 0.9
	local col = pickColor(s, ctx.fx)
	local glow = Color3.fromRGB(235, 215, 255)
	local rig: { RigPart } = {}
	local segs = 20
	local segLen = TAU * r / segs * 1.12
	for i = 1, segs do
		local a = (i / segs) * TAU
		local pos = Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local f = CFrame.lookAt(pos, pos + Vector3.new(-math.sin(a), 0, math.cos(a)))
		local band = Instance.new("Part")
		prepPart(band, col, PARK, 1)
		rigPart(rig, band, f * CFrame.new(0, -0.05, 0), Vector3.new(0.16, 0.22, segLen), 0, 0)
		local foot = Instance.new("Part")
		prepPart(foot, VOID_OBSIDIAN, PARK, 1)
		foot.Material = Enum.Material.SmoothPlastic
		rigPart(rig, foot, f * CFrame.new(0, -0.45, 0), Vector3.new(0.26, 0.4, segLen), 0, 0)
	end
	for i = 1, n do
		local a = (i / n) * TAU + math.pi / n
		local radial = Vector3.new(math.cos(a), 0, math.sin(a))
		local tall = i % 2 == 1
		local h = if tall then spikeH else spikeH * 0.55
		local hb = TAU * r / n * 0.5
		local flare = math.rad(if tall then 12 else 24)
		local base = CFrame.fromMatrix(radial * r + Vector3.new(0, 0.12, 0), radial, Vector3.yAxis) * CFrame.Angles(0, 0, -flare)
		local delay = grow * 0.3 + (i - 1) / n * grow * 0.5
		addBlade(rig, base, 0.2, h, hb, VOID_OBSIDIAN, Enum.Material.SmoothPlastic, delay)
		addBlade(rig, base, 0.26, h * 0.86, hb * 0.32, col, Enum.Material.Neon, delay + 0.04)
		if tall then
			local gem = Instance.new("Part")
			prepPart(gem, glow, PARK, 1)
			rigPart(rig, gem, base * CFrame.new(0.17, 0.32, 0) * CFrame.Angles(math.rad(45), 0, 0),
				Vector3.new(0.12, 0.34, 0.34), delay + 0.1, 0, true)
		end
	end
	local lamp = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, PARK, 1)
	local light = Instance.new("PointLight")
	light.Color = col
	light.Range = 10
	light.Brightness = 0
	light.Parent = lamp
	tween(light, grow, { Brightness = 2.5 })
	local growFor = math.max(0.06, grow * 0.35)
	local shatterFor = 0.7
	local shattered = false
	runLoop("crown", function(t, dt)
		if t < dur then
			local f = avatarFrame(ctx)
			local pivot = f * CFrame.new(0, H * (ctx.avatarScale or 1) + lift + math.sin(t * 2.4) * 0.08, 0)
				* CFrame.Angles(0, t * spinRate, 0)
			rigApply(rig, pivot, function(rp)
				local k = (t - rp.delay) / growFor
				return if k <= 0 then 0 else easeOutBack(math.min(1, k))
			end, 1)
			lamp.CFrame = pivot
			return false
		end
		if not shattered then
			shattered = true
			rigShatter(rig, lamp.Position, s.shatter or 14)
			tween(light, 0.15, { Brightness = 6, Range = 16 })
			task.delay(0.15, function()
				if light.Parent then tween(light, 0.4, { Brightness = 0 }) end
			end)
			burstAt(ctx, lamp.Position, 28, 16, col)
		end
		local k = (t - dur) / shatterFor
		rigFly(rig, dt, math.max(0, 1 - k))
		return k >= 1
	end, function()
		for _, rp in rig do rp.p:Destroy() end
		lamp:Destroy()
	end)
end

-- voidorb: schwarze Kugel aus Leere ueber der Krone (folgt dem Klon), Rand
-- leuchtet violett, Licht wird hineingesogen, Blitzboegen zucken. Bei
-- `fireAt` schiesst sie auf den Gegner und kollabiert dort.
--   size, lift, grow, fireAt, fly, arcs
BLOCKS.voidorb = function(ctx, s)
	local size = s.size or 3
	local lift = s.lift or 3
	local grow = s.grow or 0.8
	local fireAt = s.fireAt or 1.2
	local fly = s.fly or 0.3
	local col = pickColor(s, ctx.fx)
	local H = ctx.selfSize.Y
	local function home(t: number): Vector3
		local f = avatarFrame(ctx)
		return f.Position + Vector3.new(0, H * (ctx.avatarScale or 1) + lift + math.sin(t * 3) * 0.15, 0)
	end
	local start = home(0)
	local core = newPart(Enum.PartType.Ball, Vector3.one * 0.1, Color3.fromRGB(3, 0, 8), CFrame.new(start), 0)
	core.Material = Enum.Material.SmoothPlastic
	local rim = newPart(Enum.PartType.Ball, Vector3.one * 0.1, col, CFrame.new(start), 0.86)
	local hl = Instance.new("Highlight")
	hl.Adornee = core
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.FillTransparency = 1
	hl.OutlineColor = Color3.fromRGB(215, 170, 255)
	hl.OutlineTransparency = 0
	hl.Parent = core
	local light = Instance.new("PointLight")
	light.Color = col
	light.Range = size * 4
	light.Brightness = 3
	light.Parent = rim
	-- Akkretionsring: hohler Leuchtring (GUI auf einer Platte, oben und
	-- unten), schraeg; ein Verlauf laeuft darin um (Wirbel).
	local disk = newPart(Enum.PartType.Block, Vector3.new(0.1, 0.02, 0.1), col, CFrame.new(start), 1)
	local swirls: { UIGradient } = {}
	for _, face in { Enum.NormalId.Top, Enum.NormalId.Bottom } do
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		sg.CanvasSize = Vector2.new(256, 256)
		sg.LightInfluence = 0
		sg.Brightness = 3
		sg.Adornee = disk
		sg.Parent = disk
		for _, ring in { { 0.92, 10 }, { 0.68, 5 } } do
			local c = Instance.new("Frame")
			c.AnchorPoint = Vector2.new(0.5, 0.5)
			c.Position = UDim2.fromScale(0.5, 0.5)
			c.Size = UDim2.fromScale(ring[1], ring[1])
			c.BackgroundTransparency = 1
			c.Parent = sg
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = c
			local st = Instance.new("UIStroke")
			st.Color = Color3.new(1, 1, 1)
			st.Thickness = ring[2]
			st.Parent = c
			local grad = Instance.new("UIGradient")
			grad.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, col),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(245, 230, 255)),
				ColorSequenceKeypoint.new(1, col),
			})
			grad.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.75), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 0.75),
			})
			grad.Parent = st
			table.insert(swirls, grad)
		end
	end
	local tilt = CFrame.Angles(math.rad(22), 0, math.rad(8))
	-- Sog: Funken entstehen auf einer Kugelschale und fliegen hinein
	local shell = newPart(Enum.PartType.Block, Vector3.one * size * 3, col, CFrame.new(start), 1)
	local em = Instance.new("ParticleEmitter")
	em.Shape = Enum.ParticleEmitterShape.Sphere
	em.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	em.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	em.Texture = SPARK_TEX
	em.Rate = 70 * ctx.factor
	em.Speed = NumberRange.new(size * 2.2, size * 2.8)
	em.Lifetime = NumberRange.new(0.45, 0.55)
	em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.05) })
	em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(0.3, 0), NumberSequenceKeypoint.new(1, 0.3) })
	em.Color = ColorSequence.new(Color3.fromRGB(235, 215, 255), col)
	em.LightEmission = 1
	em.Parent = shell
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.6, 0)
	a0.Parent = core
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.6, 0)
	a1.Parent = core
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.25
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(col, ctx.fx.color2)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	trail.Enabled = false
	trail.Parent = core
	-- Blitzboegen: 8 Teile im Pool, je 2 Boegen aus 4 Stuecken
	local arcs: { BasePart } = {}
	if extrasOn(ctx) and s.arcs ~= false then
		for _ = 1, 8 do
			table.insert(arcs, newPart(Enum.PartType.Block, Vector3.new(0.07, 0.07, 1), Color3.fromRGB(230, 205, 255), PARK, 1))
		end
	end
	local nextArc = 0
	local from = start
	runLoop("voidorb", function(t)
		local d: number
		local pos: Vector3
		if t < fireAt then
			pos = home(t)
			from = pos
			local k = math.clamp(t / grow, 0, 1)
			d = size * easeOutBack(k) * (1 + 0.07 * math.sin(t * 16))
		elseif t < fireAt + fly then
			local k = (t - fireAt) / fly
			pos = from:Lerp(ctx.targetPos, k * k)
			d = size * lerpN(1, 0.75, k)
			em.Enabled = false
			trail.Enabled = true
		else
			local k = (t - fireAt - fly) / 0.14
			if k >= 1 then return true end
			pos = ctx.targetPos
			d = size * 0.75 * (1 - k)
		end
		d = math.max(0.05, d)
		core.Size = Vector3.one * d * 0.86
		rim.Size = Vector3.one * d * 1.1
		core.CFrame = CFrame.new(pos)
		rim.CFrame = core.CFrame
		shell.CFrame = core.CFrame
		disk.Size = Vector3.new(d * 2.6, 0.02, d * 2.6)
		disk.CFrame = CFrame.new(pos) * tilt * CFrame.Angles(0, t * 1.5, 0)
		for i, gr in swirls do
			gr.Rotation = (t * 420 * (if i % 2 == 0 then -1 else 1)) % 360
		end
		if #arcs > 0 then
			if t >= nextArc and t < fireAt then
				nextArc = t + 0.06
				for j = 0, 1 do
					local dir = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
					dir = if dir.Magnitude > 0.01 then dir.Unit else Vector3.yAxis
					local p0 = pos + dir * d * 0.5
					local p3 = pos + dir * d * (1.4 + math.random())
					local prev = p0
					for q = 1, 4 do
						local jag = if q < 4 then Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * d * 0.35 else Vector3.zero
						local nxt = p0:Lerp(p3, q / 4) + jag
						local seg = arcs[j * 4 + q]
						seg.Size = Vector3.new(0.07, 0.07, math.max(0.05, (nxt - prev).Magnitude))
						seg.CFrame = CFrame.lookAt((prev + nxt) / 2, nxt)
						seg.Transparency = 0
						prev = nxt
					end
				end
			elseif t >= nextArc - 0.03 then
				for _, a in arcs do a.Transparency = 1 end
			end
		end
		return false
	end, function()
		core:Destroy()
		rim:Destroy()
		shell:Destroy()
		disk:Destroy()
		for _, a in arcs do a:Destroy() end
	end)
end

-- Ellipsoid (Kugel-Mesh, an die Teilgroesse gedehnt), anfangs zugeklappt.
local function ellipsoid(color: Color3, size: Vector3, cf: CFrame, tr: number, material: Enum.Material?): (BasePart, SpecialMesh)
	local p = newPart(Enum.PartType.Block, size, color, cf, tr)
	if material then p.Material = material end
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Scale = Vector3.new(1, 0.03, 1)
	m.Parent = p
	return p, m
end

-- eyes: in der Dunkelheit rund um die Arena oeffnen sich leuchtende Augen
-- (Augapfel, violette Iris, Schlitzpupille, Schein), schauen zwischen Gegner
-- und Kamera, blinzeln einmal und klappen am Ende zu.
--   at, count, radius, lift, size, open, blinkAt, dur
BLOCKS.eyes = function(ctx, s)
	local n = scaled(s.count or 10, ctx.factor)
	local center = groundAt(ctx, s.at or "arena")
	local R = radiusOf(s.radius, 20)
	local lift = s.lift or 6
	local w = s.size or 2.2
	local open = s.open or 0.3
	local dur = s.dur or 2.5
	local blinkAt = s.blinkAt
	local col = pickColor(s, ctx.fx)
	local white = Color3.fromRGB(240, 222, 255)
	-- Jedes Auge schaut in JEDEM Bild zur Kamera dieses Rechners (sonst
	-- sieht man es von der Seite nur als Strich) - es starrt den Zuschauer an.
	local spin = math.random() * TAU
	local parts: { BasePart } = {}
	local offsets: { { pos: Vector3, z: number } } = {}
	for i = 1, n do
		local a = spin + (i / n) * TAU + (math.random() - 0.5) * 0.3
		local pos = center + Vector3.new(math.cos(a) * R, lift + (math.random() - 0.5) * lift * 0.7, math.sin(a) * R)
		local frame = CFrame.new(pos)
		local ew = w * (0.75 + math.random() * 0.5)
		local delay = math.random() * 0.45
		local list: { { p: BasePart, m: SpecialMesh } } = {}
		local function add(color: Color3, size: Vector3, z: number, tr: number, mat: Enum.Material?)
			local p, m = ellipsoid(color, size, frame * CFrame.new(0, 0, -z), tr, mat)
			table.insert(list, { p = p, m = m })
			table.insert(parts, p)
			table.insert(offsets, { pos = pos, z = z })
		end
		add(col, Vector3.new(ew * 1.7, ew * 0.9, 0.08), -0.12, 0.7)                                         -- Schein
		add(white, Vector3.new(ew, ew * 0.42, 0.2), 0, 0)                                                   -- Augapfel
		add(col, Vector3.new(ew * 0.36, ew * 0.36, 0.24), 0.03, 0)                                          -- Iris
		add(Color3.fromRGB(8, 0, 14), Vector3.new(ew * 0.08, ew * 0.3, 0.28), 0.05, 0, Enum.Material.SmoothPlastic) -- Pupille
		-- Achtung: ein weiterer Tween auf `Scale` bricht einen laufenden ab,
		-- AUCH wenn er erst spaeter starten soll (DelayTime). Deshalb Blinzeln
		-- und Zuklappen ueber task.delay.
		for _, e in list do
			tweenLater(e.m, delay, open, { Scale = Vector3.one }, Enum.EasingStyle.Back)
			if blinkAt then
				task.delay(delay + blinkAt, function()
					if not e.p.Parent then return end
					tween(e.m, 0.06, { Scale = Vector3.new(1, 0.05, 1) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
					task.delay(0.08, function()
						if e.p.Parent then tween(e.m, 0.12, { Scale = Vector3.one }) end
					end)
				end)
			end
			task.delay(math.max(0, dur - 0.3), function()
				if e.p.Parent then
					tween(e.m, 0.18, { Scale = Vector3.new(1.05, 0.02, 1) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				end
			end)
			Debris:AddItem(e.p, dur + 0.15)
		end
	end
	local cfs: { CFrame } = table.create(#parts)
	runLoop("eyes", function(t)
		local cam = workspace.CurrentCamera
		local camPos = if cam then cam.CFrame.Position else ctx.selfPos
		for i, o in offsets do
			local toC = camPos - o.pos
			local look = if toC.Magnitude > 0.1 then toC.Unit else -ctx.fwd
			cfs[i] = CFrame.lookAt(o.pos, o.pos + look) * CFrame.new(0, 0, -o.z)
		end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		return t >= dur
	end)
end

-- sigil: Zauberkreis am Boden. Dunkle Scheibe aus Leere, darauf leuchtende
-- Ringe (wachsen nacheinander), Runen reihum und ein Stern; aussen und innen
-- drehen gegenlaeufig, bei `pulseAt` gleisst alles kurz auf. Die Linien sind
-- GUI auf einer Platte (SurfaceGui), keine Teile: Drehen kostet fast nichts.
--   at, radius, draw, dur, runes, points, spin, pulseAt
BLOCKS.sigil = function(ctx, s)
	local center = groundAt(ctx, s.at) + Vector3.new(0, 0.06, 0)
	local R = radiusOf(s.radius, 7)
	local dur = s.dur or 3
	local draw = s.draw or 0.8
	local spin = s.spin or 0.5
	local col = pickColor(s, ctx.fx)
	local light = Color3.fromRGB(232, 210, 255)
	local PPS = 32
	local canvas = R * 2.25
	local u = 1 / canvas
	local disc = newPart(Enum.PartType.Cylinder, Vector3.new(0.03, 0.2, 0.2), ctx.fx.color2,
		CFrame.new(center - Vector3.new(0, 0.03, 0)) * CFrame.Angles(0, 0, math.rad(90)), 0.2)
	disc.Material = Enum.Material.SmoothPlastic
	tween(disc, draw * 0.5, { Size = Vector3.new(0.03, R * 2.08, R * 2.08) }, Enum.EasingStyle.Quart)
	local plate = newPart(Enum.PartType.Block, Vector3.new(canvas, 0.04, canvas), col, CFrame.new(center), 1)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PPS
	gui.LightInfluence = 0
	gui.Brightness = 3
	gui.Adornee = plate
	gui.Parent = plate
	local strokes: { UIStroke } = {}
	local fills: { Frame } = {}
	local function layer(): Frame
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.fromScale(1, 1)
		f.BackgroundTransparency = 1
		f.Parent = gui
		return f
	end
	local outer, starLayer, inner = layer(), layer(), layer()
	local function circle(parent: Frame, radius: number, thick: number, color: Color3, delay: number)
		local c = Instance.new("Frame")
		c.AnchorPoint = Vector2.new(0.5, 0.5)
		c.Position = UDim2.fromScale(0.5, 0.5)
		c.Size = UDim2.fromScale(0, 0)
		c.BackgroundTransparency = 1
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = c
		local st = Instance.new("UIStroke")
		st.Color = color
		st.Thickness = thick * PPS
		st.Parent = c
		c.Parent = parent
		table.insert(strokes, st)
		local d = radius * 2 * u
		tweenLater(c, delay, draw * 0.45, { Size = UDim2.fromScale(d, d) }, Enum.EasingStyle.Quart)
	end
	-- Strich von a nach b (Studs relativ zur Mitte)
	local function bar(parent: Frame, a: Vector2, b: Vector2, thick: number, color: Color3, delay: number)
		local mid = (a + b) / 2
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5 + mid.X * u, 0.5 + mid.Y * u)
		f.Size = UDim2.new((b - a).Magnitude * u, 0, 0, math.max(2, thick * PPS))
		f.Rotation = math.deg(math.atan2(b.Y - a.Y, b.X - a.X))
		f.BackgroundColor3 = color
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Parent = parent
		table.insert(fills, f)
		tweenLater(f, delay, draw * 0.25, { BackgroundTransparency = 0 })
	end
	circle(outer, R, 0.24, light, 0)
	circle(outer, R * 0.94, 0.08, col, draw * 0.08)
	circle(outer, R * 0.78, 0.15, light, draw * 0.16)
	circle(inner, R * 0.44, 0.13, light, draw * 0.3)
	circle(inner, R * 0.2, 0.1, col, draw * 0.4)
	-- Runen im Band zwischen aeusserem und mittlerem Ring
	local runes = s.runes or 18
	local g = R * 0.05
	for i = 1, runes do
		local a = (i / runes) * TAU
		local rad = Vector2.new(math.cos(a), math.sin(a))
		local tan = Vector2.new(-math.sin(a), math.cos(a))
		local c = rad * R * 0.86
		local delay = draw * 0.35 + (i / runes) * draw * 0.5
		bar(outer, c - rad * g, c + rad * g, 0.1, light, delay)
		local pick = math.random(1, 4)
		if pick == 1 then
			bar(outer, c + rad * g, c + rad * g * 0.2 + tan * g, 0.06, light, delay)
		elseif pick == 2 then
			bar(outer, c - tan * g * 0.8, c + tan * g * 0.8, 0.06, light, delay)
		elseif pick == 3 then
			bar(outer, c, c + (rad + tan) * g * 0.75, 0.06, light, delay)
			bar(outer, c, c + (rad - tan) * g * 0.75, 0.06, light, delay)
		else
			bar(outer, c - rad * g, c - rad * g * 0.2 - tan * g, 0.06, light, delay)
		end
	end
	-- Stern (6 Spitzen = Hexagramm, 5 = Pentagramm)
	local pts = s.points or 6
	local vr = R * 0.77
	for i = 0, pts - 1 do
		local a1 = (i / pts) * TAU - math.pi / 2
		local a2 = (((i + 2) % pts) / pts) * TAU - math.pi / 2
		bar(starLayer, Vector2.new(math.cos(a1), math.sin(a1)) * vr, Vector2.new(math.cos(a2), math.sin(a2)) * vr,
			0.13, col, draw * 0.2 + i * draw * 0.06)
	end
	-- kleine Zeichen im Innenkreis
	for i = 1, 8 do
		local a = (i / 8) * TAU
		local rad = Vector2.new(math.cos(a), math.sin(a))
		bar(inner, rad * R * 0.27, rad * R * 0.37, 0.1, light, draw * 0.5 + i * 0.03)
	end
	local pulsed, fading = false, false
	runLoop("sigil", function(t)
		outer.Rotation = math.deg(t * spin)
		starLayer.Rotation = -math.deg(t * spin * 0.6)
		inner.Rotation = math.deg(t * spin * 1.7)
		if s.pulseAt and not pulsed and t >= s.pulseAt then
			pulsed = true
			gui.Brightness = 9
			tween(gui, 0.7, { Brightness = 3 })
			disc.Color = col
			tween(disc, 0.6, { Color = ctx.fx.color2 })
			for _, st in strokes do
				local th = st.Thickness
				st.Thickness = th * 2.2
				tween(st, 0.5, { Thickness = th })
			end
		end
		if not fading and t >= dur - 0.45 then
			fading = true
			for _, st in strokes do tween(st, 0.4, { Transparency = 1 }) end
			for _, f in fills do tween(f, 0.4, { BackgroundTransparency = 1 }) end
			tween(disc, 0.4, { Transparency = 1 })
		end
		return t >= dur
	end, function()
		plate:Destroy()
		disc:Destroy()
	end)
end

-- eruption: Obsidian-Dornen (Kreuzklingen mit leuchtendem Kern) brechen in
-- Ringen um eine Figur aus dem Boden - innen zuerst, nach aussen gekippt wie
-- eine Krone -, bleiben `linger` stehen und ziehen sich wieder zurueck.
-- Dazu eine dunkle Brandscheibe, Staub und Funken.
--   at, count, rings, radius, minHeight, maxHeight, rise, stagger, linger, sink
BLOCKS.eruption = function(ctx, s)
	local center = groundAt(ctx, s.at or "target")
	local n = scaled(s.count or 12, ctx.factor)
	local rings = math.max(1, s.rings or 2)
	local R = s.radius or 3.5
	local minH = s.minHeight or 1.4
	local maxH = s.maxHeight or 4
	local rise = s.rise or 0.16
	local stagger = s.stagger or 0.05
	local linger = s.linger or 0.8
	local sink = s.sink or 0.35
	local col = pickColor(s, ctx.fx)
	local rig: { RigPart } = {}
	local sum = rings * (rings + 1) / 2
	local maxDelay = 0
	for j = 1, rings do
		local per = math.max(3, math.floor(n * j / sum + 0.5))
		local ringK = if rings == 1 then 1 else (j - 1) / (rings - 1)
		local rr = R * lerpN(0.55, 1, ringK)
		for i = 1, per do
			local a = (i / per) * TAU + j * 0.7 + (math.random() - 0.5) * 0.3
			local radial = Vector3.new(math.cos(a), 0, math.sin(a))
			-- `open`: zur Seite des Angreifers bleibt eine Luecke (dort landet er)
			if s.open and s.at ~= "self" and radial:Dot(-ctx.fwd) > 0.72 then continue end
			local h = lerpN(minH, maxH, ringK * 0.6 + math.random() * 0.4)
			local tilt = math.rad(12 + math.random() * 20)
			local base = CFrame.fromMatrix(center + radial * rr - Vector3.new(0, 0.2, 0), radial, Vector3.yAxis)
				* CFrame.Angles(0, 0, -tilt)
			local delay = (j - 1) * stagger * 2 + (i / per) * stagger
			maxDelay = math.max(maxDelay, delay)
			local hb = h * 0.32
			addBlade(rig, base, 0.3, h, hb, VOID_OBSIDIAN, Enum.Material.SmoothPlastic, delay)
			addBlade(rig, base * CFrame.Angles(0, math.pi / 2, 0), 0.3, h, hb, VOID_OBSIDIAN, Enum.Material.SmoothPlastic, delay)
			addBlade(rig, base, 0.38, h * 0.88, hb * 0.3, col, Enum.Material.Neon, delay)
		end
	end
	local scorch = newPart(Enum.PartType.Cylinder, Vector3.new(0.03, 0.2, 0.2), ctx.fx.color2,
		CFrame.new(center + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)), 0.15)
	scorch.Material = Enum.Material.SmoothPlastic
	tween(scorch, 0.18, { Size = Vector3.new(0.03, R * 2.5, R * 2.5) }, Enum.EasingStyle.Quart)
	burstAt(ctx, center + Vector3.new(0, 0.6, 0), 24, 9, col, true)
	burstAt(ctx, center + Vector3.new(0, 1, 0), 30, 18, col)
	local endT = maxDelay + rise + linger + sink
	tweenLater(scorch, endT - 0.3, 0.4, { Transparency = 1 })
	Debris:AddItem(scorch, endT + 0.2)
	runLoop("eruption", function(t)
		rigApply(rig, CFrame.identity, function(rp)
			local x = t - rp.delay
			if x <= 0 then return 0 end
			if x < rise then return easeOutBack(x / rise) end
			x -= rise
			if x < linger then return 1 end
			x -= linger
			return math.max(0, 1 - math.min(1, x / sink) ^ 3)
		end, 1)
		return t >= endT
	end, function()
		for _, rp in rig do rp.p:Destroy() end
	end)
end

--------------------------------------------------------------------------------
-- 25.10.2026 Entfuehrungsstrahl (UfoAbduction, UFO-Baerchi). Die Untertasse
-- hebt ab, saust im Zickzack ueber den Gegner und zieht ihn im Traktorstrahl
-- hoch, ein Kornkreis brennt sich ein, ein Todesstrahl schmettert ihn zurueck.
-- Doku in SkillFXConfig ("BAUSTEINE", Entfuehrungsstrahl).
--------------------------------------------------------------------------------

local UFO_WHITE = Color3.fromRGB(240, 255, 250)

-- Original einer Figur lokal ausblenden (1) bzw. zeigen (0) und ihre eigenen
-- Partikel anhalten. Gleiches Muster wie in `ascend` (F03).
local function hideFigure(model: Model): (number) -> ()
	local hidden: { Instance } = {}
	local paused: { ParticleEmitter } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			table.insert(hidden, d)
		elseif d:IsA("ParticleEmitter") and d.Enabled then
			table.insert(paused, d)
		end
	end
	return function(v: number)
		for _, d in hidden do
			pcall(function() (d :: any).LocalTransparencyModifier = v end)
		end
		for _, e in paused do
			if e.Parent then e.Enabled = v < 0.5 end
		end
	end
end

local function easeInOutSine(k: number): number
	return 0.5 - 0.5 * math.cos(math.pi * k)
end

-- waagerecht, rechts vom Blick self -> target
local function sideOf(ctx: Ctx): Vector3
	local v = ctx.fwd:Cross(Vector3.yAxis)
	return if v.Magnitude < 0.1 then Vector3.xAxis else v.Unit
end

-- saucer: der UFO-Baerchi SELBST (echter Klon, Original lokal unsichtbar, F03).
-- Duckt sich, hebt mit Drehung ab und waechst, saust in `zigs` Rucken im
-- Zickzack ueber den Gegner (Fuesse `hover` Studs ueber dessen Fuessen) und
-- schwebt wackelnd; Randlichter (Teile mit "rimlight" im Namen) laufen als
-- Lauflicht. Bei `fireAt` Rueckstoss nach oben (Schuss), Fassrolle, Zickzack
-- nach Hause, Landung. Setzt ctx.avatarCf (Unterseite) fuer tractor + Kamera.
--   height, crouch, rise, spins, grow, travel, zigs, zig, hover, fireAt, jolt, hold, back, land
BLOCKS.saucer = function(ctx, s)
	local source = ctx.selfModel
	if not source or not source.Parent then return end
	local clone = figureClone(source)
	if not clone then return end
	local H = ctx.selfSize.Y
	local home = CFrame.lookAt(ctx.selfFeet, ctx.selfFeet + ctx.fwd)
	local offset = home:ToObjectSpace(clone:GetPivot())
	local okScale, got = pcall(function() return clone:GetScale() end)
	local baseScale: number = if okScale and typeof(got) == "number" then got else 1
	local height = s.height or 8
	local crouch = s.crouch or 0.3
	local rise = s.rise or 0.55
	local spins = s.spins or 2
	local grow = s.grow or 1.3
	local travel = s.travel or 0.9
	local zigs = math.max(1, math.floor(s.zigs or 3))
	local zigW = s.zig or 3
	local hoverH = s.hover or height
	local fireAt = s.fireAt or 2.7
	local jolt = s.jolt or 0.2
	local hold = s.hold or 0.35
	local back = s.back or 0.7
	local land = s.land or 0.3
	local tTravel = crouch + rise
	local tHover = tTravel + travel
	local tHold = fireAt + jolt
	local tBack = tHold + hold
	local tLand = tBack + back
	local total = tLand + land
	local col = ctx.fx.color
	local side = sideOf(ctx)
	local up = Vector3.yAxis

	-- Wegpunkte: hin im Zickzack, zurueck mit einem Haken weniger
	local highHome = ctx.selfFeet + up * height
	local over = ctx.targetFeet + up * hoverH
	local function zigPath(a: Vector3, b: Vector3, n: number, sign: number): { Vector3 }
		local pts = { a }
		for i = 1, n - 1 do
			local swing = if i % 2 == 1 then 1 else -1
			table.insert(pts, a:Lerp(b, i / n) + side * zigW * sign * swing + up * (math.random() - 0.5) * 1.2)
		end
		table.insert(pts, b)
		return pts
	end
	local goPts = zigPath(highHome, over, zigs, 1)
	local backPts = zigPath(over + up * 1.4, highHome, math.max(1, zigs - 1), -1)

	local hide = hideFigure(source)

	-- Randlichter, nach Winkel sortiert (Lauflicht im Kreis). Aus = dunkles
	-- Indigo, an = Mint/Weiss; Neon nur solange das Lauflicht laeuft (sonst
	-- ueberstrahlen 16 helle Neon-Kugeln die ganze Untertasse).
	type Rim = { p: BasePart, c: Color3, m: Enum.Material }
	local rims: { Rim } = {}
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") and string.find(string.lower(d.Name), "rimlight", 1, true) then
			table.insert(rims, { p = d, c = d.Color, m = d.Material })
		end
	end
	local cPiv = clone:GetPivot()
	table.sort(rims, function(a: Rim, b: Rim)
		local pa = cPiv:PointToObjectSpace(a.p.Position)
		local pb = cPiv:PointToObjectSpace(b.p.Position)
		return math.atan2(pa.Z, pa.X) < math.atan2(pb.Z, pb.X)
	end)
	local dim = ctx.fx.color2:Lerp(Color3.new(0, 0, 0), 0.45)
	local neonOn = false
	local function rimLights(t: number, speed: number, on: number)
		local wantNeon = on > 0.25
		if wantNeon ~= neonOn then
			neonOn = wantNeon
			for _, r in rims do r.p.Material = if wantNeon then Enum.Material.Neon else r.m end
		end
		local n = math.max(1, #rims)
		for i, r in rims do
			local w = 0.5 + 0.5 * math.sin(t * speed - (i / n) * TAU * 2)
			local base = r.c:Lerp(dim, on)
			r.p.Color = base:Lerp(if i % 4 == 0 then UFO_WHITE else col, w * w * w * on)
		end
	end

	local hl = Instance.new("Highlight")
	hl.Adornee = clone
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.FillColor = col
	hl.FillTransparency = 0.88
	hl.OutlineColor = UFO_WHITE
	hl.OutlineTransparency = 0.15
	hl.Parent = clone

	local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, home, 1)
	-- Licht 2 Studs UNTER der Unterseite (direkt am weissen Rumpf brennt es ihn aus)
	local glowAt = Instance.new("Attachment")
	glowAt.Position = Vector3.new(0, -2, 0)
	glowAt.Parent = anchor
	local glow = Instance.new("PointLight")
	glow.Color = col
	glow.Range = 10
	glow.Brightness = 0
	glow.Parent = glowAt
	local R = math.max(ctx.selfSize.X, ctx.selfSize.Z) * 0.5
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(-R, H * 0.15, 0)
	a0.Parent = anchor
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(R, H * 0.15, 0)
	a1.Parent = anchor
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.22
	trail.LightEmission = 1
	trail.Color = ColorSequence.new(UFO_WHITE, col)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 1) })
	trail.Enabled = false
	trail.Parent = anchor

	local lastScale = 1
	-- Pose: Fuesse `feet` (Blick zum Gegner), gedreht um die Koerpermitte
	local function place(feet: Vector3, pitch: number, yaw: number, roll: number, sc: number)
		if math.abs(sc - lastScale) > 0.008 then
			lastScale = sc
			pcall(function() clone:ScaleTo(baseScale * sc) end)
		end
		local half = H * sc * 0.5
		local base = CFrame.lookAt(feet, feet + ctx.fwd)
		local pose = base * CFrame.new(0, half, 0) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll) * CFrame.new(0, -half, 0)
		ctx.avatarCf = pose
		ctx.avatarScale = sc
		clone:PivotTo(pose * CFrame.new(offset.Position * sc) * offset.Rotation)
		anchor.CFrame = pose
	end
	-- Ruck-Bewegung: je Abschnitt schnell hin (60 %), kurz stehen (40 %)
	local function along(pts: { Vector3 }, k: number): (Vector3, number)
		local n = #pts - 1
		local x = math.clamp(k, 0, 1) * n
		local i = math.min(n, math.floor(x) + 1)
		local m = math.min(1, (x - (i - 1)) / 0.6)
		local a, b = pts[i], pts[i + 1]
		local lateral = (b - a):Dot(side)
		local bank = -math.clamp(lateral / math.max(1, zigW), -1, 1) * 0.45 * math.sin(math.pi * m)
		return a:Lerp(b, easeInOutSine(m)), bank
	end

	place(ctx.selfFeet, 0, 0, 0, 1)
	clone.Parent = folder()
	hide(1)
	local liftBurst, shotDone, landDone = false, false, false
	runLoop("saucer", function(t)
		if t >= total or not clone.Parent then return true end
		if t < crouch then
			-- 1. ducken: absenken, nach hinten kippen, Lichter gehen an
			local e = math.sin((t / crouch) * math.pi * 0.5)
			place(ctx.selfFeet - up * 0.25 * e, -0.25 * e, 0, 0, 1 - 0.08 * e)
			rimLights(t, 10, e)
			glow.Brightness = 0.6 * e
		elseif t < tTravel then
			-- 2. abheben mit Drehung, wachsen
			local k = (t - crouch) / rise
			if not liftBurst then
				liftBurst = true
				burstAt(ctx, ctx.selfFeet + up * 0.4, 20, 8, col, true)
				burstAt(ctx, ctx.selfFeet + up * 0.8, 24, 14, col)
			end
			local e = easeOutCubic(k)
			place(ctx.selfFeet + up * height * easeOutBack(k), -0.25 * (1 - e), spins * TAU * e, 0, lerpN(0.92, grow, e))
			rimLights(t, 14, 1)
			glow.Brightness = 0.6 + 0.4 * e
		elseif t < tHover then
			-- 3. Zickzack ueber den Gegner
			local pos, bank = along(goPts, (t - tTravel) / travel)
			trail.Enabled = true
			place(pos, 0, 0, bank, grow)
			rimLights(t, 18, 1)
		elseif t < fireAt then
			-- 4. schweben und wackeln; die letzten 0,3 s beben
			trail.Enabled = false
			local h = t - tHover
			local tension = math.clamp(1 - (fireAt - t) / 0.3, 0, 1)
			local calm = 1 - tension
			local jitter = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 0.18 * tension
			place(over + up * math.sin(h * 3.4) * 0.25 * calm + jitter, math.sin(h * 2.3) * 0.07 * calm,
				math.sin(h * 1.7) * 0.2 * calm, math.sin(h * 2.9) * 0.09 * calm, grow * (1 + 0.025 * math.sin(h * 12) * tension))
			rimLights(t, 22 + 20 * tension, 1)
			glow.Brightness = 1 + 0.8 * tension
		elseif t < tHold then
			-- 5. Schuss: Rueckstoss nach oben, Nase hoch
			local k = (t - fireAt) / jolt
			if not shotDone then
				shotDone = true
				burstAt(ctx, over, 26, 12, UFO_WHITE)
			end
			place(over + up * 1.4 * math.sin(math.pi * 0.5 * k), 0.18 * math.sin(math.pi * k), 0, 0, grow)
			rimLights(t, 40, 1)
			glow.Brightness = 1 + 2 * (1 - k)
		elseif t < tBack then
			-- 6. Fassrolle
			local k = (t - tHold) / hold
			place(over + up * 1.4, 0, 0, TAU * easeInOutSine(k), grow)
			rimLights(t, 18, 1)
			glow.Brightness = 1
		elseif t < tLand then
			-- 7. Zickzack nach Hause
			local k = (t - tBack) / back
			local pos, bank = along(backPts, k)
			trail.Enabled = true
			place(pos, 0, 0, bank, lerpN(grow, 1.1, k))
			rimLights(t, 18, 1)
		else
			-- 8. Landung, Lichter gehen aus
			local k = (t - tLand) / land
			trail.Enabled = false
			if not landDone then
				landDone = true
				burstAt(ctx, ctx.selfFeet + up * 0.4, 14, 6, col, true)
			end
			place(highHome:Lerp(ctx.selfFeet, easeOutCubic(k)), 0, 0, 0, lerpN(1.1, 1, k))
			rimLights(t, 10, 1 - k)
			glow.Brightness = 1 - k
		end
		return false
	end, function()
		hide(0)
		ctx.avatarCf = nil
		ctx.avatarScale = nil
		clone:Destroy()
		trail.Enabled = false
		Debris:AddItem(anchor, 0.5)
	end)
end

-- tractor: Traktorstrahl von der Unterseite des `saucer`-Klons (ohne ihn:
-- kleine Neon-Untertasse `lift` Studs ueber dem Gegner, z. B. im Echo) zum
-- Boden. Oeffnet sich nach unten (`open`), gepunktete Lichtringe laufen hoch,
-- Funken steigen, Lichtfleck am Boden. Bei `zapAt` erlischt er und ein weisser
-- Todesstrahl faellt in `zap` s auf den Boden (= Einschlag), der Fleck gleisst,
-- dann verblasst alles. Strahlen = 3 FaceCamera-Beams (wirken von jeder Seite
-- wie ein Kegel, F04). `width` oben, `base` unten.
--   at, width, base, open, zapAt, zap, dur, rings, lift
BLOCKS.tractor = function(ctx, s)
	local up = Vector3.yAxis
	local ground = groundAt(ctx, s.at or "target") + up * 0.05
	local dur = s.dur or 1.5
	local open = math.max(0.03, s.open or 0.2)
	local zapAt = s.zapAt or dur * 0.65
	local zap = math.max(0.03, s.zap or 0.2)
	local hitT = zapAt + zap
	local fade = math.max(0.1, dur - hitT)
	local topW = s.width or 1.6
	local baseW = s.base or 6.5
	local lift = s.lift or 8
	local col = pickColor(s, ctx.fx)

	-- Quelle: Unterseite des Klons, sonst eine kleine Neon-Untertasse
	local ghost: { BasePart } = {}
	local ghostTr = { 0.1, 0.35 }
	local ghostTop = ground + up * lift
	if not ctx.avatarCf then
		ghost = {
			newPart(Enum.PartType.Cylinder, Vector3.new(0.45, 3.4, 3.4), col, CFrame.new(ghostTop + up * 0.2) * CFrame.Angles(0, 0, math.rad(90)), 0.1),
			newPart(Enum.PartType.Ball, Vector3.new(1.6, 1.6, 1.6), UFO_WHITE, CFrame.new(ghostTop + up * 0.55), 0.35),
		}
	end
	local lastTop = if ctx.avatarCf then ctx.avatarCf.Position else ghostTop
	local function top(): Vector3
		local f = ctx.avatarCf
		if f then lastTop = f.Position + up * 0.15 end
		return lastTop
	end

	local aTop = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, CFrame.new(top()), 1)
	local aBot = newPart(Enum.PartType.Block, Vector3.new(baseW * 0.7, 0.1, baseW * 0.7), col, CFrame.new(top()), 1)
	local att0 = Instance.new("Attachment")
	att0.Parent = aTop
	local att1 = Instance.new("Attachment")
	att1.Parent = aBot
	local function mkBeam(c0: Color3, c1: Color3): Beam
		local b = Instance.new("Beam")
		b.Attachment0 = att0
		b.Attachment1 = att1
		b.FaceCamera = true
		b.LightEmission = 1
		b.LightInfluence = 0
		b.Segments = 1
		b.Color = ColorSequence.new(c0, c1)
		b.Transparency = NumberSequence.new(1)
		b.Parent = aTop
		return b
	end
	local outer = mkBeam(col, ctx.fx.color2)
	local main = mkBeam(UFO_WHITE, col)
	local core = mkBeam(UFO_WHITE, UFO_WHITE)
	local lastTr: { [Beam]: number } = {}
	local function setTr(b: Beam, a: number, trTop: number, trBot: number)
		local key = math.floor(a * 50 + 0.5) * 10000 + math.floor(trTop * 99) * 100 + math.floor(trBot * 99)
		if lastTr[b] == key then return end
		lastTr[b] = key
		b.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1 - (1 - trTop) * a),
			NumberSequenceKeypoint.new(1, 1 - (1 - trBot) * a),
		})
	end

	-- Lichtfleck am Boden + Licht
	local spot = newPart(Enum.PartType.Cylinder, Vector3.new(0.06, 0.2, 0.2), col,
		CFrame.new(ground) * CFrame.Angles(0, 0, math.rad(90)), 1)
	local light = Instance.new("PointLight")
	light.Color = col
	light.Range = 12
	light.Brightness = 0
	light.Parent = aBot

	-- aufsteigende Funken (1 Emitter, Flaeche = aBot)
	local motes = Instance.new("ParticleEmitter")
	motes.Texture = SPARK_TEX
	motes.Rate = 0
	motes.EmissionDirection = Enum.NormalId.Top
	motes.SpreadAngle = Vector2.new(6, 6)
	motes.Speed = NumberRange.new(lift * 0.8, lift * 1.2)
	motes.Lifetime = NumberRange.new(0.7, 1.0)
	motes.Drag = 1
	motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.05) })
	motes.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	motes.Color = ColorSequence.new(UFO_WHITE, col)
	motes.LightEmission = 1
	motes.Parent = aBot
	local moteRate = if extrasOn(ctx) then 40 * ctx.factor else 0

	-- gepunktete Lichtringe (BulkMoveTo)
	local nRings = scaled(s.rings or 5, ctx.factor)
	local SEGS = 12
	local dots: { BasePart } = {}
	local dotTr: { number } = {}
	for i = 1, nRings * SEGS do
		dots[i] = newPart(Enum.PartType.Block, Vector3.new(0.26, 0.26, 0.75), if i % 3 == 0 then UFO_WHITE else col, PARK, 1)
		dotTr[i] = 1
	end
	local cfs: { CFrame } = table.create(#dots)

	local hitDone = false
	runLoop("tractor", function(t)
		if t >= dur then return true end
		local tp = top()
		local alpha = if t < hitT then 1 else math.max(0, 1 - (t - hitT) / fade)
		local openK = easeOutCubic(math.clamp(t / open, 0, 1))
		local zapK = if t < zapAt then 0 else math.clamp((t - zapAt) / zap, 0, 1)
		-- Unterkante: oeffnet sich nach unten; beim Schuss springt sie hoch
		-- und faellt als Todesstrahl beschleunigt auf den Boden
		local bottom = if t < zapAt then tp:Lerp(ground, openK) else tp:Lerp(ground, zapK * zapK)
		aTop.CFrame = CFrame.new(tp)
		aBot.CFrame = CFrame.new(bottom)
		local wBot = lerpN(topW, baseW, openK)
		if t < zapAt then
			outer.Width0, outer.Width1 = topW * 1.5, wBot * 1.15
			main.Width0, main.Width1 = topW, wBot
			core.Width0, core.Width1 = topW * 0.3, topW * 0.45
			setTr(outer, alpha, 0.72, 0.86)
			setTr(main, alpha, 0.55, 0.68)
			setTr(core, alpha, 0.38, 0.55)
		else
			-- Todesstrahl: weisser Kern, Mint-Saum (outer), der Kegel (main) erlischt
			local shrink = math.max(0, 1 - zapK * 3)
			local w = topW * (0.65 + 0.35 * zapK)
			outer.Width0, outer.Width1 = w * 2.1, w * 2.4
			main.Width0, main.Width1 = topW * shrink, topW * shrink
			core.Width0, core.Width1 = w, w * 1.15
			setTr(outer, alpha, 0.5, 0.62)
			setTr(main, alpha * shrink, 0.55, 0.68)
			setTr(core, alpha, 0, 0.05)
		end

		-- Lichtringe: vor dem Schuss nach oben, danach rasen sie nach unten
		local ringsOn = if t < zapAt then math.clamp((t - open) / 0.15, 0, 1) else math.max(0, 1 - zapK * 2)
		for r = 1, nRings do
			local phase = (r - 1) / nRings
			local u = if t < zapAt then (t * 0.9 + phase) % 1 else math.max(0, ((zapAt * 0.9 + phase) % 1) - zapK * 1.5)
			local c = ground:Lerp(tp, u)
			local rad = lerpN(baseW * 0.5, topW * 0.5, u) * 0.95
			local vis = math.sin(math.pi * math.clamp(u, 0, 1)) * ringsOn * alpha
			local spinA = t * (if r % 2 == 0 then 1.6 else -1.6)
			for j = 1, SEGS do
				local i = (r - 1) * SEGS + j
				local a = (j / SEGS) * TAU + spinA
				local pos = c + Vector3.new(math.cos(a), 0, math.sin(a)) * rad
				cfs[i] = CFrame.lookAt(pos, pos + Vector3.new(-math.sin(a), 0, math.cos(a)))
				local tr = if vis > 0.02 then 1 - 0.9 * vis else 1
				if math.abs(tr - dotTr[i]) > 0.02 then
					dotTr[i] = tr
					dots[i].Transparency = tr
				end
			end
		end
		workspace:BulkMoveTo(dots, cfs, Enum.BulkMoveMode.FireCFrameChanged)

		-- Lichtfleck, Licht, Funken
		local spotD = wBot * 0.95
		if t < hitT then
			spot.Size = Vector3.new(0.06, spotD * openK + 0.2, spotD * openK + 0.2)
			spot.Transparency = if t < zapAt then 0.7 else 0.7 - 0.5 * zapK
			light.Brightness = 2.2 * openK + 3 * zapK
			motes.Rate = if t < zapAt and openK >= 1 then moteRate else 0
		else
			if not hitDone then
				hitDone = true
				burstAt(ctx, ground + up * 0.5, 34, 16, UFO_WHITE)
			end
			local k = (t - hitT) / fade
			spot.Size = Vector3.new(0.06, spotD * (1 + 0.8 * k), spotD * (1 + 0.8 * k))
			spot.Transparency = lerpN(0.2, 1, k)
			light.Brightness = 7 * (1 - k)
			motes.Rate = 0
		end
		for gi, g in ghost do
			g.Transparency = 1 - (1 - ghostTr[gi]) * alpha
		end
		return false
	end, function()
		aTop:Destroy()
		aBot:Destroy()
		spot:Destroy()
		for _, p in dots do p:Destroy() end
		for _, g in ghost do g:Destroy() end
	end)
end

-- abduct: der GEGNER (echter Klon, Original lokal unsichtbar, F03) wird im
-- Strahl hochgezogen: zuckt zusammen, steigt taumelnd und zappelnd `height`
-- Studs (`lift` s), haengt bebend und dreht sich, stuerzt bei `dropAt` in
-- `drop` s beschleunigt auf seinen Platz und richtet sich dabei auf. Landung
-- = Einschlag: dann ist das Original wieder da (Server: Rueckstoss).
--   height, lift, dropAt, drop, spin
BLOCKS.abduct = function(ctx, s)
	local source = ctx.targetModel
	if not source or not source.Parent then return end
	local clone = figureClone(source)
	if not clone then return end
	local H = ctx.targetSize.Y
	local home = CFrame.lookAt(ctx.targetFeet, ctx.targetFeet - ctx.fwd)
	local offset = home:ToObjectSpace(clone:GetPivot())
	local height = s.height or 4
	local lift = math.max(0.2, s.lift or 0.6)
	local dropAt = s.dropAt or 0.8
	local drop = math.max(0.05, s.drop or 0.2)
	local spinRate = s.spin or 2.2
	local hide = hideFigure(source)
	local hl = Instance.new("Highlight")
	hl.Adornee = clone
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.FillColor = ctx.fx.color
	hl.FillTransparency = 0.85
	hl.OutlineColor = UFO_WHITE
	hl.OutlineTransparency = 0.25
	hl.Parent = clone
	local function place(y: number, pitch: number, yaw: number, roll: number)
		local half = H * 0.5
		local pose = home * CFrame.new(0, y + half, 0) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll) * CFrame.new(0, -half, 0)
		clone:PivotTo(pose * offset)
	end
	place(0, 0, 0, 0)
	clone.Parent = folder()
	hide(1)
	local yaw = 0
	local yawFrom: number? = nil
	local yawEnd = 0
	local hy, hp, hr = 0, 0, 0
	runLoop("abduct", function(t, dt)
		if not clone.Parent then return true end
		if t < dropAt then
			yaw += spinRate * math.clamp(t / lift, 0, 1) * dt
			if t < 0.12 then
				-- erschrecken: kleiner Hopser, nach hinten
				local e = math.sin((t / 0.12) * math.pi)
				hy, hp, hr = 0.35 * e, -0.3 * e, 0
			elseif t < lift then
				-- aufsteigen und zappeln, kippt dabei nach vorn
				local kk = (t - 0.12) / (lift - 0.12)
				local wob = kk * (1 - kk) * 4
				hy = height * easeInOutSine(kk)
				hp = math.sin(t * 9) * 0.35 * wob + 0.3 * kk
				hr = math.sin(t * 7.3) * 0.3 * wob
			else
				-- haengen und beben
				local h = t - lift
				hy = height + math.sin(h * 11) * 0.07 + (math.random() - 0.5) * 0.08
				hp = 0.3 + math.sin(h * 6) * 0.12
				hr = math.sin(h * 4.7) * 0.2
			end
			place(hy, hp, yaw, hr)
			return false
		end
		if not yawFrom then
			yawFrom = yaw
			yawEnd = math.ceil(yaw / TAU) * TAU
		end
		local k = math.clamp((t - dropAt) / drop, 0, 1)
		local e = easeOutCubic(k)
		place(hy * (1 - k * k), hp * (1 - e), lerpN(yawFrom :: number, yawEnd, e), hr * (1 - e))
		if k >= 1 then
			burstAt(ctx, ctx.targetFeet + Vector3.new(0, 0.4, 0), 22, 9, ctx.fx.color, true)
			return true
		end
		return false
	end, function()
		hide(0)
		clone:Destroy()
	end)
end

-- cropcircle: Kornkreis brennt sich unter einer Figur in den Boden
-- (SurfaceGui wie `sigil`, F06): plattgedrueckte dunkle Scheibe, Aussenring,
-- Innenring, Speichen, Mittelpunkt und `sats` Trabanten-Kreise; dreht
-- langsam, gleisst bei `pulseAt` auf, verblasst am Ende.
--   at, radius, draw, dur, spin, pulseAt, sats
BLOCKS.cropcircle = function(ctx, s)
	local center = groundAt(ctx, s.at or "target") + Vector3.new(0, 0.07, 0)
	local R = radiusOf(s.radius, 5.5)
	local dur = s.dur or 2.4
	local draw = s.draw or 0.6
	local spin = s.spin or 0.25
	local sats = s.sats or 6
	local col = pickColor(s, ctx.fx)
	local PPS = 32
	local canvas = R * 2.3
	local u = 1 / canvas
	local disc = newPart(Enum.PartType.Cylinder, Vector3.new(0.03, 0.2, 0.2), ctx.fx.color2,
		CFrame.new(center - Vector3.new(0, 0.04, 0)) * CFrame.Angles(0, 0, math.rad(90)), 0.35)
	disc.Material = Enum.Material.SmoothPlastic
	tween(disc, draw * 0.5, { Size = Vector3.new(0.03, R * 2.1, R * 2.1) }, Enum.EasingStyle.Quart)
	local plate = newPart(Enum.PartType.Block, Vector3.new(canvas, 0.04, canvas), col, CFrame.new(center), 1)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PPS
	gui.LightInfluence = 0
	gui.Brightness = 3
	gui.Adornee = plate
	gui.Parent = plate
	local root = Instance.new("Frame")
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = gui
	local strokes: { UIStroke } = {}
	local fills: { Frame } = {}
	local function roundFrame(c: Vector2): Frame
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5 + c.X * u, 0.5 + c.Y * u)
		f.Size = UDim2.fromScale(0, 0)
		f.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = f
		f.Parent = root
		return f
	end
	local function ring(c: Vector2, radius: number, thick: number, color: Color3, delay: number)
		local f = roundFrame(c)
		f.BackgroundTransparency = 1
		local st = Instance.new("UIStroke")
		st.Color = color
		st.Thickness = thick * PPS
		st.Parent = f
		table.insert(strokes, st)
		local d = radius * 2 * u
		tweenLater(f, delay, draw * 0.45, { Size = UDim2.fromScale(d, d) }, Enum.EasingStyle.Quart)
	end
	local function dot(c: Vector2, radius: number, color: Color3, delay: number)
		local f = roundFrame(c)
		f.BackgroundColor3 = color
		f.BackgroundTransparency = 0.05
		table.insert(fills, f)
		local d = radius * 2 * u
		tweenLater(f, delay, draw * 0.3, { Size = UDim2.fromScale(d, d) }, Enum.EasingStyle.Back)
	end
	local function bar(a: Vector2, b: Vector2, thick: number, color: Color3, delay: number)
		local mid = (a + b) / 2
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5 + mid.X * u, 0.5 + mid.Y * u)
		f.Size = UDim2.new((b - a).Magnitude * u, 0, 0, math.max(2, thick * PPS))
		f.Rotation = math.deg(math.atan2(b.Y - a.Y, b.X - a.X))
		f.BackgroundColor3 = color
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Parent = root
		table.insert(fills, f)
		tweenLater(f, delay, draw * 0.25, { BackgroundTransparency = 0.05 })
	end
	local Z = Vector2.zero
	ring(Z, R, 0.24, UFO_WHITE, 0)
	ring(Z, R * 0.93, 0.08, col, draw * 0.08)
	ring(Z, R * 0.55, 0.2, col, draw * 0.18)
	ring(Z, R * 0.27, 0.08, col, draw * 0.3)
	dot(Z, R * 0.17, UFO_WHITE, draw * 0.34)
	for i = 0, sats - 1 do
		local a = (i / sats) * TAU
		local dir = Vector2.new(math.cos(a), math.sin(a))
		bar(dir * R * 0.27, dir * R * 0.55, 0.12, UFO_WHITE, draw * 0.35 + i * 0.04)
		local a2 = a + TAU / sats / 2
		local d2 = Vector2.new(math.cos(a2), math.sin(a2))
		local c = d2 * R * 0.76
		bar(d2 * R * 0.55, d2 * R * 0.63, 0.1, col, draw * 0.5 + i * 0.05)
		dot(c, R * 0.075, col, draw * 0.5 + i * 0.05)
		ring(c, R * 0.13, 0.08, UFO_WHITE, draw * 0.5 + i * 0.05)
	end
	local pulsed, fading = false, false
	runLoop("cropcircle", function(t)
		root.Rotation = math.deg(t * spin)
		if s.pulseAt and not pulsed and t >= s.pulseAt then
			pulsed = true
			gui.Brightness = 10
			tween(gui, 0.8, { Brightness = 3 })
			disc.Color = col
			tween(disc, 0.7, { Color = ctx.fx.color2 })
			for _, st in strokes do
				local th = st.Thickness
				st.Thickness = th * 2.2
				tween(st, 0.5, { Thickness = th })
			end
		end
		if not fading and t >= dur - 0.45 then
			fading = true
			for _, st in strokes do tween(st, 0.4, { Transparency = 1 }) end
			for _, f in fills do tween(f, 0.4, { BackgroundTransparency = 1 }) end
			tween(disc, 0.4, { Transparency = 1 })
		end
		return t >= dur
	end, function()
		plate:Destroy()
		disc:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- 25.10.2026 Zeitstillstand (ChronosTimeStop, Chronos-Baerchi). Der Baerchi
-- steigt auf, die Uhr auf seiner Stirn rast, hinter der Arena erscheint ein
-- riesiges Zifferblatt; dann bleibt die Zeit stehen (Zeitblase, Staub haengt
-- in der Luft, der Gegner erstarrt), der Minutenzeiger tickt auf XII, der
-- Baerchi springt durch die Zeit auf den Gegner und spult rueckwaerts heim.
-- Doku in SkillFXConfig ("BAUSTEINE", Zeitstillstand).
--------------------------------------------------------------------------------

local CHRONO_IVORY = Color3.fromRGB(255, 246, 220)
local CHRONO_INK = Color3.fromRGB(20, 25, 60)
local CHRONO_ROMAN = { "XII", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI" }

-- Nachbild einer Figur in ihrer AKTUELLEN Pose: schimmerndes Kraftfeld in
-- `color`, verblasst in `life` s (lokal, raeumt sich selbst weg).
local function chronoGhost(src: Model, color: Color3, tr0: number, life: number): Model?
	local g = figureClone(src)
	if not g then return nil end
	for _, d in g:GetDescendants() do
		if d:IsA("BasePart") then
			d.Material = Enum.Material.ForceField
			d.Color = color
			d.Transparency = tr0
			d.CastShadow = false
			if d:IsA("MeshPart") then
				pcall(function() (d :: MeshPart).TextureID = "" end)
			end
			tween(d, life, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		elseif d:IsA("Decal") or d:IsA("SurfaceAppearance") or d:IsA("ParticleEmitter")
			or d:IsA("Light") or d:IsA("Trail") or d:IsA("Beam") then
			d:Destroy()
		end
	end
	g.Name = "SkillFXGhost"
	g.Parent = folder()
	Debris:AddItem(g, life + 0.15)
	return g
end

-- Stirn-Uhr eines Modells (Teile mit "clock_face", "hand_h", "hand_m" im
-- Namen). Rueckgabe: set(minuteGrad, stundeGrad) dreht die Zeiger um die
-- Mitte des Zifferblatts (0 = XII; nach jedem PivotTo aufrufen) - oder nil,
-- wenn das Modell keine Uhr hat. `scaleOf()` = Groesse relativ zum Start.
local function headClock(model: Model, scaleOf: () -> number): ((number, number) -> ())?
	local face: BasePart? = nil
	local hh: BasePart? = nil
	local hm: BasePart? = nil
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local n = string.lower(d.Name)
			if string.find(n, "clock_face", 1, true) then
				face = d
			elseif string.find(n, "hand_h", 1, true) then
				hh = d
			elseif string.find(n, "hand_m", 1, true) then
				hm = d
			end
		end
	end
	if not face or not hh or not hm then return nil end
	local faceP: BasePart = face
	local hourP: BasePart = hh
	local minP: BasePart = hm
	local f0 = faceP.CFrame
	local relH = f0:ToObjectSpace(hourP.CFrame)
	local relM = f0:ToObjectSpace(minP.CFrame)
	-- Der Stundenzeiger zeigt im Modell auf XII: seine Richtung = "oben".
	local up = math.atan2(relH.Position.Y, relH.Position.X)
	local mOff = up - math.atan2(relM.Position.Y, relM.Position.X)
	return function(minDeg: number, hourDeg: number)
		local sc = scaleOf()
		local f = faceP.CFrame
		hourP.CFrame = f * CFrame.Angles(0, 0, -math.rad(hourDeg)) * (CFrame.new(relH.Position * sc) * relH.Rotation)
		minP.CFrame = f * CFrame.Angles(0, 0, mOff - math.rad(minDeg)) * (CFrame.new(relM.Position * sc) * relM.Rotation)
	end
end

-- timewalk: der Chronos-Baerchi SELBST (echter Klon, Original lokal
-- unsichtbar, F03). Duckt sich, steigt mit Drehung auf und waechst; die Uhr
-- auf seiner Stirn rast immer schneller, goldener Zeitsand rieselt. Bei
-- `stopAt` springt die Uhr auf XII und der Sand bleibt in der Luft haengen
-- (TimeScale 0). Bei `blinkAt` springt er durch die Zeit: Spur aus goldenen
-- Nachbildern, er steht `lift` Studs ueber dem Platz vor dem Gegner, haengt
-- `appear` s, stampft in `slam` s mit zwei Drehungen auf (Landung = Einschlag,
-- der Sand faellt weiter), haelt `hold` s und spult in `back` s rueckwaerts
-- nach Hause (blaue Nachbilder, Uhr dreht rueckwaerts). Setzt ctx.avatarCf.
-- `trailLife` (optional) = wie lange die Spur-Nachbilder halten (Test-Buehnen).
--   height, crouch, rise, spins, grow, stopAt, blinkAt, appear, lift, slam, hold, back, ghosts, trailLife
BLOCKS.timewalk = function(ctx, s)
	local source = ctx.selfModel
	if not source or not source.Parent then return end
	local clone = figureClone(source)
	if not clone then return end
	local H = ctx.selfSize.Y
	local home = CFrame.lookAt(ctx.selfFeet, ctx.selfFeet + ctx.fwd)
	local offset = home:ToObjectSpace(clone:GetPivot())
	local okScale, got = pcall(function() return clone:GetScale() end)
	local baseScale: number = if okScale and typeof(got) == "number" then got else 1
	local height = s.height or 5
	local crouch = s.crouch or 0.3
	local rise = s.rise or 0.8
	local spins = s.spins or 1
	local grow = s.grow or 1.25
	local stopAt = s.stopAt or 1.3
	local blinkAt = math.max(crouch + rise + 0.05, s.blinkAt or 2.25)
	local appear = s.appear or 0.2
	local lift = s.lift or 5
	local slam = math.max(0.08, s.slam or 0.25)
	local hold = s.hold or 0.35
	local back = math.max(0.2, s.back or 0.8)
	local nGhosts = s.ghosts or 4
	local slamAt = blinkAt + appear
	local landAt = slamAt + slam
	local backAt = landAt + hold
	local total = backAt + back
	local gap = (ctx.selfSize.Z + ctx.targetSize.Z) * 0.4 + 0.4
	local landFeet = ctx.targetFeet - ctx.fwd * gap
	local land = CFrame.lookAt(landFeet, landFeet + ctx.fwd)
	local topFeet = landFeet + Vector3.new(0, lift, 0)
	local gold = ctx.fx.color
	local paleBlue = ctx.fx.color2:Lerp(Color3.new(1, 1, 1), 0.35)
	local hide = hideFigure(source)

	local hl = Instance.new("Highlight")
	hl.Adornee = clone
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.FillColor = gold
	hl.FillTransparency = 0.9
	hl.OutlineColor = gold
	hl.OutlineTransparency = 0.15
	hl.Parent = clone

	-- Funken, Zeitsand, Landestaub, Schweif (EIN Anker an der Koerpermitte)
	local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, gold, home, 1)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARK_TEX
	sparks.Rate = 0
	sparks.Speed = NumberRange.new(4, 10)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Lifetime = NumberRange.new(0.35, 0.75)
	sparks.Drag = 2
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.32), NumberSequenceKeypoint.new(1, 0) })
	sparks.Color = ColorSequence.new(CHRONO_IVORY, gold)
	sparks.LightEmission = 1
	sparks.Parent = anchor
	local sand = Instance.new("ParticleEmitter")
	sand.Texture = SPARK_TEX
	sand.Rate = 0
	sand.Speed = NumberRange.new(0.3, 1.2)
	sand.SpreadAngle = Vector2.new(180, 180)
	sand.Lifetime = NumberRange.new(0.9, 1.4)
	sand.Acceleration = Vector3.new(0, -4, 0)
	sand.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.28), NumberSequenceKeypoint.new(1, 0.12) })
	sand.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.8, 0.25), NumberSequenceKeypoint.new(1, 1) })
	sand.Color = ColorSequence.new(gold, CHRONO_IVORY)
	sand.LightEmission = 0.8
	sand.Parent = anchor
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = SMOKE_TEX
	dust.Rate = 0
	dust.Speed = NumberRange.new(3, 8)
	dust.SpreadAngle = Vector2.new(180, 20)
	dust.Lifetime = NumberRange.new(0.5, 0.9)
	dust.Drag = 3
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, H * 0.3), NumberSequenceKeypoint.new(1, H * 0.8) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	dust.Color = ColorSequence.new(CHRONO_IVORY, ctx.fx.color2)
	dust.LightEmission = 0.3
	dust.Rotation = NumberRange.new(0, 360)
	dust.Parent = anchor
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, H * 0.45, 0)
	a0.Parent = anchor
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -H * 0.45, 0)
	a1.Parent = anchor
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.25
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(CHRONO_IVORY, gold)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	trail.Enabled = false
	trail.Parent = anchor

	local lastScale = 1
	local clock = headClock(clone, function() return lastScale end)
	-- Pose: Fuesse `feet`, gedreht um die Koerpermitte (wie `ascend`)
	local function place(feet: CFrame, pitch: number, yaw: number, roll: number, sc: number)
		if math.abs(sc - lastScale) > 0.008 then
			lastScale = sc
			pcall(function() clone:ScaleTo(baseScale * sc) end)
		end
		local half = H * sc * 0.5
		local pose = feet * CFrame.new(0, half, 0) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll) * CFrame.new(0, -half, 0)
		ctx.avatarCf = pose
		ctx.avatarScale = sc
		clone:PivotTo(pose * CFrame.new(offset.Position * sc) * offset.Rotation)
		anchor.CFrame = pose * CFrame.new(0, half, 0)
	end
	place(home, 0, 0, 0, 1)
	clone.Parent = folder()
	hide(1)
	if clock then clock(0, 0) end

	local mDeg = 0
	local hover = home.Position + Vector3.new(0, height, 0)
	local stopped, blinked, landed, sanding = false, false, false, false
	local nextGhost = 0
	local ghostEvery = if extrasOn(ctx) then 0.09 else 0.18
	runLoop("timewalk", function(t, dt)
		if t >= total or not clone.Parent then return true end
		if t < crouch then
			-- 1. ausholen: zuruecklehnen, kleiner werden
			local e = math.sin((t / crouch) * math.pi * 0.5)
			place(home, 0.25 * e, 0, 0, 1 - 0.08 * e)
		elseif t < crouch + rise then
			-- 2. aufsteigen mit Drehung, wachsen, Zeitsand rieselt
			local k = (t - crouch) / rise
			local e = easeOutCubic(k)
			if not sanding and not stopped then
				sanding = true
				sand.Rate = 16 * ctx.factor
				sparks:Emit(scaled(18, ctx.factor))
			end
			place(home + Vector3.new(0, height * easeOutBack(k), 0), 0.25 * (1 - e), spins * TAU * e, 0, lerpN(0.92, grow, e))
		elseif t < blinkAt then
			-- 3. schweben; bei `stopAt` bleibt die Zeit stehen
			local h = t - crouch - rise
			if not stopped and t >= stopAt then
				stopped = true
				sand.Rate = 0
				sand.TimeScale = 0
				sparks:Emit(scaled(36, ctx.factor))
			end
			if stopped then
				-- nur er bewegt sich noch: lehnt sich vor, bebt vor dem Sprung
				local tension = math.clamp(1 - (blinkAt - t) / 0.45, 0, 1)
				local jit = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 0.16 * tension
				place(CFrame.new(hover + jit) * home.Rotation, -0.1 - 0.15 * tension, 0, 0, grow)
			else
				local feet = home + Vector3.new(0, height + math.sin(h * 3) * 0.25, 0)
				hover = feet.Position
				place(feet, 0, 0, math.sin(h * 2) * 0.05, grow * (1 + 0.03 * math.sin(h * 9)))
			end
		elseif t < slamAt then
			-- 4. Sprung durch die Zeit: Nachbilder-Spur, haengt ueber dem Gegner
			if not blinked then
				blinked = true
				for i = 1, nGhosts do
					local k = i / (nGhosts + 1)
					local pos = hover:Lerp(topFeet, k)
					place(CFrame.lookAt(pos, pos + ctx.fwd), -0.25, 0, 0, grow)
					chronoGhost(clone, gold, lerpN(0.35, 0.05, k), s.trailLife or (0.35 + 0.08 * i))
				end
				burstAt(ctx, hover + Vector3.new(0, H * grow * 0.5, 0), 20, 8, gold)
				burstAt(ctx, topFeet + Vector3.new(0, H * grow * 0.5, 0), 26, 10, gold)
			end
			local k = (t - blinkAt) / appear
			local jit = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 0.1
			place(CFrame.lookAt(topFeet, topFeet + ctx.fwd) + jit, -0.25 - 0.2 * k, 0, 0, grow)
		elseif t < landAt then
			-- 5. Stampfer: immer schneller, zwei Drehungen
			local k = (t - slamAt) / slam
			local e = k * k
			trail.Enabled = true
			local pos = topFeet:Lerp(landFeet, e)
			place(CFrame.lookAt(pos, pos + ctx.fwd), lerpN(-0.45, 0, e), 2 * TAU * e, 0, lerpN(grow, 1.12, e))
		elseif t < backAt then
			-- 6. Landung: gebueckt, die Zeit laeuft weiter
			local k = (t - landAt) / hold
			if not landed then
				landed = true
				trail.Enabled = false
				sand.TimeScale = 1
				dust:Emit(scaled(26, ctx.factor))
				sparks:Emit(scaled(40, ctx.factor))
			end
			place(land, lerpN(0.4, 0, easeOutCubic(k)), 0, 0, lerpN(1.12, 1, k))
		else
			-- 7. rueckwaerts nach Hause spulen
			local k = (t - backAt) / back
			local e = easeInOutSine(k)
			local pos = landFeet:Lerp(home.Position, e) + Vector3.new(0, math.sin(math.pi * k) * 3.5, 0)
			place(CFrame.lookAt(pos, pos + ctx.fwd), -0.2 * math.sin(math.pi * k), -2 * TAU * e, 0, 1)
			mDeg -= 1500 * dt
			if t >= nextGhost then
				nextGhost = t + ghostEvery
				chronoGhost(clone, paleBlue, 0.2, 0.4)
			end
		end
		-- Stirn-Uhr: rast bis zum Stillstand, steht dann auf XII
		if clock then
			if not stopped then
				local ramp = math.clamp(t / stopAt, 0, 1)
				mDeg += (120 + 2600 * ramp * ramp) * dt
			elseif t < backAt then
				mDeg = 0
			end
			clock(mDeg, mDeg / 12)
		end
		return false
	end, function()
		hide(0)
		ctx.avatarCf = nil
		ctx.avatarScale = nil
		clone:Destroy()
		sand.Rate = 0
		sand.TimeScale = 1
		Debris:AddItem(anchor, 1.2)
	end)
end

-- clockface: riesiges Zifferblatt hinter der Arena (at = "target": klein ueber
-- dem Gegner, z. B. im Echo). Dunkelblaue Scheibe, darauf als GUI
-- (SurfaceGui, F06): Ringe, 60 Minutenstriche, 12 roemische Ziffern, Stunden-
-- und Minutenzeiger. Steht `lift` Studs ueber dem Boden und `back` Studs
-- HINTER der Arena-Mitte - von der Kamera DIESES Clients aus - und dreht sich
-- in jedem Bild zu ihr (F04). Bis `stopAt` rasen die Zeiger, dann springen sie
-- auf "XII minus Zahl der Ticks"; jeder Eintrag in `ticks` rueckt den
-- Minutenzeiger eine Minute vor, der letzte steht auf XII (alles gleisst).
-- `crackAt`: Risse; `shatterAt`: zerspringt in Scherben (sonst Verblassen).
--   at, radius, lift, back, draw, stopAt, ticks, crackAt, shatterAt, dur
BLOCKS.clockface = function(ctx, s)
	local R = s.radius or 8
	local lift = s.lift or 10
	local backD = s.back or 8
	local draw = math.max(0.05, s.draw or 0.7)
	local stopAt = s.stopAt or 1
	local ticks: { number } = s.ticks or {}
	local nTicks = #ticks
	local dur = s.dur or 3
	local crackAt: number? = s.crackAt
	local shatterAt: number? = s.shatterAt
	local gold = ctx.fx.color
	local blue = ctx.fx.color2
	local onTarget = s.at == "target"
	local mid = groundAt(ctx, "arena")
	local dir = sideOf(ctx)
	local function wantDir(): Vector3
		local cam = workspace.CurrentCamera
		if cam then
			local v = mid - cam.CFrame.Position
			v = Vector3.new(v.X, 0, v.Z)
			if v.Magnitude > 1 then return v.Unit end
		end
		return dir
	end
	dir = wantDir()
	local function frameNow(dt: number): CFrame
		local c: Vector3
		if onTarget then
			c = ctx.targetPos + Vector3.new(0, ctx.targetSize.Y * 0.5 + lift, 0)
		else
			local w = wantDir()
			-- weich nachfuehren; bei einem Kameraschnitt (> 30 Grad) sofort springen
			local d = if dir:Dot(w) < 0.87 then w else dir:Lerp(w, math.clamp(dt * 5, 0, 1))
			dir = if d.Magnitude > 0.05 then d.Unit else w
			c = mid + dir * backD + Vector3.new(0, lift, 0)
		end
		local cam = workspace.CurrentCamera
		local eye = if cam then cam.CFrame.Position else c - ctx.fwd * 10
		local look = Vector3.new(eye.X, lerpN(c.Y, eye.Y, 0.45), eye.Z)
		if (look - c).Magnitude < 0.1 then look = c - ctx.fwd end
		return CFrame.lookAt(c, look)
	end
	local PPS = if R > 4 then 26 else 48
	local canvas = R * 2.2
	local u = 1 / canvas
	local fr0 = frameNow(1)
	local DISC_TURN = CFrame.Angles(0, math.rad(90), 0)
	local disc = newPart(Enum.PartType.Cylinder, Vector3.new(0.1, 0.2, 0.2), blue, fr0 * CFrame.new(0, 0, 0.08) * DISC_TURN, 0.2)
	disc.Material = Enum.Material.SmoothPlastic
	tween(disc, draw * 0.5, { Size = Vector3.new(0.1, R * 2.04, R * 2.04) }, Enum.EasingStyle.Quart)
	local plate = newPart(Enum.PartType.Block, Vector3.new(canvas, canvas, 0.05), gold, fr0, 1)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PPS
	gui.LightInfluence = 0
	gui.Brightness = 3
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Adornee = plate
	gui.Parent = plate
	local strokes: { UIStroke } = {}
	local ringBase: { [UIStroke]: number } = {}
	local fills: { Frame } = {}
	local texts: { TextLabel } = {}
	local function layer(z: number): Frame
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.fromScale(1, 1)
		f.BackgroundTransparency = 1
		f.ZIndex = z
		f.Parent = gui
		return f
	end
	local faceL, layerH, layerM, top = layer(1), layer(2), layer(3), layer(4)
	local function circle(parent: Frame, radius: number, thick: number, color: Color3, delay: number, fill: boolean?)
		local c = Instance.new("Frame")
		c.AnchorPoint = Vector2.new(0.5, 0.5)
		c.Position = UDim2.fromScale(0.5, 0.5)
		c.Size = UDim2.fromScale(0, 0)
		c.BackgroundColor3 = color
		c.BackgroundTransparency = if fill then 0 else 1
		c.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = c
		if fill then
			table.insert(fills, c)
		else
			local st = Instance.new("UIStroke")
			st.Color = color
			st.Thickness = thick * PPS
			st.Parent = c
			table.insert(strokes, st)
			ringBase[st] = st.Thickness
		end
		c.Parent = parent
		local d = radius * 2 * u
		tweenLater(c, delay, draw * 0.45, { Size = UDim2.fromScale(d, d) }, Enum.EasingStyle.Quart)
	end
	-- Strich von a nach b (Studs relativ zur Mitte, GUI: y nach unten)
	local function bar(parent: Frame, a: Vector2, b: Vector2, thick: number, color: Color3, delay: number, fadeIn: number)
		local m = (a + b) / 2
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5 + m.X * u, 0.5 + m.Y * u)
		f.Size = UDim2.new((b - a).Magnitude * u, 0, 0, math.max(2, thick * PPS))
		f.Rotation = math.deg(math.atan2(b.Y - a.Y, b.X - a.X))
		f.BackgroundColor3 = color
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Parent = parent
		table.insert(fills, f)
		tweenLater(f, delay, fadeIn, { BackgroundTransparency = 0 })
	end
	local function hand(parent: Frame, length: number, tail: number, thick: number, color: Color3)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 1)
		f.Position = UDim2.fromScale(0.5, 0.5 + tail * u)
		f.Size = UDim2.new(thick * u, 0, (length + tail) * u, 0)
		f.BackgroundColor3 = color
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = f
		local st = Instance.new("UIStroke")
		st.Color = CHRONO_INK
		st.Thickness = math.max(1, 0.06 * PPS)
		st.Transparency = 1
		st.Parent = f
		f.Parent = parent
		table.insert(fills, f)
		table.insert(strokes, st)
		tweenLater(f, draw * 0.55, draw * 0.3, { BackgroundTransparency = 0 })
		tweenLater(st, draw * 0.55, draw * 0.3, { Transparency = 0.15 })
	end
	-- Ringe
	circle(faceL, R * 0.98, 0.36, gold, 0)
	circle(faceL, R * 0.9, 0.08, CHRONO_IVORY, draw * 0.08)
	circle(faceL, R * 0.56, 0.07, gold, draw * 0.18)
	-- 60 Minutenstriche, jeder fuenfte lang und golden
	for i = 0, 59 do
		local a = math.rad(i * 6)
		local d = Vector2.new(math.sin(a), -math.cos(a))
		local delay = draw * 0.2 + (i / 60) * draw * 0.45
		if i % 5 == 0 then
			bar(faceL, d * R * 0.77, d * R * 0.9, 0.18, gold, delay, draw * 0.15)
		else
			bar(faceL, d * R * 0.84, d * R * 0.9, 0.07, CHRONO_IVORY, delay, draw * 0.15)
		end
	end
	-- roemische Ziffern
	for i = 0, 11 do
		local a = math.rad(i * 30)
		local p = Vector2.new(math.sin(a), -math.cos(a)) * R * 0.66
		local lbl = Instance.new("TextLabel")
		lbl.AnchorPoint = Vector2.new(0.5, 0.5)
		lbl.Position = UDim2.fromScale(0.5 + p.X * u, 0.5 + p.Y * u)
		lbl.Size = UDim2.fromScale(R * 0.28 * u, R * 0.2 * u)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.Garamond
		pcall(function()
			lbl.FontFace = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)
		end)
		lbl.TextScaled = true
		lbl.Text = CHRONO_ROMAN[i + 1]
		lbl.TextColor3 = CHRONO_IVORY
		lbl.TextStrokeColor3 = CHRONO_INK
		lbl.TextStrokeTransparency = 1
		lbl.TextTransparency = 1
		lbl.Parent = faceL
		table.insert(texts, lbl)
		tweenLater(lbl, draw * 0.4 + i * draw * 0.035, draw * 0.25, { TextTransparency = 0, TextStrokeTransparency = 0.3 })
	end
	-- Zeiger und Nabe
	hand(layerH, R * 0.42, R * 0.08, 0.38, gold)
	hand(layerM, R * 0.8, R * 0.12, 0.22, CHRONO_IVORY)
	circle(top, R * 0.075, 0, gold, draw * 0.6, true)
	circle(top, R * 0.075, 0.06, CHRONO_INK, draw * 0.6)

	local function pulse(power: number)
		gui.Brightness = 3 + 6 * power
		tween(gui, 0.6, { Brightness = 3 })
		for st, base in ringBase do
			st.Thickness = base * (1 + power)
			tween(st, 0.45, { Thickness = base })
		end
	end
	local function crack()
		for i = 1, 7 do
			local a = (i / 7) * TAU + math.random() * 0.6
			local p = Vector2.new(math.cos(a), math.sin(a)) * R * (0.06 + math.random() * 0.14)
			for j = 1, 3 do
				local a2 = a + (math.random() - 0.5) * 0.8
				local q = p + Vector2.new(math.cos(a2), math.sin(a2)) * R * (0.22 + math.random() * 0.14)
				if q.Magnitude > R * 0.97 then q = q.Unit * R * 0.97 end
				bar(top, p, q, 0.11, Color3.new(1, 1, 1), j * 0.03, 0.04)
				p = q
			end
		end
	end
	local shardRig: { RigPart } = {}
	local function shatter(fr: CFrame)
		gui.Enabled = false
		disc.Transparency = 1
		local n = scaled(if onTarget then 8 else 20, ctx.factor)
		for i = 1, n do
			local a = math.random() * TAU
			local rr = R * math.sqrt(math.random()) * 0.95
			local pick = i % 3
			local col = if pick == 0 then gold elseif pick == 1 then blue else CHRONO_IVORY
			local p = Instance.new("WedgePart")
			local cf = fr * CFrame.new(math.cos(a) * rr, math.sin(a) * rr, 0) * DISC_TURN * CFrame.Angles(math.random() * TAU, 0, 0)
			prepPart(p, col, cf, if pick == 1 then 0.15 else 0)
			p.Size = Vector3.new(0.25, R * (0.12 + math.random() * 0.16), R * (0.1 + math.random() * 0.12))
			p.Material = if pick == 0 then Enum.Material.Neon elseif pick == 1 then Enum.Material.Glass else Enum.Material.SmoothPlastic
			table.insert(shardRig, { p = p, frame = CFrame.identity, size = p.Size, delay = 0, tr = p.Transparency, g = 1, fixed = true, lt = p.Transparency })
		end
		rigShatter(shardRig, fr.Position, if onTarget then 6 else 13)
		burstAt(ctx, fr.Position, if onTarget then 12 else 30, if onTarget then 7 else 14, gold)
	end

	local mDeg, hDeg = 0, 0
	local spinning = stopAt > 0
	local function stopHands()
		mDeg = 360 - 6 * nTicks
		hDeg = 330 + (60 - nTicks) * 0.5
		layerM.Rotation = mDeg
		layerH.Rotation = hDeg
	end
	if not spinning then stopHands() end
	local nextTick = 1
	local cracked, shattered, fading = false, false, false
	local shatterT = 0
	runLoop("clockface", function(t, dt)
		local fr = frameNow(dt)
		if not shattered then
			plate.CFrame = fr
			disc.CFrame = fr * CFrame.new(0, 0, 0.08) * DISC_TURN
		end
		if spinning then
			if t < stopAt then
				local ramp = math.clamp(t / stopAt, 0, 1)
				mDeg += (240 + 1500 * ramp) * dt
				hDeg = mDeg / 12
				layerM.Rotation = mDeg % 360
				layerH.Rotation = hDeg % 360
			else
				spinning = false
				stopHands()
				pulse(0.7)
			end
		end
		while not spinning and nextTick <= nTicks and t >= ticks[nextTick] do
			-- Tick: eine Minute weiter, mit kleinem Federn
			mDeg += 6
			hDeg += 0.5
			tween(layerM, 0.14, { Rotation = mDeg }, Enum.EasingStyle.Back)
			tween(layerH, 0.14, { Rotation = hDeg }, Enum.EasingStyle.Back)
			if nextTick == nTicks then
				pulse(1)
				disc.Color = gold
				tween(disc, 0.5, { Color = blue })
			end
			nextTick += 1
		end
		if crackAt and not cracked and t >= crackAt then
			cracked = true
			crack()
			pulse(1.2)
		end
		if shatterAt and not shattered and t >= shatterAt then
			shattered = true
			shatterT = t
			shatter(fr)
		end
		if shattered then
			local k = (t - shatterT) / math.max(0.2, dur - shatterT)
			rigFly(shardRig, dt, 1 - k)
		elseif not fading and t >= dur - 0.4 then
			fading = true
			for _, st in strokes do tween(st, 0.35, { Transparency = 1 }) end
			for _, f in fills do tween(f, 0.35, { BackgroundTransparency = 1 }) end
			for _, l in texts do tween(l, 0.35, { TextTransparency = 1, TextStrokeTransparency = 1 }) end
			tween(disc, 0.35, { Transparency = 1 })
		end
		return t >= dur
	end, function()
		plate:Destroy()
		disc:Destroy()
		for _, r in shardRig do r.p:Destroy() end
	end)
end

-- timebubble: Zeitblase. Ab Start treibt goldener Staub ueber der Arena (EIN
-- Emitter). Bei `stopAt` waechst aus dem Baerchi (Klon aus `timewalk`, sonst
-- `at`) in `grow` s eine schimmernde Kugel (Kraftfeld + duenne Neon-Huelle,
-- F05) auf `radius`; der Staub erstarrt in der Luft (TimeScale 0). Bei
-- `popAt` gleisst sie auf und platzt, der Staub faellt zu Boden.
--   at, radius, stopAt, grow, popAt, dust
BLOCKS.timebubble = function(ctx, s)
	local R = radiusOf(s.radius, 16)
	local stopAt = s.stopAt or 0.75
	local grow = math.max(0.05, s.grow or 0.4)
	local popAt = math.max(stopAt + grow, s.popAt or 2)
	local gold = ctx.fx.color
	local floor = groundAt(ctx, "arena")
	local box = newPart(Enum.PartType.Block, Vector3.new(R * 1.2, 6, R * 1.2), gold, CFrame.new(floor + Vector3.new(0, 3.6, 0)), 1)
	local em = Instance.new("ParticleEmitter")
	em.Shape = Enum.ParticleEmitterShape.Box
	em.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	em.Texture = SPARK_TEX
	em.Rate = 0
	em.Speed = NumberRange.new(0.2, 0.9)
	em.SpreadAngle = Vector2.new(180, 180)
	em.Lifetime = NumberRange.new(1.8, 2.6)
	em.Acceleration = Vector3.new(0, 0.6, 0)
	em.Drag = 0.4
	em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(0.5, 0.42), NumberSequenceKeypoint.new(1, 0.22) })
	em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.12, 0.05),
		NumberSequenceKeypoint.new(0.85, 0.2), NumberSequenceKeypoint.new(1, 1) })
	em.Color = ColorSequence.new(CHRONO_IVORY, gold)
	em.LightEmission = 1
	em.Rotation = NumberRange.new(0, 360)
	em.RotSpeed = NumberRange.new(-60, 60)
	em.Parent = box
	local n = scaled(s.dust or 36, ctx.factor)
	em:Emit(n)
	em.Rate = n * 0.5
	local ball: Part? = nil
	local shell: Part? = nil
	local stopped, popped = false, false
	runLoop("timebubble", function(t)
		if not stopped and t >= stopAt then
			stopped = true
			em.Rate = 0
			em.TimeScale = 0
			local cf = ctx.avatarCf
			local center = if cf then (cf * CFrame.new(0, ctx.selfSize.Y * (ctx.avatarScale or 1) * 0.5, 0)).Position else at(ctx, s.at)
			local b = newPart(Enum.PartType.Ball, Vector3.one, gold, CFrame.new(center), 0.1)
			b.Material = Enum.Material.ForceField
			local sh = newPart(Enum.PartType.Ball, Vector3.one, CHRONO_IVORY, CFrame.new(center), 0.86)
			tween(b, grow, { Size = Vector3.one * R * 2 }, Enum.EasingStyle.Quart)
			tween(sh, grow, { Size = Vector3.one * R * 2.02 }, Enum.EasingStyle.Quart)
			tweenLater(sh, grow, 0.35, { Transparency = 0.95 })
			ball, shell = b, sh
		end
		if stopped and not popped and t >= popAt then
			popped = true
			em.TimeScale = 1
			em.Acceleration = Vector3.new(0, -32, 0)
			if ball then
				ball.Color = CHRONO_IVORY
				tween(ball, 0.35, { Size = Vector3.one * R * 2.25, Transparency = 1 }, Enum.EasingStyle.Quart)
			end
			if shell then
				shell.Transparency = 0.55
				tween(shell, 0.3, { Size = Vector3.one * R * 2.3, Transparency = 1 }, Enum.EasingStyle.Quart)
			end
		end
		return popped and t >= popAt + 0.4
	end, function()
		if ball then ball:Destroy() end
		if shell then shell:Destroy() end
		em.Rate = 0
		em.TimeScale = 1
		Debris:AddItem(box, 1.5)
	end)
end

-- timefreeze: der GEGNER erstarrt in der Zeit (echter Klon, Original lokal
-- unsichtbar, F03): steht still mit grau-blauem Schimmer (F18), goldene
-- Uhrwerk-Ringe (Teile >= 0,28 Studs, F19) ziehen um ihn auf und ruecken
-- ruckweise weiter (alle `step` s ein Glied). Bei `hold` ist das Original
-- wieder da (= Einschlag, Server: Rueckstoss); die Ringe zerspringen und
-- verblassen in `linger` s.
--   hold, linger, rings, segs, step
BLOCKS.timefreeze = function(ctx, s)
	local source = ctx.targetModel
	if not source or not source.Parent then return end
	local clone = figureClone(source)
	if not clone then return end
	local hold = s.hold or 1.2
	local linger = math.max(0.1, s.linger or 0.7)
	local nRings = math.clamp(s.rings or 2, 1, 3)
	local segs = math.max(8, s.segs or 22)
	local stepT = math.max(0.1, s.step or 0.3)
	local gold = ctx.fx.color
	local hide = hideFigure(source)
	local hl = Instance.new("Highlight")
	hl.Adornee = clone
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.FillColor = Color3.fromRGB(150, 165, 215)
	hl.FillTransparency = 1
	hl.OutlineColor = gold
	hl.OutlineTransparency = 1
	hl.Parent = clone
	clone.Parent = folder()
	hide(1)
	tween(hl, 0.2, { FillTransparency = 0.85, OutlineTransparency = 0.3 })
	burstAt(ctx, ctx.targetPos, 16, 6, gold)
	local center = ctx.targetPos
	local r = math.max(ctx.targetSize.X, ctx.targetSize.Z) * 0.6 + 0.7
	local TILTS = {
		CFrame.Angles(math.rad(70), 0, math.rad(18)),
		CFrame.Angles(math.rad(-62), 0, math.rad(-28)),
		CFrame.Angles(0, 0, math.rad(90)),
	}
	-- Ring = goldene Glieder (Neon gedaempft, F17) + kleine radiale Striche
	-- aussen wie auf einem Zifferblatt (Elfenbein, kein Neon).
	local parts: { BasePart } = {}
	local info: { { k: number, a: number, tr: number, out: number } } = {}
	local segLen = TAU * r / segs
	local mark = math.max(2, math.floor(segs / 12))
	for k = 1, nRings do
		for i = 0, segs - 1 do
			local a = (i + 0.5) / segs * TAU
			local p = newPart(Enum.PartType.Block, Vector3.new(0.28, 0.28, segLen * 0.9), gold, PARK, 1)
			table.insert(parts, p)
			table.insert(info, { k = k, a = a, tr = 0.3, out = 0 })
			if i % mark == 0 then
				local tick = newPart(Enum.PartType.Block, Vector3.new(0.5, 0.25, 0.25), CHRONO_IVORY, PARK, 1)
				tick.Material = Enum.Material.SmoothPlastic
				table.insert(parts, tick)
				table.insert(info, { k = k, a = a, tr = 0, out = 0.38 })
			end
		end
	end
	local stepA = TAU / segs
	local rig: { RigPart } = {}
	local released = false
	runLoop("timefreeze", function(t, dt)
		if not released then
			if t >= hold then
				released = true
				hide(0)
				clone:Destroy()
				for i, p in parts do
					table.insert(rig, { p = p, frame = CFrame.identity, size = p.Size, delay = 0, tr = info[i].tr, g = 1, fixed = true, lt = p.Transparency })
				end
				rigShatter(rig, center, 8)
				burstAt(ctx, center, 22, 11, gold)
				return false
			end
			local ap = math.clamp(t / 0.3, 0, 1)
			local gr = math.max(0.05, easeOutBack(ap))
			local n = math.floor(t / stepT)
			local f = math.clamp((t - n * stepT) / 0.12, 0, 1)
			local turn = (n + easeOutBack(f)) * stepA
			local cfs: { CFrame } = table.create(#parts)
			for i, p in parts do
				local inf = info[i]
				local pivot = CFrame.new(center) * TILTS[inf.k] * CFrame.Angles(0, turn * (if inf.k % 2 == 1 then 1 else -1), 0)
				cfs[i] = pivot * CFrame.Angles(0, -inf.a, 0) * CFrame.new(r * gr + inf.out, 0, 0)
				local tr = if ap > 0.02 then inf.tr else 1
				if p.Transparency ~= tr then p.Transparency = tr end
			end
			workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
			return false
		end
		local k = (t - hold) / linger
		rigFly(rig, dt, 1 - k)
		return k >= 1
	end, function()
		hide(0)
		if clone.Parent then clone:Destroy() end
		for _, p in parts do p:Destroy() end
	end)
end

--------------------------------------------------------------------------------
-- 25.10.2026 Ewiger Sternenfall (InfinityStarfall, Unendlichkeits-Baerchi).
-- Der Baerchi steigt auf und fliegt ein riesiges Unendlichkeitszeichen an den
-- Himmel (Lichtband), Sternschnuppen fallen aus seiner Bahn und kesseln den
-- Gegner ein, am Boden leuchtet ein Energienetz; dann faellt das Zeichen in
-- ihn zusammen, er stuerzt als Komet herab und ein Kristall-Geysir bricht aus
-- dem Boden. Doku in SkillFXConfig ("BAUSTEINE", Sternenfall).
--------------------------------------------------------------------------------

local STAR_WHITE = Color3.fromRGB(230, 250, 255)
local CRYSTAL_GLASS = Color3.fromRGB(70, 180, 255)

-- Punkt auf der Lemniskate (liegende Acht) mit halber Breite `a`:
-- th = 0 rechte Spitze, th = pi/2 und 3pi/2 Kreuzungspunkt (Mitte).
local function lemniscate(th: number, a: number): Vector2
	local sn, cs = math.sin(th), math.cos(th)
	local d = 1 + sn * sn
	return Vector2.new(a * cs / d, a * sn * cs / d)
end

-- Ebene des Unendlichkeitszeichens: senkrecht, waagerecht zur Kamera DIESES
-- Clients gedreht - einmal beim Start festgelegt, damit die Bahn nicht mit
-- einer Kamerafahrt mitwandert (F22). Rueckgabe: Richtung zur Kamera, rechts.
local function infinityPlane(ctx: Ctx): (Vector3, Vector3)
	local normal = sideOf(ctx)
	local cam = workspace.CurrentCamera
	if cam then
		local v = cam.CFrame.Position - ctx.arena
		v = Vector3.new(v.X, 0, v.Z)
		if v.Magnitude > 1 then
			normal = v.Unit
		end
	end
	return normal, Vector3.yAxis:Cross(normal).Unit
end

-- Ein Kristall aus zwei gekreuzten Glas-Klingen mit schmalem Leuchtkern
-- (Rig, waechst von unten, F17: Neon nur als duenner Kern). `frame` = Mitte
-- der Grundlinie, lokale Y-Achse = Kristall-Achse.
local function addCrystal(rig: { RigPart }, frame: CFrame, height: number, halfBase: number,
	glass: Color3, core: Color3, delay: number)
	for turn = 0, 1 do
		local f = frame * CFrame.Angles(0, turn * math.pi / 2, 0)
		for side = -1, 1, 2 do
			local w = Instance.new("WedgePart")
			prepPart(w, glass, PARK, 1)
			w.Material = Enum.Material.Glass
			w.Reflectance = 0.12
			local wf = f * CFrame.new(0, 0, side * halfBase / 2)
				* (if side > 0 then CFrame.Angles(0, math.pi, 0) else CFrame.identity)
			rigPart(rig, w, wf, Vector3.new(halfBase * 0.5, height, halfBase), delay, 0.2)
		end
	end
	for side = -1, 1, 2 do
		local w = Instance.new("WedgePart")
		prepPart(w, core, PARK, 1)
		local wf = frame * CFrame.Angles(0, math.pi / 4, 0) * CFrame.new(0, 0, side * halfBase * 0.17)
			* (if side > 0 then CFrame.Angles(0, math.pi, 0) else CFrame.identity)
		rigPart(rig, w, wf, Vector3.new(0.16, height * 0.88, halfBase * 0.36), delay, 0.25)
	end
end

-- Unendlichkeits-Reif auf dem Kopf eines Modells (Teile mit "acc_loop" und
-- "acc_star" im Namen, Bezug = Teil "..._body"). set(spin, phase) dreht den
-- Reif um seine Hochachse und laesst die Sterne auf der Acht um die Wette
-- laufen. Nach jedem PivotTo aufrufen; nil, wenn das Modell keinen Reif hat.
-- `scaleOf()` = Groesse relativ zum Start.
local function headInfinity(model: Model, scaleOf: () -> number): ((number, number) -> ())?
	local body: BasePart? = nil
	local loop: BasePart? = nil
	local stars: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local n = string.lower(d.Name)
			if string.find(n, "acc_loop", 1, true) then
				loop = d
			elseif string.find(n, "acc_star", 1, true) then
				table.insert(stars, d)
			elseif n == "body" or string.sub(n, -5) == "_body" then
				body = d
			end
		end
	end
	if not body or not loop or #stars == 0 then return nil end
	local bodyP: BasePart = body
	local loopP: BasePart = loop
	local relLoop = bodyP.CFrame:ToObjectSpace(loopP.CFrame)
	local starRot: { CFrame } = {}
	for i, st in stars do
		starRot[i] = loopP.CFrame:ToObjectSpace(st.CFrame).Rotation
	end
	local A = loopP.Size.X * 0.42
	return function(spin: number, phase: number)
		local sc = scaleOf()
		local lcf = bodyP.CFrame * CFrame.new(relLoop.Position * sc) * relLoop.Rotation * CFrame.Angles(0, spin, 0)
		loopP.CFrame = lcf
		for i, st in stars do
			local p = lemniscate(phase + (i - 1) * math.pi, A * sc)
			st.CFrame = lcf * CFrame.new(p.X, 0, p.Y) * starRot[i]
		end
	end
end

-- starfall: der Unendlichkeits-Baerchi SELBST (echter Klon, Original lokal
-- unsichtbar, F03). Duckt sich, steigt mit Drehung auf und waechst; sein
-- Kopf-Reif dreht sich, die Sterne rasen auf der Acht. Ab `loopAt` fliegt er
-- ein riesiges liegendes Unendlichkeitszeichen (halbe Breite `span`, Hoehe
-- x `tall`, Mitte `lift` Studs ueber der Arena, zur Kamera dieses Clients
-- gedreht) und hinterlaesst ein Lichtband aus `segs` Stuecken; er haengt
-- bebend im Kreuzungspunkt; bei `diveAt` faellt das Band in ihn zusammen und
-- er stuerzt in `dive` s mit `flips` Vorwaerts-Saltos als Komet vor den
-- Gegner (Landung = Einschlag), haelt `hold` s und springt mit einem
-- Rueckwaerts-Salto in `back` s heim. Setzt ctx.avatarCf und
-- ctx.infCenter/infRight/infNormal/infSpan.
--   height, crouch, rise, spins, grow, loopAt, loop, span, tall, lift, diveAt, dive, flips, hold, back, segs
BLOCKS.starfall = function(ctx, s)
	local source = ctx.selfModel
	if not source or not source.Parent then return end
	local clone = figureClone(source)
	if not clone then return end
	local H = ctx.selfSize.Y
	local home = CFrame.lookAt(ctx.selfFeet, ctx.selfFeet + ctx.fwd)
	local offset = home:ToObjectSpace(clone:GetPivot())
	local okScale, got = pcall(function() return clone:GetScale() end)
	local baseScale: number = if okScale and typeof(got) == "number" then got else 1
	local height = s.height or 6
	local crouch = s.crouch or 0.3
	local rise = s.rise or 0.6
	local spins = s.spins or 1
	local grow = s.grow or 1.25
	local loopAt = math.max(crouch + rise, s.loopAt or 0.9)
	local loopDur = math.max(0.4, s.loop or 1.3)
	local enter = math.min(0.3, loopDur * 0.2)
	local span = s.span or 8
	local tall = s.tall or 1.3
	local lift = s.lift or 11
	local diveAt = math.max(loopAt + loopDur + 0.05, s.diveAt or 2.55)
	local dive = math.max(0.08, s.dive or 0.25)
	local flips = s.flips or 2
	local hold = s.hold or 0.35
	local back = math.max(0.2, s.back or 0.7)
	local nSeg = math.max(16, s.segs or 56)
	local landAt = diveAt + dive
	local backAt = landAt + hold
	local total = backAt + back
	local gap = (ctx.selfSize.Z + ctx.targetSize.Z) * 0.4 + 0.4
	local landFeet = ctx.targetFeet - ctx.fwd * gap
	local land = CFrame.lookAt(landFeet, landFeet + ctx.fwd)
	local col = ctx.fx.color
	local coreCol = col:Lerp(Color3.new(1, 1, 1), 0.55)
	local hide = hideFigure(source)

	-- Ebene des Zeichens (einmal beim Start, F22) und Bahnpunkte
	local normal, right = infinityPlane(ctx)
	local faceRot = CFrame.lookAt(Vector3.zero, normal)
	local center = (ctx.selfFeet + ctx.targetFeet) / 2 + Vector3.new(0, lift, 0)
	ctx.infCenter = center
	ctx.infRight = right
	ctx.infNormal = normal
	ctx.infSpan = span
	local pts: { Vector3 } = table.create(nSeg + 1)
	for i = 0, nSeg do
		local p = lemniscate(math.pi / 2 + TAU * i / nSeg, span)
		pts[i + 1] = center + right * p.X + Vector3.yAxis * (p.Y * tall)
	end

	local hl = Instance.new("Highlight")
	hl.Adornee = clone
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.FillColor = col
	hl.FillTransparency = 0.88
	hl.OutlineColor = coreCol
	hl.OutlineTransparency = 0.15
	hl.Parent = clone

	-- Funken, Sternenstaub (Flug), Landestaub (EIN Anker an der Koerpermitte)
	local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, home, 1)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARK_TEX
	sparks.Rate = 0
	sparks.Speed = NumberRange.new(4, 10)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Lifetime = NumberRange.new(0.35, 0.75)
	sparks.Drag = 2
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.32), NumberSequenceKeypoint.new(1, 0) })
	sparks.Color = ColorSequence.new(STAR_WHITE, col)
	sparks.LightEmission = 1
	sparks.Parent = anchor
	local stream = Instance.new("ParticleEmitter")
	stream.Texture = SPARK_TEX
	stream.Rate = 0
	stream.Speed = NumberRange.new(0.3, 1.5)
	stream.SpreadAngle = Vector2.new(180, 180)
	stream.Lifetime = NumberRange.new(0.6, 1.1)
	stream.Drag = 1
	stream.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
	stream.Color = ColorSequence.new(STAR_WHITE, col)
	stream.LightEmission = 1
	stream.Parent = anchor
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = SMOKE_TEX
	dust.Rate = 0
	dust.Speed = NumberRange.new(3, 8)
	dust.SpreadAngle = Vector2.new(180, 20)
	dust.Lifetime = NumberRange.new(0.5, 0.9)
	dust.Drag = 3
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, H * 0.3), NumberSequenceKeypoint.new(1, H * 0.8) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	dust.Color = ColorSequence.new(STAR_WHITE, ctx.fx.color2)
	dust.LightEmission = 0.3
	dust.Rotation = NumberRange.new(0, 360)
	dust.Parent = anchor

	-- Kometen-Huelle (Kraftfeld) mit Schweif, nur im Sturz sichtbar
	local shell = newPart(Enum.PartType.Ball, Vector3.one * H * 1.5, col, home, 1)
	shell.Material = Enum.Material.ForceField
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(H * 0.55, 0, 0)
	a0.Parent = shell
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(-H * 0.55, 0, 0)
	a1.Parent = shell
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.35
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, STAR_WHITE),
		ColorSequenceKeypoint.new(0.35, col),
		ColorSequenceKeypoint.new(1, ctx.fx.color2),
	})
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.1) })
	trail.Enabled = false
	trail.Parent = shell

	-- Lichtband: duenner heller Kern + weicher Schein je Stueck (F17/F19)
	local ribbon: { BasePart } = {}
	local drawn = 0
	local function addSeg(i: number)
		local a, b = pts[i], pts[i + 1]
		local len = (b - a).Magnitude + 0.15
		local cf = CFrame.lookAt((a + b) / 2, b, normal) * CFrame.Angles(0, math.rad(90), 0)
		table.insert(ribbon, newPart(Enum.PartType.Cylinder, Vector3.new(len, 0.34, 0.34), coreCol, cf, 0.25))
		table.insert(ribbon, newPart(Enum.PartType.Cylinder, Vector3.new(len, 0.95, 0.95), col, cf, 0.78))
	end
	local function collapse()
		for _, p in ribbon do
			if p.Parent then
				tween(p, 0.18, { CFrame = CFrame.new(center) * p.CFrame.Rotation, Size = Vector3.new(0.3, 0.05, 0.05), Transparency = 1 },
					Enum.EasingStyle.Quad, Enum.EasingDirection.In)
				Debris:AddItem(p, 0.3)
			end
		end
		burstAt(ctx, center, 34, 12, col)
	end

	local lastScale = 1
	local headInf = headInfinity(clone, function() return lastScale end)
	-- Pose: Fuesse `feet`, gedreht um die Koerpermitte (wie `ascend`)
	local function place(feet: CFrame, pitch: number, yaw: number, roll: number, sc: number)
		if math.abs(sc - lastScale) > 0.008 then
			lastScale = sc
			pcall(function() clone:ScaleTo(baseScale * sc) end)
		end
		local half = H * sc * 0.5
		local pose = feet * CFrame.new(0, half, 0) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll) * CFrame.new(0, -half, 0)
		ctx.avatarCf = pose
		ctx.avatarScale = sc
		clone:PivotTo(pose * CFrame.new(offset.Position * sc) * offset.Rotation)
		anchor.CFrame = pose * CFrame.new(0, half, 0)
	end
	place(home, 0, 0, 0, 1)
	clone.Parent = folder()
	hide(1)

	local hover = home.Position + Vector3.new(0, height, 0)
	local hangSc = grow * 0.88
	local diveFrom = center - Vector3.new(0, H * hangSc * 0.5, 0)
	local diveDir = (landFeet - diveFrom).Unit
	local flyRate = (if extrasOn(ctx) then 40 else 16) * ctx.factor
	local spinA, phase = 0, 0
	local risen, diving, landed = false, false, false
	runLoop("starfall", function(t, dt)
		if t >= total or not clone.Parent then return true end
		local spinSpeed, phaseSpeed = 2, 3
		if t < crouch then
			-- 1. ausholen: zuruecklehnen, kleiner werden
			local e = math.sin((t / crouch) * math.pi * 0.5)
			place(home, 0.28 * e, 0, 0, 1 - 0.08 * e)
			spinSpeed, phaseSpeed = 3, 5
		elseif t < crouch + rise then
			-- 2. aufsteigen mit Drehung, wachsen
			local k = (t - crouch) / rise
			local e = easeOutCubic(k)
			if not risen then
				risen = true
				sparks:Emit(scaled(24, ctx.factor))
				dust:Emit(scaled(14, ctx.factor))
			end
			place(home + Vector3.new(0, height * easeOutBack(k), 0), 0.28 * (1 - e), spins * TAU * e, 0, lerpN(0.92, grow, e))
			spinSpeed, phaseSpeed = 6, 9
		elseif t < loopAt then
			local h = t - crouch - rise
			place(home + Vector3.new(0, height + math.sin(h * 3) * 0.25, 0), 0, 0, 0, grow)
			spinSpeed, phaseSpeed = 6, 9
		elseif t < loopAt + loopDur then
			-- 3. das Unendlichkeitszeichen fliegen, Lichtband zeichnen
			local half = H * grow * 0.5
			local pos: Vector3
			local yaw = 0
			if t < loopAt + enter then
				local k = easeInOutSine((t - loopAt) / enter)
				pos = (hover + Vector3.new(0, half, 0)):Lerp(pts[1], k)
			else
				local k = (t - loopAt - enter) / (loopDur - enter)
				local f = k * nSeg
				local i = math.clamp(math.floor(f), 0, nSeg - 1)
				pos = pts[i + 1]:Lerp(pts[i + 2], math.clamp(f - i, 0, 1))
				while drawn < math.min(nSeg, math.floor(f)) do
					drawn += 1
					addSeg(drawn)
				end
				yaw = TAU * k
			end
			stream.Rate = flyRate
			place(CFrame.new(pos - Vector3.new(0, half, 0)) * faceRot, -0.15, yaw, 0, grow)
			spinSpeed, phaseSpeed = 10, 16
		elseif t < diveAt then
			-- 4. haengt im Kreuzungspunkt, bebt, zieht sich zusammen
			while drawn < nSeg do
				drawn += 1
				addSeg(drawn)
			end
			stream.Rate = 0
			local tension = math.clamp((t - loopAt - loopDur) / math.max(0.05, diveAt - loopAt - loopDur), 0, 1)
			local jit = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 0.18 * tension
			local sc = lerpN(grow, hangSc, tension)
			place(CFrame.new(center - Vector3.new(0, H * sc * 0.5, 0) + jit) * faceRot, -0.3 * tension, 0, 0, sc)
			spinSpeed, phaseSpeed = 14, 22
		elseif t < landAt then
			-- 5. Sturz als Komet: das Band faellt in ihn zusammen, Vorwaerts-Saltos
			if not diving then
				diving = true
				while drawn < nSeg do
					drawn += 1
					addSeg(drawn)
				end
				collapse()
				shell.Size = Vector3.one * H * 1.45 * hangSc
				shell.Transparency = 0.35
				trail.Enabled = true
				sparks:Emit(scaled(30, ctx.factor))
				stream.Rate = flyRate * 1.5
			end
			local k = (t - diveAt) / dive
			local e = k * k
			local sc = lerpN(hangSc, 1.1, e)
			local pos = diveFrom:Lerp(landFeet, e)
			place(CFrame.lookAt(pos, pos + ctx.fwd), -flips * TAU * e, 0, 0, sc)
			local body = pos + Vector3.new(0, H * sc * 0.5, 0)
			shell.CFrame = CFrame.lookAt(body, body + diveDir, normal)
			spinSpeed, phaseSpeed = 14, 22
		elseif t < backAt then
			-- 6. Landung: gebueckt, richtet sich auf
			if not landed then
				landed = true
				trail.Enabled = false
				shell.Transparency = 1
				stream.Rate = 0
				dust:Emit(scaled(30, ctx.factor))
				sparks:Emit(scaled(44, ctx.factor))
			end
			local k = (t - landAt) / hold
			place(land, lerpN(-0.5, 0, easeOutCubic(k)), 0, 0, lerpN(1.1, 1, k))
			spinSpeed, phaseSpeed = 5, 8
		else
			-- 7. Rueckwaerts-Salto nach Hause
			local k = (t - backAt) / back
			local e = easeInOutSine(k)
			local pos = landFeet:Lerp(home.Position, e) + Vector3.new(0, math.sin(math.pi * k) * 4, 0)
			place(CFrame.lookAt(pos, pos + ctx.fwd), TAU * e, 0, 0, 1)
			spinSpeed, phaseSpeed = 3, 5
		end
		if headInf then
			spinA += spinSpeed * dt
			phase += phaseSpeed * dt
			headInf(spinA, phase)
		end
		return false
	end, function()
		hide(0)
		ctx.avatarCf = nil
		ctx.avatarScale = nil
		clone:Destroy()
		stream.Rate = 0
		for _, p in ribbon do
			if p.Parent then p:Destroy() end
		end
		shell:Destroy()
		Debris:AddItem(anchor, 1.2)
	end)
end

-- gridweb: Energienetz am Boden (GUI auf einer Platte wie `cropcircle`, F06):
-- dunkle Scheibe, verwackelte Speichen und Ringe aus Linien, schraege
-- Querstreben, helle Knoten; zeichnet sich von innen nach aussen, Knoten
-- flackern, gleisst bei `pulseAt` auf, verblasst am Ende.
--   at, radius, draw, dur, spokes, rings, spin, pulseAt
BLOCKS.gridweb = function(ctx, s)
	local center = groundAt(ctx, s.at or "target") + Vector3.new(0, 0.07, 0)
	local R = radiusOf(s.radius, 7)
	local dur = s.dur or 4
	local draw = s.draw or 0.9
	local spokes = math.max(5, s.spokes or 10)
	local nRings = math.max(1, s.rings or 3)
	local spin = s.spin or 0.08
	local col = pickColor(s, ctx.fx)
	local white = col:Lerp(Color3.new(1, 1, 1), 0.7)
	local PPS = 24
	local canvas = R * 2.3
	local u = 1 / canvas
	local disc = newPart(Enum.PartType.Cylinder, Vector3.new(0.03, 0.2, 0.2), ctx.fx.color2,
		CFrame.new(center - Vector3.new(0, 0.04, 0)) * CFrame.Angles(0, 0, math.rad(90)), 0.4)
	disc.Material = Enum.Material.SmoothPlastic
	tween(disc, draw * 0.6, { Size = Vector3.new(0.03, R * 2.15, R * 2.15) }, Enum.EasingStyle.Quart)
	local plate = newPart(Enum.PartType.Block, Vector3.new(canvas, 0.04, canvas), col, CFrame.new(center), 1)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PPS
	gui.LightInfluence = 0
	gui.Brightness = 3
	gui.Adornee = plate
	gui.Parent = plate
	local root = Instance.new("Frame")
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundTransparency = 1
	root.Parent = gui
	local bars: { Frame } = {}
	local barPx: { number } = {}
	local barLen: { number } = {}
	local nodes: { Frame } = {}
	local function bar(a: Vector2, b: Vector2, thick: number, color: Color3, delay: number)
		local mid = (a + b) / 2
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5 + mid.X * u, 0.5 + mid.Y * u)
		local px = math.max(2, thick * PPS)
		local len = (b - a).Magnitude * u
		f.Size = UDim2.new(0, 0, 0, px)
		f.Rotation = math.deg(math.atan2(b.Y - a.Y, b.X - a.X))
		f.BackgroundColor3 = color
		f.BackgroundTransparency = 0.05
		f.BorderSizePixel = 0
		f.Parent = root
		table.insert(bars, f)
		table.insert(barPx, px)
		table.insert(barLen, len)
		tweenLater(f, delay, draw * 0.22, { Size = UDim2.new(len, 0, 0, px) })
	end
	local function node(c: Vector2, r: number, color: Color3, delay: number)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5 + c.X * u, 0.5 + c.Y * u)
		f.Size = UDim2.fromScale(0, 0)
		f.BackgroundColor3 = color
		f.BackgroundTransparency = 0.05
		f.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = f
		f.Parent = root
		table.insert(nodes, f)
		local d = r * 2 * u
		tweenLater(f, delay, draw * 0.2, { Size = UDim2.fromScale(d, d) }, Enum.EasingStyle.Back)
	end
	-- Knotenpunkte: Ring j, Speiche i, leicht verwackelt (Netz, kein Kreis)
	local P: { { Vector2 } } = {}
	for j = 1, nRings do
		local row: { Vector2 } = {}
		local rr = R * j / nRings
		for i = 1, spokes do
			local a = (i / spokes) * TAU + (math.random() - 0.5) * 0.3
			row[i] = Vector2.new(math.cos(a), math.sin(a)) * rr * (0.9 + math.random() * 0.2)
		end
		P[j] = row
	end
	local Z = Vector2.zero
	node(Z, 0.45, white, 0)
	for j = 1, nRings do
		local d0 = draw * (j - 1) / nRings
		local d1 = draw * j / nRings
		for i = 1, spokes do
			local inner = if j == 1 then Z else P[j - 1][i]
			bar(inner, P[j][i], 0.2, col, d0)
			bar(P[j][i], P[j][i % spokes + 1], if j == nRings then 0.24 else 0.16, col, d1 * 0.9)
			if j > 1 and math.random() < 0.5 then
				bar(P[j - 1][i], P[j][i % spokes + 1], 0.1, col, d1 * 0.85)
			end
			node(P[j][i], if j == nRings then 0.32 else 0.24, white, d1)
		end
	end
	local pulsed, fading = false, false
	local nextFlick = 0
	runLoop("gridweb", function(t)
		root.Rotation = math.deg(t * spin)
		if not fading and t > draw and t >= nextFlick then
			nextFlick = t + 0.07
			local f = nodes[math.random(1, #nodes)]
			f.BackgroundColor3 = Color3.new(1, 1, 1)
			tween(f, 0.25, { BackgroundColor3 = white })
		end
		if s.pulseAt and not pulsed and t >= s.pulseAt then
			pulsed = true
			gui.Brightness = 10
			tween(gui, 0.9, { Brightness = 3 })
			disc.Color = col
			tween(disc, 0.8, { Color = ctx.fx.color2 })
			for i, f in bars do
				f.Size = UDim2.new(barLen[i], 0, 0, barPx[i] * 2.2)
				tween(f, 0.5, { Size = UDim2.new(barLen[i], 0, 0, barPx[i]) })
			end
		end
		if not fading and t >= dur - 0.45 then
			fading = true
			for _, f in bars do tween(f, 0.4, { BackgroundTransparency = 1 }) end
			for _, f in nodes do tween(f, 0.4, { BackgroundTransparency = 1 }) end
			tween(disc, 0.4, { Transparency = 1 })
		end
		return t >= dur
	end, function()
		plate:Destroy()
		disc:Destroy()
	end)
end

-- shootingstars: `count` Sternschnuppen fallen nacheinander (alle `every` s,
-- je `fall` s) aus der Bahn des `starfall`-Klons (sonst hoch ueber dem
-- Gegner) auf einen Ring (`radius`) um den Gegner - zur Seite des Angreifers
-- bleibt eine Luecke, abwechselnd links/rechts -, bei radius = 0 auf den
-- Gegner selbst. Am Einschlag: Funken, Bodenring und ein Busch aus `crystals`
-- kleinen Kristallen. Die Buesche stehen bis `breakAt` (ab Schritt-Start)
-- und zerspringen dann, ohne `breakAt` sinken sie nach `linger` ein.
--   at, count, every, fall, radius, size, crystals, breakAt, linger
BLOCKS.shootingstars = function(ctx, s)
	local count = math.max(1, s.count or 4)
	local every = s.every or 0.18
	local fall = math.max(0.05, s.fall or 0.3)
	local R = s.radius or 4.5
	local size = s.size or 0.7
	local nCrys = s.crystals or 3
	local breakAt = s.breakAt
	local linger = s.linger or 0.5
	local tgt = groundAt(ctx, s.at or "target")
	local side = sideOf(ctx)
	local col = ctx.fx.color
	local coreCol = col:Lerp(Color3.new(1, 1, 1), 0.55)
	-- Reihenfolge der Landepunkte: abwechselnd aussen links/rechts nach innen
	local order: { number } = {}
	local lo, hi = 1, count
	while lo <= hi do
		table.insert(order, lo)
		if hi ~= lo then table.insert(order, hi) end
		lo += 1
		hi -= 1
	end
	local stars: { { [string]: any } } = {}
	local rig: { RigPart } = {}
	local lastImpact = 0
	for n = 1, count do
		local idx = order[n]
		local dir: Vector3 = -ctx.fwd
		local landP = tgt
		if R > 0 then
			local k = if count == 1 then 0.5 else (idx - 1) / (count - 1)
			local a = math.rad(65 + 230 * k)
			dir = -ctx.fwd * math.cos(a) + side * math.sin(a)
			landP = tgt + dir * R
		end
		local t0 = (n - 1) * every
		local head = newPart(Enum.PartType.Ball, Vector3.one * size, col, PARK, 1)
		local core = newPart(Enum.PartType.Ball, Vector3.one * size * 0.55, STAR_WHITE, PARK, 1)
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, size * 0.5, 0)
		a0.Parent = head
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -size * 0.5, 0)
		a1.Parent = head
		local trail = Instance.new("Trail")
		trail.Attachment0 = a0
		trail.Attachment1 = a1
		trail.Lifetime = 0.22
		trail.LightEmission = 1
		trail.FaceCamera = true
		trail.Color = ColorSequence.new(STAR_WHITE, col)
		trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
		trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
		trail.Enabled = false
		trail.Parent = head
		local em = Instance.new("ParticleEmitter")
		em.Texture = SPARK_TEX
		em.Rate = 0
		em.Speed = NumberRange.new(1, 3)
		em.SpreadAngle = Vector2.new(180, 180)
		em.Lifetime = NumberRange.new(0.25, 0.45)
		em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.35), NumberSequenceKeypoint.new(1, 0) })
		em.Color = ColorSequence.new(STAR_WHITE, col)
		em.LightEmission = 1
		em.Parent = head
		table.insert(stars, { head = head, core = core, trail = trail, em = em, to = landP + Vector3.new(0, 0.3, 0),
			land = landP, dir = dir, t0 = t0, started = false, hit = false })
		lastImpact = math.max(lastImpact, t0 + fall)
		for c = 1, nCrys do
			local ang = (c / nCrys) * TAU + math.random() * 0.6
			local radial = Vector3.new(math.cos(ang), 0, math.sin(ang))
			local h = size * lerpN(2.2, 3.6, math.random())
			local tilt = math.rad(12 + math.random() * 25)
			local base = CFrame.fromMatrix(landP + radial * 0.25 - Vector3.new(0, 0.15, 0), radial, Vector3.yAxis)
				* CFrame.Angles(0, 0, -tilt) * CFrame.Angles(0, math.random() * TAU, 0)
			addCrystal(rig, base, h, h * 0.2, CRYSTAL_GLASS, coreCol, t0 + fall + c * 0.02)
		end
	end
	-- Startpunkt: wo der `starfall`-Klon gerade fliegt, sonst ueber dem Gegner
	local function origin(st: { [string]: any }): Vector3
		if ctx.avatarCf then
			return (ctx.avatarCf * CFrame.new(0, ctx.selfSize.Y * (ctx.avatarScale or 1) * 0.5, 0)).Position
		end
		local d: Vector3 = st.dir
		return (st.land :: Vector3) + Vector3.new(0, 16, 0) - ctx.fwd * 3 + side * (if d:Dot(side) >= 0 then 4 else -4)
	end
	local rise = 0.12
	local sink = 0.25
	local finishT = if breakAt then math.max(breakAt, lastImpact + rise) + 0.55 else lastImpact + rise + linger + sink
	local broken = false
	runLoop("shootingstars", function(t, dt)
		for _, st in stars do
			if not st.hit and t >= st.t0 then
				if not st.started then
					st.started = true
					st.from = origin(st)
					st.head.Transparency = 0
					st.core.Transparency = 0.1
					st.trail.Enabled = true
					st.em.Rate = 30 * ctx.factor
				end
				local k = math.clamp((t - st.t0) / fall, 0, 1)
				local from: Vector3 = st.from
				local to: Vector3 = st.to
				local pos = from:Lerp(to, k ^ 1.4)
				local mdir = to - from
				mdir = if mdir.Magnitude > 0.01 then mdir.Unit else Vector3.new(0, -1, 0)
				local up = if math.abs(mdir.Y) > 0.97 then side else Vector3.yAxis
				st.head.CFrame = CFrame.lookAt(pos, pos + mdir, up)
				st.core.CFrame = CFrame.new(pos)
				if k >= 1 then
					st.hit = true
					st.trail.Enabled = false
					st.em.Rate = 0
					fadeAndDestroy(st.head, 0.08)
					fadeAndDestroy(st.core, 0.08)
					local landP: Vector3 = st.land
					burstAt(ctx, landP + Vector3.new(0, 0.5, 0), 18, 9, col)
					local ring = newPart(Enum.PartType.Cylinder, Vector3.new(0.05, 0.3, 0.3), coreCol,
						CFrame.new(landP + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90)), 0.1)
					tween(ring, 0.35, { Size = Vector3.new(0.05, 4, 4), Transparency = 1 }, Enum.EasingStyle.Quart)
					Debris:AddItem(ring, 0.45)
				end
			end
		end
		if #rig > 0 then
			if breakAt and t >= breakAt then
				if not broken then
					broken = true
					rigShatter(rig, tgt + Vector3.new(0, 1, 0), 12)
				end
				rigFly(rig, dt, 1 - math.clamp((t - breakAt) / 0.55, 0, 1))
			else
				rigApply(rig, CFrame.identity, function(rp)
					local x = t - rp.delay
					if x <= 0 then return 0 end
					if x < rise then return easeOutBack(x / rise) end
					if breakAt then return 1 end
					x -= rise
					if x < linger then return 1 end
					x -= linger
					return math.max(0, 1 - math.min(1, x / sink) ^ 3)
				end, 1)
			end
		end
		return t >= finishT
	end, function()
		for _, rp in rig do rp.p:Destroy() end
		for _, st in stars do
			if st.head.Parent then st.head:Destroy() end
			if st.core.Parent then st.core:Destroy() end
		end
	end)
end

-- crystalgeyser: Kristall-Geysir. Hohe, schmale Glas-Kristalle mit
-- leuchtendem Kern brechen in Ringen aus dem Boden (innen die hoechsten, fast
-- senkrecht, aussen kleiner und schraeg), dazu schiesst eine Fontaene aus
-- Lichtsplittern senkrecht hoch (1 Emitter, `spray` Stueck) und eine kurze
-- weiche Lichtsaeule. `open`: zur Seite des Angreifers bleibt eine Luecke.
-- Bei `shatterAt` zerspringen die Kristalle, sonst sinken sie nach `linger` ein.
-- `needles` Kristall-Nadeln schiessen mit hoch (Fontaene aus Teilen, F19).
-- Test-Buehnen: `sprayFor` = Partikel-Fontaene dauerhaft, `freezeAt` = Nadeln anhalten.
--   at, count, rings, radius, minHeight, maxHeight, rise, stagger, linger, sink, shatterAt, spray, needles, open, sprayFor, freezeAt
BLOCKS.crystalgeyser = function(ctx, s)
	local center = groundAt(ctx, s.at or "target")
	local n = scaled(s.count or 14, ctx.factor)
	local rings = math.max(1, s.rings or 2)
	local R = s.radius or 3.2
	local minH = s.minHeight or 2.5
	local maxH = s.maxHeight or 7
	local rise = s.rise or 0.14
	local stagger = s.stagger or 0.03
	local linger = s.linger or 0.8
	local sink = s.sink or 0.3
	local shatterAt = s.shatterAt
	local col = pickColor(s, ctx.fx)
	local coreCol = col:Lerp(Color3.new(1, 1, 1), 0.55)
	local rig: { RigPart } = {}
	local sum = rings * (rings + 1) / 2
	local maxDelay = 0
	for j = 1, rings do
		local per = math.max(3, math.floor(n * j / sum + 0.5))
		local ringK = if rings == 1 then 0 else (j - 1) / (rings - 1)
		local rr = if rings == 1 then R else R * lerpN(0.5, 1, ringK)
		for i = 1, per do
			local a = (i / per) * TAU + j * 0.9 + (math.random() - 0.5) * 0.35
			local radial = Vector3.new(math.cos(a), 0, math.sin(a))
			if s.open and s.at ~= "self" and radial:Dot(-ctx.fwd) > 0.72 then continue end
			local h = lerpN(maxH, minH, ringK * 0.7 + math.random() * 0.3)
			local tilt = math.rad(lerpN(8, 32, ringK) + math.random() * 8)
			local base = CFrame.fromMatrix(center + radial * rr - Vector3.new(0, 0.3, 0), radial, Vector3.yAxis)
				* CFrame.Angles(0, 0, -tilt) * CFrame.Angles(0, math.random() * TAU, 0)
			local delay = (j - 1) * stagger * 2 + (i / per) * stagger
			maxDelay = math.max(maxDelay, delay)
			addCrystal(rig, base, h, math.max(0.35, h * 0.12), CRYSTAL_GLASS, coreCol, delay)
		end
	end
	-- Fontaene: Lichtsplitter schiessen senkrecht hoch (EIN Emitter)
	local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, CFrame.new(center + Vector3.new(0, 0.3, 0)), 1)
	local spray = Instance.new("ParticleEmitter")
	spray.Texture = SPARK_TEX
	spray.EmissionDirection = Enum.NormalId.Top
	spray.Rate = 0
	spray.Speed = NumberRange.new(22, 42)
	spray.SpreadAngle = Vector2.new(14, 14)
	spray.Lifetime = NumberRange.new(0.45, 0.8)
	spray.Acceleration = Vector3.new(0, -35, 0)
	spray.Drag = 0.6
	spray.Orientation = Enum.ParticleOrientation.VelocityParallel
	spray.Squash = NumberSequence.new(1.2)
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0.15) })
	spray.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.7, 0.2), NumberSequenceKeypoint.new(1, 1) })
	spray.Color = ColorSequence.new(coreCol, col)
	spray.LightEmission = 0.6
	spray.Parent = anchor
	spray:Emit(scaled(s.spray or 70, ctx.factor))
	if s.sprayFor then
		spray.Rate = 60 * ctx.factor
		task.delay(s.sprayFor, function() spray.Rate = 0 end)
	end
	-- Kristall-Nadeln schiessen als Fontaene hoch (Teile statt nur Partikel:
	-- im Tageslicht lesbar, F19). `freezeAt` (Test-Buehnen) haelt sie an.
	local needles: { { p: BasePart, pos: Vector3, v: Vector3 } } = {}
	local nNeedle = if (s.needles or 12) > 0 then scaled(s.needles or 12, ctx.factor) else 0
	local needleCol = col:Lerp(Color3.new(1, 1, 1), 0.35)
	for _ = 1, nNeedle do
		local a = math.random() * TAU
		local out = Vector3.new(math.cos(a), 0, math.sin(a)) * (2 + math.random() * 6)
		local v = out + Vector3.new(0, 30 + math.random() * 18, 0)
		local len = 2.2 + math.random() * 1.2
		local p = newPart(Enum.PartType.Block, Vector3.new(0.26, 0.26, len), needleCol, PARK, 0.15)
		table.insert(needles, { p = p, pos = center + Vector3.new(0, 0.5, 0) + out * 0.08, v = v })
	end
	local NEEDLE_LIFE = 0.75
	local colH = maxH * 1.6
	local column = newPart(Enum.PartType.Cylinder, Vector3.new(colH, 1.2, 1.2), col,
		CFrame.new(center + Vector3.new(0, colH / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), 0.6)
	tween(column, 0.4, { Size = Vector3.new(colH, 3.2, 3.2), Transparency = 1 })
	Debris:AddItem(column, 0.5)
	burstAt(ctx, center + Vector3.new(0, 0.8, 0), 28, 10, col, true)
	local finishT = if shatterAt then shatterAt + 0.6 else maxDelay + rise + linger + sink
	local shattered = false
	if nNeedle > 0 then finishT = math.max(finishT, NEEDLE_LIFE + 0.05) end
	runLoop("crystalgeyser", function(t, dt)
		if #needles > 0 and t <= NEEDLE_LIFE + 0.05 and not (s.freezeAt and t >= s.freezeAt) then
			local parts: { BasePart } = table.create(#needles)
			local cfs: { CFrame } = table.create(#needles)
			local fade = math.clamp((t - (NEEDLE_LIFE - 0.3)) / 0.3, 0, 1)
			for i, nd in needles do
				nd.v += Vector3.new(0, -40 * dt, 0)
				nd.pos += nd.v * dt
				parts[i] = nd.p
				cfs[i] = CFrame.lookAt(nd.pos, nd.pos + nd.v)
				nd.p.Transparency = 0.15 + 0.85 * fade
			end
			workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end
		if shatterAt and t >= shatterAt then
			if not shattered then
				shattered = true
				rigShatter(rig, center + Vector3.new(0, 1.5, 0), 16)
				burstAt(ctx, center + Vector3.new(0, 2, 0), 30, 12, col)
			end
			rigFly(rig, dt, 1 - math.clamp((t - shatterAt) / 0.6, 0, 1))
		else
			rigApply(rig, CFrame.identity, function(rp)
				local x = t - rp.delay
				if x <= 0 then return 0 end
				if x < rise then return easeOutBack(x / rise) end
				if shatterAt then return 1 end
				x -= rise
				if x < linger then return 1 end
				x -= linger
				return math.max(0, 1 - math.min(1, x / sink) ^ 3)
			end, 1)
		end
		return t >= finishT
	end, function()
		for _, rp in rig do rp.p:Destroy() end
		Debris:AddItem(anchor, 1)
		for _, nd in needles do nd.p:Destroy() end
	end)
end

--------------------------------------------------------------------------------
-- 25.10.2026 Weltenende (OmegaWorldsEnd, Omega-Baerchi). Der Baerchi steigt
-- auf, unter ihm waechst ein kleiner Planet; sein Orbit-Ring wird zum
-- Planetenring, seine drei Sterne zu Monden. Er landet auf seiner Welt wie der
-- kleine Prinz, die Monde krachen hinein, Risse gluehen; dann reitet er den
-- Planeten auf den Gegner, der Planet zerbirst und der Ring rast als
-- Bodenwelle davon. Doku in SkillFXConfig ("BAUSTEINE", Weltenende).
--------------------------------------------------------------------------------

local OMEGA_WHITE = Color3.fromRGB(246, 240, 255)
local OMEGA_HOT = Color3.fromRGB(255, 236, 255)
local OMEGA_MOONS = {
	Color3.fromRGB(255, 130, 220), Color3.fromRGB(100, 220, 255), Color3.fromRGB(255, 220, 90),
}

type OmegaInfo = { center: Vector3, normal: Vector3, radius: number, stars: { Vector3 } }
type OmegaRig = {
	set: (number, number, number, boolean) -> (),
	info: () -> OmegaInfo,
}
type World = {
	place: (CFrame, number) -> (),
	crack: (Vector3, number, number) -> (),
	glow: (number) -> (),
	burst: (number, number, number?, number?) -> (),
	destroy: () -> (),
}
type WorldRing = {
	place: (CFrame, number, number) -> (),
	spin: (number) -> (),
	shock: (Vector3, number, number, number?) -> (),
	destroy: () -> (),
}
type WorldMoon = {
	p: BasePart, trail: Trail, a0: number, at: number,
	from: Vector3, hitDir: Vector3, hit: boolean,
}

-- Gleichverteilte Richtung auf der Kugel (eigener Zufall: gleiches Aussehen).
local function randomUnit(rng: Random): Vector3
	local y = rng:NextNumber(-1, 1)
	local a = rng:NextNumber(0, TAU)
	local r = math.sqrt(math.max(0, 1 - y * y))
	return Vector3.new(r * math.cos(a), y, r * math.sin(a))
end

-- Irgendeine Senkrechte zu `v` (Laenge 1).
local function perpOf(v: Vector3): Vector3
	local p = v:Cross(if math.abs(v.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis)
	return if p.Magnitude > 1e-4 then p.Unit else Vector3.xAxis
end

-- Lage einer flachen Scheibe mit der Normale `normal` (lokales Y).
local function planeCf(pos: Vector3, normal: Vector3): CFrame
	return CFrame.fromMatrix(pos, perpOf(normal), normal)
end

-- Fluegel, Orbit-Ring + Sterne und Krone eines Modells (Teile mit "acc_wing",
-- "acc_orbit", "acc_orbitstar", "acc_crown" im Namen, Bezug = Teil
-- "..._body"). set(flap, phase, orbit, glow): `flap` hebt die Fluegelspitzen
-- (Radiant, Drehpunkt am Ruecken), `phase` dreht die Sterne auf ihrem Ring,
-- `orbit` = 0..1 Groesse von Ring und Sternen (0 = weg, die Sterne ziehen
-- sich zur Mitte), `glow` laesst die Krone leuchten (Neon nur als Akzent,
-- F17). Nach jedem PivotTo aufrufen; `scaleOf()` = Groesse relativ zum
-- Start. info() = Weltlage von Ring-Mitte, Ring-Normale, Radius und Sternen.
local function omegaParts(model: Model, scaleOf: () -> number): OmegaRig?
	local body: BasePart? = nil
	local orbit: BasePart? = nil
	local wings: { BasePart } = {}
	local stars: { BasePart } = {}
	local crown: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local n = string.lower(d.Name)
			if string.find(n, "acc_wing", 1, true) then
				table.insert(wings, d)
			elseif string.find(n, "acc_orbitstar", 1, true) then
				table.insert(stars, d)
			elseif string.find(n, "acc_orbit", 1, true) then
				orbit = d
			elseif string.find(n, "acc_crown", 1, true) then
				table.insert(crown, d)
			elseif n == "body" or string.sub(n, -5) == "_body" then
				body = d
			end
		end
	end
	if not body then return nil end
	local bodyP: BasePart = body
	local b0 = bodyP.CFrame
	local rootX = bodyP.Size.X * 0.42
	local wingRel: { CFrame } = {}
	for i, w in wings do
		wingRel[i] = b0:ToObjectSpace(w.CFrame)
	end
	local orbitRel: CFrame? = if orbit then b0:ToObjectSpace(orbit.CFrame) else nil
	local orbitSize = if orbit then orbit.Size else Vector3.one
	local cLocal = if orbitRel then orbitRel.Position else Vector3.zero
	local starRel: { CFrame } = {}
	local starSize: { Vector3 } = {}
	for i, st in stars do
		starRel[i] = b0:ToObjectSpace(st.CFrame)
		starSize[i] = st.Size
	end
	local nLocal = Vector3.new(0, 0, -1)
	if #stars >= 3 then
		local nn = (starRel[2].Position - starRel[1].Position):Cross(starRel[3].Position - starRel[1].Position)
		if nn.Magnitude > 1e-3 then nLocal = nn.Unit end
	end
	local rOrbit = if #stars > 0 then (starRel[1].Position - cLocal).Magnitude else 2
	local crownMat: { Enum.Material } = {}
	for i, p in crown do crownMat[i] = p.Material end
	local lastKey = ""
	local glowing = false
	local function set(flap: number, phase: number, orbitK: number, glow: boolean)
		local sc = scaleOf()
		local bcf = bodyP.CFrame
		for i, w in wings do
			local rel = wingRel[i]
			local side = if rel.X >= 0 then 1 else -1
			local root = Vector3.new(side * rootX, 0.05, rel.Z * 0.9) * sc
			w.CFrame = bcf * CFrame.new(root) * CFrame.Angles(0, 0, side * flap) * CFrame.new(-root)
				* CFrame.new(rel.Position * sc) * rel.Rotation
		end
		local k = math.max(0, orbitK)
		local f = math.max(0.03, k)
		local key = string.format("%.3f|%.3f", sc, k)
		if key ~= lastKey then
			lastKey = key
			local tr = if k < 0.03 then 1 else 0
			if orbit then
				orbit.Size = orbitSize * sc * f
				orbit.Transparency = tr
			end
			for i, st in stars do
				st.Size = starSize[i] * sc * f
				st.Transparency = tr
			end
		end
		if orbit and orbitRel then
			orbit.CFrame = bcf * CFrame.new(cLocal * sc) * orbitRel.Rotation
		end
		local spin = CFrame.fromAxisAngle(nLocal, phase)
		for i, st in stars do
			local off = spin:VectorToWorldSpace(starRel[i].Position - cLocal) * f
			st.CFrame = bcf * CFrame.new((cLocal + off) * sc) * starRel[i].Rotation
		end
		if glow ~= glowing then
			glowing = glow
			for i, p in crown do
				p.Material = if glow then Enum.Material.Neon else crownMat[i]
			end
		end
	end
	local function info(): OmegaInfo
		local sc = scaleOf()
		local bcf = bodyP.CFrame
		local pts: { Vector3 } = {}
		for i, st in stars do pts[i] = st.Position end
		return {
			center = bcf:PointToWorldSpace(cLocal * sc),
			normal = bcf:VectorToWorldSpace(nLocal),
			radius = rOrbit * sc,
			stars = pts,
		}
	end
	return { set = set, info = info }
end

-- Ein kleiner Planet: Ozean-Kugel, flache Kontinente und Polkappen
-- (Ellipsoide), Atmosphaere (Neon 0,87, F05) mit hellem Umriss (Highlight),
-- Leuchtkern. place(cf, sc) setzt alles per BulkMoveTo (sc = Wuchs 0..1);
-- crack(Weltpunkt, Pfade, Stuecke) laesst Risse (Zylinder, F31) vom Punkt aus
-- ueber die Kugel wachsen; glow(0..1) laesst ihn von innen gluehen;
-- burst(Wucht, Brocken, Flugzeit, Test-Halt) zerlegt ihn: Kruste und
-- gluehende Kernbrocken fliegen weg, der Kern blitzt auf und waechst.
local function makeWorld(ctx: Ctx, R: number, seed: number): World
	local col, col2 = ctx.fx.color, ctx.fx.color2
	local ocean = col2:Lerp(col, 0.14)
	local land = col:Lerp(OMEGA_WHITE, 0.12)
	local rng = Random.new(seed)
	local born = os.clock()
	local shell: { BasePart } = {}
	local shellRel: { CFrame } = {}
	local shellSize: { Vector3 } = {}
	local function addShell(p: BasePart, rel: CFrame)
		p.Material = Enum.Material.SmoothPlastic
		table.insert(shell, p)
		table.insert(shellRel, rel)
		table.insert(shellSize, p.Size)
	end
	local crust = newPart(Enum.PartType.Ball, Vector3.one * R * 2, ocean, PARK, 0)
	addShell(crust, CFrame.identity)
	for _ = 1, 9 do
		local dir = randomUnit(rng)
		local p, mesh = ellipsoid(land, Vector3.new(R * rng:NextNumber(0.55, 0.95), R * rng:NextNumber(0.35, 0.65), R * 0.3), PARK, 0)
		mesh.Scale = Vector3.one
		addShell(p, CFrame.lookAt(dir * R * 0.9, dir * R * 2, perpOf(dir)) * CFrame.Angles(0, 0, rng:NextNumber(0, TAU)))
	end
	for _, sgn in { 1, -1 } do
		local p, mesh = ellipsoid(OMEGA_WHITE, Vector3.new(R * 1.05, R * 1.05, R * 0.32), PARK, 0)
		mesh.Scale = Vector3.one
		addShell(p, CFrame.lookAt(Vector3.new(0, sgn * R * 0.9, 0), Vector3.new(0, sgn * R * 2, 0), Vector3.xAxis))
	end
	local atmo = newPart(Enum.PartType.Ball, Vector3.one * R * 2.2, col, PARK, 0.9)
	local core = newPart(Enum.PartType.Ball, Vector3.one * R * 1.6, OMEGA_HOT, PARK, 1)
	local hl = Instance.new("Highlight")
	hl.Adornee = crust
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.FillTransparency = 1
	hl.OutlineColor = OMEGA_WHITE:Lerp(col, 0.3)
	hl.OutlineTransparency = 0.35
	hl.Parent = crust
	local cracks: { RigPart } = {}
	local cur = PARK
	local lastSc = -1
	local lastGlow = -1
	local alive = true

	local function place(cf: CFrame, sc: number)
		if not alive then return end
		cur = cf
		local s = math.max(0.02, sc)
		if math.abs(s - lastSc) > 0.004 then
			lastSc = s
			for i, p in shell do p.Size = shellSize[i] * s end
			atmo.Size = Vector3.one * R * 2.2 * s
			core.Size = Vector3.one * R * 1.6 * s
		end
		local parts: { BasePart } = table.create(#shell + 2)
		local cfs: { CFrame } = table.create(#shell + 2)
		for i, p in shell do
			parts[i] = p
			cfs[i] = cf * CFrame.new(shellRel[i].Position * s) * shellRel[i].Rotation
		end
		table.insert(parts, atmo)
		table.insert(cfs, cf)
		table.insert(parts, core)
		table.insert(cfs, cf)
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		if #cracks > 0 then
			local tl = os.clock() - born
			rigApply(cracks, cf, function(r) return (tl - r.delay) / 0.04 end, 1)
		end
	end

	local function crack(hitWorld: Vector3, paths: number, steps: number)
		if not alive then return end
		local d = cur:PointToObjectSpace(hitWorld)
		local d0 = if d.Magnitude > 1e-3 then d.Unit else Vector3.yAxis
		local t0 = os.clock() - born
		for k = 1, paths do
			local p = d0
			local tangent = CFrame.fromAxisAngle(p, (k / paths) * TAU + rng:NextNumber(-0.35, 0.35)):VectorToWorldSpace(perpOf(p))
			for i = 1, steps do
				tangent = CFrame.fromAxisAngle(p, rng:NextNumber(-0.55, 0.55)):VectorToWorldSpace(tangent)
				local q = (p + tangent * rng:NextNumber(0.2, 0.32)).Unit
				local a, b = p * R * 1.01, q * R * 1.01
				local mid = (a + b) / 2
				local len = (b - a).Magnitude + 0.1
				local w = math.max(0.14, 0.3 - i * 0.022)
				local seg = newPart(Enum.PartType.Cylinder, Vector3.new(len, w, w), OMEGA_HOT, PARK, 1)
				rigPart(cracks, seg, CFrame.lookAt(mid, b, mid.Unit) * CFrame.Angles(0, math.rad(90), 0),
					Vector3.new(len, w, w), t0 + i * 0.03, 0, true)
				local tq = tangent - q * tangent:Dot(q)
				tangent = if tq.Magnitude > 1e-3 then tq.Unit else perpOf(q)
				p = q
			end
		end
	end

	local function glow(k: number)
		if not alive or math.abs(k - lastGlow) < 0.01 then return end
		lastGlow = k
		atmo.Transparency = 0.9 - 0.06 * k
		hl.OutlineTransparency = 0.35 * (1 - k)
	end

	local function burst(power: number, count: number, fly: number?, freeze: number?)
		if not alive then return end
		alive = false
		local center = cur.Position
		for _, p in shell do p:Destroy() end
		for _, r in cracks do r.p:Destroy() end
		table.clear(cracks)
		atmo:Destroy()
		local chunks: { RigPart } = {}
		for i = 1, scaled(count, ctx.factor) do
			local dir = (randomUnit(rng) + Vector3.yAxis * 0.55).Unit
			local hot = i % 3 == 0
			local w = R * (if hot then rng:NextNumber(0.22, 0.38) else rng:NextNumber(0.45, 0.8))
			local size = Vector3.new(w, R * (if hot then 0.2 else 0.26), w * rng:NextNumber(0.6, 1))
			local pos = center + dir * R * (if hot then 0.55 else 0.8)
			local p = newPart(Enum.PartType.Block, size, if hot then OMEGA_HOT elseif i % 2 == 0 then land else ocean,
				CFrame.lookAt(pos, pos + dir, perpOf(dir)) * CFrame.Angles(math.rad(90), 0, 0), 0)
			if not hot then p.Material = Enum.Material.SmoothPlastic end
			table.insert(chunks, { p = p, frame = CFrame.identity, size = size, delay = 0, tr = 0, g = 1, fixed = true, lt = 0 })
		end
		rigShatter(chunks, center, power)
		core.CFrame = CFrame.new(center)
		core.Color = col:Lerp(OMEGA_HOT, 0.55)
		local flyFor = fly or 1.3
		local fadeFor = math.min(0.45, flyFor * 0.5)
		runLoop("worldBurst", function(t, dt)
			if freeze then
				if t >= freeze + 150 then return true end
				if t > freeze then return false end
			end
			local k = math.clamp(t / 0.22, 0, 1)
			core.Size = Vector3.one * R * lerpN(1.6, 3.2, easeOutCubic(k))
			core.Transparency = lerpN(0.25, 1, k)
			rigFly(chunks, dt, if t < flyFor - fadeFor then 1 else math.max(0, (flyFor - t) / fadeFor))
			return t >= flyFor
		end, function()
			core:Destroy()
			for _, r in chunks do r.p:Destroy() end
		end)
	end

	local function destroy()
		if not alive then return end
		alive = false
		for _, p in shell do p:Destroy() end
		for _, r in cracks do r.p:Destroy() end
		atmo:Destroy()
		core:Destroy()
	end

	return { place = place, crack = crack, glow = glow, burst = burst, destroy = destroy }
end

-- Baender des Planetenrings: Radius, Dicke (Anteil am Aussenradius), Transparenz.
local RING_BANDS = {
	{ 0.62, 0.06, 0.4 }, { 0.75, 0.13, 0.05 }, { 0.9, 0.07, 0.12 }, { 0.99, 0.025, 0.3 },
}

-- Planetenring als SurfaceGui auf einer duennen Platte (oben UND unten, F06):
-- vier Baender mit Luecke, Farbverlauf rosa -> cyan -> gelb (UIGradient am
-- Strich). FixedSize: alles waechst mit der Platte. place(cf, Groesse, Alpha);
-- spin(Grad) dreht den Farbverlauf; shock(Bodenpunkt, Radius, Dauer, Test-Halt)
-- legt ihn flach auf den Boden und laesst ihn als Bodenwelle davonrasen.
local function makeRing(ctx: Ctx, rOut: number): WorldRing
	local canvas = rOut * 2.15
	local px = 512
	local plate = newPart(Enum.PartType.Block, Vector3.new(canvas, 0.04, canvas), OMEGA_WHITE, PARK, 1)
	local strokes: { UIStroke } = {}
	local baseTr: { number } = {}
	local baseTh: { number } = {}
	local grads: { UIGradient } = {}
	local seq = ColorSequence.new({
		ColorSequenceKeypoint.new(0, OMEGA_MOONS[1]),
		ColorSequenceKeypoint.new(0.33, OMEGA_MOONS[2]),
		ColorSequenceKeypoint.new(0.66, OMEGA_MOONS[3]),
		ColorSequenceKeypoint.new(1, OMEGA_MOONS[1]),
	})
	for _, face in { Enum.NormalId.Top, Enum.NormalId.Bottom } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		gui.CanvasSize = Vector2.new(px, px)
		gui.LightInfluence = 0
		gui.Brightness = 1.25
		gui.Adornee = plate
		gui.Parent = plate
		for _, b in RING_BANDS do
			local fr = Instance.new("Frame")
			fr.AnchorPoint = Vector2.new(0.5, 0.5)
			fr.Position = UDim2.fromScale(0.5, 0.5)
			local d = b[1] * 2 * rOut / canvas
			fr.Size = UDim2.fromScale(d, d)
			fr.BackgroundTransparency = 1
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0.5, 0)
			corner.Parent = fr
			local st = Instance.new("UIStroke")
			st.Color = Color3.new(1, 1, 1)
			st.Thickness = b[2] * rOut / canvas * px
			st.Transparency = b[3]
			st.Parent = fr
			local g = Instance.new("UIGradient")
			g.Color = seq
			g.Parent = st
			fr.Parent = gui
			table.insert(strokes, st)
			table.insert(baseTr, b[3])
			table.insert(baseTh, st.Thickness)
			table.insert(grads, g)
		end
	end
	local alive = true
	local lastSc = -1
	local lastA = -1
	local function place(cf: CFrame, sc: number, alpha: number)
		if not alive then return end
		local s = math.max(0.02, sc)
		if math.abs(s - lastSc) > 0.004 then
			lastSc = s
			plate.Size = Vector3.new(canvas * s, 0.04, canvas * s)
		end
		if math.abs(alpha - lastA) > 0.01 then
			lastA = alpha
			for i, st in strokes do st.Transparency = 1 - (1 - baseTr[i]) * alpha end
		end
		plate.CFrame = cf
	end
	local function spin(deg: number)
		for _, g in grads do g.Rotation = deg end
	end
	local function shock(groundPos: Vector3, toRadius: number, dur: number, freeze: number?)
		if not alive then return end
		alive = false
		local from = plate.Size.X
		local to = toRadius * canvas / (0.99 * rOut)
		plate.CFrame = CFrame.new(groundPos + Vector3.new(0, 0.15, 0))
		local rot0 = grads[1].Rotation
		runLoop("worldRing", function(t)
			if freeze then
				if t >= freeze + 150 then return true end
				if t > freeze then return false end
			end
			local k = math.clamp(t / dur, 0, 1)
			local e = easeOutCubic(k)
			local size = lerpN(from, to, e)
			plate.Size = Vector3.new(size, 0.04, size)
			for i, st in strokes do
				st.Transparency = 1 - (1 - baseTr[i]) * (1 - k * k)
				st.Thickness = baseTh[i] * lerpN(1.6, 0.5, e)
			end
			for _, g in grads do g.Rotation = rot0 + t * 240 end
			return k >= 1
		end, function()
			plate:Destroy()
		end)
	end
	local function destroy()
		if not alive then return end
		alive = false
		plate:Destroy()
	end
	return { place = place, spin = spin, shock = shock, destroy = destroy }
end

-- worldsend: der Omega-Baerchi SELBST (echter Klon, Original lokal
-- unsichtbar, F03). Duckt sich, Fluegel schlagen, steigt mit Drehung ueber
-- die Arena und waechst. Ab `birthAt` waechst unter ihm ein Planet (Radius
-- `radius`, Mitte `lift` Studs ueber der Arena): sein Orbit-Ring wird zum
-- Planetenring (Aussenradius `ring`, zur Kamera dieses Clients geneigt,
-- F22), seine Sterne fliegen als Monde auf den Ring. Bei `settleAt` steht er
-- auf dem Planeten. Die Monde krachen nacheinander hinein (`crashAt`, je
-- `cracks` Risse aus `steps` Stuecken), der Planet bebt und glueht. Ab
-- `windAt` duckt er sich, bei `hopAt` Sprung mit Vorwaerts-Salto, bei
-- `stompAt` Stampfer: er reitet den Planeten in `fall` s schraeg auf den
-- Gegner (Landung = Einschlag), der Planet zerbirst (`chunks` Brocken), der
-- Ring rast als Bodenwelle bis `shock`. Rueckwaerts-Salto heim (`bounce`),
-- die Sterne kehren zurueck (`settle`). Setzt ctx.avatarCf und
-- ctx.worldCenter/worldNormal/worldRadius (Kamera "worldsEnd").
--   crouch, rise, spins, grow, lift, radius, ring, birthAt, birth, settleAt, crashAt,
--   windAt, hopAt, stompAt, fall, bounce, settle, shock, chunks, power, cracks, steps
--   Test: freezeAt (haelt alles an), burstFreeze (haelt Brocken und Bodenwelle an)
BLOCKS.worldsend = function(ctx, s)
	local source = ctx.selfModel
	if not source or not source.Parent then return end
	local clone = figureClone(source)
	if not clone then return end
	local H = ctx.selfSize.Y
	local home = CFrame.lookAt(ctx.selfFeet, ctx.selfFeet + ctx.fwd)
	local offset = home:ToObjectSpace(clone:GetPivot())
	local okScale, got = pcall(function() return clone:GetScale() end)
	local baseScale: number = if okScale and typeof(got) == "number" then got else 1
	-- Abstand Fusssohle -> Unterkante der Bounding-Box (der Orbit-Ring reicht
	-- tiefer als die Fuesse): so steht er auf dem Planeten, ohne zu schweben.
	local footGap = 0
	do
		local okB, bcf, bsize = pcall(function() return clone:GetBoundingBox() end)
		if okB and typeof(bcf) == "CFrame" and typeof(bsize) == "Vector3" then
			local bottom = (bcf :: CFrame).Position.Y - (bsize :: Vector3).Y / 2
			local lowest = math.huge
			for _, d in clone:GetDescendants() do
				if d:IsA("BasePart") and not string.find(string.lower(d.Name), "acc_orbit", 1, true) then
					lowest = math.min(lowest, d.Position.Y - d.Size.Y / 2)
				end
			end
			if lowest < math.huge then footGap = math.clamp(lowest - bottom, 0, H * 0.3) end
		end
	end
	local crouch = s.crouch or 0.3
	local rise = s.rise or 0.62
	local spins = s.spins or 1
	local grow = s.grow or 1.3
	local lift = s.lift or 11
	local R = s.radius or 3.4
	local rOut = s.ring or R * 2.3
	local birthAt = math.max(crouch + rise, s.birthAt or 0.92)
	local birth = math.max(0.2, s.birth or 0.55)
	local settleAt = math.max(birthAt + birth, s.settleAt or 1.5)
	local crashAt: { number } = s.crashAt or { 1.95, 2.1, 2.25 }
	local windAt = math.max(settleAt, s.windAt or 2.3)
	local hopAt = math.max(windAt, s.hopAt or 2.4)
	local stompAt = math.max(hopAt + 0.08, s.stompAt or 2.62)
	local fall = math.max(0.1, s.fall or 0.27)
	local bounce = math.max(0.3, s.bounce or 0.8)
	local settle = math.max(0.2, s.settle or 0.45)
	local landAt = stompAt + fall
	local homeAt = landAt + bounce
	local total = homeAt + settle
	local freezeAt: number? = s.freezeAt
	local col = ctx.fx.color
	local f = ctx.factor
	local hide = hideFigure(source)

	-- Lage: Planet ueber der Arena (etwas zur eigenen Seite), Einschlag kurz
	-- vor dem Gegner. Ring einmal beim Start zur Kamera dieses Clients
	-- geneigt (F22), damit man ihn offen sieht und nicht als Strich.
	local base = (ctx.selfFeet + ctx.targetFeet) / 2
	local P0 = base - ctx.fwd * 1.2 + Vector3.new(0, lift, 0)
	local P1 = ctx.targetFeet - ctx.fwd * 0.6 + Vector3.new(0, R * 0.62, 0)
	local nCam = sideOf(ctx)
	local cam = workspace.CurrentCamera
	if cam then
		local v = cam.CFrame.Position - base
		v = Vector3.new(v.X, 0, v.Z)
		if v.Magnitude > 1 then nCam = v.Unit end
	end
	local rightCam = Vector3.yAxis:Cross(nCam).Unit
	local ringNormal = (Vector3.yAxis * math.cos(math.rad(26)) + nCam * math.sin(math.rad(26)) + rightCam * 0.18).Unit
	local ringRot = planeCf(Vector3.zero, ringNormal).Rotation
	local e1, e2 = ringRot.RightVector, ringRot.LookVector
	local fallDir = (P1 - P0).Unit
	ctx.worldNormal = nCam
	ctx.worldRadius = R
	ctx.worldCenter = P0

	local hl = Instance.new("Highlight")
	hl.Adornee = clone
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.FillColor = col
	hl.FillTransparency = 0.9
	hl.OutlineColor = col
	hl.OutlineTransparency = 0.05
	hl.Parent = clone

	-- Funken, Lichtfedern (Flug), Staub (EIN Anker an der Koerpermitte)
	local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, home, 1)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARK_TEX
	sparks.Rate = 0
	sparks.Speed = NumberRange.new(4, 11)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Lifetime = NumberRange.new(0.35, 0.8)
	sparks.Drag = 2
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.34), NumberSequenceKeypoint.new(1, 0) })
	sparks.Color = ColorSequence.new(OMEGA_WHITE, col)
	sparks.LightEmission = 0.8
	sparks.Parent = anchor
	local feathers = Instance.new("ParticleEmitter")
	feathers.Texture = SPARK_TEX
	feathers.Rate = 0
	feathers.Speed = NumberRange.new(0.5, 2)
	feathers.SpreadAngle = Vector2.new(180, 180)
	feathers.Lifetime = NumberRange.new(0.5, 1)
	feathers.Drag = 1
	feathers.Acceleration = Vector3.new(0, -3, 0)
	feathers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.38), NumberSequenceKeypoint.new(1, 0) })
	feathers.Color = ColorSequence.new(OMEGA_WHITE, col)
	feathers.LightEmission = 0.6
	feathers.Parent = anchor
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = SMOKE_TEX
	dust.Rate = 0
	dust.Speed = NumberRange.new(3, 8)
	dust.SpreadAngle = Vector2.new(180, 20)
	dust.Lifetime = NumberRange.new(0.5, 0.9)
	dust.Drag = 3
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, H * 0.3), NumberSequenceKeypoint.new(1, H * 0.8) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	dust.Color = ColorSequence.new(OMEGA_WHITE, ctx.fx.color2)
	dust.LightEmission = 0.3
	dust.Rotation = NumberRange.new(0, 360)
	dust.Parent = anchor

	-- Planet, Ring, Feuerhuelle im Sturz (Kraftfeld + Schweif), Monde
	local world = makeWorld(ctx, R, 31)
	local ring = makeRing(ctx, rOut)
	local fire = newPart(Enum.PartType.Ball, Vector3.one * R * 2.35, col, PARK, 1)
	fire.Material = Enum.Material.ForceField
	local fa0 = Instance.new("Attachment")
	fa0.Position = Vector3.new(R * 0.95, 0, 0)
	fa0.Parent = fire
	local fa1 = Instance.new("Attachment")
	fa1.Position = Vector3.new(-R * 0.95, 0, 0)
	fa1.Parent = fire
	local trail = Instance.new("Trail")
	trail.Attachment0 = fa0
	trail.Attachment1 = fa1
	trail.Lifetime = 0.3
	trail.LightEmission = 0.8
	trail.FaceCamera = true
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, OMEGA_HOT),
		ColorSequenceKeypoint.new(0.4, col),
		ColorSequenceKeypoint.new(1, ctx.fx.color2),
	})
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
	trail.Enabled = false
	trail.Parent = fire
	local rMoon = R * 0.19
	local rMoonOrbit = rOut * 0.8
	local moons: { WorldMoon } = {}
	for i = 1, 3 do
		local m = newPart(Enum.PartType.Ball, Vector3.one * 0.3, OMEGA_MOONS[i], PARK, 0.05)
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, rMoon * 0.9, 0)
		a0.Parent = m
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -rMoon * 0.9, 0)
		a1.Parent = m
		local tr = Instance.new("Trail")
		tr.Attachment0 = a0
		tr.Attachment1 = a1
		tr.Lifetime = 0.35
		tr.LightEmission = 0.7
		tr.FaceCamera = true
		tr.Color = ColorSequence.new(OMEGA_MOONS[i])
		tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		tr.Enabled = false
		tr.Parent = m
		table.insert(moons, { p = m, trail = tr, a0 = 0.5 + (i - 1) * TAU / 3, at = crashAt[i] or (2 + i * 0.15),
			from = Vector3.zero, hitDir = Vector3.zero, hit = false })
	end

	local function onRing(c: Vector3, a: number, r: number): Vector3
		return c + (e1 * math.cos(a) + e2 * math.sin(a)) * r
	end
	local function worldScale(t: number): number
		if t < birthAt then return 0 end
		return easeOutBack(math.clamp((t - birthAt) / birth, 0, 1))
	end
	-- Planetenmitte: schwebt und wippt, bebt nach jedem Mond, faellt beschleunigt
	local function centerAt(t: number): Vector3
		if t >= stompAt then
			local k = math.clamp((t - stompAt) / fall, 0, 1)
			return P0:Lerp(P1, k * k)
		end
		local c = P0 + Vector3.new(0, math.sin(math.max(0, t - birthAt) * 2.2) * 0.18, 0)
		for _, m in moons do
			if m.hit and t >= m.at then
				local d = t - m.at
				c += m.hitDir * 0.6 * math.exp(-d * 9) * math.cos(d * 28)
			end
		end
		return c
	end
	local function spinAt(t: number): number
		local a = 0.55 * math.max(0, t - birthAt)
		for _, m in moons do
			if m.hit and t >= m.at then a += 0.9 * (1 - math.exp(-(t - m.at) * 6)) end
		end
		if t > stompAt then a += 3 * (t - stompAt) ^ 2 end
		return a
	end
	local function topAt(t: number, sc: number): Vector3
		return centerAt(t) + Vector3.new(0, R * worldScale(t) - footGap * sc, 0)
	end

	local lastScale = 1
	local omega = omegaParts(clone, function() return lastScale end)
	-- Pose: Fuesse `feet`, gedreht um die Koerpermitte (wie `ascend`)
	local function place(feet: CFrame, pitch: number, yaw: number, roll: number, sc: number)
		if math.abs(sc - lastScale) > 0.008 then
			lastScale = sc
			pcall(function() clone:ScaleTo(baseScale * sc) end)
		end
		local half = H * sc * 0.5
		local pose = feet * CFrame.new(0, half, 0) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll) * CFrame.new(0, -half, 0)
		ctx.avatarCf = pose
		ctx.avatarScale = sc
		clone:PivotTo(pose * CFrame.new(offset.Position * sc) * offset.Rotation)
		anchor.CFrame = pose * CFrame.new(0, half, 0)
	end
	local function face(pos: Vector3): CFrame
		return CFrame.lookAt(pos, pos + ctx.fwd)
	end
	place(home, 0, 0, 0, 1)
	clone.Parent = folder()
	hide(1)

	local hoverFeet = P0 + Vector3.new(0, R + 1.4, 0)
	local flyRate = (if extrasOn(ctx) then 34 else 14) * f
	local paths = math.max(2, math.min(4, scaled(s.cracks or 3, f)))
	local steps = s.steps or 7
	local ringFrom: CFrame? = nil
	local ringFromSc = 0.3
	local bounceFrom = P1 + Vector3.new(0, R, 0)
	local risen, born, settled, stomped, landed, homed = false, false, false, false, false, false
	local tPrev, flapPh, starPh = 0, 0, 0
	runLoop("worldsend", function(tRaw)
		if not clone.Parent then return true end
		if tRaw >= (if freezeAt then freezeAt + 150 else total) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		local dtt = math.max(0, t - tPrev)
		tPrev = t
		local flapBase, flapAmp, flapFreq, starSpeed = 0.1, 0.3, 10, 4
		local orbitK = 1
		feathers.Rate = 0

		-- Planet, Ring und Monde (ab birthAt bis zum Einschlag)
		if t >= birthAt and not landed then
			if not born then
				born = true
				local inf = if omega then omega.info() else nil
				local c0 = if inf then inf.center else (ctx.avatarCf or home).Position + Vector3.new(0, H * grow * 0.5, 0)
				local n0 = if inf then inf.normal else ctx.fwd
				ringFrom = planeCf(c0, n0)
				ringFromSc = (if inf then inf.radius else 2) / (rOut * 0.99)
				for i, m in moons do
					m.from = if inf and inf.stars[i] then inf.stars[i] else c0
					m.trail.Enabled = true
				end
				sparks:Emit(scaled(20, f))
			end
			local c = centerAt(t)
			ctx.worldCenter = c
			world.place(CFrame.new(c) * ringRot * CFrame.Angles(0, spinAt(t), 0), worldScale(t))
			local hits = 0
			for _, m in moons do
				if m.hit then hits += 1 end
			end
			world.glow(math.clamp(hits / 3 + (if t > windAt then (t - windAt) * 2 else 0), 0, 1))
			-- Ring: vom eigenen Orbit-Ring zum Planetenring, im Sturz zieht er nach
			local kb = math.clamp((t - birthAt) / birth, 0, 1)
			local eb = easeInOutSine(kb)
			local ringCf = CFrame.new(c) * ringRot
			if t >= stompAt then
				local kf = math.clamp((t - stompAt) / fall, 0, 1)
				ringCf = CFrame.new(c + Vector3.new(0, R * 0.55 * kf, 0)) * ringRot
			end
			if ringFrom and kb < 1 then
				ring.place((ringFrom :: CFrame):Lerp(ringCf, eb), lerpN(ringFromSc, 1, eb), math.min(1, kb * 4))
			else
				ring.place(ringCf, 1, 1)
			end
			ring.spin((t * 90) % 360)
			-- Monde: fliegen vom Orbit des Baerchis auf den Ring, kreisen,
			-- stuerzen nacheinander in einer engen Spirale in den Planeten
			for i, m in moons do
				if not m.hit then
					local a = m.a0 + 2.6 * (t - birthAt)
					local km = math.clamp((t - birthAt) / 0.45, 0, 1)
					local pos: Vector3
					if t < m.at - 0.16 then
						pos = m.from:Lerp(onRing(c, a, rMoonOrbit), easeInOutSine(km))
							+ Vector3.new(0, math.sin(math.pi * km) * 1.2, 0)
					else
						local kc = math.clamp((t - (m.at - 0.16)) / 0.16, 0, 1)
						pos = onRing(c, a + 2.2 * kc * kc, lerpN(rMoonOrbit, R * 1.02, kc * kc))
					end
					m.p.Size = Vector3.one * lerpN(0.3, rMoon * 2, math.min(1, km * 1.5))
					m.p.CFrame = CFrame.new(pos)
					if t >= m.at then
						m.hit = true
						m.hitDir = (c - pos).Unit
						world.crack(pos, paths, steps)
						burstAt(ctx, pos, 24, 12, OMEGA_MOONS[i])
						m.trail.Enabled = false
						m.p.Transparency = 1
						m.p.CFrame = PARK
					end
				end
			end
		end

		-- Der Baerchi
		if t < crouch then
			-- 1. ausholen: zuruecklehnen, kleiner werden, Fluegel zittern
			local e = math.sin((t / crouch) * math.pi * 0.5)
			place(home, 0.28 * e, 0, 0, 1 - 0.08 * e)
			flapBase, flapAmp, flapFreq, starSpeed = 0.25, 0.2, 34, 8
		elseif t < crouch + rise then
			-- 2. aufsteigen mit Drehung ueber die Arena, wachsen, Fluegelschlag
			local k = (t - crouch) / rise
			local e = easeOutCubic(k)
			if not risen then
				risen = true
				sparks:Emit(scaled(26, f))
				dust:Emit(scaled(14, f))
			end
			local pos = home.Position:Lerp(hoverFeet, e) + Vector3.new(0, math.sin(math.pi * k) * 2.5, 0)
			place(face(pos), 0.28 * (1 - e), spins * TAU * e, 0, lerpN(0.92, grow, e))
			flapBase, flapAmp, flapFreq, starSpeed = 0.1, 0.6, 24, 10
			feathers.Rate = flyRate
		elseif t < settleAt then
			-- 3. schwebt ueber dem werdenden Planeten, Brust heraus; sein Ring
			--    und seine Sterne gehen auf den Planeten ueber; zuletzt sinkt er
			--    auf die Oberflaeche
			local h = t - crouch - rise
			local pos = hoverFeet + Vector3.new(0, math.sin(h * 5) * 0.2, 0)
			local kd = math.clamp((t - (settleAt - 0.18)) / 0.18, 0, 1)
			if kd > 0 then pos = pos:Lerp(topAt(t, grow), easeInOutSine(kd)) end
			place(face(pos), 0.22 * math.min(1, h / 0.25), 0, 0, grow)
			flapBase, flapAmp, flapFreq, starSpeed = 0.1, 0.45, 11, 10
			orbitK = 1 - math.clamp((t - birthAt) / 0.18, 0, 1)
			feathers.Rate = flyRate * 0.4
		elseif t < windAt then
			-- 4. steht auf seiner Welt (kleiner Prinz), federt ab, triumphiert
			if not settled then
				settled = true
				dust:Emit(scaled(10, f))
				sparks:Emit(scaled(14, f))
			end
			local k = t - settleAt
			local squash = math.exp(-k * 9) * math.sin(k * 30) * 0.06
			place(face(topAt(t, grow)), 0.16 + 0.05 * math.sin(k * 4), 0, 0, grow * (1 - squash))
			flapBase, flapAmp, flapFreq = 0.3, 0.3, 7
			orbitK = 0
		elseif t < hopAt then
			-- 5. holt aus: tief geduckt, Fluegel hoch, bebt
			local k = (t - windAt) / math.max(0.01, hopAt - windAt)
			local e = easeOutCubic(k)
			place(face(topAt(t, grow)), lerpN(0.16, -0.42, e), 0, 0, grow * lerpN(1, 0.94, e))
			flapBase, flapAmp, flapFreq = lerpN(0.3, 0.8, e), 0.06, 30
			orbitK = 0
		elseif t < stompAt then
			-- 6. Sprung mit Vorwaerts-Salto
			local k = (t - hopAt) / (stompAt - hopAt)
			local pos = topAt(t, grow) + Vector3.new(0, math.sin(math.pi * k) * 2.6, 0)
			place(face(pos), -0.42 - TAU * easeInOutSine(k), 0, 0, grow)
			flapBase, flapAmp, flapFreq = lerpN(0.8, -0.4, k), 0, 0
			orbitK = 0
		elseif t < landAt then
			-- 7. Stampfer: reitet den stuerzenden Planeten, tief geduckt
			if not stomped then
				stomped = true
				sparks:Emit(scaled(30, f))
				trail.Enabled = true
				fire.Transparency = 0.6
			end
			local c = centerAt(t)
			fire.CFrame = CFrame.lookAt(c, c + fallDir, nCam)
			place(face(topAt(t, grow)), -0.32, 0, 0, grow * 0.97)
			flapBase, flapAmp, flapFreq = -0.45, 0.06, 30
			orbitK = 0
		elseif t < homeAt then
			-- 8. Einschlag: der Planet zerbirst, er federt mit Rueckwaerts-Salto heim
			if not landed then
				landed = true
				ctx.worldCenter = P1
				world.burst(s.power or 30, s.chunks or 22, nil, s.burstFreeze)
				ring.shock(ctx.targetFeet, s.shock or 16, 0.75, s.burstFreeze)
				burstAt(ctx, P1, 44, 26, col)
				trail.Enabled = false
				fire.Transparency = 1
				sparks:Emit(scaled(36, f))
				bounceFrom = topAt(landAt, grow)
			end
			local k = (t - landAt) / bounce
			local e = easeInOutSine(k)
			local pos = bounceFrom:Lerp(home.Position, e) + Vector3.new(0, math.sin(math.pi * k) * 5, 0)
			place(face(pos), TAU * e, 0, 0, lerpN(grow, 1, e))
			flapBase, flapAmp, flapFreq = 0.1, 0.6, 26
			orbitK = 0
			feathers.Rate = flyRate
		else
			-- 9. Landung zu Hause, die Sterne kehren zurueck
			if not homed then
				homed = true
				dust:Emit(scaled(18, f))
				sparks:Emit(scaled(16, f))
			end
			local k = (t - homeAt) / settle
			place(home, lerpN(-0.3, 0, easeOutCubic(math.min(1, k * 2))), 0, 0, 1)
			flapBase, flapAmp, flapFreq, starSpeed = 0, 0.2 * (1 - k), 14, 6
			orbitK = easeOutBack(math.min(1, k / 0.6))
		end

		flapPh += flapFreq * dtt
		starPh += starSpeed * dtt
		if omega then
			omega.set(flapBase + flapAmp * math.sin(flapPh), starPh, orbitK, t < landAt + 0.3)
		end
		return false
	end, function()
		hide(0)
		ctx.avatarCf = nil
		ctx.avatarScale = nil
		ctx.worldCenter = nil
		ctx.worldNormal = nil
		ctx.worldRadius = nil
		clone:Destroy()
		world.destroy()
		ring.destroy()
		fire:Destroy()
		for _, m in moons do m.p:Destroy() end
		feathers.Rate = 0
		Debris:AddItem(anchor, 1.2)
	end)
end

-- miniworld: ein kleiner Planet mit Ring erscheint `height` Studs ueber dem
-- Gegner, faellt beschleunigt und zerbirst nach `drop` s (= Einschlag des
-- Echos); der Ring rast als Bodenwelle bis `shock`.
--   at, radius, height, drop, shock, chunks, power (Test: freezeAt, burstFreeze)
BLOCKS.miniworld = function(ctx, s)
	local R = s.radius or 1.2
	local feet = groundAt(ctx, s.at or "target")
	local drop = math.max(0.08, s.drop or 0.26)
	local h = s.height or 7
	local freezeAt: number? = s.freezeAt
	local w = makeWorld(ctx, R, 11)
	local ring = makeRing(ctx, R * 2.3)
	-- Ring zur Kamera dieses Clients geneigt (offen statt hochkant, F22)
	local nCam = sideOf(ctx)
	local cam = workspace.CurrentCamera
	if cam then
		local v = cam.CFrame.Position - feet
		v = Vector3.new(v.X, 0, v.Z)
		if v.Magnitude > 1 then nCam = v.Unit end
	end
	local tilt = planeCf(Vector3.zero, (Vector3.yAxis * math.cos(math.rad(30)) + nCam * math.sin(math.rad(30))).Unit).Rotation
	local from = feet + Vector3.new(0, h, 0) - ctx.fwd * 1.5
	local to = feet - ctx.fwd * 0.3 + Vector3.new(0, R * 0.6, 0)
	local done = false
	runLoop("miniworld", function(tRaw)
		if freezeAt and tRaw >= freezeAt + 150 then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		if t < drop then
			local k = t / drop
			local c = from:Lerp(to, k * k)
			local pop = math.min(1, t / 0.07)
			w.place(CFrame.new(c) * tilt * CFrame.Angles(0, t * 8, 0), pop)
			w.glow(k)
			ring.place(CFrame.new(c) * tilt, pop, 1)
			ring.spin((t * 300) % 360)
			return false
		end
		done = true
		w.burst(s.power or 16, s.chunks or 8, 0.38, s.burstFreeze)
		ring.shock(feet, s.shock or 7, 0.35, s.burstFreeze)
		burstAt(ctx, to, 22, 14, ctx.fx.color)
		return true
	end, function()
		if not done then
			w.destroy()
			ring.destroy()
		end
	end)
end

-- supernova: Finisher-Bonus. Aus dem Einschlag waechst eine riesige
-- Lichtkugel (Kraftfeld + Neon-Huelle 0,84, F05/F17) bis `radius`, duenne
-- Lichtstrahlen schiessen schraeg nach oben, Funken in den Mondfarben; alles
-- verblasst in `dur`.
--   at, radius, dur, rays (Test: freezeAt)
BLOCKS.supernova = function(ctx, s)
	local c = groundAt(ctx, s.at or "target") + Vector3.new(0, 1.2, 0)
	local R = radiusOf(s.radius, 14)
	local dur = s.dur or 1.0
	local freezeAt: number? = s.freezeAt
	local rng = Random.new()
	local shell = newPart(Enum.PartType.Ball, Vector3.one * 2, OMEGA_HOT, CFrame.new(c), 0.15)
	shell.Material = Enum.Material.ForceField
	local hull = newPart(Enum.PartType.Ball, Vector3.one * 2, ctx.fx.color:Lerp(OMEGA_WHITE, 0.3), CFrame.new(c), 0.84)
	local rays: { { p: BasePart, dir: Vector3, len: number, w: number } } = {}
	for i = 1, scaled(s.rays or 12, ctx.factor) do
		local dir = (randomUnit(rng) + Vector3.yAxis * 0.7).Unit
		local w = rng:NextNumber(0.3, 0.55)
		local rc = if i % 4 == 0 then OMEGA_MOONS[(i // 4 - 1) % 3 + 1] else OMEGA_HOT
		table.insert(rays, { p = newPart(Enum.PartType.Block, Vector3.new(w, w, 0.2), rc, CFrame.new(c), 0.1), dir = dir,
			len = R * rng:NextNumber(0.9, 1.5), w = w })
	end
	for i, mc in OMEGA_MOONS do
		burstAt(ctx, c + Vector3.new(0, i * 0.5, 0), 24, 30, mc)
	end
	runLoop("supernova", function(tRaw)
		if freezeAt and tRaw >= freezeAt + 150 then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		local k = math.clamp(t / dur, 0, 1)
		local e = math.max(0.05, easeOutCubic(math.min(1, t / (dur * 0.55))))
		shell.Size = Vector3.one * 2 * R * e
		shell.Transparency = lerpN(0.15, 1, k)
		hull.Size = Vector3.one * 2 * R * 1.04 * e
		hull.Transparency = lerpN(0.84, 1, k)
		local reach = easeOutCubic(math.min(1, t / (dur * 0.4)))
		local parts: { BasePart } = table.create(#rays)
		local cfs: { CFrame } = table.create(#rays)
		for i, r in rays do
			local len = math.max(0.2, r.len * reach)
			local wd = r.w * (1 - k * 0.7)
			r.p.Size = Vector3.new(wd, wd, len)
			r.p.Transparency = lerpN(0.1, 1, k)
			parts[i] = r.p
			cfs[i] = CFrame.lookAt(c + r.dir * len * 0.5, c + r.dir * len, perpOf(r.dir))
		end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		return freezeAt == nil and t >= dur
	end, function()
		shell:Destroy()
		hull:Destroy()
		for _, r in rays do r.p:Destroy() end
	end)
end


type GlobeCircle = {
	c: Vector3, u: Vector3, v: Vector3, k: number, w: number, tr: number,
	atts: { Attachment }, beams: { Beam },
}

-- worldglobe: die Explosion als Weltkugel aus Licht. Aus dem Einschlag
-- (ctx.worldCenter, sonst ueber dem Gegner) waechst in `grow` s eine riesige
-- Kugel (`radius`, "fence" = das ganze Fight-Pit) zur Arena-Mitte, Mitte
-- `lift` x Radius ueber dem Boden; Achse um `tilt` Grad zur Kamera dieses
-- Clients geneigt (F22). Laengengrade (`meridians`) und Breitengrade
-- (`parallels`) sind Beams aus Bezier-Vierteln (FaceCamera: auch von innen
-- sichtbar, ein normales Ball-Teil waere es nicht), Kontinente (die des
-- Planeten, gleicher Zufall) und Polkappen halbtransparente Ellipsoide, dazu
-- eine Kraftfeld-Huelle. Alle Attachments haengen an EINEM Anker: Drehen =
-- ein CFrame. Dreht sich beim Aufgehen schnell (`spin`) und wird langsamer;
-- ab `dur` - 0,6 s zerfaellt sie in Sternenstaub. Setzt ctx.globeT0/
-- globeCenter/globeRadius (Kamera "worldsEnd" faehrt zurueck).
--   at, radius, grow, dur, lift, tilt, spin, meridians, parallels (Test: freezeAt)
BLOCKS.worldglobe = function(ctx, s)
	local Rg = radiusOf(s.radius, 22)
	local grow = math.max(0.1, s.grow or 0.6)
	local dur = math.max(grow + 0.4, s.dur or 1.6)
	local fadeAt = dur - 0.6
	local freezeAt: number? = s.freezeAt
	local col = ctx.fx.color
	local f = ctx.factor
	local base = (ctx.selfFeet + ctx.targetFeet) / 2
	local from = ctx.worldCenter or (groundAt(ctx, s.at or "target") + Vector3.new(0, 2, 0))
	local r0 = math.max(1, ctx.worldRadius or 3.4)
	local to = base + Vector3.new(0, Rg * (s.lift or 0.3), 0)
	local nCam = ctx.worldNormal or sideOf(ctx)
	if not ctx.worldNormal then
		local cam = workspace.CurrentCamera
		if cam then
			local v = cam.CFrame.Position - base
			v = Vector3.new(v.X, 0, v.Z)
			if v.Magnitude > 1 then nCam = v.Unit end
		end
	end
	local tilt = math.rad(s.tilt or 23.4)
	local axisRot = planeCf(Vector3.zero, (Vector3.yAxis * math.cos(tilt) + nCam * math.sin(tilt)).Unit).Rotation
	local spin0 = s.spin or 3
	local rich = extrasOn(ctx)
	local nMer = if rich then math.max(4, s.meridians or 12) else 8
	local nPar = if rich then math.max(1, s.parallels or 5) else 3

	-- EIN Anker traegt alle Attachments (lokal Y = Achse)
	local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, CFrame.new(from) * axisRot, 1)
	local circles: { GlobeCircle } = {}
	local function addCircle(c: Vector3, u: Vector3, v: Vector3, k: number, color: Color3, w: number, tr: number, emission: number)
		local ci: GlobeCircle = { c = c, u = u, v = v, k = k, w = w, tr = tr, atts = {}, beams = {} }
		for i = 1, 4 do
			local a = Instance.new("Attachment")
			a.Parent = anchor
			ci.atts[i] = a
		end
		for i = 1, 4 do
			local b = Instance.new("Beam")
			b.Attachment0 = ci.atts[i]
			b.Attachment1 = ci.atts[i % 4 + 1]
			b.FaceCamera = true
			b.Segments = 14
			b.LightEmission = emission
			b.LightInfluence = 0
			b.Color = ColorSequence.new(color)
			b.Transparency = NumberSequence.new(1)
			b.Parent = anchor
			ci.beams[i] = b
		end
		table.insert(circles, ci)
	end
	-- Laengengrade: Grosskreise durch die Pole
	local meridCol = col:Lerp(OMEGA_WHITE, 0.3)
	for j = 0, nMer // 2 - 1 do
		local phi = j * math.pi / (nMer // 2)
		addCircle(Vector3.zero, Vector3.new(math.cos(phi), 0, math.sin(phi)), Vector3.yAxis, 1, meridCol, 0.018, 0.15, 0.4)
	end
	-- Breitengrade: Aequator gleissend, die anderen in den Mondfarben
	local lats: { { number } } = if nPar >= 5
		then { { 0, 0 }, { 30, 1 }, { -30, 2 }, { 60, 3 }, { -60, 4 } }
		else { { 0, 0 }, { 40, 1 }, { -40, 2 } }
	for _, la in lats do
		local beta = math.rad(la[1])
		local color = if la[2] == 0 then OMEGA_HOT elseif la[2] == 4 then col else OMEGA_MOONS[la[2]]
		addCircle(Vector3.new(0, math.sin(beta), 0), Vector3.xAxis, Vector3.zAxis, math.cos(beta), color,
			if la[2] == 0 then 0.034 else 0.027, if la[2] == 0 then 0.05 else 0.08, if la[2] == 0 then 0.6 else 0.3)
	end
	-- Kontinente des Planeten (gleicher Zufall wie makeWorld, Saat 31) und Polkappen
	local conts: { BasePart } = {}
	local contRel: { CFrame } = {}
	local contSize: { Vector3 } = {}
	local contTr: { number } = {}
	local rng = Random.new(31)
	local landCol = col:Lerp(OMEGA_WHITE, 0.2)
	for _ = 1, 9 do
		local dir = randomUnit(rng)
		local wq = rng:NextNumber(0.55, 0.95)
		local hq = rng:NextNumber(0.35, 0.65)
		local roll = rng:NextNumber(0, TAU)
		local p, mesh = ellipsoid(landCol, Vector3.one, PARK, 1)
		mesh.Scale = Vector3.one
		p.Material = Enum.Material.SmoothPlastic
		table.insert(conts, p)
		table.insert(contRel, CFrame.lookAt(dir * 0.99, dir * 2, perpOf(dir)) * CFrame.Angles(0, 0, roll))
		table.insert(contSize, Vector3.new(wq, hq, 0.04))
		table.insert(contTr, 0.5)
	end
	for _, sgn in { 1, -1 } do
		local p, mesh = ellipsoid(OMEGA_WHITE, Vector3.one, PARK, 1)
		mesh.Scale = Vector3.one
		p.Material = Enum.Material.SmoothPlastic
		table.insert(conts, p)
		table.insert(contRel, CFrame.lookAt(Vector3.new(0, sgn * 0.99, 0), Vector3.new(0, sgn * 2, 0), Vector3.xAxis))
		table.insert(contSize, Vector3.new(0.55, 0.55, 0.04))
		table.insert(contTr, 0.5)
	end
	-- Kraftfeld-Huelle mit Sternenstaub (EIN Emitter auf der Oberflaeche)
	local shell = newPart(Enum.PartType.Ball, Vector3.one * r0 * 2, OMEGA_WHITE:Lerp(col, 0.4), CFrame.new(from), 1)
	shell.Material = Enum.Material.ForceField
	local stardust = Instance.new("ParticleEmitter")
	stardust.Texture = SPARK_TEX
	stardust.Rate = 0
	stardust.Shape = Enum.ParticleEmitterShape.Sphere
	stardust.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	stardust.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	stardust.Speed = NumberRange.new(1, 4)
	stardust.Lifetime = NumberRange.new(0.6, 1.1)
	stardust.Acceleration = Vector3.new(0, -5, 0)
	stardust.Drag = 1
	stardust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.1), NumberSequenceKeypoint.new(1, 0) })
	stardust.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, OMEGA_MOONS[1]),
		ColorSequenceKeypoint.new(0.5, OMEGA_MOONS[2]),
		ColorSequenceKeypoint.new(1, OMEGA_WHITE),
	})
	stardust.LightEmission = 0.6
	stardust.Parent = shell

	ctx.globeT0 = os.clock()
	ctx.globeCenter = to
	ctx.globeRadius = Rg
	local lastR, lastA = -1, -1
	local dusted = false
	runLoop("worldglobe", function(tRaw)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		local eg = easeOutCubic(math.clamp(t / grow, 0, 1))
		local r = lerpN(r0, Rg, eg)
		local center = from:Lerp(to, eg)
		local ang = 0.45 * t + spin0 * (1 - math.exp(-3 * t))
		local acf = CFrame.new(center) * axisRot * CFrame.Angles(0, ang, 0)
		anchor.CFrame = acf
		if math.abs(r - lastR) > 0.01 then
			lastR = r
			for _, ci in circles do
				local rr = ci.k * r
				for i, a in ci.atts do
					local th = (i - 1) * math.pi / 2
					local dir = ci.u * math.cos(th) + ci.v * math.sin(th)
					local tan = -ci.u * math.sin(th) + ci.v * math.cos(th)
					a.CFrame = CFrame.fromMatrix(ci.c * r + dir * rr, tan, dir)
				end
				local cs = 0.5523 * rr
				local w = math.max(0.18, ci.w * r)
				for _, b in ci.beams do
					b.CurveSize0 = cs
					b.CurveSize1 = cs
					b.Width0 = w
					b.Width1 = w
				end
			end
			shell.Size = Vector3.one * r * 2
			for i, p in conts do p.Size = contSize[i] * r end
		end
		local parts: { BasePart } = table.create(#conts + 1)
		local cfs: { CFrame } = table.create(#conts + 1)
		for i, p in conts do
			local rel = contRel[i]
			parts[i] = p
			cfs[i] = acf * CFrame.new(rel.Position * r) * rel.Rotation
		end
		table.insert(parts, shell)
		table.insert(cfs, CFrame.new(center))
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		-- erscheinen, Sternenstaub, verblassen
		local alpha = math.min(1, t / 0.1)
		if t > fadeAt then
			alpha = math.max(0, 1 - (t - fadeAt) / (dur - fadeAt))
			if not dusted then
				dusted = true
				stardust:Emit(scaled(220, f))
			end
		end
		if math.abs(alpha - lastA) > 0.01 then
			lastA = alpha
			for _, ci in circles do
				local seq = NumberSequence.new(1 - (1 - ci.tr) * alpha)
				for _, b in ci.beams do b.Transparency = seq end
			end
		end
		-- Kontinente unter der Bodenlinie ausblenden (sonst liegen sie als Fleck am Boden)
		for i, p in conts do
			local hk = math.clamp((cfs[i].Y - (base.Y + 1)) / 3, 0, 1)
			local v = 1 - (1 - contTr[i]) * alpha * hk
			if math.abs(p.Transparency - v) > 0.01 then p.Transparency = v end
		end
		shell.Transparency = 1 - (1 - lerpN(0.15, 0.55, eg)) * alpha
		return false
	end, function()
		ctx.globeT0 = nil
		ctx.globeCenter = nil
		ctx.globeRadius = nil
		anchor:Destroy()
		for _, p in conts do p:Destroy() end
		Debris:AddItem(shell, 1.2)
		shell.Transparency = 1
	end)
end


--------------------------------------------------------------------------------
-- 25.10. Fragenlawine (RiddleAvalanche). Der Raetsel-Baerchi lueftet den Hut,
-- ein goldenes Fragezeichen springt heraus, waechst ueber dem Gegner und teilt
-- sich immer weiter (1 -> 2 -> 4 -> 8) zu einem Wirbel; "Aha!": alle biegen
-- sich zu Ausrufezeichen und rammen sich als Kaefig in den Boden, der Baerchi
-- stuerzt als Punkt eines riesigen "!" herab - danach wird jede Antwort
-- wieder eine Frage. Doku in SkillFXConfig ("BAUSTEINE", Fragenlawine).
--------------------------------------------------------------------------------

local RIDDLE_INK = Color3.fromRGB(46, 22, 78)      -- Umriss der Zeichen (F37)
local RIDDLE_HOT = Color3.fromRGB(255, 250, 228)   -- Aufblitzen
local GLYPH_N = 14                                  -- Zylinder-Stuecke je Zeichen
local GLYPH_DOT_Y = -0.24                           -- Punkt-Mitte unter dem Stielende (Strich-Einheiten)
local GLYPH_MID = 0.31                              -- Bildmitte ueber dem Stielende
local GLYPH_FOOT = 0.62                             -- Bildmitte ueber dem Boden, wenn der Punkt steckt
local ROT90 = CFrame.Angles(0, math.rad(90), 0)

type Glyph = {
	model: Model,
	parts: { BasePart },   -- GLYPH_N Stuecke, 2 Kappen, Punkt (BulkMoveTo-Reihenfolge)
	hl: Highlight,
	sizes: { Vector3 },
	alpha: number,
	glow: number,
	dotOn: boolean,
}
type RiddleHat = {
	set: (CFrame, number, number, number) -> (),
	top: () -> Vector3,
	glint: () -> Vector3?,
}
type ConfettiBit = { a: BasePart, tl: TextLabel, p: Vector3, v: Vector3, r0: number, spin: number }
type RiddleMark = { g: Glyph, i: number, vis: number, rank: number, theta: number, hit: boolean,
	popped: boolean, phase: number }

-- Punkte gleichmaessig nach Bogenlaenge verteilen.
local function resamplePath(raw: { Vector2 }, n: number): { Vector2 }
	local acc: { number } = { 0 }
	for i = 2, #raw do
		acc[i] = acc[i - 1] + (raw[i] - raw[i - 1]).Magnitude
	end
	local total = acc[#raw]
	local res: { Vector2 } = table.create(n)
	local j = 1
	for k = 0, n - 1 do
		local d = total * k / (n - 1)
		while j < #raw - 1 and acc[j + 1] < d do
			j += 1
		end
		local seg = acc[j + 1] - acc[j]
		local u = if seg > 1e-6 then math.clamp((d - acc[j]) / seg, 0, 1) else 0
		res[k + 1] = raw[j]:Lerp(raw[j + 1], u)
	end
	return res
end

-- Das "?" in Strich-Einheiten (Stielende = 0,0; Hakenoberkante ~0,97):
-- Bogen um (0, 0,68) mit Radius 0,29 im Uhrzeigersinn von links (198 Grad)
-- bis rechts unten (-40 Grad), Bezier-Uebergang zum Stiel, Stiel bis 0.
-- Das "!" ist der senkrechte Strich von 1 bis 0 - beide mit GLYPH_N + 1
-- Punkten, so biegt sich das eine stufenlos ins andere.
local QUESTION_PTS: { Vector2 } = (function(): { Vector2 }
	local raw: { Vector2 } = {}
	local cy, r = 0.68, 0.29
	local a0, a1 = math.rad(198), math.rad(-40)
	for i = 0, 40 do
		local a = a0 + (a1 - a0) * i / 40
		table.insert(raw, Vector2.new(r * math.cos(a), cy + r * math.sin(a)))
	end
	local pa = raw[#raw]
	local ta = Vector2.new(math.sin(a1), -math.cos(a1))
	local s0 = Vector2.new(0, 0.26)
	local c1 = pa + ta * 0.12
	local c2 = s0 + Vector2.new(0, 0.1)
	for i = 1, 12 do
		local u = i / 12
		local w = 1 - u
		table.insert(raw, pa * (w * w * w) + c1 * (3 * w * w * u) + c2 * (3 * w * u * u) + s0 * (u * u * u))
	end
	for i = 1, 6 do
		table.insert(raw, Vector2.new(0, 0.26 * (1 - i / 6)))
	end
	return resamplePath(raw, GLYPH_N + 1)
end)()

-- Waagerechte Richtung von `pos` zur Kamera DIESES Clients (flache Motive
-- jedes Bild neu zur Kamera drehen, F04).
local function camFace(pos: Vector3, fallback: Vector3): Vector3
	local cam = workspace.CurrentCamera
	if cam then
		local v = cam.CFrame.Position - pos
		v = Vector3.new(v.X, 0, v.Z)
		if v.Magnitude > 0.5 then
			return v.Unit
		end
	end
	return fallback
end

-- Ein Zeichen aus Gold-Zylindern (SmoothPlastic, kein Neon: F17) mit dunklem
-- Umriss (EIN Highlight je Zeichen, F37). Teile heissen RiddleSeg/RiddleCap/
-- RiddleDot (F38).
local function makeGlyph(col: Color3): Glyph
	local m = Instance.new("Model")
	m.Name = "RiddleGlyph"
	local parts: { BasePart } = {}
	for i = 1, GLYPH_N + 3 do
		local shape = if i <= GLYPH_N then Enum.PartType.Cylinder else Enum.PartType.Ball
		local p = newPart(shape, Vector3.one * 0.3, col, PARK, 1)
		p.Material = Enum.Material.SmoothPlastic
		p.Reflectance = 0.08
		p.Name = if i <= GLYPH_N then "RiddleSeg" elseif i == GLYPH_N + 3 then "RiddleDot" else "RiddleCap"
		p.Parent = m
		parts[i] = p
	end
	local hl = Instance.new("Highlight")
	hl.Adornee = m
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.FillColor = RIDDLE_HOT
	hl.FillTransparency = 1
	hl.OutlineColor = RIDDLE_INK
	hl.OutlineTransparency = 1
	hl.Enabled = false
	hl.Parent = m
	m.Parent = folder()
	return { model = m, parts = parts, hl = hl, sizes = table.create(GLYPH_N + 3, Vector3.zero),
		alpha = 0, glow = -1, dotOn = true }
end

-- Zeichen setzen: `center` = Bildmitte, `face` = waagerechte Richtung zur
-- Kamera, `L` = Strichlaenge in Studs, `m` = 0 "?" .. 1 "!" (darf ueber-
-- schwingen: der Haken federt), `roll` = Neigung in der Bildebene,
-- `alpha` = Sichtbarkeit, `glow` = 0..1 Aufblitzen (Umriss hell),
-- `yb` (0..1) = Unterkante des "!"-Strichs (der Strich waechst von oben),
-- `dot` = false: ohne Punkt (der Baerchi ist der Punkt).
local function glyphSet(g: Glyph, center: Vector3, face: Vector3, L: number, m: number, roll: number,
	alpha: number, glow: number, yb: number?, dot: boolean?)
	local right = Vector3.yAxis:Cross(face)
	right = if right.Magnitude > 0.01 then right.Unit else Vector3.xAxis
	local frame = CFrame.fromMatrix(center, right, Vector3.yAxis) * CFrame.Angles(0, 0, roll)
		* CFrame.new(0, -GLYPH_MID * L, 0)
	local nrm = frame.ZVector
	local n = GLYPH_N + 1
	local cut = math.clamp(yb or 0, 0, 1)
	local pts: { Vector3 } = table.create(n)
	for k = 1, n do
		local q = QUESTION_PTS[k]
		local e = Vector2.new(0, 1 - (1 - cut) * (k - 1) / (n - 1))
		local p = q + (e - q) * m
		pts[k] = frame:PointToWorldSpace(Vector3.new(p.X * L, p.Y * L, 0))
	end
	local mc = math.clamp(m, 0, 1)
	local parts = g.parts
	local sizes = g.sizes
	local cfs: { CFrame } = table.create(GLYPH_N + 3)
	local function size(i: number, v: Vector3)
		if (sizes[i] - v).Magnitude > 0.004 then
			sizes[i] = v
			parts[i].Size = v
		end
	end
	local w1, wn = 0, 0
	for k = 1, GLYPH_N do
		local a, b = pts[k], pts[k + 1]
		local w = lerpN(0.18, lerpN(0.26, 0.13, (k - 0.5) / GLYPH_N), mc) * L
		if k == 1 then w1 = w end
		if k == GLYPH_N then wn = w end
		local len = (b - a).Magnitude
		local mid = (a + b) / 2
		cfs[k] = if len > 1e-4 then CFrame.lookAt(mid, b, nrm) * ROT90 else CFrame.new(mid)
		size(k, Vector3.new(len + w * 0.5, w, w))
	end
	cfs[GLYPH_N + 1] = CFrame.new(pts[1])
	size(GLYPH_N + 1, Vector3.one * w1)
	cfs[GLYPH_N + 2] = CFrame.new(pts[n])
	size(GLYPH_N + 2, Vector3.one * wn)
	cfs[GLYPH_N + 3] = CFrame.new(frame:PointToWorldSpace(Vector3.new(0, GLYPH_DOT_Y * L, 0)))
	size(GLYPH_N + 3, Vector3.one * lerpN(0.24, 0.27, mc) * L)
	local a = math.clamp(alpha, 0, 1)
	local showDot = dot ~= false
	if math.abs(a - g.alpha) > 0.004 or showDot ~= g.dotOn then
		g.alpha = a
		g.dotOn = showDot
		local tr = if a > 0.996 then 0 else 1 - a
		for i, p in parts do
			p.Transparency = if i == GLYPH_N + 3 and not showDot then 1 else tr
		end
		g.hl.Enabled = a > 0.02
		g.glow = -1
	end
	local gl = math.clamp(glow, 0, 1)
	if math.abs(gl - g.glow) > 0.01 then
		g.glow = gl
		g.hl.OutlineColor = RIDDLE_INK:Lerp(RIDDLE_HOT, gl)
		g.hl.OutlineTransparency = 1 - a
		g.hl.FillTransparency = 1 - (0.1 + 0.45 * gl) * a
	end
	workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Funkeln: Stern aus zwei duennen Neon-Strichen (kleiner Akzent, F17), zur
-- Kamera gedreht, springt auf und vergeht in `life` s.
local function twinkle(pos: Vector3, size: number, col: Color3, life: number)
	local face = camFace(pos, Vector3.zAxis)
	local right = Vector3.yAxis:Cross(face)
	right = if right.Magnitude > 0.01 then right.Unit else Vector3.xAxis
	local base = CFrame.fromMatrix(pos, right, Vector3.yAxis)
	for _, ang in { 15, 105 } do
		local p = newPart(Enum.PartType.Block, Vector3.new(0.04, 0.04, 0.04), col, base * CFrame.Angles(0, 0, math.rad(ang)), 0)
		p.Name = "RiddleTwinkle"
		tween(p, life * 0.35, { Size = Vector3.new(size * 0.1, size, 0.04) }, Enum.EasingStyle.Back)
		-- zweiter Tween auf Size erst nach dem ersten (F02)
		task.delay(life * 0.4, function()
			if p.Parent then
				tween(p, life * 0.6, { Size = Vector3.new(0.02, 0.04, 0.02), Transparency = 1 })
			end
		end)
		Debris:AddItem(p, life + 0.15)
	end
end

-- Kleine Fragezeichen (BillboardGui, immer zur Kamera) fliegen aus `pos`
-- auseinander, steigen leicht und verblassen in `life` s (eine Schleife).
local function riddleConfetti(ctx: Ctx, pos: Vector3, n: number, size: number, life: number, speed: number)
	local bits: { ConfettiBit } = {}
	for i = 1, scaled(n, ctx.factor) do
		local a = newPart(Enum.PartType.Block, Vector3.one * 0.1, ctx.fx.color, CFrame.new(pos), 1)
		a.Name = "RiddleConfetti"
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromScale(size, size)
		bb.LightInfluence = 0
		bb.Adornee = a
		bb.Parent = a
		local tl = Instance.new("TextLabel")
		tl.Size = UDim2.fromScale(1, 1)
		tl.BackgroundTransparency = 1
		tl.Text = if i % 4 == 0 then "!" else "?"
		tl.TextScaled = true
		tl.Font = Enum.Font.FredokaOne
		tl.TextColor3 = if i % 3 == 0 then ctx.fx.color2:Lerp(Color3.new(1, 1, 1), 0.3) else ctx.fx.color:Lerp(RIDDLE_HOT, math.random() * 0.4)
		tl.TextStrokeColor3 = RIDDLE_INK
		tl.TextStrokeTransparency = 0
		tl.Rotation = math.random(-30, 30)
		tl.Parent = bb
		local dir = Vector3.new(math.random() - 0.5, 0.35 + math.random() * 0.6, math.random() - 0.5).Unit
		table.insert(bits, { a = a, tl = tl, p = pos, v = dir * speed * (0.6 + 0.6 * math.random()),
			r0 = tl.Rotation, spin = (math.random() * 2 - 1) * 200 })
	end
	runLoop("riddleConfetti", function(t, dt)
		if t >= life then return true end
		local k = t / life
		local parts: { BasePart } = table.create(#bits)
		local cfs: { CFrame } = table.create(#bits)
		for i, b in bits do
			b.v = b.v * math.max(0, 1 - 2.5 * dt) + Vector3.new(0, 4 * dt, 0)
			b.p += b.v * dt
			parts[i] = b.a
			cfs[i] = CFrame.new(b.p)
			b.tl.Rotation = b.r0 + b.spin * t
			b.tl.TextTransparency = k * k
			b.tl.TextStrokeTransparency = k * k
		end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		return false
	end, function()
		for _, b in bits do
			b.a:Destroy()
		end
	end)
end

-- Hut und Monokel eines Modells (Teile mit acc_hat/acc_brim bzw.
-- acc_monocle_glass im Namen). Bezug = Fusslage `pose0` (Klon an seinem
-- Platz, Groesse 1). set(pose, sc, lift, tilt): Hut `lift` Studs (x sc) ueber
-- dem Kopf, um `tilt` (rad, - = nach vorn) gekippt - nach jedem PivotTo
-- aufrufen. top() = Mitte ueber dem Hut, glint() = Monokel blitzt (gibt seine
-- Lage zurueck). nil ohne Hut.
local function riddleHat(model: Model, pose0: CFrame): RiddleHat?
	local hat: { BasePart } = {}
	local crown: BasePart? = nil
	local brim: BasePart? = nil
	local glass: BasePart? = nil
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local nm = string.lower(d.Name)
			if string.find(nm, "acc_brim", 1, true) then
				brim = d
				table.insert(hat, d)
			elseif string.find(nm, "acc_hat", 1, true) then
				table.insert(hat, d)
				if not string.find(nm, "band", 1, true) then
					crown = d
				end
			elseif string.find(nm, "acc_monocle_glass", 1, true) then
				glass = d
			end
		end
	end
	if #hat == 0 then return nil end
	local pivotP: BasePart = brim or hat[1]
	local relPivot = pose0:PointToObjectSpace(pivotP.Position)
	local rel: { CFrame } = {}
	for i, p in hat do
		rel[i] = pose0:ToObjectSpace(p.CFrame)
	end
	local topP: BasePart = crown or hat[1]
	local relTop = pose0:PointToObjectSpace(topP.Position + Vector3.new(0, topP.Size.Y * 0.5, 0))
	local lastT = CFrame.identity
	local lastPose = pose0
	local lastSc = 1
	local glassP = glass
	local glassCol = if glassP then glassP.Color else Color3.new(1, 1, 1)
	local glassMat = if glassP then glassP.Material else Enum.Material.Plastic
	return {
		set = function(pose: CFrame, sc: number, lift: number, tilt: number)
			local pv = pose * CFrame.new(relPivot * sc)
			local T = pv * CFrame.new(0, lift * sc, 0) * CFrame.Angles(tilt, 0, 0) * pv:Inverse()
			lastT, lastPose, lastSc = T, pose, sc
			for i, p in hat do
				p.CFrame = T * pose * CFrame.new(rel[i].Position * sc) * rel[i].Rotation
			end
		end,
		top = function(): Vector3
			return (lastT * lastPose):PointToWorldSpace(relTop * lastSc)
		end,
		glint = function(): Vector3?
			local gp = glassP
			if not gp or not gp.Parent then return nil end
			gp.Material = Enum.Material.Neon
			gp.Color = RIDDLE_HOT
			task.delay(0.2, function()
				if gp.Parent then
					gp.Material = glassMat
					gp.Color = glassCol
				end
			end)
			return gp.Position
		end,
	}
end

-- riddler: der Raetsel-Baerchi SELBST (echter Klon, Original lokal
-- unsichtbar, F03). Lueftet bei `tipAt` den Hut (ein "?" springt heraus, siehe
-- questionmarks), duckt sich bei `crouchAt`, steigt mit Drehung ueber den
-- Landepunkt vor dem Gegner (Fuesse `height` Studs hoch) und schwebt
-- gruebelnd; das Monokel blitzt bei jedem `glintAt`, bei `ahaAt` zuckt er
-- hoch ("Aha!"); bei `diveAt` Vorwaerts-Salto und Sturz in `dive` s
-- (Landung = Einschlag). Sein Weg wird zum Strich eines riesigen "!" (Spalt
-- `gap` ueber dem Kopf) - er selbst ist der Punkt. Ab `curlAt` biegt sich das
-- "!" in `curl` s zum "?"; nach `hold` s Rueckwaerts-Salto heim (`back` s),
-- an seiner Stelle erscheint der Punkt; zu Hause zieht er den Hut (`bow` s)
-- und das "?" schrumpft hinein. Setzt ctx.avatarCf, riddleHatTop, riddleLand,
-- riddleLandT. Laeuft auch auf fremden Modellen (ohne Hut).
--   tipAt, crouchAt, crouch, rise, spins, grow, height, glintAt, ahaAt, diveAt,
--   dive, flips, gap, curlAt, curl, hold, back, bow (Test: freezeAt)
BLOCKS.riddler = function(ctx, s)
	local source = ctx.selfModel
	if not source or not source.Parent then return end
	local clone = figureClone(source)
	if not clone then return end
	local H = ctx.selfSize.Y
	local home = CFrame.lookAt(ctx.selfFeet, ctx.selfFeet + ctx.fwd)
	local offset = home:ToObjectSpace(clone:GetPivot())
	local okScale, got = pcall(function() return clone:GetScale() end)
	local baseScale: number = if okScale and typeof(got) == "number" then got else 1
	local tipAt = s.tipAt or 0
	local crouchAt = math.max(tipAt + 0.45, s.crouchAt or 0.5)
	local crouch = math.max(0.05, s.crouch or 0.22)
	local rise = math.max(0.2, s.rise or 0.58)
	local spins = s.spins or 1
	local grow = s.grow or 1.2
	local height = s.height or 7
	local glintAt: { number } = s.glintAt or { 0.32, 1.62, 2.15 }
	local ahaAt = s.ahaAt or 2.15
	local riseAt = crouchAt + crouch
	local hangAt = riseAt + rise
	local diveAt = math.max(hangAt + 0.1, s.diveAt or 2.44)
	local dive = math.max(0.1, s.dive or 0.4)
	local flips = s.flips or 1
	local gap = s.gap or 0.9
	local curlAt = s.curlAt or 3.0
	local curl = math.max(0.1, s.curl or 0.3)
	local hold = math.max(0.1, s.hold or 0.55)
	local back = math.max(0.2, s.back or 0.7)
	local bow = math.max(0.2, s.bow or 0.55)
	local freezeAt: number? = s.freezeAt
	local landAt = diveAt + dive
	local backAt = landAt + hold
	local homeAt = backAt + back
	local total = homeAt + bow
	local col = ctx.fx.color
	local f = ctx.factor
	local hide = hideFigure(source)

	-- Landepunkt vor dem Gegner, darueber schwebt er (Sturz senkrecht)
	local landGap = (ctx.selfSize.Z + ctx.targetSize.Z) * 0.4 + 0.4
	local landFeet = ctx.targetFeet - ctx.fwd * landGap
	local land = CFrame.lookAt(landFeet, landFeet + ctx.fwd)
	local hover = landFeet + Vector3.new(0, height, 0)
	ctx.riddleLand = landFeet
	-- riesiges "!": Strich von `gap` ueber seinem Kopf beim Start des Sturzes
	-- bis `gap` ueber seinem Kopf nach der Landung
	local yBot = landFeet.Y + H + gap
	local Ls = math.max(2, hover.Y + H * grow + gap - yBot)
	local bang = makeGlyph(col)
	local markFrom = hangAt + 0.3

	local hl = Instance.new("Highlight")
	hl.Adornee = clone
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	-- warmes Weiss statt Gold: Gold auf dem weissen Fell im Schatten wirkte gruenlich-blass (F37)
	hl.FillColor = RIDDLE_HOT
	hl.FillTransparency = 0.84
	hl.OutlineColor = ctx.fx.color2
	hl.OutlineTransparency = 0
	hl.Parent = clone

	-- Funken und Staub (EIN Anker an der Koerpermitte)
	local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, home, 1)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARK_TEX
	sparks.Rate = 0
	sparks.Speed = NumberRange.new(4, 10)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Lifetime = NumberRange.new(0.35, 0.75)
	sparks.Drag = 2
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.32), NumberSequenceKeypoint.new(1, 0) })
	sparks.Color = ColorSequence.new(RIDDLE_HOT, col)
	sparks.LightEmission = 0.8
	sparks.Parent = anchor
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = SMOKE_TEX
	dust.Rate = 0
	dust.Speed = NumberRange.new(3, 8)
	dust.SpreadAngle = Vector2.new(180, 20)
	dust.Lifetime = NumberRange.new(0.5, 0.9)
	dust.Drag = 3
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, H * 0.3), NumberSequenceKeypoint.new(1, H * 0.8) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	dust.Color = ColorSequence.new(RIDDLE_HOT, ctx.fx.color2)
	dust.LightEmission = 0.3
	dust.Rotation = NumberRange.new(0, 360)
	dust.Parent = anchor

	-- Zielmarke: dunkler Kreis am Landepunkt, waechst bis zur Landung
	local mark = newPart(Enum.PartType.Cylinder, Vector3.new(0.05, 0.8, 0.8), RIDDLE_INK,
		CFrame.new(landFeet + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90)), 1)
	mark.Material = Enum.Material.SmoothPlastic
	mark.Name = "RiddleMark"

	local hatRig = riddleHat(clone, home)
	local hatLift, hatTilt = 0, 0
	local lastScale = 1
	-- Pose: Fuesse `feet`, gedreht um die Koerpermitte (wie `ascend`)
	local function place(feet: CFrame, pitch: number, yaw: number, roll: number, sc: number)
		if math.abs(sc - lastScale) > 0.008 then
			lastScale = sc
			pcall(function() clone:ScaleTo(baseScale * sc) end)
		end
		local half = H * sc * 0.5
		local pose = feet * CFrame.new(0, half, 0) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll) * CFrame.new(0, -half, 0)
		ctx.avatarCf = pose
		ctx.avatarScale = sc
		clone:PivotTo(pose * CFrame.new(offset.Position * sc) * offset.Rotation)
		anchor.CFrame = pose * CFrame.new(0, half, 0)
		if hatRig then
			hatRig.set(pose, sc, hatLift, hatTilt)
			ctx.riddleHatTop = hatRig.top()
		else
			ctx.riddleHatTop = (pose * CFrame.new(0, H * sc + 0.3, 0)).Position
		end
	end
	local function face(pos: Vector3): CFrame
		return CFrame.lookAt(pos, pos + ctx.fwd)
	end
	place(home, 0, 0, 0, 1)
	clone.Parent = folder()
	hide(1)

	local fired: { boolean } = {}
	local risen, diving, landed, gone, done = false, false, false, false, false
	runLoop("riddler", function(tRaw, dt)
		if not clone.Parent then return true end
		if tRaw >= (if freezeAt then freezeAt + 150 else total) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		-- Monokel blitzt
		for i, at in glintAt do
			if not fired[i] and t >= at then
				fired[i] = true
				local gp = if hatRig then hatRig.glint() else nil
				if gp then
					twinkle(gp + camFace(gp, -ctx.fwd) * 0.35, 1.5, RIDDLE_HOT, 0.32)
				end
			end
		end
		-- Hut lueften (tipAt .. +0,45), beim Verbeugen zu Hause noch einmal
		local tk = t - tipAt
		hatLift, hatTilt = 0, 0
		if tk >= 0 and tk < 0.45 then
			local up = if tk < 0.22 then easeOutBack(tk / 0.22) elseif tk < 0.3 then 1 else 1 - easeInOutSine((tk - 0.3) / 0.15)
			hatLift, hatTilt = 0.75 * up, -0.35 * up
		elseif t >= homeAt then
			local b = math.sin(math.pi * math.clamp((t - homeAt) / bow, 0, 1))
			hatLift, hatTilt = 0.95 * b, -0.55 * b
		end
		-- riesiges Zeichen: Sichtbarkeit, Form, Lage
		local gA, gM, gYb, gGlow = 0, 1, 1, 0
		local gDot = false
		local gL = Ls
		local gC: Vector3? = nil
		local gRoll = 0

		if t < crouchAt then
			-- 1. Hut lueften: lehnt sich leicht zurueck
			local k = math.clamp(tk / 0.45, 0, 1)
			place(home, 0.12 * math.sin(math.pi * k), 0, 0, 1)
		elseif t < riseAt then
			-- 2. ausholen: zuruecklehnen, kleiner werden
			local e = math.sin(((t - crouchAt) / crouch) * math.pi * 0.5)
			place(home, 0.28 * e, 0, 0, 1 - 0.08 * e)
		elseif t < hangAt then
			-- 3. aufsteigen mit Drehung, ueber den Landepunkt, wachsen
			local k = (t - riseAt) / rise
			local e = easeOutCubic(k)
			if not risen then
				risen = true
				sparks:Emit(scaled(22, f))
				dust:Emit(scaled(12, f))
			end
			local pos = home.Position:Lerp(hover, e) + Vector3.new(0, math.sin(math.pi * k) * 1.6, 0)
			place(face(pos), 0.28 * (1 - e), spins * TAU * e, 0, lerpN(0.92, grow, e))
		elseif t < diveAt then
			-- 4. schwebt und gruebelt (Kopf schief); "Aha!": zuckt hoch
			local h = t - hangAt
			local pos = hover + Vector3.new(0, math.sin(h * 2.6) * 0.22, 0)
			local pitch = 0
			local roll = math.sin(h * 1.7) * 0.14
			if t >= ahaAt then
				local a = t - ahaAt
				local j = math.exp(-a * 8)
				pos += Vector3.new(0, 0.45 * math.sin(math.min(1, a / 0.1) * math.pi * 0.5) * j, 0)
				pitch = 0.3 * j
				roll *= math.max(0, 1 - a / 0.1)
			end
			place(face(pos), pitch, 0, roll, grow)
		elseif t < landAt then
			-- 5. Vorwaerts-Salto und Sturz: sein Weg wird zum Strich des "!"
			if not diving then
				diving = true
				sparks:Emit(scaled(26, f))
			end
			local k = (t - diveAt) / dive
			local e = k * k
			local sc = lerpN(grow, 1, e)
			local pos = hover:Lerp(landFeet, e)
			place(face(pos), -flips * TAU * easeOutCubic(k), 0, 0, sc)
			gYb = math.clamp((pos.Y + H * sc + gap - yBot) / Ls, 0, 1)
			gA = math.clamp((1 - gYb) * 6, 0, 1)
		elseif t < backAt then
			-- 6. Landung (= Einschlag): gebueckt, richtet sich auf; er ist der Punkt
			if not landed then
				landed = true
				ctx.riddleLandT = os.clock()
				dust:Emit(scaled(30, f))
				sparks:Emit(scaled(40, f))
			end
			local k = (t - landAt) / hold
			place(land, lerpN(-0.45, 0, easeOutCubic(math.min(1, k * 2))), 0, 0, lerpN(0.88, 1, easeOutBack(math.min(1, k * 2.5))))
			gA, gYb = 1, 0
		elseif t < homeAt then
			-- 7. Rueckwaerts-Salto heim; an seiner Stelle erscheint der Punkt
			if not gone then
				gone = true
				twinkle(Vector3.new(landFeet.X, yBot + GLYPH_DOT_Y * Ls, landFeet.Z), 2.4, RIDDLE_HOT, 0.35)
			end
			local k = (t - backAt) / back
			local e = easeInOutSine(k)
			local pos = landFeet:Lerp(home.Position, e) + Vector3.new(0, math.sin(math.pi * k) * 4, 0)
			place(face(pos), TAU * e, 0, 0, 1)
			gA, gYb, gDot = 1, 0, true
		else
			-- 8. zieht den Hut, das riesige "?" schrumpft hinein
			local k = math.clamp((t - homeAt) / bow, 0, 1)
			place(home, -0.38 * math.sin(math.pi * k), 0, 0, 1)
			local q = math.clamp((t - homeAt) / (bow * 0.7), 0, 1)
			local e = easeInOutSine(q)
			local from = Vector3.new(landFeet.X, yBot + GLYPH_MID * Ls, landFeet.Z)
			local to = (ctx.riddleHatTop or (home.Position + Vector3.new(0, H, 0))) + Vector3.new(0, 0.15, 0)
			gC = from:Lerp(to, e) + Vector3.new(0, math.sin(math.pi * q) * 2.5, 0)
			gL = lerpN(Ls, 0.3, q * q)
			gRoll = TAU * e
			gA, gYb, gDot = (if q >= 1 then 0 else 1), 0, true
			if q >= 1 and not done then
				done = true
				twinkle(to, 1.8, RIDDLE_HOT, 0.35)
				sparks:Emit(scaled(16, f))
			end
		end

		-- Zielmarke waechst bis zur Landung, verblasst danach
		if t >= markFrom and t < landAt then
			local k = (t - markFrom) / math.max(0.05, landAt - markFrom)
			local d = lerpN(0.8, 3.4, k * k)
			mark.Size = Vector3.new(0.05, d, d)
			mark.Transparency = lerpN(0.9, 0.42, k)
		elseif t >= landAt then
			mark.Transparency = math.min(1, 0.42 + (t - landAt) / 0.3)
		end

		-- das riesige Zeichen
		if t >= diveAt then
			if t >= landAt then
				-- Aufprall: Strich staucht sich kurz, blitzt; ab `curlAt` -> "?"
				local q = t - landAt
				if not gC then
					gL = Ls * (1 - 0.07 * math.exp(-q * 10) * math.cos(q * 30))
				end
				gGlow = math.max(0, 1 - q / 0.35)
				if t >= curlAt then
					gM = 1 - easeOutBack(math.clamp((t - curlAt) / curl, 0, 1))
				end
			end
			local c = gC or Vector3.new(landFeet.X, yBot + GLYPH_MID * gL, landFeet.Z)
			glyphSet(bang, c, camFace(c, -ctx.fwd), gL, gM, gRoll, gA, gGlow, gYb, gDot)
		end
		return false
	end, function()
		hide(0)
		ctx.avatarCf = nil
		ctx.avatarScale = nil
		ctx.riddleHatTop = nil
		clone:Destroy()
		bang.model:Destroy()
		mark:Destroy()
		Debris:AddItem(anchor, 1.2)
	end)
end

-- questionmarks: die Lawine. Ein kleines goldenes "?" springt bei `appear`
-- aus dem Hut des `riddler`-Klons (sonst ueber dem Angreifer), fliegt in
-- `fly` s ueber den Gegner und waechst (Strichlaenge `big`, Mitte `high`
-- Studs ueber seinen Fuessen); bei jedem Eintrag in `splitAt` teilt sich
-- jedes Zeichen in zwei (bis `count`, Zweierpotenz; niedrige Grafik: 4). Die
-- Zeichen wirbeln immer schneller (`whirl` rad) auf einem Ring (`radius`,
-- Mitte `lift` hoch, Strichlaenge `small`) um den Gegner, mit Luecke zur
-- Seite von Angreifer und Kamera (`gap` Grad Rand); bei `stopAt` steht der
-- Wirbel schlagartig still und bebt; bei `ahaAt` biegen sich alle in `aha` s
-- zu "!", ab `dropAt` rammt sich eines nach dem anderen (`every`, hinten
-- zuerst) in `fall` s in den Boden (Ring x `inward`) - ein Kaefig; bei
-- `flashAt` leuchten alle auf; ab `curlAt` biegen sie sich in `curl` s
-- zurueck zu "?" und heben ab, ab `popAt` zerplatzen sie (`popEvery`) in
-- kleine Fragezeichen. Setzt ctx.riddleGap und ctx.riddleRing (Kamera "riddle").
--   at, count, appear, fly, big, high, splitAt, split, radius, lift, small,
--   whirl, stopAt, ahaAt, aha, dropAt, every, fall, inward, flashAt, curlAt,
--   curl, popAt, popEvery, gap (Test: freezeAt)
BLOCKS.questionmarks = function(ctx, s)
	local tg = groundAt(ctx, s.at or "target")
	local want = math.max(1, s.count or 8)
	if not extrasOn(ctx) then
		want = math.min(want, 4)
	end
	local splitAt: { number } = s.splitAt or { 0.95, 1.25, 1.55 }
	local G = 0
	while G < #splitAt and 2 ^ (G + 1) <= want do
		G += 1
	end
	local N = math.floor(2 ^ G + 0.5)
	local appear = s.appear or 0.18
	local fly = math.max(0.1, s.fly or 0.72)
	local big = s.big or 5
	local high = s.high or 7.2
	local split = math.max(0.05, s.split or 0.24)
	local R = s.radius or 6
	local lift = s.lift or 4.6
	local small = s.small or 3
	local W = s.whirl or 5
	local stopAt = s.stopAt or 1.92
	local ahaAt = s.ahaAt or 2.15
	local aha = math.max(0.05, s.aha or 0.16)
	local dropAt = s.dropAt or 2.27
	local every = s.every or 0.045
	local fall = math.max(0.04, s.fall or 0.12)
	local inward = s.inward or 0.82
	local flashAt: number? = s.flashAt
	local curlAt = s.curlAt or 3.0
	local curl = math.max(0.05, s.curl or 0.32)
	local popAt = s.popAt or 3.45
	local popEvery = s.popEvery or 0.05
	local freezeAt: number? = s.freezeAt
	local col = ctx.fx.color
	local total = popAt + (N - 1) * popEvery + 0.05

	-- Luecke: zwischen der Seite des Angreifers (dort landet er) und der
	-- Kamera dieses Clients (freier Blick auf den Gegner), einmal beim Start (F22)
	local toAtt = -ctx.fwd
	local toCam = toAtt
	local cam = workspace.CurrentCamera
	if cam then
		local v = cam.CFrame.Position - tg
		v = Vector3.new(v.X, 0, v.Z)
		if v.Magnitude > 1 then
			toCam = v.Unit
		end
	end
	local gapDir = toAtt + toCam
	gapDir = if gapDir.Magnitude > 0.2 then gapDir.Unit else toAtt
	local between = math.acos(math.clamp(toAtt:Dot(toCam), -1, 1))
	local halfGap = math.clamp(between / 2 + math.rad(s.gap or 34), math.rad(34), math.rad(80))
	local gapSide = Vector3.yAxis:Cross(gapDir).Unit
	local span = TAU - 2 * halfGap
	ctx.riddleGap = gapDir
	ctx.riddleRing = tg

	local function slotDir(theta: number): Vector3
		return gapDir * math.cos(theta) + gapSide * math.sin(theta)
	end
	local function genL(g: number): number
		return lerpN(big, small, if G > 0 then (g / G) ^ 0.8 else 1)
	end
	local function genR(g: number): number
		return if g <= 0 or G == 0 then 0 else R * (g / G) ^ 0.7
	end
	local function genH(g: number): number
		return lerpN(high, lift, if G > 0 then g / G else 1)
	end
	-- Mitte von Zeichen `i` (0-basiert) als Teil seiner Gruppe in Generation `g`
	local function slotPos(i: number, g: number, phi: number): Vector3
		if g <= 0 then
			return tg + Vector3.new(0, genH(0), 0)
		end
		local n = 2 ^ g
		local j = math.floor(i / 2 ^ (G - g))
		local theta = halfGap + (j + 0.5) * span / n + phi
		return tg + slotDir(theta) * genR(g) + Vector3.new(0, genH(g), 0)
	end
	-- Wirbel: immer schneller, steht bei `stopAt` schlagartig (Winkel 0 =
	-- Luecke an ihrem Platz)
	local function whirlAt(t: number): number
		local t1 = splitAt[1] or stopAt
		if t <= t1 then return -W end
		if t >= stopAt then return 0 end
		local u = (t - t1) / math.max(0.05, stopAt - t1)
		return -W * (1 - u * u)
	end
	local function hoverPos(i: number, t: number): (Vector3, number)
		local gnow = 0
		for k = 1, G do
			if t >= splitAt[k] then gnow = k end
		end
		local phi = whirlAt(t)
		if gnow == 0 then
			return slotPos(i, 0, phi), genL(0)
		end
		local e = easeOutBack(math.clamp((t - splitAt[gnow]) / split, 0, 1))
		return slotPos(i, gnow - 1, phi):Lerp(slotPos(i, gnow, phi), e), lerpN(genL(gnow - 1), genL(gnow), e)
	end

	-- Zeichen: Generation des Auftauchens = G - (Zweierpotenz-Exponent von i);
	-- Einschlag-Reihenfolge: gegenueber der Luecke zuerst, dann nach vorn
	local mid = (N - 1) / 2
	local order: { number } = {}
	for i = 0, N - 1 do
		table.insert(order, i)
	end
	table.sort(order, function(a, b)
		local da, db = math.abs(a - mid), math.abs(b - mid)
		if math.abs(da - db) > 1e-6 then return da < db end
		return a < b
	end)
	local rankOf: { [number]: number } = {}
	for r, i in order do
		rankOf[i] = r - 1
	end
	local marks: { RiddleMark } = {}
	for i = 0, N - 1 do
		local vis = 0
		if i > 0 then
			local v, tz = i, 0
			while v % 2 == 0 do
				v = v // 2
				tz += 1
			end
			vis = G - tz
		end
		table.insert(marks, { g = makeGlyph(col), i = i, vis = vis, rank = rankOf[i],
			theta = halfGap + (i + 0.5) * span / N, hit = false, popped = false, phase = i * 1.7 })
	end

	local from0: Vector3? = nil
	runLoop("questionmarks", function(tRaw)
		if tRaw >= (if freezeAt then freezeAt + 150 else total) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		for _, mk in marks do
			if mk.popped then continue end
			local born = if mk.vis == 0 then appear else (splitAt[mk.vis] or math.huge)
			if t < born then continue end
			local pos = tg
			local L = small
			local m, roll, glow = 0, 0, 0
			-- 1. springt aus dem Hut / schwebt, teilt sich, wirbelt
			if mk.vis == 0 and t < appear + fly then
				if not from0 then
					from0 = ctx.riddleHatTop or (ctx.selfFeet + Vector3.new(0, ctx.selfSize.Y + 0.4, 0))
					twinkle(from0 :: Vector3, 1.4, RIDDLE_HOT, 0.3)
				end
				local k = (t - appear) / fly
				local e = easeInOutSine(k)
				pos = (from0 :: Vector3):Lerp(slotPos(0, 0, -W), e) + Vector3.new(0, math.sin(math.pi * k) * 3, 0)
				-- klein aus dem Hut ploppen (0,08 s), dann im Flug wachsen
				L = lerpN(0.45, big, easeInOutSine(math.min(1, k * 1.1))) * easeOutBack(math.min(1, (t - appear) / 0.08))
				roll = TAU * e
			else
				local hp, hlen = hoverPos(mk.i, t)
				pos, L = hp, hlen
				local amp = math.clamp((t - born) / 0.3, 0, 1)
				if t >= stopAt then
					amp *= math.max(0, 1 - (t - stopAt) / 0.08)
				end
				pos += Vector3.new(0, math.sin(t * 2.4 + mk.phase) * 0.16 * amp, 0)
				roll = math.sin(t * 1.8 + mk.phase * 1.3) * 0.16 * amp
				if t >= stopAt and t < dropAt then
					roll += math.sin(t * 55 + mk.phase) * 0.035
				end
			end
			-- 2. "Aha!": "?" -> "!"
			if t >= ahaAt then
				local k = math.clamp((t - ahaAt) / aha, 0, 1)
				m = easeOutBack(k)
				glow = math.max(0, 1 - (t - ahaAt) / 0.3)
				roll *= 1 - k
			end
			-- 3. rammt sich in den Boden (der Punkt steckt)
			local tDrop = dropAt + mk.rank * every
			if t >= tDrop then
				local dir = slotDir(mk.theta)
				local Lg = genL(G)
				local foot = tg + dir * (R * inward)
				local k = math.clamp((t - tDrop) / fall, 0, 1)
				pos = slotPos(mk.i, G, 0):Lerp(foot + Vector3.new(0, GLYPH_FOOT * Lg, 0), k * k)
				L = Lg
				roll = 0
				if k >= 1 then
					if not mk.hit then
						mk.hit = true
						burstAt(ctx, foot + Vector3.new(0, 0.25, 0), 10, 8, col)
						if extrasOn(ctx) then
							burstAt(ctx, foot + Vector3.new(0, 0.2, 0), 5, 4, ctx.fx.color2, true)
						end
					end
					local q = t - tDrop - fall
					L = Lg * (1 - 0.1 * math.exp(-q * 12) * math.cos(q * 28))
					pos = foot + Vector3.new(0, GLYPH_FOOT * L, 0)
				end
			end
			-- Einschlag: alle leuchten auf
			if flashAt and t >= flashAt then
				glow = math.max(glow, 1 - (t - flashAt) / 0.35)
			end
			-- 4. jede Antwort wird wieder eine Frage: "!" -> "?", hebt ab
			local tCurl = curlAt + mk.rank * 0.02
			if t >= tCurl then
				local k = math.clamp((t - tCurl) / curl, 0, 1)
				m = 1 - easeOutBack(k)
				pos += Vector3.new(0, 1.3 * easeOutCubic(k), 0)
				roll = math.sin(k * TAU) * 0.2 * (1 - k)
			end
			-- 5. zerplatzt in kleine Fragezeichen
			if t >= popAt + mk.rank * popEvery then
				mk.popped = true
				glyphSet(mk.g, pos, camFace(pos, gapDir), L, m, roll, 0, 0)
				riddleConfetti(ctx, pos, 5, 0.9, 0.8, 7)
				twinkle(pos, 1.6, RIDDLE_HOT, 0.3)
				continue
			end
			glyphSet(mk.g, pos, camFace(pos, gapDir), L, m, roll, 1, glow)
		end
		return false
	end, function()
		for _, mk in marks do
			mk.g.model:Destroy()
		end
	end)
end

-- puzzled: der GEGNER als Klon (Original lokal unsichtbar, F03) schaut sich
-- verwirrt um (dreht sich hin und her, immer hektischer, Kopf schief), zuckt
-- bei `ahaAt` zusammen und steht starr; bei `hold` ist das Original wieder da
-- (= Einschlag, Server-Rueckstoss).
--   ahaAt, hold, look (Test: freezeAt)
BLOCKS.puzzled = function(ctx, s)
	local source = ctx.targetModel
	if not source or not source.Parent then return end
	local clone = figureClone(source)
	if not clone then return end
	local H = ctx.targetSize.Y
	local home = CFrame.lookAt(ctx.targetFeet, ctx.targetFeet - ctx.fwd)
	local offset = home:ToObjectSpace(clone:GetPivot())
	local ahaAt = s.ahaAt or 1.25
	local hold = math.max(ahaAt, s.hold or 1.95)
	local look = s.look or 0.7
	local freezeAt: number? = s.freezeAt
	local hide = hideFigure(source)
	local function place(y: number, pitch: number, yaw: number, roll: number)
		local half = H * 0.5
		local pose = home * CFrame.new(0, y + half, 0) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll) * CFrame.new(0, -half, 0)
		clone:PivotTo(pose * offset)
	end
	place(0, 0, 0, 0)
	clone.Parent = folder()
	hide(1)
	local lastYaw = 0
	runLoop("puzzled", function(tRaw)
		if not clone.Parent then return true end
		if tRaw >= (if freezeAt then freezeAt + 150 else hold) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		if t < ahaAt then
			-- umschauen: hin und her, immer hektischer, kleine Hopser
			local ph = TAU * (0.9 * t + 0.9 * t * t / math.max(0.2, ahaAt))
			local amp = math.min(1, t / 0.25)
			local yaw = look * math.sin(ph) * amp
			lastYaw = yaw
			place(0.1 * math.abs(math.sin(ph)) * amp, 0, yaw, 0.14 * math.sin(ph * 0.5 + 0.8) * amp)
		else
			-- "Aha!": zuckt zusammen (Hopser, lehnt sich zurueck), steht starr und bebt
			local a = t - ahaAt
			local hop = if a < 0.14 then math.sin((a / 0.14) * math.pi) * 0.3 else 0
			local yaw = lastYaw * math.exp(-a * 10) + math.sin(a * 60) * 0.02
			place(hop, if a < 0.14 then hop * 0.8 else 0.05, yaw, 0)
		end
		return false
	end, function()
		hide(0)
		clone:Destroy()
	end)
end

-- riddlebonk: Echo der Fragenlawine. Ein "?" (Strichlaenge `size`) springt
-- ueber dem Gegner auf, biegt sich bei `ahaAt` in `aha` s zum "!", faellt ab
-- `dropAt` in `fall` s auf seinen Kopf (Treffer), federt hoch, biegt sich ab
-- `curlAt` zurueck und zerplatzt bei `popAt` in kleine Fragezeichen
-- (Lebensdauer `life`).
--   at, size, ahaAt, aha, dropAt, fall, curlAt, popAt, life (Test: freezeAt)
BLOCKS.riddlebonk = function(ctx, s)
	local tf = groundAt(ctx, s.at or "target")
	local headY = tf.Y + ctx.targetSize.Y
	local L = s.size or 1.9
	local ahaAt = s.ahaAt or 0.08
	local aha = math.max(0.03, s.aha or 0.07)
	local dropAt = s.dropAt or 0.16
	local fall = math.max(0.03, s.fall or 0.09)
	local curlAt = s.curlAt or 0.3
	local popAt = s.popAt or 0.38
	local life = s.life or 0.26
	local freezeAt: number? = s.freezeAt
	local col = ctx.fx.color
	local g = makeGlyph(col)
	local hoverY = headY + 1.6 + 0.685 * L
	local hitY = headY + 0.66 * L
	local hit, popped = false, false
	runLoop("riddlebonk", function(tRaw)
		if tRaw >= (if freezeAt then freezeAt + 150 else popAt + 0.02) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		if popped then return false end
		local y = hoverY
		local m, glow = 0, 0
		local Lc = L * easeOutBack(math.clamp(t / 0.07, 0, 1))
		if t >= ahaAt then
			m = easeOutBack(math.clamp((t - ahaAt) / aha, 0, 1))
			glow = math.max(0, 1 - (t - ahaAt) / 0.2)
		end
		if t >= dropAt then
			local k = math.clamp((t - dropAt) / fall, 0, 1)
			y = lerpN(hoverY, hitY, k * k)
			if k >= 1 then
				if not hit then
					hit = true
					burstAt(ctx, Vector3.new(tf.X, headY + 0.2, tf.Z), 12, 9, col)
				end
				local q = t - dropAt - fall
				y = hitY + 0.9 * math.sin(math.min(1, q / 0.12) * math.pi * 0.5)
				glow = math.max(glow, 1 - q / 0.2)
			end
		end
		if t >= curlAt then
			m = 1 - easeOutBack(math.clamp((t - curlAt) / 0.08, 0, 1))
		end
		local pos = Vector3.new(tf.X, y, tf.Z)
		if t >= popAt then
			popped = true
			glyphSet(g, pos, camFace(pos, -ctx.fwd), Lc, m, 0, 0, 0)
			riddleConfetti(ctx, pos, 4, 0.7, life, 6)
			return false
		end
		glyphSet(g, pos, camFace(pos, -ctx.fwd), Lc, m, 0, 1, glow)
		return false
	end, function()
		g.model:Destroy()
	end)
end


--------------------------------------------------------------------------------
-- 25.10.2026 Hoellensiegel (HellSigil, Teufel). Nach dem Blender-Prototyp vom
-- 22.10. (Video-Vorbild des Nutzers): Siegel unter dem Teufel, Sternbruch, ein
-- rotes Mal fliegt zum Gegner und brennt dort ein ZWEITES Siegel ein; ueber dem
-- Dreizack entsteht mit einem Impact-Frame eine schwarze Sonne, der Teufel
-- schleudert sie in den Kreis, eine Feuersaeule mit Kronen-Schockwelle bricht
-- heraus. Doku in SkillFXConfig ("BAUSTEINE", Hoellensiegel).
--------------------------------------------------------------------------------

local HELL_EMBER = Color3.fromRGB(255, 196, 120)    -- Glut, heller Rand
local HELL_VIOLET = Color3.fromRGB(150, 70, 255)    -- Wulst im Siegel
local HELL_INDIGO = Color3.fromRGB(70, 45, 255)     -- Nachgluehen nach dem Sternbruch
local FIRE_TEX = "rbxasset://textures/particles/fire_main.dds"

type HellRing = { beams: { Beam }, atts: { Attachment }, set: (number, number, number?) -> () }
type HellCres = { a: { Attachment }, b: { Beam }, R: number, th0: number, th1: number, w: number }
type HellSlash = { a: BasePart, ring: HellRing, tilt: CFrame, rad: number, t0: number, spd: number }

-- Kreis aus 4 Bezier-Beams (Viertelkreise, CurveSize 0,5523 r) an EINEM
-- Anker-Teil, in dessen lokaler XZ-Ebene auf Hoehe y (Trick aus `worldglobe`).
-- `segs` < 4 = offener Bogen ab Winkel 0 (Sichel, Hieb): die Breite laeuft an
-- beiden Enden spitz aus. FaceCamera: auch von innen und von der Seite sichtbar.
local function hellRing(anchor: BasePart, r: number, y: number, width: number, col: Color3,
	emission: number, tr: number, segs: number?): HellRing
	local n = math.clamp(segs or 4, 1, 4)
	local nAtt = if n == 4 then 4 else n + 1
	local atts: { Attachment } = {}
	local beams: { Beam } = {}
	for i = 1, nAtt do
		local a = Instance.new("Attachment")
		a.Parent = anchor
		atts[i] = a
	end
	for i = 1, n do
		local b = Instance.new("Beam")
		b.Attachment0 = atts[i]
		b.Attachment1 = atts[(i % nAtt) + 1]
		b.FaceCamera = true
		b.Segments = 14
		b.LightEmission = emission
		b.LightInfluence = 0
		b.Color = ColorSequence.new(col)
		b.Transparency = NumberSequence.new(tr)
		local w0 = if n < 4 and i == 1 then 0.12 else 1
		local w1 = if n < 4 and i == n then 0.12 else 1
		b.Width0 = width * w0
		b.Width1 = width * w1
		b.Parent = anchor
		beams[i] = b
	end
	local function set(rr: number, yy: number, w: number?)
		for i, a in atts do
			local ang = (i - 1) * (math.pi / 2)
			local radial = Vector3.new(math.cos(ang), 0, math.sin(ang))
			local tangent = Vector3.new(-math.sin(ang), 0, math.cos(ang))
			a.CFrame = CFrame.fromMatrix(radial * rr + Vector3.new(0, yy, 0), tangent, radial)
		end
		for i, b in beams do
			b.CurveSize0 = 0.5523 * rr
			b.CurveSize1 = 0.5523 * rr
			if w then
				b.Width0 = w * (if n < 4 and i == 1 then 0.12 else 1)
				b.Width1 = w * (if n < 4 and i == n then 0.12 else 1)
			end
		end
	end
	set(r, y)
	return { beams = beams, atts = atts, set = set }
end

-- Sichtbarkeit einer Gruppe Beams (base = Grund-Transparenz, a = 0..1).
local function hellFade(beams: { Beam }, base: number, a: number)
	local seq = NumberSequence.new(math.clamp(1 - (1 - base) * a, 0, 1))
	for _, b in beams do b.Transparency = seq end
end

-- quadratische Bezier-Kurve
local function bez2(p0: Vector3, p1: Vector3, p2: Vector3, u: number): Vector3
	return p0 * (1 - u) ^ 2 + p1 * (2 * u * (1 - u)) + p2 * (u * u)
end

-- hellsigil: Hoellensiegel am Boden (SurfaceGui wie `sigil`): Flammenkranz,
-- Ringe, Runenband und ein umgedrehtes Pentagramm, das Strich fuer Strich
-- gezeichnet wird, ein roter Schein innen, ein violetter Wulst (Beam-Kreis).
-- Eigenes Siegel (`blades`, `discs`): Orbit-Linien (weiss/gruen), farbige
-- Lichtklingen drehen sich mit, gestapelte Feuerringe und eine Wirbelscheibe
-- am Himmel; bei `burstAt` zieht sich alles zusammen und bricht als Stern auf
-- (Spitzen, Kernblitz, Funken), ein Indigo-Ring verglimmt. Siegel unter dem
-- Gegner (`markFrom = "avatar"`): ein rotes Mal fliegt von der Dreizackspitze
-- (ctx.hellTip) im Bogen herueber, erst bei seiner Landung zeichnet sich der
-- Kreis; ab `glowAt` heller, bei `pulseAt` gleisst er (Einschlag).
-- Setzt ctx.hellCircle (bei at = "target").
--   at, radius, draw, dur, spin, runes, points, blades, bladeLen, discs,
--   burstAt, markFrom, mark, glowAt, pulseAt
BLOCKS.hellsigil = function(ctx, s)
	local center = groundAt(ctx, s.at) + Vector3.new(0, 0.06, 0)
	local R = radiusOf(s.radius, 6)
	local dur = s.dur or 3
	local draw = s.draw or 0.7
	local spin = s.spin or 0.6
	local col = pickColor(s, ctx.fx)
	local dark = ctx.fx.color2
	local sc = R / 7
	if s.at == "target" then ctx.hellCircle = center end

	-- 0. das rote Mal (fliegt herueber, erst danach wird gezeichnet)
	local t0 = 0
	if s.markFrom == "avatar" then
		t0 = s.mark or 0.4
		local from = ctx.hellTip or (ctx.selfFeet + Vector3.new(0, ctx.selfSize.Y * 2.4, 0))
		local flare = newPart(Enum.PartType.Ball, Vector3.one * 0.9, col, CFrame.new(from), 0.1)
		local bars = {
			newPart(Enum.PartType.Block, Vector3.new(3.2, 0.14, 0.14), HELL_EMBER, CFrame.new(from), 0.1),
			newPart(Enum.PartType.Block, Vector3.new(0.14, 3.2, 0.14), HELL_EMBER, CFrame.new(from), 0.1),
		}
		local fa0 = Instance.new("Attachment")
		fa0.Position = Vector3.new(0, 0.35, 0)
		fa0.Parent = flare
		local fa1 = Instance.new("Attachment")
		fa1.Position = Vector3.new(0, -0.35, 0)
		fa1.Parent = flare
		local trail = Instance.new("Trail")
		trail.Attachment0 = fa0
		trail.Attachment1 = fa1
		trail.Lifetime = 0.3
		trail.FaceCamera = true
		trail.LightEmission = 0.8
		trail.Color = ColorSequence.new(HELL_EMBER, col)
		trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		trail.Parent = flare
		local land = center + Vector3.new(0, 0.4, 0)
		local peak = (from + land) / 2 + Vector3.new(0, math.max(4, (land - from).Magnitude * 0.35), 0)
		runLoop("hellmark", function(t)
			local k = math.min(1, t / t0)
			local e = k * k * (3 - 2 * k)
			local p = bez2(from, peak, land, e)
			local cam = workspace.CurrentCamera
			local face = if cam then CFrame.lookAt(p, cam.CFrame.Position) else CFrame.new(p)
			local tw = 1 + 0.25 * math.sin(t * 40)
			flare.CFrame = face
			bars[1].CFrame = face * CFrame.Angles(0, 0, t * 6)
			bars[2].CFrame = bars[1].CFrame
			bars[1].Size = Vector3.new(3.2 * tw, 0.14, 0.14)
			bars[2].Size = Vector3.new(0.14, 3.2 * tw, 0.14)
			if k >= 1 then
				burstAt(ctx, land, 22, 10, col)
				return true
			end
			return false
		end, function()
			flare:Destroy()
			for _, b in bars do b:Destroy() end
		end)
	end

	-- 1. Scheibe + Zeichenflaeche
	local PPS = 28
	local canvas = R * 2.7
	local u = 1 / canvas
	local disc = newPart(Enum.PartType.Cylinder, Vector3.new(0.03, 0.2, 0.2), dark,
		CFrame.new(center - Vector3.new(0, 0.03, 0)) * CFrame.Angles(0, 0, math.rad(90)), 0.15)
	disc.Material = Enum.Material.SmoothPlastic
	tweenLater(disc, t0, draw * 0.5, { Size = Vector3.new(0.03, R * 2.12, R * 2.12) }, Enum.EasingStyle.Quart)
	local plate = newPart(Enum.PartType.Block, Vector3.new(canvas, 0.04, canvas), col, CFrame.new(center), 1)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PPS
	gui.LightInfluence = 0
	gui.Brightness = 3
	gui.Adornee = plate
	gui.Parent = plate
	local strokes: { UIStroke } = {}
	local fills: { Frame } = {}
	local function layer(): Frame
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.fromScale(1, 1)
		f.BackgroundTransparency = 1
		f.Parent = gui
		return f
	end
	local flames, outer, star, inner = layer(), layer(), layer(), layer()
	local layers = { flames, outer, star, inner }
	local function circle(parent: Frame, radius: number, thick: number, color: Color3, delay: number, fill: number?)
		local c = Instance.new("Frame")
		c.AnchorPoint = Vector2.new(0.5, 0.5)
		c.Position = UDim2.fromScale(0.5, 0.5)
		c.Size = UDim2.fromScale(0, 0)
		c.BackgroundColor3 = color
		c.BackgroundTransparency = 1
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = c
		if fill then
			table.insert(fills, c)
			tweenLater(c, t0 + delay, draw * 0.5, { BackgroundTransparency = fill })
		else
			local st = Instance.new("UIStroke")
			st.Color = color
			st.Thickness = thick * PPS
			st.Parent = c
			table.insert(strokes, st)
		end
		c.Parent = parent
		local d = radius * 2 * u
		tweenLater(c, t0 + delay, draw * 0.45, { Size = UDim2.fromScale(d, d) }, Enum.EasingStyle.Quart)
	end
	-- Strich von a nach b (Studs relativ zur Mitte). `grow`: er waechst von a
	-- aus (Zeichnen) - dazu ein 0-grosser Halter in a, der gedreht wird.
	local function bar(parent: Frame, a: Vector2, b: Vector2, thick: number, color: Color3, delay: number, grow: boolean?): Frame
		local holder = Instance.new("Frame")
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(0.5 + a.X * u, 0.5 + a.Y * u)
		holder.Size = UDim2.fromScale(0, 0)
		holder.BackgroundTransparency = 1
		holder.Rotation = math.deg(math.atan2(b.Y - a.Y, b.X - a.X))
		holder.Parent = parent
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0, 0.5)
		f.Position = UDim2.fromScale(0, 0)
		local px = (b - a).Magnitude * PPS
		local th = math.max(2, thick * PPS)
		f.Size = UDim2.new(0, if grow then 0 else px, 0, th)
		f.BackgroundColor3 = color
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Parent = holder
		table.insert(fills, f)
		tweenLater(f, t0 + delay, if grow then 0.05 else draw * 0.25, { BackgroundTransparency = 0 })
		if grow then
			tweenLater(f, t0 + delay, draw * 0.16, { Size = UDim2.new(0, px, 0, th) }, Enum.EasingStyle.Sine)
		end
		return f
	end
	-- Flammenkranz: Zungen nach aussen, flackern
	local tongues: { { f: Frame, len: number } } = {}
	local nT = if extrasOn(ctx) then 44 else 26
	for i = 1, nT do
		local ang = (i / nT) * TAU + (math.random() - 0.5) * 0.08
		local dir = Vector2.new(math.cos(ang), math.sin(ang))
		local len = R * (0.07 + math.random() * 0.16)
		local a = dir * R * 0.98
		local c = if i % 3 == 0 then HELL_EMBER elseif i % 3 == 1 then col else Color3.fromRGB(200, 25, 30)
		local f = bar(flames, a, a + dir * len, R * (0.022 + math.random() * 0.03), c, draw * 0.1 + (i / nT) * draw * 0.4, true)
		table.insert(tongues, { f = f, len = len })
	end
	circle(outer, R * 0.6, 0, col, draw * 0.2, 0.8)              -- roter Schein innen
	circle(outer, R, 0.28, col, 0)
	circle(outer, R * 0.94, 0.08, HELL_EMBER, draw * 0.08)
	circle(outer, R * 0.66, 0.15, HELL_EMBER, draw * 0.16)
	circle(inner, R * 0.36, 0.12, col, draw * 0.3)
	circle(inner, R * 0.16, 0.1, HELL_EMBER, draw * 0.4)
	-- Runenband zwischen 0,66 R und 0,94 R
	local runes = s.runes or 16
	local g = R * 0.05
	for i = 1, runes do
		local ang = (i / runes) * TAU
		local rad = Vector2.new(math.cos(ang), math.sin(ang))
		local tan = Vector2.new(-math.sin(ang), math.cos(ang))
		local c = rad * R * 0.8
		local delay = draw * 0.35 + (i / runes) * draw * 0.45
		bar(outer, c - rad * g * 1.4, c + rad * g * 1.4, 0.1, HELL_EMBER, delay)
		local pick = math.random(1, 4)
		if pick == 1 then
			bar(outer, c + rad * g * 1.4, c + rad * g * 0.3 + tan * g, 0.07, HELL_EMBER, delay)
		elseif pick == 2 then
			bar(outer, c - tan * g, c + tan * g, 0.07, HELL_EMBER, delay)
		elseif pick == 3 then
			bar(outer, c, c + (rad + tan) * g, 0.07, HELL_EMBER, delay)
			bar(outer, c, c + (rad - tan) * g, 0.07, HELL_EMBER, delay)
		else
			bar(outer, c - rad * g * 1.4, c - rad * g * 0.4 - tan * g, 0.07, HELL_EMBER, delay)
		end
	end
	-- Pentagramm, Strich fuer Strich gezeichnet
	local pts = s.points or 5
	local vr = R * 0.64
	local base = math.atan2(-ctx.fwd.Z, -ctx.fwd.X) * (if s.at == "target" then 1 else -1)
	for i = 0, pts - 1 do
		local a1 = base + (i / pts) * TAU
		local a2 = base + (((i + 2) % pts) / pts) * TAU
		bar(star, Vector2.new(math.cos(a1), math.sin(a1)) * vr, Vector2.new(math.cos(a2), math.sin(a2)) * vr,
			0.16, col, draw * 0.25 + i * draw * 0.11, true)
	end
	for i = 1, 10 do
		local ang = (i / 10) * TAU
		local rad = Vector2.new(math.cos(ang), math.sin(ang))
		bar(inner, rad * R * 0.2, rad * R * 0.31, 0.09, HELL_EMBER, draw * 0.5 + i * 0.025)
	end

	-- 2. violetter Wulst (3D) + eigenes Siegel: Orbits, Klingen, Feuerringe
	local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, CFrame.new(center), 1)
	local wulst = hellRing(anchor, 0.05, 0.45 * sc + 0.1, 0.95 * sc + 0.2, HELL_VIOLET, 0.35, 0.12)
	local wulstR = R * 0.42
	local orbitAnchors: { BasePart } = {}
	local orbits: { HellRing } = {}
	local bladeAnchor: BasePart? = nil
	local blades: { { b: Beam, a1: Attachment, dir: Vector3, len: number, on: number, off: number } } = {}
	local discAnchor: BasePart? = nil
	local stack: { HellRing } = {}
	local skyRings: { HellRing } = {}
	if s.blades then
		for _, def in { { R * 0.68, Color3.fromRGB(255, 245, 240) }, { R * 0.8, Color3.fromRGB(120, 255, 150) } } do
			local oa = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, CFrame.new(center), 1)
			table.insert(orbitAnchors, oa)
			table.insert(orbits, hellRing(oa, def[1], 0, 0.14, def[2], 0.6, 0.05))
		end
		local ba = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, CFrame.new(center + Vector3.new(0, 0.8, 0)), 1)
		bladeAnchor = ba
		local a0 = Instance.new("Attachment")
		a0.Parent = ba
		local colors = { Color3.fromRGB(120, 255, 150), Color3.fromRGB(255, 170, 120), Color3.fromRGB(200, 160, 255),
			Color3.fromRGB(255, 190, 140), Color3.fromRGB(140, 255, 170), Color3.fromRGB(255, 140, 200) }
		local nB = math.min(s.blades or 6, #colors)
		for i = 1, nB do
			local yaw = (i / nB) * TAU + (math.random() - 0.5) * 0.5
			local up = math.rad(8 + math.random() * 24)
			local dir = Vector3.new(math.cos(yaw) * math.cos(up), math.sin(up), math.sin(yaw) * math.cos(up))
			local len = (s.bladeLen or 15) * sc
			local a1 = Instance.new("Attachment")
			a1.Position = dir * len
			a1.Parent = ba
			local b = Instance.new("Beam")
			b.Attachment0 = a0
			b.Attachment1 = a1
			b.FaceCamera = true
			b.Width0 = 0.25
			b.Width1 = 2.6 * sc
			b.LightEmission = 0.6
			b.LightInfluence = 0
			b.Color = ColorSequence.new(colors[i])
			b.Transparency = NumberSequence.new(1)
			b.Parent = ba
			table.insert(blades, { b = b, a1 = a1, dir = dir, len = len, on = 0.05 + 0.06 * i, off = (s.burstAt or 1) - 0.25 + 0.03 * i })
		end
	end
	if s.discs then
		local da = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, CFrame.new(center), 1)
		discAnchor = da
		-- Feuerringe unter dem schwebenden Teufel, Wirbelscheibe hoch ueber ihm
		for i, def in { { 1.8, 0.6 }, { 3.3, 0.46 }, { 4.8, 0.52 } } do
			table.insert(stack, hellRing(da, R * def[2], def[1] * sc + 0.3, 0.5 * sc + 0.15, if i == 2 then HELL_EMBER else col, 0.35, 0.05))
		end
		table.insert(skyRings, hellRing(da, R, 15.5 * sc + 1, 1.0 * sc + 0.25, col, 0.35, 0.05))
		table.insert(skyRings, hellRing(da, R * 0.55, 15.5 * sc + 1.05, 1.0 * sc + 0.2, HELL_EMBER, 0.4, 0.1))
	end

	-- 3. Sternbruch (nur eigenes Siegel)
	local rig: { RigPart } = {}
	local burstT = s.burstAt
	if burstT then
		for i = 1, 22 do
			local yaw = (i / 22) * TAU + (math.random() - 0.5) * 0.2
			local dir = Vector3.new(math.cos(yaw), -0.25 + math.random() * 0.75, math.sin(yaw)).Unit
			local perp = dir:Cross(Vector3.yAxis)
			perp = if perp.Magnitude > 0.05 then perp.Unit else Vector3.xAxis
			local frame = CFrame.fromMatrix(center + Vector3.new(0, 1.2 * sc + 0.2, 0) + dir * 0.4, perp, dir)
			addBlade(rig, frame, 0.12, (3 + math.random() * 4.5) * sc + 0.6, 0.32 * sc + 0.08,
				if i % 2 == 0 then Color3.fromRGB(255, 214, 180) else HELL_EMBER, Enum.Material.Neon, math.random() * 0.03)
		end
	end

	local pulsed, glowed, fading, imploded, burst = false, false, false, false, false
	local nextFlicker = 0
	runLoop("hellsigil", function(t)
		local tt = t - t0
		outer.Rotation = math.deg(t * spin)
		flames.Rotation = math.deg(t * spin)
		star.Rotation = -math.deg(t * spin * 0.6)
		inner.Rotation = math.deg(t * spin * 1.7)
		if tt > 0 and t >= nextFlicker and not fading then
			nextFlicker = t + 0.05
			for _, tg in tongues do
				tg.f.Size = UDim2.new(0, tg.len * PPS * (0.65 + math.random() * 0.6), 0, tg.f.Size.Y.Offset)
			end
		end
		if tt > 0 and not imploded then
			local wDraw = math.min(1, tt / (draw * 0.6))
			wulst.set(math.max(0.05, wulstR * easeOutBack(wDraw)), 0.45 * sc + 0.1 + math.sin(t * 5) * 0.06)
			anchor.CFrame = CFrame.new(center) * CFrame.Angles(0, t * 1.4, 0)
		end
		for i, oa in orbitAnchors do
			local tilt = if i == 1 then CFrame.Angles(0.24, 0, 0.08) else CFrame.Angles(-0.2, 0, 0.14)
			oa.CFrame = CFrame.new(center + Vector3.new(0, 0.9 + 0.35 * i, 0)) * tilt * CFrame.Angles(0, t * (if i == 1 then 7 else -8), 0)
			local a = math.clamp(tt / 0.15, 0, 1) * (if burstT then math.clamp((burstT - t) / 0.15, 0, 1) else 1)
			hellFade(orbits[i].beams, 0.05, a)
		end
		if bladeAnchor then
			bladeAnchor.CFrame = CFrame.new(center + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, t * 9.5, 0)
			for _, bl in blades do
				local a = math.clamp((t - bl.on) / 0.06, 0, 1) * math.clamp((bl.off - t) / 0.1, 0, 1)
				bl.b.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1 - 0.95 * a), NumberSequenceKeypoint.new(0.7, 1 - 0.55 * a), NumberSequenceKeypoint.new(1, 1) })
				bl.a1.Position = bl.dir * bl.len * (0.75 + 0.25 * math.sin(t * 13 + bl.on * 40))
			end
		end
		if discAnchor then
			discAnchor.CFrame = CFrame.new(center) * CFrame.Angles(0, -t * 2.6, 0)
			local a = math.clamp(t / 0.2, 0, 1)
			for _, ring in stack do
				hellFade(ring.beams, 0.05, a * (if burstT then math.clamp((burstT - t) / 0.15, 0, 1) else 1))
			end
			for _, ring in skyRings do
				hellFade(ring.beams, 0.05, a * math.clamp((dur - t) / 0.45, 0, 1))
			end
		end
		if burstT and not imploded and t >= burstT - 0.15 then
			imploded = true
			for _, l in layers do
				tween(l, 0.15, { Size = UDim2.fromScale(0.35, 0.35) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			end
			tween(disc, 0.15, { Size = Vector3.new(0.03, R * 0.8, R * 0.8) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
		if burstT and imploded and not burst then
			local k = math.clamp((t - burstT + 0.15) / 0.15, 0, 1)
			wulst.set(wulstR * (1 - 0.6 * k), 0.45 * sc + 0.1)
		end
		if burstT and not burst and t >= burstT then
			burst = true
			local c = newPart(Enum.PartType.Ball, Vector3.one * 0.5, Color3.fromRGB(255, 225, 235), CFrame.new(center + Vector3.new(0, 1.2 * sc + 0.2, 0)), 0.3)
			tween(c, 0.18, { Size = Vector3.one * R * 0.55, Transparency = 1 })
			Debris:AddItem(c, 0.3)
			burstAt(ctx, center + Vector3.new(0, 1.2, 0), 40, 22, HELL_EMBER)
			burstAt(ctx, center + Vector3.new(0, 0.6, 0), 16, 6, Color3.fromRGB(150, 140, 150), true)
			for _, b in wulst.beams do b.Color = ColorSequence.new(HELL_INDIGO) end
			for _, st in strokes do tween(st, 0.25, { Transparency = 1 }) end
			for _, f in fills do tween(f, 0.25, { BackgroundTransparency = 1 }) end
			tween(disc, 0.6, { Transparency = 1 })
		end
		if burstT and burst then
			local k = t - burstT
			wulst.set(lerpN(wulstR * 0.4, R * 0.62, easeOutCubic(math.min(1, k / 0.25))), 0.25, (0.6 * sc + 0.15) * (1 - 0.4 * math.min(1, k)))
			hellFade(wulst.beams, 0.1, math.clamp(1 - (k - 0.3) / 0.6, 0, 1))
			if #rig > 0 then
				rigApply(rig, CFrame.identity, function(rp)
					local x = k - rp.delay
					if x <= 0 then return 0 end
					return math.min(1.15, x / 0.06) * (1 - math.clamp((x - 0.07) / 0.12, 0, 1) * 0.6)
				end, math.clamp(1 - (k - 0.08) / 0.12, 0, 1))
			end
		end
		if s.glowAt and not glowed and t >= s.glowAt then
			glowed = true
			tween(gui, math.max(0.1, (s.pulseAt or s.glowAt + 0.5) - s.glowAt), { Brightness = 5.5 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
		if s.pulseAt and not pulsed and t >= s.pulseAt then
			pulsed = true
			gui.Brightness = 10
			tween(gui, 0.8, { Brightness = 3.5 })
			disc.Color = col
			tween(disc, 0.6, { Color = dark })
			for _, st in strokes do
				local th = st.Thickness
				st.Thickness = th * 2.4
				tween(st, 0.5, { Thickness = th })
			end
			for _, b in wulst.beams do b.Color = ColorSequence.new(HELL_EMBER) end
			task.delay(0.25, function()
				for _, b in wulst.beams do
					if b.Parent then b.Color = ColorSequence.new(HELL_VIOLET) end
				end
			end)
		end
		if not fading and t >= dur - 0.45 then
			fading = true
			for _, st in strokes do tween(st, 0.4, { Transparency = 1 }) end
			for _, f in fills do tween(f, 0.4, { BackgroundTransparency = 1 }) end
			tween(disc, 0.4, { Transparency = 1 })
		end
		if fading and not burst then
			hellFade(wulst.beams, 0.12, math.clamp((dur - t) / 0.4, 0, 1))
		end
		return t >= dur
	end, function()
		plate:Destroy()
		disc:Destroy()
		anchor:Destroy()
		for _, oa in orbitAnchors do oa:Destroy() end
		if bladeAnchor then bladeAnchor:Destroy() end
		if discAnchor then discAnchor:Destroy() end
		for _, rp in rig do rp.p:Destroy() end
	end)
end

-- hellwings: der Teufel SELBST (echter Klon, Original lokal unsichtbar, F03).
-- Holt aus, steigt mit Fluegelschlaegen und einer Drehung `height` Studs hoch
-- und waechst; reckt ab `raiseAt` den Dreizack (Teile mit "fork" im Namen)
-- ueber den Kopf, schwebt mit Fluegelschlag; ab `windAt` holt er Schwung
-- (steigt, lehnt zurueck, bebt), bei `throwAt` stoesst er den Dreizack nach
-- vorn (Wurf der Sonne, Schweif an der Spitze), faengt sich; ab `homeAt`
-- Rueckwaerts-Salto nach Hause (`back`). Fluegel: Teile mit "wingL"/"wingR"
-- im Namen schlagen um ihren Ansatz am Ruecken. Laeuft auch auf fremden
-- Modellen (ohne Fluegel/Dreizack: Spitze = ueber dem Kopf).
-- Setzt ctx.avatarCf, avatarScale, hellTip (Dreizackspitze).
--   height, crouch, rise, spins, grow, raiseAt, windAt, throwAt, homeAt, back
BLOCKS.hellwings = function(ctx, s)
	local source = ctx.selfModel
	if not source or not source.Parent then return end
	local clone = figureClone(source)
	if not clone then return end
	local H = ctx.selfSize.Y
	local up = Vector3.yAxis
	local fwd = ctx.fwd
	local home = CFrame.lookAt(ctx.selfFeet, ctx.selfFeet + fwd)
	local offset = home:ToObjectSpace(clone:GetPivot())
	local okScale, got = pcall(function() return clone:GetScale() end)
	local baseScale: number = if okScale and typeof(got) == "number" then got else 1
	local height = s.height or 6.5
	local crouch = s.crouch or 0.3
	local rise = s.rise or 0.7
	local spins = s.spins or 1
	local grow = s.grow or 1.25
	local raiseAt = s.raiseAt or 1.0
	local windAt = s.windAt or 2.85
	local throwAt = s.throwAt or 3.05
	local homeAt = s.homeAt or 4.4
	local back = s.back or 0.65
	local thrust = 0.2
	local total = homeAt + back
	local col = pickColor(s, ctx.fx)
	local hide = hideFigure(source)

	-- Koerper-Teil finden (Name "_body", sonst PrimaryPart, sonst das groesste Teil)
	local body: BasePart? = nil
	local biggest = -1
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			if d.Name:match("_body$") then body = d break end
			local v = d.Size.X * d.Size.Y * d.Size.Z
			if v > biggest then biggest = v; body = d end
		end
	end
	if clone.PrimaryPart and body and not body.Name:match("_body$") then body = clone.PrimaryPart end
	if not body then return end
	local bodyPart: BasePart = body

	-- Klon an seinen Platz, dann Ruhelagen der Teile relativ zum Koerper merken
	local lastScale = 1
	clone:PivotTo(home * offset)
	local wingsL: { BasePart } = {}
	local wingsR: { BasePart } = {}
	local forks: { BasePart } = {}
	local rest: { [BasePart]: CFrame } = {}
	for _, d in clone:GetDescendants() do
		if d:IsA("BasePart") then
			local n = d.Name
			local list = if n:find("wingL", 1, true) then wingsL elseif n:find("wingR", 1, true) then wingsR
				elseif n:find("fork", 1, true) then forks else nil
			if list then
				table.insert(list, d)
				rest[d] = bodyPart.CFrame:ToObjectSpace(d.CFrame)
			end
		end
	end
	-- Ansatzpunkte (Koerper-Raum, Scale 1; gemessen am Template Excl_Teufel)
	local pivL = Vector3.new(0.5, 0.8, 0.95)
	local pivR = Vector3.new(-0.5, 0.8, 0.95)
	local pivF = Vector3.new(1.8, 0.2, -0.19)
	local tipF = Vector3.new(1.8, 1.45, -0.19)
	if #forks > 0 then
		-- Spitze = oberstes Ende des hoechsten Zinken (falls das Modell anders ist)
		local best = -math.huge
		for _, p in forks do
			local top = rest[p].Position + Vector3.new(0, p.Size.Y / 2, 0)
			if top.Y > best then best = top.Y; tipF = top end
		end
		pivF = Vector3.new(tipF.X, tipF.Y - 1.25, tipF.Z)
	end

	local hl = Instance.new("Highlight")
	hl.Adornee = clone
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.FillColor = Color3.fromRGB(255, 238, 228)
	hl.FillTransparency = 0.88
	hl.OutlineColor = col
	hl.OutlineTransparency = 0.05
	hl.Parent = clone

	-- EIN Emitter (Glut) am Koerper, Schweif an der Dreizackspitze
	local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, home, 1)
	local embers = Instance.new("ParticleEmitter")
	embers.Texture = SPARK_TEX
	embers.Rate = 0
	embers.Speed = NumberRange.new(2, 7)
	embers.SpreadAngle = Vector2.new(180, 180)
	embers.Lifetime = NumberRange.new(0.4, 0.8)
	embers.Drag = 2
	embers.Acceleration = Vector3.new(0, 4, 0)
	embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	embers.Color = ColorSequence.new(HELL_EMBER, col)
	embers.LightEmission = 0.8
	embers.Parent = anchor
	local tipPart = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, home, 1)
	local ta0 = Instance.new("Attachment")
	ta0.Position = Vector3.new(0, 0.3, 0)
	ta0.Parent = tipPart
	local ta1 = Instance.new("Attachment")
	ta1.Position = Vector3.new(0, -0.3, 0)
	ta1.Parent = tipPart
	local trail = Instance.new("Trail")
	trail.Attachment0 = ta0
	trail.Attachment1 = ta1
	trail.Lifetime = 0.22
	trail.FaceCamera = true
	trail.LightEmission = 0.9
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 240, 220), col)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
	trail.Enabled = false
	trail.Parent = tipPart

	-- Pose setzen: Fuesse, Neigung (positiv = zuruecklehnen), Drehung, Groesse,
	-- Fluegelwinkel, Dreizack (kr = gereckt 0..1, kb = zurueck, kt = Stoss)
	local moveParts: { BasePart } = {}
	local moveCfs: { CFrame } = {}
	local function place(feet: CFrame, pitch: number, yaw: number, sc: number, wing: number, kr: number, kb: number, kt: number)
		if math.abs(sc - lastScale) > 0.008 then
			lastScale = sc
			pcall(function() clone:ScaleTo(baseScale * sc) end)
		end
		local half = H * sc * 0.5
		local pose = feet * CFrame.new(0, half, 0) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0) * CFrame.new(0, -half, 0)
		ctx.avatarCf = pose
		ctx.avatarScale = sc
		clone:PivotTo(pose * CFrame.new(offset.Position * sc) * offset.Rotation)
		local bc = bodyPart.CFrame
		anchor.CFrame = bc
		table.clear(moveParts)
		table.clear(moveCfs)
		local function rel(p: BasePart): CFrame
			local r = rest[p]
			return CFrame.new(r.Position * sc) * r.Rotation
		end
		for _, p in wingsL do
			table.insert(moveParts, p)
			table.insert(moveCfs, bc * CFrame.new(pivL * sc) * CFrame.Angles(0, 0, wing) * CFrame.new(-pivL * sc) * rel(p))
		end
		for _, p in wingsR do
			table.insert(moveParts, p)
			table.insert(moveCfs, bc * CFrame.new(pivR * sc) * CFrame.Angles(0, 0, -wing) * CFrame.new(-pivR * sc) * rel(p))
		end
		local fk = CFrame.new(pivF * sc) * CFrame.new(Vector3.new(-0.75 * kr, 1.25 * kr, -0.6 * kt) * sc)
			* CFrame.Angles(0.55 * kb - 1.15 * kt, 0, 0.35 * kr) * CFrame.new(-pivF * sc)
		for _, p in forks do
			table.insert(moveParts, p)
			table.insert(moveCfs, bc * fk * rel(p))
		end
		if #moveParts > 0 then
			workspace:BulkMoveTo(moveParts, moveCfs, Enum.BulkMoveMode.FireCFrameChanged)
		end
		local tip = if #forks > 0 then (bc * fk * CFrame.new(tipF * sc)).Position
			else bc.Position + up * (H * 0.75 * sc)
		ctx.hellTip = tip
		tipPart.CFrame = CFrame.lookAt(tip, tip + fwd)
	end

	-- feste Wegpunkte (alles aus t berechnet: Test-Halt `freezeAt` moeglich)
	local function hoverPos(t: number): Vector3
		local h = math.max(0, t - crouch - rise)
		return home.Position + up * (height + math.sin(h * 3) * 0.3)
	end
	local windStart = hoverPos(windAt)
	local windPos = windStart + up * 1.1 - fwd * 0.9
	local thrustEnd = windPos + fwd * 1.6 - up * 0.4
	local hover2 = home.Position + up * height + fwd * 0.6
	local homeStart = hover2 + up * (math.sin((homeAt - crouch - rise) * 3) * 0.3)
	local phase = 0
	local burstRise, burstThrow = false, false
	local freezeAt = s.freezeAt
	clone.Parent = folder()
	hide(1)
	place(home, 0, 0, 1, 0, 0, 0, 0)
	runLoop("hellwings", function(t, dt)
		if freezeAt then
			if t >= freezeAt + 150 then return true end
			t = math.min(t, freezeAt)
		end
		if t >= total or not clone.Parent then return true end
		local feet: CFrame
		local pitch, yaw, sc = 0, 0, grow
		local amp, freq = 0.55, 4.2
		local kr, kb, kt = 0, 0, 0
		if t < crouch then
			local e = math.sin((t / crouch) * math.pi * 0.5)
			feet, pitch, sc, amp, freq = home, 0.25 * e, 1 - 0.08 * e, 0.25, 2.5
		elseif t < crouch + rise then
			local k = (t - crouch) / rise
			local e = easeOutCubic(k)
			if not burstRise then
				burstRise = true
				embers:Emit(scaled(26, ctx.factor))
			end
			feet = home + up * (height * easeOutBack(k))
			pitch, yaw, sc, amp, freq = 0.25 * (1 - e), spins * TAU * e, lerpN(0.92, grow, e), 0.95, 7
		elseif t < windAt then
			feet = CFrame.lookAt(hoverPos(t), hoverPos(t) + fwd)
			local h = t - crouch - rise
			sc = grow * (1 + 0.02 * math.sin(h * 9))
			pitch = -0.04
			kr = math.clamp(easeOutBack(math.clamp((t - raiseAt) / 0.35, 0, 1)), 0, 1.15)
			embers.Rate = if extrasOn(ctx) then 10 * ctx.factor else 0
		elseif t < throwAt then
			local k = (t - windAt) / (throwAt - windAt)
			local e = easeOutCubic(k)
			local jit = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 0.12 * k
			local p = windStart:Lerp(windPos, e) + jit
			feet = CFrame.lookAt(p, p + fwd)
			pitch, kr, kb, amp, freq = 0.35 * e, 1, e, 0.9, 6
		elseif t < throwAt + thrust then
			local k = (t - throwAt) / thrust
			local e = easeOutCubic(k)
			if not burstThrow then
				burstThrow = true
				trail.Enabled = true
				embers:Emit(scaled(30, ctx.factor))
			end
			local p = windPos:Lerp(thrustEnd, e)
			feet = CFrame.lookAt(p, p + fwd)
			pitch, kr, kb, kt, amp, freq = lerpN(0.35, -0.45, e), 1, 1 - e, e, 1.0, 8
		elseif t < homeAt then
			local k = math.min(1, (t - throwAt - thrust) / 0.5)
			local e = easeInOutSine(k)
			trail.Enabled = k < 0.4
			local p = thrustEnd:Lerp(hover2, e) + up * (math.sin((t - crouch - rise) * 3) * 0.3 * e)
			feet = CFrame.lookAt(p, p + fwd)
			pitch, kr, kt = lerpN(-0.45, 0, e), 1 - 0.6 * e, 1 - e
			embers.Rate = 0
		else
			local k = (t - homeAt) / back
			local e = easeInOutSine(k)
			local p = homeStart:Lerp(home.Position, e) + up * (math.sin(math.pi * k) * 2)
			feet = CFrame.lookAt(p, p + fwd)
			pitch, sc, kr, amp, freq = TAU * e, lerpN(grow, 1, e), 0.4 * (1 - e), 0.3 * (1 - e), 3
		end
		phase += dt * freq * TAU
		local wing = amp * math.sin(phase) - 0.1
		place(feet, pitch, yaw, sc, wing, kr, kb, kt)
		return false
	end, function()
		hide(0)
		ctx.avatarCf = nil
		ctx.avatarScale = nil
		ctx.hellTip = nil
		clone:Destroy()
		embers.Rate = 0
		Debris:AddItem(anchor, 1)
		Debris:AddItem(tipPart, 0.4)
	end)
end

-- cursed: der GEGNER als Klon im Siegel gefangen (F03): zuckt bei der
-- Landung des Mals zusammen (Hopser, lehnt zurueck), Runenfesseln (Beam-
-- Kreise) steigen an ihm hoch und ziehen sich zu, er zittert immer staerker
-- und schaut ab `look` zur Sonne hoch; bei `hold` ist das Original zurueck
-- (= Einschlag), die Fesseln zerspringen in Funken.
--   hold, look, rings
BLOCKS.cursed = function(ctx, s)
	local source = ctx.targetModel
	if not source or not source.Parent then return end
	local clone = figureClone(source)
	if not clone then return end
	local H = ctx.targetSize.Y
	local W = math.max(ctx.targetSize.X, ctx.targetSize.Z) * 0.5
	local home = CFrame.lookAt(ctx.targetFeet, ctx.targetFeet - ctx.fwd)
	local offset = home:ToObjectSpace(clone:GetPivot())
	local hold = s.hold or 1.85
	local look = s.look or 0.7
	local col = pickColor(s, ctx.fx)
	local hide = hideFigure(source)
	local hl = Instance.new("Highlight")
	hl.Adornee = clone
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.FillColor = Color3.fromRGB(150, 20, 30)
	hl.FillTransparency = 0.86
	hl.OutlineColor = col
	hl.OutlineTransparency = 0.1
	hl.Parent = clone
	clone.Parent = folder()
	hide(1)
	local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, CFrame.new(ctx.targetFeet), 1)
	local rings: { HellRing } = {}
	for i = 1, (s.rings or 3) do
		table.insert(rings, hellRing(anchor, W * 1.5, 0, 0.24, if i % 2 == 0 then HELL_VIOLET else col, 0.45, 0.1))
		hellFade(rings[i].beams, 0.1, 0)
	end
	local freezeAt = s.freezeAt
	runLoop("cursed", function(t)
		if freezeAt then
			if t >= freezeAt + 150 then return true end
			t = math.min(t, freezeAt)
		end
		if t >= hold or not clone.Parent then return true end
		local flinch = if t < 0.25 then math.sin(t / 0.25 * math.pi) else 0
		local tension = math.clamp(t / hold, 0, 1)
		local jit = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * (0.03 + 0.14 * tension)
		local lookK = easeInOutSine(math.clamp((t - look) / 0.3, 0, 1))
		local pitch = 0.22 * flinch + 0.36 * lookK
		local feet = home + Vector3.new(0, 0.5 * flinch, 0) + jit
		local pose = feet * CFrame.new(0, H * 0.5, 0) * CFrame.Angles(pitch, math.sin(t * 23) * 0.05 * tension, 0) * CFrame.new(0, -H * 0.5, 0)
		clone:PivotTo(pose * offset)
		anchor.CFrame = CFrame.new(ctx.targetFeet) * CFrame.Angles(0, t * 3, 0)
		for i, r in rings do
			local k = math.clamp((t - 0.05 - i * 0.12) / 0.45, 0, 1)
			local e = easeOutCubic(k)
			r.set(W * lerpN(1.7, 1.05, e) * (1 + 0.05 * math.sin(t * 20 + i)), H * (0.1 + 0.27 * (i - 1)) * e + 0.15)
			hellFade(r.beams, 0.1, k)
		end
		return false
	end, function()
		hide(0)
		clone:Destroy()
		burstAt(ctx, ctx.targetFeet + Vector3.new(0, H * 0.4, 0), 24, 12, col)
		anchor:Destroy()
	end)
end

-- blacksun: schwarze Sonne. Erscheint schlagartig (Pop auf 125 %, federt
-- zurueck) ueber der Dreizackspitze (ctx.hellTip; sonst ueber dem Angreifer),
-- folgt ihr atmend und waechst; ab `windAt` holt sie mit dem Teufel Schwung
-- (gestreckt), bei `throwAt` fliegt sie in `fly` s im Bogen (Bezier mit
-- Anfangsschwung + Beschleunigung, in Flugrichtung gestreckt, Feuerschweif)
-- in den Kreis unter dem Gegner (ctx.hellCircle); dort gestaucht, versinkt in
-- `sink` s. Aufbau: schwarzer Kern (Kugel-Mesh, fuer Stauchen) mit rotem
-- Highlight-Rand, duenne Neon-Huelle (F05), gluehender Sternbruch vorn
-- (BillboardGui, zur Kamera), Akkretionsring (Beam-Kreise), Kranz aus
-- schwarzen Flammenzungen, zwei weisse Sichelboegen oben (Beams, zur Kamera),
-- Sog-Funken. `echo = true`: klein, `height` ueber dem Gegner, faellt sofort.
-- Setzt ctx.hellSun, ctx.hellSunPart.
--   size, lift, windAt, throwAt, fly, sink, arc, echo, height (Test: freezeAt)
BLOCKS.blacksun = function(ctx, s)
	local echo = s.echo == true
	local d = s.size or 5
	local r = d / 2
	local lift = s.lift or 0.4
	local windAt = s.windAt or 0.65
	local throwAt = s.throwAt or 0.85
	local fly = s.fly or 0.38
	local sink = s.sink or 0.14
	local arc = s.arc or 3
	local col = pickColor(s, ctx.fx)
	local up = Vector3.yAxis
	local H = ctx.selfSize.Y
	local hit = (ctx.hellCircle or ctx.targetFeet) + Vector3.new(0, 0.05, 0)
	local function tipPos(): Vector3
		if echo then return ctx.targetFeet + up * (s.height or 7) end
		return ctx.hellTip or (ctx.selfFeet + up * (H * 2.3))
	end
	local core = newPart(Enum.PartType.Block, Vector3.one * d, Color3.fromRGB(10, 0, 4), CFrame.new(tipPos()), 0)
	core.Material = Enum.Material.SmoothPlastic
	core.Name = "HellSunCore"
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.one * 0.01
	mesh.Parent = core
	local hl = Instance.new("Highlight")
	hl.Adornee = core
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.FillTransparency = 1
	hl.OutlineColor = Color3.fromRGB(255, 90, 40)
	hl.OutlineTransparency = 0
	hl.Parent = core
	local shell = newPart(Enum.PartType.Ball, Vector3.one * 0.1, col, CFrame.new(tipPos()), 0.9)
	ctx.hellSunPart = core
	-- gluehender Sternbruch vorn (zur Kamera, StudsOffset ist kamerabezogen)
	local bb = Instance.new("BillboardGui")
	bb.Adornee = core
	bb.LightInfluence = 0
	bb.Brightness = 2
	bb.AlwaysOnTop = false
	bb.Size = UDim2.fromScale(0.01, 0.01)
	bb.Parent = core
	local burst = Instance.new("Frame")
	burst.AnchorPoint = Vector2.new(0.5, 0.5)
	burst.Position = UDim2.fromScale(0.5, 0.5)
	burst.Size = UDim2.fromScale(1, 1)
	burst.BackgroundTransparency = 1
	burst.Parent = bb
	local function disk(scale: number, color: Color3, tr: number, stroke: number?)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.fromScale(scale, scale)
		f.BackgroundColor3 = color
		f.BackgroundTransparency = if stroke then 1 else tr
		f.BorderSizePixel = 0
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = f
		if stroke then
			local st = Instance.new("UIStroke")
			st.Color = color
			st.Thickness = stroke
			st.Transparency = tr
			st.Parent = f
		end
		f.Parent = burst
	end
	disk(0.62, col, 0.55)
	local nRays = if echo then 10 else 18
	for i = 1, nRays do
		local holder = Instance.new("Frame")
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(0.5, 0.5)
		holder.Size = UDim2.fromScale(0, 0)
		holder.BackgroundTransparency = 1
		holder.Rotation = (i / nRays) * 360 + math.random() * 10
		holder.Parent = burst
		local ray = Instance.new("Frame")
		ray.AnchorPoint = Vector2.new(0, 0.5)
		ray.Position = UDim2.fromScale(0, 0)
		local len = 0.3 + math.random() * 0.17
		ray.Size = UDim2.fromScale(len, 0.035 + math.random() * 0.04)
		ray.BackgroundColor3 = Color3.new(1, 1, 1)
		ray.BorderSizePixel = 0
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 250, 225)),
			ColorSequenceKeypoint.new(0.35, HELL_EMBER),
			ColorSequenceKeypoint.new(1, col),
		})
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.6, 0.15), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = ray
		ray.Parent = holder
	end
	-- Holder haben Groesse 0 -> Strahlen relativ zum Burst ueber Scale geht nicht; Offset je Bild setzen
	disk(0.26, Color3.fromRGB(255, 245, 215), 0.05)
	disk(0.98, Color3.fromRGB(255, 60, 40), 0.1, 3)
	-- Akkretionsring + Sicheln
	local accA = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, CFrame.new(tipPos()), 1)
	local acc1 = hellRing(accA, r * 1.35, 0, 0.6, HELL_EMBER, 0.45, 0.15)
	local acc2 = hellRing(accA, r * 1.62, 0, 0.22, col, 0.4, 0.2)
	local cresA = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, CFrame.new(tipPos()), 1)
	local crescents: { HellCres } = {}
	if not echo then
		for i, def in { { 1.18, 205, -25, 1.0 }, { 1.36, 235, 20, 0.55 } } do
			local atts: { Attachment } = {}
			for j = 1, 3 do
				local a = Instance.new("Attachment")
				a.Parent = cresA
				atts[j] = a
			end
			local bs: { Beam } = {}
			for j = 1, 2 do
				local b = Instance.new("Beam")
				b.Attachment0 = atts[j]
				b.Attachment1 = atts[j + 1]
				b.FaceCamera = true
				b.Segments = 16
				b.LightEmission = 0.6
				b.LightInfluence = 0
				b.Color = ColorSequence.new(Color3.fromRGB(255, 252, 248))
				b.Transparency = NumberSequence.new(1)
				b.Parent = cresA
				bs[j] = b
			end
			table.insert(crescents, { a = atts, b = bs, R = def[1], th0 = math.rad(def[2]), th1 = math.rad(def[3]), w = def[4] })
		end
	end
	-- Kranz schwarzer Flammenzungen um die untere Haelfte
	local rig: { RigPart } = {}
	if not echo then
		local nF = if extrasOn(ctx) then 12 else 7
		for i = 1, nF do
			local a = (i / nF) * TAU
			local radial = Vector3.new(math.cos(a), 0, math.sin(a))
			-- Zungen lecken unten aussen an der Kugel hoch (nicht vor den Kern)
			local dir = (radial * 1.1 + up * 0.55).Unit
			local perp = dir:Cross(radial).Unit
			local frame = CFrame.fromMatrix(radial * r * 0.72 - up * r * 0.72, perp, dir)
			local h = r * (0.55 + math.random() * 0.35)
			addBlade(rig, frame, 0.18, h, r * 0.2, VOID_OBSIDIAN, Enum.Material.SmoothPlastic, math.random() * 0.4)
			addBlade(rig, frame, 0.22, h * 0.75, r * 0.06, col, Enum.Material.Neon, math.random() * 0.4)
		end
	end
	-- Sog-Funken (EIN Emitter) und Feuerschweif fuer den Wurf
	local em = Instance.new("ParticleEmitter")
	em.Shape = Enum.ParticleEmitterShape.Sphere
	em.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	em.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	em.Texture = SPARK_TEX
	em.Rate = if echo then 0 else 60 * ctx.factor
	em.Speed = NumberRange.new(d * 1.6, d * 2.1)
	em.Lifetime = NumberRange.new(0.4, 0.5)
	em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.32), NumberSequenceKeypoint.new(1, 0.05) })
	em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(0.3, 0), NumberSequenceKeypoint.new(1, 0.3) })
	em.Color = ColorSequence.new(HELL_EMBER, col)
	em.LightEmission = 0.8
	em.Enabled = false
	em.Parent = accA
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0, 0)
	a0.Parent = core
	local tailPart = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, CFrame.new(tipPos()), 1)
	local a1 = Instance.new("Attachment")
	a1.Parent = tailPart
	local tail = Instance.new("Beam")
	tail.Attachment0 = a0
	tail.Attachment1 = a1
	tail.FaceCamera = true
	-- volle Flaeche statt Feuer-Textur: die Textur ist im Tageslicht zu schwach (F28)
	tail.Width0 = d * 0.8
	tail.Width1 = d * 0.15
	tail.LightEmission = 0.4
	tail.LightInfluence = 0
	tail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 120)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 90, 40)),
		ColorSequenceKeypoint.new(1, col),
	})
	tail.Transparency = NumberSequence.new(1)
	tail.Parent = core

	local function scaleAt(t: number): number
		if echo then return math.min(1, t / 0.06) end
		if t < 0.07 then return lerpN(0.05, 1.25, t / 0.07) end
		if t < 0.12 then return 1.25 end
		if t < 0.2 then return lerpN(1.25, 0.94, easeOutCubic((t - 0.12) / 0.08)) end
		if t < 0.3 then return lerpN(0.94, 1, easeInOutSine((t - 0.2) / 0.1)) end
		local k = math.clamp((t - 0.3) / math.max(0.1, windAt - 0.3), 0, 1)
		return lerpN(1, 1.12, k) * (1 + 0.03 * math.sin(t * 9))
	end
	local p0: Vector3? = nil
	local p1 = Vector3.zero
	local endT = throwAt + fly + sink
	local freezeAt = s.freezeAt
	local hitDone = false
	runLoop("blacksun", function(t)
		if freezeAt then
			if t >= freezeAt + 150 then return true end
			t = math.min(t, freezeAt)
		end
		if t >= endT then return true end
		local pos: Vector3
		local sz = scaleAt(math.min(t, windAt))
		local look = CFrame.identity
		local ms = Vector3.one
		local alpha = 1
		if t < throwAt then
			local k = math.clamp((t - windAt) / (throwAt - windAt), 0, 1)
			pos = tipPos() + up * (lift + r * sz)
			ms = Vector3.new(1 + 0.06 * k, 1 + 0.14 * k, 1 + 0.06 * k)
			em.Enabled = not echo and t > 0.15
		elseif t < throwAt + fly then
			local k = (t - throwAt) / fly
			if not p0 then
				local start = tipPos() + up * (lift + r * sz)
				p0 = start
				local flat = Vector3.new(hit.X - start.X, 0, hit.Z - start.Z)
				p1 = start + flat * 0.38 + up * arc
			end
			local u = 0.3 * k + 0.7 * k * k      -- Anfangsschwung + Beschleunigung
			local target = hit + up * (r * sz * 0.62)
			pos = bez2(p0 :: Vector3, p1, target, u)
			local du = 0.3 + 1.4 * k
			local vel = ((p1 - (p0 :: Vector3)) * (2 * (1 - u)) + (target - p1) * (2 * u)) * du
			if vel.Magnitude > 0.01 then look = CFrame.lookAt(Vector3.zero, vel).Rotation end
			ms = Vector3.new(0.9, 0.9, 1.2)
			em.Enabled = false
			local tailLen = math.clamp(vel.Magnitude * 0.22, d * 1.6, d * 4.5)
			tailPart.CFrame = CFrame.new(pos - (if vel.Magnitude > 0.01 then vel.Unit else up) * tailLen)
			tail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.25), NumberSequenceKeypoint.new(1, 1) })
		else
			local k = math.clamp((t - throwAt - fly) / sink, 0, 1)
			if not hitDone then
				hitDone = true
				tail.Transparency = NumberSequence.new(1)
				burstAt(ctx, hit + up * 0.5, 40, 20, HELL_EMBER)
			end
			local squash = math.min(1, k / 0.35)
			ms = Vector3.new(lerpN(0.9, 1.35, squash), lerpN(1.2, 0.6, squash), lerpN(0.9, 1.35, squash)) * (1 - 0.8 * math.max(0, (k - 0.35) / 0.65))
			pos = hit + up * (r * sz * 0.62 * (1 - k))
			alpha = 1 - math.max(0, (k - 0.5) / 0.5)
		end
		ctx.hellSun = pos
		local dd = d * sz
		core.CFrame = CFrame.new(pos) * look
		mesh.Scale = ms * sz
		shell.Size = Vector3.one * dd * 1.06
		shell.CFrame = CFrame.new(pos)
		shell.Transparency = 1 - 0.1 * alpha
		hl.OutlineTransparency = 1 - alpha
		local avg = (ms.X + ms.Y + ms.Z) / 3
		bb.Size = UDim2.fromScale(dd * 0.92 * avg, dd * 0.92 * avg)
		bb.StudsOffset = Vector3.new(0, 0, dd * 0.52)
		burst.Rotation = t * 40
		for _, h in burst:GetChildren() do
			if h:IsA("Frame") and h.Size.X.Scale == 0 then
				local ray = h:FindFirstChildOfClass("Frame")
				if ray then
					-- Halter ist 0 gross: Strahl-Laenge in Pixeln aus der Billboard-Groesse
					local px = burst.AbsoluteSize.X
					ray.Size = UDim2.fromOffset(px * (ray:GetAttribute("L") or 0.4) * (1 + 0.08 * math.sin(t * 17 + h.Rotation)), px * 0.04)
				end
			end
		end
		bb.Enabled = alpha > 0.05
		accA.CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(20), 0, math.rad(6)) * CFrame.Angles(0, t * 2.2, 0)
		acc1.set(r * sz * 1.35, 0, 0.6 * sz)
		acc2.set(r * sz * 1.62, 0, 0.22 * sz)
		local accA2 = alpha * (if t >= throwAt then 0.4 else 1)
		hellFade(acc1.beams, 0.15, accA2)
		hellFade(acc2.beams, 0.2, accA2)
		-- Sicheln in der Bildebene der Kamera
		local cam = workspace.CurrentCamera
		if cam and #crescents > 0 then
			local cr, cu = cam.CFrame.RightVector, cam.CFrame.UpVector
			cresA.CFrame = CFrame.new(pos)
			local ca = math.clamp((t - 0.12) / 0.12, 0, 1) * math.clamp((throwAt + 0.08 - t) / 0.12, 0, 1)
			for _, c in crescents do
				local R = r * sz * c.R
				local dth = (c.th1 - c.th0) / 2
				local dir = if dth < 0 then -1 else 1
				for j = 1, 3 do
					local th = c.th0 + dth * (j - 1) + math.sin(t * 2) * 0.05
					local radial = cr * math.cos(th) + cu * math.sin(th)
					local tangent = (cr * -math.sin(th) + cu * math.cos(th)) * dir
					c.a[j].WorldCFrame = CFrame.fromMatrix(pos + radial * R, tangent, radial)
				end
				local cs = 4 / 3 * math.tan(math.abs(dth) / 4) * R
				for j, b in c.b do
					b.CurveSize0 = cs
					b.CurveSize1 = cs
					b.Width0 = (if j == 1 then 0.15 else 1) * c.w * sz
					b.Width1 = (if j == 2 then 0.15 else 1) * c.w * sz
					b.Transparency = NumberSequence.new(1 - 0.95 * ca)
				end
			end
		end
		if #rig > 0 then
			local fa = math.clamp((t - 0.2) / 0.15, 0, 1) * (if t < throwAt then 1 else math.max(0, 1 - (t - throwAt) / 0.15))
			rigApply(rig, CFrame.new(pos) * CFrame.Angles(0, t * 0.8, 0), function(rp)
				return sz * (0.8 + 0.25 * math.sin(t * 14 + rp.delay * 30))
			end, fa)
		end
		return false
	end, function()
		if ctx.hellSunPart == core then ctx.hellSunPart = nil end
		ctx.hellSun = nil
		core:Destroy()
		shell:Destroy()
		accA:Destroy()
		cresA:Destroy()
		tailPart:Destroy()
		for _, rp in rig do rp.p:Destroy() end
	end)
	-- Strahl-Laengen merken (fuer die Pixel-Laenge je Bild)
	for _, h in burst:GetChildren() do
		local ray = h:FindFirstChildOfClass("Frame")
		if h:IsA("Frame") and ray and h.Size.X.Scale == 0 then
			ray:SetAttribute("L", ray.Size.X.Scale)
		end
	end
end

-- impactframe: Anime-Impact-Frame (nur Besitzer). Je Zeichen in `pattern`
-- ein Bild von `hold` s: "d" dunkel (Welt schwarz-rot, Figuren und Sonne als
-- rote Silhouetten mit weissem Umriss), "l" hell (Welt fast weiss, Figuren und
-- Sonne schwarz); dazu Speedlines aus der Bildmitte (weiss bzw. schwarz).
-- Eigener ColorCorrection `SkillFX_Impact`, danach weg - beruehrt `sky` und
-- `hitstop` nicht (F02). Silhouetten: Modelle im Effekt-Ordner (Klone) und
-- ctx.hellSunPart; sichtbare Originale nur, wenn kein Klon sie vertritt.
--   pattern, hold, lines
BLOCKS.impactframe = function(ctx, s)
	if not ctx.isOwner then return end
	local pattern = s.pattern or "dld"
	local hold = s.hold or 0.05
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "SkillFX_Impact"
	cc.Parent = Lighting
	local hls: { Highlight } = {}
	local function addHl(a: Instance)
		if #hls >= 8 then return end
		local h = Instance.new("Highlight")
		h.Adornee = a
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Parent = folder()
		table.insert(hls, h)
	end
	for _, c in folder():GetChildren() do
		if c:IsA("Model") then addHl(c) end
	end
	for _, m in { ctx.selfModel, ctx.targetModel } do
		if m and m.Parent then
			local p = m:FindFirstChildWhichIsA("BasePart", true)
			if p and p.LocalTransparencyModifier < 0.5 then addHl(m) end
		end
	end
	local sunHl: Highlight? = nil
	if ctx.hellSunPart and ctx.hellSunPart.Parent and #hls < 8 then
		addHl(ctx.hellSunPart)
		sunHl = hls[#hls]
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "SkillFXImpact"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 48
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	local cam = workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	local diag = vp.Magnitude * 0.5
	local lines: { Frame } = {}
	for _ = 1, (s.lines or 48) do
		local holder = Instance.new("Frame")
		holder.AnchorPoint = Vector2.new(0.5, 0.5)
		holder.Position = UDim2.fromScale(0.5, 0.5)
		holder.Size = UDim2.fromScale(0, 0)
		holder.BackgroundTransparency = 1
		holder.Rotation = math.random() * 360
		holder.Parent = gui
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0, 0.5)
		f.Position = UDim2.fromOffset(diag * (0.28 + math.random() * 0.22), 0)
		f.Size = UDim2.fromOffset(diag * (0.4 + math.random() * 0.6), 2 + math.random() * 6)
		f.BorderSizePixel = 0
		f.BackgroundColor3 = Color3.new(1, 1, 1)
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, 0.05), NumberSequenceKeypoint.new(1, 0) })
		g.Parent = f
		f.Parent = holder
		table.insert(lines, f)
	end
	-- 26.10. (Himmelsgericht): Palette waehlbar - `dark` (Tint der dunklen Bilder),
	-- `light` (Tint der hellen), `fill` (Silhouetten im dunklen Bild); Standard = Hoellensiegel-Rot.
	local darkTint: Color3 = if typeof(s.dark) == "Color3" then s.dark else Color3.fromRGB(255, 55, 55)
	local lightTint: Color3 = if typeof(s.light) == "Color3" then s.light else Color3.new(1, 1, 1)
	local darkFill: Color3 = if typeof(s.fill) == "Color3" then s.fill else Color3.fromRGB(170, 0, 12)
	local function look(kind: string)
		local darkK = kind == "d"
		cc.Saturation = -1
		cc.Contrast = 1
		cc.Brightness = if darkK then -0.28 else 0.95
		cc.TintColor = if darkK then darkTint else lightTint
		for _, h in hls do
			h.FillColor = if darkK then darkFill else Color3.new(0, 0, 0)
			h.FillTransparency = 0
			h.OutlineColor = if darkK then Color3.new(1, 1, 1) else Color3.new(0, 0, 0)
			h.OutlineTransparency = 0
		end
		for _, f in lines do
			f.BackgroundColor3 = if darkK then Color3.new(1, 1, 1) else Color3.new(0, 0, 0)
		end
		-- im dunklen Bild bleibt die Sonne selbst sichtbar (Glutkern auf Schwarz-Rot)
		if sunHl then
			sunHl.FillTransparency = if darkK then 1 else 0
			sunHl.OutlineTransparency = if darkK then 1 else 0
		end
	end
	local idx = 0
	runLoop("impactframe", function(t)
		local i = math.floor(t / hold) + 1
		if i > #pattern then return true end
		if i ~= idx then
			idx = i
			look(pattern:sub(i, i))
		end
		return false
	end, function()
		cc:Destroy()
		for _, h in hls do h:Destroy() end
		gui:Destroy()
	end)
end

-- hellfire: der Einschlag im Siegel (Mitte = ctx.hellCircle, sonst `at`):
-- eine Feuersaeule bricht heraus (4 Beams mit Feuer-Textur, die nach oben
-- laufen, Neon-Kern, Glut-Huelle), wird bei `widenAt` breiter; weisse
-- Windhiebe (Beam-Sicheln) fegen um den Gegner, Funkelsterne blitzen auf;
-- ab `crownAt` waechst die Kronen-Schockwelle (Schleierwand aus Neon-Paneelen,
-- seitlich - aus Sicht der Kamera beim Start - zwei hohe Zacken, vorn niedrig,
-- F44); bei `fanAt` schlaegt ein pinker Flammenfaecher hoch; am Ende Rauch.
-- `small = true`: Echo (nur Saeule, 2 Hiebe, wenige Funken).
--   at, height, radius, dur, widenAt, crownAt, crownR, fanAt, slashes, stars, small
BLOCKS.hellfire = function(ctx, s)
	local small = s.small == true
	local center = if s.at ~= "self" and ctx.hellCircle then ctx.hellCircle else groundAt(ctx, s.at or "target")
	local Hp = s.height or (if small then 14 else 32)
	local r = s.radius or (if small then 1.3 else 2.2)
	local dur = s.dur or (if small then 0.38 else 2.0)
	local widenAt = s.widenAt or (if small then 99 else 1.0)
	local crownAt = s.crownAt or 0.15
	local fanAt = s.fanAt or 1.15
	local col = pickColor(s, ctx.fx)
	local up = Vector3.yAxis
	local Ht = ctx.targetSize.Y
	local cam = workspace.CurrentCamera
	local camPos = if cam then cam.CFrame.Position else center - ctx.fwd * 20
	local toCam = Vector3.new(camPos.X - center.X, 0, camPos.Z - center.Z)
	toCam = if toCam.Magnitude > 0.1 then toCam.Unit else -ctx.fwd
	local side = toCam:Cross(up).Unit
	-- 1. Saeule
	local pa = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, CFrame.new(center), 1)
	-- Flammenstreifen: volle Beams (tragen im Tageslicht, F28), jeder 4. mit
	-- Feuer-Textur als Struktur, jeder 4. dunkel (Kontrast wie im Vorbild);
	-- je Streifen eigene Hoehe und Breite, sie flackern.
	local cols: { { a1: Attachment, b: Beam, w: number, hf: number, ph: number, dark: boolean } } = {}
	local nCol = if small then 4 else 9
	for i = 1, nCol do
		local ang = (i / nCol) * TAU + math.random() * 0.5
		local off = Vector3.new(math.cos(ang), 0, math.sin(ang)) * r * (0.15 + math.random() * 0.35)
		local a0 = Instance.new("Attachment")
		a0.Position = off
		a0.Parent = pa
		local a1 = Instance.new("Attachment")
		a1.Position = off + up * 0.2
		a1.Parent = pa
		local b = Instance.new("Beam")
		b.Attachment0 = a0
		b.Attachment1 = a1
		b.FaceCamera = true
		b.Segments = 10
		local kind = i % 4
		local dark = kind == 0
		if kind == 1 then
			b.Texture = FIRE_TEX
			b.TextureMode = Enum.TextureMode.Wrap
			b.TextureLength = 5
			b.TextureSpeed = -2
		end
		b.LightEmission = if dark then 0 else 0.35   -- satt im Tageslicht (F35)
		b.LightInfluence = 0
		b.Color = if dark then ColorSequence.new(Color3.fromRGB(120, 12, 10), Color3.fromRGB(60, 4, 6)) else ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 248, 215)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 200, 90)),
			ColorSequenceKeypoint.new(0.6, Color3.fromRGB(255, 110, 40)),
			ColorSequenceKeypoint.new(1, col),
		})
		b.Transparency = NumberSequence.new(1)
		b.Parent = pa
		local w = r * (if dark then 0.5 else 0.8 + math.random() * 0.6)
		b.Width0 = w
		b.Width1 = w * 0.6
		table.insert(cols, { a1 = a1, b = b, w = w, hf = 0.6 + math.random() * 0.4, ph = math.random() * 10, dark = dark })
	end
	local coreP = newPart(Enum.PartType.Cylinder, Vector3.new(0.2, r * 0.9, r * 0.9), Color3.fromRGB(255, 190, 110),
		CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), 1)
	local hull = newPart(Enum.PartType.Cylinder, Vector3.new(0.2, r * 2.2, r * 2.2), col,
		CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), 1)
	local glow = newPart(Enum.PartType.Cylinder, Vector3.new(0.04, 0.2, 0.2), col,
		CFrame.new(center + up * 0.05) * CFrame.Angles(0, 0, math.rad(90)), 0.45)
	tween(glow, 0.2, { Size = Vector3.new(0.04, r * (if small then 3 else 5), r * (if small then 3 else 5)) }, Enum.EasingStyle.Quart)
	tweenLater(glow, dur - 0.4, 0.4, { Transparency = 1 })
	-- 2. Windhiebe
	local slashes: { HellSlash } = {}
	local nS = s.slashes or (if small then 2 else 4)
	for i = 1, nS do
		local a = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, CFrame.new(center), 1)
		local rad = (if small then 2.6 else 4.5) + i * (if small then 0.6 else 1.4)
		local ring = hellRing(a, rad, 0, (if small then 0.6 else 1.1), Color3.fromRGB(255, 252, 250), 0.6, 0.05, 2)
		hellFade(ring.beams, 0.05, 0)
		local tilt = CFrame.Angles((math.random() - 0.5) * 0.7, math.random() * TAU, (math.random() - 0.5) * 0.5)
		table.insert(slashes, { a = a, ring = ring, tilt = tilt, rad = rad, t0 = (i - 1) * 0.06, spd = if i % 2 == 0 then 5 else -4.5 })
	end
	-- 3. Funkelsterne (Zeitplan)
	local pal = { Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 160, 70), Color3.fromRGB(200, 120, 255), Color3.fromRGB(255, 220, 160), Color3.fromRGB(140, 150, 255) }
	local stars: { { t: number, p: Vector3, size: number, c: Color3 } } = {}
	local nSt = if small then 4 else scaled(s.stars or 18, ctx.factor)
	for i = 1, nSt do
		local p = center + side * ((math.random() - 0.5) * 10) + toCam * (1 + math.random() * 3) + up * (1.5 + math.random() * (if small then 6 else 12))
		table.insert(stars, { t = 0.05 + (i - 1) * (if small then 0.04 else 0.055), p = p, size = 1.4 + math.random() * 1.6, c = pal[(i - 1) % #pal + 1] })
	end
	local nextStar = 1
	-- 4. Kronen-Schockwelle
	local panels: { BasePart } = {}
	local edges: { BasePart } = {}
	local heights: { number } = {}
	local nP = if small then 0 elseif extrasOn(ctx) then 30 else 20
	for i = 1, nP do
		local th = (i / nP) * TAU
		local radial = math.cos(th) * side + math.sin(th) * toCam
		-- hohe Zacken links/rechts (side), vorn/hinten niedrig, kleine Wellen
		local h = 2.4 + 4.2 * math.abs(radial:Dot(side)) ^ 3 + 0.35 * math.sin(6 * th)
		heights[i] = h
		local p = newPart(Enum.PartType.Block, Vector3.new(1, 1, 0.12), Color3.fromRGB(255, 238, 244), PARK, 1)
		local e = newPart(Enum.PartType.Block, Vector3.new(1, 0.16, 0.16), Color3.fromRGB(255, 255, 255), PARK, 1)
		table.insert(panels, p)
		table.insert(edges, e)
	end
	local cR0 = s.crownR0 or 3
	local cR1 = s.crownR or 9.5
	-- 5. Flammenfaecher
	local fa = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, CFrame.new(center + up * 1.2), 1)
	local fans: { { a1: Attachment, b: Beam, dir: Vector3, len: number } } = {}
	if not small then
		local fa0 = Instance.new("Attachment")
		fa0.Parent = fa
		local nF = if extrasOn(ctx) then 11 else 7
		for i = 1, nF do
			local phi = math.rad(-78 + 156 * (i - 1) / (nF - 1)) + (math.random() - 0.5) * 0.08
			local dir = up * math.cos(phi) + side * math.sin(phi) - toCam * 0.25
			local a1 = Instance.new("Attachment")
			a1.Position = dir * 0.1
			a1.Parent = fa
			local b = Instance.new("Beam")
			b.Attachment0 = fa0
			b.Attachment1 = a1
			b.FaceCamera = true
			b.Segments = 8
			b.Width0 = 0.8
			b.Width1 = 4.2
			b.LightEmission = 0.3
			b.LightInfluence = 0
			b.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 150, 200)),
				ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 70, 160)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 20, 100)),
			})
			b.Transparency = NumberSequence.new(1)
			b.Parent = fa
			table.insert(fans, { a1 = a1, b = b, dir = dir.Unit, len = (12 + math.random() * 6) * (1 - 0.3 * math.abs(math.sin(phi))) })
		end
	end
	burstAt(ctx, center + up * 1, 50, 24, HELL_EMBER)
	local smoked = false
	local freezeAt = s.freezeAt
	runLoop("hellfire", function(t)
		if freezeAt then
			if t >= freezeAt + 150 then return true end
			t = math.min(t, freezeAt)
		end
		if t >= dur then return true end
		local out = math.clamp((dur - t) / (if small then 0.15 else 0.5), 0, 1)
		-- Saeule
		local hk = easeOutCubic(math.min(1, t / (if small then 0.08 else 0.14)))
		local wk = 1 + 0.6 * easeOutCubic(math.clamp((t - widenAt) / 0.25, 0, 1))
		local top = math.max(0.3, Hp * hk)
		pa.CFrame = CFrame.new(center) * CFrame.Angles(0, t * 0.8, 0)
		for _, c in cols do
			local fl = 1 + 0.22 * math.sin(t * 19 + c.ph) + 0.12 * math.sin(t * 31 + c.ph * 2)
			c.a1.Position = Vector3.new(c.a1.Position.X, math.max(0.3, top * c.hf * (0.92 + 0.08 * fl)), c.a1.Position.Z)
			c.b.Width0 = c.w * wk * fl
			c.b.Width1 = c.w * 0.6 * wk * (2 - fl)
			local o = if c.dark then 0.55 * out else 0.95 * out
			c.b.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1 - o), NumberSequenceKeypoint.new(0.55, 1 - o * 0.85), NumberSequenceKeypoint.new(1, 1),
			})
		end
		coreP.Size = Vector3.new(top, r * 0.4 * wk, r * 0.4 * wk)
		coreP.CFrame = CFrame.new(center + up * (top / 2)) * CFrame.Angles(0, 0, math.rad(90))
		coreP.Transparency = 1 - 0.3 * out
		hull.Size = Vector3.new(top * 0.85, r * 2.2 * wk, r * 2.2 * wk)
		hull.CFrame = CFrame.new(center + up * (top * 0.85 / 2)) * CFrame.Angles(0, 0, math.rad(90))
		hull.Transparency = 1 - 0.1 * out
		-- Hiebe
		for _, sl in slashes do
			local x = t - sl.t0
			local k = math.clamp(x / 0.7, 0, 1)
			local a = if x <= 0 then 0 else math.min(1, x / 0.06) * (1 - k)
			sl.a.CFrame = CFrame.new(center + up * (Ht * 0.6)) * sl.tilt * CFrame.Angles(0, x * sl.spd, 0)
			sl.ring.set(sl.rad * lerpN(0.7, 1.2, easeOutCubic(k)), 0)
			hellFade(sl.ring.beams, 0.05, a)
		end
		-- Funkelsterne
		while nextStar <= #stars and t >= stars[nextStar].t do
			local st = stars[nextStar]
			twinkle(st.p, st.size, st.c, 0.3)
			nextStar += 1
		end
		-- Krone
		if nP > 0 then
			local k = math.clamp((t - crownAt) / 1.0, 0, 1)
			local R = lerpN(cR0, cR1, easeOutCubic(k))
			local g = lerpN(0.15, 1, easeOutBack(math.min(1, k * 1.6)))
			local a = math.clamp((t - crownAt) / 0.08, 0, 1) * math.clamp((1 - k) / 0.3, 0, 1)
			local w = 2 * R * math.sin(math.pi / nP)   -- Sehne: keine Ueberlappung (sonst helle Naehte)
			local cfs: { CFrame } = table.create(nP * 2)
			local all: { BasePart } = table.create(nP * 2)
			for i = 1, nP do
				local th = (i / nP) * TAU
				local radial = math.cos(th) * side + math.sin(th) * toCam
				local tangent = radial:Cross(up)
				local h = heights[i] * g
				local base = center + radial * R
				panels[i].Size = Vector3.new(w, h, 0.12)
				edges[i].Size = Vector3.new(w, 0.16, 0.16)
				cfs[i] = CFrame.fromMatrix(base + up * (h / 2), tangent, up)
				cfs[nP + i] = CFrame.fromMatrix(base + up * h, tangent, up)
				all[i] = panels[i]
				all[nP + i] = edges[i]
				panels[i].Transparency = 1 - 0.3 * a
				edges[i].Transparency = 1 - 0.7 * a
			end
			workspace:BulkMoveTo(all, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end
		-- Faecher
		if #fans > 0 then
			local k = t - fanAt
			local gk = if k <= 0 then 0 else easeOutBack(math.min(1, k / 0.14))
			local a = if k <= 0 then 0 else math.clamp(1 - (k - 0.2) / 0.45, 0, 1)
			for _, f in fans do
				f.a1.Position = f.dir * math.max(0.1, f.len * gk * (1 + 0.15 * math.min(1, math.max(0, k) / 0.6)))
				f.b.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1 - 0.95 * a), NumberSequenceKeypoint.new(0.6, 1 - 0.75 * a), NumberSequenceKeypoint.new(1, 1) })
			end
		end
		if not smoked and t >= dur - 0.6 then
			smoked = true
			burstAt(ctx, center + up * 2, 18, 5, Color3.fromRGB(170, 150, 155), true)
			burstAt(ctx, center + up * 5, 14, 4, Color3.fromRGB(150, 135, 140), true)
		end
		return false
	end, function()
		pa:Destroy()
		coreP:Destroy()
		hull:Destroy()
		fa:Destroy()
		Debris:AddItem(glow, 0.5)
		for _, sl in slashes do sl.a:Destroy() end
		for i = 1, #panels do panels[i]:Destroy(); edges[i]:Destroy() end
	end)
end

--------------------------------------------------------------------------------
-- 25.10.2026 Pulsar-Nova (PulsarNova, Pulsar-Baerchi). Neue, bessere Fassung
-- des Blender-Prototyps "Pulsstoss" vom 22.10.: ein Lichtpunkt zeichnet einen
-- Ring um den Baerchi, er steigt mit dem Jetpack auf und dreht sich immer
-- schneller - Visier und Jetpack werfen zwei Lichtkegel wie ein Leuchtturm,
-- jeder Durchgang durch die Kamera blitzt. Dann kollabiert er zum
-- Neutronenstern und schlaegt als Komet ein: Impact-Frames, Feuerkuppel,
-- Weissblende. Doku in SkillFXConfig ("BAUSTEINE", Pulsar-Nova).
--------------------------------------------------------------------------------

local PULSAR_WHITE = Color3.fromRGB(232, 252, 255)
local NOVA_HOT     = Color3.fromRGB(255, 247, 224)   -- weissgluehend
local NOVA_YELLOW  = Color3.fromRGB(255, 204, 82)
local NOVA_RED     = Color3.fromRGB(230, 72, 38)
local NOVA_HOLE    = Color3.fromRGB(118, 20, 36)     -- dunkle Loecher in der Kuppel
local NOVA_PINK    = Color3.fromRGB(255, 92, 172)    -- Saum (Umriss) wie im Vorbild
local NOVA_ASH     = Color3.fromRGB(44, 30, 36)
local NOVA_INK     = Color3.fromRGB(28, 10, 34)      -- Silhouetten im invertierten Bild
local NOVA_PAPER   = Color3.fromRGB(255, 232, 246)   -- rosa-weisser Grund im invertierten Bild

type NovaRing = {
	anchor: BasePart,
	place: (CFrame, number, number) -> (),
	alpha: (number, number?) -> (),
	pattern: (number, { { number } }) -> (),
	destroy: () -> (),
}
type NovaVeil = { set: (Color3, number) -> (), destroy: () -> () }
type NovaTongue = { a0: Attachment, a1: Attachment, beam: Beam, th: number, seed: number }
type NovaFlames = {
	anchor: BasePart,
	place: (Vector3, number, number, number, number) -> (),
	destroy: () -> (),
}
type JetFlame = { p: BasePart, rel: CFrame, size: Vector3, axis: number, dir: Vector3,
	mat: Enum.Material, col: Color3, hot: boolean }
type PulsarJet = { set: (number, number, number) -> (), visor: () -> Vector3, pack: () -> Vector3 }
type SparkPill = { p: BasePart, v: Vector3, life: number, len: number }
type NovaBand = { ring: NovaRing, beta: number, w: number, spin: number, ph: number, tilt: CFrame }
type NovaHole = { p: BasePart, dir: Vector3, w: number, h: number, roll: number }

-- Deterministisches Flackern (0..1) aus zwei Zahlen: gleiche Eingabe = gleiches
-- Bild, deshalb auch in eingefrorenen Test-Buehnen stabil (freezeAt).
local function novaHash(a: number, b: number): number
	local x = math.sin(a * 127.1 + b * 311.7) * 43758.5453
	return x - math.floor(x)
end

-- quadratische Bezier-Kurve (Flugbahn des Neutronensterns)
local function novaBez(p0: Vector3, p1: Vector3, p2: Vector3, u: number): Vector3
	return p0 * ((1 - u) * (1 - u)) + p1 * (2 * u * (1 - u)) + p2 * (u * u)
end

-- Transparenz-Verlauf eines Flammenband-Viertels mit Luecken (gerissene
-- Flammenstreifen wie im Vorbild). Zeiten steigen streng, Ende genau 1.
local function novaGaps(rng: Random, tr: number): { { number } }
	local kps: { { number } } = { { 0, tr } }
	local x = rng:NextNumber(0.08, 0.3)
	while x < 0.82 and #kps < 16 do
		local g = rng:NextNumber(0.05, 0.12)
		table.insert(kps, { x, tr })
		table.insert(kps, { x + 0.025, 1 })
		table.insert(kps, { x + g, 1 })
		table.insert(kps, { x + g + 0.025, tr })
		x += g + rng:NextNumber(0.22, 0.42)
	end
	table.insert(kps, { 1, tr })
	return kps
end

-- Kreis aus 4 Bezier-Beams (Viertel, FaceCamera) an EINEM Anker - Trick aus
-- `worldglobe` (F31/F40): glatt, billig, von allen Seiten sichtbar. Der Kreis
-- liegt in der lokalen XZ-Ebene des Ankers (Normale = lokales Y), Start bei
-- lokal +X, gezeichnet Richtung lokal +Z. place(cf, Radius, Breite);
-- alpha(a, p): Sichtbarkeit 0..1 und gezeichneter Anteil p (0..1, rundherum);
-- pattern(i, kps): eigener Transparenz-Verlauf fuer Viertel i (Luecken);
-- color2 (optional): Farbverlauf color -> color2 je Viertel.
local function novaRing(color: Color3, emission: number, tr: number, segments: number?, color2: Color3?): NovaRing
	local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, color, PARK, 1)
	anchor.Name = "NovaRing"
	local atts: { Attachment } = {}
	local beams: { Beam } = {}
	for i = 1, 4 do
		local a = Instance.new("Attachment")
		a.Parent = anchor
		atts[i] = a
	end
	for i = 1, 4 do
		local b = Instance.new("Beam")
		b.Attachment0 = atts[i]
		b.Attachment1 = atts[i % 4 + 1]
		b.FaceCamera = true
		b.Segments = segments or 12
		b.LightEmission = emission
		b.LightInfluence = 0
		b.Color = if color2 then ColorSequence.new(color, color2) else ColorSequence.new(color)
		b.Transparency = NumberSequence.new(1)
		b.Parent = anchor
		beams[i] = b
	end
	local pats: { [number]: { { number } } } = {}
	local lastR, lastW, lastA, lastP = -1, -1, -1, -1
	local ring: NovaRing = {
		anchor = anchor,
		place = function(cf: CFrame, r: number, w: number)
			anchor.CFrame = cf
			if math.abs(r - lastR) > 0.004 or math.abs(w - lastW) > 0.004 then
				lastR, lastW = r, w
				local rr = math.max(0.02, r)
				for i, a in atts do
					local th = (i - 1) * math.pi / 2
					local dir = Vector3.new(math.cos(th), 0, math.sin(th))
					local tan = Vector3.new(-math.sin(th), 0, math.cos(th))
					a.CFrame = CFrame.fromMatrix(dir * rr, tan, dir)
				end
				local cs = 0.5523 * rr
				for _, b in beams do
					b.CurveSize0 = cs
					b.CurveSize1 = cs
					b.Width0 = w
					b.Width1 = w
				end
			end
		end,
		alpha = function(a: number, p: number?)
			local pp = math.clamp(p or 1, 0, 1)
			if math.abs(a - lastA) < 0.008 and math.abs(pp - lastP) < 0.003 then return end
			lastA, lastP = a, pp
			for i, b in beams do
				local kps = pats[i]
				local q = math.clamp(pp * 4 - (i - 1), 0, 1)
				if a <= 0.01 or q <= 0.01 then
					b.Transparency = NumberSequence.new(1)
				elseif kps then
					local list: { NumberSequenceKeypoint } = {}
					for _, k in kps do
						table.insert(list, NumberSequenceKeypoint.new(k[1], 1 - (1 - k[2]) * a))
					end
					b.Transparency = NumberSequence.new(list)
				else
					local v = 1 - (1 - tr) * a
					if q >= 0.99 then
						b.Transparency = NumberSequence.new(v)
					else
						-- harte Kante an der Zeichenspitze
						b.Transparency = NumberSequence.new({
							NumberSequenceKeypoint.new(0, v),
							NumberSequenceKeypoint.new(math.max(0.002, q - 0.01), v),
							NumberSequenceKeypoint.new(q, 1),
							NumberSequenceKeypoint.new(1, 1),
						})
					end
				end
			end
		end,
		pattern = function(i: number, kps: { { number } })
			pats[i] = kps
			lastA = -1
		end,
		destroy = function()
			anchor:Destroy()
		end,
	}
	return ring
end

-- Bildschirm-Schleier nur fuer den Besitzer (eigene ScreenGui ueber dem Spiel,
-- unter dem Impact-Frame): Leuchtturm-Blitz, Puls der Kuppel, Weissblende.
-- Eigener Schleier statt `flash`, weil hier Farbe UND Deckkraft je Bild laufen.
local function novaVeil(ctx: Ctx): NovaVeil?
	if not ctx.isOwner then return nil end
	local gui = Instance.new("ScreenGui")
	gui.Name = "SkillFXNovaVeil"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 49
	gui.ResetOnSpawn = false
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	f.BackgroundTransparency = 1
	f.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	local lastV = -1
	return {
		set = function(c: Color3, a: number)
			local v = 1 - math.clamp(a, 0, 1)
			if math.abs(v - lastV) > 0.004 or f.BackgroundColor3 ~= c then
				lastV = v
				f.BackgroundColor3 = c
				f.BackgroundTransparency = v
			end
		end,
		destroy = function()
			gui:Destroy()
		end,
	}
end

-- Flammenzungen als Beams (FaceCamera, unten breit, oben spitz): von jeder
-- Seite eine Flamme, ein Anker fuer alle. place(center, r, h, t, a): Kranz um
-- `center` mit Radius r, Hoehe h (flackert in 2-Bild-Schritten wie im Anime),
-- a = Sichtbarkeit 0..1.
local function novaFlames(n: number, width: number, seed: number): NovaFlames
	local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, NOVA_YELLOW, PARK, 1)
	anchor.Name = "NovaFlames"
	local rng = Random.new(seed)
	local list: { NovaTongue } = {}
	for j = 1, n do
		local a0 = Instance.new("Attachment")
		a0.Parent = anchor
		local a1 = Instance.new("Attachment")
		a1.Parent = anchor
		local b = Instance.new("Beam")
		b.Attachment0 = a0
		b.Attachment1 = a1
		b.FaceCamera = true
		b.Segments = 6
		b.Width0 = width * rng:NextNumber(0.75, 1.2)
		b.Width1 = width * 0.12
		b.LightEmission = 0.3
		b.LightInfluence = 0
		b.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, NOVA_HOT),
			ColorSequenceKeypoint.new(0.4, NOVA_YELLOW),
			ColorSequenceKeypoint.new(1, NOVA_RED),
		})
		b.Transparency = NumberSequence.new(1)
		b.Parent = anchor
		table.insert(list, { a0 = a0, a1 = a1, beam = b,
			th = (j - 0.5) / n * TAU + rng:NextNumber(-0.12, 0.12), seed = rng:NextNumber(0, 100) })
	end
	local lastA = -1
	return {
		anchor = anchor,
		place = function(center: Vector3, r: number, h: number, t: number, a: number)
			anchor.CFrame = CFrame.new(center)
			local step = math.floor(t * 15)
			for j, tg in list do
				local radial = Vector3.new(math.cos(tg.th), 0, math.sin(tg.th))
				local fl = 0.55 + 0.6 * novaHash(tg.seed, step)
				tg.a0.Position = radial * r
				tg.a1.Position = radial * (r * 1.06 + 0.25) + Vector3.new(0, h * fl, 0)
				tg.beam.CurveSize0 = 0.5 * math.sin(t * 17 + j)
			end
			if math.abs(a - lastA) > 0.01 then
				lastA = a
				local seq = if a <= 0.01 then NumberSequence.new(1) else NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1 - 0.92 * a),
					NumberSequenceKeypoint.new(0.7, 1 - 0.55 * a),
					NumberSequenceKeypoint.new(1, 1),
				})
				for _, tg in list do tg.beam.Transparency = seq end
			end
		end,
		destroy = function()
			anchor:Destroy()
		end,
	}
end

-- Jetpack und Visier eines Modells (Teile "acc_flame", "acc_nozzle",
-- "acc_visor", "acc_jetpack", Bezug "..._body"). set(power, visor, t): die
-- Duesenflammen wachsen mit `power` (0 = Original) und flackern, Neon nur
-- solange sie brennen (F17); `visor` 0..1 laesst das Visier leuchten, ueber 1
-- blitzt es weiss. Nach jedem PivotTo aufrufen (Groesse ueber scaleOf, Teil-
-- groessen absolut aus Start x Scale x Faktor). visor()/pack() = Weltlage von
-- Visier bzw. Jetpack (Quellen der Lichtkegel). Ohne "_body": nil.
local function pulsarJet(model: Model, scaleOf: () -> number, col: Color3): PulsarJet?
	local body: BasePart? = nil
	local visorP: BasePart? = nil
	local packP: BasePart? = nil
	local flameParts: { BasePart } = {}
	local nozzles: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local n = string.lower(d.Name)
			if string.find(n, "_body", 1, true) then
				body = d
			elseif string.find(n, "acc_flame", 1, true) then
				table.insert(flameParts, d)
			elseif string.find(n, "acc_nozzle", 1, true) then
				table.insert(nozzles, d)
			elseif string.find(n, "acc_visor", 1, true) then
				visorP = d
			elseif string.find(n, "acc_jetpack", 1, true) then
				packP = d
			end
		end
	end
	if not body then return nil end
	local b = body :: BasePart
	local bcf = b.CFrame
	local flames: { JetFlame } = {}
	for _, fp in flameParts do
		local rel = bcf:ToObjectSpace(fp.CFrame)
		-- Spitzen-Richtung: von der naechsten Duese zur Flamme (sonst nach unten)
		local dir = Vector3.new(0, -1, 0)
		local best = math.huge
		for _, nz in nozzles do
			local v = rel.Position - bcf:PointToObjectSpace(nz.Position)
			if v.Magnitude < best and v.Magnitude > 0.01 then
				best = v.Magnitude
				dir = v.Unit
			end
		end
		-- Laengsachse = die lokale Achse der Flamme, die am besten zur Spitze passt
		local axes = { rel.RightVector, rel.UpVector, rel.LookVector }
		local axis, bestDot = 2, -1
		for i, ax in axes do
			local dd = math.abs(ax:Dot(dir))
			if dd > bestDot then
				bestDot = dd
				axis = i
			end
		end
		table.insert(flames, { p = fp, rel = rel, size = fp.Size, axis = axis, dir = dir,
			mat = fp.Material, col = fp.Color, hot = false })
	end
	local vRel: CFrame? = if visorP then bcf:ToObjectSpace(visorP.CFrame) else nil
	local vMat = if visorP then visorP.Material else Enum.Material.Plastic
	local vCol = if visorP then visorP.Color else col
	local vHot = false
	local pRel: CFrame = if packP then bcf:ToObjectSpace(packP.CFrame) else CFrame.new(0, 0, 1)
	local function lenOf(sz: Vector3, axis: number): number
		return if axis == 1 then sz.X elseif axis == 3 then sz.Z else sz.Y
	end
	local function along(sz: Vector3, axis: number, len: number, thick: number): Vector3
		if axis == 1 then return Vector3.new(len, sz.Y * thick, sz.Z * thick) end
		if axis == 3 then return Vector3.new(sz.X * thick, sz.Y * thick, len) end
		return Vector3.new(sz.X * thick, len, sz.Z * thick)
	end
	return {
		set = function(power: number, visor: number, t: number)
			local sc = scaleOf()
			local bc = b.CFrame
			for i, fl in flames do
				if power <= 0.01 then
					if fl.hot then
						fl.hot = false
						fl.p.Material = fl.mat
						fl.p.Color = fl.col
					end
					fl.p.Size = fl.size * sc
					fl.p.CFrame = bc * CFrame.new(fl.rel.Position * sc) * fl.rel.Rotation
				else
					if not fl.hot then
						fl.hot = true
						fl.p.Material = Enum.Material.Neon
					end
					local flick = 1 + 0.22 * math.sin(t * 46 + i * 2.1) + 0.12 * math.sin(t * 91 + i * 0.7)
					local len0 = lenOf(fl.size, fl.axis) * sc
					local len = len0 * (1 + power * 2.4 * flick)
					fl.p.Size = along(fl.size * sc, fl.axis, len, 1 + 0.35 * power)
					local top = fl.rel.Position * sc - fl.dir * (len0 * 0.5)
					fl.p.CFrame = bc * CFrame.new(top + fl.dir * (len * 0.5)) * fl.rel.Rotation
					fl.p.Color = col:Lerp(PULSAR_WHITE, math.clamp(0.25 + 0.3 * flick * power, 0, 1))
				end
			end
			local vp = visorP
			if vp then
				if visor > 0.02 then
					if not vHot then
						vHot = true
						vp.Material = Enum.Material.Neon
					end
					vp.Color = col:Lerp(PULSAR_WHITE, 0.1 + 0.9 * math.clamp(visor - 1, 0, 1))
				elseif vHot then
					vHot = false
					vp.Material = vMat
					vp.Color = vCol
				end
			end
		end,
		visor = function(): Vector3
			local sc = scaleOf()
			local vr = vRel
			if vr then
				return (b.CFrame * CFrame.new(vr.Position * sc)).Position
			end
			return (b.CFrame * CFrame.new(0, 0.5 * sc, -1.0 * sc)).Position
		end,
		pack = function(): Vector3
			return (b.CFrame * CFrame.new(pRel.Position * scaleOf())).Position
		end,
	}
end

-- pulsar: der Pulsar-Baerchi SELBST (echter Klon, Original lokal unsichtbar,
-- F03). Bodenblitz, ein Lichtpunkt zeichnet in `draw` s einen Ring (Radius
-- `ring`, 12 Tick-Striche) um ihn; er duckt sich (`crouchAt`), das Jetpack
-- zuendet, er steigt mit Drehung auf (`height`, `spins`, `grow`) - der Ring
-- hebt mit ab und wird sein Orbit-Ring. Ab `beamAt` Leuchtturm: Lichtkegel
-- aus Visier (vorn) und Jetpack (hinten), Laenge `beamLen`, zur Hoehe der
-- Kamera geneigt; er dreht sich immer schneller, so dass der Visier-Kegel
-- genau zu den Zeiten in `ticks` durch die Kamera DIESES Clients fegt
-- (Richtung beim Start fest, F22) - jeder Durchgang blitzt groesser (Besitzer:
-- Bildschirm-Schleier). Bei `collapseAt` stuerzen Kegel und Ring in ihn: er
-- wird zum weissgluehenden Neutronenstern (Anime-Sternbruch: flackernde
-- Zacken, Funken im Bogen), pulst bei jedem `pulseAt`, holt ab `windAt`
-- Schwung und schiesst bei `launchAt` in `fly` s als Komet in den Gegner
-- (Landung = Einschlag; Schweif, Nachbilder). Ab `emergeAt` rollt er sich aus
-- dem Krater auf, Rueckwaerts-Salto heim (`back`), Landung, der Ring blitzt
-- noch einmal um seine Fuesse (`settle`). Setzt avatarCf, pulsarHover,
-- pulsarCam (Kamera "pulsar"). Laeuft auch ohne Jetpack (fremde Modelle).
--   ring, draw, crouchAt, crouch, rise, height, spins, grow, beamAt, beamLen,
--   ticks, collapseAt, pulseAt, windAt, launchAt, fly, emergeAt, emerge,
--   back, settle (Test: freezeAt, trailLife)
BLOCKS.pulsar = function(ctx, s)
	local source = ctx.selfModel
	if not source or not source.Parent then return end
	local clone = figureClone(source)
	if not clone then return end
	local H = ctx.selfSize.Y
	local home = CFrame.lookAt(ctx.selfFeet, ctx.selfFeet + ctx.fwd)
	local offset = home:ToObjectSpace(clone:GetPivot())
	local okScale, got = pcall(function() return clone:GetScale() end)
	local baseScale: number = if okScale and typeof(got) == "number" then got else 1
	local col = ctx.fx.color
	local col2 = ctx.fx.color2
	local f = ctx.factor
	local rich = extrasOn(ctx)
	local ringR = s.ring or 3.6
	local draw = math.max(0.1, s.draw or 0.35)
	local crouchAt = s.crouchAt or 0.38
	local crouch = math.max(0.05, s.crouch or 0.24)
	local rise = math.max(0.2, s.rise or 0.48)
	local height = s.height or 5.5
	local spins = s.spins or 1
	local grow = s.grow or 1.15
	local beamAt = s.beamAt or 1.05
	local beamLen = s.beamLen or 34
	local ticks: { number } = s.ticks or { 1.2, 1.48, 1.7, 1.86, 2.01 }
	local collapseAt = s.collapseAt or 2.05
	local pulseAt: { number } = s.pulseAt or { 2.15, 2.3 }
	local windAt = s.windAt or 2.33
	local launchAt = math.max(collapseAt + 0.1, s.launchAt or 2.45)
	local fly = math.max(0.1, s.fly or 0.43)
	local emergeAt = s.emergeAt or 4.42
	local emerge = math.max(0.05, s.emerge or 0.16)
	local back = math.max(0.2, s.back or 0.72)
	local settle = math.max(0.1, s.settle or 0.35)
	local freezeAt: number? = s.freezeAt
	local trailLife = s.trailLife or 0.16
	local riseAt = crouchAt + crouch
	local hangAt = riseAt + rise
	local landAt = launchAt + fly
	local backAt = emergeAt + emerge
	local homeAt = backAt + back
	local total = homeAt + settle
	local hide = hideFigure(source)
	local hideClone = hideFigure(clone)
	local rng = Random.new(41)

	-- Schwebepunkt und Kamera-Seite (waagerecht + Hoehenwinkel) zur Kamera
	-- DIESES Clients, einmal beim Start (F22): danach richten sich der Tick-
	-- Fahrplan, die Neigung der Kegel und die Kamerafahrt.
	local hoverFeet = ctx.selfFeet + ctx.fwd * 1.2 + Vector3.new(0, height, 0)
	local hoverC = hoverFeet + Vector3.new(0, H * grow * 0.5, 0)
	local camDir = sideOf(ctx)
	local camPitch = 0.12
	local cam = workspace.CurrentCamera
	if cam then
		local v = cam.CFrame.Position - hoverC
		local flat = Vector3.new(v.X, 0, v.Z)
		if flat.Magnitude > 1 then
			camDir = flat.Unit
			camPitch = math.clamp(math.atan2(v.Y, flat.Magnitude), -0.35, 0.45)
		end
	end
	ctx.pulsarHover = hoverC
	ctx.pulsarCam = camDir
	local camN = if cam then cam.CFrame.Position - hoverC else camDir
	camN = if camN.Magnitude > 0.1 then camN.Unit else camDir
	local upP = Vector3.yAxis - camN * Vector3.yAxis:Dot(camN)
	upP = if upP.Magnitude > 0.1 then upP.Unit else perpOf(camN)
	local rgtP = upP:Cross(camN).Unit

	-- Gier-Fahrplan: nach dem Aufstieg blickt er zum Gegner (spins * TAU); der
	-- Visier-Kegel zeigt zur Kamera, wenn yaw = yawCam (mod TAU). Zwischen den
	-- Ticks je eine volle Drehung - die Abstaende werden kuerzer, er dreht
	-- immer schneller.
	local lc = CFrame.lookAt(Vector3.zero, ctx.fwd):VectorToObjectSpace(camDir)
	local yawCam = math.atan2(-lc.X, -lc.Z)
	local yaw0 = spins * TAU
	local tickYaw: { number } = {}
	do
		local y = yawCam
		while y < yaw0 + math.pi * 0.6 do y += TAU end
		for i = 1, #ticks do
			tickYaw[i] = y + (i - 1) * TAU
		end
	end
	local function yawAt(t: number): number
		if t <= hangAt or #ticks == 0 then return yaw0 end
		local t1 = ticks[1]
		if t < t1 then
			local k = (t - hangAt) / math.max(0.05, t1 - hangAt)
			return yaw0 + (tickYaw[1] - yaw0) * k * k
		end
		for i = 1, #ticks - 1 do
			if t < ticks[i + 1] then
				local k = (t - ticks[i]) / math.max(0.02, ticks[i + 1] - ticks[i])
				return tickYaw[i] + TAU * k
			end
		end
		local n = #ticks
		local lastDt = if n >= 2 then math.max(0.02, ticks[n] - ticks[n - 1]) else 0.2
		return tickYaw[n] + TAU * (t - ticks[n]) / lastDt
	end

	-- Klon: warmes Weiss + cyan Umriss, damit er vor jedem Himmel klar bleibt (F37)
	local hl = Instance.new("Highlight")
	hl.Adornee = clone
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.FillColor = Color3.fromRGB(255, 252, 240)
	hl.FillTransparency = 0.88
	hl.OutlineColor = col
	hl.OutlineTransparency = 0.1
	hl.Parent = clone

	-- Funken und Staub (EIN Anker an der Koerpermitte)
	local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, home, 1)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARK_TEX
	sparks.Rate = 0
	sparks.Speed = NumberRange.new(5, 12)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Lifetime = NumberRange.new(0.3, 0.7)
	sparks.Drag = 2
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.34), NumberSequenceKeypoint.new(1, 0) })
	sparks.Color = ColorSequence.new(PULSAR_WHITE, col)
	sparks.LightEmission = 0.6
	sparks.Parent = anchor
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = SMOKE_TEX
	dust.Rate = 0
	dust.Speed = NumberRange.new(3, 8)
	dust.SpreadAngle = Vector2.new(180, 20)
	dust.Lifetime = NumberRange.new(0.5, 0.9)
	dust.Drag = 3
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, H * 0.3), NumberSequenceKeypoint.new(1, H * 0.8) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	dust.Color = ColorSequence.new(PULSAR_WHITE, col)
	dust.LightEmission = 0.2
	dust.Rotation = NumberRange.new(0, 360)
	dust.Parent = anchor

	-- Ring am Boden: Lichtpunkt zeichnet ihn (Start auf der Kamera-Seite),
	-- 12 Tick-Striche wie ein Zifferblatt ("tickt wie eine Uhr")
	local startAng = math.atan2(-camDir.Z, camDir.X)
	local groundC = ctx.selfFeet + Vector3.new(0, 0.12, 0)
	local ringFrame0 = CFrame.new(groundC) * CFrame.Angles(0, startAng, 0)
	local ring = novaRing(col, 0.4, 0.12, 14)
	local tickParts: { BasePart } = {}
	for j = 0, 11 do
		local th = j / 12 * TAU
		local radial = ringFrame0:VectorToWorldSpace(Vector3.new(math.cos(th), 0, math.sin(th)))
		local pos = groundC + radial * (ringR + 0.5) - Vector3.new(0, 0.06, 0)
		local p = newPart(Enum.PartType.Block, Vector3.new(0.62, 0.08, 0.26), PULSAR_WHITE,
			CFrame.fromMatrix(pos, radial, Vector3.yAxis), 1)
		p.Name = "PulsarTick"
		tickParts[j + 1] = p
	end
	local head = newPart(Enum.PartType.Ball, Vector3.one * 0.55, PULSAR_WHITE, PARK, 1)
	head.Name = "PulsarHead"
	local flashDisc = newPart(Enum.PartType.Cylinder, Vector3.new(0.06, ringR * 0.8, ringR * 0.8),
		col:Lerp(PULSAR_WHITE, 0.5), CFrame.new(ctx.selfFeet + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)), 0.3)
	flashDisc.Name = "PulsarFlash"
	tween(flashDisc, 0.24, { Size = Vector3.new(0.06, ringR * 2.7, ringR * 2.7), Transparency = 1 })
	Debris:AddItem(flashDisc, 0.3)

	-- Lichtkegel: Kern (weiss -> cyan) + breiter Schein, je vorn und hinten
	local beamAnchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, PARK, 1)
	beamAnchor.Name = "PulsarBeams"
	local function mkAtt(): Attachment
		local a = Instance.new("Attachment")
		a.Parent = beamAnchor
		return a
	end
	local vA0, vA1, jA0, jA1 = mkAtt(), mkAtt(), mkAtt(), mkAtt()
	local function mkBeam(a0: Attachment, a1: Attachment, w0: number, w1: number, c0: Color3, c1: Color3,
		tr0: number, emission: number): Beam
		local bm = Instance.new("Beam")
		bm.Attachment0 = a0
		bm.Attachment1 = a1
		bm.FaceCamera = true
		bm.Segments = 12
		bm.Width0 = w0
		bm.Width1 = w1
		bm.LightEmission = emission
		bm.LightInfluence = 0
		bm.Color = ColorSequence.new(c0, c1)
		bm.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, tr0),
			NumberSequenceKeypoint.new(0.45, tr0 + (1 - tr0) * 0.45),
			NumberSequenceKeypoint.new(1, 1),
		})
		bm.Enabled = false
		bm.Parent = beamAnchor
		return bm
	end
	local beams: { Beam } = {
		mkBeam(vA0, vA1, 0.35, 2.6, PULSAR_WHITE, col, 0.05, 0.5),
		mkBeam(vA0, vA1, 1.2, 8.0, col, col, 0.55, 0.35),
		mkBeam(jA0, jA1, 0.4, 2.8, PULSAR_WHITE, col, 0.08, 0.5),
		mkBeam(jA0, jA1, 1.3, 8.5, col, col, 0.6, 0.35),
	}
	local beamsOn = false

	-- Leuchtturm-Blitz an der Quelle, die gerade zur Kamera zeigt
	local glowTex = texOf(ctx, "glow")
	local flareP = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, PARK, 1)
	flareP.Name = "PulsarFlare"
	local flareGui: BillboardGui? = nil
	local flareImg: ImageLabel? = nil
	local flareBall: BasePart? = nil
	if glowTex then
		local g = Instance.new("BillboardGui")
		g.Size = UDim2.fromScale(2, 2)
		g.LightInfluence = 0
		g.Brightness = 2
		g.Adornee = flareP
		g.Parent = flareP
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Image = glowTex
		img.ImageColor3 = col:Lerp(PULSAR_WHITE, 0.45)
		img.ImageTransparency = 1
		img.Size = UDim2.fromScale(1, 1)
		img.Parent = g
		flareGui, flareImg = g, img
	end
	-- Neon-Kern zusaetzlich zum Bild: das Schein-Bild allein verschwindet vor
	-- hellem Himmel (Test 25.10.); sichtbar nur nahe der Kamera-Richtung
	local ball = newPart(Enum.PartType.Ball, Vector3.one, col:Lerp(PULSAR_WHITE, 0.6), PARK, 1)
	ball.Name = "PulsarFlareBall"
	flareBall = ball
	local veil = novaVeil(ctx)

	-- Neutronenstern: Kern, Kraftfeld-Huelle, Schein, Schweif (an der Huelle,
	-- die sich nicht dreht)
	local orbCore = newPart(Enum.PartType.Ball, Vector3.one * 1.5, PULSAR_WHITE, PARK, 1)
	orbCore.Name = "PulsarOrb"
	local orbShell = newPart(Enum.PartType.Ball, Vector3.one * 2.8, col, PARK, 1)
	orbShell.Material = Enum.Material.ForceField
	orbShell.Name = "PulsarOrbShell"
	local orbTex = texOf(ctx, "orb")
	local orbGui: BillboardGui? = nil
	local orbImg: ImageLabel? = nil
	if orbTex then
		local g = Instance.new("BillboardGui")
		g.Size = UDim2.fromScale(6, 6)
		g.LightInfluence = 0
		g.Brightness = 1.6
		g.Adornee = orbShell
		g.Parent = orbShell
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.Image = orbTex
		img.ImageColor3 = col
		img.ImageTransparency = 1
		img.Size = UDim2.fromScale(1, 1)
		img.Parent = g
		orbGui, orbImg = g, img
	end
	local ta0 = Instance.new("Attachment")
	ta0.Position = Vector3.new(0, 0.7, 0)
	ta0.Parent = orbShell
	local ta1 = Instance.new("Attachment")
	ta1.Position = Vector3.new(0, -0.7, 0)
	ta1.Parent = orbShell
	local trail = Instance.new("Trail")
	trail.Attachment0 = ta0
	trail.Attachment1 = ta1
	trail.Lifetime = 0.2
	trail.MinLength = 0.05
	trail.FaceCamera = true
	trail.LightEmission = 0.5
	trail.LightInfluence = 0
	trail.Color = ColorSequence.new(PULSAR_WHITE, col2)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.15) })
	local tailTex = texOf(ctx, "tail")
	if tailTex then
		trail.Texture = tailTex
		trail.TextureMode = Enum.TextureMode.Stretch
	end
	trail.Enabled = false
	trail.Parent = orbShell

	-- Sternbruch: zwei Zacken-Saetze (Klingen in der Ebene zur Kamera), im
	-- Wechsel sichtbar (2-Bild-Schritte wie im Anime), dazu Funken-Pillen
	local starRig: { RigPart } = {}
	local starSet: { [RigPart]: number } = {}
	local starBlade: { [RigPart]: number } = {}
	local nSpk = if rich then 12 else 8
	local bladeNo = 0
	for set = 1, 2 do
		for j = 1, nSpk do
			bladeNo += 1
			local a = (j - 1 + (set - 1) * 0.5 + rng:NextNumber(-0.25, 0.25)) / nSpk * TAU
			local d = upP * math.cos(a) + rgtP * math.sin(a)
			local frame = CFrame.fromMatrix(Vector3.zero, camN, d)
			local hgt = rng:NextNumber(1.6, 3.6) * (if set == 1 then 1 else 0.8)
			local before = #starRig
			addBlade(starRig, frame, 0.08, hgt, rng:NextNumber(0.13, 0.21),
				if set == 1 then PULSAR_WHITE else col, Enum.Material.Neon, 0)
			for k = before + 1, #starRig do
				starSet[starRig[k]] = set
				starBlade[starRig[k]] = bladeNo
			end
		end
	end
	local pills: { SparkPill } = {}
	for _ = 1, (if rich then 16 else 9) do
		local a = rng:NextNumber(0, TAU)
		local dirP = (upP * math.cos(a) + rgtP * math.sin(a) + camN * rng:NextNumber(-0.35, 0.35)).Unit
		local p = newPart(Enum.PartType.Block, Vector3.new(0.26, 0.26, 1.0), PULSAR_WHITE, PARK, 1)
		p.Name = "PulsarSpark"
		table.insert(pills, { p = p, v = dirP * rng:NextNumber(11, 22) + Vector3.new(0, 4, 0),
			life = rng:NextNumber(0.32, 0.58), len = rng:NextNumber(0.8, 1.5) })
	end
	local pulseRings: { NovaRing } = {}
	for _ = 1, #pulseAt do
		table.insert(pulseRings, novaRing(col:Lerp(PULSAR_WHITE, 0.3), 0.5, 0.05, 14))
	end

	local lastScale = 1
	-- Pose: Fuesse `feet`, gedreht um die Koerpermitte (wie `ascend`)
	local function place(feet: CFrame, pitch: number, yaw: number, roll: number, sc: number)
		if math.abs(sc - lastScale) > 0.008 then
			lastScale = sc
			pcall(function() clone:ScaleTo(baseScale * sc) end)
		end
		local half = H * sc * 0.5
		local pose = feet * CFrame.new(0, half, 0) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll) * CFrame.new(0, -half, 0)
		ctx.avatarCf = pose
		ctx.avatarScale = sc
		clone:PivotTo(pose * CFrame.new(offset.Position * sc) * offset.Rotation)
		anchor.CFrame = pose * CFrame.new(0, half, 0)
	end
	local function face(pos: Vector3): CFrame
		return CFrame.lookAt(pos, pos + ctx.fwd)
	end
	place(home, 0, 0, 0, 1)
	clone.Parent = folder()
	hide(1)
	-- ohne Jetpack (fremdes Modell): Quellen der Kegel vorn/hinten am Koerper
	local jet: PulsarJet = pulsarJet(clone, function() return lastScale end, col) or {
		set = function(_p: number, _v: number, _t: number) end,
		visor = function(): Vector3
			local pose = ctx.avatarCf or home
			return (pose * CFrame.new(0, H * lastScale * 0.6, -0.9 * lastScale)).Position
		end,
		pack = function(): Vector3
			local pose = ctx.avatarCf or home
			return (pose * CFrame.new(0, H * lastScale * 0.45, 0.9 * lastScale)).Position
		end,
	}

	-- Flugbahn des Neutronensterns: holt Schwung (zurueck, hoch), dann Bogen
	-- in den Gegner, beschleunigt (k^2, F32)
	local hitPos = ctx.targetPos - ctx.fwd * (ctx.targetSize.Z * 0.3)
	local windP = hoverC - ctx.fwd * 0.9 + Vector3.new(0, 0.5, 0)
	local ctrlP = windP:Lerp(hitPos, 0.45) + Vector3.new(0, 3.2, 0)
	local landGap = (ctx.selfSize.Z + ctx.targetSize.Z) * 0.4 + 0.4
	local emergeFeet = ctx.targetFeet - ctx.fwd * (landGap + 1.2)
	local function orbPos(t: number): Vector3
		if t < windAt then
			return hoverC
		elseif t < launchAt then
			return hoverC:Lerp(windP, easeOutCubic((t - windAt) / math.max(0.02, launchAt - windAt)))
		end
		local k = math.clamp((t - launchAt) / fly, 0, 1)
		return novaBez(windP, ctrlP, hitPos, k * k)
	end

	local fired: { [string]: boolean } = {}
	local function once(key: string): boolean
		if fired[key] then return false end
		fired[key] = true
		return true
	end
	local tickDone: { boolean } = {}
	local pulseDone: { boolean } = {}
	local lastT = -1
	local ghostT = 0
	local starShown = false
	runLoop("pulsar", function(tRaw)
		if not clone.Parent then return true end
		if tRaw >= (if freezeAt then freezeAt + 150 else total) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		local dtE = if lastT < 0 then 0 else math.max(0, t - lastT)
		lastT = t
		local power, visorGlow = 0, 0
		local inOrb = t >= collapseAt + 0.05 and t < emergeAt

		-- 1. der Baerchi
		if t < crouchAt then
			-- schaut sich den Ring an, das Visier geht an
			local k = math.clamp(t / crouchAt, 0, 1)
			place(home, -0.06 * math.sin(math.pi * k), 0, 0, 1)
			visorGlow = math.min(1, t / 0.25)
		elseif t < riseAt then
			-- ausholen: zuruecklehnen, kleiner; am Ende zuenden die Duesen
			local e = math.sin(((t - crouchAt) / crouch) * math.pi * 0.5)
			place(home, 0.26 * e, 0, 0, 1 - 0.08 * e)
			visorGlow = 1
			power = math.clamp((t - (riseAt - 0.1)) / 0.1, 0, 1) * 0.5
		elseif t < hangAt then
			-- Aufstieg mit Drehung (Jetpack), waechst
			if once("rise") then
				sparks:Emit(scaled(24, f))
				dust:Emit(scaled(16, f))
			end
			local k = (t - riseAt) / rise
			local e = easeOutCubic(k)
			local pos = home.Position:Lerp(hoverFeet, e) + Vector3.new(0, math.sin(math.pi * k) * 1.0, 0)
			place(face(pos), 0.26 * (1 - e), spins * TAU * e, 0, lerpN(0.92, grow, e))
			power = lerpN(0.6, 1, e)
			visorGlow = 1
		elseif t < collapseAt + 0.05 then
			-- Leuchtturm: kreist immer schneller, wippt; zieht sich zum Kollaps zusammen
			local h = t - hangAt
			local pos = hoverFeet + Vector3.new(0, math.sin(h * 5.5) * 0.12, 0)
			local shrink = math.clamp((t - (collapseAt - 0.1)) / 0.15, 0, 1)
			place(face(pos), 0.05 * math.sin(h * 3), yawAt(t), 0.04 * math.sin(h * 4.3),
				lerpN(grow, grow * 0.45, shrink * shrink))
			power = 1
			visorGlow = 1
			for i, tt in ticks do
				if t >= tt and t < tt + 0.07 then
					visorGlow = 2
				end
				if t >= tt and not tickDone[i] then
					tickDone[i] = true
					twinkle(jet.visor() + camN * 0.6, 2.4 + 0.8 * i, PULSAR_WHITE, 0.45)
					sparks:Emit(scaled(6 + 3 * i, f))
				end
			end
		elseif t >= emergeAt and t < backAt then
			-- rollt sich aus dem Krater auf (halbe Rolle, waechst federnd)
			if once("emerge") then
				hideClone(0)
				hl.Enabled = true
				twinkle(emergeFeet + Vector3.new(0, H * 0.6, 0), 3, PULSAR_WHITE, 0.3)
				sparks:Emit(scaled(18, f))
			end
			local k = (t - emergeAt) / emerge
			local pos = ctx.targetFeet:Lerp(emergeFeet, easeOutCubic(k))
			place(face(pos), -math.pi * (1 - k), 0, 0, lerpN(0.5, 1, easeOutBack(k)))
			power = 0.4
			visorGlow = 1
		elseif t >= backAt and t < homeAt then
			-- Rueckwaerts-Salto heim
			local k = (t - backAt) / back
			local e = easeInOutSine(k)
			local pos = emergeFeet:Lerp(home.Position, e) + Vector3.new(0, math.sin(math.pi * k) * 4.5, 0)
			place(face(pos), TAU * e, 0, 0, 1)
			power = 0.2 + 0.7 * math.sin(math.pi * k)
			visorGlow = 1
		elseif t >= homeAt then
			-- Landung, die Duesen gehen aus
			if once("land") then
				dust:Emit(scaled(18, f))
				sparks:Emit(scaled(12, f))
			end
			local k = math.clamp((t - homeAt) / settle, 0, 1)
			place(home, 0, 0, 0, 1 - 0.1 * math.exp(-k * 6) * math.sin(k * 9))
			power = math.max(0, 0.5 * (1 - k * 2))
			visorGlow = math.max(0, 1 - k * 1.5)
		end
		if not inOrb then
			jet.set(power, visorGlow, t)
		end

		-- 2. Ring: am Boden zeichnen, mit ihm aufsteigen (Orbit-Ring), beim
		-- Kollaps in ihn stuerzen; zu Hause blitzt er noch einmal auf
		local drawn = math.clamp(t / draw, 0, 1)
		local rA, rP, rR, rW = 0, 1, ringR, 0.32
		local rCf = ringFrame0
		if t < riseAt then
			rA, rP = 1, drawn
		elseif t < collapseAt + 0.09 then
			local kr = math.clamp((t - riseAt) / rise, 0, 1)
			local ks = math.clamp((t - hangAt) / math.max(0.1, collapseAt - hangAt), 0, 1)
			local feetNow = if t < hangAt then (ctx.avatarCf or home).Position else hoverFeet
			local waist = feetNow + Vector3.new(0, H * lastScale * 0.42, 0)
			rR = lerpN(ringR, 2.7, easeOutCubic(kr)) - 0.7 * ks
			if t >= collapseAt then
				rR *= (1 - math.min(1, (t - collapseAt) / 0.09)) ^ 2
			end
			rW = lerpN(0.32, 0.26, ks)
			rCf = CFrame.new(groundC:Lerp(waist, easeOutCubic(kr))) * CFrame.Angles(0, startAng + yawAt(t) * 0.5, 0)
			rA = 1
		elseif t >= homeAt then
			rR, rW = 2.8, 0.28
			rCf = ringFrame0
			rP = math.clamp((t - homeAt) / 0.16, 0, 1)
			rA = 1 - math.clamp((t - homeAt - 0.16) / math.max(0.05, settle - 0.16), 0, 1)
		end
		ring.place(rCf, math.max(0.05, rR), rW)
		ring.alpha(rA, rP)
		-- Zeichenkopf und Tick-Striche (bleiben am Boden, verblassen beim Abheben)
		if drawn < 1 then
			local th = drawn * TAU
			head.CFrame = CFrame.new(groundC + ringFrame0:VectorToWorldSpace(Vector3.new(math.cos(th), 0, math.sin(th))) * ringR)
			head.Transparency = 0
		elseif once("drawn") then
			head.Transparency = 1
			twinkle(head.Position, 2.2, PULSAR_WHITE, 0.3)
		end
		local tickA = if t < riseAt then 1 else 1 - math.clamp((t - riseAt) / 0.3, 0, 1)
		for j, p in tickParts do
			local v = if drawn >= (j - 1) / 12 + 0.004 then 1 - 0.9 * tickA else 1
			if math.abs(p.Transparency - v) > 0.01 then p.Transparency = v end
		end

		-- 3. Lichtkegel + Blitz zur Kamera (Besitzer: Bildschirm-Schleier)
		local beamK = 0
		if t >= beamAt and t < collapseAt then
			beamK = easeOutCubic(math.min(1, (t - beamAt) / 0.14))
		elseif t >= collapseAt and t < collapseAt + 0.08 then
			beamK = 1 - (t - collapseAt) / 0.08
		end
		local glowA = 0
		if beamK > 0.01 then
			if not beamsOn then
				beamsOn = true
				for _, bm in beams do bm.Enabled = true end
			end
			local pose = ctx.avatarCf or home
			local look = pose.LookVector
			local flatLook = Vector3.new(look.X, 0, look.Z)
			flatLook = if flatLook.Magnitude > 0.05 then flatLook.Unit else ctx.fwd
			local dir = (flatLook * math.cos(camPitch) + Vector3.yAxis * math.sin(camPitch)).Unit
			local vSrc = jet.visor()
			local jSrc = jet.pack()
			local L = beamLen * beamK
			beamAnchor.CFrame = CFrame.new(vSrc)
			vA0.Position = Vector3.zero
			vA1.Position = dir * L
			jA0.Position = jSrc - vSrc
			jA1.Position = jSrc - vSrc - dir * L
			-- Ausrichtung zur ECHTEN Kamera (F22): Blitz an der Quelle, die zur Kamera zeigt
			local c2 = workspace.CurrentCamera
			if c2 then
				local cp = c2.CFrame.Position
				local aV = math.max(0, dir:Dot((cp - vSrc).Unit))
				local aJ = math.max(0, (-dir):Dot((cp - jSrc).Unit)) * 0.7
				local a = math.max(aV, aJ)
				local boost = 0
				for i, tt in ticks do
					if t >= tt - 0.05 and t < tt + 0.12 then boost = 0.15 * i end
				end
				local inten = (a ^ 10) * beamK * (1 + boost)
				glowA = math.clamp((a ^ 14) * beamK * (0.35 + boost * 0.6), 0, 0.9)
				flareP.CFrame = CFrame.new(if aV >= aJ then vSrc else jSrc)
				local sz = 1.5 + 11 * inten
				local fg, fi, fb = flareGui, flareImg, flareBall
				if fg and fi then
					fg.Size = UDim2.fromScale(sz, sz)
					fi.ImageTransparency = 1 - math.clamp(0.2 + inten, 0, 0.95)
				end
				if fb then
					-- Kern hoechstens ~3,7 Studs, Transparenz >= 0,3 (F36)
					fb.CFrame = flareP.CFrame
					fb.Size = Vector3.one * (0.6 + 2.4 * math.min(inten, 1.3))
					fb.Transparency = 1 - math.clamp(inten * 0.7, 0, 0.7)
				end
			end
		elseif beamsOn then
			beamsOn = false
			for _, bm in beams do bm.Enabled = false end
			local fi, fb = flareImg, flareBall
			if fi then fi.ImageTransparency = 1 end
			if fb then fb.Transparency = 1 end
		end
		if veil then
			veil.set(PULSAR_WHITE, glowA)
		end

		-- 4. Kollaps: Neutronenstern, Sternbruch, Pulse, Flug
		if t >= collapseAt and t < landAt then
			if once("collapse") then
				sparks:Emit(scaled(30, f))
				twinkle(hoverC + camN * 0.5, 5, PULSAR_WHITE, 0.35)
			end
			if t >= collapseAt + 0.05 and once("orb") then
				hideClone(1)
				hl.Enabled = false
				jet.set(0, 0, t)
			end
			local shown = t >= collapseAt + 0.05
			local p = orbPos(t)
			local pop = easeOutBack(math.clamp((t - collapseAt - 0.03) / 0.12, 0, 1))
			local pulse = 0
			for i, pt in pulseAt do
				if t >= pt then
					local q = t - pt
					pulse = math.max(pulse, math.exp(-q * 14) * math.min(1, q / 0.03))
					if not pulseDone[i] then
						pulseDone[i] = true
						sparks:Emit(scaled(12, f))
					end
				end
			end
			local flyK = if t >= launchAt then math.clamp((t - launchAt) / fly, 0, 1) else 0
			local heat = flyK * flyK
			local szC = math.max(0.05, 1.5 * pop * (1 + 0.35 * pulse) * (1 - 0.25 * heat))
			orbCore.Size = Vector3.one * szC
			orbShell.Size = Vector3.one * szC * 1.9
			orbCore.Transparency = if shown then 0 else 1
			orbShell.Transparency = if shown then 0.15 else 1
			orbCore.Color = PULSAR_WHITE:Lerp(NOVA_HOT, heat)
			orbShell.Color = col:Lerp(col2, heat)
			orbCore.CFrame = CFrame.new(p)
			orbShell.CFrame = CFrame.new(p)
			anchor.CFrame = CFrame.new(p)
			ctx.avatarCf = CFrame.new(p)
			local og, oi = orbGui, orbImg
			if og and oi then
				og.Size = UDim2.fromScale(szC * 4.2, szC * 4.2)
				oi.ImageTransparency = if shown then 0.2 else 1
				oi.ImageColor3 = col:Lerp(col2, heat)
			end
			if t >= launchAt then
				if once("launch") then
					trail.Enabled = true
					sparks:Emit(scaled(20, f))
				end
				ghostT += dtE
				if ghostT >= 0.045 then
					ghostT = 0
					local g = newPart(Enum.PartType.Ball, Vector3.one * szC * 1.3, col:Lerp(col2, heat), CFrame.new(p), 0.35)
					g.Name = "PulsarGhost"
					tween(g, trailLife, { Transparency = 1, Size = Vector3.one * szC * 0.5 })
					Debris:AddItem(g, trailLife + 0.1)
				end
			end
		elseif t >= landAt and once("landed") then
			-- Einschlag: der Stern verschwindet in der Kuppel (`firedome`)
			orbCore.Transparency = 1
			orbShell.Transparency = 1
			trail.Enabled = false
			local oi = orbImg
			if oi then oi.ImageTransparency = 1 end
			ctx.avatarCf = CFrame.new(hitPos)
			burstAt(ctx, hitPos, 26, 18, col)
		end

		-- Sternbruch (collapseAt .. +0,42): Zacken flackern, Funken fliegen
		local sb = t - collapseAt
		if sb >= 0 and sb < 0.42 then
			starShown = true
			local step = math.floor(sb * 15)
			local fadeK = 1 - math.clamp((sb - 0.26) / 0.16, 0, 1)
			local big = if step == 0 then 1.35 else 1
			rigApply(starRig, CFrame.new(hoverC), function(r: RigPart): number
				local on = (step % 2 == 0) == (starSet[r] == 1)
				return if on then (0.55 + 0.7 * novaHash(starBlade[r] or 0, step)) * big else 0
			end, fadeK)
			local parts: { BasePart } = table.create(#pills)
			local cfs: { CFrame } = table.create(#pills)
			for i, pl in pills do
				local dt = sb
				local tr = 1
				local pos = hoverC
				local vel = pl.v
				if dt < pl.life then
					vel = pl.v + Vector3.new(0, -30 * dt, 0)
					pos = hoverC + pl.v * dt + Vector3.new(0, -15 * dt * dt, 0)
					tr = dt / pl.life
				end
				local ln = pl.len * (1 - 0.6 * math.min(1, dt / pl.life))
				if math.abs(pl.p.Size.Z - ln) > 0.02 then
					pl.p.Size = Vector3.new(0.26, 0.26, math.max(0.1, ln))
				end
				if math.abs(pl.p.Transparency - tr) > 0.01 then pl.p.Transparency = tr end
				parts[i] = pl.p
				cfs[i] = CFrame.lookAt(pos, pos + (if vel.Magnitude > 0.1 then vel.Unit else Vector3.yAxis))
			end
			workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		elseif starShown then
			starShown = false
			rigApply(starRig, CFrame.new(hoverC), function(_r: RigPart): number return 0 end, 0)
			for _, pl in pills do pl.p.Transparency = 1 end
		end

		-- Puls-Ringe des Neutronensterns (zur Kamera)
		for i, rg in pulseRings do
			local pt = pulseAt[i]
			local q = (t - pt) / 0.28
			if q >= 0 and q < 1 then
				rg.place(planeCf(orbPos(t), camN), lerpN(0.9, 4.8, easeOutCubic(q)), lerpN(0.32, 0.08, q))
				rg.alpha(1 - q)
			else
				rg.alpha(0)
			end
		end
		return false
	end, function()
		hide(0)
		ctx.avatarCf = nil
		ctx.avatarScale = nil
		ctx.pulsarHover = nil
		ctx.pulsarCam = nil
		clone:Destroy()
		ring.destroy()
		for _, rg in pulseRings do rg.destroy() end
		beamAnchor:Destroy()
		flareP:Destroy()
		local fb = flareBall
		if fb then fb:Destroy() end
		if veil then veil.destroy() end
		head:Destroy()
		for _, p in tickParts do p:Destroy() end
		for _, r in starRig do r.p:Destroy() end
		for _, pl in pills do pl.p:Destroy() end
		orbCore:Destroy()
		orbShell:Destroy()
		Debris:AddItem(anchor, 1.2)
	end)
end

-- Silhouette fuer den invertierten Impact-Frame: Klon einer Figur oder eines
-- Effekt-Teils, alles tintenschwarz (ViewportFrame ohne Licht).
local function novaInk(src: Instance, parent: Instance)
	local c: Instance? = nil
	if src:IsA("Model") then
		c = figureClone(src)
	else
		local ok, cc = pcall(function() return src:Clone() end)
		if ok then c = cc end
	end
	local inst = c
	if not inst then return end
	local function ink(p: BasePart)
		p.Material = Enum.Material.SmoothPlastic
		p.Color = NOVA_INK
		p.Transparency = 0
		p.Reflectance = 0
		if p:IsA("MeshPart") then
			pcall(function() (p :: MeshPart).TextureID = "" end)
		end
	end
	if inst:IsA("BasePart") then ink(inst) end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			ink(d)
		elseif d:IsA("SpecialMesh") then
			d.TextureId = ""
		elseif d:IsA("Decal") or d:IsA("Texture") or d:IsA("SurfaceAppearance") or d:IsA("Highlight")
			or d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") or d:IsA("BillboardGui")
			or d:IsA("SurfaceGui") or d:IsA("Light") then
			d:Destroy()
		end
	end
	inst.Parent = parent
end

-- novaframe: Impact-Frames (nur Besitzer, F14). Bild 1: invertiert - rosa-
-- weisser Grund, tintenschwarze Silhouetten (ViewportFrame mit Klonen des
-- Gegners und aller Effekt-Teile, deren Name mit "IFrame" beginnt, z. B. die
-- kleine Kuppel) und Speedlines, die auf den Einschlag zulaufen; danach Weiss,
-- dann blendet das Weiss aus. Jedes Bild steht mindestens EIN gerendertes
-- Bild lang (Zaehlen ueber RenderStepped, nicht ueber Wartezeiten).
--   invert, white, fade, lines
BLOCKS.novaframe = function(ctx, s)
	if not ctx.isOwner then return end
	local cam = workspace.CurrentCamera
	if not cam then return end
	local inv = s.invert or 0.045
	local wht = s.white or 0.08
	local fade = math.max(0.05, s.fade or 0.16)
	local vs = cam.ViewportSize
	local W, Hs = math.max(1, vs.X), math.max(1, vs.Y)
	local gui = Instance.new("ScreenGui")
	gui.Name = "SkillFXImpactFrame"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 52
	gui.ResetOnSpawn = false
	local paper = Instance.new("Frame")
	paper.Size = UDim2.fromScale(1, 1)
	paper.BorderSizePixel = 0
	paper.BackgroundColor3 = NOVA_PAPER
	paper.ZIndex = 1
	paper.Parent = gui
	local vp = Instance.new("ViewportFrame")
	vp.Size = UDim2.fromScale(1, 1)
	vp.BackgroundTransparency = 1
	vp.Ambient = Color3.new(0, 0, 0)
	vp.LightColor = Color3.new(0, 0, 0)
	vp.ZIndex = 2
	vp.Parent = gui
	local vcam = Instance.new("Camera")
	vcam.CFrame = cam.CFrame
	vcam.FieldOfView = cam.FieldOfView
	vcam.Parent = vp
	vp.CurrentCamera = vcam
	if ctx.targetModel and ctx.targetModel.Parent then
		novaInk(ctx.targetModel, vp)
	end
	for _, fo in workspace:GetChildren() do
		if fo.Name == "SkillFXLocal" then
			for _, d in fo:GetChildren() do
				if d:IsA("BasePart") and string.sub(d.Name, 1, 6) == "IFrame" then
					novaInk(d, vp)
				end
			end
		end
	end
	-- Speedlines laufen auf den Einschlag zu (Bildpunkt ueber dem Gegner)
	local sp, _ = cam:WorldToViewportPoint(ctx.targetFeet + Vector3.new(0, 2, 0))
	local cx = math.clamp(sp.X, W * 0.2, W * 0.8)
	local cy = math.clamp(sp.Y, Hs * 0.2, Hs * 0.8)
	local lines = Instance.new("Frame")
	lines.Size = UDim2.fromScale(1, 1)
	lines.BackgroundTransparency = 1
	lines.ZIndex = 3
	lines.Parent = gui
	local rng = Random.new()
	local n = math.max(12, s.lines or 46)
	local diag = math.sqrt(W * W + Hs * Hs)
	for i = 1, n do
		local a = (i - 1) / n * TAU + rng:NextNumber(-0.05, 0.05)
		local r0 = rng:NextNumber(0.16, 0.42) * Hs
		local len = diag
		local w = if rng:NextNumber() < 0.2 then rng:NextNumber(0.022, 0.034) * Hs else rng:NextNumber(0.004, 0.016) * Hs
		local fr = Instance.new("Frame")
		fr.AnchorPoint = Vector2.new(0.5, 0.5)
		fr.Size = UDim2.fromOffset(len, w)
		fr.Position = UDim2.fromOffset(cx + math.cos(a) * (r0 + len / 2), cy + math.sin(a) * (r0 + len / 2))
		fr.Rotation = math.deg(a)
		fr.BorderSizePixel = 0
		fr.BackgroundColor3 = NOVA_INK
		fr.ZIndex = 3
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.18, 0.25),
			NumberSequenceKeypoint.new(1, 0),
		})
		g.Parent = fr
		fr.Parent = lines
	end
	local white = Instance.new("Frame")
	white.Size = UDim2.fromScale(1, 1)
	white.BorderSizePixel = 0
	white.BackgroundColor3 = Color3.new(1, 1, 1)
	white.BackgroundTransparency = 1
	white.ZIndex = 4
	white.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	local stage, frames, tStage = 0, 0, 0
	runLoop("novaframe", function(t)
		frames += 1
		if stage == 0 then
			if t >= inv and frames >= 2 then
				stage, frames, tStage = 1, 0, t
				paper.Visible = false
				vp.Visible = false
				lines.Visible = false
				white.BackgroundTransparency = 0
			end
		elseif stage == 1 then
			if t - tStage >= wht and frames >= 2 then
				stage, tStage = 2, t
			end
		else
			local k = (t - tStage) / fade
			white.BackgroundTransparency = math.min(1, k)
			if k >= 1 then return true end
		end
		return false
	end, function()
		gui:Destroy()
	end)
end

-- firedome: die Feuerkuppel am Einschlag (wie im Vorbild). Erst steht `miniFor`
-- s eine kleine gleissende Kuppel (Radius `mini`, Name "IFrameDome": auch
-- Silhouette im invertierten Impact-Frame), dann waechst die grosse Kuppel
-- (Radius `radius`) mit Ueberschwingen (`grow`): flach weissgluehender Kern
-- (SmoothPlastic, nur schwache Highlight-Fuellung - sie liegt ueber den
-- Baendern, F45; kein Neon - kein Bloom, F17/F36),
-- pinker Umriss, schwacher Neon-Schein (0,9, F05), laufende Flammenbaender
-- (Bezier-Beams mit Luecken, LightEmission 0: vor Weiss sonst unsichtbar),
-- dunkle Loecher, Flammenkranz am Fuss (Beams, flackern), Truemmer, Glut,
-- Brandfleck. Bei jedem `pulseAt` gleisst sie auf und schwillt kurz an
-- (Besitzer: rosa Schleier), bei `flareAt` flammt sie weiss auf (Besitzer:
-- Weissblende -> Rosa) und vergeht in `fade` s; danach zuengeln `burn` s
-- kleine Flammen am Gegner (Brand). Setzt novaT0/novaCenter/novaRadius
-- (Kamera "pulsar" faehrt zurueck).
--   at, radius, mini, miniFor, grow, pulseAt, flareAt, fade, burn,
--   holes, skirt, chunks (Test: freezeAt)
BLOCKS.firedome = function(ctx, s)
	local feet = groundAt(ctx, s.at or "target")
	local R = radiusOf(s.radius, 8)
	local miniR = s.mini or 3.2
	local miniFor = math.max(0.02, s.miniFor or 0.07)
	local grow = math.max(0.05, s.grow or 0.12)
	local pulseAt: { number } = s.pulseAt or { 0.55, 1.05 }
	local flareAt = s.flareAt or 1.45
	local fade = math.max(0.1, s.fade or 0.3)
	local burn = math.max(0, s.burn or 0.75)
	local freezeAt: number? = s.freezeAt
	local goneAt = flareAt + 0.12 + fade
	local total = goneAt + burn
	local col2 = ctx.fx.color2
	local f = ctx.factor
	local rich = extrasOn(ctx)
	local rng = Random.new(77)
	local settleAt = miniFor + grow + 0.15

	-- 1. kleine Kuppel (Impact-Frame 1)
	local mini = newPart(Enum.PartType.Ball, Vector3.one * miniR * 2, NOVA_HOT, CFrame.new(feet), 0)
	mini.Material = Enum.Material.SmoothPlastic
	mini.Name = "IFrameDome"
	local mh = Instance.new("Highlight")
	mh.Adornee = mini
	mh.DepthMode = Enum.HighlightDepthMode.Occluded
	mh.FillColor = NOVA_HOT
	mh.FillTransparency = 0
	mh.OutlineColor = NOVA_YELLOW
	mh.OutlineTransparency = 0
	mh.Parent = mini

	-- 2. die grosse Kuppel
	local core = newPart(Enum.PartType.Ball, Vector3.one * 0.4, NOVA_HOT, CFrame.new(feet), 1)
	core.Material = Enum.Material.SmoothPlastic
	core.Name = "NovaDome"
	local hl = Instance.new("Highlight")
	hl.Adornee = core
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.FillColor = NOVA_HOT
	hl.FillTransparency = 1
	hl.OutlineColor = NOVA_PINK
	hl.OutlineTransparency = 1
	hl.Parent = core
	local aura = newPart(Enum.PartType.Ball, Vector3.one * 0.4, Color3.fromRGB(255, 128, 96), CFrame.new(feet), 1)
	aura.Name = "NovaDomeAura"
	local embers = Instance.new("ParticleEmitter")
	embers.Texture = SPARK_TEX
	embers.Rate = 0
	embers.Shape = Enum.ParticleEmitterShape.Sphere
	embers.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	embers.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
	embers.Speed = NumberRange.new(5, 13)
	embers.Lifetime = NumberRange.new(0.5, 1.1)
	embers.Acceleration = Vector3.new(0, 5, 0)
	embers.Drag = 1.5
	embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) })
	embers.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, NOVA_HOT),
		ColorSequenceKeypoint.new(0.45, NOVA_YELLOW),
		ColorSequenceKeypoint.new(1, NOVA_RED),
	})
	embers.LightEmission = 0.6
	embers.Parent = core

	-- Flammenbaender (Breitengrade, leicht gekippt), drehen sich verschieden
	-- schnell; je Viertel ein Verlauf zum Rot wie ein Flammenschweif. Test
	-- 25.10.: 7 breite waagerechte Baender sahen aus wie ein Wasserball, ein
	-- kleiner Ring ganz oben stand von der Seite als roter Balken ab.
	local bands: { NovaBand } = {}
	local lats: { number } = if rich then { 9, 22, 35, 48 } else { 14, 38 }
	local bandCols = { NOVA_YELLOW, col2, NOVA_YELLOW:Lerp(col2, 0.5), col2 }
	for i, deg in lats do
		local rg = novaRing(bandCols[(i - 1) % #bandCols + 1], 0, 0.1, 16, NOVA_RED)
		for q = 1, 4 do rg.pattern(q, novaGaps(rng, 0.1)) end
		table.insert(bands, { ring = rg, beta = math.rad(deg), w = rng:NextNumber(0.045, 0.075),
			spin = (if i % 2 == 0 then -1 else 1) * rng:NextNumber(0.9, 2.2), ph = rng:NextNumber(0, TAU),
			tilt = CFrame.Angles(rng:NextNumber(-0.2, 0.2), 0, rng:NextNumber(-0.2, 0.2)) })
	end
	-- dunkle Loecher auf der Oberflaeche
	local holes: { NovaHole } = {}
	for _ = 1, (if rich then (s.holes or 6) else 3) do
		local th = rng:NextNumber(0, TAU)
		local el = rng:NextNumber(0.25, 1.05)
		local p, mesh = ellipsoid(NOVA_HOLE, Vector3.one, PARK, 1, Enum.Material.SmoothPlastic)
		mesh.Scale = Vector3.one
		p.Name = "NovaHole"
		table.insert(holes, { p = p, dir = Vector3.new(math.cos(el) * math.cos(th), math.sin(el), math.cos(el) * math.sin(th)),
			w = rng:NextNumber(0.2, 0.32), h = rng:NextNumber(0.11, 0.19), roll = rng:NextNumber(0, TAU) })
	end
	local skirt = novaFlames(if rich then (s.skirt or 18) else 10, R * 0.2, 5)
	local burnFl = novaFlames(8, 1.1, 9)
	-- Truemmer (Rig, frei gebaut: fixed, g = 1)
	local rubble: { RigPart } = {}
	for _ = 1, scaled(s.chunks or 10, f) do
		local sz = Vector3.new(rng:NextNumber(0.45, 1.0), rng:NextNumber(0.35, 0.8), rng:NextNumber(0.45, 1.0))
		local p = newPart(Enum.PartType.Block, sz, NOVA_ASH, PARK, 1)
		p.Material = Enum.Material.SmoothPlastic
		p.Name = "NovaRubble"
		local a = rng:NextNumber(0, TAU)
		local rel = CFrame.new(math.cos(a) * rng:NextNumber(0.5, 2.2), 0.4, math.sin(a) * rng:NextNumber(0.5, 2.2))
			* CFrame.Angles(rng:NextNumber(0, TAU), rng:NextNumber(0, TAU), 0)
		table.insert(rubble, { p = p, frame = rel, size = sz, delay = 0, tr = 0, g = 1, fixed = true, lt = 1 })
	end
	-- Brandfleck (unter der Kuppel, sichtbar wenn sie vergeht)
	local scorch = newPart(Enum.PartType.Cylinder, Vector3.new(0.05, R * 1.9, R * 1.9), Color3.fromRGB(28, 18, 30),
		CFrame.new(feet + Vector3.new(0, 0.04, 0)) * CFrame.Angles(0, 0, math.rad(90)), 1)
	scorch.Material = Enum.Material.SmoothPlastic
	scorch.Name = "NovaScorch"
	local craterTex = texOf(ctx, "crater")
	local plate: BasePart? = nil
	local decal: Decal? = nil
	if craterTex then
		local pl = newPart(Enum.PartType.Block, Vector3.new(R * 2.3, 0.05, R * 2.3), NOVA_YELLOW, CFrame.new(feet + Vector3.new(0, 0.07, 0)), 1)
		pl.Name = "NovaCrater"
		decal = addDecal(pl, craterTex, Enum.NormalId.Top, NOVA_YELLOW)
		plate = pl
	end
	local veil = novaVeil(ctx)

	local fired: { [string]: boolean } = {}
	local function once(key: string): boolean
		if fired[key] then return false end
		fired[key] = true
		return true
	end
	local pulseDone: { boolean } = {}
	local lastT = -1
	runLoop("firedome", function(tRaw)
		if tRaw >= (if freezeAt then freezeAt + 150 else total) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		local dtE = if lastT < 0 then 0 else math.max(0, t - lastT)
		lastT = t
		-- kleine Kuppel weg, die grosse beginnt
		if t >= miniFor and once("big") then
			mini:Destroy()
			ctx.novaT0 = os.clock()
			ctx.novaCenter = feet + Vector3.new(0, R * 0.4, 0)
			ctx.novaRadius = R
			embers:Emit(scaled(40, f))
			rigApply(rubble, CFrame.new(feet), function(_r: RigPart): number return 1 end, 1)
			rigShatter(rubble, feet - Vector3.new(0, 1, 0), 22)
			burstAt(ctx, feet + Vector3.new(0, 1.5, 0), 20, 10, NOVA_ASH, true)
		end
		if t < miniFor then return false end
		local tb = t - miniFor
		-- Groesse: Ueberschwingen, langsames Wachsen, Pulse, Aufflammen
		local S: number
		if tb < grow then
			S = 0.15 + 0.97 * easeOutCubic(tb / grow)
		elseif t < settleAt then
			S = lerpN(1.12, 1.0, easeInOutSine((t - miniFor - grow) / 0.15))
		else
			S = 1 + 0.1 * math.clamp((t - settleAt) / math.max(0.1, flareAt - settleAt), 0, 1)
		end
		local spike = 0
		for i, pt in pulseAt do
			if t >= pt then
				local q = t - pt
				spike = math.max(spike, math.exp(-q * 10) * math.min(1, q / 0.04))
				if not pulseDone[i] then
					pulseDone[i] = true
					embers:Emit(scaled(28, f))
				end
			end
		end
		local flareK = if t >= flareAt then easeOutCubic(math.min(1, (t - flareAt) / 0.12)) else 0
		if t >= flareAt and once("flare") then
			embers:Emit(scaled(60, f))
		end
		S = S + 0.08 * spike + 0.14 * flareK
		local alpha = 1 - math.clamp((t - flareAt - 0.1) / fade, 0, 1)
		local Rn = R * S
		if alpha > 0.001 then
			core.Size = Vector3.one * Rn * 2
			aura.Size = Vector3.one * Rn * 2.14
		end
		core.Transparency = if alpha > 0.02 then 1 - alpha else 1
		aura.Transparency = 1 - (1 - 0.9) * alpha * (1 + spike + flareK)
		local hot = math.max(spike, flareK)
		hl.FillColor = NOVA_HOT:Lerp(Color3.new(1, 1, 1), flareK)
		-- Fuellung nur schwach: sie liegt UEBER den Baendern (Beams schreiben
		-- keine Tiefe, F45); Pulse und Aufflammen gleissen ueber die Fuellung
		hl.FillTransparency = 1 - (1 - lerpN(0.82, 0, hot)) * alpha
		hl.OutlineColor = NOVA_PINK:Lerp(Color3.new(1, 1, 1), math.max(spike * 0.6, flareK))
		hl.OutlineTransparency = 1 - alpha
		-- Baender: auf der Oberflaeche, verschwinden im Aufflammen
		local bA = alpha * (1 - flareK) * math.clamp(tb / 0.06, 0, 1)
		for _, bd in bands do
			local rr = Rn * math.cos(bd.beta) * 1.012
			bd.ring.place(CFrame.new(feet) * bd.tilt * CFrame.new(0, Rn * math.sin(bd.beta) * 1.012, 0)
				* CFrame.Angles(0, bd.ph + bd.spin * t, 0), rr, math.max(0.25, bd.w * Rn))
			bd.ring.alpha(bA)
		end
		-- Loecher drehen langsam mit
		local spinCf = CFrame.Angles(0, 0.35 * t, 0)
		local hParts: { BasePart } = table.create(#holes)
		local hCfs: { CFrame } = table.create(#holes)
		for i, ho in holes do
			local d = spinCf:VectorToWorldSpace(ho.dir)
			local pos = feet + d * Rn * 1.006
			ho.p.Size = Vector3.new(ho.w * Rn, ho.h * Rn, 0.06)
			local v = 1 - (1 - 0.08) * bA
			if math.abs(ho.p.Transparency - v) > 0.01 then ho.p.Transparency = v end
			hParts[i] = ho.p
			hCfs[i] = CFrame.lookAt(pos, pos + d, perpOf(d)) * CFrame.Angles(0, 0, ho.roll)
		end
		workspace:BulkMoveTo(hParts, hCfs, Enum.BulkMoveMode.FireCFrameChanged)
		-- Flammenkranz am Fuss
		skirt.place(feet, Rn * 0.97, R * (0.32 + 0.2 * spike) * (1 - 0.5 * flareK), t, alpha * math.clamp(tb / 0.05, 0, 1))
		-- Truemmer fliegen (eingefroren: dt = 0)
		if #rubble > 0 then
			rigFly(rubble, dtE, 1 - math.clamp((tb - 0.6) / 0.4, 0, 1))
		end
		-- Brandfleck und Glut: erst heiss, kuehlt ab, verblasst am Ende
		local cool = math.clamp((t - flareAt) / 1.0, 0, 1)
		local endA = 1 - math.clamp((t - (total - 0.35)) / 0.35, 0, 1)
		scorch.Transparency = 1 - 0.7 * endA
		local dc = decal
		if dc then
			dc.Color3 = NOVA_YELLOW:Lerp(NOVA_RED, math.min(1, cool * 1.6)):Lerp(NOVA_ASH, math.max(0, cool * 1.6 - 0.6))
			dc.Transparency = 1 - endA
		end
		-- Brand: kleine Flammen am Gegner, folgen ihm (Server-Rueckstoss)
		if t >= goneAt - 0.15 and burn > 0 then
			local c = centerOf(ctx.targetModel) or ctx.targetPos
			local tf = c - Vector3.new(0, ctx.targetSize.Y / 2, 0)
			local bk = math.clamp((t - (goneAt - 0.15)) / 0.15, 0, 1) * endA
			-- bis ueber den Kopf (Test 25.10.: 1,5 Studs hohe Flammen gingen
			-- hinter dem Gegner unter)
			burnFl.place(tf, math.max(0.7, ctx.targetSize.X * 0.5), math.max(1.8, ctx.targetSize.Y * 1.1), t, bk)
		end
		-- Besitzer: rosa Schleier bei den Pulsen, Weissblende -> Rosa beim Aufflammen
		if veil then
			local wA = 0
			local wC = Color3.fromRGB(255, 160, 205)
			if t >= flareAt then
				local q = t - flareAt
				if q < 0.36 then
					wA = math.min(1, q / 0.05)
					wC = Color3.new(1, 1, 1)
				else
					local k = math.clamp((q - 0.36) / 0.75, 0, 1)
					wA = 1 - k
					wC = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(255, 196, 226), math.min(1, k * 2.2))
				end
			else
				wA = 0.42 * spike
			end
			veil.set(wC, wA)
		end
		return false
	end, function()
		if mini.Parent then mini:Destroy() end
		ctx.novaT0 = nil
		ctx.novaCenter = nil
		ctx.novaRadius = nil
		core:Destroy()
		aura:Destroy()
		for _, bd in bands do bd.ring.destroy() end
		for _, ho in holes do ho.p:Destroy() end
		skirt.destroy()
		burnFl.destroy()
		for _, r in rubble do r.p:Destroy() end
		scorch:Destroy()
		local pl = plate
		if pl then pl:Destroy() end
		if veil then veil.destroy() end
	end)
end

-- novabolt: Echo. Ein kleiner Neutronenstern blitzt am Angreifer auf, schiesst
-- in `fly` s (k^2) in den Gegner (Treffer), dort ploppt eine kleine Feuer-
-- kuppel (Radius `radius`) auf und vergeht in `life` s.
--   at, fly, radius, life, size (Test: freezeAt)
BLOCKS.novabolt = function(ctx, s)
	local fly = math.max(0.05, s.fly or 0.25)
	local R = s.radius or 2.6
	local life = math.max(0.1, s.life or 0.34)
	local size = s.size or 0.7
	local freezeAt: number? = s.freezeAt
	local col = ctx.fx.color
	local col2 = ctx.fx.color2
	local from = ctx.selfPos + ctx.fwd * (ctx.selfSize.Z * 0.5 + 0.4) + Vector3.new(0, 0.2, 0)
	local hitFeet = groundAt(ctx, s.at or "target")
	local to = ctx.targetPos - ctx.fwd * (ctx.targetSize.Z * 0.35)
	twinkle(from, 2.4, PULSAR_WHITE, 0.25)
	local core = newPart(Enum.PartType.Ball, Vector3.one * size, PULSAR_WHITE, CFrame.new(from), 0)
	core.Name = "PulsarBolt"
	local shell = newPart(Enum.PartType.Ball, Vector3.one * size * 1.8, col, CFrame.new(from), 0.15)
	shell.Material = Enum.Material.ForceField
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, size * 0.8, 0)
	a0.Parent = shell
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -size * 0.8, 0)
	a1.Parent = shell
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.2
	trail.FaceCamera = true
	trail.LightEmission = 0.5
	trail.LightInfluence = 0
	trail.Color = ColorSequence.new(PULSAR_WHITE, col2)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
	trail.Parent = shell
	local dome = newPart(Enum.PartType.Ball, Vector3.one * 0.3, NOVA_YELLOW, CFrame.new(hitFeet), 1)
	dome.Material = Enum.Material.SmoothPlastic
	dome.Name = "NovaBoltDome"
	local hl = Instance.new("Highlight")
	hl.Adornee = dome
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.FillColor = NOVA_HOT
	hl.FillTransparency = 1
	hl.OutlineColor = NOVA_PINK
	hl.OutlineTransparency = 1
	hl.Parent = dome
	local flames = novaFlames(6, 0.8, 13)
	local hit = false
	runLoop("novabolt", function(tRaw)
		if tRaw >= (if freezeAt then freezeAt + 150 else fly + life) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		if t < fly then
			local k = t / fly
			local e = k * k
			local p = from:Lerp(to, e) + Vector3.new(0, math.sin(math.pi * k) * 1.2, 0)
			core.CFrame = CFrame.new(p)
			shell.CFrame = CFrame.new(p)
			shell.Color = col:Lerp(col2, e)
			return false
		end
		if not hit then
			hit = true
			core.Transparency = 1
			shell.Transparency = 1
			trail.Enabled = false
			burstAt(ctx, to, 18, 14, col2)
		end
		local q = (t - fly) / life
		local S = if q < 0.25 then 1.12 * easeOutCubic(q / 0.25) else lerpN(1.12, 1.0, math.min(1, (q - 0.25) / 0.2))
		dome.Size = Vector3.one * 2 * R * math.max(0.1, S)
		local a = 1 - math.clamp((q - 0.45) / 0.55, 0, 1)
		dome.Transparency = if a > 0.02 then 1 - a else 1
		hl.FillTransparency = 1 - 0.9 * a
		hl.OutlineTransparency = 1 - a
		flames.place(hitFeet, R * math.max(0.1, S) * 0.95, R * 0.5, t, a)
		return false
	end, function()
		core:Destroy()
		shell:Destroy()
		dome:Destroy()
		flames.destroy()
	end)
end


--------------------------------------------------------------------------------
-- 25.10.2026 Shows der ersten Baerchis (Uncommon bis Legendary, Stufe 2/3, ohne
-- Kamerafahrt). Schub 1: Bauchrutscher (Eisbaer), Tigersprung (Tigerbaer),
-- Brennglas (Detektiv), Bass-Drop (Zucker-DJ). Gemeinsamer Baustein `moves`:
-- der Baerchi SELBST folgt Posen aus den DATEN (SkillFXConfig), so braucht nicht
-- jede Show eine eigene Tanz-Funktion. Alle Helfer dieser Shows liegen in EINER
-- Tabelle LOW (die Modul-Ebene hat nur noch ~60 freie lokale Namen, Roblox-
-- Grenze 200). Doku in SkillFXConfig ("BAUSTEINE", Erste Baerchis).
--------------------------------------------------------------------------------

local LOW: { [string]: any } = {}

LOW.WHITE = Color3.fromRGB(255, 250, 240)      -- warmes Weiss (Klon-Fuellung, F37)
LOW.ICE = Color3.fromRGB(178, 226, 255)        -- Eis
LOW.RIME = Color3.fromRGB(232, 247, 255)       -- Reif, fast weiss
LOW.EMBER = Color3.fromRGB(150, 38, 28)        -- schwelender Kratzer
LOW.HOT = Color3.fromRGB(255, 236, 160)        -- gluehend hell
LOW.GOLD = Color3.fromRGB(243, 218, 124)       -- Messing der Lupe
LOW.BRASS = Color3.fromRGB(160, 134, 97)       -- Griff
LOW.VINYL = Color3.fromRGB(38, 30, 48)         -- Schallplatte
LOW.DEEPICE = Color3.fromRGB(140, 200, 245)    -- Eisbahn (satter als der Block, F19)
LOW.RIMBLUE = Color3.fromRGB(90, 160, 235)     -- Reifkanten der Eisbahn (blau statt weiss)
LOW.DEEPPINK = Color3.fromRGB(255, 110, 190)   -- leuchtende Kopfhoerer-Muscheln (satt, kein Bloom, F17)

-- Easing nach Name ("inout" Standard; "in" beschleunigt, "out" bremst, "back"
-- federt ueber, "linear").
LOW.ease = function(name: string?, k: number): number
	k = math.clamp(k, 0, 1)
	if name == "linear" then return k end
	if name == "in" then return k * k end
	if name == "out" then return 1 - (1 - k) * (1 - k) end
	if name == "back" then return easeOutBack(k) end
	return 0.5 - 0.5 * math.cos(math.pi * k)
end

-- Bodenhoehe zwischen den Kaempfern an einem Punkt (Tower: beide Fuesse koennen
-- leicht verschieden hoch liegen).
LOW.groundY = function(ctx: Ctx, pos: Vector3): number
	local a, b = ctx.selfFeet, ctx.targetFeet
	local d = b - a
	local flat = Vector3.new(d.X, 0, d.Z)
	if flat.Magnitude < 0.01 then return a.Y end
	local u = math.clamp((pos - a):Dot(flat) / flat:Dot(flat), 0, 1)
	return lerpN(a.Y, b.Y, u)
end

-- Emitter-Anker mit Funken, Rauch und Schweif (wie in `ascend`), folgt dem Klon.
LOW.fxAnchor = function(ctx: Ctx, H: number, col: Color3, col2: Color3): (BasePart, ParticleEmitter, ParticleEmitter, Trail)
	local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, PARK, 1)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = SMOKE_TEX
	smoke.Rate = 0
	smoke.Speed = NumberRange.new(0.5, 2.5)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Lifetime = NumberRange.new(0.45, 0.8)
	smoke.Drag = 2
	smoke.Acceleration = Vector3.new(0, 1.2, 0)
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, H * 0.22), NumberSequenceKeypoint.new(1, H * 0.55) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	smoke.Color = ColorSequence.new(LOW.WHITE, col2)
	smoke.LightEmission = 0.3
	smoke.Rotation = NumberRange.new(0, 360)
	smoke.RotSpeed = NumberRange.new(-30, 30)
	smoke.Parent = anchor
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = SPARK_TEX
	sparks.Rate = 0
	sparks.Speed = NumberRange.new(4, 9)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Lifetime = NumberRange.new(0.3, 0.65)
	sparks.Drag = 2
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	sparks.Color = ColorSequence.new(LOW.WHITE, col)
	sparks.LightEmission = 0.8
	sparks.Parent = anchor
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, H * 0.35, 0)
	a0.Parent = anchor
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -H * 0.35, 0)
	a1.Parent = anchor
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.25
	trail.LightEmission = 0.8
	trail.FaceCamera = true
	trail.Color = ColorSequence.new(LOW.WHITE, col)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	trail.Enabled = false
	trail.Parent = anchor
	return anchor, sparks, smoke, trail
end

-- Streusel: kleine bunte Staebchen fliegen aus `pos` auseinander und fallen
-- (Rig, EINE Schleife), verblassen in `life` s.
LOW.sprinkles = function(ctx: Ctx, pos: Vector3, n: number, life: number?)
	local rig: { RigPart } = {}
	local rng = Random.new()
	local colors = { Color3.fromRGB(255, 160, 211), LOW.WHITE, Color3.fromRGB(218, 196, 255), Color3.fromRGB(255, 232, 130), Color3.fromRGB(180, 255, 225) }
	for i = 1, scaled(n, ctx.factor) do
		local p = newPart(Enum.PartType.Cylinder, Vector3.new(0.55, 0.16, 0.16), colors[(i - 1) % #colors + 1], CFrame.new(pos), 0)
		p.Material = Enum.Material.SmoothPlastic
		p.Name = "Sprinkle"
		rigPart(rig, p, CFrame.new(rng:NextNumber(-0.3, 0.3), rng:NextNumber(-0.3, 0.3), rng:NextNumber(-0.3, 0.3))
			* CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0), p.Size, 0, 0, true)
	end
	rigApply(rig, CFrame.new(pos), function() return 1 end, 1)
	rigShatter(rig, pos - Vector3.new(0, 0.5, 0), 7)
	local L = life or 0.8
	runLoop("sprinkles", function(t, dt)
		if t >= L then return true end
		rigFly(rig, dt, math.clamp(1 - (t - L * 0.6) / (L * 0.4), 0, 1))
		return false
	end, function()
		for _, r in rig do r.p:Destroy() end
	end)
end

-- moves: der Baerchi SELBST (echter Klon, Original lokal unsichtbar, F03) folgt
-- Posen aus den Daten; zwischen zwei Posen wird weich ueberblendet. Felder je
-- Pose (siehe SkillFXConfig): t, at, dx/dy/dz, u/h/from/to, pitch/yaw/roll (in
-- Umdrehungen), scale, ease, arc, trail, burst, smoke, hidden, tip. Drehung,
-- Groesse, Hut und Sichtbarkeit erben von der Pose davor, Ort und Versatz nicht.
-- Setzt ctx.avatarCf, avatarScale, avatarModel.
--   keys, hat, outline, hold, gap (Test: freezeAt)
BLOCKS.moves = function(ctx, s)
	local source = ctx.selfModel
	if not source or not source.Parent then return end
	local keys = s.keys
	if type(keys) ~= "table" or #keys == 0 then return end
	local clone = figureClone(source)
	if not clone then return end
	local H = ctx.selfSize.Y
	local home = CFrame.lookAt(ctx.selfFeet, ctx.selfFeet + ctx.fwd)
	local offset = home:ToObjectSpace(clone:GetPivot())
	local okScale, got = pcall(function() return clone:GetScale() end)
	local baseScale: number = if okScale and typeof(got) == "number" then got else 1
	local gap = (ctx.selfSize.Z + ctx.targetSize.Z) * 0.4 + (s.gap or 0.4)
	local side = sideOf(ctx)
	local up = Vector3.yAxis
	-- `dxc`: seitlicher Versatz relativ zur Kamera-Seite (+ = zur Kamera hin), einmal beim Start (F22)
	local camSide = if camFace((ctx.selfFeet + ctx.targetFeet) / 2, side):Dot(side) >= 0 then 1 else -1
	local anchors: { [string]: Vector3 } = {
		home = ctx.selfFeet,
		land = ctx.targetFeet - ctx.fwd * gap,
		target = ctx.targetFeet,
		arena = (ctx.selfFeet + ctx.targetFeet) / 2,
	}
	local freezeAt: number? = s.freezeAt
	local hold = s.hold or 0.1
	local col = ctx.fx.color

	-- Posen auffuellen
	local poses: { { [string]: any } } = {}
	local start: { [string]: any } = { t = 0, pos = ctx.selfFeet, pitch = 0, yaw = 0, roll = 0, scale = 1, tip = 0,
		atName = "home", hidden = false, arc = 0, trail = false, burst = 0, smoke = 0, done = true }
	local prev = start
	for _, k in keys do
		local atName = k.at or prev.atName
		local pos: Vector3
		if k.u ~= nil then
			local a = anchors[k.from or "home"] or ctx.selfFeet
			local b = anchors[k.to or "land"] or anchors.land
			local u = math.clamp(k.u, 0, 1)
			if k.curve then
				-- Bruecke (kubische Bezier wie `rainbow`, Schub 2)
				pos = LOW.bridge(a, b, ctx.fwd, k.curve, k.tilt or 0.35, u)
			else
				pos = a:Lerp(b, u) + up * ((k.h or 0) * 4 * u * (1 - u))
			end
		else
			pos = anchors[atName] or ctx.selfFeet
		end
		pos += side * ((k.dx or 0) + (k.dxc or 0) * camSide) + up * (k.dy or 0) + ctx.fwd * (k.dz or 0)
		local p = {
			t = k.t or prev.t, pos = pos, atName = atName,
			pitch = if k.pitch ~= nil then k.pitch * TAU else prev.pitch,
			yaw = if k.yaw ~= nil then k.yaw * TAU else prev.yaw,
			roll = if k.roll ~= nil then k.roll * TAU else prev.roll,
			scale = k.scale or prev.scale,
			tip = k.tip or prev.tip,
			hidden = if k.hidden ~= nil then k.hidden == true else prev.hidden,
			ease = k.ease, arc = k.arc or 0, trail = k.trail == true,
			burst = k.burst or 0, smoke = k.smoke or 0, done = false,
		}
		table.insert(poses, p)
		prev = p
	end
	local total = prev.t + hold

	-- Hut: Teile, deren Name eines der Muster in `hat` (kommagetrennt) enthaelt;
	-- Lage relativ zum Pivot bei Groesse 1, Drehpunkt = Mitte des Huts.
	local hatParts: { { p: BasePart, rel: CFrame } } = {}
	local hatMid = Vector3.zero
	if type(s.hat) == "string" then
		local pv = clone:GetPivot()
		for _, d in clone:GetDescendants() do
			if d:IsA("BasePart") then
				for pat in string.gmatch(s.hat, "[^,]+") do
					if d.Name:find(pat, 1, true) then
						local rel = pv:ToObjectSpace(d.CFrame)
						table.insert(hatParts, { p = d, rel = rel })
						hatMid += rel.Position
						break
					end
				end
			end
		end
		if #hatParts > 0 then hatMid /= #hatParts end
	end

	-- Leuchtumriss (helle Modelle: satter Umriss, warm-weisse Fuellung, F37)
	local hl = Instance.new("Highlight")
	hl.Adornee = clone
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.FillColor = LOW.WHITE
	hl.FillTransparency = 0.9
	hl.OutlineColor = if typeof(s.outline) == "Color3" then s.outline else col
	hl.OutlineTransparency = 0.05
	hl.Parent = clone

	local anchor, sparks, smoke, trail = LOW.fxAnchor(ctx, H, col, ctx.fx.color2)
	local hide = hideFigure(source)
	local lastScale = 1
	local function place(feet: CFrame, pitch: number, yaw: number, roll: number, sc: number, tip: number, hidden: boolean)
		if math.abs(sc - lastScale) > 0.008 then
			lastScale = sc
			pcall(function() clone:ScaleTo(baseScale * sc) end)
		end
		local half = H * sc * 0.5
		local pose = feet * CFrame.new(0, half, 0) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll) * CFrame.new(0, -half, 0)
		ctx.avatarCf = pose
		ctx.avatarScale = sc
		local pv = pose * CFrame.new(offset.Position * sc) * offset.Rotation
		if hidden then pv += Vector3.new(0, 1500, 0) end
		clone:PivotTo(pv)
		if tip > 0.001 and #hatParts > 0 then
			-- Hut lueften: anheben und seitlich kippen, um die Hutmitte
			local lift = CFrame.new(hatMid * sc) * CFrame.new(0, H * sc * 0.22 * tip, 0)
				* CFrame.Angles(0, 0, -0.5 * tip) * CFrame.new(-hatMid * sc)
			for _, h in hatParts do
				h.p.CFrame = pv * lift * CFrame.new(h.rel.Position * sc) * h.rel.Rotation
			end
		end
		anchor.CFrame = pose * CFrame.new(0, half, 0)
	end
	place(home, 0, 0, 0, 1, 0, false)
	ctx.avatarModel = clone
	clone.Parent = folder()
	hide(1)

	runLoop("moves", function(tRaw)
		if not clone.Parent then return true end
		if tRaw >= (if freezeAt then freezeAt + 150 else total) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		-- Segment a -> b finden
		local a, b = start, poses[#poses]
		for i, p in poses do
			if t < p.t then
				b = p
				a = if i > 1 then poses[i - 1] else start
				break
			end
			a = p
		end
		local pos: Vector3, pitch: number, yaw: number, roll: number, sc: number, tip: number
		if t >= b.t then
			-- letzte Pose halten (leichtes Atmen)
			pos = b.pos + up * (0.03 * math.sin(t * 5))
			pitch, yaw, roll, sc, tip = b.pitch, b.yaw, b.roll, b.scale, b.tip
		else
			local k = (t - a.t) / math.max(0.001, b.t - a.t)
			local e = LOW.ease(b.ease, k)
			pos = a.pos:Lerp(b.pos, e) + up * (b.arc * 4 * k * (1 - k))
			if b.arc == 0 and (b.pos - a.pos).Magnitude < 0.01 and b.t - a.t > 0.25 then
				pos += up * (0.03 * math.sin(t * 5))
			end
			pitch = lerpN(a.pitch, b.pitch, e)
			yaw = lerpN(a.yaw, b.yaw, e)
			roll = lerpN(a.roll, b.roll, e)
			sc = lerpN(a.scale, b.scale, e)
			tip = lerpN(a.tip, b.tip, e)
		end
		trail.Enabled = (t < b.t) and b.trail and not a.hidden
		place(CFrame.lookAt(pos, pos + ctx.fwd), pitch, yaw, roll, sc, tip, a.hidden)
		-- Ereignisse beim Erreichen einer Pose (genau einmal)
		for _, p in poses do
			if not p.done and t >= p.t then
				p.done = true
				if p.burst > 0 then sparks:Emit(scaled(p.burst, ctx.factor)) end
				if p.smoke > 0 then smoke:Emit(scaled(p.smoke, ctx.factor)) end
			end
		end
		return false
	end, function()
		hide(0)
		ctx.avatarCf = nil
		ctx.avatarScale = nil
		ctx.avatarModel = nil
		clone:Destroy()
		trail.Enabled = false
		Debris:AddItem(anchor, 1)
	end)
end

-- icepath: eine Eisbahn gefriert in `draw` s von den eigenen Fuessen bis vor den
-- Gegner: Eisplatten (Material Ice) ploppen nacheinander auf, Reifkanten, kleine
-- Eiszacken an den Raendern (Rig), Frostglitzer an der Gefrierfront; zwischen
-- `slideAt` und `slideEnd` folgt eine Schneefahne dem Klon (ctx.avatarCf); ab
-- `meltAt` taut alles weg (Platten blass, Zacken sinken). Test: freezeAt.
--   draw, width, plates, spikes, over, slideAt, slideEnd, meltAt, dur
BLOCKS.icepath = function(ctx, s)
	local draw = s.draw or 0.5
	local width = s.width or 2.4
	local nPlates = math.max(2, s.plates or 6)
	local nSpikes = if (s.spikes or 8) > 0 then scaled(s.spikes or 8, ctx.factor) else 0
	local slideAt = s.slideAt or 0.75
	local slideEnd = s.slideEnd or 1.5
	local meltAt = s.meltAt or 2.2
	local dur = s.dur or 2.7
	local freezeAt: number? = s.freezeAt
	local gap = (ctx.selfSize.Z + ctx.targetSize.Z) * 0.4 + 0.4
	local a = ctx.selfFeet - ctx.fwd * 0.6
	local b = ctx.targetFeet - ctx.fwd * (gap - (s.over or 0.8))
	local len = (b - a).Magnitude
	local side = sideOf(ctx)
	local col = ctx.fx.color

	-- Platten + Reifkanten
	type Plate = { p: BasePart, l: BasePart, r: BasePart, t0: number, w: number, seg: number, mid: Vector3, k: number }
	local plates: { Plate } = {}
	local segLen = len / nPlates
	for i = 1, nPlates do
		local u0 = (i - 1) / nPlates
		local u1 = i / nPlates
		local mid = a:Lerp(b, (u0 + u1) / 2)
		mid = Vector3.new(mid.X, LOW.groundY(ctx, mid) + 0.07, mid.Z)
		local w = width * (0.8 + 0.35 * u1)
		local cf = CFrame.lookAt(mid, mid + ctx.fwd)
		local p = newPart(Enum.PartType.Block, Vector3.new(0.1, 0.14, 0.1), LOW.DEEPICE, cf, 1)
		p.Material = Enum.Material.Ice
		p.Name = "IcePlate"
		local l = newPart(Enum.PartType.Block, Vector3.new(0.1, 0.18, 0.1), LOW.RIMBLUE, cf, 1)
		local r = newPart(Enum.PartType.Block, Vector3.new(0.1, 0.18, 0.1), LOW.RIMBLUE, cf, 1)
		table.insert(plates, { p = p, l = l, r = r, t0 = draw * u0, w = w, seg = segLen + 0.04, mid = mid, k = -1 })
	end
	-- Eiszacken an den Raendern (abwechselnd links/rechts), Spitze nach aussen gekippt
	local rig: { RigPart } = {}
	local rng = Random.new(7)
	for i = 1, nSpikes do
		local u = (i - 0.5) / nSpikes
		local sideSign = if i % 2 == 0 then 1 else -1
		local pos = a:Lerp(b, u)
		local w = width * (0.8 + 0.35 * u) * 0.5
		pos = Vector3.new(pos.X, LOW.groundY(ctx, pos) + 0.12, pos.Z) + side * (sideSign * (w + 0.05))
		local h = 0.7 + rng:NextNumber(0, 0.6) + u * 0.5
		-- Klingenebene quer zur Bahn (Dicke entlang der Bahn), nach aussen gekippt
		local frame = CFrame.fromMatrix(pos, ctx.fwd, Vector3.yAxis) * CFrame.Angles(0.35 * sideSign, 0, 0)
		addBlade(rig, frame, 0.22, h, 0.3, LOW.ICE, Enum.Material.Ice, draw * u + 0.05)
	end
	-- Glitzer an der Gefrierfront, spaeter Schneefahne hinter dem Klon (EIN Emitter)
	local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, CFrame.new(a), 1)
	local em = Instance.new("ParticleEmitter")
	em.Texture = SPARK_TEX
	em.Rate = 0
	em.Speed = NumberRange.new(1, 3)
	em.SpreadAngle = Vector2.new(180, 180)
	em.Lifetime = NumberRange.new(0.3, 0.6)
	em.Drag = 2
	em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	em.Color = ColorSequence.new(LOW.RIME, col)
	em.LightEmission = 0.6
	em.Parent = anchor
	local snow = false
	local extras = extrasOn(ctx)
	local melting = false
	runLoop("icepath", function(tRaw)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		-- Platten ploppen auf (Groesse federt, dann sichtbar)
		for _, pl in plates do
			local k = math.clamp((t - pl.t0) / 0.16, 0, 1)
			if k ~= pl.k then
				pl.k = k
				local e = easeOutBack(k)
				local w = math.max(0.05, pl.w * e)
				local sg = math.max(0.05, pl.seg * e)
				local cf = CFrame.lookAt(pl.mid, pl.mid + ctx.fwd)
				pl.p.Size = Vector3.new(w, 0.14, sg)
				pl.p.CFrame = cf
				pl.p.Transparency = if k > 0 then 0.05 else 1
				pl.l.Size = Vector3.new(0.1, 0.18, sg)
				pl.r.Size = pl.l.Size
				pl.l.CFrame = cf * CFrame.new(-w / 2, 0.02, 0)
				pl.r.CFrame = cf * CFrame.new(w / 2, 0.02, 0)
				pl.l.Transparency = if k > 0 then 0.25 else 1
				pl.r.Transparency = pl.l.Transparency
			end
		end
		-- Zacken wachsen mit der Front, sinken beim Tauen
		local melt = math.clamp((t - meltAt) / 0.45, 0, 1)
		rigApply(rig, CFrame.identity, function(r)
			return math.clamp((t - r.delay) / 0.2, 0, 1) * (1 - melt)
		end, 1 - melt)
		if t < draw then
			-- Glitzer an der Gefrierfront
			local front = a:Lerp(b, t / draw)
			anchor.CFrame = CFrame.new(Vector3.new(front.X, LOW.groundY(ctx, front) + 0.3, front.Z))
			em.Rate = if extras then 60 * ctx.factor else 0
		elseif t >= slideAt and t < slideEnd and ctx.avatarCf then
			-- Schneefahne hinter dem rutschenden Klon
			if not snow then
				snow = true
				em.EmissionDirection = Enum.NormalId.Front
				em.Speed = NumberRange.new(5, 11)
				em.SpreadAngle = Vector2.new(35, 35)
				em.Lifetime = NumberRange.new(0.35, 0.7)
				em.Drag = 1.2
				em.Acceleration = Vector3.new(0, -14, 0)
				em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1.1) })
				em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) })
				em.Color = ColorSequence.new(LOW.RIME, LOW.WHITE)
				em.LightEmission = 0.2
			end
			local av = ctx.avatarCf :: CFrame
			local tail = av.Position - ctx.fwd * 0.9 + Vector3.new(0, 0.3, 0)
			anchor.CFrame = CFrame.lookAt(tail, tail - ctx.fwd * 2 + Vector3.new(0, 1.4, 0))
			em.Rate = 90 * ctx.factor
		else
			em.Rate = 0
		end
		-- Tauen: Platten und Kanten blass (einmal getweent)
		if t >= meltAt and not melting then
			melting = true
			for _, pl in plates do
				tween(pl.p, 0.45, { Transparency = 1 })
				tween(pl.l, 0.3, { Transparency = 1 })
				tween(pl.r, 0.3, { Transparency = 1 })
			end
		end
		return false
	end, function()
		for _, pl in plates do pl.p:Destroy() pl.l:Destroy() pl.r:Destroy() end
		for _, r in rig do r.p:Destroy() end
		em.Rate = 0
		Debris:AddItem(anchor, 1)
	end)
end

-- iceblock: der Gegner steckt in einem Eisblock: Eis-Quader um die Figur (Ice-
-- Material) mit vier Reif-Stegen an den Kanten, hellblauer Leuchtumriss am
-- Original, Frosthauch; folgt der Figur (Server-Rueckstoss, Hopser). Bei
-- `breakAt` zerspringt der Block in Eissplitter (Rig), sonst verschwindet er
-- bei `dur`. Test: freezeAt.
--   at, appear, breakAt, dur, pad, small
BLOCKS.iceblock = function(ctx, s)
	local where = s.at or "target"
	local model = if where == "target" then ctx.targetModel else ctx.selfModel
	local size = sizeAt(ctx, where)
	local pad = s.pad or 0.5
	local full = Vector3.new(size.X + pad, size.Y + pad * 0.5, size.Z + pad)
	if s.small then full *= 0.75 end
	local appear = math.max(0.03, s.appear or 0.1)
	local breakAt: number? = s.breakAt
	local dur = s.dur or 1
	local freezeAt: number? = s.freezeAt
	local fallback = at(ctx, where)
	local block = newPart(Enum.PartType.Block, Vector3.one * 0.1, LOW.ICE, CFrame.new(fallback), 0.12)
	block.Material = Enum.Material.Ice
	block.Name = "IceBlock"
	local edges: { BasePart } = {}
	for _ = 1, 4 do
		table.insert(edges, newPart(Enum.PartType.Block, Vector3.new(0.12, 0.1, 0.12), LOW.RIME, CFrame.new(fallback), 0.3))
	end
	local hl: Highlight? = nil
	if model and model.Parent then
		local h = Instance.new("Highlight")
		h.Adornee = model
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.FillColor = Color3.fromRGB(205, 238, 255)
		h.FillTransparency = 0.55
		h.OutlineColor = LOW.RIME
		h.OutlineTransparency = 0.1
		h.Parent = folder()
		hl = h
	end
	-- Frosthauch (EIN Emitter)
	local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, LOW.RIME, CFrame.new(fallback), 1)
	local em = Instance.new("ParticleEmitter")
	em.Texture = SMOKE_TEX
	em.Rate = if extrasOn(ctx) then 6 * ctx.factor else 0
	em.Speed = NumberRange.new(0.3, 0.8)
	em.SpreadAngle = Vector2.new(180, 180)
	em.Lifetime = NumberRange.new(0.6, 1.0)
	em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1.4) })
	em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	em.Color = ColorSequence.new(LOW.RIME, LOW.ICE)
	em.LightEmission = 0.2
	em.Parent = anchor
	local side = sideOf(ctx)
	local rig: { RigPart } = {}
	local broken = false
	local brokenAt = 0
	local lastK = -1
	runLoop("iceblock", function(tRaw, dt)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		if broken then
			-- Splitter fliegen und verblassen
			local k = math.clamp((t - brokenAt) / 0.5, 0, 1)
			if not freezeAt or tRaw < freezeAt then rigFly(rig, dt, 1 - k) end
			return false
		end
		local c = centerOf(model) or fallback
		local k = easeOutBack(math.clamp(t / appear, 0, 1))
		local sz = full * math.max(0.05, k)
		local cf = CFrame.fromMatrix(c, side, Vector3.yAxis)
		if k ~= lastK then
			lastK = k
			block.Size = sz
			for _, e in edges do e.Size = Vector3.new(0.12, sz.Y + 0.04, 0.12) end
		end
		block.CFrame = cf
		edges[1].CFrame = cf * CFrame.new(sz.X / 2, 0, sz.Z / 2)
		edges[2].CFrame = cf * CFrame.new(-sz.X / 2, 0, sz.Z / 2)
		edges[3].CFrame = cf * CFrame.new(sz.X / 2, 0, -sz.Z / 2)
		edges[4].CFrame = cf * CFrame.new(-sz.X / 2, 0, -sz.Z / 2)
		anchor.CFrame = cf
		if breakAt and t >= breakAt then
			-- zerspringen: Block weg, Eissplitter fliegen auseinander
			broken = true
			brokenAt = t
			block:Destroy()
			for _, e in edges do e:Destroy() end
			if hl then hl:Destroy() hl = nil end
			em.Rate = 0
			local rng = Random.new()
			for _ = 1, scaled(12, ctx.factor) do
				local sh = Vector3.new(0.25 + rng:NextNumber(0, 0.35), 0.3 + rng:NextNumber(0, 0.45), 0.2 + rng:NextNumber(0, 0.25))
				local p = newPart(Enum.PartType.Block, sh, LOW.ICE, cf, 0.1)
				p.Material = Enum.Material.Ice
				p.Name = "IceShard"
				local off = Vector3.new(rng:NextNumber(-0.5, 0.5) * sz.X, rng:NextNumber(-0.5, 0.5) * sz.Y, rng:NextNumber(-0.5, 0.5) * sz.Z)
				rigPart(rig, p, CFrame.new(off) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0), sh, 0, 0.1, true)
			end
			rigApply(rig, cf, function() return 1 end, 1)
			rigShatter(rig, c, 9)
			burstAt(ctx, c, 14, 7, LOW.RIME, true)
			burstAt(ctx, c, 18, 10, LOW.ICE)
		end
		return false
	end, function()
		if block.Parent then block:Destroy() end
		for _, e in edges do if e.Parent then e:Destroy() end end
		for _, r in rig do r.p:Destroy() end
		if hl then hl:Destroy() end
		em.Rate = 0
		Debris:AddItem(anchor, 1.2)
	end)
end

-- clawmarks: Krallenhiebe am Gegner. Je Hieb `claws` parallele Streifen
-- (Zylinder, F31) ziehen in `draw` s schraeg ueber die Vorderseite der Figur
-- (abwechselnd \ und /), Funken; sie gluehen hell und werden in `fade` s zu
-- schwelenden Kratzern (dunkelrot, pulsierend, Glutpartikel), die bis `dur` an
-- der Figur bleiben (folgen ihr). Test: freezeAt.
--   at, count, every, claws, len, draw, fade, dur
BLOCKS.clawmarks = function(ctx, s)
	local where = s.at or "target"
	local model = if where == "target" then ctx.targetModel else ctx.selfModel
	local size = sizeAt(ctx, where)
	local count = s.count or 3
	local every = s.every or 0.14
	local claws = s.claws or 3
	local len = s.len or 2.4
	local draw = math.max(0.03, s.draw or 0.07)
	local fade = s.fade or 0.3
	local dur = s.dur or 1.5
	local freezeAt: number? = s.freezeAt
	local col = ctx.fx.color
	local fallback = at(ctx, where)
	-- Ebene der Marken: Normale = Winkelhalbierende zwischen Richtung zum Angreifer
	-- und Richtung zur Kamera (einmal beim Start, F22) - so sieht der Spieler sie
	-- auch, wenn der Angreifer davor steht (F44)
	local toCam = camFace(fallback, -ctx.fwd)
	local nrm = (-ctx.fwd + toCam)
	nrm = if nrm.Magnitude > 0.1 then nrm.Unit else -ctx.fwd
	local side = Vector3.yAxis:Cross(nrm)
	side = if side.Magnitude > 0.1 then side.Unit else sideOf(ctx)
	local d = 0.17
	type Mark = { p: BasePart, start: Vector3, dir: Vector3, ang: number, t0: number, i: number }
	local marks: { Mark } = {}
	for i = 1, count do
		local ang = (if i % 2 == 1 then -1 else 1) * math.rad(50 + (i - 1) * 5)
		local dir = Vector3.new(math.cos(ang), math.sin(ang), 0)
		local shift = Vector3.new((i - (count + 1) / 2) * 0.3, (i - (count + 1) / 2) * -0.18, 0)
		local depth = size.Z * 0.5 + 0.12
		for c = 1, claws do
			local perp = Vector3.new(-dir.Y, dir.X, 0) * ((c - (claws + 1) / 2) * 0.3)
			local base = Vector3.new(0, size.Y * 0.05, depth) + shift + perp
			local p = newPart(Enum.PartType.Cylinder, Vector3.new(0.05, d, d), LOW.HOT, PARK, 1)
			p.Name = "ClawMark"
			table.insert(marks, { p = p, start = base - dir * (len / 2), dir = dir, ang = ang, t0 = (i - 1) * every, i = i })
		end
	end
	-- Glut (EIN Emitter), schwebt langsam hoch
	local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, col, CFrame.new(fallback), 1)
	local em = Instance.new("ParticleEmitter")
	em.Texture = SPARK_TEX
	em.Rate = 0
	em.Speed = NumberRange.new(0.5, 1.5)
	em.SpreadAngle = Vector2.new(40, 40)
	em.Lifetime = NumberRange.new(0.5, 0.9)
	em.Acceleration = Vector3.new(0, 1.5, 0)
	em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.22), NumberSequenceKeypoint.new(1, 0) })
	em.Color = ColorSequence.new(col, LOW.EMBER)
	em.LightEmission = 0.7
	em.Parent = anchor
	local emberRate = if extrasOn(ctx) then 14 * ctx.factor else 0
	local parts: { BasePart } = table.create(#marks)
	local cfs: { CFrame } = table.create(#marks)
	local sparked: { [number]: boolean } = {}
	local fading = false
	runLoop("clawmarks", function(tRaw)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		local c = centerOf(model) or fallback
		-- lokales System: X seitlich, Y hoch, +Z zum Angreifer (Vorderseite)
		local F = CFrame.fromMatrix(c, side, Vector3.yAxis, nrm)
		anchor.CFrame = F * CFrame.new(0, 0, size.Z * 0.5)
		for n, m in marks do
			local k = math.clamp((t - m.t0) / draw, 0, 1)
			local L = math.max(0.05, len * k)
			local center = m.start + m.dir * (L / 2)
			parts[n] = m.p
			cfs[n] = F * CFrame.new(center) * CFrame.Angles(0, 0, m.ang)
			if k > 0 then
				if not sparked[m.i] then
					sparked[m.i] = true
					burstAt(ctx, F:PointToWorldSpace(m.start + m.dir * (len / 2)), 14, 9, col)
				end
				local g = math.clamp(1 - (t - m.t0 - draw) / fade, 0, 1)
				m.p.Size = Vector3.new(L, d, d)
				m.p.Transparency = 0
				if g > 0.15 then
					m.p.Material = Enum.Material.Neon
					local warm = LOW.EMBER:Lerp(col, math.min(1, g * 2))
					m.p.Color = warm:Lerp(LOW.HOT, math.max(0, g * 2 - 1))
				else
					-- schwelender Kratzer: dunkelrot, pulsiert leicht
					m.p.Material = Enum.Material.SmoothPlastic
					m.p.Color = LOW.EMBER:Lerp(Color3.fromRGB(235, 90, 40), 0.3 + 0.3 * math.sin(t * 9 + m.i))
				end
			end
		end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		em.Rate = if t > draw + 0.1 and t < dur - 0.35 then emberRate else 0
		if t >= dur - 0.3 and not fading then
			fading = true
			for _, m in marks do tween(m.p, 0.28, { Transparency = 1 }) end
		end
		return false
	end, function()
		for _, m in marks do m.p:Destroy() end
		em.Rate = 0
		Debris:AddItem(anchor, 1)
	end)
end

-- pawprints: leuchtende Pfotenspuren (Ballen + drei Zehen) fuehren im leichten
-- Zickzack von den eigenen Fuessen zum Platz vor dem Gegner, eine nach der
-- anderen (`every`, federnd); bei `pulseAt` blitzen alle weiss, ab `dur` - 0,4
-- verblassen sie. Test: freezeAt.
--   count, every, sway, pulseAt, dur
BLOCKS.pawprints = function(ctx, s)
	local count = s.count or 7
	local every = s.every or 0.09
	local sway = s.sway or 0.38
	local pulseAt: number? = s.pulseAt
	local dur = s.dur or 2.8
	local freezeAt: number? = s.freezeAt
	local col = ctx.fx.color
	local side = sideOf(ctx)
	local gap = (ctx.selfSize.Z + ctx.targetSize.Z) * 0.4 + (s.gap or 0.4)
	local a = ctx.selfFeet + ctx.fwd * 1.0
	local b = ctx.targetFeet - ctx.fwd * (gap + 0.3)
	type Print = { parts: { BasePart }, rel: { CFrame }, base: CFrame, t0: number, k: number }
	local prints: { Print } = {}
	for i = 1, count do
		local u = i / count
		local pos = a:Lerp(b, u) + side * (if i % 2 == 0 then sway else -sway)
		pos = Vector3.new(pos.X, LOW.groundY(ctx, pos) + 0.04, pos.Z)
		local base = CFrame.fromMatrix(pos, side, Vector3.yAxis) * CFrame.Angles(0, (if i % 2 == 0 then -0.12 else 0.12), 0)
		local parts: { BasePart } = {}
		local rel: { CFrame } = {}
		-- Ballen (flache Ellipse) + 3 Zehen vorn (vorn = lokal -Z)
		local pad = newPart(Enum.PartType.Cylinder, Vector3.new(0.05, 0.48, 0.4), col, PARK, 1)
		pad.Name = "PawPad"
		table.insert(parts, pad)
		table.insert(rel, CFrame.new(0, 0, 0.1) * CFrame.Angles(0, 0, math.rad(90)))
		for z = -1, 1 do
			local toe = newPart(Enum.PartType.Cylinder, Vector3.new(0.05, 0.17, 0.15), col, PARK, 1)
			toe.Name = "PawToe"
			table.insert(parts, toe)
			table.insert(rel, CFrame.new(z * 0.17, 0, -0.25 - (if z == 0 then 0.05 else 0)) * CFrame.Angles(0, 0, math.rad(90)))
		end
		table.insert(prints, { parts = parts, rel = rel, base = base, t0 = (i - 1) * every, k = -1 })
	end
	runLoop("pawprints", function(tRaw)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		local flash = if pulseAt and t >= pulseAt then math.clamp(1 - (t - pulseAt) / 0.25, 0, 1) else 0
		local fade = math.clamp((t - (dur - 0.4)) / 0.4, 0, 1)
		for _, pr in prints do
			local k = math.clamp((t - pr.t0) / 0.14, 0, 1)
			if k ~= pr.k or flash > 0 or fade > 0 then
				pr.k = k
				local sc = math.max(0.05, easeOutBack(k))
				for n, p in pr.parts do
					local r = pr.rel[n]
					p.Size = Vector3.new(0.05, (if n == 1 then 0.48 else 0.17) * sc, (if n == 1 then 0.4 else 0.15) * sc)
					p.CFrame = pr.base * CFrame.new(r.Position * sc) * r.Rotation
					p.Transparency = if k > 0 then 0.25 * (1 - flash) + fade * 0.75 else 1
					p.Color = col:Lerp(LOW.WHITE, flash)
				end
			end
		end
		return false
	end, function()
		for _, pr in prints do for _, p in pr.parts do p:Destroy() end end
	end)
end

-- lensbeam: Brennglas. Eine grosse Lupe (Messingring aus 12 Zylinder-Stuecken,
-- Glas, Griff, Knauf) waechst in `appear` s aus der Pfote des Klons (seine
-- kleine Lupe - Teile mit "acc_lupe" im Namen - verschwindet so lange) vor
-- seinen Kopf; ab `beamAt` faellt eine weiche Lichtsaeule von oben in die Linse,
-- der gebuendelte Kegel trifft als Brennpunkt die Vorderseite des Gegners: der
-- Punkt wandert suchend, Rauch steigt, er wird weiss; bei `burnAt` Flammenstoss
-- (Funken, Feuerball, Glanz auf dem Glas), Strahlen aus; dann kehrt die Lupe
-- in `away` s in die Pfote zurueck. Ohne Klon: Lupe vor der eigenen Figur
-- (Echo, `small`). Test: freezeAt.
--   lens, appear, beamAt, burnAt, away, dur, small
BLOCKS.lensbeam = function(ctx, s)
	local lens = s.lens or 1.1
	local appear = math.max(0.03, s.appear or 0.25)
	local beamAt = s.beamAt or appear
	local burnAt = s.burnAt or 1.0
	local away = math.max(0.05, s.away or 0.25)
	local dur = s.dur or (burnAt + away + 0.15)
	local freezeAt: number? = s.freezeAt
	local col2 = ctx.fx.color2
	local up = Vector3.yAxis
	local H = ctx.selfSize.Y
	local targetModel = ctx.targetModel
	local tSize = ctx.targetSize

	-- Lupe: lokale Lagen (Linsenmitte = Ursprung, Z = Normale, Griff nach -Y)
	type Piece = { p: BasePart, rel: CFrame, size: Vector3 }
	local pieces: { Piece } = {}
	local d = 0.15 * lens
	local n = 12
	for i = 1, n do
		local a0 = (i - 1) / n * TAU
		local a1 = i / n * TAU
		local p0 = Vector3.new(math.cos(a0), math.sin(a0), 0) * lens
		local p1 = Vector3.new(math.cos(a1), math.sin(a1), 0) * lens
		local mid = (p0 + p1) / 2
		local segLen = (p1 - p0).Magnitude + 0.5 * d
		local p = newPart(Enum.PartType.Cylinder, Vector3.new(segLen, d, d), LOW.GOLD, PARK, 1)
		p.Material = Enum.Material.SmoothPlastic
		p.Reflectance = 0.15
		p.Name = "LensRing"
		table.insert(pieces, { p = p, rel = CFrame.lookAt(mid, p1, Vector3.zAxis) * CFrame.Angles(0, math.rad(90), 0), size = p.Size })
	end
	local glass = newPart(Enum.PartType.Cylinder, Vector3.new(0.06, lens * 1.9, lens * 1.9), Color3.fromRGB(205, 240, 255), PARK, 1)
	glass.Material = Enum.Material.Glass
	glass.Reflectance = 0.1
	glass.Name = "LensGlass"
	table.insert(pieces, { p = glass, rel = CFrame.Angles(0, math.rad(90), 0), size = glass.Size })
	local grip = newPart(Enum.PartType.Cylinder, Vector3.new(lens * 1.25, d * 1.3, d * 1.3), LOW.BRASS, PARK, 1)
	grip.Material = Enum.Material.SmoothPlastic
	grip.Name = "LensGrip"
	table.insert(pieces, { p = grip, rel = CFrame.new(0, -(lens + lens * 0.62), 0) * CFrame.Angles(0, 0, math.rad(90)), size = grip.Size })
	local knob = newPart(Enum.PartType.Ball, Vector3.one * d * 2, LOW.BRASS, PARK, 1)
	knob.Material = Enum.Material.SmoothPlastic
	knob.Name = "LensKnob"
	table.insert(pieces, { p = knob, rel = CFrame.new(0, -(lens + lens * 1.25), 0), size = knob.Size })
	local parts: { BasePart } = table.create(#pieces)
	local cfs: { CFrame } = table.create(#pieces)

	-- kleine Lupe des Klons ausblenden, solange die grosse da ist
	local smallParts: { { p: BasePart, tr: number } } = {}
	local smallGlass: BasePart? = nil
	local function findSmall()
		local m = ctx.avatarModel
		if not m or #smallParts > 0 then return end
		for _, p in m:GetDescendants() do
			if p:IsA("BasePart") and p.Name:find("acc_lupe", 1, true) then
				table.insert(smallParts, { p = p, tr = p.Transparency })
				if p.Name:find("glas", 1, true) then smallGlass = p end
			end
		end
	end
	local function smallShown(v: boolean)
		for _, e in smallParts do
			if e.p.Parent then e.p.Transparency = if v then e.tr else 1 end
		end
	end
	local function pawPos(): Vector3
		if smallGlass and smallGlass.Parent then return smallGlass.Position end
		local av = ctx.avatarCf or CFrame.lookAt(ctx.selfFeet, ctx.selfFeet + ctx.fwd)
		return (av * CFrame.new(-0.5, H * 0.45, -0.6)).Position
	end
	local function hoverPos(): Vector3
		local av = ctx.avatarCf or CFrame.lookAt(ctx.selfFeet, ctx.selfFeet + ctx.fwd)
		return (av * CFrame.new(0.3, H * 1.0, -H * 0.55)).Position
	end
	local function spotBase(): Vector3
		local c = centerOf(targetModel) or ctx.targetPos
		return c - ctx.fwd * (tSize.Z * 0.5 + 0.05) + up * (tSize.Y * 0.1)
	end

	-- Strahlen (Beams an einem Anker), Brennpunkt, Rauch
	local beamAnchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, LOW.HOT, PARK, 1)
	local function att(): Attachment
		local a = Instance.new("Attachment")
		a.Parent = beamAnchor
		return a
	end
	local sunA, sunB, focA, focB = att(), att(), att(), att()
	local function beam(a: Attachment, b: Attachment, w0: number, w1: number, t0: number, t1: number, emission: number): Beam
		local bm = Instance.new("Beam")
		bm.Attachment0 = a
		bm.Attachment1 = b
		bm.Width0 = w0
		bm.Width1 = w1
		bm.FaceCamera = true
		bm.Segments = 1
		bm.LightEmission = emission
		bm.LightInfluence = 0
		bm.Color = ColorSequence.new(Color3.fromRGB(255, 246, 210), LOW.HOT)
		bm.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, t0), NumberSequenceKeypoint.new(1, t1) })
		bm.Enabled = false
		bm.Parent = beamAnchor
		return bm
	end
	local sun = beam(sunA, sunB, 2.4 * lens, 1.9 * lens, 0.82, 0.6, 0.35)
	local focus = beam(focA, focB, 1.75 * lens, 0.14, 0.45, 0.1, 0.55)
	local spot = newPart(Enum.PartType.Ball, Vector3.one * 0.2, LOW.HOT, PARK, 1)
	spot.Name = "LensSpot"
	local glow = newPart(Enum.PartType.Ball, Vector3.one * 0.6, col2, PARK, 1)
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = SMOKE_TEX
	smoke.Rate = 0
	smoke.Speed = NumberRange.new(0.8, 1.6)
	smoke.SpreadAngle = Vector2.new(25, 25)
	smoke.Lifetime = NumberRange.new(0.6, 1.1)
	smoke.Acceleration = Vector3.new(0, 1.5, 0)
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1.1) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	smoke.Color = ColorSequence.new(Color3.fromRGB(120, 110, 100), Color3.fromRGB(70, 60, 60))
	smoke.LightEmission = 0
	smoke.Parent = spot

	local burned = false
	local gone = false
	local lastSc = -1
	runLoop("lensbeam", function(tRaw)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		if gone then return false end
		findSmall()
		-- Lage und Groesse der Lupe
		local sc: number
		local lensPos: Vector3
		if t < appear then
			local k = easeOutBack(t / appear)
			sc = lerpN(0.3, 1, k)
			lensPos = pawPos():Lerp(hoverPos(), k)
			smallShown(false)
		elseif t < burnAt + 0.1 then
			sc = 1
			lensPos = hoverPos()
		else
			local k = easeInOutSine(math.clamp((t - burnAt - 0.1) / away, 0, 1))
			sc = lerpN(1, 0.3, k)
			lensPos = hoverPos():Lerp(pawPos(), k)
			if k >= 1 then
				gone = true
				smallShown(true)
				for _, pc in pieces do pc.p.Transparency = 1 end
				return false
			end
		end
		local spotPos = spotBase()
		local toSpot = spotPos - lensPos
		local nrm = (up + (if toSpot.Magnitude > 0.1 then toSpot.Unit else ctx.fwd)).Unit
		local L = CFrame.lookAt(lensPos, lensPos + nrm)
		if sc ~= lastSc then
			lastSc = sc
			for _, pc in pieces do pc.p.Size = pc.size * sc end
		end
		for i, pc in pieces do
			parts[i] = pc.p
			cfs[i] = L * CFrame.new(pc.rel.Position * sc) * pc.rel.Rotation
			if pc.p.Transparency > 0.99 and t > 0 then
				pc.p.Transparency = if pc.p == glass then 0.4 else 0
			end
		end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		-- Strahlen und Brennpunkt
		if t >= beamAt and t < burnAt then
			local g = math.clamp((t - beamAt) / math.max(0.05, burnAt - beamAt), 0, 1)
			local w = math.clamp((burnAt - t) / 0.3, 0, 1)
			local wander = sideOf(ctx) * (0.3 * math.sin(t * 5.3) * w) + up * (0.25 * math.cos(t * 3.9) * w)
			local sp = spotPos + wander
			sun.Enabled = true
			focus.Enabled = true
			sunA.WorldPosition = lensPos + up * 14
			sunB.WorldPosition = lensPos
			focA.WorldPosition = lensPos
			focB.WorldPosition = sp
			spot.CFrame = CFrame.new(sp)
			spot.Size = Vector3.one * (0.2 + 0.3 * g)
			spot.Transparency = 0
			spot.Color = col2:Lerp(LOW.WHITE, g)
			glow.CFrame = CFrame.new(sp)
			glow.Size = Vector3.one * (0.5 + 0.9 * g)
			glow.Transparency = 0.85 - 0.25 * g
			smoke.Rate = if extrasOn(ctx) then (6 + 16 * g) * ctx.factor else 0
		elseif t >= burnAt and not burned then
			-- Flammenstoss: Funken, Feuerball, Rauchpuff, Glanz auf dem Glas
			burned = true
			sun.Enabled = false
			focus.Enabled = false
			spot.Transparency = 1
			glow.Transparency = 1
			smoke.Rate = 0
			burstAt(ctx, spotPos, 26, 10, col2)
			burstAt(ctx, spotPos + up * 0.3, 10, 3, Color3.fromRGB(90, 80, 80), true)
			local fire = newPart(Enum.PartType.Ball, Vector3.one * 0.5, col2:Lerp(LOW.WHITE, 0.45), CFrame.new(spotPos), 0.3)
			fire.Name = "LensFire"
			tween(fire, 0.22, { Size = Vector3.one * 1.9, Transparency = 1 }, Enum.EasingStyle.Quad)
			Debris:AddItem(fire, 0.3)
			twinkle(lensPos + up * (lens * 0.7), lens * 1.1, LOW.WHITE, 0.3)
			glass.Color = LOW.WHITE
			glass.Transparency = 0.1
			tween(glass, 0.25, { Color = Color3.fromRGB(205, 240, 255), Transparency = 0.4 })
		end
		return false
	end, function()
		smallShown(true)
		for _, pc in pieces do pc.p:Destroy() end
		spot:Destroy()
		glow:Destroy()
		beamAnchor:Destroy()
	end)
end

-- djset: Bass-Drop. Unter dem DJ dreht sich eine Schallplatte (dunkle Scheibe,
-- rosa Rillen und Label als SurfaceGui), rund um die Arena stehen `bars`
-- Equalizer-Balken (Neon, rosa/weiss/violett, Luecke zur Kamera, F44), die bei
-- jedem Eintrag in `beats` hochzucken (Bodenring, Kopfhoerer-Muscheln des Klons
-- leuchten kurz); ab `buildAt` steigen alle Balken zitternd an, die Platte rast;
-- bei `dropAt` der Drop: Label blitzt, Balken schlagen voll aus, Schockwelle
-- (`wave` + Bodenring bis zum Zaun), Streusel am Gegner; danach sinken die
-- Balken, die Platte bremst und verblasst. Test: freezeAt.
--   beats, buildAt, dropAt, dur, bars, radius, disc
BLOCKS.djset = function(ctx, s)
	local beats: { number } = s.beats or { 0.5, 1.0, 1.5 }
	local buildAt = s.buildAt or 1.55
	local dropAt = s.dropAt or 2.0
	local dur = s.dur or 2.9
	local nBars = scaled(s.bars or 14, ctx.factor)
	local R = radiusOf(s.radius, 7.5)
	local D = s.disc or 4.6
	local freezeAt: number? = s.freezeAt
	local col = ctx.fx.color
	local col2 = ctx.fx.color2
	local feet = ctx.selfFeet
	local center = Vector3.new(feet.X, feet.Y + 0.07, feet.Z)
	local arena = groundAt(ctx, "arena")

	-- Schallplatte: Scheibe + unsichtbare Platte mit SurfaceGui (Rillen, Label)
	local disc = newPart(Enum.PartType.Cylinder, Vector3.new(0.14, 0.2, 0.2), LOW.VINYL, CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)), 0)
	disc.Material = Enum.Material.SmoothPlastic
	disc.Reflectance = 0.08
	disc.Name = "DjDisc"
	local plate = newPart(Enum.PartType.Block, Vector3.new(0.2, 0.05, 0.2), col, CFrame.new(center + Vector3.new(0, 0.08, 0)), 1)
	plate.Name = "DjLabel"
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 32
	gui.LightInfluence = 0
	gui.Brightness = 1.25
	gui.Adornee = plate
	gui.Parent = plate
	local function roundFrame(parent: Instance, scale: number, color: Color3?, stroke: number?): Frame
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.5, 0.5)
		f.Size = UDim2.fromScale(scale, scale)
		f.BorderSizePixel = 0
		f.BackgroundTransparency = if color then 0.05 else 1
		if color then f.BackgroundColor3 = color end
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = f
		if stroke then
			local st = Instance.new("UIStroke")
			st.Color = col
			st.Thickness = stroke
			st.Transparency = 0.15
			st.Parent = f
		end
		f.Parent = parent
		return f
	end
	roundFrame(gui, 0.9, nil, 4)
	roundFrame(gui, 0.76, nil, 3)
	roundFrame(gui, 0.62, nil, 3)
	roundFrame(gui, 0.5, nil, 2)
	local label = roundFrame(gui, 0.34, col, nil)
	for _, rot in { 45, 135 } do
		local b = Instance.new("Frame")
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.Position = UDim2.fromScale(0.5, 0.5)
		b.Size = UDim2.fromScale(0.7, 0.12)
		b.Rotation = rot
		b.BackgroundColor3 = LOW.WHITE
		b.BackgroundTransparency = 0.2
		b.BorderSizePixel = 0
		b.Parent = label
	end
	roundFrame(gui, 0.07, LOW.VINYL, nil)

	-- Equalizer-Balken rund um die Arena, Luecke zur Kamera (F44)
	local camDir = camFace(arena, -ctx.fwd)
	local baseAng = math.atan2(camDir.Z, camDir.X)
	local gapHalf = math.rad(38)
	local span = TAU - 2 * gapHalf
	type Bar = { p: BasePart, pos: Vector3, h: number, goal: number, seed: number }
	local bars: { Bar } = {}
	local palette = { col, LOW.WHITE, col2 }
	for i = 1, nBars do
		local ang = baseAng + gapHalf + span * (i - 0.5) / nBars
		local pos = Vector3.new(arena.X + math.cos(ang) * R, arena.Y, arena.Z + math.sin(ang) * R)
		local p = newPart(Enum.PartType.Block, Vector3.new(0.55, 0.3, 0.3), palette[(i - 1) % 3 + 1], CFrame.new(pos), 0.3)
		p.Name = "DjBar"
		table.insert(bars, { p = p, pos = pos, h = 0.3, goal = 0.3, seed = i * 0.37 })
	end
	local function hash(a: number, b: number): number
		local x = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
		return x - math.floor(x)
	end
	-- Kopfhoerer-Muscheln des Klons (Teile mit "cup" oder "kopfhoerer" im Namen)
	local cups: { { p: BasePart, mat: Enum.Material, col: Color3 } } = {}
	local function findCups()
		if #cups > 0 then return end
		local m = ctx.avatarModel
		if m then
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") and (d.Name:find("cup", 1, true) or d.Name:find("kopfhoerer", 1, true)) then
					table.insert(cups, { p = d, mat = d.Material, col = d.Color })
				end
			end
		end
	end
	local cupUntil = -1
	local function pulseCups(t: number)
		findCups()
		cupUntil = t + 0.14
		for _, c in cups do
			if c.p.Parent then c.p.Material = Enum.Material.Neon c.p.Color = LOW.DEEPPINK end
		end
	end
	local function restoreCups()
		for _, c in cups do
			if c.p.Parent then c.p.Material = c.mat c.p.Color = c.col end
		end
	end

	local spin = 0
	local dropped = false
	local lastBeatCount = 0
	local labelFlash = 0
	runLoop("djset", function(tRaw, dt)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		local step = if freezeAt and tRaw >= freezeAt then 0 else dt
		-- Platte: dreht (33 rpm), rast im Build-up, bremst nach dem Drop
		local rps = 0.6
		if t >= buildAt and t < dropAt then
			rps = 0.6 + 2.2 * (t - buildAt) / math.max(0.1, dropAt - buildAt)
		elseif t >= dropAt then
			rps = math.max(0, 2.8 - (t - dropAt) * 4)
		end
		spin += TAU * rps * step
		local grow = easeOutBack(math.clamp(t / 0.25, 0, 1))
		disc.Size = Vector3.new(0.14, math.max(0.1, D * grow), math.max(0.1, D * grow))
		disc.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(spin, 0, 0)
		plate.Size = Vector3.new(math.max(0.1, D * grow), 0.05, math.max(0.1, D * grow))
		plate.CFrame = CFrame.new(center + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, spin, 0)
		-- Beats: Balken-Ziele neu wuerfeln, Bodenring, Muscheln
		local nBeat = 0
		for i, bt in beats do if t >= bt then nBeat = i end end
		if nBeat > lastBeatCount then
			lastBeatCount = nBeat
			for i, b in bars do b.goal = 1.0 + 3.0 * hash(i, nBeat) end
			BLOCKS.ring(ctx, { at = "self", ground = true, radius = D * 0.5 + 2.5 + nBeat * 0.6, dur = 0.4 })
			pulseCups(t)
		end
		if cupUntil >= 0 and t > cupUntil then
			cupUntil = -1
			restoreCups()
		end
		-- Build-up: alle Balken steigen zitternd
		if t >= buildAt and t < dropAt then
			local k = (t - buildAt) / math.max(0.1, dropAt - buildAt)
			for _, b in bars do b.goal = 1.5 + 2.7 * k + 0.3 * math.sin(t * 40 + b.seed) end
		end
		if t >= dropAt and not dropped then
			dropped = true
			for _, b in bars do b.goal = 5.2 b.h = 5.2 end
			labelFlash = 1
			BLOCKS.wave(ctx, { at = "self", radius = 12, dur = 0.5 })
			BLOCKS.ring(ctx, { at = "self", ground = true, toArena = true, radius = "fence", dur = 0.55 })
			LOW.sprinkles(ctx, ctx.targetPos + Vector3.new(0, ctx.targetSize.Y * 0.4, 0), 40, 0.8)
			pulseCups(t)
		end
		if t >= dropAt + 0.12 then
			for _, b in bars do b.goal = 0.3 end
		end
		-- Balken federn zu ihrem Ziel; nach dem Drop verblassen sie
		local alpha = if t >= dropAt + 0.3 then math.clamp(1 - (t - dropAt - 0.3) / 0.5, 0, 1) else 1
		local appear = math.clamp(t / 0.3, 0, 1)
		for _, b in bars do
			b.h += (b.goal - b.h) * math.min(1, step * 14)
			local h = math.max(0.15, b.h * appear)
			b.p.Size = Vector3.new(0.55, h, 0.3)
			local mid = b.pos + Vector3.new(0, h / 2, 0)
			b.p.CFrame = CFrame.lookAt(mid, Vector3.new(arena.X, mid.Y, arena.Z))
			b.p.Transparency = 0.3 + 0.7 * (1 - alpha)
		end
		-- Label-Blitz beim Drop, Platte verblasst am Ende
		if labelFlash > 0 then
			labelFlash = math.max(0, labelFlash - step * 5)
			label.BackgroundColor3 = col:Lerp(LOW.WHITE, labelFlash)
		end
		if t >= dur - 0.4 then
			local f = (t - (dur - 0.4)) / 0.4
			disc.Transparency = f
			gui.Enabled = f < 0.5
		end
		return false
	end, function()
		restoreCups()
		disc:Destroy()
		plate:Destroy()
		for _, b in bars do b.p:Destroy() end
	end)
end

-- ---------------------------------------------------------------------------
-- Schub 2 (25.10.2026): Muenzregen (Grizzly), Shuriken-Sturm (Ninja),
-- Wurzelwall (Uralter), Regenbogenbruecke (Regenbogen) - Stufe 3, ohne
-- Kamerafahrt. Helfer wieder in LOW.
-- ---------------------------------------------------------------------------

LOW.BARK = Color3.fromRGB(96, 64, 40)          -- Wurzelrinde
LOW.MOSS = Color3.fromRGB(124, 196, 108)       -- Moos, Blaetter (wie die Blattkrone)
LOW.STEEL = Color3.fromRGB(225, 227, 234)      -- Shuriken, Klinge
LOW.NINJARED = Color3.fromRGB(231, 63, 75)     -- Stirnband
LOW.INK = Color3.fromRGB(34, 28, 62)           -- Schattenklone
LOW.DARKGOLD = Color3.fromRGB(190, 150, 60)    -- dunklere Muenzen
LOW.COINGOLD = Color3.fromRGB(255, 200, 60)    -- Muenzen (satt, wenig Reflexion - sonst blass vor dem Himmel)

-- Punkt auf der Bruecke von a nach b (kubische Bezier wie ein Beam mit
-- CurveSize `c`: Tangenten am Anfang hoch-vorwaerts, am Ende runter-vorwaerts;
-- `tilt` = Vorwaertsanteil der Tangenten). `moves` (Pose mit `curve`) und
-- `rainbow` nutzen dieselbe Formel - der Baerchi laeuft genau auf den Baendern.
LOW.bridge = function(a: Vector3, b: Vector3, fwd: Vector3, c: number, tilt: number, u: number): Vector3
	local up = Vector3.yAxis
	local t0 = (fwd * tilt + up).Unit
	local t1 = (fwd * tilt - up).Unit
	local p1 = a + t0 * c
	local p2 = b - t1 * c
	local v = 1 - u
	return a * (v * v * v) + p1 * (3 * v * v * u) + p2 * (3 * v * u * u) + b * (u * u * u)
end

-- Zylinder-Stueck von p nach q (F31: Laenge + 0,5 d, Achse X entlang der Strecke)
LOW.tube = function(p: BasePart, a: Vector3, b: Vector3, d: number, f: number)
	local dir = b - a
	local L = math.max(0.05, dir.Magnitude * f)
	local u = if dir.Magnitude > 0.01 then dir.Unit else Vector3.yAxis
	p.Size = Vector3.new(L + 0.5 * d, d, d)
	p.CFrame = CFrame.lookAt(a + u * (L / 2), a + u * (L / 2 + 1), if math.abs(u.Y) > 0.9 then Vector3.xAxis else Vector3.yAxis) * CFrame.Angles(0, math.rad(90), 0)
end

-- Ein Vierstern-Shuriken (zwei gekreuzte Klingen + roter Kern) als Modell;
-- `set(cf)` setzt ihn (lokale Ebene XY, Normale Z).
LOW.shuriken = function(size: number): (Model, (CFrame) -> ())
	local m = Instance.new("Model")
	m.Name = "Shuriken"
	local parts: { BasePart } = {}
	local rels: { CFrame } = {}
	for _, ang in { 0, 90 } do
		local blade = Instance.new("Part")
		prepPart(blade, LOW.STEEL, PARK, 0)
		blade.Material = Enum.Material.SmoothPlastic
		blade.Reflectance = 0.2
		blade.Size = Vector3.new(size, size * 0.2, 0.06)
		blade.Parent = m
		table.insert(parts, blade)
		table.insert(rels, CFrame.Angles(0, 0, math.rad(ang)))
	end
	local core = Instance.new("Part")
	core.Shape = Enum.PartType.Ball
	prepPart(core, LOW.NINJARED, PARK, 0)
	core.Size = Vector3.one * size * 0.22
	core.Parent = m
	table.insert(parts, core)
	table.insert(rels, CFrame.identity)
	m.Parent = folder()
	local cfs: { CFrame } = table.create(#parts)
	return m, function(cf: CFrame)
		for i, p in parts do cfs[i] = cf * rels[i] end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

-- coinshower: Muenzregen. Bei `burstAt` spritzen `count` Goldmuenzen (flache
-- Zylinder, drehen sich) aus den Fuessen des Gegners nach oben (Funken), fliegen
-- dann nacheinander im Bogen zum Angreifer und tuermen sich dort zu einem
-- Haufen (Goldhuegel + liegende Muenzen); Glitzer am Haufen, Medaille und Rubin
-- des Klons (acc_medal, acc_ruby) blitzen bei jeder dritten Muenze; am Ende
-- sinkt der Haufen weg. `small`: Echo. Test: freezeAt.
--   count, burstAt, rise, fly, every, dur, small
BLOCKS.coinshower = function(ctx, s)
	local count = scaled(s.count or 18, ctx.factor)
	local eruptAt = s.burstAt or 0
	local rise = s.rise or 0.3
	local fly = s.fly or 0.55
	local every = s.every or 0.045
	local dur = s.dur or 2.0
	local small = s.small == true
	local freezeAt: number? = s.freezeAt
	local up = Vector3.yAxis
	local targetModel = ctx.targetModel
	local selfFeet = ctx.selfFeet
	local pileScale = if small then 0.5 else 1
	type Coin = { p: BasePart, t0: number, v: Vector3, axis: Vector3, start: Vector3?, done: boolean, dx: number, dz: number }
	local coins: { Coin } = {}
	local rng = Random.new(3)
	for i = 1, count do
		local p = newPart(Enum.PartType.Cylinder, Vector3.new(0.12, 0.75, 0.75), if i % 3 == 0 then LOW.DARKGOLD else LOW.COINGOLD, PARK, 1)
		p.Material = Enum.Material.SmoothPlastic
		p.Reflectance = 0.08
		p.Name = "Coin"
		local a = rng:NextNumber(-1.2, 1.2)
		local spread = rng:NextNumber(1.5, 3.5)
		-- Startgeschwindigkeit: steil hoch, leicht zum Angreifer hin (nicht im Gegner bleiben)
		table.insert(coins, {
			p = p, t0 = eruptAt + (i - 1) * every,
			v = (-ctx.fwd) * (math.cos(a) * spread) + sideOf(ctx) * (math.sin(a) * spread) + up * rng:NextNumber(9, 12),
			axis = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)).Unit,
			start = nil, done = false, dx = rng:NextNumber(-0.5, 0.5), dz = rng:NextNumber(-0.4, 0.4),
		})
	end
	-- Goldhaufen (Ellipsoid) + liegende Muenzen obenauf
	local pile = newPart(Enum.PartType.Block, Vector3.one * 0.1, LOW.GOLD, CFrame.new(selfFeet), 1)
	pile.Material = Enum.Material.SmoothPlastic
	pile.Reflectance = 0.2
	pile.Name = "CoinPile"
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = pile
	local resting: { BasePart } = {}
	local restCf: { CFrame } = {}
	for i = 1, 6 do
		local p = newPart(Enum.PartType.Cylinder, Vector3.new(0.12, 0.75, 0.75), if i % 2 == 0 then LOW.DARKGOLD else LOW.COINGOLD, PARK, 1)
		p.Material = Enum.Material.SmoothPlastic
		p.Reflectance = 0.08
		p.Name = "CoinRest"
		table.insert(resting, p)
		local a = i / 6 * TAU
		table.insert(restCf, CFrame.new(math.cos(a) * 0.8 * pileScale, 0, math.sin(a) * 0.7 * pileScale) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, TAU), math.rad(90) + rng:NextNumber(-0.3, 0.3)))
	end
	-- Glitzer am Haufen (EIN Emitter)
	local glitAnchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, LOW.GOLD, CFrame.new(selfFeet + up * 0.5), 1)
	local glit = Instance.new("ParticleEmitter")
	glit.Texture = SPARK_TEX
	glit.Rate = 0
	glit.Speed = NumberRange.new(1, 3)
	glit.SpreadAngle = Vector2.new(70, 70)
	glit.Lifetime = NumberRange.new(0.4, 0.8)
	glit.Drag = 2
	glit.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	glit.Color = ColorSequence.new(LOW.WHITE, LOW.GOLD)
	glit.LightEmission = 0.7
	glit.Parent = glitAnchor
	-- Medaille/Rubin des Klons
	local medals: { BasePart } = {}
	local function findMedals()
		local m = ctx.avatarModel
		if not m or #medals > 0 then return end
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and (d.Name:find("acc_medal", 1, true) or d.Name:find("acc_ruby", 1, true)) then table.insert(medals, d) end
		end
	end
	local parts: { BasePart } = table.create(count)
	local cfs: { CFrame } = table.create(count)
	local arrived = 0
	local burstDone = false
	local lastPile = -1
	runLoop("coinshower", function(tRaw)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		local tFeet = (centerOf(targetModel) or ctx.targetPos) - up * (ctx.targetSize.Y * 0.5)
		local pileTop = selfFeet + up * (0.35 * pileScale)
		if t >= eruptAt and not burstDone then
			burstDone = true
			burstAt(ctx, tFeet + up * 0.4, 20, 8, LOW.GOLD)
		end
		local n = 0
		for _, c in coins do
			local tau = t - c.t0
			local cf: CFrame
			if tau < 0 or c.done then
				cf = PARK
			elseif tau < rise then
				-- 1. nach oben spritzen (ballistisch)
				if not c.start then c.start = tFeet + up * 0.3 - ctx.fwd * (ctx.targetSize.Z * 0.45) + Vector3.new(c.dx, 0, c.dz) end
				local pos = (c.start :: Vector3) + c.v * tau + up * (-18 * tau * tau)
				cf = CFrame.new(pos) * CFrame.fromAxisAngle(c.axis, tau * 14)
				c.p.Transparency = 0
			else
				-- 2. im Bogen zum Angreifer, dann im Haufen verschwinden
				local k = math.clamp((tau - rise) / fly, 0, 1)
				local from = (c.start :: Vector3) + c.v * rise + up * (-18 * rise * rise)
				local to = pileTop + Vector3.new(c.dx * 0.8, 0, c.dz * 0.8)
				local ctrl = (from + to) / 2 + up * 3.5
				local pos = bez2(from, ctrl, to, k)
				cf = CFrame.new(pos) * CFrame.fromAxisAngle(c.axis, tau * 14)
				if k >= 1 then
					c.done = true
					c.p.Transparency = 1
					arrived += 1
					if not freezeAt or tRaw < freezeAt then
						glit:Emit(scaled(4, ctx.factor))
						if arrived % 3 == 0 then
							findMedals()
							for _, md in medals do twinkle(md.Position - ctx.fwd * 0.15, 0.9, LOW.WHITE, 0.3) end
						end
					end
					cf = PARK
				end
			end
			n += 1
			parts[n] = c.p
			cfs[n] = cf
		end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		-- Haufen waechst mit den angekommenen Muenzen, sinkt am Ende
		local k = arrived / math.max(1, count)
		local sinkLen = if small then 0.12 else 0.6
		if t >= dur - sinkLen then k *= 1 - math.clamp((t - (dur - sinkLen)) / sinkLen, 0, 1) end
		if math.abs(k - lastPile) > 0.002 then
			lastPile = k
			local sc = math.max(0.02, k) * pileScale
			pile.Size = Vector3.new(2.6 * sc, 0.9 * sc, 2.2 * sc)
			pile.CFrame = CFrame.new(selfFeet + up * (0.3 * sc))
			pile.Transparency = if k > 0.01 then 0 else 1
			for i, p in resting do
				local show = k > i / 7
				p.Transparency = if show then 0 else 1
				if show then p.CFrame = CFrame.new(selfFeet + up * (0.72 * sc)) * restCf[i] end
			end
		end
		glit.Rate = if arrived > 0 and arrived < count then 10 * ctx.factor else 0
		return false
	end, function()
		for _, c in coins do c.p:Destroy() end
		for _, p in resting do p:Destroy() end
		pile:Destroy()
		glit.Rate = 0
		Debris:AddItem(glitAnchor, 1)
	end)
end

-- ninjaclones: Schattenklone + Shuriken-Sturm. Ab `appearAt` (+ i * `every`)
-- erscheinen `count` dunkle Klone des Angreifers (inkBear, Stirnband rot) in
-- Rauch-Puffs auf einem Ring (`radius`) um den Gegner - hinten und seitlich,
-- nie zwischen Kamera und Gegner (F44); ab `throwAt` (+ i * `every`) wirft
-- jeder einen Shuriken (Vierstern, dreht sich), der im Bogen um den Gegner
-- fliegt und sich rund um ihn in den Boden bohrt (Funken); bei `dashAt`
-- stuermen alle gleichzeitig durch den Gegner (Lichtstreifen) und vergehen in
-- Puffs; bei `flashAt` blitzen die Shuriken und sinken ein. `single`: Echo -
-- ein Shuriken fliegt von self in den Boden vor dem Gegner. Test: freezeAt.
--   count, radius, appearAt, every, throwAt, flight, dashAt, dash, flashAt, dur, single
BLOCKS.ninjaclones = function(ctx, s)
	local count = s.count or 3
	local R = s.radius or 4.5
	local appearAt = s.appearAt or 0
	local every = s.every or 0.2
	local throwAt = s.throwAt or 0.7
	local flight = s.flight or 0.35
	local dashAt = s.dashAt or 1.5
	local dash = s.dash or 0.2
	local flashAt = s.flashAt or 1.8
	local dur = s.dur or 2.5
	local single = s.single == true
	local freezeAt: number? = s.freezeAt
	local up = Vector3.yAxis
	local tFeet = ctx.targetFeet
	local side = sideOf(ctx)
	local puff = smokeAt(ctx, nil, dur)
	-- Klone auf dem Ring: Winkel ab der Angreifer-Richtung (-fwd = 0 Grad),
	-- 110 / 250 / 180 Grad: hinten und seitlich, nicht vor der Kamera (F44)
	type Clone = { m: Model, off: CFrame, feet: Vector3, fwd: Vector3, t0: number, shown: boolean, gone: boolean, streak: BasePart? }
	local clones: { Clone } = {}
	-- Ring relativ zur Kamera-Richtung (0 Grad = zur Kamera), alle Klone auf der
	-- abgewandten Seite (F44); einmal beim Start (F22)
	local camDir = camFace(tFeet, -ctx.fwd)
	local camSide = up:Cross(camDir)
	camSide = if camSide.Magnitude > 0.01 then camSide.Unit else side
	local function ringPoint(deg: number): Vector3
		local a = math.rad(deg)
		local dir = camDir * math.cos(a) + camSide * math.sin(a)
		return tFeet + dir * R
	end
	if not single then
		local angles = { 180, 125, 235, 150, 210 }
		for i = 1, count do
			local spot = ringPoint(angles[(i - 1) % #angles + 1])
			local look = Vector3.new(tFeet.X - spot.X, 0, tFeet.Z - spot.Z)
			local fwd = if look.Magnitude > 0.1 then look.Unit else ctx.fwd
			local m, off = inkBear(ctx.selfModel, ctx.selfSize, LOW.INK, 0.1, spot, fwd, nil)
			m.Name = "SkillFXNinja"
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") and (d.Name:find("band", 1, true) or d.Name:find("knot", 1, true)) then d.Color = LOW.NINJARED end
			end
			m:PivotTo(PARK)
			table.insert(clones, { m = m, off = off, feet = spot, fwd = fwd, t0 = appearAt + (i - 1) * every, shown = false, gone = false, streak = nil })
		end
	end
	-- Shuriken: Start (Pfote des Klons bzw. self), Scheitel, Ziel (Boden um den Gegner)
	type Star = { m: Model, set: (CFrame) -> (), t0: number, from: Vector3, ctrl: Vector3, to: Vector3, stuck: boolean }
	local stars: { Star } = {}
	local nStars = if single then 1 else count
	for i = 1, nStars do
		local m, set = LOW.shuriken(if single then 0.9 else 1.1)
		local c = clones[i]
		local from = if c then c.feet + c.fwd * 0.6 + up * (ctx.selfSize.Y * 0.55) else ctx.selfFeet + ctx.fwd * 0.8 + up * (ctx.selfSize.Y * 0.5)
		local a = math.rad(if single then 0 else (30 + (i - 1) * 120))
		local toDir = (-ctx.fwd) * math.cos(a) + side * math.sin(a)
		local to = tFeet + toDir * (if single then 1.3 else 2.3) + up * 0.1
		local sideways = side * (if i % 2 == 0 then 1 else -1) * 2.5
		local ctrl = (from + to) / 2 + up * 2.2 + (if single then Vector3.zero else sideways)
		table.insert(stars, { m = m, set = set, t0 = throwAt + (i - 1) * every, from = from, ctrl = ctrl, to = to, stuck = false })
	end
	local flashed = false
	runLoop("ninjaclones", function(tRaw)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		local live = not freezeAt or tRaw < freezeAt
		-- Klone erscheinen (Puff), ducken sich beim Wurf, stuermen bei dashAt
		for i, c in clones do
			if c.gone then continue end
			if t >= c.t0 and not c.shown then
				c.shown = true
				if live then puff(c.feet + up * 1, 10) end
			end
			if c.shown then
				local pitch = 0
				local st = stars[i]
				if st then
					local w = t - st.t0
					if w > -0.15 and w < 0.2 then pitch = -0.25 * math.sin(math.clamp((w + 0.15) / 0.35, 0, 1) * math.pi) end
				end
				local pos = c.feet
				if t >= dashAt then
					-- Sturm: durch den Gegner hindurch zur Gegenseite
					local k = math.clamp((t - dashAt) / dash, 0, 1)
					local mirror = tFeet + (tFeet - c.feet)
					pos = c.feet:Lerp(mirror, k)
					pitch = -0.2
					if not c.streak then
						local len = (mirror - c.feet).Magnitude
						local st2 = newPart(Enum.PartType.Block, Vector3.new(0.5, 0.5, len), LOW.STEEL, CFrame.lookAt((c.feet + mirror) / 2 + up * 1.2, mirror + up * 1.2), 0.45)
						st2.Name = "NinjaStreak"
						c.streak = st2
						tween(st2, dash + 0.25, { Transparency = 1, Size = Vector3.new(0.1, 0.1, len) })
						Debris:AddItem(st2, dash + 0.35)
					end
					if k >= 1 then
						c.gone = true
						c.m:PivotTo(PARK)
						if live then puff(mirror + up * 1, 8) end
						continue
					end
				end
				local half = ctx.selfSize.Y * 0.5
				local pose = CFrame.lookAt(pos, pos + c.fwd) * CFrame.new(0, half, 0) * CFrame.Angles(pitch, 0, 0) * CFrame.new(0, -half, 0)
				c.m:PivotTo(pose * c.off)
			end
		end
		-- Shuriken fliegen, bohren sich ein, blitzen
		for _, st in stars do
			local w = t - st.t0
			if w < 0 then
				st.set(PARK)
			elseif w < flight then
				local k = w / flight
				local pos = bez2(st.from, st.ctrl, st.to, k)
				local ahead = bez2(st.from, st.ctrl, st.to, math.min(1, k + 0.02))
				local dir = ahead - pos
				dir = if dir.Magnitude > 0.001 then dir.Unit else ctx.fwd
				-- Ebene waagerecht, dreht sich um die Hochachse
				st.set(CFrame.lookAt(pos, pos + dir) * CFrame.Angles(math.rad(90), 0, 0) * CFrame.Angles(0, 0, w * 40))
			else
				if not st.stuck then
					st.stuck = true
					if live then burstAt(ctx, st.to + up * 0.2, 10, 6, LOW.STEEL) end
				end
				-- eingebohrt: Ebene senkrecht (enthaelt die Richtung zum Gegner), 35 Grad geneigt
				local radial = (st.to - tFeet) * Vector3.new(1, 0, 1)
				radial = if radial.Magnitude > 0.01 then radial.Unit else -ctx.fwd
				local tilt = CFrame.lookAt(st.to, st.to + radial:Cross(up)) * CFrame.Angles(math.rad(35), 0, 0)
				local sink = if t >= flashAt + 0.25 then math.clamp((t - flashAt - 0.25) / 0.4, 0, 1) else 0
				st.set(tilt * CFrame.new(0, 0.35 - 0.9 * sink, 0))
				if t >= flashAt and not flashed then
					for _, d in st.m:GetChildren() do
						if d:IsA("BasePart") and d.Shape ~= Enum.PartType.Ball then
							d.Material = Enum.Material.Neon
						end
					end
				end
			end
		end
		if t >= flashAt and not flashed then
			flashed = true
			task.delay(0.2, function()
				for _, st in stars do
					for _, d in st.m:GetChildren() do
						if d:IsA("BasePart") then d.Material = Enum.Material.SmoothPlastic end
					end
				end
			end)
		end
		return false
	end, function()
		for _, c in clones do c.m:Destroy() end
		for _, st in stars do st.m:Destroy() end
	end)
end

-- katana: ein sichelfoermiger Lichtschnitt (7 Neon-Stuecke, F31) fegt in
-- `draw` s ueber den Oberkoerper des Gegners, zur Kamera gedreht (F04), und
-- verblasst in `fade` s zu Stahl; Funken. Test: freezeAt.
--   at, radius, draw, fade, lift
BLOCKS.katana = function(ctx, s)
	local R = s.radius or 1.9
	local draw = math.max(0.03, s.draw or 0.08)
	local fade = s.fade or 0.3
	local lift = s.lift or 0.15
	local freezeAt: number? = s.freezeAt
	local up = Vector3.yAxis
	local c = (centerOf(ctx.targetModel) or at(ctx, s.at or "target")) + up * (ctx.targetSize.Y * lift)
	local face = camFace(c, -ctx.fwd)
	local right = up:Cross(face)
	right = if right.Magnitude > 0.01 then right.Unit else sideOf(ctx)
	local n = 7
	local segs: { BasePart } = {}
	local pts: { Vector3 } = {}
	for i = 0, n do
		local a = math.rad(-150 + 120 * i / n)
		table.insert(pts, c + right * (math.cos(a) * R) + up * (math.sin(a) * R * 0.75))
	end
	for _ = 1, n do
		local p = newPart(Enum.PartType.Cylinder, Vector3.new(0.1, 0.22, 0.22), LOW.WHITE, PARK, 1)
		p.Name = "KatanaCut"
		table.insert(segs, p)
	end
	local sparked = false
	runLoop("katana", function(tRaw)
		if tRaw >= (if freezeAt then freezeAt + 150 else draw + fade) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		local k = math.clamp(t / draw, 0, 1)
		for i, p in segs do
			local f = math.clamp(k * n - (i - 1), 0, 1)
			if f > 0 then
				LOW.tube(p, pts[i], pts[i + 1], 0.22, f)
				local age = math.clamp((t - draw) / fade, 0, 1)
				p.Transparency = age
				p.Color = LOW.WHITE:Lerp(LOW.STEEL, age)
			end
		end
		if k >= 1 and not sparked then
			sparked = true
			if not freezeAt or tRaw < freezeAt then burstAt(ctx, c, 22, 10, LOW.WHITE) end
		end
		return false
	end, function()
		for _, p in segs do p:Destroy() end
	end)
end

-- roots: Wurzelwall. `count` dicke Wurzeln brechen rund um die eigene Figur
-- aus dem Boden (Ring `radius`), winden sich als Bogen hoch und nach innen ueber
-- den Kopf (Hoehe `height` x Figurenhoehe) und flechten sich zu einem Kaefig:
-- Stueck fuer Stueck (`segs` Zylinder, verjuengt, Rinde + leuchtende Moosknoten),
-- gestaffelt (`stagger`); bei `closeAt` treffen sich die Spitzen (Puls, Blaetter
-- spriessen, Gluehwuermchen), die Blattkrone des Klons (acc_leaf*) leuchtet; ab
-- `sinkAt` ziehen sich die Wurzeln zurueck, die Blaetter stieben. Test: freezeAt.
--   count, segs, radius, height, grow, stagger, closeAt, sinkAt, dur
BLOCKS.roots = function(ctx, s)
	local count = scaled(s.count or 8, ctx.factor)
	local segs = s.segs or 7
	local R = s.radius or 2.3
	local H = ctx.selfSize.Y
	local height = (s.height or 1.45) * H
	local grow = s.grow or 0.9
	local stagger = s.stagger or 0.06
	local closeAt = s.closeAt or 1.4
	local sinkAt = s.sinkAt or 3.0
	local dur = s.dur or 3.6
	local freezeAt: number? = s.freezeAt
	local up = Vector3.yAxis
	local feet = ctx.selfFeet
	local center = feet + up * height
	type Root = { parts: { BasePart }, pts: { Vector3 }, ds: { number }, t0: number, moss: { { p: BasePart, j: number } }, leaf: BasePart }
	local roots: { Root } = {}
	local rng = Random.new(5)
	for i = 1, count do
		local ang = (i - 0.5) / count * TAU
		local out = Vector3.new(math.cos(ang), 0, math.sin(ang))
		local tang = Vector3.new(-math.sin(ang), 0, math.cos(ang))
		local p0 = feet + out * R - up * 0.35
		local p1 = feet + out * (R * 1.3) + up * (height * 0.95) + tang * rng:NextNumber(-0.7, 0.7)
		local p2 = center + out * 0.4 + tang * rng:NextNumber(-0.35, 0.35)
		local pts: { Vector3 } = {}
		for j = 0, segs do table.insert(pts, bez2(p0, p1, p2, j / segs)) end
		local parts: { BasePart } = {}
		local ds: { number } = {}
		for j = 1, segs do
			local d = lerpN(0.48, 0.2, (j - 1) / math.max(1, segs - 1))
			local p = newPart(Enum.PartType.Cylinder, Vector3.new(0.1, d, d), LOW.BARK, PARK, 1)
			p.Material = Enum.Material.Wood
			p.Name = "Root"
			table.insert(parts, p)
			table.insert(ds, d)
		end
		local moss = {}
		for j = 2, segs do
			local mp = newPart(Enum.PartType.Ball, Vector3.one * 0.3, LOW.MOSS, PARK, 1)
			mp.Name = "RootMoss"
			table.insert(moss, { p = mp, j = j })
		end
		local leaf = newPart(Enum.PartType.Block, Vector3.new(0.85, 0.05, 0.5), LOW.MOSS, PARK, 1)
		leaf.Material = Enum.Material.SmoothPlastic
		leaf.Name = "RootLeaf"
		table.insert(roots, { parts = parts, pts = pts, ds = ds, t0 = (i - 1) * stagger, moss = moss, leaf = leaf })
	end
	-- Gluehwuermchen (EIN Emitter) um den Kaefig
	local fireAnchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, LOW.MOSS, CFrame.new(feet + up * (height * 0.55)), 1)
	local fire = Instance.new("ParticleEmitter")
	fire.Texture = SPARK_TEX
	fire.Rate = 0
	fire.Speed = NumberRange.new(0.3, 1.2)
	fire.SpreadAngle = Vector2.new(180, 180)
	fire.Lifetime = NumberRange.new(1.0, 1.8)
	fire.Drag = 1
	fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 0) })
	fire.Color = ColorSequence.new(Color3.fromRGB(200, 255, 170), LOW.MOSS)
	fire.LightEmission = 0.6
	fire.Parent = fireAnchor
	-- Blattkrone des Klons
	local crown: { { p: BasePart, mat: Enum.Material } } = {}
	local crownOn = false
	local function findCrown()
		local m = ctx.avatarModel
		if not m or #crown > 0 then return end
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and d.Name:find("acc_leaf", 1, true) then table.insert(crown, { p = d, mat = d.Material }) end
		end
	end
	local function crownGlow(on: boolean)
		if on == crownOn then return end
		crownOn = on
		findCrown()
		for _, c in crown do
			if c.p.Parent then c.p.Material = if on then Enum.Material.Neon else c.mat end
		end
	end
	local closed = false
	local sunk = false
	local lastG: { number } = {}
	runLoop("roots", function(tRaw)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		local live = not freezeAt or tRaw < freezeAt
		local sink = math.clamp((t - sinkAt) / 0.5, 0, 1)
		local pulse = if t >= closeAt then math.clamp(1 - (t - closeAt) / 0.35, 0, 1) else 0
		for i, r in roots do
			local g = math.clamp((t - r.t0) / grow, 0, 1) * (1 - sink)
			if lastG[i] ~= g then
				lastG[i] = g
				for j, p in r.parts do
					local f = math.clamp(g * segs - (j - 1), 0, 1)
					if f > 0 then
						LOW.tube(p, r.pts[j], r.pts[j + 1], r.ds[j], f)
						p.Transparency = 0
					else
						p.Transparency = 1
					end
				end
				for _, mo in r.moss do
					local f = math.clamp(g * segs - (mo.j - 1), 0, 1)
					mo.p.Transparency = if f >= 1 then 0 else 1
					if f >= 1 then mo.p.CFrame = CFrame.new(r.pts[mo.j + 1]) end
				end
			end
			for _, mo in r.moss do
				mo.p.Color = LOW.MOSS:Lerp(LOW.WHITE, pulse)
			end
			-- Blatt an der Spitze ab closeAt (federnd), beim Sinken weg
			local lf = if t >= closeAt then easeOutBack(math.clamp((t - closeAt) / 0.25, 0, 1)) * (1 - sink) else 0
			if lf > 0.02 then
				local tip = r.pts[segs + 1]
				local dir = (tip - r.pts[segs])
				dir = if dir.Magnitude > 0.01 then dir.Unit else up
				r.leaf.Size = Vector3.new(0.85 * lf, 0.05, 0.5 * lf)
				r.leaf.CFrame = CFrame.lookAt(tip + dir * (0.3 * lf), tip + dir * 2, up) * CFrame.Angles(0.6, 0, 0)
				r.leaf.Transparency = 0
			else
				r.leaf.Transparency = 1
			end
		end
		if t >= closeAt and not closed then
			closed = true
			if live then
				burstAt(ctx, center, 24, 6, LOW.MOSS)
				fire.Rate = if extrasOn(ctx) then 10 * ctx.factor else 0
			end
		end
		crownGlow(t >= closeAt and t < sinkAt)
		if t >= sinkAt then
			fire.Rate = 0
			if not sunk then
				sunk = true
				if live then burstAt(ctx, center, 30, 9, LOW.MOSS) end
			end
		end
		return false
	end, function()
		crownGlow(false)
		for _, r in roots do
			for _, p in r.parts do p:Destroy() end
			for _, mo in r.moss do mo.p:Destroy() end
			r.leaf:Destroy()
		end
		fire.Rate = 0
		Debris:AddItem(fireAnchor, 2)
	end)
end

-- rainbow: Regenbogenbruecke aus `bands` Baendern (Bezier-Beams, FaceCamera,
-- F31/F35) von den eigenen Fuessen bis zum Landeplatz vor dem Gegner - derselbe
-- Bogen wie die Posen von `moves` mit `curve`/`tilt` (LOW.bridge), gestapelt
-- (rot oben); zeichnet sich in `draw` s vom Baerchi weg (Glitzer an der
-- Spitze), ab `dissolveAt` loest sie sich vom Anfang her in Glitzer auf.
-- `echo`: kurz bis zum Gegner. Test: freezeAt.
--   bands, width, curve, tilt, lift, draw, dissolveAt, dur, gap, echo
BLOCKS.rainbow = function(ctx, s)
	local bands = s.bands or 6
	local width = s.width or 0.5
	local curve = s.curve or 8.5
	local tilt = s.tilt or 0.35
	local lift = s.lift or 0.3
	local draw = math.max(0.05, s.draw or 0.6)
	local dissolveAt = s.dissolveAt or 2.6
	local dur = s.dur or 3.6
	local freezeAt: number? = s.freezeAt
	local up = Vector3.yAxis
	local gap = (ctx.selfSize.Z + ctx.targetSize.Z) * 0.4 + (s.gap or 0.4)
	local a = ctx.selfFeet + up * lift
	local b = (if s.echo then ctx.targetFeet else ctx.targetFeet - ctx.fwd * gap) + up * lift
	local side = sideOf(ctx)
	local T0 = (ctx.fwd * tilt + up).Unit
	local T1 = (ctx.fwd * tilt - up).Unit
	local anchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, ctx.fx.color, PARK, 1)
	anchor.Name = "RainbowAnchor"
	local beams: { Beam } = {}
	for i = 1, bands do
		local off = up * ((bands - i) * width * 0.9)
		-- erst einhaengen, dann WorldCFrame setzen (sonst gilt der Wert relativ zu PARK)
		local a0 = Instance.new("Attachment")
		a0.Parent = anchor
		a0.WorldCFrame = CFrame.fromMatrix(a + off, T0, T0:Cross(side).Unit)
		local a1 = Instance.new("Attachment")
		a1.Parent = anchor
		a1.WorldCFrame = CFrame.fromMatrix(b + off, T1, T1:Cross(side).Unit)
		local bm = Instance.new("Beam")
		bm.Attachment0 = a0
		bm.Attachment1 = a1
		bm.CurveSize0 = curve
		bm.CurveSize1 = curve
		bm.Width0 = width
		bm.Width1 = width
		bm.Segments = 24
		bm.FaceCamera = true
		bm.LightEmission = 0.35
		bm.LightInfluence = 0
		bm.Color = ColorSequence.new(RAINBOW[(i - 1) % #RAINBOW + 1])
		bm.Transparency = NumberSequence.new(1)
		bm.Parent = anchor
		table.insert(beams, bm)
	end
	-- sichtbarer Abschnitt k0..k1 als Transparenz-Verlauf (Zeiten streng steigend)
	local function seq(k0: number, k1: number, tr: number): NumberSequence
		local e = 0.004
		k0 = math.clamp(k0, 0, 1)
		k1 = math.clamp(k1, 0, 1)
		if k1 - k0 < 3 * e then return NumberSequence.new(1) end
		local kps: { NumberSequenceKeypoint } = {}
		if k0 > e then
			table.insert(kps, NumberSequenceKeypoint.new(0, 1))
			table.insert(kps, NumberSequenceKeypoint.new(k0 - e, 1))
			table.insert(kps, NumberSequenceKeypoint.new(k0, tr))
		else
			table.insert(kps, NumberSequenceKeypoint.new(0, tr))
		end
		if k1 < 1 - e then
			table.insert(kps, NumberSequenceKeypoint.new(k1, tr))
			table.insert(kps, NumberSequenceKeypoint.new(k1 + e, 1))
			table.insert(kps, NumberSequenceKeypoint.new(1, 1))
		else
			table.insert(kps, NumberSequenceKeypoint.new(1, tr))
		end
		return NumberSequence.new(kps)
	end
	-- Glitzer an der Zeichen- bzw. Aufloese-Front (EIN Emitter)
	local glitAnchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, LOW.WHITE, CFrame.new(a), 1)
	local glit = Instance.new("ParticleEmitter")
	glit.Texture = SPARK_TEX
	glit.Rate = 0
	glit.Speed = NumberRange.new(1, 3)
	glit.SpreadAngle = Vector2.new(180, 180)
	glit.Lifetime = NumberRange.new(0.35, 0.7)
	glit.Drag = 2
	glit.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
	glit.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, LOW.WHITE), ColorSequenceKeypoint.new(0.5, ctx.fx.color), ColorSequenceKeypoint.new(1, ctx.fx.color2) })
	glit.LightEmission = 0.6
	glit.Parent = glitAnchor
	local lastK0, lastK1 = -1, -1
	runLoop("rainbow", function(tRaw)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		local k0, k1 = 0, 0
		if t < dissolveAt then
			k1 = easeOutCubic(math.clamp(t / draw, 0, 1))
		else
			k1 = 1
			k0 = math.clamp((t - dissolveAt) / math.max(0.1, dur - dissolveAt - 0.1), 0, 1)
		end
		if math.abs(k0 - lastK0) > 0.003 or math.abs(k1 - lastK1) > 0.003 then
			lastK0, lastK1 = k0, k1
			local sq = seq(k0, k1, 0.15)
			for _, bm in beams do bm.Transparency = sq end
		end
		local front = if t < dissolveAt then k1 else k0
		local p = LOW.bridge(a, b, ctx.fwd, curve, tilt, front) + up * (bands * width * 0.45)
		glitAnchor.CFrame = CFrame.new(p)
		glit.Rate = if (t < draw) or (t >= dissolveAt and k0 < 1) then 50 * ctx.factor else 0
		return false
	end, function()
		anchor:Destroy()
		glit.Rate = 0
		Debris:AddItem(glitAnchor, 1)
	end)
end

-- paintsplash: Farbkleckse in Regenbogenfarben spritzen bei `at` rund um die
-- Figur auf den Boden (flache Ellipsen, federn auf, zufaellig gedreht),
-- verblassen ab `dur` - 0,4. Test: freezeAt.
--   at, count, radius, dur
BLOCKS.paintsplash = function(ctx, s)
	local count = scaled(s.count or 7, ctx.factor)
	local R = s.radius or 2.0
	local dur = s.dur or 1.4
	local freezeAt: number? = s.freezeAt
	local feet = groundAt(ctx, s.at or "target")
	local rng = Random.new(11)
	type Splat = { p: BasePart, cf: CFrame, w: number, l: number, t0: number }
	local splats: { Splat } = {}
	for i = 1, count do
		local ang = (i - 0.5) / count * TAU + rng:NextNumber(-0.3, 0.3)
		local r = R * rng:NextNumber(0.45, 1)
		local pos = feet + Vector3.new(math.cos(ang) * r, 0.05 + i * 0.004, math.sin(ang) * r)
		local w = rng:NextNumber(1.3, 2.2)
		local p = newPart(Enum.PartType.Cylinder, Vector3.new(0.05, 0.05, 0.05), RAINBOW[(i - 1) % #RAINBOW + 1], PARK, 1)
		p.Material = Enum.Material.SmoothPlastic
		p.Name = "PaintSplat"
		local cf = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, TAU), 0) * CFrame.Angles(0, 0, math.rad(90))
		table.insert(splats, { p = p, cf = cf, w = w, l = w * rng:NextNumber(0.6, 0.9), t0 = rng:NextNumber(0, 0.08) })
	end
	runLoop("paintsplash", function(tRaw)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		local fade = math.clamp((t - (dur - 0.4)) / 0.4, 0, 1)
		for _, sp in splats do
			local k = math.clamp((t - sp.t0) / 0.22, 0, 1)
			local e = math.max(0.02, easeOutBack(k))
			sp.p.Size = Vector3.new(0.05, sp.w * e, sp.l * e)
			sp.p.CFrame = sp.cf
			sp.p.Transparency = if k > 0 then fade else 1
		end
		return false
	end, function()
		for _, sp in splats do sp.p:Destroy() end
	end)
end

--------------------------------------------------------------------------------
-- 26.10.2026 Himmelsgericht (SeraphJudgment, Seraph-Baerchi, Divine, Stufe 4).
-- Der Seraph oeffnet seine sechs Fluegel Paar fuer Paar, steigt mit dem
-- Heiligenschein in die Hoehe, ueber der Arena oeffnet sich ein Himmelstor
-- (Ring aus Licht, Lichtschaefte), ein Speer aus Licht faellt ihm in die
-- Pfoten, eine Zielmarke schrumpft unter dem Gegner, Stille - Sturz - Einschlag
-- (Impact-Frames, Hitstop, Beben), dann die Lichtsaeule bis zum Tor, Druckwelle
-- bis zum Zaun, goldene Kuppel, die Ringe des Tors fallen als Kondensringe die
-- Saeule herab, Federn rieseln, ein schiefer kleiner Heiligenschein landet auf
-- dem Gegner (Pointe). Bewegung des Seraphs: `moves` (Daten in SkillFXConfig).
-- Alle Helfer dieser Show liegen in EINER Tabelle SER (Namensbudget, F51).
-- Doku in SkillFXConfig ("BAUSTEINE", Himmelsgericht).
--------------------------------------------------------------------------------

local SER: { [string]: any } = {}

SER.GOLD = Color3.fromRGB(255, 214, 110)      -- Honiggold (Tor, Speer-Huelle, Kuppel)
SER.HONEY = Color3.fromRGB(230, 160, 40)      -- dunkles Honiggold (Risse, Umriss-Akzent)
SER.CREAM = Color3.fromRGB(255, 246, 225)     -- warmes Weiss (Kern, aeusserer Torring)
SER.HALO = Color3.fromRGB(255, 236, 160)      -- Heiligenschein (Neon-Akzent, klein)
SER.WINGLIGHT = Color3.fromRGB(255, 232, 170) -- Fluegel aus Licht (ForceField)
SER.SCORCH = Color3.fromRGB(72, 48, 24)       -- Brandfleck (dunkel-warm)
SER.INDIGO = Color3.fromRGB(70, 50, 160)      -- dunkle Impact-Frames (Tint)
SER.INDIGOFILL = Color3.fromRGB(40, 24, 110)  -- Silhouetten im dunklen Bild

-- Beben (quake): Trauma-Modell. Staerke = trauma^2, klingt linear ab; Drehung
-- per Perlin-Rauschen auf Nick/Gier/Rollen, kleiner Versatz; angewendet als
-- LETZTER Offset je Bild (RenderPriority Camera + 2, nach Spielkamera und
-- nach `shake`), funktioniert so in Custom und waehrend einer Kamerafahrt (F46).
SER.trauma = 0
SER.bound = false
SER.seed = math.random() * 100
SER.decay = 1.1
SER.angle = 4
SER.offset = 0.4
SER.freq = 22
SER.fovPunch = 0
SER.fovT0 = 0
SER.fovIn = 0.08
SER.fovOut = 0.3
SER.fovBase = nil

-- Typen der Show (auf Modulebene, kein lokaler Name)
type SeraphWing = { p: BasePart, rel: CFrame, hinge: Vector3, side: number, pair: number, tip: Vector3,
	a0: Attachment, a1: Attachment, beam: Beam, trail: Trail, mat: Enum.Material, col: Color3 }
type SeraphHalo = { p: BasePart, rel: CFrame, mat: Enum.Material, col: Color3, size: Vector3 }
type SeraphGateRing = { ring: NovaRing, r0: number, w0: number, tr: number, spin: number, h: number, r1: number, order: number }

-- Teile eines Modells, deren Name ein Muster enthaelt (Kleinschreibung).
SER.partsLike = function(model: Model, pat: string): { BasePart }
	local out: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and string.find(string.lower(d.Name), pat, 1, true) then
			table.insert(out, d)
		end
	end
	return out
end

-- Unsichtbarer Anker mit einem Attachment (fuer Beams).
SER.anchorAt = function(pos: Vector3): (BasePart, Attachment)
	local p = newPart(Enum.PartType.Block, Vector3.one * 0.2, SER.CREAM, CFrame.new(pos), 1)
	p.Name = "SeraphAnchor"
	local a = Instance.new("Attachment")
	a.Parent = p
	return p, a
end

-- Beam zwischen zwei Attachments (FaceCamera, ohne Lichteinfluss).
SER.beam = function(a0: Attachment, a1: Attachment, w0: number, w1: number, col: Color3, emission: number, tr: number, texture: string?): Beam
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.FaceCamera = true
	b.Segments = 1
	b.LightEmission = emission
	b.LightInfluence = 0
	b.Color = ColorSequence.new(col)
	b.Transparency = NumberSequence.new(tr)
	b.Width0 = w0
	b.Width1 = w1
	if texture then
		b.Texture = texture
		b.TextureMode = Enum.TextureMode.Stretch
	end
	b.Parent = a0.Parent
	return b
end

-- Zylinder-Stueck von a nach b (Laenge entlang X des Teils, Roehre statt
-- Quader, F31).
SER.rod = function(a: Vector3, b: Vector3, d: number, col: Color3, tr: number): BasePart
	local len = (b - a).Magnitude
	local p = newPart(Enum.PartType.Cylinder, Vector3.new(math.max(0.05, len), d, d), col,
		CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0), tr)
	return p
end

-- Zufaelliges Rauschen -1..1 (math.noise liefert etwa -0,5..0,5).
SER.noise = function(x: number, y: number): number
	return math.clamp(math.noise(x, y) * 1.9, -1, 1)
end

-- quake: Camera-Shake mit Wucht (nur Besitzer). `power` (Trauma 0..1, addiert
-- sich bis 1), `decay` (Trauma je Sekunde, 1,1 = ~0,9 s Nachbeben bei 1),
-- `angle` (Grad bei Trauma 1, Standard 4), `offset` (Studs, 0,4), `freq`
-- (Rauschen Hz, 22), `fov` (optional FOV-Stoss in Grad: schnell rein `fovIn`,
-- langsam raus `fovOut`; NICHT zusammen mit `hitstop`, das selbst FOV tweent).
BLOCKS.quake = function(ctx, s)
	if not ctx.isOwner then return end
	SER.trauma = math.min(1, SER.trauma + (s.power or 0.5))
	if s.decay then SER.decay = s.decay end
	if s.angle then SER.angle = s.angle end
	if s.offset then SER.offset = s.offset end
	if s.freq then SER.freq = s.freq end
	if s.fovIn then SER.fovIn = s.fovIn end
	if s.fovOut then SER.fovOut = s.fovOut end
	if typeof(s.fov) == "number" and s.fov > 0 then
		SER.fovPunch = s.fov
		SER.fovT0 = os.clock()
	end
	if SER.bound then return end
	SER.bound = true
	RunService:BindToRenderStep("SkillFXQuake", Enum.RenderPriority.Camera.Value + 2, function(dt: number)
		local cam = workspace.CurrentCamera
		SER.trauma = math.max(0, SER.trauma - SER.decay * dt)
		local punchLeft = if SER.fovPunch > 0 then (SER.fovIn + SER.fovOut) - (os.clock() - SER.fovT0) else 0
		if not cam or (SER.trauma <= 0 and punchLeft <= 0) then
			RunService:UnbindFromRenderStep("SkillFXQuake")
			SER.bound = false
			SER.trauma = 0
			if cam and SER.fovBase then cam.FieldOfView = SER.fovBase end
			SER.fovPunch = 0
			SER.fovBase = nil
			return
		end
		local st = SER.trauma * SER.trauma
		if st > 0.0001 then
			local t = os.clock() * SER.freq
			local ang = math.rad(SER.angle) * st
			local rx = SER.noise(t, SER.seed) * ang
			local ry = SER.noise(t, SER.seed + 7.3) * ang
			local rz = SER.noise(t, SER.seed + 13.1) * ang * 0.6
			local ox = SER.noise(t * 0.8, SER.seed + 21.7) * SER.offset * st
			local oy = SER.noise(t * 0.8, SER.seed + 29.9) * SER.offset * st
			cam.CFrame = cam.CFrame * CFrame.Angles(rx, ry, rz) * CFrame.new(ox, oy, 0)
		end
		if SER.fovPunch > 0 then
			local q = os.clock() - SER.fovT0
			local env = if q < SER.fovIn then q / SER.fovIn else math.clamp(1 - (q - SER.fovIn) / SER.fovOut, 0, 1)
			if not SER.fovBase then SER.fovBase = cam.FieldOfView end
			cam.FieldOfView = SER.fovBase - SER.fovPunch * env
			if env <= 0 then
				cam.FieldOfView = SER.fovBase
				SER.fovPunch = 0
				SER.fovBase = nil
			end
		end
	end)
end

-- seraphwings: die sechs Fluegel (Teile mit "acc_wing" im Namen) und der
-- Heiligenschein ("acc_halo") des `moves`-Klons (ctx.avatarModel). Zu Beginn
-- liegen die Fluegel angelegt; bei `snapAt[i]` schnappt Paar i (oben, Mitte,
-- unten) auf (Funken an den Spitzen, Lichtfedern = Beams mit Feder-Bild), danach
-- schlagen sie; ab `launchAt` schneller Flugschlag mit Nachbildern (ForceField-
-- Klone, F26), beim Schweben weit gespreizt und hochgewoelbt; ab `diveAt` nach
-- hinten angelegt (Sturzflug, Nachbilder); ab `landAt` gespreizt; ab `foldAt`
-- legen sie sich wieder an, die Lichtfedern vergehen. Heiligenschein: ab `haloAt`
-- Neon, dreht sich, pulst; bei `landAt` blitzt er. Laeuft bis `dur`.
--   snapAt {3}, haloAt, launchAt, diveAt, landAt, foldAt, dur, ghosts (Test: freezeAt)
BLOCKS.seraphwings = function(ctx, s)
	local snapAt: { number } = if type(s.snapAt) == "table" then s.snapAt else { 0.22, 0.44, 0.66 }
	local haloAt = s.haloAt or 0.8
	local launchAt = s.launchAt or 1.0
	local diveAt = s.diveAt or 3.02
	local landAt = s.landAt or 3.27
	local foldAt = s.foldAt or 4.2
	local dur = s.dur or 5.4
	local wantGhosts = if s.ghosts ~= nil then s.ghosts == true else extrasOn(ctx)
	local freezeAt: number? = s.freezeAt
	local feather = texOf(ctx, "feather")
	local wings: { SeraphWing } = {}
	local halo: SeraphHalo? = nil
	local model: Model? = nil
	local sc0 = 1
	local lastGhost = -1
	local ghostCount = 0
	local snapped = { false, false, false }
	local haloOn = false
	local haloFlash = false
	local phase = 0

	-- Paare nach Hoehe sortieren: oben = 1, Mitte = 2, unten = 3
	local function build(m: Model): boolean
		local pv = m:GetPivot()
		local raw = SER.partsLike(m, "acc_wing")
		if #raw < 2 then return false end
		local infos: { { p: BasePart, rel: CFrame } } = {}
		for _, p in raw do
			table.insert(infos, { p = p, rel = pv:ToObjectSpace(p.CFrame) })
		end
		table.sort(infos, function(a, b) return a.rel.Position.Y > b.rel.Position.Y end)
		local pairOf: { [BasePart]: number } = {}
		local pairIdx = 0
		local lastY = math.huge
		for _, w in infos do
			if lastY - w.rel.Position.Y > 0.2 then
				pairIdx = math.min(3, pairIdx + 1)
				lastY = w.rel.Position.Y
			end
			pairOf[w.p] = math.max(1, pairIdx)
		end
		for _, w in infos do
			local side = if w.rel.Position.X < 0 then -1 else 1
			local sz = w.p.Size
			-- Scharnier am Ruecken (Wirbelsaeule), Spitze = hinteres Ende des Blatts
			local hinge = Vector3.new(side * 0.25, w.rel.Position.Y, w.rel.Position.Z - sz.Z * 0.35)
			local tip = Vector3.new(0, sz.Y * 0.45, sz.Z * 0.5)
			local a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(0, -sz.Y * 0.4, -sz.Z * 0.45)
			a0.Parent = w.p
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(side * 0.35, sz.Y * 0.55, sz.Z * 0.95)
			a1.Parent = w.p
			local beam = SER.beam(a0, a1, 0.9, 0.25, SER.GOLD, 0.35, 1, feather)
			beam.Segments = 4
			local t0a = Instance.new("Attachment")
			t0a.Position = Vector3.new(0, sz.Y * 0.45, sz.Z * 0.5)
			t0a.Parent = w.p
			local t1a = Instance.new("Attachment")
			t1a.Position = Vector3.new(0, -sz.Y * 0.1, sz.Z * 0.5)
			t1a.Parent = w.p
			local trail = Instance.new("Trail")
			trail.Attachment0 = t0a
			trail.Attachment1 = t1a
			trail.Lifetime = 0.22
			trail.LightEmission = 0.6
			trail.FaceCamera = true
			trail.Color = ColorSequence.new(SER.CREAM, SER.GOLD)
			trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
			trail.Enabled = false
			trail.Parent = w.p
			table.insert(wings, { p = w.p, rel = w.rel, hinge = hinge, side = side, pair = pairOf[w.p], tip = tip,
				a0 = a0, a1 = a1, beam = beam, trail = trail, mat = w.p.Material, col = w.p.Color })
		end
		local hp = SER.partsLike(m, "acc_halo")[1]
		if hp then
			halo = { p = hp, rel = pv:ToObjectSpace(hp.CFrame), mat = hp.Material, col = hp.Color, size = hp.Size }
		end
		sc0 = ctx.avatarScale or 1   -- Groesse des Klons beim Erfassen der Ruhelagen
		return true
	end

	local function restore()
		for _, w in wings do
			w.p.Material = w.mat
			w.p.Color = w.col
			w.trail.Enabled = false
		end
		if halo then
			halo.p.Material = halo.mat
			halo.p.Color = halo.col
		end
	end

	local function fanAngle(pairIdx: number): number
		-- Grundwinkel des Faechers (oben 28, Mitte 45, unten 60 Grad)
		return math.rad(if pairIdx == 1 then 28 elseif pairIdx == 2 then 45 else 60)
	end

	runLoop("seraphwings", function(tRaw, dt)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		local m = ctx.avatarModel
		if not m or not m.Parent then
			if t > 0.6 and model == nil then return true end   -- kein Klon gekommen (fremdes Modell?)
			if model ~= nil then return true end               -- `moves` ist fertig
			return false
		end
		if model == nil then
			model = m
			if not build(m) then return true end
		end
		local pv = m:GetPivot()
		local sc = ctx.avatarScale or 1
		local k = sc / math.max(0.01, sc0)
		phase += dt * TAU * (if t < launchAt then 2.2 elseif t < launchAt + 0.7 then 7.5 elseif t < diveAt then 3.6 elseif t < landAt then 9 else 2.0)
		local parts: { BasePart } = {}
		local cfs: { CFrame } = {}
		for _, w in wings do
			local openK: number
			local snapT = snapAt[w.pair] or 0.5
			if t < snapT then
				openK = 0
			else
				local q = math.clamp((t - snapT) / 0.09, 0, 1)
				openK = easeOutBack(q)
				if not snapped[w.pair] then
					snapped[w.pair] = true
					burstAt(ctx, pv:PointToWorldSpace((w.rel.Position + w.tip) * k), 14, 7, SER.GOLD)
				end
			end
			if t >= foldAt then
				openK *= 1 - math.clamp((t - foldAt) / 0.5, 0, 1)
			end
			-- Schlag (Flattern) + Haltung je Phase: Schweben weit und hoch, Sturz angelegt
			local flap = math.sin(phase + w.pair * 0.6)
			local spread: number
			local liftRoll: number
			if t < launchAt then
				spread = 0.35 + 0.12 * flap
				liftRoll = 0.15 + 0.08 * flap
			elseif t < diveAt then
				local hoverK = math.clamp((t - launchAt) / 0.5, 0, 1)
				spread = 0.35 + 0.45 * hoverK + 0.22 * flap
				liftRoll = 0.15 + 0.55 * hoverK + 0.2 * flap
			elseif t < landAt then
				spread = -0.5 + 0.05 * flap          -- nach hinten angelegt
				liftRoll = -0.1
			else
				local landK = math.clamp((t - landAt) / 0.25, 0, 1)
				spread = -0.5 + 1.1 * easeOutBack(landK) + 0.1 * flap
				liftRoll = -0.1 + 0.6 * landK + 0.08 * flap
			end
			local yaw = w.side * (-fanAngle(w.pair) + (fanAngle(w.pair) + spread) * openK)
			local roll = w.side * liftRoll * openK
			local h = w.hinge * k
			local localCf = CFrame.new(h) * CFrame.Angles(0, yaw, roll) * CFrame.new(-h)
				* CFrame.new(w.rel.Position * k) * w.rel.Rotation
			table.insert(parts, w.p)
			table.insert(cfs, pv * localCf)
			-- Licht: Fluegel aus Licht sobald offen
			local lit = openK > 0.3
			local wantMat = if lit then Enum.Material.ForceField else w.mat
			if w.p.Material ~= wantMat then
				w.p.Material = wantMat
				w.p.Color = if lit then SER.WINGLIGHT else w.col
			end
			local beamA = math.clamp(openK * 1.2, 0, 1)
			w.beam.Transparency = NumberSequence.new(1 - 0.75 * beamA)
			w.trail.Enabled = (t >= launchAt and t < launchAt + 0.55) or (t >= diveAt and t < landAt + 0.05)
		end
		if halo then
			local hk = math.clamp((t - haloAt) / 0.3, 0, 1)
			if hk > 0 and not haloOn then
				haloOn = true
				halo.p.Material = Enum.Material.Neon
				halo.p.Color = SER.HALO
			end
			local pulse = 1 + 0.35 * math.sin(math.pi * hk) + 0.05 * math.sin(t * 9)
			if t >= landAt and t < landAt + 0.3 then
				pulse += 0.5 * (1 - (t - landAt) / 0.3)
				if not haloFlash then
					haloFlash = true
					burstAt(ctx, pv:PointToWorldSpace(halo.rel.Position * k), 18, 6, SER.HALO)
				end
			end
			local lift = 0.12 * hk + 0.06 * math.sin(t * 3)
			local hp = halo.rel.Position * k + Vector3.new(0, lift, 0)
			local tilt = if t >= diveAt and t < landAt then 0.35 else 0.08 * math.sin(t * 2.1)
			local localCf = CFrame.new(hp) * CFrame.Angles(tilt, t * 3.0 * hk, 0) * halo.rel.Rotation
			table.insert(parts, halo.p)
			table.insert(cfs, pv * localCf)
			local wantSize = halo.size * (if haloOn then pulse else 1)
			if (wantSize - halo.p.Size).Magnitude > 0.01 then halo.p.Size = wantSize end
		end
		if #parts > 0 then
			workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		end
		-- Nachbilder beim Start und im Sturz
		if wantGhosts and ((t >= launchAt and t < launchAt + 0.45) or (t >= diveAt and t < landAt)) then
			local every = if t < diveAt then 0.07 else 0.045
			if t - lastGhost >= every and ghostCount < 14 then
				lastGhost = t
				ghostCount += 1
				chronoGhost(m, SER.GOLD, 0.3, 0.26)
			end
		end
		return false
	end, function()
		restore()
		for _, w in wings do
			w.beam:Destroy()
			w.trail:Destroy()
			w.a0:Destroy()
			w.a1:Destroy()
		end
	end)
end

-- seraphspear: der Speer aus Licht. Bei `formAt` entsteht er klein am Himmelstor
-- (ctx.seraphGate) und sinkt in `form` s zu dem schwebenden Klon; ab `grabAt`
-- in den Pfoten (folgt ctx.avatarCf), richtet sich in 0,3 s auf die Fuesse des
-- Gegners aus (zielt); im Sturz voraus; bei `plantAt` steckt er im Boden an
-- den Fuessen des Gegners (Spitze unten, Schaft zum Seraph geneigt) und blitzt
-- - setzt ctx.seraphHit; bei `pullAt` hebt er sich und zerfaellt in Federn
-- und Funken. Kern Neon (schmal, F17), Huelle ForceField, Klinge aus zwei
-- Keilen, goldene Parierscheibe, zwei Feder-Troddeln (Beams).
--   formAt, form, grabAt, plantAt, pullAt, length, dur (Test: freezeAt)
BLOCKS.seraphspear = function(ctx, s)
	local formAt = s.formAt or 0
	local form = s.form or 0.35
	local grabAt = s.grabAt or 0.45
	local plantAt = s.plantAt or 1.38
	local pullAt = s.pullAt or 2.45
	local L = s.length or 8
	local dur = s.dur or 2.7
	local freezeAt: number? = s.freezeAt
	local feather = texOf(ctx, "feather")
	local H = ctx.selfSize.Y

	-- Teile: lokale Achse = +Y (Spitze bei +L/2)
	local rig: { { p: BasePart, rel: CFrame, tr: number } } = {}
	local function add(p: BasePart, rel: CFrame, tr: number)
		p.Transparency = 1
		table.insert(rig, { p = p, rel = rel, tr = tr })
	end
	local shaftLen = L * 0.78
	local core = newPart(Enum.PartType.Cylinder, Vector3.new(shaftLen, 0.18, 0.18), SER.CREAM, PARK, 1)
	core.Name = "SeraphSpearCore"
	add(core, CFrame.new(0, -L * 0.08, 0) * CFrame.Angles(0, 0, math.rad(90)), 0)
	local shell = newPart(Enum.PartType.Cylinder, Vector3.new(shaftLen, 0.44, 0.44), SER.GOLD, PARK, 1)
	shell.Material = Enum.Material.ForceField
	add(shell, CFrame.new(0, -L * 0.08, 0) * CFrame.Angles(0, 0, math.rad(90)), 0.15)
	local guard = newPart(Enum.PartType.Cylinder, Vector3.new(0.14, 0.9, 0.9), SER.HONEY, PARK, 1)
	guard.Material = Enum.Material.SmoothPlastic
	add(guard, CFrame.new(0, L * 0.31, 0) * CFrame.Angles(0, 0, math.rad(90)), 0)
	local bladeLen = L * 0.2
	for side = -1, 1, 2 do
		local w = Instance.new("WedgePart")
		prepPart(w, SER.CREAM, PARK, 1)
		w.Material = Enum.Material.Neon
		w.Size = Vector3.new(0.12, bladeLen, 0.42)
		-- Keil: senkrechte Flaeche hinten (+Z), Spitze oben (F16); zwei Keile Ruecken an Ruecken
		add(w, CFrame.new(0, L * 0.31 + bladeLen / 2, side * 0.21) * (if side > 0 then CFrame.Angles(0, math.pi, 0) else CFrame.identity), 0)
	end
	local bladeGlow = newPart(Enum.PartType.Ball, Vector3.new(0.7, bladeLen * 1.1, 0.7), SER.GOLD, PARK, 1)
	bladeGlow.Material = Enum.Material.ForceField
	add(bladeGlow, CFrame.new(0, L * 0.31 + bladeLen / 2, 0), 0.35)
	local pommel = newPart(Enum.PartType.Ball, Vector3.one * 0.36, SER.HONEY, PARK, 1)
	pommel.Material = Enum.Material.SmoothPlastic
	add(pommel, CFrame.new(0, -L * 0.47, 0), 0)
	-- Troddeln: zwei Feder-Beams vom Rand der Parierscheibe nach unten-aussen
	-- (Scheibe ist um 90 Grad gedreht: lokal +X = zur Spitze, Y/Z = Scheibenebene)
	local tassels: { Beam } = {}
	for side = -1, 1, 2 do
		local a0 = Instance.new("Attachment")
		a0.Parent = guard
		a0.Position = Vector3.new(0, side * 0.42, 0)
		local a1 = Instance.new("Attachment")
		a1.Parent = guard
		a1.Position = Vector3.new(-1.1, side * 0.8, 0)
		local b = SER.beam(a0, a1, 0.45, 0.12, SER.CREAM, 0.3, 1, feather)
		b.Segments = 3
		b.CurveSize0 = 0.4
		b.CurveSize1 = -0.4
		table.insert(tassels, b)
	end
	local light = Instance.new("PointLight")
	light.Color = SER.GOLD
	light.Brightness = 0
	light.Range = 9
	light.Parent = core

	local gateC: Vector3 = ctx.seraphGate or (ctx.selfFeet + Vector3.new(0, 24, 0))
	local hit: Vector3 = ctx.targetFeet
	local planted = false
	local pulled = false
	local alpha = 0
	local lastAlpha = -1
	local function setAlpha(a: number)
		if math.abs(a - lastAlpha) < 0.01 then return end
		lastAlpha = a
		for _, r in rig do
			r.p.Transparency = 1 - (1 - r.tr) * a
		end
		local seq = NumberSequence.new(1 - 0.8 * a)
		for _, b in tassels do b.Transparency = seq end
		light.Brightness = 1.4 * a
	end
	local function place(cf: CFrame)
		local parts: { BasePart } = table.create(#rig)
		local cfs: { CFrame } = table.create(#rig)
		for i, r in rig do
			parts[i] = r.p
			cfs[i] = cf * r.rel
		end
		workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end
	-- Speer-Lage aus Mitte und Richtung (Spitze zeigt nach `dir`)
	local function frameOf(center: Vector3, dir: Vector3, roll: number): CFrame
		local d = if dir.Magnitude > 0.01 then dir.Unit else Vector3.yAxis
		local ref = if math.abs(d:Dot(Vector3.yAxis)) > 0.95 then ctx.fwd else Vector3.yAxis
		local right = d:Cross(ref).Unit
		-- lokale Y-Achse = d (Z ergibt sich als X x Y)
		return CFrame.fromMatrix(center, right, d) * CFrame.Angles(0, roll, 0)
	end
	local restCenter = ctx.selfFeet + Vector3.new(0, H * 0.7, 0)
	local lastCf = CFrame.new(gateC)

	runLoop("seraphspear", function(tRaw)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		local av = ctx.avatarCf
		local sc = ctx.avatarScale or 1
		local cf: CFrame = lastCf
		if t < formAt then
			setAlpha(0)
			return false
		elseif t < grabAt then
			-- Entstehen: vom Tor herab in die Naehe der Pfoten, erst klein (F43)
			local q = math.clamp((t - formAt) / form, 0, 1)
			local e = easeOutCubic(q)
			local hover = if av then av.Position + Vector3.new(0, H * sc * 0.75, 0) + av.LookVector * (H * sc * 0.3) else restCenter
			local pos = gateC:Lerp(hover + Vector3.new(0, 1.6, 0), e)
			local spin = (1 - e) * 4
			cf = frameOf(pos, Vector3.new(0, 1, 0), spin)
			setAlpha(0.25 + 0.75 * e)
		elseif t < plantAt then
			if not av then
				cf = frameOf(restCenter + Vector3.new(0, 1.6, 0), Vector3.yAxis, 0)
			else
				local body = av.Position + Vector3.new(0, H * sc * 0.5, 0)
				-- in den Pfoten: rechts-vorn vor der Brust
				local grip = body + av.RightVector * (0.35 * sc) + av.LookVector * (H * sc * 0.45) - av.UpVector * (H * sc * 0.05)
				local aimK = math.clamp((t - grabAt) / 0.3, 0, 1)
				local toHit = (hit + Vector3.new(0, 0.3, 0)) - grip
				local upDir = av.UpVector
				local dir = upDir:Lerp(toHit.Unit, easeInOutSine(aimK))
				local roll = t * 0.8
				cf = frameOf(grip + dir.Unit * (L * 0.1), dir, roll)
			end
			setAlpha(1)
		else
			if not planted then
				planted = true
				ctx.seraphHit = hit
				burstAt(ctx, hit + Vector3.new(0, 0.6, 0), 26, 11, SER.CREAM)
			end
			if t < pullAt then
				-- steckt im Boden: Spitze bei `hit`, Schaft zum Seraph geneigt (20 Grad)
				local back = -ctx.fwd
				local axis = (Vector3.yAxis * math.cos(math.rad(20)) + back * math.sin(math.rad(20))).Unit
				local center = hit + axis * (L * 0.5 - L * 0.35)   -- Spitze 35 % eingegraben
				local wob = 0.03 * math.sin((t - plantAt) * 28) * math.max(0, 1 - (t - plantAt) * 2)
				cf = frameOf(center, -axis, 0) * CFrame.Angles(wob, 0, 0)
				setAlpha(1)
			else
				local q = math.clamp((t - pullAt) / 0.25, 0, 1)
				if not pulled then
					pulled = true
					burstAt(ctx, hit + Vector3.new(0, 1.2, 0), 30, 9, SER.GOLD)
					-- Federn
					local a = newPart(Enum.PartType.Block, Vector3.one * 0.3, SER.CREAM, CFrame.new(hit + Vector3.new(0, 1.5, 0)), 1)
					local em = Instance.new("ParticleEmitter")
					em.Texture = feather or SPARK_TEX
					em.Rate = 0
					em.Speed = NumberRange.new(2, 6)
					em.SpreadAngle = Vector2.new(180, 180)
					em.Lifetime = NumberRange.new(0.8, 1.4)
					em.Drag = 2
					em.Acceleration = Vector3.new(0, -1.5, 0)
					em.Size = NumberSequence.new(0.5)
					em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
					em.Color = ColorSequence.new(SER.CREAM, SER.GOLD)
					em.LightEmission = 0.5
					em.Rotation = NumberRange.new(0, 360)
					em.RotSpeed = NumberRange.new(-60, 60)
					em.Parent = a
					em:Emit(scaled(18, ctx.factor))
					Debris:AddItem(a, 1.8)
				end
				local back = -ctx.fwd
				local axis = (Vector3.yAxis * math.cos(math.rad(20)) + back * math.sin(math.rad(20))).Unit
				local center = hit + axis * (L * 0.15) + Vector3.new(0, 1.2 * easeOutCubic(q), 0)
				cf = frameOf(center, -axis, q * 3)
				setAlpha(1 - q)
			end
		end
		lastCf = cf
		place(cf)
		return false
	end, function()
		for _, r in rig do r.p:Destroy() end
	end)
end

-- halogate: das Himmelstor ueber der Arena (`at` + `lift`): drei Ringe aus je
-- 4 Bezier-Beams (novaRing, FaceCamera - von unten, schraeg und von innen
-- sichtbar, F40): aussen warm-weiss breit, innen Gold schmal (gestrichelt,
-- dreht sich), dazwischen ein duenner Honigring. Oeffnet sich bei 0: erst
-- klein, dann in `open` s auf `radius` (F43). Ab `raysAt` Lichtschaefte vom
-- Ring herab zur Arena (Beams, oben schmal, unten breit, drehen langsam);
-- bei jedem `ticks` pulsen Ringe und Schaefte; bei `offAt` reissen die
-- Schaefte ab (Einschlag). Bei `fallAt` stuerzen die drei Ringe in `fallFor` s
-- zur Lichtsaeule am Einschlagpunkt (ctx.seraphHit) und werden dort zu
-- Kondensringen (dehnen sich, verblassen); ein vierter kleiner Ring (Krone)
-- sinkt langsamer und landet schief ueber dem Kopf des Gegners (Pointe), bei
-- `popAt` zerplatzt er zu Funken. Setzt ctx.seraphGate und ctx.seraphGateR.
--   at, lift, radius, open, raysAt, ticks {}, offAt, fallAt, fallFor, popAt, dur
--   (Test: freezeAt)
BLOCKS.halogate = function(ctx, s)
	local lift = s.lift or 24
	local R = s.radius or 16
	local open = s.open or 0.55
	local raysAt = s.raysAt or 0.35
	local ticks: { number } = if type(s.ticks) == "table" then s.ticks else {}
	local offAt = s.offAt or 2.18
	local fallAt = s.fallAt or 2.7
	local fallFor = s.fallFor or 0.55
	local popAt = s.popAt or 4.55
	local dur = s.dur or 4.6
	local freezeAt: number? = s.freezeAt
	local center = at(ctx, s.at or "arena") + Vector3.new(0, lift, 0)
	ctx.seraphGate = center
	ctx.seraphGateR = R
	local flat = CFrame.new(center)   -- lokale XZ-Ebene = waagerecht
	local rings: { SeraphGateRing } = {
		{ ring = novaRing(SER.CREAM, 0.6, 0.12, 14), r0 = 1.0, w0 = 1.3, tr = 0.12, spin = 0.0, h = 14, r1 = 7.0, order = 1 },
		{ ring = novaRing(SER.HONEY, 0.3, 0.25, 14), r0 = 0.84, w0 = 0.28, tr = 0.25, spin = 0.35, h = 9.5, r1 = 5.0, order = 2 },
		{ ring = novaRing(SER.GOLD, 0.35, 0.2, 14), r0 = 0.72, w0 = 0.55, tr = 0.2, spin = -0.6, h = 5.0, r1 = 3.4, order = 3 },
	}
	-- gestrichelter Innenring (4 Striche je Viertel; NumberSequence erlaubt 20 Stuetzen)
	local dashed: { { number } } = {}
	for i = 0, 3 do
		local a = i / 4
		table.insert(dashed, { a, 0.2 })
		table.insert(dashed, { a + 0.16, 0.2 })
		table.insert(dashed, { a + 0.17, 1 })
		table.insert(dashed, { a + 0.245, 1 })
	end
	table.insert(dashed, { 1, 0.2 })
	for i = 1, 4 do rings[3].ring.pattern(i, dashed) end
	-- Krone (Pointe)
	local crown = novaRing(SER.HALO, 0.5, 0.1, 10)
	local crownR = 0.9
	-- Lichtschaefte: ein Anker in der Tormitte, Attachments lokal (drehen mit dem Anker)
	local nRays = if extrasOn(ctx) then 8 else 5
	local rayAnchor = newPart(Enum.PartType.Block, Vector3.one * 0.2, SER.CREAM, flat, 1)
	rayAnchor.Name = "SeraphRays"
	local rays: { Beam } = {}
	for i = 1, nRays do
		local a = (i - 1) / nRays * TAU
		local top = Instance.new("Attachment")
		top.Parent = rayAnchor
		top.Position = Vector3.new(math.cos(a) * R * 0.8, 0, math.sin(a) * R * 0.8)
		local low = Instance.new("Attachment")
		low.Parent = rayAnchor
		low.Position = Vector3.new(math.cos(a + 0.25) * R * 0.45, -lift + 0.3, math.sin(a + 0.25) * R * 0.45)
		local b = SER.beam(top, low, 1.4, 4.6, Color3.fromRGB(255, 236, 190), 0.3, 1)
		b.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 1) })
		table.insert(rays, b)
	end
	local hitP: Vector3? = nil
	local fellSound = false
	local popped = false
	local lastRayA = -1
	local function raysAlpha(a: number)
		if math.abs(a - lastRayA) < 0.01 then return end
		lastRayA = a
		local seq = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1 - 0.45 * a), NumberSequenceKeypoint.new(1, 1 - 0.15 * a) })
		for _, b in rays do b.Transparency = seq end
	end
	local function pulseAt(t: number): number
		-- Puls (0..1) kurz nach jedem Tick
		local best = 0
		for _, tk in ticks do
			local q = t - tk
			if q >= 0 and q < 0.22 then best = math.max(best, 1 - q / 0.22) end
		end
		return best
	end

	runLoop("halogate", function(tRaw)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		local pulse = pulseAt(t)
		local openK = easeOutCubic(math.clamp(t / open, 0, 1))
		local pop = easeOutBack(math.clamp(t / 0.1, 0, 1))
		local scaleR = (0.06 + 0.94 * openK) * (0.9 + 0.1 * pop)
		local fading = math.clamp((t - (dur - 0.5)) / 0.4, 0, 1)
		if t < fallAt then
			for _, g in rings do
				local r = R * g.r0 * scaleR
				local w = g.w0 * math.min(1, t / 0.12) * (1 + 0.35 * pulse)
				g.ring.place(flat * CFrame.Angles(0, t * g.spin, 0), r, w)
				g.ring.alpha(math.clamp(openK * 1.5, 0, 1) * (1 - fading))
			end
			local rk = math.clamp((t - raysAt) / 0.4, 0, 1)
			local off = if t >= offAt then math.clamp(1 - (t - offAt) / 0.06, 0, 1) else 1
			raysAlpha(rk * off * (0.75 + 0.25 * pulse))
			rayAnchor.CFrame = flat * CFrame.Angles(0, t * 0.12, 0)
			crown.place(flat, 0.01, 0.01)
			crown.alpha(0)
		else
			raysAlpha(0)
			if not hitP then
				hitP = ctx.seraphHit or ctx.targetFeet
			end
			local hp = hitP :: Vector3
			local q = math.clamp((t - fallAt) / fallFor, 0, 1)
			local e = q * q * q   -- Fall beschleunigt
			for _, g in rings do
				local land = Vector3.new(hp.X, hp.Y + g.h, hp.Z)
				local pos = center:Lerp(land, e)
				local r = lerpN(R * g.r0, g.r1, e)
				local w = g.w0
				local a = 1
				if q >= 1 then
					-- Kondensring: dehnt sich, verblasst in 1 s (gestaffelt)
					local q2 = math.clamp((t - fallAt - fallFor - (g.order - 1) * 0.12) / 1.0, 0, 1)
					r = g.r1 + 2.6 * easeOutCubic(q2)
					w = g.w0 * (1 - 0.5 * q2)
					a = 1 - q2
				end
				g.ring.place(CFrame.new(pos) * CFrame.Angles(0, t * g.spin, 0), r, w)
				g.ring.alpha(a * (1 - fading))
			end
			if not fellSound and q >= 1 then
				fellSound = true
				burstAt(ctx, hp + Vector3.new(0, 1, 0), 20, 8, SER.GOLD)
			end
			-- Krone: langsamer, landet schief ueber dem Kopf des Gegners
			local headY = ctx.targetFeet.Y + ctx.targetSize.Y + 0.5
			local head = Vector3.new(ctx.targetFeet.X, headY, ctx.targetFeet.Z)
			local qc = math.clamp((t - fallAt) / (fallFor + 0.7), 0, 1)
			local ec = easeInOutSine(qc)
			local cpos = center:Lerp(head, ec)
			local tilt = math.rad(22) * ec
			local wob = if qc >= 1 then math.sin((t - fallAt) * 6) * 0.08 else 0
			local cr = lerpN(R * 0.5, crownR, ec)
			crown.place(CFrame.new(cpos) * CFrame.Angles(tilt + wob, t * 1.5, 0), cr, lerpN(0.6, 0.18, ec))
			if t >= popAt then
				if not popped then
					popped = true
					burstAt(ctx, cpos, 16, 6, SER.HALO)
				end
				crown.alpha(math.clamp(1 - (t - popAt) / 0.05, 0, 1))
			else
				crown.alpha(math.clamp((t - fallAt) / 0.3, 0, 1))
			end
		end
		return false
	end, function()
		for _, g in rings do g.ring.destroy() end
		crown.destroy()
		rayAnchor:Destroy()
	end)
end

-- seraphmark: Zielmarke unter dem Gegner: ein goldener Heiligenschein (Decal-
-- Platte, Bild `halo`) schrumpft von `radius` auf `shrinkTo`, bei jedem
-- `ticks` blitzt er (twinkle) - ein Lichtfaden vom Himmelstor (ctx.seraphGate)
-- laeuft beim ersten Tick herab in die Marke. Der Gegner (echter Klon, Original
-- lokal unsichtbar, F03) schaut hoch, zittert immer schneller, hopst bei den
-- Ticks; bei `releaseAt` (kurz vor impactAt) verschwindet der Klon, das
-- Original zeigt den Server-Rueckstoss (F15).
--   at, radius, shrinkTo, ticks {}, releaseAt, dur (Test: freezeAt)
BLOCKS.seraphmark = function(ctx, s)
	local r0 = s.radius or 5.5
	local r1 = s.shrinkTo or 1.6
	local ticks: { number } = if type(s.ticks) == "table" then s.ticks else {}
	local releaseAt = s.releaseAt or 0.96
	local dur = s.dur or 1.0
	local freezeAt: number? = s.freezeAt
	local g = groundAt(ctx, s.at or "target") + Vector3.new(0, 0.08, 0)
	local halo = texOf(ctx, "halo")
	local plate = newPart(Enum.PartType.Block, Vector3.new(r0 * 2, 0.05, r0 * 2), SER.GOLD, CFrame.new(g), 1)
	plate.Name = "SeraphMark"
	local decal: Decal? = nil
	local ringBeam: NovaRing? = nil
	if halo then
		local d0 = addDecal(plate, halo, Enum.NormalId.Top, SER.GOLD)
		d0.Transparency = 0.15
		decal = d0
	else
		ringBeam = novaRing(SER.GOLD, 0.4, 0.2, 12)
	end
	-- Lichtfaden vom Tor
	local gate = ctx.seraphGate or (g + Vector3.new(0, 24, 0))
	local topP, topA = SER.anchorAt(gate)
	local lowP, lowA = SER.anchorAt(gate)
	local thread = SER.beam(topA, lowA, 0.32, 0.14, SER.CREAM, 0.5, 1)
	local threadOn = false
	-- Gegner-Klon
	local source = ctx.targetModel
	local clone: Model? = if source and source.Parent then figureClone(source) else nil
	local hide: ((number) -> ())? = nil
	local tOff: CFrame = CFrame.identity
	local Ht = ctx.targetSize.Y
	local tHome = CFrame.lookAt(ctx.targetFeet, ctx.targetFeet - ctx.fwd)
	if clone and source then
		tOff = tHome:ToObjectSpace(clone:GetPivot())
		local hl = Instance.new("Highlight")
		hl.Adornee = clone
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.FillColor = SER.CREAM
		hl.FillTransparency = 0.9
		hl.OutlineColor = SER.HONEY
		hl.OutlineTransparency = 0.1
		hl.Parent = clone
		clone.Parent = folder()
		hide = hideFigure(source)
		;(hide :: (number) -> ())(1)
	end
	local released = false
	local function release()
		if released then return end
		released = true
		if hide then hide(0) end
		if clone then clone:Destroy() end
	end
	local tickDone: { boolean } = {}
	local hop = 0

	runLoop("seraphmark", function(tRaw, dt)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		local q = math.clamp(t / (dur * 0.92), 0, 1)
		local r = lerpN(r0, r1, easeInOutSine(q))
		local pulse = 0
		for i, tk in ticks do
			local d = t - tk
			if d >= 0 and d < 0.2 then pulse = math.max(pulse, 1 - d / 0.2) end
			if d >= 0 and not tickDone[i] then
				tickDone[i] = true
				twinkle(g + Vector3.new(0, 0.6, 0), 1.6 + 0.4 * i, SER.CREAM, 0.3)
				hop = 0.25 + 0.1 * i
				if i == 1 then
					threadOn = true
					tween(lowP, 0.25, { CFrame = CFrame.new(g + Vector3.new(0, 0.3, 0)) }, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
				end
			end
		end
		plate.Size = Vector3.new(r * 2, 0.05, r * 2)
		plate.CFrame = CFrame.new(g) * CFrame.Angles(0, t * 0.6, 0)
		local appear = math.clamp(t / 0.15, 0, 1)
		if decal then
			(decal :: Decal).Transparency = 1 - (0.85 + 0.15 * pulse) * appear
		elseif ringBeam then
			(ringBeam :: NovaRing).place(CFrame.new(g + Vector3.new(0, 0.1, 0)), r, 0.4)
			;(ringBeam :: NovaRing).alpha(appear)
		end
		if threadOn then
			thread.Transparency = NumberSequence.new(1 - (0.55 + 0.45 * pulse))
			thread.Width0 = 0.32 + 0.3 * pulse
			thread.Width1 = 0.14 + 0.2 * pulse
		end
		-- Gegner: schaut hoch, zittert schneller, hopst bei den Ticks
		if clone and clone.Parent and not released then
			hop = math.max(0, hop - dt * 1.6)
			local look = math.clamp(t / 0.35, 0, 1)
			local f = 18 + 50 * q
			local tremble = (0.012 + 0.025 * q) * math.sin(t * f)
			local pitch = 0.22 * easeInOutSine(look)
			local y = 4 * hop * (1 - hop) * 0.5
			local half = Ht * 0.5
			local pose = tHome * CFrame.new(0, half + y, 0) * CFrame.Angles(pitch, 0, tremble) * CFrame.new(0, -half, 0)
			clone:PivotTo(pose * CFrame.new(tOff.Position) * tOff.Rotation)
		end
		if t >= releaseAt then release() end
		return false
	end, function()
		release()
		plate:Destroy()
		if ringBeam then (ringBeam :: NovaRing).destroy() end
		topP:Destroy()
		lowP:Destroy()
	end)
end

-- lightnuke: das Ende als Nuke in himmlischer Haut (2.5): bei 0 ein kleiner
-- goldener Kern (F36); ab `columnAt` eine Lichtsaeule (zwei Beams mit dem
-- Bild `column`: Kern warm-weiss, Huelle Gold) schiesst vom Einschlag
-- (ctx.seraphHit, sonst `at`) `height` Studs hoch (durch das Himmelstor), ab
-- `waveAt` die Druckwelle: eine Wand aus Licht (hellRing, heller Rand) rast bis
-- zum Zaun, eine zweite schmale dahinter; Brandfleck (dunkle Scheibe, Bild
-- `halo` als goldenes Siegel, sechs goldene Risse) bleibt bis `dur`; ab
-- `domeAt` drueckt die Saeule eine goldene Kuppel hoch (ForceField, zwei
-- Schalen, Radius `dome` in `domeFor` s), die Kuppel verblasst, Glut steigt.
-- Weit entfernte Zuschauer (ctx.far) sehen nur Kern und Saeule (`global`).
--   at, core, columnAt, height, waveAt, domeAt, dome, domeFor, scorch, dur
--   (Test: freezeAt)
BLOCKS.lightnuke = function(ctx, s)
	local hit: Vector3 = ctx.seraphHit or groundAt(ctx, s.at or "target")
	local coreFor = s.core or 0.2
	local columnAt = s.columnAt or 0.12
	local height = s.height or 160
	local waveAt = s.waveAt or 0.15
	local domeAt = s.domeAt or 0.6
	local domeR = s.dome or 11
	local domeFor = s.domeFor or 0.7
	local scorchR = s.scorch or 3.6
	local dur = s.dur or 2.5
	local freezeAt: number? = s.freezeAt
	local fenceR = radiusOf("fence", 24.6)
	local column = texOf(ctx, "column")
	local haloTex = texOf(ctx, "halo")
	local bodyR = math.max(ctx.targetSize.X, ctx.targetSize.Z) * 0.5

	-- Kern
	local core = newPart(Enum.PartType.Ball, Vector3.one * 0.6, SER.GOLD:Lerp(Color3.new(1, 1, 1), 0.55), CFrame.new(hit + Vector3.new(0, 1.2, 0)), 0.25)
	core.Name = "SeraphCore"
	-- Saeule
	local baseP, baseA = SER.anchorAt(hit + Vector3.new(0, 0.2, 0))
	local topP, topA = SER.anchorAt(hit + Vector3.new(0, 2, 0))
	local colCore = SER.beam(topA, baseA, 2.6, 2.6, SER.CREAM, 0.6, 1, column)
	local colShell = SER.beam(topA, baseA, 7.0, 6.0, SER.GOLD, 0.35, 1, column)
	local colLight = Instance.new("PointLight")
	colLight.Color = SER.GOLD
	colLight.Brightness = 0
	colLight.Range = 40
	colLight.Parent = baseP
	-- Druckwelle (zwei Lichtwaende)
	local waveP = newPart(Enum.PartType.Block, Vector3.one * 0.2, SER.CREAM, CFrame.new(hit), 1)
	waveP.Name = "SeraphWave"
	local wave1: HellRing? = nil
	local wave2: HellRing? = nil
	-- Brandfleck
	local scorchP: BasePart? = nil
	local sigil: Decal? = nil
	local cracksDone = false
	-- Kuppel
	local domeOuter: BasePart? = nil
	local domeInner: BasePart? = nil
	local embers: ParticleEmitter? = nil
	local emberP: BasePart? = nil
	local far = ctx.far

	runLoop("lightnuke", function(tRaw)
		if tRaw >= (if freezeAt then freezeAt + 150 else dur) then return true end
		local t = if freezeAt then math.min(tRaw, freezeAt) else tRaw
		-- Kern: klein, kurz, getoent
		if t < coreFor then
			local q = t / coreFor
			local rr = lerpN(0.3, 3.2 * bodyR, easeOutCubic(q))
			core.Size = Vector3.one * rr * 2
			core.Transparency = 0.25 + 0.75 * q
		elseif core.Transparency < 1 then
			core.Transparency = 1
		end
		-- Saeule
		if t >= columnAt then
			local q = math.clamp((t - columnAt) / 0.18, 0, 1)
			local h = lerpN(2, height, easeOutCubic(q))
			topP.CFrame = CFrame.new(hit + Vector3.new(0, h, 0))
			local fadeQ = math.clamp((t - (columnAt + 1.6)) / 0.5, 0, 1)
			local wCore = 2.6 * (1 - 0.8 * fadeQ) * (1 + 0.15 * math.sin(t * 14))
			local wShell = 7.0 * (1 - 0.8 * fadeQ)
			colCore.Width0 = wCore
			colCore.Width1 = wCore
			colShell.Width0 = wShell
			colShell.Width1 = wShell * 0.85
			colCore.Transparency = NumberSequence.new(0.15 + 0.85 * fadeQ)
			colShell.Transparency = NumberSequence.new(0.55 + 0.45 * fadeQ)
			colLight.Brightness = 2.5 * (1 - fadeQ)
		end
		if far then return false end
		-- Druckwelle: Wand aus Licht bis zum Zaun
		if t >= waveAt then
			if not wave1 then
				wave1 = hellRing(waveP, 1, 1.0, 2.6, SER.CREAM, 0.5, 0.15)
				wave2 = hellRing(waveP, 1, 0.6, 1.2, SER.GOLD, 0.35, 0.25)
			end
			local q = math.clamp((t - waveAt) / 0.45, 0, 1)
			local e = easeOutCubic(q)
			local r = lerpN(1, fenceR, e)
			local w = lerpN(2.6, 1.0, e)
			;(wave1 :: HellRing).set(r, w * 0.5 + 0.2, w)
			hellFade((wave1 :: HellRing).beams, 0.15, 1 - q)
			local q2 = math.clamp((t - waveAt - 0.1) / 0.5, 0, 1)
			local r2 = lerpN(1, fenceR, easeOutCubic(q2))
			;(wave2 :: HellRing).set(r2, 0.6, 1.2 * (1 - 0.5 * q2))
			hellFade((wave2 :: HellRing).beams, 0.25, if t >= waveAt + 0.1 then 1 - q2 else 0)
		end
		-- Brandfleck + Risse (bleiben bis dur)
		if t >= columnAt and not scorchP then
			local sp = newPart(Enum.PartType.Cylinder, Vector3.new(0.08, scorchR * 2, scorchR * 2), SER.SCORCH,
				CFrame.new(hit + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90)), 0.1)
			sp.Material = Enum.Material.SmoothPlastic
			sp.Name = "SeraphScorch"
			scorchP = sp
			if haloTex then
				local plate = newPart(Enum.PartType.Block, Vector3.new(scorchR * 1.9, 0.05, scorchR * 1.9), SER.GOLD, CFrame.new(hit + Vector3.new(0, 0.12, 0)), 1)
				plate.Name = "SeraphSigil"
				sigil = addDecal(plate, haloTex, Enum.NormalId.Top, SER.GOLD)
				Debris:AddItem(plate, dur + 0.1)
			end
		end
		if t >= columnAt + 0.05 and not cracksDone then
			cracksDone = true
			for i = 1, 6 do
				local a = (i - 1) / 6 * TAU + 0.3
				local dir = Vector3.new(math.cos(a), 0, math.sin(a))
				local len = scorchR + 1.2 + math.random() * 1.8
				groundStroke(ctx, hit + dir * 0.6 + Vector3.new(0, 0.1, 0), hit + dir * len + Vector3.new(0, 0.1, 0),
					0.28, SER.HONEY, 0, 0.18, dur - 0.55)
			end
		end
		if sigil then
			local pulse = 0.5 + 0.5 * math.sin(t * 4)
			local fadeQ = math.clamp((t - (dur - 0.45)) / 0.4, 0, 1)
			;(sigil :: Decal).Transparency = (0.08 + 0.25 * pulse) + (1 - (0.08 + 0.25 * pulse)) * fadeQ
		end
		if scorchP then
			local fadeQ = math.clamp((t - (dur - 0.45)) / 0.4, 0, 1)
			;(scorchP :: BasePart).Transparency = 0.1 + 0.9 * fadeQ
		end
		-- Kuppel
		if t >= domeAt then
			if not domeOuter then
				local o = newPart(Enum.PartType.Ball, Vector3.one, SER.GOLD, CFrame.new(hit + Vector3.new(0, 0.4, 0)), 0.3)
				o.Material = Enum.Material.ForceField
				o.Name = "SeraphDome"
				domeOuter = o
				local inn = newPart(Enum.PartType.Ball, Vector3.one, SER.CREAM, CFrame.new(hit + Vector3.new(0, 0.4, 0)), 0.55)
				inn.Material = Enum.Material.ForceField
				inn.Name = "SeraphDomeInner"
				domeInner = inn
				local ep = newPart(Enum.PartType.Block, Vector3.new(domeR, 0.3, domeR), SER.GOLD, CFrame.new(hit + Vector3.new(0, 0.5, 0)), 1)
				emberP = ep
				local em = Instance.new("ParticleEmitter")
				em.Texture = SPARK_TEX
				em.Shape = Enum.ParticleEmitterShape.Box
				em.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
				em.Rate = 0
				em.Speed = NumberRange.new(3, 7)
				em.SpreadAngle = Vector2.new(20, 20)
				em.Lifetime = NumberRange.new(0.8, 1.5)
				em.Drag = 1
				em.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
				em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
				em.Color = ColorSequence.new(SER.CREAM, SER.GOLD)
				em.LightEmission = 0.6
				em.Parent = ep
				embers = em
				em:Emit(scaled(36, ctx.factor))
			end
			local q = math.clamp((t - domeAt) / domeFor, 0, 1)
			local rr = lerpN(2, domeR, easeOutCubic(q))
			local holdEnd = domeAt + domeFor + 0.45
			local fadeQ = math.clamp((t - holdEnd) / 0.6, 0, 1)
			local o = domeOuter :: BasePart
			local inn = domeInner :: BasePart
			o.Size = Vector3.one * rr * 2
			inn.Size = Vector3.one * rr * 1.7
			o.Transparency = 0.3 + 0.7 * fadeQ
			inn.Transparency = 0.55 + 0.45 * fadeQ
		end
		return false
	end, function()
		core:Destroy()
		baseP:Destroy()
		topP:Destroy()
		waveP:Destroy()
		if scorchP then (scorchP :: BasePart):Destroy() end
		if domeOuter then (domeOuter :: BasePart):Destroy() end
		if domeInner then (domeInner :: BasePart):Destroy() end
		if emberP then Debris:AddItem(emberP :: BasePart, 1.6) end
	end)
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
	bonus    : boolean?,   -- Finisher/Opener hat gegriffen: Schritte mit `bonus = true` laufen mit
}

function SkillFXController.play(req: PlayRequest)
	local fx = SkillFXConfig.get(req.skillId)
	local selfPos = centerOf(req.attacker) or req.center
	if not selfPos then return end
	local targetPos = centerOf(req.target) or (selfPos + Vector3.new(0, 0, -8))
	local isOwner = req.owner == player.UserId

	-- v16: weit weg = nur Schritte mit `global = true` (z. B. die Omega-
	-- Lichtsaeule, die man von der Hauptinsel sieht) und nur in der vollen Show.
	local far = false
	if not isOwner then
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or (root.Position - selfPos).Magnitude > SPECTATOR_DISTANCE then
			far = true
		end
	end
	if far and not req.full then
		return
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
		far = far,
		bonus = req.bonus == true,
	}

	-- Schritte abspielen (volle Show oder eigenes Echo), je Schritt EIN
	-- verzoegerter Aufruf; Fehler eines Bausteins stoppen die Show nicht.
	local function run(steps: { SkillFXConfig.Step }, limit: number, echo: boolean)
		for _, step in steps do
			local block = BLOCKS[step.fx]
			if block and not (step.extra and not extrasOn(ctx)) and not (step.ownerOnly and not ctx.isOwner)
				and not (ctx.far and not step.global)
				and not (step.bonus and not ctx.bonus)
			then
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
				and step.fx ~= "flash" and step.fx ~= "shake" and not step.bonus
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
