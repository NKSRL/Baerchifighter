-- pit_v2.test.lua — Honig-Kolosseum (25.10.2026)
-- python tools/luau-tests/run_local.py tools/luau-tests/pit_v2.test.lua

local Rules = require(RS.Modules.PitV2Rules)
local Cfg = require(RS.Config.PitV2Config)
local MapConfig = require(RS.Config.MapConfig)
local WorldFXConfig = require(RS.Config.WorldFXConfig)

local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else
		failures += 1
		print("FAIL " .. name .. (if detail ~= nil then ": " .. tostring(detail) else ""))
	end
end

local function holesIn(arc, blocks)
	local holes = 0
	local steps = arc.segments * 8
	for k = 0, steps do
		local a = math.rad(arc.from + (arc.to - arc.from) * k / steps)
		for _, r in { arc.inner + 0.01, (arc.inner + arc.outer) * 0.5, arc.outer - 0.01 } do
			local x, y = r * math.cos(a), r * math.sin(a)
			local hit = false
			for _, b in blocks do
				if Rules.contains(b, x, y) then hit = true; break end
			end
			if not hit then holes += 1 end
		end
	end
	return holes
end

local function innerFace(blocks)
	local m = math.huge
	for _, b in blocks do
		m = math.min(m, math.sqrt(b.x * b.x + b.y * b.y) - b.radial * 0.5)
	end
	return m
end

-- 1) Mauer + Tribuene: Band lueckenlos, Kollision hoechstens 0.2 vor der Mauerkrone
local all = {}
for i, arc in Cfg.ARC_COLLIDERS do
	local blocks = Rules.arcBlocks(arc, Cfg.COLLIDER_OVERLAP)
	check("Bogen " .. i .. ": Anzahl Bloecke", #blocks == arc.segments, #blocks)
	check("Bogen " .. i .. ": Band lueckenlos", holesIn(arc, blocks) == 0, holesIn(arc, blocks))
	check("Bogen " .. i .. ": hoechstens 0.2 vor der Krone", innerFace(blocks) >= arc.inner - 0.2, innerFace(blocks))
	check("Bogen " .. i .. ": hoeher als ein Sprung von der Kampfflaeche", arc.top - (MapConfig.PLATFORM_TOP_Y - MapConfig.PIT_RIM_DROP) > 7.2, arc.top)
	for _, b in blocks do table.insert(all, b) end
end
for _, box in Cfg.BLOCK_COLLIDERS do table.insert(all, Rules.block(box)) end

local function blocked(x, y)
	for _, b in all do
		if Rules.contains(b, x, y) then return true end
	end
	return false
end

-- 2) Tor-Gassen frei: Steg und Raketen-Steg samt Gelaender
local laneHalf = MapConfig.BRIDGE_WIDTH * 0.5 + MapConfig.BRIDGE_RAIL_WIDTH
local inLane = 0
for _, sy in { 1, -1 } do
	for y = 18, 40, 0.5 do
		for x = -laneHalf, laneHalf, 0.25 do
			if blocked(x, sy * y) then inLane += 1 end
		end
	end
end
check("Steg- und Raketen-Gasse frei (|quer| <= " .. laneHalf .. ")", inLane == 0, inLane)

-- 3) Flugfeld samt Leuchtring frei (WorldFXConfig.TOWER_FLIGHT, along = nach aussen)
local tf = WorldFXConfig.TOWER_FLIGHT
local ringR = tf.PAD_RADIUS * 1.3
local padHits = 0
for k = 0, 71 do
	local a = math.rad(k * 5)
	local x, y = math.abs(tf.PAD_ACROSS) + ringR * math.cos(a), -tf.PAD_ALONG + ringR * math.sin(a)
	if blocked(x, y) or blocked(-x, y) then padHits += 1 end
end
check("Flugfeld-Ring frei", padHits == 0, padHits)

-- 4) Kampfflaeche frei
local floorHits = 0
for k = 0, 359, 3 do
	local a = math.rad(k)
	local r = MapConfig.PIT_RADIUS + 0.5
	if blocked(r * math.cos(a), r * math.sin(a)) then floorHits += 1 end
end
check("Rand der Kampfflaeche (+0.5) frei", floorHits == 0, floorHits)

-- 5) Zaun der obersten Turm-Etage: lueckenlos, schneidet nicht in die Etage
local f = Cfg.TOWER_FENCE
local fenceArc = { inner = f.inner, outer = f.outer, bottom = 0, top = f.height, from = 0, to = 360, segments = f.segments }
local fence = Rules.arcBlocks(fenceArc, Cfg.COLLIDER_OVERLAP)
check("Turm-Zaun lueckenlos", holesIn(fenceArc, fence) == 0, holesIn(fenceArc, fence))
check("Turm-Zaun schneidet nicht in die Etage", innerFace(fence) >= MapConfig.PIT_TOWER_RADIUS - 0.05, innerFace(fence))
check("Turm-Zaun aufspringbar (gewollter Sprung)", f.height < 7.2, f.height)

-- 6) Teile-Budget der Kollision
local count = #all + f.segments
check("Kollisionsbloecke <= 50", count <= 50, count)

if failures > 0 then error("pit_v2: " .. failures .. " Fehler") end
print("pit_v2: alle Tests gruen")
