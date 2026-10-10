--!strict
-- WorldMomentService.luau
-- ServerScriptService/Services/WorldMomentService.luau
--
-- Einzige Zustaendigkeit:
--   - Grosse Momente eines Spielers (seltener Baerchi, neuer Tower, Rekord,
--     Rebirth, seltene Mutation) an ALLE Clients melden (Paket G, "Welt
--     aufwerten"), gedrosselt auf einen grossen Moment je Spieler und 30 s
--
-- Erkannt wird aus dem Spielstand (Modules/WorldMoments.diff): dieser
-- Service haengt an PlayerService.onDataChanged und vergleicht mit dem
-- letzten Stand. So muss kein anderer Service angefasst werden, und kein
-- Moment geht verloren, egal welcher Weg (Ei, Fusion, Event) ihn ausloest.
--
-- Was die Clients daraus machen (Lichtsaeule, Feuerwerk, Welle ...),
-- entscheidet WorldMomentController. Der Server schickt nur Art, Wert und
-- gross/klein. Ein Spieler, dessen Momente zu dicht kommen, sendet weiter,
-- aber als kleine Version (WorldMoments.throttle).

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types        = require(ReplicatedStorage.Network.Types)
local Remotes      = require(ReplicatedStorage.Network.Remotes)
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)
local WorldMoments = require(ReplicatedStorage.Modules.WorldMoments)

local PlayerService = require(ServerScriptService.Services.PlayerService)

local WorldMomentService = {}

local _snapshots: { [Player]: WorldMoments.Snapshot } = {}
local _lastBig: { [Player]: number } = {}

-- Meldet einen Moment an alle (auch fuer den Debug-Befehl "moment").
function WorldMomentService.announce(player: Player, moment: WorldMoments.Moment, forceBig: boolean?)
	local big, last = WorldMoments.throttle(_lastBig[player], os.clock())
	if forceBig then big, last = true, os.clock() end
	_lastBig[player] = last
	Remotes.WorldMoment:FireAllClients({
		userId = player.UserId,
		kind   = moment.kind,
		value  = moment.value,
		number = moment.number,
		big    = big,
	})
end

local function onChanged(player: Player, data: Types.PlayerData)
	local after = WorldMoments.snapshot(data)
	local before = _snapshots[player]
	_snapshots[player] = after
	if not before then return end
	for _, moment in WorldMoments.diff(before, after) do
		WorldMomentService.announce(player, moment)
	end
end

function WorldMomentService.init()
	if not FeatureFlags.isOn("WORLD_G_MOMENTS") then return end

	-- Ausgangsstand beim Laden: was schon da war, ist kein neuer Moment
	PlayerService.onPlayerReady(function(player, data)
		_snapshots[player] = WorldMoments.snapshot(data)
	end)
	PlayerService.onDataChanged(onChanged)
	Players.PlayerRemoving:Connect(function(player)
		_snapshots[player] = nil
		_lastBig[player] = nil
	end)

	print("[WorldMomentService] Initialisiert")
end

return WorldMomentService
