-- potions.test.lua — Traenke (26.10.): Regeln, Sortiment, Preis, Glueck, Migration, Texte
-- python tools/luau-tests/run_local.py tools/luau-tests/potions.test.lua
--
-- 1. Konfiguration: fuenf Sorten, jeder Trank hat Faktor > 1, Dauer, Preis, Texte in de/en/fr/es.
-- 2. Effekte: anlegen, Faktor, Restzeit, Ablauf (prune), verschiedene Sorten nebeneinander.
-- 3. Stapel-Regeln: gleich = verlaengern, staerker = ersetzen, schwaecher = ablehnen,
--    Vorrats-Grenze = ablehnen; abgelehnt aendert nichts.
-- 4. Sortiment: deterministisch je Fenster, 3-5 Traenke ohne Doppelte, wechselt ueber
--    die Fenster, Fenster = 5 Minuten, Restzeit bis zum Wechsel.
-- 5. Preis: Untergrenze fuer Neulinge, waechst mit der Bezugsgroesse.
-- 6. Glueck: haeufigstes Ergebnis bleibt, alle anderen x Faktor, Eingabe unveraendert.
-- 7. Migration: potions wird angelegt/repariert, kaputte Effekte fallen weg.

local PotionConfig    = rbxRequire("ReplicatedStorage/Config/PotionConfig")
local PotionRules     = rbxRequire("ReplicatedStorage/Modules/PotionRules")
local Loc             = rbxRequire("ReplicatedStorage/Localization/Loc")
local Names           = rbxRequire("ReplicatedStorage/Localization/Names")
local Types           = rbxRequire("ReplicatedStorage/Network/Types")
local PlayerMigration = rbxRequire("ServerScriptService/Util/PlayerMigration")

local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else
		failures += 1
		print("FAIL " .. name .. (if detail then ": " .. tostring(detail) else ""))
	end
end

local function byId(id) return PotionConfig.byId(id) end
local MAX = PotionConfig.MAX_REMAINING_SECONDS

-- 1. Konfiguration
check("fuenf Sorten", #PotionConfig.KINDS == 5)
local kindsSeen = {}
for _, def in PotionConfig.POTIONS do
	kindsSeen[def.kind] = true
	check("Trank " .. def.id .. " gueltig",
		PotionConfig.isKind(def.kind) and def.multiplier > 1 and def.durationSeconds > 0
		and def.minPrice > 0 and def.stagePrice > 0 and def.weight > 0 and def.durationSeconds <= MAX)
end
for _, kind in PotionConfig.KINDS do
	check("Sorte " .. kind .. " hat einen Trank", kindsSeen[kind] == true)
	check("Sorte " .. kind .. " hat ein Zeichen", type(PotionConfig.GLYPH[kind]) == "string" and #PotionConfig.GLYPH[kind] > 0)
end
local function complete(text)
	return type(text) == "string" and text ~= "" and string.find(text, "%[[%w_]+%.[%w_.]+%]") == nil and string.find(text, "{[%w_]+}") == nil
end
for _, lang in { "de", "en", "fr", "es" } do
	Loc.setLanguage(lang)
	for _, def in PotionConfig.POTIONS do
		check(lang .. " Name " .. def.id, complete(Names.potion(def.id)) and Names.potion(def.id) ~= def.id, Names.potion(def.id))
		check(lang .. " Beschreibung " .. def.id, complete(Names.potionDesc(def.id)), Names.potionDesc(def.id))
	end
	for _, kind in PotionConfig.KINDS do
		check(lang .. " Sorte " .. kind, complete(Names.potionKind(kind)) and Names.potionKind(kind) ~= kind)
	end
	check(lang .. " HUD-Text", complete(Loc.t("ui.potion.hud", { mult = 1.5, time = Loc.formatDuration(90) })))
	check(lang .. " Kauf-Meldung", complete(Loc.t("msg.potion_on", { name = "X", mult = 2, time = "1m" })))
end
Loc.setLanguage("de")

-- 2. Effekte
local T0 = 1_700_000_000
local state = PotionRules.newState()
check("leer: Faktor 1", PotionRules.multiplier(state, "coins", T0) == 1)
check("leer: nil-Zustand Faktor 1", PotionRules.multiplier(nil, "coins", T0) == 1)
check("leer: Restzeit 0", PotionRules.remaining(state, "coins", T0) == 0)
check("leer: Sicht leer", #PotionRules.view(state, T0) == 0)

local coinsI = byId("CoinsI")
local ok, outcome, effect = PotionRules.apply(state, coinsI, T0, MAX)
check("CoinsI anlegen", ok and outcome == PotionRules.NEW and effect ~= nil, outcome)
check("Faktor coins", PotionRules.multiplier(state, "coins", T0) == coinsI.multiplier)
check("Faktor andere Sorte bleibt 1", PotionRules.multiplier(state, "strength", T0) == 1)
check("Restzeit = Dauer", PotionRules.remaining(state, "coins", T0) == coinsI.durationSeconds)
check("gekauft gezaehlt", state.bought == 1)
check("kurz vor Ablauf noch da", PotionRules.multiplier(state, "coins", T0 + coinsI.durationSeconds - 1) == coinsI.multiplier)
check("ab Ablauf Faktor 1", PotionRules.multiplier(state, "coins", T0 + coinsI.durationSeconds) == 1)
check("prune vorher: nichts", #PotionRules.prune(state, T0 + 10) == 0 and state.active.coins ~= nil)
local removed = PotionRules.prune(state, T0 + coinsI.durationSeconds)
check("prune traegt aus", #removed == 1 and removed[1] == "coins" and state.active.coins == nil)

-- verschiedene Sorten nebeneinander
state = PotionRules.newState()
for _, id in { "StrengthI", "CoinsI", "SpeedI", "LuckI", "PetXpI" } do
	PotionRules.apply(state, byId(id), T0, MAX)
end
local view = PotionRules.view(state, T0 + 5)
check("fuenf Sorten gleichzeitig", #view == 5)
check("Sicht in Sorten-Reihenfolge", view[1].kind == "strength" and view[3].kind == "speed" and view[5].kind == "petxp")
check("Sicht: Restzeit statt Zeitpunkt", view[2].remaining == coinsI.durationSeconds - 5)

-- 3. Stapel-Regeln
state = PotionRules.newState()
PotionRules.apply(state, byId("SpeedI"), T0, MAX)
local speedI, speedII = byId("SpeedI"), byId("SpeedII")
check("gleicher Trank = verlaengern", PotionRules.check(state, speedI, T0 + 60, MAX) == PotionRules.EXTEND)
ok, outcome = PotionRules.apply(state, speedI, T0 + 60, MAX)
check("verlaengert: Restzeit addiert", ok and PotionRules.remaining(state, "speed", T0 + 60) == 2 * speedI.durationSeconds - 60)
check("verlaengert: Faktor gleich", PotionRules.multiplier(state, "speed", T0 + 60) == speedI.multiplier)
check("staerker = ersetzen", PotionRules.check(state, speedII, T0 + 60, MAX) == PotionRules.REPLACE)
ok, outcome = PotionRules.apply(state, speedII, T0 + 60, MAX)
check("ersetzt: neuer Faktor, neue Dauer", ok and PotionRules.multiplier(state, "speed", T0 + 60) == speedII.multiplier
	and PotionRules.remaining(state, "speed", T0 + 60) == speedII.durationSeconds)
check("schwaecher = ablehnen", PotionRules.check(state, speedI, T0 + 60, MAX) == PotionRules.WEAKER)
local before = PotionRules.remaining(state, "speed", T0 + 60)
ok, outcome = PotionRules.apply(state, speedI, T0 + 60, MAX)
check("abgelehnt aendert nichts", not ok and outcome == PotionRules.WEAKER
	and PotionRules.remaining(state, "speed", T0 + 60) == before and state.bought == 3)
-- Vorrats-Grenze: so oft verlaengern, bis es nicht mehr geht
local extends = 0
while PotionRules.check(state, speedII, T0 + 60, MAX) == PotionRules.EXTEND do
	PotionRules.apply(state, speedII, T0 + 60, MAX)
	extends += 1
	if extends > 100 then break end
end
check("Vorrats-Grenze greift", PotionRules.check(state, speedII, T0 + 60, MAX) == PotionRules.MAXTIME
	and PotionRules.remaining(state, "speed", T0 + 60) <= MAX and extends >= 1, extends)
ok = PotionRules.apply(state, speedII, T0 + 60, MAX)
check("ueber der Grenze abgelehnt", not ok)
check("neuer Trank laenger als Grenze = maxtime", PotionRules.check(PotionRules.newState(), speedI, T0, speedI.durationSeconds - 1) == PotionRules.MAXTIME)
-- abgelaufener Effekt zaehlt wie keiner
check("abgelaufen = neu", PotionRules.check(state, speedI, T0 + 60 + MAX + 1, MAX) == PotionRules.NEW)

-- 4. Sortiment
local M = PotionConfig.MERCHANT
check("Fenster = 5 Minuten", M.ROTATE_SECONDS == 300)
check("Fenster-Index", PotionRules.windowOf(T0, 300) == math.floor(T0 / 300))
check("Fenster wechselt auf volle 5 min", PotionRules.windowOf(600, 300) == 2 and PotionRules.windowOf(599, 300) == 1)
check("Restzeit bis Wechsel", PotionRules.secondsUntilRotation(600, 300) == 300 and PotionRules.secondsUntilRotation(899, 300) == 1)
check("Hoechstens 6 Angebote mit Ei", 1 + M.SLOTS_MAX <= M.MAX_ITEMS and M.SLOTS_MIN >= 1 and M.SLOTS_MIN <= M.SLOTS_MAX)
local first = nil
local differs = false
local sizes = {}
for window = 1000, 1099 do
	local ids = PotionRules.rollAssortment(window, PotionConfig.POTIONS, M.SLOTS_MIN, M.SLOTS_MAX)
	sizes[#ids] = (sizes[#ids] or 0) + 1
	local okSize = #ids >= M.SLOTS_MIN and #ids <= M.SLOTS_MAX
	local seen, dup, known = {}, false, true
	for _, id in ids do
		if seen[id] then dup = true end
		seen[id] = true
		if not byId(id) then known = false end
	end
	if not (okSize and not dup and known) then
		check("Fenster " .. window .. " Los gueltig", false, table.concat(ids, ","))
	end
	local again = PotionRules.rollAssortment(window, PotionConfig.POTIONS, M.SLOTS_MIN, M.SLOTS_MAX)
	if table.concat(again, ",") ~= table.concat(ids, ",") then
		check("Fenster " .. window .. " deterministisch", false)
	end
	local key = table.concat(ids, ",")
	if first == nil then first = key elseif key ~= first then differs = true end
end
check("100 Fenster: Lose gueltig und deterministisch", true)
check("Sortiment wechselt ueber die Fenster", differs)
local sizeKinds = 0
for _ in sizes do sizeKinds += 1 end
check("Anzahl der Plaetze variiert (bis zu)", sizeKinds >= 2, sizeKinds)
check("leerer Pool = leer", #PotionRules.rollAssortment(5, {}, 3, 5) == 0)
check("Pool kleiner als Plaetze", #PotionRules.rollAssortment(5, { byId("CoinsI"), byId("LuckI") }, 3, 5) == 2)

-- 5. Preis
check("Neuling zahlt Untergrenze", PotionRules.price(coinsI, 0) == coinsI.minPrice and PotionRules.price(coinsI, 3) == coinsI.minPrice)
check("Preis waechst mit Bezug", PotionRules.price(coinsI, 1000) == coinsI.stagePrice * 1000)
check("grosser Trank teurer", PotionRules.price(byId("CoinsII"), 1000) > PotionRules.price(coinsI, 1000))

-- 6. Glueck
local entries = { { configId = "a", weight = 0.7 }, { configId = "b", weight = 0.2 }, { configId = "c", weight = 0.1 } }
local lucky = PotionRules.applyLuck(entries, 2)
check("Glueck: haeufigstes bleibt", lucky[1].weight == 0.7)
check("Glueck: seltene x2", lucky[2].weight == 0.4 and math.abs(lucky[3].weight - 0.2) < 1e-9)
check("Glueck: Eingabe unveraendert", entries[2].weight == 0.2)
check("Glueck: Faktor 1 = dieselbe Liste", PotionRules.applyLuck(entries, 1) == entries)
local total = 0
for _, e in lucky do total += e.weight end
check("Glueck: seltener Anteil gestiegen", (lucky[2].weight + lucky[3].weight) / total > 0.3)

-- 7. Migration
local fresh = Types.createDefaultPlayerData()
check("Standard hat potions", fresh.potions ~= nil and next(fresh.potions.active) == nil and fresh.potions.bought == 0)
check("Version 20", fresh.version == 20)

local old = Types.createDefaultPlayerData()
old.potions = nil
PlayerMigration.applyDefaults(old)
check("alter Stand: potions angelegt", old.potions ~= nil and type(old.potions.active) == "table" and old.potions.bought == 0)

local broken = Types.createDefaultPlayerData()
broken.potions = { active = { coins = { potionId = "CoinsI", multiplier = 1.5, expiresAt = T0 + 100 }, speed = "x", luck = { potionId = 5 } }, bought = "7" } :: any
PlayerMigration.applyDefaults(broken)
check("kaputte Effekte weg, gueltiger bleibt", broken.potions.active.coins ~= nil and broken.potions.active.speed == nil
	and broken.potions.active.luck == nil and broken.potions.bought == 0)
check("Migration ist wiederholbar", (function()
	local a = PlayerMigration.applyDefaults(Types.createDefaultPlayerData())
	return a.potions ~= nil and a.potions.bought == 0
end)())

if failures > 0 then error(failures .. " Fehler", 0) end
print("potions: alle Tests gruen")
