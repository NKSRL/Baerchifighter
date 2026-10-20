# Map-Stilbibel (Phase 1) – "Epilog-Insel-Stil", 2026-10-20

Status: Analyse fertig, noch nichts gebaut. Referenz-Renders: `docs/map_stilbibel/Epilog_Insel_Ref_schraeg.png`, `..._vorn.png` (Blender Workbench, Vertexfarben).

## 1. Ist-Stand der Map (Studio-Play, Server-Zaehlung)
| Teil | Anzahl | Herkunft |
|---|---|---|
| GrassTile | 38 | `MapParts.buildCheckerDisc/Plate` (Block, 0.08 hoch, CanCollide=false), Raster 24 / Plot 18 |
| Ground / GroundShore | 1 / 1 | `MapParts.buildIsland` (Zylinder-Scheibe + Sandkante), traegt die Kollision |
| PlotIsland_n (+Shore) | 8 (+8) | `PlotBuilder`/`WorldBuilder`, Radius 58 |
| TreeTrunk / TreeCrown / TreeTop | 18 / 18 / 18 | `ScenicBuilder` (Soll 22, 4 Plaetze fanden sich nicht) |
| Bush | 25 | Soll 26 |
| RimBush (+RimRock) | 32 (+40) | `PLOT_RIM_COUNT` 9 je Plot, abwechselnd Fels/Busch |
| Rock | 13 | Soll 16 |
| Teile gesamt Workspace (mit Spieler-Plot) | 1094 | Basiswert fuer den Bericht |

Abweichungen zum Auftrag: Baeume 18 statt "ca. 18" stimmt, Buesche 25 und RimBush 32 stimmen. Ein Baum besteht aus **3 Teilen** (Stamm, Krone, Top) -> 1 MeshPart spart 36 Instanzen.
Dreiecke heute: nur als Schaetzung moeglich (Block = 12, Ball/Zylinder = Engine-intern). Ich messe vor dem Umbau per `GetTriangleCount`-Ersatz nicht; Basis fuer das Budget ist daher **Instanzen** (hart) und die Mesh-Tris der neuen Teile (genau).

## 2. Gemessen an der Epilog-Insel (`Epilog_Insel.fbx`)
| Teil | Tris | Masse (Blender-Einh.) | Bemerkung |
|---|---|---|---|
| Wiese | 224 | 24.9 x 1.2 x 23.5 | Scheibe, 2 Gruen-Toene + hellere Flecken |
| Fels | 180 | 22.3 x 11.2 x 20.7 | dunkel-violett, Unterseite |
| Kristall | 288 | 11.7 x 5.3 x 11.7 | 3 Farbstufen (hell/mittel/dunkel) |
| Busch1-3 | je 85 | ca. 2.8 x 2.2 x 2.8 | 48 Verts, Blob mit grossen Facetten |

Formensprache: wenige, grosse Facetten; aufgeblasene Blobs; Boden 1.2 hoch; Farbe nur ueber **Vertexfarben** (Attribut `Col`, keine Textur); Verlauf unten dunkel / oben hell.
Vertexfarben (sRGB, aus linearen Werten umgerechnet, gerundet): Wiese dunkel ca. (24,110,24), Wiese hell/Flecken ca. (75,185,38) bis (60,165,25); Busch ca. (18,85,18) bis (22,115,22).

## 3. Palette (Vorgabe Auftrag + Messung)
- Honiggelb ca. (255,200,70) – Pfad, Blumen, Lichtpunkte
- Frisches Wiesengruen ca. (92,178,82) (= heutiges `GRASS_LIGHT`) bis (75,185,38)
- Tiefes Blattgruen ca. (30,100,40) bis (18,85,18)
- Sandbeige ca. (222,196,146) (= `PATH_COLOR`)
- Kristall-Akzent: Tuerkis ca. (70,220,200) und Flieder ca. (180,140,235)
- Stamm: warmes Braun, heute (122,84,52) bleibt

**Annahme A1 (bitte pruefen):** Die Epilog-Insel hat *magenta-pinke* Kristalle und *dunkelviolette* Felsen, der Auftrag verlangt aber Tuerkis/Flieder. Ich folge dem Auftragstext (Tuerkis/Flieder) und uebernehme von der Epilog-Insel nur Form, Facettenzahl und Verlaufslogik, nicht ihre Fremdfarben.
**Annahme A2:** Die Epilog-Buesche wirken facettiert. Ich baue sie etwas weicher (Smooth-Normalen, gleiche Tris-Groessenordnung), weil der Auftrag "weiche, aufgeblasene Formen" fordert.

## 4. Triangle-Budgets
| Teil | Budget Auftrag | Plan |
|---|---|---|
| Bodenkachel | <= 400 | 220-300 (Wiese ca. 224 wie Epilog) |
| Baum (1 MeshPart: Stamm+Krone) | <= 320 | 4 Varianten, 200-300 |
| Stumpf/Blumen-Gruppe | <= 320 | 2 Varianten, ca. 150 |
| Busch | <= 120 | 5 Varianten, 70-110 |
| RimBush | <= 120 | 2 Varianten, flach/breit, 60-90 |
| Kristall-Cluster (optional) | - | 2, ca. 90, Neon nur 1 Part je Cluster |

Instanz-Bilanz (Soll-Zahlen): Baeume 54 -> 18, Buesche 25 -> 25, RimBush 32 -> 32, GrassTile 38 -> 38 (Mesh). Instanzen sinken um 36, Teile nie mehr als heute.

## 5. Technische Befunde fuer Phase 2-5
1. `ServerStorage.Assets` **existiert nicht** (nur `ReplicatedStorage.Assets`, dort liegen Epilog-Vorlagen). **Annahme A3:** Ich lege `ServerStorage.Assets` an, Vorlagen `Map_*` darin (Server baut, Clients sehen nur Klone). Vorlagen bleiben so aus der Replikation raus.
2. Kollision haengt an `Ground`/`PlotIsland_n`, nicht an den GrassTiles (`CanCollide=false`). Kachel-Austausch aendert Laufwege also nicht, solange `Ground` bleibt. Pivot/Hoehe der Kacheln: Oberkante `PLATFORM_TOP_Y + GRASS_HEIGHT`.
3. `MapConfig` steht bei 192/200 lokalen Namen -> alle neuen Konstanten nach `Config/MapStyleConfig`, Flag `MAP_STYLE_V2` in `FeatureFlags`.
4. Epilog nutzt bereits ein Muster (`EpilogMeshes`: Vorlage klonen, Fallback auf Primitive). Ich uebernehme es fuer `Map_*`: fehlt die Vorlage, baut der Builder das alte Primitive.
5. Deterministik: `ScenicBuilder` nutzt `SCENERY_SEED = 20261004`. Die Anzahl/Position bleibt, nur der `ball()`/`pole()`-Aufruf wird getauscht; Varianten werden aus demselben Random-Strom gezogen **nach** den bestehenden Aufrufen, damit Positionen unveraendert bleiben.
6. Studio laeuft gerade im Play-Modus; Einspielung spaeter nur per `tools/make_update_rbxmx.py`.
7. Blender: `Map_Assets.blend` + `assets/map/*.fbx` noch nicht vorhanden. Blender-MCP ist verbunden (Szene aktuell: `Epilog_Rakete`, bleibt unangetastet; ich arbeite in eigenen Szenen).

## 6. Offen aus Phase 1
- Studio-Vorher-Screenshots (Hub, Plot, Arena-Rand): nicht gemacht, weil Studio im Play-Modus laeuft und die Aufnahme-Funktion eine Aufnahme-ID braucht. Hole ich vor Phase 5 nach.
- Genaue Dreieckszahl der alten Primitive: nicht ermittelbar, Vergleich laeuft ueber Instanzen und Mesh-Tris.
