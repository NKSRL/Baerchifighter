-- tower_unlock.test.lua — 08.10. Tower-Terminal (Pakete B und C)
-- python tools/luau-tests/run_local.py tools/luau-tests/tower_unlock.test.lua
--
-- 1. Freischalt-Regel: Tower N+1 offen, sobald Tower N geschafft ist
--    (Rekord >= Stage-Zahl), unabhaengig von Rebirths; Deckel = volle
--    Stage-Zahl; kein Rebirth-Hinweis am Deckel.
-- 2. Bestandsschutz (Migration v16 -> v17): was per Rebirth offen war oder
--    einen Rekord hat, bleibt offen; zweiter Durchlauf aendert nichts.
-- 3. Terminal-Zustand und "NEU" aus den Daten.
-- 4. Terminal-Platz auf der Plot-Insel (nicht im Beet, nicht auf dem Steg).
-- 5. Bezahlter Einstieg: Kosten 0 mit Pass (Paket C, Rechnung in TowerConfig).

local TowerConfig     = require(RS.Config.TowerConfig)
local FeatureFlags    = require(RS.Config.FeatureFlags)
local MapConfig       = require(RS.Config.MapConfig)
local Types           = require(RS.Network.Types)
local PlayerMigration = require(SSS.Util.PlayerMigration)

local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else
		failures += 1
		print("FAIL " .. name .. (if detail ~= nil then ": " .. tostring(detail) else ""))
	end
end

local FLAGS = FeatureFlags.FLAGS
local before = FLAGS.TOWER_UNLOCK_BY_CLEAR
FLAGS.TOWER_UNLOCK_BY_CLEAR = true

-- 1. Regel ---------------------------------------------------------------
check("I immer offen", TowerConfig.isOpen(0, "I", {}, nil))
check("II zu bei I/29", not TowerConfig.isOpen(0, "II", { I = 29 }, nil))
check("II offen bei I/30 (Rebirth 0)", TowerConfig.isOpen(0, "II", { I = 30 }, nil))
check("III zu bei II/44", not TowerConfig.isOpen(0, "III", { I = 30, II = 44 }, nil))
check("III offen bei II/45", TowerConfig.isOpen(0, "III", { I = 30, II = 45 }, nil))
check("Final offen bei III/60", TowerConfig.isOpen(0, "Final", { III = 60 }, nil))
check("Rebirths oeffnen nichts mehr", not TowerConfig.isOpen(10, "III", { I = 30 }, nil))
check("gespeicherte Freischaltung zaehlt", TowerConfig.isOpen(0, "III", {}, { III = true }))
check("Rekord im Tower haelt ihn offen", TowerConfig.isOpen(0, "Final", { Final = 3 }, nil))
check("Deckel = volle Stage-Zahl", TowerConfig.getStageCap(0, "II", { I = 30 }, nil) == 45,
	TowerConfig.getStageCap(0, "II", { I = 30 }, nil))
check("Deckel 0 solange zu", TowerConfig.getStageCap(0, "II", { I = 3 }, nil) == 0)
check("kein Rebirth-Hinweis mehr", not TowerConfig.isCapLimiting(0, "I"))
if TowerConfig.get("Endless") then
	check("Endless nach Final 100", TowerConfig.isOpen(0, "Endless", { Final = 100 }, nil)
		and not TowerConfig.isOpen(0, "Endless", { Final = 99 }, nil))
end
local unlocks = TowerConfig.unlocksAfterClear("I", 30)
check("I/30 oeffnet genau II", #unlocks == 1 and unlocks[1] == "II", #unlocks)
check("I/29 oeffnet nichts", #TowerConfig.unlocksAfterClear("I", 29) == 0)
local prev, have, need = TowerConfig.getUnlockProgress("II", { I = 12 })
check("Fortschritt zu II: I 12/30", prev == "I" and have == 12 and need == 30, tostring(prev) .. " " .. have .. "/" .. need)
local prevI = TowerConfig.getUnlockProgress("I", {})
check("I hat keinen Vorgaenger", prevI == nil)

-- Alte Regel bleibt abrufbar (Migration)
check("Altregel: III ab Rebirth 4", TowerConfig.getLegacyStageCap(4, "III", {}) > 0
	and TowerConfig.getLegacyStageCap(3, "III", {}) == 0)

-- 2. Migration / Bestandsschutz ------------------------------------------
local function v16(rebirths: number, records: { [string]: number })
	local data = Types.createDefaultPlayerData() :: any
	data.version = 16
	data.rebirthCount = rebirths
	data.towers = { records = records, claimed = {}, highestTower = "I", selected = "I" }
	return data
end

local a = PlayerMigration.applyDefaults(v16(4, { I = 30, II = 20 })) :: any
check("v17: Version", a.version == 17, a.version)
check("R4: III bleibt offen (Altregel)", a.towers.unlocked.III == true)
check("R4: II offen", a.towers.unlocked.II == true)
check("R4: Final zu", a.towers.unlocked.Final ~= true)

local b = PlayerMigration.applyDefaults(v16(0, { Final = 12 })) :: any
check("Rekord in Final (migriert) -> Final offen", b.towers.unlocked.Final == true)
check("I immer drin", b.towers.unlocked.I == true)

local c = PlayerMigration.applyDefaults(v16(0, { I = 30 })) :: any
check("frisch, I/30 -> II offen", c.towers.unlocked.II == true and c.towers.unlocked.III ~= true)

-- Zweiter Durchlauf: nach v17 gilt die Altregel nicht mehr (ein Rebirth nach
-- dem 08.10. oeffnet nichts), und nichts aendert sich.
local again = PlayerMigration.applyDefaults(a) :: any
check("zweiter Durchlauf stabil", again.towers.unlocked.III == true and again.towers.unlocked.Final ~= true)
local later = PlayerMigration.applyDefaults(v16(0, { I = 5 })) :: any
later.rebirthCount = 6
later = PlayerMigration.applyDefaults(later) :: any
check("Rebirth nach v17 oeffnet nichts", later.towers.unlocked.Final ~= true and later.towers.unlocked.II ~= true)

local fresh = Types.createDefaultPlayerData() :: any
check("neuer Spieler: unlocked = { I }", fresh.towers.unlocked.I == true and fresh.towers.unlocked.II == nil)

-- 3. Terminal / NEU --------------------------------------------------------
check("Terminal zu (I/12)", TowerConfig.terminalState({ records = { I = 12 }, selected = "I", unlocked = { I = true } }) == "locked")
local ready = { records = { I = 30 }, selected = "I", unlocked = { I = true, II = true } }
check("Terminal bereit", TowerConfig.terminalState(ready) == "ready")
check("II ist NEU", TowerConfig.isNew("II", ready))
check("I nie NEU", not TowerConfig.isNew("I", ready))
local switched = { records = { I = 30 }, selected = "II", unlocked = { I = true, II = true } }
check("gewaehlt -> nicht mehr NEU, Terminal normal", not TowerConfig.isNew("II", switched)
	and TowerConfig.terminalState(switched) == "normal")
local fought = { records = { I = 30, II = 2 }, selected = "I", unlocked = { I = true, II = true } }
check("gekaempft -> normal", TowerConfig.terminalState(fought) == "normal")

-- 4. Terminal-Platz --------------------------------------------------------
local term = MapConfig.TOWER_TERMINAL
check("TOWER_TERMINAL vorhanden", term ~= nil)
if term then
	local o = term.offset
	local half = MapConfig.PLOT_SIZE.Z * 0.5
	local footprint = term.footprint
	check("nicht im Beet", o.Z - footprint > half, o.Z - footprint)
	check("auf der Insel", math.sqrt(o.X * o.X + o.Z * o.Z) + footprint < MapConfig.PLOT_ISLAND_RADIUS, o)
	check("nicht im Laufweg / auf dem Steg", math.abs(o.X) - footprint > MapConfig.BRIDGE_WIDTH * 0.5 + 1, math.abs(o.X) - footprint)
	local parts = 0
	local lowest = math.huge
	for _, piece in term.pieces do
		parts += 1
		lowest = math.min(lowest, piece.offset.Y - piece.size.Y * 0.5)
	end
	check("Teile-Budget Terminal <= 30", parts <= 30, parts)
	check("steht auf dem Boden", lowest >= -0.05, lowest)
end

-- 5. Skip-Kosten (Paket C) -------------------------------------------------
check("Skip kostet ohne Pass", TowerConfig.getResumeCost("I", 20, 1, false) > 0)
check("Skip kostet 0 mit Pass", TowerConfig.getResumeCost("I", 20, 1, true) == 0)
check("Stage 1 immer 0", TowerConfig.getResumeCost("II", 1, 3, false) == 0)

FLAGS.TOWER_UNLOCK_BY_CLEAR = before

if failures > 0 then error(failures .. " Test(s) fehlgeschlagen", 0) end
print("tower_unlock: alle Tests gruen")
