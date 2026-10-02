# Teil D (Die 3 Gebäude: Redesign + UI) — abgeschlossen

Stand: 07.09.2026. Auftrag aus `claude/OPUS_PROMPT_QUALITAET_GEBAEUDE_2026-09-07.md`,
**Teil D**. Setzt auf dem Stand nach Teil A + C + B auf. Damit ist das Dokument
vollständig abgearbeitet.

Die drei Gebäude sind nicht mehr „dasselbe mit anderem Namen". Jedes hat genau eine
eigene Achse, und das Ausbauen ist ab jetzt drei verschiedene Entscheidungen.

## Die drei Rollen

| Gebäude | Rolle | Level 1 → 10 |
|---|---|---|
| **Bienenstock** | **Vorrat** | Lager 5 → 14 Honig, Takt 20 s → 8 s |
| **Honigtopf** | **Heilung** | *sein* Honig heilt 25 % → 60 % der HP |
| **Honig-Presse** | **Wachstum** | +0 % → +2400 % XP auf **jeden** Honig, egal woher |

Daraus entsteht die eigentliche Entscheidung im Spiel: Topf-Honig heilt am meisten, ist
aber knapp — verfütterst du ihn jetzt für XP, fehlt er nach dem nächsten PIT-Lauf. Die
XP sind bei allen drei gleich, es lohnt sich also, den Heil-Honig aufzuheben.

## Die Entscheidung bei Punkt 2 (Fütter-Logik)

Das Dokument stellt „volles UI-Feature" und „vorerst nur bessere Auto-Wahl" zur Wahl und
verlangt, die Entscheidung explizit zu benennen. **Ich habe beides gebaut — und das ist
keine Ausweichantwort, sondern folgt daraus, dass es zwei Aufrufer gibt:**

* **Der Spieler wählt selbst.** Auf der Bärchi-Detailkarte stehen drei Fütter-Knöpfe, je
  einer pro Gebäude, mit dem eigenen Bestand daneben und in derselben Farbe wie die
  zugehörige Karte im Gebäude-Panel. `Remotes.RequestFeedHoney` überträgt jetzt ein
  zusätzliches `buildingId`; der Server validiert es wie
  `IslandService.upgradeBuilding` und lehnt ein unbekanntes Gebäude ab, statt
  stillschweigend automatisch zu wählen.
* **Der Autopilot kann nicht fragen.** `BaerchiAutopilotService` schickt den
  ausgerüsteten Bärchi von selbst zum Teich — dort steht niemand, den man fragen könnte.
  Ohne eine bessere Regel hätte genau der Weg, über den im Spiel die meisten Fütterungen
  laufen, weiter blind den „wertvollsten" Honig genommen. Die neue Regel:
  * unter 50 % HP (`EconomyConfig.HONEY_AUTO_HEAL_HP_RATIO`): der Honig, der am meisten
    heilt — dafür hebt man den Topf ja auf;
  * sonst: das **vollste** Lager zuerst, weil dort die Produktion stillsteht, und bei
    Gleichstand bewusst der Honig, der am **wenigsten** heilt — der Topf-Honig soll für
    nach dem Kampf liegen bleiben.

Nur die alte Regel zu verbessern hätte das UI unverändert gelassen, obwohl genau dort
sichtbar werden soll, dass es jetzt drei Sorten gibt. Nur das UI zu bauen hätte den
Autopiloten mit einer Regel zurückgelassen, die es nicht mehr gibt.

## Geänderte Dateien

**Mechanik**

- `BuildingBehavior.luau` — von einem Feld auf fünf pro Gebäude erweitert
  (`getIntervalSeconds`, `getCapacity`, `getHealPercent`, `getXpMultiplier`, `describe`)
  plus die drei Ausbau-Tabellen, `getXpPerHoney`, `getTotalCapacity`, `getMaxCapacity`,
  `isValidId`.
- `EconomyConfig.luau` — die Ausbau-Tabellen sind raus, `HONEY_UPGRADE_COSTS` wird
  exportiert, `HONEY_AUTO_HEAL_HP_RATIO` ist neu. `HONEY_CAPACITY` / `HONEY_HEAL_PERCENT`
  sind jetzt ausdrücklich **Basis**-Werte.
- `HoneyService.luau` — `feed` nimmt ein optionales `buildingId`; Heilung nach
  Herkunfts-Gebäude, XP über `getXpPerHoney`; `pickBestBuilding` → `pickAutoBuilding`.
- `EconomyService.luau`, `MapService.luau`, `DebugService.luau` — fragen Kapazität und
  Ausbau-Daten über `BuildingBehavior` ab.
- `PlayerService.luau` — v7-Migration (siehe unten). `Types.luau` — nur Kommentare und
  `version = 7`.
- `MapConfig.luau` — `shortName` je Gebäude, `HONEY_DOT_SPACING`.

**UI**

- `BuildingPanel.luau` — neu geschrieben: Farbstreifen und farbiger Titel je Gebäude,
  drei Zeilen statt einer (Bestand / was es kann / was die nächste Stufe bringt), und die
  über den Prompt geöffnete Karte wird hervorgehoben und angescrollt.
- `BaerchiPanel.luau` — ein „Honig fuettern" wird zu drei Knöpfen mit Bestand.
- `Theme.luau` — drei Rollenfarben plus `Theme.buildingColor(id)`.
- `WorldController.luau` — gibt die angeklickte `BuildingId` ans Panel weiter.

**Werkzeuge**

- `tools/check_consistency.py` / `tools/README.md` — die Gebäude-IDs werden jetzt in
  **neun** Listen gegengeprüft (drei neue: `BuildingBehavior.BEHAVIORS`,
  `BuildingBehavior.BUILDING_UPGRADES`, `Theme.BUILDING_COLORS`).
- `tools/render_map.py` — Tropfen-Bogen wie in `MapService`.

## Getroffene Default-Entscheidungen

1. **Das schnellere Produzieren ist vom Honigtopf zum Bienenstock gewandert.** Das
   Dokument gibt dem Bienenstock „mehr Lager und/oder Grund-Produktionsrate" und dem
   Honigtopf die Heilung — seine bisherige Sonderregel wäre damit ersatzlos entfallen.
   „Mehr Honig pro Zeit" und „mehr Honig auf Lager" sind aber dieselbe Achse, also hat
   der Bienenstock sie bekommen, statt sie zu löschen. Nachgeprüft: er erbt **exakt** die
   Intervall-Kurve, die bis v6 der Honigtopf hatte (20 → 8 s).

2. **Die XP-Kurve ist unverändert, sie hat nur den Besitzer gewechselt.** Der
   Multiplikator der Presse ist keine neue Zahl, sondern `HONEY_XP[level]` geteilt durch
   `HONEY_XP[1]`. Bei „Presse auf Level N" gibt ein Honig deshalb genau so viel XP wie
   früher bei „Gebäude auf Level N" — 30 / 45 / 65 / … / 750, aus dem echten Code
   ausgelesen und Stufe für Stufe verglichen.

3. **Preise unverändert.** Das Abnahmekriterium verlangt, dass es keine gemeinsame
   `HONEY_BUILDING_UPGRADES` mehr gibt — es gibt jetzt drei eigene Tabellen mit je
   eigenem Effekt-Text. Die **Kosten** kommen aber weiter aus derselben Kurve. Ich habe
   Preisfaktoren je Rolle erwogen (Presse teurer, weil ihr Effekt global wirkt) und
   verworfen: das wäre eine Balance-Änderung, die niemand bestellt hat und die ein
   laufender Spielstand sofort merkt. Wenn du sie doch willst — die drei Tabellen werden
   in `BuildingBehavior` an einer Stelle aus der Kurve gebaut.

4. **Die Ausbau-Tabellen sind von `EconomyConfig` nach `BuildingBehavior` gezogen.** Ihr
   Effekt-Text beschreibt die Mechanik des jeweiligen Gebäudes, und die kennt nur
   `BuildingBehavior`. Umgekehrt darf `EconomyConfig` es nicht requiren — das wäre ein
   Ringschluss. Der Text wird **erzeugt**: der Satz einer Ausbau-Stufe ist wörtlich die
   `describe()` dieser Stufe, Anzeige und Wirkung können also nicht auseinanderlaufen.

5. **Bienenstock-Maximum ist 14, nicht die runde 12.** 5 auf Level 1 und 14 auf Level 10
   sind neun Stufen und neun Honig — jeder Ausbau bringt genau einen Platz mehr. Bei 12
   wären zwei Stufen dabei gewesen, auf denen sich am Lager sichtbar nichts tut, und ein
   Ausbau ohne erkennbare Wirkung ist genau das, was dieses Redesign abschaffen soll.

6. **Farben nach Rolle, nicht nach Gebäude.** `Theme.COLORS.volume / healing / growth`,
   zugeordnet über `Theme.buildingColor(id)` — dieselbe Bauart wie `rarityColor`, damit
   Gebäude-Karte und Fütter-Knopf nicht auseinanderlaufen können.

7. **Keine neuen 3D-Modelle**, wie im Dokument ausdrücklich vorgegeben. Die Honig-Tropfen
   am Gebäude passen sich aber an: fester Winkelabstand statt festem Bogen, gedeckelt bei
   200°. Fünf Tropfen sehen dadurch exakt aus wie vorher, vierzehn überlappen nicht.

## Die v7-Migration (wichtig für deinen laufenden Spielstand)

Vorher hing die XP eines Honigs am Level des Gebäudes, aus dem er kam — also an allen
dreien. Jetzt hängt sie allein an der Presse. **Ohne Ausgleich hättest du beim ersten
Start Fortschritt verloren:** Bienenstock auf 5, Presse auf 1 hätte plötzlich 30 statt
135 XP pro Honig gegeben.

Deshalb erbt die Presse **einmalig** das höchste Level, das der Spielstand bei irgendeinem
Gebäude erreicht hatte. Weil die alte Auto-Wahl ohnehin immer das Gebäude mit den meisten
XP genommen hat, bekommst du danach exakt so viel XP pro Honig wie vorher — nicht weniger
und nicht mehr.

Das ist die erste Migration im Projekt, die an der Versionsnummer hängen **muss**: sie
rechnet einen Wert um, statt ein fehlendes Feld anzulegen. Liefe sie bei jedem Join
erneut, würde die Presse jedes Mal wieder hochgezogen und du könntest die anderen beiden
nie überholen. `version` steht deshalb jetzt auf 7. Am Datenmodell selbst ändert sich
nichts — `Types.Building` hat unverändert `id`, `level`, `honey`, `lastProducedAt`.

## Verifikation (alles grün)

| Prüfung | Ergebnis |
|---|---|
| `luau-compile --null` über alle 50 `.luau` | fehlerfrei |
| `check_members.py` / `check_consistency.py` / `check_decor.py` | alle sauber (Gebäude-IDs jetzt in neun Listen) |
| Zusatz-Prüfungen Teil A+C und Teil B | weiterhin bestanden |
| **Der echte Luau-Code ausgeführt** | `EconomyConfig` + `BuildingBehavior` laufen im Standalone-Luau; alle Zahlen unten stammen aus dem ausgelieferten Code, nicht aus einer Nachbildung |
| XP pro Honig, Presse Lv. 1–10 | 30 / 45 / 65 / 95 / 135 / 190 / 265 / 370 / 520 / 750 — identisch zu vorher |
| XP unabhängig von den anderen beiden Gebäuden | ✔ (gegen Level 1, 5 und 10 der anderen geprüft) |
| Jede Achse gehört genau einem Gebäude | ✔ Bienenstock Lager+Tempo, Topf Heilung, Presse XP — auf allen 10 Leveln |
| Bienenstock-Takt = alte Honigtopf-Kurve | ✔ auf 1e-9 genau |
| Jeder Ausbau ändert den Effekt-Text sichtbar | ✔ für alle drei, Level 2–10 |
| Ausbau-Text = Effekt-Text derselben Stufe | ✔ (er wird daraus erzeugt) |
| Ausbau-Kosten unverändert | ✔ alle neun Stufen |
| `isValidId` weist Unbekanntes ab | ✔ |
| Kein Service/Panel verzweigt nach einer BuildingId | ✔ nur Listen, Validierung und Farbzuordnung nennen die ids |
| `Types.Building` unverändert → keine Datenmigration | ✔ (die v7-Migration rechnet nur die Presse hoch) |
| Honig-Tropfen überlappen nicht | ✔ bei 5 und bei 14 Plätzen; fünf Tropfen exakt wie vorher (150°) |
| `luau-analyze` vorher/nachher | keine neue Meldungsart |

Zu `luau-analyze` wie in den Teilen davor: ohne Roblox-API-Definitionen meldet es schon im
unveränderten Projekt hunderte `Unknown type 'Model'`. Aussagekräftig ist der Vergleich
der Meldungs**arten** — der einzige Zuwachs ist ein `LocalShadow` in `PlayerService`, das
es vorher schon gab und das nur durch die eingefügte Migration von Zeile 479 auf 510
gerutscht ist.

## Was im Studio zu testen ist

1. **Gebäude-Panel öffnen.** Drei Karten mit drei Farben und drei verschiedenen Sätzen.
   Am Bienenstock stehen Lager und Takt, am Topf ein Heil-Prozentsatz, an der Presse ein
   XP-Bonus.
2. **Ein Gebäude in der Welt anklicken** → das Panel geht auf und die richtige Karte ist
   umrandet und im Bild.
3. **Bärchi-Karte öffnen.** Drei Fütter-Knöpfe statt einem, jeder mit seinem Bestand;
   leere Lager sind ausgegraut. Farben passen zu den Karten aus Schritt 1.
4. **Gezielt füttern.** Erst Topf-Honig, dann Stock-Honig auf denselben verletzten
   Bärchi: der Topf-Honig muss sichtbar mehr HP bringen, die XP müssen gleich sein.
5. **Presse ausbauen** und noch einmal füttern — jetzt müssen die XP steigen, egal aus
   welchem Gebäude der Honig kommt.
6. **Bienenstock ausbauen** und `RBLDebug:Invoke("honey")` laufen lassen: der Bienenstock
   muss mehr Honig fassen als die anderen beiden, und am Gebäude müssen entsprechend mehr
   Tropfen leuchten.
7. **Autopilot beobachten.** Bärchi unter 50 % HP kämpfen lassen und warten: er soll von
   selbst zum Teich gehen und dabei den Topf-Honig nehmen. Bei fast vollen HP soll er
   stattdessen das vollste Lager leeren.
8. **Deinen bestehenden Spielstand laden** und im Gebäude-Panel nachsehen: die
   Honig-Presse muss auf dem höchsten Level stehen, das vorher irgendeines deiner
   Gebäude hatte. Danach beim zweiten Join **nicht** weiter steigen.

## Offen für später

- **Sichtbare Unterscheidung der Gebäude in der Welt** — im Dokument ausdrücklich
  ausgeschlossen, weil es Asset-Exporte aus Studio braucht. Konkrete Wünsche, jetzt wo die
  Rollen feststehen:
  * **Bienenstock:** ein zweites/drittes Stockwerk, das mit dem Level dazukommt — das
    wäre die direkteste Übersetzung von „mehr Lager".
  * **Honigtopf:** ein Topf, dessen Füllstand mit dem Level sichtbar steigt, plus etwas
    Dampf oder Glanz — er ist jetzt die Heilstation.
  * **Honig-Presse:** bewegliche Teile (eine Spindel, ein Hebel), damit „Wachstum"
    Bewegung hat. Mit `FigureFX` aus Teil B ließe sich das ohne Rig animieren.
  * Alles nach dem Muster von `BaerchiTemplate_<Rarity>.rbxm` — nur du kannst das in
    Studio exportieren.
- **`tools/render_map.py` ist kaputt** — und zwar schon vorher, nicht durch Teil D: es
  sucht einen Block `BAERCHI_AREA` in `MapConfig`, den es seit dem Equip-System nicht mehr
  gibt (statt eines Rasters für 25 Figuren steht dort ein einzelnes
  `BAERCHI_HOME_OFFSET`). Die anderen fünf Werkzeuge laufen.
- **Rebirth mitten in einem PIT-Lauf** reißt weiterhin den ganzen Plot weg
  (`MapService.rebuildIsland` fragt kein `ActivityLock`). Offen seit Teil A.
- **Teil A Punkt 5** (Signatur-Neuberechnung in `PlotDisplayService`) weiterhin offen.
- **Balance zum Nachjustieren**, alles an je einer Stelle: `BEEHIVE_MAX_CAPACITY`,
  `BEEHIVE_MIN_INTERVAL_SECONDS`, `HONEYPOT_MAX_HEAL_PERCENT` in `BuildingBehavior`;
  `HONEY_AUTO_HEAL_HP_RATIO` und die Kostenkurve in `EconomyConfig`.
