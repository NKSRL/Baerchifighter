--!strict
-- EggIcon.luau
-- StarterPlayerScripts/UI/EggIcon.luau
--
-- Einzige Zustaendigkeit:
--   - Ein Ei als UI-Symbol zeichnen: Eiform, dicker Cartoon-Rand, Muster,
--     Glanzpunkt und bei seltenen Eiern ein Schimmer — alles aus EggLook.
--
-- Gezeichnet statt als Bild: es gibt 21 Eier, jedes in eigener Farbe und
-- mit eigenem Pfad-Muster; ein Bild je Ei waere 21 Uploads, die bei jeder
-- Farbaenderung neu entstehen muessten. Dieselbe EggLook-Beschreibung
-- benutzt der Server fuer die gelegten Eier in der Welt, also sieht ein Ei im
-- Fenster aus wie auf der Wiese.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EggLook = require(ReplicatedStorage.Modules.EggLook)
local Theme   = require(script.Parent.Theme)

local EggIcon = {}

-- Breite : Hoehe des Symbols
local ASPECT = 0.8

local function shape(parent: Instance, name: string, cx: number, cy: number, w: number, h: number, color: Color3, z: number, roundness: number?): Frame
	local frame = Instance.new("Frame")
	frame.Name             = name
	frame.AnchorPoint      = Vector2.new(0.5, 0.5)
	frame.Position         = UDim2.fromScale(cx, cy)
	frame.Size             = UDim2.fromScale(w, h)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel  = 0
	frame.ZIndex           = z
	frame.Active           = false
	frame.Parent           = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(roundness or 0.5, 0)
	corner.Parent = frame
	return frame
end

-- Kreis mit Durchmesser `d` (Anteil der Breite); die Hoehe rechnet `aspect`
-- (Breite : Hoehe des Elternobjekts) um, damit er rund bleibt.
local function dot(parent: Instance, name: string, cx: number, cy: number, d: number, aspect: number, color: Color3, z: number): Frame
	return shape(parent, name, cx, cy, d, d * aspect, color, z)
end

-- Muster in ein eifoermiges Elternobjekt. Alle Positionen liegen bewusst im
-- Mittelbereich (x 0.2 bis 0.8), damit sie auf der Ei-Silhouette bleiben, egal
-- ob das Elternobjekt eine Ellipse oder ein Zwei-Ellipsen-Ei ist.
function EggIcon.addPattern(parent: Instance, eggId: string, aspect: number, z: number)
	local look = EggLook.get(eggId)
	local accent = look.accent

	if look.pattern == "spots" then
		dot(parent, "Spot", 0.34, 0.62, 0.20, aspect, accent, z)
		dot(parent, "Spot", 0.64, 0.76, 0.16, aspect, accent, z)
		dot(parent, "Spot", 0.60, 0.40, 0.13, aspect, accent, z)

	elseif look.pattern == "band" then
		local band = shape(parent, "Band", 0.5, 0.52, 0.72, 0.13, accent, z, 0.45)
		band.Rotation = -4

	elseif look.pattern == "stripes" then
		local upper = shape(parent, "Stripe", 0.5, 0.40, 0.58, 0.06, accent, z, 0.45)
		local lower = shape(parent, "Stripe", 0.5, 0.60, 0.74, 0.06, accent, z, 0.45)
		upper.Rotation = -5
		lower.Rotation = -5

	else
		-- "swirl" (Void: violette Tupfen) und "stars" (Kosmos/Ascension/Event:
		-- vierzackige Funken aus einem gedrehten Quadrat)
		if look.pattern == "swirl" then
			dot(parent, "Glint", 0.36, 0.60, 0.22, aspect, accent, z).BackgroundTransparency = 0.1
			dot(parent, "Glint", 0.64, 0.74, 0.15, aspect, accent, z).BackgroundTransparency = 0.1
			dot(parent, "Glint", 0.60, 0.40, 0.12, aspect, accent, z).BackgroundTransparency = 0.1
		else
			for index, spot in { Vector3.new(0.36, 0.60, 0.16), Vector3.new(0.64, 0.74, 0.11), Vector3.new(0.60, 0.38, 0.09) } do
				local star = shape(parent, "Star" .. index, spot.X, spot.Y, spot.Z, spot.Z * aspect, accent, z, 0.12)
				star.Rotation = 45
			end
		end
	end

	-- Glanzpunkt oben links
	local shine = shape(parent, "Shine", 0.34, 0.24, 0.20, 0.10, Color3.new(1, 1, 1), z, 0.5)
	shine.BackgroundTransparency = 0.3
	shine.Rotation = -30
end

-- Ein Ei-Symbol der Hoehe `height` Pixel in `parent`. Position stellt der
-- Aufrufer ein. `z` ist der ZIndex des Symbols (Panels mit eigenen
-- ZIndex-Staffeln brauchen ihn).
function EggIcon.make(parent: Instance, eggId: string, height: number, z: number?): Frame
	local look = EggLook.get(eggId)
	local layer = z or 1
	local outline = Theme.COLORS.outline

	local root = Instance.new("Frame")
	root.Name                   = "EggIcon"
	root.BackgroundTransparency = 1
	root.Size                   = UDim2.fromOffset(math.floor(height * ASPECT), height)
	root.ZIndex                 = layer
	root.Parent                 = parent

	-- Schimmer hinter seltenen Eiern
	if look.glow then
		local glow = shape(root, "Glow", 0.5, 0.55, 1.5, 1.2, look.accent, layer)
		glow.BackgroundTransparency = 0.7
	end

	-- Rand: dieselbe Eiform in Dunkel, etwas groesser als die Fuellung
	shape(root, "OutlineLower", 0.5, 0.64, 1.00, 0.72, outline, layer)
	shape(root, "OutlineTop",   0.5, 0.37, 0.80, 0.74, outline, layer)

	-- Fuellung: zwei Ellipsen derselben Farbe, die zu einem Ei verschmelzen
	shape(root, "FillLower", 0.5, 0.64, 0.90, 0.64, look.base, layer)
	shape(root, "FillTop",   0.5, 0.37, 0.70, 0.66, look.base, layer)

	EggIcon.addPattern(root, eggId, ASPECT, layer)
	return root
end

-- Fuer ein Ei, das schon als Ellipsen-Frame existiert (Schluepf-Animation):
-- Muster und Glanz darauf setzen. `aspect` = Breite : Hoehe des Frames.
function EggIcon.decorate(egg: Frame, eggId: string, aspect: number, z: number)
	EggIcon.addPattern(egg, eggId, aspect, z)
end

return EggIcon
