--!strict
-- TouchSafeArea.luau
-- StarterPlayerScripts/UI/TouchSafeArea.luau
--
-- Einzige Zustaendigkeit:
--   - Auf Touch-Geraeten wissen, wo die Roblox-Steuerung liegt, und den
--     freien Streifen unten dazwischen liefern.
--
-- Warum (Playtest 07.10., Handy): die Pet-Leiste (Event/Fight) lag unten
-- mittig und war 434 breit — auf einem Handy quer (~844 breit) reichte der
-- Event-Knopf in die Zone des Bewegungs-Sticks. Wer laufen wollte, tippte auf
-- "Event". Der Heim-Knopf lag sogar ganz in dieser Zone (unten links).
--
-- Die Zonen sind die der Standard-Steuerung (PlayerModule, nicht von uns
-- gebaut, deshalb hier als Konstanten nachgebildet):
--   * Bewegungs-Stick (DynamicThumbstick): reagiert in den linken 40 % der
--     Breite, unteres Zwei-Drittel der Hoehe.
--   * Sprung-Knopf: unten rechts. Kleine Bildschirme (kuerzere Seite <= 500 px)
--     70 px gross, 25 px vom Rand; sonst 120 px, 50 px vom Rand.
-- Wir halten links und rechts davon Abstand und legen unsere Knoepfe in den
-- Streifen dazwischen.
--
-- Am PC/Konsole (kein Touch) ist der ganze untere Rand frei — dann liefert
-- `zone` nil und die Aufrufer behalten ihr bisheriges Layout.

local UserInputService = game:GetService("UserInputService")

local UiScale = require(script.Parent.UiScale)

local TouchSafeArea = {}

-- Anteil der Breite, auf den der Bewegungs-Stick reagiert, plus Luft
local THUMBSTICK_WIDTH = 0.40
local THUMBSTICK_GAP   = 16

-- Sprung-Knopf (Pixel) je nach Bildschirmgroesse, plus Luft daneben
local JUMP_SMALL = { size = 70,  margin = 25, below = 500 }
local JUMP_LARGE = { size = 120, margin = 50 }
local JUMP_GAP   = 16

export type Zone = {
	left  : number,   -- linke Kante des freien Streifens (Oberflaechen-Einheiten)
	right : number,   -- rechte Kante
	width : number,
	center: number,   -- Mitte, als Offset von der linken Bildschirmkante
}

-- Touch-Steuerung aktiv? Tablets mit Tastatur benutzen sie nicht.
function TouchSafeArea.isTouch(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

-- Freier Streifen unten zwischen Bewegungs-Stick und Sprung-Knopf, oder nil
-- ohne Touch-Steuerung.
function TouchSafeArea.zone(screenGui: ScreenGui): Zone?
	if not TouchSafeArea.isTouch() then
		return nil
	end

	local pixels = screenGui.AbsoluteSize
	local shortSide = math.min(pixels.X, pixels.Y)
	local jump = if shortSide <= JUMP_SMALL.below then JUMP_SMALL else JUMP_LARGE

	local width = UiScale.toGui(pixels.X)
	local left  = width * THUMBSTICK_WIDTH + THUMBSTICK_GAP
	local right = width - UiScale.toGui(jump.size + jump.margin) - JUMP_GAP
	if right <= left then
		return nil
	end
	return { left = left, right = right, width = right - left, center = (left + right) / 2 }
end

-- Wie viel Hoehe rechts unten frei bleiben muss (Oberflaechen-Einheiten):
-- mit Touch-Steuerung der Sprung-Knopf samt Rand und Luft, sonst `fallback`.
-- Fuer alles, was am rechten Rand nach unten waechst (MenuBar).
function TouchSafeArea.rightBottomReserve(screenGui: ScreenGui, fallback: number): number
	if not TouchSafeArea.isTouch() then
		return fallback
	end
	local pixels = screenGui.AbsoluteSize
	local jump = if math.min(pixels.X, pixels.Y) <= JUMP_SMALL.below then JUMP_SMALL else JUMP_LARGE
	return math.max(fallback, UiScale.toGui(jump.size + jump.margin) + JUMP_GAP)
end

-- Ruft `callback` jetzt und bei jeder Groessen- oder Eingabeart-Aenderung.
function TouchSafeArea.watch(screenGui: ScreenGui, callback: () -> ())
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(callback)
	UserInputService:GetPropertyChangedSignal("KeyboardEnabled"):Connect(callback)
	UserInputService:GetPropertyChangedSignal("TouchEnabled"):Connect(callback)
	callback()
end

return TouchSafeArea
