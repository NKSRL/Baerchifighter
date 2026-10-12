--!strict
-- SoundZones.luau
-- ReplicatedStorage/Modules/SoundZones.luau
--
-- Einzige Zustaendigkeit:
--   - Wie laut jede Klang-Zone an einer Kamera-Position sein soll (Paket H,
--     "Welt aufwerten"), als REINE Funktion: Ufer, Wiese/Grillen, Honigmast,
--     Event-Pit, Wind an der Arena und in der Hoehe
--
-- Jedes Gewicht ist stetig in der Position (keine harten Kanten): wer ueber
-- die Map laeuft, hoert weiche Uebergaenge. `audible` waehlt die lautesten
-- MAX_AUDIBLE aus, der Rest bekommt 0. Testbar: sound_zones.test.lua.

local Config = script.Parent.Parent.Config
local MapConfig     = require(Config.MapConfig)
local WorldFXConfig = require(Config.WorldFXConfig)
local MapLayout     = require(script.Parent.MapLayout)

local SoundZones = {}

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function flatDist(a: Vector3, b: Vector3): number
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- Naechste Insel: (Abstand zur Mitte, Kuestenradius). Hauptinsel, alle
-- Plot-Inseln, alle Arena-Inseln (die festen Formeln, besetzt oder nicht).
local function nearestIsland(p: Vector3): (number, number)
	local shore = MapConfig.SHORE_WIDTH
	local bestGap, bestD, bestR = math.huge, 0, 0
	local function consider(center: Vector3, radius: number)
		local d = flatDist(p, center)
		local gap = d - (radius + shore)
		if gap < bestGap then
			bestGap, bestD, bestR = gap, d, radius + shore
		end
	end
	consider(MapConfig.CENTER, MapConfig.PLATFORM_RADIUS)
	for slot = 1, MapConfig.PLOT_COUNT do
		consider(MapLayout.plotCenter(slot), MapConfig.PLOT_ISLAND_RADIUS)
		consider(MapLayout.pitCenter(slot), MapConfig.PIT_BASE_RADIUS)
	end
	return bestD, bestR
end

-- Gewichte 0..1 je Klang. `dusk` 0..1 (Tageslauf), `eventLive` = Event laeuft.
function SoundZones.weights(p: Vector3, dusk: number, eventLive: boolean): { [string]: number }
	local cfg = WorldFXConfig.SOUNDSCAPE
	local d, coast = nearestIsland(p)
	local band = cfg.SHORE_BAND

	-- Ufer: an der Kueste voll, auf dem Wasser voll, ins Land hinein leiser
	local waves = if d >= coast then 1 else clamp01(1 - (coast - d) / band)
	-- Wiese: im Inselinneren voll, zur Kueste hin leiser
	local land = if d >= coast then 0 else clamp01((coast - d) / (band * 0.66))
	local night = clamp01((dusk - (cfg.NIGHT_FROM - 0.1)) / 0.2)
	night = night * night * (3 - 2 * night)

	local mastD = flatDist(p, MapConfig.CENTER)
	local drip = clamp01(1 - mastD / cfg.MAST_RADIUS)
	local crowd = if eventLive then clamp01(1 - mastD / cfg.PIT_RADIUS) else 0

	local arena = 0
	for slot = 1, MapConfig.PLOT_COUNT do
		arena = math.max(arena, clamp01(1 - flatDist(p, MapLayout.pitCenter(slot)) / cfg.ARENA_RADIUS))
	end
	local high = clamp01((p.Y - MapConfig.PLATFORM_TOP_Y - cfg.HIGH_FROM) / 60)
	local wind = clamp01(arena * 0.6 + high * 0.7)

	return {
		waves    = waves,
		meadow   = land * (1 - night),
		crickets = land * night,
		drip     = drip,
		crowd    = crowd,
		wind     = wind,
	}
end

-- Hoechstens MAX_AUDIBLE Klaenge mit Gewicht ueber MIN_WEIGHT, der Rest 0.
function SoundZones.audible(weights: { [string]: number }): { [string]: number }
	local cfg = WorldFXConfig.SOUNDSCAPE
	local names = {}
	for name, w in weights do
		if w > cfg.MIN_WEIGHT then table.insert(names, name) end
	end
	table.sort(names, function(a, b)
		if weights[a] == weights[b] then return a < b end
		return weights[a] > weights[b]
	end)
	local out = {}
	for name in weights do out[name] = 0 end
	for i = 1, math.min(cfg.MAX_AUDIBLE, #names) do
		out[names[i]] = weights[names[i]]
	end
	return out
end

return SoundZones
