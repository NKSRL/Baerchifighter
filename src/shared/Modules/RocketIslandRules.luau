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

-- Lage der Mini-Insel. anchor = Weltposition des Ankers (oder nil -> Platzhalter).
-- Gibt { center, outward, fromRadius, toRadius, distance, placeholder } zurueck; der Abstand
-- zur Mitte wird so geklemmt, dass zwischen Hauptinsel-Rand und Mini-Insel mindestens
-- MIN_GAP_FROM_MAIN Studs Wasser bleiben (die Bruecke ueberspannt genau diese Luecke).
function RocketIslandRules.layout(anchor: Vector3?): {
	center: Vector3, outward: Vector3, fromRadius: number, toRadius: number, distance: number, placeholder: boolean }
	local c = MapConfig.CENTER
	local R = RocketIslandConfig.ISLAND_RADIUS
	local placeholder = anchor == nil
	local outward: Vector3
	local distance: number
	if anchor then
		local flat = Vector3.new(anchor.X - c.X, 0, anchor.Z - c.Z)
		if flat.Magnitude < 1e-3 then
			outward = Vector3.new(1, 0, 0)
			distance = 0
		else
			outward = flat.Unit
			distance = flat.Magnitude
		end
	else
		local angle = math.rad(RocketIslandConfig.PLACEHOLDER_ANGLE_DEG)
		outward = Vector3.new(math.cos(angle), 0, math.sin(angle))
		-- ein Inselabstand hinter dem Hauptinsel-Rand (wie die Stege zu den Plot-Inseln)
		distance = MapConfig.PLATFORM_RADIUS + MapConfig.ISLAND_GAP + R
	end
	local minDistance = MapConfig.PLATFORM_RADIUS + RocketIslandConfig.MIN_GAP_FROM_MAIN + R
	distance = math.max(distance, minDistance)
	return {
		center = Vector3.new(c.X + outward.X * distance, MapConfig.PLATFORM_TOP_Y, c.Z + outward.Z * distance),
		outward = outward,
		fromRadius = MapConfig.PLATFORM_RADIUS,
		toRadius = distance - R,
		distance = distance,
		placeholder = placeholder,
	}
end

-- Kleinster Abstand zwischen den Raendern der Mini-Insel und aller Plot-Inseln (positiv = frei).
function RocketIslandRules.clearanceToPlots(center: Vector3): number
	local best = math.huge
	for slot = 1, MapConfig.PLOT_COUNT do
		local angle = math.rad((slot - 1) * (360 / MapConfig.PLOT_COUNT))
		local px = MapConfig.CENTER.X + MapConfig.PLOT_RING_RADIUS * math.cos(angle)
		local pz = MapConfig.CENTER.Z + MapConfig.PLOT_RING_RADIUS * math.sin(angle)
		local d = math.sqrt((center.X - px) ^ 2 + (center.Z - pz) ^ 2)
		best = math.min(best, d - MapConfig.PLOT_ISLAND_RADIUS - RocketIslandConfig.ISLAND_RADIUS - MapConfig.SHORE_WIDTH * 2)
	end
	return best
end

return RocketIslandRules
