-- recycler.test.lua — 12.10. Recycler als Geld-Multiplikator, Sofort-Auszahlung
-- python tools/luau-tests/run_local.py tools/luau-tests/recycler.test.lua
--
-- 1. Level 1 = x1, Auszahlung je Einheit = Grundwert x Multiplikator.
-- 2. Multiplikator und Auszahlung steigen mit jedem Level (nie gleich/fallend).
-- 3. Staerker als vorher: auf jedem Level mindestens 3x der alte Ertrag.
-- 4. Schild-Text: "×1", "×1,7", "×80", "×23K" (sprachneutral, kurz).

local CombConfig = require(RS.Config.CombConfig)

local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else
		failures += 1
		print("FAIL " .. name .. (if detail ~= nil then ": " .. tostring(detail) else ""))
	end
end

check("Level 1 = x1", CombConfig.getMultiplier(1) == 1, CombConfig.getMultiplier(1))
check("Level 1 = Grundwert", CombConfig.getPayPerUnit(1) == CombConfig.BASE_PAY_PER_UNIT, CombConfig.getPayPerUnit(1))

local function oldPay(level)
	local fixed = CombConfig.PAY_PER_UNIT[level]
	if fixed then return fixed end
	return math.floor(CombConfig.PAY_PER_UNIT[10] * CombConfig.PAY_GROWTH ^ (level - 10) + 0.5)
end

local prevMult, prevPay = 0, 0
for level = 1, CombConfig.RECYCLER_MAX_LEVEL do
	local m, pay = CombConfig.getMultiplier(level), CombConfig.getPayPerUnit(level)
	if m <= prevMult or pay <= prevPay then
		check("steigt auf Level " .. level, false, string.format("x%s / %d", tostring(m), pay))
	end
	if pay < oldPay(level) * 3 then
		check("mindestens 3x alt auf Level " .. level, false, string.format("%d < 3 x %d", pay, oldPay(level)))
	end
	prevMult, prevPay = m, pay
end
check("Multiplikator und Ertrag steigen auf jedem Level", true)

check("Schild L1", CombConfig.formatMultiplier(1) == "×1", CombConfig.formatMultiplier(1))
check("Schild L2 mit Komma", CombConfig.formatMultiplier(2) == "×1,7", CombConfig.formatMultiplier(2))
check("Schild L10", CombConfig.formatMultiplier(10) == "×80", CombConfig.formatMultiplier(10))
local top = CombConfig.formatMultiplier(CombConfig.RECYCLER_MAX_LEVEL)
check("Schild L60 kurz", #top <= 8 and string.find(top, "K") ~= nil, top)
check("Sofort-Auszahlung an", CombConfig.INSTANT_PAYOUT == true)

if failures > 0 then error(failures .. " Test(s) fehlgeschlagen", 0) end
print("recycler: alle Tests gruen")
