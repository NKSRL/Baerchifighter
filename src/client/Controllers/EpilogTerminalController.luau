--!strict
-- EpilogTerminalController.luau
-- StarterPlayerScripts/Controllers/EpilogTerminalController.luau
--
-- Einzige Zustaendigkeit (Prompt 4 von 7, Final-Epilog):
--   - Das Start-Terminal auf der Insel lebendig machen: Bildschirmtext (in der
--     Sprache des Betrachters), Lampen, Schutzklappe, Knopf (Pulsieren, Senken),
--     Funken — alles aus dem Attribut `EpilogTerminalState` am Modell `Terminal`
--     (idle, ready, armed, fired, done). Der Server baut das Modell einmal und
--     fuehrt den Zustand; hier wird nur gezeigt (wie TerminalController).
--
-- Bewegungsvokabular: mechanisch-schwer, Scharniere mit Overshoot (Back), Knopf
-- Quad; kein Wackeln. Lampen blinken mit zufaelligem Mikro-Offset (+-0,1 s).
-- Der Prompt (Halten 1,2 s, Ladering) ist ein normaler serverseitiger
-- ProximityPrompt; sein Text kommt ueber WorldText.
--
-- Eine Heartbeat-Verbindung, nur solange mindestens ein Terminal steht.

local CollectionService = game:GetService("CollectionService")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loc          = require(ReplicatedStorage.Localization.Loc)
local EpilogConfig = require(ReplicatedStorage.Config.EpilogConfig)
local Audio        = require(ReplicatedStorage.Audio)
local AudioController = require(script.Parent.AudioController)

local EpilogTerminalController = {}

local T  = EpilogConfig.TERMINAL
local ST = T.STATE
local PREFIX = "Epilog_Terminal_"

type View = {
	model     : Model,
	lamps     : { BasePart },
	jitter    : { number },
	lid       : BasePart,
	lidClosed : CFrame,
	hingeCF   : CFrame,
	knob      : BasePart,
	knobClosed: CFrame,
	label     : TextLabel,
	emitter   : ParticleEmitter?,
	angle     : NumberValue,   -- Klappe in Bogenmass
	press     : NumberValue,   -- Knopf gesenkt in Studs
	angleTween: Tween?,
	pressTween: Tween?,
	hum       : Sound?,        -- leises Summen (3D, Schleife) solange das Terminal wartet
	state     : string,
	stateAt   : number,
	conns     : { RBXScriptConnection },
}

local _views: { [Model]: View } = {}
local _count = 0
local _beat: RBXScriptConnection? = nil
local _langConn: any = nil

--------------------------------------------------------------------------------
-- Zustand -> Darstellung
--------------------------------------------------------------------------------

local SCREEN_KEY: { [string]: string } = {
	[ST.IDLE]  = "epilog.terminal.screen_idle",
	[ST.READY] = "epilog.terminal.screen_ready",
	[ST.ARMED] = "epilog.terminal.screen_armed",
	[ST.FIRED] = "epilog.terminal.screen_fired",
	[ST.DONE]  = "epilog.terminal.screen_done",
}

local function screenColor(state: string): Color3
	local c = T.colors
	if state == ST.FIRED or state == ST.DONE then return c.green end
	if state == ST.READY or state == ST.ARMED then return c.yellow end
	return c.red
end

-- Prompt 6: Countdown-Zahl (Attribut EpilogCountdown, 3 / 2 / 1; 0 oder fehlt = keine)
local function countdownOf(model: Model): number
	local n = model:GetAttribute(T.COUNTDOWN_ATTRIBUTE)
	return if typeof(n) == "number" then n else 0
end

local function setText(view: View)
	local n = countdownOf(view.model)
	if view.state == ST.FIRED and n > 0 then
		view.label.Text = Loc.t("epilog.finale.count_" .. tostring(math.clamp(math.floor(n), 1, 3)))
		view.label.TextColor3 = T.colors.yellow
		return
	end
	view.label.Text = Loc.t(SCREEN_KEY[view.state] or SCREEN_KEY[ST.IDLE])
	view.label.TextColor3 = screenColor(view.state)
end

local function applyLid(view: View)
	view.lid.CFrame = view.hingeCF * CFrame.Angles(view.angle.Value, 0, 0)
		* (view.hingeCF:Inverse() * view.lidClosed)
end

local function applyKnob(view: View)
	view.knob.CFrame = view.knobClosed - view.knobClosed.RightVector * view.press.Value
end

local function targetAngle(state: string): number
	if state == ST.READY then return math.rad(T.lidReadyDeg) end
	if state == ST.ARMED or state == ST.FIRED or state == ST.DONE then return math.rad(T.lidOpenDeg) end
	return 0
end

-- Summen nur vor dem Druck (idle/ready/armed); danach schweigt das Terminal.
local function updateHum(view: View)
	local hum = view.hum
	if not hum then return end
	local waiting = view.state == ST.IDLE or view.state == ST.READY or view.state == ST.ARMED
	if waiting and not hum.IsPlaying then hum:Play() elseif not waiting and hum.IsPlaying then hum:Stop() end
end

local function play(view: View, instant: boolean)
	local state = view.state
	local angle = targetAngle(state)
	local pressed = if state == ST.FIRED or state == ST.DONE then T.pressDepth else 0

	if view.angleTween then view.angleTween:Cancel() end
	if view.pressTween then view.pressTween:Cancel() end
	if instant then
		view.angle.Value = angle
		view.press.Value = pressed
	else
		local opening = angle > view.angle.Value
		local seconds = if state == ST.READY then T.lidReadySeconds
			elseif opening then T.lidOpenSeconds else T.lidCloseSeconds
		local at = TweenService:Create(view.angle, TweenInfo.new(seconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Value = angle })
		view.angleTween = at
		at:Play()
		-- harter Klack beim Druecken (Quad In), sanft zurueck beim Loslassen (Quad Out)
		local down = pressed > view.press.Value
		local pt = TweenService:Create(view.press, TweenInfo.new(if down then T.pressSeconds else T.releaseSeconds,
			Enum.EasingStyle.Quad, if down then Enum.EasingDirection.In else Enum.EasingDirection.Out), { Value = pressed })
		view.pressTween = pt
		pt:Play()
	end
	if view.emitter then
		view.emitter.Enabled = (state == ST.FIRED or state == ST.DONE)
	end
	setText(view)
	updateHum(view)
end

local function readState(model: Model): string
	local raw = model:GetAttribute(T.ATTRIBUTE)
	if typeof(raw) == "string" and SCREEN_KEY[raw] then return raw end
	return ST.IDLE
end

--------------------------------------------------------------------------------
-- Lampen und Knopf (pro Frame, nur Farben)
--------------------------------------------------------------------------------

local function scale(c: Color3, f: number): Color3
	return Color3.new(math.min(1, c.R * f), math.min(1, c.G * f), math.min(1, c.B * f))
end

local function animate(view: View, now: number)
	local c = T.colors
	local age = now - view.stateAt
	local state = view.state
	for i, lamp in view.lamps do
		local color: Color3
		if state == ST.IDLE then
			-- rot blinkend, jede Lampe mit eigenem Mikro-Offset
			local phase = (now + view.jitter[i]) % T.blinkSeconds
			color = if phase < T.blinkSeconds / 2 then c.red else c.lampOff
		elseif state == ST.READY then
			-- der Reihe nach auf Gelb
			color = if age >= (i - 1) * T.lampStepSeconds then c.yellow else c.red
		elseif state == ST.ARMED then
			color = if now % 0.3 < 0.15 then c.yellow else c.lampOff
		elseif state == ST.FIRED then
			local n = countdownOf(view.model)
			if n > 0 then
				-- Countdown: von Gelb der Reihe nach auf Gruen (3: alle gelb, 2: eine gruen, 1: zwei gruen)
				color = if i <= T.lampCount - n then c.green else c.yellow
			else
				-- kurz gruen blitzen, dann dauerhaft gruen
				color = if age < T.fireFlashSeconds and now % 0.2 >= 0.1 then c.lampOff else c.green
			end
		else
			color = c.green
		end
		lamp.Color = color
	end

	-- Knopf pulsiert (Glow +-15 %, 1,2 s), solange er bereit ist
	local factor = 1
	if state == ST.READY or state == ST.ARMED then
		factor = 1 + T.pulseAmount * math.sin(now * 2 * math.pi / T.pulseSeconds)
	end
	view.knob.Color = scale(c.red, factor)
end

local function onBeat()
	local now = os.clock()
	for _, view in _views do
		animate(view, now)
	end
end

local function startBeat()
	if _beat == nil then
		_beat = RunService.Heartbeat:Connect(onBeat)
	end
end

local function stopBeat()
	if _beat ~= nil and _count == 0 then
		_beat:Disconnect()
		_beat = nil
	end
end

--------------------------------------------------------------------------------
-- Ansicht auf- und abbauen
--------------------------------------------------------------------------------

local function forget(model: Model)
	local view = _views[model]
	if not view then return end
	_views[model] = nil
	_count -= 1
	if view.angleTween then view.angleTween:Cancel() end
	if view.pressTween then view.pressTween:Cancel() end
	for _, conn in view.conns do conn:Disconnect() end
	view.angle:Destroy()
	view.press:Destroy()
	if view.hum then view.hum:Destroy() end
	stopBeat()
end

local function build(model: Model)
	if _views[model] then return end
	local function part(name: string): BasePart?
		local found = model:WaitForChild(PREFIX .. name, 10)
		return if found and found:IsA("BasePart") then found else nil
	end
	local screen, lid, knob = part("Bildschirm"), part("Klappe"), part("Knopf")
	local korpus = part("Korpus")
	if not (screen and lid and knob and korpus) or _views[model] then return end
	local hinge = korpus:WaitForChild("Scharnier", 10)
	if not (hinge and hinge:IsA("Attachment")) then return end
	local lamps: { BasePart } = {}
	local jitter: { number } = {}
	local rng = Random.new()
	for i = 1, T.lampCount do
		local lamp = part("Lampe" .. i)
		if not lamp then return end
		table.insert(lamps, lamp)
		table.insert(jitter, rng:NextNumber(-T.blinkJitter, T.blinkJitter))
	end

	-- Bildschirm (SurfaceGui auf der Oberseite des Schirm-Teils)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "EpilogSchirm"
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(420, 100)
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	gui.Parent = screen
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.Code
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = T.colors.red
	label.Parent = gui

	local funken = knob:FindFirstChild("Funken")
	local emitter = if funken then funken:FindFirstChildOfClass("ParticleEmitter") else nil

	local view: View = {
		model = model, lamps = lamps, jitter = jitter,
		lid = lid, lidClosed = lid.CFrame, hingeCF = hinge.WorldCFrame,
		knob = knob, knobClosed = knob.CFrame, label = label, emitter = emitter,
		angle = Instance.new("NumberValue"), press = Instance.new("NumberValue"),
		angleTween = nil, pressTween = nil, hum = nil,
		state = readState(model), stateAt = os.clock(), conns = {},
	}
	_views[model] = view
	_count += 1

	-- Summen: 3D-Schleife am Korpus, folgt dem Effekt-Regler (SoundGroup) und der Stumm-Taste
	local humId = Audio.sfxId("epilog_terminal_idle")
	local humDef = Audio.SFX.epilog_terminal_idle
	if humId ~= "" and humDef then
		local hum = Instance.new("Sound")
		hum.Name = "Epilog_TerminalSummen"
		hum.SoundId = humId
		hum.Looped = true
		hum.Volume = humDef.volume
		hum.RollOffMode = Enum.RollOffMode.Linear
		hum.RollOffMinDistance = 6
		hum.RollOffMaxDistance = 40
		hum.SoundGroup = AudioController.sfxGroup()
		hum.Parent = korpus
		view.hum = hum
	end

	table.insert(view.conns, view.angle.Changed:Connect(function() applyLid(view) end))
	table.insert(view.conns, view.press.Changed:Connect(function() applyKnob(view) end))
	table.insert(view.conns, model:GetAttributeChangedSignal(T.ATTRIBUTE):Connect(function()
		local new = readState(model)
		if new == view.state then return end
		view.state = new
		view.stateAt = os.clock()
		play(view, false)
		-- Piepton, wenn das Terminal bereit wird (Avatar nah genug)
		if new == ST.READY then AudioController.play(EpilogConfig.CUES.ready) end
	end))
	table.insert(view.conns, model:GetAttributeChangedSignal(T.COUNTDOWN_ATTRIBUTE):Connect(function()
		setText(view)
	end))
	table.insert(view.conns, model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then forget(model) end
	end))

	play(view, true)
	startBeat()
end

--------------------------------------------------------------------------------
-- Start
--------------------------------------------------------------------------------

function EpilogTerminalController.init()
	local function onAdded(instance: Instance)
		if instance:IsA("Model") then
			task.spawn(build, instance)
		end
	end
	CollectionService:GetInstanceAddedSignal(T.TAG):Connect(onAdded)
	CollectionService:GetInstanceRemovedSignal(T.TAG):Connect(function(instance)
		if instance:IsA("Model") then forget(instance) end
	end)
	for _, instance in CollectionService:GetTagged(T.TAG) do
		onAdded(instance)
	end
	-- Sprachwechsel: Schirmtexte neu setzen
	_langConn = Loc.onChanged(function()
		for _, view in _views do setText(view) end
	end)
end

return EpilogTerminalController
