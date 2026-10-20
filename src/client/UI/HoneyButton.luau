--!strict
-- HoneyButton.luau
-- StarterPlayerScripts/UI/HoneyButton.luau
--
-- Einzige Zustaendigkeit:
--   - Einen Standard-Knopf im Honig-Look bauen (honey/btn_dark oder btn_light, mit
--     Beschriftung darueber) — und ohne Honig-Bilder auf Theme.button zurueckfallen
--
-- Das Muster stammt aus LanguagePanel.honeyRow; hier einmal ausgelagert, damit
-- der Verkaufsmodus und sein Bestaetigungsfenster nicht je eine eigene Kopie
-- brauchen. Die Groesse setzt der Aufrufer am `holder`; das Bild passt sich mit
-- festem Seitenverhaeltnis (Fit) ein.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)

local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)

local HoneyButton = {}

export type Kind = "dark" | "light"

export type Handle = {
	-- das Objekt, dessen Position/Groesse/LayoutOrder der Aufrufer setzt
	holder     : GuiObject,
	-- der klickbare Knopf (Activated)
	button     : TextButton,
	setEnabled : (boolean) -> (),
	setText    : (string) -> (),
	-- "eingeschaltet"-Zustand (z.B. Umschalter): helles Bild bzw. Akzentfarbe
	setActive  : (boolean) -> (),
}

function HoneyButton.isHoney(): boolean
	return FeatureFlags.isOn("UI_HONEY_SKIN") and Icons.hasUi("honey/btn_dark") and Icons.hasUi("honey/btn_light")
end

function HoneyButton.make(parent: Instance, name: string, text: string, kind: Kind, fallbackColor: Color3?): Handle
	if not HoneyButton.isHoney() then
		local plain = Theme.button(name, parent, text, fallbackColor or Theme.COLORS.panelLight)
		plain.TextColor3 = Theme.COLORS.text
		return {
			holder     = plain,
			button     = plain,
			setEnabled = function(enabled: boolean) Theme.setEnabled(plain, enabled) end,
			setText    = function(newText: string) plain.Text = newText end,
			setActive  = function(active: boolean)
				plain.BackgroundColor3 = if active then Theme.COLORS.goldGummy else (fallbackColor or Theme.COLORS.panelLight)
				plain:SetAttribute("EnabledColor", plain.BackgroundColor3)
				plain.TextColor3 = if active then Theme.COLORS.outline else Theme.COLORS.text
			end,
		}
	end

	local holder = Theme.container(name .. "_Holder", parent)

	local art = Icons.honeyStdButton(holder, if kind == "light" then "honey/btn_light" else "honey/btn_dark")
	if art then art.ZIndex = 1 end

	local button = Instance.new("TextButton")
	button.Name                   = name
	button.BackgroundTransparency = 1
	button.AutoButtonColor        = false
	button.Size                   = UDim2.fromScale(1, 1)
	button.Font                   = Theme.FONT
	button.Text                   = text
	button.TextScaled             = true
	button.ZIndex                 = 2
	button.Parent                 = holder

	local light = kind == "light"
	local textColor   = if light then Color3.fromRGB(78, 42, 12) else Color3.fromRGB(255, 244, 214)
	local strokeColor = if light then Color3.fromRGB(255, 226, 140) else Color3.fromRGB(58, 30, 8)
	button.TextColor3       = textColor
	button.TextStrokeColor3 = strokeColor
	button.TextStrokeTransparency = if light then 0.75 else 0.3

	-- Text bleibt im Feld des Bildes (Blaetter/Blueten links und rechts frei)
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft   = UDim.new(0.17, 0)
	padding.PaddingRight  = UDim.new(0.17, 0)
	padding.PaddingTop    = UDim.new(0.24, 0)
	padding.PaddingBottom = UDim.new(0.26, 0)
	padding.Parent = button

	return {
		holder = holder,
		button = button,
		setEnabled = function(enabled: boolean)
			button.Active = enabled
			button.TextTransparency = if enabled then 0 else 0.45
			if art then art.ImageTransparency = if enabled then 0 else 0.55 end
		end,
		setText = function(newText: string)
			button.Text = newText
		end,
		setActive = function(active: boolean)
			local asLight = active or light
			if art then art.Image = Icons.ui(if asLight then "honey/btn_light" else "honey/btn_dark") or art.Image end
			button.TextColor3 = if asLight then Color3.fromRGB(78, 42, 12) else Color3.fromRGB(255, 244, 214)
			button.TextStrokeColor3 = if asLight then Color3.fromRGB(255, 226, 140) else Color3.fromRGB(58, 30, 8)
			button.TextStrokeTransparency = if asLight then 0.75 else 0.3
		end,
	}
end

return HoneyButton
