--!strict
-- GameManager.server.luau
-- ServerScriptService/Core/GameManager.server.luau
--
-- Startet alle Services in der richtigen Reihenfolge.
-- Einzige Stelle die die Initialisierungsreihenfolge kennt.
-- Kein anderer Script startet Services direkt.
--
-- Reihenfolge — die Begruendung steht hier, nicht in den Services:
--   1. RateLimiter zuerst: jeder Service der ein Remote verbindet benutzt ihn.
--   2. MapService vor PlayerService (PlayerService ruft MapService beim Join auf).
--   3. EconomyService vor allen Services die Waehrung bewegen.
--   4. HoneyService vor PlayerService: es registriert den onDataLoaded-Callback
--      fuer den Offline-Honig und wuerde sonst die ersten Joins verpassen.
--   5. PlayerService als LETZTES — sein init() loest sofort Join-Events aus.

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

-- Reihenfolge = Startreihenfolge. Der Name links ist nur fuer den
-- Studio-Debug-Hook am Ende der Datei relevant.
local REGISTRY: { { name: string, module: ModuleScript } } = {
	{ name = "RateLimiter",    module = ServerScriptService.Util.RateLimiter },

	{ name = "MapService",     module = ServerScriptService.Services.MapService },
	{ name = "EconomyService", module = ServerScriptService.Services.EconomyService },

	-- Faehrt den Event-Zyklus (Pause/Event-Wechsel am Event-Pit in der
	-- Weltmitte). Braucht nur MapService, keine Spielerdaten — Reihenfolge zu
	-- allem anderen ist unkritisch, steht aber der Vollstaendigkeit halber
	-- gleich bei MapService/EconomyService.
	{ name = "EventService",   module = ServerScriptService.Services.EventService },

	{ name = "IslandService",  module = ServerScriptService.Services.IslandService },
	{ name = "EggService",     module = ServerScriptService.Services.EggService },

	-- Reine Darstellung des PIT-Laufs in der Arena. Muss vor CombatService
	-- stehen, weil der sie am Ende eines Laufs aufruft.
	{ name = "PitArenaService", module = ServerScriptService.Services.PitArenaService },
	{ name = "CombatService",  module = ServerScriptService.Services.CombatService },
	{ name = "FusionService",  module = ServerScriptService.Services.FusionService },
	{ name = "RecycleService", module = ServerScriptService.Services.RecycleService },
	{ name = "RebirthService", module = ServerScriptService.Services.RebirthService },

	-- Die zweite Fortschrittsachse (Promotion/Charms, siehe
	-- Config/PromotionConfig). Beide aendern nur Spielerdaten und verbinden je
	-- ein Remote — sie brauchen weder MapService noch eine bestimmte Position
	-- vor PlayerService. Sie stehen hier bei Fusion/Recycling, weil sie
	-- dieselbe Art Aktion sind: der Spieler gibt Besitz auf und bekommt dafuer
	-- etwas Staerkeres.
	--
	-- CharmService MUSS nach EconomyService stehen (er bucht GoldGummies ab) —
	-- das ist durch dessen Platz weiter oben erfuellt.
	{ name = "PromotionService", module = ServerScriptService.Services.PromotionService },
	{ name = "CharmService",     module = ServerScriptService.Services.CharmService },

	-- Honig-Produktion und Fuettern. Registriert einen onDataLoaded-Callback
	-- (Offline-Honig) und muss deshalb vor PlayerService stehen.
	-- Ersetzt den frueheren FarmService, der aus dem Projekt entfernt ist.
	{ name = "HoneyService",   module = ServerScriptService.Services.HoneyService },

	-- Laesst den ausgeruesteten Baerchi Eier legen und nimmt das Einsammeln
	-- entgegen. Registriert einen onDataLoaded-Callback (Offline-Eier) und muss
	-- deshalb vor PlayerService stehen — genau wie HoneyService.
	--
	-- Steht nach MapService, weil es dessen Figuren-Position braucht, um zu
	-- wissen, WO das Ei landet.
	{ name = "EggLayService",  module = ServerScriptService.Services.EggLayService },

	-- Wie HoneyService: registriert einen onDataLoaded-Callback und muss
	-- deshalb vor PlayerService stehen. Haengt ausserdem beim Start die
	-- Datenquelle fuer MapServices nachgeholten Figuren-Neuaufbau ein.
	-- Ersetzt den frueheren BaerchiDisplayService, der aus dem Projekt
	-- entfernt ist.
	{ name = "PlotDisplayService", module = ServerScriptService.Services.PlotDisplayService },

	-- Laesst den ausgeruesteten Baerchi selbststaendig zum Honig-Teich laufen.
	-- Registriert keinen onDataLoaded-Callback (pollt einfach Players:GetPlayers()),
	-- die Reihenfolge zu PlayerService ist deshalb nicht kritisch — steht aber
	-- der Vollstaendigkeit halber bei den anderen Anzeige-nahen Services.
	{ name = "BaerchiAutopilotService", module = ServerScriptService.Services.BaerchiAutopilotService },

	-- Schickt den ausgeruesteten Baerchi auf Knopfdruck zum Event-Pit in der
	-- Weltmitte und verteilt beim Event-Ende die Stat-Stufen.
	--
	-- Muss nach EventService stehen: sein init() meldet dort den
	-- onEventEnded-Callback an. Und nach BaerchiAutopilotService, weil beide
	-- dieselbe Figur bewegen und sich ueber ActivityLock einigen — die
	-- Reihenfolge ist dafuer zwar nicht zwingend, aber wer eines der beiden
	-- anfasst, soll das andere direkt daneben sehen.
	{ name = "EventParticipationService", module = ServerScriptService.Services.EventParticipationService },

	-- Spieler-Einstellungen (aktuell: Sprache). Aendert nur ein Feld in den
	-- Spielerdaten und verbindet ein Remote — Reihenfolge zu PlayerService
	-- unkritisch (der Handler laeuft erst, wenn ein Spieler etwas anklickt).
	{ name = "SettingsService", module = ServerScriptService.Services.SettingsService },

	{ name = "PlayerService",  module = ServerScriptService.Services.PlayerService },  -- letzter Spiel-Service!

	-- Kein Spiel-Service: baut nur die Studio-Test-Schnittstelle.
	-- Muss nach allen anderen kommen, weil es sie alle referenziert.
	{ name = "DebugService",   module = ServerScriptService.Services.DebugService },
}

-- Erst alle laden, dann alle starten — ein init() darf sich darauf verlassen
-- dass jedes andere Modul bereits ausgewertet ist.
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
