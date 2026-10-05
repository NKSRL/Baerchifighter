-- rebirth_rules.test.lua — Sammel-Update 05.10., Paket 4.1
-- python tools/luau-tests/run_local.py tools/luau-tests/rebirth_rules.test.lua
--
-- 1. Erster Rebirth: Tower I Stage 30, und der Deckel von R0 reicht bis dorthin.
-- 2. Die Bedingung liegt fuer JEDEN Rebirth in einem offenen Tower (sonst ist
--    sie nie erreichbar) und steigt nie (Aequivalenz), bis Final 100 echt.
-- 3. isRebirthReady: zaehlt nur dieses Leben (stageBest), ueber die
--    Aequivalenz auch in hoeheren Towern; Rekorde allein reichen nicht.
-- 4. Kein Gummy-Preis mehr: RebirthService fragt getRebirthCost nicht ab
--    (Quelltext-Pruefung).

local TowerConfig  = rbxRequire("ReplicatedStorage/Config/TowerConfig")
local FeatureFlags = rbxRequire("ReplicatedStorage/Config/FeatureFlags")

local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else
		failures += 1
		print("FAIL " .. name .. (if detail then ": " .. tostring(detail) else ""))
	end
end

-- 1.
local t0, s0 = TowerConfig.getRebirthRequirement(0)
check("erster Rebirth: Tower I Stage 30", t0 == "I" and s0 == 30, t0 .. "/" .. s0)
check("Deckel R0 >= Bedingung R0", TowerConfig.getStageCap(0, "I") >= 30)

-- 2.
local endlessRecords = { Final = 100 }
local lastEq = 0
for n = 0, 40 do
	local records = if n >= TowerConfig.REBIRTH_AFTER_FINAL.fromRebirth then endlessRecords else nil
	local towerId, stage = TowerConfig.getRebirthRequirement(n, records)
	local cap = TowerConfig.getStageCap(n, towerId, records)
	check(string.format("R%d: Bedingung %s/%d liegt in offenem Tower", n, towerId, stage), cap > 0, cap)
	local eq = TowerConfig.getEquivalent(towerId, stage)
	check(string.format("R%d: Bedingung faellt nicht (%.1f >= %.1f)", n, eq, lastEq), eq >= lastEq - 1e-6)
	if n >= 1 and n <= 14 and n ~= 6 then
		-- bis Final 100 steigt sie (R6 ist der Sprung in den Final-Tower)
		check(string.format("R%d: Bedingung steigt", n), eq > lastEq)
	end
	lastEq = eq
end

-- 3.
check("R0: I/29 reicht nicht", not TowerConfig.isRebirthReady(0, { I = 29 }))
check("R0: I/30 reicht", TowerConfig.isRebirthReady(0, { I = 30 }))
check("R0: leeres Leben reicht nicht", not TowerConfig.isRebirthReady(0, {}))
check("R0: ohne stageBest nie", not TowerConfig.isRebirthReady(0, nil))
local t1, s1 = TowerConfig.getRebirthRequirement(1)
check("R1: I/30 reicht nicht mehr", not TowerConfig.isRebirthReady(1, { I = 30 }))
check("R1: Bedingung selbst reicht", TowerConfig.isRebirthReady(1, { [t1] = s1 }))
-- gleich starke Stage in hoeherem Tower zaehlt
local t4, s4 = TowerConfig.getRebirthRequirement(4)
check("R4: Final 1 zaehlt ueber Aequivalenz nicht, wenn schwaecher",
	TowerConfig.isRebirthReady(4, { Final = 1 }) == (TowerConfig.getEquivalent("Final", 1) >= TowerConfig.getEquivalent(t4, s4)))
if FeatureFlags.isOn("ENDLESS") then
	local tE, sE = TowerConfig.getRebirthRequirement(TowerConfig.REBIRTH_AFTER_FINAL.fromRebirth, endlessRecords)
	check("nach Final 100: Bedingung im Endless-Tower", tE == "Endless" and sE > 0, tE .. "/" .. sE)
end

-- 4.
local f = io and io.open and io.open("src/server/Services/RebirthService.luau", "r")
if f then
	local text = f:read("*a")
	f:close()
	check("RebirthService ruft getRebirthCost nicht mehr", not string.find(text, "getRebirthCost", 1, true))
	check("RebirthService prueft isRebirthReady", string.find(text, "isRebirthReady", 1, true) ~= nil)
else
	print("info io nicht verfuegbar, Quelltext-Pruefung uebersprungen")
end

if failures > 0 then
	error(failures .. " Pruefung(en) fehlgeschlagen")
end
print("ALLE OK")
