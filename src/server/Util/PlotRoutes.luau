--!strict
-- PlotRoutes.luau
-- ServerScriptService/Util/PlotRoutes.luau
--
-- Einzige Zustaendigkeit:
--   - Der Fussweg eines Baerchis zwischen BELIEBIGEN zwei Punkten entlang der
--     Wegachse eines Plots (Arena <-> Steg <-> Plot-Beet <-> Steg <-> Event-Mitte)
--     als Kette von Fusspunkten — um Brunnen, Schild und Stege herum statt als
--     Gerade durch alles hindurch (13.10., Playtest "laeuft durch die Bruecke").
--
-- Plot-lokal: -Z zeigt zur Mitte (Event), +Z nach aussen (Arena), +X ist die
-- rechte Hand. Die Achse ist in Z monoton, darum reicht der Vergleich der Z-Werte.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MapConfig = require(ReplicatedStorage.Config.MapConfig)

local PlotRoutes = {}

local SIDE_X = -12   -- Seitenabstand am Brunnen (Becken ~8.4 + Luft), frei von Recycler (+15)
local FOUNTAIN_ZONE_Z = -26
local INNER_BRIDGE_ARCH_H = 1.35   -- synchron mit HubPlazaBuilder.BRIDGE_ARCH_HEIGHT

type LanePoint = { p: Vector3, crossing: boolean }

local function innerBridgeY(localZ: number): number
	local radius    = MapConfig.PLOT_RING_RADIUS + localZ
	local innerEdge = MapConfig.PLATFORM_RADIUS - MapConfig.BRIDGE_OVERLAP
	local outerEdge = (MapConfig.PLOT_RING_RADIUS - MapConfig.PLOT_ISLAND_RADIUS) + MapConfig.BRIDGE_OVERLAP
	local t         = math.clamp((radius - innerEdge) / math.max(1e-3, outerEdge - innerEdge), 0, 1)
	return -MapConfig.BRIDGE_SINK + INNER_BRIDGE_ARCH_H * math.sin(math.pi * t)
end

-- Alle Wegpunkte von innen (Event) nach aussen (Arena), aufsteigend in Z.
local function lane(): { LanePoint }
	local beetTop   = MapConfig.PLOT_SIZE.Y
	local beetEdge  = MapConfig.PLOT_SIZE.Z * 0.5
	local deckY     = -MapConfig.BRIDGE_SINK
	local bridgeIn  = MapConfig.PLOT_ISLAND_RADIUS - 1
	local bridgeOut = MapConfig.PLOT_ISLAND_RADIUS + MapConfig.ISLAND_GAP + 1
	local pitFloorY = MapConfig.EVENT_PIT_GROUND_CLEARANCE + MapConfig.EVENT_PIT_FLOOR_HEIGHT
	local stairTopZ = -(MapConfig.PLOT_RING_RADIUS - 46.2)
	local stairBotZ = -(MapConfig.PLOT_RING_RADIUS - 52.0)

	local pts: { LanePoint } = {
		{ p = Vector3.new(0, pitFloorY, stairTopZ),                 crossing = false },   -- Event-Pit Oberkante Treppe
		{ p = Vector3.new(0, 0, stairBotZ),                         crossing = false },   -- Allee vor der Treppe
		{ p = Vector3.new(0, 0, -(bridgeOut + 3)),                  crossing = false },   -- Hauptinsel (Event-Seite)
	}

	-- Bogenverlauf ueber die innere Bogenbruecke (7 Stuetzpunkte fuer glatten Lauf)
	local archSteps = 6
	for k = 0, archSteps do
		local z = -bridgeOut + (k / archSteps) * (bridgeOut - bridgeIn)
		table.insert(pts, { p = Vector3.new(0, innerBridgeY(z), z), crossing = false })
	end

	table.insert(pts, { p = Vector3.new(0, 0, -(beetEdge + 1.6)),                 crossing = false })   -- unten auf der Wiese
	table.insert(pts, { p = Vector3.new(SIDE_X, beetTop, -(beetEdge - 0.6)),      crossing = false })   -- Beet-Kante, am Schild vorbei
	table.insert(pts, { p = Vector3.new(SIDE_X, beetTop, beetEdge - 0.6),         crossing = true  })   -- ueber das Beet in der Seitenbahn
	table.insert(pts, { p = Vector3.new(0, beetTop, beetEdge - 0.6),              crossing = false })   -- Beet-Kante, Arena-Seite
	table.insert(pts, { p = Vector3.new(0, 0, beetEdge + 1.6),                    crossing = false })   -- unten auf der Wiese
	table.insert(pts, { p = Vector3.new(0, deckY, bridgeIn),                      crossing = false })   -- Steg-Anfang
	table.insert(pts, { p = Vector3.new(0, deckY, bridgeOut),                     crossing = false })   -- Steg-Ende
	table.insert(pts, { p = Vector3.new(0, 0, bridgeOut + 3),                     crossing = false })   -- in der Arena

	return pts
end

function PlotRoutes.route(plotCFrame: CFrame, from: Vector3, to: Vector3): { Vector3 }
	local fromL = plotCFrame:PointToObjectSpace(from)
	local toL   = plotCFrame:PointToObjectSpace(to)
	local inwards = toL.Z < fromL.Z
	local pts = lane()
	local route: { Vector3 } = { from }

	local beetEdge = MapConfig.PLOT_SIZE.Z * 0.5

	local function add(p: Vector3)
		table.insert(route, plotCFrame:PointToWorldSpace(p))
	end

	local crossesBeet = math.min(fromL.Z, toL.Z) < -(beetEdge - 0.6) - 0.5
		and math.max(fromL.Z, toL.Z) > (beetEdge - 0.6) + 0.5

	if inwards then
		if fromL.Z > FOUNTAIN_ZONE_Z and fromL.Z < beetEdge and toL.Z < FOUNTAIN_ZONE_Z then
			add(Vector3.new(SIDE_X, fromL.Y, fromL.Z))
		end
		for i = #pts, 1, -1 do
			local lp = pts[i]
			if lp.p.Z < fromL.Z - 0.5 and lp.p.Z > toL.Z + 0.5 and (not lp.crossing or crossesBeet) then
				add(lp.p)
			end
		end
	else
		for i = 1, #pts do
			local lp = pts[i]
			if lp.p.Z > fromL.Z + 0.5 and lp.p.Z < toL.Z - 0.5 and (not lp.crossing or crossesBeet) then
				add(lp.p)
			end
		end
		if toL.Z > FOUNTAIN_ZONE_Z and toL.Z < beetEdge and fromL.Z < FOUNTAIN_ZONE_Z then
			add(Vector3.new(SIDE_X, toL.Y, toL.Z))
		end
	end

	table.insert(route, to)
	return route
end

return PlotRoutes
