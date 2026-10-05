# HBB Paket 6 umgesetzt (Teil) – 05.10.2026

## Neu
- **Event-Timer am Event-Knopf** (`EVENT_V2_TIMER`): Icon des kommenden bzw. laufenden Events + Restzeit "2:13", keine Wörter. Wespenkönigin mit eigenem Zeichen 🐝. `EventPhaseChanged` enthielt Restzeit und nächstes Event bereits – Nutzlast unverändert.
- **Erste Pause kürzer:** `EventConfig.FIRST_GAP_SECONDS = 75` für den ersten Zyklus eines frisch gestarteten Servers. Alle anderen Pausen und `everyNthCycle` unverändert.

## Wespenkönigin – nur berichtet, nicht geändert
Zyklus: je Event 300 s Pause davor; UFO 240 s, vier Events à 180 s, Boss 240 s nur in jedem 2. Durchlauf → Periode 91 min (41 + 50).

| Fall | Ergebnis |
| --- | --- |
| Frischer Server, erste Pause 300 s | erster Boss nach 87,0 min |
| Frischer Server, erste Pause 75 s | erster Boss nach 83,2 min |
| Join zu zufälliger Zeit (laufender Server) | frühestens sofort (Boss läuft, 4/91), im Mittel **41,6 min**, Median 41,5 min, höchstens 87 min |

Der Mensch entscheidet, ob die Boss-Häufigkeit geändert wird.

## Nicht umgesetzt
- Live-Kampf-Board (neue Tafel, Teile-Budget, `SurfaceGui`) und Wespen-Nest: brauchen Map-Werkzeuge und Studio.

## Studio-Testschritte
1. Neuer Server: Event-Knopf zeigt UFO-Icon und ~1:15.
2. `skipevent`/`startevent WaspQueen`: Icon wechselt, Zeit stimmt.
3. `EVENT_V2_TIMER = false` → alter Text, erste Pause 300 s.
