# P2 – Tower F Stage 100 leichter (20.10.2026)

Schalter `TOWER_F_EASIER` (aus = alte Werte 1:1; alt/neu stehen nebeneinander in `TowerConfig`).

## Aenderung
| | alt | neu |
|---|---|---|
| Final `startEquivalent` | 82 | **52** |
| Final `equivalentPerStage` | 0,5 | **0,303** (Stage 100 ~ Aequivalenz 82 statt 131,5) |
| Final `rewardFactor` | 1 | **10** |
| Tower III | 55 / 0,6 | unveraendert |
| Endless | 132 / 0,5 | unveraendert (fester Anker, A4) |

## Messung (tower_calibration.lua, Einzel-Baerchi, Stage-Rekord in Final, max. 100)
Profil L50 Max (P10 C S100): Epic 86 | Legendaer 91 | Mythisch 100 | Divine+ 100 | Omega 100.
Profil L50 P5 C S50: Epic < 80 | Mythisch >= 85 | Omega 100.
Alt: Max Epic 4, Legendaer 6, Mythisch 16, Divine 55, Omega 93.
Ziel erreicht: Mythisch (und hoeher) schafft Final 100, Legendaer kommt knapp heran (91), Epic scheitert (86), Omega locker.

## Abweichung vom Auftrag: Monotonie zu Tower III
Final 1 (Aequivalenz 52) liegt unter dem Ende von III (90,4). Streng monoton ist nicht erreichbar: damit Mythisch Final 100 schafft, muss Final unter ~90 enden, III endet aber bei 90,4 und braucht den vollen Ausbau. Es gibt dafuer Vorbild: II endet bei 66,8, III startet bei 55 — jeder Tower beginnt wieder leichter. III wurde deshalb **nicht** angefasst.

## Belohnung
Summe aller Final-Stage-Gummies pro kompletten Lauf: alt ~10,1 Mrd, neu bei Faktor 1 ~0,73 Mrd, **bei Faktor 10 ~7,3 Mrd** (Tower III ~3,3 Mrd). Faktor 10 haelt den Final-Lauf wertvoller als III, ohne dass Mythisch-Teams mehr als bisher Omega-Teams verdienen. `goldPerFive` unveraendert.

## Epilog / Freischaltung
Unveraendert: Final 100 bleibt Ausloeser (`UNLOCK_AFTER`, `isEndlessOpen`), Rekord-Kodierung `Index*1000+Stage` gleich, keine Migration. Der Epilog startet weiter erst nach gespeichertem Sieg (Code nicht angefasst, nicht neu geprueft).

## Tests
`tower_calibration.lua` ALLE OK (Pruefungen je nach Schalter), `boss_balance`, `pit_balance`, `boss_tiers`, `guide_steps`, `tower_unlock`, `endless` (Endless-Anker-Pruefung auf Schalter angepasst), `combat_rating`, `gold_rules` gruen. `unlock_rules`: 1 bekannter Alt-Fehler.

## Offen / Entscheidung
1. `progression_pacing.lua`: 5 Alt-Fehler (auch mit Schalter aus), mit Schalter an **2 neue**: `Viel: Endless Woche 16 bei 80-100` (jetzt 43) und `Viel: Endless steht eine Woche still`. Ursache: Final faellt frueher, Endless bleibt bei 132 -> Wand. Test: Endless-Start 110 bringt Woche 16 auf Stage 83 (ok), "steht still" bleibt rot. Entscheidung fuer dich: Endless-Anker senken (eine Zahl) oder die Sim-Ziele anpassen.
2. `towerforecast`-Debugbefehl nicht gebaut (braucht Team-Schaetzung).
3. Zahlen gelten fuer Einzel-Baerchi; Team-Test in Studio steht aus.
