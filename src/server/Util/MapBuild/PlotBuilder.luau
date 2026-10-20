--!strict
-- PlotBuilder.luau
-- ServerScriptService/Util/MapBuild/PlotBuilder.luau
--
-- Einzige Zustaendigkeit:
--   - Das Grundgeruest eines Spieler-Plots (Beet, Zaun, Schild) und die
--     Honig-Gebaeude mit Schild und Honig-Tropfen bauen und beschriften
--
-- Gebaeude bestehen aus einem unsichtbaren Koerper (Name, Level, Schild,
-- Client-Prompt) und der deklarativen Deko aus MapConfig.BUILDING_DECOR plus
-- den Zusaetzen ihres Looks (v15, MapConfig.getBuildingDecor). Der Look steht
-- als Attribut "Look" am Koerper — MapService baut ein Gebaeude nur neu, wenn
-- sich der Look aendert.
--
-- Teil von MapService: nur MapService (und die Builder untereinander)
-- benutzen dieses Modul. Es aendert keine Spielerdaten.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MapConfig        = require(ReplicatedStorage.Config.MapConfig)
local MapStyleConfig   = require(ReplicatedStorage.Config.MapStyleConfig)
local FeatureFlags     = require(ReplicatedStorage.Config.FeatureFlags)
local BuildingBehavior = require(ReplicatedStorage.Config.BuildingBehavior)
local Types            = require(ReplicatedStorage.Network.Types)
local Loc       = require(ReplicatedStorage.Localization.Loc)
local Names     = require(ReplicatedStorage.Localization.Names)
local WorldText = require(ReplicatedStorage.Localization.WorldText)

local MapParts = require(ServerScriptService.Util.MapBuild.MapParts)

local PlotBuilder = {}

-- Zaun rund um den Plot: an beiden Seiten durchgehend und vorne (-Z) sowie
-- hinten (+Z) von den Ecken bis direkt an die Torbogen-Saeulen (x = ±8.6),
-- sodass das gesamte Beet eingerahmt ist und nur die beiden Torboegen offen bleiben.
function PlotBuilder.buildFence(plotModel: Model, slot: number)
	local plotCFrame = MapParts.plotCFrame(slot)
	local halfX = MapConfig.PLOT_SIZE.X * 0.5
	local halfZ = MapConfig.PLOT_SIZE.Z * 0.5

	local surfaceY      = MapParts.plotSurfaceOffset()
	local postY         = surfaceY + MapConfig.FENCE_POST_SIZE.Y * 0.5
	local steps         = math.max(1, math.floor(MapConfig.PLOT_SIZE.Z / MapConfig.FENCE_POST_SPACING))
	local postColor     = Color3.fromRGB(122, 78, 42)
	local goldColor     = Color3.fromRGB(235, 180, 50)
	local pillarX       = 8.6
	local wingSpan      = halfX - pillarX
	local wingCenterX   = (halfX + pillarX) * 0.5
	local railThickness = MapConfig.FENCE_POST_SIZE.X * 0.62

	for _, side in { -1, 1 } do
		for i = 0, steps do
			local z = -halfZ + (i / steps) * MapConfig.PLOT_SIZE.Z

			local post = MapParts.newPart(
				"FencePost",
				MapConfig.FENCE_POST_SIZE,
				plotCFrame * CFrame.new(side * halfX, postY, z),
				postColor,
				Enum.Material.Wood
			)
			post.CanCollide = false
			post.Parent     = plotModel

			-- Goldene Honig-Kappen samt Metall-Kragen auf den vier Eckpfosten
			-- (Eingang von der Hauptinsel und Ausgang zur Arena), damit das Plot
			-- wie ein edel eingerahmtes Camp wirkt.
			if i == 0 or i == steps then
				local collar = MapParts.newPart(
					"FenceCollar",
					Vector3.new(MapConfig.FENCE_POST_SIZE.X + 0.35, 0.45, MapConfig.FENCE_POST_SIZE.Z + 0.35),
					plotCFrame * CFrame.new(side * halfX, surfaceY + MapConfig.FENCE_POST_SIZE.Y - 0.15, z),
					goldColor,
					Enum.Material.Metal
				)
				collar.CanCollide = false
				collar.CanQuery   = false
				collar.CanTouch   = false
				collar.CastShadow = false
				collar.Parent     = plotModel

				local capY = surfaceY + MapConfig.FENCE_POST_SIZE.Y + 0.55
				local cap = MapParts.newPart(
					"FenceCap",
					Vector3.new(1.65, 1.65, 1.65),
					plotCFrame * CFrame.new(side * halfX, capY, z),
					Color3.fromRGB(255, 200, 65),
					Enum.Material.Neon
				)
				cap.Shape      = Enum.PartType.Ball
				cap.CanCollide = false
				cap.CanQuery   = false
				cap.CanTouch   = false
				cap.CastShadow = false
				cap.Parent     = plotModel
			end
		end

		-- Zwei durchgehende Honig-Zedernholz-Querlatten an den beiden laengsseitigen Zaeunen
		for _, heightFactor in { 0.42, 0.82 } do
			local railY = surfaceY + MapConfig.FENCE_POST_SIZE.Y * heightFactor

			local rail = MapParts.newPart(
				"FenceRail",
				Vector3.new(railThickness, MapConfig.FENCE_RAIL_HEIGHT, MapConfig.PLOT_SIZE.Z),
				plotCFrame * CFrame.new(side * halfX, railY, 0),
				MapConfig.FENCE_COLOR,
				Enum.Material.WoodPlanks
			)
			rail.CanCollide = false
			rail.Parent     = plotModel
		end

		-- Vorne (-Z) und hinten (+Z): Zaunfluegel von der Ecke bis direkt in die Torbogen-Saeule
		for _, zSign in { -1, 1 } do
			local zPos = zSign * halfZ

			for step = 1, 2 do
				local xPos = side * (pillarX + (step / 3) * wingSpan)
				local wingPost = MapParts.newPart(
					"FencePost",
					MapConfig.FENCE_POST_SIZE,
					plotCFrame * CFrame.new(xPos, postY, zPos),
					postColor,
					Enum.Material.Wood
				)
				wingPost.CanCollide = false
				wingPost.Parent     = plotModel
			end

			for _, heightFactor in { 0.42, 0.82 } do
				local railY = surfaceY + MapConfig.FENCE_POST_SIZE.Y * heightFactor
				local wingRail = MapParts.newPart(
					"FenceRail",
					Vector3.new(wingSpan, MapConfig.FENCE_RAIL_HEIGHT, railThickness),
					plotCFrame * CFrame.new(side * wingCenterX, railY, zPos),
					MapConfig.FENCE_COLOR,
					Enum.Material.WoodPlanks
				)
				wingRail.CanCollide = false
				wingRail.Parent     = plotModel
			end
		end
	end
end

-- Trittstein-Gartenpfad auf dem 72x72-Beet: fuehrt das Auge (und die Fuesse)
-- vom inneren Steg direkt durch den Torbogen zum Honig-Brunnen/Baerchi-Platz
-- und weiter zum Arena-Steg sowie zu Inkubator und Recycler. Rein optisch (keine Kollision).
local STEP_STONES: { { x: number, z: number, r: number } } = {
	{ x =   0, z = -32, r = 3.5 },
	{ x =  -3, z = -23, r = 3.0 },
	{ x =  -8, z = -14, r = 3.0 },
	{ x =  -6, z =  -3, r = 3.2 },
	{ x =   0, z =   6, r = 4.2 },
	{ x =   0, z =  17, r = 3.2 },
	{ x =   3, z =  26, r = 3.0 },
	{ x =   0, z =  33, r = 3.4 },
	{ x =  12, z =   8, r = 2.8 },
}

function PlotBuilder.buildPlotPath(plotModel: Model, slot: number)
	local plotCFrame = MapParts.plotCFrame(slot)
	local y = MapParts.plotSurfaceOffset() + MapConfig.GRASS_HEIGHT + 0.04
	local stoneColor = Color3.fromRGB(228, 206, 162)

	for i, s in STEP_STONES do
		local stone = MapParts.newPart(
			"StepStone_" .. i,
			Vector3.new(0.12, s.r * 2, s.r * 2),
			plotCFrame * CFrame.new(s.x, y, s.z) * CFrame.Angles(0, 0, math.rad(90)),
			stoneColor,
			Enum.Material.Cobblestone
		)
		stone.Shape      = Enum.PartType.Cylinder
		stone.CanCollide = false
		stone.CanQuery   = false
		stone.CanTouch   = false
		stone.CastShadow = false
		stone.Parent     = plotModel
	end
end

-- Baut jeweils einen eindrucksvollen Torbogen vorne (-Z, Richtung Hauptinsel,
-- mit grosser Namenstafel "SignBoard" fuer Besitzername und Tower-Rekord) und
-- hinten (+Z, Richtung Arena-Steg, als reiner monumentaler Ehrenbogen ohne Namenstafel).
-- Die Saeulen stehen bei x = ±8.6 direkt in der Flucht der vorderen/hinteren Zaeune.
function PlotBuilder.buildPlotSign(plotModel: Model, slot: number, ownerName: string)
	local plotCFrame = MapParts.plotCFrame(slot)
	local halfZ      = MapConfig.PLOT_SIZE.Z * 0.5
	local surfaceY   = MapParts.plotSurfaceOffset()

	local boardSize  = MapConfig.SIGN_BOARD_SIZE
	local pillarX    = 8.6
	local postHeight = 15.2
	local goldColor  = Color3.fromRGB(235, 180, 50)
	local stoneColor = Color3.fromRGB(215, 198, 168)

	local gates: { { z: number, boardName: string? } } = {
		{ z = -halfZ, boardName = "SignBoard" },
		{ z =  halfZ, boardName = nil },
	}

	for _, gate in gates do
		local archZ = gate.z

		-- Zwei Torbogen-Saeulen links und rechts neben dem Hauptweg (15+ Studs Durchgang)
		for _, side in { -1, 1 } do
			local px = side * pillarX

			local plinth = MapParts.newPart(
				"SignPlinth",
				Vector3.new(2.8, 1.8, 2.8),
				plotCFrame * CFrame.new(px, surfaceY + 0.9, archZ),
				stoneColor,
				Enum.Material.Cobblestone
			)
			plinth.CanCollide = false
			plinth.CanQuery   = false
			plinth.CanTouch   = false
			plinth.CastShadow = false
			plinth.Parent     = plotModel

			local post = MapParts.newPart(
				"SignPost",
				Vector3.new(MapConfig.SIGN_POST_SIZE.X, postHeight, MapConfig.SIGN_POST_SIZE.Z),
				plotCFrame * CFrame.new(px, surfaceY + postHeight * 0.5, archZ),
				MapConfig.SIGN_POST_COLOR,
				Enum.Material.Wood
			)
			post.CanCollide = false
			post.Parent     = plotModel

			local capital = MapParts.newPart(
				"SignCapital",
				Vector3.new(2.6, 0.8, 2.6),
				plotCFrame * CFrame.new(px, surfaceY + postHeight + 0.4, archZ),
				goldColor,
				Enum.Material.Metal
			)
			capital.CanCollide = false
			capital.CanQuery   = false
			capital.CanTouch   = false
			capital.CastShadow = false
			capital.Parent     = plotModel

			-- Warme Honig-Laterne innen an jeder Saeule (direkt mit dem Pfosten verbunden)
			local lantern = MapParts.newPart(
				"SignLantern",
				Vector3.new(1.5, 1.9, 1.5),
				plotCFrame * CFrame.new(side * (pillarX - 1.25), surfaceY + 9.2, archZ),
				Color3.fromRGB(255, 205, 75),
				Enum.Material.Neon
			)
			lantern.Shape      = Enum.PartType.Ball
			lantern.CanCollide = false
			lantern.CanQuery   = false
			lantern.CanTouch   = false
			lantern.CastShadow = false
			lantern.Parent     = plotModel
		end

		-- Unterer Tor-Querbalken (ueber 10 Studs freie Durchgangshoehe)
		local archBeam = MapParts.newPart(
			"SignArchBeam",
			Vector3.new(20.0, 1.1, 2.0),
			plotCFrame * CFrame.new(0, surfaceY + 10.6, archZ),
			MapConfig.SIGN_POST_COLOR,
			Enum.Material.Wood
		)
		archBeam.CanCollide = false
		archBeam.CanQuery   = false
		archBeam.CanTouch   = false
		archBeam.CastShadow = false
		archBeam.Parent     = plotModel

		-- Goldener Giebelbalken oben (SignTrim1) und goldene Einfassung unten (SignTrim2)
		local trimTop = MapParts.newPart(
			"SignTrim1",
			Vector3.new(20.6, 0.9, 2.2),
			plotCFrame * CFrame.new(0, surfaceY + 16.2, archZ),
			goldColor,
			Enum.Material.Metal
		)
		trimTop.CanCollide = false
		trimTop.CanQuery   = false
		trimTop.CanTouch   = false
		trimTop.CastShadow = false
		trimTop.Parent     = plotModel

		local trimBot = MapParts.newPart(
			"SignTrim2",
			Vector3.new(boardSize.X + 0.8, 0.45, boardSize.Z + 0.5),
			plotCFrame * CFrame.new(0, surfaceY + 11.15, archZ),
			goldColor,
			Enum.Material.Metal
		)
		trimBot.CanCollide = false
		trimBot.CanQuery   = false
		trimBot.CanTouch   = false
		trimBot.CastShadow = false
		trimBot.Parent     = plotModel

		-- Goldene Honigwaben-Krone auf dem Torbogen-Scheitel
		local crown = MapParts.newPart(
			"SignCrown",
			Vector3.new(1.0, 3.6, 3.6),
			plotCFrame * CFrame.new(0, surfaceY + 17.5, archZ) * CFrame.Angles(0, math.rad(90), 0),
			goldColor,
			Enum.Material.Metal
		)
		crown.Shape      = Enum.PartType.Cylinder
		crown.CanCollide = false
		crown.CanQuery   = false
		crown.CanTouch   = false
		crown.CastShadow = false
		crown.Parent     = plotModel

		local crownGem = MapParts.newPart(
			"SignCrownGem",
			Vector3.new(1.6, 1.6, 1.5),
			plotCFrame * CFrame.new(0, surfaceY + 17.5, archZ),
			Color3.fromRGB(255, 220, 80),
			Enum.Material.Neon
		)
		crownGem.Shape      = Enum.PartType.Ball
		crownGem.CanCollide = false
		crownGem.CanQuery   = false
		crownGem.CanTouch   = false
		crownGem.CastShadow = false
		crownGem.Parent     = plotModel

		-- Die grosse Namenstafel sitzt nur am vorderen Torbogen (-Z, Richtung Hauptinsel)
		if gate.boardName then
			local boardY = surfaceY + 13.5
			local board = MapParts.newPart(
				gate.boardName,
				boardSize,
				plotCFrame * CFrame.new(0, boardY, archZ),
				MapConfig.SIGN_COLOR,
				Enum.Material.Wood
			)
			board.CanCollide = false
			board.Parent     = plotModel

			-- Die Schrift kommt auf die Vorderseite (-Z) sowie auf die Rueckseite (+Z)
			local surface = Instance.new("SurfaceGui")
			surface.Name          = "SignText"
			surface.Face          = Enum.NormalId.Front
			surface.PixelsPerStud = 45
			surface.Adornee       = board
			surface.Parent        = board

			local label = MapParts.newTextLabel("Owner", surface, UDim2.fromScale(0.92, 0.50), UDim2.fromScale(0.04, 0.06))
			label.TextColor3             = Color3.fromRGB(55, 35, 18)
			label.TextStrokeColor3       = Color3.fromRGB(255, 220, 125)
			label.TextStrokeTransparency = 0.35
			label.Text                   = ownerName

			local divider = Instance.new("Frame")
			divider.Name             = "Divider"
			divider.Size             = UDim2.fromScale(0.76, 0.04)
			divider.Position         = UDim2.fromScale(0.12, 0.58)
			divider.BackgroundColor3 = goldColor
			divider.BorderSizePixel  = 0
			divider.Parent           = surface

			local badge = MapParts.newTextLabel("TowerBadge", surface, UDim2.fromScale(0.92, 0.34), UDim2.fromScale(0.04, 0.63))
			badge.TextStrokeColor3       = Color3.fromRGB(35, 22, 12)
			badge.TextStrokeTransparency = 0.15
			badge.Text                   = ""

			local backSurface = surface:Clone()
			backSurface.Name = "SignTextBack"
			backSurface.Face = Enum.NormalId.Back
			backSurface.Parent = board
		end
	end
end

-- v15: Tower-Symbol unter dem Besitzernamen ("◆ III · 42") am vorderen Torbogen. Billig, nur Text.
function PlotBuilder.writeOwnerBadge(plotModel: Model, text: string | Types.LocMsg, color: Color3)
	local board = plotModel:FindFirstChild("SignBoard")
	if board then
		for _, guiName in { "SignText", "SignTextBack" } do
			local surface = board:FindFirstChild(guiName)
			local badge = surface and surface:FindFirstChild("TowerBadge")
			if badge and badge:IsA("TextLabel") then
				WorldText.set(badge, text)
				badge.TextColor3 = color
			end
		end
	end
end

-- Die Plot-Platte samt Terrassen-Einfassung, Zaun und Torbogen-Schild.
--
-- Das Besitzer-Attribut wird gesetzt BEVOR das Model in den Workspace kommt:
-- der Client bekommt es damit zusammen mit dem Model und muss nicht darauf
-- warten. WorldController haengt daran, ob er ueberhaupt einen Prompt baut.
function PlotBuilder.buildPlotBase(slot: number, owner: Player): Model
	local plotCFrame = MapParts.plotCFrame(slot)

	local model = Instance.new("Model")
	model.Name  = "Plot_" .. slot
	model:SetAttribute("PlotOwner", owner.UserId)

	-- Das Beet: eine quadratische Platte auf der Plot-Insel. Dunkles Gruen wie
	-- die Hauptinsel, darauf dieselben hellen Karos — nur plot-lokal gerastert,
	-- weil das Beet je nach Plot in einem anderen Winkel steht.
	local base = MapParts.newPart(
		"Base",
		MapConfig.PLOT_SIZE,
		plotCFrame * CFrame.new(0, MapConfig.PLOT_SIZE.Y * 0.5, 0),
		MapConfig.GRASS_DARK,
		Enum.Material.Grass
	)
	base.CanCollide = true
	base.Parent     = model

	-- Old-School-Boden (P1): das Beet ist selbst die Baseplate (Plastic, grau, echte
	-- Noppen). Ohne diese Zeilen deckt das Gras-Beet samt Karos den Noppen-Boden zu.
	local studBed = FeatureFlags.isOn("MAP_GROUND_OLDSCHOOL") and not MapStyleConfig.STUD_GROUND.MODERN
	if studBed then
		base.Material   = Enum.Material.Plastic
		base.Color      = MapStyleConfig.GROUND.PLOT_COLOR
		base.TopSurface = Enum.SurfaceType.Studs
		-- Schachbrett: jedes zweite Feld etwas dunkler, als duenne Platten mit Noppen obendrauf
		local cfg   = MapStyleConfig.GROUND
		local n     = math.max(1, math.floor(MapConfig.PLOT_SIZE.X / cfg.PLOT_TILE))
		local step  = MapConfig.PLOT_SIZE.X / n
		local dark  = Color3.new(cfg.PLOT_COLOR.R * (1 - cfg.ALT_TON), cfg.PLOT_COLOR.G * (1 - cfg.ALT_TON), cfg.PLOT_COLOR.B * (1 - cfg.ALT_TON))
		for i = 0, n - 1 do
			for j = 0, n - 1 do
				if (i + j) % 2 == 1 then
					local tile = MapParts.newPart(
						"BedTile",
						Vector3.new(step, 0.1, step),
						plotCFrame * CFrame.new((i - (n - 1) * 0.5) * step, MapConfig.PLOT_SIZE.Y + 0.05, (j - (n - 1) * 0.5) * step),
						dark,
						Enum.Material.Plastic
					)
					tile.TopSurface = Enum.SurfaceType.Studs
					tile.CanCollide = false
					tile.CanQuery   = false
					tile.CanTouch   = false
					tile.CastShadow = false
					tile.Parent     = model
				end
			end
		end
	end

	-- Steinerne Garten-Terrassenkante rund um das 72x72-Beet (vorne und hinten
	-- in der Mitte fuer Steg und Torbogen offen gelassen, damit keine Stufe entsteht).
	local halfX     = MapConfig.PLOT_SIZE.X * 0.5
	local halfZ     = MapConfig.PLOT_SIZE.Z * 0.5
	local curbY     = MapConfig.PLOT_SIZE.Y * 0.5 + 0.06
	local curbH     = MapConfig.PLOT_SIZE.Y + 0.12
	local curbColor = Color3.fromRGB(215, 198, 168)

	for _, side in { -1, 1 } do
		local sideCurb = MapParts.newPart(
			"PlotCurb",
			Vector3.new(1.0, curbH, MapConfig.PLOT_SIZE.Z + 2.0),
			plotCFrame * CFrame.new(side * (halfX + 0.5), curbY, 0),
			curbColor,
			Enum.Material.Cobblestone
		)
		sideCurb.CanCollide = false
		sideCurb.CanQuery   = false
		sideCurb.CanTouch   = false
		sideCurb.CastShadow = false
		sideCurb.Parent     = model

		for _, zSign in { -1, 1 } do
			local endCurb = MapParts.newPart(
				"PlotCurb",
				Vector3.new(27.0, curbH, 1.0),
				plotCFrame * CFrame.new(side * 22.5, curbY, zSign * (halfZ + 0.5)),
				curbColor,
				Enum.Material.Cobblestone
			)
			endCurb.CanCollide = false
			endCurb.CanQuery   = false
			endCurb.CanTouch   = false
			endCurb.CastShadow = false
			endCurb.Parent     = model
		end
	end

	if not studBed then
		MapParts.buildCheckerPlate(
			model,
			plotCFrame * CFrame.new(0, MapConfig.PLOT_SIZE.Y, 0),
			MapConfig.PLOT_SIZE.X,
			MapConfig.PLOT_SIZE.Z
		)
	end

	model.PrimaryPart = base

	PlotBuilder.buildFence(model, slot)
	PlotBuilder.buildPlotPath(model, slot)
	PlotBuilder.buildPlotSign(model, slot, owner.DisplayName)

	-- Der Spieler spawnt (und respawnt nach dem Tod) auf seiner EIGENEN
	-- Insel statt in der Weltmitte — siehe MapConfig.PLAYER_SPAWN_OFFSET fuer
	-- die Wahl der Stelle. Unsichtbar: sie soll wie ein normaler Fleck Wiese
	-- aussehen, kein Extra-Bodenbelag auf dem Plot.
	--
	-- `owner.RespawnLocation` direkt zu setzen (statt sich auf Roblox' eigene
	-- Naechste-SpawnLocation-Auswahl zu verlassen) ist entscheidend: mit acht
	-- SpawnLocations in der Welt (eine pro Plot) waere sonst nicht garantiert,
	-- dass ein Spieler nach dem Tod bei SEINER eigenen landet.
	--
	-- newPart baut nur ein normales Part — eine SpawnLocation braucht die
	-- eigene Roblox-Klasse (Instance.new("SpawnLocation")), deshalb hier von
	-- Hand statt ueber das gemeinsame Util.
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name          = "PlayerSpawn"
	spawnLocation.Size          = Vector3.new(6, 1, 6)
	spawnLocation.CFrame        = plotCFrame * CFrame.new(
		MapConfig.PLAYER_SPAWN_OFFSET.X,
		MapParts.plotSurfaceOffset() + MapConfig.PLAYER_SPAWN_OFFSET.Y + 0.5,
		MapConfig.PLAYER_SPAWN_OFFSET.Z
	)
	spawnLocation.Anchored      = true
	spawnLocation.CanCollide    = false
	spawnLocation.CanQuery      = false
	spawnLocation.Neutral       = true
	spawnLocation.Transparency  = 1
	spawnLocation.Duration      = 0   -- keine Unverwundbarkeits-Phase, das Spiel kennt kein PvP am Spawn
	spawnLocation.Parent        = model

	owner.RespawnLocation = spawnLocation

	model.Parent = workspace

	return model
end

-- Die Honig-Tropfen am Fuss eines Gebaeudes einmalig anlegen. Sie werden
-- danach nur noch ein- und ausgeblendet (writeBuildingState), nie neu gebaut:
-- ein Neuaufbau alle 20 Sekunden mal drei Gebaeude mal acht Spieler waere
-- fuer reine Deko viel zu teuer.
--
-- `ground` ist die Mitte der Grundflaeche des Gebaeudes, also derselbe
-- Ursprung wie fuer die Deko.
--
-- `slots` ist das GROESSTE Lager, das dieses Gebaeude je haben kann — nicht
-- sein aktuelles —, seit v15 aber hoechstens MapConfig.HONEY_DOT_MAX (das Lager
-- des Bienenstocks waechst bis 39). Ueberzaehlige Tropfen stoeren nicht:
-- sichtbar ist ein Tropfen erst, wenn wirklich Honig drin liegt
-- (writeBuildingState).
function PlotBuilder.buildHoneyDots(body: BasePart, ground: CFrame, slots: number)
	if slots <= 0 then return end

	-- Fester Abstand, bis der maximale Bogen erreicht ist — dann ruecken die
	-- Tropfen zusammen, statt sich um das ganze Gebaeude zu wickeln.
	local arc = math.min(
		math.rad(MapConfig.HONEY_DOT_ARC),
		math.rad(MapConfig.HONEY_DOT_SPACING) * math.max(1, slots - 1)
	)

	for i = 1, slots do
		-- Bogen mittig um -Z herum. Bei nur einem Punkt gibt es nichts zu
		-- verteilen — dann steht er genau vorne.
		local t     = if slots > 1 then (i - 1) / (slots - 1) - 0.5 else 0
		local angle = t * arc

		local offset = Vector3.new(
			math.sin(angle) * MapConfig.HONEY_DOT_RADIUS,
			MapConfig.HONEY_DOT_HEIGHT,
			-math.cos(angle) * MapConfig.HONEY_DOT_RADIUS
		)

		local dot = MapParts.newPart(
			"HoneyDot" .. i,
			Vector3.new(MapConfig.HONEY_DOT_SIZE, MapConfig.HONEY_DOT_SIZE, MapConfig.HONEY_DOT_SIZE),
			ground * CFrame.new(offset),
			MapConfig.HONEY_DOT_COLOR,
			Enum.Material.Neon
		)
		dot.Shape        = Enum.PartType.Ball
		dot.Transparency = 1        -- Startzustand: leeres Lager
		dot.CanCollide   = false
		dot.CanQuery     = false
		dot.CanTouch     = false
		dot.Parent       = body
	end
end

-- Alles am Gebaeude, was sich im Betrieb aendert: Schildtext, Honig-Tropfen
-- und der Vorrats-Wert fuer den Fuetter-Prompt. Getrennt vom Aufbau, weil das
-- bei JEDER Honig-Aenderung laeuft (siehe updateBuildingSigns) und deshalb
-- billig bleiben muss.
function PlotBuilder.writeBuildingState(part: BasePart, buildingData: Types.Building, pool: number)
	local config = MapConfig.BUILDING_OFFSETS[buildingData.id]
	if not config then return end

	-- Attribut statt eigenem Remote: der Client haengt seinen Fuetter-Prompt
	-- daran und bekommt jede Aenderung ohne Zutun mit.
	part:SetAttribute("HoneyPool", pool)

	-- Lager DIESES Gebaeudes auf DIESEM Level — beim Bienenstock waechst es mit.
	local capacity = BuildingBehavior.getCapacity(buildingData.id, buildingData.level)
	local honey    = math.clamp(buildingData.honey or 0, 0, capacity)

	-- Ein Tropfen pro eingelagertem Honig. Es koennen mehr Tropfen dastehen als
	-- das aktuelle Lager fasst (gebaut wird nach dem Maximal-Lager) — die
	-- ueberzaehligen bleiben unsichtbar. v15: ist das Lager groesser als
	-- HONEY_DOT_MAX, steht ein Tropfen fuer einen ANTEIL (voll = alle an).
	local dotCount = math.min(BuildingBehavior.getMaxCapacity(buildingData.id), MapConfig.HONEY_DOT_MAX)
	local lit = if capacity <= MapConfig.HONEY_DOT_MAX
		then honey
		else math.ceil(honey * MapConfig.HONEY_DOT_MAX / math.max(1, capacity))
	for i = 1, dotCount do
		local dot = part:FindFirstChild("HoneyDot" .. i)
		if dot and dot:IsA("BasePart") then
			dot.Transparency = if i <= lit then 0 else 1
		end
	end

	local sign = part:FindFirstChild("Sign")
	if not sign or not sign:IsA("BillboardGui") then return end

	local title = sign:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		WorldText.set(title, Loc.msg("ui.world.sign_level", {
			name = Names.msg.building(buildingData.id), level = buildingData.level,
		}))
	end

	local stock = sign:FindFirstChild("Stock")
	if stock and stock:IsA("TextLabel") then
		stock.Text = string.format("🍯 %d / %d", honey, capacity)   -- sprachneutral (2.4)

		-- Volles Lager faellt farblich auf: dann steht die Produktion und es
		-- wird Zeit, zurueckzukommen und zu fuettern.
		stock.TextColor3 = if honey >= capacity
			then Color3.fromRGB(255, 215, 100)
			else Color3.fromRGB(235, 235, 235)
	end
end

-- Ein Gebaeude auf dem Plot.
-- Der Name der Part ist die BuildingId — der Client (WorldController) findet
-- darueber das Gebaeude fuer den ProximityPrompt.
--
-- Die Part selbst ist seit v5 unsichtbar und kollidiert nicht: sie ist nur
-- noch Trefferflaeche fuer den Prompt sowie Traeger von Name, Attribut und
-- Schild. Zu SEHEN und anzustossen ist ausschliesslich die Deko. Getrennt,
-- weil das Anklickbare und das Huebsche zwei verschiedene Dinge sind — sonst
-- muesste jede Formaenderung Ruecksicht auf die Trefferflaeche nehmen.
-- Partikel-Effekte des Looks an die gerade gebauten Deko-Teile haengen
-- (MapConfig.BUILDING_LOOK_FX / FX_PRESETS). Fehlt ein Teil, wird der Effekt
-- still uebersprungen — der Test honey_pond.test.lua faengt das vorher ab.
function PlotBuilder.addLookEffects(body: BasePart, buildingId: string, look: number)
	for _, fx in MapConfig.getLookFx(buildingId, look) do
		local target = body:FindFirstChild(fx.piece)
		local preset = MapConfig.FX_PRESETS[fx.preset]
		if target and target:IsA("BasePart") and preset then
			local emitter = Instance.new("ParticleEmitter")
			emitter.Name          = "Fx_" .. fx.preset
			emitter.Texture       = preset.texture
			emitter.Color         = ColorSequence.new(preset.color)
			emitter.Size          = NumberSequence.new(preset.size[1], preset.size[2])
			emitter.Transparency  = NumberSequence.new(preset.transparency[1], preset.transparency[2])
			emitter.Lifetime      = NumberRange.new(preset.lifetime[1], preset.lifetime[2])
			emitter.Rate          = preset.rate
			emitter.Speed         = NumberRange.new(preset.speed[1], preset.speed[2])
			emitter.SpreadAngle   = Vector2.new(preset.spread, preset.spread)
			emitter.Acceleration  = preset.acceleration
			emitter.EmissionDirection = (Enum.NormalId :: any)[preset.emitFrom]
			emitter.LightEmission = preset.lightEmission
			emitter.Parent        = target
		end
	end
end

function PlotBuilder.buildBuilding(plotModel: Model, slot: number, buildingData: Types.Building, pool: number)
	local config = MapConfig.BUILDING_OFFSETS[buildingData.id]
	if not config then return end

	local plotCFrame = MapParts.plotCFrame(slot)
	local localY = MapParts.plotSurfaceOffset() + config.offset.Y + config.size.Y * 0.5

	local part = MapParts.newPart(
		buildingData.id,
		config.size,
		plotCFrame * CFrame.new(config.offset.X, localY, config.offset.Z),
		config.color,
		Enum.Material.SmoothPlastic
	)
	part.Transparency = 1
	part.CanCollide   = false
	part.Parent       = plotModel

	-- Ursprung von Deko UND Honig-Tropfen: Mitte der Grundflaeche des Gebaeudes
	-- auf Plot-Hoehe.
	local ground = plotCFrame * CFrame.new(
		config.offset.X,
		MapParts.plotSurfaceOffset() + config.offset.Y,
		config.offset.Z
	)

	-- v15: Grund-Deko plus die Zusaetze des aktuellen Looks.
	local look  = BuildingBehavior.getLook(buildingData.level)
	local decor = MapConfig.getBuildingDecor(buildingData.id, look)
	-- NEW_MODELS_V3: der Honig-Brunnen kommt als Modell aus PondBuilder
	-- (Assets.Fountains); die alte Teile-Deko wuerde ihn ueberlagern.
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local fountainModel = buildingData.id == "HoneyPond"
		and require(ReplicatedStorage.Config.FeatureFlags).isOn("NEW_MODELS_V3")
		and assets ~= nil and assets:FindFirstChild("Fountains") ~= nil
	if not fountainModel then
		MapParts.buildDecor(part, ground, decor)
		PlotBuilder.addLookEffects(part, buildingData.id, look)

		PlotBuilder.buildHoneyDots(part, ground,
			math.min(BuildingBehavior.getMaxCapacity(buildingData.id), MapConfig.HONEY_DOT_MAX))
	end

	-- Level als Attribut: der Client kann es direkt auslesen ohne eigenes Remote
	part:SetAttribute("BuildingLevel", buildingData.level)
	part:SetAttribute("Look", look)

	-- Schild ueber dem Gebaeude: Name, Level und Honig-Lagerstand. Ohne das
	-- muesste man fuer die Frage "ist schon wieder Honig da?" jedes Mal ein
	-- Panel oeffnen.
	--
	-- Die Hoehe richtet sich nach dem hoechsten Deko-Teil, nicht nach der
	-- Koerpergroesse: sonst haengt das Schild nach jeder Formaenderung falsch.
	-- StudsOffset zaehlt ab der MITTE der Part, deshalb die Halbierung.
	local topOfDecor = math.max(MapParts.decorHeight(decor), config.size.Y)

	-- Sammel-Update 2.6 ("UI von Honig-Sumpf weg"): der Honig-Teich bekommt
	-- kein Schild — der Baerchi isst dort von selbst (Autopilot), Text und
	-- Zahlen braucht dort niemand. writeBuildingState kommt ohne Schild aus.
	if buildingData.id == "HoneyPond" then
		PlotBuilder.writeBuildingState(part, buildingData, pool)
		return
	end

	local sign = Instance.new("BillboardGui")
	sign.Name         = "Sign"
	sign.Size         = UDim2.fromScale(9, 2.6)
	sign.StudsOffset  = Vector3.new(0, topOfDecor - config.size.Y * 0.5 + 2, 0)
	sign.AlwaysOnTop  = false
	sign.MaxDistance  = MapConfig.BUILDING_SIGN_DISTANCE
	sign.Adornee      = part
	sign.Parent       = part

	MapParts.newTextLabel("Title", sign, UDim2.fromScale(1, 0.5), UDim2.fromScale(0, 0))
	MapParts.newTextLabel("Stock", sign, UDim2.fromScale(1, 0.5), UDim2.fromScale(0, 0.5))

	PlotBuilder.writeBuildingState(part, buildingData, pool)
end

return PlotBuilder
