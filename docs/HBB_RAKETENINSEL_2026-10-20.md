# P4 – Brücke, Mini-Insel und Rakete als Welt-2-Hinweis (20.10.2026)

Schalter `ROCKET_ISLAND` (aus = Welt wie vorher). **Nur im Code gebaut, noch nicht in Studio gesehen.**

## Gebaut
- `Config/RocketIslandConfig` (Maße, Farben, Text-Schlüssel), `Modules/RocketIslandRules` (Lage + Schild-Zustand, rein, getestet), `Util/MapBuild/RocketIslandBuilder` (Aufbau, hängt in `WorldBuilder.buildPlatform`, Fehler dort stoppen den Welt-Aufbau nie), `Controllers/RocketIslandController` (Client: Schild/Rakete nach eigenem Stand).
- Insel Radius 12, Sandkante, Old-School-Boden aus P1 (`MapMeshes.groundOldschool` mit Optionen, Kacheln 8/4/2, 20 Blöcke). Brücke mit `MapParts.buildSpan` (Breite 12 wie die Stege, mit Geländer).
- Rakete aus Primitiven (Zylinder-Sektionen weiß/rot, Nase aus 3 Scheiben, 3 Flossen, Neon-Fenster), Rampe aus Holz mit 4 Pfosten, Schild mit Holzpfosten + SurfaceGui, 2 Laternen, 3 Felsen. Name `RocketIsland_*`, alles an `Platform`.
- Teile geplant ca. 55 (Budget 60); der Builder meldet die echte Zahl im Output und als Attribut `PartCount`.
- Schild-Zustände nach Spielstand (`RocketIslandRules.state`): 1 gesperrt (inkl. Zeile "Final-Tower: Stage X/100"), 2 bereit (`epilog.state` pending/seen oder Final-Rekord ≥ 100), 3 gestartet (Rakete lokal ausgeblendet, "Welt 2 ist geöffnet."). Texte in 4 Sprachen (`world.rocket.*`, über `WorldText`/`Loc.msg`).
- Fenster-Glimmen ±10 %, 3 s (Tween, kein Loop-Code).
- Debug: `D:Invoke("rocketisland","state")`, `D:Invoke("rocketisland","set",1|2|3)` (0 = aus dem Spielstand).

## Lage (A6)
Part `RaketenAnker` im Workspace gibt die Mitte vor (Richtung + Abstand von der Inselmitte; zu nah wird geklemmt, Mindestluft 10 Studs). **Ohne Anker: Platzhalter** bei 22,5° zwischen Plot 1 und 2, Abstand 166 von der Mitte. Der Builder warnt dann im Output; das Attribut `Placeholder` steht am Ordner `RocketIsland_Root`. Abstand zu den Plot-Inseln ist im Test geprüft (Platzhalter: frei), bei eigenem Anker warnt der Builder bei zu geringer Luft.

## Abweichungen / nicht gebaut
- Keine Blender-Assets (`Map_Rakete_Insel.fbx`, `Map_Schild_Welt2.fbx`) und keine Wiederverwendung von `Epilog_Rakete`: die Rakete besteht aus Primitiven. Ein Blender-Modell ersetzt sie später, ohne die Logik anzufassen (Teile tragen das Attribut `RocketPart`).
- Journey-Etappe 7 "Insel entdeckt" und der einmalige "Welt 2"-Moment sind nicht verdrahtet.
- `mapstyle on/off` baut die Raketen-Insel nicht neu (nur beim Welt-Aufbau).
- Keine Screenshots (vorne/seitlich, 3 Zustände × 4 Sprachen), keine Studio-Abnahme, Palette nicht im Spiel geprüft.

## Tests
`rocket_island.test.lua` (neu, grün): Zustände, Platzhalter-Lage, Klemmen, Plot-Abstand, Boden-Raster. `check_decor/ui/loc/locals/feedback/members/consistency`: keine neuen Funde.
