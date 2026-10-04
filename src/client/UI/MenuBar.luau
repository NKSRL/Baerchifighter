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
	-- Beschriftung unter der Kachel. Eine Funktion statt eines Strings, weil
	-- sie bei jedem Sprachwechsel neu ausgewertet wird.
	title  : () -> string,
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
	label : TextLabel,
}

local _tiles: { Tile } = {}

--------------------------------------------------------------------------------
-- Die Eintraege
--------------------------------------------------------------------------------

local function buildEntries(): { Entry }
	return {
		{ panel = "Hatch",     title = function() return Loc.t("ui.menu.eggs") end,     color = Theme.COLORS.gummy,  symbol = "EI" },
		{ panel = "Inventory", title = function() return Loc.t("ui.menu.baerchis") end, color = Theme.COLORS.accent, symbol = "BA" },
		-- v14: Ei-Baum. Das "!" zeigt eine ungenutzte Blaupause an.
		{ panel = "EggTree", title = function() return Loc.t("ui.menu.tree") end, color = Theme.COLORS.growth, symbol = "BAUM",
			live = function(data: Types.PlayerDataUpdate)
				local bp = if data.eggTree then data.eggTree.blueprints or 0 else 0
				return "BAUM", bp > 0
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

	local label = Theme.label("Name", slot, entry.title())
	label.Position       = UDim2.new(0, 0, 0, TILE + 1)
	label.Size           = UDim2.new(1, 0, 0, LABEL)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextScaled     = false
	label.TextSize       = 13
	Theme.outlineText(label)

	return { entry = entry, tile = button, alert = alert, label = label }
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
