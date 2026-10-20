--!strict
-- DebugRegistry.luau
-- ServerScriptService/Debug/DebugRegistry.luau
--
-- Gemeinsame Befehlstabelle und Hilfsfunktionen der Debug-Module. Die
-- Befehlsmodule tragen sich beim require in `commands` ein; DebugService
-- ruft sie darueber auf. Nur in Studio geladen.

local Players = game:GetService("Players")

local Types         = require(game:GetService("ReplicatedStorage").Network.Types)
local PlayerService = require(game:GetService("ServerScriptService").Services.PlayerService)

local DebugRegistry = {}

export type Command = (Player, Types.PlayerData, ...any) -> any

DebugRegistry.commands = {} :: { [string]: Command }

-- Der erste Spieler im Server. Fuer Solo-Tests in Studio genau richtig.
function DebugRegistry.firstPlayer(): Player?
	return Players:GetPlayers()[1]
end

function DebugRegistry.requireData(): (Player?, Types.PlayerData?, string?)
	local player = DebugRegistry.firstPlayer()
	if not player then
		return nil, nil, "Kein Spieler im Spiel — laeuft der Play-Modus?"
	end

	local data = PlayerService.getData(player)
	if not data then
		return player, nil, "Daten fuer " .. player.Name .. " noch nicht geladen"
	end

	return player, data, nil
end

function DebugRegistry.countBaerchis(data: Types.PlayerData): number
	local n = 0
	for _ in data.island.baerchis do n += 1 end
	return n
end

return DebugRegistry
