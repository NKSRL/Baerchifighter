--!strict
-- CombatRating.luau
-- ReplicatedStorage/Modules/CombatRating.luau
--
-- Einzige Zustaendigkeit:
--   - Eine einzige Zahl pro Baerchi ("Kampfwert"), aus denselben effektiven
--     Werten, mit denen CombatCalculator kaempft
--
-- Kontext: HBB Paket 4. Ein Kind vergleicht eine grosse Zahl, nicht fuenf
-- Werte. Bewusst KEIN zweites Stat-Modell: Level, Promotion, Stat-Stufen,
-- Charms und Mutation stecken schon in CombatCalculator.getEffectiveStats;
-- hier wird nur verdichtet.
--
-- Name bewusst nicht "Power": PWR ist schon ein Stat.
--
-- Formel: Wurzel aus (Ausdauer x Schlagkraft) — Ausdauer = maxHp,
-- Schlagkraft = ATK x SPD x (1 + PWR). Steigt in jedem einzelnen Stat
-- streng monoton. Ob die Rangfolge zu den erreichbaren Stages passt, prueft
-- tools/luau-tests/combat_rating.test.lua mit dem echten Kampfmodell.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types            = require(ReplicatedStorage.Network.Types)
local BaerchiConfig    = require(ReplicatedStorage.Config.BaerchiConfig)
local CombatCalculator = require(ReplicatedStorage.Modules.CombatCalculator)

local CombatRating = {}

-- Skaliert auf griffige Zahlen (Common Lv 10 ≈ 870)
CombatRating.SCALE = 10

export type Stats = { maxHp: number, atk: number, spd: number, pwr: number }

function CombatRating.fromStats(stats: Stats): number
	local stamina = math.max(0, stats.maxHp)
	local punch = math.max(0, stats.atk) * math.max(0, stats.spd) * (1 + math.max(0, stats.pwr))
	return math.floor(math.sqrt(stamina * punch) * CombatRating.SCALE + 0.5)
end

function CombatRating.of(baerchi: Types.Baerchi): number
	local def = BaerchiConfig.getById(baerchi.configId)
	if not def then return 0 end
	return CombatRating.fromStats(CombatCalculator.getEffectiveStats(baerchi, def.baseStats))
end

-- Gekuerzte Anzeige: 870, 1,2K, 34K, 5,6M (Dezimalzeichen liefert der Aufrufer
-- ueber Loc, hier nur die Form)
function CombatRating.short(value: number): (number, string)
	if value >= 1e9 then return value / 1e9, "B" end
	if value >= 1e6 then return value / 1e6, "M" end
	if value >= 1e3 then return value / 1e3, "K" end
	return value, ""
end

return CombatRating
