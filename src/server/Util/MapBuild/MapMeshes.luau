--!strict
-- MapMeshes.luau
-- ServerScriptService/Util/MapBuild/MapMeshes.luau
--
-- Einzige Zustaendigkeit:
--   - Map-Stil V2: Klone der Mesh-Vorlagen (Boden-Kachel, Baum, Busch, Fels, Kristall)
--     passend auf die alten Deko-Positionen setzen.
--
-- Die Vorlagen liegen als MeshParts "Map_*" unter ServerStorage.Assets (bevorzugt) oder
-- ReplicatedStorage.Assets (Studio-Import der FBX aus assets/map/). Fehlt eine Vorlage
-- oder ist der Schalter FeatureFlags.MAP_STYLE_V2 aus, liefert jede Funktion false/nil
-- und der Aufrufer baut das alte Primitiv. Es wird nie etwas veraendert oder geloescht.
--
-- Alles hier ist reine Deko: Anchored, ohne Kollision/Abfrage/Beruehrung, ohne Schatten,
-- Material SmoothPlastic (nur die Kristall-Spitze ist Neon). Die Position der Deko legt
-- weiterhin ScenicBuilder fest (deterministischer Seed); hier kommt nur der Look dazu.
-- Variante/Drehung/Groesse kommen aus einem EIGENEN Zufallsstrom (MapStyleConfig.SEED),
-- damit sich dadurch keine Position verschiebt und jeder Server dieselbe Welt baut.
-- CollisionFidelity ist zur Laufzeit nicht schreibbar: bitte an den Vorlagen auf Box setzen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage     = game:GetService("ServerStorage")

local FeatureFlags   = require(ReplicatedStorage.Config.FeatureFlags)
local MapConfig      = require(ReplicatedStorage.Config.MapConfig)
local MapStyleConfig = require(ReplicatedStorage.Config.MapStyleConfig)
local MapStyleRules  = require(ReplicatedStorage.Modules.MapStyleRules)

local MapMeshes = {}

local templateCache: { [string]: MeshPart } = {}

function MapMeshes.enabled(): boolean
	return FeatureFlags.isOn("MAP_STYLE_V2")
end

local function assetRoots(): { Instance }
	local roots: { Instance } = {}
	for _, service in { ServerStorage, ReplicatedStorage } do
		local assets = service:FindFirstChild("Assets")
		if assets then table.insert(roots, assets) end
	end
	return roots
end

-- Vorlage `name` (MeshPart mit MeshId) oder nil.
function MapMeshes.template(name: string): MeshPart?
	local cached = templateCache[name]
	if cached and cached.Parent then return cached end
	for _, assets in assetRoots() do
		local found = assets:FindFirstChild(name, true)
		if found and found:IsA("MeshPart") and found.MeshId ~= "" then
			templateCache[name] = found
			return found
		end
	end
	return nil
end

-- true, wenn Studio die Vertexfarben nicht uebernimmt: dann Farben aus den alten Configs
-- (Attribut MapFarbenAusConfig = true an einem Assets-Ordner).
function MapMeshes.colorsFromConfig(): boolean
	for _, assets in assetRoots() do
		if assets:GetAttribute("MapFarbenAusConfig") == true then return true end
	end
	return false
end

-- Eigener, deterministischer Zufallsstrom (je Aufgabe ein `salt`).
function MapMeshes.stream(salt: number): Random
	return Random.new(MapStyleConfig.SEED + salt)
end

local function finishPart(part: MeshPart, name: string, size: Vector3, cframe: CFrame, color: Color3)
	part.Name          = name
	part.Size          = size
	part.CFrame        = cframe
	part.Color         = color
	part.Material      = Enum.Material.SmoothPlastic
	part.Anchored      = true
	part.CanCollide    = false
	part.CanQuery      = false
	part.CanTouch      = false
	part.CastShadow    = false
	part.TopSurface    = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part:SetAttribute("MapStyle", 2)
end

-- Farbe: Vertexfarben * leichte Toenung (oder die alte Config-Farbe, s. colorsFromConfig).
local function pickColor(stream: Random, legacy: Color3, foliage: boolean?): Color3
	local tint = MapStyleRules.pick(MapStyleConfig.TINTS, stream:NextNumber())
	if MapMeshes.colorsFromConfig() then return legacy end
	if foliage then
		local f = MapStyleConfig.FOLIAGE_TINT
		return Color3.new(tint.R * f.R, tint.G * f.G, tint.B * f.B)
	end
	return tint
end

-- Mittelpunkt der Vorlage ueber dem Pivot (Boden), im Massstab der MeshPart.
local function centerY(name: string, tpl: MeshPart, size: Vector3): number
	local z = MapStyleConfig.MESH_Z[name]
	if not z then return size.Y * 0.5 end
	return MapStyleRules.centerOffsetY(z[1], z[2], size.Y)
end

-- Allgemeines Setzen: `base` = Punkt am Boden (Pivot), `rotation` = nur Drehung.
local function place(parent: Instance, name: string, tplName: string, base: Vector3, rotation: CFrame, scale: number, color: Color3): MeshPart?
	local tpl = MapMeshes.template(tplName)
	if not tpl then return nil end
	local clone = tpl:Clone()
	local size = tpl.Size * scale
	local center = base + rotation:VectorToWorldSpace(Vector3.new(0, centerY(tplName, tpl, size), 0))
	finishPart(clone, name, size, CFrame.new(center) * rotation, color)
	clone:SetAttribute("MapTemplate", tplName)
	clone.Parent = parent
	return clone
end

local function scaleFromStream(stream: Random): number
	return stream:NextNumber(MapStyleConfig.SCALE_MIN, MapStyleConfig.SCALE_MAX)
end

-- Bodenkachel: ersetzt GrassTile. `cframe` ist der Mittelpunkt des alten Blocks,
-- `index` waehlt die Variante (Raster i/j). true, wenn gebaut.
function MapMeshes.groundTile(parent: Instance, name: string, cframe: CFrame, sizeX: number, sizeZ: number, index: number): boolean
	if not MapMeshes.enabled() then return false end
	local tplName = MapStyleConfig.GROUND_TILES[MapStyleRules.tileVariant(index, index // 3, #MapStyleConfig.GROUND_TILES)]
	local tpl = MapMeshes.template(tplName)
	if not tpl then return false end
	local clone = tpl:Clone()
	local thick = tpl.Size.Y
	-- alter Block: Mitte auf GRASS_HEIGHT/2 ueber der Scheibe; die Kachel steht mit der Unterkante darauf
	local lifted = cframe * CFrame.new(0, (thick - MapConfig.GRASS_HEIGHT) * 0.5 + MapStyleConfig.TILE_LIFT, 0)
	local color = if MapMeshes.colorsFromConfig() then MapConfig.GRASS_LIGHT else MapStyleConfig.TILE_TINT
	finishPart(clone, name, Vector3.new(sizeX, thick, sizeZ), lifted, color)
	clone:SetAttribute("MapTemplate", tplName)
	clone.Parent = parent
	return true
end

-- Baum: ersetzt Stamm + Krone + Spitze (3 Teile) durch EIN MeshPart.
function MapMeshes.tree(parent: Instance, x: number, y: number, z: number, stream: Random, legacyColor: Color3): boolean
	if not MapMeshes.enabled() then return false end
	local tplName = MapStyleRules.pick(MapStyleConfig.TREES, stream:NextNumber())
	local yaw = stream:NextNumber(0, math.pi * 2)
	local scale = scaleFromStream(stream)
	local color = pickColor(stream, legacyColor, true)
	return place(parent, "Tree", tplName, Vector3.new(x, y, z), CFrame.Angles(0, yaw, 0), scale, color) ~= nil
end

-- Busch / Rand-Busch: `width` ist die alte Breite (Studs); `kind` = "bush" | "rimBush".
function MapMeshes.bush(parent: Instance, name: string, kind: string, x: number, y: number, z: number, width: number, yaw: number, stream: Random, legacyColor: Color3): boolean
	if not MapMeshes.enabled() then return false end
	local list = if kind == "rimBush" then MapStyleConfig.RIM_BUSHES else MapStyleConfig.BUSHES
	local tplName = MapStyleRules.pick(list, stream:NextNumber())
	local scale = MapStyleRules.scaleForWidth(width, MapStyleConfig.REF_WIDTH[kind] or 6) * scaleFromStream(stream)
	local color = pickColor(stream, legacyColor, true)
	return place(parent, name, tplName, Vector3.new(x, y, z), CFrame.Angles(0, yaw, 0), scale, color) ~= nil
end

-- Fels: `rotation` = die alte Drehung (leichte Neigung + Yaw), `width` die alte Breite.
-- withCrystal: kleine Kristallgruppe (Neon) obenauf (1 zusaetzliches Teil).
function MapMeshes.rock(parent: Instance, name: string, kind: string, x: number, y: number, z: number, width: number, rotation: CFrame, stream: Random, legacyColor: Color3, withCrystal: boolean): boolean
	if not MapMeshes.enabled() then return false end
	local tplName = MapStyleRules.pick(MapStyleConfig.ROCKS, stream:NextNumber())
	local scale = MapStyleRules.scaleForWidth(width, MapStyleConfig.REF_WIDTH[kind] or 5) * scaleFromStream(stream)
	local color = pickColor(stream, legacyColor)
	local base = Vector3.new(x, y, z)
	local rock = place(parent, name, tplName, base, rotation, scale, color)
	if not rock then return false end
	if withCrystal then
		local crystalName = MapStyleRules.pick(MapStyleConfig.CRYSTALS, stream:NextNumber())
		local crystalColor = MapStyleConfig.CRYSTAL_COLORS[if crystalName == MapStyleConfig.CRYSTALS[1] then 1 else 2]
		local up = rock.Size.Y * 0.8
		local crystal = place(parent, "RockCrystal", crystalName, base + rotation:VectorToWorldSpace(Vector3.new(rock.Size.X * 0.12, up * 0.55, 0)), rotation, scale * 0.45, crystalColor)
		if crystal then crystal.Material = Enum.Material.Neon end
	end
	return true
end

-- Namen aller Deko-Teile dieses Stils bzw. der alten Primitive (fuer Umschalten/Zaehlen).
MapMeshes.VEGETATION_NAMES = {
	TreeTrunk = true, TreeCrown = true, TreeTop = true, Tree = true,
	Bush = true, BushMesh = true, RimBush = true, RimBushMesh = true,
	Rock = true, RockMesh = true, RimRock = true, RimRockMesh = true, RockCrystal = true,
}

-- Old-School-Boden (P1): Raster aus Bloecken mit echten Noppen (TopSurface = Studs).
-- Sie liegen als Ordner "GroundStuds" im Modell `parent`; der Zylinder `top` darunter
-- wird nur eingefaerbt (Alt-Werte als Attribute gemerkt). Gibt die Anzahl Bloecke zurueck.
-- opts (optional, fuer kleine Inseln wie die Raketen-Insel): center, radius, levels, margin, folderName.
function MapMeshes.groundOldschool(parent: Instance, top: BasePart, opts: { center: Vector3?, radius: number?, levels: { number }?, margin: number?, folderName: string?, color: Color3? }?): number
	local cfg = MapStyleConfig.GROUND
	local o = opts or {}
	local center = o.center or MapConfig.CENTER
	local folderName = o.folderName or "GroundStuds"
	local baseColor = o.color or cfg.COLOR
	local old = parent:FindFirstChild(folderName)
	if old then old:Destroy() end
	local cells = MapStyleRules.groundCells(o.radius or MapConfig.PLATFORM_RADIUS, o.levels or cfg.LEVELS, o.margin or cfg.MARGIN)
	if #cells > cfg.MAX_PARTS then
		warn("[MapMeshes] Bodenraster hat", #cells, "Teile (Budget", cfg.MAX_PARTS, ")")
	end
	local folder = Instance.new("Folder")
	folder.Name = folderName
	local y = MapConfig.PLATFORM_TOP_Y + cfg.LIFT - cfg.THICKNESS * 0.5
	for _, c in cells do
		local p = Instance.new("Part")
		p.Name = "GroundStud"
		p.Anchored = true
		p.Size = Vector3.new(c.size, cfg.THICKNESS, c.size)
		p.Position = Vector3.new(center.X + c.x, y, center.Z + c.z)
		p.Material = Enum.Material.Plastic
		-- Schachbrett: jedes zweite Feld (je Kachelgroesse) etwas dunkler (nur Optik)
		local shade = 0
		if cfg.ALT_TON > 0 and (math.floor(c.x / c.size) + math.floor(c.z / c.size)) % 2 ~= 0 then
			shade = -cfg.ALT_TON
		end
		p.Color = Color3.new(
			math.clamp(baseColor.R * (1 + shade), 0, 1),
			math.clamp(baseColor.G * (1 + shade), 0, 1),
			math.clamp(baseColor.B * (1 + shade), 0, 1)
		)
		p.BottomSurface = Enum.SurfaceType.Smooth
		if cfg.TEXTURE ~= "" then
			p.TopSurface = Enum.SurfaceType.Smooth
			local t = Instance.new("Texture")
			t.Name = "BaseplateTexture"
			t.Texture = cfg.TEXTURE
			t.Face = Enum.NormalId.Top
			t.StudsPerTileU = cfg.TILE
			t.StudsPerTileV = cfg.TILE
			t.Parent = p
		else
			p.TopSurface = Enum.SurfaceType.Studs
		end
		p.CastShadow = false
		p.CanTouch = false
		p.CanQuery = false
		p.CanCollide = false -- begehbar bleibt der Zylinder darunter (Bloecke liegen nur 5 cm drueber)
		p.Parent = folder
	end
	folder.Parent = parent
	if top:GetAttribute("AltFarbe") == nil then
		top:SetAttribute("AltFarbe", top.Color)
		top:SetAttribute("AltMaterial", top.Material.Name)
	end
	top.Material = Enum.Material.Plastic
	top.Color = baseColor
	return #cells
end

-- Inselboden: Noppen-Textur (Classic Baseplate) auf der runden Hauptinsel-Scheibe.
-- on=true setzt Farbe/Material/Textur (alte Werte als Attribute gemerkt), on=false stellt zurueck.
-- Mit MAP_GROUND_OLDSCHOOL (und STUD_GROUND.MODERN = false) entsteht stattdessen der Old-School-Boden.
function MapMeshes.studGround(top: Instance?, on: boolean)
	if not top or not top:IsA("BasePart") then return end
	local parent = top.Parent
	local tex = top:FindFirstChild("StudTexture")
	local studs = if parent then parent:FindFirstChild("GroundStuds") else nil
	if on and FeatureFlags.isOn("MAP_GROUND_OLDSCHOOL") and not MapStyleConfig.STUD_GROUND.MODERN and parent then
		if tex then tex:Destroy() end
		MapMeshes.groundOldschool(parent, top :: BasePart)
		return
	end
	if studs then studs:Destroy() end
	if on then
		if top:GetAttribute("AltFarbe") == nil then
			top:SetAttribute("AltFarbe", top.Color)
			top:SetAttribute("AltMaterial", top.Material.Name)
		end
		local cfg = MapStyleConfig.STUD_GROUND
		top.Material = Enum.Material.Plastic
		top.Color = cfg.COLOR
		if not tex then
			local t = Instance.new("Texture")
			t.Name = "StudTexture"
			t.Texture = cfg.TEXTURE
			t.Face = Enum.NormalId.Right -- Zylinder liegt gedreht: Deckflaeche = Right
			t.StudsPerTileU = cfg.TILE
			t.StudsPerTileV = cfg.TILE
			t.Transparency = cfg.TRANSPARENCY
			t.Color3 = cfg.TEXTURE_COLOR
			t.Parent = top
		end
	else
		if tex then tex:Destroy() end
		local c = top:GetAttribute("AltFarbe")
		local m = top:GetAttribute("AltMaterial")
		if typeof(c) == "Color3" then top.Color = c end
		if typeof(m) == "string" then top.Material = (Enum.Material :: any)[m] end
		top:SetAttribute("AltFarbe", nil)
		top:SetAttribute("AltMaterial", nil)
	end
end

return MapMeshes
