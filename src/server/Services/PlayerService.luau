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
-- Kein anderer Service beruehrt den DataStore.
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

local Types            = require(ReplicatedStorage.Network.Types)
local Remotes          = require(ReplicatedStorage.Network.Remotes)
local BaerchiConfig    = require(ReplicatedStorage.Config.BaerchiConfig)
local PromotionConfig  = require(ReplicatedStorage.Config.PromotionConfig)
local CharmConfig      = require(ReplicatedStorage.Config.CharmConfig)
local CombatCalculator = require(ReplicatedStorage.Modules.CombatCalculator)
local MapService       = require(ServerScriptService.Services.MapService)
local RateLimiter      = require(ServerScriptService.Util.RateLimiter)

--------------------------------------------------------------------------------
-- Konstanten
--------------------------------------------------------------------------------

local DATA_STORE_NAME = "PlayerData_v1"
-- v1 im Namen: wenn wir das Schema brechen, wird es v2 und alte Daten
-- werden nicht mehr geladen (sauberer als Migration fuer early dev).
-- Nicht-brechende Feld-Ergaenzungen laufen ueber applyDefaults().

-- Spaetestens nach so vielen Sekunden wird auf jeden Fall gespeichert.
local SAVE_INTERVAL = 60

-- Fruehestens nach so vielen Sekunden darf derselbe Schluessel wieder
-- geschrieben werden. Roblox drosselt Schreibvorgaenge auf denselben
-- Schluessel unterhalb von etwa sechs Sekunden und verwirft sie irgendwann
-- ganz. saveNow() wird von acht Stellen aufgerufen (Ei einlegen, abholen,
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

-- Callbacks anderer Services, ausgefuehrt bei jedem markDirty
local _onDataChanged: { (Player, Types.PlayerData) -> () } = {}

--------------------------------------------------------------------------------
-- Hilfsfunktionen (privat)
--------------------------------------------------------------------------------

-- Fehlende Felder aus Default auffuellen (einfache Migration fuer neue Felder).
-- Muss jedes Feld abdecken das seit dem ersten Release in Types.luau
-- dazugekommen ist — sonst crasht alter Save-Stand beim ersten Zugriff.
local function applyDefaults(data: Types.PlayerData): Types.PlayerData
	local default = Types.createDefaultPlayerData()

	-- Neue Top-Level-Felder
	if data.gummies      == nil then data.gummies      = default.gummies      end
	if data.goldGummies  == nil then data.goldGummies  = default.goldGummies  end
	if data.rebirthCount == nil then data.rebirthCount = default.rebirthCount end
	if data.rebirthMult  == nil then data.rebirthMult  = default.rebirthMult  end
	if data.rank         == nil then data.rank         = default.rank         end
	if data.island       == nil then data.island       = default.island       end
	if data.stats        == nil then data.stats        = default.stats        end
	if data.createdAt    == nil then data.createdAt    = default.createdAt    end
	if data.lastSeenAt   == nil then data.lastSeenAt   = default.lastSeenAt   end

	-- Neue Stats-Felder (dynamischer Key → bewusst ueber any, sonst meckert --!strict)
	local stats     = data.stats    :: any
	local defStats  = default.stats :: any
	for key, value in defStats do
		if stats[key] == nil then
			stats[key] = value
		end
	end

	-- Neue Island-Felder
	local island = data.island
	if island.pitLevel  == nil then island.pitLevel  = 1  end
	if island.baerchis  == nil then island.baerchis  = {} end
	if island.eggStock  == nil then island.eggStock  = { BasicEgg = 3 } end

	-- language: kein Nachruesten noetig — nil bedeutet "automatisch" (die
	-- Roblox-Sprache des Clients), und genau das soll ein alter Spielstand
	-- bekommen. Kein Versions-Sprung. Siehe SettingsService.
	--
	-- v6: equippedUid. Kein Nachruesten noetig — ein fehlendes Feld liest
	-- sich in Lua ohnehin als nil, und IslandService.autoEquipIfNone laeuft
	-- bei jedem Join (onDataLoaded) und ruestet automatisch den ersten
	-- vorhandenen Baerchi aus, falls noch/wieder keiner steht.

	-- v2: laufende Brut-Slots
	if island.hatchingEggs == nil then island.hatchingEggs = {} end

	-- v10: gelegte Eier.
	--
	-- lastEggAt bewusst auf JETZT statt auf createdAt: ein Spielstand, der vor
	-- diesem Feature entstanden ist, hat keine Ei-Zeit — wuerde man hier
	-- createdAt einsetzen, bekaeme er beim ersten Join nach dem Update die
	-- Obergrenze auf einen Schlag geschenkt, fuer eine Zeit, in der es das
	-- Legen noch gar nicht gab.
	if island.laidEggs == nil then
		island.laidEggs = {}
	else
		-- Nur vollstaendige Eintraege behalten. Ein Ei ohne uid liesse sich nie
		-- einsammeln und laege bis in alle Ewigkeit auf dem Plot herum.
		local cleaned: { Types.LaidEgg } = {}
		for _, egg in island.laidEggs do
			if typeof(egg.uid) == "string" and #egg.uid > 0
				and typeof(egg.eggType) == "string"
				and typeof(egg.x) == "number"
				and typeof(egg.y) == "number"
				and typeof(egg.z) == "number"
			then
				table.insert(cleaned, egg)
			end
		end
		island.laidEggs = cleaned
	end

	if island.lastEggAt == nil then
		island.lastEggAt = os.time()
	end

	-- v5: Eier werden ueber eine uid geclaimt statt ueber ihren Listenindex.
	-- Alte Spielstaende haben noch keine — ohne Nachruesten waere ihr Ei
	-- unclaimbar, weil der Server keine passende uid findet. Der Index geht
	-- hier mit in den Namen, damit zwei Eier desselben Spielstands sich nicht
	-- zufaellig dieselbe uid teilen koennen.
	for index, egg in island.hatchingEggs do
		if egg.uid == nil or typeof(egg.uid) ~= "string" or #egg.uid == 0 then
			egg.uid = string.format("e_migrated_%d_%d", index, egg.startedAt or 0)
		end
	end

	-- v4: die Gebaeude sind komplett ausgetauscht. Frueher gab es Hatchery,
	-- GummyFarm, Recycler (und davor FusionLab) mit je eigener Funktion —
	-- jetzt drei reine Honig-Produzenten. Alte Eintraege werden entfernt und
	-- die neuen angelegt; das Level laesst sich nicht sinnvoll uebertragen,
	-- weil die Gebaeude etwas voellig anderes tun.
	local OBSOLETE_BUILDINGS = { "Hatchery", "GummyFarm", "Recycler", "FusionLab" }

	if island.buildings == nil then
		island.buildings = default.island.buildings
	else
		local buildings = island.buildings :: any

		for _, obsolete in OBSOLETE_BUILDINGS do
			buildings[obsolete] = nil
		end

		for buildingId, building in default.island.buildings do
			local existing = buildings[buildingId]
			if existing == nil then
				buildings[buildingId] = {
					id             = building.id,
					level          = building.level,
					honey          = building.honey,
					lastProducedAt = building.lastProducedAt,
				}
			else
				-- v4: Honig-Felder auf bereits vorhandenen Gebaeuden nachruesten
				if existing.honey == nil then
					existing.honey = 0
				end
				if existing.lastProducedAt == nil then
					existing.lastProducedAt = os.time()
				end
			end
		end
	end

	-- v7: die drei Gebaeude haben eigene Rollen bekommen (siehe
	-- Config/BuildingBehavior). Die XP pro Honig haengen seitdem allein am Level
	-- der Honig-Presse — vorher am Level des Gebaeudes, aus dem der Honig kam,
	-- also an allen dreien.
	--
	-- Ohne Ausgleich wuerde ein laufender Spielstand dabei XP VERLIEREN: wer
	-- seinen Bienenstock auf Level 5 stehen hat und die Presse auf Level 1,
	-- bekaeme ploetzlich 30 statt 135 XP pro Honig. Deshalb erbt die Presse
	-- einmalig das hoechste Level, das dieser Spielstand bei irgendeinem
	-- Gebaeude erreicht hatte. Danach ist die XP-Ausbeute mindestens so gut wie
	-- vorher, und niemand muss etwas nachkaufen.
	--
	-- DAS IST DIE ERSTE MIGRATION, DIE AN DER VERSIONSNUMMER HAENGEN MUSS
	-- (siehe den Kommentar bei data.version am Ende dieser Funktion): sie
	-- rechnet einen Wert um, statt ein fehlendes Feld anzulegen. Liefe sie bei
	-- jedem Join erneut, wuerde die Presse jedes Mal wieder auf das Maximum
	-- hochgezogen — der Spieler koennte die anderen beiden nie ueberholen.
	if (data.version or 0) < 7 then
		local press = island.buildings.HoneyPress

		if press then
			local highest = press.level or 1

			for _, building in island.buildings do
				highest = math.max(highest, building.level or 1)
			end

			press.level = highest
		end
	end

	-- v8: die zweite Fortschrittsachse (Promotion, Stat-Level, Charms).
	--
	-- Steht bewusst VOR der currentHp-Migration weiter unten: die rechnet mit
	-- CombatCalculator.getEffectiveStats, und das liest inzwischen genau diese
	-- Felder. Es kaeme auch ohne zurecht (es faengt fehlende Felder mit 0 ab),
	-- aber ein Spielstand soll die Migration nicht in halb fertigem Zustand
	-- durchlaufen — das ist die Art Reihenfolge-Abhaengigkeit, die man erst
	-- Monate spaeter bemerkt.
	--
	-- Erkennt fehlende Felder einzeln statt an der Versionsnummer und ist
	-- deshalb gefahrlos wiederholbar (dieselbe Konvention wie v2/v4/v5).
	for _, baerchi in island.baerchis do
		if baerchi.promotionLevel == nil then
			baerchi.promotionLevel = 0
		end

		if baerchi.statLevels == nil then
			baerchi.statLevels = PromotionConfig.newStatLevels()
		else
			-- Einzelne Stat-Schluessel nachruesten: `egg` kam als letzter dazu,
			-- und ein kuenftiger fuenfter Stat soll hier ebenfalls landen, ohne
			-- dass die ganze Tabelle ersetzt (und damit der Fortschritt
			-- geloescht) wird.
			local levels = baerchi.statLevels :: any
			for _, key in PromotionConfig.ALL_STATS do
				if levels[key] == nil then
					levels[key] = 0
				end
			end
		end

		if baerchi.charms == nil then
			baerchi.charms = {}
		else
			-- Nur gueltige Eintraege behalten. Ein Charm ohne Slot oder mit
			-- einem Stat-Typ, den es nicht mehr gibt (Pool-Aenderung), waere
			-- sonst ein stiller Rechenfehler in getEffectiveStats.
			local cleaned: { Types.Charm } = {}
			for _, charm in baerchi.charms do
				local slotOk = typeof(charm.slot) == "number"
					and charm.slot >= 1
					and charm.slot <= CharmConfig.SLOT_COUNT

				if slotOk and CharmConfig.getStatDef(charm.statId) then
					if charm.locked == nil then
						charm.locked = false
					end
					table.insert(cleaned, charm)
				end
			end
			table.sort(cleaned, function(a, b)
				return a.slot < b.slot
			end)
			baerchi.charms = cleaned
		end

		-- baseStatOverride bleibt absichtlich ungesetzt: nil heisst "Basiswerte
		-- kommen wie immer aus BaerchiConfig", und genau das gilt fuer jeden
		-- Baerchi, der vor dieser Version entstanden ist — auch fuer die
		-- damaligen Fusions-Ergebnisse (die haben ihren Vorteil ueber
		-- fusionBonus, nicht ueber die Basiswerte).

		-- ============================================================
		-- v9: DEF ist weg, PWR ist da, Inverted ist neu
		-- ============================================================
		-- Anders als alles darueber RAEUMT diese Migration etwas WEG. Ein
		-- statLevels.def oder ein baseStatOverride.def aus v8 zeigt auf einen
		-- Stat, den es nicht mehr gibt — stehen bleiben duerfte er trotzdem
		-- nicht: er landete beim naechsten Speichern wieder im DataStore und
		-- waere in einem Jahr ein Feld, das niemand mehr einordnen kann.
		--
		-- Der alte def-WERT wird NICHT in pwr uebertragen. Die beiden haben
		-- nichts miteinander zu tun (Schadensreduktion gegen Ability-Staerke),
		-- und ein Baerchi mit acht DEF-Stufen haette sonst still acht Stufen
		-- eines voellig anderen Stats geschenkt bekommen. pwr faengt bei 0 an.
		local statLevels = baerchi.statLevels :: any
		if statLevels.def ~= nil then
			statLevels.def = nil
		end
		if statLevels.pwr == nil then
			statLevels.pwr = 0
		end

		local override = baerchi.baseStatOverride :: any
		if override ~= nil then
			override.def = nil

			-- Ein Fusions-Ergebnis aus v8 hat einen gemischten Basiswert fuer
			-- hp/atk/spd, aber keinen fuer pwr (den Stat gab es noch nicht).
			-- nil ist hier genau richtig: getEffectiveStats faellt dann auf den
			-- pwr-Wert seines configId zurueck.
		end

		-- ============================================================
		-- v11: MUTATION-SYSTEM ERSETZT INVERTED
		-- ============================================================
		-- Das binaere isInverted-Feld weicht dem gestuften Mutation-System
		-- (siehe BaerchiConfig.MUTATIONS). Alte Spielstaende kannten hoechstens
		-- isInverted = true.
		--
		-- ANNAHME, nicht vom Projektinhaber vorgegeben: ein zuvor invertierter
		-- Baerchi wird auf die Mutation "Diamond" abgebildet (0.3% Wurf-Chance,
		-- damit nahe an der alten INVERTED_CHANCE von 0.5% — eine exakte
		-- Entsprechung gibt es nicht, weil das alte System nur eine einzige
		-- Stufe kannte). Wer eine andere Zuordnung will, ist das hier die
		-- einzige Stelle, die es aendern muss.
		--
		-- Erkennt das alte Feld selbst (ueber `any`, weil Types.Baerchi es seit
		-- v11 nicht mehr kennt) und ist deshalb gefahrlos wiederholbar: beim
		-- ersten Durchlauf wird das alte Feld entfernt, jeder weitere Durchlauf
		-- findet es dann bereits als nil vor und tut nichts mehr.
		local legacy = baerchi :: any
		if legacy.isInverted == true and baerchi.mutation == nil then
			baerchi.mutation = "Diamond"
		end
		legacy.isInverted = nil
	end

	-- v2: fusionBonus auf allen bestehenden Baerchis
	for _, baerchi in island.baerchis do
		if baerchi.fusionBonus == nil then
			baerchi.fusionBonus = 0
		end
		if baerchi.isFusionResult == nil then
			baerchi.isFusionResult = false
		end
	end

	-- v4: currentHp auf allen bestehenden Baerchis.
	-- Sie haben unter dem neuen System noch nicht gekaempft, starten also mit
	-- vollen HP. CombatCalculator wird dafuer bewusst hier requiret: es ist
	-- ein reines Rechenmodul ohne Zustand, und maxHp soll es nur EINE Formel
	-- im ganzen Projekt geben.
	for _, baerchi in island.baerchis do
		if baerchi.currentHp == nil then
			local baerchiDef = BaerchiConfig.getById(baerchi.configId)

			if baerchiDef then
				-- In pcall: getEffectiveStats rechnet mit level und
				-- fusionBonus. Fehlt einem uralten Eintrag eines davon, waere
				-- der Fehler sonst mitten im Join — und ein einziger kaputter
				-- Baerchi wuerde den ganzen Spielstand unbrauchbar machen.
				local ok, maxHp = pcall(function()
					return CombatCalculator.getEffectiveStats(baerchi, baerchiDef.baseStats).maxHp
				end)

				baerchi.currentHp = if ok then maxHp else 0
				if not ok then
					warn("[PlayerService] Kaputter Baerchi-Eintrag migriert:", baerchi.configId, maxHp)
				end
			else
				-- Unbekannter configId (Config-Eintrag entfernt): nicht raten,
				-- lieber erschoepft starten als mit erfundenen Werten.
				baerchi.currentHp = 0
			end
		end
	end

	-- Zum Schluss die Versionsnummer nachziehen. Sie steuert heute keine der
	-- Migrationen oben — die pruefen alle einzeln auf fehlende Felder und
	-- laufen deshalb harmlos bei jedem Laden. Sie ist trotzdem wichtig: sobald
	-- eine kuenftige Migration NICHT mehr am Feld erkennbar ist (weil sie zum
	-- Beispiel Werte umrechnet statt welche anzulegen), ist diese Zahl der
	-- einzige Weg, sie nicht bei jedem Join erneut auszufuehren. Wer
	-- Types.createDefaultPlayerData um ein Feld erweitert, erhoeht sie dort.
	data.version = default.version
	return data
end

-- Wie oft das Laden bei einem DataStore-Fehler erneut versucht wird, und wie
-- lange dazwischen gewartet wird (verdoppelt sich jedes Mal).
local LOAD_RETRIES     = 3
local LOAD_RETRY_DELAY = 2

local function loadFromDataStore(player: Player): (Types.PlayerData, boolean)
	local key   = storageKey(player)
	local store = getDataStore()

	-- Kein DataStore (unveroeffentlichter Place / Studio ohne API-Services):
	-- aus dem Sitzungs-Speicher lesen, damit Leave/Rejoin trotzdem testbar ist.
	if not store then
		local cached = _sessionStore[key]
		if cached then
			return applyDefaults(cached), true
		end
		return Types.createDefaultPlayerData(), true
	end

	-- Mehrfach versuchen: ein einzelner DataStore-Aussetzer (Drosselung,
	-- Roblox-Stoerung) ist haeufig und geht meist beim zweiten Versuch durch.
	local lastError: any = nil

	for attempt = 1, LOAD_RETRIES do
		local success, result = pcall(function()
			return store:GetAsync(key)
		end)

		if success then
			if result == nil then
				return Types.createDefaultPlayerData(), true   -- neuer Spieler
			end
			return applyDefaults(result), true
		end

		lastError = result
		if attempt < LOAD_RETRIES then
			task.wait(LOAD_RETRY_DELAY * attempt)
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

local function saveToDataStore(player: Player, data: Types.PlayerData)
	-- Konnte der Spielstand nicht geladen werden, wird auch nicht gespeichert.
	-- Siehe loadFromDataStore: sonst ueberschreibt eine Standard-Datei den
	-- echten Spielstand.
	if _noSave[player] then
		return
	end

	-- Zeitstempel VOR dem Schreiben setzen. SetAsync haelt den Thread an;
	-- stuende die Zeile darunter, wuerde die Auto-Save-Schleife waehrend des
	-- Wartens immer wieder dieselbe Bedingung erfuellen und dutzende
	-- gleichzeitige Schreibvorgaenge auf denselben Schluessel ausloesen.
	_lastSave[player] = os.time()
	data.lastSeenAt   = os.time()

	local key   = storageKey(player)
	local store = getDataStore()

	if store then
		local success, err = pcall(function()
			store:SetAsync(key, data)
		end)

		if not success then
			warn("[PlayerService] DataStore-Fehler beim Speichern fuer", player.Name, ":", err)
		end
	else
		_sessionStore[key] = data
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
		saveToDataStore(player, data)
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
-- rausgeht. Muss VOR PlayerService.init() aufgerufen werden, also aus dem
-- init() eines Services der im GameManager vorher steht.
function PlayerService.onDataLoaded(callback: (Player, Types.PlayerData) -> ())
	table.insert(_onDataLoaded, callback)
end

-- Registriert einen Callback der bei JEDER Datenaenderung laeuft (markDirty).
-- Wird oft aufgerufen — der Callback muss selbst entscheiden ob er wirklich
-- etwas tun muss, und darf nicht seinerseits markDirty aufrufen.
function PlayerService.onDataChanged(callback: (Player, Types.PlayerData) -> ())
	table.insert(_onDataChanged, callback)
end

--------------------------------------------------------------------------------
-- Join / Leave
--------------------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	if _loading[player] then return end
	_loading[player] = true

	-- Daten laden (kann einen Moment dauern).
	--
	-- Zusaetzlich in pcall: applyDefaults rechnet fuer die Migration alter
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

	-- Ersten Sync zum Client
	syncToClient(player)

	print("[PlayerService] Spieler geladen:", player.Name,
		"| Gummies:", data.gummies,
		"| Rebirths:", data.rebirthCount)
end

local function onPlayerRemoving(player: Player)
	local data = _playerData[player]
	if data then
		saveToDataStore(player, data)
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
-- Schreibvorgaenge aus, weil SetAsync den Thread anhaelt.
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

					local ok, err = pcall(saveToDataStore, player, data)
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

	-- Bereits verbundene Spieler (falls Script spaet laedt)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Sicherheitsnetz: beim Server-Shutdown alle speichern
	game:BindToClose(function()
		for player, data in _playerData do
			saveToDataStore(player, data)
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

return PlayerService
