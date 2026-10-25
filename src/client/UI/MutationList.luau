--!strict
-- MutationList.luau
-- StarterPlayerScripts/UI/MutationList.luau
--
-- Einzige Zustaendigkeit:
--   - Das kleine Honig-Fenster "Mutationen": alle Stufen mit Farbe, Staerke und
--     Seltenheit, damit Spieler wissen, was eine Mutation bringt und wie selten sie ist.
--   - Alle Zahlen kommen aus BaerchiConfig.MUTATIONS (Gewichte, Faktoren) — hier steht
--     keine eigene Balance. Namen ueber Names.mutation (Loc), Texte ueber Loc.
--
-- Wie PetSellConfirm: KEIN Panel im PanelManager. Das Fenster liegt ueber dem Menue, das
-- es geoeffnet hat; X, Escape und ein Klick daneben schliessen nur dieses Fenster.
-- Fenster-Optik nur aus dem hochgeladenen Template (honey/daily_window).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Loc = require(ReplicatedStorage.Localization.Loc)
local Names = require(ReplicatedStorage.Localization.Names)
local BaerchiConfig = require(ReplicatedStorage.Config.BaerchiConfig)

local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)

local MutationList = {}

-- Honig-Fenster (wie RebirthDialog / PetSellConfirm): daily_window, 660 x 440
local WIN_W, WIN_H = 660, 440
local ROW_H = 40
local HEAD_H = 22

-- Spaltenbreiten in Scale (Summe 1): Farbpunkt+Name | Staerke | Chance
local COL_NAME = 0.40
local COL_POWER = 0.20

local _backdrop: TextButton? = nil
local _root: Frame? = nil
local _scroller: ScrollingFrame? = nil
local _escape: RBXScriptConnection? = nil

-- Prozent-Anzeige ohne ueberfluessige Nullen: 1 -> "1 %", 0.0005 -> "0,0005 %"
local function formatPercent(percent: number): string
	local digits = 0
	while digits < 4 and math.abs(percent * 10 ^ digits - math.round(percent * 10 ^ digits)) > 1e-9 do
		digits += 1
	end
	return Loc.formatDecimal(percent, digits) .. " %"
end

-- Gesamtgewicht = alle Stufen + "keine Mutation" (siehe BaerchiConfig.rollMutation).
-- Das Gewicht "keine" ist dort lokal; die Summe aller Chancen ist 1.5 %, also 1_000_000 gesamt.
local TOTAL_WEIGHT = 1000000

local function addText(parent: Instance, name: string, text: string, size: number, color: Color3, xAlign: Enum.TextXAlignment): TextLabel
	local label = Theme.label(name, parent, text)
	label.TextScaled = false
	label.TextSize = size
	label.TextColor3 = color
	label.TextXAlignment = xAlign
	label.TextWrapped = true
	label.TextYAlignment = Enum.TextYAlignment.Center
	return label
end

local function clearList()
	local scroller = _scroller
	if not scroller then return end
	for _, child in scroller:GetChildren() do
		if not child:IsA("UIListLayout") then child:Destroy() end
	end
end

local function fill()
	local scroller = _scroller
	if not scroller then return end
	clearList()

	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	-- Einleitung: Gesamtchance aus den Gewichten
	local sum = 0
	for _, id in BaerchiConfig.MUTATION_ORDER do
		sum += BaerchiConfig.MUTATIONS[id].weight
	end
	local intro = addText(scroller, "Intro",
		Loc.t("ui.mut.intro", { pct = formatPercent(sum / TOTAL_WEIGHT * 100) }),
		16, Theme.COLORS.cream, Enum.TextXAlignment.Left)
	intro.Size = UDim2.new(1, -18, 0, 40)
	intro.LayoutOrder = nextOrder()

	-- Spaltenkopf
	local head = Theme.container("Head", scroller)
	head.Size = UDim2.new(1, -18, 0, HEAD_H)
	head.LayoutOrder = nextOrder()
	local headColor = Theme.COLORS.goldGummy
	local h1 = addText(head, "Name", Loc.t("ui.mut.col_name"), 16, headColor, Enum.TextXAlignment.Left)
	h1.Position = UDim2.new(0, 36, 0, 0)
	h1.Size = UDim2.new(COL_NAME, -36, 1, 0)
	local h2 = addText(head, "Power", Loc.t("ui.mut.col_power"), 16, headColor, Enum.TextXAlignment.Center)
	h2.Position = UDim2.fromScale(COL_NAME, 0)
	h2.Size = UDim2.fromScale(COL_POWER, 1)
	local h3 = addText(head, "Chance", Loc.t("ui.mut.col_chance"), 16, headColor, Enum.TextXAlignment.Right)
	h3.Position = UDim2.fromScale(COL_NAME + COL_POWER, 0)
	h3.Size = UDim2.fromScale(1 - COL_NAME - COL_POWER, 1)

	-- Eine Zeile je Stufe, von schwach/haeufig bis stark/selten (MUTATION_ORDER)
	for index, id in BaerchiConfig.MUTATION_ORDER do
		local def = BaerchiConfig.MUTATIONS[id]
		local row = Instance.new("Frame")
		row.Name = "Row_" .. id
		row.BackgroundColor3 = Color3.new(0, 0, 0)
		row.BackgroundTransparency = 0.55
		row.BorderSizePixel = 0
		row.Size = UDim2.new(1, -18, 0, ROW_H)
		row.LayoutOrder = nextOrder()
		row.Parent = scroller
		Theme.corner(row, 8)

		local dot = Instance.new("Frame")
		dot.Name = "Dot"
		dot.AnchorPoint = Vector2.new(0, 0.5)
		dot.Position = UDim2.new(0, 8, 0.5, 0)
		dot.Size = UDim2.fromOffset(22, 22)
		dot.BackgroundColor3 = def.color
		dot.BorderSizePixel = 0
		dot.Parent = row
		Theme.corner(dot, 11)
		Theme.stroke(dot, Color3.fromRGB(255, 244, 214), 2)

		-- Zu dunkle Stufenfarben (Bloodrot, Galaxy) fuer den Text auf dunklem Grund anheben
		local textColor = def.color
		local h, s, v = def.color:ToHSV()
		if v < 0.75 then textColor = Color3.fromHSV(h, math.min(s, 0.75), 0.9) end

		local name = addText(row, "Name", Names.mutation(id), 22, textColor, Enum.TextXAlignment.Left)
		name.Position = UDim2.new(0, 38, 0, 0)
		name.Size = UDim2.new(COL_NAME, -38, 1, 0)
		Theme.outlineText(name, 2)

		local power = addText(row, "Power", "×" .. Loc.formatDecimal(def.multiplier, 2), 24, Theme.COLORS.goldGummy, Enum.TextXAlignment.Center)
		power.Position = UDim2.fromScale(COL_NAME, 0)
		power.Size = UDim2.fromScale(COL_POWER, 1)
		Theme.outlineText(power, 2)

		local odds = addText(row, "Odds", Loc.t("ui.mut.odds", { n = Loc.formatNumber(math.round(TOTAL_WEIGHT / def.weight)) }),
			20, Theme.COLORS.cream, Enum.TextXAlignment.Right)
		odds.Position = UDim2.new(COL_NAME + COL_POWER, 0, 0, 3)
		odds.Size = UDim2.new(1 - COL_NAME - COL_POWER, -10, 0.55, 0)

		local per = addText(row, "Per", Loc.t("ui.mut.per_hatch", { pct = formatPercent(def.weight / TOTAL_WEIGHT * 100) }),
			14, Theme.COLORS.textDim, Enum.TextXAlignment.Right)
		per.Position = UDim2.new(COL_NAME + COL_POWER, 0, 0.55, 0)
		per.Size = UDim2.new(1 - COL_NAME - COL_POWER, -10, 0.4, 0)

		-- Rang-Index nur fuer Tests/Barrierefreiheit (Reihenfolge schwach -> stark)
		row:SetAttribute("Rank", index)
	end

	local note = addText(scroller, "Note", Loc.t("ui.mut.note"), 15, Theme.COLORS.textDim, Enum.TextXAlignment.Left)
	note.Size = UDim2.new(1, -18, 0, 64)
	note.LayoutOrder = nextOrder()
end

function MutationList.isOpen(): boolean
	return _root ~= nil and (_root :: Frame).Visible
end

function MutationList.close()
	local escape = _escape
	if escape then
		escape:Disconnect()
		_escape = nil
	end
	if _root then (_root :: Frame).Visible = false end
	if _backdrop then (_backdrop :: TextButton).Visible = false end
end

function MutationList.open()
	local root = _root
	local backdrop = _backdrop
	if not root or not backdrop then return end
	fill()
	if _scroller then (_scroller :: ScrollingFrame).CanvasPosition = Vector2.zero end
	backdrop.Visible = true
	root.Visible = true
	if _escape == nil then
		_escape = UserInputService.InputBegan:Connect(function(input: InputObject)
			if input.KeyCode == Enum.KeyCode.Escape then
				MutationList.close()
			end
		end)
	end
end

function MutationList.init(screenGui: ScreenGui)
	-- Abdunkelung hinter dem Fenster; faengt den Klick "daneben" ab.
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "MutationListBackdrop"
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.ZIndex = 18
	backdrop.Visible = false
	backdrop.Parent = screenGui
	backdrop.Activated:Connect(MutationList.close)
	_backdrop = backdrop

	local root = Theme.dialog(
		"MutationList", screenGui,
		Vector2.new(0.5, 0.5),
		Vector2.new(300, 300),
		Vector2.new(560, 440)
	)
	_root = root
	root.ZIndex = 20   -- ueber Abdunkler (18) und Honig-Menue (10), wie PetSellConfirm

	local honey = Icons.honeyWindow(root, "honey/daily_window", WIN_W, WIN_H) ~= nil

	local title = Theme.dialogHeader(root, "", MutationList.close)
	Loc.bind(title, "ui.mut.title")

	local body = Theme.dialogBody(root)
	if honey then
		Icons.honeyHeader(root, Rect.new(60, 30, 584, 77), 614, 40, 44)
		body.Position = UDim2.fromOffset(58, 100)
		body.Size = UDim2.fromOffset(544, 290)
	end

	local scroller = Theme.scroller("List", body)
	scroller.Size = UDim2.fromScale(1, 1)
	scroller.ZIndex = 21
	local layout = Theme.listLayout(scroller, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	_scroller = scroller

	Loc.onChanged(function()
		if MutationList.isOpen() then fill() end
	end)
end

return MutationList
