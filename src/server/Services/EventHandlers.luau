--!strict
-- EventHandlers.luau
-- ServerScriptService/Services/EventHandlers.luau
--
-- Einzige Zustaendigkeit:
--   - Den Ablauf der fuenf Events in der Event-Area spielen:
--     Ufo, HotEgg, MutationsSturm, Koenigshuegel, Schatzgraeber
--
-- Kein eigener Eintrag im GameManager: EventParticipationService ruft den
-- passenden Handler beim Event-Start auf. Das sechste Event (Wespenkoenigin)
-- steht wegen seiner Groesse in Util/WaspQueenEvent; gemeinsame Typen und
-- Werkzeuge in Util/EventKit.
--
-- Bewegte Dinge (UFO, Kisten, Koenigin) sind reine Funktionen der Serverzeit
-- (Modules/EventMotion): der Server schreibt nur die Startzeit als Attribut,
-- der Client (EventFXController) bewegt die Optik. Waben-Themen und
-- fliegende Waben laufen ueber CombService (setTheme, launchCombs).
--
-- Jeder Handler hat die Signatur   handler(api, def) -> session
-- und die Session hat   session.stop() -> results
-- wobei results = { [Player] = { egg = EventBonus?, mutationRoll = boolean? } }
-- die Belohnungen sind, die EventParticipationService am Event-ENDE auszahlt.
-- (Das UFO zahlt seine Belohnung schon beim Absetzen aus, dort ist results leer.)
--
-- `api` stellt EventParticipationService bereit (siehe dort, buildApi): die
-- Handler fassen weder Spielerdaten noch ActivityLock direkt an, sie laufen
-- nur mit Figuren ueber api.walkTo und lesen api.participants().
--
-- Zahlen, die das Spiel veraendern (Dauern, Abstaende, Abklingzeiten,
-- Zufallsstreuung), stehen in EventConfig. Reine Optik (Farben, Groessen,
-- Animationszeiten) steht als benannte Konstante unten in dieser Datei.

local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local Workspace           = game:GetService("Workspace")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local EventConfig     = require(ReplicatedStorage.Config.EventConfig)
local FigureFX        = require(ServerScriptService.Util.FigureFX)
local FigurePlacement = require(ServerScriptService.Util.FigurePlacement)
local EventKit        = require(ServerScriptService.Util.EventKit)
local JackpotRoll     = require(ServerScriptService.Util.JackpotRoll)
local WaspQueenEvent  = require(ServerScriptService.Util.WaspQueenEvent)
local CombService     = require(ServerScriptService.Services.CombService)
local EventMotion     = require(ReplicatedStorage.Modules.EventMotion)
local Loc             = require(ReplicatedStorage.Localization.Loc)

local EventHandlers = {}

--------------------------------------------------------------------------------
-- Typen (stehen in Util/EventKit, hier unter den gewohnten Namen)
--------------------------------------------------------------------------------

export type Part    = EventKit.Part
export type Api     = EventKit.Api
export type Reward  = EventKit.Reward
export type Session = EventKit.Session
export type Handler = EventKit.Handler

--------------------------------------------------------------------------------
-- Optik (keine Balance — aendert nur, wie es aussieht)
--------------------------------------------------------------------------------

-- Duell: abwechselnde Ausfallschritte, am Ende blitzt der Verlierer rot
local DUEL_LUNGE_DISTANCE      = 2
local DUEL_LUNGE_SECONDS       = 0.3
local DUEL_LUNGE_GAP_SECONDS   = 0.35
local DUEL_END_MARGIN_SECONDS  = 0.4
local DUEL_LOSER_FLASH_COLOR   = Color3.fromRGB(255, 80, 80)
local DUEL_LOSER_FLASH_SECONDS = 0.6

-- Wer jemanden beruehren soll, laeuft auf diesen Anteil von TOUCH_DISTANCE
-- heran — sicher innerhalb, ohne in die andere Figur zu laufen.
local APPROACH_SHARE = 0.7
-- Wer auf den Beam/Huegel zulaeuft, steuert diesen Anteil des Radius an.
local INNER_TARGET_SHARE = 0.5

-- Wartendes Wippen (im Beam) und Jubel-Wippen (nach Weitergabe/Huegel)
local WAIT_BOB    = { height = 0.8, rate = 1.1 }
local CHEER_BOB   = { height = 1.6, rate = 2.2 }
local DIG_BOB     = { height = 0.35, rate = 3 }

-- UFO
local UFO_HOVER_HEIGHT        = EventMotion.UFO_HOVER_HEIGHT
local UFO_COLOR               = Color3.fromRGB(120, 255, 190)
local UFO_CLOSED_COLOR        = Color3.fromRGB(255, 90, 90)
local UFO_DISC_COLOR          = Color3.fromRGB(170, 180, 195)
local UFO_DISC_SIZE           = Vector3.new(3, 26, 26)
local UFO_DOME_SIZE           = Vector3.new(12, 10, 12)
local UFO_DOME_LIFT           = 3
local UFO_DOME_TRANSPARENCY   = 0.3
local UFO_BEAM_TRANSPARENCY   = 0.65
local UFO_RING_TRANSPARENCY   = 0.3
local UFO_RING_CLOSED_TRANSPARENCY = 0.85
local UFO_RING_THICKNESS      = 0.3
local UFO_RING_LIFT           = 0.25
local UFO_BURST_COUNT         = 24
-- Entfuehrung: hoch zum UFO, rueber zum Plot, schweben, absetzen
local UFO_PICKUP_BELOW_DISC   = 6
local UFO_LIFT_SECONDS        = 2.0
local UFO_LIFT_TURNS          = 2
local UFO_TRANSPORT_HEIGHT    = 40
local UFO_TRANSPORT_SECONDS   = 3.0
local UFO_TRANSPORT_TURNS     = 1
local UFO_HOVER_BOB_HEIGHT    = 1.2
local UFO_HOVER_BOB_RATE      = 2
local UFO_HOVER_SPIN_RATE     = 1.5
local UFO_HOVER_STEP_SECONDS  = 0.1
local UFO_DROP_HEIGHT         = 4
local UFO_DROP_SECONDS        = 1.5
-- Abgeworfene Kiste (die Kiste bewegt der Client, siehe EventFXController)
local CRATE_SIZE              = Vector3.new(3, 3, 3)
local CRATE_COLOR             = Color3.fromRGB(150, 105, 60)
local CRATE_GOLD_COLOR        = Color3.fromRGB(255, 205, 60)
local CANOPY_SIZE             = Vector3.new(8, 3, 8)
local CANOPY_LIFT             = 6
local CANOPY_COLOR            = Color3.fromRGB(120, 255, 190)
local MARK_THICKNESS          = 0.25
local MARK_TRANSPARENCY       = 0.35
local MARK_COLOR              = Color3.fromRGB(120, 255, 190)
local MARK_GOLD_COLOR         = Color3.fromRGB(255, 215, 70)
local PILLAR_HEIGHT           = 90
local PILLAR_WIDTH            = 2.2
local PILLAR_TRANSPARENCY     = 0.45

-- Hot Egg: Warnring vor dem Vulkan-Ausbruch
local ERUPTION_RING_RADIUS    = 7
local ERUPTION_RING_COLOR     = Color3.fromRGB(255, 90, 30)
local ERUPTION_RING_THICKNESS = 0.35
local ERUPTION_ORIGIN_LIFT    = 2

-- Hot Egg
local HOT_EGG_FIRE_SIZE       = 8
local HOT_EGG_FIRE_HEAT       = 6
local HOT_EGG_FIRE_COLOR      = Color3.fromRGB(255, 120, 40)
local HOT_EGG_FIRE_COLOR_2    = Color3.fromRGB(255, 60, 20)
-- Etwas Spielraum beim Uebergeben: die Figur bleibt APPROACH_SHARE vor dem
-- Ziel stehen, der Laufweg ist aber nicht zentimetergenau.
local HOT_EGG_PASS_SLACK      = 1.5

-- Mutations-Sturm
local STORM_COLOR             = Color3.fromRGB(255, 90, 235)
local STORM_BOLT_SIZE         = Vector3.new(0.8, 70, 0.8)
local STORM_BOLT_TRANSPARENCY = 0.1
local STORM_BOLT_SECONDS      = 0.3
local STORM_BURST_LIFT        = 2
local STORM_BURST_COUNT       = 24
local STORM_FLASH_SECONDS     = 0.5
local STORM_CLEANUP_SECONDS   = 1

-- Koenigshuegel
local HILL_COLOR              = Color3.fromRGB(255, 215, 70)
local HILL_TRANSPARENCY       = 0.45
local HILL_THICKNESS          = 0.4
local HILL_LIFT               = 0.3

-- Schatzgraeber
local MOUND_SIZE              = Vector3.new(4, 1.6, 4)
local MOUND_LIFT              = 0.6
local MOUND_COLOR             = Color3.fromRGB(120, 85, 50)
local BOMB_BLAST_RADIUS       = 6     -- nur Optik: BlastPressure ist 0
local BOMB_COLLAPSE_SECONDS   = 0.8
local FIND_COLOR              = Color3.fromRGB(255, 220, 90)
local FIND_BURST_LIFT         = 1
local FIND_BURST_COUNT        = 20
-- Wie oft waehrend des Grabens geprueft wird, ob abgebrochen wurde, und wie
-- oft neue Teilnehmer ihren Lauf bekommen.
local DIG_CHECK_SECONDS       = 0.25
local TREASURE_JOIN_CHECK_SECONDS = 1

--------------------------------------------------------------------------------
-- Hilfen
--------------------------------------------------------------------------------

local flatDist  = EventKit.flatDist
local make      = EventKit.make
local fxPart    = EventKit.fxPart
local rootOf    = EventKit.rootOf
local setLabel  = EventKit.setLabel
local newFolder = EventKit.newFolder

-- Kurzer Kampf zweier Teilnehmer: serverseitiger Vergleich (ATK/HP-basiert,
-- siehe api.power) mit etwas Zufall. Dauert fix `seconds`. Gibt Gewinner und
-- Verlierer zurueck.
local function duel(api: Api, a: Part, b: Part, seconds: number): (Part, Part)
	local spread = EventConfig.DUEL.POWER_SPREAD
	local ra = api.power(a) * (1 - spread + math.random() * spread * 2)
	local rb = api.power(b) * (1 - spread + math.random() * spread * 2)

	local winner, loser = a, b
	if rb > ra then
		winner, loser = b, a
	end

	local startedAt = os.clock()
	task.spawn(function()
		while os.clock() - startedAt < seconds - DUEL_END_MARGIN_SECONDS and api.running() do
			if a.figure and b.figure and a.figure.Parent and b.figure.Parent then
				pcall(FigureFX.attackLunge, a.figure, b.figure:GetPivot().Position, DUEL_LUNGE_DISTANCE, DUEL_LUNGE_SECONDS)
				task.wait(DUEL_LUNGE_GAP_SECONDS)
				pcall(FigureFX.attackLunge, b.figure, a.figure:GetPivot().Position, DUEL_LUNGE_DISTANCE, DUEL_LUNGE_SECONDS)
				task.wait(DUEL_LUNGE_GAP_SECONDS)
			else
				break
			end
		end
	end)

	task.wait(seconds)

	if loser.figure and loser.figure.Parent then
		pcall(FigureFX.hitFlash, loser.figure, DUEL_LOSER_FLASH_COLOR, DUEL_LOSER_FLASH_SECONDS)
	end

	return winner, loser
end

local function moveFoot(figure: Model, from: Vector3, to: Vector3, seconds: number, spin: number?)
	local startedAt = os.clock()
	while true do
		local t = math.clamp((os.clock() - startedAt) / seconds, 0, 1)
		FigurePlacement.place(
			figure,
			from:Lerp(to, t),
			CFrame.Angles(0, (spin or 0) * t, 0)
		)
		if t >= 1 then
			break
		end
		RunService.Heartbeat:Wait()
	end
end

--------------------------------------------------------------------------------
-- UFO
--------------------------------------------------------------------------------

type UfoState = {
	progress   : number,
	moving     : boolean,
	fightUntil : number,
	coolUntil  : number,
	abducting  : boolean,
	inBeam     : boolean,
}

function EventHandlers.Ufo(api: Api, def: EventConfig.EventDef): Session
	local cfg    = EventConfig.UFO
	local center = api.center
	local ringR  = api.radius * cfg.BEAM_RADIUS_FACTOR
	local hoverY = center.Y + UFO_HOVER_HEIGHT

	local running    = true
	local beamOpen   = true
	local idleTimer  = 0
	local fightPause = 0
	local states: { [Part]: UfoState } = {}
	local taken: { [Player]: boolean } = {}     -- in DIESEM Event schon entfuehrt
	local pairCool: { [string]: number } = {}   -- ["uidA|uidB"] = os.clock(), bis zu dem nicht erneut gekaempft wird

	local folder = newFolder("EventUfo")

	-- PATROUILLE: das UFO fliegt auf der Bahn aus EventMotion. Der Server
	-- rechnet nur Positionen aus (Beam, Abwurf), bewegt aber nichts: die
	-- Teile stehen am Startpunkt, der Client zieht das Model jedes Frame aus
	-- derselben Funktion nach (Attribute StartTime/Center am Ordner).
	local startTime = Workspace:GetServerTimeNow()
	folder:SetAttribute("StartTime", startTime)
	folder:SetAttribute("Center", center)

	local function ringCenterAt(serverTime: number): Vector3
		return EventMotion.ufoGround(center, startTime, serverTime)
	end

	local ufoModel = Instance.new("Model")
	ufoModel.Name = "Ufo"
	ufoModel.Parent = folder

	local ground0 = ringCenterAt(startTime)

	-- UFO-Optik: Scheibe, Kuppel, Beam, Ring am Boden (alles im Model, ein
	-- PivotTo pro Frame beim Client)
	local discPos = Vector3.new(ground0.X, hoverY, ground0.Z)
	fxPart({
		Name = "Disc", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Metal,
		Color = UFO_DISC_COLOR, Size = UFO_DISC_SIZE,
		CFrame = CFrame.new(discPos) * CFrame.Angles(0, 0, math.rad(90)),
	}, ufoModel)
	fxPart({
		Name = "Dome", Shape = Enum.PartType.Ball, Material = Enum.Material.Glass,
		Color = UFO_COLOR, Transparency = UFO_DOME_TRANSPARENCY, Size = UFO_DOME_SIZE,
		CFrame = CFrame.new(discPos + Vector3.new(0, UFO_DOME_LIFT, 0)),
	}, ufoModel)
	local beamHeight = hoverY - center.Y
	local beam = fxPart({
		Name = "Beam", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon,
		Color = UFO_COLOR, Transparency = UFO_BEAM_TRANSPARENCY,
		Size = Vector3.new(beamHeight, ringR * 2, ringR * 2),
		CFrame = CFrame.new(Vector3.new(ground0.X, center.Y + beamHeight / 2, ground0.Z)) * CFrame.Angles(0, 0, math.rad(90)),
	}, ufoModel)
	local ring = fxPart({
		Name = "Ring", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon,
		Color = UFO_COLOR, Transparency = UFO_RING_TRANSPARENCY,
		Size = Vector3.new(UFO_RING_THICKNESS, ringR * 2, ringR * 2),
		CFrame = CFrame.new(Vector3.new(ground0.X, center.Y + UFO_RING_LIFT, ground0.Z)) * CFrame.Angles(0, 0, math.rad(90)),
	}, ufoModel)
	-- Drehpunkt = Bodenpunkt unter dem UFO: der Client setzt das Model mit
	-- PivotTo(CFrame.new(EventMotion.ufoGround(...))) genau dorthin.
	ufoModel.WorldPivot = CFrame.new(ground0)

	local function setBeam(open: boolean)
		beamOpen = open
		beam.Transparency = if open then UFO_BEAM_TRANSPARENCY else 1
		ring.Transparency = if open then UFO_RING_TRANSPARENCY else UFO_RING_CLOSED_TRANSPARENCY
		ring.Color        = if open then UFO_COLOR else UFO_CLOSED_COLOR
	end

	local function stateOf(part: Part): UfoState
		local st = states[part]
		if not st then
			st = { progress = 0, moving = false, fightUntil = 0, coolUntil = 0, abducting = false, inBeam = false }
			states[part] = st
		end
		return st
	end

	local function abduct(part: Part, st: UfoState)
		st.abducting     = true
		part.abducting   = true
		taken[part.player] = true
		setLabel(part, Loc.msg("ev.label.abducted"))

		task.spawn(function()
			local ok, err = pcall(function()
				local figure = part.figure
				local player = part.player
				api.toast(player, Loc.msg("ev.ufo.abducted"))

				local startFoot = api.footOf(figure)
				local here      = ringCenterAt(Workspace:GetServerTimeNow())
				local ufoFoot   = Vector3.new(here.X, hoverY - UFO_PICKUP_BELOW_DISC, here.Z)
				pcall(FigureFX.burstAt, startFoot, UFO_COLOR, folder, UFO_BURST_COUNT)

				-- 1) hochgezogen
				FigureFX.stopIdle(figure)
				moveFoot(figure, startFoot, ufoFoot, UFO_LIFT_SECONDS, math.pi * 2 * UFO_LIFT_TURNS)

				-- 2) Transport zum Plot des Spielers
				local plotPos = api.plotPosition(player)
				local overPlot = (plotPos or ufoFoot) + Vector3.new(0, UFO_TRANSPORT_HEIGHT, 0)
				setLabel(part, Loc.msg("ev.label.transport"))
				moveFoot(figure, ufoFoot, overPlot, UFO_TRANSPORT_SECONDS, math.pi * 2 * UFO_TRANSPORT_TURNS)

				-- 3) Wartezeit ueber dem Plot
				local waitStart = os.clock()
				while os.clock() - waitStart < cfg.ABDUCT_WAIT_SECONDS do
					local left = math.ceil(cfg.ABDUCT_WAIT_SECONDS - (os.clock() - waitStart))
					setLabel(part, Loc.msg("ev.label.landing", { s = left }))
					local hovered = os.clock() - waitStart
					FigurePlacement.place(
						figure,
						overPlot + Vector3.new(0, math.sin(hovered * UFO_HOVER_BOB_RATE) * UFO_HOVER_BOB_HEIGHT, 0),
						CFrame.Angles(0, hovered * UFO_HOVER_SPIN_RATE, 0)
					)
					task.wait(UFO_HOVER_STEP_SECONDS)
				end

				-- 4) Absetzen auf dem Plot
				setLabel(part, nil)
				local homeFoot = part.homeFoot
				moveFoot(figure, overPlot, homeFoot + Vector3.new(0, UFO_DROP_HEIGHT, 0), UFO_DROP_SECONDS, 0)
				api.finishHome(part)
				api.ufoReward(part)
			end)

			if not ok then
				warn("[EventHandlers.Ufo] Entfuehrung fehlgeschlagen:", err)
				pcall(setLabel, part, nil)
				pcall(api.finishHome, part)
			end
		end)
	end

	local function startFight(a: Part, b: Part, sa: UfoState, sb: UfoState, now: number)
		sa.fightUntil = now + cfg.FIGHT_SECONDS
		sb.fightUntil = now + cfg.FIGHT_SECONDS
		fightPause    = now + cfg.FIGHT_SECONDS
		a.cancelWalk, b.cancelWalk = true, true
		setLabel(a, Loc.msg("ev.label.fight"))
		setLabel(b, Loc.msg("ev.label.fight"))

		task.spawn(function()
			local ok, err = pcall(function()
				local winner, loser = duel(api, a, b, cfg.FIGHT_SECONDS)
				local sw, sl = stateOf(winner), stateOf(loser)

				-- Verlierer: aus dem Ring gedraengt, beginnt von vorne.
				sl.progress  = 0
				sl.coolUntil = os.clock() + cfg.LOSER_COOLDOWN_SECONDS
				api.toast(loser.player, Loc.msg("ev.ufo.fight_lost"))
				api.toast(winner.player, Loc.msg("ev.ufo.fight_won"))
				setLabel(winner, nil)
				setLabel(loser, nil)

				sl.moving = true
				task.spawn(function()
					api.walkTo(loser, loser.standFoot)
					sl.moving = false
				end)
				sw.fightUntil = 0
			end)
			if not ok then
				warn("[EventHandlers.Ufo] Kampf fehlgeschlagen:", err)
			end
		end)
	end

	local function closeBeam()
		for part, st in states do
			st.progress = 0
			setLabel(part, nil)
		end
		for _, part in api.participants() do
			api.toast(part.player, Loc.msg("ev.ufo.beam_reset"))
		end
		setBeam(false)
		task.delay(cfg.BEAM_REOPEN_SECONDS, function()
			if running then
				idleTimer = 0
				setBeam(true)
			end
		end)
	end

	for _, part in api.participants() do
		api.toast(part.player, Loc.msg("ev.ufo.go_beam", { s = cfg.BEAM_REQUIRED_SECONDS }))
	end
	api.announce(Loc.msg("msg.ufo.patrol"), "info")

	local dt = cfg.TICK_SECONDS
	task.spawn(function()
		while running do
			task.wait(dt)
			local ok, err = pcall(function()
				local parts = api.participants()
				local now   = os.clock()
				local anyInBeam = false
				local inBeamList: { Part } = {}

				-- Der Ring wandert mit dem UFO: jetzt hier, gleich dort.
				local serverNow  = Workspace:GetServerTimeNow()
				local ringCenter = ringCenterAt(serverNow)
				local ringAhead  = ringCenterAt(serverNow + cfg.FOLLOW_LEAD_SECONDS)

				for _, part in parts do
					local st = stateOf(part)
					if st.abducting or taken[part.player] then
						continue
					end
					local foot = api.footOf(part.figure)
					st.inBeam = beamOpen and flatDist(foot, ringCenter) <= ringR
					if st.inBeam and now >= st.fightUntil then
						anyInBeam = true
						table.insert(inBeamList, part)
					end
				end

				-- Wer nicht im Beam steht, laeuft zum Beam: bevorzugt zu einem
				-- Baerchi, das schon drin steht (Regel 2), sonst zur eigenen Seite.
				for _, part in parts do
					local st = stateOf(part)
					if st.abducting or taken[part.player] then continue end
					if beamOpen and not st.inBeam and not st.moving and not part.busy
						and now >= st.fightUntil and now >= st.coolUntil then

						st.moving = true
						local target: Vector3
						local anchor = inBeamList[1]
						if anchor and anchor ~= part then
							local af   = api.footOf(anchor.figure)
							local from = api.footOf(part.figure)
							local dir  = Vector3.new(from.X - af.X, 0, from.Z - af.Z)
							if dir.Magnitude < 0.1 then dir = Vector3.new(1, 0, 0) end
							target = af + dir.Unit * (cfg.TOUCH_DISTANCE * APPROACH_SHARE)
						else
							local dir = Vector3.new(part.standFoot.X - ringAhead.X, 0, part.standFoot.Z - ringAhead.Z)
							if dir.Magnitude < 0.1 then dir = Vector3.new(1, 0, 0) end
							target = ringAhead + dir.Unit * (ringR * INNER_TARGET_SHARE)
						end

						task.spawn(function()
							api.walkTo(part, target)
							st.moving = false
							if running and api.stillHere(part) and not st.abducting then
								pcall(FigureFX.idleBob, part.figure, WAIT_BOB)
							end
						end)
					end
				end

				-- Wer im Ring steht, bleibt drin: rutscht der Ring weg, laeuft der
				-- Baerchi zur Ring-Mitte von gleich nach (Fortschritt laeuft weiter).
				for _, part in inBeamList do
					local st = stateOf(part)
					if not st.moving and not part.busy and now >= st.fightUntil
						and flatDist(api.footOf(part.figure), ringAhead) > ringR * cfg.FOLLOW_SHARE then
						st.moving = true
						task.spawn(function()
							api.walkTo(part, ringAhead)
							st.moving = false
							if running and api.stillHere(part) and not st.abducting then
								pcall(FigureFX.idleBob, part.figure, WAIT_BOB)
							end
						end)
					end
				end

				-- Beruehrung -> Kampf (mindestens einer im Beam)
				for i = 1, #parts do
					for j = i + 1, #parts do
						local a, b = parts[i], parts[j]
						local sa, sb = stateOf(a), stateOf(b)
						if sa.abducting or sb.abducting or taken[a.player] or taken[b.player] then continue end
						if now < sa.fightUntil or now < sb.fightUntil then continue end
						if not (sa.inBeam or sb.inBeam) then continue end
						local key = a.baerchiUid .. "|" .. b.baerchiUid
						if pairCool[key] and now < pairCool[key] then continue end
						if flatDist(api.footOf(a.figure), api.footOf(b.figure)) <= cfg.TOUCH_DISTANCE then
							pairCool[key] = now + cfg.FIGHT_SECONDS + cfg.PAIR_COOLDOWN_EXTRA_SECONDS
							startFight(a, b, sa, sb, now)
						end
					end
				end

				-- Beam-Fortschritt (pausiert waehrend eines Kampfes)
				if beamOpen and now >= fightPause then
					for _, part in inBeamList do
						local st = stateOf(part)
						st.progress += dt
						setLabel(part, string.format("%d / %ds", math.floor(st.progress), cfg.BEAM_REQUIRED_SECONDS))
						if st.progress >= cfg.BEAM_REQUIRED_SECONDS then
							abduct(part, st)
						end
					end
				end

				-- Beam-Timeout
				if beamOpen then
					if anyInBeam or now < fightPause then
						idleTimer = 0
					else
						idleTimer += dt
						if idleTimer >= cfg.BEAM_IDLE_TIMEOUT_SECONDS then
							closeBeam()
						end
					end
				end
			end)
			if not ok then
				warn("[EventHandlers.Ufo] Tick fehlgeschlagen:", err)
			end
		end
	end)

	----------------------------------------------------------------------------
	-- EI-ABWURF (alle DROP_INTERVAL_SECONDS, 1 % Jackpot mit Pity)
	----------------------------------------------------------------------------
	type Drop = { model: Model, landing: Vector3, landAt: number, jackpot: boolean, taken: boolean }
	local drops: { Drop } = {}
	local duration = EventConfig.getDuration(def)

	local function buildDrop(landing: Vector3, releaseAt: number, landAt: number, jackpot: boolean): Model
		local model = Instance.new("Model")
		model.Name = "UfoDrop"
		model:SetAttribute("ReleaseAt", releaseAt)
		model:SetAttribute("LandAt", landAt)
		model:SetAttribute("Jackpot", jackpot)

		local crateColor = if jackpot then CRATE_GOLD_COLOR else CRATE_COLOR
		fxPart({
			Name = "Crate", Material = if jackpot then Enum.Material.Neon else Enum.Material.WoodPlanks,
			Color = crateColor, Size = CRATE_SIZE,
			CFrame = CFrame.new(landing + Vector3.new(0, CRATE_SIZE.Y / 2, 0)),
		}, model)
		fxPart({
			Name = "Canopy", Shape = Enum.PartType.Ball, Material = Enum.Material.SmoothPlastic,
			Color = if jackpot then CRATE_GOLD_COLOR else CANOPY_COLOR, Size = CANOPY_SIZE,
			CFrame = CFrame.new(landing + Vector3.new(0, CRATE_SIZE.Y + CANOPY_LIFT, 0)),
		}, model)
		model.WorldPivot = CFrame.new(landing)

		-- Landekreis (Telegraph) und beim Jackpot die Lichtsaeule: liegen fest
		-- am Boden, gehoeren deshalb NICHT zum fallenden Model.
		fxPart({
			Name = "Mark", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon,
			Color = if jackpot then MARK_GOLD_COLOR else MARK_COLOR, Transparency = MARK_TRANSPARENCY,
			Size = Vector3.new(MARK_THICKNESS, cfg.DROP_PICKUP_RADIUS * 2, cfg.DROP_PICKUP_RADIUS * 2),
			CFrame = CFrame.new(landing + Vector3.new(0, UFO_RING_LIFT, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		}, model)
		if jackpot then
			fxPart({
				Name = "Pillar", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon,
				Color = CRATE_GOLD_COLOR, Transparency = PILLAR_TRANSPARENCY,
				Size = Vector3.new(PILLAR_HEIGHT, PILLAR_WIDTH, PILLAR_WIDTH),
				CFrame = CFrame.new(landing + Vector3.new(0, PILLAR_HEIGHT / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			}, model)
		end
		model.Parent = folder
		return model
	end

	-- Plant die Abwuerfe: DROP_FIRST_SECONDS, dann alle DROP_INTERVAL_SECONDS,
	-- solange die Landung noch im Event liegt. Ein Thread fuer alle Abwuerfe.
	task.spawn(function()
		local landRel = cfg.DROP_FIRST_SECONDS
		while running and landRel < duration do
			local landAt    = startTime + landRel
			local releaseAt = landAt - cfg.DROP_TELEGRAPH_SECONDS
			local waitFor   = releaseAt - Workspace:GetServerTimeNow()
			if waitFor > 0 then task.wait(waitFor) end
			if not running then break end

			local ok, err = pcall(function()
				-- Landepunkt = Bodenpunkt unter dem UFO im Moment der Landung.
				local landing = ringCenterAt(landAt)
				local jackpot = JackpotRoll.roll(JackpotRoll.ufo, cfg.JACKPOT_CHANCE, cfg.JACKPOT_PITY_DROPS, math.random())
				local model = buildDrop(landing, releaseAt, landAt, jackpot)
				table.insert(drops, { model = model, landing = landing, landAt = landAt, jackpot = jackpot, taken = false })
				if jackpot then
					api.announce(Loc.msg("msg.ufo.jackpot_drop"), "big")
				end
			end)
			if not ok then
				warn("[EventHandlers.Ufo] Abwurf fehlgeschlagen:", err)
			end
			landRel += cfg.DROP_INTERVAL_SECONDS
		end
	end)

	-- Aufheben: Spieler-CHARAKTER am Landepunkt, der Naechste gewinnt. Der
	-- Server prueft im Takt (wie bei den Waben), der Client meldet nichts.
	task.spawn(function()
		while running do
			task.wait(cfg.DROP_CHECK_SECONDS)
			local ok, err = pcall(function()
				local serverNow = Workspace:GetServerTimeNow()
				for _, drop in drops do
					if drop.taken or serverNow < drop.landAt then continue end

					local winner: Player? = nil
					local best = math.huge
					for _, player in Players:GetPlayers() do
						local character = player.Character
						local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
						if root and root:IsA("BasePart") then
							local d = flatDist(root.Position, drop.landing)
							if d <= cfg.DROP_PICKUP_RADIUS and math.abs(root.Position.Y - drop.landing.Y) <= cfg.DROP_PICKUP_MAX_HEIGHT and d < best then
								winner, best = player, d
							end
						end
					end

					if winner then
						local eggType = if drop.jackpot then cfg.JACKPOT_EGG else cfg.DROP_EGG
						if api.grantEgg(winner, eggType, 1) then
							drop.taken = true
							drop.model:Destroy()
							api.notify(winner, Loc.msg("msg.ufo.drop_picked", { egg = Loc.msg("egg." .. eggType .. ".name") }), "good")
							if drop.jackpot then
								api.announce(Loc.msg("msg.ufo.jackpot_picked", { player = winner.DisplayName }), "big")
							end
						end
					end
				end
			end)
			if not ok then
				warn("[EventHandlers.Ufo] Aufheben fehlgeschlagen:", err)
			end
		end
	end)

	return {
		stop = function()
			running = false
			for part in states do
				if not part.abducting then
					part.cancelWalk = true
				end
				pcall(setLabel, part, nil)
			end
			folder:Destroy()
			return {}
		end,
	}
end

--------------------------------------------------------------------------------
-- Hot Egg
--------------------------------------------------------------------------------

function EventHandlers.HotEgg(api: Api, def: EventConfig.EventDef): Session
	local cfg = EventConfig.HOT_EGG

	local running       = true
	local holder: Part? = nil
	local lastHolder: Part? = nil
	local cooldownUntil = 0
	local chasing       = false
	local fire: Instance? = nil

	-- LAVA-WABEN: das Wabenthema gilt fuer die ganze Event-Dauer (CombService
	-- kennt Skin, Wert, Slots und Tempo). Hier steht nur der Aufruf.
	CombService.setTheme(cfg.COMB_THEME)
	api.announce(Loc.msg("msg.hotegg.lava"), "info")

	-- VULKAN-AUSBRUCH: Warnring in der Mitte, dann fliegen Lava-Waben in
	-- alle Richtungen (Landepunkte legt CombService fest, den Flug zeichnet
	-- der Client aus der Serverzeit).
	local volcano = newFolder("EventVolcano")
	task.spawn(function()
		while running do
			task.wait(math.max(0, cfg.ERUPTION_INTERVAL_SECONDS - cfg.ERUPTION_WARN_SECONDS))
			if not running then break end
			local ok, err = pcall(function()
				local ring = fxPart({
					Name = "EruptionWarning", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon,
					Color = ERUPTION_RING_COLOR, Transparency = 0.2,
					Size = Vector3.new(ERUPTION_RING_THICKNESS, ERUPTION_RING_RADIUS * 2, ERUPTION_RING_RADIUS * 2),
					CFrame = CFrame.new(api.center + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
				}, volcano)
				task.wait(cfg.ERUPTION_WARN_SECONDS)
				ring:Destroy()
				if running then
					CombService.launchCombs(
						math.random(cfg.ERUPTION_MIN, cfg.ERUPTION_MAX),
						api.center + Vector3.new(0, ERUPTION_ORIGIN_LIFT, 0)
					)
				end
			end)
			if not ok then
				warn("[EventHandlers.HotEgg] Ausbruch fehlgeschlagen:", err)
			end
		end
	end)

	local function setHolder(part: Part?)
		if fire then
			fire:Destroy()
			fire = nil
		end
		if holder then
			setLabel(holder, nil)
		end
		holder = part
		if part and part.figure then
			local root = rootOf(part.figure)
			if root then
				fire = make("Fire", {
					Size = HOT_EGG_FIRE_SIZE, Heat = HOT_EGG_FIRE_HEAT,
					Color = HOT_EGG_FIRE_COLOR, SecondaryColor = HOT_EGG_FIRE_COLOR_2,
				}, root)
			end
			setLabel(part, Loc.msg("ev.label.hot_egg"))
			api.toast(part.player, Loc.msg("ev.hot_egg.you_have"))
		end
	end

	task.spawn(function()
		while running do
			task.wait(cfg.CHECK_INTERVAL_SECONDS)
			local ok, err = pcall(function()
				local parts = api.participants()

				local current = holder
				if current and not api.stillHere(current) then
					setHolder(nil)
					current = nil
				end
				if not current and #parts > 0 then
					current = parts[math.random(1, #parts)]
					setHolder(current)
				end

				if not current or chasing or current.busy or #parts < 2 then
					return
				end
				if os.clock() < cooldownUntil then
					return
				end

				local chaser: Part = current
				local hf = api.footOf(chaser.figure)
				local best: Part? = nil
				local bestDist = math.huge
				for _, other in parts do
					if other ~= chaser and other ~= lastHolder then
						local d = flatDist(hf, api.footOf(other.figure))
						if d < bestDist then
							best, bestDist = other, d
						end
					end
				end
				local target: Part = best or (if parts[1] ~= chaser then parts[1] else parts[2])

				chasing = true
				task.spawn(function()
					local ef = api.footOf(target.figure)
					local dir = Vector3.new(hf.X - ef.X, 0, hf.Z - ef.Z)
					if dir.Magnitude < 0.1 then dir = Vector3.new(1, 0, 0) end
					api.walkTo(chaser, ef + dir.Unit * (cfg.TOUCH_DISTANCE * APPROACH_SHARE))

					if running and holder == chaser and api.stillHere(target) and api.stillHere(chaser)
						and flatDist(api.footOf(chaser.figure), api.footOf(target.figure)) <= cfg.TOUCH_DISTANCE + HOT_EGG_PASS_SLACK then
						lastHolder    = chaser
						cooldownUntil = os.clock() + cfg.PASS_COOLDOWN_SECONDS
						setHolder(target)
						task.spawn(function()
							api.walkTo(chaser, chaser.standFoot)
							if running and api.stillHere(chaser) then
								pcall(FigureFX.idleBob, chaser.figure, CHEER_BOB)
							end
						end)
					end
					chasing = false
				end)
			end)
			if not ok then
				warn("[EventHandlers.HotEgg] Tick fehlgeschlagen:", err)
			end
		end
	end)

	return {
		stop = function()
			running = false
			local results: { [Player]: Reward } = {}
			for _, part in api.participants() do
				part.cancelWalk = true
			end
			local last = holder
			if last and api.stillHere(last) then
				results[last.player] = { egg = def.bonus }
			end
			if last then
				setLabel(last, nil)
			end
			local flame = fire
			if flame then
				flame:Destroy()
			end
			volcano:Destroy()
			-- Waben im Pit werden wieder normal; getragene behalten ihren Wert.
			CombService.clearTheme()
			return results
		end,
	}
end

--------------------------------------------------------------------------------
-- Mutations-Sturm
--------------------------------------------------------------------------------

function EventHandlers.MutationsSturm(api: Api, _def: EventConfig.EventDef): Session
	local cfg     = EventConfig.STORM
	local running = true
	local folder  = newFolder("EventStorm")

	local function strike(part: Part)
		local pos = api.footOf(part.figure)
		local bolt = fxPart({
			Name = "Bolt", Material = Enum.Material.Neon, Color = STORM_COLOR,
			Transparency = STORM_BOLT_TRANSPARENCY, Size = STORM_BOLT_SIZE,
			CFrame = CFrame.new(pos + Vector3.new(0, STORM_BOLT_SIZE.Y / 2, 0)),
		}, folder)
		pcall(FigureFX.burstAt, pos + Vector3.new(0, STORM_BURST_LIFT, 0), STORM_COLOR, folder, STORM_BURST_COUNT)
		pcall(FigureFX.hitFlash, part.figure, STORM_COLOR, STORM_FLASH_SECONDS)
		task.delay(STORM_BOLT_SECONDS, function()
			bolt:Destroy()
		end)
	end

	task.spawn(function()
		while running do
			task.wait(cfg.STRIKE_INTERVAL_SECONDS)
			if not running then break end
			local ok, err = pcall(function()
				local parts = api.participants()
				if #parts > 0 then
					strike(parts[math.random(1, #parts)])
				end
			end)
			if not ok then
				warn("[EventHandlers.MutationsSturm] Blitz fehlgeschlagen:", err)
			end
		end
	end)

	return {
		stop = function()
			running = false
			local results: { [Player]: Reward } = {}
			for _, part in api.participants() do
				results[part.player] = { mutationRoll = true }
				pcall(strike, part)
			end
			task.delay(STORM_CLEANUP_SECONDS, function()
				folder:Destroy()
			end)
			return results
		end,
	}
end

--------------------------------------------------------------------------------
-- Koenigshuegel
--------------------------------------------------------------------------------

function EventHandlers.Koenigshuegel(api: Api, def: EventConfig.EventDef): Session
	local cfg     = EventConfig.KING
	local running = true
	local center  = api.center
	local hillR   = api.radius * cfg.HILL_RADIUS_FACTOR
	local folder  = newFolder("EventKing")

	fxPart({
		Name = "Hill", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon,
		Color = HILL_COLOR, Transparency = HILL_TRANSPARENCY,
		Size = Vector3.new(HILL_THICKNESS, hillR * 2, hillR * 2),
		CFrame = CFrame.new(Vector3.new(center.X, center.Y + HILL_LIFT, center.Z)) * CFrame.Angles(0, 0, math.rad(90)),
	}, folder)

	local seconds: { [Player]: number } = {}   -- Sekunden oben
	local coolUntil: { [Part]: number } = {}   -- os.clock()
	local fighting  = false

	local function onHill(part: Part): boolean
		return flatDist(api.footOf(part.figure), center) <= hillR
	end

	task.spawn(function()
		while running do
			task.wait(cfg.TICK_SECONDS)
			local ok, err = pcall(function()
				local parts = api.participants()
				local king: Part? = nil
				local kingTime = -1
				for _, part in parts do
					local up = onHill(part)
					if up then
						seconds[part.player] = (seconds[part.player] or 0) + cfg.TICK_SECONDS
					end
					local t = seconds[part.player] or 0
					if up and t > kingTime then
						king, kingTime = part, t
					end
					setLabel(part, Loc.msg("ev.label.on_top", { s = math.floor(seconds[part.player] or 0) }))
				end

				for _, part in parts do
					if part.busy or fighting or os.clock() < (coolUntil[part] or 0) then
						continue
					end

					if not onHill(part) then
						local dir = Vector3.new(part.standFoot.X - center.X, 0, part.standFoot.Z - center.Z)
						if dir.Magnitude < 0.1 then dir = Vector3.new(1, 0, 0) end
						local target = center + dir.Unit * (hillR * INNER_TARGET_SHARE)
						if king and king ~= part then
							local kf = api.footOf(king.figure)
							local from = api.footOf(part.figure)
							local d = Vector3.new(from.X - kf.X, 0, from.Z - kf.Z)
							if d.Magnitude < 0.1 then d = Vector3.new(1, 0, 0) end
							target = kf + d.Unit * cfg.CHALLENGE_DISTANCE
						end
						task.spawn(function()
							api.walkTo(part, target)
							if running and api.stillHere(part) then
								pcall(FigureFX.idleBob, part.figure, CHEER_BOB)
							end
						end)
					elseif king and king ~= part and not king.busy then
						-- Herausforderer: zum Koenig laufen und kaempfen
						local kf = api.footOf(king.figure)
						local pf = api.footOf(part.figure)
						if flatDist(kf, pf) > cfg.TOUCH_DISTANCE then
							local d = Vector3.new(pf.X - kf.X, 0, pf.Z - kf.Z)
							if d.Magnitude < 0.1 then d = Vector3.new(1, 0, 0) end
							task.spawn(function()
								api.walkTo(part, kf + d.Unit * cfg.CHALLENGE_DISTANCE)
							end)
						end
					end
				end

				-- Beruehrung zweier Teilnehmer auf dem Huegel -> Kampf
				if not fighting then
					for i = 1, #parts do
						for j = i + 1, #parts do
							local a, b = parts[i], parts[j]
							if onHill(a) and onHill(b)
								and flatDist(api.footOf(a.figure), api.footOf(b.figure)) <= cfg.TOUCH_DISTANCE
								and os.clock() >= (coolUntil[a] or 0) and os.clock() >= (coolUntil[b] or 0) then

								fighting = true
								a.cancelWalk, b.cancelWalk = true, true
								task.spawn(function()
									local ok2, err2 = pcall(function()
										local winner, loser = duel(api, a, b, cfg.DUEL_SECONDS)
										coolUntil[loser] = os.clock() + cfg.LOSER_COOLDOWN_SECONDS
										api.toast(loser.player, Loc.msg("ev.king.pushed"))
										api.toast(winner.player, Loc.msg("ev.king.holding"))
										api.walkTo(loser, loser.standFoot)
									end)
									if not ok2 then
										warn("[EventHandlers.Koenigshuegel] Kampf fehlgeschlagen:", err2)
									end
									fighting = false
								end)
								return
							end
						end
					end
				end
			end)
			if not ok then
				warn("[EventHandlers.Koenigshuegel] Tick fehlgeschlagen:", err)
			end
		end
	end)

	return {
		stop = function()
			running = false
			local results: { [Player]: Reward } = {}
			local bestPlayer: Player? = nil
			local bestTime = 0
			for _, part in api.participants() do
				part.cancelWalk = true
				setLabel(part, nil)
				local t = seconds[part.player] or 0
				if t > bestTime then
					bestPlayer, bestTime = part.player, t
				end
			end
			if bestPlayer then
				results[bestPlayer] = { egg = def.bonus }
			end
			folder:Destroy()
			return results
		end,
	}
end

--------------------------------------------------------------------------------
-- Schatzgraeber
--------------------------------------------------------------------------------

function EventHandlers.Schatzgraeber(api: Api, _def: EventConfig.EventDef): Session
	local cfg     = EventConfig.TREASURE
	local running = true
	local center  = api.center
	local folder  = newFolder("EventTreasure")

	local started: { [Part]: boolean } = {}
	local finds: { [Player]: number } = {}    -- Anzahl Funde
	local bombed: { [Player]: boolean } = {}

	local function randomSite(): Vector3
		local angle = math.random() * math.pi * 2
		local dist  = api.radius * (cfg.SITE_MIN_RADIUS_FACTOR
			+ math.random() * (cfg.SITE_MAX_RADIUS_FACTOR - cfg.SITE_MIN_RADIUS_FACTOR))
		return Vector3.new(center.X + math.cos(angle) * dist, center.Y, center.Z + math.sin(angle) * dist)
	end

	local function run(part: Part)
		local level   = api.level(part)
		local sites   = math.min(cfg.MAX_SITES, cfg.BASE_SITES + math.floor(level / cfg.LEVEL_PER_EXTRA_SITE))
		local digTime = math.max(cfg.MIN_DIG_SECONDS, cfg.BASE_DIG_SECONDS - level * cfg.DIG_SECONDS_PER_LEVEL)
		local player  = part.player

		finds[player] = finds[player] or 0
		api.toast(player, Loc.msg("ev.treasure.start", { n = sites }))

		for i = 1, sites do
			if not running or not api.stillHere(part) then return end

			local pos = randomSite()
			local mound = fxPart({
				Name = "Mound", Shape = Enum.PartType.Ball, Material = Enum.Material.Ground,
				Color = MOUND_COLOR, Size = MOUND_SIZE,
				CFrame = CFrame.new(pos + Vector3.new(0, MOUND_LIFT, 0)),
			}, folder)
			local isBomb = math.random() < cfg.BOMB_SHARE

			if not api.walkTo(part, pos) then
				mound:Destroy()
				return
			end

			-- graben
			setLabel(part, Loc.msg("ev.label.digging", { i = i, n = sites }))
			pcall(FigureFX.idleBob, part.figure, DIG_BOB)
			local t0 = os.clock()
			while os.clock() - t0 < digTime do
				if not running or not api.stillHere(part) then
					mound:Destroy()
					setLabel(part, nil)
					return
				end
				task.wait(DIG_CHECK_SECONDS)
			end
			pcall(FigureFX.stopIdle, part.figure)
			mound:Destroy()

			if isBomb then
				local boom = Instance.new("Explosion")
				boom.Position = pos
				boom.BlastRadius = BOMB_BLAST_RADIUS
				boom.BlastPressure = 0
				boom.DestroyJointRadiusPercent = 0
				boom.Parent = folder
				pcall(FigureFX.defeatCollapse, part.figure, BOMB_COLLAPSE_SECONDS)
				finds[player] = 0
				bombed[player] = true
				setLabel(part, nil)
				api.toast(player, Loc.msg("ev.treasure.bomb"))
				api.recall(player)
				return
			end

			finds[player] += 1
			pcall(FigureFX.burstAt, pos + Vector3.new(0, FIND_BURST_LIFT, 0), FIND_COLOR, folder, FIND_BURST_COUNT)
			api.toast(player, Loc.msg("ev.treasure.find", { n = finds[player] }))
		end

		setLabel(part, nil)
		api.toast(player, Loc.msg("ev.treasure.done", { n = finds[player] }))
		if api.walkTo(part, part.standFoot) and running and api.stillHere(part) then
			pcall(FigureFX.idleBob, part.figure, DIG_BOB)
		end
	end

	task.spawn(function()
		while running do
			local ok, err = pcall(function()
				for _, part in api.participants() do
					if not started[part] and not bombed[part.player] then
						started[part] = true
						task.spawn(function()
							local ok2, err2 = pcall(run, part)
							if not ok2 then
								warn("[EventHandlers.Schatzgraeber] Lauf fehlgeschlagen:", err2)
							end
						end)
					end
				end
			end)
			if not ok then
				warn("[EventHandlers.Schatzgraeber] Tick fehlgeschlagen:", err)
			end
			task.wait(TREASURE_JOIN_CHECK_SECONDS)
		end
	end)

	return {
		stop = function()
			running = false
			local results: { [Player]: Reward } = {}
			for _, part in api.participants() do
				part.cancelWalk = true
				setLabel(part, nil)
				local n = finds[part.player] or 0
				if n > 0 and not bombed[part.player] then
					local reward: any = nil
					for _, tier in cfg.REWARDS do
						if n >= tier.minFinds then
							reward = tier
						end
					end
					if reward then
						results[part.player] = { egg = {
							kind = "eggs", eggType = reward.eggType, eggPick = reward.eggPick,
							amount = reward.amount, blueprintChance = reward.blueprintChance,
						} }
					end
				end
			end
			folder:Destroy()
			return results
		end,
	}
end

--------------------------------------------------------------------------------
-- Wespenkoenigin (Boss-Event, Ablauf in Util/WaspQueenEvent)
--------------------------------------------------------------------------------

function EventHandlers.WaspQueen(api: Api, def: EventConfig.EventDef): Session
	return WaspQueenEvent.run(api, def)
end

return EventHandlers
