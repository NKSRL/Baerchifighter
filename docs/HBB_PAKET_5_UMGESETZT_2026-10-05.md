# HBB Paket 5 umgesetzt (Teil) – 05.10.2026

## Neu
- **Ei-Händler sichtbar** (`MAP_V2_MERCHANT`): neuer Platz `EggConfig.MERCHANT_V2` (67,5°, Radius 66) auf dem Weg zum Event-Pit, ~16 Studs vor dem Pit-Zaun, ~59 Studs von der Bestenlisten-Tafel, mittig zwischen zwei Stegen. Ei-Schild als Billboard-Bild (keine Teile).
- **Heim-Knopf** (`MAP_V2_HOME`): `HomeService` + `RequestGoHome` (Cooldown 3 s). Teleport zur eigenen Plot-SpawnLocation; mit getragenen Waben Ablehnung über `ActionFailed` (`err.home_carrying`). Client-Knopf 🏠 unten links, nur > 60 Studs vom eigenen Spawn.
- **Führung zum Händler**: `GuideSteps` zeigt `merchant` (Beam zur Theke), wenn weder Lager noch Plot ein Ei haben und die Gummies reichen.

## Schon vorhanden (nicht doppelt gebaut)
- Start auf dem eigenen Plot: `PlotBuilder` legt je Plot eine SpawnLocation an und setzt `Player.RespawnLocation`, `PlayerService` lädt den Charakter erst danach (`CharacterAutoLoads = false`). Im Playtest bestätigt: Spawn direkt am eigenen Bienenstock.

## Nicht umgesetzt (braucht Studio + `render_map.py`/`check_decor.py`)
- Schau-Turm an den Brückenkopf, drei feste Bestenlisten-Tafeln, kürzerer Weg zur Arena. Diese Punkte ändern Geometrie und Teile-Budget und sind ohne die Map-Werkzeuge und Studio-Messung (`parts`) nicht sicher prüfbar.

## Prüfergebnisse
| Werkzeug | Ergebnis |
| --- | --- |
| luau-compile | grün |
| guide_steps.test.lua (inkl. Händler-Fälle) | grün |
| check_decor.py, render_map.py | nicht vorhanden (Heim-PC) |

## Studio-Testschritte
1. Händler vom Weg zum Pit sichtbar, Ei-Schild von weitem erkennbar, kaufen funktioniert.
2. Zum Event-Pit laufen → 🏠 erscheint; antippen → zurück auf dem Plot. Mit Waben in der Hand → Meldung, kein Teleport.
3. `state fresh`, alle Eier öffnen, Eier-Lager leer, ≥ 50 Gummies → Beam zum Händler.
4. Zwei Spieler: jeder startet auf seinem Plot.
5. Alle Flags `false` → alte Map.
