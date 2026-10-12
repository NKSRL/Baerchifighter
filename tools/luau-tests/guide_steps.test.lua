-- guide_steps.test.lua — HBB Paket 2
-- Laeuft ohne Roblox: luau tools/luau-tests/guide_steps.test.lua
-- (GuideSteps hat keine requires.)

local GuideSteps = require("../../src/shared/Modules/GuideSteps")

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
		rebirthCount = 0,
		gummies = 100,
		island = { baerchis = {}, eggStock = { BasicEgg = 3 }, laidEggs = {}, towerProgress = {} },
		towers = { records = {} },
		quests = { chainDone = 0 },
		stats = { totalEventsCompleted = 0 },
	}
end

local v = fresh()
check("frisch -> hatch", GuideSteps.current(v), "hatch")

v.island.baerchis = { a = {} }
v.island.eggStock.BasicEgg = 2
check("Baerchi da -> fight", GuideSteps.current(v), "fight")

v.island.towerProgress = { I = 3 }
-- Sammel-Update 3.5 (Studio-Stand): nach dem Kampf erst Waben, dann
-- verbessern, dann Event (Test 08.10. an die Kette angepasst)
check("gekaempft, keine Eier -> combs", GuideSteps.current(v), "combs")
v.stats.totalCombsDelivered = 1
check("Waben abgegeben -> upgrade", GuideSteps.current(v), "upgrade")
v.island.recycler = { level = 2 }
check("verbessert -> event", GuideSteps.current(v), "event")

v.island.laidEggs = { { uid = "e1" } }
check("gelegtes Ei -> collect", GuideSteps.current(v), "collect")

v.island.laidEggs = {}
v.stats.totalEventsCompleted = 1
check("Event geschafft -> fertig", GuideSteps.current(v), nil)

local vet = fresh()
vet.rebirthCount = 2
check("Rebirth -> kein Schritt", GuideSteps.current(vet), nil)

local vet2 = fresh()
vet2.quests.chainDone = 5
check("Kette >= 4 -> kein Schritt", GuideSteps.current(vet2), nil)

local broke = fresh()
broke.island.eggStock = {}
check("kein Ei, kein Haendler -> nil", GuideSteps.current(broke), nil)
check("kein Ei, Haendler bezahlbar -> merchant", GuideSteps.current(broke, { merchantPrice = 50 }), "merchant")
check("kein Ei, Haendler zu teuer -> nil", GuideSteps.current(broke, { merchantPrice = 500 }), nil)

-- Haendler-Schritt nach der Einfuehrung, wenn keine Eier mehr da sind
local late = fresh()
late.island.baerchis = { a = {} }
late.island.eggStock = {}
late.island.towerProgress = { I = 2 }
late.stats.totalEventsCompleted = 1
check("nach Einfuehrung, keine Eier -> merchant", GuideSteps.current(late, { merchantPrice = 50 }), "merchant")
check("nach Einfuehrung, Ei liegt -> nil", (function()
	late.island.laidEggs = { {} }
	return GuideSteps.current(late, { merchantPrice = 50 })
end)(), nil)

-- Rekord ohne towerProgress (Rebirth leert die Insel) zaehlt als gekaempft
local rec = fresh()
rec.island.baerchis = { a = {} }
rec.towers.records = { I = 4 }
rec.island.towerProgress = nil
check("Rekord zaehlt als Kampf", GuideSteps.current(rec), "combs")

-- Monotonie: eine wachsende Folge darf nie zu einem frueheren Schritt zurueck
-- "collect" ist ein Einschub zwischen Kampf und Event: gleicher Rang wie "event"
local order = { hatch = 1, merchant = 1, fight = 2, collect = 3, combs = 3, upgrade = 3, event = 3, tower = 4 }
local seq = fresh()
local last = 0
local states = {
	function(s) end,
	function(s) s.island.baerchis = { a = {} } end,
	function(s) s.island.towerProgress = { I = 1 } end,
	function(s) s.island.laidEggs = { {} } end,
	function(s) s.island.laidEggs = {} end,
	function(s) s.stats.totalEventsCompleted = 1 end,
}
local monotone = true
for _, apply in states do
	apply(seq)
	local step = GuideSteps.current(seq)
	local rank = if step then order[step] else 99
	if rank < last then monotone = false end
	last = rank
end
check("Monotonie", monotone, true)

-- 08.10.: Schritt "tower" (Terminal, Tower wechseln)
local tw = fresh()
tw.island.baerchis = { a = {} }
tw.island.towerProgress = { I = 30 }
tw.stats.totalEventsCompleted = 1
tw.towers = { records = { I = 12 }, selected = "I", unlocked = { I = true } }
check("Tower I nicht geschafft -> kein tower", GuideSteps.current(tw), nil)
tw.towers.records.I = 30
tw.towers.unlocked.II = true
check("Tower I geschafft -> tower", GuideSteps.current(tw), "tower")
tw.quests.chainDone = 9
check("tower auch nach >= 4 Ketten-Quests", GuideSteps.current(tw), "tower")
tw.towers.selected = "II"
check("gewechselt -> fertig", GuideSteps.current(tw), nil)
tw.towers.selected = "I"
tw.towers.records.II = 3
check("zurueck auf I, aber in II gekaempft -> fertig", GuideSteps.current(tw), nil)
local twv = fresh()
twv.rebirthCount = 1
twv.island.baerchis = { a = {} }
twv.towers = { records = { I = 30 }, selected = "I", unlocked = { I = true, II = true } }
check("Veteran mit Rebirth -> keine Fuehrung", GuideSteps.current(twv), nil)

if failures > 0 then
	error(failures .. " Test(s) fehlgeschlagen")
end
print("guide_steps: alle Tests gruen")
