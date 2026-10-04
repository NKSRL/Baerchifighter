--!strict
-- SessionLock.luau
-- ServerScriptService/Util/SessionLock.luau
--
-- Einzige Zustaendigkeit:
--   - Entscheiden, ob ein gespeicherter Spielstand gerade von einem ANDEREN
--     Server benutzt wird, und das Sitzungs-Feld fuer diesen Server bauen
--
-- Warum es das gibt: wechselt ein Spieler schnell den Server, kann der neue
-- Server den Spielstand laden, bevor der alte ihn beim Verlassen geschrieben
-- hat. Ohne Sperre spielen dann zwei Server mit zwei Kopien, und wer zuletzt
-- schreibt, loescht den Fortschritt des anderen. Das Feld `session` im
-- Spielstand sagt, welcher Server ihn gerade haelt und seit wann.
--
-- Bewusst eine reine Rechnung (kein DataStore, keine Zeitquelle): PlayerService
-- ruft sie INNERHALB des UpdateAsync-Rueckrufs auf, und dort darf nichts
-- yielden. Ausserdem laesst sie sich so ohne Studio testen
-- (tools/luau-tests/session_lock.test.lua).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Network.Types)

-- Nach so vielen Sekunden ohne Auffrischung gilt eine fremde Sperre als
-- verwaist (Server abgestuerzt, ohne zu speichern). Der Halter frischt sie mit
-- jedem Speichern auf, also spaetestens alle SAVE_INTERVAL (60 s) in
-- PlayerService. Drei verpasste Speicherungen sind sicher kein Zufall mehr.
local STALE_AFTER_SECONDS = 180

local SessionLock = {}

SessionLock.STALE_AFTER_SECONDS = STALE_AFTER_SECONDS

-- true = ein anderer Server haelt den Spielstand und hat sich vor kurzem
-- gemeldet. Unlesbare oder unvollstaendige Felder zaehlen als "keine Sperre":
-- lieber einmal zu viel laden als einen Spieler fuer immer aussperren.
function SessionLock.isHeldByOther(session: any, jobId: string, now: number): boolean
	if typeof(session) ~= "table" then
		return false
	end
	if typeof(session.jobId) ~= "string" or typeof(session.lockedAt) ~= "number" then
		return false
	end
	if session.jobId == jobId then
		return false
	end
	return now - session.lockedAt < STALE_AFTER_SECONDS
end

-- Das Feld, das dieser Server beim Laden und bei jedem Speichern einsetzt.
function SessionLock.claim(jobId: string, now: number): Types.SessionLock
	return { jobId = jobId, lockedAt = now }
end

return SessionLock
