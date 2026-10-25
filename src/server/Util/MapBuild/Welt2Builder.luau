--!strict
-- Welt2Builder.luau
-- ServerScriptService/Util/MapBuild/Welt2Builder.luau
--
-- Einzige Zustaendigkeit (Welt 2, 21.10.): den Plot im Welt-2-Look bauen. Die Meshes
-- (Blender-Prototyp, 6 Gebaeude) liegen als Vorlagen in ServerStorage.Assets.Welt2
-- (Plot, Fusion, Brunnen, Inkubator, Recycler, Terminal). Jedes Teil traegt das
-- Attribut `tier` (additive Look-Stufe); Teile ohne `tier` sind immer da.
--
-- Der Builder ersetzt KEINE Spiel-Logik: Brunnen, Recycler, Inkubator und Terminal
-- behalten ihre Positionen und ihr Verhalten, die jeweiligen Builder rufen nur
-- `clone` statt der alten Deko auf. Aktiv ist der Look nur, wenn der Plot das
-- Attribut `World2` traegt (MapService setzt es aus WorldService) UND der Schalter
-- WELT2_LOOK an ist. Schalter aus / Vorlage fehlt = alter Look, nie ein Fehler.
--
-- Teil von MapService (und der Builder-Module). Aendert keine Spielerdaten.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerStorage       = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)
local MapConfig    = require(ReplicatedStorage.Config.MapConfig)
local MapParts     = require(ServerScriptService.Util.MapBuild.MapParts)

local Welt2Builder = {}

Welt2Builder.PLOT_ATTRIBUTE = "World2"
Welt2Builder.PLOT_MODEL     = "World2Plot"
Welt2Builder.FUSION_MODEL   = "World2Fusion"

-- Die Vorlagen haben ihre Bodenkante bei y = 0.65 ueber dem Modell-Ursprung
-- (Prototyp). Der Plot-Boden des Spiels liegt bei PLOT_SIZE.Y.
local TEMPLATE_FLOOR = 0.65
-- Fusionsmaschine: plot-lokal vor dem Brunnen (der steht hinten), kleiner als im
-- Prototyp, damit sie nicht in den Brunnen und den Inkubator ragt.
local FUSION_OFFSET = Vector3.new(33, 0, 20)   -- spiegelbildlich gegenueber dem Inkubator (-33, 20)
-- Inkubator: im Welt-2-Look ein Stueck zur Seite (plot-lokal), damit er Platz zur Fusionsmaschine hat.
Welt2Builder.INCUBATOR_SHIFT_X = -13
local FUSION_SCALE  = 0.7
-- Begehbarer Boden: das Beet (72x72) ist kleiner als der Welt-2-Boden (108x108).
local WALK_SIZE = 108
local RAMP_FROM = 54       -- plot-lokal z: Ende des Welt-2-Bodens
local RAMP_TO   = 58       -- Rand der Plot-Insel (hier beginnt der Steg)

-- Lichtstrahlen: plot-lokal (Spiel-Koordinaten), h = Hoehe, r = Radius.
local PLOT_BEAMS = {
	{ pos = Vector3.new(0, 21, 0), h = 48, r = 3.6 },
}
local CRYSTAL_BEAMS = {
	{ 54.36, 23.33, 10.81 }, { -30.79, 23.33, 46.08 }, { 46.08, 23.33, -30.79 }, { 54.36, 23.33, -10.81 },
	{ 46.08, 16.72, 30.79 }, { 30.79, 16.72, 46.08 }, { -30.79, 16.72, -46.08 }, { 46.08, 16.72, -30.79 },
	{ -30.79, 23.33, -46.08 }, { 30.79, 23.33, -46.08 }, { -46.08, 23.33, 30.79 }, { 46.08, 23.33, 30.79 },
}
-- Strahl ueber einem Gebaeude: Hoehe ab Gebaeudeboden, ab welchem Tier sichtbar
local BUILDING_BEAMS: { [string]: { y: number, h: number, r: number, tier: number } } = {
	Brunnen   = { y = 12.5, h = 22, r = 1.8, tier = 6 },
	Inkubator = { y = 9.2,  h = 20, r = 1.6, tier = 4 },
	Recycler  = { y = 10,   h = 18, r = 1.8, tier = 6 },
}

local BEAM_COLOR        = Color3.fromRGB(255, 190, 90)
local BEAM_TRANSPARENCY = 0.88

--------------------------------------------------------------------------------
-- Schalter und Vorlagen
--------------------------------------------------------------------------------

-- Ist der Welt-2-Look fuer diesen Plot an?
function Welt2Builder.enabled(plotModel: Instance?): boolean
	if not plotModel then return false end
	if not FeatureFlags.isOn("WELT2_LOOK") then return false end
	return plotModel:GetAttribute(Welt2Builder.PLOT_ATTRIBUTE) == true
end

local function templateOf(name: string): Model?
	local assets = ServerStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Welt2")
	local tpl = folder and folder:FindFirstChild(name)
	if tpl and tpl:IsA("Model") then return tpl end
	return nil
end

-- Klon der Vorlage mit den Teilen bis `tier`. Teilnamen verlieren das Praefix
-- "<Gebaeude>__" (Config und Client suchen z.B. "Bildschirm", "Lampe").
-- nil = Vorlage fehlt.
function Welt2Builder.clone(name: string, tier: number?): Model?
	local tpl = templateOf(name)
	if not tpl then return nil end
	local pivot = tpl:GetPivot()
	local model = tpl:Clone()
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local partTier = part:GetAttribute("tier")
			if tier and typeof(partTier) == "number" and partTier > tier then
				part:Destroy()
			else
				part.Name = (part.Name:gsub("^" .. name .. "__", ""))
				if part.Name == "Rec_L1_Lampe" then part.Name = "Lampe" end
				part.Anchored   = true
				part.CanCollide = false
				part.CanTouch   = false
				part.CanQuery   = false
				part.CastShadow = false
			end
		end
	end
	model.WorldPivot = pivot
	model:SetAttribute("Welt2", true)
	return model
end

-- Klon an `origin` (Gebaeude-Boden, -Z = vorne) in `parent` setzen.
function Welt2Builder.place(parent: Instance, name: string, origin: CFrame, tier: number?, modelName: string?): Model?
	local model = Welt2Builder.clone(name, tier)
	if not model then return nil end
	model.Name = modelName or name
	model:PivotTo(origin)
	model.Parent = parent
	return model
end

--------------------------------------------------------------------------------
-- Lichtstrahlen (Neon-Zylinder, sehr durchsichtig, ohne Kollision)
--------------------------------------------------------------------------------

local function beam(parent: Instance, name: string, center: CFrame, height: number, radius: number)
	local part = Instance.new("Part")
	part.Name         = name
	part.Shape        = Enum.PartType.Cylinder
	part.Size         = Vector3.new(height, radius * 2, radius * 2)
	part.CFrame       = center * CFrame.Angles(0, 0, math.rad(90))   -- Zylinder steht
	part.Color        = BEAM_COLOR
	part.Material     = Enum.Material.Neon
	part.Transparency = BEAM_TRANSPARENCY
	part.Anchored     = true
	part.CanCollide   = false
	part.CanTouch     = false
	part.CanQuery     = false
	part.CastShadow   = false
	part.Parent       = parent
end

-- Strahl ueber einem Gebaeude (Tier-abhaengig). `origin` = Gebaeudeboden.
function Welt2Builder.addBuildingBeam(model: Model, name: string, origin: CFrame, tier: number)
	local cfg = BUILDING_BEAMS[name]
	if not cfg or tier < cfg.tier then return end
	beam(model, "Strahl", origin * CFrame.new(0, cfg.y, 0), cfg.h, cfg.r)
end

--------------------------------------------------------------------------------
-- Plot: Boden, Saeulen, Krone, Fusionsmaschine
--------------------------------------------------------------------------------

-- Ursprung der Plot-Vorlage (Boden des Prototyps = Plot-Oberflaeche des Spiels).
function Welt2Builder.plotOrigin(slot: number): CFrame
	return MapParts.plotCFrame(slot) * CFrame.new(0, MapConfig.PLOT_SIZE.Y - TEMPLATE_FLOOR, 0)
end

-- Hoehe, um die Gebaeude ausserhalb des Beets (Recycler, Terminal) angehoben werden.
function Welt2Builder.groundLift(plotModel: Instance?): number
	if Welt2Builder.enabled(plotModel) then
		return MapConfig.PLOT_SIZE.Y - MapConfig.GRASS_HEIGHT
	end
	return 0
end

local function setLook(part: BasePart, color: Color3, material: Enum.Material?)
	part.Color = color
	if material then part.Material = material end
end

-- Baut Boden, Saeulen, Krone, Fusionsmaschine und Strahlen; das Beet bekommt
-- die dunkle Farbe und eine begehbare Platte in Welt-2-Groesse.
function Welt2Builder.buildPlot(plotModel: Model, slot: number): boolean
	local old = plotModel:FindFirstChild(Welt2Builder.PLOT_MODEL)
	if old then old:Destroy() end
	local oldFusion = plotModel:FindFirstChild(Welt2Builder.FUSION_MODEL)
	if oldFusion then oldFusion:Destroy() end

	local folder = Instance.new("Model")
	folder.Name = Welt2Builder.PLOT_MODEL
	local plotCFrame = MapParts.plotCFrame(slot)
	local surface = MapConfig.PLOT_SIZE.Y

	local floorModel = Welt2Builder.place(folder, "Plot", Welt2Builder.plotOrigin(slot), nil, "Plot")
	if not floorModel then
		folder:Destroy()
		return false
	end

	-- altes Beet: dunkel statt Gras, Karos und Terrassenkante unsichtbar/dunkel
	local dark = Color3.fromRGB(44, 38, 60)
	for _, child in plotModel:GetChildren() do
		if child:IsA("BasePart") then
			if child.Name == "Base" then
				setLook(child, Color3.fromRGB(62, 54, 82), Enum.Material.Slate)
				child.TopSurface = Enum.SurfaceType.Smooth
				child.Transparency = 1   -- die Platte drunter bleibt zum Laufen, sichtbar ist der Welt-2-Boden
			elseif child.Name == "BedTile" then
				child.Transparency = 1
			elseif child.Name:sub(1, 8) == "PlotCurb" then
				setLook(child, dark, Enum.Material.SmoothPlastic)
				child.Transparency = 1
				child.CanCollide = false
			elseif child.Name:sub(1, 5) == "Fence" or child.Name:sub(1, 10) == "StepStone_" then
				child:Destroy()   -- Holzzaun und Trittsteine passen nicht zum neuen Boden (Saeulen begrenzen den Plot)
			end
		end
	end

	-- begehbarer Boden in Welt-2-Groesse (unsichtbar) + Rampe zur Brueckenseite
	local plate = Instance.new("Part")
	plate.Name = "Welt2Boden"
	plate.Size = Vector3.new(WALK_SIZE, surface, WALK_SIZE)
	plate.CFrame = plotCFrame * CFrame.new(0, surface * 0.5, 0)
	plate.Transparency = 1
	plate.Anchored = true
	plate.CanCollide = true
	plate.CanTouch = false
	plate.CastShadow = false
	plate.Parent = folder

	local rampLen = math.sqrt((RAMP_TO - RAMP_FROM) ^ 2 + surface ^ 2)
	local rampFrom = plotCFrame * Vector3.new(0, surface, RAMP_FROM)
	local rampTo   = plotCFrame * Vector3.new(0, MapConfig.GRASS_HEIGHT, RAMP_TO)
	local ramp = Instance.new("Part")
	ramp.Name = "Welt2Rampe"
	ramp.Size = Vector3.new(14, 0.4, rampLen)
	ramp.CFrame = CFrame.lookAt((rampFrom + rampTo) * 0.5, rampTo) * CFrame.new(0, -0.2, 0)
	ramp.Transparency = 1
	ramp.Anchored = true
	ramp.CanCollide = true
	ramp.CanTouch = false
	ramp.CastShadow = false
	ramp.Parent = folder

	-- Kristall-Strahlen am Rand + Kernstrahl
	local origin = Welt2Builder.plotOrigin(slot)
	for index, cfg in PLOT_BEAMS do
		beam(folder, "Strahl_Kern" .. index, origin * CFrame.new(cfg.pos), cfg.h, cfg.r)
	end
	for index, p in CRYSTAL_BEAMS do
		beam(folder, "Strahl_Kristall" .. index, origin * CFrame.new(p[1], p[2], p[3]), 22, 0.9)
	end
	folder.Parent = plotModel

	-- Fusionsmaschine (kleiner, plot-lokal weiter vorn)
	local fusionGround = plotCFrame * CFrame.new(FUSION_OFFSET.X, surface, FUSION_OFFSET.Z)
	local fusion = Welt2Builder.clone("Fusion", nil)
	if fusion then
		fusion.Name = Welt2Builder.FUSION_MODEL
		fusion:ScaleTo(FUSION_SCALE)
		fusion:PivotTo(fusionGround)
		fusion.Parent = plotModel
		-- Interaktions-Anker fuer den Client (Prompt "Fusion")
		local core = fusion:FindFirstChild("Fusion_Kern")
		if core and core:IsA("BasePart") then core:SetAttribute("FusionAnchor", true) end
	end
	return true
end

return Welt2Builder
