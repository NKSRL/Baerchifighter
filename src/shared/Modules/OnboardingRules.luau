--!strict
-- OnboardingRules.luau
-- ReplicatedStorage/Modules/OnboardingRules.luau
--
-- Einzige Zustaendigkeit:
--   - Reine Regeln der "Reise" (P3): welche Etappe ist erfuellt, welche ist dran, was ist
--     abholbar, wie sieht der Fortschrittsbalken aus. Keine Roblox-Dienste, kein Speichern.
--
-- Etappen kommen aus dem ECHTEN Spielstand (towers.records/unlocked, stats, island) — nie aus
-- einem eigenen Zaehler. journey.claimed/skipped/hidden speichern nur, was der Spieler mit
-- der Anzeige gemacht hat, damit nichts doppelt ausgezahlt wird.
--
-- Test: tools/luau-tests/onboarding_rules.test.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local OnboardingConfig = require(ReplicatedStorage.Config.OnboardingConfig)

export type Journey = { claimed: { [string]: boolean }, skipped: { [string]: boolean }, hidden: boolean }

export type View = {
	island  : { baerchis: { [string]: any }?, equippedUid: string? }?,
	towers  : { records: { [string]: number }?, unlocked: { [string]: boolean }? }?,
	stats   : { [string]: number }?,
}

local OnboardingRules = {}

local function record(view: View, towerId: string): number
	local towers = view.towers
	local records = towers and towers.records
	return (records and tonumber(records[towerId])) or 0
end

local function unlocked(view: View, towerId: string): boolean
	local towers = view.towers
	local u = towers and towers.unlocked
	return u ~= nil and u[towerId] == true
end

local function hasBaerchi(view: View): boolean
	local stats = view.stats
	if stats and (stats.totalHatched or 0) >= 1 then return true end
	local island = view.island
	return island ~= nil and island.baerchis ~= nil and next(island.baerchis) ~= nil
end

-- Erfuellt laut Spielstand? (Fortschritt cur/target als zweiter Wert, fuer den Balken)
function OnboardingRules.progress(id: string, view: View): (number, number)
	if id == "hatch" then
		return if hasBaerchi(view) then 1 else 0, 1
	elseif id == "equip" then
		local island = view.island
		local fought = record(view, "I") >= 1
		return if hasBaerchi(view) and ((island ~= nil and island.equippedUid ~= nil) or fought) then 1 else 0, 1
	elseif id == "tower1_enter" then
		return if record(view, "I") >= 1 then 1 else 0, 1
	elseif id == "tower1_clear" then
		local target = OnboardingConfig.TOWER1_CLEAR_STAGE
		return math.min(record(view, "I"), target), target
	elseif id == "tower3_open" then
		return if unlocked(view, "III") or record(view, "III") >= 1 then 1 else 0, 1
	elseif id == "final_open" then
		return if unlocked(view, "Final") or record(view, "Final") >= 1 then 1 else 0, 1
	elseif id == "final_clear" then
		local target = OnboardingConfig.FINAL_CLEAR_STAGE
		return math.min(record(view, "Final"), target), target
	end
	return 0, 1
end

function OnboardingRules.isDone(id: string, view: View): boolean
	local cur, target = OnboardingRules.progress(id, view)
	return cur >= target
end

function OnboardingRules.defaultJourney(): Journey
	return { claimed = {}, skipped = {}, hidden = false }
end

-- Bringt ein (evtl. kaputtes) journey-Feld in Form; veraendert und gibt zurueck.
function OnboardingRules.sanitize(journey: any): Journey
	if typeof(journey) ~= "table" then return OnboardingRules.defaultJourney() end
	if typeof(journey.claimed) ~= "table" then journey.claimed = {} end
	if typeof(journey.skipped) ~= "table" then journey.skipped = {} end
	if typeof(journey.hidden) ~= "boolean" then journey.hidden = false end
	return journey :: Journey
end

-- Migration (Bestandsspieler): schon erfuellte Etappen gelten als abgeholt, OHNE Nachzahlung
-- (Entscheidung: wer das Spiel schon gespielt hat, bekommt keine nachtraeglichen Gold-Gummies;
-- das haelt die Waehrung stabil und vermeidet Abholen-Spam beim ersten Login).
function OnboardingRules.migrate(journey: any, view: View): Journey
	local j = OnboardingRules.sanitize(journey)
	for _, stage in OnboardingConfig.STAGES do
		if OnboardingRules.isDone(stage.id, view) then
			j.claimed[stage.id] = true
		end
	end
	return j
end

-- Aktuelle Etappe: die erste, die weder abgeholt noch uebersprungen ist.
-- Gibt (id, index, erfuellt) zurueck; nil, wenn die Reise fertig ist.
function OnboardingRules.current(view: View, journey: Journey): (string?, number, boolean)
	for i, stage in OnboardingConfig.STAGES do
		if not journey.claimed[stage.id] and not journey.skipped[stage.id] then
			return stage.id, i, OnboardingRules.isDone(stage.id, view)
		end
	end
	return nil, 0, false
end

-- Darf der Server diese Etappe jetzt auszahlen? (erfuellt, nicht abgeholt, bekannte ID)
function OnboardingRules.canClaim(id: any, view: View, journey: Journey): boolean
	if typeof(id) ~= "string" then return false end
	local found = false
	for _, stage in OnboardingConfig.STAGES do
		if stage.id == id then found = true break end
	end
	if not found then return false end
	if journey.claimed[id] then return false end
	return OnboardingRules.isDone(id, view)
end

function OnboardingRules.canSkip(id: any, journey: Journey): boolean
	if typeof(id) ~= "string" then return false end
	for _, stage in OnboardingConfig.STAGES do
		if stage.id == id then
			return not journey.claimed[id] and not journey.skipped[id]
		end
	end
	return false
end

-- Reise abgeschlossen? (alle Etappen abgeholt oder uebersprungen)
function OnboardingRules.isComplete(journey: Journey): boolean
	for _, stage in OnboardingConfig.STAGES do
		if not journey.claimed[stage.id] and not journey.skipped[stage.id] then return false end
	end
	return true
end

-- Etappe per Index, fuer Debug-Befehle.
function OnboardingRules.stageAt(index: number): OnboardingConfig.Stage?
	return OnboardingConfig.STAGES[index]
end

return OnboardingRules
