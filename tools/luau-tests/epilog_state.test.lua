-- epilog_state.test.lua — 20.10. Final-Epilog, Prompt 1 (Siegeslogik, Datenmodell)
-- python tools/luau-tests/run_local.py tools/luau-tests/epilog_state.test.lua
--
-- Prueft Modules/EpilogRules (die reinen Regeln, die EpilogService benutzt):
--   1. Zustandsautomat none -> pending -> seen -> launched, ungueltige Uebergaenge
--   2. Final-100-Sieg: ein Schreibvorgang (Endless + pending + firstClearAt)
--   3. Doppel-Clear / Race: nur eine Sequenz; Reset erlaubt eine neue
--   4. Knopf: nur aus "seen", Welt 2 gleichzeitig
--   5. Token: richtig/falsch/anderer Spieler/zu frueh/abgelaufen/schon benutzt
--   6. Migration-Regeln (Rekord >= 100 -> pending, Muell reparieren, idempotent)
--   7. Config-Vertrag: Zustandsnamen, Remote-Namen, Schalter existiert
-- Der Spielstand-Fall v17 -> v18 steht in migration_hbb.test.lua (Block K).

local EpilogRules  = require(RS.Modules.EpilogRules)
local EpilogConfig = require(RS.Config.EpilogConfig)
local FeatureFlags = require(RS.Config.FeatureFlags)
local TowerConfig  = require(RS.Config.TowerConfig)
local Remotes      = nil

local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else
		failures += 1
		print("FAIL " .. name .. (if detail ~= nil then ": " .. tostring(detail) else ""))
	end
end

local function newData()
	return { towers = { records = { Final = 100 }, unlocked = { I = true } },
		epilog = EpilogRules.newEpilog(), worlds = EpilogRules.newWorlds() }
end

local FINAL_STAGES = TowerConfig.get("Final").stages

-- 7. Vertrag -------------------------------------------------------------
check("Final hat 100 Stages", FINAL_STAGES == 100, FINAL_STAGES)
-- Seit 20.10. ist der Schalter an; geprueft wird nur, dass es ihn gibt.
check("Schalter FINAL_EPILOG existiert", type(FeatureFlags.FLAGS.FINAL_EPILOG) == "boolean",
	tostring(FeatureFlags.FLAGS.FINAL_EPILOG))
check("Zustandsnamen", EpilogConfig.STATE.NONE == "none" and EpilogConfig.STATE.PENDING == "pending"
	and EpilogConfig.STATE.SEEN == "seen" and EpilogConfig.STATE.LAUNCHED == "launched")
check("Remote-Namen laut Vertrag", EpilogConfig.REMOTES.START == "EpilogStart" and EpilogConfig.REMOTES.SEEN == "EpilogSeen"
	and EpilogConfig.REMOTES.SKIP == "EpilogSkip" and EpilogConfig.REMOTES.PRESS_LAUNCH == "RequestPressLaunch"
	and EpilogConfig.REMOTES.LAUNCH_RESULT == "EpilogLaunchResult" and EpilogConfig.REMOTES.WORLD2 == "World2Unlocked")

-- 1. Automat -------------------------------------------------------------
check("none -> pending erlaubt", EpilogRules.canTransition("none", "pending"))
check("pending -> seen erlaubt", EpilogRules.canTransition("pending", "seen"))
check("seen -> launched erlaubt", EpilogRules.canTransition("seen", "launched"))
check("none -> seen verboten", not EpilogRules.canTransition("none", "seen"))
check("none -> launched verboten", not EpilogRules.canTransition("none", "launched"))
check("pending -> launched verboten", not EpilogRules.canTransition("pending", "launched"))
check("seen -> pending verboten", not EpilogRules.canTransition("seen", "pending"))
check("launched -> irgendwas verboten", not EpilogRules.canTransition("launched", "none")
	and not EpilogRules.canTransition("launched", "pending") and not EpilogRules.canTransition("launched", "seen"))
check("unbekannter Zustand ungueltig", not EpilogRules.isValidState("banane") and not EpilogRules.isValidState(5))

local e = EpilogRules.newEpilog()
check("ungueltiger Wechsel aendert nichts", not EpilogRules.transition(e, "launched", 1) and e.state == "none")

-- 2. Trigger + atomarer Sieg --------------------------------------------
check("Final 100 ist Trigger", EpilogRules.isTrigger("Final", 100, FINAL_STAGES))
check("Final 99 ist kein Trigger", not EpilogRules.isTrigger("Final", 99, FINAL_STAGES))
check("Tower III 60 ist kein Trigger", not EpilogRules.isTrigger("III", 60, 60))
check("Endless 100 ist kein Trigger", not EpilogRules.isTrigger("Endless", 100, FINAL_STAGES))

local d = newData()
local started = EpilogRules.applyFinalClear(d, 1000)
check("Sieg startet Sequenz", started == true)
check("-> state pending", d.epilog.state == "pending", d.epilog.state)
check("-> Endless offen", d.towers.unlocked.Endless == true)
check("-> firstClearAt gesetzt", d.epilog.firstClearAt == 1000)
check("-> Welt 2 noch zu", d.worlds.unlocked.World2 == nil)

-- 3. Doppel-Clear -------------------------------------------------------
local again = EpilogRules.applyFinalClear(d, 2000)
check("zweiter Sieg startet nichts", again == false)
check("zweiter Sieg laesst firstClearAt", d.epilog.firstClearAt == 1000)
check("zweiter Sieg laesst state", d.epilog.state == "pending")
d.epilog.state = "seen"
check("Sieg bei seen startet nichts", EpilogRules.applyFinalClear(d, 3000) == false and d.epilog.state == "seen")

-- 4. Knopf --------------------------------------------------------------
local p = newData()
EpilogRules.applyFinalClear(p, 1)
check("Knopf bei pending verboten", EpilogRules.applyLaunch(p, 5) == false)
check("Welt 2 bleibt zu bei pending", p.worlds.unlocked.World2 == nil and p.epilog.state == "pending")
check("Knopf bei none verboten", EpilogRules.applyLaunch(newData(), 5) == false)
EpilogRules.transition(p.epilog, "seen", 2)
check("Knopf bei seen erlaubt", EpilogRules.applyLaunch(p, 9) == true)
check("-> launched + launchedAt", p.epilog.state == "launched" and p.epilog.launchedAt == 9)
check("-> Welt 2 gleichzeitig frei", p.worlds.unlocked.World2 == true)
check("zweiter Knopf verboten", EpilogRules.applyLaunch(p, 10) == false)
check("launched ist endgueltig (Sieg startet nichts)", EpilogRules.applyFinalClear(p, 11) == false and p.epilog.state == "launched")

-- Reset (Debug): Endless/Welt 2 bleiben, neue Sequenz moeglich
EpilogRules.reset(p.epilog)
check("Reset -> none ohne Zeiten", p.epilog.state == "none" and p.epilog.firstClearAt == nil and p.epilog.launchedAt == nil)
check("Reset laesst Welt 2", p.worlds.unlocked.World2 == true)
check("nach Reset startet ein Sieg wieder", EpilogRules.applyFinalClear(p, 20) == true and p.epilog.state == "pending")

-- 5. Token --------------------------------------------------------------
local T0 = 10000
local tok = EpilogRules.newToken("abc", 42, T0)
local ok1, why1 = EpilogRules.checkToken(tok, "abc", 42, "seen", T0 + EpilogConfig.SEEN_MIN_SECONDS)
check("Token gueltig nach Mindestzeit", ok1, why1)
check("kein Token -> abgelehnt", not (EpilogRules.checkToken(nil, "abc", 42, "seen", T0 + 100)))
check("falsches Token abgelehnt", not (EpilogRules.checkToken(tok, "xyz", 42, "seen", T0 + 100)))
check("kein String abgelehnt", not (EpilogRules.checkToken(tok, 123, 42, "seen", T0 + 100)))
check("anderer Spieler abgelehnt", not (EpilogRules.checkToken(tok, "abc", 43, "seen", T0 + 100)))
check("Seen zu frueh abgelehnt", not (EpilogRules.checkToken(tok, "abc", 42, "seen", T0 + EpilogConfig.SEEN_MIN_SECONDS - 1)))
check("Seen abgelaufen abgelehnt", not (EpilogRules.checkToken(tok, "abc", 42, "seen", T0 + EpilogConfig.SEEN_MAX_SECONDS + 1)))
EpilogRules.consumeSeen(tok)
check("Seen nur einmal", not (EpilogRules.checkToken(tok, "abc", 42, "seen", T0 + 100)))
check("Knopf-Token danach weiter gueltig (ohne Zeitfenster)", (EpilogRules.checkToken(tok, "abc", 42, "press", T0 + 100000)))
check("Skip ohne Mindestzeit gueltig", (EpilogRules.checkToken(EpilogRules.newToken("q", 1, T0), "q", 1, "skip", T0)))

-- 6. Migration-Regeln ---------------------------------------------------
local m1 = {}
EpilogRules.migrate(m1, 100, FINAL_STAGES, 77)
check("Rekord 100 -> pending", m1.epilog.state == "pending" and m1.epilog.firstClearAt == 77)
local m2 = {}
EpilogRules.migrate(m2, 99, FINAL_STAGES, 77)
check("Rekord 99 -> none", m2.epilog.state == "none" and m2.epilog.firstClearAt == nil)
local m3 = { epilog = { state = "seen", firstClearAt = 5 }, worlds = { unlocked = {} } }
EpilogRules.migrate(m3, 100, FINAL_STAGES, 77)
check("seen bleibt, firstClearAt bleibt", m3.epilog.state == "seen" and m3.epilog.firstClearAt == 5)
local m4 = { epilog = { state = "launched" }, worlds = { unlocked = { Welt9 = true } } }
EpilogRules.migrate(m4, 100, FINAL_STAGES, 77)
check("launched -> Welt 2 steht, Fremdes weg", m4.worlds.unlocked.World2 == true and m4.worlds.unlocked.Welt9 == nil)
local m5 = { epilog = { state = "kaputt" }, worlds = 5 }
EpilogRules.migrate(m5, 0, FINAL_STAGES, 77)
check("kaputt -> none, worlds neu", m5.epilog.state == "none" and type(m5.worlds.unlocked) == "table")
local snap = { m1.epilog.state, m1.epilog.firstClearAt }
EpilogRules.migrate(m1, 100, FINAL_STAGES, 999)
check("Migration idempotent", m1.epilog.state == snap[1] and m1.epilog.firstClearAt == snap[2])

-- Gesamtablauf: Sieg -> Seen -> Knopf, Sieg dazwischen loest nichts aus
local run = newData()
local seq = {}
table.insert(seq, EpilogRules.applyFinalClear(run, 1))   -- true
table.insert(seq, EpilogRules.applyFinalClear(run, 2))   -- false (Race)
EpilogRules.transition(run.epilog, "seen", 3)
table.insert(seq, EpilogRules.applyFinalClear(run, 4))   -- false
table.insert(seq, EpilogRules.applyLaunch(run, 5))       -- true
table.insert(seq, EpilogRules.applyFinalClear(run, 6))   -- false
check("Gesamtablauf: genau eine Sequenz", seq[1] == true and seq[2] == false and seq[3] == false
	and seq[4] == true and seq[5] == false, table.concat({ tostring(seq[1]), tostring(seq[2]), tostring(seq[3]), tostring(seq[4]), tostring(seq[5]) }, ","))

if failures > 0 then error(failures .. " Test(s) fehlgeschlagen") end
print("epilog_state: alle Tests gruen")
