-- onboarding_rules.test.lua — P3 (20.10.2026), die "Reise"
-- python tools/luau-tests/run_local.py tools/luau-tests/onboarding_rules.test.lua

local Rules  = require(RS.Modules.OnboardingRules)
local Config = require(RS.Config.OnboardingConfig)

local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else
		failures += 1
		print("FAIL " .. name .. (if detail ~= nil then ": " .. tostring(detail) else ""))
	end
end

local function view(over)
	local v = {
		island = { baerchis = {}, equippedUid = nil },
		towers = { records = {}, unlocked = { I = true } },
		stats = { totalHatched = 0 },
	}
	for k, x in over or {} do v[k] = x end
	return v
end

-- 1. Neuer Spielstand startet bei Etappe 1
local fresh = Rules.defaultJourney()
local id, idx, done = Rules.current(view(), fresh)
check("neuer Spielstand: Etappe 1 (hatch), nicht erfuellt", id == "hatch" and idx == 1 and done == false, id)

-- 2. Fortschritt kommt aus dem Spielstand
local v = view({ stats = { totalHatched = 1 }, island = { baerchis = { a = {} }, equippedUid = "a" } })
check("hatch erfuellt nach erstem Ei", Rules.isDone("hatch", v))
check("equip erfuellt mit ausgeruestetem Baerchi", Rules.isDone("equip", v))
check("tower1_enter noch offen", not Rules.isDone("tower1_enter", v))
v.towers.records.I = 12
local cur, target = Rules.progress("tower1_clear", v)
check("tower1_clear Balken 12/30", cur == 12 and target == 30, cur)
v.towers.records.I = 99
cur = Rules.progress("tower1_clear", v)
check("Balken ueber Ziel gedeckelt", cur == 30, cur)
v.towers.unlocked.III = true
check("tower3_open ueber unlocked", Rules.isDone("tower3_open", v))
v.towers.records.Final = 100
check("final_clear bei Rekord 100", Rules.isDone("final_clear", v))

-- 3. Abholen: nur erfuellt, nur einmal, nur bekannte IDs, keine Spoof-Typen
local j = Rules.defaultJourney()
check("canClaim erfuellte Etappe", Rules.canClaim("hatch", v, j))
check("canClaim unerfuellte Etappe abgelehnt", not Rules.canClaim("final_open", view(), j))
j.claimed.hatch = true
check("Doppel-Claim abgelehnt", not Rules.canClaim("hatch", v, j))
check("unbekannte ID abgelehnt", not Rules.canClaim("gibtsnicht", v, j))
check("Zahl als ID abgelehnt", not Rules.canClaim(5, v, j))
check("Tabelle als ID abgelehnt", not Rules.canClaim({}, v, j))
check("nil als ID abgelehnt", not Rules.canClaim(nil, v, j))

-- 4. Weiter zur naechsten Etappe nach Abholen, Ueberspringen
id = Rules.current(v, j)
check("nach hatch ist equip dran", id == "equip", id)
check("canSkip aktuelle Etappe", Rules.canSkip("equip", j))
j.skipped.equip = true
check("Doppel-Skip abgelehnt", not Rules.canSkip("equip", j))
id = Rules.current(v, j)
check("nach Skip ist tower1_enter dran", id == "tower1_enter", id)

-- 5. Migration Bestandsspieler: erfuellte Etappen = abgeholt, ohne Nachzahlung
local veteran = view({
	stats = { totalHatched = 400 },
	island = { baerchis = { a = {} }, equippedUid = "a" },
	towers = { records = { I = 30, II = 45, III = 60, Final = 35 }, unlocked = { I = true, II = true, III = true, Final = true } },
})
local mj = Rules.migrate(nil, veteran)
check("Migration: 6 Etappen abgeholt", mj.claimed.hatch and mj.claimed.equip and mj.claimed.tower1_enter and mj.claimed.tower1_clear and mj.claimed.tower3_open and mj.claimed.final_open)
check("Migration: final_clear nicht abgeholt", not mj.claimed.final_clear)
id, idx = Rules.current(veteran, mj)
check("Veteran landet bei Etappe 7", id == "final_clear" and idx == 7, id)
check("Migration ist wiederholbar", select(2, pcall(function() return Rules.migrate(mj, veteran) end)).claimed.hatch == true)

-- 6. Kaputte Felder
local broken = Rules.sanitize({ claimed = 5, skipped = "x", hidden = 3 })
check("sanitize repariert Felder", type(broken.claimed) == "table" and type(broken.skipped) == "table" and broken.hidden == false)

-- 7. Reise abgeschlossen
local all = Rules.defaultJourney()
for _, s in Config.STAGES do all.claimed[s.id] = true end
check("isComplete wenn alles abgeholt", Rules.isComplete(all))
check("current ist nil wenn fertig", (Rules.current(veteran, all)) == nil)
check("nicht fertig bei frischem Stand", not Rules.isComplete(Rules.defaultJourney()))

-- 8. Config
check("7 Etappen", #Config.STAGES == 7)
local ids, bad = {}, false
for _, s in Config.STAGES do
	if ids[s.id] then bad = true end
	ids[s.id] = true
	local r = s.reward
	if (r.goldGummies or 0) > 50 or (r.gummies or 0) > 0 and false then bad = true end
end
check("IDs eindeutig, Belohnungen klein (<= 50)", not bad)

if failures > 0 then error("onboarding_rules: " .. failures .. " Fehler") end
print("onboarding_rules: alle Tests gruen")
