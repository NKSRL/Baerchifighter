--!strict
-- RocketIslandRules.luau
-- ReplicatedStorage/Modules/RocketIslandRules.luau
--
-- Einzige Zustaendigkeit:
--   - Reine Regeln der Raketen-Insel (P4): Lage (aus Anker oder Platzhalter, mit Mindestabstaenden)
--     und der Schild-Zustand (gesperrt / bereit / gestartet) aus dem Spielstand.
--
-- Keine Instanzen, kein Speichern. Test: tools/luau-tests/rocket_island.test.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RocketIslandConfig = require(ReplicatedStorage.Config.RocketIslandConfig)
local MapConfig = require(ReplicatedStorage.Config.MapConfig)

export type View = {
	epilog : { state: string? }?,
	towers : { records: { [string]: number }? }?,
}

local RocketIslandRules = {}

-- Schild-Zustand: 3 = gestartet (epilog.state == "launched"), 2 = bereit (pending/seen, oder
-- Final-Rekord >= 100), sonst 1 = gesperrt.
function RocketIslandRules.state(view: View): number
	local epilogState = view.epilog and view.epilog.state
	if epilogState == "launched" then return RocketIslandConfig.STATE_LAUNCHED end
	if epilogState == "pending" or epilogState == "seen" then return RocketIslandConfig.STATE_READY end
	if RocketIslandRules.finalRecord(view) >= 100 then return RocketIslandConfig.STATE_READY end
	return RocketIslandConfig.STATE_LOCKED
end

function RocketIslandRules.finalRecord(view: View): number
	local records = view.towers and view.towers.records
	return (records and tonumber(records.Final)) or 0
end

-- Lage der Raketen-Insel von `slot`: auf der Achse des Plots HINTER der Arena-Insel (Fight-Pit).
-- anchor = Weltposition eines Ankers (oder nil -> berechnet). Gibt { center, outward, fromRadius, toRadius,
-- distance, placeholder, angleDeg } zurueck; `fromRadius` ist der Rand der Arena-Insel, `toRadius` der Rand der
-- Raketen-Insel (die Bruecke ueberspannt genau diese Luecke). `placeholder` = nicht aus einem Anker.
function RocketIslandRules.layout(slot: number, anchor: Vector3?): {
	center: Vector3, outward: Vector3, fromRadius: number, toRadius: number, distance: number, placeholder: boolean, angleDeg: number }
	local c = MapConfig.CENTER
	local R = RocketIslandConfig.ISLAND_RADIUS
	local angle = math.rad((slot - 1) * (360 / MapConfig.PLOT_COUNT))
	local outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
	local distance: number
	-- Rand der Arena-Insel (MapParts.pitCenter + PIT_BASE_RADIUS)
	local arenaEdge = MapConfig.PLOT_RING_RADIUS + MapConfig.PLOT_ISLAND_RADIUS + MapConfig.ISLAND_GAP + 2 * MapConfig.PIT_BASE_RADIUS
	if anchor then
		local flat = Vector3.new(anchor.X - c.X, 0, anchor.Z - c.Z)
		if flat.Magnitude < 1e-3 then
			distance = arenaEdge + RocketIslandConfig.GAP_FROM_ARENA + R
		else
			outward = flat.Unit
			distance = flat.Magnitude
		end
	else
		distance = arenaEdge + RocketIslandConfig.GAP_FROM_ARENA + R
	end
	distance = math.max(distance, arenaEdge + RocketIslandConfig.MIN_GAP_FROM_MAIN + R)
	return {
		center = Vector3.new(c.X + outward.X * distance, MapConfig.PLATFORM_TOP_Y, c.Z + outward.Z * distance),
		outward = outward,
		fromRadius = arenaEdge,
		toRadius = distance - R,
		distance = distance,
		placeholder = anchor == nil,
		angleDeg = math.deg(math.atan2(outward.Z, outward.X)) % 360,
	}
end

-- Kleinster Abstand zwischen dem Rand dieser Insel (`center`) und dem Rand aller ANDEREN Inseln: Plot-Inseln,
-- Arena-Inseln und der Raketen-Inseln der uebrigen Slots (positiv = frei). Wasser-Ufer (SHORE_WIDTH) zaehlt doppelt.
function RocketIslandRules.clearanceToIslands(center: Vector3, slot: number): number
	local best = math.huge
	local n = MapConfig.PLOT_COUNT
	local shore = MapConfig.SHORE_WIDTH * 2
	local R = RocketIslandConfig.ISLAND_RADIUS
	for other = 1, n do
		local angle = math.rad((other - 1) * (360 / n))
		local ox, oz = math.cos(angle), math.sin(angle)
		local function dist(radius: number): number
			return math.sqrt((center.X - MapConfig.CENTER.X - ox * radius) ^ 2 + (center.Z - MapConfig.CENTER.Z - oz * radius) ^ 2)
		end
		best = math.min(best, dist(MapConfig.PLOT_RING_RADIUS) - MapConfig.PLOT_ISLAND_RADIUS - R - shore)
		if other ~= slot then
			local arenaCenter = MapConfig.PLOT_RING_RADIUS + MapConfig.PLOT_ISLAND_RADIUS + MapConfig.ISLAND_GAP + MapConfig.PIT_BASE_RADIUS
			best = math.min(best, dist(arenaCenter) - MapConfig.PIT_BASE_RADIUS - R - shore)
			local rocketCenter = arenaCenter + MapConfig.PIT_BASE_RADIUS + RocketIslandConfig.GAP_FROM_ARENA + R
			best = math.min(best, dist(rocketCenter) - 2 * R - shore)
		end
	end
	return best
end

return RocketIslandRules
