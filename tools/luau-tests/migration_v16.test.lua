-- migration_v16.test.lua — Sammel-Update 05.10.: Fall v15 -> v16
-- python tools/luau-tests/run_local.py tools/luau-tests/migration_v16.test.lua
-- (Zum Zusammenfuehren mit migration.test.lua auf dem Heim-PC: der Block
-- unten kann 1:1 als neuer Fall uebernommen werden.)
--
-- Prueft: v16-Felder werden angelegt (island.stageBest aus towerProgress
-- gesaeet, island.incubator, indexClaimed, specialClaimed), keine Waehrung
-- wird angefasst, Versionsnummer 16, zweiter Durchlauf aendert nichts.

local PlayerMigration = require(SSS.Util.PlayerMigration)
local Types           = require(RS.Network.Types)

local failures = 0
local function check(name, got, want)
	if got ~= want then
		failures += 1
		print("FAIL " .. string.format("%s: erwartet %s, bekommen %s", name, tostring(want), tostring(got)))
	else
		print("ok   " .. name)
	end
end

local function deepCopy(t)
	if type(t) ~= "table" then return t end
	local c = {}
	for k, v in t do c[k] = deepCopy(v) end
	return c
end

local function deepEqual(a, b)
	if type(a) ~= type(b) then return false end
	if type(a) ~= "table" then return a == b end
	for k, v in a do if not deepEqual(v, b[k]) then return false end end
	for k in b do if a[k] == nil then return false end end
	return true
end

local function legacyV15()
	local d = deepCopy(Types.createDefaultPlayerData()) :: any
	d.version = 15
	d.island.stageBest = nil
	d.island.incubator = nil
	d.indexClaimed = nil
	d.specialClaimed = nil
	d.island.towerProgress = { I = 23, II = 1 }
	d.gummies = 123456
	d.goldGummies = 789
	return d
end

local default = Types.createDefaultPlayerData()
check("Default: Version 16", default.version, 16)
check("Default: 6 Start-Eier (Paket 6.4)", default.island.eggStock.BasicEgg, 6)
check("Default: stageBest leer", next(default.island.stageBest), nil)
check("Default: Inkubator Level 1", default.island.incubator.level, 1)

local out = PlayerMigration.applyDefaults(legacyV15())
check("v16: Version", out.version, 16)
check("v16: stageBest I = 22 (betreten 23)", out.island.stageBest.I, 22)
check("v16: stageBest II nicht gesaeet (betreten 1 = nichts geschafft)", out.island.stageBest.II, nil)
check("v16: Inkubator angelegt", typeof(out.island.incubator), "table")
check("v16: Inkubator Level 1", out.island.incubator.level, 1)
check("v16: Inkubator leer", #out.island.incubator.slots, 0)
check("v16: indexClaimed leer", typeof(out.indexClaimed) == "table" and next(out.indexClaimed) == nil, true)
check("v16: specialClaimed leer", typeof(out.specialClaimed) == "table" and next(out.specialClaimed) == nil, true)
check("v16: Gummies unberuehrt", out.gummies, 123456)
check("v16: GoldGummies unberuehrt", out.goldGummies, 789)

local again = PlayerMigration.applyDefaults(deepCopy(out))
check("v16: zweiter Durchlauf aendert nichts", deepEqual(again, out), true)

-- Ein v16-Stand mit Inhalt bleibt, wie er ist
local full = deepCopy(out)
full.island.stageBest = { II = 30 }
full.island.incubator = { level = 4, slots = { { slot = 1, baerchiUid = "b1", lastEggAt = 10, eggs = { "SugarEgg" } } } }
full.indexClaimed = { ["egg:BasicEgg"] = true }
local kept = PlayerMigration.applyDefaults(deepCopy(full))
check("v16: stageBest bleibt", kept.island.stageBest.II, 30)
check("v16: Inkubator-Baerchi bleibt", kept.island.incubator.slots[1].baerchiUid, "b1")
check("v16: wartendes Ei bleibt", kept.island.incubator.slots[1].eggs[1], "SugarEgg")
check("v16: Inkubator-Level bleibt", kept.island.incubator.level, 4)
check("v16: indexClaimed bleibt", kept.indexClaimed["egg:BasicEgg"], true)

-- Umbau 05.10.: ein alter Ei-Eintrag (Brutzeit-Modell) geht zurueck ins Lager
local oldModel = deepCopy(out)
oldModel.island.eggStock.GoldenEgg = 2
oldModel.island.incubator = { level = 2, slots = { { slot = 1, eggType = "GoldenEgg", startedAt = 10, finishAt = 130 } } }
local moved = PlayerMigration.applyDefaults(oldModel)
check("Umbau: alter Ei-Platz geraeumt", #moved.island.incubator.slots, 0)
check("Umbau: Ei zurueck im Lager", moved.island.eggStock.GoldenEgg, 3)

if failures > 0 then error(failures .. " Test(s) fehlgeschlagen", 0) end
print("migration_v16: alle Tests gruen")
