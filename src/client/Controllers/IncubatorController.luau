--!strict
-- IncubatorController.luau
-- StarterPlayerScripts/Controllers/IncubatorController.luau
--
-- Einzige Zustaendigkeit:
--   - Den Inkubator auf dem EIGENEN Plot lebendig machen (Sammel-Update
--     05.10., Paket 8, Umbau nach Rueckmeldung 05.10.):
--       * zwei Prompts am Sockel: "Eier abholen" (nur wenn Eier warten) und
--         "Baerchi einsetzen" (oeffnet das Inkubator-Fenster) — Bedienung
--         durch Hingehen, kein Seitenknopf;
--       * ueber jeder belegten Kuppel: welche Eier der Baerchi mit welcher
--         Wahrscheinlichkeit bruetet, wie viele warten und ein Balken bis
--         zum naechsten Ei; Leuchten, solange Eier warten.
--
-- Rein clientseitig aus den Attributen der Kuppeln (BaerchiUid, LastEggAt,
-- Interval, Eggs — siehe IncubatorBuilder) und dem eigenen Spielstand
-- (ClientState, fuer die Ei-Tabelle des Baerchis). "Jetzt" ist
-- workspace:GetServerTimeNow() (die Marken sind os.time() des Servers).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local Remotes         = require(ReplicatedStorage.Network.Remotes)
local Loc             = require(ReplicatedStorage.Localization.Loc)
local FeatureFlags    = require(ReplicatedStorage.Config.FeatureFlags)
local IncubatorConfig = require(ReplicatedStorage.Config.IncubatorConfig)
local IncubatorRules  = require(ReplicatedStorage.Modules.IncubatorRules)

local PanelManager   = require(script.Parent.Parent.UI.PanelManager)
local IncubatorPanel = require(script.Parent.Parent.UI.IncubatorPanel)
local ClientState    = require(script.Parent.ClientState)

local IncubatorController = {}

local OWNER_ATTRIBUTE = "PlotOwner"
local TICK_SECONDS    = 0.5
local BAR_COLOR       = Color3.fromRGB(120, 230, 140)
local READY_COLOR     = Color3.fromRGB(255, 220, 90)

type DomeView = {
	dome: BasePart, gui: BillboardGui, chances: TextLabel, fill: Frame,
	text: TextLabel, light: PointLight, uid: string,
}
local _views: { [BasePart]: DomeView } = {}
local _collectPrompt: ProximityPrompt? = nil

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
	gui.Name        = "IncubatorInfo"
	gui.Size        = UDim2.fromScale(7, 3)
	gui.StudsOffset = Vector3.new(0, dome.Size.Y * 0.5 + 1.8, 0)
	gui.MaxDistance = IncubatorConfig.LOOK.signDistance
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Adornee     = dome
	gui.Enabled     = false
	gui.Parent      = dome

	-- Oben: was gebruetet wird ("Basis-Ei 70 % · Zucker-Ei 25 %")
	local chances = Instance.new("TextLabel")
	chances.Name = "Chances"
	chances.Size = UDim2.fromScale(1, 0.55)
	chances.BackgroundTransparency = 1
	chances.Font = Enum.Font.FredokaOne
	chances.TextScaled = true
	chances.TextWrapped = true
	chances.TextColor3 = Color3.fromRGB(255, 236, 170)
	chances.TextStrokeTransparency = 0.2
	chances.Text = ""
	chances.Parent = gui

	-- Unten: Balken bis zum naechsten Ei, darin "🥚 2/5 · 3:12"
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
	text.Name = "Status"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.2
	text.Text = ""
	text.ZIndex = 2
	text.Parent = track

	local light = Instance.new("PointLight")
	light.Name = "ReadyGlow"
	light.Color = READY_COLOR
	light.Range = 9
	light.Brightness = 0
	light.Parent = dome

	_views[dome] = { dome = dome, gui = gui, chances = chances, fill = fill, text = text, light = light, uid = "" }
end

local function update(view: DomeView, now: number)
	local dome = view.dome
	local uid = dome:GetAttribute("BaerchiUid")
	local lastEggAt = dome:GetAttribute("LastEggAt")
	local interval = dome:GetAttribute("Interval")
	local eggs = dome:GetAttribute("Eggs")
	local data = ClientState.get()
	local baerchi = if data and typeof(uid) == "string" then data.island.baerchis[uid] else nil
	if not baerchi or typeof(lastEggAt) ~= "number" or typeof(interval) ~= "number" or interval <= 0 then
		view.gui.Enabled = false
		view.light.Brightness = 0
		view.uid = ""
		return
	end

	view.gui.Enabled = true
	-- Chancen nur bei Wechsel des Baerchis neu schreiben (Text ist teuer genug)
	local key = (uid :: string) .. "|" .. Loc.getLanguage()
	if view.uid ~= key then
		view.uid = key
		view.chances.Text = IncubatorPanel.chanceText(baerchi, data and data.eggTree)
	end

	local waiting = if typeof(eggs) == "number" then eggs else 0
	local full = waiting >= IncubatorConfig.STORE_PER_SLOT
	local left = math.max(0, math.ceil(lastEggAt + interval - now))
	local share = if full then 1 else math.clamp((now - lastEggAt) / interval, 0, 1)
	view.fill.Size = UDim2.fromScale(share, 1)
	view.fill.BackgroundColor3 = if full then READY_COLOR else BAR_COLOR
	view.text.Text = string.format("🥚 %d/%d  ·  %s", waiting, IncubatorConfig.STORE_PER_SLOT,
		if full then Loc.t("ui.incubator.full_short") else Loc.formatDuration(left))
	-- Eier warten: pulsierendes Leuchten, damit man es vom anderen Ende des Plots sieht
	view.light.Brightness = if waiting > 0 then 1.2 + math.sin(os.clock() * 4) * 0.6 else 0
end

local function promptTexts()
	local data = ClientState.get()
	local stored = if data and data.island.incubator then IncubatorRules.storedCount(data.island.incubator.slots) else 0
	local collect = _collectPrompt
	if collect then
		collect.Enabled = stored > 0
		collect.ActionText = Loc.t("ui.incubator.prompt_collect", { n = stored })
		collect.ObjectText = Loc.t("ui.incubator.title")
	end
end

local function attachPrompts(base: BasePart)
	if base:FindFirstChild("IncubatorPrompt") then return end

	-- "Baerchi einsetzen": oeffnet das Fenster (Auswahl, Herausnehmen, Ausbau)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "IncubatorPrompt"
	prompt.ActionText = Loc.t("ui.incubator.prompt_action")
	prompt.ObjectText = Loc.t("ui.incubator.title")
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.UIOffset = Vector2.new(0, 70)
	prompt.Parent = base
	prompt.Triggered:Connect(function()
		PanelManager.open("Incubator")
	end)

	-- "Eier abholen": direkt, ohne Fenster (nur sichtbar, wenn Eier warten)
	local collect = Instance.new("ProximityPrompt")
	collect.Name = "IncubatorCollectPrompt"
	collect.KeyboardKeyCode = Enum.KeyCode.E
	collect.MaxActivationDistance = 14
	collect.RequiresLineOfSight = false
	collect.Enabled = false
	collect.Parent = base
	collect.Triggered:Connect(function()
		Remotes.RequestIncubatorCollect:FireServer()
	end)
	_collectPrompt = collect

	Loc.onChanged(function()
		prompt.ActionText = Loc.t("ui.incubator.prompt_action")
		prompt.ObjectText = Loc.t("ui.incubator.title")
		promptTexts()
	end)
	promptTexts()
end

local function hook(instance: Instance)
	if not instance:IsA("BasePart") then return end
	local model = instance.Parent
	if not model or model.Name ~= IncubatorConfig.MODEL_NAME then return end
	if not isOwnPlot(model) then return end
	if instance.Name == "Base" then
		attachPrompts(instance)
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

	ClientState.onChanged(function()
		promptTexts()
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
