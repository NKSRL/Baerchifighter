-- guide_arrow.test.lua — Tutorial-Pfeile aus Partikeln
-- Laeuft ohne Roblox: luau tools/luau-tests/guide_arrow.test.lua
local R = require("../../src/shared/Modules/GuideArrowRules")

local failures = 0
local function near(name, got, want)
	if math.abs(got - want) > 1e-9 then
		failures += 1
		print(string.format("FAIL %s: erwartet %s, bekommen %s", name, tostring(want), tostring(got)))
	else
		print("ok   " .. name)
	end
end
local function check(name, got, want)
	if got ~= want then
		failures += 1
		print(string.format("FAIL %s: erwartet %s, bekommen %s", name, tostring(want), tostring(got)))
	else
		print("ok   " .. name)
	end
end

-- Beispiel aus dem Wunsch: 28 Studs nach links
local m = R.motion(-28, 0)
near("28 links -> X = -2.8", m.accelX, -2.8)
near("28 links -> Z = 0", m.accelZ, 0)
near("28 links -> Drag = 2.8 / DRAG_DIVISOR", m.drag, 2.8 / R.DRAG_DIVISOR)
check("Y bleibt 0", m.accelY, 0)

local f = R.motion(0, -50)
near("50 vorwaerts -> Z = -5", f.accelZ, -5)
near("50 vorwaerts -> Drag = 5 / DRAG_DIVISOR", f.drag, 5 / R.DRAG_DIVISOR)

-- Endgeschwindigkeit = Beschleunigung / Drag = Speed, egal wie weit
local d = R.motion(30, -40)
near("Diagonale Distanz 50", d.distance, 50)
near("Endgeschwindigkeit = Speed", math.sqrt(d.accelX ^ 2 + d.accelZ ^ 2) / d.drag, R.SPEED)

near("Rate normal im Stand", R.rate(false, 0), R.SPEED / R.SPACING_HIGH)
near("Rate schwaches Geraet im Stand", R.rate(true, 0), R.SPEED / R.SPACING_LOW)
check("schwaches Geraet hat weniger Pfeile", R.rate(true, 0) < R.rate(false, 0), true)
-- Abstand der Pfeile bleibt gleich, ob der Spieler steht oder laeuft
for _, c in { 0, 4, 8, 12, 16 } do
	near("Abstand bei Laufen " .. c, (R.SPEED - c) / R.rate(false, c), R.SPACING_HIGH)
end
check("beim Laufen aufs Ziel weniger Rate", R.rate(false, 16) < R.rate(false, 0), true)
check("beim Weglaufen mehr Rate", R.rate(false, -16) > R.rate(false, 0), true)
check("Rate hat Obergrenze", R.rate(false, -1000) <= R.MAX_RATE, true)
check("Rate hat Untergrenze", R.rate(true, 1000) >= R.MIN_RATE, true)
check("ohne Laufwert wie Stand", R.rate(false), R.rate(false, 0))
check("nah -> unsichtbar", R.motion(2, 2).visible, false)
check("fern -> sichtbar", R.motion(28, 0).visible, true)
near("Lebensdauer = Abstand / Speed", R.motion(20, 0).lifetime, 20 / R.SPEED)
near("Lebensdauer Min", R.motion(7, 0).lifetime, R.MIN_LIFETIME)
check("Speed ueber Laufgeschwindigkeit (16)", R.SPEED > 16, true)
near("Lebensdauer Max", R.motion(500, 0).lifetime, R.MAX_LIFETIME)

if failures > 0 then error(failures .. " Fehler") end
print("guide_arrow: alles ok")
