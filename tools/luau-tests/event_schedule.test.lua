-- event_schedule.test.lua — HBB Paket 6: Zeit bis zur Wespenkoenigin
-- python tools/luau-tests/run_local.py tools/luau-tests/event_schedule.test.lua
--
-- EventConfig.secondsUntilStart gegen die Zahlen aus
-- docs/HBB_PAKET_6_UMGESETZT_2026-10-05.md (frischer Server: erster Boss nach
-- 87,0 min bei 300 s erster Pause, 83,2 min bei 75 s) und gegen Grundregeln.

local EventConfig = rbxRequire("ReplicatedStorage/Config/EventConfig")

local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else
		failures += 1
		print("FAIL " .. name .. (if detail then ": " .. tostring(detail) else ""))
	end
end

local BOSS = "WaspQueen"
check("WaspQueen gibt es", EventConfig.getById(BOSS) ~= nil)

local fresh300 = EventConfig.secondsUntilStart(BOSS, nil, 300, 1, 1)
check("frischer Server, Pause 300 s: 87,0 min", fresh300 and math.abs(fresh300 / 60 - 87.0) < 0.05, fresh300 and fresh300 / 60)
local fresh75 = EventConfig.secondsUntilStart(BOSS, nil, EventConfig.FIRST_GAP_SECONDS, 1, 1)
check("frischer Server, Pause 75 s: 83,2 min", fresh75 and math.abs(fresh75 / 60 - 83.25) < 0.1, fresh75 and fresh75 / 60)

check("laeuft gerade: 0", EventConfig.secondsUntilStart(BOSS, BOSS, 120, 1, 2) == 0)

-- Index des Bosses und Stand "Pause direkt vor dem Boss" (in seinem Durchlauf)
local bossIndex
for i, def in EventConfig.EVENTS do
	if def.id == BOSS then bossIndex = i end
end
local cycle = EventConfig.getById(BOSS).everyNthCycle or 1   -- Durchlauf, in dem der Boss laeuft
check("Pause vor dem Boss: Restzeit", EventConfig.secondsUntilStart(BOSS, nil, 42, bossIndex, cycle) == 42)

-- Gleich nach dem Boss: eine ganze Periode (91 min) minus die Boss-Dauer
local period = 0
for c = 1, 2 do
	for _, def in EventConfig.EVENTS do
		if EventConfig.isScheduledInCycle(def, c) then
			period += EventConfig.getDuration(def) + EventConfig.EVENT_GAP_SECONDS
		end
	end
end
check("Periode 91 min", math.abs(period / 60 - 91) < 0.01, period / 60)
local afterBoss = EventConfig.secondsUntilStart(BOSS, nil, EventConfig.EVENT_GAP_SECONDS, 1, cycle + 1)
check("nach dem Boss: Periode - Bossdauer",
	afterBoss == period - EventConfig.getDuration(EventConfig.getById(BOSS)), afterBoss)

check("unbekanntes Event: nil", EventConfig.secondsUntilStart("GibtsNicht", nil, 10, 1, 1) == nil)

if failures > 0 then error(failures .. " Fehler", 0) end
print("event_schedule: alle Tests gruen")
