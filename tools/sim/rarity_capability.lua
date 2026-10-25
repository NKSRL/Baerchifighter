-- rarity_capability.lua — wie hohe Gegner-AEQUIVALENZ schafft welche Rarity? (neu 21.10.)
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
local function runEq(b, slope)
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
local REPS = { {"Common","RedBaerchi"},{"Uncommon",nil},{"Rare","SugarBaerchi"},{"Epic","GoldenGrizzly"},{"Legendary","RainbowBaerchi"},
 {"Mythic","CosmicBaerchi"},{"Divine","SeraphBaerchi"},{"Cosmic","CometBaerchi"},{"Secret","ShadeBaerchi"},{"Godly","TitanBaerchi"},{"Eternal","ChronosBaerchi"},{"Omega","OmegaBaerchi"} }
local PROFILES = {
 { "L20 P0",            20, 0, false, 0 },
 { "L30 P3 S30",        30, 3, false, 0.3 },
 { "L40 P5 C S50",      40, 5, true,  0.5 },
 { "L50 P5 C S50",      50, 5, true,  0.5 },
 { "L50 Max",           50, 10, true, 1.0 },
}
local head = "Rarity     "
for _, p in PROFILES do head ..= string.format("| %-13s", p[1]) end
__log(head)
for _, rep in REPS do
	if rep[2] then
		local row = string.format("%-10s ", rep[1])
		for _, p in PROFILES do
			local sum = 0
			for _ = 1, 4 do sum += runEq(make(rep[2], p[2], p[3], p[4], p[5]), 0.6) end
			row ..= string.format("| %-13.1f", sum / 4)
		end
		__log(row)
	end
end
