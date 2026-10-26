--!strict
-- PotionConfig.luau
-- ReplicatedStorage/Config/PotionConfig.luau
--
-- Einzige Zustaendigkeit:
--   - Alle Zahlen der Traenke (26.10., FeatureFlags.POTIONS_V1): welche Sorten
--     es gibt, Multiplikator und Dauer je Trank, Preisregel, Stapel-Grenze und
--     das wechselnde Sortiment des Haendlers in der Mitte.
--
-- Texte (Name, Beschreibung) stehen NICHT hier, sondern nur in den
-- Sprachdateien (potion.<id>.name / .desc, Localization/Names.potion). Die
-- Regeln (Stapeln, Ablauf, Rotation) stehen in Modules/PotionRules (rein,
-- Test: tools/luau-tests/potions.test.lua).
--
-- ============================================================
-- FUENF SORTEN (kind) — wo der Bonus greift
-- ============================================================
--   strength  Angriff des Baerchis im Tower-Lauf (CombatService, Momentaufnahme
--             beim Start des Laufs)
--   coins     Pfotenmuenzen-EINKOMMEN (EconomyService.awardGummies: Tower-
--             Stages, Events, Waben-Recycler). Erstattungen und Verkaufswerte
--             (awardGummiesFlat) bleiben unveraendert.
--   speed     Laufgeschwindigkeit des Spielers (CombConfig.BASE_WALK_SPEED x
--             Faktor; Waben bremsen weiter anteilig)
--   luck      Ei oeffnen: alle Ergebnisse ausser dem haeufigsten bekommen das
--             x-fache Gewicht (dieselbe Idee wie der Inkubator-Gluecksbonus)
--   petxp     XP je verfuettertem Honig (HoneyService.feed)
--
-- ============================================================
-- PREIS
-- ============================================================
-- Pfotenmuenzen wachsen ueber die Tower um Groessenordnungen (Tower I Stage 10
-- ~1.100, Final Stage 10 ~40 Mio.). Ein fester Preis waere entweder sofort
-- bedeutungslos oder fuer Neulinge unerreichbar. Deshalb kostet ein Trank
-- `stagePrice` Stage-Belohnungen der besten Stage DIESES Lebens (hoechster
-- Tower mit island.stageBest, mal rebirthMult — so wie das Einkommen), aber
-- nie weniger als `minPrice`. Neuling: Tower I Stage 1 = 3 Muenzen -> es gilt
-- minPrice. Ein Rebirth setzt stageBest zurueck, der Preis faellt mit dem
-- Einkommen. PotionService.priceReference rechnet die Bezugsgroesse.

local PotionConfig = {}

export type Kind = "strength" | "coins" | "speed" | "luck" | "petxp"

export type PotionDef = {
	id              : string,   -- Text: potion.<id>.name / potion.<id>.desc
	kind            : Kind,
	tier            : number,   -- 1 = kleiner Trank, 2 = grosser Trank (nur Anzeige/Reihung)
	multiplier      : number,   -- > 1; x1.5 = +50 %
	durationSeconds : number,   -- Laufzeit ab Kauf
	stagePrice      : number,   -- Preis in Stage-Belohnungen der aktuellen Tiefe
	minPrice        : number,   -- Untergrenze in Pfotenmuenzen
	weight          : number,   -- Gewicht im Los des Sortiments (grosse seltener)
	color           : Color3,   -- Flaeschchen (Regal am Stand, Karte im Fenster, HUD-Chip)
}

-- Reihenfolge = Anzeige-Reihenfolge (HUD, Haendler)
PotionConfig.KINDS = { "strength", "coins", "speed", "luck", "petxp" } :: { Kind }

-- Sprachneutrale Zeichen je Sorte (Rueckfall, solange es kein Bild gibt;
-- Icons.make zeigt das Zeichen, wenn das Bild fehlt)
PotionConfig.GLYPH = {
	strength = "⚔",
	coins    = "💰",
	speed    = "⚡",
	luck     = "🍀",
	petxp    = "⭐",
} :: { [string]: string }

local MIN = 60

local function potion(id: string, kind: Kind, tier: number, multiplier: number, minutes: number,
	stagePrice: number, minPrice: number, weight: number, color: Color3): PotionDef
	return {
		id = id, kind = kind, tier = tier, multiplier = multiplier,
		durationSeconds = minutes * MIN, stagePrice = stagePrice, minPrice = minPrice,
		weight = weight, color = color,
	}
end

-- Zehn Traenke: je Sorte ein kleiner (I) und ein grosser (II). Der grosse
-- wirkt staerker UND laenger, ist aber teurer und seltener im Angebot.
PotionConfig.POTIONS = {
	potion("StrengthI",  "strength", 1, 1.5, 10, 5,  60,  3, Color3.fromRGB(255,  96,  96)),
	potion("StrengthII", "strength", 2, 2.0, 15, 12, 180, 1, Color3.fromRGB(214,  40,  40)),
	potion("CoinsI",     "coins",    1, 1.5, 10, 5,  60,  3, Color3.fromRGB(255, 196,  60)),
	potion("CoinsII",    "coins",    2, 2.0, 15, 12, 180, 1, Color3.fromRGB(230, 150,  20)),
	potion("SpeedI",     "speed",    1, 1.25, 10, 4, 50,  3, Color3.fromRGB(120, 200, 255)),
	potion("SpeedII",    "speed",    2, 1.5, 15, 10, 150, 1, Color3.fromRGB( 40, 140, 240)),
	potion("LuckI",      "luck",     1, 1.5, 10, 6,  80,  3, Color3.fromRGB(120, 230, 120)),
	potion("LuckII",     "luck",     2, 2.0, 15, 14, 220, 1, Color3.fromRGB( 40, 170,  70)),
	potion("PetXpI",     "petxp",    1, 1.5, 10, 5,  60,  3, Color3.fromRGB(210, 150, 255)),
	potion("PetXpII",    "petxp",    2, 2.0, 15, 12, 180, 1, Color3.fromRGB(150,  70, 230)),
} :: { PotionDef }

-- Stapel-Regeln (Modules/PotionRules.check):
--   * verschiedene Sorten laufen unabhaengig nebeneinander (bis zu fuenf)
--   * gleiche Sorte, gleicher Multiplikator: die Zeit wird angehaengt ("extend")
--   * gleiche Sorte, staerker: ersetzt den laufenden Trank samt Restzeit ("replace")
--   * gleiche Sorte, schwaecher: Kauf abgelehnt, nichts abgebucht ("weaker")
--   * mehr Restzeit als MAX_REMAINING_SECONDS je Sorte gibt es nicht ("maxtime")
PotionConfig.MAX_REMAINING_SECONDS = 60 * MIN

-- Wie oft der Server abgelaufene Effekte austraegt (Sekunden). Reine Technik.
PotionConfig.TICK_SECONDS = 1

-- Der Haendler in der Mitte (EggMerchantService): das Basis-Ei ist immer da
-- (fester erster Platz), dazu SLOTS_MIN..SLOTS_MAX Traenke aus dem Los —
-- zusammen also hoechstens MAX_ITEMS Angebote. Das Los haengt am
-- 5-Minuten-Fenster der Weltzeit (PotionRules.windowOf): alle Server zeigen
-- dasselbe Sortiment, und der Wechsel faellt auf volle 5 Minuten.
PotionConfig.MERCHANT = {
	ROTATE_SECONDS = 5 * MIN,
	SLOTS_MIN      = 3,
	SLOTS_MAX      = 5,
	MAX_ITEMS      = 6,   -- 1 Ei + SLOTS_MAX Traenke
}

local BY_ID: { [string]: PotionDef } = {}
for _, def in PotionConfig.POTIONS do
	BY_ID[def.id] = def
end

function PotionConfig.byId(id: string): PotionDef?
	return BY_ID[id]
end

function PotionConfig.isKind(value: any): boolean
	return typeof(value) == "string" and table.find(PotionConfig.KINDS, value :: any) ~= nil
end

return PotionConfig
