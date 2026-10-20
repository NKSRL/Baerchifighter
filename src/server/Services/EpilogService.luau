--!strict
-- EpilogService.luau
-- ServerScriptService/Services/EpilogService.luau
--
-- Einzige Zustaendigkeit (Prompt 1 von 7, Final-Epilog):
--   - Den Zustandsautomaten des Epilogs fuehren: none -> pending -> seen ->
--     launched (Regeln in Modules/EpilogRules, hier nur Verdrahtung).
--   - Den Final-100-Sieg ATOMAR festhalten (Endless offen + pending), bevor
--     irgendein Effekt beginnt, dann EpilogStart mit Token schicken.
--   - Token ausgeben und pruefen (EpilogSeen / EpilogSkip / RequestPressLaunch);
--     Ungueltiges still verwerfen (Zaehler im Log, kein Kick).
--   - Die Endless-Meldung (TowerUnlocked) zurueckhalten, bis die Sequenz
--     vorbei ist (Verzoegerungs-Hook fuer Prompt 5/6).
--   - Schnittstellen/Stubs fuer Prompt 2-6 (restore, Gipfel, Insel, Knopf).
--
-- Nicht hier: Gipfel/Insel/Bruecke/Terminal (Prompt 2-4), Kamera (5), Knopf-
-- Finale und Welt-Betreten (6), Texte/Audio (7). Der Server ist autoritativ,
-- der Client bekommt nur Token + Zustand. Nichts wird geloescht.
--
-- Abhaengigkeiten: PlayerService, Remotes, Config. KEIN require auf
-- TowerService (der ruft uns auf) — sonst ein Ringschluss.

local HttpService       = game:GetService("HttpService")
local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace         = game:GetService("Workspace")

local Types         = require(ReplicatedStorage.Network.Types)
local Remotes       = require(ReplicatedStorage.Network.Remotes)
local EpilogConfig  = require(ReplicatedStorage.Config.EpilogConfig)
local FeatureFlags  = require(ReplicatedStorage.Config.FeatureFlags)
local TowerConfig   = require(ReplicatedStorage.Config.TowerConfig)
local EpilogRules   = require(ReplicatedStorage.Modules.EpilogRules)
local EpilogRoute   = require(ReplicatedStorage.Modules.EpilogRoute)
local MapConfig     = require(ReplicatedStorage.Config.MapConfig)

local PlayerService  = require(ServerScriptService.Services.PlayerService)
local MapService     = require(ServerScriptService.Services.MapService)
local PitArenaService = require(ServerScriptService.Services.PitArenaService)
local RateLimiter    = require(ServerScriptService.Util.RateLimiter)
local EpilogIslandBuilder = require(ServerScriptService.Util.MapBuild.EpilogIslandBuilder)
local EpilogTerminalBuilder = require(ServerScriptService.Util.MapBuild.EpilogTerminalBuilder)
local FigureFX      = require(ServerScriptService.Util.FigureFX)
local FigurePlacement = require(ServerScriptService.Util.FigurePlacement)

local EpilogService = {}

local S = EpilogConfig.STATE

--------------------------------------------------------------------------------
-- Zustand im Speicher (nie gespeichert, beim Verlassen freigegeben)
--------------------------------------------------------------------------------

-- Token pro Spieler (Rules.newToken)
local _tokens: { [Player]: any } = {}
-- Zeitpunkt (os.clock) der letzten Start-Entscheidung — Race-Schutz
local _lastStartClock: { [Player]: number } = {}
-- Endless-Meldung zurueckgehalten: Spieler -> Liste Tower-Ids
local _deferred: { [Player]: { string } } = {}
-- Verworfene Anfragen (Log-Zaehler, kein Kick)
local _rejected: { [Player]: number } = {}
local _rejectedTotal = 0

-- Prompt 5: laufende Kamerafahrt je Spieler (nur im Speicher). Der Server fuehrt den
-- Zeitplan (Teleport, Bruecke, Begleiter, Wachhund); die Kamera macht der Client.
type Seq = {
	startClock : number,        -- os.clock() beim EpilogStart
	speed      : number,        -- Zeitraffer (Debug), sonst 1
	route      : any,           -- MapService.getEpilogRoute (Zahlen-Tabellen)
	thread     : thread?,       -- Zeitplan
	companion  : thread?,       -- Begleiter-Lauf
	cancelled  : boolean,
	skipped    : boolean,
	arrived    : boolean,       -- Ankunft ist abgeschlossen (Insel, Bruecke, Terminal, Avatar)
}
local _seq: { [Player]: Seq } = {}
-- Zeitraffer fuer den naechsten Start (nur Debug: epilog speed N)
local _speed: { [Player]: number } = {}
-- Debug-Bericht des Clients (epilog audit): wartender Aufrufer
local _auditWait: { [Player]: { thread: thread, done: boolean } } = {}

-- Laufendes Finale je Spieler (nur im Speicher). Zeit f = Sekunden seit dem gueltigen Druck.
type Fin = {
	startClock : number,
	speed      : number,
	jump       : number,          -- Sekunden, die ein Skip vorgezogen hat
	token      : string,          -- gueltig nur fuer EpilogSkip waehrend des Finales
	thread     : thread?,
	cancelled  : boolean,
	skipped    : boolean,
	phase      : string,          -- "finale" | "return"
	conns      : { RBXScriptConnection },
}
local _fin: { [Player]: Fin } = {}
local _lastPress: { [Player]: number } = {}

-- Prompt 6 haengt hier den Knopf-Ablauf ein (nach gueltigem Token + State "seen").
local _pressHandler: ((Player, Types.PlayerData) -> ())? = nil
-- Prompt 2/3 haengen hier das Platzieren auf Gipfel/Insel ein.
local _placeHandler: ((Player, Types.PlayerData, string) -> ())? = nil

local function isEnabled(): boolean
	return FeatureFlags.isOn(EpilogConfig.FLAG)
end

local function reject(player: Player, what: string, why: string)
	_rejected[player] = (_rejected[player] or 0) + 1
	_rejectedTotal += 1
	if _rejected[player] <= 5 then   -- Log-Flood-Schutz wie im RateLimiter
		print("[EpilogService] verworfen:", player.Name, "|", what, "|", why,
			"| gesamt:", _rejected[player])
	end
end

--------------------------------------------------------------------------------
-- Lesen
--------------------------------------------------------------------------------

function EpilogService.getState(data: Types.PlayerData): string
	local epilog = data.epilog
	return if epilog and EpilogRules.isValidState(epilog.state) then epilog.state else S.NONE
end

-- Laeuft fuer diesen Spieler gerade eine Sequenz (pending/seen, Flag an)?
function EpilogService.isSequenceActive(player: Player): boolean
	if not isEnabled() then return false end
	local data = PlayerService.getData(player)
	if not data then return false end
	local state = EpilogService.getState(data)
	return state == S.PENDING or state == S.SEEN
end

function EpilogService.getRejectedCount(): number
	return _rejectedTotal
end

--------------------------------------------------------------------------------
-- Verzoegerte Endless-Meldung (Hook fuer Prompt 5/6)
--------------------------------------------------------------------------------

-- Von TowerService vor jedem TowerUnlocked aufgerufen. true = die Meldung ist
-- zurueckgestellt (TowerService feuert dann NICHT). Nur Endless wird gehalten,
-- nur solange die Sequenz offen ist.
function EpilogService.deferUnlockNotice(player: Player, towerId: string): boolean
	if towerId ~= "Endless" or not EpilogService.isSequenceActive(player) then
		return false
	end
	local list = _deferred[player]
	if not list then
		list = {}
		_deferred[player] = list
	end
	if not table.find(list, towerId) then
		table.insert(list, towerId)
	end
	-- Notfall-Freigabe, falls niemand sie holt (z. B. Client ohne Epilog-Anzeige).
	task.delay(EpilogConfig.DEFER_MAX_SECONDS, function()
		EpilogService.releaseDeferred(player)
	end)
	return true
end

-- Gibt zurueckgehaltene Meldungen frei (Prompt 5/6: nach Rueckweg bzw. Finale;
-- hier auch bei "launched" und per Notfall-Timer). Mehrfachaufruf harmlos.
function EpilogService.releaseDeferred(player: Player)
	local list = _deferred[player]
	if not list then return end
	_deferred[player] = nil
	if player.Parent == nil then return end
	for _, towerId in list do
		Remotes.TowerUnlocked:FireClient(player, towerId)
	end
end

--------------------------------------------------------------------------------
-- Token
--------------------------------------------------------------------------------

-- `backdate` (Sekunden): nur fuer den Debug-Zeitraffer, damit die Mindestzeit fuer EpilogSeen
-- nicht an der verkuerzten Sequenz scheitert.
local function issueToken(player: Player, backdate: number?): string
	local guid = HttpService:GenerateGUID(false)
	_tokens[player] = EpilogRules.newToken(guid, player.UserId, os.time() - (backdate or 0))
	return guid
end

--------------------------------------------------------------------------------
-- Sieg: Phase 1-3
--------------------------------------------------------------------------------

-- Von TowerService.recordRun aufgerufen (synchron, im selben Schreibvorgang wie
-- der Rekord; vor dem Speichern des CombatService). Gibt true zurueck, wenn
-- eine NEUE Sequenz beginnt. Kein task.wait vor der Mutation.
function EpilogService.onFinalClear(player: Player, data: Types.PlayerData, towerId: string, stage: number): boolean
	if not isEnabled() then return false end
	local def = TowerConfig.get(EpilogConfig.TOWER_ID)
	if not def or not EpilogRules.isTrigger(towerId, stage, def.stages) then return false end

	-- Race: zwei Final-Clears kurz hintereinander -> hoechstens eine Sequenz
	-- (der Zustand schuetzt schon; das hier faengt zusaetzlich Debug/Doppelaufruf).
	local nowClock = os.clock()
	local last = _lastStartClock[player]
	if last and nowClock - last < EpilogConfig.START_DEBOUNCE_SECONDS then
		return false
	end

	-- Phase 2: EINE Mutation (Endless offen + pending + firstClearAt).
	local started = EpilogRules.applyFinalClear(data, os.time())
	if not started then
		-- Phase 3: Zustand war nicht "none" -> nur der normale Sieg-Moment.
		return false
	end
	_lastStartClock[player] = nowClock

	-- Prompt 2 / Phase 1: der Run-Turm bleibt stehen und bekommt den Gipfel. Das
	-- MUSS synchron hier passieren (der Abbau beginnt kurz nach der Abrechnung).
	-- Ein Fehler im Bau darf die Abrechnung nie verhindern.
	local okSummit, errSummit = pcall(MapService.setSummit, player, true, true)
	if not okSummit then
		warn("[EpilogService] Gipfel konnte nicht gebaut werden:", errSummit)
	end

	-- Phase 3: Start erst NACH dem Speichern melden. task.defer: der Speicherstoss
	-- beginnt erst, wenn die Abrechnung des Laufs (recordRun, Meilensteine,
	-- CombatService-Save) durch ist; UpdateAsync haelt den Thread an und soll sie
	-- nicht blockieren. Bis dahin steht der Stand vollstaendig im Speicher.
	task.defer(function()
		local ok = PlayerService.saveConfirmed(player)
		if not ok then
			warn("[EpilogService] Speichern nach Final 100 meldete Fehler fuer", player.Name,
				"- Stand liegt im Speicher, naechster Auto-Save holt ihn nach")
		end
		if player.Parent == nil then return end
		EpilogService.beginFull(player)
	end)
	print("[EpilogService]", player.Name, "| Final", stage, "geschafft -> pending (Sequenz startet)")
	return true
end

--------------------------------------------------------------------------------
-- Fortschritt: seen / launched
--------------------------------------------------------------------------------

-- EpilogSeen: Spieler hat Insel/Terminal erreicht. pending -> seen.
local function handleSeen(player: Player, token: any)
	local data = PlayerService.getData(player)
	if not data or not isEnabled() then return end
	if EpilogService.getState(data) ~= S.PENDING then
		reject(player, "EpilogSeen", "falscher Zustand: " .. EpilogService.getState(data))
		return
	end
	local ok, why = EpilogRules.checkToken(_tokens[player], token, player.UserId, "seen", os.time())
	if not ok then
		reject(player, "EpilogSeen", why)
		return
	end
	EpilogRules.consumeSeen(_tokens[player])
	if EpilogRules.transition(data.epilog, S.SEEN, os.time()) then
		PlayerService.markDirty(player)
		PlayerService.saveNow(player)
	end
end

-- EpilogSkip: Kamerafahrt uebersprungen. Aendert den Zustand NICHT (Skip darf
-- nie den Weg zu Endless/Welt 2 verbauen). Prompt 5: der Server springt zur Ankunft
-- (Insel, Bruecke, Terminal fertig, Avatar und Begleiter davor) - nie ueber den Knopf
-- hinweg, und nicht vor Sekunde 12 der Sequenz.
local function handleSkip(player: Player, token: any)
	local data = PlayerService.getData(player)
	if not data or not isEnabled() then return end
	-- Prompt 6: waehrend des Finales (State "launched") gilt der Skip dem Finale
	if EpilogService.skipFinale(player, token) then return end
	local state = EpilogService.getState(data)
	if state ~= S.PENDING and state ~= S.SEEN then
		reject(player, "EpilogSkip", "falscher Zustand: " .. state)
		return
	end
	local ok, why = EpilogRules.checkToken(_tokens[player], token, player.UserId, "skip", os.time())
	if not ok then
		reject(player, "EpilogSkip", why)
		return
	end
	local seq = _seq[player]
	if not seq or seq.cancelled or seq.skipped or seq.arrived then
		reject(player, "EpilogSkip", "keine_laufende_fahrt")
		return
	end
	local Q = EpilogConfig.SEQUENCE
	local elapsed = (os.clock() - seq.startClock) * seq.speed
	if elapsed < Q.skipFromSeconds - Q.skipTolerance * seq.speed then
		reject(player, "EpilogSkip", "zu_frueh")
		return
	end
	EpilogService.skipToArrival(player, seq)
end

-- RequestPressLaunch (C->S): Knopf gehalten. Nur mit gueltigem Token, State pending/seen,
-- lebendem Spieler und Abstand < 14 Studs zum Terminal (Pruefung in startFinale). Ein
-- zweiter Druck waehrend des Finales ist ein no-op. Ohne Token wirkt nichts.
local function handlePress(player: Player, token: any)
	local data = PlayerService.getData(player)
	if not data or not isEnabled() then return end
	local state = EpilogService.getState(data)
	if state ~= S.PENDING and state ~= S.SEEN then
		if _fin[player] == nil then
			reject(player, "RequestPressLaunch", "falscher Zustand: " .. state)
		end
		return
	end
	local ok, why = EpilogRules.checkToken(_tokens[player], token, player.UserId, "press", os.time())
	if not ok then
		reject(player, "RequestPressLaunch", why)
		return
	end
	EpilogService.startFinale(player, "remote", false)
end

-- Knopf-Finale: seen -> launched UND World2 frei in einer Mutation, dann
-- speichern, melden und zurueckgehaltene Meldungen freigeben. Wird von
-- Prompt 6 (nach dem Halten) und vom Debug-Befehl benutzt. false = nicht erlaubt.
function EpilogService.markLaunched(player: Player, keepDeferred: boolean?): boolean
	local data = PlayerService.getData(player)
	if not data then return false end
	local now = os.time()
	-- Ein Druck vor EpilogSeen (Spieler war schneller als die Meldung): pending -> seen nachholen
	if EpilogService.getState(data) == S.PENDING then
		EpilogRules.transition(data.epilog, S.SEEN, now)
	end
	if not EpilogRules.applyLaunch(data, now) then return false end
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)
	_tokens[player] = nil
	Remotes.World2Unlocked:FireClient(player, EpilogConfig.WORLD2_ID)
	if keepDeferred ~= true then EpilogService.releaseDeferred(player) end
	print("[EpilogService]", player.Name, "| launched -> Welt 2 frei")
	return true
end

--------------------------------------------------------------------------------
-- Gipfel (Prompt 2)
--------------------------------------------------------------------------------

-- Setzt Avatar und Begleiter-Baerchi auf den Gipfel. Wartet (hoechstens
-- `maxWait` s) auf den Charakter; der Builder holt spaeter auch jeden Respawn
-- selbst auf den Gipfel zurueck.
function EpilogService.teleportWhenReady(player: Player, maxWait: number?)
	local waited = 0
	while player.Parent ~= nil and waited < (maxWait or 15) do
		local data = PlayerService.getData(player)
		if data and MapService.hasSummit(player) and player.Character
			and player.Character:FindFirstChild("HumanoidRootPart") then
			MapService.teleportToSummit(player, data.island.equippedUid)
			return
		end
		task.wait(0.25)
		waited += 0.25
	end
end

--------------------------------------------------------------------------------
-- Kamerafahrt (Prompt 5): Zeitplan des Servers
--------------------------------------------------------------------------------
-- Der Server fuehrt nur, was autoritativ sein muss: Teleport beim Flash, Insel und
-- Bruecke ab Sekunde 5, den Begleiter-Baerchi und die Ankunft. Kamera, Lauf des Avatars
-- (Humanoid:MoveTo auf dem Client) und Effekte macht der Client (EpilogController).
-- Kommt der Avatar nicht an (Tod, Haenger, Skip), setzt der Server ihn vor das Terminal.

local function clampSpeed(speed: number?): number
	local Q = EpilogConfig.SEQUENCE
	return math.clamp(speed or 1, Q.minSpeed, Q.maxSpeed)
end

local function seqAlive(player: Player, seq: Seq): boolean
	return _seq[player] == seq and not seq.cancelled and not seq.skipped and player.Parent ~= nil
end

-- Wartet bis Sekunde `t` der Sequenz (durch den Zeitraffer geteilt). false = Fahrt vorbei.
local function waitUntil(player: Player, seq: Seq, t: number): boolean
	local remaining = seq.startClock + t / seq.speed - os.clock()
	if remaining > 0 then task.wait(remaining) end
	return seqAlive(player, seq)
end

local function sequenceSeconds(seq: Seq): number
	return (os.clock() - seq.startClock) * seq.speed
end

local function stopThreads(seq: Seq)
	local current = coroutine.running()
	if seq.thread and seq.thread ~= current then pcall(task.cancel, seq.thread) end
	if seq.companion and seq.companion ~= current then pcall(task.cancel, seq.companion) end
	seq.thread = nil
	seq.companion = nil
end

-- Fahrt abbrechen (Verlassen, Debug-Reset): nichts wird nachgeholt.
function EpilogService.cancelSequence(player: Player)
	local seq = _seq[player]
	if not seq then return end
	seq.cancelled = true
	stopThreads(seq)
	_seq[player] = nil
end

function EpilogService.hasSequence(player: Player): boolean
	return _seq[player] ~= nil
end

-- Der Begleiter-Baerchi laeuft `companionAhead` Studs vor dem Avatar ueber den Weg (gleiches
-- Tempoprofil wie der Avatar, Hopser wie FigureWalker). Eine Heartbeat-Schleife, ein Thread.
local function walkCompanion(player: Player, seq: Seq)
	local Q = EpilogConfig.SEQUENCE
	local data = PlayerService.getData(player)
	local uid = data and data.island.equippedUid
	local model = if uid then MapService.getBaerchiModel(player, uid) else nil
	local pts = seq.route and seq.route.points
	if not model or not pts or #pts < 2 then return end

	local route = EpilogRoute.new(pts)
	local duration = Q.arriveAt - Q.walkAt
	local profile = EpilogRoute.profile(route.length, duration, Q.walkFactors)
	local sideStart = EpilogConfig.SUMMIT.companionSide
	FigureFX.stopIdle(model)

	local lastFacing = CFrame.new()
	while seqAlive(player, seq) and model.Parent ~= nil do
		local tau = sequenceSeconds(seq) - Q.walkAt
		if tau >= duration then break end
		local s = math.min(route.length, EpilogRoute.distanceAt(profile, math.max(tau, 0)) + Q.companionAhead)
		local p = EpilogRoute.pointAt(route, s)
		local dir = EpilogRoute.directionAt(route, s)
		local foot = Vector3.new(p[1], p[2], p[3])
		-- Anfangs steht er neben dem Avatar (Gipfel): die Seitenverschiebung gleitet in 1,5 s weg
		local lateral = sideStart * (1 - math.clamp(tau / 1.5, 0, 1))
		foot += Vector3.new(-dir[3], 0, dir[1]) * lateral
		local travelled = EpilogRoute.distanceAt(profile, math.max(tau, 0))
		local bob = math.abs(math.sin(travelled * MapConfig.WALK_BOB_PER_STUD * math.pi)) * MapConfig.WALK_BOB_HEIGHT
		lastFacing = CFrame.lookAt(Vector3.zero, Vector3.new(dir[1], 0, dir[3]))
			* CFrame.Angles(math.rad(MapConfig.WALK_LEAN_DEGREES), 0, 0)
		FigurePlacement.place(model, foot + Vector3.new(0, bob, 0), lastFacing)
		RunService.Heartbeat:Wait()
	end
	-- Am Ziel wieder sanft wippen (bei Skip/Ankunft setzt teleportToIsland die Figur ohnehin neu)
	if seqAlive(player, seq) and model.Parent ~= nil then
		FigureFX.idleBob(model, { height = MapConfig.IDLE_BOB_HEIGHT, rate = MapConfig.IDLE_BOB_RATE })
	end
end

-- Ankunft sichern: Insel, Bruecke und Terminal stehen, Avatar und Begleiter sind vor dem
-- Terminal. `force` (Skip) setzt den Avatar immer um, sonst nur, wenn er nicht angekommen ist.
local function finishArrival(player: Player, seq: Seq, force: boolean)
	if seq.arrived then return end
	seq.arrived = true
	local data = PlayerService.getData(player)
	if not data or not MapService.hasSummit(player) then return end
	if not MapService.hasIsland(player) then MapService.buildIsland(player, false) end
	if not MapService.isBridgeComplete(player) then MapService.buildBridgeInstant(player) end
	if not MapService.hasTerminal(player) then MapService.buildTerminal(player) end

	local pts = seq.route and seq.route.points
	local last = pts and pts[#pts]
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local near = false
	if last and root and root:IsA("BasePart") then
		local d = root.Position - Vector3.new(last[1], last[2], last[3])
		near = Vector3.new(d.X, 0, d.Z).Magnitude <= EpilogConfig.SEQUENCE.arriveRadius
	end
	if force or not near then
		MapService.teleportToIsland(player, data.island.equippedUid)
	end
end

-- Skip (nach der Pruefung in handleSkip): Zeitplan und Begleiter-Lauf stoppen, Ankunft herstellen.
function EpilogService.skipToArrival(player: Player, seq: Seq)
	seq.skipped = true
	stopThreads(seq)
	task.spawn(function()
		finishArrival(player, seq, true)
		-- Eintrag bleibt bis zum Ende der Phase 5 (der Client spielt sie noch)
		local remaining = EpilogConfig.SEQUENCE.endAt - EpilogConfig.SEQUENCE.arriveAt
		task.wait(remaining / seq.speed)
		if _seq[player] == seq then _seq[player] = nil end
	end)
end

local function runSequence(player: Player, seq: Seq)
	local Q = EpilogConfig.SEQUENCE
	if not waitUntil(player, seq, Q.teleportAt) then return end
	EpilogService.teleportWhenReady(player)
	if not waitUntil(player, seq, Q.bridgeAt) then return end
	EpilogService.runBridgeSequence(player)
	if not waitUntil(player, seq, Q.walkAt) then return end
	seq.companion = task.spawn(walkCompanion, player, seq)
	if not waitUntil(player, seq, Q.arriveAt + 0.5) then return end
	finishArrival(player, seq, false)
	if not waitUntil(player, seq, Q.endAt) then return end
	if _seq[player] == seq then _seq[player] = nil end
end

-- Komplette Sequenz-Eroeffnung nach dem Sieg (Prompt 2): erst warten, bis die
-- Kampf-Wiedergabe vorbei ist (der Baerchi ist wieder heim), dann EpilogStart
-- und Teleport (nach EpilogConfig.SUMMIT.teleportDelay, Prompt 5 stellt ihn auf
-- den Flash-Hoehepunkt).
function EpilogService.beginFull(player: Player)
	local waited = 0
	while PitArenaService.isRunning(player) and waited < 60 and player.Parent ~= nil do
		task.wait(0.25)
		waited += 0.25
	end
	if player.Parent == nil then return end
	local data = PlayerService.getData(player)
	if not data or EpilogService.getState(data) ~= S.PENDING then return end
	if not MapService.hasSummit(player) then
		MapService.setSummit(player, true, false)
	end
	-- Prompt 5: Kamerafahrt mit Zeitplan. Ohne Wegdaten (oder mit SEQUENCE.enabled = false)
	-- laeuft der alte Ablauf (Teleport, Bruecke ohne Kamera).
	local Q = EpilogConfig.SEQUENCE
	local route = if Q.enabled then MapService.getEpilogRoute(player) else nil
	if route then
		_seq[player] = nil
		local speed = clampSpeed(_speed[player])
		local seq: Seq = {
			startClock = os.clock(), speed = speed, route = route, thread = nil, companion = nil,
			cancelled = false, skipped = false, arrived = false,
		}
		_seq[player] = seq
		Remotes.EpilogStart:FireClient(player, {
			token = issueToken(player, if speed > 1 then EpilogConfig.SEEN_MIN_SECONDS else 0),
			mode  = EpilogConfig.MODE.FULL,
			state = S.PENDING,
			speed = speed,
			startAt = Workspace:GetServerTimeNow(),
			skipFrom = Q.skipFromSeconds,
			route = route,
		})
		seq.thread = task.spawn(runSequence, player, seq)
		return
	end
	Remotes.EpilogStart:FireClient(player, {
		token = issueToken(player),
		mode  = EpilogConfig.MODE.FULL,
		state = S.PENDING,
	})
	local delay = EpilogConfig.SUMMIT.teleportDelay
	if delay > 0 then task.wait(delay) end
	EpilogService.teleportWhenReady(player)
	-- Prompt 3: Insel entsteht mit dem Sequenzstart, dann waechst die Bruecke.
	if EpilogConfig.BRIDGE.autoStart then
		EpilogService.runBridgeSequence(player)
	end
end

--------------------------------------------------------------------------------
-- Insel und Bruecke (Prompt 3)
--------------------------------------------------------------------------------

-- Erlaubnis fuer den Brueckenbau: Epilog an UND state "pending"/"seen".
local function bridgeAllowed(player: Player): boolean
	if not isEnabled() then return false end
	local data = PlayerService.getData(player)
	if not data then return false end
	local state = EpilogService.getState(data)
	return state == S.PENDING or state == S.SEEN
end

-- Setzt den Avatar vor das Terminal auf die Insel (wartet auf den Charakter).
function EpilogService.placeOnIsland(player: Player, maxWait: number?)
	local waited = 0
	while player.Parent ~= nil and waited < (maxWait or 15) do
		local data = PlayerService.getData(player)
		if data and MapService.isBridgeComplete(player) and player.Character
			and player.Character:FindFirstChild("HumanoidRootPart") then
			MapService.teleportToIsland(player, data.island.equippedUid)
			return
		end
		task.wait(0.25)
		waited += 0.25
	end
end

--------------------------------------------------------------------------------
-- Prompt 6: Knopf-Finale (Server entscheidet, speichert und raeumt auf)
--------------------------------------------------------------------------------

local function finTime(fin: Fin): number
	return (os.clock() - fin.startClock) * fin.speed + fin.jump
end

local function finAlive(player: Player, fin: Fin): boolean
	return _fin[player] == fin and not fin.cancelled and player.Parent ~= nil
end

-- Wartet bis Finale-Zeit `t`. false = abgebrochen/Spieler weg.
local function finWait(player: Player, fin: Fin, t: number): boolean
	while finAlive(player, fin) do
		if finTime(fin) >= t then return true end
		task.wait(0.05)
	end
	return false
end

function EpilogService.isFinaleRunning(player: Player): boolean
	return _fin[player] ~= nil
end

-- Schluss des Finales (normal oder Abbruch): Rakete weg, Gipfel/Insel/Terminal weg,
-- Avatar auf dem Plot, Client beenden. Idempotent. Der Spielstand bleibt "launched".
local function finishFinale(player: Player, fin: Fin, aborted: boolean)
	if _fin[player] ~= fin then return end
	_fin[player] = nil
	fin.cancelled = true
	for _, c in fin.conns do c:Disconnect() end
	table.clear(fin.conns)
	if fin.thread and fin.thread ~= coroutine.running() then
		pcall(task.cancel, fin.thread)
	end
	if player.Parent == nil then return end
	MapService.destroyRocket(player)
	-- Auch bei Abbruch (Tod/Skip-Fehler) keine Reste: alles sofort weg
	if MapService.hasSummit(player) or MapService.hasIsland(player) or MapService.hasTerminal(player) then
		MapService.setSummit(player, false)
	end
	MapService.placeOnPlotIfFar(player, EpilogConfig.FINALE.plotMaxDistance)
	EpilogService.releaseDeferred(player)
	Remotes.EpilogLaunchResult:FireClient(player, { ok = true, phase = "end", aborted = aborted })
end

function EpilogService.cancelFinale(player: Player)
	local fin = _fin[player]
	if not fin then return end
	_fin[player] = nil
	fin.cancelled = true
	for _, c in fin.conns do c:Disconnect() end
	table.clear(fin.conns)
	if fin.thread and fin.thread ~= coroutine.running() then
		pcall(task.cancel, fin.thread)
	end
	if player.Parent ~= nil then
		MapService.destroyRocket(player)
	end
end

local function runFinale(player: Player, fin: Fin)
	local F = EpilogConfig.FINALE
	local T = EpilogConfig.TERMINAL
	local data = PlayerService.getData(player)

	-- Phase 2: Countdown 3 ... 2 ... 1 (Terminal-Bildschirm, Lampen, Bildschirmrand)
	for i, t in F.countTimes do
		if not finWait(player, fin, t) then return end
		MapService.setTerminalCountdown(player, #F.countTimes - i + 1)
	end
	-- Beat vor dem Hoehepunkt: 0,3 s Stille
	if not finWait(player, fin, F.silenceAt) then return end
	MapService.setTerminalCountdown(player, 0)

	-- Phase 3: Start. Die Rakete zuendet; der Client faehrt sie in die Wolken.
	if not finWait(player, fin, F.launchAt) then return end
	MapService.launchRocket(player, true)
	if not finWait(player, fin, F.launchEnd + 0.5) then return end
	MapService.launchRocket(player, false)
	MapService.destroyRocket(player)

	-- Phase 4: Feier (Banner/Himmel/Portal macht der Client). Terminal: "WELT 2 OFFEN".
	if not finWait(player, fin, F.returnAt) then return end
	MapService.setTerminalState(player, T.STATE.DONE)
	EpilogService.releaseDeferred(player)   -- verzoegerte Endless-Meldung jetzt zeigen
	fin.phase = "return"
	Remotes.EpilogLaunchResult:FireClient(player, { ok = true, phase = "return" })

	-- Phase 5: Rueckweg. Flash, Avatar + Begleiter auf den Gipfel ("Zurueck"), Bruecke und
	-- Insel bauen sich ab, danach faehrt der Turm ab (Lift).
	if not finWait(player, fin, F.returnTeleportAt) then return end
	if not MapService.hasSummit(player) then MapService.setSummit(player, true, false) end
	local uid = if data then data.island.equippedUid else nil
	MapService.teleportToSummit(player, uid)
	local removed = false
	MapService.removeIsland(player, true, function() removed = true end)
	local waited = 0
	while not removed and waited < EpilogConfig.BRIDGE.removeSeconds + 4 and finAlive(player, fin) do
		task.wait(0.1)
		waited += 0.1
	end
	if not finAlive(player, fin) then return end
	if MapService.hasSummit(player) then
		MapService.lowerSummit(player, uid, F.lowerSeconds)
	end
	finishFinale(player, fin, false)
end

-- Gemeinsame Pruefung fuer Prompt und Remote. Gibt true oder false + Grund. `force` (Debug)
-- ueberspringt Abstand und Rate-Limit.
local function canStartFinale(player: Player, force: boolean): (boolean, string)
	local F = EpilogConfig.FINALE
	if not isEnabled() or not F.enabled then return false, "disabled" end
	local data = PlayerService.getData(player)
	if not data then return false, "no_data" end
	if _fin[player] then return false, "already_running" end   -- doppelte Anfrage = no-op
	if not bridgeAllowed(player) then return false, "state_not_allowed" end
	if not MapService.hasTerminal(player) then return false, "no_terminal" end
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		return false, "dead"
	end
	if not force then
		local last = _lastPress[player]
		if last and os.clock() - last < F.pressCooldownSeconds then return false, "rate_limit" end
		local mount = MapService.getTerminalMount(player)
		if not mount or (root.Position - mount.Position).Magnitude > F.pressMaxDistance then
			return false, "too_far"
		end
	end
	return true, "ok"
end

-- Phase 1: Freigabe. Prueft, schreibt "launched" + Welt 2 in EINER Mutation, speichert und
-- startet den Ablauf. Rueckgabe true = angenommen. Doppelte/ungueltige Anfragen aendern nichts.
function EpilogService.startFinale(player: Player, source: string, force: boolean?): boolean
	_lastPress[player] = if force == true then _lastPress[player] else os.clock()
	local ok, why = canStartFinale(player, force == true)
	if not ok then
		if why ~= "already_running" then reject(player, "startFinale:" .. source, why) end
		return false
	end
	if not EpilogService.markLaunched(player, true) then
		reject(player, "startFinale:" .. source, "launch_refused")
		return false
	end
	-- Ein noch laufender Anfahrts-Ablauf endet hier (Insel/Terminal bleiben stehen).
	EpilogService.cancelSequence(player)

	local F = EpilogConfig.FINALE
	local speed = math.clamp(_speed[player] or 1, F.minSpeed, F.maxSpeed)
	local fin: Fin = {
		startClock = os.clock(), speed = speed, jump = 0,
		token = HttpService:GenerateGUID(false), thread = nil,
		cancelled = false, skipped = false, phase = "finale", conns = {},
	}
	_fin[player] = fin

	-- Abbruch bei Tod / Charakterwechsel: sofort aufraeumen, State bleibt "launched"
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if humanoid then
		table.insert(fin.conns, humanoid.Died:Connect(function()
			finishFinale(player, fin, true)
		end))
	end
	table.insert(fin.conns, player.CharacterRemoving:Connect(function()
		finishFinale(player, fin, true)
	end))

	MapService.setTerminalState(player, EpilogConfig.TERMINAL.STATE.FIRED)
	MapService.buildRocket(player)
	local info = MapService.getEpilogRoute(player)
	local rocketBase = MapService.getRocketBase(player)
	Remotes.EpilogLaunchResult:FireClient(player, {
		ok = true, phase = "start", token = fin.token, speed = speed,
		startAt = Workspace:GetServerTimeNow(), skipFrom = F.skipFromSeconds,
		route = info, rocketBase = rocketBase,
	})
	fin.thread = task.spawn(function()
		local okRun, err = pcall(runFinale, player, fin)
		if not okRun then
			warn("[EpilogService] Finale fehlgeschlagen fuer", player.Name, ":", err)
			finishFinale(player, fin, true)
		end
	end)
	print("[EpilogService]", player.Name, "| Knopf (", source, ") -> launched, Finale laeuft")
	return true
end

-- Skip des Finales (ab Sekunde skipFromSeconds): springt zum Rueckweg. Token pflicht.
function EpilogService.skipFinale(player: Player, token: any): boolean
	local fin = _fin[player]
	if not fin then return false end
	if typeof(token) ~= "string" or token ~= fin.token then
		reject(player, "EpilogSkip", "finale_wrong_token")
		return true
	end
	local F = EpilogConfig.FINALE
	local f = finTime(fin)
	if fin.phase ~= "finale" or fin.skipped then
		reject(player, "EpilogSkip", "finale_nicht_skippbar")
		return true
	end
	if f < F.skipFromSeconds - F.skipTolerance * fin.speed then
		reject(player, "EpilogSkip", "finale_zu_frueh")
		return true
	end
	fin.skipped = true
	fin.jump += math.max(0, F.returnAt - f)
	return true
end

-- Prompt 4 -> 6: Startwunsch vom Terminal (Prompt voll gehalten, 1,2 s). Der Prompt ist
-- serverseitig, ein Token ist hier nicht noetig. true = angenommen.
function EpilogService.onLaunchRequested(player: Player): boolean
	if MapService.getTerminalState(player) ~= EpilogConfig.TERMINAL.STATE.ARMED then
		reject(player, "onLaunchRequested", "not_armed")
		return false
	end
	return EpilogService.startFinale(player, "prompt", false)
end

-- Insel enthuellen (3 s), danach die Bruecke Planke fuer Planke wachsen lassen.
-- `onDone` laeuft, wenn der Lichtimpuls die Insel erreicht hat. Prompt 5 ruft das
-- zum Kamera-Zeitpunkt (BRIDGE.autoStart = false). Bedingungen (Zustand, lebt,
-- am Gipfel) prueft EpilogIslandBuilder; hier wird nur kurz gewartet, bis sie stimmen.
function EpilogService.runBridgeSequence(player: Player, onDone: (() -> ())?)
	task.spawn(function()
		if not MapService.hasIsland(player) then
			if not MapService.buildIsland(player, true) then
				warn("[EpilogService] Insel konnte nicht gebaut werden fuer", player.Name)
				return
			end
		end
		local waited = 0
		local limit = EpilogConfig.BRIDGE.retrySeconds + EpilogConfig.ISLAND.revealSeconds
		while player.Parent ~= nil and waited < limit do
			local ok, why = MapService.growBridge(player, function()
				-- Prompt 4: das Terminal steht, sobald die Bruecke fertig ist
				MapService.buildTerminal(player)
				if onDone then onDone() end
			end)
			if ok or (why ~= "island_not_revealed" and why ~= "player_not_at_summit" and why ~= "player_dead") then
				if not ok and why ~= "already_growing" and why ~= "already_complete" then
					warn("[EpilogService] Bruecke nicht gebaut:", why)
				end
				return
			end
			task.wait(0.5)
			waited += 0.5
		end
	end)
end

--------------------------------------------------------------------------------
-- Schnittstellen/Stubs fuer Prompt 2-6
--------------------------------------------------------------------------------

-- Prompt 6: Ablauf nach gueltigem Knopfdruck.
function EpilogService.setPressHandler(handler: (Player, Types.PlayerData) -> ())
	_pressHandler = handler
end

-- Prompt 2/3: platziert den Spieler (state, ohne Kamerafahrt). "pending" ->
-- Gipfel, "seen" -> Insel. Der Handler baut die Teile bei Bedarf auf.
function EpilogService.setPlaceHandler(handler: (Player, Types.PlayerData, string) -> ())
	_placeHandler = handler
end

-- Wiedereinstieg beim Join mit "pending"/"seen": KEINE Kamerafahrt. Stub: die
-- Platzierung kommt aus Prompt 2 (Gipfel) und 3 (Insel). Schickt ein frisches
-- Token mit mode = "restore" (Client in Prompt 5 baut daraus die ruhige Szene).
function EpilogService.restore(player: Player)
	if not isEnabled() then return end
	local data = PlayerService.getData(player)
	if not data then return end
	local state = EpilogService.getState(data)
	-- Prompt 6: "launched" (Spieler kam beim Finale/Rueckweg heraus): Gipfel, Insel, Terminal
	-- und Rakete gibt es nach dem Join nicht mehr; sicherheitshalber alles wegraeumen, den
	-- Turm freigeben und den Avatar auf den Plot setzen. Keine Effekte, keine Fahrt.
	if state == S.LAUNCHED then
		if _fin[player] == nil then
			MapService.setSummit(player, false)
			MapService.placeOnPlotIfFar(player, EpilogConfig.FINALE.plotMaxDistance)
		end
		return
	end
	if state ~= S.PENDING and state ~= S.SEEN then return end

	-- Prompt 2: "pending" -> Gipfel samt Teleport, ohne Fahrt. "seen" -> Insel
	-- (Prompt 3, ueber den Platzier-Handler).
	if state == S.PENDING then
		if MapService.setSummit(player, true, false) then
			-- ANNAHME (Prompt 3): auch bei "pending" steht die Bruecke fertig da, sonst
			-- haengt der Spieler ohne Kamerafahrt auf dem Gipfel fest. Der Avatar
			-- steht auf dem Gipfel und kann hinueber laufen.
			MapService.buildIsland(player, false)
			MapService.buildBridgeInstant(player)
			MapService.buildTerminal(player)   -- Prompt 4
			task.spawn(EpilogService.teleportWhenReady, player)
		end
	elseif state == S.SEEN then
		-- Prompt 3: Insel + fertige Bruecke sofort, Avatar vor das Terminal.
		if MapService.setSummit(player, true, false) then
			MapService.buildIsland(player, false)
			MapService.buildBridgeInstant(player)
			MapService.buildTerminal(player)   -- Prompt 4
			task.spawn(EpilogService.placeOnIsland, player)
		end
	end
	local handler = _placeHandler
	if handler then
		local ok, err = pcall(handler, player, data, state)
		if not ok then
			warn("[EpilogService] Platzieren fehlgeschlagen fuer", player.Name, ":", err)
		end
	end
	Remotes.EpilogStart:FireClient(player, {
		token = issueToken(player),
		mode  = EpilogConfig.MODE.RESTORE,
		state = state,
	})
end

--------------------------------------------------------------------------------
-- Debug (nur ueber DebugService)
--------------------------------------------------------------------------------

-- start: erzwingt eine NEUE Sequenz (state -> pending), unabhaengig vom Rekord.
function EpilogService.debugStart(player: Player): (boolean, string)
	local data = PlayerService.getData(player)
	if not data then return false, "no_data" end
	if EpilogService.getState(data) ~= S.NONE then
		return false, "state_not_none:" .. EpilogService.getState(data)
	end
	_lastStartClock[player] = nil
	local started = EpilogRules.applyFinalClear(data, os.time())
	PlayerService.markDirty(player)
	if started then
		MapService.setSummit(player, true, true)
		task.spawn(EpilogService.beginFull, player)
	end
	return started, "ok"
end

function EpilogService.debugReset(player: Player)
	local data = PlayerService.getData(player)
	if not data then return end
	EpilogService.cancelSequence(player)
	EpilogService.cancelFinale(player)
	EpilogRules.reset(data.epilog)
	MapService.setSummit(player, false)
	_tokens[player] = nil
	_lastStartClock[player] = nil
	EpilogService.releaseDeferred(player)
	PlayerService.markDirty(player)
end

-- launch: spielt das Knopf-Finale (Prompt 6) von hier aus: baut bei Bedarf Gipfel, Insel,
-- Bruecke und Terminal sofort, setzt den Avatar vor das Terminal und loest den Knopf aus.
-- `launch fast`: wie bisher nur Spielstand (launched + Welt 2), ohne Finale (Folgen testen).
function EpilogService.debugLaunch(player: Player, mode: string?): boolean
	local data = PlayerService.getData(player)
	if not data then return false end
	local state = EpilogService.getState(data)
	if state == S.LAUNCHED then return false end
	if state == S.NONE then
		EpilogRules.applyFinalClear(data, os.time())
		state = S.PENDING
	end
	if mode == "fast" then
		if state == S.PENDING then
			EpilogRules.transition(data.epilog, S.SEEN, os.time())
		end
		MapService.setSummit(player, false)   -- ohne Finale: Gipfel sofort weg
		return EpilogService.markLaunched(player)
	end
	if _fin[player] then return false end
	if not MapService.hasSummit(player) then MapService.setSummit(player, true, false) end
	if not MapService.hasIsland(player) then MapService.buildIsland(player, false) end
	if not MapService.isBridgeComplete(player) then MapService.buildBridgeInstant(player) end
	if not MapService.hasTerminal(player) then MapService.buildTerminal(player) end
	EpilogService.placeOnIsland(player, 5)
	MapService.setTerminalState(player, EpilogConfig.TERMINAL.STATE.ARMED)
	return EpilogService.startFinale(player, "debug", true)
end

-- summit [off]: Gipfel ohne Zustandswechsel bauen/entfernen (Test).
function EpilogService.debugSummit(player: Player, on: boolean): boolean
	local ok = MapService.setSummit(player, on, true)
	if ok and on then task.spawn(EpilogService.teleportWhenReady, player) end
	return ok
end

-- bridge [instant|off]: Insel + Bruecke testen (verlangt state pending/seen,
-- also vorher `epilog start`). Setzt den Avatar auf den Gipfel und laesst die
-- Bruecke wachsen; "instant" baut sofort, "off" baut animiert ab.
function EpilogService.debugBridge(player: Player, act: string): (boolean, string)
	local data = PlayerService.getData(player)
	if not data then return false, "no_data" end
	if act == "bridgeoff" then
		MapService.removeIsland(player, true)
		return true, "removing"
	end
	if not bridgeAllowed(player) then
		return false, "state_not_pending_or_seen (epilog start first)"
	end
	if not MapService.hasSummit(player) then
		MapService.setSummit(player, true, false)
	end
	if act == "bridgeinstant" then
		MapService.buildIsland(player, false)
		local ok, why = MapService.buildBridgeInstant(player)
		task.spawn(EpilogService.teleportWhenReady, player)
		return ok, why
	end
	task.spawn(function()
		EpilogService.teleportWhenReady(player)
		EpilogService.runBridgeSequence(player)
	end)
	return true, "started"
end

-- terminal [zustand]: Terminal testen (verlangt state pending/seen). Ohne Zustand:
-- `ready`. "fired" spielt die Ausloese-Animation (erst armed, dann fired). Baut bei
-- Bedarf Gipfel, Insel und Bruecke sofort. Speichert nichts.
function EpilogService.debugTerminal(player: Player, wanted: string?): (boolean, string)
	local ST = EpilogConfig.TERMINAL.STATE
	local data = PlayerService.getData(player)
	if not data then return false, "no_data" end
	if wanted == "off" then
		EpilogTerminalBuilder.destroy(player)
		return true, "removed"
	end
	if not bridgeAllowed(player) then
		return false, "state_not_pending_or_seen (epilog start first)"
	end
	local target = wanted or ST.READY
	local valid = false
	for _, v in ST do if v == target then valid = true end end
	if not valid then return false, "unknown_state" end
	if not MapService.hasSummit(player) then MapService.setSummit(player, true, false) end
	if not MapService.hasIsland(player) then MapService.buildIsland(player, false) end
	if not MapService.isBridgeComplete(player) then MapService.buildBridgeInstant(player) end
	if not MapService.hasTerminal(player) then MapService.buildTerminal(player) end
	if not MapService.hasTerminal(player) then return false, "terminal_not_built" end
	if target == ST.FIRED then
		MapService.setTerminalState(player, ST.ARMED)
		task.delay(EpilogConfig.TERMINAL.debugArmedSeconds, function()
			if MapService.hasTerminal(player) then MapService.setTerminalState(player, ST.FIRED) end
		end)
		return true, "armed -> fired"
	end
	MapService.setTerminalState(player, target)
	return true, target
end

-- speed N: Zeitraffer fuer den naechsten Start (0,5 bis 5). Zeitplan, Lauf und Kamera
-- laufen dann N-mal so schnell; das Token wird zurueckdatiert, damit EpilogSeen durchgeht.
function EpilogService.debugSpeed(player: Player, value: any): number
	local n = tonumber(value)
	_speed[player] = if n then clampSpeed(n) else nil
	return _speed[player] or 1
end

-- audit: fragt den Client nach Kamera-, Lighting-, Steuerungs- und Verbindungszustand
-- (muss nach jedem Durchlauf sauber sein) und haengt den Serverstand an.
function EpilogService.debugAudit(player: Player): { [string]: any }
	local waiting = { thread = coroutine.running(), done = false }
	_auditWait[player] = waiting
	Remotes.EpilogDebug:FireClient(player, { cmd = "audit" })
	task.delay(3, function()
		if _auditWait[player] == waiting and not waiting.done then
			waiting.done = true
			_auditWait[player] = nil
			task.spawn(waiting.thread, { fehler = "no_client_reply" })
		end
	end)
	local report = coroutine.yield()
	local seq = _seq[player]
	return {
		client = report,
		server = {
			fahrtLaeuft = seq ~= nil,
			uebersprungen = seq ~= nil and seq.skipped,
			angekommen = seq ~= nil and seq.arrived,
			zeitraffer = _speed[player] or 1,
			endlessGehalten = _deferred[player] ~= nil,
			finaleLaeuft = _fin[player] ~= nil,
			finalePhase = if _fin[player] then _fin[player].phase else nil,
		},
	}
end

-- Gibt das aktuelle Token zurueck (nur Studio-Test der Remotes).
function EpilogService.debugToken(player: Player): any
	local entry = _tokens[player]
	return if entry then entry.id else nil
end

-- Sicherungs-Scan: Spieler mit Final-Rekord >= 100, aber Zustand "none"
-- (z. B. Flag war beim Sieg aus). Meldet nur, aendert nichts.
function EpilogService.debugScan(player: Player, data: Types.PlayerData): { [string]: any }
	local def = TowerConfig.get(EpilogConfig.TOWER_ID)
	local record = data.towers.records[EpilogConfig.TOWER_ID] or 0
	return {
		finalRekord   = record,
		endlessOffen  = data.towers.unlocked.Endless == true,
		endlessRekord = data.towers.records.Endless or 0,
		epilogState   = EpilogService.getState(data),
		luecke        = def ~= nil and record >= def.stages and EpilogService.getState(data) == S.NONE,
		welt2         = data.worlds.unlocked[EpilogConfig.WORLD2_ID] == true,
		verworfen     = _rejectedTotal,
		-- Prompt 2
		gipfel        = MapService.hasSummit(player),
		gipfelTeile   = MapService.countSummitParts(player),
		turmGehalten  = MapService.getTowerHold(player),
		reste         = MapService.epilogLeftover(player),
		-- Prompt 3
		insel         = MapService.hasIsland(player),
		bruecke       = MapService.isBridgeComplete(player),
		brueckeWaechst = MapService.isBridgeGrowing(player),
		inselTeile    = (MapService.countIslandParts(player)),
		brueckenTeile = select(2, MapService.countIslandParts(player)),
		workspace     = EpilogIslandBuilder.scanWorkspace(),
		-- Prompt 4
		terminal      = MapService.hasTerminal(player),
		terminalZustand = MapService.getTerminalState(player),
		terminalTeile = MapService.countTerminalParts(player),
		-- Prompt 6
		finaleLaeuft  = _fin[player] ~= nil,
		raketeTeile   = MapService.countRocketParts(player),
	}
end

--------------------------------------------------------------------------------
-- Initialisierung
--------------------------------------------------------------------------------

function EpilogService.init()
	RateLimiter.connect(Remotes.EpilogSeen, "EpilogSeen", function(player, token: any)
		handleSeen(player, token)
	end)
	RateLimiter.connect(Remotes.EpilogSkip, "EpilogSkip", function(player, token: any)
		handleSkip(player, token)
	end)
	RateLimiter.connect(Remotes.RequestPressLaunch, "RequestPressLaunch", function(player, token: any)
		handlePress(player, token)
	end)

	-- Prompt 5 (Debug): Bericht des Clients, nur wenn der Server ihn angefordert hat.
	RateLimiter.connect(Remotes.EpilogDebugReport, "EpilogDebugReport", function(player, report: any)
		local waiting = _auditWait[player]
		if not waiting or waiting.done or typeof(report) ~= "table" then return end
		waiting.done = true
		_auditWait[player] = nil
		task.spawn(waiting.thread, report)
	end)

	-- Prompt 3: die Bruecke wird nur gebaut, solange der Zustand es erlaubt.
	EpilogIslandBuilder.setGuard(bridgeAllowed)
	-- Prompt 4: Terminal-Prompt nur bei erlaubtem Zustand; Startwunsch geht an onLaunchRequested.
	EpilogTerminalBuilder.setAccessCheck(bridgeAllowed)
	EpilogTerminalBuilder.setLaunchHandler(function(player: Player)
		EpilogService.onLaunchRequested(player)
	end)

	-- Wiedereinstieg: NACH allen onDataLoaded (Plot und Charakter stehen dann).
	PlayerService.onPlayerReady(function(player, _data)
		EpilogService.restore(player)
	end)

	-- Cleanup: Token/Cache frei. Die Sequenz ueberlebt das Verlassen nur ueber
	-- den gespeicherten Zustand.
	Players.PlayerRemoving:Connect(function(player)
		EpilogService.cancelSequence(player)
		EpilogService.cancelFinale(player)
		_lastPress[player] = nil
		_speed[player] = nil
		_auditWait[player] = nil
		_tokens[player] = nil
		_lastStartClock[player] = nil
		_deferred[player] = nil
		_rejected[player] = nil
	end)

	print("[EpilogService] Initialisiert | Schalter", EpilogConfig.FLAG, "=", isEnabled())
end

return EpilogService
