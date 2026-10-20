--!strict
-- PetSellConfirm.luau
-- StarterPlayerScripts/UI/PetSellConfirm.luau
--
-- Einzige Zustaendigkeit:
--   - Das kleine Bestaetigungsfenster vor dem endgueltigen Verkaufen:
--     "Willst du wirklich N Baerchis verkaufen?" (+ Warnzeile bei seltenen)
--
-- Es ist KEIN Panel im PanelManager: das Baerchis-Menue bleibt dahinter offen.
-- Ja ruft den uebergebenen Callback; Nein, X, Escape und ein Klick daneben
-- schliessen NUR dieses Fenster — Verkaufsmodus und Markierung bleiben, weil der
-- Besitzer (BaerchiInventory) sie haelt. Es gibt zum Verkaufen selbst keine
-- Spiellogik hier, der Server prueft alles neu.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Loc = require(ReplicatedStorage.Localization.Loc)

local Theme       = require(script.Parent.Theme)
local Icons       = require(script.Parent.Icons)
local HoneyButton = require(script.Parent.HoneyButton)

local PetSellConfirm = {}

export type Info = {
	count : number,   -- wie viele Baerchis verkauft werden
	rare  : number,   -- davon selten (ab PetLimitConfig.SELL_WARN_MIN_RARITY)
}

-- Honig-Fenster (wie RebirthDialog): daily_window, 660 x 440
local WIN_W, WIN_H = 660, 440
local BTN_W, BTN_H = 236, 61   -- Seitenverhaeltnis der Standard-Knoepfe (~3,85)

local _backdrop: TextButton? = nil
local _root: Frame? = nil
local _text: TextLabel? = nil
local _rareLabel: TextLabel? = nil
local _yes: HoneyButton.Handle? = nil
local _no: HoneyButton.Handle? = nil
local _onYes: (() -> ())? = nil
local _info: Info = { count = 0, rare = 0 }
local _escape: RBXScriptConnection? = nil

local function fill()
	local text = _text
	if text then
		text.Text = Loc.tn("ui.pets.sell.confirm_text", _info.count)
	end
	local rare = _rareLabel
	if rare then
		rare.Visible = _info.rare > 0
		if _info.rare > 0 then
			rare.Text = "⚠ " .. Loc.tn("ui.pets.sell.confirm_rare", _info.rare)
		end
	end
	if _yes then (_yes :: HoneyButton.Handle).setText(Loc.t("ui.pets.sell.confirm_yes")) end
	if _no then (_no :: HoneyButton.Handle).setText(Loc.t("ui.pets.sell.confirm_no")) end
end

function PetSellConfirm.isOpen(): boolean
	return _root ~= nil and (_root :: Frame).Visible
end

function PetSellConfirm.close()
	_onYes = nil
	local escape = _escape
	if escape then
		escape:Disconnect()
		_escape = nil
	end
	if _root then (_root :: Frame).Visible = false end
	if _backdrop then (_backdrop :: TextButton).Visible = false end
end

-- Oeffnet das Fenster. `onYes` laeuft nur bei "Ja".
function PetSellConfirm.open(info: Info, onYes: () -> ())
	local root = _root
	local backdrop = _backdrop
	if not root or not backdrop then return end

	_info = info
	_onYes = onYes
	fill()
	backdrop.Visible = true
	root.Visible = true

	-- Escape schliesst nur dieses Fenster. Die Verbindung gibt close() wieder frei.
	if _escape == nil then
		_escape = UserInputService.InputBegan:Connect(function(input: InputObject)
			if input.KeyCode == Enum.KeyCode.Escape then
				PetSellConfirm.close()
			end
		end)
	end
end

function PetSellConfirm.init(screenGui: ScreenGui)
	-- Abdunkelung hinter dem Fenster: faengt den Klick "daneben" ab, ohne dass er
	-- das Baerchis-Menue dahinter trifft (ein Klick darauf ist verarbeitet).
	local backdrop = Instance.new("TextButton")
	backdrop.Name                   = "PetSellConfirmBackdrop"
	backdrop.AutoButtonColor        = false
	backdrop.Text                   = ""
	backdrop.BackgroundColor3       = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel        = 0
	backdrop.Size                   = UDim2.fromScale(1, 1)
	backdrop.ZIndex                 = 18
	backdrop.Visible                = false
	backdrop.Parent                 = screenGui
	backdrop.Activated:Connect(PetSellConfirm.close)
	_backdrop = backdrop

	local root = Theme.dialog(
		"PetSellConfirm", screenGui,
		Vector2.new(0.5, 0.4),
		Vector2.new(300, 240),
		Vector2.new(520, 320)
	)
	_root = root
	-- Ueber dem Abdunkler (18) UND ueber dem Honig-Menue (BaerchiInventorySkin, 10);
	-- Theme.dialog setzt 10, dann wuerde das Menue den Dialog verdecken.
	root.ZIndex = 20

	local honey = Icons.honeyWindow(root, "honey/daily_window", WIN_W, WIN_H) ~= nil

	local title = Theme.dialogHeader(root, "", PetSellConfirm.close)
	Loc.bind(title, "ui.pets.sell.confirm_title")

	local body = Theme.dialogBody(root)
	if honey then
		Icons.honeyHeader(root, Rect.new(60, 30, 584, 77), 614, 40, 44)
		body.Position = UDim2.fromOffset(58, 100)
		body.Size     = UDim2.fromOffset(544, 250)
	end

	local text = Theme.bodyText("Text", body, "")
	text.Position       = UDim2.new(0, 0, 0, 0)
	text.Size           = UDim2.new(1, 0, 0, if honey then 100 else 90)
	text.TextScaled     = false
	text.TextSize       = if honey then 24 else 20
	text.TextWrapped    = true
	text.TextXAlignment = Enum.TextXAlignment.Center
	text.TextYAlignment = Enum.TextYAlignment.Center
	if honey then text.TextColor3 = Theme.COLORS.cream end
	_text = text

	local rare = Theme.label("Rare", body, "")
	rare.Position       = UDim2.new(0, 0, 0, if honey then 104 else 94)
	rare.Size           = UDim2.new(1, 0, 0, 34)
	rare.TextScaled     = false
	rare.TextSize       = if honey then 22 else 18
	rare.TextXAlignment = Enum.TextXAlignment.Center
	rare.TextColor3     = Theme.COLORS.goldGummy
	rare.Visible        = false
	Theme.outlineText(rare, 2)
	_rareLabel = rare

	-- Nein links, Ja rechts. Die Reihenfolge ist auf dem Handy wie am PC gleich.
	local no = HoneyButton.make(body, "No", Loc.t("ui.pets.sell.confirm_no"), "dark", Theme.COLORS.panelLight)
	no.holder.AnchorPoint = Vector2.new(0, 1)
	no.holder.Position    = UDim2.new(0, 0, 1, 0)
	no.holder.Size        = if honey then UDim2.fromOffset(BTN_W, BTN_H) else UDim2.new(0.5, -6, 0, 40)
	no.button.Activated:Connect(PetSellConfirm.close)
	_no = no

	local yes = HoneyButton.make(body, "Yes", Loc.t("ui.pets.sell.confirm_yes"), "light", Theme.COLORS.bad)
	yes.holder.AnchorPoint = Vector2.new(1, 1)
	yes.holder.Position    = UDim2.new(1, 0, 1, 0)
	yes.holder.Size        = if honey then UDim2.fromOffset(BTN_W, BTN_H) else UDim2.new(0.5, -6, 0, 40)
	yes.button.Activated:Connect(function()
		local callback = _onYes
		PetSellConfirm.close()
		if callback then callback() end
	end)
	_yes = yes

	Loc.onChanged(function()
		if PetSellConfirm.isOpen() then fill() end
	end)
end

return PetSellConfirm
