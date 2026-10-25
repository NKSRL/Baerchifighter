--!strict
-- Welt2Controller.luau
-- StarterPlayerScripts/Controllers/Welt2Controller.luau
--
-- Einzige Zustaendigkeit (Welt 2, 21.10.): am EIGENEN Plot die Fusionsmaschine
-- (Model "World2Fusion", gebaut von Welt2Builder) bedienbar machen: ein Prompt
-- "Fusionieren" oeffnet das Baerchi-Inventar, wo zwei Baerchis fusioniert werden
-- (Logik: FusionService, Panel: FusionPanel/BaerchiInventory). Nur ein Prompt, kein Neubau.

local Players           = game:GetService("Players")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loc          = require(ReplicatedStorage.Localization.Loc)
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)

local UI           = script.Parent.Parent:WaitForChild("UI")
local PanelManager = require(UI:WaitForChild("PanelManager"))

local Welt2Controller = {}

local MODEL_NAME = "World2Fusion"
local ANCHOR     = "Fusion_Kern"
local PROMPT     = "FusionPrompt"

local function isOwn(model: Model): boolean
	local plot = model.Parent
	return plot ~= nil and plot:GetAttribute("PlotOwner") == Players.LocalPlayer.UserId
end

local function hook(instance: Instance)
	if not instance:IsA("Model") or instance.Name ~= MODEL_NAME then return end
	task.defer(function()
		if not instance.Parent or not isOwn(instance :: Model) then return end
		local core = instance:FindFirstChild(ANCHOR) or instance:WaitForChild(ANCHOR, 5)
		if not core or not core:IsA("BasePart") or core:FindFirstChild(PROMPT) then return end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = PROMPT
		prompt.ActionText = Loc.t("ui.fusion.fuse")
		prompt.ObjectText = ""
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 14
		prompt.RequiresLineOfSight = false
		prompt.Parent = core
		prompt.Triggered:Connect(function()
			PanelManager.open("Inventory")
		end)
		Loc.onChanged(function()
			prompt.ActionText = Loc.t("ui.fusion.fuse")
		end)
	end)
end

function Welt2Controller.init()
	if not FeatureFlags.isOn("WELT2_LOOK") then return end
	for _, descendant in Workspace:GetDescendants() do
		hook(descendant)
	end
	Workspace.DescendantAdded:Connect(hook)
	print("[Welt2Controller] Initialisiert")
end

return Welt2Controller
