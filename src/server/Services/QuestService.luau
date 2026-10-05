--!strict
-- QuestService.luau
-- ServerScriptService/Services/QuestService.luau
--
-- Einzige Zustaendigkeit:
--   - Quest-Belohnungen abholen lassen (Pruefung + Auszahlung)
--   - Den Tageswechsel der Tages-Quests durchfuehren
--   - Den Index fuehren: jede configId, die ein Spieler je besessen hat, in
--     data.discovered eintragen
--
-- Was dieser Service NICHT tut: Fortschritt mitzaehlen. Der wird jedes Mal aus
-- den Spielzaehlern berechnet (shared/Modules/QuestProgress) — kein anderer
-- Service muss Quests kennen. Der Fortschritt reist ueber PlayerDataUpdated
-- zum Client, dieser Service schickt nur die Belohnungs-Meldung.
--
-- Gummies zahlt ausschliesslich EconomyService aus (awardGummiesFlat: Quest-
-- Belohnungen sind fest und bekommen KEINEN Rebirth-Multiplikator, sonst
-- wuerden sie mit jedem Rebirth die Kette entwerten).

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types         = require(ReplicatedStorage.Network.Types)
local Remotes       = require(ReplicatedStorage.Network.Remotes)
local Loc           = require(ReplicatedStorage.Localization.Loc)
local QuestConfig   = require(ReplicatedStorage.Config.QuestConfig)
local QuestProgress = require(ReplicatedStorage.Modules.QuestProgress)

local PlayerService  = require(ServerScriptService.Services.PlayerService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local RateLimiter    = require(ServerScriptService.Util.RateLimiter)

local QuestService = {}

-- Wie oft geprueft wird, ob fuer wartende Spieler der Tag gewechselt hat.
local DAY_CHECK_INTERVAL = 60

local function fail(player: Player, reason: Types.LocMsg)
	Remotes.ActionFailed:FireClient(player, "RequestClaimQuest", reason)
end

--------------------------------------------------------------------------------
-- Tageswechsel
--------------------------------------------------------------------------------

-- Setzt die Tages-Quests zurueck, wenn der UTC-Tag ein anderer ist. Gibt true
-- zurueck, wenn sich etwas geaendert hat.
local function ensureDay(data: Types.PlayerData): boolean
	local today = QuestConfig.dayOf(os.time())
	if data.quests.day == today then
		return false
	end

	data.quests.day          = today
	data.quests.baseline     = QuestProgress.snapshot(data)
	data.quests.dailyClaimed = {}
	return true
end

--------------------------------------------------------------------------------
-- Index
--------------------------------------------------------------------------------

-- Traegt neue configIds ein. Gibt true zurueck, wenn etwas dazukam.
local function updateDiscovered(data: Types.PlayerData): boolean
	local changed = false
	for _, baerchi in data.island.baerchis do
		if not data.discovered[baerchi.configId] then
			data.discovered[baerchi.configId] = true
			changed = true
		end
	end
	return changed
end

-- Laeuft bei JEDER Datenaenderung (siehe PlayerService.onDataChanged) und darf
-- dort nicht selbst markDirty aufrufen — deshalb der Aufschub mit task.defer.
-- Er konvergiert: der zweite Durchlauf findet nichts Neues mehr.
local function onDataChanged(player: Player, data: Types.PlayerData)
	local changed = updateDiscovered(data)
	if ensureDay(data) then changed = true end

	if changed then
		task.defer(function()
			if player.Parent and PlayerService.getData(player) == data then
				PlayerService.markDirty(player)
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- Belohnung abholen
--------------------------------------------------------------------------------

function QuestService.claim(player: Player, kind: any, questId: any)
	local data = PlayerService.getData(player)
	if not data then return end

	-- Alles, was vom Client kommt, ist unbekannt.
	if (kind ~= "chain" and kind ~= "daily") or typeof(questId) ~= "string" then
		return
	end

	ensureDay(data)

	local def = QuestConfig.getById(questId)
	if not def then
		fail(player, Loc.msg("err.quest_unknown"))
		return
	end

	local isDaily = kind == "daily"

	if isDaily then
		local isDailyDef = false
		for _, d in QuestConfig.DAILY do
			if d.id == questId then isDailyDef = true end
		end
		if not isDailyDef then
			fail(player, Loc.msg("err.quest_unknown"))
			return
		end
		if data.quests.dailyClaimed[questId] then
			fail(player, Loc.msg("err.quest_already_claimed"))
			return
		end
	else
		-- Kette: nur die aktuelle Quest darf abgeholt werden, nie eine spaetere.
		local current = QuestConfig.CHAIN[data.quests.chainClaimed + 1]
		if not current or current.id ~= questId then
			fail(player, Loc.msg("err.quest_not_current"))
			return
		end
	end

	if not QuestProgress.isComplete(def, data, isDaily) then
		fail(player, Loc.msg("err.quest_not_done"))
		return
	end

	-- Zuerst als abgeholt markieren, dann auszahlen: so kann ein zweiter,
	-- gleichzeitiger Aufruf nichts doppelt bekommen.
	if isDaily then
		data.quests.dailyClaimed[questId] = true
	else
		data.quests.chainClaimed += 1
	end

	local paid = EconomyService.awardGummiesFlat(player, def.reward.gummies)

	local eggType = def.reward.eggType
	if eggType then
		data.island.eggStock[eggType] = (data.island.eggStock[eggType] or 0) + 1
	end

	-- GOLD_CHARMS_ONLY: einzige GoldGummies-Quelle (ohne Flag 0)
	local gold = QuestConfig.goldReward(def)
	local goldPaid = if gold > 0 then EconomyService.awardGoldGummies(player, gold) else 0

	local reward: Types.QuestReward = {
		questId = questId,
		gummies = paid,
		eggType = eggType,
		goldGummies = if goldPaid > 0 then goldPaid else nil,
	}
	Remotes.QuestRewardReceived:FireClient(player, reward)

	PlayerService.markDirty(player)
	PlayerService.saveNow(player)

	print("[QuestService]", player.Name, "holt", questId, "ab | +", paid, "Gummies |", goldPaid, "Gold", eggType or "")
end

--------------------------------------------------------------------------------
-- Start
--------------------------------------------------------------------------------

function QuestService.init()
	-- Vor dem ersten Sync: Tag setzen, damit der Client sofort den richtigen
	-- Stand sieht.
	PlayerService.onDataLoaded(function(_player, data)
		ensureDay(data)
		updateDiscovered(data)
	end)

	PlayerService.onDataChanged(onDataChanged)

	RateLimiter.connect(Remotes.RequestClaimQuest, "RequestClaimQuest", function(player, kind: any, questId: any)
		QuestService.claim(player, kind, questId)
	end)

	-- Wer nur im Spiel steht und nichts tut, loest keine Datenaenderung aus —
	-- ohne diese Schleife wuerden seine Tages-Quests erst bei der naechsten
	-- Aktion zurueckgesetzt.
	task.spawn(function()
		while true do
			task.wait(DAY_CHECK_INTERVAL)
			for _, player in Players:GetPlayers() do
				local data = PlayerService.getData(player)
				if data and ensureDay(data) then
					PlayerService.markDirty(player)
				end
			end
		end
	end)

	print("[QuestService] Initialisiert")
end

return QuestService
