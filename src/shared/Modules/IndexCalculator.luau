--!strict
-- IndexCalculator.luau
-- ReplicatedStorage/Modules/IndexCalculator.luau
--
-- Einzige Zustaendigkeit:
--   - Aus EggConfig die Struktur des Index ableiten: pro Ei die Baerchis mit
--     ihrer Wahrscheinlichkeit, und pro Baerchi die Eier, aus denen er faellt
--     (reine Funktionen, kein UI, kein Netzwerk)
--
-- Der Index hat KEINE eigene Liste von Baerchis oder Eiern. Alles wird aus den
-- hatchTables abgeleitet; wenn der Ei-Baum (Block B) neue Eier oder
-- Zuordnungen bringt, waechst der Index damit automatisch mit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EggConfig     = require(ReplicatedStorage.Config.EggConfig)
local BaerchiConfig = require(ReplicatedStorage.Config.BaerchiConfig)

local IndexCalculator = {}

export type Drop = {
	configId : string,
	chance   : number,   -- 0..1, bereits normalisiert
}

export type EggNode = {
	eggId     : string,
	sortOrder : number,
	drops     : { Drop },   -- chancenreichste zuerst
}

export type Source = {
	eggId  : string,
	chance : number,
}

-- Alle Eier in Anzeige-Reihenfolge, jeweils mit ihren Drops.
function IndexCalculator.buildTree(): { EggNode }
	local nodes: { EggNode } = {}

	for eggId, def in EggConfig.data do
		local total = 0
		for _, weight in def.hatchTable do
			total += weight
		end

		local drops: { Drop } = {}
		if total > 0 then
			for configId, weight in def.hatchTable do
				table.insert(drops, { configId = configId, chance = weight / total })
			end
		end

		-- Gleiche Chance? Dann nach id, sonst waere die Reihenfolge je Lauf anders.
		table.sort(drops, function(a, b)
			if a.chance ~= b.chance then return a.chance > b.chance end
			return a.configId < b.configId
		end)

		table.insert(nodes, { eggId = eggId, sortOrder = def.sortOrder, drops = drops })
	end

	table.sort(nodes, function(a, b)
		if a.sortOrder ~= b.sortOrder then return a.sortOrder < b.sortOrder end
		return a.eggId < b.eggId
	end)

	return nodes
end

-- Aus welchen Eiern faellt dieser Baerchi — chancenreichstes Ei zuerst.
function IndexCalculator.sourcesOf(configId: string): { Source }
	local sources: { Source } = {}

	for _, node in IndexCalculator.buildTree() do
		for _, drop in node.drops do
			if drop.configId == configId then
				table.insert(sources, { eggId = node.eggId, chance = drop.chance })
				break
			end
		end
	end

	table.sort(sources, function(a, b)
		if a.chance ~= b.chance then return a.chance > b.chance end
		return a.eggId < b.eggId
	end)

	return sources
end

-- Alle Baerchis, die der Index kennt (also aus mindestens einem Ei fallen),
-- sortiert nach Seltenheit und id.
function IndexCalculator.allPets(): { string }
	local seen: { [string]: boolean } = {}
	local list: { string } = {}

	for _, node in IndexCalculator.buildTree() do
		for _, drop in node.drops do
			if not seen[drop.configId] and BaerchiConfig.getById(drop.configId) then
				seen[drop.configId] = true
				table.insert(list, drop.configId)
			end
		end
	end

	table.sort(list, function(a, b)
		local da, db = BaerchiConfig.getById(a), BaerchiConfig.getById(b)
		if da and db then
			local ra, rb = BaerchiConfig.getRarityIndex(da.rarity), BaerchiConfig.getRarityIndex(db.rarity)
			if ra ~= rb then return ra < rb end
		end
		return a < b
	end)

	return list
end

return IndexCalculator
