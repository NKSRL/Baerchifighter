# tools — Prüfungen vor dem Studio-Start

Vier Prüfungen und zwei Vorschauen, die Fehler finden, bevor Roblox sie beim
Start um die Ohren haut. Alles davon ist **optional** — es braucht Python 3
und (für die erste) den Luau-Compiler. Wer sie nicht laufen lässt, verliert
nichts außer der Vorwarnung.

## 1. Syntax — `luau-compile`

Der offizielle Luau-Parser. Findet jeden Tippfehler, den Studio erst beim
Laden meldet.

Einmalig herunterladen (Windows: `luau-windows.zip`):

    https://github.com/luau-lang/luau/releases/latest

Dann im Projektordner:

    for %f in (src\*.luau) do luau-compile --binary "%f"

Keine Ausgabe = alles in Ordnung.

## 2. `check_members.py` — unbekannte Modul-Felder

Findet Zugriffe wie `MapConfig.GIBT_ES_NICHT` oder `EconomyConfig.tippfehler`.
Das ist die häufigste Fehlerart in diesem Projekt: Ein Wert wird in einer
Config umbenannt, und eine Stelle irgendwo greift noch auf den alten Namen zu.
Luau selbst meldet das nicht, weil die Configs einfache Tabellen zurückgeben.

    python3 tools/check_members.py

## 3. `check_consistency.py` — verteilte Wahrheiten

Prüft die Dinge, die über mehrere Dateien verteilt sind und deshalb
auseinanderlaufen können:

* Die Gebäude-IDs müssen in **allen neun** Listen identisch sein
  (`Types.BuildingId`, `MapConfig.BUILDING_OFFSETS`, `BUILDING_ORDER`,
  `BuildingBehavior.BEHAVIORS`, `BuildingBehavior.BUILDING_UPGRADES`,
  `Theme.BUILDING_COLORS`, `IslandService.VALID_BUILDINGS`,
  `WorldController.BUILDING_NAMES`, `BuildingPanel.BUILDINGS`,
  `Types.createDefaultPlayerData`).
  Die Ausbau-Tabellen sind mit v7 von `EconomyConfig` nach `BuildingBehavior`
  gewandert — dort steht seitdem alles, was sich pro Gebäude unterscheidet.
* Bei `RateLimiter.connect` müssen Remote-Objekt und Cooldown-Schlüssel
  denselben Namen tragen.
* Jedes verbundene Remote sollte einen eigenen Cooldown in `NetworkConfig`
  haben.
* Jedes Modul in der `GameManager`-Boot-Liste muss als Datei existieren.
* Jeder Service mit `init()` muss in der Boot-Liste stehen.

    python3 tools/check_consistency.py

Beide Skripte nehmen optional den Pfad zu `src` als Argument, sonst suchen
sie ihn relativ zum Projektordner.

## 4. `check_decor.py` — Geometrie der Gebäude

Die Formen der Gebäude und des Honigmasts stehen als reine Zahlen in
`MapConfig.BUILDING_DECOR` / `CENTER_DECOR`. Ob ein Deckel schwebt oder ein
Ring in den Nachbarn ragt, sieht man dort nicht — hier schon:

* kein Teil steckt im Boden,
* kein Teil schwebt (jedes muss senkrecht an einem anderen anliegen),
* Gebäude-Deko bleibt im Grundriss der unsichtbaren Körper-Part,
* Gebäude-Deko bleibt unter dem Schild.

<!-- -->

    python3 tools/check_decor.py

## 5. `render_decor.py` — Vorschau ohne Studio

Zeichnet dieselben Daten als maßstabsgetreue Seitenansicht in eine
HTML-Datei. Beantwortet die Frage „sieht das überhaupt nach einem
Bienenstock aus?", ohne Studio zu starten.

    python3 tools/render_decor.py decor_preview.html

## 6. `render_map.py` — Grundriss der Welt

Drei Ansichten, alle maßstabsgetreu aus `MapConfig` gezeichnet:

1. **Die Welt von oben** — Hauptinsel, die acht Plot-Inseln, die 16 Stege und
   die Arena-Inseln, samt Karo-Wiese und Sandkanten.
2. **Eine Plot-Insel in groß** — Beet, Gebäude, Honig-Tropfen, Teich und der
   Platz des ausgerüsteten Bärchis.
3. **Ein senkrechter Schnitt** von der Weltmitte bis zur Arena. Das ist die
   Ansicht, die der Grundriss nicht zeigen kann: liegt der Steg über dem Wasser
   statt darin, sitzt die Sandkante zwischen Wiese und Wasser, und sind die
   Stufen niedrig genug, dass man aus dem Wasser wieder an Land kommt?

Beantwortet die Fragen, die man den Zahlen nicht ansieht: Ragt das Beet über
seine Insel? Kommt der Steg an der nächsten Insel an? Berühren sich zwei
Inseln? Die Tabelle rechnet dieselben Zusammenhänge nach, die auch
`MapService.init` beim Serverstart prüft — hier sieht man das Ergebnis
allerdings sofort und ohne Studio.

    python3 tools/render_map.py map_preview.html

Mit `--svg` schreibt das Werkzeug stattdessen die drei nackten SVGs in einen
Ordner — praktisch, wenn man sie weiterverarbeiten oder in ein PNG wandeln will:

    python3 tools/render_map.py --svg vorschau/

## 5. `check_loc.py` — Übersetzungen

Prüft das Lokalisierungssystem (`src/shared/Localization`): hat jede Sprache
alle Schlüssel, stimmen die `{platzhalter}` überein, sind alle im Code
verwendeten Schlüssel vorhanden? Meldet außerdem, wie viele Textstellen noch
fest im Code stehen (`--todo` zeigt jede einzelne).

    python3 tools/check_loc.py
    python3 tools/check_loc.py --todo

Exit-Code 1 bei Fehlern — taugt als letzter Schritt vor dem Commit.

## 6. `luau-tests/` — Tests ohne Studio

Führt Luau-Code mit dem echten Compiler aus (Syntax aller Dateien, Tests für
`Loc`, Rauchtest der Client-UI). Braucht Node.js, siehe
`tools/luau-tests/README.md`.
