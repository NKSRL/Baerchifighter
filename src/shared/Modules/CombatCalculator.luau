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
	uid   : string,
	stats : FighterStats,
	hp    : number,     -- aktuell
	skillCooldown : number,
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
-- an der "was macht ein Treffer" beantwortet wird, und ein spaeterer Effekt
-- (Kritischer Treffer, Elementbonus) gehoert genau hierher und nirgendwo sonst.
local function calcDamage(atk: number): number
	return math.max(1, math.floor(atk))
end

-- ============================================================
-- DIE ABILITY-FORMEL
-- ============================================================
-- Der Schaden einer Ability setzt sich aus drei Dingen zusammen:
--
--     Skill-Schaden = (ATK x Skill-Multiplikator + Skill-Basisschaden)
--                     x (1 + PWR)
--
--   * Skill-Multiplikator und Basisschaden gehoeren dem SKILL
--     (SkillConfig.params.multiplier / baseDamage) — sie sagen, was diese
--     Ability grundsaetzlich taugt.
--   * ATK und PWR gehoeren dem BAERCHI. ATK skaliert jede Ability, PWR NUR
--     die Abilities — der Grundschlag einer Runde (calcDamage) bleibt davon
--     unberuehrt. Siehe FighterStats.pwr zum Sonderfall BasicPunch.
--
-- Genau diese Trennung macht PWR zu einem eigenen Stat: zwei Baerchis mit
-- gleichem ATK unterscheiden sich in dem, was ihre Ability daraus macht.
--
-- WARUM DIE FUNKTION EINEN "BONUS" ZURUECKGIBT UND NICHT DEN GANZEN SCHADEN:
-- eine Runde besteht aus einem normalen Schlag, und der Skill kommt obendrauf.
-- Der Aufrufer rechnet `calcDamage(atk) + bonus`. Damit am Ende exakt der oben
-- stehende Skill-Schaden herauskommt, wird hier der normale Schlag abgezogen.
-- Ein Skill, der schwaecher waere als ein normaler Schlag, gibt 0 Bonus statt
-- eines negativen Werts — er verpufft also, statt den eigenen Angriff zu
-- schwaechen.
local function skillDamage(stats: FighterStats, multiplier: number, baseDamage: number): number
	local raw = (stats.atk * multiplier + baseDamage) * (1 + stats.pwr)
	return math.max(0, math.floor(raw) - calcDamage(stats.atk))
end

-- Verarbeitet einen Skill-Effekt
-- Gibt (schadenBonus, geheiltHP, stunned) zurueck
local function applySkill(
	attacker: CombatSnapshot,
	defender: CombatSnapshot
): (number, number, boolean)

	if attacker.skillCooldown > 0 then
		return 0, 0, false
	end

	local skill = SkillConfig.getById(attacker.stats.skillId)
	if not skill then return 0, 0, false end

	-- Jeder Skill DARF einen Basisschaden haben, keiner MUSS. Fehlt er, ist er
	-- 0 und die Formel faellt auf das reine ATK-Vielfache zurueck — so bleiben
	-- Skills ohne eigenen Grundwert (und kuenftige neue Eintraege) gueltig,
	-- ohne dass hier eine Sonderbehandlung noetig waere.
	local baseDamage = skill.params.baseDamage or 0

	local bonusDmg = 0
	local healHp   = 0
	local stuns    = false

	if skill.effectType == "Damage" then
		bonusDmg = skillDamage(attacker.stats, skill.params.multiplier, baseDamage)

	elseif skill.effectType == "Heal" then
		-- Heilung ist kein Schaden und wird deshalb NICHT von PWR skaliert.
		-- PWR ist ausdruecklich der Ability-SCHADENS-Wert; wuerde er auch
		-- Heilung anheben, waere er der eine Stat, den jeder Baerchi will.
		healHp = math.floor(attacker.stats.maxHp * skill.params.healPercent)

	elseif skill.effectType == "Drain" then
		-- Drain nimmt einen Anteil der GEGNERISCHEN HP — der Wert haengt also
		-- am Gegner, nicht am eigenen ATK. PWR skaliert trotzdem mit: es ist
		-- der Schaden einer Ability, und ein Ability-Baerchi soll ihn spueren.
		local drained = math.floor(defender.hp * skill.params.drainPercent * (1 + attacker.stats.pwr))
		drained  = math.min(drained, defender.hp)
		bonusDmg = drained
		healHp   = drained

	elseif skill.effectType == "Stun" then
		bonusDmg = skillDamage(attacker.stats, skill.params.damageMultiplier, baseDamage)
		stuns    = true

	elseif skill.effectType == "InstantKill" then
		if math.random() < skill.params.chance then
			-- Sofortiger K.O.: hier gibt es nichts zu skalieren, mehr als die
			-- restlichen HP des Gegners kann kein Schaden sein. PWR wirkt
			-- deshalb nur auf den Ersatzschaden darunter.
			bonusDmg = defender.hp
		else
			bonusDmg = skillDamage(attacker.stats, skill.params.fallbackMultiplier, baseDamage)
		end
	end

	attacker.skillCooldown = skill.cooldown
	return bonusDmg, healHp, stuns
end

export type FullCombatResult = {
	winnerUid   : string,
	loserUid    : string,
	rounds      : number,
	log         : { Types.RoundLogEntry }, -- NEU: Nutzt jetzt den zentralen Typ aus Types.luau
}

-- Simuliert einen vollstaendigen Kampf zwischen zwei Baerchis.
-- Gibt das Ergebnis zurueck — kein Side-Effect, keine Daten-Aenderung.
function CombatCalculator.simulate(
	a: CombatSnapshot,
	b: CombatSnapshot
): FullCombatResult

	local MAX_ROUNDS = 50  -- Endlosschleifen-Schutz
	local log: { Types.RoundLogEntry } = {} -- NEU: Tabelle typisiert mit Types.RoundLogEntry
	local round = 0
	local bStunned = false

	while a.hp > 0 and b.hp > 0 and round < MAX_ROUNDS do
		round += 1

		-- Cooldowns runterzaehlen
		if a.skillCooldown > 0 then a.skillCooldown -= 1 end
		if b.skillCooldown > 0 then b.skillCooldown -= 1 end

		-- A greift B an
		local aBonusDmg, aHeal, aStuns = applySkill(a, b)
		local aDmg = calcDamage(a.stats.atk) + aBonusDmg
		b.hp = math.max(0, b.hp - aDmg)
		a.hp = math.min(a.stats.maxHp, a.hp + aHeal)

		if aStuns then bStunned = true end

		-- B greift A an (ausser wenn betaeubt)
		if b.hp > 0 and not bStunned then
			local bBonusDmg, bHeal, _ = applySkill(b, a)
			local bDmg = calcDamage(b.stats.atk) + bBonusDmg
			a.hp = math.max(0, a.hp - bDmg)
			b.hp = math.min(b.stats.maxHp, b.hp + bHeal)
		end

		bStunned = false

		table.insert(log, {
			attackerHpAfter = a.hp,
			defenderHpAfter = b.hp,
			skillUsed       = aBonusDmg > 0 or aHeal > 0,
			roundNumber     = round,
		})
	end

	-- Bei Unentschieden (MAX_ROUNDS) gewinnt wer mehr HP hat
	local winnerUid, loserUid
	if a.hp >= b.hp then
		winnerUid, loserUid = a.uid, b.uid
	else
		winnerUid, loserUid = b.uid, a.uid
	end

	return {
		winnerUid = winnerUid,
		loserUid  = loserUid,
		rounds    = round,
		log       = log,
	}
end

return CombatCalculator