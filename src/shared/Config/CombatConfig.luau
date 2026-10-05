--!strict
-- CombatConfig.luau
-- ReplicatedStorage/Config/CombatConfig.luau
--
-- Einzige Zustaendigkeit:
--   - Die Grundformel der Kampf-Gegner: Grundwerte, Wachstum pro
--     "Aequivalenz-Stage" und der Ausgleich fuer den DEF-Ausbau.
--
-- Seit v15 (Tower-System) gibt es kein PIT-Level mehr. Welche Gegnerstaerke
-- in welcher Stage welches Towers steht, rechnet Config/TowerConfig: jede
-- Stage eines Towers bekommt eine AEQUIVALENZ-STAGE (die Stage von Tower I mit
-- derselben Staerke), und daraus baut getEnemyStatsForEquivalent hier den
-- Gegner. Tower I Stage N IST Aequivalenz-Stage N — die Kalibrierung unten
-- ("Level N schafft etwa N Stages") gilt fuer Tower I also unveraendert.
--
-- ============================================================
-- WIE EIN PIT-LAUF FUNKTIONIERT
-- ============================================================
-- Ein Lauf ist kein einzelner Kampf: der Baerchi tritt gegen Stage 1 an,
-- danach gegen Stage 2 und so weiter — solange er gewinnt. Seine HP werden
-- zwischen den Stages NICHT zurueckgesetzt. Der Lauf endet, wenn er eine
-- Stage verliert oder bei 0 HP ankommt; danach steht er erschoepft auf dem
-- Plot und muss mit Honig hochgefuettert werden.
--
-- Bis v14 machten zwei Achsen die Gegner staerker: das gekaufte PIT-Level
-- (PIT_LEVEL_GROWTH, nur noch fuer die Migration alter Rekorde da) und das
-- Stage-Wachstum innerhalb eines Laufs. Seit v15 gibt es nur noch die zweite
-- — welcher Tower welche Stages hat, steht in TowerConfig.
--
-- Das Stage-Wachstum liegt bewusst knapp UNTER dem Level-Wachstum der
-- Baerchis (BaerchiConfig.STAT_GROWTH_PER_LEVEL = 10%): jedes Level bringt
-- damit etwas mehr als eine zusaetzliche Stage, Hochfuettern lohnt sich also
-- spuerbar. Die beiden Zahlen muessen nah beieinander bleiben — waere das
-- Stage-Wachstum groesser, kaeme man mit hoeherem Level nicht weiter,
-- sondern weniger weit.
--
-- NACHGERECHNET (frischer RedBaerchi, volle HP, PIT-Level 1). Die Zahlen sind
-- nicht geschaetzt, sondern mit einer Simulation des kompletten Laufs gemessen
-- — derselben, mit der auch ENEMY_ATK_SOFTENING weiter unten bestimmt wurde:
--   Level  1 →  3 Stages      Level 15 → 15 Stages
--   Level  5 →  5 Stages      Level 20 → 21 Stages
--   Level  7 →  7 Stages      Level 30 → 32 Stages
--   Level 10 → 10 Stages      Level 50 → 54 Stages
--
-- und derselbe Level-10-Baerchi angeschlagen:
--   100% HP → 10 Stages   50% HP → 7 Stages   25% HP → 4 Stages
-- Genau dieser Unterschied ist der Grund, vor einem Lauf erst zu fuettern.
--
-- (Bis v14: auf hoeheren PIT-Leveln, Level-10-Baerchi: PIT 3 → 6 Stages,
-- PIT 5 → 4. Seit v15 gibt es dafuer Tower II, III und Final, siehe TowerConfig.)

export type EnemyStats = {
	maxHp  : number,
	atk    : number,
	spd    : number,
	pwr    : number,
	skillId: string,
}

-- Gegner auf PIT-Level 1, Stage 1. Deutlich schwaecher als ein frischer
-- Level-1-Baerchi (105 HP / 10 ATK): der Einstieg soll drei Stages am Stueck
-- hergeben, nicht eine. Waere der Gegner hier auf Augenhoehe, waere jeder
-- Lauf nach der ersten Stage vorbei.
--
-- DEF-AUSBAU: der Gegner hatte frueher 50 HP und 4% Schadensreduktion. Seine
-- HP sind nach derselben Regel umgerechnet worden wie die der Baerchis
-- (50 / (1 - 0.04) = 52, siehe BaerchiConfig) — er haelt also exakt so viel
-- aus wie vorher. PWR ist 0: der Standard-Gegner benutzt BasicPunch, einen
-- reinen 1.0x-Schlag ohne Skill-Anteil, den PWR gar nicht beruehren wuerde.
local ENEMY_BASE: EnemyStats = {
	maxHp   = 52,
	atk     = 6,
	spd     = 1.0,
	pwr     = 0.0,
	skillId = "BasicPunch",
}

-- Zuwachs pro Stage innerhalb eines Laufs (siehe Kopf: knapp unter den 10%
-- Level-Wachstum der Baerchis).
local STAGE_GROWTH = 0.09

-- v15: NUR NOCH FUER DIE MIGRATION. Zuwachs pro altem PIT-Level (additiv auf
-- den Grundwert: Level 3 = +50%). TowerConfig.legacyPitToTower rechnet damit
-- einen alten PIT-Rekord in die gleich starke Tower-Stage um.
local PIT_LEVEL_GROWTH = 0.25

-- ============================================================
-- DER AUSGLEICH FUER DEN DEF-AUSBAU
-- ============================================================
-- Frueher wuchs die Verteidigung BEIDER Seiten mit: der Baerchi bekam +0.5%
-- je Level (bis 75%), der Gegner +1% je PIT-Level (bis 50%). Beides ist
-- ersatzlos entfallen.
--
-- Das hebt sich nicht von selbst auf. Ein Level-50-Baerchi hatte deutlich mehr
-- DEF als ein Gegner auf einem normalen PIT-Level — ohne Ausgleich waeren die
-- hohen Level spuerbar schwaecher geworden, obwohl an ihnen nichts geaendert
-- wurde. Statt allen Baerchis dafuer HP zu schenken (was im spaeteren PvP
-- niemandem helfen wuerde, weil dort beide Seiten Baerchis sind), sitzt der
-- Ausgleich hier bei den Gegnern:
--
--   ENEMY_ATK_SOFTENING senkt den Angriffswert der Gegner leicht ab, genau so
--   weit, dass die oben nachgerechnete Stage-Kalibrierung wieder stimmt.
--
--   Die Zahl ist NICHT geraten: sie ist mit einer Simulation des kompletten
--   PIT-Laufs bestimmt worden, die den alten Stand (mit DEF) und den neuen
--   gegeneinander gerechnet hat. Bei 0.95 stimmen die Stage-Zahlen ueber alle
--   getesteten Level und PIT-Level auf hoechstens eine Stage genau mit dem
--   Stand vor dem DEF-Ausbau ueberein — und die Werte des angeschlagenen
--   Baerchis (100%/50%/25% HP) sogar exakt. Details im Bericht
--   claude/PROMOTION_CHARMS_ABGESCHLOSSEN.md, Abschnitt Balancing.
--
--   Ein Rest bleibt bewusst stehen: Baerchis mit frueher HOHER Verteidigung
--   (CrystalBaerchi, AncientBaerchi) sind auf hoeheren Leveln etwas staerker
--   geworden. Das ist die logische Folge der Umrechnung — aus einem flachen
--   Prozentsatz sind HP geworden, und HP wachsen mit dem Level mit. Es trifft
--   genau die Baerchis, die als zaeh gedacht waren, und ist deshalb als
--   Verbesserung stehen geblieben statt wegkorrigiert zu werden.
local ENEMY_ATK_SOFTENING = 0.95

-- ============================================================
-- v14: GEGNER-SPD WAECHST MIT DER STAGE
-- ============================================================
-- Seit v14 wertet der Kampf SPD aus (wer schneller ist, handelt oefter).
-- Die Baerchis bekommen +0.02 SPD je Level (BaerchiConfig.SPD_PER_LEVEL).
-- Damit die Kalibrierung oben (Level N schafft etwa N Stages) fuer einen
-- Baerchi mit SPD 1.0 stehen bleibt, waechst die Gegner-SPD genauso: Stage S
-- hat die SPD, die ein Level-S-Baerchi mit Grund-SPD 1.0 haette. Ein
-- Baerchi mit hoeherer Grund-SPD (Kristall-Pfad) handelt dadurch im
-- Verhaeltnis oefter, einer mit niedriger (Gold-Pfad) seltener — genau das
-- ist die Pfad-Identitaet.
local ENEMY_SPD_PER_STAGE = 0.02

-- Sicherheitsnetz gegen Endlos-Laeufe: selbst ein voellig ueberlegener
-- Baerchi hoert hier auf. Rein technisch, kein Balancing-Wert. Seit v15 so
-- gross wie der laengste Tower (Final, 100 Stages); die eigentliche Grenze
-- eines Laufs ist die Stage-Zahl des gewaehlten Towers (TowerConfig).
local MAX_STAGES_PER_RUN = 100

-- Gesamtfaktor auf HP und ATK eines Gegners mit dieser Aequivalenz-Stage
-- (Tower I Stage N = Aequivalenz N). Darf eine Kommazahl sein: Tower II, III
-- und Final wachsen langsamer als 1 Aequivalenz pro Stage.
local function getGrowthForEquivalent(equivalent: number): number
	return math.pow(1 + STAGE_GROWTH, math.max(equivalent, 1) - 1)
end

-- Fertige Gegner-Werte fuer eine Aequivalenz-Stage. TowerConfig rechnet die
-- Aequivalenz aus Tower und Stage, CombatService macht daraus nur noch einen
-- CombatSnapshot.
--
-- Die SPD folgt derselben Aequivalenz: ein Gegner so stark wie Tower-I-Stage
-- 80 ist auch so schnell wie einer dort — dieselbe Regel wie bis v14 ("Stage
-- S hat die SPD eines Level-S-Baerchis").
local function getEnemyStatsForEquivalent(equivalent: number): EnemyStats
	local growth = getGrowthForEquivalent(equivalent)

	return {
		maxHp   = math.max(1, math.floor(ENEMY_BASE.maxHp * growth)),
		atk     = math.max(1, math.floor(ENEMY_BASE.atk * growth * ENEMY_ATK_SOFTENING)),
		spd     = ENEMY_BASE.spd + ENEMY_SPD_PER_STAGE * (math.max(equivalent, 1) - 1),
		pwr     = ENEMY_BASE.pwr,
		skillId = ENEMY_BASE.skillId,
	}
end

-- v15: NUR NOCH FUER MIGRATION UND ALTE SIMULATIONEN. Gegnerstaerke des alten
-- PIT (PIT-Level x Stage). TowerConfig.legacyPitToTower sucht damit die
-- gleich starke Tower-Stage.
local function getLegacyPitGrowth(pitLevel: number, stage: number): number
	local levelPart = 1 + PIT_LEVEL_GROWTH * (math.max(pitLevel, 1) - 1)
	return levelPart * getGrowthForEquivalent(stage)
end

-- Alte Schnittstelle (bis v14): PIT-Level 1 Stage N = Tower I Stage N. Bleibt
-- fuer Debug und alte Sims stehen; ein PIT-Level > 1 wird ueber seine
-- Aequivalenz-Stage abgebildet.
local function getEnemyStats(pitLevel: number, stage: number): EnemyStats
	local growth = getLegacyPitGrowth(pitLevel, stage)
	local equivalent = 1 + math.log(growth) / math.log(1 + STAGE_GROWTH)
	return getEnemyStatsForEquivalent(equivalent)
end

return {
	ENEMY_BASE              = ENEMY_BASE,
	STAGE_GROWTH            = STAGE_GROWTH,
	PIT_LEVEL_GROWTH        = PIT_LEVEL_GROWTH,
	ENEMY_ATK_SOFTENING     = ENEMY_ATK_SOFTENING,
	MAX_STAGES_PER_RUN      = MAX_STAGES_PER_RUN,
	ENEMY_SPD_PER_STAGE     = ENEMY_SPD_PER_STAGE,

	getGrowthForEquivalent     = getGrowthForEquivalent,
	getEnemyStatsForEquivalent = getEnemyStatsForEquivalent,
	getLegacyPitGrowth         = getLegacyPitGrowth,
	getEnemyStats              = getEnemyStats,
}
