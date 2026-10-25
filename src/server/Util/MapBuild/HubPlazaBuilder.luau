--!strict
-- HubPlazaBuilder.luau
-- ServerScriptService/Util/MapBuild/HubPlazaBuilder.luau
--
-- Einzige Zustaendigkeit:
--   - Baut das neue Zentrum der Hauptinsel (Welt 1 Hub, Blender-Entwurf v3):
--     1. Koenigliches Honig-Heiligtum & Brunnen ("Honigmast")
--     2. Gestufte Tempel-Plaza mit geschlossener Sanktuarium-Zaun-Einfriedung ("EventPit")
--     3. Eingefasste Pracht-Alleen mit Waben-Medaillons & Imker-Galgenlaternen
--     4. Geschwungene Stein- & Holz-Bogenbruecken mit Goldleisten & Wasserpfeilern
--     5. Ueberdachte Pavillon-Rahmen fuer die Bestenlisten- und Live-Tafeln
--
-- Alle Spiel-Anker (EventFloor, EventRing, EventBannerAnchor, EventFence_*,
-- EventCompassRay_*, Honigmast.Tropfen, BridgeInner_*, Bridge) behalten ihre
-- exakten Namen und Funktionen fuer EventService, CombService, DebugBridge
-- und alle Client-Controller.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AmbienceConfig = require(ReplicatedStorage.Config.AmbienceConfig)
local MapConfig      = require(ReplicatedStorage.Config.MapConfig)
local MapParts       = require(ServerScriptService.Util.MapBuild.MapParts)

local HubPlazaBuilder = {}

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

-- Farbpalette (abgestimmt auf Welt 2 & Epilog-Insel)
local COL_CREAM_STONE  = Color3.fromRGB(238, 223, 192)
local COL_CREAM_LIGHT  = Color3.fromRGB(247, 236, 212)
local COL_DARK_SLATE   = Color3.fromRGB(48, 43, 64)
local COL_MID_SLATE    = Color3.fromRGB(76, 70, 96)
local COL_GOLD         = Color3.fromRGB(242, 188, 64)
local COL_GOLD_DARK    = Color3.fromRGB(196, 142, 42)
local COL_HONEY_GLOW   = Color3.fromRGB(255, 196, 56)
local COL_HONEY_BRIGHT = Color3.fromRGB(255, 224, 115)
local COL_WOOD_WARM    = Color3.fromRGB(162, 108, 64)
local COL_WOOD_DARK    = Color3.fromRGB(104, 68, 42)
local COL_FOAM         = Color3.fromRGB(248, 250, 255)

HubPlazaBuilder.DEFAULT_FLOOR_COLOR = COL_CREAM_STONE
HubPlazaBuilder.DEFAULT_RING_COLOR  = COL_GOLD
HubPlazaBuilder.DEFAULT_FENCE_COLOR = COL_HONEY_GLOW

-- Hoehe des Brueckenbogens (Studs). Sanft genug zum darueberlaufen ohne Springen,
-- synchron mit PlotRoutes.luau fuer DebugBridge.
HubPlazaBuilder.BRIDGE_ARCH_HEIGHT = 1.35

--------------------------------------------------------------------------------
-- FBX-MESH-VORLAGEN (assets/map/Hub_*.fbx -> ReplicatedStorage.Assets)
--------------------------------------------------------------------------------
-- Sobald die 4 FBX-Dateien aus assets/map/ in ReplicatedStorage.Assets importiert
-- sind (als Model oder Ordner oder direkt die MeshParts), klont HubPlazaBuilder
-- automatisch die vereinigten MeshParts je Materialgruppe und erzeugt nur noch
-- schlanke, unsichtbare Box-/Zylinder-Collider fuer die Spielphysik.
-- Solange eine Vorlage noch nicht in Studio importiert wurde, greift nahtlos
-- der prozedurale Part-Fallback.

local function findAssetMeshPart(partName: string): MeshPart?
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end
	for _, d in assets:GetDescendants() do
		if d.Name == partName and d:IsA("MeshPart") and d.MeshId ~= "" then
			return d
		end
	end
	return nil
end

type MeshSpec = {
	name: string,
	color: Color3,
	material: Enum.Material,
	transparency: number?,
	targetName: string?,
}

local function spawnMeshGroup(
	parent: Instance,
	refName: string,
	refWidth: number,
	refLocalOriginOffset: Vector3,
	targetCF: CFrame,
	specs: { MeshSpec }
): { [string]: MeshPart }?
	local refTemplate = findAssetMeshPart(refName)
	if not refTemplate then
		return nil
	end
	local clones: { [string]: MeshPart } = {}
	for _, spec in specs do
		local tmpl = findAssetMeshPart(spec.name)
		if not tmpl then
			for _, c in clones do
				c:Destroy()
			end
			return nil
		end
		clones[spec.name] = tmpl:Clone()
	end

	local refClone = clones[refName]
	local rawSpan = math.max(refClone.Size.X, refClone.Size.Z)
	local importScale = if rawSpan > 1e-3 then (rawSpan / refWidth) else 1
	local f = 1 / importScale
	local originCF = CFrame.new(refClone.CFrame:PointToWorldSpace(refLocalOriginOffset * importScale))
		* refClone.CFrame.Rotation

	for _, spec in specs do
		local part = clones[spec.name]
		local rel = originCF:ToObjectSpace(part.CFrame)
		part.Name          = spec.targetName or spec.name
		part.Size          = part.Size * f
		part.CFrame        = targetCF * CFrame.new(rel.Position * f) * rel.Rotation
		part.Color         = spec.color
		part.Material      = spec.material
		part.Transparency  = spec.transparency or 0
		part.Anchored      = true
		part.CanCollide    = false
		part.CanQuery      = false
		part.CanTouch      = false
		part.CastShadow    = false
		part.TopSurface    = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Parent        = parent
	end
	return clones
end

local function makePart(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?,
	collide: boolean?,
	query: boolean?
): Part
	local part = MapParts.newPart(name, size, cframe, color, material)
	part.Shape      = shape or Enum.PartType.Block
	part.CanCollide = collide == true
	part.CanQuery   = query == true
	part.CanTouch   = false
	part.CastShadow = false
	part.Parent     = parent
	return part
end

local function makeCylinder(
	parent: Instance,
	name: string,
	centerPos: Vector3,
	radius: number,
	height: number,
	color: Color3,
	material: Enum.Material,
	collide: boolean?,
	query: boolean?
): Part
	return makePart(
		parent,
		name,
		Vector3.new(height, radius * 2, radius * 2),
		CFrame.new(centerPos) * UPRIGHT,
		color,
		material,
		Enum.PartType.Cylinder,
		collide,
		query
	)
end

-- Baut einen 6-eckigen Ring aus 6 Kanten-Balken (in der XZ-Ebene oder vertikal).
local function buildHexRingFlat(
	parent: Instance,
	namePrefix: string,
	centerPos: Vector3,
	radius: number,
	barThick: number,
	barHeight: number,
	color: Color3,
	material: Enum.Material,
	yawOffset: number?
)
	local baseYaw = yawOffset or 0
	local sideLen = radius * 1.04
	local apothem = radius * math.cos(math.pi / 6)
	for i = 0, 5 do
		local a = baseYaw + i * (math.pi / 3)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local p = centerPos + dir * apothem
		makePart(
			parent,
			namePrefix,
			Vector3.new(sideLen, barHeight, barThick),
			CFrame.lookAt(p, p + dir),
			color,
			material
		)
	end
end

-- Baut einen aufrechten 6-eckigen Ring (z.B. im Zaunfeld oder als schwebende Krone).
local function buildHexRingVertical(
	parent: Instance,
	namePrefix: string,
	originCF: CFrame,
	radius: number,
	barThick: number,
	barDepth: number,
	color: Color3,
	material: Enum.Material
)
	local sideLen = radius * 1.05
	local apothem = radius * math.cos(math.pi / 6)
	for i = 0, 5 do
		local a = i * (math.pi / 3)
		local localPos = Vector3.new(math.cos(a) * apothem, math.sin(a) * apothem, 0)
		local cf = originCF * CFrame.new(localPos) * CFrame.Angles(0, 0, a + math.pi * 0.5)
		makePart(
			parent,
			namePrefix,
			Vector3.new(sideLen, barThick, barDepth),
			cf,
			color,
			material
		)
	end
end

--------------------------------------------------------------------------------
-- 1. KOENIGLICHES HONIG-HEILIGTUM ("Honigmast")
--------------------------------------------------------------------------------

function HubPlazaBuilder.buildSanctuaryFountain(mastModel: Model, floorOrigin: Vector3)
	local cx, fy, cz = floorOrigin.X, floorOrigin.Y, floorOrigin.Z

	-- Kompatibilitaets-Teile fuer MapLayout/Tests (unsichtbar im Inneren der Saeule)
	for _, piece in MapConfig.CENTER_DECOR do
		local cframe = CFrame.new(floorOrigin) * CFrame.new(piece.offset)
		if piece.rotation then
			cframe = cframe * CFrame.Angles(
				math.rad(piece.rotation.X),
				math.rad(piece.rotation.Y),
				math.rad(piece.rotation.Z)
			)
		end
		local compat = MapParts.newPart(
			piece.name,
			piece.size,
			cframe,
			piece.color,
			piece.material or Enum.Material.SmoothPlastic
		)
		compat.Shape = piece.shape
		compat.Transparency = if piece.name == "Tropfen" then 0 else 1
		compat.CanCollide = false
		compat.CanQuery = false
		compat.CanTouch = false
		compat.CastShadow = false
		compat.Parent = mastModel
	end

	-- FBX-Mesh-Pfad (Hub_Brunnen.fbx -> 6 vereinigte MeshParts + 1 unsichtbarer Zylinder-Collider)
	local brunnenMeshes = spawnMeshGroup(
		mastModel,
		"Hub_Brunnen_Sandstein",
		15.20,
		Vector3.new(0, -0.234, 0),
		CFrame.new(cx, fy, cz),
		{
			{ name = "Hub_Brunnen_Sandstein", color = COL_CREAM_STONE,  material = Enum.Material.Sandstone },
			{ name = "Hub_Brunnen_Schiefer",  color = COL_DARK_SLATE,   material = Enum.Material.Slate },
			{ name = "Hub_Brunnen_Gold",      color = COL_GOLD,         material = Enum.Material.Metal },
			{ name = "Hub_Brunnen_GoldNeon",  color = COL_GOLD,         material = Enum.Material.Neon },
			{ name = "Hub_Brunnen_HonigNeon", color = COL_HONEY_GLOW,   material = Enum.Material.Neon },
			{ name = "Hub_Brunnen_Tropfen",   color = COL_HONEY_BRIGHT, material = Enum.Material.Neon },
		}
	)
	if brunnenMeshes then
		local col = makeCylinder(mastModel, "Sanctuary_Collider", Vector3.new(cx, fy + 4.5, cz), 7.4, 9.0, COL_DARK_SLATE, Enum.Material.SmoothPlastic, true, false)
		col.Transparency = 1
		local drop = mastModel:FindFirstChild("Tropfen")
		local meshDrop = brunnenMeshes["Hub_Brunnen_Tropfen"]
		if drop and drop:IsA("BasePart") and meshDrop then
			drop.CFrame = meshDrop.CFrame
			drop.Transparency = 1
		end
		local beam = makeCylinder(mastModel, "Sanctuary_LightBeam", Vector3.new(cx, fy + 38, cz), 3.1, 52, COL_HONEY_GLOW, Enum.Material.Neon, false, false)
		beam.Transparency = 0.89
		return
	end

	-- 1a. Unteres Brunnenbecken (R <= 7.6, damit CombConfig.SPAWN_RADIUS_MIN = 8 frei bleibt)
	makeCylinder(mastModel, "Sanctuary_BasePlinth", Vector3.new(cx, fy + 0.42, cz), 7.5, 0.84, COL_DARK_SLATE, Enum.Material.Slate, true, false)
	makeCylinder(mastModel, "Sanctuary_BaseGold", Vector3.new(cx, fy + 0.22, cz), 7.75, 0.44, COL_GOLD, Enum.Material.Metal, false, false)
	makeCylinder(mastModel, "Sanctuary_BasinWall", Vector3.new(cx, fy + 1.35, cz), 6.8, 1.5, COL_DARK_SLATE, Enum.Material.Slate, true, false)
	makeCylinder(mastModel, "Sanctuary_BasinRim", Vector3.new(cx, fy + 2.15, cz), 7.1, 0.36, COL_GOLD, Enum.Material.Metal, false, false)
	makeCylinder(mastModel, "Sanctuary_HoneyPool", Vector3.new(cx, fy + 1.95, cz), 6.35, 0.24, COL_HONEY_GLOW, Enum.Material.Neon, false, false)

	-- 8 geneigte Schiefer- & Gold-Dornen am Beckenrand
	for k = 0, 7 do
		local a = (k + 0.5) * (math.pi / 4)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local p = Vector3.new(cx, fy + 1.45, cz) + dir * 7.15
		local cf = CFrame.lookAt(p, p + dir) * CFrame.Angles(math.rad(-22), 0, 0)
		makePart(mastModel, "Sanctuary_Spike", Vector3.new(0.85, 2.5, 0.85), cf, COL_DARK_SLATE, Enum.Material.Slate)
		makePart(mastModel, "Sanctuary_SpikeGold", Vector3.new(0.95, 0.45, 0.95), cf * CFrame.new(0, 0.85, 0), COL_GOLD, Enum.Material.Metal)
	end

	-- 1b. Zentrale Heiligtums-Saeule mit 6 goldenen Rippen
	makeCylinder(mastModel, "Sanctuary_Pillar", Vector3.new(cx, fy + 5.4, cz), 2.7, 7.2, COL_DARK_SLATE, Enum.Material.Slate, true, false)
	makeCylinder(mastModel, "Sanctuary_PillarFootGold", Vector3.new(cx, fy + 2.35, cz), 3.15, 0.5, COL_GOLD, Enum.Material.Metal, false, false)
	makeCylinder(mastModel, "Sanctuary_PillarMidGold", Vector3.new(cx, fy + 5.6, cz), 2.95, 0.42, COL_GOLD, Enum.Material.Metal, false, false)

	for i = 0, 5 do
		local a = i * (math.pi / 3)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local p = Vector3.new(cx, fy + 5.5, cz) + dir * 2.65
		makePart(mastModel, "Sanctuary_Rib", Vector3.new(0.45, 6.8, 0.55), CFrame.lookAt(p, p + dir), COL_GOLD, Enum.Material.Metal)
	end

	-- 1c. Oberes Wabenbecken & 6 fliessende Honig-Kaskaden
	makeCylinder(mastModel, "Sanctuary_UpperBasin", Vector3.new(cx, fy + 9.2, cz), 4.4, 1.3, COL_DARK_SLATE, Enum.Material.Slate, false, false)
	makeCylinder(mastModel, "Sanctuary_UpperRim", Vector3.new(cx, fy + 9.9, cz), 4.68, 0.34, COL_GOLD, Enum.Material.Metal, false, false)
	makeCylinder(mastModel, "Sanctuary_UpperHoney", Vector3.new(cx, fy + 9.75, cz), 4.1, 0.22, COL_HONEY_GLOW, Enum.Material.Neon, false, false)

	for i = 0, 5 do
		local a = (i + 0.5) * (math.pi / 3)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local spoutPos = Vector3.new(cx, fy + 9.45, cz) + dir * 4.45
		makePart(mastModel, "Sanctuary_Spout", Vector3.new(0.75, 0.45, 1.1), CFrame.lookAt(spoutPos, spoutPos + dir), COL_GOLD, Enum.Material.Metal)

		local streamPos = Vector3.new(cx, fy + 5.75, cz) + dir * 4.85
		local stream = makeCylinder(mastModel, "Sanctuary_Stream", streamPos, 0.34, 7.3, COL_HONEY_GLOW, Enum.Material.Neon, false, false)
		stream.Transparency = 0.12

		local splashPos = Vector3.new(cx, fy + 2.12, cz) + dir * 4.85
		local splash = makeCylinder(mastModel, "Sanctuary_Splash", splashPos, 0.9, 0.12, COL_HONEY_BRIGHT, Enum.Material.Neon, false, false)
		splash.Transparency = 0.25
	end

	-- 1d. 4 Klauen-Streben um das Kristall-Herz
	makeCylinder(mastModel, "Sanctuary_UpperPedestal", Vector3.new(cx, fy + 10.9, cz), 1.95, 2.1, COL_DARK_SLATE, Enum.Material.Slate, false, false)
	makeCylinder(mastModel, "Sanctuary_UpperPedestalGold", Vector3.new(cx, fy + 11.95, cz), 2.15, 0.35, COL_GOLD, Enum.Material.Metal, false, false)

	for i = 0, 3 do
		local a = i * (math.pi * 0.5) + math.pi * 0.25
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local pLow = Vector3.new(cx, fy + 12.2, cz) + dir * 2.55
		local cfLow = CFrame.lookAt(pLow, pLow + dir) * CFrame.Angles(math.rad(-18), 0, 0)
		makePart(mastModel, "Sanctuary_ClawLower", Vector3.new(0.65, 4.2, 0.8), cfLow, COL_DARK_SLATE, Enum.Material.Slate)

		local pHigh = Vector3.new(cx, fy + 15.8, cz) + dir * 2.85
		local cfHigh = CFrame.lookAt(pHigh, pHigh + dir) * CFrame.Angles(math.rad(22), 0, 0)
		makePart(mastModel, "Sanctuary_ClawUpper", Vector3.new(0.55, 3.8, 0.65), cfHigh, COL_GOLD, Enum.Material.Metal)
	end

	-- 1e. Schwebender Honig-Kristall + 2 Gyro-Ringe + Doppel-Hexagon-Krone
	local crystalCenter = Vector3.new(cx, fy + 15.2, cz)
	makePart(
		mastModel,
		"Sanctuary_CrystalCore",
		Vector3.new(2.8, 2.8, 2.8),
		CFrame.new(crystalCenter) * CFrame.Angles(math.rad(45), math.rad(45), 0),
		COL_HONEY_BRIGHT,
		Enum.Material.Neon
	)
	-- Tropfen aus CENTER_DECOR an die neue Kristallposition schieben (fuer DayCycleController)
	local drop = mastModel:FindFirstChild("Tropfen")
	if drop and drop:IsA("BasePart") then
		drop.Size = Vector3.new(3.2, 4.6, 3.2)
		drop.CFrame = CFrame.new(crystalCenter)
		drop.Transparency = 0.15
	end

	-- 2 geneigte Gyro-Ringe (als 8-eckige Goldringe)
	for gIdx, tilt in { CFrame.Angles(math.rad(28), math.rad(15), 0), CFrame.Angles(math.rad(-32), math.rad(75), 0) } do
		local ringR = 4.1 + (gIdx - 1) * 0.45
		local ringCF = CFrame.new(crystalCenter) * tilt
		local segs = 8
		local segLen = 2 * ringR * math.sin(math.pi / segs) + 0.25
		local apothem = ringR * math.cos(math.pi / segs)
		for s = 0, segs - 1 do
			local a = s * (2 * math.pi / segs)
			local posL = Vector3.new(math.cos(a) * apothem, math.sin(a) * apothem, 0)
			makePart(
				mastModel,
				"Sanctuary_Gyro_" .. gIdx,
				Vector3.new(segLen, 0.28, 0.28),
				ringCF * CFrame.new(posL) * CFrame.Angles(0, 0, a + math.pi * 0.5),
				COL_GOLD,
				Enum.Material.Metal
			)
		end
	end

	-- Schwebende Doppel-Hexagon-Krone darueber
	local crownCenter = CFrame.new(cx, fy + 22.8, cz)
	buildHexRingVertical(mastModel, "Sanctuary_CrownOuter", crownCenter, 3.5, 0.45, 0.55, COL_GOLD, Enum.Material.Metal)
	buildHexRingVertical(mastModel, "Sanctuary_CrownInner", crownCenter, 2.25, 0.35, 0.65, COL_HONEY_BRIGHT, Enum.Material.Neon)
	makePart(
		mastModel,
		"Sanctuary_CrownGem",
		Vector3.new(1.5, 1.5, 1.5),
		crownCenter * CFrame.Angles(math.rad(45), math.rad(45), 0),
		COL_HONEY_GLOW,
		Enum.Material.Neon
	)

	-- Sanfter vertikaler Lichtstrahl (wie Welt 2)
	local beam = makeCylinder(mastModel, "Sanctuary_LightBeam", Vector3.new(cx, fy + 38, cz), 3.1, 52, COL_HONEY_GLOW, Enum.Material.Neon, false, false)
	beam.Transparency = 0.89
end

--------------------------------------------------------------------------------
-- 2. EVENT-PIT PLAZA & GESCHLOSSENER SANKTUARIUM-ZAUNRING ("EventPit")
--------------------------------------------------------------------------------

function HubPlazaBuilder.buildEventPitPlaza(container: Model)
	local center       = MapConfig.CENTER
	local groundY      = MapConfig.PLATFORM_TOP_Y
	local floorBottomY = groundY + MapConfig.EVENT_PIT_GROUND_CLEARANCE
	local floorY       = floorBottomY + MapConfig.EVENT_PIT_FLOOR_HEIGHT
	local radius       = MapConfig.EVENT_PIT_RADIUS

	-- EventRing: wird von MapService.setEventPitTheme bei einem Event auf Neon geschaltet
	-- und von HubEventController beobachtet.
	local step1H = (floorY - groundY) * 0.52
	local ringRadius = radius + MapConfig.EVENT_PIT_RING_OVERHANG
	makeCylinder(
		container,
		"EventRing",
		Vector3.new(center.X, groundY + step1H - 0.14, center.Z),
		ringRadius,
		0.32,
		COL_GOLD,
		Enum.Material.Metal,
		false,
		false
	)

	-- EventFloor: Haupt-Podestscheibe (Oberkante exakt floorY = 1.28)
	local floor = makeCylinder(
		container,
		"EventFloor",
		Vector3.new(center.X, floorY - MapConfig.EVENT_PIT_FLOOR_HEIGHT * 0.5, center.Z),
		radius,
		MapConfig.EVENT_PIT_FLOOR_HEIGHT,
		COL_CREAM_STONE,
		Enum.Material.Sandstone,
		true,
		true
	)
	floor.CanQuery = true

	-- FBX-Mesh-Pfad (Hub_PlazaUndZaun.fbx -> 8 vereinigte MeshParts + schlanke Physik-Collider)
	local plazaMeshes = spawnMeshGroup(
		container,
		"Hub_Plaza_Sandstein",
		106.10,
		Vector3.new(0, -0.761, 0),
		CFrame.new(center.X, groundY, center.Z),
		{
			{ name = "Hub_Plaza_Sandstein", color = COL_CREAM_STONE, material = Enum.Material.Sandstone },
			{ name = "Hub_Plaza_Randstein", color = COL_CREAM_LIGHT, material = Enum.Material.Sandstone },
			{ name = "Hub_Plaza_Schiefer",  color = COL_DARK_SLATE,  material = Enum.Material.Slate },
			{ name = "Hub_Plaza_Gold",      color = COL_GOLD,        material = Enum.Material.Metal },
			{ name = "Hub_Plaza_HonigNeon", color = COL_HONEY_GLOW,  material = Enum.Material.Neon, targetName = "EventFence_PlazaHoneyNeon" },
			{ name = "Hub_Zaun_Schiefer",   color = COL_DARK_SLATE,  material = Enum.Material.Slate },
			{ name = "Hub_Zaun_Gold",       color = COL_GOLD,        material = Enum.Material.Metal },
			{ name = "Hub_Zaun_HonigNeon",  color = COL_HONEY_GLOW,  material = Enum.Material.Neon, targetName = "EventFence_ZaunHoneyNeon" },
		}
	)
	if plazaMeshes then
		floor.Transparency = 1
		local fenceR = 46.0
		local gateHalfAngle = 0.124
		for slot = 1, MapConfig.PLOT_COUNT do
			local outward = MapParts.outwardDirection(slot)
			local side    = Vector3.new(-outward.Z, 0, outward.X)
			-- 3 begehbare Treppenstufen-Collider
			local stairSteps = 3
			for st = 1, stairSteps do
				local t = (st - 0.5) / stairSteps
				local rStep = 46.4 + t * 5.2
				local hStep = floorY * (1 - (st - 1) / stairSteps)
				local stepPos = Vector3.new(center.X, groundY + hStep * 0.5, center.Z) + outward * rStep
				local stPart = makePart(container, "Plaza_Stair_" .. slot, Vector3.new(10.6, hStep, 2.0), CFrame.lookAt(stepPos, stepPos + outward), COL_CREAM_STONE, Enum.Material.Sandstone, nil, true, true)
				stPart.Transparency = 1
			end
			-- Unsichtbare Treppenwangen-Collider
			for _, s in { -1, 1 } do
				local cheekPos = Vector3.new(center.X, floorY + 6.0, center.Z) + outward * 49.0 + side * (s * 5.65)
				local cw = makePart(container, "PlazaFence_StairBarrier", Vector3.new(0.9, 13.0, 6.6), CFrame.lookAt(cheekPos, cheekPos + outward), COL_DARK_SLATE, Enum.Material.SmoothPlastic, nil, true, false)
				cw.Transparency = 1
			end
			-- Unsichtbare Zaun-Collider je Sektor (3 Segmente)
			local baseAngle = math.rad((slot - 1) * 45)
			local aStart    = baseAngle + gateHalfAngle
			local aEnd      = baseAngle + math.pi * 0.25 - gateHalfAngle
			for b = 1, 3 do
				local ba0 = aStart + (b - 1) * (aEnd - aStart) / 3
				local ba1 = aStart + b * (aEnd - aStart) / 3
				local bMid = (ba0 + ba1) * 0.5
				local dir  = Vector3.new(math.cos(bMid), 0, math.sin(bMid))
				local chord = 2 * fenceR * math.sin((ba1 - ba0) * 0.5)
				local bayPos = Vector3.new(center.X, floorY + 6.75, center.Z) + dir * (fenceR * math.cos((ba1 - ba0) * 0.5))
				local wall = makePart(container, "PlazaFence_Barrier", Vector3.new(chord + 0.6, 13.5, 1.4), CFrame.lookAt(bayPos, bayPos + dir), COL_DARK_SLATE, Enum.Material.SmoothPlastic, nil, true, false)
				wall.Transparency = 1
			end
		end
		return
	end

	-- 2a. Zweistufiges Creme-Sandstein- & Gold-Fundament (Oberkante exakt auf floorY)
	makeCylinder(
		container,
		"Plaza_Step1",
		Vector3.new(center.X, groundY + step1H * 0.5, center.Z),
		radius + 1.2,
		step1H,
		COL_CREAM_STONE,
		Enum.Material.Sandstone,
		true,
		false
	)

	makeCylinder(
		container,
		"Plaza_UpperGoldRim",
		Vector3.new(center.X, floorY - 0.14, center.Z),
		radius + 0.25,
		0.24,
		COL_GOLD,
		Enum.Material.Metal,
		false,
		false
	)

	-- 2b. Konzentrische Boden-Intarsien buendig auf floorY
	makeCylinder(container, "Plaza_OuterSlateRing", Vector3.new(center.X, floorY + 0.01, center.Z), 45.2, 0.02, COL_DARK_SLATE, Enum.Material.Slate, false, false)
	makeCylinder(container, "Plaza_InnerCreamDisc", Vector3.new(center.X, floorY + 0.02, center.Z), 42.4, 0.04, COL_CREAM_LIGHT, Enum.Material.Sandstone, false, false)
	makeCylinder(container, "EventCompassRing", Vector3.new(center.X, floorY + 0.03, center.Z), 29.5, 0.06, COL_GOLD, Enum.Material.Metal, false, false)
	makeCylinder(container, "EventCompassInner", Vector3.new(center.X, floorY + 0.04, center.Z), 27.8, 0.08, COL_DARK_SLATE, Enum.Material.Slate, false, false)
	makeCylinder(container, "Plaza_MidCreamDisc", Vector3.new(center.X, floorY + 0.05, center.Z), 19.5, 0.10, COL_CREAM_STONE, Enum.Material.Sandstone, false, false)
	makeCylinder(container, "Plaza_CenterGoldRing", Vector3.new(center.X, floorY + 0.06, center.Z), 13.8, 0.12, COL_GOLD, Enum.Material.Metal, false, false)
	makeCylinder(container, "Plaza_CenterSlateDisc", Vector3.new(center.X, floorY + 0.07, center.Z), 12.8, 0.14, COL_DARK_SLATE, Enum.Material.Slate, false, false)

	-- 2c. 8 leuchtende Honig-Rinnen entlang der 8 Allee-Achsen + 8 Waben-Medaillons in den Zwischensektoren
	for slot = 1, MapConfig.PLOT_COUNT do
		local outward = MapParts.outwardDirection(slot)
		local side    = Vector3.new(-outward.Z, 0, outward.X)
		local rayMid  = center + outward * 27.2
		local rayPos  = Vector3.new(rayMid.X, floorY + 0.08, rayMid.Z)
		local rayCF   = CFrame.lookAt(rayPos, rayPos + outward)

		local ray = makePart(
			container,
			"EventCompassRay_" .. slot,
			Vector3.new(2.1, 0.06, 36.5),
			rayCF,
			COL_HONEY_GLOW,
			Enum.Material.Neon
		)
		ray.Transparency = 0.15

		for _, s in { -1, 1 } do
			makePart(
				container,
				"Plaza_RayBorder",
				Vector3.new(0.55, 0.08, 36.5),
				rayCF * CFrame.new(s * 1.35, 0, 0),
				COL_CREAM_LIGHT,
				Enum.Material.Sandstone
			)
		end

		-- Sechseckiges Waben-Medaillon in der Mitte jedes Zwischensektors (22.5 + (slot-1)*45 Grad)
		local secAngle = math.rad((slot - 1) * 45 + 22.5)
		local secDir   = Vector3.new(math.cos(secAngle), 0, math.sin(secAngle))
		local medPos   = Vector3.new(center.X, floorY + 0.09, center.Z) + secDir * 35.0
		buildHexRingFlat(container, "Plaza_SectorHexRing", medPos, 3.6, 0.55, 0.08, COL_GOLD, Enum.Material.Metal, secAngle)
		makeCylinder(container, "EventFence_SectorHexCore_" .. slot, medPos + Vector3.new(0, 0.01, 0), 2.3, 0.08, COL_HONEY_GLOW, Enum.Material.Neon, false, false)

		-- 2d. 8 Freitreppen an den Allee-Zugaengen (R = 46.2 .. 51.8)
		local stairSteps = 3
		for st = 1, stairSteps do
			local t = (st - 0.5) / stairSteps
			local rStep = 46.4 + t * 5.2
			local hStep = floorY * (1 - (st - 1) / stairSteps)
			local stepPos = Vector3.new(center.X, groundY + hStep * 0.5, center.Z) + outward * rStep
			local stepCF = CFrame.lookAt(stepPos, stepPos + outward)
			makePart(container, "Plaza_Stair_" .. slot, Vector3.new(10.6, hStep, 2.0), stepCF, COL_CREAM_STONE, Enum.Material.Sandstone, nil, true, true)
			makePart(container, "Plaza_StairGold_" .. slot, Vector3.new(10.65, 0.16, 0.28), stepCF * CFrame.new(0, hStep * 0.5 - 0.06, -0.9), COL_GOLD, Enum.Material.Metal)
		end

		-- 2e. Treppenwangen, schraege goldene Handlaeufe & aeussere Treppenpfosten (schliessen an Allee-Randsteine an)
		for _, s in { -1, 1 } do
			local cheekPos = Vector3.new(center.X, groundY + floorY * 0.5 + 0.35, center.Z) + outward * 49.0 + side * (s * 5.65)
			local cheekCF  = CFrame.lookAt(cheekPos, cheekPos + outward)
			makePart(container, "PlazaFence_StairCheek", Vector3.new(0.85, floorY + 0.7, 6.2), cheekCF, COL_DARK_SLATE, Enum.Material.Slate, nil, true, false)
			makePart(container, "PlazaFence_StairCheekCap", Vector3.new(1.0, 0.24, 6.4), cheekCF * CFrame.new(0, (floorY + 0.7) * 0.5 + 0.1, 0), COL_GOLD, Enum.Material.Metal)

			-- Schraeger Handlauf vom Tor-Obelisken (R=46.0) zum Treppenpfosten (R=52.2)
			local railTopPos = Vector3.new(center.X, floorY + 2.8, center.Z) + outward * 49.1 + side * (s * 5.65)
			local railCF = CFrame.lookAt(railTopPos, railTopPos + outward) * CFrame.Angles(math.rad(-14), 0, 0)
			makePart(container, "PlazaFence_StairRail", Vector3.new(0.45, 0.35, 6.5), railCF, COL_GOLD, Enum.Material.Metal)
			makePart(container, "PlazaFence_StairSubRail", Vector3.new(0.32, 0.24, 6.5), railCF * CFrame.new(0, -0.85, 0), COL_DARK_SLATE, Enum.Material.Slate)

			-- Aeusserer Treppenpfosten am Allee-Beginn (R = 52.2)
			local postPos = Vector3.new(center.X, groundY + 1.85, center.Z) + outward * 52.2 + side * (s * 5.65)
			local postCF  = CFrame.lookAt(postPos, postPos + outward)
			makePart(container, "PlazaFence_StairPost", Vector3.new(1.35, 3.7, 1.35), postCF, COL_DARK_SLATE, Enum.Material.Slate, nil, true, false)
			makePart(container, "PlazaFence_StairPostCap", Vector3.new(1.6, 0.35, 1.6), postCF * CFrame.new(0, 1.95, 0), COL_GOLD, Enum.Material.Metal)
			makePart(
				container,
				"EventFence_StairGem_" .. slot .. "_" .. (if s < 0 then "L" else "R"),
				Vector3.new(0.85, 0.85, 0.85),
				postCF * CFrame.new(0, 2.65, 0) * CFrame.Angles(math.rad(45), math.rad(45), 0),
				COL_HONEY_GLOW,
				Enum.Material.Neon
			)

			-- Unsichtbare Kollisionswand auf der Treppenwange (damit man nicht seitlich abkuerzen kann)
			local cheekWall = makePart(
				container,
				"PlazaFence_StairBarrier",
				Vector3.new(0.9, 13.0, 6.6),
				CFrame.lookAt(Vector3.new(cheekPos.X, floorY + 6.0, cheekPos.Z), Vector3.new(cheekPos.X, floorY + 6.0, cheekPos.Z) + outward),
				COL_DARK_SLATE,
				Enum.Material.SmoothPlastic,
				nil,
				true,
				false
			)
			cheekWall.Transparency = 1
		end
	end

	-- 2f. 16 Tor-Obelisken & geschlossener 3-feldriger Sanktuarium-Zaunring (R = 46.0)
	local fenceR = 46.0
	local gateHalfAngle = 0.124 -- entspricht +-5.7 Studs bei R = 46.0 (exakte Treppenbreite)

	local function buildGateObelisk(angle: number, tag: string)
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local basePos = Vector3.new(center.X, floorY, center.Z) + dir * fenceR
		local baseCF  = CFrame.lookAt(basePos, basePos + dir)

		-- Gestufter Schiefer- & Gold-Sockel
		makePart(container, "Plaza_ObeliskBase", Vector3.new(2.7, 1.2, 2.7), baseCF * CFrame.new(0, 0.6, 0), COL_DARK_SLATE, Enum.Material.Slate, nil, true, false)
		makePart(container, "Plaza_ObeliskBaseGold", Vector3.new(2.9, 0.28, 2.9), baseCF * CFrame.new(0, 1.3, 0), COL_GOLD, Enum.Material.Metal)
		makePart(container, "Plaza_ObeliskPlinth", Vector3.new(2.2, 1.1, 2.2), baseCF * CFrame.new(0, 1.95, 0), COL_DARK_SLATE, Enum.Material.Slate)

		-- Verjuengter Obelisk-Schaft (2 Stufen) + 4 goldene Eckleisten
		makePart(container, "Plaza_ObeliskShaftLow", Vector3.new(1.75, 5.2, 1.75), baseCF * CFrame.new(0, 5.1, 0), COL_DARK_SLATE, Enum.Material.Slate, nil, true, false)
		makePart(container, "Plaza_ObeliskBandGold", Vector3.new(1.95, 0.32, 1.95), baseCF * CFrame.new(0, 7.8, 0), COL_GOLD, Enum.Material.Metal)
		makePart(container, "Plaza_ObeliskShaftHigh", Vector3.new(1.35, 4.4, 1.35), baseCF * CFrame.new(0, 10.1, 0), COL_DARK_SLATE, Enum.Material.Slate)

		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				makePart(
					container,
					"Plaza_ObeliskRib",
					Vector3.new(0.24, 9.4, 0.24),
					baseCF * CFrame.new(sx * 0.78, 7.2, sz * 0.78),
					COL_GOLD,
					Enum.Material.Metal
				)
			end
		end

		-- Goldene Spitze & schwebender Honig-Kristall
		makePart(container, "Plaza_ObeliskCap", Vector3.new(1.6, 0.45, 1.6), baseCF * CFrame.new(0, 12.45, 0), COL_GOLD, Enum.Material.Metal)
		makePart(
			container,
			"EventFence_ObeliskGem_" .. tag,
			Vector3.new(1.15, 1.55, 1.15),
			baseCF * CFrame.new(0, 13.8, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
			COL_HONEY_GLOW,
			Enum.Material.Neon
		)
	end

	local function buildMidPillar(angle: number, tag: string)
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local basePos = Vector3.new(center.X, floorY, center.Z) + dir * fenceR
		local baseCF  = CFrame.lookAt(basePos, basePos + dir)

		makePart(container, "PlazaFence_MidBase", Vector3.new(1.75, 1.8, 1.75), baseCF * CFrame.new(0, 0.9, 0), COL_DARK_SLATE, Enum.Material.Slate, nil, true, false)
		makePart(container, "PlazaFence_MidBaseGold", Vector3.new(1.92, 0.26, 1.92), baseCF * CFrame.new(0, 1.9, 0), COL_GOLD, Enum.Material.Metal)
		makePart(container, "PlazaFence_MidShaft", Vector3.new(1.28, 4.4, 1.28), baseCF * CFrame.new(0, 4.2, 0), COL_DARK_SLATE, Enum.Material.Slate, nil, true, false)
		for _, sx in { -1, 1 } do
			makePart(container, "PlazaFence_MidTrim", Vector3.new(0.22, 4.2, 1.36), baseCF * CFrame.new(sx * 0.58, 4.2, 0), COL_GOLD, Enum.Material.Metal)
		end
		makePart(container, "PlazaFence_MidCap", Vector3.new(1.6, 0.38, 1.6), baseCF * CFrame.new(0, 6.55, 0), COL_GOLD, Enum.Material.Metal)
		makePart(
			container,
			"EventFence_MidGem_" .. tag,
			Vector3.new(0.85, 0.85, 0.85),
			baseCF * CFrame.new(0, 7.35, 0) * CFrame.Angles(math.rad(45), math.rad(45), 0),
			COL_HONEY_GLOW,
			Enum.Material.Neon
		)
	end

	for slot = 1, MapConfig.PLOT_COUNT do
		local baseAngle = math.rad((slot - 1) * 45)
		local aStart    = baseAngle + gateHalfAngle
		local aEnd      = baseAngle + math.pi * 0.25 - gateHalfAngle

		-- Die 2 Tor-Obelisken, die den Sektor einrahmen
		buildGateObelisk(aStart, slot .. "_A")
		buildGateObelisk(aEnd, slot .. "_B")

		-- 3 Zaunfelder je Sektor, getrennt durch 2 Zwischenpfeiler
		local bays = 3
		for b = 1, bays do
			local ba0 = aStart + (b - 1) * (aEnd - aStart) / bays
			local ba1 = aStart + b * (aEnd - aStart) / bays
			if b < bays then
				buildMidPillar(ba1, slot .. "_" .. b)
			end

			local bMid = (ba0 + ba1) * 0.5
			local dir  = Vector3.new(math.cos(bMid), 0, math.sin(bMid))
			local chord = 2 * fenceR * math.sin((ba1 - ba0) * 0.5)
			local bayPos = Vector3.new(center.X, floorY, center.Z) + dir * (fenceR * math.cos((ba1 - ba0) * 0.5))
			local bayCF  = CFrame.lookAt(bayPos, bayPos + dir)

			-- Sockelmauer + Schiefer-Deckplatte + leuchtende Honig-Ader
			makePart(container, "PlazaFence_Plinth", Vector3.new(chord, 1.35, 1.15), bayCF * CFrame.new(0, 0.675, 0), COL_CREAM_STONE, Enum.Material.Sandstone, nil, true, false)
			makePart(container, "PlazaFence_PlinthCap", Vector3.new(chord + 0.1, 0.26, 1.32), bayCF * CFrame.new(0, 1.48, 0), COL_DARK_SLATE, Enum.Material.Slate)
			makePart(container, "EventFence_Strip_" .. slot .. "_" .. b, Vector3.new(chord + 0.05, 0.22, 1.24), bayCF * CFrame.new(0, 0.72, 0), COL_HONEY_GLOW, Enum.Material.Neon)

			-- Untere, mittlere und obere Quergurte (Schiefer & Gold)
			makePart(container, "PlazaFence_RailBot", Vector3.new(chord, 0.24, 0.42), bayCF * CFrame.new(0, 2.05, 0), COL_GOLD, Enum.Material.Metal)
			makePart(container, "PlazaFence_RailMid", Vector3.new(chord, 0.22, 0.38), bayCF * CFrame.new(0, 3.85, 0), COL_GOLD, Enum.Material.Metal)
			makePart(container, "PlazaFence_RailTop", Vector3.new(chord, 0.34, 0.55), bayCF * CFrame.new(0, 5.65, 0), COL_DARK_SLATE, Enum.Material.Slate)
			makePart(container, "PlazaFence_RailTopGold", Vector3.new(chord, 0.18, 0.62), bayCF * CFrame.new(0, 5.91, 0), COL_GOLD, Enum.Material.Metal)

			-- 6 vertikale Schiefer-Gitterstaebe mit goldenen Speerspitzen
			local nBars = 6
			for barIdx = 1, nBars do
				local frac = (barIdx - 0.5) / nBars - 0.5
				local xOff = frac * (chord - 1.2)
				local isCenter = (barIdx == 3 or barIdx == 4)
				if isCenter then
					-- Kurze Staebe unter und ueber dem Mittel-Medaillon
					makePart(container, "PlazaFence_BarShort", Vector3.new(0.22, 1.65, 0.22), bayCF * CFrame.new(xOff, 2.9, 0), COL_DARK_SLATE, Enum.Material.Slate)
					makePart(container, "PlazaFence_BarTop", Vector3.new(0.22, 0.75, 0.22), bayCF * CFrame.new(xOff, 5.3, 0), COL_DARK_SLATE, Enum.Material.Slate)
				else
					makePart(container, "PlazaFence_Bar", Vector3.new(0.24, 4.1, 0.24), bayCF * CFrame.new(xOff, 3.65, 0), COL_DARK_SLATE, Enum.Material.Slate)
				end
				-- Goldene Speerspitze auf jedem Stab
				makePart(
					container,
					"PlazaFence_Spear",
					Vector3.new(0.36, 0.65, 0.36),
					bayCF * CFrame.new(xOff, 6.32, 0) * CFrame.Angles(0, math.rad(45), 0),
					COL_GOLD,
					Enum.Material.Metal
				)
			end

			-- Zentrales Sechseck-Wabenmedaillon im Zaunfeld
			local hexCF = bayCF * CFrame.new(0, 3.85, 0)
			buildHexRingVertical(container, "PlazaFence_HexRing", hexCF, 1.05, 0.22, 0.34, COL_GOLD, Enum.Material.Metal)
			makePart(
				container,
				"EventFence_HexCore_" .. slot .. "_" .. b,
				Vector3.new(0.75, 0.75, 0.38),
				hexCF * CFrame.Angles(0, 0, math.rad(45)),
				COL_HONEY_GLOW,
				Enum.Material.Neon
			)

			-- Unsichtbare durchgehende Kollisionswand (verhindert Ueberspringen des Zauns)
			local wall = makePart(
				container,
				"PlazaFence_Barrier",
				Vector3.new(chord + 0.6, 13.5, 1.4),
				bayCF * CFrame.new(0, 6.75, 0),
				COL_DARK_SLATE,
				Enum.Material.SmoothPlastic,
				nil,
				true,
				false
			)
			wall.Transparency = 1
		end
	end
end

--------------------------------------------------------------------------------
-- 3. EINGEFASSTE PRACHT-ALLEEN & IMKER-GALGENLATERNEN (ScenicBuilder)
--------------------------------------------------------------------------------

function HubPlazaBuilder.buildAvenuePaths(parent: Instance)
	local fromRadius = MapConfig.EVENT_PIT_RADIUS + 1.8
	local toRadius   = MapConfig.PLATFORM_RADIUS - 2.2
	local length     = toRadius - fromRadius
	local baseY      = MapConfig.PLATFORM_TOP_Y

	-- FBX-Mesh-Pfad (Hub_Alleen.fbx -> 6 vereinigte MeshParts fuer alle 8 Alleen & Laternen)
	local alleeMeshes = spawnMeshGroup(
		parent,
		"Hub_Allee_Schiefer",
		233.0,
		Vector3.new(0, -0.11, 0),
		CFrame.new(MapConfig.CENTER.X, baseY, MapConfig.CENTER.Z),
		{
			{ name = "Hub_Allee_Schiefer",  color = COL_DARK_SLATE,   material = Enum.Material.Slate },
			{ name = "Hub_Allee_Sandstein", color = COL_CREAM_STONE,  material = Enum.Material.Sandstone },
			{ name = "Hub_Allee_Randstein", color = COL_CREAM_LIGHT,  material = Enum.Material.Sandstone },
			{ name = "Hub_Allee_Gold",      color = COL_GOLD,         material = Enum.Material.Metal },
			{ name = "Hub_Allee_HonigNeon", color = COL_HONEY_GLOW,   material = Enum.Material.Neon },
			{ name = "Hub_Laterne_Holz",    color = COL_WOOD_DARK,    material = Enum.Material.Wood },
		}
	)
	if alleeMeshes then
		for slot = 1, MapConfig.PLOT_COUNT do
			local outward = MapParts.outwardDirection(slot)
			local mid     = MapConfig.CENTER + outward * ((fromRadius + toRadius) * 0.5)
			local at      = Vector3.new(mid.X, baseY + AmbienceConfig.PATH_LIFT, mid.Z)
			local refPath = makePart(parent, "Path_" .. slot, Vector3.new(AmbienceConfig.PATH_WIDTH, 0.12, length), CFrame.lookAt(at, at + outward), COL_CREAM_STONE, Enum.Material.Sandstone)
			refPath.Transparency = 1
		end
		return
	end

	for slot = 1, MapConfig.PLOT_COUNT do
		local outward = MapParts.outwardDirection(slot)
		local mid     = MapConfig.CENTER + outward * ((fromRadius + toRadius) * 0.5)
		local at      = Vector3.new(mid.X, baseY + AmbienceConfig.PATH_LIFT, mid.Z)
		local pathCF  = CFrame.lookAt(at, at + outward)

		-- Sandstein-Bett (behaelt den Namen Path_<slot>)
		makePart(
			parent,
			"Path_" .. slot,
			Vector3.new(AmbienceConfig.PATH_WIDTH + 1.2, 0.14, length),
			pathCF,
			COL_CREAM_STONE,
			Enum.Material.Sandstone
		)

		-- Erhoehte Randsteine links & rechts mit leuchtender Gold-Ader
		local curbOffset = AmbienceConfig.PATH_WIDTH * 0.5 + 0.55
		for _, s in { -1, 1 } do
			makePart(
				parent,
				"PathCurb_" .. slot,
				Vector3.new(0.95, 0.42, length),
				pathCF * CFrame.new(s * curbOffset, 0.16, 0),
				COL_DARK_SLATE,
				Enum.Material.Slate
			)
			makePart(
				parent,
				"PathCurbGold_" .. slot,
				Vector3.new(0.32, 0.12, length),
				pathCF * CFrame.new(s * (curbOffset - 0.18), 0.38, 0),
				COL_GOLD,
				Enum.Material.Metal
			)
		end

		-- 8 Naturstein-Platten entlang der Allee
		local nSlabs = 8
		local slabStep = (length - 4) / nSlabs
		for i = 1, nSlabs do
			local rSlab = fromRadius + 2 + (i - 0.5) * slabStep
			local pSlab = MapConfig.CENTER + outward * rSlab
			local cfSlab = CFrame.lookAt(Vector3.new(pSlab.X, baseY + AmbienceConfig.PATH_LIFT + 0.06, pSlab.Z), Vector3.new(pSlab.X, baseY + AmbienceConfig.PATH_LIFT + 0.06, pSlab.Z) + outward)
			makePart(
				parent,
				"PathSlab_" .. slot,
				Vector3.new(AmbienceConfig.PATH_WIDTH - 0.8, 0.10, slabStep * 0.82),
				cfSlab,
				if i % 2 == 0 then COL_MID_SLATE else COL_DARK_SLATE,
				Enum.Material.Slate
			)
		end

		-- 3 eingelassene goldene Waben-Medaillons je Allee
		local angle = math.atan2(outward.Z, outward.X)
		for _, rMed in { 65, 84, 103 } do
			local pMed = MapConfig.CENTER + outward * rMed
			local medPos = Vector3.new(pMed.X, baseY + AmbienceConfig.PATH_LIFT + 0.12, pMed.Z)
			buildHexRingFlat(parent, "PathHexRing_" .. slot, medPos, 2.3, 0.38, 0.08, COL_GOLD, Enum.Material.Metal, angle)
			makeCylinder(parent, "PathHexCore_" .. slot, medPos + Vector3.new(0, 0.01, 0), 1.45, 0.08, COL_HONEY_GLOW, Enum.Material.Neon, false, false)
		end
	end
end

function HubPlazaBuilder.buildBeekeeperLamp(parent: Instance, pos: Vector3, inwardSideDir: Vector3)
	local baseY = pos.Y
	local h = AmbienceConfig.LAMP_HEIGHT
	local hangX = pos.X + inwardSideDir.X * 2.15
	local hangZ = pos.Z + inwardSideDir.Z * 2.15

	-- Falls Hub_Alleen.fbx aktiv ist, sind die Laternen bereits in den 6 Allee-MeshParts enthalten;
	-- wir erzeugen nur das LampGlow-Ankerpart fuer die PointLights des DayCycleControllers.
	if findAssetMeshPart("Hub_Allee_Schiefer") ~= nil then
		local glow = makeCylinder(parent, "LampGlow", Vector3.new(hangX, baseY + h - 1.15, hangZ), 0.92, 1.35, AmbienceConfig.LAMP_GLOW_COLOR, Enum.Material.Neon, false, false)
		glow.Shape = Enum.PartType.Ball
		glow.Size = Vector3.new(1.85, 2.1, 1.85)
		glow.Transparency = 1
		return
	end

	local lampCF = CFrame.lookAt(Vector3.new(pos.X, baseY, pos.Z), Vector3.new(pos.X, baseY, pos.Z) + inwardSideDir)

	-- Gestufter Stein- & Gold-Sockel
	makePart(parent, "LampBase", Vector3.new(1.8, 0.9, 1.8), lampCF * CFrame.new(0, 0.45, 0), COL_CREAM_STONE, Enum.Material.Sandstone)
	makePart(parent, "LampBaseGold", Vector3.new(1.5, 0.28, 1.5), lampCF * CFrame.new(0, 1.04, 0), COL_GOLD, Enum.Material.Metal)

	-- Dunkler Pfosten + goldener Mittelring
	makeCylinder(parent, "LampPole", Vector3.new(pos.X, baseY + h * 0.5 + 0.5, pos.Z), 0.42, h, COL_WOOD_DARK, Enum.Material.Wood, false, false)
	makeCylinder(parent, "LampCollar", Vector3.new(pos.X, baseY + h * 0.62, pos.Z), 0.56, 0.35, COL_GOLD, Enum.Material.Metal, false, false)

	-- Galgen-Ausleger & Strebe Richtung Allee-Mitte
	makePart(parent, "LampArm", Vector3.new(0.42, 0.42, 3.0), lampCF * CFrame.new(0, h + 0.65, -1.1), COL_GOLD, Enum.Material.Metal)
	makePart(parent, "LampBrace", Vector3.new(0.28, 0.28, 2.2), lampCF * CFrame.new(0, h - 0.15, -0.75) * CFrame.Angles(math.rad(38), 0, 0), COL_WOOD_DARK, Enum.Material.Wood)

	-- Haengende Imker-Laterne (LampGlow behaelt den Namen fuer DayCycleController)
	makeCylinder(parent, "LampChain", Vector3.new(hangX, baseY + h + 0.25, hangZ), 0.12, 0.7, COL_GOLD_DARK, Enum.Material.Metal, false, false)
	makeCylinder(parent, "LampRoof", Vector3.new(hangX, baseY + h - 0.2, hangZ), 1.25, 0.42, COL_WOOD_DARK, Enum.Material.Wood, false, false)
	makeCylinder(parent, "LampRoofGold", Vector3.new(hangX, baseY + h - 0.42, hangZ), 1.32, 0.14, COL_GOLD, Enum.Material.Metal, false, false)

	local glow = makeCylinder(parent, "LampGlow", Vector3.new(hangX, baseY + h - 1.15, hangZ), 0.92, 1.35, AmbienceConfig.LAMP_GLOW_COLOR, Enum.Material.Neon, false, false)
	glow.Shape = Enum.PartType.Ball
	glow.Size = Vector3.new(1.85, 2.1, 1.85)

	makeCylinder(parent, "LampBottom", Vector3.new(hangX, baseY + h - 1.95, hangZ), 0.72, 0.28, COL_GOLD, Enum.Material.Metal, false, false)
end

--------------------------------------------------------------------------------
-- 4. GESCHWUNGENE BOGENBRUECKEN (MapParts.buildSpan)
--------------------------------------------------------------------------------

function HubPlazaBuilder.buildArchedBridge(
	parent: Instance,
	name: string,
	outward: Vector3,
	fromRadius: number,
	toRadius: number
)
	local innerEdge  = fromRadius - MapConfig.BRIDGE_OVERLAP
	local outerEdge  = toRadius + MapConfig.BRIDGE_OVERLAP
	local deckLength = outerEdge - innerEdge
	local baseDeckY  = MapConfig.PLATFORM_TOP_Y - MapConfig.BRIDGE_SINK
	local archH      = HubPlazaBuilder.BRIDGE_ARCH_HEIGHT
	local width      = MapConfig.BRIDGE_WIDTH
	local waterY     = MapConfig.PLATFORM_TOP_Y - MapConfig.WATER_DROP

	-- 4a. Begehbare Bogen-Segmente (CanCollide = true, CanQuery = true, Name enthaelt "Bridge" fuer DebugBridge)
	local nPlanks = 13
	local plankStep = deckLength / nPlanks
	local plankThick = 0.55

	-- Haupt-Referenzpart (unsichtbar, fuer FindFirstChild(name))
	local midPoint = MapConfig.CENTER + outward * ((innerEdge + outerEdge) * 0.5)
	local mainRef = MapParts.newPart(
		name,
		Vector3.new(width, MapConfig.BRIDGE_HEIGHT, deckLength),
		CFrame.lookAt(
			Vector3.new(midPoint.X, baseDeckY - MapConfig.BRIDGE_HEIGHT * 0.5, midPoint.Z),
			Vector3.new(midPoint.X, baseDeckY - MapConfig.BRIDGE_HEIGHT * 0.5, midPoint.Z) + outward
		),
		COL_WOOD_WARM,
		Enum.Material.WoodPlanks
	)
	mainRef.Transparency = 1
	mainRef.CanCollide   = false
	mainRef.CanQuery     = false
	mainRef.CanTouch     = false
	mainRef.CastShadow   = false
	mainRef.Parent       = parent

	-- FBX-Mesh-Pfad (Hub_Bruecke.fbx -> 7 vereinigte MeshParts je Bruecke + unsichtbare Bogen-Collider)
	local slotIdx = tonumber(string.match(name, "%d+")) or 1
	local laneColors = AmbienceConfig.LANE_COLORS
	local laneColor = (laneColors and laneColors[slotIdx]) or COL_HONEY_GLOW
	local yaw = -math.atan2(outward.Z, outward.X)
	local brueckeMeshes = spawnMeshGroup(
		parent,
		"Hub_Bruecke_HolzHell",
		34.058,
		Vector3.new(0, -1.616, 0),
		CFrame.new(midPoint.X, MapConfig.PLATFORM_TOP_Y, midPoint.Z) * CFrame.Angles(0, yaw, 0),
		{
			{ name = "Hub_Bruecke_HolzHell",   color = COL_WOOD_WARM,               material = Enum.Material.WoodPlanks, targetName = name .. "_MeshHolzHell" },
			{ name = "Hub_Bruecke_HolzMittel", color = Color3.fromRGB(148, 96, 56), material = Enum.Material.WoodPlanks, targetName = name .. "_MeshHolzMittel" },
			{ name = "Hub_Bruecke_HolzDunkel", color = COL_WOOD_DARK,               material = Enum.Material.Wood,       targetName = name .. "Rail_MeshHolzDunkel" },
			{ name = "Hub_Bruecke_Randstein",  color = COL_CREAM_STONE,             material = Enum.Material.Sandstone,  targetName = name .. "_MeshRandstein" },
			{ name = "Hub_Bruecke_Gold",       color = COL_GOLD,                    material = Enum.Material.Metal,      targetName = name .. "Rail_MeshGold" },
			{ name = "Hub_Bruecke_HonigNeon",  color = COL_HONEY_GLOW,              material = Enum.Material.Neon,       targetName = name .. "Rail_MeshHonig" },
			{ name = "Hub_Bruecke_SlotAkzent", color = laneColor,                   material = Enum.Material.Neon,       targetName = name .. "Rail_MeshAkzent" },
		}
	)
	if brueckeMeshes then
		for i = 1, nPlanks do
			local t0 = (i - 1) / nPlanks
			local t1 = i / nPlanks
			local tm = (t0 + t1) * 0.5
			local r0 = innerEdge + t0 * deckLength
			local r1 = innerEdge + t1 * deckLength
			local rm = (r0 + r1) * 0.5
			local y0 = baseDeckY + archH * math.sin(math.pi * t0)
			local y1 = baseDeckY + archH * math.sin(math.pi * t1)
			local ym = baseDeckY + archH * math.sin(math.pi * tm)
			local segLen = math.sqrt((r1 - r0) ^ 2 + (y1 - y0) ^ 2)
			local p0 = MapConfig.CENTER + outward * r0
			local p1 = MapConfig.CENTER + outward * r1
			local pm = MapConfig.CENTER + outward * rm
			local segCF = CFrame.lookAt(
				Vector3.new(pm.X, ym - plankThick * 0.5, pm.Z),
				Vector3.new(p1.X, y1 - plankThick * 0.5, p1.Z)
			)
			local colPlank = makePart(parent, name .. "_Plank_" .. i, Vector3.new(width - 0.6, plankThick, segLen + 0.18), segCF, COL_WOOD_WARM, Enum.Material.WoodPlanks, nil, true, true)
			colPlank.Transparency = 1
		end
		return
	end

	for i = 1, nPlanks do
		local t0 = (i - 1) / nPlanks
		local t1 = i / nPlanks
		local tm = (t0 + t1) * 0.5
		local r0 = innerEdge + t0 * deckLength
		local r1 = innerEdge + t1 * deckLength
		local rm = (r0 + r1) * 0.5

		local y0 = baseDeckY + archH * math.sin(math.pi * t0)
		local y1 = baseDeckY + archH * math.sin(math.pi * t1)
		local ym = baseDeckY + archH * math.sin(math.pi * tm)
		local segLen = math.sqrt((r1 - r0) ^ 2 + (y1 - y0) ^ 2)

		local p0 = MapConfig.CENTER + outward * r0
		local p1 = MapConfig.CENTER + outward * r1
		local pm = MapConfig.CENTER + outward * rm

		local from3 = Vector3.new(p0.X, y0 - plankThick * 0.5, p0.Z)
		local to3   = Vector3.new(p1.X, y1 - plankThick * 0.5, p1.Z)
		local mid3  = Vector3.new(pm.X, ym - plankThick * 0.5, pm.Z)
		local segCF = CFrame.lookAt(mid3, to3)

		-- Holzbohle (Epilog-Stil: abwechselnd warme Holztoene, leicht ueberlappend fuer geschlossene Oberflaeche)
		local plankColor = if i % 2 == 0 then COL_WOOD_WARM else Color3.fromRGB(148, 96, 56)
		local plank = makePart(
			parent,
			name .. "_Plank_" .. i,
			Vector3.new(width - 0.6, plankThick, segLen + 0.18),
			segCF,
			plankColor,
			Enum.Material.WoodPlanks,
			nil,
			true,
			true
		)
		plank.TopSurface = Enum.SurfaceType.Smooth

		-- Seitliche Goldleisten an jeder Bohle (wie Epilog_Plank)
		for _, s in { -1, 1 } do
			makePart(
				parent,
				name .. "_GoldTrim",
				Vector3.new(0.45, plankThick + 0.06, plankStep * 0.86),
				segCF * CFrame.new(s * (width * 0.5 - 0.15), 0.02, 0),
				COL_GOLD,
				Enum.Material.Metal
			)
			-- Dunkle Laengswangen & Handlauf-Segmente (Name enthaelt "Rail", damit DebugBridge sie ignoriert)
			makePart(
				parent,
				name .. "Rail_Stringer",
				Vector3.new(0.75, 0.72, segLen + 0.25),
				segCF * CFrame.new(s * (width * 0.5 + 0.35), -0.15, 0),
				COL_DARK_SLATE,
				Enum.Material.Slate
			)
			makePart(
				parent,
				name .. "Rail_Top",
				Vector3.new(0.55, 0.35, segLen + 0.22),
				segCF * CFrame.new(s * (width * 0.5 + 0.35), 2.35, 0),
				COL_WOOD_DARK,
				Enum.Material.Wood,
				nil,
				true,
				false
			)
			makePart(
				parent,
				name .. "Rail_Gold",
				Vector3.new(0.32, 0.16, segLen + 0.22),
				segCF * CFrame.new(s * (width * 0.5 + 0.35), 2.58, 0),
				COL_GOLD,
				Enum.Material.Metal
			)
		end

		-- Gelaenderpfosten mit Goldkappe an jedem zweiten Segment
		if i % 2 == 1 then
			for _, s in { -1, 1 } do
				local postPos = (segCF * CFrame.new(s * (width * 0.5 + 0.35), 1.15, 0)).Position
				local postCF  = CFrame.lookAt(postPos, postPos + outward)
				makePart(parent, name .. "Rail_Post", Vector3.new(0.68, 2.7, 0.68), postCF, COL_DARK_SLATE, Enum.Material.Slate)
				makePart(parent, name .. "Rail_PostCap", Vector3.new(0.84, 0.24, 0.84), postCF * CFrame.new(0, 1.42, 0), COL_GOLD, Enum.Material.Metal)
			end
		end
	end

	-- 4b. 4 Steinpfeiler im Wasser unter der Bruecke + Schaumringe
	local side = Vector3.new(-outward.Z, 0, outward.X)
	for _, tPier in { 0.24, 0.76 } do
		local rPier = innerEdge + tPier * deckLength
		local yTop  = baseDeckY + archH * math.sin(math.pi * tPier) - 0.4
		local pierH = math.max(2.0, yTop - (waterY - 3.5))
		for _, s in { -1, 1 } do
			local pPier = MapConfig.CENTER + outward * rPier + side * (s * (width * 0.5 - 0.5))
			makeCylinder(
				parent,
				name .. "_WaterPier",
				Vector3.new(pPier.X, yTop - pierH * 0.5, pPier.Z),
				1.35,
				pierH,
				COL_CREAM_STONE,
				Enum.Material.Sandstone,
				false,
				false
			)
			makeCylinder(
				parent,
				name .. "_WaterPierGold",
				Vector3.new(pPier.X, yTop - 0.35, pPier.Z),
				1.52,
				0.38,
				COL_GOLD,
				Enum.Material.Metal,
				false,
				false
			)
			local foam = makeCylinder(
				parent,
				name .. "_PierFoam",
				Vector3.new(pPier.X, waterY + 0.06, pPier.Z),
				2.05,
				0.10,
				COL_FOAM,
				Enum.Material.SmoothPlastic,
				false,
				false
			)
			foam.Transparency = 0.3
		end
	end

	-- 4c. Mittige Laternen-Galgen am Brueckenscheitel (t = 0.5, ausserhalb der Fahrbahn)
	local rMid = (innerEdge + outerEdge) * 0.5
	local yMid = baseDeckY + archH
	for _, s in { -1, 1 } do
		local pLantern = MapConfig.CENTER + outward * rMid + side * (s * (width * 0.5 + 0.45))
		local basePos  = Vector3.new(pLantern.X, yMid, pLantern.Z)
		local cfL      = CFrame.lookAt(basePos, basePos - side * s)

		makePart(parent, name .. "Rail_LanternPost", Vector3.new(0.78, 6.2, 0.78), cfL * CFrame.new(0, 3.1, 0), COL_DARK_SLATE, Enum.Material.Slate)
		makePart(parent, name .. "Rail_LanternArm", Vector3.new(0.38, 0.38, 2.1), cfL * CFrame.new(0, 6.0, -0.75), COL_GOLD, Enum.Material.Metal)
		makePart(
			parent,
			name .. "Rail_LanternGlow",
			Vector3.new(1.1, 1.35, 1.1),
			cfL * CFrame.new(0, 5.1, -1.55),
			COL_HONEY_GLOW,
			Enum.Material.Neon,
			Enum.PartType.Ball
		)
	end
end

-- Hoehe der Bruecken-Oberkante bei einem Abstand `radius` zur Weltmitte (fuer PlotRoutes)
function HubPlazaBuilder.bridgeSurfaceY(radius: number, fromRadius: number, toRadius: number): number
	local innerEdge = fromRadius - MapConfig.BRIDGE_OVERLAP
	local outerEdge = toRadius + MapConfig.BRIDGE_OVERLAP
	local t = math.clamp((radius - innerEdge) / math.max(1e-3, outerEdge - innerEdge), 0, 1)
	return (MapConfig.PLATFORM_TOP_Y - MapConfig.BRIDGE_SINK) + HubPlazaBuilder.BRIDGE_ARCH_HEIGHT * math.sin(math.pi * t)
end

--------------------------------------------------------------------------------
-- 5. BRUECKENKOPF-PORTALE (ScenicBuilder.buildBridgePosts)
--------------------------------------------------------------------------------

function HubPlazaBuilder.buildBridgePortals(parent: Instance)
	local deckTop    = MapConfig.PLATFORM_TOP_Y - MapConfig.BRIDGE_SINK
	local sideOffset = (MapConfig.BRIDGE_WIDTH + MapConfig.BRIDGE_RAIL_WIDTH) * 0.5 + 0.35
	local fromRadius = MapConfig.PLATFORM_RADIUS
	local toRadius   = MapConfig.PLOT_RING_RADIUS - MapConfig.PLOT_ISLAND_RADIUS
	local inset      = AmbienceConfig.BRIDGE_POST_INSET
	local laneColors = AmbienceConfig.LANE_COLORS

	for slot = 1, MapConfig.PLOT_COUNT do
		local outward   = MapParts.outwardDirection(slot)
		local side      = Vector3.new(-outward.Z, 0, outward.X)
		local laneColor = (laneColors and laneColors[slot]) or AmbienceConfig.LAMP_GLOW_COLOR

		for idx, radius in { fromRadius + inset, toRadius - inset } do
			local surfaceY = HubPlazaBuilder.bridgeSurfaceY(radius, fromRadius, toRadius)
			for _, sign in { -1, 1 } do
				local p = MapConfig.CENTER + outward * radius + side * (sign * sideOffset)
				local baseCF = CFrame.lookAt(Vector3.new(p.X, surfaceY, p.Z), Vector3.new(p.X, surfaceY, p.Z) + outward)
				local h = AmbienceConfig.BRIDGE_POST_HEIGHT + 1.2

				-- Falls Hub_Bruecke.fbx aktiv ist, sind die Portale bereits im Bruecken-Mesh enthalten;
				-- wir erzeugen nur das BridgeCap-Ankerpart fuer die PointLights des DayCycleControllers.
				if findAssetMeshPart("Hub_Bruecke_HolzHell") ~= nil then
					local cap = makePart(
						parent,
						"BridgeCap",
						Vector3.new(1.55, 1.85, 1.55),
						baseCF * CFrame.new(0, h + 1.65, 0),
						laneColor,
						Enum.Material.Neon
					)
					cap.Transparency = 1
					continue
				end

				-- Gestufter Schiefer- & Gold-Portalpfeiler
				makePart(parent, "BridgePostBase", Vector3.new(2.1, 1.4, 2.1), baseCF * CFrame.new(0, 0.7, 0), COL_CREAM_STONE, Enum.Material.Sandstone)
				makePart(parent, "BridgePost", Vector3.new(1.5, h, 1.5), baseCF * CFrame.new(0, h * 0.5 + 0.5, 0), COL_DARK_SLATE, Enum.Material.Slate)
				makePart(parent, "BridgePostGold", Vector3.new(1.75, 0.35, 1.75), baseCF * CFrame.new(0, h + 0.55, 0), COL_GOLD, Enum.Material.Metal)

				-- Schwebender Slot-Kristall (Name "BridgeCap" fuer DayCycleController)
				makePart(
					parent,
					"BridgeCap",
					Vector3.new(1.55, 1.85, 1.55),
					baseCF * CFrame.new(0, h + 1.65, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
					laneColor,
					Enum.Material.Neon
				)

				if idx == 1 then
					local barPos = p + side * (sign * 1.15) + Vector3.new(0, surfaceY + h - 0.25, 0)
					makePart(
						parent,
						"LaneCrossbar",
						Vector3.new(2.3, 0.36, 0.36),
						CFrame.lookAt(barPos, barPos + outward),
						COL_GOLD,
						Enum.Material.Metal
					)

					local flagPos = p + side * (sign * 1.35) + Vector3.new(0, surfaceY + h - 1.55, 0)
					local flagCF = CFrame.lookAt(flagPos, flagPos + outward)
					makePart(
						parent,
						"LanePennant",
						Vector3.new(1.6, 2.5, 0.22),
						flagCF,
						laneColor,
						Enum.Material.SmoothPlastic
					)
					makePart(
						parent,
						"LanePennantGold",
						Vector3.new(1.7, 0.25, 0.26),
						flagCF * CFrame.new(0, -1.25, 0),
						COL_GOLD,
						Enum.Material.Metal
					)
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- 6. PAVILLON-RAHMEN FUER DIE BESTENLISTEN- & LIVE-TAFELN
--------------------------------------------------------------------------------

function HubPlazaBuilder.decorateBoardPavilion(parent: Instance, boardName: string, frame: CFrame, size: Vector3, postHeight: number)
	local totalH = postHeight + size.Y
	local groundCF = frame * CFrame.new(0, -size.Y * 0.5 - postHeight, 0)

	-- Steinsockel unter der Tafel
	makePart(parent, boardName .. "_Plinth", Vector3.new(size.X + 2.8, 0.85, 3.2), groundCF * CFrame.new(0, 0.425, 0.4), COL_CREAM_STONE, Enum.Material.Sandstone)
	makePart(parent, boardName .. "_PlinthGold", Vector3.new(size.X + 3.1, 0.22, 3.4), groundCF * CFrame.new(0, 0.92, 0.4), COL_GOLD, Enum.Material.Metal)

	-- Pavillon-Dach ueber der Tafel
	makePart(parent, boardName .. "_RoofBeam", Vector3.new(size.X + 2.6, 0.55, 2.6), groundCF * CFrame.new(0, totalH + 0.35, 0.4), COL_DARK_SLATE, Enum.Material.Slate)
	makePart(parent, boardName .. "_RoofGold", Vector3.new(size.X + 3.0, 0.24, 2.9), groundCF * CFrame.new(0, totalH + 0.72, 0.4), COL_GOLD, Enum.Material.Metal)
	makePart(parent, boardName .. "_RoofCrest", Vector3.new(size.X + 1.2, 0.65, 1.8), groundCF * CFrame.new(0, totalH + 1.15, 0.4), COL_DARK_SLATE, Enum.Material.Slate)
end

--------------------------------------------------------------------------------
-- 7. HAUPTINSEL-SANKTUARIUM-PARK & UFERPROMENADE (Statt Baseplate-Slop)
--------------------------------------------------------------------------------

local COL_GRASS_DEEP   = Color3.fromRGB(62, 140, 62)
local COL_GRASS_MID    = Color3.fromRGB(72, 152, 68)
local COL_GRASS_SUNLIT = Color3.fromRGB(84, 164, 76)

function HubPlazaBuilder.buildMainIslandMeadow(parent: Instance)
	-- Entferne evtl. alte GrassTile- oder GroundStuds-Reste
	for _, child in parent:GetChildren() do
		if child.Name == "GrassTile" or child.Name == "GroundStuds" or string.sub(child.Name, 1, 7) == "Meadow_" then
			child:Destroy()
		end
	end

	local ground = parent:FindFirstChild("Ground")
	if ground and ground:IsA("BasePart") then
		ground.Color      = COL_GRASS_DEEP
		ground.Material   = Enum.Material.Grass
		ground.TopSurface = Enum.SurfaceType.Smooth
		local studTex = ground:FindFirstChild("StudTexture")
		if studTex then
			studTex:Destroy()
		end
	end
	local shore = parent:FindFirstChild("GroundShore")
	if shore and shore:IsA("BasePart") then
		shore.Color    = Color3.fromRGB(234, 212, 166)
		shore.Material = Enum.Material.Sand
	end

	local cx, cz = MapConfig.CENTER.X, MapConfig.CENTER.Z
	local baseY  = MapConfig.PLATFORM_TOP_Y
	local maxR   = MapConfig.PLATFORM_RADIUS

	-- FBX-Mesh-Pfad (Hub_InselBoden.fbx -> vereinigte MeshParts fuer Hauptinsel-Park & Uferkranz)
	local inselMeshes = spawnMeshGroup(
		parent,
		"Hub_Insel_Sandstein",
		241.0,
		Vector3.new(0, 0.45, 0),
		CFrame.new(cx, baseY, cz),
		{
			{ name = "Hub_Insel_Sandstein",   color = COL_CREAM_STONE,  material = Enum.Material.Sandstone, targetName = "Meadow_MeshSandstein" },
			{ name = "Hub_Insel_Randstein",   color = COL_CREAM_LIGHT,  material = Enum.Material.Sandstone, targetName = "Meadow_MeshRandstein" },
			{ name = "Hub_Insel_Schiefer",    color = COL_DARK_SLATE,   material = Enum.Material.Slate,     targetName = "Meadow_MeshSchiefer" },
			{ name = "Hub_Insel_Gold",        color = COL_GOLD,         material = Enum.Material.Metal,     targetName = "Meadow_MeshGold" },
			{ name = "Hub_Insel_HonigNeon",   color = COL_HONEY_GLOW,   material = Enum.Material.Neon,      targetName = "Meadow_MeshHonig" },
			{ name = "Hub_Insel_WieseHell",   color = COL_GRASS_SUNLIT, material = Enum.Material.Grass,     targetName = "Meadow_MeshWieseHell" },
			{ name = "Hub_Insel_WieseMittel", color = COL_GRASS_MID,    material = Enum.Material.Grass,     targetName = "Meadow_MeshWieseMittel" },
		}
	)
	if inselMeshes then
		return
	end

	-- 7a. Konzentrische botanische Rasenspiegel & eingelassene Sandstein-Gartenringe
	--     (Alle Oberkanten zwischen Y = +0.008 und +0.040, flimmerfrei unter den Alleen)
	local function disc(name: string, radius: number, topOffset: number, color: Color3, mat: Enum.Material)
		makeCylinder(parent, name, Vector3.new(cx, baseY + topOffset * 0.5, cz), radius, topOffset, color, mat, false, false)
	end

	disc("Meadow_BandOuter",       maxR - 3.6, 0.008, COL_GRASS_MID,    Enum.Material.Grass)
	disc("Meadow_RingOuterStone",  99.8,       0.013, COL_CREAM_LIGHT,  Enum.Material.Sandstone)
	disc("Meadow_RingOuterGold",   99.1,       0.015, COL_GOLD,         Enum.Material.Metal)
	disc("Meadow_BandMidDark",     98.5,       0.018, COL_GRASS_DEEP,   Enum.Material.Grass)
	disc("Meadow_BandMidLight",    86.2,       0.022, COL_GRASS_SUNLIT, Enum.Material.Grass)
	disc("Meadow_RingInnerStone",  73.4,       0.026, COL_CREAM_LIGHT,  Enum.Material.Sandstone)
	disc("Meadow_RingInnerGold",   72.7,       0.028, COL_GOLD,         Enum.Material.Metal)
	disc("Meadow_BandInner",       72.1,       0.032, COL_GRASS_MID,    Enum.Material.Grass)
	disc("Meadow_PlazaApronGold",  54.5,       0.036, COL_GOLD,         Enum.Material.Metal)
	disc("Meadow_PlazaApronStone", 53.8,       0.040, COL_CREAM_STONE,  Enum.Material.Sandstone)

	-- 7b. 8 Sektor-Gartenspiegel, Waben-Gartensteine & Koenigliche Uferpromenade
	local rimR = maxR - 1.2
	local bridgeHalfGapAngle = 0.074 -- haelt Allee + Brueckenportal komplett frei

	for slot = 1, MapConfig.PLOT_COUNT do
		local baseAngle = math.rad((slot - 1) * 45)
		local secAngle  = baseAngle + math.pi / 8
		local secDir    = Vector3.new(math.cos(secAngle), 0, math.sin(secAngle))

		-- Sanfter radialer Rasen-Mittelspiegel je Parksektor mit schmaler Sandstein-Fassung
		local rayLen = 56.0
		local rayMid = Vector3.new(cx, baseY + 0.017, cz) + secDir * 84.0
		local rayCF  = CFrame.lookAt(rayMid, rayMid + secDir)
		makePart(parent, "Meadow_SectorLawn", Vector3.new(13.5, 0.034, rayLen), rayCF, COL_GRASS_SUNLIT, Enum.Material.Grass)
		for _, s in { -1, 1 } do
			makePart(parent, "Meadow_SectorBorder", Vector3.new(0.48, 0.038, rayLen), rayCF * CFrame.new(s * 7.0, 0, 0), COL_CREAM_LIGHT, Enum.Material.Sandstone)
		end

		-- Eingelassene Garten-Wabenmedaillons bei R = 63.0 und R = 107.0 auf der Sektor-Halbierenden
		-- (Slot 2 / 67.5 Grad hat bei R = 66 den Ei-Haendler -> bekommt dort ein eigenes Haendler-Rondell)
		for _, rHex in { 63.0, 107.0 } do
			if not (slot == 2 and rHex < 70) then
				local pHex = Vector3.new(cx, baseY + 0.042, cz) + secDir * rHex
				buildHexRingFlat(parent, "Meadow_SectorHex", pHex, 2.5, 0.42, 0.06, COL_CREAM_STONE, Enum.Material.Sandstone, secAngle)
				buildHexRingFlat(parent, "Meadow_SectorHexGold", pHex + Vector3.new(0, 0.01, 0), 1.85, 0.28, 0.06, COL_GOLD, Enum.Material.Metal, secAngle)
				makeCylinder(parent, "Meadow_SectorHexCore", pHex + Vector3.new(0, 0.015, 0), 1.1, 0.06, COL_HONEY_GLOW, Enum.Material.Neon, false, false)
			end
		end

		-- Koenigliches Haendler-Rondell bei 67.5 Grad (Slot 2), R = 66
		if slot == 2 then
			local mPos = Vector3.new(cx, baseY, cz) + secDir * 66.0
			makeCylinder(parent, "Meadow_MerchantPlinth", mPos + Vector3.new(0, 0.06, 0), 6.2, 0.12, COL_CREAM_STONE, Enum.Material.Sandstone, false, false)
			makeCylinder(parent, "Meadow_MerchantGold", mPos + Vector3.new(0, 0.08, 0), 5.6, 0.14, COL_GOLD, Enum.Material.Metal, false, false)
			makeCylinder(parent, "Meadow_MerchantSlate", mPos + Vector3.new(0, 0.10, 0), 5.1, 0.16, COL_DARK_SLATE, Enum.Material.Slate, false, false)
		end

		-- 3-teiliger Uferpromenaden-Bogen zwischen zwei Brueckenkoepfen
		local aStart = baseAngle + bridgeHalfGapAngle
		local aEnd   = baseAngle + math.pi * 0.25 - bridgeHalfGapAngle
		local segs   = 3
		for sIdx = 1, segs do
			local a0   = aStart + (sIdx - 1) * (aEnd - aStart) / segs
			local a1   = aStart + sIdx * (aEnd - aStart) / segs
			local aMid = (a0 + a1) * 0.5
			local dir  = Vector3.new(math.cos(aMid), 0, math.sin(aMid))
			local chord = 2 * rimR * math.sin((a1 - a0) * 0.5) + 0.45
			local rCos  = rimR * math.cos((a1 - a0) * 0.5)
			local segPos = Vector3.new(cx, baseY, cz) + dir * rCos
			local segCF  = CFrame.lookAt(segPos, segPos + dir)

			-- Aeussere Sandstein-Klippenfassung (verkleidet die Zylinderschulter zum Sandstrand)
			makePart(parent, "Meadow_RimCliff", Vector3.new(chord + 0.4, 2.0, 1.5), segCF * CFrame.new(0, -0.55, 0.65), COL_CREAM_STONE, Enum.Material.Sandstone)
			-- Dunkler Schiefer-Uferbordstein + Goldader
			makePart(parent, "Meadow_RimSlate", Vector3.new(chord + 0.2, 0.42, 1.45), segCF * CFrame.new(0, 0.52, 0.35), COL_DARK_SLATE, Enum.Material.Slate)
			makePart(parent, "Meadow_RimGold", Vector3.new(chord + 0.25, 0.14, 0.48), segCF * CFrame.new(0, 0.78, 0.35), COL_GOLD, Enum.Material.Metal)
			-- Innerer heller Creme-Gartenbordstein
			makePart(parent, "Meadow_RimInnerCurb", Vector3.new(chord, 0.24, 1.65), segCF * CFrame.new(0, 0.12, -1.05), COL_CREAM_LIGHT, Enum.Material.Sandstone)
		end

		-- Ufer-Bastion & Waben-Grenzstein in der Mitte jedes Uferbogens (secAngle)
		local bastPos = Vector3.new(cx, baseY, cz) + secDir * (maxR - 1.5)
		local bastCF  = CFrame.lookAt(bastPos, bastPos + secDir)
		makeCylinder(parent, "Meadow_BastionBase", bastPos + Vector3.new(0, -0.35, 0), 2.8, 1.9, COL_CREAM_STONE, Enum.Material.Sandstone, false, false)
		makeCylinder(parent, "Meadow_BastionSlate", bastPos + Vector3.new(0, 0.55, 0), 2.35, 0.45, COL_DARK_SLATE, Enum.Material.Slate, false, false)
		makeCylinder(parent, "Meadow_BastionGold", bastPos + Vector3.new(0, 0.82, 0), 2.05, 0.18, COL_GOLD, Enum.Material.Metal, false, false)
		makePart(parent, "Meadow_BastionPillar", Vector3.new(1.15, 1.65, 1.15), bastCF * CFrame.new(0, 1.65, 0), COL_DARK_SLATE, Enum.Material.Slate)
		makePart(parent, "Meadow_BastionCap", Vector3.new(1.38, 0.28, 1.38), bastCF * CFrame.new(0, 2.55, 0), COL_GOLD, Enum.Material.Metal)
		makePart(
			parent,
			"Meadow_BastionGem",
			Vector3.new(0.78, 0.95, 0.78),
			bastCF * CFrame.new(0, 3.15, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
			COL_HONEY_GLOW,
			Enum.Material.Neon
		)
	end
end

--------------------------------------------------------------------------------
-- 8. SPIELER-INSEL-PLATTFORMEN (PlotIsland_1..8 — Basis, Uferkranz & Vorplaetze)
--------------------------------------------------------------------------------

function HubPlazaBuilder.buildPlotIslandGround(parent: Instance, slot: number, center: Vector3)
	local oldStuds = parent:FindFirstChild("PlotGroundStuds_" .. slot)
	if oldStuds then
		oldStuds:Destroy()
	end
	local oldFolder = parent:FindFirstChild("PlotIslandDecor_" .. slot)
	if oldFolder then
		oldFolder:Destroy()
	end

	local plotIsland = parent:FindFirstChild("PlotIsland_" .. slot)
	if plotIsland and plotIsland:IsA("BasePart") then
		plotIsland.Color      = COL_GRASS_DEEP
		plotIsland.Material   = Enum.Material.Grass
		plotIsland.TopSurface = Enum.SurfaceType.Smooth
	end
	local plotShore = parent:FindFirstChild("PlotIsland_" .. slot .. "Shore")
	if plotShore and plotShore:IsA("BasePart") then
		plotShore.Color    = Color3.fromRGB(234, 212, 166)
		plotShore.Material = Enum.Material.Sand
	end

	local folder = Instance.new("Folder")
	folder.Name   = "PlotIslandDecor_" .. slot
	folder.Parent = parent

	local cx, cz  = center.X, center.Z
	local baseY   = MapConfig.PLATFORM_TOP_Y
	local radius  = MapConfig.PLOT_ISLAND_RADIUS
	local outward = MapParts.outwardDirection(slot)
	local plotCF  = MapParts.plotCFrame(slot) -- lokales -Z = Richtung Hauptinsel, +Z = Richtung Arena

	-- 8a. Konzentrische botanische Wiesenringe & Frei-Insel-Mittelmedaillon
	--     (Wenn ein Spieler spawnt, ueberdeckt sein 72x72-Beet auf Y=2.0 den inneren Bereich;
	--      auf freien Inseln bildet dies einen einladenden, edlen Sanktuarium-Hain!)
	local function disc(name: string, r: number, topOffset: number, color: Color3, mat: Enum.Material)
		makeCylinder(folder, name, Vector3.new(cx, baseY + topOffset * 0.5, cz), r, topOffset, color, mat, false, false)
	end

	disc("PlotMeadow_Outer",      radius - 2.6, 0.008, COL_GRASS_MID,    Enum.Material.Grass)
	disc("PlotMeadow_StoneRing",  radius - 5.8, 0.014, COL_CREAM_LIGHT,  Enum.Material.Sandstone)
	disc("PlotMeadow_GoldRing",   radius - 6.3, 0.016, COL_GOLD,         Enum.Material.Metal)
	disc("PlotMeadow_Mid",        radius - 6.8, 0.020, COL_GRASS_DEEP,   Enum.Material.Grass)
	disc("PlotMeadow_InnerStone", 31.5,         0.024, COL_CREAM_LIGHT,  Enum.Material.Sandstone)
	disc("PlotMeadow_Inner",      30.7,         0.028, COL_GRASS_SUNLIT, Enum.Material.Grass)

	-- Zentrales Waben-Medaillon & Gartenpfad fuer unbesetzte Inseln (unter Y = 0.08, verschwindet unter Base)
	disc("PlotMeadow_CenterStone", 9.2, 0.034, COL_CREAM_STONE, Enum.Material.Sandstone)
	disc("PlotMeadow_CenterGold",  8.2, 0.038, COL_GOLD,        Enum.Material.Metal)
	disc("PlotMeadow_CenterSlate", 7.5, 0.042, COL_DARK_SLATE,  Enum.Material.Slate)
	buildHexRingFlat(
		folder,
		"PlotMeadow_CenterHex",
		Vector3.new(cx, baseY + 0.048, cz),
		4.2,
		0.55,
		0.04,
		COL_GOLD,
		Enum.Material.Metal,
		math.atan2(outward.Z, outward.X)
	)
	disc("PlotMeadow_CenterHoney", 2.4, 0.052, COL_HONEY_GLOW, Enum.Material.Neon)

	makePart(
		folder,
		"PlotMeadow_FreeWalk",
		Vector3.new(7.2, 0.032, 72.0),
		plotCF * CFrame.new(0, 0.016, 0),
		COL_CREAM_STONE,
		Enum.Material.Sandstone
	)

	-- 8b. Bruecken-Empfangsplaetze (Vorplatz vorne -Z zur Hauptinsel & hinten +Z zur Arena)
	for _, zSign in { -1, 1 } do
		-- Liegt zwischen Beet-Kante (z = 36) und Inselrand (z = 57.2)
		local zMid = zSign * 46.8
		local foreCF = plotCF * CFrame.new(0, 0.04, zMid)
		makePart(folder, "PlotForecourt_Bed", Vector3.new(13.2, 0.08, 21.0), foreCF, COL_CREAM_STONE, Enum.Material.Sandstone)
		makePart(folder, "PlotForecourt_Slab", Vector3.new(10.4, 0.10, 18.2), foreCF * CFrame.new(0, 0.01, 0), COL_DARK_SLATE, Enum.Material.Slate)

		for _, xSide in { -1, 1 } do
			makePart(folder, "PlotForecourt_Curb", Vector3.new(0.85, 0.32, 20.6), foreCF * CFrame.new(xSide * 6.2, 0.12, 0), COL_DARK_SLATE, Enum.Material.Slate)
			makePart(folder, "PlotForecourt_CurbGold", Vector3.new(0.30, 0.10, 20.6), foreCF * CFrame.new(xSide * 6.05, 0.30, 0), COL_GOLD, Enum.Material.Metal)
		end

		-- Goldene Waben-Intarsie auf dem Bruecken-Vorplatz (R = 46.8 vom Plot-Zentrum)
		local medWorld = (plotCF * CFrame.new(0, 0.10, zSign * 46.8)).Position
		buildHexRingFlat(folder, "PlotForecourt_Hex", medWorld, 2.4, 0.38, 0.06, COL_GOLD, Enum.Material.Metal, math.atan2(outward.Z, outward.X))
		makeCylinder(folder, "PlotForecourt_HexCore", medWorld + Vector3.new(0, 0.01, 0), 1.4, 0.06, COL_HONEY_GLOW, Enum.Material.Neon, false, false)
	end

	-- 8c. Sandstein- & Schiefer-Uferkranz rund um die Plot-Insel (laesst Brueckenachsen bei 0 und pi frei)
	local baseAngle = math.atan2(outward.Z, outward.X)
	local gapAngle  = 0.145
	local rimR      = radius - 0.8
	for _, halfOffset in { 0, math.pi } do
		local aStart = baseAngle + halfOffset + gapAngle
		local aEnd   = baseAngle + halfOffset + math.pi - gapAngle
		local segs   = 8
		for sIdx = 1, segs do
			local a0    = aStart + (sIdx - 1) * (aEnd - aStart) / segs
			local a1    = aStart + sIdx * (aEnd - aStart) / segs
			local aMid  = (a0 + a1) * 0.5
			local dir   = Vector3.new(math.cos(aMid), 0, math.sin(aMid))
			local chord = 2 * rimR * math.sin((a1 - a0) * 0.5) + 0.35
			local rCos  = rimR * math.cos((a1 - a0) * 0.5)
			local segPos = Vector3.new(cx, baseY, cz) + dir * rCos
			local segCF  = CFrame.lookAt(segPos, segPos + dir)

			makePart(folder, "PlotRim_Cliff", Vector3.new(chord + 0.3, 1.75, 1.25), segCF * CFrame.new(0, -0.52, 0.45), COL_CREAM_STONE, Enum.Material.Sandstone)
			makePart(folder, "PlotRim_Slate", Vector3.new(chord + 0.15, 0.34, 1.18), segCF * CFrame.new(0, 0.40, 0.25), COL_DARK_SLATE, Enum.Material.Slate)
			makePart(folder, "PlotRim_Gold", Vector3.new(chord + 0.2, 0.12, 0.38), segCF * CFrame.new(0, 0.60, 0.25), COL_GOLD, Enum.Material.Metal)
			makePart(folder, "PlotRim_InnerCurb", Vector3.new(chord, 0.20, 1.25), segCF * CFrame.new(0, 0.10, -0.75), COL_CREAM_LIGHT, Enum.Material.Sandstone)
		end
	end
end

return HubPlazaBuilder
