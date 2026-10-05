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

if failures > 0 then error(failures .. " Fehler", 0) end
print("map_layout: alle Tests gruen (" .. #landmarks .. " Wahrzeichen)")
