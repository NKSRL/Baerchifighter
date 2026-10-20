--!strict
-- LanguagePanel.luau
-- StarterPlayerScripts/UI/LanguagePanel.luau
--
-- Einzige Zustaendigkeit:
--   - Kleines Fenster, in dem der Spieler seine Sprache waehlt
--
-- Die Sprachnamen stehen bewusst in der JEWEILIGEN Sprache ("Deutsch",
-- "English", "Français", "Español") und werden nie uebersetzt: wer die
-- Oberflaeche gerade nicht versteht, muss seine Sprache trotzdem finden.
-- Nur der Eintrag "Automatisch" und der Titel folgen der aktiven Sprache.
--
-- Was gilt und was gespeichert wird, entscheidet LanguageController — dieses
-- Panel ruft nur dessen choose() auf und faerbt die aktuelle Wahl.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loc = require(ReplicatedStorage.Localization.Loc)

local Theme              = require(script.Parent.Theme)
local Icons              = require(script.Parent.Icons)
local FeatureFlags       = require(ReplicatedStorage.Config.FeatureFlags)
local PanelManager       = require(script.Parent.PanelManager)
local LanguageController = require(script.Parent.Parent.Controllers.LanguageController)

local LanguagePanel = {}

local PANEL_NAME = "Language"

-- Eintrag "Automatisch" hat den Wert nil; die anderen ihren Sprachcode.
type Row = {
	code   : string?,
	button : TextButton,
	color  : Color3,
	-- Honig-UI (14.10.): zwei Bilder uebereinander, gewaehlt = heller Knopf, sonst dunkler
	dark   : ImageLabel?,
	light  : ImageLabel?,
}

-- Honig-UI: Fenster aus honey/settings_window (zugeschnitten, 800 x 474 Einheiten)
local WIN_W, WIN_H = 800, 474
local ROW_W, ROW_H = 208, 54   -- Seitenverhaeltnis der Standard-Knoepfe (~3,85)

local function honeyOn(): boolean
	return FeatureFlags.isOn("UI_HONEY_SKIN") and Icons.hasUi("honey/settings_window")
		and Icons.hasUi("honey/btn_dark") and Icons.hasUi("honey/btn_light")
end

local _root: Frame? = nil
local _rows: { Row } = {}
local honeyWindowImage: ImageLabel? = nil

--------------------------------------------------------------------------------
-- Anzeige
--------------------------------------------------------------------------------

-- Faerbt die gerade gewaehlte Zeile hell, alle anderen gedaempft.
local function refresh()
	local choice = LanguageController.getChoice()

	for _, row in _rows do
		local selected = row.code == choice
		if row.dark and row.light then
			row.dark.Visible  = not selected
			row.light.Visible = selected
			row.button.TextColor3 = if selected then Color3.fromRGB(78, 42, 12) else Color3.fromRGB(255, 244, 214)
			row.button.TextStrokeColor3 = if selected then Color3.fromRGB(255, 226, 140) else Color3.fromRGB(58, 30, 8)
			row.button.TextStrokeTransparency = if selected then 0.75 else 0.3
		else
			row.button.BackgroundColor3 = if selected then Theme.COLORS.good else row.color
			row.button.TextColor3       = if selected then Theme.COLORS.outline else Theme.COLORS.text
		end
	end
end

local function openInternal(...: any)
	local root = _root
	if not root then return end
	root.Visible = true
	refresh()
end

local function closeInternal()
	local root = _root
	if root then root.Visible = false end
end

--------------------------------------------------------------------------------
-- Aufbau
--------------------------------------------------------------------------------

-- Honig-UI: Zeile = fester Halter mit den zwei Knopf-Bildern, darueber ein durchsichtiger
-- Knopf (fuellt den Halter, Text mit Rand innen). Gibt Knopf und Bilder zurueck.
local function honeyRow(body: Frame, order: number, name: string, text: string): (TextButton, ImageLabel?, ImageLabel?)
	local holder = Theme.container(name .. "_Row", body)
	holder.Size        = UDim2.fromOffset(ROW_W, ROW_H)
	holder.LayoutOrder = order

	local dark  = Icons.honeyStdButton(holder, "honey/btn_dark")
	local light = Icons.honeyStdButton(holder, "honey/btn_light")
	for _, art in { dark, light } do
		if art then art.ZIndex = 1 end
	end
	if light then light.Visible = false end

	local button = Instance.new("TextButton")
	button.Name                   = name
	button.BackgroundTransparency = 1
	button.AutoButtonColor        = false
	button.Size                   = UDim2.fromScale(1, 1)
	button.Font                   = Theme.FONT
	button.Text                   = text
	button.TextScaled             = true
	button.TextColor3             = Color3.fromRGB(255, 244, 214)
	button.ZIndex                 = 2
	button.Parent                 = holder

	-- Text bleibt im Feld des Bildes (Blaetter/Blueten links und rechts frei)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft   = UDim.new(0.17, 0)
	padding.PaddingRight  = UDim.new(0.17, 0)
	padding.PaddingTop    = UDim.new(0.24, 0)
	padding.PaddingBottom = UDim.new(0.26, 0)
	padding.Parent = button

	return button, dark, light
end

local function addRow(body: Frame, order: number, code: string?, text: string?, bindKey: string?)
	local button: TextButton
	local dark: ImageLabel? = nil
	local light: ImageLabel? = nil
	local rowName = "Lang_" .. tostring(code or "auto")

	if honeyOn() then
		button, dark, light = honeyRow(body, order, rowName, text or "")
	else
		button = Theme.button(rowName, body, text or "", Theme.COLORS.panelLight)
		button.Size        = UDim2.new(1, -8, 0, 40)
		button.LayoutOrder = order
		button.TextColor3  = Theme.COLORS.text
	end

	if bindKey then
		Loc.bind(button, bindKey)
	end

	button.Activated:Connect(function()
		LanguageController.choose(code)
		refresh()
		PanelManager.close(PANEL_NAME)
	end)

	table.insert(_rows, { code = code, button = button, color = Theme.COLORS.panelLight, dark = dark, light = light })
end

function LanguagePanel.init(screenGui: ScreenGui)
	local honey = honeyOn()

	-- Honig-UI: feste Fenstergroesse = auch Mindestgroesse, damit sich der Dialog auf kleinen
	-- Bildschirmen als Ganzes verkleinert (UIScale in Theme.dialog) statt ueberzustehen.
	local root = Theme.dialog(
		"LanguagePanel", screenGui,
		Vector2.new(0.30, 0.52),
		if honey then Vector2.new(WIN_W, WIN_H) else Vector2.new(240, 300),
		if honey then Vector2.new(WIN_W, WIN_H) else Vector2.new(340, 360)
	)
	_root = root

	-- 14.10. (UI_HONEY_SKIN): Fenster ist ein Bild (Einstellungen), Titel steht im Bild
	if honey then
		honeyWindowImage = Icons.honeyWindow(root, "honey/settings_window", WIN_W, WIN_H)
		honey = honeyWindowImage ~= nil
	end

	local title = Theme.dialogHeader(root, "", function()
		PanelManager.close(PANEL_NAME)
	end)
	Loc.bind(title, "ui.language.title")

	local body = Theme.dialogBody(root)
	local layout = Theme.listLayout(body, 8)

	if honey then
		-- Kreuz auf das Kreuz im Bild (Mitte 747/67), Titel-Label aus: "Settings" steht im Bild
		Icons.honeyHeader(root, Rect.new(260, 20, 560, 80), 747, 67, 58)
		title.Visible = false
		-- Inhaltsflaeche = dunkles Feld des Bildes (links daneben die Tab-Leiste, noch leer)
		body.Position = UDim2.fromOffset(108, 114)
		body.Size     = UDim2.fromOffset(652, 326)
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	end

	-- "Automatisch" zuerst, danach die Sprachen in der Reihenfolge aus Loc
	addRow(body, 1, nil, nil, "ui.language.auto")
	for index, lang in Loc.LANGUAGES do
		addRow(body, index + 1, lang.code, lang.native, nil)
	end

	PanelManager.register(PANEL_NAME, {
		open  = openInternal,
		close = closeInternal,
	})

	print("[LanguagePanel] Initialisiert")
end

return LanguagePanel
