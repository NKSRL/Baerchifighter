--!strict
-- ArenaLifeController.luau
-- StarterPlayerScripts/Controllers/ArenaLifeController.luau
--
-- Einzige Zustaendigkeit:
--   - Der Weg in den Kampf (Paket E, "Welt aufwerten"): Honig-Laternen am
--     Steg zur Arena (Welle beim Laufstart), Torbogen am Arena-Eingang,
--     Zuschauer-Baerchis auf dem Zaun (huepfen bei Faehigkeiten, jubeln bei
--     neuem Rekord) und eine wehende Flagge auf dem Schau-Turm
--
-- Woher der Client weiss, was passiert (keine neue Server-Logik):
--   * Lauf laeuft    = die Arena-Tafel ist eingeblendet
--                      (Plot_N/PitPlatform/PitBannerAnchor/Banner.Enabled,
--                      MapService.setPitBanner)
--   * Faehigkeit     = Remotes.SkillFXPlay (geht ohnehin an alle Clients),
--                      `center` liegt in dieser Arena
--   * neuer Rekord   = der Schau-Turm wird neu gebaut und die Zahl am Ende
--                      seines Schilds ist hoeher als vorher
--                      (ArenaBuilder.buildShowcase, Titel "Name · Tower III · 42")
--
-- Alles nur auf dem Client, pro besetztem Slot aus einem Pool (einmal gebaut,
-- danach ein- und ausgehaengt). Kein Server-Teil.
--
-- PERFORMANCE: EIN Takt (20x pro Sekunde) nur fuer Arenen in Sichtweite;
-- Lauf-Zustand 4x pro Sekunde. Keine Lichter, kein Emitter.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local MapConfig     = require(ReplicatedStorage.Config.MapConfig)
local WorldFXConfig = require(ReplicatedStorage.Config.WorldFXConfig)
local FeatureFlags  = require(ReplicatedStorage.Config.FeatureFlags)
local MapLayout     = require(ReplicatedStorage.Modules.MapLayout)
local Remotes       = require(ReplicatedStorage.Network.Remotes)

local WorldFXKit         = require(script.Parent.WorldFXKit)
local DayCycleController = require(script.Parent.DayCycleController)

local ArenaLifeController = {}

local TICK = 0.05
local TAU = math.pi * 2

type Spectator = { model: Model, base: CFrame, armL: BasePart, armR: BasePart, phase: number }
type Arena = {
	slot: number,
	group: Folder,
	shown: boolean,
	occupied: boolean,
	lamps: { { glass: BasePart, index: number } },
	running: boolean,
	waveStart: number,
	spectators: { Spectator },
	hopUntil: number,
	cheerUntil: number,
	flag: { pole: BasePart, cloth: BasePart, base: CFrame }?,
	flagShineUntil: number,
	record: number?,
}

local _folder: Folder? = nil
local _arenas: { [number]: Arena } = {}

--------------------------------------------------------------------------------
-- Hilfen
--------------------------------------------------------------------------------

-- Richtung in der Arena: 0 Grad = nach aussen (weg vom Steg), 90 = zur Seite.
local function pitDir(slot: number, degrees: number): Vector3
	local a = math.rad(degrees)
	return MapLayout.outward(slot) * math.cos(a) + MapLayout.side(slot) * math.sin(a)
end

local function plotOf(slot: number): Instance?
	return workspace:FindFirstChild("Plot_" .. slot)
end

local function isRunning(slot: number): boolean
	local plot = plotOf(slot)
	local platform = plot and plot:FindFirstChild("PitPlatform")
	local anchor = platform and platform:FindFirstChild("PitBannerAnchor")
	local banner = anchor and anchor:FindFirstChild("Banner")
	return banner ~= nil and banner:IsA("BillboardGui") and banner.Enabled
end

--------------------------------------------------------------------------------
-- Bau (einmal je Slot)
--------------------------------------------------------------------------------

local function buildLamps(arena: Arena)
	if not WorldFXKit.enabled("bridgeLamps") then return end
	local cfg = WorldFXConfig.BRIDGE_LAMPS
	local slot = arena.slot
	local outward, side = MapLayout.outward(slot), MapLayout.side(slot)
	local deckTop = MapConfig.PLATFORM_TOP_Y - MapConfig.BRIDGE_SINK
	local sideOffset = (MapConfig.BRIDGE_WIDTH + MapConfig.BRIDGE_RAIL_WIDTH) * 0.5
	local from = MapConfig.PLOT_RING_RADIUS + MapConfig.PLOT_ISLAND_RADIUS + 6
	local to = from + MapConfig.ISLAND_GAP - 12
	for i = 1, cfg.PER_SIDE do
		local r = from + (to - from) * (i - 1) / math.max(1, cfg.PER_SIDE - 1)
		for _, sign in { -1, 1 } do
			local p = MapConfig.CENTER + outward * r + side * (sign * sideOffset)
			local foot = Vector3.new(p.X, deckTop, p.Z)
			WorldFXKit.pole("LampPost", arena.group, foot, cfg.POST_HEIGHT, 0.35, MapConfig.BRIDGE_RAIL_COLOR, Enum.Material.Wood)
			local glass = WorldFXKit.ball("LampGlass", arena.group, cfg.GLASS_SIZE,
				foot + Vector3.new(0, cfg.POST_HEIGHT + cfg.GLASS_SIZE * 0.4, 0), cfg.OFF_COLOR, Enum.Material.Glass)
			table.insert(arena.lamps, { glass = glass, index = i })
		end
	end
end

local function buildArch(arena: Arena)
	if not WorldFXKit.enabled("arenaArch") then return end
	local cfg = WorldFXConfig.ARENA_ARCH
	local slot = arena.slot
	local pit = MapLayout.pitCenter(slot)
	-- auf dem Zaunring, mitten in der Zaunluecke zum Steg
	local ring = MapConfig.PIT_BASE_RADIUS - MapConfig.PIT_FENCE_INSET
	local gate = pit - MapLayout.outward(slot) * ring
	local side = MapLayout.side(slot)
	local baseY = MapConfig.PLATFORM_TOP_Y - MapConfig.PIT_RIM_DROP
	for _, sign in { -1, 1 } do
		local p = gate + side * (sign * cfg.HALF_WIDTH)
		WorldFXKit.pole("ArchPost", arena.group, Vector3.new(p.X, baseY, p.Z), cfg.HEIGHT, cfg.POST_DIAMETER, cfg.WOOD, Enum.Material.Wood)
	end
	local top = Vector3.new(gate.X, baseY + cfg.HEIGHT - 0.3, gate.Z)
	WorldFXKit.part("ArchBeam", arena.group, Vector3.new(cfg.HALF_WIDTH * 2 + 1.2, 0.8, 0.8),
		CFrame.fromMatrix(top, side, Vector3.yAxis), cfg.WOOD, Enum.Material.Wood, Enum.PartType.Cylinder)
	-- Honigwabe oben, Stirnseite zum Steg
	local comb = WorldFXKit.part("ArchComb", arena.group, Vector3.new(0.8, cfg.COMB_SIZE, cfg.COMB_SIZE),
		CFrame.fromMatrix(top + Vector3.new(0, cfg.COMB_SIZE * 0.5 + 0.2, 0), -MapLayout.outward(slot), Vector3.yAxis),
		WorldFXConfig.MAST.CELL_DAY, Enum.Material.Neon, Enum.PartType.Cylinder)
	DayCycleController.registerGlow(comb, WorldFXConfig.MAST.CELL_DAY, WorldFXConfig.MAST.CELL_NIGHT)
end

local SPECTATOR_ANGLES = { -120, -75, -30, 30, 75, 120 }   -- fern der Steg-Luecke (180 +- 34)

local function buildSpectators(arena: Arena)
	if not WorldFXKit.enabled("spectators") then return end
	local cfg = WorldFXConfig.SPECTATORS
	local slot = arena.slot
	local pit = MapLayout.pitCenter(slot)
	local ring = MapConfig.PIT_BASE_RADIUS - MapConfig.PIT_FENCE_INSET
	local seatY = MapConfig.PLATFORM_TOP_Y - MapConfig.PIT_RIM_DROP + MapConfig.PIT_FENCE_SIZE.Y
	for i = 1, math.min(cfg.COUNT, #SPECTATOR_ANGLES) do
		local dir = pitDir(slot, SPECTATOR_ANGLES[i])
		local seat = Vector3.new(pit.X, seatY, pit.Z) + dir * ring
		-- schaut zur Arena-Mitte
		local base = CFrame.lookAt(seat, Vector3.new(pit.X, seatY, pit.Z))
		local color = cfg.COLORS[(i - 1) % #cfg.COLORS + 1]
		local model = Instance.new("Model")
		model.Name = "Spectator"
		local s = cfg.SCALE
		local body = WorldFXKit.ellipsoid("Body", model, Vector3.new(1.3, 1.4, 1.1) * s, base * CFrame.new(0, 0.7 * s, 0), color)
		WorldFXKit.ball("Head", model, 1.0 * s, (base * CFrame.new(0, 1.75 * s, 0)).Position, color)
		for _, x in { -0.38, 0.38 } do
			WorldFXKit.ball("Ear", model, 0.38 * s, (base * CFrame.new(x * s, 2.25 * s, 0)).Position, color)
		end
		local armL = WorldFXKit.part("ArmL", model, Vector3.new(0.3, 0.8, 0.3) * s, base * CFrame.new(-0.7 * s, 0.9 * s, 0), color)
		local armR = WorldFXKit.part("ArmR", model, Vector3.new(0.3, 0.8, 0.3) * s, base * CFrame.new(0.7 * s, 0.9 * s, 0), color)
		model.PrimaryPart = body
		model.Parent = arena.group
		table.insert(arena.spectators, { model = model, base = model:GetPivot(), armL = armL, armR = armR, phase = i * 0.37 })
	end
end

local function buildArena(slot: number): Arena
	local group = WorldFXKit.folder("ArenaLife_" .. slot, _folder :: Folder)
	local arena: Arena = {
		slot = slot, group = group, shown = true, occupied = false,
		lamps = {}, running = false, waveStart = 0,
		spectators = {}, hopUntil = 0, cheerUntil = 0,
		flag = nil, flagShineUntil = 0, record = nil,
	}
	buildLamps(arena)
	buildArch(arena)
	buildSpectators(arena)
	return arena
end

--------------------------------------------------------------------------------
-- Schau-Turm: Flagge und Rekord
--------------------------------------------------------------------------------

local function recordOf(showcase: Instance): (number?, Color3?)
	local anchor = showcase:FindFirstChild("SignAnchor")
	local sign = anchor and anchor:FindFirstChild("Sign")
	local title = sign and sign:FindFirstChild("Title")
	if not (title and title:IsA("TextLabel")) then return nil, nil end
	local n = string.match(title.Text, "(%d+)%s*$")
	return (if n then tonumber(n) else nil), title.TextColor3
end

local function cheer(arena: Arena)
	local now = os.clock()
	arena.cheerUntil = now + WorldFXConfig.SPECTATORS.CHEER_TIME
	arena.flagShineUntil = now + WorldFXConfig.SHOWCASE_FLAG.SHINE_TIME
end

local function attachFlag(arena: Arena, showcase: Instance)
	local old = arena.flag
	if old then
		old.pole:Destroy()
		old.cloth:Destroy()
	end
	arena.flag = nil

	local record, color = recordOf(showcase)
	local previous = arena.record
	arena.record = record
	if previous and record and record > previous then
		cheer(arena)
	end

	if not (WorldFXKit.enabled("showcaseFlag") and showcase:IsA("Model")) then return end
	local cfg = WorldFXConfig.SHOWCASE_FLAG
	-- Spitze: oberste Kante der Turm-Teile (Schild-Anker ausgenommen)
	local top = -math.huge
	local foot = MapLayout.showcaseFoot(arena.slot)
	for _, part in showcase:GetChildren() do
		if part:IsA("BasePart") and part.Name ~= "SignAnchor" then
			top = math.max(top, part.Position.Y + part.Size.Y * 0.5)
		end
	end
	if top == -math.huge then return end
	local poleFoot = Vector3.new(foot.X, top - 0.2, foot.Z)
	-- Flaggen-Container haengt am Turm-Gruppen-Ordner des Schau-Turms (Hauptinsel)
	local pole = WorldFXKit.pole("FlagPole", _folder, poleFoot, cfg.POLE_HEIGHT, 0.2, Color3.fromRGB(110, 76, 48), Enum.Material.Wood)
	local side = MapLayout.side(arena.slot)
	local base = CFrame.fromMatrix(poleFoot + Vector3.new(0, cfg.POLE_HEIGHT - cfg.FLAG_SIZE.Y * 0.5, 0), side, Vector3.yAxis)
	local cloth = WorldFXKit.part("Flag", _folder, cfg.FLAG_SIZE, base * CFrame.new(cfg.FLAG_SIZE.X * 0.5, 0, 0),
		color or Color3.fromRGB(255, 214, 110), Enum.Material.Fabric)
	local flagId = WorldFXKit.textureId("flag_fabric")
	if flagId then
		for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
			local decal = Instance.new("Decal")
			decal.Texture = flagId
			decal.Face = face
			decal.Parent = cloth
		end
	end
	arena.flag = { pole = pole, cloth = cloth, base = base }
end

local function watchShowcase(arena: Arena)
	local plot = plotOf(arena.slot)
	if not plot then return end
	local current = plot:FindFirstChild("TowerShowcase")
	if current then
		attachFlag(arena, current)
	end
	plot.ChildAdded:Connect(function(child)
		if child.Name == "TowerShowcase" then
			task.wait(0.1)   -- Schild wird nach dem Model gefuellt
			if child.Parent then attachFlag(arena, child) end
		end
	end)
end

--------------------------------------------------------------------------------
-- Takt
--------------------------------------------------------------------------------

local function stepFlag(arena: Arena, now: number, clock: number)
	-- Flagge weht; beim Rekord glaenzt sie einmal auf
	local flag = arena.flag
	if not flag then return end
	local fcfg = WorldFXConfig.SHOWCASE_FLAG
	local swing = math.rad(fcfg.WAVE_DEGREES) * math.sin(clock * fcfg.WAVE_RATE * TAU + arena.slot)
	flag.cloth.CFrame = flag.base * CFrame.Angles(0, swing, 0) * CFrame.new(fcfg.FLAG_SIZE.X * 0.5, 0, 0)
	local material = if now < arena.flagShineUntil then Enum.Material.Neon else Enum.Material.Fabric
	if flag.cloth.Material ~= material then flag.cloth.Material = material end
end

local function stepArena(arena: Arena, now: number)
	-- Laternen: Welle vom Plot zur Arena, aus nach dem Lauf
	local cfg = WorldFXConfig.BRIDGE_LAMPS
	for _, lamp in arena.lamps do
		local on = arena.running and now >= arena.waveStart + (lamp.index - 1) * cfg.WAVE_STEP
		local want = if on then cfg.ON_COLOR else cfg.OFF_COLOR
		if lamp.glass.Color ~= want then
			lamp.glass.Color = want
			lamp.glass.Material = if on then Enum.Material.Neon else Enum.Material.Glass
		end
	end

	-- Zuschauer: Hopser bei einer Faehigkeit, Jubel (Arme hoch) beim Rekord
	local scfg = WorldFXConfig.SPECTATORS
	local cheering = now < arena.cheerUntil
	local hopping = now < arena.hopUntil or cheering
	for _, sp in arena.spectators do
		local lift = 0
		if hopping then
			local t = ((now + sp.phase) % scfg.HOP_TIME) / scfg.HOP_TIME
			lift = scfg.HOP_HEIGHT * 4 * t * (1 - t)
		end
		sp.model:PivotTo(sp.base * CFrame.new(0, lift, 0))
		local armAngle = if cheering then math.rad(160) else 0
		local pivot = sp.model:GetPivot()
		-- Schulter knapp ueber der Koerpermitte; Arm haengt, beim Jubel hoch
		sp.armL.CFrame = pivot * CFrame.new(-0.7, 0.35, 0) * CFrame.Angles(0, 0, -armAngle) * CFrame.new(0, -0.35, 0)
		sp.armR.CFrame = pivot * CFrame.new(0.7, 0.35, 0) * CFrame.Angles(0, 0, armAngle) * CFrame.new(0, -0.35, 0)
	end
end

--------------------------------------------------------------------------------
-- Besetzung, Sichtweite, Lauf-Zustand (4x pro Sekunde)
--------------------------------------------------------------------------------

local function setOccupied(slot: number, occupied: boolean)
	local arena = _arenas[slot]
	if not arena then
		if not occupied then return end
		arena = buildArena(slot)
		_arenas[slot] = arena
	end
	local a = arena :: Arena
	a.occupied = occupied
	if occupied then
		a.record = nil
		task.spawn(watchShowcase, a)
	else
		local flag = a.flag
		if flag then
			flag.pole:Destroy()
			flag.cloth:Destroy()
		end
		a.flag = nil
	end
end

local function refresh()
	local camera = workspace.CurrentCamera
	local folder = _folder
	if not (camera and folder) then return end
	local eye = camera.CFrame.Position
	for slot, arena in _arenas do
		local d = (MapLayout.pitCenter(slot) - eye).Magnitude
		local limit = WorldFXConfig.BRIDGE_LAMPS.SHOW_DISTANCE * (if arena.shown then 1 else 0.9)
		local want = arena.occupied and d <= limit
		if want ~= arena.shown then
			arena.shown = want
			arena.group.Parent = if want then folder else nil
		end
		local running = arena.occupied and isRunning(slot)
		if running and not arena.running then
			arena.waveStart = os.clock()
		end
		arena.running = running
	end
end

local function slotOf(child: Instance): number?
	local n = string.match(child.Name, "^Plot_(%d+)$")
	return if n then tonumber(n) else nil
end

-- Arena des Spielers mit dieser UserId (ueber das Plot-Attribut PlotOwner).
local function arenaOfUser(userId: number?): Arena?
	if not userId then return nil end
	for slot, arena in _arenas do
		local plot = plotOf(slot)
		if plot and plot:GetAttribute("PlotOwner") == userId then return arena end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Einstieg
--------------------------------------------------------------------------------

function ArenaLifeController.init()
	if not FeatureFlags.isOn("WORLD_E_ARENA") then return end
	_folder = WorldFXKit.folder("ArenaLife", WorldFXKit.root())

	for slot = 1, MapConfig.PLOT_COUNT do
		if workspace:FindFirstChild("Plot_" .. slot) then setOccupied(slot, true) end
	end
	workspace.ChildAdded:Connect(function(child)
		local slot = slotOf(child)
		if slot then setOccupied(slot, true) end
	end)
	workspace.ChildRemoved:Connect(function(child)
		local slot = slotOf(child)
		if slot and not workspace:FindFirstChild(child.Name) then setOccupied(slot, false) end
	end)

	-- Faehigkeit in einer Arena: die Zuschauer dort huepfen kurz
	Remotes.SkillFXPlay.OnClientEvent:Connect(function(req: any)
		if typeof(req) ~= "table" or typeof(req.owner) ~= "number" then return end
		local arena = arenaOfUser(req.owner)
		if arena then
			arena.hopUntil = os.clock() + WorldFXConfig.SPECTATORS.HOP_TIME * 2
		end
	end)

	-- Debug (Studio): "<userId>|hop|n" bzw. "<userId>|n" fuer den Rekord
	WorldFXKit.onDebug("DebugSpectators", function(value: any)
		if typeof(value) ~= "string" then return end
		local id, mode = string.match(value, "^(%d+)|(%a+)")
		local arena = arenaOfUser(tonumber(id))
		if not arena then return end
		if mode == "cheer" then cheer(arena) else arena.hopUntil = os.clock() + 2 end
	end, false)
	WorldFXKit.onDebug("DebugRecord", function(value: any)
		if typeof(value) ~= "string" then return end
		local arena = arenaOfUser(tonumber(string.match(value, "^(%d+)")))
		if arena then cheer(arena) end
	end, false)

	local acc, stateAcc, clock = 0, 1, 0
	RunService.Heartbeat:Connect(function(dt: number)
		clock += dt
		acc += dt
		stateAcc += dt
		if stateAcc >= 0.25 then
			stateAcc = 0
			refresh()
		end
		if acc < TICK then return end
		acc = 0
		local now = os.clock()
		for _, arena in _arenas do
			if arena.shown then
				stepArena(arena, now)
			end
			stepFlag(arena, now, clock)
		end
	end)

	print("[ArenaLife] aktiv")
end

return ArenaLifeController
