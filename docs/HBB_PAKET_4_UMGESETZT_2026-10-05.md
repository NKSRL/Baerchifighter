# HBB Paket 4 umgesetzt (Teil) – 05.10.2026

## Neu
- `Modules/CombatRating`: eine Zahl pro Bärchi aus den **effektiven** Werten von `CombatCalculator` (Level, Promotion, Stat-Stufen, Charms, Mutation): `√(maxHp · ATK · SPD · (1+PWR)) · 10`. Name "Kampfwert", Anzeige "⚔ 1,2K".
- `Config/RarityBandConfig` + `Theme.BAND_COLORS`/`Theme.bandColor`: 12 Rarities → 5 Farbbänder (nur Anzeige).
- Inventar-Zeilen: Kampfwert groß statt HP/ATK, Akzent in Bandfarbe.
- Bärchi-Karte: Kampfwert-Zeile im Kopf, Bandfarbe; Zeile "⬆ + 🐻" öffnet das bestehende Fusions-Fenster mit diesem Bärchi (sichtbar nach Freischaltung "Upgrade").
- `tools/luau-tests/run_local.py`: führt Luau-Tests mit einer kleinen Roblox-Attrappe ohne Node aus.

## Prüfergebnisse
| Werkzeug | Ergebnis |
| --- | --- |
| `python tools/luau-tests/run_local.py tools/luau-tests/combat_rating.test.lua` | grün: steigt in jedem Stat; **Spearman ρ = 1,000** zwischen Kampfwert und höchster schlagbarer Äquivalenz-Stage (30 Bärchis, 10 Arten × Level 1/15/30, echtes Kampfmodell) |
| luau-compile | grün |
| sim/pit_balance.lua | nicht vorhanden (Heim-PC) – durch obigen Test ersetzt |

## Annahmen und Abweichungen
- **Kein eigener Tab.** Die Bärchi-Karte ist eine einzige Scroll-Karte; ein Tab-System wäre ein Umbau. Stattdessen eine "Stärker machen"-Zeile über der Promotion (Befördern bleibt darunter, Fusion öffnet das Fusions-Fenster). Bewusst kleiner als geplant.
- Einzelwerte (HP, ATK, SPD, PWR) sind noch **nicht** in einen Aufklapper gewandert.
- Ei-Presse/Blaupausen: haben keinen eigenen Einstieg außerhalb von `EggTreePanel` gefunden – nichts verschoben.

## Studio-Testschritte für den Menschen
1. Inventar öffnen: jede Zeile zeigt "⚔ Zahl", stärkere Bärchis höhere Zahl.
2. Karte öffnen: Kampfwert groß, Farbband statt Einzelfarbe. "⬆ + 🐻" öffnet Fusion mit diesem Bärchi.
3. Eine Fusion und eine Beförderung durchführen – Ergebnis wie vorher.
4. `UI_V2_UPGRADE_TAB = false` → alte Ansicht.

## Offen
- Aufklapper für Einzelwerte, echter Upgrade-Tab (falls gewünscht).
