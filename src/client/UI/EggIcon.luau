--!strict
-- EggIcon.luau
-- StarterPlayerScripts/UI/EggIcon.luau
--
-- Einzige Zustaendigkeit:
--   - Ein Ei als UI-Symbol: das gezeichnete Ei-Bild (assets/ui/eggs, in
--     Blender aus EggConfig + EggLook gerendert), dazu Seltenheits-Effekte
--     und die kleine "will gleich schluepfen"-Animation.
--
-- Was man am Ei sieht:
--   - Ab Tier 6 (EggLook.glow): innerer Schimmer (wandernder Lichtstreifen
--     ueber der Ei-Maske) und ein weicher Halo dahinter.
--   - Die hoechsten Eier (Tier 9+, Event): ein langsam rotierender Lichtkranz.
--   - opts.idle: das Ei wackelt ab und zu um seinen Fusspunkt und blitzt kurz
--     auf. Alles per Eigenschaften, keine Sprite-Sheets.
--
-- Ohne hochgeladenes Bild (Icons.luau, Schluessel "eggs/<EggId>") zeichnet
-- das Modul wie frueher ein Ei aus Frames — jetzt aus EINER Ellipse, nicht
-- mehr aus zwei mit Taille. Das UI bleibt so ohne Upload bedienbar.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local EggLook = require(ReplicatedStorage.Modules.EggLook)
local Theme   = require(script.Parent.Theme)
local Icons   = require(script.Parent.Icons)

local EggIcon = {}

-- Breite : Hoehe des Symbols (unveraendert, damit Aufrufer-Layouts passen)
local ASPECT = 0.8

-- Masse im 512-px-Ei-Bild (tools/art/render_eggs.py: Kamera 3.3 Einheiten,
-- Mitte z 1.27): Fusspunkt des Eis von oben, Abstand Mitte → Fuss.
EggIcon.FOOT_Y = 0.885
local FOOT_FROM_CENTER = EggIcon.FOOT_Y - 0.5

-- Ab dieser Stufe dreht sich ein Lichtkranz hinter dem Ei.
local RAYS_FROM_TIER = 9

local SILHOUETTE = Color3.fromRGB(38, 30, 46)

export type Options = {
	idle     : boolean?,   -- wackeln + aufblitzen
	pedestal : boolean?,   -- kleiner Baumstumpf-Sockel unter dem Ei
	effects  : boolean?,   -- Halo/Kranz/Schimmer (Standard: an)
}

type Entry = {
	root    : Frame,
	body    : Frame,
	height  : number,
	flash   : ImageLabel?,
	flashG  : UIGradient?,
	shimmer : UIGradient?,
	halo    : ImageLabel?,
	rays    : ImageLabel?,
	idle    : boolean,
	phase   : number,
	nextAt  : number,
	wobbleT : number,     -- Startzeit des laufenden Wackelns, -1 = keins
	flashT  : number,     -- Startzeit des laufenden Aufblitzens, -1 = keins
}

local _entries: { Entry } = {}
local _loop: RBXScriptConnection? = nil
local _rng = Random.new()

function EggIcon.imageId(eggId: string): string?
	return Icons.ui("eggs/" .. eggId)
end

--------------------------------------------------------------------------------
-- Rueckfall ohne Bild: Frames
--------------------------------------------------------------------------------

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
-- Mittelbereich (x 0.2 bis 0.8), damit sie auf der Ei-Silhouette bleiben.
function EggIcon.addPattern(parent: Instance, eggId: string, aspect: number, z: number)
	local look = EggLook.get(eggId)
	local accent = look.accent

	if look.pattern == "spots" then
		dot(parent, "Spot", 0.34, 0.62, 0.20, aspect, accent, z)
		dot(parent, "Spot", 0.64, 0.76, 0.16, aspect, accent, z)
		dot(parent, "Spot", 0.60, 0.40, 0.13, aspect, accent, z)

	elseif look.pattern == "band" then
		local band = shape(parent, "Band", 0.5, 0.56, 0.86, 0.13, accent, z, 0.45)
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

-- EINE Ellipse (oben etwas schmaler wirkt durch die Neigung) statt der
-- frueheren zwei Ellipsen mit Taille.
local function drawFallback(body: Frame, eggId: string, z: number)
	local look = EggLook.get(eggId)
	local outline = shape(body, "Outline", 0.5, 0.52, 0.80, 0.86, Theme.COLORS.outline, z)
	outline.Rotation = 6
	local fill = shape(outline, "Fill", 0.5, 0.5, 0.88, 0.9, look.base, z)
	EggIcon.addPattern(fill, eggId, 0.8 / 0.86, z)
end

--------------------------------------------------------------------------------
-- Animation (ein gemeinsamer Takt fuer alle Eier)
--------------------------------------------------------------------------------

local function onScreen(root: Frame): boolean
	if root.AbsoluteSize.X <= 0 then return false end
	local node: Instance? = root
	while node do
		if node:IsA("GuiObject") and not node.Visible then return false end
		if node:IsA("ScreenGui") then return node.Enabled end
		node = node.Parent
	end
	return false
end

local function step()
	local now = os.clock()
	local i = 1
	while i <= #_entries do
		local e = _entries[i]
		if e.root.Parent == nil then
			table.remove(_entries, i)
			continue
		end
		i += 1
		if not onScreen(e.root) then continue end

		local t = now + e.phase
		if e.rays then
			e.rays.Rotation = (t * 14) % 360
		end
		if e.halo then
			e.halo.ImageTransparency = 0.45 + 0.15 * math.sin(t * 2.1)
		end
		if e.shimmer then
			e.shimmer.Offset = Vector2.new(((t * 0.45) % 1) * 3 - 1.5, 0)
		end

		-- Wackeln um den Fusspunkt: Ei will schluepfen
		local angle = 0
		if e.idle and e.root:GetAttribute("Silhouette") ~= true then
			if e.wobbleT < 0 and now >= e.nextAt then
				e.wobbleT = now
			end
			if e.wobbleT >= 0 then
				local k = now - e.wobbleT
				if k > 0.75 then
					e.wobbleT = -1
					e.flashT = now
					e.nextAt = now + _rng:NextNumber(3.5, 7.5)
				else
					angle = 9 * math.sin(k * 26) * (1 - k / 0.75)
				end
			end
		end
		local d = e.height * FOOT_FROM_CENTER
		local rad = math.rad(angle)
		e.body.Rotation = angle
		e.body.Position = UDim2.new(0.5, d * math.sin(rad), 0, d * (1 - math.cos(rad)))

		-- Aufblitzen: heller Streifen gleitet ueber die Ei-Maske
		if e.flash and e.flashG then
			if e.flashT >= 0 then
				local k = (now - e.flashT) / 0.4
				if k >= 1 then
					e.flashT = -1
					e.flash.Visible = false
				else
					e.flash.Visible = true
					e.flashG.Offset = Vector2.new(-1.2 + 2.4 * k, 0)
				end
			end
		end
	end
	if #_entries == 0 and _loop then
		_loop:Disconnect()
		_loop = nil
	end
end

local function register(e: Entry)
	table.insert(_entries, e)
	if not _loop then
		_loop = RunService.Heartbeat:Connect(step)
	end
end

-- Ein Bild aus der Ei-Maske (gleiche Form fuer alle Eier) mit Verlaufsband.
local function maskOverlay(parent: Instance, name: string, color: Color3, z: number, width: number, strength: number): (ImageLabel?, UIGradient?)
	local mask = Icons.uiImage(parent, "eggs/egg_mask")
	if not mask then return nil, nil end
	mask.Name        = name
	mask.Size        = UDim2.fromScale(1, 1)
	mask.ImageColor3 = color
	mask.ZIndex      = z
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 25
	local a = 1 - strength
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(math.max(0.001, 0.5 - width), 1),
		NumberSequenceKeypoint.new(0.5, a),
		NumberSequenceKeypoint.new(math.min(0.999, 0.5 + width), 1),
		NumberSequenceKeypoint.new(1, 1),
	})
	gradient.Parent = mask
	return mask, gradient
end

--------------------------------------------------------------------------------
-- Oeffentlich
--------------------------------------------------------------------------------

-- Ein Ei-Symbol der Hoehe `height` Pixel in `parent`. Position stellt der
-- Aufrufer ein. `z` ist der ZIndex des Symbols (Panels mit eigenen
-- ZIndex-Staffeln brauchen ihn).
function EggIcon.make(parent: Instance, eggId: string, height: number, z: number?, opts: Options?): Frame
	local look = EggLook.get(eggId)
	local layer = z or 1
	local options: Options = opts or {}
	local effects = options.effects ~= false

	local root = Instance.new("Frame")
	root.Name                   = "EggIcon"
	root.BackgroundTransparency = 1
	root.Size                   = UDim2.fromOffset(math.floor(height * ASPECT), height)
	root.ZIndex                 = layer
	root:SetAttribute("EggId", eggId)
	root.Parent                 = parent

	local imageId = EggIcon.imageId(eggId)
	local glowColor = look.accent:Lerp(Color3.new(1, 1, 1), 0.3)

	-- Lichtkranz und Halo hinter dem Ei
	local rays: ImageLabel? = nil
	local halo: ImageLabel? = nil
	if effects and imageId and (look.tier >= RAYS_FROM_TIER or look.pattern == "stars" and look.tier == 0) then
		rays = Icons.uiImage(root, "fx/ring_rays")
		if rays then
			rays.Name        = "Rays"
			rays.AnchorPoint = Vector2.new(0.5, 0.5)
			rays.Position    = UDim2.fromScale(0.5, 0.5)
			rays.Size        = UDim2.fromOffset(height * 1.9, height * 1.9)
			rays.ImageColor3 = glowColor
			rays.ImageTransparency = 0.25
			rays.ZIndex      = layer
		end
	end
	if effects and look.glow then
		halo = Icons.uiImage(root, "fx/ring_soft")
		if halo then
			halo.Name        = "Halo"
			halo.AnchorPoint = Vector2.new(0.5, 0.5)
			halo.Position    = UDim2.fromScale(0.5, 0.5)
			halo.Size        = UDim2.fromOffset(height * 1.35, height * 1.35)
			halo.ImageColor3 = glowColor
			halo.ZIndex      = layer
		elseif not imageId then
			-- Rueckfall: der alte Schimmer-Kreis
			local glow = shape(root, "Glow", 0.5, 0.55, 1.5, 1.2, look.accent, layer)
			glow.BackgroundTransparency = 0.7
		end
	end

	if options.pedestal then
		local ped = Icons.uiImage(root, "frames/pedestal")
		if ped then
			ped.Name        = "Pedestal"
			ped.AnchorPoint = Vector2.new(0.5, 0)
			ped.Position    = UDim2.new(0.5, 0, 0, height * (EggIcon.FOOT_Y - 0.2))
			ped.Size        = UDim2.fromOffset(height * 1.05, height * 1.05 * 160 / 256)
			ped.ZIndex      = layer
		end
	end

	-- Koerper: quadratisch, unten am Fusspunkt ausgerichtet; dreht beim Wackeln.
	local body = Instance.new("Frame")
	body.Name                   = "Body"
	body.BackgroundTransparency = 1
	body.AnchorPoint            = Vector2.new(0.5, 0)
	body.Position               = UDim2.fromScale(0.5, 0)
	body.Size                   = UDim2.fromOffset(height, height)
	body.ZIndex                 = layer
	body.Parent                 = root

	local flash: ImageLabel? = nil
	local flashG: UIGradient? = nil
	local shimmer: UIGradient? = nil

	if imageId then
		local image = Instance.new("ImageLabel")
		image.Name                   = "Egg"
		image.BackgroundTransparency = 1
		image.Image                  = imageId
		image.ScaleType              = Enum.ScaleType.Fit
		image.Size                   = UDim2.fromScale(1, 1)
		image.ZIndex                 = layer
		image.Parent                 = body

		if effects and look.glow then
			local _, g = maskOverlay(body, "Shimmer", glowColor, layer, 0.22, 0.45)
			shimmer = g
		end
		if options.idle then
			local f, g = maskOverlay(body, "Flash", Color3.new(1, 1, 1), layer, 0.12, 0.85)
			if f then f.Visible = false end
			flash, flashG = f, g
		end
	else
		drawFallback(body, eggId, layer)
	end

	if rays or halo or shimmer or options.idle then
		register({
			root = root, body = body, height = height,
			flash = flash, flashG = flashG, shimmer = shimmer, halo = halo, rays = rays,
			idle = options.idle == true,
			phase = _rng:NextNumber(0, 10),
			nextAt = os.clock() + _rng:NextNumber(0.8, 5),
			wobbleT = -1, flashT = -1,
		})
	end
	return root
end

-- Dunkle Silhouette (gesperrter Knoten im Ei-Baum) bzw. wieder in Farbe.
function EggIcon.setSilhouette(root: Frame, on: boolean)
	root:SetAttribute("Silhouette", on)
	for _, d in root:GetDescendants() do
		if d:IsA("ImageLabel") then
			if d.Name == "Egg" then
				d.ImageColor3 = if on then SILHOUETTE else Color3.new(1, 1, 1)
			elseif d.Name == "Shimmer" or d.Name == "Halo" or d.Name == "Rays" then
				d.Visible = not on
			end
		elseif d:IsA("Frame") and d.Name == "Fill" then
			local eggId = root:GetAttribute("EggId")
			if typeof(eggId) == "string" then
				d.BackgroundColor3 = if on then SILHOUETTE else EggLook.get(eggId).base
			end
		end
	end
end

-- Sofort einmal wackeln und aufblitzen (z. B. nach dem Landen beim Freischalten).
function EggIcon.poke(root: Frame)
	for _, e in _entries do
		if e.root == root then
			e.wobbleT = os.clock()
			return
		end
	end
end

-- Fuer ein Ei, das schon als Ellipsen-Frame existiert (Schluepf-Animation):
-- Muster und Glanz darauf setzen. `aspect` = Breite : Hoehe des Frames.
function EggIcon.decorate(egg: Frame, eggId: string, aspect: number, z: number)
	EggIcon.addPattern(egg, eggId, aspect, z)
end

return EggIcon
