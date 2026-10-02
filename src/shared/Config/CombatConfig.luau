--!strict
-- CombatConfig.luau
-- ReplicatedStorage/Config/CombatConfig.luau
--
-- Alle Zahlen der PIT-Gegner an einer Stelle.
-- CombatService baut daraus die Gegner und rechnet selbst nichts aus.
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
-- Zwei Achsen machen die Gegner staerker:
--   1. PIT_LEVEL_GROWTH — das kauft der Spieler bewusst (hoeheres PIT-Level
--      heisst staerkere Gegner UND mehr Gummies pro Stage).
--   2. Stage-Wachstum innerhalb eines Laufs — das passiert automatisch und
--      begrenzt, wie weit man mit einem gegebenen Baerchi kommt.
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
-- Auf hoeheren PIT-Leveln (Level-10-Baerchi): PIT 3 → 6 Stages, PIT 5 → 4.

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

-- Zuwachs pro PIT-Level (additiv auf den Grundwert: Level 3 = +50%).
-- Ein Level-10-Baerchi schafft damit auf PIT 1 zehn Stages, auf PIT 3 noch
-- sechs, auf PIT 5 noch vier — dafuer gibt jede Stage deutlich mehr Gummies.
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

-- Sicherheitsnetz gegen Endlos-Laeufe: selbst ein voellig ueberlegener
-- Baerchi hoert hier auf. Rein technisch, kein Balancing-Wert.
local MAX_STAGES_PER_RUN = 60

-- Gesamtfaktor auf HP und ATK eines Gegners.
local function getEnemyGrowth(pitLevel: number, stage: number): number
	local levelPart = 1 + PIT_LEVEL_GROWTH * (math.max(pitLevel, 1) - 1)
	local stagePart = math.pow(1 + STAGE_GROWTH, math.max(stage, 1) - 1)
	return levelPart * stagePart
end

-- Fertige Gegner-Werte fuer eine Stage. CombatService macht daraus nur noch
-- einen CombatSnapshot.
local function getEnemyStats(pitLevel: number, stage: number): EnemyStats
	local growth = getEnemyGrowth(pitLevel, stage)

	return {
		maxHp   = math.max(1, math.floor(ENEMY_BASE.maxHp * growth)),
		atk     = math.max(1, math.floor(ENEMY_BASE.atk * growth * ENEMY_ATK_SOFTENING)),
		spd     = ENEMY_BASE.spd,
		pwr     = ENEMY_BASE.pwr,
		skillId = ENEMY_BASE.skillId,
	}
end

return {
	ENEMY_BASE              = ENEMY_BASE,
	STAGE_GROWTH            = STAGE_GROWTH,
	PIT_LEVEL_GROWTH        = PIT_LEVEL_GROWTH,
	ENEMY_ATK_SOFTENING     = ENEMY_ATK_SOFTENING,
	MAX_STAGES_PER_RUN      = MAX_STAGES_PER_RUN,

	getEnemyGrowth = getEnemyGrowth,
	getEnemyStats  = getEnemyStats,
}
