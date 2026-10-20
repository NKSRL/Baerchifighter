--!strict
-- CharmIcon.luau
-- StarterPlayerScripts/UI/CharmIcon.luau
--
-- Zeigt das Bild einer Charm-Rarity (CharmConfig.RARITY_ICON) auf einer
-- Kachel. Gibt es fuer die Rarity kein Bild (leere ID), tut die Funktion
-- nichts und liefert false: der Aufrufer behaelt dann Farbflaeche + Buchstabe.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CharmConfig       = require(ReplicatedStorage.Config.CharmConfig)

local CharmIcon = {}

local ICON_NAME = "CharmIcon"

-- host:   Kachel, auf die das Bild gelegt wird (Kind, mittig)
-- rarity: Rarity des Charms oder nil (dann wird das Bild versteckt)
-- size:   Groesse relativ zur Kachel
-- z:      ZIndex des Bildes
function CharmIcon.set(host: GuiObject, rarity: string?, size: UDim2, z: number): boolean
	local existing = host:FindFirstChild(ICON_NAME)
	local image    = if existing and existing:IsA("ImageLabel") then existing else nil

	local icons = CharmConfig.RARITY_ICON :: { [string]: string }
	local id    = if rarity then icons[rarity] else nil

	if not id or id == "" then
		if image then image.Visible = false end
		return false
	end

	if not image then
		local created = Instance.new("ImageLabel")
		created.Name                   = ICON_NAME
		created.BackgroundTransparency = 1
		created.AnchorPoint            = Vector2.new(0.5, 0.5)
		created.Position               = UDim2.fromScale(0.5, 0.5)
		created.ScaleType              = Enum.ScaleType.Fit
		created.Active                 = false
		created.Parent                 = host
		image = created
	end

	local shown = image :: ImageLabel
	shown.Size    = size
	shown.ZIndex  = z
	shown.Image   = id
	shown.Visible = true
	return true
end

return CharmIcon
