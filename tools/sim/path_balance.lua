-- path_balance.lua — WP6: Pfad-Identitaeten pruefen.
-- Je Rarity mit mehreren Pfaden: wer ist am STAERKSTEN (PIT-Stages),
-- am SCHNELLSTEN (SPD und Lege-Tempo), am SELTENSTEN (Ø Rarity der gelegten
-- Eier)? Erwartung: Gold staerkster, Kristall schnellster, Void seltenster,
-- und kein Pfad gewinnt alle drei.
-- Aufruf: cd tools/luau-tests && node run.mjs ../sim/path_balance.lua
local BaerchiConfig    = require(RS.Config.BaerchiConfig)
local EggConfig        = require(RS.Config.EggConfig)
local CombatConfig     = require(RS.Config.CombatConfig)
local CombatCalculator = require(RS.Modules.CombatCalculator)
local BaerchiFactory   = require(RS.Modules.BaerchiFactory)
local EggCalculator    = require(RS.Modules.EggCalculator)
local EggTree          = require(RS.Modules.EggTree)

math.randomseed(77)
local LEVEL, PIT, RUNS = 30, 8, 30

local function stages(b)
	local def = BaerchiConfig.getById(b.configId)
	local stats = CombatCalculator.getEffectiveStats(b, def.baseStats)
	local total = 0
	for _ = 1, RUNS do
		local hp = stats.maxHp
		local charge = 0
		local n = 0
		for stage = 1, 400 do
			local es = CombatConfig.getEnemyStats(PIT, stage)
			local me = { uid = "me", stats = stats, hp = hp, charge = charge }
			local en = { uid = "en", stats = es, hp = es.maxHp, charge = 0 }
			local r = CombatCalculator.simulate(me, en, false)
			hp = math.clamp(me.hp, 0, stats.maxHp)
			charge = me.charge
			if r.winnerUid ~= "me" or hp <= 0 then break end
			n += 1
		end
		total += n
	end
	return total / RUNS
end

-- alles frei, damit kein Fallback die Wertung verzerrt
local state = EggTree.newState()
for id in EggConfig.data do state.unlocked[id] = true end

local function eggRarity(b)
	local def = BaerchiConfig.getById(b.configId)
	local total, sum = 0, 0
	for _, e in def.eggTable do
		local egg = e.eggType
		local w = e.weight
		local up = def.layUpgradeChance or 0
		local target = EggTree.upgradeTarget(state, egg, def.path)
		local base = EggTree.expectedRarity(egg)
		local val = base
		if target and up > 0 then
			val = base * (1 - up) + EggTree.expectedRarity(target) * up
		end
		sum += val * w
		total += w
	end
	return sum / total
end

local byRarity = {}
for id, def in BaerchiConfig.data do
	byRarity[def.rarity] = byRarity[def.rarity] or {}
	table.insert(byRarity[def.rarity], id)
end

local fails = 0
for _, rarity in BaerchiConfig.RARITY_ORDER do
	local ids = byRarity[rarity]
	if ids then
		table.sort(ids)
		local paths = {}
		-- Gewertet werden nur die Ziel-Pfade (Stamm ist Einstieg, kein Ziel).
		for _, id in ids do
			local pth = BaerchiConfig.data[id].path
			if pth ~= "Stamm" then paths[pth] = true end
		end
		local nPaths = 0
		for _ in paths do nPaths += 1 end
		local rows = {}
		for _, id in ids do
			local b = BaerchiFactory.create(id, { level = LEVEL })
			local def = BaerchiConfig.data[id]
			local stats = CombatCalculator.getEffectiveStats(b, def.baseStats)
			local interval = EggCalculator.getLayIntervalSeconds(b, false)
			local row = {
				id = id, path = def.path,
				str = stages(b),
				spd = stats.spd,
				eggsPerHour = 3600 / interval,
				rare = eggRarity(b),
			}
			table.insert(rows, row)
			__log(string.format("%-10s %-22s %-9s stages %6.1f | spd %.2f | eier/h %5.1f | Ø Ei-Rarity %.2f",
				rarity, id, def.path, row.str, row.spd, row.eggsPerHour, row.rare))
		end
		if nPaths >= 2 and rarity ~= "Common" and rarity ~= "Uncommon" then
			local function best(key)
				local b, bv = nil, -math.huge
				for _, r in rows do if r.path ~= "Stamm" and r[key] > bv then b, bv = r, r[key] end end
				return b
			end
			local s, f, r = best("str"), best("spd"), best("rare")
			local fastest = best("eggsPerHour")
			__log(string.format("  -> staerkster %s (%s) | schnellster %s (%s) | Eier/h %s (%s) | seltenster %s (%s)",
				s.id, s.path, f.id, f.path, fastest.id, fastest.path, r.id, r.path))
			if paths.Gold and s.path ~= "Gold" then fails += 1; __log("FAIL " .. rarity .. ": staerkster ist nicht Gold") end
			if paths.Kristall and (f.path ~= "Kristall" or fastest.path ~= "Kristall") then fails += 1; __log("FAIL " .. rarity .. ": schnellster ist nicht Kristall") end
			if paths.Void and r.path ~= "Void" then fails += 1; __log("FAIL " .. rarity .. ": seltenster ist nicht Void") end
			if s.id == f.id and f.id == r.id then fails += 1; __log("FAIL " .. rarity .. ": " .. s.id .. " gewinnt alles") end
		end
	end
end
__log(if fails == 0 then "OK Pfad-Balancing gruen" else ("FAIL " .. fails .. " Pfad-Pruefungen"))
