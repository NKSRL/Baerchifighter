--!strict
-- QuestConfig.luau
-- ReplicatedStorage/Config/QuestConfig.luau
--
-- Einzige Zustaendigkeit:
--   - ALLE Zahlen und Definitionen der Quests: die Einsteiger-Kette, die
--     Tages-Quests, ihre Ziele und Belohnungen
--
-- Texte stehen NICHT hier, sondern in den Sprachdateien unter
-- "quest.<id>.title" (siehe Localization). Hier stehen nur ids und Zahlen.
--
-- ============================================================
-- WARUM EINE KETTE UND TAGES-QUESTS
-- ============================================================
-- Die Kette ist das Tutorial: jeder Schritt zeigt dem Spieler die naechste
-- Sache, die das Spiel anbietet, in der Reihenfolge, in der sie Sinn ergibt
-- (Ei oeffnen -> kaempfen -> Gebaeude ausbauen -> fusionieren -> Index fuellen).
-- Es ist immer genau EINE Quest aktiv, damit keine Liste zu lesen ist.
-- Die Tages-Quests geben danach einen Grund, wiederzukommen.
--
-- Fortschritt wird nirgends mitgezaehlt, sondern aus den Spielzaehlern
-- abgeleitet (siehe Modules/QuestProgress). Neue Quests brauchen deshalb nur
-- einen Eintrag hier, keinen Eingriff in andere Services.

local Types = require(script.Parent.Parent.Network.Types)
local FeatureFlags = require(script.Parent.FeatureFlags)

-- Welche Groesse eine Quest misst. Gesamtwerte (Kette) lesen den Zaehler
-- direkt, Tages-Quests ziehen den Stand zu Tagesbeginn ab.
export type Metric =
	"hatched"        -- geoeffnete Eier
	| "fightsWon"    -- gewonnene Kaempfe
	| "gummiesEarned"-- verdiente Gummies
	| "fusions"      -- Fusionen
	| "baerchiCount" -- Baerchis im Besitz (Zustand, kein Zaehler)
	| "discovered"   -- Index-Eintraege
	| "buildingLevel"-- hoechstes Gebaeude-Level
	| "towerStage"   -- v15: beste geschaffte Stage in irgendeinem Tower (ersetzt "pitLevel")

export type Reward = {
	gummies : number,
	eggType : Types.EggType?,   -- optional: ein Ei dazu ("gelegentlich")
	goldGummies : number?,      -- nur mit GOLD_CHARMS_ONLY ausgezahlt (goldReward)
}

export type QuestDef = {
	id     : string,
	metric : Metric,
	target : number,
	reward : Reward,
}

-- Die Einsteiger-Kette, in Reihenfolge.
local CHAIN: { QuestDef } = {
	{ id = "c_hatch1",    metric = "hatched",       target = 1,  reward = { gummies = 50  } },
	{ id = "c_pets3",     metric = "baerchiCount",  target = 3,  reward = { gummies = 100, eggType = "BasicEgg" } },
	{ id = "c_fight1",    metric = "fightsWon",     target = 1,  reward = { gummies = 100 } },
	{ id = "c_fight5",    metric = "fightsWon",     target = 5,  reward = { gummies = 200, eggType = "BasicEgg" } },
	{ id = "c_upgrade",   metric = "buildingLevel", target = 2,  reward = { gummies = 250 } },
	{ id = "c_hatch5",    metric = "hatched",       target = 5,  reward = { gummies = 300, eggType = "SugarEgg" } },
	{ id = "c_discover5", metric = "discovered",    target = 5,  reward = { gummies = 400 } },
	{ id = "c_fuse1",     metric = "fusions",       target = 1,  reward = { gummies = 500, eggType = "SugarEgg" } },
	-- v15: ersetzt "c_pit2" (PIT-Level 2) an derselben Stelle der Kette — der
	-- Kettenstand zaehlt Positionen, abgeholte Quests bleiben also abgeholt.
	{ id = "c_tower10",   metric = "towerStage",    target = 10, reward = { gummies = 600 } },
	{ id = "c_discover8", metric = "discovered",    target = 8,  reward = { gummies = 800, eggType = "GoldenEgg" } },
	{ id = "c_fight25",   metric = "fightsWon",     target = 25, reward = { gummies = 1000 } },
	{ id = "c_discover10",metric = "discovered",    target = 10, reward = { gummies = 1500, eggType = "CrystalEgg" } },
}

-- Tages-Quests: Fortschritt = Zuwachs seit Tagesbeginn.
-- GOLD_CHARMS_ONLY: die Tages-Quests sind die einzige GoldGummies-Quelle.
-- Je Quest genau ein Charm-Wurf (CharmConfig.ROLL_COST_GOLD_GUMMIES = 25),
-- also 3 Wuerfe pro Tag. Wer den Preis aendert, aendert diese Zahl mit.
local DAILY_GOLD = 25
local DAILY: { QuestDef } = {
	{ id = "d_hatch3",  metric = "hatched",       target = 3,    reward = { gummies = 150, goldGummies = DAILY_GOLD } },
	{ id = "d_fight8",  metric = "fightsWon",     target = 8,    reward = { gummies = 250, goldGummies = DAILY_GOLD } },
	{ id = "d_earn",    metric = "gummiesEarned", target = 1500, reward = { gummies = 100, eggType = "BasicEgg", goldGummies = DAILY_GOLD } },
}

local SECONDS_PER_DAY = 86400

-- HBB Paket 2: Icon je Messgroesse (Namen aus UI/Icons). Der Quest-Tracker
-- zeigt Icon + Zaehler statt Text; der Volltext kommt erst beim Antippen.
-- Pro Messgroesse statt pro Quest: so braucht eine neue Quest kein Icon.
local METRIC_ICON: { [string]: string } = {
	hatched       = "egg",
	fightsWon     = "swords",
	gummiesEarned = "gummy",
	fusions       = "bear",
	baerchiCount  = "bear",
	discovered    = "scroll",
	buildingLevel = "honey",
	towerStage    = "trophy",
}

local byId: { [string]: QuestDef } = {}
for _, def in CHAIN do byId[def.id] = def end
for _, def in DAILY do byId[def.id] = def end

-- Tagesnummer (UTC). Ein Tageswechsel ist fuer alle Spieler derselbe Moment.
local function dayOf(unixTime: number): number
	return math.floor(unixTime / SECONDS_PER_DAY)
end

return {
	CHAIN = CHAIN,
	DAILY = DAILY,
	METRIC_ICON = METRIC_ICON,
	SECONDS_PER_DAY = SECONDS_PER_DAY,

	getById = function(id: string): QuestDef?
		return byId[id]
	end,

	dayOf = dayOf,

	-- GoldGummies, die diese Quest wirklich auszahlt (0 ohne GOLD_CHARMS_ONLY).
	-- Server (Auszahlung) und Client (Belohnungstext) fragen nur hier.
	goldReward = function(def: QuestDef): number
		if not FeatureFlags.isOn("GOLD_CHARMS_ONLY") then return 0 end
		return def.reward.goldGummies or 0
	end,

	-- Sekunden bis zum naechsten Tageswechsel.
	secondsUntilReset = function(unixTime: number): number
		return SECONDS_PER_DAY - (unixTime % SECONDS_PER_DAY)
	end,
}
