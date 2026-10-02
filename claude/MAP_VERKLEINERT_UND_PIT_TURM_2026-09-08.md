# Map verkleinert, PIT-Turm hinzugefügt

Stand: 2026-09-08

---

## Was du gesagt hast

> „Ich finde nur, dass die Map Skalierung ein wenig groß geraten ist. Der
> Spieler braucht sehr lange um von einer Insel zur Mitte zu kommen. Bitte
> füge außerdem hinzu, dass man pro Stage im Pit eine Etage aufrückt. Der
> Boden soll quasi um eine Stufe angehoben werden und bei vielen Stufen soll
> das dann einen Turm bilden."

Dazu kam ein Screenshot: ein hoher Zylinder aus vielen dünnen, bunten
Streifen, der aus einem gelb-orangenen Untergrund aufragt.

---

## Teil 1: Die Welt ist kleiner

Angefasst wurden nur die Zahlen, die den WEG bestimmen — nicht die Größe der
Plots, Gebäude, Beete oder der Arena selbst. Die haben ihre eigene, feste
Geometrie (Beet 72×72, PIT-Radius 26 usw.), an der nichts hing, was mit
„zu weit laufen" zu tun hat.

| | vorher | jetzt |
|---|---|---|
| Hauptinsel-Radius | 150 | **120** |
| Steglänge (jede der 16 Brücken) | 44 | **34** |
| Plot-Ring (Insel-Mitte ab Weltmitte) | 252 | **212** |
| Arena-Mitte ab Weltmitte | 384 | **334** |
| Wasser-Radius | 700 | **650** |
| Wasser zwischen zwei Plot-Inseln | 61 Studs | 30 Studs |
| Weg Bärchi-Platz → Arena | ~126 Studs | ~116 Studs |

`PLOT_ISLAND_RADIUS` (58) blieb bewusst unverändert — der hängt fest an der
Beetgröße (72×72, halbe Diagonale 50.9 Studs), und daran zu drehen hätte das
Beet über den Inselrand ragen lassen statt nur den Weg dorthin zu kürzen.

Die vier Geometrie-Prüfungen, die `MapService.init` beim Serverstart laufen
lässt (passt das Beet auf die Insel, stimmt der Plot-Ring mit der Lücke
überein, berühren sich Nachbarinseln, reicht das Wasser hinter die Arenen),
sind mit den neuen Zahlen alle grün — nachgerechnet mit `tools/render_map.py`,
das dieselben vier Prüfungen unabhängig vom Spiel repliziert und als Tabelle
ausgibt.

---

## Teil 2: Der PIT-Turm

Neu in `MapConfig` (Abschnitt „PIT-TURM"), `MapService` und
`PitArenaService`.

**Wie es funktioniert:** Stage 1 eines Laufs kämpft weiterhin auf der
normalen, goldenen Kampffläche — unverändert gegenüber vorher. Ab Stage 2
bekommt jede weitere Stage eine eigene Etage: eine farbige Scheibe im
gleichen Radius wie die Kampffläche, die direkt unter den Kämpfern nachwächst
und die Kampfhöhe um `PIT_TOWER_STEP_HEIGHT` (2.4 Studs) anhebt. Bei einem
kurzen Lauf sieht man davon kaum etwas; bei einem langen — bei hohem
PIT-Level sind zwanzig und mehr Stages realistisch — türmt sich sichtbar ein
gestreifter Turm unter dem eigenen Bärchi auf, genau wie im Referenz-
Screenshot.

Die acht Farben (`PIT_TOWER_COLORS`) wechseln der Reihe nach durch — Ocker,
Braun, Salbeigrün, Hellblaugrau, Mauve, Terrakotta, Dunkelbraun, Creme —
gedeckte, erdige Töne, die auch bei vielen Etagen als Streifen lesbar
bleiben statt zu einem Farbbrei zu verschwimmen.

**Lebensdauer: nur innerhalb EINES Laufs.** Der Turm ist reine Wiedergabe wie
die Kampf-Figuren selbst — er wächst während der Stages und wird beim
nächsten Lauf (oder wenn dieser abbricht) wieder auf null zurückgebaut. Er
bleibt also NICHT zwischen zwei Läufen stehen; jeder Lauf fängt wieder ebenerdig
an. Das war die einfachste Lesart von „pro Stage im PIT rückt man eine Etage
auf" — ein dauerhaft dastehender Turm hätte eine ganz andere (und viel
größere) Änderung bedeutet: eine persistente Bestenmarke pro Spieler, die
zwischen Läufen sichtbar bliebe. Falls du das eigentlich meintest, sag
Bescheid — das Feld `highestTowerFloor` liegt in `Types.luau` bereits als
Platzhalter für genau so etwas herum (siehe `CONTEXT_BRIEFING.md`, Abschnitt
7 „Bekannt, noch nicht gebaut").

**Technisch:**

* `MapService.setPitTowerLevel(player, level)` — baut/entfernt Etagen-Ringe
  in einem neuen `Tower`-Ordner (liegt neben `Fighters` im `PitPlatform`-
  Container) bis genau `level` Stück da sind. Idempotent, mit `level = 0`
  verschwindet der Turm komplett. Schiebt außerdem die Anzeigetafel-
  Verankerung mit nach oben, damit sie über dem gewachsenen Turm hängen
  bleibt statt mittendrin zu stecken.
* `MapService.getPitTowerFloorY(level)` — reine Rechenfunktion für die
  Kampfhöhe bei `level` Etagen, dieselbe Formel wie beim Bauen einer Etage.
* `PitArenaService` ruft `setPitTowerLevel` bei jeder Stage mit
  `stage.stage - 1` auf, stellt den eigenen Bärchi (Ruhe-Atmen kurz abgemeldet
  und an der neuen Stelle neu angemeldet, dieselbe Reihenfolge wie beim
  Heimkehren) und den neuen Gegner auf die aktuelle Etagenhöhe, und läuft am
  Ende von der ZULETZT erreichten Etage zurück zum Plot — nicht von der
  ursprünglichen Bodenposition, sonst wäre der Bärchi nach einem langen Lauf
  durch die Luft zurückgesprungen.
* Aufgeräumt wird der Turm an allen drei Stellen, an denen auch die
  Kampf-Figuren aufgeräumt werden (neuer Lauf beginnt, Wiedergabe bricht ab,
  `PitArenaService.play` schlägt fehl) — dieselbe Lebensdauer, derselbe
  Cleanup-Pfad.

---

## Geprüft

Ohne Studio, aber nicht ungeprüft:

* `tools/check_members.py`, `tools/check_consistency.py`,
  `tools/check_decor.py` — alle grün, keine unbekannten Config-Felder, keine
  auseinandergelaufenen Listen, keine schwebende/versenkte Deko.
* `tools/render_map.py` neu gerendert (Grundriss, Plot, Schnitt) und als
  Bild angeschaut — Inseln sauber getrennt, keine Überlappung, Wasser/Sand/
  Wiese-Treppe im Schnitt unverändert sauber.
* Die eingebettete Zahlen-Tabelle aus `render_map.py` bestätigt alle vier
  Geometrie-Invarianten als „ja"/positiv (siehe Tabelle oben).
* Der PIT-Turm selbst läuft nur zur Laufzeit in Studio — dafür eine
  eigenständige Farbstreifen-Vorschau gebaut (nicht Teil des Repos, nur zur
  Kontrolle) und angeschaut: die acht Farben ergeben tatsächlich lesbare,
  gestreifte Etagen wie im Referenz-Screenshot.
* Kein Zugriff auf `luau-compile`/`luau-analyze` in dieser Session (kein
  Luau-Compiler in der Cowork-Umgebung) — Klammer-/Geschweifte-Klammern-
  Balance aller drei geänderten Dateien automatisiert geprüft, blieb aber
  offen für den nächsten Studio-Start.

## Was als Nächstes anstehen könnte

* **Im Studio anschauen** — vor allem den PIT-Turm bei einem langen Lauf
  (hohes PIT-Level, viele Stages), das lässt sich außerhalb von Studio nicht
  wirklich beurteilen.
* Falls der Turm doch dauerhaft (als Bestenmarke) stehen bleiben soll statt
  nur während des Laufs zu wachsen: das wäre eine Zwei-Schichten-Version
  (laufender Turm + eingefrorene Bestmarke) und eine neue Design-Entscheidung
  wert, siehe oben.
* `luau-compile`/`luau-analyze` einmal über die drei geänderten Dateien laufen
  lassen (siehe `tools/README.md`, Abschnitt 1) — reine Syntaxprüfung, die in
  dieser Session nicht verfügbar war.
