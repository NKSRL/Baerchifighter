# HBB Paket 5/6 – Map-Teile umgesetzt – 05.10.2026

Alle Positionen kommen aus `Modules/MapLayout.luau` (reine Rechnung). Builder, Deko-Freiraum (`ScenicBuilder`) und der Test benutzen dieselbe Formel.

| Teil | Schalter | Was |
| --- | --- | --- |
| 3 feste Bestenlisten-Tafeln | `MAP_V2_BOARDS` | Tower 22,5°, Rebirths 157,5°, Index 292,5° (je r 80, Lücke zwischen zwei Stegen). Jede Liste immer sichtbar statt einer Tafel, die alle 15 s wechselt. |
| Schau-Turm am Brückenkopf | `MAP_V2_SHOWCASE` | Der Turm jedes Spielers steht an seinem Steg auf der Hauptinsel (106 entlang, 18 seitlich), wo alle vorbeilaufen, statt draußen auf der Arena-Insel. |
| Kürzerer Weg zur Arena | `MAP_V2_ARENA_SPRINT` | Bärchi sprintet Plot ↔ Arena mit 21 statt 13 Studs/s (~37 % weniger Laufzeit je Lauf); gleiche Hopser pro Sekunde, nur weiter. **Abweichung:** Stege nicht verkürzt, das hätte alle Inselringe verschoben und nur ~18 % gebracht. |
| Live-Kampf-Board | `MAP_V2_LIVE_BOARD` | Tafel bei 202,5°: „⚔ LIVE · n“, darunter wer in welchem Tower/Stage kämpft (sprachneutral). `LiveBoardService`, Text aus `Modules/LiveBoardText`. Schreibt nur bei Änderung. |
| Wespen-Nest | `MAP_V2_WASP_NEST` | Nest am Honigmast (unter dem oberen Querholz): „🐝 41:30“ bis zur nächsten Wespenkönigin, leuchtet in den letzten 5 min und während des Bosses. Zeit aus `EventConfig.secondsUntilStart` (rein). |

Nebenbei behoben: Bäume und Büsche hielten keinen Abstand zur Tafel und zum neuen Händlerplatz. Jetzt reserviert `ScenicBuilder` alle Wahrzeichen (Folge: Die Zufallsdeko steht an etwas anderen Stellen).

## Tests (alle grün)
- `map_layout.test.lua`: alle Wahrzeichen auf der Insel, außerhalb des Event-Pits, frei von Stegen, Laternen und einander; das Nest hängt frei am Mast. Gegenprobe: ein Turm mit 8 statt 18 seitlich wird rot.
- `event_schedule.test.lua`: Erster Boss nach 87,0 / 83,2 min (wie im Paket-6-Bericht), Periode 91 min.
- `live_board.test.lua`: Reihenfolge, Rückweg ausgeblendet, Zeilenlimit.
- `run_local.py` kann jetzt mit `Vector3` rechnen.

## Studio-Testschritte
1. Play: drei Tafeln, Live-Board, acht Türme-Plätze (nur belegte Plots haben einen Turm), Nest am Mast mit Uhr.
2. `parts` (Debug): Insel-Budget ≤ 250; der Turm zählt weiter zur eigenen Insel.
3. Kampf starten: Bärchi sprintet hin und zurück, Live-Board zeigt „⚔ Name III · 4“.
4. `startevent WaspQueen`: Nest leuchtet, Schild „🐝 LIVE“.
5. Je Schalter `false` → altes Verhalten.
