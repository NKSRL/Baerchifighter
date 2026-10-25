-- drop_rates_v2.lua — Welt 1, Paket 5c: Drop-Tabelle alt/neu, Erwartungswert in Oeffnungen und Spielzeit
-- python tools/luau-tests/run_local.py tools/sim/drop_rates_v2.lua
-- Annahme Spielzeit: EGGS_PER_MIN Eier pro Minute aktive Spielzeit (Lege-Intervalle ~80-185 s, Honig, Inkubator, Haendler),
-- Startwert 1 Ei/Min (egg_tree_sim rechnet genauer; hier nur Groessenordnung). Aufruf mit EGGS_PER_MIN = x vorher setzen.
local EggConfig     = require(RS.Config.EggConfig)
local BaerchiConfig = require(RS.Config.BaerchiConfig)
local EPM = EGGS_PER_MIN or 1

local function rarestOf(dist)
	local best, bi = nil, 0
	for r, p in dist do
		local i = BaerchiConfig.getRarityIndex(r)
		if i > bi then best, bi = r, i end
	end
	return best, dist[best]
end

local function pad(s, n) return string.format("%-" .. n .. "s", s) end
local ids = EggConfig.getOrderedIds()
__log("Ei               | seltenste Stufe   alt -> neu | Schluessel-Pet(s) fuer Kind: Chance/Oeffnung alt -> neu | Oeffnungen (neu) | Min. (neu)")
local function keyChance(eggId)
	-- Chance, dass eine Oeffnung von eggId ein Schluessel-Pet eines Kind-Eis liefert (mindestens eines der Kinder)
	local out = {}
	for _, child in EggConfig.getChildren(eggId) do
		local node = EggConfig.TREE[child]
		if node and node.keyPets then
			local sum = 0
			for _, pet in node.keyPets do sum += EggConfig.data[eggId].hatchTable[pet] or 0 end
			out[child] = sum
		end
	end
	return out
end
local rowsOld = {}
EggConfig.setDropRatesV2(false)
for _, id in ids do rowsOld[id] = keyChance(id) end
EggConfig.setDropRatesV2(true)
for _, id in ids do
	local dOld, dNew = EggConfig.RARITY_DIST[id], EggConfig.getRarityDist(id)
	local r, pOld = rarestOf(dOld)
	local _, pNew = rarestOf(dNew)
	local kc = keyChance(id)
	local keys = {}
	for child, v in kc do
		local o = rowsOld[id][child]
		table.insert(keys, string.format("%s %.2f%%->%.2f%% (%d Oeffn., %d Min.)", child, o, v, v > 0 and math.ceil(100 / v) or -1, v > 0 and math.ceil(100 / v / EPM) or -1))
	end
	table.sort(keys)
	__log(string.format("%-16s | %-10s %5.2f%% -> %5.2f%% | %s | 1/p = %d Oeffn.", id, r, pOld, pNew, #keys > 0 and table.concat(keys, "; ") or "-", math.ceil(100 / pNew)))
end
__log("")
__log("Verteilung neu je Ei (Prozent):")
for _, id in ids do
	local parts = {}
	for r, p in EggConfig.getRarityDist(id) do table.insert(parts, { BaerchiConfig.getRarityIndex(r), string.format("%s %.2f", r, p) }) end
	table.sort(parts, function(a, b) return a[1] < b[1] end)
	local t = {}
	for _, x in parts do table.insert(t, x[2]) end
	__log(string.format("  %-16s %s", id, table.concat(t, " | ")))
end
EggConfig.setDropRatesV2(false)
