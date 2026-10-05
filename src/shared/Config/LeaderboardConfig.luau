--!strict
-- LeaderboardConfig.luau
-- ReplicatedStorage/Config/LeaderboardConfig.luau
--
-- Einzige Zustaendigkeit:
--   - Die Zahlen der Bestenlisten (v15): welche Listen, wie viele Plaetze, wie
--     oft geschrieben und gelesen wird, wie oft die Tafel am Spawn umschaltet.
--
-- Benutzt von LeaderboardService (einziger Nutzer von OrderedDataStores) und
-- vom LeaderboardPanel (Anzeige). Die Werte je Liste rechnet LeaderboardService
-- aus dem Spielstand:
--   Tower       Tower-Index x 1000 + Rekord (TowerConfig.leaderboardValue)
--   Rebirths    rebirthCount
--   Collection  Anzahl Index-Eintraege (data.discovered)
--   Endless     Endless-Rekord (Paket 9, FeatureFlags.ENDLESS)
--   EndlessWeek beste Endless-Stage dieser Woche (Montag 00:00 UTC neu),
--               ein OrderedDataStore je Woche (storeName)

local FeatureFlags = require(script.Parent.FeatureFlags)

local LeaderboardConfig = {}

export type ListId = "Tower" | "Rebirths" | "Collection" | "Endless" | "EndlessWeek"

LeaderboardConfig.LISTS = { "Tower", "Rebirths", "Collection" } :: { ListId }
if FeatureFlags.isOn("ENDLESS") then
	table.insert(LeaderboardConfig.LISTS, "Endless")
	table.insert(LeaderboardConfig.LISTS, "EndlessWeek")
end

-- Name des OrderedDataStores je Liste. Versions-Suffix, damit eine spaetere
-- Umstellung der Wertformel mit leeren Listen startet statt mit Altwerten.
LeaderboardConfig.STORE_NAMES = {
	Tower      = "LB_Tower_v1",
	Rebirths   = "LB_Rebirths_v1",
	Collection = "LB_Collection_v1",
	Endless    = "LB_Endless_v1",
	EndlessWeek = "LB_EndlessWeek_v1_W",   -- + Wochennummer (storeName)
} :: { [string]: string }

-- Paket 9: Wochen. Woche 0 begann Montag, 05.01.1970 00:00 UTC (os.time 0
-- ist ein Donnerstag, +4 Tage).
LeaderboardConfig.WEEK_SECONDS = 7 * 86400
LeaderboardConfig.WEEK_START   = 4 * 86400
-- So viele der Vorwoche tragen diese Woche die Krone am Plot-Schild.
LeaderboardConfig.CROWN_TOP_N  = 10

function LeaderboardConfig.weekOf(now: number): number
	return (now - LeaderboardConfig.WEEK_START) // LeaderboardConfig.WEEK_SECONDS
end

function LeaderboardConfig.secondsUntilNextWeek(now: number): number
	local week = LeaderboardConfig.weekOf(now)
	return LeaderboardConfig.WEEK_START + (week + 1) * LeaderboardConfig.WEEK_SECONDS - now
end

-- Name des OrderedDataStores einer Liste (`week` nur fuer EndlessWeek).
function LeaderboardConfig.storeName(listId: string, week: number): string
	local base = LeaderboardConfig.STORE_NAMES[listId]
	return if listId == "EndlessWeek" then base .. tostring(week) else base
end

LeaderboardConfig.TOP_N        = 50   -- Plaetze im Panel
LeaderboardConfig.BOARD_TOP_N  = 10   -- Plaetze auf der Tafel am Spawn

-- Schreiben: nur bei Aenderung und hoechstens alle WRITE_MIN_SECONDS pro Spieler.
LeaderboardConfig.WRITE_MIN_SECONDS = 60
-- Lesen: serverweit hoechstens alle READ_INTERVAL_SECONDS (Cache dazwischen).
LeaderboardConfig.READ_INTERVAL_SECONDS = 120
-- Takt, in dem faellige Schreibvorgaenge abgearbeitet werden.
LeaderboardConfig.TICK_SECONDS = 10
-- Tafel am Spawn: alle BOARD_CYCLE_SECONDS die naechste Liste.
LeaderboardConfig.BOARD_CYCLE_SECONDS = 15

-- Unter diesem Rest-Budget wird nicht geschrieben/gelesen (fuer den
-- Spieler-DataStore muss Luft bleiben).
LeaderboardConfig.MIN_REQUEST_BUDGET = 4

return LeaderboardConfig
