--!strict
-- Kit.luau
-- StarterPlayerScripts/UI/Kit.luau
--
-- Einzige Zustaendigkeit:
--   - Die Bausteine des neuen UI-Looks (08.10., Paket D): Fenster mit Schatten
--     und Kopf, Schliessen-X, Karte, Chip, Abzeichen, Balken, Knoepfe
--     (primaer/sekundaer/premium/waehlen), Schloss, Tower-Abzeichen,
--     Konfetti, Klang — und EINE Animations-Schleife fuer alles Bewegte.
--
-- Alle Farben, Radien, Striche, Abstaende, Schriftgroessen und Zeiten kommen
-- aus Theme.v2 (Tokens). Kein Baustein kennt ein bestimmtes Panel: das
-- Tower-Panel (UI/TowerPanel) ist der erste Nutzer, die anderen Panels
-- koennen spaeter einfach umsteigen. Die alte Theme-API bleibt unberuehrt.
--
-- Leistung: Bausteine sind ein paar Frames, keine Bilder (ausser optionalen
-- Icons mit Text-Rueckfall). Bewegung laeuft ueber Kit.animate in EINER
-- RenderStepped-Verbindung, die nur lebt, solange etwas animiert — kein
-- Thread und kein Dauer-Tween pro Element. Tweens (Oeffnen, Druecken) sind
-- kurz und raeumen sich selbst auf.

local SoundService      = game:GetService("SoundService")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundConfig = require(ReplicatedStorage.Config.SoundConfig)

local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)

local Kit = {}

local T = Theme.v2
Kit.T = T

--------------------------------------------------------------------------------
-- Klang
--------------------------------------------------------------------------------

-- Ein Sound-Objekt je Name, einmal angelegt und wiederverwendet.
local _sounds: { [string]: Sound } = {}

-- Spielt einen UI-Klang aus SoundConfig. Stumm-sicher: unbekannt, leer oder
-- nicht ladbar → es passiert nichts.
function Kit.playSound(name: string)
	local def = SoundConfig.get(name)
	if not def then return end
	local sound = _sounds[name]
	if not sound then
		local created = Instance.new("Sound")
		created.Name    = "UiSound_" .. name
		created.SoundId = def.id
		created.Parent  = SoundService
		_sounds[name] = created
		sound = created
	end
	sound.Volume = def.volume * SoundConfig.MASTER_VOLUME
	pcall(function()
		SoundService:PlayLocalSound(sound)
	end)
end

--------------------------------------------------------------------------------
-- Die eine Animations-Schleife
--------------------------------------------------------------------------------
-- Kit.animate(step) haengt `step(now)` an; gibt step false zurueck, faellt er
-- heraus. Laeuft nichts mehr, wird die Verbindung getrennt. Rueckgabe: eine
-- Funktion zum vorzeitigen Abmelden.

type Step = (number) -> boolean
local _steps: { Step } = {}
local _connection: RBXScriptConnection? = nil

local function runSteps()
	local now = os.clock()
	for i = #_steps, 1, -1 do
		local ok, keep = pcall(_steps[i], now)
		if not ok or keep == false then
			table.remove(_steps, i)
		end
	end
	if #_steps == 0 and _connection then
		_connection:Disconnect()
		_connection = nil
	end
end

function Kit.animate(step: Step): () -> ()
	table.insert(_steps, step)
	if not _connection then
		_connection = RunService.RenderStepped:Connect(runSteps)
	end
	return function()
		local index = table.find(_steps, step)
		if index then table.remove(_steps, index) end
	end
end

-- Anzahl laufender Animationen (Leck-Test: muss nach dem Schliessen 0 sein).
function Kit.activeAnimations(): number
	return #_steps
end

function Kit.tween(instance: Instance, seconds: number, props: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local tween = TweenService:Create(instance, TweenInfo.new(seconds, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	tween:Play()
	return tween
end

--------------------------------------------------------------------------------
-- Grundformen
--------------------------------------------------------------------------------

function Kit.corner(parent: Instance, radius: number): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

function Kit.stroke(parent: Instance, thickness: number, color: Color3?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or T.color.outline
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.LineJoinMode = Enum.LineJoinMode.Round
	stroke.Parent = parent
	return stroke
end

-- Verlauf von oben nach unten. Achtung: ein UIGradient MULTIPLIZIERT sich auf
-- die Hintergrundfarbe — deshalb setzen die Bausteine BackgroundColor3 weiss
-- und tragen die echte Farbe im Verlauf.
function Kit.gradient(parent: Instance, top: Color3, bottom: Color3): UIGradient
	local gradient = parent:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(top, bottom)
	gradient.Rotation = 90
	gradient.Parent = parent
	return gradient
end

function Kit.frame(name: string, parent: Instance, color: Color3?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BorderSizePixel = 0
	if color then
		frame.BackgroundColor3 = color
	else
		frame.BackgroundTransparency = 1
	end
	frame.Parent = parent
	return frame
end

-- Text, der nie abgeschnitten wird: TextScaled zwischen `size` (Ziel) und
-- T.text.small (Untergrenze). Lange FR/ES-Texte werden kleiner, nicht kuerzer.
export type TextOptions = {
	color   : Color3?,
	stroke  : number?,           -- Kontur (px), nil = keine
	strokeColor : Color3?,
	align   : Enum.TextXAlignment?,
	alignY  : Enum.TextYAlignment?,
	wrap    : boolean?,
	min     : number?,
}

function Kit.text(name: string, parent: Instance, text: string, size: number, options: TextOptions?): TextLabel
	local o: TextOptions = options or {}
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = T.text.font
	label.Text = text
	label.TextColor3 = o.color or T.color.ink
	label.TextScaled = true
	label.TextWrapped = o.wrap == true
	label.TextXAlignment = o.align or Enum.TextXAlignment.Left
	label.TextYAlignment = o.alignY or Enum.TextYAlignment.Center
	label.Parent = parent
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = size
	limit.MinTextSize = math.min(size, o.min or T.text.small)
	limit.Parent = label
	if o.stroke then
		local stroke = Instance.new("UIStroke")
		stroke.Color = o.strokeColor or T.color.outline
		stroke.Thickness = o.stroke
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		stroke.LineJoinMode = Enum.LineJoinMode.Round
		stroke.Parent = label
	end
	return label
end

-- Glanzlicht auf der oberen Haelfte (wie Theme.shine, mit v2-Masse)
function Kit.shine(parent: GuiObject, radius: number, height: number?): Frame
	local shine = Kit.frame("Shine", parent, T.color.white)
	shine.BackgroundTransparency = 0.72
	shine.AnchorPoint = Vector2.new(0.5, 0)
	shine.Position = UDim2.new(0.5, 0, 0, 4)
	shine.Size = UDim2.new(1, -16, height or 0.38, 0)
	shine.ZIndex = parent.ZIndex + 1
	Kit.corner(shine, math.max(4, radius - 6))
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new(0, 0.85)
	fade.Parent = shine
	return shine
end

-- Weiches Anwachsen beim Drueberfahren, Eindruecken beim Druecken (UIScale,
-- damit Layouts unberuehrt bleiben).
function Kit.pressable(button: GuiButton, onPress: (() -> ())?): UIScale
	local scale = Instance.new("UIScale")
	scale.Name = "PressScale"
	scale.Parent = button
	local function to(target: number)
		Kit.tween(scale, T.motion.press, { Scale = target })
	end
	button.MouseEnter:Connect(function() if button.Active then to(1.04) end end)
	button.MouseLeave:Connect(function() to(1) end)
	button.MouseButton1Down:Connect(function()
		if button.Active then
			to(0.94)
			if onPress then onPress() end
		end
	end)
	button.MouseButton1Up:Connect(function() if button.Active then to(1.04) end end)
	return scale
end

--------------------------------------------------------------------------------
-- Fenster
--------------------------------------------------------------------------------

export type Window = {
	root     : Frame,    -- unsichtbarer Rahmen, traegt FitScale (passt aufs Bild)
	holder   : Frame,    -- traegt PopScale (Aufspring-Animation)
	pop      : UIScale,
	body     : Frame,    -- Creme-Koerper mit Kontur
	content  : Frame,    -- Innenflaeche unter dem Kopf
	header   : Frame?,
	title    : TextLabel?,
	close    : TextButton?,
	mascot   : GuiObject?,
	setSize  : (Vector2) -> (),
}

-- Ein zentriertes Fenster mit Schlagschatten. `design` ist die gebaute Groesse
-- in Oberflaechen-Einheiten; passt sie nicht, wird erst die Hoehe bis
-- `minHeight` gekuerzt (die Liste darin scrollt), danach alles gleichmaessig
-- verkleinert. `reserve` haelt Raender frei (HUD, Pet-Leiste, Menueleiste).
export type WindowOptions = {
	design    : Vector2,
	minHeight : number,
	reserve   : { top: number, bottom: number, left: number, right: number },
}

function Kit.window(name: string, screenGui: ScreenGui, options: WindowOptions): Window
	local root = Kit.frame(name, screenGui)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Visible = false
	root.ZIndex = 20
	local fit = Instance.new("UIScale")
	fit.Name = "FitScale"
	fit.Parent = root

	local holder = Kit.frame("Holder", root)
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = 20
	local pop = Instance.new("UIScale")
	pop.Name = "PopScale"
	pop.Parent = holder

	-- Weicher Schlagschatten: dieselbe Form, dunkel, nach unten versetzt
	local shadow = Kit.frame("Shadow", holder, T.color.shadow)
	shadow.BackgroundTransparency = 0.55
	shadow.Position = UDim2.fromOffset(0, 10)
	shadow.Size = UDim2.fromScale(1, 1)
	shadow.ZIndex = 20
	Kit.corner(shadow, T.radius.panel)

	local body = Kit.frame("Body", holder, T.color.white)
	body.Size = UDim2.fromScale(1, 1)
	body.ZIndex = 22
	Kit.corner(body, T.radius.panel)
	Kit.stroke(body, T.stroke.panel)
	Kit.gradient(body, T.color.surface, T.color.surfaceDeep)

	local content = Kit.frame("Content", body)
	content.Size = UDim2.fromScale(1, 1)
	content.ZIndex = 23

	local window: Window = {
		root = root, holder = holder, pop = pop, body = body, content = content,
		header = nil, title = nil, close = nil, mascot = nil,
		setSize = function(_: Vector2) end,
	}

	local function refit()
		local global = screenGui:FindFirstChild("GlobalScale")
		local g = if global and global:IsA("UIScale") then math.max(global.Scale, 0.01) else 1
		local screen = screenGui.AbsoluteSize / g
		if screen.X <= 0 or screen.Y <= 0 then return end
		local r = options.reserve
		local roomX = screen.X - r.left - r.right
		local roomY = screen.Y - r.top - r.bottom
		local width = options.design.X
		local height = math.clamp(roomY, options.minHeight, options.design.Y)
		local scale = math.min(1, roomX / width, roomY / height)
		root.Size = UDim2.fromOffset(width, height)
		fit.Scale = scale
		-- Mitte des freien Bereichs
		root.Position = UDim2.fromOffset(r.left + roomX * 0.5, r.top + roomY * 0.5)
		window.setSize(Vector2.new(width, height))
	end
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	screenGui.ChildAdded:Connect(function(child)
		if child.Name == "GlobalScale" and child:IsA("UIScale") then
			child:GetPropertyChangedSignal("Scale"):Connect(refit)
			refit()
		end
	end)
	local global = screenGui:FindFirstChild("GlobalScale")
	if global and global:IsA("UIScale") then
		global:GetPropertyChangedSignal("Scale"):Connect(refit)
	end
	task.defer(refit)
	;(window :: any).refit = refit
	return window
end

-- Kopf: Honig-Band oben im Koerper. Es hat DENSELBEN Eckradius und liegt
-- buendig in der oberen Kante — dadurch folgt es der Rundung exakt und kein
-- Pixel steht ueber die Kontur. Die unteren Ecken fuellt ein Streifen in
-- Bandfarbe auf (gerade Unterkante). Der Titel federt beim Oeffnen ein.
function Kit.header(window: Window, title: string, height: number): TextLabel
	local band = Kit.frame("Header", window.body, T.color.white)
	band.Size = UDim2.new(1, 0, 0, height)
	band.ZIndex = 24
	Kit.corner(band, T.radius.panel)
	Kit.gradient(band, T.color.honeyTop, T.color.honeyBottom)

	local filler = Kit.frame("HeaderFill", band, T.color.white)
	filler.AnchorPoint = Vector2.new(0, 1)
	filler.Position = UDim2.fromScale(0, 1)
	filler.Size = UDim2.new(1, 0, 0, T.radius.panel)
	filler.ZIndex = 24
	local fillGradient = Instance.new("UIGradient")
	fillGradient.Rotation = 90
	-- Fortsetzung des Band-Verlaufs im unteren Teil (ohne sichtbare Naht)
	local split = 1 - T.radius.panel / height
	fillGradient.Color = ColorSequence.new(
		T.color.honeyTop:Lerp(T.color.honeyBottom, split),
		T.color.honeyBottom
	)
	fillGradient.Parent = filler

	-- Trennlinie zum Inhalt (Teil der dicken Kontur-Sprache)
	local line = Kit.frame("HeaderLine", band, T.color.outline)
	line.AnchorPoint = Vector2.new(0, 1)
	line.Position = UDim2.fromScale(0, 1)
	line.Size = UDim2.new(1, 0, 0, T.stroke.card)
	line.ZIndex = 26

	local shine = Kit.frame("HeaderShine", band, T.color.white)
	shine.BackgroundTransparency = 0.7
	shine.Position = UDim2.fromOffset(14, 6)
	shine.Size = UDim2.new(1, -28, 0, math.floor(height * 0.28))
	shine.ZIndex = 25
	Kit.corner(shine, 12)
	local fade = Instance.new("UIGradient")
	fade.Rotation = 90
	fade.Transparency = NumberSequence.new(0, 0.9)
	fade.Parent = shine

	local label = Kit.text("Title", band, title, T.text.title, {
		color = T.color.white, stroke = T.stroke.text + 1, align = Enum.TextXAlignment.Center,
	})
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.new(1, -220, 0, T.text.title + 6)
	label.ZIndex = 27
	local titleScale = Instance.new("UIScale")
	titleScale.Name = "TitleScale"
	titleScale.Parent = label

	window.header = band
	window.title = label
	return label
end

-- Maskottchen: ein Baerchi-Kopf lugt ueber die obere Kante (hinter dem
-- Koerper, nur die obere Haelfte ist zu sehen).
function Kit.mascot(window: Window, xOffset: number): GuiObject
	local holder = Kit.frame("Mascot", window.holder)
	holder.AnchorPoint = Vector2.new(0.5, 1)
	holder.Position = UDim2.new(0, xOffset, 0, 34)
	holder.Size = UDim2.fromOffset(84, 84)
	holder.ZIndex = 21   -- unter dem Koerper (22): die untere Haelfte steckt dahinter
	local icon = Icons.make(holder, "bear", "🐻")
	icon.Size = UDim2.fromScale(1, 1)
	icon.ZIndex = 21
	window.mascot = holder
	return holder
end

-- Schliessen-X: eigenes Geschwister des Koerpers, an dessen Ecke oben rechts
-- verankert (Mittelpunkt 10 px innerhalb der Ecke), steht leicht ueber, wird
-- nicht abgeschnitten. 52 px sichtbar, 64 px Trefferflaeche (Touch >= 48).
function Kit.closeButton(window: Window, onClose: () -> ()): TextButton
	local size = 52
	local button = Instance.new("TextButton")
	button.Name = "Close"
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.new(1, -10, 0, 10)
	button.Size = UDim2.fromOffset(size, size)
	button.BackgroundColor3 = T.color.white
	button.AutoButtonColor = false
	button.Text = ""
	button.ZIndex = 40
	button.Parent = window.holder
	Kit.corner(button, size)
	Kit.stroke(button, T.stroke.button)
	Kit.gradient(button, Color3.fromRGB(255, 120, 120), Color3.fromRGB(226, 60, 70))

	local cross = Kit.text("X", button, "✕", 30, { color = T.color.white, stroke = 2, align = Enum.TextXAlignment.Center })
	cross.Size = UDim2.fromScale(1, 1)
	cross.ZIndex = 41

	local hit = Instance.new("TextButton")
	hit.Name = "CloseHit"
	hit.AnchorPoint = Vector2.new(0.5, 0.5)
	hit.Position = UDim2.fromScale(0.5, 0.5)
	hit.Size = UDim2.fromOffset(64, 64)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.ZIndex = 42
	hit.Parent = button

	Kit.pressable(button)
	local function fire()
		Kit.playSound("click")
		onClose()
	end
	button.Activated:Connect(fire)
	hit.Activated:Connect(fire)
	window.close = button
	return button
end

-- Aufspringen beim Oeffnen: Fenster von 0,86 auf 1 (Back), Titel etwas spaeter.
function Kit.popIn(window: Window)
	window.pop.Scale = 0.86
	Kit.tween(window.pop, T.motion.open, { Scale = 1 }, Enum.EasingStyle.Back)
	local title = window.title
	local titleScale = if title then title:FindFirstChild("TitleScale") else nil
	if titleScale and titleScale:IsA("UIScale") then
		titleScale.Scale = 0.5
		task.delay(0.08, function()
			Kit.tween(titleScale, T.motion.open + 0.1, { Scale = 1 }, Enum.EasingStyle.Back)
		end)
	end
end

-- Scrollbare Liste (Canvas waechst mit dem Inhalt), Balken in Baerchi-Braun.
function Kit.scroller(name: string, parent: Instance): ScrollingFrame
	local list = Instance.new("ScrollingFrame")
	list.Name = name
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 8
	list.ScrollBarImageColor3 = T.color.bear
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.ZIndex = 30
	list.Parent = parent
	return list
end

--------------------------------------------------------------------------------
-- Karte, Chip, Abzeichen, Balken
--------------------------------------------------------------------------------

-- Karte mit Kontur und kleiner 3D-Kante (dunklerer Streifen unten).
-- Rueckgabe: der Halter fuer Layouts (`holder`) und die Kartenflaeche (`face`),
-- die beim Einlaufen verschoben werden darf.
export type Card = { holder: Frame, face: Frame, stroke: UIStroke, gradient: UIGradient }

function Kit.card(name: string, parent: Instance, height: number): Card
	local holder = Kit.frame(name, parent)
	holder.Size = UDim2.new(1, 0, 0, height)

	local face = Kit.frame("Face", holder, T.color.white)
	face.Size = UDim2.new(1, -8, 1, -6)
	face.Position = UDim2.fromOffset(4, 0)
	face.ZIndex = 30
	Kit.corner(face, T.radius.card)
	local stroke = Kit.stroke(face, T.stroke.card)
	local gradient = Kit.gradient(face, T.color.card, T.color.surface)

	-- 3D-Kante: gleiche Form, dunkler, 6 px tiefer, hinter der Flaeche
	local edge = Kit.frame("Edge", face, T.color.quietEdge)
	edge.Position = UDim2.fromOffset(0, 6)
	edge.Size = UDim2.fromScale(1, 1)
	edge.ZIndex = 29
	Kit.corner(edge, T.radius.card)
	Kit.stroke(edge, T.stroke.card)

	return { holder = holder, face = face, stroke = stroke, gradient = gradient }
end

-- Pille mit Text (Status, Fortschritt). Breite waechst mit dem Text.
function Kit.chip(name: string, parent: Instance, text: string, color: Color3?, textColor: Color3?): Frame
	local chip = Kit.frame(name, parent, color or T.color.sunk)
	chip.AutomaticSize = Enum.AutomaticSize.X
	chip.Size = UDim2.fromOffset(0, 30)
	chip.ZIndex = 32
	Kit.corner(chip, 15)
	Kit.stroke(chip, T.stroke.textSmall)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = chip
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromScale(0, 1)
	label.Font = T.text.font
	label.TextSize = T.text.small + 1
	label.TextColor3 = textColor or T.color.ink
	label.Text = text
	label.ZIndex = 33
	label.Parent = chip
	return chip
end

function Kit.setChip(chip: Frame, text: string)
	local label = chip:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then label.Text = text end
end

-- Kleiner schraeger Aufkleber ("NEU", "AKTIV", "GRATIS").
function Kit.badge(name: string, parent: Instance, text: string, color: Color3, rotation: number?): Frame
	local badge = Kit.frame(name, parent, T.color.white)
	badge.AnchorPoint = Vector2.new(0.5, 0.5)
	badge.AutomaticSize = Enum.AutomaticSize.X
	badge.Size = UDim2.fromOffset(0, 28)
	badge.Rotation = rotation or -8
	badge.ZIndex = 36
	Kit.corner(badge, 10)
	Kit.stroke(badge, T.stroke.textSmall)
	Kit.gradient(badge, Theme.shade(color, 0.25), color)
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0, 10)
	pad.PaddingRight = UDim.new(0, 10)
	pad.Parent = badge
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromScale(0, 1)
	label.Font = T.text.font
	label.TextSize = T.text.small + 2
	label.TextColor3 = T.color.white
	label.Text = text
	label.ZIndex = 37
	label.Parent = badge
	local stroke = Instance.new("UIStroke")
	stroke.Color = T.color.outline
	stroke.Thickness = 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
	return badge
end

export type Progress = { track: Frame, fill: Frame, label: TextLabel, set: (number, string) -> () }

-- Fortschrittsbalken mit Text in der Mitte.
function Kit.progress(name: string, parent: Instance, height: number, color: Color3?): Progress
	local track = Kit.frame(name, parent, T.color.sunk)
	track.Size = UDim2.new(1, 0, 0, height)
	track.ZIndex = 32
	track.ClipsDescendants = true
	Kit.corner(track, math.floor(height / 2))
	Kit.stroke(track, T.stroke.textSmall)

	local fill = Kit.frame("Fill", track, T.color.white)
	fill.Size = UDim2.fromScale(0, 1)
	fill.ZIndex = 33
	Kit.corner(fill, math.floor(height / 2))
	local base = color or T.color.progress
	Kit.gradient(fill, Theme.shade(base, 0.3), base)

	local label = Kit.text("Text", track, "", height - 4, { color = T.color.white, stroke = 2, align = Enum.TextXAlignment.Center, min = 12 })
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 34

	local function set(ratio: number, text: string)
		local r = math.clamp(ratio, 0, 1)
		fill.Visible = r > 0
		fill.Size = UDim2.new(math.max(r, 0.06), 0, 1, 0)
		label.Text = text
	end
	return { track = track, fill = fill, label = label, set = set }
end

--------------------------------------------------------------------------------
-- Knoepfe
--------------------------------------------------------------------------------
-- Ein Knopf = unsichtbarer TextButton (Trefferflaeche) mit "Edge" (3D-Kante,
-- dunkel, volle Groesse) und "Face" (Flaeche mit Verlauf und Glanz, 6 px
-- hoeher). Beim Druecken sinkt die Flaeche auf die Kante.
--   primary   gross, kraeftig gruen, Glanz, darf pulsieren (Kit.pulse)
--   secondary Creme mit Kontur, kein Glanz, gedaempfte Kante — lesbar, ruhig
--   premium   gold, ruhig, Krone
--   choose    himmelblau (Waehlen auf einer Karte)

export type ButtonKind = "primary" | "secondary" | "premium" | "choose"

export type Button = {
	button : TextButton,
	face   : Frame,
	label  : TextLabel,
	sub    : TextLabel,
	kind   : ButtonKind,
	setEnabled : (boolean) -> (),
	setKind    : (ButtonKind) -> (),
}

local KIND_COLORS: { [string]: { top: Color3, bottom: Color3, edge: Color3, text: Color3, stroke: number? } } = {
	primary   = { top = T.color.goTop,   bottom = T.color.go,       edge = T.color.goEdge,     text = T.color.white, stroke = T.stroke.text },
	secondary = { top = T.color.quiet,   bottom = T.color.surface,  edge = T.color.quietEdge,  text = T.color.ink,   stroke = nil },
	premium   = { top = T.color.goldTop, bottom = T.color.gold,     edge = T.color.goldEdge,   text = T.color.ink,   stroke = nil },
	choose    = { top = Theme.shade(T.color.choose, 0.3), bottom = T.color.choose, edge = T.color.chooseEdge, text = T.color.white, stroke = T.stroke.text },
}

local EDGE = 6

function Kit.button(name: string, parent: Instance, kind: ButtonKind, text: string, textSize: number?): Button
	local button = Instance.new("TextButton")
	button.Name = name
	button.BackgroundTransparency = 1
	button.AutoButtonColor = false
	button.Text = ""
	button.ZIndex = 34
	button.Parent = parent

	local edge = Kit.frame("Edge", button, T.color.white)
	edge.Position = UDim2.fromOffset(0, EDGE)
	edge.Size = UDim2.new(1, 0, 1, -EDGE)
	edge.ZIndex = 34
	Kit.corner(edge, T.radius.button)
	Kit.stroke(edge, T.stroke.button)

	local face = Kit.frame("Face", button, T.color.white)
	face.Size = UDim2.new(1, 0, 1, -EDGE)
	face.ZIndex = 35
	Kit.corner(face, T.radius.button)
	Kit.stroke(face, T.stroke.button)
	local shine = Kit.shine(face, T.radius.button)
	shine.ZIndex = 36

	local label = Kit.text("Label", face, text, textSize or T.text.button, { align = Enum.TextXAlignment.Center })
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.new(1, -16, 0.62, 0)
	label.ZIndex = 37

	local sub = Kit.text("Sub", face, "", T.text.small, { align = Enum.TextXAlignment.Center })
	sub.AnchorPoint = Vector2.new(0.5, 1)
	sub.Position = UDim2.new(0.5, 0, 1, -4)
	sub.Size = UDim2.new(1, -16, 0, T.text.small + 2)
	sub.ZIndex = 37
	sub.Visible = false

	local view: Button = {
		button = button, face = face, label = label, sub = sub, kind = kind,
		setEnabled = function(_: boolean) end, setKind = function(_: ButtonKind) end,
	}

	local function paint()
		local c = KIND_COLORS[view.kind]
		local enabled = button.Active
		local top = if enabled then c.top else T.color.sunk
		local bottom = if enabled then c.bottom else T.color.cardLocked
		Kit.gradient(face, top, bottom)
		edge.BackgroundColor3 = if enabled then c.edge else T.color.quietEdge
		shine.Visible = enabled and view.kind ~= "secondary"
		local textColor = if enabled then c.text else T.color.inkSoft
		label.TextColor3 = textColor
		sub.TextColor3 = textColor
		for _, l in { label, sub } do
			local stroke = l:FindFirstChildOfClass("UIStroke")
			if c.stroke and enabled then
				if not stroke then
					stroke = Instance.new("UIStroke")
					stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
					stroke.LineJoinMode = Enum.LineJoinMode.Round
					stroke.Parent = l
				end
				local s = stroke :: UIStroke
				s.Color = T.color.outline
				s.Thickness = if l == label then c.stroke else 2
				s.Enabled = true
			elseif stroke then
				stroke.Enabled = false
			end
		end
	end

	view.setEnabled = function(enabled: boolean)
		button.Active = enabled
		button.Selectable = enabled
		paint()
	end
	view.setKind = function(newKind: ButtonKind)
		view.kind = newKind
		paint()
	end

	-- Eindruecken: Flaeche sinkt auf die Kante
	button.MouseButton1Down:Connect(function()
		if button.Active then face.Position = UDim2.fromOffset(0, EDGE - 2) end
	end)
	local function release() face.Position = UDim2.fromOffset(0, 0) end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	Kit.pressable(button)

	paint()
	return view
end

-- Sanfter Puls (nur fuer EIN Element je Fenster: den Hauptknopf). Laeuft in
-- der gemeinsamen Schleife; die Rueckgabe stoppt ihn.
function Kit.pulse(target: GuiObject, amount: number?): () -> ()
	local scale = target:FindFirstChild("PulseScale") :: UIScale?
	if not scale then
		local created = Instance.new("UIScale")
		created.Name = "PulseScale"
		-- Ein GuiObject darf nur EIN UIScale haben; der Knopf hat schon
		-- PressScale. Deshalb pulsiert der Inhalt (Face) statt des Knopfs.
		created.Parent = target
		scale = created
	end
	local s = scale :: UIScale
	local a = amount or 0.045
	local t0 = os.clock()
	local stop = Kit.animate(function(now)
		if not target.Parent then return false end
		local phase = ((now - t0) % T.motion.pulse) / T.motion.pulse
		s.Scale = 1 + a * math.sin(phase * math.pi * 2) ^ 2
		return true
	end)
	return function()
		stop()
		s.Scale = 1
	end
end

--------------------------------------------------------------------------------
-- Schloss, Tower-Abzeichen, Konfetti
--------------------------------------------------------------------------------

-- Gedaempfte Flaeche mit Schloss — "gesperrt, aber nicht tot": der Inhalt
-- darunter bleibt lesbar (nur leicht abgedeckt).
function Kit.lockOverlay(parent: GuiObject): Frame
	local overlay = Kit.frame("Lock", parent, T.color.cardLocked)
	overlay.BackgroundTransparency = 0.45
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.ZIndex = parent.ZIndex + 5
	Kit.corner(overlay, T.radius.card)
	return overlay
end

function Kit.lockIcon(parent: Instance, size: number): GuiObject
	local icon = Icons.make(parent, "lock", "🔒")
	icon.Size = UDim2.fromOffset(size, size)
	return icon
end

-- Tower-Abzeichen: Quadrat in der Look-Farbe mit Kante, grosser Ziffer und
-- einem Material-Zeichen aus Frames (Holz: Maserung, Stein: Fugen, Gold:
-- Glanzstreif, Kristall: Raute, Endless: Kreis). Keine Bilder noetig.
function Kit.towerBadge(name: string, parent: Instance, look: string, color: Color3, numeral: string, size: number): Frame
	local badge = Kit.frame(name, parent, T.color.white)
	badge.Size = UDim2.fromOffset(size, size)
	badge.ZIndex = 32
	Kit.corner(badge, T.radius.badge)
	Kit.stroke(badge, T.stroke.card)
	Kit.gradient(badge, Theme.shade(color, 0.35), Theme.shade(color, -0.12))

	local deco = Theme.shade(color, -0.3)
	local function mark(n: string, pos: UDim2, sz: UDim2, rot: number?, radius: number?)
		local f = Kit.frame(n, badge, deco)
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = pos
		f.Size = sz
		f.Rotation = rot or 0
		f.BackgroundTransparency = 0.45
		f.ZIndex = 33
		if radius then Kit.corner(f, radius) end
	end
	if look == "Wood" then
		mark("Grain1", UDim2.fromScale(0.5, 0.3), UDim2.new(0.8, 0, 0, 3), 0, 2)
		mark("Grain2", UDim2.fromScale(0.5, 0.72), UDim2.new(0.8, 0, 0, 3), 0, 2)
	elseif look == "Stone" then
		mark("Joint1", UDim2.fromScale(0.5, 0.36), UDim2.new(0.9, 0, 0, 3))
		mark("Joint2", UDim2.fromScale(0.5, 0.66), UDim2.new(0.9, 0, 0, 3))
		mark("Joint3", UDim2.fromScale(0.3, 0.51), UDim2.new(0, 3, 0.3, 0))
	elseif look == "Gold" then
		local f = Kit.frame("Gleam", badge, T.color.white)
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromScale(0.32, 0.4)
		f.Size = UDim2.new(0.14, 0, 0.9, 0)
		f.Rotation = 30
		f.BackgroundTransparency = 0.45
		f.ZIndex = 33
	elseif look == "Crystal" then
		mark("Gem", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.62, 0.62), 45, 6)
	elseif look == "Endless" then
		mark("Ring", UDim2.fromScale(0.5, 0.5), UDim2.fromScale(0.8, 0.8), 0, 999)
	end

	local label = Kit.text("Numeral", badge, numeral, math.floor(size * 0.52), {
		color = T.color.white, stroke = T.stroke.text, align = Enum.TextXAlignment.Center,
	})
	label.Size = UDim2.fromScale(1, 1)
	label.ZIndex = 34
	local s = Kit.shine(badge, T.radius.badge, 0.32)
	s.ZIndex = 35
	return badge
end

-- Konfetti: wenige Schnipsel (Frames) fallen aus `origin` (Position in
-- `parent`), drehen sich und verblassen. Alles in der gemeinsamen Schleife,
-- nach T.motion.confetti wieder weg.
local CONFETTI_COLORS = { T.color.honey, T.color.gummy, T.color.sky, T.color.go, T.color.gold }

function Kit.confetti(parent: GuiObject, origin: Vector2, count: number?)
	local pieces: { { frame: Frame, vx: number, vy: number, spin: number } } = {}
	for i = 1, count or 22 do
		local f = Kit.frame("Confetti", parent, CONFETTI_COLORS[(i - 1) % #CONFETTI_COLORS + 1])
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = UDim2.fromOffset(math.random(7, 12), math.random(10, 16))
		f.Position = UDim2.fromOffset(origin.X, origin.Y)
		f.ZIndex = 60
		f.Rotation = math.random(0, 360)
		Kit.corner(f, 3)
		table.insert(pieces, {
			frame = f,
			vx = (math.random() - 0.5) * 520,
			vy = -(220 + math.random() * 260),
			spin = (math.random() - 0.5) * 900,
		})
	end
	local t0 = os.clock()
	local last = t0
	Kit.animate(function(now)
		local dt = math.min(now - last, 0.05)
		last = now
		local t = (now - t0) / T.motion.confetti
		for _, p in pieces do
			p.vy += 900 * dt
			local pos = p.frame.Position
			p.frame.Position = UDim2.fromOffset(pos.X.Offset + p.vx * dt, pos.Y.Offset + p.vy * dt)
			p.frame.Rotation += p.spin * dt
			p.frame.BackgroundTransparency = math.max(0, (t - 0.6) / 0.4)
		end
		if t >= 1 then
			for _, p in pieces do p.frame:Destroy() end
			return false
		end
		return true
	end)
end

return Kit
