-- power_rules.test.lua — Welt 1, Paket 5b (20.10.2026)
-- python tools/luau-tests/run_local.py tools/luau-tests/power_rules.test.lua
local P   = require(RS.Modules.PowerRules)
local Cfg = require(RS.Config.PowerConfig)
local FLOORZERO = true

local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else failures += 1; print("FAIL " .. name .. (detail ~= nil and (" -> " .. tostring(detail)) or "")) end
end

-- Deterministisch
local a, b = P.roll("b_1760000000_5_1234", 4), P.roll("b_1760000000_5_1234", 4)
check("gleiche uid = gleicher Wurf", a.total == b.total and a.hp == b.hp and a.pwr == b.pwr)
local c = P.roll("b_1760000000_6_1234", 4)
check("andere uid = anderer Wurf", c.total ~= a.total)

-- Grenzen, Gleichverteilung, Rarity-Minimum
local N = 4000
for _, k in { 0, 5, 11 } do
	local lo, hi = P.range(k)
	local minT, maxT, sum = 99, 0, 0
	for i = 1, N do
		local r = P.roll(string.format("b_1760000000_%d_%d", i, i * 7 % 9000), k)
		minT = math.min(minT, r.total); maxT = math.max(maxT, r.total); sum += r.total
	end
	check(("Rarity %d: Wurf in [lo,hi]"):format(k), minT >= lo - 1e-9 and maxT <= hi + 1e-9, minT .. ".." .. maxT)
	local mean = sum / N
	check(("Rarity %d: Mittel wie erwartet (%.3f)"):format(k, mean), math.abs(mean - (lo + (hi - lo) / (Cfg.SHAPE + 1))) < 0.01, mean)
end
local lo0 = P.range(0); local lo11 = P.range(11)
check("Rarity-Minimum: absolute Untergrenze steigt mit der Rarity", lo11 * P.baseG(11) > lo0 * P.baseG(0))

-- HP*ATK-Produkt = T^2 (Verteilung aendert nicht die Gesamtstaerke)
local r = P.roll("b_1760000000_77_4242", 3)
check("hp*atk = T^2", math.abs(r.hp * r.atk - r.total ^ 2) < 1e-9)

-- Bestandsschutz
local cutoff = 1760000500
local worst = 99
for i = 1, 3000 do
	local x = P.rollWith(string.format("b_1760000000_%d_%d", i, i), 2, cutoff)
	worst = math.min(worst, x.total)
end
check("Bestand (uid vor Stichtag): T >= 1.0", worst >= 1.0, worst)
local newWorst = 99
for i = 1, 3000 do
	local x = P.rollWith(string.format("b_1760009999_%d_%d", i, i), 2, cutoff)
	newWorst = math.min(newWorst, x.total)
end
check("Neue Pets (nach Stichtag) koennen unter 1.0 liegen", newWorst < 1.0, newWorst)
check("uid ohne Zeitstempel -> kein Bestand", P.uidTime("irgendwas") == nil)

-- Grade
check("Qualitaet 0.1 = weak", P.grade(0.1) == "weak")
check("Perzentil-Qualitaet ~ gleichverteilt", (function() local s = 0; for i = 1, 2000 do s += P.roll("b_1760000000_" .. i .. "_" .. i * 3, 4).quality end return math.abs(s / 2000 - 0.5) < 0.03 end)())
check("Qualitaet 0.5 = good", P.grade(0.5) == "good")
check("Qualitaet 1.0 = outstanding", P.grade(1.0) == "outstanding")

-- Normalisierung: Verhaeltnis bleibt, g folgt der Rarity
local base = { hp = 420, atk = 40, spd = 0.85, pwr = 0.14 }
local v = P.applyV2(base, 0, "b_1760000000_1_1")
local ratioOld, ratioNew = base.hp / base.atk, v.hp / v.atk
local rr = P.roll("b_1760000000_1_1", 0)
check("Verhaeltnis bleibt bis auf den Wurf-Skew", math.abs(ratioNew / ratioOld - rr.hp / rr.atk) < 1e-6)

-- Zielmatrix (Spieler-Stufe 1): (a) Top-15 % von N schlaegt Median von N+1 und N+2; (b) schlechtester N+2 > Median N-1;
-- (c) bester N+1 / Median N <= 1.35
local function sample(k)
	local t = {}
	for i = 1, 3000 do table.insert(t, P.roll(string.format("b_1760000000_%d_%d", i, i * 13 % 9973), k).total * P.baseG(k)) end
	table.sort(t)
	return t
end
local ok_a, ok_b, ok_c = true, true, true
local detail = {}
for k = 1, 9 do
	local n, n1, n2, m1 = sample(k), sample(k + 1), sample(k + 2), sample(k - 1)
	local top15 = n[math.floor(#n * 0.85)]
	local med = function(t) return t[math.floor(#t / 2)] end
	if not (top15 > med(n1) and top15 > med(n2)) then ok_a = false; table.insert(detail, "a@" .. k .. " " .. top15 .. " vs " .. med(n1) .. "/" .. med(n2)) end
	if not (n2[1] > med(m1)) then ok_b = false; table.insert(detail, "b@" .. k) end
	if not (n1[#n1] / med(n) <= 1.35) then ok_c = false; table.insert(detail, "c@" .. k .. " " .. n1[#n1] / med(n)) end
end
check("Zielmatrix (a) guter Wurf N schlaegt Median N+1 und N+2", ok_a, detail[1])
check("Zielmatrix (b) Minimum: schlechtester N+2 > Median N-1", ok_b, detail[1])
check("Zielmatrix (c) bester N+1 / Median N <= 1.35", ok_c, detail[1])

-- Schalter aus = altes Modell 1:1 (Standard); an = anderes Ergebnis fuer ein hohes Pet
local FF = require(RS.Config.FeatureFlags)
local CC = require(RS.Modules.CombatCalculator)
local BC = require(RS.Config.BaerchiConfig)
local BF = require(RS.Modules.BaerchiFactory)
check("POWER_MODEL_V2 ist standardmaessig aus", FF.isOn("POWER_MODEL_V2") == false)
local omega = BF.create("OmegaBaerchi", { level = 10 })
local def = BC.getById("OmegaBaerchi")
local off = CC.getEffectiveStats(omega, def.baseStats)
local expectOld = math.floor(def.baseStats.hp * CC.getLevelGrowth(10))
check("Aus: HP = Basis * Level-Wachstum (altes Modell)", off.maxHp == expectOld, off.maxHp .. " vs " .. expectOld)
FF.FLAGS.POWER_MODEL_V2 = true
local on = CC.getEffectiveStats(omega, def.baseStats)
FF.FLAGS.POWER_MODEL_V2 = false
check("An: Omega deutlich schwaecher als alt (Rarity-Spanne komprimiert)", on.maxHp < off.maxHp * 0.2, on.maxHp .. " vs " .. off.maxHp)
check("Aus nach Test wieder altes Ergebnis", CC.getEffectiveStats(omega, def.baseStats).maxHp == off.maxHp)

if failures > 0 then error(failures .. " Fehler") end
print("alle ok")
