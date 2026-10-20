--!strict
-- AudioPanel.luau
-- StarterPlayerScripts/UI/AudioPanel.luau
--
-- Einzige Zustaendigkeit:
--   - Das Ton-Fenster: Regler fuer Musik und Effekte, Stumm-Taste
--   - Den kleinen Lautsprecher-Knopf unter dem Zahnrad, der es oeffnet
--
-- Was gilt und was gespeichert wird, entscheidet AudioController — dieses
-- Panel ruft nur dessen set() auf und zeigt den aktuellen Stand.
-- (Audio-Rework 16.10. Das Sprach-Fenster hat ein festes Bild als Rahmen
-- ohne Platz fuer Regler, deshalb ein eigenes kleines Fenster.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local Loc = require(ReplicatedStorage.Localization.Loc)

local Theme           = require(script.Parent.Theme)
local PanelManager    = require(script.Parent.PanelManager)
local AudioController = require(script.Parent.Parent.Controllers.AudioController)

local AudioPanel = {}

local PANEL_NAME = "Audio"

local _root: Frame? = nil
local _refresh: (() -> ())? = nil

-- Loc.bind haelt Beschriftungen nur schwach. Ein Label, das sonst niemand
-- festhaelt, kann vom Muellsammler eingesammelt werden und folgt dann dem
-- Sprachwechsel nicht mehr — deshalb hier festhalten.
local _keep: { Instance } = {}

local function openInternal(...: any)
	local root = _root
	if not root then return end
	root.Visible = true
	local refresh = _refresh
	if refresh then refresh() end
end

local function closeInternal()
	local root = _root
	if root then root.Visible = false end
end

-- Regler 0..1 in 5-%-Schritten, ziehen mit Maus oder Finger. onChange bekommt
-- den Wert laufend; gespeichert wird verzoegert (AudioController).
local function addSlider(body: Frame, order: number, bindKey: string, getValue: () -> number, onChange: (number) -> ()): () -> ()
	local row = Instance.new("Frame")
	row.Name = "Slider_" .. bindKey
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, -8, 0, 40)
	row.LayoutOrder = order
	row.Parent = body

	local label = Theme.label("Label", row, "")
	label.AutoLocalize = false
	table.insert(_keep, label)
	label.Size = UDim2.new(0.32, 0, 1, 0)
	Loc.bind(label, bindKey)

	local track = Instance.new("TextButton")
	track.Name = "Track"
	track.Text = ""
	track.AutoButtonColor = false
	track.AnchorPoint = Vector2.new(1, 0.5)
	track.Position = UDim2.new(1, -14, 0.5, 0)
	track.Size = UDim2.new(0.60, 0, 0, 14)
	track.BackgroundColor3 = Theme.COLORS.panelLight
	track.BorderSizePixel = 0
	track.Parent = row
	Theme.corner(track, 7)
	Theme.stroke(track, Theme.COLORS.outline, 2)

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = Theme.COLORS.goldGummy
	fill.BorderSizePixel = 0
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = track
	Theme.corner(fill, 7)

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.Size = UDim2.fromOffset(24, 24)
	knob.BackgroundColor3 = Theme.COLORS.text
	knob.BorderSizePixel = 0
	knob.ZIndex = 2
	knob.Parent = track
	Theme.corner(knob, 12)
	Theme.stroke(knob, Theme.COLORS.outline, 2)

	local function show(value: number)
		fill.Size = UDim2.fromScale(value, 1)
		knob.Position = UDim2.new(value, 0, 0.5, 0)
	end

	local dragging = false
	local function fromInput(position: Vector3)
		local width = math.max(track.AbsoluteSize.X, 1)
		local value = math.clamp((position.X - track.AbsolutePosition.X) / width, 0, 1)
		value = math.floor(value * 20 + 0.5) / 20
		show(value)
		onChange(value)
	end

	track.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			fromInput(input.Position)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			fromInput(input.Position)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			dragging = false
			AudioController.play("select")   -- kurzer Hoertest der Effekt-Lautstaerke
		end
	end)

	return function() show(getValue()) end
end

function AudioPanel.init(screenGui: ScreenGui)
	local root = Theme.dialog(
		"AudioPanel", screenGui,
		Vector2.new(0.30, 0.40),
		Vector2.new(280, 230),
		Vector2.new(360, 260)
	)
	_root = root

	local title = Theme.dialogHeader(root, "", function()
		PanelManager.close(PANEL_NAME)
	end)
	title.AutoLocalize = false
	table.insert(_keep, title)
	Loc.bind(title, "ui.audio.section")

	local body = Theme.dialogBody(root)
	Theme.listLayout(body, 10)

	local refreshMusic = addSlider(body, 1, "ui.audio.music",
		function() return AudioController.getSettings().music end,
		function(value) AudioController.set({ music = value }) end)
	local refreshSfx = addSlider(body, 2, "ui.audio.sfx",
		function() return AudioController.getSettings().sfx end,
		function(value) AudioController.set({ sfx = value }) end)

	local mute = Theme.button("Mute", body, "", Theme.COLORS.panelLight)
	mute.Size = UDim2.new(1, -8, 0, 40)
	mute.LayoutOrder = 3
	mute.TextColor3 = Theme.COLORS.text
	table.insert(_keep, mute)
	mute.AutoLocalize = false   -- Roblox uebersetzt sonst "Mute" selbst (zeigte "Stumm" bei en); Loc macht das
	Loc.bind(mute, "ui.audio.mute")
	mute.Activated:Connect(function()
		AudioController.set({ muted = not AudioController.getSettings().muted })
		AudioController.play("click")
	end)

	local function refreshAll()
		refreshMusic()
		refreshSfx()
		mute.BackgroundColor3 = if AudioController.getSettings().muted then Theme.COLORS.bad else Theme.COLORS.panelLight
	end
	_refresh = refreshAll
	AudioController.onSettingsChanged(refreshAll)
	refreshAll()

	-- Lautsprecher-Knopf: als 4. Knopf in die Knopf-Zeile oben links (HudRow:
	-- Zahnrad, Quests, Shop), sobald es sie gibt; sonst fest unter die Waehrungen.
	local button = Theme.button("AudioButton", screenGui, "🔊", Theme.COLORS.panelLight)
	button.AnchorPoint = Vector2.new(0, 0)
	button.Position    = UDim2.new(0.012, 12, 0, 150)
	button.Size        = UDim2.fromOffset(38, 38)
	button.TextColor3  = Theme.COLORS.text
	button.LayoutOrder = 4
	button.Activated:Connect(function()
		PanelManager.toggle(PANEL_NAME)
	end)
	task.spawn(function()
		local row = screenGui:WaitForChild("HudRow", 15)
		if row and row:IsA("GuiObject") then
			row.Size = row.Size + UDim2.fromOffset(44, 0)   -- Platz fuer den 4. Knopf (38 px + 6 px Abstand)
			button.Parent = row
		end
	end)
	AudioController.onSettingsChanged(function(settings)
		button.Text = if settings.muted or (settings.music <= 0 and settings.sfx <= 0) then "🔇" else "🔊"
	end)

	PanelManager.register(PANEL_NAME, {
		open  = openInternal,
		close = closeInternal,
	})

	print("[AudioPanel] Initialisiert")
end

return AudioPanel
