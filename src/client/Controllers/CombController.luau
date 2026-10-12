--!strict
-- CombController.luau
-- StarterPlayerScripts/Controllers/CombController.luau
--
-- Einzige Zustaendigkeit:
--   - Alles, was der Spieler von den Honigwaben im Event-Pit und vom
--     Waben-Recycler SIEHT und ausloest:
--       1. Eine kleine Anzeige "Waben 12/25" (nur wenn er welche traegt)
--       2. Meldungen bei Abgabe und Recycler-Ausbau
--       3. Den Ausbau-Prompt am EIGENEN Recycler
--       4. Das Wippen und Drehen der im Pit liegenden Waben
--
-- Die Wahrheit liegt komplett auf dem Server (CombService, CombRecyclerService):
-- was getragen wird, kommt ueber Player-Attribute ("CombsCarried"/"CombsMax"),
-- Level und Warteschlange des Recyclers ueber PlayerDataUpdated. Dieser Controller
-- rechnet nichts und entscheidet nichts.
--
-- Der Prompt entsteht auf dem Client, nur am eigenen Plot — dasselbe Muster wie
-- die Gebaeude-Prompts im WorldController (der Server wendet die Anfrage ohnehin
-- immer auf die Daten des anfragenden Spielers an).

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombConfig = require(ReplicatedStorage.Config.CombConfig)
local MapConfig  = require(ReplicatedStorage.Config.MapConfig)
local Remotes    = require(ReplicatedStorage.Network.Remotes)
local Loc        = require(ReplicatedStorage.Localization.Loc)
local FeedbackConfig = require(ReplicatedStorage.Config.FeedbackConfig)

local Theme       = require(script.Parent.Parent.UI.Theme)
local Toast       = require(script.Parent.Parent.UI.Toast)
-- HBB Paket 1: Meldungen nach FeedbackConfig verteilen (Icon/Moment/Toast)
local Notify      = require(script.Parent.Parent.UI.Notify)
local Feedback    = require(script.Parent.Parent.UI.Feedback)
local ClientState = require(script.Parent.ClientState)

local CombController = {}

local localPlayer = Players.LocalPlayer

local WORLD_FOLDER_NAME = "EventPitCombs"
local OWNER_ATTRIBUTE   = "PlotOwner"
local PROMPT_NAME       = "UpgradeRecycler"
local PROMPT_DISTANCE   = 14
-- 08.10. (Paket G): ein Druck statt Halten; gegen Doppelkauf sperrt sich der
-- Prompt danach kurz (FeedbackConfig.UPGRADE_FX.PROMPT_LOCK).
local PROMPT_HOLD       = 0

-- Wippen und Drehen der Waben im Pit (rein optisch, nur auf diesem Client)
local BOB_HEIGHT = 0.32
local BOB_RATE   = 2.0    -- Schwingungen pro Sekunde (in Radiant: * 1)
local SPIN_RATE  = 0.9    -- Radiant pro Sekunde

--------------------------------------------------------------------------------
-- Anzeige "Waben x/y"
--------------------------------------------------------------------------------

local _pill: Frame? = nil
local _carryLabel: TextLabel? = nil
local _hintLabel: TextLabel? = nil

local function isInPit(): boolean
	local character = localPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then return false end

	local flat = Vector3.new(
		root.Position.X - MapConfig.CENTER.X,
		0,
		root.Position.Z - MapConfig.CENTER.Z
	)
	return flat.Magnitude <= MapConfig.EVENT_PIT_RADIUS
end

local function refreshCarry()
	local pill, carryLabel, hint = _pill, _carryLabel, _hintLabel
	if not pill or not carryLabel or not hint then return end

	local count = localPlayer:GetAttribute("CombsCarried")
	local max   = localPlayer:GetAttribute("CombsMax")
	if typeof(count) ~= "number" or typeof(max) ~= "number" or count <= 0 then
		pill.Visible = false
		return
	end

	pill.Visible = true
	carryLabel.Text = Loc.t("ui.comb.carry", { n = count, max = max })

	if count >= max then
		hint.Text = Loc.t("ui.comb.full")
		hint.TextColor3 = Theme.COLORS.goldGummy
	elseif isInPit() then
		hint.Text = Loc.t("ui.comb.slow")
		hint.TextColor3 = Theme.COLORS.textDim
	else
		hint.Text = ""
	end
end

local function buildPill(screenGui: ScreenGui)
	local pill = Theme.panel("CombPill", screenGui, Theme.COLORS.panel)
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position    = UDim2.new(0.5, 0, 0, 12)
	pill.Size        = UDim2.new(0, 250, 0, 54)
	pill.Visible     = false

	local carry = Theme.label("Carry", pill, "")
	carry.Position       = UDim2.new(0, 10, 0, 4)
	carry.Size           = UDim2.new(1, -20, 0, 26)
	carry.TextXAlignment = Enum.TextXAlignment.Center
	carry.TextColor3     = Theme.COLORS.goldGummy

	local hint = Theme.bodyText("Hint", pill, "")
	hint.Position       = UDim2.new(0, 10, 0, 30)
	hint.Size           = UDim2.new(1, -20, 0, 20)
	hint.TextXAlignment = Enum.TextXAlignment.Center

	_pill        = pill
	_carryLabel  = carry
	_hintLabel   = hint
end

--------------------------------------------------------------------------------
-- Recycler-Prompt (nur am eigenen Plot)
--------------------------------------------------------------------------------

local function findPlotOwner(instance: Instance): number?
	local current: Instance? = instance
	while current do
		local owner = current:GetAttribute(OWNER_ATTRIBUTE)
		if typeof(owner) == "number" then
			return owner
		end
		current = current.Parent
	end
	return nil
end

local function costText(level: number): string
	local cost = CombConfig.getUpgradeCost(level + 1)
	if not cost then
		return Loc.t("ui.recycler.maxed")
	end

	local text = if cost.goldGummies > 0
		then Loc.t("ui.recycler.cost_gg", { gummies = Theme.formatNumber(cost.gummies), gold = cost.goldGummies })
		else Loc.t("ui.recycler.cost_g", { gummies = Theme.formatNumber(cost.gummies) })

	return Loc.t("ui.recycler.upgrade", { cost = text })
end

local _locked: { [ProximityPrompt]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function writePrompt(prompt: ProximityPrompt)
	local data = ClientState.get()
	local level = if data then data.island.recycler.level else 1

	prompt.ObjectText = string.format("%s  Lv.%d", Loc.t("ui.recycler.name"), level)

	if level >= CombConfig.RECYCLER_MAX_LEVEL then
		prompt.ActionText = Loc.t("ui.recycler.maxed")
		prompt.Enabled    = false
	else
		-- Reicht es nicht, steht im Prompt, wie viel fehlt (ausgrauen kann der
		-- Standard-Prompt nicht); der Server lehnt einen Druck dann ab.
		local cost = CombConfig.getUpgradeCost(level + 1)
		local missing = if cost and data then cost.gummies - data.gummies else 0
		prompt.ActionText = if missing > 0
			then Loc.t("ui.upgrade.prompt_need", { missing = Theme.formatNumber(missing) })
			else costText(level)
		prompt.Enabled    = not _locked[prompt]
	end
end

local _prompts: { ProximityPrompt } = {}

local function attachPrompt(body: BasePart)
	if body:FindFirstChild(PROMPT_NAME) then return end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name                  = PROMPT_NAME
	prompt.KeyboardKeyCode       = Enum.KeyCode.E
	prompt.HoldDuration          = PROMPT_HOLD
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight   = false
	prompt.Parent                = body

	prompt.Triggered:Connect(function()
		if _locked[prompt] then return end
		_locked[prompt] = true
		prompt.Enabled = false
		Remotes.RequestUpgradeRecycler:FireServer()
		task.delay(FeedbackConfig.UPGRADE_FX.PROMPT_LOCK, function()
			_locked[prompt] = nil
			if prompt.Parent then writePrompt(prompt) end
		end)
	end)

	table.insert(_prompts, prompt)
	prompt.Destroying:Connect(function()
		local index = table.find(_prompts, prompt)
		if index then table.remove(_prompts, index) end
	end)

	writePrompt(prompt)
end

local function hookWorldPart(instance: Instance)
	if not instance:IsA("BasePart") then return end
	if instance.Name ~= CombConfig.RECYCLER_NAME then return end

	local function tryAttach()
		if findPlotOwner(instance) == localPlayer.UserId then
			attachPrompt(instance)
			return true
		end
		return false
	end

	if tryAttach() then return end

	-- Replikation ist nicht sortiert: das Plot-Model kann beim Client ankommen,
	-- bevor sein Besitzer-Attribut da ist. Einmal im naechsten Frame nachsehen.
	task.defer(function()
		if instance.Parent then
			tryAttach()
		end
	end)
end

--------------------------------------------------------------------------------
-- Waben im Pit: Wippen und Drehen
--------------------------------------------------------------------------------

-- `fly` = Einflug (Vulkan-Ausbruch, Waben-Regen): von `from` zur Ruhelage
-- zwischen den Serverzeiten `start` und `finish` (Attribute FlyFrom/FlyStart/FlyEnd).
type Fly = { from: Vector3, start: number, finish: number }
type Bob = { base: CFrame?, phase: number, spawnTime: number, fly: Fly? }

local _bobbing: { [Model]: Bob } = {}

-- Wie oft trackComb auf fehlende Attribute wartet (je ein Frame), bevor die
-- Wabe aufgegeben wird. Attribute kommen mit dem Model selbst an; das ist nur
-- ein Sicherheitsnetz.
local BASE_RETRY_FRAMES = 6

-- Auftauch-Effekt frisch gespawnter Waben: steigt aus dem Boden und federt nach.
local POP_SECONDS = 0.45
local POP_DEPTH   = 1.6

-- Baut die Ruhelage aus den Attributen "Pos"/"Yaw" (CombBuilder.buildWorldComb).
-- NIE aus GetPivot(): siehe Kopf von buildWorldComb.
local function readBase(model: Model): CFrame?
	local pos = model:GetAttribute("Pos")
	local yaw = model:GetAttribute("Yaw")
	if typeof(pos) ~= "Vector3" or typeof(yaw) ~= "number" then
		return nil
	end
	return CFrame.new(pos) * CFrame.Angles(0, yaw, 0)
end

local function trackComb(child: Instance)
	if not child:IsA("Model") then return end
	local model = child :: Model

	local phase = model:GetAttribute("Phase")
	local spawnTime = model:GetAttribute("SpawnTime")
	local flyFrom   = model:GetAttribute("FlyFrom")
	local flyStart  = model:GetAttribute("FlyStart")
	local flyEnd    = model:GetAttribute("FlyEnd")
	local fly: Fly? = nil
	if typeof(flyFrom) == "Vector3" and typeof(flyStart) == "number" and typeof(flyEnd) == "number" then
		fly = { from = flyFrom, start = flyStart, finish = flyEnd }
	end
	local bob: Bob = {
		base      = readBase(model),
		phase     = if typeof(phase) == "number" then phase else 0,
		-- Fliegende Waben tauchen nicht zusaetzlich aus dem Boden auf.
		spawnTime = if fly then 0 elseif typeof(spawnTime) == "number" then spawnTime else 0,
		fly       = fly,
	}
	_bobbing[model] = bob

	if bob.base then return end

	-- Sicherheitsnetz: Attribute fehlen noch. Ein paar Frames nachsehen, bis
	-- dahin ueberspringt animateCombs diese Wabe (kein PivotTo mit Identitaet).
	task.spawn(function()
		for _ = 1, BASE_RETRY_FRAMES do
			task.wait()
			if _bobbing[model] ~= bob then return end
			local base = readBase(model)
			if base then
				bob.base = base
				return
			end
		end
	end)
end

local function hookWorldFolder(folder: Instance)
	for _, child in folder:GetChildren() do
		trackComb(child)
	end
	folder.ChildAdded:Connect(trackComb)
	folder.ChildRemoved:Connect(function(child)
		if child:IsA("Model") then
			_bobbing[child] = nil
		end
	end)
end

-- Versatz nach unten waehrend des Auftauchens (0 = fertig). Ueberschwingt kurz.
local function popOffset(now: number, spawnTime: number): number
	local age = now - spawnTime
	if spawnTime <= 0 or age >= POP_SECONDS or age < 0 then return 0 end
	local k = age / POP_SECONDS
	-- 1 → 0 mit kleinem Ueberschwinger (Back-Ease-Out)
	local c = 1.7
	local eased = 1 + (c + 1) * (k - 1) ^ 3 + c * (k - 1) ^ 2
	return -POP_DEPTH * (1 - eased)
end

-- Einflug: Bogen von `from` zur Ruhelage, Hoehe CombConfig.FLIGHT_ARC_HEIGHT.
-- nil = Flug ist vorbei (oder hat noch nicht begonnen und die Wabe wartet oben).
local function flyPosition(fly: Fly, landing: Vector3, now: number): Vector3?
	if now >= fly.finish then return nil end
	local span = math.max(0.05, fly.finish - fly.start)
	local k = math.clamp((now - fly.start) / span, 0, 1)
	local arc = 4 * k * (1 - k) * CombConfig.FLIGHT_ARC_HEIGHT
	return fly.from:Lerp(landing, k) + Vector3.new(0, arc, 0)
end

local function animateCombs()
	local t = os.clock()
	local serverNow = Workspace:GetServerTimeNow()
	for model, bob in _bobbing do
		local base = bob.base
		local fly = bob.fly
		if base and fly and model.Parent then
			local pos = flyPosition(fly, base.Position, serverNow)
			if pos then
				model:PivotTo(CFrame.new(pos) * CFrame.Angles(t * 6, t * SPIN_RATE * 3, 0))
				continue
			end
			bob.fly = nil
		end
		if base and model.Parent then
			local lift = math.sin(t * BOB_RATE + bob.phase) * BOB_HEIGHT + popOffset(serverNow, bob.spawnTime)
			model:PivotTo(base * CFrame.new(0, lift, 0) * CFrame.Angles(0, t * SPIN_RATE + bob.phase, 0))
		end
	end
end

--------------------------------------------------------------------------------
-- Initialisierung
--------------------------------------------------------------------------------

function CombController.init(screenGui: ScreenGui)
	buildPill(screenGui)

	for _, name in { "CombsCarried", "CombsMax" } do
		localPlayer:GetAttributeChangedSignal(name):Connect(refreshCarry)
	end
	refreshCarry()

	-- "Im Pit" aendert sich ohne Attribut-Aenderung, deshalb ein gemuetlicher
	-- Takt fuer den Hinweistext.
	task.spawn(function()
		while true do
			task.wait(0.4)
			refreshCarry()
		end
	end)

	Remotes.CombDelivered.OnClientEvent:Connect(function(count: any, _units: any)
		if typeof(count) ~= "number" then return end
		Notify.emit("comb_delivered", function()
			Toast.success(Loc.tn("msg.comb_delivered", count))
		end, function()
			Feedback.gain("comb", count)
		end)
	end)

	Remotes.RecyclerUpgraded.OnClientEvent:Connect(function(level: any)
		if typeof(level) ~= "number" then return end
		Notify.emit("recycler_upgraded", function()
			Toast.success(Loc.t("msg.recycler_upgraded", { level = level }))
		end, function()
			-- Paket G: den Moment zeigt UI/UpgradeFX am Recycler selbst
			-- (aus dem Datenstand) — hier kein zweites "⬆" ueber dem Spieler.
		end)
	end)

	-- Prompt-Text nachziehen, wenn sich Level/Gummies aendern oder die Sprache
	ClientState.onChanged(function()
		for _, prompt in _prompts do
			writePrompt(prompt)
		end
	end)
	Loc.onChanged(function()
		for _, prompt in _prompts do
			writePrompt(prompt)
		end
		refreshCarry()
	end)

	for _, descendant in Workspace:GetDescendants() do
		hookWorldPart(descendant)
	end
	Workspace.DescendantAdded:Connect(hookWorldPart)

	local existing = Workspace:FindFirstChild(WORLD_FOLDER_NAME)
	if existing then
		hookWorldFolder(existing)
	end
	Workspace.ChildAdded:Connect(function(child)
		if child.Name == WORLD_FOLDER_NAME then
			hookWorldFolder(child)
		end
	end)

	RunService.RenderStepped:Connect(animateCombs)

	print("[CombController] Initialisiert")
end

return CombController
