--!strict
-- CharmPanel.luau
-- StarterPlayerScripts/UI/CharmPanel.luau
--
-- Einzige Zustaendigkeit:
--   - Die acht Battle-Charm-Slots eines Baerchis zeigen
--   - Einzelne Slots sperren/freigeben und alle offenen neu wuerfeln
--
-- Wird aus der Baerchi-Detailkarte geoeffnet (Knopf "Charms") und bekommt die
-- uid dabei uebergeben — genau wie BaerchiPanel selbst. Eigene Auswahl haelt
-- dieses Panel nicht.
--
-- ============================================================
-- WAS DIE "PROMOTION TIERS"-LISTE HIER IST — UND WAS NICHT
-- ============================================================
-- Sie zeigt AUSSCHLIESSLICH, ab welcher Promotions-Stufe ein Slot benutzbar
-- wird. Sie sagt NICHT, welcher Stat in einem Slot sitzt: die Slots sind nicht
-- an einen Stat-Typ gebunden, jeder Wurf wuerfelt Rarity UND Stat neu (siehe
-- CharmConfig, Kopf-Kommentar). Wer hier eine Spalte "Bonus" vermisst: die
-- gibt es bewusst nicht.
--
-- Der Server bleibt in jedem Fall autoritativ. Ausgegraute Knoepfe sind nur
-- die freundliche Vorwarnung — abgelehnt wird serverseitig (→ Toast).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loc             = require(ReplicatedStorage.Localization.Loc)   -- Sammel-Update 2.4
local Types           = require(ReplicatedStorage.Network.Types)
local Remotes         = require(ReplicatedStorage.Network.Remotes)
local BaerchiConfig   = require(ReplicatedStorage.Config.BaerchiConfig)
local CharmConfig     = require(ReplicatedStorage.Config.CharmConfig)
local PromotionConfig = require(ReplicatedStorage.Config.PromotionConfig)

local Theme        = require(script.Parent.Theme)
local Toast        = require(script.Parent.Toast)
-- HBB Paket 1: Meldungen nach FeedbackConfig verteilen (Icon/Moment/Toast)
local Notify       = require(script.Parent.Notify)
local PanelManager = require(script.Parent.PanelManager)
local ClientState  = require(script.Parent.Parent.Controllers.ClientState)
local Loc          = require(ReplicatedStorage.Localization.Loc)
local Names        = require(ReplicatedStorage.Localization.Names)

local CharmPanel = {}

local PANEL_NAME = "Charms"

local _root: Frame?          = nil
local _openUid: string?      = nil
local _titleLabel: TextLabel? = nil
local _hintLabel: TextLabel?  = nil
local _costLabel: TextLabel?  = nil
local _rollButton: TextButton? = nil
local _autoButton: TextButton? = nil

-- Ein Eintrag pro Slot: der Knopf (= Sperr-Umschalter) und seine Beschriftung.
type SlotWidget = {
	slot    : number,
	button  : TextButton,
	letter  : TextLabel,
	lockDot : Frame,
	detail  : TextLabel,
}

local _slots: { SlotWidget } = {}

--------------------------------------------------------------------------------
-- Lesen
--------------------------------------------------------------------------------

local function findCharm(baerchi: Types.Baerchi, slot: number): Types.Charm?
	-- `or {}`: ein Datenpaket von einem aelteren Serverstand haette das Feld
	-- nicht. Die Zuweisung an eine typisierte Variable statt direkt in die
	-- Schleife, damit der Typ dabei nicht verloren geht.
	local charms: { Types.Charm } = baerchi.charms or {}

	for _, charm in charms do
		if charm.slot == slot then
			return charm
		end
	end
	return nil
end

-- Dieselbe Bedingung, nach der CharmService.getRollableSlots wuerfelt.
local function countRollable(baerchi: Types.Baerchi): number
	local count = 0
	for slot = 1, CharmConfig.SLOT_COUNT do
		if CharmConfig.isSlotUnlocked(slot, baerchi.promotionLevel or 0) then
			local charm = findCharm(baerchi, slot)
			if not (charm and charm.locked) then
				count += 1
			end
		end
	end
	return count
end

--------------------------------------------------------------------------------
-- Fuellen
--------------------------------------------------------------------------------

local function fill(baerchi: Types.Baerchi)
	local data      = ClientState.get()
	local promotion = baerchi.promotionLevel or 0

	if _titleLabel then
		_titleLabel.Text = Loc.t("ui.charm.title_baerchi", {
			name = Names.baerchi(baerchi.configId),
			p    = promotion,
			max  = PromotionConfig.MAX_PROMOTION,
		})
	end

	for _, widget in _slots do
		local unlocked = CharmConfig.isSlotUnlocked(widget.slot, promotion)
		local charm    = if unlocked then findCharm(baerchi, widget.slot) else nil

		if not unlocked then
			widget.button.BackgroundColor3 = Theme.COLORS.disabled
			widget.letter.Text             = "-"
			widget.letter.TextColor3       = Theme.COLORS.textDim
			widget.lockDot.Visible         = false
			widget.detail.Text = Loc.t("ui.charm.unlock_at", { n = CharmConfig.getUnlockPromotion(widget.slot) })
			widget.detail.TextColor3 = Theme.COLORS.textDim

		elseif not charm then
			widget.button.BackgroundColor3 = Theme.COLORS.panelLight
			widget.letter.Text             = "?"
			widget.letter.TextColor3       = Theme.COLORS.text
			widget.lockDot.Visible         = false
			widget.detail.Text             = Loc.t("ui.charm.empty_slot")
			widget.detail.TextColor3       = Theme.COLORS.textDim

		else
			local color = CharmConfig.RARITY_COLORS[charm.rarity] or Theme.COLORS.panelLight

			widget.button.BackgroundColor3 = color
			widget.letter.Text             = CharmConfig.RARITY_LETTER[charm.rarity] or "?"
			widget.letter.TextColor3       = Theme.COLORS.outline
			widget.lockDot.Visible         = charm.locked
			widget.detail.Text             = CharmConfig.describe(charm)
			widget.detail.TextColor3       = color
		end
	end

	local rollable = countRollable(baerchi)
	local gold     = if data then data.goldGummies else 0
	local cost     = CharmConfig.ROLL_COST_GOLD_GUMMIES

	if _costLabel then
		_costLabel.Text = Loc.t("ui.charm.cost", { gold = gold, cost = cost })
		_costLabel.TextColor3 = if gold >= cost then Theme.COLORS.goldGummy else Theme.COLORS.bad
	end

	if _hintLabel then
		if rollable == 0 then
			_hintLabel.Text = Loc.t("ui.charm.all_locked")
		else
			_hintLabel.Text = Loc.t("ui.charm.roll_hint", { n = rollable })
		end
	end

	local canRoll = rollable > 0 and gold >= cost
	if _rollButton then Theme.setEnabled(_rollButton, canRoll) end
	if _autoButton then Theme.setEnabled(_autoButton, canRoll) end
end

function CharmPanel.refresh()
	local root = _root
	if not root or not root.Visible then return end

	local uid = _openUid
	if not uid then return end

	local baerchi = ClientState.getBaerchi(uid)
	if baerchi then
		fill(baerchi)
	else
		PanelManager.close(PANEL_NAME)
	end
end

--------------------------------------------------------------------------------
-- Oeffnen / Schliessen
--------------------------------------------------------------------------------

local function openInternal(...: any)
	local argument = ...
	if typeof(argument) ~= "string" then return end

	local uid = argument :: string
	if not ClientState.getBaerchi(uid) then
		PanelManager.close(PANEL_NAME)
		return
	end

	_openUid = uid

	local root = _root
	if root then root.Visible = true end

	CharmPanel.refresh()
end

local function closeInternal()
	_openUid = nil
	local root = _root
	if root then root.Visible = false end
end

function CharmPanel.show(uid: string)
	if not ClientState.getBaerchi(uid) then return end
	PanelManager.open(PANEL_NAME, uid)
end

--------------------------------------------------------------------------------
-- Aufbau
--------------------------------------------------------------------------------

function CharmPanel.init(screenGui: ScreenGui)
	local root = Theme.dialog(
		"CharmPanel", screenGui,
		Vector2.new(0.50, 0.66),
		Vector2.new(320, 420),
		Vector2.new(560, 620)
	)
	_root = root

	_titleLabel = Theme.dialogHeader(root, Loc.t("ui.card.section_charms"), function()
		PanelManager.close(PANEL_NAME)
	end)

	local body = Theme.dialogBody(root)

	-- Die acht Slot-Kacheln in zwei Reihen zu vier. Eine Reihe zu acht waere
	-- auf einem Handy zu schmal zum Antippen.
	local slotArea = Theme.container("Slots", body)
	slotArea.Size = UDim2.new(1, 0, 0, 118)

	local grid = Instance.new("UIGridLayout")
	grid.CellSize      = UDim2.new(0.25, -6, 0, 54)
	grid.CellPadding   = UDim2.new(0, 6, 0, 8)
	grid.SortOrder     = Enum.SortOrder.LayoutOrder
	grid.FillDirection = Enum.FillDirection.Horizontal
	grid.Parent        = slotArea

	for slot = 1, CharmConfig.SLOT_COUNT do
		local button = Theme.button("Slot_" .. slot, slotArea, "", Theme.COLORS.panelLight)
		button.LayoutOrder = slot
		button.Text        = ""

		local letter = Theme.label("Letter", button, CharmConfig.SLOT_NUMERALS[slot])
		letter.Size           = UDim2.new(1, 0, 0, 26)
		letter.Position       = UDim2.new(0, 0, 0, 4)
		letter.TextXAlignment = Enum.TextXAlignment.Center
		letter.TextColor3     = Theme.COLORS.outline

		local numeral = Theme.label("Numeral", button, CharmConfig.SLOT_NUMERALS[slot])
		numeral.Size           = UDim2.new(1, 0, 0, 16)
		numeral.Position       = UDim2.new(0, 0, 1, -20)
		numeral.TextXAlignment = Enum.TextXAlignment.Center
		numeral.TextScaled     = false
		numeral.TextSize       = 12
		numeral.TextColor3     = Theme.COLORS.outline

		-- Kleines Schloss-Zeichen oben rechts: gesperrte Slots wuerfelt ein
		-- Wurf nicht mit.
		local lockDot = Theme.panel("Lock", button, Theme.COLORS.outline)
		lockDot.AnchorPoint = Vector2.new(1, 0)
		lockDot.Position    = UDim2.new(1, -2, 0, 2)
		lockDot.Size        = UDim2.new(0, 16, 0, 16)
		lockDot.Visible     = false
		lockDot.ZIndex      = 3
		Theme.corner(lockDot, 8)

		local lockText = Theme.label("Text", lockDot, "")
		Loc.bind(lockText, "ui.charm.lock_letter")
		lockText.Size           = UDim2.fromScale(1, 1)
		lockText.TextXAlignment = Enum.TextXAlignment.Center
		lockText.TextScaled     = false
		lockText.TextSize       = 11
		lockText.ZIndex         = 4

		button.Activated:Connect(function()
			local uid = _openUid
			if not uid then return end
			Remotes.RequestToggleCharmLock:FireServer(uid, slot)
		end)

		table.insert(_slots, {
			slot    = slot,
			button  = button,
			letter  = letter,
			lockDot = lockDot,
			detail  = Theme.label("Detail_" .. slot, body, ""),   -- Position unten
		})
	end

	-- Die Effekt-Zeilen unter den Kacheln: eine pro Slot, scrollbar, damit acht
	-- Zeilen auch auf einem kleinen Bildschirm vollstaendig lesbar bleiben.
	local list = Theme.scroller("Effects", body)
	list.Position = UDim2.new(0, 0, 0, 126)
	list.Size     = UDim2.new(1, 0, 1, -126 - 92)
	Theme.listLayout(list, 3)

	for _, widget in _slots do
		local row = Theme.container("Row_" .. widget.slot, list)
		-- Sammel-Update 2.5 ("Charm Text der Effekte groesser"): 13 -> 18 px,
		-- Zeile 20 -> 28 px, mit duenner dunkler Kontur fuer den Kontrast auf
		-- dem farbigen Text (Rarity-Farben sind teils hell).
		row.Size        = UDim2.new(1, -8, 0, 28)
		row.LayoutOrder = widget.slot

		local numeral = Theme.label("Num", row, CharmConfig.SLOT_NUMERALS[widget.slot])
		numeral.Size       = UDim2.new(0, 44, 1, 0)
		numeral.TextScaled = false
		numeral.TextSize   = 17
		numeral.TextColor3 = Theme.COLORS.textDim

		widget.detail.Parent         = row
		widget.detail.Position       = UDim2.new(0, 48, 0, 0)
		widget.detail.Size           = UDim2.new(1, -48, 1, 0)
		widget.detail.TextScaled     = false
		widget.detail.TextSize       = 18
		widget.detail.TextWrapped    = true
		widget.detail.TextXAlignment = Enum.TextXAlignment.Left
		widget.detail.TextStrokeTransparency = 0.55
		widget.detail.TextStrokeColor3       = Theme.COLORS.outline
	end

	-- Fusszeile: Bestand, Hinweis, zwei Knoepfe.
	local footer = Theme.container("Footer", body)
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position    = UDim2.new(0, 0, 1, 0)
	footer.Size        = UDim2.new(1, 0, 0, 88)

	_costLabel = Theme.label("Cost", footer, "")
	_costLabel.Size       = UDim2.new(1, 0, 0, 20)
	_costLabel.TextScaled = false
	_costLabel.TextSize   = 14

	_hintLabel = Theme.bodyText("Hint", footer, "")
	_hintLabel.Position = UDim2.new(0, 0, 0, 22)
	_hintLabel.Size     = UDim2.new(1, 0, 0, 26)

	local roll = Theme.button("Roll", footer, Loc.t("ui.charm.roll"), Theme.COLORS.gummy)
	roll.Position = UDim2.new(0, 0, 0, 52)
	roll.Size     = UDim2.new(0.5, -4, 0, 34)
	_rollButton = roll
	roll.Activated:Connect(function()
		local uid = _openUid
		if not uid then return end
		Remotes.RequestRollCharms:FireServer(uid, 1)
	end)

	local auto = Theme.button("AutoRoll", footer, "", Theme.COLORS.goldGummy)
	Loc.bind(auto, "ui.charm.auto_roll", { n = CharmConfig.AUTO_ROLL_COUNT })
	auto.AnchorPoint = Vector2.new(1, 0)
	auto.Position    = UDim2.new(1, 0, 0, 52)
	auto.Size        = UDim2.new(0.5, -4, 0, 34)
	_autoButton = auto
	auto.Activated:Connect(function()
		local uid = _openUid
		if not uid then return end
		Remotes.RequestRollCharms:FireServer(uid, CharmConfig.AUTO_ROLL_COUNT)
	end)

	PanelManager.register(PANEL_NAME, {
		open  = openInternal,
		close = closeInternal,
	})

	ClientState.onChanged(function()
		CharmPanel.refresh()
	end)
	Loc.onChanged(function()
		CharmPanel.refresh()
	end)

	Remotes.CharmRollResultReceived.OnClientEvent:Connect(function(result: any)
		if typeof(result) ~= "table" then return end
		local typed = result :: Types.CharmRollResult

		Notify.emit("charm_roll", function()
			Toast.success(Loc.tn("msg.charm_rolled", typed.rolls, { gold = typed.goldGummiesSpent }))
		end)

		CharmPanel.refresh()
	end)

	print("[CharmPanel] Initialisiert |", CharmConfig.SLOT_COUNT, "Slots")
end

return CharmPanel
