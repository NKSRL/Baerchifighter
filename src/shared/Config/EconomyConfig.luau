--!strict
-- EconomyConfig.luau
-- ReplicatedStorage/Config/EconomyConfig.luau
--
-- Einzige Zustaendigkeit:
--   - Alle Preise, Kosten und Ertraege, die nicht zu einem eigenen System
--     gehoeren: Rebirth, Honig, Gebaeude-Ausbau (Level 1-60), Recycling,
--     Fusion, Rang.
-- EconomyService liest nur von hier — keine Zahl ist im Service selbst.
--
-- Seit v15 stehen die Zahlen des Kampfs (Stage-Gummies, GoldGummies pro Lauf,
-- Fortsetzen) in Config/TowerConfig — das PIT-Level gibt es nicht mehr.
--
-- Die "effect"-Strings in BUILDING_UPGRADES werden aus HONEY_XP ERZEUGT und
-- nicht von Hand gepflegt. Frueher standen Text und Zahl getrennt da und
-- liefen beim Balancing auseinander — das kann jetzt nicht mehr passieren.

local Types = require(script.Parent.Parent.Network.Types)

--------------------------------------------------------------------------------
-- Rebirth
--------------------------------------------------------------------------------

-- Gummies-Kosten fuer Rebirth n (Index = rebirthCount + 1).
--
-- v15: NEU KALIBRIERT fuer das Tower-System (tools/sim/progression_pacing.lua,
-- Profil "Normal" 90 min/Tag). Mit dem Tower-Einkommen waeren die alten Preise
-- (10.000 / 35.000 / ...) nach Minuten bezahlt gewesen. Ziel-Dauer eines
-- Lebens: Rebirth 1 nach ~3 h aktiver Zeit (Spieltag 2-3), danach 3,5 / 4,5 /
-- 6 h; die Rebirths 4-6 und 14-15 werden vom Tower-Deckel bzw. der
-- Baerchi-Staerke begrenzt, ihre Preise sind geglaettet. ANNAHME, im Bericht.
local REBIRTH_COST_GUMMIES: { number } = {
	1_500_000,             -- Rebirth 1
	230_000_000,           -- Rebirth 2
	4_400_000_000,         -- Rebirth 3
	25_000_000_000,        -- Rebirth 4
	120_000_000_000,       -- Rebirth 5
	300_000_000_000,       -- Rebirth 6
	570_000_000_000,       -- Rebirth 7 (oeffnet den Final-Tower)
	1_160_000_000_000,     -- Rebirth 8
	1_600_000_000_000,     -- Rebirth 9
	3_500_000_000_000,     -- Rebirth 10
	6_500_000_000_000,     -- Rebirth 11
	11_000_000_000_000,    -- Rebirth 12
	17_000_000_000_000,    -- Rebirth 13
	25_000_000_000_000,    -- Rebirth 14
	40_000_000_000_000,    -- Rebirth 15 (Final-Deckel 100)
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
--   Kosten  Rebirth n (n >= 16) = Kosten 15 x REBIRTH_COST_GROWTH ^ (n - 15)
--   Multi   nach Rebirth n (n >= 6) = 8 x REBIRTH_MULT_GROWTH ^ (n - 5)
--
-- (v15: die Kosten-Tabelle oben reicht bis Rebirth 15, danach waechst sie wie
-- bisher mit 1.13. Die Multiplikatoren sind unveraendert.)
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

-- Die XP-Kurve fuer EINEN Honig. Index = Level des HONIG-VEREDLERS (bis v14:
-- der Honig-Presse; die Migration uebernimmt das hoehere Level von Topf und
-- Presse, siehe PlayerMigration).
--
-- BuildingBehavior rechnet daraus den Multiplikator des Veredlers, der auf
-- JEDEN Honig wirkt. Level 1-10 sind unveraendert seit v7; ab Level 11 waechst
-- die Kurve mit HONEY_XP_GROWTH pro Level weiter (siehe getHoneyXp).
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

-- v15: XP-Zuwachs pro Veredler-Level ab Level 11 (Level 30 ≈ 12.300, Level 60
-- ≈ 820.000 XP pro Honig). Kalibriert mit tools/sim/progression_pacing.lua: ein
-- hoher Veredler bringt einen frisch zurueckgesetzten Baerchi nach einem
-- Rebirth in Minuten statt Stunden wieder auf Level 50.
local HONEY_XP_GROWTH = 1.15

--------------------------------------------------------------------------------
-- Gebaeude-Upgrades (v15: Level 1-60)
--------------------------------------------------------------------------------

local MAX_BUILDING_LEVEL = 60

-- Kosten fuer das Upgrade AUF dieses Level. Beginnt bei Index 2, weil Level 1
-- der Startzustand ist — deshalb bewusst als Map und nicht als Array.
--
-- Die KOSTENKURVE gilt fuer ALLE Gebaeude inklusive Recycler (CombConfig): sie
-- kosten gleich viel, koennen aber Verschiedenes. Die Ausbau-Tabellen mit
-- Effekt-Text baut BuildingBehavior aus dieser Kurve.
--
-- Level 2-10 sind seit v7 unveraendert (Vorgabe: bestehende Spielstaende).
-- Ab Level 11 setzt sich die Kurve exponentiell fort (unten erzeugt), flacher
-- als bisher (x2,3 je Level bis 10, danach COST_GROWTH_AFTER_10).
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

-- v15: Fortsetzung der Kostenkurve ab Level 11. ANNAHME, per
-- tools/sim/progression_pacing.lua kalibriert auf die Look-Zielzeiten (README
-- 4.4): Look 3 (L20) ~Tag 2-3, Look 4 (L30) ~Woche 1, Look 5 (L45) ~Woche 2-3,
-- Look 6 (L60) ~Woche 5-8 bei 1,5 h aktiver Spielzeit pro Tag.
-- Zwei Abschnitte: bis Level 30 flacher (Look 3 und 4 sollen in der ersten
-- Woche kommen), danach steiler (Look 5 und 6 sind das Langzeitziel).
local COST_GROWTH_AFTER_10 = 1.22   -- Level 11-30
local COST_GROWTH_AFTER_30 = 1.33   -- Level 31-60
local GOLD_GROWTH_AFTER_10 = 1.035

-- v15: Look-Stufen der Gebaeude (Modelle kommen in Prompt 4). Index = Look,
-- Wert = erstes Level dieses Looks: 1-9 / 10-19 / 20-29 / 30-44 / 45-59 / 60.
local LOOK_THRESHOLDS: { number } = { 1, 10, 20, 30, 45, 60 }

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

-- (v15: der Abschnitt "PIT" ist entfallen. Stage-Gummies, GoldGummies pro Lauf
-- und Fortsetzen stehen in Config/TowerConfig, die alten PIT-Ausbaukosten nur
-- noch fuer die Erstattung in TowerConfig.LEGACY_PIT_UPGRADE_COSTS.)

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

-- v15: Ausbaukosten ab Level 11 erzeugen (einmal beim Laden).
do
	local base = HONEY_UPGRADE_COSTS[10]
	for level = 11, MAX_BUILDING_LEVEL do
		local steps = level - 10
		local early = math.min(steps, 20)
		local late  = math.max(0, steps - 20)
		HONEY_UPGRADE_COSTS[level] = {
			gummies     = roundSignificant(base.gummies * COST_GROWTH_AFTER_10 ^ early * COST_GROWTH_AFTER_30 ^ late),
			goldGummies = roundSignificant(base.goldGummies * GOLD_GROWTH_AFTER_10 ^ steps),
		}
	end
end

-- Look-Stufe (1-6) eines Gebaeude-Levels.
local function getLook(level: number): number
	local look = 1
	for index, from in LOOK_THRESHOLDS do
		if level >= from then
			look = index
		end
	end
	return look
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

-- XP die ein Honig bei diesem Veredler-Level gibt (Level 1-10 aus der
-- Tabelle, danach mit HONEY_XP_GROWTH weiter).
local function getHoneyXp(buildingLevel: number): number
	local level = clampBuildingLevel(buildingLevel)
	if level <= #HONEY_XP then
		return HONEY_XP[level]
	end
	return math.floor(HONEY_XP[#HONEY_XP] * HONEY_XP_GROWTH ^ (level - #HONEY_XP) + 0.5)
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
	HONEY_XP_GROWTH          = HONEY_XP_GROWTH,

	HONEY_UPGRADE_COSTS  = HONEY_UPGRADE_COSTS,
	MAX_BUILDING_LEVEL   = MAX_BUILDING_LEVEL,
	COST_GROWTH_AFTER_10 = COST_GROWTH_AFTER_10,
	COST_GROWTH_AFTER_30 = COST_GROWTH_AFTER_30,
	GOLD_GROWTH_AFTER_10 = GOLD_GROWTH_AFTER_10,
	LOOK_THRESHOLDS      = LOOK_THRESHOLDS,
	getLook              = getLook,

	RECYCLE_RETURN      = RECYCLE_RETURN,
	RECYCLE_BASE_VALUE  = RECYCLE_BASE_VALUE,
	RECYCLE_LEVEL_BONUS = RECYCLE_LEVEL_BONUS,

	FUSION_STAT_BONUS = FUSION_STAT_BONUS,

	RANK_TIERS = RANK_TIERS,

	clampBuildingLevel    = clampBuildingLevel,
	roundSignificant      = roundSignificant,
	getRebirthCost        = getRebirthCost,
	getRebirthMult        = getRebirthMult,
	getAscensionEggReward = getAscensionEggReward,
	getHoneyXp            = getHoneyXp,
	getFusionStatBonus    = getFusionStatBonus,
	getBaerchiBaseValue   = getBaerchiBaseValue,
	getRankForPoints      = getRankForPoints,
}
