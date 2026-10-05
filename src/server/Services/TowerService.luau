--!strict
-- TowerService.luau
-- ServerScriptService/Services/TowerService.luau
--
-- Einzige Zustaendigkeit:
--   - Den permanenten Tower-Fortschritt fuehren (v15, ersetzt das PIT-Level):
--     Tower-Wahl, Deckel pro Rebirth (weich), Rekorde, Meilensteine (auch
--     rueckwirkend), die PIT-Erstattung aus der Migration und der
--     Rebirth-Hinweis am Deckel.
--
-- Was ein Lauf ist und wie er simuliert wird, weiss CombatService; dieser
-- Service sagt ihm nur, in welchem Tower gekaempft wird, bis wohin es Belohnung
-- gibt, und nimmt am Ende das Ergebnis entgegen (recordRun). Die Zahlen stehen
-- in Config/TowerConfig.
--
-- Die Daten (data.towers) liegen ausserhalb der Insel wie der Ei-Baum: ein
-- Rebirth setzt die Insel zurueck, Rekorde und abgeholte Meilensteine bleiben.
--
-- Auszahlungen laufen ausschliesslich ueber die zustaendigen Services:
-- Gummies/GoldGummies ueber EconomyService (Meilensteine OHNE Multiplikator,
-- awardGummiesFlat), Eier ueber EggService.grantEggs, Blaupausen ueber
-- EggTreeService.grantBlueprint.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types       = require(ReplicatedStorage.Network.Types)
local Remotes     = require(ReplicatedStorage.Network.Remotes)
local Loc         = require(ReplicatedStorage.Localization.Loc)
local TowerConfig = require(ReplicatedStorage.Config.TowerConfig)
local LeaderboardConfig = require(ReplicatedStorage.Config.LeaderboardConfig)  -- Paket 9: Woche
local EggTree     = require(ReplicatedStorage.Modules.EggTree)

local PlayerService  = require(ServerScriptService.Services.PlayerService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local EggService     = require(ServerScriptService.Services.EggService)
local EggTreeService = require(ServerScriptService.Services.EggTreeService)
local RateLimiter    = require(ServerScriptService.Util.RateLimiter)

local TowerService = {}

-- Nur Studio/Debug: Spielstaende, fuer die jeder Tower offen ist (Kampf in allen
-- vier Towern ohne Rebirths testen). Schluessel = die Daten-Tabelle, schwach.
local _debugOpen: { [any]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function fail(player: Player, reason: Types.LocMsg)
	Remotes.ActionFailed:FireClient(player, "RequestSelectTower", reason)
end

--------------------------------------------------------------------------------
-- Lesen
--------------------------------------------------------------------------------

-- Deckel in diesem Tower beim aktuellen Rebirth (0 = Tower noch zu).
function TowerService.getStageCap(data: Types.PlayerData, towerId: string): number
	local cap = TowerConfig.getStageCap(data.rebirthCount, towerId, data.towers.records)
	if cap <= 0 and _debugOpen[data] then
		local def = TowerConfig.get(towerId)
		return if def then def.stages else 0
	end
	return cap
end

-- Der gewaehlte Tower; ist er (z. B. nach einer Datenreparatur) nicht offen,
-- der hoechste offene.
function TowerService.getSelected(data: Types.PlayerData): string
	local selected = data.towers.selected
	if TowerConfig.isOpen(data.rebirthCount, selected, data.towers.records) or (_debugOpen[data] and TowerConfig.isValidId(selected)) then
		return selected
	end
	local capTower = TowerConfig.getCap(data.rebirthCount)
	return capTower
end

--------------------------------------------------------------------------------
-- Meilensteine
--------------------------------------------------------------------------------

-- Zahlt einen einzelnen Meilenstein aus (einmalig) und meldet ihn dem Client.
-- Gibt true zurueck, wenn er neu abgeholt wurde.
local function grantMilestone(player: Player, data: Types.PlayerData, towerId: string, stage: number): boolean
	local milestone = TowerConfig.getMilestone(towerId, stage)
	if not milestone then return false end

	local claimed = data.towers.claimed[towerId]
	if not claimed then
		claimed = {}
		data.towers.claimed[towerId] = claimed
	end
	local key = tostring(stage)
	if claimed[key] then return false end
	claimed[key] = true

	local reward: Types.TowerMilestoneReward = {
		towerId     = towerId,
		stage       = stage,
		gummies     = 0,
		goldGummies = 0,
		eggType     = nil,
		eggs        = 0,
		blueprints  = 0,
	}

	if milestone.gummies > 0 then
		reward.gummies = EconomyService.awardGummiesFlat(player, milestone.gummies)
	end
	if milestone.goldGummies > 0 then
		reward.goldGummies = EconomyService.awardGoldGummies(player, milestone.goldGummies)
	end
	if milestone.eggs > 0 then
		local eggType = EggTree.highestUnlocked(data.eggTree)
		if EggService.grantEggs(player, eggType, milestone.eggs) then
			reward.eggType = eggType
			reward.eggs = milestone.eggs
		end
	end
	if milestone.blueprints > 0 then
		EggTreeService.grantBlueprint(player, data, milestone.blueprints)
		reward.blueprints = milestone.blueprints
	end
	if milestone.endlessLevels > 0 then
		local baerchi = data.island.equippedUid and data.island.baerchis[data.island.equippedUid]
		if baerchi then
			baerchi.endlessLevel = (baerchi.endlessLevel or 0) + milestone.endlessLevels
			reward.endlessLevels = milestone.endlessLevels
		end
	end

	-- Kurz verzoegert: beim Join haengt der Client sein UI erst noch an.
	task.delay(1, function()
		if player.Parent then
			Remotes.TowerMilestoneReceived:FireClient(player, reward)
		end
	end)
	return true
end

-- Alle noch offenen Meilensteine bis einschliesslich `upTo` (rueckwirkend).
local function grantMilestonesUpTo(player: Player, data: Types.PlayerData, towerId: string, upTo: number): number
	local granted = 0
	local stage = TowerConfig.MILESTONE_EVERY
	while stage <= upTo do
		if grantMilestone(player, data, towerId, stage) then
			granted += 1
		end
		stage += TowerConfig.MILESTONE_EVERY
	end
	return granted
end

--------------------------------------------------------------------------------
-- Ergebnis eines Laufs
--------------------------------------------------------------------------------

-- Vom CombatService am Ende eines Laufs aufgerufen. `highestWon` = hoechste
-- gewonnene Stage dieses Laufs. Rekord und Meilensteine zaehlen nur bis zum
-- Deckel (weich). Gibt den neuen Rekord (nil = keiner) und zurueck, ob der Lauf
-- den Deckel erreicht hat (Rebirth-Hinweis, nur wenn der Deckel ein echtes
-- Limit ist).
function TowerService.recordRun(player: Player, data: Types.PlayerData, towerId: string, highestWon: number): (number?, boolean)
	local def = TowerConfig.get(towerId)
	if not def or highestWon <= 0 then return nil, false end

	local cap = TowerService.getStageCap(data, towerId)
	local counted = math.min(highestWon, cap)

	-- Sammel-Update 05.10. (Paket 4.1): beste Stage dieses Lebens fuer die
	-- Rebirth-Bedingung. Ungedeckelt: die Bedingung liegt ohnehin unter dem
	-- Deckel, und ein Spieler, der darueber kaempft, hat sie erst recht erfuellt.
	local island = data.island
	if typeof(island.stageBest) ~= "table" then island.stageBest = {} end
	island.stageBest[towerId] = math.max(island.stageBest[towerId] or 0, highestWon)

	local newRecord: number? = nil
	local previous = data.towers.records[towerId] or 0
	if counted > previous then
		data.towers.records[towerId] = counted
		newRecord = counted
		if def.index > TowerConfig.getIndex(data.towers.highestTower) then
			data.towers.highestTower = towerId
		end
		grantMilestonesUpTo(player, data, towerId, counted)
	end

	-- Paket 9: beste Endless-Stage dieser Woche (Wochen-Bestenliste).
	if towerId == "Endless" then
		local week = LeaderboardConfig.weekOf(os.time())
		local entry = data.towers.endlessWeek
		if not entry or entry.week ~= week then
			entry = { week = week, best = 0 }
			data.towers.endlessWeek = entry
		end
		entry.best = math.max(entry.best, counted)
	end

	local capReached = highestWon >= cap and TowerConfig.isCapLimiting(data.rebirthCount, towerId)
	return newRecord, capReached
end

--------------------------------------------------------------------------------
-- Tower waehlen
--------------------------------------------------------------------------------

function TowerService.select(player: Player, towerId: string)
	local data = PlayerService.getData(player)
	if not data then return end

	if not TowerConfig.isValidId(towerId) then
		fail(player, Loc.msg("err.tower_unknown"))
		return
	end
	if not TowerConfig.isOpen(data.rebirthCount, towerId, data.towers.records) then
		if towerId == "Endless" then
			fail(player, Loc.msg("err.tower_locked_endless"))
		else
			fail(player, Loc.msg("err.tower_locked", { rebirths = TowerConfig.getOpeningRebirth(towerId) }))
		end
		return
	end
	if data.towers.selected == towerId then return end

	data.towers.selected = towerId
	PlayerService.markDirty(player)
end

-- Debug: alle Tower fuer diesen Spielstand oeffnen (bis zum Verlassen).
function TowerService.debugOpenAll(data: Types.PlayerData)
	_debugOpen[data] = true
end

-- Debug: Rekord direkt setzen (mit Meilensteinen bis dorthin).
function TowerService.debugSetRecord(player: Player, towerId: string, stage: number)
	local data = PlayerService.getData(player)
	local def = TowerConfig.get(towerId)
	if not data or not def then return end
	local value = math.clamp(math.floor(stage), 0, def.stages)
	data.towers.records[towerId] = value
	if value > 0 and def.index > TowerConfig.getIndex(data.towers.highestTower) then
		data.towers.highestTower = towerId
	end
	grantMilestonesUpTo(player, data, towerId, value)
	PlayerService.markDirty(player)
end

--------------------------------------------------------------------------------
-- Initialisierung
--------------------------------------------------------------------------------

function TowerService.init()
	RateLimiter.connect(Remotes.RequestSelectTower, "RequestSelectTower", function(player, towerId: any)
		if typeof(towerId) ~= "string" then return end
		TowerService.select(player, towerId)
	end)

	PlayerService.onDataLoaded(function(player, data)
		-- 1. PIT-Erstattung aus der Migration v14 -> v15 (einmalig).
		local refund = data.island.pitRefund or 0
		if refund > 0 then
			data.island.pitRefund = 0
			local paid = EconomyService.awardGummiesFlat(player, refund)
			task.delay(4, function()
				if player.Parent then
					Remotes.EventNotice:FireClient(player, Loc.msg("msg.pit_refund", { amount = paid }), "good")
				end
			end)
			print("[TowerService]", player.Name, "| PIT-Erstattung:", paid)
		end

		-- 2. Rueckwirkende Meilensteine (migrierter Rekord, oder ein neuer
		--    Meilenstein in der Config).
		for towerId, record in data.towers.records do
			grantMilestonesUpTo(player, data, towerId, record)
		end

		-- 3. Gewaehlter Tower muss offen sein.
		data.towers.selected = TowerService.getSelected(data)
	end)

	print("[TowerService] Initialisiert |", #TowerConfig.TOWERS, "Tower")
end

return TowerService
