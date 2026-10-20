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

-- Platzhalter-Lage
local L = Rules.layout(nil)
check("Platzhalter markiert", L.placeholder == true)
check("Bruecke ueberspannt >= Mindestluecke", L.toRadius - L.fromRadius >= Cfg.MIN_GAP_FROM_MAIN, L.toRadius - L.fromRadius)
check("Platzhalter frei von Plot-Inseln", Rules.clearanceToPlots(L.center) > 0, Rules.clearanceToPlots(L.center))
check("Platzhalter im Wasserkreis", L.distance + Cfg.ISLAND_RADIUS + 8 < MapConfig.WATER_RADIUS)

-- Anker: zu nah wird geklemmt, Richtung bleibt
local near = Rules.layout(Vector3.new(30, 5, 0))
check("zu naher Anker wird geklemmt", near.distance >= MapConfig.PLATFORM_RADIUS + Cfg.MIN_GAP_FROM_MAIN + Cfg.ISLAND_RADIUS)
check("Anker behaelt Richtung", math.abs(near.outward.X - 1) < 1e-6)
check("Anker im Zentrum -> Sicherheitsrichtung", Rules.layout(Vector3.new(0, 0, 0)).outward.X == 1)
local far = Rules.layout(Vector3.new(0, 0, 200))
check("Anker weit weg bleibt unveraendert", math.abs(far.distance - 200) < 1e-6 and not far.placeholder)

-- Teile-Budget: Boden-Raster der Mini-Insel
local cells = MapStyleRules.groundCells(Cfg.ISLAND_RADIUS, Cfg.GROUND_LEVELS, Cfg.GROUND_MARGIN)
check("Boden-Raster Mini-Insel <= 20 Bloecke", #cells > 0 and #cells <= 20, #cells)

if failures > 0 then error("rocket_island: " .. failures .. " Fehler") end
print("rocket_island: alle Tests gruen")
