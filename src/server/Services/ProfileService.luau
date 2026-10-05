--!strict
-- ProfileService.luau
-- ServerScriptService/Services/ProfileService.luau
--
-- Einzige Zustaendigkeit:
--   - Die Profilkarte eines Spielers fuer den Inspektor bauen (v15): Klick auf
--     einen anderen Spieler (Charakter oder Plot-Schild) -> GetPlayerProfile.
--
-- Nur Spieler auf DIESEM Server, nur aus den Daten im Speicher, rate-limited.
-- Es gehen nie rohe PlayerData an einen fremden Client — die Karte enthaelt
-- genau die Felder aus Types.PlayerProfileCard (kein Gummy-Stand, keine uids,
-- keine Statistiken).

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types            = require(ReplicatedStorage.Network.Types)
local Remotes          = require(ReplicatedStorage.Network.Remotes)
local BaerchiConfig    = require(ReplicatedStorage.Config.BaerchiConfig)
local TowerConfig      = require(ReplicatedStorage.Config.TowerConfig)
local CombatCalculator = require(ReplicatedStorage.Modules.CombatCalculator)

local PlayerService = require(ServerScriptService.Services.PlayerService)
local RateLimiter   = require(ServerScriptService.Util.RateLimiter)

local ProfileService = {}

-- Wie viele Baerchis die Karte als "Top" zeigt.
local TOP_COUNT = 3

local _indexTotal: number? = nil
local function indexTotal(): number
	if _indexTotal then return _indexTotal end
	local n = 0
	for _ in BaerchiConfig.data do n += 1 end
	_indexTotal = n
	return n
end

-- Grobe Staerke fuer die Sortierung: geometrisches Mittel aus HP, ATK und SPD
-- (dieselben Kampfwerte, die der Kampf sieht).
local function describe(baerchi: Types.Baerchi): Types.ProfileBaerchi?
	local def = BaerchiConfig.getById(baerchi.configId)
	if not def then return nil end
	local stats = CombatCalculator.getEffectiveStats(baerchi, def.baseStats)
	return {
		configId  = baerchi.configId,
		rarity    = baerchi.rarity,
		mutation  = baerchi.mutation,
		level     = baerchi.level,
		promotion = baerchi.promotionLevel or 0,
		power     = math.floor((math.max(1, stats.maxHp) * math.max(1, stats.atk) * math.max(0.1, stats.spd)) ^ (1 / 3)),
	}
end

function ProfileService.buildCard(target: Player): Types.PlayerProfileCard?
	local data = PlayerService.getData(target)
	if not data then return nil end

	local all: { Types.ProfileBaerchi } = {}
	local equipped: Types.ProfileBaerchi? = nil
	for uid, baerchi in data.island.baerchis do
		local entry = describe(baerchi)
		if entry then
			table.insert(all, entry)
			if uid == data.island.equippedUid then
				equipped = entry
			end
		end
	end
	table.sort(all, function(a, b) return a.power > b.power end)
	local top: { Types.ProfileBaerchi } = {}
	for i = 1, math.min(TOP_COUNT, #all) do
		table.insert(top, all[i])
	end

	local towerId, record = TowerConfig.bestRecord(data.towers)
	local indexCount = 0
	for _ in data.discovered do indexCount += 1 end

	return {
		userId       = target.UserId,
		name         = target.DisplayName,
		equipped     = equipped,
		highestTower = towerId,
		towerRecord  = record,
		rebirths     = data.rebirthCount,
		indexCount   = indexCount,
		indexTotal   = indexTotal(),
		top          = top,
	}
end

function ProfileService.init()
	RateLimiter.connectFunction(Remotes.GetPlayerProfile, "GetPlayerProfile", function(_player, userId: any)
		if typeof(userId) ~= "number" then return nil end
		local target = Players:GetPlayerByUserId(userId)
		if not target then return nil end   -- nur Spieler auf diesem Server
		return ProfileService.buildCard(target)
	end)

	print("[ProfileService] Initialisiert")
end

return ProfileService
