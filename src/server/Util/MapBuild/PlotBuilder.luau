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
local Loc       = require(ReplicatedStorage.Localization.Loc)
local Names     = require(ReplicatedStorage.Localization.Names)
local WorldText = require(ReplicatedStorage.Localization.WorldText)

local MapParts = require(ServerScriptService.Util.MapBuild.MapParts)

local PlotBuilder = {}

-- Royal-Honey-Sanktuarium Farbpalette fuer das Spieler-Heim-Plateau
local COL_CREAM_STONE  = Color3.fromRGB(238, 224, 192)
local COL_CREAM_LIGHT  = Color3.fromRGB(246, 236, 212)
local COL_DARK_SLATE   = Color3.fromRGB(48, 43, 64)
local COL_GOLD         = Color3.fromRGB(235, 180, 50)
local COL_HONEY_GLOW   = Color3.fromRGB(255, 200, 55)
local COL_WOOD_WARM    = Color3.fromRGB(165, 108, 56)
local COL_GRASS_DEEP   = Color3.fromRGB(68, 146, 66)
local COL_GRASS_MID    = Color3.fromRGB(78, 158, 72)
local COL_GRASS_SOFT   = Color3.fromRGB(84, 164, 76)

local function addDecorPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	shape: Enum.PartType?,
	canCollide: boolean?
): BasePart
	local p = MapParts.newPart(name, size, cframe, color, material)
	if shape then
		p.Shape = shape
	end
	local collide = if canCollide ~= nil then canCollide else false
	p.CanCollide = collide
	p.CanQuery   = collide
	p.CanTouch   = false
	p.CastShadow = false
	p.Parent     = parent
	return p
end

-- Sanktuarium-Gartenzaun rund um den Plot: auf einer niedrigen Creme-Sandstein-Mauer
-- stehen dunkle Schiefer-Pfeiler mit warmen Zedernholz-Bohlen, goldener Zierleiste
-- und vier leuchtenden Imker-Ecklaternen. Vorne (-Z) und hinten (+Z) schliessen
-- die Zaunfluegel direkt an die Torbogen-Saeulen (x = ±8.6) an.
function PlotBuilder.buildFence(plotModel: Model, slot: number)
	local plotCFrame = MapParts.plotCFrame(slot)
	local halfX = MapConfig.PLOT_SIZE.X * 0.5
	local halfZ = MapConfig.PLOT_SIZE.Z * 0.5

	local surfaceY      = MapParts.plotSurfaceOffset()
	local postH         = MapConfig.FENCE_POST_SIZE.Y + 0.35
	local postY         = surfaceY + postH * 0.5
	local steps         = 3
	local pillarX       = 8.6
	local wingSpan      = halfX - pillarX
	local wingCenterX   = (halfX + pillarX) * 0.5
	local railThickness = MapConfig.FENCE_POST_SIZE.X * 0.62

	for _, side in { -1, 1 } do
		-- Durchgehender Creme-Sandstein-Mauersockel an den beiden Laengsseiten
		addDecorPart(
			plotModel,
			"FencePlinth",
			Vector3.new(1.15, 0.85, MapConfig.PLOT_SIZE.Z),
			plotCFrame * CFrame.new(side * halfX, surfaceY + 0.425, 0),
			COL_CREAM_STONE,
			Enum.Material.Sandstone
		)

		for i = 0, steps do
			local z = -halfZ + (i / steps) * MapConfig.PLOT_SIZE.Z

			addDecorPart(
				plotModel,
				"FencePost",
				Vector3.new(1.15, postH, 1.15),
				plotCFrame * CFrame.new(side * halfX, postY, z),
				COL_DARK_SLATE,
				Enum.Material.Slate
			)

			-- Goldene Imker-Laternen auf den vier Eckpfosten
			if i == 0 or i == steps then
				addDecorPart(
					plotModel,
					"FenceCollar",
					Vector3.new(1.55, 0.42, 1.55),
					plotCFrame * CFrame.new(side * halfX, surfaceY + postH - 0.12, z),
					COL_GOLD,
					Enum.Material.Metal
				)

				addDecorPart(
					plotModel,
					"FenceCap",
					Vector3.new(1.65, 1.65, 1.65),
					plotCFrame * CFrame.new(side * halfX, surfaceY + postH + 0.58, z),
					COL_HONEY_GLOW,
					Enum.Material.Neon,
					Enum.PartType.Ball
				)
			end
		end

		-- Zwei durchgehende Honig-Zedernholz-Querlatten + goldene Kopfleiste
		for _, heightFactor in { 0.46, 0.82 } do
			local railY = surfaceY + postH * heightFactor
			addDecorPart(
				plotModel,
				"FenceRail",
				Vector3.new(railThickness, MapConfig.FENCE_RAIL_HEIGHT, MapConfig.PLOT_SIZE.Z),
				plotCFrame * CFrame.new(side * halfX, railY, 0),
				COL_WOOD_WARM,
				Enum.Material.WoodPlanks
			)
		end

		addDecorPart(
			plotModel,
			"FenceGold",
			Vector3.new(0.30, 0.14, MapConfig.PLOT_SIZE.Z),
			plotCFrame * CFrame.new(side * halfX, surfaceY + postH * 0.82 + MapConfig.FENCE_RAIL_HEIGHT * 0.5 + 0.07, 0),
			COL_GOLD,
			Enum.Material.Metal
		)

		-- Vorne (-Z) und hinten (+Z): Zaunfluegel von der Ecke bis direkt in die Torbogen-Saeule
		for _, zSign in { -1, 1 } do
			local zPos = zSign * halfZ

			addDecorPart(
				plotModel,
				"FencePlinth",
				Vector3.new(wingSpan, 0.85, 1.15),
				plotCFrame * CFrame.new(side * wingCenterX, surfaceY + 0.425, zPos),
				COL_CREAM_STONE,
				Enum.Material.Sandstone
			)

			local xPos = side * (pillarX + 0.5 * wingSpan)
			addDecorPart(
				plotModel,
				"FencePost",
				Vector3.new(1.15, postH, 1.15),
				plotCFrame * CFrame.new(xPos, postY, zPos),
				COL_DARK_SLATE,
				Enum.Material.Slate
			)

			for _, heightFactor in { 0.46, 0.82 } do
				local railY = surfaceY + postH * heightFactor
				addDecorPart(
					plotModel,
					"FenceRail",
					Vector3.new(wingSpan, MapConfig.FENCE_RAIL_HEIGHT, railThickness),
					plotCFrame * CFrame.new(side * wingCenterX, railY, zPos),
					COL_WOOD_WARM,
					Enum.Material.WoodPlanks
				)
			end
		end
	end
end

-- Strukturierte botanische Gartenflaeche & Royal-Honey-Wege auf dem 72x72-Plateau:
-- Alle Teile tragen das Praefix "StepStone_", damit Welt2Builder sie beim
-- Wechsel auf den Welt-2-Kristallboden automatisch aufraeumt.
function PlotBuilder.buildPlotPath(plotModel: Model, slot: number)
	local plotCFrame = MapParts.plotCFrame(slot)
	local topY = MapParts.plotSurfaceOffset()

	-- 1. Ruhige botanische Rasenspiegel + feiner Creme-Sandstein-Gartenrahmen
	addDecorPart(
		plotModel,
		"StepStone_LawnMid",
		Vector3.new(66.4, 0.03, 66.4),
		plotCFrame * CFrame.new(0, topY + 0.015, 0),
		COL_GRASS_MID,
		Enum.Material.Grass
	)
	addDecorPart(
		plotModel,
		"StepStone_LawnCenter",
		Vector3.new(48.0, 0.04, 52.0),
		plotCFrame * CFrame.new(0, topY + 0.02, 0),
		COL_GRASS_SOFT,
		Enum.Material.Grass
	)

	-- Vier eingelassene Sandstein-Randstreifen als edle Einfassung der Grünfläche
	for _, side in { -1, 1 } do
		addDecorPart(
			plotModel,
			"StepStone_Border",
			Vector3.new(1.2, 0.05, 67.6),
			plotCFrame * CFrame.new(side * 33.2, topY + 0.025, 0),
			COL_CREAM_LIGHT,
			Enum.Material.Sandstone
		)
		addDecorPart(
			plotModel,
			"StepStone_Border",
			Vector3.new(65.2, 0.05, 1.2),
			plotCFrame * CFrame.new(0, topY + 0.025, side * 33.2),
			COL_CREAM_LIGHT,
			Enum.Material.Sandstone
		)
	end

	-- 2. Durchgehende Royal-Honey-Gartenallee vom Eingangstor (-Z) zum Arenator (+Z)
	addDecorPart(
		plotModel,
		"StepStone_MainBed",
		Vector3.new(6.8, 0.06, 71.2),
		plotCFrame * CFrame.new(0, topY + 0.03, 0),
		COL_CREAM_STONE,
		Enum.Material.Sandstone
	)
	addDecorPart(
		plotModel,
		"StepStone_MainSlate",
		Vector3.new(4.8, 0.07, 70.8),
		plotCFrame * CFrame.new(0, topY + 0.035, 0),
		COL_DARK_SLATE,
		Enum.Material.Slate
	)

	-- 3. Zentrales Heimplatz-Wabenmedaillon bei (x = 0, z = 2) — genau dort, wo der
	--    Spieler beim Spawnen hinschaut und sein aktiver Baerchi Wache haelt
	local hubZ = 2
	addDecorPart(
		plotModel,
		"StepStone_HubStone",
		Vector3.new(0.08, 16.4, 16.4),
		plotCFrame * CFrame.new(0, topY + 0.04, hubZ) * CFrame.Angles(0, 0, math.rad(90)),
		COL_CREAM_STONE,
		Enum.Material.Sandstone,
		Enum.PartType.Cylinder
	)
	addDecorPart(
		plotModel,
		"StepStone_HubGold",
		Vector3.new(0.09, 13.6, 13.6),
		plotCFrame * CFrame.new(0, topY + 0.045, hubZ) * CFrame.Angles(0, 0, math.rad(90)),
		COL_GOLD,
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	)
	addDecorPart(
		plotModel,
		"StepStone_HubSlate",
		Vector3.new(0.10, 12.4, 12.4),
		plotCFrame * CFrame.new(0, topY + 0.05, hubZ) * CFrame.Angles(0, 0, math.rad(90)),
		COL_DARK_SLATE,
		Enum.Material.Slate,
		Enum.PartType.Cylinder
	)
	addDecorPart(
		plotModel,
		"StepStone_HubHoney",
		Vector3.new(0.11, 4.8, 4.8),
		plotCFrame * CFrame.new(0, topY + 0.055, hubZ) * CFrame.Angles(0, 0, math.rad(90)),
		COL_HONEY_GLOW,
		Enum.Material.Neon,
		Enum.PartType.Cylinder
	)

	-- 4. Einfassung des Honig-Teichs bei (x = 0, z = -14)
	local pondZ = -14
	addDecorPart(
		plotModel,
		"StepStone_PondStone",
		Vector3.new(0.08, 16.2, 16.2),
		plotCFrame * CFrame.new(0, topY + 0.04, pondZ) * CFrame.Angles(0, 0, math.rad(90)),
		COL_CREAM_STONE,
		Enum.Material.Sandstone,
		Enum.PartType.Cylinder
	)
	addDecorPart(
		plotModel,
		"StepStone_PondGold",
		Vector3.new(0.09, 14.6, 14.6),
		plotCFrame * CFrame.new(0, topY + 0.045, pondZ) * CFrame.Angles(0, 0, math.rad(90)),
		COL_GOLD,
		Enum.Material.Metal,
		Enum.PartType.Cylinder
	)

	-- 5. Seitenwege zu Brutkasten (-20, 20), Tower-Terminal (-12, -28) und Honig-Stationen
	local incStart = Vector3.new(0, topY + 0.03, 10)
	local incEnd   = Vector3.new(-20, topY + 0.03, 20)
	local incLen   = (incEnd - incStart).Magnitude
	local incCF    = plotCFrame * CFrame.lookAt((incStart + incEnd) * 0.5, incEnd)
	addDecorPart(plotModel, "StepStone_IncBed", Vector3.new(4.2, 0.06, incLen), incCF, COL_CREAM_STONE, Enum.Material.Sandstone)
	addDecorPart(plotModel, "StepStone_IncSlate", Vector3.new(2.8, 0.07, incLen - 0.6), incCF * CFrame.new(0, 0.005, 0), COL_DARK_SLATE, Enum.Material.Slate)

	addDecorPart(
		plotModel,
		"StepStone_TermBed",
		Vector3.new(12.0, 0.06, 4.0),
		plotCFrame * CFrame.new(-6.0, topY + 0.03, -28.0),
		COL_CREAM_STONE,
		Enum.Material.Sandstone
	)

	local stationPads: { { x: number, z: number, d: number } } = {
		{ x = -20, z = -14, d = 9.6 }, -- Kleewiese
		{ x = -20, z =   2, d = 9.6 }, -- Bienenstock
		{ x =  20, z =  -6, d = 9.6 }, -- Sonnenblumenbeet
	}
	for i, pad in stationPads do
		addDecorPart(
			plotModel,
			"StepStone_Pad" .. i,
			Vector3.new(0.07, pad.d, pad.d),
			plotCFrame * CFrame.new(pad.x, topY + 0.035, pad.z) * CFrame.Angles(0, 0, math.rad(90)),
			COL_CREAM_STONE,
			Enum.Material.Sandstone,
			Enum.PartType.Cylinder
		)
	end
end

-- Baut jeweils einen eindrucksvollen Royal-Honey-Sanktuarium-Torbogen vorne
-- (-Z, Richtung Hauptinsel, mit grosser Namenstafel "SignBoard" fuer Besitzername
-- und Tower-Rekord) und hinten (+Z, Richtung Arena-Steg, als Ehrenbogen).
-- Die Saeulen stehen bei x = ±8.6 direkt in der Flucht der vorderen/hinteren Zaeune.
function PlotBuilder.buildPlotSign(plotModel: Model, slot: number, ownerName: string)
	local plotCFrame = MapParts.plotCFrame(slot)
	local halfZ      = MapConfig.PLOT_SIZE.Z * 0.5
	local surfaceY   = MapParts.plotSurfaceOffset()

	local boardSize  = MapConfig.SIGN_BOARD_SIZE
	local pillarX    = 8.6
	local postHeight = 15.4

	local gates: { { z: number, boardName: string? } } = {
		{ z = -halfZ, boardName = "SignBoard" },
		{ z =  halfZ, boardName = nil },
	}

	for _, gate in gates do
		local archZ = gate.z

		-- Zwei Torbogen-Saeulen links und rechts neben dem Hauptweg (15+ Studs Durchgang)
		for _, side in { -1, 1 } do
			local px = side * pillarX

			addDecorPart(
				plotModel,
				"SignPlinth",
				Vector3.new(3.0, 2.0, 3.0),
				plotCFrame * CFrame.new(px, surfaceY + 1.0, archZ),
				COL_CREAM_STONE,
				Enum.Material.Sandstone
			)

			local post = MapParts.newPart(
				"SignPost",
				Vector3.new(MapConfig.SIGN_POST_SIZE.X + 0.15, postHeight, MapConfig.SIGN_POST_SIZE.Z + 0.15),
				plotCFrame * CFrame.new(px, surfaceY + postHeight * 0.5, archZ),
				COL_DARK_SLATE,
				Enum.Material.Slate
			)
			post.CanCollide = false
			post.Parent     = plotModel

			addDecorPart(
				plotModel,
				"SignCapital",
				Vector3.new(2.8, 0.85, 2.8),
				plotCFrame * CFrame.new(px, surfaceY + postHeight + 0.42, archZ),
				COL_GOLD,
				Enum.Material.Metal
			)

			-- Warme Honig-Laterne innen an jeder Saeule
			addDecorPart(
				plotModel,
				"SignLantern",
				Vector3.new(1.55, 1.95, 1.55),
				plotCFrame * CFrame.new(side * (pillarX - 1.3), surfaceY + 9.2, archZ),
				COL_HONEY_GLOW,
				Enum.Material.Neon,
				Enum.PartType.Ball
			)
		end

		-- Unterer Schiefer-Torbalken + Creme-Sandstein-Fries (ueber 10 Studs freie Durchgangshoehe)
		addDecorPart(
			plotModel,
			"SignArchBeam",
			Vector3.new(20.4, 1.15, 2.2),
			plotCFrame * CFrame.new(0, surfaceY + 10.6, archZ),
			COL_DARK_SLATE,
			Enum.Material.Slate
		)
		addDecorPart(
			plotModel,
			"SignFrieze",
			Vector3.new(19.6, 0.55, 1.85),
			plotCFrame * CFrame.new(0, surfaceY + 15.65, archZ),
			COL_CREAM_STONE,
			Enum.Material.Sandstone
		)

		-- Goldener Giebelbalken oben (SignTrim1) und goldene Einfassung unten (SignTrim2)
		addDecorPart(
			plotModel,
			"SignTrim1",
			Vector3.new(21.0, 0.9, 2.35),
			plotCFrame * CFrame.new(0, surfaceY + 16.3, archZ),
			COL_GOLD,
			Enum.Material.Metal
		)

		addDecorPart(
			plotModel,
			"SignTrim2",
			Vector3.new(boardSize.X + 0.8, 0.45, boardSize.Z + 0.5),
			plotCFrame * CFrame.new(0, surfaceY + 11.18, archZ),
			COL_GOLD,
			Enum.Material.Metal
		)

		-- Goldene Honigwaben-Krone auf dem Torbogen-Scheitel
		addDecorPart(
			plotModel,
			"SignCrown",
			Vector3.new(1.0, 3.8, 3.8),
			plotCFrame * CFrame.new(0, surfaceY + 17.6, archZ) * CFrame.Angles(0, math.rad(90), 0),
			COL_GOLD,
			Enum.Material.Metal,
			Enum.PartType.Cylinder
		)

		addDecorPart(
			plotModel,
			"SignCrownGem",
			Vector3.new(1.7, 1.7, 1.55),
			plotCFrame * CFrame.new(0, surfaceY + 17.6, archZ),
			COL_HONEY_GLOW,
			Enum.Material.Neon,
			Enum.PartType.Ball
		)

		-- Die grosse Namenstafel sitzt nur am vorderen Torbogen (-Z, Richtung Hauptinsel)
		if gate.boardName then
			local boardY = surfaceY + 13.5
			local board = MapParts.newPart(
				gate.boardName,
				boardSize,
				plotCFrame * CFrame.new(0, boardY, archZ),
				COL_DARK_SLATE,
				Enum.Material.Slate
			)
			board.CanCollide = false
			board.Parent     = plotModel

			-- Die Schrift kommt auf die Vorderseite (-Z) sowie auf die Rueckseite (+Z)
			local surface = Instance.new("SurfaceGui")
			surface.Name          = "SignText"
			surface.Face          = Enum.NormalId.Front
			-- 21.10.: ohne SizingMode ist die Flaeche fix 800x600 und wird auf das Brett gestreckt
			surface.SizingMode    = Enum.SurfaceGuiSizingMode.PixelsPerStud
			surface.PixelsPerStud = 45
			surface.Adornee       = board
			surface.Parent        = board

			local label = MapParts.newTextLabel("Owner", surface, UDim2.fromScale(0.92, 0.50), UDim2.fromScale(0.04, 0.06))
			label.TextColor3             = COL_CREAM_LIGHT
			label.TextStrokeColor3       = Color3.fromRGB(28, 20, 14)
			label.TextStrokeTransparency = 0.25
			label.Text                   = ownerName

			local divider = Instance.new("Frame")
			divider.Name             = "Divider"
			divider.Size             = UDim2.fromScale(0.76, 0.04)
			divider.Position         = UDim2.fromScale(0.12, 0.58)
			divider.BackgroundColor3 = COL_GOLD
			divider.BorderSizePixel  = 0
			divider.Parent           = surface

			local badge = MapParts.newTextLabel("TowerBadge", surface, UDim2.fromScale(0.92, 0.34), UDim2.fromScale(0.04, 0.63))
			badge.TextStrokeColor3       = Color3.fromRGB(28, 20, 14)
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

-- Die Plot-Platte samt Royal-Honey-Terrassenkante, Freitreppen, Zaun und Torbogen-Schild.
--
-- Das Besitzer-Attribut wird gesetzt BEVOR das Model in den Workspace kommt:
-- der Client bekommt es damit zusammen mit dem Model und muss nicht darauf
-- warten. WorldController haengt daran, ob er ueberhaupt einen Prompt baut.
function PlotBuilder.buildPlotBase(slot: number, owner: Player): Model
	local plotCFrame = MapParts.plotCFrame(slot)

	local model = Instance.new("Model")
	model.Name  = "Plot_" .. slot
	model:SetAttribute("PlotOwner", owner.UserId)

	-- Das Beet: eine erhabene 72x72-Gartenterrasse auf der Plot-Insel.
	-- Ruhiges, sattes Wiesen-Gruen ohne Noppen/Baseplate-Karos.
	local base = MapParts.newPart(
		"Base",
		MapConfig.PLOT_SIZE,
		plotCFrame * CFrame.new(0, MapConfig.PLOT_SIZE.Y * 0.5, 0),
		COL_GRASS_DEEP,
		Enum.Material.Grass
	)
	base.TopSurface    = Enum.SurfaceType.Smooth
	base.BottomSurface = Enum.SurfaceType.Smooth
	base.CanCollide    = true
	base.Parent        = model

	-- Gestufte Royal-Honey-Terrassenkante (Creme-Sandstein + dunkler Schiefer)
	-- samt Eckbastionen und breiten Freitreppen an den beiden Toren (-Z und +Z).
	-- Alle Teile beginnen mit "PlotCurb", damit Welt2Builder sie bei Welt-2-Aktivierung ausblendet.
	local halfX = MapConfig.PLOT_SIZE.X * 0.5
	local halfZ = MapConfig.PLOT_SIZE.Z * 0.5
	local curbY = MapConfig.PLOT_SIZE.Y * 0.5 + 0.04
	local curbH = MapConfig.PLOT_SIZE.Y + 0.08

	for _, side in { -1, 1 } do
		addDecorPart(
			model,
			"PlotCurb",
			Vector3.new(1.5, curbH, MapConfig.PLOT_SIZE.Z + 2.4),
			plotCFrame * CFrame.new(side * (halfX + 0.65), curbY, 0),
			COL_CREAM_STONE,
			Enum.Material.Sandstone
		)
		addDecorPart(
			model,
			"PlotCurb_Trim",
			Vector3.new(1.15, 0.28, MapConfig.PLOT_SIZE.Z + 2.1),
			plotCFrame * CFrame.new(side * (halfX + 0.55), MapConfig.PLOT_SIZE.Y + 0.08, 0),
			COL_DARK_SLATE,
			Enum.Material.Slate
		)

		for _, zSign in { -1, 1 } do
			addDecorPart(
				model,
				"PlotCurb",
				Vector3.new(27.8, curbH, 1.5),
				plotCFrame * CFrame.new(side * 22.5, curbY, zSign * (halfZ + 0.65)),
				COL_CREAM_STONE,
				Enum.Material.Sandstone
			)
			addDecorPart(
				model,
				"PlotCurb_Trim",
				Vector3.new(27.4, 0.28, 1.15),
				plotCFrame * CFrame.new(side * 22.5, MapConfig.PLOT_SIZE.Y + 0.08, zSign * (halfZ + 0.55)),
				COL_DARK_SLATE,
				Enum.Material.Slate
			)
			-- Eckbastion der Gartenterrasse
			addDecorPart(
				model,
				"PlotCurb_Corner",
				Vector3.new(3.2, curbH + 0.25, 3.2),
				plotCFrame * CFrame.new(side * (halfX + 0.35), curbY + 0.12, zSign * (halfZ + 0.35)),
				COL_CREAM_STONE,
				Enum.Material.Sandstone
			)
		end
	end

	-- Breite Sandstein-Freitreppen mit goldener Trittkante vor dem vorderen (-Z)
	-- und hinteren (+Z) Torbogen, damit der Spieler sanft auf das 2 Studs hohe Plateau laeuft
	-- Treppe zum Beet an beiden Steg-Achsen: zwei Stufen anteilig an der
	-- Beet-Hoehe (bei 2 Studs wie frueher 0,72 und 1,38). Seit 25.10. ist das
	-- Beet nur 0,5 hoch (PLOT_SIZE.Y): dann keine Stufen, man tritt direkt auf
	-- die Kante, und so flache Stufen liessen die Bordsteine des Vorplatzes
	-- (bis 0,39) durchstechen. Die Goldkante bleibt.
	local beetH  = MapConfig.PLOT_SIZE.Y
	local stairs = beetH > 1
	for _, zSign in { -1, 1 } do
		if stairs then
			addDecorPart(
				model,
				"PlotCurb_Stair",
				Vector3.new(15.4, beetH * 0.36, 3.4),
				plotCFrame * CFrame.new(0, beetH * 0.18, zSign * (halfZ + 1.55)),
				COL_CREAM_STONE,
				Enum.Material.Sandstone,
				nil,
				true
			)
			addDecorPart(
				model,
				"PlotCurb_Stair",
				Vector3.new(15.2, beetH * 0.69, 2.0),
				plotCFrame * CFrame.new(0, beetH * 0.345, zSign * (halfZ + 0.55)),
				COL_CREAM_LIGHT,
				Enum.Material.Sandstone,
				nil,
				true
			)
		end
		addDecorPart(
			model,
			"PlotCurb_StairGold",
			Vector3.new(15.0, 0.14, 0.45),
			plotCFrame * CFrame.new(0, MapConfig.PLOT_SIZE.Y + 0.03, zSign * (halfZ - 0.15)),
			COL_GOLD,
			Enum.Material.Metal
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
		and ((require(ReplicatedStorage.Config.FeatureFlags).isOn("NEW_MODELS_V3")
		and assets ~= nil and assets:FindFirstChild("Fountains") ~= nil)
		or require(ServerScriptService.Util.MapBuild.Welt2Builder).enabled(plotModel))   -- 21.10. Welt 2
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
