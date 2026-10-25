-- rocket_island.test.lua — P4 (20.10.2026)
-- python tools/luau-tests/run_local.py tools/luau-tests/rocket_island.test.lua

local Rules  = require(RS.Modules.RocketIslandRules)
local Cfg    = require(RS.Config.RocketIslandConfig)
local MapConfig = require(RS.Config.MapConfig)
local MapStyleRules = require(RS.Modules.MapStyleRules)

local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else
		failures += 1
		print("FAIL " .. name .. (if detail ~= nil then ": " .. tostring(detail) else ""))
	end
end

-- Zustaende
check("gesperrt ohne Epilog", Rules.state({ epilog = { state = "none" }, towers = { records = { Final = 40 } } }) == 1)
check("gesperrt ohne Felder", Rules.state({}) == 1)
check("bereit bei pending", Rules.state({ epilog = { state = "pending" } }) == 2)
check("bereit bei seen", Rules.state({ epilog = { state = "seen" } }) == 2)
check("bereit bei Final-Rekord 100", Rules.state({ towers = { records = { Final = 100 } } }) == 2)
check("gestartet bei launched", Rules.state({ epilog = { state = "launched" }, towers = { records = { Final = 100 } } }) == 3)
check("Fortschritt Final-Rekord", Rules.finalRecord({ towers = { records = { Final = 37 } } }) == 37)

-- Lage je Slot (W1-P2): auf der Plot-Achse HINTER der Arena-Insel (Fight-Pit)
local arenaEdge = MapConfig.PLOT_RING_RADIUS + MapConfig.PLOT_ISLAND_RADIUS + MapConfig.ISLAND_GAP + 2 * MapConfig.PIT_BASE_RADIUS
local seen = {}
for slot = 1, MapConfig.PLOT_COUNT do
	local L = Rules.layout(slot, nil)
	local a = math.rad((slot - 1) * (360 / MapConfig.PLOT_COUNT))
	local dx, dz = L.center.X - MapConfig.CENTER.X, L.center.Z - MapConfig.CENTER.Z
	check("Slot " .. slot .. ": Platzhalter markiert", L.placeholder == true)
	check("Slot " .. slot .. ": auf der Plot-Achse", math.abs(dx * math.sin(a) - dz * math.cos(a)) < 1e-6)
	check("Slot " .. slot .. ": hinter dem Fight-Pit", L.distance - Cfg.ISLAND_RADIUS >= arenaEdge + 1, L.distance)
	check("Slot " .. slot .. ": Bruecke ueberspannt die Luecke", math.abs((L.toRadius - L.fromRadius) - Cfg.GAP_FROM_ARENA) < 1e-6, L.toRadius - L.fromRadius)
	check("Slot " .. slot .. ": im Wasserkreis", L.distance + Cfg.ISLAND_RADIUS + 8 < MapConfig.WATER_RADIUS, L.distance)
	local clear = Rules.clearanceToIslands(L.center, slot)
	check("Slot " .. slot .. ": frei von anderen Inseln", clear > 0, clear)
	local key = string.format("%.1f/%.1f", L.center.X, L.center.Z)
	check("Slot " .. slot .. ": eigene Lage", not seen[key])
	seen[key] = true
end
check("Reihenfolge Plot -> Pit -> Rakete", Rules.layout(1, nil).fromRadius > MapConfig.PLOT_RING_RADIUS + MapConfig.PLOT_ISLAND_RADIUS)

-- Anker: behaelt Richtung, wird hinter dem Pit geklemmt
local near = Rules.layout(1, Vector3.new(30, 5, 0))
check("zu naher Anker wird hinter das Pit geklemmt", near.distance >= arenaEdge + Cfg.MIN_GAP_FROM_MAIN + Cfg.ISLAND_RADIUS)
check("Anker behaelt Richtung", math.abs(near.outward.X - 1) < 1e-6)
check("Anker im Zentrum -> Plot-Achse", Rules.layout(1, Vector3.new(MapConfig.CENTER.X, 0, MapConfig.CENTER.Z)).placeholder == false)
local far = Rules.layout(1, Vector3.new(MapConfig.CENTER.X + 500, 0, MapConfig.CENTER.Z))
check("Anker weit weg bleibt unveraendert", math.abs(far.distance - 500) < 1e-6 and not far.placeholder)

-- Teile-Budget: Boden-Raster der Mini-Insel
local cells = MapStyleRules.groundCells(Cfg.ISLAND_RADIUS, Cfg.GROUND_LEVELS, Cfg.GROUND_MARGIN)
check("Boden-Raster Mini-Insel <= 20 Bloecke", #cells > 0 and #cells <= 20, #cells)

if failures > 0 then error("rocket_island: " .. failures .. " Fehler") end
print("rocket_island: alle Tests gruen")
