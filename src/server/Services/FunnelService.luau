--!strict
-- FunnelService.luau
-- ServerScriptService/Services/FunnelService.luau
--
-- Einzige Zustaendigkeit:
--   - Messpunkte an Roblox Analytics melden: Onboarding-Trichter (F01–F10),
--     Zeit je Schritt und Pacing-Meilenstein in der ersten Sitzung (Paket 8)
--     und wenige UI-Ereignisse vom Client
--
-- Kontext: Der Plan "Honey Bear Brawl" (Paket 0) braucht Zahlen aus Playtest
-- und Launch: wo steigen neue Spieler aus? Deshalb misst der Trichter nur
-- Konten, die juenger als FunnelConfig.NEW_PLAYER_MAX_AGE sind.
--
-- Name bewusst NICHT "AnalyticsService": das wuerde den Roblox-Dienst gleichen
-- Namens verdecken.
--
-- API-Wahl: LogOnboardingFunnelStepEvent(player, step, stepName). Das ist der
-- Trichter-Typ fuer "einmal pro Nutzer" und braucht keine funnelSessionId —
-- genau der Fall hier. (LogFunnelStepEvent waere fuer wiederkehrende Trichter
-- wie einen Shop-Kauf gedacht.)
--
-- In Studio nimmt Roblox keine Analytics-Events an. Dort wird nur geloggt
-- (DebugConfig.FUNNEL_LOG), damit Testschritte trotzdem pruefbar sind.
--
-- Andere Services melden einen Schritt mit genau einer Zeile:
--   FunnelService.step(player, "F03_FirstEggOpened")
-- Ein Schritt zaehlt pro Sitzung hoechstens einmal; Wiederholungen sind
-- billig (eine Tabellen-Abfrage) und duerfen ueberall stehen.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local AnalyticsService  = game:GetService("AnalyticsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes      = require(ReplicatedStorage.Network.Remotes)
local FunnelConfig = require(ReplicatedStorage.Config.FunnelConfig)
local DebugConfig  = require(ReplicatedStorage.Config.DebugConfig)

local PlayerService = require(ServerScriptService.Services.PlayerService)
local RateLimiter   = require(ServerScriptService.Util.RateLimiter)

local FunnelService = {}

local IS_STUDIO = RunService:IsStudio()

-- Wie oft der Server nach der ersten Bewegung schaut. Eine Sekunde reicht:
-- F02 misst "hat sich ueberhaupt bewegt", nicht wann genau.
local MOVE_CHECK_INTERVAL = 1

-- [Player] = { [stepName] = true } — was in dieser Sitzung schon gemeldet ist
local _done: { [Player]: { [string]: boolean } } = {}
-- [Player] = Anzahl UI-Ereignisse in dieser Sitzung
local _uiCount: { [Player]: number } = {}
-- [Player] = erster gemessener Standpunkt (fuer F02)
local _firstPos: { [Player]: Vector3 } = {}
-- [Player] = os.clock() beim Join / ob es die erste Sitzung des Kontos ist
local _sessionStart: { [Player]: number } = {}
local _firstSession: { [Player]: boolean } = {}

local function log(...: any)
	if DebugConfig.FUNNEL_LOG then
		print("[FunnelService]", ...)
	end
end

local function accountAge(player: Player): number?
	local data = PlayerService.getData(player)
	if not data then return nil end
	return os.time() - (data.createdAt or os.time())
end

local function isMeasured(player: Player, stepName: string): boolean
	local age = accountAge(player)
	if not age then return false end
	if stepName == "F10_SecondSession" then
		return age <= FunnelConfig.SECOND_SESSION_MAX_AGE
	end
	return age <= FunnelConfig.NEW_PLAYER_MAX_AGE
end

-- HBB Paket 8: Zeitpunkt eines Schritts/Meilensteins melden (siehe
-- FunnelConfig.TIME_EVENT). Nur die erste Sitzung bekommt eine Zeit: dort ist
-- "Sekunden seit Join" gleich der aktiven Spielzeit, wie im Pacing-Sim.
local function logTime(player: Player, name: string)
	local started = _sessionStart[player]
	if not started then return end
	local first = _firstSession[player] == true
	local seconds = if first then math.floor(os.clock() - started) else 0
	log(player.Name, "Zeit", name, if first then string.format("%d s (Sitzung 1)", seconds) else "(spaetere Sitzung)")

	if IS_STUDIO then return end
	local ok, err = pcall(function()
		AnalyticsService:LogCustomEvent(player, FunnelConfig.TIME_EVENT, seconds, {
			[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = name,
			[Enum.AnalyticsCustomFieldKeys.CustomField02.Name] = if first then "S1" else "S2+",
		})
	end)
	if not ok then
		warn("[FunnelService] Zeit-Event fehlgeschlagen:", name, err)
	end
end

local function highestBuildingLevel(data: any): number
	local best = 0
	for _, building in data.island.buildings do
		best = math.max(best, building.level)
	end
	return best
end

-- Sitzungsbeginn merken. Meilensteine, die schon VOR dieser Sitzung erreicht
-- waren, gelten als erledigt und melden nichts.
local function beginSession(player: Player, data: any, firstSession: boolean)
	_sessionStart[player] = os.clock()
	_firstSession[player] = firstSession
	local done = _done[player]
	if not done then
		done = {}
		_done[player] = done
	end
	local level = highestBuildingLevel(data)
	for _, milestone in FunnelConfig.PACING_MILESTONES do
		if level >= milestone.buildingLevel then done[milestone.name] = true end
	end
end

-- Pacing-Meilensteine pruefen (aus onDataChanged; billig: 3 Gebaeude)
local function checkMilestones(player: Player, data: any)
	local done = _done[player]
	if not done or not _sessionStart[player] then return end
	local level: number? = nil
	for _, milestone in FunnelConfig.PACING_MILESTONES do
		if done[milestone.name] then continue end
		level = level or highestBuildingLevel(data)
		if (level :: number) >= milestone.buildingLevel then
			done[milestone.name] = true
			-- Bis 48 h: wer 30 min/Tag spielt, erreicht Look 2 evtl. erst am Tag 2
			if isMeasured(player, "F10_SecondSession") then
				logTime(player, milestone.name)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Oeffentliche API
--------------------------------------------------------------------------------

function FunnelService.step(player: Player, stepName: string)
	-- Abrechnung beim Verlassen (CombatService) kann nach PlayerRemoving
	-- laufen; dann nichts mehr anlegen, sonst bliebe die Tabelle haengen.
	if player.Parent == nil then return end

	local index = FunnelConfig.STEP_INDEX[stepName]
	if not index then
		warn("[FunnelService] Unbekannter Schritt:", stepName)
		return
	end

	local done = _done[player]
	if not done then
		done = {}
		_done[player] = done
	end
	if done[stepName] then return end
	-- Auch bei Veteranen merken: sonst wuerde jede Wiederholung erneut das
	-- Alter pruefen.
	done[stepName] = true

	if not isMeasured(player, stepName) then return end

	log(player.Name, string.format("Schritt %02d", index), stepName)
	if stepName ~= "F01_Join" and stepName ~= "F10_SecondSession" then
		logTime(player, stepName)
	end

	if IS_STUDIO then return end
	local ok, err = pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, index, stepName)
	end)
	if not ok then
		warn("[FunnelService] Trichter-Event fehlgeschlagen:", stepName, err)
	end
end

-- Nur fuer DebugService ("state fresh"): die Sitzung beginnt fuer den
-- Trichter von vorn, damit F01–F09 in Studio erneut erscheinen.
function FunnelService.debugReset(player: Player)
	_done[player] = {}
	_uiCount[player] = 0
	_firstPos[player] = nil
	local data = PlayerService.getData(player)
	if data then beginSession(player, data, true) end
	FunnelService.step(player, "F01_Join")
end

--------------------------------------------------------------------------------
-- UI-Ereignisse vom Client
--------------------------------------------------------------------------------

local function onUiEvent(player: Player, kind: any, name: any)
	if typeof(kind) ~= "string" or not FunnelConfig.UI_EVENT_KINDS[kind] then
		return
	end
	-- Nur IdleStanding kommt ohne Panel-Namen.
	local panel: string? = nil
	if kind ~= "IdleStanding" then
		if typeof(name) ~= "string" or not FunnelConfig.UI_PANEL_NAMES[name] then
			return
		end
		panel = name
	end

	local count = (_uiCount[player] or 0) + 1
	if count > FunnelConfig.MAX_UI_EVENTS_PER_SESSION then return end
	_uiCount[player] = count

	if not isMeasured(player, "F01_Join") then return end

	log(player.Name, "UI", kind, panel or "")

	if IS_STUDIO then return end
	local ok, err = pcall(function()
		if panel then
			AnalyticsService:LogCustomEvent(player, kind, 1, {
				[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = panel,
			})
		else
			AnalyticsService:LogCustomEvent(player, kind)
		end
	end)
	if not ok then
		warn("[FunnelService] UI-Event fehlgeschlagen:", kind, err)
	end
end

--------------------------------------------------------------------------------
-- F02: erste Bewegung, rein serverseitig gemessen (kein Remote noetig)
--------------------------------------------------------------------------------

local function checkFirstMoves()
	for _, player in Players:GetPlayers() do
		local done = _done[player]
		if not done or done.F02_FirstMove or not done.F01_Join then continue end

		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if not root or not root:IsA("BasePart") then continue end

		local first = _firstPos[player]
		if not first then
			_firstPos[player] = root.Position
		elseif (root.Position - first).Magnitude >= FunnelConfig.FIRST_MOVE_DISTANCE then
			FunnelService.step(player, "F02_FirstMove")
		end
	end
end

--------------------------------------------------------------------------------
-- Initialisierung
--------------------------------------------------------------------------------

function FunnelService.init()
	RateLimiter.connect(Remotes.RequestLogUiEvent, "RequestLogUiEvent", onUiEvent)

	-- onPlayerReady: der Stand ist fertig geladen, createdAt ist sicher gesetzt.
	PlayerService.onPlayerReady(function(player, data)
		-- Ein frisch angelegtes Konto hat createdAt ≈ jetzt. Ist es beim Join
		-- schon aelter, war der Spieler vorher schon einmal da.
		local returning = os.time() - (data.createdAt or os.time()) >= FunnelConfig.SECOND_SESSION_MIN_AGE
		beginSession(player, data, not returning)
		FunnelService.step(player, "F01_Join")
		if returning then
			FunnelService.step(player, "F10_SecondSession")
		end
	end)

	-- F04: Der erste Baerchi wird beim Oeffnen automatisch ausgeruestet
	-- (IslandService.autoEquipIfNone, ohne Remote). Ein Beobachter erfasst
	-- beide Wege — automatisch und per Knopf — mit einer Stelle. Er schreibt
	-- nichts zurueck, loest also kein markDirty aus.
	PlayerService.onDataChanged(function(player, data)
		if data.island.equippedUid ~= nil then
			FunnelService.step(player, "F04_BearEquipped")
		end
		checkMilestones(player, data)
	end)

	Players.PlayerRemoving:Connect(function(player)
		_done[player] = nil
		_uiCount[player] = nil
		_firstPos[player] = nil
		_sessionStart[player] = nil
		_firstSession[player] = nil
	end)
end

function FunnelService.start()
	task.spawn(function()
		while true do
			task.wait(MOVE_CHECK_INTERVAL)
			checkFirstMoves()
		end
	end)
end

return FunnelService
