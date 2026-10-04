--!strict
-- EconomyConfig.luau
-- ReplicatedStorage/Config/EconomyConfig.luau
--
-- Alle Preise, Kosten und Ertraege.
-- EconomyService liest nur von hier — keine Zahl ist im Service selbst.
--
-- Die "effect"-Strings in BUILDING_UPGRADES werden aus HONEY_XP ERZEUGT und
-- nicht von Hand gepflegt. Frueher standen Text und Zahl getrennt da und
-- liefen beim Balancing auseinander — das kann jetzt nicht mehr passieren.

local Types = require(script.Parent.Parent.Network.Types)

--------------------------------------------------------------------------------
-- Rebirth
--------------------------------------------------------------------------------

-- Gummies-Kosten fuer Rebirth n (Index = rebirthCount + 1)
local REBIRTH_COST_GUMMIES: { number } = {
	10_000,    -- Rebirth 1
	35_000,    -- Rebirth 2
	100_000,   -- Rebirth 3
	300_000,   -- Rebirth 4
	1_000_000, -- Rebirth 5+
}

-- Multiplikator nach Rebirth n (Index = rebirthCount nach dem Reset)
local REBIRTH_MULTIPLIERS: { number } = {
	1.0,   -- kein Rebirth
	1.5,   -- nach Rebirth 1
	2.25,  -- nach Rebirth 2
	3.50,  -- nach Rebirth 3
	5.50,  -- nach Rebirth 4
	8.00,  -- nach Rebirth 5+
}

-- Gummies mit denen ein Spieler nach dem Rebirth startet.
-- Bewusst identisch mit dem Startwert eines neuen Spielers.
local REBIRTH_START_GUMMIES = 100

-- ============================================================
-- v14: REBIRTH-KURVE BIS 100
-- ============================================================
-- Bis v13 waren die Kosten ab Rebirth 5 flach (1 Mio) und der Multiplikator
-- stoppte bei x8. Fuer die Ascensions-Eier bei Rebirth 50 bis 100 geht die
-- Kurve jetzt weiter:
--
--   Kosten  Rebirth n (n >= 6) = 1 Mio x REBIRTH_COST_GROWTH ^ (n - 5)
--   Multi   nach Rebirth n (n >= 6) = 8 x REBIRTH_MULT_GROWTH ^ (n - 5)
--
-- Die Rebirths 1 bis 5 bleiben exakt wie bisher (bestehende Spielstaende).
--
-- Warum diese beiden Zahlen: die Zeit fuer einen Rebirth ist ungefaehr
-- Kosten / (Einkommen x Multiplikator). Waechst die Kosten-Kurve nur ein
-- kleines Stueck schneller als der Multiplikator (1.13 gegen 1.12), wird
-- jeder Rebirth nur knapp 1% laenger als der vorige: Rebirth 100 dauert
-- etwa 2,3-mal so lange wie Rebirth 6. Gerechnet in tools/sim/rebirth_curve.lua
-- (Tabelle im Bericht MEGA_EGG_TREE_UMGESETZT).
--
-- Gerundet wird auf drei gueltige Stellen, damit im UI "1.130.000" steht und
-- nicht "1.129.999".
local REBIRTH_COST_GROWTH = 1.13
local REBIRTH_MULT_GROWTH = 1.12

-- v14: REBIRTH-MEILENSTEINE. Bei welchem rebirthCount (NACH dem Rebirth) es
-- welche Eier gibt. `unlock` = dieser Meilenstein schaltet den Knoten des
-- Eis im Ei-Baum frei (zusaetzlich zur normalen Rebirth-Bedingung, die bei
-- derselben Zahl liegt — doppelt haelt besser, falls jemand eine der beiden
-- Zahlen verschiebt).
--
-- Die Ascensions-Eier sind nicht kaufbar und werden fast nie gelegt — das
-- hier ist ihre Hauptquelle. Transzendenz, Ewigkeit und Omega gibt es NUR hier.
export type RebirthMilestone = {
	eggs   : { { eggType: Types.EggType, count: number } },
	unlock : { Types.EggType }?,
}

local REBIRTH_MILESTONES: { [number]: RebirthMilestone } = {
	[1]   = { eggs = { { eggType = "AscensionEgg", count = 1 } } },
	[3]   = { eggs = { { eggType = "AscensionEgg", count = 1 } } },
	[5]   = { eggs = { { eggType = "AscensionEgg", count = 2 } } },
	[10]  = { eggs = { { eggType = "AscensionEgg", count = 3 } } },
	[15]  = { eggs = { { eggType = "TranscendenceEgg", count = 1 } }, unlock = { "TranscendenceEgg" } },
	[20]  = { eggs = { { eggType = "AscensionEgg", count = 5 } } },
	[25]  = { eggs = { { eggType = "TranscendenceEgg", count = 2 } } },
	[30]  = { eggs = { { eggType = "EternityEgg", count = 1 } }, unlock = { "EternityEgg" } },
	[40]  = { eggs = { { eggType = "TranscendenceEgg", count = 3 }, { eggType = "EternityEgg", count = 1 } } },
	[50]  = { eggs = { { eggType = "OmegaEgg", count = 1 }, { eggType = "EternityEgg", count = 2 } }, unlock = { "OmegaEgg" } },
	[75]  = { eggs = { { eggType = "OmegaEgg", count = 2 } } },
	[100] = { eggs = { { eggType = "OmegaEgg", count = 3 } } },
}

-- Fuer alte Stellen, die nur die Ascensions-Eier kennen (wird von
-- getAscensionEggReward weiter gelesen).
local REBIRTH_ASCENSION_MILESTONES: { [number]: number } = {}
for n, milestone in REBIRTH_MILESTONES do
	for _, entry in milestone.eggs do
		if entry.eggType == "AscensionEgg" then
			REBIRTH_ASCENSION_MILESTONES[n] = (REBIRTH_ASCENSION_MILESTONES[n] or 0) + entry.count
		end
	end
end

--------------------------------------------------------------------------------
-- Honig (Gebaeude-Produktion und Fuetterung)
--------------------------------------------------------------------------------

-- Sekunden bis ein Gebaeude einen weiteren Honig hergestellt hat — die
-- gemeinsame Basis fuer alle drei. Auch der Takt, in dem HoneyService seinen
-- Nachrechen-Loop laufen laesst.
--
-- Ob ein einzelnes Gebaeude davon ABWEICHT (aktuell: nur der Honigtopf wird
-- mit steigendem Level schneller), steht nicht mehr hier, sondern in
-- Config/BuildingBehavior.luau — ein Eintrag pro Gebaeude statt einer
-- if-Kette. Diese Datei kennt BuildingBehavior bewusst NICHT: die
-- Abhaengigkeit geht nur in die andere Richtung, sonst waere es ein
-- Ringschluss.
local HONEY_INTERVAL_SECONDS = 20

-- BASIS-Lager eines Gebaeudes. Ist das Lager voll, steht die Produktion bis
-- wieder gefuettert wird — genau das macht das regelmaessige Zurueckkommen zum
-- Plot noetig.
--
-- Der Bienenstock waechst darueber hinaus (BuildingBehavior); fuer die anderen
-- beiden ist das der endgueltige Wert.
local HONEY_CAPACITY = 5

-- BASIS-Anteil der maximalen HP, den ein Honig heilt. Vier Honig bringen einen
-- erschoepften Baerchi also wieder auf volle Kraft.
--
-- Der Honigtopf heilt mit steigendem Level mehr (BuildingBehavior); fuer die
-- anderen beiden bleibt es bei diesem Wert.
local HONEY_HEAL_PERCENT = 0.25

-- Ab welchem HP-Anteil der Autopilot beim Fuettern bewusst den Honig mit der
-- STAERKSTEN Heilung nimmt, statt den, dessen Lager am vollsten ist.
--
-- Der Autopilot ist der einzige, der nicht fragen kann, welchen Honig der
-- Spieler verfuettern will — im UI waehlt der Spieler selbst (BaerchiPanel).
local HONEY_AUTO_HEAL_HP_RATIO = 0.5

-- Die XP-Kurve fuer EINEN Honig. Index = Level der HONIG-PRESSE.
--
-- Bis v6 hing das am Level des Gebaeudes, aus dem der Honig kam — jedes der
-- drei tat also dasselbe. Seit v7 besitzt die Presse diese Kurve allein
-- (BuildingBehavior rechnet daraus ihren Multiplikator, der auf JEDEN Honig
-- wirkt). Die Zahlen selbst sind unveraendert: bei "Presse auf Level N" gibt
-- ein Honig genau so viel XP wie frueher bei "Gebaeude auf Level N".
--
-- Zusammen mit der XP-Kurve in BaerchiConfig (ca. 730 XP bis Level 7) heisst
-- Level 1: rund 24 Honig bis Level 7 — bei drei Gebaeuden gut zweieinhalb
-- Minuten. Genau so schnell soll der Einstieg sein.
local HONEY_XP: { number } = {
	[1]  = 30,
	[2]  = 45,
	[3]  = 65,
	[4]  = 95,
	[5]  = 135,
	[6]  = 190,
	[7]  = 265,
	[8]  = 370,
	[9]  = 520,
	[10] = 750,
}

--------------------------------------------------------------------------------
-- Gebaeude-Upgrades
--------------------------------------------------------------------------------

local MAX_BUILDING_LEVEL = 10

-- Kosten fuer das Upgrade AUF dieses Level. Beginnt bei Index 2, weil Level 1
-- der Startzustand ist — deshalb bewusst als Map und nicht als Array.
--
-- Die KOSTENKURVE gilt weiterhin fuer alle drei Gebaeude: sie kosten gleich
-- viel, koennen aber seit v7 voellig Verschiedenes. Wer sie unterschiedlich
-- teuer machen will, findet die drei Ausbau-Tabellen in
-- Config/BuildingBehavior.luau — dort werden sie aus dieser Kurve gebaut.
local HONEY_UPGRADE_COSTS: { [number]: { gummies: number, goldGummies: number } } = {
	[2]  = { gummies = 250,    goldGummies = 0  },
	[3]  = { gummies = 700,    goldGummies = 0  },
	[4]  = { gummies = 1_800,  goldGummies = 0  },
	[5]  = { gummies = 4_500,  goldGummies = 3  },
	[6]  = { gummies = 11_000, goldGummies = 8  },
	[7]  = { gummies = 26_000, goldGummies = 16 },
	[8]  = { gummies = 60_000, goldGummies = 30 },
	[9]  = { gummies = 140_000,goldGummies = 55 },
	[10] = { gummies = 320_000,goldGummies = 95 },
}

-- Die fertigen Ausbau-Tabellen (Kosten + Effekt-Text) stehen seit v7 in
-- Config/BuildingBehavior.luau, eine pro Gebaeude. Sie muessen dort stehen und
-- nicht hier, weil ihr Effekt-Text die Mechanik des jeweiligen Gebaeudes
-- beschreibt — und die kennt nur BuildingBehavior. Umgekehrt duerfte diese
-- Datei BuildingBehavior gar nicht requiren: das waere ein Ringschluss.

--------------------------------------------------------------------------------
-- Feste Werte fuer die Funktionen die kein Gebaeude mehr haben
--------------------------------------------------------------------------------

-- (v12: HATCH_SLOTS ist entfallen — Eier werden sofort geoeffnet.)

-- Recycling laeuft ebenfalls ueber das GUI: fester Anteil des Baerchi-Werts,
-- der als Gummies zurueckkommt (frueher Recycler-Level-abhaengig).
local RECYCLE_RETURN = 0.40

-- Basiswert eines Baerchis auf Level 1, nach Rarity (in Gummies).
-- Das Recycling gibt davon RECYCLE_RETURN zurueck.
local RECYCLE_BASE_VALUE: { [Types.Rarity]: number } = {
	Common    = 25,
	Uncommon  = 60,
	Rare      = 150,
	Epic      = 500,
	Legendary = 2_000,
	Mythic    = 8_000,
	Divine    = 20_000,
	Cosmic    = 50_000,
	Secret    = 120_000,
	Godly     = 300_000,
	Eternal   = 750_000,
	Omega     = 2_000_000,
}

-- Wertzuwachs pro Baerchi-Level: value * (1 + (level-1) * RECYCLE_LEVEL_BONUS)
local RECYCLE_LEVEL_BONUS = 0.10

--------------------------------------------------------------------------------
-- Fusion
--------------------------------------------------------------------------------

-- Fester Stat-Bonus den JEDES Fusions-Ergebnis mitbekommt. Fusion ist seit v3
-- kein Gebaeude mehr, sondern ein reines GUI-Feature ohne Unlock-Level.
local FUSION_STAT_BONUS = 0.50

--------------------------------------------------------------------------------
-- PIT (Kampfplattform)
--------------------------------------------------------------------------------

local MAX_PIT_LEVEL = 8

-- [pitLevel] = Gummies-Kosten um auf dieses Level zu steigen
local PIT_UPGRADE_COSTS: { [number]: number } = {
	[2]  = 500,
	[3]  = 1_500,
	[4]  = 4_000,
	[5]  = 10_000,
	[6]  = 25_000,
	[7]  = 60_000,
	[8]  = 150_000,
}

-- Gummy-Belohnung fuer die ERSTE Stage eines Laufs auf diesem PIT-Level
-- (Basiswert vor rebirthMult).
local PIT_GUMMY_REWARDS: { number } = {
	[1] = 10,
	[2] = 25,
	[3] = 60,
	[4] = 140,
	[5] = 320,
	[6] = 700,
	[7] = 1_500,
	[8] = 3_500,
}

-- Jede weitere Stage im selben Lauf gibt entsprechend mehr. Tiefer kommen
-- lohnt sich dadurch ueberproportional — genau der Anreiz, den Baerchi
-- vorher mit Honig moeglichst weit hochzufuettern.
local PIT_STAGE_REWARD_GROWTH = 0.15

-- GoldGummies gibt es als Meilenstein im PIT: alle N geschafften Stages
-- eines Laufs, multipliziert mit dem PIT-Level. Seit die GummyFarm weg ist,
-- ist das ihre einzige Quelle — sie haengen damit direkt am Kern-Loop statt
-- an passivem Warten.
--
-- Das PIT-Level steht bewusst mit im Produkt. Ohne es waere die Gold-Menge
-- fast flach (ein Baerchi schafft mit Level 10 zehn Stages, mit Level 40
-- zweiunddreissig — also 2 statt 6 Gold), waehrend die Gold-Kosten der
-- Gebaeude von 3 auf 95 steigen. Die letzten Ausbaustufen haetten dann rund
-- 16 Laeufe gekostet, obwohl ihr Gummy-Anteil in zweien drin ist. Mit dem
-- Faktor liegt jede Stufe bei ein bis vier Laeufen — und auf PIT-Level 1
-- (Spielanfang) aendert sich nichts, weil dort mal 1 gerechnet wird.
local PIT_GOLD_EVERY_STAGES = 5
local PIT_GOLD_AMOUNT       = 1

-- ============================================================
-- PIT-FORTSETZUNG (v12, PET_STEUERUNG_UND_EI_ANIMATION_KONZEPT Abschnitt 4b)
-- ============================================================
-- Vor einem PIT-Lauf darf der Spieler gegen Gummies weiter oben einsteigen:
-- bei 65 % der Stage-Tiefe seines letzten Laufs oder direkt bei der letzten
-- erreichten Stage.
--
-- Kosten = Anteil der Belohnungen, die die UEBERSPRUNGENEN Stages gebracht
-- haetten. Das skaliert automatisch mit dem PIT-Level (die Belohnungen tun
-- es) und mit rebirthMult (das Einkommen tut es auch — ohne ihn waere das
-- Ueberspringen nach ein paar Rebirths praktisch umsonst).
--
-- 0,35 ist ein PLATZHALTER aus dem Konzept: zu billig, und jeder startet
-- immer oben; zu teuer, und niemand nutzt es. Muss im Playtest geprueft werden.
local PIT_RESUME_COST_FACTOR = 0.35

-- "65 %" = 65 % der STAGE-TIEFE des letzten Laufs (nicht der HP).
local PIT_RESUME_PERCENT = 0.65

--------------------------------------------------------------------------------
-- Rang-Schwellwerte (Arena PvP)
--------------------------------------------------------------------------------

export type RankTierDef = {
	tier        : number,
	name        : string,
	minPoints   : number,
	rewardGummies     : number,   -- Saisonende-Belohnung
	rewardGoldGummies : number,
}

local RANK_TIERS: { RankTierDef } = {
	{ tier=1, name="Gummy Hatchling", minPoints=0,    rewardGummies=500,   rewardGoldGummies=0  },
	{ tier=2, name="Sugar Brawler",   minPoints=100,  rewardGummies=1500,  rewardGoldGummies=5  },
	{ tier=3, name="Crystal Fighter", minPoints=300,  rewardGummies=4000,  rewardGoldGummies=15 },
	{ tier=4, name="Golden Champion", minPoints=700,  rewardGummies=10000, rewardGoldGummies=40 },
	{ tier=5, name="Cosmic Legend",   minPoints=1500, rewardGummies=30000, rewardGoldGummies=100},
}

--------------------------------------------------------------------------------
-- Hilfsfunktionen
--------------------------------------------------------------------------------

-- Level auf den gueltigen Bereich einer Effekt-Tabelle klemmen.
-- Schuetzt vor kaputten Save-Daten mit Level 0 oder 99.
local function clampBuildingLevel(level: number): number
	return math.clamp(math.floor(level), 1, MAX_BUILDING_LEVEL)
end

-- Auf drei gueltige Stellen runden (1129999 -> 1130000).
local function roundSignificant(value: number): number
	if value < 1000 then return math.floor(value + 0.5) end
	local digits = math.floor(math.log10(value)) + 1
	local factor = 10 ^ (digits - 3)
	return math.floor(value / factor + 0.5) * factor
end

-- Kosten fuer den NAECHSTEN Rebirth (rebirthCount = bisherige Anzahl).
local function getRebirthCost(rebirthCount: number): number
	local n = rebirthCount + 1
	if n <= #REBIRTH_COST_GUMMIES then
		return REBIRTH_COST_GUMMIES[n]
	end
	local last = REBIRTH_COST_GUMMIES[#REBIRTH_COST_GUMMIES]
	return roundSignificant(last * REBIRTH_COST_GROWTH ^ (n - #REBIRTH_COST_GUMMIES))
end

-- Multiplikator NACH `rebirthCount` Rebirths.
local function getRebirthMult(rebirthCount: number): number
	local idx = rebirthCount + 1
	if idx <= #REBIRTH_MULTIPLIERS then
		return REBIRTH_MULTIPLIERS[idx]
	end
	local last = REBIRTH_MULTIPLIERS[#REBIRTH_MULTIPLIERS]
	local raw = last * REBIRTH_MULT_GROWTH ^ (idx - #REBIRTH_MULTIPLIERS)
	-- Zwei Nachkommastellen reichen fuer die Anzeige "x8,96".
	if raw < 100 then
		return math.floor(raw * 100 + 0.5) / 100
	end
	return roundSignificant(raw)
end

-- Wie viele AscensionEggs es fuer das Erreichen dieses rebirthCount gibt
local function getAscensionEggReward(rebirthCount: number): number
	return REBIRTH_ASCENSION_MILESTONES[rebirthCount] or 0
end

-- v14: der komplette Meilenstein (alle Ei-Sorten) oder nil.
local function getRebirthMilestone(rebirthCount: number): RebirthMilestone?
	return REBIRTH_MILESTONES[rebirthCount]
end

-- XP die ein Honig aus einem Gebaeude dieses Levels gibt
local function getHoneyXp(buildingLevel: number): number
	return HONEY_XP[clampBuildingLevel(buildingLevel)]
end

-- Wie lange EIN bestimmtes Gebaeude fuer seinen naechsten Honig braucht,
-- stand frueher hier als `if buildingId ~= "HoneyPot"`. Das ist jetzt
-- BuildingBehavior.getIntervalSeconds — siehe Kommentar bei
-- HONEY_INTERVAL_SECONDS weiter oben.

-- Basis-Belohnung der ERSTEN Stage eines Laufs, OHNE rebirthMult.
-- Der Multiplikator wird zentral von EconomyService.awardGummies angewendet —
-- wer ihn hier nochmal drauf rechnet, verdoppelt ihn.
local function getPitBaseReward(pitLevel: number): number
	local lvl = math.clamp(math.floor(pitLevel), 1, #PIT_GUMMY_REWARDS)
	return PIT_GUMMY_REWARDS[lvl]
end

-- Basis-Belohnung fuer eine bestimmte Stage eines Laufs, OHNE rebirthMult.
local function getPitStageReward(pitLevel: number, stage: number): number
	local growth = math.pow(1 + PIT_STAGE_REWARD_GROWTH, math.max(stage, 1) - 1)
	return math.max(1, math.floor(getPitBaseReward(pitLevel) * growth))
end

-- Nur fuer UI-Vorschau ("du wuerdest X Gummies bekommen") — erste Stage.
-- Server-Code benutzt getPitStageReward + EconomyService.awardGummies.
local function getPitReward(pitLevel: number, rebirthMult: number): number
	return math.floor(getPitBaseReward(pitLevel) * rebirthMult)
end

local function getPitUpgradeCost(targetPitLevel: number): number?
	return PIT_UPGRADE_COSTS[targetPitLevel]
end

-- Wie viele GoldGummies ein Lauf bringt: pro angefangene N Stages einer,
-- mal PIT-Level (Begruendung siehe PIT_GOLD_EVERY_STAGES oben).
local function getPitGoldReward(stagesCleared: number, pitLevel: number): number
	if stagesCleared < PIT_GOLD_EVERY_STAGES then
		return 0
	end

	local milestones = math.floor(stagesCleared / PIT_GOLD_EVERY_STAGES)
	local level      = math.clamp(math.floor(pitLevel), 1, MAX_PIT_LEVEL)

	return milestones * PIT_GOLD_AMOUNT * level
end

-- Startstage fuer "ab 65 %" bei einem letzten Lauf bis reachedStage.
local function getPitResumePercentStage(reachedStage: number): number
	return math.max(1, math.floor(PIT_RESUME_PERCENT * reachedStage))
end

-- Gummy-Kosten, um bei `startStage` einzusteigen (Stage 1 = kostenlos).
-- Summe der Basis-Belohnungen aller uebersprungenen Stages, mal Faktor, mal
-- rebirthMult. Server (CombatService) und Client (PitResumeDialog) rechnen
-- beide hiermit — dieselbe Zahl im Dialog und beim Abbuchen.
local function getPitResumeCost(pitLevel: number, startStage: number, rebirthMult: number): number
	if startStage <= 1 then
		return 0
	end

	local skipped = 0
	for stage = 1, startStage - 1 do
		skipped += getPitStageReward(pitLevel, stage)
	end

	return math.floor(PIT_RESUME_COST_FACTOR * skipped * math.max(rebirthMult, 1))
end

-- Fester Wert seit v3 (siehe FUSION_STAT_BONUS oben) — keine Level-Eingabe
-- mehr noetig. Als Funktion belassen statt die Konstante direkt zu lesen,
-- damit FusionService/FusionPanel nicht wissen muessen OB es ein fester
-- Wert oder eine Berechnung ist.
local function getFusionStatBonus(): number
	return FUSION_STAT_BONUS
end

-- Gummy-Wert eines Baerchis wenn er komplett (100%) verwertet wuerde
local function getBaerchiBaseValue(rarity: Types.Rarity, level: number): number
	local base = RECYCLE_BASE_VALUE[rarity] or RECYCLE_BASE_VALUE.Common
	return math.floor(base * (1 + (math.max(level, 1) - 1) * RECYCLE_LEVEL_BONUS))
end

local function getRankForPoints(points: number): RankTierDef
	local result = RANK_TIERS[1]
	for _, tier in RANK_TIERS do
		if points >= tier.minPoints then
			result = tier
		end
	end
	return result
end

return {
	REBIRTH_COST_GUMMIES         = REBIRTH_COST_GUMMIES,
	REBIRTH_MULTIPLIERS          = REBIRTH_MULTIPLIERS,
	REBIRTH_START_GUMMIES        = REBIRTH_START_GUMMIES,
	REBIRTH_ASCENSION_MILESTONES = REBIRTH_ASCENSION_MILESTONES,
	REBIRTH_MILESTONES           = REBIRTH_MILESTONES,
	REBIRTH_COST_GROWTH          = REBIRTH_COST_GROWTH,
	REBIRTH_MULT_GROWTH          = REBIRTH_MULT_GROWTH,
	getRebirthMilestone          = getRebirthMilestone,

	HONEY_INTERVAL_SECONDS   = HONEY_INTERVAL_SECONDS,
	HONEY_CAPACITY           = HONEY_CAPACITY,
	HONEY_HEAL_PERCENT       = HONEY_HEAL_PERCENT,
	HONEY_AUTO_HEAL_HP_RATIO = HONEY_AUTO_HEAL_HP_RATIO,
	HONEY_XP                 = HONEY_XP,

	HONEY_UPGRADE_COSTS = HONEY_UPGRADE_COSTS,
	MAX_BUILDING_LEVEL  = MAX_BUILDING_LEVEL,

	RECYCLE_RETURN      = RECYCLE_RETURN,
	RECYCLE_BASE_VALUE  = RECYCLE_BASE_VALUE,
	RECYCLE_LEVEL_BONUS = RECYCLE_LEVEL_BONUS,

	FUSION_STAT_BONUS = FUSION_STAT_BONUS,

	MAX_PIT_LEVEL           = MAX_PIT_LEVEL,
	PIT_UPGRADE_COSTS       = PIT_UPGRADE_COSTS,
	PIT_GUMMY_REWARDS       = PIT_GUMMY_REWARDS,
	PIT_STAGE_REWARD_GROWTH = PIT_STAGE_REWARD_GROWTH,
	PIT_GOLD_EVERY_STAGES   = PIT_GOLD_EVERY_STAGES,
	PIT_GOLD_AMOUNT         = PIT_GOLD_AMOUNT,
	PIT_RESUME_COST_FACTOR  = PIT_RESUME_COST_FACTOR,
	PIT_RESUME_PERCENT      = PIT_RESUME_PERCENT,

	RANK_TIERS = RANK_TIERS,

	clampBuildingLevel    = clampBuildingLevel,
	getRebirthCost        = getRebirthCost,
	getRebirthMult        = getRebirthMult,
	getAscensionEggReward = getAscensionEggReward,
	getHoneyXp            = getHoneyXp,
	getPitBaseReward      = getPitBaseReward,
	getPitStageReward     = getPitStageReward,
	getPitReward          = getPitReward,
	getPitUpgradeCost     = getPitUpgradeCost,
	getPitGoldReward      = getPitGoldReward,
	getPitResumePercentStage = getPitResumePercentStage,
	getPitResumeCost      = getPitResumeCost,
	getFusionStatBonus    = getFusionStatBonus,
	getBaerchiBaseValue   = getBaerchiBaseValue,
	getRankForPoints      = getRankForPoints,
}
