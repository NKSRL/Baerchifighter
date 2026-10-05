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

local UiScale = {}

-- Bei dieser Bildschirmhoehe (Pixel, ohne Topbar) ist die UI 1:1 gebaut.
local REFERENCE_HEIGHT = 820
local MAX_SCALE = 1.6

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
		local height = screenGui.AbsoluteSize.Y
		_scale = math.clamp(height / REFERENCE_HEIGHT, 1, MAX_SCALE)
		scale.Scale = _scale
	end
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(update)
	update()
end

return UiScale
