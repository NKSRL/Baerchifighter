--!strict
-- BossBalance.luau
-- ReplicatedStorage/Modules/BossBalance.luau
--
-- Einzige Zustaendigkeit:
--   - Die Zahlen des Boss-Events rechnen: Schaden pro Sekunde eines Baerchis,
--     Boss-HP aus Spielerzahl und mittlerer Staerke, Belohnung nach
--     Schadensanteil.
--
-- KEINE eigene Schadensformel: die DPS eines Baerchis kommt aus dem echten
-- Kampfmodell (CombatCalculator.simulate mit seinen effektiven Werten inkl.
-- Level, Promotion, Charms, Rarity, Mutation, Faehigkeit). Gegner ist ein
-- Trainings-Dummy mit DUMMY_HP_FACTOR x den eigenen HP: so bleiben Faehigkeiten,
-- die sich an den Gegner-HP orientieren (Drain, Finisher, Sofort-Sieg), in
-- derselben Groessenordnung wie im PIT statt gegen eine Million HP zu explodieren.
--
-- Reine Mathe, kein Zustand: EventHandlers (WaspQueen) und
-- tools/sim/boss_balance.lua benutzen dasselbe Modul. Alle Stellschrauben in
-- EventConfig.WASP_QUEEN.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventConfig      = require(ReplicatedStorage.Config.EventConfig)
local CombatCalculator = require(ReplicatedStorage.Modules.CombatCalculator)

local BossBalance = {}

-- Trainings-Dummy (Messaufbau, kein Balancing-Wert): eigene HP x Faktor,
-- schlaegt kaum zurueck, damit der Baerchi die volle Zeit austeilt.
local DUMMY_HP_FACTOR = 4
local DUMMY_SPD       = 0.2
local DPS_RUNS        = 5

-- Schaden pro Sekunde eines Baerchis mit diesen effektiven Werten
-- (CombatCalculator.getEffectiveStats). Mittel ueber DPS_RUNS Kaempfe.
function BossBalance.dpsFromStats(stats: CombatCalculator.FighterStats): number
	local total, seconds = 0, 0
	for _ = 1, DPS_RUNS do
		local dummyHp = math.max(1, stats.maxHp * DUMMY_HP_FACTOR)
		local me: CombatCalculator.CombatSnapshot = { uid = "me", stats = stats, hp = stats.maxHp, charge = 0 }
		local dummy: CombatCalculator.CombatSnapshot = {
			uid = "dummy",
			stats = { maxHp = dummyHp, atk = 1, spd = DUMMY_SPD, pwr = 0, skillId = "BasicPunch" },
			hp = dummyHp,
			charge = 0,
		}
		local result = CombatCalculator.simulate(me, dummy, false)
		total   += dummyHp - math.max(0, dummy.hp)
		seconds += math.max(1, result.rounds) / math.max(0.1, stats.spd)
	end
	return if seconds > 0 then total / seconds else 0
end

-- v15: Faktor nach dem hoechsten Tower-Index der Teilnehmer (1-4). Hook fuer
-- spaeter — EventConfig.WASP_QUEEN.TOWER_HP_FACTOR steht ueberall auf 1.
function BossBalance.towerHpFactor(highestTowerIndex: number?): number
	local list = EventConfig.WASP_QUEEN.TOWER_HP_FACTOR
	local index = math.clamp(math.floor(highestTowerIndex or 1), 1, #list)
	return list[index] or 1
end

-- Boss-HP beim Kampfbeginn: Spieler x mittlere DPS x Zielzeit x Faktor.
-- `highestTowerIndex` (v15, optional): siehe towerHpFactor.
-- (Spieler x mittlere DPS ist die Summe der DPS; so steht es aber in der
-- Form, in der man es einstellt.)
function BossBalance.bossHp(dpsList: { number }, highestTowerIndex: number?): number
	local cfg = EventConfig.WASP_QUEEN
	local n = #dpsList
	if n == 0 then
		return cfg.MIN_HP
	end
	local sum = 0
	for _, dps in dpsList do
		sum += dps
	end
	local mean = sum / n
	local towerFactor = BossBalance.towerHpFactor(highestTowerIndex)
	return math.max(cfg.MIN_HP, math.floor(n * mean * cfg.TARGET_FIGHT_SECONDS * cfg.HP_FACTOR * towerFactor))
end

-- Zusaetzliche HP, wenn ein Baerchi erst `elapsed` Sekunden nach
-- Kampfbeginn dazukommt (er soll den Kampf nicht verkuerzen).
function BossBalance.lateJoinHp(dps: number, elapsed: number): number
	local cfg = EventConfig.WASP_QUEEN
	local rest = math.max(cfg.LATE_JOIN_MIN_SECONDS, cfg.TARGET_FIGHT_SECONDS - elapsed)
	return math.floor(dps * rest * cfg.HP_FACTOR)
end

export type Payout = {
	share     : number,    -- Anteil am Gesamtschaden (0..1)
	rank      : number,    -- 1 = meister Schaden
	qualified : boolean,   -- ueber MIN_DAMAGE_SHARE
	gummies   : number,    -- Basisbetrag (EconomyService wendet den Rebirth-Multiplikator an)
	combUnits : number,
	top       : boolean,   -- unter den TOP_RANKS: Sprung-Ei + Rarity-Up-Wurf
	victoryEgg: boolean,   -- Sieg: hoechstes Ei (bzw. Jackpot)
}

-- Belohnung je Teilnehmer aus seinem Schaden. `damage` = { [key] = Schaden }
-- (key = Player im Spiel, beliebig in der Simulation).
function BossBalance.payouts(damage: { [any]: number }, victory: boolean): { [any]: Payout }
	local cfg = EventConfig.WASP_QUEEN
	local total = 0
	local keys: { any } = {}
	for key, dmg in damage do
		total += math.max(0, dmg)
		table.insert(keys, key)
	end
	table.sort(keys, function(a: any, b: any): boolean
		return (damage[a] or 0) > (damage[b] or 0)
	end)

	local result: { [any]: Payout } = {}
	if total <= 0 then
		return result
	end

	local n = #keys
	for rank, key in keys do
		local share = math.max(0, damage[key] or 0) / total
		local qualified = share >= cfg.MIN_DAMAGE_SHARE
		local factor = math.clamp(share * n, cfg.SHARE_FACTOR_MIN, cfg.SHARE_FACTOR_MAX)
		local outcome = if victory then 1 else cfg.DEFEAT_FACTOR

		result[key] = {
			share      = share,
			rank       = rank,
			qualified  = qualified,
			gummies    = if qualified then math.floor(cfg.GUMMIES_BASE * factor * outcome) else 0,
			combUnits  = if qualified then math.floor(cfg.COMB_UNITS_BASE * factor * outcome) else 0,
			top        = qualified and victory and rank <= cfg.TOP_RANKS,
			victoryEgg = qualified and victory,
		}
	end
	return result
end

return BossBalance
