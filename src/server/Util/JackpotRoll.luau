--!strict
-- JackpotRoll.luau
-- ServerScriptService/Util/JackpotRoll.luau
--
-- Einzige Zustaendigkeit:
--   - Entscheiden, ob ein Abwurf ein Jackpot ist: feste Chance plus
--     Pity-Zaehler (spaetestens der n-te Versuch ist ein Jackpot).
--
-- Der Zaehler ist LAUFZEIT-Zustand des Servers (kein Spielstand, keine
-- Migration): er gilt serverweit und beginnt mit jedem neuen Server bei 0.
-- Bewusst eine reine Rechnung mit hereingereichter Zufallszahl, damit
-- tools/sim/ufo_jackpot.lua dasselbe Modul benutzen kann.

local JackpotRoll = {}

export type State = {
	sinceLast : number,    -- Versuche seit dem letzten Jackpot
	forceNext : boolean,   -- naechster Versuch ist sicher ein Jackpot (Debug)
	total     : number,    -- Versuche insgesamt (Debug/Log)
	jackpots  : number,
}

function JackpotRoll.new(): State
	return { sinceLast = 0, forceNext = false, total = 0, jackpots = 0 }
end

-- Ein Versuch. `rnd` ist eine Zufallszahl in [0, 1). `pity` = spaetestens
-- dieser Versuch (seit dem letzten Jackpot) gewinnt; nil/0 = kein Pity.
function JackpotRoll.roll(state: State, chance: number, pity: number?, rnd: number): boolean
	state.total += 1
	state.sinceLast += 1

	local hit = state.forceNext
		or rnd < chance
		or (pity ~= nil and pity > 0 and state.sinceLast >= pity)

	if hit then
		state.forceNext = false
		state.sinceLast = 0
		state.jackpots += 1
	end
	return hit
end

-- Der serverweite Zaehler fuer UFO-Abwuerfe (EventHandlers.Ufo, DebugService).
JackpotRoll.ufo = JackpotRoll.new()

return JackpotRoll
