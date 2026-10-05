-- pit_balance.lua — misst, wie weit jeder Baerchi in einem Tower kommt (volle HP).
-- Aufruf: cd tools/luau-tests && node run.mjs ../sim/pit_balance.lua
-- v15: statt PIT-Level ein Tower (TOWER_ID, Standard "I" = der alte PIT 1).
-- Die ausfuehrliche Kalibrierung aller Profile steht in tower_calibration.lua.
local BaerchiConfig    = require(RS.Config.BaerchiConfig)
local TowerConfig      = require(RS.Config.TowerConfig)
local CombatCalculator = require(RS.Modules.CombatCalculator)
local BaerchiFactory   = require(RS.Modules.BaerchiFactory)

local LEVELS = { 1, 10, 20, 30, 50 }
local RUNS = 40
math.randomseed(1234)

local function runOnce(b, towerId)
	local def = BaerchiConfig.getById(b.configId)
	local stats = CombatCalculator.getEffectiveStats(b, def.baseStats)
	local hp = stats.maxHp
	local charge = 0
	local cleared = 0
	for stage = 1, TowerConfig.get(towerId).stages do
		local es = TowerConfig.getEnemyStats(towerId, stage)
		local me = { uid = "me", stats = stats, hp = hp, charge = charge }
		local en = { uid = "en", stats = es, hp = es.maxHp, charge = 0 }
		local r = CombatCalculator.simulate(me, en, false)
		hp = math.clamp(me.hp, 0, stats.maxHp)
		charge = me.charge
		if r.winnerUid ~= "me" or hp <= 0 then break end
		cleared += 1
	end
	return cleared
end

local ids = {}
for id in BaerchiConfig.data do table.insert(ids, id) end
table.sort(ids, function(a, b)
	local ra = BaerchiConfig.getRarityIndex(BaerchiConfig.data[a].rarity)
	local rb = BaerchiConfig.getRarityIndex(BaerchiConfig.data[b].rarity)
	if ra ~= rb then return ra < rb end
	return a < b
end)

local towerId = TOWER_ID or "I"
__log("Tower " .. towerId .. " — Spalten: Level " .. table.concat(LEVELS, "/"))
for _, id in ids do
	local line = { id }
	for _, lvl in LEVELS do
		local b = BaerchiFactory.create(id, { level = lvl })
		local sum = 0
		for _ = 1, RUNS do sum += runOnce(b, towerId) end
		table.insert(line, string.format("%.1f", sum / RUNS))
	end
	__log("ROW", table.concat(line, "\t"))
end
