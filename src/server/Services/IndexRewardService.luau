--!strict
-- IndexRewardService.luau
-- ServerScriptService/Services/IndexRewardService.luau
--
-- Einzige Zustaendigkeit:
--   - Index-Belohnungen (Sammel-Update 05.10., Paket 7): pruefen, ob eine
--     Kollektion fertig ist, und sie beim Abholen auszahlen.
--
-- Welche Kollektionen es gibt und was sie bringen, steht in
-- Config/IndexRewardConfig. Abgeholt wird bewusst von Hand (kein
-- automatisches Auszahlen) und auch rueckwirkend: wer eine Reihe schon
-- komplett hat, holt sie sofort ab.
--
-- Auszahlung nur ueber die bestehenden Wege: Gummies und GoldGummies ueber
-- EconomyService, Eier ueber EggService.grantEggs, Blaupausen ueber
-- EggTreeService.grantBlueprint. Inkubator-Plaetze werden nicht gespeichert,
-- sondern aus indexClaimed abgeleitet (IndexRewardConfig.incubatorSlots).
--
-- Beobachter an onDataChanged: meldet einmal pro Sitzung, wenn eine neue
-- Belohnung abholbar wird (Hinweis), mit task.defer und ohne markDirty —
-- er aendert nichts am Spielstand.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players             = game:GetService("Players")

local Types             = require(ReplicatedStorage.Network.Types)
local Remotes           = require(ReplicatedStorage.Network.Remotes)
local Loc               = require(ReplicatedStorage.Localization.Loc)
local FeatureFlags      = require(ReplicatedStorage.Config.FeatureFlags)
local IndexRewardConfig = require(ReplicatedStorage.Config.IndexRewardConfig)

local PlayerService  = require(ServerScriptService.Services.PlayerService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local EggService     = require(ServerScriptService.Services.EggService)
local EggTreeService = require(ServerScriptService.Services.EggTreeService)
local RateLimiter    = require(ServerScriptService.Util.RateLimiter)

local IndexRewardService = {}

-- Was dieser Spieler in dieser Sitzung schon als abholbar gemeldet bekam.
local _announced: { [Player]: { [string]: boolean } } = {}

local function fail(player: Player, reason: Types.LocMsg)
	Remotes.ActionFailed:FireClient(player, "RequestClaimIndexReward", reason)
end

function IndexRewardService.claim(player: Player, rewardId: string): Types.IndexRewardResult?
	if not FeatureFlags.isOn("INDEX_REWARDS") then return nil end
	local data = PlayerService.getData(player)
	if not data then return nil end

	local entry = IndexRewardConfig.get(rewardId)
	if not entry then
		fail(player, Loc.msg("err.index_reward_unknown"))
		return nil
	end
	if data.indexClaimed[rewardId] then
		fail(player, Loc.msg("err.index_reward_claimed"))
		return nil
	end
	if not IndexRewardConfig.isComplete(entry, data.discovered) then
		local have, total = IndexRewardConfig.progress(entry, data.discovered)
		fail(player, Loc.msg("err.index_reward_incomplete", { have = have, total = total }))
		return nil
	end

	-- Erst als abgeholt markieren, dann auszahlen: ein zweiter Klick im
	-- selben Moment findet den Haken schon gesetzt.
	data.indexClaimed[rewardId] = true

	local reward = entry.reward
	local result: Types.IndexRewardResult = {
		rewardId       = rewardId,
		gummies        = 0,
		goldGummies    = 0,
		eggType        = reward.eggType,
		eggs           = 0,
		blueprints     = reward.blueprints,
		incubatorSlots = reward.incubatorSlots,
	}
	if reward.gummies > 0 then
		result.gummies = EconomyService.awardGummies(player, reward.gummies)
	end
	if reward.goldGummies > 0 then
		result.goldGummies = EconomyService.awardGoldGummies(player, reward.goldGummies)
	end
	if reward.eggType and reward.eggs > 0 and EggService.grantEggs(player, reward.eggType, reward.eggs) then
		result.eggs = reward.eggs
	end
	if reward.blueprints > 0 then
		EggTreeService.grantBlueprint(player, data, reward.blueprints)
	end

	Remotes.IndexRewardReceived:FireClient(player, result)
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)
	print("[IndexRewardService]", player.Name, "| abgeholt:", rewardId)
	return result
end

local function onDataChanged(player: Player, data: Types.PlayerData)
	if not FeatureFlags.isOn("INDEX_REWARDS") then return end
	local seen = _announced[player]
	if not seen then
		-- Erster Stand der Sitzung: was schon abholbar ist, zeigt das "!" am
		-- Index; ein Extra-Hinweis kommt nur fuer NEU fertige Reihen.
		seen = {}
		for _, id in IndexRewardConfig.claimable(data.discovered, data.indexClaimed) do
			seen[id] = true
		end
		_announced[player] = seen
		return
	end
	local fresh: { string } = {}
	for _, id in IndexRewardConfig.claimable(data.discovered, data.indexClaimed) do
		if not seen[id] then
			seen[id] = true
			table.insert(fresh, id)
		end
	end
	if #fresh > 0 then
		task.defer(function()
			if player.Parent then
				Remotes.EventNotice:FireClient(player, Loc.msg("msg.index_reward_ready"), "good")
			end
		end)
	end
end

function IndexRewardService.init()
	RateLimiter.connect(Remotes.RequestClaimIndexReward, "RequestClaimIndexReward", function(player, rewardId: any)
		if typeof(rewardId) ~= "string" or #rewardId > 64 then return end
		IndexRewardService.claim(player, rewardId)
	end)
	PlayerService.onDataChanged(onDataChanged)
	Players.PlayerRemoving:Connect(function(player)
		_announced[player] = nil
	end)
	print("[IndexRewardService] Initialisiert |", #IndexRewardConfig.ENTRIES, "Belohnungen")
end

return IndexRewardService
