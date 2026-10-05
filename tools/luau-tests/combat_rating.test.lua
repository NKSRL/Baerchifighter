-- combat_rating.test.lua — HBB Paket 4
-- python tools/luau-tests/run_local.py tools/luau-tests/combat_rating.test.lua
--
-- 1. Der Kampfwert steigt mit jedem einzelnen Stat.
-- 2. Die Rangfolge von Beispiel-Baerchis passt grob zu den Stages, die sie
--    im echten Kampfmodell (CombatCalculator + TowerConfig, HP-Uebertrag)
--    erreichen. Ersatz fuer sim/pit_balance.lua, das hier nicht vorliegt.

local CombatRating     = rbxRequire("ReplicatedStorage/Modules/CombatRating")
local CombatCalculator = rbxRequire("ReplicatedStorage/Modules/CombatCalculator")
local BaerchiFactory   = rbxRequire("ReplicatedStorage/Modules/BaerchiFactory")
local BaerchiConfig    = rbxRequire("ReplicatedStorage/Config/BaerchiConfig")
local TowerConfig      = rbxRequire("ReplicatedStorage/Config/TowerConfig")

local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else
		failures += 1
		print("FAIL " .. name .. (if detail then ": " .. detail else ""))
	end
end

-- 1. Monotonie je Stat
local base = { maxHp = 500, atk = 40, spd = 1.2, pwr = 0.2 }
local r0 = CombatRating.fromStats(base)
for _, key in { "maxHp", "atk", "spd", "pwr" } do
	local more = table.clone(base)
	more[key] = more[key] * 1.1 + 0.01
	check("steigt mit " .. key, CombatRating.fromStats(more) > r0)
end

-- 2. Rangfolge gegen erreichbare Staerke: hoechste Aequivalenz-Stage
--    (TowerConfig.getEquivalent), die der Baerchi mit vollen HP noch schlaegt.
--    Aequivalenz statt Tower-Stage, damit schwache und starke Baerchis auf
--    derselben Skala landen (I/1 = Aequivalenz 1, Final/100 = Maximum).
local CombatConfig = rbxRequire("ReplicatedStorage/Config/CombatConfig")
local MAX_EQ = TowerConfig.getEquivalent("Final", TowerConfig.get("Final").stages)

local function wins(stats, eq)
	local me = { uid = "me", stats = stats, hp = stats.maxHp, charge = 0 }
	local es = CombatConfig.getEnemyStatsForEquivalent(eq)
	local en = { uid = "en", stats = es, hp = es.maxHp, charge = 0 }
	return CombatCalculator.simulate(me, en, false).winnerUid == "me"
end

local function reach(baerchi)
	local def = BaerchiConfig.getById(baerchi.configId)
	local stats = CombatCalculator.getEffectiveStats(baerchi, def.baseStats)
	if not wins(stats, 1) then return 0 end
	-- Kampfausgang ist (fast) monoton in der Aequivalenz: Binaersuche
	local lo, hi = 1, MAX_EQ
	if wins(stats, hi) then return hi end
	while hi - lo > 0.5 do
		local mid = (lo + hi) / 2
		if wins(stats, mid) then lo = mid else hi = mid end
	end
	return math.floor(lo * 10 + 0.5) / 10
end

local samples = {}
for _, id in { "RedBaerchi", "BlueBaerchi", "SugarBaerchi", "GoldenGrizzly", "RainbowBaerchi",
	"CosmicBaerchi", "SeraphBaerchi", "CometBaerchi", "TitanBaerchi", "OmegaBaerchi" } do
	for _, level in { 1, 15, 30 } do
		local b = BaerchiFactory.create(id, { level = level })
		if b then
			table.insert(samples, { name = id .. " L" .. level, rating = CombatRating.of(b), stage = reach(b) })
		end
	end
end

-- Spearman-Rangkorrelation
local function ranks(list, key)
	local idx = {}
	for i = 1, #list do idx[i] = i end
	table.sort(idx, function(a, b) return list[a][key] < list[b][key] end)
	local r = {}
	local i = 1
	while i <= #idx do
		local j = i
		while j < #idx and list[idx[j + 1]][key] == list[idx[i]][key] do j += 1 end
		local avg = (i + j) / 2
		for k = i, j do r[idx[k]] = avg end
		i = j + 1
	end
	return r
end
local ra, rb = ranks(samples, "rating"), ranks(samples, "stage")
local n = #samples
local ma, mb = 0, 0
for i = 1, n do ma += ra[i]; mb += rb[i] end
ma /= n; mb /= n
local cov, va, vb = 0, 0, 0
for i = 1, n do
	cov += (ra[i] - ma) * (rb[i] - mb)
	va += (ra[i] - ma) ^ 2
	vb += (rb[i] - mb) ^ 2
end
local rho = cov / math.sqrt(va * vb)

table.sort(samples, function(a, b) return a.rating < b.rating end)
print(string.format("%-22s %10s %8s", "Baerchi", "Kampfwert", "Aequiv."))
for _, s in samples do
	print(string.format("%-22s %10d %8.1f", s.name, s.rating, s.stage))
end
print(string.format("Spearman rho = %.3f (Stichprobe %d)", rho, n))
check("Rangfolge passt zu erreichbaren Stages (rho >= 0.85)", rho >= 0.85, string.format("rho = %.3f", rho))

if failures > 0 then error(failures .. " Test(s) fehlgeschlagen") end
print("combat_rating: alle Tests gruen")
