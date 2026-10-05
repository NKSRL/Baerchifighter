--!strict
-- AmbienceController.luau
-- StarterPlayerScripts/Controllers/AmbienceController.luau
--
-- Einzige Zustaendigkeit:
--   - Lebendige Himmels-Kulisse nur auf dem Client: treibende Wolkenpuffs,
--     ferne Schwebeinseln, schwebender Pollen um die Kamera und das leise
--     Atmen der Schaumsaeume um die Inseln
--
-- Warum auf dem Client: Kulisse ist fuer jeden Spieler gleich und hat keine
-- Spielwirkung. Gebaut auf dem Server wuerde sie repliziert und der Server
-- muesste sie bewegen; hier kostet sie das Netzwerk nichts und die Rechenzeit
-- bezahlt nur, wer sie sieht. Zahlen in AmbienceConfig.
--
-- PERFORMANCE:
--   * Alle Wolken sind EIN Model und werden pro Frame mit EINEM PivotTo
--     gedreht; die Schwebeinseln je EIN PivotTo. Keine Schleife ueber Parts.
--   * Alle Parts: Anchored, ohne Kollision, ohne Query, ohne Schatten. Die
--     Kamera-Zoom-Logik und Klick-Raycasts sehen sie nicht.
--   * Schwache Geraete (Grafikstufe < AmbienceConfig.HIGH_QUALITY_FROM) bekommen
--     weniger Wolken, weniger Inseln und keinen Pollen.
--   * Der Schaum wird nur 10 mal pro Sekunde aktualisiert.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local AmbienceConfig = require(ReplicatedStorage.Config.AmbienceConfig)
local MapConfig      = require(ReplicatedStorage.Config.MapConfig)

local AmbienceController = {}

local FOAM_TICK = 0.1

local _folder: Folder? = nil
local _cloudModel: Model? = nil
local _cloudBase: CFrame = CFrame.new()
local _islands: { { model: Model, base: CFrame, phase: number } } = {}
local _foamParts: { { part: Part, phase: number } } = {}
local _pollenPart: Part? = nil

--------------------------------------------------------------------------------
-- Qualitaet
--------------------------------------------------------------------------------

local function isHighQuality(): boolean
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value
	end)
	if not ok then
		return true
	end
	-- 0 = Automatisch: zaehlt als hoch, Roblox regelt dort selbst nach.
	return level == 0 or level >= AmbienceConfig.HIGH_QUALITY_FROM
end

--------------------------------------------------------------------------------
-- Bausteine
--------------------------------------------------------------------------------

local function newPart(name: string, parent: Instance, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType): Part
	local part = Instance.new("Part")
	part.Name          = name
	part.Anchored      = true
	part.CanCollide    = false
	part.CanQuery      = false
	part.CanTouch      = false
	part.CastShadow    = false
	part.Size          = size
	part.CFrame        = cframe
	part.Color         = color
	part.Material      = material
	part.Shape         = shape
	part.TopSurface    = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent        = parent
	return part
end

--------------------------------------------------------------------------------
-- Wolkenpuffs
--------------------------------------------------------------------------------

-- Ein Puff = vier bis fuenf ueberlappende, plattgedrueckte Baelle.
local function buildCloudPuff(parent: Instance, position: Vector3, random: Random)
	local scale = random:NextNumber(0.8, 1.4)
	local lumps = random:NextInteger(4, 5)

	for i = 1, lumps do
		local w = random:NextNumber(60, 110) * scale
		local offset = Vector3.new(
			(i - (lumps + 1) / 2) * 45 * scale + random:NextNumber(-12, 12),
			random:NextNumber(-6, 10),
			random:NextNumber(-20, 20)
		)
		local part = newPart(
			"Puff", parent,
			Vector3.new(w, w * 0.38, w * 0.7),
			CFrame.new(position + offset),
			AmbienceConfig.CLOUD_COLOR,
			Enum.Material.SmoothPlastic,
			Enum.PartType.Ball
		)
		part.Transparency = 0.12
	end
end

local function buildClouds(parent: Instance, count: number, random: Random)
	local model = Instance.new("Model")
	model.Name = "Clouds"

	for i = 1, count do
		-- Gleichmaessig um den Kreis verteilt, mit Zufall in Abstand und Hoehe.
		local angle  = (i - 1) / count * math.pi * 2 + random:NextNumber(-0.15, 0.15)
		local radius = random:NextNumber(AmbienceConfig.CLOUD_RING_MIN, AmbienceConfig.CLOUD_RING_MAX)
		local height = random:NextNumber(AmbienceConfig.CLOUD_HEIGHT_MIN, AmbienceConfig.CLOUD_HEIGHT_MAX)

		buildCloudPuff(model, Vector3.new(
			MapConfig.CENTER.X + radius * math.cos(angle),
			height,
			MapConfig.CENTER.Z + radius * math.sin(angle)
		), random)
	end

	model.Parent = parent
	_cloudModel = model
	_cloudBase  = model:GetPivot()
end

--------------------------------------------------------------------------------
-- Ferne Schwebeinseln
--------------------------------------------------------------------------------

local function buildFarIsland(parent: Instance, angle: number, random: Random, index: number)
	local model = Instance.new("Model")
	model.Name = "FarIsland"

	local base = Vector3.new(
		MapConfig.CENTER.X + AmbienceConfig.FAR_ISLAND_RING * math.cos(angle),
		AmbienceConfig.FAR_ISLAND_HEIGHT + random:NextNumber(-20, 40),
		MapConfig.CENTER.Z + AmbienceConfig.FAR_ISLAND_RING * math.sin(angle)
	)
	local size = random:NextNumber(70, 110)

	-- Felsbrocken darunter (ein umgedrehter, plattgedrueckter Ball), Wiese oben drauf.
	newPart("Rock", model, Vector3.new(size, size * 0.7, size),
		CFrame.new(base + Vector3.new(0, -size * 0.28, 0)),
		Color3.fromRGB(140, 130, 150), Enum.Material.Slate, Enum.PartType.Ball)
	newPart("Grass", model, Vector3.new(4, size, size),
		CFrame.new(base) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(96, 190, 92), Enum.Material.Grass, Enum.PartType.Cylinder)

	-- Ein Baum und ein Leuchtkristall, damit die Silhouette nicht langweilig ist.
	newPart("Trunk", model, Vector3.new(14, 4, 4),
		CFrame.new(base + Vector3.new(size * 0.15, 9, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(122, 84, 52), Enum.Material.Wood, Enum.PartType.Cylinder)
	newPart("Crown", model, Vector3.new(26, 20, 26),
		CFrame.new(base + Vector3.new(size * 0.15, 22, 0)),
		(index % 2 == 0) and Color3.fromRGB(255, 160, 190) or Color3.fromRGB(72, 170, 80),
		Enum.Material.Grass, Enum.PartType.Ball)

	model.Parent = parent
	table.insert(_islands, { model = model, base = model:GetPivot(), phase = random:NextNumber(0, math.pi * 2) })
end

--------------------------------------------------------------------------------
-- Pollen
--------------------------------------------------------------------------------

local function buildPollen(parent: Instance)
	local anchor = Instance.new("Part")
	anchor.Name         = "PollenAnchor"
	anchor.Anchored     = true
	anchor.CanCollide   = false
	anchor.CanQuery     = false
	anchor.CanTouch     = false
	anchor.CastShadow   = false
	anchor.Transparency = 1
	anchor.Size         = Vector3.new(140, 50, 140)
	anchor.Parent       = parent

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture       = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color         = ColorSequence.new(AmbienceConfig.POLLEN_COLOR)
	emitter.Size          = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.8),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency  = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.2, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime      = NumberRange.new(8, 12)
	emitter.Rate          = AmbienceConfig.POLLEN_RATE
	emitter.Speed         = NumberRange.new(0.5, 2)
	emitter.SpreadAngle   = Vector2.new(180, 180)
	emitter.Acceleration  = Vector3.new(0, 0.3, 0)
	emitter.LightEmission = 0.6
	emitter.LockedToPart  = false
	emitter.Shape         = Enum.ParticleEmitterShape.Box
	emitter.Parent        = anchor

	_pollenPart = anchor
end

--------------------------------------------------------------------------------
-- Schaum einsammeln
--------------------------------------------------------------------------------

local function collectFoam()
	local platform = workspace:WaitForChild("Platform", 30)
	if not platform then
		return
	end
	local scenery = platform:WaitForChild("Scenery", 30)
	local foam = scenery and scenery:WaitForChild("Foam", 30)
	if not foam then
		return
	end
	for _, child in foam:GetChildren() do
		if child:IsA("Part") then
			table.insert(_foamParts, { part = child, phase = (child:GetAttribute("FoamPhase") :: number?) or 0 })
		end
	end
end

--------------------------------------------------------------------------------
-- Einstieg
--------------------------------------------------------------------------------

function AmbienceController.init()
	local high   = isHighQuality()
	local random = Random.new(AmbienceConfig.SCENERY_SEED + 7)

	local folder = Instance.new("Folder")
	folder.Name   = "BaerchiAmbience"
	folder.Parent = workspace
	_folder = folder

	buildClouds(folder, high and AmbienceConfig.CLOUD_PUFFS_HIGH or AmbienceConfig.CLOUD_PUFFS_LOW, random)

	local islandCount = high and AmbienceConfig.FAR_ISLANDS_HIGH or AmbienceConfig.FAR_ISLANDS_LOW
	for i = 1, islandCount do
		-- Gleichmaessig verteilt, damit man von jeder Insel eine am Horizont sieht.
		buildFarIsland(folder, (i - 0.5) / islandCount * math.pi * 2, random, i)
	end

	if high then
		buildPollen(folder)
	end

	task.spawn(collectFoam)

	local clock = 0
	local foamClock = 0
	local cloudAngle = 0

	RunService.Heartbeat:Connect(function(dt: number)
		clock += dt

		-- Wolken: ein Pivot fuer alle.
		local clouds = _cloudModel
		if clouds then
			cloudAngle += dt * AmbienceConfig.CLOUD_DRIFT_SPEED
			-- Drehung um die Weltmitte, relativ zur Ausgangslage (das Model-Pivot liegt
			-- in der Mitte seiner Teile, nicht in der Weltmitte).
			clouds:PivotTo(CFrame.new(MapConfig.CENTER) * CFrame.Angles(0, cloudAngle, 0) * CFrame.new(-MapConfig.CENTER) * _cloudBase)
		end

		-- Schwebeinseln: sanftes Auf und Ab, ein Pivot je Insel.
		for _, island in _islands do
			island.model:PivotTo(island.base * CFrame.new(0, math.sin(clock * 0.35 + island.phase) * 5, 0))
		end

		-- Pollen folgt der Kamera.
		local anchor = _pollenPart
		local camera = workspace.CurrentCamera
		if anchor and camera then
			anchor.Position = camera.CFrame.Position + Vector3.new(0, 4, 0)
		end

		-- Schaum atmet, 10 mal pro Sekunde.
		foamClock += dt
		if foamClock >= FOAM_TICK then
			foamClock = 0
			local twoPi = math.pi * 2
			for _, foam in _foamParts do
				foam.part.Transparency = AmbienceConfig.FOAM_TRANSPARENCY
					+ math.sin(clock / AmbienceConfig.FOAM_PULSE_PERIOD * twoPi + foam.phase) * AmbienceConfig.FOAM_PULSE
			end
		end
	end)

	print("[Ambience] Kulisse aktiv |", high and "hoch" or "niedrig")
end

return AmbienceController
