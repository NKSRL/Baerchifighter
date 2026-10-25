-- tower_rebalance_v3.lua — Tower-Kurven AKTUELL vs VORSCHLAG (neu 21.10.)
-- Aufruf: python tools/luau-tests/run_local.py tools/sim/rarity_capability.lua
-- Synthetischer Turm (Steigung 0,6 wie Tower III, HP-Uebertrag wie im echten Lauf), Ergebnis:
-- hoechste Aequivalenz, die ein Baerchi im Mittel erreicht. Unabhaengig vom Tower-Layout:
-- daraus lassen sich Tower-Kurven nach "welche Rarity soll was schaffen" setzen.
local BaerchiConfig    = require(RS.Config.BaerchiConfig)
local PromotionConfig  = require(RS.Config.PromotionConfig)
local CharmConfig      = require(RS.Config.CharmConfig)
local CombatConfig     = require(RS.Config.CombatConfig)
local CombatCalculator = require(RS.Modules.CombatCalculator)
local BaerchiFactory   = require(RS.Modules.BaerchiFactory)
math.randomseed(77)
local function make(id, level, promo, charmsOn, share)
	local b = BaerchiFactory.create(id, { level = level })
	b.promotionLevel = promo
	local cap = PromotionConfig.getStatCap(b.rarity)
	for _, k in { "hp", "atk", "spd", "pwr", "egg" } do b.statLevels[k] = math.floor(cap * share) end
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
local function runEqOld(b, slope)
	local def = BaerchiConfig.getById(b.configId)
	local st = CombatCalculator.getEffectiveStats(b, def.baseStats)
	local hp, ch, last = st.maxHp, 0, 1
	for s = 1, 400 do
		local eq = 1 + (s - 1) * slope
		local es = CombatConfig.getEnemyStatsForEquivalent(eq)
		local me = { uid = "me", stats = st, hp = hp, charge = ch }
		local en = { uid = "en", stats = es, hp = es.maxHp, charge = 0 }
		local r = CombatCalculator.simulate(me, en, false)
		hp = math.clamp(me.hp, 0, st.maxHp); ch = me.charge
		if r.winnerUid ~= "me" or hp <= 0 then break end
		last = eq
	end
	return last
end

local function runTower(b, t)
	local def = BaerchiConfig.getById(b.configId)
	local st = CombatCalculator.getEffectiveStats(b, def.baseStats)
	local hp, ch, cleared = st.maxHp, 0, 0
	for s = 1, t.n do
		local es = CombatConfig.getEnemyStatsForEquivalent(t.s + (s - 1) * t.p)
		local me = { uid = "me", stats = st, hp = hp, charge = ch }
		local en = { uid = "en", stats = es, hp = es.maxHp, charge = 0 }
		local r = CombatCalculator.simulate(me, en, false)
		hp = math.clamp(me.hp, 0, st.maxHp); ch = me.charge
		if r.winnerUid ~= "me" or hp <= 0 then break end
		cleared += 1
	end
	return cleared
end
local SETS = {
 AKTUELL = { I={s=1,p=1.15,n=30}, II={s=25,p=0.95,n=45}, III={s=55,p=0.6,n=60}, F={s=52,p=0.303,n=100}, E={s=132,p=0.5,n=300} },
 VORSCHLAG = { I={s=1,p=1.15,n=30}, II={s=22,p=0.65,n=45}, III={s=41,p=0.45,n=60}, F={s=58,p=0.265,n=100}, E={s=85,p=0.5,n=300} },
}
local REPS = { {"Common","RedBaerchi"},{"Rare","SugarBaerchi"},{"Epic","GoldenGrizzly"},{"Legendary","RainbowBaerchi"},
 {"Mythic","CosmicBaerchi"},{"Divine","SeraphBaerchi"},{"Cosmic","CometBaerchi"},{"Secret","ShadeBaerchi"},{"Godly","TitanBaerchi"},{"Eternal","ChronosBaerchi"},{"Omega","OmegaBaerchi"} }
local PROFILES = {
 { "L30 P3 S30", 30, 3, false, 0.3 },
 { "L40 P5 C S50", 40, 5, true, 0.5 },
 { "L50 Max", 50, 10, true, 1.0 },
}
for _, name in { "VORSCHLAG" } do
 local set = SETS[name]
 for _, p in PROFILES do
  __log("") __log(name .. " / " .. p[1])
  __log("Rarity     |   I |  II | III |   F |   E")
  for _, rep in REPS do
	local b = make(rep[2], p[2], p[3], p[4], p[5])
	local function avg(t) local x=0 for _=1,4 do x+=runTower(b,t) end return x/4 end
	__log(string.format("%-10s | %3.0f | %3.0f | %3.0f | %3.0f | %3.0f", rep[1], avg(set.I), avg(set.II), avg(set.III), avg(set.F), avg(set.E)))
  end
 end
end
