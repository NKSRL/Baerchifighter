-- unlock_rules.test.lua — HBB Paket 3
-- Laeuft ohne Roblox: luau tools/luau-tests/unlock_rules.test.lua

local UnlockRules = require("../../src/shared/Modules/UnlockRules")

local failures = 0
local function check(name, got, want)
	if got ~= want then
		failures += 1
		print(string.format("FAIL %s: erwartet %s, bekommen %s", name, tostring(want), tostring(got)))
	else
		print("ok   " .. name)
	end
end

local function fresh()
	return {
		rebirthCount = 0, goldGummies = 0,
		island = { baerchis = {}, towerProgress = {} },
		towers = { records = {} },
		discovered = {},
		eggTree = { unlocked = { BasicEgg = true, SugarEgg = true } },
		stats = { totalHatched = 0, totalFightsWon = 0, totalFightsLost = 0 },
		uiSeen = {},
	}
end

local function visibleCount(v)
	local n = 0
	for _, on in UnlockRules.visible(v) do if on then n += 1 end end
	return n
end

-- frisch: genau 1 Pill, 2 Kacheln, Fight-Knopf
local v = fresh()
local vis = UnlockRules.visible(v)
check("frisch: 4 Elemente", visibleCount(v), 4)
check("frisch: Gummies", vis.pill_gummies, true)
check("frisch: kein Event", vis.button_event, false)
check("frisch: kein Gold", vis.pill_gold, false)

-- nach 10 Hatches
local h = fresh()
h.stats.totalHatched = 10
h.island.baerchis = { a = {}, b = {} }
h.discovered = { A = true, B = true, C = true }
vis = UnlockRules.visible(h)
check("hatch10: Baum", vis.tile_tree, true)
check("hatch10: Upgrade-Tab", vis.tab_upgrade, true)
check("hatch10: Index", vis.index, true)
check("hatch10: Event noch zu", vis.button_event, false)

-- nach Tower-Rekord
local t = fresh()
t.stats.totalHatched = 10
t.towers.records = { I = 30 }
vis = UnlockRules.visible(t)
check("tower: Event", vis.button_event, true)
check("tower: Bestenliste", vis.tile_leaderboard, true)
check("tower: Charms (I >= 15)", vis.charms, true)
check("tower: Rebirth-Pille noch zu", vis.pill_rebirth, false)

-- Veteran
local vet = fresh()
vet.rebirthCount = 5
vet.goldGummies = 300
vet.stats.totalHatched = 400
vet.towers.records = { I = 30, II = 45 }
vet.discovered = { A = true, B = true, C = true, D = true }
-- Sammel-Update 3.4: die zwei Waehrungs-Hinweise sind reine Gesehen-Marken
-- (nie von selbst sichtbar), deshalb -3 statt -1.
check("Veteran: alles ausser Shop und Hinweisen", visibleCount(vet), #UnlockRules.ELEMENTS - 3)
check("Veteran hat Fortschritt", UnlockRules.hasProgress(vet), true)
check("Frisch ohne Fortschritt", UnlockRules.hasProgress(fresh()), false)

-- Latch: Gold ausgegeben, Pille bleibt
local g = fresh()
g.goldGummies = 5
check("Gold > 0", UnlockRules.isVisible(g, "pill_gold"), true)
g.goldGummies = 0
g.uiSeen.pill_gold = true
check("Gold 0, aber gesehen", UnlockRules.isVisible(g, "pill_gold"), true)

-- Monotonie: zufaellig wachsende Daten sperren nie wieder etwas
math.randomseed(42)
local monotone = true
for run = 1, 200 do
	local s = fresh()
	local before = UnlockRules.visible(s)
	for _ = 1, 30 do
		local r = math.random(1, 6)
		if r == 1 then s.stats.totalHatched += math.random(0, 3)
		elseif r == 2 then s.towers.records.I = math.max(s.towers.records.I or 0, math.random(0, 30))
		elseif r == 3 then s.rebirthCount += (if math.random() < 0.1 then 1 else 0)
		elseif r == 4 then s.discovered["K" .. math.random(1, 10)] = true
		elseif r == 5 then s.stats.totalFightsLost += 1
		else
			-- nicht monotone Quelle: Gold rauf und runter, mit Latch beim Sehen
			s.goldGummies = math.random(0, 2)
			if s.goldGummies > 0 then s.uiSeen.pill_gold = true end
		end
		local now = UnlockRules.visible(s)
		for id, was in before do
			if was and not now[id] then monotone = false end
		end
		before = now
	end
end
check("Monotonie (200 zufaellige Folgen)", monotone, true)

if failures > 0 then error(failures .. " Test(s) fehlgeschlagen") end
print("unlock_rules: alle Tests gruen")
