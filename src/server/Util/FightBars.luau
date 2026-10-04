--!strict
-- FightBars.luau
-- ServerScriptService/Util/FightBars.luau
--
-- Einzige Zustaendigkeit:
--   - HP-Balken und Ladeleiste ueber einer kaempfenden Figur anzeigen und
--     animieren
--
-- Reine Optik fuer PitArenaService. Die Balken sind BillboardGuis an der
-- Figur selbst: so sieht sie jeder Zuschauer in der Naehe der Arena, nicht nur
-- der Besitzer.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local MapConfig   = require(ReplicatedStorage.Config.MapConfig)
local BaerchiMesh = require(ReplicatedStorage.Modules.BaerchiMesh)

local FightBars = {}

-- HP-Balken ueber einer Figur. Gibt die Fuell-Flaeche zurueck, damit der
-- Aufrufer sie animieren kann.
function FightBars.attachHealthBar(model: Model, fillColor: Color3): Frame?
	local anchor = (model:FindFirstChild("head", true) :: BasePart?) or model.PrimaryPart
	if not anchor then return nil end

	local billboard = Instance.new("BillboardGui")
	billboard.Name        = "FightBar"
	billboard.Size        = UDim2.fromScale(MapConfig.FIGHT_BAR_WIDTH, MapConfig.FIGHT_BAR_HEIGHT)
	billboard.StudsOffset = Vector3.new(0, BaerchiMesh.getHeight(model) * 0.55 + 2.2, 0)
	billboard.AlwaysOnTop = true
	-- Ohne Reichweiten-Grenze waeren die Balken ueber ALLEN acht Arenen quer
	-- ueber die Karte zu sehen — und wegen AlwaysOnTop auch noch durch die
	-- Landschaft hindurch.
	billboard.MaxDistance = MapConfig.FIGHT_BAR_DISTANCE
	billboard.Adornee     = anchor
	billboard.Parent      = anchor

	local back = Instance.new("Frame")
	back.Name              = "Back"
	back.Size              = UDim2.fromScale(1, 1)
	back.BackgroundColor3  = MapConfig.FIGHT_BAR_BACK_COLOR
	back.BorderSizePixel   = 0
	back.Parent            = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.4, 0)
	corner.Parent       = back

	local fill = Instance.new("Frame")
	fill.Name              = "Fill"
	fill.Size              = UDim2.fromScale(1, 1)
	fill.BackgroundColor3  = fillColor
	fill.BorderSizePixel   = 0
	fill.Parent            = back

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.4, 0)
	fillCorner.Parent       = fill

	return fill
end

function FightBars.removeHealthBar(model: Model)
	local bar = model:FindFirstChild("FightBar", true)
	if bar then
		bar:Destroy()
	end
	local charge = model:FindFirstChild("ChargeBar", true)
	if charge then
		charge:Destroy()
	end
end

-- Ladeleiste der Faehigkeit, direkt unter dem HP-Balken. Gibt die
-- Fuell-Flaeche zurueck (Breite = Ladestand).
function FightBars.attachChargeBar(model: Model): Frame?
	local anchor = (model:FindFirstChild("head", true) :: BasePart?) or model.PrimaryPart
	if not anchor then return nil end

	local below = (MapConfig.FIGHT_BAR_HEIGHT + MapConfig.FIGHT_CHARGE_BAR_HEIGHT) * 0.5 + 0.08

	local billboard = Instance.new("BillboardGui")
	billboard.Name        = "ChargeBar"
	billboard.Size        = UDim2.fromScale(MapConfig.FIGHT_BAR_WIDTH, MapConfig.FIGHT_CHARGE_BAR_HEIGHT)
	billboard.StudsOffset = Vector3.new(0, BaerchiMesh.getHeight(model) * 0.55 + 2.2 - below, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = MapConfig.FIGHT_BAR_DISTANCE
	billboard.Adornee     = anchor
	billboard.Parent      = anchor

	local back = Instance.new("Frame")
	back.Name             = "Back"
	back.Size             = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = MapConfig.FIGHT_BAR_BACK_COLOR
	back.BorderSizePixel  = 0
	back.Parent           = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent       = back

	local fill = Instance.new("Frame")
	fill.Name             = "Fill"
	fill.Size             = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = MapConfig.FIGHT_CHARGE_COLOR
	fill.BorderSizePixel  = 0
	fill.Parent           = back

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent       = fill

	return fill
end

-- Ladeleiste setzen: voll = gold, sonst blau.
function FightBars.setCharge(fill: Frame?, ratio: number, seconds: number)
	if not fill then return end
	local r = math.clamp(ratio, 0, 1)
	fill.BackgroundColor3 = if r >= 0.999 then MapConfig.FIGHT_CHARGE_FULL_COLOR else MapConfig.FIGHT_CHARGE_COLOR
	TweenService:Create(
		fill,
		TweenInfo.new(math.max(seconds, 0.05), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromScale(r, 1) }
	):Play()
end

function FightBars.tweenFill(fill: Frame?, ratio: number, seconds: number)
	if not fill then return end

	local goal = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
	local info = TweenInfo.new(math.max(seconds, 0.05), Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	TweenService:Create(fill, info, { Size = goal }):Play()
end

return FightBars
