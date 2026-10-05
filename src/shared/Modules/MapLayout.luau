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
			table.insert(boards, { listId = b.listId :: string?, angleDegrees = b.angleDegrees })
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

return MapLayout
