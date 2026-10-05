--!strict
-- BuildingBehavior.luau
-- ReplicatedStorage/Config/BuildingBehavior.luau
--
-- Einzige Zustaendigkeit:
--   - Alles, was pro Types.BuildingId unterschiedlich ist: was ein Gebaeude
--     kann, was sein Ausbau kostet, wie sein Effekt heisst, welche Look-Stufe
--     es hat und welche Meilenstein-Faehigkeiten es freischaltet.
--
-- ============================================================
-- ZWEI HONIG-GEBAEUDE (v15, Option B)
-- ============================================================
-- Bis v14 gab es drei: Bienenstock (Vorrat), Honigtopf (Heilung), Honig-Presse
-- (XP). Die Entscheidung "Heil-Honig oder XP-Honig?" war schwach, und jedes
-- Gebaeude braucht in Prompt 4 sechs Looks. Seit v15:
--
--   Beehive       VORRAT    Lager waechst, und es produziert schneller.
--
--   HoneyRefiner  VEREDELN  Sein Level hebt die XP JEDES Honigs (die alte
--                           Kurve der Presse) und die Heilung SEINES Honigs
--                           (die alte Achse des Topfs, 25 % -> 60 % auf Level 10,
--                           -> 100 % auf Level 60). Name "Honig-Veredler" ist
--                           ein Platzhalter (steht nur in Strings/MapConfig).
--
-- Damit niemand Honig verliert, produziert der Veredler im Tempo von Topf und
-- Presse zusammen (halbes Intervall, doppeltes Lager). Die Gesamtmenge Honig
-- pro Minute ist dieselbe wie bis v14.
--
-- Das dritte Gebaeude, der Waben-Recycler, hat seine Zahlen in CombConfig; nur
-- seine Meilenstein-Faehigkeiten stehen hier (MILESTONES.Recycler), damit alle
-- Faehigkeiten an einer Stelle sind.
--
-- ============================================================
-- WARUM ALLES HIER STEHT
-- ============================================================
-- Kein Service und kein Panel verzweigt nach einer BuildingId. Ein Gebaeude
-- aendern heisst: EINEN Eintrag in BEHAVIORS anfassen. Die Abhaengigkeit geht
-- nur in EINE Richtung: BuildingBehavior kennt EconomyConfig (Basiswerte,
-- Kostenkurve, XP-Kurve, Look-Stufen), EconomyConfig kennt BuildingBehavior
-- nicht.

local EconomyConfig = require(script.Parent.EconomyConfig)
local Types         = require(script.Parent.Parent.Network.Types)

--------------------------------------------------------------------------------
-- Abweichungen der einzelnen Gebaeude
--------------------------------------------------------------------------------

-- Bienenstock — Vorrat. Bis Level 10 wie bisher (Lager 5 -> 14, je Ausbau ein
-- Platz; Intervall 20 s -> 8 s). Danach langsamer weiter: +1 Lager je
-- BEEHIVE_CAPACITY_STEP Level und Intervall bis BEEHIVE_MIN_INTERVAL_L60.
local BEEHIVE_CAPACITY_L10        = 14
local BEEHIVE_CAPACITY_STEP       = 2      -- ab Level 11: alle 2 Level +1 Platz (L60 = 39)
local BEEHIVE_INTERVAL_L10        = 8
local BEEHIVE_MIN_INTERVAL_L60    = 4

-- Honig-Veredler — Tempo/Lager wie Topf + Presse zusammen.
local REFINER_INTERVAL_FACTOR = 0.5    -- halbes Basis-Intervall (= zwei Gebaeude)
local REFINER_CAPACITY        = 10     -- doppeltes Basis-Lager
-- Heilung SEINES Honigs: Basis (Level 1) -> 60 % (Level 10) -> 100 % (Level 60)
local REFINER_HEAL_L10 = 0.60
local REFINER_HEAL_L60 = 1.00

--------------------------------------------------------------------------------
-- Meilenstein-Faehigkeiten (README 4.3) — Daten + Effekt-Hook
--------------------------------------------------------------------------------
-- Pro Gebaeude: ab welchem Level welche Faehigkeit gilt. `implemented = false`
-- heisst: nur als Daten da, der Effekt kommt spaeter (Liste im Bericht). Ein
-- Service fragt mit BuildingBehavior.hasAbility(...) — er muss nie selbst
-- wissen, auf welchem Level etwas freigeschaltet wird.
export type Ability = {
	id          : string,
	level       : number,
	implemented : boolean,
}

local MILESTONES: { [string]: { Ability } } = {
	Beehive = {
		-- Volles Lager wird automatisch an den ausgeruesteten Baerchi verfuettert
		-- (XP + Heilung), die Produktion steht also nie still (HoneyService).
		{ id = "AutoHarvest",   level = 10, implemented = true },
		{ id = "GoldenDrops",   level = 30, implemented = false },
	},
	HoneyRefiner = {
		{ id = "RefinerBoost",  level = 10, implemented = false },
		{ id = "RoyalJelly",    level = 30, implemented = false },
		{ id = "NectarOfAges",  level = 60, implemented = false },
	},
	Recycler = {
		-- Groesserer Aufheb-Radius fuer Waben im Event-Pit (CombService).
		{ id = "CollectRadius", level = 20, implemented = true },
		{ id = "AutoDeposit",   level = 45, implemented = false },
	},
}

--------------------------------------------------------------------------------
-- Kleine Rechen-Hilfen
--------------------------------------------------------------------------------

local MAX = EconomyConfig.MAX_BUILDING_LEVEL

-- Linear von `fromValue` (Level fromLevel) nach `toValue` (Level toLevel).
local function lerpLevel(fromLevel: number, fromValue: number, toLevel: number, toValue: number, level: number): number
	local span = math.max(1, toLevel - fromLevel)
	local t = math.clamp((level - fromLevel) / span, 0, 1)
	return fromValue + (toValue - fromValue) * t
end

local function clampLevel(level: number): number
	return EconomyConfig.clampBuildingLevel(level)
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

	-- Der Effekt dieses Gebaeudes auf diesem Level, in eigenen Worten
	-- (deutsch; das UI zeigt die lokalisierten Werte selbst an).
	describe : (level: number) -> string,
}

local BASE_INTERVAL = EconomyConfig.HONEY_INTERVAL_SECONDS
local BASE_CAPACITY = EconomyConfig.HONEY_CAPACITY
local BASE_HEAL     = EconomyConfig.HONEY_HEAL_PERCENT

local function baseInterval(_level: number): number  return BASE_INTERVAL end
local function baseCapacity(_level: number): number  return BASE_CAPACITY end
local function baseHeal(_level: number): number      return BASE_HEAL end
local function noXpBonus(_level: number): number     return 1 end

--------------------------------------------------------------------------------
-- Beehive — Vorrat
--------------------------------------------------------------------------------

local function beehiveInterval(level: number): number
	local l = clampLevel(level)
	if l <= 10 then
		return lerpLevel(1, BASE_INTERVAL, 10, BEEHIVE_INTERVAL_L10, l)
	end
	return lerpLevel(10, BEEHIVE_INTERVAL_L10, MAX, BEEHIVE_MIN_INTERVAL_L60, l)
end

local function beehiveCapacity(level: number): number
	local l = clampLevel(level)
	if l <= 10 then
		return roundToInt(lerpLevel(1, BASE_CAPACITY, 10, BEEHIVE_CAPACITY_L10, l))
	end
	return BEEHIVE_CAPACITY_L10 + math.floor((l - 10) / BEEHIVE_CAPACITY_STEP)
end

local function beehiveDescribe(level: number): string
	return string.format(
		"Lager: %d Honig  —  alle %.1f s ein neuer",
		beehiveCapacity(level),
		beehiveInterval(level)
	)
end

--------------------------------------------------------------------------------
-- HoneyRefiner — Veredeln (XP fuer jeden Honig + Heilung seines Honigs)
--------------------------------------------------------------------------------

local function refinerInterval(_level: number): number
	return BASE_INTERVAL * REFINER_INTERVAL_FACTOR
end

local function refinerCapacity(_level: number): number
	return REFINER_CAPACITY
end

local function refinerHeal(level: number): number
	local l = clampLevel(level)
	if l <= 10 then
		return lerpLevel(1, BASE_HEAL, 10, REFINER_HEAL_L10, l)
	end
	return lerpLevel(10, REFINER_HEAL_L10, MAX, REFINER_HEAL_L60, l)
end

-- Der Multiplikator ist die XP-Kurve, bezogen auf ihren eigenen Startwert:
-- Level 1 = Faktor 1, Level 10 = 25x (wie die alte Presse), danach weiter.
local function refinerXpMultiplier(level: number): number
	local base = EconomyConfig.getHoneyXp(1)
	if base <= 0 then return 1 end
	return EconomyConfig.getHoneyXp(level) / base
end

local function refinerDescribe(level: number): string
	return string.format(
		"+%s XP auf jeden Honig  —  sein Honig heilt %s",
		percentText(refinerXpMultiplier(level) - 1),
		percentText(refinerHeal(level))
	)
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

	HoneyRefiner = {
		getIntervalSeconds = refinerInterval,
		getCapacity        = refinerCapacity,
		getHealPercent     = refinerHeal,
		getXpMultiplier    = refinerXpMultiplier,
		describe           = refinerDescribe,
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
-- Die KOSTEN sind fuer alle gleich (EconomyConfig.HONEY_UPGRADE_COSTS), der
-- Effekt-Text ist die describe() des Gebaeudes auf der gekauften Stufe —
-- Anzeige und Wirkung koennen nicht auseinanderlaufen.

export type UpgradeDef = {
	costGummies     : number,
	costGoldGummies : number,
	effect          : string,   -- was DIESE Stufe kann (erzeugt aus describe)
}

local BUILDING_UPGRADES: { [Types.BuildingId]: { [number]: UpgradeDef } } = {
	Beehive      = {},
	HoneyRefiner = {},
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
BuildingBehavior.MILESTONES        = MILESTONES

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

-- Groesstes Lager, das dieses Gebaeude je haben kann.
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

-- v15: Look-Stufe (1-6) eines Gebaeude-Levels. Gilt fuer Bienenstock,
-- Veredler UND Recycler (gleiche Stufen). PlotDisplayService baut ein Gebaeude
-- nur neu, wenn sich DIESE Zahl aendert, nicht bei jedem Level.
function BuildingBehavior.getLook(level: number): number
	return EconomyConfig.getLook(level)
end

-- v15: Hat dieses Gebaeude (oder "Recycler") auf diesem Level die Faehigkeit?
-- Nur umgesetzte Faehigkeiten zaehlen — eine reine Daten-Faehigkeit hat noch
-- keinen Effekt und darf deshalb auch keinen ausloesen.
function BuildingBehavior.hasAbility(buildingKey: string, level: number, abilityId: string): boolean
	for _, ability in MILESTONES[buildingKey] or {} do
		if ability.id == abilityId then
			return ability.implemented and level >= ability.level
		end
	end
	return false
end

-- Alle Faehigkeiten eines Gebaeudes mit Freischalt-Level (fuers Panel).
function BuildingBehavior.getAbilities(buildingKey: string): { Ability }
	return MILESTONES[buildingKey] or {}
end

-- XP, die EIN Honig gibt — egal aus welchem Gebaeude er kommt.
--
-- Die Multiplikatoren ALLER Gebaeude werden aufmultipliziert. Heute traegt nur
-- der Veredler etwas bei (der Bienenstock gibt 1).
function BuildingBehavior.getXpPerHoney(buildings: { [Types.BuildingId]: Types.Building }): number
	local multiplier = 1

	for id, building in buildings do
		multiplier *= BuildingBehavior.getXpMultiplier(id, building.level)
	end

	-- RUNDEN, nicht abschneiden: Basis mal Quotient landet in Fliesskomma knapp
	-- NEBEN der ganzen Zahl (30 * (65/30) = 64.999...).
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
