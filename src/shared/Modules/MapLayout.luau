--!strict
-- MapLayout.luau
-- ReplicatedStorage/Modules/MapLayout.luau
--
-- Einzige Zustaendigkeit:
--   - WO die festen Wahrzeichen der Welt stehen (HBB Paket 5/6): Bestenlisten-
--     Tafeln, Live-Kampf-Board, Schau-Tuerme, Wespen-Nest, Ei-Haendler.
--     Reine Rechnung aus MapConfig/EggConfig, baut nichts.
--
-- Warum ein eigenes Modul: Dieselben Positionen brauchen drei Stellen — die
-- Builder (bauen), ScenicBuilder (haelt Baeume/Buesche fern) und der Test
-- tools/luau-tests/map_layout.test.lua (prueft Abstaende zu Stegen, Laternen
-- und untereinander). Stuende die Formel dreimal da, liefe sie auseinander.
--
-- Winkel wie MapParts.buildPlotCFrame: Slot 1 liegt bei 0 Grad (+X), jeder
-- weitere 360/PLOT_COUNT Grad weiter Richtung +Z. Zwischen zwei Stegen liegt
-- eine "Luecke" bei 22,5 + k x 45 Grad.

local Config = script.Parent.Parent.Config
local MapConfig    = require(Config.MapConfig)
local EggConfig    = require(Config.EggConfig)
local FeatureFlags = require(Config.FeatureFlags)

local MapLayout = {}

-- Ein Wahrzeichen als Kreis auf der Wiese (fuer Abstandspruefungen).
export type Landmark = { name: string, x: number, z: number, r: number }

--------------------------------------------------------------------------------
-- Richtungen
--------------------------------------------------------------------------------

function MapLayout.slotAngle(slot: number): number
	return math.rad((slot - 1) * (360 / MapConfig.PLOT_COUNT))
end

-- Einheitsvektor von der Weltmitte zum Plot `slot` (= Richtung seines Stegs).
function MapLayout.outward(slot: number): Vector3
	local angle = MapLayout.slotAngle(slot)
	return Vector3.new(math.cos(angle), 0, math.sin(angle))
end

-- Quer zum Steg, zum naechsten Slot hin (wie die Laternen in ScenicBuilder).
function MapLayout.side(slot: number): Vector3
	local o = MapLayout.outward(slot)
	return Vector3.new(-o.Z, 0, o.X)
end

-- Punkt auf der Wiese bei `angleDegrees` und `radius` (Hoehe PLATFORM_TOP_Y).
function MapLayout.atAngle(angleDegrees: number, radius: number): Vector3
	local angle = math.rad(angleDegrees)
	return Vector3.new(
		MapConfig.CENTER.X + radius * math.cos(angle),
		MapConfig.PLATFORM_TOP_Y,
		MapConfig.CENTER.Z + radius * math.sin(angle)
	)
end

--------------------------------------------------------------------------------
-- Honig-Teich und Baerchi-Platz auf dem Plot (plot-lokal, siehe MapConfig-Kopf)
--------------------------------------------------------------------------------
-- HONEY_POND_V2: der Teich steht dort, wo das Gebaeude HoneyPond steht (Mitte
-- des hinteren Plot-Teils), sein Standplatz zeigt nach +Z (ins Plot hinein),
-- und der Baerchi WOHNT auf diesem Standplatz — er frisst ohne hinzulaufen.
-- Ohne Schalter: alter Teich (POND_OFFSET) und alter Baerchi-Platz.

local function pondV2(): boolean
	return FeatureFlags.isOn("HONEY_POND_V2")
end

function MapLayout.pondOffset(): Vector3
	return if pondV2() then MapConfig.BUILDING_OFFSETS.HoneyPond.offset else MapConfig.POND_OFFSET
end

-- Richtung (plot-lokal, waagerecht, Einheitsvektor) vom Teich zum Standplatz.
function MapLayout.pondFacing(): Vector3
	if pondV2() then
		return Vector3.new(0, 0, 1)
	end
	local toHome = MapConfig.BAERCHI_HOME_OFFSET - MapConfig.POND_OFFSET
	local flat = Vector3.new(toHome.X, 0, toHome.Z)
	return if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, 1)
end

-- Abstand Teich-Mitte -> Standplatz (Beckenrand + Luecke).
function MapLayout.pondStandDistance(): number
	return MapConfig.POND_RADIUS + MapConfig.POND_STAND_GAP
end

-- Wo der ausgeruestete Baerchi steht, wenn er nichts tut.
function MapLayout.baerchiHomeOffset(): Vector3
	if pondV2() then
		return MapLayout.pondOffset() + MapLayout.pondFacing() * MapLayout.pondStandDistance()
	end
	return MapConfig.BAERCHI_HOME_OFFSET
end

--------------------------------------------------------------------------------
-- Wahrzeichen
--------------------------------------------------------------------------------

-- Fuss des Schau-Turms von `slot` (Mitte, PLATFORM_TOP_Y).
-- MAP_V2_SHOWCASE: am Brueckenkopf auf der Hauptinsel; sonst wie v15 aussen
-- an der Arena-Insel (gleiche Formel wie MapParts.pitCenter + distance).
function MapLayout.showcaseFoot(slot: number): Vector3
	local cfg = MapConfig.TOWER_SHOWCASE
	local outward = MapLayout.outward(slot)
	local flat: Vector3
	if FeatureFlags.isOn("MAP_V2_SHOWCASE") then
		flat = MapConfig.CENTER + outward * cfg.bridgeheadAlong + MapLayout.side(slot) * cfg.bridgeheadAcross
	else
		local pitRadius = MapConfig.PLOT_RING_RADIUS + MapConfig.PLOT_ISLAND_RADIUS
			+ MapConfig.ISLAND_GAP + MapConfig.PIT_BASE_RADIUS
		flat = MapConfig.CENTER + outward * (pitRadius + cfg.distance)
	end
	return Vector3.new(flat.X, MapConfig.PLATFORM_TOP_Y, flat.Z)
end

-- Die Bestenlisten-Tafeln: je Tafel Liste (nil = wechselnd, alter Weg) und Winkel.
function MapLayout.leaderboardBoards(): { { listId: string?, angleDegrees: number } }
	if FeatureFlags.isOn("MAP_V2_BOARDS") then
		local boards = {}
		for _, b in MapConfig.LEADERBOARD_BOARDS_V2 do
			if b.flag == nil or FeatureFlags.isOn(b.flag) then
				table.insert(boards, { listId = b.listId :: string?, angleDegrees = b.angleDegrees })
			end
		end
		return boards
	end
	return { { listId = nil, angleDegrees = MapConfig.LEADERBOARD_BOARD.angleDegrees } }
end

-- Mitte des Wespen-Nests (Weltkoordinaten).
function MapLayout.waspNestCenter(): Vector3
	return MapConfig.CENTER + Vector3.new(0, MapConfig.PLATFORM_TOP_Y, 0) + MapConfig.WASP_NEST.offset
end

-- Alle Wahrzeichen auf der Wiese der Hauptinsel, die gerade gebaut werden.
-- `r` = Radius des Kreises, der den Grundriss sicher umschliesst.
function MapLayout.landmarks(): { Landmark }
	local list: { Landmark } = {}
	local function add(name: string, p: Vector3, r: number)
		table.insert(list, { name = name, x = p.X, z = p.Z, r = r })
	end

	local board = MapConfig.LEADERBOARD_BOARD
	for i, b in MapLayout.leaderboardBoards() do
		add("Bestenliste" .. i, MapLayout.atAngle(b.angleDegrees, board.radius), board.size.X * 0.5 + 0.5)
	end

	if FeatureFlags.isOn("MAP_V2_LIVE_BOARD") then
		local live = MapConfig.LIVE_BOARD
		add("LiveBoard", MapLayout.atAngle(live.angleDegrees, live.radius), live.size.X * 0.5 + 0.5)
	end

	if FeatureFlags.isOn("MAP_V2_MERCHANT") then
		local m = EggConfig.MERCHANT_V2
		add("Haendler", MapLayout.atAngle(m.angleDegrees, m.radius), 6)
	end

	if FeatureFlags.isOn("MAP_V2_SHOWCASE") then
		-- Sockel: Turmradius + 1,2 (ArenaBuilder.buildShowcase), Dach bis 5
		local r = math.max(MapConfig.TOWER_SHOWCASE.radius + 1.2, 5) + 0.5
		for slot = 1, MapConfig.PLOT_COUNT do
			add("SchauTurm" .. slot, MapLayout.showcaseFoot(slot), r)
		end
	end

	return list
end

--------------------------------------------------------------------------------
-- Welt aufwerten (08.10.2026): Inselmitten, offenes Wasser, Wegweiser, Bojen
--------------------------------------------------------------------------------
-- Gebraucht von den Client-Controllern (Water/Hub/DayCycle) und von
-- map_layout.test.lua. Gleiche Formeln wie MapParts (Server), hier ohne
-- Server-Abhaengigkeit.

-- Mitte der Plot-Insel `slot` (PLATFORM_TOP_Y).
function MapLayout.plotCenter(slot: number): Vector3
	local flat = MapConfig.CENTER + MapLayout.outward(slot) * MapConfig.PLOT_RING_RADIUS
	return Vector3.new(flat.X, MapConfig.PLATFORM_TOP_Y, flat.Z)
end

-- Abstand der Arena-Mitte zur Weltmitte (wie MapParts.pitCenter).
function MapLayout.pitRadius(): number
	return MapConfig.PLOT_RING_RADIUS + MapConfig.PLOT_ISLAND_RADIUS
		+ MapConfig.ISLAND_GAP + MapConfig.PIT_BASE_RADIUS
end

-- Mitte der Arena-Insel `slot` (PLATFORM_TOP_Y).
function MapLayout.pitCenter(slot: number): Vector3
	local flat = MapConfig.CENTER + MapLayout.outward(slot) * MapLayout.pitRadius()
	return Vector3.new(flat.X, MapConfig.PLATFORM_TOP_Y, flat.Z)
end

-- Liegt (x, z) auf offenem Wasser, mit `margin` Studs Abstand zu jeder
-- Sandkante und jedem Steg? Arena-Inseln und aeussere Stege zaehlen immer als
-- Land (es koennte ein Spieler kommen). Fuer Fisch und Gluehwuermchen.
function MapLayout.isOpenWater(x: number, z: number, margin: number): boolean
	local dx, dz = x - MapConfig.CENTER.X, z - MapConfig.CENTER.Z
	local r = math.sqrt(dx * dx + dz * dz)
	if r > MapConfig.WATER_RADIUS - margin then
		return false
	end
	local shore = MapConfig.SHORE_WIDTH + margin
	if r < MapConfig.PLATFORM_RADIUS + shore then
		return false
	end
	local laneHalf = MapConfig.BRIDGE_WIDTH * 0.5 + margin
	local pitR = MapLayout.pitRadius()
	for slot = 1, MapConfig.PLOT_COUNT do
		local o = MapLayout.outward(slot)
		local along = dx * o.X + dz * o.Z
		local across = math.abs(dx * o.Z - dz * o.X)
		if along > 0 and along < pitR and across <= laneHalf then
			return false
		end
		local plot = MapLayout.plotCenter(slot)
		if math.sqrt((x - plot.X) ^ 2 + (z - plot.Z) ^ 2) < MapConfig.PLOT_ISLAND_RADIUS + shore then
			return false
		end
		local pit = MapLayout.pitCenter(slot)
		if math.sqrt((x - pit.X) ^ 2 + (z - pit.Z) ^ 2) < MapConfig.PIT_BASE_RADIUS + shore then
			return false
		end
	end
	return true
end

-- Wegweiser: einer je Steg, neben dem Pflasterweg, wo er am Event-Pit
-- beginnt. `facing` = Richtung nach aussen (zum Plot).
function MapLayout.signposts(radius: number, sideOffset: number): { { slot: number, position: Vector3, outward: Vector3 } }
	local list = {}
	for slot = 1, MapConfig.PLOT_COUNT do
		local o = MapLayout.outward(slot)
		local flat = MapConfig.CENTER + o * radius + MapLayout.side(slot) * sideOffset
		table.insert(list, { slot = slot, position = Vector3.new(flat.X, MapConfig.PLATFORM_TOP_Y, flat.Z), outward = o })
	end
	return list
end

-- Bojen: je eine in der Luecke zwischen zwei Stegen, weit draussen.
function MapLayout.buoys(radius: number): { Vector3 }
	local list = {}
	for slot = 1, MapConfig.PLOT_COUNT do
		local angle = (slot - 1) * (360 / MapConfig.PLOT_COUNT) + 180 / MapConfig.PLOT_COUNT
		local p = MapLayout.atAngle(angle, radius)
		table.insert(list, Vector3.new(p.X, MapConfig.PLATFORM_TOP_Y - MapConfig.WATER_DROP, p.Z))
	end
	return list
end

return MapLayout
