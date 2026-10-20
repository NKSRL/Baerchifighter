--!strict
-- EpilogController.luau
-- StarterPlayerScripts/Controllers/EpilogController.luau
--
-- Prompt 5 von 7 (Final-Epilog): Kamerafahrt und Bildschirmrand-Effekte.
--
-- Einzige Zustaendigkeit: die ~34 s lange Fahrt nach dem Final-100-Sieg ABSPIELEN.
--   - Kamera: EpilogCameraPath.sample(t, ctx) in einer einzigen Kit.animate-Schleife
--   - Avatar: Humanoid:MoveTo-Lauf ueber die Bruecke (Tempo-Profil wie der Begleiter)
--   - Bildschirmrand: UI/EpilogOverlay (Flash, Vignette, Funken, Konfetti, Speed-Lines ...)
--   - Licht: Bloom, SunRays, ColorCorrection (Namen Epilog*)
--   - Skip: Halten 1 s ab Sekunde 12 (Ring unten rechts), der Server prueft nach
--   - Aufraeumen: Kamera, FOV, Licht, UI, Verbindungen, Steuerung — immer, auch bei Tod,
--     Respawn, Verlassen und Fehlern.
-- Der Server fuehrt den Zeitplan (Teleport, Insel, Bruecke, Begleiter, Wachhund); der
-- Client zeigt nur und laeuft. Entscheidungen ueber Zustand trifft allein der Server.
--
-- Wiederaufnahme (mode "restore"): keine fahrt, nur 1,2 s Flash; EpilogSeen, sobald der
-- Avatar am Terminal steht.

local Players           = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Workspace         = game:GetService("Workspace")
local Lighting          = game:GetService("Lighting")
local GuiService        = game:GetService("GuiService")
local UserInputService  = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes          = require(ReplicatedStorage.Network.Remotes)
local EpilogConfig     = require(ReplicatedStorage.Config.EpilogConfig)
local Loc              = require(ReplicatedStorage.Localization.Loc)
local EpilogRoute      = require(ReplicatedStorage.Modules.EpilogRoute)
local EpilogCameraPath = require(ReplicatedStorage.Modules.EpilogCameraPath)

local Kit            = require(script.Parent.Parent.UI.Kit)
local Moment         = require(script.Parent.Parent.UI.Moment)
local EpilogOverlay  = require(script.Parent.Parent.UI.EpilogOverlay)
local EpilogFinaleFX = require(script.Parent.Parent.UI.EpilogFinaleFX)
local AudioController = require(script.Parent.AudioController)

local EpilogController = {}

local Q  = EpilogConfig.SEQUENCE
local FX = EpilogConfig.FX
local player = Players.LocalPlayer

type Run = {
	token       : string,
	startAt     : number,    -- Serverzeit des Starts
	speed       : number,
	jump        : number,    -- Sekunden, die ein Skip der Fahrt vorgezogen hat
	ctx         : EpilogCameraPath.Context,
	route       : EpilogRoute.Route,
	profile     : EpilogRoute.Profile,
	camera      : Camera,
	saved       : { cameraType : Enum.CameraType, subject : Instance?, fov : number, cframe : CFrame },
	humanoid    : Humanoid?,
	walkSpeed   : number,
	stop        : (() -> ())?,
	conns       : { RBXScriptConnection },
	effects     : { Instance },
	controls    : any?,
	controlsOff : boolean,
	hidden      : { GuiObject },
	skipHeld    : number?,   -- Beginn des Haltens (os.clock) oder nil
	skipSent    : boolean,
	cuesDone    : { [number]: boolean },
	momentDone  : boolean,
	seenSent    : boolean,
	planks      : { BasePart },
	reduced     : boolean,
	ended       : boolean,
	lastClock   : number,
	stepAt      : number,    -- naechster Schritt-Klang (Sequenzzeit)
}

local _run: Run? = nil
local _restoreWatch: thread? = nil

--------------------------------------------------------------------------------
-- Kleine Helfer
--------------------------------------------------------------------------------

local function v3(a: { number }): Vector3
	return Vector3.new(a[1], a[2], a[3])
end

local function arr(v: Vector3): { number }
	return { v.X, v.Y, v.Z }
end

-- Stueckweise lineare Kurve { {t, wert}, ... }
local function curve(points: { { number } }, t: number): number
	if t <= points[1][1] then return points[1][2] end
	for i = 2, #points do
		local a, b = points[i - 1], points[i]
		if t <= b[1] then
			local u = (t - a[1]) / math.max(1e-6, b[1] - a[1])
			return a[2] + (b[2] - a[2]) * u
		end
	end
	return points[#points][2]
end

local function intensity(): string
	local reduced = false
	pcall(function()
		if (GuiService :: any).ReducedMotionEnabled == true then reduced = true end
	end)
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		reduced = true
	end
	pcall(function()
		local level = (UserSettings():GetService("UserGameSettings") :: any).SavedQualityLevel
		local n = if typeof(level) == "EnumItem" then level.Value else tonumber(level)
		if n and n > 0 and n <= 3 then reduced = true end
	end)
	return if reduced then "reduced" else "full"
end

-- HUD ausblenden, aber den Moment-Banner (haengt in derselben ScreenGui) stehen lassen.
-- Gibt die versteckten Elemente zurueck; showHud stellt sie wieder her.
local function hideHud(): { GuiObject }
	local hidden: { GuiObject } = {}
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local hud = if pg then pg:FindFirstChild("RBL") else nil
	if hud and hud:IsA("ScreenGui") then
		for _, c in hud:GetChildren() do
			if c:IsA("GuiObject") and c.Name ~= "Moment" and c.Visible then
				c.Visible = false
				table.insert(hidden, c)
			end
		end
	end
	return hidden
end

local function showHud(hidden: { GuiObject })
	for _, c in hidden do
		if c.Parent then c.Visible = true end
	end
end

local function isNight(): boolean
	local h = Lighting.ClockTime
	return h < FX.dayFrom or h >= FX.dayTo
end

-- Spielt einen Epilog-Klang ueber Audio.SFX (Ids/Lautstaerken aus Config/SoundConfig).
-- Stumm, Effekt-Regler und 6-Stimmen-Limit gelten dort (AudioController.play).
-- Das Terminal-Modell steht unter dem Plot und traegt das Tag EpilogConfig.TERMINAL.TAG (der Name
-- ist "Terminal"); gesucht wird das naechste zum Avatar.
local function nearestTerminal(root: BasePart?): Model?
	if not root then return nil end
	local best: Model? = nil
	local bestDistance = math.huge
	for _, instance in CollectionService:GetTagged(EpilogConfig.TERMINAL.TAG) do
		if instance:IsA("Model") then
			local distance = (instance:GetPivot().Position - root.Position).Magnitude
			if distance < bestDistance then best, bestDistance = instance, distance end
		end
	end
	return best
end

local function playCue(name: string)
	local id = EpilogConfig.CUES[name]
	if id then
		AudioController.play(id)
	end
end

-- Epilog-Musik: an = Spielmusik -10 dB und Epilog-Spur blendet ein; aus = 2 s zurueck zur Spielmusik.
-- Beides ist idempotent und wird bei jedem Abbruch (cleanup/endFinale) gegengesteuert.
local function musicOn() pcall(AudioController.epilogMusic, true) end
local function musicOff() pcall(AudioController.epilogMusic, false) end
local watchMusic: () -> () = function() end   -- Waechter, unten definiert (braucht _fin)

local function sequenceTime(run: Run): number
	return math.max(0, (Workspace:GetServerTimeNow() - run.startAt) * run.speed) + run.jump
end

--------------------------------------------------------------------------------
-- Steuerung (Disable/Enable immer paarweise)
--------------------------------------------------------------------------------

local function getControls(): any?
	local ok, controls = pcall(function()
		local module = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 2)
		if not module then return nil end
		return (require(module :: ModuleScript) :: any):GetControls()
	end)
	if ok then return controls end
	return nil
end

local function setControls(run: Run, off: boolean)
	if run.controls == nil then return end
	if off and not run.controlsOff then
		run.controlsOff = true
		pcall(function() run.controls:Disable() end)
	elseif not off and run.controlsOff then
		run.controlsOff = false
		pcall(function() run.controls:Enable() end)
	end
end

--------------------------------------------------------------------------------
-- Licht
--------------------------------------------------------------------------------

local function makeEffects(run: Run)
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "EpilogBloom"
	bloom.Intensity = 0
	bloom.Size = 28
	bloom.Threshold = 1.0
	bloom.Parent = Lighting
	local rays = Instance.new("SunRaysEffect")
	rays.Name = "EpilogSunRays"
	rays.Intensity = 0
	rays.Spread = 0.6
	rays.Parent = Lighting
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "EpilogColorCorrection"
	grade.Parent = Lighting
	run.effects = { bloom, rays, grade }
end

local function updateEffects(run: Run, t: number)
	local boost = if isNight() then FX.nightBoost else 1
	local bloom, rays, grade = run.effects[1], run.effects[2], run.effects[3]
	if bloom and bloom:IsA("BloomEffect") then
		bloom.Intensity = curve(FX.bloom, t) * boost * (if run.reduced then 0.8 else 1)
	end
	if rays and rays:IsA("SunRaysEffect") then
		rays.Intensity = curve(FX.sunRays, t) * (if run.reduced then 0.7 else 1)
	end
	if grade and grade:IsA("ColorCorrectionEffect") then
		local k = curve(FX.grade, t)
		grade.Saturation = FX.saturation * k
		grade.Contrast = FX.contrast * k
	end
end

--------------------------------------------------------------------------------
-- Aufraeumen
--------------------------------------------------------------------------------

local function cleanup(run: Run, reason: string)
	if run.ended then return end
	run.ended = true
	if _run == run then _run = nil end

	if run.stop then run.stop() run.stop = nil end
	for _, c in run.conns do
		c:Disconnect()
	end
	table.clear(run.conns)
	-- Musik: nach regulärem Ende ("done") und beim Wechsel ins Finale ("finale") bleibt sie,
	-- bei jedem Abbruch (Tod, Respawn, Fehler, neuer Lauf ausser Finale) geht sie sanft aus.
	if reason ~= "done" and reason ~= "finale" and reason ~= "new_run" then musicOff() end

	-- Kamera zurueck
	local cam = run.camera
	pcall(function()
		cam.FieldOfView = run.saved.fov
		cam.CameraType = run.saved.cameraType
		if run.saved.subject then cam.CameraSubject = run.saved.subject :: any end
	end)

	-- Licht, UI
	for _, e in run.effects do
		e:Destroy()
	end
	table.clear(run.effects)
	EpilogOverlay.finish()
	showHud(run.hidden)
	table.clear(run.hidden)

	-- Avatar und Steuerung
	local hum = run.humanoid
	if hum and hum.Parent then
		hum.WalkSpeed = run.walkSpeed
		pcall(function()
			local root = hum.RootPart
			if root then hum:MoveTo(root.Position) end
		end)
	end
	setControls(run, false)
	for _, p in run.planks do
		if p.Parent then p:SetAttribute("EpilogFlash", nil) end
	end
	if reason ~= "done" then
		warn("[EpilogController] Fahrt beendet:", reason)
	end
end

--------------------------------------------------------------------------------
-- Planken: golden aufblitzen, wenn der Avatar drueberlaeuft (rein visuell)
--------------------------------------------------------------------------------

local function collectPlanks(run: Run)
	for _, d in Workspace:GetDescendants() do
		if d:IsA("BasePart") and string.sub(d.Name, 1, 12) == "Epilog_Plank" then
			table.insert(run.planks, d)
			if #run.planks >= 80 then break end
		end
	end
end

local function flashPlanks(run: Run, pos: Vector3)
	for _, p in run.planks do
		if p.Parent and p:GetAttribute("EpilogFlash") == nil then
			local d = (p.Position - pos)
			if Vector3.new(d.X, 0, d.Z).Magnitude < 2.5 then
				p:SetAttribute("EpilogFlash", true)
				local old = p.Color
				p.Color = FX.colors.gold
				Kit.tween(p, 0.6, { Color = old })
				task.delay(0.8, function()
					if p.Parent then p:SetAttribute("EpilogFlash", nil) end
				end)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Lauf des Avatars
--------------------------------------------------------------------------------

local function walk(run: Run, t: number)
	local hum = run.humanoid
	local root = if hum then hum.RootPart else nil
	if not hum or not root or hum.Health <= 0 then return end
	local tau = t - Q.walkAt
	if tau < 0 or t >= Q.arriveAt then return end
	local progress = EpilogRoute.project(run.route, arr(root.Position))
	local want = EpilogRoute.distanceAt(run.profile, tau)
	local base = EpilogRoute.speedAt(run.profile, tau) * run.speed
	local speed = math.clamp(base + (want - progress) * 1.5, Q.walkMinSpeed, Q.walkMaxSpeed * math.max(1, run.speed))
	hum.WalkSpeed = speed
	local carrot = EpilogRoute.pointAt(run.route, math.min(run.route.length, progress + 6))
	hum:MoveTo(v3(carrot))
	flashPlanks(run, root.Position)
	-- Schritte auf Holz im Takt 0,28 s (Tonhoehe +/-5 % kommt aus Audio.SFX.epilog_run);
	-- nur wenn der Avatar wirklich laeuft, und nach einem Skip/Sprung nicht nachholen.
	if t >= run.stepAt then
		run.stepAt = math.max(run.stepAt + EpilogConfig.STEP_INTERVAL, t)
		if root.AssemblyLinearVelocity.Magnitude > 2 then playCue("run") end
	end
end

--------------------------------------------------------------------------------
-- Skip
--------------------------------------------------------------------------------

local function skipVisible(run: Run, t: number): boolean
	return t >= Q.skipFromSeconds and t < Q.arriveAt and not run.skipSent
end

local function doSkip(run: Run)
	if run.skipSent then return end
	run.skipSent = true
	Remotes.EpilogSkip:FireServer(run.token)
	local t = sequenceTime(run)
	run.jump += math.max(0, Q.arriveAt - t)
	run.cuesDone[3] = true
	EpilogOverlay.flashNow(FX.skipFlashSeconds, "skip")
	EpilogOverlay.setSkip(false, 0)
end

local function skipInput(run: Run, down: boolean)
	if run.ended then return end
	if down then
		if skipVisible(run, sequenceTime(run)) then run.skipHeld = os.clock() end
	else
		run.skipHeld = nil
	end
end

local function connectSkip(run: Run)
	local button = EpilogOverlay.skipButton()
	if button then
		table.insert(run.conns, button.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				skipInput(run, true)
			end
		end))
		table.insert(run.conns, button.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				skipInput(run, false)
			end
		end))
	end
	table.insert(run.conns, UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonX then
			skipInput(run, true)
		end
	end))
	table.insert(run.conns, UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonX then
			skipInput(run, false)
		end
	end))
end

--------------------------------------------------------------------------------
-- Der Takt (eine einzige Kit.animate-Schleife)
--------------------------------------------------------------------------------

local function defaultPose(run: Run): EpilogCameraPath.Pose
	local hum = run.humanoid
	local root = if hum then hum.RootPart else nil
	if not root then
		return { pos = run.ctx.cam0, look = run.ctx.avatar, fov = run.saved.fov }
	end
	local look = root.CFrame.LookVector
	local head = root.Position + Vector3.new(0, 2, 0)
	return {
		pos = arr(head - Vector3.new(look.X, 0, look.Z).Unit * 12 + Vector3.new(0, 5, 0)),
		look = arr(head),
		fov = run.saved.fov,
	}
end

local function step(run: Run): boolean
	if run.ended then return false end
	local now = os.clock()
	local dt = math.min(now - run.lastClock, 0.1)
	run.lastClock = now

	local hum = run.humanoid
	if not hum or hum.Health <= 0 or hum.Parent == nil then
		cleanup(run, "avatar_gone")
		return false
	end
	local root = hum.RootPart
	if not root then
		cleanup(run, "no_root")
		return false
	end

	local t = sequenceTime(run)
	-- Kontext aktualisieren
	local ctx = run.ctx
	ctx.avatar = arr(root.Position)
	ctx.progress = EpilogRoute.project(run.route, ctx.avatar)
	ctx.default = defaultPose(run)

	local pose, phase = EpilogCameraPath.sample(t, ctx)
	run.camera.CFrame = CFrame.lookAt(v3(pose.pos), v3(pose.look))
	run.camera.FieldOfView = pose.fov

	updateEffects(run, t)
	EpilogOverlay.update(t, dt, phase)
	walk(run, t)

	-- Cues
	for i, c in EpilogConfig.CUE_TIMES do
		if not run.cuesDone[i] and t >= c[1] then
			run.cuesDone[i] = true
			-- "run" macht walk() im Schritt-Takt; veraltete Cues (nach Skip/Sprung) bleiben stumm
			if c[2] ~= "run" and t - c[1] <= EpilogConfig.CUE_LATE_SECONDS then
				playCue(c[2] :: string)
			end
		end
	end
	if not run.momentDone and t >= FX.momentAt then
		run.momentDone = true
		Moment.show("milestone", FX.colors.gold, "ui.moment.tower_cleared")
	end

	-- Skip-Ring
	local show = skipVisible(run, t)
	local progress = 0
	if run.skipHeld then
		progress = (now - run.skipHeld) / Q.skipHoldSeconds
		if progress >= 1 and show then
			run.skipHeld = nil
			doSkip(run)
			show = false
		end
	end
	EpilogOverlay.setSkip(show, progress)

	-- Steuerung zurueck, Ende der Fahrt
	if t >= EpilogConfig.TIMELINE.ARRIVAL_END then
		if not run.seenSent then
			run.seenSent = true
			Remotes.EpilogSeen:FireServer(run.token)
		end
		setControls(run, false)
		hum.WalkSpeed = run.walkSpeed
	end
	if t >= EpilogConfig.TIMELINE.ARRIVAL_END + Q.blendBackSeconds then
		cleanup(run, "done")
		return false
	end
	return true
end

--------------------------------------------------------------------------------
-- Start
--------------------------------------------------------------------------------

local function startFull(payload: any)
	if _run then cleanup(_run, "new_run") end
	local character = player.Character
	local hum = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local camera = Workspace.CurrentCamera
	local info = payload.route
	if not hum or not hum.RootPart or not camera or type(info) ~= "table" or type(info.points) ~= "table" then
		-- Ohne Wegdaten laeuft die Fahrt nicht; der Server hat seinen Zeitplan trotzdem
		-- (EpilogSeen kommt dann nach dem Mindestabstand von selbst).
		task.delay(EpilogConfig.SEEN_MIN_SECONDS, function()
			Remotes.EpilogSeen:FireServer(payload.token)
		end)
		return
	end

	local route = EpilogRoute.new(info.points)
	local reduced = intensity() == "reduced"
	local speed = math.clamp(tonumber(payload.speed) or 1, Q.minSpeed, Q.maxSpeed)
	local startAt = tonumber(payload.startAt) or Workspace:GetServerTimeNow()

	local run: Run = {
		token = tostring(payload.token), startAt = startAt, speed = speed, jump = 0,
		ctx = {
			cam0 = arr(camera.CFrame.Position), fov0 = camera.FieldOfView,
			summit = { center = info.summit, dir = info.dir },
			route = route, avatar = arr(hum.RootPart.Position), progress = 0,
			island = { center = info.island },
			terminal = { pos = info.terminalPos, look = info.terminalLook },
			default = { pos = arr(camera.CFrame.Position), look = arr(hum.RootPart.Position), fov = camera.FieldOfView },
			reduced = reduced,
		},
		route = route,
		profile = EpilogRoute.profile(route.length, Q.arriveAt - Q.walkAt, Q.walkFactors),
		camera = camera,
		saved = { cameraType = camera.CameraType, subject = camera.CameraSubject, fov = camera.FieldOfView, cframe = camera.CFrame },
		humanoid = hum, walkSpeed = hum.WalkSpeed,
		stop = nil, conns = {}, effects = {}, controls = getControls(), controlsOff = false,
		hidden = hideHud(),
		skipHeld = nil, skipSent = false, cuesDone = {}, momentDone = false, seenSent = false,
		planks = {}, reduced = reduced, ended = false, lastClock = os.clock(), stepAt = Q.walkAt,
	}
	_run = run
	musicOn()
	watchMusic()
	camera.CameraType = Enum.CameraType.Scriptable
	setControls(run, true)
	makeEffects(run)
	collectPlanks(run)
	EpilogOverlay.begin(if reduced then "reduced" else "full")
	connectSkip(run)

	-- Tod, Respawn, Verlassen: sofort sauber beenden
	table.insert(run.conns, hum.Died:Connect(function() cleanup(run, "died") end))
	table.insert(run.conns, player.CharacterRemoving:Connect(function() cleanup(run, "char_removed") end))
	table.insert(run.conns, Players.PlayerRemoving:Connect(function(p)
		if p == player then cleanup(run, "player_left") end
	end))

	run.stop = Kit.animate(function(): boolean
		local ok, keep = pcall(step, run)
		if not ok then
			cleanup(run, "error:" .. tostring(keep))
			return false
		end
		return keep :: boolean
	end)
end

-- Wiederaufnahme: nur Flash; EpilogSeen, sobald der Avatar am Terminal steht.
local function startRestore(payload: any)
	local token = tostring(payload.token)
	EpilogOverlay.flashNow(Q.restoreFlashSeconds, "restore")
	if payload.state ~= "pending" then return end
	musicOn()
	watchMusic()
	if _restoreWatch then task.cancel(_restoreWatch) end
	_restoreWatch = task.spawn(function()
		for _ = 1, 240 do
			task.wait(0.5)
			local character = player.Character
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			local terminal = nearestTerminal(root :: BasePart?)
			if root and terminal then
				if (terminal:GetPivot().Position - (root :: BasePart).Position).Magnitude < Q.arriveRadius * 1.5 then
					Remotes.EpilogSeen:FireServer(token)
					return
				end
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- Prompt 6: Knopf-Finale (Countdown, Start, Feier, Rueckweg)
--------------------------------------------------------------------------------

local FIN = EpilogConfig.FINALE

type FRun = {
	token      : string,
	startAt    : number,
	speed      : number,
	jump       : number,
	humanoid   : Humanoid?,
	fx         : EpilogFinaleFX.Instance,
	conns      : { RBXScriptConnection },
	stop       : (() -> ())?,
	controls   : any?,
	controlsOff: boolean,
	hidden     : { GuiObject },
	skipHeld   : number?,
	skipSent   : boolean,
	counted    : number,        -- wie viele Countdown-Zahlen schon gezeigt
	silence    : boolean,
	launched   : boolean,
	salvos     : number,
	bannerDone : boolean,
	returned   : boolean,
	reduced    : boolean,
	ended      : boolean,
	lastClock  : number,
}

local _fin: FRun? = nil

-- Waechter: steht weder Sequenz noch Finale und der Avatar ist weit weg vom Terminal
-- (Server-Rueckholung, Teleport, Abbruch), geht die Epilog-Musik sanft aus.
local _musicWatch: thread? = nil
watchMusic = function()
	if _musicWatch then return end
	_musicWatch = task.spawn(function()
		local away = 0
		while true do
			task.wait(1)
			if _run == nil and _fin == nil then
				local character = player.Character
				local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
				local terminal = nearestTerminal(root :: BasePart?)
				local near = terminal ~= nil and root ~= nil
					and (terminal:GetPivot().Position - (root :: BasePart).Position).Magnitude < 160
				away = if near then 0 else away + 1
				if away >= 3 then break end
			else
				away = 0
			end
		end
		_musicWatch = nil
		musicOff()
	end)
end

local function finaleTime(run: FRun): number
	return math.max(0, (Workspace:GetServerTimeNow() - run.startAt) * run.speed) + run.jump
end

local function finaleControls(run: FRun, off: boolean)
	if run.controls == nil then return end
	if off and not run.controlsOff then
		run.controlsOff = true
		pcall(function() run.controls:Disable() end)
	elseif not off and run.controlsOff then
		run.controlsOff = false
		pcall(function() run.controls:Enable() end)
	end
end

-- Beendet das Finale lokal: Effekte, Schuetteln, Steuerung, HUD. `keepOverlaySeconds`: der
-- Hinweis "Welt 2: Weg folgt bald" bleibt noch so lange sichtbar, dann geht die Schicht aus.
local function endFinale(run: FRun, reason: string, hintSeconds: number?)
	if run.ended then return end
	run.ended = true
	if _fin == run then _fin = nil end
	musicOff()   -- 2 s sanft zurueck zur Spielmusik (auch bei Abbruch)
	if run.stop then run.stop() run.stop = nil end
	for _, c in run.conns do c:Disconnect() end
	table.clear(run.conns)
	EpilogFinaleFX.destroy(run.fx)
	finaleControls(run, false)
	showHud(run.hidden)
	table.clear(run.hidden)
	local hum = run.humanoid
	if hum and hum.Parent then hum.CameraOffset = Vector3.zero end
	EpilogOverlay.setCountdown(0)
	EpilogOverlay.rain(0)
	EpilogOverlay.setSkip(false, 0)
	if hintSeconds and hintSeconds > 0 then
		EpilogOverlay.hint(Loc.t("epilog.finale.hint_world2"), hintSeconds)
		task.delay(hintSeconds + 0.6, function()
			if _run == nil and _fin == nil then EpilogOverlay.finish() end
		end)
	else
		EpilogOverlay.finish()
	end
	if reason ~= "done" and reason ~= "server_end" then
		warn("[EpilogController] Finale beendet:", reason)
	end
end

local function finaleSkipInput(run: FRun, down: boolean)
	if run.ended then return end
	if down then
		local f = finaleTime(run)
		if f >= FIN.skipFromSeconds and f < FIN.returnAt and not run.skipSent then
			run.skipHeld = os.clock()
		end
	else
		run.skipHeld = nil
	end
end

local function finaleStep(run: FRun): boolean
	if run.ended then return false end
	local now = os.clock()
	local dt = math.min(now - run.lastClock, 0.1)
	run.lastClock = now
	local hum = run.humanoid
	if not hum or hum.Parent == nil or hum.Health <= 0 then
		endFinale(run, "avatar_gone")
		return false
	end
	local f = finaleTime(run)

	-- Countdown 3 ... 2 ... 1 (Terminal zeigt ihn selbst, hier die grosse Zahl am Rand)
	while run.counted < #FIN.countTimes and f >= FIN.countTimes[run.counted + 1] do
		run.counted += 1
		local n = #FIN.countTimes - run.counted + 1
		EpilogOverlay.setCountdown(n, Loc.t("epilog.finale.count_" .. tostring(math.clamp(n, 1, 3))))
		playCue("countdown")
	end
	if not run.silence and f >= FIN.silenceAt then
		run.silence = true
		EpilogOverlay.setCountdown(0)
		pcall(function() AudioController.duck(FIN.launchAt - FIN.silenceAt + 0.4) end)
	end
	-- Start: weisser Flash, Salven (3 x 0,4 s), Konfetti-Regen
	if not run.launched and f >= FIN.launchAt then
		run.launched = true
		EpilogOverlay.flashNow(0.5, "skip")
		EpilogOverlay.rain(if run.reduced then 25 else 50)
		playCue("launch")
	end
	if run.launched and run.salvos < FIN.salvos and f >= FIN.launchAt + run.salvos * FIN.salvoGap then
		run.salvos += 1
		EpilogOverlay.salvo()
	end
	-- Feier: Banner genau einmal (auch nach einem Skip)
	if not run.bannerDone and f >= FIN.celebrateAt then
		run.bannerDone = true
		EpilogOverlay.rain(0)
		EpilogOverlay.banner(Loc.t("epilog.finale.banner"), 2.4)
		Moment.show("unlock", EpilogConfig.FX.colors.gold, "ui.moment.world2")
		playCue("unlock")
	end
	if f >= FIN.celebrateAt + 0.5 then EpilogOverlay.rain(0) end

	EpilogFinaleFX.update(run.fx, f, dt)
	EpilogOverlay.update(-1000, dt, 0)

	-- Skip-Ring (erst ab Sekunde 5)
	local show = f >= FIN.skipFromSeconds and f < FIN.returnAt and not run.skipSent
	local progress = 0
	if run.skipHeld then
		progress = (now - run.skipHeld) / Q.skipHoldSeconds
		if progress >= 1 and show then
			run.skipHeld = nil
			run.skipSent = true
			Remotes.EpilogSkip:FireServer(run.token)
			run.jump += math.max(0, FIN.returnAt - f)
			show = false
		end
	end
	EpilogOverlay.setSkip(show, progress)

	-- Sicherheitsnetz: kommt das Server-Ende nie an, geben wir selbst frei
	if f > FIN.returnAt + 40 then
		endFinale(run, "timeout", 0)
		return false
	end
	return true
end

local function startFinale(payload: any)
	if _run then cleanup(_run, "finale") end
	if _fin then endFinale(_fin, "new_finale", 0) end
	local character = player.Character
	local hum = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local info = payload.route
	if not hum or type(info) ~= "table" then return end

	local reduced = intensity() == "reduced"
	local speed = math.clamp(tonumber(payload.speed) or 1, FIN.minSpeed, FIN.maxSpeed)
	local fx = EpilogFinaleFX.new({
		rocketBase = payload.rocketBase, island = info.island, dir = info.dir,
	}, hum, reduced)
	local run: FRun = {
		token = tostring(payload.token), startAt = tonumber(payload.startAt) or Workspace:GetServerTimeNow(),
		speed = speed, jump = 0, humanoid = hum, fx = fx, conns = {}, stop = nil,
		controls = getControls(), controlsOff = false, hidden = hideHud(),
		skipHeld = nil, skipSent = false, counted = 0, silence = false, launched = false, salvos = 0,
		bannerDone = false, returned = false, reduced = reduced, ended = false, lastClock = os.clock(),
	}
	_fin = run
	musicOn()   -- falls die Sequenz uebersprungen/wiederaufgenommen wurde (idempotent)
	watchMusic()
	finaleControls(run, true)
	EpilogOverlay.begin(if reduced then "reduced" else "full")
	local button = EpilogOverlay.skipButton()
	if button then
		table.insert(run.conns, button.InputBegan:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				finaleSkipInput(run, true)
			end
		end))
		table.insert(run.conns, button.InputEnded:Connect(function(input: InputObject)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				finaleSkipInput(run, false)
			end
		end))
	end
	table.insert(run.conns, UserInputService.InputBegan:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonX then finaleSkipInput(run, true) end
	end))
	table.insert(run.conns, UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.ButtonX then finaleSkipInput(run, false) end
	end))
	table.insert(run.conns, hum.Died:Connect(function() endFinale(run, "died", 0) end))
	table.insert(run.conns, player.CharacterRemoving:Connect(function() endFinale(run, "char_removed", 0) end))
	playCue("press")

	run.stop = Kit.animate(function(): boolean
		local ok, keep = pcall(finaleStep, run)
		if not ok then
			endFinale(run, "error:" .. tostring(keep), 0)
			return false
		end
		return keep :: boolean
	end)
end

-- Antworten des Servers waehrend des Finales: "return" (Flash zum Rueckweg), "end" (fertig).
local function onLaunchResult(payload: any)
	if type(payload) ~= "table" then return end
	if payload.phase == "start" and payload.ok == true then
		local ok, err = pcall(startFinale, payload)
		if not ok then
			warn("[EpilogController] Finale-Start fehlgeschlagen:", err)
			if _fin then endFinale(_fin, "start_error", 0) end
		end
	elseif payload.phase == "return" then
		local run = _fin
		if run then
			run.returned = true
			EpilogOverlay.flashNow(FIN.returnFlashSeconds, "skip")
			EpilogOverlay.setCountdown(0)
			EpilogOverlay.rain(0)
			EpilogOverlay.setSkip(false, 0)
		end
	elseif payload.phase == "end" then
		local run = _fin
		if run then
			endFinale(run, "server_end", if payload.aborted == true then 0 else FIN.hintSeconds)
		elseif payload.aborted ~= true then
			EpilogOverlay.init()
		end
	end
end

--------------------------------------------------------------------------------
-- Debug-Audit (epilog audit)
--------------------------------------------------------------------------------

local function audit(): { [string]: any }
	local cam = Workspace.CurrentCamera
	local count = 0
	for _, c in Lighting:GetChildren() do
		if string.sub(c.Name, 1, 6) == "Epilog" then count += 1 end
	end
	local hum = if player.Character then player.Character:FindFirstChildOfClass("Humanoid") else nil
	local run = _run
	return {
		fahrtLaeuft = run ~= nil,
		finaleLaeuft = _fin ~= nil,
		finaleSteuerungAus = _fin ~= nil and (_fin :: FRun).controlsOff,
		finaleFx = EpilogFinaleFX.audit(),
		cameraOffset = if hum then hum.CameraOffset.Magnitude else 0,
		kameraTyp = if cam then cam.CameraType.Name else "?",
		fov = if cam then cam.FieldOfView else 0,
		lichtEffekte = count,
		steuerungAus = run ~= nil and run.controlsOff,
		verbindungen = (if run then #run.conns else 0) + (if _fin then #_fin.conns else 0),
		animationen = Kit.activeAnimations(),
		walkSpeed = if hum then hum.WalkSpeed else 0,
		hudVersteckt = (if _run then #_run.hidden else 0) + (if _fin then #_fin.hidden else 0),
		overlay = EpilogOverlay.audit(),
		audio = AudioController.epilogAudit(),
	}
end

EpilogController.audit = audit

function EpilogController.isRunning(): boolean
	return _run ~= nil
end

function EpilogController.init()
	Remotes.EpilogStart.OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then return end
		local ok, err = pcall(function()
			if payload.mode == EpilogConfig.MODE.RESTORE then
				startRestore(payload)
			else
				startFull(payload)
			end
		end)
		if not ok then
			warn("[EpilogController] Start fehlgeschlagen:", err)
			if _run then cleanup(_run, "start_error") end
		end
	end)

	Remotes.EpilogLaunchResult.OnClientEvent:Connect(onLaunchResult)

	Remotes.EpilogDebug.OnClientEvent:Connect(function(payload: any)
		if type(payload) == "table" and payload.cmd == "audit" then
			Remotes.EpilogDebugReport:FireServer(audit())
		end
	end)
end

return EpilogController
