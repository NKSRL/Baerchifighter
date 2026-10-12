--!strict
-- TowerFlightController.luau
-- StarterPlayerScripts/Controllers/TowerFlightController.luau
--
-- Einzige Zustaendigkeit:
--   - 12.10. (Playtest "man kann den Turm nicht hochfliegen"): ein Flugfeld
--     am Rand der EIGENEN Arena. Steht der Kampf-Turm (Server-Attribut
--     PitPlatform.TowerTopY / TowerLevel, geschrieben von
--     MapService.setPitTowerLevel), fliegt der eigene Charakter beim
--     Betreten im Bogen auf die Turm-Spitze und sieht dem Kampf von oben zu.
--
-- Warum auf dem Client: die Spielfigur gehoert physikalisch dem Client
-- (Network Ownership). Eine Geschwindigkeit vom Server wuerde sofort vom
-- Client ueberschrieben. Das Feld selbst ist reine Optik (lokales Teil), der
-- Server baut nichts neu und kein Spielstand haengt daran.
--
-- Die Flugbahn: senkrechte Startgeschwindigkeit so, dass der Scheitel
-- APEX_EXTRA ueber der Spitze liegt; waagerecht so, dass der Charakter im
-- Scheitel ueber dem Landepunkt ist und von dort auf die Spitze faellt.

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace  = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldFXConfig = require(ReplicatedStorage.Config.WorldFXConfig)
local MapLayout     = require(ReplicatedStorage.Modules.MapLayout)

local WorldFXKit = require(script.Parent.WorldFXKit)

local TowerFlightController = {}

local CFG = WorldFXConfig.TOWER_FLIGHT
local localPlayer = Players.LocalPlayer

local _slot: number? = nil
local _pad: BasePart? = nil
local _ring: BasePart? = nil
local _lastLaunch = 0

-- Punkt in Arena-Koordinaten (along = nach aussen, across = quer) auf Hoehe y
local function arenaPoint(slot: number, along: number, across: number, y: number): Vector3
	local center = MapLayout.pitCenter(slot)
	local p = center + MapLayout.outward(slot) * along + MapLayout.side(slot) * across
	return Vector3.new(p.X, y, p.Z)
end

local function ownSlot(): number?
	for _, child in Workspace:GetChildren() do
		local slot = tonumber(string.match(child.Name, "^Plot_(%d+)$"))
		if slot and child:GetAttribute("PlotOwner") == localPlayer.UserId then
			return slot
		end
	end
	return nil
end

local function platform(slot: number): Instance?
	local plot = Workspace:FindFirstChild("Plot_" .. slot)
	return if plot then plot:FindFirstChild("PitPlatform") else nil
end

local function towerTop(slot: number): (number, number)
	local container = platform(slot)
	if not container then return 0, 0 end
	local level = container:GetAttribute("TowerLevel")
	local top = container:GetAttribute("TowerTopY")
	return (if typeof(level) == "number" then level else 0), (if typeof(top) == "number" then top else 0)
end

local function buildPad(slot: number)
	local old = _pad
	if old then old:Destroy() end
	local oldRing = _ring
	if oldRing then oldRing:Destroy() end
	local folder = WorldFXKit.folder("TowerFlight", WorldFXKit.root())
	local base = arenaPoint(slot, CFG.PAD_ALONG, CFG.PAD_ACROSS, MapLayout.pitCenter(slot).Y)
	-- flache Scheibe knapp ueber dem Sockelrand (der liegt 0.35 tiefer als die Mitte)
	local pad = WorldFXKit.part("FlightPad", folder, Vector3.new(0.2, CFG.PAD_RADIUS * 2, CFG.PAD_RADIUS * 2),
		CFrame.new(base + Vector3.new(0, -0.25, 0)) * WorldFXKit.UPRIGHT, CFG.COLOR_OFF, Enum.Material.Neon, Enum.PartType.Cylinder)
	pad.Transparency = 0.25
	local ring = WorldFXKit.part("FlightRing", folder, Vector3.new(0.1, CFG.PAD_RADIUS * 2.6, CFG.PAD_RADIUS * 2.6),
		CFrame.new(base + Vector3.new(0, -0.3, 0)) * WorldFXKit.UPRIGHT, CFG.COLOR_OFF, Enum.Material.Neon, Enum.PartType.Cylinder)
	ring.Transparency = 0.6
	_pad, _ring = pad, ring
	WorldFXKit.cullGroup(folder, base, CFG.SHOW_DISTANCE)
end

local function launch(root: BasePart, slot: number, topY: number)
	local gravity = Workspace.Gravity
	local start = root.Position
	-- Hoehe der Huefte ueber dem Fuss etwa 3 Studs: Ziel = Spitze + 3
	local landing = arenaPoint(slot, CFG.LAND_ALONG, CFG.LAND_ACROSS, topY + 3)
	local apexY = math.max(landing.Y, start.Y) + CFG.APEX_EXTRA
	local rise = math.max(1, apexY - start.Y)
	local vy = math.sqrt(2 * gravity * rise)
	local tApex = vy / gravity
	local flat = Vector3.new(landing.X - start.X, 0, landing.Z - start.Z)
	local vxz = flat / tApex
	root.AssemblyLinearVelocity = Vector3.new(vxz.X, vy, vxz.Z)
	-- Im Scheitel die Waagerechte abbremsen, sonst rutscht er ueber die Kante
	task.delay(tApex, function()
		if root.Parent then
			local v = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(0, math.min(v.Y, 0), 0)
		end
	end)
end

local function step()
	local slot = _slot
	local pad = _pad
	if not slot or not pad then return end
	local level, topY = towerTop(slot)
	local active = level >= CFG.MIN_LEVEL
	local color = if active then CFG.COLOR_ON else CFG.COLOR_OFF
	if pad.Color ~= color then
		pad.Color = color
		local ring = _ring
		if ring then ring.Color = color end
	end
	local ring = _ring
	if ring and active then
		ring.Transparency = 0.45 + math.sin(os.clock() * 5) * 0.2
	end
	if not active then return end

	local character = localPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not humanoid then return end
	if humanoid.FloorMaterial == Enum.Material.Air then return end
	if os.clock() - _lastLaunch < CFG.COOLDOWN then return end

	local p = pad.Position
	local d = Vector3.new(root.Position.X - p.X, 0, root.Position.Z - p.Z).Magnitude
	if d > CFG.PAD_RADIUS or math.abs(root.Position.Y - p.Y) > 6 then return end
	-- schon oben? (z. B. auf der Spitze gelandet und zurueckgelaufen)
	if root.Position.Y > topY + 1 then return end

	_lastLaunch = os.clock()
	humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
	launch(root, slot, topY)
end

local function refreshSlot()
	local slot = ownSlot()
	if slot == _slot then return end
	_slot = slot
	if slot then buildPad(slot) end
end

function TowerFlightController.init()
	if not WorldFXKit.enabled("towerFlight") then return end
	refreshSlot()
	Workspace.ChildAdded:Connect(function(child)
		if string.match(child.Name, "^Plot_%d+$") then task.defer(refreshSlot) end
	end)
	Workspace.ChildRemoved:Connect(function(child)
		if string.match(child.Name, "^Plot_%d+$") then task.defer(refreshSlot) end
	end)
	-- PlotOwner kommt evtl. nach dem Plot an
	task.delay(3, refreshSlot)
	RunService.Heartbeat:Connect(step)
	print("[TowerFlightController] Initialisiert")
end

return TowerFlightController
