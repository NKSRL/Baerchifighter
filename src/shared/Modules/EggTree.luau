--!strict
-- EggTree.luau
-- ReplicatedStorage/Modules/EggTree.luau
--
-- Einzige Zustaendigkeit (v14, Mega Egg Tree):
--   - Aus EggConfig.TREE und dem Spielstand ableiten, welche Knoten frei
--     sind, was jedem Knoten noch fehlt, und welches Ei beim Legen an die
--     Stelle eines gesperrten tritt.
--
-- Reine Funktionen, kein Netzwerk, kein UI. Server (EggService,
-- EggLayService, RebirthService) und Client (EggTreePanel) rechnen mit
-- denselben Funktionen — das Panel zeigt also genau die Bedingungen, die der
-- Server auch prueft.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types         = require(ReplicatedStorage.Network.Types)
local EggConfig     = require(ReplicatedStorage.Config.EggConfig)
local BaerchiConfig = require(ReplicatedStorage.Config.BaerchiConfig)

local EggTree = {}

-- Was EggTree vom Spielstand braucht. PlayerData UND PlayerDataUpdate
-- (Client) passen beide hinein.
export type TreeInput = {
	eggTree      : Types.EggTreeState?,
	discovered   : { [string]: boolean }?,
	rebirthCount : number?,
}

export type Condition = {
	kind  : string,         -- "hatch" | "hatchAny" | "index" | "rebirth" | "blueprint"
	egg   : Types.EggType?, -- bei hatch
	rarity: Types.Rarity?,  -- bei index
	have  : number,
	need  : number,
	done  : boolean,
	-- nur bei hatchAny: die einzelnen Eier
	parts : { { egg: Types.EggType, have: number, need: number, done: boolean } }?,
	needParts : number?,
}

export type NodeProgress = {
	egg        : Types.EggType,
	unlocked   : boolean,
	ready      : boolean,      -- alle Bedingungen erfuellt (wird beim naechsten evaluate frei)
	bypassed   : boolean,      -- Blaupause eingesetzt
	conditions : { Condition },
}

function EggTree.newState(): Types.EggTreeState
	return {
		unlocked   = { BasicEgg = true, SugarEgg = true },
		hatched    = {},
		pressed    = {},
		blueprints = 0,
		bypass     = {},
	}
end

-- Fehlende Felder eines (alten oder kaputten) Stands ergaenzen.
function EggTree.sanitize(state: any): Types.EggTreeState
	if typeof(state) ~= "table" then
		return EggTree.newState()
	end
	if typeof(state.unlocked) ~= "table" then state.unlocked = {} end
	if typeof(state.hatched) ~= "table" then state.hatched = {} end
	if typeof(state.pressed) ~= "table" then state.pressed = {} end
	if typeof(state.bypass) ~= "table" then state.bypass = {} end
	if typeof(state.blueprints) ~= "number" then state.blueprints = 0 end
	for eggId, node in EggConfig.TREE do
		if node.start then state.unlocked[eggId] = true end
	end
	-- Unbekannte Ei-Typen (aus einer spaeteren/aelteren Config) entfernen.
	for eggId in state.unlocked do
		if not EggConfig.data[eggId :: Types.EggType] then state.unlocked[eggId] = nil end
	end
	return state :: Types.EggTreeState
end

function EggTree.isUnlocked(state: Types.EggTreeState?, eggType: Types.EggType): boolean
	if not state then
		local node = EggConfig.TREE[eggType]
		return node ~= nil and node.start == true
	end
	return state.unlocked[eggType] == true
end

-- Wie viele VERSCHIEDENE Baerchis dieser Rarity der Spieler entdeckt hat.
function EggTree.countDiscovered(discovered: { [string]: boolean }?, rarity: Types.Rarity): number
	if not discovered then return 0 end
	local n = 0
	for configId, seen in discovered do
		if seen then
			local def = BaerchiConfig.getById(configId)
			if def and def.rarity == rarity then
				n += 1
			end
		end
	end
	return n
end

local function hatchedOf(state: Types.EggTreeState?, egg: Types.EggType): number
	if not state then return 0 end
	return state.hatched[egg] or 0
end

-- Alle Bedingungen eines Knotens mit aktuellem Stand.
function EggTree.getProgress(input: TreeInput, eggType: Types.EggType): NodeProgress
	local state = input.eggTree
	local node = EggConfig.TREE[eggType] or {}
	local bypassed = state ~= nil and state.bypass[eggType] == true
	local conditions: { Condition } = {}

	if not node.start then
		if node.hatch and not bypassed then
			for _, req in node.hatch do
				local have = hatchedOf(state, req.egg)
				table.insert(conditions, {
					kind = "hatch", egg = req.egg, have = math.min(have, req.count),
					need = req.count, done = have >= req.count,
				})
			end
		end

		if node.hatchAnyOf and not bypassed then
			local parts = {}
			local doneCount = 0
			for _, req in node.hatchAnyOf.of do
				local have = hatchedOf(state, req.egg)
				local done = have >= req.count
				if done then doneCount += 1 end
				table.insert(parts, { egg = req.egg, have = math.min(have, req.count), need = req.count, done = done })
			end
			table.insert(conditions, {
				kind = "hatchAny", have = doneCount, need = node.hatchAnyOf.need,
				done = doneCount >= node.hatchAnyOf.need, parts = parts, needParts = node.hatchAnyOf.need,
			})
		end

		if node.index and not bypassed then
			local have = EggTree.countDiscovered(input.discovered, node.index.rarity)
			table.insert(conditions, {
				kind = "index", rarity = node.index.rarity, have = math.min(have, node.index.count),
				need = node.index.count, done = have >= node.index.count,
			})
		end

		if bypassed then
			table.insert(conditions, { kind = "blueprint", have = 1, need = 1, done = true })
		end

		if node.rebirth and node.rebirth > 0 then
			local have = input.rebirthCount or 0
			table.insert(conditions, {
				kind = "rebirth", have = math.min(have, node.rebirth), need = node.rebirth,
				done = have >= node.rebirth,
			})
		end
	end

	local ready = true
	for _, c in conditions do
		if not c.done then ready = false break end
	end

	return {
		egg        = eggType,
		unlocked   = EggTree.isUnlocked(state, eggType),
		ready      = ready,
		bypassed   = bypassed,
		conditions = conditions,
	}
end

-- Prueft alle Knoten und schaltet frei, was bereit ist. Mehrere Runden, weil
-- eine Freischaltung keine andere ausloest (Bedingungen haengen an
-- Hatch-Zaehlern, nicht an Freischaltungen) — eine Runde reicht, die
-- Schleife ist nur Vorsorge. Gibt die NEU freien Eier zurueck.
function EggTree.evaluate(input: TreeInput): { Types.EggType }
	local state = input.eggTree
	if not state then return {} end
	local newly: { Types.EggType } = {}
	for _, eggId in EggConfig.getOrderedIds() do
		if not state.unlocked[eggId] then
			local progress = EggTree.getProgress(input, eggId)
			if progress.ready then
				state.unlocked[eggId] = true
				table.insert(newly, eggId)
			end
		end
	end
	return newly
end

-- Kann auf diesem Knoten eine Blaupause eingesetzt werden? Nur, wenn er noch
-- gesperrt ist, nicht schon eine hat, kein reiner Rebirth-Knoten ist und sein
-- Vorgaenger (bzw. beim Kometen-Ei: zwei der drei Endeier) schon frei ist.
-- So schaltet eine Blaupause immer das NAECHSTE Ei frei, nie eins mitten im
-- Nirgendwo.
function EggTree.canUseBlueprint(input: TreeInput, eggType: Types.EggType): boolean
	local state = input.eggTree
	if not state or state.blueprints <= 0 then return false end
	if state.unlocked[eggType] or state.bypass[eggType] then return false end
	local node = EggConfig.TREE[eggType]
	local egg = EggConfig.data[eggType]
	if not node or not egg or node.start then return false end
	if not node.hatch and not node.hatchAnyOf then return false end
	if egg.parent then
		return state.unlocked[egg.parent] == true
	end
	if node.hatchAnyOf then
		local n = 0
		for _, req in node.hatchAnyOf.of do
			if state.unlocked[req.egg] then n += 1 end
		end
		return n >= node.hatchAnyOf.need
	end
	return false
end

-- ============================================================
-- LEGE-FALLBACK
-- ============================================================
-- Wuerfelt ein Baerchi ein noch GESPERRTES Ei, wird stattdessen das hoechste
-- freigeschaltete Ei desselben Pfads gelegt — also der naechste freie
-- Vorgaenger. Im Stamm endet die Kette bei Basis/Zucker, die immer frei
-- sind. Nichts geht verloren, nichts wird uebersprungen.
--
-- Sonderfaelle:
--   * Kometen-Ei (kein Vorgaenger im eigenen Pfad): das hoechste freie der
--     drei Endeier, sonst deren Fallback.
--   * Ascensions-Ei: wird IMMER gelegt (selten, nur von wenigen Baerchis).
--     Es ist ein Rebirth-Pfad, sein Knoten zeigt nur, ab wann man es planbar
--     bekommt. Seine Nachfolger legt kein Baerchi.
local LAY_ALWAYS: { [string]: boolean } = { AscensionEgg = true }

function EggTree.resolveLaid(state: Types.EggTreeState?, eggType: Types.EggType): Types.EggType
	if LAY_ALWAYS[eggType] or EggTree.isUnlocked(state, eggType) then
		return eggType
	end

	local egg = EggConfig.data[eggType]
	if not egg then
		return "BasicEgg"
	end

	if egg.parent then
		return EggTree.resolveLaid(state, egg.parent)
	end

	local node = EggConfig.TREE[eggType]
	if node and node.hatchAnyOf then
		local best: Types.EggType = "SugarEgg"
		local bestTier = 0
		for _, req in node.hatchAnyOf.of do
			local candidate = EggTree.resolveLaid(state, req.egg)
			local tier = EggConfig.data[candidate].tier
			if tier > bestTier then
				best, bestTier = candidate, tier
			end
		end
		return best
	end

	return "SugarEgg"
end

-- Void-Identitaet: ein gelegtes Ei kann eine Stufe aufsteigen (Chance je
-- Baerchi, BaerchiConfig.layUpgradeChance). Ziel ist die naechste Stufe im
-- Pfad des Eis — beim Zucker-Ei die im Pfad des Baerchis (Void-Baerchi:
-- Nebel-Ei). Nur, wenn das Ziel schon frei ist; sonst nil (kein Aufstieg).
function EggTree.upgradeTarget(state: Types.EggTreeState?, eggType: Types.EggType, petPath: string?): Types.EggType?
	local egg = EggConfig.data[eggType]
	if not egg or egg.path == "Ascension" then return nil end
	local prefer: string? = nil
	if egg.path == "Stamm" and eggType == "SugarEgg" then
		prefer = if petPath == "Gold" or petPath == "Void" then petPath else "Void"
	end
	local target = EggConfig.getNextInPath(eggType, prefer :: any)
	if target and EggTree.isUnlocked(state, target) then
		return target
	end
	return nil
end

-- Das hoechste freie Ei ueber alle Pfade ausser Ascension (Events).
-- Bei Gleichstand der Stufe gewinnt die kleinere sortOrder (stabil).
function EggTree.highestUnlocked(state: Types.EggTreeState?): Types.EggType
	local best: Types.EggType = "SugarEgg"
	local bestTier, bestOrder = 0, math.huge
	for eggId, egg in EggConfig.data do
		if egg.path ~= "Ascension" and not egg.special and EggTree.isUnlocked(state, eggId) then
			if egg.tier > bestTier or (egg.tier == bestTier and egg.sortOrder < bestOrder) then
				best, bestTier, bestOrder = eggId, egg.tier, egg.sortOrder
			end
		end
	end
	return best
end

-- "Sprung-Ei" (Events): eine Stufe ueber dem hoechsten freien Ei. Gewaehlt
-- wird zufaellig unter den gesperrten Kindern freier Knoten (ohne
-- Ascension). Gibt nil, wenn es keins gibt (alles frei).
function EggTree.pickJumpEgg(state: Types.EggTreeState?): Types.EggType?
	local options: { Types.EggType } = {}
	for _, eggId in EggConfig.getOrderedIds() do
		local egg = EggConfig.data[eggId]
		if egg.path ~= "Ascension" and not EggTree.isUnlocked(state, eggId) then
			local parentFree = (egg.parent ~= nil and EggTree.isUnlocked(state, egg.parent :: Types.EggType))
			if not egg.parent then
				local node = EggConfig.TREE[eggId]
				if node and node.hatchAnyOf then
					local n = 0
					for _, req in node.hatchAnyOf.of do
						if EggTree.isUnlocked(state, req.egg) then n += 1 end
					end
					parentFree = n >= node.hatchAnyOf.need
				end
			end
			if parentFree then table.insert(options, eggId) end
		end
	end
	if #options == 0 then return nil end
	return options[math.random(1, #options)]
end

-- Erwartete Rarity (1 = Common ... 12 = Omega) eines Eis — fuer Pruefskripte
-- und die Anzeige "Ø".
function EggTree.expectedRarity(eggType: Types.EggType): number
	local dist = EggConfig.RARITY_DIST[eggType]
	if not dist then return 0 end
	local sum, total = 0, 0
	for rarity, percent in dist do
		sum += BaerchiConfig.getRarityIndex(rarity :: Types.Rarity) * percent
		total += percent
	end
	return if total > 0 then sum / total else 0
end

return EggTree
