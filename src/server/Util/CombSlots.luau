--!strict
-- CombSlots.luau
-- ServerScriptService/Util/CombSlots.luau
--
-- Einzige Zustaendigkeit:
--   - Das Slot-Modell der Honigwaben rechnen: Respawn-Warteschlange (sortiert
--     nach Faelligkeit) und die Entscheidung, wie viele Waben in diesem Takt
--     neu ins Pit kommen.
--
-- Das Pit hat eine feste Zahl Slots (CombConfig.MAX_WORLD_COMBS bzw. das Limit
-- eines Wabenthemas). Belegt ist ein Slot von einer Wabe im Pit, einer
-- getragenen Wabe oder einem Eintrag in der Warteschlange (abgegeben oder
-- verloren, wartet auf Respawn). Drei Wege fuehren zu einer neuen Wabe:
--
--   1. RESPAWN: ein Warteschlangen-Eintrag ist faellig. Ist der Server gerade
--      ueberbelegt (Tropfen-Waben, gesunkenes Limit), verfaellt er, statt zu
--      spawnen — so pendelt die Belegung zurueck auf das Limit.
--   2. NACHFUELLEN: es gibt freie Slots (Serverstart, gestiegenes Limit,
--      Spawn ohne Platz). Eine Wabe pro `refillInterval`.
--   3. TROEPFELN: liegen weniger als `minWorld` im Pit, eine Wabe pro
--      `trickleSeconds`, auch wenn alle Slots belegt sind.
--
-- Im Pit liegen nie mehr als `limit` Waben.
--
-- Bewusst eine reine Rechnung (keine Instanzen, keine Zeitquelle): CombService
-- fuehrt die Spawns aus, tools/sim/comb_respawn.lua rechnet mit demselben Modul.

local CombSlots = {}

export type State = {
	queue       : { number },   -- Faelligkeitszeiten, aufsteigend sortiert
	nextRefill  : number,
	lastTrickle : number,
}

export type TickInput = {
	now            : number,
	world          : number,   -- Waben gerade im Pit
	held           : number,   -- Waben gerade auf Koepfen
	limit          : number,   -- Slot-Zahl (= Hoechstzahl im Pit)
	refillInterval : number,
	minWorld       : number,
	trickleSeconds : number,
}

function CombSlots.new(): State
	return { queue = {}, nextRefill = 0, lastTrickle = -math.huge }
end

-- Traegt `count` Eintraege mit Faelligkeit `dueAt` ein (sortiert einfuegen;
-- die Liste ist klein, lineares Einfuegen reicht).
function CombSlots.schedule(state: State, dueAt: number, count: number)
	local queue = state.queue
	for _ = 1, math.max(0, math.floor(count)) do
		local index = #queue + 1
		while index > 1 and queue[index - 1] > dueAt do
			index -= 1
		end
		table.insert(queue, index, dueAt)
	end
end

function CombSlots.pending(state: State): number
	return #state.queue
end

-- Wie viele Waben sollen JETZT neu ins Pit? Nimmt faellige Eintraege aus der
-- Warteschlange und stellt die Zeitgeber weiter. Der Aufrufer spawnt genau so
-- viele (scheitert ein Spawn, fehlt der Slot und wird nachgefuellt).
function CombSlots.tick(state: State, input: TickInput): number
	local spawn = 0
	local queue = state.queue

	local function occupied(): number
		return input.world + spawn + input.held + #queue
	end

	-- 1. Faellige Respawns
	while queue[1] ~= nil and queue[1] <= input.now do
		table.remove(queue, 1)
		if occupied() < input.limit and input.world + spawn < input.limit then
			spawn += 1
		end
	end

	-- 2. Freie Slots nachfuellen
	if occupied() < input.limit
		and input.world + spawn < input.limit
		and input.now >= state.nextRefill
	then
		spawn += 1
		state.nextRefill = input.now + input.refillInterval
	end

	-- 3. Mindest-Troepfeln
	if input.world + spawn < input.minWorld
		and input.world + spawn < input.limit
		and input.now - state.lastTrickle >= input.trickleSeconds
	then
		spawn += 1
		state.lastTrickle = input.now
	end

	return spawn
end

return CombSlots
