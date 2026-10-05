-- gold_rules.test.lua — GoldGummies nur aus Tages-Quests, nur fuer Charms
-- python tools/luau-tests/run_local.py tools/luau-tests/gold_rules.test.lua
--
-- Prueft die Config-Seite von FeatureFlags.GOLD_CHARMS_ONLY (Flag an):
-- 1. Kein Ausbau (Gebaeude 2-60, Recycler) kostet GoldGummies.
-- 2. Tower-Laeufe, Meilensteine und Login-Bonus geben kein Gold;
--    kein Meilenstein ist dadurch leer.
-- 3. Jede Tages-Quest gibt Gold, keine Ketten-Quest.
-- 4. Charms kosten weiter Gold (einzige Ausgabe).
-- Die Services zahlen nur, was diese Configs liefern (QuestService ueber
-- QuestConfig.goldReward), deshalb reicht der Blick auf die Configs.

local FeatureFlags     = rbxRequire("ReplicatedStorage/Config/FeatureFlags")
local EconomyConfig    = rbxRequire("ReplicatedStorage/Config/EconomyConfig")
local CombConfig       = rbxRequire("ReplicatedStorage/Config/CombConfig")
local TowerConfig      = rbxRequire("ReplicatedStorage/Config/TowerConfig")
local LoginBonusConfig = rbxRequire("ReplicatedStorage/Config/LoginBonusConfig")
local QuestConfig      = rbxRequire("ReplicatedStorage/Config/QuestConfig")
local CharmConfig      = rbxRequire("ReplicatedStorage/Config/CharmConfig")

local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else
		failures += 1
		print("FAIL " .. name .. (if detail then ": " .. tostring(detail) else ""))
	end
end

check("Flag GOLD_CHARMS_ONLY ist an", FeatureFlags.isOn("GOLD_CHARMS_ONLY"))

-- 1. Ausbauten
local goldLevels = {}
for level = 2, EconomyConfig.MAX_BUILDING_LEVEL or 60 do
	local cost = EconomyConfig.HONEY_UPGRADE_COSTS[level]
	if cost and cost.goldGummies ~= 0 then table.insert(goldLevels, level) end
	local comb = CombConfig.getUpgradeCost(level)
	if comb and comb.goldGummies ~= 0 then table.insert(goldLevels, "R" .. level) end
end
check("Ausbauten kosten kein Gold", #goldLevels == 0, table.concat(goldLevels, ","))

-- 2. Quellen
local runGold, goldMilestones, emptyMilestones = 0, {}, {}
for _, def in TowerConfig.TOWERS do
	runGold += TowerConfig.getRunGold(def.id, def.stages)
	for stage = 1, def.stages do
		local m = TowerConfig.getMilestone(def.id, stage)
		if m then
			if m.goldGummies ~= 0 then table.insert(goldMilestones, def.id .. "/" .. stage) end
			if m.gummies == 0 and m.eggs == 0 and m.blueprints == 0 then
				table.insert(emptyMilestones, def.id .. "/" .. stage)
			end
		end
	end
end
check("Tower-Laeufe geben kein Gold", runGold == 0, runGold)
check("Meilensteine geben kein Gold", #goldMilestones == 0, table.concat(goldMilestones, ","))
check("kein Meilenstein leer", #emptyMilestones == 0, table.concat(emptyMilestones, ","))

local loginGold = 0
for day = 1, LoginBonusConfig.CYCLE_DAYS do
	loginGold += LoginBonusConfig.getDay(day).goldGummies or 0
end
check("Login-Bonus gibt kein Gold", loginGold == 0, loginGold)

-- 3. Tages-Quests sind die Quelle
for _, def in QuestConfig.DAILY do
	check("Tages-Quest " .. def.id .. " gibt Gold", QuestConfig.goldReward(def) > 0)
end
local chainGold = 0
for _, def in QuestConfig.CHAIN do chainGold += QuestConfig.goldReward(def) end
check("Ketten-Quests geben kein Gold", chainGold == 0, chainGold)

-- 4. Ausgabe
check("Charm-Wurf kostet Gold", CharmConfig.ROLL_COST_GOLD_GUMMIES > 0)

if failures > 0 then error(failures .. " Fehler", 0) end
print("gold_rules: alle Tests gruen")
