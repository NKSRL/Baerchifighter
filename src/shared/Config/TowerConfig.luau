--!strict
-- TowerConfig.luau
-- ReplicatedStorage/Config/TowerConfig.luau
--
-- Einzige Zustaendigkeit:
--   - Alle Zahlen des Tower-Systems (v15): welche Tower es gibt, wie stark ihre
--     Gegner sind, was eine Stage bringt, wie weit ein Rebirth die Tower oeffnet
--     (Deckel), welche Meilensteine es gibt, und wie alte PIT-Staende
--     umgerechnet werden.
--
-- Server (TowerService, CombatService) und Client (CombatPanel,
-- PitResumeDialog, PetBar) rechnen mit denselben Funktionen — Anzeige und
-- Abrechnung koennen nicht auseinanderlaufen.
--
-- ============================================================
-- DIE AEQUIVALENZ-STAGE
-- ============================================================
-- Jede Stage eines Towers hat eine Aequivalenz-Stage: die Stage von Tower I
-- mit derselben Gegnerstaerke (CombatConfig.getEnemyStatsForEquivalent).
--
--   equivalent(tower, stage) = startEquivalent + (stage - 1) * equivalentPerStage
--
-- Tower I: Start 1, je Stage 1 — also genau der alte PIT 1 ("Level N schafft
-- etwa N Stages" bleibt fuer Anfaenger wie gehabt). Die hoeheren Tower fangen
-- weiter oben an (Stage 1 von II ≈ Stage 25 von I) und wachsen LANGSAMER pro
-- Stage: so passen 45/60/100 Stages in den Bereich, den Baerchis mit Level 50,
-- Promotion, Charms und Stat-Stufen ueberhaupt erreichen. Die Zahlen sind mit
-- tools/sim/tower_calibration.lua gemessen (Tabelle im Bericht
-- TOWER_GEBAEUDE_ANGEBEN_UMGESETZT).
--
-- ============================================================
-- DER DECKEL PRO REBIRTH (weich)
-- ============================================================
-- Jeder Rebirth oeffnet ein Stage-Fenster (STAGE_CAP_BY_REBIRTH). Kaempfen darf
-- man darueber hinaus, aber Stage-Gummies, Meilensteine und Rekorde zaehlen nur
-- bis zum Deckel. Wer ihn erreicht, bekommt den Hinweis "mit Rebirth geht es
-- weiter". Tower N+1 laesst sich waehlen, sobald der Deckel ihn oeffnet; aeltere
-- bleiben waehlbar (dort gilt die volle Stage-Zahl als Deckel).

local Types        = require(script.Parent.Parent.Network.Types)
local FeatureFlags = require(script.Parent.FeatureFlags)
local CombatConfig = require(script.Parent.CombatConfig)

local TowerConfig = {}

--------------------------------------------------------------------------------
-- Die vier Tower
--------------------------------------------------------------------------------

export type TowerDef = {
	id                : Types.TowerId,
	index             : number,     -- 1..4, fuer Sortierung und Bestenliste
	stages            : number,
	startEquivalent   : number,     -- Aequivalenz-Stage von Stage 1
	equivalentPerStage: number,     -- Zuwachs der Aequivalenz je Stage

	-- Faktor auf die Stage-Gummies (REWARD_ANCHORS) — 1 = wie jeder Tower
	-- bei gleicher Gegnerstaerke.
	rewardFactor : number,

	-- GoldGummies pro Lauf: je angefangene 5 geschaffte Stages (bis zum Deckel).
	goldPerFive : number,

	look      : string,   -- Look-Id des Turms (MapConfig.TOWER_LOOKS)
	color     : Color3,   -- Akzentfarbe (Karten im UI, Abzeichen)
	numeral   : string,   -- Kurzzeichen ("I", "II", "III", "F") fuer Schild/Abzeichen
}

-- ANNAHMEN (Startwerte, per Simulation kalibriert, im Bericht gelistet):
--   * Aequivalenz: II startet bei 25, III bei 55, Final bei 82 — die Wachstums-
--     Stufen (1.0 / 0.95 / 0.6 / 0.5) sind so gewaehlt, dass ein Level-50-
--     Baerchi mit Maximal-Ausbau Tower I locker schafft, Tower III mit Muehe
--     (Legendaer/Mythisch ~45-60) und Final nur eine hohe Rarity (~70-100).
--   * Belohnung: haengt an der Aequivalenz-Stage (REWARD_ANCHORS weiter unten),
--     nicht am Tower — eine Stage zahlt so viel, wie ihr Gegner stark ist.
--     Hoehere Tower bringen pro Lauf trotzdem mehr, weil sie mehr Stages pro
--     Staerke-Bereich haben.
local TOWERS: { TowerDef } = {
	{
		id = "I", index = 1, stages = 30,
		startEquivalent = 1, equivalentPerStage = 1.0,
		rewardFactor = 1,
		goldPerFive = 10,
		look = "Wood", color = Color3.fromRGB(196, 140, 80), numeral = "I",
	},
	{
		id = "II", index = 2, stages = 45,
		startEquivalent = 25, equivalentPerStage = 0.95,
		rewardFactor = 1,
		goldPerFive = 20,
		look = "Stone", color = Color3.fromRGB(150, 160, 175), numeral = "II",
	},
	{
		id = "III", index = 3, stages = 60,
		startEquivalent = 55, equivalentPerStage = 0.6,
		rewardFactor = 1,
		goldPerFive = 24,
		look = "Gold", color = Color3.fromRGB(255, 196, 60), numeral = "III",
	},
	{
		id = "Final", index = 4, stages = 100,
		startEquivalent = 82, equivalentPerStage = 0.5,
		rewardFactor = 1,
		goldPerFive = 40,
		look = "Crystal", color = Color3.fromRGB(150, 220, 255), numeral = "F",
	},
}

-- HBB Paket 9 (FeatureFlags.ENDLESS): der Endless-Tower "∞". Stage 1 ist so
-- stark wie Final 101 (82 + 100 x 0,5 = 132) und waechst wie Final weiter.
-- Offen, sobald Final 100 einmal geschafft ist (getStageCap mit `records`),
-- ohne Rebirth-Deckel. 999 Stages = praktisch ohne Ende und passt in die
-- Bestenlisten-Kodierung (Index x 1000 + Stage). Staerker wird man nur durch
-- staerkere Baerchis: Endless-Level (BaerchiConfig.ENDLESS_*).
-- Nur mit Schalter in TOWERS — ohne ist alles wie vorher (UI, Sims).
if FeatureFlags.isOn("ENDLESS") then
	table.insert(TOWERS, {
		id = "Endless", index = 5, stages = 999,
		startEquivalent = 132, equivalentPerStage = 0.5,
		rewardFactor = 1,
		goldPerFive = 40,
		look = "Endless", color = Color3.fromRGB(255, 170, 230), numeral = "∞",
	})
end

-- Endless: alle wie viele Endless-Stages (erstmals geschafft) der kaempfende
-- Baerchi +1 Endless-Level bekommt (Entscheidung 05.10.: ja).
TowerConfig.ENDLESS_LEVEL_EVERY = 10

local BY_ID: { [string]: TowerDef } = {}
for _, def in TOWERS do
	BY_ID[def.id] = def
end

TowerConfig.TOWERS = TOWERS
TowerConfig.FIRST_TOWER = "I" :: Types.TowerId

function TowerConfig.get(towerId: string): TowerDef?
	return BY_ID[towerId]
end

function TowerConfig.isValidId(value: any): boolean
	return typeof(value) == "string" and BY_ID[value] ~= nil
end

function TowerConfig.getIndex(towerId: string): number
	local def = BY_ID[towerId]
	return if def then def.index else 1
end

function TowerConfig.getByIndex(index: number): TowerDef
	return TOWERS[math.clamp(math.floor(index), 1, #TOWERS)]
end

--------------------------------------------------------------------------------
-- Gegner
--------------------------------------------------------------------------------

function TowerConfig.getEquivalent(towerId: string, stage: number): number
	local def = BY_ID[towerId] or TOWERS[1]
	return def.startEquivalent + (math.max(stage, 1) - 1) * def.equivalentPerStage
end

-- Gegner-Werte einer Stage. CombatService baut daraus den Snapshot.
function TowerConfig.getEnemyStats(towerId: string, stage: number): CombatConfig.EnemyStats
	return CombatConfig.getEnemyStatsForEquivalent(TowerConfig.getEquivalent(towerId, stage))
end

--------------------------------------------------------------------------------
-- Deckel pro Rebirth
--------------------------------------------------------------------------------

-- Bis Rebirth 6 eine feste Tabelle: hoechster offener Tower und dessen Deckel.
local STAGE_CAP_BY_REBIRTH: { [number]: { tower: Types.TowerId, stage: number } } = {
	[0] = { tower = "I",   stage = 15 },
	[1] = { tower = "I",   stage = 30 },
	[2] = { tower = "II",  stage = 25 },
	[3] = { tower = "II",  stage = 45 },
	[4] = { tower = "III", stage = 40 },
	[5] = { tower = "III", stage = 60 },
	[6] = { tower = "III", stage = 60 },
}

-- Ab Rebirth 7 ist der Final-Tower offen: Deckel 20, jeder weitere Rebirth +10,
-- bis 100 (bei Rebirth 15).
local FINAL_CAP = {
	fromRebirth = 7,
	startStage  = 20,
	perRebirth  = 10,
}

TowerConfig.STAGE_CAP_BY_REBIRTH = STAGE_CAP_BY_REBIRTH
TowerConfig.FINAL_CAP = FINAL_CAP

-- Hoechster offener Tower und sein Deckel bei `rebirthCount` Rebirths.
function TowerConfig.getCap(rebirthCount: number): (Types.TowerId, number)
	local n = math.max(0, math.floor(rebirthCount))
	if n >= FINAL_CAP.fromRebirth then
		local finalDef = BY_ID.Final
		local stage = FINAL_CAP.startStage + (n - FINAL_CAP.fromRebirth) * FINAL_CAP.perRebirth
		return "Final", math.min(stage, finalDef.stages)
	end
	local entry = STAGE_CAP_BY_REBIRTH[n] or STAGE_CAP_BY_REBIRTH[0]
	return entry.tower, entry.stage
end

-- Ist Endless fuer diese Rekorde offen? (Final 100 einmal geschafft)
function TowerConfig.isEndlessOpen(records: { [string]: number }?): boolean
	local finalDef = BY_ID.Final
	return BY_ID.Endless ~= nil and records ~= nil and (records.Final or 0) >= finalDef.stages
end

-- Deckel in DIESEM Tower: volle Stage-Zahl fuer Tower unter dem Deckel-Tower,
-- der Deckel selbst fuer den Deckel-Tower, 0 fuer noch geschlossene Tower.
-- `records` (Tower-Rekorde) braucht nur Endless: offen ab Final 100.
function TowerConfig.getStageCap(rebirthCount: number, towerId: string, records: { [string]: number }?): number
	local def = BY_ID[towerId]
	if not def then return 0 end
	if towerId == "Endless" then
		return if TowerConfig.isEndlessOpen(records) then def.stages else 0
	end
	local capTower, capStage = TowerConfig.getCap(rebirthCount)
	local capIndex = TowerConfig.getIndex(capTower)
	if def.index < capIndex then return def.stages end
	if def.index == capIndex then return math.min(capStage, def.stages) end
	return 0
end

function TowerConfig.isOpen(rebirthCount: number, towerId: string, records: { [string]: number }?): boolean
	return TowerConfig.getStageCap(rebirthCount, towerId, records) > 0
end

-- Ab welchem Rebirth ein Tower offen ist (fuer die gesperrte Karte im UI).
function TowerConfig.getOpeningRebirth(towerId: string): number
	for n = 0, FINAL_CAP.fromRebirth do
		if TowerConfig.isOpen(n, towerId) then return n end
	end
	return FINAL_CAP.fromRebirth
end

-- Ist der Deckel des aktuellen Rebirths ein ECHTES Limit (nicht die volle
-- Stage-Zahl eines aelteren Towers)? Nur dann gibt es den Rebirth-Hinweis.
function TowerConfig.isCapLimiting(rebirthCount: number, towerId: string): boolean
	local def = BY_ID[towerId]
	if not def then return false end
	local capTower = TowerConfig.getCap(rebirthCount)
	if capTower ~= towerId then return false end
	-- Final bei 100 oder Tower III bei 60: es gibt nichts mehr hinter dem Deckel,
	-- was ein Rebirth oeffnen wuerde — ausser beim letzten Stand der Tabelle.
	local nextTower, nextStage = TowerConfig.getCap(rebirthCount + 1)
	return TowerConfig.getIndex(nextTower) > def.index
		or nextStage > TowerConfig.getStageCap(rebirthCount, towerId)
end

--------------------------------------------------------------------------------
-- Belohnungen pro Lauf
--------------------------------------------------------------------------------

-- Stage-Gummies (Basis, ohne Rebirth-Multiplikator) ueber der Aequivalenz-
-- Stage: zwischen zwei Ankerpunkten log-linear (also exponentiell)
-- interpoliert, darueber mit der Steigung des letzten Abschnitts weiter.
-- Ersetzt die alte Tabelle PIT_GUMMY_REWARDS (die PIT-Level-Stufen) — das Tempo
-- kommt jetzt aus der Tiefe. Kalibriert mit tools/sim/progression_pacing.lua
-- (ANNAHME, im Bericht gelistet). Erster Anker = alter PIT 1, Stage 1.
local REWARD_ANCHORS: { { number } } = {
	{ 1,   10 },
	{ 15,  30_000 },
	{ 30,  300_000 },
	{ 45,  1_500_000 },
	{ 67,  6_000_000 },
	{ 90,  30_000_000 },
	{ 132, 300_000_000 },
}
TowerConfig.REWARD_ANCHORS = REWARD_ANCHORS

local function rewardForEquivalent(equivalent: number): number
	local first = REWARD_ANCHORS[1]
	if equivalent <= first[1] then return first[2] end
	for i = 2, #REWARD_ANCHORS do
		local a, b = REWARD_ANCHORS[i - 1], REWARD_ANCHORS[i]
		if equivalent <= b[1] or i == #REWARD_ANCHORS then
			local t = (equivalent - a[1]) / (b[1] - a[1])
			return a[2] * math.pow(b[2] / a[2], t)
		end
	end
	return first[2]
end

-- Basis-Gummies einer geschafften Stage, OHNE rebirthMult (den wendet
-- EconomyService.awardGummies an — wer ihn hier draufrechnet, verdoppelt ihn).
function TowerConfig.getStageReward(towerId: string, stage: number): number
	local def = BY_ID[towerId] or TOWERS[1]
	local value = rewardForEquivalent(TowerConfig.getEquivalent(towerId, stage)) * def.rewardFactor
	return math.max(1, math.floor(value))
end

-- Summe der Basis-Gummies fuer die Stages fromStage..toStage.
function TowerConfig.sumStageRewards(towerId: string, fromStage: number, toStage: number): number
	local total = 0
	for stage = math.max(1, fromStage), toStage do
		total += TowerConfig.getStageReward(towerId, stage)
	end
	return total
end

-- GoldGummies eines Laufs: pro 5 geschaffte Stages (bis zum Deckel).
TowerConfig.GOLD_EVERY_STAGES = 5

function TowerConfig.getRunGold(towerId: string, stagesCleared: number): number
	local def = BY_ID[towerId] or TOWERS[1]
	-- GOLD_CHARMS_ONLY: Tower-Laeufe geben kein Gold mehr
	if FeatureFlags.isOn("GOLD_CHARMS_ONLY") then return 0 end
	return math.floor(math.max(0, stagesCleared) / TowerConfig.GOLD_EVERY_STAGES) * def.goldPerFive
end

--------------------------------------------------------------------------------
-- Meilensteine (einmalig pro Tower und Stage, permanent)
--------------------------------------------------------------------------------
-- ANNAHME (im Bericht gelistet): alle 5 Stages ein Meilenstein.
--   * Gummies (OHNE Rebirth-Multiplikator) bis Stage 25 des jeweiligen
--     Towers: MILESTONE_GUMMY_FACTOR x Stage-Belohnung dieser Stage.
--   * jede 10er-Stage zusaetzlich ein Ei (das hoechste freie Ei im Ei-Baum).
--   * jede 25er-Stage GoldGummies + eine Blaupause.
--   * Ein Meilenstein ueber Stage 25, der sonst leer bliebe (35, 45, ...),
--     gibt MILESTONE_GOLD_SMALL x goldPerFive GoldGummies — leer soll keiner sein.
--   * GOLD_CHARMS_ONLY: kein Gold; leere Meilensteine geben stattdessen Gummies.

TowerConfig.MILESTONE_EVERY        = 5
TowerConfig.MILESTONE_GUMMY_UNTIL  = 25
TowerConfig.MILESTONE_EGG_EVERY    = 10
TowerConfig.MILESTONE_BIG_EVERY    = 25
TowerConfig.MILESTONE_GUMMY_FACTOR = 10
TowerConfig.MILESTONE_GOLD_BIG     = 25   -- x goldPerFive
TowerConfig.MILESTONE_GOLD_SMALL   = 4    -- x goldPerFive
TowerConfig.MILESTONE_BLUEPRINTS   = 1

export type Milestone = {
	gummies     : number,   -- flach, ohne Multiplikator
	goldGummies : number,
	eggs        : number,   -- Anzahl "hoechstes freies Ei"
	blueprints  : number,
	endlessLevels : number, -- Paket 9: +Endless-Level fuer den ausgeruesteten Baerchi
}

function TowerConfig.isMilestone(stage: number): boolean
	return stage >= TowerConfig.MILESTONE_EVERY and stage % TowerConfig.MILESTONE_EVERY == 0
end

function TowerConfig.getMilestone(towerId: string, stage: number): Milestone?
	local def = BY_ID[towerId]
	if not def or stage > def.stages or not TowerConfig.isMilestone(stage) then
		return nil
	end

	local result: Milestone = { gummies = 0, goldGummies = 0, eggs = 0, blueprints = 0, endlessLevels = 0 }
	if stage <= TowerConfig.MILESTONE_GUMMY_UNTIL then
		result.gummies = TowerConfig.MILESTONE_GUMMY_FACTOR * TowerConfig.getStageReward(towerId, stage)
	end
	if stage % TowerConfig.MILESTONE_EGG_EVERY == 0 then
		result.eggs = 1
	end
	if stage % TowerConfig.MILESTONE_BIG_EVERY == 0 then
		result.goldGummies += TowerConfig.MILESTONE_GOLD_BIG * def.goldPerFive
		result.blueprints = TowerConfig.MILESTONE_BLUEPRINTS
	end
	if FeatureFlags.isOn("GOLD_CHARMS_ONLY") then
		-- Kein Gold aus Meilensteinen. Was sonst leer bliebe (35, 45, ...),
		-- gibt flache Gummies wie die Meilensteine bis Stage 25.
		result.goldGummies = 0
		if result.gummies == 0 and result.eggs == 0 then
			result.gummies = TowerConfig.MILESTONE_GUMMY_FACTOR * TowerConfig.getStageReward(towerId, stage)
		end
	elseif result.gummies == 0 and result.eggs == 0 and result.goldGummies == 0 then
		result.goldGummies = TowerConfig.MILESTONE_GOLD_SMALL * def.goldPerFive
	end
	if towerId == "Endless" and stage % TowerConfig.ENDLESS_LEVEL_EVERY == 0 then
		result.endlessLevels = 1
	end
	return result
end

-- Der naechste noch nicht abgeholte Meilenstein ab `fromStage` (fuer die Karte
-- im UI). nil = es gibt keinen mehr.
function TowerConfig.nextMilestoneStage(towerId: string, claimed: { [string]: boolean }?, fromStage: number): number?
	local def = BY_ID[towerId]
	if not def then return nil end
	local stage = math.max(TowerConfig.MILESTONE_EVERY, fromStage)
	stage = math.ceil(stage / TowerConfig.MILESTONE_EVERY) * TowerConfig.MILESTONE_EVERY
	while stage <= def.stages do
		if not (claimed and claimed[tostring(stage)]) then
			return stage
		end
		stage += TowerConfig.MILESTONE_EVERY
	end
	return nil
end

--------------------------------------------------------------------------------
-- Fortsetzen (pro Tower, Regeln wie beim alten PIT)
--------------------------------------------------------------------------------
-- "Percent" = 65 % der Stage-Tiefe des letzten Laufs, "Last" = die letzte
-- erreichte Stage. Kosten = Anteil der Belohnungen der uebersprungenen Stages,
-- mal rebirthMult (sonst waere Ueberspringen nach ein paar Rebirths umsonst).
-- 0,35 ist weiterhin ein PLATZHALTER aus dem PIT-Konzept.
TowerConfig.RESUME_PERCENT     = 0.65
TowerConfig.RESUME_COST_FACTOR = 0.35

function TowerConfig.getResumePercentStage(reachedStage: number): number
	return math.max(1, math.floor(TowerConfig.RESUME_PERCENT * reachedStage))
end

function TowerConfig.getResumeCost(towerId: string, startStage: number, rebirthMult: number): number
	if startStage <= 1 then return 0 end
	local skipped = TowerConfig.sumStageRewards(towerId, 1, startStage - 1)
	return math.floor(TowerConfig.RESUME_COST_FACTOR * skipped * math.max(rebirthMult, 1))
end

--------------------------------------------------------------------------------
-- Darstellung (Etagen) — die Modelle stehen in MapConfig.TOWER_LOOKS
--------------------------------------------------------------------------------

-- Waehrend eines Laufs waechst unter den Kaempfern ein Turm. Bei bis zu 100
-- Stages wird er GESTAUCHT: hoechstens RUN_MAX_FLOORS Etagen, gleichmaessig
-- ueber die Stage-Zahl des Towers verteilt (Tower I: eine Etage pro Stage).
TowerConfig.RUN_MAX_FLOORS = 30

-- Fuer Hoehen-Anzeigen: Endless hat 999 Stages "ohne Ende", wird aber wie
-- ein 100er-Tower gestaucht — sonst blieben Arena und Schau-Turm flach.
local function displayStages(def: TowerDef): number
	return if def.id == "Endless" then 100 else def.stages
end

function TowerConfig.getRunFloor(towerId: string, stage: number): number
	local def = BY_ID[towerId] or TOWERS[1]
	if stage <= 1 then return 0 end
	local stages = displayStages(def)
	local floors = math.min(TowerConfig.RUN_MAX_FLOORS, stages)
	return math.clamp(math.floor((stage - 1) * floors / stages + 0.5), 0, floors)
end

-- Der staendige Angeber-Turm auf der Arena-Insel: Hoehe = Rekord im hoechsten
-- Tower, gestaucht auf hoechstens SHOWCASE_MAX_FLOORS Etagen (Part-Budget).
TowerConfig.SHOWCASE_MAX_FLOORS = 12

function TowerConfig.getShowcaseFloors(towerId: string, record: number): number
	local def = BY_ID[towerId] or TOWERS[1]
	if record <= 0 then return 1 end
	return math.clamp(math.ceil(record * TowerConfig.SHOWCASE_MAX_FLOORS / displayStages(def)), 1, TowerConfig.SHOWCASE_MAX_FLOORS)
end

--------------------------------------------------------------------------------
-- Bestenliste
--------------------------------------------------------------------------------

-- Ein Wert fuer "wie weit oben": Tower-Index x 1000 + Rekord.
function TowerConfig.leaderboardValue(towerId: string, record: number): number
	return TowerConfig.getIndex(towerId) * 1000 + math.max(0, math.floor(record))
end

function TowerConfig.fromLeaderboardValue(value: number): (string, number)
	local index = math.clamp(math.floor(value / 1000), 1, #TOWERS)
	return TOWERS[index].id, math.floor(value % 1000)
end

-- Hoechster Tower mit Rekord > 0 (oder der erste) und dieser Rekord.
function TowerConfig.bestRecord(towers: Types.TowerState?): (string, number)
	if not towers then return TOWERS[1].id, 0 end
	for i = #TOWERS, 1, -1 do
		local id = TOWERS[i].id
		local record = towers.records[id] or 0
		if record > 0 then
			return id, record
		end
	end
	return TOWERS[1].id, 0
end

--------------------------------------------------------------------------------
-- Migration v14 -> v15
--------------------------------------------------------------------------------

-- Bezahlte Ausbaukosten der alten PIT-Level (nur fuer die Erstattung).
local LEGACY_PIT_UPGRADE_COSTS: { [number]: number } = {
	[2] = 500, [3] = 1_500, [4] = 4_000, [5] = 10_000,
	[6] = 25_000, [7] = 60_000, [8] = 150_000,
}
TowerConfig.LEGACY_PIT_UPGRADE_COSTS = LEGACY_PIT_UPGRADE_COSTS

-- Summe der bezahlten Kosten fuer ein altes PIT-Level.
function TowerConfig.legacyPitRefund(pitLevel: number): number
	local total = 0
	for level = 2, math.clamp(math.floor(pitLevel or 1), 1, 8) do
		total += LEGACY_PIT_UPGRADE_COSTS[level] or 0
	end
	return total
end

-- Rechnet einen alten PIT-Stand (Level + Stage) in die gleich starke
-- Tower-Stage um: der NIEDRIGSTE Tower, in dessen Stage-Bereich die Staerke
-- noch passt, und darin die letzte Stage, die nicht staerker ist. So landet ein
-- Anfaenger-Rekord in Tower I (den er sofort wieder spielen kann) und nur ein
-- Rekord jenseits von Tower-I-Stage 30 in einem hoeheren Tower. Gibt nil
-- zurueck, wenn es nichts umzurechnen gibt (Stage < 1).
function TowerConfig.legacyPitToTower(pitLevel: number, stage: number): (string?, number)
	if (stage or 0) < 1 then return nil, 0 end
	local growth = CombatConfig.getLegacyPitGrowth(pitLevel or 1, stage)
	local equivalent = 1 + math.log(growth) / math.log(1 + CombatConfig.STAGE_GROWTH)

	for _, def in TOWERS do
		local lastEquivalent = TowerConfig.getEquivalent(def.id, def.stages)
		if equivalent <= lastEquivalent + 1e-6 then
			local s = 1 + math.floor((equivalent - def.startEquivalent) / def.equivalentPerStage + 1e-6)
			return def.id, math.clamp(s, 1, def.stages)
		end
	end
	local last = TOWERS[#TOWERS]
	return last.id, last.stages
end

return TowerConfig
