--!strict
-- MenuBar.luau
-- StarterPlayerScripts/UI/MenuBar.luau
--
-- Einzige Zustaendigkeit:
--   - Der Zugang zu ALLEN Menues: eine Kachelleiste am rechten Bildschirmrand
--
-- ============================================================
-- WARUM RECHTS, UND WARUM FUER JEDES GEBAEUDE EINE EIGENE KACHEL
-- ============================================================
-- Vorher standen hier vier Knoepfe links, und die drei Gebaeude teilten sich
-- einen davon. Wer den Honigtopf ausbauen wollte, musste ueber den Plot laufen
-- oder sich durch eine Liste scrollen. Seit jedes Gebaeude eine eigene Rolle
-- und ein eigenes Menue hat, bekommt jedes auch eine eigene Kachel: alles, was
-- der Spieler regelmaessig tut, ist damit von jeder Stelle der Karte aus
-- erreichbar, ohne einen Schritt zu gehen.
--
-- Die Leiste steht rechts, weil links oben die Waehrungs-Pillen sitzen und
-- unten in der Mitte der Toast-Stapel — das ist die einzige Kante, an der eine
-- Spalte aus sieben Kacheln niemandem im Weg steht. Es ist ausserdem die
-- Anordnung, die Spieler aus diesem Genre kennen.
--
-- Fusion und Rebirth haben bewusst KEINE Kachel:
--   - Fusion wird aus dem Inventar geoeffnet, weil sie ohne zwei ausgewaehlte
--     Baerchis sinnlos ist.
--   - Rebirth haengt an der Rebirth-Pille rechts oben im HUD.
--
-- ============================================================
-- LEBENDE KACHELN
-- ============================================================
-- Dieses Modul war frueher ein reiner Ausloeser ohne Datenzugriff. Das reicht
-- nicht mehr: eine Kachel, die den Honig-Bestand zeigt und aufleuchtet, sobald
-- ein Ausbau bezahlbar ist, erspart genau das Herumklicken, das die Leiste
-- abschaffen soll. Sie liest deshalb mit — aber nur lesend, ueber ClientState,
-- und rechnet nichts selbst aus.
--
-- Welches Panel offen ist, weiss weiterhin ausschliesslich der PanelManager.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types            = require(ReplicatedStorage.Network.Types)
local EconomyConfig    = require(ReplicatedStorage.Config.EconomyConfig)
local BuildingBehavior = require(ReplicatedStorage.Config.BuildingBehavior)
local MapConfig        = require(ReplicatedStorage.Config.MapConfig)

local Theme        = require(script.Parent.Theme)
local PanelManager = require(script.Parent.PanelManager)
local ClientState  = require(script.Parent.Parent.Controllers.ClientState)

local MenuBar = {}

-- Groessen. TILE ist gleichzeitig die Antippflaeche — darunter wird es auf dem
-- Handy zur Geduldsprobe.
local TILE   = 46
local LABEL  = 15
local GAP    = 6
local WIDTH  = 76

-- Was eine Kachel anzeigt: `value` ist die Beschriftung IN der Kachel,
-- `alert` laesst das rote Ausrufezeichen erscheinen.
type Live = (Types.PlayerDataUpdate) -> (string, boolean)

type Entry = {
	panel  : string,
	text   : string,
	color  : Color3,
	symbol : string,
	live   : Live?,
}

type Tile = {
	entry : Entry,
	-- Die Beschriftung IN der Kachel ist das Text-Feld des Knopfes selbst: ein
	-- eigenes Label darueber wuerde die Klicks abfangen.
	tile  : TextButton,
	alert : Frame,
}

local _tiles: { Tile } = {}

--------------------------------------------------------------------------------
-- Was auf den Kacheln steht
--------------------------------------------------------------------------------

-- Gebaeude-Kachel: die Zahl ist der eingelagerte Honig — das ist der Wert, den
-- man im Vorbeigehen sucht ("kann ich fuettern?"). Das Ausrufezeichen kommt,
-- wenn es etwas zu TUN gibt: Ausbau bezahlbar, oder Lager voll (dann steht die
-- Produktion still und jeder weitere Honig verfaellt).
local function buildingLive(buildingId: Types.BuildingId): Live
	return function(data: Types.PlayerDataUpdate): (string, boolean)
		local building = data.island.buildings[buildingId]
		if not building then
			return "-", false
		end

		local honey    = building.honey or 0
		local capacity = BuildingBehavior.getCapacity(buildingId, building.level)
		local next_    = BuildingBehavior.getUpgrade(buildingId, building.level + 1)

		local affordable = next_ ~= nil
			and data.gummies >= next_.costGummies
			and data.goldGummies >= next_.costGoldGummies

		return tostring(honey), affordable or honey >= capacity
	end
end

-- Arena-Kachel: die Zahl ist die Stufe, das Ausrufezeichen kommt bei
-- bezahlbarem Ausbau.
local function arenaLive(data: Types.PlayerDataUpdate): (string, boolean)
	-- `or 1` wie ueberall sonst im Client: ein Datenpaket von einem aelteren
	-- Serverstand haette das Feld nicht, und die Kachel soll dann Stufe 1
	-- zeigen statt beim Rechnen abzubrechen.
	local level = data.island.pitLevel or 1
	local cost  = if level + 1 <= EconomyConfig.MAX_PIT_LEVEL
		then EconomyConfig.getPitUpgradeCost(level + 1)
		else nil

	return tostring(level), cost ~= nil and data.gummies >= cost
end

-- Reihenfolge = Spielablauf: erst Eier, dann Baerchis, dann Kampf, dann die
-- drei Gebaeude, zuletzt die Arena.
--
-- Die Gebaeude-Eintraege werden aus MapConfig.BUILDING_ORDER erzeugt, nicht von
-- Hand aufgezaehlt: sonst waere das die naechste Liste von Gebaeude-Ids, die
-- irgendwann von den anderen abweicht.
local function buildEntries(): { Entry }
	local entries: { Entry } = {
		{ panel = "Hatch",     text = "Eier",     color = Theme.COLORS.gummy,  symbol = "EI" },
		{ panel = "Inventory", text = "Baerchis", color = Theme.COLORS.accent, symbol = "BA" },
		{ panel = "Combat",    text = "Kampf",    color = Theme.COLORS.bad,    symbol = "VS" },
	}

	for _, id in MapConfig.BUILDING_ORDER do
		local config = MapConfig.BUILDING_OFFSETS[id]

		table.insert(entries, {
			panel  = PanelManager.buildingPanelName(id),
			text   = if config then config.shortName else id,
			color  = Theme.buildingColor(id),
			symbol = "0",
			live   = buildingLive(id :: Types.BuildingId),
		})
	end

	table.insert(entries, {
		panel  = PanelManager.ARENA_PANEL,
		text   = "Arena",
		color  = Theme.COLORS.goldGummy,
		symbol = "1",
		live   = arenaLive,
	})

	return entries
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

	button.Activated:Connect(function()
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

	local label = Theme.label("Name", slot, entry.text)
	label.Position       = UDim2.new(0, 0, 0, TILE + 1)
	label.Size           = UDim2.new(1, 0, 0, LABEL)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextScaled     = false
	label.TextSize       = 13
	Theme.outlineText(label)

	return { entry = entry, tile = button, alert = alert }
end

--------------------------------------------------------------------------------
-- Aktualisieren
--------------------------------------------------------------------------------

local function refresh(data: Types.PlayerDataUpdate)
	for _, tile in _tiles do
		local live = tile.entry.live
		if live then
			local ok, value, alert = pcall(live, data)

			-- In pcall: eine kaputte Kachel darf nicht die ganze Leiste
			-- lahmlegen. Ein alter Spielstand ohne ein Gebaeude waere sonst
			-- genau so ein Fall.
			if ok then
				tile.tile.Text     = value
				tile.alert.Visible = alert
			end
		end
	end
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

	for order, entry in entries do
		table.insert(_tiles, buildTile(root, order, entry))
	end

	ClientState.onChanged(refresh)

	print("[MenuBar] Initialisiert |", #entries, "Kacheln")
end

return MenuBar
