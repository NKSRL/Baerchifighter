--!strict
-- RebirthButton.luau
-- StarterPlayerScripts/UI/RebirthButton.luau
--
-- Einzige Zustaendigkeit:
--   - Der feste Rebirth-Knopf unten rechts: immer an derselben Stelle,
--     unsichtbar bis zur ersten Rebirth-Moeglichkeit, dann mit Pop-in.
--
-- Kontext: Sammel-Update 05.10., Paket 2.7 ("Rebirth Button muss fixiert
-- sein. Ab der ersten Rebirth-Moeglichkeit erst."). Die Rebirth-Pille oben
-- rechts (Multiplikator) bleibt als zweiter Weg bestehen; dieser Knopf ist
-- der, den man nicht suchen muss.
--
-- Sichtbar ab: erste Rebirth-Bedingung erfuellt (Paket 4.1,
-- TowerConfig.isRebirthReady) ODER schon einmal rebirthed. Danach bleibt er
-- stehen; leuchtet nur, wenn ein Rebirth gerade moeglich ist. Die Wahrheit
-- (darf ich?) entscheidet weiterhin der Server (RebirthService).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local Loc         = require(ReplicatedStorage.Localization.Loc)
local TowerConfig = require(ReplicatedStorage.Config.TowerConfig)

local Theme        = require(script.Parent.Theme)
local PanelManager = require(script.Parent.PanelManager)
local ClientState  = require(script.Parent.Parent.Controllers.ClientState)

local RebirthButton = {}

local SIZE        = Vector2.new(132, 56)
local MARGIN      = 16
local GLOW_PERIOD = 1.2

local _button: TextButton? = nil
local _shown = false
local _glow: UIStroke? = nil
local _glowTween: Tween? = nil

-- Darf der Spieler gerade rebirthen? (gleiche Regel wie der Server)
local function isReady(data: any): boolean
	return TowerConfig.isRebirthReady(data.rebirthCount or 0, data.island.stageBest, data.towers and data.towers.records)
end

local function popIn(button: TextButton)
	local scale = button:FindFirstChild("PopScale") :: UIScale?
	if not scale then
		local created = Instance.new("UIScale")
		created.Name = "PopScale"
		created.Parent = button
		scale = created
	end
	local uiScale = scale :: UIScale
	uiScale.Scale = 0.2
	TweenService:Create(uiScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function setGlow(on: boolean)
	local glow = _glow
	if not glow then return end
	if _glowTween then
		_glowTween:Cancel()
		_glowTween = nil
	end
	if on then
		glow.Transparency = 0
		local tween = TweenService:Create(glow,
			TweenInfo.new(GLOW_PERIOD * 0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Transparency = 0.8 })
		tween:Play()
		_glowTween = tween
	else
		glow.Transparency = 1
	end
end

local function refresh()
	local button = _button
	if not button then return end
	local data = ClientState.get()
	if not data then
		button.Visible = false
		return
	end

	local ready = isReady(data)
	local show = ready or (data.rebirthCount or 0) >= 1
	button.Visible = show
	if show and not _shown then
		popIn(button)
	end
	_shown = show
	setGlow(ready)
end

function RebirthButton.init(screenGui: ScreenGui)
	local button = Theme.bigButton("RebirthButton", screenGui, Loc.t("ui.rebirth.button"), Theme.COLORS.good)
	Loc.bind(button, "ui.rebirth.button")
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position    = UDim2.new(1, -MARGIN, 1, -MARGIN)
	button.Size        = UDim2.fromOffset(SIZE.X, SIZE.Y)
	button.Visible     = false
	button.ZIndex      = 5

	local glow = Instance.new("UIStroke")
	glow.Name            = "Glow"
	glow.Color           = Theme.COLORS.goldGummy
	glow.Thickness       = 5
	glow.Transparency    = 1
	glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	glow.Parent          = button
	_glow = glow

	button.Activated:Connect(function()
		PanelManager.toggle("Rebirth")
	end)
	_button = button

	ClientState.onChanged(refresh)
	refresh()
end

return RebirthButton
