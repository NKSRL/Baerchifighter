--!strict
-- IndexRewardConfig.luau
-- ReplicatedStorage/Config/IndexRewardConfig.luau
--
-- Einzige Zustaendigkeit:
--   - Welche Kollektionen im Index eine Belohnung haben, wann sie fertig sind
--     und was sie bringen (Sammel-Update 05.10., Paket 7).
--
-- Server (IndexRewardService: pruefen und auszahlen) und Client (IndexView:
-- Fortschritt, "Abholen", "!" am Index) rechnen mit denselben Funktionen.
--
-- Vier Ebenen (Entscheidung 11.7, Standard: alle vier):
--   egg:<EggType>   alle Baerchis, die aus diesem Ei schluepfen koennen,
--                   entdeckt -> Gummies + Eier dieses Typs
--   path:<PathId>   alle Eier des Pfads fertig (Stamm, Gold, Kristall, Void,
--                   Kosmos) -> GoldGummies + Blaupause + 1 Inkubator-Platz
--   rarity:<Rarity> alle Baerchis dieser Rarity -> GoldGummies (= Charm-Wuerfe,
--                   seit GOLD_CHARMS_ONLY zahlt man Charms mit Gold)
--   all             der ganze Index -> 2 Ascensions-Eier (zaehlt als
--                   besonderer Meilenstein, Paket 6.2)
--
-- "Entdeckt" = die Art (data.discovered), Mutationen zaehlen nicht (Annahme
-- aus dem Plan; ein Mutations-Index waere ein eigener Ausbau).
--
-- Ascensions-Eier tauchen hier NUR bei "all" auf. Die Ei-Belohnung eines
-- Ascensions-Pfad-Eis ist deshalb Gold statt Eier (sonst waere das eine
-- dritte Quelle, siehe tools/check_consistency.py, Abschnitt 9).
--
-- Alle Zahlen sind ANNAHMEN (im Bericht SAMMEL_UPDATE_UMGESETZT benannt).

local Types         = require(script.Parent.Parent.Network.Types)
local EggConfig     = require(script.Parent.EggConfig)
local BaerchiConfig = require(script.Parent.BaerchiConfig)

local IndexRewardConfig = {}

export type Reward = {
	gummies        : number,
	goldGummies    : number,
	eggType        : Types.EggType?,
	eggs           : number,
	blueprints     : number,
	incubatorSlots : number,
}

export type Entry = {
	id      : string,
	kind    : string,                 -- "egg" | "path" | "rarity" | "all"
	key     : string,                 -- EggType / PathId / Rarity / "all"
	members : { string },             -- configIds, die entdeckt sein muessen
	reward  : Reward,
	order   : number,                 -- Anzeige-Reihenfolge
}

--------------------------------------------------------------------------------
-- Zahlen
--------------------------------------------------------------------------------

-- Ei-Reihe: Gummies = EGG_GUMMIES_BASE x EGG_GUMMIES_GROWTH^(Stufe-1),
-- ausgezahlt ueber EconomyService (mit Rebirth-Multiplikator). Dazu
-- EGG_COUNT Eier derselben Sorte.
IndexRewardConfig.EGG_GUMMIES_BASE   = 2000
IndexRewardConfig.EGG_GUMMIES_GROWTH = 5
IndexRewardConfig.EGG_COUNT          = 2
IndexRewardConfig.ASCENSION_EGG_GOLD = 60     -- statt Eiern (siehe Kopf)

-- Pfad: GoldGummies je Pfad, dazu 1 Blaupause und 1 Inkubator-Platz.
IndexRewardConfig.PATHS = { "Stamm", "Gold", "Kristall", "Void", "Kosmos" }
IndexRewardConfig.PATH_GOLD = {
	Stamm = 80, Gold = 200, Kristall = 200, Void = 200, Kosmos = 400,
}
IndexRewardConfig.PATH_BLUEPRINTS      = 1
IndexRewardConfig.PATH_INCUBATOR_SLOTS = 1

-- Rarity: GoldGummies = RARITY_GOLD_PER_INDEX x Rarity-Index (Common 1 ... Omega 12).
IndexRewardConfig.RARITY_GOLD_PER_INDEX = 20

-- Ganzer Index (besonderer Meilenstein).
IndexRewardConfig.ALL_EGGS = { eggType = "AscensionEgg" :: Types.EggType, count = 2 }
IndexRewardConfig.ALL_GOLD = 500

--------------------------------------------------------------------------------
-- Aufbau der Liste (aus EggConfig/BaerchiConfig berechnet)
--------------------------------------------------------------------------------

local function emptyReward(): Reward
	return { gummies = 0, goldGummies = 0, eggType = nil, eggs = 0, blueprints = 0, incubatorSlots = 0 }
end

local function sortedKeys(set: { [string]: boolean }): { string }
	local list = {}
	for id in set do table.insert(list, id) end
	table.sort(list)
	return list
end

local ENTRIES: { Entry } = {}
local BY_ID: { [string]: Entry } = {}

local function add(entry: Entry)
	table.insert(ENTRIES, entry)
	BY_ID[entry.id] = entry
end

do
	local order = 0

	-- Ei-Reihen (in Baum-Reihenfolge; Sonder-Eier ausserhalb des Baums nicht)
	local eggMembers: { [string]: { [string]: boolean } } = {}
	for _, eggId in EggConfig.getOrderedIds() do
		local egg = EggConfig.data[eggId]
		local set: { [string]: boolean } = {}
		for configId, weight in egg.hatchTable do
			if weight > 0 and BaerchiConfig.data[configId] then set[configId] = true end
		end
		eggMembers[eggId] = set

		local reward = emptyReward()
		reward.gummies = math.floor(IndexRewardConfig.EGG_GUMMIES_BASE
			* IndexRewardConfig.EGG_GUMMIES_GROWTH ^ (math.max(egg.tier, 1) - 1))
		if egg.path == "Ascension" then
			reward.goldGummies = IndexRewardConfig.ASCENSION_EGG_GOLD
		else
			reward.eggType = eggId
			reward.eggs    = IndexRewardConfig.EGG_COUNT
		end
		order += 1
		add({ id = "egg:" .. eggId, kind = "egg", key = eggId, members = sortedKeys(set), reward = reward, order = order })
	end

	-- Pfade: Vereinigung aller Ei-Reihen des Pfads
	for _, path in IndexRewardConfig.PATHS do
		local set: { [string]: boolean } = {}
		for eggId, members in eggMembers do
			if EggConfig.data[eggId].path == path then
				for configId in members do set[configId] = true end
			end
		end
		local reward = emptyReward()
		reward.goldGummies    = IndexRewardConfig.PATH_GOLD[path] or 0
		reward.blueprints     = IndexRewardConfig.PATH_BLUEPRINTS
		reward.incubatorSlots = IndexRewardConfig.PATH_INCUBATOR_SLOTS
		order += 1
		add({ id = "path:" .. path, kind = "path", key = path, members = sortedKeys(set), reward = reward, order = order })
	end

	-- Rarities
	local byRarity: { [string]: { [string]: boolean } } = {}
	for configId, def in BaerchiConfig.data do
		byRarity[def.rarity] = byRarity[def.rarity] or {}
		byRarity[def.rarity][configId] = true
	end
	local rarities = {}
	for rarity in byRarity do table.insert(rarities, rarity) end
	table.sort(rarities, function(a, b)
		return (BaerchiConfig.getRarityIndex(a :: any) or 0) < (BaerchiConfig.getRarityIndex(b :: any) or 0)
	end)
	for _, rarity in rarities do
		local reward = emptyReward()
		reward.goldGummies = IndexRewardConfig.RARITY_GOLD_PER_INDEX * (BaerchiConfig.getRarityIndex(rarity :: any) or 1)
		order += 1
		add({ id = "rarity:" .. rarity, kind = "rarity", key = rarity, members = sortedKeys(byRarity[rarity]), reward = reward, order = order })
	end

	-- Ganzer Index
	local all: { [string]: boolean } = {}
	for configId in BaerchiConfig.data do all[configId] = true end
	local reward = emptyReward()
	reward.eggType     = IndexRewardConfig.ALL_EGGS.eggType
	reward.eggs        = IndexRewardConfig.ALL_EGGS.count
	reward.goldGummies = IndexRewardConfig.ALL_GOLD
	order += 1
	add({ id = "all", kind = "all", key = "all", members = sortedKeys(all), reward = reward, order = order })
end

IndexRewardConfig.ENTRIES = ENTRIES

--------------------------------------------------------------------------------
-- Abfragen
--------------------------------------------------------------------------------

function IndexRewardConfig.get(id: string): Entry?
	return BY_ID[id]
end

-- (entdeckt, gesamt) einer Kollektion.
function IndexRewardConfig.progress(entry: Entry, discovered: { [string]: boolean }?): (number, number)
	local have = 0
	if discovered then
		for _, configId in entry.members do
			if discovered[configId] then have += 1 end
		end
	end
	return have, #entry.members
end

function IndexRewardConfig.isComplete(entry: Entry, discovered: { [string]: boolean }?): boolean
	local have, total = IndexRewardConfig.progress(entry, discovered)
	return total > 0 and have >= total
end

-- Alle fertigen, noch nicht abgeholten Belohnungen (fuer "!" und Hinweis).
function IndexRewardConfig.claimable(discovered: { [string]: boolean }?, claimed: { [string]: boolean }?): { string }
	local list = {}
	for _, entry in ENTRIES do
		if not (claimed and claimed[entry.id]) and IndexRewardConfig.isComplete(entry, discovered) then
			table.insert(list, entry.id)
		end
	end
	return list
end

-- Zusaetzliche Inkubator-Plaetze aus abgeholten Belohnungen (Paket 8).
function IndexRewardConfig.incubatorSlots(claimed: { [string]: boolean }?): number
	local n = 0
	if claimed then
		for id in claimed do
			local entry = BY_ID[id]
			if entry then n += entry.reward.incubatorSlots end
		end
	end
	return n
end

return IndexRewardConfig
