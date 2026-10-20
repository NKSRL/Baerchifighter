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
local Icons        = require(script.Parent.Icons)
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)

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

--------------------------------------------------------------------------------
-- 14.10. Honig-UI (UI_HONEY_SKIN): quest-bar.png als Zeile, quest-window.png als Fenster
--------------------------------------------------------------------------------

local HONEY_ROW_H = 80
local HONEY_WIN_W, HONEY_WIN_H = 900, 408   -- quest-window.png 1442 x 654 (2,205 : 1), unverzerrt

local function honeyOn(): boolean
	return FeatureFlags.isOn("UI_HONEY_SKIN") and Icons.hasUi("honey/quest_bar") and Icons.hasUi("honey/quest_window")
end

local function honeyLabel(name: string, parent: Instance, text: string, size: number): TextLabel
	local label = Theme.label(name, parent, text)
	label.TextScaled     = false
	label.TextSize       = size
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate   = Enum.TextTruncate.AtEnd
	label.ZIndex         = 4
	Theme.outlineText(label, 2)
	return label
end

local function buildHoneyRow(parent: Instance, order: number, entry: Types.QuestEntry)
	local done = entry.progress >= entry.target
	-- Das Bild (1408 x 296) wird nie verzerrt: feste Groesse im Originalverhaeltnis,
	-- alle Positionen sind Pixel des Originals mal S.
	local S = HONEY_ROW_H / 296
	local function px(v: number): number return math.floor(v * S + 0.5) end

	local row = Instance.new("Frame")
	row.Name                   = "Quest_" .. entry.id
	row.BackgroundTransparency = 1
	row.BorderSizePixel        = 0
	row.Size                   = UDim2.fromOffset(px(1408), HONEY_ROW_H)
	row.LayoutOrder            = order
	row.Parent                 = parent

	local skin = Icons.honeyImage(row, "honey/quest_bar")
	if skin then skin.ZIndex = 1 end

	-- Orange Leiste (x 150-873, y 52-143): Titel
	local title = honeyLabel("Title", row, QuestPanel.title(entry.id), 16)
	title.Position = UDim2.fromOffset(px(150), px(52))
	title.Size     = UDim2.fromOffset(px(873 - 150), px(143 - 52))

	-- Untere Leiste (x 72-845, y 163-227): Fortschritt, Belohnung links, Zaehler rechts
	local track = Instance.new("Frame")
	track.Name                   = "Track"
	track.BackgroundTransparency = 1
	track.Position               = UDim2.fromOffset(px(72), px(163))
	track.Size                   = UDim2.fromOffset(px(845 - 72), px(227 - 163))
	track.ZIndex                 = 2
	track.Parent                 = row

	local fraction = math.clamp(entry.progress / math.max(1, entry.target), 0, 1)
	if fraction > 0 then
		local fill = Instance.new("Frame")
		fill.Name                   = "Fill"
		fill.BackgroundColor3       = if done then Theme.COLORS.good else Color3.fromRGB(255, 190, 50)
		fill.BackgroundTransparency = 0.4
		fill.BorderSizePixel        = 0
		fill.Size                   = UDim2.fromScale(fraction, 1)
		fill.ZIndex                 = 2
		fill.Parent                 = track
		Theme.corner(fill, 8)
	end

	local reward = honeyLabel("Reward", track, QuestPanel.rewardText(entry.id), 11)
	reward.Position   = UDim2.new(0, 6, 0, 0)
	reward.Size       = UDim2.new(1, -52, 1, 0)
	reward.TextColor3 = Theme.COLORS.goldGummy

	local count = honeyLabel("Count", track, Loc.formatNumber(entry.progress) .. " / " .. Loc.formatNumber(entry.target), 12)
	count.AnchorPoint    = Vector2.new(1, 0)
	count.Position       = UDim2.new(1, -6, 0, 0)
	count.Size           = UDim2.new(0, 46, 1, 0)
	count.TextXAlignment = Enum.TextXAlignment.Right

	-- Graues Oval rechts (x 930-1330, y 92-225) = Platz fuer "Claim"
	local plateX, plateY = px(930), px(92)
	local plateW, plateH = px(1330 - 930), px(225 - 92)

	if entry.claimed then
		local tag = honeyLabel("Done", row, Loc.t("ui.quest.claimed"), 16)
		tag.Position       = UDim2.fromOffset(plateX, plateY)
		tag.Size           = UDim2.fromOffset(plateW, plateH)
		tag.TextXAlignment = Enum.TextXAlignment.Center
		tag.TextColor3     = Theme.COLORS.good
	else
		local glow = Instance.new("Frame")
		glow.Name                   = "ClaimGlow"
		glow.BackgroundColor3       = Theme.COLORS.good
		glow.BackgroundTransparency = 0.25
		glow.BorderSizePixel        = 0
		glow.Position               = UDim2.fromOffset(plateX, plateY)
		glow.Size                   = UDim2.fromOffset(plateW, plateH)
		glow.Visible                = done
		glow.ZIndex                 = 2
		glow.Parent                 = row
		Theme.corner(glow, plateH)

		local button = Instance.new("TextButton")
		button.Name                   = "Claim"
		button.BackgroundTransparency = 1
		button.AutoButtonColor        = false
		button.Position               = glow.Position
		button.Size                   = glow.Size
		button.Text                   = Loc.t("ui.quest.claim_short")
		button.Font                   = Theme.FONT
		button.TextSize               = 16
		button.TextColor3             = if done then Color3.new(1, 1, 1) else Color3.fromRGB(205, 190, 180)
		button.TextStrokeColor3       = Theme.COLORS.outline
		button.TextStrokeTransparency = if done then 0 else 0.4
		button.Active                 = done
		button.ZIndex                 = 5
		button.Parent                 = row
		button.Activated:Connect(function()
			if done then QuestPanel.claim(entry) end
		end)
	end
end

local function buildRow(parent: Instance, order: number, entry: Types.QuestEntry)
	if honeyOn() then
		buildHoneyRow(parent, order, entry)
		return
	end
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
	local honey = honeyOn()
	local root = if honey
		then Theme.dialog("QuestPanel", screenGui, Vector2.new(0.6, 0.8), Vector2.new(HONEY_WIN_W, HONEY_WIN_H), Vector2.new(HONEY_WIN_W, HONEY_WIN_H))
		else Theme.dialog("QuestPanel", screenGui,
			Vector2.new(0.46, 0.7), Vector2.new(300, 320), Vector2.new(480, 560))
	_root = root

	-- 14.10.: das Fenster ist ein Bild (quest-window.png, 1442 x 654, Titelleiste und
	-- Kreuz sind schon drin). Das alte Panel-Aussehen verschwindet.
	if honey then
		root.BackgroundTransparency = 1
		for _, child in root:GetChildren() do
			if child:IsA("UIStroke") or child:IsA("UIGradient") or child:IsA("UICorner") then
				child:Destroy()
			elseif child:IsA("GuiObject") then
				child.Visible = false
			end
		end
		root.Size = UDim2.fromOffset(HONEY_WIN_W, HONEY_WIN_H)   -- FitScale des Dialogs verkleinert bei Bedarf
		local frame = Icons.honeyImage(root, "honey/quest_window")
		if frame then frame.ZIndex = 0 end
	end

	local title = Theme.dialogHeader(root, "", function()
		PanelManager.close(PANEL_NAME)
	end)
	Loc.bind(title, "ui.quest.panel_title")

	local body = Theme.dialogBody(root)

	if honey then
		-- Titel in die Pille, Kreuz auf das Sechseck, Liste in den dunklen Teil
		local band = root:FindFirstChild("TitleBand")
		if band and band:IsA("GuiObject") then band.Visible = false end
		local header = root:FindFirstChild("Header")
		if header and header:IsA("GuiObject") then
			header.Position = UDim2.fromOffset(190, 40)
			header.Size     = UDim2.fromOffset(540, 56)
			local close = header:FindFirstChild("Close")
			if close and close:IsA("GuiObject") then
				close.Parent      = root
				close.AnchorPoint = Vector2.new(0.5, 0.5)
				close.Position    = UDim2.fromOffset(820, 69)   -- Mitte des Sechsecks im Bild
				close.Size        = UDim2.fromOffset(72, 72)
				local skin = close:FindFirstChild("HoneySkin")
				if skin and skin:IsA("GuiObject") then skin.Visible = false end
			end
		end
		body.Position = UDim2.fromOffset(30, 132)
		body.Size     = UDim2.fromOffset(HONEY_WIN_W - 60, HONEY_WIN_H - 132 - 26)
	end

	local scroller = Theme.scroller("List", body)
	scroller.Size = UDim2.fromScale(1, 1)
	_scroller = scroller
	local layout = Theme.listLayout(scroller, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	if honey then
		layout.FillDirection = Enum.FillDirection.Horizontal   -- Abschnitte sind volle Breite, Quest-Zeilen stehen zu zweit
		layout.Wraps = true
		layout.VerticalAlignment = Enum.VerticalAlignment.Top
	end

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
