--!strict
-- HubLandmarkController.luau
-- StarterPlayerScripts/Controllers/HubLandmarkController.luau
--
-- Einzige Zustaendigkeit:
--   - Die festen Wahrzeichen der Hauptinsel aufwerten (Paket C, "Welt
--     aufwerten"): Wabenkrone und Honigfaden am Honigmast, Wegweiser an den
--     Wegen, Laterne und Eierkorb am Haendler, Holzrahmen mit Krone an den
--     Tafeln und der Glanz auf Platz 1
--
-- Was auf Events reagiert (Pit-Rahmen, Wespen-Nest), steht in
-- HubEventController; die Ankunft in ArrivalController.
--
-- Alles nur auf dem Client (WorldFX_Local): kein Server-Teil, keine
-- Replikation, die Wegweiser in der Sprache des Betrachters. Positionen aus
-- MapLayout/MapConfig (Test: map_layout.test.lua), Zahlen aus WorldFXConfig.
--
-- PERFORMANCE: EIN Takt (20x pro Sekunde) fuer Tropfen und Glanz, nur wenn
-- die jeweilige Gruppe in Sichtweite ist (WorldFXKit.cullGroup). Wegweiser,
-- Haendler-Deko und Rahmen stehen still und kosten ausser Sichtweite nichts.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local MapConfig     = require(ReplicatedStorage.Config.MapConfig)
local EggConfig     = require(ReplicatedStorage.Config.EggConfig)
local WorldFXConfig = require(ReplicatedStorage.Config.WorldFXConfig)
local FeatureFlags  = require(ReplicatedStorage.Config.FeatureFlags)
local MapLayout     = require(ReplicatedStorage.Modules.MapLayout)
local Loc           = require(ReplicatedStorage.Localization.Loc)

local WorldFXKit         = require(script.Parent.WorldFXKit)
local DayCycleController = require(script.Parent.DayCycleController)

local HubLandmarkController = {}

local localPlayer = Players.LocalPlayer
local UPRIGHT = WorldFXKit.UPRIGHT
local TICK = 0.05

-- Mast-Fuss: Oberkante des Event-Pit-Podests (wie WorldBuilder.buildPlatform)
local MAST_FOOT = Vector3.new(
	MapConfig.CENTER.X,
	MapConfig.PLATFORM_TOP_Y + MapConfig.EVENT_PIT_GROUND_CLEARANCE + MapConfig.EVENT_PIT_FLOOR_HEIGHT,
	MapConfig.CENTER.Z
)

type Drip = { group: Instance, drop: BasePart, ring: BasePart, spout: Vector3, surfaceY: number, cycleStart: number }
local _drip: Drip? = nil

type Shine = { gradient: UIGradient, group: Instance }
local _shines: { Shine } = {}

type SignLabel = { label: TextLabel, slot: number }
local _islandLabels: { SignLabel } = {}

--------------------------------------------------------------------------------
-- Honigmast: Wabenkrone
--------------------------------------------------------------------------------

-- Ein Teil, dessen +X nach `outward` zeigt (Zylinder-Stirnseite nach aussen).
local function facing(position: Vector3, outward: Vector3): CFrame
	return CFrame.fromMatrix(position, outward, Vector3.yAxis)
end

local function buildCrown(folder: Instance)
	local cfg = WorldFXConfig.MAST
	local model = Instance.new("Model")
	model.Name = "MastCrown"
	local combId = WorldFXKit.textureId("amber_comb")

	for row = 0, 1 do
		local y = MAST_FOOT.Y + cfg.CROWN_HEIGHT + (row - 0.5) * cfg.CROWN_ROW_GAP
		for i = 0, cfg.CROWN_CELLS - 1 do
			-- zweite Reihe um eine halbe Zelle versetzt: wie echte Waben
			local angle = (i + row * 0.5) / cfg.CROWN_CELLS * math.pi * 2
			local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
			local p = Vector3.new(MAST_FOOT.X, y, MAST_FOOT.Z) + outward * cfg.CROWN_RADIUS
			local cell = WorldFXKit.part("Comb", model, Vector3.new(cfg.CELL_DEPTH, cfg.CELL_SIZE, cfg.CELL_SIZE),
				facing(p, outward), cfg.CELL_DAY, Enum.Material.Neon, Enum.PartType.Cylinder)
			if combId then
				local decal = Instance.new("Decal")
				decal.Texture = combId
				decal.Face = Enum.NormalId.Right
				decal.Parent = cell
			end
			DayCycleController.registerGlow(cell, cfg.CELL_DAY, cfg.CELL_NIGHT)
		end
	end
	model.Parent = folder
end

--------------------------------------------------------------------------------
-- Honigmast: Faden, Tuelle, Schale, Tropfen
--------------------------------------------------------------------------------

local function buildHoneyThread(folder: Instance)
	local cfg = WorldFXConfig.MAST
	local group = WorldFXKit.folder("HoneyThread", folder)
	local angle = math.rad(cfg.THREAD_ANGLE)
	local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))

	-- Faden am Mast herab
	local length = cfg.THREAD_TOP - cfg.THREAD_BOTTOM
	local threadBase = MAST_FOOT + dir * cfg.THREAD_RADIUS + Vector3.new(0, cfg.THREAD_BOTTOM, 0)
	local thread = WorldFXKit.pole("Thread", group, threadBase, length, cfg.THREAD_WIDTH, cfg.HONEY_COLOR, Enum.Material.Glass)
	thread.Transparency = 0.15

	-- Tuelle: waagerecht vom Mast bis ueber die Schale
	local reach = cfg.SPOUT_REACH - cfg.THREAD_RADIUS
	local spoutMid = MAST_FOOT + dir * (cfg.THREAD_RADIUS + reach * 0.5) + Vector3.new(0, cfg.THREAD_BOTTOM, 0)
	WorldFXKit.part("Spout", group, Vector3.new(reach, 0.45, 0.45), facing(spoutMid, dir),
		cfg.BOWL_COLOR, Enum.Material.Wood, Enum.PartType.Cylinder)

	-- Schale auf dem Podest, darin die Honig-Oberflaeche
	local bowlCenter = MAST_FOOT + dir * cfg.SPOUT_REACH
	WorldFXKit.part("Bowl", group, Vector3.new(cfg.BOWL_HEIGHT, cfg.BOWL_RADIUS * 2, cfg.BOWL_RADIUS * 2),
		CFrame.new(bowlCenter + Vector3.new(0, cfg.BOWL_HEIGHT * 0.5, 0)) * UPRIGHT,
		cfg.BOWL_COLOR, Enum.Material.Wood, Enum.PartType.Cylinder)
	local surfaceY = bowlCenter.Y + cfg.BOWL_HEIGHT + 0.02
	local honey = WorldFXKit.part("Honey", group, Vector3.new(0.08, cfg.BOWL_RADIUS * 1.7, cfg.BOWL_RADIUS * 1.7),
		CFrame.new(bowlCenter.X, surfaceY, bowlCenter.Z) * UPRIGHT, cfg.HONEY_COLOR, Enum.Material.Glass, Enum.PartType.Cylinder)
	honey.Reflectance = 0.2

	local drop = WorldFXKit.ball("Drop", nil, cfg.DROP_SIZE, bowlCenter, cfg.HONEY_COLOR, Enum.Material.Glass)
	local ring = WorldFXKit.part("Ring", nil, Vector3.new(0.04, 0.3, 0.3), CFrame.new(), Color3.fromRGB(255, 226, 150),
		Enum.Material.Neon, Enum.PartType.Cylinder)

	_drip = {
		group = group,
		drop = drop,
		ring = ring,
		spout = MAST_FOOT + dir * cfg.SPOUT_REACH + Vector3.new(0, cfg.THREAD_BOTTOM - 0.3, 0),
		surfaceY = surfaceY,
		cycleStart = os.clock(),
	}
	WorldFXKit.cullGroup(group, MAST_FOOT, cfg.SHOW_DISTANCE)
end

-- Ein Tropfen-Zyklus: an der Tuelle wachsen, fallen, Ring in der Schale.
local function stepDrip(now: number)
	local drip = _drip
	if not drip or not drip.group.Parent then return end
	local cfg = WorldFXConfig.MAST
	local t = (now - drip.cycleStart) % cfg.DROP_INTERVAL
	local fallHeight = drip.spout.Y - drip.surfaceY
	local fallTime = math.sqrt(2 * fallHeight / workspace.Gravity)

	if t < cfg.DROP_GROW then
		local k = t / cfg.DROP_GROW
		drip.drop.Size = Vector3.one * (cfg.DROP_SIZE * (0.3 + 0.7 * k))
		drip.drop.Position = drip.spout
		drip.drop.Parent = drip.group
	elseif t < cfg.DROP_GROW + fallTime then
		local f = t - cfg.DROP_GROW
		drip.drop.Position = drip.spout - Vector3.new(0, 0.5 * workspace.Gravity * f * f, 0)
	else
		drip.drop.Parent = nil
		local k = (t - cfg.DROP_GROW - fallTime) / cfg.RING_TIME
		if k < 1 then
			local size = 0.3 + cfg.BOWL_RADIUS * 1.4 * k
			drip.ring.Size = Vector3.new(0.04, size, size)
			drip.ring.CFrame = CFrame.new(drip.spout.X, drip.surfaceY + 0.05, drip.spout.Z) * UPRIGHT
			drip.ring.Transparency = 0.3 + 0.7 * k
			drip.ring.Parent = drip.group
		else
			drip.ring.Parent = nil
		end
	end
end

--------------------------------------------------------------------------------
-- Wegweiser
--------------------------------------------------------------------------------

-- Ein Schild in Baerchi-Form, das in Richtung `dir` zeigt. Text vorn und
-- hinten, je mit dem Pfeil auf der richtigen Seite (wer auf die Vorderseite
-- schaut, hat +X links).
local function buildBoard(parent: Instance, center: Vector3, dir: Vector3, color: Color3): (TextLabel, TextLabel)
	local cfg = WorldFXConfig.SIGNPOST
	local frame = CFrame.fromMatrix(center, dir, Vector3.yAxis)
	local board = WorldFXKit.part("Board", parent, cfg.BOARD_SIZE, frame, color, Enum.Material.Wood)
	local signId = WorldFXKit.textureId("bear_sign")
	if signId then
		-- Form aus dem Bild: Teil unsichtbar, Bild vorn und hinten
		board.Transparency = 1
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			local decal = Instance.new("Decal")
			decal.Texture = signId
			decal.Face = face
			decal.Color3 = color
			decal.Parent = board
		end
	else
		-- Ohren oben
		for _, side in { -1, 1 } do
			WorldFXKit.part("Ear", parent, Vector3.new(0.3, 0.75, 0.75),
				frame * CFrame.new(side * cfg.BOARD_SIZE.X * 0.3, cfg.BOARD_SIZE.Y * 0.5, 0) * CFrame.Angles(0, math.rad(90), 0),
				color, Enum.Material.Wood, Enum.PartType.Cylinder)
		end
	end

	local labels = {}
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.PixelsPerStud = 40
		gui.LightInfluence = 1
		gui.Parent = board
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(0.9, 0.8)
		label.Position = UDim2.fromScale(0.05, 0.1)
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.TextColor3 = cfg.TEXT_COLOR
		label.Parent = gui
		table.insert(labels, label)
	end
	return labels[1], labels[2]
end

-- Pfeil links (Vorderseite) bzw. rechts (Rueckseite) an den Text haengen.
local function arrowText(front: TextLabel, back: TextLabel, text: string)
	front.Text = "◀ " .. text
	back.Text  = text .. " ▶"
end

local function bindArrow(front: TextLabel, back: TextLabel, key: string, args: { [string]: any }?)
	local function refresh()
		arrowText(front, back, Loc.t(key, args))
	end
	refresh()
	Loc.onChanged(refresh)
end

-- Beschriftung "Insel von X" / "Deine Insel" / "Freie Insel" fuer Slot `slot`.
local function islandText(slot: number): (string, boolean)
	local plot = workspace:FindFirstChild("Plot_" .. slot)
	local ownerId = if plot then plot:GetAttribute("PlotOwner") else nil
	if typeof(ownerId) ~= "number" then
		return Loc.t("world.sign.free"), false
	end
	if ownerId == localPlayer.UserId then
		return Loc.t("world.sign.home"), true
	end
	local owner = Players:GetPlayerByUserId(ownerId)
	return Loc.t("world.sign.island", { name = if owner then owner.DisplayName else "?" }), false
end

local function refreshIslandLabels()
	local cfg = WorldFXConfig.SIGNPOST
	for _, entry in _islandLabels do
		local text, home = islandText(entry.slot)
		local gui = entry.label.Parent
		local board = gui and gui.Parent
		if board and board:IsA("BasePart") then
			board.Color = if home then cfg.HOME_COLOR else cfg.WOOD
			for _, decal in board:GetChildren() do
				if decal:IsA("Decal") then decal.Color3 = board.Color end
			end
		end
		if entry.label.Name == "Front" then
			entry.label.Text = "◀ " .. text
		else
			entry.label.Text = text .. " ▶"
		end
	end
end

-- Ziel, auf das der dritte Arm zeigt: Haendler oder naechste Bestenliste.
local function sideTarget(from: Vector3): (Vector3, string)
	local m = EggConfig.MERCHANT_V2
	local best = MapLayout.atAngle(m.angleDegrees, m.radius)
	local bestDist = (best - from).Magnitude
	local key = "world.sign.merchant"
	for _, b in MapLayout.leaderboardBoards() do
		local p = MapLayout.atAngle(b.angleDegrees, MapConfig.LEADERBOARD_BOARD.radius)
		local d = (p - from).Magnitude
		if d < bestDist then
			best, bestDist, key = p, d, "world.sign.board"
		end
	end
	return best, key
end

local function flatDir(from: Vector3, to: Vector3): Vector3
	local d = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	return if d.Magnitude > 1e-3 then d.Unit else Vector3.new(1, 0, 0)
end

local function buildSignposts(folder: Instance)
	local cfg = WorldFXConfig.SIGNPOST
	for _, spot in MapLayout.signposts(cfg.RADIUS, cfg.SIDE) do
		local group = WorldFXKit.folder("Signpost_" .. spot.slot, folder)
		local base = spot.position
		WorldFXKit.pole("Post", group, base, cfg.POST_HEIGHT, 0.55, cfg.WOOD_DARK, Enum.Material.Wood)

		local function at(level: number): Vector3
			return base + Vector3.new(0, cfg.POST_HEIGHT - 0.9 - level * cfg.BOARD_GAP, 0)
		end

		-- 1: zur eigenen bzw. dieser Plot-Insel (nach aussen)
		local f1, b1 = buildBoard(group, at(0), spot.outward, cfg.WOOD)
		f1.Name, b1.Name = "Front", "Back"
		table.insert(_islandLabels, { label = f1, slot = spot.slot })
		table.insert(_islandLabels, { label = b1, slot = spot.slot })

		-- 2: zum Event (zur Mitte)
		local f2, b2 = buildBoard(group, at(1), -spot.outward, cfg.WOOD)
		bindArrow(f2, b2, "world.sign.event")

		-- 3: Haendler oder Bestenliste, was naeher ist
		local target, key = sideTarget(base)
		local f3, b3 = buildBoard(group, at(2), flatDir(base, target), cfg.WOOD)
		bindArrow(f3, b3, key)

		WorldFXKit.cullGroup(group, base, cfg.SHOW_DISTANCE)
	end

	refreshIslandLabels()
	Loc.onChanged(refreshIslandLabels)
	-- Plots kommen und gehen mit den Spielern
	local function onWorldChild(child: Instance)
		if string.match(child.Name, "^Plot_%d+$") then
			task.defer(refreshIslandLabels)
		end
	end
	workspace.ChildAdded:Connect(onWorldChild)
	workspace.ChildRemoved:Connect(onWorldChild)
	Players.PlayerAdded:Connect(function() task.delay(1, refreshIslandLabels) end)
end

--------------------------------------------------------------------------------
-- Haendler: Laterne und Eierkorb
--------------------------------------------------------------------------------

local function buildStallDecor(folder: Instance)
	local stand = workspace:WaitForChild("EggMerchant", 60)
	if not (stand and stand:IsA("Model")) then return end
	local counter = stand.PrimaryPart or stand:FindFirstChild("Counter")
	if not (counter and counter:IsA("BasePart")) then return end
	local cfg = WorldFXConfig.STALL

	-- Boden-CFrame des Stands (Theke steht 1,3 ueber dem Boden, siehe EggMerchantService)
	local base = counter.CFrame * CFrame.new(0, -1.3, 0)
	local group = WorldFXKit.folder("StallDecor", folder)

	-- Laterne links neben dem Stand
	local lampFoot = (base * CFrame.new(-4.2, 0, 0.6)).Position
	WorldFXKit.pole("LampPost", group, lampFoot, 4.2, 0.35, WorldFXConfig.SIGNPOST.WOOD_DARK, Enum.Material.Wood)
	local glow = WorldFXKit.ball("LampGlow", group, 1.1, lampFoot + Vector3.new(0, 4.7, 0), cfg.LANTERN_COLOR, Enum.Material.Neon)
	DayCycleController.registerGlow(glow, WorldFXConfig.LAMP_DAY, WorldFXConfig.LAMP_NIGHT)

	-- Korb rechts davor, mit drei Eiern
	local basketCF = base * CFrame.new(4.0, 0.45, -0.8)
	WorldFXKit.part("Basket", group, Vector3.new(0.9, 2.2, 2.2), basketCF * UPRIGHT, cfg.BASKET_COLOR, Enum.Material.WoodPlanks, Enum.PartType.Cylinder)
	for i, color in cfg.EGG_COLORS do
		local a = (i - 1) / #cfg.EGG_COLORS * math.pi * 2
		WorldFXKit.ellipsoid("Egg", group, Vector3.new(0.8, 1.05, 0.8),
			basketCF * CFrame.new(math.cos(a) * 0.45, 0.75, math.sin(a) * 0.45) * CFrame.Angles(math.rad(10) * math.cos(a), 0, math.rad(10) * math.sin(a)),
			color, Enum.Material.SmoothPlastic)
	end

	WorldFXKit.cullGroup(group, base.Position, cfg.SHOW_DISTANCE)
end

--------------------------------------------------------------------------------
-- Tafeln: Rahmen, Krone, Glanz auf Platz 1
--------------------------------------------------------------------------------

local function isBoard(part: Instance): boolean
	return part:IsA("BasePart") and (string.sub(part.Name, 1, 16) == "LeaderboardBoard" or part.Name == "LiveBoard")
		and part:FindFirstChild("Board") ~= nil
end

local _framed: { [Instance]: boolean } = {}

local function frameBoard(board: BasePart, folder: Instance)
	if _framed[board] then return end
	_framed[board] = true
	local cfg = WorldFXConfig.BOARD_FRAME
	local group = WorldFXKit.folder("Frame_" .. board.Name, folder)
	local cf, size = board.CFrame, board.Size
	local depth = size.Z + 0.25
	local hw, hh = size.X * 0.5, size.Y * 0.5

	-- vier Balken
	for _, sy in { -1, 1 } do
		WorldFXKit.part("Beam", group, Vector3.new(size.X + cfg.BEAM * 2, cfg.BEAM, depth),
			cf * CFrame.new(0, sy * (hh + cfg.BEAM * 0.5), 0), cfg.WOOD, Enum.Material.Wood)
	end
	for _, sx in { -1, 1 } do
		WorldFXKit.part("Beam", group, Vector3.new(cfg.BEAM, size.Y, depth),
			cf * CFrame.new(sx * (hw + cfg.BEAM * 0.5), 0, 0), cfg.WOOD, Enum.Material.Wood)
	end
	-- Honig-Ecken
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			WorldFXKit.ball("Corner", group, cfg.CORNER_SIZE,
				(cf * CFrame.new(sx * (hw + cfg.BEAM * 0.5), sy * (hh + cfg.BEAM * 0.5), 0)).Position,
				cfg.CORNER_COLOR, Enum.Material.Glass)
		end
	end
	-- Krone oben: Reif und drei Zacken
	local top = cf * CFrame.new(0, hh + cfg.BEAM + 0.45, 0)
	WorldFXKit.part("CrownBand", group, Vector3.new(0.6, 2.4, 2.4), top * UPRIGHT, cfg.CROWN_COLOR, Enum.Material.Neon, Enum.PartType.Cylinder)
	for i = -1, 1 do
		WorldFXKit.ball("CrownTip", group, 0.6, (top * CFrame.new(i * 0.85, 0.65 - math.abs(i) * 0.15, 0)).Position,
			cfg.CROWN_COLOR, Enum.Material.Neon)
	end

	-- Glanz auf Platz 1 (nur Bestenlisten, nicht das Live-Board)
	if board.Name ~= "LiveBoard" and WorldFXKit.enabled("boardShine") then
		local gui = board:FindFirstChild("Board")
		local line = gui and gui:FindFirstChild("Line1")
		if line and line:IsA("GuiObject") then
			local shine = Instance.new("Frame")
			shine.Name = "Shine"
			shine.BackgroundColor3 = Color3.new(1, 1, 1)
			shine.BorderSizePixel = 0
			shine.Position = line.Position
			shine.Size = line.Size
			shine.ZIndex = line.ZIndex + 1
			shine.Parent = gui
			local gradient = Instance.new("UIGradient")
			gradient.Rotation = 20
			gradient.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 1),
				NumberSequenceKeypoint.new(0.5, 0.55), NumberSequenceKeypoint.new(0.58, 1),
				NumberSequenceKeypoint.new(1, 1),
			})
			gradient.Parent = shine
			table.insert(_shines, { gradient = gradient, group = group })
		end
	end

	WorldFXKit.cullGroup(group, cf.Position, cfg.SHOW_DISTANCE)
end

local function buildBoardFrames(folder: Instance)
	local platform = workspace:WaitForChild("Platform", 60)
	if not platform then return end
	for _, child in platform:GetChildren() do
		if isBoard(child) then
			frameBoard(child :: BasePart, folder)
		end
	end
	platform.ChildAdded:Connect(function(child)
		task.defer(function()
			if isBoard(child) then frameBoard(child :: BasePart, folder) end
		end)
	end)
end

--------------------------------------------------------------------------------
-- Einstieg
--------------------------------------------------------------------------------

function HubLandmarkController.init()
	if not FeatureFlags.isOn("WORLD_C_HUB") then return end
	local folder = WorldFXKit.folder("Hub", WorldFXKit.root())

	if WorldFXKit.enabled("mastCrown") then
		buildCrown(folder)
	end
	if WorldFXKit.enabled("honeyThread") then
		buildHoneyThread(folder)
	end
	if WorldFXKit.enabled("signposts") then
		buildSignposts(folder)
	end
	if WorldFXKit.enabled("stallDecor") then
		task.spawn(buildStallDecor, folder)
	end
	if WorldFXKit.enabled("boardFrames") then
		task.spawn(buildBoardFrames, folder)
	end

	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc < TICK then return end
		acc = 0
		local now = os.clock()
		stepDrip(now)
		-- Glanzstreifen wandert ueber Platz 1 (nur sichtbare Tafeln)
		local offset = ((now / WorldFXConfig.BOARD_FRAME.SHINE_PERIOD) % 1) * 2 - 1
		for _, shine in _shines do
			if shine.group.Parent then
				shine.gradient.Offset = Vector2.new(offset, 0)
			end
		end
	end)

	print("[Hub] Wahrzeichen aktiv")
end

return HubLandmarkController
