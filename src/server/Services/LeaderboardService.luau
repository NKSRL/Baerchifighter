--!strict
-- LeaderboardService.luau
-- ServerScriptService/Services/LeaderboardService.luau
--
-- Einzige Zustaendigkeit:
--   - Die Bestenlisten (v15): Tower, Rebirths, Sammlung; mit Paket 9 auch
--     Endless und Endless-Woche. Werte schreiben (gedrosselt), Top-Listen
--     lesen (gecacht), dem Client auf Anfrage geben, die Tafeln beschriften
--     und die Top 10 der Vorwoche kroenen (Plot-Schild, MapService).
--
-- REGEL (seit v15, steht auch im Briefing): dieser Service ist der EINZIGE, der
-- OrderedDataStores benutzt — so wie PlayerService der einzige mit dem
-- Spieler-DataStore ist. Kein anderer Service fasst DataStoreService an.
--
-- Budget: Schreiben nur bei Aenderung und hoechstens alle WRITE_MIN_SECONDS pro
-- Spieler, Lesen serverweit alle READ_INTERVAL_SECONDS. Jeder Zugriff laeuft in
-- pcall und erst nach einer Budget-Pruefung (GetRequestBudgetForRequestType);
-- ist das Budget knapp, wird verschoben statt riskiert.
--
-- Ohne DataStore (Studio ohne API-Zugriff, unveroeffentlichter Place) gibt es
-- eine Sitzungsliste: die Werte aller Spieler, die in dieser Sitzung auf dem
-- Server waren. Das Spiel bleibt so vollstaendig testbar.

local Players             = game:GetService("Players")
local DataStoreService    = game:GetService("DataStoreService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types             = require(ReplicatedStorage.Network.Types)
local Remotes           = require(ReplicatedStorage.Network.Remotes)
local LeaderboardConfig = require(ReplicatedStorage.Config.LeaderboardConfig)
local TowerConfig       = require(ReplicatedStorage.Config.TowerConfig)

local PlayerService = require(ServerScriptService.Services.PlayerService)
local MapService    = require(ServerScriptService.Services.MapService)
local RateLimiter   = require(ServerScriptService.Util.RateLimiter)

local LeaderboardService = {}

type Entry = Types.LeaderboardEntry

-- Gelesener Stand je Liste (Top N) und Zeitpunkt.
local _cache: { [string]: { entries: { Entry }, updatedAt: number } } = {}

-- Pro Spieler: zuletzt geschriebene Werte und Zeitpunkt.
local _written: { [number]: { [string]: number } } = {}
local _lastWriteAt: { [number]: number } = {}

-- Sitzungsliste (ohne DataStore) und Namens-Cache.
local _session: { [string]: { [number]: number } } = {}
local _names: { [number]: string } = {}

-- Nach Store-NAME (EndlessWeek hat jede Woche einen neuen).
local _stores: { [string]: OrderedDataStore } = {}
local _storesChecked = false
local _storesOk = false

local _lastRead = 0
local _boardIndex = 0

-- Paket 9: Krone = Top CROWN_TOP_N der Vorwoche. `_crownWeek` = fuer welche
-- (laufende) Woche `_crowned` gilt; nil = noch nicht gelesen.
local _crowned: { [number]: boolean } = {}
local _crownWeek: number? = nil

--------------------------------------------------------------------------------
-- Werte
--------------------------------------------------------------------------------

local function countKeys(t: { [string]: any }?): number
	local n = 0
	for _ in t or {} do n += 1 end
	return n
end

-- Wert eines Spielers in einer Liste (ganze Zahl, OrderedDataStore-tauglich).
function LeaderboardService.valueOf(data: Types.PlayerData, listId: string): number
	if listId == "Tower" then
		local towerId, record = TowerConfig.bestRecord(data.towers)
		if record <= 0 then return 0 end
		return TowerConfig.leaderboardValue(towerId, record)
	elseif listId == "Rebirths" then
		return math.max(0, math.floor(data.rebirthCount))
	elseif listId == "Collection" then
		return countKeys(data.discovered)
	elseif listId == "Endless" then
		return math.max(0, math.floor(data.towers.records.Endless or 0))
	elseif listId == "EndlessWeek" then
		local entry = data.towers.endlessWeek
		if entry and entry.week == LeaderboardConfig.weekOf(os.time()) then
			return math.max(0, math.floor(entry.best))
		end
		return 0
	end
	return 0
end

--------------------------------------------------------------------------------
-- DataStore (nur hier!)
--------------------------------------------------------------------------------

local function currentStoreName(listId: string): string
	return LeaderboardConfig.storeName(listId, LeaderboardConfig.weekOf(os.time()))
end

-- Store nach Namen (einmal geholt, dann gecacht). nil = nicht verfuegbar.
local function storeByName(name: string): OrderedDataStore?
	local store = _stores[name]
	if store then return store end
	local ok, result = pcall(function()
		return DataStoreService:GetOrderedDataStore(name)
	end)
	if not ok then return nil end
	_stores[name] = result
	return result
end

local function getStores(): boolean
	if _storesChecked then return _storesOk end
	_storesChecked = true
	local ok, err = pcall(function()
		for _, listId in LeaderboardConfig.LISTS do
			local name = currentStoreName(listId)
			_stores[name] = DataStoreService:GetOrderedDataStore(name)
		end
	end)
	_storesOk = ok
	if not ok then
		warn("[LeaderboardService] Keine OrderedDataStores — Sitzungsliste. Grund:", err)
	end
	return ok
end

local function hasBudget(requestType: Enum.DataStoreRequestType): boolean
	local ok, budget = pcall(function()
		return DataStoreService:GetRequestBudgetForRequestType(requestType)
	end)
	return ok and (budget :: number) >= LeaderboardConfig.MIN_REQUEST_BUDGET
end

local function nameOf(userId: number): string
	local cached = _names[userId]
	if cached then return cached end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		_names[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and typeof(name) == "string" then name else ("#" .. userId)
	_names[userId] = result
	return result
end

--------------------------------------------------------------------------------
-- Schreiben
--------------------------------------------------------------------------------

-- Schreibt die geaenderten Werte eines Spielers (gedrosselt, ausser `force`).
local function writePlayer(player: Player, force: boolean)
	local data = PlayerService.getData(player)
	if not data then return end
	local userId = player.UserId
	_names[userId] = player.DisplayName

	local now = os.clock()
	if not force and now - (_lastWriteAt[userId] or -math.huge) < LeaderboardConfig.WRITE_MIN_SECONDS then
		return
	end

	local written = _written[userId] or {}
	_written[userId] = written
	local changed = false

	for _, listId in LeaderboardConfig.LISTS do
		local value = LeaderboardService.valueOf(data, listId)
		-- Nach Store-Namen gemerkt: in einer neuen Woche wird neu geschrieben.
		local name = currentStoreName(listId)

		-- Sitzungsliste immer pflegen (Studio-Ersatz und Fallback). Die
		-- Wochenliste beginnt zum Wochenwechsel leer.
		local session = _session[name] or {}
		_session[name] = session
		session[userId] = value

		if written[name] ~= value then
			if getStores() then
				local store = storeByName(name)
				if store and hasBudget(Enum.DataStoreRequestType.SetIncrementSortedAsync) then
					local ok, err = pcall(function()
						store:SetAsync(tostring(userId), value)
					end)
					if ok then
						written[name] = value
						changed = true
					else
						-- Studio ohne API-Zugriff: GetOrderedDataStore klappt, jeder
						-- Zugriff scheitert. Einmal melden, dann Sitzungsliste.
						warn("[LeaderboardService] Schreiben fehlgeschlagen — ab jetzt Sitzungsliste:", listId, err)
						_storesOk = false
					end
				end
			else
				written[name] = value
				changed = true
			end
		end
	end

	if changed then
		_lastWriteAt[userId] = now
	end
end

--------------------------------------------------------------------------------
-- Lesen
--------------------------------------------------------------------------------

local function sessionTop(listId: string): { Entry }
	local rows: { { userId: number, value: number } } = {}
	for userId, value in _session[currentStoreName(listId)] or {} do
		if value > 0 then
			table.insert(rows, { userId = userId, value = value })
		end
	end
	table.sort(rows, function(a, b)
		if a.value ~= b.value then return a.value > b.value end
		return a.userId < b.userId
	end)
	local entries: { Entry } = {}
	for rank, row in rows do
		if rank > LeaderboardConfig.TOP_N then break end
		table.insert(entries, { rank = rank, userId = row.userId, name = nameOf(row.userId), value = row.value })
	end
	return entries
end

-- Liest die Top `count` eines Stores. nil = gerade nicht moeglich.
local function readStore(name: string, count: number): { Entry }?
	if not hasBudget(Enum.DataStoreRequestType.GetSortedAsync) then
		return nil
	end
	local store = storeByName(name)
	if not store then return nil end
	local ok, result = pcall(function()
		local pages = store:GetSortedAsync(false, count)
		return pages:GetCurrentPage()
	end)
	if not ok then
		warn("[LeaderboardService] Lesen fehlgeschlagen — ab jetzt Sitzungsliste:", name, result)
		_storesOk = false
		return nil
	end
	local entries: { Entry } = {}
	for _, item in result :: { any } do
		local userId = tonumber(item.key)
		local value = tonumber(item.value) or 0
		-- Paket 9: Nullen (z. B. Endless noch nicht offen) stehen nicht in der Liste.
		if userId and value > 0 then
			table.insert(entries, { rank = #entries + 1, userId = userId, name = nameOf(userId), value = value })
		end
	end
	return entries
end

local function readList(listId: string): { Entry }?
	if not getStores() then
		return sessionTop(listId)
	end
	local entries = readStore(currentStoreName(listId), LeaderboardConfig.TOP_N)
	if entries == nil and not _storesOk then
		return sessionTop(listId)
	end
	return entries
end

-- Paket 9: Krone fuer die Top 10 der VORWOCHE (eine Woche lang). Ohne
-- DataStore (Studio) gibt es keine Vorwoche — dann kroenen die Top 10 der
-- laufenden Sitzungsliste, damit sich das testen laesst.
local function applyCrowns()
	for _, player in Players:GetPlayers() do
		MapService.setOwnerCrown(player, _crowned[player.UserId] == true)
	end
end

local function refreshCrowns()
	if not table.find(LeaderboardConfig.LISTS, "EndlessWeek") then return end
	local week = LeaderboardConfig.weekOf(os.time())
	local entries: { Entry }?
	if getStores() then
		if _crownWeek == week then return end
		entries = readStore(LeaderboardConfig.storeName("EndlessWeek", week - 1), LeaderboardConfig.CROWN_TOP_N)
	end
	if entries == nil and not (getStores() and _storesOk) then
		entries = sessionTop("EndlessWeek")
	end
	if entries == nil then return end   -- spaeter nochmal versuchen

	_crowned = {}
	for _, entry in entries do
		if entry.rank <= LeaderboardConfig.CROWN_TOP_N then
			_crowned[entry.userId] = true
		end
	end
	_crownWeek = week
	applyCrowns()
end

local function refreshAll()
	_lastRead = os.clock()
	for _, listId in LeaderboardConfig.LISTS do
		local entries = readList(listId)
		if entries then
			_cache[listId] = { entries = entries, updatedAt = os.time() }
		end
	end
	refreshCrowns()
end

function LeaderboardService.isCrowned(userId: number): boolean
	return _crowned[userId] == true
end

--------------------------------------------------------------------------------
-- Anzeige
--------------------------------------------------------------------------------

-- Wert fuer die Anzeige ("Tower III · 42", "17", "23/28").
function LeaderboardService.formatValue(listId: string, value: number): string
	if listId == "Tower" then
		local towerId, stage = TowerConfig.fromLeaderboardValue(value)
		local def = TowerConfig.get(towerId) or TowerConfig.TOWERS[1]
		return string.format("Tower %s · %d", def.numeral, stage)
	elseif listId == "Endless" or listId == "EndlessWeek" then
		return string.format("∞ · %d", value)
	end
	return tostring(value)
end

local BOARD_TITLES: { [string]: string } = {
	Tower      = "TOP 10  ·  TOWER",
	Rebirths   = "TOP 10  ·  REBIRTHS",
	Collection = "TOP 10  ·  INDEX",
	Endless    = "TOP 10  ·  ENDLESS ∞",
	EndlessWeek = "TOP 10  ·  ∞ WEEK  ·  ♛",
}

local function paintList(listId: string)
	local cached = _cache[listId]
	local lines: { string } = {}
	for _, entry in (if cached then cached.entries else {}) do
		if entry.rank > LeaderboardConfig.BOARD_TOP_N then break end
		table.insert(lines, string.format("%2d.  %s   —   %s", entry.rank, entry.name, LeaderboardService.formatValue(listId, entry.value)))
	end
	MapService.writeLeaderboardBoard(BOARD_TITLES[listId] or listId, lines, listId)
end

-- HBB Paket 5: Hat jede Liste ihre feste Tafel, werden alle beschrieben;
-- sonst wechselt die eine Tafel reihum (v15).
local function paintBoard()
	if MapService.hasLeaderboardBoard(LeaderboardConfig.LISTS[1]) then
		for _, listId in LeaderboardConfig.LISTS do
			-- Paket 9: eine Liste ohne eigene Tafel landete sonst auf der
			-- wechselnden (die es dann nicht gibt) — einfach auslassen.
			if MapService.hasLeaderboardBoard(listId) then
				paintList(listId)
			end
		end
		return
	end
	_boardIndex = (_boardIndex % #LeaderboardConfig.LISTS) + 1
	paintList(LeaderboardConfig.LISTS[_boardIndex])
end

-- Die Sicht eines Spielers auf eine Liste (Top N + eigener Rang).
function LeaderboardService.getView(player: Player, listId: string): Types.LeaderboardView?
	if not table.find(LeaderboardConfig.LISTS, listId :: any) then return nil end
	local cached = _cache[listId]
	local entries = if cached then cached.entries else {}
	local data = PlayerService.getData(player)
	local ownValue = if data then LeaderboardService.valueOf(data, listId) else 0
	local ownRank: number? = nil
	for _, entry in entries do
		if entry.userId == player.UserId then
			ownRank = entry.rank
			break
		end
	end
	return {
		listId    = listId,
		entries   = entries,
		ownRank   = ownRank,
		ownValue  = ownValue,
		updatedAt = if cached then cached.updatedAt else 0,
	}
end

-- Debug ("lbflush"): alle sofort schreiben und neu lesen.
function LeaderboardService.flush(): { [string]: number }
	for _, player in Players:GetPlayers() do
		writePlayer(player, true)
	end
	refreshAll()
	paintBoard()
	local counts: { [string]: number } = {}
	for listId, cached in _cache do
		counts[listId] = #cached.entries
	end
	return counts
end

--------------------------------------------------------------------------------
-- Initialisierung
--------------------------------------------------------------------------------

function LeaderboardService.init()
	RateLimiter.connectFunction(Remotes.GetLeaderboard, "GetLeaderboard", function(player, listId: any)
		if typeof(listId) ~= "string" then return nil end
		return LeaderboardService.getView(player, listId)
	end)

	-- Beim Verlassen zuletzt noch schreiben (ungedrosselt, wenn sich etwas
	-- geaendert hat). Laeuft vor dem Speichern, darf aber nicht yielden — daher
	-- abgekoppelt.
	PlayerService.onPlayerLeaving(function(player, _data)
		task.spawn(writePlayer, player, true)
	end)

	-- Paket 9: Krone gleich beim Betreten, nicht erst beim naechsten Lesen.
	PlayerService.onPlayerReady(function(player, _data)
		MapService.setOwnerCrown(player, _crowned[player.UserId] == true)
	end)

	Players.PlayerRemoving:Connect(function(player)
		_lastWriteAt[player.UserId] = nil
		_written[player.UserId] = nil
	end)

	print("[LeaderboardService] Initialisiert |", #LeaderboardConfig.LISTS, "Listen")
end

function LeaderboardService.start()
	task.spawn(function()
		while true do
			task.wait(LeaderboardConfig.BOARD_CYCLE_SECONDS)
			local ok, err = pcall(paintBoard)
			if not ok then
				warn("[LeaderboardService] Tafel fehlgeschlagen:", err)
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(LeaderboardConfig.TICK_SECONDS)
			local ok, err = pcall(function()
				for _, player in Players:GetPlayers() do
					writePlayer(player, false)
				end
				if os.clock() - _lastRead >= LeaderboardConfig.READ_INTERVAL_SECONDS or next(_cache) == nil then
					refreshAll()
				end
			end)
			if not ok then
				warn("[LeaderboardService] Takt fehlgeschlagen:", err)
			end
		end
	end)
end

return LeaderboardService
