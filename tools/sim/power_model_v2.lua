-- power_model_v2.lua — Welt 1, Paket 5b: Tower-Kalibrierung mit der Achse "Wurf-Qualitaet"
-- python tools/luau-tests/run_local.py tools/sim/power_model_v2.lua
-- Modell V2 an, je Rarity ein Vertreter, Wurf-Perzentil p10/p50/p90, Profile L1 / L50 P5 / L50 Max.
-- Parameter (optional vorher setzen): SCALE = { I=, II=, III=, Final= }
local FeatureFlags     = require(RS.Config.FeatureFlags)
local PowerConfig      = require(RS.Config.PowerConfig)
local PowerRules       = require(RS.Modules.PowerRules)
local BaerchiConfig    = require(RS.Config.BaerchiConfig)
local PromotionConfig  = require(RS.Config.PromotionConfig)
local CharmConfig      = require(RS.Config.CharmConfig)
local TowerConfig      = require(RS.Config.TowerConfig)
local CombatCalculator = require(RS.Modules.CombatCalculator)
local BaerchiFactory   = require(RS.Modules.BaerchiFactory)

FeatureFlags.FLAGS.POWER_MODEL_V2 = true
if SCALE then for k, v in SCALE do PowerConfig.TOWER_ENEMY_SCALE[k] = v end end
math.randomseed(4242)

local function uidForPercentile(rank, target)
	for i = 1, 20000 do
		local uid = string.format("b_1760000000_%d_%d", i, i * 31 % 9000)
		local q = PowerRules.roll(uid, rank).quality
		if math.abs(q - target) < 0.01 then return uid end
	end
	return "b_1760000000_1_1"
end

local function makeBaerchi(id, level, promotion, charmsOn, statShare, pct)
	local b = BaerchiFactory.create(id, { level = level })
	local rank = BaerchiConfig.getRarityIndex(b.rarity) - 1
	b.uid = uidForPercentile(rank, pct)
	b.promotionLevel = promotion
	local cap = PromotionConfig.getStatCap(b.rarity)
	for _, key in { "hp", "atk", "spd", "pwr", "egg" } do b.statLevels[key] = math.floor(cap * statShare) end
	if charmsOn then
		local ids = { "HpBoost", "AtkBoost", "SpdBoost", "PwrBoost" }
		b.charms = {}
		for slot = 1, CharmConfig.SLOT_COUNT do
			local def = CharmConfig.getStatDef(ids[(slot - 1) % #ids + 1])
			table.insert(b.charms, { slot = slot, rarity = "Legendary", statId = def.id, value = def.base * 4.4, locked = false })
		end
	end
	return b
end

local function runOnce(b, towerId)
	local def = BaerchiConfig.getById(b.configId)
	local stats = CombatCalculator.getEffectiveStats(b, def.baseStats)
	local tower = TowerConfig.get(towerId)
	local hp, charge, cleared = stats.maxHp, 0, 0
	for stage = 1, tower.stages do
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
local function avg(b, towerId) local s = 0 for _ = 1, 4 do s += runOnce(b, towerId) end return s / 4 end

local REPS = {
	{ "Common", "RedBaerchi" }, { "Rare", "SugarBaerchi" }, { "Epic", "GoldenGrizzly" }, { "Legendary", "RainbowBaerchi" },
	{ "Mythic", "CosmicBaerchi" }, { "Divine", "SeraphBaerchi" }, { "Cosmic", "CometBaerchi" }, { "Secret", "ShadeBaerchi" },
	{ "Godly", "TitanBaerchi" }, { "Eternal", "ChronosBaerchi" }, { "Omega", "OmegaBaerchi" },
}
local PROFILES = {
	{ name = "L1 nackt", level = 1, promo = 0, charms = false, stats = 0 },
	{ name = "L25 P5 C S50", level = 25, promo = 5, charms = true, stats = 0.5 },
	{ name = "L50 P5 C S50", level = 50, promo = 5, charms = true, stats = 0.5 },
	{ name = "L50 Max", level = 50, promo = 10, charms = true, stats = 1.0 },
}
RESULT = {}
for _, prof in PROFILES do
	__log("")
	__log("Profil: " .. prof.name .. "  (Wurf p10 / p50 / p90)   Tower I | II | III | Final")
	RESULT[prof.name] = {}
	for _, rep in REPS do
		local cells = {}
		RESULT[prof.name][rep[1]] = {}
		for _, pct in { 0.10, 0.50, 0.90 } do
			local b = makeBaerchi(rep[2], prof.level, prof.promo, prof.charms, prof.stats, pct)
			local row = {}
			for _, t in TowerConfig.TOWERS do
				if t.id ~= "Endless" then row[t.id] = avg(b, t.id) end
			end
			RESULT[prof.name][rep[1]][pct] = row
			table.insert(cells, string.format("%3d|%3d|%3d|%3d", row.I, row.II, row.III, row.Final))
		end
		__log(string.format("%-10s %s   %s   %s", rep[1], cells[1], cells[2], cells[3]))
	end
end
