--!strict
-- AudioPanel.luau
-- StarterPlayerScripts/UI/AudioPanel.luau
--
-- Einzige Zustaendigkeit:
--   - Den Abschnitt "Ton und Geraet" fuer das Einstellungs-Fenster (Zahnrad,
--     LanguagePanel): Regler fuer Musik und Effekte, Stumm-Taste, Option
--     "Schwaches Geraet"
--
-- Was gilt und was gespeichert wird, entscheidet AudioController bzw.
-- LowEndSetting — dieser Abschnitt ruft nur deren set() auf und zeigt den
-- aktuellen Stand. (21.10.: der eigene Lautsprecher-Knopf mit eigenem Fenster
-- ist entfallen, alles liegt jetzt im Einstellungs-Fenster.)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService  = game:GetService("UserInputService")

local Loc = require(ReplicatedStorage.Localization.Loc)

local Theme           = require(script.Parent.Theme)
local AudioController = require(script.Parent.Parent.Controllers.AudioController)
local LowEndSetting   = require(script.Parent.Parent.Controllers.LowEndSetting)   -- 21.10.

local AudioPanel = {}

-- Loc.bind haelt Beschriftungen nur schwach. Ein Label, das sonst niemand
-- festhaelt, kann vom Muellsammler eingesammelt werden und folgt dann dem
-- Sprachwechsel nicht mehr — deshalb hier festhalten.
local _keep: { Instance } = {}

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

-- Baut den Abschnitt in `parent` (eine leere Spalte) und gibt eine Funktion
-- zurueck, die alle Anzeigen auf den aktuellen Stand bringt (beim Oeffnen).
function AudioPanel.buildSection(parent: Frame): () -> ()
	Theme.listLayout(parent, 10)

	local heading = Theme.label("Heading", parent, "")
	heading.AutoLocalize = false
	table.insert(_keep, heading)
	heading.Size = UDim2.new(1, -8, 0, 30)
	heading.LayoutOrder = 0
	Loc.bind(heading, "ui.audio.section")

	local refreshMusic = addSlider(parent, 1, "ui.audio.music",
		function() return AudioController.getSettings().music end,
		function(value) AudioController.set({ music = value }) end)
	local refreshSfx = addSlider(parent, 2, "ui.audio.sfx",
		function() return AudioController.getSettings().sfx end,
		function(value) AudioController.set({ sfx = value }) end)

	local mute = Theme.button("Mute", parent, "", Theme.COLORS.panelLight)
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

	-- 21.10. Option "Schwaches Geraet": weniger Partikel (Tutorial-Pfeile)
	local lowEnd = Theme.button("LowEnd", parent, "", Theme.COLORS.panelLight)
	lowEnd.Size = UDim2.new(1, -8, 0, 40)
	lowEnd.LayoutOrder = 4
	lowEnd.TextColor3 = Theme.COLORS.text
	table.insert(_keep, lowEnd)
	lowEnd.AutoLocalize = false
	lowEnd.Activated:Connect(function()
		LowEndSetting.set(not LowEndSetting.get())
		AudioController.play("click")
	end)
	local function refreshLowEnd()
		local on = LowEndSetting.get()
		lowEnd.Text = Loc.t(if on then "ui.lowend.on" else "ui.lowend.off")
		lowEnd.BackgroundColor3 = if on then Theme.COLORS.good else Theme.COLORS.panelLight
	end
	LowEndSetting.onChanged(refreshLowEnd)
	Loc.onChanged(refreshLowEnd)

	local function refreshAll()
		refreshMusic()
		refreshSfx()
		refreshLowEnd()
		mute.BackgroundColor3 = if AudioController.getSettings().muted then Theme.COLORS.bad else Theme.COLORS.panelLight
	end
	AudioController.onSettingsChanged(refreshAll)
	refreshAll()
	return refreshAll
end

-- Bleibt fuer Main.client: kein eigener Knopf und kein eigenes Fenster mehr.
function AudioPanel.init(screenGui: ScreenGui)
	print("[AudioPanel] Initialisiert | Abschnitt im Einstellungs-Fenster")
end

return AudioPanel
