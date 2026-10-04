--!strict
-- MapService.luau
-- ServerScriptService/Services/MapService.luau
--
-- Einzige Zustaendigkeit:
--   - Die Welt bauen: eine runde Lego-Wiesen-Plattform, einmal beim Start
--   - Spieler-Plots am Aussenrand spawnen, neu aufbauen und despawnen
--   - Pro Plot: Gebaeude, Baerchi-Figuren, Bruecke und eigene PIT-Arena
--   - Die sichtbaren Teile aktuell halten (Gebaeude-Schilder, Baerchi-Zustand)
--
-- Baut physische Roblox-Parts aus IslandData.
-- Kennt keine Spielerdaten ausser IslandData (und den Namen fuer das Schild).
--
-- Alle Masse, Farben und Offsets kommen aus MapConfig — dieser Service hat
-- keine einzige hardcodierte Zahl. Wie das plot-lokale Koordinatensystem
-- funktioniert (lokales -Z = Richtung Mitte, +Z = nach aussen), steht im
-- Kopf von MapConfig.
--
-- ZWEI ARTEN VON AKTUALISIERUNG — bewusst getrennt:
--   * NEU BAUEN (updateBaerchis, updatePitLevel): teuer, nur wenn sich die
--     Struktur aendert (ein Baerchi kommt dazu, faellt weg oder steigt im Level).
--   * IN-PLACE (updateBaerchiStates, updateBuildingSigns): billig, aendert nur
--     Beschriftung und Transparenz an bereits stehenden Teilen. Dafuer gibt es
--     die Trennung: HP und Honig aendern sich staendig, und dafuer jedes Mal
--     25 Mesh-Figuren neu zu bauen waere Verschwendung.
--   PlotDisplayService entscheidet welche der beiden noetig ist.
--
-- NEUAUFBAU WAEHREND EINER BEWEGUNG — die eine Sperre in dieser Datei:
-- updateBaerchis zerstoert die Figur und baut sie neu. Laeuft sie in dem
-- Moment gerade (Kampf-Lauf oder Weg zum Honig-Teich), verschwaende sie mitten
-- im Schritt. Die Pruefung dagegen steht EINMAL hier drin statt an jeder
-- Aufrufstelle — und der uebersprungene Neuaufbau wird nachgeholt, sobald das
-- Schloss frei ist (siehe scheduleRebuildWhenFree weiter unten). Ohne das
-- Nachholen bliebe die Beschriftung dauerhaft veraltet, weil der Aufrufer
-- (PlotDisplayService) den neuen Stand direkt danach als "dargestellt" merkt.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Lighting          = game:GetService("Lighting")

local MapConfig        = require(ReplicatedStorage.Config.MapConfig)
local BaerchiConfig    = require(ReplicatedStorage.Config.BaerchiConfig)
local EggConfig        = require(ReplicatedStorage.Config.EggConfig)
local BuildingBehavior = require(ReplicatedStorage.Config.BuildingBehavior)
local BaerchiMesh      = require(ReplicatedStorage.Modules.BaerchiMesh)
local CombatCalculator = require(ReplicatedStorage.Modules.CombatCalculator)
local Types            = require(ReplicatedStorage.Network.Types)

local ActivityLock     = require(ServerScriptService.Util.ActivityLock)
local FigureFX         = require(ServerScriptService.Util.FigureFX)

--------------------------------------------------------------------------------
-- Interner Zustand
--------------------------------------------------------------------------------

-- Welcher Slot gehoert welchem Spieler
local _playerSlot: { [Player]: number } = {}

-- Alle gespawnten Plot-Models, key = Player
local _plotModels: { [Player]: Model } = {}

-- Verfuegbare Slots (1 .. PLOT_COUNT), wird in init() gefuellt
local _freeSlots: { number } = {}

-- Plot-CFrames pro Slot. Einmal in init() berechnet, weil sie sich nie
-- aendern und sowohl beim Noppen-Raster als auch bei jedem Plot gebraucht
-- werden.
local _plotCFrames: { CFrame } = {}

-- Fuer welche Spieler gerade ein Waechter darauf wartet, den wegen
-- ActivityLock uebersprungenen Figuren-Neuaufbau nachzuholen. Verhindert, dass
-- mehrere Datenaenderungen waehrend derselben Bewegung mehrere Warte-Schleifen
-- starten — eine reicht, sie liest am Ende ohnehin frische Daten.
local _pendingRebuild: { [Player]: boolean } = {}

-- Woher der nachgeholte Neuaufbau seine FRISCHEN IslandData bekommt.
--
-- Absichtlich als eingehaengte Funktion statt eines require(PlayerService):
-- PlayerService requiret bereits MapService, der umgekehrte Weg waere ein
-- Ringschluss. Ausserdem bleibt damit die Regel
-- im Kopf dieser Datei gueltig — MapService kennt weiterhin keine
-- Spielerdaten ausser IslandData. Eingehaengt wird sie von
-- PlotDisplayService.init(); ohne sie faellt nur das Nachholen aus.
local _islandDataProvider: ((Player) -> Types.IslandData?)? = nil

-- Wird aufgerufen, wenn der BESITZER eines Plots sein eigenes gelegtes Ei mit
-- der Spielfigur beruehrt (siehe buildLaidEgg weiter unten).
--
-- Genau dasselbe Pull-Callback-Muster wie bei _islandDataProvider und aus
-- demselben Grund: EggLayService.init() require't bereits MapService, ein
-- MapService.require(EggLayService) waere ein Ringschluss. Eingehaengt wird
-- die Funktion von EggLayService.init(); ohne sie sammelt Beruehren einfach
-- nichts ein.
local _eggCollectHandler: ((Player, string) -> ())? = nil

--------------------------------------------------------------------------------
-- Geometrie-Hilfen
--------------------------------------------------------------------------------

-- Das CFrame eines Plots: steht auf dem Ring und schaut zur Plattform-Mitte.
-- Dadurch ist lokales -Z immer "Richtung Mitte" und +Z immer "nach aussen",
-- egal bei welchem der 8 Winkel der Plot liegt.
local function buildPlotCFrame(slot: number): CFrame
	local angle = math.rad((slot - 1) * (360 / MapConfig.PLOT_COUNT))
	local position = Vector3.new(
		MapConfig.CENTER.X + MapConfig.PLOT_RING_RADIUS * math.cos(angle),
		MapConfig.PLATFORM_TOP_Y,
		MapConfig.CENTER.Z + MapConfig.PLOT_RING_RADIUS * math.sin(angle)
	)

	return CFrame.lookAt(position, Vector3.new(MapConfig.CENTER.X, position.Y, MapConfig.CENTER.Z))
end

-- Richtung "nach aussen" fuer einen Plot (XZ-Einheitsvektor vom Mittelpunkt weg)
local function outwardDirection(slot: number): Vector3
	local position = _plotCFrames[slot].Position
	local flat = Vector3.new(position.X - MapConfig.CENTER.X, 0, position.Z - MapConfig.CENTER.Z)
	if flat.Magnitude < 1e-3 then
		return Vector3.new(1, 0, 0)   -- Sicherheitsnetz, sollte nie vorkommen
	end
	return flat.Unit
end

-- Hoehe der begehbaren Plot-Oberflaeche ueber dem Plot-CFrame-Ursprung.
-- Der Ursprung liegt auf der Plattform-Oberkante, die Plot-Platte liegt
-- darauf — alles was auf dem Plot steht, startet also hier.
-- Attribut, das jedes gelegte Ei traegt. Der Client liest es beim Klick
-- (WorldController) — dieselbe Konvention wie "BaerchiUid" an den Figuren.
local LAID_EGG_ATTRIBUTE = "LaidEggUid"

local function plotSurfaceOffset(): number
	return MapConfig.PLOT_SIZE.Y
end

local function newPart(name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material): Part
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

--------------------------------------------------------------------------------
-- Inseln, Sandkante, Karo-Wiese
--------------------------------------------------------------------------------

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
local function buildIsland(
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
	local shore = newPart(
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

	local top = newPart(
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
local function newGrassTile(parent: Instance, name: string, cframe: CFrame, sizeX: number, sizeZ: number)
	local tile = newPart(
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
local function buildCheckerDisc(parent: Instance, centerX: number, centerZ: number, radius: number)
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
					newGrassTile(parent, "GrassTile", CFrame.new(x, y, z), tile, tile)
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
local function buildCheckerPlate(parent: Instance, plate: CFrame, sizeX: number, sizeZ: number)
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
				newGrassTile(parent, "GrassTile", plate * CFrame.new(x, y, z), stepX, stepZ)
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
local function buildDecor(parent: Instance, origin: CFrame, pieces: { MapConfig.DecorPiece })
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

		local part = newPart(
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
local function decorHeight(pieces: { MapConfig.DecorPiece }?): number
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
local function newTextLabel(name: string, parent: Instance, size: UDim2, position: UDim2): TextLabel
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

--------------------------------------------------------------------------------
-- Globale Welt (einmal beim Server-Start)
--------------------------------------------------------------------------------

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
local function buildSpan(parent: Instance, name: string, outward: Vector3, fromRadius: number, toRadius: number)
	local innerEdge = fromRadius - MapConfig.BRIDGE_OVERLAP
	local outerEdge = toRadius + MapConfig.BRIDGE_OVERLAP

	local deckLength = outerEdge - innerEdge
	local midpoint   = MapConfig.CENTER + outward * ((innerEdge + outerEdge) * 0.5)
	local deckY      = MapConfig.PLATFORM_TOP_Y - MapConfig.BRIDGE_SINK - MapConfig.BRIDGE_HEIGHT * 0.5

	local deckCFrame = CFrame.lookAt(
		Vector3.new(midpoint.X, deckY, midpoint.Z),
		Vector3.new(midpoint.X, deckY, midpoint.Z) + outward
	)

	local deck = newPart(
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
		local rail = newPart(
			name .. "Rail",
			Vector3.new(MapConfig.BRIDGE_RAIL_WIDTH, MapConfig.BRIDGE_RAIL_HEIGHT, deckLength),
			deckCFrame * CFrame.new(side * railOffsetX, railY, 0),
			MapConfig.BRIDGE_RAIL_COLOR,
			Enum.Material.WoodPlanks
		)
		rail.Parent = parent
	end
end

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
local function isOnBridgeLane(worldPosition: Vector3, margin: number): boolean
	local half = MapConfig.BRIDGE_WIDTH * 0.5 + margin

	for slot = 1, MapConfig.PLOT_COUNT do
		local outward = outwardDirection(slot)
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
local function buildFlowers(parent: Instance)
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

		if not isOnBridgeLane(Vector3.new(x, MapConfig.PLATFORM_TOP_Y, z), 5) then
			local stem = newPart(
				"FlowerStem",
				MapConfig.FLOWER_STEM_SIZE,
				CFrame.new(x, stemY, z),
				MapConfig.FLOWER_STEM_COLOR,
				Enum.Material.Grass
			)
			stem.CanCollide = false
			stem.Parent     = parent

			local color = MapConfig.FLOWER_COLORS[random:NextInteger(1, #MapConfig.FLOWER_COLORS)]
			local head = newPart(
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

--------------------------------------------------------------------------------
-- Event-Pit (einmal, in der Weltmitte)
--------------------------------------------------------------------------------

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
local function buildEventPit(parent: Instance)
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

	local floor = newPart(
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
	local ring = newPart(
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
		local outward = outwardDirection(slot)
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
			local post = newPart(
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
	local anchor = newPart(
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

	local bannerTitle = newTextLabel("Title", banner, UDim2.fromScale(1, 0.6), UDim2.fromScale(0, 0))
	bannerTitle.Text  = "..."
	bannerTitle.TextColor3 = MapConfig.EVENT_PIT_BANNER_IDLE_COLOR
	newTextLabel("Sub", banner, UDim2.fromScale(1, 0.4), UDim2.fromScale(0, 0.6))
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
local function buildGlobalLighting()
	if Lighting:FindFirstChild("BaerchiBloom") then
		return   -- schon gesetzt
	end

	Lighting.ClockTime = MapConfig.LIGHTING_CLOCK_TIME

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
local function buildPlatform()
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
	local water = newPart(
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
	buildIsland(
		model,
		"Ground",
		MapConfig.CENTER,
		MapConfig.PLATFORM_RADIUS,
		MapConfig.GRASS_DARK,
		Enum.Material.Grass
	)
	buildCheckerDisc(model, MapConfig.CENTER.X, MapConfig.CENTER.Z, MapConfig.PLATFORM_RADIUS)

	-- Die acht Plot-Inseln und die Stege dorthin.
	for slot = 1, MapConfig.PLOT_COUNT do
		local outward = outwardDirection(slot)
		local center  = MapConfig.CENTER + outward * MapConfig.PLOT_RING_RADIUS

		buildIsland(
			model,
			"PlotIsland_" .. slot,
			center,
			MapConfig.PLOT_ISLAND_RADIUS,
			MapConfig.PLOT_ISLAND_COLOR,
			Enum.Material.Grass
		)

		buildSpan(
			model,
			"BridgeInner_" .. slot,
			outward,
			MapConfig.PLATFORM_RADIUS,
			MapConfig.PLOT_RING_RADIUS - MapConfig.PLOT_ISLAND_RADIUS
		)
	end

	buildFlowers(model)

	-- Das Event-Pit in der Mitte — siehe buildEventPit oben.
	buildEventPit(model)

	-- Der Honigmast steht jetzt auf dem Event-Pit-Podest statt auf einem
	-- eigenen Spawn-Pad (das gibt es nicht mehr, siehe Not-Spawn unten) — er
	-- bleibt derselbe Orientierungspunkt, den man von jeder Insel aus sieht,
	-- nur jetzt mittig im Stall statt auf einer separaten Platte.
	local mast = Instance.new("Model")
	mast.Name = "Honigmast"
	buildDecor(
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

	model.Parent = workspace
	print(
		"[MapService] Welt gebaut | Hauptinsel:", MapConfig.PLATFORM_RADIUS,
		"| Plot-Inseln:", MapConfig.PLOT_COUNT, "bei", MapConfig.PLOT_RING_RADIUS,
		"| Wasser:", MapConfig.WATER_RADIUS
	)
end

--------------------------------------------------------------------------------
-- Plot-Grundgeruest
--------------------------------------------------------------------------------

-- Zaun an den beiden Seiten des Plots. Vorne und hinten bleibt offen, sonst
-- kaeme man weder auf den Plot noch zur Bruecke.
local function buildFence(plotModel: Model, slot: number)
	local plotCFrame = _plotCFrames[slot]
	local halfX = MapConfig.PLOT_SIZE.X * 0.5
	local halfZ = MapConfig.PLOT_SIZE.Z * 0.5

	local postY = plotSurfaceOffset() + MapConfig.FENCE_POST_SIZE.Y * 0.5
	local steps = math.max(1, math.floor(MapConfig.PLOT_SIZE.Z / MapConfig.FENCE_POST_SPACING))

	for _, side in { -1, 1 } do
		for i = 0, steps do
			local z = -halfZ + (i / steps) * MapConfig.PLOT_SIZE.Z

			local post = newPart(
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
			local railY = plotSurfaceOffset() + MapConfig.FENCE_POST_SIZE.Y * heightFactor

			local rail = newPart(
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
local function buildPlotSign(plotModel: Model, slot: number, ownerName: string)
	local plotCFrame = _plotCFrames[slot]
	local halfZ = MapConfig.PLOT_SIZE.Z * 0.5

	local postY = plotSurfaceOffset() + MapConfig.SIGN_POST_SIZE.Y * 0.5
	local post = newPart(
		"SignPost",
		MapConfig.SIGN_POST_SIZE,
		plotCFrame * CFrame.new(0, postY, -halfZ + 2),
		MapConfig.SIGN_POST_COLOR,
		Enum.Material.Wood
	)
	post.CanCollide = false
	post.Parent     = plotModel

	local boardY = plotSurfaceOffset() + MapConfig.SIGN_POST_SIZE.Y - MapConfig.SIGN_BOARD_SIZE.Y * 0.5
	local board = newPart(
		"SignBoard",
		MapConfig.SIGN_BOARD_SIZE,
		plotCFrame * CFrame.new(0, boardY, -halfZ + 2),
		MapConfig.SIGN_COLOR,
		Enum.Material.Wood
	)
	board.CanCollide = false
	board.Parent     = plotModel

	-- Die Schrift kommt auf die Seite, die zur Plattform-Mitte zeigt. Das ist
	-- die lokale -Z-Seite des Plots und damit die Vorderseite des Boards.
	local surface = Instance.new("SurfaceGui")
	surface.Name        = "SignText"
	surface.Face        = Enum.NormalId.Front
	surface.PixelsPerStud = 40
	surface.Adornee     = board
	surface.Parent      = board

	local label = newTextLabel("Owner", surface, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0))
	label.TextColor3             = Color3.fromRGB(70, 50, 30)
	label.TextStrokeTransparency = 1
	label.Text                   = ownerName
end

-- Die Plot-Platte samt Zaun und Schild.
--
-- Das Besitzer-Attribut wird gesetzt BEVOR das Model in den Workspace kommt:
-- der Client bekommt es damit zusammen mit dem Model und muss nicht darauf
-- warten. WorldController haengt daran, ob er ueberhaupt einen Prompt baut.
local function buildPlotBase(slot: number, owner: Player): Model
	local plotCFrame = _plotCFrames[slot]

	local model = Instance.new("Model")
	model.Name  = "Plot_" .. slot
	model:SetAttribute("PlotOwner", owner.UserId)

	-- Das Beet: eine quadratische Platte auf der Plot-Insel. Dunkles Gruen wie
	-- die Hauptinsel, darauf dieselben hellen Karos — nur plot-lokal gerastert,
	-- weil das Beet je nach Plot in einem anderen Winkel steht.
	local base = newPart(
		"Base",
		MapConfig.PLOT_SIZE,
		plotCFrame * CFrame.new(0, MapConfig.PLOT_SIZE.Y * 0.5, 0),
		MapConfig.GRASS_DARK,
		Enum.Material.Grass
	)
	base.CanCollide = true
	base.Parent     = model

	buildCheckerPlate(
		model,
		plotCFrame * CFrame.new(0, MapConfig.PLOT_SIZE.Y, 0),
		MapConfig.PLOT_SIZE.X,
		MapConfig.PLOT_SIZE.Z
	)

	model.PrimaryPart = base

	buildFence(model, slot)
	buildPlotSign(model, slot, owner.DisplayName)

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
		plotSurfaceOffset() + MapConfig.PLAYER_SPAWN_OFFSET.Y + 0.5,
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

--------------------------------------------------------------------------------
-- Gebaeude
--------------------------------------------------------------------------------

-- Die Honig-Tropfen am Fuss eines Gebaeudes einmalig anlegen. Sie werden
-- danach nur noch ein- und ausgeblendet (writeBuildingState), nie neu gebaut:
-- ein Neuaufbau alle 20 Sekunden mal drei Gebaeude mal acht Spieler waere
-- fuer reine Deko viel zu teuer.
--
-- `ground` ist die Mitte der Grundflaeche des Gebaeudes, also derselbe
-- Ursprung wie fuer die Deko.
--
-- `slots` ist das GROESSTE Lager, das dieses Gebaeude je haben kann — nicht
-- sein aktuelles. Seit v7 waechst das Lager des Bienenstocks mit dem Level,
-- und die Tropfen entstehen nur einmal beim Aufbau. Ueberzaehlige Tropfen
-- stoeren nicht: sichtbar ist ein Tropfen erst, wenn wirklich Honig drin liegt
-- (writeBuildingState).
local function buildHoneyDots(body: BasePart, ground: CFrame, slots: number)
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

		local dot = newPart(
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

-- Der gesamte Honig-Vorrat einer Insel.
--
-- Wird als Attribut an JEDES Gebaeude geschrieben, nicht nur der eigene
-- Bestand: gefuettert wird auf der Baerchi-Detailkarte, und dort stehen alle
-- drei Vorraete nebeneinander zur Wahl. Wer vor dem Bienenstock steht, soll
-- deshalb sehen, dass ueberhaupt noch Honig da ist — auch wenn er im Honigtopf
-- nebenan liegt.
local function honeyPool(islandData: Types.IslandData): number
	local total = 0
	for _, building in islandData.buildings do
		total += math.max(0, building.honey or 0)
	end
	return total
end

-- Alles am Gebaeude, was sich im Betrieb aendert: Schildtext, Honig-Tropfen
-- und der Vorrats-Wert fuer den Fuetter-Prompt. Getrennt vom Aufbau, weil das
-- bei JEDER Honig-Aenderung laeuft (siehe updateBuildingSigns) und deshalb
-- billig bleiben muss.
local function writeBuildingState(part: BasePart, buildingData: Types.Building, pool: number)
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
	-- ueberzaehligen bleiben unsichtbar.
	for i = 1, BuildingBehavior.getMaxCapacity(buildingData.id) do
		local dot = part:FindFirstChild("HoneyDot" .. i)
		if dot and dot:IsA("BasePart") then
			dot.Transparency = if i <= honey then 0 else 1
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
local function buildBuilding(plotModel: Model, slot: number, buildingData: Types.Building, pool: number)
	local config = MapConfig.BUILDING_OFFSETS[buildingData.id]
	if not config then return end

	local plotCFrame = _plotCFrames[slot]
	local localY = plotSurfaceOffset() + config.offset.Y + config.size.Y * 0.5

	local part = newPart(
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
		plotSurfaceOffset() + config.offset.Y,
		config.offset.Z
	)

	local decor = MapConfig.BUILDING_DECOR[buildingData.id]
	if decor then
		buildDecor(part, ground, decor)
	end

	buildHoneyDots(part, ground, BuildingBehavior.getMaxCapacity(buildingData.id))

	-- Level als Attribut: der Client kann es direkt auslesen ohne eigenes Remote
	part:SetAttribute("BuildingLevel", buildingData.level)

	-- Schild ueber dem Gebaeude: Name, Level und Honig-Lagerstand. Ohne das
	-- muesste man fuer die Frage "ist schon wieder Honig da?" jedes Mal ein
	-- Panel oeffnen.
	--
	-- Die Hoehe richtet sich nach dem hoechsten Deko-Teil, nicht nach der
	-- Koerpergroesse: sonst haengt das Schild nach jeder Formaenderung falsch.
	-- StudsOffset zaehlt ab der MITTE der Part, deshalb die Halbierung.
	local topOfDecor = math.max(decorHeight(decor), config.size.Y)

	local sign = Instance.new("BillboardGui")
	sign.Name         = "Sign"
	sign.Size         = UDim2.fromScale(9, 2.6)
	sign.StudsOffset  = Vector3.new(0, topOfDecor - config.size.Y * 0.5 + 2, 0)
	sign.AlwaysOnTop  = false
	sign.MaxDistance  = MapConfig.BUILDING_SIGN_DISTANCE
	sign.Adornee      = part
	sign.Parent       = part

	newTextLabel("Title", sign, UDim2.fromScale(1, 0.5), UDim2.fromScale(0, 0))
	newTextLabel("Stock", sign, UDim2.fromScale(1, 0.5), UDim2.fromScale(0, 0.5))

	writeBuildingState(part, buildingData, pool)
end

--------------------------------------------------------------------------------
-- Honig-Teich
--------------------------------------------------------------------------------

-- Wie voll der Teich angezeigt wird: Anteil des GESAMTEN Honig-Vorrats an der
-- Lagermenge, die diese Insel auf ihren AKTUELLEN Leveln fasst.
--
-- Bewusst die aktuelle und nicht die theoretisch maximale Menge: der
-- Bienenstock vergroessert sein Lager mit jedem Level, und ein Teich, der nach
-- einem Ausbau ploetzlich leerer aussieht, waere die falsche Rueckmeldung.
-- So heisst "voller Teich" immer dasselbe — alle Lager sind voll.
local function pondFillRatio(islandData: Types.IslandData): number
	local capacity = BuildingBehavior.getTotalCapacity(islandData.buildings)
	if capacity <= 0 then return 0 end
	return math.clamp(honeyPool(islandData) / capacity, 0, 1)
end

-- Der Boden-Ursprung des Teichs fuer einen Plot.
--
-- Mitte des Beckens auf Beet-Hoehe — dieselbe Rolle wie `ground` bei den
-- Gebaeuden, aber zusaetzlich GEDREHT: das lokale -Z zeigt zum Baerchi-Platz,
-- also dorthin, wo der Baerchi herkommt und beim Fressen steht. Genau
-- dieselbe Regel wie beim Plot-CFrame ("-Z zeigt dorthin, wo man herkommt"),
-- und der Grund, warum die Offsets in MapConfig.POND_DECOR ohne einen einzigen
-- Winkel auskommen.
--
-- Faellt die Richtung weg (Teich exakt auf dem Baerchi-Platz — kann nur durch
-- eine kaputte Config passieren), bleibt die Plot-Ausrichtung stehen: lieber
-- ein Teich, der in die falsche Richtung schaut, als gar keiner.
local function pondGround(slot: number): CFrame
	local plotCFrame = _plotCFrames[slot]

	local center = CFrame.new(
		MapConfig.POND_OFFSET.X,
		plotSurfaceOffset() + MapConfig.POND_OFFSET.Y,
		MapConfig.POND_OFFSET.Z
	)

	local toHome = Vector3.new(
		MapConfig.BAERCHI_HOME_OFFSET.X - MapConfig.POND_OFFSET.X,
		0,
		MapConfig.BAERCHI_HOME_OFFSET.Z - MapConfig.POND_OFFSET.Z
	)

	if toHome.Magnitude < 1e-3 then
		return plotCFrame * center
	end

	-- CFrame.lookAt richtet -Z auf das Ziel aus (siehe buildPlotCFrame).
	local facing = CFrame.lookAt(center.Position, center.Position + toHome.Unit)
	return plotCFrame * facing
end

-- Der Standplatz vor dem Becken: teich-lokal auf -Z, um Beckenrand plus
-- Abstand von der Mitte entfernt. Hier landet der Baerchi, hier liegen die
-- Bohlen, und genau hier hat der Steinkranz seine Luecke.
local function pondStandDistance(): number
	return MapConfig.POND_RADIUS + MapConfig.POND_STAND_GAP
end

local function pondStand(slot: number): CFrame
	return pondGround(slot) * CFrame.new(0, 0, -pondStandDistance())
end

-- Setzt die Fuellhoehe der "Fuellung"-Part auf den aktuellen Vorrat. Getrennt
-- vom Aufbau, weil das bei jeder Honig-Aenderung laeuft (siehe
-- updateBuildingSigns) und deshalb billig bleiben muss — kein Neuaufbau.
--
-- `ground` ist derselbe Ursprung wie beim Aufbau: die Fuellung waechst von
-- dort nach oben, statt ueber die WELT-Position herumzurechnen (die haengt
-- vom Plot-Winkel ab und ist dafuer ungeeignet).
local function writePondFill(fill: BasePart, ground: CFrame, ratio: number)
	-- Breiter UND hoeher (siehe MapConfig): nur hoeher waere aus der
	-- Spielerkamera kaum abzulesen, nur breiter saehe aus wie ein Aufkleber.
	local maxRadius = MapConfig.POND_RADIUS - MapConfig.POND_FILL_INSET
	local scale     = MapConfig.POND_FILL_MIN_SCALE
		+ (1 - MapConfig.POND_FILL_MIN_SCALE) * math.clamp(ratio, 0, 1)

	local radius = maxRadius * scale
	local height = MapConfig.POND_FILL_MIN_HEIGHT
		+ (MapConfig.POND_FILL_MAX_HEIGHT - MapConfig.POND_FILL_MIN_HEIGHT) * math.clamp(ratio, 0, 1)

	-- Der Honig steht AUF dem Beckenboden, nicht auf dem Beet.
	fill.CFrame = ground
		* CFrame.new(0, MapConfig.POND_FLOOR_TOP + height * 0.5, 0)
		* CFrame.Angles(0, 0, math.rad(90))
	fill.Size   = Vector3.new(height, radius * 2, radius * 2)

	fill.Transparency = if ratio <= 0 then 1 else MapConfig.POND_FILL_TRANSPARENCY
end

-- Eine der beiden flachen Scheiben des Beckens (Sandkante bzw. Beckenboden).
-- Beide sind dicker als der sichtbare Teil; der Rest steckt im Beet, damit
-- unten nichts durchscheint.
local function buildPondDisc(parent: Instance, ground: CFrame, name: string, radius: number, top: number, color: Color3, material: Enum.Material)
	local disc = newPart(
		name,
		Vector3.new(MapConfig.POND_DISC_HEIGHT, radius * 2, radius * 2),
		ground * CFrame.new(0, top - MapConfig.POND_DISC_HEIGHT * 0.5, 0)
			* CFrame.Angles(0, 0, math.rad(90)),
		color,
		material
	)
	disc.Shape      = Enum.PartType.Cylinder
	disc.CanCollide = true
	disc.CanQuery   = false
	disc.Parent     = parent
end

-- Der Steinkranz: die Beckenwand.
--
-- Er laesst auf der Seite zum Baerchi-Platz eine Luecke frei — dieselbe Idee
-- wie beim Zaun um die Arena, und aus demselben Grund: durch eine Wand kommt
-- man nicht. Groessen und Farben wechseln reihum durch, damit es nach
-- gesammelten Feldsteinen aussieht und nicht nach einer Perlenkette.
local function buildPondStones(parent: Instance, ground: CFrame)
	local ringRadius = MapConfig.POND_RADIUS + MapConfig.POND_RIM_WIDTH * 0.5
	local gap        = math.rad(MapConfig.POND_STONE_GAP_DEGREES)

	-- Die Steine stehen bei (sin a, cos a): a = 0 ist teich-lokales +Z,
	-- a = pi ist -Z. Die Luecke liegt also bei pi.
	local gapAngle = math.pi

	for i = 1, MapConfig.POND_STONE_COUNT do
		local angle = (i - 1) * (2 * math.pi / MapConfig.POND_STONE_COUNT)

		-- Winkelabstand zur Luecke, immer als kuerzester Weg gemessen.
		local delta = math.abs(((angle - gapAngle + math.pi) % (2 * math.pi)) - math.pi)

		if delta > gap then
			local size  = MapConfig.POND_STONE_SIZES[((i - 1) % #MapConfig.POND_STONE_SIZES) + 1]
			local color = MapConfig.POND_STONE_COLORS[((i - 1) % #MapConfig.POND_STONE_COLORS) + 1]

			-- Etwas eingegraben: die Steine sollen im Sand liegen und nicht
			-- auf dem Boden balancieren. Sie sind leicht gestaucht, damit sie
			-- nach Feldsteinen aussehen und nicht nach Murmeln.
			local stone = newPart(
				"Stein_" .. i,
				Vector3.new(size, size * 0.82, size),
				ground * CFrame.new(
					math.sin(angle) * ringRadius,
					MapConfig.POND_RIM_TOP + size * 0.30,
					math.cos(angle) * ringRadius
				),
				color,
				Enum.Material.Slate
			)
			stone.Shape      = Enum.PartType.Ball
			stone.CanCollide = true
			stone.CanQuery   = false
			stone.Parent     = parent
		end
	end
end

-- Die zwei Bohlen vor der Luecke, auf denen der Baerchi beim Fressen steht,
-- plus zwei Pfloecke daneben. Sie liegen um den Standplatz herum, den auch
-- MapService.getPondPosition zurueckgibt — eine Rechnung, kein zweiter Satz
-- Zahlen (siehe MapConfig.POND_STAND_GAP).
local function buildPondPlanks(parent: Instance, ground: CFrame)
	local stand = pondStandDistance()
	local step: number = (MapConfig.POND_PLANK_SIZE.Z + MapConfig.POND_PLANK_GAP) * 0.5
	local y: number    = MapConfig.POND_PLANK_TOP - MapConfig.POND_PLANK_SIZE.Y * 0.5

	for i, offset in { -step, step } do
		local plank = newPart(
			"Bohle_" .. i,
			MapConfig.POND_PLANK_SIZE,
			ground * CFrame.new(0, y, -stand + offset),
			MapConfig.POND_PLANK_COLORS[((i - 1) % #MapConfig.POND_PLANK_COLORS) + 1],
			Enum.Material.WoodPlanks
		)
		plank.CanCollide = false
		plank.CanQuery   = false
		plank.Parent     = parent
	end

	-- Pfloecke: liegende Zylinder quer zu den Bohlen, wie eingeschlagene
	-- Pfosten. UPRIGHT waere hier falsch — sie sollen liegen.
	for i, side in { -1, 1 } do
		local peg = newPart(
			"Pflock_" .. i,
			MapConfig.POND_PEG_SIZE,
			ground * CFrame.new(side * MapConfig.POND_PEG_SPREAD, MapConfig.POND_PEG_SIZE.Y * 0.4, -stand)
				* CFrame.Angles(0, 0, math.rad(90)),
			MapConfig.POND_PLANK_COLORS[2],
			Enum.Material.Wood
		)
		peg.Shape      = Enum.PartType.Cylinder
		peg.CanCollide = false
		peg.CanQuery   = false
		peg.Parent     = parent
	end
end

-- Der Honig-Teich auf dem Plot: Sandkante, Steinkranz, abgesenkter Beckenboden
-- und darauf der Honig, dessen Flaeche und Hoehe den Gesamt-Vorrat zeigen. Der
-- ausgeruestete Baerchi laeuft zu den Bohlen davor, um zu essen (siehe
-- BaerchiAutopilotService).
local function buildPond(plotModel: Model, slot: number, islandData: Types.IslandData)
	local old = plotModel:FindFirstChild("Pond")
	if old then old:Destroy() end

	local ground = pondGround(slot)

	local pond = Instance.new("Model")
	pond.Name   = "Pond"
	pond.Parent = plotModel

	-- Sandkante zuerst und TIEFER als der Beckenboden: nur so bleibt sie
	-- ringsum als Streifen sichtbar, ohne dass ein Ring aus Einzelteilen
	-- noetig waere — derselbe Trick wie am Ufer jeder Insel.
	buildPondDisc(
		pond, ground, "Rand",
		MapConfig.POND_RADIUS + MapConfig.POND_RIM_WIDTH,
		MapConfig.POND_RIM_TOP,
		MapConfig.POND_RIM_COLOR,
		Enum.Material.Sand
	)
	buildPondDisc(
		pond, ground, "Boden",
		MapConfig.POND_RADIUS,
		MapConfig.POND_FLOOR_TOP,
		MapConfig.POND_FLOOR_COLOR,
		Enum.Material.Slate
	)

	buildPondStones(pond, ground)
	buildPondPlanks(pond, ground)
	buildDecor(pond, ground, MapConfig.POND_DECOR)

	-- Als Platzhalter-Groesse angelegt — writePondFill setzt Groesse und
	-- Position gleich im Anschluss auf den echten Vorrat.
	local fill = newPart(
		"Fuellung",
		Vector3.new(0.05, MapConfig.POND_RADIUS, MapConfig.POND_RADIUS),
		ground,
		MapConfig.POND_FILL_COLOR,
		Enum.Material.Neon
	)
	fill.Shape      = Enum.PartType.Cylinder
	fill.CanCollide = false
	fill.CanQuery   = false
	fill.CanTouch   = false
	fill.Parent     = pond

	writePondFill(fill, ground, pondFillRatio(islandData))
end

--------------------------------------------------------------------------------
-- Steg zur Arena-Insel und die PIT-Arena
--------------------------------------------------------------------------------

-- Weltposition der Arena-Mitte (Oberkante Kampfflaeche).
--
-- Die Arena-Insel liegt genau eine Luecke hinter der Plot-Insel, ihr SOCKEL
-- (PIT_BASE_RADIUS) ist ihr Inselrand. Der Steg landet deshalb auf dem Sockel;
-- die goldene Kampfflaeche liegt als kleinere Scheibe darauf, sodass ringsum
-- ein Absatz fuer Zaun und Leuchtring bleibt.
local function pitCenter(slot: number): Vector3
	local outward = outwardDirection(slot)
	local radius  = MapConfig.PLOT_RING_RADIUS
		+ MapConfig.PLOT_ISLAND_RADIUS
		+ MapConfig.ISLAND_GAP
		+ MapConfig.PIT_BASE_RADIUS

	local flat = MapConfig.CENTER + outward * radius
	return Vector3.new(flat.X, MapConfig.PLATFORM_TOP_Y, flat.Z)
end

-- Der aeussere Steg: von der Plot-Insel des Spielers auf seine Arena-Insel.
-- Er gehoert zum Spieler und wird deshalb mit dessen Plot-Model gebaut — die
-- INNEREN Stege (Hauptinsel → Plot-Insel) stehen dagegen immer, siehe
-- buildPlatform.
local function buildBridge(plotModel: Model, slot: number)
	local islandEdge = MapConfig.PLOT_RING_RADIUS + MapConfig.PLOT_ISLAND_RADIUS

	buildSpan(
		plotModel,
		"Bridge",
		outwardDirection(slot),
		islandEdge,
		islandEdge + MapConfig.ISLAND_GAP
	)
end

-- Die PIT-Arena am Ende der Bruecke. Flache runde Kampfflaeche; das PIT-Level
-- zeigt sich an der Anzahl der Saeulen am Rand.
--
-- Die Kampfflaeche heisst bewusst weiterhin "FightFloor": WorldController
-- haengt genau an diesem Namen seinen Kampf-Prompt auf.
local function buildPit(plotModel: Model, slot: number, pitLevel: number)
	local old = plotModel:FindFirstChild("PitPlatform")
	if old then old:Destroy() end

	local container = Instance.new("Model")
	container.Name   = "PitPlatform"
	container.Parent = plotModel

	local center = pitCenter(slot)

	-- Die Arena-Insel: derselbe Aufbau wie jede andere Insel (Sandkante plus
	-- Scheibe), damit sie nicht wie ein Fremdkoerper im Wasser steht. Ihre
	-- Oberflaeche ist der Sockel, auf dem der Steg landet.
	-- Der Sockel liegt PIT_RIM_DROP tiefer als die Kampfflaeche, sonst waeren
	-- die beiden Oberseiten deckungsgleich und wuerden flimmern.
	local rimY = MapConfig.PLATFORM_TOP_Y - MapConfig.PIT_RIM_DROP

	buildIsland(
		container,
		"PitBase",
		center,
		MapConfig.PIT_BASE_RADIUS,
		MapConfig.PIT_BASE_COLOR,
		Enum.Material.Slate,
		MapConfig.PIT_RIM_DROP
	)

	-- Leuchtender Ring am Sockelrand: eine etwas breitere Scheibe, die flach
	-- darunter liegt. Sichtbar bleibt nur ihr ueberstehender Rand — derselbe
	-- Trick wie bei der Sandkante, und ein Teil statt eines Dutzends Segmente.
	-- Sie sitzt eine halbe Ringhoehe unter dem Sockel: damit liegt sie
	-- zwischen Sockel und Sandkante, ohne mit einer von beiden auf gleicher
	-- Hoehe zu liegen.
	local ringRadius = MapConfig.PIT_BASE_RADIUS + MapConfig.PIT_RING_OVERHANG
	local ring = newPart(
		"PitRing",
		Vector3.new(MapConfig.PIT_RING_HEIGHT, ringRadius * 2, ringRadius * 2),
		CFrame.new(center.X, rimY - MapConfig.PIT_RING_HEIGHT, center.Z)
			* CFrame.Angles(0, 0, math.rad(90)),
		MapConfig.PIT_RING_COLOR,
		Enum.Material.Neon
	)
	ring.Shape      = Enum.PartType.Cylinder
	ring.CanCollide = false
	ring.CanQuery   = false
	ring.Parent     = container

	-- Kampfflaeche: Oberkante auf PLATFORM_TOP_Y, also ein kleiner Absatz ueber
	-- dem Sockelring ringsum.
	local floorY = MapConfig.PLATFORM_TOP_Y - MapConfig.PIT_FLOOR_HEIGHT * 0.5
	local floor = newPart(
		"FightFloor",
		Vector3.new(MapConfig.PIT_FLOOR_HEIGHT, MapConfig.PIT_RADIUS * 2, MapConfig.PIT_RADIUS * 2),
		CFrame.new(center.X, floorY, center.Z) * CFrame.Angles(0, 0, math.rad(90)),
		MapConfig.PIT_FLOOR_COLOR,
		Enum.Material.SmoothPlastic
	)
	floor.Shape  = Enum.PartType.Cylinder
	floor.Parent = container

	-- Leuchtender Zaun auf dem Sockelrand.
	--
	-- Zur Steg-Seite bleibt eine Luecke frei, sonst muesste man beim Betreten
	-- der Arena ueber den Zaun springen. Die Steg-Seite ist die Richtung ZUR
	-- Weltmitte, also das Gegenteil der Aussenrichtung des Plots.
	local outward    = outwardDirection(slot)
	local inwardAngle = math.atan2(-outward.Z, -outward.X)
	local gap        = math.rad(MapConfig.PIT_FENCE_GAP_DEGREES)
	local postRadius = MapConfig.PIT_BASE_RADIUS - MapConfig.PIT_FENCE_INSET
	local postY      = rimY + MapConfig.PIT_FENCE_SIZE.Y * 0.5

	for i = 1, MapConfig.PIT_FENCE_COUNT do
		local angle = (i - 1) * (2 * math.pi / MapConfig.PIT_FENCE_COUNT)

		-- Winkelabstand zur Steg-Richtung, immer als kuerzester Weg gemessen —
		-- sonst faellt die Luecke bei manchen Plots auseinander.
		local delta = math.abs(((angle - inwardAngle + math.pi) % (2 * math.pi)) - math.pi)

		if delta > gap then
			local post = newPart(
				"PitFence_" .. i,
				MapConfig.PIT_FENCE_SIZE,
				CFrame.new(
					center.X + postRadius * math.cos(angle),
					postY,
					center.Z + postRadius * math.sin(angle)
				),
				MapConfig.PIT_FENCE_COLOR,
				Enum.Material.Neon
			)
			post.CanCollide = false
			post.CanQuery   = false
			post.Parent     = container
		end
	end

	-- Ordner fuer die Kampf-Figuren waehrend eines Laufs. Liegt hier, damit
	-- PitArenaService nichts selbst anlegen muss und ein Neuaufbau des PIT
	-- die Figuren automatisch mitnimmt.
	local fighters = Instance.new("Folder")
	fighters.Name   = "Fighters"
	fighters.Parent = container

	-- Ordner fuer die Turm-Etagen, die waehrend eines Laufs Stage fuer Stage
	-- dazukommen (siehe MapService.setPitTowerLevel). Aus demselben Grund wie
	-- Fighters: PitArenaService legt hier nichts selbst an, und ein Neuaufbau
	-- des PIT (z. B. beim Ausbauen) raeumt einen laufenden Turm automatisch mit
	-- weg statt ihn verwaist stehen zu lassen.
	local tower = Instance.new("Folder")
	tower.Name   = "Tower"
	tower.Parent = container

	-- Anzeigetafel ueber der Arena. Sie haengt an einer eigenen unsichtbaren
	-- Part und nicht am Boden: der Boden ist ein um 90 Grad gekippter Zylinder,
	-- an dem "oben" nicht nach oben zeigt. Standardmaessig ausgeschaltet —
	-- eingeblendet wird sie nur waehrend einer Wiedergabe.
	local anchor = newPart(
		"PitBannerAnchor",
		Vector3.new(1, 1, 1),
		CFrame.new(center.X, MapConfig.PLATFORM_TOP_Y + MapConfig.PIT_BANNER_HEIGHT, center.Z),
		MapConfig.PIT_FLOOR_COLOR,
		Enum.Material.SmoothPlastic
	)
	anchor.Transparency = 1
	anchor.CanCollide   = false
	anchor.CanQuery     = false
	anchor.CanTouch     = false
	anchor.Parent       = container

	local banner = Instance.new("BillboardGui")
	banner.Name        = "Banner"
	banner.Size        = UDim2.fromScale(MapConfig.PIT_BANNER_SIZE.X, MapConfig.PIT_BANNER_SIZE.Y)
	banner.AlwaysOnTop = false
	banner.MaxDistance = MapConfig.PIT_BANNER_DISTANCE
	banner.Adornee     = anchor
	banner.Enabled     = false
	banner.Parent      = anchor

	local bannerTitle = newTextLabel("Title", banner, UDim2.fromScale(1, 0.6), UDim2.fromScale(0, 0))
	bannerTitle.Text  = ""
	newTextLabel("Sub", banner, UDim2.fromScale(1, 0.4), UDim2.fromScale(0, 0.6))

	-- Eine Saeule pro PIT-Level, gleichmaessig am Rand verteilt
	local pillarCount = math.max(0, math.floor(pitLevel))
	if pillarCount <= 0 then
		return
	end

	local pillarRadius = MapConfig.PIT_RADIUS - MapConfig.PIT_PILLAR_INSET
	local pillarY      = MapConfig.PLATFORM_TOP_Y + MapConfig.PIT_PILLAR_SIZE.Y * 0.5

	for i = 1, pillarCount do
		local angle = math.rad((i - 1) * (360 / pillarCount))
		local color = MapConfig.PIT_PILLAR_COLORS[((i - 1) % #MapConfig.PIT_PILLAR_COLORS) + 1]

		local pillar = newPart(
			"PitPillar_" .. i,
			MapConfig.PIT_PILLAR_SIZE,
			CFrame.new(
				center.X + pillarRadius * math.cos(angle),
				pillarY,
				center.Z + pillarRadius * math.sin(angle)
			),
			color,
			Enum.Material.Neon
		)
		pillar.Parent = container
	end
end

--------------------------------------------------------------------------------
-- PIT-Turm: waechst waehrend eines Laufs eine Etage pro geschaffter Stage
--------------------------------------------------------------------------------

-- Eine einzelne Turm-Etage: eine Scheibe im selben Radius wie die
-- Kampfflaeche, die direkt auf der vorherigen aufsetzt. `level` ist 1-basiert
-- — Etage 1 ist die erste Scheibe UEBER der normalen Kampfflaeche.
local function buildTowerRing(tower: Folder, center: Vector3, level: number)
	local color = MapConfig.PIT_TOWER_COLORS[((level - 1) % #MapConfig.PIT_TOWER_COLORS) + 1]
	local topY  = MapConfig.PLATFORM_TOP_Y + level * MapConfig.PIT_TOWER_STEP_HEIGHT

	local ring = newPart(
		"Ring_" .. level,
		Vector3.new(MapConfig.PIT_TOWER_STEP_HEIGHT, MapConfig.PIT_TOWER_RADIUS * 2, MapConfig.PIT_TOWER_RADIUS * 2),
		CFrame.new(center.X, topY - MapConfig.PIT_TOWER_STEP_HEIGHT * 0.5, center.Z)
			* CFrame.Angles(0, 0, math.rad(90)),
		color,
		Enum.Material.SmoothPlastic
	)
	ring.Shape  = Enum.PartType.Cylinder
	ring.Parent = tower
end

--------------------------------------------------------------------------------
-- Sichtbare Baerchis
--------------------------------------------------------------------------------

-- Beschriftung und Erschoepfungs-Zustand einer bereits stehenden Figur.
-- Getrennt vom Aufbau, weil sich HP staendig aendern und ein kompletter
-- Neuaufbau der Mesh-Figuren dafuer viel zu teuer waere.
local function writeFigureState(model: Model, rawHp: number, maxHp: number)
	local hp        = math.clamp(rawHp, 0, maxHp)
	local exhausted = hp <= 0

	local label = model:FindFirstChild("Health", true)
	if label and label:IsA("TextLabel") then
		label.Text = if exhausted
			then "erschoepft"
			else string.format("%d / %d HP", hp, maxHp)

		label.TextColor3 = if exhausted
			then Color3.fromRGB(255, 120, 120)
			elseif hp < maxHp * 0.34 then Color3.fromRGB(255, 205, 110)
			else Color3.fromRGB(190, 245, 195)
	end

	-- Ein erschoepfter Baerchi wird matt. Bewusst nicht komplett durchsichtig:
	-- er ist ausser Gefecht, nicht weg.
	--
	-- Die urspruengliche Transparenz jedes Teils steht als Attribut daran
	-- (gesetzt beim Aufbau). Sie einfach auf 0 zurueckzusetzen wuerde sonst
	-- absichtliche Durchsichtigkeit im importierten Modell zerstoeren — der
	-- Gummy-Baer ist genau dafuer ein Beispiel.
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local stored = part:GetAttribute("BaseTransparency")
			local base   = if typeof(stored) == "number" then stored else 0

			part.Transparency = if exhausted
				then math.max(base, MapConfig.BAERCHI_EXHAUSTED_TRANSPARENCY)
				else base
		end
	end
end

-- Wie writeFigureState, aber respektiert einen laufenden PIT-Kampf.
--
-- Waehrend eines Laufs gehoert die Figur dem PitArenaService: der Kampf ist
-- serverseitig schon ausgerechnet und die HP stehen bereits auf dem Endwert,
-- waehrend die Wiedergabe in der Arena noch laeuft. Wuerde hier
-- dazwischengeschrieben, saehe der Baerchi ab der ersten Sekunde erschoepft
-- aus statt am Ende. PitArenaService zieht den Zustand selbst nach.
local function writeBaerchiState(model: Model, baerchi: Types.Baerchi, maxHp: number)
	if model:GetAttribute("InArena") == true then
		return
	end

	writeFigureState(model, baerchi.currentHp, maxHp)
end

-- Eine Baerchi-Figur: das geklonte Pet-Mesh aus BaerchiMesh.build. Welches
-- Modell das ist (eigenes fuer diese Rarity oder der gemeinsame Platzhalter)
-- und ob es eingefaerbt wird, entscheidet BaerchiMesh selbst.
--
-- JEDE BasePart der Figur traegt das Attribut "BaerchiUid" und einen eigenen
-- ClickDetector — bei einem Mesh aus mehreren Teilen waere ein einzelner
-- Hitbereich schwer zu treffen. Der Client (WorldController) liest das
-- Attribut beim Klick und schlaegt die Details in seinem eigenen Datenstand
-- nach — dafuer braucht es kein zusaetzliches Remote.
--
-- Fehlt das Mesh-Template noch, gibt BaerchiMesh.build nil zurueck — dann
-- wird diese eine Figur uebersprungen, der Rest des Plots baut sich normal.
local function buildBaerchiFigure(parent: Instance, baerchi: Types.Baerchi, footPos: Vector3, facing: CFrame): Model?
	local color = BaerchiConfig.getRarityColor(baerchi.rarity)
	local def   = BaerchiConfig.getById(baerchi.configId)

	-- Ein MUTIERTER Baerchi (seit v11, ersetzt das fruehere binaere Inverted)
	-- bekommt die Farbe seiner Mutations-Stufe und leuchtet (siehe
	-- BaerchiMesh.build). Fuer alle anderen ist der vierte Parameter nil und
	-- es aendert sich nichts.
	local mutationColor = if baerchi.mutation
		then BaerchiConfig.getMutationColor(baerchi.mutation)
		else nil

	local model = BaerchiMesh.build(footPos, color, baerchi.rarity, mutationColor)
	if not model then
		return nil
	end
	model.Name = "Baerchi_" .. baerchi.uid

	-- BaerchiMesh stellt die Figur achsen-parallel hin. Hier wird sie noch in
	-- die Blickrichtung des Plots gedreht — und zwar um die senkrechte Achse
	-- DURCH footPos, nicht um den Modell-Pivot: wo der Pivot im importierten
	-- Mesh liegt, weiss dieses Modul nicht, eine Drehung darum wuerde die
	-- Figur seitlich wegschieben.
	local rotation = facing.Rotation
	local toOrigin = CFrame.new(-footPos)
	model:PivotTo(CFrame.new(footPos) * rotation * toOrigin * model:GetPivot())

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part:SetAttribute("BaerchiUid", baerchi.uid)

			-- Ausgangs-Transparenz merken, damit der Erschoepfungs-Zustand
			-- sie spaeter nicht ueberschreibt (siehe writeBaerchiState).
			part:SetAttribute("BaseTransparency", part.Transparency)

			local click = Instance.new("ClickDetector")
			click.MaxActivationDistance = MapConfig.BAERCHI_CLICK_DISTANCE
			click.Parent = part
		end
	end

	-- Rarity-Aura: ab Rare ein dezentes Dauer-Glitzern, ab Epic zusaetzlich ein
	-- PointLight. Nutzt dieselbe Farbe wie die Koerpereinfaerbung
	-- (BaerchiConfig.getRarityColor) — Seltenheit soll auch aus der Distanz auf
	-- einen Blick erkennbar sein, nicht erst beim Ranschauen des Namensschilds.
	-- Siehe DESIGN_VORSCHLAG_TRENDANALYSE_2026-09-11.md Abschnitt 5.
	--
	-- Haengt an EINEM zentralen Part (nicht an jedem BasePart wie der
	-- ClickDetector oben): ein Glitzern pro Teilstueck des Mesh saehe wie ein
	-- Funkensturm aus, nicht wie eine Aura.
	local auraAnchor = (model.PrimaryPart :: BasePart?) or (model:FindFirstChildWhichIsA("BasePart", true) :: BasePart?)
	if auraAnchor then
		local rarityKey = baerchi.rarity :: string

		if MapConfig.RARITY_AURA_MIN_SPARKLE[rarityKey] then
			local sparkle = Instance.new("ParticleEmitter")
			sparkle.Name          = "RarityAura"
			sparkle.Texture       = "rbxasset://textures/particles/sparkles_main.dds"
			sparkle.Color         = ColorSequence.new(color)
			sparkle.Size          = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.35),
				NumberSequenceKeypoint.new(1, 0),
			})
			sparkle.Transparency  = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.3),
				NumberSequenceKeypoint.new(1, 1),
			})
			sparkle.Lifetime      = NumberRange.new(0.8, 1.4)
			sparkle.Speed         = NumberRange.new(1, 3)
			sparkle.SpreadAngle   = Vector2.new(180, 180)
			sparkle.Rate          = MapConfig.RARITY_AURA_PARTICLE_RATE
			sparkle.Parent        = auraAnchor
		end

		if MapConfig.RARITY_AURA_MIN_LIGHT[rarityKey] then
			local light = Instance.new("PointLight")
			light.Name       = "RarityAuraLight"
			light.Color      = color
			light.Range      = MapConfig.RARITY_AURA_LIGHT_RANGE
			light.Brightness = MapConfig.RARITY_AURA_LIGHT_BRIGHTNESS
			light.Parent     = auraAnchor
		end

		-- Mutations-Aura (seit v11): unabhaengig von der Rarity-Aura oben, weil
		-- eine Mutation auch einen Common treffen kann, der sonst nie eine Aura
		-- haette. JEDE Mutation bekommt zumindest ein Punktlicht in ihrer
		-- eigenen Farbe; ab Multiplikator 4x (Celestial/Candy/Lava/Galaxy/
		-- Rainbow — siehe BaerchiConfig.MUTATIONS) zusaetzlich ein dichteres
		-- Glitzern, damit die seltensten Baerchis im Spiel auch aus der
		-- Distanz sofort als etwas Besonderes auffallen.
		if baerchi.mutation then
			local mutColor = BaerchiConfig.getMutationColor(baerchi.mutation)

			local mutLight = Instance.new("PointLight")
			mutLight.Name       = "MutationAuraLight"
			mutLight.Color      = mutColor
			mutLight.Range      = MapConfig.RARITY_AURA_LIGHT_RANGE
			mutLight.Brightness = MapConfig.RARITY_AURA_LIGHT_BRIGHTNESS * 1.5
			mutLight.Parent     = auraAnchor

			if BaerchiConfig.getMutationMultiplier(baerchi.mutation) >= 4 then
				local mutSparkle = Instance.new("ParticleEmitter")
				mutSparkle.Name          = "MutationAura"
				mutSparkle.Texture       = "rbxasset://textures/particles/sparkles_main.dds"
				mutSparkle.Color         = ColorSequence.new(mutColor)
				mutSparkle.Size          = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.5),
					NumberSequenceKeypoint.new(1, 0),
				})
				mutSparkle.Transparency  = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.15),
					NumberSequenceKeypoint.new(1, 1),
				})
				mutSparkle.Lifetime      = NumberRange.new(1.0, 1.8)
				mutSparkle.Speed         = NumberRange.new(2, 5)
				mutSparkle.SpreadAngle   = Vector2.new(180, 180)
				mutSparkle.Rate          = MapConfig.RARITY_AURA_PARTICLE_RATE * 2
				mutSparkle.Parent        = auraAnchor
			end
		end
	end

	-- Namensschild ueber dem Kopf (faellt auf den Body zurueck, falls das
	-- Template keinen Part namens "head" hat). Rekursiv gesucht: der Importer
	-- packt die Teile in eine Zwischen-Gruppe.
	--
	-- Drei Zeilen statt zwei seit dem Ei-Legen: Name+Level, HP, und ganz unten
	-- der Ei-Timer. Der Ei-Timer-Text wird HIER nur als leeres Label angelegt —
	-- befuellt wird er rein clientseitig (EggTimerController), weil er
	-- sekuendlich weiterzaehlt und dafuer keine Serverlast noetig ist (siehe
	-- Kommentar-Kopf dort).
	local labelAnchor = (model:FindFirstChild("head", true) :: BasePart?) or model.PrimaryPart
	if labelAnchor then
		local billboard = Instance.new("BillboardGui")
		billboard.Name        = "Label"
		billboard.Size        = UDim2.fromScale(6, 3.0)
		billboard.StudsOffset = Vector3.new(0, BaerchiMesh.getHeight(model) * 0.55 + 0.6, 0)
		billboard.AlwaysOnTop = false
		billboard.MaxDistance = MapConfig.BAERCHI_CLICK_DISTANCE
		billboard.Adornee     = labelAnchor
		billboard.Parent      = labelAnchor

		local name = newTextLabel("Name", billboard, UDim2.fromScale(1, 0.36), UDim2.fromScale(0, 0))
		name.Text = string.format(
			"%s%s  Lv.%d",
			-- Das Namensschild ist die zweite Stelle, an der eine Mutation
			-- auffaellt (die erste ist die leuchtende Mutations-Farbe der
			-- Figur selbst). Beides zusammen, weil die Farbe allein bei einer
			-- Rarity mit ungewohnter Palette nicht eindeutig genug waere —
			-- und weil ein Spieler lesen koennen soll, WELCHE der acht Stufen
			-- es genau ist (die Farbe allein verraet das nicht zuverlaessig).
			if baerchi.mutation then BaerchiConfig.getMutationBadge(baerchi.mutation) .. " " else "",
			def and def.displayName or baerchi.configId,
			baerchi.level
		)

		if baerchi.mutation then
			name.TextColor3 = BaerchiConfig.getMutationColor(baerchi.mutation)
		end

		newTextLabel("Health", billboard, UDim2.fromScale(1, 0.32), UDim2.fromScale(0, 0.36))

		local eggTimer = newTextLabel("EggTimer", billboard, UDim2.fromScale(1, 0.32), UDim2.fromScale(0, 0.68))
		eggTimer.TextColor3 = Color3.fromRGB(255, 224, 140)   -- Ei-Gold, passend zur HUD-Farbwelt
		eggTimer.Text        = ""   -- EggTimerController fuellt das im ersten Tick
	end

	model.Parent = parent
	return model
end

-- Maximale HP eines Baerchis. Liegt hier statt inline, weil sowohl der Aufbau
-- als auch die In-Place-Aktualisierung sie brauchen.
local function maxHpOf(baerchi: Types.Baerchi): number
	local def = BaerchiConfig.getById(baerchi.configId)
	if not def then return 1 end

	return CombatCalculator.getEffectiveStats(baerchi, def.baseStats).maxHp
end

--------------------------------------------------------------------------------
-- Gelegte Eier
--------------------------------------------------------------------------------

-- Ein gelegtes Ei in der Welt: eine kleine Kugel in der Farbe seines Ei-Typs,
-- mit einer kurzen Beschriftung darueber. Eingesammelt wird es, indem die
-- Spielfigur des BESITZERS hindurchlaeuft (Touched) — kein Klick mehr noetig.
--
-- Warum Touched statt ClickDetector: ein Ei anzuklicken heisst erst zielen,
-- dann treffen — bei bis zu zwoelf Eiern auf einem Plot ist das umstaendlich.
-- Der Spieler laesst seinen Baerchi ohnehin standig zum Honig-Teich und
-- zurueck laufen (siehe BaerchiAutopilotService) und hinterlaesst dabei eine
-- Spur aus Eiern — die sollen von selbst eingesammelt werden, sobald man
-- durchlaeuft.
--
-- Server-autoritativ, wie ueberall im Projekt: der Touch-Kontakt loest nicht
-- direkt EggLayService.collect aus (MapService kennt EggLayService nicht,
-- Ringschluss-Gefahr — siehe _eggCollectHandler), sondern ruft nur den
-- eingehaengten Handler auf. Der entscheidet autoritativ, ob das Ei noch da
-- ist und wem es gehoert.
local function buildLaidEgg(parent: Instance, egg: Types.LaidEgg, worldFoot: Vector3, owner: Player): Part?
	local def = EggConfig.data[egg.eggType]
	if not def then
		-- Ei-Typ aus der Config entfernt: still ueberspringen. Ein Ei ohne
		-- Farbe und Namen zu bauen waere schlimmer als keines.
		return nil
	end

	local size = EggConfig.LAY_EGG_SIZE

	local part = newPart(
		"LaidEgg_" .. egg.uid,
		size,
		-- Unterkante auf den Fusspunkt: die Kugel liegt auf dem Boden, statt
		-- zur Haelfte darin zu stecken.
		CFrame.new(worldFoot + Vector3.new(0, size.Y * 0.5, 0)),
		def.color,
		Enum.Material.SmoothPlastic
	)
	part.Shape      = Enum.PartType.Ball
	part.CanCollide = false   -- man soll durch Eier laufen koennen, nicht ueber sie stolpern
	part.Parent     = parent

	part:SetAttribute(LAID_EGG_ATTRIBUTE, egg.uid)

	-- Nur EIN erfolgreicher Touch-Kontakt darf einsammeln: Touched feuert
	-- fuer jeden Frame, in dem die Figur noch im Part steckt, erneut. Ohne
	-- diese Sperre wuerde derselbe Durchlauf den Handler viele Male aufrufen
	-- (harmlos, weil EggLayService.collect bei einem bereits entfernten Ei
	-- einfach nichts tut — aber unnoetige Anfragen).
	local collected = false
	local touchConnection: RBXScriptConnection? = nil
	touchConnection = part.Touched:Connect(function(hit: BasePart)
		if collected then return end

		local character = hit.Parent
		if not character then return end

		local toucher = Players:GetPlayerFromCharacter(character)
		if not toucher then return end

		-- Nur der Besitzer des Plots sammelt sein eigenes Ei ein — ein
		-- durchlaufender Nachbar soll fremde Eier nicht mitnehmen koennen.
		if toucher ~= owner then return end

		collected = true
		if touchConnection then
			touchConnection:Disconnect()
		end

		-- Partikel-Stoss in der Ei-Farbe AN WORKSPACE, nicht am "LaidEggs"-
		-- Ordner: der wird gleich durch den Datenwechsel neu aufgebaut
		-- (renderLaidEggs zerstoert ihn komplett), der Burst soll das
		-- ueberleben statt mitten in der Animation zu verschwinden.
		FigureFX.burstAt(part.Position, def.color, workspace)

		local handler = _eggCollectHandler
		if handler then
			handler(toucher, egg.uid)
		end
	end)

	local billboard = Instance.new("BillboardGui")
	billboard.Name        = "Label"
	billboard.Size        = UDim2.fromScale(4, 1.2)
	billboard.StudsOffset = Vector3.new(0, size.Y * 0.6 + 0.4, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = EggConfig.LAY_LABEL_DISTANCE
	billboard.Adornee     = part
	billboard.Parent      = part

	local label = newTextLabel("Name", billboard, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0))
	label.Text       = def.shortName
	label.TextColor3 = def.color

	return part
end

-- Baut ALLE herumliegenden Eier eines Plots neu.
--
-- Bewusst komplett neu statt einzeln nachzupflegen: es sind hoechstens
-- EggConfig.MAX_UNCOLLECTED_EGGS Stueck (zwoelf kleine Kugeln), und der
-- Vergleich "welches Ei ist neu, welches wurde eingesammelt" waere mehr Code
-- als der gesamte Neuaufbau. Die Baerchi-Figuren sind der Fall, wo sich der
-- Aufwand lohnt — ein Mesh ist um Groessenordnungen teurer als eine Kugel.
--
-- Die Positionen in den Daten sind PLOT-RELATIV (siehe Types.LaidEgg): hier
-- werden sie in Weltkoordinaten zurueckgerechnet.
local function renderLaidEggs(plotModel: Model, slot: number, islandData: Types.IslandData, owner: Player)
	local old = plotModel:FindFirstChild("LaidEggs")
	if old then old:Destroy() end

	local folder = Instance.new("Folder")
	folder.Name   = "LaidEggs"
	folder.Parent = plotModel

	-- Typisiert statt direkt aus islandData gelesen: ein Datenpaket von einem
	-- aelteren Serverstand haette das Feld nicht, und ohne die Annotation
	-- verliert die Schleife darunter den Typ.
	local eggs: { Types.LaidEgg } = islandData.laidEggs or {}
	if #eggs == 0 then
		return
	end

	local plotCFrame = _plotCFrames[slot]
	if not plotCFrame then return end

	for _, egg in eggs do
		local worldFoot = plotCFrame:PointToWorldSpace(Vector3.new(egg.x, egg.y, egg.z))
		buildLaidEgg(folder, egg, worldFoot, owner)
	end
end

-- Baut die sichtbare Baerchi-Figur eines Plots neu: seit dem Equip-System
-- steht dort hoechstens EINE — der ausgeruestete Baerchi. Alle anderen sind
-- reiner Inventar-Datensatz und werden nicht in die Welt gebaut. Ist keiner
-- ausgeruestet (leerer Plot, z.B. direkt nach einem Rebirth), bleibt der
-- Ordner einfach leer.
local function renderBaerchis(plotModel: Model, slot: number, islandData: Types.IslandData)
	local old = plotModel:FindFirstChild("Baerchis")
	if old then old:Destroy() end

	local folder = Instance.new("Folder")
	folder.Name   = "Baerchis"
	folder.Parent = plotModel

	local equippedUid = islandData.equippedUid
	local equipped = if equippedUid then islandData.baerchis[equippedUid] else nil
	if not equipped then
		return
	end

	local plotCFrame = _plotCFrames[slot]
	local home       = MapConfig.BAERCHI_HOME_OFFSET
	local footPos    = (plotCFrame * CFrame.new(home.X, plotSurfaceOffset() + home.Y, home.Z)).Position

	local figure = buildBaerchiFigure(folder, equipped, footPos, plotCFrame)
	if figure then
		writeBaerchiState(figure, equipped, maxHpOf(equipped))

		-- Eine frisch gebaute Figur steht — also atmet sie. Wer sie danach
		-- selbst bewegt (PitArenaService, BaerchiAutopilotService), meldet sie
		-- vorher ab und danach wieder an. Die alte Figur ist eine Zeile weiter
		-- oben zerstoert worden; ihr Registry-Eintrag raeumt sich beim
		-- naechsten Durchlauf des Idle-Loops selbst weg.
		FigureFX.idleBob(figure, {
			height = MapConfig.IDLE_BOB_HEIGHT,
			rate   = MapConfig.IDLE_BOB_RATE,
		})
	end
end

-- Baut den kompletten Inhalt eines Plots (Gebaeude + Bruecke + PIT + Baerchis).
local function buildPlotContents(plotModel: Model, slot: number, islandData: Types.IslandData, owner: Player)
	local pool = honeyPool(islandData)
	for _, building in islandData.buildings do
		buildBuilding(plotModel, slot, building, pool)
	end

	buildBridge(plotModel, slot)
	buildPit(plotModel, slot, islandData.pitLevel)
	buildPond(plotModel, slot, islandData)
	renderBaerchis(plotModel, slot, islandData)
	renderLaidEggs(plotModel, slot, islandData, owner)
end

--------------------------------------------------------------------------------
-- Oeffentliche API
--------------------------------------------------------------------------------

local MapService = {}

local function claimSlot(): number?
	if #_freeSlots == 0 then return nil end
	return table.remove(_freeSlots, 1)
end

local function releaseSlot(slot: number)
	table.insert(_freeSlots, slot)
	table.sort(_freeSlots)
end

function MapService.spawnIsland(player: Player, islandData: Types.IslandData)
	-- Alten Slot freigeben falls vorhanden (sollte nicht passieren, aber sicher)
	if _playerSlot[player] then
		MapService.despawnIsland(player)
	end

	local slot = claimSlot()
	if not slot then
		warn("[MapService] Kein freier Plot fuer Spieler:", player.Name)
		return
	end

	_playerSlot[player] = slot

	local plotModel = buildPlotBase(slot, player)
	_plotModels[player] = plotModel

	buildPlotContents(plotModel, slot, islandData, player)

	print("[MapService] Plot gespawnt fuer:", player.Name, "| Slot:", slot)
end

-- Baut den Plot eines Spielers komplett neu — behaelt aber seinen Slot,
-- damit er nach einem Rebirth an derselben Stelle der Map steht.
function MapService.rebuildIsland(player: Player, islandData: Types.IslandData)
	local slot = _playerSlot[player]
	if not slot then
		-- Noch kein Plot (z.B. Server voll) → normaler Spawn-Versuch
		MapService.spawnIsland(player, islandData)
		return
	end

	local oldModel = _plotModels[player]
	if oldModel then
		oldModel:Destroy()
	end

	local plotModel = buildPlotBase(slot, player)
	_plotModels[player] = plotModel

	buildPlotContents(plotModel, slot, islandData, player)

	print("[MapService] Plot neu aufgebaut fuer:", player.Name, "| Slot:", slot)
end

function MapService.despawnIsland(player: Player)
	-- Ein noch wartender Nachhol-Waechter hat hier nichts mehr zu tun. Er
	-- merkt das zwar selbst beim naechsten Durchlauf (kein Plot mehr), aber so
	-- bleibt kein Eintrag fuer einen laengst gegangenen Spieler stehen.
	_pendingRebuild[player] = nil

	local model = _plotModels[player]
	if model then
		model:Destroy()
		_plotModels[player] = nil
	end

	local slot = _playerSlot[player]
	if slot then
		releaseSlot(slot)
		_playerSlot[player] = nil
	end
end

-- Wird aufgerufen wenn PIT-Level steigt (siehe IslandService.upgradePit).
-- Baut nur die Arena neu, nicht den ganzen Plot.
function MapService.updatePitLevel(player: Player, newPitLevel: number)
	local model = _plotModels[player]
	if not model then return end

	local slot = _playerSlot[player]
	if not slot then return end

	buildPit(model, slot, newPitLevel)
	print("[MapService] PIT-Level aktualisiert fuer:", player.Name, "| Level:", newPitLevel)
end

-- Haengt die Quelle fuer frische IslandData ein (siehe _islandDataProvider).
-- Wird einmal beim Start von PlotDisplayService aufgerufen.
function MapService.setIslandDataProvider(provider: (Player) -> Types.IslandData?)
	_islandDataProvider = provider
end

-- Wartet, bis die Figur des Spielers nicht mehr in einer Bewegung steckt, und
-- baut sie dann mit FRISCH gelesenen Daten neu.
--
-- Frisch gelesen ist der entscheidende Teil: waehrend der Bewegung koennen
-- weitere Aenderungen anfallen (mehrere Level-Ups waehrend eines Ess-Zyklus),
-- und nach einem Rebirth ist die alte IslandData-Tabelle gar nicht mehr die
-- des Spielers — sie einfach aufzuheben und spaeter nochmal zu rendern wuerde
-- einen veralteten Stand in die Welt stellen.
local function scheduleRebuildWhenFree(player: Player)
	if _pendingRebuild[player] then return end
	_pendingRebuild[player] = true

	task.spawn(function()
		local interval = MapConfig.FIGURE_REBUILD_RETRY_SECONDS
		local waited   = 0

		while waited < MapConfig.FIGURE_REBUILD_TIMEOUT_SECONDS do
			task.wait(interval)
			waited += interval

			-- Spieler weg oder Plot abgeraeumt: es gibt nichts mehr nachzuholen.
			if player.Parent == nil or _plotModels[player] == nil then
				break
			end

			if ActivityLock.isFree(player) then
				local provider = _islandDataProvider
				local island   = if provider then provider(player) else nil

				-- Vor dem erneuten Aufruf freigeben: updateBaerchis darf, falls
				-- inzwischen doch wieder eine Bewegung laeuft, sauber einen
				-- neuen Waechter starten.
				_pendingRebuild[player] = nil

				if island then
					MapService.updateBaerchis(player, island)
				end
				return
			end
		end

		_pendingRebuild[player] = nil
	end)
end

-- Baut die sichtbaren Baerchis eines Spielers NEU. Teuer — nur aufrufen wenn
-- sich der Bestand oder ein Level geaendert hat (siehe PlotDisplayService).
--
-- Steckt die Figur gerade in einer Bewegung, wird der Neuaufbau verschoben
-- statt sie mitten im Schritt zu ersetzen (Begruendung im Kopf der Datei).
function MapService.updateBaerchis(player: Player, islandData: Types.IslandData)
	local model = _plotModels[player]
	if not model then return end

	local slot = _playerSlot[player]
	if not slot then return end

	if not ActivityLock.isFree(player) then
		scheduleRebuildWhenFree(player)
		return
	end

	renderBaerchis(model, slot, islandData)
	renderLaidEggs(model, slot, islandData, player)
end

-- Baut die herumliegenden Eier eines Spielers neu.
--
-- Anders als updateBaerchis KEINE ActivityLock-Pruefung: Eier bewegen sich
-- nicht und gehoeren niemandem, der sie gerade animiert. Sie duerfen deshalb
-- auch mitten in einem Kampf oder Weg zum Teich erscheinen und verschwinden —
-- genau das muss sogar sein, weil der Baerchi WAEHREND er laeuft legt.
function MapService.updateLaidEggs(player: Player, islandData: Types.IslandData)
	local model = _plotModels[player]
	if not model then return end

	local slot = _playerSlot[player]
	if not slot then return end

	renderLaidEggs(model, slot, islandData, player)
end

-- Haengt den Ei-Einsammel-Handler ein (siehe _eggCollectHandler). Wird einmal
-- beim Start von EggLayService aufgerufen.
function MapService.setEggCollectHandler(handler: (Player, string) -> ())
	_eggCollectHandler = handler
end

-- Rechnet eine Weltposition in das Koordinatensystem des Plots um.
--
-- Gelegte Eier werden PLOT-RELATIV gespeichert, nicht in Weltkoordinaten. Der
-- Grund: welchen der acht Plots ein Spieler bekommt, entscheidet sich bei
-- jedem Join neu (siehe _freeSlots). Absolute Positionen wuerden nach einem
-- Rejoin auf einem anderen Plot liegen — im schlimmsten Fall auf dem eines
-- Nachbarn.
function MapService.worldToPlot(player: Player, worldPosition: Vector3): Vector3?
	local slot = _playerSlot[player]
	if not slot then return nil end

	local plotCFrame = _plotCFrames[slot]
	if not plotCFrame then return nil end

	return plotCFrame:PointToObjectSpace(worldPosition)
end

-- Aktualisiert nur Beschriftung und Erschoepfung der bereits stehenden
-- Figuren. Billig — das ist der Weg fuer HP-Aenderungen.
function MapService.updateBaerchiStates(player: Player, islandData: Types.IslandData)
	local model = _plotModels[player]
	if not model then return end

	local folder = model:FindFirstChild("Baerchis")
	if not folder then return end

	for _, baerchi in islandData.baerchis do
		local figure = folder:FindFirstChild("Baerchi_" .. baerchi.uid)
		if figure and figure:IsA("Model") then
			writeBaerchiState(figure, baerchi, maxHpOf(baerchi))
		end
	end
end

-- Aktualisiert das Level-Attribut einer Gebaeude-Part (fuer Client-UI).
-- Wird nach einem Gebaeude-Upgrade aufgerufen; baut nichts neu.
function MapService.updateBuildingLevel(player: Player, buildingId: Types.BuildingId, level: number)
	local model = _plotModels[player]
	if not model then return end

	local part = model:FindFirstChild(buildingId)
	if part then
		part:SetAttribute("BuildingLevel", level)
	end
end

-- Wohin der Baerchi zum Fressen laeuft.
--
-- Das ist der Standplatz VOR dem Becken (auf den Bohlen), nicht mehr die
-- Beckenmitte. Bis der Teich ein richtiges Becken wurde, war beides dasselbe
-- — und der Baerchi stand mitten im Teich. Jetzt stuende er bis zum Bauch im
-- Beckenboden.
function MapService.getPondPosition(player: Player): Vector3?
	local slot = _playerSlot[player]
	if not slot then return nil end
	return pondStand(slot).Position
end

-- Fuellstand des Teichs nachziehen. Billig — das ist der Weg fuer
-- Honig-Aenderungen (siehe MapService.updateBuildingSigns, das das mit
-- aufruft, weil beides an denselben Werten haengt).
function MapService.updatePondFill(player: Player, islandData: Types.IslandData)
	local model = _plotModels[player]
	if not model then return end

	local slot = _playerSlot[player]
	if not slot then return end

	local pond = model:FindFirstChild("Pond")
	if not pond then return end

	local fill = pond:FindFirstChild("Fuellung")
	if fill and fill:IsA("BasePart") then
		writePondFill(fill, pondGround(slot), pondFillRatio(islandData))
	end
end

-- Schreibt Level und Honig-Lagerstand auf die Gebaeude-Schilder.
-- Billig — das ist der Weg fuer Honig-Aenderungen.
function MapService.updateBuildingSigns(player: Player, islandData: Types.IslandData)
	local model = _plotModels[player]
	if not model then return end

	local pool = honeyPool(islandData)

	for _, building in islandData.buildings do
		local part = model:FindFirstChild(building.id)
		if part and part:IsA("BasePart") then
			part:SetAttribute("BuildingLevel", building.level)
			writeBuildingState(part, building, pool)
		end
	end

	-- Haengt an denselben Werten wie die Gebaeude-Schilder — deshalb hier
	-- gleich mit erledigt statt eines eigenen Aufrufers in PlotDisplayService.
	MapService.updatePondFill(player, islandData)
end

-- Die Anzeigetafel ueber der Arena. Bewusst ueber den exakten Pfad gesucht und
-- nicht rekursiv: unter dem Plot haengen bis zu 25 importierte Mesh-Figuren,
-- deren Teilenamen aus einer .glb stammen und die wir nicht kontrollieren.
-- Eine rekursive Suche wuerde bei einem gleichnamigen Teil das Falsche finden
-- — und muesste bei jeder der bis zu 60 Stages den ganzen Baum durchlaufen.
local function findPitBanner(player: Player): BillboardGui?
	local model = _plotModels[player]
	if not model then return nil end

	local platform = model:FindFirstChild("PitPlatform")
	if not platform then return nil end

	local anchor = platform:FindFirstChild("PitBannerAnchor")
	if not anchor then return nil end

	local banner = anchor:FindFirstChild("Banner")
	return if banner and banner:IsA("BillboardGui") then banner else nil
end

-- Die Anzeigetafel ueber der Arena beschriften und einblenden.
-- Aufgerufen von PitArenaService waehrend einer Wiedergabe; MapService kennt
-- den Kampfverlauf nicht und entscheidet deshalb nichts ueber den Inhalt.
function MapService.setPitBanner(player: Player, title: string, subtitle: string, color: Color3)
	local banner = findPitBanner(player)
	if not banner then return end

	local titleLabel = banner:FindFirstChild("Title")
	if titleLabel and titleLabel:IsA("TextLabel") then
		titleLabel.Text       = title
		titleLabel.TextColor3 = color
	end

	local subLabel = banner:FindFirstChild("Sub")
	if subLabel and subLabel:IsA("TextLabel") then
		subLabel.Text = subtitle
	end

	banner.Enabled = true
end

-- Tafel wieder ausblenden. Idempotent — ein zweiter Aufruf schadet nicht.
function MapService.clearPitBanner(player: Player)
	local banner = findPitBanner(player)
	if banner then
		banner.Enabled = false
	end
end

--------------------------------------------------------------------------------
-- Event-Pit: Farbe und Anzeigetafel von aussen setzbar (EventService)
--------------------------------------------------------------------------------

-- Anders als findPitBanner gibt es das Event-Pit nur EINMAL fuer die ganze
-- Welt, nicht pro Spieler — keine Player-Suche noetig.
local function findEventPitContainer(): Model?
	local platform = workspace:FindFirstChild("Platform")
	if not platform then return nil end

	local pit = platform:FindFirstChild("EventPit")
	return if pit and pit:IsA("Model") then pit else nil
end

export type EventTheme = {
	floorColor : Color3,
	fenceColor : Color3,
	ringColor  : Color3,
}

-- Faerbt Boden, Zaun und Ring des Event-Pits um. Mit `theme = nil` kehrt es
-- zum schlichten Stall-Look zurueck (siehe MapConfig, EVENT_PIT_DEFAULT_*).
-- EventService ruft das genau zweimal pro Zyklus: einmal beim Start eines
-- Events mit dessen Farben, einmal beim Ende mit nil.
function MapService.setEventPitTheme(theme: EventTheme?)
	local container = findEventPitContainer()
	if not container then return end

	local floorColor = if theme then theme.floorColor else MapConfig.EVENT_PIT_DEFAULT_FLOOR_COLOR
	local fenceColor = if theme then theme.fenceColor else MapConfig.EVENT_PIT_DEFAULT_FENCE_COLOR
	local ringColor  = if theme then theme.ringColor  else MapConfig.EVENT_PIT_DEFAULT_RING_COLOR

	-- Material wechselt mit: Wood/SmoothPlastic im Stall-Look, Neon waehrend
	-- eines Events — sonst saehe man den Farbwechsel bei Zaun und Ring kaum,
	-- weil beide im Stall-Look bewusst matt sind.
	local activeMaterial = if theme then Enum.Material.Neon else Enum.Material.Wood
	local ringMaterial   = if theme then Enum.Material.Neon else Enum.Material.SmoothPlastic

	local floor = container:FindFirstChild("EventFloor")
	if floor and floor:IsA("BasePart") then
		floor.Color = floorColor
	end

	local ring = container:FindFirstChild("EventRing")
	if ring and ring:IsA("BasePart") then
		ring.Color    = ringColor
		ring.Material = ringMaterial
	end

	for _, child in container:GetChildren() do
		if child.Name:match("^EventFence_") and child:IsA("BasePart") then
			child.Color    = fenceColor
			child.Material = activeMaterial
		end
	end
end

-- Beschriftet die Countdown-Tafel ueber dem Event-Pit. Anders als
-- setPitBanner blendet das hier NICHT ein/aus — die Tafel steht permanent
-- (siehe buildEventPit): sie zeigt entweder den Countdown bis zum naechsten
-- Event oder Name + Restzeit des laufenden.
function MapService.setEventBanner(title: string, subtitle: string, color: Color3)
	local container = findEventPitContainer()
	if not container then return end

	local anchor = container:FindFirstChild("EventBannerAnchor")
	if not anchor then return end

	local banner = anchor:FindFirstChild("Banner")
	if not (banner and banner:IsA("BillboardGui")) then return end

	local titleLabel = banner:FindFirstChild("Title")
	if titleLabel and titleLabel:IsA("TextLabel") then
		titleLabel.Text       = title
		titleLabel.TextColor3 = color
	end

	local subLabel = banner:FindFirstChild("Sub")
	if subLabel and subLabel:IsA("TextLabel") then
		subLabel.Text = subtitle
	end
end

-- Weltposition der PODEST-OBERFLAECHE des Event-Pits in der Weltmitte.
--
-- Anders als getPitPosition NICHT pro Spieler: das Event-Pit gibt es einmal
-- fuer die ganze Welt (siehe findEventPitContainer). EventParticipationService
-- laesst die Figuren aller teilnehmenden Spieler auf dieselbe Flaeche laufen.
--
-- Der Y-Wert ist dieselbe Rechnung wie in buildEventPit (`floorY`), bewusst
-- aus MapConfig neu gerechnet statt aus der gebauten Geometrie gemessen: die
-- Zahl gehoert der Konfiguration, nicht dem Modell.
function MapService.getEventPitPosition(): Vector3
	local center = MapConfig.CENTER
	local floorY = MapConfig.PLATFORM_TOP_Y
		+ MapConfig.EVENT_PIT_GROUND_CLEARANCE
		+ MapConfig.EVENT_PIT_FLOOR_HEIGHT

	return Vector3.new(center.X, floorY, center.Z)
end

-- Radius der begehbaren Event-Flaeche. EventParticipationService prueft damit
-- serverseitig nach, ob eine Figur tatsaechlich noch dort steht, statt sich auf
-- ein gesetztes Flag zu verlassen.
function MapService.getEventPitRadius(): number
	return MapConfig.EVENT_PIT_RADIUS
end

-- Weltposition der Kampfflaeche dieses Spielers.
-- Wird von PitArenaService benoetigt um die Kaempfer zu platzieren.
function MapService.getPitPosition(player: Player): Vector3?
	local slot = _playerSlot[player]
	if not slot then return nil end
	return pitCenter(slot)
end

-- Das CFrame des Plots (Blickrichtung zur Plattform-Mitte).
-- PitArenaService braucht es, um die Kaempfer sinnvoll auszurichten.
function MapService.getPlotCFrame(player: Player): CFrame?
	local slot = _playerSlot[player]
	if not slot then return nil end
	return _plotCFrames[slot]
end

-- Die stehende Figur eines Baerchis auf dem Plot, falls vorhanden.
-- PitArenaService schickt genau diese Figur in die Arena und wieder zurueck,
-- statt eine zweite Kopie zu bauen — sonst staende derselbe Baerchi doppelt
-- in der Welt.
function MapService.getBaerchiModel(player: Player, baerchiUid: string): Model?
	local model = _plotModels[player]
	if not model then return nil end

	local folder = model:FindFirstChild("Baerchis")
	if not folder then return nil end

	local figure = folder:FindFirstChild("Baerchi_" .. baerchiUid)
	if figure and figure:IsA("Model") then
		return figure
	end
	return nil
end

-- Feiert ein Ereignis (Level-Up, Promotion, Rebirth, ...) SICHTBAR auf dem
-- Plot: Partikel-Stoss, Huepfer, kurzes Aufleuchten (siehe FigureFX.celebrate).
--
-- Bewusst als eigene MapService-Funktion und nicht direkt FigureFX.celebrate
-- vom Aufrufer: der Aufrufer (HoneyService, PromotionService, RebirthService,
-- ...) soll keine Modelle aus der Welt heraussuchen muessen — genau wie bei
-- getBaerchiModel bleibt das MapServices Job. Steht die Figur gerade nicht in
-- der Welt (Plot noch nicht gebaut, Bewegung verzoegert den Neuaufbau), passiert
-- einfach nichts — kein Fehler, der Toast-Text kommt ja trotzdem an.
function MapService.celebrateBaerchi(player: Player, baerchiUid: string, color: Color3)
	local model = MapService.getBaerchiModel(player, baerchiUid)
	if not model then return end

	FigureFX.celebrate(model, color)
end

-- Beschriftung und Transparenz einer Figur mit einem AUSDRUECKLICH
-- angegebenen HP-Wert setzen — auch waehrend eines laufenden PIT-Kampfes.
--
-- Nur fuer PitArenaService: der muss die Figur beim Start der Wiedergabe auf
-- die HP zuruecksetzen, mit denen der Lauf BEGONNEN hat. Die gespeicherten HP
-- stehen zu dem Zeitpunkt laengst auf dem Endwert, der Baerchi saehe sonst
-- schon vor dem ersten Schlag erschoepft aus.
function MapService.setFigureState(model: Model, hp: number, maxHp: number)
	writeFigureState(model, hp, maxHp)
end

-- Der Ordner in der Arena, in den die Kampf-Figuren gehoeren.
function MapService.getFighterFolder(player: Player): Folder?
	local model = _plotModels[player]
	if not model then return nil end

	local pit = model:FindFirstChild("PitPlatform")
	if not pit then return nil end

	local fighters = pit:FindFirstChild("Fighters")
	if fighters and fighters:IsA("Folder") then
		return fighters
	end
	return nil
end

-- Baut den PIT-Turm auf genau `level` Etagen aus bzw. ab — idempotent: fehlt
-- eine Etage, wird sie ergaenzt; ist eine zu viel da, wird sie entfernt. Mit
-- `level = 0` verschwindet der Turm komplett.
--
-- PitArenaService ruft das bei jeder Stage mit der neuen Stufenzahl auf, und
-- mit 0 sobald ein Lauf zu Ende ist oder ein neuer beginnt — der Turm bleibt
-- also NIE zwischen zwei Laeufen stehen, genau wie die Kampf-Figuren selbst
-- (siehe clearFighters in PitArenaService).
--
-- Bewegt bei einem Aufbau auch die Anzeigetafel-Verankerung mit nach oben,
-- damit sie ueber dem gewachsenen Turm haengen bleibt statt mittendrin zu
-- stecken.
function MapService.setPitTowerLevel(player: Player, level: number)
	local slot  = _playerSlot[player]
	local model = _plotModels[player]
	if not slot or not model then return end

	local container = model:FindFirstChild("PitPlatform")
	if not container then return end

	local tower = container:FindFirstChild("Tower")
	if not (tower and tower:IsA("Folder")) then return end

	local wanted = math.max(0, math.floor(level))
	local center = pitCenter(slot)

	for _, child in tower:GetChildren() do
		local index = tonumber(child.Name:match("^Ring_(%d+)$"))
		if not index or index > wanted then
			child:Destroy()
		end
	end

	for i = 1, wanted do
		if not tower:FindFirstChild("Ring_" .. i) then
			buildTowerRing(tower, center, i)
		end
	end

	local anchor = container:FindFirstChild("PitBannerAnchor")
	if anchor and anchor:IsA("BasePart") then
		local topY = MapConfig.PLATFORM_TOP_Y
			+ wanted * MapConfig.PIT_TOWER_STEP_HEIGHT
			+ MapConfig.PIT_BANNER_HEIGHT
		anchor.CFrame = CFrame.new(center.X, topY, center.Z)
	end

	-- Die staendigen PIT-Level-Saeulen (buildPit, "PitPillar_i") sitzen auf
	-- fester Hoehe knapp ueber PLATFORM_TOP_Y — genau der Bereich, den der
	-- Turm mit seinen vollflaechigen Etagen-Scheiben (gleicher Radius wie die
	-- Kampfflaeche) Stufe fuer Stufe ueberdeckt. Ohne diese Ausblendung
	-- wuerden die Saeulen mit steigendem Turm zunehmend darin verschwinden
	-- und nur noch mit der Spitze oben herausschauen — sieht wie
	-- durchgeklippte Geometrie aus, ist aber nur diese Kollision zweier
	-- Deko-Elemente aus verschiedenen Systemen (permanentes PIT-Level vs.
	-- Lauf-Turm). Deshalb: sobald ein Turm steht, Saeulen weg; sobald er auf
	-- 0 ist (kein Lauf aktiv), wieder da.
	local hidePillars = wanted > 0
	for _, child in container:GetChildren() do
		if child:IsA("BasePart") and child.Name:match("^PitPillar_") then
			child.Transparency = if hidePillars then 1 else 0
			child.CanCollide   = not hidePillars
			child.CanQuery     = not hidePillars
		end
	end
end

-- Hoehe (Y ueber PLATFORM_TOP_Y) der Kampfflaeche bei `level` bereits
-- gewachsenen Etagen. PitArenaService braucht das, um die Kaempfer beim
-- Erklimmen jeder Stage auf die richtige Hoehe zu stellen — dieselbe Formel
-- wie in buildTowerRing, hier aber ohne selbst eine Etage zu bauen.
function MapService.getPitTowerFloorY(level: number): number
	return MapConfig.PLATFORM_TOP_Y + math.max(0, level) * MapConfig.PIT_TOWER_STEP_HEIGHT
end

function MapService.init()
	-- Plot-CFrames und freie Slots einmalig aufbauen
	for slot = 1, MapConfig.PLOT_COUNT do
		_plotCFrames[slot] = buildPlotCFrame(slot)
		table.insert(_freeSlots, slot)
	end

	-- ============================================================
	-- GEOMETRIE-PRUEFUNG
	-- ============================================================
	-- Die Weltgeometrie haengt an einem guten Dutzend Zahlen, die voneinander
	-- abhaengen. Faellt eine aus dem Rahmen, sieht man das im fertigen Spiel als
	-- Loch im Boden oder als Insel im Nichts — und sucht dann im Code statt in
	-- der Config. Diese vier Pruefungen sagen es beim Start, im Klartext.
	--
	-- Sie WARNEN nur und brechen nicht ab: eine Welt mit einer schiefen Zahl ist
	-- immer noch spielbar, und ein harter Abbruch beim Serverstart waere die
	-- schlechtere Rueckmeldung.

	-- 1. Passt das quadratische Beet auf die runde Plot-Insel? Entscheidend ist
	--    die ECKE, nicht die Kante — eine halbe Diagonale, nicht eine halbe Seite.
	local plateCorner = math.sqrt(
		(MapConfig.PLOT_SIZE.X * 0.5) ^ 2 + (MapConfig.PLOT_SIZE.Z * 0.5) ^ 2
	)
	if plateCorner > MapConfig.PLOT_ISLAND_RADIUS then
		warn(
			"[MapService] Das Beet ragt ueber die Plot-Insel:",
			"halbe Diagonale von PLOT_SIZE =", string.format("%.1f", plateCorner),
			"> PLOT_ISLAND_RADIUS =", MapConfig.PLOT_ISLAND_RADIUS
		)
	end

	-- 2. Liegt der Plot-Ring wirklich eine Steglaenge vor der Hauptinsel?
	--    Sonst waere der Steg entweder zu kurz (Luecke) oder zu lang (er endet
	--    auf der Insel).
	local expectedRing = MapConfig.PLATFORM_RADIUS + MapConfig.ISLAND_GAP + MapConfig.PLOT_ISLAND_RADIUS
	if math.abs(MapConfig.PLOT_RING_RADIUS - expectedRing) > 0.5 then
		warn(
			"[MapService] PLOT_RING_RADIUS passt nicht zur Luecke:",
			MapConfig.PLOT_RING_RADIUS, "sollte", expectedRing, "sein",
			"(PLATFORM_RADIUS + ISLAND_GAP + PLOT_ISLAND_RADIUS)"
		)
	end

	-- 3. Beruehren sich zwei benachbarte Plot-Inseln samt Sandkante?
	local shoreRadius = MapConfig.PLOT_ISLAND_RADIUS + MapConfig.SHORE_WIDTH
	local neighbourGap = 2 * MapConfig.PLOT_RING_RADIUS
		* math.sin(math.pi / MapConfig.PLOT_COUNT) - 2 * shoreRadius
	if neighbourGap <= 0 then
		warn(
			"[MapService] Die Plot-Inseln ueberlappen sich:",
			MapConfig.PLOT_COUNT, "Inseln mit Rand", shoreRadius,
			"auf Ring", MapConfig.PLOT_RING_RADIUS
		)
	end

	-- 4. Reicht das Wasser bis hinter die aeusserste Arena?
	local worldEdge = (pitCenter(1) - MapConfig.CENTER).Magnitude
		+ MapConfig.PIT_BASE_RADIUS + MapConfig.SHORE_WIDTH
	if worldEdge > MapConfig.WATER_RADIUS then
		warn(
			"[MapService] Die Arenen ragen ueber den Wasserrand:",
			"Weltrand =", string.format("%.0f", worldEdge),
			"> WATER_RADIUS =", MapConfig.WATER_RADIUS
		)
	end

	buildPlatform()
	buildGlobalLighting()

	-- Sicherheitsnetz: falls PlayerService den Leave-Fall mal verpasst,
	-- bleibt sonst ein Slot dauerhaft belegt.
	Players.PlayerRemoving:Connect(function(player)
		if _playerSlot[player] then
			MapService.despawnIsland(player)
		end
	end)

	print("[MapService] Initialisiert | Plots:", MapConfig.PLOT_COUNT)
end

return MapService
