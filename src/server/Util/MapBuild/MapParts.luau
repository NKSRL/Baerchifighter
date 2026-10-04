--!strict
-- MapParts.luau
-- ServerScriptService/Util/MapBuild/MapParts.luau
--
-- Einzige Zustaendigkeit:
--   - Bausteine, die alle Map-Builder teilen: Plot-Lage (CFrame, Richtung
--     nach aussen, Arena-Mitte), einfache Parts und Beschriftungen, Inseln,
--     Karo-Wiese, Stege und deklarative Deko aus MapConfig
--
-- Reine Bau-Funktionen ohne Zustand ausser einem Cache der Plot-CFrames (die
-- sich nie aendern). Alle Masse kommen aus MapConfig.
--
-- Teil von MapService: nur MapService (und die Builder untereinander)
-- benutzen dieses Modul. Es aendert keine Spielerdaten.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")

local MapConfig        = require(ReplicatedStorage.Config.MapConfig)

local MapParts = {}

-- Plot-CFrames pro Slot. Sie haengen nur an MapConfig und aendern sich nie,
-- deshalb einmal berechnet und gemerkt.
local _plotCFrames: { [number]: CFrame } = {}

-- Das CFrame eines Plots: steht auf dem Ring und schaut zur Plattform-Mitte.
-- Dadurch ist lokales -Z immer "Richtung Mitte" und +Z immer "nach aussen",
-- egal bei welchem der 8 Winkel der Plot liegt.
function MapParts.buildPlotCFrame(slot: number): CFrame
	local angle = math.rad((slot - 1) * (360 / MapConfig.PLOT_COUNT))
	local position = Vector3.new(
		MapConfig.CENTER.X + MapConfig.PLOT_RING_RADIUS * math.cos(angle),
		MapConfig.PLATFORM_TOP_Y,
		MapConfig.CENTER.Z + MapConfig.PLOT_RING_RADIUS * math.sin(angle)
	)

	return CFrame.lookAt(position, Vector3.new(MapConfig.CENTER.X, position.Y, MapConfig.CENTER.Z))
end

-- Richtung "nach aussen" fuer einen Plot (XZ-Einheitsvektor vom Mittelpunkt weg)
function MapParts.outwardDirection(slot: number): Vector3
	local position = MapParts.plotCFrame(slot).Position
	local flat = Vector3.new(position.X - MapConfig.CENTER.X, 0, position.Z - MapConfig.CENTER.Z)
	if flat.Magnitude < 1e-3 then
		return Vector3.new(1, 0, 0)   -- Sicherheitsnetz, sollte nie vorkommen
	end
	return flat.Unit
end

-- Hoehe der begehbaren Plot-Oberflaeche ueber dem Plot-CFrame-Ursprung.
-- Der Ursprung liegt auf der Plattform-Oberkante, die Plot-Platte liegt
-- darauf — alles was auf dem Plot steht, startet also hier.
function MapParts.plotSurfaceOffset(): number
	return MapConfig.PLOT_SIZE.Y
end

function MapParts.newPart(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name          = name
	part.Size          = size
	part.CFrame        = cframe
	part.Anchored      = true
	part.Material      = material
	part.Color         = color
	part.TopSurface    = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- Eine runde Insel: Sandkante plus die eigentliche Oberflaeche.
--
-- Der Trick fuer die Sandkante ist, dass sie KEIN Ring ist, sondern eine
-- breitere Scheibe, die ein Stueck tiefer liegt. Sichtbar bleibt nur ihr
-- ueberstehender Rand — ein echter Ring waere ein Dutzend Segmente fuer
-- dasselbe Bild, und an jeder Naht eine Kante, an der man haengen bleibt.
--
-- Ein Cylinder-Part liegt in Roblox von Haus aus entlang X; damit er flach
-- liegt, wird er um 90 Grad um Z gekippt. Seine Size ist dann
-- (Dicke, Durchmesser, Durchmesser) — dieselbe Stolperfalle wie bei den
-- Deko-Zylindern in der Config.
-- `drop` senkt die Oberflaeche der Insel ab (Standard 0, also buendig mit
-- PLATFORM_TOP_Y). Gebraucht wird das nur von der Arena-Insel: auf ihr liegt
-- noch die Kampfflaeche, und zwei deckungsgleiche Oberseiten wuerden
-- flimmern — siehe MapConfig.PIT_RIM_DROP.
function MapParts.buildIsland(
	parent: Instance,
	name: string,
	center: Vector3,
	radius: number,
	topColor: Color3,
	topMaterial: Enum.Material,
	drop: number?
): Part
	local topY = MapConfig.PLATFORM_TOP_Y - (drop or 0)

	local shoreRadius = radius + MapConfig.SHORE_WIDTH
	local shore = MapParts.newPart(
		name .. "Shore",
		Vector3.new(MapConfig.ISLAND_HEIGHT, shoreRadius * 2, shoreRadius * 2),
		CFrame.new(
			center.X,
			topY - MapConfig.SHORE_DROP - MapConfig.ISLAND_HEIGHT * 0.5,
			center.Z
		) * CFrame.Angles(0, 0, math.rad(90)),
		MapConfig.SHORE_COLOR,
		Enum.Material.Sand
	)
	shore.Shape  = Enum.PartType.Cylinder
	shore.Parent = parent

	local top = MapParts.newPart(
		name,
		Vector3.new(MapConfig.ISLAND_HEIGHT, radius * 2, radius * 2),
		CFrame.new(center.X, topY - MapConfig.ISLAND_HEIGHT * 0.5, center.Z)
			* CFrame.Angles(0, 0, math.rad(90)),
		topColor,
		topMaterial
	)
	top.Shape  = Enum.PartType.Cylinder
	top.Parent = parent

	return top
end

-- Ein einzelnes helles Karo-Feld.
--
-- Es liegt GRASS_HEIGHT ueber der Inselscheibe statt buendig mit ihr: zwei
-- exakt gleich hohe Flaechen flimmern in Roblox gegeneinander. Es kollidiert
-- nicht — die begehbare Flaeche bleibt die Insel darunter, sonst haette die
-- Wiese alle paar Studs eine 0.08 hohe Stufe.
function MapParts.newGrassTile(parent: Instance, name: string, cframe: CFrame, sizeX: number, sizeZ: number)
	local tile = MapParts.newPart(
		name,
		Vector3.new(sizeX, MapConfig.GRASS_HEIGHT, sizeZ),
		cframe,
		MapConfig.GRASS_LIGHT,
		Enum.Material.Grass
	)
	tile.CanCollide = false
	tile.CanQuery   = false
	tile.CanTouch   = false
	tile.Parent     = parent
end

-- Die hellen Felder der Karo-Wiese auf einer runden Insel.
--
-- Gebaut wird nur die HELLE Haelfte; die dunkle ist die Inselscheibe selbst.
-- Das Raster liegt in Weltkoordinaten mit Ursprung im Weltmittelpunkt, damit
-- die Karos ueber alle Inseln durchlaufen statt auf jeder neu anzusetzen.
--
-- Ein Feld wird nur gesetzt, wenn seine VIER ECKEN in der Scheibe liegen —
-- sonst raete ein halbes Karo ueber den Inselrand hinaus ins Wasser. Am Rand
-- bleibt dadurch ein unregelmaessiger dunkler Saum stehen, und genau der
-- laesst die Wiese am Ufer auslaufen statt abgeschnitten zu wirken.
-- Die Mitte kommt als zwei Zahlen und nicht als Vector3: das hier ist ein
-- Raster in der Ebene, die Hoehe steht ohnehin fest. Aufrufer, die einen
-- Vector3 haben, geben eben .X und .Z weiter.
function MapParts.buildCheckerDisc(parent: Instance, centerX: number, centerZ: number, radius: number)
	local tile = MapConfig.GRASS_TILE
	local half = tile * 0.5
	local y    = MapConfig.PLATFORM_TOP_Y + MapConfig.GRASS_HEIGHT * 0.5

	for i = math.floor((centerX - radius) / tile), math.ceil((centerX + radius) / tile) do
		for j = math.floor((centerZ - radius) / tile), math.ceil((centerZ + radius) / tile) do
			if (i + j) % 2 == 0 then
				local x = (i + 0.5) * tile
				local z = (j + 0.5) * tile

				local inside = true
				for _, cx in { -half, half } do
					for _, cz in { -half, half } do
						local dx = x + cx - centerX
						local dz = z + cz - centerZ
						if dx * dx + dz * dz > radius * radius then
							inside = false
						end
					end
				end

				if inside then
					MapParts.newGrassTile(parent, "GrassTile", CFrame.new(x, y, z), tile, tile)
				end
			end
		end
	end
end

-- Dasselbe auf einer quadratischen, GEDREHTEN Flaeche (dem Plot-Beet).
--
-- Hier rastert das Karo plot-lokal und nicht weltweit: das Beet steht je nach
-- Plot in einem anderen Winkel, und ein weltweit ausgerichtetes Raster laege
-- darauf schief. Weil zwischen Beet und Hauptinsel Wasser liegt, sieht man die
-- beiden Raster nie nebeneinander.
function MapParts.buildCheckerPlate(parent: Instance, plate: CFrame, sizeX: number, sizeZ: number)
	local tile   = MapConfig.PLOT_GRASS_TILE
	local countX = math.max(1, math.floor(sizeX / tile))
	local countZ = math.max(1, math.floor(sizeZ / tile))

	-- Was nicht in ganze Felder aufgeht, wird gleichmaessig auf die Felder
	-- verteilt statt als Reststreifen an einer Kante stehen zu lassen.
	local stepX = sizeX / countX
	local stepZ = sizeZ / countZ
	local y     = MapConfig.GRASS_HEIGHT * 0.5

	for i = 0, countX - 1 do
		for j = 0, countZ - 1 do
			if (i + j) % 2 == 0 then
				local x = (i - (countX - 1) * 0.5) * stepX
				local z = (j - (countZ - 1) * 0.5) * stepZ
				MapParts.newGrassTile(parent, "GrassTile", plate * CFrame.new(x, y, z), stepX, stepZ)
			end
		end
	end
end

-- Baut eine Liste von Deko-Teilen (MapConfig.DecorPiece) auf.
--
-- `origin` ist der Ursprung, auf den sich alle Offsets beziehen: die Mitte der
-- Grundflaeche des Objekts, +Y nach oben. Damit kann in der Config in "so hoch
-- ueber dem Boden" gedacht werden statt in Weltkoordinaten.
--
-- Deko ist nie anklickbar (CanQuery = false): ein Klick soll immer beim
-- EIGENTLICHEN Objekt landen — der Gebaeude-Part —, nicht beim Deckel oder
-- der Kuppel.
--
-- Kollision entscheidet dagegen die Config pro Teil (`solid`). Der unsichtbare
-- Koerper taugt dafuer nicht: er ist ein Kasten in der Groesse aus
-- BUILDING_OFFSETS und hat mit der sichtbaren Form nichts mehr zu tun. Bei der
-- offenen Presse wuerde man mitten in der Luft zwischen den Pfosten
-- stehenbleiben und ueber der Kuppel des Bienenstocks auf einer 12x12 grossen
-- unsichtbaren Platte. Also kollidieren genau die Teile, die man auch SIEHT.
function MapParts.buildDecor(parent: Instance, origin: CFrame, pieces: { MapConfig.DecorPiece })
	for _, piece in pieces do
		local cframe = origin * CFrame.new(piece.offset)

		local rotation = piece.rotation
		if rotation then
			cframe = cframe * CFrame.Angles(
				math.rad(rotation.X),
				math.rad(rotation.Y),
				math.rad(rotation.Z)
			)
		end

		local part = MapParts.newPart(
			piece.name,
			piece.size,
			cframe,
			piece.color,
			piece.material or Enum.Material.SmoothPlastic
		)
		part.Shape      = piece.shape
		part.CanCollide = piece.solid == true
		part.CanQuery   = false
		part.CanTouch   = false
		part.Parent     = parent
	end
end

-- Wie hoch das hoechste Deko-Teil einer Liste ueber dem Boden reicht.
--
-- Braucht das Schild ueber einem Gebaeude: haenge es an der Groesse des
-- unsichtbaren Koerpers auf, und es rutscht bei jeder Formaenderung entweder
-- in die Kuppel hinein oder schwebt weit darueber. So bleibt die Regel
-- "Form aendert man nur in der Config" auch fuer das Schild wahr.
--
-- Ein um 90 Grad gekippter Zylinder hat seine Hoehe in X, nicht in Y — dieselbe
-- Umrechnung wie in tools/check_decor.py.
function MapParts.decorHeight(pieces: { MapConfig.DecorPiece }?): number
	if not pieces then return 0 end

	local top = 0
	for _, piece in pieces do
		local halfHeight = piece.size.Y * 0.5

		local rotation = piece.rotation
		if rotation then
			local roll = rotation.Z % 360
			if roll == 90 or roll == 270 then
				halfHeight = piece.size.X * 0.5
			end
		end

		top = math.max(top, piece.offset.Y + halfHeight)
	end

	return top
end

-- Ein einzeiliges Text-Label, wie es auf allen Schildern und Namensschildern
-- benutzt wird. Spart die immer gleichen acht Zeilen Aufbau.
function MapParts.newTextLabel(name: string, parent: Instance, size: UDim2, position: UDim2): TextLabel
	local label = Instance.new("TextLabel")
	label.Name                   = name
	label.Size                   = size
	label.Position               = position
	label.BackgroundTransparency = 1
	label.Font                   = Enum.Font.FredokaOne
	label.TextScaled             = true
	label.TextColor3             = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
	label.Text                   = ""
	label.Parent                 = parent
	return label
end

-- Ein Holzsteg zwischen zwei Inseln, entlang der Aussenrichtung eines Plots.
--
-- `fromRadius` ist der Rand der inneren, `toRadius` der Rand der aeusseren
-- Insel — beide als Abstand zur WELT-Mitte, weil alle Inseln auf derselben
-- Achse liegen. Der Steg schiebt sich an beiden Enden um BRIDGE_OVERLAP
-- darunter, damit an den runden Raendern keine Sichel klafft (siehe
-- MapConfig.BRIDGE_OVERLAP).
--
-- Es gibt genau diese eine Funktion fuer alle 16 Stege: der innere (Hauptinsel
-- → Plot) und der aeussere (Plot → Arena) unterscheiden sich nur in den beiden
-- Radien. Zwei getrennte Bau-Funktionen waren genau die Doppelung, aus der die
-- alte, nur fuer den aeusseren Steg gedachte BRIDGE_LENGTH stammte.
function MapParts.buildSpan(parent: Instance, name: string, outward: Vector3, fromRadius: number, toRadius: number)
	local innerEdge = fromRadius - MapConfig.BRIDGE_OVERLAP
	local outerEdge = toRadius + MapConfig.BRIDGE_OVERLAP

	local deckLength = outerEdge - innerEdge
	local midpoint   = MapConfig.CENTER + outward * ((innerEdge + outerEdge) * 0.5)
	local deckY      = MapConfig.PLATFORM_TOP_Y - MapConfig.BRIDGE_SINK - MapConfig.BRIDGE_HEIGHT * 0.5

	local deckCFrame = CFrame.lookAt(
		Vector3.new(midpoint.X, deckY, midpoint.Z),
		Vector3.new(midpoint.X, deckY, midpoint.Z) + outward
	)

	local deck = MapParts.newPart(
		name,
		Vector3.new(MapConfig.BRIDGE_WIDTH, MapConfig.BRIDGE_HEIGHT, deckLength),
		deckCFrame,
		MapConfig.BRIDGE_COLOR,
		Enum.Material.WoodPlanks
	)
	deck.Parent = parent

	-- Gelaender links und rechts, damit der Steg nicht wie ein Brett aussieht
	local railOffsetX = (MapConfig.BRIDGE_WIDTH + MapConfig.BRIDGE_RAIL_WIDTH) * 0.5
	local railY       = MapConfig.BRIDGE_HEIGHT * 0.5 + MapConfig.BRIDGE_RAIL_HEIGHT * 0.5

	for _, side in { -1, 1 } do
		local rail = MapParts.newPart(
			name .. "Rail",
			Vector3.new(MapConfig.BRIDGE_RAIL_WIDTH, MapConfig.BRIDGE_RAIL_HEIGHT, deckLength),
			deckCFrame * CFrame.new(side * railOffsetX, railY, 0),
			MapConfig.BRIDGE_RAIL_COLOR,
			Enum.Material.WoodPlanks
		)
		rail.Parent = parent
	end
end

-- Weltposition der Arena-Mitte (Oberkante Kampfflaeche).
--
-- Die Arena-Insel liegt genau eine Luecke hinter der Plot-Insel, ihr SOCKEL
-- (PIT_BASE_RADIUS) ist ihr Inselrand. Der Steg landet deshalb auf dem Sockel;
-- die goldene Kampfflaeche liegt als kleinere Scheibe darauf, sodass ringsum
-- ein Absatz fuer Zaun und Leuchtring bleibt.
function MapParts.pitCenter(slot: number): Vector3
	local outward = MapParts.outwardDirection(slot)
	local radius  = MapConfig.PLOT_RING_RADIUS
		+ MapConfig.PLOT_ISLAND_RADIUS
		+ MapConfig.ISLAND_GAP
		+ MapConfig.PIT_BASE_RADIUS

	local flat = MapConfig.CENTER + outward * radius
	return Vector3.new(flat.X, MapConfig.PLATFORM_TOP_Y, flat.Z)
end

-- Das CFrame eines Plots (gemerkt). Siehe buildPlotCFrame.
function MapParts.plotCFrame(slot: number): CFrame
	local cached = _plotCFrames[slot]
	if cached then
		return cached
	end
	local cframe = MapParts.buildPlotCFrame(slot)
	_plotCFrames[slot] = cframe
	return cframe
end

return MapParts
