--!strict
-- BuildingBehavior.luau
-- ReplicatedStorage/Config/BuildingBehavior.luau
--
-- Einzige Zustaendigkeit:
--   - Alles, was pro Types.BuildingId unterschiedlich ist: was ein Gebaeude
--     kann, was sein Ausbau kostet und wie sein Effekt heisst.
--
-- ============================================================
-- DIE DREI ROLLEN
-- ============================================================
-- Bis v6 taten die drei Gebaeude bis auf eine einzige Zahl dasselbe: Honig
-- produzieren, dessen XP am eigenen Level hing. Ausbauen war dreimal dieselbe
-- Entscheidung mit einem anderen Namen darueber. Seit v7 hat jedes Gebaeude
-- genau EINE eigene Achse — und damit einen eigenen Grund, es auszubauen:
--
--   Beehive     VOLUMEN    Lager waechst, und es produziert schneller.
--                          Der "ich brauche ueberhaupt viel Honig"-Baustein.
--
--   HoneyPot    HEILUNG    Sein Honig heilt mehr HP — nur SEINER.
--                          Der "ich will zwischen zwei PIT-Laeufen schnell
--                          wieder kampffaehig sein"-Baustein. Passt zu seinem
--                          Teich auf dem Plot, an dem der Baerchi frisst.
--
--   HoneyPress  WACHSTUM   Ihr Level hebt die XP von JEDEM Honig, egal aus
--                          welchem Gebaeude er kommt. Der "ich will schneller
--                          leveln"-Baustein.
--
-- Daraus entsteht die eigentliche Entscheidung im Spiel: Honigtopf-Honig heilt
-- am meisten, ist aber knapp — verfuettert man ihn jetzt fuer XP, fehlt er
-- nach dem naechsten Kampf. Die XP sind ueberall gleich, es lohnt sich also,
-- den Heil-Honig aufzuheben.
--
-- ============================================================
-- WARUM ALLES HIER STEHT
-- ============================================================
-- Kein Service und kein Panel verzweigt mehr nach einer BuildingId. Ein
-- Gebaeude aendern oder hinzufuegen heisst: EINEN Eintrag in BEHAVIORS
-- anfassen. Auch die Ausbau-Tabellen liegen deshalb hier und nicht mehr in
-- EconomyConfig — sie tragen den Effekt-Text, und der beschreibt genau die
-- Mechanik, die hier definiert ist.
--
-- Die Abhaengigkeit geht nur in EINE Richtung: BuildingBehavior kennt
-- EconomyConfig (Basiswerte, Kostenkurve), EconomyConfig kennt
-- BuildingBehavior nicht. Andersherum waere es ein Ringschluss.
--
-- BALANCE-AUFTEILUNG: was fuer ALLE gilt (Basis-Intervall, Basis-Lager,
-- Basis-Heilung, XP-Kurve, Kostenkurve, Maximal-Level) steht in EconomyConfig.
-- Hier steht nur, wie weit ein EINZELNES Gebaeude davon abweicht.

local EconomyConfig = require(script.Parent.EconomyConfig)
local Types         = require(script.Parent.Parent.Network.Types)

--------------------------------------------------------------------------------
-- Abweichungen der einzelnen Gebaeude (Werte auf Maximal-Level)
--------------------------------------------------------------------------------

-- Bienenstock — Volumen.
-- Lager waechst von EconomyConfig.HONEY_CAPACITY auf diesen Wert, das
-- Produktions-Intervall faellt von EconomyConfig.HONEY_INTERVAL_SECONDS auf
-- dieses Minimum. Beides linear ueber die Level.
--
-- Das schnellere Produzieren lag bis v6 beim Honigtopf. Es ist mit dem Redesign
-- zum Bienenstock gewandert, weil "mehr Honig pro Zeit" und "mehr Honig auf
-- Lager" dieselbe Achse sind — und der Honigtopf dafuer die Heilung bekommt.
--
-- 14 ist mit Absicht kein runder Wert: 5 auf Level 1 und 14 auf Level 10 sind
-- neun Stufen und neun Honig — so bringt JEDER Ausbau genau einen Platz mehr.
-- Bei 12 waeren zwei Stufen dabei, auf denen sich am Lager nichts tut, und ein
-- Ausbau, der sichtbar nichts bringt, ist genau die Enttaeuschung, die dieses
-- Redesign abschaffen soll.
local BEEHIVE_MAX_CAPACITY         = 14
local BEEHIVE_MIN_INTERVAL_SECONDS = 8

-- Honigtopf — Heilung.
-- Heil-Anteil pro Honig AUS DIESEM TOPF, waechst von
-- EconomyConfig.HONEY_HEAL_PERCENT auf diesen Wert. Auf Maximal-Level machen
-- also zwei seiner Honige einen erschoepften Baerchi wieder voll.
local HONEYPOT_MAX_HEAL_PERCENT = 0.60

-- Honig-Presse — Wachstum.
-- Ihr XP-Multiplikator kommt NICHT aus einer eigenen Zahl, sondern direkt aus
-- der vorhandenen XP-Kurve (EconomyConfig.HONEY_XP), geteilt durch deren
-- Startwert. Damit ist die Progression bei "Presse auf Level N" exakt
-- dieselbe wie vorher bei "Gebaeude auf Level N" — das Redesign verschiebt nur,
-- WER die Kurve besitzt, und aendert keine einzige XP-Zahl.

--------------------------------------------------------------------------------
-- Kleine Rechen-Hilfen
--------------------------------------------------------------------------------

-- Linear von `from` (Level 1) nach `to` (Maximal-Level).
local function byLevel(from: number, to: number, level: number): number
	local clamped = EconomyConfig.clampBuildingLevel(level)

	-- max(1, ...) nur als Division-durch-Null-Schutz, falls MAX_BUILDING_LEVEL
	-- je auf 1 gesetzt wird. Bei jedem sinnvollen Wert aendert es nichts.
	local steps = math.max(1, EconomyConfig.MAX_BUILDING_LEVEL - 1)

	return from + (to - from) * ((clamped - 1) / steps)
end

local function roundToInt(value: number): number
	return math.floor(value + 0.5)
end

local function percentText(value: number): string
	return tostring(roundToInt(value * 100)) .. "%"
end

--------------------------------------------------------------------------------
-- Verhaltens-Objekte
--------------------------------------------------------------------------------

export type Behavior = {
	-- Sekunden, bis dieses Gebaeude auf diesem Level den naechsten Honig hat.
	getIntervalSeconds : (level: number) -> number,

	-- Wie viel Honig dieses Gebaeude auf diesem Level lagern kann.
	getCapacity : (level: number) -> number,

	-- Anteil der maximalen HP, den EIN Honig AUS DIESEM Gebaeude heilt.
	getHealPercent : (level: number) -> number,

	-- Faktor, den dieses Gebaeude zur XP JEDES Honigs beitraegt (1 = keiner).
	getXpMultiplier : (level: number) -> number,

	-- Der Effekt dieses Gebaeudes auf diesem Level, in eigenen Worten.
	describe : (level: number) -> string,
}

local BASE_INTERVAL = EconomyConfig.HONEY_INTERVAL_SECONDS
local BASE_CAPACITY = EconomyConfig.HONEY_CAPACITY
local BASE_HEAL     = EconomyConfig.HONEY_HEAL_PERCENT

-- Vorgaben fuer jede Achse, auf der ein Gebaeude NICHT sein Schwerpunkt hat.
local function baseInterval(_level: number): number  return BASE_INTERVAL end
local function baseCapacity(_level: number): number  return BASE_CAPACITY end
local function baseHeal(_level: number): number      return BASE_HEAL end
local function noXpBonus(_level: number): number     return 1 end

--------------------------------------------------------------------------------
-- Beehive — Volumen
--------------------------------------------------------------------------------

local function beehiveInterval(level: number): number
	return byLevel(BASE_INTERVAL, BEEHIVE_MIN_INTERVAL_SECONDS, level)
end

local function beehiveCapacity(level: number): number
	return roundToInt(byLevel(BASE_CAPACITY, BEEHIVE_MAX_CAPACITY, level))
end

local function beehiveDescribe(level: number): string
	return string.format(
		"Lager: %d Honig  —  alle %.1f s ein neuer",
		beehiveCapacity(level),
		beehiveInterval(level)
	)
end

--------------------------------------------------------------------------------
-- HoneyPot — Heilung
--------------------------------------------------------------------------------

local function honeyPotHeal(level: number): number
	return byLevel(BASE_HEAL, HONEYPOT_MAX_HEAL_PERCENT, level)
end

local function honeyPotDescribe(level: number): string
	return string.format(
		"Sein Honig heilt %s der HP  —  der beste nach einem Kampf",
		percentText(honeyPotHeal(level))
	)
end

--------------------------------------------------------------------------------
-- HoneyPress — Wachstum
--------------------------------------------------------------------------------

-- Der Multiplikator ist die XP-Kurve, bezogen auf ihren eigenen Startwert:
-- Level 1 = Faktor 1 (kein Bonus), Maximal-Level = voller Kurvenwert.
local function pressXpMultiplier(level: number): number
	local base = EconomyConfig.getHoneyXp(1)
	if base <= 0 then return 1 end
	return EconomyConfig.getHoneyXp(level) / base
end

local function pressDescribe(level: number): string
	local bonus = pressXpMultiplier(level) - 1

	if bonus <= 0 then
		return "Noch kein XP-Bonus — jede Stufe hebt die XP JEDES Honigs"
	end

	return string.format("+%s XP auf JEDEN Honig, egal woher er kommt", percentText(bonus))
end

--------------------------------------------------------------------------------
-- Die Tabelle
--------------------------------------------------------------------------------

local BEHAVIORS: { [Types.BuildingId]: Behavior } = {
	Beehive = {
		getIntervalSeconds = beehiveInterval,
		getCapacity        = beehiveCapacity,
		getHealPercent     = baseHeal,
		getXpMultiplier    = noXpBonus,
		describe           = beehiveDescribe,
	},

	HoneyPot = {
		getIntervalSeconds = baseInterval,
		getCapacity        = baseCapacity,
		getHealPercent     = honeyPotHeal,
		getXpMultiplier    = noXpBonus,
		describe           = honeyPotDescribe,
	},

	HoneyPress = {
		getIntervalSeconds = baseInterval,
		getCapacity        = baseCapacity,
		getHealPercent     = baseHeal,
		getXpMultiplier    = pressXpMultiplier,
		describe           = pressDescribe,
	},
}

-- Fallback fuer kaputte Spielstaende mit einer id, die es nicht (mehr) gibt:
-- lieber die Basis-Mechanik als ein Fehler mitten in der Honig-Abrechnung.
local DEFAULT_BEHAVIOR: Behavior = {
	getIntervalSeconds = baseInterval,
	getCapacity        = baseCapacity,
	getHealPercent     = baseHeal,
	getXpMultiplier    = noXpBonus,
	describe           = function(_level: number): string return "Produziert Honig" end,
}

--------------------------------------------------------------------------------
-- Ausbau-Kosten und -Texte, pro Gebaeude
--------------------------------------------------------------------------------
--
-- Drei EIGENE Tabellen statt der einen gemeinsamen von frueher: der
-- Effekt-Text unterscheidet sich jetzt pro Gebaeude, weil sich die Mechanik
-- unterscheidet. Die KOSTEN sind bewusst weiterhin fuer alle drei gleich
-- (EconomyConfig.HONEY_UPGRADE_COSTS) — an den Preisen zu drehen waere eine
-- Balance-Aenderung, die niemand bestellt hat, und laufende Spielstaende
-- wuerden es sofort merken.
--
-- Der Text wird ERZEUGT, nicht von Hand gepflegt: er ist genau die describe()
-- des Gebaeudes auf der Stufe, die man kauft. Anzeige und Wirkung koennen
-- damit gar nicht auseinanderlaufen.

export type UpgradeDef = {
	costGummies     : number,
	costGoldGummies : number,
	effect          : string,   -- was DIESE Stufe kann (erzeugt aus describe)
}

local BUILDING_UPGRADES: { [Types.BuildingId]: { [number]: UpgradeDef } } = {
	Beehive    = {},
	HoneyPot   = {},
	HoneyPress = {},
}

for id, table_ in BUILDING_UPGRADES do
	local behavior = BEHAVIORS[id]

	for level, cost in EconomyConfig.HONEY_UPGRADE_COSTS do
		table_[level] = {
			costGummies     = cost.gummies,
			costGoldGummies = cost.goldGummies,
			effect          = behavior.describe(level),
		}
	end
end

--------------------------------------------------------------------------------
-- Oeffentliche API
--------------------------------------------------------------------------------

local BuildingBehavior = {}

BuildingBehavior.BUILDING_UPGRADES = BUILDING_UPGRADES

function BuildingBehavior.get(buildingId: Types.BuildingId): Behavior
	return BEHAVIORS[buildingId] or DEFAULT_BEHAVIOR
end

-- Ist das ein Gebaeude, das es wirklich gibt? Fuer Strings, die vom Client
-- kommen — die duerfen nie ungeprueft als Types.BuildingId weiterlaufen.
function BuildingBehavior.isValidId(value: string): boolean
	return BEHAVIORS[value :: Types.BuildingId] ~= nil
end

function BuildingBehavior.getIntervalSeconds(buildingId: Types.BuildingId, level: number): number
	return BuildingBehavior.get(buildingId).getIntervalSeconds(level)
end

function BuildingBehavior.getCapacity(buildingId: Types.BuildingId, level: number): number
	return BuildingBehavior.get(buildingId).getCapacity(level)
end

-- Groesstes Lager, das dieses Gebaeude je haben kann. MapService baut danach
-- seine Honig-Tropfen, weil die nur EINMAL beim Aufbau entstehen und danach
-- nur noch ein- und ausgeblendet werden.
function BuildingBehavior.getMaxCapacity(buildingId: Types.BuildingId): number
	return BuildingBehavior.getCapacity(buildingId, EconomyConfig.MAX_BUILDING_LEVEL)
end

function BuildingBehavior.getHealPercent(buildingId: Types.BuildingId, level: number): number
	return BuildingBehavior.get(buildingId).getHealPercent(level)
end

function BuildingBehavior.getXpMultiplier(buildingId: Types.BuildingId, level: number): number
	return BuildingBehavior.get(buildingId).getXpMultiplier(level)
end

function BuildingBehavior.describeEffect(buildingId: Types.BuildingId, level: number): string
	return BuildingBehavior.get(buildingId).describe(level)
end

function BuildingBehavior.getUpgrade(buildingId: Types.BuildingId, targetLevel: number): UpgradeDef?
	local upgrades = BUILDING_UPGRADES[buildingId]
	if not upgrades then return nil end
	return upgrades[targetLevel]
end

-- XP, die EIN Honig gibt — egal aus welchem Gebaeude er kommt.
--
-- Die Multiplikatoren ALLER Gebaeude werden aufmultipliziert. Heute traegt nur
-- die Honig-Presse etwas bei (alle anderen geben 1), aber genau deshalb muss
-- kein Aufrufer wissen, WELCHES Gebaeude das ist: kaeme spaeter ein zweites
-- mit XP-Anteil dazu, aendert sich hier nichts.
function BuildingBehavior.getXpPerHoney(buildings: { [Types.BuildingId]: Types.Building }): number
	local multiplier = 1

	for id, building in buildings do
		multiplier *= BuildingBehavior.getXpMultiplier(id, building.level)
	end

	-- RUNDEN, nicht abschneiden. Der Multiplikator ist ein Quotient aus der
	-- XP-Kurve (z.B. 65/30), und Basis mal Quotient landet in Fliesskomma
	-- knapp NEBEN der ganzen Zahl: 30 * (65/30) ist 64.99999999999999, und
	-- math.floor haette daraus 64 XP gemacht statt der 65, die genau hier
	-- herauskommen muessen, damit die Kurve unveraendert bleibt.
	return math.max(1, math.floor(EconomyConfig.getHoneyXp(1) * multiplier + 0.5))
end

-- Gesamtes Lager einer Insel ueber alle Gebaeude — fuer die Teich-Anzeige.
function BuildingBehavior.getTotalCapacity(buildings: { [Types.BuildingId]: Types.Building }): number
	local total = 0

	for id, building in buildings do
		total += BuildingBehavior.getCapacity(id, building.level)
	end

	return total
end

return BuildingBehavior
