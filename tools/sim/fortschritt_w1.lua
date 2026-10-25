-- fortschritt_w1.lua — Paket 5e (20.10.2026): wie progression_pacing.lua, aber
-- OHNE Rebirth vor Welt 2 (REBIRTH_NEEDS_WORLD2). Rebirth ist erst erlaubt, wenn
-- Final 100 geschafft ist (Welt 2 = Epilog gestartet; hier: Final 100 + 0 min).
-- Zusaetzlich: Fortschritts-Takt (Abstand zwischen sichtbaren Fortschritts-
-- Ereignissen, Ziel <= 10 aktive Minuten) und Anti-Speedrun-Tabelle.
-- Aufruf: python3 tools/luau-tests/run_local.py tools/sim/fortschritt_w1.lua
-- Basis: progression_pacing.lua (v15)
-- Aufruf: cd tools/luau-tests && node run.mjs ../sim/progression_pacing.lua
--
-- Modell eines Spielers ueber Wochen, Schritt = 1 Minute AKTIVE Spielzeit.
-- Alle Spielzahlen kommen aus den Configs (EconomyConfig, BuildingBehavior,
-- CombConfig, TowerConfig, LoginBonusConfig, BaerchiConfig) — wer dort dreht,
-- sieht hier sofort die Wirkung. Was NICHT aus den Configs kommt, sind die
-- Verhaltens-Annahmen unten (ANNAHMEN); sie stehen auch im Bericht.
--
-- Einkommen: Tower-Stage-Gummies (+ GoldGummies, Meilensteine), Recycler
-- (Wabeneinheiten aus dem Event-Pit), Events (Boss-Teilnahme), Login-Bonus,
-- alles mit Rebirth-Multiplikator wie im Spiel.
-- Ausgaben: Gebaeude 1-60 (Honig-Teich bzw. Bienenstock + Veredler je nach
-- FeatureFlags.HONEY_POND_V2, dazu Recycler), Rebirth-Kosten.
-- Baerchi: Level aus Honig (Veredler-XP x Honig pro Minute), Staerke im Tower
-- als Aequivalenz-Stage = Level + Ausbau-Bonus (Rarity/Promotion/Charms/Stats,
-- siehe POWER_BONUS).
--
-- Ziele (README 4.4 / Prompt 2, HBB Paket 8): Look 2 (L10) 20-45 min, Look 3 (L20) Tag 2-3,
-- Look 4 (L30) ~Woche 1, Look 5 (L45) Woche 2-3, Look 6 (L60) Woche 5-8;
-- Rebirth 1 nach ~2-3 Spieltagen, Final Stage 100 nicht vor ~Woche 8
-- (jeweils Profil "Normal").

local EconomyConfig    = require(RS.Config.EconomyConfig)
local BuildingBehavior = require(RS.Config.BuildingBehavior)
local CombConfig       = require(RS.Config.CombConfig)
local TowerConfig      = require(RS.Config.TowerConfig)
local BaerchiConfig    = require(RS.Config.BaerchiConfig)
local LoginBonusConfig = require(RS.Config.LoginBonusConfig)
local EventConfig      = require(RS.Config.EventConfig)
local FeatureFlags     = require(RS.Config.FeatureFlags)

--------------------------------------------------------------------------------
-- ANNAHMEN (Verhalten, nicht Spielzahlen)
--------------------------------------------------------------------------------

local PROFILES = {
	{ name = "Gelegenheit", minutesPerDay = 30 },
	{ name = "Normal",      minutesPerDay = 90 },
	{ name = "Viel",        minutesPerDay = 240 },
}

local RUN_CYCLE_MINUTES  = 2.0   -- ein Tower-Lauf inkl. Hin-/Rueckweg und Hochfuettern
local COMB_UNITS_PER_MIN = 4     -- Wabeneinheiten pro aktiver Minute (Sammeln nebenbei)
local EVENT_CYCLE_MIN    = 45.5  -- Mittel aus 41/50 min (Boss jeden 2. Durchlauf)
local SIM_DAYS           = 112   -- 16 Wochen

-- Kaufverhalten: ein Ausbau wird gekauft, sobald er hoechstens so viel kostet
-- wie PATIENCE_MINUTES Einkommen (gleitender Mittelwert). Teureres wartet. Bei
-- mehreren kaufbaren der guenstigste nach Gewicht (der Veredler zuerst: XP).
local PATIENCE_MINUTES = 20
local SHOP_WEIGHT = { HoneyRefiner = 1.6, Recycler = 1.2, Beehive = 1.0, HoneyPond = 1.6 }

-- Ausbau-Bonus in Aequivalenz-Stages ueber der Level-Zahl, nach aktiven
-- Stunden. Herkunft: tools/sim/tower_calibration.lua (Level 50 Common nackt
-- ≈ +4, Legendaer Max ≈ +33, Mythisch Max ≈ +43, Divine Max ≈ +60, Omega Max
-- ≈ +82). Die Kurve, WANN ein Spieler welche Rarity und welchen Ausbau hat,
-- ist eine Annahme (Ei-Baum + Events + Fusion + Promotion).
local POWER_BONUS = {   -- { aktive Stunden, Bonus }
	{ 0, 0 }, { 1, 4 }, { 3, 9 }, { 6, 14 }, { 12, 20 }, { 20, 27 }, { 35, 36 },
	{ 50, 44 }, { 70, 54 }, { 90, 63 }, { 110, 71 }, { 135, 78 }, { 160, 82 },
}

local function powerBonus(hours)
	for i = #POWER_BONUS, 1, -1 do
		local a = POWER_BONUS[i]
		if hours >= a[1] then
			local b = POWER_BONUS[i + 1]
			if not b then return a[2] end
			local t = (hours - a[1]) / (b[1] - a[1])
			return a[2] + (b[2] - a[2]) * t
		end
	end
	return 0
end

--------------------------------------------------------------------------------
-- Modell
--------------------------------------------------------------------------------

-- Honig-Gebaeude wie im Spiel: der Teich (HONEY_POND_V2) oder Stock + Veredler.
local HONEY_BUILDINGS = if FeatureFlags.isOn("HONEY_POND_V2") then { "HoneyPond" } else { "Beehive", "HoneyRefiner" }
local SHOP_KEYS = table.clone(HONEY_BUILDINGS)
table.insert(SHOP_KEYS, "Recycler")

-- Kosten wie im Spiel: Honig-Gebaeude aus BuildingBehavior (Teich mit
-- POND_COST_FACTOR), Recycler aus der Grundkurve (CombConfig.getUpgradeCost).
local function upgradeCost(key, level)
	if key == "Recycler" then
		return EconomyConfig.HONEY_UPGRADE_COSTS[level]
	end
	local def = BuildingBehavior.getUpgrade(key, level)
	return if def then { gummies = def.costGummies, goldGummies = def.costGoldGummies } else nil
end

local function ev(p, kind)
	p.events = p.events or {}
	local last = p.events[#p.events]
	if not last or last.t ~= p.minutes then table.insert(p.events, { t = p.minutes, k = kind }) end
end

local function newLife(p)
	p.levels = { Recycler = 1 }
	for _, id in HONEY_BUILDINGS do p.levels[id] = 1 end
	p.baerchiLevel = 1
	p.baerchiXp = 0
	p.capReached = false
end

local function honeyPerMinute(p)
	local total = 0
	for _, id in HONEY_BUILDINGS do
		total += 60 / BuildingBehavior.getIntervalSeconds(id, p.levels[id])
	end
	return total
end

local function honeyBuildings(p)
	local t = {}
	for _, id in HONEY_BUILDINGS do
		t[id] = { id = id, level = p.levels[id], honey = 0, lastProducedAt = 0 }
	end
	return t
end

local function xpPerHoney(p)
	return BuildingBehavior.getXpPerHoney(honeyBuildings(p))
end

local function maxBuildingLevel(p)
	local best = 0
	for _, level in p.levels do best = math.max(best, level) end
	return best
end

local function levelsText(p)
	local parts = {}
	for _, key in SHOP_KEYS do table.insert(parts, tostring(p.levels[key])) end
	return table.concat(parts, "/")
end

local function gainXp(p, xp)
	p.baerchiXp += xp
	while p.baerchiLevel < BaerchiConfig.MAX_LEVEL and p.baerchiXp >= BaerchiConfig.xpForNextLevel(p.baerchiLevel) do
		p.baerchiXp -= BaerchiConfig.xpForNextLevel(p.baerchiLevel)
		p.baerchiLevel += 1
		ev(p, "baerchi")
	end
	-- Paket 9: mit offenem Endless fliessen die XP ins Endless-Level.
	if p.baerchiLevel >= BaerchiConfig.MAX_LEVEL and TowerConfig.isEndlessOpen(p.records) then
		while p.baerchiXp >= BaerchiConfig.xpForEndlessLevel(p.endless) do
			p.baerchiXp -= BaerchiConfig.xpForEndlessLevel(p.endless)
			p.endless += 1
		end
	elseif p.baerchiLevel >= BaerchiConfig.MAX_LEVEL then
		p.baerchiXp = 0
	end
end

-- Wie viele Stages schafft der Baerchi in diesem Tower? (Aequivalenz-Modell)
local function reach(p, towerId)
	local def = TowerConfig.get(towerId)
	local endless = if p.baerchiLevel >= BaerchiConfig.MAX_LEVEL then p.endless else 0
	local equivalent = p.baerchiLevel + endless + powerBonus(p.minutes / 60)
	if equivalent < def.startEquivalent then return 0 end
	local s = 1 + math.floor((equivalent - def.startEquivalent) / def.equivalentPerStage)
	return math.clamp(s, 0, def.stages)
end

local INCOME_MULT = 1   -- Anti-Speedrun: Spieler mit x-fachem Einkommen (perfektes Spiel)

local function award(p, base)
	local amount = math.floor(base * INCOME_MULT * EconomyConfig.getRebirthMult(p.rebirths))
	p.gummies += amount
	p.earned += amount
end

-- Paket 9: Ist Endless offen und schafft der Baerchi dort mehr als den
-- Rekord, geht der Lauf in den Endless-Tower (Rekord + Meilensteine).
local function doEndlessRun(p)
	if not TowerConfig.isEndlessOpen(p.records) then return false end
	local cleared = reach(p, "Endless")
	local record = p.records.Endless or 0
	if cleared <= record then return false end
	award(p, TowerConfig.sumStageRewards("Endless", 1, cleared))
	for stage = record + 1, cleared do
		local m = TowerConfig.getMilestone("Endless", stage)
		if m then
			p.gummies += m.gummies
			p.endless += m.endlessLevels
		end
	end
	p.records.Endless = cleared
	return true
end

local function doRun(p)
	if doEndlessRun(p) then return end
	-- Erst den Rekord im Deckel-Tower schieben (dafuer spielt man), sonst der
	-- Tower mit dem meisten Ertrag pro Lauf (nur bis zum Deckel bezahlt).
	local bestId, bestGain, bestCleared, bestCap = nil, -1, 0, 0
	local capTowerId, capStageNow = TowerConfig.getCap(p.rebirths)
	local capReach = reach(p, capTowerId)
	if capReach > (p.records[capTowerId] or 0) and (p.records[capTowerId] or 0) < capStageNow then
		local paid = math.min(capReach, capStageNow)
		bestId, bestGain, bestCleared, bestCap = capTowerId, TowerConfig.sumStageRewards(capTowerId, 1, paid), capReach, capStageNow
	end
	for _, def in (if bestId then {} else TowerConfig.TOWERS) do
		-- 08.10.: Rekorde mitgeben (TOWER_UNLOCK_BY_CLEAR: offen = vorherigen
		-- Tower geschafft, Deckel = volle Stage-Zahl)
		local cap = TowerConfig.getStageCap(p.rebirths, def.id, p.records)
		if cap > 0 then
			local cleared = reach(p, def.id)
			local paid = math.min(cleared, cap)
			local gain = TowerConfig.sumStageRewards(def.id, 1, paid)
			-- Bei Gleichstand den hoeheren Tower (Rekord/Look).
			if gain >= bestGain then
				bestId, bestGain, bestCleared, bestCap = def.id, gain, cleared, cap
			end
		end
	end
	if not bestId then return end

	local paid = math.min(bestCleared, bestCap)
	award(p, bestGain)
	p.gold += TowerConfig.getRunGold(bestId, paid)

	-- Rekord + Meilensteine (permanent)
	local record = p.records[bestId] or 0
	if paid > record then
		for stage = record + 1, paid do
			local m = TowerConfig.getMilestone(bestId, stage)
			if m then
				p.gummies += m.gummies
				p.gold += m.goldGummies
			end
		end
		p.records[bestId] = paid
		ev(p, "tower")
		if TowerConfig.getIndex(bestId) > TowerConfig.getIndex(p.highestTower) then
			p.highestTower = bestId
		end
	end

	-- Deckel erreicht? (nur der Deckel-Tower zaehlt fuer den Rebirth-Hinweis)
	local capTower, capStage = TowerConfig.getCap(p.rebirths)
	if (p.records[capTower] or 0) >= capStage then
		p.capReached = true
	end
	if (p.records.Final or 0) >= 100 and not p.final100 then
		p.final100 = p.minutes
	end
end

local function cheapestUpgrade(p)
	local bestKey, bestCost = nil, math.huge
	for _, key in SHOP_KEYS do
		local nextLevel = p.levels[key] + 1
		local cost = upgradeCost(key, nextLevel)
		if cost and cost.gummies / SHOP_WEIGHT[key] < bestCost then
			bestKey, bestCost = key, cost.gummies / SHOP_WEIGHT[key]
		end
	end
	return bestKey
end

local function shop(p)
	for _ = 1, 20 do
		local key = cheapestUpgrade(p)
		if not key then return end
		local cost = upgradeCost(key, p.levels[key] + 1)
		if cost.gummies > p.incomePerMin * PATIENCE_MINUTES then return end
		if p.gummies < cost.gummies or p.gold < cost.goldGummies then return end
		p.gummies -= cost.gummies
		p.gold -= cost.goldGummies
		p.levels[key] += 1
		ev(p, "gebaeude")
		local lvl = p.levels[key]
		-- Looks zaehlen am Honig-Gebaeude (dem Brunnen bzw. Stock/Veredler),
		-- nicht am Recycler: das ist der Fortschritt, den man auf dem Plot sieht.
		for _, threshold in (if table.find(HONEY_BUILDINGS, key) then EconomyConfig.LOOK_THRESHOLDS else {}) do
			if lvl == threshold and not p.lookAt[threshold] then
				p.lookAt[threshold] = p.minutes
			end
		end
	end
end

local function tryRebirth(p)
	if not p.final100 then return end   -- 5a: Rebirth erst nach Welt 2
	if not p.capReached then return end
	local cost = EconomyConfig.getRebirthCost(p.rebirths)
	if p.gummies < cost then return end
	table.insert(p.lives, {
		n = p.rebirths, endMin = p.minutes, cost = cost,
		maxLevel = maxBuildingLevel(p),
		income = p.incomePerMin, baerchi = p.baerchiLevel, gold = p.gold,
		levels = levelsText(p),
	})
	p.rebirths += 1
	p.rebirthAt[p.rebirths] = p.minutes
	p.gummies = EconomyConfig.REBIRTH_START_GUMMIES
	newLife(p)
end

local function loginBonus(p, dayIndex)
	local d = ((dayIndex - 1) % LoginBonusConfig.CYCLE_DAYS) + 1
	local reward = LoginBonusConfig.getDay(d)
	if reward.gummies then award(p, reward.gummies) end
	p.gold += reward.goldGummies or 0
end

-- stopAfterRebirth (optional): Abbruch, sobald so viele Rebirths erreicht sind
-- (fuer die Kalibrierung der Rebirth-Kosten).
local function simulate(profile, stopAfterRebirth)
	local p = {
		minutes = 0, gummies = 100, gold = 0, earned = 0, rebirths = 0, incomePerMin = 0,
		records = {}, highestTower = "I", lookAt = {}, rebirthAt = {}, final100 = nil, lives = {},
		endless = 0,   -- Paket 9: Endless-Level (bleibt ueber Rebirths, newLife fasst es nicht an)
	}
	newLife(p)

	local weekly = {}
	local runTimer, eventTimer, eventCount = 0, 0, 0
	for day = 1, SIM_DAYS do
		loginBonus(p, day)
		-- Offline: beide Lager voll beim Zurueckkommen (wird gegessen).
		local offlineHoney = BuildingBehavior.getTotalCapacity(honeyBuildings(p))
		gainXp(p, offlineHoney * xpPerHoney(p))

		for _ = 1, profile.minutesPerDay do
			p.minutes += 1
			local earnedBefore = p.earned
			gainXp(p, honeyPerMinute(p) * xpPerHoney(p))

			-- Waben -> Recycler (Verarbeitung schnell genug, siehe CombConfig.getSpeed)
			award(p, COMB_UNITS_PER_MIN * CombConfig.getPayPerUnit(p.levels.Recycler))

			runTimer += 1
			while runTimer >= RUN_CYCLE_MINUTES do
				runTimer -= RUN_CYCLE_MINUTES
				doRun(p)
			end

			eventTimer += 1
			if eventTimer >= EVENT_CYCLE_MIN then
				eventTimer -= EVENT_CYCLE_MIN
				eventCount += 1
				if eventCount % 2 == 0 then
					award(p, EventConfig.WASP_QUEEN.GUMMIES_BASE)
					award(p, EventConfig.WASP_QUEEN.COMB_UNITS_BASE * CombConfig.getPayPerUnit(p.levels.Recycler))
				end
			end

			-- Einkommen pro Minute, gleitend ueber ~10 Minuten
			p.incomePerMin = p.incomePerMin * 0.9 + (p.earned - earnedBefore) * 0.1

			tryRebirth(p)
			if stopAfterRebirth and p.rebirths >= stopAfterRebirth then
				return p, weekly
			end
			shop(p)
		end

		if day % 7 == 0 then
			local maxLevel = maxBuildingLevel(p)
			local towerId, record = TowerConfig.bestRecord({ records = p.records, claimed = {}, highestTower = p.highestTower, selected = "I" })
			table.insert(weekly, {
				week = day // 7, rebirths = p.rebirths, tower = towerId, record = record,
				maxLevel = maxLevel, baerchi = p.baerchiLevel, bonus = powerBonus(p.minutes / 60),
				endless = p.endless, endlessRecord = p.records.Endless or 0,
			})
		end
	end
	return p, weekly
end

--------------------------------------------------------------------------------
-- Ausgabe
--------------------------------------------------------------------------------

local function fmtTime(minutes, perDay)
	if not minutes then return "—" end
	local day = math.floor((minutes - 1) / perDay) + 1
	if minutes < 120 then
		return string.format("%d min (Tag %d)", minutes, day)
	end
	return string.format("%.1f h (Tag %d, Wo %d)", minutes / 60, day, (day - 1) // 7 + 1)
end

local normalResult = nil
for _, profile in PROFILES do
	local p, weekly = simulate(profile)
	if profile.name == "Normal" then normalResult = p end
	__log("")
	__log(string.format("=== Profil %s (%d min/Tag) ===", profile.name, profile.minutesPerDay))
	__log("Meilenstein                | aktive Zeit")
	__log("---------------------------+---------------------------")
	for index, threshold in EconomyConfig.LOOK_THRESHOLDS do
		if index > 1 then
			__log(string.format("Look %d (Honig-Gebaeude L%-2d) | %s", index, threshold, fmtTime(p.lookAt[threshold], profile.minutesPerDay)))
		end
	end
	for _, n in { 1, 2, 3, 5, 7, 10, 15 } do
		__log(string.format("Rebirth %-2d                 | %s", n, fmtTime(p.rebirthAt[n], profile.minutesPerDay)))
	end
	__log(string.format("Final-Tower Stage 100      | %s", fmtTime(p.final100, profile.minutesPerDay)))
	__log("")
	__log("Leben | Ende (h) | Dauer (h) | Rebirth-Kosten | " .. table.concat(SHOP_KEYS, "/") .. " | Einkommen/min am Ende | Gold")
	local lastEnd = 0
	for _, life in p.lives do
		__log(string.format("%5d | %8.1f | %9.1f | %14s | %23s | %21s | %d", life.n, life.endMin / 60,
			(life.endMin - lastEnd) / 60, string.format("%.3g", life.cost), life.levels, string.format("%.3g", life.income), life.gold))
		lastEnd = life.endMin
	end
	__log("")
	__log("Woche | Rebirths | bester Tower | Gebaeude max | Baerchi-Lvl | Ausbau-Bonus | Endless-Lvl | Endless-Stage")
	for _, w in weekly do
		__log(string.format("%5d | %8d | %4s / %-3d   | %12d | %11d | %12.0f | %11d | %13d",
			w.week, w.rebirths, w.tower, w.record, w.maxLevel, w.baerchi, w.bonus, w.endless, w.endlessRecord))
	end
	profile.result = p
	profile.weekly = weekly
end

-- Fortschritts-Takt: Abstand zwischen sichtbaren Ereignissen (Gebaeude-Ausbau,
-- Baerchi-Level, neuer Tower-Rekord) in aktiven Minuten, bis Final 100.
__log("")
__log("=== Fortschritts-Takt bis Final 100 (aktive Minuten zwischen Ereignissen) ===")
__log("Profil       | Ereignisse | max Luecke | P95 | Luecken > 10 min | Final 100 nach")
local function gaps(p)
	local limit = p.final100 or p.minutes
	local list, last, big = {}, 0, {}
	for _, e in p.events or {} do
		if e.t > limit then break end
		local g = e.t - last
		table.insert(list, g)
		if g > 10 then table.insert(big, string.format("%d->%d", last, e.t)) end
		last = e.t
	end
	table.sort(list)
	local p95 = list[math.max(1, math.floor(#list * 0.95))] or 0
	return #list, list[#list] or 0, p95, big
end
for _, profile in PROFILES do
	local n, mx, p95, big = gaps(profile.result)
	__log(string.format("%-12s | %10d | %10d | %3d | %3d %s | %s", profile.name, n, mx, p95, #big,
		table.concat(table.move(big, 1, math.min(#big, 6), 1, {}), " "), fmtTime(profile.result.final100, profile.minutesPerDay)))
end

-- Anti-Speedrun: wie schnell ist Final 100 bei x-fachem Einkommen (Profil Viel)?
__log("")
__log("=== Anti-Speedrun (Profil Viel, 240 min/Tag) ===")
__log("Einkommen | Look 4 (h) | Look 5 (h) | Look 6 (h) | Final 100 (h) | Tage")
local function hours(m) return if m then string.format("%.1f", m / 60) else "nie" end
local srFinal = {}
for _, mult in { 1, 1.5, 2, 3 } do
	INCOME_MULT = mult
	local p = simulate({ name = "Viel", minutesPerDay = 240 })
	srFinal[mult] = p.final100
	__log(string.format("x%-8.1f | %10s | %10s | %10s | %13s | %s", mult, hours(p.lookAt[30]), hours(p.lookAt[45]),
		hours(p.lookAt[60]), hours(p.final100), if p.final100 then string.format("%.1f", p.final100 / 240) else "-"))
end
INCOME_MULT = 1

-- Gate-Pruefung (kein FAIL fuer Pacing-Ziele des alten Modells, nur harte Aussagen)
local fails = 0
local function check(name, ok) if ok then __log("ok  ", name) else fails += 1; __log("FAIL", name) end end
__log("")
for _, profile in PROFILES do
	check(profile.name .. ": kein Rebirth vor Final 100", (profile.result.rebirthAt[1] or 1e9) >= (profile.result.final100 or 1e9))
end
check("Speedrun x3 erreicht Final 100 nicht vor 1/4 der Normalzeit", srFinal[3] == nil or srFinal[1] == nil or srFinal[3] >= srFinal[1] / 4)
__log(fails == 0 and "ALLE ZIELE OK" or ("ZIELE VERFEHLT: " .. fails))
