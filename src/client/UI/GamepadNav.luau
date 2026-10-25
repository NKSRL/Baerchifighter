--!strict
-- GamepadNav.luau
-- StarterPlayerScripts/UI/GamepadNav.luau
--
-- Einzige Zustaendigkeit:
--   - Fokus-Hilfen fuer die Controller-Bedienung (Welt 1, Paket 6d): sichtbarer
--     Auswahl-Rahmen, erstes sinnvolles Element im Fenster auswaehlen, Tab- und
--     Hauptknopf-Suche, Blaettern, Tastensymbole in Knoepfen.
--
-- Keine Eingabe-Bindung hier (das macht Controllers/GamepadController), kein
-- Wissen ueber einzelne Fenster: Fenster werden ueber ihre Bauart erkannt
-- (sichtbare Kinder der ScreenGui mit hoher ZIndex, Knoepfe "Tab_*", Kit-Knopf
-- mit Attribut HBBKind = "primary").

local GuiService = game:GetService("GuiService")

local GamepadConfig = require(game:GetService("ReplicatedStorage").Config.GamepadConfig)

local GamepadNav = {}

local WINDOW_MIN_Z = 10          -- Theme.dialog setzt ZIndex 10
local GLYPH_NAME   = "PadGlyph"

local _template: Frame? = nil
local _styled: { [GuiObject]: boolean } = {}
local _styleConn: RBXScriptConnection? = nil

--------------------------------------------------------------------------------
-- Auswahl-Rahmen
--------------------------------------------------------------------------------

local function template(): Frame
	if _template then return _template end
	local frame = Instance.new("Frame")
	frame.Name = "PadSelection"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.new(1, 8, 1, 8)
	frame.Position = UDim2.fromOffset(-4, -4)
	local stroke = Instance.new("UIStroke")
	stroke.Color = GamepadConfig.SELECTION_COLOR
	stroke.Thickness = GamepadConfig.SELECTION_THICKNESS
	stroke.Parent = frame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = frame
	_template = frame
	return frame
end

local function styleOne(instance: Instance)
	if instance:IsA("GuiButton") then
		instance.SelectionImageObject = template()
		_styled[instance] = true
	end
end

-- Rahmen an alle Knoepfe (jetzt und spaeter gebaute). Wiederholter Aufruf ist harmlos.
function GamepadNav.styleSelection(root: Instance)
	if _styleConn then return end
	for _, d in root:GetDescendants() do styleOne(d) end
	_styleConn = root.DescendantAdded:Connect(styleOne)
end

function GamepadNav.unstyleSelection()
	if _styleConn then _styleConn:Disconnect(); _styleConn = nil end
	for object in _styled do
		if object.Parent then object.SelectionImageObject = nil end
	end
	table.clear(_styled)
end

--------------------------------------------------------------------------------
-- Sichtbarkeit / Suche
--------------------------------------------------------------------------------

local function visibleChain(object: GuiObject, stopAt: Instance): boolean
	local node: Instance? = object
	while node and node ~= stopAt do
		if node:IsA("GuiObject") and not node.Visible then return false end
		node = node.Parent
	end
	return true
end

local function selectable(button: GuiButton, container: Instance): boolean
	return button.Active and button.Selectable and button.AbsoluteSize.X > 4 and button.AbsoluteSize.Y > 4
		and visibleChain(button, container.Parent or container)
end

local function readingOrder(a: GuiObject, b: GuiObject): boolean
	local pa, pb = a.AbsolutePosition, b.AbsolutePosition
	if math.abs(pa.Y - pb.Y) > 8 then return pa.Y < pb.Y end
	return pa.X < pb.X
end

-- Alle auswaehlbaren Knoepfe in Leserichtung
function GamepadNav.buttons(container: Instance): { GuiButton }
	local list: { GuiButton } = {}
	for _, d in container:GetDescendants() do
		if d:IsA("GuiButton") and selectable(d, container) then table.insert(list, d) end
	end
	table.sort(list, readingOrder)
	return list
end

-- Das oberste offene Fenster: sichtbares Kind der ScreenGui mit ZIndex >= 10 und mindestens einem Knopf
function GamepadNav.topWindow(screenGui: Instance): GuiObject?
	local best: GuiObject? = nil
	for _, child in screenGui:GetChildren() do
		if child:IsA("GuiObject") and child.Visible and child.ZIndex >= WINDOW_MIN_Z then
			if #GamepadNav.buttons(child) > 0 then
				if not best or child.ZIndex >= best.ZIndex then best = child end
			end
		end
	end
	return best
end

--------------------------------------------------------------------------------
-- Fokus
--------------------------------------------------------------------------------

function GamepadNav.selected(): GuiObject?
	return GuiService.SelectedObject
end

function GamepadNav.select(object: GuiObject?)
	GuiService.SelectedObject = object
end

-- Beim Oeffnen: erstes sinnvolles Element. Vorrang Hauptknopf nur, wenn es keine Tabs gibt.
function GamepadNav.focusFirst(container: Instance): GuiObject?
	local list = GamepadNav.buttons(container)
	local pick: GuiButton? = list[1]
	if pick then GuiService.SelectedObject = pick end
	return pick
end

function GamepadNav.primary(container: Instance): GuiButton?
	for _, button in GamepadNav.buttons(container) do
		if button:GetAttribute("HBBKind") == "primary" then return button end
	end
	return nil
end

-- Tabs: Knoepfe mit Namen "Tab_*", von links nach rechts
function GamepadNav.tabs(container: Instance): { GuiButton }
	local list: { GuiButton } = {}
	for _, button in GamepadNav.buttons(container) do
		if button.Name:sub(1, 4) == "Tab_" then table.insert(list, button) end
	end
	table.sort(list, function(a, b) return a.AbsolutePosition.X < b.AbsolutePosition.X end)
	return list
end

-- Fokus auf den Nachbar-Tab (dir = -1/+1). Gibt den neuen Tab zurueck.
function GamepadNav.stepTab(container: Instance, dir: number): GuiButton?
	local tabs = GamepadNav.tabs(container)
	if #tabs == 0 then return nil end
	local current = table.find(tabs :: { any }, GuiService.SelectedObject)
	local index = if current then ((current - 1 + dir) % #tabs) + 1 else (if dir > 0 then 1 else #tabs)
	GuiService.SelectedObject = tabs[index]
	return tabs[index]
end

-- Liste blaettern: groesste sichtbare ScrollingFrame um einen Anteil der Hoehe verschieben
function GamepadNav.scrollPage(container: Instance, dir: number): boolean
	local best: ScrollingFrame? = nil
	local bestArea = 0
	for _, d in container:GetDescendants() do
		if d:IsA("ScrollingFrame") and visibleChain(d, container.Parent or container) then
			local area = d.AbsoluteSize.X * d.AbsoluteSize.Y
			if area > bestArea then best, bestArea = d, area end
		end
	end
	if not best then return false end
	local step = best.AbsoluteWindowSize.Y * GamepadConfig.PAGE_FRACTION * dir
	local maxY = math.max(0, best.AbsoluteCanvasSize.Y - best.AbsoluteWindowSize.Y)
	best.CanvasPosition = Vector2.new(best.CanvasPosition.X, math.clamp(best.CanvasPosition.Y + step, 0, maxY))
	return true
end

--------------------------------------------------------------------------------
-- Tastensymbol im Knopf
--------------------------------------------------------------------------------

function GamepadNav.addGlyph(button: GuiObject, text: string)
	local existing = button:FindFirstChild(GLYPH_NAME)
	if existing and existing:IsA("TextLabel") then
		existing.Text = text
		existing.Visible = true
		return
	end
	local label = Instance.new("TextLabel")
	label.Name = GLYPH_NAME
	label.AnchorPoint = Vector2.new(0, 0)
	label.Position = UDim2.fromOffset(4, 4)
	label.Size = UDim2.fromOffset(34, 26)
	label.BackgroundColor3 = Color3.fromRGB(24, 20, 38)
	label.BackgroundTransparency = 0.15
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.Text = text
	label.ZIndex = button.ZIndex + 20
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
	label.Parent = button
end

function GamepadNav.removeGlyph(button: GuiObject)
	local existing = button:FindFirstChild(GLYPH_NAME)
	if existing then existing:Destroy() end
end

return GamepadNav
