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

local MapParts = require(ServerScriptService.Util.MapBuild.MapParts)
local SkyBuilder = require(ServerScriptService.Util.MapBuild.SkyBuilder)
local ScenicBuilder = require(ServerScriptService.Util.MapBuild.ScenicBuilder)

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

-- Das runde, eingezaeunte Podest in der Weltmitte. Siehe MapConfig, Abschnitt
-- "EVENT-PIT" fuer das Warum der Zahlen. Normalerweise ein schlichter Stall —
-- EventService faerbt Boden/Zaun/Ring waehrend eines Events um
-- (MapService.setEventPitTheme) und schreibt die Countdown-Tafel
-- (MapService.setEventBanner).
--
-- Acht Zaunluecken statt einer: das Pit liegt in der Mitte ALLER acht Stege,
-- nicht am Ende von nur einem. Jede Luecke sitzt exakt in der Aussenrichtung
-- eines Plots (outwardDirection) — wer von seiner Bruecke kommt, laeuft
-- geradewegs hinein.
function WorldBuilder.buildEventPit(parent: Instance)
	local container = Instance.new("Model")
	container.Name   = "EventPit"
	container.Parent = parent

	local center = MapConfig.CENTER

	-- Unterkante des Podests: bewusst NICHT direkt auf PLATFORM_TOP_Y (dort
	-- liegt schon die Kachel-Oberseite, siehe EVENT_PIT_GROUND_CLEARANCE) —
	-- sonst flimmert der Podestrand mit dem Rasen darunter statt sauber
	-- darueber zu stehen.
	local floorBottomY = MapConfig.PLATFORM_TOP_Y + MapConfig.EVENT_PIT_GROUND_CLEARANCE
	local floorY       = floorBottomY + MapConfig.EVENT_PIT_FLOOR_HEIGHT   -- Podest-Oberflaeche

	local floor = MapParts.newPart(
		"EventFloor",
		Vector3.new(MapConfig.EVENT_PIT_FLOOR_HEIGHT, MapConfig.EVENT_PIT_RADIUS * 2, MapConfig.EVENT_PIT_RADIUS * 2),
		CFrame.new(center.X, floorY - MapConfig.EVENT_PIT_FLOOR_HEIGHT * 0.5, center.Z)
			* CFrame.Angles(0, 0, math.rad(90)),
		MapConfig.EVENT_PIT_DEFAULT_FLOOR_COLOR,
		Enum.Material.WoodPlanks
	)
	floor.Shape = Enum.PartType.Cylinder
	floor.Parent = container

	-- Sockel-Ring am Podestfuss: anders als bei den Spieler-Arenen (dort ein
	-- SUNKENER Pit mit einem Ring, der grossteils im Boden verschwindet) steht
	-- dieses Podest ueber dem Boden — der Ring sitzt deshalb komplett OBERHALB
	-- der Grasflaeche, direkt am Fuss der Podestwand, und ist als kleiner
	-- Sockel-Kranz ringsum sichtbar statt im Boden zu verschwinden. Bleibt im
	-- Stall-Look ein mattes Braun und glimmt erst waehrend eines Events
	-- (siehe setEventPitTheme).
	local ringRadius = MapConfig.EVENT_PIT_RADIUS + MapConfig.EVENT_PIT_RING_OVERHANG
	local ring = MapParts.newPart(
		"EventRing",
		Vector3.new(MapConfig.EVENT_PIT_RING_HEIGHT, ringRadius * 2, ringRadius * 2),
		CFrame.new(center.X, floorBottomY + MapConfig.EVENT_PIT_RING_HEIGHT * 0.5, center.Z)
			* CFrame.Angles(0, 0, math.rad(90)),
		MapConfig.EVENT_PIT_DEFAULT_RING_COLOR,
		Enum.Material.SmoothPlastic
	)
	ring.Shape      = Enum.PartType.Cylinder
	ring.CanCollide = false
	ring.CanQuery   = false
	ring.Parent     = container

	-- Eine Luecken-Mitte pro Plot-Richtung.
	local gapAngles: { number } = {}
	for slot = 1, MapConfig.PLOT_COUNT do
		local outward = MapParts.outwardDirection(slot)
		table.insert(gapAngles, math.atan2(outward.Z, outward.X))
	end

	local gap        = math.rad(MapConfig.EVENT_PIT_FENCE_GAP_DEGREES)
	local postRadius = MapConfig.EVENT_PIT_RADIUS - MapConfig.EVENT_PIT_FENCE_INSET
	local postY      = floorY + MapConfig.EVENT_PIT_FENCE_SIZE.Y * 0.5

	for i = 1, MapConfig.EVENT_PIT_FENCE_COUNT do
		local angle = (i - 1) * (2 * math.pi / MapConfig.EVENT_PIT_FENCE_COUNT)

		local blocked = false
		for _, gapAngle in gapAngles do
			local delta = math.abs(((angle - gapAngle + math.pi) % (2 * math.pi)) - math.pi)
			if delta <= gap then
				blocked = true
				break
			end
		end

		if not blocked then
			local post = MapParts.newPart(
				"EventFence_" .. i,
				MapConfig.EVENT_PIT_FENCE_SIZE,
				CFrame.new(
					center.X + postRadius * math.cos(angle),
					postY,
					center.Z + postRadius * math.sin(angle)
				),
				MapConfig.EVENT_PIT_DEFAULT_FENCE_COLOR,
				Enum.Material.Wood
			)
			-- Wie beim Zaun der Spieler-Arenen (PIT_FENCE): reine Silhouette,
			-- kein Hindernis. Acht schmalere Luecken statt einer breiten lassen
			-- sonst zu wenig Spielraum, falls ein Pfosten optisch knapp am
			-- Bruecken-Rand steht.
			post.CanCollide = false
			post.CanQuery   = false
			post.Parent     = container
		end
	end

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

	local bannerTitle = MapParts.newTextLabel("Title", banner, UDim2.fromScale(1, 0.6), UDim2.fromScale(0, 0))
	bannerTitle.Text  = "..."
	bannerTitle.TextColor3 = MapConfig.EVENT_PIT_BANNER_IDLE_COLOR
	MapParts.newTextLabel("Sub", banner, UDim2.fromScale(1, 0.4), UDim2.fromScale(0, 0.6))
end

-- Die ganze feste Welt: Wasser, Hauptinsel, die acht Plot-Inseln und die acht
-- Stege dazwischen, Blumen, Spawn und Honigmast. Wird nur EINMAL beim
-- Server-Start aufgerufen, nicht pro Spieler.
--
-- Globales Post-Processing: Bloom, Farbsaettigung, dezente Sonnenstrahlen.
--
-- Einmal in MapService.init() gesetzt, wirkt auf die GESAMTE Welt — kein
-- Aufwand pro Plot oder Figur. Siehe DESIGN_VORSCHLAG_TRENDANALYSE_2026-09-11.md
-- Abschnitt 5: der grosse Hebel hier ist nicht ein einzelner Effekt, sondern
-- dass es diese Objekte bisher ueberhaupt nicht gab — Lighting stand auf den
-- Roblox-Standardwerten.
--
-- Bewusst idempotent (FindFirstChild-Pruefung wie buildPlatform): ein
-- Server-Neustart im selben Studio-Prozess soll keine zweiten Kopien anlegen.
-- v15: die Bestenlisten-Tafel auf der Hauptinsel (zwei Pfosten, ein Brett mit
-- SurfaceGui: Titel + LEADERBOARD_BOARD.lines Zeilen). Beschriftet wird sie von
-- LeaderboardService ueber MapService.writeLeaderboardBoard.
function WorldBuilder.buildLeaderboardBoard(parent: Instance): BasePart
	local cfg = MapConfig.LEADERBOARD_BOARD
	local angle = math.rad(cfg.angleDegrees)
	local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local groundY = MapConfig.PLATFORM_TOP_Y
	local base = MapConfig.CENTER + outward * cfg.radius
	local center = Vector3.new(base.X, groundY + cfg.postHeight + cfg.size.Y * 0.5, base.Z)
	local frame = CFrame.lookAt(center, center + outward)

	local board = MapParts.newPart("LeaderboardBoard", cfg.size, frame, cfg.color, Enum.Material.Wood)
	board.CanCollide = true
	board.Parent = parent

	for _, side in { -1, 1 } do
		local postHeight = cfg.postHeight + cfg.size.Y
		local post = MapParts.newPart(
			"LeaderboardPost",
			Vector3.new(0.8, postHeight, 0.8),
			frame * CFrame.new(side * (cfg.size.X * 0.5 - 0.6), -cfg.size.Y * 0.5 - cfg.postHeight + postHeight * 0.5, 0.8),
			cfg.color,
			Enum.Material.Wood
		)
		post.CanCollide = true
		post.Parent = parent
	end

	local surface = Instance.new("SurfaceGui")
	surface.Name          = "Board"
	surface.Face          = Enum.NormalId.Front
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

function WorldBuilder.buildGlobalLighting()
	if Lighting:FindFirstChild("BaerchiBloom") then
		return   -- schon gesetzt
	end

	-- Himmel, Atmosphaere, Wolken, Tageszeit: siehe SkyBuilder / AmbienceConfig.
	-- (MapConfig.LIGHTING_CLOCK_TIME ist damit abgeloest: die Tageszeit steht
	-- jetzt in AmbienceConfig.CLOCK_TIME.)
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

-- WARUM DIE PLOT-INSELN HIER STEHEN UND NICHT BEI buildPlotBase:
-- Eine Insel gehoert zur Landschaft, nicht zum Spieler. Wuerden sie mit dem
-- Plot-Model eines Spielers entstehen und vergehen, waere die Welt bei zwei
-- Spielern ein Ozean mit zwei Inseln darin, und beim Verlassen verschwaende
-- mitten im Bild ein Stueck Land. Auf einer leeren Insel steht dann eben
-- nichts — den Weg dorthin gibt es trotzdem. Was dem SPIELER gehoert (Beet,
-- Zaun, Schild, Gebaeude, Arena), baut buildPlotBase darauf.
function WorldBuilder.buildPlatform()
	if workspace:FindFirstChild("Platform") then
		return   -- schon gebaut
	end

	local model = Instance.new("Model")
	model.Name = "Platform"

	-- Das Wasser zuerst: eine einzige grosse Scheibe unter allem.
	--
	-- Sie ist begehbar. Wer von einem Steg faellt, landet auf der Oberflaeche
	-- und laeuft zurueck, statt ins Leere zu stuerzen — in einem Spiel, in dem
	-- man staendig ueber schmale Stege laeuft, ist das die freundlichere
	-- Loesung (siehe MapConfig).
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

	-- Hauptinsel: dunkle Wiesenscheibe mit Sandkante, darauf die hellen Karos.
	MapParts.buildIsland(
		model,
		"Ground",
		MapConfig.CENTER,
		MapConfig.PLATFORM_RADIUS,
		MapConfig.GRASS_DARK,
		Enum.Material.Grass
	)
	MapParts.buildCheckerDisc(model, MapConfig.CENTER.X, MapConfig.CENTER.Z, MapConfig.PLATFORM_RADIUS)

	-- Die acht Plot-Inseln und die Stege dorthin.
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

		MapParts.buildSpan(
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

	-- Der Honigmast steht jetzt auf dem Event-Pit-Podest statt auf einem
	-- eigenen Spawn-Pad (das gibt es nicht mehr, siehe Not-Spawn unten) — er
	-- bleibt derselbe Orientierungspunkt, den man von jeder Insel aus sieht,
	-- nur jetzt mittig im Stall statt auf einer separaten Platte.
	local mast = Instance.new("Model")
	mast.Name = "Honigmast"
	MapParts.buildDecor(
		mast,
		CFrame.new(
			MapConfig.CENTER.X,
			MapConfig.PLATFORM_TOP_Y + MapConfig.EVENT_PIT_GROUND_CLEARANCE + MapConfig.EVENT_PIT_FLOOR_HEIGHT,
			MapConfig.CENTER.Z
		),
		MapConfig.CENTER_DECOR
	)
	mast.Parent = model

	-- Not-Spawn: seit dem Insel-Spawn (siehe buildPlotBase → PLAYER_SPAWN_OFFSET
	-- und PlayerService.onPlayerAdded) spawnt hier niemand mehr normalerweise.
	-- Der einzige Fall, der diesen Pad noch braucht, ist ein voller Server
	-- (MapService.spawnIsland findet keinen freien Slot mehr) — dann bekommt
	-- der Spieler nie ein RespawnLocation gesetzt und faellt auf den naechsten
	-- SpawnLocation in der Welt zurueck. Unsichtbar, damit er nicht als
	-- zweiter Bodenbelag unter dem Event-Pit durchscheint.
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

	-- Landschafts-Deko (Meeresboden, Schaum, Wege, Laternen, Baeume ...).
	ScenicBuilder.build(model, WorldBuilder.isOnBridgeLane)

	model.Parent = workspace
	print(
		"[MapService] Welt gebaut | Hauptinsel:", MapConfig.PLATFORM_RADIUS,
		"| Plot-Inseln:", MapConfig.PLOT_COUNT, "bei", MapConfig.PLOT_RING_RADIUS,
		"| Wasser:", MapConfig.WATER_RADIUS
	)
end

return WorldBuilder
