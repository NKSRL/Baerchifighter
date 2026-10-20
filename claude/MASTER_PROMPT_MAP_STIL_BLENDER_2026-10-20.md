=== MASTER PROMPT · Map-Überarbeitung im "Epilog-Insel-Stil" (Blender-MCP) ===

--- KOPIEREN AB HIER ---

Create a stylized low-poly map set (ground, shoreline, grass, trees, bushes, rim foliage) for a cartoon Roblox idle/gacha-fighter game ("Honey Bear Brawl", Luau, Rojo-Struktur), modelled in Blender via MCP in the same style as the finished Epilog island.

Lies zuerst `CLAUDE.md`, `docs/HBB_STATUS_2026-10-05.md`, `docs/HBB_EPILOG_ABNAHME_2026-10-20.md`, `src/server/Util/MapBuild/EpilogMeshes.luau`, `ScenicBuilder.luau`, `WorldBuilder.luau`, `PlotBuilder.luau`, `MapParts.luau` und `src/shared/Config/MapConfig.luau` (192/200 lokale Namen: neue Konstanten NUR in einer neuen Config-Datei, z.B. `Config/MapStyleConfig`).

========================================
0. KERNIDEE
========================================
Die ganze Map bekommt dieselbe Handschrift wie die Epilog-Insel (`assets/epilog/Epilog_Insel.fbx`: Wiese, Fels, Kristall, Busch1-3): weiche, leicht aufgeblasene Formen, wenige große Facetten, klare Silhouetten, warme Farbverläufe über Vertexfarben, kleine Details (Kristalle, Grasbüschel). Der Spieler soll das Gefühl haben, auf einem handgemachten Spielzeug-Diorama zu stehen, das überall gleich liebevoll aussieht. Nichts wird gelöscht; die alte Optik bleibt über einen Schalter erreichbar.

========================================
1. STRUKTUR & ABLAUF
========================================
Gesamtdauer der Arbeit: in Etappen, jede einzeln abnehmbar. Anker: Weltursprung der Hauptinsel (`MapConfig`), Plot-Inseln wie bisher. Ersetzt werden die bestehenden Teile `Ground`, `GroundShore`, `GrassTile` (ca. 38), `TreeTrunk`/`TreeCrown`/`TreeTop` (ca. 18 Bäume), `Bush` (ca. 25) und `RimBush` (ca. 32) sowie die kleinen Bäume auf den Plots.

* Phase 1 – Analyse und Stilbibel (kein Bauen): Screenshots der aktuellen Map (Hub, Plot, Arena-Rand) und der Epilog-Insel nebeneinander; aus der Epilog-Insel messen: Tris pro Teil (Busch 85, Fels 180, Kristall 288, Wiese 224), Proportionen, Vertexfarben-Paletten, Kantenweichheit. Ergebnis: `docs/HBB_MAP_STILBIBEL_<datum>.md` mit Palette, Triangle-Budgets, Beispielrenders. Rückfrage an mich nur, wenn die Stilbibel nicht eindeutig ableitbar ist.
* Phase 2 – Bodenfläche (Hauptinsel + Plot-Inseln + Uferstreifen): modulare, kachelbare Boden-Meshes (Wiese mit weicher Kante, Uferband, kleine Fels- und Kristall-Akzente am Rand, optional Pfad-Kacheln). Jede Kachel mit Vertexfarben-Variation, damit keine sichtbare Wiederholung entsteht. Gleiche Maße und Pivots wie die bisherigen Parts, damit Laufwege, Plots und Kollision unverändert bleiben.
* Phase 3 – Bäume: 4 Baum-Varianten (rund, hoch-schmal, doppelt-krone, junger Baum) + 2 Baumstumpf/Blumen-Gruppen. Stamm weich geschwungen, Krone aus 2-3 verschmolzenen Kugel-Lobes, Farbverlauf unten dunkel, oben hell. Pro Baum 150-320 Tris.
* Phase 4 – Büsche und Rand-Vegetation: 5 Busch-Varianten im Stil der Epilog-Büsche (Ziel 60-120 Tris), Rand-Busch (RimBush) flacher/breiter, Grasbüschel-Cluster, kleine Blumen. Platzierung bleibt in `ScenicBuilder` deterministisch (Seed), Position und Zahl wie bisher, nur der Look tauscht.
* Phase 5 – Einbau und Abgleich: Meshes als FBX nach `assets/map/`, in Studio importieren, Vorlagen unter `ServerStorage.Assets` (`Map_*`), Builder auf Klonen der Vorlagen umstellen, alte Parts über `FeatureFlags.MAP_STYLE_V2` (Standard erst nach meiner Abnahme an) ersetzen. Vorher/Nachher-Screenshots.
* Finale: Gesamtvergleich Hub, Plot, Arena-Rand, Nacht und Tag; Teile-Zahlen und Tris vor/nach; Liste der Asset-IDs.

Bewegungs- und Timing-Vokabular: statische Geometrie. Nur der vorhandene Wind/Schaukeln aus `Ambience`/`Life` darf weiterlaufen; neue Animation nur, wenn sie ohne Mehrkosten über bestehende Skripte geht.
Variation: pro Baum/Busch Zufallsrotation um Y, Skalierung ±12 %, Farbvariante über Attribute (Material bleibt gleich), deterministisch per Seed (kein Flackern bei Neuaufbau, kein Unterschied zwischen Servern).

========================================
2. ATMOSPHÄRE, STIL & FARBPALETTE
========================================
It should feel warm, soft and handcrafted, with a palette of honey yellow, fresh meadow green, deep leaf green and sandy beige, with small crystal accents in turquoise and lilac on rocks, not realistic, noisy, grey or over-detailed.
Referenzen: die Epilog-Insel dieses Projekts (verbindlich), Toy-Diorama, Animal-Crossing-/Mario-Galaxy-Weichheit, kein Pixel-Rauschen.
Licht & Glow: Materialien nur Plastic/SmoothPlastic, keine Neon-Flächen außer winzigen Kristall-Akzenten (Neon max. 1 Part pro Kristallgruppe), keine Eigenbeleuchtung; Look muss bei Tag UND Nacht (`DayCycle`/`ZoneLight`) lesbar bleiben; Bloom des Projekts unverändert.
Audio: nicht Teil dieses Auftrags.

========================================
3. TECHNISCHE RAHMENBEDINGUNGEN
========================================
* Ausführung: Server baut wie bisher (`WorldBuilder`/`ScenicBuilder`/`PlotBuilder`), Clients sehen nur replizierte Parts; Vegetation rein dekorativ.
* Parameter: `Config/MapStyleConfig` (Seeds, Dichte, Skalierungsbereiche, Farbvarianten, Variantenanzahl); Schalter `FeatureFlags.MAP_STYLE_V2`.
* Performance-Budget: Gesamtmap vor/nach messen und im Bericht nennen. Ziel: nicht mehr Dreiecke als heute in Summe (+15 % erlaubt), pro Baum ≤ 320, Busch ≤ 120, Bodenkachel ≤ 400 Tris; Texturen höchstens eine gemeinsame 512×512 Palette (oder nur Vertexfarben, bevorzugt); maximal gleichviel Instanzen wie heute (Teile zusammenlegen, wo möglich, z.B. Krone+Stamm = ein MeshPart); Mobile-tauglich: ja (StreamingEnabled und Low-End-Geräte mitdenken).
* Cleanup: Neuaufbau (Rebirth, Plot-Reset) darf keine Reste lassen; `check_decor.py` und Teile-Zahl-Test grün.
* Kollision/Gameplay: Bäume und Büsche ohne Kollision (`CanCollide=false`, `CanQuery=false`, `CanTouch=false`); Boden-Kollision bleibt exakt wie bisher (gleiche Höhe, gleiche Ausdehnung). `CollisionFidelity` an den Vorlagen auf Box setzen (zur Laufzeit nicht schreibbar).
* Kompatibilität: R15, `--!strict`, deutsche Kommentare, Texte nur über `Loc`, nichts löschen, keine Balance-Zahlen ändern, Studio-Einspielung ausschließlich über `tools/make_update_rbxmx.py` (nie Rojo über Studio-Inhalte, nie Studio-Skripte mit älteren Repo-Ständen überschreiben, vorher Sync Studio→Repo prüfen).

========================================
4. CUSTOM ASSETS & PIPELINE
========================================
Create/draw custom 3D-MESHES in Blender (kein Plugin-Import, kein Fremdasset):
 1. Boden-Kacheln (Wiese, Uferband, Ecke, Randfels): FBX, Vertexfarben, ≤ 400 Tris, Pivot Mitte-Unterkante, 1 Stud = 1 Blender-Einheit.
 2. 4 Baum-Varianten + Stumpf/Blumen: je ≤ 320 Tris, Pivot Stammfuß, Y-up.
 3. 5 Busch-Varianten + Grasbüschel-Cluster: je ≤ 120 Tris, Pivot Boden.
 4. Rand-Busch (RimBush) 2 Varianten.
 5. Optional: 2 kleine Kristall-Cluster für Fels-Akzente (Neon-Anteil als getrennter Part).
Konventionen: Präfix `Map_`, Namen `Map_Baum_A`, `Map_Busch_B` usw.; Vertexfarben in sRGB, keine Texturen (oder eine gemeinsame `Map_Palette_512.png`); Normalen weich, Facetten nur bei Fels; Modifier angewendet, Skalierung 1, Ursprung am Boden; ein Ordner `assets/map/` plus `.blend`-Quelle `Map_Assets.blend`.
Ablauf: Erst in Blender erstellen und prüfen (Renders von vorn, schräg oben und im Vergleich zur Epilog-Insel ansehen, Tris pro Teil per Skript zählen), dann lokal in Studio importieren, mit der alten Map vergleichen und im Zusammenspiel testen (Tag/Nacht, Plot, Arena-Rand, Mobile-Ansicht); erst danach nur den finalen Satz hochladen (keine Zwischenstände, keine Dubletten). Am Ende alle hochgeladenen Asset-IDs auflisten und in `Config/MapStyleConfig` eintragen.

========================================
5. INTEGRATION & ÜBERGABE
========================================
Ziel: Vorlagen unter `ServerStorage.Assets.Map_*`; Builder (`WorldBuilder`, `ScenicBuilder`, `PlotBuilder`) klonen sie. Test: `D:Invoke("mapstyle","on"|"off")` (neuer Debug-Befehl, nur Studio) schaltet zwischen alt und neu; `D:Invoke("parts")` liefert die Teile-Zahlen.
Gewünscht: Aufruf-Beispiel als Einzeiler, Hinweis auf Konstanten in `MapStyleConfig`, kurze Ordnerübersicht, Update-Datei `updates/HBBUpdate_MapStil_<datum>.rbxmx` samt Befehlsdatei, Bericht `docs/HBB_MAP_STIL_ABNAHME_<datum>.md` und Studio-Playbook "In Studio prüfen".

========================================
6. ABNAHMEKRITERIEN
========================================
Fertig ist es, wenn ich:
 * Boden, Bäume, Büsche und Rand im selben Stil wie die Epilog-Insel sehe, ohne Fremdfarben und ohne harte Kanten;
 * auf Hub, Plot und Arena-Rand keine Laufwege-, Kollisions- oder Kamera-Änderung bemerke;
 * die Teile-/Dreieckszahl vor und nach dem Umbau im Bericht finde und sie im Budget liegt;
 * Tag und Nacht, Mobile-Ansicht und Rebirth-Neuaufbau ohne Fehler und ohne Reste in Workspace sehe;
 * mit einem Befehl zwischen alter und neuer Map wechseln kann;
 * die Meshes vorab in Blender-Renders und im Studio gesehen habe, bevor irgendetwas hochgeladen wurde;
 * `check_loc`, `check_ui`, `check_locals`, `check_members`, `check_consistency`, `check_decor` und alle Luau-Tests wie vor dem Umbau grün sind (bekannte rote Altlasten dürfen nicht schlechter werden).

========================================
7. ARBEITSWEISE & NICHT-ZIELE
========================================
* Wenn etwas unklar ist: sinnvolle Annahme treffen, kennzeichnen und weitermachen.
* Etappenweise vorgehen (Phase 1-5), nach Phase 2 und nach Phase 4 je ein Zwischenstand mit Renders zur Abnahme.
* Nicht gewünscht: Gebäude-, Terminal-, Arena- oder Epilog-Umbau außerhalb dieses Auftrags, neue Features, neue Währungen, Balance-Änderungen, Fremdassets, Standard-Roblox-Texturen, Platzhalter-Decals, Terrain-Umbau.
* Am Ende: kurze Zusammenfassung (was gebaut, wo es liegt, Tris/Teile vor und nach, Annahmen, Asset-IDs, was offen ist).

--- KOPIEREN BIS HIER ---
