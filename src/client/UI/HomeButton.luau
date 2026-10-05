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

local Theme = require(script.Parent.Theme)

local HomeButton = {}

local SHOW_DISTANCE = 60
local CHECK_SECONDS = 0.5
local SIZE = 64

function HomeButton.init(screenGui: ScreenGui)
	local button = Theme.bigButton("HomeButton", screenGui, "🏠", Theme.COLORS.good)
	button.AnchorPoint = Vector2.new(0, 1)
	button.Position    = UDim2.new(0, 16, 1, -16)
	button.Size        = UDim2.fromOffset(SIZE, SIZE)
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
