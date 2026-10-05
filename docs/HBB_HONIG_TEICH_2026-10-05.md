# Honig-Teich statt Bienenstock + Veredler – 05.10.2026

Entscheidung des Projektinhabers: Stock und Veredler entfallen. Der Honig-Teich, aus dem der Bärchi frisst, wird selbst ausgebaut und wächst bis zum Honig-Springbrunnen. Der Bärchi läuft nicht mehr hin und her.

Schalter: `FeatureFlags.HONEY_POND_V2 = true`. Auf `false` ist alles wie vorher, inklusive der alten Gebäudestände.

## Was sich ändert
| Bereich | Umsetzung |
| --- | --- |
| Daten | neues Gebäude `HoneyPond`. Bienenstock und Veredler wandern nach `island.retiredBuildings` (nichts gelöscht). Regel in `Modules/HoneyPondMode` (rein, umkehrbar, idempotent), aufgerufen von `Types.createDefaultPlayerData` (neue Spieler, Rebirth) und `PlayerMigration.applyDefaults` (jeder Join, **vor** dem Aufräumen unbekannter IDs). |
| Umstieg | Teich-Level = höheres der beiden alten Level, Honig beider zusammengelegt (auf das Lager gedeckelt). Niemand verliert etwas. |
| Leistung | Teich auf Level L = Stock **und** Veredler auf Level L: gleiche Honig/min, beide Lager, XP und Heilung wie der Veredler, Auto-Ernte ab L10 (`BuildingBehavior`, Test `honey_pond.test.lua`). |
| Kosten | `HONEY_UPGRADE_COSTS` × 1,2 bis Level 10, × 2,2 ab Level 11 (`BuildingBehavior.pondCostFactor`). |
| Ort | Mitte des hinteren Plot-Teils (plot-lokal 0/−14), wo die beiden Gebäude standen; der Brunnen ist vom Steg aus sichtbar. |
| Bärchi | wohnt auf den Bohlen vor dem Becken (`MapLayout.baerchiHomeOffset`), frisst ohne zu laufen; zum Kampf startet er von dort. Gelegte Eier, die im Becken landen würden, werden auf die andere Seite gespiegelt. |
| Looks | `BUILDING_LOOK_DECOR.HoneyPond` (Tabelle unten), alle Looks bestehen `check_decor.py`, höchstens 32 Teile. Der Honiglöffel (`POND_DECOR`) entfällt im neuen Modus. |
| UI | Gebäude-Panel, Welt-Prompt, Farben, Texte (Honig-Brunnen/Honey Fountain/Fontaine de miel/Fuente de miel). Fütter-Knöpfe auf der Bärchi-Karte zeigen nur vorhandene Gebäude. |

## Look-Reihe (Level → Bild)
| Look | Level | Zusatz |
| --- | --- | --- |
| 1 | 1–9 | Teich mit Holzpfahl und Wabe |
| 2 | 10–19 | Holzrinne mit Honigstrahl, Honigtopf |
| 3 | 20–29 | Steinsäule mit Brunnenschale voll Honig |
| 4 | 30–44 | zweite Schale, Goldring, zwei Honig-Kaskaden |
| 5 | 45–59 | goldene Bienen-Statuen, Honig-Fontäne |
| 6 | 60 | riesiger Neon-Honigtropfen mit Goldkrone, vier Honigfälle, Kristalle |
Platzhalter aus Grundformen wie bei Türmen und Gebäuden; echte Modelle können die Tabelle 1:1 ersetzen.

### Effekte (Partikel, `MapConfig.BUILDING_LOOK_FX` / `FX_PRESETS`, gebaut von `PlotBuilder.addLookEffects`)
| Look | Effekt |
| --- | --- |
| 2 | Honigtropfen am Strahl |
| 3 | Funkeln auf der Honigschale |
| 4 | Tropfen an beiden Kaskaden |
| 5 | Fontäne spritzt Honig hoch, der in die Schale zurückfällt; Funkeln an den Bienen |
| 6 | goldene Funkel-Aura um den Riesentropfen, Glitzer an der Krone, Tropfen an allen vier Fällen |
Nur eingebaute Roblox-Texturen, keine Lichter. Der Test prüft, dass jedes Ziel-Teil ab seinem Look existiert. In Studio prüfen: Stärke (`rate`) nach Gefühl nachstellen, nur in `FX_PRESETS`.

## Pacing (`progression_pacing.lua`, alle Ziele grün)
Die Looks zählen jetzt am Honig-Gebäude (vorher am ersten Gebäude, oft dem Recycler).
| Normal (90 min/Tag) | vorher | jetzt |
| --- | --- | --- |
| Look 2 | 28 min | **24 min** (auch bei 30 min/Tag an Tag 1) |
| Look 3 | 3,9 h | 2,6 h |
| Look 4 | 6,3 h | 8,2 h |
| Look 5 | 18,0 h | 16,4 h |
| Look 6 | 68,6 h | 75,5 h |
| Rebirth 1 | 3,6 h | 1,9 h (Gelegenheit: **Tag 4 statt Tag 8**) |
| Rebirth 10 / Final 100 | 76,1 / 156,9 h | 73,7 / 156,9 h |

## Prüfungen
`honey_pond.test.lua` (Umstieg, Rückweg, Idempotenz, Ruhestand gewinnt, neuer Spieler, Leistung je Level), `check_decor.py` (alle Looks), alle Sims und Tests grün. `check_members.py` erkennt jetzt auch generische Funktionen (`function M.f<T>()`).

## Offen / Heim-PC
- `migration.test.lua`: Fälle für `retiredBuildings` und den Umstieg ergänzen (Spielstände v14/v15 → Teich).
- `render_map.py` zeigt den Teich noch an der alten Stelle (liest `POND_OFFSET` statisch).

## Studio-Testschritte
1. Neues Konto: nur der Brunnen-Teich auf dem Plot, Bärchi steht auf den Bohlen davor und frisst, ohne zu laufen.
2. Alter Spielstand mit Stock L20 / Veredler L17: Teich auf L20, Honig übernommen.
3. `D:Invoke("building", "HoneyPond", 10/20/30/45/60)`: Brunnen wächst Look für Look.
4. Teich ausbauen: Kosten L2 = 300 Gummies.
5. `HONEY_POND_V2 = false`: Stock und Veredler mit altem Stand zurück.
