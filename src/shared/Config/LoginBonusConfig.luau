--!strict
-- LoginBonusConfig.luau
-- ReplicatedStorage/Config/LoginBonusConfig.luau
--
-- Einzige Zustaendigkeit:
--   - Die Zahlen des taeglichen Login-Bonus (v15): 7-Tage-Zyklus nach UTC-Tag,
--     Belohnung je Tag, Gnadenfrist.
--
-- Die Regeln (welcher Tag ist dran, darf heute abgeholt werden) rechnet
-- Modules/LoginBonusCalc — rein und testbar (tools/luau-tests/login_bonus.test.lua).
-- Ausgezahlt wird in LoginBonusService ueber EconomyService (Gummies MIT
-- Rebirth-Multiplikator, damit der Bonus auch nach vielen Rebirths noch zaehlt),
-- EggService (Eier) und EggTreeService (Blaupause).
--
-- ANNAHMEN (Startwerte, im Bericht gelistet):
--   * Tag 1-6 steigen Gummies, GoldGummies und Basis-Eier.
--   * Tag 7: das hoechste freie Ei im Ei-Baum + 25 % Chance auf eine Blaupause.
--   * Ein verpasster Tag wird verziehen (Gnadenfrist): wer am uebernaechsten
--     UTC-Tag abholt, macht mit dem naechsten Tag weiter. Wer zwei oder mehr
--     Tage verpasst, faengt wieder bei Tag 1 an.

local Types = require(script.Parent.Parent.Network.Types)

local LoginBonusConfig = {}

export type DayReward = {
	gummies     : number?,                               -- Basis (x rebirthMult)
	goldGummies : number?,
	eggType     : Types.EggType?,                        -- feste Sorte
	eggs        : number?,                               -- Anzahl dieser Sorte
	highestEgg  : number?,                               -- Anzahl "hoechstes freies Ei"
	blueprintChance : number?,                           -- 0..1
}

LoginBonusConfig.CYCLE_DAYS = 7

-- Wie viele UTC-Tage nach der letzten Abholung die Serie noch weiterlaeuft:
-- 1 = gestern abgeholt (normal), 2 = einen Tag verpasst (Gnadenfrist, "48 h").
LoginBonusConfig.GRACE_DAYS = 2

LoginBonusConfig.SECONDS_PER_DAY = 86400

LoginBonusConfig.DAYS = {
	[1] = { gummies = 500 },
	[2] = { gummies = 1_500, goldGummies = 5 },
	[3] = { gummies = 3_000, eggType = "BasicEgg", eggs = 3 },
	[4] = { gummies = 6_000, goldGummies = 15 },
	[5] = { goldGummies = 25, eggType = "BasicEgg", eggs = 5 },
	[6] = { gummies = 15_000, goldGummies = 40 },
	[7] = { goldGummies = 60, highestEgg = 1, blueprintChance = 0.25 },
} :: { [number]: DayReward }

function LoginBonusConfig.getDay(day: number): DayReward
	return LoginBonusConfig.DAYS[math.clamp(math.floor(day), 1, LoginBonusConfig.CYCLE_DAYS)]
end

return LoginBonusConfig
