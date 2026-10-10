-- map_layout.test.lua — HBB Paket 5/6: Wahrzeichen der Hauptinsel
-- python tools/luau-tests/run_local.py tools/luau-tests/map_layout.test.lua
--
-- Prueft die Positionen aus Modules/MapLayout (mit den aktuellen Flags):
-- 1. Jedes Wahrzeichen steht ganz auf der Hauptinsel und ausserhalb des
--    Event-Pits samt Ring.
-- 2. Keins ragt in einen Steg-Weg (Stegbreite + 1 Stud Luft).
-- 3. Keins beruehrt eine Laterne oder ein anderes Wahrzeichen.
-- 4. Das Wespen-Nest haengt frei am Mast: nicht im Mast, ueber den Wimpeln,
--    unter dem oberen Querholz.
-- Was hier nicht geprueft wird: Baeume/Buesche (die weichen den Wahrzeichen
-- in ScenicBuilder aus) und das Aussehen (Studio).

local MapLayout      = rbxRequire("ReplicatedStorage/Modules/MapLayout")
local MapConfig      = rbxRequire("ReplicatedStorage/Config/MapConfig")
local AmbienceConfig = rbxRequire("ReplicatedStorage/Config/AmbienceConfig")

local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else
		failures += 1
		print("FAIL " .. name .. (if detail then ": " .. tostring(detail) else ""))
	end
end

local landmarks = MapLayout.landmarks()
check("es gibt Wahrzeichen", #landmarks > 0, #landmarks)

local pitClear = MapConfig.EVENT_PIT_RADIUS + MapConfig.EVENT_PIT_RING_OVERHANG + 2
local laneHalf = MapConfig.BRIDGE_WIDTH * 0.5 + 1

for _, l in landmarks do
	local dist = math.sqrt(l.x ^ 2 + l.z ^ 2)

	-- 1. Insel und Event-Pit
	check(l.name .. " auf der Insel", dist + l.r <= MapConfig.PLATFORM_RADIUS - 1,
		string.format("%.1f + %.1f", dist, l.r))
	check(l.name .. " ausserhalb des Event-Pits", dist - l.r >= pitClear,
		string.format("%.1f - %.1f < %.1f", dist, l.r, pitClear))

	-- 2. Steg-Wege (von der Mitte nach aussen, je Slot)
	for slot = 1, MapConfig.PLOT_COUNT do
		local o = MapLayout.outward(slot)
		local along = l.x * o.X + l.z * o.Z
		local across = math.abs(l.x * o.Z - l.z * o.X)
		if along > 0 then
			check(string.format("%s frei von Steg %d", l.name, slot), across - l.r >= laneHalf,
				string.format("quer %.1f - %.1f < %.1f", across, l.r, laneHalf))
		end
	end

	-- 3a. Laternen
	for slot = 1, MapConfig.PLOT_COUNT do
		local o, s = MapLayout.outward(slot), MapLayout.side(slot)
		for _, radius in AmbienceConfig.LAMP_RADII do
			for _, sign in { -1, 1 } do
				local p = o * radius + s * (sign * AmbienceConfig.LAMP_SIDE)
				local d = math.sqrt((p.X - l.x) ^ 2 + (p.Z - l.z) ^ 2)
				if d - l.r < 1.5 then
					check(string.format("%s frei von Laterne %d/%d", l.name, slot, radius), false, string.format("%.1f", d))
				end
			end
		end
	end
end

-- 3b. untereinander
for i = 1, #landmarks do
	for j = i + 1, #landmarks do
		local a, b = landmarks[i], landmarks[j]
		local d = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
		if d < a.r + b.r + 1 then
			check(a.name .. " frei von " .. b.name, false, string.format("%.1f", d))
		end
	end
end

-- 4. Wespen-Nest am Mast (Masse aus MapConfig.CENTER_DECOR)
local function piece(name)
	for _, p in MapConfig.CENTER_DECOR do
		if p.name == name then return p end
	end
	error("CENTER_DECOR ohne " .. name)
end
local nest = MapConfig.WASP_NEST
local mastRadius = piece("Mast").size.Y * 0.5
local horizontal = math.sqrt(nest.offset.X ^ 2 + nest.offset.Z ^ 2)
check("Nest nicht im Mast", horizontal - nest.bodySize.X * 0.5 >= mastRadius - 0.3,
	string.format("%.2f", horizontal - nest.bodySize.X * 0.5))
check("Nest haengt am Mast (kein Schweben)", horizontal - nest.bodySize.X * 0.5 <= mastRadius + 0.3)
local wimpel = piece("Wimpel1")
check("Nest ueber den Wimpeln", nest.offset.Y - nest.bodySize.Y * 0.5 > wimpel.offset.Y + wimpel.size.Y * 0.5)
local quer = piece("QuerB1")
check("Nest unter dem oberen Querholz", nest.offset.Y + nest.bodySize.Y * 0.5 < quer.offset.Y - quer.size.Y * 0.5)

-- 5. Welt aufwerten (08.10.2026): Bojen, Wegweiser, Pit-Rahmen, Honigmast
local WorldFXConfig = rbxRequire("ReplicatedStorage/Config/WorldFXConfig")

-- 5a. Bojen liegen auf offenem Wasser, weit weg von jeder Insel
for i, b in MapLayout.buoys(WorldFXConfig.BUOYS.RADIUS) do
	check("Boje " .. i .. " auf offenem Wasser", MapLayout.isOpenWater(b.X, b.Z, 20))
end
-- offenes Wasser: Stichproben
check("Weltmitte ist kein Wasser", not MapLayout.isOpenWater(0, 0, 0))
local plot1 = MapLayout.plotCenter(1)
check("Plot-Insel ist kein Wasser", not MapLayout.isOpenWater(plot1.X, plot1.Z, 0))
local pit1 = MapLayout.pitCenter(1)
check("Arena-Insel ist kein Wasser", not MapLayout.isOpenWater(pit1.X, pit1.Z, 0))
local bridge = MapLayout.outward(1) * 290
check("aeusserer Steg ist kein Wasser", not MapLayout.isOpenWater(bridge.X, bridge.Z, 0))
local gap = MapLayout.atAngle(22.5, 200)
check("zwischen zwei Plot-Inseln ist Wasser", MapLayout.isOpenWater(gap.X, gap.Z, 5))
check("Arena-Mitte wie Schau-Turm-Formel (v15)",
	math.abs(MapLayout.pitRadius() - (MapConfig.PLOT_RING_RADIUS + MapConfig.PLOT_ISLAND_RADIUS + MapConfig.ISLAND_GAP + MapConfig.PIT_BASE_RADIUS)) < 1e-6)

-- 5b. Wegweiser: neben dem Pflaster (nicht darauf), auf der Wiese, frei von
-- Laternen und Wahrzeichen, ausserhalb des Pit-Rahmens
local sp = WorldFXConfig.SIGNPOST
local pf = WorldFXConfig.PIT_FRAME
for _, s in MapLayout.signposts(sp.RADIUS, sp.SIDE) do
	local p = s.position
	local o = MapLayout.outward(s.slot)
	local across = math.abs(p.X * o.Z - p.Z * o.X)
	local name = "Wegweiser " .. s.slot
	check(name .. " neben dem Pflaster", across - 0.5 > AmbienceConfig.PATH_WIDTH * 0.5, string.format("%.2f", across))
	-- die Schilder sind am Pfosten mittig, ein halbes Schild darf nicht ueber den Weg ragen
	check(name .. " Schilder ragen nicht ueber den Weg",
		across - sp.BOARD_SIZE.X * 0.5 > AmbienceConfig.PATH_WIDTH * 0.5, string.format("%.2f", across - sp.BOARD_SIZE.X * 0.5))
	local r = math.sqrt(p.X ^ 2 + p.Z ^ 2)
	check(name .. " ausserhalb von Pit + Rahmen", r - 3 > pf.POLE_RADIUS, string.format("%.1f", r))
	for slot = 1, MapConfig.PLOT_COUNT do
		local lo, ls = MapLayout.outward(slot), MapLayout.side(slot)
		for _, radius in AmbienceConfig.LAMP_RADII do
			for _, sign in { -1, 1 } do
				local q = lo * radius + ls * (sign * AmbienceConfig.LAMP_SIDE)
				local d = math.sqrt((p.X - q.X) ^ 2 + (p.Z - q.Z) ^ 2)
				if d < 4 then check(name .. " frei von Laterne", false, string.format("%.1f", d)) end
			end
		end
	end
	for _, l in landmarks do
		local d = math.sqrt((p.X - l.x) ^ 2 + (p.Z - l.z) ^ 2)
		if d < l.r + 3.5 then check(name .. " frei von " .. l.name, false, string.format("%.1f", d)) end
	end
end

-- 5c. Pit-Rahmen: Masten in den Zaunfeldern (nicht in einer Steg-Luecke),
-- ausserhalb von Podest und Ring, frei von Wahrzeichen
for k = 0, MapConfig.PLOT_COUNT - 1 do
	local angle = 22.5 + k * 45
	local p = MapLayout.atAngle(angle, pf.POLE_RADIUS)
	local gapDelta = 22.5   -- Abstand zur naechsten Steg-Achse in Grad
	check("Pit-Mast " .. k .. " nicht in Steg-Luecke", gapDelta > MapConfig.EVENT_PIT_FENCE_GAP_DEGREES + 3)
	check("Pit-Mast " .. k .. " ausserhalb des Rings",
		pf.POLE_RADIUS - 0.5 > MapConfig.EVENT_PIT_RADIUS + MapConfig.EVENT_PIT_RING_OVERHANG)
	for _, l in landmarks do
		local d = math.sqrt((p.X - l.x) ^ 2 + (p.Z - l.z) ^ 2)
		if d < l.r + 1.5 then check("Pit-Mast " .. k .. " frei von " .. l.name, false, string.format("%.1f", d)) end
	end
end

-- 5d. Honigmast: Schale neben dem Sockel, Faden frei von Querhoelzern und Nest
local mast = WorldFXConfig.MAST
local sockel = piece("Sockel")
check("Honig-Schale neben dem Sockel",
	mast.SPOUT_REACH - mast.BOWL_RADIUS > sockel.size.Y * 0.5, string.format("%.2f", mast.SPOUT_REACH - mast.BOWL_RADIUS))
check("Schale auf dem Podest", mast.SPOUT_REACH + mast.BOWL_RADIUS < MapConfig.EVENT_PIT_RADIUS - 2)
local function angleDelta(a, b)
	return math.abs(((a - b + 180) % 360) - 180)
end
for _, beam in { { "QuerA1", 0 }, { "QuerA2", 90 }, { "QuerB1", 315 }, { "QuerB2", 225 } } do
	local q = piece(beam[1])
	local nearest = math.min(angleDelta(mast.THREAD_ANGLE, beam[2]), angleDelta(mast.THREAD_ANGLE, beam[2] + 180))
	local dist = mast.THREAD_RADIUS * math.sin(math.rad(nearest))
	-- QuerA (y 12) liegt unter der Tuelle? Nein: Faden laeuft bis THREAD_BOTTOM.
	-- Beruehrt der Faden das Holz, laeuft der Honig darueber: erlaubt fuer die
	-- untere Lage (A), nicht fuer die schraegen B-Hoelzer (sieht wie Fehler aus).
	if string.sub(beam[1], 1, 5) == "QuerB" then
		check("Honigfaden frei von " .. beam[1], dist - mast.THREAD_WIDTH * 0.5 > q.size.Y * 0.5,
			string.format("%.2f", dist))
	end
end
check("Honigfaden auf der anderen Seite als das Nest",
	angleDelta(mast.THREAD_ANGLE, math.deg(math.atan2(nest.offset.Z, nest.offset.X))) > 90)
check("Wabenkrone ueber dem oberen Querholz",
	mast.CROWN_HEIGHT - mast.CROWN_ROW_GAP * 0.5 - mast.CELL_SIZE * 0.5 > quer.offset.Y + 1)

-- 6. Paket D: Insel-Stufen am Rand der Plot-Insel
local stageCfg = WorldFXConfig.ISLAND_STAGE
local beetHalf = MapConfig.PLOT_SIZE.X * 0.5 + 1   -- Beet + Zaun
for i, item in WorldFXConfig.ISLAND_STAGE_ITEMS do
	local name = string.format("Insel-Deko %d (%s)", i, item.kind)
	local a = math.rad(item.angle)
	local along, across = math.cos(a) * stageCfg.RIM_RADIUS, math.sin(a) * stageCfg.RIM_RADIUS
	local r = 2   -- grosszuegiger Radius jeder Art
	check(name .. " frei von den Steg-Achsen", math.abs(across) - r > MapConfig.BRIDGE_WIDTH * 0.5 + 2,
		string.format("quer %.1f", across))
	check(name .. " ausserhalb von Beet und Zaun", math.abs(along) - r > beetHalf or math.abs(across) - r > beetHalf,
		string.format("%.1f/%.1f", along, across))
	check(name .. " auf der Insel", stageCfg.RIM_RADIUS + r < MapConfig.PLOT_ISLAND_RADIUS)
	check(name .. " Art bekannt", WorldFXConfig.ISLAND_KINDS[item.kind] ~= nil)
	-- islandRimPoint liefert denselben Punkt fuer jeden Slot (Abstand zur Mitte)
	for slot = 1, MapConfig.PLOT_COUNT, 3 do
		local p = MapLayout.islandRimPoint(slot, item.angle, stageCfg.RIM_RADIUS)
		local c = MapLayout.plotCenter(slot)
		local d = math.sqrt((p.X - c.X) ^ 2 + (p.Z - c.Z) ^ 2)
		if math.abs(d - stageCfg.RIM_RADIUS) > 1e-6 then check(name .. " Abstand Slot " .. slot, false, d) end
	end
end
-- Winkel 0 zeigt zur Arena
local p0 = MapLayout.islandRimPoint(1, 0, 10)
check("Insel-Winkel 0 zeigt nach aussen", p0.X > MapLayout.plotCenter(1).X + 9.9)

if failures > 0 then error(failures .. " Fehler", 0) end
print("map_layout: alle Tests gruen (" .. #landmarks .. " Wahrzeichen)")
