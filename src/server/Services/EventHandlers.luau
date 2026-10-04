--!strict
-- EventHandlers.luau
-- ServerScriptService/Services/EventHandlers.luau
--
-- Einzige Zustaendigkeit:
--   - Den Ablauf der fuenf Events in der Event-Area spielen:
--     Ufo, HotEgg, MutationsSturm, Koenigshuegel, Schatzgraeber
--
-- Kein eigener Eintrag im GameManager: EventParticipationService ruft den
-- passenden Handler beim Event-Start auf.
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

local RunService          = game:GetService("RunService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local EventConfig     = require(ReplicatedStorage.Config.EventConfig)
local FigureFX        = require(ServerScriptService.Util.FigureFX)
local FigurePlacement = require(ServerScriptService.Util.FigurePlacement)

local EventHandlers = {}

--------------------------------------------------------------------------------
-- Typen
--------------------------------------------------------------------------------

-- Ein Teilnehmer, wie EventParticipationService ihn liefert (dort: Presence).
-- Die Handler lesen ihn und setzen nur die drei Steuerfelder unten.
export type Part = {
	player     : Player,
	figure     : Model,
	baerchiUid : string,
	homeFoot   : Vector3,
	standFoot  : Vector3,
	busy       : boolean?,   -- Figur laeuft gerade (walkTo)
	cancelWalk : boolean?,   -- laufende Bewegung abbrechen
	abducting  : boolean?,   -- UFO hat die Figur gerade
}

-- Was EventParticipationService den Handlern bereitstellt (buildApi).
export type Api = {
	center       : Vector3,
	radius       : number,
	running      : () -> boolean,
	footOf       : (Model) -> Vector3,
	participants : () -> { Part },
	stillHere    : (Part) -> boolean,
	plotPosition : (Player) -> Vector3?,
	level        : (Part) -> number,
	power        : (Part) -> number,
	toast        : (Player, string) -> (),
	recall       : (Player) -> (),
	finishHome   : (Part) -> (),
	ufoReward    : (Part) -> (),
	walkTo       : (Part, Vector3) -> boolean,
}

-- Belohnung eines Spielers am Event-Ende.
export type Reward = {
	egg          : EventConfig.EventBonus?,
	mutationRoll : boolean?,
}

export type Session = {
	stop : () -> { [Player]: Reward },
}

export type Handler = (Api, EventConfig.EventDef) -> Session

--------------------------------------------------------------------------------
-- Optik (keine Balance — aendert nur, wie es aussieht)
--------------------------------------------------------------------------------

-- Textmarke ueber der Figur
local LABEL_SIZE              = UDim2.fromOffset(120, 26)
local LABEL_OFFSET            = Vector3.new(0, 6, 0)
local LABEL_MAX_DISTANCE      = 220
local LABEL_BACK_TRANSPARENCY = 0.35
local LABEL_BACK_COLOR        = Color3.fromRGB(20, 20, 30)
local LABEL_TEXT_COLOR        = Color3.new(1, 1, 1)

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
local UFO_HOVER_HEIGHT        = 40
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

local function flatDist(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Eigenschaften per Tabelle setzen. Ueber `any`, weil der Klassenname erst
-- zur Laufzeit feststeht und --!strict die Felder sonst nicht kennt.
local function make(className: string, props: { [string]: any }, parent: Instance): Instance
	local inst: any = Instance.new(className)
	for key, value in props do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

local function fxPart(props: { [string]: any }, parent: Instance): BasePart
	props.Anchored   = true
	props.CanCollide = false
	props.CanQuery   = false
	props.CanTouch   = false
	props.CastShadow = false
	return make("Part", props, parent) :: BasePart
end

local function rootOf(figure: Model): BasePart?
	return figure.PrimaryPart or figure:FindFirstChildWhichIsA("BasePart", true)
end

-- Kleine Textmarke ueber der Figur (Fortschritt, "Ei!", ...). nil entfernt sie.
local function setLabel(part: Part, text: string?)
	local figure = part.figure
	if not figure or not figure.Parent then
		return
	end

	local gui = figure:FindFirstChild("EventLabel")
	if not text then
		if gui then
			gui:Destroy()
		end
		return
	end

	if not gui then
		local root = rootOf(figure)
		if not root then
			return
		end
		local created = make("BillboardGui", {
			Name         = "EventLabel",
			Size         = LABEL_SIZE,
			StudsOffset  = LABEL_OFFSET,
			AlwaysOnTop  = true,
			Adornee      = root,
			MaxDistance  = LABEL_MAX_DISTANCE,
		}, figure)
		make("TextLabel", {
			Name                   = "Text",
			Size                   = UDim2.fromScale(1, 1),
			BackgroundTransparency = LABEL_BACK_TRANSPARENCY,
			BackgroundColor3       = LABEL_BACK_COLOR,
			TextColor3             = LABEL_TEXT_COLOR,
			TextScaled             = true,
			Font                   = Enum.Font.GothamBold,
		}, created)
		gui = created
	end

	local label = (gui :: Instance):FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

local function newFolder(name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name   = name
	folder.Parent = workspace
	return folder
end

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

function EventHandlers.Ufo(api: Api, _def: EventConfig.EventDef): Session
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

	-- UFO-Optik: Scheibe, Kuppel, Beam, Ring am Boden
	local discPos = Vector3.new(center.X, hoverY, center.Z)
	fxPart({
		Name = "Disc", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Metal,
		Color = UFO_DISC_COLOR, Size = UFO_DISC_SIZE,
		CFrame = CFrame.new(discPos) * CFrame.Angles(0, 0, math.rad(90)),
	}, folder)
	fxPart({
		Name = "Dome", Shape = Enum.PartType.Ball, Material = Enum.Material.Glass,
		Color = UFO_COLOR, Transparency = UFO_DOME_TRANSPARENCY, Size = UFO_DOME_SIZE,
		CFrame = CFrame.new(discPos + Vector3.new(0, UFO_DOME_LIFT, 0)),
	}, folder)
	local beamHeight = hoverY - center.Y
	local beam = fxPart({
		Name = "Beam", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon,
		Color = UFO_COLOR, Transparency = UFO_BEAM_TRANSPARENCY,
		Size = Vector3.new(beamHeight, ringR * 2, ringR * 2),
		CFrame = CFrame.new(Vector3.new(center.X, center.Y + beamHeight / 2, center.Z)) * CFrame.Angles(0, 0, math.rad(90)),
	}, folder)
	local ring = fxPart({
		Name = "Ring", Shape = Enum.PartType.Cylinder, Material = Enum.Material.Neon,
		Color = UFO_COLOR, Transparency = UFO_RING_TRANSPARENCY,
		Size = Vector3.new(UFO_RING_THICKNESS, ringR * 2, ringR * 2),
		CFrame = CFrame.new(Vector3.new(center.X, center.Y + UFO_RING_LIFT, center.Z)) * CFrame.Angles(0, 0, math.rad(90)),
	}, folder)

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
		setLabel(part, "ENTFUEHRT!")

		task.spawn(function()
			local ok, err = pcall(function()
				local figure = part.figure
				local player = part.player
				api.toast(player, "UFO: Dein Baerchi wird entfuehrt!")

				local startFoot = api.footOf(figure)
				local ufoFoot   = Vector3.new(center.X, hoverY - UFO_PICKUP_BELOW_DISC, center.Z)
				pcall(FigureFX.burstAt, startFoot, UFO_COLOR, folder, UFO_BURST_COUNT)

				-- 1) hochgezogen
				FigureFX.stopIdle(figure)
				moveFoot(figure, startFoot, ufoFoot, UFO_LIFT_SECONDS, math.pi * 2 * UFO_LIFT_TURNS)

				-- 2) Transport zum Plot des Spielers
				local plotPos = api.plotPosition(player)
				local overPlot = (plotPos or ufoFoot) + Vector3.new(0, UFO_TRANSPORT_HEIGHT, 0)
				setLabel(part, "Transport...")
				moveFoot(figure, ufoFoot, overPlot, UFO_TRANSPORT_SECONDS, math.pi * 2 * UFO_TRANSPORT_TURNS)

				-- 3) Wartezeit ueber dem Plot
				local waitStart = os.clock()
				while os.clock() - waitStart < cfg.ABDUCT_WAIT_SECONDS do
					local left = math.ceil(cfg.ABDUCT_WAIT_SECONDS - (os.clock() - waitStart))
					setLabel(part, string.format("Landung in %ds", left))
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
		setLabel(a, "KAMPF!")
		setLabel(b, "KAMPF!")

		task.spawn(function()
			local ok, err = pcall(function()
				local winner, loser = duel(api, a, b, cfg.FIGHT_SECONDS)
				local sw, sl = stateOf(winner), stateOf(loser)

				-- Verlierer: aus dem Ring gedraengt, beginnt von vorne.
				sl.progress  = 0
				sl.coolUntil = os.clock() + cfg.LOSER_COOLDOWN_SECONDS
				api.toast(loser.player, "Kampf verloren - Beam-Fortschritt zurueckgesetzt")
				api.toast(winner.player, "Kampf gewonnen!")
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
			api.toast(part.player, "UFO: Der Beam wurde zurueckgesetzt - alle Countdowns beginnen von vorne")
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
		api.toast(part.player, string.format(
			"UFO: Geh in den Strahl! %ds Beam-Fortschritt bis zur Entfuehrung", cfg.BEAM_REQUIRED_SECONDS
		))
	end

	local dt = cfg.TICK_SECONDS
	task.spawn(function()
		while running do
			task.wait(dt)
			local ok, err = pcall(function()
				local parts = api.participants()
				local now   = os.clock()
				local anyInBeam = false
				local inBeamList: { Part } = {}

				for _, part in parts do
					local st = stateOf(part)
					if st.abducting or taken[part.player] then
						continue
					end
					local foot = api.footOf(part.figure)
					st.inBeam = beamOpen and flatDist(foot, center) <= ringR
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
							local dir = Vector3.new(part.standFoot.X - center.X, 0, part.standFoot.Z - center.Z)
							if dir.Magnitude < 0.1 then dir = Vector3.new(1, 0, 0) end
							target = center + dir.Unit * (ringR * INNER_TARGET_SHARE)
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
			setLabel(part, "HEISSES EI!")
			api.toast(part.player, "Du hast das heisse Ei! Gib es per Beruehrung weiter.")
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
					setLabel(part, string.format("%ds oben", math.floor(seconds[part.player] or 0)))
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
										api.toast(loser.player, "Vom Huegel gestossen!")
										api.toast(winner.player, "Du haeltst den Huegel!")
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
		api.toast(player, string.format("Schatzgraeber: %d Fundstellen - Vorsicht, Bomben!", sites))

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
			setLabel(part, string.format("Graebt %d/%d", i, sites))
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
				api.toast(player, "BOMBE! Dein Baerchi ist besiegt - die Beute ist weg")
				api.recall(player)
				return
			end

			finds[player] += 1
			pcall(FigureFX.burstAt, pos + Vector3.new(0, FIND_BURST_LIFT, 0), FIND_COLOR, folder, FIND_BURST_COUNT)
			api.toast(player, string.format("Fund! (%d)", finds[player]))
		end

		setLabel(part, nil)
		api.toast(player, string.format("Alle Fundstellen geleert: %d Funde", finds[player]))
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

return EventHandlers
