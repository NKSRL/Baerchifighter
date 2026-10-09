--!strict
-- LifeController.luau
-- StarterPlayerScripts/Controllers/LifeController.luau
--
-- Einzige Zustaendigkeit:
--   - Kleine Bewegung ueberall (Paket F, "Welt aufwerten"): Bienenschwaerme
--     zwischen Blumen und Teichen, Schmetterlinge auf der Hauptinsel, Blumen
--     nicken im Wind und weichen dem eigenen Charakter aus, Pfotenabdruecke
--     im Sand
--
-- Die Pollenfarbe folgt dem Tageslauf; das macht DayCycleController (dort
-- haengt jede Farbe, die am Tageslauf haengt).
--
-- PERFORMANCE:
--   * EIN Takt (15x pro Sekunde). Bienen, Schmetterlinge und Blumen bewegt je
--     EIN workspace:BulkMoveTo, nur was in Sichtweite ist.
--   * Bienen: hoechstens BEES.MAX_SWARMS Schwaerme in Sicht (plus
--     HOME_EXTRA auf der eigenen Insel), aus einem festen Pool.
--   * Die Blumen der Hauptinsel sind Server-Teile; sie werden nur lokal
--     gedreht (der Server setzt sie nie wieder), nichts wird repliziert.
--   * Pfotenabdruecke: Pool von FOOTPRINTS.MAX, kein Neubau.
--   * Niedrige Qualitaet: alles aus Paket F aus (WorldFXConfig.MIN_QUALITY).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local MapConfig     = require(ReplicatedStorage.Config.MapConfig)
local WorldFXConfig = require(ReplicatedStorage.Config.WorldFXConfig)
local FeatureFlags  = require(ReplicatedStorage.Config.FeatureFlags)
local MapLayout     = require(ReplicatedStorage.Modules.MapLayout)

local WorldFXKit         = require(script.Parent.WorldFXKit)
local PlotLifeController = require(script.Parent.PlotLifeController)

local LifeController = {}

local localPlayer = Players.LocalPlayer
local TICK = 1 / 15
local TAU = math.pi * 2

--------------------------------------------------------------------------------
-- Orte, an denen Leben ist
--------------------------------------------------------------------------------

type Site = { position: Vector3, home: boolean }

-- Feste Orte auf der Hauptinsel (in den Wiesenstuecken zwischen den Wegen)
local function hubSites(): { Site }
	local list: { Site } = {}
	for k = 0, MapConfig.PLOT_COUNT - 1 do
		for _, r in { 70, 96 } do
			local angle = 22.5 + k * 45 + (if r == 70 then 8 else -8)
			table.insert(list, { position = MapLayout.atAngle(angle, r), home = false })
		end
	end
	return list
end

-- Orte auf den besetzten Plot-Inseln: der Teich und zwei Randpunkte
local function plotSites(): { Site }
	local list: { Site } = {}
	local home = PlotLifeController.homeSlot()
	for slot = 1, MapConfig.PLOT_COUNT do
		if workspace:FindFirstChild("Plot_" .. slot) then
			local center = MapLayout.plotCenter(slot)
			local plotCF = CFrame.lookAt(center, Vector3.new(MapConfig.CENTER.X, center.Y, MapConfig.CENTER.Z))
			local isHome = slot == home
			table.insert(list, { position = (plotCF * CFrame.new(MapLayout.pondOffset())).Position, home = isHome })
			for _, angle in { 75, 285 } do
				local p = MapLayout.islandRimPoint(slot, angle, WorldFXConfig.ISLAND_STAGE.RIM_RADIUS)
				table.insert(list, { position = p, home = isHome })
			end
		end
	end
	return list
end

--------------------------------------------------------------------------------
-- Bienen
--------------------------------------------------------------------------------

type Swarm = { parts: { BasePart }, count: number, site: Site?, phase: number, center: Vector3? }
local SWARM_SPEED = 14   -- Studs/s: so schnell zieht ein Schwarm zu seinem neuen Ort
local _rally: { position: Vector3, untilTime: number }? = nil
local _swarms: { Swarm } = {}
local _hubSites: { Site } = {}
local _swarmFolder: Folder? = nil

local function buildBees(folder: Folder)
	local cfg = WorldFXConfig.BEES
	_swarmFolder = folder
	local random = Random.new(20261009)
	for i = 1, cfg.MAX_SWARMS + cfg.HOME_EXTRA do
		local count = random:NextInteger(cfg.PER_SWARM[1], cfg.PER_SWARM[2])
		local parts: { BasePart } = {}
		for _ = 1, count do
			table.insert(parts, WorldFXKit.ellipsoid("Bee", nil, Vector3.new(0.32, 0.32, 0.5), CFrame.new(), cfg.COLOR))
			table.insert(parts, WorldFXKit.part("Wings", nil, Vector3.new(0.6, 0.04, 0.2), CFrame.new(), Color3.new(1, 1, 1)))
			parts[#parts].Transparency = 0.5
		end
		table.insert(_swarms, { parts = parts, count = count, site = nil, phase = i * 1.9 })
	end
	_hubSites = hubSites()
end

-- Alle 2 s: die naechsten Orte an die Schwaerme verteilen (eigene Insel zuerst).
local function assignSwarms()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local cfg = WorldFXConfig.BEES
	local eye = camera.CFrame.Position
	local candidates: { { site: Site, d: number } } = {}
	-- Paket G: Event startet — alle Schwaerme in Sicht ziehen zum Event-Pit
	local rally = _rally
	if rally and os.clock() < rally.untilTime then
		local site: Site = { position = rally.position, home = false }
		for _, swarm in _swarms do
			if swarm.site then swarm.site = site end
		end
		return
	end
	_rally = nil
	local all = plotSites()
	for _, s in _hubSites do table.insert(all, s) end
	for _, site in all do
		local d = (site.position - eye).Magnitude
		if d <= cfg.VIEW_DISTANCE then
			table.insert(candidates, { site = site, d = if site.home then d - 1000 else d })
		end
	end
	table.sort(candidates, function(a, b) return a.d < b.d end)

	local homeLeft = cfg.HOME_EXTRA
	local used = 0
	for i, swarm in _swarms do
		local entry = candidates[i]
		local allowed = entry ~= nil and (used < cfg.MAX_SWARMS or (entry.site.home and homeLeft > 0))
		if allowed and entry then
			if entry.site.home and used >= cfg.MAX_SWARMS then homeLeft -= 1 else used += 1 end
			if not swarm.site then swarm.center = entry.site.position end   -- neu: dort erscheinen
			swarm.site = entry.site
			for _, part in swarm.parts do part.Parent = _swarmFolder end
		else
			swarm.site = nil
			swarm.center = nil
			for _, part in swarm.parts do part.Parent = nil end
		end
	end
end

local function stepBees(clock: number, dt: number, parts: { BasePart }, cframes: { CFrame })
	local cfg = WorldFXConfig.BEES
	for _, swarm in _swarms do
		local site = swarm.site
		if site then
			-- weich zum (neuen) Ort fliegen statt zu springen
			local center = swarm.center or site.position
			local delta = site.position - center
			local step = SWARM_SPEED * dt
			center = if delta.Magnitude <= step then site.position else center + delta.Unit * step
			swarm.center = center
			for j = 1, swarm.count do
				-- Acht ueber dem Ort, jede Biene etwas schneller und versetzt
				local a = clock * cfg.SPEED * TAU * (1 + 0.17 * j) + swarm.phase + j * 1.3
				local r = cfg.SITE_RADIUS * (0.6 + 0.12 * j)
				local pos = center + Vector3.new(math.cos(a) * r, 1.8 + 0.6 * math.sin(a * 3), math.sin(a * 2) * r * 0.5)
				local ahead = Vector3.new(-math.sin(a), 0, math.cos(a * 2))
				local body = CFrame.lookAt(pos, pos + (if ahead.Magnitude > 1e-3 then ahead else Vector3.new(0, 0, 1)))
				table.insert(parts, swarm.parts[j * 2 - 1])
				table.insert(cframes, body)
				table.insert(parts, swarm.parts[j * 2])
				table.insert(cframes, body * CFrame.new(0, 0.18, 0) * CFrame.Angles(0, 0, math.rad(25) * math.sin(clock * 40 + j)))
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Schmetterlinge (Hauptinsel)
--------------------------------------------------------------------------------

type Butterfly = { wings: { BasePart }, home: Vector3, phase: number }
local _butterflies: { Butterfly } = {}

local function buildButterflies(folder: Folder)
	local cfg = WorldFXConfig.BUTTERFLIES
	for i = 1, cfg.COUNT do
		local angle = 22.5 + (i - 1) * (360 / cfg.COUNT) + 12
		local home = MapLayout.atAngle(angle, 84)
		local color = cfg.COLORS[(i - 1) % #cfg.COLORS + 1]
		local wings: { BasePart } = {}
		for _ = 1, 2 do
			table.insert(wings, WorldFXKit.part("Wing", folder, Vector3.new(0.75, 0.05, 0.55), CFrame.new(home), color))
		end
		table.insert(_butterflies, { wings = wings, home = home, phase = i * 2.1 })
	end
end

local function stepButterflies(clock: number, eye: Vector3, parts: { BasePart }, cframes: { CFrame })
	local cfg = WorldFXConfig.BUTTERFLIES
	for _, b in _butterflies do
		if (b.home - eye).Magnitude <= cfg.VIEW_DISTANCE then
			local t = clock * 0.22 + b.phase
			local pos = b.home + Vector3.new(math.cos(t) * cfg.WANDER, cfg.HEIGHT + math.sin(t * 2.7) * 0.9, math.sin(t * 1.3) * cfg.WANDER)
			local ahead = Vector3.new(-math.sin(t), 0, math.cos(t * 1.3) * 1.3)
			local body = CFrame.lookAt(pos, pos + (if ahead.Magnitude > 1e-3 then ahead else Vector3.new(0, 0, 1)))
			local flap = math.rad(55) * math.sin(clock * cfg.FLAP_RATE * TAU + b.phase)
			table.insert(parts, b.wings[1])
			table.insert(cframes, body * CFrame.Angles(0, 0, flap) * CFrame.new(-0.38, 0, 0))
			table.insert(parts, b.wings[2])
			table.insert(cframes, body * CFrame.Angles(0, 0, -flap) * CFrame.new(0.38, 0, 0))
		end
	end
end

--------------------------------------------------------------------------------
-- Blumen im Wind (Server-Blumen der Hauptinsel, nur lokal gedreht)
--------------------------------------------------------------------------------

type Flower = { stem: BasePart, head: BasePart?, foot: Vector3, stemOffset: CFrame, headOffset: CFrame?, dodge: Vector3 }
local _flowers: { Flower } = {}
local WIND = Vector3.new(1, 0, 0.35).Unit

local function collectFlowers()
	local platform = workspace:WaitForChild("Platform", 60)
	if not platform then return end
	local heads: { [string]: BasePart } = {}
	local stems: { BasePart } = {}
	local function key(p: Vector3): string
		return string.format("%d:%d", math.floor(p.X * 10 + 0.5), math.floor(p.Z * 10 + 0.5))
	end
	for _, child in platform:GetChildren() do
		if child:IsA("BasePart") then
			if child.Name == "FlowerStem" then
				table.insert(stems, child)
			elseif child.Name == "FlowerHead" then
				heads[key(child.Position)] = child
			end
		end
	end
	for _, stem in stems do
		local foot = stem.Position - Vector3.new(0, stem.Size.Y * 0.5, 0)
		local pivot = CFrame.new(foot)
		local head = heads[key(stem.Position)]
		table.insert(_flowers, {
			stem = stem,
			head = head,
			foot = foot,
			stemOffset = pivot:ToObjectSpace(stem.CFrame),
			headOffset = if head then pivot:ToObjectSpace(head.CFrame) else nil,
			dodge = Vector3.zero,
		})
	end
end

local function stepFlowers(clock: number, eye: Vector3, root: BasePart?, parts: { BasePart }, cframes: { CFrame })
	local cfg = WorldFXConfig.FLOWER_SWAY
	local axis = Vector3.new(-WIND.Z, 0, WIND.X)   -- Kippachse quer zum Wind
	local body = if root then root.Position else nil
	for _, f in _flowers do
		if (f.foot - eye).Magnitude <= cfg.VIEW_DISTANCE then
			-- gemeinsame Welle, die ueber die Insel laeuft
			local along = f.foot.X * WIND.X + f.foot.Z * WIND.Z
			local angle = math.rad(cfg.DEGREES) * math.sin(TAU * (clock * cfg.RATE - along / cfg.WAVELENGTH))
			local tilt = CFrame.fromAxisAngle(axis, angle)

			-- Ausweichen: vom Charakter weg kippen, danach langsam zurueck
			local target = Vector3.zero
			if body then
				local away = Vector3.new(f.foot.X - body.X, 0, f.foot.Z - body.Z)
				local d = away.Magnitude
				if d < cfg.DODGE_RADIUS and d > 1e-3 and math.abs(body.Y - f.foot.Y) < 6 then
					target = away.Unit * (1 - d / cfg.DODGE_RADIUS)
				end
			end
			f.dodge = f.dodge:Lerp(target, 0.25)
			if f.dodge.Magnitude > 0.01 then
				local dodgeAxis = Vector3.new(f.dodge.Z, 0, -f.dodge.X)
				tilt = CFrame.fromAxisAngle(dodgeAxis.Unit, -math.rad(cfg.DODGE_DEGREES) * f.dodge.Magnitude) * tilt
			end

			local pivot = CFrame.new(f.foot) * tilt
			table.insert(parts, f.stem)
			table.insert(cframes, pivot * f.stemOffset)
			local head, offset = f.head, f.headOffset
			if head and offset then
				table.insert(parts, head)
				table.insert(cframes, pivot * offset)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Pfotenabdruecke
--------------------------------------------------------------------------------

type Print = { part: BasePart, decal: Decal?, born: number }
local _prints: { Print } = {}
local _nextPrint = 1
local _lastPrintAt: Vector3? = nil
local _printSide = 1

local function buildPrints()
	local cfg = WorldFXConfig.FOOTPRINTS
	local pawId = WorldFXKit.textureId("paw_print")
	for _ = 1, cfg.MAX do
		local part = WorldFXKit.part("Paw", nil, Vector3.new(cfg.SIZE, 0.05, cfg.SIZE * 1.15), CFrame.new(), cfg.COLOR)
		local decal: Decal? = nil
		if pawId then
			part.Transparency = 1
			local d = Instance.new("Decal")
			d.Texture = pawId
			d.Face = Enum.NormalId.Top
			d.Color3 = cfg.COLOR
			d.Parent = part
			decal = d
		else
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = part
		end
		table.insert(_prints, { part = part, decal = decal, born = -math.huge })
	end
end

local function stepPrints(folder: Folder, character: Model?)
	local cfg = WorldFXConfig.FOOTPRINTS
	local now = os.clock()
	-- verblassen
	for _, p in _prints do
		if p.part.Parent then
			local k = (now - p.born) / cfg.FADE
			if k >= 1 then
				p.part.Parent = nil
			elseif p.decal then
				(p.decal :: Decal).Transparency = k
			else
				p.part.Transparency = 0.25 + 0.75 * k
			end
		end
	end

	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (humanoid and root and root:IsA("BasePart")) then return end
	if humanoid.FloorMaterial ~= Enum.Material.Sand then
		_lastPrintAt = nil
		return
	end
	local feetY = root.Position.Y - root.Size.Y * 0.5 - humanoid.HipHeight
	local here = Vector3.new(root.Position.X, feetY, root.Position.Z)
	local last = _lastPrintAt
	if last and (here - last).Magnitude < cfg.STEP then return end
	_lastPrintAt = here

	local look = root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	local sideways = Vector3.new(-flat.Z, 0, flat.X) * (0.45 * _printSide)
	_printSide = -_printSide
	local p = _prints[_nextPrint]
	_nextPrint = _nextPrint % #_prints + 1
	local at = here + sideways + Vector3.new(0, 0.03, 0)
	p.part.CFrame = CFrame.lookAt(at, at + flat)
	p.born = now
	if p.decal then (p.decal :: Decal).Transparency = 0 else p.part.Transparency = 0.25 end
	p.part.Parent = folder
end

-- Paket G (Event startet): Bienen in Sicht fliegen `seconds` lang zu `position`.
function LifeController.rally(position: Vector3, seconds: number)
	_rally = { position = position + Vector3.new(0, 4, 0), untilTime = os.clock() + seconds }
	assignSwarms()
end

--------------------------------------------------------------------------------
-- Einstieg
--------------------------------------------------------------------------------

function LifeController.init()
	if not FeatureFlags.isOn("WORLD_F_LIFE") then return end
	local folder = WorldFXKit.folder("Life", WorldFXKit.root())

	local bees = WorldFXKit.enabled("bees")
	local butterflies = WorldFXKit.enabled("butterflies")
	local sway = WorldFXKit.enabled("flowerSway")
	local prints = WorldFXKit.enabled("footprints")
	if bees then buildBees(WorldFXKit.folder("Bees", folder)) end
	if butterflies then buildButterflies(WorldFXKit.folder("Butterflies", folder)) end
	if sway then task.spawn(collectFlowers) end
	local printFolder = WorldFXKit.folder("Footprints", folder)
	if prints then buildPrints() end

	if not (bees or butterflies or sway or prints) then
		print("[Life] aus (niedrige Qualitaet)")
		return
	end

	local acc, assignAcc, clock = 0, 2, 0
	RunService.Heartbeat:Connect(function(dt: number)
		clock += dt
		acc += dt
		assignAcc += dt
		if acc < TICK then return end
		acc = 0
		local camera = workspace.CurrentCamera
		if not camera then return end
		local eye = camera.CFrame.Position

		if bees and assignAcc >= 2 then
			assignAcc = 0
			assignSwarms()
		end

		local parts: { BasePart } = {}
		local cframes: { CFrame } = {}
		if bees then stepBees(clock, TICK, parts, cframes) end
		if butterflies then stepButterflies(clock, eye, parts, cframes) end
		local character = localPlayer.Character
		if sway then
			local root = character and character:FindFirstChild("HumanoidRootPart")
			stepFlowers(clock, eye, if root and root:IsA("BasePart") then root else nil, parts, cframes)
		end
		if #parts > 0 then
			workspace:BulkMoveTo(parts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
		end
		if prints then stepPrints(printFolder, character) end
	end)

	print("[Life] aktiv | Bienen:", bees, "| Schmetterlinge:", butterflies, "| Blumen:", sway, "| Pfoten:", prints)
end

return LifeController
