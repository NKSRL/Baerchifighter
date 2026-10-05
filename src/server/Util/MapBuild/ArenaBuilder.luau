--!strict
-- ArenaBuilder.luau
-- ServerScriptService/Util/MapBuild/ArenaBuilder.luau
--
-- Einzige Zustaendigkeit:
--   - Den Steg zur Arena-Insel, die PIT-Arena, die Ringe des Lauf-Turms und
--     (v15) den staendigen Tower-Turm (Angeberflaeche) bauen
--
-- Die Arena ist eine flache Kampfflaeche. Seit v15 gibt es kein PIT-Level und
-- damit keine Saeulen mehr; den Fortschritt zeigt der Tower-Turm am aeusseren
-- Rand der Insel (Look = hoechster Tower, Hoehe = Rekord, MapConfig.TOWER_LOOKS).
--
-- Teil von MapService: nur MapService (und die Builder untereinander)
-- benutzen dieses Modul. Es aendert keine Spielerdaten.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MapConfig        = require(ReplicatedStorage.Config.MapConfig)
local TowerConfig      = require(ReplicatedStorage.Config.TowerConfig)

local MapParts = require(ServerScriptService.Util.MapBuild.MapParts)

local ArenaBuilder = {}

-- Der aeussere Steg: von der Plot-Insel des Spielers auf seine Arena-Insel.
-- Er gehoert zum Spieler und wird deshalb mit dessen Plot-Model gebaut — die
-- INNEREN Stege (Hauptinsel → Plot-Insel) stehen dagegen immer, siehe
-- buildPlatform.
function ArenaBuilder.buildBridge(plotModel: Model, slot: number)
	local islandEdge = MapConfig.PLOT_RING_RADIUS + MapConfig.PLOT_ISLAND_RADIUS

	MapParts.buildSpan(
		plotModel,
		"Bridge",
		MapParts.outwardDirection(slot),
		islandEdge,
		islandEdge + MapConfig.ISLAND_GAP
	)
end

-- Die PIT-Arena am Ende der Bruecke. Flache runde Kampfflaeche.
--
-- Die Kampfflaeche heisst bewusst weiterhin "FightFloor": WorldController
-- haengt genau an diesem Namen seinen Kampf-Prompt auf.
function ArenaBuilder.buildPit(plotModel: Model, slot: number)
	local old = plotModel:FindFirstChild("PitPlatform")
	if old then old:Destroy() end

	local container = Instance.new("Model")
	container.Name   = "PitPlatform"
	container.Parent = plotModel

	local center = MapParts.pitCenter(slot)

	-- Die Arena-Insel: derselbe Aufbau wie jede andere Insel (Sandkante plus
	-- Scheibe), damit sie nicht wie ein Fremdkoerper im Wasser steht. Ihre
	-- Oberflaeche ist der Sockel, auf dem der Steg landet.
	-- Der Sockel liegt PIT_RIM_DROP tiefer als die Kampfflaeche, sonst waeren
	-- die beiden Oberseiten deckungsgleich und wuerden flimmern.
	local rimY = MapConfig.PLATFORM_TOP_Y - MapConfig.PIT_RIM_DROP

	MapParts.buildIsland(
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
	local ring = MapParts.newPart(
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
	local floor = MapParts.newPart(
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
	local outward    = MapParts.outwardDirection(slot)
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
			local post = MapParts.newPart(
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
	local anchor = MapParts.newPart(
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

	local bannerTitle = MapParts.newTextLabel("Title", banner, UDim2.fromScale(1, 0.6), UDim2.fromScale(0, 0))
	bannerTitle.Text  = ""
	MapParts.newTextLabel("Sub", banner, UDim2.fromScale(1, 0.4), UDim2.fromScale(0, 0.6))
end

-- Eine einzelne Turm-Etage: eine Scheibe im selben Radius wie die
-- Kampfflaeche, die direkt auf der vorherigen aufsetzt. `level` ist 1-basiert
-- — Etage 1 ist die erste Scheibe UEBER der normalen Kampfflaeche.
function ArenaBuilder.buildTowerRing(tower: Folder, center: Vector3, level: number)
	local color = MapConfig.PIT_TOWER_COLORS[((level - 1) % #MapConfig.PIT_TOWER_COLORS) + 1]
	local topY  = MapConfig.PLATFORM_TOP_Y + level * MapConfig.PIT_TOWER_STEP_HEIGHT

	local ring = MapParts.newPart(
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
-- v15: der Tower-Turm (Angeberflaeche)
--------------------------------------------------------------------------------

export type ShowcaseView = {
	look   : string,   -- Schluessel in MapConfig.TOWER_LOOKS
	floors : number,   -- 1 .. TowerConfig.SHOWCASE_MAX_FLOORS
	title  : string,   -- Schild: "Name · Tower III · 42"
	color  : Color3,
}

-- Mitte des Turm-Fusses (Arena-Hoehe), aussen an der Arena-Insel.
function ArenaBuilder.showcaseFoot(slot: number): Vector3
	local center  = MapParts.pitCenter(slot)
	local outward = MapParts.outwardDirection(slot)
	local pos = center + outward * MapConfig.TOWER_SHOWCASE.distance
	return Vector3.new(pos.X, MapConfig.PLATFORM_TOP_Y, pos.Z)
end

-- Baut den Turm neu (der alte wird ersetzt). Teile: Sockel (bis ins Wasser),
-- `floors` Etagen aus dem Look, Spitze, Schild. Rein deklarativ aus
-- MapConfig.TOWER_LOOKS — Formaenderungen nur dort.
function ArenaBuilder.buildShowcase(plotModel: Model, slot: number, view: ShowcaseView): Model
	local old = plotModel:FindFirstChild("TowerShowcase")
	if old then old:Destroy() end

	local cfg  = MapConfig.TOWER_SHOWCASE
	local look = MapConfig.TOWER_LOOKS[view.look] or MapConfig.TOWER_LOOKS.Wood
	local foot = ArenaBuilder.showcaseFoot(slot)

	local container = Instance.new("Model")
	container.Name = "TowerShowcase"
	container:SetAttribute("Look", view.look)
	container:SetAttribute("Floors", view.floors)

	-- Sockel: vom Grund der Insel bis knapp ueber die Arena, damit der Turm
	-- nicht auf dem Wasser schwebt.
	local plinthHeight = MapConfig.ISLAND_HEIGHT + cfg.plinthHeight
	local plinth = MapParts.newPart(
		"Sockel",
		Vector3.new(plinthHeight, (cfg.radius + 1.2) * 2, (cfg.radius + 1.2) * 2),
		CFrame.new(foot.X, foot.Y + cfg.plinthHeight - plinthHeight * 0.5, foot.Z) * CFrame.Angles(0, 0, math.rad(90)),
		look.plinth,
		Enum.Material.Slate
	)
	plinth.Shape    = Enum.PartType.Cylinder
	plinth.CanQuery = false
	plinth.Parent   = container

	local floors = math.clamp(math.floor(view.floors), 1, TowerConfig.SHOWCASE_MAX_FLOORS)
	local baseY  = cfg.plinthHeight
	for i = 1, floors do
		local origin = CFrame.new(foot.X, foot.Y + baseY + (i - 1) * cfg.floorHeight, foot.Z)
		MapParts.buildDecor(container, origin, look.floor)
	end

	local topY = baseY + floors * cfg.floorHeight
	MapParts.buildDecor(container, CFrame.new(foot.X, foot.Y + topY, foot.Z), look.top)

	-- Schild ueber der Spitze (Name · Tower · Rekord).
	local anchor = MapParts.newPart(
		"SignAnchor",
		Vector3.new(1, 1, 1),
		CFrame.new(foot.X, foot.Y + topY + MapParts.decorHeight(look.top) + cfg.signGap, foot.Z),
		look.accent,
		Enum.Material.SmoothPlastic
	)
	anchor.Transparency = 1
	anchor.CanCollide   = false
	anchor.CanQuery     = false
	anchor.CanTouch     = false
	anchor.Parent       = container

	local sign = Instance.new("BillboardGui")
	sign.Name        = "Sign"
	sign.Size        = UDim2.fromScale(16, 2.4)
	sign.AlwaysOnTop = false
	sign.MaxDistance = cfg.signDistance
	sign.Adornee     = anchor
	sign.Parent      = anchor

	local title = MapParts.newTextLabel("Title", sign, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0))
	title.Text       = view.title
	title.TextColor3 = view.color

	container.Parent = plotModel
	return container
end

return ArenaBuilder
