--!strict
-- EggTreePanel.luau
-- StarterPlayerScripts/UI/EggTreePanel.luau
--
-- v14 (Mega Egg Tree, WP5): das Ei-Baum-Fenster.
--
-- Links der Baum: 20 Knoten in Pfad-Reihen, Linien zwischen Vorgaenger und
-- Nachfolger. Freie Knoten in ihrer Ei-Farbe, gesperrte abgedunkelt mit
-- Schloss, "bereit" (alle Bedingungen erfuellt) leuchtend umrandet.
--
-- Rechts die Detail-Karte des gewaehlten Knotens: was ihm noch fehlt
-- (Fortschrittsbalken je Bedingung), was herausfaellt (Drop-Vorschau mit
-- Chancen), wie viele im Lager liegen, und drei Aktionen: Oeffnen, Pressen
-- (5 -> 1 der naechsten Stufe), Blaupause einsetzen.
--
-- Die Bedingungen rechnet Modules/EggTree — dieselbe Funktion, die der
-- Server zum Freischalten benutzt. Das Panel kann also nie etwas anderes
-- anzeigen, als der Server tut. Es aktualisiert sich live ueber ClientState.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types           = require(ReplicatedStorage.Network.Types)
local Remotes         = require(ReplicatedStorage.Network.Remotes)
local Loc             = require(ReplicatedStorage.Localization.Loc)
local EggConfig       = require(ReplicatedStorage.Config.EggConfig)
local BaerchiConfig   = require(ReplicatedStorage.Config.BaerchiConfig)
local EggTree         = require(ReplicatedStorage.Modules.EggTree)
local IndexCalculator = require(ReplicatedStorage.Modules.IndexCalculator)

local Theme          = require(script.Parent.Theme)
local EggIcon = require(script.Parent.EggIcon)
local PanelManager   = require(script.Parent.PanelManager)
local HatchAnimation = require(script.Parent.HatchAnimation)
local ClientState    = require(script.Parent.Parent.Controllers.ClientState)

local EggTreePanel = {}

local PANEL_NAME = "EggTree"
EggTreePanel.PANEL_NAME = PANEL_NAME

local NODE_W   = 112
local NODE_H   = 64
local STEP_X   = 132
local STEP_Y   = 84
local MARGIN   = 18
local DETAIL_W = 270

-- Position (Spalte, Zeile) jedes Knotens im Raster. Folgt dem Bild aus dem
-- Konzept: Stamm oben links, drei Pfade darunter, Kosmos rechts in der
-- Mitte, Ascension als eigene Reihe unten.
local LAYOUT: { [string]: { col: number, row: number } } = {
	BasicEgg         = { col = 0, row = 0 },
	SugarEgg         = { col = 1, row = 0 },
	GoldenEgg        = { col = 2, row = 1 },
	PlatinumEgg      = { col = 3, row = 1 },
	SunEgg           = { col = 4, row = 1 },
	ZenithEgg        = { col = 5, row = 1 },
	CrystalEgg       = { col = 3, row = 2 },
	PrismEgg         = { col = 4, row = 2 },
	AuroraEgg        = { col = 5, row = 2 },
	MistEgg          = { col = 2, row = 3 },
	VoidEgg          = { col = 3, row = 3 },
	ShadowEgg        = { col = 4, row = 3 },
	AbyssEgg         = { col = 5, row = 3 },
	CometEgg         = { col = 6, row = 2 },
	NovaEgg          = { col = 7, row = 2 },
	GalaxyEgg        = { col = 8, row = 2 },
	AscensionEgg     = { col = 1, row = 4.4 },
	TranscendenceEgg = { col = 2, row = 4.4 },
	EternityEgg      = { col = 3, row = 4.4 },
	OmegaEgg         = { col = 4, row = 4.4 },
}

-- Reihen-Beschriftung links (Pfad und sein Ziel).
local ROW_LABELS: { { row: number, path: string } } = {
	{ row = 0,   path = "Stamm" },
	{ row = 1,   path = "Gold" },
	{ row = 2,   path = "Kristall" },
	{ row = 3,   path = "Void" },
	{ row = 4.4, path = "Ascension" },
}

local _root: Frame?            = nil
local _canvas: ScrollingFrame? = nil
local _detail: ScrollingFrame? = nil
local _header: TextLabel?      = nil
local _selected: Types.EggType = "BasicEgg"
local _nodes: { [string]: { frame: Frame, stroke: UIStroke, lock: TextLabel, count: TextLabel, name: TextLabel } } = {}

local function nodeCenter(eggId: string): Vector2
	local p = LAYOUT[eggId]
	return Vector2.new(MARGIN + 70 + p.col * STEP_X + NODE_W / 2, MARGIN + p.row * STEP_Y + NODE_H / 2)
end

local function eggName(eggId: string): string
	local def = EggConfig.data[eggId :: Types.EggType]
	return Loc.name("egg." .. eggId .. ".name", def and def.displayName or eggId)
end

local function rarityName(rarity: string): string
	return Loc.name("rarity." .. rarity, rarity)
end

--------------------------------------------------------------------------------
-- Linien
--------------------------------------------------------------------------------

local function line(parent: Instance, a: Vector2, b: Vector2, color: Color3, thickness: number)
	local d = b - a
	local len = d.Magnitude
	local f = Instance.new("Frame")
	f.Name = "Edge"
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
	f.Size = UDim2.fromOffset(len, thickness)
	f.Rotation = math.deg(math.atan2(d.Y, d.X))
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.ZIndex = 11
	f.Parent = parent
end

--------------------------------------------------------------------------------
-- Baum aufbauen (einmalig)
--------------------------------------------------------------------------------

local function buildTree(canvas: ScrollingFrame)
	local maxCol, maxRow = 0, 0
	for _, p in LAYOUT do
		maxCol = math.max(maxCol, p.col)
		maxRow = math.max(maxRow, p.row)
	end
	canvas.CanvasSize = UDim2.fromOffset(MARGIN * 2 + 70 + (maxCol + 1) * STEP_X, MARGIN * 2 + (maxRow + 1) * STEP_Y)

	for _, rl in ROW_LABELS do
		local label = Theme.label("Row_" .. rl.path, canvas, Loc.name("path." .. rl.path, rl.path))
		label.Position = UDim2.fromOffset(4, MARGIN + rl.row * STEP_Y + 8)
		label.Size = UDim2.fromOffset(74, 22)
		label.TextColor3 = BaerchiConfig.getPathColor(rl.path)
		label.ZIndex = 12
		local goal = Theme.bodyText("Goal", canvas, Loc.name("path." .. rl.path .. ".goal", ""))
		goal.Position = UDim2.fromOffset(4, MARGIN + rl.row * STEP_Y + 30)
		goal.Size = UDim2.fromOffset(74, 32)
		goal.TextSize = 11
		goal.ZIndex = 12
	end

	-- Kanten zuerst (liegen unter den Knoten).
	for eggId, def in EggConfig.data do
		if def.parent and LAYOUT[def.parent] then
			line(canvas, nodeCenter(def.parent), nodeCenter(eggId), Theme.COLORS.panelLight, 3)
		end
	end
	local comet = EggConfig.TREE.CometEgg
	if comet and comet.hatchAnyOf then
		for _, req in comet.hatchAnyOf.of do
			line(canvas, nodeCenter(req.egg), nodeCenter("CometEgg"), BaerchiConfig.getPathColor("Kosmos"), 2)
		end
	end

	for eggId, def in EggConfig.data do
		-- Sonder-Eier (EggConfig: special) haben keinen Platz im Baum.
		if not LAYOUT[eggId] then continue end
		local c = nodeCenter(eggId)
		local frame = Theme.panel("Node_" .. eggId, canvas, Theme.COLORS.panel)
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromOffset(c.X, c.Y)
		frame.Size = UDim2.fromOffset(NODE_W, NODE_H)
		frame.ZIndex = 13
		local stroke = frame:FindFirstChildOfClass("UIStroke") :: UIStroke

		local swatch = EggIcon.make(frame, eggId, 38, 14)
		swatch.AnchorPoint = Vector2.new(0, 0.5)
		swatch.Position = UDim2.new(0, 6, 0.5, 0)

		local name = Theme.label("Name", frame, eggName(eggId))
		name.Position = UDim2.fromOffset(42, 6)
		name.Size = UDim2.new(1, -46, 0, 22)
		name.ZIndex = 14

		local count = Theme.label("Count", frame, "")
		count.Position = UDim2.fromOffset(42, 32)
		count.Size = UDim2.new(1, -46, 0, 20)
		count.TextColor3 = Theme.COLORS.good
		count.ZIndex = 14

		local lock = Theme.label("Lock", frame, "")
		lock.AnchorPoint = Vector2.new(1, 0)
		lock.Position = UDim2.new(1, -4, 0, 2)
		lock.Size = UDim2.fromOffset(40, 16)
		lock.TextXAlignment = Enum.TextXAlignment.Right
		lock.TextColor3 = Theme.COLORS.textDim
		lock.ZIndex = 15

		local click = Instance.new("TextButton")
		click.Name = "Click"
		click.BackgroundTransparency = 1
		click.Text = ""
		click.Size = UDim2.fromScale(1, 1)
		click.ZIndex = 16
		click.Parent = frame
		click.Activated:Connect(function()
			_selected = eggId
			EggTreePanel.refresh()
		end)

		_nodes[eggId] = { frame = frame, stroke = stroke, lock = lock, count = count, name = name }
	end
end

--------------------------------------------------------------------------------
-- Detail-Karte
--------------------------------------------------------------------------------

local function conditionText(c: EggTree.Condition): string
	if c.kind == "hatch" then
		return Loc.t("ui.tree.cond_hatch", { egg = eggName(c.egg :: string), have = c.have, need = c.need })
	elseif c.kind == "hatchAny" then
		return Loc.t("ui.tree.cond_any", { have = c.have, need = c.need })
	elseif c.kind == "index" then
		return Loc.t("ui.tree.cond_index", { rarity = rarityName(c.rarity :: string), have = c.have, need = c.need })
	elseif c.kind == "rebirth" then
		return Loc.t("ui.tree.cond_rebirth", { have = c.have, need = c.need })
	elseif c.kind == "blueprint" then
		return Loc.t("ui.tree.cond_blueprint")
	end
	return c.kind
end

local function addRow(parent: Instance, order: number, height: number): Frame
	local row = Theme.container("Row" .. order, parent)
	row.Size = UDim2.new(1, -8, 0, height)
	row.LayoutOrder = order
	return row
end

local function buildDetail(detail: ScrollingFrame, data: Types.PlayerDataUpdate)
	for _, child in detail:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end

	local eggId = _selected
	local def = EggConfig.data[eggId]
	if not def then return end
	local progress = EggTree.getProgress(data, eggId)
	local stock = data.island.eggStock[eggId] or 0
	local order = 0
	local function nextOrder(): number order += 1 return order end

	local title = Theme.label("Title", addRow(detail, nextOrder(), 28), eggName(eggId))
	title.Size = UDim2.fromScale(1, 1)
	title.TextColor3 = def.color
	Theme.outlineText(title)

	local sub = Theme.bodyText("Sub", addRow(detail, nextOrder(), 36), Loc.t("ui.tree.path_line", {
		path = Loc.name("path." .. def.path, def.path),
		goal = Loc.name("path." .. def.path .. ".goal", ""),
		avg  = Loc.formatDecimal(EggTree.expectedRarity(eggId), 2),
	}))
	sub.Size = UDim2.fromScale(1, 1)

	local status = Theme.label("Status", addRow(detail, nextOrder(), 22),
		if progress.unlocked then Loc.t("ui.tree.unlocked")
		elseif progress.ready then Loc.t("ui.tree.ready")
		else Loc.t("ui.tree.locked"))
	status.Size = UDim2.fromScale(1, 1)
	status.TextColor3 = if progress.unlocked then Theme.COLORS.good else Theme.COLORS.goldGummy

	-- Bedingungen
	if not progress.unlocked and #progress.conditions > 0 then
		Theme.sectionLabel("CondHead", addRow(detail, nextOrder(), 16), Loc.t("ui.tree.needs")).Size = UDim2.fromScale(1, 1)
		for _, c in progress.conditions do
			local row = addRow(detail, nextOrder(), 26)
			local bar = Theme.progress(row, if c.done then Theme.COLORS.good else Theme.COLORS.accent)
			bar.track.Size = UDim2.fromScale(1, 1)
			bar.fill.Size = UDim2.fromScale(math.clamp(c.have / math.max(1, c.need), 0, 1), 1)
			bar.text.Text = conditionText(c)
			if c.parts then
				for _, part in c.parts do
					local prow = addRow(detail, nextOrder(), 20)
					local pl = Theme.bodyText("Part", prow, string.format("   %s %s  %d/%d",
						if part.done then "✓" else "·", eggName(part.egg), part.have, part.need))
					pl.Size = UDim2.fromScale(1, 1)
					pl.TextSize = 12
				end
			end
		end
	end

	-- Lager + Aktionen
	local stockRow = addRow(detail, nextOrder(), 22)
	local stockLabel = Theme.label("Stock", stockRow, Loc.t("ui.tree.in_stock", { n = stock }))
	stockLabel.Size = UDim2.fromScale(1, 1)
	stockLabel.TextColor3 = if stock > 0 then Theme.COLORS.good else Theme.COLORS.textDim

	local openRow = addRow(detail, nextOrder(), 34)
	local openBtn = Theme.bigButton("Open", openRow, Loc.t("ui.tree.open"), Theme.COLORS.accent)
	openBtn.Size = UDim2.fromScale(1, 1)
	Theme.setEnabled(openBtn, stock > 0)
	openBtn.Activated:Connect(function()
		local now = ClientState.get()
		if not now or (now.island.eggStock[eggId] or 0) <= 0 then return end
		HatchAnimation.request(eggId)
		Remotes.RequestHatchEgg:FireServer(eggId)
	end)

	-- Presse: beim Zucker-Ei zwei Wege (Gold / Void)
	if not EggConfig.PRESS.blockedPaths[def.path] then
		local targets: { { path: string?, egg: Types.EggType } } = {}
		if eggId == "SugarEgg" then
			for _, path in { "Gold", "Void" } do
				local t = EggConfig.getNextInPath(eggId, path :: any)
				if t then table.insert(targets, { path = path, egg = t }) end
			end
		else
			local t = EggConfig.getNextInPath(eggId)
			if t then table.insert(targets, { path = nil, egg = t }) end
		end
		for _, target in targets do
			local row = addRow(detail, nextOrder(), 32)
			local free = EggTree.isUnlocked(data.eggTree, target.egg)
			local btn = Theme.button("Press", row, Loc.t("ui.tree.press", {
				n = EggConfig.PRESS.cost, egg = eggName(target.egg),
			}), Theme.COLORS.goldGummy)
			btn.Size = UDim2.fromScale(1, 1)
			Theme.setEnabled(btn, free and stock >= EggConfig.PRESS.cost)
			btn.Activated:Connect(function()
				Remotes.RequestPressEggs:FireServer(eggId, target.path)
			end)
		end
	end

	-- Blaupause
	if EggTree.canUseBlueprint(data, eggId) then
		local row = addRow(detail, nextOrder(), 32)
		local btn = Theme.button("Blueprint", row, Loc.t("ui.tree.use_blueprint", { n = data.eggTree.blueprints }),
			BaerchiConfig.getPathColor("Kosmos"))
		btn.TextColor3 = Theme.COLORS.text
		btn.Size = UDim2.fromScale(1, 1)
		btn.Activated:Connect(function()
			Remotes.RequestUseBlueprint:FireServer(eggId)
		end)
	end

	-- Drop-Vorschau
	Theme.sectionLabel("DropHead", addRow(detail, nextOrder(), 16), Loc.t("ui.tree.drops")).Size = UDim2.fromScale(1, 1)
	for _, node in IndexCalculator.buildTree() do
		if node.eggId == eggId then
			for _, drop in node.drops do
				local bdef = BaerchiConfig.getById(drop.configId)
				if bdef then
					local row = addRow(detail, nextOrder(), 20)
					local known = data.discovered and data.discovered[drop.configId]
					local name = if known then Loc.name("baerchi." .. drop.configId .. ".name", bdef.displayName) else "???"
					local pct = drop.chance * 100
					local pctText = if pct >= 10 then Loc.formatNumber(math.round(pct)) .. "%" else Loc.formatDecimal(pct, 1) .. "%"
					local l = Theme.bodyText("Drop", row, string.format("%s  •  %s  •  %s", pctText, name, rarityName(bdef.rarity)))
					l.Size = UDim2.fromScale(1, 1)
					l.TextSize = 12
					l.TextColor3 = BaerchiConfig.getRarityColor(bdef.rarity)
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Aktualisieren
--------------------------------------------------------------------------------

function EggTreePanel.refresh()
	local root = _root
	if not root or not root.Visible then return end
	local data = ClientState.get()
	if not data or not data.eggTree then return end

	if _header then
		_header.Text = Loc.t("ui.tree.title_bp", { n = data.eggTree.blueprints or 0 })
	end

	for eggId, node in _nodes do
		local progress = EggTree.getProgress(data, eggId :: Types.EggType)
		local def = EggConfig.data[eggId :: Types.EggType]
		local stock = data.island.eggStock[eggId :: Types.EggType] or 0
		node.count.Text = if stock > 0 then "x" .. stock else ""
		node.name.Text = eggName(eggId)
		if progress.unlocked then
			node.frame.BackgroundColor3 = Theme.shade(def.color, -0.55)
			node.lock.Text = ""
			node.stroke.Color = Theme.COLORS.outline
			node.stroke.Thickness = 2
		else
			node.frame.BackgroundColor3 = Theme.COLORS.panelDeep
			node.lock.Text = if progress.ready then "!" else Loc.t("ui.tree.lock_short")
			node.stroke.Color = if progress.ready then Theme.COLORS.goldGummy else Theme.COLORS.outline
			node.stroke.Thickness = if progress.ready then 3 else 2
		end
		if eggId == _selected then
			node.stroke.Color = Theme.COLORS.text
			node.stroke.Thickness = 3
		end
	end

	if _detail then
		buildDetail(_detail, data)
	end
end

local function openInternal(eggId: any)
	local root = _root
	if not root then return end
	if typeof(eggId) == "string" and EggConfig.data[eggId :: Types.EggType] then
		_selected = eggId :: Types.EggType
	end
	root.Visible = true
	EggTreePanel.refresh()
end

local function closeInternal()
	if _root then _root.Visible = false end
end

function EggTreePanel.init(screenGui: ScreenGui)
	local root = Theme.dialog("EggTreePanel", screenGui, Vector2.new(0.9, 0.84), Vector2.new(560, 360), Vector2.new(1240, 720))
	_root = root

	_header = Theme.dialogHeader(root, Loc.t("ui.tree.title"), function()
		PanelManager.close(PANEL_NAME)
	end)

	local body = Theme.dialogBody(root)

	local canvas = Instance.new("ScrollingFrame")
	canvas.Name = "Canvas"
	canvas.BackgroundTransparency = 1
	canvas.BorderSizePixel = 0
	canvas.ScrollBarThickness = 6
	canvas.ScrollBarImageColor3 = Theme.COLORS.panelLight
	canvas.ScrollingDirection = Enum.ScrollingDirection.XY
	canvas.Size = UDim2.new(1, -DETAIL_W - 10, 1, 0)
	canvas.ZIndex = 10
	canvas.Parent = body
	_canvas = canvas

	local detailHost = Theme.panel("Detail", body, Theme.COLORS.panel)
	detailHost.AnchorPoint = Vector2.new(1, 0)
	detailHost.Position = UDim2.new(1, 0, 0, 0)
	detailHost.Size = UDim2.new(0, DETAIL_W, 1, 0)
	detailHost.ZIndex = 10
	local detail = Theme.scroller("List", detailHost)
	detail.Position = UDim2.fromOffset(8, 8)
	detail.Size = UDim2.new(1, -12, 1, -16)
	detail.ZIndex = 11
	local layout = Theme.listLayout(detail, 4)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	_detail = detail

	buildTree(canvas)

	PanelManager.register(PANEL_NAME, { open = openInternal, close = closeInternal })

	ClientState.onChanged(function()
		EggTreePanel.refresh()
	end)
	Loc.onChanged(function()
		if _header then _header.Text = Loc.t("ui.tree.title") end
		EggTreePanel.refresh()
	end)

	print("[EggTreePanel] Initialisiert |", #EggConfig.getOrderedIds(), "Knoten")
end

return EggTreePanel
