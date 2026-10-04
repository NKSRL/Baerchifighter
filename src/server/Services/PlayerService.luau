--!strict
-- PlayerService.luau
-- ServerScriptService/Services/PlayerService.luau
--
-- Einzige Zustaendigkeit:
--   - Spielerdaten laden (DataStore) und im Speicher halten
--   - Spielerdaten speichern (beim Leave und periodisch)
--   - Insel spawnen/despawnen via MapService
--   - Anderen Services Zugriff auf PlayerData geben
--
-- Kein anderer Service beruehrt den DataStore. Geschrieben wird mit
-- UpdateAsync und einer Sitzungs-Sperre im Spielstand (Util/SessionLock),
-- damit zwei Server nie gegenseitig ihren Fortschritt ueberschreiben. Die
-- Migration alter Spielstaende steht in Util/PlayerMigration.
--
-- Hinweis zu onDataLoaded():
--   PlayerService darf EconomyService NICHT requiren (EconomyService requiret
--   PlayerService — das waere ein Zirkel). Services die beim Join etwas
--   gutschreiben wollen (z.B. HoneyService fuer den Offline-Honig) registrieren
--   deshalb hier einen Callback statt selbst an PlayerAdded zu haengen —
--   nur so ist garantiert dass die Daten zum Zeitpunkt des Callbacks geladen sind.

local Players       = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")

local Types           = require(ReplicatedStorage.Network.Types)
local Remotes         = require(ReplicatedStorage.Network.Remotes)
local QuestProgress   = require(ReplicatedStorage.Modules.QuestProgress)
local MapService      = require(ServerScriptService.Services.MapService)
local RateLimiter     = require(ServerScriptService.Util.RateLimiter)
local PlayerMigration = require(ServerScriptService.Util.PlayerMigration)
local SessionLock     = require(ServerScriptService.Util.SessionLock)

--------------------------------------------------------------------------------
-- Konstanten
--------------------------------------------------------------------------------

local DATA_STORE_NAME = "PlayerData_v1"
-- v1 im Namen: wenn wir das Schema brechen, wird es v2 und alte Daten
-- werden nicht mehr geladen (sauberer als Migration fuer early dev).
-- Nicht-brechende Feld-Ergaenzungen laufen ueber
-- PlayerMigration.applyDefaults().

-- Spaetestens nach so vielen Sekunden wird auf jeden Fall gespeichert.
local SAVE_INTERVAL = 60

-- Fruehestens nach so vielen Sekunden darf derselbe Schluessel wieder
-- geschrieben werden. Roblox drosselt Schreibvorgaenge auf denselben
-- Schluessel unterhalb von etwa sechs Sekunden und verwirft sie irgendwann
-- ganz. saveNow() wird von vielen Stellen aufgerufen (Ei oeffnen,
-- fusionieren, verwerten, kaempfen, zwei Upgrades, Rebirth) — ohne diese
-- Bremse kaeme ein normal spielender Mensch auf mehrere Schreibvorgaenge
-- pro Sekunde.
local MIN_SAVE_GAP = 7

-- Wie oft nachgesehen wird ob jemand faellig ist.
local SAVE_TICK = 5

--------------------------------------------------------------------------------
-- DataStore-Zugriff
--
-- GetDataStore() wirft in einem unveroeffentlichten Place ("You must publish
-- this place to the web to access DataStore") und in Studio ohne aktivierte
-- API-Services. Frueher stand der Aufruf auf Modulebene — ein Fehler dort hat
-- PlayerService, EconomyService und damit den ganzen GameManager mitgerissen.
--
-- Deshalb: verzoegert holen, in pcall, und bei Nichtverfuegbarkeit auf einen
-- reinen Sitzungs-Speicher zurueckfallen. Das Spiel bleibt in Studio komplett
-- testbar (inklusive Leave/Rejoin und Offline-Ertrag), nur ueberlebt der
-- Fortschritt keinen Server-Neustart. Im veroeffentlichten Place greift
-- automatisch der echte DataStore.
--------------------------------------------------------------------------------

local _dataStore: DataStore? = nil
local _dataStoreChecked = false

-- Fallback wenn kein DataStore verfuegbar ist, key = "player_<UserId>"
local _sessionStore: { [string]: Types.PlayerData } = {}

local function getDataStore(): DataStore?
	if _dataStoreChecked then
		return _dataStore
	end
	_dataStoreChecked = true

	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(DATA_STORE_NAME)
	end)

	if ok then
		_dataStore = result
	else
		warn(
			"[PlayerService] DataStore nicht verfuegbar —",
			"Fortschritt wird nur fuer diese Server-Sitzung gehalten.",
			"Grund:", result
		)
	end

	return _dataStore
end

local function storageKey(player: Player): string
	return "player_" .. player.UserId
end

--------------------------------------------------------------------------------
-- Interner Zustand
-- Nur dieser Service liest/schreibt diese Tabelle.
--------------------------------------------------------------------------------

-- Alle geladenen Spielerdaten im Speicher, key = Player
local _playerData: { [Player]: Types.PlayerData } = {}

-- Timestamp des letzten Saves pro Spieler
local _lastSave: { [Player]: number } = {}

-- Spieler die gerade geladen werden (verhindert Doppel-Joins)
local _loading: { [Player]: boolean } = {}

-- Spieler deren Spielstand NICHT geladen werden konnte. Ihre Sitzung ist
-- spielbar, wird aber nie gespeichert — sonst wuerden die frischen
-- Standardwerte den echten Spielstand ueberschreiben.
local _noSave: { [Player]: boolean } = {}

-- Spieler die gespeichert werden wollen, aber gerade in der Schonfrist
-- stecken (siehe MIN_SAVE_GAP). Die Auto-Save-Schleife holt sie nach.
local _pendingSave: { [Player]: boolean } = {}

-- Callbacks anderer Services, ausgefuehrt direkt nach dem Laden
local _onDataLoaded: { (Player, Types.PlayerData) -> () } = {}

-- Callbacks anderer Services, ausgefuehrt nach allen _onDataLoaded
local _onPlayerReady: { (Player, Types.PlayerData) -> () } = {}

-- Callbacks anderer Services, ausgefuehrt bei jedem markDirty
local _onDataChanged: { (Player, Types.PlayerData) -> () } = {}

-- v12: Callbacks, die beim Verlassen (und beim Server-Shutdown) laufen,
-- BEVOR gespeichert wird. Grund: ein PIT-Lauf wird erst am Ende seiner
-- Wiedergabe abgerechnet (PitArenaService). Verlaesst der Spieler mitten im
-- Lauf, muss die Abrechnung noch in den Spielstand, bevor er geschrieben
-- wird — die Reihenfolge zweier PlayerRemoving-Verbindungen ist dafuer
-- nicht verlaesslich genug.
local _onPlayerLeaving: { (Player, Types.PlayerData) -> () } = {}

local function runLeavingCallbacks(player: Player, data: Types.PlayerData)
	for _, callback in _onPlayerLeaving do
		local ok, err = pcall(callback, player, data)
		if not ok then
			warn("[PlayerService] onPlayerLeaving-Callback fehlgeschlagen:", err)
		end
	end
end

--------------------------------------------------------------------------------
-- Hilfsfunktionen (privat)
--------------------------------------------------------------------------------

-- Wie oft das Laden bei einem DataStore-Fehler erneut versucht wird, und wie
-- lange dazwischen gewartet wird (verdoppelt sich jedes Mal).
local LOAD_RETRIES     = 3
local LOAD_RETRY_DELAY = 2

-- Haelt ein anderer Server den Spielstand noch (siehe Util/SessionLock), wird
-- so oft im Abstand von SESSION_WAIT_SECONDS erneut gefragt. Der Normalfall
-- ist ein schneller Serverwechsel: der alte Server schreibt beim Verlassen und
-- gibt die Sperre dabei frei, das dauert Sekunden. Insgesamt 30 Sekunden
-- reichen dafuer und sind kurz genug, dass der Spieler nicht ewig wartet.
local SESSION_WAIT_ATTEMPTS = 5
local SESSION_WAIT_SECONDS  = 6

-- In Studio ist game.JobId leer. Alle Studio-Sitzungen gelten dann als
-- derselbe Server, sonst sperrte man sich beim Neustart einer Testsitzung
-- selbst aus.
local function currentJobId(): string
	return if game.JobId ~= "" then game.JobId else "studio"
end

-- Ein Ladeversuch: liest den Spielstand und traegt im SELBEN Schreibvorgang
-- diesen Server als Halter ein (UpdateAsync ist dafuer atomar). Ergebnis:
--   "ok"     data ist der rohe Spielstand (isNew = frisch angelegt)
--   "locked" ein anderer Server haelt ihn, es wurde nichts geschrieben
--   "error"  der DataStore hat geworfen, data ist die Fehlermeldung
local function tryLoadAndClaim(store: DataStore, key: string): (string, any, boolean)
	local jobId = currentJobId()
	local outcome = "ok"
	local loaded: any = nil
	local isNew = false

	local success, err = pcall(function()
		store:UpdateAsync(key, function(old: any)
			-- Roblox kann diesen Rueckruf mehrfach aufrufen (Konflikt beim
			-- Schreiben). Deshalb setzt jeder Durchlauf alle Ergebnisse neu.
			local now = os.time()
			if old ~= nil and SessionLock.isHeldByOther(old.session, jobId, now) then
				outcome, loaded, isNew = "locked", nil, false
				return nil   -- nil = nichts schreiben
			end

			local data = if old ~= nil then old else Types.createDefaultPlayerData()
			data.session = SessionLock.claim(jobId, now)
			outcome, loaded, isNew = "ok", data, old == nil
			return data
		end)
	end)

	if not success then
		return "error", err, false
	end
	return outcome, loaded, isNew
end

-- Liefert (Spielstand, darf gespeichert werden).
local function loadFromDataStore(player: Player): (Types.PlayerData, boolean)
	local key   = storageKey(player)
	local store = getDataStore()

	-- Kein DataStore (unveroeffentlichter Place / Studio ohne API-Services):
	-- aus dem Sitzungs-Speicher lesen, damit Leave/Rejoin trotzdem testbar ist.
	if not store then
		local cached = _sessionStore[key]
		if cached then
			return PlayerMigration.applyDefaults(cached), true
		end
		return Types.createDefaultPlayerData(), true
	end

	-- Mehrfach versuchen: ein einzelner DataStore-Aussetzer (Drosselung,
	-- Roblox-Stoerung) ist haeufig und geht meist beim zweiten Versuch durch.
	-- Fehler und fremde Sperre werden getrennt gezaehlt, weil sie verschieden
	-- lange brauchen, um sich aufzuloesen.
	local lastError: any = nil
	local errors = 0
	local waits  = 0

	while true do
		local outcome, result, isNew = tryLoadAndClaim(store, key)

		if outcome == "ok" then
			-- Ein frischer Spielstand ist schon aktuell; nur alte Staende
			-- laufen durch die Migration.
			if isNew then
				return result, true
			end
			return PlayerMigration.applyDefaults(result), true
		end

		if outcome == "locked" then
			waits += 1
			if waits >= SESSION_WAIT_ATTEMPTS then
				-- Der andere Server meldet sich weiter. Ihn zu ueberschreiben
				-- hiesse, seinen Fortschritt zu loeschen. Also dieselbe
				-- Behandlung wie ein Lesefehler: spielbar, aber nie gespeichert.
				warn(
					"[PlayerService] Spielstand von", player.Name,
					"wird noch von einem anderen Server gehalten — Sitzung laeuft OHNE Speichern weiter."
				)
				return Types.createDefaultPlayerData(), false
			end
			task.wait(SESSION_WAIT_SECONDS)
		else
			errors += 1
			lastError = result
			if errors >= LOAD_RETRIES then
				break
			end
			task.wait(LOAD_RETRY_DELAY * errors)
		end

		-- Wer waehrend des Wartens geht, braucht keinen Spielstand mehr.
		if player.Parent == nil then
			return Types.createDefaultPlayerData(), false
		end
	end

	-- Auch nach allen Versuchen kein Erfolg. Der Spieler bekommt eine
	-- spielbare Sitzung, aber sie DARF NICHT GESPEICHERT werden:
	-- sonst wuerde der Auto-Save die frischen Standardwerte ueber einen
	-- vollkommen intakten Spielstand schreiben und ihn dauerhaft loeschen.
	warn(
		"[PlayerService] Laden endgueltig fehlgeschlagen fuer", player.Name,
		"— Sitzung laeuft OHNE Speichern weiter. Grund:", lastError
	)
	return Types.createDefaultPlayerData(), false
end

-- Schreibt den Spielstand. release = true beim Verlassen und beim Shutdown:
-- dann wird die Sitzungs-Sperre freigegeben, damit der naechste Server sofort
-- laden kann, statt auf ihren Ablauf zu warten.
local function saveToDataStore(player: Player, data: Types.PlayerData, release: boolean)
	-- Konnte der Spielstand nicht geladen werden, wird auch nicht gespeichert.
	-- Siehe loadFromDataStore: sonst ueberschreibt eine Standard-Datei den
	-- echten Spielstand.
	if _noSave[player] then
		return
	end

	-- Zeitstempel VOR dem Schreiben setzen. UpdateAsync haelt den Thread an;
	-- stuende die Zeile darunter, wuerde die Auto-Save-Schleife waehrend des
	-- Wartens immer wieder dieselbe Bedingung erfuellen und dutzende
	-- gleichzeitige Schreibvorgaenge auf denselben Schluessel ausloesen.
	_lastSave[player] = os.time()
	data.lastSeenAt   = os.time()

	local key   = storageKey(player)
	local store = getDataStore()

	if not store then
		_sessionStore[key] = data
		return
	end

	-- UpdateAsync statt SetAsync: es liest den gespeicherten Stand, bevor es
	-- schreibt. Hat inzwischen ein anderer Server die Sperre uebernommen (weil
	-- unsere abgelaufen ist), wird NICHT geschrieben — dessen Stand ist neuer.
	local jobId = currentJobId()
	local lostLock = false

	local success, err = pcall(function()
		store:UpdateAsync(key, function(old: any)
			local now = os.time()
			if old ~= nil and SessionLock.isHeldByOther(old.session, jobId, now) then
				lostLock = true
				return nil
			end
			lostLock = false
			data.session = if release then nil else SessionLock.claim(jobId, now)
			return data
		end)
	end)

	if not success then
		warn("[PlayerService] DataStore-Fehler beim Speichern fuer", player.Name, ":", err)
	elseif lostLock then
		-- Ab jetzt gilt der andere Server. Diese Sitzung schreibt nie wieder,
		-- sonst wechselten sich zwei Staende gegenseitig ab.
		_noSave[player] = true
		warn(
			"[PlayerService] Sitzungs-Sperre von", player.Name,
			"liegt bei einem anderen Server — diese Sitzung speichert nicht mehr."
		)
	end
end

-- Baut das Client-Paket aus den Serverdaten.
-- Stats bleiben bewusst draussen (kein Leak sensibler Serverdaten).
local function buildUpdate(data: Types.PlayerData): Types.PlayerDataUpdate
	return {
		gummies      = data.gummies,
		goldGummies  = data.goldGummies,
		rebirthCount = data.rebirthCount,
		rebirthMult  = data.rebirthMult,
		rank         = data.rank,
		language     = data.language,
		island       = data.island,
		discovered   = data.discovered,
		quests       = QuestProgress.buildView(data, os.time()),
		eggTree      = data.eggTree,
	}
end

-- Sendet den aktuellen Spielerzustand an den Client
-- Wird nach jeder relevanten Aenderung aufgerufen
local function syncToClient(player: Player)
	local data = _playerData[player]
	if not data then return end

	Remotes.PlayerDataUpdated:FireClient(player, buildUpdate(data))
end

--------------------------------------------------------------------------------
-- Oeffentliche API
-- Andere Services rufen diese Funktionen auf.
--------------------------------------------------------------------------------

local PlayerService = {}

-- Gibt PlayerData zurueck — nil wenn noch nicht geladen
function PlayerService.getData(player: Player): Types.PlayerData?
	return _playerData[player]
end

-- Gibt PlayerData zurueck und wirft einen Fehler wenn nicht vorhanden
-- Fuer Services die sicher sind dass der Spieler eingeloggt ist
function PlayerService.getDataOrError(player: Player): Types.PlayerData
	local data = _playerData[player]
	assert(data, "[PlayerService] Keine Daten fuer Spieler: " .. player.Name)
	return data
end

-- Wird von anderen Services aufgerufen nachdem sie Daten veraendert haben.
-- Loest Client-Sync aus. Services aendern Daten direkt auf dem Objekt,
-- rufen dann markDirty() — kein Kopieren, kein Callback-Hell.
function PlayerService.markDirty(player: Player)
	syncToClient(player)

	local data = _playerData[player]
	if not data then return end

	-- Beobachter benachrichtigen (z.B. PlotDisplayService, das die Figuren und
	-- Schilder auf der Insel nachzieht). Ein Callback darf hier NICHT selbst
	-- markDirty aufrufen — das waere eine Endlosschleife.
	for _, callback in _onDataChanged do
		local ok, err = pcall(callback, player, data)
		if not ok then
			warn("[PlayerService] onDataChanged-Callback fehlgeschlagen:", err)
		end
	end
end

-- Nach einer wichtigen Aenderung speichern (Kauf, Kampf, Rebirth).
--
-- "Sofort" nur wenn die Schonfrist abgelaufen ist — sonst wird es lediglich
-- vorgemerkt und die Auto-Save-Schleife holt es nach, sobald sie darf. Ohne
-- das wuerde Roblox die Schreibvorgaenge irgendwann verwerfen, und dann waere
-- ausgerechnet der Fortschritt weg, den dieser Aufruf sichern sollte.
--
-- Der Leave- und der Shutdown-Weg gehen bewusst direkt auf saveToDataStore
-- und umgehen die Bremse: dort gibt es kein spaeter mehr.
function PlayerService.saveNow(player: Player)
	local data = _playerData[player]
	if not data then return end

	if os.time() - (_lastSave[player] or 0) >= MIN_SAVE_GAP then
		saveToDataStore(player, data, false)
	else
		_pendingSave[player] = true
	end
end

-- Frische Standard-Insel. Einzige erlaubte Quelle fuer einen Insel-Reset —
-- RebirthService benutzt dies statt Types.createDefaultPlayerData selbst
-- aufzurufen (Regel: nur PlayerService ruft die Default-Fabrik auf).
function PlayerService.buildDefaultIsland(): Types.IslandData
	return Types.createDefaultPlayerData().island
end

-- Registriert einen Callback der laeuft sobald die Daten eines Spielers
-- geladen und seine Insel gespawnt ist — aber bevor der erste Client-Sync
-- rausgeht. Hier gehoert alles hin, was die Daten beim Join noch aendert
-- (Offline-Honig, Offline-Eier, Ausruesten). Aus init() aufrufen: Spieler
-- werden erst in start() geladen, also verpasst kein Callback einen Join.
--
-- Die Callbacks laufen in Anmelde-Reihenfolge. Keiner darf sich auf einen
-- anderen verlassen; wer den fertigen Stand braucht, nimmt onPlayerReady.
function PlayerService.onDataLoaded(callback: (Player, Types.PlayerData) -> ())
	table.insert(_onDataLoaded, callback)
end

-- Registriert einen Callback der nach ALLEN onDataLoaded-Callbacks laeuft,
-- direkt vor dem ersten Client-Sync. Fuer alles, was den fertig geladenen
-- Stand nur anzeigt (Schilder, gelegte Eier in der Welt). Darf die Daten
-- nicht mehr aendern.
function PlayerService.onPlayerReady(callback: (Player, Types.PlayerData) -> ())
	table.insert(_onPlayerReady, callback)
end

-- Registriert einen Callback der bei JEDER Datenaenderung laeuft (markDirty).
-- Wird oft aufgerufen — der Callback muss selbst entscheiden ob er wirklich
-- etwas tun muss, und darf nicht seinerseits markDirty aufrufen.
function PlayerService.onDataChanged(callback: (Player, Types.PlayerData) -> ())
	table.insert(_onDataChanged, callback)
end

-- v12: Callback, der beim Verlassen VOR dem Speichern laeuft (siehe
-- _onPlayerLeaving). Darf Daten aendern, aber nicht yielden.
function PlayerService.onPlayerLeaving(callback: (Player, Types.PlayerData) -> ())
	table.insert(_onPlayerLeaving, callback)
end

--------------------------------------------------------------------------------
-- Join / Leave
--------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	if _loading[player] then return end
	_loading[player] = true

	-- Daten laden (kann einen Moment dauern).
	--
	-- Zusaetzlich in pcall: die Migration (PlayerMigration) rechnet fuer alte
	-- Spielstaende echte Kampfwerte aus. Ein einzelner kaputter Eintrag darf
	-- den Join nicht mittendrin abbrechen — sonst bliebe _loading fuer immer
	-- gesetzt, der Spieler haette nie Daten und jedes Remote liefe still ins
	-- Leere, ohne dass irgendwo ein Fehler sichtbar waere.
	local ok, data, canSave = pcall(loadFromDataStore, player)

	if not ok then
		warn("[PlayerService] Spielstand von", player.Name, "ist beschaedigt:", data)
		data    = Types.createDefaultPlayerData()
		canSave = false   -- niemals ueber einen Stand schreiben den wir nicht lesen konnten
	end

	-- Spieler kann waehrend des Ladens schon wieder weg sein
	if player.Parent == nil then
		_loading[player] = nil
		return
	end

	if not canSave then
		_noSave[player] = true
	end

	_playerData[player] = data
	_lastSave[player]   = os.time()
	_loading[player]    = nil

	-- Insel spawnen — setzt dabei auch player.RespawnLocation auf die eigene
	-- Insel (siehe MapService.buildPlotBase).
	MapService.spawnIsland(player, data.island)

	-- Erst JETZT den Charakter laden: Players.CharacterAutoLoads steht in
	-- GameManager auf false, genau damit kein Spieler zwischen Join und
	-- geladenen Daten kurz in der Weltmitte auftaucht. RespawnLocation ist ab
	-- hier gesetzt (oder, falls der Server keinen freien Plot mehr hatte,
	-- eben nicht — dann faellt LoadCharacter auf den Not-Spawn zurueck, siehe
	-- MapService.buildPlatform).
	player:LoadCharacter()

	-- Andere Services informieren (Offline-Progress etc.)
	-- pcall: ein fehlerhafter Callback darf den Join nicht abbrechen.
	for _, callback in _onDataLoaded do
		local ok, err = pcall(callback, player, data)
		if not ok then
			warn("[PlayerService] onDataLoaded-Callback fehlgeschlagen:", err)
		end
	end

	for _, callback in _onPlayerReady do
		local ok, err = pcall(callback, player, data)
		if not ok then
			warn("[PlayerService] onPlayerReady-Callback fehlgeschlagen:", err)
		end
	end

	-- Ersten Sync zum Client
	syncToClient(player)

	print("[PlayerService] Spieler geladen:", player.Name,
		"| Gummies:", data.gummies,
		"| Rebirths:", data.rebirthCount)
end

local function onPlayerRemoving(player: Player)
	local data = _playerData[player]
	if data then
		runLeavingCallbacks(player, data)
		saveToDataStore(player, data, true)
		MapService.despawnIsland(player)
	end

	_playerData[player]  = nil
	_lastSave[player]    = nil
	_loading[player]     = nil
	_noSave[player]      = nil
	_pendingSave[player] = nil

	print("[PlayerService] Spieler entfernt:", player.Name)
end

--------------------------------------------------------------------------------
-- Auto-Save Loop
--------------------------------------------------------------------------------

-- Bewusst eine eigene Schleife und nicht Heartbeat: ein Speicher-Timer hat
-- nichts an der Bildwiederholrate zu suchen. Vorher lief die Pruefung 60 mal
-- pro Sekunde und ein einzelner faelliger Spieler loeste dutzende parallele
-- Schreibvorgaenge aus, weil das Schreiben den Thread anhaelt.
local function startAutoSave()
	task.spawn(function()
		while true do
			task.wait(SAVE_TICK)

			local now = os.time()
			for player, data in _playerData do
				local since = now - (_lastSave[player] or 0)

				-- Zwei Gruende zu speichern: es liegt eine Vormerkung aus
				-- saveNow vor, oder es ist einfach lange genug her.
				local wanted = _pendingSave[player] or since >= SAVE_INTERVAL

				if wanted and since >= MIN_SAVE_GAP then
					_pendingSave[player] = nil

					local ok, err = pcall(saveToDataStore, player, data, false)
					if not ok then
						warn("[PlayerService] Auto-Save fehlgeschlagen fuer", player.Name, ":", err)
					end
				end
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- Initialisierung
--------------------------------------------------------------------------------

function PlayerService.init()
	-- Reconnect-Fall: Client fragt seinen Zustand aktiv an.
	-- Ohne diesen Handler blockiert ein GetPlayerData-Invoke ewig.
	RateLimiter.connectFunction(Remotes.GetPlayerData, "GetPlayerData", function(player: Player)
		local data = _playerData[player]
		if not data then
			-- Noch nicht fertig geladen — Client soll auf PlayerDataUpdated warten
			return nil
		end
		return buildUpdate(data)
	end)

	-- Sicherheitsnetz: beim Server-Shutdown alle speichern
	game:BindToClose(function()
		for player, data in _playerData do
			runLeavingCallbacks(player, data)
			saveToDataStore(player, data, true)
		end
	end)

	startAutoSave()

	-- Verfuegbarkeit einmal beim Start pruefen, damit die Warnung im Log steht
	-- bevor der erste Spieler joint — und nicht mitten in einem Join auftaucht.
	if getDataStore() then
		print("[PlayerService] Initialisiert | DataStore aktiv")
	else
		print("[PlayerService] Initialisiert | OHNE DataStore — nur Sitzungs-Speicher")
	end
end

-- Erst hier werden Spieler geladen: GameManager ruft start() nach ALLEN
-- init(). Damit hat jeder Service seine Callbacks angemeldet, bevor der erste
-- Join sie ausloest — egal, wo er in der Startliste steht.
function PlayerService.start()
	-- Bereits verbundene Spieler (in Studio-Play-Solo ist der Spieler oft
	-- schon da, bevor der Server mit dem Starten fertig ist)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
end

return PlayerService
