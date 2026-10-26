--!strict
-- MerchantPanel.luau
-- StarterPlayerScripts/UI/MerchantPanel.luau
--
-- Einzige Zustaendigkeit:
--   - Das Haendler-Fenster (26.10., FeatureFlags.POTIONS_V1): bis zu sechs
--     Angebote — das Basis-Ei als fester erster Platz und die Traenke des
--     aktuellen Loses — mit Preis, Wirkung, Stapel-Stand und der Zeit bis zum
--     naechsten Sortiment.
--
-- Oeffnet sich NUR auf Zuruf des Servers (MerchantViewReceived mit open =
-- true, nachdem der Spieler am Regal des Ei-Haendlers gedrueckt hat). Was im
-- Regal steht, was es kostet und ob ein Kauf verlaengert, ersetzt oder
-- abgelehnt wird, entscheidet der Server (PotionService) — dieses Fenster
-- zeigt nur die zuletzt erhaltene Sicht und schickt Kaufwuensche mit dem
-- Zeitfenster der Sicht zurueck. Der Countdown laeuft lokal (eine Sekunde
-- Takt, nur solange das Fenster offen ist); laeuft er ab, wird die Sicht neu
-- angefragt (der Server schickt sie beim Wechsel ohnehin an alle).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types        = require(ReplicatedStorage.Network.Types)
local Remotes      = require(ReplicatedStorage.Network.Remotes)
local Loc          = require(ReplicatedStorage.Localization.Loc)
local Names        = require(ReplicatedStorage.Localization.Names)
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)
local PotionConfig = require(ReplicatedStorage.Config.PotionConfig)
local PotionRules  = require(ReplicatedStorage.Modules.PotionRules)

local Theme        = require(script.Parent.Theme)
local Icons        = require(script.Parent.Icons)
local PanelManager = require(script.Parent.PanelManager)
local ClientState  = require(script.Parent.Parent.Controllers.ClientState)

local MerchantPanel = {}

local PANEL_NAME = "Merchant"
local CARD_H = 168

local _root: Frame? = nil
local _grid: ScrollingFrame? = nil
local _rotateLabel: TextLabel? = nil
local _offersLabel: TextLabel? = nil
local _view: Types.MerchantView? = nil
-- os.clock(), zu dem das Sortiment wechselt (aus view.rotatesIn beim Empfang)
local _rotateAt = 0
local _requested = false
local _honey = false

--------------------------------------------------------------------------------
-- Hilfen
--------------------------------------------------------------------------------

-- Laufender Effekt dieser Sorte aus dem Datenstand (Restzeit ab Empfang)
local function activeOf(kind: string): (number?, number?)
	local data = ClientState.get()
	local list = if data then (data :: any).potions else nil
	if typeof(list) ~= "table" then return nil end
	for _, view in list do
		if view.kind == kind then
			return view.multiplier, view.remaining
		end
	end
	return nil, nil
end

local function statusText(def: PotionConfig.PotionDef, action: string): (string, Color3)
	local activeMult, activeLeft = activeOf(def.kind)
	if action == PotionRules.WEAKER then
		return Loc.t("ui.potion.weaker"), Theme.COLORS.bad
	elseif action == PotionRules.MAXTIME then
		return Loc.t("ui.potion.maxtime", { time = Loc.formatDuration(PotionConfig.MAX_REMAINING_SECONDS) }), Theme.COLORS.bad
	elseif action == PotionRules.EXTEND then
		return Loc.t("ui.potion.extend", { time = Loc.formatDuration(def.durationSeconds) }), Theme.COLORS.good
	elseif action == PotionRules.REPLACE and activeMult and activeLeft then
		return Loc.t("ui.potion.replace"), Theme.COLORS.goldGummy
	end
	if activeMult and activeLeft then
		return Loc.t("ui.potion.active", { mult = activeMult, time = Loc.formatDuration(activeLeft) }), Theme.COLORS.accent
	end
	return "", Theme.COLORS.textDim
end

--------------------------------------------------------------------------------
-- Karten
--------------------------------------------------------------------------------

type CardSpec = {
	name     : string,
	icon     : GuiObject?,
	iconName : string?,
	glyph    : string,
	color    : Color3,
	title    : string,
	effect   : string,
	desc     : string,
	status   : string,
	statusColor : Color3,
	price    : number,
	enabled  : boolean,
	onBuy    : () -> (),
}

local function buildCard(parent: Instance, order: number, spec: CardSpec)
	local card = Theme.panel(spec.name, parent, Theme.COLORS.panel)
	card.LayoutOrder = order

	-- Farbstreifen oben in der Trank-Farbe
	local band = Instance.new("Frame")
	band.Name = "Band"
	band.BackgroundColor3 = spec.color
	band.BorderSizePixel = 0
	band.Position = UDim2.new(0, 6, 0, 5)
	band.Size = UDim2.new(1, -12, 0, 6)
	band.ZIndex = 2
	band.Parent = card
	Theme.corner(band, 3)

	local holder = Theme.container("IconHolder", card)
	holder.Position = UDim2.fromOffset(8, 14)
	holder.Size = UDim2.fromOffset(40, 40)
	local icon = Icons.make(holder, spec.iconName or "", spec.glyph)
	icon.Size = UDim2.fromScale(1, 1)

	local title = Theme.label("Title", card, spec.title)
	title.Position = UDim2.new(0, 54, 0, 14)
	title.Size = UDim2.new(1, -62, 0, 22)
	title.TextXAlignment = Enum.TextXAlignment.Left

	local effect = Theme.bodyText("Effect", card, spec.effect)
	effect.Position = UDim2.new(0, 54, 0, 36)
	effect.Size = UDim2.new(1, -62, 0, 18)
	effect.TextSize = 13
	effect.TextColor3 = Theme.COLORS.text

	local desc = Theme.bodyText("Desc", card, spec.desc)
	desc.Position = UDim2.new(0, 8, 0, 60)
	desc.Size = UDim2.new(1, -16, 0, 34)
	desc.TextSize = 12

	local status = Theme.bodyText("Status", card, spec.status)
	status.Position = UDim2.new(0, 8, 0, 96)
	status.Size = UDim2.new(1, -16, 0, 18)
	status.TextSize = 12
	status.TextColor3 = spec.statusColor
	status.TextYAlignment = Enum.TextYAlignment.Center

	local buy = Theme.bigButton("Buy", card, Loc.t("ui.potion.buy", { n = spec.price }), Theme.COLORS.gummy)
	buy.AnchorPoint = Vector2.new(0.5, 1)
	buy.Position = UDim2.new(0.5, 0, 1, -8)
	buy.Size = UDim2.new(1, -16, 0, 36)
	Theme.setEnabled(buy, spec.enabled)
	buy.Activated:Connect(function()
		if not buy.Active then return end
		spec.onBuy()
	end)
end

local function rebuild()
	local grid = _grid
	local view = _view
	if not grid then return end
	for _, child in grid:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	if not view then return end

	-- 1. Platz: das Basis-Ei (immer da)
	buildCard(grid, 1, {
		name = "Card_Egg",   -- ui-ok: Instanzname, kein Text
		iconName = "egg",    -- ui-ok: Bildname aus UI/Icons
		glyph = "🥚",
		color = Theme.COLORS.cream,
		title = Names.egg(view.eggType),
		effect = Loc.t("ui.merchant.always"),
		desc = Names.eggDesc(view.eggType),
		status = "",
		statusColor = Theme.COLORS.textDim,
		price = view.eggPrice,
		enabled = true,
		onBuy = function()
			Remotes.RequestMerchantBuy:FireServer("egg")
		end,
	})

	-- 2..6: die Traenke des Loses
	for _, offer in view.offers do
		local def = PotionConfig.byId(offer.potionId)
		if def then
			local status, statusColor = statusText(def, offer.action)
			local potionId = offer.potionId
			local window = view.window
			buildCard(grid, 1 + offer.slot, {
				name = "Card_" .. potionId,   -- ui-ok: Instanzname, kein Text
				glyph = PotionConfig.GLYPH[def.kind] or "?",
				color = def.color,
				title = Names.potion(potionId),
				effect = Loc.t("ui.potion.effect", { mult = def.multiplier, time = Loc.formatDuration(def.durationSeconds) }),
				desc = Names.potionDesc(potionId),
				status = status,
				statusColor = statusColor,
				price = offer.price,
				enabled = offer.action ~= PotionRules.WEAKER and offer.action ~= PotionRules.MAXTIME,
				onBuy = function()
					Remotes.RequestMerchantBuy:FireServer("potion", potionId, window)
				end,
			})
		end
	end

	local offers = _offersLabel
	if offers then
		offers.Text = Loc.t("ui.merchant.offers", { n = #view.offers, max = PotionConfig.MERCHANT.SLOTS_MAX })
	end
end

-- Countdown bis zum Wechsel: nur bei voller Sekunde neu schreiben
local _lastShown = -1
local function tickRotate()
	local label = _rotateLabel
	if not label or not _view then return end
	local left = math.max(0, math.ceil(_rotateAt - os.clock()))
	if left ~= _lastShown then
		_lastShown = left
		label.Text = Loc.t("ui.merchant.rotates_in", { time = Loc.formatDuration(left) })
	end
	if left <= 0 and not _requested then
		_requested = true
		Remotes.RequestMerchantView:FireServer()
	end
end

local function runCountdown(root: Frame)
	task.spawn(function()
		while root.Visible do
			tickRotate()
			task.wait(1)
		end
	end)
end

local function receive(view: Types.MerchantView, open: boolean)
	_view = view
	_rotateAt = os.clock() + math.max(0, view.rotatesIn)
	_requested = false
	_lastShown = -1
	local root = _root
	if not root then return end
	if open then
		PanelManager.open(PANEL_NAME)
	elseif root.Visible then
		rebuild()
		tickRotate()
	end
end

--------------------------------------------------------------------------------
-- Aufbau
--------------------------------------------------------------------------------

function MerchantPanel.init(screenGui: ScreenGui)
	if not FeatureFlags.isOn("POTIONS_V1") then return end

	local root = Theme.dialog("MerchantPanel", screenGui, Vector2.new(0.62, 0.66), Vector2.new(400, 340), Vector2.new(720, 520))
	_root = root

	-- 14.10. (UI_HONEY_SKIN): dasselbe Fenster-Bild wie der Shop (shop_window, 900 x 600)
	_honey = Icons.honeyWindow(root, "honey/shop_window", 900, 600) ~= nil

	Theme.dialogHeader(root, Loc.t("ui.merchant.title"), function()
		PanelManager.close(PANEL_NAME)
	end)
	local body = Theme.dialogBody(root)
	if _honey then
		Icons.honeyHeader(root, Rect.new(82, 41, 797, 105), 837, 55, 58)
		body.Position = UDim2.fromOffset(70, 125)
		body.Size     = UDim2.fromOffset(765, 385)
	end

	-- Kopfzeile: Zeit bis zum Wechsel links, Platzzahl rechts
	local rotate = Theme.label("RotatesIn", body, "")
	rotate.Position = UDim2.new(0, 0, 0, 0)
	rotate.Size = UDim2.new(0.6, 0, 0, 24)
	_rotateLabel = rotate

	local offers = Theme.bodyText("Offers", body, "")
	offers.AnchorPoint = Vector2.new(1, 0)
	offers.Position = UDim2.new(1, 0, 0, 4)
	offers.Size = UDim2.new(0.4, 0, 0, 20)
	offers.TextXAlignment = Enum.TextXAlignment.Right
	_offersLabel = offers
	if _honey then
		rotate.TextColor3 = Color3.fromRGB(110, 70, 36)
		offers.TextColor3 = Color3.fromRGB(122, 84, 53)
	end

	-- Raster mit bis zu sechs Karten (3 x 2), scrollbar fuer kleine Fenster
	local grid = Theme.scroller("Grid", body)
	grid.Position = UDim2.new(0, 0, 0, 30)
	grid.Size = UDim2.new(1, 0, 1, -30)
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(1 / 3, -10, 0, CARD_H)
	layout.CellPadding = UDim2.fromOffset(8, 8)
	layout.FillDirectionMaxCells = 3
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	layout.Parent = grid
	_grid = grid

	PanelManager.register(PANEL_NAME, {
		open = function()
			root.Visible = true
			rebuild()
			tickRotate()
			runCountdown(root)
		end,
		close = function()
			root.Visible = false
		end,
	})

	Remotes.MerchantViewReceived.OnClientEvent:Connect(function(view: any, open: any)
		if typeof(view) ~= "table" or typeof(view.offers) ~= "table" then return end
		receive(view :: Types.MerchantView, open == true)
	end)

	-- Stapel-Stand der Karten haengt am Datenstand (laufende Traenke)
	ClientState.onChanged(function()
		if root.Visible then rebuild() end
	end)
	Loc.onChanged(function()
		if root.Visible then
			rebuild()
			_lastShown = -1
			tickRotate()
		end
	end)

	print("[MerchantPanel] Initialisiert")
end

return MerchantPanel
