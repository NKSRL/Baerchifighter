--!strict
-- WaterController.luau
-- StarterPlayerScripts/Controllers/WaterController.luau
--
-- Einzige Zustaendigkeit:
--   - Wasser und Kueste lebendig machen (Paket B, "Welt aufwerten"):
--     wanderndes Glitzern und Wellenlinien auf dem Wasser, Schaum-Textur auf
--     den Saeumen, Schaum und Stegpfosten an Arena-Inseln, springender
--     Honig-Fisch, schaukelnde Bonbon-Bojen
--
-- Alles nur auf dem Client: die Server-Teile (Wasser, Schaum-Scheiben)
-- bekommen hoechstens eine lokale Textur als Kind und eine lokale Farbe; neue
-- Teile entstehen in WorldFX_Local und werden nie repliziert. Das Teile-
-- Budget der Plot-Inseln (Server) bleibt unberuehrt.
--
-- Ohne hochgeladene Textur-IDs (WorldFXConfig.TEXTURE_IDS) gibt es kein
-- Glitzern, keine Wellen und keine Schaum-Textur: das Wasser bleibt wie
-- heute. Fisch, Bojen und Arena-Kueste laufen auch ohne Bilder.
--
-- PERFORMANCE: EIN Takt (WATER.TICK, 30x pro Sekunde) fuer Textur-Versatz,
-- Fisch und Bojen; die Arena-Kueste wird 2x pro Sekunde auf Sichtweite und
-- Besetzung geprueft. Ein Emitter (Spritzer), alle Teile aus festen Pools.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local AmbienceConfig = require(ReplicatedStorage.Config.AmbienceConfig)
local MapConfig      = require(ReplicatedStorage.Config.MapConfig)
local WorldFXConfig  = require(ReplicatedStorage.Config.WorldFXConfig)
local MapLayout      = require(ReplicatedStorage.Modules.MapLayout)
local FeatureFlags   = require(ReplicatedStorage.Config.FeatureFlags)

local WorldFXKit         = require(script.Parent.WorldFXKit)
local DayCycleController = require(script.Parent.DayCycleController)

local WaterController = {}

local WATER_Y = MapConfig.PLATFORM_TOP_Y - MapConfig.WATER_DROP
local FOAM_Y  = WATER_Y + 0.05
local UPRIGHT = WorldFXKit.UPRIGHT
local TOP_FACE = Enum.NormalId.Right   -- liegender Zylinder (UPRIGHT): +X zeigt nach oben

local _folder: Folder? = nil
local _glitter: Texture? = nil
local _waves: Texture? = nil
local _laces: { Texture } = {}

type Coast = { model: Model, occupied: boolean, shown: boolean, foam: BasePart, lace: Texture?, phase: number }
local _coasts: { [number]: Coast } = {}

type Buoy = { model: Model, base: CFrame, phase: number }
local _buoys: { Buoy } = {}

type Fish = { model: Model, active: boolean, start: number, from: Vector3, dir: Vector3 }
local _fish: Fish? = nil
local _nextFishAt = 0
local _splashAnchor: BasePart? = nil
local _splash: ParticleEmitter? = nil
local _ring: BasePart? = nil
local _ringDecal: Decal? = nil
local _ringStart = -math.huge

local _random = Random.new()

--------------------------------------------------------------------------------
-- Glitzern und Wellen
--------------------------------------------------------------------------------

local function newTexture(parent: Instance, name: string, id: string, tile: number, transparency: number): Texture
	local tex = Instance.new("Texture")
	tex.Name          = name
	tex.Texture       = id
	tex.Face          = TOP_FACE
	tex.StudsPerTileU = tile
	tex.StudsPerTileV = tile
	tex.Transparency  = transparency
	tex.Parent        = parent
	return tex
end

local function setupWater()
	local platform = workspace:WaitForChild("Platform", 60)
	local water = platform and platform:WaitForChild("Water", 30)
	if not (water and water:IsA("BasePart")) then return end
	local cfg = WorldFXConfig.WATER

	local glitterId = WorldFXKit.textureId("water_glitter")
	if glitterId and WorldFXKit.enabled("waterGlitter") then
		_glitter = newTexture(water, "Glitter", glitterId, cfg.GLITTER_TILE, cfg.GLITTER_TRANSPARENCY)
	end
	local wavesId = WorldFXKit.textureId("water_waves")
	if wavesId and WorldFXKit.enabled("waterWaves") then
		_waves = newTexture(water, "Waves", wavesId, cfg.WAVES_TILE, cfg.WAVES_TRANSPARENCY)
	end
end

--------------------------------------------------------------------------------
-- Schaum der festen Inseln (Server-Scheiben, lokal eingefaerbt)
--------------------------------------------------------------------------------

-- Gibt die Textur zurueck, falls es ein Schaum-Bild gibt. Die Scheibe wird
-- dann unsichtbar; das Atmen uebernimmt AmbienceController an der Textur.
local function dressFoam(part: BasePart): Texture?
	part.Color = WorldFXConfig.FOAM_COLOR
	local laceId = WorldFXKit.textureId("foam_lace")
	if not (laceId and WorldFXKit.enabled("foamTexture")) then
		return nil
	end
	local tex = newTexture(part, "FoamLace", laceId, WorldFXConfig.WATER.FOAM_TILE, part.Transparency)
	tex.Color3 = WorldFXConfig.FOAM_COLOR
	part.Transparency = 1
	table.insert(_laces, tex)
	return tex
end

local function setupFoam()
	local platform = workspace:WaitForChild("Platform", 60)
	local scenery = platform and platform:WaitForChild("Scenery", 30)
	local foam = scenery and scenery:WaitForChild("Foam", 30)
	if not foam then return end
	for _, child in foam:GetChildren() do
		if child:IsA("BasePart") then
			dressFoam(child)
		end
	end
end

--------------------------------------------------------------------------------
-- Arena-Insel und aeusserer Steg (pro besetztem Slot, lokal)
--------------------------------------------------------------------------------

local function buildCoast(slot: number): Coast
	local cfg = WorldFXConfig.ARENA_COAST
	local model = Instance.new("Model")
	model.Name = "ArenaCoast_" .. slot

	-- Schaum um die Arena-Insel: wie ScenicBuilder.buildFoam
	local center = MapLayout.pitCenter(slot)
	local radius = MapConfig.PIT_BASE_RADIUS + MapConfig.SHORE_WIDTH + AmbienceConfig.FOAM_REACH
	local foam = WorldFXKit.part("Foam", model, Vector3.new(0.1, radius * 2, radius * 2),
		CFrame.new(center.X, FOAM_Y, center.Z) * UPRIGHT, WorldFXConfig.FOAM_COLOR,
		Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	foam.Transparency = AmbienceConfig.FOAM_TRANSPARENCY
	local lace = dressFoam(foam)

	-- Pfosten mit Leuchtkappe an beiden Enden des aeusseren Stegs (wie
	-- ScenicBuilder.buildBridgePosts fuer die inneren Stege)
	local outward = MapLayout.outward(slot)
	local side = MapLayout.side(slot)
	local deckTop = MapConfig.PLATFORM_TOP_Y - MapConfig.BRIDGE_SINK
	local sideOffset = (MapConfig.BRIDGE_WIDTH + MapConfig.BRIDGE_RAIL_WIDTH) * 0.5
	local islandEdge = MapConfig.PLOT_RING_RADIUS + MapConfig.PLOT_ISLAND_RADIUS
	for _, r in { islandEdge + cfg.INSET, islandEdge + MapConfig.ISLAND_GAP - cfg.INSET } do
		for _, sign in { -1, 1 } do
			local p = MapConfig.CENTER + outward * r + side * (sign * sideOffset)
			WorldFXKit.pole("Post", model, Vector3.new(p.X, deckTop, p.Z), cfg.POST_HEIGHT, cfg.POST_DIAMETER,
				MapConfig.BRIDGE_RAIL_COLOR, Enum.Material.Wood)
			local cap = WorldFXKit.ball("Cap", model, cfg.CAP_SIZE,
				Vector3.new(p.X, deckTop + cfg.POST_HEIGHT + 0.5, p.Z), WorldFXConfig.LAMP_DAY, Enum.Material.Neon)
			DayCycleController.registerGlow(cap, WorldFXConfig.LAMP_DAY, WorldFXConfig.LAMP_NIGHT)
		end
	end

	return { model = model, occupied = false, shown = false, foam = foam, lace = lace, phase = slot * 0.8 + 0.4 }
end

local function slotOf(child: Instance): number?
	local n = string.match(child.Name, "^Plot_(%d+)$")
	return if n then tonumber(n) else nil
end

local function setOccupied(slot: number, occupied: boolean)
	if not WorldFXKit.enabled("arenaCoast") then return end
	local coast = _coasts[slot]
	if not coast then
		if not occupied then return end
		coast = buildCoast(slot)
		_coasts[slot] = coast
	end
	coast.occupied = occupied
end

-- 2x pro Sekunde: sichtbar = besetzt und in Sichtweite (Pool: das Model
-- bleibt erhalten und wird nur ein- und ausgehaengt).
local function refreshCoasts()
	local camera = workspace.CurrentCamera
	local folder = _folder
	if not (camera and folder) then return end
	local eye = camera.CFrame.Position
	for slot, coast in _coasts do
		local d = (MapLayout.pitCenter(slot) - eye).Magnitude
		local limit = WorldFXConfig.ARENA_COAST.SHOW_DISTANCE * (if coast.shown then 1 else 0.9)
		local want = coast.occupied and d <= limit
		if want ~= coast.shown then
			coast.shown = want
			coast.model.Parent = if want then folder else nil
		end
	end
end

--------------------------------------------------------------------------------
-- Bonbon-Bojen
--------------------------------------------------------------------------------

local function buildBuoys(folder: Instance)
	local cfg = WorldFXConfig.BUOYS
	local positions = MapLayout.buoys(cfg.RADIUS)
	local step = if WorldFXKit.quality() == 1 then 1 else 2
	for i = 1, #positions, step do
		local p = positions[i]
		local model = Instance.new("Model")
		model.Name = "Buoy"
		local s = cfg.SIZE
		WorldFXKit.ball("Body", model, s, p + Vector3.new(0, s * 0.25, 0), cfg.BODY_COLOR, Enum.Material.SmoothPlastic)
		WorldFXKit.part("Stripe", model, Vector3.new(s * 0.32, s * 1.02, s * 1.02),
			CFrame.new(p + Vector3.new(0, s * 0.3, 0)) * UPRIGHT, cfg.STRIPE_COLOR, Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
		WorldFXKit.ball("Knob", model, s * 0.38, p + Vector3.new(0, s * 0.8, 0), cfg.STRIPE_COLOR, Enum.Material.SmoothPlastic)
		model.Parent = folder
		table.insert(_buoys, { model = model, base = model:GetPivot(), phase = i * 1.7 })
	end
end

--------------------------------------------------------------------------------
-- Honig-Fisch
--------------------------------------------------------------------------------

local function buildFish(folder: Instance)
	local cfg = WorldFXConfig.FISH
	local model = Instance.new("Model")
	model.Name = "HoneyFish"
	-- Koerper: runder, goldglaenzender Ball (Laengsachse = Z), Schwanz, Flosse, Auge
	local body = WorldFXKit.ellipsoid("Body", model, Vector3.new(1.3, 1.5, 2.2), CFrame.new(), cfg.COLOR,
		Enum.Material.SmoothPlastic)
	body.Reflectance = 0.25
	WorldFXKit.part("Tail", model, Vector3.new(0.2, 1.4, 1.0), CFrame.new(0, 0, 1.35), cfg.FIN_COLOR, Enum.Material.SmoothPlastic)
	WorldFXKit.part("Fin", model, Vector3.new(0.15, 0.6, 0.8), CFrame.new(0, 0.8, 0.1), cfg.FIN_COLOR, Enum.Material.SmoothPlastic)
	for _, x in { -0.5, 0.5 } do
		WorldFXKit.ball("Eye", model, 0.28, Vector3.new(x, 0.25, -0.75), Color3.fromRGB(40, 28, 20), Enum.Material.SmoothPlastic)
	end
	model.PrimaryPart = body
	_fish = { model = model, active = false, start = 0, from = Vector3.zero, dir = Vector3.new(0, 0, -1) }

	-- Spritzer: ein Emitter, wird an Absprung- und Eintauchstelle gesetzt
	local anchor = WorldFXKit.anchor("SplashAnchor", folder, Vector3.new(1, 0.2, 1), Vector3.new(0, -200, 0))
	local emitter = Instance.new("ParticleEmitter")
	if WorldFXKit.applyParticleTexture(emitter, "splash_flipbook") then
		if emitter.FlipbookLayout ~= Enum.ParticleFlipbookLayout.None then
			emitter.FlipbookMode = Enum.ParticleFlipbookMode.OneShot   -- 4 Bilder ueber die Lebenszeit
		end
		emitter.Rate = 0
		emitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
		emitter.Lifetime = NumberRange.new(0.5, 0.8)
		emitter.Speed = NumberRange.new(4, 9)
		emitter.SpreadAngle = Vector2.new(35, 35)
		emitter.Acceleration = Vector3.new(0, -30, 0)
		emitter.EmissionDirection = Enum.NormalId.Top
		emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0.2) })
		emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		emitter.Parent = anchor
		_splash = emitter
	else
		emitter:Destroy()
	end
	_splashAnchor = anchor

	-- Ring auf der Oberflaeche: flache Scheibe; mit Ring-Bild nur das Bild
	local ring = WorldFXKit.part("Ring", nil, Vector3.new(0.05, 1, 1), CFrame.new(), Color3.new(1, 1, 1),
		Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
	local ringId = WorldFXKit.textureId("water_ring")
	if ringId then
		local decal = Instance.new("Decal")
		decal.Texture = ringId
		decal.Face = TOP_FACE
		decal.Parent = ring
		ring.Transparency = 1
		_ringDecal = decal
	end
	_ring = ring
end

local function splashAt(position: Vector3, folder: Instance)
	local anchor = _splashAnchor
	local emitter = _splash
	if anchor and emitter then
		anchor.Position = Vector3.new(position.X, WATER_Y + 0.2, position.Z)
		emitter:Emit(10)
	end
	local ring = _ring
	if ring then
		ring.CFrame = CFrame.new(position.X, WATER_Y + 0.06, position.Z) * UPRIGHT
		ring.Parent = folder
		_ringStart = os.clock()
	end
end

-- Neuer Sprung: offener Wasserpunkt vor der Kamera, sonst spaeter erneut.
local function startFish(folder: Instance): boolean
	local fish = _fish
	local camera = workspace.CurrentCamera
	if not (fish and camera) or fish.active then return false end
	local cfg = WorldFXConfig.FISH
	local look = camera.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.new(0, 0, -1)
	for _ = 1, 8 do
		local turn = _random:NextNumber(-0.6, 0.6)
		local dist = _random:NextNumber(cfg.DIST_MIN, cfg.DIST_MAX)
		local dir = CFrame.Angles(0, turn, 0):VectorToWorldSpace(flat)
		local p = camera.CFrame.Position + dir * dist
		local jumpAngle = _random:NextNumber(0, math.pi * 2)
		local jumpDir = Vector3.new(math.cos(jumpAngle), 0, math.sin(jumpAngle))
		local land = p + jumpDir * cfg.JUMP_LENGTH
		if MapLayout.isOpenWater(p.X, p.Z, cfg.WATER_MARGIN) and MapLayout.isOpenWater(land.X, land.Z, cfg.WATER_MARGIN) then
			fish.from = Vector3.new(p.X, WATER_Y, p.Z)
			fish.dir = jumpDir
			fish.start = os.clock()
			fish.active = true
			fish.model.Parent = folder
			splashAt(fish.from, folder)
			return true
		end
	end
	return false
end

local function stepFish(folder: Instance)
	local fish = _fish
	if not fish then return end
	local cfg = WorldFXConfig.FISH

	if fish.active then
		local t = (os.clock() - fish.start) / cfg.JUMP_TIME
		if t >= 1 then
			fish.active = false
			fish.model.Parent = nil
			splashAt(fish.from + fish.dir * cfg.JUMP_LENGTH, folder)
			_nextFishAt = os.clock() + _random:NextNumber(cfg.PAUSE_MIN, cfg.PAUSE_MAX)
		else
			-- Bogen: startet und endet knapp unter Wasser, Nase folgt der Bahn
			local height = cfg.JUMP_HEIGHT * 4 * t * (1 - t) - 0.8
			local pos = fish.from + fish.dir * (cfg.JUMP_LENGTH * t) + Vector3.new(0, height, 0)
			local slope = cfg.JUMP_HEIGHT * 4 * (1 - 2 * t) / cfg.JUMP_LENGTH
			local forward = (fish.dir + Vector3.new(0, slope, 0)).Unit
			fish.model:PivotTo(CFrame.lookAt(pos, pos + forward))
		end
	elseif os.clock() >= _nextFishAt then
		if not startFish(folder) then
			_nextFishAt = os.clock() + 5   -- kein Wasser in Sicht: gleich nochmal
		end
	end

	-- Ring waechst und verblasst
	local ring = _ring
	if ring and ring.Parent then
		local k = (os.clock() - _ringStart) / cfg.RING_TIME
		if k >= 1 then
			ring.Parent = nil
		else
			local size = 1 + cfg.RING_SIZE * k
			ring.Size = Vector3.new(0.05, size, size)
			local decal = _ringDecal
			if decal then
				decal.Transparency = k
			else
				ring.Transparency = 0.5 + 0.5 * k
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Einstieg
--------------------------------------------------------------------------------

function WaterController.init()
	if not FeatureFlags.isOn("WORLD_B_WATER") then return end
	local folder = WorldFXKit.folder("Water", WorldFXKit.root())
	_folder = folder

	task.spawn(setupWater)
	task.spawn(setupFoam)

	if WorldFXKit.enabled("buoys") then
		buildBuoys(folder)
	end
	if WorldFXKit.enabled("fish") then
		buildFish(folder)
		_nextFishAt = os.clock() + _random:NextNumber(WorldFXConfig.FISH.PAUSE_MIN * 0.5, WorldFXConfig.FISH.PAUSE_MAX * 0.5)
	end

	-- Besetzte Plots (Plot_N in workspace) bekommen ihre Arena-Kueste
	for _, child in workspace:GetChildren() do
		local slot = slotOf(child)
		if slot then setOccupied(slot, true) end
	end
	workspace.ChildAdded:Connect(function(child)
		local slot = slotOf(child)
		if slot then setOccupied(slot, true) end
	end)
	workspace.ChildRemoved:Connect(function(child)
		local slot = slotOf(child)
		if slot and not workspace:FindFirstChild(child.Name) then setOccupied(slot, false) end
	end)

	-- Debug (Studio): sofort einen Fisch springen lassen
	WorldFXKit.onDebug("DebugFish", function()
		_nextFishAt = 0
	end, false)

	local cfg = WorldFXConfig.WATER
	local buoyCfg = WorldFXConfig.BUOYS
	local acc, coastAcc, clock = 0, 0, 0
	local twoPi = math.pi * 2
	RunService.Heartbeat:Connect(function(dt: number)
		clock += dt
		acc += dt
		coastAcc += dt
		if coastAcc >= 0.5 then
			coastAcc = 0
			refreshCoasts()
		end
		if acc < cfg.TICK then return end
		acc = 0

		local day = DayCycleController.values()

		-- Glitzern und Wellen wandern in zwei Richtungen
		local glitter = _glitter
		if glitter then
			glitter.OffsetStudsU = (clock * cfg.GLITTER_SPEED.X) % cfg.GLITTER_TILE
			glitter.OffsetStudsV = (clock * cfg.GLITTER_SPEED.Y) % cfg.GLITTER_TILE
			glitter.Transparency = 1 - (1 - cfg.GLITTER_TRANSPARENCY) * day.glitter
			glitter.Color3 = day.glitterTint
		end
		local waves = _waves
		if waves then
			waves.OffsetStudsU = (clock * cfg.WAVES_SPEED.X) % cfg.WAVES_TILE
			waves.OffsetStudsV = (clock * cfg.WAVES_SPEED.Y) % cfg.WAVES_TILE
		end
		-- Schaum treibt ganz langsam (die festen Saeume atmet AmbienceController)
		for _, lace in _laces do
			lace.OffsetStudsU = (clock * cfg.FOAM_DRIFT) % cfg.FOAM_TILE
		end
		-- Arena-Schaum atmet wie die festen Saeume
		for _, coast in _coasts do
			if coast.shown then
				local value = AmbienceConfig.FOAM_TRANSPARENCY
					+ math.sin(clock / AmbienceConfig.FOAM_PULSE_PERIOD * twoPi + coast.phase) * AmbienceConfig.FOAM_PULSE
				local lace = coast.lace
				if lace then lace.Transparency = value else coast.foam.Transparency = value end
			end
		end

		-- Bojen schaukeln
		for _, buoy in _buoys do
			local w = clock * buoyCfg.ROCK_RATE * twoPi + buoy.phase
			buoy.model:PivotTo(buoy.base
				* CFrame.new(0, math.sin(w * 0.7) * buoyCfg.BOB_HEIGHT, 0)
				* CFrame.Angles(math.rad(buoyCfg.ROCK_DEGREES) * math.sin(w), 0, math.rad(buoyCfg.ROCK_DEGREES * 0.6) * math.cos(w * 0.8)))
		end

		stepFish(folder)
	end)

	print("[Water] aktiv | Glitzer-Bild:", WorldFXKit.textureId("water_glitter") ~= nil, "| Bojen:", #_buoys, "| Fisch:", _fish ~= nil)
end

return WaterController
