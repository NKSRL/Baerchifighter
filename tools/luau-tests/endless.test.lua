-- endless.test.lua — HBB Paket 9: Endless-Tower, Endless-Level, Woche
-- python tools/luau-tests/run_local.py tools/luau-tests/endless.test.lua
--
-- 1. Tower: Endless gibt es nur mit Schalter, ist bis Final 100 zu, danach
--    offen (unabhaengig von Rebirths); zeigt "Stage 101+" im Schau-Turm-Mass.
-- 2. Meilensteine: jede 10. Endless-Stage +1 Endless-Level, sonst keins.
-- 3. Endless-Level: XP-Kurve steigt, wirkt im Kampf nur auf Max-Level,
--    +1 Endless-Level = gleiche Werte wie +1 Level.
-- 4. Woche: Wechsel genau Montag 00:00 UTC, Store-Name je Woche.
-- 5. Tafeln: Endless + Woche stehen in MapLayout (Abstaende: map_layout.test).
-- Was hier nicht geprueft wird: OrderedDataStores, Krone am Schild (Studio).

local TowerConfig       = rbxRequire("ReplicatedStorage/Config/TowerConfig")
local BaerchiConfig     = rbxRequire("ReplicatedStorage/Config/BaerchiConfig")
local LeaderboardConfig = rbxRequire("ReplicatedStorage/Config/LeaderboardConfig")
local FeatureFlags      = rbxRequire("ReplicatedStorage/Config/FeatureFlags")
local CombatCalculator  = rbxRequire("ReplicatedStorage/Modules/CombatCalculator")
local MapLayout         = rbxRequire("ReplicatedStorage/Modules/MapLayout")

local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else
		failures += 1
		print("FAIL " .. name .. (if detail then ": " .. tostring(detail) else ""))
	end
end

if not FeatureFlags.isOn("ENDLESS") then
	check("ohne Schalter kein Endless-Tower", TowerConfig.get("Endless") == nil)
	check("ohne Schalter keine Endless-Liste", table.find(LeaderboardConfig.LISTS, "Endless") == nil)
	print("endless: Schalter aus — nur Abwesenheit geprueft")
	if failures > 0 then error(failures .. " Fehler", 0) end
	return
end

-- 1. Tower
local endless = TowerConfig.get("Endless")
local final = TowerConfig.get("Final")
check("Endless existiert", endless ~= nil)
check("Endless ist der letzte Tower", TowerConfig.TOWERS[#TowerConfig.TOWERS].id == "Endless")
check("Endless setzt Final fort (Aequivalenz)",
	math.abs(endless.startEquivalent - (final.startEquivalent + final.stages * final.equivalentPerStage)) <= 0.5,
	endless.startEquivalent)
check("zu ohne Rekorde", not TowerConfig.isEndlessOpen(nil))
check("zu bei Final 99", not TowerConfig.isEndlessOpen({ Final = 99 }))
check("offen bei Final 100", TowerConfig.isEndlessOpen({ Final = 100 }))
check("Deckel 0 solange zu", TowerConfig.getStageCap(30, "Endless", { Final = 99 }) == 0)
check("Deckel = alle Stages wenn offen, auch nach Rebirth 0",
	TowerConfig.getStageCap(0, "Endless", { Final = 100 }) == endless.stages)
check("isOpen folgt dem Deckel", TowerConfig.isOpen(0, "Endless", { Final = 100 })
	and not TowerConfig.isOpen(99, "Endless", {}))
check("Tower-Deckel-Tabelle kennt Endless nicht (kein Rebirth-Hinweis)",
	not TowerConfig.isCapLimiting(99, "Endless"))
check("Bestenlisten-Wert Endless > jeder Final-Wert",
	TowerConfig.leaderboardValue("Endless", 1) > TowerConfig.leaderboardValue("Final", final.stages))
local backId, backStage = TowerConfig.fromLeaderboardValue(TowerConfig.leaderboardValue("Endless", 37))
check("Bestenlisten-Wert hin und zurueck", backId == "Endless" and backStage == 37, backId .. "/" .. backStage)

-- 2. Meilensteine
local m10 = TowerConfig.getMilestone("Endless", 10)
local m20 = TowerConfig.getMilestone("Endless", 20)
local m5 = TowerConfig.getMilestone("Endless", 5)
check("Stage 10: +1 Endless-Level", m10 ~= nil and m10.endlessLevels == 1)
check("Stage 20: +1 Endless-Level", m20 ~= nil and m20.endlessLevels == 1)
check("Stage 5: kein Endless-Level", m5 ~= nil and m5.endlessLevels == 0)
check("Final 100: kein Endless-Level", TowerConfig.getMilestone("Final", 100).endlessLevels == 0)
check("Endless-Meilenstein ohne Gold", m10.goldGummies == 0 and TowerConfig.getMilestone("Endless", 25).goldGummies == 0)

-- 3. Endless-Level
local x0 = BaerchiConfig.xpForEndlessLevel(0)
local x1 = BaerchiConfig.xpForEndlessLevel(1)
check("Endless-XP > Level-XP", x0 > BaerchiConfig.xpForNextLevel(BaerchiConfig.MAX_LEVEL))
check("Endless-XP steigt", x1 > x0)
check("Endless-XP bleibt ganzzahlig darstellbar (Stufe 300)", BaerchiConfig.xpForEndlessLevel(300) < 2 ^ 53)

local def = BaerchiConfig.data[next(BaerchiConfig.data)]
local function bear(level, endlessLevel)
	return {
		uid = "t", configId = def.id or "x", rarity = "Common", level = level, xp = 0,
		endlessLevel = endlessLevel, skillId = "None", isFusionResult = false, fusionBonus = 0, currentHp = 1,
	}
end
check("Kampf-Level unter Max ohne Endless", CombatCalculator.getCombatLevel(bear(49, 5)) == 49)
check("Kampf-Level auf Max mit Endless", CombatCalculator.getCombatLevel(bear(50, 5)) == 55)
check("Kampf-Level ohne Feld", CombatCalculator.getCombatLevel(bear(50, nil)) == 50)
local a = CombatCalculator.getEffectiveStats(bear(50, 1), def.baseStats)
local b = CombatCalculator.getEffectiveStats(bear(51, nil), def.baseStats)
check("+1 Endless-Level = +1 Level (HP)", a.maxHp == b.maxHp, a.maxHp .. " / " .. b.maxHp)
check("+1 Endless-Level = +1 Level (ATK)", a.atk == b.atk)

-- 4. Woche (05.10.2026 00:00 UTC ist ein Montag)
local monday = 1791158400
local w = LeaderboardConfig.weekOf(monday)
check("Sonntag 23:59:59 gehoert zur Vorwoche", LeaderboardConfig.weekOf(monday - 1) == w - 1)
check("Montag 00:00 beginnt die Woche", LeaderboardConfig.weekOf(monday + 6 * 86400 + 86399) == w)
check("Restzeit am Montag 00:00 = 7 Tage", LeaderboardConfig.secondsUntilNextWeek(monday) == 7 * 86400)
check("Store je Woche", LeaderboardConfig.storeName("EndlessWeek", w) ~= LeaderboardConfig.storeName("EndlessWeek", w + 1))
check("Store Endless fest", LeaderboardConfig.storeName("Endless", w) == LeaderboardConfig.storeName("Endless", w + 1))

-- 5. Tafeln
local found = {}
for _, board in MapLayout.leaderboardBoards() do
	if board.listId then found[board.listId] = true end
end
if FeatureFlags.isOn("MAP_V2_BOARDS") then
	check("Tafel Endless", found.Endless == true)
	check("Tafel Endless-Woche", found.EndlessWeek == true)
end
for _, listId in LeaderboardConfig.LISTS do
	check("Store-Name fuer " .. listId, LeaderboardConfig.STORE_NAMES[listId] ~= nil)
end

if failures > 0 then error(failures .. " Fehler", 0) end
print("endless: alle Tests gruen")
