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
-- 14.10. (Befehle jederzeit): Vorher gab es zwei Teilstuecke — dieses Modul fuer
-- Heimplatz <-> Mitte und `arenaRoute` in PitArenaService fuer Heimplatz <-> Arena.
-- Wer unterwegs umgelenkt wird (z. B. von der Arena direkt zum Event), startet
-- aber NICHT am Heimplatz, sondern irgendwo auf der Achse. Deshalb liegt jetzt
-- die ganze Achse hier, und route() nimmt von ihr genau die Punkte, die zwischen
-- Start und Ziel liegen. Start und Ziel duerfen irgendwo auf der Achse stehen.
--
-- Plot-lokal: -Z zeigt zur Mitte (Event), +Z nach aussen (Arena), +X ist die
-- rechte Hand. Die Achse ist in Z monoton, darum reicht der Vergleich der Z-Werte.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MapConfig = require(ReplicatedStorage.Config.MapConfig)

local PlotRoutes = {}

local SIDE_X = -12   -- Seitenabstand am Brunnen (Becken ~8.4 + Luft), frei von Recycler (+15)

-- Zwischen der Heimposition am Brunnen und der Beet-Kante zur Mitte laeuft der
-- Baerchi erst zur Seite (SIDE_X). Gilt nur fuer Start/Ziel auf dem Beet bis hierhin.
local FOUNTAIN_ZONE_Z = -26

type LanePoint = { p: Vector3, crossing: boolean }

-- Alle Wegpunkte von innen (Event) nach aussen (Arena), aufsteigend in Z.
-- `crossing` = Querung des ganzen Beets (SIDE_X-Bahn); nur noetig, wenn Start und
-- Ziel auf verschiedenen Seiten des Beets liegen.
local function lane(): { LanePoint }
	local beetTop   = MapConfig.PLOT_SIZE.Y
	local beetEdge  = MapConfig.PLOT_SIZE.Z * 0.5
	local deckY     = -MapConfig.BRIDGE_SINK
	local bridgeIn  = MapConfig.PLOT_ISLAND_RADIUS - 1
	local bridgeOut = MapConfig.PLOT_ISLAND_RADIUS + MapConfig.ISLAND_GAP + 1
	return {
		{ p = Vector3.new(0, 0, -(bridgeOut + 3)),                  crossing = false },   -- Hauptinsel (Event-Seite)
		{ p = Vector3.new(0, deckY, -bridgeOut),                    crossing = false },   -- Steg-Ende
		{ p = Vector3.new(0, deckY, -bridgeIn),                     crossing = false },   -- Steg-Anfang
		{ p = Vector3.new(0, 0, -(beetEdge + 1.6)),                 crossing = false },   -- unten auf der Wiese
		{ p = Vector3.new(SIDE_X, beetTop, -(beetEdge - 0.6)),      crossing = false },   -- Beet-Kante, am Schild vorbei
		{ p = Vector3.new(SIDE_X, beetTop, beetEdge - 0.6),         crossing = true  },   -- ueber das Beet in der Seitenbahn
		{ p = Vector3.new(0, beetTop, beetEdge - 0.6),              crossing = false },   -- Beet-Kante, Arena-Seite
		{ p = Vector3.new(0, 0, beetEdge + 1.6),                    crossing = false },   -- unten auf der Wiese
		{ p = Vector3.new(0, deckY, bridgeIn),                      crossing = false },   -- Steg-Anfang
		{ p = Vector3.new(0, deckY, bridgeOut),                     crossing = false },   -- Steg-Ende
		{ p = Vector3.new(0, 0, bridgeOut + 3),                     crossing = false },   -- in der Arena
	}
end

-- Von `from` nach `to` (Weltpunkte). Beide duerfen irgendwo auf der Achse liegen;
-- es werden nur die Punkte dazwischen genommen. Das erste Element ist `from`,
-- das letzte `to` — FigureWalker.walkPath folgt auch der Hoehe.
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

	-- Muss das ganze Beet gequert werden (von der Event-Seite zur Arena-Seite)?
	local crossesBeet = math.min(fromL.Z, toL.Z) < -(beetEdge - 0.6) - 0.5
		and math.max(fromL.Z, toL.Z) > (beetEdge - 0.6) + 0.5

	if inwards then
		-- Vom Brunnen (auf dem Beet) Richtung Mitte: erst zur Seite
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
		-- Von der Mitte zum Brunnen auf dem Beet: zuletzt zur Seite hinein
		if toL.Z > FOUNTAIN_ZONE_Z and toL.Z < beetEdge and fromL.Z < FOUNTAIN_ZONE_Z then
			add(Vector3.new(SIDE_X, toL.Y, toL.Z))
		end
	end

	table.insert(route, to)
	return route
end

return PlotRoutes
