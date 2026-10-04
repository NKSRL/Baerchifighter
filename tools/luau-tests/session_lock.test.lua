-- session_lock.test.lua — Entscheidung der Sitzungs-Sperre
-- Aufruf: cd tools/luau-tests && node run.mjs session_lock.test.lua
--
-- PlayerService fragt beim Laden und Speichern SessionLock.isHeldByOther.
-- Diese Faelle muessen stimmen, sonst laedt ein Server einen Spielstand, den
-- ein anderer noch benutzt, oder ein Spieler wird dauerhaft ausgesperrt.

local SessionLock = require(SSS.Util.SessionLock)

local fails = 0
local function check(name, got, want)
	if got ~= want then
		fails += 1
		__log("FAIL", name, "got=[" .. tostring(got) .. "] want=[" .. tostring(want) .. "]")
	else
		__log("ok  ", name)
	end
end

local NOW   = 1000000
local STALE = SessionLock.STALE_AFTER_SECONDS

check("keine Sperre",               SessionLock.isHeldByOther(nil, "A", NOW), false)
check("eigene Sperre",              SessionLock.isHeldByOther({ jobId = "A", lockedAt = NOW }, "A", NOW), false)
check("fremde, frische Sperre",     SessionLock.isHeldByOther({ jobId = "B", lockedAt = NOW - 10 }, "A", NOW), true)
check("fremde, knapp frische",      SessionLock.isHeldByOther({ jobId = "B", lockedAt = NOW - STALE + 1 }, "A", NOW), true)
check("fremde, verwaiste Sperre",   SessionLock.isHeldByOther({ jobId = "B", lockedAt = NOW - STALE }, "A", NOW), false)
check("kaputtes Feld (kein jobId)", SessionLock.isHeldByOther({ lockedAt = NOW }, "A", NOW), false)
check("kaputtes Feld (kein Datum)", SessionLock.isHeldByOther({ jobId = "B" }, "A", NOW), false)
check("Feld ist keine Tabelle",     SessionLock.isHeldByOther("B", "A", NOW), false)

local claimed = SessionLock.claim("A", NOW)
check("claim jobId",    claimed.jobId, "A")
check("claim lockedAt", claimed.lockedAt, NOW)
check("nach claim fuer A frei",    SessionLock.isHeldByOther(claimed, "A", NOW + 5), false)
check("nach claim fuer B gesperrt", SessionLock.isHeldByOther(claimed, "B", NOW + 5), true)

__log(fails == 0 and "ALLE OK" or ("FEHLER: " .. fails))
