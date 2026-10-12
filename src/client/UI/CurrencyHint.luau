--!strict
-- CurrencyHint.luau
-- StarterPlayerScripts/UI/CurrencyHint.luau
--
-- Einzige Zustaendigkeit:
--   - Einmal erklaeren, wofuer eine Waehrung gut ist (Sammel-Update 05.10.,
--     Paket 3.4): beim ersten Gummy-Gewinn und bei den ersten GoldGummies ein
--     Satz in einer Sprechblase an der Waehrungs-Pille, mit Pfeil darauf.
--
-- Keine Textwand: ein Satz, ein Pfeil, Tippen oder 8 Sekunden schliessen.
-- Gemerkt wird ueber uiSeen ("hint_gummies" / "hint_gold", UiStateService),
-- damit der Hinweis nur einmal pro Konto kommt. Veteranen (GuideSteps)
-- bekommen ihn nicht.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loc        = require(ReplicatedStorage.Localization.Loc)
local GuideSteps = require(ReplicatedStorage.Modules.GuideSteps)

local Theme       = require(script.Parent.Theme)
local UiScale     = require(script.Parent.UiScale)
local Hud         = require(script.Parent.Hud)
local Unlock      = require(script.Parent.Unlock)
local ClientState = require(script.Parent.Parent.Controllers.ClientState)

local CurrencyHint = {}

local SHOW_SECONDS = 8
local START_GUMMIES = 100   -- Startbestand (Types.createDefaultPlayerData): erst ein GEWINN zaehlt

local _bubble: Frame? = nil
local _text: TextLabel? = nil
local _shownSession: { [string]: boolean } = {}

local function show(kind: string, key: string)
	local bubble, text = _bubble, _text
	local anchor = Hud.getPillAnchor(kind)
	if not bubble or not text or not anchor then return end
	text.Text = "⬆ " .. Loc.t(key)
	-- Bildschirm-Pixel -> Oberflaechen-Einheiten (globale UiScale)
	local pos, size = UiScale.toGui(anchor.AbsolutePosition), UiScale.toGui(anchor.AbsoluteSize)
	bubble.Position = UDim2.fromOffset(pos.X, pos.Y + size.Y + 10)
	bubble.Visible = true
	local token = os.clock()
	bubble:SetAttribute("Token", token)
	task.delay(SHOW_SECONDS, function()
		if bubble:GetAttribute("Token") == token then bubble.Visible = false end
	end)
end

local function check()
	local data = ClientState.get()
	if not data or GuideSteps.isVeteran(data :: any) then return end
	local seen = (data :: any).uiSeen or {}
	if not seen.hint_gummies and not _shownSession.hint_gummies and data.gummies > START_GUMMIES then
		_shownSession.hint_gummies = true
		Unlock.markSeen("hint_gummies")
		show("gummies", "hint.gummies")
	elseif not seen.hint_gold and not _shownSession.hint_gold and data.goldGummies > 0 then
		_shownSession.hint_gold = true
		Unlock.markSeen("hint_gold")
		show("goldGummies", "hint.gold")
	end
end

function CurrencyHint.init(screenGui: ScreenGui)
	local bubble = Theme.panel("CurrencyHint", screenGui, Theme.COLORS.panelDeep)
	bubble.Size = UDim2.fromOffset(300, 56)
	bubble.Visible = false
	bubble.ZIndex = 45
	local text = Theme.bodyText("Text", bubble, "")
	text.Position = UDim2.fromOffset(10, 4)
	text.Size = UDim2.new(1, -20, 1, -8)
	text.TextColor3 = Theme.COLORS.goldGummy
	text.ZIndex = 46
	local hit = Instance.new("TextButton")
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 47
	hit.Parent = bubble
	hit.Activated:Connect(function() bubble.Visible = false end)
	_bubble, _text = bubble, text

	ClientState.onChanged(check)
end

return CurrencyHint
