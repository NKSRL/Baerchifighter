--!strict
-- LeaderboardPanel.luau
-- StarterPlayerScripts/UI/LeaderboardPanel.luau
--
-- Einzige Zustaendigkeit:
--   - Die Bestenlisten im Menue zeigen (v15): drei Reiter (Tower, Rebirths,
--     Sammlung), Top 50 und der eigene Rang.
--
-- Die Daten holt das Panel beim Oeffnen und beim Reiterwechsel ueber die
-- RemoteFunction GetLeaderboard (der Server antwortet aus seinem Cache, der
-- alle 120 s aufgefrischt wird). Ein Klick auf einen Namen eines Spielers auf
-- diesem Server oeffnet seine Profilkarte (Inspektor).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types             = require(ReplicatedStorage.Network.Types)
local Remotes           = require(ReplicatedStorage.Network.Remotes)
local Loc               = require(ReplicatedStorage.Localization.Loc)
local LeaderboardConfig = require(ReplicatedStorage.Config.LeaderboardConfig)
local TowerConfig       = require(ReplicatedStorage.Config.TowerConfig)

local Theme        = require(script.Parent.Theme)
local PanelManager = require(script.Parent.PanelManager)
local Icons        = require(script.Parent.Icons)
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)

local LeaderboardPanel = {}

local PANEL_NAME = "Leaderboard"
local ROW_HEIGHT = 26

local _root: Frame? = nil
local _scroller: ScrollingFrame? = nil
local _own: TextLabel? = nil
local _tabs: { [string]: TextButton } = {}
local _list = "Tower"
local _requestId = 0

-- 14.10. (UI_HONEY_SKIN): schmales Saeulen-Fenster (daily_pillar, 342x976 -> Entwurf 300x856).
-- Sechseck = Titel, Creme-Flaeche = Liste mit Reiter-Wahl (Pfeile + Punkte), untere Pille = eigener Rang.
local _honey = false
local _light = false   -- helles Honig-Fenster (shop_window) statt dunklem Dialog
local TXT_DARK = Color3.fromRGB(110, 70, 36)
local _selLabel: TextLabel? = nil
local _dots: { Frame } = {}
local WIN_W, WIN_H = 300, 856
local BROWN  = Color3.fromRGB(110, 70, 36)
local BROWN2 = Color3.fromRGB(150, 104, 62)
local H_ROW = 40

local function formatValue(listId: string, value: number): string
	if listId == "Tower" then
		local towerId, stage = TowerConfig.fromLeaderboardValue(value)
		local def = TowerConfig.get(towerId) or TowerConfig.TOWERS[1]
		return Loc.t("ui.leaderboard.tower_value", { tower = Loc.t("ui.petbar.tower", { n = def.numeral }), stage = stage })
	end
	return Loc.formatNumber(value)
end

local function medalColor(rank: number): Color3
	if rank == 1 then return Color3.fromRGB(214, 140, 0)
	elseif rank == 2 then return Color3.fromRGB(122, 126, 140)
	elseif rank == 3 then return Color3.fromRGB(168, 92, 40) end
	return BROWN
end

local function renderHoney(view: Types.LeaderboardView?)
	local scroller = _scroller
	if not scroller then return end
	for _, child in scroller:GetChildren() do
		if child:IsA("Frame") then child:Destroy() end
	end
	local own = _own
	if not view then
		if own then own.Text = Loc.t("ui.leaderboard.loading") end
		return
	end
	for _, entry in view.entries do
		local mine = entry.userId == Players.LocalPlayer.UserId
		local row = Instance.new("Frame")
		row.Name = "Row" .. entry.rank
		row.BorderSizePixel = 0
		row.BackgroundColor3 = if mine then Color3.fromRGB(255, 196, 92) elseif entry.rank % 2 == 0 then Color3.fromRGB(255, 232, 192) else Color3.fromRGB(255, 240, 214)
		row.BackgroundTransparency = if mine then 0.1 else 0.35
		row.Size = UDim2.new(1, -6, 0, H_ROW)
		row.LayoutOrder = entry.rank
		row.Parent = scroller
		Theme.corner(row, 8)

		local rank = Instance.new("TextLabel")
		rank.BackgroundTransparency = 1
		rank.Font = Enum.Font.FredokaOne
		rank.Text = "#" .. entry.rank
		rank.TextColor3 = medalColor(entry.rank)
		rank.TextScaled = true
		rank.Position = UDim2.new(0, 5, 0, 6)
		rank.Size = UDim2.new(0, 34, 1, -12)
		rank.Parent = row
		local rcap = Instance.new("UITextSizeConstraint"); rcap.MaxTextSize = 18; rcap.Parent = rank

		local name = Instance.new("TextButton")
		name.Name = "Name"
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.FredokaOne
		name.TextScaled = true
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextColor3 = BROWN
		name.Text = entry.name
		name.Position = UDim2.new(0, 42, 0, 3)
		name.Size = UDim2.new(1, -46, 0, 19)
		name.Parent = row
		local ncap = Instance.new("UITextSizeConstraint"); ncap.MaxTextSize = 16; ncap.Parent = name
		name.Activated:Connect(function()
			if Players:GetPlayerByUserId(entry.userId) and entry.userId ~= Players.LocalPlayer.UserId then
				PanelManager.open("Profile", entry.userId)
			end
		end)

		local value = Instance.new("TextLabel")
		value.Name = "Value"
		value.BackgroundTransparency = 1
		value.Font = Enum.Font.FredokaOne
		value.Text = formatValue(view.listId, entry.value)
		value.TextColor3 = BROWN2
		value.TextScaled = true
		value.TextXAlignment = Enum.TextXAlignment.Left
		value.Position = UDim2.new(0, 42, 0, 22)
		value.Size = UDim2.new(1, -46, 0, 15)
		value.Parent = row
		local vcap = Instance.new("UITextSizeConstraint"); vcap.MaxTextSize = 13; vcap.Parent = value
	end
	if own then
		own.Text = if view.ownRank
			then Loc.t("ui.leaderboard.own_rank", { rank = view.ownRank, value = formatValue(view.listId, view.ownValue) })
			else Loc.t("ui.leaderboard.own_unranked", { value = formatValue(view.listId, view.ownValue) })
	end
end

local function render(view: Types.LeaderboardView?)
	if _honey then return renderHoney(view) end
	local scroller = _scroller
	if not scroller then return end
	for _, child in scroller:GetChildren() do
		if child:IsA("Frame") then child:Destroy() end
	end

	local own = _own
	if not view then
		if own then own.Text = Loc.t("ui.leaderboard.loading") end
		return
	end

	for _, entry in view.entries do
		local mine = entry.userId == Players.LocalPlayer.UserId
		local row = Theme.panel("Row" .. entry.rank, scroller, if mine then Theme.COLORS.panelLight else Theme.COLORS.panel)
		if _light then
			row.BackgroundColor3 = if mine then Color3.fromRGB(255, 196, 92) elseif entry.rank % 2 == 0 then Color3.fromRGB(255, 232, 192) else Color3.fromRGB(255, 240, 214)
			for _, c in row:GetChildren() do
				if c:IsA("UIStroke") or c:IsA("UIGradient") then c:Destroy() end
			end
		end
		row.Size        = UDim2.new(1, -8, 0, ROW_HEIGHT)
		row.LayoutOrder = entry.rank

		local rank = Theme.label("Rank", row, "#" .. entry.rank)
		rank.Position = UDim2.new(0, 8, 0, 3)
		rank.Size     = UDim2.new(0, 44, 1, -6)
		rank.TextColor3 = if entry.rank <= 3 then Theme.COLORS.goldGummy else Theme.COLORS.textDim
		if _light then rank.TextColor3 = medalColor(entry.rank) end

		local name = Instance.new("TextButton")
		name.Name = "Name"
		name.BackgroundTransparency = 1
		name.Font = Theme.FONT
		name.TextScaled = true
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextColor3 = if _light then TXT_DARK else Theme.COLORS.text
		name.Text = entry.name
		name.Position = UDim2.new(0, 56, 0, 3)
		name.Size     = UDim2.new(0.55, -56, 1, -6)
		name.Parent   = row
		name.Activated:Connect(function()
			if Players:GetPlayerByUserId(entry.userId) and entry.userId ~= Players.LocalPlayer.UserId then
				PanelManager.open("Profile", entry.userId)
			end
		end)

		local value = Theme.label("Value", row, formatValue(view.listId, entry.value))
		value.AnchorPoint    = Vector2.new(1, 0)
		value.Position       = UDim2.new(1, -8, 0, 3)
		value.Size           = UDim2.new(0.42, 0, 1, -6)
		value.TextXAlignment = Enum.TextXAlignment.Right
		if _light then
			value.TextColor3 = Color3.fromRGB(150, 104, 62)
			for _, c in value:GetChildren() do if c:IsA("UIStroke") then c:Destroy() end end
			value.TextStrokeTransparency = 1
		end
	end

	if own then
		own.Text = if view.ownRank
			then Loc.t("ui.leaderboard.own_rank", { rank = view.ownRank, value = formatValue(view.listId, view.ownValue) })
			else Loc.t("ui.leaderboard.own_unranked", { value = formatValue(view.listId, view.ownValue) })
	end
end

local function load(listId: string)
	_list = listId
	for id, tab in _tabs do
		if _light then
			tab.BackgroundColor3 = if id == listId then Color3.fromRGB(255, 176, 48) else Color3.fromRGB(246, 218, 170)
		else
			tab.BackgroundColor3 = if id == listId then Theme.COLORS.accent else Theme.COLORS.panelLight
		end
	end
	if _honey then
		if _selLabel then _selLabel.Text = Loc.t("ui.leaderboard.list." .. listId) end
		for i, dot in _dots do
			local active = LeaderboardConfig.LISTS[i] == listId
			dot.BackgroundColor3 = if active then Color3.fromRGB(230, 140, 20) else Color3.fromRGB(214, 176, 128)
			dot.Size = if active then UDim2.fromOffset(10, 10) else UDim2.fromOffset(7, 7)
		end
	end
	render(nil)

	_requestId += 1
	local myRequest = _requestId
	task.spawn(function()
		local ok, view = pcall(function()
			return Remotes.GetLeaderboard:InvokeServer(listId)
		end)
		if myRequest ~= _requestId then return end   -- inzwischen anderer Reiter
		render(if ok and typeof(view) == "table" then view :: Types.LeaderboardView else nil)
	end)
end

local function initHoney(screenGui: ScreenGui)
	local root = Theme.dialog("LeaderboardPanel", screenGui, Vector2.new(0.46, 0.72), Vector2.new(320, 420), Vector2.new(520, 640))
	_root = root
	_honey = true
	Icons.honeyWindow(root, "honey/daily_pillar", WIN_W, WIN_H)

	-- Sechseck: Pokal + Titel
	local cup = Icons.make(root, "trophy", "T")
	cup.AnchorPoint = Vector2.new(0.5, 0.5)
	cup.Position = UDim2.fromOffset(148, 78)
	cup.Size = UDim2.fromOffset(78, 78)
	cup.ZIndex = 5
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.FredokaOne
	title.Text = Loc.t("ui.leaderboard.title")
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextStrokeColor3 = Color3.fromRGB(110, 60, 20)
	title.TextStrokeTransparency = 0
	title.TextScaled = true
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromOffset(148, 142)
	title.Size = UDim2.fromOffset(120, 28)
	title.ZIndex = 5
	title.Parent = root
	local tcap = Instance.new("UITextSizeConstraint"); tcap.MaxTextSize = 24; tcap.Parent = title
	Loc.bind(title, "ui.leaderboard.title")

	-- Kreuz oben rechts (auf dem Blatt)
	local close = Theme.closeButton(root, function() PanelManager.close(PANEL_NAME) end)
	close.AnchorPoint = Vector2.new(0.5, 0.5)
	close.Position = UDim2.fromOffset(266, 34)
	close.Size = UDim2.fromOffset(42, 42)
	close.ZIndex = 30

	-- Creme-Flaeche (56,244)-(243,653)
	local field = Instance.new("Frame")
	field.Name = "Field"
	field.BackgroundTransparency = 1
	field.Position = UDim2.fromOffset(56, 244)
	field.Size = UDim2.fromOffset(187, 409)
	field.ZIndex = 5
	field.Parent = root

	-- Reiter-Wahl: < Name >
	local function arrow(text: string, x: number, step: number)
		local b = Theme.button("Arrow", field, text, Color3.fromRGB(255, 190, 70))
		b.Position = UDim2.fromOffset(x, 6)
		b.Size = UDim2.fromOffset(30, 28)
		b.TextColor3 = Color3.fromRGB(110, 60, 20)
		b.ZIndex = 6
		b.Activated:Connect(function()
			local n = #LeaderboardConfig.LISTS
			local idx = 1
			for i, id in LeaderboardConfig.LISTS do if id == _list then idx = i end end
			load(LeaderboardConfig.LISTS[((idx - 1 + step) % n) + 1])
		end)
	end
	arrow("<", 4, -1)
	arrow(">", 153, 1)
	local sel = Instance.new("TextLabel")
	sel.Name = "ListName"
	sel.BackgroundTransparency = 1
	sel.Font = Enum.Font.FredokaOne
	sel.TextColor3 = BROWN
	sel.TextScaled = true
	sel.Text = ""
	sel.Position = UDim2.fromOffset(38, 6)
	sel.Size = UDim2.fromOffset(111, 28)
	sel.ZIndex = 6
	sel.Parent = field
	local scap = Instance.new("UITextSizeConstraint"); scap.MaxTextSize = 17; scap.Parent = sel
	_selLabel = sel

	-- Punkte
	local dotRow = Instance.new("Frame")
	dotRow.BackgroundTransparency = 1
	dotRow.Position = UDim2.fromOffset(0, 38)
	dotRow.Size = UDim2.new(1, 0, 0, 12)
	dotRow.ZIndex = 6
	dotRow.Parent = field
	local dl = Instance.new("UIListLayout")
	dl.FillDirection = Enum.FillDirection.Horizontal
	dl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	dl.VerticalAlignment = Enum.VerticalAlignment.Center
	dl.Padding = UDim.new(0, 6)
	dl.Parent = dotRow
	for i = 1, #LeaderboardConfig.LISTS do
		local d = Instance.new("Frame")
		d.BorderSizePixel = 0
		d.Size = UDim2.fromOffset(7, 7)
		d.BackgroundColor3 = Color3.fromRGB(214, 176, 128)
		d.LayoutOrder = i
		d.ZIndex = 6
		Theme.corner(d, 5)
		d.Parent = dotRow
		_dots[i] = d
	end

	local scroller = Theme.scroller("List", field)
	scroller.Position = UDim2.fromOffset(0, 56)
	scroller.Size = UDim2.new(1, 0, 1, -60)
	scroller.ZIndex = 6
	local layout = Theme.listLayout(scroller, 3)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	_scroller = scroller

	-- Untere Pille (29,700)-(268,794): eigener Rang
	local own = Instance.new("TextLabel")
	own.Name = "Own"
	own.BackgroundTransparency = 1
	own.Font = Enum.Font.FredokaOne
	own.TextColor3 = Color3.fromRGB(110, 60, 20)
	own.TextScaled = true
	own.TextWrapped = true
	own.Text = ""
	own.Position = UDim2.fromOffset(52, 714)
	own.Size = UDim2.fromOffset(196, 66)
	own.ZIndex = 6
	own.Parent = root
	local ocap = Instance.new("UITextSizeConstraint"); ocap.MaxTextSize = 17; ocap.Parent = own
	_own = own

	PanelManager.register(PANEL_NAME, {
		open = function()
			root.Visible = true
			load(_list)
		end,
		close = function()
			root.Visible = false
		end,
	})
	print("[LeaderboardPanel] Initialisiert (Honig)")
end

function LeaderboardPanel.init(screenGui: ScreenGui)
	if false and FeatureFlags.isOn("UI_HONEY_SKIN") and Icons.hasUi("honey/daily_pillar") then -- Saeule ist fuer Daily vorgesehen; Honig-Zweig vorerst aus
		return initHoney(screenGui)
	end
	local root = Theme.dialog("LeaderboardPanel", screenGui, Vector2.new(0.46, 0.72), Vector2.new(320, 420), Vector2.new(520, 640))
	_root = root
	_light = Icons.honeyWindow(root, "honey/shop_window", 900, 600) ~= nil

	Theme.dialogHeader(root, Loc.t("ui.leaderboard.title"), function()
		PanelManager.close(PANEL_NAME)
	end)
	if _light then Icons.honeyHeader(root, Rect.new(82, 41, 797, 105), 837, 55, 58) end

	local body = Theme.dialogBody(root)
	if _light then
		body.Position = UDim2.fromOffset(70, 125)
		body.Size = UDim2.fromOffset(765, 385)
	end

	local tabs = Theme.container("Tabs", body)
	tabs.Size = UDim2.new(1, 0, 0, 30)
	local tabLayout = Theme.listLayout(tabs, 6, true)
	tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	for order, listId in LeaderboardConfig.LISTS do
		local tab = Theme.button("Tab_" .. listId, tabs, Loc.t("ui.leaderboard.list." .. listId), Theme.COLORS.panelLight)
		-- Paket 9: 5 Listen passen nur schmaler (gleich breit, 6 px Luecke)
		tab.Size = UDim2.new(1 / #LeaderboardConfig.LISTS, -6, 1, 0)
		tab.TextScaled = true
		tab.LayoutOrder = order
		tab.TextColor3 = if _light then TXT_DARK else Theme.COLORS.text
		if _light then
			for _, c in tab:GetChildren() do if c:IsA("UIStroke") then c.Color = Color3.fromRGB(150, 100, 50) end end
		end
		tab.Activated:Connect(function() load(listId) end)
		_tabs[listId] = tab
	end

	local scroller = Theme.scroller("List", body)
	scroller.Position = UDim2.new(0, 0, 0, 38)
	scroller.Size     = UDim2.new(1, 0, 1, -72)
	local layout = Theme.listLayout(scroller, 4)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	_scroller = scroller

	local own = Theme.label("Own", body, "")
	own.AnchorPoint = Vector2.new(0, 1)
	own.Position    = UDim2.new(0, 4, 1, 0)
	own.Size        = UDim2.new(1, -8, 0, 26)
	own.TextColor3  = if _light then TXT_DARK else Theme.COLORS.goldGummy
	if _light then
		own.Position = UDim2.new(0, 56, 1, 0)
		own.Size = UDim2.new(1, -112, 0, 26)
		own.TextXAlignment = Enum.TextXAlignment.Center
		own.TextStrokeTransparency = 1
		for _, c in own:GetChildren() do if c:IsA("UIStroke") then c:Destroy() end end
	end
	_own = own

	PanelManager.register(PANEL_NAME, {
		open = function()
			root.Visible = true
			load(_list)
		end,
		close = function()
			root.Visible = false
		end,
	})

	print("[LeaderboardPanel] Initialisiert")
end

return LeaderboardPanel
