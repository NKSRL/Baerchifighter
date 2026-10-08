--!strict
-- GamepassService.luau
-- ServerScriptService/Services/GamepassService.luau
--
-- Einzige Zustaendigkeit:
--   - Gamepass-Besitz pruefen und im Speicher halten (08.10., Paket C):
--     beim Join und nach PromptGamePassPurchaseFinished
--     (MarketplaceService.UserOwnsGamePassAsync, mit pcall); den Kauf-Dialog
--     ausloesen (RequestBuyGamepass).
--
-- Besitz steht NICHT im Spielstand (Roblox ist die Wahrheit). Fuer die
-- Anzeige schreibt der Service ein Attribut an den Player
-- (GamepassConfig.attributeName); Kosten rechnet nur der Server mit
-- GamepassService.owns (z. B. CombatService beim bezahlten Einstieg).
--
-- id = 0 (nicht angelegt): niemand besitzt den Pass, ein Kaufwunsch wird
-- still verworfen (der Knopf zeigt "Bald") — kein Fehler, kein Crash.
-- Studio: Debug "pass <KEY> on|off" setzt den Besitz fuer diese Sitzung.

local Players            = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes        = require(ReplicatedStorage.Network.Remotes)
local GamepassConfig = require(ReplicatedStorage.Config.GamepassConfig)
local RateLimiter    = require(ServerScriptService.Util.RateLimiter)

local GamepassService = {}

-- Spieler -> Pass-Key -> Besitz (aus Roblox)
local _owned: { [Player]: { [string]: boolean } } = {}
-- Debug-Uebersteuerung (nur Studio): Spieler -> Key -> Besitz
local _debug: { [Player]: { [string]: boolean } } = {}

local function publish(player: Player, key: string)
	player:SetAttribute(GamepassConfig.attributeName(key), GamepassService.owns(player, key))
end

-- Besitz eines Passes (Debug vor Roblox). Nie ein Fehler.
function GamepassService.owns(player: Player, key: string): boolean
	local forced = _debug[player]
	if forced and forced[key] ~= nil then
		return forced[key]
	end
	local owned = _owned[player]
	return owned ~= nil and owned[key] == true
end

-- Fragt Roblox fuer alle angelegten Passes (pcall: der Dienst kann ausfallen,
-- dann bleibt der bekannte Stand bzw. "nicht besessen").
function GamepassService.refresh(player: Player)
	local owned = _owned[player] or {}
	_owned[player] = owned
	for key, def in GamepassConfig.PASSES do
		if def.id > 0 then
			local ok, result = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, def.id)
			end)
			if ok then
				owned[key] = result == true
			else
				warn("[GamepassService] Besitz nicht pruefbar:", player.Name, key, result)
			end
		else
			owned[key] = false
		end
		publish(player, key)
	end
end

-- Debug (Studio): Besitz fuer diese Sitzung erzwingen; nil = wieder Roblox.
function GamepassService.debugSet(player: Player, key: string, value: boolean?)
	local forced = _debug[player] or {}
	_debug[player] = forced
	forced[key] = value
	publish(player, key)
end

local function keyForId(passId: number): string?
	for key, def in GamepassConfig.PASSES do
		if def.id > 0 and def.id == passId then return key end
	end
	return nil
end

function GamepassService.init()
	RateLimiter.connect(Remotes.RequestBuyGamepass, "RequestBuyGamepass", function(player, key: any)
		if typeof(key) ~= "string" then return end
		local def = GamepassConfig.get(key)
		if not def or def.id <= 0 then return end          -- "Bald": still verwerfen
		if GamepassService.owns(player, key) then return end
		local ok, err = pcall(function()
			MarketplaceService:PromptGamePassPurchase(player, def.id)
		end)
		if not ok then warn("[GamepassService] Kauf-Dialog fehlgeschlagen:", err) end
	end)

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
		local key = keyForId(passId)
		if not key or not purchased then return end
		local owned = _owned[player] or {}
		_owned[player] = owned
		owned[key] = true
		publish(player, key)
		print("[GamepassService]", player.Name, "hat gekauft:", key)
	end)

	Players.PlayerRemoving:Connect(function(player)
		_owned[player] = nil
		_debug[player] = nil
	end)

	print("[GamepassService] Initialisiert")
end

function GamepassService.start()
	for _, player in Players:GetPlayers() do
		task.spawn(GamepassService.refresh, player)
	end
	Players.PlayerAdded:Connect(function(player)
		GamepassService.refresh(player)
	end)
end

return GamepassService
