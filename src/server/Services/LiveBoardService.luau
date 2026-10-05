--!strict
-- LiveBoardService.luau
-- ServerScriptService/Services/LiveBoardService.luau
--
-- Einzige Zustaendigkeit:
--   - Das Live-Kampf-Board auf der Hauptinsel aktuell halten (HBB Paket 6,
--     FeatureFlags.MAP_V2_LIVE_BOARD): wer kaempft gerade wo?
--
-- Liest nur: PitArenaService.liveRuns() (laufende Laeufe), schreibt nur ueber
-- MapService.writeLiveBoard. Den Text baut Modules/LiveBoardText (getestet).
-- Geschrieben wird nur bei Aenderung — sonst jede Sekunde dieselben Texte
-- an alle Clients replizieren.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MapConfig     = require(ReplicatedStorage.Config.MapConfig)
local FeatureFlags  = require(ReplicatedStorage.Config.FeatureFlags)
local LiveBoardText = require(ReplicatedStorage.Modules.LiveBoardText)

local MapService      = require(ServerScriptService.Services.MapService)
local PitArenaService = require(ServerScriptService.Services.PitArenaService)

local LiveBoardService = {}

local _lastSignature = ""

local function refresh()
	local cfg = MapConfig.LIVE_BOARD
	local title, lines, live = LiveBoardText.build(PitArenaService.liveRuns(), cfg.lines)
	local signature = title .. "\n" .. table.concat(lines, "\n")
	if signature == _lastSignature then return end
	_lastSignature = signature
	MapService.writeLiveBoard(title, lines, live)
end

function LiveBoardService.init()
	print("[LiveBoardService] Initialisiert | aktiv:", FeatureFlags.isOn("MAP_V2_LIVE_BOARD"))
end

function LiveBoardService.start()
	if not FeatureFlags.isOn("MAP_V2_LIVE_BOARD") then return end
	task.spawn(function()
		while true do
			local ok, err = pcall(refresh)
			if not ok then
				warn("[LiveBoardService] Aktualisierung fehlgeschlagen:", err)
			end
			task.wait(MapConfig.LIVE_BOARD.refreshSeconds)
		end
	end)
end

return LiveBoardService
