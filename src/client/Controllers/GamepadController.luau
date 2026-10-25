--!strict
-- GamepadController.luau
-- StarterPlayerScripts/Controllers/GamepadController.luau
--
-- Einzige Zustaendigkeit:
--   - Controller-Steuerung (Welt 1, Paket 6d, Schalter CONSOLE_V1): Tasten
--     binden, Fokus setzen, Fenster per B schliessen, Pet-Leiste per
--     Schultertasten, Prompt-Taste X, Tastensymbole und Legende zeigen.
--
-- Aktiv NUR, solange DeviceProfile "console" meldet (Gamepad zuletzt benutzt).
-- Wechselt der Spieler zu Maus/Touch, werden alle Bindungen entfernt
-- (BindAction/UnbindAction immer paarweise) und die Oberflaeche ist wie vorher.
-- Die Belegung steht als Tabelle in Config/GamepadConfig.
--
-- Bewusst nicht gebunden: Start (bleibt Roblox-Pausenmenue), A (Roblox-Auswahl).
-- Hat eine Taste im aktuellen Zustand nichts zu tun, geht sie unveraendert
-- weiter (ContextActionResult.Pass) — so bleiben ProximityPrompts (X) und die
-- Standard-Steuerung heil.

local Players                = game:GetService("Players")
local ContextActionService   = game:GetService("ContextActionService")
local GuiService             = game:GetService("GuiService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage      = game:GetService("ReplicatedStorage")

local FeatureFlags  = require(ReplicatedStorage.Config.FeatureFlags)
local GamepadConfig = require(ReplicatedStorage.Config.GamepadConfig)
local Loc           = require(ReplicatedStorage.Localization.Loc)

local UI            = script.Parent.Parent.UI
local DeviceProfile = require(UI.DeviceProfile)
local GamepadNav    = require(UI.GamepadNav)
local PanelManager  = require(UI.PanelManager)
local PetBar        = require(UI.PetBar)

local GamepadController = {}

local _screenGui: ScreenGui? = nil
local _active = false
local _boundActions: { string } = {}
local _legend: Frame? = nil
local _returnFocus: GuiObject? = nil
local _promptConn: RBXScriptConnection? = nil
local _shownConn: RBXScriptConnection? = nil
local _managerHooked = false

--------------------------------------------------------------------------------
-- Aktionen
--------------------------------------------------------------------------------

local function topWindow(): GuiObject?
	return if _screenGui then GamepadNav.topWindow(_screenGui) else nil
end

local function focusMenu()
	local gui = _screenGui
	if not gui then return end
	local menu = gui:FindFirstChild("MenuBar")
	if menu then GamepadNav.focusFirst(menu) end
end

-- Spieler, der dem Bildschirmmittelpunkt am naechsten ist (R3 = Inspektor)
local function aimedPlayer(): Player?
	local camera = workspace.CurrentCamera
	if not camera then return nil end
	local center = camera.ViewportSize / 2
	local best: Player? = nil
	local bestDistance = camera.ViewportSize.Y * 0.25   -- nur nahe der Mitte
	for _, other in Players:GetPlayers() do
		if other ~= Players.LocalPlayer and other.Character then
			local root = other.Character:FindFirstChild("HumanoidRootPart")
			if root and root:IsA("BasePart") then
				local point, onScreen = camera:WorldToViewportPoint(root.Position)
				if onScreen and point.Z < 80 then
					local d = (Vector2.new(point.X, point.Y) - center).Magnitude
					if d < bestDistance then best, bestDistance = other, d end
				end
			end
		end
	end
	return best
end

local PANEL_HANDLERS: { [string]: () -> boolean } = {
	close = function()
		local name = PanelManager.current()
		if not name then return false end
		PanelManager.close(name)
		return true
	end,
	menu = function()
		local name = PanelManager.current()
		if name then PanelManager.close(name) end
		focusMenu()
		return true
	end,
	primary = function()
		local window = topWindow()
		local button = if window then GamepadNav.primary(window) else nil
		if not button then return false end
		GamepadNav.select(button)
		return true
	end,
	tabPrev  = function() local w = topWindow(); return w ~= nil and GamepadNav.stepTab(w, -1) ~= nil end,
	tabNext  = function() local w = topWindow(); return w ~= nil and GamepadNav.stepTab(w, 1) ~= nil end,
	pagePrev = function() local w = topWindow(); return w ~= nil and GamepadNav.scrollPage(w, -1) end,
	pageNext = function() local w = topWindow(); return w ~= nil and GamepadNav.scrollPage(w, 1) end,
}

local WORLD_HANDLERS: { [string]: () -> boolean } = {
	event  = function() return PetBar.press("Event") end,
	fight  = function() return PetBar.press("Fight") end,
	recall = function() return PetBar.press("Recall") end,
	menu   = function() focusMenu(); return true end,
	inspect = function()
		local target = aimedPlayer()
		if not target then return false end
		PanelManager.open("Profile", target.UserId)
		return true
	end,
}

local function actionFor(list: { GamepadConfig.Binding }, key: string): string?
	for _, binding in list do
		if binding.key == key then return binding.action end
	end
	return nil
end

local function onKey(key: string, state: Enum.UserInputState): Enum.ContextActionResult
	if state ~= Enum.UserInputState.Begin or not _active then return Enum.ContextActionResult.Pass end
	local inPanel = PanelManager.current() ~= nil
	local action = actionFor(if inPanel then GamepadConfig.PANEL else GamepadConfig.WORLD, key)
	local handler = if action then (if inPanel then PANEL_HANDLERS[action] else WORLD_HANDLERS[action]) else nil
	if handler and handler() then
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

--------------------------------------------------------------------------------
-- Fokus beim Oeffnen / Schliessen
--------------------------------------------------------------------------------

local function hookPanelManager()
	if _managerHooked then return end
	_managerHooked = true
	PanelManager.onOpened(function(_name: string)
		if not _active then return end
		local before = GuiService.SelectedObject
		if before and not _returnFocus then _returnFocus = before end
		-- Fenster baut sich im selben Frame auf; kurz warten, dann ersten Knopf waehlen
		task.delay(0.1, function()
			if not _active then return end
			local window = topWindow()
			if window then GamepadNav.focusFirst(window) end
		end)
	end)
	PanelManager.onClosed(function(_name: string, _seconds: number)
		if not _active then return end
		task.defer(function()
			if PanelManager.current() then return end   -- anderes Fenster hat uebernommen
			local back = _returnFocus
			_returnFocus = nil
			if back and back.Parent and back:IsDescendantOf(game) then
				GamepadNav.select(back)
			else
				GamepadNav.select(nil)
			end
		end)
	end)
end

--------------------------------------------------------------------------------
-- Prompts, Glyphen, Legende
--------------------------------------------------------------------------------

local function tunePrompt(prompt: ProximityPrompt)
	prompt.GamepadKeyCode = Enum.KeyCode[GamepadConfig.PROMPT_KEY]
	prompt.ClickablePrompt = true
end

local function buildLegend(screenGui: ScreenGui)
	local frame = Instance.new("Frame")
	frame.Name = "PadLegend"
	frame.AnchorPoint = Vector2.new(0, 1)
	frame.AutomaticSize = Enum.AutomaticSize.XY
	frame.Size = UDim2.fromOffset(0, 0)
	frame.BackgroundColor3 = Color3.fromRGB(24, 20, 38)
	frame.BackgroundTransparency = 0.25
	frame.BorderSizePixel = 0
	frame.ZIndex = 4
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6)
	pad.Parent = frame
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.AutomaticSize = Enum.AutomaticSize.XY
	label.Size = UDim2.fromOffset(0, 0)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 22   -- Konsole: >= 24 px bei 1080p entsteht ueber UiScale (1,27 am TV)
	local parts = {}
	for _, entry in GamepadConfig.LEGEND do
		table.insert(parts, string.format("[%s] %s", entry.glyph, Loc.t(entry.textKey)))
	end
	label.Text = table.concat(parts, "   ")
	label.ZIndex = 5
	label.Parent = frame
	-- Rand >= 5 %: bei der Skala der Oberflaeche rechnet UiScale; hier grob 5 % der Hoehe
	local margin = math.max(24, math.floor(screenGui.AbsoluteSize.Y * 0.05 / math.max(1, screenGui.AbsoluteSize.Y / 820)))
	frame.Position = UDim2.new(0, margin, 1, -margin)
	frame.Parent = screenGui
	return frame
end

local function setGlyphs(on: boolean)
	for mode, binding in { Event = "L1", Fight = "R1" } do
		local button = PetBar.getButton(mode)
		if button then
			if on then GamepadNav.addGlyph(button, binding) else GamepadNav.removeGlyph(button) end
		end
	end
end

--------------------------------------------------------------------------------
-- Ein- und Ausschalten
--------------------------------------------------------------------------------

local function enable()
	if _active then return end
	local gui = _screenGui
	if not gui then return end
	_active = true
	hookPanelManager()

	-- Union aller Tasten beider Ebenen; Start bleibt bei Roblox
	local keys: { [string]: boolean } = {}
	for _, list in { GamepadConfig.WORLD, GamepadConfig.PANEL } do
		for _, binding in list do
			if binding.key ~= "ButtonStart" then keys[binding.key] = true end
		end
	end
	for key in keys do
		local name = GamepadConfig.ACTION_PREFIX .. key
		ContextActionService:BindActionAtPriority(name, function(_n: string, state: Enum.UserInputState)
			return onKey(key, state)
		end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode[key])
		table.insert(_boundActions, name)
	end

	GamepadNav.styleSelection(gui)
	_legend = buildLegend(gui)
	setGlyphs(true)

	for _, d in workspace:GetDescendants() do
		if d:IsA("ProximityPrompt") then tunePrompt(d) end
	end
	_promptConn = workspace.DescendantAdded:Connect(function(d: Instance)
		if d:IsA("ProximityPrompt") then tunePrompt(d) end
	end)
	_shownConn = ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		if _active then tunePrompt(prompt) end
	end)
end

local function disable()
	if not _active then return end
	_active = false
	for _, name in _boundActions do
		ContextActionService:UnbindAction(name)
	end
	table.clear(_boundActions)
	GamepadNav.unstyleSelection()
	setGlyphs(false)
	if _legend then _legend:Destroy(); _legend = nil end
	if _promptConn then _promptConn:Disconnect(); _promptConn = nil end
	if _shownConn then _shownConn:Disconnect(); _shownConn = nil end
	_returnFocus = nil
	GuiService.SelectedObject = nil
end

-- Wird von Tests/Debug genutzt
function GamepadController.isActive(): boolean
	return _active
end

function GamepadController.init(screenGui: ScreenGui)
	_screenGui = screenGui
	local function apply()
		if FeatureFlags.isOn("CONSOLE_V1") and DeviceProfile.kind() == "console" then
			enable()
		else
			disable()
		end
	end
	DeviceProfile.onChanged(function() apply() end)
	apply()
end

return GamepadController
