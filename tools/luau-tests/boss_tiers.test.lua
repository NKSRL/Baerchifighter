-- boss_tiers.test.lua — HBB Paket 7
-- Laeuft ohne Roblox: luau tools/luau-tests/boss_tiers.test.lua

local BossTiers = require("../../src/shared/Modules/BossTiers")

local failures = 0
local function check(name, got, want)
	if got ~= want then
		failures += 1
		print(string.format("FAIL %s: erwartet %s, bekommen %s", name, tostring(want), tostring(got)))
	else
		print("ok   " .. name)
	end
end

check("Schaden 0 -> 0", BossTiers.tierFor(0, 1000, true, false), 0)
check("Schaden 0 + Sieg -> 0", BossTiers.tierFor(0, 1000, true, true), 0)
check("Schaden 1 -> 1", BossTiers.tierFor(1, 1000, true, false), 1)
check("5 % -> 2", BossTiers.tierFor(50, 1000, true, false), 2)
check("25 % -> 3", BossTiers.tierFor(250, 1000, true, false), 3)
check("60 % -> 4", BossTiers.tierFor(600, 1000, true, false), 4)

-- AFK nie ueber 1, auch nicht mit Sieg und vollem Schaden
local afkMax = 0
for _, dmg in { 1, 10, 100, 500, 1000, 5000 } do
	for _, won in { false, true } do
		afkMax = math.max(afkMax, BossTiers.tierFor(dmg, 1000, false, won))
	end
end
check("AFK hoechstens 1", afkMax, 1)

-- Sieg hebt um genau 1 und deckelt bei 4
check("Sieg 1 -> 2", BossTiers.tierFor(1, 1000, true, true), 2)
check("Sieg 2 -> 3", BossTiers.tierFor(50, 1000, true, true), 3)
check("Sieg 3 -> 4", BossTiers.tierFor(250, 1000, true, true), 4)
check("Sieg 4 bleibt 4", BossTiers.tierFor(900, 1000, true, true), 4)

-- Monoton mit dem Schaden
local monotone = true
for _, won in { false, true } do
	for _, active in { false, true } do
		local last = -1
		for dmg = 0, 1500, 7 do
			local tier = BossTiers.tierFor(dmg, 1000, active, won)
			if tier < last then monotone = false end
			last = tier
		end
	end
end
check("monoton mit dem Schaden", monotone, true)

-- Ohne Potenzial (Messung fehlt): jeder Treffer zaehlt als voll
check("Potenzial 0 -> Stufe 4", BossTiers.tierFor(5, 0, true, false), 4)

if failures > 0 then error(failures .. " Test(s) fehlgeschlagen") end
print("boss_tiers: alle Tests gruen")
