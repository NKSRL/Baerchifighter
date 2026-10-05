--!strict
-- TopButtons.luau
-- StarterPlayerScripts/UI/TopButtons.luau
--
-- Einzige Zustaendigkeit:
--   - Die kleine Knopfreihe oben links rechts neben dem Zahnrad (Rueckmeldung
--     05.10.): Quests, dann Shop — alles in einer Zeile.
--
-- Die Quest-Karte (QuestTracker) steht nicht mehr dauerhaft im Bild; ihr
-- Zugang ist dieser Knopf. Ein rotes "!" zeigt, dass etwas abholbereit ist
-- (Kettenquest geschafft, Tagesquest fertig oder Login-Bonus offen) — dann
-- oeffnet der Knopf direkt das passende Fenster.
-- Der Shop-Knopf erscheint ueber UnlockRules ("tile_shop") und nur mit
-- FeatureFlags.SHOP_V1; sein "!" steht fuer den freien Gratis-Griff.
-- Rein lesend aus ClientState, kein eigenes Remote.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types        = require(ReplicatedStorage.Network.Types)
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)

local Theme        = require(script.Parent.Theme)
local PanelManager = require(script.Parent.PanelManager)
local Unlock       = require(script.Parent.Unlock)
local ClientState  = require(script.Parent.Parent.Controllers.ClientState)

local TopButtons = {}

-- Gleiche Zeile und Groesse wie das Zahnrad im Hud (x = 12, y = 106, 30 px)
local ROW_Y   = 106
local START_X = 12 + 30 + 8
local SIZE    = 30
local GAP     = 8

local _questButton: TextButton? = nil
local _questAlert: Frame?       = nil
local _shopButton: TextButton?  = nil
local _shopAlert: Frame?        = nil
local _bonusOpen = false
local _dailyReady = false

local function makeButton(screenGui: ScreenGui, name: string, symbol: string, index: number): (TextButton, Frame)
	local button = Theme.button(name, screenGui, symbol, Theme.COLORS.panelLight)
	button.AnchorPoint = Vector2.new(0, 0)
	button.Position    = UDim2.new(0.012, START_X + (index - 1) * (SIZE + GAP), 0, ROW_Y)
	button.Size        = UDim2.fromOffset(SIZE, SIZE)
	button.TextColor3  = Theme.COLORS.text
	button.TextXAlignment = Enum.TextXAlignment.Center

	local alert = Theme.panel("Alert", button, Theme.COLORS.bad)
	alert.AnchorPoint = Vector2.new(1, 0)
	alert.Position    = UDim2.new(1, 6, 0, -6)
	alert.Size        = UDim2.fromOffset(16, 16)
	alert.Visible     = false
	alert.ZIndex      = 4
	Theme.corner(alert, 8)
	local bang = Theme.label("Bang", alert, "!")
	bang.Size           = UDim2.fromScale(1, 1)
	bang.TextXAlignment = Enum.TextXAlignment.Center
	bang.ZIndex         = 5
	return button, alert
end

local function refresh(data: Types.PlayerDataUpdate)
	local questAlert = _questAlert
	local quests = data.quests
	if questAlert then
		local chainReady, dailyReady = false, false
		if quests then
			local chain = quests.chain
			chainReady = chain ~= nil and chain.progress >= chain.target
			for _, entry in quests.daily do
				if not entry.claimed and entry.progress >= entry.target then
					dailyReady = true
				end
			end
			_dailyReady = chainReady or dailyReady
		end
		_bonusOpen = data.daily ~= nil and data.daily.claimable
		questAlert.Visible = chainReady or dailyReady or _bonusOpen
	end

	local shopButton = _shopButton
	if shopButton then
		local enabled = FeatureFlags.isOn("SHOP_V1")
		if enabled then
			Unlock.apply("tile_shop", shopButton)
		else
			shopButton.Visible = false
		end
		local shopAlert = _shopAlert
		local shop = data.shop
		if shopAlert then
			shopAlert.Visible = enabled and shop ~= nil and shop.freeReady
		end
	end
end

function TopButtons.init(screenGui: ScreenGui)
	local questButton, questAlert = makeButton(screenGui, "QuestButton", "📜", 1)
	_questButton, _questAlert = questButton, questAlert
	questButton.Activated:Connect(function()
		-- Nur der Login-Bonus offen (keine Quest abholbereit): direkt dorthin
		PanelManager.toggle(if _bonusOpen and not _dailyReady then "DailyBonus" else "Quests")
	end)

	local shopButton, shopAlert = makeButton(screenGui, "ShopButton", "🛒", 2)
	_shopButton, _shopAlert = shopButton, shopAlert
	shopButton.Visible = false
	shopButton.Activated:Connect(function()
		Unlock.markSeen("tile_shop")
		PanelManager.toggle("Shop")
	end)

	ClientState.onChanged(refresh)
	local data = ClientState.get()
	if data then refresh(data) end
end

return TopButtons
