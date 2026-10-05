-- incubator.test.lua — Sammel-Update 05.10., Paket 8 (+ Paket 7 Index-Belohnungen)
-- python tools/luau-tests/run_local.py tools/luau-tests/incubator.test.lua
--
-- 1. Brut-Takt (Umbau 05.10.: Baerchi im Platz): faellige Eier, Rest der
--    Zeitmarke, Lager-Deckel auch offline, keine angesammelte Wartezeit.
-- 2. Plaetze: 1 am Anfang, mehr ueber Level/Rebirth/Index, nie ueber MAX.
-- 3. Ei-Chancen eines Baerchis: 100 %, nur freie Eier.
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

-- 1. Brut-Takt (rein, mit festem `now`)
local T0 = 1_000_000
local common = IncubatorRules.breedSeconds("Common", 1)
check("Common-Takt laut Config", common == IncubatorConfig.BREED_SECONDS_BY_RARITY.Common, common)
check("seltener bruetet schneller", IncubatorRules.breedSeconds("Legendary", 1) < common)
check("hoeheres Level bruetet schneller", IncubatorRules.breedSeconds("Common", 30) < common)
check("offline gebremst", IncubatorRules.breedSeconds("Common", 1, true) > common)
check("unbekannte Rarity -> Ersatzwert", IncubatorRules.breedSeconds("Quatsch", 1) == IncubatorConfig.BREED_SECONDS_FALLBACK)

local slot = { slot = 1, baerchiUid = "b1", lastEggAt = T0, eggs = {} }
local n, mark = IncubatorRules.due(slot, 100, T0 + 99)
check("vor dem Takt kein Ei", n == 0 and mark == T0, tostring(n) .. "/" .. tostring(mark))
n, mark = IncubatorRules.due(slot, 100, T0 + 250)
check("2 Eier nach 250 s", n == 2, n)
check("Rest bleibt erhalten (Marke +200)", mark == T0 + 200, mark)
n, mark = IncubatorRules.due(slot, 100, T0 + 3 * 86400)
check("offline: gedeckelt durch Lager", n == IncubatorConfig.STORE_PER_SLOT, n)
check("volles Lager: Marke auf jetzt", mark == T0 + 3 * 86400, mark)
local fullSlot = { slot = 1, baerchiUid = "b1", lastEggAt = T0, eggs = {} }
for _ = 1, IncubatorConfig.STORE_PER_SLOT do table.insert(fullSlot.eggs, "BasicEgg") end
n, mark = IncubatorRules.due(fullSlot, 100, T0 + 500)
check("Lager voll: keine neuen Eier", n == 0, n)
check("Lager voll: Zeit sammelt sich nicht an", mark == T0 + 500, mark)
check("Fortschritt halb", math.abs(IncubatorRules.progress(slot, 100, T0 + 50) - 0.5) < 1e-9)
check("Fortschritt voll bei vollem Lager", IncubatorRules.progress(fullSlot, 100, T0) == 1)
check("Zeitmarke in der Zukunft: nichts", (IncubatorRules.due(slot, 100, T0 - 10)) == 0)
check("storedCount", IncubatorRules.storedCount({ slot, fullSlot }) == IncubatorConfig.STORE_PER_SLOT)
check("slotOf findet Baerchi", IncubatorRules.slotOf({ slot }, "b1") == 1)
check("slotOf sonst nil", IncubatorRules.slotOf({ slot }, "b2") == nil)

-- 2. Plaetze
check("Start 1 Platz", IncubatorRules.slotCount(1, 0, {}) == 1)
check("Level 10 = 2", IncubatorRules.slotCount(10, 0, {}) == 2)
check("Rebirth 2 +1", IncubatorRules.slotCount(1, 2, {}) == 2)
local allPaths = {}
for _, p in IndexRewardConfig.PATHS do allPaths["path:" .. p] = true end
check("nie ueber MAX", IncubatorRules.slotCount(60, 99, allPaths) == IncubatorConfig.MAX_SLOTS)
check("Index-Pfad +1", IncubatorRules.slotCount(1, 0, { ["path:Stamm"] = true }) == 2)
check("firstFree", IncubatorRules.firstFree({ slot }, 2) == 2)
check("firstFree voll", IncubatorRules.firstFree({ slot }, 1) == nil)
check("Ausbau kostet etwas", (IncubatorRules.upgradeCost(2) or { gummies = 0 }).gummies > 0)
check("ueber MAX kein Ausbau", IncubatorRules.upgradeCost(IncubatorConfig.MAX_LEVEL + 1) == nil)
check("frisch: gesperrt", not IncubatorRules.isUnlocked({ rebirthCount = 0, towers = { records = {} }, stats = {} }))
check("nach Kampf frei", IncubatorRules.isUnlocked({ rebirthCount = 0, towers = { records = {} }, stats = { totalFightsLost = 1 } }))

-- 3. Chancen: summieren zu 100 %, gesperrte Eier landen beim Vorgaenger
local BaerchiConfig = rbxRequire("ReplicatedStorage/Config/BaerchiConfig")
local EggTree       = rbxRequire("ReplicatedStorage/Modules/EggTree")
local anyId = nil
for id, def in BaerchiConfig.data do
	if def.eggTable and #def.eggTable > 1 then anyId = id break end
end
if anyId then
	local baerchi = { configId = anyId, rarity = BaerchiConfig.data[anyId].rarity }
	local total = 0
	for _, entry in IncubatorRules.chances(baerchi, EggTree.newState()) do
		total += entry.percent
		check("Chance nur fuer freie Eier: " .. entry.eggType, EggTree.isUnlocked(EggTree.newState(), entry.eggType))
	end
	check("Chancen summieren zu 100", math.abs(total - 100) < 1e-6, total)
else
	check("Baerchi mit Ei-Tabelle gefunden", false)
end

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
