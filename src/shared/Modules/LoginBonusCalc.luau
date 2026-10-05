--!strict
-- LoginBonusCalc.luau
-- ReplicatedStorage/Modules/LoginBonusCalc.luau
--
-- Einzige Zustaendigkeit:
--   - Die Regeln des Login-Bonus als reine Funktionen: welcher UTC-Tag ist
--     heute, welcher Tag des Zyklus ist dran, darf abgeholt werden, wie sieht
--     der Stand nach dem Abholen aus.
--
-- Kein Spieler-Objekt, kein Speichern, keine Zufallszahl: LoginBonusService
-- ruft das auf und zahlt aus, tools/luau-tests/login_bonus.test.lua prueft
-- Tageswechsel, Gnadenfrist, Reset, Doppelklick und die Zeitzonen-Grenze.
--
-- Tage zaehlen nach UTC: utcDay = floor(os.time() / 86400). os.time() ist auf
-- dem Roblox-Server immer UTC, deshalb gibt es keine Zeitzone des Spielers, die
-- den Tag verschieben koennte — die Grenze liegt fuer alle um 00:00 UTC.

local Types            = require(script.Parent.Parent.Network.Types)
local LoginBonusConfig = require(script.Parent.Parent.Config.LoginBonusConfig)

local LoginBonusCalc = {}

function LoginBonusCalc.utcDay(now: number): number
	return math.floor(now / LoginBonusConfig.SECONDS_PER_DAY)
end

-- Sekunden bis zum naechsten UTC-Tageswechsel.
function LoginBonusCalc.secondsToReset(now: number): number
	local spd = LoginBonusConfig.SECONDS_PER_DAY
	return spd - (now % spd)
end

-- Laeuft die Serie noch? (letzte Abholung gestern oder innerhalb der Gnadenfrist)
local function streakAlive(state: Types.DailyState, today: number): boolean
	if (state.lastClaimDay or 0) <= 0 then return false end
	local gap = today - state.lastClaimDay
	return gap >= 1 and gap <= LoginBonusConfig.GRACE_DAYS
end

-- Was heute gilt.
--   day        Zyklus-Tag, der beim Abholen ausgezahlt wird (1..7)
--   claimable  heute noch nicht abgeholt
--   streak     schon abgeholte Tage im laufenden Zyklus (fuer die Anzeige)
function LoginBonusCalc.evaluate(state: Types.DailyState, now: number): (number, boolean, number)
	local today = LoginBonusCalc.utcDay(now)
	local cycle = LoginBonusConfig.CYCLE_DAYS
	local last  = state.lastClaimDay or 0
	local streak = math.clamp(math.floor(state.streak or 0), 0, cycle)

	if last == today then
		-- Heute schon abgeholt: angezeigt wird der heutige Tag als erledigt.
		local shown = if streak <= 0 then 1 else streak
		return shown, false, streak
	end

	if streakAlive(state, today) then
		-- Serie laeuft weiter; nach Tag 7 beginnt ein neuer Zyklus.
		local done = streak % cycle
		return done + 1, true, done
	end

	-- Erstes Mal oder Serie gerissen: zurueck auf Tag 1.
	return 1, true, 0
end

-- Stand nach dem Abholen. Gibt nil zurueck, wenn heute schon abgeholt wurde
-- (Doppelklick): dann darf nichts ausgezahlt werden.
function LoginBonusCalc.claim(state: Types.DailyState, now: number): (Types.DailyState?, number)
	local day, claimable = LoginBonusCalc.evaluate(state, now)
	if not claimable then
		return nil, day
	end
	return {
		lastClaimDay = LoginBonusCalc.utcDay(now),
		streak       = day,
	}, day
end

-- Die Sicht fuer den Client (Types.DailyView).
function LoginBonusCalc.buildView(state: Types.DailyState, now: number): Types.DailyView
	local day, claimable, streak = LoginBonusCalc.evaluate(state, now)
	return {
		day       = day,
		claimable = claimable,
		streak    = streak,
		resetIn   = LoginBonusCalc.secondsToReset(now),
	}
end

return LoginBonusCalc
