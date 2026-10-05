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
local ClientState  = require(script.Parent.ClientState)
local EggConfig     = require(ReplicatedStorage.Config.EggConfig)
local BaerchiConfig = require(ReplicatedStorage.Config.BaerchiConfig)
local EggCalculator = require(ReplicatedStorage.Modules.EggCalculator)

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

--------------------------------------------------------------------------------
-- INCUBATOR_BREED: Schild ueber einem Platz mit Baerchi
--------------------------------------------------------------------------------
-- Wunsch Projektinhaber 05.10.: "Der Baerchi zeigt im Inkubator an, mit
-- welcher Wahrscheinlichkeit welches Ei gebruetet wird." Name, die Chancen
-- (nach EggTree.resolveLaid zusammengefasst — gesperrte Eier rutschen auf den
-- freien Vorgaenger, genau wie beim Server) und die Zeit bis zum naechsten Ei.

local BREED_MAX_LINES = 4

type BreedView = { dome: BasePart, gui: BillboardGui, title: TextLabel, odds: TextLabel, timer: TextLabel, key: string }
local _breedViews: { [BasePart]: BreedView } = {}

local function breedLabel(parent: Instance, name: string, y: number, h: number, color: Color3): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = UDim2.fromScale(0, y)
	label.Size = UDim2.fromScale(1, h)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.Text = ""
	label.Parent = parent
	return label
end

local function attachBreedView(dome: BasePart)
	if _breedViews[dome] then return end
	local gui = Instance.new("BillboardGui")
	gui.Name        = "BreederInfo"
	gui.Size        = UDim2.fromScale(7, 5)
	gui.StudsOffset = Vector3.new(0, dome.Size.Y * 0.5 + 3.2, 0)
	gui.MaxDistance = IncubatorConfig.LOOK.signDistance
	gui.AlwaysOnTop = false
	gui.Adornee     = dome
	gui.Enabled     = false
	gui.Parent      = dome

	local title = breedLabel(gui, "Title", 0, 0.24, Color3.new(1, 1, 1))
	local odds = breedLabel(gui, "Odds", 0.25, 0.55, Color3.fromRGB(255, 240, 200))
	odds.TextYAlignment = Enum.TextYAlignment.Top
	local timer = breedLabel(gui, "Timer", 0.82, 0.18, BAR_COLOR)
	_breedViews[dome] = { dome = dome, gui = gui, title = title, odds = odds, timer = timer, key = "" }
end

local function eggName(eggType: string): string
	local def = EggConfig.data[eggType :: any]
	return Loc.name("egg." .. eggType .. ".name", if def then def.displayName else eggType)
end

-- Chancen dieses Baerchis, nach dem tatsaechlich gebrueteten Ei zusammengefasst.
local function oddsText(baerchi: any, eggTree: any): string
	local list = EggCalculator.getResolvedChances(baerchi, eggTree)
	local lines: { string } = {}
	for i, entry in list do
		if i > BREED_MAX_LINES then break end
		local percent = if entry.percent >= 10 then string.format("%d", math.floor(entry.percent + 0.5))
			else Loc.formatDecimal(entry.percent, 1)
		table.insert(lines, string.format("%s  %s%%", eggName(entry.eggType), percent))
	end
	return table.concat(lines, "\n")
end

local function updateBreed(view: BreedView, now: number)
	local dome = view.dome
	local uid = dome:GetAttribute("BreederUid")
	local data = ClientState.get()
	local baerchi = if typeof(uid) == "string" and uid ~= "" and data then data.island.baerchis[uid] else nil
	if not baerchi or not data then
		view.gui.Enabled = false
		view.key = ""
		return
	end
	view.gui.Enabled = true

	-- Name und Chancen nur neu schreiben, wenn sich etwas daran aendert
	local unlockedCount = 0
	if data.eggTree then
		for _ in data.eggTree.unlocked do unlockedCount += 1 end
	end
	local key = table.concat({ uid :: string, baerchi.configId, tostring(baerchi.mutation), Loc.getLanguage(),
		tostring(unlockedCount) }, "|")
	if key ~= view.key then
		view.key = key
		local def = BaerchiConfig.getById(baerchi.configId)
		local name = Loc.name("baerchi." .. baerchi.configId .. ".name", if def then def.displayName else baerchi.configId)
		view.title.Text = string.format("%s · %s", name, Loc.name("rarity." .. baerchi.rarity, baerchi.rarity))
		view.title.TextColor3 = BaerchiConfig.getRarityColor(baerchi.rarity)
		view.odds.Text = oddsText(baerchi, data.eggTree)
	end

	local unlocked = dome:GetAttribute("Unlocked")
	if unlocked == false then
		view.timer.Text = "🔒"
		return
	end
	local lying = 0
	for _, egg in data.island.laidEggs do
		if (egg :: any).fromIncubator then lying += 1 end
	end
	if lying >= IncubatorConfig.BREED_MAX_LYING then
		view.timer.Text = "🥚 " .. Loc.t("ui.incubator.breed_full")
		view.timer.TextColor3 = READY_COLOR
		return
	end
	local last = dome:GetAttribute("LastEggAt")
	local seconds = dome:GetAttribute("BreedSeconds")
	if typeof(last) == "number" and typeof(seconds) == "number" and seconds > 0 then
		local left = math.max(0, last + seconds - now)
		view.timer.Text = "🥚 " .. Loc.formatDuration(math.ceil(left))
		view.timer.TextColor3 = BAR_COLOR
	end
end

-- INCUBATOR_BREED: "Baerchi einsetzen" statt "Oeffnen"
local function actionKey(): string
	return if FeatureFlags.isOn("INCUBATOR_BREED") then "ui.incubator.prompt_breed" else "ui.incubator.prompt_action"
end

local function attachPrompt(base: BasePart)
	if base:FindFirstChild("IncubatorPrompt") then return end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "IncubatorPrompt"
	prompt.ActionText = Loc.t(actionKey())
	prompt.ObjectText = Loc.t("ui.incubator.title")
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = base
	prompt.Triggered:Connect(function()
		PanelManager.open("Incubator")
	end)
	Loc.onChanged(function()
		prompt.ActionText = Loc.t(actionKey())
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
		if FeatureFlags.isOn("INCUBATOR_BREED") then
			attachBreedView(instance)
		end
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
			for dome, view in _breedViews do
				if dome.Parent == nil then
					_breedViews[dome] = nil
				else
					local ok, err = pcall(updateBreed, view, now)
					if not ok then warn("[IncubatorController] Brut-Schild:", err) end
				end
			end
		end
	end)
end

return IncubatorController
