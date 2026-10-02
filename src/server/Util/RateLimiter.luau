--!strict
-- RateLimiter.luau
-- ServerScriptService/Util/RateLimiter.luau
--
-- Einzige Zustaendigkeit:
--   - Cooldowns pro Spieler pro Remote durchsetzen
--   - Eine einheitliche Stelle an der Client-Requests entgegengenommen werden
--
-- Kein Service (kein init() im GameManager noetig ausser dem Cleanup-Hook) —
-- eine Utility die von jedem Service benutzt wird der ein Request*-Remote
-- entgegennimmt.
--
-- Benutzung in einem Service:
--   RateLimiter.connect(Remotes.RequestFoo, "RequestFoo", function(player, arg)
--       ...
--   end)
--
-- Damit ist es unmoeglich ein Remote zu verbinden und das Limit zu vergessen.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkConfig = require(ReplicatedStorage.Config.NetworkConfig)

local RateLimiter = {}

--------------------------------------------------------------------------------
-- Interner Zustand
--------------------------------------------------------------------------------

-- [Player][remoteName] = os.clock() des letzten akzeptierten Aufrufs
local _lastCall: { [Player]: { [string]: number } } = {}

-- [Player] = Anzahl bereits geloggter Verstoesse (Log-Flood-Schutz)
local _warnCount: { [Player]: number } = {}

--------------------------------------------------------------------------------
-- Oeffentliche API
--------------------------------------------------------------------------------

-- Prueft ob dieser Spieler dieses Remote gerade aufrufen darf.
-- Gibt true zurueck und merkt sich den Zeitpunkt, oder false bei Cooldown.
function RateLimiter.check(player: Player, remoteName: string): boolean
	local now      = os.clock()
	local cooldown = NetworkConfig.getCooldown(remoteName)

	local perPlayer = _lastCall[player]
	if not perPlayer then
		perPlayer = {}
		_lastCall[player] = perPlayer
	end

	local last = perPlayer[remoteName]
	if last and (now - last) < cooldown then
		local count = (_warnCount[player] or 0) + 1
		_warnCount[player] = count
		if count <= NetworkConfig.MAX_WARNINGS_PER_PLAYER then
			warn(
				"[RateLimiter] Zu schnell:", player.Name, "→", remoteName,
				string.format("(%.2fs von %.2fs)", now - last, cooldown)
			)
		end
		return false
	end

	perPlayer[remoteName] = now
	return true
end

-- Verbindet ein RemoteEvent mit einem Handler und schaltet das Limit davor.
-- Der Handler wird nur aufgerufen wenn der Cooldown eingehalten wurde.
function RateLimiter.connect(
	remote: RemoteEvent,
	remoteName: string,
	handler: (Player, ...any) -> ()
)
	remote.OnServerEvent:Connect(function(player: Player, ...)
		if not RateLimiter.check(player, remoteName) then
			return
		end
		handler(player, ...)
	end)
end

-- Dasselbe fuer RemoteFunctions. Bei Cooldown wird nil zurueckgegeben
-- statt den Handler aufzurufen.
function RateLimiter.connectFunction(
	remote: RemoteFunction,
	remoteName: string,
	handler: (Player, ...any) -> any
)
	remote.OnServerInvoke = function(player: Player, ...)
		if not RateLimiter.check(player, remoteName) then
			return nil
		end
		return handler(player, ...)
	end
end

-- Speicher freigeben wenn ein Spieler geht
function RateLimiter.clear(player: Player)
	_lastCall[player]  = nil
	_warnCount[player] = nil
end

function RateLimiter.init()
	Players.PlayerRemoving:Connect(RateLimiter.clear)
	print("[RateLimiter] Initialisiert")
end

return RateLimiter
