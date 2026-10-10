--!strict
-- PondBuilder.luau
-- ServerScriptService/Util/MapBuild/PondBuilder.luau
--
-- Einzige Zustaendigkeit:
--   - Den Honig-Teich eines Plots bauen und seinen Fuellstand anzeigen
--
-- Der Fuellstand ist der gelagerte Honig aller Gebaeude (honeyPool). Der
-- ausgeruestete Baerchi isst am Steg (pondStand).
--
-- Teil von MapService: nur MapService (und die Builder untereinander)
-- benutzen dieses Modul. Es aendert keine Spielerdaten.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MapConfig        = require(ReplicatedStorage.Config.MapConfig)
local BuildingBehavior = require(ReplicatedStorage.Config.BuildingBehavior)
local Types            = require(ReplicatedStorage.Network.Types)

local MapParts = require(ServerScriptService.Util.MapBuild.MapParts)
local MapLayout = require(ReplicatedStorage.Modules.MapLayout)
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)

local PondBuilder = {}

-- Der gesamte Honig-Vorrat einer Insel.
--
-- Wird als Attribut an JEDES Gebaeude geschrieben, nicht nur der eigene
-- Bestand: gefuettert wird auf der Baerchi-Detailkarte, und dort stehen alle
-- drei Vorraete nebeneinander zur Wahl. Wer vor dem Bienenstock steht, soll
-- deshalb sehen, dass ueberhaupt noch Honig da ist — auch wenn er im Honigtopf
-- nebenan liegt.
function PondBuilder.honeyPool(islandData: Types.IslandData): number
	local total = 0
	for _, building in islandData.buildings do
		total += math.max(0, building.honey or 0)
	end
	return total
end

-- Wie voll der Teich angezeigt wird: Anteil des GESAMTEN Honig-Vorrats an der
-- Lagermenge, die diese Insel auf ihren AKTUELLEN Leveln fasst.
--
-- Bewusst die aktuelle und nicht die theoretisch maximale Menge: der
-- Bienenstock vergroessert sein Lager mit jedem Level, und ein Teich, der nach
-- einem Ausbau ploetzlich leerer aussieht, waere die falsche Rueckmeldung.
-- So heisst "voller Teich" immer dasselbe — alle Lager sind voll.
function PondBuilder.pondFillRatio(islandData: Types.IslandData): number
	local capacity = BuildingBehavior.getTotalCapacity(islandData.buildings)
	if capacity <= 0 then return 0 end
	return math.clamp(PondBuilder.honeyPool(islandData) / capacity, 0, 1)
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
function PondBuilder.pondGround(slot: number): CFrame
	local plotCFrame = MapParts.plotCFrame(slot)

	-- Lage und Richtung aus MapLayout (HONEY_POND_V2: Teich in der Plot-Mitte
	-- hinten, Standplatz nach +Z; sonst wie bisher zum Baerchi-Platz).
	local offset = MapLayout.pondOffset()
	local center = CFrame.new(offset.X, MapParts.plotSurfaceOffset() + offset.Y, offset.Z)
	local toHome = MapLayout.pondFacing()

	-- CFrame.lookAt richtet -Z auf das Ziel aus (siehe buildPlotCFrame).
	local facing = CFrame.lookAt(center.Position, center.Position + toHome)
	return plotCFrame * facing
end

-- Der Standplatz vor dem Becken: teich-lokal auf -Z, um Beckenrand plus
-- Abstand von der Mitte entfernt. Hier landet der Baerchi, hier liegen die
-- Bohlen, und genau hier hat der Steinkranz seine Luecke.
function PondBuilder.pondStandDistance(): number
	return MapLayout.pondStandDistance()
end

function PondBuilder.pondStand(slot: number): CFrame
	return PondBuilder.pondGround(slot) * CFrame.new(0, 0, -PondBuilder.pondStandDistance())
end

-- Setzt die Fuellhoehe der "Fuellung"-Part auf den aktuellen Vorrat. Getrennt
-- vom Aufbau, weil das bei jeder Honig-Aenderung laeuft (siehe
-- updateBuildingSigns) und deshalb billig bleiben muss — kein Neuaufbau.
--
-- `ground` ist derselbe Ursprung wie beim Aufbau: die Fuellung waechst von
-- dort nach oben, statt ueber die WELT-Position herumzurechnen (die haengt
-- vom Plot-Winkel ab und ist dafuer ungeeignet).
function PondBuilder.writePondFill(fill: BasePart, ground: CFrame, ratio: number)
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
function PondBuilder.buildPondDisc(parent: Instance, ground: CFrame, name: string, radius: number, top: number, color: Color3, material: Enum.Material)
	local disc = MapParts.newPart(
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
function PondBuilder.buildPondStones(parent: Instance, ground: CFrame)
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
			local stone = MapParts.newPart(
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
function PondBuilder.buildPondPlanks(parent: Instance, ground: CFrame)
	local stand = PondBuilder.pondStandDistance()
	local step: number = (MapConfig.POND_PLANK_SIZE.Z + MapConfig.POND_PLANK_GAP) * 0.5
	local y: number    = MapConfig.POND_PLANK_TOP - MapConfig.POND_PLANK_SIZE.Y * 0.5

	for i, offset in { -step, step } do
		local plank = MapParts.newPart(
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

	-- Pfloecke: kleine Pfosten an beiden Bohlen-Enden. CFrame.Angles(0, 0, 90)
	-- stellt den Zylinder AUFRECHT (seine Laenge ist Size.X) — deshalb muss
	-- auch die Hoehe aus Size.X kommen. 08.10.: vorher stand hier
	-- Size.Y * 0.4 (der Durchmesser), der Pfosten steckte 0.49 im Beet.
	for i, side in { -1, 1 } do
		local peg = MapParts.newPart(
			"Pflock_" .. i,
			MapConfig.POND_PEG_SIZE,
			ground * CFrame.new(side * MapConfig.POND_PEG_SPREAD, MapConfig.POND_PEG_SIZE.X * MapConfig.POND_PEG_LIFT, -stand)
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
function PondBuilder.buildPond(plotModel: Model, slot: number, islandData: Types.IslandData)
	local old = plotModel:FindFirstChild("Pond")
	if old then old:Destroy() end

	local ground = PondBuilder.pondGround(slot)

	local pond = Instance.new("Model")
	pond.Name   = "Pond"
	pond.Parent = plotModel

	-- Sandkante zuerst und TIEFER als der Beckenboden: nur so bleibt sie
	-- ringsum als Streifen sichtbar, ohne dass ein Ring aus Einzelteilen
	-- noetig waere — derselbe Trick wie am Ufer jeder Insel.
	PondBuilder.buildPondDisc(
		pond, ground, "Rand",
		MapConfig.POND_RADIUS + MapConfig.POND_RIM_WIDTH,
		MapConfig.POND_RIM_TOP,
		MapConfig.POND_RIM_COLOR,
		Enum.Material.Sand
	)
	PondBuilder.buildPondDisc(
		pond, ground, "Boden",
		MapConfig.POND_RADIUS,
		MapConfig.POND_FLOOR_TOP,
		MapConfig.POND_FLOOR_COLOR,
		Enum.Material.Slate
	)

	PondBuilder.buildPondStones(pond, ground)
	PondBuilder.buildPondPlanks(pond, ground)
	-- Mit HONEY_POND_V2 schmueckt der Brunnen (Gebaeude HoneyPond) das
	-- Becken; der Honigloeffel wuerde in seine Schale ragen.
	if not FeatureFlags.isOn("HONEY_POND_V2") then
		MapParts.buildDecor(pond, ground, MapConfig.POND_DECOR)
	end

	-- Als Platzhalter-Groesse angelegt — writePondFill setzt Groesse und
	-- Position gleich im Anschluss auf den echten Vorrat.
	local fill = MapParts.newPart(
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

	PondBuilder.writePondFill(fill, ground, PondBuilder.pondFillRatio(islandData))
end

return PondBuilder
