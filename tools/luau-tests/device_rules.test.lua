-- device_rules.test.lua — Welt 1, Paket 6b/6d (20.10.2026)
-- python tools/luau-tests/run_local.py tools/luau-tests/device_rules.test.lua
local D = require(RS.Modules.DeviceRules)
local G = require(RS.Config.GamepadConfig)

local failures = 0
local function check(name, ok)
	if ok then print("ok   " .. name) else failures += 1; print("FAIL " .. name) end
end
local function inp(t) -- Standardwerte: Desktop
	local base = { touch = false, keyboard = true, gamepad = false, lastInput = nil, viewportX = 1920, viewportY = 1080 }
	for k, v in t do base[k] = v end
	return base
end

check("Desktop", D.classify(inp({})) == "desktop")
check("Handy quer", D.classify(inp({ touch = true, keyboard = false, viewportX = 844, viewportY = 390 })) == "phone")
check("Handy hoch", D.classify(inp({ touch = true, keyboard = false, viewportX = 390, viewportY = 844 })) == "phone")
check("Tablet quer", D.classify(inp({ touch = true, keyboard = false, viewportX = 1180, viewportY = 820 })) == "tablet")
check("Tablet hoch", D.classify(inp({ touch = true, keyboard = false, viewportX = 820, viewportY = 1180 })) == "tablet")
check("Tablet mit Tastatur = Desktop", D.classify(inp({ touch = true, keyboard = true, viewportX = 1180, viewportY = 820 })) == "desktop")
check("Konsole: nur Gamepad", D.classify(inp({ keyboard = false, gamepad = true })) == "console")
check("PC mit Controller zuletzt benutzt", D.classify(inp({ gamepad = true, lastInput = "gamepad" })) == "console")
check("PC Controller da, Maus zuletzt = Desktop", D.classify(inp({ gamepad = true, lastInput = "mouse" })) == "desktop")
check("Handy mit Controller zuletzt = Konsole", D.classify(inp({ touch = true, keyboard = false, gamepad = true, lastInput = "gamepad", viewportX = 844, viewportY = 390 })) == "console")
check("Viewport 0 (Start) = Tablet statt Absturz", D.classify(inp({ touch = true, keyboard = false, viewportX = 0, viewportY = 0 })) == "tablet")

-- Masse laut Prompt 6b
local ph, co, de = D.metrics("phone"), D.metrics("console"), D.metrics("desktop")
check("Handy: >=48 Touch, >=64 Hauptknopf, >=14 pt", ph.minTouch >= 48 and ph.minMainTouch >= 64 and ph.minFontPx >= 14)
check("Konsole: >=64, >=24 px bei 1080, >=5 % Rand", co.minTouch >= 64 and co.minFontPx >= 24 and co.safeFraction >= 0.05)
check("Handy: Fenster <= 90 % Hoehe", ph.maxPanelHeight <= 0.9)
check("Desktop: keine Mindestmasse", de.minTouch == 0 and de.safeFraction == 0)
check("touchOk 47 px Handy faellt durch", not D.touchOk("phone", 47, 80, false))
check("touchOk 48 px Handy", D.touchOk("phone", 48, 48, false))
check("Hauptknopf 63 px faellt durch", not D.touchOk("phone", 63, 63, true))
check("Konsole 1080: 24 px", math.abs(D.minFontFor("console", 1080) - 24) < 1e-6)
check("Konsole 720: 16 px", math.abs(D.minFontFor("console", 720) - 16) < 1e-6)
check("Rand 5 % von 1080", math.abs(D.safeMargin("console", 1080) - 54) < 1e-6)

-- Belegung: keine Taste doppelt je Ebene, B schliesst, A nicht ueberschrieben
local function unique(list)
	local seen = {}
	for _, b in list do
		if seen[b.key] then return false, b.key end
		seen[b.key] = true
	end
	return true
end
check("WORLD: keine Taste doppelt", unique(G.WORLD))
check("PANEL: keine Taste doppelt", unique(G.PANEL))
local function has(list, key, action) for _, b in list do if b.key == key and b.action == action then return true end end return false end
check("B schliesst im Fenster", has(G.PANEL, "ButtonB", "close"))
check("L1/R1 sind Tabs im Fenster", has(G.PANEL, "ButtonL1", "tabPrev") and has(G.PANEL, "ButtonR1", "tabNext"))
check("L1/R1 sind Event/Fight in der Welt", has(G.WORLD, "ButtonL1", "event") and has(G.WORLD, "ButtonR1", "fight"))
check("A bleibt unbelegt (Roblox-Auswahl)", not has(G.WORLD, G.CONFIRM_KEY, "x") and G.CONFIRM_KEY == "ButtonA")
for _, list in { G.WORLD, G.PANEL } do
	for _, b in list do
		check("Taste " .. b.key .. " existiert in Roblox", b.key:match("^Button") ~= nil or b.key:match("^DPad") ~= nil)
	end
end
check("Prompt-Taste X", G.PROMPT_KEY == "ButtonX")

if failures > 0 then error(failures .. " Fehler") end
print("alle ok")
