-- drop_rates.test.lua — Welt 1, Paket 5c (20.10.2026)
-- python tools/luau-tests/run_local.py tools/luau-tests/drop_rates.test.lua
local EggConfig     = require(RS.Config.EggConfig)
local BaerchiConfig = require(RS.Config.BaerchiConfig)
local FF            = require(RS.Config.FeatureFlags)

local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else failures += 1; print("FAIL " .. name .. (detail ~= nil and (" -> " .. tostring(detail)) or "")) end
end

check("DROPRATES_V2 standardmaessig aus", FF.isOn("DROPRATES_V2") == false)

local function sum(t) local s = 0 for _, v in t do s += v end return s end
local oldTables = {}
for id, egg in EggConfig.data do
	local copy = {}
	for k, v in egg.hatchTable do copy[k] = v end
	oldTables[id] = copy
end

local ok_sum, ok_rare, ok_order, ok_hatch = true, true, true, true
local why = {}
for id, dist in EggConfig.RARITY_DIST_V2 do
	if math.abs(sum(dist) - 100) > 1e-6 then ok_sum = false; table.insert(why, "Summe " .. id) end
	local pct = EggConfig.RAREST_PCT_V2[id]
	if pct then
		local bi, bp = 0, 0
		for r, p in dist do local i = BaerchiConfig.getRarityIndex(r) if i > bi then bi, bp = i, p end end
		if math.abs(bp - pct) > 1e-6 then ok_rare = false; table.insert(why, "rarest " .. id .. " " .. bp) end
		-- Haeufigkeit steigt nach unten
		local rows = {}
		for r, p in dist do table.insert(rows, { BaerchiConfig.getRarityIndex(r), p }) end
		table.sort(rows, function(a, b) return a[1] < b[1] end)
		for i = 2, #rows do if rows[i][2] > rows[i - 1][2] + 1e-9 then ok_order = false; table.insert(why, "Ordnung " .. id) end end
	end
end
check("V2: jede Verteilung = 100 %", ok_sum, why[1])
check("V2: seltenste Stufe je Ei = Vorgabe (10/5/1/0,1)", ok_rare, why[1])
check("V2: Haeufigkeit steigt nach unten", ok_order, why[1])
check("Stufen: 5 x 10 %, 5 x 5 %, 5 x 1 %, 4 x 0,1 %", (function()
	local c = { [10] = 0, [5] = 0, [1] = 0, [0.1] = 0 }
	for _, p in EggConfig.RAREST_PCT_V2 do c[p] += 1 end
	return c[10] == 5 and c[5] == 5 and c[1] == 5 and c[0.1] == 4
end)())

EggConfig.setDropRatesV2(true)
for id, egg in EggConfig.data do
	if math.abs(sum(egg.hatchTable) - 100) > 1e-6 then ok_hatch = false; table.insert(why, "hatch " .. id) end
end
check("V2: jede hatchTable = 100 %", ok_hatch, why[#why])
-- Schluessel-Pets bleiben erreichbar (>= 0.5 % je Oeffnung des Vorgaenger-Eis)
local keyOk, keyWhy = true, nil
for _, id in EggConfig.getOrderedIds() do
	for _, child in EggConfig.getChildren(id) do
		local node = EggConfig.TREE[child]
		if node and node.keyPets then
			local s = 0
			for _, pet in node.keyPets do s += EggConfig.data[id].hatchTable[pet] or 0 end
			if s < 0.5 then keyOk = false; keyWhy = id .. " -> " .. child .. " " .. s end
		end
	end
end
check("V2: Schluessel-Pets erreichbar (>= 0,5 % je Oeffnung)", keyOk, keyWhy)
EggConfig.setDropRatesV2(false)
local same = true
for id, egg in EggConfig.data do
	for k, v in egg.hatchTable do if math.abs((oldTables[id][k] or -1) - v) > 1e-9 then same = false end end
end
check("Aus: hatchTables wieder exakt wie vorher", same)
check("CHILDREN nach Umschalten nicht verdoppelt", #EggConfig.getChildren("SugarEgg") == 2, #EggConfig.getChildren("SugarEgg"))

if failures > 0 then error(failures .. " Fehler") end
print("alle ok")
