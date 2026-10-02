# BÄRCHI FIGHTER — Qualitäts-, Animations- und Gebäude-Überarbeitung (Opus-Auftrag)

> **Wie du das benutzt:** Kopiere dieses ganze Dokument in eine neue Claude-Session mit
> Modell **Opus** und Zugriff auf den Ordner `C:\Users\youpa\Documents\Claude Downloads\RBL`.
> Das Dokument hat vier Teile (A–D), die zusammengehören, aber unterschiedlich riskant und
> unterschiedlich groß sind. Sag Opus explizit, **welchen Teil** es gerade bearbeiten soll —
> nicht alles auf einmal. Empfohlene Reihenfolge und Begründung:
>
> 1. **Teil A** (Quality Checks) — klein, risikoarm, macht drei konkrete, bereits gefundene
>    Lücken dicht, bevor mehr Code darauf aufbaut.
> 2. **Teil C** (SOLID-Refactors) — legt die Bausteine (`BuildingBehavior`-Modul,
>    gemeinsame Platzier-Hilfsfunktion), die Teil D direkt braucht. Vor Teil D machen,
>    sonst baut Teil D auf Struktur, die kurz danach wieder umgebaut wird.
> 3. **Teil D** (Gebäude-Redesign + UI) — der größte und wichtigste Teil inhaltlich.
> 4. **Teil B** (Animationsqualität) — unabhängig von den anderen drei, kann jederzeit
>    dazwischengeschoben werden, auch parallel in einer eigenen Session.
>
> **AUFTRAG FÜR DIESEN LAUF:** _[hier eintragen: "Bearbeite Teil A" / "Bearbeite Teil B" /
> "Bearbeite Teil C" / "Bearbeite Teil D"]_
>
> Nach jedem Teil: in Studio testen (`rojo build` / `rojo serve`), erst dann den nächsten
> Teil starten. Am Ende jedes Teils einen kurzen Abschlussbericht schreiben (siehe
> Format-Erwartung, Abschnitt 6) — nach dem Vorbild von `claude/SCHRITT2_ABGESCHLOSSEN.md`.

---

## 1. Projektkontext (Pflichtlektüre für Opus)

**Was für ein Spiel:** Ein Idle-/Kampf-Spiel im Stil von "Grow a Chicken Fighter", Thema
Bärchis ("Baerchis") statt Hühner. Spieler hatchen Eier zu Bärchis (Gacha), rüsten genau
EINEN davon auf ihrem Plot aus, der Bärchi läuft selbstständig zum Honig-Teich wenn er
Honig braucht (`BaerchiAutopilotService`), kämpft auf Spieler-Kommando stufenweise durch
die PIT-Arena (`PitArenaService`/`CombatService`), kommt erschöpft zurück und wird mit
Honig aus den drei Gebäuden wieder hochgefüttert (`HoneyService`) — das ist der Kern-Loop.
Bis zu 8 Spieler gleichzeitig, jeder mit eigener Insel im Ring um eine zentrale Wasserfläche.

**Tech-Stack:** Rojo (via Aftman), Luau mit `--!strict` überall, `DataStoreService` für
Persistenz, `RemoteEvent`/`RemoteFunction` für Client-Server-Kommunikation.

**Stand des Projekts:** Die ursprüngliche 3-Schritt-Roadmap (`OPUS_PROMPT_ROADMAP.md`) ist
durch — Backend-Loop, komplettes Client-UI und Equip-/Autopilot-System sind fertig und
funktionsfähig (siehe `claude/SCHRITT2_ABGESCHLOSSEN.md` und den Verlauf danach). Am
03.09.2026 gab es einen vollständigen Architektur-Review
(`claude/ARCHITEKTUR_REVIEW_2026-09-03.md`) — **lies das Dokument**, ein kritischer Fund
daraus (überlappende PIT-Läufe) ist bereits behoben, drei Should-Fix-Punkte sind bewusst
noch offen und werden in Teil A dieses Dokuments konkret adressiert.

**Architektur-Prinzipien — zwingend beibehalten, nicht neu erfinden:**
- Ein Service = eine klar benannte Zuständigkeit (Kommentarblock oben in jeder Datei).
- Alle Zahlen/Balance-Werte leben in `Config`-Modulen (`shared/Config/*.luau`), niemals
  hardcoded in einem Service.
- `Types.luau` ist die einzige Wahrheit für Datenstrukturen — neue Felder gehören dort rein,
  inklusive Migration in `PlayerService`/`createDefaultPlayerData` (aktuell `version = 6`).
- `Remotes.luau` ist die einzige Stelle für Remote-Namen — keine Magic Strings.
- Nur `PlayerService` fasst den DataStore an. Nur `EconomyService` ändert
  `gummies`/`goldGummies` (Ausnahme bewusst über `EconomyService.resetGummies`/
  `awardGummiesFlat`, nie ein direkter Feld-Schreibzugriff woanders).
- `GameManager.server.luau` bestimmt die Boot-Reihenfolge — neue Services müssen dort
  eingetragen werden, Reihenfolge-Begründung steht im Kommentar der Datei.
- `PanelManager` (Client) ist die einzige Stelle, die weiß welches Panel offen ist — Panels
  requiren sich nie gegenseitig direkt, sondern melden sich unter einem Namen an.
- `ActivityLock` (Server) ist das einzige Schloss, das entscheidet, ob die eine sichtbare
  Bärchi-Figur gerade "beschäftigt" ist (Kampf oder Weg zum Honig-Teich).
- Kommentare im Code sind durchgehend deutsch — Stil beibehalten, `--!strict` in jeder
  neuen Datei.

**Wichtiger Kontext speziell für dieses Dokument — wie die 3 Gebäude HEUTE tatsächlich
funktionieren (Stand 07.09.2026, geprüft im echten Code, nicht angenommen):**

- Es gibt `Beehive` (Bienenstock), `HoneyPot` (Honigtopf), `HoneyPress` (Honig-Presse) —
  definiert als `Types.BuildingId`.
- Alle drei zeigen in `EconomyConfig.BUILDING_UPGRADES` auf **dieselbe** Tabelle
  (`HONEY_BUILDING_UPGRADES`): identische Kosten pro Level, identischer Effekt-Text
  ("Honig gibt %d XP"). Der einzige mechanische Unterschied im ganzen Spiel ist eine
  einzelne Ausnahme in `EconomyConfig.getHoneyIntervalSeconds`: `HoneyPot` produziert mit
  steigendem Level schneller (von 20s auf bis zu 8s pro Honig), die anderen beiden bleiben
  bei fixen 20s. Das ist der einzige Code-Zweig im Projekt, der überhaupt nach `buildingId`
  unterscheidet.
- `HoneyService.pickBestBuilding` wählt beim Füttern **automatisch** das Gebäude mit dem
  aktuell wertvollsten Honig (höchste XP pro Honig) — der Spieler wählt nie selbst, welches
  Gebäude er verfüttert.
- `BuildingPanel.luau` (Client) zeigt alle drei Gebäude als **identische Karten** in einer
  Liste: Name, Level, "Honig: n/5 — je N XP", Preis, ein Knopf. Es gibt keine visuelle oder
  textliche Unterscheidung zwischen den dreien außer dem Namen.
- `WorldController.luau` öffnet für alle drei Gebäude-Parts denselben generischen
  `"Building"`-Panel-Namen — der Client weiß beim Öffnen nicht einmal, welches der drei
  Gebäude angeklickt wurde (das Panel zeigt sowieso immer alle drei).
- Einzige physische Sonderrolle: `HoneyPot` hat bereits einen echten Honig-Teich auf dem
  Plot (`MapService.getPondPosition`), zu dem der ausgerüstete Bärchi läuft, um zu essen
  (`BaerchiAutopilotService`). Das ist der einzige Punkt, an dem eines der drei Gebäude
  heute schon eine eigene, sichtbare Identität in der Welt hat.

Das ist die Grundlage für Teil D: die drei Gebäude sind aktuell **mechanisch identisch bis
auf eine Zahl**, obwohl sie unterschiedlich benannt und unterschiedlich in der Welt platziert
sind. Das ist kein Bug — die Architektur dahinter (eine gemeinsame Tabelle, ein Service) ist
sogar sauber im Sinne von "nicht unnötig duplizieren" — aber es bedeutet, dass Ausbauen aktuell
dreimal dieselbe Entscheidung ist, nur mit anderem Namen drüber.

**Animations-Kontext (Grundlage für Teil B):** Die Bärchi-Meshes sind importierte `.glb`
→ `.rbxm`-Modelle ohne Rig/Motor6D (`BaerchiMesh.luau`). Bewegung passiert nicht über
`Humanoid`/`AnimationController`, sondern über `FigureWalker.luau`: ein Heartbeat-Loop, der
das ganze Model jeden Frame per `PivotTo` neu positioniert (Huepfen + Vorlehnung in
Laufrichtung), wobei der Fußpunkt exakt auf dem Boden bleibt. Dieselbe Technik (Bounding-Box
→ Fußpunkt setzen) steckt fast identisch nochmal in `PitArenaService.placeModel` — bewusst
getrennt gehalten bisher, aber eine offensichtliche Dopplung (siehe Teil C).

Aktuell existiert **nur** Lauf-Animation (hin und zurück, zum Teich, zur Arena). Während
eines PIT-Kampfs (`PitArenaService.startPlayback`) passiert optisch: Figur läuft hin, steht
dann komplett **still**, während im Hintergrund nur die HP-Balken (Billboard-`Frame`s)
per `TweenService` schrumpfen. Es gibt keine Angriffsbewegung, keine Treffer-Reaktion, kein
Sieg-/Niederlage-Verhalten am Modell selbst, und keine Idle-Bewegung, solange eine Figur
irgendwo steht (auf dem Plot, wartend in der Arena). Das ist die Lücke, die Teil B schließt.

---

## Teil A — Allgemeine Qualitäts-Checks

**Ziel:** Drei im Review vom 03.09. bewusst zurückgestellte Lücken schließen, bevor Teil C/D
mehr Code auf denselben Stellen aufbauen. Klein und risikoarm, keine neuen Features.

**Deliverables:**

1. **`ActivityLock`-Schutz vor Recycle/Equip fehlt.** Geprüft: `RecycleService.recycle` und
   `IslandService.equipBaerchi` fragen `ActivityLock` aktuell gar nicht ab. Ein Spieler
   könnte den gerade kämpfenden oder gerade zum Teich laufenden Bärchi mitten in der
   Bewegung recyceln oder einen anderen ausrüsten — kein Crash (defensive `Parent == nil`-
   Prüfungen in `FigureWalker`/`PitArenaService` fangen das ab), aber ein sichtbarer
   Sprung/Verschwinden statt eines sauberen Abbruchs.
   Fix: in beiden Funktionen früh prüfen, ob die betroffene uid die aktuell **ausgerüstete**
   ist UND `not ActivityLock.isFree(player)` — nur dann ablehnen (mit `fail(...)`, Text z.B.
   "Der Bärchi ist gerade unterwegs — kurz warten"). Ein NICHT ausgerüsteter, im Inventar
   ruhender Bärchi darf jederzeit recycelt/ausgerüstet werden, dafür gibt es keinen Grund
   zu blockieren.

2. **`MapService.updateBaerchis` baut die Figur ohne Rücksicht auf `ActivityLock` neu.**
   Geprüft: `PlotDisplayService.refresh` ruft `MapService.updateBaerchis` bei jeder
   Struktur-Änderung (Level-Up, Equip-Wechsel) auf, unabhängig davon ob die aktuelle Figur
   gerade mitten in einer `FigureWalker`/`PitArenaService`-Bewegung steckt. Empfohlene Lösung
   (statt den Check an jeder Aufrufstelle zu wiederholen — das wäre die falsche, verteilte
   Variante): die Sperre **einmal zentral** in `MapService.updateBaerchis` selbst einbauen.
   Wichtige Falle dabei, die nicht übersehen werden darf: `PlotDisplayService` merkt sich
   direkt danach die neue Signatur als "schon dargestellt" — wird der Rebuild wegen der
   Sperre stillschweigend übersprungen, muss trotzdem irgendwann nachgezogen werden, sobald
   die Sperre wieder frei ist (z.B. über einen kurzen Retry-Loop, der `ActivityLock.isFree`
   pollt und dann mit frisch gelesenen Daten `MapService.updateBaerchis` erneut aufruft) —
   sonst bleibt die Beschriftung nach dem Kampf dauerhaft veraltet stehen. Bitte diesen Punkt
   bewusst lösen, nicht nur den Rebuild unterdrücken.

3. **Tote Stub-Dateien entfernen.** `src/server/Services/FarmService.luau` (798 Bytes) und
   `src/server/Services/BaerchiDisplayService.luau` (860 Bytes) sind stillgelegte Stubs
   (eigener Kommentar-Kopf sagt das bereits), stehen **nicht** in `GameManager.REGISTRY` und
   werden ersetzt durch `HoneyService` bzw. `PlotDisplayService`. Bevor gelöscht wird: einmal
   projektweit nach `FarmService` und `BaerchiDisplayService` suchen (auch in Kommentaren
   anderer Dateien, die evtl. noch darauf verweisen) — falls wirklich nirgendwo mehr
   referenziert, beide Dateien löschen.

4. **Bereits verifiziert, keine Aktion nötig (zur Info, damit nicht doppelt geprüft wird):**
   `Remotes.GetPlayerData` hat einen funktionierenden `OnServerInvoke`-Handler in
   `PlayerService.luau` (`RateLimiter.connectFunction(Remotes.GetPlayerData, ...)`) — der
   Reconnect-Fall aus der ursprünglichen Roadmap ist erledigt.

5. **Nice-to-have, niedrige Priorität:** `PlotDisplayService` berechnet drei Signatur-Strings
   (`structureSignature`/`stateSignature`/`buildingSignature`) bei **jeder** Datenänderung
   neu, auch wenn sich z.B. nur die Gummy-Anzahl geändert hat — die teuren
   `MapService`-Aufrufe selbst werden zwar schon korrekt übersprungen, aber das
   `table.sort`+String-Concat läuft trotzdem jedes Mal über die komplette Bärchi-/Gebäude-
   Liste. Bei 8 Spielern mit großem Inventar ist das messbar, aber aktuell nicht kritisch —
   nur angehen, falls Zeit übrig ist, kein Blocker für den Rest dieses Dokuments.

**Akzeptanzkriterien:** Recycle/Equip eines gerade animierten (ausgerüsteten, gesperrten)
Bärchis wird serverseitig abgelehnt statt die Figur mitten in der Bewegung zu ersetzen. Ein
Level-Up/Equip-Wechsel während der Bärchi kämpft oder isst, zieht die Beschriftung spätestens
nach Ende der Bewegung sichtbar nach (nicht erst beim nächsten zufälligen Datenwechsel). Die
beiden Stub-Dateien existieren nicht mehr, `rojo build` kompiliert weiterhin fehlerfrei.
`luau-analyze` (oder die projekteigenen Checks unter `tools/`, falls vorhanden) läuft über
alle geänderten Dateien ohne neue Fehler.

---

## Teil B — Animationsqualität

**Ziel:** Aus der aktuell rein funktionalen Lauf-Animation ein Set von wiederverwendbaren,
kleinen Animations-Bausteinen machen, die den PIT-Kampf, das Warten und das Fressen sichtbar
lebendiger machen — ohne ein echtes Rig zu brauchen (das bleibt technisch ausgeschlossen,
siehe Kommentar-Kopf von `FigureWalker.luau`).

**Deliverables:**

1. **Neues Modul `src/shared/Modules/FigureFX.luau`** (oder `src/server/Util/FigureFX.luau`,
   je nachdem ob rein Server-seitig gebraucht — aktuell ja): rein kosmetische, zustandslose
   Animations-Bausteine für ein `Model`, ohne jeden Zugriff auf Spieldaten — bewusst getrennt
   von `PitArenaService` (der entscheidet WANN/WELCHE Stage, nicht WIE ein Treffer aussieht).
   Mindestens:
   - `FigureFX.attackLunge(model, towardPosition, distance, duration)` — kurzer Vor-und-
     Zurück-Hop in Richtung Gegner, dieselbe Bounding-Box-Fußpunkt-Technik wie
     `FigureWalker.placeFoot`.
   - `FigureFX.hitFlash(model, color, duration)` — kurzer Farbpuls auf allen `BasePart`s
     (oder ein `Highlight`-Instance-Ansatz, falls sauberer) als Treffer-Feedback.
   - `FigureFX.defeatCollapse(model, duration)` — sinkt/kippt leicht ab statt hart zu
     `Destroy()`en, bevor die Figur entfernt wird.
   - `FigureFX.idleBob(model, options): () -> ()` — startet eine leise, langsame
     Auf-ab-Bewegung für eine STEHENDE Figur, gibt eine Stop-Funktion zurück.

2. **`PitArenaService.startPlayback` um die Stage-Schleife herum erweitern**: pro Stage,
   wenn `stage.won == true`, `FigureFX.attackLunge` auf die eigene Figur plus
   `FigureFX.hitFlash` auf den Gegner zum Zeitpunkt des HP-Balken-Tweens; bei Niederlage
   umgekehrt. Beim letzten Gegner (`showSummary`): `FigureFX.defeatCollapse` auf den
   Verlierer VOR dem `Destroy`/vor `restoreHome`. Alle neuen Zeit-Konstanten dafür gehören
   in `MapConfig` (Konvention: keine neuen Magic Numbers in den Services), z.B.
   `FIGHT_LUNGE_DISTANCE`, `FIGHT_LUNGE_SECONDS`, `FIGHT_HIT_FLASH_SECONDS`.

3. **Idle-Bewegung für ruhende Figuren.** Aktuell steht der ausgerüstete Bärchi auf dem Plot
   und jeder PIT-Gegner in der Arena komplett bewegungslos, solange kein Lauf/Kampf läuft.
   Wichtig aus Performance-/Wartbarkeitssicht: **nicht** pro Figur eine eigene
   `RunService.Heartbeat`-Connection aufmachen (das würde bei 8 Spielern × mehreren Figuren
   unnötig viele parallele Loops erzeugen) — stattdessen einen einzigen zentralen Idle-Loop
   mit einer kleinen Registry (`{[Model]: baseCFrame}`), der alle registrierten Figuren in
   EINEM Heartbeat-Callback bewegt. Guter Ort dafür: ein eigener kleiner
   `IdleFigureRegistry`-Teil in `FigureFX.luau` oder ein eigenes Util-Modul, je nachdem was
   sich beim Schreiben sauberer anfühlt — Hauptsache ein Loop, nicht N.
   Anbindung: `MapService` registriert eine Figur beim `standOn`/Platzieren, `PitArenaService`
   und `BaerchiAutopilotService` deregistrieren kurz bevor sie selbst `PivotTo` aufrufen
   (sonst überschreiben sich Idle-Loop und Lauf-Animation gegenseitig) und registrieren nach
   Ende der Bewegung wieder.

4. **Kleine Fress-Animation am Teich.** `BaerchiAutopilotService.runEatCycle` wartet aktuell
   `EAT_PAUSE_SECONDS` komplett ohne Bewegung. Eine kurze Kopfneige-/Vorbeuge-Tween
   (`FigureFX`-Baustein, z.B. `FigureFX.leanForward`) während dieser Pause macht das
   "Essen" sichtbar, statt dass der Bärchi nur stehen bleibt.

5. **Optional, niedrige Priorität:** Lauf-Bob-Intensität in `FigureWalker.walk` leicht an
   die Geschwindigkeit koppeln (schnellere Bewegung = etwas ausgeprägteres Hüpfen) — nur
   angehen, wenn Zeit übrig ist, kein Kern-Deliverable.

**Akzeptanzkriterien:** Jede neue Animationsfunktion lebt in `FigureFX.luau` (oder
gleichwertig benanntem, single-purpose Modul) und kennt weder `PlayerData` noch Remotes —
reine Funktionen auf `Model`/`CFrame`/Zahlen. `PitArenaService` orchestriert weiterhin nur
WANN etwas passiert und delegiert das WIE an `FigureFX`. Genau ein zentraler Idle-Loop läuft
serverweit (keine Heartbeat-Connection pro Figur). Kein Motor6D/Animator wird eingeführt.
Alle neuen Zeit-/Distanz-Konstanten stehen in `MapConfig`. `rojo build` fehlerfrei,
`luau-analyze` sauber.

---

## Teil C — Software-Engineering-Audit (hohe Kohäsion, niedrige Kopplung)

**Ziel:** Der bestehende Review vom 03.09. hat die Architektur insgesamt als sauber
eingestuft (kein Befund zu zirkulären Requires, zentralisierte Währungslogik, konsequentes
`--!strict`). Dieser Teil ist deshalb bewusst **kein Rewrite**, sondern gezielte
Konsolidierung an zwei konkreten Stellen, die beim aktuellen Lesen aufgefallen sind — plus
die Vorbereitung, die Teil D technisch braucht.

**Deliverables:**

1. **Dopplung `placeFoot`/`placeModel` auflösen.** `FigureWalker.placeFoot` (Datei
   `FigureWalker.luau`) und `PitArenaService.placeModel` (Datei `PitArenaService.luau`) tun
   fast dasselbe: Model drehen, dann per Bounding-Box auf einen Fußpunkt setzen. Der einzige
   Unterschied ist, WORAUF sie ausrichten (feste `facing`-CFrame vs. "schau zu einem
   `lookTarget`"). Extrahiere eine gemeinsame Hilfsfunktion — z.B.
   `FigureWalker.placeFacing(model, footPos, facingCFrame)` als die eine kanonische Variante,
   `placeModel`'s "schau zu X"-Logik wird zu einer dünnen Schicht darüber
   (`CFrame.lookAt(...)` berechnen, dann `placeFacing` aufrufen). Wo genau die kanonische
   Funktion landet (in `FigureWalker` oder einem neuen, neutralen Util wie
   `FigurePlacement.luau`) ist eine Geschmacksfrage — wichtig ist nur, dass es am Ende EINE
   Implementierung gibt, nicht zwei beinah identische.

2. **`BuildingBehavior`-Modul als Vorbereitung für Teil D.** Aktuell entscheidet
   `EconomyConfig.getHoneyIntervalSeconds` mit einem harten `if buildingId ~= "HoneyPot"`,
   ob ein Gebäude schneller produziert — das ist der einzige Ort im Projekt, der überhaupt
   pro `BuildingId` unterscheidet, und genau dieses Muster wird mit drei unterschiedlichen
   Gebäude-Mechaniken (Teil D) schnell unübersichtlich, wenn es einfach per `if`-Kette
   wächst. Bevor Teil D neue Mechaniken einführt: ein neues Modul
   `src/shared/Config/BuildingBehavior.luau` (oder `src/shared/Modules/...`, wie es besser
   passt), das pro `Types.BuildingId` ein Verhaltens-Objekt bereitstellt (Funktionen wie
   `getIntervalSeconds(level)`, später in Teil D ergänzt um z.B. `getHealBonus(level)`,
   `getXpMultiplier(level)`), statt dass `HoneyService`/`EconomyConfig` selbst nach id
   verzweigen. Neues Gebäude später hinzufügen = ein neuer Eintrag in dieser Tabelle, keine
   Änderung an bestehenden `if`-Ketten — das ist der konkrete Kohäsions-/Kopplungs-Gewinn,
   den dieses Dokument einfordert.
   **Wichtig:** dieses Deliverable nur so weit umsetzen, wie es die JETZIGE Mechanik
   (nur `HoneyPot` schneller) abbildet — die eigentlichen neuen Mechaniken pro Gebäude sind
   Teil D. Teil C liefert nur das saubere Gerüst dafür.

3. **Kurzer projektweiter Konsistenz-Pass** (falls Zeit bleibt, kein Blocker): einmal prüfen,
   ob es weitere Stellen gibt, an denen ein Service direkt nach einer `BuildingId`- oder
   `EggType`-artigen String-Konstante verzweigt statt eine Config-Tabelle zu befragen — falls
   ja, nach demselben Muster wie Punkt 2 auflösen.

**Akzeptanzkriterien:** `placeFoot`/`placeModel` teilen sich eine Implementierung, sichtbares
Verhalten in Studio unverändert (Lauf-Animation und PIT-Platzierung sehen exakt gleich aus
wie vorher — das ist ein reiner Refactor, kein Feature). `BuildingBehavior` existiert, wird
von `EconomyConfig`/`HoneyService` für die Honigtopf-Sonderregel verwendet, und das Verhalten
ist unverändert nachweisbar identisch zu vorher (gleiche Sekunden-Werte für alle Level).
Keine neuen zirkulären Requires. `luau-analyze` sauber.

---

## Teil D — Die 3 Gebäude: Redesign für echten Spielspaß + UI-Überarbeitung

**Ausgangsfrage (vom Projektinhaber selbst gestellt):** Ist es wirklich Spielspaß, wenn alle
drei Gebäude bis auf eine Zahl dasselbe tun? Die eigene Einschätzung dazu: nein — jedes
Gebäude sollte eine erkennbar eigene Rolle im Kern-Loop haben, und das sollte sich auch im UI
zeigen, nicht nur im Fließtext einer Karte.

**Default-Vorschlag (konkret, sofort umsetzbar — falls eine andere Aufteilung besser gefällt,
bitte trotzdem an DIESEM Schema weiterdenken, es ist bewusst so gewählt, dass alle drei
Gebäude im selben Ressourcen-Fluss bleiben: ein Bärchi frisst weiterhin "Honig", nur dessen
Wirkung unterscheidet sich je nach Herkunfts-Gebäude):**

| Gebäude | Heutige Rolle | Neue, eigene Rolle |
|---|---|---|
| **Beehive** (Bienenstock) | Honig-Produzent, identisch zu den anderen beiden | **Volumen**: höheres Level erhöht `HONEY_CAPACITY` NUR für dieses Gebäude (mehr Lager) und/oder die Grund-Produktionsrate — der "ich brauche viel Honig"-Baustein |
| **HoneyPot** (Honigtopf) | Produziert mit Level schneller (einzige Sonderregel) | **Heilung**: sein Honig heilt überproportional mehr HP (`HONEY_HEAL_PERCENT` wird für DIESES Gebäude mit Level skaliert, statt fix 25% für alle) — der "ich will meinen Bärchi zwischen PIT-Läufen schnell wieder kampffähig machen"-Baustein. Passt genau zu seinem bereits vorhandenen Teich-Visual. |
| **HoneyPress** (Honig-Presse) | Gibt XP wie die anderen | **Wachstum**: sein Honig gibt einen XP-**Multiplikator**, der level-abhängig auf JEDEN verfütterten Honig wirkt (nicht nur seinen eigenen) — der "ich will schneller leveln"-Baustein |

Das ergibt drei klar unterscheidbare Investitionsgründe (mehr Vorrat / schnellere Heilung /
schnelleres Leveln) statt einer dreifach wiederholten Entscheidung.

**Deliverables:**

1. **`BuildingBehavior` (aus Teil C) um die drei neuen Effekte erweitern**: je Gebäude eine
   eigene Formel für seinen jeweiligen Bonus (`getCapacityBonus`, `getHealMultiplier`,
   `getXpMultiplier` o.ä. — Benennung offen, Hauptsache pro Gebäude eindeutig zugeordnet).
   `HoneyService.accrue`/`HoneyService.feed` fragen diese Werte über `BuildingBehavior` ab,
   statt (wie heute) direkt globale `EconomyConfig`-Konstanten zu verwenden.

2. **Fütter-Logik überdenken.** Mit drei mechanisch unterschiedlichen Honig-Sorten ist
   "automatisch das mit den meisten XP verfüttern" (`pickBestBuilding`) nicht mehr
   eindeutig richtig — manchmal will der Spieler lieber Heilung als XP. Empfehlung: dem
   Spieler die Wahl zurückgeben, statt es weiter automatisch zu entscheiden — das ist auch
   genau der Punkt, an dem sich "klar viel am UI verändern" konkret zeigen sollte. Konkret:
   auf der Bärchi-Detailkarte (`BaerchiPanel.luau`) drei kleine Buttons/Icons (eines pro
   Gebäude, mit eigenem verfügbaren Honig-Bestand daneben) statt eines einzigen
   "Füttern"-Auslösers — der Spieler klickt, WELCHES Gebäude gefüttert werden soll. Serverseitig
   braucht `HoneyService.feed` dafür ein `buildingId`-Argument (aktuell nimmt es nur
   `baerchiUid`) und `Remotes.RequestFeedHoney` müsste dieses Argument mit übertragen — bitte
   `RateLimiter`/Validierung entsprechend der bestehenden Konvention (siehe wie
   `IslandService.upgradeBuilding` einen `buildingId`-String aus dem Client prüft) mitziehen.
   Falls das zu groß für diesen einen Durchlauf wird: automatische Auswahl vorerst behalten,
   aber `pickBestBuilding` auf eine Regel umstellen, die auch Heilbedarf berücksichtigt (z.B.
   "wenn HP unter 50%, HoneyPot bevorzugen, sonst höchste XP") — als expliziter
   Zwischenschritt, der schon einmal die drei Rollen sichtbar macht, ohne das ganze
   UI-Feature zu bauen. **Diese Entscheidung bitte explizit treffen und im Abschlussbericht
   benennen, nicht stillschweigend eine der beiden Varianten wählen.**

3. **`BuildingPanel.luau` von einer generischen Liste zu drei eigenen Darstellungen.** Jede
   der drei Karten soll ihren eigenen Effekt in eigenen Worten zeigen (nicht mehr denselben
   Satzbau mit nur anderer Zahl) — z.B. Beehive: "Lagerkapazität: X Honig", HoneyPot:
   "Heilt X% mehr HP pro Honig", HoneyPress: "+X% XP auf jeden Honig". Wo sinnvoll: je
   Gebäude eine eigene Akzentfarbe aus `Theme.COLORS` (falls dort noch keine drei passenden
   Farben definiert sind, dort ergänzen), damit sich die Karten auch optisch unterscheiden,
   nicht nur textlich.

4. **`WorldController.luau` anpassen**, falls Punkt 2 (manuelle Fütter-Auswahl) umgesetzt
   wird: der `"Building"`-Panel-Prompt könnte dann sinnvollerweise direkt die richtige Karte
   vorauswählen/scrollen, statt nur "irgendein Gebäude-Panel" zu öffnen — optional, kein
   Blocker.

5. **Ausdrücklich NICHT in diesem Durchlauf:** neue 3D-Modelle/visuelle Unterscheidung der
   Gebäude selbst in der Welt (z.B. ein sichtbar anderes Presse-Modell für HoneyPress) — das
   bräuchte neue Asset-Exporte aus Studio nach demselben Muster wie
   `BaerchiTemplate_<Rarity>.rbxm` (siehe Kommentar-Kopf `BaerchiMesh.luau`), was nur der
   Projektinhaber selbst in Studio machen kann. Dieser Durchlauf bleibt bei Zahlen/Formeln/
   UI-Text/Farbe — visuelle Asset-Wünsche bitte als offenen Punkt im Abschlussbericht
   auflisten, nicht selbst neue Modelle konstruieren.

**Akzeptanzkriterien:** Alle drei Gebäude haben nachweisbar unterschiedliche, im Code klar
benannte Effekte (kein gemeinsames `HONEY_BUILDING_UPGRADES` mehr für alle drei). Das
BuildingPanel zeigt für jedes Gebäude einen eigenen, in eigenen Worten formulierten Effekt-
Text. Die getroffene Entscheidung bei Punkt 2 (manuelle Auswahl vs. verbesserte Auto-Wahl)
ist im Abschlussbericht klar benannt samt Begründung. Bestehende Spielstände laden weiterhin
korrekt (Migration in `PlayerService`/`createDefaultPlayerData` falls neue Felder nötig
werden — z.B. falls `Building` um weitere Zahlen erweitert wird). `rojo build` fehlerfrei,
`luau-analyze` sauber.

---

## 5. Referenz — bereits vorhandene Remotes/Types, die hier relevant sind

- `Remotes.RequestUpgradeBuilding` (Client→Server, `buildingId: string`)
- `Remotes.RequestFeedHoney` (Client→Server, aktuell nur `baerchiUid: string` — für Teil D
  Punkt 2 evtl. um `buildingId` zu erweitern)
- `Remotes.FeedResultReceived` (Server→Client, `Types.FeedResult` — enthält bereits
  `buildingId`, aus welchem Gebäude der Honig kam)
- `Remotes.CombatResultReceived` (Server→Client, `Types.PitRunResult` — wird von
  `PitArenaService.sendResult` erst bei Ankunft am Kampf-Spot gefeuert, siehe Kommentar-Kopf
  der Datei)
- `Types.Building` (`id`, `level`, `honey`, `lastProducedAt`) — falls Teil D neue
  gebäudespezifische Felder braucht (z.B. eine eigene Kapazität statt der globalen
  `EconomyConfig.HONEY_CAPACITY`), hier erweitern und in `createDefaultPlayerData` +
  `PlayerService`-Migration nachziehen
- `EconomyConfig.BUILDING_UPGRADES` / `HONEY_BUILDING_UPGRADES` — wird in Teil D
  aufgelöst in drei eigene Tabellen bzw. in die neuen `BuildingBehavior`-Funktionen verlagert

## 6. Format-Erwartung an Opus

- Bei Code: **vollständige Dateien**, kein "Rest bleibt gleich" — mit Dateipfad als
  Kommentar in der ersten Zeile, im bestehenden Stil.
- Am Ende jedes bearbeiteten Teils: kurze Zusammenfassung (neue/geänderte Dateien, was für
  den Studio-Test nötig ist), nach dem Vorbild von `claude/SCHRITT2_ABGESCHLOSSEN.md`. Bei
  größerem Umfang gerne als eigenes Dokument `claude/TEIL_<X>_ABGESCHLOSSEN.md`.
- Bei offenen Balance-/Design-Entscheidungen (genaue Zahlen für Kapazitäts-/Heil-/XP-Boni,
  ob Teil D Punkt 2 als volles UI-Feature oder als Zwischenschritt umgesetzt wird, exakte
  Icon-/Farbwahl): eine sinnvolle Default-Annahme treffen **und explizit benennen**, statt
  implizit zu raten oder den Lauf mit einer Rückfrage zu blockieren.
- Nach JEDER Änderung an bestehenden `.luau`-Dateien: prüfen, dass keine Funktion vor der
  `local Tabelle = {}`-Deklaration ihres eigenen Moduls steht (dieses Projekt hatte diesen
  exakten Bug bereits einmal, siehe `MapService`-Fix vom 03.09.) — kurz mit `luau-analyze`
  oder einem Blick auf die Zeilenreihenfolge gegenprüfen, bevor eine Datei als fertig gilt.
