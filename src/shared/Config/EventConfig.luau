--!strict
-- EventConfig.luau
-- ReplicatedStorage/Config/EventConfig.luau
--
-- Der Event-Zyklus (Stand 2026-10-04, siehe Projekt-Docs
-- EVENT_UND_RARITY_IDEEN_2026-10-02 und README_EVENTS_GEBAEUDE_TOWER_PLAN):
-- SECHS Events im festen Wechsel, das Boss-Event nur in jedem zweiten
-- Durchlauf (everyNthCycle). Ein Durchlauf ohne Boss dauert ~41 min, mit ~46.
--
--   UFO             Flaggschiff, 4 Min. Patrouilliert ueber dem Pit, der Beam
--                   wandert mit; Entfuehrung = +1 auf ALLE Stats und
--                   Rarity-Up-Chance. Alle 30 s ein Ei-Abwurf (1 % Jackpot).
--   Hot Egg         Heisses Ei wird weitergegeben -> Gutes Ei. Waben werden
--                   zu Lava (x3), alle ~30 s ein Vulkan-Ausbruch.
--   Mutations-Sturm Blitze mutieren Baerchis, Chance sinkt mit Rarity -> Mutation
--   Koenigshuegel   Wer am laengsten oben steht -> Gutes Ei
--   Schatzgraeber   Baerchis graben, Bomben schicken sie heim -> Gutes Ei
--   Wespenkoenigin  Boss-Kampf fuer alle (jeder zweite Durchlauf): Baerchis
--                   kaempfen, Spieler weichen Telegraphen aus. Belohnung nach
--                   Schadensanteil.
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

	-- Laeuft nur in jedem n-ten Durchlauf des Zyklus (nil = jeder). Der Zyklus
	-- zaehlt ab 1; mit 2 kommt das Event im 2., 4., 6. ... Durchlauf.
	everyNthCycle : number?,
}

--------------------------------------------------------------------------------
-- Zeiten
--------------------------------------------------------------------------------

-- Standard-Dauer, falls ein Event keine eigene hat (und fuer Debug-Ausgaben).
local EVENT_DURATION_SECONDS = 180
local EVENT_GAP_SECONDS      = 300
-- HBB Paket 6: Pause vor dem ERSTEN Event eines frisch gestarteten Servers.
-- Kuerzer, damit die ersten Spieler eines neuen Servers nicht fuenf Minuten
-- auf das erste Event warten. Alle spaeteren Pausen und die Boss-Haeufigkeit
-- (everyNthCycle) bleiben unveraendert. Gilt nur mit FeatureFlags.EVENT_V2_TIMER.
local FIRST_GAP_SECONDS      = 75

--------------------------------------------------------------------------------
-- UFO-Event
--------------------------------------------------------------------------------

local UFO = {
	-- So viele Sekunden Beam-Fortschritt braucht ein Baerchi zur Entfuehrung.
	-- Der Fortschritt muss nicht am Stueck laufen (Kaempfe pausieren ihn nur).
	-- 20 statt 30: der Ring wandert, der Baerchi verliert beim Nachlaufen Zeit.
	BEAM_REQUIRED_SECONDS = 20,

	-- PATROUILLE: Lissajous-Bahn ueber dem Pit (Studs, Sekunden), reine
	-- Funktion der Serverzeit (Modules/EventMotion). Halbachsen so, dass der
	-- Beam-Ring immer im Pit bleibt (Pit-Radius 50, Ring 11); schnellster
	-- Punkt ~2,5 Studs/s, ein Baerchi laeuft am Event 26.
	PATROL_RADIUS_X = 24,
	PATROL_RADIUS_Z = 18,
	PATROL_PERIOD_X = 90,
	PATROL_PERIOD_Z = 60,
	-- Ein Baerchi im Beam laeuft nach, sobald er weiter als dieser Anteil des
	-- Ring-Radius von der Ring-Mitte steht; Ziel ist die Ring-Mitte so viele
	-- Sekunden voraus.
	FOLLOW_SHARE      = 0.55,
	FOLLOW_LEAD_SECONDS = 1.5,

	-- EI-ABWURF: alle DROP_INTERVAL_SECONDS (erster nach DROP_FIRST_SECONDS,
	-- 8 pro Event). DROP_TELEGRAPH_SECONDS vorher erscheint der Landekreis an
	-- der vorhergesagten UFO-Position. Aufheben: Spieler-CHARAKTER innerhalb
	-- DROP_PICKUP_RADIUS, erster gewinnt (Server prueft im Takt).
	DROP_FIRST_SECONDS      = 15,
	DROP_INTERVAL_SECONDS   = 30,
	DROP_TELEGRAPH_SECONDS  = 3,
	DROP_PICKUP_RADIUS      = 5,
	DROP_PICKUP_MAX_HEIGHT  = 8,
	DROP_CHECK_SECONDS      = 0.1,
	DROP_EGG                = "BasicEgg" :: Types.EggType,

	-- JACKPOT: goldene Kiste mit dem UFO-Jackpot-Ei. Pity: spaetestens der
	-- JACKPOT_PITY_DROPS-te Abwurf (serverweit, Laufzeit-Zaehler, wird nach
	-- jedem Jackpot zurueckgesetzt).
	JACKPOT_CHANCE     = 0.01,
	JACKPOT_PITY_DROPS = 100,
	JACKPOT_EGG        = "UfoJackpotEgg" :: Types.EggType,

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

	-- Takt der Beam-Pruefung. Der Fortschritt waechst je Takt um genau diesen
	-- Wert, die Summe pro Sekunde bleibt also gleich; der Takt bestimmt nur,
	-- wie fein Beruehrungen und Beam-Grenze erkannt werden.
	TICK_SECONDS = 0.25,

	-- Der Verlierer eines Kampfs laeuft zurueck und darf so lange nicht
	-- wieder zum Beam.
	LOSER_COOLDOWN_SECONDS = 4,

	-- Dasselbe Paar kaempft fruehestens nach FIGHT_SECONDS + so vielen
	-- Sekunden erneut gegeneinander.
	PAIR_COOLDOWN_EXTRA_SECONDS = 6,

	-- Nach einem Beam-Reset bleibt der Beam so lange geschlossen.
	BEAM_REOPEN_SECONDS = 4,
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

-- Duelle (UFO, Koenigshuegel): die Kampfkraft beider Seiten wird mit einem
-- Zufallsfaktor 1 ± POWER_SPREAD multipliziert. 0.2 = auch der Schwaechere
-- gewinnt manchmal, wenn der Abstand klein ist.
local DUEL = {
	POWER_SPREAD = 0.2,
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

	-- Wabenthema waehrend des Events (CombConfig.THEMES).
	COMB_THEME = "HotEgg",

	-- VULKAN-AUSBRUCH: alle ERUPTION_INTERVAL_SECONDS ein Warnring in der
	-- Mitte, ERUPTION_WARN_SECONDS spaeter fliegen ERUPTION_MIN..MAX
	-- Lava-Waben in alle Richtungen (landen als normale Waben im Slot-Modell).
	ERUPTION_INTERVAL_SECONDS = 30,
	ERUPTION_WARN_SECONDS     = 2,
	ERUPTION_MIN              = 8,
	ERUPTION_MAX              = 10,
}

--------------------------------------------------------------------------------
-- Koenigshuegel
--------------------------------------------------------------------------------

local KING = {
	-- Radius des Huegels (Anteil des Podest-Radius).
	HILL_RADIUS_FACTOR = 0.30,
	TICK_SECONDS       = 1,

	-- Zwei Baerchis auf dem Huegel, die sich so nahe kommen, kaempfen.
	TOUCH_DISTANCE = 6,
	-- Fixe Dauer eines Huegel-Duells.
	DUEL_SECONDS = 3,
	-- Der Verlierer muss runter und darf so lange nicht wieder hoch.
	LOSER_COOLDOWN_SECONDS = 6,
	-- Ein Herausforderer bleibt so weit vor dem Koenig stehen (innerhalb von
	-- TOUCH_DISTANCE, damit das Duell ausgeloest wird).
	CHALLENGE_DISTANCE = 4,
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
	-- Fundstellen liegen in diesem Ring um die Event-Mitte (Anteil des
	-- Podest-Radius): nicht direkt in der Mitte und nicht am Zaun.
	SITE_MIN_RADIUS_FACTOR = 0.25,
	SITE_MAX_RADIUS_FACTOR = 0.80,
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
-- Wespenkoenigin (Boss-Event)
--------------------------------------------------------------------------------
-- Ablauf: ANNOUNCE_SECONDS Ankuendigung (Himmel dunkelt), dann Kampf bis zum
-- Sieg oder Event-Ende. Die Baerchis am Event kaempfen automatisch, ihr
-- Schaden kommt aus dem echten Kampfmodell (Modules/BossBalance ueber
-- CombatCalculator). Die Spieler weichen Telegraphen aus: ein Treffer stoesst
-- zurueck, bremst und setzt den Schaden des eigenen Baerchis kurz aus. Wer
-- mit seinem Charakter im Pit steht, feuert an (CHEER_FACTOR).

local WASP_QUEEN = {
	ANNOUNCE_SECONDS = 20,
	TICK_SECONDS     = 0.5,

	-- Ziel-Kampfdauer, aus der die HP berechnet werden:
	--   HP = Spieler x mittlere DPS x TARGET_FIGHT_SECONDS x HP_FACTOR
	-- (Spieler = Baerchis am Event beim Kampfbeginn). Wer spaeter dazukommt,
	-- erhoeht die HP um seine DPS x Restzeit bis zum Ziel (mind. LATE_JOIN_MIN_SECONDS).
	-- 135 statt 150: Treffer setzen Schaden aus, und Anfaenger weichen
	-- schlechter aus; mit 135 liegt der Kampf ueber alle Staerken bei
	-- ~125-170 s (tools/sim/boss_balance.lua).
	TARGET_FIGHT_SECONDS  = 135,
	HP_FACTOR             = 1.0,
	-- v15 (vorbereitet, AUS): Boss-HP-Faktor nach dem hoechsten Tower der
	-- Teilnehmer (Index 1-4 = I, II, III, Final). Standard ueberall 1 — erst
	-- nach dem Playtest einschalten (BossBalance.towerHpFactor).
	TOWER_HP_FACTOR       = { 1.0, 1.0, 1.0, 1.0 },
	MIN_HP                = 400,
	LATE_JOIN_MIN_SECONDS = 30,

	CHEER_FACTOR     = 1.25,
	HIT_STUN_SECONDS = 3,
	-- Treffer am Spieler: Rueckstoss (Studs/s) und Bremse (Anteil, Sekunden).
	KNOCKBACK_SPEED  = 70,
	SLOW_FACTOR      = 0.5,
	SLOW_SECONDS     = 2,

	-- Phase 2 ab diesem HP-Anteil: schnellere Attacken, Waben-Regen (Koenigsgelee).
	PHASE2_AT              = 0.5,
	PHASE1_ATTACK_INTERVAL = 6,
	PHASE2_ATTACK_INTERVAL = 4,
	TELEGRAPH_SECONDS      = 2,
	RAIN_THEME             = "WaspQueen",
	RAIN_INTERVAL_SECONDS  = 8,
	RAIN_COUNT             = 6,

	-- Attacken (Studs). Schockwelle: Ring um den Boden unter der Koenigin.
	-- Stachel-Salve: Kreise auf Spielerpositionen. Schwarm: Bahn quer durchs Pit.
	SHOCK_INNER        = 7,
	SHOCK_OUTER        = 17,
	STING_RADIUS       = 6,
	STING_COUNT        = 3,
	STING_COUNT_PHASE2 = 5,
	SWARM_WIDTH        = 9,

	-- Bewegung (Modules/EventMotion): Kreis ueber dem Pit.
	ORBIT_RADIUS        = 14,
	ORBIT_PERIOD        = 32,
	ORBIT_PERIOD_PHASE2 = 20,

	-- Belohnung nach Schadensanteil. Unter MIN_DAMAGE_SHARE gibt es nichts.
	-- Teilnahme: Gummies (mit Rebirth-Multiplikator) und Wabeneinheiten in den
	-- Recycler, je GUMMIES_BASE/COMB_UNITS_BASE mal Anteil x Teilnehmerzahl
	-- (ein Durchschnitts-Teilnehmer bekommt genau die Basis), begrenzt auf
	-- SHARE_FACTOR_MIN..MAX. Die besten TOP_RANKS bekommen ein Sprung-Ei und
	-- einen Rarity-Up-Wurf (RARITY_UP_FACTOR x EventConfig.RARITY_UP_CHANCE).
	-- Sieg: jeder bekommt sein hoechstes Ei, mit JACKPOT_CHANCE stattdessen das
	-- Jackpot-Ei. Niederlage: nur Teilnahme x DEFEAT_FACTOR.
	MIN_DAMAGE_SHARE  = 0.02,
	GUMMIES_BASE      = 300,
	COMB_UNITS_BASE   = 15,
	SHARE_FACTOR_MIN  = 0.5,
	SHARE_FACTOR_MAX  = 2.0,
	TOP_RANKS         = 3,
	RARITY_UP_FACTOR  = 0.5,
	JACKPOT_CHANCE    = 0.01,
	DEFEAT_FACTOR     = 0.5,
}

-- HBB Paket 7: Belohnungsstufen am Boss (Modules/BossTiers), ZUSAETZLICH zur
-- Belohnung nach Schadensanteil oben. Gilt nur mit FeatureFlags.BOSS_TIERS.
-- Schwellen relativ zum eigenen Potenzial (DPS x Zeit am Boss).
-- Belohnungen nur aus vorhandenen Bausteinen; Gummies sind Basisbetraege
-- (EconomyService wendet den Rebirth-Multiplikator an). Kumuliert: Stufe 3
-- hat zusammen zwei Basis-Eier, Stufe 4 dazu einen Mutations-Wurf.
local BOSS_TIERS = {
	T2 = 0.05,
	T3 = 0.25,
	T4 = 0.60,
	-- Aktivitaet: Charakter alle CHECK_SECONDS mehr als MOVE_STUDS bewegt
	-- (Player.Idled gibt es nur auf dem Client)
	ACTIVE_WINDOW_SECONDS = 60,
	ACTIVE_CHECK_SECONDS  = 2,
	ACTIVE_MOVE_STUDS     = 4,
	REWARDS = {
		[1] = { gummies = 40,  combUnits = 3, basicEggs = 0, mutationRoll = false },
		[2] = { gummies = 60,  combUnits = 4, basicEggs = 1, mutationRoll = false },
		[3] = { gummies = 80,  combUnits = 5, basicEggs = 2, mutationRoll = false },
		[4] = { gummies = 100, combUnits = 6, basicEggs = 2, mutationRoll = true },
	} :: { [number]: { gummies: number, combUnits: number, basicEggs: number, mutationRoll: boolean } },
	-- Wurf wie beim Mutations-Sturm (gleiche Chance, gleiche Rarity-Daempfung)
	MUTATION_CHANCE = 0.20,
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

	-- ---------------------------------------------------------------- 6
	{
		id              = "WaspQueen",
		displayName     = "Wespenkoenigin",
		floorColor      = Color3.fromRGB( 60,  44,  20),
		fenceColor      = Color3.fromRGB(255, 200,  40),
		ringColor       = Color3.fromRGB(255, 170,  30),
		bannerColor     = Color3.fromRGB(255, 210,  90),
		action          = "bounce",
		actionText      = "kaempft gegen die Wespenkoenigin",
		durationSeconds = 240,
		handler         = "WaspQueen",
		statGain        = false,
		statFocus       = nil,
		bonus           = { kind = "eggs", eggPick = "highest", amount = 1 },
		rewardText      = "Boss! Belohnung nach Schaden  •  Sieg: dein hoechstes Ei (1 % Jackpot)",
		everyNthCycle   = 2,
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

-- Laeuft dieses Event im Durchlauf `cycle` (ab 1 gezaehlt)?
local function isScheduledInCycle(def: EventDef, cycle: number): boolean
	local n = def.everyNthCycle
	if not n or n <= 1 then return true end
	return cycle % n == 0
end

local function getDuration(def: EventDef): number
	return def.durationSeconds or EVENT_DURATION_SECONDS
end

-- HBB Paket 6: Sekunden, bis Event `targetId` das naechste Mal STARTET
-- (0 = laeuft gerade). Rein, nach demselben Ablauf wie EventService:
-- Event -> Pause (EVENT_GAP_SECONDS) -> naechstes geplantes Event.
--   activeId  laufendes Event oder nil (Pause)
--   remaining Restsekunden der aktuellen Phase
--   nextIndex/nextCycle  Stand von EventService (_nextIndex, _nextCycle)
-- nil, wenn das Event im Zyklus nie vorkommt.
local function secondsUntilStart(targetId: string, activeId: string?, remaining: number,
	nextIndex: number, nextCycle: number): number?
	if activeId == targetId then return 0 end
	local t = math.max(0, remaining)
	if activeId then
		t += EVENT_GAP_SECONDS   -- erst endet das laufende Event, dann Pause
	end

	local index, cycle = nextIndex, nextCycle
	local count = #EVENTS
	for _ = 1, count * 8 do
		local def = EVENTS[index]
		if isScheduledInCycle(def, cycle) then
			if def.id == targetId then return t end
			t += getDuration(def) + EVENT_GAP_SECONDS
		end
		index += 1
		if index > count then
			index = 1
			cycle += 1
		end
	end
	return nil
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

--------------------------------------------------------------------------------
-- Sammel-Update 05.10. (Paket 5.2): KAMPF UM DIE MITTE
--------------------------------------------------------------------------------
-- Waehrend eines Events stossen die Event-Baerchis Spieler, die KEIN eigenes
-- Baerchi im Event haben und ihnen im Pit zu nahe kommen (Rueckstoss + kurze
-- Verlangsamung + kurze Waben-Pause). Die Baerchis kaempfen zuerst
-- untereinander (Handler); greifen tun sie nur, wenn sie gerade frei sind.
-- Annahmen (Abschnitt 11.10, Standard): kein Angriff auf Spieler mit eigenem
-- Baerchi im Pit, kein Festhalten (Abklingzeit je Spieler), nur im Pit-Radius.
local PIT_BRAWL = {
	TICK_SECONDS        = 0.5,
	REACH               = 9,      -- Studs: so nah muss der Spieler am Baerchi sein
	PLAYER_COOLDOWN     = 4,      -- Sekunden: so oft wird ein Spieler hoechstens gestossen
	BAERCHI_COOLDOWN    = 2.5,    -- Sekunden: so oft greift ein Baerchi hoechstens an
	KNOCKBACK_SPEED     = 55,
	SLOW_FACTOR         = 0.7,
	SLOW_SECONDS        = 1.5,
	PICKUP_PAUSE_SECONDS = 1.5,
	LUNGE_DISTANCE      = 2.5,
	LUNGE_SECONDS       = 0.3,
}

return {
	EMERGENCY_BASIC_EGG_CHANCE = EMERGENCY_BASIC_EGG_CHANCE,
	EVENT_DURATION_SECONDS = EVENT_DURATION_SECONDS,
	EVENT_GAP_SECONDS      = EVENT_GAP_SECONDS,
	FIRST_GAP_SECONDS      = FIRST_GAP_SECONDS,
	BOSS_TIERS             = BOSS_TIERS,
	EVENTS                 = EVENTS,

	UFO                    = UFO,
	DUEL                   = DUEL,
	RARITY_UP_CHANCE       = RARITY_UP_CHANCE,
	MUTATION_RARITY_FACTOR = MUTATION_RARITY_FACTOR,
	STORM                  = STORM,
	HOT_EGG                = HOT_EGG,
	KING                   = KING,
	TREASURE               = TREASURE,
	WASP_QUEEN             = WASP_QUEEN,

	getById           = getById,
	getDuration       = getDuration,
	isScheduledInCycle = isScheduledInCycle,
	secondsUntilStart  = secondsUntilStart,
	getRarityUpChance = getRarityUpChance,
	getMutationFactor = getMutationFactor,
	describeBonus     = describeBonus,
	describeReward    = describeReward,
	PIT_BRAWL         = PIT_BRAWL,   -- Sammel-Update 5.2
}
