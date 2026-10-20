--!strict
-- IncubatorConfig.luau
-- ReplicatedStorage/Config/IncubatorConfig.luau
--
-- Einzige Zustaendigkeit:
--   - Alle Zahlen des Solo-Inkubators (15.10.2026): Stufen, Lager, Tempo,
--     Ausbau-Voraussetzungen, Brut-Takt, Platz auf dem Plot.
--
-- Der Inkubator ist ein einziger Platz: EIN Baerchi sitzt darin und bruetet
-- im Takt seiner Rarity Eier. Die Eier fallen nicht mehr neben den Inkubator,
-- sondern werden IM Inkubator gesammelt (Lager, Grenze je Stufe) und per
-- Abholen ins normale Ei-Lager gelegt. Vier Stufen = vier Modelle
-- (Config/IncubatorModels): Stufe 1 + drei Ausbauten im Spielverlauf.
--
-- Der Ausbau braucht Rebirths UND Gummies, und er geht beim Rebirth NICHT
-- verloren (RebirthService traegt den ganzen Inkubator-Stand weiter).
--
-- Die Regeln stehen als reine Funktionen in Modules/IncubatorRules.

local IncubatorConfig = {}

-- Genau ein Baerchi-Platz.
IncubatorConfig.MAX_SLOTS = 1

-- Stufe 1 = Grundstufe, 2..4 = die drei Ausbauten.
--   capacity   Eier, die der Inkubator sammeln kann, bevor er pausiert
--   speed      Tempo-Faktor auf den Brut-Takt (bewusst nur leicht)
--   rebirths   noetige Rebirths fuer DIESE Stufe
--   costLevel  Kosten = EconomyConfig.HONEY_UPGRADE_COSTS[costLevel].gummies
--              x COST_FACTOR (wie die Gebaeude-Kurve, daher gleiche Groessenordnung)
-- ANNAHME (zum Nachstellen): Rebirth 1 / 3 / 6, Kosten wie Gebaeude-Level 15 / 35 / 55.
IncubatorConfig.LEVELS = {
	[1] = { capacity = 6,  speed = 1.00 },
	[2] = { capacity = 12, speed = 1.03, rebirths = 1, costLevel = 15 },
	[3] = { capacity = 24, speed = 1.06, rebirths = 3, costLevel = 35 },
	[4] = { capacity = 48, speed = 1.10, rebirths = 6, costLevel = 55 },
} :: { [number]: { capacity: number, speed: number, rebirths: number?, costLevel: number? } }
IncubatorConfig.MAX_LEVEL   = 4
IncubatorConfig.COST_FACTOR = 1

-- Takt in Sekunden pro Ei auf Stufe 1, je Rarity des Baerchis im Inkubator.
-- Hoehere Rarity = schnellerer Takt (und bessere Eier aus der eigenen
-- eggTable). Bewusst langsamer als das Legen des ausgeruesteten Baerchis:
-- der Inkubator ist ein Zusatz, kein Ersatz. ANNAHME, zum Nachstellen.
IncubatorConfig.BREED_SECONDS_BY_RARITY = {
	Common = 180,
	Uncommon = 210,
	Rare = 240,
	Epic = 270,
	Legendary = 300,
	Mythic = 330,
	Divine = 360,
	Cosmic = 390,
	Secret = 420,
	Godly = 450,
	Eternal = 480,
	Omega = 510,
} :: { [string]: number }
IncubatorConfig.BREED_DEFAULT_SECONDS = 300

-- Hoehe der Mini-Figur in der Kuppel (Studs). Kuppel-Innenraum: Radius 3,2.
IncubatorConfig.BREED_FIGURE_HEIGHT = 3.2

-- Aussehen auf dem Plot (Plot-Koordinaten, siehe IncubatorBuilder). Steht auf
-- dem Beet links hinten. Teile je Stufe: siehe Config/IncubatorModels
-- (hoechstens PART_BUDGET).
IncubatorConfig.LOOK = {
	offset       = Vector3.new(-20, 0, 20),
	signDistance = 80,
}
IncubatorConfig.PART_BUDGET = 20

-- Gluecks-Bonus (15.10.): waechst, solange ein Baerchi im Inkubator sitzt und der
-- Spieler online ist, von 0 auf MAX_PERCENT (linear ueber MAX_SECONDS). Er wirkt auf
-- die Eier-Wuerfe des Inkubators: alle Eier ausser dem haeufigsten bekommen
-- (1 + Bonus) mal ihr Gewicht. Nichts davon wird gespeichert: beim Verlassen, beim
-- Herausnehmen oder Tauschen des Baerchis beginnt er wieder bei 0.
-- ANNAHME (zum Nachstellen): 90 Minuten bis +50 %.
IncubatorConfig.LUCK = {
	MAX_SECONDS = 90 * 60,
	MAX_PERCENT = 50,
}

IncubatorConfig.MODEL_NAME = "Incubator"

return IncubatorConfig
