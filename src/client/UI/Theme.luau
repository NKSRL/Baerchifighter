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

local BaerchiConfig = require(ReplicatedStorage.Config.BaerchiConfig)
local Types         = require(ReplicatedStorage.Network.Types)
local Loc           = require(ReplicatedStorage.Localization.Loc)

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
	HoneyPot   = Theme.COLORS.healing,
	HoneyPress = Theme.COLORS.growth,
}

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
	local gradient = Instance.new("UIGradient")
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
	return frame
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
	button.AutoButtonColor = enabled
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
	local track = Theme.panel("Track", parent, Theme.COLORS.panel)
	track.ClipsDescendants = true   -- damit der Fuellbalken die Rundung nicht ueberragt

	local fill = Instance.new("Frame")
	fill.Name             = "Fill"
	fill.Size             = UDim2.fromScale(0, 1)
	fill.BackgroundColor3  = fillColor or Theme.COLORS.accent
	fill.BorderSizePixel   = 0
	fill.Parent            = track
	Theme.corner(fill, 12)

	local text = Theme.label("Text", track, "")
	text.Size           = UDim2.fromScale(1, 1)
	text.TextXAlignment = Enum.TextXAlignment.Center
	text.ZIndex         = 2

	return { track = track, fill = fill, text = text }
end

--------------------------------------------------------------------------------
-- Dialoge
--------------------------------------------------------------------------------

-- Zentriertes Panel, standardmaessig unsichtbar. Groesse in Scale, damit es
-- auf Handy und Monitor passt; die Constraints halten es lesbar.
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

	return root
end

-- Kopfzeile eines Dialogs: Titel links, Schliessen-Kreuz rechts.
-- Gibt das Titel-Label zurueck, damit der Aufrufer es spaeter aendern kann.
function Theme.dialogHeader(root: Frame, title: string, onClose: () -> ()): TextLabel
	local header = Theme.container("Header", root)
	header.Position = UDim2.new(0, 14, 0, 10)
	header.Size     = UDim2.new(1, -28, 0, 30)

	local label = Theme.label("Title", header, title)
	label.Size = UDim2.new(1, -40, 1, 0)

	local close = Theme.button("Close", header, "X", Theme.COLORS.panelLight)
	close.AnchorPoint = Vector2.new(1, 0.5)
	close.Position    = UDim2.new(1, 0, 0.5, 0)
	close.Size        = UDim2.new(0, 32, 0, 26)
	close.TextColor3  = Theme.COLORS.text
	close.Activated:Connect(onClose)

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
