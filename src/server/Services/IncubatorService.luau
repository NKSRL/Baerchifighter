--!strict
-- IncubatorService.luau
-- ServerScriptService/Services/IncubatorService.luau
--
-- Einzige Zustaendigkeit:
--   - Der Inkubator (Sammel-Update 05.10., Paket 8, Umbau nach Rueckmeldung
--     05.10.): einen Baerchi in einen freien Platz setzen, wieder
--     herausnehmen, die gebrueteten Eier abholen und den Inkubator ausbauen.
--   - Der Brut-Takt: jeder belegte Platz bruetet im Takt der Rarity seines
--     Baerchis zusaetzliche Eier aus dessen Ei-Tabelle — zusaetzlich zu den
--     Eiern, die der ausgeruestete Baerchi legt.
--
-- Bedienung durch Hingehen: alle Aktionen nur in der Naehe des Inkubators
-- (IncubatorConfig.USE_DISTANCE, Server prueft). Keine Seitenknoepfe.
--
-- Zeitmarke statt Timer pro Ei: ein Platz traegt lastEggAt, der Takt hier
-- rechnet nur nach (IncubatorRules.due) — auch offline (beim Laden, gebremst
-- mit EggConfig.OFFLINE_SLOWDOWN) und ueber Server-Neustarts hinweg.
--
-- Aufraeumen: ein Baerchi, den es nicht mehr gibt (Fusion, Recycler,
-- Rebirth) oder der ausgeruestet wurde, verlaesst seinen Platz im naechsten
-- Takt; seine wartenden Eier gehen ins Lager, nichts geht verloren.
--
-- Was NICHT hier passiert: Waehrungen (EconomyService), Anzeige
-- (PlotDisplayService/MapService ueber die Signatur), Schluepfen (EggService).

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types           = require(ReplicatedStorage.Network.Types)
local Remotes         = require(ReplicatedStorage.Network.Remotes)
local Loc             = require(ReplicatedStorage.Localization.Loc)
local FeatureFlags    = require(ReplicatedStorage.Config.FeatureFlags)
local IncubatorConfig = require(ReplicatedStorage.Config.IncubatorConfig)
local IncubatorRules  = require(ReplicatedStorage.Modules.IncubatorRules)
local EggCalculator   = require(ReplicatedStorage.Modules.EggCalculator)
local EggTree         = require(ReplicatedStorage.Modules.EggTree)

local PlayerService  = require(ServerScriptService.Services.PlayerService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local MapService     = require(ServerScriptService.Services.MapService)
local RateLimiter    = require(ServerScriptService.Util.RateLimiter)

local IncubatorService = {}

local function fail(player: Player, action: string, reason: Types.LocMsg)
	Remotes.ActionFailed:FireClient(player, action, reason)
end

local function changed(player: Player, slot: number, kind: string, count: number?)
	Remotes.IncubatorChanged:FireClient(player, { slot = slot, kind = kind, count = count or 0 })
end

-- Gemeinsame Vorpruefung. Gibt die Daten zurueck, wenn der Inkubator benutzbar ist.
local function usable(player: Player, action: string, needNear: boolean): Types.PlayerData?
	if not FeatureFlags.isOn("INCUBATOR") then return nil end
	local data = PlayerService.getData(player)
	if not data then return nil end
	if not IncubatorRules.isUnlocked(data) then
		fail(player, action, Loc.msg("err.incubator_locked"))
		return nil
	end
	if needNear then
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		local at = MapService.getBuildingPosition(player, IncubatorConfig.MODEL_NAME)
		if not (root and root:IsA("BasePart") and at)
			or Vector3.new(root.Position.X - at.X, 0, root.Position.Z - at.Z).Magnitude > IncubatorConfig.USE_DISTANCE then
			fail(player, action, Loc.msg("err.incubator_too_far"))
			return nil
		end
	end
	return data
end

-- Eier eines Platzes ins Lager. Gibt die Anzahl zurueck.
local function emptyEggs(data: Types.PlayerData, entry: Types.IncubatorSlot): number
	local stock = data.island.eggStock
	local n = #entry.eggs
	for _, eggType in entry.eggs do
		stock[eggType] = (stock[eggType] or 0) + 1
	end
	table.clear(entry.eggs)
	return n
end

-- Ein Ei aus der Tabelle dieses Baerchis (gesperrte Eier -> freier
-- Vorgaenger, wie beim Legen).
local function rollEgg(data: Types.PlayerData, baerchi: Types.Baerchi): Types.EggType?
	local rolled = EggCalculator.rollEggType(baerchi)
	if not rolled then return nil end
	return EggTree.resolveLaid(data.eggTree, rolled)
end

-- Rechnet alle Plaetze nach. Gibt true zurueck, wenn sich etwas geaendert hat.
local function advance(data: Types.PlayerData, now: number, offline: boolean): boolean
	local island = data.island
	local incubator = island.incubator
	if not incubator then return false end
	local count = IncubatorRules.slotCountFor(data)
	local dirty = false

	for i = #incubator.slots, 1, -1 do
		local entry = incubator.slots[i]
		local baerchi = island.baerchis[entry.baerchiUid]
		-- Weg, ausgeruestet oder Platz nicht mehr da (Rebirth): Platz raeumen
		if not baerchi or island.equippedUid == entry.baerchiUid or entry.slot > count then
			emptyEggs(data, entry)
			table.remove(incubator.slots, i)
			dirty = true
			continue
		end
		local interval = IncubatorRules.breedSeconds(baerchi.rarity, incubator.level, offline)
		local due, nextMark = IncubatorRules.due(entry, interval, now)
		for _ = 1, due do
			local eggType = rollEgg(data, baerchi)
			if eggType then table.insert(entry.eggs, eggType) end
		end
		if due > 0 then dirty = true end
		entry.lastEggAt = nextMark
	end
	return dirty
end

--------------------------------------------------------------------------------
-- Einsetzen / Herausnehmen
--------------------------------------------------------------------------------

function IncubatorService.insert(player: Player, baerchiUid: string): boolean
	local data = usable(player, "RequestIncubatorStart", true)
	if not data then return false end

	local island = data.island
	if not island.baerchis[baerchiUid] then
		fail(player, "RequestIncubatorStart", Loc.msg("err.baerchi_not_found"))
		return false
	end
	if island.equippedUid == baerchiUid then
		fail(player, "RequestIncubatorStart", Loc.msg("err.incubator_equipped"))
		return false
	end
	local incubator = island.incubator
	if IncubatorRules.slotOf(incubator.slots, baerchiUid) then
		return true   -- sitzt schon drin (Doppelklick)
	end
	local index = IncubatorRules.firstFree(incubator.slots, IncubatorRules.slotCountFor(data))
	if not index then
		fail(player, "RequestIncubatorStart", Loc.msg("err.incubator_full"))
		return false
	end

	table.insert(incubator.slots, {
		slot       = index,
		baerchiUid = baerchiUid,
		lastEggAt  = os.time(),
		eggs       = {},
	})
	table.sort(incubator.slots, function(a, b) return a.slot < b.slot end)

	changed(player, index, "insert")
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)
	return true
end

function IncubatorService.remove(player: Player, index: number): boolean
	local data = usable(player, "RequestIncubatorRemove", true)
	if not data then return false end
	local incubator = data.island.incubator
	local entry, position = IncubatorRules.findSlot(incubator.slots, index)
	if not entry or not position then
		fail(player, "RequestIncubatorRemove", Loc.msg("err.incubator_empty"))
		return false
	end
	advance(data, os.time(), false)
	local eggs = emptyEggs(data, entry)
	local _, again = IncubatorRules.findSlot(incubator.slots, index)
	if again then table.remove(incubator.slots, again) end

	changed(player, index, "remove", eggs)
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)
	return true
end

--------------------------------------------------------------------------------
-- Abholen (alle wartenden Eier ins Lager)
--------------------------------------------------------------------------------

function IncubatorService.collectAll(player: Player): number
	local data = usable(player, "RequestIncubatorCollect", true)
	if not data then return 0 end
	advance(data, os.time(), false)
	local total = 0
	for _, entry in data.island.incubator.slots do
		total += emptyEggs(data, entry)
	end
	if total == 0 then
		fail(player, "RequestIncubatorCollect", Loc.msg("err.incubator_none_ready"))
		return 0
	end
	changed(player, 0, "collect", total)
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)
	return total
end

--------------------------------------------------------------------------------
-- Ausbauen (Geldsenke vor dem Rebirth, Paket 4.4)
--------------------------------------------------------------------------------

function IncubatorService.upgrade(player: Player): boolean
	local data = usable(player, "RequestUpgradeIncubator", true)
	if not data then return false end

	local incubator = data.island.incubator
	local target = incubator.level + 1
	local cost = IncubatorRules.upgradeCost(target)
	if not cost then
		fail(player, "RequestUpgradeIncubator", Loc.msg("err.incubator_max"))
		return false
	end
	if data.gummies < cost.gummies then
		fail(player, "RequestUpgradeIncubator", Loc.msg("err.not_enough_gummies", { need = cost.gummies, have = data.gummies }))
		return false
	end
	if data.goldGummies < cost.goldGummies then
		fail(player, "RequestUpgradeIncubator", Loc.msg("err.not_enough_gold_gummies", { need = cost.goldGummies, have = data.goldGummies }))
		return false
	end

	local ok, reason = EconomyService.spendGummies(player, cost.gummies)
	if not ok then
		fail(player, "RequestUpgradeIncubator", reason or Loc.msg("err.unknown"))
		return false
	end
	if cost.goldGummies > 0 then
		local okGold, reasonGold = EconomyService.spendGoldGummies(player, cost.goldGummies)
		if not okGold then
			-- Gummies zurueck: die Pruefung oben hat schon gesagt, dass es reicht,
			-- das hier ist nur das Netz fuer einen gleichzeitigen zweiten Abzug.
			EconomyService.awardGummiesFlat(player, cost.gummies)
			fail(player, "RequestUpgradeIncubator", reasonGold or Loc.msg("err.unknown"))
			return false
		end
	end

	-- Bis jetzt im alten Takt nachrechnen, danach gilt der neue.
	advance(data, os.time(), false)
	incubator.level = target
	changed(player, 0, "upgrade")
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)
	return true
end

--------------------------------------------------------------------------------
-- Debug (Studio): alle Plaetze sofort voll
--------------------------------------------------------------------------------

function IncubatorService.debugFill(player: Player)
	local data = PlayerService.getData(player)
	if not data then return end
	for _, entry in data.island.incubator.slots do
		entry.lastEggAt -= 24 * 3600
	end
	advance(data, os.time(), false)
	PlayerService.markDirty(player)
end

--------------------------------------------------------------------------------
-- Takt und Initialisierung
--------------------------------------------------------------------------------

local function tick()
	local now = os.time()
	for _, player in Players:GetPlayers() do
		local data = PlayerService.getData(player)
		if data and data.island.incubator and #data.island.incubator.slots > 0 then
			if advance(data, now, false) then
				PlayerService.markDirty(player)
			end
		end
	end
end

local function validIndex(index: any): boolean
	return typeof(index) == "number" and index == math.floor(index) and index >= 1 and index <= IncubatorConfig.MAX_SLOTS
end

function IncubatorService.init()
	RateLimiter.connect(Remotes.RequestIncubatorStart, "RequestIncubatorStart", function(player, baerchiUid: any)
		if typeof(baerchiUid) ~= "string" or #baerchiUid > 64 then return end
		IncubatorService.insert(player, baerchiUid)
	end)

	RateLimiter.connect(Remotes.RequestIncubatorRemove, "RequestIncubatorRemove", function(player, index: any)
		if not validIndex(index) then return end
		IncubatorService.remove(player, index)
	end)

	RateLimiter.connect(Remotes.RequestIncubatorCollect, "RequestIncubatorCollect", function(player)
		IncubatorService.collectAll(player)
	end)

	RateLimiter.connect(Remotes.RequestUpgradeIncubator, "RequestUpgradeIncubator", function(player)
		IncubatorService.upgrade(player)
	end)

	-- Offline-Brueten beim Laden (gebremst, gedeckelt durch STORE_PER_SLOT).
	PlayerService.onDataLoaded(function(_player, data)
		if not FeatureFlags.isOn("INCUBATOR") then return end
		advance(data, os.time(), true)
	end)

	print("[IncubatorService] Initialisiert | Plaetze max", IncubatorConfig.MAX_SLOTS)
end

function IncubatorService.start()
	if not FeatureFlags.isOn("INCUBATOR") then return end
	task.spawn(function()
		while true do
			task.wait(IncubatorConfig.TICK_SECONDS)
			tick()
		end
	end)
end

return IncubatorService
