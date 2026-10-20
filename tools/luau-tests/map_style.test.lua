-- map_style.test.lua — Map-Stil V2 (20.10.2026)
-- python tools/luau-tests/run_local.py tools/luau-tests/map_style.test.lua
--
-- Prueft die reinen Regeln und die Konfiguration (ohne Roblox-Instanzen):
-- 1. Variantenwahl ist deterministisch und deckt alle Varianten ab.
-- 2. Jede Vorlage in der Config hat eine Dreieckszahl und liegt im Budget des Auftrags.
-- 3. Der Schalter MAP_STYLE_V2 existiert und ist bis zur Abnahme AUS.
-- 4. Skalierung, Mittelpunkt-Versatz und Variantenlisten sind schluessig.
-- Was hier nicht geprueft wird: das Aussehen und das Klonen der Vorlagen (Studio).

local MapStyleConfig = rbxRequire("ReplicatedStorage/Config/MapStyleConfig")
local MapStyleRules  = rbxRequire("ReplicatedStorage/Modules/MapStyleRules")
local FeatureFlags   = rbxRequire("ReplicatedStorage/Config/FeatureFlags")

local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else
		failures += 1
		print("FAIL " .. name .. (if detail then ": " .. tostring(detail) else ""))
	end
end

-- 1. Varianten
local seen = {}
for i = 0, 30 do for j = 0, 30 do seen[MapStyleRules.tileVariant(i, j, 2)] = true end end
check("tileVariant deckt beide Kacheln ab", seen[1] and seen[2])
check("tileVariant deterministisch", MapStyleRules.tileVariant(5, 9, 2) == MapStyleRules.tileVariant(5, 9, 2))
local neg = MapStyleRules.tileVariant(-3, -7, 2)
check("tileVariant mit negativem Raster im Bereich", neg >= 1 and neg <= 2, neg)
check("pick r=0 -> erstes", MapStyleRules.pick({ "a", "b", "c" }, 0) == "a")
check("pick r=0.999 -> letztes", MapStyleRules.pick({ "a", "b", "c" }, 0.999) == "c")
check("pick r=1 bleibt im Bereich", MapStyleRules.pick({ "a", "b", "c" }, 1) == "c")

-- 2. Budgets
local function budgetOf(name)
	if name:find("Wiese") then return MapStyleConfig.BUDGET.tile end
	if name:find("RimBusch") then return MapStyleConfig.BUDGET.rimBush end
	if name:find("Busch") then return MapStyleConfig.BUDGET.bush end
	if name:find("Baum") then return MapStyleConfig.BUDGET.tree end
	return MapStyleConfig.BUDGET.tile
end
local allListed = {}
for _, list in { MapStyleConfig.GROUND_TILES, MapStyleConfig.TREES, MapStyleConfig.BUSHES,
	MapStyleConfig.RIM_BUSHES, MapStyleConfig.ROCKS, MapStyleConfig.CRYSTALS } do
	for _, name in list do table.insert(allListed, name) end
end
for _, name in allListed do
	local tris = MapStyleConfig.TRIS[name]
	check(name .. " hat Dreieckszahl", tris ~= nil)
	check(name .. " im Budget", tris ~= nil and MapStyleRules.withinBudget(tris, budgetOf(name)), tris)
	check(name .. " hat Boxhoehe (MESH_Z)", MapStyleConfig.MESH_Z[name] ~= nil)
end
check("Varianten: 4 Baeume", #MapStyleConfig.TREES == 4)
check("Varianten: 5 Buesche", #MapStyleConfig.BUSHES == 5)
check("Varianten: 2 Rand-Buesche", #MapStyleConfig.RIM_BUSHES == 2)

-- 3. Schalter
check("Schalter MAP_STYLE_V2 vorhanden", FeatureFlags.FLAGS.MAP_STYLE_V2 ~= nil)
check("Schalter MAP_STYLE_V2 ist nach der Abnahme AN", FeatureFlags.FLAGS.MAP_STYLE_V2 == true)
check("Skalierung +-12 %", MapStyleConfig.SCALE_MIN == 0.88 and MapStyleConfig.SCALE_MAX == 1.12)

-- 4. Rechenregeln
check("scaleForWidth 6 -> 3 = 0.5", math.abs(MapStyleRules.scaleForWidth(3, 6) - 0.5) < 1e-9)
check("scaleForWidth schuetzt vor 0", MapStyleRules.scaleForWidth(3, 0) == 1)
check("centerOffsetY Baum (0..16, Hoehe 16) = 8", math.abs(MapStyleRules.centerOffsetY(0, 16, 16) - 8) < 1e-9)
check("centerOffsetY Busch (-0.5..3, Hoehe 3.5)", math.abs(MapStyleRules.centerOffsetY(-0.5, 3, 3.5) - 1.25) < 1e-9)
check("centerOffsetY im Massstab 2", math.abs(MapStyleRules.centerOffsetY(0, 4, 8) - 4) < 1e-9)

print(failures == 0 and "ALLE OK" or ("FEHLER: " .. failures))

-- 5. Old-School-Boden (P1)
local G = MapStyleConfig.GROUND
local cells = MapStyleRules.groundCells(120, G.LEVELS, G.MARGIN)
check("Bodenraster im Teile-Budget", #cells > 0 and #cells <= G.MAX_PARTS, #cells)
local allInside, area = true, 0
for _, c in cells do
	local h = c.size * 0.5
	for _, d in { { -h, -h }, { h, -h }, { -h, h }, { h, h } } do
		local x, z = c.x + d[1], c.z + d[2]
		if x * x + z * z > (120 - G.MARGIN) ^ 2 + 1e-6 then allInside = false end
	end
	area += c.size * c.size
end
check("alle Bodenbloecke liegen im Kreis", allInside)
check("Bodenraster deckt >= 80 % der Insel", area / (math.pi * 120 * 120) >= 0.8, area / (math.pi * 120 * 120))
check("Flag MAP_GROUND_OLDSCHOOL existiert", FeatureFlags.FLAGS.MAP_GROUND_OLDSCHOOL ~= nil)
check("Moderne Textur bleibt als Option", MapStyleConfig.STUD_GROUND.MODERN == false)

if failures > 0 then error("map_style: " .. failures .. " Fehler") end
