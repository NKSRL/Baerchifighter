-- pacing_v2_vorschlag.lua — HBB Paket 8: Wert-Vorschlag, NICHT im Spiel aktiv
-- Aufruf (Vorspann vor der Pacing-Simulation):
--   python tools/luau-tests/run_local.py tools/sim/pacing_v2_vorschlag.lua tools/sim/progression_pacing.lua
--
-- Ueberschreibt im Speicher nur die Werte unten und laesst dann die normale
-- Simulation laufen. Bericht und Tabelle: docs/HBB_PAKET_8_TABELLE_2026-10-05.md
-- Erwartet: genau ein FAIL ("Look 2 in 30-75 min") — die Zielgrenze selbst
-- steht zur Entscheidung (Vorschlag: 20-45 min).

local E = require(RS.Config.EconomyConfig)

-- A) GoldGummies fuer Gebaeude-Level 5-10 x 0,7. Bewusst NACH dem Aufbau der
--    Tabelle: Level 11-60 bleiben unveraendert. (Im Config wuerde eine
--    Aenderung von [10] die Gold-Kosten ab Level 11 mitziehen.)
local GOLD_V2 = { [5] = 2, [6] = 5, [7] = 11, [8] = 21, [9] = 38, [10] = 66 }
for level, gold in GOLD_V2 do
	E.HONEY_UPGRADE_COSTS[level].goldGummies = gold
end

-- B) Rebirth 1 kostet 750.000 statt 1.500.000 Gummies; alle weiteren gleich.
local REBIRTH_1_V2 = 750_000
local baseCost = E.getRebirthCost
E.getRebirthCost = function(rebirthCount)
	if rebirthCount == 0 then return REBIRTH_1_V2 end
	return baseCost(rebirthCount)
end
