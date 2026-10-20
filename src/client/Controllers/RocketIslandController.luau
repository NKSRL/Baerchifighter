--!strict
-- RocketIslandController.luau
-- StarterPlayerScripts/Controllers/RocketIslandController.luau
--
-- Einzige Zustaendigkeit:
--   - P4: Schild und Rakete der Raketen-Insel nach dem EIGENEN Spielstand anzeigen
--     (gesperrt / bereit / gestartet). Die Welt gibt es nur einmal, darum rechnet der
--     Client lokal: Text ueber das Loc-Attribut (WorldText), Rakete per LocalTransparencyModifier.
--   - Das Glimmen des Fensters (+-10 %, 3 s).
--
-- Keine Interaktion, keine Remotes. Zustand aus Modules/RocketIslandRules.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local Loc                = require(ReplicatedStorage.Localization.Loc)
local WorldText          = require(ReplicatedStorage.Localization.WorldText)
local FeatureFlags       = require(ReplicatedStorage.Config.FeatureFlags)
local RocketIslandConfig = require(ReplicatedStorage.Config.RocketIslandConfig)
local RocketIslandRules  = require(ReplicatedStorage.Modules.RocketIslandRules)
local ClientState        = require(script.Parent.ClientState)

local RocketIslandController = {}

local _root: Instance? = nil
local _debugState: number? = nil
local _glow: Tween? = nil
local _lastState = 0

local function findRoot(): Instance?
	if _root and _root.Parent then return _root end
	local platform = workspace:FindFirstChild("Platform")
	_root = if platform then platform:FindFirstChild(RocketIslandConfig.NAME_PREFIX .. "Root") else nil
	return _root
end

local function apply(view: any)
	local root = findRoot()
	if not root then return end
	local state = _debugState or RocketIslandRules.state(view)
	local T = RocketIslandConfig.TEXT

	local text = root:FindFirstChild("SignText", true)
	local progress = root:FindFirstChild("SignProgress", true)
	if text then
		local key = if state == 3 then T.launched elseif state == 2 then T.ready else T.locked
		WorldText.set(text, Loc.msg(key))   -- lokal gesetzt; WorldText.startClient loest die Sprache auf
	end
	if progress and progress:IsA("TextLabel") then
		progress.Visible = (state == 1)
		WorldText.set(progress, Loc.msg(T.progress, { stage = math.min(RocketIslandRules.finalRecord(view), 100), total = 100 }))
	end

	-- Rakete: im Zustand "gestartet" lokal ausblenden (Rampe bleibt leer)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("RocketPart") then
			d.LocalTransparencyModifier = if state == 3 then 1 else 0
		end
	end

	if state ~= _lastState then
		_lastState = state
		if _glow then _glow:Cancel(); _glow = nil end
		local window = root:FindFirstChild(RocketIslandConfig.NAME_PREFIX .. "RocketWindow", true)
		if window and window:IsA("BasePart") and state ~= 3 then
			local base = window.Color
			local k = 1 - RocketIslandConfig.GLOW_AMOUNT
			_glow = TweenService:Create(window, TweenInfo.new(RocketIslandConfig.GLOW_PERIOD * 0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Color = Color3.new(base.R * k, base.G * k, base.B * k) })
			;(_glow :: Tween):Play()
		end
	end
end

-- Debug (Server-Befehl rocketisland set n schickt n ueber Attribut am Workspace)
function RocketIslandController.init()
	if not FeatureFlags.isOn("ROCKET_ISLAND") then return end
	ClientState.onChanged(apply)
	workspace:GetAttributeChangedSignal("RocketIslandDebugState"):Connect(function()
		local v = workspace:GetAttribute("RocketIslandDebugState")
		_debugState = if typeof(v) == "number" and v >= 1 and v <= 3 then v else nil
		local current = ClientState.get()
		if current then apply(current) end
	end)
	-- die Plattform wird beim Welt-Aufbau repliziert: kurz nachfassen, sobald sie da ist
	task.spawn(function()
		for _ = 1, 20 do
			if findRoot() then break end
			task.wait(1)
		end
		local current = ClientState.get()
		if current then apply(current) end
	end)
end

return RocketIslandController
