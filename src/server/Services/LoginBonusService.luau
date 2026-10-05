--!strict
-- LoginBonusService.luau
-- ServerScriptService/Services/LoginBonusService.luau
--
-- Einzige Zustaendigkeit:
--   - Den taeglichen Login-Bonus (v15) abholen lassen: Tag pruefen, Stand
--     fortschreiben, Belohnung ueber die zustaendigen Services auszahlen.
--
-- Die Regeln (UTC-Tag, Gnadenfrist, Reset, Doppelklick) stehen rein und
-- getestet in Modules/LoginBonusCalc, die Zahlen in Config/LoginBonusConfig.
-- Ausgezahlt wird nur ueber EconomyService (Gummies MIT Rebirth-Multiplikator,
-- GoldGummies), EggService.grantEggs (Eier) und EggTreeService.grantBlueprint.
--
-- Der Client sieht den Stand als Types.DailyView im PlayerDataUpdate
-- (PlayerService ruft buildView) und oeffnet beim Join selbst das Fenster.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types            = require(ReplicatedStorage.Network.Types)
local Remotes          = require(ReplicatedStorage.Network.Remotes)
local Loc              = require(ReplicatedStorage.Localization.Loc)
local LoginBonusConfig = require(ReplicatedStorage.Config.LoginBonusConfig)
local LoginBonusCalc   = require(ReplicatedStorage.Modules.LoginBonusCalc)
local EggTree          = require(ReplicatedStorage.Modules.EggTree)

local PlayerService  = require(ServerScriptService.Services.PlayerService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local EggService     = require(ServerScriptService.Services.EggService)
local EggTreeService = require(ServerScriptService.Services.EggTreeService)
local RateLimiter    = require(ServerScriptService.Util.RateLimiter)

local LoginBonusService = {}

-- Nur Studio/Debug ("dailyshift"): Zeitversatz in Sekunden, um Tageswechsel
-- ohne Warten zu testen. Im Live-Spiel immer 0.
local _timeOffset = 0

local function now(): number
	return os.time() + _timeOffset
end

function LoginBonusService.buildView(data: Types.PlayerData): Types.DailyView
	return LoginBonusCalc.buildView(data.daily, now())
end

function LoginBonusService.claim(player: Player)
	local data = PlayerService.getData(player)
	if not data then return end

	local newState, day = LoginBonusCalc.claim(data.daily, now())
	if not newState then
		Remotes.ActionFailed:FireClient(player, "RequestClaimDailyBonus", Loc.msg("err.daily_claimed"))
		return
	end

	-- Erst den Stand fortschreiben, dann auszahlen: ein zweiter Klick, der
	-- waehrend der Auszahlung ankommt, findet "heute schon abgeholt" vor.
	data.daily = newState

	local reward = LoginBonusConfig.getDay(day)
	local result: Types.DailyBonusResult = {
		day = day, gummies = 0, goldGummies = 0, eggType = nil, eggs = 0, blueprint = false,
	}

	if (reward.gummies or 0) > 0 then
		result.gummies = EconomyService.awardGummies(player, reward.gummies :: number)
	end
	if (reward.goldGummies or 0) > 0 then
		result.goldGummies = EconomyService.awardGoldGummies(player, reward.goldGummies :: number)
	end
	if reward.eggType and (reward.eggs or 0) > 0 then
		if EggService.grantEggs(player, reward.eggType, reward.eggs :: number) then
			result.eggType = reward.eggType
			result.eggs = reward.eggs :: number
		end
	end
	if (reward.highestEgg or 0) > 0 then
		local eggType = EggTree.highestUnlocked(data.eggTree)
		if EggService.grantEggs(player, eggType, reward.highestEgg :: number) then
			result.eggType = eggType
			result.eggs += reward.highestEgg :: number
		end
	end
	if (reward.blueprintChance or 0) > 0 and math.random() < (reward.blueprintChance :: number) then
		EggTreeService.grantBlueprint(player, data, 1)
		result.blueprint = true
	end

	PlayerService.markDirty(player)
	PlayerService.saveNow(player)
	Remotes.DailyBonusReceived:FireClient(player, result)

	print("[LoginBonusService]", player.Name, "| Tag", day, "| Gummies:", result.gummies,
		"| Gold:", result.goldGummies, "| Eier:", result.eggs, "| Blaupause:", result.blueprint)
end

-- Debug ("dailyshift <tage>"): Zeitversatz um `days` Tage erhoehen (0 = zurueck
-- auf die echte Zeit) und den neuen Stand melden.
function LoginBonusService.debugShift(player: Player, days: number): { [string]: any }
	if days == 0 then
		_timeOffset = 0
	else
		_timeOffset += days * LoginBonusConfig.SECONDS_PER_DAY
	end
	local data = PlayerService.getData(player)
	if data then PlayerService.markDirty(player) end
	return {
		offsetTage = _timeOffset / LoginBonusConfig.SECONDS_PER_DAY,
		utcTag = LoginBonusCalc.utcDay(now()),
		ansicht = if data then LoginBonusService.buildView(data) else nil,
		stand = if data then data.daily else nil,
	}
end

function LoginBonusService.init()
	RateLimiter.connect(Remotes.RequestClaimDailyBonus, "RequestClaimDailyBonus", function(player)
		LoginBonusService.claim(player)
	end)

	PlayerService.setDailyViewProvider(LoginBonusService.buildView)

	print("[LoginBonusService] Initialisiert |", LoginBonusConfig.CYCLE_DAYS, "Tage-Zyklus")
end

return LoginBonusService
