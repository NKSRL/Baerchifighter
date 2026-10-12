-- sound_zones.test.lua — Paket H "Welt aufwerten": Klang-Zonen
-- python tools/luau-tests/run_local.py tools/luau-tests/sound_zones.test.lua
--
-- Prueft Modules/SoundZones: richtige Zone an typischen Orten, keine harten
-- Uebergaenge auf einem Rundgang (Mitte → Plot → Arena → Wasser), Grillen
-- statt Voegel in der blauen Stunde, nie mehr als MAX_AUDIBLE hoerbar.

local SZ        = rbxRequire("ReplicatedStorage/Modules/SoundZones")
local MapLayout = rbxRequire("ReplicatedStorage/Modules/MapLayout")
local CFG       = rbxRequire("ReplicatedStorage/Config/WorldFXConfig").SOUNDSCAPE

local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else
		failures += 1
		print("FAIL " .. name .. (if detail then ": " .. tostring(detail) else ""))
	end
end

local function top(w)
	local best, bw = nil, -1
	for k, v in w do if v > bw then best, bw = k, v end end
	return best
end

local mast = SZ.weights(Vector3.new(5, 3, 5), 0, false)
check("am Honigmast tropft es", mast.drip > 0.8, mast.drip)
check("am Honigmast kein Stimmengewirr ohne Event", mast.crowd == 0)
check("am Honigmast mit Event: Stimmengewirr", SZ.weights(Vector3.new(5, 3, 5), 0, true).crowd > 0.8)
local plot = MapLayout.plotCenter(2)
check("Mitte der Plot-Insel: Wiese", top(SZ.weights(plot + Vector3.new(0, 3, 0), 0, false)) == "meadow")
check("blaue Stunde: Grillen statt Voegel", top(SZ.weights(plot + Vector3.new(0, 3, 0), 1, false)) == "crickets")
local sea = MapLayout.atAngle(22.5, 500)
check("offenes Wasser: Wellen", top(SZ.weights(sea + Vector3.new(0, 3, 0), 0, false)) == "waves")
local pit = MapLayout.pitCenter(3)
check("Arena: Wind", SZ.weights(pit + Vector3.new(0, 3, 0), 0, false).wind > 0.5)
check("hoch ueber der Arena mehr Wind",
	SZ.weights(pit + Vector3.new(0, 140, 0), 0, false).wind > SZ.weights(pit + Vector3.new(0, 3, 0), 0, false).wind)

-- Rundgang in 1-Stud-Schritten: kein Gewicht springt mehr als 0,1
local path = { Vector3.new(0, 3, 0), plot + Vector3.new(0, 3, 0), MapLayout.pitCenter(2) + Vector3.new(0, 3, 0), MapLayout.atAngle(60, 600) + Vector3.new(0, 3, 0) }
local maxJump, where = 0, ""
for i = 1, #path - 1 do
	local a, b = path[i], path[i + 1]
	local steps = math.ceil((b - a).Magnitude)
	local prev = nil
	for s = 0, steps do
		local p = a + (b - a) * (s / steps)
		local w = SZ.weights(p, 0.5, true)
		if prev then
			for k, v in w do
				local j = math.abs(v - prev[k])
				if j > maxJump then maxJump, where = j, k end
			end
		end
		prev = w
	end
end
check("Rundgang ohne harte Uebergaenge (max. 0,1 je Stud)", maxJump <= 0.1, string.format("%.3f bei %s", maxJump, where))

-- hoechstens MAX_AUDIBLE gleichzeitig
local all = SZ.audible({ waves = 0.9, meadow = 0.8, crickets = 0.7, drip = 0.6, crowd = 0.5, wind = 0.4 })
local n = 0
for _, v in all do if v > 0 then n += 1 end end
check("hoechstens " .. CFG.MAX_AUDIBLE .. " hoerbar", n == CFG.MAX_AUDIBLE, n)
check("die lautesten bleiben", all.waves == 0.9 and all.drip == 0)

if failures > 0 then error(failures .. " Fehler", 0) end
print("sound_zones: alles gruen")
