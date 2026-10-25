-- rebirth_world2.test.lua — Welt 1, Paket 5a (20.10.2026)
-- python tools/luau-tests/run_local.py tools/luau-tests/rebirth_world2.test.lua
local R  = require(RS.Modules.RebirthRules)
local IR = require(RS.Modules.IncubatorRules)

local failures = 0
local function check(name, ok)
	if ok then print("ok   " .. name) else failures += 1; print("FAIL " .. name) end
end

check("Flag aus: immer erlaubt", R.allowedWith(false, { rebirthCount = 0 }))
check("Flag an, R0, kein Epilog: gesperrt", not R.allowedWith(true, { rebirthCount = 0, epilog = { state = "none" } }))
check("Flag an, pending: gesperrt", not R.allowedWith(true, { rebirthCount = 0, epilog = { state = "pending" } }))
check("Flag an, seen: gesperrt", not R.allowedWith(true, { rebirthCount = 0, epilog = { state = "seen" } }))
check("Flag an, launched: erlaubt", R.allowedWith(true, { rebirthCount = 0, epilog = { state = "launched" } }))
check("Bestandsschutz R1", R.allowedWith(true, { rebirthCount = 1 }))
check("view nil: gesperrt", not R.allowedWith(true, nil))

local rec = { I = 30, II = 44 }
check("Inkubator Flag aus: Rebirth-Regel", IR.gateWith(false, 2, 1, {}) == true and IR.gateWith(false, 2, 0, {}) == false)
local ok1, t1 = IR.gateWith(true, 2, 0, rec)
check("Inkubator Stufe 2 = Tower I geschafft", ok1 == true and t1 == "I")
local ok2, t2 = IR.gateWith(true, 3, 9, rec)
check("Inkubator Stufe 3 braucht Tower II voll (44<45)", ok2 == false and t2 == "II")
check("Inkubator ohne Records", IR.gateWith(true, 2, 5, nil) == false)
check("Inkubator Stufe 4 = III", select(2, IR.gateWith(true, 4, 0, { III = 60 })) == "III" and IR.gateWith(true, 4, 0, { III = 60 }))

if failures > 0 then error(failures .. " Fehler") end
print("alle ok")
