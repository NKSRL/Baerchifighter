-- epilog_finale.test.lua — 20.10. Final-Epilog, Prompt 6 (Knopf-Finale, Welt 2)
-- python tools/luau-tests/run_local.py tools/luau-tests/epilog_finale.test.lua
--
-- Prueft die reinen Regeln und Zahlen des Finales (ohne Roblox-Dienste):
--   1. Zeitplan: Zahlen < Stille < Start < Ende Start <= Feier < Rueckweg, Skip ab Sekunde 5
--   2. Budgets: Konfetti <= 150, Emitter <= 4 (Rakete 2), Rakete <= 8 Teile, Rueckweg ~ 6 s
--   3. Schuetteln 0,3 -> 0,8, Bloom 1,5 -> 0,8 in 2 s, Salven 3 x 0,4 s
--   4. Spielstand: nur "seen" -> launched + Welt 2 in EINER Mutation; zweiter Aufruf ist ein no-op;
--      "pending"/"none" koennen nicht direkt starten; reset (Debug) laesst Welt 2 stehen
--   5. Cues und Platzhalter in SoundConfig, Terminal-Countdown-Attribut

local EpilogConfig = require(RS.Config.EpilogConfig)
local EpilogRules  = require(RS.Modules.EpilogRules)
local SoundConfig  = require(RS.Config.SoundConfig)

local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else
		failures += 1
		print("FAIL " .. name .. (if detail ~= nil then ": " .. tostring(detail) else ""))
	end
end

local F = EpilogConfig.FINALE
local S = EpilogConfig.STATE

-- 1. Zeitplan
local mono = true
for i = 2, #F.countTimes do if F.countTimes[i] <= F.countTimes[i - 1] then mono = false end end
check("drei Zahlen, aufsteigend", #F.countTimes == 3 and mono)
check("Countdown beginnt bei 1,2 s", F.countTimes[1] == 1.2)
check("letzte Zahl vor der Stille", F.countTimes[3] < F.silenceAt)
check("0,3 s Stille vor dem Start", math.abs((F.launchAt - F.silenceAt) - 0.3) < 1e-6)
check("Start bei 5 s, Ende 7,5 s", F.launchAt == 5 and F.launchEnd == 7.5)
check("Feier 7,5 bis 9 s", F.celebrateAt == 7.5 and F.returnAt == 9)
check("Skip ab Sekunde 5", F.skipFromSeconds == 5 and F.skipFromSeconds <= F.launchAt)
check("Skip springt in den Rueckweg", F.skipFromSeconds < F.returnAt)
check("Rueckweg-Teleport nach dem Ende des Finales", F.returnTeleportAt > F.returnAt)
local back = (F.returnTeleportAt - F.returnAt) + EpilogConfig.BRIDGE.removeSeconds + F.lowerSeconds
check("Rueckweg ca. 6 s", back >= 5.5 and back <= 7, back)
check("Abstand zum Terminal < 14 Studs", F.pressMaxDistance == 14)
check("Rate-Limit 1/s", F.pressCooldownSeconds == 1)

-- 2. Budgets
check("Konfetti <= 150", F.confettiMax <= 150)
check("Pools (Overlay) <= 60 Teilchen", (function()
	local n = 0
	for _, v in EpilogConfig.FX.pools do n += v end
	return n <= EpilogConfig.FX.maxSprites
end)())
check("Emitter <= 4 gleichzeitig", F.emittersMax <= 4)
check("Rakete: 2 Emitter + Schacht-Teile im Budget", F.rocket.parts >= 7 and F.rocket.parts <= 8)
check("Rakete: ein Mesh/Part-Satz", F.rocket.height > 0 and F.rocket.rise > 100)
check("Vorlage heisst EpilogRakete", EpilogConfig.ASSETS.rocketTemplate == "EpilogRakete")

-- 3. Bewegung und Licht
check("Schuetteln 0,3 -> 0,8", F.shake.from == 0.3 and F.shake.to == 0.8)
check("Bloom 1,5 -> 0,8 in 2 s", F.bloomPeak == 1.5 and F.bloomRest == 0.8 and F.bloomSeconds == 2)
check("drei Salven im Abstand 0,4 s", F.salvos == 3 and F.salvoGap == 0.4)
check("Salven passen in den Start", F.launchAt + (F.salvos - 1) * F.salvoGap < F.celebrateAt)

-- 4. Spielstand
local function data(state)
	local d = { epilog = { state = state }, worlds = { unlocked = {} } }
	return d
end
local d = data(S.SEEN)
check("seen -> launched + Welt 2 in einer Mutation", EpilogRules.applyLaunch(d, 1000)
	and d.epilog.state == S.LAUNCHED and d.worlds.unlocked[EpilogConfig.WORLD2_ID] == true
	and d.epilog.launchedAt == 1000)
check("zweiter Druck ist ein no-op", EpilogRules.applyLaunch(d, 2000) == false and d.epilog.launchedAt == 1000)
local p = data(S.PENDING)
check("pending startet nicht direkt", EpilogRules.applyLaunch(p, 1) == false and p.worlds.unlocked.World2 == nil)
-- pending -> seen -> launched (Service holt "seen" vor dem Start nach)
check("pending ueber seen erreichbar", EpilogRules.transition(p.epilog, S.SEEN, 1) and EpilogRules.applyLaunch(p, 2))
local n0 = data(S.NONE)
check("none startet nicht", EpilogRules.applyLaunch(n0, 1) == false and n0.worlds.unlocked.World2 == nil)
EpilogRules.reset(d.epilog)
check("Debug-Reset laesst Welt 2 stehen", d.worlds.unlocked.World2 == true and d.epilog.state == S.NONE)
check("Welt-2-Id", EpilogConfig.WORLD2_ID == "World2")

-- 5. Cues und Terminal
for _, k in { "press", "countdown", "launch", "unlock" } do
	local cue = EpilogConfig.CUES[k]
	check("Cue " .. k, cue ~= nil and SoundConfig.SOUNDS[cue] ~= nil and SoundConfig.SOUNDS[cue].id == "", cue)
end
check("Countdown-Attribut", EpilogConfig.TERMINAL.COUNTDOWN_ATTRIBUTE == "EpilogCountdown")

print(failures == 0 and "ALLE OK" or ("FEHLER: " .. failures))
if failures > 0 then error("epilog_finale: " .. failures .. " Fehler") end
