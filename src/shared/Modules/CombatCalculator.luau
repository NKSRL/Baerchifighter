--!strict
-- CombatCalculator.luau
-- ReplicatedStorage/Modules/CombatCalculator.luau
--
-- Reine Funktionen fuer Kampfberechnungen.
-- Kein State, keine Services — nur Mathe.
-- Kann einfach unit-getestet werden.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SkillConfig     = require(ReplicatedStorage.Config.SkillConfig)
local BaerchiConfig   = require(ReplicatedStorage.Config.BaerchiConfig)
local PromotionConfig = require(ReplicatedStorage.Config.PromotionConfig)
local CharmConfig     = require(ReplicatedStorage.Config.CharmConfig)
local Types           = require(ReplicatedStorage.Network.Types)

local CombatCalculator = {}

-- ============================================================
-- ES GIBT KEINE VERTEIDIGUNG
-- ============================================================
-- Frueher hatte jeder Kaempfer einen DEF-Wert, der eingehenden Schaden
-- prozentual reduzierte. Der ist ersatzlos entfallen: ein Treffer macht genau
-- so viel Schaden, wie der Angreifer ATK hat. Wer einen Tank will, baut einen
-- Baerchi mit viel HP.
--
-- Das ist eine bewusste Entscheidung fuer ein einfaches Spiel, keine
-- Vereinfachung aus Versehen. Wer hier wieder eine Reduktion einbauen will:
-- die Stelle ist calcDamage, und die HP-Grundwerte in BaerchiConfig muessten
-- dann zurueckgerechnet werden (dort steht, wie sie entstanden sind).
export type FighterStats = {
	maxHp  : number,
	atk    : number,
	spd    : number,

	-- Ability-Staerke als Anteil (0.20 = +20% Skill-Schaden). Wirkt
	-- ausschliesslich auf den SKILL-Anteil einer Runde, nie auf den Grundschlag
	-- (calcDamage) — siehe applySkill weiter unten.
	--
	-- Eine Feinheit, die man kennen sollte: BasicPunch ist als Skill mit
	-- Multiplikator 1.0 und Cooldown 0 modelliert, ist also technisch eine
	-- Ability. Ein Baerchi mit BasicPunch bekommt seine PWR deshalb in JEDER
	-- Runde als Aufschlag, waehrend ein Baerchi mit ShardBlast (Cooldown 3)
	-- sie nur alle vier Runden sieht. Das ist Absicht und kein Versehen: der
	-- Grundschlag-Baerchi hat dafuer keinen Ausschlag nach oben, der
	-- Skill-Baerchi schon.
	pwr    : number,

	skillId: string,
}

export type CombatSnapshot = {
	uid    : string,
	stats  : FighterStats,
	hp     : number,     -- aktuell
	-- v15: Aufladung der Faehigkeit in "Stoessen" (siehe SkillConfig.CHARGE).
	-- Bleibt ueber die Stages eines Laufs erhalten, deshalb im Snapshot.
	charge : number,
}

-- Wachstumsfaktor eines Levels: +10% pro Level auf den Vorwert, also
-- exponentiell (siehe BaerchiConfig.STAT_GROWTH_PER_LEVEL). Level 1 = 1.0.
-- Oeffentlich, weil die PIT-Gegner mit derselben Kurve skalieren muessen —
-- zwei getrennte Formeln wuerden beim naechsten Balancing auseinanderlaufen.
function CombatCalculator.getLevelGrowth(level: number): number
	return math.pow(1 + BaerchiConfig.STAT_GROWTH_PER_LEVEL, math.max(level, 1) - 1)
end

-- Alle Charm-Boni eines Baerchis, aufsummiert nach Ziel-Stat.
--
-- Getrennt nach `percent` (Faktor, multipliziert sich auf den Basiswert) und
-- `flat` (wird direkt addiert) — welcher Typ was ist, steht in
-- CharmConfig.STAT_POOL, nicht hier.
--
-- Gleiche Typen addieren sich einfach: acht Slots mit je +1.4% HP ergeben
-- +11.2%, nicht 1.014^8. Das ist die einfachere und vorhersagbarere Variante,
-- und bei acht Slots ist der Unterschied ohnehin klein.
type CharmTotals = {
	percent : { hp: number, atk: number, spd: number, pwr: number },
	flat    : { hp: number, atk: number, spd: number, pwr: number },
}

local function sumCharms(baerchi: Types.Baerchi): CharmTotals
	local totals: CharmTotals = {
		percent = { hp = 0, atk = 0, spd = 0, pwr = 0 },
		flat    = { hp = 0, atk = 0, spd = 0, pwr = 0 },
	}

	local charms = baerchi.charms
	if not charms then
		return totals
	end

	for _, charm in charms do
		-- Ein Charm in einem Slot, der durch einen spaeteren Datenstand nicht
		-- mehr freigeschaltet waere, zaehlt bewusst NICHT mit: die Freischaltung
		-- ist die einzige Bremse des Systems, und sie muss auch dann greifen,
		-- wenn ein Spielstand aus irgendeinem Grund mehr Charms enthaelt als
		-- der Promotions-Stand erlaubt.
		if CharmConfig.isSlotUnlocked(charm.slot, baerchi.promotionLevel or 0) then
			local statDef = CharmConfig.getStatDef(charm.statId)
			if statDef then
				local bucket = if statDef.mode == "percent" then totals.percent else totals.flat
				bucket[statDef.target] += charm.value or 0
			end
		end
	end

	return totals
end

-- Berechnet effektive Stats eines Bärchis auf seinem Level.
--
-- ============================================================
-- DIE FUENF MULTIPLIKATOREN AUF HP/ATK — REIHENFOLGE UND WARUM
-- ============================================================
--   1. Level-Wachstum   (getLevelGrowth, exponentiell)
--   2. Fusions-Bonus    (Baerchi.fusionBonus, gesetzt von FusionService)
--   3. Promotions-Bonus (+2% je Stufe, PromotionConfig)
--   4. Stat-Level-Bonus (+4% je Stufe, waechst durch Event-Teilnahme)
--   5. Charm-Bonus      (Summe aller ausgeruesteten Charms)
--
-- Alle fuenf multiplizieren sich, weil jeder eine EIGENE Fortschrittsachse ist:
-- wer beides betreibt (fuettern UND Events), soll den Nutzen von beidem sehen.
-- Addierte Faktoren wuerden die spaetere Achse jeweils entwerten.
--
-- Der MUTATIONS-Bonus (BaerchiConfig.getMutationBonus, seit v11 an die Stelle
-- des frueheren binaeren INVERTED_BONUS getreten) kommt VOR allem anderen: er
-- wirkt auf den Basiswert, nicht auf das Ergebnis. Dadurch bedeutet z.B.
-- "+150% HP" (Diamond) wirklich 150% mehr, egal auf welchem Level oder mit
-- welchen Charms der Baerchi gerade steht — und nicht mal mehr, mal weniger.
--
-- SPD und PWR bekommen bewusst KEINEN Prozentbonus aus Level/Fusion/Promotion,
-- sondern nur flache Zugaben. Der Grund steht in BaerchiConfig bei
-- SPD_PER_LEVEL / PWR_PER_LEVEL: PWR multipliziert bereits den Skill-Schaden,
-- der seinerseits am exponentiell wachsenden ATK haengt.
--
-- ============================================================
-- baseStatOverride
-- ============================================================
-- Basiswerte kommen normalerweise aus `baseDef` (das ist
-- BaerchiConfig.data[configId].baseStats, der Aufrufer reicht es herein). Ein
-- FUSIONS-Ergebnis kann aber per Stat hoehere Basiswerte geerbt haben, als sein
-- eigener configId hergibt (siehe FusionService, Regel 1) — dafuer, und NUR
-- dafuer, gibt es Baerchi.baseStatOverride. Fuer jeden anderen Baerchi ist das
-- Feld nil.
function CombatCalculator.getEffectiveStats(baerchi: Types.Baerchi, baseDef: { [string]: any }): FighterStats
	local level  = baerchi.level
	local growth = CombatCalculator.getLevelGrowth(level)

	-- 1. Basiswerte: Override schlaegt Config, wo gesetzt.
	local override = baerchi.baseStatOverride
	local baseHp   = (override and override.hp)  or baseDef.hp
	local baseAtk  = (override and override.atk) or baseDef.atk
	local baseSpd  = (override and override.spd) or baseDef.spd
	local basePwr  = (override and override.pwr) or baseDef.pwr or 0

	-- 2. Mutation: wirkt direkt auf die Basiswerte, vor allem anderen.
	-- getMutationBonus liefert fuer baerchi.mutation == nil einen Nullbonus,
	-- die Multiplikation unten ist deshalb ohne Sonderfall immer korrekt.
	local mutationBonus = BaerchiConfig.getMutationBonus(baerchi.mutation)
	baseHp  *= (1 + mutationBonus.hp)
	baseAtk *= (1 + mutationBonus.atk)
	baseSpd *= (1 + mutationBonus.spd)
	basePwr *= (1 + mutationBonus.pwr)

	-- 3. Die prozentualen Zuschlaege ausserhalb des Levels.
	local fusionBonus    = 1 + (baerchi.fusionBonus or 0)
	local promotionBonus = 1 + PromotionConfig.getPromotionBonus(baerchi.promotionLevel or 0)

	local statLevels = baerchi.statLevels
	local hpLevels   = if statLevels then (statLevels.hp  or 0) else 0
	local atkLevels  = if statLevels then (statLevels.atk or 0) else 0
	local spdLevels  = if statLevels then (statLevels.spd or 0) else 0
	local pwrLevels  = if statLevels then (statLevels.pwr or 0) else 0

	local hpStatBonus  = 1 + hpLevels  * PromotionConfig.STAT_LEVEL_GAIN.hp
	local atkStatBonus = 1 + atkLevels * PromotionConfig.STAT_LEVEL_GAIN.atk

	-- 4. Charms.
	local charms = sumCharms(baerchi)

	local maxHp = baseHp * growth * fusionBonus * promotionBonus * hpStatBonus
		* (1 + charms.percent.hp) + charms.flat.hp

	local atk = baseAtk * growth * fusionBonus * promotionBonus * atkStatBonus
		* (1 + charms.percent.atk) + charms.flat.atk

	local spd = baseSpd
		+ (level - 1) * BaerchiConfig.SPD_PER_LEVEL
		+ spdLevels * PromotionConfig.STAT_LEVEL_GAIN.spd
		+ charms.flat.spd

	local pwr = basePwr
		+ (level - 1) * BaerchiConfig.PWR_PER_LEVEL
		+ pwrLevels * PromotionConfig.STAT_LEVEL_GAIN.pwr
		+ charms.flat.pwr

	return {
		-- math.max(1, ...): ein Baerchi mit 0 maxHp waere sofort und dauerhaft
		-- erschoepft und liesse sich auch nicht mehr hochfuettern.
		maxHp   = math.max(1, math.floor(maxHp)),
		atk     = math.max(1, math.floor(atk)),
		spd     = spd * (1 + charms.percent.spd),

		-- PWR darf nicht negativ werden (ein Skill soll nie heilen statt zu
		-- schaden), nach oben ist es bewusst offen: es multipliziert nur den
		-- Skill-Anteil, und dessen Cooldown begrenzt ihn ohnehin.
		pwr     = math.max(0, pwr * (1 + charms.percent.pwr)),

		skillId = baerchi.skillId,
	}
end

-- Schaden eines normalen Schlags.
--
-- Seit dem DEF-Ausbau ist das schlicht der ATK-Wert — es gibt nichts mehr, was
-- ihn reduziert. Die Funktion bleibt trotzdem stehen: sie ist die eine Stelle,
-- an der "was macht ein Treffer" beantwortet wird.
local function calcDamage(atk: number): number
	return math.max(1, math.floor(atk))
end

-- ============================================================
-- DIE ABILITY-FORMEL
-- ============================================================
--     Skill-Schaden = (ATK x Skill-Multiplikator + Skill-Basisschaden)
--                     x (1 + PWR)
--
-- Gibt den BONUS ueber den normalen Schlag zurueck (der Aufrufer rechnet
-- calcDamage(atk) + bonus). Ein Skill, der schwaecher waere als ein normaler
-- Schlag, gibt 0 Bonus statt eines negativen Werts.
local function skillDamage(atk: number, pwr: number, multiplier: number, baseDamage: number): number
	local raw = (atk * multiplier + baseDamage) * (1 + pwr)
	return math.max(0, math.floor(raw) - calcDamage(atk))
end

-- ============================================================
-- v14: RUNDENKAMPF MIT SPD UND STATUS-EFFEKTEN
-- ============================================================
-- Bis v13 schlugen beide Seiten strikt abwechselnd zu, SPD wurde nie
-- ausgewertet, und Shield/SpeedBuff/DoT/AoE setzten nur ihren Cooldown.
--
-- Jetzt laeuft der Kampf auf einer ZEITACHSE: jeder Kaempfer handelt alle
-- 1/SPD Sekunden. Wer doppelt so schnell ist, handelt doppelt so oft. Bei
-- Gleichstand handelt A (der Baerchi) zuerst — damit ist ein Kampf zweier
-- gleich schneller Kaempfer exakt der alte Wechsel.
--
-- Eine AKTION des Kaempfers X gegen Y:
--   1. Ist X betaeubt, verfaellt die Aktion (nur die Betaeubung endet).
--   2. Brennt X (DoT von Y), nimmt er zuerst den Brand-Schaden.
--   3. Cooldown von X zaehlt eins runter; steht er auf 0, setzt X seinen
--      Skill ein (sonst nur der normale Schlag).
--   4. Schaden trifft Y — ein Schild von Y faengt seinen Anteil ab, die
--      Letzte Chance von Y kann ihn mit 1 HP retten.
--   5. Alle Status, die X TRAEGT, zaehlen eine Aktion runter.
--   6. Naechste Aktion von X in 1 / (SPD x Buff x Verlangsamung) Sekunden.
--
-- Die Dauer eines Status zaehlt also die Aktionen dessen, der ihn traegt.
-- Ein Status, der in dieser Aktion erst entstanden ist, zaehlt in ihr nicht.

-- Ein Eintrag im Runden-Log (serverseitig). Der Client bekommt davon nur die
-- Zusammenfassung je Stage (PitStageResult.skillUses), siehe Types.
export type ActionLog = Types.RoundLogEntry

type Timed = { left: number, fresh: boolean }

type Fighter = {
	snap      : CombatSnapshot,
	tag       : string,          -- "A" | "B"
	nextAt    : number,
	actions   : number,
	stunned   : boolean,
	dot       : { perTick: number, left: number }?,
	shield    : (Timed & { absorb: number })?,
	slow      : (Timed & { mult: number })?,
	weaken    : (Timed & { mult: number })?,
	buff      : (Timed & { spdMult: number, pwrAdd: number, atkMult: number })?,
	lastStand : boolean,          -- hat (noch) eine Letzte Chance
	burst     : number,           -- ausstehender Feuerstoss (Schaden)
	rampUses  : number,
	opened    : boolean,
	skillUses : number,
}

local function newFighter(snap: CombatSnapshot, tag: string): Fighter
	local skill = SkillConfig.getById(snap.stats.skillId)
	local hasLastStand = skill ~= nil and (skill.effectType == "LastStand" or skill.effectType == "Revive")
	return {
		snap      = snap,
		tag       = tag,
		nextAt    = 0,
		actions   = 0,
		stunned   = false,
		dot       = nil,
		shield    = nil,
		slow      = nil,
		weaken    = nil,
		buff      = nil,
		lastStand = hasLastStand,
		burst     = 0,
		rampUses  = 0,
		opened    = false,
		skillUses = 0,
	}
end

local function effSpd(f: Fighter): number
	local spd = math.max(0.1, f.snap.stats.spd)
	if f.buff then spd *= f.buff.spdMult end
	if f.slow then spd *= f.slow.mult end
	return math.max(0.1, spd)
end

local function effAtk(f: Fighter): number
	local atk = f.snap.stats.atk
	if f.buff then atk *= f.buff.atkMult end
	if f.weaken then atk *= f.weaken.mult end
	return math.max(1, atk)
end

local function effPwr(f: Fighter): number
	local pwr = f.snap.stats.pwr
	if f.buff then pwr += f.buff.pwrAdd end
	return math.max(0, pwr)
end

-- Schaden auf `target` anwenden. Gibt (wirklich abgezogen, abgefangen,
-- Letzte-Chance-ausgeloest) zurueck.
local function dealDamage(target: Fighter, amount: number): (number, number, boolean)
	if amount <= 0 or target.snap.hp <= 0 then
		return 0, 0, false
	end

	local absorbed = 0
	if target.shield then
		absorbed = math.floor(amount * target.shield.absorb)
		amount -= absorbed
	end

	local before = target.snap.hp
	local after  = before - amount
	local saved  = false

	if after <= 0 and target.lastStand then
		target.lastStand = false
		saved = true
		local skill = SkillConfig.getById(target.snap.stats.skillId)
		if skill and skill.effectType == "Revive" then
			after = math.max(1, math.floor(target.snap.stats.maxHp * (skill.params.reviveHpPercent or 0.5)))
		else
			after = 1
			-- Phoenix-Glut: der Feuerstoss kommt mit der naechsten eigenen Aktion.
			if skill then
				target.burst = skillDamage(effAtk(target), effPwr(target),
					skill.params.burstMultiplier or 2, skill.params.baseDamage or 0) + calcDamage(effAtk(target))
			end
		end
	end

	target.snap.hp = math.max(0, after)
	return before - target.snap.hp, absorbed, saved
end

local function tickTimed(t: Timed?): Timed?
	if not t then return nil end
	if t.fresh then
		t.fresh = false
		return t
	end
	t.left -= 1
	if t.left <= 0 then return nil end
	return t
end

-- Fuehrt EINE Aktion von x gegen y aus und gibt den Log-Eintrag zurueck.
local function act(x: Fighter, y: Fighter, round: number, a: Fighter, b: Fighter): ActionLog
	local entry: ActionLog = {
		roundNumber     = round,
		actor           = x.tag,
		kind            = "hit",
		chargeA         = 0,
		skillUsed       = false,
		skillId         = nil,
		damage          = 0,
		heal            = 0,
		absorbed        = 0,
		effects         = nil,
		attackerHpAfter = 0,
		defenderHpAfter = 0,
	}
	local effects: { string } = {}

	x.actions += 1

	if x.stunned then
		x.stunned = false
		table.insert(effects, "stunned")
		entry.kind = "stunned"
	else
		-- Brand
		if x.dot then
			local burnt = dealDamage(x, x.dot.perTick)
			table.insert(effects, "burn:" .. burnt)
			x.dot.left -= 1
			if x.dot.left <= 0 then x.dot = nil end
		end

		if x.snap.hp > 0 then
			local atk = effAtk(x)
			local pwr = effPwr(x)
			local dmg = calcDamage(atk)
			local heal = 0
			local selfCost = 0

			-- Ausstehender Feuerstoss (Letzte Chance) ersetzt den Schlag.
			if x.burst > 0 then
				dmg = x.burst
				x.burst = 0
				table.insert(effects, "laststand_burst")
				entry.skillUsed = true
				entry.skillId = x.snap.stats.skillId
				entry.kind = "burst"
			end

			-- ============================================================
			-- v15: STOSS ODER FAEHIGKEIT
			-- ============================================================
			-- Normalfall: ein STOSS (Grundschaden = ATK), der die Faehigkeit
			-- laedt. Ist sie voll geladen, ist dieser Zug die Faehigkeit.
			local skill = SkillConfig.getById(x.snap.stats.skillId)
			local cost = if skill then (skill.charge or 0) else 0
			local canCharge = skill ~= nil and cost > 0 and skill.effectType ~= "Passive"
				and skill.effectType ~= "LastStand" and skill.effectType ~= "Revive"

			if entry.kind ~= "burst" and skill and cost <= 0 and skill.effectType == "Damage" then
				-- Grundschlag-Baerchi (BasicPunch): keine eigene Faehigkeit, dafuer
				-- bekommt JEDER Stoss den PWR-Aufschlag (wie bisher).
				dmg += skillDamage(atk, pwr, skill.params.multiplier or 1, skill.params.baseDamage or 0)
			elseif entry.kind ~= "burst" and canCharge and skill and (x.snap.charge or 0) >= cost then
				local p = skill.params
				local base = p.baseDamage or 0
				local et = skill.effectType
				local used = true

				if et == "Damage" then
					dmg += skillDamage(atk, pwr, p.multiplier or 1, base)
				elseif et == "AoeDamage" then
					dmg += skillDamage(atk, pwr, p.damageMultiplier or 1, base)
				elseif et == "Heal" then
					heal = math.floor(x.snap.stats.maxHp * (p.healPercent or 0))
				elseif et == "Drain" then
					local drained = math.floor(y.snap.hp * (p.drainPercent or 0) * (1 + pwr))
					drained = math.min(drained, y.snap.hp)
					dmg += drained
					heal = drained
				elseif et == "Stun" then
					dmg += skillDamage(atk, pwr, p.damageMultiplier or 1, base)
					y.stunned = true
					table.insert(effects, "stun")
				elseif et == "InstantKill" then
					if math.random() < (p.chance or 0) then
						dmg += y.snap.hp
						table.insert(effects, "instakill")
					else
						dmg += skillDamage(atk, pwr, p.fallbackMultiplier or 1, base)
					end
				elseif et == "Shield" then
					x.shield = { absorb = p.absorbPercent or 0, left = p.duration or 1, fresh = true }
					table.insert(effects, "shield")
				elseif et == "SpeedBuff" then
					x.buff = { spdMult = p.speedMult or 1, pwrAdd = 0, atkMult = 1, left = p.duration or 1, fresh = true }
					table.insert(effects, "buff")
				elseif et == "SelfBuff" then
					x.buff = {
						spdMult = p.spdMult or 1, pwrAdd = p.pwrAdd or 0, atkMult = p.atkMult or 1,
						left = p.duration or 1, fresh = true,
					}
					selfCost = math.floor(x.snap.stats.maxHp * (p.hpCost or 0))
					table.insert(effects, "buff")
				elseif et == "Slow" then
					y.slow = { mult = 1 - (p.slowPercent or 0), left = p.duration or 1, fresh = false }
					table.insert(effects, "slow")
				elseif et == "Weaken" then
					y.weaken = { mult = 1 - (p.atkReduce or 0), left = p.duration or 1, fresh = false }
					table.insert(effects, "weaken")
				elseif et == "DoT" then
					dmg += skillDamage(atk, pwr, p.multiplier or 1, base)
					local perTick = math.floor(((p.dotDamage or 0) + atk * (p.dotMultiplier or 0)) * (1 + pwr))
					y.dot = { perTick = math.max(1, perTick), left = p.dotDuration or 1 }
					table.insert(effects, "dot")
				elseif et == "Finisher" then
					local ratio = y.snap.hp / math.max(1, y.snap.stats.maxHp)
					local mult = if ratio < (p.threshold or 0.3) then (p.finisherMultiplier or 1) else (p.multiplier or 1)
					if ratio < (p.threshold or 0.3) then table.insert(effects, "finisher") end
					dmg += skillDamage(atk, pwr, mult, base)
				elseif et == "Opener" then
					local mult = if x.opened then (p.multiplier or 1) else (p.openerMultiplier or 1)
					if not x.opened then table.insert(effects, "opener") end
					x.opened = true
					dmg += skillDamage(atk, pwr, mult, base)
				elseif et == "Ramp" then
					local mult = (p.multiplier or 1) + (p.rampPerUse or 0) * x.rampUses
					x.rampUses += 1
					dmg += skillDamage(atk, pwr, mult, base)
				elseif et == "MultiHit" then
					local hits = math.max(1, math.floor(p.hits or 1))
					local per = (atk * (p.multiplierPerHit or 1) + base) * (1 + pwr)
					dmg = math.max(dmg, math.floor(per * hits))
					table.insert(effects, "hits:" .. hits)
				else
					used = false
				end

				if used then
					x.snap.charge = math.max(0, (x.snap.charge or 0) - cost)
					x.skillUses += 1
					entry.skillUsed = true
					entry.skillId = skill.id
					entry.kind = "skill"
				end
			end

			-- Ein normaler Stoss laedt die Faehigkeit auf.
			if entry.kind == "hit" and canCharge then
				local gain = SkillConfig.CHARGE.PER_HIT * (1 + pwr * SkillConfig.CHARGE.PWR_FACTOR)
				x.snap.charge = math.min(cost, (x.snap.charge or 0) + gain)
			end

			local dealt, absorbed, saved = dealDamage(y, dmg)
			entry.damage   = dealt
			entry.absorbed = absorbed
			if saved then
				table.insert(effects, "laststand")
				-- Die Letzte Chance IST der Skill des Getroffenen: zaehlt als Einsatz.
				y.skillUses += 1
			end

			if heal > 0 then
				local before = x.snap.hp
				x.snap.hp = math.min(x.snap.stats.maxHp, x.snap.hp + heal)
				entry.heal = x.snap.hp - before
			end

			if selfCost > 0 then
				-- Der Preis eines Buffs darf nie selbst toeten.
				x.snap.hp = math.max(1, x.snap.hp - selfCost)
			end
		end
	end

	-- Status des Handelnden laufen ab.
	x.shield = tickTimed(x.shield) :: any
	x.buff   = tickTimed(x.buff) :: any
	x.slow   = tickTimed(x.slow) :: any
	x.weaken = tickTimed(x.weaken) :: any

	x.nextAt += 1 / effSpd(x)

	entry.attackerHpAfter = a.snap.hp
	entry.defenderHpAfter = b.snap.hp
	-- Ladestand von A (0..1) fuer die Ladeleiste in der Arena.
	do
		local sk = SkillConfig.getById(a.snap.stats.skillId)
		local c = if sk then (sk.charge or 0) else 0
		entry.chargeA = if c > 0 then math.clamp((a.snap.charge or 0) / c, 0, 1) else 0
	end
	if #effects > 0 then entry.effects = effects end
	return entry
end

export type FullCombatResult = {
	winnerUid   : string,
	loserUid    : string,
	rounds      : number,           -- Aktionen des Baerchis (A)
	log         : { Types.RoundLogEntry },
	skillUses   : number,           -- wie oft A seinen Skill eingesetzt hat
	firstSkillRound : number?,      -- in welcher Runde (A-Aktion) zum ersten Mal
}

-- Schutz vor Endlos-Kaempfen (z.B. zwei Heiler). Bei Erreichen gewinnt, wer
-- mehr HP hat — dieselbe Regel wie vorher bei MAX_ROUNDS = 50.
local MAX_A_ACTIONS     = 50
local MAX_TOTAL_ACTIONS = 200

-- Simuliert einen vollstaendigen Kampf zwischen zwei Baerchis.
-- Gibt das Ergebnis zurueck — kein Side-Effect ausser auf den Snapshots
-- (hp/charge, wie bisher hp/skillCooldown).
--
-- `withLog = false` spart den Log (Massensimulationen in tools/sim).
function CombatCalculator.simulate(a: CombatSnapshot, b: CombatSnapshot, withLog: boolean?): FullCombatResult
	local log: { Types.RoundLogEntry } = {}
	local fa = newFighter(a, "A")
	local fb = newFighter(b, "B")
	local total = 0
	local firstSkill: number? = nil

	while a.hp > 0 and b.hp > 0 and fa.actions < MAX_A_ACTIONS and total < MAX_TOTAL_ACTIONS do
		total += 1
		local entry
		local usesBefore = fa.skillUses
		if fa.nextAt <= fb.nextAt then
			entry = act(fa, fb, fa.actions + 1, fa, fb)
		else
			entry = act(fb, fa, fa.actions, fa, fb)
		end
		if fa.skillUses > usesBefore and not firstSkill then
			firstSkill = math.max(1, fa.actions)
		end
		if withLog ~= false then
			table.insert(log, entry)
		end
	end

	local winnerUid, loserUid
	if a.hp >= b.hp then
		winnerUid, loserUid = a.uid, b.uid
	else
		winnerUid, loserUid = b.uid, a.uid
	end

	return {
		winnerUid = winnerUid,
		loserUid  = loserUid,
		rounds    = fa.actions,
		log       = log,
		skillUses = fa.skillUses,
		firstSkillRound = firstSkill,
	}
end

return CombatCalculator
