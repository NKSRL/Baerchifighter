# HBB Fortschritt ohne Rebirth in Welt 1 (Paket 5e, 20.10.2026)

Messwerkzeug: `tools/sim/fortschritt_w1.lua` (Kopie von `progression_pacing.lua`, Rebirth erst nach Final 100 = Welt 2,
Ereignis-Log, Takt- und Anti-Speedrun-Tabelle). Aufruf: `python3 tools/luau-tests/run_local.py tools/sim/fortschritt_w1.lua`.
Alle Zahlen: aktive Spielzeit, Modell wie im alten Pacing-Sim (Annahmen siehe dort: 2-min-Lauf, Geduld 20 min, Ausbau-Bonus nach Stunden).

## Vorher (Rebirth erlaubt, `progression_pacing.lua`) / nachher (kein Rebirth vor Welt 2)

| Meilenstein (Profil Normal, 90 min/Tag) | vorher | nachher |
|---|---|---|
| Look 2 / 3 / 4 | 20 min / 66 min / 2,2 h | 20 min / 66 min / 1,9 h |
| Look 5 (L45) | 10,4 h | 25,4 h |
| Look 6 (L60) | 44,0 h | 45,2 h |
| Rebirth 1 | 0,9 h | gesperrt bis Welt 2 |
| Final 100 | 43,4 h | 43,3 h (Tag 29) |

Das alte Modell verfehlte die Pacing-Ziele schon vorher (7 FAIL, u. a. Rebirth 1 nach 0,9 h statt 1,5–4,5 h). Das ist nicht neu. Die neue Variante hat bewusst keine FAILs auf Pacing-Zielen, nur harte Aussagen (kein Rebirth vor Final 100; Speedrun nicht >4x schneller).

## Profile bis Final 100

| Profil | Look 4 | Look 5 | Look 6 | Final 100 |
|---|---|---|---|---|
| Gelegenheit 30 min/Tag | 1,9 h (Tag 4) | 25,4 h (Wo 8) | 45,2 h (Wo 13) | 43,3 h = Tag 87 (Wo 13) |
| Normal 90 min/Tag | 1,9 h (Tag 2) | 25,4 h (Wo 3) | 45,2 h (Wo 5) | 43,3 h = Tag 29 (Wo 5) |
| Viel 240 min/Tag | 1,9 h (Tag 1) | 25,4 h (Wo 1) | 45,3 h (Wo 2) | 43,3 h = Tag 11 (Wo 2) |

## Fortschritts-Takt (Ziel: sichtbarer Fortschritt höchstens alle 10 aktive Minuten)

Gemessen werden Gebäude-Ausbau, Bärchi-Level und neue Tower-Rekorde (ohne Eier, Quests, Charms, Events).

| Profil | Ereignisse bis Final 100 | größte Lücke | P95-Lücke | Lücken > 10 min |
|---|---|---|---|---|
| Gelegenheit | 149 | 68 min | 62 min | 48 |
| Normal | 152 | 68 min | 62 min | 48 |
| Viel | 159 | 68 min | 62 min | 49 |

Ergebnis: Mit diesen drei Quellen allein ist der 10-Minuten-Takt **nicht** erreicht (ab ca. Minute 200 liegen 12–68 min zwischen Ereignissen, weil Gebäude teuer werden und Tower-Rekorde am zeitgebundenen Ausbau-Bonus hängen). Der Takt wird in der Praxis von Eiern (ca. 1 Ei/min, `drop_rates_v2.lua`), Haustier-Level, Charms, Events und Quests getragen; die sind im Sim nicht als Ereignis modelliert. Offene Empfehlung: Ereignisquellen im Sim ergänzen oder die Lücken im Spiel mit einem „nächstes Ziel“-Hinweis überbrücken (Paket 7, NextActionRules).

## Anti-Speedrun (Viel, Einkommen ×1 / ×1,5 / ×2 / ×3)

| Einkommen | Look 4 | Look 5 | Look 6 | Final 100 |
|---|---|---|---|---|
| ×1 | 1,9 h | 25,4 h | 45,3 h | 43,3 h |
| ×1,5 | 1,6 h | 18,2 h | 44,6 h | 43,3 h |
| ×2 | 1,4 h | 14,8 h | 44,3 h | 43,3 h |
| ×3 | 1,2 h | 10,2 h | 44,0 h | 43,3 h |

Final 100 ist unabhängig vom Einkommen, weil der Ausbau-Bonus im Modell eine reine Funktion der aktiven Stunden ist (Annahme aus `progression_pacing.lua`). Das ist eine Modellannahme, kein Messergebnis des echten Spiels: Ob Eier und Fusion einen Speedrunner schneller machen, zeigt erst ein Test mit echter Power-Verteilung.

## Gegenmessen (keine FAILs)

| Messung | Ergebnis |
|---|---|
| `tower_calibration.lua` (Flag aus) | ALLE ZIELE OK |
| `boss_balance.lua` | OK (Dauer 120–180 s) |
| `pit_balance.lua` | läuft; Tabelle plausibel (Tower I, Level 50 → 30/30) |
| `combat_rating.test.lua` | grün (ρ ≥ 0,85) |
| `egg_press.test.lua` | grün, gesperrte Pfade nicht pressbar |
| `power_rules.test.lua`, `drop_rates.test.lua`, `ascension_v2.test.lua`, `rebirth_world2.test.lua` | grün |
