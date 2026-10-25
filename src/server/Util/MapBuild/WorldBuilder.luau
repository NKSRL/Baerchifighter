--!strict
-- WorldBuilder.luau
-- ServerScriptService/Util/MapBuild/WorldBuilder.luau
--
-- Einzige Zustaendigkeit:
--   - Die feste Welt einmal beim Serverstart bauen: Wasser, Hauptinsel,
--     Plot- und Arena-Inseln samt Stegen, Blumen, Spawn, Honigmast, Event-Pit
--     und das globale Licht
--
-- Wird nur von MapService.init aufgerufen. Was pro Spieler gebaut wird, steht
-- in den anderen Buildern.
--
-- Teil von MapService: nur MapService (und die Builder untereinander)
-- benutzen dieses Modul. Es aendert keine Spielerdaten.

local Lighting            = game:GetService("Lighting")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MapConfig        = require(ReplicatedStorage.Config.MapConfig)
local FeatureFlags     = require(ReplicatedStorage.Config.FeatureFlags)
local MapStyleConfig   = require(ReplicatedStorage.Config.MapStyleConfig)

local MapParts = require(ServerScriptService.Util.MapBuild.MapParts)
local SkyBuilder = require(ServerScriptService.Util.MapBuild.SkyBuilder)
local ScenicBuilder = require(ServerScriptService.Util.MapBuild.ScenicBuilder)
local MapMeshes = require(ServerScriptService.Util.MapBuild.MapMeshes)
local HubPlazaBuilder = require(ServerScriptService.Util.MapBuild.HubPlazaBuilder)
local RocketIslandBuilder = require(ServerScriptService.Util.MapBuild.RocketIslandBuilder)   -- P4 Raketen-Insel

local WorldBuilder = {}

-- Liegt dieser Punkt auf einer der acht Bahnen von der Inselmitte zu einem Steg?
--
-- Blumen halten sich davon frei. NICHT weil sie im Weg waeren — sie
-- kollidieren nicht — sondern weil die freien Bahnen den Weg ZEIGEN: von der
-- Spawn-Mitte fuehrt zu jedem Steg eine blumenlose Gasse. Auf einer ringsum
-- gleich gruenen Insel ist das neben dem Honigmast die einzige Orientierung,
-- und sie kostet keine einzige zusaetzliche Part.
--
-- Die Bahn ist der Halbstreifen in Aussenrichtung des Plots: `along > 0` ist
-- "vor der Mitte", `across` der Abstand quer dazu.
function WorldBuilder.isOnBridgeLane(worldPosition: Vector3, margin: number): boolean
	local half = MapConfig.BRIDGE_WIDTH * 0.5 + margin

	for slot = 1, MapConfig.PLOT_COUNT do
		local outward = MapParts.outwardDirection(slot)
		local offset  = worldPosition - MapConfig.CENTER

		-- Abstand zur Steg-Achse: die Komponente quer zur Aussenrichtung.
		local along  = offset.X * outward.X + offset.Z * outward.Z
		local across = offset.X * outward.Z - offset.Z * outward.X

		if along > 0 and math.abs(across) <= half then
			return true
		end
	end
	return false
end

-- Blumen auf der freien Wiese der Hauptinsel. Rein optisch, damit die Flaeche
-- zwischen Spawn und Inselrand nicht leer wirkt. Deterministisch gesetzt
-- (fester Zufallsstartwert), damit die Welt bei jedem Server-Start gleich
-- aussieht — eine Map die sich bei jedem Neustart anders anfuehlt ist
-- verwirrend.
function WorldBuilder.buildFlowers(parent: Instance)
	if MapConfig.FLOWER_COUNT <= 0 then
		return
	end

	local random     = Random.new(MapConfig.FLOWER_SEED)
	-- Innere Kante ist jetzt der Rand des Event-Pits (frueher das kleine
	-- Spawn-Pad) — das Pit ist deutlich groesser, also braucht auch der freie
	-- Ring drumherum mehr Platz, sonst wuerden Blumen im Zaun stecken.
	local spawnEdge  = MapConfig.EVENT_PIT_RADIUS + 8
	local outerEdge  = MapConfig.PLATFORM_RADIUS - 12

	local stemY = MapConfig.PLATFORM_TOP_Y + MapConfig.FLOWER_STEM_SIZE.Y * 0.5
	local headY = MapConfig.PLATFORM_TOP_Y + MapConfig.FLOWER_STEM_SIZE.Y + MapConfig.FLOWER_HEAD_SIZE * 0.3

	local placed   = 0
	local attempts = 0

	-- Begrenzte Anzahl Versuche: liegt ein Los auf einem Steg, wird es
	-- verworfen statt verschoben — sonst haeuften sich die Blumen an den
	-- Steg-Kanten.
	while placed < MapConfig.FLOWER_COUNT and attempts < MapConfig.FLOWER_COUNT * 6 do
		attempts += 1

		local angle  = random:NextNumber(0, math.pi * 2)
		local radius = random:NextNumber(spawnEdge, outerEdge)
		local x = MapConfig.CENTER.X + radius * math.cos(angle)
		local z = MapConfig.CENTER.Z + radius * math.sin(angle)

		if not WorldBuilder.isOnBridgeLane(Vector3.new(x, MapConfig.PLATFORM_TOP_Y, z), 5) then
			local stem = MapParts.newPart(
				"FlowerStem",
				MapConfig.FLOWER_STEM_SIZE,
				CFrame.new(x, stemY, z),
				MapConfig.FLOWER_STEM_COLOR,
				Enum.Material.Grass
			)
			stem.CanCollide = false
			stem.Parent     = parent

			local color = MapConfig.FLOWER_COLORS[random:NextInteger(1, #MapConfig.FLOWER_COLORS)]
			local head = MapParts.newPart(
				"FlowerHead",
				Vector3.new(MapConfig.FLOWER_HEAD_SIZE, MapConfig.FLOWER_HEAD_SIZE, MapConfig.FLOWER_HEAD_SIZE),
				CFrame.new(x, headY, z),
				color,
				Enum.Material.SmoothPlastic
			)
			head.Shape      = Enum.PartType.Ball
			head.CanCollide = false
			head.Parent     = parent

			placed += 1
		end
	end
end

-- Das runde, eingezaeunte Podest in der Weltmitte (Tempel-Plaza + geschlossener
-- Sanktuarium-Zaunring, nur ueber die 8 Freitreppen der Alleen betretbar).
-- EventService faerbt Boden/Zaun/Ring waehrend eines Events um
-- (MapService.setEventPitTheme) und schreibt die Countdown-Tafel
-- (MapService.setEventBanner).
function WorldBuilder.buildEventPit(parent: Instance)
	local container = Instance.new("Model")
	container.Name   = "EventPit"
	container.Parent = parent

	local center       = MapConfig.CENTER
	local floorBottomY = MapConfig.PLATFORM_TOP_Y + MapConfig.EVENT_PIT_GROUND_CLEARANCE
	local floorY       = floorBottomY + MapConfig.EVENT_PIT_FLOOR_HEIGHT

	HubPlazaBuilder.buildEventPitPlaza(container)

	-- Anzeigetafel: anders als bei den Spieler-Arenen IMMER eingeblendet — sie
	-- ist der einzige Ort, an dem der Event-Countdown steht, egal ob gerade
	-- ein Event laeuft oder die naechste Wartezeit herunterzaehlt.
	local anchor = MapParts.newPart(
		"EventBannerAnchor",
		Vector3.new(1, 1, 1),
		CFrame.new(center.X, floorY + MapConfig.EVENT_PIT_BANNER_HEIGHT, center.Z),
		MapConfig.EVENT_PIT_DEFAULT_FLOOR_COLOR,
		Enum.Material.SmoothPlastic
	)
	anchor.Transparency = 1
	anchor.CanCollide   = false
	anchor.CanQuery     = false
	anchor.CanTouch     = false
	anchor.Parent       = container

	local banner = Instance.new("BillboardGui")
	banner.Name        = "Banner"
	banner.Size        = UDim2.fromScale(MapConfig.EVENT_PIT_BANNER_SIZE.X, MapConfig.EVENT_PIT_BANNER_SIZE.Y)
	banner.AlwaysOnTop = false
	banner.MaxDistance = MapConfig.EVENT_PIT_BANNER_DISTANCE
	banner.Adornee     = anchor
	banner.Enabled     = true
	banner.Parent      = anchor

	-- Drei feste Zeilen: Titel, Zeit, Belohnung.
	local bannerTitle = MapParts.newTextLabel("Title", banner, UDim2.fromScale(1, 0.45), UDim2.fromScale(0, 0))
	bannerTitle.Text  = "..."
	bannerTitle.TextColor3 = MapConfig.EVENT_PIT_BANNER_IDLE_COLOR
	MapParts.newTextLabel("Sub", banner, UDim2.fromScale(1, 0.3), UDim2.fromScale(0, 0.45))
	MapParts.newTextLabel("Reward", banner, UDim2.fromScale(1, 0.25), UDim2.fromScale(0, 0.75))
end

-- Eine Tafel auf der Hauptinsel (zwei Pfosten, ein Brett mit SurfaceGui:
-- Titel + cfg.lines Zeilen), Schrift nach aussen, mit Pavillon-Rahmen.
type BoardCfg = {
	angleDegrees : number,
	radius       : number,
	size         : Vector3,
	postHeight   : number,
	color        : Color3,
	textColor    : Color3,
	lines        : number,
}

local function buildBoard(parent: Instance, name: string, cfg: BoardCfg): BasePart
	local angle = math.rad(cfg.angleDegrees)
	local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local groundY = MapConfig.PLATFORM_TOP_Y
	local base = MapConfig.CENTER + outward * cfg.radius
	local center = Vector3.new(base.X, groundY + cfg.postHeight + cfg.size.Y * 0.5, base.Z)
	local frame = CFrame.lookAt(center, center + outward)

	local board = MapParts.newPart(name, cfg.size, frame, Color3.fromRGB(48, 43, 64), Enum.Material.Slate)
	board.CanCollide = true
	board.Parent = parent

	for _, side in { -1, 1 } do
		local postHeight = cfg.postHeight + cfg.size.Y
		local post = MapParts.newPart(
			name .. "Post",
			Vector3.new(0.95, postHeight, 0.95),
			frame * CFrame.new(side * (cfg.size.X * 0.5 - 0.5), -cfg.size.Y * 0.5 - cfg.postHeight + postHeight * 0.5, 0.7),
			Color3.fromRGB(48, 43, 64),
			Enum.Material.Slate
		)
		post.CanCollide = true
		post.Parent = parent
	end

	HubPlazaBuilder.decorateBoardPavilion(parent, name, frame, cfg.size, cfg.postHeight)

	local surface = Instance.new("SurfaceGui")
	surface.Name          = "Board"
	surface.Face          = Enum.NormalId.Front
	-- 21.10.: PixelsPerStud wirkt nur mit diesem SizingMode (sonst gestreckte Schrift)
	surface.SizingMode    = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 30
	surface.Adornee       = board
	surface.Parent        = board

	local title = MapParts.newTextLabel("Title", surface, UDim2.fromScale(1, 0.14), UDim2.fromScale(0, 0.01))
	title.TextColor3 = cfg.textColor
	title.Text = ""

	local lineHeight = 0.84 / cfg.lines
	for i = 1, cfg.lines do
		local line = MapParts.newTextLabel("Line" .. i, surface,
			UDim2.fromScale(0.94, lineHeight * 0.9), UDim2.fromScale(0.03, 0.15 + (i - 1) * lineHeight))
		line.TextXAlignment = Enum.TextXAlignment.Left
		line.TextColor3 = cfg.textColor
		line.Text = ""
	end

	return board
end

-- v15: die Bestenlisten-Tafel auf der Hauptinsel.
function WorldBuilder.buildLeaderboardBoard(parent: Instance, angleDegrees: number?, name: string?): BasePart
	local cfg = table.clone(MapConfig.LEADERBOARD_BOARD) :: any
	cfg.angleDegrees = angleDegrees or cfg.angleDegrees
	return buildBoard(parent, name or "LeaderboardBoard", cfg)
end

-- HBB Paket 6: Live-Kampf-Board (MapConfig.LIVE_BOARD)
function WorldBuilder.buildLiveBoard(parent: Instance): BasePart
	return buildBoard(parent, "LiveBoard", MapConfig.LIVE_BOARD :: any)
end

-- HBB Paket 6: Wespen-Nest am Honigmast (MapConfig.WASP_NEST). Skulptiertes
-- Koenigs-Hornissennest mit Chitin-Ringen, Goldkrone, leuchtendem Flugloch
-- und darueber dem Schild mit der Zeit bis zum Boss.
function WorldBuilder.buildWaspNest(parent: Instance, center: Vector3): Model
	local cfg = MapConfig.WASP_NEST
	local nest = Instance.new("Model")
	nest.Name = "WaspNest"

	local function piece(name: string, shape: Enum.PartType, size: Vector3, frame: CFrame, color: Color3, mat: Enum.Material?): BasePart
		local part = MapParts.newPart(name, size, frame, color, mat or Enum.Material.SmoothPlastic)
		part.Shape      = shape
		part.CanCollide = false
		part.CanQuery   = false
		part.CanTouch   = false
		part.CastShadow = false
		part.Parent     = nest
		return part
	end

	local body = piece("Body", Enum.PartType.Ball, cfg.bodySize, CFrame.new(center), cfg.color, Enum.Material.Sandstone)
	body.Material = Enum.Material.Sandstone

	-- Obere und untere Kappe + goldener Aufhaenge-Kronenring
	piece("CrownAttach", Enum.PartType.Cylinder,
		Vector3.new(0.45, cfg.bodySize.X * 0.52, cfg.bodySize.Z * 0.52),
		CFrame.new(center + Vector3.new(0, cfg.bodySize.Y * 0.46, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(238, 186, 52), Enum.Material.Metal)
	piece("BottomSpike", Enum.PartType.Ball,
		Vector3.new(cfg.bodySize.X * 0.45, cfg.bodySize.Y * 0.38, cfg.bodySize.Z * 0.45),
		CFrame.new(center + Vector3.new(0, -cfg.bodySize.Y * 0.44, 0)),
		cfg.stripeColor, Enum.Material.Slate)

	for i, spec in { { dy = 1.05, s = 0.88 }, { dy = 0.0, s = 1.02 }, { dy = -1.05, s = 0.86 } } do
		piece("Stripe" .. i, Enum.PartType.Cylinder,
			Vector3.new(0.38, cfg.bodySize.X * spec.s, cfg.bodySize.Z * spec.s),
			CFrame.new(center + Vector3.new(0, spec.dy, 0)) * CFrame.Angles(0, 0, math.rad(90)),
			cfg.stripeColor, Enum.Material.Slate)
	end

	local away = Vector3.new(cfg.offset.X, 0, cfg.offset.Z)
	away = if away.Magnitude > 1e-3 then away.Unit else Vector3.new(1, 0, 0)
	local holePos = center + away * (cfg.bodySize.X * 0.46) + Vector3.new(0, -0.85, 0)
	piece("HoleRim", Enum.PartType.Ball, Vector3.new(1.65, 1.65, 1.15),
		CFrame.lookAt(holePos, holePos + away),
		Color3.fromRGB(238, 186, 52), Enum.Material.Metal)
	piece("Hole", Enum.PartType.Ball, Vector3.new(1.25, 1.25, 1.25),
		CFrame.new(holePos + away * 0.12),
		cfg.stripeColor, Enum.Material.Slate)
	piece("HoleGlow", Enum.PartType.Ball, Vector3.new(0.75, 0.75, 0.75),
		CFrame.new(holePos + away * 0.22),
		cfg.glowColor, Enum.Material.Neon)

	local anchor = MapParts.newPart("SignAnchor", Vector3.new(1, 1, 1),
		CFrame.new(center + Vector3.new(0, cfg.bodySize.Y * 0.5 + cfg.signGap, 0)), cfg.glowColor, Enum.Material.SmoothPlastic)
	anchor.Transparency = 1
	anchor.CanCollide   = false
	anchor.CanQuery     = false
	anchor.CanTouch     = false
	anchor.Parent       = nest

	local sign = Instance.new("BillboardGui")
	sign.Name        = "Sign"
	sign.Size        = UDim2.fromScale(8, 2.2)
	sign.AlwaysOnTop = false
	sign.MaxDistance = cfg.signDistance
	sign.Adornee     = anchor
	sign.Parent      = anchor
	local title = MapParts.newTextLabel("Title", sign, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0))
	title.TextColor3 = cfg.glowColor
	title.Text = ""

	nest.Parent = parent
	return nest
end

function WorldBuilder.buildGlobalLighting()
	if Lighting:FindFirstChild("BaerchiBloom") then
		return   -- schon gesetzt
	end

	SkyBuilder.build()

	local bloom = Instance.new("BloomEffect")
	bloom.Name      = "BaerchiBloom"
	bloom.Intensity = MapConfig.LIGHTING_BLOOM_INTENSITY
	bloom.Threshold = MapConfig.LIGHTING_BLOOM_THRESHOLD
	bloom.Size      = MapConfig.LIGHTING_BLOOM_SIZE
	bloom.Parent    = Lighting

	local colorCorrection = Instance.new("ColorCorrectionEffect")
	colorCorrection.Name       = "BaerchiColorCorrection"
	colorCorrection.Saturation = MapConfig.LIGHTING_SATURATION
	colorCorrection.Contrast   = MapConfig.LIGHTING_CONTRAST
	colorCorrection.Parent     = Lighting

	local sunRays = Instance.new("SunRaysEffect")
	sunRays.Name      = "BaerchiSunRays"
	sunRays.Intensity = MapConfig.LIGHTING_SUNRAYS_INTENSITY
	sunRays.Spread    = MapConfig.LIGHTING_SUNRAYS_SPREAD
	sunRays.Parent    = Lighting
end

function WorldBuilder.buildPlatform()
	if workspace:FindFirstChild("Platform") then
		return   -- schon gebaut
	end

	local model = Instance.new("Model")
	model.Name = "Platform"

	local water = MapParts.newPart(
		"Water",
		Vector3.new(MapConfig.WATER_HEIGHT, MapConfig.WATER_RADIUS * 2, MapConfig.WATER_RADIUS * 2),
		CFrame.new(
			MapConfig.CENTER.X,
			MapConfig.PLATFORM_TOP_Y - MapConfig.WATER_DROP - MapConfig.WATER_HEIGHT * 0.5,
			MapConfig.CENTER.Z
		) * CFrame.Angles(0, 0, math.rad(90)),
		MapConfig.WATER_COLOR,
		Enum.Material.Water
	)
	water.Shape        = Enum.PartType.Cylinder
	water.Transparency = MapConfig.WATER_TRANSPARENCY
	water.CanQuery     = false
	water.Parent       = model

	-- Hauptinsel: strukturierte botanische Sanktuarium-Wiese mit Sandstein-Uferpromenade
	MapParts.buildIsland(
		model,
		"Ground",
		MapConfig.CENTER,
		MapConfig.PLATFORM_RADIUS,
		MapConfig.GRASS_DARK,
		Enum.Material.Grass
	)
	HubPlazaBuilder.buildMainIslandMeadow(model)

	-- Die acht Plot-Inseln und die geschwungenen Bogenbruecken dorthin.
	for slot = 1, MapConfig.PLOT_COUNT do
		local outward = MapParts.outwardDirection(slot)
		local center  = MapConfig.CENTER + outward * MapConfig.PLOT_RING_RADIUS

		MapParts.buildIsland(
			model,
			"PlotIsland_" .. slot,
			center,
			MapConfig.PLOT_ISLAND_RADIUS,
			MapConfig.PLOT_ISLAND_COLOR,
			Enum.Material.Grass
		)
		HubPlazaBuilder.buildPlotIslandGround(model, slot, center)

		HubPlazaBuilder.buildArchedBridge(
			model,
			"BridgeInner_" .. slot,
			outward,
			MapConfig.PLATFORM_RADIUS,
			MapConfig.PLOT_RING_RADIUS - MapConfig.PLOT_ISLAND_RADIUS
		)
	end

	WorldBuilder.buildFlowers(model)

	-- Das Event-Pit in der Mitte — siehe buildEventPit oben.
	WorldBuilder.buildEventPit(model)

	-- Koenigliches Honig-Heiligtum & Brunnen in der Weltmitte (unter dem Namen "Honigmast"
	-- fuer volle Kompatibilitaet mit DayCycleController, HubLandmarkController & Tests).
	local mast = Instance.new("Model")
	mast.Name = "Honigmast"
	HubPlazaBuilder.buildSanctuaryFountain(
		mast,
		Vector3.new(
			MapConfig.CENTER.X,
			MapConfig.PLATFORM_TOP_Y + MapConfig.EVENT_PIT_GROUND_CLEARANCE + MapConfig.EVENT_PIT_FLOOR_HEIGHT,
			MapConfig.CENTER.Z
		)
	)
	mast.Parent = model

	if not workspace:FindFirstChildOfClass("SpawnLocation") then
		local spawnPad = Instance.new("SpawnLocation")
		spawnPad.Name          = "FallbackSpawn"
		spawnPad.Size          = MapConfig.SPAWN_SIZE
		spawnPad.CFrame        = CFrame.new(
			MapConfig.CENTER.X,
			MapConfig.PLATFORM_TOP_Y + MapConfig.EVENT_PIT_GROUND_CLEARANCE + MapConfig.EVENT_PIT_FLOOR_HEIGHT + MapConfig.SPAWN_SIZE.Y * 0.5,
			MapConfig.CENTER.Z + MapConfig.EVENT_PIT_RADIUS * 0.5
		)
		spawnPad.Anchored      = true
		spawnPad.Transparency  = 1
		spawnPad.CanCollide    = false
		spawnPad.Color         = MapConfig.SPAWN_COLOR
		spawnPad.Material      = Enum.Material.SmoothPlastic
		spawnPad.TopSurface    = Enum.SurfaceType.Smooth
		spawnPad.BottomSurface = Enum.SurfaceType.Smooth
		spawnPad.Parent        = model
	end

	-- Landschafts-Deko (Meeresboden, Schaum, Alleen, Imker-Laternen, Brueckenportale, Baeume ...).
	ScenicBuilder.build(model, WorldBuilder.isOnBridgeLane)

	model.Parent = workspace
	print(
		"[MapService] Welt gebaut | Hauptinsel:", MapConfig.PLATFORM_RADIUS,
		"| Plot-Inseln:", MapConfig.PLOT_COUNT, "bei", MapConfig.PLOT_RING_RADIUS,
		"| Wasser:", MapConfig.WATER_RADIUS
	)
end

-- Nur Studio-Debug (D:Invoke("mapstyle")): Boden der Hauptinsel und die Vegetation
-- nach dem Schalter MAP_STYLE_V2 neu aufbauen.
function WorldBuilder.restyle(): (number, number)
	local model = workspace:FindFirstChild("Platform")
	if not model then return 0, 0 end

	for _, child in model:GetChildren() do
		if child.Name == "GrassTile" or child.Name:sub(1, 7) == "Meadow_" then
			child:Destroy()
		end
	end
	HubPlazaBuilder.buildMainIslandMeadow(model)
	local tiles = 0
	for _, child in model:GetChildren() do
		if child.Name:sub(1, 7) == "Meadow_" then tiles += 1 end
	end

	return tiles, ScenicBuilder.restyle(model, WorldBuilder.isOnBridgeLane)
end

return WorldBuilder
