-- boss_balance.lua — Kampfdauer der Wespenkoenigin bei 1/4/8 Spielern und
-- verschiedener Staerke (Anfaenger bis Maximalausbau).
-- Aufruf: cd tools/luau-tests && node run.mjs ../sim/boss_balance.lua
--
-- Rechnet mit denselben Modulen wie der Server: DPS aus dem echten
-- Kampfmodell (Modules/BossBalance → CombatCalculator), HP-Formel und
-- Belohnung aus BossBalance, alle Zahlen aus EventConfig.WASP_QUEEN.
--
-- Spielermodell (Annahme): ein Spieler steht mit Wahrscheinlichkeit IN_PIT
-- im Pit (feuert an, kann getroffen werden); jede Attacke trifft einen
-- Spieler im Pit mit HIT_CHANCE (Anfaenger weichen schlechter aus).
--
-- Ziele (Auftrag): mittlere Kampfdauer 120–180 s, nie unter 60 s, und ein
-- einzelner starker Spieler schafft es immer vor Ablauf des Timers.

local EventConfig      = require(RS.Config.EventConfig)
local BaerchiConfig    = require(RS.Config.BaerchiConfig)
local PromotionConfig  = require(RS.Config.PromotionConfig)
local BaerchiFactory   = require(RS.Modules.BaerchiFactory)
local CombatCalculator = require(RS.Modules.CombatCalculator)
local BossBalance      = require(RS.Modules.BossBalance)

local cfg = EventConfig.WASP_QUEEN
local def = EventConfig.getById("WaspQueen")
local FIGHT_LIMIT = EventConfig.getDuration(def) - cfg.ANNOUNCE_SECONDS
local RUNS = 300

local fails = 0
local function check(ok, msg)
	if not ok then fails += 1; __log("FAIL " .. msg) end
end

math.randomseed(777)

-- Staerke-Stufen: { Name, configId, Level, Promotion, Stat-Stufen (Anteil am Cap), Trefferquote }
local TIERS = {
	{ name = "Anfaenger", configId = "RedBaerchi",   level = 1,  promo = 0,  statShare = 0,   hit = 0.45 },
	{ name = "Mitte",     configId = "GoldenGrizzly", level = 25, promo = 4,  statShare = 0.5, hit = 0.30 },
	{ name = "Stark",     configId = "SeraphBaerchi", level = 40, promo = 8,  statShare = 0.8, hit = 0.20 },
	{ name = "Maximal",   configId = "OmegaBaerchi",  level = BaerchiConfig.MAX_LEVEL, promo = 10, statShare = 1, hit = 0.15 },
}
local IN_PIT = 0.8

local dpsCache = {}
local function dpsOf(tier)
	if dpsCache[tier.name] then return dpsCache[tier.name] end
	local b = BaerchiFactory.create(tier.configId, { level = tier.level })
	b.promotionLevel = tier.promo
	local cap = PromotionConfig.getStatCap(b.rarity)
	for _, key in PromotionConfig.GROWABLE_STATS do
		b.statLevels[key] = math.floor(cap * tier.statShare)
	end
	local stats = CombatCalculator.getEffectiveStats(b, BaerchiConfig.getById(tier.configId).baseStats)
	local dps = BossBalance.dpsFromStats(stats)
	dpsCache[tier.name] = dps
	return dps
end

-- Ein Kampf; gibt Dauer (s, oder nil bei Flucht) und Schadensanteile zurueck.
local function fight(team)
	local dpsList = {}
	for _, tier in team do table.insert(dpsList, dpsOf(tier)) end
	local maxHp = BossBalance.bossHp(dpsList)
	local hp = maxHp
	local t = 0
	local stun = {}
	local damage = {}
	local nextAttack = cfg.PHASE1_ATTACK_INTERVAL
	local phase2 = false
	while t < FIGHT_LIMIT do
		t += cfg.TICK_SECONDS
		local inPit = {}
		for i, tier in team do
			inPit[i] = math.random() < IN_PIT
			if t >= (stun[i] or 0) then
				local cheer = if inPit[i] then cfg.CHEER_FACTOR else 1
				local dmg = dpsList[i] * cfg.TICK_SECONDS * cheer
				damage[i] = (damage[i] or 0) + dmg
				hp -= dmg
			end
		end
		if not phase2 and hp <= maxHp * cfg.PHASE2_AT then phase2 = true end
		if t >= nextAttack then
			for i, tier in team do
				if inPit[i] and math.random() < tier.hit then
					stun[i] = t + cfg.TELEGRAPH_SECONDS + cfg.HIT_STUN_SECONDS
				end
			end
			nextAttack = t + (if phase2 then cfg.PHASE2_ATTACK_INTERVAL else cfg.PHASE1_ATTACK_INTERVAL)
		end
		if hp <= 0 then return t, damage, maxHp end
	end
	return nil, damage, maxHp
end

local function team(n, pick)
	local list = {}
	for i = 1, n do table.insert(list, pick(i)) end
	return list
end

__log(string.format("Wespenkoenigin: Zielzeit %d s, Kampf-Timer %d s, Cheer x%.2f, Stun %d s, Attacke alle %d/%d s",
	cfg.TARGET_FIGHT_SECONDS, FIGHT_LIMIT, cfg.CHEER_FACTOR, cfg.HIT_STUN_SECONDS, cfg.PHASE1_ATTACK_INTERVAL, cfg.PHASE2_ATTACK_INTERVAL))
__log("")
__log("DPS je Staerke (echtes Kampfmodell gegen den Trainings-Dummy):")
for _, tier in TIERS do
	__log(string.format("  %-9s %-14s Lv %-2d Promo %-2d -> %12.1f DPS", tier.name, tier.configId, tier.level, tier.promo, dpsOf(tier)))
end
__log("")
__log("Spieler | Team                  | Boss-HP          | Dauer Ø | min | max | Flucht | Top-Anteil | unter 2 %")
__log("--------+-----------------------+------------------+---------+-----+-----+--------+------------+----------")

local scenarios = {}
for _, n in { 1, 4, 8 } do
	for _, tier in TIERS do
		table.insert(scenarios, { n = n, label = "alle " .. tier.name, team = team(n, function() return tier end), strongSolo = (n == 1 and tier.name ~= "Anfaenger") })
	end
	if n > 1 then
		table.insert(scenarios, { n = n, label = "gemischt", team = team(n, function(i) return TIERS[(i - 1) % #TIERS + 1] end) })
		table.insert(scenarios, { n = n, label = "1 Maximal + Anfaenger", team = team(n, function(i) return if i == 1 then TIERS[4] else TIERS[1] end) })
	end
end

for _, sc in scenarios do
	local sum, count, minT, maxT, fled, topShare, under = 0, 0, math.huge, 0, 0, 0, 0
	local hpShown = 0
	for _ = 1, RUNS do
		local t, damage, maxHp = fight(sc.team)
		hpShown = maxHp
		local pays = BossBalance.payouts(damage, t ~= nil)
		local best = 0
		for _, p in pays do
			if p.share > best then best = p.share end
			if not p.qualified then under += 1 end
		end
		topShare += best
		if t then
			sum += t; count += 1
			if t < minT then minT = t end
			if t > maxT then maxT = t end
		else
			fled += 1
		end
	end
	local avg = if count > 0 then sum / count else 0
	__log(string.format("%7d | %-21s | %16s | %6.0f s | %3.0f | %3.0f | %5.0f%% | %9.0f%% | %8.1f",
		sc.n, sc.label, string.format("%.3g", hpShown), avg, if count > 0 then minT else 0, maxT,
		100 * fled / RUNS, 100 * topShare / RUNS, under / RUNS))

	check(count == 0 or minT >= 60, sc.label .. " (" .. sc.n .. "): Kampf unter 60 s")
	check(avg >= 120 and avg <= 180, string.format("%s (%d): mittlere Dauer %.0f s ausserhalb 120-180", sc.label, sc.n, avg))
	if sc.strongSolo then
		check(fled == 0, sc.label .. ": starker Einzelspieler schafft den Boss nicht immer vor dem Timer")
	end
end
__log("")
if fails == 0 then
	__log("OK: Dauer im Mittel 120-180 s, nie unter 60 s, starke Einzelspieler immer vor dem Timer")
end
