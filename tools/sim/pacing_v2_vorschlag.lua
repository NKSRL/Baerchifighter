-- pacing_v2_vorschlag.lua — HBB Paket 8: offener Wert-Vorschlag, NICHT im Spiel aktiv
-- Aufruf (Vorspann vor der Pacing-Simulation):
--   python tools/luau-tests/run_local.py tools/sim/pacing_v2_vorschlag.lua tools/sim/progression_pacing.lua
--
-- Ueberschreibt im Speicher nur den Wert unten und laesst dann die normale
-- Simulation laufen. Bericht: docs/HBB_PAKET_8_TABELLE_2026-10-05.md
-- (Vorschlag A "Gold L5-10 x 0,7" ist mit GOLD_CHARMS_ONLY hinfaellig.)
-- Stand 05.10. mit GOLD_CHARMS_ONLY: NICHT EMPFOHLEN. Gelegenheit nur Tag 8 -> 7,
-- dafuer faellt Look 4 bei Normal auf 5,1 h (FAIL, Ziel >= 6 h).

local E = require(RS.Config.EconomyConfig)

-- B) Rebirth 1 kostet 750.000 statt 1.500.000 Gummies; alle weiteren gleich.
--    Ziel: Gelegenheitsspieler (30 min/Tag) erreichen Rebirth 1 in Woche 1.
local REBIRTH_1_V2 = 750_000
local baseCost = E.getRebirthCost
E.getRebirthCost = function(rebirthCount)
	if rebirthCount == 0 then return REBIRTH_1_V2 end
	return baseCost(rebirthCount)
end
