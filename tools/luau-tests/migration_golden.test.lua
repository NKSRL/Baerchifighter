-- migration_golden.test.lua — Vorher/Nachher-Vergleich fuer PlayerMigration.applyDefaults (20.10.2026)
-- python tools/luau-tests/run_local.py tools/luau-tests/migration_golden.test.lua > ausgabe.txt
--
-- Schickt viele, absichtlich verschiedene alte/kaputte Spielstaende durch applyDefaults und
-- druckt das Ergebnis deterministisch (Schluessel sortiert, echte Zeit-Werte (10-stellig, 179...) werden beim Vergleich per sed zu T). Zum Umbauen von
-- PlayerMigration: Ausgabe VORHER und NACHHER speichern und mit diff vergleichen - jede
-- Abweichung ist eine Verhaltensaenderung. Die Datei prueft selbst nichts.

local PlayerMigration = require(SSS.Util.PlayerMigration)
local Types           = require(RS.Network.Types)
local FeatureFlags    = require(RS.Config.FeatureFlags)

local NOW = 1_700_000_000

local function ser(v, indent)
	if type(v) ~= "table" then
		if type(v) == "string" then return string.format("%q", v) end
		return tostring(v)
	end
	local keys = {}
	for k in v do table.insert(keys, k) end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	local parts = {}
	for _, k in keys do table.insert(parts, tostring(k) .. "=" .. ser(v[k])) end
	return "{" .. table.concat(parts, ",") .. "}"
end

local function deepCopy(t)
	if type(t) ~= "table" then return t end
	local c = {}
	for k, v in t do c[k] = deepCopy(v) end
	return c
end

local function base()
	local d = Types.createDefaultPlayerData()
	d.createdAt = NOW - 100000
	d.lastSeenAt = NOW - 50
	return d
end

local function addBaerchi(d, uid, id, level)
	d.island.baerchis[uid] = { uid = uid, configId = id, rarity = "Common", level = level, xp = 0, nickname = nil }
end

local cases = {}
local function add(name, fn) table.insert(cases, { name = name, fn = fn }) end

add("default", function(d) return d end)
for _, v in { 0, 1, 3, 6, 7, 12, 13, 14, 15, 16, 17, 18, 19 } do
	add("version " .. v, function(d)
		d.version = v
		addBaerchi(d, "a", "RedBaerchi", 5)
		addBaerchi(d, "b", "SugarBaerchi", 12)
		d.island.eggStock.GoldenEgg = 2
		d.island.eggStock.KaputtesEi = 4
		d.rebirthCount = v % 5
		return d
	end)
end
add("alt: Felder fehlen", function(d)
	d.gummies = nil; d.goldGummies = nil; d.rebirthCount = nil; d.rebirthMult = nil; d.rank = nil
	d.discovered = nil; d.quests = nil; d.eggTree = nil; d.towers = nil; d.daily = nil; d.uiSeen = nil
	d.indexClaimed = nil; d.specialClaimed = nil; d.epilog = nil; d.worlds = nil; d.journey = nil; d.shop = nil
	d.version = 5
	d.stats.sessions = nil; d.stats.totalHatched = nil
	addBaerchi(d, "a", "RedBaerchi", 3)
	return d
end)
add("alt: Bruteier und pitProgress", function(d)
	d.version = 11
	local i = d.island :: any
	i.hatchingEggs = { { eggType = "BasicEgg" }, { eggType = "Unbekannt" }, "muell", { eggType = 5 } }
	i.pitLevel = 9
	i.pitProgress = { pitLevel = 9, reachedStage = 14 }
	i.pitRefund = 12
	i.towerProgress = { I = 5, Muell = 3, II = 0, III = "x" }
	addBaerchi(d, "a", "RedBaerchi", 20)
	d.stats.highestPitLevel = 4
	d.stats.highestTowerFloor = 7
	return d
end)
add("alt: halber pitProgress", function(d)
	d.version = 11
	local isl = d.island :: any
	isl.pitProgress = { pitLevel = "x" }
	return d
end)
add("alt: Gebaeude Topf/Presse", function(d)
	d.version = 6
	local b = d.island.buildings :: any
	b.HoneyPot = { id = "HoneyPot", level = 7, honey = 3, lastProducedAt = NOW - 10 }
	b.HoneyPress = { id = "HoneyPress", level = 2, honey = 2, lastProducedAt = NOW - 10 }
	b.Beehive = { id = "Beehive", level = 4 }
	b.Hatchery = { id = "Hatchery", level = 3 }
	b.HoneyRefiner = nil
	return d
end)
for _, pond in { true, false } do
	add("Teich " .. tostring(pond), function(d)
		d.version = 14
		FeatureFlags.FLAGS.HONEY_POND_V2 = pond
		local b = d.island.buildings :: any
		b.HoneyPot = { id = "HoneyPot", level = 30, honey = 99999, lastProducedAt = NOW }
		b.HoneyPress = { id = "HoneyPress", level = 50, honey = 5, lastProducedAt = NOW }
		return d
	end)
end
add("Eier kaputt", function(d)
	d.version = 9
	d.island.laidEggs = { { uid = "x", eggType = "BasicEgg", x = 1, y = 2, z = 3 }, { eggType = "BasicEgg" }, { uid = "", eggType = "BasicEgg", x = 1, y = 1, z = 1 } }
	d.island.lastEggAt = nil
	local isl = d.island :: any
	isl.recycler = { level = "x", queued = nil }
	return d
end)
add("Tower: Rekorde kaputt", function(d)
	d.version = 16
	d.rebirthCount = 3
	d.towers = { records = { I = 12.7, II = -3, Muell = 5, III = "40", Final = 1000 }, claimed = { I = { ["5"] = true, ["x"] = true, ["10"] = false }, Muell = {}, II = "x" }, highestTower = "Quatsch", selected = "Bla", unlocked = { Muell = true, II = 1 } }
	return d
end)
add("Tower: Final 100 v17", function(d)
	d.version = 17
	d.towers.records = { I = 30, II = 45, III = 60, Final = 100 }
	d.epilog = nil; d.worlds = nil
	return d
end)
add("Tower: Final 99 v18 gueltig", function(d)
	d.version = 18
	d.towers.records = { I = 30, Final = 99 }
	d.epilog = { state = "seen", firstClearAt = 5 }
	return d
end)
add("Baerchi: alte Felder", function(d)
	d.version = 3
	addBaerchi(d, "a", "RedBaerchi", 10)
	addBaerchi(d, "b", "OmegaBaerchi", 50)
	local a = d.island.baerchis.a :: any
	a.promotionLevel = nil; a.statLevels = nil; a.charms = nil; a.fusionBonus = nil; a.currentHp = nil
	local b = d.island.baerchis.b :: any
	b.currentHp = 999999; b.promotionLevel = 3
	return d
end)
add("Shop/Daily kaputt", function(d)
	local dd = d :: any
	dd.shop = "x"
	dd.daily = 5
	d.island.stageBest = "x"
	local isl = d.island :: any
	isl.incubator = "x"
	dd.indexClaimed = 1
	dd.journey = { claimed = 5, skipped = "x", hidden = 2 }
	return d
end)
add("Journey: Veteran v18", function(d)
	d.version = 18
	d.stats.totalHatched = 50
	addBaerchi(d, "a", "RedBaerchi", 10)
	d.island.equippedUid = "a"
	d.towers.records = { I = 30, II = 45 }
	d.towers.unlocked = { I = true, II = true, III = true }
	return d
end)

local pond0 = FeatureFlags.FLAGS.HONEY_POND_V2
for _, c in cases do
	FeatureFlags.FLAGS.HONEY_POND_V2 = true
	local d = c.fn(base())
	local ok, out = pcall(PlayerMigration.applyDefaults, d)
	if not ok then
		print(c.name .. " => FEHLER " .. tostring(out))
	else
		print(c.name .. " => " .. ser(out))
		-- zweiter Lauf (Idempotenz)
		local ok2, out2 = pcall(PlayerMigration.applyDefaults, deepCopy(out))
		print(c.name .. " (2. Lauf) => " .. (if ok2 then ser(out2) else "FEHLER " .. tostring(out2)))
	end
end
FeatureFlags.FLAGS.HONEY_POND_V2 = pond0
print("migration_golden: " .. #cases .. " Faelle")
