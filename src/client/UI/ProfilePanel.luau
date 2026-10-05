--!strict
-- ProfilePanel.luau
-- StarterPlayerScripts/UI/ProfilePanel.luau
--
-- Einzige Zustaendigkeit:
--   - Die Profilkarte eines anderen Spielers zeigen (Inspektor, v15):
--     ausgeruesteter Baerchi (Rarity, Mutation, Level, Sterne), hoechster
--     Tower/Rekord, Rebirths, Index x/28 und die Top 3 Baerchis nach Staerke.
--
-- Geoeffnet ueber PanelManager.open("Profile", userId) — vom WorldController
-- (Klick auf Charakter oder Plot-Schild) und vom LeaderboardPanel. Die Karte
-- baut der Server (GetPlayerProfile); hier wird nur angezeigt.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types         = require(ReplicatedStorage.Network.Types)
local Remotes       = require(ReplicatedStorage.Network.Remotes)
local Loc           = require(ReplicatedStorage.Localization.Loc)
local BaerchiConfig = require(ReplicatedStorage.Config.BaerchiConfig)
local TowerConfig   = require(ReplicatedStorage.Config.TowerConfig)
local PromotionConfig = require(ReplicatedStorage.Config.PromotionConfig)

local Theme        = require(script.Parent.Theme)
local PanelManager = require(script.Parent.PanelManager)

local ProfilePanel = {}

local PANEL_NAME = "Profile"

local _root: Frame? = nil
local _title: TextLabel? = nil
local _lines: TextLabel? = nil
local _requestId = 0

local function baerchiLine(entry: Types.ProfileBaerchi): string
	local def = BaerchiConfig.getById(entry.configId)
	local name = Loc.name("baerchi." .. entry.configId .. ".name", if def then def.displayName else entry.configId)
	local stars = math.floor(math.clamp(entry.promotion, 0, PromotionConfig.MAX_PROMOTION) / 2)
	local mutation = if entry.mutation then " · " .. Loc.name("mutation." .. entry.mutation .. ".name", entry.mutation) else ""
	return string.format("%s  (%s%s)  Lv.%d  %s", name, Loc.name("rarity." .. entry.rarity, entry.rarity), mutation,
		entry.level, string.rep("★", stars))
end

local function render(card: Types.PlayerProfileCard?)
	local title, lines = _title, _lines
	if not title or not lines then return end
	if not card then
		title.Text = Loc.t("ui.profile.title")
		lines.Text = Loc.t("ui.profile.unavailable")
		return
	end

	title.Text = card.name
	local def = TowerConfig.get(card.highestTower) or TowerConfig.TOWERS[1]
	local out: { string } = {
		Loc.t("ui.profile.equipped", { baerchi = if card.equipped then baerchiLine(card.equipped) else "—" }),
		Loc.t("ui.profile.tower", { tower = def.numeral, stage = card.towerRecord }),
		Loc.t("ui.profile.rebirths", { n = card.rebirths }),
		Loc.t("ui.profile.index", { have = card.indexCount, total = card.indexTotal }),
		"",
		Loc.t("ui.profile.top"),
	}
	for i, entry in card.top do
		table.insert(out, string.format("%d. %s", i, baerchiLine(entry)))
	end
	lines.Text = table.concat(out, "\n")
end

local function show(userId: number)
	render(nil)
	local title = _title
	if title then title.Text = Loc.t("ui.leaderboard.loading") end

	_requestId += 1
	local myRequest = _requestId
	task.spawn(function()
		local ok, card = pcall(function()
			return Remotes.GetPlayerProfile:InvokeServer(userId)
		end)
		if myRequest ~= _requestId then return end
		render(if ok and typeof(card) == "table" then card :: Types.PlayerProfileCard else nil)
	end)
end

function ProfilePanel.init(screenGui: ScreenGui)
	local root = Theme.dialog("ProfilePanel", screenGui, Vector2.new(0.42, 0.5), Vector2.new(300, 300), Vector2.new(480, 420))
	_root = root

	_title = Theme.dialogHeader(root, Loc.t("ui.profile.title"), function()
		PanelManager.close(PANEL_NAME)
	end)

	local body = Theme.dialogBody(root)
	local lines = Theme.bodyText("Lines", body, "")
	lines.Size       = UDim2.fromScale(1, 1)
	lines.TextColor3 = Theme.COLORS.text
	lines.TextSize   = 15
	_lines = lines

	PanelManager.register(PANEL_NAME, {
		open = function(...: any)
			local userId = select(1, ...)
			if typeof(userId) ~= "number" then return end
			root.Visible = true
			show(userId)
		end,
		close = function()
			root.Visible = false
		end,
	})

	print("[ProfilePanel] Initialisiert")
end

return ProfilePanel
