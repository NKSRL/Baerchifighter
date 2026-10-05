--!strict
-- ScenicBuilder.luau
-- ServerScriptService/Util/MapBuild/ScenicBuilder.luau
--
-- Einzige Zustaendigkeit:
--   - Die feste Landschafts-Deko der Welt: Meeresboden, Schaumsaeume, Wege,
--     Laternen, Stegpfosten, Baeume, Buesche, Felsen, Pilze, Plot-Randdeko
--
-- Wird nur von WorldBuilder.buildPlatform aufgerufen, einmal beim Serverstart.
-- Alles landet in einem Ordner "Scenery" unter dem Platform-Model.
--
-- PERFORMANCE-REGELN, die hier fuer jede Part gelten:
--   * Anchored, CanCollide/CanQuery/CanTouch aus, CastShadow aus. Deko ist
--     reine Silhouette; nichts davon darf Physik, Klick-Raycasts oder
--     Schattenberechnung kosten.
--   * Einfache Formen (Ball, Zylinder, Block), keine MeshParts, keine Lichter.
--     "Leuchten" macht Neon + Bloom.
--   * Deterministischer Zufall (AmbienceConfig.SCENERY_SEED): jeder Server
--     baut dieselbe Welt, und es gibt keinen Netzwerk-Mehraufwand durch
--     staendig wechselnde Instanzen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AmbienceConfig = require(ReplicatedStorage.Config.AmbienceConfig)
local EggConfig      = require(ReplicatedStorage.Config.EggConfig)
local MapConfig      = require(ReplicatedStorage.Config.MapConfig)

local MapParts = require(ServerScriptService.Util.MapBuild.MapParts)

local ScenicBuilder = {}

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))   -- Zylinder liegen von Haus aus entlang X

type Placed = { x: number, z: number, r: number }

-- Eine Deko-Part mit allen Performance-Schaltern aus.
local function decorPart(
	name: string,
	parent: Instance,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?
): Part
	local part = MapParts.newPart(name, size, cframe, color, material)
	part.Shape      = shape or Enum.PartType.Block
	part.CanCollide = false
	part.CanQuery   = false
	part.CanTouch   = false
	part.CastShadow = false
	part.Parent     = parent
	return part
end

-- Ein senkrecht stehender Zylinder: `height` ist seine Hoehe, `diameter` die Breite.
local function pole(name: string, parent: Instance, baseX: number, baseY: number, baseZ: number, height: number, diameter: number, color: Color3, material: Enum.Material): Part
	return decorPart(
		name, parent,
		Vector3.new(height, diameter, diameter),
		CFrame.new(baseX, baseY + height * 0.5, baseZ) * UPRIGHT,
		color, material, Enum.PartType.Cylinder
	)
end

local function ball(name: string, parent: Instance, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	return decorPart(name, parent, size, cframe, color, material, Enum.PartType.Ball)
end

--------------------------------------------------------------------------------
-- Meeresboden und Schaum
--------------------------------------------------------------------------------

local function buildSeabed(parent: Instance)
	local radius = AmbienceConfig.SEABED_RADIUS
	local seabed = decorPart(
		"Seabed", parent,
		Vector3.new(2, radius * 2, radius * 2),
		CFrame.new(MapConfig.CENTER.X, AmbienceConfig.SEABED_Y, MapConfig.CENTER.Z) * UPRIGHT,
		AmbienceConfig.SEABED_COLOR,
		Enum.Material.Sand,
		Enum.PartType.Cylinder
	)
	seabed.Name = "Seabed"
end

-- Eine Schaumscheibe pro Insel. Sie liegt knapp ueber der Wasseroberflaeche und
-- unter der Sandkante: sichtbar ist nur der Rand, der ueber den Sand hinausragt.
local function buildFoam(parent: Instance, name: string, center: Vector3, islandRadius: number, phase: number)
	local radius = islandRadius + MapConfig.SHORE_WIDTH + AmbienceConfig.FOAM_REACH
	local y = MapConfig.PLATFORM_TOP_Y - MapConfig.WATER_DROP + 0.05

	local foam = decorPart(
		name, parent,
		Vector3.new(0.1, radius * 2, radius * 2),
		CFrame.new(center.X, y, center.Z) * UPRIGHT,
		AmbienceConfig.FOAM_COLOR,
		Enum.Material.SmoothPlastic,
		Enum.PartType.Cylinder
	)
	foam.Transparency = AmbienceConfig.FOAM_TRANSPARENCY
	-- Phase fuer den Client: jede Insel atmet versetzt, sonst pulsiert alles gleichzeitig.
	foam:SetAttribute("FoamPhase", phase)
end

--------------------------------------------------------------------------------
-- Streuung
--------------------------------------------------------------------------------

local function isFree(placed: { Placed }, x: number, z: number, r: number): boolean
	for _, other in placed do
		local dx = x - other.x
		local dz = z - other.z
		local minDist = r + other.r
		if dx * dx + dz * dz < minDist * minDist then
			return false
		end
	end
	return true
end

--------------------------------------------------------------------------------
-- Wege, Laternen, Stegpfosten
--------------------------------------------------------------------------------

local function buildPaths(parent: Instance)
	local fromRadius = MapConfig.EVENT_PIT_RADIUS - 1
	local toRadius   = MapConfig.PLATFORM_RADIUS - 4
	local length     = toRadius - fromRadius
	local y          = MapConfig.PLATFORM_TOP_Y + AmbienceConfig.PATH_LIFT

	for slot = 1, MapConfig.PLOT_COUNT do
		local outward = MapParts.outwardDirection(slot)
		local mid     = MapConfig.CENTER + outward * ((fromRadius + toRadius) * 0.5)
		local at      = Vector3.new(mid.X, y, mid.Z)

		decorPart(
			"Path_" .. slot, parent,
			Vector3.new(AmbienceConfig.PATH_WIDTH, 0.1, length),
			CFrame.lookAt(at, at + outward),
			AmbienceConfig.PATH_COLOR,
			Enum.Material.Cobblestone
		)
	end
end

local function buildLamps(parent: Instance, placed: { Placed })
	for slot = 1, MapConfig.PLOT_COUNT do
		local outward = MapParts.outwardDirection(slot)
		local side    = Vector3.new(-outward.Z, 0, outward.X)

		for _, radius in AmbienceConfig.LAMP_RADII do
			for _, sign in { -1, 1 } do
				local p = MapConfig.CENTER + outward * radius + side * (sign * AmbienceConfig.LAMP_SIDE)
				local baseY = MapConfig.PLATFORM_TOP_Y

				pole("LampPole", parent, p.X, baseY, p.Z, AmbienceConfig.LAMP_HEIGHT, 0.8,
					AmbienceConfig.LAMP_POLE_COLOR, Enum.Material.Wood)
				ball("LampGlow", parent, Vector3.new(2.2, 2.2, 2.2),
					CFrame.new(p.X, baseY + AmbienceConfig.LAMP_HEIGHT + 0.7, p.Z),
					AmbienceConfig.LAMP_GLOW_COLOR, Enum.Material.Neon)

				table.insert(placed, { x = p.X, z = p.Z, r = 2 })
			end
		end
	end
end

-- Pfosten mit Leuchtkappe an beiden Enden jedes inneren Stegs (Hauptinsel → Plot).
local function buildBridgePosts(parent: Instance)
	local deckTop = MapConfig.PLATFORM_TOP_Y - MapConfig.BRIDGE_SINK
	local sideOffset = (MapConfig.BRIDGE_WIDTH + MapConfig.BRIDGE_RAIL_WIDTH) * 0.5

	local fromRadius = MapConfig.PLATFORM_RADIUS
	local toRadius   = MapConfig.PLOT_RING_RADIUS - MapConfig.PLOT_ISLAND_RADIUS
	local inset      = AmbienceConfig.BRIDGE_POST_INSET

	for slot = 1, MapConfig.PLOT_COUNT do
		local outward = MapParts.outwardDirection(slot)
		local side    = Vector3.new(-outward.Z, 0, outward.X)

		for _, radius in { fromRadius + inset, toRadius - inset } do
			for _, sign in { -1, 1 } do
				local p = MapConfig.CENTER + outward * radius + side * (sign * sideOffset)

				pole("BridgePost", parent, p.X, deckTop, p.Z, AmbienceConfig.BRIDGE_POST_HEIGHT, 1.3,
					MapConfig.BRIDGE_RAIL_COLOR, Enum.Material.Wood)
				ball("BridgeCap", parent, Vector3.new(1.9, 1.9, 1.9),
					CFrame.new(p.X, deckTop + AmbienceConfig.BRIDGE_POST_HEIGHT + 0.5, p.Z),
					AmbienceConfig.LAMP_GLOW_COLOR, Enum.Material.Neon)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Hauptinsel: Baeume, Buesche, Felsen, Pilze
--------------------------------------------------------------------------------

local function buildMainIslandScenery(parent: Instance, placed: { Placed }, isOnLane: (Vector3, number) -> boolean)
	local random = Random.new(AmbienceConfig.SCENERY_SEED)

	-- Der versteckte Ei-Haendler bleibt frei, sonst steht er mitten im Busch.
	local merchant = EggConfig.MERCHANT
	local merchantAngle = math.rad(merchant.angleDegrees)
	table.insert(placed, {
		x = MapConfig.CENTER.X + merchant.radius * math.cos(merchantAngle),
		z = MapConfig.CENTER.Z + merchant.radius * math.sin(merchantAngle),
		r = AmbienceConfig.MERCHANT_CLEAR,
	})

	local y = MapConfig.PLATFORM_TOP_Y

	-- Findet einen freien Platz auf dem Ring; nil, wenn nach 40 Versuchen keiner da ist.
	local function findSpot(footprint: number): (number?, number?)
		for _ = 1, 40 do
			local angle  = random:NextNumber(0, math.pi * 2)
			local radius = random:NextNumber(AmbienceConfig.SCENERY_INNER, AmbienceConfig.SCENERY_OUTER)
			local x = MapConfig.CENTER.X + radius * math.cos(angle)
			local z = MapConfig.CENTER.Z + radius * math.sin(angle)

			if not isOnLane(Vector3.new(x, y, z), AmbienceConfig.LANE_MARGIN)
				and isFree(placed, x, z, footprint) then
				table.insert(placed, { x = x, z = z, r = footprint })
				return x, z
			end
		end
		return nil, nil
	end

	-- Baeume: Stamm + zwei uebereinander gesetzte Kronen-Baelle.
	for i = 1, AmbienceConfig.TREE_COUNT do
		local x, z = findSpot(7)
		if x and z then
			local canopyColor = AmbienceConfig.TREE_CANOPY_COLORS[random:NextInteger(1, #AmbienceConfig.TREE_CANOPY_COLORS)]
			local scale = random:NextNumber(0.85, 1.25)
			local trunkHeight = 7 * scale

			pole("TreeTrunk", parent, x, y, z, trunkHeight, 1.8 * scale,
				AmbienceConfig.TREE_TRUNK_COLOR, Enum.Material.Wood)
			ball("TreeCrown", parent, Vector3.new(11, 9, 11) * scale,
				CFrame.new(x, y + trunkHeight + 2.5 * scale, z),
				canopyColor, Enum.Material.Grass)
			ball("TreeTop", parent, Vector3.new(7, 6, 7) * scale,
				CFrame.new(x, y + trunkHeight + 7 * scale, z),
				canopyColor, Enum.Material.Grass)
		end
	end

	-- Buesche: ein platter Ball.
	for i = 1, AmbienceConfig.BUSH_COUNT do
		local x, z = findSpot(3.5)
		if x and z then
			local size = random:NextNumber(4, 6.5)
			ball("Bush", parent, Vector3.new(size, size * 0.65, size),
				CFrame.new(x, y + size * 0.2, z) * CFrame.Angles(0, random:NextNumber(0, math.pi), 0),
				AmbienceConfig.BUSH_COLORS[random:NextInteger(1, #AmbienceConfig.BUSH_COLORS)],
				Enum.Material.Grass)
		end
	end

	-- Felsen: plattgedrueckte, verdrehte Baelle.
	for i = 1, AmbienceConfig.ROCK_COUNT do
		local x, z = findSpot(3.5)
		if x and z then
			local size = random:NextNumber(3, 6)
			ball("Rock", parent, Vector3.new(size, size * 0.6, size * random:NextNumber(0.7, 1.1)),
				CFrame.new(x, y + size * 0.12, z)
					* CFrame.Angles(random:NextNumber(-0.2, 0.2), random:NextNumber(0, math.pi * 2), random:NextNumber(-0.2, 0.2)),
				AmbienceConfig.ROCK_COLORS[random:NextInteger(1, #AmbienceConfig.ROCK_COLORS)],
				Enum.Material.Slate)
		end
	end

	-- Pilze: heller Stiel + roter Hut.
	for i = 1, AmbienceConfig.MUSHROOM_COUNT do
		local x, z = findSpot(2)
		if x and z then
			local scale = random:NextNumber(0.8, 1.5)
			pole("MushroomStem", parent, x, y, z, 2.2 * scale, 1.1 * scale,
				Color3.fromRGB(250, 240, 220), Enum.Material.SmoothPlastic)
			ball("MushroomCap", parent, Vector3.new(4, 2.4, 4) * scale,
				CFrame.new(x, y + 2.3 * scale, z),
				Color3.fromRGB(226, 76, 76), Enum.Material.SmoothPlastic)
		end
	end
end

--------------------------------------------------------------------------------
-- Plot-Inseln: Randdeko
--------------------------------------------------------------------------------

-- Felsen und Buesche in einem schmalen Ring am Inselrand, AUSSERHALB des Beets
-- und der Gebaeude. Die Stegachse (zur Mitte und zur Arena) bleibt frei.
local function buildPlotRims(parent: Instance)
	local random = Random.new(AmbienceConfig.SCENERY_SEED + 1)
	local y = MapConfig.PLATFORM_TOP_Y

	for slot = 1, MapConfig.PLOT_COUNT do
		local outward = MapParts.outwardDirection(slot)
		local perp    = Vector3.new(-outward.Z, 0, outward.X)
		local center  = MapConfig.CENTER + outward * MapConfig.PLOT_RING_RADIUS

		local placedCount = 0
		local attempts = 0
		while placedCount < AmbienceConfig.PLOT_RIM_COUNT and attempts < 60 do
			attempts += 1

			local angle  = random:NextNumber(0, math.pi * 2)
			local radius = random:NextNumber(AmbienceConfig.PLOT_RIM_MIN, AmbienceConfig.PLOT_RIM_MAX)
			local dx = radius * math.cos(angle)
			local dz = radius * math.sin(angle)

			-- Quer-Abstand zur Stegachse dieses Plots.
			local across = math.abs(dx * perp.X + dz * perp.Z)
			if across > AmbienceConfig.PLOT_RIM_LANE then
				local x = center.X + dx
				local z = center.Z + dz

				if placedCount % 2 == 0 then
					local size = random:NextNumber(2.4, 3.6)
					ball("RimRock", parent, Vector3.new(size, size * 0.6, size),
						CFrame.new(x, y + size * 0.1, z) * CFrame.Angles(0, random:NextNumber(0, math.pi), 0),
						AmbienceConfig.ROCK_COLORS[random:NextInteger(1, #AmbienceConfig.ROCK_COLORS)],
						Enum.Material.Slate)
				else
					local size = random:NextNumber(2.6, 3.8)
					ball("RimBush", parent, Vector3.new(size, size * 0.7, size),
						CFrame.new(x, y + size * 0.2, z),
						AmbienceConfig.BUSH_COLORS[random:NextInteger(1, #AmbienceConfig.BUSH_COLORS)],
						Enum.Material.Grass)
				end
				placedCount += 1
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Einstieg
--------------------------------------------------------------------------------

-- `isOnLane` kommt von WorldBuilder (isOnBridgeLane); als Parameter statt
-- require, damit die beiden Module sich nicht gegenseitig laden.
function ScenicBuilder.build(platform: Instance, isOnLane: (Vector3, number) -> boolean)
	if platform:FindFirstChild("Scenery") then
		return   -- schon gebaut
	end

	local folder = Instance.new("Folder")
	folder.Name = "Scenery"

	local placed: { Placed } = {}

	buildSeabed(folder)

	local foam = Instance.new("Folder")
	foam.Name = "Foam"
	foam.Parent = folder
	buildFoam(foam, "Foam_Main", MapConfig.CENTER, MapConfig.PLATFORM_RADIUS, 0)
	for slot = 1, MapConfig.PLOT_COUNT do
		local center = MapConfig.CENTER + MapParts.outwardDirection(slot) * MapConfig.PLOT_RING_RADIUS
		buildFoam(foam, "Foam_Plot" .. slot, center, MapConfig.PLOT_ISLAND_RADIUS, slot * 0.8)
	end

	buildPaths(folder)
	buildLamps(folder, placed)
	buildBridgePosts(folder)
	buildMainIslandScenery(folder, placed, isOnLane)
	buildPlotRims(folder)

	folder.Parent = platform
end

return ScenicBuilder
