-- comb_respawn.lua — Fuellstand des Event-Pits mit dem Slot-Modell (Util/CombSlots).
-- Aufruf: cd tools/luau-tests && node run.mjs ../sim/comb_respawn.lua
--
-- Rechnet mit DEMSELBEN Modul wie CombService (SSS.Util.CombSlots) und den
-- Zahlen aus CombConfig. Spieler laufen eine einfache Schleife:
--   im Pit sammeln (eine Wabe pro PICK_SECONDS, solange welche da sind) bis
--   zum Ziel-Stapel → Weg zur Insel → Abgabe → Rueckweg.
-- Pro Ausflug stirbt ein Spieler mit DEATH_CHANCE (Stapel verloren → Slots
-- nach ORPHAN_RELEASE_SECONDS frei).
--
-- Prueft: im Pit nie mehr als das Limit; das Pit ist nie laenger als
-- MAX_EMPTY_SECONDS am Stueck leer, ohne dass eine neue Wabe erscheint (nie
-- "dauerhaft leer"; eine Tropfen-Wabe, die sofort aufgehoben wird, zaehlt).
-- Wer PATIENCE_SECONDS lang nichts findet, geht mit dem angefangenen Stapel.

local CombConfig = require(RS.Config.CombConfig)
local CombSlots  = require(SSS.Util.CombSlots)

local DURATION        = 600
local DT              = CombConfig.RESPAWN_TICK_SECONDS
local PICK_SECONDS    = 1.2
local TRAVEL_SECONDS  = 14     -- Pit-Rand → Plot-Insel (ein Weg)
local DEATH_CHANCE    = 0.05
local PATIENCE_SECONDS = 10    -- so lange wartet ein Spieler ohne Wabe, dann geht er mit dem, was er hat
local MAX_EMPTY_SECONDS = CombConfig.MIN_TRICKLE_SECONDS + 1

local LIMIT = CombConfig.MAX_WORLD_COMBS

local fails = 0
local function fail(...)
	fails += 1
	__log("FAIL", ...)
end

-- Einfacher, reproduzierbarer Zufall
local seed = 12345
local function rnd()
	seed = (seed * 1103515245 + 12345) % 2147483648
	return seed / 2147483648
end

local function run(playerCount, stackTarget)
	local slots = CombSlots.new()
	local world = CombConfig.INITIAL_COMBS
	local players = {}
	for i = 1, playerCount do
		-- versetzt starten, damit nicht alle gleichzeitig ankommen
		players[i] = { state = "travelIn", timer = (i - 1) * 3, carry = 0, pick = 0, idle = 0 }
	end

	local stats = { min = math.huge, max = 0, sum = 0, samples = 0, emptyRun = 0, maxEmptyRun = 0, emptySec = 0, emptySamples = 0, emptySec = 0, emptySamples = 0,
		delivered = 0, lost = 0, maxOccupied = 0 }

	local t = 0
	local nextSample = 0
	while t < DURATION do
		-- Spieler
		for _, p in players do
			if p.state == "travelIn" then
				p.timer -= DT
				if p.timer <= 0 then p.state = "pit"; p.pick = PICK_SECONDS end
			elseif p.state == "pit" then
				p.pick -= DT
				p.idle += DT
				if p.pick <= 0 and world > 0 and p.carry < stackTarget then
					world -= 1
					p.carry += 1
					p.pick = PICK_SECONDS
					p.idle = 0
				end
				if p.carry >= stackTarget or (p.carry > 0 and p.idle >= PATIENCE_SECONDS) then
					p.idle = 0
					p.state = "travelOut"; p.timer = TRAVEL_SECONDS
				end
			elseif p.state == "travelOut" then
				p.timer -= DT
				if p.timer <= 0 then
					if rnd() < DEATH_CHANCE then
						CombSlots.schedule(slots, t + CombConfig.ORPHAN_RELEASE_SECONDS, p.carry)
						stats.lost += p.carry
					else
						CombSlots.schedule(slots, t + CombConfig.getRespawnDelay(1), p.carry)
						stats.delivered += p.carry
					end
					p.carry = 0
					p.state = "travelIn"; p.timer = TRAVEL_SECONDS
				end
			end
		end

		local held = 0
		for _, p in players do held += p.carry end

		local spawned = CombSlots.tick(slots, {
			now = t, world = world, held = held, limit = LIMIT,
			refillInterval = CombConfig.SPAWN_INTERVAL_SECONDS,
			minWorld = CombConfig.MIN_WORLD_COMBS,
			trickleSeconds = CombConfig.MIN_TRICKLE_SECONDS,
		})
		world += spawned

		-- leer UND nichts Neues: zaehlt als Leerlauf
		if world == 0 and spawned == 0 then
			stats.emptyRun += DT
			if stats.emptyRun > stats.maxEmptyRun then stats.maxEmptyRun = stats.emptyRun end
		else
			stats.emptyRun = 0
		end

		if world > LIMIT then fail("ueber Limit", playerCount, stackTarget, t, world) end
		local occupied = world + held + CombSlots.pending(slots)
		if occupied > stats.maxOccupied then stats.maxOccupied = occupied end

		if t >= nextSample then
			nextSample += 1
			stats.samples += 1
			stats.sum += world
			if world < stats.min then stats.min = world end
			if world > stats.max then stats.max = world end
			if world == 0 then stats.emptySec += 1 end
		end
		t += DT
	end

	if stats.maxEmptyRun > MAX_EMPTY_SECONDS then
		fail("Pit zu lange leer", playerCount, stackTarget, stats.maxEmptyRun .. " s")
	end
	return stats
end

__log(string.format("Slot-Modell: Limit %d, Respawn %d s, Verwaist %d s, Troepfeln <%d alle %d s, Tod/Ausflug %d %%",
	LIMIT, CombConfig.RESPAWN_DELAY_SECONDS, CombConfig.ORPHAN_RELEASE_SECONDS,
	CombConfig.MIN_WORLD_COMBS, CombConfig.MIN_TRICKLE_SECONDS, DEATH_CHANCE * 100))
__log("")
__log("Spieler | Stapel | Pit min | Pit mittel | Pit max | Pit leer (Anteil) | max. Luecke ohne Wabe | abgegeben | verloren | max. belegt")
__log("--------+--------+---------+------------+---------+-------------------+-----------------------+-----------+----------+------------")
for _, n in { 1, 4, 8 } do
	for _, stack in { 5, 15, 25 } do
		local s = run(n, stack)
		__log(string.format("%7d | %6d | %7d | %10.1f | %7d | %16.0f%% | %19.1f s | %9d | %8d | %10d",
			n, stack, s.min, s.sum / s.samples, s.max, 100 * s.emptySec / s.samples, s.maxEmptyRun, s.delivered, s.lost, s.maxOccupied))
	end
end
__log("")
if fails == 0 then
	__log("OK: nie ueber Limit, nie laenger als " .. MAX_EMPTY_SECONDS .. " s leer")
end
