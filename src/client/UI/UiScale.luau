--!strict
-- UiScale.luau
-- StarterPlayerScripts/UI/UiScale.luau
--
-- Einzige Zustaendigkeit:
--   - Die ganze Oberflaeche (eine ScreenGui "RBL") mit der Bildschirmhoehe
--     mitwachsen lassen, und Bildschirm-Pixel in Oberflaechen-Einheiten
--     umrechnen.
--
-- Warum: Alle Panels sind in festen Pixeln gebaut. Auf einem grossen Monitor
-- (1440p/4K) wirkte die UI dadurch winzig (Playtest 05.10.), in Studio mit
-- kleinem Fenster nicht. Ein UIScale direkt an der ScreenGui vergroessert
-- alles gleichmaessig. Nur NACH OBEN (>= 1): kleine Bildschirme regeln
-- MenuBar und PetBar schon selbst.
--
-- WICHTIG fuer jede Stelle, die AbsolutePosition/AbsoluteSize oder
-- Kamera-Pixel in eine Position (UDim2.fromOffset) zurueckschreibt: diese
-- Werte sind echte Bildschirm-Pixel und muessen durch UiScale.toGui, sonst
-- landet das Element um den Faktor daneben. Betrifft heute GuideController,
-- Feedback, IndexView, MenuBar, PetBar.

local UserInputService = game:GetService("UserInputService")

local UiScale = {}

-- Bei dieser Bildschirmhoehe (Pixel, ohne Topbar) ist die UI 1:1 gebaut.
local REFERENCE_HEIGHT = 820
local MAX_SCALE = 1.6

-- 12.10. (Playtest "am PC ist der Bildschirm noch recht leer"): am PC (Maus +
-- Tastatur, kein reines Touch-Geraet) waechst die UI frueher und weiter mit.
-- 1080p: 1,27 -> 1,49; 1440p: 1,6 -> 1,85; 768p-Laptop: 1,0 -> 1,05.
-- Deckel ueber die BREITE, damit die Leisten nebeneinander passen.
-- Handy und Tablet behalten die alte Rechnung unveraendert (dort ist der
-- Platz knapp, groesser hiesse: Knoepfe ueber dem Spielfeld).
local PC_REFERENCE_HEIGHT = 700
local PC_MAX_SCALE        = 1.9
local PC_REFERENCE_WIDTH  = 1150   -- bei dieser Breite hoechstens 1:1

local function isPc(): boolean
	local ok, result = pcall(function()
		local touch = UserInputService.TouchEnabled
		local keyboard = UserInputService.KeyboardEnabled
		local mouse = UserInputService.MouseEnabled
		if typeof(touch) ~= "boolean" or typeof(keyboard) ~= "boolean" or typeof(mouse) ~= "boolean" then
			return false
		end
		-- Laptop mit Touchscreen hat Tastatur und Maus: zaehlt als PC
		return keyboard and mouse
	end)
	return ok and result == true
end

local _scale = 1
local _uiScale: UIScale? = nil

function UiScale.get(): number
	return _scale
end

-- Bildschirm-Pixel -> Oberflaechen-Einheiten (Vector2 oder Zahl)
function UiScale.toGui<T>(value: T): T
	return ((value :: any) / _scale) :: any
end

function UiScale.init(screenGui: ScreenGui)
	local scale = Instance.new("UIScale")
	scale.Name = "GlobalScale"
	scale.Parent = screenGui
	_uiScale = scale

	local function update()
		local size = screenGui.AbsoluteSize
		if isPc() then
			local byHeight = size.Y / PC_REFERENCE_HEIGHT
			local byWidth = size.X / PC_REFERENCE_WIDTH
			_scale = math.clamp(math.min(byHeight, byWidth), 1, PC_MAX_SCALE)
		else
			_scale = math.clamp(size.Y / REFERENCE_HEIGHT, 1, MAX_SCALE)
		end
		scale.Scale = _scale
	end
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	update()
end

return UiScale
