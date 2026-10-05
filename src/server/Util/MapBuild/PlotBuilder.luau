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
local BuildingBehavior = require(ReplicatedStorage.Config.BuildingBehavior)
local Types            = require(ReplicatedStorage.Network.Types)

local MapParts = require(ServerScriptService.Util.MapBuild.MapParts)

local PlotBuilder = {}

-- Zaun an den beiden Seiten des Plots. Vorne und hinten bleibt offen, sonst
-- kaeme man weder auf den Plot noch zur Bruecke.
function PlotBuilder.buildFence(plotModel: Model, slot: number)
	local plotCFrame = MapParts.plotCFrame(slot)
	local halfX = MapConfig.PLOT_SIZE.X * 0.5
	local halfZ = MapConfig.PLOT_SIZE.Z * 0.5

	local postY = MapParts.plotSurfaceOffset() + MapConfig.FENCE_POST_SIZE.Y * 0.5
	local steps = math.max(1, math.floor(MapConfig.PLOT_SIZE.Z / MapConfig.FENCE_POST_SPACING))

	for _, side in { -1, 1 } do
		for i = 0, steps do
			local z = -halfZ + (i / steps) * MapConfig.PLOT_SIZE.Z

			local post = MapParts.newPart(
				"FencePost",
				MapConfig.FENCE_POST_SIZE,
				plotCFrame * CFrame.new(side * halfX, postY, z),
				MapConfig.FENCE_COLOR,
				Enum.Material.Wood
			)
			post.CanCollide = false
			post.Parent     = plotModel
		end

		-- Zwei durchgehende Querlatten statt einzelner Segmente: ein Part
		-- statt acht, und optisch macht es keinen Unterschied.
		for _, heightFactor in { 0.45, 0.85 } do
			local railY = MapParts.plotSurfaceOffset() + MapConfig.FENCE_POST_SIZE.Y * heightFactor

			local rail = MapParts.newPart(
				"FenceRail",
				Vector3.new(MapConfig.FENCE_POST_SIZE.X * 0.6, MapConfig.FENCE_RAIL_HEIGHT, MapConfig.PLOT_SIZE.Z),
				plotCFrame * CFrame.new(side * halfX, railY, 0),
				MapConfig.FENCE_COLOR,
				Enum.Material.Wood
			)
			rail.CanCollide = false
			rail.Parent     = plotModel
		end
	end
end

-- Schild an der zur Mitte zeigenden Kante mit dem Namen des Besitzers.
-- v15: darunter ein kleines Tower-Symbol (hoechster Tower, siehe
-- writeOwnerBadge) — gesetzt von MapService, sobald der Tower-Stand bekannt ist.
function PlotBuilder.buildPlotSign(plotModel: Model, slot: number, ownerName: string)
	local plotCFrame = MapParts.plotCFrame(slot)
	local halfZ = MapConfig.PLOT_SIZE.Z * 0.5

	local boardSize = MapConfig.SIGN_BOARD_SIZE
	local postSize  = MapConfig.SIGN_POST_SIZE

	-- Zwei Pfosten an den Raendern, HINTER dem Brett (lokal +Z = weg von der
	-- Mitte; die Schrift zeigt nach -Z). So verdeckt kein Pfosten die Schrift.
	local postY = MapParts.plotSurfaceOffset() + postSize.Y * 0.5
	local behind = boardSize.Z * 0.5 + postSize.Z * 0.5
	for _, side in { -1, 1 } do
		local post = MapParts.newPart(
			"SignPost",
			postSize,
			plotCFrame * CFrame.new(side * (boardSize.X * 0.5 - postSize.X), postY, -halfZ + 2 + behind),
			MapConfig.SIGN_POST_COLOR,
			Enum.Material.Wood
		)
		post.CanCollide = false
		post.Parent     = plotModel
	end

	local boardY = MapParts.plotSurfaceOffset() + postSize.Y - boardSize.Y * 0.5
	local board = MapParts.newPart(
		"SignBoard",
		boardSize,
		plotCFrame * CFrame.new(0, boardY, -halfZ + 2),
		MapConfig.SIGN_COLOR,
		Enum.Material.Wood
	)
	board.CanCollide = false
	board.Parent     = plotModel

	-- Dunkle Leisten oben und unten (Rahmen statt nacktem Brett)
	for i, dy in { boardSize.Y * 0.5, -boardSize.Y * 0.5 } do
		local trim = MapParts.newPart(
			"SignTrim" .. i,
			Vector3.new(boardSize.X + 0.6, 0.45, boardSize.Z + 0.2),
			plotCFrame * CFrame.new(0, boardY + dy, -halfZ + 2),
			MapConfig.SIGN_TRIM_COLOR,
			Enum.Material.Wood
		)
		trim.CanCollide = false
		trim.Parent     = plotModel
	end

	-- Die Schrift kommt auf die Seite, die zur Plattform-Mitte zeigt. Das ist
	-- die lokale -Z-Seite des Plots und damit die Vorderseite des Boards.
	local surface = Instance.new("SurfaceGui")
	surface.Name        = "SignText"
	surface.Face        = Enum.NormalId.Front
	surface.PixelsPerStud = 40
	surface.Adornee     = board
	surface.Parent      = board

	local label = MapParts.newTextLabel("Owner", surface, UDim2.fromScale(0.9, 0.56), UDim2.fromScale(0.05, 0.08))
	label.TextColor3             = Color3.fromRGB(70, 50, 30)
	label.TextStrokeTransparency = 1
	label.Text                   = ownerName

	local badge = MapParts.newTextLabel("TowerBadge", surface, UDim2.fromScale(0.9, 0.28), UDim2.fromScale(0.05, 0.64))
	badge.TextStrokeTransparency = 1
	badge.Text                   = ""
end

-- v15: Tower-Symbol unter dem Besitzernamen ("◆ III · 42"). Billig, nur Text.
function PlotBuilder.writeOwnerBadge(plotModel: Model, text: string, color: Color3)
	local board = plotModel:FindFirstChild("SignBoard")
	local surface = board and board:FindFirstChild("SignText")
	local badge = surface and surface:FindFirstChild("TowerBadge")
	if badge and badge:IsA("TextLabel") then
		badge.Text       = text
		badge.TextColor3 = color
	end
end

-- Die Plot-Platte samt Zaun und Schild.
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

	MapParts.buildCheckerPlate(
		model,
		plotCFrame * CFrame.new(0, MapConfig.PLOT_SIZE.Y, 0),
		MapConfig.PLOT_SIZE.X,
		MapConfig.PLOT_SIZE.Z
	)

	model.PrimaryPart = base

	PlotBuilder.buildFence(model, slot)
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
		title.Text = string.format("%s  Lv.%d", config.displayName, buildingData.level)
	end

	local stock = sign:FindFirstChild("Stock")
	if stock and stock:IsA("TextLabel") then
		stock.Text = string.format("Honig %d / %d", honey, capacity)

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
	MapParts.buildDecor(part, ground, decor)
	PlotBuilder.addLookEffects(part, buildingData.id, look)

	PlotBuilder.buildHoneyDots(part, ground,
		math.min(BuildingBehavior.getMaxCapacity(buildingData.id), MapConfig.HONEY_DOT_MAX))

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
