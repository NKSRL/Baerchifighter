-- day_cycle.test.lua — Paket A "Welt aufwerten": Tageslauf
-- python tools/luau-tests/run_local.py tools/luau-tests/day_cycle.test.lua
--
-- Prueft Modules/DayCycle mit den Zahlen aus WorldFXConfig:
-- 1. Die Uhr bleibt in der Spanne und erreicht beide Enden.
-- 2. Keine Spruenge: zwei Zeitpunkte 0,2 s auseinander (ein Takt) liegen in
--    Uhrzeit und in jedem Licht-Wert nur ein winziges Stueck auseinander.
-- 3. Gleiche Serverzeit = gleiche Werte (zwei Clients sehen dasselbe).
-- 4. Bei 16,9 Uhr stehen die bisherigen festen Werte (AmbienceConfig/MapConfig):
--    der bekannte Look ist ein Punkt im Zyklus.
-- 5. Jede Kurve ist aufsteigend sortiert, beginnt bei 0 und endet bei 1.
-- 6. Lesbarkeit: in der blauen Stunde bleibt das Aussenlicht hell genug.

local DayCycle       = rbxRequire("ReplicatedStorage/Modules/DayCycle")
local WorldFXConfig  = rbxRequire("ReplicatedStorage/Config/WorldFXConfig")
local AmbienceConfig = rbxRequire("ReplicatedStorage/Config/AmbienceConfig")
local MapConfig      = rbxRequire("ReplicatedStorage/Config/MapConfig")

local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else
		failures += 1
		print("FAIL " .. name .. (if detail then ": " .. tostring(detail) else ""))
	end
end

local function diff(a, b)
	if type(a) == "number" then return math.abs(a - b) end
	return math.max(math.abs(a.R - b.R), math.abs(a.G - b.G), math.abs(a.B - b.B))
end

local cfg = WorldFXConfig.DAY

-- 1. Spanne
local lo, hi = math.huge, -math.huge
for t = 0, cfg.PERIOD * 2, 0.5 do
	local c = DayCycle.clockAt(1.7e9 + t)
	lo = math.min(lo, c); hi = math.max(hi, c)
end
check("Uhr nie unter CLOCK_MIN", lo >= cfg.CLOCK_MIN - 1e-6, lo)
check("Uhr nie ueber CLOCK_MAX", hi <= cfg.CLOCK_MAX + 1e-6, hi)
check("Uhr erreicht den Nachmittag", lo <= cfg.CLOCK_MIN + 0.01, lo)
check("Uhr erreicht die blaue Stunde", hi >= cfg.CLOCK_MAX - 0.01, hi)

-- 2. Keine Spruenge (ein Takt = cfg.TICK Sekunden)
local maxClockStep, maxValueStep, worst = 0, 0, ""
local prev = nil
local prevClock = nil
for t = 0, cfg.PERIOD, cfg.TICK do
	local now = 1.7e9 + t
	local clock = DayCycle.clockAt(now)
	local values = DayCycle.valuesAt(DayCycle.duskOf(clock))
	if prevClock then
		maxClockStep = math.max(maxClockStep, math.abs(clock - prevClock))
		for name, v in values do
			local step = diff(v, prev[name])
			-- relativ zur Spannweite der Kurve
			local curve = WorldFXConfig.DAY_CURVES[name]
			local span = 0
			for i = 2, #curve do span = math.max(span, diff(curve[i][2], curve[1][2])) end
			local rel = if span > 0 then step / span else 0
			if rel > maxValueStep then maxValueStep = rel; worst = name end
		end
	end
	prev, prevClock = values, clock
end
-- 4,5 Stunden Hin- und Rueckweg in 20 min: im Mittel 0,0015 h je 0,2 s
check("Uhr springt nie (max. Schritt je Takt)", maxClockStep < 0.005, string.format("%.5f h", maxClockStep))
check("Licht springt nie (max. 0,5 % der Spannweite je Takt)", maxValueStep < 0.005,
	string.format("%.4f bei %s", maxValueStep, worst))

-- 3. Gleiche Serverzeit, gleiche Werte
local a = DayCycle.valuesAt(DayCycle.duskOf(DayCycle.clockAt(1712345678.25)))
local b = DayCycle.valuesAt(DayCycle.duskOf(DayCycle.clockAt(1712345678.25)))
local same = true
for name, v in a do if diff(v, b[name]) ~= 0 then same = false end end
check("gleiche Serverzeit, gleiche Werte", same)

-- 4. Der bisherige feste Himmel (16,9 Uhr) liegt im Zyklus
local base = DayCycle.valuesAt(DayCycle.duskOf(AmbienceConfig.CLOCK_TIME))
local function near(name, value, expected)
	check("16,9 Uhr = bisher: " .. name, diff(value, expected) < 0.01,
		string.format("%s statt %s", tostring(type(value) == "number" and value or value.R), tostring(type(expected) == "number" and expected or expected.R)))
end
near("Brightness", base.brightness, AmbienceConfig.BRIGHTNESS)
near("Ambient", base.ambient, AmbienceConfig.AMBIENT)
near("OutdoorAmbient", base.outdoorAmbient, AmbienceConfig.OUTDOOR_AMBIENT)
near("ColorShift_Top", base.colorShiftTop, AmbienceConfig.COLOR_SHIFT_TOP)
near("Atmosphaere Dichte", base.atmDensity, AmbienceConfig.ATMOSPHERE_DENSITY)
near("Atmosphaere Offset", base.atmOffset, AmbienceConfig.ATMOSPHERE_OFFSET)
near("Atmosphaere Farbe", base.atmColor, AmbienceConfig.ATMOSPHERE_COLOR)
near("Atmosphaere Decay", base.atmDecay, AmbienceConfig.ATMOSPHERE_DECAY)
near("Atmosphaere Glare", base.atmGlare, AmbienceConfig.ATMOSPHERE_GLARE)
near("Atmosphaere Haze", base.atmHaze, AmbienceConfig.ATMOSPHERE_HAZE)
near("Bloom Intensitaet", base.bloomIntensity, MapConfig.LIGHTING_BLOOM_INTENSITY)
near("Bloom Schwelle", base.bloomThreshold, MapConfig.LIGHTING_BLOOM_THRESHOLD)
near("Bloom Groesse", base.bloomSize, MapConfig.LIGHTING_BLOOM_SIZE)
near("Saettigung", base.ccSaturation, MapConfig.LIGHTING_SATURATION)
near("Kontrast", base.ccContrast, MapConfig.LIGHTING_CONTRAST)
near("Wolkenfarbe", base.cloudColor, AmbienceConfig.CLOUD_COLOR)
near("Terrain-Wolken", base.terrainCloudColor, AmbienceConfig.CLOUDS_COLOR)

-- 5. Kurven wohlgeformt
for name, curve in WorldFXConfig.DAY_CURVES do
	local sorted = true
	for i = 2, #curve do if curve[i][1] < curve[i - 1][1] then sorted = false end end
	check("Kurve " .. name .. " sortiert, 0..1", sorted and curve[1][1] == 0 and curve[#curve][1] == 1)
end

-- 6. Lesbarkeit in der blauen Stunde: Aussenlicht nicht dunkler als 85 % des
-- Nachmittags (Summe der Kanaele), Helligkeit nicht unter 1,5.
local dusk = DayCycle.valuesAt(1)
local noon = DayCycle.valuesAt(0)
local function lum(c) return c.R + c.G + c.B end
check("blaue Stunde: Aussenlicht hell genug", lum(dusk.outdoorAmbient) >= 0.85 * lum(noon.outdoorAmbient),
	string.format("%.2f vs %.2f", lum(dusk.outdoorAmbient), lum(noon.outdoorAmbient)))
check("blaue Stunde: Brightness >= 1,5", dusk.brightness >= 1.5, dusk.brightness)

-- Mischung fuer den Rueckweg nach einer Show
local m = DayCycle.blend({ brightness = 1 }, { brightness = 3 }, 0.5)
check("blend mischt Zahlen", math.abs(m.brightness - 2) < 1e-9, m.brightness)

if failures > 0 then error(failures .. " Fehler", 0) end
print("day_cycle: alles gruen")
