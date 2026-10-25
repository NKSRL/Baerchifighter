-- badge_rules.test.lua — Welt 1, Paket 3 (20.10.2026)
-- python tools/luau-tests/run_local.py tools/luau-tests/badge_rules.test.lua

local Rules = require(RS.Modules.BadgeRules)
local Cfg   = require(RS.Config.BadgeConfig)

local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else
		failures += 1
		print("FAIL " .. name .. (detail ~= nil and (" -> " .. tostring(detail)) or ""))
	end
end

-- Neuling
local n = Rules.info({ records = {} }, 0)
check("kein Rekord -> Neuling", n.towerId == "" and n.record == 0)
local k, a = Rules.plaque(n)
check("Neuling-Schluessel", k == Cfg.TEXT.rookie and a == nil)
check("R0 wird nie gezeigt", Rules.showRebirth(n) == false)
check("towers = nil -> Neuling", Rules.info(nil, nil).towerId == "")

-- Tower I/II/III
local t2 = Rules.info({ records = { I = 30, II = 37 } }, 5)
check("hoechster Tower zaehlt", t2.towerId == "II" and t2.record == 37 and t2.rebirth == 5)
local k2, a2 = Rules.plaque(t2)
check("Tower II -> ui.badge.tower mit Ziffer II und Stage 37", k2 == Cfg.TEXT.tower and a2 and a2.tower == "II" and a2.stage == 37)
check("R5 wird gezeigt", Rules.showRebirth(t2))

-- Final / Endless
local f = Rules.info({ records = { Final = 100 } }, 0)
local kf, af = Rules.plaque(f)
check("Final -> ui.badge.final", kf == Cfg.TEXT.final and af and af.stage == 100)
local e = Rules.info({ records = { Endless = 40 } }, 0)
local ke = Rules.plaque(e)
check("Endless -> ui.badge.endless", ke == Cfg.TEXT.endless)

-- Attribute vom Client
local at = Rules.fromAttributes("III", 12.7, 3)
check("Attribute: gueltig", at.towerId == "III" and at.record == 12 and at.rebirth == 3)
check("Attribute: unbekannter Tower -> Neuling", Rules.fromAttributes("X", 5, 1).towerId == "")
check("Attribute: Rekord 0 -> Neuling", Rules.fromAttributes("I", 0, 1).towerId == "")
check("Attribute: Muell -> Neuling R0", (function() local m = Rules.fromAttributes(nil, "a", {}) return m.towerId == "" and m.rebirth == 0 and m.record == 0 end)())
check("Attribute: negative Rebirth -> 0", Rules.fromAttributes("I", 3, -4).rebirth == 0)

-- Ausblenden
check("Alpha voll bis FADE_START", Rules.alphaAt(Cfg.FADE_START) == 1 and Rules.alphaAt(5) == 1)
check("Alpha 0 ab MAX_DISTANCE", Rules.alphaAt(Cfg.MAX_DISTANCE) == 0 and Rules.alphaAt(500) == 0)
local mid = Rules.alphaAt((Cfg.FADE_START + Cfg.MAX_DISTANCE) / 2)
check("Alpha in der Mitte 0,5", math.abs(mid - 0.5) < 1e-9, mid)

-- Hoechstens 8 sichtbar, die naechsten
local d = {}
for i = 1, 12 do d["p" .. i] = i * 5 end   -- 5..60
d.far = 200
local vis = Rules.pickVisible(d, Cfg.MAX_VISIBLE)
local count = 0
for _ in vis do count += 1 end
check("hoechstens 8 sichtbar", count == 8, count)
check("naechste zuerst", vis.p1 and vis.p8 and not vis.p9)
check("zu weit weg nie sichtbar", not vis.far)

if failures > 0 then error("badge_rules: " .. failures .. " Fehler") end
print("badge_rules: alle Tests gruen")
