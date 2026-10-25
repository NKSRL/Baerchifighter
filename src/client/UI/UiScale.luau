--!strict
-- UiScale.luau
-- StarterPlayerScripts/UI/UiScale.luau
--
-- Einzige Zustaendigkeit:
--   - Die ganze Oberflaeche (eine ScreenGui "RBL") mit der Bildschirmhoehe
--     mitwachsen UND -schrumpfen lassen, und Bildschirm-Pixel in
--     Oberflaechen-Einheiten umrechnen.
--
-- Warum: Alle Panels sind in festen Pixeln gebaut. Auf einem grossen Monitor
-- (1440p/4K) wirkte die UI dadurch winzig (Playtest 05.10.). Ein UIScale
-- direkt an der ScreenGui vergroessert alles gleichmaessig.
--
-- R1 (16.10.): auch NACH UNTEN. Auf dem Handy quer (Hoehe ~340 px) war das HUD
-- zu gross und stand im Weg. Jetzt gibt es zwei Untergrenzen:
--   * Desktop: MIN_SCALE_DESKTOP - ein kleines Studio-Fenster / 1366x768
--     behaelt dieselben Proportionen wie 1920x1080.
--   * Touch:   MIN_SCALE_TOUCH - Handy quer landet bei ca. 65 % der Groesse am
--     PC; darunter wuerden Touch-Ziele (68 px Knoepfe der Pet-Leiste) unter
--     44 px fallen. Das ist der "Touch-Zuschlag".
-- Alle Zahlen stehen unten als Tokens und nirgends sonst.
--
-- Referenz: REFERENCE_HEIGHT = 820 sind die ~1044 px, die ein Fenster mit
-- 1080 px Hoehe nach Abzug der Roblox-Topbar noch hat (Faktor 1,27 am PC wie
-- bisher). Alles darunter schrumpft proportional bis zur Untergrenze.
--
-- WICHTIG fuer jede Stelle, die AbsolutePosition/AbsoluteSize oder
-- Kamera-Pixel in eine Position (UDim2.fromOffset) zurueckschreibt: diese
-- Werte sind echte Bildschirm-Pixel und muessen durch UiScale.toGui, sonst
-- landet das Element um den Faktor daneben. Betrifft heute GuideController,
-- Feedback, IndexView, MenuBar, PetBar.

local UserInputService = game:GetService("UserInputService")
local FeatureFlags     = require(game:GetService("ReplicatedStorage").Config.FeatureFlags)

local UiScale = {}

-- Tokens ----------------------------------------------------------------------
-- Bei dieser Bildschirmhoehe (Pixel, ohne Topbar) ist die UI 1:1 gebaut.
UiScale.REFERENCE_HEIGHT   = 820
-- 21.10. Playtest: Mit 1,6 als Obergrenze wurde die UI auf WQHD leicht und auf 4K deutlich
-- KLEINER im Verhaeltnis zum Bildschirm als auf Full-HD (und Fenster sassen anders). Die Grenze
-- liegt jetzt oberhalb von 4K (2160 / 820 = 2,63): gleiche Proportionen auf jedem Monitor.
UiScale.MAX_SCALE          = 3.2
UiScale.MIN_SCALE_DESKTOP  = 0.75
UiScale.MIN_SCALE_TOUCH    = 0.65
-- W1-P6b (UI_ADAPTIVE_V1): damit 60-Einheiten-Knoepfe auf dem Handy >= 48 px bleiben (60 x 0,8)
UiScale.MIN_SCALE_TOUCH_ADAPTIVE = 0.8

local _scale = 1
local _uiScale: UIScale? = nil
local _listeners: { (number) -> () } = {}

-- Touch-Steuerung aktiv? Tablets mit Tastatur benutzen sie nicht.
function UiScale.isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- Reine Rechnung (ohne Roblox-Objekte), damit sie testbar bleibt.
function UiScale.compute(heightPixels: number, touch: boolean): number
	local touchFloor = if FeatureFlags.isOn("UI_ADAPTIVE_V1") then UiScale.MIN_SCALE_TOUCH_ADAPTIVE else UiScale.MIN_SCALE_TOUCH
	local floor = if touch then touchFloor else UiScale.MIN_SCALE_DESKTOP
	return math.clamp(heightPixels / UiScale.REFERENCE_HEIGHT, floor, UiScale.MAX_SCALE)
end

function UiScale.get(): number
	return _scale
end

-- Bildschirm-Pixel -> Oberflaechen-Einheiten (Vector2 oder Zahl)
function UiScale.toGui<T>(value: T): T
	return ((value :: any) / _scale) :: any
end

-- Meldet jede Aenderung des Faktors (Handy gedreht, Fenster gezogen).
function UiScale.onChanged(callback: (number) -> ())
	table.insert(_listeners, callback)
end

function UiScale.init(screenGui: ScreenGui)
	local scale = Instance.new("UIScale")
	scale.Name = "GlobalScale"
	scale.Parent = screenGui
	_uiScale = scale

	local function update()
		local height = screenGui.AbsoluteSize.Y
		if height <= 0 then return end
		local new = UiScale.compute(height, UiScale.isTouch())
		if math.abs(new - _scale) < 1e-4 and scale.Scale == new then return end
		_scale = new
		scale.Scale = new
		for _, callback in _listeners do
			task.spawn(callback, new)
		end
	end
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(update)
	UserInputService:GetPropertyChangedSignal("KeyboardEnabled"):Connect(update)
	update()
end

return UiScale
