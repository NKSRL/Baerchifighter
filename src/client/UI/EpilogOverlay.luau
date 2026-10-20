--!strict
-- EpilogOverlay.luau
-- StarterPlayerScripts/UI/EpilogOverlay.luau
--
-- Einzige Zustaendigkeit (Prompt 5 von 7, Final-Epilog):
--   - Die Bildschirmrand-Effekte der Kamerafahrt in einer eigenen UI-Schicht:
--     Flash, Vignette (gold/dunkel, aus vier UI-Verlaeufen, kein Bild), goldene Eckfunken,
--     aufsteigende Konfetti-Schleier links/rechts, Konfetti-Burst, Speed-Lines,
--     Wolkenfetzen mit Parallax, Lens-Flare am oberen Rand, Letterbox (2,35:1),
--     roter Knopf-Puls im Zentrum und der Skip-Ring (zwoelf Punkte) unten rechts.
--
-- Keine eigene Schleife: der EpilogController ruft `update(t, dt)` aus seiner einen
-- Kit.animate-Schleife. Alle Teilchen kommen aus festen Pools (hoechstens FX.maxSprites,
-- "reduced" halbiert) und werden nur wiederverwendet. Ohne hochgeladene Bilder
-- (EpilogConfig.ASSETS) zeichnen Frames die Teilchen. Keine Texte (nur "TOWER GESCHAFFT!"
-- kommt ueber UI/Moment).
--
-- Eigene ScreenGui `RBL_Epilog` (IgnoreGuiInset, ohne UiScale), steht ueber dem HUD.

local Players           = game:GetService("Players")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EpilogConfig = require(ReplicatedStorage.Config.EpilogConfig)

local EpilogOverlay = {}

local FX = EpilogConfig.FX
local A  = EpilogConfig.ASSETS
local SKIP_DOTS = 12

type Sprite = {
	gui    : GuiObject,
	kind   : string,
	active : boolean,
	age    : number,
	life   : number,
	x      : number, y : number,
	vx     : number, vy : number,
	spin   : number,
	size   : number,
	depth  : number,
	color  : Color3,
	flip   : boolean,
}

local _gui: ScreenGui? = nil
local _root: Frame? = nil
local _pools: { [string]: { Sprite } } = {}
local _spawnAcc: { [string]: number } = {}
local _rng = Random.new(20261020)
local _reduced = false
local _running = false

local _flash: Frame? = nil
local _flashEnd = 0          -- Ende eines manuellen Flashs (Sequenzzeit-unabhaengig, os.clock)
local _flashStart = 0
local _flashHold = 0
local _flashKind = ""        -- "" | "manual" | "restore"
local _vig: { Frame } = {}
local _letter: { Frame } = {}
local _glow: Frame? = nil
local _skip: TextButton? = nil
local _dots: { Frame } = {}
local _flare: { Frame } = {}
local _conns: { RBXScriptConnection } = {}
-- Prompt 6 (Finale): Zahl, Banner, Hinweis, Konfetti-Regen, feste Vignette
local _count: TextLabel? = nil
local _banner: TextLabel? = nil
local _hint: TextLabel? = nil
local _rain = 0                                  -- Konfetti pro Sekunde von oben (0 = aus)
local _vigManual: { color: Color3, alpha: number }? = nil

--------------------------------------------------------------------------------
-- Hilfen
--------------------------------------------------------------------------------

local function inWindow(w: { number }, t: number): boolean
	return t >= w[1] and t < w[2]
end

local function inAnyWindow(list: { { number } }, t: number): boolean
	for _, w in list do
		if inWindow(w, t) then return true end
	end
	return false
end

-- 0 -> 1 -> 0 ueber ein Fenster (sanfte Huellkurve)
local function envelope(w: { number }, t: number, edge: number): number
	if not inWindow(w, t) then return 0 end
	return math.min(1, (t - w[1]) / edge, (w[2] - t) / edge)
end

local function lerp(a: number, b: number, t: number): number return a + (b - a) * t end

local function size(): Vector2
	local root = _root
	return if root then root.AbsoluteSize else Vector2.new(1280, 720)
end

local function frame(name: string, parent: Instance, color: Color3, z: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Active = false
	f.ZIndex = z
	f.Parent = parent
	return f
end

local function corner(parent: Instance, scale: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(scale, 0)
	c.Parent = parent
end

--------------------------------------------------------------------------------
-- Teilchen
--------------------------------------------------------------------------------

local function makeSprite(kind: string): Sprite
	local root = _root :: Frame
	local gui: GuiObject
	if kind == "sparks" then
		if A.sparkTex ~= "" then
			local img = Instance.new("ImageLabel")
			img.Image = A.sparkTex
			img.BackgroundTransparency = 1
			gui = img
		else
			local f = frame("Funke", root, FX.colors.gold, 12)
			f.Rotation = 45
			corner(f, 0.12)
			gui = f
		end
	elseif kind == "veil" or kind == "burst" then
		if A.confettiTex ~= "" then
			local img = Instance.new("ImageLabel")
			img.Image = A.confettiTex
			img.ImageRectSize = Vector2.new(64, 64)
			img.BackgroundTransparency = 1
			gui = img
		else
			local f = frame("Konfetti", root, FX.colors.gold, if kind == "burst" then 16 else 13)
			corner(f, 0.2)
			gui = f
		end
	elseif kind == "speed" then
		if A.speedLineTex ~= "" then
			local img = Instance.new("ImageLabel")
			img.Image = A.speedLineTex
			img.BackgroundTransparency = 1
			gui = img
		else
			local f = frame("SpeedLine", root, FX.colors.white, 11)
			local g = Instance.new("UIGradient")
			g.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.25), NumberSequenceKeypoint.new(1, 1),
			})
			g.Parent = f
			corner(f, 0.5)
			gui = f
		end
	else -- cloud
		local f = frame("Wolke", root, FX.colors.white, 10)
		corner(f, 0.5)
		gui = f
	end
	gui.AnchorPoint = Vector2.new(0.5, 0.5)
	gui.Visible = false
	gui.Parent = root
	return {
		gui = gui, kind = kind, active = false, age = 0, life = 1, x = 0, y = 0, vx = 0, vy = 0,
		spin = 0, size = 10, depth = 1, color = FX.colors.white, flip = false,
	}
end

local function setTint(s: Sprite, color: Color3)
	s.color = color
	if s.gui:IsA("ImageLabel") then
		(s.gui :: ImageLabel).ImageColor3 = color
	else
		s.gui.BackgroundColor3 = color
	end
end

local function setAlpha(s: Sprite, alpha: number)   -- alpha 1 = sichtbar
	local transparency = math.clamp(1 - alpha, 0, 1)
	if s.gui:IsA("ImageLabel") then
		(s.gui :: ImageLabel).ImageTransparency = transparency
	elseif s.kind == "speed" then
		s.gui.BackgroundTransparency = math.clamp(transparency * 0.9, 0, 1)
	elseif s.kind == "cloud" then
		s.gui.BackgroundTransparency = math.clamp(1 - alpha * 0.45, 0, 1)
	else
		s.gui.BackgroundTransparency = transparency
	end
end

local function free(kind: string): Sprite?
	local pool = _pools[kind]
	if not pool then return nil end
	for _, s in pool do
		if not s.active then return s end
	end
	return nil
end

local function activate(s: Sprite, life: number)
	s.active = true
	s.age = 0
	s.life = life
	s.gui.Visible = true
end

local function deactivate(s: Sprite)
	s.active = false
	s.gui.Visible = false
end

local PALETTE_SPARK = { FX.colors.gold, FX.colors.gold, FX.colors.white, FX.colors.pink }
local PALETTE_VEIL  = { FX.colors.gold, FX.colors.white, FX.colors.sky, FX.colors.pink, FX.colors.magenta }

local function spawnSpark(screen: Vector2)
	local s = free("sparks")
	if not s then return end
	local corners = { { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }
	local c = corners[_rng:NextInteger(1, 4)]
	s.x = (c[1] * screen.X) + (if c[1] == 0 then 1 else -1) * _rng:NextNumber(0.02, 0.2) * screen.X
	s.y = (c[2] * screen.Y) + (if c[2] == 0 then 1 else -1) * _rng:NextNumber(0.02, 0.28) * screen.Y
	s.vx = _rng:NextNumber(-12, 12)
	s.vy = -_rng:NextNumber(8, 34)   -- steigt langsam auf
	s.size = _rng:NextNumber(10, 26)
	s.spin = _rng:NextNumber(-40, 40)
	s.gui.Rotation = if s.gui:IsA("Frame") then 45 else _rng:NextNumber(0, 90)
	setTint(s, PALETTE_SPARK[_rng:NextInteger(1, #PALETTE_SPARK)])
	activate(s, _rng:NextNumber(0.9, 1.6))
end

local function spawnVeil(screen: Vector2)
	local s = free("veil")
	if not s then return end
	local left = _rng:NextNumber() < 0.5
	s.x = if left then _rng:NextNumber(0, 0.12) * screen.X else _rng:NextNumber(0.88, 1) * screen.X
	s.y = screen.Y + 12
	s.vx = (if left then 1 else -1) * _rng:NextNumber(10, 60)
	s.vy = -_rng:NextNumber(170, 330)
	s.size = _rng:NextNumber(8, 15)
	s.spin = _rng:NextNumber(-260, 260)
	s.gui.Rotation = _rng:NextNumber(0, 360)
	setTint(s, PALETTE_VEIL[_rng:NextInteger(1, #PALETTE_VEIL)])
	if s.gui:IsA("ImageLabel") then
		(s.gui :: ImageLabel).ImageRectOffset = Vector2.new(64 * _rng:NextInteger(0, 3), 0)
	end
	activate(s, _rng:NextNumber(2.2, 3.2))
end

-- Konfetti-Regen von oben (Finale, Phase 3): nutzt den Veil-Pool, faellt statt zu steigen.
local function spawnRain(screen: Vector2)
	local s = free("veil")
	if not s then return end
	s.x = _rng:NextNumber(0.02, 0.98) * screen.X
	s.y = -14
	s.vx = _rng:NextNumber(-40, 40)
	s.vy = _rng:NextNumber(220, 420)
	s.size = _rng:NextNumber(8, 15)
	s.spin = _rng:NextNumber(-260, 260)
	s.gui.Rotation = _rng:NextNumber(0, 360)
	setTint(s, PALETTE_VEIL[_rng:NextInteger(1, #PALETTE_VEIL)])
	if s.gui:IsA("ImageLabel") then
		(s.gui :: ImageLabel).ImageRectOffset = Vector2.new(64 * _rng:NextInteger(0, 3), 0)
	end
	activate(s, _rng:NextNumber(1.8, 2.8))
end

local function spawnBurst(screen: Vector2)
	local s = free("burst")
	if not s then return end
	s.x = _rng:NextNumber(0.15, 0.85) * screen.X
	s.y = screen.Y + 6
	s.vx = _rng:NextNumber(-260, 260)
	s.vy = -_rng:NextNumber(520, 980)
	s.size = _rng:NextNumber(9, 17)
	s.spin = _rng:NextNumber(-540, 540)
	s.gui.Rotation = _rng:NextNumber(0, 360)
	setTint(s, PALETTE_VEIL[_rng:NextInteger(1, #PALETTE_VEIL)])
	if s.gui:IsA("ImageLabel") then
		(s.gui :: ImageLabel).ImageRectOffset = Vector2.new(64 * _rng:NextInteger(0, 3), 0)
	end
	activate(s, _rng:NextNumber(1.4, 2.2))
end

local function spawnSpeed(screen: Vector2)
	local s = free("speed")
	if not s then return end
	local left = _rng:NextNumber() < 0.5
	s.y = _rng:NextNumber(0.12, 0.88) * screen.Y
	s.x = if left then _rng:NextNumber(0.02, 0.2) * screen.X else _rng:NextNumber(0.8, 0.98) * screen.X
	s.vx = (if left then -1 else 1) * _rng:NextNumber(500, 900)   -- vom Zentrum nach aussen
	s.vy = 0
	s.size = _rng:NextNumber(0.18, 0.34) * screen.X               -- Laenge
	s.gui.Rotation = 0
	setTint(s, FX.colors.white)
	activate(s, _rng:NextNumber(0.28, 0.45))
end

local function spawnClouds(screen: Vector2)
	for _, s in (_pools.cloud or {}) do
		if not s.active then
			s.depth = _rng:NextNumber(0.4, 1.6)
			s.x = _rng:NextNumber(-0.2, 1.1) * screen.X
			s.y = _rng:NextNumber(0.1, 0.9) * screen.Y
			s.vx = -(60 + 220 * s.depth)               -- Parallax: nah = schnell
			s.vy = 0
			s.size = (90 + 170 * s.depth)
			setTint(s, FX.colors.white)
			activate(s, 99)                             -- lebt, bis das Fenster endet
		end
	end
end

local function layoutSprite(s: Sprite)
	if s.kind == "speed" then
		s.gui.Size = UDim2.fromOffset(s.size, math.max(3, s.size * 0.025))
	elseif s.kind == "cloud" then
		s.gui.Size = UDim2.fromOffset(s.size * 1.9, s.size * 0.55)
	elseif s.kind == "sparks" and A.sparkTex ~= "" then
		s.gui.Size = UDim2.fromOffset(s.size * 2.2, s.size * 2.2)
	else
		s.gui.Size = UDim2.fromOffset(s.size, if s.kind == "veil" or s.kind == "burst" then s.size * 1.35 else s.size)
	end
	s.gui.Position = UDim2.fromOffset(s.x, s.y)
end

--------------------------------------------------------------------------------
-- Aufbau
--------------------------------------------------------------------------------

local function buildVignette(root: Frame)
	-- Vier Randstreifen mit Verlauf nach innen (Transparenz 0 am Rand, 1 innen).
	local defs = {
		{ "Oben",   UDim2.new(1, 0, 0.34, 0), UDim2.fromScale(0, 0), 90 },
		{ "Unten",  UDim2.new(1, 0, 0.34, 0), UDim2.fromScale(0, 0.66), 270 },
		{ "Links",  UDim2.new(0.26, 0, 1, 0), UDim2.fromScale(0, 0), 0 },
		{ "Rechts", UDim2.new(0.26, 0, 1, 0), UDim2.fromScale(0.74, 0), 180 },
	}
	for _, d in defs do
		local f = frame("Vignette" .. (d[1] :: string), root, FX.colors.gold, 2)
		f.Size = d[2] :: UDim2
		f.Position = d[3] :: UDim2
		f.BackgroundTransparency = 1
		local g = Instance.new("UIGradient")
		g.Rotation = d[4] :: number
		g.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		g.Parent = f
		table.insert(_vig, f)
	end
end

local function buildLetterbox(root: Frame)
	for i = 1, 2 do
		local f = frame(if i == 1 then "LetterboxOben" else "LetterboxUnten", root, Color3.new(0, 0, 0), 6)
		f.AnchorPoint = Vector2.new(0, if i == 1 then 0 else 1)
		f.Position = UDim2.fromScale(0, if i == 1 then 0 else 1)
		f.Size = UDim2.new(1, 0, 0, 0)
		table.insert(_letter, f)
	end
end

local function buildSkip(root: Frame)
	local button = Instance.new("TextButton")
	button.Name = "SkipRing"
	button.Text = ""
	button.AutoButtonColor = false
	button.BackgroundColor3 = Color3.fromRGB(20, 24, 40)
	button.BackgroundTransparency = 0.45
	button.AnchorPoint = Vector2.new(1, 1)
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	button.Position = UDim2.new(1, -28, 1, if touch then -200 else -36)   -- ueber dem Sprung-Knopf
	button.Size = UDim2.fromOffset(62, 62)
	button.ZIndex = 60
	button.Visible = false
	button.Parent = root
	corner(button, 0.5)
	for i = 1, SKIP_DOTS do
		local a = (i - 1) / SKIP_DOTS * math.pi * 2 - math.pi / 2
		local d = frame("Punkt" .. i, button, FX.colors.white, 61)
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Size = UDim2.fromOffset(8, 8)
		d.Position = UDim2.new(0.5, math.cos(a) * 22, 0.5, math.sin(a) * 22)
		d.BackgroundTransparency = 0.7
		corner(d, 0.5)
		table.insert(_dots, d)
	end
	local center = frame("Mitte", button, FX.colors.gold, 61)   -- kleine Raute als Symbol, ohne Text
	center.AnchorPoint = Vector2.new(0.5, 0.5)
	center.Position = UDim2.fromScale(0.5, 0.5)
	center.Size = UDim2.fromOffset(14, 14)
	center.Rotation = 45
	corner(center, 0.15)
	_skip = button
end

local function buildFlare(root: Frame)
	if A.lensFlareTex ~= "" then
		local img = Instance.new("ImageLabel")
		img.Name = "LensFlare"
		img.Image = A.lensFlareTex
		img.BackgroundTransparency = 1
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Size = UDim2.fromOffset(420, 420)
		img.Position = UDim2.fromScale(0.62, 0.04)
		img.ImageTransparency = 1
		img.ZIndex = 14
		img.Parent = root
		table.insert(_flare, img :: any)
	else
		-- Ersatz: heller Kern und ein waagrechter Streifen am oberen Rand
		local core = frame("LensFlare", root, FX.colors.white, 14)
		core.AnchorPoint = Vector2.new(0.5, 0.5)
		core.Size = UDim2.fromOffset(120, 120)
		core.Position = UDim2.fromScale(0.62, 0.05)
		core.BackgroundTransparency = 1
		corner(core, 0.5)
		table.insert(_flare, core)
		local streak = frame("LensStreifen", root, FX.colors.gold, 14)
		streak.AnchorPoint = Vector2.new(0.5, 0.5)
		streak.Size = UDim2.fromOffset(520, 10)
		streak.Position = UDim2.fromScale(0.62, 0.05)
		streak.BackgroundTransparency = 1
		local g = Instance.new("UIGradient")
		g.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1),
		})
		g.Parent = streak
		corner(streak, 0.5)
		table.insert(_flare, streak)
	end
end

local function scaled(n: number): number
	return math.max(1, math.floor(n * (if _reduced then FX.reducedFactor else 1) + 0.5))
end

--------------------------------------------------------------------------------
-- Oeffentlich
--------------------------------------------------------------------------------

-- Baut die Schicht einmal (unsichtbar). Wiederholter Aufruf ist harmlos.
function EpilogOverlay.init()
	if _gui then return end
	local gui = Instance.new("ScreenGui")
	gui.Name = "RBL_Epilog"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 20
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Active = false
	root.Parent = gui
	_gui, _root = gui, root

	buildVignette(root)
	local glow = frame("KnopfGlow", root, FX.colors.red, 3)
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromOffset(260, 260)
	glow.BackgroundTransparency = 1
	corner(glow, 0.5)
	_glow = glow
	buildFlare(root)
	buildLetterbox(root)
	buildSkip(root)
	local flash = frame("Flash", root, FX.flash.color, 50)
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundTransparency = 1
	_flash = flash
	-- Finale-Texte (Loc-Texte setzt der Controller; hier nur die Huelle)
	local function label(name: string, y: number, size: number, color: Color3, z: number): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Position = UDim2.fromScale(0.5, y)
		l.Size = UDim2.fromOffset(900, size)
		l.Font = Enum.Font.FredokaOne
		l.TextScaled = true
		l.TextColor3 = color
		l.Text = ""
		l.TextTransparency = 1
		l.TextStrokeColor3 = Color3.fromRGB(70, 36, 8)
		l.TextStrokeTransparency = 1
		l.ZIndex = z
		l.Parent = root
		local sc = Instance.new("UIScale")
		sc.Parent = l
		return l
	end
	_count = label("Countdown", 0.4, 260, FX.colors.gold, 40)
	_banner = label("Banner", 0.3, 110, FX.colors.gold, 41)
	_hint = label("Hinweis", 0.84, 56, FX.colors.white, 41)
end

-- Beginnt eine Fahrt: Pools fuer die gewaehlte Staerke ("full" | "reduced").
function EpilogOverlay.begin(intensity: string)
	EpilogOverlay.init()
	EpilogOverlay.finish()
	_reduced = intensity == "reduced"
	_running = true
	_spawnAcc = {}
	for kind, n in FX.pools do
		local pool: { Sprite } = {}
		for _ = 1, scaled(n) do
			table.insert(pool, makeSprite(kind))
		end
		_pools[kind] = pool
	end
	local guiNow = _gui :: ScreenGui
	guiNow.Enabled = true
end

-- Raeumt alles ab (Teilchen, Zustand, Sichtbarkeit). Immer sicher aufrufbar.
function EpilogOverlay.finish()
	_running = false
	for _, pool in _pools do
		for _, s in pool do s.gui:Destroy() end
	end
	table.clear(_pools)
	table.clear(_spawnAcc)
	_flashKind = ""
	_rain = 0
	_vigManual = nil
	for _, l in { _count, _banner, _hint } do
		if l then l.Text = ""; l.TextTransparency = 1; l.TextStrokeTransparency = 1 end
	end
	if _flash then _flash.BackgroundTransparency = 1 end
	for _, v in _vig do v.BackgroundTransparency = 1 end
	for _, l in _letter do l.Size = UDim2.new(1, 0, 0, 0) end
	if _glow then _glow.BackgroundTransparency = 1 end
	for _, f in _flare do
		if f:IsA("ImageLabel") then (f :: any).ImageTransparency = 1 else f.BackgroundTransparency = 1 end
	end
	if _skip then _skip.Visible = false end
	if _gui then _gui.Enabled = false end
end

-- Zaehler fuer den Audit.
function EpilogOverlay.audit(): { [string]: any }
	local active, total = 0, 0
	for _, pool in _pools do
		for _, s in pool do
			total += 1
			if s.active then active += 1 end
		end
	end
	return {
		sichtbar = _gui ~= nil and _gui.Enabled,
		laeuft = _running,
		teilchenAktiv = active,
		teilchenPool = total,
		reduced = _reduced,
	}
end

-- Das Skip-Ring-Knopfobjekt (der Controller haengt Eingaben an).
function EpilogOverlay.skipButton(): TextButton?
	return _skip
end

-- Skip-Ring zeigen/verstecken; progress 0..1 fuellt die zwoelf Punkte.
function EpilogOverlay.setSkip(visible: boolean, progress: number)
	local button = _skip
	if not button then return end
	button.Visible = visible and _running
	local lit = math.floor(math.clamp(progress, 0, 1) * SKIP_DOTS + 0.5)
	for i, d in _dots do
		if i <= lit then
			d.BackgroundColor3 = FX.colors.gold
			d.BackgroundTransparency = 0
		else
			d.BackgroundColor3 = FX.colors.white
			d.BackgroundTransparency = 0.7
		end
	end
end

-- Weisser Flash jetzt: bei "restore" startet er voll und blendet in `seconds` aus
-- (Wiederaufnahme ohne Fahrt), sonst kurz hoch und wieder runter (z. B. beim Skip).
function EpilogOverlay.flashNow(seconds: number, kind: string?)
	EpilogOverlay.init()
	local guiNow = _gui :: ScreenGui
	guiNow.Enabled = true
	_flashKind = kind or "manual"
	_flashStart = os.clock()
	_flashEnd = _flashStart + seconds
end

-- Prompt 6 (Finale): grosse Zahl am Bildschirmrand-Zentrum (0/nil = weg). Pop-Animation.
function EpilogOverlay.setCountdown(n: number, text: string?)
	local l = _count
	if not l then return end
	if n <= 0 then
		l.TextTransparency = 1
		l.TextStrokeTransparency = 1
		return
	end
	l.Text = text or tostring(n)
	l.TextTransparency = 0
	l.TextStrokeTransparency = 0
	local sc = l:FindFirstChildOfClass("UIScale")
	if sc then
		sc.Scale = 1.6
		TweenService:Create(sc, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

local function popText(l: TextLabel?, text: string, seconds: number, from: number)
	if not l then return end
	l.Text = text
	l.TextTransparency = 0
	l.TextStrokeTransparency = 0
	local sc = l:FindFirstChildOfClass("UIScale")
	if sc then
		sc.Scale = from
		TweenService:Create(sc, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	task.delay(seconds, function()
		if l.Parent == nil or l.Text ~= text then return end
		TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
end

-- Banner (Gold mit Kontur) und Hinweis unten. Text kommt vom Aufrufer (Loc).
function EpilogOverlay.banner(text: string, seconds: number)
	popText(_banner, text, seconds, 0.3)
end

function EpilogOverlay.hint(text: string, seconds: number)
	popText(_hint, text, seconds, 0.8)
end

-- Eine Salve: Konfetti-Burst + Funken (Pools begrenzen die Anzahl).
function EpilogOverlay.salvo()
	if not _running then return end
	local screen = size()
	for _ = 1, #(_pools.burst or {}) do spawnBurst(screen) end
	for _ = 1, 5 do spawnSpark(screen) end
end

-- Konfetti-Regen von oben (Teilchen pro Sekunde, 0 = aus).
function EpilogOverlay.rain(perSecond: number)
	_rain = perSecond
end

-- Feste Randfarbe/-staerke (nil = Standard der Kamerafahrt, also keine Vignette).
function EpilogOverlay.setVignette(color: Color3?, alpha: number)
	_vigManual = if color then { color = color, alpha = alpha } else nil
end

local function flashAlpha(t: number, now: number): number
	local F = FX.flash
	local alpha = 0
	if t >= F.at and t < F.at + F.upSeconds + F.downSeconds then
		local u = t - F.at
		alpha = if u < F.upSeconds then u / F.upSeconds else 1 - (u - F.upSeconds) / F.downSeconds
	end
	if _flashKind ~= "" then
		local u = (now - _flashStart) / math.max(_flashEnd - _flashStart, 1e-3)
		if u >= 1 then
			_flashKind = ""
		elseif _flashKind == "restore" then
			alpha = math.max(alpha, 1 - u)
		else
			alpha = math.max(alpha, if u < 0.35 then u / 0.35 else 1 - (u - 0.35) / 0.65)
		end
	end
	return math.clamp(alpha, 0, 1)
end

-- Ein Bild: t = Sekunde der Sequenz (real), dt = Frame-Zeit, phase 1..6.
function EpilogOverlay.update(t: number, dt: number, phase: number)
	local root = _root
	if not root or not _running then return end
	local screen = size()
	local now = os.clock()
	dt = math.min(dt, 0.05)

	-- Flash
	local flash = _flash
	if flash then flash.BackgroundTransparency = 1 - flashAlpha(t, now) end

	-- Vignette: gold pulsiert im Sieg-Beat, dunkel vor dem Terminal-Reveal
	local vigAlpha, vigColor = 0, FX.colors.gold
	if inWindow(FX.vignetteGold, t) then
		vigColor = FX.colors.gold
		vigAlpha = 0.55 + 0.25 * math.sin(t * math.pi * 4)
	elseif t >= FX.vignetteDark[1] and phase <= 5 then
		vigColor = Color3.fromRGB(18, 20, 44)
		vigAlpha = 0.75 * math.min(1, (t - FX.vignetteDark[1]) / 1.5)
	end
	local manual = _vigManual
	if manual then vigColor, vigAlpha = manual.color, manual.alpha end
	for _, v in _vig do
		v.BackgroundColor3 = vigColor
		v.BackgroundTransparency = 1 - vigAlpha
	end

	-- Letterbox 2,35:1 (nur "full")
	if not _reduced then
		local lb = FX.letterbox
		local u = if t < lb[1] then 0 elseif t > lb[2] then 0 else math.min(1, (t - lb[1]) / lb[3])
		local bar = math.max(0, (screen.Y - screen.X / 2.35) / 2) * u
		for _, l in _letter do l.Size = UDim2.new(1, 0, 0, bar) end
	end

	-- Knopf-Puls im Zentrum (rot), waehrend die Vignette abdunkelt
	local glow = _glow
	if glow then
		if t >= FX.vignetteDark[1] and t < EpilogConfig.SEQUENCE.endAt then
			local pulse = 0.5 + 0.5 * math.sin((t - FX.vignetteDark[1]) * math.pi * 2 / 1.2)
			glow.BackgroundTransparency = 1 - (0.12 + 0.2 * pulse) * math.min(1, (t - FX.vignetteDark[1]) / 1.5)
			local s = 220 + 60 * pulse
			glow.Size = UDim2.fromOffset(s, s)
		else
			glow.BackgroundTransparency = 1
		end
	end

	-- Lens-Flare am oberen Rand (Insel-Reveal)
	local fl = envelope(FX.lensFlare, t, 0.6)
	for i, f in _flare do
		local a = fl * (if i == 1 then 0.55 else 0.7)
		if f:IsA("ImageLabel") then (f :: any).ImageTransparency = 1 - a else f.BackgroundTransparency = 1 - a end
	end

	-- Wolken-Overlay
	local cloudOn = inWindow(FX.clouds, t)
	if cloudOn then
		local pool = _pools.cloud
		if pool and not pool[1].active then spawnClouds(screen) end
	end

	-- Spawns (gleichmaessig ueber die Lebensdauer verteilt)
	local function emit(kind: string, perSecond: number, spawn: (Vector2) -> ())
		local acc = (_spawnAcc[kind] or 0) + perSecond * dt
		while acc >= 1 do
			acc -= 1
			spawn(screen)
		end
		_spawnAcc[kind] = acc
	end
	if inWindow(FX.sparks, t) then
		emit("sparks", #(_pools.sparks or {}) / 1.2, spawnSpark)
	end
	if inAnyWindow(FX.veil, t) then
		emit("veil", #(_pools.veil or {}) / 2.7, spawnVeil)
	end
	if inAnyWindow(FX.speedLines, t) then
		local env = 1
		for _, w in FX.speedLines do
			if inWindow(w, t) then env = envelope(w, t, 0.35) end
		end
		emit("speed", #(_pools.speed or {}) / 0.36 * math.max(env, 0.2), spawnSpeed)
	end
	if _rain > 0 then
		emit("veil", _rain, spawnRain)
	end
	if t >= FX.confettiBurstAt and _spawnAcc.burstDone ~= 1 then
		_spawnAcc.burstDone = 1
		for _ = 1, #(_pools.burst or {}) do spawnBurst(screen) end
	end

	-- Bewegen
	for _, pool in _pools do
		for _, s in pool do
			if s.active then
				s.age += dt
				local u = s.age / s.life
				if s.kind == "cloud" then
					s.x += s.vx * dt
					if s.x < -s.size * 1.2 then s.x = screen.X + s.size end
					local a = math.min(1, s.age / 0.6)
					if not cloudOn then
						deactivate(s)   -- Fenster vorbei: Wolke verschwindet (sie ist bereits hauchduenn)
					else
						setAlpha(s, a)
					end
				elseif u >= 1 then
					deactivate(s)
				else
					if s.kind == "burst" then s.vy += 900 * dt end
					s.x += s.vx * dt
					s.y += s.vy * dt
					s.gui.Rotation += s.spin * dt
					local a: number
					if s.kind == "sparks" then
						a = math.sin(math.pi * u) * (0.75 + 0.25 * math.sin(s.age * 14))   -- funkelt
					elseif s.kind == "speed" then
						a = math.sin(math.pi * u) * 0.8
					elseif s.kind == "burst" then
						a = if u < 0.7 then 1 else (1 - u) / 0.3
					else
						a = if u < 0.12 then u / 0.12 elseif u > 0.75 then (1 - u) / 0.25 else 0.9
					end
					setAlpha(s, a)
				end
				if s.active then layoutSprite(s) end
			end
		end
	end
end

return EpilogOverlay
