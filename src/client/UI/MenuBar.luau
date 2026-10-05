--!strict
-- MenuBar.luau
-- StarterPlayerScripts/UI/MenuBar.luau
--
-- Einzige Zustaendigkeit:
--   - Die schmale Kachelleiste am rechten Bildschirmrand: Eier und Baerchis
--
-- ============================================================
-- WARUM NUR ZWEI KACHELN
-- ============================================================
-- Vorher standen hier sieben Kacheln (Eier, Baerchis, Kampf, drei Gebaeude,
-- Arena). Fuer einen neuen Spieler war das eine Wand aus Knoepfen ohne Antwort
-- auf "was mache ich jetzt?". Drei Dinge sind weggefallen:
--   - Gebaeude und Arena: Man oeffnet sie, indem man am Gebaeude selbst den
--     Prompt benutzt (WorldController). Eine zweite Tuer dorthin ist ueberfluessig.
--   - Kampf: Die PetBar unten ist der bessere Kampf-Knopf.
-- Uebrig bleiben die zwei Dinge, die man von ueberall aus braucht: Eier
-- (zum Schluepfen) und Baerchis (Sammlung, Fusion und der Index).
--
-- Welches Panel offen ist, weiss weiterhin ausschliesslich der PanelManager.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types            = require(ReplicatedStorage.Network.Types)
local Loc              = require(ReplicatedStorage.Localization.Loc)
local IncubatorRules   = require(ReplicatedStorage.Modules.IncubatorRules)   -- Sammel-Update 8
local IndexRewardConfig = require(ReplicatedStorage.Config.IndexRewardConfig) -- Sammel-Update 7
local BuildingBehavior  = require(ReplicatedStorage.Config.BuildingBehavior)
local FeatureFlags     = require(ReplicatedStorage.Config.FeatureFlags)
local Workspace        = game:GetService("Workspace")

local Theme        = require(script.Parent.Theme)
local UiScale      = require(script.Parent.UiScale)
local PanelManager = require(script.Parent.PanelManager)
local Icons        = require(script.Parent.Icons)
local ClientState  = require(script.Parent.Parent.Controllers.ClientState)
local Unlock       = require(script.Parent.Unlock)

-- HBB Paket 3: Kachel (Panel-Name) → Element-Id der Freischaltung
local TILE_ELEMENT: { [string]: string } = {
	Hatch = "tile_eggs", Inventory = "tile_bears", EggTree = "tile_tree",
	Leaderboard = "tile_leaderboard", DailyBonus = "tile_daily",
	Shop = "tile_shop",
	Incubator = "tile_incubator",   -- Sammel-Update Paket 8
}

local MenuBar = {}

-- Groessen. TILE ist gleichzeitig die Antippflaeche — darunter wird es auf dem
-- Handy zur Geduldsprobe.
local TILE   = 54
local LABEL  = 16
local GAP    = 6
local WIDTH  = 76

-- Was eine Kachel anzeigt: `value` ist die Beschriftung IN der Kachel,
-- `alert` laesst das rote Ausrufezeichen erscheinen.
type Live = (Types.PlayerDataUpdate) -> (string, boolean)

type Entry = {
	panel  : string,
	-- Beschriftung unter der Kachel. Eine Funktion statt eines Strings, weil
	-- sie bei jedem Sprachwechsel neu ausgewertet wird.
	title  : () -> string,
	color  : Color3,
	symbol : string,
	-- Name des Bild-Icons (siehe Icons); `symbol` ist der Text-Rueckfall
	icon   : string,
	live   : Live?,
}

type Tile = {
	entry : Entry,
	-- Die Beschriftung IN der Kachel ist das Text-Feld des Knopfes selbst: ein
	-- eigenes Label darueber wuerde die Klicks abfangen.
	tile  : TextButton,
	alert : Frame,
	label : TextLabel,
	-- true, wenn die Kachel ein Bild zeigt: dann bleibt ihr Text leer
	image : boolean,
}

local _tiles: { Tile } = {}
local buildAllEntries: () -> { Entry }

-- Sammel-Update 3.5: welches Gebaeude-Menue die Kachel oeffnet
local function buildingPanel(): string
	return PanelManager.buildingPanelName(if FeatureFlags.isOn("HONEY_POND_V2") then "HoneyPond" else "HoneyRefiner")
end
TILE_ELEMENT[buildingPanel()] = "tile_building"

--------------------------------------------------------------------------------
-- Die Eintraege
--------------------------------------------------------------------------------

local function buildEntries(): { Entry }
	local list = buildAllEntries()
	if not FeatureFlags.isOn("INCUBATOR") then
		for i = #list, 1, -1 do
			if list[i].panel == "Incubator" then table.remove(list, i) end
		end
	end
	return list
end

function buildAllEntries(): { Entry }
	return {
		{ panel = "Hatch",     title = function() return Loc.t("ui.menu.eggs") end,     color = Theme.COLORS.gummy,  symbol = "EI", icon = "egg" },
		-- Sammel-Update 05.10. (Paket 7): "!" = eine Index-Belohnung ist abholbar.
		{ panel = "Inventory", title = function() return Loc.t("ui.menu.baerchis") end, color = Theme.COLORS.accent, symbol = "BA", icon = "bear",
			live = function(data: Types.PlayerDataUpdate)
				if not FeatureFlags.isOn("INDEX_REWARDS") then return "BA", false end
				return "BA", #IndexRewardConfig.claimable(data.discovered, data.indexClaimed) > 0
			end },
		-- Sammel-Update 05.10. (Paket 3.5/3.6): das Honig-Gebaeude als Kachel
		-- (Verbessern ohne hinzulaufen). "!" = Ausbau bezahlbar.
		{ panel = buildingPanel(), title = function() return Loc.t("ui.menu.building") end, color = Theme.COLORS.goldGummy, symbol = "⬆", icon = "upgrade",
			live = function(data: Types.PlayerDataUpdate)
				local id = if FeatureFlags.isOn("HONEY_POND_V2") then "HoneyPond" else "HoneyRefiner"
				local building = data.island.buildings[id :: any]
				if not building then return "⬆", false end
				local cost = BuildingBehavior.getUpgrade(id :: any, building.level + 1)
				return "⬆", cost ~= nil and data.gummies >= cost.costGummies and data.goldGummies >= (cost.costGoldGummies or 0)
			end },
		-- Sammel-Update 05.10. (Paket 8): Inkubator ("!" = ein Ei ist fertig).
		{ panel = "Incubator", title = function() return Loc.t("ui.incubator.tile") end, color = Theme.COLORS.growth, symbol = "⏳", icon = "incubator",
			live = function(data: Types.PlayerDataUpdate)
				local incubator = data.island.incubator
				if not incubator then return "⏳", false end
				local now = Workspace:GetServerTimeNow()
				local ready = false
				for _, entry in incubator.slots do
					if IncubatorRules.isReady(entry, now) then ready = true end
				end
				return "⏳", ready
			end },
		-- v14: Ei-Baum. Das "!" zeigt eine ungenutzte Blaupause an.
		{ panel = "EggTree", title = function() return Loc.t("ui.menu.tree") end, color = Theme.COLORS.growth, symbol = "BAUM", icon = "tree",
			live = function(data: Types.PlayerDataUpdate)
				local bp = if data.eggTree then data.eggTree.blueprints or 0 else 0
				return "BAUM", bp > 0
			end },
		-- v15: Bestenlisten und Login-Bonus ("!" = heute noch nicht abgeholt)
		{ panel = "Leaderboard", title = function() return Loc.t("ui.menu.leaderboard") end, color = Theme.COLORS.goldGummy, symbol = "TOP", icon = "trophy" },
		{ panel = "DailyBonus", title = function() return Loc.t("ui.menu.daily") end, color = Theme.COLORS.gummy, symbol = "7", icon = "gift",
			live = function(data: Types.PlayerDataUpdate)
				local daily = data.daily
				return if daily then tostring(daily.day) else "7", daily ~= nil and daily.claimable
			end },
		-- HBB Paket 10: Shop ("!" = Gratis-Griff heute noch offen). Sichtbar ab
		-- der 2. Sitzung und nur mit SHOP_V1 (UnlockRules "tile_shop").
		{ panel = "Shop", title = function() return Loc.t("ui.menu.shop") end, color = Theme.COLORS.goldGummy, symbol = "GG", icon = "goldgummy",
			live = function(data: Types.PlayerDataUpdate)
				local shop = data.shop
				return "GG", shop ~= nil and shop.freeReady
			end },
	}
end

--------------------------------------------------------------------------------
-- Eine Kachel
--------------------------------------------------------------------------------

local function buildTile(parent: Instance, order: number, entry: Entry): Tile
	local slot = Theme.container("Slot_" .. entry.panel, parent)
	slot.Size        = UDim2.new(1, 0, 0, TILE + LABEL + 2)
	slot.LayoutOrder = order

	local button = Theme.button("Tile", slot, entry.symbol, entry.color)
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.Position    = UDim2.new(0.5, 0, 0, 0)
	button.Size        = UDim2.new(0, TILE, 0, TILE)
	button.TextColor3  = Theme.COLORS.outline
	Theme.gradient(button, Theme.shade(entry.color, 0.34), Theme.shade(entry.color, -0.16))

	-- Bild-Icon gross in die Kachel. Ohne Asset bleibt das Text-Kuerzel stehen.
	local hasImage = Icons.has(entry.icon)
	if hasImage then
		button.Text = ""
		local icon = Icons.make(button, entry.icon)
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position    = UDim2.fromScale(0.5, 0.52)
		icon.Size        = UDim2.fromScale(0.86, 0.86)
		icon.ZIndex      = 3
	end

	button.Activated:Connect(function()
		local element = TILE_ELEMENT[entry.panel]
		if element then Unlock.markSeen(element) end
		PanelManager.toggle(entry.panel)
	end)

	-- Rotes Ausrufezeichen oben rechts, wie man es aus dem Genre kennt.
	-- Startet unsichtbar und wird von refresh() geschaltet.
	local alert = Theme.panel("Alert", slot, Theme.COLORS.bad)
	alert.AnchorPoint = Vector2.new(1, 0)
	alert.Position    = UDim2.new(0.5, TILE * 0.5 + 5, 0, -4)
	alert.Size        = UDim2.new(0, 20, 0, 20)
	alert.Visible     = false
	alert.ZIndex      = 3
	Theme.corner(alert, 10)

	local bang = Theme.label("Bang", alert, "!")
	bang.Size           = UDim2.fromScale(1, 1)
	bang.TextXAlignment = Enum.TextXAlignment.Center
	bang.ZIndex         = 4

	local label = Theme.label("Name", slot, entry.title())
	label.Position       = UDim2.new(0, 0, 0, TILE + 1)
	label.Size           = UDim2.new(1, 0, 0, LABEL)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextScaled     = false
	label.TextSize       = 14
	Theme.outlineText(label)

	return { entry = entry, tile = button, alert = alert, label = label, image = hasImage }
end

--------------------------------------------------------------------------------
-- Aktualisieren
--------------------------------------------------------------------------------

local function refresh(data: Types.PlayerDataUpdate)
	for _, tile in _tiles do
		-- HBB Paket 3: Kachel erst zeigen, wenn sie gebraucht wird; neue
		-- Kacheln tragen das "!" bis zum ersten Antippen.
		local element = TILE_ELEMENT[tile.entry.panel]
		local isNew = false
		if element then
			local slot = tile.tile.Parent
			if slot and slot:IsA("GuiObject") then
				Unlock.apply(element, slot)
			end
			isNew = Unlock.isNew(element)
			tile.alert.Visible = isNew
		end

		local live = tile.entry.live
		if live then
			local ok, value, alert = pcall(live, data)

			-- In pcall: eine kaputte Kachel darf nicht die ganze Leiste
			-- lahmlegen. Ein alter Spielstand ohne ein Gebaeude waere sonst
			-- genau so ein Fall.
			if ok then
				if not tile.image then
					tile.tile.Text = value
				end
				tile.alert.Visible = alert or isNew
			end
		end
	end
end

--------------------------------------------------------------------------------
-- HBB Paket 1: Ziel fliegender Icons (Eier fliegen zur Eier-Kachel)
--------------------------------------------------------------------------------

function MenuBar.getTileAnchor(panel: string): GuiObject?
	for _, tile in _tiles do
		if tile.entry.panel == panel then
			return tile.tile
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Aufbau
--------------------------------------------------------------------------------

function MenuBar.init(screenGui: ScreenGui)
	local entries = buildEntries()
	local slot    = TILE + LABEL + 2
	local height  = #entries * slot + (#entries - 1) * GAP

	local root = Theme.container("MenuBar", screenGui)
	root.AnchorPoint = Vector2.new(1, 0)
	-- Rechte Kante, unter den Rang-/Rebirth-Pillen. Y bewusst als Pixel-Offset:
	-- die Pillen darueber sind ebenfalls pixelhoch, mit Scale wuerde die Leiste
	-- je nach Bildschirmhoehe hineinrutschen.
	root.Position = UDim2.new(0.988, 0, 0, 108)
	root.Size     = UDim2.new(0, WIDTH, 0, height)

	local layout = Theme.listLayout(root, GAP)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	-- Auf niedrigen Fenstern (Handy quer, kleines Studio-Fenster) schrumpfen,
	-- damit die Leiste nicht ueber den unteren Rand ragt.
	local scale = Instance.new("UIScale")
	scale.Parent = root
	local function rescale()
		local room = UiScale.toGui(screenGui.AbsoluteSize.Y) - 108 - 12
		scale.Scale = math.clamp(room / height, 0.55, 1)
	end
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
	rescale()

	for order, entry in entries do
		table.insert(_tiles, buildTile(root, order, entry))
	end

	ClientState.onChanged(refresh)

	-- HBB Paket 3: ein Panel, das sich von selbst oeffnet (Login-Bonus u.a.), gilt
	-- ebenso als gesehen wie eines, das per Kachel geoeffnet wurde.
	PanelManager.onOpened(function(name)
		local element = TILE_ELEMENT[name]
		if element then Unlock.markSeen(element) end
	end)

	-- Sprachwechsel: nur die Beschriftungen neu setzen (die Zahlen in den
	-- Kacheln sind sprachunabhaengig)
	Loc.onChanged(function()
		for _, tile in _tiles do
			tile.label.Text = tile.entry.title()
		end
	end)

	print("[MenuBar] Initialisiert |", #entries, "Kacheln")
end

return MenuBar
