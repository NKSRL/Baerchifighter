-- island_stage.test.lua — Paket D "Welt aufwerten": Stufe der Insel-Deko
-- python tools/luau-tests/run_local.py tools/luau-tests/island_stage.test.lua
--
-- Prueft Modules/IslandStage: Start = 1, steigt mit geschafften Towern ODER
-- Rebirths, nie ueber 4, ein Tower zaehlt nur ganz geschafft, Luecken
-- (II geschafft ohne I) zaehlen nicht, Endless zaehlt nicht mit.

local IslandStage = rbxRequire("ReplicatedStorage/Modules/IslandStage")

local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else
		failures += 1
		print("FAIL " .. name .. (if detail then ": " .. tostring(detail) else ""))
	end
end
local function eq(name, got, want) check(name, got == want, string.format("%s statt %s", tostring(got), tostring(want))) end

eq("neues Konto", IslandStage.compute(nil, 0), 1)
eq("Tower I halb", IslandStage.compute({ I = 15 }, 0), 1)
eq("Tower I geschafft", IslandStage.compute({ I = 30 }, 0), 2)
eq("Tower II geschafft", IslandStage.compute({ I = 30, II = 45 }, 0), 3)
eq("Tower III geschafft", IslandStage.compute({ I = 30, II = 45, III = 60 }, 0), 4)
eq("Final geschafft bleibt 4", IslandStage.compute({ I = 30, II = 45, III = 60, Final = 100, Endless = 300 }, 20), 4)
eq("Luecke zaehlt nicht (II ohne I)", IslandStage.towersCleared({ II = 45 }), 0)
eq("1 Rebirth", IslandStage.compute(nil, 1), 2)
eq("3 Rebirths", IslandStage.compute({ I = 30 }, 3), 3)
eq("5 Rebirths", IslandStage.compute(nil, 5), 4)
eq("Rebirth und Tower: das Weitere zaehlt", IslandStage.compute({ I = 30, II = 45 }, 1), 3)
local monotone = true
local last = 0
for r = 0, 30 do
	local st = IslandStage.compute(nil, r)
	if st < last or st > IslandStage.MAX then monotone = false end
	last = st
end
check("steigt nur und bleibt <= MAX", monotone)

if failures > 0 then error(failures .. " Fehler", 0) end
print("island_stage: alles gruen")
