--!strict
-- BaerchiInventory.luau
-- StarterPlayerScripts/UI/BaerchiInventory.luau
--
-- Einzige Zustaendigkeit:
--   - Alle Baerchis des Spielers als scrollbare Liste zeigen
--   - Die Zwei-Slot-Auswahl fuer die Fusion verwalten
--   - Die zwei Reiter: "Meine Baerchis" (diese Liste) und "Index" (IndexView)
--
-- Die Liste kommt fertig sortiert aus ClientState.getBaerchiList()
-- (Rarity absteigend, dann Level) — hier wird nichts nachsortiert.
--
-- Die Fusions-Auswahl ist der einzige Zustand den dieses Modul selbst haelt.
-- Das ist erlaubt: welche zwei Zeilen gerade markiert sind, ist eine reine
-- Bedien-Information und kein Spielstand — sie steht in keinem Save und der
-- Server erfaehrt davon erst beim Bestaetigen in FusionPanel.
--
-- Neu aufgebaut wird die Liste nur wenn das Panel sichtbar ist. Kommt ein
-- Update waehrend es zu ist, wird nur ein Merker gesetzt und beim naechsten
-- Oeffnen nachgeholt — sonst baut jede Kampfrunde 25 Zeilen neu.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types            = require(ReplicatedStorage.Network.Types)
local Loc              = require(ReplicatedStorage.Localization.Loc)
local BaerchiConfig    = require(ReplicatedStorage.Config.BaerchiConfig)
local CombatCalculator = require(ReplicatedStorage.Modules.CombatCalculator)

local Theme        = require(script.Parent.Theme)
local PanelManager = require(script.Parent.PanelManager)
local ClientState  = require(script.Parent.Parent.Controllers.ClientState)
local Unlock       = require(script.Parent.Unlock)   -- HBB Paket 3
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)
local CombatRating = require(ReplicatedStorage.Modules.CombatRating)

-- HBB Paket 4: "⚔ 1,2K" statt HP/ATK in der Zeile
local function ratingText(baerchi: Types.Baerchi): string
	local value, suffix = CombatRating.short(CombatRating.of(baerchi))
	local digits = if suffix ~= "" and value < 100 then 1 else 0
	return "⚔ " .. (if digits > 0 then Loc.formatDecimal(value, digits) else Loc.formatNumber(math.floor(value))) .. suffix
end
local IndexView    = require(script.Parent.IndexView)

local BaerchiInventory = {}

local PANEL_NAME  = "Inventory"
local ROW_HEIGHT  = 48
local TOOLBAR_H   = 32
local FOOTER_H    = 64
local TAB_H       = 32

local _root: Frame?               = nil
local _title: TextLabel?          = nil
local _scroller: ScrollingFrame?  = nil
local _empty: TextLabel?          = nil
local _footer: Frame?             = nil
local _slotLabels: { TextLabel }  = {}
local _fuseButton: TextButton?    = nil
local _modeButton: TextButton?    = nil
local _hint: TextLabel?           = nil
local _listPage: Frame?           = nil
local _tabButtons: { [string]: TextButton } = {}
local _tab = "Pets"   -- "Pets" | "Index"

local _fusionMode = false
local _selection: { string } = {}
local _dirty = true

--------------------------------------------------------------------------------
-- Auswahl
--------------------------------------------------------------------------------

local function isSelected(uid: string): boolean
	return table.find(_selection, uid) ~= nil
end

local function toggleSelection(uid: string)
	local index = table.find(_selection, uid)
	if index then
		table.remove(_selection, index)
		return
	end

	-- Sammel-Update 2.8: B muss dieselbe Rarity wie A haben (der Server
	-- lehnt sonst ab, err.fuse_rarity_mismatch). Die Liste zeigt ohnehin nur
	-- passende — das hier ist das Netz fuer einen Klick waehrend eines Umbaus.
	local first = if _selection[1] then ClientState.getBaerchi(_selection[1]) else nil
	local picked = ClientState.getBaerchi(uid)
	if first and picked and first.rarity ~= picked.rarity then
		return
	end

	-- Sammel-Update 1.3: ein weiterer Klick ersetzt B, nie A — A ist der
	-- Baerchi, von dessen Karte der Spieler kam.
	if #_selection >= 2 then
		table.remove(_selection, 2)
	end
	table.insert(_selection, uid)
end

-- Sammel-Update 2.8: im Fusions-Modus mit gewaehltem A nur Baerchis
-- derselben Rarity zeigen (A selbst bleibt sichtbar, zum Abwaehlen).
local function visibleInFusion(baerchi: Types.Baerchi): boolean
	if not _fusionMode or not _selection[1] then return true end
	if isSelected(baerchi.uid) then return true end
	local first = ClientState.getBaerchi(_selection[1])
	return first == nil or first.rarity == baerchi.rarity
end

-- Sammel-Update 1.3 ("kann keinen 2. auswaehlen"): die Zeilen wurden bei JEDEM
-- Datenstand (Honig, Eier, ... mehrmals pro Sekunde) zerstoert und neu
-- gebaut. Lag ein Tipp gerade dazwischen (Finger runter, Zeile weg, Finger
-- hoch), kam Activated nie an — auf dem Handy fast jedes Mal. Jetzt bleibt
-- die Zeile samt Knopf pro uid stehen, nur der Inhalt wird erneuert.
local _rows: { [string]: Frame } = {}

-- Markierungen wegwerfen die es nicht mehr gibt (verwertet, fusioniert, Rebirth)
local function pruneSelection()
	for i = #_selection, 1, -1 do
		if not ClientState.getBaerchi(_selection[i]) then
			table.remove(_selection, i)
		end
	end
end

--------------------------------------------------------------------------------
-- Aufbau der Liste
--------------------------------------------------------------------------------

-- Zeigt die AKTUELLEN HP, nicht nur das Maximum: seit die HP zwischen
-- PIT-Laeufen stehen bleiben, ist "wer kann ueberhaupt noch kaempfen" die
-- eigentliche Frage beim Durchscrollen der Liste.
local function describeStats(baerchi: Types.Baerchi): string
	local def = BaerchiConfig.getById(baerchi.configId)
	if not def then return "" end

	local stats = CombatCalculator.getEffectiveStats(baerchi, def.baseStats)
	-- `or stats.maxHp`: ohne den Rueckfall wuerde ein Baerchi ohne currentHp
	-- (Datenpaket von einem aelteren Serverstand) hier den Aufbau der GANZEN
	-- Liste abbrechen, weil dieser Aufruf mitten in der Zeilen-Schleife steht.
	local hp    = math.clamp(baerchi.currentHp or stats.maxHp, 0, stats.maxHp)

	return string.format("HP %d/%d\nATK %d", hp, stats.maxHp, stats.atk)
end

local function buildRow(parent: Instance, order: number, baerchi: Types.Baerchi)
	local upgradeUi = FeatureFlags.isOn("UI_V2_UPGRADE_TAB")
	-- HBB Paket 4: Farbband statt zwoelf Einzelfarben
	local color = if upgradeUi then Theme.bandColor(baerchi.rarity) else Theme.rarityColor(baerchi.rarity)
	local def   = BaerchiConfig.getById(baerchi.configId)

	local data     = ClientState.get()
	local equipped = data ~= nil and data.island.equippedUid == baerchi.uid

	local uid = baerchi.uid
	local row = _rows[uid]
	local fresh = row == nil or row.Parent == nil
	if fresh then
		row = Theme.panel("Row_" .. uid, parent, Theme.COLORS.panel)
		row.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
		_rows[uid] = row :: Frame

		-- Die ganze Zeile ist der Knopf: ein durchsichtiger Button darueber.
		-- Er bleibt ueber alle Aktualisierungen bestehen (siehe _rows).
		local hit = Instance.new("TextButton")
		hit.Name                   = "Hit"
		hit.BackgroundTransparency = 1
		hit.Text                   = ""
		hit.Size                   = UDim2.fromScale(1, 1)
		hit.ZIndex                 = 3
		hit.Parent                 = row

		hit.Activated:Connect(function()
			if _fusionMode then
				toggleSelection(uid)
				BaerchiInventory.refresh()
			else
				PanelManager.open("Baerchi", uid)
			end
		end)
	end
	local frame = row :: Frame
	frame.LayoutOrder = order
	frame.Visible     = visibleInFusion(baerchi)
	for _, child in frame:GetChildren() do
		if child.Name == "Accent" or child.Name == "Name" or child.Name == "Sub" or child.Name == "Stats" then
			child:Destroy()
		end
	end
	row = frame

	-- Markierte Zeilen bekommen einen farbigen Rand statt eines eigenen Symbols
	local stroke = row:FindFirstChildOfClass("UIStroke")
	if stroke then
		local marked = _fusionMode and isSelected(uid)
		stroke.Color     = if marked then Theme.COLORS.gummy else Theme.COLORS.outline
		stroke.Thickness = if marked then Theme.OUTLINE_THICKNESS + 2 else Theme.OUTLINE_THICKNESS
	end

	local accent = Instance.new("Frame")
	accent.Name             = "Accent"
	accent.Size             = UDim2.new(0, 6, 1, -14)
	accent.Position         = UDim2.new(0, 8, 0, 7)
	-- Der ausgeruestete Baerchi (der einzige, der auf dem Plot steht und
	-- kaempfen/essen kann) hebt sich hier golden ab statt in Rarity-Farbe —
	-- das ist auf einen Blick wichtiger als die Rarity.
	accent.BackgroundColor3  = if equipped then Theme.COLORS.goldGummy else color
	accent.BorderSizePixel   = 0
	accent.Parent            = row
	Theme.corner(accent, 3)

	-- Eine Mutation ist in einer langen Liste die Information, die man auf
	-- keinen Fall uebersehen darf: die haeufigste Stufe trifft trotzdem nur
	-- 1 von 100 Baerchis. Deshalb hier gleich zweimal — als Kuerzel im Namen
	-- und als Farbe der Unterzeile (seit v11, ersetzt das binaere Inverted).
	local mutation = baerchi.mutation

	local name = Theme.label("Name", row,
		(if equipped then "\u{2605} " else "")
		.. (if mutation then BaerchiConfig.getMutationBadge(mutation) .. " " else "")
		.. Loc.name("baerchi." .. baerchi.configId .. ".name", def and def.displayName or baerchi.configId))
	name.Position = UDim2.new(0, 22, 0, 5)
	name.Size     = UDim2.new(1, -120, 0, 21)

	local sub = Theme.label("Sub", row, string.format(
		"Lv. %d  —  %s%s",
		baerchi.level,
		Loc.t("rarity." .. baerchi.rarity),
		if mutation then "  —  " .. Loc.name("mutation." .. mutation .. ".name", BaerchiConfig.getMutationDisplayName(mutation)):upper() else ""
	))
	sub.Position   = UDim2.new(0, 22, 0, 26)
	sub.Size       = UDim2.new(1, -120, 0, 16)
	sub.TextColor3 = if mutation then BaerchiConfig.getMutationColor(mutation) else color

	local stats = Theme.label("Stats", row, if upgradeUi then ratingText(baerchi) else describeStats(baerchi))
	stats.AnchorPoint    = Vector2.new(1, 0.5)
	stats.Position       = UDim2.new(1, -10, 0.5, 0)
	stats.Size           = UDim2.new(0, 84, 1, -10)
	stats.TextXAlignment = Enum.TextXAlignment.Right
	stats.TextScaled     = false
	stats.TextSize       = if upgradeUi then 20 else 13
	stats.Font           = if upgradeUi then Theme.FONT else Theme.FONT_BODY
	stats.TextColor3     = if upgradeUi then Theme.COLORS.text else Theme.COLORS.textDim
end

--------------------------------------------------------------------------------
-- Aktualisieren
--------------------------------------------------------------------------------

local function updateFooter()
	local footer = _footer
	if footer then
		footer.Visible = _fusionMode
	end

	local scroller = _scroller
	if scroller then
		local reserved = if _fusionMode then FOOTER_H + 6 else 0
		scroller.Size = UDim2.new(1, 0, 1, -(TOOLBAR_H + 6 + reserved))
	end

	for slot = 1, 2 do
		local label = _slotLabels[slot]
		if not label then continue end

		local uid = _selection[slot]
		local baerchi = if uid then ClientState.getBaerchi(uid) else nil

		if baerchi then
			local def = BaerchiConfig.getById(baerchi.configId)
			label.Text       = string.format("%s  Lv.%d", Loc.name("baerchi." .. baerchi.configId .. ".name", def and def.displayName or baerchi.configId), baerchi.level)
			label.TextColor3  = Theme.rarityColor(baerchi.rarity)
		else
			label.Text       = Loc.t("ui.fusion.slot_empty", { n = slot })
			label.TextColor3  = Theme.COLORS.textDim
		end
	end

	local fuseButton = _fuseButton
	if fuseButton then
		Theme.setEnabled(fuseButton, #_selection == 2)
	end

	local modeButton = _modeButton
	if modeButton then
		modeButton.Text = Loc.t(if _fusionMode then "ui.fusion.mode_on" else "ui.fusion.mode_off")
	end

	local hint = _hint
	if hint then
		hint.Text = if not _fusionMode
			then Loc.t("ui.inventory.hint_card")
			elseif _selection[1] then Loc.t("ui.fusion.hint_pick_b")
			else Loc.t("ui.fusion.hint_pick_a")
	end
end

function BaerchiInventory.refresh()
	local scroller = _scroller
	local root     = _root
	if not scroller or not root then return end

	if not root.Visible then
		_dirty = true
		return
	end
	_dirty = false

	pruneSelection()

	local list = ClientState.getBaerchiList()

	-- Sammel-Update 1.3: nur Zeilen entfernen, deren Baerchi es nicht mehr gibt.
	local alive: { [string]: boolean } = {}
	for _, baerchi in list do alive[baerchi.uid] = true end
	for uid, row in _rows do
		if not alive[uid] then
			row:Destroy()
			_rows[uid] = nil
		end
	end

	local title = _title
	if title then
		title.Text = Loc.t("ui.inventory.title_count", { n = #list })
	end

	local empty = _empty
	if empty then
		empty.Visible = #list == 0
	end

	for order, baerchi in list do
		buildRow(scroller, order, baerchi)
	end

	updateFooter()
end

--------------------------------------------------------------------------------
-- Oeffnen / Schliessen
--------------------------------------------------------------------------------

local function applyTab()
	-- HBB Paket 3: der Index-Reiter erscheint ab drei entdeckten Arten
	local indexTab = _tabButtons.Index
	if indexTab then
		Unlock.apply("index", indexTab)
		if not indexTab.Visible and _tab == "Index" then _tab = "Pets" end
	end

	local listPage = _listPage
	if listPage then
		listPage.Visible = _tab == "Pets"
	end
	IndexView.setVisible(_tab == "Index" and _root ~= nil and _root.Visible)

	for tab, button in _tabButtons do
		local active = tab == _tab
		button.BackgroundColor3 = if active then Theme.COLORS.accent else Theme.COLORS.panelLight
		button.TextColor3       = if active then Theme.COLORS.outline else Theme.COLORS.text
	end

	-- Sammel-Update 05.10. (Paket 7): "!" am Index-Reiter, solange eine
	-- Belohnung abholbar ist.
	local indexButton = _tabButtons.Index
	if indexButton then
		local badge = indexButton:FindFirstChild("RewardBadge")
		if badge and badge:IsA("GuiObject") then
			badge.Visible = IndexView.claimableCount() > 0
		end
	end

	if _tab == "Pets" then
		BaerchiInventory.refresh()
	end
end

local function openInternal(...: any)
	local root = _root
	if not root then return end

	-- PanelManager.open("Inventory", "Index") springt direkt in den Index
	-- (zum Beispiel aus einer Quest heraus).
	local wanted, uid = ...
	if wanted == "Index" or wanted == "Pets" then
		_tab = wanted
	elseif wanted == "Fuse" then
		-- Playtest 05.10.: Fusion von der Baerchi-Karte aus. Das Fusions-
		-- Fenster selbst hat keine Auswahl; ausgewaehlt wird hier. A ist
		-- dieser Baerchi, B tippt der Spieler in der Liste an.
		_tab = "Pets"
		_fusionMode = true
		table.clear(_selection)
		if typeof(uid) == "string" then table.insert(_selection, uid) end
	end

	root.Visible = true
	applyTab()
end

local function closeInternal()
	local root = _root
	if root then root.Visible = false end
	IndexView.setVisible(false)
end

function BaerchiInventory.show()
	PanelManager.open(PANEL_NAME)
end

--------------------------------------------------------------------------------
-- Aufbau
--------------------------------------------------------------------------------

function BaerchiInventory.init(screenGui: ScreenGui)
	local root = Theme.dialog(
		"BaerchiInventory", screenGui,
		Vector2.new(0.46, 0.66),
		Vector2.new(300, 300),
		Vector2.new(520, 580)
	)
	_root  = root
	_title = Theme.dialogHeader(root, "Baerchis", function()
		PanelManager.close(PANEL_NAME)
	end)

	local body = Theme.dialogBody(root)

	-- Reiter-Leiste: "Meine Baerchis" | "Index"
	local tabBar = Theme.container("Tabs", body)
	tabBar.Size = UDim2.new(1, 0, 0, TAB_H)
	local tabLayout = Theme.listLayout(tabBar, 8, true)
	tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left

	local function addTab(tab: string, key: string, order: number)
		local button = Theme.button("Tab_" .. tab, tabBar, "", Theme.COLORS.panelLight)
		button.Size        = UDim2.new(0, 150, 1, 0)
		button.LayoutOrder = order
		Loc.bind(button, key)
		button.Activated:Connect(function()
			if tab == "Index" then Unlock.markSeen("index") end
			_tab = tab
			applyTab()
		end)
		_tabButtons[tab] = button
	end
	addTab("Pets",  "ui.inventory.tab_pets",  1)
	addTab("Index", "ui.inventory.tab_index", 2)
	do
		local indexButton = _tabButtons.Index
		local badge = Theme.panel("RewardBadge", indexButton, Theme.COLORS.bad)
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.Position = UDim2.new(1, 4, 0, -6)
		badge.Size = UDim2.fromOffset(20, 20)
		badge.ZIndex = 4
		badge.Visible = false
		Theme.corner(badge, 10)
		local bang = Theme.label("Bang", badge, "!")
		bang.Size = UDim2.fromScale(1, 1)
		bang.TextXAlignment = Enum.TextXAlignment.Center
		bang.ZIndex = 5
	end

	-- Beide Seiten teilen sich die Flaeche unter den Reitern.
	local pages = Theme.container("Pages", body)
	pages.Position = UDim2.new(0, 0, 0, TAB_H + 8)
	pages.Size     = UDim2.new(1, 0, 1, -(TAB_H + 8))

	local listPage = Theme.container("ListPage", pages)
	listPage.Size = UDim2.fromScale(1, 1)
	_listPage = listPage

	IndexView.build(pages, root)

	-- Werkzeugleiste: Fusions-Modus an/aus
	local toolbar = Theme.container("Toolbar", listPage)
	toolbar.Size = UDim2.new(1, 0, 0, TOOLBAR_H)

	local modeButton = Theme.button("FusionMode", toolbar, Loc.t("ui.fusion.mode_off"), Theme.COLORS.gummy)
	modeButton.Size = UDim2.new(0, 130, 1, 0)
	_modeButton = modeButton

	local hint = Theme.bodyText("Hint", toolbar, Loc.t("ui.inventory.hint_card"))
	_hint = hint
	hint.Position       = UDim2.new(0, 140, 0, 0)
	hint.Size           = UDim2.new(1, -140, 1, 0)
	hint.TextYAlignment = Enum.TextYAlignment.Center

	modeButton.Activated:Connect(function()
		_fusionMode = not _fusionMode
		if not _fusionMode then
			table.clear(_selection)
		end
		BaerchiInventory.refresh()
	end)

	-- Liste
	local scroller = Theme.scroller("List", listPage)
	scroller.Position = UDim2.new(0, 0, 0, TOOLBAR_H + 6)
	scroller.Size     = UDim2.new(1, 0, 1, -(TOOLBAR_H + 6))
	_scroller = scroller

	local layout = Theme.listLayout(scroller, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left

	local empty = Theme.bodyText("Empty", listPage, Loc.t("ui.inventory.empty"))
	empty.Position = UDim2.new(0, 4, 0, TOOLBAR_H + 16)
	empty.Size     = UDim2.new(1, -8, 0, 40)
	empty.Visible  = false
	_empty = empty

	-- Fussleiste fuer die Fusions-Auswahl
	local footer = Theme.panel("FusionFooter", listPage, Theme.COLORS.panel)
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position    = UDim2.new(0, 0, 1, 0)
	footer.Size        = UDim2.new(1, -8, 0, FOOTER_H)
	footer.Visible     = false
	_footer = footer

	for slot = 1, 2 do
		local label = Theme.label("Slot" .. slot, footer, Loc.t("ui.fusion.slot_empty", { n = slot }))
		label.Position   = UDim2.new(0, 10, 0, 6 + (slot - 1) * 22)
		label.Size       = UDim2.new(1, -140, 0, 20)
		label.TextColor3  = Theme.COLORS.textDim
		_slotLabels[slot] = label
	end

	local fuseButton = Theme.button("Fuse", footer, Loc.t("ui.fusion.fuse"), Theme.COLORS.gummy)
	fuseButton.AnchorPoint = Vector2.new(1, 0.5)
	fuseButton.Position    = UDim2.new(1, -10, 0.5, 0)
	fuseButton.Size        = UDim2.new(0, 116, 0, 34)
	_fuseButton = fuseButton

	fuseButton.Activated:Connect(function()
		if #_selection < 2 then return end
		PanelManager.open("Fusion", _selection[1], _selection[2])
	end)

	PanelManager.register(PANEL_NAME, {
		open  = openInternal,
		close = closeInternal,
	})

	-- Bestandsaenderungen: sichtbar sofort nachziehen, sonst nur merken
	ClientState.onChanged(function()
		local current = _root
		local indexButton = _tabButtons.Index
		local badge = if indexButton then indexButton:FindFirstChild("RewardBadge") else nil
		if badge and badge:IsA("GuiObject") then
			badge.Visible = IndexView.claimableCount() > 0
		end
		if current and current.Visible then
			BaerchiInventory.refresh()
		else
			_dirty = true
		end
	end)

	print("[BaerchiInventory] Initialisiert")
end

return BaerchiInventory
