-- incubator.test.lua — Sammel-Update 05.10., Paket 8 (+ Paket 7 Index-Belohnungen)
-- python tools/luau-tests/run_local.py tools/luau-tests/incubator.test.lua
--
-- 1. Zeitrechnung (rein, mit festem `now`): fertig genau ab finishAt, auch
--    nach langer Abwesenheit (Offline-Fall), Fortschritt 0..1, Beschleunigen.
-- 2. Plaetze: 1 am Anfang, mehr ueber Level/Rebirth/Index, nie ueber MAX.
-- 3. Sofort-Oeffnen: Basis/Zucker immer, Gold+ erst nach Freischaltung.
-- 4. Index-Belohnungen: Ei-Reihe fertig/rueckwirkend, Ascension nur bei "all".

local IncubatorRules    = rbxRequire("ReplicatedStorage/Modules/IncubatorRules")
local IncubatorConfig   = rbxRequire("ReplicatedStorage/Config/IncubatorConfig")
local IndexRewardConfig = rbxRequire("ReplicatedStorage/Config/IndexRewardConfig")
local EggConfig         = rbxRequire("ReplicatedStorage/Config/EggConfig")

local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else
		failures += 1
		print("FAIL " .. name .. (if detail then ": " .. tostring(detail) else ""))
	end
end

-- 1. Zeit
local T0 = 1_000_000
local brew = IncubatorRules.brewSeconds("BasicEgg", 1)
check("Basis-Ei 30 s auf Level 1", brew == 30, brew)
check("Gold-Ei braucht laenger als Basis", IncubatorRules.brewSeconds("GoldenEgg", 1) > brew)
check("hoeheres Level bruetet schneller", IncubatorRules.brewSeconds("GoldenEgg", 30) < IncubatorRules.brewSeconds("GoldenEgg", 1))
local slot = { slot = 1, eggType = "GoldenEgg", startedAt = T0, finishAt = T0 + 180 }
check("nicht fertig kurz davor", not IncubatorRules.isReady(slot, T0 + 179))
check("fertig genau bei finishAt", IncubatorRules.isReady(slot, T0 + 180))
check("offline: nach 3 Tagen fertig", IncubatorRules.isReady(slot, T0 + 3 * 86400))
check("Fortschritt halb", math.abs(IncubatorRules.progress(slot, T0 + 90) - 0.5) < 1e-9)
check("Fortschritt gedeckelt", IncubatorRules.progress(slot, T0 + 9999) == 1)
check("Restzeit 0 wenn fertig", IncubatorRules.remaining(slot, T0 + 500) == 0)
check("Beschleunigen 3 min = 3 Gold", IncubatorRules.speedUpCost(slot, T0) == 3 * IncubatorConfig.SPEEDUP_GOLD_PER_MINUTE)
check("Beschleunigen angefangene Minute", IncubatorRules.speedUpCost(slot, T0 + 170) == IncubatorConfig.SPEEDUP_GOLD_PER_MINUTE)
check("Beschleunigen fertig = 0", IncubatorRules.speedUpCost(slot, T0 + 180) == 0)

-- 2. Plaetze
check("Start 1 Platz", IncubatorRules.slotCount(1, 0, {}) == 1)
check("Level 10 = 2", IncubatorRules.slotCount(10, 0, {}) == 2)
check("Rebirth 2 +1", IncubatorRules.slotCount(1, 2, {}) == 2)
local allPaths = {}
for _, p in IndexRewardConfig.PATHS do allPaths["path:" .. p] = true end
check("nie ueber MAX", IncubatorRules.slotCount(60, 99, allPaths) == IncubatorConfig.MAX_SLOTS)
check("Index-Pfad +1", IncubatorRules.slotCount(1, 0, { ["path:Stamm"] = true }) == 2)
check("firstFree", IncubatorRules.firstFree({ { slot = 1, eggType = "BasicEgg", startedAt = 0, finishAt = 1 } }, 2) == 2)
check("firstFree voll", IncubatorRules.firstFree({ { slot = 1, eggType = "BasicEgg", startedAt = 0, finishAt = 1 } }, 1) == nil)
check("Ausbau kostet etwas", (IncubatorRules.upgradeCost(2) or { gummies = 0 }).gummies > 0)
check("ueber MAX kein Ausbau", IncubatorRules.upgradeCost(IncubatorConfig.MAX_LEVEL + 1) == nil)

-- 3. Sofort-Oeffnen
check("Basis sofort", not IncubatorRules.requiresIncubator("BasicEgg", true))
check("Zucker sofort", not IncubatorRules.requiresIncubator("SugarEgg", true))
check("Gold braucht Inkubator", IncubatorRules.requiresIncubator("GoldenEgg", true))
check("vor Freischaltung alles sofort", not IncubatorRules.requiresIncubator("GoldenEgg", false))
check("frisch: gesperrt", not IncubatorRules.isUnlocked({ rebirthCount = 0, towers = { records = {} }, stats = {} }))
check("nach Kampf frei", IncubatorRules.isUnlocked({ rebirthCount = 0, towers = { records = {} }, stats = { totalFightsLost = 1 } }))

-- 4. Index-Belohnungen
local basic = IndexRewardConfig.get("egg:BasicEgg")
check("Ei-Reihe Basis existiert", basic ~= nil)
if basic then
	local disc = {}
	for _, id in basic.members do disc[id] = true end
	check("Basis-Reihe komplett", IndexRewardConfig.isComplete(basic, disc))
	local claim = IndexRewardConfig.claimable(disc, {})
	check("rueckwirkend abholbar", table.find(claim, "egg:BasicEgg") ~= nil)
	check("abgeholt nicht mehr abholbar", table.find(IndexRewardConfig.claimable(disc, { ["egg:BasicEgg"] = true }), "egg:BasicEgg") == nil)
	check("leer nicht komplett", not IndexRewardConfig.isComplete(basic, {}))
end
for _, entry in IndexRewardConfig.ENTRIES do
	local egg = entry.reward.eggType
	if egg and EggConfig.data[egg] and EggConfig.data[egg].path == "Ascension" then
		check("Ascension nur bei Gesamt-Belohnung (" .. entry.id .. ")", entry.id == "all")
	end
	check("Kollektion nicht leer: " .. entry.id, #entry.members > 0)
end

if failures > 0 then error(failures .. " Fehler", 0) end
print("incubator: alle Tests gruen")
