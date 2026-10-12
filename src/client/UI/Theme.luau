--!strict
-- Theme.luau
-- StarterPlayerScripts/UI/Theme.luau
--
-- Einzige Zustaendigkeit:
--   - Farben, Schrift und Baustein-Helfer fuer das gesamte UI
--
-- Kein UI-Modul definiert eigene Farben oder baut Frames von Hand —
-- alles laeuft hier durch. Wenn der Look sich aendert, aendert er sich hier.
--
-- Die Rarity-Farben kommen bewusst NICHT von hier, sondern aus
-- BaerchiConfig.RARITY_COLORS: der Server faerbt die Figuren auf der Insel
-- mit denselben Werten, und die duerfen nicht auseinanderlaufen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local BaerchiConfig = require(ReplicatedStorage.Config.BaerchiConfig)
local Types         = require(ReplicatedStorage.Network.Types)
local Loc           = require(ReplicatedStorage.Localization.Loc)
local RarityBandConfig = require(ReplicatedStorage.Config.RarityBandConfig)  -- HBB Paket 4
local Icons            = require(script.Parent.Icons)

local Theme = {}

--------------------------------------------------------------------------------
-- Farben
--------------------------------------------------------------------------------

Theme.COLORS = {
	-- Flaechen
	panel      = Color3.fromRGB( 52,  46,  78),
	panelDeep  = Color3.fromRGB( 38,  34,  58),
	panelLight = Color3.fromRGB( 72,  64, 104),

	-- Rahmen (der dicke dunkle Cartoon-Rand)
	outline    = Color3.fromRGB( 24,  20,  38),

	-- Schrift
	text       = Color3.fromRGB(255, 255, 255),
	textDim    = Color3.fromRGB(188, 182, 210),

	-- Waehrungen
	gummy      = Color3.fromRGB(255, 105, 150),
	goldGummy  = Color3.fromRGB(255, 196,  60),

	-- Zustaende
	good       = Color3.fromRGB( 76, 217, 100),
	bad        = Color3.fromRGB(255,  82,  82),
	accent     = Color3.fromRGB(120, 190, 255),

	-- Die drei Gebaeude-Rollen (siehe Theme.buildingColor). Benannt nach der
	-- ROLLE, nicht nach dem Gebaeude: die Farbe soll sagen WOFUER sein Honig
	-- gut ist.
	volume     = Color3.fromRGB(255, 186,  62),   -- Vorrat
	healing    = Color3.fromRGB( 92, 222, 160),   -- Heilung
	growth     = Color3.fromRGB(178, 148, 255),   -- Wachstum

	-- Ausgegrauter Button (siehe Theme.setEnabled)
	disabled   = Color3.fromRGB( 84,  80, 104),

	-- Bilderbuch-Palette fuer Ei-Menue und Ei-Baum (passend zu den
	-- Blender-Texturen in assets/ui, tools/art/render_ui.py)
	honey      = Color3.fromRGB(255, 186,  52),
	honeyDeep  = Color3.fromRGB(214, 128,  24),
	cream      = Color3.fromRGB(255, 244, 220),
	forest     = Color3.fromRGB( 36,  74,  50),
	walnut     = Color3.fromRGB( 92,  58,  36),
	walnutDeep = Color3.fromRGB( 52,  32,  22),
}

Theme.FONT      = Enum.Font.FredokaOne
Theme.FONT_BODY = Enum.Font.GothamMedium

-- Dicke des Cartoon-Rands
Theme.OUTLINE_THICKNESS = 3
Theme.CORNER_RADIUS     = 14

function Theme.rarityColor(rarity: Types.Rarity): Color3
	return BaerchiConfig.getRarityColor(rarity)
end

-- Akzentfarbe eines Honig-Gebaeudes.
--
-- Die Zuordnung steht an EINER Stelle, genau wie bei rarityColor: das
-- Gebaeude-Panel faerbt damit seine Karten, die Baerchi-Detailkarte ihre
-- Fuetter-Knoepfe. Zwei getrennte Listen waeren die naechste Stelle, an der
-- Farbe und Gebaeude auseinanderlaufen.
--
-- Was die Farben BEDEUTEN, steht bei den Rollen in Config/BuildingBehavior:
-- Bienenstock = Vorrat, Honigtopf = Heilung, Honig-Presse = Wachstum.
local BUILDING_COLORS: { [string]: Color3 } = {
	Beehive    = Theme.COLORS.volume,
	HoneyRefiner = Theme.COLORS.growth,
	HoneyPond  = Theme.COLORS.goldGummy,   -- Honig-Teich / -Brunnen (HONEY_POND_V2)
}

-- HBB Paket 4: Farben der fuenf Rarity-Baender (Zuordnung in
-- Config/RarityBandConfig). Kraeftig und weit auseinander, damit ein Kind
-- sie ohne Text unterscheidet.
Theme.BAND_COLORS = {
	Color3.fromRGB(176, 190, 204),   -- 1 grau
	Color3.fromRGB( 46, 155, 255),   -- 2 blau
	Color3.fromRGB(255, 176,  32),   -- 3 gold
	Color3.fromRGB(168,  85, 247),   -- 4 lila
	Color3.fromRGB(255,  70, 110),   -- 5 rot-pink
}

function Theme.bandColor(rarity: string): Color3
	return Theme.BAND_COLORS[RarityBandConfig.bandOf(rarity)] or Theme.BAND_COLORS[1]
end

function Theme.buildingColor(buildingId: string): Color3
	return BUILDING_COLORS[buildingId] or Theme.COLORS.accent
end

--------------------------------------------------------------------------------
-- Bausteine
--------------------------------------------------------------------------------

function Theme.corner(parent: Instance, radius: number?): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or Theme.CORNER_RADIUS)
	corner.Parent = parent
	return corner
end

function Theme.stroke(parent: Instance, color: Color3?, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color        = color or Theme.COLORS.outline
	stroke.Thickness    = thickness or Theme.OUTLINE_THICKNESS
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent       = parent
	return stroke
end

-- Hellere bzw. dunklere Variante einer Farbe. `amount` > 0 hellt auf, < 0
-- dunkelt ab, jeweils 0..1. Damit muss keine Farbvariante von Hand gepflegt
-- werden — jede Flaeche kann sich ihre Abstufung aus der Grundfarbe holen.
function Theme.shade(color: Color3, amount: number): Color3
	if amount >= 0 then
		return color:Lerp(Color3.new(1, 1, 1), math.clamp(amount, 0, 1))
	end
	return color:Lerp(Color3.new(0, 0, 0), math.clamp(-amount, 0, 1))
end

-- Farbverlauf ueber eine Flaeche.
--
-- Der kuerzeste Weg von "Platzhalter" zu "Spiel": eine flache Farbe sieht aus
-- wie ein unfertiges Rechteck, dieselbe Farbe mit einem Verlauf sieht aus wie
-- ein Knopf. Wird fuer die Kopfbalken und die grossen Knoepfe der
-- Gebaeude-Menues benutzt.
--
-- `rotation` in Grad: 90 = von oben nach unten (Standard).
function Theme.gradient(parent: Instance, top: Color3, bottom: Color3, rotation: number?): UIGradient
	-- Ein vorhandener Verlauf wird ueberschrieben statt gestapelt: zwei
	-- UIGradients multiplizieren sich und machen den Knopf dunkel. So kann
	-- Theme.button schon einen Grundverlauf setzen, und bigButton oder eine
	-- Kachel faerbt ihn nur um.
	local gradient = parent:FindFirstChildOfClass("UIGradient") or Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, top),
		ColorSequenceKeypoint.new(1, bottom),
	})
	gradient.Rotation = rotation or 90
	gradient.Parent   = parent
	return gradient
end

function Theme.padding(parent: Instance, px: number): UIPadding
	local padding = Instance.new("UIPadding")
	padding.PaddingTop    = UDim.new(0, px)
	padding.PaddingBottom = UDim.new(0, px)
	padding.PaddingLeft   = UDim.new(0, px)
	padding.PaddingRight  = UDim.new(0, px)
	padding.Parent        = parent
	return padding
end

function Theme.listLayout(parent: Instance, padding: number, horizontal: boolean?): UIListLayout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection       = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
	layout.SortOrder           = Enum.SortOrder.LayoutOrder
	layout.Padding             = UDim.new(0, padding)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment   = Enum.VerticalAlignment.Top
	layout.Parent              = parent
	return layout
end

-- Durchsichtiger Container ohne Rand
function Theme.container(name: string, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Name                   = name
	frame.BackgroundTransparency = 1
	frame.BorderSizePixel        = 0
	frame.Parent                 = parent
	return frame
end

-- Gefuellte Flaeche mit Rundung und Cartoon-Rand
function Theme.panel(name: string, parent: Instance, color: Color3?): Frame
	local frame = Instance.new("Frame")
	frame.Name            = name
	frame.BackgroundColor3 = color or Theme.COLORS.panel
	frame.BorderSizePixel = 0
	frame.Parent          = parent

	Theme.corner(frame)
	Theme.stroke(frame)
	-- Leichter Verlauf: eine flache Flaeche wirkt wie ein Platzhalter, mit
	-- hellerer Oberkante wie ein Spielelement.
	-- (Ein UIGradient MULTIPLIZIERT sich auf die Hintergrundfarbe: weiss =
	-- unveraendert, grau = dunkler. Deshalb neutrale Farben, nicht shade().)
	Theme.gradient(frame, Color3.fromRGB(255, 255, 255), Color3.fromRGB(196, 196, 208))
	return frame
end

-- Heller Glanzstreifen auf der oberen Haelfte eines Knopfes — der kleine
-- Kniff, der aus einem Rechteck einen "Cartoon-Knopf" macht. Faengt keine
-- Klicks ab (Frame, nicht aktiv).
function Theme.shine(parent: GuiObject, radius: number?): Frame
	local shine = Instance.new("Frame")
	shine.Name                   = "Shine"
	shine.AnchorPoint            = Vector2.new(0.5, 0)
	shine.Position               = UDim2.new(0.5, 0, 0, 3)
	shine.Size                   = UDim2.new(1, -10, 0.42, 0)
	shine.BackgroundColor3       = Color3.new(1, 1, 1)
	shine.BackgroundTransparency = 0.82
	shine.BorderSizePixel        = 0
	shine.Active                 = false
	shine.Parent                 = parent
	Theme.corner(shine, radius or 8)
	return shine
end

-- Weiches Anwachsen beim Drueberfahren, Eindruecken beim Druecken. Ein
-- UIScale statt Size, damit Layouts und Tweens an der Groesse unberuehrt bleiben.
local PRESS_TWEEN = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function Theme.pressable(button: GuiButton, hover: number?)
	local grow = hover or 1.06
	local scale = Instance.new("UIScale")
	scale.Name   = "PressScale"
	scale.Parent = button

	local function to(target: number)
		TweenService:Create(scale, PRESS_TWEEN, { Scale = target }):Play()
	end

	button.MouseEnter:Connect(function()
		if button.Active then to(grow) end
	end)
	button.MouseLeave:Connect(function()
		to(1)
	end)
	button.MouseButton1Down:Connect(function()
		if button.Active then to(0.93) end
	end)
	button.MouseButton1Up:Connect(function()
		if button.Active then to(grow) end
	end)
end

function Theme.label(name: string, parent: Instance, text: string?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name                   = name
	label.BackgroundTransparency = 1
	label.Font                   = Theme.FONT
	label.Text                   = text or ""
	label.TextColor3             = Theme.COLORS.text
	label.TextScaled             = true
	label.TextXAlignment         = Enum.TextXAlignment.Left
	label.Parent                 = parent

	-- Verhindert absurd grosse Schrift auf hohen Frames
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 28
	constraint.MinTextSize = 8
	constraint.Parent      = label

	return label
end

-- Kleiner, mehrzeiliger Fliesstext (Beschreibungen, Effekt-Texte).
-- Bewusst mit fester TextSize statt TextScaled: umgebrochener Text
-- wird sonst je nach Zeilenzahl unterschiedlich gross.
function Theme.bodyText(name: string, parent: Instance, text: string?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name                   = name
	label.BackgroundTransparency = 1
	label.Font                   = Theme.FONT_BODY
	label.Text                   = text or ""
	label.TextColor3             = Theme.COLORS.textDim
	label.TextScaled             = false
	label.TextSize               = 14
	label.TextWrapped            = true
	label.TextXAlignment         = Enum.TextXAlignment.Left
	label.TextYAlignment         = Enum.TextYAlignment.Top
	label.Parent                 = parent
	return label
end

function Theme.button(name: string, parent: Instance, text: string, color: Color3?): TextButton
	local button = Instance.new("TextButton")
	button.Name             = name
	button.BackgroundColor3  = color or Theme.COLORS.accent
	button.BorderSizePixel   = 0
	button.Font              = Theme.FONT
	button.Text              = text
	button.TextColor3        = Theme.COLORS.outline
	button.TextScaled        = true
	button.AutoButtonColor   = true
	button.Parent            = parent

	Theme.corner(button, 12)
	Theme.stroke(button)

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 24
	constraint.MinTextSize = 8
	constraint.Parent      = button

	-- Cartoon-Look: Verlauf + Glanzstreifen + Hover/Druck-Animation.
	-- AutoButtonColor aus: der Standard-Abdunkler faerbt sonst den ganzen
	-- Verlauf grau; die Animation uebernimmt das Feedback.
	-- Neutraler Verlauf (multipliziert sich auf die Knopffarbe, siehe panel).
	Theme.gradient(button, Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 190, 200))
	Theme.shine(button, 9)
	button.AutoButtonColor = false
	Theme.pressable(button)

	return button
end

-- Button ausgrauen bzw. wieder freigeben.
--
-- Das ist reiner Komfort: der Server prueft jede Anfrage selbst und schickt
-- bei Ablehnung ein ActionFailed (→ Toast). Ein ausgegrauter Button ist nur
-- die freundliche Vorwarnung, nie die Absicherung.
--
-- Die urspruengliche Farbe wird beim ersten Ausgrauen als Attribut gemerkt,
-- damit der Aufrufer sie nicht selbst mitschleppen muss.
-- Grosser, bunter Aktionsknopf mit Verlauf — der Knopf, um den herum ein
-- Menue gebaut wird ("AUSBAUEN", "FUETTERN"). Bewusst deutlich hoeher und
-- kraeftiger als Theme.button: in einem Menue soll auf einen Blick klar sein,
-- was der Hauptzweck ist.
function Theme.bigButton(name: string, parent: Instance, text: string, color: Color3): TextButton
	local button = Theme.button(name, parent, text, color)
	Theme.gradient(button, Theme.shade(color, 0.28), Theme.shade(color, -0.12))
	return button
end

-- Dunkler Umriss um die Schrift — der Look, den Roblox-Spiele fuer Beschriftungen
-- ueber bunten Flaechen benutzen. Ohne ihn verschwindet weisser Text auf gelben
-- Kacheln, und mit ihm wirkt jede Beschriftung wie aufgeklebt statt wie
-- hineingerechnet.
function Theme.outlineText(label: TextLabel, thickness: number?): TextLabel
	label.TextStrokeColor3       = Theme.COLORS.outline
	label.TextStrokeTransparency = 0
	label.RichText               = false

	local stroke = Instance.new("UIStroke")
	stroke.Color         = Theme.COLORS.outline
	stroke.Thickness     = thickness or 2
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent        = label

	return label
end

-- Kleine Grossbuchstaben-Ueberschrift ueber einem Abschnitt einer Karte.
function Theme.sectionLabel(name: string, parent: Instance, text: string, color: Color3?): TextLabel
	local label = Theme.label(name, parent, string.upper(text))
	label.TextColor3 = color or Theme.COLORS.textDim
	label.TextScaled = false
	label.TextSize   = 13
	label.Font       = Theme.FONT
	return label
end

function Theme.setEnabled(button: TextButton, enabled: boolean)
	local stored = button:GetAttribute("EnabledColor")
	if typeof(stored) ~= "Color3" then
		stored = button.BackgroundColor3
		button:SetAttribute("EnabledColor", stored)
	end

	button.Active          = enabled
	local shine = button:FindFirstChild("Shine")
	if shine and shine:IsA("GuiObject") then
		shine.Visible = enabled
	end
	button.BackgroundColor3 = if enabled then (stored :: Color3) else Theme.COLORS.disabled
	button.TextTransparency = if enabled then 0 else 0.4

	-- Ein Verlauf (Theme.bigButton) multipliziert sich auf die Hintergrundfarbe
	-- und wuerde den ausgegrauten Knopf weiter bunt aussehen lassen. Deshalb
	-- geht er beim Ausgrauen mit aus.
	local gradient = button:FindFirstChildOfClass("UIGradient")
	if gradient then
		gradient.Enabled = enabled
	end
end

-- Scrollbare Liste. Der Aufrufer haengt ein Theme.listLayout hinein und
-- setzt seine Zeilen auf UDim2.new(1, -8, 0, hoehe) — die -8 lassen Platz
-- fuer den Scrollbalken, sonst ragt jede Zeile darunter.
function Theme.scroller(name: string, parent: Instance): ScrollingFrame
	local scroller = Instance.new("ScrollingFrame")
	scroller.Name                   = name
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel        = 0
	scroller.ScrollBarThickness     = 6
	scroller.ScrollBarImageColor3   = Theme.COLORS.panelLight
	scroller.CanvasSize             = UDim2.new()
	scroller.AutomaticCanvasSize    = Enum.AutomaticSize.Y
	scroller.ScrollingDirection     = Enum.ScrollingDirection.Y
	scroller.Parent                 = parent
	return scroller
end

export type Progress = {
	track : Frame,
	fill  : Frame,
	text  : TextLabel,
}

-- Fortschrittsbalken mit Text darueber (Brut-Timer, XP, Kampf-HP).
function Theme.progress(parent: Instance, fillColor: Color3?): Progress
	local track = Theme.panel("Track", parent, Theme.COLORS.panelDeep)
	track.ClipsDescendants = true   -- damit der Fuellbalken die Rundung nicht ueberragt

	local fill = Instance.new("Frame")
	fill.Name             = "Fill"
	fill.Size             = UDim2.fromScale(0, 1)
	fill.BackgroundColor3  = fillColor or Theme.COLORS.accent
	fill.BorderSizePixel   = 0
	fill.Parent            = track
	Theme.corner(fill, 12)
	Theme.gradient(fill, Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 170, 185))
	Theme.shine(fill, 6).Size = UDim2.new(1, -8, 0.4, 0)

	local text = Theme.label("Text", track, "")
	text.Size           = UDim2.fromScale(1, 1)
	text.TextXAlignment = Enum.TextXAlignment.Center
	text.ZIndex         = 3
	Theme.outlineText(text, 2)

	return { track = track, fill = fill, text = text }
end

--------------------------------------------------------------------------------
-- Dialoge
--------------------------------------------------------------------------------

-- Ein Dialog laesst mindestens so viel vom Bildschirm frei (Anteil, je Achse).
local DIALOG_SCREEN_FILL = 0.94

-- Name des UIScale, mit dem ein Dialog auf kleine Bildschirme passt (siehe
-- Theme.dialog und Theme.dialogScale).
local FIT_SCALE_NAME = "FitScale"

-- Schliessen-Knopf (Sammel-Update 2.1: 44x40) plus eine unsichtbare
-- Trefferflaeche 56x56 darum — auf dem Handy trifft ein Daumen sonst leicht
-- daneben (Richtwert 44 pt).
local CLOSE_HIT = 56

-- Zentriertes Panel, standardmaessig unsichtbar. Groesse in Scale, damit es
-- auf Handy und Monitor passt; die Constraints halten es lesbar.
--
-- UI-Qualitaet Schritt 2: die Mindestgroesse (minSize) war auf kleinen
-- Bildschirmen groesser als der Bildschirm selbst — ein Handy quer hat ohne
-- Topbar rund 350 px Hoehe, Charms/Bestenliste/Kampf brauchen 420. Kopfzeile
-- und Schliessen-X lagen dann ausserhalb. Jetzt verkleinert ein UIScale
-- (FitScale) den GANZEN Dialog gleichmaessig, bis er passt: das Layout bleibt
-- wie gebaut, nur kleiner. Auf normalen Bildschirmen ist der Faktor 1.
function Theme.dialog(name: string, parent: Instance, scale: Vector2, minSize: Vector2, maxSize: Vector2): Frame
	local root = Theme.panel(name, parent, Theme.COLORS.panelDeep)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position    = UDim2.fromScale(0.5, 0.5)
	root.Size        = UDim2.fromScale(scale.X, scale.Y)
	root.Visible     = false
	root.ZIndex      = 10

	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = minSize
	constraint.MaxSize = maxSize
	constraint.Parent  = root

	local fit = Instance.new("UIScale")
	fit.Name   = FIT_SCALE_NAME
	fit.Parent = root

	if parent:IsA("LayerCollector") then
		local screen = parent :: LayerCollector
		local function refit()
			-- AbsoluteSize sind echte Pixel; die globale UiScale (>= 1) rechnet
			-- sie in Oberflaechen-Einheiten um, in denen minSize gemeint ist.
			local global = screen:FindFirstChild("GlobalScale")
			local globalScale = if global and global:IsA("UIScale") then math.max(global.Scale, 0.01) else 1
			local room = screen.AbsoluteSize / globalScale * DIALOG_SCREEN_FILL
			if room.X <= 0 or room.Y <= 0 then return end
			fit.Scale = math.min(1, room.X / minSize.X, room.Y / minSize.Y)
		end
		screen:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
		-- Die globale UiScale kann nach dem Dialog angelegt werden (Main) und
		-- aendert sich mit der Fenstergroesse.
		screen.ChildAdded:Connect(function(child)
			if child.Name == "GlobalScale" and child:IsA("UIScale") then
				child:GetPropertyChangedSignal("Scale"):Connect(refit)
				refit()
			end
		end)
		local global = screen:FindFirstChild("GlobalScale")
		if global and global:IsA("UIScale") then
			global:GetPropertyChangedSignal("Scale"):Connect(refit)
		end
		refit()
	end

	return root
end

-- Gesamter Verkleinerungsfaktor der Dialoge, in denen `gui` steckt (1 = keiner).
-- Fuer Code, der AbsolutePosition/AbsoluteSize in eine Position INNERHALB eines
-- Dialogs zurueckrechnet (IndexView): erst UiScale.toGui, dann durch diesen Wert.
function Theme.dialogScale(gui: Instance): number
	local factor = 1
	local node: Instance? = gui
	while node do
		local fit = node:FindFirstChild(FIT_SCALE_NAME)
		if fit and fit:IsA("UIScale") then
			factor *= fit.Scale
		end
		node = node.Parent
	end
	return factor
end

-- Sammel-Update 2.1: der eine Schliessen-Knopf fuer alle Fenster (oben
-- rechts, gross genug zum Tippen). Fenster ohne dialogHeader (Baerchi-Karte)
-- setzen ihn direkt. `color` optional (Gebaeude-Menue: Ton seiner Farbe).
-- UI-Qualitaet: dazu eine unsichtbare Trefferflaeche (CLOSE_HIT) als Kind —
-- sie liegt ueber dem Knopf (ZIndexBehavior.Sibling) und nimmt jeden Klick in
-- ihrem Bereich an, auch knapp neben dem sichtbaren X.
function Theme.closeButton(parent: Instance, onClose: () -> (), color: Color3?): TextButton
	local close = Theme.button("Close", parent, "X", color or Theme.COLORS.bad)
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position    = UDim2.new(1, 4, 0.5, 0)
	close.Size        = UDim2.new(0, 44, 0, 40)
	close.TextColor3  = Theme.COLORS.text
	close.ZIndex      = math.max(close.ZIndex, 12)
	close.Activated:Connect(onClose)

	local hit = Instance.new("TextButton")
	hit.Name                   = "CloseHit"
	hit.AnchorPoint            = Vector2.new(0.5, 0.5)
	hit.Position               = UDim2.fromScale(0.5, 0.5)
	hit.Size                   = UDim2.fromOffset(CLOSE_HIT, CLOSE_HIT)
	hit.BackgroundTransparency = 1
	hit.Text                   = ""
	hit.AutoButtonColor        = false
	hit.ZIndex                 = close.ZIndex
	hit.Parent                 = close
	hit.Activated:Connect(onClose)

	return close
end

-- Kopfzeile eines Dialogs: Titel links, Schliessen-Kreuz rechts.
-- Gibt das Titel-Label zurueck, damit der Aufrufer es spaeter aendern kann.
function Theme.dialogHeader(root: Frame, title: string, onClose: () -> ()): TextLabel
	-- Farbiger Titelbalken hinter der Kopfzeile (zuerst gebaut, liegt darum
	-- unter Titel und Kreuz).
	local band = Instance.new("Frame")
	band.Name             = "TitleBand"
	band.Position         = UDim2.new(0, 6, 0, 5)
	band.Size             = UDim2.new(1, -12, 0, 42)
	band.BackgroundColor3 = Color3.fromRGB(122, 104, 204)
	band.BorderSizePixel  = 0
	band.Parent           = root
	Theme.corner(band, 12)
	Theme.stroke(band, Theme.COLORS.outline, 2)
	Theme.gradient(band, Color3.fromRGB(255, 255, 255), Color3.fromRGB(176, 170, 215))
	Theme.shine(band, 8).Size = UDim2.new(1, -12, 0.36, 0)

	local header = Theme.container("Header", root)
	header.Position = UDim2.new(0, 14, 0, 11)
	header.Size     = UDim2.new(1, -28, 0, 30)

	local label = Theme.label("Title", header, title)
	label.Size = UDim2.new(1, -52, 1, 0)
	Theme.outlineText(label, 2)

	-- Sammel-Update 2.1: groesserer X-Knopf (Tippflaeche ~44 px, Apple/
	-- Google-Empfehlung) — er ragt bewusst etwas ueber die Kopfzeile hinaus.
	Theme.closeButton(header, onClose)

	return label
end

-- Inhaltsflaeche unter der Kopfzeile.
function Theme.dialogBody(root: Frame): Frame
	local body = Theme.container("Body", root)
	body.Position = UDim2.new(0, 14, 0, 48)
	body.Size     = UDim2.new(1, -28, 1, -62)
	return body
end

--------------------------------------------------------------------------------
-- Theme.v2 — Tokens des neuen Looks (08.10., Paket D)
--------------------------------------------------------------------------------
-- Nur UI/Kit (und Panels, die Kit benutzen) lesen diese Tabelle. Alles oben
-- (COLORS, panel, button, dialog ...) bleibt unveraendert: die alten Panels
-- sehen genauso aus wie vorher. Wer die Palette tauschen will, aendert NUR
-- die Werte hier — kein Kit-Baustein hat eine eigene Farbe oder Zahl.
--
-- Richtung: warm und freundlich (Honig-Amber, Baerchi-Braun, Gummi-Pink,
-- Himmelblau), helle Creme-Flaechen mit dicker schokobrauner Kontur, Knoepfe
-- mit 3D-Kante und Glanz. Masse in Oberflaechen-Einheiten (die globale
-- UiScale vergroessert auf grossen Bildschirmen, 1080p ~ x1,27). 8er-Raster.
-- Kontraste (WCAG, gerechnet im Bericht): ink auf surface 11,6:1, inkSoft auf
-- card 6,5:1; weisse Knopfschrift traegt immer eine 3-px-Kontur (ink).
Theme.v2 = {
	color = {
		-- Flaechen
		surface     = Color3.fromRGB(255, 244, 220),   -- Panel-Koerper (Creme)
		surfaceDeep = Color3.fromRGB(246, 226, 190),   -- Verlauf unten
		card        = Color3.fromRGB(255, 252, 243),   -- Karte
		cardLocked  = Color3.fromRGB(236, 226, 210),   -- gesperrte Karte
		sunk        = Color3.fromRGB(240, 222, 190),   -- Balken-Spur, Chips
		shadow      = Color3.fromRGB( 59,  34,  18),   -- Schlagschatten

		-- Schrift und Kontur
		ink         = Color3.fromRGB( 74,  44,  23),   -- Text (Schokolade)
		inkSoft     = Color3.fromRGB(122,  84,  53),   -- Nebentext
		outline     = Color3.fromRGB( 59,  34,  18),   -- dicke Kontur
		white       = Color3.fromRGB(255, 255, 255),

		-- Marke
		honey       = Color3.fromRGB(255, 182,  39),
		honeyTop    = Color3.fromRGB(255, 214, 100),
		honeyBottom = Color3.fromRGB(255, 152,  24),
		bear        = Color3.fromRGB(156,  98,  51),
		gummy       = Color3.fromRGB(255,  92, 154),
		gummyDeep   = Color3.fromRGB(214,  51, 120),
		sky         = Color3.fromRGB( 76, 195, 255),
		skyDeep     = Color3.fromRGB( 22, 120, 190),

		-- Knopf-Arten
		go          = Color3.fromRGB( 72, 196,  70),   -- Primaer (Gratis-Start)
		goTop       = Color3.fromRGB(120, 230, 100),
		goEdge      = Color3.fromRGB( 30, 128,  44),   -- 3D-Kante unten
		quiet       = Color3.fromRGB(255, 248, 232),   -- Sekundaer (Skip): Creme
		quietEdge   = Color3.fromRGB(214, 190, 150),
		gold        = Color3.fromRGB(255, 222, 128),   -- Premium (Pass): ruhiges Gold
		goldTop     = Color3.fromRGB(255, 243, 200),
		goldEdge    = Color3.fromRGB(206, 150,  30),
		choose      = Color3.fromRGB( 76, 195, 255),   -- "Waehlen" auf der Karte
		chooseEdge  = Color3.fromRGB( 22, 120, 190),

		-- Zustaende
		active      = Color3.fromRGB(255, 196,  40),   -- "AKTIV"-Band
		new         = Color3.fromRGB(255,  92, 154),   -- "NEU"-Abzeichen
		lock        = Color3.fromRGB(150, 132, 112),
		progress    = Color3.fromRGB( 72, 196,  70),
	},
	radius = { panel = 26, card = 18, button = 16, chip = 999, badge = 14 },
	stroke = { panel = 4, card = 3, button = 3, text = 3, textSmall = 2 },
	space  = { xs = 4, s = 8, m = 16, l = 24, xl = 32 },
	text   = {
		font      = Enum.Font.FredokaOne,
		title     = 40,
		cardTitle = 26,
		number    = 30,
		body      = 18,
		small     = 15,   -- nie kleiner (1080p: ~19 px)
		button    = 26,
	},
	motion = {
		open      = 0.32,   -- Panel springt auf (Back)
		stagger   = 0.05,   -- Karten nacheinander
		cardIn    = 0.28,
		press     = 0.10,
		pulse     = 1.6,    -- Sekunden je Puls (nur der Gratis-Start)
		glimmer   = 2.6,    -- Glanz ueber freie neue Karten
		confetti  = 1.2,
	},
}

--------------------------------------------------------------------------------
-- Verzierte Rahmen (Ei-Menue, Ei-Baum, Infokarte)
--------------------------------------------------------------------------------

-- Legt den 9-Slice-Rahmen `kind` ("panel" | "card" | "tile") ueber `frame`.
-- "panel" und "card" bringen ihre Fuellung mit (Hintergrund wird
-- durchsichtig), "tile" ist nur ein Zierrand ueber der vorhandenen Farbe.
--
-- Ohne hochgeladenes Bild bleibt die Flaeche ein normales Theme.panel, nur in
-- den Farben der Bilderbuch-Palette — bedienbar und im selben Ton.
function Theme.ornate(frame: GuiObject, kind: string, sliceScale: number?): ImageLabel?
	local stroke = frame:FindFirstChildOfClass("UIStroke")
	local image = Icons.uiImage(frame, "frames/frame_" .. kind, sliceScale)
	if not image then
		if stroke then stroke.Color = Theme.COLORS.honeyDeep end
		if kind == "panel" then
			frame.BackgroundColor3 = Theme.COLORS.walnutDeep
		elseif kind == "card" then
			frame.BackgroundColor3 = Theme.COLORS.forest
		end
		return nil
	end
	image.Name   = "Ornate"
	image.Size   = UDim2.fromScale(1, 1)
	-- ZIndexBehavior = Sibling: der Rahmen ist ein Geschwister von Titel und
	-- Inhalt und muss UNTER ihnen liegen.
	image.ZIndex = 0
	if kind ~= "tile" then
		frame.BackgroundTransparency = 1
		if stroke then stroke.Enabled = false end
	end
	return image
end

-- Dialog (Theme.dialog + dialogHeader + dialogBody) im verzierten Rahmen:
-- Titelband in Honig statt Lila, Kopf und Inhalt ruecken vom Zierrand weg.
function Theme.ornateDialog(root: Frame)
	local image = Theme.ornate(root, "panel", 0.5)
	local band = root:FindFirstChild("TitleBand")
	if band and band:IsA("Frame") then
		band.BackgroundColor3 = Theme.COLORS.honeyDeep
		Theme.gradient(band, Color3.fromRGB(255, 236, 200), Color3.fromRGB(200, 150, 110))
	end
	if not image then return end
	local header = root:FindFirstChild("Header")
	local body = root:FindFirstChild("Body")
	if band and band:IsA("GuiObject") then
		band.Position = UDim2.new(0, 18, 0, 15)
		band.Size     = UDim2.new(1, -36, 0, 40)
	end
	if header and header:IsA("GuiObject") then
		header.Position = UDim2.new(0, 26, 0, 20)
		header.Size     = UDim2.new(1, -52, 0, 30)
	end
	if body and body:IsA("GuiObject") then
		body.Position = UDim2.new(0, 22, 0, 62)
		body.Size     = UDim2.new(1, -44, 1, -82)
	end
end

-- Grosser Aktionsknopf als Honigtropfen-Siegel ("Oeffnen"). Ohne Bild ein
-- honigfarbener bigButton. Die Beschriftung bleibt button.Text (ein
-- Kind-Label spiegelt sie ueber das Siegelbild), damit Aufrufer und
-- Theme.setEnabled wie gewohnt arbeiten.
function Theme.sealButton(name: string, parent: Instance, text: string): TextButton
	local button = Theme.bigButton(name, parent, text, Theme.COLORS.honey)
	local image = Icons.uiImage(button, "frames/seal", 0.42)
	if not image then return button end

	button.BackgroundTransparency = 1
	local stroke = button:FindFirstChildOfClass("UIStroke")
	if stroke then stroke.Enabled = false end
	local shine = button:FindFirstChild("Shine")
	if shine then shine:Destroy() end
	image.Name     = "Seal"
	image.Position = UDim2.new(0, -4, 0, -3)
	image.Size     = UDim2.new(1, 8, 1, 10)
	image.ZIndex   = 0

	local label = Theme.label("SealText", button, text)
	label.Size           = UDim2.new(1, -16, 1, -4)
	label.Position       = UDim2.fromOffset(8, 1)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.ZIndex         = 2
	Theme.outlineText(label, 2)
	button.TextTransparency = 1

	local function sync()
		label.Text   = button.Text
		image.ImageColor3 = if button.Active then Color3.new(1, 1, 1) else Color3.fromRGB(130, 124, 120)
		label.TextTransparency = if button.Active then 0 else 0.35
		button.TextTransparency = 1
	end
	button:GetPropertyChangedSignal("Text"):Connect(sync)
	button:GetPropertyChangedSignal("Active"):Connect(sync)
	button:GetPropertyChangedSignal("TextTransparency"):Connect(function()
		if button.TextTransparency ~= 1 then sync() end
	end)
	sync()
	return button
end

--------------------------------------------------------------------------------
-- Formatierung
--------------------------------------------------------------------------------

-- Grosse Zahlen lesbar machen: 1234567 → "1.234.567" (de/es), "1,234,567" (en),
-- "1 234 567" (fr). Das Trennzeichen kommt aus der Sprache des Spielers — die
-- Logik steht in Loc, damit Server-Texte und UI dieselbe Formatierung teilen.
-- Bleibt als Theme-Funktion bestehen, damit kein UI-Modul umgeschrieben werden
-- muss, das schon formatNumber benutzt.
function Theme.formatNumber(value: number): string
	return Loc.formatNumber(value)
end

-- Restzeiten: "45s", "2m 05s", "1h 12m" (Einheiten je nach Sprache)
function Theme.formatDuration(seconds: number): string
	return Loc.formatDuration(seconds)
end

return Theme
