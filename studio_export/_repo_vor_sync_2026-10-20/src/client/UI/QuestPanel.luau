--!strict
-- QuestPanel.luau
-- StarterPlayerScripts/UI/QuestPanel.luau
--
-- Einzige Zustaendigkeit:
--   - Das Quest-Fenster: die aktuelle Einsteiger-Quest und die Tages-Quests
--     mit Fortschritt und "Abholen"-Knopf
--   - Belohnungs-Text einer Quest (fuer Fenster, Tracker und Toast)
--
-- Das Fenster rechnet nichts: Fortschritt, Ziel und "abgeholt" liefert der
-- Server fertig in ClientState.get().quests (siehe QuestProgress). Auch ob
-- abholbar ist, prueft am Ende der Server — der Knopf hier ist nur die Anzeige.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types       = require(ReplicatedStorage.Network.Types)
local Remotes     = require(ReplicatedStorage.Network.Remotes)
local Loc         = require(ReplicatedStorage.Localization.Loc)
local QuestConfig = require(ReplicatedStorage.Config.QuestConfig)

local Theme        = require(script.Parent.Theme)
local PanelManager = require(script.Parent.PanelManager)
local ClientState  = require(script.Parent.Parent.Controllers.ClientState)

local QuestPanel = {}

local PANEL_NAME = "Quests"
local ROW_H      = 78

local _root: Frame?              = nil
local _scroller: ScrollingFrame? = nil
local _receivedAt = os.clock()

--------------------------------------------------------------------------------
-- Hilfen (auch vom Tracker benutzt)
--------------------------------------------------------------------------------

function QuestPanel.title(questId: string): string
	return Loc.t("quest." .. questId .. ".title")
end

function QuestPanel.hint(questId: string): string
	return Loc.t("quest." .. questId .. ".hint")
end

function QuestPanel.rewardText(questId: string): string
	local def = QuestConfig.getById(questId)
	if not def then return "" end

	local eggType = def.reward.eggType
	local text = if eggType
		then Loc.t("ui.quest.reward_with_egg", {
			n   = def.reward.gummies,
			egg = Loc.name("egg." .. eggType .. ".name", eggType),
		})
		else Loc.t("ui.quest.reward_gummies", { n = def.reward.gummies })
	-- GOLD_CHARMS_ONLY: Tages-Quests zeigen ihr Gold dazu
	local gold = QuestConfig.goldReward(def)
	if gold > 0 then
		text ..= "  " .. Loc.t("ui.quest.reward_gold", { n = gold })
	end
	return text
end

function QuestPanel.claim(entry: Types.QuestEntry)
	Remotes.RequestClaimQuest:FireServer(entry.kind, entry.id)
end

--------------------------------------------------------------------------------
-- Zeile
--------------------------------------------------------------------------------

local function buildRow(parent: Instance, order: number, entry: Types.QuestEntry)
	local done = entry.progress >= entry.target

	local row = Theme.panel("Quest_" .. entry.id, parent, Theme.COLORS.panel)
	row.Size        = UDim2.new(1, -8, 0, ROW_H)
	row.LayoutOrder = order

	local title = Theme.label("Title", row, QuestPanel.title(entry.id))
	title.Position = UDim2.new(0, 10, 0, 6)
	title.Size     = UDim2.new(1, -130, 0, 20)

	local reward = Theme.bodyText("Reward", row, QuestPanel.rewardText(entry.id))
	reward.Position   = UDim2.new(0, 10, 0, 28)
	reward.Size       = UDim2.new(1, -130, 0, 16)
	reward.TextSize   = 13
	reward.TextColor3 = Theme.COLORS.goldGummy

	local bar = Theme.progress(row, if done then Theme.COLORS.good else Theme.COLORS.accent)
	bar.track.Position = UDim2.new(0, 10, 1, -26)
	bar.track.Size     = UDim2.new(1, -130, 0, 18)
	bar.fill.Size      = UDim2.fromScale(math.clamp(entry.progress / math.max(1, entry.target), 0, 1), 1)
	bar.text.Text      = Loc.formatNumber(entry.progress) .. " / " .. Loc.formatNumber(entry.target)
	bar.text.TextScaled = false
	bar.text.TextSize   = 12

	if entry.claimed then
		local tag = Theme.label("Done", row, Loc.t("ui.quest.claimed"))
		tag.AnchorPoint    = Vector2.new(1, 0.5)
		tag.Position       = UDim2.new(1, -12, 0.5, 0)
		tag.Size           = UDim2.new(0, 100, 0, 24)
		tag.TextXAlignment = Enum.TextXAlignment.Center
		tag.TextColor3     = Theme.COLORS.good
	else
		local button = Theme.bigButton("Claim", row, Loc.t("ui.quest.claim_short"), Theme.COLORS.good)
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position    = UDim2.new(1, -10, 0.5, 0)
		button.Size        = UDim2.new(0, 104, 0, 38)
		Theme.setEnabled(button, done)
		button.Activated:Connect(function()
			if done then QuestPanel.claim(entry) end
		end)
	end
end

local function buildSection(parent: Instance, order: number, text: string)
	local label = Theme.label("Section_" .. order, parent, text)
	label.LayoutOrder = order
	label.Size        = UDim2.new(1, -8, 0, 24)
	label.TextColor3  = Theme.COLORS.accent
end

--------------------------------------------------------------------------------
-- Aktualisieren
--------------------------------------------------------------------------------

function QuestPanel.refresh()
	local scroller, root = _scroller, _root
	if not scroller or not root or not root.Visible then return end

	for _, child in scroller:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end

	local data = ClientState.get()
	if not data or not data.quests then return end
	local quests = data.quests

	local order = 1
	buildSection(scroller, order, Loc.t("ui.quest.section_chain") .. "  "
		.. quests.chainDone .. "/" .. quests.chainTotal)
	order += 1

	if quests.chain then
		buildRow(scroller, order, quests.chain)
		order += 1
		local hint = Theme.bodyText("Hint", scroller, QuestPanel.hint(quests.chain.id))
		hint.LayoutOrder = order
		hint.Size        = UDim2.new(1, -8, 0, 34)
		order += 1
	else
		local all = Theme.bodyText("AllDone", scroller, Loc.t("ui.quest.chain_done"))
		all.LayoutOrder = order
		all.Size        = UDim2.new(1, -8, 0, 22)
		order += 1
	end

	buildSection(scroller, order, Loc.t("ui.quest.section_daily"))
	order += 1

	for _, entry in quests.daily do
		buildRow(scroller, order, entry)
		order += 1
	end

	local remaining = math.max(0, quests.dailyResetIn - (os.clock() - _receivedAt))
	local resets = Theme.bodyText("Resets", scroller, Loc.t("ui.quest.resets_in", { time = Loc.formatDuration(remaining) }))
	resets.LayoutOrder = order
	resets.Size        = UDim2.new(1, -8, 0, 20)
end

--------------------------------------------------------------------------------
-- Aufbau
--------------------------------------------------------------------------------

function QuestPanel.init(screenGui: ScreenGui)
	local root = Theme.dialog("QuestPanel", screenGui,
		Vector2.new(0.46, 0.7), Vector2.new(300, 320), Vector2.new(480, 560))
	_root = root

	local title = Theme.dialogHeader(root, "", function()
		PanelManager.close(PANEL_NAME)
	end)
	Loc.bind(title, "ui.quest.panel_title")

	local body = Theme.dialogBody(root)

	local scroller = Theme.scroller("List", body)
	scroller.Size = UDim2.fromScale(1, 1)
	_scroller = scroller
	local layout = Theme.listLayout(scroller, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left

	PanelManager.register(PANEL_NAME, {
		open = function()
			root.Visible = true
			QuestPanel.refresh()
		end,
		close = function()
			root.Visible = false
		end,
	})

	ClientState.onChanged(function()
		_receivedAt = os.clock()
		QuestPanel.refresh()
	end)
	Loc.onChanged(function()
		QuestPanel.refresh()
	end)

	print("[QuestPanel] Initialisiert")
end

return QuestPanel
