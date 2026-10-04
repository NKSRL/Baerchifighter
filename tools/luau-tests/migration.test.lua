-- migration.test.lua — alte Spielstaende durch die Migration schicken
-- Aufruf: cd tools/luau-tests && node run.mjs migration.test.lua
--
-- Drei Spielstaende im Format v6, v10 und v13 (so, wie sie damals im
-- DataStore lagen) laufen durch PlayerMigration.applyDefaults. Geprueft wird:
--   1. das Ergebnis hat die Struktur von Types.createDefaultPlayerData
--      (gleiche Felder, gleiche Typen, keine Altlasten),
--   2. die einzelnen Migrationsschritte haben das Richtige getan,
--   3. ein zweiter Durchlauf aendert nichts mehr (wiederholbar).

local Types           = require(RS.Network.Types)
local PlayerMigration = require(SSS.Util.PlayerMigration)

local fails = 0
local function check(name, cond, detail)
	if cond then
		__log("ok  ", name)
	else
		fails += 1
		__log("FAIL", name, detail and ("— " .. tostring(detail)) or "")
	end
end

--------------------------------------------------------------------------------
-- Hilfen
--------------------------------------------------------------------------------

local function deepCopy(v)
	if type(v) ~= "table" then return v end
	local out = {}
	for k, x in v do out[k] = deepCopy(x) end
	return out
end

local function deepEqual(a, b, path)
	path = path or "data"
	if type(a) ~= type(b) then return false, path .. ": Typ " .. type(a) .. " ~= " .. type(b) end
	if type(a) ~= "table" then
		if a ~= b then return false, path .. ": " .. tostring(a) .. " ~= " .. tostring(b) end
		return true
	end
	for k, x in a do
		local ok, why = deepEqual(x, b[k], path .. "." .. tostring(k))
		if not ok then return false, why end
	end
	for k in b do
		if a[k] == nil then return false, path .. "." .. tostring(k) .. " fehlt links" end
	end
	return true
end

-- Felder, die in Types.PlayerData optional sind und deshalb im Default fehlen.
local OPTIONAL = {
	data   = { language = true, session = true },
	island = { equippedUid = true, pitProgress = true },
}

-- Vergleicht die Struktur mit dem Default: jedes Default-Feld muss da sein und
-- denselben Typ haben; ein Feld, das der Default nicht kennt, ist eine
-- Altlast. Tabellen mit frei waehlbaren Schluesseln (baerchis, eggStock,
-- discovered, ...) werden nur auf "ist Tabelle" geprueft.
local FREE_KEYS = {
	["data.island.baerchis"] = true, ["data.island.eggStock"] = true,
	["data.island.laidEggs"] = true, ["data.discovered"] = true,
	["data.eggTree.unlocked"] = true, ["data.eggTree.hatched"] = true,
	["data.eggTree.pressed"] = true, ["data.eggTree.bypass"] = true,
	["data.quests.dailyClaimed"] = true,
}

local function shapeIssues(got, want, path, optional, out)
	for k, w in want do
		local p = path .. "." .. k
		local g = got[k]
		if g == nil then
			table.insert(out, p .. " fehlt")
		elseif type(g) ~= type(w) then
			table.insert(out, p .. " hat Typ " .. type(g) .. " statt " .. type(w))
		elseif type(w) == "table" and not FREE_KEYS[p] then
			local key = string.match(p, "%.(%w+)$")
			shapeIssues(g, w, p, OPTIONAL[key] or {}, out)
		end
	end
	for k in got do
		if want[k] == nil and not optional[k] then
			table.insert(out, path .. "." .. tostring(k) .. " ist eine Altlast")
		end
	end
end

local BAERCHI_FIELDS = {
	uid = "string", configId = "string", rarity = "string", level = "number",
	xp = "number", skillId = "string", isFusionResult = "boolean",
	fusionBonus = "number", currentHp = "number", promotionLevel = "number",
	statLevels = "table", charms = "table",
}
local BAERCHI_OPTIONAL = { baseStatOverride = "table", mutation = "string" }
local STAT_KEYS = { "hp", "atk", "spd", "pwr", "egg" }

local function baerchiIssues(b, out)
	for field, t in BAERCHI_FIELDS do
		if type(b[field]) ~= t then
			table.insert(out, b.uid .. "." .. field .. " ist " .. type(b[field]) .. " statt " .. t)
		end
	end
	for field, v in b do
		if BAERCHI_FIELDS[field] == nil then
			if BAERCHI_OPTIONAL[field] == nil then
				table.insert(out, b.uid .. "." .. field .. " ist eine Altlast")
			elseif type(v) ~= BAERCHI_OPTIONAL[field] then
				table.insert(out, b.uid .. "." .. field .. " hat falschen Typ")
			end
		end
	end
	if type(b.statLevels) == "table" then
		for _, key in STAT_KEYS do
			if type(b.statLevels[key]) ~= "number" then
				table.insert(out, b.uid .. ".statLevels." .. key .. " fehlt")
			end
		end
		for key in b.statLevels do
			if not table.find(STAT_KEYS, key) then
				table.insert(out, b.uid .. ".statLevels." .. key .. " ist eine Altlast")
			end
		end
	end
	local lastSlot = 0
	for _, charm in (b.charms or {}) do
		if charm.slot <= lastSlot then table.insert(out, b.uid .. ".charms nicht nach slot sortiert") end
		lastSlot = charm.slot
		if type(charm.locked) ~= "boolean" then table.insert(out, b.uid .. ".charm.locked fehlt") end
	end
end

local function checkMatchesTypes(label, data)
	local out = {}
	shapeIssues(data, Types.createDefaultPlayerData(), "data", OPTIONAL.data, out)
	for _, b in data.island.baerchis do
		baerchiIssues(b, out)
	end
	for _, egg in (data.island.laidEggs or {}) do
		if type(egg.uid) ~= "string" or type(egg.x) ~= "number" then
			table.insert(out, "laidEggs: unvollstaendiges Ei")
		end
	end
	check(label .. ": Struktur = Types.PlayerData", #out == 0, table.concat(out, "; "))
end

local function checkIdempotent(label, migrated)
	local again = PlayerMigration.applyDefaults(deepCopy(migrated))
	local same, why = deepEqual(again, migrated)
	check(label .. ": zweiter Durchlauf aendert nichts", same, why)
end

local function migrate(raw)
	local ok, result = pcall(PlayerMigration.applyDefaults, raw)
	return ok, result
end

local NOW = os.time()

--------------------------------------------------------------------------------
-- v6: Brut-Slots, keine Promotion/Charms, keine gelegten Eier, alte Gebaeude
--------------------------------------------------------------------------------

local v6 = {
	version = 6, createdAt = NOW - 86400 * 30, lastSeenAt = NOW - 3600,
	gummies = 5400, goldGummies = 12, rebirthCount = 1, rebirthMult = 1.5,
	rank = { tier = 1, name = "Gummy Hatchling", points = 0 },
	island = {
		pitLevel = 3,
		buildings = {
			Beehive    = { id = "Beehive",    level = 5, honey = 2, lastProducedAt = NOW - 100 },
			HoneyPot   = { id = "HoneyPot",   level = 2, honey = 0, lastProducedAt = NOW - 100 },
			HoneyPress = { id = "HoneyPress", level = 1 },   -- Honig-Felder fehlen
			GummyFarm  = { id = "GummyFarm",  level = 4 },   -- gibt es nicht mehr
		},
		baerchis = {
			b_1 = { uid = "b_1", configId = "RedBaerchi", rarity = "Common", level = 7, xp = 20,
			        skillId = "BasicPunch", isFusionResult = false, fusionBonus = 0, currentHp = 80 },
			b_2 = { uid = "b_2", configId = "GoldenGrizzly", rarity = "Legendary", level = 3, xp = 0,
			        skillId = "BasicPunch" },   -- fusionBonus/currentHp fehlen
		},
		eggStock = { BasicEgg = 2, GoldenEgg = 1 },
		hatchingEggs = {
			{ uid = "e_1", eggType = "GoldenEgg", startedAt = NOW - 50, readyAt = NOW + 50 },
			{ uid = "e_2", eggType = "UraltEi",   startedAt = NOW - 50, readyAt = NOW - 10 },
		},
		equippedUid = "b_1",
	},
	stats = {
		totalGummiesEarned = 9000, totalFightsWon = 40, totalFightsLost = 9,
		totalFusions = 1, totalRebirths = 1, totalRecycled = 3,
		highestPitLevel = 3, highestTowerFloor = 0,
	},
}

do
	local ok, d = migrate(deepCopy(v6))
	check("v6: Migration laeuft ohne Fehler", ok, d)
	if ok then
		checkMatchesTypes("v6", d)
		check("v6: Version 14", d.version == 14, d.version)
		check("v6: Presse erbt hoechstes Gebaeude-Level (v7)", d.island.buildings.HoneyPress.level == 5,
			d.island.buildings.HoneyPress.level)
		check("v6: altes Gebaeude entfernt", d.island.buildings.GummyFarm == nil)
		check("v6: Honig-Felder nachgeruestet", d.island.buildings.HoneyPress.honey == 0
			and type(d.island.buildings.HoneyPress.lastProducedAt) == "number")
		check("v6: Bruten zurueck ins Lager (v12)", d.island.eggStock.GoldenEgg == 2
			and d.island.eggStock.BasicEgg == 3, d.island.eggStock.GoldenEgg)
		check("v6: hatchingEggs entfernt", d.island.hatchingEggs == nil)
		check("v6: laidEggs/lastEggAt angelegt (v10)", #d.island.laidEggs == 0 and d.island.lastEggAt == NOW)
		check("v6: Promotion-Felder angelegt (v8)", d.island.baerchis.b_1.promotionLevel == 0
			and #d.island.baerchis.b_1.charms == 0)
		check("v6: currentHp bleibt stehen", d.island.baerchis.b_1.currentHp == 80)
		check("v6: fehlende currentHp = volle HP (v4)", (d.island.baerchis.b_2.currentHp or 0) > 0,
			d.island.baerchis.b_2.currentHp)
		check("v6: fusionBonus nachgeruestet (v2)", d.island.baerchis.b_2.fusionBonus == 0)
		check("v6: Index aus Bestand gesaeet (v13)", d.discovered.RedBaerchi == true
			and d.discovered.GoldenGrizzly == true)
		check("v6: totalHatched = Anzahl Baerchis (v13)", d.stats.totalHatched == 2, d.stats.totalHatched)
		check("v6: Goldenes Ei im Baum frei (v14)", d.eggTree.unlocked.GoldenEgg == true)
		check("v6: Ausruestung bleibt", d.island.equippedUid == "b_1")
		check("v6: Waehrungen unveraendert", d.gummies == 5400 and d.goldGummies == 12)
		checkIdempotent("v6", d)
	end
end

--------------------------------------------------------------------------------
-- v10: Inverted statt Mutation, DEF-Reste, kaputte Charms und Eier
--------------------------------------------------------------------------------

local v10 = {
	version = 10, createdAt = NOW - 86400 * 10, lastSeenAt = NOW - 60,
	gummies = 120000, goldGummies = 300, rebirthCount = 3, rebirthMult = 3.4,
	rank = { tier = 2, name = "Sugar Brawler", points = 10 },
	language = "fr",
	island = {
		pitLevel = 5,
		buildings = {
			Beehive    = { id = "Beehive",    level = 4, honey = 5, lastProducedAt = NOW - 20 },
			HoneyPot   = { id = "HoneyPot",   level = 6, honey = 1, lastProducedAt = NOW - 20 },
			HoneyPress = { id = "HoneyPress", level = 2, honey = 0, lastProducedAt = NOW - 20 },
		},
		baerchis = {
			b_7 = {
				uid = "b_7", configId = "CrystalBaerchi", rarity = "Epic", level = 20, xp = 5,
				skillId = "BasicPunch", isFusionResult = true, fusionBonus = 0.5, currentHp = 300,
				promotionLevel = 2,
				statLevels = { hp = 3, atk = 1, spd = 0, pwr = 2, def = 4 },   -- egg fehlt, def ist Altlast
				charms = {
					{ slot = 5, rarity = "Rare",   statId = "AtkBoost", value = 0.02 },   -- locked fehlt
					{ slot = 2, rarity = "Common", statId = "HpBoost",  value = 0.01, locked = true },
					{ slot = 3, rarity = "Common", statId = "DefBoost", value = 0.01, locked = false },   -- Stat gibt es nicht mehr
					{ slot = 9, rarity = "Common", statId = "HpBoost",  value = 0.01, locked = false },   -- Slot zu gross
				},
				baseStatOverride = { hp = 200, atk = 20, def = 5 },
				isInverted = true,
			},
		},
		eggStock = { BasicEgg = 1, CrystalEgg = 2 },
		hatchingEggs = {},
		equippedUid = "b_7",
		laidEggs = {
			{ uid = "l_1", eggType = "BasicEgg", laidAt = NOW - 30, x = 1, y = 2, z = 3 },
			{ eggType = "BasicEgg", laidAt = NOW - 30, x = 1, y = 2, z = 3 },   -- ohne uid
		},
		lastEggAt = NOW - 200,
	},
	stats = {
		totalGummiesEarned = 500000, totalFightsWon = 300, totalFightsLost = 40,
		totalFusions = 6, totalRebirths = 3, totalRecycled = 20,
		highestPitLevel = 5, highestTowerFloor = 0,
	},
}

do
	local ok, d = migrate(deepCopy(v10))
	check("v10: Migration laeuft ohne Fehler", ok, d)
	if ok then
		checkMatchesTypes("v10", d)
		local b = d.island.baerchis.b_7
		check("v10: Inverted wird Mutation Diamond (v11)", b.mutation == "Diamond", b.mutation)
		check("v10: def aus statLevels entfernt (v9)", b.statLevels.def == nil)
		check("v10: egg-Stufe nachgeruestet", b.statLevels.egg == 0)
		check("v10: vorhandene Stufen bleiben", b.statLevels.hp == 3 and b.statLevels.pwr == 2)
		check("v10: def aus baseStatOverride entfernt", b.baseStatOverride.def == nil
			and b.baseStatOverride.hp == 200)
		check("v10: nur gueltige Charms bleiben", #b.charms == 2, #b.charms)
		check("v10: Charms nach Slot sortiert", b.charms[1].slot == 2 and b.charms[2].slot == 5)
		check("v10: locked nachgeruestet", b.charms[2].locked == false)
		check("v10: Ei ohne uid verworfen", #d.island.laidEggs == 1)
		check("v10: lastEggAt bleibt", d.island.lastEggAt == NOW - 200)
		check("v10: Presse bleibt (v7 laeuft nur einmal)", d.island.buildings.HoneyPress.level == 2)
		check("v10: Sprache bleibt", d.language == "fr")
		check("v10: Kristall-Ei im Baum frei (v14)", d.eggTree.unlocked.CrystalEgg == true)
		check("v10: Quests angelegt (v13)", type(d.quests) == "table" and d.quests.chainClaimed == 0)
		checkIdempotent("v10", d)
	end
end

--------------------------------------------------------------------------------
-- v13: Quests und Index schon da, Ei-Baum fehlt, Ei-Typ aus alter Config
--------------------------------------------------------------------------------

local v13 = {
	version = 13, createdAt = NOW - 86400 * 3, lastSeenAt = NOW - 10,
	gummies = 777, goldGummies = 4, rebirthCount = 0, rebirthMult = 1,
	rank = { tier = 1, name = "Gummy Hatchling", points = 0 },
	island = {
		pitLevel = 2,
		buildings = {
			Beehive    = { id = "Beehive",    level = 1, honey = 0, lastProducedAt = NOW },
			HoneyPot   = { id = "HoneyPot",   level = 1, honey = 0, lastProducedAt = NOW },
			HoneyPress = { id = "HoneyPress", level = 1, honey = 0, lastProducedAt = NOW },
		},
		baerchis = {
			b_9 = {
				uid = "b_9", configId = "SugarBaerchi", rarity = "Uncommon", level = 4, xp = 0,
				skillId = "BasicPunch", isFusionResult = false, fusionBonus = 0, currentHp = 50,
				promotionLevel = 0, statLevels = { hp = 0, atk = 0, spd = 0, pwr = 0, egg = 1 },
				charms = {}, mutation = "Gold",
			},
		},
		eggStock = { BasicEgg = 4, RubinEi = 2 },   -- RubinEi gibt es nicht
		equippedUid = "b_9",
		laidEggs = { { uid = "l_9", eggType = "GoldenEgg", laidAt = NOW, x = 0, y = 0, z = 0 } },
		lastEggAt = NOW - 5,
		pitProgress = { pitLevel = 2 },   -- reachedStage fehlt
	},
	stats = {
		totalGummiesEarned = 1000, totalFightsWon = 5, totalFightsLost = 1,
		totalFusions = 0, totalRebirths = 0, totalRecycled = 0,
		highestPitLevel = 2, highestTowerFloor = 0, totalHatched = 9,
	},
	discovered = { SugarBaerchi = true, RedBaerchi = true },
	quests = {
		chainClaimed = 3, day = 20000,
		baseline = { hatched = 5, fightsWon = 2, gummies = 100 },
		dailyClaimed = { daily_hatch = true },
	},
}

do
	local ok, d = migrate(deepCopy(v13))
	check("v13: Migration laeuft ohne Fehler", ok, d)
	if ok then
		checkMatchesTypes("v13", d)
		check("v13: unbekanntes Ei wird Basis-Ei", d.island.eggStock.RubinEi == nil
			and d.island.eggStock.BasicEgg == 6, d.island.eggStock.BasicEgg)
		check("v13: halber pitProgress verworfen", d.island.pitProgress == nil)
		check("v13: Quest-Stand bleibt", d.quests.chainClaimed == 3 and d.quests.dailyClaimed.daily_hatch == true)
		check("v13: Index bleibt", d.discovered.RedBaerchi == true)
		check("v13: totalHatched bleibt", d.stats.totalHatched == 9, d.stats.totalHatched)
		check("v13: gelegtes Goldenes Ei schaltet Knoten frei (v14)", d.eggTree.unlocked.GoldenEgg == true)
		check("v13: Mutation bleibt", d.island.baerchis.b_9.mutation == "Gold")
		checkIdempotent("v13", d)
	end
end

--------------------------------------------------------------------------------
-- Aktueller Default: die Migration darf ihn nicht veraendern
--------------------------------------------------------------------------------

do
	local fresh = Types.createDefaultPlayerData()
	local ok, d = migrate(deepCopy(fresh))
	check("Default: Migration laeuft ohne Fehler", ok, d)
	if ok then
		checkMatchesTypes("Default", d)
		local same, why = deepEqual(d, fresh)
		check("Default: unveraendert", same, why)
	end
end

__log(fails == 0 and "ALLE OK" or ("FEHLER: " .. fails))
