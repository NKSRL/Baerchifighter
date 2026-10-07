--!strict
-- SpecialMilestoneService.luau
-- ServerScriptService/Services/SpecialMilestoneService.luau
--
-- Einzige Zustaendigkeit:
--   - Die besonderen Meilensteine (Sammel-Update 05.10., Paket 6.2) einmalig
--     pro Konto auszahlen, sobald sie erreicht sind — auch rueckwirkend.
--
-- Regel (fuer CONTEXT_BRIEFING): Ascensions-Eier haben genau zwei Quellen —
-- Rebirth-Meilensteine (RebirthService) und die besonderen Meilensteine
-- (EconomyConfig.SPECIAL_MILESTONES, hier; die Gesamt-Index-Belohnung zaehlt
-- dazu und wird im Index abgeholt). tools/check_consistency.py prueft das.
--
-- Wie TowerService die Tower-Meilensteine: Pruefung beim Join und bei jeder
-- Datenaenderung, gemerkt in data.specialClaimed. Der Beobachter aendert die
-- Daten nur im task.defer (nie synchron markDirty im Beobachter).

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types         = require(ReplicatedStorage.Network.Types)
local Remotes       = require(ReplicatedStorage.Network.Remotes)
local EconomyConfig = require(ReplicatedStorage.Config.EconomyConfig)

local PlayerService = require(ServerScriptService.Services.PlayerService)
local EggService    = require(ServerScriptService.Services.EggService)

local SpecialMilestoneService = {}

local _pending: { [Player]: boolean } = {}

local function reached(data: Types.PlayerData, m: EconomyConfig.SpecialMilestone): boolean
	if m.kind == "tower" then
		return ((data.towers.records or {})[m.tower or ""] or 0) >= (m.stage or math.huge)
	elseif m.kind == "stat" then
		return ((data.stats :: any)[m.stat or ""] or 0) >= (m.atLeast or math.huge)
	end
	return false
end

-- Offene, erreichte Meilensteine (rein lesend).
local function due(data: Types.PlayerData): { EconomyConfig.SpecialMilestone }
	local list = {}
	for _, m in EconomyConfig.SPECIAL_MILESTONES do
		if not data.specialClaimed[m.id] and reached(data, m) then
			table.insert(list, m)
		end
	end
	return list
end

local function payOut(player: Player, data: Types.PlayerData)
	for _, m in due(data) do
		data.specialClaimed[m.id] = true
		for _, entry in m.eggs do
			EggService.grantEggs(player, entry.eggType, entry.count)
		end
		local result: Types.SpecialMilestoneResult = { id = m.id, eggs = m.eggs }
		Remotes.SpecialMilestoneReceived:FireClient(player, result)
		print("[SpecialMilestoneService]", player.Name, "| besonderer Meilenstein:", m.id)
	end
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)
end

local function check(player: Player, data: Types.PlayerData)
	if _pending[player] or #due(data) == 0 then return end
	_pending[player] = true
	task.defer(function()
		_pending[player] = nil
		if player.Parent and PlayerService.getData(player) == data then
			payOut(player, data)
		end
	end)
end

function SpecialMilestoneService.init()
	PlayerService.onDataChanged(check)
	PlayerService.onPlayerReady(check)
	print("[SpecialMilestoneService] Initialisiert |", #EconomyConfig.SPECIAL_MILESTONES, "Meilensteine")
end

return SpecialMilestoneService
