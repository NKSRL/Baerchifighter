-- power_sweep.lua — Welt 1 P5b: Parameter-Suche fuer die Zielmatrix (a)(b)(c)
-- python tools/luau-tests/run_local.py tools/sim/power_sweep.lua
local Cfg = require(RS.Config.PowerConfig)
local P   = require(RS.Modules.PowerRules)
local function sample(k)
	local t = {}
	for i = 1, 500 do table.insert(t, P.roll(string.format("b_1760000000_%d_%d", i, i * 13 % 9973), k).total * P.baseG(k)) end
	table.sort(t)
	return t
end
local function med(t) return t[math.floor(#t / 2)] end
local rows = {}
for _, Sd in { 0.08, 0.10, 0.12, 0.15, 0.18 } do
 for _, Su in { 0.15, 0.18, 0.20, 0.22, 0.25, 0.30 } do
  for _, p in { 0.03, 0.04, 0.05, 0.06, 0.07 } do
   for _, F in { 0.0, 0.005, 0.01, 0.015, 0.02 } do
	Cfg.SPREAD, Cfg.SPREAD_UP, Cfg.POWER_PER_RARITY, Cfg.FLOOR_PER_RARITY = Sd, Su, p, F
	local worstA, worstB, worstC = 9, 9, 0
	local S = {}
	for k = 0, 11 do S[k] = sample(k) end
	for k = 1, 9 do
		local n, n1, n2, m1 = S[k], S[k + 1], S[k + 2], S[k - 1]
		local top = n[math.floor(#n * 0.85)]
		worstA = math.min(worstA, top / math.max(med(n1), med(n2)))
		worstB = math.min(worstB, n2[1] / med(m1))
		worstC = math.max(worstC, n1[#n1] / med(n))
	end
	if worstC <= 1.35 then table.insert(rows, { score = math.min(worstA, worstB), s = string.format("Sd=%.2f Su=%.2f p=%.2f F=%.3f | a=%.3f b=%.3f c=%.3f", Sd, Su, p, F, worstA, worstB, worstC) }) end
   end
  end
 end
end
table.sort(rows, function(x, y) return x.score > y.score end)
for i = 1, 8 do if rows[i] then __log(rows[i].s) end end
