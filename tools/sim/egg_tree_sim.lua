-- egg_tree_sim.lua — WP4: wie lange dauert der Ei-Baum mit den echten
-- Lege-Intervallen? Und wie sieht die Rebirth-Kurve bis 100 aus?
--
-- Aufruf: cd tools/luau-tests && node run.mjs ../sim/egg_tree_sim.lua
--
-- ANNAHMEN (bewusst einfach, im Bericht genannt):
--   * Spielzeit ONLINE_H Stunden pro Tag, der Rest offline (2,5x langsamer,
--     hoechstens 12 Eier bis zum naechsten Einloggen).
--   * Der ausgeruestete Baerchi steht im Mittel auf Level LEVEL (Honig).
--   * Jedes Ei wird sofort geoeffnet. Die Ei-Presse wird NICHT benutzt.
--   * Der Spieler ruestet immer den Baerchi aus, der fuer die naechsten
--     Knoten am meisten bringt (gierig).
--   * Rebirth-Tempo: Stunden je Rebirth aus der Kosten-/Multi-Kurve,
--     geeicht mit REBIRTH5_HOURS fuer Rebirth 5 (Einkommen ist im Spiel
--     nicht messbar ohne Playtest — das ist die groesste Unsicherheit).
local BaerchiConfig  = require(RS.Config.BaerchiConfig)
local EggConfig      = require(RS.Config.EggConfig)
local EconomyConfig  = require(RS.Config.EconomyConfig)
local EggTree        = require(RS.Modules.EggTree)
local EggCalculator  = require(RS.Modules.EggCalculator)
local BaerchiFactory = require(RS.Modules.BaerchiFactory)

local ONLINE_H = ONLINE_HOURS or 2
local LEVEL = SIM_LEVEL or 12
local REBIRTH5_HOURS = 8
local MIN_REBIRTH_HOURS = 2
local SEED = 4242
local DAYS = 400

----------------------------------------------------------------------------
-- Rebirth-Kurve
----------------------------------------------------------------------------
-- Stunden fuer Rebirth n ~ Kosten(n) / Multi(n-1), geeicht auf Rebirth 5.
local function rebirthHours(n)
	local ref = EconomyConfig.getRebirthCost(4) / EconomyConfig.getRebirthMult(4)
	local cur = EconomyConfig.getRebirthCost(n - 1) / EconomyConfig.getRebirthMult(n - 1)
	-- Mindestens MIN_REBIRTH_HOURS: nach jedem Rebirth muessen Gebaeude und
	-- PIT neu hochgezogen werden, das geht nicht in Minuten.
	return math.max(MIN_REBIRTH_HOURS, REBIRTH5_HOURS * cur / ref)
end
local rebirthAt = {}   -- Spielstunde, zu der Rebirth n erreicht ist
do
	local h = 0
	for n = 1, 100 do
		h += rebirthHours(n)
		rebirthAt[n] = h
	end
end
local function rebirthsAfter(hours)
	local c = 0
	for n = 1, 100 do if rebirthAt[n] <= hours then c = n end end
	return c
end

if not SKIP_REBIRTH_TABLE then
	__log("REBIRTH  n | Kosten          | Multi        | Std. (Annahme) | Summe Std. | Tage bei " .. ONLINE_H .. " h")
	for _, n in { 1, 2, 3, 4, 5, 6, 8, 10, 15, 20, 25, 30, 40, 50, 60, 75, 100 } do
		__log(string.format("REBIRTH %3d | %15s | %12s | %6.1f | %8.0f | %6.0f",
			n, string.format("%.0f", EconomyConfig.getRebirthCost(n - 1)),
			tostring(EconomyConfig.getRebirthMult(n)), rebirthHours(n), rebirthAt[n], rebirthAt[n] / ONLINE_H))
	end
end

----------------------------------------------------------------------------
-- Ei-Baum
----------------------------------------------------------------------------
math.randomseed(SEED)
local data = {
	eggTree = EggTree.newState(),
	discovered = {},
	rebirthCount = 0,
}
local owned = {}   -- configId -> true

local function hatch(eggType)
	data.eggTree.hatched[eggType] = (data.eggTree.hatched[eggType] or 0) + 1
	local entries = {}
	for id, w in EggConfig.data[eggType].hatchTable do table.insert(entries, { id = id, w = w }) end
	table.sort(entries, function(a, b) return a.id < b.id end)
	local total = 0
	for _, e in entries do total += e.w end
	local r = math.random() * total
	for _, e in entries do
		r -= e.w
		if r <= 0 then
			owned[e.id] = true
			data.discovered[e.id] = true
			return
		end
	end
end

-- Start: 3 Basis-Eier
for _ = 1, 3 do hatch("BasicEgg") end

-- Ei-Rate eines Baerchis (nach Fallback und Aufstieg), je Ei-Typ, als Anteil.
local function layShares(configId)
	local def = BaerchiConfig.getById(configId)
	local shares = {}
	local total = 0
	for _, e in def.eggTable do total += e.weight end
	for _, e in def.eggTable do
		local egg = EggTree.resolveLaid(data.eggTree, e.eggType)
		local p = e.weight / total
		local up = def.layUpgradeChance or 0
		local target = if up > 0 then EggTree.upgradeTarget(data.eggTree, egg, def.path) else nil
		if target then
			shares[egg] = (shares[egg] or 0) + p * (1 - up)
			shares[target] = (shares[target] or 0) + p * up
		else
			shares[egg] = (shares[egg] or 0) + p
		end
	end
	return shares
end

local function intervalOf(configId)
	local b = BaerchiFactory.create(configId, { level = LEVEL })
	return EggCalculator.getLayIntervalSeconds(b, false)
end

-- Was wird gerade gebraucht? Gewicht je Ei-Typ.
local function needs()
	local need = {}
	for _, eggId in EggConfig.getOrderedIds() do
		if not data.eggTree.unlocked[eggId] then
			local p = EggTree.getProgress(data, eggId)
			for _, c in p.conditions do
				if not c.done then
					if c.kind == "hatch" then
						need[c.egg] = (need[c.egg] or 0) + 1
					elseif c.kind == "hatchAny" then
						for _, part in c.parts do
							if not part.done then need[part.egg] = (need[part.egg] or 0) + 0.7 end
						end
					elseif c.kind == "index" then
						-- Eier, die diese Rarity enthalten
						for e, dist in EggConfig.RARITY_DIST do
							if dist[c.rarity] and data.eggTree.unlocked[e] then
								need[e] = (need[e] or 0) + 0.5 * dist[c.rarity] / 100
							end
						end
					end
				end
			end
		end
	end
	return need
end

local function chooseEquip()
	local need = needs()
	local best, bestScore = nil, -1
	for id in owned do
		local shares = layShares(id)
		local rate = 3600 / intervalOf(id)
		local score = 0
		for egg, share in shares do
			score += (need[egg] or 0) * share * rate
			score += 0.001 * share * rate * EggTree.expectedRarity(egg)
		end
		if score > bestScore then best, bestScore = id, score end
	end
	return best
end

local unlockedAt = {}
for e in data.eggTree.unlocked do unlockedAt[e] = 0 end

local playHours = 0
local function evaluate()
	data.rebirthCount = if NO_GATES then 999 else rebirthsAfter(playHours)
	for _, e in EggTree.evaluate(data) do
		unlockedAt[e] = playHours
	end
end

local function layOne(configId)
	local shares = layShares(configId)
	local r = math.random()
	local list = {}
	for egg, p in shares do table.insert(list, { egg = egg, p = p }) end
	table.sort(list, function(a, b) return a.egg < b.egg end)
	for _, x in list do
		r -= x.p
		if r <= 0 then return x.egg end
	end
	return list[#list].egg
end

for day = 1, DAYS do
	-- Offline-Eier (gelegt seit gestern, max 12)
	local eq = chooseEquip()
	local offlineEggs = math.min(EggConfig.OFFLINE_MAX_EGGS, math.floor((24 - ONLINE_H) * 3600 / (intervalOf(eq) * EggConfig.OFFLINE_SLOWDOWN)))
	if day > 1 then
		for _ = 1, offlineEggs do hatch(layOne(eq)) end
		evaluate()
	end
	-- Online
	local t = 0
	while t < ONLINE_H * 3600 do
		eq = chooseEquip()
		local dt = intervalOf(eq)
		t += dt
		playHours += dt / 3600
		hatch(layOne(eq))
		evaluate()
	end
	local all = true
	for e in EggConfig.data do if not data.eggTree.unlocked[e] then all = false end end
	if all then break end
end

__log(string.format("SIM Annahmen: %d h/Tag online, Level %d, Rebirth 5 nach %d Std.", ONLINE_H, LEVEL, REBIRTH5_HOURS))
for _, eggId in EggConfig.getOrderedIds() do
	local h = unlockedAt[eggId]
	local node = EggConfig.TREE[eggId]
	local gate = node.rebirth or 0
	local gateH = if gate > 0 then rebirthAt[gate] else 0
	__log(string.format("TREE %-17s %s | Rebirth-Gate %2d (ab %5.0f Std.) | bremst: %s",
		eggId,
		if h then string.format("frei nach %6.1f Spielstunden = Tag %4d", h, math.floor(h / ONLINE_H) + 1) else "NICHT frei im Zeitraum      ",
		gate, gateH,
		if h and gate > 0 and math.abs(h - gateH) < 0.6 then "Rebirth" elseif h then "Eier" else "-"))
end
