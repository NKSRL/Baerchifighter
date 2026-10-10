-- migration_v17.test.lua — Types-Wechsel v16 -> v17 (Tower-Terminal, 10.10.2026)
-- python tools/luau-tests/run_local.py tools/luau-tests/migration_v17.test.lua
--
-- Ersatz hier fuer den Fall v16 -> v17 aus migration.test.lua (der laeuft nur
-- am Heim-PC unter Node). Geprueft wird ein Spielstand im Format der
-- Studio-Types (v16, ohne towers.unlocked):
-- 1. Nach der Migration steht jeder alte Wert unveraendert da (Waehrung,
--    Insel, Baerchis, Rekorde ...). Neu sind nur towers.unlocked und version.
-- 2. Version 17, Tower I offen, Bestandsschutz nach Rebirths.
-- 3. Zweiter Durchlauf aendert nichts mehr.
-- 4. Ein v17-Stand, der von altem Code zurueck auf 16 gesetzt wurde (Rueckweg
--    ueber das Backup), verliert beim erneuten Laden nichts.

local Types           = require(RS.Network.Types)
local PlayerMigration = require(SSS.Util.PlayerMigration)

local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else
		failures += 1
		print("FAIL " .. name .. (if detail ~= nil then ": " .. tostring(detail) else ""))
	end
end

local function deepCopy(value)
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value do
		copy[k] = deepCopy(v)
	end
	return copy
end

-- Jeder Wert aus `before` muss in `after` gleich sein (neue Felder erlaubt).
local function sameValues(before, after, path, ignore, out)
	for k, v in before do
		local p = path .. "." .. tostring(k)
		if not ignore[p] then
			local w = after[k]
			if type(v) == "table" then
				if type(w) ~= "table" then
					table.insert(out, p .. " fehlt")
				else
					sameValues(v, w, p, ignore, out)
				end
			elseif v ~= w then
				table.insert(out, p .. ": " .. tostring(v) .. " -> " .. tostring(w))
			end
		end
	end
	return out
end

-- Ein gespielter v16-Stand, wie ihn die Studio-Types anlegen.
local function v16Save()
	local data = Types.createDefaultPlayerData() :: any
	data.version = 16
	data.towers.unlocked = nil
	data.gummies = 123456
	data.goldGummies = 789
	data.rebirthCount = 4
	data.towers.records = { I = 30, II = 22 }
	data.towers.highestTower = "II"
	data.towers.selected = "II"
	data.towers.claimed = { I = { ["10"] = true, ["20"] = true } }
	return data
end

-- 1.+2. ---------------------------------------------------------------------
local before = v16Save()
local snapshot = deepCopy(before)
local after = PlayerMigration.applyDefaults(before) :: any

local diffs = sameValues(snapshot, after, "data", { ["data.version"] = true }, {})
check("alle alten Werte unveraendert", #diffs == 0, table.concat(diffs, "; "))
check("Version 17", after.version == 17, after.version)
check("Waehrung unberuehrt", after.gummies == 123456 and after.goldGummies == 789)
check("towers.unlocked angelegt", type(after.towers.unlocked) == "table")
check("Tower I offen", after.towers.unlocked.I == true)
check("II offen (Rekord)", after.towers.unlocked.II == true)
check("III offen (Bestandsschutz R4)", after.towers.unlocked.III == true)
check("Final zu", after.towers.unlocked.Final ~= true)
check("Auswahl bleibt II", after.towers.selected == "II")

-- 3. -------------------------------------------------------------------------
local second = deepCopy(after)
local again = PlayerMigration.applyDefaults(second) :: any
local diffs2 = sameValues(after, again, "data", {}, {})
local diffs3 = sameValues(again, after, "data", {}, {})
check("zweiter Durchlauf aendert nichts", #diffs2 == 0 and #diffs3 == 0,
	table.concat(diffs2, "; ") .. " | " .. table.concat(diffs3, "; "))

-- 4. Rueckweg: alter Code setzt version = 16, unlocked bleibt stehen ---------
local rolledBack = deepCopy(after)
rolledBack.version = 16
local back = PlayerMigration.applyDefaults(rolledBack) :: any
check("nach Rueckweg: Version wieder 17", back.version == 17, back.version)
check("nach Rueckweg: Freischaltungen bleiben",
	back.towers.unlocked.I == true and back.towers.unlocked.II == true and back.towers.unlocked.III == true)

-- Frischer Spieler --------------------------------------------------------------
local fresh = PlayerMigration.applyDefaults(Types.createDefaultPlayerData()) :: any
check("neuer Spieler: v17, nur I offen", fresh.version == 17 and fresh.towers.unlocked.I == true
	and fresh.towers.unlocked.II == nil)

if failures > 0 then
	error(("migration_v17: %d FAIL"):format(failures))
end
print("migration_v17: alles gruen")
