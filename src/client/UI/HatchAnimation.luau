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
local Loc           = require(ReplicatedStorage.Localization.Loc)
local Names         = require(ReplicatedStorage.Localization.Names)

local HatchFxConfig   = require(ReplicatedStorage.Config.HatchFxConfig)
local EggHatch       = require(ReplicatedStorage.VFX.EggHatch)   -- R6: die neue Inszenierung
local BaerchiMesh   = require(ReplicatedStorage.Modules.BaerchiMesh)   -- Sammel-Update 2.2: Baerchi gross zeigen
local Loc           = require(ReplicatedStorage.Localization.Loc)

local AudioController = require(script.Parent.Parent.Controllers.AudioController)
local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)
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
	batch   : boolean?,    -- 15.10.: "10 oeffnen" (Ergebnis kommt als Liste in `results`)
	results : { Types.HatchResult }?,
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
	art      : ImageLabel?,   -- gemaltes Ei-Bild (falls vorhanden)
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

	-- 13.10.: Gibt es ein gemaltes Ei-Bild, zeigt die Animation genau dieses
	-- Bild (wie Menue und Ei-Baum); sonst das gezeichnete Ersatz-Ei.
	local art: ImageLabel? = nil
	local imageId = EggIcon.imageId(tostring(eggType))
	if imageId then
		egg.BackgroundTransparency = 1
		stroke.Enabled = false
		local image = Instance.new("ImageLabel")
		image.Name                   = "Art"
		image.BackgroundTransparency = 1
		image.Image                  = imageId
		image.ScaleType              = Enum.ScaleType.Fit
		image.AnchorPoint            = Vector2.new(0.5, 0.5)
		image.Position               = UDim2.fromScale(0.5, 0.5)
		image.Size                   = UDim2.fromScale(1.3, 1.08)
		image.ZIndex                 = 53
		image.Parent                 = egg
		art = image
	else
		Theme.gradient(egg, Theme.shade(eggColor, 0.25), Theme.shade(eggColor, -0.15))
		-- Muster und Glanzpunkt wie auf dem Ei in der Welt (EggIcon/EggLook)
		EggIcon.decorate(egg, eggType, EGG_SIZE.X / EGG_SIZE.Y, 53)
	end

	local cracks = Instance.new("Frame")
	cracks.Name                   = "Cracks"
	cracks.BackgroundTransparency = 1
	cracks.Size                   = UDim2.fromScale(1, 1)
	cracks.ZIndex                 = 54
	cracks.Parent                 = egg

	local label = Theme.label("Hint", stage, Names.egg(tostring(eggType)))
	label.AnchorPoint    = Vector2.new(0.5, 0)
	label.Position       = UDim2.new(0.5, 0, 0.48, EGG_SIZE.Y * 0.5 + 18)
	label.Size           = UDim2.fromOffset(320, 30)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.ZIndex         = 55
	Theme.outlineText(label)

	return {
		root = root, backdrop = backdrop, stage = stage, glow = glow,
		egg = egg, eggStroke = stroke, cracks = cracks, label = label, art = art,
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
		return BaerchiMesh.buildFor(baerchi.configId, Vector3.zero, rarityColor, baerchi.rarity,
			if mutation then BaerchiConfig.getMutationColor(mutation) else nil, baerchi.configId)
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
			local dir = Vector3.new(math.sin(spin), 0.3, -math.cos(spin)).Unit   -- R6: Start vorn (-Z)
			camera.CFrame = CFrame.lookAt(center + dir * distance, center)
		end)
	end

	local title = (if mutation then Loc.name("mutation." .. mutation .. ".name", BaerchiConfig.getMutationDisplayName(mutation)):upper() .. "  " else "")
		.. Names.baerchi(baerchi.configId)
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

--------------------------------------------------------------------------------
-- Absicherung gegen haengende Animationen (Playtest 21.10.: nach ca. 30 Minuten
-- wurde die Animation uebersprungen, die Eier waren trotzdem weg, und man
-- sah nicht, was man gezogen hatte; erst ein Rejoin half).
-- Ursache: Die Warteschlange (pump) wartete ohne Zeitlimit auf das Ende EINER
-- Animation. Haengt eine einzige (Signal verpasst, Szene von aussen zerstoert,
-- OK-Knopf weg), wartet jede weitere Oeffnung unsichtbar dahinter.
--------------------------------------------------------------------------------

local JOB_LIMIT_SINGLE = 40    -- Sekunden: Einzel-Ei komplett (inkl. Auto-Schliessen)
local JOB_LIMIT_BATCH  = 150   -- Sekunden: "x3/x10 oeffnen" (Spieler klickt OK)

-- Wartet auf das Ende der Inszenierung, aber hoechstens `maxSeconds`.
local function waitFinished(handle: EggHatch.Handle, maxSeconds: number)
	local t0 = os.clock()
	while not handle.finished and os.clock() - t0 < maxSeconds do
		task.wait(0.05)
	end
	if not handle.finished then
		warn("[HatchAnimation] Szene meldet kein Ende nach", maxSeconds, "s - wird beendet")
		handle.destroy()
	end
end

-- Notnagel: Hat die Animation nicht (richtig) gespielt, steht das Ergebnis
-- wenigstens als Toast da, damit man nicht im Inventar nachsehen muss.
local function showFallbackResult(job: any)
	local list: { string } = {}
	local function add(r: any)
		local b = if typeof(r) == "table" then r.baerchi else nil
		if typeof(b) ~= "table" then return end
		table.insert(list, string.format("%s (%s)", Names.baerchi(b.configId), Loc.t("rarity." .. tostring(b.rarity))))
	end
	if job.result then add(job.result) end
	if job.results then
		for i, r in job.results do
			if i > 6 then break end
			add(r)
		end
	end
	if #list == 0 then return end
	local more = if job.results and #job.results > 6 then " ..." else ""
	local text = Loc.t("ui.hatch.fallback", { list = table.concat(list, ", ") .. more })
	Notify.emit("hatch_fallback", function()
		Toast.show(text, Theme.COLORS.good)
	end)
end

-- R6: Einzel-Ei ueber VFX/EggHatch. Das Ergebnis ist vor dem Start bekannt (der Server
-- hat gerollt); bis es da ist, passiert nichts, bei Timeout kommt die Fehlermeldung.
local function play(job: Job)
	local screenGui = _screenGui
	if not screenGui then return end

	while not job.result and not job.failed do
		if os.clock() - job.started > RESULT_TIMEOUT then
			job.failed = Loc.t("err.hatch_timeout")
			break
		end
		RunService.RenderStepped:Wait()
	end
	local result = job.result
	if not result then
		if not job.silent then
			Notify.emit("hatch_failed", function()
				Toast.show(job.failed or Loc.t("err.hatch_failed"), Theme.COLORS.bad)
			end)
		end
		return
	end

	local baerchi = result.baerchi
	local handle = EggHatch.play({
		parent   = screenGui,
		eggType  = tostring(result.eggType),
		rarity   = baerchi.rarity,
		configId = baerchi.configId,
		level    = baerchi.level,
		mutation = baerchi.mutation,
		isNew    = result.isNew == true,
	})
	waitFinished(handle, JOB_LIMIT_SINGLE - 5)
end

-- Alte Inszenierung (Ellipse + Karte), nicht mehr benutzt; bleibt als Rueckfall im Code.
local function playLegacy(job: Job)
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
		if scene.art then tween(scene.art, FADE_SECONDS, { ImageTransparency = 1 }) end
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
			if crackIndex == 1 or crackIndex == 3 then AudioController.play("hatchCrack") end
		end
		waitSkippable(WOBBLE_STAGE_SECONDS * intensity.wobbleMul)
		if _skip then break end
	end

	-- 3. Aufladen: Zittern, Gluehen in der Rarity-Farbe
	if not _skip then
		scene.glow.BackgroundColor3 = rarityColor
		tween(scene.glow, CHARGE_SECONDS, { BackgroundTransparency = 0.35, Size = UDim2.fromOffset(EGG_SIZE.X * 2.1, EGG_SIZE.Y * 1.9) })
		tween(scene.eggStroke, CHARGE_SECONDS, { Color = rarityColor, Thickness = 8 })
		if scene.art then tween(scene.art, CHARGE_SECONDS, { ImageColor3 = Color3.new(1, 1, 1):Lerp(rarityColor, 0.35) }) end
		amplitude = intensity.amplitude * 1.4
		wobbleClock *= 2.5
		waitSkippable(CHARGE_SECONDS)
	end
	connection:Disconnect()

	-- 4. Burst
	-- Audio-Rework 16.10.: normales Schluepfen = kleiner weicher Klang; ab der
	-- Stufe mit Bildschirmzittern der grosse Jingle (senkt die Musik ab).
	AudioController.play(if intensity.shake then "hatchRare" else "hatchCommon")
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

--------------------------------------------------------------------------------
-- 15.10.: "10 oeffnen" — eine kurze Ei-Animation, danach alle Pets in kleinen
-- Fenstern (2 Reihen x 5), die bis zum Klick auf OK stehen bleiben.
--------------------------------------------------------------------------------

local GRID_COLS = 5

local function attachSpinningModel(view: ViewportFrame, baerchi: any, rarityColor: Color3)
	local mutation = baerchi.mutation
	local okModel, model = pcall(function()
		return BaerchiMesh.build(Vector3.zero, rarityColor, baerchi.rarity,
			if mutation then BaerchiConfig.getMutationColor(mutation) else nil, baerchi.configId)
	end)
	if not (okModel and model) then return end
	-- R6: Start in Vorderansicht, dann sanftes Pendeln (frueher: Vollrotation ab +Z = Rueckseite)
	EggHatch.attachPet(view, model, { sway = true })
end

local function miniLabel(parent: Instance, name: string, text: string, y: number, h: number, color: Color3, maxSize: number): TextLabel
	local label = Theme.label(name, parent, text)
	label.AnchorPoint    = Vector2.new(0.5, 0)
	label.Position       = UDim2.fromScale(0.5, y)
	label.Size           = UDim2.fromScale(0.94, h)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextColor3     = color
	label.TextScaled     = true
	label.ZIndex         = 59
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize
	c.Parent = label
	return label
end

local function buildMiniCard(parent: Instance, result: Types.HatchResult, order: number): Frame
	local baerchi = result.baerchi
	local mutation = baerchi.mutation
	local rarityColor = Theme.rarityColor(baerchi.rarity)
	local color = if mutation then BaerchiConfig.getMutationColor(mutation) else rarityColor

	local card = Theme.panel("Mini" .. order, parent, Theme.COLORS.panelDeep)
	card.LayoutOrder = order
	card.ZIndex = 58
	local stroke = card:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
		stroke.Thickness = 3
	end

	local view = Instance.new("ViewportFrame")
	view.Name = "Model"
	view.AnchorPoint = Vector2.new(0.5, 0)
	view.Position = UDim2.fromScale(0.5, 0.11)
	view.Size = UDim2.fromScale(0.92, 0.5)
	view.BackgroundTransparency = 1
	view.ZIndex = 59
	view.Ambient = Color3.fromRGB(200, 200, 210)
	view.LightColor = Color3.fromRGB(255, 250, 235)
	view.Parent = card
	attachSpinningModel(view, baerchi, rarityColor)

	if result.isNew then
		local new = miniLabel(card, "New", Loc.t("ui.hatch.new"), 0.01, 0.11, Theme.COLORS.goldGummy, 16)
		Theme.outlineText(new)
	end

	local title = (if mutation then Loc.name("mutation." .. mutation .. ".name", BaerchiConfig.getMutationDisplayName(mutation)) .. " " else "")
		.. Names.baerchi(baerchi.configId)
	local name = miniLabel(card, "Title", title, 0.63, 0.17, color, 20)
	Theme.outlineText(name)
	miniLabel(card, "Rarity", string.upper(Loc.t("rarity." .. baerchi.rarity)), 0.81, 0.11, rarityColor, 14)
	miniLabel(card, "Level", "Lv " .. tostring(baerchi.level), 0.91, 0.08, Theme.COLORS.textDim, 12)

	return card
end

local function playBatch(job: Job)
	local screenGui = _screenGui
	if not screenGui then return end

	_skip = false
	-- Ergebnis abwarten (der Server hat gerollt)
	while not job.results and not job.failed do
		if os.clock() - job.started > RESULT_TIMEOUT then
			job.failed = Loc.t("err.hatch_timeout")
			break
		end
		RunService.RenderStepped:Wait()
	end
	local results = job.results
	if not results or #results == 0 then
		if not job.silent then
			Notify.emit("hatch_failed", function()
				Toast.show(job.failed or Loc.t("err.hatch_failed"), Theme.COLORS.bad)
			end)
		end
		return
	end

	-- Staerkstes Pet bestimmt Farbe und Wucht des Ei-Bursts
	local best = results[1].baerchi
	for _, r in results do
		if BaerchiConfig.getRarityIndex(r.baerchi.rarity) > BaerchiConfig.getRarityIndex(best.rarity) then
			best = r.baerchi
		end
	end
	local handle = EggHatch.play({
		parent    = screenGui,
		eggType   = tostring(job.eggType),
		rarity    = best.rarity,
		configId  = best.configId,
		level     = best.level,
		mutation  = nil,
		isNew     = false,
		burstOnly = true,
	})
	-- burstOnly meldet "fertig", sobald das Ei aufgebrochen ist; die Szene bleibt stehen
	waitFinished(handle, 25)
	local scene = {
		root = handle.root,
		stage = handle.stage,
		backdrop = handle.root:FindFirstChild("Dim") :: Frame,
	}

	-- Titel
	local title = Theme.label("BatchTitle", scene.stage, Loc.t("ui.hatch.batch_title"))
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.fromScale(0.5, 0.05)
	title.Size = UDim2.fromOffset(420, 36)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.ZIndex = 60
	Theme.outlineText(title)

	-- Raster: 5 Spalten, bei 10 Pets 2 Reihen
	local grid = Instance.new("Frame")
	grid.Name = "BatchGrid"
	grid.AnchorPoint = Vector2.new(0.5, 0.5)
	grid.Position = UDim2.fromScale(0.5, 0.47)
	grid.Size = UDim2.fromScale(0.92, 0.62)
	grid.BackgroundTransparency = 1
	grid.ZIndex = 57
	grid.Parent = scene.stage
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(1100, 600)
	limit.Parent = grid
	local layout = Instance.new("UIGridLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.FillDirectionMaxCells = GRID_COLS
	layout.CellSize = UDim2.new(0.19, 0, 0.47, 0)
	layout.CellPadding = UDim2.new(0.0125, 0, 0.04, 0)
	layout.Parent = grid

	for index, result in results do
		local card = buildMiniCard(grid, result, index)
		local scale = Instance.new("UIScale")
		scale.Scale = 0
		scale.Parent = card
		task.delay((index - 1) * HatchFxConfig.GENERAL.batchStaggerSeconds, function()
			if scale.Parent then
				tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
			end
		end)
	end

	-- OK-Knopf (Honig-Template, sonst Standardknopf)
	local clicked = false
	local okButton = Instance.new("TextButton")
	okButton.Name = "BatchOk"
	okButton.Text = ""
	okButton.AutoButtonColor = false
	okButton.BackgroundTransparency = 1
	okButton.AnchorPoint = Vector2.new(0.5, 1)
	okButton.Position = UDim2.fromScale(0.5, 0.96)
	okButton.Size = UDim2.fromOffset(222, 51)   -- Bildverhaeltnis 855:196
	okButton.ZIndex = 60
	okButton.Parent = scene.stage
	local word = Icons.skinLabelButton(okButton, "honey/res_bar_gold", Loc.t("ui.hatch.batch_ok"))
	if word then
		word.AnchorPoint = Vector2.new(0.5, 0.5)
		word.Position = UDim2.fromScale(0.5, 0.5)
		word.Size = UDim2.fromScale(0.6, 0.52)
		word.ZIndex = 62
	else
		okButton.Text = Loc.t("ui.hatch.batch_ok")
		okButton.Font = Enum.Font.FredokaOne
		okButton.TextSize = 26
		okButton.TextColor3 = Color3.new(1, 1, 1)
		okButton.BackgroundTransparency = 0
		okButton.BackgroundColor3 = Theme.COLORS.good
		Theme.corner(okButton, 12)
	end
	okButton.Activated:Connect(function()
		clicked = true
	end)

	task.wait(0.6)
	-- Mit Zeitlimit und Szenen-Pruefung: ist die Szene weg oder klickt niemand,
	-- darf die Warteschlange nicht ewig stehen bleiben.
	local waitStart = os.clock()
	while not clicked do
		if not scene.root.Parent or os.clock() - waitStart > JOB_LIMIT_BATCH - 40 then
			break
		end
		RunService.RenderStepped:Wait()
	end

	tween(scene.backdrop, FADE_SECONDS, { BackgroundTransparency = 1 })
	grid:Destroy()
	okButton:Destroy()
	title:Destroy()
	task.wait(FADE_SECONDS)
	handle.destroy()
end

-- Raeumt uebrig gebliebene Szenen weg (Name: EggHatch, so heisst die Wurzel in VFX/EggHatch).
local function removeLeftovers()
	local gui = _screenGui
	if not gui then return end
	for _, child in gui:GetChildren() do
		if child.Name == "EggHatch" or child.Name == "HatchAnimation" then
			child:Destroy()
		end
	end
end

local function pump()
	if _running then return end
	_running = true

	task.spawn(function()
		while #_queue > 0 do
			local job = _queue[1]
			-- Das Ergebnis-Zeitlimit zaehlt ab Start dieser Animation, nicht ab dem Klick:
			-- Jobs, die hinter einer langen Animation warteten, sind sonst schon "abgelaufen".
			if not job.result and not job.results then job.started = os.clock() end

			local finishedJob = false
			local worker = task.spawn(function()
				local ok, err = pcall(if job.batch then playBatch else play, job)
				if not ok then
					warn("[HatchAnimation] Abspielen fehlgeschlagen:", err)
					removeLeftovers()
					showFallbackResult(job)
				end
				finishedJob = true
			end)

			-- Waechter: so lange wie eine Animation hoechstens dauern darf
			local limit = if job.batch then JOB_LIMIT_BATCH else JOB_LIMIT_SINGLE
			local startedAt = os.clock()
			while not finishedJob and os.clock() - startedAt < limit do
				task.wait(0.1)
			end
			if not finishedJob then
				warn("[HatchAnimation] Job haengt (", limit, "s) - Warteschlange wird freigegeben. batch =",
					job.batch == true, "Ergebnis da =", (job.result ~= nil or job.results ~= nil))
				pcall(task.cancel, worker)
				removeLeftovers()
				showFallbackResult(job)
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
local function oldestPending(batch: boolean?): Job?
	local wantBatch = batch == true
	for _, job in _queue do
		if (job.batch == true) == wantBatch and not job.result and not job.results and not job.failed then
			return job
		end
	end
	return nil
end

-- 15.10.: "10 oeffnen". Das Ergebnis liefert spaeter deliverBatch().
function HatchAnimation.requestBatch(eggType: Types.EggType)
	table.insert(_queue, {
		eggType = eggType,
		result  = nil,
		failed  = nil,
		silent  = false,
		started = os.clock(),
		batch   = true,
	})
	pump()
end

function HatchAnimation.deliverBatch(payload: any)
	if typeof(payload) ~= "table" or typeof(payload.results) ~= "table" then return end
	local job = oldestPending(true)
	if job then
		job.results = payload.results
		return
	end
	table.insert(_queue, {
		eggType = payload.eggType,
		failed  = nil,
		silent  = false,
		started = os.clock(),
		batch   = true,
		results = payload.results,
	})
	pump()
end

-- ActionFailed fuer RequestHatchEggs (oder RequestHatchEgg, wenn nur ein Sammel-Job offen ist)
function HatchAnimation.rejectBatch(reason: string)
	local job = oldestPending(true)
	if job then
		job.failed = reason
		job.silent = true
	end
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
	local job = oldestPending() or oldestPending(true)
	if job then
		job.failed = reason
		job.silent = true
	end
end

function HatchAnimation.init(screenGui: ScreenGui)
	_screenGui = screenGui
	EggHatch.preload()   -- R6: Bilder vorladen, damit sie beim ersten Ei schon da sind

	-- Beim Verlassen nichts haengen lassen
	Players.LocalPlayer.AncestryChanged:Connect(function()
		table.clear(_queue)
	end)

	print("[HatchAnimation] Initialisiert")
end

return HatchAnimation
