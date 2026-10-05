--!strict
-- PetModeService.luau
-- ServerScriptService/Services/PetModeService.luau
--
-- Einzige Zustaendigkeit:
--   - Die untere Pet-Leiste (Event / Fight) serverseitig entscheiden: was ein
--     Knopfdruck bedeutet (hinschicken, zurueckholen, wechseln) und in welchem
--     Zustand der ausgeruestete Baerchi gerade ist.
--
-- ============================================================
-- WARUM EIN EIGENER SERVICE
-- ============================================================
-- Event-Teilnahme (EventParticipationService) und PIT-Lauf
-- (CombatService/PitArenaService) bewegen dieselbe Figur. Die Leiste macht
-- beides exklusiv und erlaubt den Wechsel per Klick ("erst heim, dann
-- dorthin"). Diese Reihenfolge soll nicht an zwei Services UND dem Client
-- haengen — deshalb entscheidet sie hier, an einer Stelle.
--
-- Der Zustand wird NICHT selbst nachgefuehrt, sondern aus den beiden
-- Services abgelesen (getPhase). Damit kann er nie von der Wirklichkeit
-- abweichen: laeuft die Figur, sagt das der Service, der sie bewegt. Hier
-- liegt nur das VORGEMERKTE Ziel beim Wechsel.
--
-- Zustaende (an den Client ueber PetModeChanged):
--   Home       auf dem Plot (Honig-Teich zaehlt dazu, siehe Konzept)
--   ToEvent    auf dem Weg zum Event-Pit       AtEvent  dort
--   ToPit      auf dem Weg in die eigene Arena  InPit    im Kampf
--   Returning  auf dem Heimweg (von Event oder PIT)
--
-- Ein Klick (RequestPetMode "Event"/"Fight"):
--   - gleicher Modus aktiv         -> zurueckholen
--   - zu Hause                     -> hinschicken
--   - anderer Modus aktiv/Heimweg  -> Ziel vormerken, anderen zurueckholen;
--                                     zu Hause startet das Ziel automatisch.
--                                     Nochmal klicken bricht den Wechsel ab.

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes = require(ReplicatedStorage.Network.Remotes)

local PlayerService             = require(ServerScriptService.Services.PlayerService)
local CombatService             = require(ServerScriptService.Services.CombatService)
local PitArenaService           = require(ServerScriptService.Services.PitArenaService)
local EventParticipationService = require(ServerScriptService.Services.EventParticipationService)
local RateLimiter               = require(ServerScriptService.Util.RateLimiter)
local FunnelService = require(ServerScriptService.Services.FunnelService)  -- HBB: Messpunkte

local PetModeService = {}

-- Wie oft der Zustand abgelesen und (bei Aenderung) an den Client gemeldet
-- wird. Kurz genug, dass die Leiste sofort reagiert und die Stage-Anzeige
-- mitlaeuft; bei hoechstens acht Spielern vernachlaessigbar.
local TICK_SECONDS = 0.2

export type Mode  = "Event" | "Fight"
type Pending = { mode: Mode, resume: CombatService.ResumeChoice? }

local VALID_RESUME: { [string]: boolean } = { Fresh = true, Percent = true, Last = true }

local _pending: { [Player]: Pending } = {}
local _lastSent: { [Player]: string } = {}

--------------------------------------------------------------------------------
-- Zustand ablesen
--------------------------------------------------------------------------------

-- Gibt Zustand, laufende Stage (nur im PIT) und den Modus zurueck, aus dem
-- ein Heimweg kommt.
local function readState(player: Player): (string, number?, Mode?)
	local pitPhase, stage = PitArenaService.getPhase(player)
	if pitPhase then
		return pitPhase, stage, "Fight"
	end

	local eventPhase = EventParticipationService.getPhase(player)
	if eventPhase then
		return eventPhase, nil, "Event"
	end

	return "Home", nil, nil
end

-- Welcher Modus ist gerade AKTIV (hin oder dort)? Ein Heimweg zaehlt nicht.
local function activeMode(state: string): Mode?
	if state == "ToEvent" or state == "AtEvent" then return "Event" end
	if state == "ToPit" or state == "InPit" then return "Fight" end
	return nil
end

-- Ist der Baerchi zu Hause auf dem Plot? (EggLayService: Legen nur dann)
function PetModeService.isHome(player: Player): boolean
	local state = readState(player)
	return state == "Home"
end

--------------------------------------------------------------------------------
-- Aktionen
--------------------------------------------------------------------------------

local function recall(player: Player, mode: Mode)
	if mode == "Event" then
		EventParticipationService.recall(player)
	else
		PitArenaService.requestRecall(player)
	end
end

local function start(player: Player, mode: Mode, resume: CombatService.ResumeChoice?): boolean
	if mode == "Event" then
		return EventParticipationService.sendToEvent(player)
	end

	local data = PlayerService.getData(player)
	local uid  = if data then data.island.equippedUid else nil
	if not uid then
		Remotes.ActionFailed:FireClient(player, "RequestPetMode", "Kein Baerchi ausgeruestet")
		return false
	end
	return CombatService.startPitRun(player, uid, resume)
end

local function broadcast(player: Player, force: boolean?)
	local state, stage, from = readState(player)
	local pending = _pending[player]
	local abducting = EventParticipationService.isAbducting(player)

	-- v15: in welchem Tower gekaempft wird (Pet-Leiste "Tower II · Stage 23").
	local data = PlayerService.getData(player)
	local tower = if data then data.towers.selected else nil

	local signature = table.concat({
		state,
		tostring(stage),
		tostring(tower),
		tostring(from),
		if pending then pending.mode else "-",
		tostring(abducting),
	}, "|")

	if not force and _lastSent[player] == signature then
		return
	end
	_lastSent[player] = signature

	Remotes.PetModeChanged:FireClient(player, state, if pending then pending.mode else nil, {
		stage     = stage,
		tower     = tower,
		from      = from,
		abducting = abducting,
	})
end

-- Ein Knopfdruck aus der Pet-Leiste.
function PetModeService.request(player: Player, mode: string, resume: CombatService.ResumeChoice?)
	local state = readState(player)
	local active = activeMode(state)

	if mode == "Home" then
		_pending[player] = nil
		if active then recall(player, active) end
		broadcast(player)
		return
	end

	if mode ~= "Event" and mode ~= "Fight" then
		return
	end
	local wanted: Mode = mode :: Mode
	if wanted == "Event" then FunnelService.step(player, "F08_EventButtonPressed") end

	if active == wanted then
		-- Gleicher Knopf nochmal: zurueckholen.
		_pending[player] = nil
		recall(player, wanted)

	elseif state == "Home" then
		_pending[player] = nil
		start(player, wanted, resume)

	else
		-- Anderer Modus aktiv oder Heimweg: Wechsel vormerken bzw. abbrechen.
		local pending = _pending[player]
		if pending and pending.mode == wanted then
			_pending[player] = nil
		else
			_pending[player] = { mode = wanted, resume = resume }
			if active then recall(player, active) end
		end
	end

	broadcast(player)
end

local function tick()
	for _, player in Players:GetPlayers() do
		if not PlayerService.getData(player) then continue end

		-- Vorgemerkter Wechsel: sobald der Baerchi zu Hause ist, losschicken.
		local pending = _pending[player]
		if pending and readState(player) == "Home" then
			_pending[player] = nil
			-- v15: der Start simuliert in Portionen (yieldet) — nicht den Takt
			-- fuer alle anderen Spieler aufhalten.
			task.spawn(start, player, pending.mode, pending.resume)
		end

		broadcast(player)
	end
end

--------------------------------------------------------------------------------
-- Initialisierung
--------------------------------------------------------------------------------

function PetModeService.init()
	RateLimiter.connect(Remotes.RequestPetMode, "RequestPetMode", function(player, mode: any, resume: any)
		if typeof(mode) ~= "string" then return end

		local choice: CombatService.ResumeChoice? = nil
		if typeof(resume) == "string" and VALID_RESUME[resume] then
			choice = resume :: CombatService.ResumeChoice
		end

		PetModeService.request(player, mode, choice)
	end)

	Players.PlayerRemoving:Connect(function(player)
		_pending[player]  = nil
		_lastSent[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(TICK_SECONDS)
			local ok, err = pcall(tick)
			if not ok then
				warn("[PetModeService] Tick fehlgeschlagen:", err)
			end
		end
	end)

	print("[PetModeService] Initialisiert")
end

return PetModeService
