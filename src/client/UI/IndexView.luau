--!strict
-- IndexView.luau
-- StarterPlayerScripts/UI/IndexView.luau
--
-- Einzige Zustaendigkeit:
--   - Den Index zeichnen: pro Ei eine Reihe Baerchis mit Wahrscheinlichkeit,
--     entdeckte in Farbe, unentdeckte als schwarze Silhouette
--   - Das kleine Fenster mit den Eiern, aus denen ein Baerchi faellt
--     (PC: Maus drueberhalten, Handy: antippen)
--
-- Zweck ist Orientierung: wer eine schwarze Silhouette sieht, tippt sie an und
-- weiss sofort, WELCHES Ei er oeffnen muss. Der Index liest nur — er schaltet
-- nichts frei. Entdeckt ist ein Baerchi, sobald der Server ihn in
-- data.discovered vermerkt hat (QuestService).
--
-- Die Daten (welche Eier, welche Chancen) kommen komplett aus
-- IndexCalculator/EggConfig; dieses Modul kennt keine einzige Baerchi-id.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types           = require(ReplicatedStorage.Network.Types)
local Loc             = require(ReplicatedStorage.Localization.Loc)
local Names           = require(ReplicatedStorage.Localization.Names)
local EggConfig       = require(ReplicatedStorage.Config.EggConfig)
local BaerchiConfig   = require(ReplicatedStorage.Config.BaerchiConfig)
local IndexCalculator = require(ReplicatedStorage.Modules.IndexCalculator)
local BaerchiMesh     = require(ReplicatedStorage.Modules.BaerchiMesh)

local Theme       = require(script.Parent.Theme)
local UiScale     = require(script.Parent.UiScale)
local ClientState = require(script.Parent.Parent.Controllers.ClientState)

local IndexView = {}

local TILE_W   = 78
local TILE_H   = 104
local VIEW     = 62
local POP_W    = 210

local _page: Frame?        = nil
local _scroller: ScrollingFrame? = nil
local _summary: TextLabel? = nil
local _popup: Frame?       = nil
local _popupHost: Frame?   = nil

-- Antippen haelt das Fenster fest (Handy); Hover zeigt es nur solange die Maus
-- drauf ist.
local _pinnedId: string? = nil
local _shownId: string?  = nil
local _signature = ""

--------------------------------------------------------------------------------
-- Hilfen
--------------------------------------------------------------------------------

local function percent(chance: number): string
	local p = chance * 100
	if math.abs(p - math.round(p)) < 0.05 then
		return Loc.formatNumber(math.round(p)) .. "%"
	end
	return Loc.formatDecimal(p, 1) .. "%"
end

local function isDiscovered(configId: string): boolean
	local data = ClientState.get()
	return data ~= nil and data.discovered ~= nil and data.discovered[configId] == true
end

-- Macht aus einem gebauten Baerchi eine schwarze Silhouette.
local function blacken(model: Model)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Color    = Color3.new(0.04, 0.04, 0.06)
			d.Material = Enum.Material.SmoothPlastic
			if d:IsA("MeshPart") then
				d.TextureID = ""
			end
		elseif d:IsA("Decal") or d:IsA("Texture") or d:IsA("SurfaceAppearance") then
			d:Destroy()
		end
	end
end

-- Zeigt einen Baerchi in einem ViewportFrame. Gibt false zurueck, wenn kein
-- Modell gebaut werden konnte (fehlendes Template) — der Aufrufer zeigt dann
-- ein Fragezeichen.
local function fillViewport(vp: ViewportFrame, configId: string, discovered: boolean): boolean
	local def = BaerchiConfig.getById(configId)
	if not def then return false end

	local ok, model = pcall(function()
		return BaerchiMesh.build(Vector3.zero, Theme.rarityColor(def.rarity), def.rarity, nil)
	end)
	if not ok or not model then return false end

	if not discovered then
		blacken(model)
	end
	model.Parent = vp

	local cf, size = model:GetBoundingBox()
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	local radius = math.max(size.X, size.Y, size.Z)
	local distance = radius / (2 * math.tan(math.rad(camera.FieldOfView / 2))) * 1.15
	-- Leicht von vorne-oben, damit man Gesicht und Koerper sieht.
	local dir = Vector3.new(0.35, 0.25, 1).Unit
	camera.CFrame = CFrame.lookAt(cf.Position + dir * distance, cf.Position)
	camera.Parent = vp
	vp.CurrentCamera = camera
	return true
end

--------------------------------------------------------------------------------
-- Das Fenster "faellt aus diesen Eiern"
--------------------------------------------------------------------------------

local function hidePopup()
	local popup = _popup
	if popup then popup.Visible = false end
	_shownId = nil
end

local function showPopup(configId: string, anchor: GuiObject)
	local popup, host = _popup, _popupHost
	if not popup or not host then return end

	local def = BaerchiConfig.getById(configId)
	if not def then return end

	for _, child in popup:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end

	local found = isDiscovered(configId)
	local color = Theme.rarityColor(def.rarity)

	local title = Theme.label("Title", popup,
		if found then Names.baerchi(configId) else Loc.t("ui.index.unknown"))
	title.Position = UDim2.new(0, 10, 0, 6)
	title.Size     = UDim2.new(1, -20, 0, 22)

	local rarity = Theme.label("Rarity", popup, Loc.name("rarity." .. def.rarity, def.rarity))
	rarity.Position   = UDim2.new(0, 10, 0, 28)
	rarity.Size       = UDim2.new(1, -20, 0, 16)
	rarity.TextColor3 = color

	local header = Theme.bodyText("DropsFrom", popup, Loc.t("ui.index.drops_from"))
	header.Position = UDim2.new(0, 10, 0, 50)
	header.Size     = UDim2.new(1, -20, 0, 16)

	local data   = ClientState.get()
	local sources = IndexCalculator.sourcesOf(configId)
	local y = 68

	for _, source in sources do
		local eggDef = EggConfig.data[source.eggId :: Types.EggType]
		local row = Theme.container("Src_" .. source.eggId, popup)
		row.Position = UDim2.new(0, 10, 0, y)
		row.Size     = UDim2.new(1, -20, 0, 22)

		local dot = Theme.panel("Dot", row, if eggDef then eggDef.color else Theme.COLORS.accent)
		dot.Position = UDim2.new(0, 0, 0.5, -7)
		dot.Size     = UDim2.new(0, 14, 0, 14)
		Theme.corner(dot, 7)

		local name = Theme.label("Name", row, Loc.name("egg." .. source.eggId .. ".name", source.eggId))
		name.Position = UDim2.new(0, 22, 0, 0)
		name.Size     = UDim2.new(1, -90, 1, 0)
		name.TextSize = 14

		local chance = Theme.label("Chance", row, percent(source.chance))
		chance.AnchorPoint    = Vector2.new(1, 0)
		chance.Position       = UDim2.new(1, 0, 0, 0)
		chance.Size           = UDim2.new(0, 64, 1, 0)
		chance.TextXAlignment = Enum.TextXAlignment.Right
		chance.TextColor3     = Theme.COLORS.goldGummy

		y += 22

		-- Hat der Spieler dieses Ei gerade im Lager? Dann ist das der
		-- naechste Schritt, und genau den soll das Fenster zeigen.
		local stock = if data then (data.island.eggStock :: any)[source.eggId] or 0 else 0
		if stock > 0 then
			local have = Theme.bodyText("Have", popup, Loc.t("ui.index.you_have", { n = stock }))
			have.Position   = UDim2.new(0, 32, 0, y - 4)
			have.Size       = UDim2.new(1, -42, 0, 14)
			have.TextSize   = 12
			have.TextColor3 = Theme.COLORS.good
			y += 14
		end
	end

	if #sources == 0 then
		local none = Theme.bodyText("None", popup, Loc.t("ui.index.no_source"))
		none.Position = UDim2.new(0, 10, 0, y)
		none.Size     = UDim2.new(1, -20, 0, 30)
		y += 30
	end

	popup.Size = UDim2.new(0, POP_W, 0, y + 10)

	-- Neben die Kachel setzen und im Dialog halten.
	-- Bildschirm-Pixel -> Oberflaechen-Einheiten (globale UiScale), dann in die
	-- Einheiten INNERHALB des Dialogs (Theme.dialogScale: auf kleinen
	-- Bildschirmen ist der ganze Dialog verkleinert).
	local inner    = math.max(Theme.dialogScale(host), 0.01)
	local hostPos  = UiScale.toGui(host.AbsolutePosition) / inner
	local hostSize = UiScale.toGui(host.AbsoluteSize) / inner
	local aPos, aSize = UiScale.toGui(anchor.AbsolutePosition) / inner, UiScale.toGui(anchor.AbsoluteSize) / inner

	local x = aPos.X - hostPos.X + aSize.X + 6
	if x + POP_W > hostSize.X then
		x = aPos.X - hostPos.X - POP_W - 6
	end
	x = math.clamp(x, 4, math.max(4, hostSize.X - POP_W - 4))
	local py = math.clamp(aPos.Y - hostPos.Y, 4, math.max(4, hostSize.Y - (y + 10) - 4))

	popup.Position = UDim2.new(0, x, 0, py)
	popup.Visible  = true
	_shownId = configId
end

--------------------------------------------------------------------------------
-- Eine Kachel
--------------------------------------------------------------------------------

local function buildTile(parent: Instance, order: number, drop: IndexCalculator.Drop)
	local def = BaerchiConfig.getById(drop.configId)
	if not def then return end

	local found = isDiscovered(drop.configId)
	local color = Theme.rarityColor(def.rarity)

	local tile = Theme.panel("Tile_" .. drop.configId, parent, Theme.COLORS.panel)
	tile.LayoutOrder = order

	local stroke = tile:FindFirstChildOfClass("UIStroke")
	if stroke and found then stroke.Color = color end

	local vp = Instance.new("ViewportFrame")
	vp.Name                   = "Preview"
	vp.BackgroundColor3       = if found then Theme.shade(color, -0.55) else Color3.fromRGB(70, 66, 92)
	vp.BackgroundTransparency = 0
	vp.BorderSizePixel        = 0
	vp.Ambient                = Color3.fromRGB(180, 180, 190)
	vp.LightColor             = Color3.fromRGB(255, 255, 255)
	vp.AnchorPoint            = Vector2.new(0.5, 0)
	vp.Position               = UDim2.new(0.5, 0, 0, 5)
	vp.Size                   = UDim2.new(0, VIEW, 0, VIEW)
	vp.Parent                 = tile
	Theme.corner(vp, 10)

	if not fillViewport(vp, drop.configId, found) then
		local q = Theme.label("Q", vp, if found then "B" else "?")
		q.Size           = UDim2.fromScale(1, 1)
		q.TextXAlignment = Enum.TextXAlignment.Center
		q.TextColor3     = if found then color else Theme.COLORS.textDim
	end

	local name = Theme.label("Name", tile,
		if found then Names.baerchi(drop.configId) else Loc.t("ui.index.unknown"))
	name.Position       = UDim2.new(0, 3, 0, VIEW + 7)
	name.Size           = UDim2.new(1, -6, 0, 14)
	name.TextXAlignment = Enum.TextXAlignment.Center
	name.TextColor3     = if found then Theme.COLORS.text else Theme.COLORS.textDim

	local chance = Theme.label("Chance", tile, percent(drop.chance))
	chance.Position       = UDim2.new(0, 3, 0, VIEW + 22)
	chance.Size           = UDim2.new(1, -6, 0, 14)
	chance.TextXAlignment = Enum.TextXAlignment.Center
	chance.TextColor3     = Theme.COLORS.goldGummy

	local hit = Instance.new("TextButton")
	hit.Name                   = "Hit"
	hit.BackgroundTransparency = 1
	hit.Text                   = ""
	hit.Size                   = UDim2.fromScale(1, 1)
	hit.ZIndex                 = 5
	hit.Parent                 = tile

	-- Maus: Hover zeigt, Verlassen versteckt (ausser angetippt).
	hit.MouseEnter:Connect(function()
		if _pinnedId == nil then
			showPopup(drop.configId, tile)
		end
	end)
	hit.MouseLeave:Connect(function()
		if _pinnedId == nil and _shownId == drop.configId then
			hidePopup()
		end
	end)
	-- Handy (und Mausklick): antippen haelt fest, nochmal antippen schliesst.
	hit.Activated:Connect(function()
		if _pinnedId == drop.configId then
			_pinnedId = nil
			hidePopup()
		else
			_pinnedId = drop.configId
			showPopup(drop.configId, tile)
		end
	end)
end

--------------------------------------------------------------------------------
-- Aufbau / Aktualisieren
--------------------------------------------------------------------------------

local function currentSignature(): string
	local data = ClientState.get()
	local keys: { string } = {}
	if data and data.discovered then
		for id in data.discovered do table.insert(keys, id) end
	end
	table.sort(keys)
	return table.concat(keys, ",") .. "|" .. Loc.getLanguage()
end

function IndexView.refresh(force: boolean?)
	local scroller, page = _scroller, _page
	if not scroller or not page or not page.Visible then return end

	local signature = currentSignature()
	if not force and signature == _signature then return end
	_signature = signature

	hidePopup()
	_pinnedId = nil

	for _, child in scroller:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end

	local tree  = IndexCalculator.buildTree()
	local total = #IndexCalculator.allPets()
	local found = 0
	for _, configId in IndexCalculator.allPets() do
		if isDiscovered(configId) then found += 1 end
	end

	local summary = _summary
	if summary then
		summary.Text = Loc.t("ui.index.progress", { found = found, total = total })
	end

	for order, node in tree do
		local eggDef = EggConfig.data[node.eggId :: Types.EggType]

		local section = Theme.container("Egg_" .. node.eggId, scroller)
		section.LayoutOrder   = order
		section.Size          = UDim2.new(1, -8, 0, 0)
		section.AutomaticSize = Enum.AutomaticSize.Y
		local sl = Theme.listLayout(section, 4)
		sl.HorizontalAlignment = Enum.HorizontalAlignment.Left

		local head = Theme.container("Head", section)
		head.LayoutOrder = 1
		head.Size        = UDim2.new(1, 0, 0, 24)

		local dot = Theme.panel("Dot", head, if eggDef then eggDef.color else Theme.COLORS.accent)
		dot.Position = UDim2.new(0, 2, 0.5, -9)
		dot.Size     = UDim2.new(0, 18, 0, 18)
		Theme.corner(dot, 9)

		local sectionFound = 0
		for _, drop in node.drops do
			if isDiscovered(drop.configId) then sectionFound += 1 end
		end

		local title = Theme.label("Title", head,
			Loc.name("egg." .. node.eggId .. ".name", node.eggId)
			.. "  (" .. sectionFound .. "/" .. #node.drops .. ")")
		title.Position = UDim2.new(0, 28, 0, 0)
		title.Size     = UDim2.new(1, -30, 1, 0)

		local grid = Theme.container("Grid", section)
		grid.LayoutOrder   = 2
		grid.Size          = UDim2.new(1, 0, 0, 0)
		grid.AutomaticSize = Enum.AutomaticSize.Y

		local layout = Instance.new("UIGridLayout")
		layout.CellSize            = UDim2.new(0, TILE_W, 0, TILE_H)
		layout.CellPadding         = UDim2.new(0, 6, 0, 6)
		layout.SortOrder           = Enum.SortOrder.LayoutOrder
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
		layout.Parent              = grid

		for i, drop in node.drops do
			buildTile(grid, i, drop)
		end
	end
end

-- Fuer BaerchiInventory: Seite zeigen/verstecken.
function IndexView.setVisible(visible: boolean)
	local page = _page
	if not page then return end
	page.Visible = visible
	if visible then
		IndexView.refresh(true)
	else
		hidePopup()
		_pinnedId = nil
	end
end

-- `host` ist der Dialog, in dem das Fenster liegen darf (damit es nicht vom
-- Scroller abgeschnitten wird); `parent` ist die Flaeche fuer die Seite.
function IndexView.build(parent: Instance, host: Frame): Frame
	local page = Theme.container("IndexPage", parent)
	page.Size    = UDim2.fromScale(1, 1)
	page.Visible = false
	_page = page

	local summary = Theme.label("Summary", page, "")
	summary.Size    = UDim2.new(1, 0, 0, 22)
	summary.TextSize = 16
	_summary = summary

	local scroller = Theme.scroller("IndexList", page)
	scroller.Position = UDim2.new(0, 0, 0, 28)
	scroller.Size     = UDim2.new(1, 0, 1, -28)
	_scroller = scroller

	local layout = Theme.listLayout(scroller, 10)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left

	-- Das Fenster haengt am Dialog, ganz oben.
	local popup = Theme.panel("DropPopup", host, Theme.COLORS.panelDeep)
	popup.Visible = false
	popup.ZIndex  = 50
	popup.Active  = false
	_popup     = popup
	_popupHost = host

	ClientState.onChanged(function()
		IndexView.refresh(false)
	end)
	Loc.onChanged(function()
		IndexView.refresh(true)
	end)

	return page
end

return IndexView
