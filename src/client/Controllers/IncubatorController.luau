--!strict
-- IncubatorController.luau
-- StarterPlayerScripts/Controllers/IncubatorController.luau
--
-- Einzige Zustaendigkeit:
--   - Den Inkubator auf dem EIGENEN Plot lebendig machen (Sammel-Update
--     05.10., Paket 8): Prompt "Inkubator" am Sockel, ueber jeder belegten
--     Kuppel ein Fortschrittsbalken mit Restzeit, Leuchten kurz vor dem
--     Schluepfen und solange das Ei fertig ist.
--
-- Rein clientseitig aus den Attributen der Kuppeln (StartedAt/FinishAt, siehe
-- IncubatorBuilder) — dasselbe Zeitmarken-Prinzip wie EggTimerController:
-- kein Server-Takt pro Ei, kein zusaetzliches Remote. "Jetzt" ist
-- workspace:GetServerTimeNow() (die Marken sind os.time() des Servers).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local Loc             = require(ReplicatedStorage.Localization.Loc)
local FeatureFlags    = require(ReplicatedStorage.Config.FeatureFlags)
local IncubatorConfig = require(ReplicatedStorage.Config.IncubatorConfig)

local PanelManager = require(script.Parent.Parent.UI.PanelManager)

local IncubatorController = {}

local OWNER_ATTRIBUTE = "PlotOwner"
local TICK_SECONDS    = 0.5
local BAR_COLOR       = Color3.fromRGB(120, 230, 140)
local READY_COLOR     = Color3.fromRGB(255, 220, 90)

type DomeView = { dome: BasePart, gui: BillboardGui, fill: Frame, text: TextLabel, light: PointLight }
local _views: { [BasePart]: DomeView } = {}

local function isOwnPlot(instance: Instance): boolean
	local current: Instance? = instance
	while current do
		local owner = current:GetAttribute(OWNER_ATTRIBUTE)
		if typeof(owner) == "number" then
			return owner == Players.LocalPlayer.UserId
		end
		current = current.Parent
	end
	return false
end

local function attachView(dome: BasePart)
	if _views[dome] then return end

	local gui = Instance.new("BillboardGui")
	gui.Name        = "IncubatorProgress"
	gui.Size        = UDim2.fromScale(4.4, 1.2)
	gui.StudsOffset = Vector3.new(0, dome.Size.Y * 0.5 + 1.0, 0)
	gui.MaxDistance = IncubatorConfig.LOOK.signDistance
	gui.AlwaysOnTop = false
	gui.Adornee     = dome
	gui.Enabled     = false
	gui.Parent      = dome

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.fromScale(1, 0.38)
	track.Position = UDim2.fromScale(0, 0.62)
	track.BackgroundColor3 = Color3.fromRGB(30, 26, 46)
	track.BorderSizePixel = 0
	track.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = BAR_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = track
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fill

	local text = Instance.new("TextLabel")
	text.Name = "Time"
	text.Size = UDim2.fromScale(1, 0.6)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.2
	text.Text = ""
	text.Parent = gui

	local light = Instance.new("PointLight")
	light.Name = "ReadyGlow"
	light.Color = READY_COLOR
	light.Range = 9
	light.Brightness = 0
	light.Parent = dome

	_views[dome] = { dome = dome, gui = gui, fill = fill, text = text, light = light }
end

local function update(view: DomeView, now: number)
	local dome = view.dome
	local eggType = dome:GetAttribute("EggType")
	local startedAt = dome:GetAttribute("StartedAt")
	local finishAt = dome:GetAttribute("FinishAt")
	if typeof(eggType) ~= "string" or eggType == "" or typeof(startedAt) ~= "number" or typeof(finishAt) ~= "number" then
		view.gui.Enabled = false
		view.light.Brightness = 0
		return
	end

	view.gui.Enabled = true
	local total = math.max(1, finishAt - startedAt)
	local left = math.max(0, finishAt - now)
	local share = math.clamp(1 - left / total, 0, 1)
	view.fill.Size = UDim2.fromScale(share, 1)
	if left <= 0 then
		view.text.Text = "✔ " .. Loc.t("ui.incubator.ready")
		view.fill.BackgroundColor3 = READY_COLOR
		-- Fertig: pulsierendes Leuchten, damit man es vom anderen Ende des Plots sieht
		view.light.Brightness = 1.5 + math.sin(os.clock() * 4) * 0.8
	else
		view.text.Text = Loc.formatDuration(math.ceil(left))
		view.fill.BackgroundColor3 = BAR_COLOR
		view.light.Brightness = if left <= IncubatorConfig.GLOW_LAST_SECONDS then 1 else 0
	end
end

local function attachPrompt(base: BasePart)
	if base:FindFirstChild("IncubatorPrompt") then return end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "IncubatorPrompt"
	prompt.ActionText = Loc.t("ui.incubator.prompt_action")
	prompt.ObjectText = Loc.t("ui.incubator.title")
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = base
	prompt.Triggered:Connect(function()
		PanelManager.open("Incubator")
	end)
	Loc.onChanged(function()
		prompt.ActionText = Loc.t("ui.incubator.prompt_action")
		prompt.ObjectText = Loc.t("ui.incubator.title")
	end)
end

local function hook(instance: Instance)
	if not instance:IsA("BasePart") then return end
	local model = instance.Parent
	if not model or model.Name ~= IncubatorConfig.MODEL_NAME then return end
	if not isOwnPlot(model) then return end
	if instance.Name == "Base" then
		attachPrompt(instance)
	elseif string.match(instance.Name, "^Dome_%d+$") then
		attachView(instance)
	end
end

function IncubatorController.init()
	if not FeatureFlags.isOn("INCUBATOR") then return end

	for _, descendant in Workspace:GetDescendants() do
		hook(descendant)
	end
	Workspace.DescendantAdded:Connect(function(instance)
		-- Die Attribute (PlotOwner) haengen am Plot; die Teile kommen dazu.
		task.defer(hook, instance)
	end)

	task.spawn(function()
		while true do
			task.wait(TICK_SECONDS)
			local now = Workspace:GetServerTimeNow()
			for dome, view in _views do
				if dome.Parent == nil then
					_views[dome] = nil
				else
					update(view, now)
				end
			end
		end
	end)
end

return IncubatorController
