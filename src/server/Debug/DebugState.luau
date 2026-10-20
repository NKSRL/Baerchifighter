--!strict
-- DebugState.luau
-- ServerScriptService/Debug/DebugState.luau
--
-- Studio-Testbefehle: Ei-Baum, Freischaltung, Testzustaende.
-- Registriert sich beim require in DebugRegistry.commands; geladen nur von
-- DebugService.init() und nur in Studio (nie im Live-Spiel).

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types            = require(ReplicatedStorage.Network.Types)
local EconomyConfig    = require(ReplicatedStorage.Config.EconomyConfig)
local EggConfig        = require(ReplicatedStorage.Config.EggConfig)
local BaerchiConfig    = require(ReplicatedStorage.Config.BaerchiConfig)
local BaerchiFactory   = require(ReplicatedStorage.Modules.BaerchiFactory)
local CombatCalculator = require(ReplicatedStorage.Modules.CombatCalculator)
local PlayerService  = require(ServerScriptService.Services.PlayerService)
local EggService     = require(ServerScriptService.Services.EggService)
local MapService     = require(ServerScriptService.Services.MapService)
local EggTreeService            = require(ServerScriptService.Services.EggTreeService)
local EggTree                   = require(ReplicatedStorage.Modules.EggTree)
local CombatConfig              = require(ReplicatedStorage.Config.CombatConfig)
local TowerService              = require(ServerScriptService.Services.TowerService)
local FunnelService             = require(ServerScriptService.Services.FunnelService)
local DebugRegistry = require(script.Parent.DebugRegistry)

local commands = DebugRegistry.commands
local countBaerchis = DebugRegistry.countBaerchis

commands.tree = function(_player, data)
	local out = { blueprints = data.eggTree.blueprints, rebirths = data.rebirthCount }
	for _, eggId in EggConfig.getOrderedIds() do
		local p = EggTree.getProgress(data, eggId)
		local parts = {}
		for _, c in p.conditions do
			local label = c.kind .. (if c.egg then ":" .. c.egg elseif c.rarity then ":" .. c.rarity else "")
			table.insert(parts, string.format("%s %d/%d%s", label, c.have, c.need, if c.done then " ok" else ""))
		end
		out[string.format("%02d %s", EggConfig.data[eggId].sortOrder, eggId)] = string.format("%s | hatched %d | lager %d | %s",
			if p.unlocked then "FREI" else "zu", data.eggTree.hatched[eggId] or 0,
			data.island.eggStock[eggId] or 0, table.concat(parts, ", "))
	end
	return out
end

commands.unlock = function(player, data, eggType: any)
	if eggType == "all" then
		for _, eggId in EggConfig.getOrderedIds() do
			EggTreeService.forceUnlock(player, data, eggId, "debug")
		end
	elseif typeof(eggType) == "string" and EggConfig.data[eggType :: Types.EggType] then
		EggTreeService.forceUnlock(player, data, eggType :: Types.EggType, "debug")
	else
		return { error = "Unbekanntes Ei: " .. tostring(eggType) }
	end
	PlayerService.markDirty(player)
	return commands.tree(player, data)
end

commands.hatched = function(player, data, eggType: any, count: any)
	if typeof(eggType) ~= "string" or not EggConfig.data[eggType :: Types.EggType] then
		return { error = "Unbekanntes Ei: " .. tostring(eggType) }
	end
	data.eggTree.hatched[eggType] = math.max(0, math.floor(tonumber(count) or 0))
	PlayerService.markDirty(player)
	return commands.tree(player, data)
end

commands.blueprint = function(player, data, amount: any)
	EggTreeService.grantBlueprint(player, data, tonumber(amount) or 1)
	PlayerService.markDirty(player)
	return { blueprints = data.eggTree.blueprints }
end

commands.useblueprint = function(player, data, eggType: any)
	local ok = EggTreeService.useBlueprint(player, eggType)
	return { ok = ok, tree = commands.tree(player, data) }
end

commands.press = function(player, data, eggType: any, path: any)
	local result = EggTreeService.press(player, eggType, path)
	return { result = result, stock = data.island.eggStock }
end

commands.setrebirth = function(player, data, count: any)
	data.rebirthCount = math.max(0, math.floor(tonumber(count) or 0))
	data.rebirthMult  = EconomyConfig.getRebirthMult(data.rebirthCount)
	PlayerService.markDirty(player)
	return commands.tree(player, data)
end

-- Spielstand fuer Tests sichern und zuruecksetzen. Die Kopie liegt nur im
-- Speicher dieses Servers (nicht im DataStore).
local HttpService = game:GetService("HttpService")
local _snapshot: string? = nil

commands.snapshot = function(_player, data)
	_snapshot = HttpService:JSONEncode(data)
	return { ok = true, bytes = #(_snapshot :: string) }
end

commands.restore = function(player, data)
	if not _snapshot then return { error = "Kein Snapshot" } end
	local saved = HttpService:JSONDecode(_snapshot :: string)
	for k in data :: any do (data :: any)[k] = nil end
	for k, v in saved do (data :: any)[k] = v end
	MapService.rebuildIsland(player, data.island)
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)
	return { ok = true }
end

-- HBB Paket 0: feste Test-Zustaende fuer Playtests und Studio-Testschritte.
--   fresh   = Startstand eines neuen Kontos (createdAt = jetzt → Trichter misst)
--   hatch10 = fresh + zehn geoeffnete Basis-Eier
--   tower1  = hatch10 + Tower I geschafft (Rekord 30, Meilensteine ausgezahlt)
--
-- Studio spielt gegen den ECHTEN DataStore. Deshalb verlangt der Befehl einen
-- vorherigen "snapshot"; zurueck geht es mit "restore". Der Snapshot liegt nur
-- im Speicher dieses Servers — vor "Stop" also restore aufrufen.
--
-- Der Baerchi sollte zu Hause stehen (kein Kampf, kein Event), sonst haelt ein
-- anderer Service noch die alte Figur.
local TEST_STATES = { fresh = true, hatch10 = true, tower1 = true }
local TEST_HATCH_COUNT = 10
local TEST_TOWER_RECORD = 30

commands.state = function(player, data, name: any)
	local stateName = tostring(name or "")
	if not TEST_STATES[stateName] then
		return { error = "Unbekannter Zustand: " .. stateName, verfuegbar = { "fresh", "hatch10", "tower1" } }
	end
	if not _snapshot then
		return { error = "Erst D:Invoke(\"snapshot\") — Studio schreibt in den echten Spielstand" }
	end

	-- 1. fresh: alles ersetzen ausser Sitzungs-Sperre und Sprache
	local session  = (data :: any).session
	local language = data.language
	local fresh = PlayerService.buildDefaultData()
	for k in data :: any do (data :: any)[k] = nil end
	for k, v in fresh :: any do (data :: any)[k] = v end
	;(data :: any).session = session
	data.language = language
	MapService.rebuildIsland(player, data.island)
	FunnelService.debugReset(player)

	-- 2. hatch10: ueber den echten Weg oeffnen, damit Zaehler, Index und
	-- Auto-Ausruesten genau wie im Spiel laufen.
	if stateName == "hatch10" or stateName == "tower1" then
		data.island.eggStock.BasicEgg = (data.island.eggStock.BasicEgg or 0) + TEST_HATCH_COUNT
		for _ = 1, TEST_HATCH_COUNT do
			EggService.openEgg(player, "BasicEgg")
		end
	end

	-- 3. tower1: Rekord setzen, Meilensteine wie bei "towerrecord"
	if stateName == "tower1" then
		TowerService.debugSetRecord(player, "I", TEST_TOWER_RECORD)
	end

	PlayerService.markDirty(player)
	PlayerService.saveNow(player)
	return {
		ok = true,
		zustand = stateName,
		baerchis = countBaerchis(data),
		lager = data.island.eggStock,
		rekorde = data.towers.records,
		hinweis = "Zurueck mit D:Invoke(\"restore\")",
	}
end

-- Ein einzelner Kampf mit Runden-Log (Faehigkeiten pruefen).
commands.skilltest = function(_player, _data, configId: any, stage: any)
	local b = BaerchiFactory.create(tostring(configId), { level = 20 })
	if not b then return { error = "Unbekannter Baerchi" } end
	local def = BaerchiConfig.getById(b.configId)
	local stats = CombatCalculator.getEffectiveStats(b, (def :: any).baseStats)
	local es = CombatConfig.getEnemyStats(1, tonumber(stage) or 20)
	local me = { uid = "me", stats = stats, hp = stats.maxHp, charge = 0 }
	local en = { uid = "en", stats = es, hp = es.maxHp, charge = 0 }
	local r = CombatCalculator.simulate(me, en)
	local lines = {}
	for i, e in r.log do
		if i > 40 then break end
		table.insert(lines, string.format("%s r%d %s dmg %d heal %d abs %d | A %d B %d %s",
			e.actor, e.roundNumber, e.skillId or "-", e.damage, e.heal, e.absorbed,
			e.attackerHpAfter, e.defenderHpAfter, if e.effects then table.concat(e.effects, ",") else ""))
	end
	return { winner = r.winnerUid, rounds = r.rounds, skillUses = r.skillUses, log = lines }
end

return {}
