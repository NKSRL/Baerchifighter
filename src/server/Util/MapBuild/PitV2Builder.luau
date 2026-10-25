--!strict
-- PitV2Builder.luau
-- ServerScriptService/Util/MapBuild/PitV2Builder.luau
--
-- Einzige Zustaendigkeit:
--   - Das Honig-Kolosseum (Schalter PIT_V2) bauen: Mesh-Vorlagen klonen und
--     einfaerben, unsichtbare Kollision setzen, jeder Turm-Etage ihren Zaun
--     geben und die Kollision der obersten Etage mitfuehren
--
-- Teil von ArenaBuilder: nur ArenaBuilder benutzt dieses Modul. Schalter aus
-- oder Vorlage fehlt = enabled() ist false, dann baut ArenaBuilder das alte Pit.
-- Daten: Config/PitV2Config, Rechnung: Modules/PitV2Rules, Mesh-Geometrie:
-- tools/pit/pit_kolosseum_scene.py (Blender).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")

local MapConfig      = require(ReplicatedStorage.Config.MapConfig)
local AmbienceConfig = require(ReplicatedStorage.Config.AmbienceConfig)
local FeatureFlags   = require(ReplicatedStorage.Config.FeatureFlags)
local PitV2Config    = require(ReplicatedStorage.Config.PitV2Config)
local PitV2Rules     = require(ReplicatedStorage.Modules.PitV2Rules)

local MapParts = require(script.Parent.MapParts)

local PitV2Builder = {}

local function template(name: string): Model?
	local assets = ServerStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild(PitV2Config.TEMPLATE_FOLDER)
	local model = folder and folder:FindFirstChild(name)
	return if model and model:IsA("Model") then model else nil
end

-- Neuer Look nur mit Schalter UND beiden Vorlagen (sonst altes Pit, nie ein Fehler).
function PitV2Builder.enabled(): boolean
	return FeatureFlags.isOn("PIT_V2")
		and template(PitV2Config.ARENA_TEMPLATE) ~= nil
		and template(PitV2Config.STAGE_TEMPLATE) ~= nil
end

-- Arena-Rahmen: Ursprung = Arena-Mitte auf Kampfflaechen-Hoehe, -Z zeigt zum
-- Steg (Richtung Weltmitte). So liegt auch das exportierte Blender-Modell.
local function pitFrame(slot: number): CFrame
	local center = MapParts.pitCenter(slot)
	local outward = MapParts.outwardDirection(slot)
	return CFrame.fromMatrix(
		Vector3.new(center.X, MapConfig.PLATFORM_TOP_Y, center.Z),
		Vector3.yAxis:Cross(outward),
		Vector3.yAxis
	)
end

-- Studio verwirft die FBX-Farben: Farbe und Material nach Teilname. Die Meshes
-- sind reine Optik, Kollision liefern die unsichtbaren Bloecke.
local function style(part: BasePart, slot: number?)
	local look = PitV2Config.PARTS[part.Name]
	if look then
		local lane = if look.lane and slot then AmbienceConfig.LANE_COLORS[slot] else nil
		part.Color      = lane or look.color
		part.Material   = look.material
		part.CastShadow = look.shadow ~= false
	end
	part.Anchored   = true
	part.CanCollide = false
	part.CanQuery   = false
	part.CanTouch   = false
end

local function cloneTemplate(name: string, parent: Instance, at: CFrame, slot: number?): Model?
	local source = template(name)
	if not source then return nil end
	local model = source:Clone()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then style(d, slot) end
	end
	model:PivotTo(at)
	model.Parent = parent
	return model
end

-- Unsichtbare Bloecke aus Arena-Koordinaten (PitV2Rules) in den Rahmen setzen.
local function blocks(parent: Instance, frame: CFrame, name: string, list: { PitV2Rules.Block })
	for _, b in list do
		local part = MapParts.newPart(
			name,
			Vector3.new(b.radial, b.height, b.length),
			frame * CFrame.new(b.x, b.h, -b.y) * CFrame.Angles(0, math.rad(b.angle), 0),
			Color3.new(1, 1, 1),
			Enum.Material.SmoothPlastic
		)
		part.Transparency = 1
		part.CanQuery     = false
		part.CanTouch     = false
		part.CastShadow   = false
		part.Parent       = parent
	end
end

-- Arena-Meshes (Mauer, Tribuenen, Tore, Waben, Honigrinne, Wimpel in der
-- Spurfarbe) und ihre Kollision in den PitPlatform-Container.
function PitV2Builder.decorate(container: Model, slot: number)
	local frame = pitFrame(slot)
	local arena = cloneTemplate(PitV2Config.ARENA_TEMPLATE, container, frame, slot)
	if arena then arena.Name = "PitV2_Arena" end

	local walls = Instance.new("Model")
	walls.Name = "PitV2_Kollision"
	for _, arc in PitV2Config.ARC_COLLIDERS do
		blocks(walls, frame, "Wand", PitV2Rules.arcBlocks(arc, PitV2Config.COLLIDER_OVERLAP))
	end
	local solids: { PitV2Rules.Block } = {}
	for _, box in PitV2Config.BLOCK_COLLIDERS do
		table.insert(solids, PitV2Rules.block(box))
	end
	blocks(walls, frame, "Block", solids)
	walls.Parent = container
end

-- Zaun einer Turm-Etage: Sims und Goldgelaender AUSSEN am Etagen-Ring (innen
-- verdeckte ihn die naechste Etage). Haengt am Ring, damit er mit ihm geht:
-- MapService raeumt im Tower-Ordner nur "Ring_<n>" auf.
function PitV2Builder.addStageFence(ring: BasePart, center: Vector3, topY: number)
	local fence = cloneTemplate(PitV2Config.STAGE_TEMPLATE, ring, CFrame.new(center.X, topY, center.Z), nil)
	if fence then fence.Name = "PitV2_Etagenzaun" end
end

-- Kollision der obersten Etage, nach jedem Etagenwechsel. Ohne Turm wird der
-- Ring abgebaut. Gehaltener Gipfel (`held`): kein Gelaender und keine
-- Kollision, dort fuehrt die Gipfel-Bruecke hinaus und der Gipfel hat ein eigenes.
function PitV2Builder.placeTopFence(container: Instance, slot: number, level: number, held: boolean)
	if not PitV2Builder.enabled() then return end
	local cfg = PitV2Config.TOWER_FENCE
	local old = container:FindFirstChild(cfg.name)
	if level < 1 or held then
		if old then old:Destroy() end
		local tower = if held then container:FindFirstChild("Tower") else nil
		local top = if tower then tower:FindFirstChild("Ring_" .. level) else nil
		local rail = if top then top:FindFirstChild("Pit_Stufe_Gold", true) else nil
		if rail then rail:Destroy() end
		return
	end

	local frame = pitFrame(slot) + Vector3.new(0, level * MapConfig.PIT_TOWER_STEP_HEIGHT, 0)
	if old and old:IsA("Model") then
		old:PivotTo(frame)
		return
	end
	local fence = Instance.new("Model")
	fence.Name = cfg.name
	blocks(fence, frame, "Zaun", PitV2Rules.arcBlocks({
		inner = cfg.inner, outer = cfg.outer, bottom = 0, top = cfg.height,
		from = 0, to = 360, segments = cfg.segments,
	}, PitV2Config.COLLIDER_OVERLAP))
	fence.WorldPivot = frame
	fence.Parent = container
end

return PitV2Builder
