-- ufo_jackpot.lua — Jackpots aus UFO-Abwuerfen pro Serverstunde, mit und ohne Pity.
-- Aufruf: cd tools/luau-tests && node run.mjs ../sim/ufo_jackpot.lua
--
-- Rechnet mit demselben Modul wie der Server (SSS.Util.JackpotRoll) und den
-- Zahlen aus EventConfig.UFO. Ein UFO-Event pro Durchlauf des Zyklus, je
-- Event so viele Abwuerfe, wie zwischen DROP_FIRST und Event-Ende passen.
-- Annahme: jede Kiste wird aufgehoben (die Chance haengt am Abwurf, nicht am
-- Aufheben).
--
-- Zykluslaengen: 41 und 46 min wie im Auftrag, dazu die aus EventConfig
-- berechneten Werte (ohne Boss / mit Boss inkl. Pause) und der Wechsel beider.

local EventConfig = require(RS.Config.EventConfig)
local JackpotRoll = require(SSS.Util.JackpotRoll)

local cfg = EventConfig.UFO
local ufoDef = EventConfig.getById("Ufo")
local duration = EventConfig.getDuration(ufoDef)

local dropsPerEvent = 0
do
	local t = cfg.DROP_FIRST_SECONDS
	while t < duration do
		dropsPerEvent += 1
		t += cfg.DROP_INTERVAL_SECONDS
	end
end

-- Zykluslaenge aus der Config (Sekunden) fuer Durchlauf `cycle`.
local function cycleSeconds(cycle)
	local total = 0
	for _, def in EventConfig.EVENTS do
		if EventConfig.isScheduledInCycle(def, cycle) then
			total += EventConfig.EVENT_GAP_SECONDS + EventConfig.getDuration(def)
		end
	end
	return total
end

local fails = 0
local function check(ok, msg)
	if not ok then fails += 1; __log("FAIL " .. msg) end
end

math.randomseed(4242)
local HOURS = 20000

local function simulate(cycleMinutesList, withPity)
	local state = JackpotRoll.new()
	local pity = if withPity then cfg.JACKPOT_PITY_DROPS else nil
	local seconds = HOURS * 3600
	local t, i, drops, maxGap = 0, 0, 0, 0
	local hoursWithJackpot = {}
	while t < seconds do
		i += 1
		local cycle = cycleMinutesList[(i - 1) % #cycleMinutesList + 1] * 60
		for d = 1, dropsPerEvent do
			drops += 1
			local before = state.sinceLast
			if JackpotRoll.roll(state, cfg.JACKPOT_CHANCE, pity, math.random()) then
				if before + 1 > maxGap then maxGap = before + 1 end
				hoursWithJackpot[math.floor(t / 3600)] = true
			end
		end
		t += cycle
	end
	local hoursHit = 0
	for _ in hoursWithJackpot do hoursHit += 1 end
	return {
		perHour = state.jackpots / HOURS,
		dropsPerHour = drops / HOURS,
		hoursPerJackpot = HOURS / math.max(1, state.jackpots),
		maxGap = maxGap,
		hourShare = hoursHit / HOURS,
	}
end

local noBoss = cycleSeconds(1) / 60
local withBoss = cycleSeconds(2) / 60

__log(string.format("UFO: %d Abwuerfe je Event (erster nach %d s, dann alle %d s), Jackpot %.1f %%, Pity %d",
	dropsPerEvent, cfg.DROP_FIRST_SECONDS, cfg.DROP_INTERVAL_SECONDS, cfg.JACKPOT_CHANCE * 100, cfg.JACKPOT_PITY_DROPS))
__log(string.format("Zyklus laut EventConfig: ohne Boss %.1f min, mit Boss %.1f min (inkl. Pause), Mittel %.1f min",
	noBoss, withBoss, (noBoss + withBoss) / 2))
__log(string.format("Simulation: %d Serverstunden je Zeile", HOURS))
__log("")
__log("Zyklus              | Pity | Abwuerfe/h | Jackpots/h | Std. je Jackpot | Std. mit Jackpot | max. Abwuerfe bis Jackpot")
__log("--------------------+------+------------+------------+-----------------+------------------+--------------------------")

local rows = {
	{ "41 min (Auftrag)", { 41 } },
	{ "46 min (Auftrag)", { 46 } },
	{ string.format("Config %.0f/%.0f Wechsel", noBoss, withBoss), { noBoss, withBoss } },
}
for _, row in rows do
	for _, pity in { false, true } do
		local r = simulate(row[2], pity)
		__log(string.format("%-19s | %-4s | %10.2f | %10.3f | %15.1f | %15.0f%% | %25d",
			row[1], if pity then "ja" else "nein", r.dropsPerHour, r.perHour, r.hoursPerJackpot, r.hourShare * 100, r.maxGap))
		if pity then
			check(r.maxGap <= cfg.JACKPOT_PITY_DROPS, "Pity verletzt: " .. r.maxGap .. " Abwuerfe ohne Jackpot")
		end
	end
end

-- Erwartungswert mit Pity: mittlere Abwuerfe je Jackpot = (1 - q^P) / p
local p, q, P = cfg.JACKPOT_CHANCE, 1 - cfg.JACKPOT_CHANCE, cfg.JACKPOT_PITY_DROPS
local expected = (1 - q ^ P) / p
__log("")
__log(string.format("Rechnerisch: ohne Pity %.0f Abwuerfe je Jackpot, mit Pity %.1f (Anteil Pity-Jackpots %.0f %%)",
	1 / p, expected, 100 * q ^ (P - 1)))
if fails == 0 then __log("OK: Pity greift spaetestens beim " .. P .. ". Abwurf") end
