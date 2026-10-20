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
-- 14.10. Honig-UI (UI_HONEY_SKIN): Fenster als Bild, siehe buildHoney
local Icons        = require(script.Parent.Icons)
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)
local CharmIcon    = require(script.Parent.CharmIcon)   -- 16.10. Charm-Bilder je Rarity

local CharmPanel = {}

local PANEL_NAME = "Charms"

local _root: Frame?          = nil
local _openUid: string?      = nil
local _titleLabel: TextLabel? = nil
local _hintLabel: TextLabel?  = nil
local _costLabel: TextLabel?  = nil
local _rollButton: TextButton? = nil
local _autoButton: TextButton? = nil
local _honey = false
local _rollCover: Frame? = nil
local _autoCover: Frame? = nil
local _autoCostLabel: TextLabel? = nil
local _canRoll = false

-- Ein Eintrag pro Slot: der Knopf (= Sperr-Umschalter) und seine Beschriftung.
type SlotWidget = {
	slot    : number,
	button  : TextButton,
	letter  : TextLabel,
	lockDot : Frame,
	detail  : TextLabel,
	tint    : Frame?,        -- Honig-UI: Rarity-Flaeche ueber dem Silhouetten-Bild
	cover   : Frame?,        -- Honig-UI: dunkle Abdeckung (Slot noch nicht freigeschaltet)
	rarity  : TextLabel?,    -- Honig-UI: Rarity-Name im rechten Feld der Zeile
	lockMark: TextLabel?,    -- Honig-UI: Sperr-Zeichen im Sechseck der Zeile
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

-- Dieselbe Bedingung, nach der CharmService.getRollableSlots wuerfelt (14.10.:
-- alle acht Slots ausser den gesperrten, unabhaengig von der Promotion).
local function countRollable(baerchi: Types.Baerchi): number
	local count = 0
	for slot = 1, CharmConfig.SLOT_COUNT do
		local charm = findCharm(baerchi, slot)
		if not (charm and charm.locked) then
			count += 1
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

	if _titleLabel and _honey then
		-- Im Banner ist nur Platz fuer den Namen; die Promotion zeigen die Zeilen (ab Promotion n)
		_titleLabel.Text = Names.baerchi(baerchi.configId)
	elseif _titleLabel then
		_titleLabel.Text = Loc.t("ui.charm.title_baerchi", {
			name = Names.baerchi(baerchi.configId),
			p    = promotion,
			max  = PromotionConfig.MAX_PROMOTION,
		})
	end

	for _, widget in _slots do
		-- 14.10.: auch Slots, die die Promotion noch nicht freischaltet, tragen
		-- einen gewuerfelten Charm — er ist nur noch nicht wirksam (abgedunkelt).
		local unlocked = CharmConfig.isSlotUnlocked(widget.slot, promotion)
		local charm    = findCharm(baerchi, widget.slot)

		if _honey then
			local dim = Color3.fromRGB(205, 170, 120)
			local ink = Color3.fromRGB(255, 244, 214)
			if widget.cover then widget.cover.Visible = not unlocked end
			if widget.tint then widget.tint.Visible = charm ~= nil end
			-- 16.10.: Charm-Bild statt Farbflaeche + Buchstabe (ohne Bild bleibt das alte Aussehen)
			local hasIcon = false
			if widget.tint then
				hasIcon = CharmIcon.set(widget.tint, if charm then charm.rarity else nil, UDim2.fromScale(1.42, 1.42), 4)
				widget.tint.BackgroundTransparency = if hasIcon then 1 else 0.1
			end
			widget.letter.Visible = not hasIcon
			if widget.lockMark then widget.lockMark.Visible = false end
			if widget.rarity then widget.rarity.Text = "" end
			widget.lockDot.Visible = false

			if not unlocked and not charm then
				widget.letter.Text       = "-"
				widget.letter.TextColor3 = ink
				widget.detail.Text       = Loc.t("ui.charm.unlock_at", { n = CharmConfig.getUnlockPromotion(widget.slot) })
				widget.detail.TextColor3 = dim
			elseif not charm then
				widget.letter.Text       = "?"
				widget.letter.TextColor3 = ink
				widget.detail.Text       = Loc.t("ui.charm.empty_slot")
				widget.detail.TextColor3 = dim
			else
				local color = CharmConfig.RARITY_COLORS[charm.rarity] or ink
				if widget.tint then widget.tint.BackgroundColor3 = color end
				widget.letter.Text       = CharmConfig.RARITY_LETTER[charm.rarity] or "?"
				widget.letter.TextColor3 = Color3.fromRGB(58, 30, 8)
				widget.detail.Text       = CharmConfig.describe(charm)
				widget.detail.TextColor3 = color
				if widget.rarity then
					widget.rarity.Text       = Names.rarity(charm.rarity)
					widget.rarity.TextColor3 = color
				end
				if not unlocked then
					-- noch nicht wirksam: Zeile gedaempft, rechts steht wann
					widget.detail.TextColor3 = dim
					if widget.rarity then
						widget.rarity.Text       = Loc.t("ui.charm.unlock_at", { n = CharmConfig.getUnlockPromotion(widget.slot) })
						widget.rarity.TextColor3 = dim
					end
				end
				widget.lockDot.Visible = charm.locked
				if widget.lockMark then widget.lockMark.Visible = charm.locked end
			end
			continue
		end

		if not unlocked and not charm then
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
			if not unlocked then
				widget.button.BackgroundColor3 = Theme.COLORS.disabled
				widget.detail.TextColor3       = Theme.COLORS.textDim
			end
		end
	end

	local rollable = countRollable(baerchi)
	local gold     = if data then data.goldGummies else 0
	-- 14.10.: jeder gesperrte Slot macht den Wurf teurer.
	local cost     = CharmConfig.getRollCost(CharmConfig.countLocked(baerchi.charms))

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
	_canRoll = canRoll
	if _honey then
		-- Zahlen statt Saetze: das Bild hat nur Platz fuer kurze Beschriftungen
		local total = cost * CharmConfig.AUTO_ROLL_COUNT
		local ok    = Color3.fromRGB(255, 244, 214)
		if _costLabel then
			_costLabel.Text       = tostring(cost)
			_costLabel.TextColor3 = if gold >= cost then ok else Theme.COLORS.bad
		end
		if _autoCostLabel then
			_autoCostLabel.Text       = tostring(total)
			_autoCostLabel.TextColor3 = if gold >= total then ok else Theme.COLORS.bad
		end
		if _rollCover then _rollCover.Visible = not canRoll end
		if _autoCover then _autoCover.Visible = not canRoll end
		return
	end
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

-- Honig-UI (14.10.): Fenster = Bild "honey/charm_window" (zugeschnitten 1005 x 1489 Bildpixel).
-- Alle Masse unten sind Bildpixel (Original 1024 x 1536); hx/hy rechnen in Fenster-Einheiten um.
-- Kacheln (oben, 2 x 4) = Slots, Zeilen (unten, 8) = Effekt je Slot, goldener Knopf = Wuerfeln,
-- lila Knopf = Auto-Wurf. Die Klicks sitzen als durchsichtige Knoepfe auf den gemalten Elementen.
local WIN_W, WIN_H = 520, 770
local HS = WIN_W / 1005
local function hx(x: number): number return (x - 11) * HS end
local function hy(y: number): number return y * HS end
local function hplace(obj: GuiObject, x0: number, y0: number, x1: number, y1: number)
	obj.Position = UDim2.fromOffset(hx(x0), hy(y0))
	obj.Size     = UDim2.fromOffset((x1 - x0) * HS, (y1 - y0) * HS)
end

local INK        = Color3.fromRGB(255, 244, 214)
local INK_STROKE = Color3.fromRGB(58, 30, 8)

local TILE_X = { 196, 407, 619, 830 }
local TILE_Y = { 328, 526 }
local ROW_Y  = { 688, 760, 833, 906, 979, 1052, 1126, 1199 }

local function hlabel(parent: Instance, name: string, x0: number, y0: number, x1: number, y1: number,
	maxSize: number, align: Enum.TextXAlignment?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name                   = name
	label.BackgroundTransparency = 1
	label.Font                   = Theme.FONT
	label.Text                   = ""
	label.TextScaled             = true
	label.TextWrapped            = true
	label.TextColor3             = INK
	label.TextStrokeColor3       = INK_STROKE
	label.TextStrokeTransparency = 0.35
	label.TextXAlignment         = align or Enum.TextXAlignment.Left
	label.ZIndex                 = 6
	label.Active                 = false
	label.Parent                 = parent
	hplace(label, x0, y0, x1, y1)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize
	limit.MinTextSize = 7
	limit.Parent = label
	return label
end

local function hbutton(parent: Instance, name: string, x0: number, y0: number, x1: number, y1: number): TextButton
	local button = Instance.new("TextButton")
	button.Name                   = name
	button.BackgroundTransparency = 1
	button.Text                   = ""
	button.AutoButtonColor        = false
	button.ZIndex                 = 8
	button.Parent                 = parent
	hplace(button, x0, y0, x1, y1)
	return button
end

local function hframe(parent: Instance, name: string, x0: number, y0: number, x1: number, y1: number,
	color: Color3, transparency: number, radius: number, z: number): Frame
	local frame = Instance.new("Frame")
	frame.Name                   = name
	frame.BackgroundColor3       = color
	frame.BackgroundTransparency = transparency
	frame.BorderSizePixel        = 0
	frame.ZIndex                 = z
	frame.Active                 = false
	frame.Parent                 = parent
	hplace(frame, x0, y0, x1, y1)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius * HS)
	corner.Parent = frame
	return frame
end

local function buildHoney(root: Frame)
	local function toggleLock(slot: number)
		local uid = _openUid
		if not uid then return end
		Remotes.RequestToggleCharmLock:FireServer(uid, slot)
	end

	for slot = 1, CharmConfig.SLOT_COUNT do
		local col = (slot - 1) % 4 + 1
		local row = (slot - 1) // 4 + 1
		local cx, cy = TILE_X[col], TILE_Y[row]
		local ry = ROW_Y[slot]

		-- Kachel: Rarity-Flaeche + Buchstabe ueber der Silhouette, dunkle Abdeckung bis zur Freischaltung
		local cover = hframe(root, "Cover_" .. slot, cx - 92, cy - 85, cx + 92, cy + 85, Color3.fromRGB(30, 15, 5), 0.4, 18, 5)
		cover.Visible = false
		local tint = hframe(root, "Tint_" .. slot, cx - 56, cy - 56, cx + 56, cy + 56, Color3.new(1, 1, 1), 0.1, 20, 4)
		tint.Visible = false
		local letter = hlabel(root, "Letter_" .. slot, cx - 55, cy - 50, cx + 55, cy + 50, 44, Enum.TextXAlignment.Center)
		letter.TextStrokeTransparency = 1
		letter.ZIndex = 7

		local lockDot = hframe(root, "Lock_" .. slot, cx + 46, cy - 82, cx + 90, cy - 38, INK_STROKE, 0, 22, 9)
		lockDot.Visible = false
		local lockText = Instance.new("TextLabel")
		lockText.BackgroundTransparency = 1
		lockText.Size = UDim2.fromScale(1, 1)
		lockText.Font = Theme.FONT
		lockText.TextSize = 12
		lockText.TextColor3 = INK
		lockText.ZIndex = 10
		lockText.Parent = lockDot
		Loc.bind(lockText, "ui.charm.lock_letter")

		local tile = hbutton(root, "Slot_" .. slot, cx - 95, cy - 88, cx + 95, cy + 88)
		tile.Activated:Connect(function() toggleLock(slot) end)

		-- Zeile: Nummer im Kreis, Effekt im linken Balken, Rarity im rechten, Sperr-Zeichen im Sechseck
		local num = hlabel(root, "Num_" .. slot, 124, ry - 22, 168, ry + 22, 13, Enum.TextXAlignment.Center)
		num.Text = CharmConfig.SLOT_NUMERALS[slot]
		num.TextStrokeTransparency = 1

		local detail = hlabel(root, "Detail_" .. slot, 200, ry - 21, 486, ry + 21, 18, Enum.TextXAlignment.Left)
		local rarityText = hlabel(root, "Rarity_" .. slot, 606, ry - 21, 828, ry + 21, 17, Enum.TextXAlignment.Center)

		local lockMark = hlabel(root, "LockMark_" .. slot, 862, ry - 22, 908, ry + 22, 18, Enum.TextXAlignment.Center)
		Loc.bind(lockMark, "ui.charm.lock_letter")
		lockMark.TextColor3 = INK_STROKE
		lockMark.TextStrokeTransparency = 1
		lockMark.Visible = false

		local rowButton = hbutton(root, "Row_" .. slot, 108, ry - 32, 916, ry + 32)
		rowButton.Activated:Connect(function() toggleLock(slot) end)

		table.insert(_slots, {
			slot     = slot,
			button   = tile,
			letter   = letter,
			lockDot  = lockDot,
			detail   = detail,
			tint     = tint,
			cover    = cover,
			rarity   = rarityText,
			lockMark = lockMark,
		})
	end

	-- Unten: goldener Knopf (Wuerfeln, Preis rechts der Muenze), lila Knopf (Auto-Wurf, Gesamtpreis)
	local black = Color3.fromRGB(30, 15, 5)
	_rollCover = hframe(root, "RollCover", 150, 1290, 475, 1408, black, 0.45, 26, 5)
	_rollCover.Visible = false
	_autoCover = hframe(root, "AutoCover", 575, 1290, 868, 1408, black, 0.45, 26, 5)
	_autoCover.Visible = false

	local rollOne = hlabel(root, "RollCount", 168, 1318, 262, 1380, 24, Enum.TextXAlignment.Center)
	rollOne.Text = "x1"
	_costLabel = hlabel(root, "Cost", 380, 1318, 466, 1380, 24, Enum.TextXAlignment.Center)

	local autoCount = hlabel(root, "AutoCount", 592, 1318, 674, 1380, 24, Enum.TextXAlignment.Center)
	autoCount.Text = "x" .. CharmConfig.AUTO_ROLL_COUNT
	_autoCostLabel = hlabel(root, "AutoCost", 772, 1318, 862, 1380, 24, Enum.TextXAlignment.Center)

	local roll = hbutton(root, "Roll", 150, 1290, 475, 1408)
	_rollButton = roll
	roll.Activated:Connect(function()
		local uid = _openUid
		if not uid or not _canRoll then return end
		Remotes.RequestRollCharms:FireServer(uid, 1)
	end)

	local auto = hbutton(root, "AutoRoll", 575, 1290, 868, 1408)
	_autoButton = auto
	auto.Activated:Connect(function()
		local uid = _openUid
		if not uid or not _canRoll then return end
		Remotes.RequestRollCharms:FireServer(uid, CharmConfig.AUTO_ROLL_COUNT)
	end)
end

function CharmPanel.init(screenGui: ScreenGui)
	local honeyReady = FeatureFlags.isOn("UI_HONEY_SKIN") and Icons.hasUi("honey/charm_window")
	local root = Theme.dialog(
		"CharmPanel", screenGui,
		Vector2.new(0.50, 0.66),
		if honeyReady then Vector2.new(WIN_W, WIN_H) else Vector2.new(320, 420),
		if honeyReady then Vector2.new(WIN_W, WIN_H) else Vector2.new(560, 620)
	)
	_root = root
	_honey = honeyReady and Icons.honeyWindow(root, "honey/charm_window", WIN_W, WIN_H) ~= nil

	_titleLabel = Theme.dialogHeader(root, Loc.t("ui.card.section_charms"), function()
		PanelManager.close(PANEL_NAME)
	end)

	if _honey then
		-- Titel (Name + Promotion) in das Banner, Kreuz auf das Kreuz im Bild
		Icons.honeyHeader(root, Rect.new(hx(345), hy(125), hx(770), hy(192)), hx(920), hy(120), 96 * HS)
		local title = _titleLabel
		if title then
			local limit = Instance.new("UITextSizeConstraint")
			limit.MaxTextSize = 20
			limit.MinTextSize = 8
			limit.Parent = title
			title.TextScaled = true
		end
		buildHoney(root)
	end
	if not _honey then
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

	end -- not _honey

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
