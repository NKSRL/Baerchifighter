--!strict
-- IncubatorRules.luau
-- ReplicatedStorage/Modules/IncubatorRules.luau
--
-- Einzige Zustaendigkeit:
--   - Die Rechenregeln des Inkubators als reine Funktionen (Sammel-Update
--     05.10., Paket 8, Umbau nach Rueckmeldung 05.10.): Freischaltung,
--     Platz-Zahl, Brut-Takt eines Baerchis, wie viele Eier faellig sind,
--     Ausbau-Kosten.
--
-- Keine Roblox-Dienste, keine Zeit-Abfrage: `now` kommt immer von aussen.
-- Damit laeuft die Zeitrechnung (auch der Offline-Fall) im reinen Test
-- (tools/luau-tests/incubator.test.lua) und auf Server und Client gleich.
--
-- WARUM ZEITMARKEN STATT TIMER: wie Honig und Recycler. Ein Platz traegt
-- lastEggAt; faellig sind floor((now - lastEggAt) / Takt) Eier — egal, ob
-- der Spieler dazwischen offline war oder der Server neu gestartet ist.

local Types             = require(script.Parent.Parent.Network.Types)
local IncubatorConfig   = require(script.Parent.Parent.Config.IncubatorConfig)
local EggConfig         = require(script.Parent.Parent.Config.EggConfig)
local EconomyConfig     = require(script.Parent.Parent.Config.EconomyConfig)
local IndexRewardConfig = require(script.Parent.Parent.Config.IndexRewardConfig)
local EggCalculator     = require(script.Parent.EggCalculator)
local EggTree           = require(script.Parent.EggTree)

local IncubatorRules = {}

-- Frei ab dem ersten Kampf (Entscheidung 11.6). Gleiche Bedingung wie
-- UnlockRules.hasFought, aber nur aus den gespeicherten Werten.
function IncubatorRules.isUnlocked(data: any): boolean
	if (data.rebirthCount or 0) > 0 then return true end
	local towers = data.towers
	if towers and towers.records and next(towers.records) ~= nil then return true end
	local stats = data.stats or {}
	return (stats.totalFightsWon or 0) + (stats.totalFightsLost or 0) > 0
end

-- Plaetze aus Level, Rebirths und Index-Belohnungen, hoechstens MAX_SLOTS.
function IncubatorRules.slotCount(level: number, rebirthCount: number, indexClaimed: { [string]: boolean }?): number
	local n = 0
	for _, step in IncubatorConfig.SLOTS_BY_LEVEL do
		if level >= step.level then n = step.slots end
	end
	if rebirthCount >= IncubatorConfig.REBIRTH_BONUS_FROM then n += 1 end
	n += IndexRewardConfig.incubatorSlots(indexClaimed)
	return math.clamp(n, 1, IncubatorConfig.MAX_SLOTS)
end

function IncubatorRules.slotCountFor(data: any): number
	local incubator = data.island and data.island.incubator
	local level = if incubator then incubator.level or 1 else 1
	return IncubatorRules.slotCount(level, data.rebirthCount or 0, data.indexClaimed)
end

-- Tempo-Faktor des Levels (1 auf Level 1).
function IncubatorRules.speed(level: number): number
	return 1 + math.max(0, math.floor(level) - 1) * IncubatorConfig.SPEED_PER_LEVEL
end

-- Sekunden pro Ei fuer einen Baerchi dieser Rarity auf diesem Level.
-- `offline = true` bremst wie beim Legen (EggConfig.OFFLINE_SLOWDOWN).
function IncubatorRules.breedSeconds(rarity: string, level: number, offline: boolean?): number
	local base = IncubatorConfig.BREED_SECONDS_BY_RARITY[rarity] or IncubatorConfig.BREED_SECONDS_FALLBACK
	local seconds = base / IncubatorRules.speed(level)
	if offline then seconds *= EggConfig.OFFLINE_SLOWDOWN end
	return math.max(1, math.floor(seconds + 0.5))
end

-- Wie viele Eier seit lastEggAt faellig sind (gedeckelt durch den freien
-- Platz im Lager) und die neue Zeitmarke. Ist das Lager voll, laeuft die
-- Zeitmarke mit (sonst kaeme nach dem Abholen die Wartezeit auf einmal).
function IncubatorRules.due(slot: Types.IncubatorSlot, interval: number, now: number): (number, number)
	local stored = #slot.eggs
	local room = math.max(0, IncubatorConfig.STORE_PER_SLOT - stored)
	local elapsed = now - slot.lastEggAt
	if elapsed <= 0 or interval <= 0 then return 0, math.min(slot.lastEggAt, now) end
	local count = math.floor(elapsed / interval)
	if count >= room then
		return room, now
	end
	return count, slot.lastEggAt + count * interval
end

-- Anteil 0..1 bis zum naechsten Ei (fuer den Balken ueber der Kuppel).
function IncubatorRules.progress(slot: Types.IncubatorSlot, interval: number, now: number): number
	if #slot.eggs >= IncubatorConfig.STORE_PER_SLOT then return 1 end
	return math.clamp((now - slot.lastEggAt) / math.max(1, interval), 0, 1)
end

-- Mit welcher Wahrscheinlichkeit bruetet dieser Baerchi welches Ei? Wie
-- EggCalculator.getChances, aber gesperrte Eier schon auf ihren freien
-- Vorgaenger umgerechnet (EggTree.resolveLaid) — also genau das, was im
-- Platz landen kann. Absteigend sortiert.
function IncubatorRules.chances(baerchi: Types.Baerchi, eggTree: Types.EggTreeState?): { { eggType: Types.EggType, percent: number } }
	local merged: { [string]: number } = {}
	for _, entry in EggCalculator.getChances(baerchi) do
		local eggType = EggTree.resolveLaid(eggTree, entry.eggType)
		merged[eggType] = (merged[eggType] or 0) + entry.percent
	end
	local result: { { eggType: Types.EggType, percent: number } } = {}
	for eggType, percent in merged do
		table.insert(result, { eggType = eggType :: Types.EggType, percent = percent })
	end
	table.sort(result, function(a, b)
		if a.percent ~= b.percent then return a.percent > b.percent end
		return a.eggType < b.eggType
	end)
	return result
end

-- Ist dieser Baerchi gerade im Inkubator? (Platz-Index oder nil)
function IncubatorRules.slotOf(slots: { Types.IncubatorSlot }, baerchiUid: string): number?
	for _, entry in slots do
		if entry.baerchiUid == baerchiUid then return entry.slot end
	end
	return nil
end

-- Alle wartenden Eier zusammen.
function IncubatorRules.storedCount(slots: { Types.IncubatorSlot }): number
	local n = 0
	for _, entry in slots do n += #entry.eggs end
	return n
end

-- Kosten fuer Level `targetLevel` (nil = gibt es nicht).
function IncubatorRules.upgradeCost(targetLevel: number): { gummies: number, goldGummies: number }?
	if targetLevel < 2 or targetLevel > IncubatorConfig.MAX_LEVEL then return nil end
	local base = EconomyConfig.HONEY_UPGRADE_COSTS[targetLevel]
	if not base then return nil end
	return {
		gummies     = math.floor(base.gummies * IncubatorConfig.COST_FACTOR),
		goldGummies = math.floor((base.goldGummies or 0) * IncubatorConfig.COST_FACTOR),
	}
end

-- Der Eintrag in `slots` fuer Platz `index`, oder nil (frei).
function IncubatorRules.findSlot(slots: { Types.IncubatorSlot }, index: number): (Types.IncubatorSlot?, number?)
	for i, entry in slots do
		if entry.slot == index then return entry, i end
	end
	return nil, nil
end

-- Der erste freie Platz (1 .. count), oder nil.
function IncubatorRules.firstFree(slots: { Types.IncubatorSlot }, count: number): number?
	for index = 1, count do
		if not IncubatorRules.findSlot(slots, index) then return index end
	end
	return nil
end

return IncubatorRules
