--!strict
-- ClientState.luau
-- StarterPlayerScripts/Controllers/ClientState.luau
--
-- Einzige Zustaendigkeit:
--   - Den letzten vom Server gesendeten Datenstand halten
--   - UI-Module benachrichtigen wenn er sich aendert
--
-- WICHTIG — die zentrale Regel des Clients:
--   Der Client hat KEINEN eigenen Wahrheitsstand. Er zeigt nur, was zuletzt
--   ueber PlayerDataUpdated hereinkam. Kein UI-Modul rechnet Gummies selbst
--   hoch, weil es gerade einen Kauf ausgeloest hat — es wartet auf den Server.
--   Dadurch kann die Anzeige nie dauerhaft von der Realitaet abweichen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes       = require(ReplicatedStorage.Network.Remotes)
local Types         = require(ReplicatedStorage.Network.Types)
local BaerchiConfig = require(ReplicatedStorage.Config.BaerchiConfig)

local ClientState = {}

local _data: Types.PlayerDataUpdate? = nil
local _listeners: { (Types.PlayerDataUpdate) -> () } = {}

--------------------------------------------------------------------------------
-- Lesen
--------------------------------------------------------------------------------

-- Aktueller Stand — nil solange der erste Sync nicht da ist
function ClientState.get(): Types.PlayerDataUpdate?
	return _data
end

function ClientState.getBaerchi(uid: string): Types.Baerchi?
	if not _data then return nil end
	return _data.island.baerchis[uid]
end

-- Alle Baerchis als sortierte Liste (Rarity absteigend, dann Level, dann uid)
function ClientState.getBaerchiList(): { Types.Baerchi }
	local list: { Types.Baerchi } = {}
	if not _data then return list end

	for _, baerchi in _data.island.baerchis do
		table.insert(list, baerchi)
	end

	table.sort(list, function(a, b)
		local ra = BaerchiConfig.getRarityIndex(a.rarity)
		local rb = BaerchiConfig.getRarityIndex(b.rarity)
		if ra ~= rb then return ra > rb end
		if a.level ~= b.level then return a.level > b.level end
		return a.uid < b.uid
	end)

	return list
end

--------------------------------------------------------------------------------
-- Beobachten
--------------------------------------------------------------------------------

-- Registriert einen Callback. Ist bereits ein Stand da, wird er sofort
-- einmal mit dem aktuellen Stand aufgerufen — dadurch muss kein UI-Modul
-- selbst unterscheiden ob es vor oder nach dem ersten Sync gestartet ist.
function ClientState.onChanged(callback: (Types.PlayerDataUpdate) -> ())
	table.insert(_listeners, callback)

	local current = _data
	if current then
		local ok, err = pcall(callback, current)
		if not ok then
			warn("[ClientState] Listener fehlgeschlagen:", err)
		end
	end
end

local function apply(update: Types.PlayerDataUpdate)
	_data = update

	for _, callback in _listeners do
		local ok, err = pcall(callback, update)
		if not ok then
			warn("[ClientState] Listener fehlgeschlagen:", err)
		end
	end
end

--------------------------------------------------------------------------------
-- Initialisierung
--------------------------------------------------------------------------------

function ClientState.init()
	Remotes.PlayerDataUpdated.OnClientEvent:Connect(function(update: any)
		if typeof(update) ~= "table" then return end
		apply(update :: Types.PlayerDataUpdate)
	end)

	-- Reconnect- und Startfall: der erste PlayerDataUpdated kann durch sein
	-- bevor dieses Skript ueberhaupt laeuft. Deshalb einmal aktiv nachfragen.
	task.spawn(function()
		local ok, result = pcall(function()
			return Remotes.GetPlayerData:InvokeServer()
		end)

		if not ok then
			warn("[ClientState] GetPlayerData fehlgeschlagen:", result)
			return
		end

		-- Nur uebernehmen wenn inzwischen nicht schon ein Update kam
		if result ~= nil and _data == nil then
			apply(result :: Types.PlayerDataUpdate)
		end
	end)

	print("[ClientState] Initialisiert")
end

return ClientState
