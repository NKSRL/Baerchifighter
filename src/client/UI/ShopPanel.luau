--!strict
-- ShopPanel.luau
-- StarterPlayerScripts/UI/ShopPanel.luau
--
-- Einzige Zustaendigkeit:
--   - Das Shop-Fenster (HBB Paket 10, FeatureFlags.SHOP_V1): Gratis-Griff
--     (einmal pro UTC-Tag GoldGummies) und Robux-Goldpakete.
--
-- Was abholbar ist, entscheidet der Server (PlayerDataUpdate.shop,
-- RequestClaimFreeGrab). Robux-Kaeufe startet der Client nur
-- (PromptProductPurchase); ausgezahlt wird ausschliesslich in
-- ShopService.processReceipt. Pakete mit productId 0 sind nicht eingerichtet
-- und erscheinen nicht.
--
-- Erklaert nebenbei, WOFUER GoldGummies sind (Playtest 05.10.: "keine Ahnung,
-- woher man die bekommt"): eine Zeile unter dem Gratis-Griff.

local Players            = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local TweenService       = game:GetService("TweenService")

local Types        = require(ReplicatedStorage.Network.Types)
local Remotes      = require(ReplicatedStorage.Network.Remotes)
local Loc          = require(ReplicatedStorage.Localization.Loc)
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)
local ShopConfig   = require(ReplicatedStorage.Config.ShopConfig)
local UnlockRules  = require(ReplicatedStorage.Modules.UnlockRules)

local Theme        = require(script.Parent.Theme)
local Icons        = require(script.Parent.Icons)
local PanelManager = require(script.Parent.PanelManager)
local ClientState  = require(script.Parent.Parent.Controllers.ClientState)

local ShopPanel = {}

local PANEL_NAME = "Shop"

local _root: Frame? = nil
local _freeButton: TextButton? = nil
local _freeStatus: TextLabel? = nil
local _pulse: Tween? = nil

local function refresh()
	local data = ClientState.get()
	local view: Types.ShopView? = if data then (data :: any).shop else nil
	local button, status = _freeButton, _freeStatus
	if not view or not button or not status then return end

	button.Text = if view.freeReady then Loc.t("ui.shop.free_claim") else Loc.t("ui.shop.free_taken")
	Theme.setEnabled(button, view.freeReady)
	status.Text = if view.freeReady
		then Loc.t("ui.shop.free_hint")
		else Loc.t("ui.shop.free_next", { time = Loc.formatDuration(view.nextFreeIn) })

	local pulse = _pulse
	if pulse then
		if view.freeReady then pulse:Play() else pulse:Cancel() end
	end
end

local function buildPack(parent: Instance, order: number, product: ShopConfig.Product)
	local card = Theme.panel("Pack_" .. product.key, parent, Theme.COLORS.panel)
	card.LayoutOrder = order
	card.Size = UDim2.new(1 / 3, -8, 1, 0)

	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0)
	holder.Position = UDim2.new(0.5, 0, 0, 8)
	holder.Size = UDim2.new(0.6, 0, 0.42, 0)
	holder.Parent = card
	local icon = Icons.make(holder, product.icon, "GG")
	icon.Size = UDim2.fromScale(1, 1)

	local amount = Theme.label("Amount", card, "+" .. Loc.formatNumber(product.gold))
	amount.AnchorPoint = Vector2.new(0.5, 0)
	amount.Position = UDim2.new(0.5, 0, 0.45, 8)
	amount.Size = UDim2.new(1, -8, 0, 22)
	amount.TextXAlignment = Enum.TextXAlignment.Center

	local buy = Theme.bigButton("Buy", card, Loc.t("ui.shop.buy"), Theme.COLORS.goldGummy)
	buy.AnchorPoint = Vector2.new(0.5, 1)
	buy.Position = UDim2.new(0.5, 0, 1, -8)
	buy.Size = UDim2.new(1, -16, 0, 34)
	buy.Activated:Connect(function()
		MarketplaceService:PromptProductPurchase(Players.LocalPlayer, product.productId)
	end)

	-- Preis in Robux aus dem Dashboard nachladen (massgeblich ist nur dieser)
	task.spawn(function()
		local ok, info = pcall(function()
			return MarketplaceService:GetProductInfo(product.productId, Enum.InfoType.Product)
		end)
		if ok and typeof(info) == "table" and typeof((info :: any).PriceInRobux) == "number" then
			buy.Text = "R$ " .. Loc.formatNumber((info :: any).PriceInRobux)
		end
	end)
end

function ShopPanel.init(screenGui: ScreenGui)
	if not FeatureFlags.isOn("SHOP_V1") then return end
	-- Shop-Kachel darf freigeschaltet werden (UnlockRules hat keine requires)
	UnlockRules.SHOP_ENABLED = true

	local root = Theme.dialog("ShopPanel", screenGui, Vector2.new(0.56, 0.6), Vector2.new(360, 340), Vector2.new(640, 480))
	_root = root

	Theme.dialogHeader(root, Loc.t("ui.shop.title"), function()
		PanelManager.close(PANEL_NAME)
	end)
	local body = Theme.dialogBody(root)

	-- Gratis-Griff: grosse Karte oben
	local free = Theme.panel("Free", body, Theme.COLORS.goldGummy)
	free.Size = UDim2.new(1, 0, 0.46, 0)
	Theme.gradient(free, Color3.fromRGB(255, 236, 160), Color3.fromRGB(255, 190, 60))
	local scale = Instance.new("UIScale")
	scale.Parent = free
	_pulse = TweenService:Create(scale, TweenInfo.new(0.8, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.03 })

	local giftHolder = Instance.new("Frame")
	giftHolder.BackgroundTransparency = 1
	giftHolder.Position = UDim2.new(0, 12, 0.1, 0)
	giftHolder.Size = UDim2.new(0.22, 0, 0.8, 0)
	giftHolder.Parent = free
	local gift = Icons.make(giftHolder, "gift", "🎁")
	gift.Size = UDim2.fromScale(1, 1)

	local freeTitle = Theme.label("Title", free, Loc.t("ui.shop.free_title", { n = ShopConfig.FREE_GRAB_GOLD }))
	freeTitle.Position = UDim2.new(0.27, 0, 0.08, 0)
	freeTitle.Size = UDim2.new(0.7, 0, 0.3, 0)
	freeTitle.TextColor3 = Theme.COLORS.outline

	local freeButton = Theme.bigButton("Claim", free, "", Theme.COLORS.good)
	freeButton.Position = UDim2.new(0.27, 0, 0.42, 0)
	freeButton.Size = UDim2.new(0.68, 0, 0.3, 0)
	freeButton.Activated:Connect(function()
		if not freeButton.Active then return end
		Remotes.RequestClaimFreeGrab:FireServer()
	end)
	_freeButton = freeButton

	local status = Theme.bodyText("Status", free, "")
	status.Position = UDim2.new(0.27, 0, 0.76, 0)
	status.Size = UDim2.new(0.7, 0, 0.22, 0)
	status.TextColor3 = Theme.COLORS.outline
	status.TextSize = 12
	_freeStatus = status

	-- Robux-Pakete (nur eingerichtete)
	local live: { ShopConfig.Product } = {}
	for _, product in ShopConfig.PRODUCTS do
		if product.productId ~= 0 then table.insert(live, product) end
	end
	if #live > 0 then
		local row = Theme.container("Packs", body)
		row.Position = UDim2.new(0, 0, 0.5, 0)
		row.Size = UDim2.new(1, 0, 0.5, 0)
		local layout = Theme.listLayout(row, 8, true)
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		for order, product in live do
			buildPack(row, order, product)
		end
	else
		local soon = Theme.bodyText("Soon", body, Loc.t("ui.shop.more_soon"))
		soon.Position = UDim2.new(0, 0, 0.54, 0)
		soon.Size = UDim2.new(1, 0, 0, 40)
		soon.TextXAlignment = Enum.TextXAlignment.Center
	end

	PanelManager.register(PANEL_NAME, {
		open = function()
			root.Visible = true
			refresh()
		end,
		close = function()
			root.Visible = false
			local pulse = _pulse
			if pulse then pulse:Cancel() end
		end,
	})

	ClientState.onChanged(function()
		if root.Visible then refresh() end
	end)

	print("[ShopPanel] Initialisiert | Pakete:", #live)
end

return ShopPanel
