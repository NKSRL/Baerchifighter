--!strict
-- BuildingPanel.luau
-- StarterPlayerScripts/UI/BuildingPanel.luau
--
-- Einzige Zustaendigkeit:
--   - Fuer JEDES Honig-Gebaeude ein eigenes Menue bauen und aktuell halten
--
-- v15: zwei Gebaeude (Bienenstock, Honig-Veredler), Level 1-60 mit Look-Stufe
-- und Meilenstein-Faehigkeiten. Das fruehere Menue der Kampfplattform
-- (PIT-Level) ist entfallen — die Tower-Wahl liegt im CombatPanel. Der Recycler
-- wird an seinem eigenen Prompt ausgebaut (CombController).
--
-- ============================================================
-- WARUM EIGENE MENUES STATT EINER LISTE
-- ============================================================
-- Bis v7 gab es EIN Panel mit drei untereinander gestapelten Karten. Das war
-- richtig, solange die drei Gebaeude dasselbe taten — man wollte sie ja
-- vergleichen. Seit jedes eine eigene Rolle hat (Vorrat / Heilung / Wachstum,
-- siehe Config/BuildingBehavior), vergleicht man nicht mehr, sondern
-- entscheidet sich: "ich brauche jetzt Heilung". Dafuer will man EIN Fenster
-- sehen, das ganz diesem Gebaeude gehoert — mit seiner Farbe, seinem Level und
-- seinem Honig, gross statt in einer Zeile.
--
-- Trotzdem gibt es nur DIESE eine Datei: sie baut viermal dasselbe Geruest mit
-- unterschiedlichen Farben und Inhalten. Drei fast gleiche Panel-Module waeren
-- dieselbe Dopplung, die dieses Projekt an anderen Stellen schon aufgeloest
-- hat.
--
-- Jedes Menue meldet sich unter PanelManager.buildingPanelName(id) an. Diesen
-- Namen benutzen auch die Menueleiste und der Prompt am Gebaeude in der Welt —
-- deshalb steht er im PanelManager und nicht hier.
--
-- ============================================================
-- OHNE HINLAUFEN BEDIENBAR
-- ============================================================
-- Jedes Menue kann BEIDES: ausbauen und den ausgeruesteten Baerchi mit dem
-- Honig genau dieses Gebaeudes fuettern. Zusammen mit den Knoepfen in der
-- Menueleiste heisst das: der Spieler muss zu keinem Gebaeude mehr hinlaufen.
-- Die Prompts in der Welt bleiben trotzdem — wer davorsteht, soll es auch
-- dort anklicken koennen.
--
-- Dieses Modul rechnet nichts aus und formuliert nichts selbst: Effekt-Saetze
-- kommen aus BuildingBehavior, Preise aus EconomyConfig, Namen aus MapConfig,
-- Farben aus Theme. Ein hier nachgebauter Text waere beim naechsten Balancing
-- sofort falsch.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types            = require(ReplicatedStorage.Network.Types)
local Loc              = require(ReplicatedStorage.Localization.Loc)
local Names            = require(ReplicatedStorage.Localization.Names)
local Remotes          = require(ReplicatedStorage.Network.Remotes)
local EconomyConfig    = require(ReplicatedStorage.Config.EconomyConfig)
local BuildingBehavior = require(ReplicatedStorage.Config.BuildingBehavior)
local MapConfig        = require(ReplicatedStorage.Config.MapConfig)

local Theme        = require(script.Parent.Theme)
local PanelManager = require(script.Parent.PanelManager)
local ClientState  = require(script.Parent.Parent.Controllers.ClientState)

local BuildingPanel = {}

-- Feste Reihenfolge. Die Gebaeude in IslandData liegen in einer Hash-Tabelle
-- und kommen damit nicht stabil heraus.
--
-- Nur die ids stehen hier: Name kommt aus MapConfig (dasselbe Schild traegt
-- ihn in der Welt), Farbe aus Theme.buildingColor (dieselbe faerbt die
-- Fuetter-Knoepfe auf der Baerchi-Karte).
local BUILDINGS: { { id: Types.BuildingId } } = {
	{ id = "Beehive"      },
	{ id = "HoneyRefiner" },
	{ id = "HoneyPond"    },
}

-- Alles, was ein einzelnes Menue zum Aktualisieren braucht.
type Menu = {
	root       : Frame,
	title      : TextLabel,
	levelBadge : TextLabel,
	subLabel   : TextLabel,
	honeyFill  : Frame,
	honeyText  : TextLabel,
	nowText    : TextLabel,
	nextText   : TextLabel,
	priceText  : TextLabel,
	abilities  : TextLabel,
	upgrade    : TextButton,
	feed       : TextButton?,
}

local _menus: { [string]: Menu } = {}

--------------------------------------------------------------------------------
-- Hilfstexte
--------------------------------------------------------------------------------

local function displayName(buildingId: string): string
	return Names.building(buildingId)
end

-- v15: Meilenstein-Faehigkeiten als eine Zeile ("Lv.10 Auto-Abnahme ✓ ·
-- Lv.30 Goldene Tropfen (bald)").
local function abilitiesText(buildingId: string, level: number): string
	local parts: { string } = {}
	for _, ability in BuildingBehavior.getAbilities(buildingId) do
		local name = Loc.t("ability." .. ability.id)
		local state = if not ability.implemented then Loc.t("ui.ability.soon")
			elseif level >= ability.level then "✓"
			else ""
		table.insert(parts, string.format("Lv.%d %s %s", ability.level, name, state))
	end
	return table.concat(parts, "  ·  ")
end

local function priceText(costGummies: number, costGoldGummies: number): string
	local parts: { string } = {}

	if costGummies > 0 then
		table.insert(parts, Loc.t("event.bonus.gummies", { n = costGummies }))
	end
	if costGoldGummies > 0 then
		table.insert(parts, Loc.t("event.bonus.gold", { n = costGoldGummies }))
	end
	if #parts == 0 then
		return Loc.t("ui.common.free")
	end

	return table.concat(parts, " + ")
end

local function canPay(data: Types.PlayerDataUpdate, costGummies: number, costGoldGummies: number): boolean
	if costGummies > 0 and data.gummies < costGummies then return false end
	if costGoldGummies > 0 and data.goldGummies < costGoldGummies then return false end
	return true
end

--------------------------------------------------------------------------------
-- Das Geruest eines Menues
--------------------------------------------------------------------------------

-- Baut ein Menue in der Farbe `accent`. `withFeed` legt zusaetzlich den
-- Fuetter-Knopf an — die Kampfplattform hat keinen Honig.
local function buildMenu(
	screenGui: ScreenGui,
	panelName: string,
	title: string,
	accent: Color3,
	withFeed: boolean,
	onUpgrade: () -> (),
	onFeed: (() -> ())?
): Menu
	local root = Theme.dialog(
		panelName, screenGui,
		Vector2.new(0.40, 0.62),
		Vector2.new(300, 400),
		Vector2.new(440, 520)
	)

	-- Der Rand des ganzen Fensters traegt die Gebaeudefarbe: schon bevor man
	-- liest, sieht man welches Gebaeude offen ist.
	local outline = root:FindFirstChildOfClass("UIStroke")
	if outline then
		outline.Color = Theme.shade(accent, -0.35)
	end

	--------------------------------------------------------------------------
	-- Kopfbalken mit Verlauf
	--------------------------------------------------------------------------

	local header = Theme.panel("Banner", root, accent)
	header.Size     = UDim2.new(1, 0, 0, 74)
	header.Position = UDim2.fromScale(0, 0)
	Theme.gradient(header, Theme.shade(accent, 0.30), Theme.shade(accent, -0.18))

	-- Rundes Emblem mit der Stufe darin. Zwei Fliegen: es macht den Kopf bunt
	-- UND beantwortet die haeufigste Frage ("auf welcher Stufe bin ich?"),
	-- ohne dass man Text lesen muss.
	local badge = Theme.panel("Badge", header, Theme.shade(accent, -0.30))
	badge.AnchorPoint = Vector2.new(0, 0.5)
	badge.Position    = UDim2.new(0, 12, 0.5, 0)
	badge.Size        = UDim2.new(0, 50, 0, 50)
	Theme.corner(badge, 25)

	local levelBadge = Theme.label("Level", badge, "1")
	levelBadge.Size           = UDim2.fromScale(1, 1)
	levelBadge.TextXAlignment = Enum.TextXAlignment.Center

	local titleLabel = Theme.label("Title", header, title)
	titleLabel.Position   = UDim2.new(0, 72, 0, 12)
	titleLabel.Size       = UDim2.new(1, -118, 0, 30)
	titleLabel.TextColor3 = Theme.COLORS.outline

	local subLabel = Theme.sectionLabel("Sub", header, "", Theme.shade(accent, -0.45))
	subLabel.Position = UDim2.new(0, 72, 0, 42)
	subLabel.Size     = UDim2.new(1, -118, 0, 20)

	local close = Theme.button("Close", header, "X", Theme.shade(accent, -0.30))
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position    = UDim2.new(1, -10, 0, 10)
	close.Size        = UDim2.new(0, 32, 0, 28)
	close.TextColor3  = Theme.COLORS.text
	close.Activated:Connect(function()
		PanelManager.close(panelName)
	end)

	--------------------------------------------------------------------------
	-- Inhalt
	--------------------------------------------------------------------------

	local body = Theme.container("Body", root)
	body.Position = UDim2.new(0, 0, 0, 74)
	body.Size     = UDim2.new(1, 0, 1, -74)
	Theme.padding(body, 14)

	local layout = Theme.listLayout(body, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left

	local order = 0
	local function row(height: number): Frame
		order += 1
		local frame = Theme.container("Row", body)
		frame.Size        = UDim2.new(1, 0, 0, height)
		frame.LayoutOrder = order
		return frame
	end

	-- Honig-Balken: der Wert, den man beim Reinschauen zuerst sucht.
	local honeyHead = row(18)
	local honeyHeadLabel = Theme.sectionLabel("HoneyHead", honeyHead, "", accent)
	honeyHeadLabel.Size = UDim2.fromScale(1, 1)
	Loc.bind(honeyHeadLabel, "ui.building.honey_stock")

	local honeyRow  = row(26)
	local honeyBar  = Theme.progress(honeyRow, accent)
	honeyBar.track.Size = UDim2.new(1, 0, 1, 0)

	-- Was das Gebaeude JETZT kann
	local nowHead = row(18)
	local nowHeadLabel = Theme.sectionLabel("NowHead", nowHead, "", accent)
	nowHeadLabel.Size = UDim2.fromScale(1, 1)
	Loc.bind(nowHeadLabel, "ui.building.now")

	local nowRow  = row(38)
	local nowText = Theme.bodyText("Now", nowRow, "")
	nowText.Size      = UDim2.fromScale(1, 1)
	nowText.TextColor3 = Theme.COLORS.text

	-- Was die naechste Stufe braechte
	local nextHead = row(18)
	local nextHeadLabel = Theme.sectionLabel("NextHead", nextHead, "", accent)
	nextHeadLabel.Size = UDim2.fromScale(1, 1)
	Loc.bind(nextHeadLabel, "ui.building.next")

	local nextRow  = row(38)
	local nextText = Theme.bodyText("Next", nextRow, "")
	nextText.Size = UDim2.fromScale(1, 1)

	local priceRow   = row(22)
	local priceLabel = Theme.label("Price", priceRow, "")
	priceLabel.Size     = UDim2.fromScale(1, 1)
	priceLabel.TextSize = 16
	priceLabel.TextScaled = false

	-- v15: Meilenstein-Faehigkeiten dieses Gebaeudes
	local abilityRow  = row(30)
	local abilityText = Theme.bodyText("Abilities", abilityRow, "")
	abilityText.Size       = UDim2.fromScale(1, 1)
	abilityText.TextColor3 = Theme.COLORS.textDim

	-- Die Knoepfe ganz unten, in der Reihenfolge, in der man sie braucht.
	local upgradeRow = row(44)
	local upgrade    = Theme.bigButton("Upgrade", upgradeRow, Loc.t("ui.building.upgrade_btn"), accent)
	upgrade.Size = UDim2.new(1, 0, 1, 0)
	upgrade.Activated:Connect(onUpgrade)

	local feedButton: TextButton? = nil
	if withFeed and onFeed then
		local feedRow = row(38)
		local feed    = Theme.bigButton("Feed", feedRow, "", Theme.shade(accent, -0.10))
		feed.Size = UDim2.new(1, 0, 1, 0)
		feed.Activated:Connect(onFeed)
		feedButton = feed
	end

	return {
		root       = root,
		title      = titleLabel,
		levelBadge = levelBadge,
		subLabel   = subLabel,
		honeyFill  = honeyBar.fill,
		honeyText  = honeyBar.text,
		nowText    = nowText,
		nextText   = nextText,
		priceText  = priceLabel,
		abilities  = abilityText,
		upgrade    = upgrade,
		feed       = feedButton,
	}
end

--------------------------------------------------------------------------------
-- Aktualisieren
--------------------------------------------------------------------------------

local function refreshBuilding(buildingId: Types.BuildingId)
	local menu = _menus[PanelManager.buildingPanelName(buildingId)]
	if not menu or not menu.root.Visible then return end

	local data = ClientState.get()
	if not data then return end

	local building = data.island.buildings[buildingId]
	local level    = if building then building.level else 1
	local honey    = if building then (building.honey or 0) else 0
	local capacity = math.max(1, BuildingBehavior.getCapacity(buildingId, level))

	menu.levelBadge.Text = tostring(level)
	menu.subLabel.Text   = Loc.t("ui.building.level_look", {
		level = level, max = EconomyConfig.MAX_BUILDING_LEVEL, look = BuildingBehavior.getLook(level),
	})
	menu.abilities.Text  = abilitiesText(buildingId, level)

	menu.honeyFill.Size = UDim2.fromScale(math.clamp(honey / capacity, 0, 1), 1)
	menu.honeyText.Text = string.format("%d / %d", honey, capacity)

	menu.nowText.Text = BuildingBehavior.describeEffect(buildingId, level)

	local next_ = BuildingBehavior.getUpgrade(buildingId, level + 1)

	if next_ then
		local affordable = canPay(data, next_.costGummies, next_.costGoldGummies)

		menu.nextText.Text   = next_.effect
		menu.priceText.Text  = priceText(next_.costGummies, next_.costGoldGummies)
		menu.priceText.TextColor3 = if affordable then Theme.COLORS.good else Theme.COLORS.bad

		menu.upgrade.Text = Loc.t("ui.building.upgrade_btn")
		Theme.setEnabled(menu.upgrade, affordable)
	else
		menu.nextText.Text        = Loc.t("ui.building.maxed_text")
		menu.priceText.Text       = ""
		menu.upgrade.Text         = Loc.t("ui.building.maxed_btn")
		Theme.setEnabled(menu.upgrade, false)
	end

	local feed = menu.feed
	if feed then
		feed.Text = Loc.t("ui.building.feed", { n = honey })
		Theme.setEnabled(feed, honey > 0 and data.island.equippedUid ~= nil)
	end
end

-- Oeffentlich, damit ClientState alle Menues auf einmal nachziehen kann.
function BuildingPanel.refresh()
	for _, entry in BUILDINGS do
		refreshBuilding(entry.id)
	end
end

--------------------------------------------------------------------------------
-- Aufbau
--------------------------------------------------------------------------------

function BuildingPanel.init(screenGui: ScreenGui)
	for _, entry in BUILDINGS do
		local id        = entry.id
		local panelName = PanelManager.buildingPanelName(id)

		local menu = buildMenu(
			screenGui, panelName, displayName(id), Theme.buildingColor(id), true,
			function()
				Remotes.RequestUpgradeBuilding:FireServer(id)
			end,
			function()
				-- Gefuettert wird immer der ausgeruestete Baerchi: nur der steht
				-- in der Welt, und nur er kaempft. Wer einen anderen meint,
				-- ruestet ihn erst aus — dieselbe Regel wie beim Autopiloten.
				local data = ClientState.get()
				local uid  = if data then data.island.equippedUid else nil
				if not uid then return end

				Remotes.RequestFeedHoney:FireServer(uid, id)
			end
		)

		_menus[panelName] = menu

		PanelManager.register(panelName, {
			open = function()
				menu.root.Visible = true
				refreshBuilding(id)
			end,
			close = function()
				menu.root.Visible = false
			end,
		})
	end

	ClientState.onChanged(function()
		BuildingPanel.refresh()
	end)
	-- Sprachwechsel: Titel und alle Zeilen der offenen Menues neu beschriften
	Loc.onChanged(function()
		for _, entry in BUILDINGS do
			local menu = _menus[PanelManager.buildingPanelName(entry.id)]
			if menu then menu.title.Text = displayName(entry.id) end
		end
		BuildingPanel.refresh()
	end)

	print("[BuildingPanel] Initialisiert |", #BUILDINGS, "Gebaeude-Menues")
end

return BuildingPanel
