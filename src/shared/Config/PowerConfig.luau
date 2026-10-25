--!strict
-- PowerConfig.luau
-- ReplicatedStorage/Config/PowerConfig.luau
--
-- Welt 1, Paket 5b (20.10.2026): Werte des Staerke-Modells V2 (Schalter POWER_MODEL_V2, Standard aus).
-- Leitidee: Rarity gibt eine moderate Basis und ein Minimum, entscheidet aber nicht allein.
-- Ein guter individueller Wurf ("Roll", deterministisch aus der uid) schlaegt die naechsten Rarities.
-- Alle Zahlen sind Startwerte, tools/sim/power_model_v2.lua prueft die Zielmatrix.
-- Eigenes Modul (nichts in MapConfig/BaerchiConfig): alt und neu laufen nebeneinander.

local PowerConfig = {}

-- Referenzstaerke g = sqrt(hp * atk) eines Common-Baerchis (Bestand: 32.2 .. 33.4).
PowerConfig.G_REF = 32.4

-- Rarity-Basis: g waechst je Rarity-Stufe um diesen Anteil (Vorgabe +6..10 %, Startwert 6 %).
PowerConfig.POWER_PER_RARITY = 0.06

-- Wurf: Gesamtstaerke T = lo + (hi - lo) * u^SHAPE, u = Zufall aus der uid (0..1),
-- lo(k) = 1 - SPREAD + FLOOR_PER_RARITY * k, hi = 1 + SPREAD_UP. SHAPE > 1: die meisten Pets liegen leicht unter
-- dem Schnitt, ein richtig guter Wurf ist selten (Top 15 % ab u = 0,85). Werte aus tools/sim/power_sweep.lua
-- (Zielmatrix a/b/c). Das "Rarity-Minimum" ist die steigende Untergrenze g(k) * lo (Rarity-Basis waechst
-- je Stufe); FLOOR_PER_RARITY hebt lo zusaetzlich, ist im Startwert 0, weil Matrix (a) sonst kippt.
PowerConfig.SPREAD = 0.12        -- nach unten
PowerConfig.SPREAD_UP = 0.20     -- nach oben
PowerConfig.SHAPE = 2.0
PowerConfig.FLOOR_PER_RARITY = 0.0

-- Ungleiche Verteilung auf die Werte: hp = T^(1+w), atk = T^(1-w), w in [-SKEW, SKEW].
PowerConfig.SKEW = 0.40
-- Tempo folgt dem Wurf nur zu diesem Anteil (SPD bleibt ein ruhiger Wert).
PowerConfig.SPD_FOLLOW = 0.25
-- Skill-Wurf: eigene Streuung auf PWR, unabhaengig von der Rarity (Faehigkeiten sind nicht mehr "nur hohe Rarity").
PowerConfig.SKILL_SPREAD = 0.25
PowerConfig.PWR_FOLLOW = 0.5

-- Bestandsschutz: Baerchis, deren uid-Zeitstempel VOR diesem Wert liegt, bekommen T >= 1.0 (nie schwaecher
-- als der Durchschnitt). 0 = kein Stichtag (nur gesetzt, wenn das Modell aktiviert wird).
PowerConfig.LEGACY_CUTOFF_TIME = 0

-- Wurf-Qualitaet (Perzentil 0..1 innerhalb der Rarity) -> Text-Schluessel (ui.power.grade.*).
PowerConfig.GRADES = {
	{ max = 0.20, key = "weak" },
	{ max = 0.45, key = "average" },
	{ max = 0.75, key = "good" },
	{ max = 0.92, key = "great" },
	{ max = 1.01, key = "outstanding" },
} :: { { max: number, key: string } }

-- Tower-Gegner im Modell V2 (Faktor auf HP und ATK der Gegner, je Tower), weil die Spieler-Spanne zwischen
-- den Rarities schmaler ist. Kalibriert mit tools/sim/power_calibrate_towers.lua auf "Common, Level 50, voller Ausbau":
-- II: schlechter Wurf (p10) schafft 45/45, III: guter Wurf (p90) 60/60, Final: guter Wurf (p90) 100/100. Tower I bleibt.
PowerConfig.TOWER_ENEMY_SCALE = { I = 1, II = 0.556, III = 0.063, Final = 0.0996, Endless = 0.0996 } :: { [string]: number }

return PowerConfig
