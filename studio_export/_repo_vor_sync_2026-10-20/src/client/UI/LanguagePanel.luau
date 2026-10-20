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
local PanelManager       = require(script.Parent.PanelManager)
local LanguageController = require(script.Parent.Parent.Controllers.LanguageController)

local LanguagePanel = {}

local PANEL_NAME = "Language"

-- Eintrag "Automatisch" hat den Wert nil; die anderen ihren Sprachcode.
type Row = {
	code   : string?,
	button : TextButton,
	color  : Color3,
}

local _root: Frame? = nil
local _rows: { Row } = {}

--------------------------------------------------------------------------------
-- Anzeige
--------------------------------------------------------------------------------

-- Faerbt die gerade gewaehlte Zeile hell, alle anderen gedaempft.
local function refresh()
	local choice = LanguageController.getChoice()

	for _, row in _rows do
		local selected = row.code == choice
		row.button.BackgroundColor3 = if selected then Theme.COLORS.good else row.color
		row.button.TextColor3       = if selected then Theme.COLORS.outline else Theme.COLORS.text
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

local function addRow(body: Frame, order: number, code: string?, text: string?, bindKey: string?)
	local button = Theme.button("Lang_" .. tostring(code or "auto"), body, text or "", Theme.COLORS.panelLight)
	button.Size        = UDim2.new(1, -8, 0, 40)
	button.LayoutOrder = order
	button.TextColor3  = Theme.COLORS.text

	if bindKey then
		Loc.bind(button, bindKey)
	end

	button.Activated:Connect(function()
		LanguageController.choose(code)
		refresh()
		PanelManager.close(PANEL_NAME)
	end)

	table.insert(_rows, { code = code, button = button, color = Theme.COLORS.panelLight })
end

function LanguagePanel.init(screenGui: ScreenGui)
	local root = Theme.dialog(
		"LanguagePanel", screenGui,
		Vector2.new(0.30, 0.52),
		Vector2.new(240, 300),
		Vector2.new(340, 360)
	)
	_root = root

	local title = Theme.dialogHeader(root, "", function()
		PanelManager.close(PANEL_NAME)
	end)
	Loc.bind(title, "ui.language.title")

	local body = Theme.dialogBody(root)
	Theme.listLayout(body, 8)

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
