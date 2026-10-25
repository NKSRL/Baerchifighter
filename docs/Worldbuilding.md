# Worldbuilding – Wissensbasis (Grow a Baerchi Fighter)

**Version 1.3 · 25.10.2026** · Grundlage: Erstanalyse im laufenden Spiel (Playtest, 1 Spieler mit Welt 2 auf Slot 1) von Spieler-Plot, Brücke und Mitte. Nutzer dazu: „Es ist noch nicht perfekt, aber damit arbeiten wir erstmal.“ Der Ist-Stand ist also die Basis, nicht neu erfinden. Seit 1.2 steht das neue Kampf-Pit „Honig-Kolosseum“ (Schalter `PIT_V2`) drin: Maße in Abschnitt 2, Bauweise in Abschnitt 4. Seit 1.3 liegen alle Plots 1,5 Studs tiefer (`MapConfig.PLOT_SIZE.Y` 0,5 statt 2, „Plot tiefer“): Maße in Abschnitt 2 „Spieler-Plot“.

Diese Datei ist das Gedächtnis des Skills `roblox-worldbuilding`. Sie wird zu Beginn jedes Welt-Prompts gelesen und am Ende jedes Prompts nach der Fehleranalyse aktualisiert.

- **Quelle der Wahrheit:** Repo `docs/Worldbuilding.md`. **Spiegel:** Projekt-Dok `claude/Worldbuilding.md` (nach jeder Änderung 1:1 hochladen, MD5 gleich).
- **Einträge:** nie löschen. Behobenes als „behoben TT.MM.“ markieren, Überholtes als „(veraltet)“. Neue IDs fortlaufend: W = Befund in der Welt, M = Fehler in der Arbeitsweise, S = Prüf-Snippet.
- **Abschnitt 2 (Maße) ist maßgeblich.** Ältere Docs (Stilguide, Stilbibel) können veraltet sein (W12).

---

## 1. Projektkarte Welt (wer baut was)

**Die Welt entsteht zur Laufzeit.** Im Edit-Modus enthält `workspace` nur `TestPond`, `Terrain`, `Camera`. Messen und Fotografieren geht nur im Playtest (Server-DataModel), Code ändern nur im Edit-Modus.

**Edit-Vorschau (S7):** Die Start-Welt lässt sich mit dem aktuellen Studio-Code im Edit-Modus bauen: `WorldBuilder.buildPlatform` plus Tafeln und Wespennest wie in `MapService.init` (0,3 s, 5062 Teile, identisch zur Laufzeit). Ergebnis in `workspace.WB_Vorschau` mit `Archivable = false`: wird nicht gespeichert und nicht ins Play kopiert (Play-Test 25.10.: Server ohne `WB_Vorschau`, genau ein `Platform` mit 5062 Teilen). Nicht in der Vorschau: alles, was Spielstand braucht (`Plot_<slot>` mit Gebäuden, Außensteg, Arena, Raketen-Insel, Bärchis, Eier, Waben), und das Laufzeit-Licht (Atmosphäre, Bloom). Nach Code-Änderungen zeigt ein Neubau per `require` den alten Stand (M09).

| Bereich | Gebaut von (`ServerScriptService.Util.MapBuild.*`) | Ergebnis in `workspace` |
|---|---|---|
| Wasser, Hauptinsel, Plot-Inseln, Innenbrücken | `WorldBuilder.buildPlatform` (einmal beim Serverstart, aus `MapService.init`) | `Platform` (Model): `Water`, `Ground` + `GroundShore`, `PlotIsland_<n>` + `…Shore` |
| Rasen-Muster Hauptinsel | `HubPlazaBuilder.buildMainIslandMeadow` (auch bei `WorldBuilder.restyle`) | `Platform.Meadow_*` (lose Teile) |
| Plot-Insel-Boden (leere Inseln) | `HubPlazaBuilder.buildPlotIslandGround` | `Platform.PlotIslandDecor_<n>` (Folder, 107 Teile) |
| Innenbrücke Hub → Plot | `HubPlazaBuilder.buildArchedBridge` | `Platform.BridgeInner_<n>` + `BridgeInner_<n>_Plank_<i>`, `…Rail_*`, `…_WaterPier*` (164 lose Teile je Brücke) |
| Plaza / Event-Pit | `WorldBuilder.buildEventPit` → `HubPlazaBuilder.buildEventPitPlaza` | `Platform.EventPit` |
| Brunnen „Honigmast“ | `HubPlazaBuilder.buildSanctuaryFountain` | `Platform.Honigmast` |
| Bestenlisten-Tafeln | `WorldBuilder.buildLeaderboardBoard/LiveBoard` + `HubPlazaBuilder.decorateBoardPavilion` | `Platform.LeaderboardBoard_*`, `LiveBoard*` |
| Alleen, Laternen, Brückenportale, Bäume, Büsche, Felsen, Pilze, Rand-Deko | `ScenicBuilder.build` → `HubPlazaBuilder.buildAvenuePaths / buildBeekeeperLamp / buildBridgePortals`, `MapMeshes` | `Platform.Scenery` |
| Blumen, Wespennest, Fallback-Spawn | `WorldBuilder.buildFlowers / buildWaspNest` | `Platform.FlowerHead/FlowerStem`, `WaspNest`, `FallbackSpawn` |
| Spieler-Plot (pro Spieler) | `PlotBuilder` (Beet `Base`, Zaun, Schild-Tor `Sign*`, Gebäude) + `PondBuilder`, `RecyclerBuilder`, `IncubatorBuilder`, `TerminalBuilder` | `Plot_<slot>` |
| Außensteg Plot → Arena, Arena, Tower-Vitrine | `ArenaBuilder.buildBridge` (über `MapParts.buildSpan`), `buildPit`, `buildShowcase`; mit `PIT_V2` setzt `PitV2Builder` das Honig-Kolosseum (Vorlagen `ServerStorage.Assets.PitV2`, Daten `Config/PitV2Config`, Rechnung `Modules/PitV2Rules`) | `Plot_<slot>.Bridge`, `BridgeRail`, `Combat*`, `PitPlatform` (V2: `PitV2_Arena`, `PitV2_Kollision`, während eines Laufs `PitV2_TurmZaun`), `TowerShowcase` |
| Lauf-Turm in der Arena | `MapService.setPitTowerLevel` → `ArenaBuilder.buildTowerRing` (V2: Etagen-Zaun als Kind des Rings) und `ArenaBuilder.placeTowerFence` | `PitPlatform.Tower.Ring_<n>` |
| Raketen-Insel | `RocketIslandBuilder` (Schalter `ROCKET_ISLAND`) | `Plot_<slot>.RocketIsland_Root` |
| Welt-2-Look des Plots | `Welt2Builder.buildPlot` (Attribut `World2` am Plot + Schalter `WELT2_LOOK`) | `Plot_<slot>.World2Plot`, `World2Fusion` |

**Vorlagen:** `ServerStorage.Assets` (22 `Map_*`-MeshParts für Boden/Bäume/Büsche, `Welt2` mit 91 Teilen, `Map_BodenAlt_Vorlage`, seit 25.10. `PitV2` mit `Arena` (6 MeshParts) und `Stufe` (2 MeshParts)), `ReplicatedStorage.Assets` (Fountains, Recyclers, Eggs, Epilog*, EventUfoModel …). **Nicht importiert:** die im Stilguide beschriebenen `Hub_*.fbx` (Hub_Bruecke, Hub_Insel …) → `HubPlazaBuilder` läuft komplett im prozeduralen Fallback (`spawnMeshGroup` liefert nil).

**Welt-Schalter (`FeatureFlags`, Stand 25.10.):** `MAP_STYLE_V2 = true`, `MAP_GROUND_OLDSCHOOL = false`, `WELT2_LOOK = true`, `ROCKET_ISLAND = true`, `MAP_V2_MERCHANT/HOME/SHOWCASE/LIVE_BOARD/WASP_NEST = true`, `WORLD_C_HUB / WORLD_F_LIFE / WORLD_G_MOMENTS = true`, `PIT_V2 = true` (seit 25.10.). Die Schalter stehen in der Tabelle `FeatureFlags.FLAGS`, abgefragt über `FeatureFlags.isOn("NAME")` (in Studio Fehler bei unbekanntem Namen). Das Hub-Redesign (`HubPlazaBuilder`) hat **keinen** Schalter (W11).

**Namensverträge (Pflicht, sonst bricht Logik):** `EventPit.EventFloor` (kollidiert, CanQuery an), `EventRing`, `EventBannerAnchor.Banner`, `EventFence_*` und `EventCompassRay_*` (färbt `MapService.setEventPitTheme`), `Honigmast.Tropfen`, `BridgeInner_<n>`. Begehbare Brückenteile tragen „Bridge“ oder „Plank“ im Namen (CanCollide und CanQuery an); Geländer heißen „Rail“ oder „Fence“ (CanQuery aus, `DebugBridge` ignoriert sie). `BridgeCap` = Lichtanker für den DayCycleController. `Meadow_*` und `GrassTile` werden bei `restyle` gelöscht und neu gebaut. Die Arena-Fläche heißt `FightFloor` (WorldController-Prompt, AreaSignController). Im Ordner `PitPlatform.Tower` räumt `MapService.setPitTowerLevel` alles weg, was nicht `Ring_<n>` heißt: Zubehör einer Etage hängt deshalb als Kind am Ring. `PitPlatform.PitBannerAnchor.Banner.Enabled` = „Lauf läuft“ (ArenaLifeController), Attribute `TowerLevel`/`TowerTopY` liest das Turm-Flugfeld.

**Wer nutzt Boden- und Brückenhöhen (bei Änderungen mitprüfen):** `PlotRoutes` (Bärchi-Wege Plot ↔ Arena, eigene Bogenhöhe!), `DebugBridge` (prüft Wege gegen Planken), `FigureWalker` (setzt Wegpunkte ohne Bodenprüfung), `CombService` (Waben auf dem Plaza-Boden, R 8–44 laut `CombConfig`), `LaidEggBuilder` (gelegte Eier), Spawn-Punkte.

**Plot-Bodenhöhe = eine Zahl:** `MapConfig.PLOT_SIZE.Y` (über `MapParts.plotSurfaceOffset()`). Daran hängen Beet, Bordsteine, Treppe, Schild-Tor, Spawn, alle Gebäude, Bärchi-Figuren, `PlotRoutes.beetTop`, die Welt-2-Vorlage (`Welt2Builder.plotOrigin` = `PLOT_SIZE.Y − 0,65`), `Welt2Boden`, `Welt2Rampe`, `Welt2Builder.groundLift` (Recycler, Terminal) und auf dem Client `WorldShotController`, `WorldMomentController`, `PlotLifeController` (Stufen-Deko auf der Welt-2-Platte). Nicht mit: gelegte Eier (speichern ihre absolute Höhe, W22) und alles, was nur durch die alte Höhe verdeckt war (M18, S10).

**Configs:** `MapConfig` (Layout; 192/200 lokale Namen, dort keine neuen `local`), `MapStyleConfig` (Map_*-Meshes), `AmbienceConfig` (Licht, Lane-Farben, Portale, Laternen, Deko-Zahlen), `FeatureFlags`. Viele Maße und alle Hub-Farben stehen aber hart in `HubPlazaBuilder`, `PlotBuilder`, `Welt2Builder` (W04).

---

## 2. Raster und Maße (gemessen 25.10.2026)

### Welt-Raster
- Weltmitte `CENTER = (0, 0, 0)`, Laufhöhe `PLATFORM_TOP_Y = 0`.
- Hauptinsel: Zylinder R 120, Oberkante 0; Sandufer R 128, Oberkante −1 (`SHORE_WIDTH 8`, `SHORE_DROP 1`); Inselkörper 16 hoch.
- Wasser: Oberkante −2,6 (`WATER_DROP`), R 650, T 0,28; Meeresboden y −13,2.
- 8 Slots: Winkel a = (k − 1) · 45°, `outward = (cos a, 0, sin a)`, Plot-Mitte = outward · 212 (`PLOT_RING_RADIUS`). Slot 1 = +X, Slot 3 = +Z.
- Plot-Insel R 58, Ufer R 66 (Oberkante −1). Lücke Hauptinsel ↔ Plot-Insel 34 (`ISLAND_GAP`: Rand 120 → 154), ebenso Plot-Insel ↔ Arena (270 → 304).
- **Plot-lokal:** `MapParts.plotCFrame(slot)`, −Z = Richtung Hub, +Z = Richtung Arena. Slot 1: plot-lokal +Z = Welt +X, plot-lokal +X = Welt −Z.
- Punkte vom Slot-1-Rahmen auf Slot k drehen: x' = x · cos a − z · sin a, z' = x · sin a + z · cos a.

### Innenbrücke (Hub → Plot, `BridgeInner_<n>`)
- Von r 118 bis 156 (je 2 Studs Überlappung `BRIDGE_OVERLAP`), Länge 38, Breite 12 (`BRIDGE_WIDTH`), Planken 11,4 breit, 13 Planken à 0,55 dick.
- Bogen: Deck-Oberkante y = −0,05 + 1,35 · sin(π · t) mit t = (r − 118) / 38 → Scheitel y 1,30 bei r 137.
- Geländer: `Rail_Top` (kollidiert) bei ±6,35 vom Achsmittel, Handlauf-Oberkante ≈ Deck + 2,4; Pfosten an jeder 2. Planke; 2 × 2 Sandstein-Pfeiler im Wasser bei t 0,24 / 0,76 mit Gold-Ring und Schaumring; 2 Galgenlaternen am Scheitel (Seitenabstand 6,45).
- Portale (in `Scenery`): bei r 123 und 151, Seitenabstand 6,85; Sockel 2,1, Pfosten 1,5 × 5,8, Gold-Kragen, Kristall `BridgeCap` (Neon, Lane-Farbe, Oberkante y ≈ 9,3); am Hub-Ende zusätzlich `LaneCrossbar` + `LanePennant`.
- Teile je Brücke: 164 (Brücke) + 22 (Portale) = 186.
- Lane-Farben (`AmbienceConfig.LANE_COLORS`): 1 (255,200,60), 2 (255,115,95), 3 (255,130,195), 4 (185,130,255), 5 (100,195,255), 6 (80,225,200), 7 (130,225,95), 8 (255,155,70).

### Außensteg (Plot → Arena, `Plot_<slot>.Bridge`, alter Stil)
- Slot 1: Welt-x 268 bis 306, flach, Oberkante −0,05, Part 12 × 1,5 × 38 WoodPlanks (170,120,70).
- Geländer `BridgeRail` 1 × 3 × 38 bei ±6,5, WoodPlanks (140,95,55), kollidiert.
- Gold-Säule `CombatPost` + Neon-Kugel `CombatBrazier` bei r 273 / 301, roter `CombatPennant` (flacher Quader).
- Zur Raketen-Insel führt ein zweiter Steg im selben alten Stil.

### Kampf-Pit V2 „Honig-Kolosseum“ (Schalter `PIT_V2`, Slot 1, gebaut und gemessen 25.10.)
- **Rahmen:** Pit-Mitte Slot 1 (334, 0, 0). `PitV2Builder.pitFrame(slot)`: Ursprung = Arena-Mitte auf Kampfflächen-Oberkante, −Z zum Steg (Weltmitte), +X = `Vector3.yAxis:Cross(outward)`. Arena-Koordinaten wie im Blender-Prototyp (`tools/pit/pit_kolosseum_scene.py`): x quer, y längs (+ = Steg), Winkel 0 = +x, 90 = Steg. Für Slot 1 gilt Welt = (334 − y, h, −x).
- **Kampffläche:** `FightFloor` bleibt der Roblox-Zylinder R 26, Oberkante 0 (Kollision, Prompt), Farbe (247,236,212) = Fugen. Darauf Waben-Mesh: Sechsecke r 1,86 im Raster 2,0, bis R 22,95 angeschnitten, Oberkante 0,05; Medaillon r 4,7 (Schiefer 0,12, Goldring 0,16, Gold-Kern und Honig-Blüte bis 0,20); Goldring R 22,8–23,3 (0,10); Schieferband R 23,3–25,9 (0,05); Honigrinne (einziges Neon) R 25,7–26,6, −0,40 bis −0,20.
- **Sockel und Ufer:** `PitBase` R 30, Oberkante −0,35 (V2: (234,212,166) SmoothPlastic statt Slate); `PitBaseShore` R 38, −1,35. Altes Pit (Neon-`PitRing`, Emblem, 17 Neon-Pfosten, Holzbogen) wird mit `PIT_V2` nicht gebaut.
- **Mauer:** Schiefer R 28,1–29,1 bis 3,75; Sandstein-Krone R 27,9–29,3 bis **4,05 = Sitzhöhe der Zuschauer** (ArenaLifeController, Ring 28,6); Goldband innen 3,3–3,5; 24 Gold-Medaillons (r 0,8) alle 12° auf 1,9 Höhe.
- **Tribüne:** Stufen R 29,1–31,0 / 31,0–32,9 / 32,9–35,5 mit Oberkante 4,65 / 5,55 / 6,45; Schiefer-Brüstung bis 7,35, Goldkante bis 7,55; Fassade R 35,5 mit Pilastern (alle 12°) und Bogenfenstern; Abschlusswände an den Toren; zwei Ecktürme bei 0° und 180° (R 36,4, Dach bis 11,4, Wimpel bis 14,2).
- **Tore:** Halbwinkel 18° um Steg (90°) und Rakete (270°). Pfeiler 1,8 × 1,8 (Sockel 2,4) achsparallel bei (±8,84, ±27,2), bis 11,3 plus Mast mit Wimpel bis 13,8; lichte Weite 15,9 (Steg 12 + Geländer bis ±7). **Steg-Tor ohne Sturz** (Turmflug-Bahn, W15); Raketen-Tor mit Sturz y 8,0–9,0 (innen R 27,3) und Wappen bis 11,9.
- **Etagen-Zaun** (`Stufe`, Ursprung = Etagen-Oberkante): Sandstein-Sims R 25,5–27,1 von −0,4 bis +0,06; Gold-Geländer R 26,55–26,85 bis +1,68, Mittelholm +0,78–0,88, 32 Pfosten auf R 26,7. Außerhalb des Etagen-Zylinders (R 26), sonst verdeckt ihn die nächste Etage. Hängt als `PitV2_Etagenzaun` am `Ring_<n>`.
- **Kollision (unsichtbar, Meshes ohne Kollision):** 24 Blöcke Mauer + Tribüne (Band R 27,9–35,95, y −1,35 bis 7,55, 12 je Bogen, innen höchstens 0,15 vor der Krone), 6 Blöcke Pfeiler und Türme, Turm-Zaun `PitV2_TurmZaun` mit 16 Blöcken (R 26,5–27,1, 3 hoch) nur auf der obersten Etage, ohne Turm abgebaut, am gehaltenen Gipfel aus (dort auch kein Gold-Geländer auf der obersten Etage).
- **Teile:** `PitPlatform` 40 (vorher 29), je Etage 3 (vorher 1): 30 Etagen = 130 (Gipfel-Test 129). **Dreiecke:** Arena 16 024 (Sandstein 3188, Schiefer 3924, Gold 3380, Waben 4460, Honig 960, Wimpel 112), Etagen-Zaun 2112 je Etage; alle Slots teilen dieselben MeshIds.
- **Lauftests (S5):** Mitte → Mauer stoppt bei R 27,35; Steg → Mitte und Mitte → Raketen-Steg frei; Torecke stoppt an der Mauer.
- **Flugfeld (Client):** along −28 / quer −4,5, Scheibe Oberkante −0,15 – liegt zur Hälfte unter dem Steg-Ende (W17), Leuchtring R 2,86 passt zwischen die Torpfeiler.
- **Mesh-IDs (Upload 25.10.):** Pit_Sandstein 86362270339345, Pit_Schiefer 119518256664985, Pit_Gold 133908802766198, Pit_Waben 125916288366028, Pit_Honig 101671943504547, Pit_Wimpel 130560841318598, Pit_Stufe_Rand 80374957144288, Pit_Stufe_Gold 84539674493847.

### Mitte (Plaza „EventPit“ und Brunnen)
- `EventFloor`: Scheibe R 50, Oberkante **y 2,30** (= 0 + 0,3 Bodenabstand + 2,0 Bodenhöhe), Sandstone (238,223,192), kollidiert.
- `EventRing` R 51,6 (Gold-Metal, y 0,9–1,22); Boden-Discs `Plaza_*` / `EventCompass*` zwischen y 2,30 und 2,50.
- 8 Neon-Strahlen `EventCompassRay` (Event-Farbe) laufen vom Brunnen zum Zaun (Mittelpunkt bei r 27), Sektor-Waben `Plaza_SectorHexRing` bei r ≈ 35.
- Zaunring r 45,8–46: 24 Felder mit Wabenringen und Speerspitzen, 16 Obelisken (Schaft bis y 14,6, Edelsteine bis y 17,2), unsichtbare Barriere `PlazaFence_Barrier` bis y 15,8.
- 8 Freitreppen an den Alleen: r 47,3–51,6, 3 Stufen von y 0 auf 2,25, mit Wangen, Handläufen und Leucht-Edelsteinen.
- Brunnen `Honigmast`: Sockel-Ring R 7,75, Neon-Ströme bis R 8,5 (y ≈ 8, ohne Kollision), Lichtstrahl bis y 66. **Waben spawnen auf dem Plaza-Boden zwischen R 8 und 44 (`CombConfig.SPAWN_RADIUS_MIN/MAX`, gemessen r 10,5–43,9) → Brunnen-Fuß innerhalb R ≈ 7,6 halten, Fläche R 8–44 frei von Hindernissen.**

### Alleen (Hub, in `Scenery`)
- Von r 51,8 bis 117,8: Weg `Path` 11,2 breit (Sandstone, Oberkante 0,21), Bordsteine `PathCurb` bei ±5,55 (Oberkante 0,51) mit Goldleiste, 8 Schiefer-Platten `PathSlab` (9,2 breit) je Allee, Waben-Medaillons (`PathHexRing` aus 6 Balken + `PathHexCore` Neon) bei r 63–105.
- Imker-Laternen (je 12 Teile): Seitenabstand 7,5, bei r 72 und 100, beidseitig (4 je Allee, 32 gesamt).
- Rasen der Hauptinsel: konzentrische Discs `Meadow_*` (Oberkanten 0,008–0,040), 8 Sektor-Rasen mit weißen Sandstein-Linien, Waben-Medaillons bei R 63 und 107, Händler-Rondell Slot 2 bei R 66, Uferkranz (3 Segmente × 4 Teile je Sektor) und 8 Bastionen.

### Spieler-Plot
- **Welt 1 / leere Insel:** `PlotIslandDecor_<n>` = 10 Discs (inkl. Honig-Kern) + Mittel-Wabe, Weg `PlotMeadow_FreeWalk` 7,2 × 72, 2 Vorplätze 13,2 × 21 bei plot-lokal z ±46,8 (Schiefer-Platte, Bordsteine, Waben-Medaillon), Uferkranz 2 × 8 Segmente × 4 Teile (Lücke ±0,145 rad an den Brückenachsen).
- Beet `Base` 72 × 0,5 × 72, Oberkante y 0,5 (seit 25.10. „Plot tiefer“, vorher 2,0; in Welt 2 unsichtbar, kollidiert weiter); Bordstein bis 0,58, Ecksteine 0,83, Goldkante 0,46–0,60; **keine Treppe**, solange die Beet-Höhe ≤ 1 ist (vorher zwei Stufen 0,72 / 1,38, anteilig `PLOT_SIZE.Y` · 0,36 / 0,69); Schild-Tore `Sign*` bei plot-lokal z ±36 (Slot 1: Welt-x 176 / 248), Balken auf y 10,5–11,7, Schild bis y 16,4.
- **Welt 2 („Angeber“-Look, `World2Plot`, 27 Teile, Stand nach „Plot tiefer“, vorher alle Höhen +1,5):** unsichtbarer Boden `Welt2Boden` 108 × 0,5 × 108, Oberkante y 0,5 – ein **Quader**, Ecken bei R 76 (W21); sichtbare Platte **rund**: Boden `T0__W2_Floor` Scheibe R 54,4 (y −0,15–0,35, Farbe (62,54,82) Slate) + `Floor2` R 30 bis 0,5, Neonlinien `MagentaSoft` R 29–54,8 bis 0,56, Goldrand `T0__W2_Gold` R 54,8–58 (−0,15–0,55), Schürze `ObsidianDark` R 55–58 bis −6,15 (Vorlagen-Ursprung = Plot-Boden − 0,65, Schürze 6 darunter); Obelisken/Gold bis y 39,25; Kernstrahl `Strahl_Kern1` auf der Plot-Mitte (R 3,6, 48 hoch, y bis 44,85, Neon T 0,88); 12 Kristallstrahlen (R 0,9, 22 hoch); `Halo_Hex` (23 × 20) an der Arena-Seite. Geometrie per `EditableMesh` aus den Mesh-IDs gelesen (25.10.).
- Welt-2-Rampe `Welt2Rampe` (14 breit) **nur auf der Arena-Seite** (plot-lokal z 54 → 58, von 0,5 auf 0,08). Hub-Seite = 0,5-Kante (vorher 2): Innenbrücke ↔ Platte ohne Sprung (Lauftest 25.10. abends, S5 im Client). Die Stege enden innerhalb des Goldrands (Innenbrücke bei r 156 = R 56, Außensteg bei r 268 = R 56): sichtbare Stufe am Stegende jetzt 0,6 statt 2,1.
- Gebäude plot-lokal (Welt 2): Brunnen (0, −14), Inkubator (−33, 20), Fusionsmaschine (33, 20), Recycler (15, −47), Terminal (11, 45).
- Spawn `PlayerSpawn` (212, 1,0, 0) = Plot-Mitte (Slot 1, vorher 2,5); Figur steht bei y 3,34 (vorher 4,84); Startkamera (224, 9,5, 0) (nach „Plot tiefer“ nicht neu gemessen), blickt Richtung Hub.
- Insel unter der Welt-2-Platte (seit 25.10.): `PlotIslandDecor_<slot>` (107 Teile, Oberkanten bis 0,66) und Scenery-Teile mit Mitte im Inselradius (Randbüsche/-felsen, je Insel 9–10, Mitte R 55–57, bis 1,66 hoch) blendet jeder Client per `LocalTransparencyModifier` aus, solange die Platte steht (`PlotLifeController.setCovered`); leere und Welt-1-Inseln zeigen sie.
- Client-Stufen-Deko (`PlotLifeController`, Blumen/Pilze/Bienenhaus/Bernstein, `WorldFXConfig.ISLAND_STAGE_ITEMS`): Welt 1 auf der Insel bei R 53,5 (y 0, außerhalb der Beet-Ecke 50,9), Welt 2 auf dem Plattenboden bei R 52,5 (y 0,35 = Plot-Boden − 0,15), Ton in Ton in (62,54,82) Slate, ohne Neon (`ISLAND_STAGE.WELT2`). Höchste Teile: Bienenhaus 4,65, Bernstein 2,5, Pilze 2,4, Blumen 1,55.

### Teilezahlen (Playtest 25.10., Slot 1 mit Welt 2)
| Bereich | Teile |
|---|---|
| `Platform` gesamt | **5062** (5151 Instanzen) |
| Innenbrücken `BridgeInner_*` | 1312 (8 × 164, lose direkt in `Platform`) |
| Plaza `EventPit` | 1268 (Zaunring ≈ 700: Wabenringe 144, Speere 144, Stäbe 96 + 48 + 48, Zierleisten 32 …) |
| `Scenery` | 963 (Laternen 384, Wege-Waben 144, Portale 176, RimRock 40, RimBush 32, Büsche 25, Bäume 18, Felsen 13, Pilze 22, Platten 64 …) |
| `PlotIslandDecor_*` | 856 (8 × 107) |
| `Meadow_*` | ≈ 380 (Waben-Medaillons 195, Uferkranz 96, Bastionen 48 …) |
| `Honigmast` | 117 |
| Blumen | 92 |
| `Plot_1` | 292 (World2Plot 27, Inkubator 34, Raketen-Insel 32, Arena 29 …); Arena seit `PIT_V2` 40; seit „Plot tiefer“ ohne Treppe (−4) |

- Sechseck-Ringe aus je 6 Balken (`buildHexRingFlat`): 516 Teile in `Platform` + 144 auf den Plot-Inseln.
- Neon-Teile auf Hauptinsel und Innenbrücken: ≈ 250.
- `workspace.StreamingEnabled = false` → jeder Client lädt alles.
- Budgets: Projektregel ≤ 250 Teile pro Insel; Gebäude-Looks `MapConfig.LOOK_PART_BUDGET` = 40 / 40 / 70 / 70 / 110 / 110 (Look 1–6).

### Licht (Client, ClockTime 16,9)
Brightness 2,4 · Ambient (120,118,150) · OutdoorAmbient (150,150,185) · EnvironmentDiffuse 0,6 / Specular 0,5 · Atmosphere Density 0,3, Color (255,200,200), Decay (255,140,120), Glare 0,5, Haze 1,6 · Bloom 0,55 / Größe 20 / Schwelle 1,4 · ColorCorrection Sättigung 0,15, Kontrast 0,05 · SunRays 0,15 / 0,6. Werte aus `AmbienceConfig`; `MapConfig.LIGHTING_*` hat abweichende Werte (z. B. ClockTime 15,5, W04). **Im Edit-Modus:** ClockTime 16,9 und Brightness 2,4, aber ohne Sky, Atmosphere, Bloom und ColorCorrection (die entstehen erst zur Laufzeit) → die Edit-Vorschau wirkt klarer und kühler als im Spiel.

---

## 3. Stilbibel (Ist-Stand)

### Hub / Welt 1: „Royal-Honey-Sanktuarium“ (`HubPlazaBuilder`)
| Rolle | RGB | Material |
|---|---|---|
| Hauptstein Creme | (238,223,192) | Sandstone |
| Zierstein hell | (247,236,212) | Sandstone |
| Schiefer dunkel | (48,43,64) | Slate |
| Schiefer mittel | (76,70,96) | Slate |
| Königsgold | (242,188,64) | Metal |
| Antikgold | (196,142,42) | Metal |
| Honig-Leuchten | (255,196,56) | Neon |
| Kristall-Leuchten | (255,224,115) | Neon |
| Deckholz warm | (162,108,64), Wechsel (148,96,56) | WoodPlanks |
| Bauholz dunkel | (104,68,42) | Wood |
| Schaum | (248,250,255), T 0,3 | SmoothPlastic |
| Gras tief / mittel / sonnig | (62,140,62) / (72,152,68) / (84,164,76) | Grass |
| Ufersand | (234,212,166) | Sand |

**Abweichende Werte im selben Spiel (W04):** `PlotBuilder` Creme (238,224,192), hell (246,236,212), Gold (235,180,50), Honig (255,200,55), Holz (165,108,56), Gras (68,146,66) / (78,158,72) / (84,164,76); `MapConfig` GRASS_DARK (58,140,62), GRASS_LIGHT (92,178,82), PLOT_ISLAND_COLOR (70,152,70), SHORE_COLOR (238,214,158), BRIDGE_COLOR (170,120,70), WATER_COLOR (64,164,214).

### Welt 2: „Angeber“-Look (`Welt2Builder`, Meshes aus Blender)
Obsidian dunkel (SmoothPlastic), Schiefer-Boden, Gold (Metal), Neon in Honig, Magenta und Cyan; altes Beet (62,54,82) Slate bzw. (44,38,60); Lichtstrahlen (255,190,90) Neon T 0,88.

### Kampf-Pit V2 „Honig-Kolosseum“ (`PIT_V2`, 25.10.)
Royal-Honey-Palette aus dem Hub, als MeshParts (SmoothPlastic, Gold = Metal): Creme-Sandstein (238,223,192) für Krone, Tribüne, Sockel der Pfeiler und Sturz; Schiefer (48,43,64) für Mauer, Pfeiler, Brüstung, Pilaster, Fenster, Randband; Königsgold (242,188,64) für Ringe, Medaillons, Kragen, Masten; Waben (236,182,82) für den Boden; Honig-Neon (255,196,56) nur in der Rinne; Wimpel und Banner in der Lane-Farbe des Slots (`AmbienceConfig.LANE_COLORS`). Formsprache: Mauerring mit Medaillons, gestufte Tribüne, Pylonen-Tore mit Pyramidendach und Wimpel (echte Dreiecke statt flacher Quader), Waben-Intarsien. Beobachtung im Spiel-Licht: der Sandstein der Tribüne wirkt fast weiß (Bilder `docs/screens/pit_v2/2026-10-25/pitv2_01`, `_05`).

### Natur (`MAP_STYLE_V2`, Map-Stilbibel 20.10.)
Kantig, Flat-Shading, keine abstehenden Blattspitzen, Vertexfarben, Epilog-Insel als Formvorbild (wenige große Facetten, unten dunkel, oben hell). Bäume ≤ 320 Tris, Büsche ≤ 120, Bodenkachel ≤ 400.

### Formsprache (Stilguide, gilt weiter)
Gestufte Sockel (2–3 Stufen), gefaste Kanten, verjüngte Pfeiler/Obelisken mit Goldleisten, Waben-Intarsien; Höhenwechsel über eingefasste Treppen mit Wangen und Randsteinen; Neon nur als gezielter Akzent (Honig-Rinne, Waben-Kern, Kristall).

### Was funktioniert (behalten)
- Klare radiale Ordnung: Mitte → 8 Alleen → 8 Bogenbrücken → 8 Plot-Inseln; Lane-Farbe am Portal-Kristall gibt jedem Slot eine Erkennungsfarbe (Bilder 01, 02).
- Die Bogenbrücke liest sich gut: sanfter Bogen, Pfeiler mit Schaumring, Portale als Landmarken; der Laufblick vom Hub endet genau am Plot-Tor mit Name und Werten (Bilder 03, 04).
- Plaza als lesbarer Ring mit Freitreppen, Brunnen als Mittelpunkt (Bilder 02, 12, 13).
- Map_*-Bäume (low-poly, kantig) passen zur gewünschten Handschrift.

### Was schwach wirkt (Ansatzpunkte)
- Neon überall (Strahlen, Zaun-Kerne, Edelsteine, Laternen, Kristalle) → keine Hierarchie; ein Event färbt die ganze Mitte um (z. B. Cyan beim UFO-Event) (W08).
- Creme-Sandstein wirkt durch die Material-Textur grau-marmoriert, Plaza und Alleen wirken kühl (Bilder 02, 12).
- Weiße Rasenlinien und Ringe wirken wie Sportplatz-Markierungen; leere Plots sehen aus wie Spielfelder (Bilder 07, 10).
- Dunkle, schwere Bestenlisten-Tafeln mitten im Park (Bild 10).
- Wimpel als flache Quader (`LanePennant` 1,6 × 2,5 × 0,22, `CombatPennant`), keine Wimpelform (Bild 15).
- Außensteg und Raketen-Steg im alten Holzstil direkt hinter dem Plot (W03, Bild 08).
- Welt-2-Plot sehr dicht (39 Studs hohe Obelisken, 13 Strahlen, Magenta + Gelb + Cyan) und konkurriert mit der Mitte (Bild 05).
- Ufer: breiter, steiler Sandzylinder mit sichtbaren Facetten (Bilder 03, 11).

---

## 4. Baumuster (so wird hier gebaut)
- Plot-lokal bauen über `MapParts.plotCFrame(slot)`; Weltachsen über `MapParts.outwardDirection(slot)` und Seitenvektor `(-outward.Z, 0, outward.X)`.
- Deko-Teile: Anchored, CanCollide/CanQuery/CanTouch aus, CastShadow aus (`HubPlazaBuilder.makePart`, `PlotBuilder.addDecorPart`). Begehbares über wenige einfache, oft unsichtbare Collider (`EventFloor`, `Welt2Boden`, `Welt2Rampe`, `PlazaFence_Barrier`, unsichtbare Planken im FBX-Fall).
- Vorlage klonen mit Rückfall: `HubPlazaBuilder.spawnMeshGroup` (fehlt eine Vorlage → prozedural), `MapMeshes` (Map_*), `Welt2Builder.place/clone` (Attribut `tier` = additive Look-Stufe; Vorlage fehlt oder Schalter aus = alter Look, nie ein Fehler).
- Bögen über sin(π · t), t aus dem Radius; die Höhenformel braucht jeder, der darauf läuft (`HubPlazaBuilder.bridgeSurfaceY`, `PlotRoutes.innerBridgeY`) → nur eine Quelle (W05).
- Zustand per Attribut und billiges Update, Neubau nur bei Look-Wechsel (`Look`-Attribut am Gebäude).
- Deterministische Zufallsplatzierung mit festem Seed (`SCENERY_SEED`, `FLOWER_SEED`), Alleen werden per `WorldBuilder.isOnBridgeLane` frei gehalten (Prüfung 25.10.: 242 Deko-Teile, keine auf Alleen oder Plaza).
- **Mesh-Bauwerk über Roblox-Kern** (Vorbild `PitV2Builder`): funktionale Roblox-Teile mit Namensvertrag behalten (`FightFloor`, `PitBase`), die Optik als wenige MeshParts je Material ohne Kollision darüberlegen; Kollision als unsichtbare Blöcke aus einer reinen Rechen-Datei (`PitV2Rules.arcBlocks`: Bogenband als gerade Blöcke, innen um den Kosinus des halben Stückwinkels tiefer, mit Test); Vorlagen in `ServerStorage.Assets.<Name>` mit Pivot im lokalen Ursprung; Einfärben nach Teilname aus der Config (Studio verwirft FBX-Farben); Schalter aus oder Vorlage fehlt = altes Bauwerk.
- **Hohlräume ohne Kollision einschließen:** Ist ein Mesh nicht begehbar (Tribüne), füllt EIN unsichtbarer Block je Stück den ganzen Körper bis zur Oberkante. Sonst fällt man (z. B. vom Turm) hinein und steckt zwischen Wänden fest.
- **Gestapelte Etagen:** Außenteile (Geländer, Sims) außerhalb des Stapel-Radius, sonst verdeckt sie die nächste Etage; Zubehör als Kind des Etagen-Teils, damit das vorhandene Aufräumen es mitnimmt; EIN mitwandernder Kollisionsring für die oberste Etage statt Kollision an jeder Etage; Sonderfall gehaltener Gipfel (eigenes Geländer, Brücke) ausnehmen.
- **Bewegungsbahnen vor dem Modellieren nachrechnen:** Flugbahnen, Laufwege und Kamerafahrten mit den echten Config-Zahlen gegen neue Querbalken, Dächer und Brüstungen prüfen (Turmflug `WorldFXConfig.TOWER_FLIGHT`: steigt so steil, dass jeder Sturz über dem Flugfeld je nach Turmhöhe durchflogen wird → Steg-Tor ohne Sturz).
- **Bodenhöhe als eine Zahl:** Alles auf dem Plot hängt an `PLOT_SIZE.Y`. Abgeleitete Maße (Treppe) anteilig rechnen, sodass der alte Wert exakt die alte Geometrie ergibt – dann ist die Zahl selbst der Rückweg und es braucht keinen Schalter. Vor dem Ändern die Durchstich-Suche (S10) für Server- und Client-Deko.
- **Verdecken statt löschen (Client):** Was ein Look komplett überdeckt und sonst durchsticht (Insel-Deko unter der Welt-2-Platte), blendet der Client im vorhandenen Belegungs-Lebenszyklus aus (`PlotLifeController.setOccupied` → `setCovered`, `LocalTransparencyModifier` 1/0). Kein Server-Zustand und keine Abbau-Ereignisse (beim Zerstören eines Plots laufen deferred Events zu spät oder gar nicht, ein Rennen mit dem Neubau). Spätere Attribut-Wechsel (`World2`) über `GetAttributeChangedSignal` am Plot, die Verbindung endet mit dem Plot; nach jedem Warten den Zustand neu prüfen.

---

## 5. Fehlerliste

### 5a. Befunde in der Welt (W)
| ID | Symptom | Ursache | Regel | Status / Beleg |
|---|---|---|---|---|
| W01 | `Platform` hat 5062 Teile; eine Innenbrücke 186, eine Laterne 12, ein Sechseck-Ring 6 Teile (660 Ring-Balken gesamt); StreamingEnabled aus | Ornamente prozedural aus Einzelteilen; Hub_*.fbx nie importiert | Vor dem Bauen ein Teilebudget je Bauwerk festlegen, nach dem Bau zählen (S2). Wiederholte Ornamente (Wabenring, Laterne, Pfosten, Brückensegment) als EIN MeshPart je Material aus Blender, dazu wenige unsichtbare Collider. Projektregel ≤ 250 Teile pro Insel | offen · S2, 25.10. |
| W02 | Konzentrische Discs mit Deckflächen 0,002–0,015 Studs übereinander auf riesigen Flächen (`Meadow_*`, `PlotMeadow_*`, Beet-`StepStone_*` in 0,01-Schritten, `Plaza_*` 2,30–2,50); Scanner: 676 Paare in 98 Gruppen. In drei flachen Standbildern kein Flimmern sichtbar | Muster durch Übereinanderlegen statt Ausschneiden | Sichtbare Deckflächen ≥ 0,02 Studs Abstand, für Flächen, die man aus > 100 Studs sieht, ≥ 0,05. Besser: Ringe als echte Ring-Meshes oder eine Fläche mit Vertexfarben. Nach jedem Boden-Umbau S4 laufen lassen | offen (Risiko, Flimmern nicht bestätigt) · S4, Bilder 09–11 |
| W03 | Zwei Brückenstile am selben Plot: Innenbrücke Royal-Honey-Bogen, Außensteg und Raketen-Steg flach im alten Holzstil | Redesign hat nur `buildArchedBridge` umgestellt; `ArenaBuilder.buildBridge` nutzt weiter `MapParts.buildSpan` | Gleiche Funktion = ein Baustein. Bei Stilwechsel alle Aufrufer suchen (`script_grep` nach `buildSpan`, „Bridge“) und gemeinsam umstellen | offen · Bilder 05, 08 |
| W04 | Farben und Licht mehrfach und abweichend: Palette in `HubPlazaBuilder` ≠ `PlotBuilder` ≠ `MapConfig`; Licht in `MapConfig.LIGHTING_*` und `AmbienceConfig`; Positionen hart in Buildern (`HubPlazaBuilder` 1586 Zeilen, `Welt2Builder`) | Redesign aus anderem Chat/Werkzeug ohne Config-Disziplin | Eine Palette in Config und nur daraus lesen (neue Datei nur bei echtem Bedarf); neue Maße und Positionen nur in Config; vor jeder Farbwahl Abschnitt 3 lesen | offen · Code 25.10. |
| W05 | Bogenhöhe der Innenbrücke doppelt: `HubPlazaBuilder.BRIDGE_ARCH_HEIGHT = 1.35` und `PlotRoutes.INNER_BRIDGE_ARCH_H = 1.35` | getrennte Konstanten | Geometrie, von der Wege oder Collider abhängen (Bogen, Deckhöhe, Plattenkante), nur an einer Stelle (MapConfig); nach Änderung `DebugBridge` laufen lassen | offen · Code 25.10. |
| W06 | Bärchi-Wege kennen den Welt-2-Boden nicht: `PlotRoutes` legt Wegpunkte auf y 0 bei plot-lokal z ±37,6 (alte Beetkante 36 + 1,6), der Welt-2-Boden liegt aber bis z ±54 auf y 2,0 → rechnerisch laufen Bärchis dort ~2 Studs im Boden | Welt 2 hat die begehbare Fläche vergrößert, `PlotRoutes` rechnet mit `PLOT_SIZE`; `FigureWalker` prüft keinen Boden | Jede Änderung an Bodenhöhe oder -größe gegen alle Verbraucher prüfen (Liste in Abschnitt 1). Erst im Kampf beobachten, dann beheben | Verdacht (rechnerisch, im Spiel nicht beobachtet) · 25.10. abends: seit „Plot tiefer“ liegen die Wegpunkte zwischen Beet-Kante und Plattenrand nur noch 0,35–0,5 unter dem Welt-2-Boden |
| W07 | Spawn liegt im Lichtstrahl: `Strahl_Kern1` (Neon, R 3,6, bis y 46) steht genau auf `PlayerSpawn` (212, 2,5, 0); die Startkamera schaut durch die Säule Richtung Hub | Plot-Mitte doppelt belegt (Spawn und Deko-Mittelpunkt) | Spawn-Punkt und Sichtachse Startkamera → Hub/Plot-Tor frei halten; neue Deko immer auch aus der echten Startkamera fotografieren | offen · Bild 16 |
| W08 | ≈ 250 Neon-Teile auf Hauptinsel und Innenbrücken (Plaza 104, Laternen 32, Portal-Kristalle 32, Wege-Kerne 24, Rasen-Kerne 15, Brücken-Laternen 16, Brunnen 18, Bastionen 8), Bloom 0,55 → alles leuchtet | an jedem Bauteil ein Leuchtakzent | Neon nur für Ziel, Interaktion und Orientierung (Portal-Kristall in Lane-Farbe, Brunnen-Kern, Event-Ring), sonst Gold-Metal; höchstens ein Leuchtakzent pro Bauwerk; Tag und Nacht prüfen | offen · Bilder 02, 12, 13 |
| W09 | Verdeckte Altteile: bei Welt-2-Plots liegen 87 von 107 Teilen der `PlotIslandDecor` unter der Platte; `PlotCurb*` (24) und `Base` bleiben unsichtbar im Plot | Welt 2 überlagert statt ersetzt (Logik-Teile sollen bleiben) | Rein dekorative Teile, die ein Look komplett verdeckt, gar nicht bauen; Logik-Teile (Collider, Anker) dürfen unsichtbar bleiben | offen · S2 · teilweise behoben 25.10. abends: der Client blendet die Insel-Deko unter der Welt-2-Platte aus (W20, „Plot tiefer“), auf dem Server bleiben die Teile |
| W10 | Gelegte Eier außerhalb der Welt: 4 alte Eier in `Plot_1.LaidEggs` bei (124,7 / −26,2 / −1,1), (126,1 / −26,2 / −1,5), (146,5 / −18,5 / −2,4) unter Wasser an der Innenbrücke und bei (582,7 / 128 / −1,4) in der Luft | nicht untersucht (vermutlich gelegt, während das Bärchi auf der Brücke oder im Epilog war) | Alles, was in der Welt abgelegt wird, auf begehbaren Boden des eigenen Plots setzen (Raycast, Rückfall Plot-Mitte); bei jeder Analyse Bounding-Boxen auf Ausreißer prüfen | offen · Messung 25.10. |
| W11 | Hub-Redesign ohne Schalter und ohne Backup; Studio ≠ Repo bei 7 Welt-Skripten (`HubPlazaBuilder` im Repo untracked und anders, `PlotBuilder`, `WorldBuilder`, `ScenicBuilder`, `PlotRoutes`, `MapService`, `FeatureFlags`); gleich: `MapParts`, `MapMeshes`, `Welt2Builder`, `ArenaBuilder`, `MapConfig`, `MapStyleConfig` | Arbeit aus einem anderen Werkzeug direkt in Studio und Repo ohne Abgleich | Vor jeder Weltänderung Hash-Abgleich Studio ↔ Repo (S1) für alle betroffenen Skripte. Bei Abweichung erst klären, welcher Stand gilt (Studio = laufendes Spiel), nie blind überschreiben. Umbauten hinter Schalter und mit Backup. **Nutzer 25.10.: Das Repo ist veraltet, nichts aus dem Repo nach Studio holen** | offen · S1, 25.10. (Welt-Skripte in Studio seitdem unverändert, Hash-Vergleich 25.10. abends). Pit V2 (25.10.): gleiche Anker-Edits in Studio und Repo; `ArenaBuilder`, `ArenaLifeController` und die neuen `PitV2*`-Dateien per Hash gleich, `MapService` und `FeatureFlags` weiter verschieden (nur die neuen Zeilen gleich) |
| W12 | Doku veraltet: Stilguide nennt Plaza-Oberkante 1,28 (gemessen 2,30) und einen FBX-Schnellpfad, dessen Vorlagen nie importiert wurden | Doku nach Umbau nicht nachgezogen | Maße messen statt aus Doku übernehmen; Abschnitt 2 hier ist maßgeblich und wird nach jeder Messung korrigiert | offen |
| W13 | Bauteile durchdringen sich: Portal-Pfosten (6,85 ± 0,75) und Scheitel-Laternenpfosten (6,45 ± 0,39) stehen im Geländer (6,35 ± 0,275); Portal-Sockel auf Deckhöhe über dem Sand (rechnerisch ~1,5 Studs Luft, Ufer-Oberkante −1) | Seitenabstände unabhängig geschätzt | Seitenabstände aus einer Formel ableiten (Deck-Halbbreite + Geländerbreite + Luft); Sockel auf den echten Boden darunter setzen; Durchdringung per Bounding-Box prüfen (S3) | offen · Bilder 14, 15 |
| W14 | Wege ins Leere: leere Plots haben auf der Arena-Seite einen Vorplatz mit Medaillon, der am Wasser endet (Außensteg gibt es nur mit Besitzer) | Vorplätze unabhängig vom Steg gebaut | Jeder Weg endet an einem Ziel; Vorplätze und Portale nur dort, wo ein Steg anschließt, sonst als Aussichtspunkt gestalten | offen · Bild 07 |
| W15 | Doppelter Torbogen am Arena-Eingang (Server `ArchPost/ArchBeam/ArchCrest` bei r 28,5, Client `ArenaArch` aus ArenaLifeController bei r 28,6), beide Balken (8–12 Studs) genau über der Turmflug-Bahn vom Flugfeld | Client-Paket baute einen zweiten Bogen, ohne nach dem Server-Bogen zu suchen; Flugbahn nie gegen Geometrie gerechnet | Vor neuer Deko an Eingängen nach vorhandener Deko suchen (Server UND Client, `script_grep` nach dem Bauteil-Namen); Bauteile über Bahnen gegen die Bahn rechnen (Abschnitt 4) | behoben 25.10. (`PIT_V2`: kein Server-Bogen, Client-Bogen aus, Steg-Tor ohne Sturz) |
| W16 | Turmflug fliegt bei hohen Türmen durch die Etagen (Etage 30: ≈ 0,3 s innerhalb R 26 unter der Spitze) | `TowerFlightController` bewegt x/z linear, y ballistisch: der Charakter ist früh über der Turmfläche, aber noch tief | Bahnen gegen Hindernisse rechnen; Lösungsidee: waagerechte Bewegung verzögern (k² statt k), erst steigen, dann nach innen | offen (bestehend, nicht verändert) |
| W17 | Flugfeld liegt zur Hälfte unter dem Steg-Ende (Steg-Deck −0,05 bis along −28, Feld-Oberkante −0,15) | Feld und Steg unabhängig platziert | Bodenmarken nie unter eine andere begehbare Fläche legen; Höhe aus der Fläche darunter ableiten | offen (bestehend) |
| W18 | Etagen-Simse (R 25,5–27,1) stehen auf Etage 1–2 in Brusthöhe über dem Sockelring zwischen Turm und Mauer; wer bei stehendem Turm dicht am Turm läuft, steckt kurz im Sims | Außen-Geländer braucht Platz außerhalb des Turms (Abschnitt 4) | Außenanbauten an wachsenden Bauten gegen Laufwege darunter prüfen; bei Bedarf Durchgang sperren oder Sims schmaler | offen (Randfall, bewusst in Kauf genommen 25.10.) |
| W19 | Welt-2-Platte stand an allen Seiten 2 Studs über Insel und Stegen (Goldrand bis 2,05, darunter dunkle Schürze); Nutzer: „steht hoch ab, auf allen Seiten“ | Plot-Bodenhöhe `PLOT_SIZE.Y = 2` aus der Welt-1-Beet-Zeit, Welt-2-Vorlage auf diese Höhe gesetzt | Plattform-Höhen gegen die Umgebung (Insel 0, Stege −0,05) aus dem Spielerblick prüfen; die Plot-Bodenhöhe nur über `PLOT_SIZE.Y` ändern | behoben 25.10. (`PLOT_SIZE.Y` 0,5, alles auf dem Plot −1,50 gemessen; Bilder `plot_tiefer` 00 → 24, 06, 05) |
| W20 | Client-Stufen-Deko (R 53,5, y 0) stand bei Welt-2-Plots unter der Platte: Pilze (2,4), Bernstein (2,5), Bienenhaus (4,65) stachen schon durch den Boden (2,0), nach dem Absenken auch die Blumen | `PlotLifeController` kannte Welt 2 nicht (W09-Muster auf dem Client) | Client-Deko in die Durchstich-Suche nehmen (M18); Deko eines Looks auf dessen Boden setzen | behoben 25.10. (auf der Platte bei R 52,5, Ton in Ton; Bild `plot_tiefer` 25) |
| W21 | `Welt2Boden` ist ein Quader 108 × 108, die sichtbare Platte rund (R 58): an den Diagonalen trägt der unsichtbare Boden bis R 76 über Sand und Wasser (begehbare Luft, jetzt auf 0,5) | Collider als Block statt in der Form der Platte | Collider-Form = sichtbare Form (hier Zylinder R 58); jede unsichtbare Lauffläche einmal am Rand ablaufen | offen (bestehend, rechnerisch, nicht abgelaufen) |
| W22 | Gelegte Eier schweben nach dem Absenken 1,5 Studs über dem Boden, bis sie eingesammelt sind | `Types.LaidEgg` speichert die Fußhöhe relativ zum Plot-Ursprung, nicht zum Boden | Bei Änderungen der Bodenhöhe gespeicherte Positionen mitdenken; Höhen künftig relativ zum Boden speichern oder beim Bauen auf den Boden setzen | offen, vorübergehend (per Touched sammelbar, neue Eier liegen richtig) |

### 5b. Fehler in der Arbeitsweise (M)
| ID | Symptom | Ursache | Regel |
|---|---|---|---|
| M01 | FNV-Hash in Luau lieferte für identische Dateien andere Werte als Python | `h * 16777619` überschreitet 2^53, Luau rechnet mit Double | Split-Multiplikation `(h * 403 + bit32.lshift(h, 24)) % 2^32` (S1); Hash-Vergleich immer an einer bekannt gleichen Datei gegenprüfen |
| M02 | Brunnen-Lichtstrahl ergab „Radius 26“ | Ausdehnung über `Size.X/Z` gerechnet, Teil steht senkrecht | Ausdehnung und Radien immer aus den 8 Ecken über `CFrame:PointToWorldSpace` (S3) |
| M03 | Client-`execute_luau` brach ab: „cannot read 'Technology' (lacking capability RobloxScript)“ | geschützte Eigenschaft gelesen | Geschützte Eigenschaften weglassen oder in `pcall` lesen |
| M04 | Playtest endete mitten in der Messung (Fehler „Server datamodel is not available in Edit mode“); kurz danach lief ein neuer Playtest (Fehler „Edit datamodel is not available in Play mode“) | Der Nutzer startet und stoppt Play selbst, während Claude arbeitet | Messungen in kurze, unabhängige Aufrufe teilen; Ergebnisse sofort notieren; bei Modus-Fehler `get_studio_state`, nicht blind neu starten oder stoppen. Läuft sein Playtest: nur Server lesen, keine Client-Aufrufe (Kamera, vgl. VFX-Skill F39), vor dem Stoppen fragen |
| M05 | Schleife über `require(FeatureFlags)` fand 0 Schalter | Die Schalter stehen in der Untertabelle `FeatureFlags.FLAGS`, das Modul selbst hat nur `FLAGS` und `isOn` | Schalter über `FeatureFlags.FLAGS` bzw. `FeatureFlags.isOn("NAME")` lesen |
| M06 | Übersichtsbild aus ~450 Studs ganz pink | Atmosphäre (Density 0,3, Haze 1,6) färbt die Ferne | Farben und Materialien aus 20–80 Studs beurteilen; Fernbilder nur für das Layout |
| M07 | Z-Fighting im Standbild nicht erkennbar | Flimmern zeigt sich erst in Bewegung | Kandidaten über den Scanner (S4); Sichtprüfung mit zwei leicht versetzten Aufnahmen oder im Live-Playtest |
| M08 | HUD verdeckt das erste Bild | ScreenGuis aktiv | Vor Aufnahmen ScreenGuis (außer Freecam) und die eigene Figur ausblenden (S6) |
| M09 | `require` im MCP lieferte nach einer Quelltext-Änderung weiter die alte Fassung (Wegwerf-Modul: v = 1, nach Änderung auf v = 2 weiter v = 1); auch `WorldBuilder` blieb zwischen zwei Aufrufen im Cache | Alle `execute_luau`-Aufrufe laufen in derselben Plugin-VM, `require` merkt sich jedes ModuleScript | Edit-Vorschau nach Code-Änderungen nicht per `require` neu bauen, sonst zeigt sie den alten Stand. Vorher per S1 prüfen, ob sich Welt-Skripte geändert haben; dann frische Module laden (Loader per `loadstring`, noch zu bauen und zu testen) oder Studio neu starten |
| M10 | Zwei Aufnahmen „im Edit-Modus“ zeigten HUD, Eier und Waben | Der Nutzer hatte zwischen Vorschau-Bau und Aufnahme Play gestartet; `screen_capture` zeigt den aktuellen Viewport | Direkt vor jeder Aufnahme `get_studio_state`; Bilder mit HUD stammen aus Play |
| M11 | Nach `device_commit_files` hatten zwei JPGs eine andere MD5 (je +5771 Bytes) | Beim Übertragen kam ein C2PA-Block hinzu (APP11-Segment „c2pa“ hinter dem JFIF-Kopf); die Bilddaten sind gleich (Dateiende identisch) | MD5-Vergleich nach dem Commit nur für Textdateien; Bilder über Größe minus APP11-Segment oder das Dateiende prüfen |
| M12 | Nach dem 3D-Import lag der Steg (Blender +Y) in Studio auf +Z statt −Z | Der Roblox-3D-Import dreht das FBX um 180° um die Hochachse (Größen und Höhen stimmen) | Jeder Export braucht ein asymmetrisches Merkmal; nach dem Import die Teil-Mittelpunkte relativ zum Pivot mit dem Manifest vergleichen; ausgleichen über den Pivot der Vorlage (`WorldPivot * CFrame.Angles(0, π, 0)`), nicht neu exportieren (S8) |
| M13 | `CollisionFidelity = Box` per Befehl zeigte beim sofortigen Zurücklesen noch `Default` | Studio berechnet die Kollisionsgeometrie verzögert | Nach dem Setzen kurz warten und erneut lesen |
| M14 | Lade-Test per MCP brach mit „Unbekannter Schalter: PIT_V2“ ab, obwohl der Schalter eingetragen war | `FeatureFlags` lag noch alt im require-Cache der Plugin-VM (M09); in Studio wirft `isOn` bei unbekanntem Namen | Neue Schalter nicht per MCP-`require` prüfen, sondern im Playtest (frische VM); Module für Lade-Tests als Klon neben das Original legen und danach löschen |
| M15 | `D:Invoke("fight", uid)` simulierte den Lauf, aber die Arena blieb leer; der zweite Versuch zeigte den Turm erst, als die Aufnahme schon zu spät kam | Die Wiedergabe braucht die Figur des Bärchis auf dem Plot (nur das ausgerüstete hat eine); Läufe dauern nur wenige Stages | `snapshot` → `equipbear uid` → `fight uid` (in `task.spawn`) → `TowerLevel` abfragen und direkt danach aufnehmen → am Ende `restore` (S9) |
| M16 | Klick ins Studio scheiterte: „The desktop shell is frontmost“; im schmalen Fenster fehlte „Importieren“ im Menüband | Studio war nicht im Vordergrund und nicht maximiert; `computer_open_application` würde leere Studio-Fenster öffnen | Zusätzlich „File Explorer“ (nur Klick) freigeben, die Studio-Titelleiste anklicken, maximieren; Dateipfad ins Dateiname-Feld tippen, Return per Taste; mehrere Dateien als `"a.fbx" "b.fbx"` |
| M17 | Lauftest per Server (`hrp.CFrame`, `hum:MoveTo`) im eigenen Playtest lief seitlich weg (z 0 → 14), sprang und endete am falschen Ort; derselbe Test im Client lief sauber | Die Spielfigur gehört physikalisch dem Client, Server-Teleport und -MoveTo werden überschrieben (am Vormittag hatte es zufällig geklappt) | Lauftests (S5) im Client-DataModel des eigenen Playtests; während eines Playtests des Nutzers keine Client-Aufrufe (M04) |
| M18 | Eine Zahl (`PLOT_SIZE.Y`) hätte gereicht – aber was die alte Platte verdeckt hatte, wäre durchgestochen (Insel-Deko 107 Teile bis 0,66, Randbüsche/-felsen bis 1,66, Client-Stufen-Deko bis 4,65) | „Verdeckt“ hing an der alten Höhe; Server- und Client-Deko liegen in verschiedenen Modulen | Vor jeder Höhen- oder Größenänderung einer Fläche alles in ihrer Grundfläche suchen, dessen Oberkante über der neuen Höhe liegt (S10 auf dem Server, Client-Configs und -Controller per Suche nach Radius/Höhe), und mit dem Nutzer entscheiden: ausblenden, versetzen oder weniger tief |

---

## 6. Prüfwerkzeuge (Snippets, getestet)

**S1 · Hash Studio ↔ Repo** (Edit-Modus bzw. `device_bash` im Repo). Gleiche Werte = gleiche Datei (CRLF wird normalisiert).
```lua
local function fnv(s: string): (string, number)
	s = s:gsub("\r\n", "\n")
	local h = 2166136261
	for i = 1, #s do
		h = bit32.bxor(h, s:byte(i))
		h = (h * 403 + bit32.lshift(h, 24)) % 4294967296 -- nie h * 16777619 (M01)
	end
	return string.format("%08x", h), #s
end
return fnv(game.ServerScriptService.Util.MapBuild.WorldBuilder.Source)
```
```python
def fnv(b):
    b = b.replace(b"\r\n", b"\n"); h = 2166136261
    for c in b:
        h ^= c; h = (h * 16777619) % 4294967296
    return "%08x" % h, len(b)
# fnv(open("src/server/Util/MapBuild/WorldBuilder.luau", "rb").read())
```

**S2 · Teile je Namensgruppe zählen** (Server im Playtest, z. B. `workspace.Platform`, `workspace.Plot_1`).
```lua
local function zaehle(root: Instance): string
	local g = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			local k = d.Name:gsub("_%d+.*$", ""):gsub("%d+$", "")
			g[k] = (g[k] or 0) + 1
		end
	end
	local a = {}
	for k, n in g do table.insert(a, { k = k, n = n }) end
	table.sort(a, function(x, y) return x.n > y.n end)
	local out = {}
	for i, e in a do if i <= 40 then table.insert(out, string.format("%5d %s", e.n, e.k)) end end
	return table.concat(out, "\n")
end
```

**S3 · Ausdehnung aus den Ecken** (statt `Size`, M02).
```lua
local function aabb(root: Instance): (Vector3?, Vector3?)
	local lo, hi
	local list = if root:IsA("BasePart") then { root } else root:GetDescendants()
	for _, d in list do
		if d:IsA("BasePart") then
			local cf, s = d.CFrame, d.Size
			for _, x in { -1, 1 } do for _, y in { -1, 1 } do for _, z in { -1, 1 } do
				local p = cf:PointToWorldSpace(Vector3.new(x * s.X / 2, y * s.Y / 2, z * s.Z / 2))
				lo = if lo then lo:Min(p) else p
				hi = if hi then hi:Max(p) else p
			end end end
		end
	end
	return lo, hi
end
```

**S4 · Z-Fighting-Scanner** (Server im Playtest). Meldet waagerechte Deckflächen (Part-Blöcke und stehende Zylinder), die sich überlappen und weniger als 0,015 Studs Höhenunterschied haben, sortiert nach Fläche.
```lua
local function zfight(roots: { Instance }, maxRows: number): string
	local items = {}
	for _, root in roots do
		for _, d in root:GetDescendants() do
			if d.ClassName == "Part" and (d :: Part).Transparency < 0.95 then
				local part = d :: Part
				local cf, s = part.CFrame, part.Size
				if part.Shape == Enum.PartType.Cylinder and math.abs(cf.RightVector.Y) > 0.999 then
					local r = math.min(s.Y, s.Z) * 0.5
					table.insert(items, { p = part, top = cf.Position.Y + s.X * 0.5, x = cf.Position.X, z = cf.Position.Z, hx = r, hz = r })
				elseif part.Shape == Enum.PartType.Block and math.abs(cf.UpVector.Y) > 0.999 and s.X * s.Z >= 1 then
					local rv, lv = cf.RightVector, cf.LookVector
					table.insert(items, { p = part, top = cf.Position.Y + s.Y * 0.5, x = cf.Position.X, z = cf.Position.Z,
						hx = math.abs(rv.X) * s.X * 0.5 + math.abs(lv.X) * s.Z * 0.5,
						hz = math.abs(rv.Z) * s.X * 0.5 + math.abs(lv.Z) * s.Z * 0.5 })
				end
			end
		end
	end
	local buckets = {}
	for i, it in items do
		local b = math.floor(it.top / 0.02)
		buckets[b] = buckets[b] or {}
		table.insert(buckets[b], i)
	end
	local stats = {}
	for b, list in buckets do
		local cand = table.clone(list)
		for _, j in buckets[b + 1] or {} do table.insert(cand, j) end
		for _, i in list do
			local a = items[i]
			for _, j in cand do
				local c = items[j]
				if j ~= i and not (j < i and math.floor(c.top / 0.02) == b) then
					local dy = math.abs(a.top - c.top)
					if dy < 0.015 and (a.p.Color ~= c.p.Color or a.p.Material ~= c.p.Material) then
						local ox = math.min(a.x + a.hx, c.x + c.hx) - math.max(a.x - a.hx, c.x - c.hx)
						local oz = math.min(a.z + a.hz, c.z + c.hz) - math.max(a.z - a.hz, c.z - c.hz)
						if ox > 0.05 and oz > 0.05 and ox * oz > 0.5 then
							local key = string.format("%s <> %s dy=%.3f", a.p.Name:gsub("%d+", "#"), c.p.Name:gsub("%d+", "#"), dy)
							local st = stats[key] or { n = 0, area = 0, y = a.top }
							st.n += 1; st.area += ox * oz
							stats[key] = st
						end
					end
				end
			end
		end
		task.wait()
	end
	local arr = {}
	for k, st in stats do table.insert(arr, { k = k, st = st }) end
	table.sort(arr, function(x, y) return x.st.area > y.st.area end)
	local out = { string.format("Flaechen=%d Gruppen=%d", #items, #arr) }
	for i, e in arr do
		if i > maxRows then break end
		table.insert(out, string.format("%4dx Flaeche=%8.1f y=%.3f  %s", e.st.n, e.st.area, e.st.y, e.k))
	end
	return table.concat(out, "\n")
end
-- return zfight({ workspace.Platform, workspace.Plot_1 }, 45)
```

**S5 · Lauftest** (im **Client**-DataModel des eigenen Playtests, M17; R15 ohne Sprung). Ziel erreicht, wenn die Endposition in x/z nahe am Ziel liegt. Nicht während eines Playtests des Nutzers (M04).
```lua
local plr = game.Players.LocalPlayer
local hum = plr.Character:FindFirstChildOfClass("Humanoid")
local hrp = plr.Character:FindFirstChild("HumanoidRootPart")
local function lauf(von: Vector3, nach: Vector3, sek: number): Vector3
	hrp.CFrame = CFrame.new(von)
	task.wait(1)
	hum:MoveTo(nach)
	local t = os.clock()
	while os.clock() - t < sek do task.wait(0.1) end
	return hrp.Position
end
local ende = lauf(Vector3.new(148, 4, 0), Vector3.new(185, 2, 0), 5) -- Slot 1: Innenbrücke → Welt-2-Platte
hrp.CFrame = CFrame.new(212, 5, 0) -- zurück zum Spawn
return ende
```
Getestete Übergänge (25.10., alle ohne Sprung erreicht): Innenbrücke → Welt-2-Platte (2-Stud-Kante), Platte → Außensteg (Rampe), Außensteg → Platte. 25.10. abends nach „Plot tiefer“ (Client): Innenbrücke ↔ Platte (0,5-Kante), Platte → Außensteg (Rampe 0,5 → 0,08).

**S6 · Aufnahme vorbereiten** (Client im Playtest).
```lua
local lp = game.Players.LocalPlayer
for _, g in lp.PlayerGui:GetChildren() do
	if g:IsA("ScreenGui") and g.Enabled and g.Name ~= "Freecam" then
		g:SetAttribute("WB_Hidden", true)
		g.Enabled = false
	end
end
if lp.Character then
	for _, d in lp.Character:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then d.LocalTransparencyModifier = 1 end
	end
end
-- Rückweg (ungetestet): alle ScreenGuis mit Attribut WB_Hidden wieder einschalten, Attribut entfernen, LocalTransparencyModifier = 0
```

**S7 · Edit-Vorschau der Insel** (Edit-Modus). Baut die Start-Welt mit dem aktuellen Studio-Code in `workspace.WB_Vorschau` (nicht gespeichert, nicht im Play). Achtung M09: nach Code-Änderungen zeigt `require` den alten Stand.
```lua
local SSS, RS = game.ServerScriptService, game.ReplicatedStorage
if workspace:FindFirstChild("Platform") then return "ABBRUCH: workspace.Platform existiert schon" end
local old = workspace:FindFirstChild("WB_Vorschau")
if old then
	if old.Archivable then return "ABBRUCH: WB_Vorschau ist speicherbar, nicht von uns" end
	old:Destroy()
end
local WorldBuilder = require(SSS.Util.MapBuild.WorldBuilder)
local MapLayout = require(RS.Modules.MapLayout)
local FeatureFlags = require(RS.Config.FeatureFlags)
WorldBuilder.buildPlatform() -- wie MapService.init; buildGlobalLighting NICHT aufrufen (änderte das gespeicherte Lighting)
local platform = workspace:FindFirstChild("Platform") :: Model
platform.Archivable = false
for _, b in MapLayout.leaderboardBoards() do
	WorldBuilder.buildLeaderboardBoard(platform, b.angleDegrees, if b.listId then "LeaderboardBoard_" .. b.listId else "LeaderboardBoard")
end
if FeatureFlags.isOn("MAP_V2_LIVE_BOARD") then WorldBuilder.buildLiveBoard(platform) end
if FeatureFlags.isOn("MAP_V2_WASP_NEST") then WorldBuilder.buildWaspNest(platform, MapLayout.waspNestCenter()) end
local folder = Instance.new("Folder")
folder.Name = "WB_Vorschau"
folder.Archivable = false -- nicht speichern, nicht ins Play kopieren
folder.Parent = workspace
platform.Parent = folder
return "ok"
```
Prüfen: `folder:Clone()` liefert nil; im Playtest (Server) gibt es kein `WB_Vorschau`. Entfernen: `workspace.WB_Vorschau:Destroy()`.

**S8 · Vorlage nach dem 3D-Import einrichten** (Edit-Modus). Der Import („Importieren“ im Start-Tab, Warteschlange „Import starten“) legt je FBX ein Model in `workspace` ab, Pivot = FBX-Ursprung, Meshes sind sofort hochgeladen. Getestet 25.10. mit `Pit_Kolosseum`/`Pit_Stufe`.
```lua
local src = workspace:FindFirstChild("Pit_Kolosseum") :: Model
local assets = game.ServerStorage.Assets
local folder = assets:FindFirstChild("PitV2") or Instance.new("Folder")
folder.Name = "PitV2"
folder.Parent = assets
-- Kontrolle M12: Mittelpunkt eines asymmetrischen Teils relativ zum Pivot gegen das Manifest
local p = src:GetPivot().Position
local w = src:FindFirstChild("Pit_Waben") :: BasePart
print("Waben relativ:", w.Position - p) -- Manifest (0, 5.375, 1.176): Z-Vorzeichen gedreht = 180°-Import
src.WorldPivot = CFrame.new(p) * CFrame.Angles(0, math.pi, 0) -- danach zeigt -Z des Pivots zum Steg
for _, d in src:GetDescendants() do
	if d:IsA("MeshPart") then
		d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch = true, false, false, false
		d.CollisionFidelity = Enum.CollisionFidelity.Box -- verzoegert, nachpruefen (M13)
	end
end
src.Name = "Arena"
src.Parent = folder
```

**S9 · Turm-Test über die Debug-Befehle** (Server im Playtest). Schützt den Spielstand mit `snapshot`/`restore` (M15).
```lua
local D = game.ServerScriptService.RBLDebug
local uid = "<uid eines starken Baerchis>" -- D:Invoke("list")
D:Invoke("snapshot")
D:Invoke("equipbear", uid)
task.spawn(function() D:Invoke("fight", uid) end)
local pit = workspace.Plot_1.PitPlatform
local t0 = os.clock()
while os.clock() - t0 < 50 do
	task.wait(0.5)
	local lv = pit:GetAttribute("TowerLevel")
	if typeof(lv) == "number" and lv >= 2 then break end
end
return pit:GetAttribute("TowerLevel") -- jetzt sofort screen_capture
-- Gipfel (gehaltener Turm, 30 Etagen): D:Invoke("epilog", "summit") / D:Invoke("epilog", "summitoff")
-- Zum Schluss: D:Invoke("restore")
```

**S10 · Durchstich-Suche** (Server im Playtest; vor jeder Höhen- oder Größenänderung einer Fläche, M18). Listet sichtbare Teile, deren Box einen Kreis um die Mitte berührt und über eine Schwelle ragt. Getestet 25.10. (Slot 1, R 58,5, Schwelle 0,30: PlotIslandDecor 56 Teile, RimBush 4, RimRock 5, Brücken-Geländer). Client-Deko extra prüfen (Configs/Controller, z. B. `WorldFXConfig.ISLAND_STAGE`).
```lua
local function durchstich(root: Instance, mitte: Vector3, r: number, schwelle: number): string
	local groups = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local cf, s = d.CFrame, d.Size
			local lo, hi
			for _, x in { -1, 1 } do for _, y in { -1, 1 } do for _, z in { -1, 1 } do
				local p = cf:PointToWorldSpace(Vector3.new(x * s.X / 2, y * s.Y / 2, z * s.Z / 2))
				lo = if lo then lo:Min(p) else p
				hi = if hi then hi:Max(p) else p
			end end end
			local nx, nz = math.clamp(mitte.X, lo.X, hi.X), math.clamp(mitte.Z, lo.Z, hi.Z)
			if math.sqrt((nx - mitte.X) ^ 2 + (nz - mitte.Z) ^ 2) <= r and hi.Y > schwelle then
				local key = d.Parent.Name .. "/" .. d.Name:gsub("%d+", "#")
				local g = groups[key] or { n = 0, top = -1e9 }
				g.n += 1; g.top = math.max(g.top, hi.Y)
				groups[key] = g
			end
		end
	end
	local out = {}
	for k, g in groups do table.insert(out, string.format("%-44s n=%3d oben<=%.2f", k, g.n, g.top)) end
	table.sort(out)
	return table.concat(out, "\n")
end
-- return durchstich(workspace.Platform, Vector3.new(212, 0, 0), 58.5, 0.30) -- Slot 1
```

**S11 · Welt-1-Test-Plot auf einem leeren Slot** (Server im Playtest). Für Bilder eines Welt-1-Beets, wenn der eigene Plot Welt 2 ist. Platzhalter-Besitzer statt echtem Spieler: RespawnLocation und Heim-Deko des Spielers bleiben unberührt, der Client zeigt die Insel als belegt und nach dem Entfernen wieder als frei. Getestet 25.10. (Slot 2, 117 Teile, Kamera 26/27).
```lua
if workspace:FindFirstChild("Plot_2") then return "Slot belegt" end
local PlotBuilder = require(game.ServerScriptService.Util.MapBuild.PlotBuilder)
local fake = { UserId = 0, DisplayName = "Welt-1-Test", Name = "Welt1Test", RespawnLocation = nil }
local model = PlotBuilder.buildPlotBase(2, fake :: any)
model:SetAttribute("WB_Test", true)
-- ... Aufnahmen, danach aufraeumen:
-- local p = workspace:FindFirstChild("Plot_2"); if p and p:GetAttribute("WB_Test") then p:Destroy() end
```

---

## 7. Kamera-Set für Vorher/Nachher (Slot 1)
`screen_capture` mit `camera_position` → `look_at_position`. Für andere Slots die Punkte drehen (Abschnitt 2). Referenzbilder des Ist-Stands: Repo `docs/screens/worldbuilding/2026-10-25/` (Nummer = Bild).

| Nr. | Kennung | Kamera | Blick auf | Zweck |
|---|---|---|---|---|
| 01 | WB_Uebersicht | (0, 380, 330) | (0, 0, 20) | Layout (Farben unbrauchbar, M06; hier noch mit HUD) |
| 02 | WB_Mitte | (0, 48, 82) | (0, 3, 0) | Plaza, Alleen, Tafeln |
| 03 | WB_Bruecke_Seite | (137, 9, 36) | (137, 0.5, 0) | Bogen, Pfeiler, Ufer |
| 04 | WB_Bruecke_Lauf | (104, 7, 0) | (160, 2, 0) | Laufblick Hub → Plot |
| 05 | WB_Plot_Oben | (150, 95, 95) | (214, 4, 0) | Plot gesamt, Außensteg, Arena |
| 06 | WB_Plot_Brueckenkopf | (146, 6.5, 14) | (170, 2, −4) | Plattenkante, Tor, Anschluss |
| 07 | WB_Plot_Leer_Slot2 | (95, 60, 175) | (150, 1, 150) | leerer Plot |
| 08 | WB_Aussensteg_Arena | (278, 14, 34) | (300, 1, 0) | Außensteg, Arena |
| 09 | WB_Flach_Slot2 | (70, 7, 245) | (150, 0, 150) | Schichtstapel aus der Ferne |
| 10 | WB_Allee_Flach | (−20, 6, −118) | (30, 0, −40) | Allee, Rasen, Tafeln |
| 11 | WB_Plotrand_Fern | (−60, 4, −260) | (−20, 0, −80) | Plot-Rand, Ufer |
| 12 | WB_Mitte_Brunnen_nah | (22, 10, 30) | (0, 6, 0) | Brunnen |
| 13 | WB_Mitte_Zaun_Treppe | (62, 9, 14) | (44, 2, 0) | Zaun, Freitreppe |
| 14 | WB_Bruecke_Scheitel | (131, 5.5, −2) | (138, 3, 6.5) | Geländer, Scheitel-Laterne |
| 15 | WB_Bruecke_Hubkopf | (128, 4, 10) | (116, 1, 2) | Portal, Anschluss Hub |
| 16 | WB_Spawn_Startblick | (224, 9.5, 0) | (150, 3, 0) | echte Startkamera |
| 17 | WB_Edit_Mitte | (0, 48, 82) | (0, 3, 0) | Edit-Vorschau (S7), Mitte ohne Laufzeit-Licht |
| 18 | WB_Edit_Uebersicht | (0, 300, 260) | (0, 0, 20) | Edit-Vorschau (S7), ganze Insel, alle Plots leer |
| 19 | PitV2_Gesamt | (258, 44, −50) | (337, 0, 0) | Kolosseum von schräg oben (Steg-Seite) |
| 20 | PitV2_Steg | (276, 8.5, 0) | (334, 3.5, 0) | Einlauf über den Außensteg, Steg-Tor |
| 21 | PitV2_Innen | (315, 6.5, 15) | (352, 4, −5) | Kampffläche, Mauer, Zuschauer, Raketen-Tor |
| 22 | PitV2_Turm | (290, 22, −40) | (334, 6, 0) | Lauf-Turm mit Etagen-Zaun (während eines Laufs, S9) |
| 23 | PitV2_Gipfelturm | (232, 52, −82) | (334, 34, 0) | gehaltener Turm mit Gipfel (30 Etagen) |
| 24 | PlotTiefer_Steg_Nutzerblick | (288, 3.4, 0) | (250, 2.6, 0) | Außensteg → Plattenkante (Blick des Nutzers 25.10.) |
| 25 | PlotTiefer_Rand_Deko | (196, 9, 76) | (210, 1, 50) | Plattenrand von der Seite, Stufen-Deko auf der Platte |
| 26 | PlotTiefer_Welt1_Eingang_Slot2 | (101.8, 5, 116) | (124.5, 0.5, 124.5) | Welt-1-Beet am Hub-Eingang (Test-Plot S11) |
| 27 | PlotTiefer_Welt1_Slot2_Oben | (95, 60, 175) | (150, 1, 150) | Welt-1-Beet von oben (wie 07, Test-Plot S11) |

Bilder des Kolosseums: Repo `docs/screens/pit_v2/2026-10-25/` (`pitv2_01_aussensteg_arena` = Kamera 08 nach dem Umbau, `_02` = 19, `_03` = 20, `_04` = 21, `_05`/`_06` = 22, `_07`/`_08` = 23 und Gipfel von oben); Blender-Renders in `assets/pit/renders/`.

Bilder „Plot tiefer“: Repo `docs/screens/plot_tiefer/2026-10-25/` (`00_vorher_nutzerblick_steg` = Bild des Nutzers vorher, `05`/`06` = Kamera 05/06 nachher, Vergleich mit `worldbuilding/2026-10-25/05`, `06`; `24`–`27` = Kamera 24–27).

---

## 8. Offene Baustellen (Vorschlag, priorisiert)
1. **W07** Spawn aus dem Kernstrahl (Strahl versetzen oder schmaler/aus der Sichtachse) – klein, sofort sichtbar.
2. **W21** `Welt2Boden` in der Form der Platte (Zylinder R 58) statt Quader – klein, beseitigt begehbare Luft an den Diagonalen.
3. **W06** im Kampf prüfen, ob Bärchis im Welt-2-Boden laufen (seit „Plot tiefer“ höchstens 0,5 tief, wohl kaum sichtbar); dann `PlotRoutes` Welt-2-fähig machen.
4. **W03** Außensteg und Raketen-Steg im Stil der Innenbrücke (ein gemeinsamer Brücken-Baustein).
5. **W01** Teilebudget: Hub-Ornamente (Wabenring, Laterne, Brückensegment, Zaunfeld) als Blender-Meshes; Ziel `Platform` deutlich unter 5000.
6. **W08** Neon-Hierarchie in der Mitte.
7. **W02** Schichtstapel durch Ring-Meshes oder Flächen ersetzen.
8. **W04 / W05** Palette und Brückengeometrie zentral in Config.
9. **W09** verdeckte Deko bei Welt-2-Plots nicht bauen.
10. **W10** Eier-Ablage auf begehbaren Boden klemmen.
11. **W11** Studio ↔ Repo zusammenführen (vor allem `HubPlazaBuilder`); bis dahin gilt Studio, nichts aus dem Repo holen.
12. **M09** Loader für frische Module bauen, damit die Edit-Vorschau (S7) Welt-Änderungen sofort zeigt, ohne Studio neu zu starten.
13. **Kolosseum-Nacharbeit:** Sandstein der Tribüne wirkt im Spiel fast weiß (Ton absenken? Nutzer fragen); Mobil-Test (16 024 Dreiecke je Arena plus 2112 je Etage); Außensteg wirkt neben dem Kolosseum jetzt noch älter (W03).
14. **W16 / W17** Turmflug-Bahn (erst steigen, dann nach innen) und Flugfeld neben statt unter dem Steg-Ende – eigener kleiner Schalter im TowerFlightController.
15. **W18** Durchgang zwischen Turm und Mauer bei stehendem Turm sperren oder Etagen-Sims schmaler, falls Spieler dort laufen.
16. **W22** Eier-Höhe relativ zum Boden speichern oder beim Bauen auf den Boden setzen (nur wichtig, falls die Bodenhöhe noch einmal geändert wird).

---

## 9. Nutzer-Vorlieben (Welt)
- Handschrift: kantig, Flat-Shading, keine abstehenden Blattspitzen; Epilog-Insel als Qualitäts- und Formvorbild („handgemachtes Spielzeug-Diorama“); warme Palette aus Honiggelb, Wiesengrün, Blattgrün, Sandbeige, kleine Kristall-Akzente.
- Hub-Stil „Royal-Honey“ (Creme-Sandstein, Schiefer, Gold, Holz, Honig-Waben) ist gesetzt.
- Ablauf: erst Blender-Prototyp und Abstimmung, dann FBX-Import, dann Verdrahtung; 1 Blender-Einheit = 1 Stud.
- Nichts löschen, immer Backup; kein Rojo; der Nutzer speichert selbst (erinnern).
- 25.10.: Ist-Stand von Plot, Brücke und Mitte ist die Arbeitsbasis.
- 25.10.: Will die Insel im Edit-Modus sehen (Edit-Vorschau S7). Das Repo ist gerade veraltet: nichts aus dem Repo nach Studio holen, Studio ist die Quelle.
- Startet und stoppt Play auch selbst, während Claude arbeitet; Play beendet er lieber selbst (vorher fragen). 25.10. abends auf Nachfrage: „Du darfst stoppen“ (gilt nicht automatisch für später, weiter fragen).
- 25.10.: Neues Kampf-Pit als „Honig-Kolosseum“ (Mauer, Tribünen, Tore, Waben-Boden), Zaun an **jeder** Turm-Etage, Kollision gegen Herunterfallen. Abnahme über Blender-Renders vor jedem Einbau; die dunklen Abschlusswände am Steg-Eingang sollen so bleiben.
- 25.10. abends: Plot fast bündig gewünscht (1,5 Studs tiefer gewählt, Empfehlung war 1), für alle Plots gleich; Deko auf der Welt-2-Platte Ton in Ton in der Farbe des Plattenbodens. Abnahme: „du hast das Plot vernünftig tiefergelegt, ich bin zufrieden“.

---

## 10. Changelog
- **1.3 · 25.10.2026** – „Plot tiefer“ (`PLOT_SIZE.Y` 2 → 0,5, alle Plots): Maße Spieler-Plot und Welt-2-Platte neu (Abschnitt 1 „Plot-Bodenhöhe = eine Zahl“, Abschnitt 2), zwei neue Baumuster (Bodenhöhe als eine Zahl, Verdecken per Client); neu W19 (Platte stand hoch ab, behoben), W20 (Client-Stufen-Deko stach durch, behoben), W21 (Quader-Collider, begehbare Luft), W22 (gespeicherte Eier-Höhe); W06/W09 aktualisiert; neu M17 (Lauftest im Client), M18 (Durchstich-Suche vor Höhenänderungen); S5 auf Client umgestellt, neu S10 (Durchstich-Suche), S11 (Welt-1-Test-Plot); Kamera 24–27; Baustellen und Vorlieben ergänzt.
- **1.2 · 25.10.2026** – Kampf-Pit V2 „Honig-Kolosseum“ gebaut (Blender → FBX → Studio, Schalter `PIT_V2`): Maße, Kollision, Teile, Dreiecke und Mesh-IDs in Abschnitt 2, Palette in 3, vier neue Baumuster in 4 (Mesh über Roblox-Kern, Hohlräume einschließen, gestapelte Etagen, Bahnen nachrechnen); neu W15 (doppelter Torbogen in der Flugbahn, behoben), W16–W18 (Turmflug, Flugfeld, Sims über dem Sockelring); neu M12 (3D-Import dreht 180°), M13 (CollisionFidelity verzögert), M14 (neuer Schalter im require-Cache), M15 (Lauf-Test braucht ausgerüstetes Bärchi), M16 (Studio-Fenster für den Import); neu S8 (Vorlage nach dem Import), S9 (Turm-Test mit snapshot/restore); Kamera 19–23; Projektkarte, Namensverträge, Baustellen und Vorlieben ergänzt.
- **1.1 · 25.10.2026** – Edit-Vorschau der Insel gebaut und belegt (S7: `WB_Vorschau`, Archivable = false, 5062 Teile wie zur Laufzeit, im Play nicht vorhanden); Edit-Licht notiert; M05 präzisiert; neu M09 (require-Cache hält alte Fassung), M10 (Modus direkt vor Aufnahmen prüfen) und M11 (C2PA-Block in übertragenen JPGs); W11 um Nutzer-Aussage ergänzt; Vorlieben und Baustellen ergänzt; Edit-Referenzbilder 17 und 18.
- **1.0 · 25.10.2026** – Erstanalyse im Playtest (Slot 1, Welt 2): Projektkarte, Maße, Teilezahlen, Licht, Stilbibel, Baumuster, 14 Welt-Befunde (W01–W14), 8 Methodik-Fehler (M01–M08), 6 getestete Snippets (S1–S6), Kamera-Set mit 16 Referenzbildern.
