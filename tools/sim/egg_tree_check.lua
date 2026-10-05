-- egg_tree_check.lua — Pruefungen fuer den Ei-Baum (WP4).
-- Aufruf: cd tools/luau-tests && node run.mjs ../sim/egg_tree_check.lua
-- Jede gescheiterte Pruefung schreibt eine Zeile mit "FAIL" (Exit-Code 1).
local EggConfig     = require(RS.Config.EggConfig)
local BaerchiConfig = require(RS.Config.BaerchiConfig)
local SkillConfig   = require(RS.Config.SkillConfig)
local EggTree       = require(RS.Modules.EggTree)

local fails = 0
local function check(ok, msg)
	if not ok then fails += 1; __log("FAIL " .. msg) end
end

-- 1. Jede Rarity-Verteilung = 100 %, jede hatchTable = 100 %
for eggId, egg in EggConfig.data do
	local sum = 0
	for _, p in EggConfig.RARITY_DIST[eggId] do sum += p end
	check(math.abs(sum - 100) < 1e-9, eggId .. ": Rarity-Summe " .. sum)
	local hs = 0
	for _, w in egg.hatchTable do hs += w end
	check(math.abs(hs - 100) < 1e-6, eggId .. ": hatchTable-Summe " .. hs)
	if egg.special then
		check(EggConfig.TREE[eggId] == nil, eggId .. ": Sonder-Ei darf keinen TREE-Eintrag haben")
		check(egg.parent == nil, eggId .. ": Sonder-Ei darf keinen Vorgaenger haben")
	else
		check(EggConfig.TREE[eggId] ~= nil, eggId .. ": kein TREE-Eintrag")
	end
end

-- 2. Ø steigt entlang jeder Kante
for eggId, egg in EggConfig.data do
	if egg.parent then
		local a, b = EggTree.expectedRarity(egg.parent), EggTree.expectedRarity(eggId)
		check(b > a, string.format("Ø faellt %s (%.2f) -> %s (%.2f)", egg.parent, a, eggId, b))
	end
end
-- Kosmos ueber allen drei Vorgaengern
local comet = EggTree.expectedRarity("CometEgg")
for _, e in { "ZenithEgg", "AuroraEgg", "AbyssEgg" } do
	check(comet > EggTree.expectedRarity(e), "Kometen-Ei nicht ueber " .. e)
end

-- 3. Jeder Baerchi faellt aus mindestens einem Ei; jedes gelegte Ei existiert;
--    jeder Skill existiert; Pfad gesetzt.
for id, def in BaerchiConfig.data do
	check(#def.eggSource > 0, id .. ": faellt aus keinem Ei")
	check(SkillConfig.getById(def.defaultSkill) ~= nil, id .. ": Skill fehlt " .. def.defaultSkill)
	check(def.path ~= nil, id .. ": kein Pfad")
	for _, e in def.eggTable do
		check(EggConfig.data[e.eggType] ~= nil, id .. ": legt unbekanntes Ei " .. e.eggType)
	end
end

-- 4. Nicht-Schaden-Bilanz
local utility, total = 0, 0
for _, def in BaerchiConfig.data do
	total += 1
	local s = SkillConfig.getById(def.defaultSkill)
	if s and s.category == "utility" then utility += 1 end
end
__log(string.format("INFO Nicht-Schaden-Faehigkeiten: %d von %d", utility, total))
-- Cosmic bis Omega: nur Schaden
for id, def in BaerchiConfig.data do
	if BaerchiConfig.getRarityIndex(def.rarity) >= BaerchiConfig.getRarityIndex("Cosmic") then
		local s = SkillConfig.getById(def.defaultSkill)
		check(s ~= nil and s.category == "damage", id .. ": ab Cosmic nur Schaden-Faehigkeiten")
	end
end
-- jede Faehigkeit hoechstens einmal (Einzigartigkeit)
local seen = {}
for id, def in BaerchiConfig.data do
	check(not seen[def.defaultSkill], "Faehigkeit doppelt: " .. def.defaultSkill .. " (" .. id .. ", " .. tostring(seen[def.defaultSkill]) .. ")")
	seen[def.defaultSkill] = id
end

-- 4b. SkillFX: jede Faehigkeit eines Baerchis hat eine EIGENE Show
local SkillFXConfig = require(RS.Config.SkillFXConfig)
local sigs = {}
for id, def in BaerchiConfig.data do
	local fx = SkillFXConfig.data[def.defaultSkill]
	check(fx ~= nil, id .. ": keine SkillFX fuer " .. def.defaultSkill)
	if fx then
		local parts = {}
		for _, st in fx.steps do
			table.insert(parts, string.format("%s@%.2f", st.fx, st.t or 0))
		end
		local sig = table.concat(parts, ",") .. tostring(fx.color)
		check(not sigs[sig], "SkillFX doppelt: " .. def.defaultSkill .. " = " .. tostring(sigs[sig]))
		sigs[sig] = def.defaultSkill
		local tier = SkillFXConfig.TIERS[fx.tier]
		check(fx.duration <= tier.maxDuration, def.defaultSkill .. ": Show laenger als Stufe erlaubt")
		local sound = false
		for _, st in fx.steps do if st.fx == "sound" then sound = true end end
		check(sound, def.defaultSkill .. ": kein Sound-Slot")
	end
end

-- 5. Fallback: alles gesperrt ausser Start -> jedes Ei faellt auf ein freies zurueck
local st = EggTree.newState()
for eggId in EggConfig.data do
	local r = EggTree.resolveLaid(st, eggId)
	check(EggTree.isUnlocked(st, r) or r == "AscensionEgg", eggId .. " faellt auf gesperrtes " .. r)
end

-- Tabelle ausgeben
for _, eggId in EggConfig.getOrderedIds() do
	local egg = EggConfig.data[eggId]
	local parts = {}
	local ids = {}
	for cid in egg.hatchTable do table.insert(ids, cid) end
	table.sort(ids, function(a, b) return egg.hatchTable[a] > egg.hatchTable[b] end)
	for _, cid in ids do table.insert(parts, string.format("%s %.2f", cid, egg.hatchTable[cid])) end
	__log(string.format("EGG %-17s %-9s Ø %.2f | %s", eggId, egg.path, EggTree.expectedRarity(eggId), table.concat(parts, ", ")))
end
__log(fails == 0 and "OK alle Ei-Baum-Pruefungen gruen" or ("FAIL " .. fails .. " Pruefungen"))
