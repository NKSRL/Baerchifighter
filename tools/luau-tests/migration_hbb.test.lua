-- migration_hbb.test.lua
-- Zusatzfaelle fuer migration.test.lua: der aktuelle Stand von
-- Util/PlayerMigration.applyDefaults (v15 + HBB Paket 2/3 + Honig-Teich).
--
-- Aufruf (eine der beiden Harnesses, beide stellen RS und SSS bereit):
--   cd tools/luau-tests && node run.mjs migration_hbb.test.lua
--   python tools/luau-tests/run_local.py tools/luau-tests/migration_hbb.test.lua
--
-- Zum Zusammenfuehren: Die Faelle stehen in Bloecken (A-H) und koennen einzeln
-- in migration.test.lua uebernommen werden. Der Kopf (check/fixture) ersetzt
-- ggf. die dort vorhandenen Hilfsfunktionen.

local PlayerMigration  = require(SSS.Util.PlayerMigration)
local Types            = require(RS.Network.Types)
local TowerConfig      = require(RS.Config.TowerConfig)
local BuildingBehavior = require(RS.Config.BuildingBehavior)
local FeatureFlags     = require(RS.Config.FeatureFlags)

-- Alle Faelle ausser Block J laufen mit HONEY_POND_V2 = true (aktueller
-- Standard), egal was in FeatureFlags steht. Am Ende wird der Wert zurueckgesetzt.
local FLAGS = FeatureFlags.FLAGS
local originalPond = FLAGS.HONEY_POND_V2
FLAGS.HONEY_POND_V2 = true

local function withPond(on: boolean, fn: () -> ())
	local before = FLAGS.HONEY_POND_V2
	FLAGS.HONEY_POND_V2 = on
	local ok, err = pcall(fn)
	FLAGS.HONEY_POND_V2 = before
	if not ok then error(err, 0) end
end

local failures = 0
local log = __log or print
local function check(name, got, want)
	if got ~= want then
		failures += 1
		log("FAIL", string.format("%s: erwartet %s, bekommen %s", name, tostring(want), tostring(got)))
	else
		print("ok   " .. name)
	end
end

local function deepEqual(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for k, v in a do
		if not deepEqual(v, b[k]) then return false end
	end
	for k in b do
		if a[k] == nil then return false end
	end
	return true
end

local function deepCopy(t)
	if type(t) ~= "table" then return t end
	local c = {}
	for k, v in t do c[k] = deepCopy(v) end
	return c
end

local function count(t)
	local n = 0
	for _ in t do n += 1 end
	return n
end

-- ---------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------

-- Leerer, aktueller Spielstand als Ausgangspunkt, dann gezielt zurueck in ein
-- altes Format gebaut. So bleibt der Test von unbeteiligten Feldern unabhaengig.
local function legacyV14()
	local d = deepCopy(Types.createDefaultPlayerData()) :: any
	d.version = 14
	-- Felder, die es in v14 noch nicht gab
	d.uiSeen = nil
	d.towers = nil
	d.daily = nil
	d.island.recycler = nil
	d.island.towerProgress = nil
	d.island.pitRefund = nil
	d.stats.totalEventsCompleted = nil
	-- Felder, die es in v14 noch gab
	d.island.pitLevel = 5
	d.island.pitProgress = { pitLevel = 5, reachedStage = 12 }
	d.stats.highestPitLevel = 5
	d.stats.highestTowerFloor = 3
	-- Gebaeude exakt wie im v14-Stand (kein Teich, kein Veredler)
	d.island.retiredBuildings = nil
	d.island.buildings = {
		Beehive    = { id = "Beehive",    level = 2, honey = 0, lastProducedAt = 1000 },
		HoneyPot   = { id = "HoneyPot",   level = 7, honey = 3, lastProducedAt = 1000 },
		HoneyPress = { id = "HoneyPress", level = 4, honey = 2, lastProducedAt = 1000 },
	}
	return d
end

-- ===============================================================
-- A) HBB Paket 3: uiSeen
-- ===============================================================
do
	local d = legacyV14()
	local out = PlayerMigration.applyDefaults(d)
	check("A1 uiSeen fehlt -> leere Tabelle", typeof(out.uiSeen), "table")
	check("A1 uiSeen ist leer", count(out.uiSeen), 0)

	local d2 = legacyV14()
	d2.uiSeen = { tile_tree = true, pill_gold = true }
	local out2 = PlayerMigration.applyDefaults(d2)
	check("A2 vorhandenes uiSeen bleibt: tile_tree", out2.uiSeen.tile_tree, true)
	check("A2 vorhandenes uiSeen bleibt: pill_gold", out2.uiSeen.pill_gold, true)
	check("A2 keine Fremdschluessel", count(out2.uiSeen), 2)
end

-- ===============================================================
-- B) HBB Paket 2: stats.totalEventsCompleted
-- ===============================================================
do
	local out = PlayerMigration.applyDefaults(legacyV14())
	check("B1 fehlender Zaehler -> 0", out.stats.totalEventsCompleted, 0)

	local d = legacyV14()
	d.stats.totalEventsCompleted = 7
	check("B2 vorhandener Zaehler bleibt", PlayerMigration.applyDefaults(d).stats.totalEventsCompleted, 7)

	-- Veteranen-Zaehler duerfen durch die Stats-Schleife nicht ueberschrieben werden
	local v = legacyV14()
	v.stats.totalHatched = 250
	v.stats.totalFightsWon = 80
	v.stats.totalEventsCompleted = nil
	local o = PlayerMigration.applyDefaults(v)
	check("B3 totalHatched unveraendert", o.stats.totalHatched, 250)
	check("B3 totalFightsWon unveraendert", o.stats.totalFightsWon, 80)
	check("B3 Event-Zaehler startet bei 0", o.stats.totalEventsCompleted, 0)

	-- Stats-Tabelle fehlt ganz (uralter Stand): alle Defaults inkl. Zaehler
	local w = legacyV14()
	w.stats = nil
	local ow = PlayerMigration.applyDefaults(w)
	check("B4 stats fehlt -> Tabelle", typeof(ow.stats), "table")
	check("B4 stats fehlt -> Event-Zaehler 0", ow.stats.totalEventsCompleted, 0)
end

-- ===============================================================
-- C) v14 -> v15: Beispiel aus dem Briefing
--    Topf L7 / Presse L4 / PIT 5 Stage 12
--    -> Veredler L7, Erstattung 16.000, Rekord Tower I / 20
-- ===============================================================
do
	local out = PlayerMigration.applyDefaults(legacyV14())
	local b = out.island.buildings
	-- Topf/Presse -> Veredler L7 (v15), danach geht der Veredler zusammen mit dem
	-- Stock in den Ruhestand und der Teich startet auf dem hoechsten Level (7).
	check("C1 Teich erbt hoechstes Level (7)", b.HoneyPond.level, 7)
	check("C1 nur der Teich ist aktiv", count(b), 1)
	check("C1 HoneyPot entfernt", b.HoneyPot, nil)
	check("C1 HoneyPress entfernt", b.HoneyPress, nil)
	check("C1 Veredler im Ruhestand (L7)", out.island.retiredBuildings.HoneyRefiner.level, 7)
	check("C1 Stock im Ruhestand (L2)", out.island.retiredBuildings.Beehive.level, 2)
	check("C1 Topf nicht im Ruhestand", out.island.retiredBuildings.HoneyPot, nil)

	local cap = BuildingBehavior.getCapacity("HoneyPond", b.HoneyPond.level)
	check("C2 Honig zusammengelegt (3 + 2, gedeckelt)", b.HoneyPond.honey, math.min(5, cap))

	check("C3 Erstattung 16000", out.island.pitRefund, 16000)
	-- Sammel-Update 05.10. (Paket 4.2): Tower I waechst staerker je Stage
	-- (1.15 statt 1.0) — der alte Stand mit Aequivalenz 20 landet deshalb
	-- etwas tiefer (bei 1.0 waren es genau 20).
	local perStage = TowerConfig.get(TowerConfig.FIRST_TOWER).equivalentPerStage
	check("C4 Rekord Tower I = Aequivalenz 20", out.towers.records[TowerConfig.FIRST_TOWER], 1 + math.floor(19 / perStage + 1e-6))
	check("C4 hoechster Tower = erster", out.towers.highestTower, TowerConfig.FIRST_TOWER)
	check("C4 Auswahl = erster Tower", out.towers.selected, TowerConfig.FIRST_TOWER)

	check("C5 pitLevel entfernt", out.island.pitLevel, nil)
	check("C5 pitProgress entfernt", out.island.pitProgress, nil)
	check("C5 stats.highestPitLevel entfernt", out.stats.highestPitLevel, nil)
	check("C5 stats.highestTowerFloor entfernt", out.stats.highestTowerFloor, nil)

	check("C6 Version nachgezogen", out.version, Types.createDefaultPlayerData().version)
end

-- Niedrigeres Veredler-Level als Topf/Presse darf nie gewinnen; Presse > Topf
do
	local d = legacyV14()
	d.island.buildings.HoneyPot.level = 3
	d.island.buildings.HoneyPress.level = 9
	check("C7 Presse hoeher als Topf -> 9", PlayerMigration.applyDefaults(d).island.buildings.HoneyPond.level, 9)

	local e = legacyV14()
	e.island.buildings.HoneyRefiner = { id = "HoneyRefiner", level = 12, honey = 0, lastProducedAt = 1000 }
	check("C8 Veredler schon hoeher -> Teich 12", PlayerMigration.applyDefaults(e).island.buildings.HoneyPond.level, 12)
end

-- ===============================================================
-- D) Kein PIT-Lauf gespeichert: nur Erstattung, kein Rekord
-- ===============================================================
do
	local d = legacyV14()
	d.island.pitProgress = nil
	local out = PlayerMigration.applyDefaults(d)
	check("D1 Erstattung trotzdem gezahlt", out.island.pitRefund, 16000)
	check("D1 kein Rekord ohne Lauf", count(out.towers.records), 0)

	local f = legacyV14()
	f.island.pitLevel = 1
	f.island.pitProgress = nil
	check("D2 PIT 1 ohne Ausbau -> keine Erstattung", PlayerMigration.applyDefaults(f).island.pitRefund, 0)

	local h = legacyV14()
	h.island.pitProgress = { pitLevel = 5 } -- halber Eintrag
	local oh = PlayerMigration.applyDefaults(h)
	check("D3 halber pitProgress verworfen", oh.island.pitProgress, nil)
	check("D3 kein Rekord aus halbem Eintrag", count(oh.towers.records), 0)
end

-- ===============================================================
-- E) Version >= 15: die umrechnenden Schritte laufen NICHT erneut
-- ===============================================================
do
	local first = PlayerMigration.applyDefaults(legacyV14())
	-- Spieler hat die Erstattung inzwischen bekommen, TowerService setzt 0
	first.island.pitRefund = 0
	-- und den Veredler selbst ausgebaut
	first.island.buildings.HoneyPond.level = 9
	first.towers.records[TowerConfig.FIRST_TOWER] = 25

	local again = PlayerMigration.applyDefaults(first)
	check("E1 keine zweite Erstattung", again.island.pitRefund, 0)
	check("E2 Teich-Level bleibt", again.island.buildings.HoneyPond.level, 9)
	check("E2 Ruhestand bleibt (Veredler L7)", again.island.retiredBuildings.HoneyRefiner.level, 7)
	check("E3 Rekord bleibt", again.towers.records[TowerConfig.FIRST_TOWER], 25)
end

-- ===============================================================
-- F) Idempotenz: zweimal hintereinander == einmal
-- ===============================================================
do
	local once = PlayerMigration.applyDefaults(legacyV14())
	local snapshot = deepCopy(once)
	local twice = PlayerMigration.applyDefaults(once)
	-- os.time()-Felder duerfen sich hoechstens beim ersten Anlegen unterscheiden;
	-- nach dem ersten Lauf sind sie gesetzt, also muss alles gleich sein.
	check("F1 zweiter Lauf aendert nichts", deepEqual(snapshot, twice), true)

	-- Auch fuer einen frischen, aktuellen Spielstand
	local fresh = deepCopy(Types.createDefaultPlayerData())
	local fSnap = deepCopy(fresh)
	check("F2 aktueller Stand bleibt unveraendert", deepEqual(fSnap, PlayerMigration.applyDefaults(fresh)), true)
end

-- ===============================================================
-- G) Neue Felder aus v15 / HBB werden angelegt, nichts Fremdes geloescht
-- ===============================================================
do
	local d = legacyV14()
	d.island.baerchis = {
		{ uid = "b1", configId = "Bear_Basic", level = 3, fusionBonus = 0, isFusionResult = false, currentHp = 10 },
	}
	d.gummies = 4242
	d.goldGummies = 9
	d.rebirthCount = 2
	local out = PlayerMigration.applyDefaults(d)
	check("G1 Gummies unveraendert", out.gummies, 4242)
	check("G1 GoldGummies unveraendert", out.goldGummies, 9)
	check("G1 Rebirths unveraendert", out.rebirthCount, 2)
	check("G2 Baerchi bleibt erhalten", #out.island.baerchis, 1)
	check("G2 Baerchi-uid unveraendert", out.island.baerchis[1].uid, "b1")

	check("G3 Recycler angelegt", typeof(out.island.recycler), "table")
	check("G3 Recycler Level 1", out.island.recycler.level, 1)
	check("G4 daily angelegt: lastClaimDay", out.daily.lastClaimDay, 0)
	check("G4 daily angelegt: streak", out.daily.streak, 0)
	check("G5 towerProgress angelegt", typeof(out.island.towerProgress), "table")
	check("G6 eggTree angelegt", typeof(out.eggTree), "table")
end

-- ===============================================================
-- H) Kaputte / halbe Eintraege der neuen Strukturen werden repariert
-- ===============================================================
do
	local d = legacyV14()
	d.towers = {
		records = { [TowerConfig.FIRST_TOWER] = 9999, NichtDa = 5, },
		claimed = { NichtDa = { ["10"] = true } },
		highestTower = "Quatsch",
		selected = "Quatsch",
	}
	local out = PlayerMigration.applyDefaults(d)
	local def = TowerConfig.get(TowerConfig.FIRST_TOWER)
	check("H1 Rekord auf Stage-Zahl gedeckelt", out.towers.records[TowerConfig.FIRST_TOWER], def.stages)
	check("H2 unbekannter Tower aus Rekorden entfernt", out.towers.records.NichtDa, nil)
	check("H3 unbekannter Tower aus claimed entfernt", out.towers.claimed.NichtDa, nil)
	check("H4 ungueltiger highestTower -> erster", TowerConfig.isValidId(out.towers.highestTower), true)
	check("H5 ungueltige Auswahl -> erster", out.towers.selected, TowerConfig.FIRST_TOWER)

	local r = legacyV14()
	r.island.recycler = { level = "x", queued = -1 }
	local o = PlayerMigration.applyDefaults(r)
	check("H6 Recycler-Level kaputt -> 1", o.island.recycler.level, 1)
	check("H6 Recycler-lastProcessedAt ergaenzt", typeof(o.island.recycler.lastProcessedAt), "number")

	local q = legacyV14()
	q.daily = { lastClaimDay = "gestern" }
	local oq = PlayerMigration.applyDefaults(q)
	check("H7 daily.lastClaimDay kaputt -> 0", oq.daily.lastClaimDay, 0)
	check("H7 daily.streak ergaenzt", oq.daily.streak, 0)

	local u = legacyV14()
	u.island.towerProgress = { [TowerConfig.FIRST_TOWER] = 12, NichtDa = 4, [TowerConfig.FIRST_TOWER .. "x"] = 0 }
	local ou = PlayerMigration.applyDefaults(u)
	check("H8 gueltiger Fortsetz-Punkt bleibt", ou.island.towerProgress[TowerConfig.FIRST_TOWER], 12)
	check("H8 unbekannter Tower entfernt", ou.island.towerProgress.NichtDa, nil)
end

-- ===============================================================
-- I) Honig-Teich (HONEY_POND_V2 = true): alter Stand mit Stock + Veredler
--    (Vorlage: honey_pond.test.lua 1a-1e)
-- ===============================================================
local function pondFixture()
	local d = legacyV14()
	d.version = 15
	d.island.buildings = {
		Beehive      = { id = "Beehive",      level = 23, honey = 4, lastProducedAt = 1000 },
		HoneyRefiner = { id = "HoneyRefiner", level = 17, honey = 6, lastProducedAt = 1000 },
	}
	return d
end

local pondResult
do
	local out = PlayerMigration.applyDefaults(pondFixture())
	pondResult = deepCopy(out)
	local b = out.island.buildings
	check("I1 nur der Teich ist aktiv", count(b) == 1 and b.HoneyPond ~= nil, true)
	check("I1 Teich-Level = hoechstes altes (23)", b.HoneyPond.level, 23)
	check("I1 Honig uebernommen (4 + 6)", b.HoneyPond.honey, 10)
	check("I1 Stock im Ruhestand mit altem Level", out.island.retiredBuildings.Beehive.level, 23)
	check("I1 Veredler im Ruhestand mit altem Level", out.island.retiredBuildings.HoneyRefiner.level, 17)
	check("I1 Stock-Honig im Ruhestand unveraendert", out.island.retiredBuildings.Beehive.honey, 4)

	-- I2: zweiter Durchlauf aendert nichts (auch wenn der Teich inzwischen ausgebaut wurde)
	local snap = deepCopy(out)
	check("I2 zweiter Lauf aendert nichts", deepEqual(snap, PlayerMigration.applyDefaults(out)), true)

	out.island.buildings.HoneyPond.level = 30
	local again = PlayerMigration.applyDefaults(out)
	check("I2 Teich-Level 30 bleibt", again.island.buildings.HoneyPond.level, 30)
	check("I2 Honig bleibt 10", again.island.buildings.HoneyPond.honey, 10)
	check("I2 Ruhestand unveraendert", again.island.retiredBuildings.Beehive.level, 23)

	-- I3: ein frisch angelegter Standard-Stock ueberschreibt den Ruhestand nicht
	again.island.buildings.Beehive = { id = "Beehive", level = 1, honey = 0, lastProducedAt = 1000 }
	local third = PlayerMigration.applyDefaults(again)
	check("I3 Stock nicht aktiv", third.island.buildings.Beehive, nil)
	check("I3 Ruhestand gewinnt (L23)", third.island.retiredBuildings.Beehive.level, 23)
	check("I3 Teich bleibt 30", third.island.buildings.HoneyPond.level, 30)
end

-- Nur Stock oder nur Veredler vorhanden
do
	local d = pondFixture()
	d.island.buildings.HoneyRefiner = nil
	local out = PlayerMigration.applyDefaults(d)
	check("I4 nur Stock: Teich-Level 23", out.island.buildings.HoneyPond.level, 23)
	check("I4 nur Stock: Honig 4", out.island.buildings.HoneyPond.honey, 4)
end

-- ===============================================================
-- J) HONEY_POND_V2 = false: Stock und Veredler kommen mit altem Level zurueck
-- ===============================================================
do
	withPond(false, function()
		local back = PlayerMigration.applyDefaults(deepCopy(pondResult))
		local b = back.island.buildings
		check("J1 Stock wieder L23", b.Beehive.level, 23)
		check("J1 Veredler wieder L17", b.HoneyRefiner.level, 17)
		check("J1 Stock-Honig wieder 4", b.Beehive.honey, 4)
		check("J1 Veredler-Honig wieder 6", b.HoneyRefiner.honey, 6)
		check("J1 Teich nicht aktiv", b.HoneyPond, nil)
		check("J1 Teich im Ruhestand (Level 23)", back.island.retiredBuildings.HoneyPond.level, 23)
		check("J1 Teich-Honig im Ruhestand (10)", back.island.retiredBuildings.HoneyPond.honey, 10)

		local snap = deepCopy(back)
		check("J2 zweiter Lauf aendert nichts", deepEqual(snap, PlayerMigration.applyDefaults(back)), true)
	end)

	-- v14-Stand direkt im klassischen Modus: Topf/Presse -> Veredler L7, nichts im Ruhestand
	withPond(false, function()
		local out = PlayerMigration.applyDefaults(legacyV14())
		local b = out.island.buildings
		check("J3 klassisch: Veredler L7", b.HoneyRefiner.level, 7)
		check("J3 klassisch: Stock bleibt L2", b.Beehive.level, 2)
		check("J3 klassisch: kein Teich", b.HoneyPond, nil)
		check("J3 klassisch: kein Ruhestand", out.island.retiredBuildings, nil)
	end)
end

FLAGS.HONEY_POND_V2 = originalPond

if failures > 0 then error(failures .. " Test(s) fehlgeschlagen") end
print("migration_hbb: alle Tests gruen")
