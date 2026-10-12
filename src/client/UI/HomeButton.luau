--!strict
-- HomeButton.luau
-- StarterPlayerScripts/UI/HomeButton.luau
--
-- Einzige Zustaendigkeit:
--   - Den Heim-Knopf zeigen, wenn der Spieler weit weg von seinem Plot ist,
--     und RequestGoHome senden
--
-- Kontext: HBB Paket 5 (MAP_V2_HOME). Der Knopf erscheint erst ab
-- SHOW_DISTANCE Studs Abstand zum eigenen Spawn-Pad (Player.RespawnLocation,
-- von PlotBuilder gesetzt). Ob der Teleport erlaubt ist (getragene Waben),
-- entscheidet der Server.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes      = require(ReplicatedStorage.Network.Remotes)
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)
local Loc          = require(ReplicatedStorage.Localization.Loc)

local Theme = require(script.Parent.Theme)
local TouchSafeArea = require(script.Parent.TouchSafeArea)

local HomeButton = {}

local SHOW_DISTANCE = 60
local CHECK_SECONDS = 0.5
-- Breiter als hoch: das Wort ("Maison") braucht Platz
local SIZE = Vector2.new(104, 56)

function HomeButton.init(screenGui: ScreenGui)
	-- Playtest 05.10.: Wort statt Haus-Emoji (das Emoji war winzig und unklar)
	local button = Theme.bigButton("HomeButton", screenGui, Loc.t("ui.home.button"), Theme.COLORS.good)
	Loc.bind(button, "ui.home.button")
	button.AnchorPoint = Vector2.new(0, 1)
	button.Size        = UDim2.fromOffset(SIZE.X, SIZE.Y)

	-- Am PC unten links. Auf Touch-Geraeten liegt dort der Bewegungs-Stick
	-- (Playtest 07.10.) — dann im freien Streifen (TouchSafeArea) ueber der
	-- Pet-Leiste. Die Leiste wird erst nach diesem Knopf gebaut (Main),
	-- deshalb wird sie hier gesucht statt vorausgesetzt.
	local function barHeight(): number
		local bar = screenGui:FindFirstChild("PetBar")
		if not (bar and bar:IsA("GuiObject")) then return 68 end
		local barScale = bar:FindFirstChildOfClass("UIScale")
		return bar.Size.Y.Offset * (if barScale then barScale.Scale else 1)
	end
	local function place()
		local zone = TouchSafeArea.zone(screenGui)
		if zone then
			button.Position = UDim2.new(0, zone.left, 1, -(14 + barHeight() + 10))
		else
			button.Position = UDim2.new(0, 16, 1, -16)
		end
	end
	TouchSafeArea.watch(screenGui, place)
	local function hookBar(child: Instance)
		if child.Name ~= "PetBar" then return end
		local barScale = child:FindFirstChildOfClass("UIScale")
		if barScale then barScale:GetPropertyChangedSignal("Scale"):Connect(place) end
		place()
	end
	screenGui.ChildAdded:Connect(function(child)
		-- Der UIScale der Leiste kommt direkt nach ihr; einen Frame warten
		task.defer(hookBar, child)
	end)
	local existing = screenGui:FindFirstChild("PetBar")
	if existing then hookBar(existing) end
	button.Visible     = false
	button.ZIndex      = 5
	button.Activated:Connect(function()
		Remotes.RequestGoHome:FireServer()
	end)

	task.spawn(function()
		local player = Players.LocalPlayer
		while true do
			task.wait(CHECK_SECONDS)
			local show = false
			if FeatureFlags.isOn("MAP_V2_HOME") then
				local spawn = player.RespawnLocation
				local character = player.Character
				local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
				if spawn and root and root:IsA("BasePart") then
					show = (root.Position - spawn.Position).Magnitude > SHOW_DISTANCE
				end
			end
			button.Visible = show
		end
	end)
end

return HomeButton
