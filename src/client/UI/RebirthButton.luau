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
local Icons        = require(script.Parent.Icons)
local PanelManager = require(script.Parent.PanelManager)
local TouchSafeArea = require(script.Parent.TouchSafeArea)   -- R1
local ClientState  = require(script.Parent.Parent.Controllers.ClientState)

local RebirthButton = {}

local SIZE        = Vector2.new(132, 56)
local MARGIN      = 16
local GLOW_PERIOD = 1.2

local _button: TextButton? = nil
local _place: (() -> ())? = nil
local _shown = false
local _glow: UIStroke? = nil
local _glowTween: Tween? = nil
local _art: ImageLabel? = nil   -- Honig-Bild: leuchtet statt des Rahmens

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
	local art = _art
	if art then
		-- Honig: das Bild pulsiert warm, wenn ein Rebirth moeglich ist
		art.ImageColor3 = Color3.new(1, 1, 1)
		if on then
			local tween = TweenService:Create(art,
				TweenInfo.new(GLOW_PERIOD * 0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ ImageColor3 = Color3.fromRGB(255, 226, 140) })
			tween:Play()
			_glowTween = tween
		end
		return
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
	if _place then _place() end
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

	-- R1: auf Touch-Geraeten liegt unten rechts der Sprung-Knopf der Standard-
	-- Steuerung. Der Rebirth-Knopf sitzt dann darueber, und die MenuBar endet
	-- noch eine Knopfhoehe weiter oben (TouchSafeArea.setRightBottomExtra).
	local function place()
		-- Honig-Skin (UI_HONEY_SKIN): der Knopf sitzt oben links unter der
		-- Knopf-Zeile, nicht mehr unten rechts — dann gibt es nichts zu tun.
		if _art then
			TouchSafeArea.setRightBottomExtra(0)
			return
		end
		local jump = TouchSafeArea.jumpReserve(screenGui)
		if jump then
			button.Position = UDim2.new(1, -MARGIN, 1, -jump)
			TouchSafeArea.setRightBottomExtra(if button.Visible then SIZE.Y + MARGIN else 0)
		else
			button.Position = UDim2.new(1, -MARGIN, 1, -MARGIN)
			TouchSafeArea.setRightBottomExtra(0)
		end
	end
	_place = place
	TouchSafeArea.watch(screenGui, place)

	-- 14.10. (UI_HONEY_SKIN): goldene Baer-Leiste, links auf dem Bildschirm unter den Knoepfen
	local word, art = Icons.skinLabelButton(button, "honey/res_bar_gold", Loc.t("ui.rebirth.button"))
	if word and art then
		Loc.bind(word, "ui.rebirth.button")
		button.AnchorPoint = Vector2.new(0, 0)
		-- bündig unter der Knopf-Zeile (HudRow: y 106, 60 hoch, gleiche Luecke wie die Pillen = 6)
		-- und exakt so breit wie die drei Knoepfe (3 x 60 + 2 x 6), damit es eine Gruppe ist
		button.Position    = UDim2.new(0.012, 12, 0, (require(game:GetService("ReplicatedStorage").Config.FeatureFlags).isOn("UI_HONEY_SKIN") and 129 or 106) + 60 + 3)
		button.Size        = UDim2.fromOffset(186, 44)
		_art = art
	end

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
