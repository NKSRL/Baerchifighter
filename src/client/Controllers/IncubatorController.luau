--!strict
-- IncubatorController.luau
-- StarterPlayerScripts/Controllers/IncubatorController.luau
--
-- Einzige Zustaendigkeit:
--   - Den Solo-Inkubator auf dem EIGENEN Plot lebendig machen (15.10.2026):
--     Prompt am Stumpf (oeffnet das Fenster) und ein Schild ueber der Kuppel
--     mit Name und Chancen des Baerchis, Zeit bis zum naechsten Ei und dem
--     Fuellstand des Lagers ("5 / 12").
--
-- Rein clientseitig aus den Attributen der Kuppel (BreederUid, LastEggAt,
-- BreedSeconds, Stored, Capacity, siehe IncubatorBuilder) — Zeitmarken-
-- Prinzip wie EggTimerController: kein Server-Takt, kein Remote. "Jetzt" ist
-- workspace:GetServerTimeNow() (die Marken sind os.time() des Servers).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local Loc             = require(ReplicatedStorage.Localization.Loc)
local Names           = require(ReplicatedStorage.Localization.Names)
local FeatureFlags    = require(ReplicatedStorage.Config.FeatureFlags)
local IncubatorConfig = require(ReplicatedStorage.Config.IncubatorConfig)
local BaerchiConfig   = require(ReplicatedStorage.Config.BaerchiConfig)
local EggCalculator   = require(ReplicatedStorage.Modules.EggCalculator)

local PanelManager = require(script.Parent.Parent.UI.PanelManager)
local ClientState  = require(script.Parent.ClientState)

local IncubatorController = {}

local OWNER_ATTRIBUTE = "PlotOwner"
local TICK_SECONDS    = 0.5
local OK_COLOR        = Color3.fromRGB(120, 230, 140)
local FULL_COLOR      = Color3.fromRGB(255, 220, 90)
local MAX_ODDS_LINES  = 3

type DomeView = {
	dome: BasePart, gui: BillboardGui,
	title: TextLabel, odds: TextLabel, timer: TextLabel, stored: TextLabel,
	key: string,
}
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

local function label(parent: Instance, name: string, y: number, h: number, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Position = UDim2.fromScale(0, y)
	l.Size = UDim2.fromScale(1, h)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.TextScaled = true
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.2
	l.Text = ""
	l.Parent = parent
	return l
end

local function attachView(dome: BasePart)
	if _views[dome] then return end
	local gui = Instance.new("BillboardGui")
	gui.Name        = "IncubatorInfo"
	gui.Size        = UDim2.fromScale(8, 5.6)
	gui.StudsOffset = Vector3.new(0, dome.Size.Y * 0.5 + 4.2, 0)   -- ueber den Ohren
	gui.MaxDistance = IncubatorConfig.LOOK.signDistance
	gui.AlwaysOnTop = true
	gui.Adornee     = dome
	gui.Parent      = dome

	local title  = label(gui, "Title", 0, 0.2, Color3.new(1, 1, 1))
	local odds   = label(gui, "Odds", 0.2, 0.42, Color3.fromRGB(255, 240, 200))
	odds.TextYAlignment = Enum.TextYAlignment.Top
	local timer  = label(gui, "Timer", 0.63, 0.17, OK_COLOR)
	local stored = label(gui, "Stored", 0.82, 0.18, Color3.new(1, 1, 1))
	_views[dome] = { dome = dome, gui = gui, title = title, odds = odds, timer = timer, stored = stored, key = "" }
end

-- Chancen dieses Baerchis, nach dem tatsaechlich gebrueteten Ei zusammengefasst
-- (gesperrte Eier rutschen auf den freien Vorgaenger, wie auf dem Server).
local function oddsText(baerchi: any, eggTree: any): string
	local lines: { string } = {}
	for i, entry in EggCalculator.getResolvedChances(baerchi, eggTree) do
		if i > MAX_ODDS_LINES then break end
		local percent = if entry.percent >= 10 then string.format("%d", math.floor(entry.percent + 0.5))
			else Loc.formatDecimal(entry.percent, 1)
		table.insert(lines, string.format("%s  %s%%", Names.egg(entry.eggType), percent))
	end
	return table.concat(lines, "\n")
end

local function update(view: DomeView, now: number)
	local dome = view.dome
	local stored = dome:GetAttribute("Stored")
	local capacity = dome:GetAttribute("Capacity")
	local uid = dome:GetAttribute("BreederUid")
	local data = ClientState.get()
	local baerchi = if typeof(uid) == "string" and uid ~= "" and data then data.island.baerchis[uid] else nil

	-- Lager immer zeigen
	if typeof(stored) == "number" and typeof(capacity) == "number" then
		local full = stored >= capacity
		view.stored.Text = "🥚 " .. string.format("%d / %d", stored, capacity)
		view.stored.TextColor3 = if full then FULL_COLOR else Color3.new(1, 1, 1)
	end

	if not baerchi or not data then
		view.title.Text = Loc.t("ui.incubator.prompt_breed")
		view.title.TextColor3 = Color3.new(1, 1, 1)
		view.odds.Text = ""
		view.timer.Text = ""
		view.key = ""
		return
	end

	-- Name und Chancen nur neu schreiben, wenn sich etwas daran aendert
	local unlockedCount = 0
	if data.eggTree then
		for _ in data.eggTree.unlocked do unlockedCount += 1 end
	end
	local key = table.concat({ uid :: string, baerchi.configId, tostring(baerchi.mutation), Loc.getLanguage(),
		tostring(unlockedCount) }, "|")
	if key ~= view.key then
		view.key = key
		view.title.Text = string.format("%s · %s", Names.baerchi(baerchi.configId),
			Loc.name("rarity." .. baerchi.rarity, baerchi.rarity))
		view.title.TextColor3 = BaerchiConfig.getRarityColor(baerchi.rarity)
		view.odds.Text = oddsText(baerchi, data.eggTree)
	end

	if typeof(stored) == "number" and typeof(capacity) == "number" and stored >= capacity then
		view.timer.Text = Loc.t("ui.incubator.breed_full")
		view.timer.TextColor3 = FULL_COLOR
		return
	end
	local last = dome:GetAttribute("LastEggAt")
	local seconds = dome:GetAttribute("BreedSeconds")
	if typeof(last) == "number" and typeof(seconds) == "number" and seconds > 0 then
		local left = math.max(0, last + seconds - now)
		view.timer.Text = "⏱ " .. Loc.formatDuration(math.ceil(left))
		view.timer.TextColor3 = OK_COLOR
	end
end

local function attachPrompt(base: BasePart)
	if base:FindFirstChild("IncubatorPrompt") then return end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "IncubatorPrompt"
	prompt.ActionText = Loc.t("ui.incubator.prompt_action")
	prompt.ObjectText = Loc.t("ui.incubator.title")
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 16
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
	elseif instance.Name == "Dome_1" then
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
					local ok, err = pcall(update, view, now)
					if not ok then warn("[IncubatorController] Schild:", err) end
				end
			end
		end
	end)
end

return IncubatorController
