--!strict
-- HudRow.luau
-- StarterPlayerScripts/UI/HudRow.luau
--
-- Einzige Zustaendigkeit:
--   - Die Knopf-Zeile oben links (FeatureFlags.HUD_ROW_V2): Zahnrad, Quests,
--     Shop — alles nebeneinander in einer Zeile.
--
-- Wunsch Projektinhaber 05.10.: Die Quest-Karte muss nicht die ganze Zeit
-- sichtbar sein; ein kleiner Knopf rechts neben den Einstellungen reicht, und
-- der Shop sitzt rechts daneben (statt in der Kachelleiste rechts).
--
-- Das Zahnrad baut weiterhin Hud (Sprache); hier wird es nur in die Zeile
-- gehaengt. Die Quest-Karte (QuestTracker) bleibt gebaut, ist aber versteckt —
-- ihr Belohnungs-Toast laeuft weiter. Ein rotes "!" an den Knoepfen zeigt,
-- dass etwas abholbereit ist.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types        = require(ReplicatedStorage.Network.Types)
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)

local Theme        = require(script.Parent.Theme)
local Icons        = require(script.Parent.Icons)
local PanelManager = require(script.Parent.PanelManager)
local Unlock       = require(script.Parent.Unlock)
local ClientState  = require(script.Parent.Parent.Controllers.ClientState)

local HudRow = {}

local SIZE = 38
local GAP  = 6

type Button = { button: TextButton, alert: Frame }
local _quests: Button? = nil
local _shop: Button? = nil

local function makeAlert(parent: GuiObject): Frame
	local alert = Theme.panel("Alert", parent, Theme.COLORS.bad)
	alert.AnchorPoint = Vector2.new(1, 0)
	alert.Position    = UDim2.new(1, 6, 0, -6)
	alert.Size        = UDim2.fromOffset(18, 18)
	alert.Visible     = false
	alert.ZIndex      = 6
	Theme.corner(alert, 9)
	local bang = Theme.label("Bang", alert, "!")
	bang.Size           = UDim2.fromScale(1, 1)
	bang.TextXAlignment = Enum.TextXAlignment.Center
	bang.ZIndex         = 7
	return alert
end

local function makeButton(parent: Instance, name: string, order: number, icon: string, fallback: string, color: Color3, onClick: () -> ()): Button
	local button = Theme.button(name, parent, fallback, color)
	button.Size        = UDim2.fromOffset(SIZE, SIZE)
	button.LayoutOrder = order
	button.TextColor3  = Theme.COLORS.outline
	if Icons.has(icon) then
		button.Text = ""
		local image = Icons.make(button, icon)
		image.AnchorPoint = Vector2.new(0.5, 0.5)
		image.Position    = UDim2.fromScale(0.5, 0.5)
		image.Size        = UDim2.fromScale(0.82, 0.82)
		image.ZIndex      = 3
	end
	button.Activated:Connect(onClick)
	return { button = button, alert = makeAlert(button) }
end

local function questsReady(data: Types.PlayerDataUpdate): boolean
	local quests = (data :: any).quests
	if not quests then return false end
	local chain = quests.chain
	if chain and chain.progress >= chain.target then return true end
	for _, entry in quests.daily or {} do
		if not entry.claimed and entry.progress >= entry.target then return true end
	end
	return false
end

local function refresh(data: Types.PlayerDataUpdate)
	local quests = _quests
	if quests then
		quests.alert.Visible = questsReady(data)
	end
	local shop = _shop
	if shop then
		Unlock.apply("tile_shop", shop.button)
		local view = (data :: any).shop
		shop.alert.Visible = Unlock.isNew("tile_shop") or (view ~= nil and view.freeReady == true)
	end
end

function HudRow.init(screenGui: ScreenGui)
	if not FeatureFlags.isOn("HUD_ROW_V2") then return end

	local row = Theme.container("HudRow", screenGui)
	-- Gleiche Stelle wie vorher das Zahnrad (Hud), Pixel-Offset wie dort.
	row.Position = UDim2.new(0.012, 12, 0, 106)
	row.Size     = UDim2.fromOffset(SIZE * 3 + GAP * 2 + 8, SIZE)
	local layout = Instance.new("UIListLayout")
	layout.FillDirection     = Enum.FillDirection.Horizontal
	layout.Padding           = UDim.new(0, GAP)
	layout.SortOrder         = Enum.SortOrder.LayoutOrder
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent            = row

	-- 1) Zahnrad aus dem Hud in die Zeile holen
	local gear = screenGui:FindFirstChild("Language")
	if gear and gear:IsA("GuiObject") then
		gear.Parent      = row
		gear.Size        = UDim2.fromOffset(SIZE, SIZE)
		gear.LayoutOrder = 1
	end

	-- 2) Quests
	_quests = makeButton(row, "QuestButton", 2, "scroll", "📜", Theme.COLORS.panelLight, function()
		PanelManager.toggle("Quests")
	end)

	-- 3) Shop (erscheint wie die alte Kachel erst ab der 2. Sitzung, UnlockRules)
	if FeatureFlags.isOn("SHOP_V1") then
		_shop = makeButton(row, "ShopButton", 3, "goldgummy", "GG", Theme.COLORS.goldGummy, function()
			Unlock.markSeen("tile_shop")
			PanelManager.toggle("Shop")
		end)
	end

	-- Quest-Karte verstecken (sie bleibt fuer ihre Toasts gebaut)
	local card = screenGui:FindFirstChild("QuestTracker")
	if card and card:IsA("GuiObject") then
		card.Visible = false
	end

	ClientState.onChanged(refresh)
	PanelManager.onOpened(function(name)
		if name == "Shop" then Unlock.markSeen("tile_shop") end
	end)
end

return HudRow
