--!strict
-- EggConfig.luau
-- ReplicatedStorage/Config/EggConfig.luau
--
-- Egg-Typen mit Hatch-Wahrscheinlichkeiten und Kosten.
-- Getrennt von BaerchiConfig: Egg-Balance != Baerchi-Balance.
-- GachaRoller liest die HatchTable, EconomyConfig liest den Preis.
--
-- Seit v10 steht hier ausserdem alles, was das EI-LEGEN steuert (Abschnitt
-- ganz unten). Bewusst hier und nicht in einer eigenen Datei: es ist
-- dieselbe Domaene — welche Eier es gibt, woher sie kommen und was aus ihnen
-- schluepft. Was der EINZELNE Baerchi legt (Tempo und Chancen), gehoert
-- dagegen zu ihm und steht in BaerchiConfig.

local Types = require(script.Parent.Parent.Network.Types)

-- Wahrscheinlichkeiten muessen pro Egg genau 1.0 ergeben.
-- Format: { configId = Gewichtung }  (wird von GachaRoller normalisiert)
export type HatchTable = { [string]: number }

export type EggDef = {
	id          : Types.EggType,
	displayName : string,
	hatchTable  : HatchTable,
	hatchTime   : number,   -- Sekunden bis das Ei ausgebruetet ist (fest, seit v4 ohne Gebaeude-Reduktion)
	costGummies : number,   -- Kaufpreis in Gummies (0 = nicht kaufbar)
	costGoldGummies : number, -- Kaufpreis in GoldGummies (0 = nicht kaufbar)
	description : string,

	-- Farbe des gelegten Eis in der Welt (MapService) und der Anzeige im UI.
	-- Steht hier statt im Client-Theme, weil Server und Client dieselbe Farbe
	-- brauchen — dieselbe Begruendung wie bei BaerchiConfig.RARITY_COLORS.
	color       : Color3,
	shortName   : string,   -- kurze Beschriftung ueber dem gelegten Ei
}

local EGGS: { [Types.EggType]: EggDef } = {

	BasicEgg = {
		id          = "BasicEgg",
		displayName = "Basis-Ei",
		hatchTime   = 5,
		costGummies = 50,
		costGoldGummies = 0,
		description = "Ein ganz normales Ei. Was wird wohl raus kommen?",
		color       = Color3.fromRGB(238, 232, 214),
		shortName   = "Basis",
		hatchTable  = {
			-- Common: 70%, Uncommon: 25%, Rare: 5%
			RedBaerchi    = 25,
			GreenBaerchi  = 25,
			YellowBaerchi = 20,
			BlueBaerchi   = 15,
			OrangeBaerchi = 10,
			SugarBaerchi  = 4,
			CrystalBaerchi= 1,
		},
	},

	SugarEgg = {
		id          = "SugarEgg",
		displayName = "Zucker-Ei",
		hatchTime   = 15,
		costGummies = 250,
		costGoldGummies = 0,
		description = "Schmeckt suess. Der Inhalt auch.",
		color       = Color3.fromRGB(255, 168, 205),
		shortName   = "Zucker",
		hatchTable  = {
			-- Uncommon: 50%, Rare: 38%, Epic: 12%
			BlueBaerchi   = 28,
			OrangeBaerchi = 22,
			SugarBaerchi  = 22,
			CrystalBaerchi= 16,
			GoldenGrizzly = 9,
			VoidBaerchi   = 3,
		},
	},

	GoldenEgg = {
		id          = "GoldenEgg",
		displayName = "Goldenes Ei",
		hatchTime   = 45,
		costGummies = 0,
		costGoldGummies = 10,
		description = "Glitzert verdaechtig. Rare oder besser garantiert.",
		color       = Color3.fromRGB(255, 205,  74),
		shortName   = "Gold",
		hatchTable  = {
			-- Rare: 45%, Epic: 45%, Legendary: 10%
			SugarBaerchi   = 25,
			CrystalBaerchi = 20,
			GoldenGrizzly  = 28,
			VoidBaerchi    = 17,
			RainbowBaerchi = 6,
			AncientBaerchi = 4,
		},
	},

	CrystalEgg = {
		id          = "CrystalEgg",
		displayName = "Kristall-Ei",
		hatchTime   = 120,
		costGummies = 0,
		costGoldGummies = 50,
		description = "Durchsichtig. Man sieht schon fast was drin ist.",
		color       = Color3.fromRGB(150, 226, 255),
		shortName   = "Kristall",
		hatchTable  = {
			-- Epic: 55%, Legendary: 40%, Mythic: 5%
			GoldenGrizzly  = 30,
			VoidBaerchi    = 25,
			RainbowBaerchi = 22,
			AncientBaerchi = 18,
			CosmicBaerchi  = 5,
		},
	},

	AscensionEgg = {
		id          = "AscensionEgg",
		displayName = "Ascensions-Ei",
		hatchTime   = 300,
		costGummies = 0,
		costGoldGummies = 0,   -- nicht kaufbar, nur durch Rebirth-Meilensteine
		description = "Verdient, nicht gekauft. Legendary garantiert.",
		color       = Color3.fromRGB(196, 128, 255),
		shortName   = "Ascension",
		hatchTable  = {
			-- Legendary: 85%, Mythic: 15%
			RainbowBaerchi = 45,
			AncientBaerchi = 40,
			CosmicBaerchi  = 15,
		},
	},
}

-- Hilfsfunktion: Hatch-Table als normalisierte Gewichtungs-Liste
-- GachaRoller benutzt dies direkt
local function getNormalizedTable(eggType: Types.EggType): { configId: string, weight: number }
	local def = EGGS[eggType]
	assert(def, "EggConfig: unbekannter EggType " .. eggType)

	local total = 0
	for _, w in def.hatchTable do total += w end

	local result = {}
	for id, w in def.hatchTable do
		table.insert(result, { configId = id, weight = w / total })
	end
	return result
end

--------------------------------------------------------------------------------
-- EIER LEGEN
--------------------------------------------------------------------------------
--
-- Der ausgeruestete Baerchi legt regelmaessig ein Ei dort ab, wo er gerade
-- steht. Es bleibt als anklickbares Objekt in der Welt liegen, bis der Spieler
-- es einsammelt — dann landet es in island.eggStock und laesst sich wie ein
-- gekauftes Ei ausbrueten.
--
-- Die Zahlen HIER gelten fuer alle Baerchis. Was ein EINZELNER legt und wie
-- schnell, steht bei ihm in BaerchiConfig (layIntervalSeconds / eggTable).
--
-- ============================================================
-- WARUM DAS LEVEL HIER LINEAR WIRKT UND NICHT EXPONENTIELL
-- ============================================================
-- HP und ATK wachsen mit 1.1^(level-1), auf Level 50 also auf das 106-fache.
-- Das ist dort richtig, weil die PIT-Gegner mit derselben Kurve mitwachsen —
-- es gibt eine Gegenseite.
--
-- Beim Ei-Legen gibt es die nicht. Dieselbe Kurve wuerde bedeuten: ein
-- Level-50-Baerchi legt 106-mal so schnell, also alle zwei bis neun Sekunden.
-- Der individuelle Grundwert jedes Baerchis waere damit bedeutungslos, und die
-- Obergrenze unten waere binnen einer Minute erreicht — die ganze Mechanik
-- liefe leer.
--
-- Deshalb addiert jedes Level hier 10% des GRUNDWERTS statt 10% des Vorwerts:
-- auf Level 50 legt ein Baerchi knapp 6-mal so schnell wie auf Level 1. Das
-- ist spuerbar, laesst die Unterschiede zwischen den Baerchis aber bestehen.
--
-- Wer das doch exponentiell haben will: LAY_LEVEL_GAIN durch
-- CombatCalculator.getLevelGrowth ersetzen — es ist genau eine Zeile in
-- EggCalculator.
local LAY_LEVEL_GAIN = 0.10

-- Was eine EGG-Stat-Stufe bringt (waechst ueber Event-Teilnahme, gedeckelt
-- durch die Rarity — siehe PromotionConfig). Ein Legendary am Cap (24) legt
-- damit knapp dreimal so schnell.
--
-- Die Zahl steht bewusst NICHT in PromotionConfig.STAT_LEVEL_GAIN wie die
-- vier Kampf-Stats: die wirken alle in CombatCalculator, diese hier wirkt
-- ausschliesslich im Ei-System. Sie neben den Kampfwerten abzulegen waere die
-- naechste Stelle, an der jemand beim Balancing am falschen Wert dreht.
local LAY_STAT_LEVEL_GAIN = 0.08

-- Wie viel langsamer offline gelegt wird.
--
-- Die Produktion laeuft weiter, waehrend der Spieler weg ist (dasselbe
-- Zeitstempel-Verfahren wie beim Honig, kein Server-Loop noetig) — aber
-- gebremst. Anwesenheit soll sich lohnen, ohne dass Abwesenheit bestraft wird.
local OFFLINE_SLOWDOWN = 2.5

-- Wie viele NICHT eingesammelte Eier gleichzeitig herumliegen duerfen.
--
-- Ist die Grenze erreicht, hoert der Baerchi auf zu legen — genau wie ein
-- volles Honig-Lager die Produktion anhaelt. Laenger wegbleiben bringt also
-- nichts zusaetzlich, und der Plot wird nie zum Ei-Teppich.
local MAX_UNCOLLECTED_EGGS = 12

-- Absolute Untergrenze, egal wie viel Level, Stufen und Charms
-- zusammenkommen. Reines Sicherheitsnetz gegen eine Kombination, an die beim
-- Balancing niemand gedacht hat — kein Balancing-Wert.
local MIN_LAY_INTERVAL_SECONDS = 15

-- Wie weit ein gelegtes Ei seitlich neben dem Baerchi landet (Studs). Ohne
-- diesen Versatz laegen mehrere Eier exakt uebereinander, wenn der Baerchi
-- laenger an derselben Stelle steht.
local LAY_SCATTER_RADIUS = 4.5

-- Groesse des Eis in der Welt. Bewusst klein: es sollen bis zu zwoelf davon
-- auf einem Plot liegen koennen, ohne dass man den Baerchi nicht mehr sieht.
local LAY_EGG_SIZE = Vector3.new(1.7, 2.3, 1.7)

-- Ab welcher Entfernung die Beschriftung ueber einem Ei ausgeblendet wird.
local LAY_LABEL_DISTANCE = 60

-- Gewichtete Ei-Auswahl fuer einen Baerchi.
--
-- `eggTable` kommt aus BaerchiConfig und ist pro Baerchi verschieden. Die
-- Gewichte muessen sich zu nichts Bestimmtem addieren — hier wird normalisiert,
-- damit man in der Config mit runden Zahlen arbeiten kann.
--
-- Gibt nil zurueck, wenn die Tabelle leer oder unbrauchbar ist. Der Aufrufer
-- legt dann kein Ei, statt eines zu erfinden.
local function rollEggType(eggTable: { { eggType: Types.EggType, weight: number } }): Types.EggType?
	local total = 0
	for _, entry in eggTable do
		if entry.weight > 0 then
			total += entry.weight
		end
	end

	if total <= 0 then
		return nil
	end

	local roll        = math.random() * total
	local accumulated = 0

	for _, entry in eggTable do
		if entry.weight > 0 then
			accumulated += entry.weight
			if roll < accumulated then
				return entry.eggType
			end
		end
	end

	-- Rundungsrest: der letzte gueltige Eintrag.
	for i = #eggTable, 1, -1 do
		if eggTable[i].weight > 0 then
			return eggTable[i].eggType
		end
	end
	return nil
end

return {
	data               = EGGS,
	getNormalizedTable = getNormalizedTable,

	LAY_LEVEL_GAIN           = LAY_LEVEL_GAIN,
	LAY_STAT_LEVEL_GAIN      = LAY_STAT_LEVEL_GAIN,
	OFFLINE_SLOWDOWN         = OFFLINE_SLOWDOWN,
	MAX_UNCOLLECTED_EGGS     = MAX_UNCOLLECTED_EGGS,
	MIN_LAY_INTERVAL_SECONDS = MIN_LAY_INTERVAL_SECONDS,
	LAY_SCATTER_RADIUS       = LAY_SCATTER_RADIUS,
	LAY_EGG_SIZE             = LAY_EGG_SIZE,
	LAY_LABEL_DISTANCE       = LAY_LABEL_DISTANCE,

	rollEggType = rollEggType,
}
