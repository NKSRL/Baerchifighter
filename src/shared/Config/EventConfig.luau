--!strict
-- EventConfig.luau
-- ReplicatedStorage/Config/EventConfig.luau
--
-- Der Event-Zyklus (Stand 2026-10-02, siehe Projekt-Doc
-- EVENT_UND_RARITY_IDEEN_2026-10-02): FUENF Events im festen Wechsel.
--
--   UFO             Flaggschiff, 4 Min. Als EINZIGES Event gibt es Stat-Stufen
--                   (+1 auf ALLE fuenf Stats) und eine Rarity-Up-Chance.
--   Hot Egg         Heisses Ei wird per Beruehrung weitergegeben -> Gutes Ei
--   Mutations-Sturm Blitze mutieren Baerchis, Chance sinkt mit Rarity -> Mutation
--   Koenigshuegel   Wer am laengsten oben steht -> Gutes Ei
--   Schatzgraeber   Baerchis graben, Bomben schicken sie heim -> Gutes Ei
--
-- EventService faehrt nur die Uhr, EventParticipationService teilt aus und
-- startet die Event-Handler (Services/EventHandlers/*). WAS es gibt und alle
-- Zahlen stehen ausschliesslich hier.
--
-- Der alte 10-Events-Katalog steht im Projekt-Doc EVENT_KATALOG_2026-09-16.

local Types           = require(script.Parent.Parent.Network.Types)
local EggConfig       = require(script.Parent.EggConfig)
local PromotionConfig = require(script.Parent.PromotionConfig)

--------------------------------------------------------------------------------
-- Typen
--------------------------------------------------------------------------------

--   kind = "honey"        amount  = Honig je Gebaeude (aufs Lager gedeckelt)
--   kind = "eggs"         amount  = Anzahl, eggType = welche Sorte
--   kind = "gummies"      amount  = Basisbetrag, wird mit rebirthMult vergeben
--   kind = "goldGummies"  amount  = Betrag (kein Multiplikator)
--   kind = "mutation"     chance  = Basis-Wahrscheinlichkeit auf EINEN Mutations-Wurf
--                         (wird mit MUTATION_RARITY_FACTOR[rarity] multipliziert)
--
-- v14 (Ei-Baum, WP10): bei kind = "eggs" darf statt einer festen Sorte
--   eggPick = "highest"   das hoechste freie Ei des Spielers (ohne Ascension)
--   eggPick = "jump"      ein SPRUNG-EI: eine Stufe ueber dem hoechsten freien
--                         Ei eines Pfads. Laesst sich oeffnen, schaltet den
--                         Knoten aber nicht frei. Gibt es keins (alles frei),
--                         wird es zu "highest".
-- stehen, und blueprintChance gibt eine Chance auf eine Blaupause dazu.
export type EventBonus = {
	kind    : "honey" | "eggs" | "gummies" | "goldGummies" | "mutation",
	amount  : number?,
	eggType : Types.EggType?,
	eggPick : ("highest" | "jump")?,
	blueprintChance : number?,
	chance  : number?,
}

-- v14: NOTFALL-EI. Bei jeder Ei-Belohnung eines Events gibt es mit dieser
-- Chance ZUSAETZLICH ein Basis-Ei. Das Konzept sah "statt" vor — zusaetzlich
-- erfuellt denselben Zweck (Notanker fuer das Basis-Ei), ohne dass ein
-- Spieler sein gutes Ei verliert. ANNAHME, eine Zeile hier.
local EMERGENCY_BASIC_EGG_CHANCE = 0.05

export type EventDef = {
	id          : string,
	displayName : string,

	floorColor  : Color3,
	fenceColor  : Color3,
	ringColor   : Color3,
	bannerColor : Color3,

	-- "bounce" | "lean" | "spin": rein kosmetisch (Idle-Bewegung am Event).
	action      : "bounce" | "lean" | "spin",
	actionText  : string,

	-- Dauer DIESES Events in Sekunden (individuell je Event).
	durationSeconds : number,

	-- Welcher Handler (Services/EventHandlers/<handler>) das Event steuert.
	handler     : string,

	-- true NUR beim UFO: Stat-Stufen + Rarity-Up. Alle anderen Events geben
	-- keine Stat-Stufe.
	statGain    : boolean,

	-- Legacy-Feld (frueher Stat-Fokus je Event). Bleibt nil.
	statFocus   : string?,

	-- Zusatz-Ertrag ("gutes Ei" bzw. Mutations-Wurf), oder nil.
	bonus       : EventBonus?,

	-- Ein Satz fuer Tafel/UI. Hat Vorrang vor der automatisch gebauten Zeile.
	rewardText  : string?,
}

--------------------------------------------------------------------------------
-- Zeiten
--------------------------------------------------------------------------------

-- Standard-Dauer, falls ein Event keine eigene hat (und fuer Debug-Ausgaben).
local EVENT_DURATION_SECONDS = 180
local EVENT_GAP_SECONDS      = 300

--------------------------------------------------------------------------------
-- UFO-Event
--------------------------------------------------------------------------------

local UFO = {
	-- So viele Sekunden Beam-Fortschritt braucht ein Baerchi zur Entfuehrung.
	-- Der Fortschritt muss nicht am Stueck laufen (Kaempfe pausieren ihn nur).
	BEAM_REQUIRED_SECONDS = 30,

	-- War so lange KEIN Baerchi im Beam (oder kommt einer zu spaet), schliesst
	-- das UFO den Beam und setzt ihn zurueck: alle Countdowns beginnen neu.
	BEAM_IDLE_TIMEOUT_SECONDS = 75,

	-- Fixe Kampfdauer, wenn sich ein Baerchi im Beam und ein anderer beruehren.
	-- Waehrenddessen pausiert der Beam-Fortschritt.
	FIGHT_SECONDS = 3,

	-- Nach der Entfuehrung: Wartezeit, bevor das Baerchi wieder aufs Plot gesetzt wird.
	ABDUCT_WAIT_SECONDS = 10,

	-- Beim Absetzen: +1 auf jeden dieser Stats (begrenzt durch STAT_CAP).
	STAT_GAIN_PER_STAT = 1,

	-- Radius des Beam-Rings (Anteil des Podest-Radius) und Beruehrungsabstand.
	BEAM_RADIUS_FACTOR = 0.22,
	TOUCH_DISTANCE     = 5,

	-- Laufgeschwindigkeit der Baerchis im Event (Faktor auf WALK_SPEED).
	WALK_SPEED_FACTOR = 1.0,
}

-- Rarity-Up-Chance beim Absetzen des entfuehrten Baerchis. Aufstieg immer nur
-- EINE Stufe. Chance je AKTUELLER Rarity. Common->Uncommon 55 % und
-- Secret->Godly 0,5 % vom Projektinhaber, Rest Interpolation.
local RARITY_UP_CHANCE: { [string]: number } = {
	Common    = 0.55,
	Uncommon  = 0.40,
	Rare      = 0.28,
	Epic      = 0.18,
	Legendary = 0.11,
	Mythic    = 0.065,
	Divine    = 0.035,
	Cosmic    = 0.015,
	Secret    = 0.005,
	Godly     = 0.0025,
	Eternal   = 0.001,
	Omega     = 0,
}

--------------------------------------------------------------------------------
-- Mutations-Sturm
--------------------------------------------------------------------------------

-- Faktor auf die Mutationschance: je hoeher die Rarity, desto geringer.
local MUTATION_RARITY_FACTOR: { [string]: number } = {
	Common    = 1.00,
	Uncommon  = 0.80,
	Rare      = 0.60,
	Epic      = 0.40,
	Legendary = 0.25,
	Mythic    = 0.15,
	Divine    = 0.10,
	Cosmic    = 0.06,
	Secret    = 0.03,
	Godly     = 0.015,
	Eternal   = 0.008,
	Omega     = 0.004,
}

local STORM = {
	-- Alle so viele Sekunden schlaegt ein Blitz in einen Teilnehmer ein (nur
	-- Optik); der Mutations-Wurf selbst faellt am Event-Ende.
	STRIKE_INTERVAL_SECONDS = 20,
}

--------------------------------------------------------------------------------
-- Hot Egg
--------------------------------------------------------------------------------

local HOT_EGG = {
	CHECK_INTERVAL_SECONDS = 0.5,
	-- Nach einer Weitergabe darf das Ei kurz nicht zurueck.
	PASS_COOLDOWN_SECONDS  = 2.0,
	TOUCH_DISTANCE         = 5,
}

--------------------------------------------------------------------------------
-- Koenigshuegel
--------------------------------------------------------------------------------

local KING = {
	-- Radius des Huegels (Anteil des Podest-Radius).
	HILL_RADIUS_FACTOR = 0.30,
	TICK_SECONDS       = 1,
}

--------------------------------------------------------------------------------
-- Schatzgraeber
--------------------------------------------------------------------------------

local TREASURE = {
	-- Basis-Sekunden pro Fundstelle; hoeheres Level = schneller.
	BASE_DIG_SECONDS      = 14,
	DIG_SECONDS_PER_LEVEL = 0.15,
	MIN_DIG_SECONDS       = 6,
	-- Fundstellen je Spieler (hoeheres Level -> mehr).
	BASE_SITES            = 5,
	LEVEL_PER_EXTRA_SITE  = 10,
	MAX_SITES             = 9,
	-- Anteil der Fundstellen, in denen eine Bombe liegt.
	BOMB_SHARE            = 0.15,
	-- Belohnung nach Funden (ueberlebt man bis Ende): hoechste passende Stufe.
	-- Bei Bombe geht ALLES verloren.
	-- v14: hoechstes freies Ei statt fest Golden/Kristall; ab 5 Funden ein
	-- Sprung-Ei mit 10% Chance auf eine Blaupause.
	REWARDS = {
		{ minFinds = 1, eggPick = "highest", amount = 1 },
		{ minFinds = 3, eggPick = "highest", amount = 2 },
		{ minFinds = 5, eggPick = "jump",    amount = 1, blueprintChance = 0.10 },
	},
}

--------------------------------------------------------------------------------
-- Der Katalog
--------------------------------------------------------------------------------

local EVENTS: { EventDef } = {

	-- ---------------------------------------------------------------- 1
	{
		id              = "Ufo",
		displayName     = "UFO",
		floorColor      = Color3.fromRGB( 18,  34,  64),
		fenceColor      = Color3.fromRGB( 90, 255, 160),
		ringColor       = Color3.fromRGB(120, 255, 190),
		bannerColor     = Color3.fromRGB(150, 255, 200),
		action          = "spin",
		actionText      = "wartet im Strahl des UFOs",
		durationSeconds = 240,
		handler         = "Ufo",
		statGain        = true,
		statFocus       = nil,
		bonus           = nil,
		rewardText      = "+1 auf alle Stats  •  Chance auf Rarity-Up",
	},

	-- ---------------------------------------------------------------- 2
	{
		id              = "HotEgg",
		displayName     = "Hot Egg",
		floorColor      = Color3.fromRGB(120,  30,  22),
		fenceColor      = Color3.fromRGB(255, 100,  40),
		ringColor       = Color3.fromRGB(255,  80,  40),
		bannerColor     = Color3.fromRGB(255, 140,  90),
		action          = "bounce",
		actionText      = "jongliert das heisse Ei",
		durationSeconds = 180,
		handler         = "HotEgg",
		statGain        = false,
		statFocus       = nil,
		bonus           = { kind = "eggs", eggPick = "highest", amount = 1 },
		rewardText      = "Wer das Ei am Ende haelt: 1x dein hoechstes Ei",
	},

	-- ---------------------------------------------------------------- 3
	{
		id              = "MutationsSturm",
		displayName     = "Mutations-Sturm",
		floorColor      = Color3.fromRGB( 90,  20,  90),
		fenceColor      = Color3.fromRGB(255,  60, 220),
		ringColor       = Color3.fromRGB(255, 100, 235),
		bannerColor     = Color3.fromRGB(255, 140, 240),
		action          = "spin",
		actionText      = "steht mitten im schimmernden Sturm",
		durationSeconds = 180,
		handler         = "MutationsSturm",
		statGain        = false,
		statFocus       = nil,
		bonus           = { kind = "mutation", chance = 0.20 },
		rewardText      = nil,
	},

	-- ---------------------------------------------------------------- 4
	{
		id              = "Koenigshuegel",
		displayName     = "Koenigshuegel",
		floorColor      = Color3.fromRGB( 60,  70,  30),
		fenceColor      = Color3.fromRGB(255, 215,  70),
		ringColor       = Color3.fromRGB(255, 225, 110),
		bannerColor     = Color3.fromRGB(255, 232, 140),
		action          = "bounce",
		actionText      = "kaempft um den Huegel",
		durationSeconds = 180,
		handler         = "Koenigshuegel",
		statGain        = false,
		statFocus       = nil,
		bonus           = { kind = "eggs", eggPick = "jump", amount = 1, blueprintChance = 0.10 },
		rewardText      = "Wer am laengsten oben steht: 1 Sprung-Ei  •  Chance auf Blaupause",
	},

	-- ---------------------------------------------------------------- 5
	{
		id              = "Schatzgraeber",
		displayName     = "Schatzgraeber",
		floorColor      = Color3.fromRGB(110,  78,  40),
		fenceColor      = Color3.fromRGB(230, 180, 100),
		ringColor       = Color3.fromRGB(240, 200, 120),
		bannerColor     = Color3.fromRGB(245, 215, 150),
		action          = "lean",
		actionText      = "graebt nach Schaetzen",
		durationSeconds = 180,
		handler         = "Schatzgraeber",
		statGain        = false,
		statFocus       = nil,
		bonus           = nil,
		rewardText      = "Eier je nach Funden  •  Vorsicht, Bomben!",
	},
}

--------------------------------------------------------------------------------
-- Hilfsfunktionen
--------------------------------------------------------------------------------

local function getById(id: string): EventDef?
	for _, def in EVENTS do
		if def.id == id then
			return def
		end
	end
	return nil
end

local function getDuration(def: EventDef): number
	return def.durationSeconds or EVENT_DURATION_SECONDS
end

local function getRarityUpChance(rarity: string): number
	return RARITY_UP_CHANCE[rarity] or 0
end

local function getMutationFactor(rarity: string): number
	return MUTATION_RARITY_FACTOR[rarity] or 1
end

local function describeBonus(bonus: EventBonus?): string?
	if not bonus then
		return nil
	end

	local amount = bonus.amount or 0

	if bonus.kind == "honey" then
		return string.format("%d Honig je Gebaeude", amount)

	elseif bonus.kind == "eggs" then
		if bonus.eggPick == "jump" then
			return string.format("%dx Sprung-Ei", amount)
		elseif bonus.eggPick == "highest" then
			return string.format("%dx dein hoechstes Ei", amount)
		end
		local eggType = bonus.eggType or "BasicEgg"
		local eggDef  = EggConfig.data[eggType]
		return string.format("%dx %s", amount, if eggDef then eggDef.displayName else eggType)

	elseif bonus.kind == "gummies" then
		return string.format("%d Gummies", amount)

	elseif bonus.kind == "goldGummies" then
		return string.format("%d GoldGummies", amount)

	elseif bonus.kind == "mutation" then
		return string.format(
			"bis zu %d%% Chance auf eine Mutation (sinkt mit Rarity)",
			math.floor((bonus.chance or 0) * 100 + 0.5)
		)
	end

	return nil
end

-- Die vollstaendige Belohnung in einer Zeile, fuer Tafel und UI.
local function describeReward(def: EventDef): string
	if def.rewardText then
		return def.rewardText
	end

	local bonusPart = describeBonus(def.bonus)
	if bonusPart then
		return bonusPart
	end

	return "Belohnung unbekannt"
end

return {
	EMERGENCY_BASIC_EGG_CHANCE = EMERGENCY_BASIC_EGG_CHANCE,
	EVENT_DURATION_SECONDS = EVENT_DURATION_SECONDS,
	EVENT_GAP_SECONDS      = EVENT_GAP_SECONDS,
	EVENTS                 = EVENTS,

	UFO                    = UFO,
	RARITY_UP_CHANCE       = RARITY_UP_CHANCE,
	MUTATION_RARITY_FACTOR = MUTATION_RARITY_FACTOR,
	STORM                  = STORM,
	HOT_EGG                = HOT_EGG,
	KING                   = KING,
	TREASURE               = TREASURE,

	getById           = getById,
	getDuration       = getDuration,
	getRarityUpChance = getRarityUpChance,
	getMutationFactor = getMutationFactor,
	describeBonus     = describeBonus,
	describeReward    = describeReward,
}
