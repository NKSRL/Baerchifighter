--!strict
-- DayCycleController.luau
-- StarterPlayerScripts/Controllers/DayCycleController.luau
--
-- Einzige Zustaendigkeit:
--   - Den Tageslauf auf dem Client zeigen (Paket A, "Welt aufwerten"): Uhr,
--     Licht, Atmosphaere, Bloom, Grund-Farbkorrektur, Wolkenfarbe, das
--     Leuchten von Laternen/Krone/Tropfen, Gluehwuermchen, Sterne und
--     Wolkenschleier
--
-- Woher die Zeit kommt: Modules/DayCycle, eine reine Funktion von
-- workspace:GetServerTimeNow(). Alle Spieler eines Servers sehen dieselbe
-- Tageszeit, ohne dass der Server etwas schickt.
--
-- Schalter: AmbienceConfig.DAY_CYCLE. Aus = dieser Controller tut nichts,
-- es bleibt der feste Himmel von SkyBuilder (16,9 Uhr).
--
-- Faehigkeiten-Shows haben Vorrang: SkillFXController legt fuer den Besitzer
-- einen EIGENEN Farbfilter "SkillFX_Sky" an, und der Boss-Himmel einen
-- eigenen "BossSky_Local". Dieser Controller schreibt nur in die Basis-
-- Effekte (BaerchiBloom, BaerchiColorCorrection, BaerchiAtmosphere) und in
-- Lighting — keine Seite ueberschreibt die andere, die Filter stapeln sich.
-- Zusaetzlich haelt der Tageslauf an, solange "SkillFX_Sky" faerbt, und
-- kehrt danach in DAY.RETURN_SECONDS weich zum aktuellen Stand zurueck: so
-- wandert das Licht nicht unter einer Show weg.
--
-- PERFORMANCE: EIN Takt (DAY.TICK, 5x pro Sekunde), Lighting-Werte sind
-- reine Property-Schreibvorgaenge. Leuchtende Teile werden nur umgefaerbt,
-- wenn sich das Leuchten um mehr als 1 % geaendert hat. Drei Emitter
-- (Gluehwuermchen, Sterne, Schleier), nur auf hoher Qualitaet.

local Lighting          = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local AmbienceConfig = require(ReplicatedStorage.Config.AmbienceConfig)
local FeatureFlags   = require(ReplicatedStorage.Config.FeatureFlags)
local MapConfig      = require(ReplicatedStorage.Config.MapConfig)
local WorldFXConfig  = require(ReplicatedStorage.Config.WorldFXConfig)
local DayCycle       = require(ReplicatedStorage.Modules.DayCycle)
local MapLayout      = require(ReplicatedStorage.Modules.MapLayout)

local WorldFXKit = require(script.Parent.WorldFXKit)

local DayCycleController = {}

local SHOW_FILTER = "SkillFX_Sky"
local GLOW_STEP   = 0.01

type Glow = { part: BasePart, day: Color3, night: Color3 }

local _values: { [string]: any } = DayCycle.valuesAt(WorldFXConfig.DAY_BASE_D)
local _dusk = WorldFXConfig.DAY_BASE_D
local _glows: { Glow } = {}
local _lastGlow = -1
local _cloudParts: { BasePart } = {}
local _pollen: ParticleEmitter? = nil      -- Paket F: Pollenfarbe folgt dem Tageslauf
local _lastPollen: Color3? = nil
local _lastCloud: Color3? = nil
local _override: number? = nil      -- Debug: feste Uhrzeit
local _held: { [string]: any }? = nil
local _returnStart = 0
local _returnFrom: { [string]: any }? = nil

local _fireflyAnchor: BasePart? = nil
local _firefly: ParticleEmitter? = nil
local _star: ParticleEmitter? = nil
local _wisp: ParticleEmitter? = nil

--------------------------------------------------------------------------------
-- Fuer andere Controller
--------------------------------------------------------------------------------

-- Aktuelle Werte (Schluessel wie WorldFXConfig.DAY_CURVES). Ohne Tageslauf:
-- die Werte bei 16,9 Uhr.
function DayCycleController.values(): { [string]: any }
	return _values
end

-- 0 = Nachmittag, 1 = blaue Stunde.
function DayCycleController.dusk(): number
	return _dusk
end

-- Ein Neon-Teil leuchtet mit dem Tageslauf: Farbe `day` bei glow = 0,
-- `night` bei glow = 1.
function DayCycleController.registerGlow(part: BasePart, day: Color3, night: Color3)
	table.insert(_glows, { part = part, day = day, night = night })
	part.Color = day:Lerp(night, math.clamp(_values.glow or 0, 0, 1))
end

--------------------------------------------------------------------------------
-- Show-Vorrang
--------------------------------------------------------------------------------

-- Faerbt gerade ein Show-Filter? (TintColor nicht weiss oder Helligkeit/
-- Saettigung/Kontrast nicht null.)
local function showActive(): boolean
	local cc = Lighting:FindFirstChild(SHOW_FILTER)
	if not (cc and cc:IsA("ColorCorrectionEffect")) then
		return false
	end
	local tint = cc.TintColor
	return tint.R < 0.99 or tint.G < 0.99 or tint.B < 0.99
		or math.abs(cc.Brightness) > 0.01 or math.abs(cc.Saturation) > 0.01 or math.abs(cc.Contrast) > 0.01
end

--------------------------------------------------------------------------------
-- Anwenden
--------------------------------------------------------------------------------

local function apply(v: { [string]: any }, clock: number)
	Lighting.ClockTime            = clock
	Lighting.Brightness           = v.brightness
	Lighting.Ambient              = v.ambient
	Lighting.OutdoorAmbient       = v.outdoorAmbient
	Lighting.ColorShift_Top       = v.colorShiftTop
	Lighting.ExposureCompensation = v.exposure

	local atm = Lighting:FindFirstChild("BaerchiAtmosphere")
	if atm and atm:IsA("Atmosphere") then
		atm.Density = v.atmDensity
		atm.Offset  = v.atmOffset
		atm.Color   = v.atmColor
		atm.Decay   = v.atmDecay
		atm.Glare   = v.atmGlare
		atm.Haze    = v.atmHaze
	end

	local bloom = Lighting:FindFirstChild("BaerchiBloom")
	if bloom and bloom:IsA("BloomEffect") then
		bloom.Intensity = v.bloomIntensity
		bloom.Threshold = v.bloomThreshold
		bloom.Size      = v.bloomSize
	end

	local cc = Lighting:FindFirstChild("BaerchiColorCorrection")
	if cc and cc:IsA("ColorCorrectionEffect") then
		cc.Saturation = v.ccSaturation
		cc.Contrast   = v.ccContrast
		cc.TintColor  = v.ccTint
	end

	local clouds = workspace.Terrain:FindFirstChildOfClass("Clouds")
	if clouds then
		clouds.Color = v.terrainCloudColor
	end

	-- Wolkenpuffs (AmbienceController): nur bei spuerbarer Aenderung
	local cloud: Color3 = v.cloudColor
	local last = _lastCloud
	if #_cloudParts > 0 and (not last or math.abs(last.R - cloud.R) + math.abs(last.G - cloud.G) + math.abs(last.B - cloud.B) > 0.01) then
		_lastCloud = cloud
		for _, part in _cloudParts do
			part.Color = cloud
		end
	end

	-- Leuchten
	if WorldFXKit.enabled("lampGlow") then
		local glow = math.clamp(v.glow, 0, 1)
		if math.abs(glow - _lastGlow) > GLOW_STEP then
			_lastGlow = glow
			for _, g in _glows do
				g.part.Color = g.day:Lerp(g.night, glow)
			end
		end
	end

	-- Pollen (Paket F): nur bei spuerbarer Aenderung
	local pollen = _pollen
	local pollenColor: Color3 = v.pollenColor
	local lastPollen = _lastPollen
	if pollen and (not lastPollen or math.abs(lastPollen.R - pollenColor.R) + math.abs(lastPollen.G - pollenColor.G)
		+ math.abs(lastPollen.B - pollenColor.B) > 0.01) then
		_lastPollen = pollenColor
		pollen.Color = ColorSequence.new(pollenColor)
	end

	-- Emitter: Rate folgt der Kurve
	local firefly = _firefly
	if firefly then
		firefly.Rate = WorldFXConfig.FIREFLY_RATE * v.fireflies
	end
	local star = _star
	if star then
		star.Rate = WorldFXConfig.STAR_RATE * v.stars
	end
	local wisp = _wisp
	if wisp then
		wisp.Color = ColorSequence.new(cloud)
	end
end

--------------------------------------------------------------------------------
-- Emitter
--------------------------------------------------------------------------------

local function newEmitter(anchor: BasePart, texture: string): ParticleEmitter?
	local emitter = Instance.new("ParticleEmitter")
	if not WorldFXKit.applyParticleTexture(emitter, texture) then
		emitter:Destroy()
		return nil
	end
	emitter.LockedToPart = false
	emitter.Shape = Enum.ParticleEmitterShape.Box
	emitter.Rate = 0
	emitter.Parent = anchor
	return emitter
end

local function buildEmitters(folder: Instance)
	if WorldFXKit.enabled("fireflies") then
		local anchor = WorldFXKit.anchor("FireflyAnchor", folder, WorldFXConfig.FIREFLY_BOX, Vector3.new(0, -100, 0))
		local e = newEmitter(anchor, "firefly")
		if e then
			e.Color = ColorSequence.new(WorldFXConfig.FIREFLY_COLOR)
			e.LightEmission = 1
			e.Lifetime = NumberRange.new(4, 7)
			e.Speed = NumberRange.new(0.3, 1.2)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.2, 0.45),
				NumberSequenceKeypoint.new(0.8, 0.45), NumberSequenceKeypoint.new(1, 0),
			})
			-- sanftes An- und Abschwellen (eine Kurve, weit unter 3 Hz)
			e.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.1),
				NumberSequenceKeypoint.new(0.6, 0.5), NumberSequenceKeypoint.new(0.8, 0.1),
				NumberSequenceKeypoint.new(1, 1),
			})
			_firefly = e
			_fireflyAnchor = anchor
		end
	end

	if WorldFXKit.enabled("stars") then
		local anchor = WorldFXKit.anchor("StarAnchor", folder, WorldFXConfig.STAR_BOX,
			Vector3.new(0, WorldFXConfig.STAR_HEIGHT, 0))
		local e = newEmitter(anchor, "star_twinkle")
		if e then
			e.Color = ColorSequence.new(Color3.new(1, 1, 1))
			e.LightEmission = 1
			e.Lifetime = NumberRange.new(10, 16)
			e.Speed = NumberRange.new(0, 0)
			e.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.15, 5),
				NumberSequenceKeypoint.new(0.85, 5), NumberSequenceKeypoint.new(1, 0),
			})
			e.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.2),
				NumberSequenceKeypoint.new(0.5, 0.45), NumberSequenceKeypoint.new(0.8, 0.2),
				NumberSequenceKeypoint.new(1, 1),
			})
			_star = e
		end
	end

	-- Schleier nur mit hochgeladenem Wolkenbild: der Rueckfall (Funkeln)
	-- saehe als Wolke falsch aus.
	if WorldFXKit.enabled("cloudWisps") and WorldFXKit.textureId("cloud_puff_flipbook") then
		local anchor = WorldFXKit.anchor("WispAnchor", folder, WorldFXConfig.WISP_BOX,
			Vector3.new(0, WorldFXConfig.WISP_HEIGHT, 0))
		local e = newEmitter(anchor, "cloud_puff_flipbook")
		if e then
			-- nicht blaettern: jede Wolke behaelt ihre Variante
			e.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
			e.FlipbookFramerate = NumberRange.new(0, 0)
			e.Rate = WorldFXConfig.WISP_RATE
			e.Lifetime = NumberRange.new(50, 70)
			e.Speed = NumberRange.new(0.5, 1.5)
			e.SpreadAngle = Vector2.new(10, 180)
			e.Size = NumberSequence.new(110)
			e.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.35),
				NumberSequenceKeypoint.new(0.8, 0.35), NumberSequenceKeypoint.new(1, 1),
			})
			_wisp = e
		end
	end
end

-- Gluehwuermchen auf offenes Wasser vor der Kamera legen. Kein Wasser in
-- Sicht: der Anker geht tief unter die Welt (Rate laeuft weiter, sieht keiner).
local function placeFireflies()
	local anchor = _fireflyAnchor
	local camera = workspace.CurrentCamera
	if not (anchor and camera) then return end
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(1, 0, 0)
	local eye = camera.CFrame.Position
	local waterY = MapConfig.PLATFORM_TOP_Y - MapConfig.WATER_DROP + 2.5   -- knapp ueber dem Wasser
	for _, turn in { 0, 0.6, -0.6, 1.2, -1.2 } do
		local dir = CFrame.Angles(0, turn, 0):VectorToWorldSpace(flat)
		local p = eye + dir * WorldFXConfig.FIREFLY_AHEAD
		if MapLayout.isOpenWater(p.X, p.Z, 8) then
			anchor.Position = Vector3.new(p.X, waterY, p.Z)
			return
		end
	end
	anchor.Position = Vector3.new(0, -200, 0)
end

--------------------------------------------------------------------------------
-- Einsammeln: Laternen, Tropfen, Wolken
--------------------------------------------------------------------------------

local function collectGlows()
	local platform = workspace:WaitForChild("Platform", 60)
	if not platform then return end
	local scenery = platform:WaitForChild("Scenery", 30)
	if scenery then
		for _, child in scenery:GetChildren() do
			if child:IsA("BasePart") and (WorldFXConfig.LAMP_NAMES :: any)[child.Name] then
				DayCycleController.registerGlow(child, WorldFXConfig.LAMP_DAY, WorldFXConfig.LAMP_NIGHT)
			end
		end
	end
	-- Der leuchtende Tropfen auf dem Honigmast
	local mast = platform:WaitForChild("Honigmast", 30)
	local drop = mast and mast:FindFirstChild("Tropfen", true)
	if drop and drop:IsA("BasePart") then
		DayCycleController.registerGlow(drop, WorldFXConfig.MAST.CELL_DAY:Lerp(drop.Color, 0.6), WorldFXConfig.MAST.CELL_NIGHT)
	end
	_lastGlow = -1
end

local function collectClouds()
	local ambience = workspace:WaitForChild("BaerchiAmbience", 30)
	if ambience and FeatureFlags.isOn("WORLD_F_LIFE") and WorldFXKit.enabled("pollenTint") then
		local anchor = ambience:FindFirstChild("PollenAnchor")
		local emitter = anchor and anchor:FindFirstChildOfClass("ParticleEmitter")
		if emitter then _pollen = emitter end
	end
	local clouds = ambience and ambience:WaitForChild("Clouds", 30)
	if not clouds then return end
	for _, part in clouds:GetDescendants() do
		if part:IsA("BasePart") then
			table.insert(_cloudParts, part)
		end
	end
	_lastCloud = nil
end

--------------------------------------------------------------------------------
-- Einstieg
--------------------------------------------------------------------------------

function DayCycleController.init()
	-- Debug (Studio): feste Uhrzeit fuer Screenshot-Vergleiche, "auto" = Zyklus
	WorldFXKit.onDebug("DebugDayTime", function(value: any)
		_override = if typeof(value) == "number" and value > 0 then value else nil
	end)

	if not (AmbienceConfig.DAY_CYCLE and WorldFXKit.enabled("dayCycle")) then
		print("[DayCycle] aus (fester Himmel)")
		return
	end

	local folder = WorldFXKit.folder("DayCycle", WorldFXKit.root())
	buildEmitters(folder)
	task.spawn(collectGlows)
	task.spawn(collectClouds)

	local acc = 0
	local fireflyAcc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc < WorldFXConfig.DAY.TICK then return end
		acc = 0

		local clock = _override or DayCycle.clockAt(workspace:GetServerTimeNow())
		local d = DayCycle.duskOf(clock)
		local live = DayCycle.valuesAt(d)

		-- Show-Vorrang: anhalten, danach weich zurueck
		if showActive() then
			if not _held then
				_held = _values
			end
			return
		end
		local held = _held
		if held then
			_held = nil
			_returnFrom = held
			_returnStart = os.clock()
		end
		local from = _returnFrom
		if from then
			local t = (os.clock() - _returnStart) / WorldFXConfig.DAY.RETURN_SECONDS
			if t >= 1 then
				_returnFrom = nil
			else
				live = DayCycle.blend(from, live, t * t * (3 - 2 * t))
			end
		end

		_values = live
		_dusk = d
		apply(live, clock)

		fireflyAcc += WorldFXConfig.DAY.TICK
		if fireflyAcc >= 1 then
			fireflyAcc = 0
			if live.fireflies > 0 then
				placeFireflies()
			end
		end
	end)

	print(string.format("[DayCycle] an | %d min Zyklus, %.1f–%.1f Uhr | %s",
		WorldFXConfig.DAY.PERIOD // 60, WorldFXConfig.DAY.CLOCK_MIN, WorldFXConfig.DAY.CLOCK_MAX,
		if WorldFXKit.quality() == 1 then "hoch" else "niedrig"))
end

return DayCycleController
