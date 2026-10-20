--!strict
-- EpilogRules.luau
-- ReplicatedStorage/Modules/EpilogRules.luau
--
-- Einzige Zustaendigkeit:
--   - Die Regeln des Final-Epilogs als reine Funktionen auf dem Spielstand-Teil
--     `epilog` / `worlds`: erlaubte Zustandswechsel, atomares Speichern beim
--     Final-100-Sieg, Migration, Token-Pruefung.
--     Test: tools/luau-tests/epilog_state.test.lua. EpilogService ruft nur diese auf.
--
-- Bewusst ohne Roblox-Dienste (Zeit und GUID kommen als Parameter), damit der
-- Test ohne Attrappe laeuft. Nur der Server ruft Schreibfunktionen auf.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EpilogConfig = require(ReplicatedStorage.Config.EpilogConfig)

local EpilogRules = {}

local S = EpilogConfig.STATE

-- Erlaubte Uebergaenge. Rueckwaerts gibt es nur ueber reset() (Debug).
local ALLOWED: { [string]: { [string]: boolean } } = {
	[S.NONE]     = { [S.PENDING] = true },
	[S.PENDING]  = { [S.SEEN] = true },
	[S.SEEN]     = { [S.LAUNCHED] = true },
	[S.LAUNCHED] = {},
}

function EpilogRules.isValidState(value: any): boolean
	return typeof(value) == "string" and ALLOWED[value] ~= nil
end

-- Neuer, leerer Teil fuer den Spielstand.
function EpilogRules.newEpilog(): any
	return { state = S.NONE }
end

function EpilogRules.newWorlds(): any
	return { unlocked = {} }
end

function EpilogRules.canTransition(from: string, to: string): boolean
	local row = ALLOWED[from]
	return row ~= nil and row[to] == true
end

-- Zustandswechsel. false = ungueltig (nichts geaendert).
function EpilogRules.transition(epilog: any, to: string, now: number): boolean
	if not EpilogRules.canTransition(epilog.state, to) then return false end
	epilog.state = to
	if to == S.PENDING and epilog.firstClearAt == nil then
		epilog.firstClearAt = now
	elseif to == S.LAUNCHED then
		epilog.launchedAt = now
	end
	return true
end

-- Ist das der Sieg, der den Epilog ausloest? Nur Final, nur die volle
-- Stage-Zahl (`finalStages` = TowerConfig-Stage-Zahl des Final-Towers).
function EpilogRules.isTrigger(towerId: string, stage: number, finalStages: number): boolean
	return towerId == EpilogConfig.TOWER_ID and stage >= finalStages
end

-- Phase 2 + 3: der Final-100-Sieg. Ein einziger Schreibvorgang auf den Daten:
--   Endless offen (towers.unlocked.Endless), epilog.state = pending (nur bei
--   "none"), firstClearAt. Gibt true zurueck, wenn eine NEUE Sequenz startet
--   (state war "none"). Jeder weitere Aufruf aendert den Zustand nicht, setzt
--   aber Endless weiter (idempotent) und liefert false.
function EpilogRules.applyFinalClear(data: any, now: number): boolean
	local towers = data.towers
	if typeof(towers.unlocked) ~= "table" then towers.unlocked = {} end
	towers.unlocked.Endless = true

	if typeof(data.epilog) ~= "table" then data.epilog = EpilogRules.newEpilog() end
	if data.epilog.state ~= S.NONE then return false end
	local started = EpilogRules.transition(data.epilog, S.PENDING, now)
	if started then data.epilog.firstClearAt = now end
	return started
end

-- Knopf: seen -> launched und Welt 2 frei, in EINER Mutation. false = nicht
-- erlaubt (state ist nicht "seen"); Welt 2 bleibt dann zu.
function EpilogRules.applyLaunch(data: any, now: number): boolean
	if not EpilogRules.transition(data.epilog, S.LAUNCHED, now) then return false end
	if typeof(data.worlds) ~= "table" then data.worlds = EpilogRules.newWorlds() end
	if typeof(data.worlds.unlocked) ~= "table" then data.worlds.unlocked = {} end
	data.worlds.unlocked[EpilogConfig.WORLD2_ID] = true
	return true
end

-- Debug: zurueck auf "none" (Welt 2 und Endless bleiben, nichts geht verloren).
function EpilogRules.reset(epilog: any)
	epilog.state = S.NONE
	epilog.firstClearAt = nil
	epilog.launchedAt = nil
end

-- Migration auf v18 (idempotent, am Feld erkennbar). `finalRecord` = Rekord
-- im Final-Tower. Bestandsspieler mit Final >= finalStages bekommen "pending"
-- (Epilog nachholen); alle anderen "none". Ein vorhandener, gueltiger Stand
-- bleibt unangetastet, Muell wird repariert.
function EpilogRules.migrate(data: any, finalRecord: number, finalStages: number, now: number)
	local epilog = data.epilog
	if typeof(epilog) ~= "table" then
		epilog = EpilogRules.newEpilog()
		data.epilog = epilog
		if finalRecord >= finalStages then
			EpilogRules.transition(epilog, S.PENDING, now)
		end
	end
	if not EpilogRules.isValidState(epilog.state) then
		epilog.state = if finalRecord >= finalStages then S.PENDING else S.NONE
	end
	if typeof(epilog.firstClearAt) ~= "number" then epilog.firstClearAt = nil end
	if typeof(epilog.launchedAt) ~= "number" then epilog.launchedAt = nil end
	if epilog.state == S.PENDING and epilog.firstClearAt == nil then epilog.firstClearAt = now end

	local worlds = data.worlds
	if typeof(worlds) ~= "table" then
		worlds = EpilogRules.newWorlds()
		data.worlds = worlds
	end
	if typeof(worlds.unlocked) ~= "table" then worlds.unlocked = {} end
	for id, flag in worlds.unlocked do
		if flag ~= true or id ~= EpilogConfig.WORLD2_ID then worlds.unlocked[id] = nil end
	end
	-- Konsistenz: "launched" heisst Welt 2 ist frei (auch nach Datenreparatur).
	if epilog.state == S.LAUNCHED then worlds.unlocked[EpilogConfig.WORLD2_ID] = true end
end

--------------------------------------------------------------------------------
-- Token (nur im Speicher des Servers, nie gespeichert)
--------------------------------------------------------------------------------

-- Neues Token fuer genau diesen Spieler (userId) zum Zeitpunkt `now`.
function EpilogRules.newToken(guid: string, userId: number, now: number): any
	return { id = guid, userId = userId, issuedAt = now, seenUsed = false }
end

-- Prueft ein Token fuer eine Aktion ("seen" | "skip" | "press"). Gibt
-- true oder false + Grund zurueck. Verbraucht nichts (das macht der Aufrufer
-- erst nach erfolgreicher Aktion, siehe consumeSeen).
function EpilogRules.checkToken(entry: any, given: any, userId: number, action: string, now: number): (boolean, string)
	if entry == nil then return false, "no_token" end
	if typeof(given) ~= "string" or given ~= entry.id then return false, "wrong_token" end
	if entry.userId ~= userId then return false, "other_player" end
	local age = now - entry.issuedAt
	if action == "seen" then
		if entry.seenUsed then return false, "already_used" end
		if age < EpilogConfig.SEEN_MIN_SECONDS then return false, "too_early" end
		if age > EpilogConfig.SEEN_MAX_SECONDS then return false, "expired" end
	end
	return true, "ok"
end

function EpilogRules.consumeSeen(entry: any)
	entry.seenUsed = true
end

return EpilogRules
