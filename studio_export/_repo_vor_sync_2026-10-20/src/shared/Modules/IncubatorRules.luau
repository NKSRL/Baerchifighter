--!strict
-- IncubatorRules.luau
-- ReplicatedStorage/Modules/IncubatorRules.luau
--
-- Einzige Zustaendigkeit:
--   - Die Rechenregeln des Inkubators als reine Funktionen (Sammel-Update
--     05.10., Paket 8): Freischaltung, Platz-Zahl, Brutzeit, fertig?,
--     Beschleunigungs-Kosten, Ausbau-Kosten.
--
-- Keine Roblox-Dienste, keine Zeit-Abfrage: `now` kommt immer von aussen.
-- Damit laeuft die Zeitrechnung (auch der Offline-Fall) im reinen Test
-- (tools/luau-tests/incubator.test.lua) und auf Server und Client gleich.
--
-- WARUM ZEITMARKEN STATT TIMER: wie Honig und Recycler. Ein Platz traegt
-- startedAt/finishAt; fertig ist er, sobald now >= finishAt — egal, ob der
-- Spieler dazwischen offline war oder der Server neu gestartet ist. Kein
-- Thread pro Ei.

local Types             = require(script.Parent.Parent.Network.Types)
local IncubatorConfig   = require(script.Parent.Parent.Config.IncubatorConfig)
local EggConfig         = require(script.Parent.Parent.Config.EggConfig)
local EconomyConfig     = require(script.Parent.Parent.Config.EconomyConfig)
local IndexRewardConfig = require(script.Parent.Parent.Config.IndexRewardConfig)

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
	--------------------------------------------------------------------------------
-- INCUBATOR_BREED: Baerchis im Inkubator
--------------------------------------------------------------------------------

-- Sekunden pro gebruetetes Ei fuer diese Rarity auf diesem Level.
-- `offline` bremst wie beim Legen (offlineSlowdown, vom Aufrufer).
function IncubatorRules.breedSeconds(rarity: string, level: number, offlineSlowdown: number?): number
	local base = IncubatorConfig.BREED_SECONDS_BY_RARITY[rarity] or IncubatorConfig.BREED_DEFAULT_SECONDS
	local seconds = base / IncubatorRules.speed(level) * (offlineSlowdown or 1)
	return math.max(1, math.floor(seconds + 0.5))
end

-- Wie viele Eier seit `lastEggAt` faellig sind (0, wenn keins).
function IncubatorRules.breedDue(lastEggAt: number, now: number, seconds: number): number
	if seconds <= 0 or now <= lastEggAt then return 0 end
	return math.floor((now - lastEggAt) / seconds)
end

-- Der Eintrag fuer Platz `index` in `breeders`, oder nil.
function IncubatorRules.findBreeder(breeders: { Types.IncubatorBreeder }?, index: number): (Types.IncubatorBreeder?, number?)
	for i, entry in breeders or {} do
		if entry.slot == index then return entry, i end
	end
	return nil, nil
end

-- Sitzt dieser Baerchi im Inkubator? Gibt den Platz zurueck.
function IncubatorRules.breederSlotOf(breeders: { Types.IncubatorBreeder }?, uid: string): number?
	for _, entry in breeders or {} do
		if entry.uid == uid then return entry.slot end
	end
	return nil
end

-- Der erste freie Baerchi-Platz (1 .. count), oder nil.
function IncubatorRules.firstFreeBreeder(breeders: { Types.IncubatorBreeder }?, count: number): number?
	for index = 1, count do
		if not IncubatorRules.findBreeder(breeders, index) then return index end
	end
	return nil
end

-- Darf dieser Baerchi hinein? Gibt (ok, Fehler-Schluessel) zurueck.
-- Der ausgeruestete legt schon selbst — er bleibt draussen.
function IncubatorRules.canBreed(island: any, uid: string): (boolean, string?)
	if not island.baerchis[uid] then return false, "err.baerchi_not_found" end
	if island.equippedUid == uid then return false, "err.incubator_equipped" end
	local incubator = island.incubator
	if incubator and IncubatorRules.breederSlotOf(incubator.breeders, uid) then
		return false, "err.incubator_already_in"
	end
	return true, nil
end

return IncubatorRules.slotCount(level, data.rebirthCount or 0, data.indexClaimed)
end

-- Tempo-Faktor des Levels (1 auf Level 1).
function IncubatorRules.speed(level: number): number
	return 1 + math.max(0, math.floor(level) - 1) * IncubatorConfig.SPEED_PER_LEVEL
end

-- Brutzeit in Sekunden fuer dieses Ei auf diesem Level.
function IncubatorRules.brewSeconds(eggType: Types.EggType, level: number): number
	local egg = EggConfig.data[eggType]
	local tier = if egg then egg.tier else 1
	local base = IncubatorConfig.BREW_SECONDS_BY_TIER[tier] or IncubatorConfig.BREW_SECONDS_BY_TIER[11]
	return math.max(1, math.floor(base / IncubatorRules.speed(level) + 0.5))
end

-- Muss dieses Ei in den Inkubator (statt sofort aufzugehen)? Nur, wenn der
-- Inkubator schon frei ist — vorher geht alles sofort (sonst haengt ein
-- neuer Spieler mit einem gelegten Gold-Ei fest).
function IncubatorRules.requiresIncubator(eggType: Types.EggType, unlocked: boolean): boolean
	if not unlocked then return false end
	local egg = EggConfig.data[eggType]
	if not egg then return false end
	return egg.tier > IncubatorConfig.INSTANT_MAX_TIER or egg.special == true
end

function IncubatorRules.isReady(slot: Types.IncubatorSlot, now: number): boolean
	return now >= slot.finishAt
end

function IncubatorRules.remaining(slot: Types.IncubatorSlot, now: number): number
	return math.max(0, slot.finishAt - now)
end

-- Anteil 0..1 (fuer Fortschrittsbalken).
function IncubatorRules.progress(slot: Types.IncubatorSlot, now: number): number
	local total = math.max(1, slot.finishAt - slot.startedAt)
	return math.clamp((now - slot.startedAt) / total, 0, 1)
end

-- GoldGummies fuer "sofort fertig" (0 = schon fertig).
function IncubatorRules.speedUpCost(slot: Types.IncubatorSlot, now: number): number
	local left = IncubatorRules.remaining(slot, now)
	if left <= 0 then return 0 end
	return math.max(1, math.ceil(left / 60)) * IncubatorConfig.SPEEDUP_GOLD_PER_MINUTE
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

--------------------------------------------------------------------------------
-- INCUBATOR_BREED: Baerchis im Inkubator
--------------------------------------------------------------------------------

-- Sekunden pro gebruetetes Ei fuer diese Rarity auf diesem Level.
-- `offline` bremst wie beim Legen (offlineSlowdown, vom Aufrufer).
function IncubatorRules.breedSeconds(rarity: string, level: number, offlineSlowdown: number?): number
	local base = IncubatorConfig.BREED_SECONDS_BY_RARITY[rarity] or IncubatorConfig.BREED_DEFAULT_SECONDS
	local seconds = base / IncubatorRules.speed(level) * (offlineSlowdown or 1)
	return math.max(1, math.floor(seconds + 0.5))
end

-- Wie viele Eier seit `lastEggAt` faellig sind (0, wenn keins).
function IncubatorRules.breedDue(lastEggAt: number, now: number, seconds: number): number
	if seconds <= 0 or now <= lastEggAt then return 0 end
	return math.floor((now - lastEggAt) / seconds)
end

-- Der Eintrag fuer Platz `index` in `breeders`, oder nil.
function IncubatorRules.findBreeder(breeders: { Types.IncubatorBreeder }?, index: number): (Types.IncubatorBreeder?, number?)
	for i, entry in breeders or {} do
		if entry.slot == index then return entry, i end
	end
	return nil, nil
end

-- Sitzt dieser Baerchi im Inkubator? Gibt den Platz zurueck.
function IncubatorRules.breederSlotOf(breeders: { Types.IncubatorBreeder }?, uid: string): number?
	for _, entry in breeders or {} do
		if entry.uid == uid then return entry.slot end
	end
	return nil
end

-- Der erste freie Baerchi-Platz (1 .. count), oder nil.
function IncubatorRules.firstFreeBreeder(breeders: { Types.IncubatorBreeder }?, count: number): number?
	for index = 1, count do
		if not IncubatorRules.findBreeder(breeders, index) then return index end
	end
	return nil
end

-- Darf dieser Baerchi hinein? Gibt (ok, Fehler-Schluessel) zurueck.
-- Der ausgeruestete legt schon selbst — er bleibt draussen.
function IncubatorRules.canBreed(island: any, uid: string): (boolean, string?)
	if not island.baerchis[uid] then return false, "err.baerchi_not_found" end
	if island.equippedUid == uid then return false, "err.incubator_equipped" end
	local incubator = island.incubator
	if incubator and IncubatorRules.breederSlotOf(incubator.breeders, uid) then
		return false, "err.incubator_already_in"
	end
	return true, nil
end

return IncubatorRules
