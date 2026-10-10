--!strict
-- ArrivalController.luau
-- StarterPlayerScripts/Controllers/ArrivalController.luau
--
-- Einzige Zustaendigkeit:
--   - Die Ankunft beim ERSTEN Betreten des Servers (Paket C, "Welt
--     aufwerten"): Honigblasen steigen um den Spieler auf, ein kleiner
--     Bienenschwarm kreist einmal gruessend um ihn und fliegt dann los —
--     dorthin, wo er als Naechstes hin soll
--
-- Ziel der Bienen: Der Spieler spawnt seit dem Insel-Spawn auf SEINER Insel
-- (MapConfig.PLAYER_SPAWN_OFFSET). Steht er dort, zeigen die Bienen zum
-- Honigmast (Herz der Welt, Event, Haendler). Steht er woanders (voller
-- Server → Not-Spawn in der Mitte), zeigen sie zur eigenen Insel.
--
-- Nur fuer diesen einen Spieler sichtbar (alles lokal), einmal pro Beitritt:
-- ein Respawn loest nichts aus (dieses Skript laeuft einmal je Beitritt).
--
-- PERFORMANCE: ein Emitter (Blasen, einmal Emit), sechs kleine Bienen aus
-- einem festen Pool, ein Takt nur waehrend der ~6 Sekunden der Ankunft.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local MapConfig     = require(ReplicatedStorage.Config.MapConfig)
local WorldFXConfig = require(ReplicatedStorage.Config.WorldFXConfig)
local FeatureFlags  = require(ReplicatedStorage.Config.FeatureFlags)
local MapLayout     = require(ReplicatedStorage.Modules.MapLayout)

local WorldFXKit = require(script.Parent.WorldFXKit)

local ArrivalController = {}

local localPlayer = Players.LocalPlayer
local TAU = math.pi * 2

local _bees: { Model } = {}
local _bubbleAnchor: BasePart? = nil
local _bubbles: ParticleEmitter? = nil
local _running = false

--------------------------------------------------------------------------------
-- Pool
--------------------------------------------------------------------------------

local function buildPool(folder: Instance)
	local cfg = WorldFXConfig.ARRIVAL
	for _ = 1, cfg.BEES do
		local model = Instance.new("Model")
		model.Name = "Bee"
		local body = WorldFXKit.ellipsoid("Body", model, Vector3.new(0.5, 0.5, 0.75), CFrame.new(), cfg.BEE_COLOR,
			Enum.Material.SmoothPlastic)
		WorldFXKit.part("Stripe", model, Vector3.new(0.52, 0.16, 0.22), CFrame.new(0, 0, 0.08), cfg.STRIPE_COLOR, Enum.Material.SmoothPlastic)
		local wings = WorldFXKit.part("Wings", model, Vector3.new(0.9, 0.05, 0.3), CFrame.new(0, 0.27, -0.02), Color3.new(1, 1, 1),
			Enum.Material.SmoothPlastic)
		wings.Transparency = 0.45
		model.PrimaryPart = body
		table.insert(_bees, model)
	end

	local anchor = WorldFXKit.anchor("BubbleAnchor", folder, Vector3.new(4, 0.5, 4), Vector3.new(0, -200, 0))
	local emitter = Instance.new("ParticleEmitter")
	if WorldFXKit.applyParticleTexture(emitter, "honey_bubble") then
		emitter.Rate = 0
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 214, 110))
		emitter.LightEmission = 0.3
		emitter.Lifetime = NumberRange.new(2.2, 3.2)
		emitter.Speed = NumberRange.new(2.5, 4.5)
		emitter.SpreadAngle = Vector2.new(20, 20)
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.Acceleration = Vector3.new(0, 0.6, 0)
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.3, 0.7), NumberSequenceKeypoint.new(1, 0.9),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.8, 0.3), NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Parent = anchor
		_bubbles = emitter
	else
		emitter:Destroy()
	end
	_bubbleAnchor = anchor
end

--------------------------------------------------------------------------------
-- Ziel
--------------------------------------------------------------------------------

local function ownPlotSlot(): number?
	for slot = 1, MapConfig.PLOT_COUNT do
		local plot = workspace:FindFirstChild("Plot_" .. slot)
		if plot and plot:GetAttribute("PlotOwner") == localPlayer.UserId then
			return slot
		end
	end
	return nil
end

local function target(from: Vector3): Vector3
	local mast = MapConfig.CENTER + Vector3.new(0, MapConfig.PLATFORM_TOP_Y + 20, 0)
	local slot = ownPlotSlot()
	if not slot then
		return mast
	end
	local home = MapLayout.plotCenter(slot)
	local flat = Vector3.new(from.X - home.X, 0, from.Z - home.Z)
	if flat.Magnitude <= MapConfig.PLOT_ISLAND_RADIUS then
		return mast
	end
	return home + Vector3.new(0, 8, 0)
end

--------------------------------------------------------------------------------
-- Ablauf
--------------------------------------------------------------------------------

local function play(root: BasePart, folder: Instance)
	if _running then return end
	_running = true
	local cfg = WorldFXConfig.ARRIVAL

	local anchor = _bubbleAnchor
	local bubbles = _bubbles
	if anchor and bubbles then
		anchor.Position = root.Position - Vector3.new(0, 2.6, 0)
		bubbles:Emit(cfg.BUBBLES)
	end

	local goal = target(root.Position)
	local start = os.clock()
	local leaveFrom: { Vector3 } = {}
	for _, bee in _bees do
		bee.Parent = folder
	end

	local connection: RBXScriptConnection? = nil
	connection = RunService.Heartbeat:Connect(function()
		local t = os.clock() - start
		local center = if root.Parent then root.Position + Vector3.new(0, 1.5, 0) else goal
		for i, bee in _bees do
			local offset = i / #_bees * TAU
			local pos: Vector3
			local ahead: Vector3
			if t < cfg.CIRCLE_TIME then
				-- einmal gruessend rundherum, leicht auf und ab
				local a = t / cfg.CIRCLE_TIME * TAU + offset
				pos = center + Vector3.new(math.cos(a) * cfg.CIRCLE_RADIUS, math.sin(t * 4 + i) * 0.8, math.sin(a) * cfg.CIRCLE_RADIUS)
				ahead = Vector3.new(-math.sin(a), 0, math.cos(a))
				leaveFrom[i] = pos
			else
				-- dann gemeinsam zum Ziel, leicht versetzt, im Bogen
				local k = math.clamp((t - cfg.CIRCLE_TIME - i * 0.08) / cfg.FLY_TIME, 0, 1)
				local from = leaveFrom[i] or center
				local eased = k * k * (3 - 2 * k)
				pos = from:Lerp(goal, eased) + Vector3.new(0, math.sin(k * math.pi) * 6, 0)
					+ Vector3.new(math.cos(offset), 0, math.sin(offset)) * (1.5 * (1 - k))
				ahead = (goal - from)
				ahead = Vector3.new(ahead.X, 0, ahead.Z)
				ahead = if ahead.Magnitude > 1e-3 then ahead.Unit else Vector3.new(0, 0, -1)
			end
			bee:PivotTo(CFrame.lookAt(pos, pos + ahead))
		end
		if t > cfg.CIRCLE_TIME + cfg.FLY_TIME + 0.6 then
			for _, bee in _bees do
				bee.Parent = nil
			end
			_running = false
			local c = connection
			if c then c:Disconnect() end
		end
	end)
end

function ArrivalController.init()
	if not FeatureFlags.isOn("WORLD_C_HUB") then return end
	if not WorldFXKit.enabled("arrival") then return end
	local folder = WorldFXKit.folder("Arrival", WorldFXKit.root())
	buildPool(folder)

	local function playFor(character: Model)
		local root = character:WaitForChild("HumanoidRootPart", 10)
		if root and root:IsA("BasePart") then
			-- kurz warten: Insel und Plot sind beim ersten Spawn noch im Aufbau
			task.wait(1.2)
			play(root, folder)
		end
	end

	-- Nur der ERSTE Charakter dieses Beitritts
	local character = localPlayer.Character
	if character then
		task.spawn(playFor, character)
	else
		local first: RBXScriptConnection? = nil
		first = localPlayer.CharacterAdded:Connect(function(c)
			local conn = first
			if conn then conn:Disconnect() end
			playFor(c)
		end)
	end

	-- Debug (Studio): Ankunft erneut abspielen
	WorldFXKit.onDebug("DebugArrival", function()
		local c = localPlayer.Character
		local root = c and c:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			play(root, folder)
		end
	end, false)
end

return ArrivalController
