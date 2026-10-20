-- epilog_rules.test.lua — 20.10. Final-Epilog, Prompt 7 (Haertung der Server-Regeln)
-- python tools/luau-tests/run_local.py tools/luau-tests/epilog_rules.test.lua
--
-- Prueft die reinen Regeln aus Modules/EpilogRules, die EpilogService fuer Knopf und Remotes nutzt:
--   1. Token: fehlt / falsch / fremder Spieler / Typfehler / zu frueh / abgelaufen / doppelt (Seen)
--   2. Knopf-Abstand: < 14 Studs erlaubt, ab 14 und NaN/fehlende Halterung abgelehnt
--   3. Rate-Limit: zweiter Druck innerhalb der Abklingzeit abgelehnt, danach wieder erlaubt
--   4. Doppeldruck: laeuft das Finale schon, ist jeder weitere Druck wirkungslos
--   5. Doppel-Clear-Race: zwei Final-Siege kurz hintereinander = genau eine Sequenz
--   6. Spoofing: Remote-Aufrufe ohne Token / im falschen Zustand aendern nichts
--   7. Reihenfolge der Pruefungen (Grund stimmt)

local EpilogRules  = require(RS.Modules.EpilogRules)
local EpilogConfig = require(RS.Config.EpilogConfig)

local F = EpilogConfig.FINALE
local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else
		failures += 1
		print("FAIL " .. name .. (if detail ~= nil then ": " .. tostring(detail) else ""))
	end
end

local function good(over)
	local i = { enabled = true, hasData = true, running = false, allowed = true, hasTerminal = true,
		alive = true, force = false, sinceLastPress = nil, distance = 3 }
	for k, v in over or {} do i[k] = v end
	return i
end
local function press(over) return EpilogRules.checkPress(good(over), F.pressMaxDistance, F.pressCooldownSeconds) end

-- 2. Abstand --------------------------------------------------------------
check("Vertrag: Abstand 14 Studs, Abklingzeit > 0", F.pressMaxDistance == 14 and F.pressCooldownSeconds > 0)
check("Druck direkt am Terminal erlaubt", (press({ distance = 0 })))
check("Abstand 13.9 erlaubt", (press({ distance = 13.9 })))
local ok14, why14 = press({ distance = 14 })
check("Abstand 14 abgelehnt", ok14 == false and why14 == "too_far", why14)
check("Abstand 80 (Teleport/Speed-Hack) abgelehnt", select(2, press({ distance = 80 })) == "too_far")
check("Abstand NaN abgelehnt", select(2, press({ distance = 0 / 0 })) == "too_far")
local noMount = good(); noMount.distance = nil   -- Halterung fehlt
check("Abstand fehlt (keine Halterung) abgelehnt", select(2, EpilogRules.checkPress(noMount, F.pressMaxDistance, F.pressCooldownSeconds)) == "too_far")
check("Debug force ignoriert Abstand", (press({ distance = 500, force = true })))

-- 3. Rate-Limit -----------------------------------------------------------
check("noch nie gedrueckt: erlaubt", (press({ sinceLastPress = nil })))
check("Druck 0.1 s nach dem letzten: Rate-Limit", select(2, press({ sinceLastPress = 0.1 })) == "rate_limit")
check("Druck knapp vor Ablauf: Rate-Limit", select(2, press({ sinceLastPress = F.pressCooldownSeconds - 0.01 })) == "rate_limit")
check("Druck nach Ablauf: erlaubt", (press({ sinceLastPress = F.pressCooldownSeconds + 0.01 })))
check("Debug force ignoriert Rate-Limit", (press({ sinceLastPress = 0, force = true })))

-- Ablauf wie in EpilogService.startFinale: erst pruefen, dann Zeitstempel setzen
local last, clock = nil, 100
local function attempt(distance)
	local ok = EpilogRules.checkPress(good({ distance = distance, sinceLastPress = if last then clock - last else nil }),
		F.pressMaxDistance, F.pressCooldownSeconds)
	last = clock
	return ok
end
check("erster echter Druck wird NICHT an sich selbst abgelehnt", attempt(3) == true)
clock += 0.2
check("Spam 0.2 s spaeter abgelehnt", attempt(3) == false)
clock += 0.2
check("Spam-Versuche halten das Limit am Leben", attempt(3) == false)
clock += F.pressCooldownSeconds + 0.1
check("nach Ruhe wieder erlaubt", attempt(3) == true)

-- 4. Doppeldruck ----------------------------------------------------------
local okRun, whyRun = press({ running = true })
check("laeuft das Finale: weiterer Druck wirkungslos", okRun == false and whyRun == "already_running", whyRun)
check("laeuft das Finale: auch mit force wirkungslos", select(2, press({ running = true, force = true })) == "already_running")

-- 7. Pruefreihenfolge / Gruende ------------------------------------------
check("Schalter aus", select(2, press({ enabled = false })) == "disabled")
check("keine Daten", select(2, press({ hasData = false })) == "no_data")
check("Zustand nicht erlaubt (Remote-Spoof vor dem Sieg)", select(2, press({ allowed = false })) == "state_not_allowed")
check("kein Terminal", select(2, press({ hasTerminal = false })) == "no_terminal")
check("tot", select(2, press({ alive = false })) == "dead")

-- 5. Doppel-Clear-Race ----------------------------------------------------
local d = { towers = { records = { Final = 100 }, unlocked = {} }, epilog = EpilogRules.newEpilog(), worlds = EpilogRules.newWorlds() }
local a1 = EpilogRules.applyFinalClear(d, 1000)
local a2 = EpilogRules.applyFinalClear(d, 1000.001)
local a3 = EpilogRules.applyFinalClear(d, 1000.002)
check("zwei/drei Siege direkt hintereinander = genau eine Sequenz", a1 == true and a2 == false and a3 == false)
check("State bleibt pending, firstClearAt unveraendert", d.epilog.state == "pending" and d.epilog.firstClearAt == 1000)

-- 1. + 6. Token / Spoofing ------------------------------------------------
local T0 = 5000
local tok = EpilogRules.newToken("guid-1", 7, T0)
local function chk(given, uid, action, dt) return EpilogRules.checkToken(tok, given, uid, action, T0 + dt) end
for _, action in { "seen", "skip", "press" } do
	check("ohne Token wirkungslos (" .. action .. ")", not (EpilogRules.checkToken(nil, "guid-1", 7, action, T0 + 100)))
	check("falsches Token wirkungslos (" .. action .. ")", not (chk("guid-2", 7, action, 100)))
	check("Nicht-String als Token wirkungslos (" .. action .. ")", not (chk(12345, 7, action, 100)) and not (chk({}, 7, action, 100))
		and not (chk(true, 7, action, 100)) and not (chk(nil, 7, action, 100)))
	check("Token eines anderen Spielers wirkungslos (" .. action .. ")", not (chk("guid-1", 8, action, 100)))
end
check("Seen: zu frueh abgelehnt", select(2, chk("guid-1", 7, "seen", EpilogConfig.SEEN_MIN_SECONDS - 0.5)) == "too_early")
check("Seen: im Fenster angenommen", (chk("guid-1", 7, "seen", EpilogConfig.SEEN_MIN_SECONDS + 0.5)))
check("Seen: abgelaufen abgelehnt", select(2, chk("guid-1", 7, "seen", EpilogConfig.SEEN_MAX_SECONDS + 1)) == "expired")
EpilogRules.consumeSeen(tok)
check("Seen: zweiter Aufruf abgelehnt", select(2, chk("guid-1", 7, "seen", EpilogConfig.SEEN_MIN_SECONDS + 1)) == "already_used")

-- Spoofing im falschen Zustand: Knopf-Regeln aendern den Spielstand nicht
local s = { towers = { records = {}, unlocked = {} }, epilog = EpilogRules.newEpilog(), worlds = EpilogRules.newWorlds() }
check("Knopf bei none: Welt 2 bleibt zu", EpilogRules.applyLaunch(s, 1) == false and s.worlds.unlocked.World2 == nil)
EpilogRules.applyFinalClear(s, 2)
check("Knopf bei pending (Seen nie bestaetigt): Welt 2 bleibt zu", EpilogRules.applyLaunch(s, 3) == false
	and s.worlds.unlocked.World2 == nil and s.epilog.state == "pending")
check("Seen->none/pending rueckwaerts unmoeglich", not EpilogRules.transition(s.epilog, "none", 4) and s.epilog.state == "pending")
check("Sprung pending->launched unmoeglich", not EpilogRules.transition(s.epilog, "launched", 4) and s.worlds.unlocked.World2 == nil)

if failures > 0 then error(failures .. " Test(s) fehlgeschlagen") end
print("epilog_rules: alle Tests gruen")
