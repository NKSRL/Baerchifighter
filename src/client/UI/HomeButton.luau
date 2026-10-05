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
	button.Position    = UDim2.new(0, 16, 1, -16)
	button.Size        = UDim2.fromOffset(SIZE.X, SIZE.Y)
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
