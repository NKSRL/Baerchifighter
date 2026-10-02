# Teil B (Animationsqualität) — abgeschlossen

Stand: 07.09.2026. Auftrag aus `claude/OPUS_PROMPT_QUALITAET_GEBAEUDE_2026-09-07.md`,
**Teil B**. Setzt auf dem Stand nach Teil A + C auf. Teil D (Gebäude-Redesign) ist
weiterhin nicht angefasst.

Kein Motor6D, kein Animator, kein AnimationController — alles bewegt weiterhin das
ganze Model per `PivotTo`, genau wie `FigureWalker`. Die Gesamtdauer einer
PIT-Wiedergabe bleibt exakt gleich; die neuen Bewegungen füllen vorhandene Pausen aus,
statt sie zu verlängern.

## Neue Datei

| Datei | Zweck |
|---|---|
| `src/server/Util/FigureFX.luau` | Die Animations-Bausteine: `attackLunge`, `hitFlash`, `defeatCollapse`, `leanForward`, `idleBob` / `stopIdle`. Kennt weder Spielerdaten noch Remotes noch Config — nur `Model`, `CFrame` und Zahlen. |

Liegt in `server/Util/` statt `shared/Modules/`, weil alle Aufrufer Server-Services sind
und es damit neben `FigureWalker` und `FigurePlacement` steht — denselben zwei Modulen,
mit denen es sich die Fußpunkt-Technik teilt.

## Geänderte Dateien

- `PitArenaService.luau` — pro Stage Ausfallschritt beim Gewinner + Treffer-Blitz beim
  Verlierer, Umkippen des Verlierers der letzten Stage, An-/Abmelden des Ruhe-Atmens an
  allen vier Stellen, an denen der Service selbst `PivotTo` aufruft. **Zusätzlich ein
  Fehler behoben, siehe unten.**
- `MapService.luau` — meldet jede frisch gebaute Plot-Figur zum Ruhe-Atmen an.
- `BaerchiAutopilotService.luau` — Vorbeuge-Bewegung statt reiner Warte-Pause am Teich;
  Ab-/Anmelden um den Lauf herum.
- `MapConfig.luau` — acht neue Konstanten (siehe unten).

## Neue Konstanten in MapConfig

| Konstante | Wert | Wofür |
|---|---|---|
| `IDLE_BOB_HEIGHT` | 0.16 | Hub des Ruhe-Atmens in Studs |
| `IDLE_BOB_RATE` | 1.5 | Schwingungen pro Sekunde |
| `FIGHT_LUNGE_DISTANCE` | 1.7 | Studs, die der Angreifer vorsetzt |
| `FIGHT_LUNGE_SECONDS` | 0.22 | Dauer des Ausfallschritts |
| `FIGHT_HIT_FLASH_SECONDS` | 0.22 | Dauer des Treffer-Blitzes |
| `FIGHT_HIT_FLASH_COLOR` | warmes Weiß | Farbe des Treffer-Blitzes |
| `FIGHT_COLLAPSE_SECONDS` | 0.45 | Dauer des Umkippens |
| `EAT_LEAN_DEGREES` | 26 | Wie weit sich der Bärchi zum Fressen vorbeugt |

## Getroffene Default-Entscheidungen

1. **Treffer-Blitz als `Highlight`, nicht als Farbpuls auf den BaseParts.** Das Dokument
   stellt beides frei. Farbe und Transparenz der Parts sind hier bereits doppelt belegt:
   `BaerchiMesh` färbt nach Rarity ein, `MapService` schreibt die
   Erschöpfungs-Transparenz und merkt sich die Ausgangswerte als Attribut
   (`BaseTransparency`). Ein Farbpuls müsste diese Werte sichern und wiederherstellen —
   und zwei Treffer kurz hintereinander würden den falschen Wert zurückschreiben. Das
   Highlight legt sich darüber und fasst nichts davon an. `DepthMode = Occluded`, sonst
   leuchtete der Treffer quer über die Plattform durch die Landschaft.

2. **Auch der eigene Bärchi atmet in der Arena**, nicht nur die Gegner. Die
   Nachlauf-Pause (`FIGHT_LINGER_SECONDS`, 1,6 s) ist der längste Moment eines Laufs, in
   dem er reglos dasteht — genau der, der vorher tot wirkte. Das hat eine Konsequenz, die
   leicht zu übersehen ist: `restoreHome` muss das Atmen **vor** `PivotTo(home.pivot)`
   abmelden. Die gemerkte Ruhelage ist während des Kampfs der Kampf-Spot, ein späteres
   Abmelden hätte die Figur genau dorthin zurückgesetzt und die Heimkehr wieder
   zunichtegemacht. Der Zusatz-Check prüft diese Reihenfolge mechanisch mit.

3. **Ein Loop, keine N.** `FigureFX` hält genau eine `RunService.Heartbeat`-Verbindung
   und eine `{[Model]: Eintrag}`-Registry. Die Verbindung entsteht erst mit der ersten
   Figur und löst sich wieder, sobald keine mehr registriert ist — ein leerer Server
   lässt gar nichts mitlaufen. Zerstörte Figuren räumt der Loop selbst aus der Registry,
   kein Aufrufer muss daran denken.

4. **Die Wiedergabe wird nicht länger.** Der Ausfallschritt blockiert, seine Dauer geht
   deshalb von der Stage-Pause ab; das Umkippen läuft innerhalb der Nachlauf-Pause.
   Zusätzlich ist der Ausfallschritt auf die halbe Stage-Zeit geklemmt: bei vielen Stages
   dauert eine Stage nur `FIGHT_MIN_STAGE_SECONDS` (0,16 s), und zwei überlappende
   Ausfallschritte auf derselben Figur würden sich gegenseitig überschreiben. Nachgerechnet
   für 1, 5 und 40 Stages — die Zeit pro Stage bleibt auf die Nachkommastelle gleich.

5. **Der eigene Bärchi kippt nur um, wenn er den Lauf wirklich erschöpft beendet**
   (`hpAfter <= 0`). Sonst läuft er direkt danach selbst nach Hause — eine umgekippte
   Figur, die losmarschiert, wäre schlechter als gar keine Animation.

6. **Form gegen Menge.** Dauer, Distanz und Farbe kommen als Argument aus `MapConfig` —
   das sind Balance-/Optik-Werte des Spiels. Was in `FigureFX` als Konstante steht, ist
   die *Form* der Bewegung: Hüpfhöhe als Anteil der Ausfall-Distanz (0.35), Kippwinkel
   (74°) und Absacken als Anteil der Figurenhöhe (0.18), Halte-Anteil beim Fressen (0.40),
   Deckkraft des Blitzes (0.45). Dieselbe Aufteilung, die `FigureWalker` schon vormacht
   (Hüpfhöhe/Vorlehnung als eigene Vorgaben). **Wenn dir das Umkippen zu heftig oder das
   Vorbeugen zu tief vorkommt: Winkel und Anteile stehen oben in `FigureFX.luau`,
   `EAT_LEAN_DEGREES` in `MapConfig`.**

7. **Punkt 5 des Auftrags (Lauf-Bob an die Geschwindigkeit koppeln) bewusst nicht
   umgesetzt.** Er ist als optional markiert, und beim Nachsehen ist er größtenteils schon
   erfüllt: `bobRate` in `FigureWalker` ist "Hüpfer pro zurückgelegtem Stud", die
   *Frequenz* skaliert also bereits mit dem Tempo. Fix ist nur die Amplitude — und es gibt
   im ganzen Projekt genau eine Geschwindigkeit (`MapConfig.WALK_SPEED`, für Teich- und
   Arena-Weg dieselbe). Eine Kopplung wäre heute toter Code mit Faktor 1,0. Sobald es eine
   zweite Geschwindigkeit gibt, ist das eine Zeile in `FigureWalker.walk`.

## Nebenbei behoben (nicht Teil des Auftrags)

**`PitArenaService.startPlayback` hat das Bewegungs-Schloss auf zwei Abbruchpfaden nie
freigegeben.** `ActivityLock.forceAcquire` läuft immer, die beiden stillen Abbrüche
darunter (kein Plot / keine gerenderte Figur, oder ein Lauf ohne Stages) kamen aber ohne
`release()` zurück. Nur der Fehler-Pfad in `PitArenaService.play` hat freigegeben.

Wer also einmal ohne Plot oder ohne Mesh-Template in einen Lauf ging, behielt `"Kampf"`
als Schloss-Besitzer für den Rest der Sitzung. Vorher fiel das kaum auf — der Autopilot
ging nur nie wieder essen. Seit dem `ActivityLock`-Schutz aus Teil A hätte derselbe Zustand
zusätzlich **Ausrüsten und Verwerten dauerhaft abgelehnt und den Figuren-Neuaufbau für
immer verschoben**. Weil Teil A die Folgen dieses Fehlers so deutlich verschärft, ist er
hier gleich mit erledigt statt nur notiert: beide Pfade laufen jetzt über ein gemeinsames
`abortPlayback()`, das Ergebnis verschickt **und** das Schloss freigibt.

## Verifikation (alles grün)

| Prüfung | Ergebnis |
|---|---|
| `luau-compile --null` über alle 50 `.luau` | fehlerfrei |
| `tools/check_members.py` / `check_consistency.py` / `check_decor.py` | alle sauber |
| Genau **eine** `RunService`-Connection serverweit | ✔ `server/Util/FigureFX.luau` |
| Kein Service baut sich eine eigene Figuren-Schleife | ✔ |
| Kein `Motor6D` / `Animator` / `AnimationController` / `Instance.new("Animation")` | ✔ nirgends |
| `FigureFX` requiret nur `FigurePlacement` | ✔ kein Types/Remotes/Config/Service |
| `FigureFX` erwähnt weder `PlayerData`, `Remotes`, `island` noch eine Config | ✔ |
| `stopIdle` steht in `restoreHome` direkt vor `PivotTo(home.pivot)` | ✔ mechanisch geprüft |
| Alle acht neuen Konstanten deklariert, exportiert **und** benutzt | ✔ |
| Bewegungs-Mathematik (401 Stützstellen je Kurve) | Ruhe-Atmen bleibt in 0..1 (taucht nie in den Boden), Ausfallschritt endet exakt am Ausgangspunkt, Vorbeugen ist an beiden Phasenübergängen stetig, Umkippen läuft von 0 auf 1 |
| Stage-Dauer bei 1 / 5 / 40 Stages | unverändert |
| `luau-analyze` vorher/nachher | keine neue Meldungsart |

Zu `luau-analyze` wie beim letzten Mal: ohne Roblox-API-Definitionen meldet es schon im
unveränderten Projekt hunderte `Unknown type 'Model'` / `Unknown global 'CFrame'`. Der
Vergleich der Meldungs**arten** vorher/nachher ist deshalb das aussagekräftige Kriterium —
und der ist leer.

## Was im Studio zu testen ist

1. **Einfach hinschauen.** Der ausgerüstete Bärchi auf dem Plot atmet jetzt leicht auf und
   ab. Bewusst dezent — wenn es dir zu wenig auffällt, `IDLE_BOB_HEIGHT` hochdrehen.
2. **Acht Plots gleichzeitig** (Studio: mehrere Spieler starten): die Figuren dürfen
   **nicht** im Gleichschritt wippen — jede bekommt beim Anmelden eine eigene Phase.
3. **PIT-Lauf.** Pro Stage macht der Gewinner einen Ausfallschritt, der Verlierer leuchtet
   kurz auf. Der letzte Verlierer kippt nach hinten weg, bevor aufgeräumt wird. Der Lauf
   darf sich **nicht länger anfühlen** als vorher.
4. **Lauf mit sehr vielen Stages** (hohes PIT-Level): die Ausfallschritte dürfen nicht
   ineinanderlaufen oder die Figur verschieben — sie muss nach jeder Stage exakt auf ihrem
   Kampf-Spot stehen.
5. **Nach dem Kampf**: der Bärchi muss exakt auf seinem alten Platz landen, nicht ein
   Stückchen höher. Das ist der Fall, den die Abmelde-Reihenfolge absichert — mehrere
   Kämpfe hintereinander laufen lassen, ein Versatz würde sich sonst aufaddieren.
6. **Fressen am Teich**: er beugt sich hinunter, bleibt kurz unten, richtet sich auf. Wenn
   die Nase im Boden verschwindet, `EAT_LEAN_DEGREES` kleiner stellen.
7. **Kampf starten, während er zum Teich läuft**: die Vorbeuge-Bewegung muss sauber
   abbrechen und der Bärchi aufgerichtet in die Arena laufen — nicht schräg.

## Offen für später

- **Teil D** (die drei Gebäude) steht als einziger Teil des Dokuments noch aus.
- **Rebirth mitten in einem PIT-Lauf** reißt weiterhin den ganzen Plot weg
  (`MapService.rebuildIsland` hat keine `ActivityLock`-Abfrage). Unverändert offen aus
  Teil A — kein Absturz, aber ein sichtbarer Sprung.
- **Teil A Punkt 5** (Signatur-Neuberechnung in `PlotDisplayService`) weiterhin offen.
- Eigene Bewegungen pro Rarity oder pro Skill wären der nächste sinnvolle Schritt auf
  `FigureFX` — die Bausteine nehmen dafür bereits alle Werte als Argument entgegen.
