-- epilog_summit.test.lua — 20.10. Final-Epilog, Prompt 2 (Gipfel)
-- python tools/luau-tests/run_local.py tools/luau-tests/epilog_summit.test.lua
--
-- Prueft die Gipfel-Geometrie (Modules/EpilogSummitLayout, reine Rechnung):
--   1. Teile-Budget: hoechstens 24 (Gipfel), Rig/Fangboden/Gelaender unsichtbar
--   2. Boden: nichts steckt unter der Etage, nichts schwebt (jedes erhoehte
--      Teil sitzt auf einem anderen) — wie check_decor.py fuer die Config
--   3. Reichweite: nichts weiter als Etagenradius + extraRing
--   4. Gelaender: umschliesst den Rand rundum, laesst die Bruecke frei
--      (Luecke schmaler als die Bruecke, so dass niemand seitlich abstuerzt)
--   5. Spawn/Kamera-Anker, Fangboden, Haltehoehe des Turms
-- fuer mehrere Brueckenrichtungen (jede Plot-Lage ist anders gedreht).

local EpilogConfig = require(RS.Config.EpilogConfig)
local MapConfig    = require(RS.Config.MapConfig)
local TowerConfig  = require(RS.Config.TowerConfig)
local Layout       = require(RS.Modules.EpilogSummitLayout)

local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else
		failures += 1
		print("FAIL " .. name .. (if detail ~= nil then ": " .. tostring(detail) else ""))
	end
end

local C = EpilogConfig.SUMMIT
local R = MapConfig.PIT_TOWER_RADIUS
local EPS = 0.05
local FLOOR_Y = 72
local CX, CZ = 1000, -500

local function top(p) return p.pos[2] + (if p.kind == "Disc" then p.size[1] else p.size[2]) / 2 end
local function bottom(p) return p.pos[2] - (if p.kind == "Disc" then p.size[1] else p.size[2]) / 2 end

-- Liegt (x, z) im Grundriss des Teils? (Scheibe: Kreis, Block: gedrehtes Rechteck)
local function inFootprint(p, x, z, grow)
	grow = grow or 0
	local dx, dz = x - p.pos[1], z - p.pos[3]
	if p.kind == "Disc" then
		return math.sqrt(dx * dx + dz * dz) <= p.size[2] / 2 + grow
	end
	local tx, tz = math.cos(p.yaw), -math.sin(p.yaw)     -- lokale X-Achse in der Welt
	local along = dx * tx + dz * tz
	local across = dx * -tz + dz * tx
	return math.abs(along) <= p.size[1] / 2 + grow and math.abs(across) <= p.size[3] / 2 + grow
end

local function runFor(angleDeg)
	local label = string.format("[%d°] ", angleDeg)
	local a = math.rad(angleDeg)
	local r = Layout.compute(CX, CZ, FLOOR_Y, R, a)
	local bx, bz = math.cos(a), math.sin(a)

	-- 1. Budget
	check(label .. "Teile <= 24", r.totalCount <= 24, r.totalCount)
	local hiddenNames, hiddenCount = {}, 0
	for _, p in r.pieces do
		if p.hidden then
			local base = string.gsub(p.name, "_%d+$", "")
			if not hiddenNames[base] then hiddenNames[base] = true hiddenCount += 1 end
		end
	end
	check(label .. "unsichtbar: nur Rig, Gelaender, Fangboden",
		hiddenNames.Rig and hiddenNames.Gelaender and hiddenNames.Fangboden and hiddenCount == 3, hiddenCount)

	-- 2. Boden
	local belowFloor, floating = {}, {}
	for _, p in r.pieces do
		if not p.hidden then
			if bottom(p) < FLOOR_Y - EPS then table.insert(belowFloor, p.name) end
			if bottom(p) > FLOOR_Y + EPS then
				local supported = false
				for _, q in r.pieces do
					if q ~= p and not q.hidden and math.abs(top(q) - bottom(p)) <= EPS
						and inFootprint(q, p.pos[1], p.pos[3]) then supported = true end
				end
				if not supported then table.insert(floating, p.name) end
			end
		end
	end
	check(label .. "nichts steckt unter der Etage", #belowFloor == 0, table.concat(belowFloor, ","))
	check(label .. "nichts schwebt", #floating == 0, table.concat(floating, ","))

	-- 3. Reichweite (sichtbare Teile)
	local farthest = 0
	for _, p in r.pieces do
		if not p.hidden then
			local dx, dz = p.pos[1] - CX, p.pos[3] - CZ
			local reach
			if p.kind == "Disc" then
				reach = math.sqrt(dx * dx + dz * dz) + p.size[2] / 2
			else
				reach = math.sqrt(dx * dx + dz * dz) + p.size[1] / 2
			end
			farthest = math.max(farthest, reach)
		end
	end
	check(label .. "Reichweite <= Radius + extraRing", farthest <= R + C.extraRing + 0.2, farthest)

	-- 4. Gelaender
	local rails = {}
	for _, p in r.pieces do
		if p.name:find("^Gelaender") then table.insert(rails, p) end
	end
	check(label .. "Gelaender-Anzahl", #rails == C.railSides, #rails)
	local allCollide = true
	for _, p in rails do if not p.collide then allCollide = false end end
	check(label .. "Gelaender kollidiert", allCollide)

	local function inRail(x, z)
		for _, p in rails do
			if inFootprint(p, x, z) then return true end
		end
		return false
	end
	-- jeder Randpunkt ausserhalb des Brueckenstreifens trifft radial nach aussen ein Gelaender
	local openLeaks, checked = {}, 0
	for deg = 0, 359 do
		local th = math.rad(deg)
		local dxr, dzr = math.cos(th), math.sin(th)
		local delta = math.acos(math.clamp(dxr * bx + dzr * bz, -1, 1))
		local lateral = (R + 0.3) * math.sin(delta)
		local inCorridor = delta < math.pi / 2 and lateral <= C.bridgeWidth / 2 + 0.3
		if not inCorridor then
			checked += 1
			local hit = false
			local t = R + 0.3
			while t <= R + 8 do
				if inRail(CX + dxr * t, CZ + dzr * t) then hit = true break end
				t += 0.1
			end
			if not hit then table.insert(openLeaks, deg) end
		end
	end
	check(label .. "Rand ringsum geschlossen (ausser Brueckenstreifen)", #openLeaks == 0,
		#openLeaks .. " offen, z. B. " .. tostring(openLeaks[1]))

	-- Bruecke bleibt frei: auf der Achse und im Laufstreifen kein Gelaender. Die
	-- gekuerzten Wandenden (Wanddicke!) streifen den aeussersten halben Stud der
	-- Platten; frei sind +-(Luecke/2 - Wanddicke) = 3,5 Studs.
	local blocked = false
	local freeHalf = 2 * C.railOpenEnd * math.sin(math.pi / 3) / 2 - C.railThick
	for along = R - 1, R + C.extraRing, 0.25 do
		for _, lat in { -freeHalf, 0, freeHalf } do
			local x = CX + bx * along + (-bz) * lat
			local z = CZ + bz * along + bx * lat
			if inRail(x, z) then blocked = true end
		end
	end
	check(label .. "Bruecke frei vom Gelaender", not blocked)

	-- Luecke zwischen den zwei gekuerzten Enden schmaler als die Bruecke
	local gap = 2 * C.railOpenEnd * math.sin(math.pi / 3)
	check(label .. "Luecke schmaler als die Bruecke", gap < C.bridgeWidth, gap)

	-- 5. Anker, Spawn, Fangboden
	local names = {}
	for _, an in r.anchors do names[an.name] = an end
	check(label .. "Anker Spawn/Cam_Start/Cam_Orbit/Cam_Bridge",
		names.Spawn and names.Cam_Start and names.Cam_Orbit and names.Cam_Bridge)
	check(label .. "Spawn in der Mitte", math.abs(r.spawn[1] - CX) < 1e-6 and math.abs(r.spawn[3] - CZ) < 1e-6)
	check(label .. "Spawn ueber der Platte", math.abs(r.spawn[2] - (r.plateTop + C.spawnLift)) < 1e-6)
	local catchFloor
	for _, p in r.pieces do if p.name == "Fangboden" then catchFloor = p end end
	check(label .. "Fangboden unter der Etage, breiter als der Rand",
		catchFloor ~= nil and top(catchFloor) < FLOOR_Y and catchFloor.size[2] / 2 > R + C.rimWidth)
	check(label .. "Kristalle ohne Kollision",
		(function() for _, p in r.pieces do if p.name:find("^Kristall") and p.collide then return false end end return true end)())
	return r
end

for _, deg in { 0, 37, 90, 135, 222, 300 } do
	runFor(deg)
end

-- 5b. Haltehoehe = oberste Etage des Final-Laufs
local def = TowerConfig.get(EpilogConfig.TOWER_ID)
check("Haltehoehe = RUN_MAX_FLOORS", TowerConfig.getRunFloor(EpilogConfig.TOWER_ID, def.stages) == TowerConfig.RUN_MAX_FLOORS,
	TowerConfig.getRunFloor(EpilogConfig.TOWER_ID, def.stages))
check("Look des Final-Towers hat eine Akzentfarbe", MapConfig.TOWER_LOOKS[def.look] ~= nil and MapConfig.TOWER_LOOKS[def.look].accent ~= nil)
check("Aufbau dauert 1,5 s", math.abs(C.holdSeconds + C.decorSeconds + C.readySeconds - 1.5) < 1e-9)
check("Abfahrt = FALL x 3", C.lowerFactor == 3 and math.abs(MapConfig.PIT_TOWER_FALL_SECONDS * C.lowerFactor - 2.4) < 1e-9,
	MapConfig.PIT_TOWER_FALL_SECONDS * C.lowerFactor)

if failures > 0 then error(failures .. " Test(s) fehlgeschlagen") end
print("epilog_summit: alle Tests gruen")
