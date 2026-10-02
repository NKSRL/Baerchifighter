--!strict
-- Hud.luau
-- StarterPlayerScripts/UI/Hud.luau
--
-- Einzige Zustaendigkeit:
--   - Dauerhaft sichtbare Kopfzeile: Waehrungen, Rang, Rebirth-Multiplikator
--
-- Liest ausschliesslich aus ClientState und reagiert auf dessen onChanged —
-- die Anzeige rechnet nie selbst etwas hoch.
--
-- Die Rebirth-Pille rechts oben ist gleichzeitig der Knopf fuer den
-- Rebirth-Dialog: der Multiplikator ist genau die Zahl die ein Rebirth
-- erhoeht, also gehoert der Weg dorthin an dieselbe Stelle.
--
-- Die Y-Positionen der beiden Spalten sind bewusst Pixel-Offsets und keine
-- Scale-Werte: die MenuBar haengt direkt darunter und wuerde sonst je nach
-- Bildschirmhoehe in die Pillen rutschen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Network.Types)

local Theme        = require(script.Parent.Theme)
local PanelManager = require(script.Parent.PanelManager)
local ClientState  = require(script.Parent.Parent.Controllers.ClientState)

local Hud = {}

-- Merker auf die Labels, damit refresh() nicht jedes Mal suchen muss
local _gummyLabel: TextLabel?     = nil
local _goldLabel: TextLabel?      = nil
local _rankLabel: TextLabel?      = nil
local _multLabel: TextLabel?      = nil

--------------------------------------------------------------------------------
-- Bausteine
--------------------------------------------------------------------------------

-- Eine "Pille": farbiger Kreis mit Symbol links, Wert rechts.
-- Gibt Wert-Label UND Pille zurueck — manche Pillen sind anklickbar.
local function makePill(parent: Instance, order: number, icon: string, iconColor: Color3): (TextLabel, Frame)
	local pill = Theme.panel("Pill", parent, Theme.COLORS.panel)
	pill.Size        = UDim2.new(1, 0, 0, 38)
	pill.LayoutOrder = order

	local badge = Instance.new("Frame")
	badge.Name             = "Badge"
	badge.Size             = UDim2.new(0, 26, 0, 26)
	badge.Position         = UDim2.new(0, 6, 0.5, -13)
	badge.BackgroundColor3  = iconColor
	badge.BorderSizePixel   = 0
	badge.Parent            = pill
	Theme.corner(badge, 13)
	Theme.stroke(badge, Theme.COLORS.outline, 2)

	local iconLabel = Theme.label("Icon", badge, icon)
	iconLabel.Size          = UDim2.fromScale(1, 1)
	iconLabel.TextXAlignment = Enum.TextXAlignment.Center
	iconLabel.TextColor3     = Theme.COLORS.outline

	local value = Theme.label("Value", pill, "0")
	value.Position = UDim2.new(0, 38, 0, 4)
	value.Size     = UDim2.new(1, -44, 1, -8)

	return value, pill
end

--------------------------------------------------------------------------------
-- Aktualisieren
--------------------------------------------------------------------------------

local function refresh(data: Types.PlayerDataUpdate)
	if _gummyLabel then
		_gummyLabel.Text = Theme.formatNumber(data.gummies)
	end
	if _goldLabel then
		_goldLabel.Text = Theme.formatNumber(data.goldGummies)
	end
	if _rankLabel then
		_rankLabel.Text = data.rank.name
	end
	if _multLabel then
		_multLabel.Text = string.format("x%.2f  (%d)", data.rebirthMult, data.rebirthCount)
	end
end

--------------------------------------------------------------------------------
-- Initialisierung
--------------------------------------------------------------------------------

function Hud.init(screenGui: ScreenGui)
	-- Links oben: Waehrungen
	local left = Theme.container("HudLeft", screenGui)
	left.AnchorPoint = Vector2.new(0, 0)
	left.Position    = UDim2.new(0.012, 0, 0, 12)
	left.Size        = UDim2.new(0.21, 0, 0, 82)

	local leftConstraint = Instance.new("UISizeConstraint")
	leftConstraint.MinSize = Vector2.new(150, 0)
	leftConstraint.MaxSize = Vector2.new(260, math.huge)
	leftConstraint.Parent  = left

	local leftLayout = Theme.listLayout(left, 6)
	leftLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left

	_gummyLabel = makePill(left, 1, "G", Theme.COLORS.gummy)
	_goldLabel  = makePill(left, 2, "$", Theme.COLORS.goldGummy)

	-- Rechts oben: Rang und Rebirth
	local right = Theme.container("HudRight", screenGui)
	right.AnchorPoint = Vector2.new(1, 0)
	right.Position    = UDim2.new(0.988, 0, 0, 12)
	right.Size        = UDim2.new(0.24, 0, 0, 82)

	local rightConstraint = Instance.new("UISizeConstraint")
	rightConstraint.MinSize = Vector2.new(160, 0)
	rightConstraint.MaxSize = Vector2.new(280, math.huge)
	rightConstraint.Parent  = right

	local rightLayout = Theme.listLayout(right, 6)
	rightLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right

	_rankLabel = makePill(right, 1, "R", Theme.COLORS.accent)

	local multLabel, multPill = makePill(right, 2, "*", Theme.COLORS.good)
	_multLabel = multLabel

	-- Die Pille selbst ist der Rebirth-Knopf. Ein durchsichtiger Button
	-- darueber, damit der Aufbau der Pille unveraendert bleibt.
	local rebirthHit = Instance.new("TextButton")
	rebirthHit.Name                   = "RebirthHit"
	rebirthHit.BackgroundTransparency = 1
	rebirthHit.Text                   = ""
	rebirthHit.Size                   = UDim2.fromScale(1, 1)
	rebirthHit.ZIndex                 = 3
	rebirthHit.Parent                 = multPill

	rebirthHit.Activated:Connect(function()
		PanelManager.toggle("Rebirth")
	end)

	-- Sofort mit dem aktuellen Stand fuellen, danach bei jeder Aenderung
	ClientState.onChanged(refresh)

	print("[Hud] Initialisiert")
end

return Hud
