-- pit_balance.lua — misst, wie weit jeder Baerchi im PIT kommt (volle HP, PIT 1).
-- Aufruf: cd tools/luau-tests && node run.mjs ../sim/pit_balance.lua
local BaerchiConfig    = require(RS.Config.BaerchiConfig)
local CombatConfig     = require(RS.Config.CombatConfig)
local CombatCalculator = require(RS.Modules.CombatCalculator)
local BaerchiFactory   = require(RS.Modules.BaerchiFactory)

local LEVELS = { 1, 10, 20, 30, 50 }
local RUNS = 40
math.randomseed(1234)

local function runOnce(b, pit)
	local def = BaerchiConfig.getById(b.configId)
	local stats = CombatCalculator.getEffectiveStats(b, def.baseStats)
	local hp = stats.maxHp
	local charge = 0
	local cleared = 0
	for stage = 1, CombatConfig.MAX_STAGES_PER_RUN do
		local es = CombatConfig.getEnemyStats(pit, stage)
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

local pit = PIT_LEVEL or 1
for _, id in ids do
	local line = { id }
	for _, lvl in LEVELS do
		local b = BaerchiFactory.create(id, { level = lvl })
		local sum = 0
		for _ = 1, RUNS do sum += runOnce(b, pit) end
		table.insert(line, string.format("%.1f", sum / RUNS))
	end
	__log("ROW", table.concat(line, "\t"))
end
