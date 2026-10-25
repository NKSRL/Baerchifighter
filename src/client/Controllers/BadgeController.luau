--!strict
-- BadgeController.luau
-- StarterPlayerScripts/Controllers/BadgeController.luau
--
-- Einzige Zustaendigkeit:
--   - Rang-Billboard ueber dem Kopf jedes Spielers (Welt 1, Paket 3, Schalter RANK_BADGE_V2).
--     Zeile 1: Name. Zeile 2: Plakette "Tower II · 37" / "Final · 100" / "Neuling" in der Tower-Farbe mit dunkler
--     Kontur, daneben Rebirth "R5" (nur wenn >= 1). Die Daten kommen aus drei Spieler-Attributen, die der Server
--     setzt (PlayerBadgeService); hier wird nur gezeichnet.
--   - Antippen/Anklicken oeffnet den bestehenden Inspektor (PanelManager "Profile").
--
-- Ein BillboardGui pro Spieler, hoechstens MAX_VISIBLE gleichzeitig sichtbar (die naechsten), feste Groesse
-- auf dem Bildschirm, weiches Ausblenden zwischen FADE_START und MAX_DISTANCE. Kein Frame-Loop: eine
-- Abstandspruefung alle UPDATE_STEP Sekunden. Alles wird beim Verlassen und bei jedem Respawn sauber entfernt.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")

local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)
local BadgeConfig  = require(ReplicatedStorage.Config.BadgeConfig)
local TowerConfig  = require(ReplicatedStorage.Config.TowerConfig)
local BadgeRules   = require(ReplicatedStorage.Modules.BadgeRules)
local Loc          = require(ReplicatedStorage.Localization.Loc)

local PanelManager = require(script.Parent.Parent.UI.PanelManager)

local BadgeController = {}

type Entry = {
	player   : Player,
	gui      : BillboardGui,
	canvas   : CanvasGroup,
	name     : TextLabel,
	rank     : TextLabel,
	rebirth  : TextLabel,
	stroke   : UIStroke,
	alpha    : number,
}

local C = BadgeConfig.COLORS
local _entries: { [Player]: Entry } = {}
local _connections: { [Player]: { RBXScriptConnection } } = {}

local function isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function sizeFor(player: Player): Vector2
	local base = if player == Players.LocalPlayer then BadgeConfig.WORLD_SIZE_SELF else BadgeConfig.WORLD_SIZE_OTHER
	return if isTouch() then base * BadgeConfig.TOUCH_SCALE else base
end

local function label(parent: Instance, name: string, font: Enum.Font): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.BackgroundTransparency = 1
	l.Font = font
	l.TextScaled = true
	l.TextStrokeColor3 = C.outline
	l.TextStrokeTransparency = 0
	l.Parent = parent
	return l
end

local function build(player: Player, head: BasePart): Entry
	local gui = Instance.new("BillboardGui")
	gui.Name = BadgeConfig.GUI_NAME
	local size = sizeFor(player)
	-- 21.10.: Scale-Groesse = Studs (feste Groesse in der Welt), nicht mehr Pixel
	gui.Size = UDim2.fromScale(size.X, size.Y)
	gui.AlwaysOnTop = false
	gui.MaxDistance = BadgeConfig.MAX_DISTANCE
	gui.LightInfluence = 0
	gui.Active = true
	gui.ResetOnSpawn = false

	-- Hoehe nach dem tatsaechlichen Charakter (Huete, Aufbauten), nicht fix
	local top = head.Size.Y * 0.5
	local character = player.Character
	if character then
		local cf, ext = character:GetBoundingBox()
		top = math.max(top, cf.Position.Y + ext.Y * 0.5 - head.Position.Y)
	end
	gui.StudsOffsetWorldSpace = Vector3.new(0, top + BadgeConfig.HEAD_CLEARANCE, 0)

	local canvas = Instance.new("CanvasGroup")
	canvas.Name = "Canvas"
	canvas.Size = UDim2.fromScale(1, 1)
	canvas.BackgroundTransparency = 1
	canvas.Parent = gui

	local name = label(canvas, "Name", Enum.Font.FredokaOne)
	name.Size = UDim2.fromScale(1, 0.36)
	name.TextColor3 = C.name
	name.TextTransparency = 0.05

	local plaque = Instance.new("Frame")
	plaque.Name = "Plaque"
	plaque.Position = UDim2.fromScale(0, 0.4)
	plaque.Size = UDim2.fromScale(1, 0.6)
	plaque.BackgroundColor3 = C.plaqueBg
	plaque.BackgroundTransparency = 0.1
	plaque.Parent = canvas
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.3, 0)
	corner.Parent = plaque
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2
	stroke.Color = C.outline
	stroke.Parent = plaque
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 8)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 3), UDim.new(0, 3)
	pad.Parent = plaque

	local rank = label(plaque, "Rank", Enum.Font.FredokaOne)
	rank.Size = UDim2.fromScale(0.68, 1)
	rank.TextXAlignment = Enum.TextXAlignment.Left

	local rebirth = label(plaque, "Rebirth", Enum.Font.FredokaOne)
	rebirth.Position = UDim2.fromScale(0.7, 0)
	rebirth.Size = UDim2.fromScale(0.3, 1)
	rebirth.TextXAlignment = Enum.TextXAlignment.Right
	rebirth.TextColor3 = C.rebirth

	-- Antippen/Anklicken -> bestehender Inspektor (nicht fuer sich selbst)
	if player ~= Players.LocalPlayer then
		local button = Instance.new("TextButton")
		button.Name = "Inspect"
		button.BackgroundTransparency = 1
		button.Text = ""
		button.Size = UDim2.fromScale(1, 1)
		button.ZIndex = 10
		button.Parent = canvas
		button.Activated:Connect(function()
			PanelManager.open("Profile", player.UserId)
		end)
	end

	gui.Adornee = head
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return { player = player, gui = gui, canvas = canvas, name = name, rank = rank, rebirth = rebirth, stroke = stroke, alpha = 1 }
end

-- Beschriftung aus den Spieler-Attributen
local function refresh(entry: Entry)
	local p = entry.player
	local info = BadgeRules.fromAttributes(
		p:GetAttribute(BadgeConfig.ATTR_TOWER), p:GetAttribute(BadgeConfig.ATTR_RECORD), p:GetAttribute(BadgeConfig.ATTR_REBIRTH))
	entry.name.Text = p.DisplayName
	local key, args = BadgeRules.plaque(info)
	entry.rank.Text = Loc.t(key, args)
	local def = if info.towerId ~= "" then TowerConfig.get(info.towerId) else nil
	entry.rank.TextColor3 = if def then def.color else C.rookie
	entry.stroke.Color = if def then def.color else C.outline
	local showRebirth = BadgeRules.showRebirth(info)
	entry.rebirth.Visible = showRebirth
	entry.rebirth.Text = if showRebirth then Loc.t(BadgeConfig.TEXT.rebirth, { n = info.rebirth }) else ""
	entry.rank.Size = UDim2.fromScale(if showRebirth then 0.68 else 1, 1)
	entry.rank.TextXAlignment = if showRebirth then Enum.TextXAlignment.Left else Enum.TextXAlignment.Center
end

local function remove(player: Player)
	local entry = _entries[player]
	if entry then entry.gui:Destroy() end
	_entries[player] = nil
end

local function attach(player: Player)
	remove(player)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not (head and head:IsA("BasePart")) then return end
	local entry = build(player, head)
	_entries[player] = entry
	refresh(entry)
end

local function track(player: Player)
	if _connections[player] then return end
	local list: { RBXScriptConnection } = {}
	_connections[player] = list
	table.insert(list, player.CharacterAdded:Connect(function(character)
		character:WaitForChild("Head", 10)
		attach(player)
	end))
	table.insert(list, player.CharacterRemoving:Connect(function() remove(player) end))
	for _, attr in { BadgeConfig.ATTR_TOWER, BadgeConfig.ATTR_RECORD, BadgeConfig.ATTR_REBIRTH } do
		table.insert(list, player:GetAttributeChangedSignal(attr):Connect(function()
			local entry = _entries[player]
			if entry then refresh(entry) end
		end))
	end
	if player.Character then task.spawn(attach, player) end
end

local function untrack(player: Player)
	remove(player)
	local list = _connections[player]
	if list then
		for _, c in list do c:Disconnect() end
	end
	_connections[player] = nil
end

-- Abstand zur Kamera, Auswahl der naechsten MAX_VISIBLE, weiches Ausblenden
local function step()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local distances: { [Player]: number } = {}
	for player, entry in _entries do
		local head = entry.gui.Adornee
		if head and head:IsA("BasePart") and player ~= Players.LocalPlayer then
			distances[player] = (head.Position - camera.CFrame.Position).Magnitude
		end
	end
	local visible = BadgeRules.pickVisible(distances, BadgeConfig.MAX_VISIBLE)
	for player, entry in _entries do
		local show = player == Players.LocalPlayer or visible[player] == true
		entry.gui.Enabled = show
		if show then
			local alpha = if player == Players.LocalPlayer then 1 else BadgeRules.alphaAt(distances[player] or 0)
			if math.abs(alpha - entry.alpha) > 0.02 then
				entry.alpha = alpha
				TweenService:Create(entry.canvas, TweenInfo.new(BadgeConfig.FADE_TIME), { GroupTransparency = 1 - alpha }):Play()
			end
		end
	end
end

function BadgeController.init()
	if not FeatureFlags.isOn("RANK_BADGE_V2") then return end
	for _, p in Players:GetPlayers() do track(p) end
	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(untrack)
	-- Sprachwechsel: Beschriftungen neu setzen
	Loc.onChanged(function()
		for _, entry in _entries do refresh(entry) end
	end)
	task.spawn(function()
		while true do
			task.wait(BadgeConfig.UPDATE_STEP)
			step()
		end
	end)
	print("[BadgeController] Initialisiert | Rang-Billboard V2")
end

return BadgeController
