--!strict
-- EventService.luau
-- ServerScriptService/Services/EventService.luau
--
-- Einzige Zustaendigkeit:
--   - Den Event-Zyklus fahren (Pause → Event → Pause → ...)
--   - Das Event-Pit in der Weltmitte entsprechend umfaerben (MapService)
--   - Die Countdown-Tafel darueber beschriften
--
-- Kennt weiterhin WEDER Spielerdaten NOCH Waehrung. Dass ein Event inzwischen
-- eine spielerische Auswirkung hat (Stat-Fortschritt fuer teilnehmende
-- Baerchis), aendert daran nichts: dieser Service meldet nur, WANN ein Event
-- endet — was daraufhin passiert, entscheidet allein
-- EventParticipationService ueber den onEventEnded-Callback weiter unten.
--
-- Genau diese Trennung ist der Grund, warum der Zyklus hier keine einzige
-- Zeile Spiellogik bekommt: sonst waere dieser Service beim naechsten Feature
-- ("Event gibt auch Honig") die Stelle, an der drei fremde Systeme
-- zusammenlaufen.
--
-- ============================================================
-- WARUM EIN EIGENER SERVICE UND NICHT TEIL VON MAPSERVICE
-- ============================================================
-- MapService baut und AENDERT Geometrie, entscheidet aber nirgendwo sonst
-- WANN etwas passiert — das ist ueberall sonst Sache des aufrufenden Service
-- (CombatService/PitArenaService fuer den Kampf-Ablauf, HoneyService fuer die
-- Produktions-Zeitpunkte). Der Event-Zyklus ist genau so ein "wann", also
-- bekommt er einen eigenen, kleinen Service statt MapService eine zweite
-- Zustaendigkeit aufzubuerden.

local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")

local EventConfig = require(ReplicatedStorage.Config.EventConfig)
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)  -- HBB Paket 6
local MapConfig    = require(ReplicatedStorage.Config.MapConfig)
local Remotes      = require(ReplicatedStorage.Network.Remotes)
local MapService   = require(ServerScriptService.Services.MapService)

local EventService = {}

-- Das Boss-Event, auf das das Wespen-Nest zeigt (EventConfig.EVENTS)
local WASP_QUEEN_ID = "WaspQueen"

--------------------------------------------------------------------------------
-- Zustand
--------------------------------------------------------------------------------

-- Das gerade laufende Event, oder nil waehrend einer Pause.
local _active: EventConfig.EventDef? = nil

-- Zeitstempel (os.time()), an dem die aktuelle Phase (Event ODER Pause) endet.
local _phaseEndsAt = 0

-- Index in EventConfig.EVENTS, der als naechstes drankommt. Der Reihe nach,
-- kein Zufall — siehe EventConfig, Kommentar bei EVENTS.
local _nextIndex = 1

-- In welchem Durchlauf des Zyklus das naechste Event liegt (ab 1). Events mit
-- everyNthCycle (Boss) laufen nur in passenden Durchlaeufen; die Regel steht
-- in EventConfig.isScheduledInCycle, hier wird nur weitergezaehlt.
local _nextCycle = 1

-- Beobachter, die beim START eines Events benachrichtigt werden wollen
-- (EventParticipationService startet damit den Event-Handler).
local _onEventStarted: { (EventConfig.EventDef) -> () } = {}

-- Beobachter, die beim ENDE eines Events benachrichtigt werden wollen.
-- Aktuell genau einer: EventParticipationService, der dann die Stat-Stufen
-- an die anwesenden Baerchis verteilt.
local _onEventEnded: { (EventConfig.EventDef) -> () } = {}

--------------------------------------------------------------------------------
-- Hilfen
--------------------------------------------------------------------------------

local function formatCountdown(seconds: number): string
	local clamped = math.max(0, math.floor(seconds))
	local minutes = clamped // 60
	local secs    = clamped % 60
	return string.format("%d:%02d", minutes, secs)
end

-- Die drei Angaben einer Phasen-Meldung: laufendes Event (nil in der Pause),
-- Restzeit der Phase, und welches Event als naechstes kommt.
--
-- Das NAECHSTE Event gehoert mit dazu, weil der Spieler waehrend der Pause
-- entscheidet: nur wenn er weiss, was gleich laeuft, kann er seinen Baerchi
-- rechtzeitig losschicken (der Weg in die Mitte dauert selbst ein paar
-- Sekunden). Auf der Tafel steht dieselbe Information — die sieht aber nur,
-- wer gerade in die Weltmitte schaut.
local function phasePayload(): (string?, number, string)
	return
		(if _active then _active.id else nil),
		math.max(0, _phaseEndsAt - os.time()),
		EventConfig.EVENTS[_nextIndex].id
end

-- Sagt ALLEN Clients, welches Event gerade laeuft (bzw. dass Pause ist).
--
-- Nur bei einem PHASENWECHSEL und beim Join, nicht im Sekundentakt: die Uhr
-- steht sichtbar auf der Tafel in der Welt, dafuer braucht es kein Remote. Der
-- Client benutzt die Meldung ausschliesslich, um auf der Baerchi-Karte
-- anzuzeigen, was eine Teilnahme gerade bringen wuerde (siehe BaerchiPanel).
local function broadcastPhase()
	Remotes.EventPhaseChanged:FireAllClients(phasePayload())
end

-- Stellt _nextIndex auf das naechste Event, das im jeweiligen Durchlauf
-- laeuft. Beim Umlauf (letztes → erstes Event) beginnt ein neuer Durchlauf.
local function advance()
	local count = #EventConfig.EVENTS
	for _ = 1, count * 2 do
		_nextIndex += 1
		if _nextIndex > count then
			_nextIndex = 1
			_nextCycle += 1
		end
		if EventConfig.isScheduledInCycle(EventConfig.EVENTS[_nextIndex], _nextCycle) then
			return
		end
	end
end

local function startEvent()
	local def = EventConfig.EVENTS[_nextIndex]
	advance()

	_active      = def
	_phaseEndsAt = os.time() + EventConfig.getDuration(def)

	MapService.setEventPitTheme({
		floorColor = def.floorColor,
		fenceColor = def.fenceColor,
		ringColor  = def.ringColor,
	})

	broadcastPhase()

	print("[EventService] Event gestartet:", def.displayName, "|", EventConfig.describeReward(def))

	for _, callback in _onEventStarted do
		local ok, err = pcall(callback, def)
		if not ok then
			warn("[EventService] onEventStarted-Callback fehlgeschlagen:", err)
		end
	end
end

local function endEvent()
	local finished = _active
	_active      = nil
	_phaseEndsAt = os.time() + EventConfig.EVENT_GAP_SECONDS

	MapService.setEventPitTheme(nil)
	broadcastPhase()

	if finished then
		print("[EventService] Event beendet:", finished.displayName)

		-- Beobachter NACH dem Aufraeumen benachrichtigen: sie sollen einen
		-- Zustand vorfinden, in dem das Event nachweislich vorbei ist
		-- (getActive() gibt bereits nil zurueck). Jeder Callback in pcall — ein
		-- Fehler beim Verteilen der Belohnung darf den Zyklus nicht anhalten,
		-- sonst stuende die Event-Uhr fuer den ganzen Server still.
		for _, callback in _onEventEnded do
			local ok, err = pcall(callback, finished)
			if not ok then
				warn("[EventService] onEventEnded-Callback fehlgeschlagen:", err)
			end
		end
	end
end

-- Ein Tick pro Sekunde: Phase ggf. wechseln, danach die Tafel nachziehen.
-- Zeit wird immer aus os.time()/_phaseEndsAt neu gerechnet statt einfach
-- runtergezaehlt — ein einzelner ausgesetzter Tick (Server-Laghlack) darf die
-- Uhr nicht verschieben.
local function tick()
	local remaining = _phaseEndsAt - os.time()

	if remaining <= 0 then
		if _active then
			endEvent()
		else
			startEvent()
		end
		remaining = _phaseEndsAt - os.time()
	end

	-- Auf der Tafel steht IMMER auch die Belohnung — bei zehn Events im
	-- Wechsel waere "Naechstes Event / in 4:12" sonst keine Information, auf
	-- die man eine Entscheidung stuetzen kann. Waehrend der Pause wird deshalb
	-- zusaetzlich angekuendigt, WELCHES Event als naechstes kommt: nur so kann
	-- ein Spieler seinen Baerchi rechtzeitig hinschicken, wenn genau dieses
	-- Event den Stat bringt, den er braucht.
	if _active then
		MapService.setEventBanner(
			string.format("%s  •  LIVE", _active.displayName),
			string.format("noch %s", formatCountdown(remaining)),
			_active.bannerColor,
			EventConfig.describeReward(_active)
		)
	else
		local upcoming = EventConfig.EVENTS[_nextIndex]

		MapService.setEventBanner(
			string.format("Naechstes: %s", upcoming.displayName),
			string.format("in %s", formatCountdown(remaining)),
			MapConfig.EVENT_PIT_BANNER_IDLE_COLOR,
			EventConfig.describeReward(upcoming)
		)
	end

	-- HBB Paket 6: Wespen-Nest am Mast zaehlt bis zur Koenigin herunter
	-- (sprachneutral: Biene + Uhr) und leuchtet kurz davor und waehrenddessen.
	if FeatureFlags.isOn("MAP_V2_WASP_NEST") then
		local activeId = if _active then _active.id else nil
		local untilBoss = EventConfig.secondsUntilStart(WASP_QUEEN_ID, activeId, remaining, _nextIndex, _nextCycle)
		if untilBoss then
			MapService.setWaspNest(
				if untilBoss == 0 then "🐝 LIVE" else "🐝 " .. formatCountdown(untilBoss),
				untilBoss <= MapConfig.WASP_NEST.glowSeconds
			)
		end
	end
end

--------------------------------------------------------------------------------
-- Oeffentliche API
--------------------------------------------------------------------------------

-- Das gerade laufende Event, falls eins laeuft — nil waehrend einer Pause.
-- Wird von EventParticipationService gelesen (und vom Client ueber dessen
-- Zustandsmeldungen indirekt mitbekommen).
function EventService.getActive(): EventConfig.EventDef?
	return _active
end

-- Das Event, das als NAECHSTES an der Reihe ist. Waehrend einer Pause ist das
-- der Countdown-Gegenstand auf der Tafel; waehrend eines laufenden Events ist
-- es das darauf folgende.
--
-- Gibt es immer (der Zyklus ist ein Ring), deshalb kein optionaler Rueckgabewert.
function EventService.getNext(): EventConfig.EventDef
	return EventConfig.EVENTS[_nextIndex]
end

-- Sekunden bis zum Ende der laufenden Phase (Event ODER Pause). Nie negativ.
function EventService.getRemainingSeconds(): number
	return math.max(0, _phaseEndsAt - os.time())
end

-- Beendet die laufende Phase sofort — laeuft gerade ein Event, ist es danach
-- vorbei (inklusive aller onEventEnded-Callbacks); ist gerade Pause, startet
-- sofort das naechste Event.
--
-- Nur fuer den Studio-Test gedacht (DebugService): ein Zyklus aus 3 Minuten
-- Event und 5 Minuten Pause laesst sich sonst nicht in vertretbarer Zeit
-- durchspielen. Bewusst KEIN eigener Sonderweg — es wird nur die Uhr
-- vorgestellt, den Rest macht der normale tick(). Dadurch kann dieser Aufruf
-- auch nichts kaputt machen, was im echten Ablauf nicht ohnehin passiert.
function EventService.skipPhase()
	_phaseEndsAt = os.time()
end

-- Stellt den Zyklus so, dass als naechstes GENAU dieses Event kommt, und
-- startet es sofort. Gibt false zurueck, wenn es die id nicht gibt.
--
-- Ebenfalls nur fuer den Studio-Test gedacht (DebugService): bei zehn Events
-- im Wechsel dauert ein voller Durchlauf 80 Minuten — ein bestimmtes Event
-- abzuwarten waere sonst keine Testmoeglichkeit, sondern eine Geduldsprobe.
--
-- Laeuft gerade ein Event, wird es ordentlich beendet (inklusive aller
-- onEventEnded-Callbacks, also auch der Belohnungen) statt einfach ersetzt —
-- sonst haette ein Testaufruf nebenbei die Teilnahme aller Anwesenden
-- verschluckt.
function EventService.startById(id: string): boolean
	local index: number? = nil
	for i, def in EventConfig.EVENTS do
		if def.id == id then
			index = i
			break
		end
	end

	if not index then
		return false
	end

	if _active then
		endEvent()
	end

	_nextIndex = index
	startEvent()
	return true
end

-- Registriert einen Callback, der laeuft sobald ein Event ZU ENDE ist.
--
-- Anders als PlayerService.onDataLoaded ist die Reihenfolge zu init() hier
-- UNKRITISCH: der Server startet grundsaetzlich in einer Pause (siehe init),
-- das erste Event endet also fruehestens nach EVENT_GAP + EVENT_DURATION
-- Sekunden. Bis dahin sind laengst alle Services angemeldet.
function EventService.onEventStarted(callback: (EventConfig.EventDef) -> ())
	table.insert(_onEventStarted, callback)
end

function EventService.onEventEnded(callback: (EventConfig.EventDef) -> ())
	table.insert(_onEventEnded, callback)
end

function EventService.init()
	-- Wer spaeter dazukommt, hat den letzten Phasenwechsel verpasst — also
	-- bekommt jeder neue Spieler den Stand einmal gezielt zugeschickt. Ohne
	-- das zeigte seine Baerchi-Karte bis zum naechsten Wechsel (bis zu fuenf
	-- Minuten) "gerade kein Event", obwohl das Pit vor ihm leuchtet.
	Players.PlayerAdded:Connect(function(player)
		Remotes.EventPhaseChanged:FireClient(player, phasePayload())
	end)

	print(
		"[EventService] Initialisiert |", #EventConfig.EVENTS, "Events im Wechsel",
		"(manche nur jeden n-ten Durchlauf) | individuelle Dauer,", EventConfig.EVENT_GAP_SECONDS, "s Pause"
	)
end

-- Der Zyklus laeuft erst in start(): dann steht die Welt (das Event-Pit baut
-- MapService.init) und alle onEventStarted/onEventEnded-Rueckrufe sind
-- angemeldet.
function EventService.start()
	-- Server startet in der Pause, nicht mitten in einem Event — sonst wuerde
	-- jeder frisch gestartete Server sofort mit einem laufenden Event
	-- begruesst, was sich nach einem Fehler anfuehlt statt nach Absicht.
	-- HBB Paket 6: die erste Pause eines neuen Servers ist kuerzer.
	local firstGap = if FeatureFlags.isOn("EVENT_V2_TIMER")
		then EventConfig.FIRST_GAP_SECONDS
		else EventConfig.EVENT_GAP_SECONDS
	_phaseEndsAt = os.time() + firstGap
	MapService.setEventPitTheme(nil)

	task.spawn(function()
		while true do
			local ok, err = pcall(tick)
			if not ok then
				warn("[EventService] Tick fehlgeschlagen:", err)
			end
			task.wait(1)
		end
	end)
end

return EventService
