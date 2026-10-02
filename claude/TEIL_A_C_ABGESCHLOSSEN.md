# Teil A (Qualitäts-Checks) + Teil C (SOLID-Refactors) — abgeschlossen

Stand: 07.09.2026. Auftrag aus `claude/OPUS_PROMPT_QUALITAET_GEBAEUDE_2026-09-07.md`,
Teile **A und C**. Teil B (Animationen) und Teil D (Gebäude-Redesign) sind **nicht**
angefasst — Teil C liefert nur das Gerüst, auf dem D aufsetzt.

Reines Verhalten: **sichtbar unverändert**, bis auf zwei neue Ablehnungs-Meldungen
(Recycle/Equip während einer Bewegung) und die nachgezogene Beschriftung nach einer
Bewegung. Keine Balance-Zahl hat sich geändert, keine Migration nötig,
`Types.PlayerData` bleibt bei `version = 6`.

## Neue Dateien

| Datei | Zweck |
|---|---|
| `src/server/Util/FigurePlacement.luau` | Die eine kanonische Platzier-Funktion: Model drehen, dann per Bounding-Box exakt auf einen Fußpunkt stellen. Ersetzt die zwei fast identischen Kopien (`FigureWalker.placeFoot` / `PitArenaService.placeModel`). |
| `src/shared/Config/BuildingBehavior.luau` | Ein Verhaltens-Objekt pro `Types.BuildingId`. Heute nur `getIntervalSeconds(level)` — das Gerüst, in das Teil D `getCapacityBonus` / `getHealMultiplier` / `getXpMultiplier` einträgt. |

## Gelöschte Dateien

- `src/server/Services/FarmService.luau` (Stub, 798 B)
- `src/server/Services/BaerchiDisplayService.luau` (Stub, 860 B)

Projektweite Suche vorher: beide kamen **nur noch in Kommentaren** vor (GameManager,
PlotDisplayService, PlayerService), in keinem `require` und in keiner
`GameManager.REGISTRY`. Die vier Kommentare sind mitgezogen worden.

## Geänderte Dateien

**Teil A**

- `RecycleService.luau` — lehnt ab, wenn die übergebene uid die **ausgerüstete** ist
  UND `ActivityLock` gehalten wird ("Der Baerchi ist gerade unterwegs — kurz warten").
  Ein Bärchi aus dem Inventar bleibt jederzeit verwertbar.
- `IslandService.luau` — lehnt einen Equip-**Wechsel** ab, solange `ActivityLock`
  gehalten wird. Bewusst ohne uid-Vergleich: der neue Bärchi ist nie der beschäftigte,
  der **alte** ist es — er wäre die Figur, die mitten im Schritt verschwindet.
- `MapService.luau` — die Sperre sitzt **einmal zentral** in `updateBaerchis`. Ist sie
  gesetzt, wird der Neuaufbau verschoben und von `scheduleRebuildWhenFree` nachgeholt,
  sobald `ActivityLock.isFree` wieder gilt; neue `setIslandDataProvider`-Einhängung,
  `despawnIsland` räumt einen wartenden Wächter mit ab.
- `PlotDisplayService.luau` — hängt beim Start die Datenquelle für dieses Nachholen ein
  (`PlayerService.getData(player).island`).
- `MapConfig.luau` — neu: `FIGURE_REBUILD_RETRY_SECONDS = 0.25`,
  `FIGURE_REBUILD_TIMEOUT_SECONDS = 30`.
- `GameManager.server.luau`, `PlayerService.luau` — nur Kommentare (tote Service-Namen).

**Teil C**

- `FigureWalker.luau` — `placeFoot` entfernt, ruft `FigurePlacement.place` auf.
- `PitArenaService.luau` — `placeModel` entfernt, beide Aufstell-Stellen rufen
  `FigurePlacement.placeLookingAt` auf.
- `EconomyConfig.luau` — `getHoneyIntervalSeconds` und `HONEYPOT_MIN_INTERVAL_SECONDS`
  entfernt (nach `BuildingBehavior` gewandert). `HONEY_INTERVAL_SECONDS` bleibt hier.
- `HoneyService.luau` — `accrue` fragt `BuildingBehavior.getIntervalSeconds` statt
  `EconomyConfig.getHoneyIntervalSeconds`.

## Getroffene Default-Entscheidungen

1. **Equip prüft nicht die uid, Recycle schon.** Das Dokument beschreibt beide Fälle mit
   derselben Formel ("betroffene uid ist die ausgerüstete UND Schloss gehalten"). Für
   Recycle stimmt das genau; für Equip nicht: dort ist die gefährdete Figur die **alte**,
   nicht die neu gewählte. Eine wörtliche Umsetzung hätte den Fall aus dem Fließtext des
   Dokuments ("… oder einen anderen ausrüsten") gerade nicht abgedeckt. Ohne
   ausgerüsteten Bärchi ist das Schloss ohnehin frei — der erste Equip geht wie bisher
   sofort durch.

2. **Nachholen sitzt in `MapService`, nicht in `PlotDisplayService`.** `PlotDisplayService`
   darf seine Signatur weiterhin sofort als "dargestellt" merken; sonst müsste es den
   Zustand einer fremden Warteschlange mitführen. Das Nachholen liest die Daten
   **frisch** statt die alte `islandData`-Tabelle aufzuheben — nach einem Rebirth ist die
   gar nicht mehr die des Spielers (`RebirthService` setzt `data.island = freshIsland`).

3. **Datenquelle wird eingehängt statt requiret.** `MapService` darf `PlayerService`
   nicht requiren (`PlayerService` requiret bereits `MapService`) — das wäre der erste
   Ringschluss im Projekt. `PlotDisplayService.init()` reicht die Lesefunktion durch;
   damit gilt auch die Regel im Dateikopf weiter, dass `MapService` keine Spielerdaten
   außer `IslandData` kennt.

4. **Timeout 30 s statt endlos.** Deckt eine komplette PIT-Wiedergabe (Hinlauf + Stages
   + Nachlauf + Rücklauf) mit Reserve ab. Läuft er ab, bleibt die Beschriftung bis zur
   nächsten Datenänderung stehen — aber es dreht sich keine Endlosschleife. Pro Spieler
   wartet höchstens **ein** Wächter.

5. **Eigenes Util `FigurePlacement` statt `FigureWalker.placeFacing`.** Das Dokument
   stellt beides frei. Hinstellen ist keine Lauf-Animation: `PitArenaService` stellt
   Gegner auf, die nie einen Schritt machen, und müsste sonst einen "Walker" requiren.
   Nebeneffekt der Zusammenführung: `place` benutzt jetzt `facing.Rotation` (vorher
   `facing`) — für alle bestehenden Aufrufer identisch, weil deren `facing` nie eine
   Position trägt, aber robuster.

6. **`HONEY_INTERVAL_SECONDS` bleibt in `EconomyConfig`, nur die Abweichung zieht um.**
   Der Basiswert gilt für die ganze Honig-Wirtschaft (auch für den Tick-Loop in
   `HoneyService`, der gar kein einzelnes Gebäude meint). `BuildingBehavior` kennt
   `EconomyConfig`, nicht umgekehrt — deshalb ist `getHoneyIntervalSeconds` dort ganz
   verschwunden statt als Weiterleitung stehen zu bleiben.

7. **Teil C Punkt 3 (Konsistenz-Pass) ist erledigt und leer.** Projektweite Suche nach
   Verzweigungen auf `BuildingId`-/`EggType`-Strings: der einzige Treffer im ganzen
   `src/` war `if buildingId ~= "HoneyPot"` in `EconomyConfig` — und genau der ist jetzt
   weg. Es gibt keine weitere Stelle, die nach einer solchen Konstante verzweigt.

## Verifikation (alles grün)

| Prüfung | Ergebnis |
|---|---|
| `luau-compile --null` über alle 51 `.luau` | fehlerfrei |
| `tools/check_members.py` | keine unbekannten Modul-Felder |
| `tools/check_consistency.py` | alles konsistent (Gebäude-IDs in allen sieben Listen) |
| `tools/check_decor.py` | alles sauber |
| Zeilenreihenfolge (`function X.y` vor `local X = {}`) | in keiner Datei |
| Zirkuläre `require` (voller Graph, ohne Kommentare) | keine |
| Honigtopf-Intervalle Lv. 1–10 alt vs. neu | identisch (20,0 / 18,667 / … / 8,0 s) |

`luau-analyze` ist hier **nicht** aussagekräftig: ohne Roblox-API-Definitionen meldet es
schon im unveränderten Projekt hunderte `Unknown type 'Model'` / `Unknown global 'CFrame'`
/ `Unknown require: unsupported path`. Zum Gegenprüfen wurde es trotzdem einmal über den
Stand **vorher** und **nachher** laufen gelassen und die Meldungen verglichen: es kommt
**keine neue Meldungsart** dazu, alle Zuwächse sind genau diese Umgebungs-Meldungen an
den neu hinzugekommenen `CFrame`/`Vector3`/`task`/`script`-Zeilen.

## Was im Studio zu testen ist

1. **Equip während der Bärchi zum Teich läuft** → Toast "Der Baerchi ist gerade unterwegs
   — kurz warten", die Figur läuft ungestört weiter. Danach greift der Equip normal.
2. **Verwerten des ausgerüsteten Bärchis während eines PIT-Laufs** → dieselbe Ablehnung.
   **Einen anderen Bärchi aus dem Inventar** verwerten geht in derselben Sekunde durch.
3. **Level-Up während des Ess-Zyklus** (füttern lassen, bis er levelt): das Namensschild
   springt nicht mehr mitten im Lauf, sondern zieht **innerhalb einer Sekunde nach dem
   Zurückkommen** auf das neue Level nach. Das ist der eigentliche Fix aus A.2.
4. **PIT-Lauf komplett anschauen** — Hinlauf, Ausrichtung zum Gegner, Rücklauf müssen
   exakt wie vorher aussehen (Teil C ist ein reiner Refactor, kein Feature).
5. **Honig-Produktion**: Honigtopf auf Level 2+ ausbauen und prüfen, dass er weiterhin
   schneller produziert als Bienenstock/Presse.

## Ein manueller Schritt

Die beiden Stub-Dateien sind in dieser Sitzung **nicht auf der Platte gelöscht worden** —
die Sitzung hatte diesmal nur Schreib-, keinen Lösch-Zugriff auf den Ordner. Sie werden
von nichts mehr referenziert und stören einen Studio-Test nicht, sollten aber weg:

```powershell
Remove-Item "src\server\Services\FarmService.luau", "src\server\Services\BaerchiDisplayService.luau"
```

## Offen für später

- **Teil A Punkt 5** (Signatur-Neuberechnung in `PlotDisplayService` bei jeder
  Datenänderung) — bewusst nicht angefasst, ist im Dokument als "nur falls Zeit übrig"
  markiert. Das Frühausstiegs-Flag aus dem Review vom 03.09. steht weiterhin aus.
- **`MapService.rebuildIsland` hat dieselbe Lücke wie `updateBaerchis` hatte**: ein
  Rebirth mitten in einem PIT-Lauf reißt den ganzen Plot weg. Kein Absturz (die
  `stillValid`-Prüfungen fangen es ab), aber derselbe sichtbare Sprung. Nicht Teil des
  Auftrags — `RebirthService` fragt weder `ActivityLock` noch `PitArenaService.isRunning`
  ab. Kandidat für den nächsten Qualitäts-Durchgang.
- **Teil B und Teil D** stehen unverändert an. `BuildingBehavior` ist so gebaut, dass D
  nur Felder in die drei bestehenden Einträge ergänzt.
