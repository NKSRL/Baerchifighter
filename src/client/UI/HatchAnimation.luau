--!strict
-- HatchAnimation.luau
-- StarterPlayerScripts/UI/HatchAnimation.luau
--
-- Einzige Zustaendigkeit:
--   - Die Ei-Oeffnen-Animation abspielen: Drop, Wackeln, Risse, Aufladen,
--     Burst in der Rarity-Farbe, Reveal-Karte des Baerchis.
--
-- Reine Client-Optik aus UI-Elementen, keine Assets. Der Server entscheidet
-- allein, was aus dem Ei kommt (EggService.openEgg) — die Animation startet
-- trotzdem SOFORT beim Klick (Drop + Wackeln in Schleife) und geht erst zu
-- Rissen und Burst ueber, wenn das Ergebnis da ist. So fuehlt sich der Klick
-- unmittelbar an, ohne dass der Client etwas vorwegnimmt.
--
-- Ablauf pro Ei (bei normaler Rarity rund 3 Sekunden):
--   1. Drop     — Ei faellt von oben ins Bild und federt
--   2. Wackeln  — drei Stufen, jede staerker, mit jeder ein Riss
--   3. Aufladen — starkes Zittern, Gluehen in der Rarity-Farbe
--   4. Burst    — weisser Blitz, Ring, Partikel in der Rarity-Farbe
--   5. Reveal   — Karte mit Name, Rarity, Level, NEU!, Mutation
--
-- Die Rarity bestimmt die Wucht (siehe intensityFor): ab Epic mehr Risse,
-- ab Legendary laenger Wackeln, Bildschirmzittern und mehr Partikel, ab Divine
-- zusaetzlich ein Lichtstrahl. Das skaliert ueber den Rarity-Index und
-- funktioniert damit auch fuer kuenftige Rarities ohne Code-Aenderung.
--
-- Mehrere Eier: jede Oeffnung kommt in eine Warteschlange und wird
-- nacheinander gezeigt. Ergebnisse kommen in derselben Reihenfolge an, in der
-- die Anfragen rausgingen (ein Remote, ein Server-Thread) — deshalb wird ein
-- eintreffendes Ergebnis immer der aeltesten noch offenen Oeffnung zugeordnet.
--
-- Ton: bewusst offen (keine verifizierten Sound-Assets).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local Types         = require(ReplicatedStorage.Network.Types)
local EggConfig     = require(ReplicatedStorage.Config.EggConfig)
local BaerchiConfig = require(ReplicatedStorage.Config.BaerchiConfig)

local BaerchiMesh   = require(ReplicatedStorage.Modules.BaerchiMesh)   -- Sammel-Update 2.2: Baerchi gross zeigen
local Loc           = require(ReplicatedStorage.Localization.Loc)

local Theme = require(script.Parent.Theme)
local EggIcon = require(script.Parent.EggIcon)
local Toast = require(script.Parent.Toast)
-- Sammel-Update: fehlte, Notify.emit beim Fehlschlag waere ein Laufzeitfehler.
local Notify = require(script.Parent.Notify)

local HatchAnimation = {}

--------------------------------------------------------------------------------
-- Zahlen (reine Optik, deshalb hier und nicht in einer Config)
--------------------------------------------------------------------------------

local DROP_SECONDS        = 0.4
local WOBBLE_STAGE_SECONDS = 0.45   -- pro Wackel-Stufe (3 Stufen = ~1,4 s)
local CHARGE_SECONDS      = 0.3
-- Sammel-Update 2.2 ("Ei-Oeffnen geht zu schnell weg"): das Ergebnis bleibt
-- mindestens REVEAL_MIN_SECONDS stehen (vorher 1,2 s + 0,8 s) und schliesst
-- danach erst durch Tippen oder nach REVEAL_AUTO_CLOSE Sekunden.
local REVEAL_SECONDS      = 2.5
local REVEAL_MIN_TAP      = 0.8     -- frueher als das schliesst auch ein Tipp nicht
local REVEAL_AUTO_CLOSE   = 7.0
local CARD_SIZE           = Vector2.new(360, 330)
local MODEL_VIEW_HEIGHT   = 150
local FADE_SECONDS        = 0.25
local RESULT_TIMEOUT      = 5       -- Sekunden ohne Server-Antwort, dann Abbruch
local SKIP_AFTER          = 1.0     -- ab hier beschleunigt ein Tap aufs Ergebnis
local EGG_SIZE            = Vector2.new(150, 190)
local BACKDROP_TRANSPARENCY = 0.35

--------------------------------------------------------------------------------
-- Zustand
--------------------------------------------------------------------------------

type Job = {
	eggType : Types.EggType,
	result  : Types.HatchResult?,
	failed  : string?,     -- Grund, falls der Server abgelehnt hat oder nichts kam
	silent  : boolean,     -- true = die Meldung hat schon der Toast gezeigt (ActionFailed)
	started : number,      -- os.clock() beim Klick (fuer den Timeout)
}

local _screenGui: ScreenGui? = nil
local _queue: { Job } = {}
local _running = false
local _skip = false

--------------------------------------------------------------------------------
-- Intensitaet nach Rarity
--------------------------------------------------------------------------------

type Intensity = {
	cracks    : number,    -- Risse insgesamt
	wobbleMul : number,    -- Faktor auf die Wackel-Dauer
	amplitude : number,    -- Grad, maximales Wackeln in der letzten Stufe
	particles : number,
	shake     : boolean,   -- Bildschirmzittern
	beam      : boolean,   -- Lichtstrahl hinter der Karte
	flash     : number,    -- Deckkraft des weissen Blitzes (0..1)
}

local function intensityFor(rarity: Types.Rarity): Intensity
	-- Common = 1 ... Omega = 12. Unbekannte Rarities zaehlen wie Common.
	local index = BaerchiConfig.getRarityIndex(rarity) or 1

	return {
		cracks    = if index >= 4 then 5 else 3,
		wobbleMul = if index >= 5 then 1.35 else 1,
		amplitude = math.min(10 + index * 2.5, 32),
		particles = math.min(10 + index * 4, 56),
		shake     = index >= 5,
		beam      = index >= 7,
		flash     = if index >= 4 then 0.95 else 0.6,
	}
end

--------------------------------------------------------------------------------
-- Hilfen
--------------------------------------------------------------------------------

local function tween(instance: Instance, seconds: number, props: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local info = TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
	local t = TweenService:Create(instance, info, props)
	t:Play()
	return t
end

-- Wartet `seconds`, bricht aber frueher ab, sobald der Spieler ueberspringt.
local function waitSkippable(seconds: number)
	local untilTime = os.clock() + seconds
	while os.clock() < untilTime do
		if _skip then return end
		RunService.RenderStepped:Wait()
	end
end

local function newFrame(name: string, parent: Instance, size: UDim2, position: UDim2, color: Color3): Frame
	local frame = Instance.new("Frame")
	frame.Name             = name
	frame.Size             = size
	frame.Position         = position
	frame.AnchorPoint      = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel  = 0
	frame.Parent           = parent
	return frame
end

local function round(frame: Frame)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = frame
end

--------------------------------------------------------------------------------
-- Bausteine der Szene
--------------------------------------------------------------------------------

type Scene = {
	root     : Frame,     -- Vollbild, faengt Taps
	backdrop : Frame,
	stage    : Frame,     -- traegt alles, wird beim Bildschirmzittern verschoben
	glow     : Frame,
	egg      : Frame,
	eggStroke: UIStroke,
	cracks   : Frame,
	label    : TextLabel,
}

local function buildScene(screenGui: ScreenGui, eggType: Types.EggType): Scene
	local eggDef   = EggConfig.data[eggType]
	local eggColor = if eggDef then eggDef.color else Color3.fromRGB(238, 232, 214)

	local root = Instance.new("TextButton")
	root.Name                   = "HatchAnimation"
	root.Text                   = ""
	root.AutoButtonColor        = false
	root.BackgroundTransparency = 1
	root.Size                   = UDim2.fromScale(1, 1)
	root.ZIndex                 = 50
	root.Parent                 = screenGui

	local backdrop = newFrame("Backdrop", root, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), Color3.new(0, 0, 0))
	backdrop.BackgroundTransparency = 1
	backdrop.ZIndex = 50

	local stage = Instance.new("Frame")
	stage.Name                   = "Stage"
	stage.BackgroundTransparency = 1
	stage.Size                   = UDim2.fromScale(1, 1)
	stage.ZIndex                 = 51
	stage.Parent                 = root

	-- Leuchten hinter dem Ei (erst beim Aufladen sichtbar)
	local glow = newFrame("Glow", stage, UDim2.fromOffset(EGG_SIZE.X * 1.6, EGG_SIZE.Y * 1.5), UDim2.fromScale(0.5, 0.48), Color3.new(1, 1, 1))
	glow.BackgroundTransparency = 1
	glow.ZIndex = 51
	round(glow)

	-- Das Ei: eine Ellipse in der Ei-Farbe mit dickem Cartoon-Rand
	local egg = newFrame("Egg", stage, UDim2.fromOffset(EGG_SIZE.X, EGG_SIZE.Y), UDim2.new(0.5, 0, -0.3, 0), eggColor)
	egg.ZIndex = 52
	round(egg)
	local stroke = Theme.stroke(egg, Theme.COLORS.outline, 4)
	Theme.gradient(egg, Theme.shade(eggColor, 0.25), Theme.shade(eggColor, -0.15))

	-- Muster und Glanzpunkt wie auf dem Ei in der Welt (EggIcon/EggLook)
	EggIcon.decorate(egg, eggType, EGG_SIZE.X / EGG_SIZE.Y, 53)

	local cracks = Instance.new("Frame")
	cracks.Name                   = "Cracks"
	cracks.BackgroundTransparency = 1
	cracks.Size                   = UDim2.fromScale(1, 1)
	cracks.ZIndex                 = 54
	cracks.Parent                 = egg

	local label = Theme.label("Hint", stage, if eggDef then eggDef.displayName else tostring(eggType))
	label.AnchorPoint    = Vector2.new(0.5, 0)
	label.Position       = UDim2.new(0.5, 0, 0.48, EGG_SIZE.Y * 0.5 + 18)
	label.Size           = UDim2.fromOffset(320, 30)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.ZIndex         = 55
	Theme.outlineText(label)

	return {
		root = root, backdrop = backdrop, stage = stage, glow = glow,
		egg = egg, eggStroke = stroke, cracks = cracks, label = label,
	}
end

-- Ein Riss: zwei kurze, dunkle, schraeg gestellte Striche als Zickzack.
local function addCrack(scene: Scene, index: number)
	local x = 0.25 + ((index * 0.37) % 0.5)
	local y = 0.30 + ((index * 0.23) % 0.4)
	local base = (index % 2 == 0) and 35 or -35

	for part = 0, 1 do
		local line = newFrame("Crack" .. index .. "_" .. part, scene.cracks,
			UDim2.new(0, 0, 0, 4),
			UDim2.fromScale(x + part * 0.08, y + part * 0.07),
			Theme.COLORS.outline)
		line.Rotation = base * (if part == 0 then 1 else -1)
		line.ZIndex   = 54
		tween(line, 0.12, { Size = UDim2.new(0.22, 0, 0, 4) })
	end
end

-- Partikel: kleine Quadrate, die in alle Richtungen auseinanderfliegen.
local function burstParticles(scene: Scene, color: Color3, count: number)
	for index = 1, count do
		local angle    = (index / count) * math.pi * 2 + math.random() * 0.4
		local distance = 180 + math.random() * 220
		local size     = 8 + math.random() * 10

		local particle = newFrame("Particle", scene.stage, UDim2.fromOffset(size, size), UDim2.fromScale(0.5, 0.48),
			if index % 3 == 0 then Color3.new(1, 1, 1) else color)
		particle.ZIndex   = 56
		particle.Rotation = math.random(0, 90)

		tween(particle, 0.6 + math.random() * 0.3, {
			Position = UDim2.new(0.5, math.cos(angle) * distance, 0.48, math.sin(angle) * distance),
			BackgroundTransparency = 1,
			Rotation = particle.Rotation + 180,
		})
		task.delay(1, function()
			particle:Destroy()
		end)
	end
end

local function burstRing(scene: Scene, color: Color3)
	local ring = newFrame("Ring", scene.stage, UDim2.fromOffset(60, 60), UDim2.fromScale(0.5, 0.48), color)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 55
	round(ring)
	local stroke = Theme.stroke(ring, color, 10)

	tween(ring, 0.55, { Size = UDim2.fromOffset(620, 620) })
	tween(stroke, 0.55, { Transparency = 1, Thickness = 2 })
	task.delay(0.6, function()
		ring:Destroy()
	end)
end

local function flash(scene: Scene, strength: number)
	local white = newFrame("Flash", scene.root, UDim2.fromScale(1, 1), UDim2.fromScale(0.5, 0.5), Color3.new(1, 1, 1))
	white.BackgroundTransparency = 1 - strength
	white.ZIndex = 60
	tween(white, 0.45, { BackgroundTransparency = 1 })
	task.delay(0.5, function()
		white:Destroy()
	end)
end

local function shakeScreen(scene: Scene, seconds: number, strength: number)
	task.spawn(function()
		local untilTime = os.clock() + seconds
		while os.clock() < untilTime and scene.stage.Parent do
			scene.stage.Position = UDim2.fromOffset(
				math.random(-strength, strength),
				math.random(-strength, strength)
			)
			RunService.RenderStepped:Wait()
		end
		if scene.stage.Parent then
			scene.stage.Position = UDim2.fromOffset(0, 0)
		end
	end)
end

local function beam(scene: Scene, color: Color3)
	for index = 0, 2 do
		local ray = newFrame("Beam" .. index, scene.stage, UDim2.fromOffset(70, 0), UDim2.fromScale(0.5, 0.48), color)
		ray.BackgroundTransparency = 0.35
		ray.Rotation = -20 + index * 20
		ray.ZIndex   = 51
		Theme.gradient(ray, Theme.shade(color, 0.6), color, 0)
		tween(ray, 0.35, { Size = UDim2.fromOffset(70, 1400) })
		task.delay(REVEAL_SECONDS + 0.4, function()
			if ray.Parent then
				tween(ray, FADE_SECONDS, { BackgroundTransparency = 1 })
			end
		end)
	end
end

-- Die Reveal-Karte. Eine Mutation uebernimmt Farbe und Titel und bekommt
-- zusaetzlich einen farbigen Ring um die Karte.
local function buildReveal(scene: Scene, result: Types.HatchResult): Frame
	local baerchi  = result.baerchi
	local def      = BaerchiConfig.getById(baerchi.configId)
	local mutation = baerchi.mutation
	local rarityColor = Theme.rarityColor(baerchi.rarity)
	local color = if mutation then BaerchiConfig.getMutationColor(mutation) else rarityColor

	local card = Theme.panel("RevealCard", scene.stage, Theme.COLORS.panelDeep)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position    = UDim2.fromScale(0.5, 0.48)
	card.Size        = UDim2.fromOffset(0, 0)
	card.ZIndex      = 57

	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color     = color
		stroke.Thickness = 5
	end

	if mutation then
		local ring = newFrame("MutationRing", card, UDim2.new(1, 22, 1, 22), UDim2.fromScale(0.5, 0.5), color)
		ring.BackgroundTransparency = 1
		ring.ZIndex = 56
		Theme.corner(ring, 22)
		Theme.stroke(ring, color, 4)
	end

	local function cardLabel(name: string, text: string, y: number, height: number, textColor: Color3): TextLabel
		local label = Theme.label(name, card, text)
		label.AnchorPoint    = Vector2.new(0.5, 0)
		label.Position       = UDim2.new(0.5, 0, 0, y)
		label.Size           = UDim2.new(1, -24, 0, height)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextColor3     = textColor
		label.ZIndex         = 58
		return label
	end

	if result.isNew then
		local new = cardLabel("New", Loc.t("ui.hatch.new"), 10, 22, Theme.COLORS.goldGummy)
		Theme.outlineText(new)
	end

	-- Sammel-Update 2.2 (Luccini: "Baerchen bei Eioeffnung zeigen"): der
	-- Baerchi selbst, gross und drehend, in einem ViewportFrame.
	local view = Instance.new("ViewportFrame")
	view.Name                   = "Model"
	view.AnchorPoint            = Vector2.new(0.5, 0)
	view.Position               = UDim2.new(0.5, 0, 0, 34)
	view.Size                   = UDim2.new(1, -40, 0, MODEL_VIEW_HEIGHT)
	view.BackgroundTransparency = 1
	view.ZIndex                 = 58
	view.Ambient                = Color3.fromRGB(200, 200, 210)
	view.LightColor             = Color3.fromRGB(255, 250, 235)
	view.Parent                 = card
	local okModel, model = pcall(function()
		return BaerchiMesh.build(Vector3.zero, rarityColor, baerchi.rarity,
			if mutation then BaerchiConfig.getMutationColor(mutation) else nil)
	end)
	if okModel and model then
		model.Parent = view
		local cf, size = model:GetBoundingBox()
		local camera = Instance.new("Camera")
		camera.FieldOfView = 30
		local radius = math.max(size.X, size.Y, size.Z)
		local distance = radius / (2 * math.tan(math.rad(camera.FieldOfView / 2))) * 1.1
		camera.Parent = view
		view.CurrentCamera = camera
		-- Langsam drehen, solange die Karte steht (Ende: Karte zerstoert).
		local center = cf.Position
		local spin = 0
		local conn: RBXScriptConnection? = nil
		conn = RunService.RenderStepped:Connect(function(dt)
			if not view.Parent then
				if conn then conn:Disconnect() end
				return
			end
			spin += dt * 0.9
			local dir = Vector3.new(math.sin(spin), 0.3, math.cos(spin)).Unit
			camera.CFrame = CFrame.lookAt(center + dir * distance, center)
		end)
	end

	local title = (if mutation then Loc.name("mutation." .. mutation .. ".name", BaerchiConfig.getMutationDisplayName(mutation)):upper() .. "  " else "")
		.. Loc.name("baerchi." .. baerchi.configId .. ".name", if def then def.displayName else baerchi.configId)
	local base = 34 + MODEL_VIEW_HEIGHT
	local titleLabel = cardLabel("Title", title, base + 2, 34, color)
	Theme.outlineText(titleLabel)

	cardLabel("Rarity", string.upper(Loc.t("rarity." .. baerchi.rarity)), base + 40, 24, rarityColor)

	local eggName = Loc.name("egg." .. tostring(result.eggType) .. ".name", tostring(result.eggType))
	local sub = cardLabel("Sub", Loc.t("ui.hatch.sub", {
		level = baerchi.level,
		mutation = if mutation then string.format("  •  %s x%.2g", Loc.name("mutation." .. mutation .. ".name", BaerchiConfig.getMutationDisplayName(mutation)), BaerchiConfig.getMutationMultiplier(mutation)) else "",
		egg = eggName,
	}), base + 66, 40, Theme.COLORS.textDim)
	sub.Font       = Theme.FONT_BODY
	sub.TextScaled = false
	sub.TextSize   = 15

	local tapHint = cardLabel("Tap", Loc.t("ui.hatch.tap_close"), CARD_SIZE.Y - 22, 16, Theme.COLORS.textDim)
	tapHint.TextScaled = false
	tapHint.TextSize   = 13

	tween(card, 0.28, { Size = UDim2.fromOffset(CARD_SIZE.X, CARD_SIZE.Y) }, Enum.EasingStyle.Back)
	return card
end

--------------------------------------------------------------------------------
-- Ablauf einer Oeffnung
--------------------------------------------------------------------------------

local function play(job: Job)
	local screenGui = _screenGui
	if not screenGui then return end

	_skip = false
	local scene = buildScene(screenGui, job.eggType)
	local opened = os.clock()

	scene.root.Activated:Connect(function()
		if os.clock() - opened >= SKIP_AFTER then
			_skip = true
		end
	end)

	-- 1. Drop
	tween(scene.backdrop, 0.25, { BackgroundTransparency = BACKDROP_TRANSPARENCY })
	tween(scene.egg, DROP_SECONDS, { Position = UDim2.fromScale(0.5, 0.48) }, Enum.EasingStyle.Bounce)
	task.wait(DROP_SECONDS)

	-- 2. Wackeln — in Schleife, bis das Ergebnis da ist (oder der Timeout greift).
	-- Danach noch die drei Stufen bis zum Burst. Die Stufen-Dauer haengt an der
	-- Rarity, die erst mit dem Ergebnis bekannt ist — vorher wackelt das Ei
	-- mit der leichtesten Stufe.
	local wobbleClock = 0
	local amplitude = 6
	local connection = RunService.RenderStepped:Connect(function(delta)
		wobbleClock += delta
		scene.egg.Rotation = math.sin(wobbleClock * 18) * amplitude
	end)

	while not job.result and not job.failed do
		if os.clock() - job.started > RESULT_TIMEOUT then
			job.failed = Loc.t("err.hatch_timeout")
			break
		end
		RunService.RenderStepped:Wait()
	end

	local result = job.result
	if not result then
		connection:Disconnect()
		if not job.silent then
			Notify.emit("hatch_failed", function()
				Toast.show(job.failed or Loc.t("err.hatch_failed"), Theme.COLORS.bad)
			end)
		end
		tween(scene.backdrop, FADE_SECONDS, { BackgroundTransparency = 1 })
		tween(scene.egg, FADE_SECONDS, { BackgroundTransparency = 1, Position = UDim2.fromScale(0.5, 1.3) })
		task.wait(FADE_SECONDS)
		scene.root:Destroy()
		return
	end

	local rarityColor = Theme.rarityColor(result.baerchi.rarity)
	local intensity   = intensityFor(result.baerchi.rarity)

	-- Wackel-Stufen mit Rissen
	local crackIndex = 0
	local stages = 3
	for stage = 1, stages do
		amplitude = intensity.amplitude * (stage / stages)
		local cracksNow = math.floor(intensity.cracks * stage / stages) - crackIndex
		for _ = 1, cracksNow do
			crackIndex += 1
			addCrack(scene, crackIndex)
		end
		waitSkippable(WOBBLE_STAGE_SECONDS * intensity.wobbleMul)
		if _skip then break end
	end

	-- 3. Aufladen: Zittern, Gluehen in der Rarity-Farbe
	if not _skip then
		scene.glow.BackgroundColor3 = rarityColor
		tween(scene.glow, CHARGE_SECONDS, { BackgroundTransparency = 0.35, Size = UDim2.fromOffset(EGG_SIZE.X * 2.1, EGG_SIZE.Y * 1.9) })
		tween(scene.eggStroke, CHARGE_SECONDS, { Color = rarityColor, Thickness = 8 })
		amplitude = intensity.amplitude * 1.4
		wobbleClock *= 2.5
		waitSkippable(CHARGE_SECONDS)
	end
	connection:Disconnect()

	-- 4. Burst
	flash(scene, intensity.flash)
	burstRing(scene, rarityColor)
	burstParticles(scene, rarityColor, intensity.particles)
	if intensity.shake then
		shakeScreen(scene, 0.45, 10)
	end
	if intensity.beam then
		beam(scene, rarityColor)
	end

	scene.egg.Visible  = false
	scene.label.Visible = false
	tween(scene.glow, 0.5, { BackgroundTransparency = 1 })

	-- 5. Reveal
	local card = buildReveal(scene, result)

	-- Nach dem Burst darf ein Tap die Karte sofort schliessen.
	_skip = false
	local revealStart = os.clock()
	-- Sammel-Update 2.2: steht mindestens REVEAL_SECONDS (plus Zuschlag fuer
	-- seltene), ein Tipp schliesst ab REVEAL_MIN_TAP, sonst nach REVEAL_AUTO_CLOSE.
	-- Warten in der Schlange weitere Eier, geht es nach der Mindestzeit weiter.
	local minimum = REVEAL_SECONDS + (if intensity.beam then 0.8 elseif intensity.shake then 0.4 else 0)
	while true do
		local shown = os.clock() - revealStart
		if _skip and shown > REVEAL_MIN_TAP then break end
		if shown >= REVEAL_AUTO_CLOSE then break end
		if shown >= minimum and #_queue > 1 then break end
		RunService.RenderStepped:Wait()
	end

	tween(scene.backdrop, FADE_SECONDS, { BackgroundTransparency = 1 })
	tween(card, FADE_SECONDS, { Size = UDim2.fromOffset(0, 0) }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	task.wait(FADE_SECONDS)
	scene.root:Destroy()
end

local function pump()
	if _running then return end
	_running = true

	task.spawn(function()
		while #_queue > 0 do
			local job = _queue[1]
			local ok, err = pcall(play, job)
			if not ok then
				warn("[HatchAnimation] Abspielen fehlgeschlagen:", err)
				local gui = _screenGui
				local leftover = if gui then gui:FindFirstChild("HatchAnimation") else nil
				if leftover then leftover:Destroy() end
			end
			table.remove(_queue, 1)
		end
		_running = false
	end)
end

--------------------------------------------------------------------------------
-- Oeffentliche API
--------------------------------------------------------------------------------

-- Beim Klick auf "Oeffnen": startet (oder reiht ein) eine Animation fuer
-- dieses Ei. Das Ergebnis liefert spaeter deliver().
function HatchAnimation.request(eggType: Types.EggType)
	table.insert(_queue, {
		eggType = eggType,
		result  = nil,
		failed  = nil,
		silent  = false,
		started = os.clock(),
	})
	pump()
end

-- Die aelteste noch offene Oeffnung, oder nil.
local function oldestPending(): Job?
	for _, job in _queue do
		if not job.result and not job.failed then
			return job
		end
	end
	return nil
end

-- Server-Ergebnis eingetroffen. Ohne offene Oeffnung (z.B. ein Debug-Befehl
-- aus der Command Bar) wird eine neue Animation direkt mit Ergebnis gestartet.
function HatchAnimation.deliver(result: Types.HatchResult)
	local job = oldestPending()
	if job then
		job.result = result
		return
	end

	table.insert(_queue, {
		eggType = result.eggType,
		result  = result,
		failed  = nil,
		silent  = false,
		started = os.clock(),
	})
	pump()
end

-- Der Server hat das Oeffnen abgelehnt (ActionFailed fuer RequestHatchEgg).
-- Die Fehlermeldung zeigt der Toast ohnehin — hier wird nur die Animation
-- ohne eigene zweite Meldung beendet.
function HatchAnimation.reject(reason: string)
	local job = oldestPending()
	if job then
		job.failed = reason
		job.silent = true
	end
end

function HatchAnimation.init(screenGui: ScreenGui)
	_screenGui = screenGui

	-- Beim Verlassen nichts haengen lassen
	Players.LocalPlayer.AncestryChanged:Connect(function()
		table.clear(_queue)
	end)

	print("[HatchAnimation] Initialisiert")
end

return HatchAnimation
