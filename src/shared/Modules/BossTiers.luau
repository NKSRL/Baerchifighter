--!strict
-- BossTiers.luau
-- ReplicatedStorage/Modules/BossTiers.luau
--
-- Einzige Zustaendigkeit:
--   - Die Belohnungsstufe (0–4) eines Boss-Teilnehmers bestimmen
--     (reine Funktion, keine Roblox-Dienste)
--
-- Kontext: HBB Paket 7. Jeder, der am Boss teilnimmt, bekommt etwas, schon
-- ab 1 Schaden. Gemessen wird der Schaden RELATIV ZUM EIGENEN POTENZIAL
-- (DPS des eigenen Baerchis x Zeit am Boss), nicht als Anteil am
-- Gesamtschaden: so geht ein schwacher Baerchi in einem starken Team nicht
-- leer aus. Die bisherige Belohnung nach Anteil (Top 3, Sieg) bleibt
-- zusaetzlich bestehen (WaspQueenEvent).
--
-- Regeln (Schwellen in EventConfig.BOSS_TIERS, hier als Parameter):
--   Stufe 0: kein Schaden
--   Stufe 1: Schaden >= 1
--   Stufe 2/3/4: Schaden >= T2/T3/T4 x Potenzial
--   Gemeinsamer Sieg: jede Stufe >= 1 steigt um 1 (hoechstens 4)
--   Nicht aktiv in den letzten 60 s: hoechstens Stufe 1 (gilt NACH dem Sieg-Bonus)
--
-- Keine requires: laeuft unveraendert im Luau-Test
-- (tools/luau-tests/boss_tiers.test.lua).

export type Thresholds = { T2: number, T3: number, T4: number }

local BossTiers = {}

BossTiers.MAX_TIER = 4
BossTiers.DEFAULT = { T2 = 0.05, T3 = 0.25, T4 = 0.60 } :: Thresholds

function BossTiers.tierFor(damage: number, potential: number, activeRecently: boolean, won: boolean, thresholds: Thresholds?): number
	if damage < 1 then
		return 0
	end
	local t = thresholds or BossTiers.DEFAULT
	local ratio = if potential > 0 then damage / potential else 1

	local tier = 1
	if ratio >= t.T4 then
		tier = 4
	elseif ratio >= t.T3 then
		tier = 3
	elseif ratio >= t.T2 then
		tier = 2
	end

	if won then
		tier = math.min(BossTiers.MAX_TIER, tier + 1)
	end
	if not activeRecently then
		tier = math.min(tier, 1)
	end
	return tier
end

return BossTiers
