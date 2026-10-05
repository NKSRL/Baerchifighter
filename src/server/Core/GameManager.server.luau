--!strict
-- GameManager.server.luau
-- ServerScriptService/Core/GameManager.server.luau
--
-- Einzige Zustaendigkeit:
--   - Alle Services laden und in drei Phasen starten
--
-- Kein anderes Skript startet Services. Die drei Phasen:
--   1. laden   alle Module per require — danach existiert jedes Modul
--   2. init()  jeder Service richtet sich ein: Remotes verbinden, Rueckrufe
--              bei anderen Services anmelden (onDataLoaded, onEventEnded ...)
--   3. start() erst jetzt passiert etwas mit Spielern oder Zeit: PlayerService
--              laedt verbundene Spieler, EventService startet den Zyklus
--
-- Weil kein Service in init() schon Spieler verarbeitet, ist die Reihenfolge
-- in REGISTRY beliebig: jeder Rueckruf ist angemeldet, bevor der erste
-- Spieler geladen wird. Ein neuer Service traegt sich irgendwo ein und
-- verschiebt Arbeit mit Spielern in ein start().

local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService          = game:GetService("RunService")

-- ALLERERSTE Zeile mit Wirkung, bevor irgendein Service laedt: kein Spieler
-- soll automatisch in der Weltmitte landen. Stattdessen spawnt PlayerService
-- jeden Spieler explizit auf seiner eigenen Insel (player:LoadCharacter(),
-- erst NACHDEM MapService.spawnIsland sein RespawnLocation gesetzt hat — siehe
-- PlayerService.onPlayerAdded). Muss vor jedem require() stehen: ein Spieler
-- kann in Studio-Play-Solo bereits verbunden sein, sobald dieses Skript
-- ueberhaupt zu laufen beginnt.
Players.CharacterAutoLoads = false

-- Der Name links ist nur fuer den Studio-Debug-Hook am Ende der Datei
-- relevant. Gruppiert nach Thema, nicht nach Abhaengigkeit.
local REGISTRY: { { name: string, module: ModuleScript } } = {
	-- Infrastruktur
	{ name = "RateLimiter",    module = ServerScriptService.Util.RateLimiter },
	{ name = "PlayerService",  module = ServerScriptService.Services.PlayerService },
	{ name = "EconomyService", module = ServerScriptService.Services.EconomyService },

	-- Welt und Darstellung
	{ name = "MapService",              module = ServerScriptService.Services.MapService },
	{ name = "PlotDisplayService",      module = ServerScriptService.Services.PlotDisplayService },
	{ name = "BaerchiAutopilotService", module = ServerScriptService.Services.BaerchiAutopilotService },

	-- Insel, Honig, Eier
	{ name = "IslandService",      module = ServerScriptService.Services.IslandService },
	{ name = "HoneyService",       module = ServerScriptService.Services.HoneyService },
	{ name = "EggService",         module = ServerScriptService.Services.EggService },
	{ name = "EggMerchantService", module = ServerScriptService.Services.EggMerchantService },
	{ name = "EggLayService",      module = ServerScriptService.Services.EggLayService },
	{ name = "EggTreeService",     module = ServerScriptService.Services.EggTreeService },

	-- Kampf
	{ name = "PitArenaService", module = ServerScriptService.Services.PitArenaService },
	{ name = "CombatService",   module = ServerScriptService.Services.CombatService },
	{ name = "PetModeService",  module = ServerScriptService.Services.PetModeService },
	-- v15: Tower-Fortschritt (ersetzt das PIT-Level)
	{ name = "TowerService",    module = ServerScriptService.Services.TowerService },

	-- Events
	{ name = "EventService",              module = ServerScriptService.Services.EventService },
	{ name = "EventParticipationService", module = ServerScriptService.Services.EventParticipationService },

	-- Waben: Sammeln im Event-Pit und der Recycler auf dem Plot
	{ name = "CombRecyclerService", module = ServerScriptService.Services.CombRecyclerService },
	{ name = "CombService",         module = ServerScriptService.Services.CombService },

	-- Baerchis veraendern
	{ name = "FusionService",    module = ServerScriptService.Services.FusionService },
	{ name = "RecycleService",   module = ServerScriptService.Services.RecycleService },
	{ name = "PromotionService", module = ServerScriptService.Services.PromotionService },
	{ name = "CharmService",     module = ServerScriptService.Services.CharmService },
	{ name = "RebirthService",   module = ServerScriptService.Services.RebirthService },

	-- Meta
	{ name = "QuestService",    module = ServerScriptService.Services.QuestService },
	{ name = "SettingsService", module = ServerScriptService.Services.SettingsService },

	-- v15: Angeben (Bestenlisten, Inspektor, Abzeichen) und Login-Bonus
	{ name = "LeaderboardService", module = ServerScriptService.Services.LeaderboardService },
	{ name = "ProfileService",     module = ServerScriptService.Services.ProfileService },
	{ name = "PlayerBadgeService", module = ServerScriptService.Services.PlayerBadgeService },
	{ name = "LoginBonusService",  module = ServerScriptService.Services.LoginBonusService },

	-- HBB Paket 0: Messpunkte (Onboarding-Trichter, UI-Ereignisse)
	{ name = "FunnelService",      module = ServerScriptService.Services.FunnelService },
	-- HBB Paket 3: Anzeigestand (welche Bedienelemente schon gesehen sind)
	{ name = "UiStateService",     module = ServerScriptService.Services.UiStateService },
	-- HBB Paket 5: Heim-Knopf (zurueck auf den eigenen Plot)
	{ name = "HomeService",        module = ServerScriptService.Services.HomeService },

	-- Kein Spiel-Service: die Studio-Test-Schnittstelle
	{ name = "DebugService", module = ServerScriptService.Services.DebugService },
}

local loaded: { [string]: any } = {}

for _, entry in REGISTRY do
	loaded[entry.name] = require(entry.module)
end

for _, entry in REGISTRY do
	local service = loaded[entry.name]
	if service.init then
		service.init()
	end
end

for _, entry in REGISTRY do
	local service = loaded[entry.name]
	if service.start then
		service.start()
	end
end

--------------------------------------------------------------------------------
-- Studio-Debug-Hook
--
-- Legt die tatsaechlich laufenden Service-Instanzen unter _G.RBL ab.
-- Nur in Studio — im Live-Spiel existiert der Hook nicht.
--
-- ACHTUNG, gemessen und bestaetigt: die Studio Command Bar laeuft in einem
-- EIGENEN Lua-VM. Sie sieht dieses _G NICHT, und ein dortiges
-- require(ServerScriptService.Services.PlayerService) liefert eine zweite,
-- nie initialisierte Kopie des Moduls mit leerem _playerData — Aufrufe darauf
-- laufen still ins Leere. Zum Testen aus der Command Bar deshalb IMMER die
-- BindableFunction benutzen, die DebugService anlegt:
--
--   game.ServerScriptService.RBLDebug:Invoke("help")
--
-- _G.RBL ist nur fuer anderen Server-Code im selben VM gedacht.
--------------------------------------------------------------------------------

if RunService:IsStudio() then
	local debugTable: { [string]: any } = {}
	for name, service in loaded do
		debugTable[name] = service
	end

	-- Configs und Factories gleich mitgeben, die braucht man beim Testen staendig
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	debugTable.EconomyConfig  = require(ReplicatedStorage.Config.EconomyConfig)
	debugTable.BaerchiConfig  = require(ReplicatedStorage.Config.BaerchiConfig)
	debugTable.EggConfig      = require(ReplicatedStorage.Config.EggConfig)
	debugTable.BaerchiFactory = require(ReplicatedStorage.Modules.BaerchiFactory)

	_G.RBL = debugTable
	print("[GameManager] Studio-Debug-Hook aktiv — Zugriff ueber _G.RBL")
end

print("[GameManager] Alle Services gestartet")
