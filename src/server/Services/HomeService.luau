--!strict
-- HomeService.luau
-- ServerScriptService/Services/HomeService.luau
--
-- Einzige Zustaendigkeit:
--   - Den Spieler auf Wunsch zurueck auf seinen eigenen Plot bringen
--     (RequestGoHome, Heim-Knopf)
--
-- Kontext: HBB Paket 5 (MAP_V2_HOME). Ziel ist die SpawnLocation des eigenen
-- Plots, die PlotBuilder anlegt und als Player.RespawnLocation setzt.
--
-- Wer Waben traegt, wird abgelehnt: sonst waere der Knopf eine Abkuerzung
-- vom Event-Pit direkt zum Recycler (Sofort-Abgabe). Die Zahl der
-- getragenen Waben liest dieser Service aus dem Attribut "CombsCarried",
-- das CombService pflegt — so braucht er CombService nicht zu requiren.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes      = require(ReplicatedStorage.Network.Remotes)
local Loc          = require(ReplicatedStorage.Localization.Loc)
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)

local RateLimiter = require(ServerScriptService.Util.RateLimiter)

local HomeService = {}

-- Hoehe ueber dem Spawn-Pad, damit der Charakter nicht im Boden steckt
local DROP_HEIGHT = 4

local function fail(player: Player, key: string)
	Remotes.ActionFailed:FireClient(player, "RequestGoHome", Loc.msg(key))
end

local function goHome(player: Player)
	if not FeatureFlags.isOn("MAP_V2_HOME") then return end

	local carried = player:GetAttribute("CombsCarried")
	if typeof(carried) == "number" and carried > 0 then
		fail(player, "err.home_carrying")
		return
	end

	local spawn = player.RespawnLocation
	local character = player.Character
	if not spawn or not character or not character.PrimaryPart then
		fail(player, "err.home_unavailable")
		return
	end

	character:PivotTo(spawn.CFrame + Vector3.new(0, DROP_HEIGHT, 0))
end

function HomeService.init()
	RateLimiter.connect(Remotes.RequestGoHome, "RequestGoHome", function(player)
		goHome(player)
	end)
end

return HomeService
