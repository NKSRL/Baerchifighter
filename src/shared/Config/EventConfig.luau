--!strict
-- EventConfig.luau
-- ReplicatedStorage/Config/EventConfig.luau
--
-- Der Event-Zyklus: welche Events es gibt, WAS eine Teilnahme bringt, wie lange
-- ein Event laeuft und wie lange die Pause bis zum naechsten ist.
--
-- EventService faehrt nur die Uhr, EventParticipationService teilt nur aus —
-- entschieden und gerechnet wird ausschliesslich hier. Wer ein Event
-- hinzufuegen, streichen oder anders belohnen will, aendert genau diese Datei
-- und sonst keine.
--
-- ============================================================
-- WAS EIN EVENT IST
-- ============================================================
-- Das Event-Pit in der Weltmitte sieht normalerweise aus wie ein schlichter
-- Stall. Waehrend eines Events nimmt es dessen Farben an, und die Tafel
-- darueber zeigt Name, Restzeit und Belohnung (siehe EventService).
--
-- Wer seinen ausgeruesteten Baerchi ueber den "Zum Event"-Knopf hinschickt und
-- ihn dort stehen laesst, BIS das Event ablaeuft, bekommt zwei Dinge:
--
--   1. IMMER eine Stat-Stufe (siehe PromotionConfig.GROWABLE_STATS). Welchen
--      Stat, haengt vom Event ab: `statFocus` setzt ihn fest, nil wuerfelt wie
--      bisher unter allen noch nicht gedeckelten Stats.
--   2. Bei manchen Events zusaetzlich einen BONUS (`bonus`) — Honig, Eier,
--      Gummies, GoldGummies oder einen Wurf auf eine Mutation.
--
-- Wer niemanden hinschickt, merkt vom Event weiterhin nichts ausser der Farbe.
-- Das ist unveraendert Absicht: der Knopf ist die Entscheidung, und waehrend
-- der Teilnahme frisst der Baerchi keinen Honig (siehe
-- EventParticipationService, LOCK_HOLDER).
--
-- ============================================================
-- WARUM GEZIELTE STAT-EVENTS
-- ============================================================
-- Frueher gab JEDES Event eine ZUFAELLIGE Stat-Stufe. Damit war Teilnahme zwar
-- Fortschritt, aber keine Entscheidung: man konnte nie auf etwas hinarbeiten.
-- Fuenf der zehn Events haben deshalb jetzt einen festen Stat (`statFocus`) —
-- wer PWR fuer seinen Ability-Baerchi will, wartet gezielt auf den
-- Zauber-Zirkel. Steht der Ziel-Stat schon am Rarity-Cap, faellt die Vergabe
-- automatisch auf einen zufaelligen offenen Stat zurueck; eine Teilnahme laeuft
-- also nie ins Leere, solange ueberhaupt noch etwas wachsen kann.
--
-- ============================================================
-- ANNAHMEN, NICHT VOM PROJEKTINHABER VORGEGEBEN
-- ============================================================
--   * Zehn Events in fester Reihenfolge (kein Zufall — sonst kann ein Server
--     durch reines Pech dasselbe Event dreimal hintereinander zeigen, und die
--     Tafel koennte nicht ankuendigen, was als naechstes kommt).
--   * Stat-Events und Bonus-Events wechseln sich in der Reihenfolge ab, damit
--     nicht fuenf Trainings-Events am Stueck laufen.
--   * Je 3 Minuten Event, 5 Minuten Pause → ein voller Durchlauf durch alle
--     zehn Events dauert 80 Minuten. Wer auf ein bestimmtes Event wartet,
--     wartet also hoechstens so lange. Beide Zeiten stehen unten an einer
--     Stelle, falls sich das als zu lang herausstellt.
--   * Die Bonus-Betraege sind an vorhandenen Preisen geeicht: ein Goldenes Ei
--     kostet 10 GoldGummies (EggConfig), ein Charm-Wurf 25 (CharmConfig), ein
--     Zucker-Ei 250 Gummies. Ein Bonus entspricht damit ungefaehr einem
--     mittleren Kauf — spuerbar, aber keine Abkuerzung durchs halbe Spiel.

local Types           = require(script.Parent.Parent.Network.Types)
local EggConfig       = require(script.Parent.EggConfig)
local PromotionConfig = require(script.Parent.PromotionConfig)

--------------------------------------------------------------------------------
-- Typen
--------------------------------------------------------------------------------

-- Der Zusatz-Ertrag eines Events, ueber die Stat-Stufe hinaus.
--
-- Bewusst EINE Tabellenform mit optionalen Feldern statt einer echten
-- Variantentypen-Union: `kind` sagt, welches Feld gilt, und
-- EventParticipationService verzweigt genau einmal darauf. Eine Union waere
-- sauberer zu lesen, braeuchte unter --!strict aber an jeder Auswertung eine
-- Typ-Einengung — fuer fuenf Faelle mehr Umstand als Nutzen.
--
--   kind = "honey"        amount  = Honig je Gebaeude (aufs Lager gedeckelt)
--   kind = "eggs"         amount  = Anzahl, eggType = welche Sorte
--   kind = "gummies"      amount  = Basisbetrag, wird mit rebirthMult vergeben
--   kind = "goldGummies"  amount  = Betrag (kein Multiplikator, Premium-Waehrung)
--   kind = "mutation"     chance  = Wahrscheinlichkeit auf EINEN Mutations-Wurf
export type EventBonus = {
	kind    : "honey" | "eggs" | "gummies" | "goldGummies" | "mutation",
	amount  : number?,
	eggType : Types.EggType?,
	chance  : number?,
}

export type EventDef = {
	id          : string,
	displayName : string,

	-- Farben, die das Pit annimmt, waehrend dieses Event laeuft (siehe
	-- MapService.setEventPitTheme). Neon auf Zaun und Ring, damit der
	-- Unterschied zum stillen Stall-Look sofort auffaellt.
	floorColor  : Color3,
	fenceColor  : Color3,
	ringColor   : Color3,
	bannerColor : Color3,

	-- Was ein teilnehmender Baerchi waehrend dieses Events TUT.
	--
	-- Bewusst rein kosmetisch: der Spieler soll sehen, dass sein Baerchi aktiv
	-- mitmacht und nicht bloss herumsteht. Der Ertrag haengt NICHT daran — der
	-- steht in statFocus/bonus direkt darunter.
	--
	--   "bounce" — huepft auf der Stelle
	--   "lean"   — beugt sich rhythmisch vor (wie beim Fressen am Teich)
	--   "spin"   — dreht sich langsam
	action      : "bounce" | "lean" | "spin",

	-- Ein Satz fuer die Anzeige, was der Baerchi dort gerade macht.
	actionText  : string,

	-- Welcher Stat die garantierte Stufe bekommt (Schluessel aus
	-- PromotionConfig.GROWABLE_STATS). nil = zufaellig unter allen offenen.
	statFocus   : string?,

	-- Zusatz-Ertrag, oder nil fuer "nur die Stat-Stufe".
	bonus       : EventBonus?,
}

--------------------------------------------------------------------------------
-- Zeiten
--------------------------------------------------------------------------------

-- Wie lange ein Event laeuft, und wie lange danach Pause ist, bevor das
-- naechste beginnt. Siehe Kommentar-Kopf — Annahme, kein Vorgabewert.
local EVENT_DURATION_SECONDS = 180   -- 3 Minuten
local EVENT_GAP_SECONDS      = 300   -- 5 Minuten

--------------------------------------------------------------------------------
-- Der Katalog
--------------------------------------------------------------------------------

-- Die Reihenfolge hier IST die Reihenfolge im Spiel (EventService zaehlt
-- stumpf durch und faengt danach wieder von vorne an).
local EVENTS: { EventDef } = {

	-- ---------------------------------------------------------------- 1
	{
		id          = "HotEgg",
		displayName = "Hot Egg",
		floorColor  = Color3.fromRGB(120,  30,  22),
		fenceColor  = Color3.fromRGB(255, 100,  40),
		ringColor   = Color3.fromRGB(255,  80,  40),
		bannerColor = Color3.fromRGB(255, 140,  90),
		action      = "bounce",
		actionText  = "haelt das heisse Ei warm",
		statFocus   = nil,
		bonus       = { kind = "eggs", eggType = "GoldenEgg", amount = 1 },
	},

	-- ---------------------------------------------------------------- 2
	{
		id          = "Kraftprobe",
		displayName = "Kraftprobe",
		floorColor  = Color3.fromRGB(110,  20,  30),
		fenceColor  = Color3.fromRGB(255,  60,  80),
		ringColor   = Color3.fromRGB(255,  90, 110),
		bannerColor = Color3.fromRGB(255, 120, 140),
		action      = "bounce",
		actionText  = "stemmt Honigfaesser",
		statFocus   = "atk",
		bonus       = nil,
	},

	-- ---------------------------------------------------------------- 3
	{
		id          = "HoneyRush",
		displayName = "Honig-Rausch",
		floorColor  = Color3.fromRGB(150, 100,  20),
		fenceColor  = Color3.fromRGB(255, 200,  60),
		ringColor   = Color3.fromRGB(255, 214,  90),
		bannerColor = Color3.fromRGB(255, 214, 120),
		action      = "lean",
		actionText  = "schleckt Honig aus dem Trog",
		statFocus   = nil,
		bonus       = { kind = "honey", amount = 3 },
	},

	-- ---------------------------------------------------------------- 4
	{
		id          = "PanzerTraining",
		displayName = "Panzer-Training",
		floorColor  = Color3.fromRGB( 28,  90,  45),
		fenceColor  = Color3.fromRGB( 90, 230, 120),
		ringColor   = Color3.fromRGB(120, 240, 150),
		bannerColor = Color3.fromRGB(150, 245, 175),
		action      = "lean",
		actionText  = "laesst sich mit Gummis bewerfen",
		statFocus   = "hp",
		bonus       = nil,
	},

	-- ---------------------------------------------------------------- 5
	{
		id          = "GoldenSwarm",
		displayName = "Goldener Schwarm",
		floorColor  = Color3.fromRGB(140, 115,  40),
		fenceColor  = Color3.fromRGB(255, 225, 120),
		ringColor   = Color3.fromRGB(255, 240, 160),
		bannerColor = Color3.fromRGB(255, 235, 170),
		action      = "spin",
		actionText  = "faengt goldene Bienen",
		statFocus   = nil,
		bonus       = { kind = "goldGummies", amount = 10 },
	},

	-- ---------------------------------------------------------------- 6
	{
		id          = "FlinkePfoten",
		displayName = "Flinke Pfoten",
		floorColor  = Color3.fromRGB( 20,  90, 105),
		fenceColor  = Color3.fromRGB( 80, 225, 255),
		ringColor   = Color3.fromRGB(120, 235, 255),
		bannerColor = Color3.fromRGB(150, 240, 255),
		action      = "spin",
		actionText  = "jagt Schmetterlinge",
		statFocus   = "spd",
		bonus       = nil,
	},

	-- ---------------------------------------------------------------- 7
	{
		id          = "GummiRegen",
		displayName = "Gummi-Regen",
		floorColor  = Color3.fromRGB(120,  30,  70),
		fenceColor  = Color3.fromRGB(255,  90, 170),
		ringColor   = Color3.fromRGB(255, 120, 190),
		bannerColor = Color3.fromRGB(255, 150, 200),
		action      = "bounce",
		actionText  = "faengt Gummis mit dem Maul",
		statFocus   = nil,
		bonus       = { kind = "gummies", amount = 400 },
	},

	-- ---------------------------------------------------------------- 8
	{
		id          = "ZauberZirkel",
		displayName = "Zauber-Zirkel",
		floorColor  = Color3.fromRGB( 60,  30, 110),
		fenceColor  = Color3.fromRGB(170, 110, 255),
		ringColor   = Color3.fromRGB(190, 140, 255),
		bannerColor = Color3.fromRGB(205, 165, 255),
		action      = "spin",
		actionText  = "uebt seine Ability",
		statFocus   = "pwr",
		bonus       = nil,
	},

	-- ---------------------------------------------------------------- 9
	{
		id          = "NestFieber",
		displayName = "Nest-Fieber",
		floorColor  = Color3.fromRGB(120,  70,  40),
		fenceColor  = Color3.fromRGB(255, 180, 140),
		ringColor   = Color3.fromRGB(255, 200, 165),
		bannerColor = Color3.fromRGB(255, 215, 185),
		action      = "lean",
		actionText  = "waermt fremde Nester mit",
		statFocus   = "egg",
		bonus       = nil,
	},

	-- ---------------------------------------------------------------- 10
	-- Das seltenste Ereignis im Zyklus und der einzige Weg an eine Mutation
	-- ausserhalb eines Eis. Bewusst nur eine CHANCE und bewusst nur nach
	-- OBEN (siehe EventParticipationService): ein Baerchi, der schon Lava
	-- traegt, verliert sie hier nie — er kann sie nur verbessern.
	{
		id          = "MutationsSturm",
		displayName = "Mutations-Sturm",
		floorColor  = Color3.fromRGB( 90,  20,  90),
		fenceColor  = Color3.fromRGB(255,  60, 220),
		ringColor   = Color3.fromRGB(255, 100, 235),
		bannerColor = Color3.fromRGB(255, 140, 240),
		action      = "spin",
		actionText  = "steht mitten im schimmernden Sturm",
		statFocus   = nil,
		bonus       = { kind = "mutation", chance = 0.20 },
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

-- Der Bonus eines Events als kurzer, lesbarer Text ("1x Goldenes Ei").
-- nil, wenn das Event gar keinen Bonus hat.
--
-- Steht hier und nicht im UI, weil BEIDE Seiten denselben Text brauchen: die
-- Tafel ueber dem Pit (Server, EventService) und die Baerchi-Karte (Client).
-- Zwei getrennte Formulierungen wuerden beim naechsten Balancing auseinander
-- laufen.
local function describeBonus(bonus: EventBonus?): string?
	if not bonus then
		return nil
	end

	local amount = bonus.amount or 0

	if bonus.kind == "honey" then
		return string.format("%d Honig je Gebaeude", amount)

	elseif bonus.kind == "eggs" then
		local eggType = bonus.eggType or "BasicEgg"
		local eggDef  = EggConfig.data[eggType]
		return string.format("%dx %s", amount, if eggDef then eggDef.displayName else eggType)

	elseif bonus.kind == "gummies" then
		return string.format("%d Gummies", amount)

	elseif bonus.kind == "goldGummies" then
		return string.format("%d GoldGummies", amount)

	elseif bonus.kind == "mutation" then
		return string.format("%d%% Chance auf eine Mutation", math.floor((bonus.chance or 0) * 100 + 0.5))
	end

	return nil
end

-- Die vollstaendige Belohnung eines Events in einer Zeile, fuer Tafel und UI:
--   "+1 ATK-Stufe"
--   "+1 Stat-Stufe  •  1x Goldenes Ei"
local function describeReward(def: EventDef): string
	-- statFocus erst in eine lokale Variable: ein optionales Feld direkt als
	-- Tabellen-Schluessel zu benutzen ist unter --!strict die Art Stelle, an
	-- der die Typpruefung je nach Luau-Version zickt.
	local focus    = def.statFocus
	local statPart = "+1 Stat-Stufe"

	if focus then
		statPart = string.format("+1 %s-Stufe", PromotionConfig.STAT_LABELS[focus] or focus)
	end

	local bonusPart = describeBonus(def.bonus)
	if not bonusPart then
		return statPart
	end

	return statPart .. "  •  " .. bonusPart
end

return {
	EVENT_DURATION_SECONDS = EVENT_DURATION_SECONDS,
	EVENT_GAP_SECONDS      = EVENT_GAP_SECONDS,
	EVENTS                 = EVENTS,

	getById        = getById,
	describeBonus  = describeBonus,
	describeReward = describeReward,
}
