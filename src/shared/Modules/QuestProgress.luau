--!strict
-- QuestProgress.luau
-- ReplicatedStorage/Modules/QuestProgress.luau
--
-- Einzige Zustaendigkeit:
--   - Aus den Spielerdaten ausrechnen, wie weit jede Quest ist
--     (reine Funktionen, keine Seiteneffekte, kein Remote, kein DataStore)
--
-- Es gibt absichtlich keinen Zaehler "Quest-Fortschritt" in den Daten: der
-- Fortschritt ist immer eine Ableitung von Zaehlern, die es ohnehin gibt
-- (data.stats, Insel, Index). Daher kann er nicht von der Wahrheit abweichen
-- und andere Services muessen von Quests nichts wissen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types       = require(ReplicatedStorage.Network.Types)
local QuestConfig = require(ReplicatedStorage.Config.QuestConfig)

local QuestProgress = {}

local function count(map: { [string]: any }): number
	local n = 0
	for _ in map do n += 1 end
	return n
end

-- Gesamtwert einer Messgroesse (ohne Tagesabzug).
local function total(metric: QuestConfig.Metric, data: Types.PlayerData): number
	if metric == "hatched" then
		return data.stats.totalHatched
	elseif metric == "fightsWon" then
		return data.stats.totalFightsWon
	elseif metric == "gummiesEarned" then
		return data.stats.totalGummiesEarned
	elseif metric == "fusions" then
		return data.stats.totalFusions
	elseif metric == "baerchiCount" then
		return count(data.island.baerchis)
	elseif metric == "discovered" then
		return count(data.discovered)
	elseif metric == "buildingLevel" then
		local best = 0
		for _, building in data.island.buildings do
			best = math.max(best, building.level)
		end
		return best
	elseif metric == "pitLevel" then
		return data.island.pitLevel
	end
	return 0
end

-- Tages-Quests messen den Zuwachs; Zustands-Messgroessen (Besitz, Level) sind
-- als Tages-Quest nicht sinnvoll und werden als Gesamtwert gelesen.
local function baselineOf(metric: QuestConfig.Metric, baseline: Types.QuestBaseline): number
	if metric == "hatched" then return baseline.hatched end
	if metric == "fightsWon" then return baseline.fightsWon end
	if metric == "gummiesEarned" then return baseline.gummies end
	return 0
end

-- Aktueller Fortschritt einer Quest, auf das Ziel gedeckelt.
function QuestProgress.progressOf(def: QuestConfig.QuestDef, data: Types.PlayerData, daily: boolean): number
	local value = total(def.metric, data)
	if daily then
		value -= baselineOf(def.metric, data.quests.baseline)
	end
	return math.clamp(value, 0, def.target)
end

function QuestProgress.isComplete(def: QuestConfig.QuestDef, data: Types.PlayerData, daily: boolean): boolean
	return QuestProgress.progressOf(def, data, daily) >= def.target
end

-- Zaehlerstand fuer den Tagesbeginn.
function QuestProgress.snapshot(data: Types.PlayerData): Types.QuestBaseline
	return {
		hatched   = data.stats.totalHatched,
		fightsWon = data.stats.totalFightsWon,
		gummies   = data.stats.totalGummiesEarned,
	}
end

-- Alles, was der Client zum Anzeigen braucht.
function QuestProgress.buildView(data: Types.PlayerData, now: number): Types.QuestView
	local quests = data.quests

	local chain: Types.QuestEntry? = nil
	local nextDef = QuestConfig.CHAIN[quests.chainClaimed + 1]
	if nextDef then
		chain = {
			id       = nextDef.id,
			kind     = "chain",
			progress = QuestProgress.progressOf(nextDef, data, false),
			target   = nextDef.target,
			claimed  = false,
		}
	end

	local daily: { Types.QuestEntry } = {}
	for _, def in QuestConfig.DAILY do
		table.insert(daily, {
			id       = def.id,
			kind     = "daily",
			progress = QuestProgress.progressOf(def, data, true),
			target   = def.target,
			claimed  = quests.dailyClaimed[def.id] == true,
		})
	end

	return {
		chain        = chain,
		chainDone    = math.min(quests.chainClaimed, #QuestConfig.CHAIN),
		chainTotal   = #QuestConfig.CHAIN,
		daily        = daily,
		dailyResetIn = QuestConfig.secondsUntilReset(now),
	}
end

return QuestProgress
