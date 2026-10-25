--!strict
-- IncubatorRules.luau
-- ReplicatedStorage/Modules/IncubatorRules.luau
--
-- Einzige Zustaendigkeit:
--   - Die Rechenregeln des Solo-Inkubators (15.10.2026) als reine Funktionen:
--     Freischaltung, Stufe, Lager-Grenze, Tempo, Brut-Takt, Ausbau-
--     Voraussetzungen und -Kosten.
--
-- Keine Roblox-Dienste, keine Zeit-Abfrage: `now` kommt immer von aussen.
-- Server (IncubatorService) und Client (IncubatorPanel/-Controller) rechnen
-- damit gleich.
--
-- WARUM ZEITMARKEN STATT TIMER: wie Honig und Recycler. Der Baerchi im
-- Inkubator traegt lastEggAt; faellig wird nachgerechnet (breedDue) — egal,
-- ob der Spieler dazwischen offline war oder der Server neu gestartet ist.

local Types           = require(script.Parent.Parent.Network.Types)
local IncubatorConfig = require(script.Parent.Parent.Config.IncubatorConfig)
local EconomyConfig   = require(script.Parent.Parent.Config.EconomyConfig)
local TowerConfig     = require(script.Parent.Parent.Config.TowerConfig)       -- 20.10. P5a
local FeatureFlags    = require(script.Parent.Parent.Config.FeatureFlags)

local IncubatorRules = {}

-- Frei ab dem ersten Kampf. Gleiche Bedingung wie UnlockRules.hasFought, aber
-- nur aus den gespeicherten Werten.
function IncubatorRules.isUnlocked(data: any): boolean
	if (data.rebirthCount or 0) > 0 then return true end
	local towers = data.towers
	if towers and towers.records and next(towers.records) ~= nil then return true end
	local stats = data.stats or {}
	return (stats.totalFightsWon or 0) + (stats.totalFightsLost or 0) > 0
end

--------------------------------------------------------------------------------
-- Stufe, Lager, Tempo
--------------------------------------------------------------------------------

-- Stufe 1..MAX_LEVEL. Alte Staende (Level bis 60) werden gekappt.
function IncubatorRules.levelOf(incubator: { level: number }?): number
	local level = if incubator then incubator.level else 1
	if typeof(level) ~= "number" then return 1 end
	return math.clamp(math.floor(level), 1, IncubatorConfig.MAX_LEVEL)
end

function IncubatorRules.levelDef(level: number): { capacity: number, speed: number, rebirths: number?, costLevel: number? }
	return IncubatorConfig.LEVELS[math.clamp(math.floor(level), 1, IncubatorConfig.MAX_LEVEL)]
end

-- So viele Eier sammelt der Inkubator, bevor das Brueten pausiert.
function IncubatorRules.capacity(level: number): number
	return IncubatorRules.levelDef(level).capacity
end

-- Tempo-Faktor der Stufe (1 auf Stufe 1, nur leicht darueber).
function IncubatorRules.speed(level: number): number
	return IncubatorRules.levelDef(level).speed
end

-- Es gibt genau einen Platz (die alten Funktionen bleiben fuer Aufrufer).
function IncubatorRules.slotCount(_level: number?, _rebirthCount: number?, _indexClaimed: any?): number
	return IncubatorConfig.MAX_SLOTS
end

function IncubatorRules.slotCountFor(_data: any): number
	return IncubatorConfig.MAX_SLOTS
end

-- Das Lager (Sorte -> Anzahl); legt es an, falls es in alten Staenden fehlt.
function IncubatorRules.storedOf(incubator: Types.IncubatorData): { [string]: number }
	if typeof(incubator.stored) ~= "table" then incubator.stored = {} end
	return incubator.stored :: { [string]: number }
end

function IncubatorRules.storedTotal(incubator: Types.IncubatorData?): number
	local total = 0
	if incubator and typeof(incubator.stored) == "table" then
		for _, count in incubator.stored :: { [string]: number } do total += math.max(0, count) end
	end
	return total
end

-- Noch freier Platz im Lager (>= 0).
function IncubatorRules.storedFree(incubator: Types.IncubatorData): number
	return math.max(0, IncubatorRules.capacity(IncubatorRules.levelOf(incubator)) - IncubatorRules.storedTotal(incubator))
end

--------------------------------------------------------------------------------
-- Brut-Takt
--------------------------------------------------------------------------------

-- Sekunden pro gebruetetes Ei fuer diese Rarity auf dieser Stufe.
-- `offlineSlowdown` bremst wie beim Legen (vom Aufrufer, EggConfig.OFFLINE_SLOWDOWN).
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

--------------------------------------------------------------------------------
-- Der Baerchi im Inkubator
--------------------------------------------------------------------------------

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

-- Eier gehen immer sofort auf; der Inkubator bruetet nur noch Eier aus.
function IncubatorRules.requiresIncubator(_eggType: any, _unlocked: boolean): boolean
	return false
end

--------------------------------------------------------------------------------
-- Gluecks-Bonus (siehe IncubatorConfig.LUCK)
--------------------------------------------------------------------------------

-- Sekunden, die der Bonus schon waechst (0..MAX_SECONDS). `startedAt` = Zeitmarke
-- (os.time / GetServerTimeNow), nil = laeuft nicht.
function IncubatorRules.luckSeconds(startedAt: number?, now: number): number
	if typeof(startedAt) ~= "number" then return 0 end
	return math.clamp(now - startedAt, 0, IncubatorConfig.LUCK.MAX_SECONDS)
end

-- Bonus in Prozent (0..MAX_PERCENT) nach `seconds`.
function IncubatorRules.luckPercent(seconds: number): number
	local luck = IncubatorConfig.LUCK
	return math.clamp(seconds / luck.MAX_SECONDS, 0, 1) * luck.MAX_PERCENT
end

--------------------------------------------------------------------------------
-- Ausbau (Stufe 2..4): Rebirths UND Gummies
--------------------------------------------------------------------------------

export type UpgradeCost = { gummies: number, goldGummies: number, rebirths: number }

-- Voraussetzungen fuer Stufe `targetLevel` (nil = gibt es nicht).
function IncubatorRules.upgradeCost(targetLevel: number): UpgradeCost?
	if targetLevel < 2 or targetLevel > IncubatorConfig.MAX_LEVEL then return nil end
	local def = IncubatorConfig.LEVELS[targetLevel]
	local costLevel = def and def.costLevel
	local base = if costLevel then EconomyConfig.HONEY_UPGRADE_COSTS[costLevel] else nil
	if not def or not base then return nil end
	return {
		gummies     = math.floor(base.gummies * IncubatorConfig.COST_FACTOR),
		goldGummies = 0,
		rebirths    = def.rebirths or 0,
	}
end

-- Reicht der Rebirth-Stand fuer diese Stufe?
function IncubatorRules.rebirthsOk(targetLevel: number, rebirthCount: number): boolean
	local cost = IncubatorRules.upgradeCost(targetLevel)
	return cost ~= nil and rebirthCount >= cost.rebirths
end

-- 20.10. P5a: Ausbau-Voraussetzung. Flag an: Tower der Stufe komplett geschafft (Rekord >= Stages);
-- aus: alte Rebirth-Zahl. Gibt (ok, towerId?, stages?) zurueck; towerId = nil -> Rebirth-Regel.
function IncubatorRules.gateWith(flagOn: boolean, targetLevel: number, rebirthCount: number, records: { [string]: number }?): (boolean, string?, number?)
	if not flagOn then return IncubatorRules.rebirthsOk(targetLevel, rebirthCount), nil, nil end
	local towerId = IncubatorConfig.TOWER_GATE[targetLevel]
	if towerId == nil then return IncubatorRules.rebirthsOk(targetLevel, rebirthCount), nil, nil end
	local def = TowerConfig.get(towerId)
	if not def then return false, towerId, nil end
	local have = if records then (records[towerId] or 0) else 0
	return have >= def.stages, towerId, def.stages
end

function IncubatorRules.gate(targetLevel: number, rebirthCount: number, records: { [string]: number }?): (boolean, string?, number?)
	return IncubatorRules.gateWith(FeatureFlags.isOn("REBIRTH_NEEDS_WORLD2"), targetLevel, rebirthCount, records)
end

return IncubatorRules
