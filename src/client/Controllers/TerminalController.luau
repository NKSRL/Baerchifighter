--!strict
-- TerminalController.luau
-- StarterPlayerScripts/Controllers/TerminalController.luau
--
-- Einzige Zustaendigkeit:
--   - Das Tower-Terminal an der Bruecke (08.10., Paket B2) lebendig machen:
--     Bildschirm (SurfaceGui, in der Sprache des Betrachters), Lampenfarbe
--     und Blinken, "!"-Marker, und am EIGENEN Terminal der Prompt
--     "Tower waehlen", der das Tower-Panel oeffnet.
--
-- Der Server baut das Terminal einmal (TerminalBuilder) und schreibt nur
-- Attribute (State, Tower, Record, NextTower, NewTower, Progress, Needed). Hier wird
-- daraus Text und Licht — ohne Neubau, ohne Emitter, ohne Light-Instanz
-- (Neon + Bloom). Eine Heartbeat-Schleife fuer das Blinken aller Terminals.
--
-- Zustaende (TowerConfig.terminalState):
--   locked  Bildschirm dunkel mit Schloss und "Tower I 12/30", Lampe rot;
--           der Prompt oeffnet nichts, sondern zeigt einen Hinweis
--   ready   Bildschirm leuchtet "NEU: Tower II!", Lampe gruen blinkend, "!"
--   normal  ruhig, zeigt den gewaehlten Tower und den Rekord

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loc          = require(ReplicatedStorage.Localization.Loc)
local MapConfig    = require(ReplicatedStorage.Config.MapConfig)
local TowerConfig  = require(ReplicatedStorage.Config.TowerConfig)
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)

local UI           = script.Parent.Parent:WaitForChild("UI")
local Theme        = require(UI:WaitForChild("Theme"))
local Kit          = require(UI:WaitForChild("Kit"))
local Icons        = require(UI:WaitForChild("Icons"))
local Notify       = require(UI:WaitForChild("Notify"))
local Toast        = require(UI:WaitForChild("Toast"))
local PanelManager = require(UI:WaitForChild("PanelManager"))

local TerminalController = {}

local MODEL_NAME = "TowerTerminal"
local CFG = MapConfig.TOWER_TERMINAL
local T = Kit.T

type View = {
	model   : Model,
	screen  : SurfaceGui,
	bg      : Frame,
	badgeHolder : Frame,
	lock    : GuiObject,
	title   : TextLabel,
	line    : TextLabel,
	bar     : Kit.Progress,
	lamp    : BasePart?,
	marker  : BillboardGui,
	prompt  : ProximityPrompt?,
	badgeKey: string,
}

local _views: { [Model]: View } = {}

local function isOwn(model: Model): boolean
	local plot = model.Parent
	return plot ~= nil and plot:GetAttribute("PlotOwner") == Players.LocalPlayer.UserId
end

local function attr(model: Model, name: string, default: any): any
	local value = model:GetAttribute(name)
	return if value == nil then default else value
end

local function towerName(id: string): string
	return Loc.t("tower." .. id .. ".name")
end

local function write(view: View)
	local model = view.model
	local state = attr(model, "State", "locked") :: string
	local towerId = attr(model, "Tower", "I") :: string
	local record = attr(model, "Record", 0) :: number
	local nextTower = attr(model, "NextTower", "") :: string
	local progress = attr(model, "Progress", 0) :: number
	local needed = attr(model, "Needed", 0) :: number
	local def = TowerConfig.get(towerId) or TowerConfig.TOWERS[1]

	-- Abzeichen nur neu bauen, wenn sich Tower oder Zustand aendern
	local key = state .. ":" .. def.id
	if view.badgeKey ~= key then
		view.badgeKey = key
		for _, child in view.badgeHolder:GetChildren() do child:Destroy() end
		local shown = if state == "locked" then (TowerConfig.get(nextTower) or def) else def
		local badge = Kit.towerBadge("Badge", view.badgeHolder, shown.look, shown.color, shown.numeral, 150)
		badge.Size = UDim2.fromScale(1, 1)
		badge.ZIndex = 3
	end

	view.lock.Visible = state == "locked"
	if state == "locked" then
		local prev = TowerConfig.UNLOCK_AFTER[nextTower] or TowerConfig.FIRST_TOWER
		view.title.Text = Loc.t("ui.terminal.screen_locked")
		view.title.TextColor3 = Color3.fromRGB(255, 120, 120)
		view.line.Text = Loc.t("ui.terminal.screen_unlock_by", { tower = towerName(prev) })
		view.bar.track.Visible = true
		view.bar.set(if needed > 0 then progress / needed else 0, string.format("%d/%d", progress, needed))
		view.bg.BackgroundColor3 = Color3.fromRGB(28, 22, 36)
	elseif state == "ready" then
		local newId = attr(model, "NewTower", towerId) :: string
		view.title.Text = Loc.t("ui.terminal.screen_new", { tower = towerName(newId) })
		view.title.TextColor3 = Color3.fromRGB(140, 255, 150)
		view.line.Text = Loc.t("ui.terminal.prompt_action")
		view.bar.track.Visible = false
		view.bg.BackgroundColor3 = Theme.shade(def.color, -0.55)
	else
		view.title.Text = towerName(def.id)
		view.title.TextColor3 = T.color.white
		view.line.Text = if def.id == "Endless"
			then Loc.t("ui.tower2.record_endless", { record = record })
			else Loc.t("ui.tower2.record", { record = record, stages = def.stages })
		view.bar.track.Visible = def.id ~= "Endless"
		view.bar.set(record / math.max(1, def.stages), "")
		view.bg.BackgroundColor3 = Theme.shade(def.color, -0.6)
	end

	view.marker.Enabled = state == "ready" and isOwn(model)

	local prompt = view.prompt
	if prompt then
		if state == "locked" then
			local prev = TowerConfig.UNLOCK_AFTER[nextTower] or TowerConfig.FIRST_TOWER
			prompt.ActionText = Loc.t("ui.terminal.prompt_locked", { tower = towerName(prev), have = progress, need = needed })
		else
			prompt.ActionText = Loc.t("ui.terminal.prompt_action")
		end
		prompt.ObjectText = Loc.t("ui.terminal.prompt_object")
	end
end

local function buildScreen(model: Model): View?
	local screenPart = model:FindFirstChild(CFG.screenPart)
	if not screenPart or not screenPart:IsA("BasePart") then return nil end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "TerminalScreen"
	gui.Face = Enum.NormalId.Front
	gui.CanvasSize = CFG.screenPixels
	gui.LightInfluence = 0
	gui.Brightness = 1.4
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.MaxDistance = 120
	gui.Adornee = screenPart
	gui.Parent = screenPart

	local bg = Kit.frame("Bg", gui, Color3.fromRGB(28, 22, 36))
	bg.Size = UDim2.fromScale(1, 1)
	local glow = Instance.new("UIGradient")
	glow.Rotation = 90
	glow.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 150, 150))
	glow.Parent = bg

	local badgeHolder = Kit.frame("BadgeHolder", bg)
	badgeHolder.AnchorPoint = Vector2.new(0, 0.5)
	badgeHolder.Position = UDim2.new(0, 24, 0.5, 0)
	badgeHolder.Size = UDim2.fromOffset(150, 150)

	local lock = Icons.make(badgeHolder, "lock", "🔒")
	lock.AnchorPoint = Vector2.new(0.5, 0.5)
	lock.Position = UDim2.fromScale(0.5, 0.5)
	lock.Size = UDim2.fromOffset(110, 110)
	lock.ZIndex = 8

	local title = Kit.text("Title", bg, "", 48, { color = T.color.white, stroke = 4, min = 24 })
	title.Position = UDim2.fromOffset(196, 30)
	title.Size = UDim2.new(1, -212, 0, 60)
	local line = Kit.text("Line", bg, "", 32, { color = Color3.fromRGB(240, 230, 210), stroke = 3, min = 20 })
	line.Position = UDim2.fromOffset(196, 96)
	line.Size = UDim2.new(1, -212, 0, 44)
	local bar = Kit.progress("Bar", bg, 36, T.color.honey)
	bar.track.Position = UDim2.fromOffset(196, 156)
	bar.track.Size = UDim2.new(1, -212, 0, 36)

	-- "!" ueber dem Terminal (nur am eigenen, im Zustand "ready")
	local marker = Instance.new("BillboardGui")
	marker.Name = "TerminalMarker"
	marker.Size = UDim2.fromOffset(64, 64)
	marker.StudsOffsetWorldSpace = Vector3.new(0, CFG.markerHeight, 0)
	marker.AlwaysOnTop = true
	marker.LightInfluence = 0
	marker.MaxDistance = 180
	marker.Enabled = false
	marker.Adornee = model.PrimaryPart or screenPart
	marker.Parent = screenPart
	local bang = Kit.text("Bang", marker, "!", 56, { color = Color3.fromRGB(255, 230, 80), stroke = 4, align = Enum.TextXAlignment.Center })
	bang.Size = UDim2.fromScale(1, 1)

	local lamp = model:FindFirstChild(CFG.lampPart)
	local view: View = {
		model = model, screen = gui, bg = bg, badgeHolder = badgeHolder, lock = lock,
		title = title, line = line, bar = bar,
		lamp = if lamp and lamp:IsA("BasePart") then lamp else nil,
		marker = marker, prompt = nil, badgeKey = "",
	}

	if isOwn(model) then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "TerminalPrompt"
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0   -- Paket G: ein Druck genuegt
		prompt.MaxActivationDistance = CFG.promptDistance
		prompt.RequiresLineOfSight = false
		prompt.Parent = screenPart
		prompt.Triggered:Connect(function()
			if attr(model, "State", "locked") == "locked" then
				local nextTower = attr(model, "NextTower", "II") :: string
				local prev = TowerConfig.UNLOCK_AFTER[nextTower] or TowerConfig.FIRST_TOWER
				local needed = attr(model, "Needed", 0)
				Notify.emit("terminal_locked", function()
					Toast.info(Loc.t("msg.terminal_locked", { tower = towerName(prev), need = needed }))
				end)
				return
			end
			Kit.playSound("click")
			PanelManager.open(PanelManager.ARENA_PANEL)
		end)
		view.prompt = prompt
	end

	model.AttributeChanged:Connect(function()
		write(view)
	end)
	model.Destroying:Connect(function()
		_views[model] = nil
	end)
	write(view)
	return view
end

local function hook(instance: Instance)
	if not instance:IsA("Model") or instance.Name ~= MODEL_NAME then return end
	if _views[instance] then return end
	-- Teile kommen evtl. nach dem Model an; einen Frame warten
	task.defer(function()
		if not instance.Parent or _views[instance] then return end
		if not instance:FindFirstChild(CFG.screenPart) then
			instance:WaitForChild(CFG.screenPart, 5)
		end
		local view = buildScreen(instance)
		if view then _views[instance] = view end
	end)
end

-- Lampe: Farbe nach Zustand, "ready" blinkt (eine Schleife fuer alle)
local function blink()
	local on = (os.clock() % (CFG.blinkSeconds * 2)) < CFG.blinkSeconds
	for model, view in _views do
		local lamp = view.lamp
		if lamp then
			local state = attr(model, "State", "locked") :: string
			local color = CFG.lampColors[state] or CFG.lampColors.normal
			if state == "ready" then
				lamp.Color = if on then color else Theme.shade(color, -0.6)
			else
				lamp.Color = color
			end
		end
		if view.marker.Enabled then
			view.marker.StudsOffsetWorldSpace = Vector3.new(0, CFG.markerHeight + math.sin(os.clock() * 4) * 0.4, 0)
		end
	end
end

-- Fuer die Fuehrung: der Bildschirm des eigenen Terminals.
function TerminalController.getOwnScreen(): BasePart?
	for model in _views do
		if isOwn(model) then
			local part = model:FindFirstChild(CFG.screenPart)
			if part and part:IsA("BasePart") then return part end
		end
	end
	return nil
end

function TerminalController.init()
	if not FeatureFlags.isOn("TOWER_TERMINAL") then return end
	for _, descendant in Workspace:GetDescendants() do
		hook(descendant)
	end
	Workspace.DescendantAdded:Connect(hook)
	Loc.onChanged(function()
		for _, view in _views do write(view) end
	end)
	RunService.Heartbeat:Connect(blink)
	print("[TerminalController] Initialisiert")
end

return TerminalController
