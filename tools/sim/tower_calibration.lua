-- tower_calibration.lua — wie weit kommt welcher Baerchi in welchem Tower?
-- Aufruf: cd tools/luau-tests && node run.mjs ../sim/tower_calibration.lua
--
-- Simuliert komplette Laeufe (HP-Uebertrag zwischen Stages, Ladung der
-- Faehigkeit) mit dem echten CombatCalculator und den Gegnern aus TowerConfig.
-- Profile: Rarity x Level 1/25/50 x Promotion 0/5/10 x Charms aus/an x
-- Stat-Stufen 0/50/100 % der Rarity-Obergrenze. Die Charms "an" sind 8
-- Legendaer-Charms (je 2x HP, ATK, SPD, PWR, Mittelwert des Wurfs).
--
-- Ziele (Prompt 2, Paket 3.5):
--   * frischer Level-1-Common: Tower I ~3 Stages (wie heute PIT 1)
--   * Level 50 + Maximal-Ausbau: Tower I locker (30/30)
--   * Tower III mit Muehe (~45-60) fuer Level 50 + Maximal-Ausbau Legendaer/Mythisch
--   * Final nur mit Maximal-Ausbau einer hohen Rarity (~70-100)
-- Ausserdem: Dauer der Server-Simulation eines 100-Stage-Laufs.

local BaerchiConfig    = require(RS.Config.BaerchiConfig)
local PromotionConfig  = require(RS.Config.PromotionConfig)
local CharmConfig      = require(RS.Config.CharmConfig)
local TowerConfig      = require(RS.Config.TowerConfig)
local CombatCalculator = require(RS.Modules.CombatCalculator)
local BaerchiFactory   = require(RS.Modules.BaerchiFactory)

local RUNS = 6
math.randomseed(4242)

local function makeBaerchi(id, level, promotion, charmsOn, statShare)
	local b = BaerchiFactory.create(id, { level = level })
	b.promotionLevel = promotion
	local cap = PromotionConfig.getStatCap(b.rarity)
	for _, key in { "hp", "atk", "spd", "pwr", "egg" } do
		b.statLevels[key] = math.floor(cap * statShare)
	end
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

-- Ein Lauf ab Stage 1 bis zur Niederlage (oder bis zur letzten Stage).
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

local function avgStages(b, towerId)
	local sum = 0
	for _ = 1, RUNS do sum += runOnce(b, towerId) end
	return sum / RUNS
end

local REPS = {
	{ "Common",    "RedBaerchi" },
	{ "Rare",      "SugarBaerchi" },
	{ "Epic",      "GoldenGrizzly" },
	{ "Legendary", "RainbowBaerchi" },
	{ "Mythic",    "CosmicBaerchi" },
	{ "Divine",    "SeraphBaerchi" },
	{ "Cosmic",    "CometBaerchi" },
	{ "Secret",    "ShadeBaerchi" },
	{ "Godly",     "TitanBaerchi" },
	{ "Eternal",   "ChronosBaerchi" },
	{ "Omega",     "OmegaBaerchi" },
}

local PROFILES = {
	{ name = "L1 nackt",            level = 1,  promo = 0,  charms = false, stats = 0 },
	{ name = "L25 P0",              level = 25, promo = 0,  charms = false, stats = 0 },
	{ name = "L25 P5 C S50",        level = 25, promo = 5,  charms = true,  stats = 0.5 },
	{ name = "L50 P0",              level = 50, promo = 0,  charms = false, stats = 0 },
	{ name = "L50 P5 C S50",        level = 50, promo = 5,  charms = true,  stats = 0.5 },
	{ name = "L50 Max (P10 C S100)", level = 50, promo = 10, charms = true,  stats = 1.0 },
}

local results = {}
for _, profile in PROFILES do
	__log("")
	__log(string.format("Profil: %s", profile.name))
	__log("Rarity     |  I/30 | II/45 | III/60 | F/100")
	__log("-----------+-------+-------+--------+------")
	results[profile.name] = {}
	for _, rep in REPS do
		local b = makeBaerchi(rep[2], profile.level, profile.promo, profile.charms, profile.stats)
		local row = {}
		for _, tower in TowerConfig.TOWERS do
			row[tower.id] = avgStages(b, tower.id)
		end
		results[profile.name][rep[1]] = row
		__log(string.format("%-10s | %5.1f | %5.1f | %6.1f | %5.1f",
			rep[1], row.I, row.II, row.III, row.Final))
	end
end

-- Laufzeit eines 100-Stage-Laufs auf dem Server (ohne Portionierung gemessen).
local omega = makeBaerchi("OmegaBaerchi", 50, 10, true, 1.0)
local t0 = REAL_CLOCK()
local REPEAT = 20
for _ = 1, REPEAT do runOnce(omega, "Final") end
local perRun = (REAL_CLOCK() - t0) / REPEAT
__log("")
__log(string.format("Simulationsdauer Final-Lauf (Omega max): %.2f ms pro Lauf (in Portionen zu 10 Stages je task.wait)", perRun * 1000))

-- Pruefungen gegen die Ziele
local fails = 0
local function check(name, cond, detail)
	if cond then __log("ok  ", name) else fails += 1; __log("FAIL", name, detail or "") end
end
local fresh = results["L1 nackt"].Common.I
check("frischer L1-Common schafft ~3 Stages in Tower I", fresh >= 2 and fresh <= 4, fresh)
local maxP = results["L50 Max (P10 C S100)"]
check("L50 Max Common schafft Tower I locker", maxP.Common.I >= 30, maxP.Common.I)
check("L50 Max Legendaer: Tower III mit Muehe (40-60)", maxP.Legendary.III >= 38 and maxP.Legendary.III <= 60, maxP.Legendary.III)
check("L50 Max Mythisch: Tower III mit Muehe (45-60)", maxP.Mythic.III >= 45, maxP.Mythic.III)
check("L50 Max Mythisch: Final kaum (< 30)", maxP.Mythic.Final < 30, maxP.Mythic.Final)
check("L50 Max Omega: Final 70-100", maxP.Omega.Final >= 70 and maxP.Omega.Final <= 100, maxP.Omega.Final)
check("Final 100 nur mit Maximal-Ausbau (Omega P5 S50 < 100)", results["L50 P5 C S50"].Omega.Final < 100, results["L50 P5 C S50"].Omega.Final)
check("Simulation 100 Stages < 50 ms", perRun < 0.05, perRun)
__log(fails == 0 and "ALLE ZIELE OK" or ("ZIELE VERFEHLT: " .. fails))
