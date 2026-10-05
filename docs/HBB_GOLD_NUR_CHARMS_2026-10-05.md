# GoldGummies nur noch für Charms – umgesetzt 05.10.2026

Entscheidung des Projektinhabers: GoldGummies gibt es nur noch aus Tages-Quests
(später zusätzlich als Gratis-Griff im Shop) und man gibt sie nur noch für Charms aus.
Kein Upgrade hängt mehr an Gold, der Fortschritt läuft allein über Gummies.

Schalter: `FeatureFlags.GOLD_CHARMS_ONLY = true`. Auf `false` gestellt verhält sich alles exakt wie vorher.

## Was der Schalter ändert
| Stelle | vorher | jetzt |
| --- | --- | --- |
| Gebäude-Ausbau L2–60, Recycler (`EconomyConfig.HONEY_UPGRADE_COSTS`) | Gummies + Gold | nur Gummies |
| Tower-Lauf (`TowerConfig.getRunGold`) | Gold je 5 Stages | 0 |
| Tower-Meilensteine (`TowerConfig.getMilestone`) | Gold alle 25 Stages, leere → Gold | kein Gold; leere (35, 45, …) → flache Gummies (10 × Stage-Belohnung) |
| Login-Bonus (`LoginBonusConfig.DAYS_V2`) | Tag 2/4/5/6/7 Gold | kein Gold; Tag 5 → 10.000, Tag 7 → 30.000 Gummies |
| Tages-Quests (`QuestConfig.DAILY`, `goldReward`) | nur Gummies | **+100 Gold je Quest** (= 4 Charm-Würfe, 12 pro Tag) |
| Gummi-Kurve L11–30 (`COST_GROWTH_AFTER_10`) | 1,22 | 1,23 (Ausgleich, s. u.) |
| Charm-Wurf | 25 Gold | unverändert, einzige Ausgabe |

Events vergeben schon heute kein Gold (kein `goldGummies`-Bonus in `EventConfig`). Vorhandenes Gold bleibt den Spielern erhalten.
Anzeige: Quest-Zeile zeigt „+100 GoldGummies“ (`ui.quest.reward_gold`, 4 Sprachen); Preise mit 0 Gold blendet die UI schon aus.

## Pacing nur mit Gummies (`progression_pacing.lua`, alle 7 Ziele grün)
| Meilenstein (Normal 90 min/Tag) | vorher | ohne Gold, 1,22 | **jetzt (1,23)** |
| --- | --- | --- | --- |
| Look 2 | 32 min | 28 min | **28 min** (Tag 1 auch bei 30 min/Tag) |
| Look 3 | 4,5 h | 3,9 h | 3,9 h |
| Look 4 | 7,0 h | 5,9 h ✗ | 6,3 h |
| Look 5 / 6 | 19,1 / 61,0 h | 18,4 / 61,0 h | 18,0 / 68,6 h |
| Rebirth 1 / 10 | 3,5 / 76,6 h | 3,5 / 76,6 h | 3,6 / 76,1 h |
| Final 100 | 156,9 h | 156,9 h | 156,9 h |

Gold hat vor allem das frühe Spiel gebremst (L5–10). Ab Mitte des Spiels gab ohnehin der Gummi-Preis den Takt vor.
Ziel Look 2 im Sim von 30–75 auf **20–45 min** gesetzt: Der erste große Moment soll in die erste Sitzung fallen.

## Charms und Endgame – entschieden: 12 Würfe pro Tag (100 Gold je Tages-Quest)
Ein Legendary-Charm kommt mit 1 % (Ascended 0,1 %). Acht davon brauchen im Mittel ~730 Würfe.
`tower_calibration.lua` setzt für Final 100 Maximal-Ausbau **mit 8 Legendary-Charms** voraus.

| Würfe pro Tag | Tage bis 8 Legendary (Mittel) |
| --- | --- |
| 3 (erster Stand: 3 × 25 Gold) | ~240 |
| **12 (jetzt: 3 × 100 Gold)** | **~60** |
| 25 | ~30 |

Vorher hatte ein Spieler nach 3,5 h bereits ~1.600 Gold (~64 Würfe).
Folge: Der Ausbau-Bonus im Pacing-Sim (`POWER_BONUS`, Annahme) ist jetzt zu optimistisch, und Final 100 rückt für die meisten weit nach hinten.
Möglichkeiten (einzeln oder kombiniert):
1. Mehr Gold je Tages-Quest bzw. mehr Tages-Quests (eine Zahl: `DAILY_GOLD` in `QuestConfig`).
2. Gratis-Griff im Shop (Paket 10) großzügig.
3. Billigerer Wurf (`CharmConfig.ROLL_COST_GOLD_GUMMIES`) oder bessere Legendary-Chance.
4. Final 100 neu kalibrieren (weniger Charm-Anteil).
5. Gold-Pakete für Robux. Das ist der übliche Roblox-Weg, aber Pay-to-Win-Gefahr, weil Charms Kampfkraft geben.

## Prüfungen
- `python tools/luau-tests/run_local.py tools/luau-tests/gold_rules.test.lua`: kein Ausbau kostet Gold, keine Quelle außer Tages-Quests, kein Meilenstein leer, Charm kostet Gold.
- Alle Sims, alle Luau-Tests, `check_*.py`, Syntax aller `.luau`: grün.

## Studio-Testschritte
1. Gebäude-Menü: nur noch Gummi-Preis, Ausbau ohne Gold möglich.
2. Tower-Lauf: kein „+GoldGummies“; Meilenstein 35 gibt Gummies.
3. Tages-Quest abholen: Text „… +100 GoldGummies“, Gold-Pille steigt um 100.
4. Charm würfeln: kostet 25 Gold wie bisher.
5. `GOLD_CHARMS_ONLY = false` → altes Verhalten (Gold-Preise, Tower-Gold).
