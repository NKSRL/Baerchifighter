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

local LeaderboardPanel = {}

local PANEL_NAME = "Leaderboard"
local ROW_HEIGHT = 26

local _root: Frame? = nil
local _scroller: ScrollingFrame? = nil
local _own: TextLabel? = nil
local _tabs: { [string]: TextButton } = {}
local _list = "Tower"
local _requestId = 0

local function formatValue(listId: string, value: number): string
	if listId == "Tower" then
		local towerId, stage = TowerConfig.fromLeaderboardValue(value)
		local def = TowerConfig.get(towerId) or TowerConfig.TOWERS[1]
		return Loc.t("ui.leaderboard.tower_value", { tower = Loc.t("ui.petbar.tower", { numeral = def.numeral }), stage = stage })
	end
	return Loc.formatNumber(value)
end

local function render(view: Types.LeaderboardView?)
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
		row.Size        = UDim2.new(1, -8, 0, ROW_HEIGHT)
		row.LayoutOrder = entry.rank

		local rank = Theme.label("Rank", row, "#" .. entry.rank)
		rank.Position = UDim2.new(0, 8, 0, 3)
		rank.Size     = UDim2.new(0, 44, 1, -6)
		rank.TextColor3 = if entry.rank <= 3 then Theme.COLORS.goldGummy else Theme.COLORS.textDim

		local name = Instance.new("TextButton")
		name.Name = "Name"
		name.BackgroundTransparency = 1
		name.Font = Theme.FONT
		name.TextScaled = true
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextColor3 = Theme.COLORS.text
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
		tab.BackgroundColor3 = if id == listId then Theme.COLORS.accent else Theme.COLORS.panelLight
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

function LeaderboardPanel.init(screenGui: ScreenGui)
	local root = Theme.dialog("LeaderboardPanel", screenGui, Vector2.new(0.46, 0.72), Vector2.new(320, 420), Vector2.new(520, 640))
	_root = root

	Theme.dialogHeader(root, Loc.t("ui.leaderboard.title"), function()
		PanelManager.close(PANEL_NAME)
	end)

	local body = Theme.dialogBody(root)

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
		tab.TextColor3 = Theme.COLORS.text
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
	own.TextColor3  = Theme.COLORS.goldGummy
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
