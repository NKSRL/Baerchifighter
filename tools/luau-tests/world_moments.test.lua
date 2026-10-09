-- world_moments.test.lua — Paket G "Welt aufwerten": Welt-Momente
-- python tools/luau-tests/run_local.py tools/luau-tests/world_moments.test.lua
--
-- Prueft Modules/WorldMoments: erkennt Schluepfen ab Mythic, seltene
-- Mutationen, neuen Tower, Rekord und Rebirth aus zwei Spielstaenden;
-- je Spieler hoechstens ein grosser Moment pro 30 s; die Warteschlange zeigt
-- fuenf gleichzeitige Momente nacheinander und nie zwei grosse zugleich.

local WM  = rbxRequire("ReplicatedStorage/Modules/WorldMoments")
local CFG = rbxRequire("ReplicatedStorage/Config/WorldFXConfig").MOMENTS

local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else
		failures += 1
		print("FAIL " .. name .. (if detail then ": " .. tostring(detail) else ""))
	end
end

local function data(baerchis, highest, records, rebirths)
	return { island = { baerchis = baerchis }, towers = { highestTower = highest, records = records }, rebirthCount = rebirths }
end
local function kinds(list)
	local t = {}
	for _, m in list do t[m.kind] = m end
	return t
end

local base = data({ a = { rarity = "Rare" } }, "I", { I = 12 }, 0)
local s0 = WM.snapshot(base)

-- nichts passiert
check("gleicher Stand: kein Moment", #WM.diff(s0, WM.snapshot(base)) == 0)

-- Schluepfen
local k = kinds(WM.diff(s0, WM.snapshot(data({ a = { rarity = "Rare" }, b = { rarity = "Legendary" } }, "I", { I = 12 }, 0))))
check("Legendary ist kein Welt-Moment", k.hatch == nil)
k = kinds(WM.diff(s0, WM.snapshot(data({ a = { rarity = "Rare" }, b = { rarity = "Mythic" }, c = { rarity = "Cosmic" } }, "I", { I = 12 }, 0))))
check("Mythic + Cosmic: ein Moment mit der hoeheren Rarity", k.hatch ~= nil and k.hatch.value == "Cosmic", k.hatch and k.hatch.value)

-- Mutation
k = kinds(WM.diff(s0, WM.snapshot(data({ a = { rarity = "Rare", mutation = "Gold" } }, "I", { I = 12 }, 0))))
check("Gold ist keine seltene Mutation", k.mutation == nil)
k = kinds(WM.diff(s0, WM.snapshot(data({ a = { rarity = "Rare", mutation = "Galaxy" } }, "I", { I = 12 }, 0))))
check("Mutations-Sturm auf Galaxy", k.mutation ~= nil and k.mutation.value == "Galaxy")

-- Tower, Rekord, Rebirth
k = kinds(WM.diff(s0, WM.snapshot(data({ a = { rarity = "Rare" } }, "II", { I = 30 }, 0))))
check("neuer Tower", k.tower ~= nil and k.tower.value == "II")
check("Rekord gesteigert", k.record ~= nil and k.record.number == 30)
k = kinds(WM.diff(WM.snapshot(data({}, "I", {}, 0)), WM.snapshot(data({}, "I", { I = 3 }, 0))))
check("erster Lauf ist kein Rekord-Moment", k.record == nil)
k = kinds(WM.diff(s0, WM.snapshot(data({ a = { rarity = "Rare" } }, "I", { I = 12 }, 1))))
check("Rebirth", k.rebirth ~= nil and k.rebirth.number == 1)

-- Drosselung je Spieler
local big, last = WM.throttle(nil, 100)
check("erster Moment ist gross", big and last == 100)
big, last = WM.throttle(last, 100 + CFG.PLAYER_COOLDOWN - 1)
check("innerhalb 30 s: klein", not big and last == 100)
big, last = WM.throttle(last, 100 + CFG.PLAYER_COOLDOWN)
check("nach 30 s wieder gross", big)

-- Warteschlange: fuenf grosse gleichzeitig
local q = WM.newQueue()
local shownNow = 0
for i = 1, 5 do
	if WM.push(q, { id = i, kind = "hatch", big = true, at = 0 }) then shownNow += 1 end
end
check("Schlange voll: der fuenfte laeuft sofort klein", shownNow == 1 and #q.waiting == CFG.QUEUE_MAX, shownNow)
local order, t, overlap, lastEnd = {}, 0, false, -1
while #q.waiting > 0 and t < 60 do
	local e = WM.pop(q, t)
	if e then
		if e.big then
			if t < lastEnd then overlap = true end
			lastEnd = t + CFG.DURATION.hatch
		end
		table.insert(order, e.id)
	end
	t += 0.1
end
check("alle wartenden kommen dran, in Reihenfolge", #order == CFG.QUEUE_MAX and order[1] == 1 and order[4] == 4, table.concat(order, ","))
check("nie zwei grosse zugleich", not overlap)
check("kleiner Moment wartet nicht", WM.push(WM.newQueue(), { id = 9, kind = "record", big = false, at = 0 }))
-- zu lange gewartet: klein
local q2 = WM.newQueue()
WM.push(q2, { id = 1, kind = "hatch", big = true, at = 0 })
q2.busyUntil = 1000
local late = WM.pop(q2, CFG.MAX_WAIT + 1)
check("zu lange gewartet: kommt klein", late ~= nil and late.big == false)

if failures > 0 then error(failures .. " Fehler", 0) end
print("world_moments: alles gruen")
