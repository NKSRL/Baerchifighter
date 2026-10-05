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

local LeaderboardConfig = {}

export type ListId = "Tower" | "Rebirths" | "Collection"

LeaderboardConfig.LISTS = { "Tower", "Rebirths", "Collection" } :: { ListId }

-- Name des OrderedDataStores je Liste. Versions-Suffix, damit eine spaetere
-- Umstellung der Wertformel mit leeren Listen startet statt mit Altwerten.
LeaderboardConfig.STORE_NAMES = {
	Tower      = "LB_Tower_v1",
	Rebirths   = "LB_Rebirths_v1",
	Collection = "LB_Collection_v1",
} :: { [string]: string }

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
