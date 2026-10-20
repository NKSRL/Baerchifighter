--!strict
-- WorldService.luau
-- ServerScriptService/Services/WorldService.luau
--
-- Einzige Zustaendigkeit (Prompt 6 von 7, Final-Epilog): Auskunft, welche Welten ein
-- Spieler freigeschaltet hat. NUR LESEN: geschrieben wird `worlds.unlocked.World2`
-- ausschliesslich von EpilogRules.applyLaunch (ueber EpilogService nach dem Knopfdruck).
-- Der Zugang zu Welt 2 (Betreten) haengt spaeter hier dran; es gibt noch keinen Teleport.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local EpilogConfig = require(ReplicatedStorage.Config.EpilogConfig)
local PlayerService = require(ServerScriptService.Services.PlayerService)

local WorldService = {}

-- worldId: "World2" (EpilogConfig.WORLD2_ID). Unbekannte Ids sind nie frei.
function WorldService.isUnlocked(player: Player, worldId: string): boolean
	local data = PlayerService.getData(player)
	if not data then return false end
	local worlds = (data :: any).worlds
	if typeof(worlds) ~= "table" or typeof(worlds.unlocked) ~= "table" then return false end
	return worlds.unlocked[worldId] == true
end

function WorldService.isWorld2Unlocked(player: Player): boolean
	return WorldService.isUnlocked(player, EpilogConfig.WORLD2_ID)
end

return WorldService
