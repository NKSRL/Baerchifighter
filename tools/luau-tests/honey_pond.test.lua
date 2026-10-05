-- honey_pond.test.lua — Honig-Teich statt Stock + Veredler (HONEY_POND_V2)
-- python tools/luau-tests/run_local.py tools/luau-tests/honey_pond.test.lua
--
-- 1. Modules/HoneyPondMode: Umstieg, Rueckweg, Idempotenz, nichts geht verloren.
-- 2. BuildingBehavior: der Teich auf Level L leistet so viel wie Stock UND
--    Veredler auf Level L (Honig pro Minute, Lager, XP, Heilung) — kein
--    Spieler faellt durch den Umstieg zurueck.

local HoneyPondMode    = rbxRequire("ReplicatedStorage/Modules/HoneyPondMode")
local BuildingBehavior = rbxRequire("ReplicatedStorage/Config/BuildingBehavior")
local Types            = rbxRequire("ReplicatedStorage/Network/Types")

local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else
		failures += 1
		print("FAIL " .. name .. (if detail then ": " .. tostring(detail) else ""))
	end
end

local function b(id, level, honey) return { id = id, level = level, honey = honey, lastProducedAt = 0 } end
local function count(t) local n = 0 for _ in t or {} do n += 1 end return n end

-- 1a. Umstieg: Teich bekommt das hoechste Level und allen Honig
local island = { buildings = { Beehive = b("Beehive", 23, 4), HoneyRefiner = b("HoneyRefiner", 17, 6) } }
HoneyPondMode.apply(island, true, 100)
check("nur der Teich ist aktiv", count(island.buildings) == 1 and island.buildings.HoneyPond ~= nil)
check("Teich-Level = hoechstes altes", island.buildings.HoneyPond.level == 23, island.buildings.HoneyPond.level)
check("Honig zusammengelegt", island.buildings.HoneyPond.honey == 10, island.buildings.HoneyPond.honey)
check("alte im Ruhestand", island.retiredBuildings.Beehive.level == 23 and island.retiredBuildings.HoneyRefiner.level == 17)

-- 1b. Idempotent
island.buildings.HoneyPond.level = 30
HoneyPondMode.apply(island, true, 200)
check("zweiter Aufruf aendert nichts", island.buildings.HoneyPond.level == 30 and island.buildings.HoneyPond.honey == 10)

-- 1c. Ein frisch angelegter Standard-Stock (Migration fuellt fehlende Ids
--     auf) ueberschreibt den Ruhestand nicht
island.buildings.Beehive = b("Beehive", 1, 0)
HoneyPondMode.apply(island, true, 300)
check("Ruhestand gewinnt gegen frischen Standard", island.retiredBuildings.Beehive.level == 23 and island.buildings.Beehive == nil)
check("Teich bleibt bei 30", island.buildings.HoneyPond.level == 30, island.buildings.HoneyPond.level)

-- 1d. Rueckweg: alte kommen unveraendert, Teich geht in den Ruhestand
island.buildings.Beehive = b("Beehive", 1, 0)   -- Standard (Schalter aus) fuellt auf
HoneyPondMode.apply(island, false, 400)
check("Rueckweg: Stock wieder 23", island.buildings.Beehive.level == 23, island.buildings.Beehive.level)
check("Rueckweg: Veredler wieder 17", island.buildings.HoneyRefiner.level == 17)
check("Rueckweg: Teich im Ruhestand", island.retiredBuildings.HoneyPond.level == 30 and island.buildings.HoneyPond == nil)

-- 1e. Neuer Spieler (Standard mit Schalter an)
local fresh = Types.createDefaultPlayerData()
check("neuer Spieler: nur Teich", count(fresh.island.buildings) == 1 and fresh.island.buildings.HoneyPond.level == 1)

-- 2. Teich = Stock + Veredler auf gleichem Level
for _, level in { 1, 5, 10, 20, 30, 45, 60 } do
	local perMinOld = 60 / BuildingBehavior.getIntervalSeconds("Beehive", level)
		+ 60 / BuildingBehavior.getIntervalSeconds("HoneyRefiner", level)
	local perMinPond = 60 / BuildingBehavior.getIntervalSeconds("HoneyPond", level)
	check("L" .. level .. " Honig/min gleich", math.abs(perMinOld - perMinPond) < 1e-6, string.format("%.3f vs %.3f", perMinOld, perMinPond))

	local capOld = BuildingBehavior.getCapacity("Beehive", level) + BuildingBehavior.getCapacity("HoneyRefiner", level)
	check("L" .. level .. " Lager gleich", BuildingBehavior.getCapacity("HoneyPond", level) == capOld)

	local xpOld = BuildingBehavior.getXpPerHoney({ Beehive = b("Beehive", level, 0), HoneyRefiner = b("HoneyRefiner", level, 0) })
	local xpPond = BuildingBehavior.getXpPerHoney({ HoneyPond = b("HoneyPond", level, 0) })
	check("L" .. level .. " XP je Honig gleich", xpOld == xpPond, xpOld .. " vs " .. xpPond)

	check("L" .. level .. " Heilung = Veredler",
		BuildingBehavior.getHealPercent("HoneyPond", level) == BuildingBehavior.getHealPercent("HoneyRefiner", level))
end
check("Auto-Ernte ab L10", BuildingBehavior.hasAbility("HoneyPond", 10, "AutoHarvest") and not BuildingBehavior.hasAbility("HoneyPond", 9, "AutoHarvest"))

if failures > 0 then error(failures .. " Fehler", 0) end
print("honey_pond: alle Tests gruen")
