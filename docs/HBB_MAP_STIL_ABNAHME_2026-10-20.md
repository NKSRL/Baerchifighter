# Map-Stil V2 ("Epilog-Insel-Stil"): Abnahme (Phase 1-5), 2026-10-20

Stand: Code fertig, Meshes gebaut und in Blender geprueft. **In Studio noch nichts importiert und nichts gesehen.** Schalter `MAP_STYLE_V2` ist AUS; ohne importierte Vorlagen baut jeder Builder wie bisher die alten Primitive.

## Was gebaut ist
| Datei (assets/map/) | Inhalt | Dreiecke je Teil |
|---|---|---|
| `Map_Boden.fbx` | Wiese A/B (24x24), Ufer gerade, Ufer Ecke, Randfels A/B, Kristall tuerkis/flieder | 120/120, 60, 30, 80/80, 90/90 |
| `Map_Baeume.fbx` | Baum A rund, B hoch, C doppelte Krone, D jung, Stumpf, Blumengruppe | 168, 148, 168, 141, 95, 160 |
| `Map_Buesche.fbx` | Busch A-E, Randbusch A/B, Gras A/B | 100, 120, 100, 100, 100, 80, 60, 42, 48 |
| `Map_Assets.blend` | Quell-Objekte; Neuaufbau per `tools/map_assets/build_map_*.py` | |

Stil: kantig (Flat-Shading), stark verbeulte Klumpen, Vertexfarben (Attribut `Col`) mit Verlauf unten dunkel/oben hell, keine Textur. **Auf Wunsch (20.10.) keine abstehenden Blattspitzen**; die Spitzen-/Blatt-Varianten liegen als `tools/map_assets/*_spitzen_v2.py` bzw. per `LEAVES_ON` in `map_common.py`. Renders: `docs/map_stilbibel/`. Alle Budgets (Kachel 400, Baum 320, Busch 120) eingehalten.

## Was der Code tut (Schalter `FeatureFlags.MAP_STYLE_V2`, Standard AUS)
- `Config/MapStyleConfig` (neu): Seed, Variantenlisten, +-12 % Groesse, Tris-Tabelle, Budgets, Farbtoenung, Kristall-Akzent jeder 4. Fels, Asset-IDs (leer).
- `Modules/MapStyleRules` (neu, rein, getestet): Kachelvariante, Variantenwahl, Skalierung, Mittelpunkt-Versatz.
- `Util/MapBuild/MapMeshes` (neu): klont Vorlagen `Map_*` (ServerStorage.Assets bevorzugt, sonst ReplicatedStorage.Assets; rekursive Suche nach MeshPart-Name), setzt Anchored, CanCollide/CanQuery/CanTouch aus, CastShadow aus, SmoothPlastic, Attribute `MapStyle=2`, `MapTemplate`.
- `MapParts.newGrassTile`: Mesh-Kachel (Variante A/B nach Rasterfeld, gleiche Masse und Mitte wie der alte Block, Unterkante 0,02 ueber der Scheibe). Kollision bleibt bei `Ground`/`PlotIsland`.
- `ScenicBuilder`: Baeume (3 Teile -> 1 MeshPart), Buesche, Felsen, Plot-Randbuesche/-felsen. **Positionen identisch zu vorher**: die alten Zufallsziehungen laufen in gleicher Reihenfolge weiter, Variante/Drehung/Groesse kommen aus eigenen Stroemen (`MapStyleConfig.SEED`). Fehlt eine Vorlage -> altes Primitiv.
- Debug (Studio): `D:Invoke("mapstyle", "on" | "off" | "info")`. `on/off` baut Bodenkacheln der Hauptinsel und die Vegetation neu (der Ordner `Scenery` bleibt, die Client-Controller halten ihn). `info` liefert Teile gesamt, Mesh-Teile, Mesh-Dreiecke, Deko je Name, fehlende Vorlagen. Plot-Beete wechseln beim naechsten Plot-Aufbau (Rebirth/Reset).

## Teile/Dreiecke vor und nach (Soll, wenn alle Vorlagen da sind)
| | vorher | nachher |
|---|---|---|
| Baeume (Stamm+Krone+Spitze) | 54 Teile | 18 MeshParts |
| Buesche / Randbuesche | 25 / 32 | 25 / 32 |
| Felsen / Randfelsen | 13 / 40 | 13 / 40 (+ ca. 3 Kristall-Neonteile) |
| Bodenkacheln | 38 | 38 |
| Teile gesamt Workspace (mit einem Plot) | 1094 | ca. 1061 |
| Dreiecke der Mesh-Teile | (Primitive, nicht zaehlbar) | siehe `mapstyle info` (Baeume 18 x ca. 155, Buesche 25 x ca. 100, Rand 32 x ca. 70, Kacheln 38 x 120, Felsen 53 x 80 -> ca. 17 000) |
Die echten Zahlen bitte nach dem Import mit `mapstyle info` ablesen und hier eintragen.

## Pruefungen (Cloud/Linux-VM)
- `luau-compile --null` fuer alle geaenderten Dateien: ok. Neuer Test `map_style.test.lua`: ALLE OK (Varianten, Budgets, Schalter aus, Rechenregeln).
- Tests combat_rating, gold_rules, map_layout, live_board, event_schedule, egg_press, honey_pond, shop, endless, ui_texts, epilog_island, epilog_state, guide_steps, boss_tiers: 0 FAIL. `unlock_rules`: 1 FAIL (schon vorher offen).
- `check_decor` sauber, `check_loc` konsistent, `check_locals` MapConfig weiter 192/200 (nicht angefasst). `check_members/consistency/ui/feedback` rot wie vorher, **keine Treffer in meinen Dateien**.
- Studio-Abgleich: Quelltext-Pruefsummen von FeatureFlags, MapParts, ScenicBuilder, WorldBuilder, DebugService in Studio sind **identisch mit dem Repo-Stand HEAD** (vor meinen Aenderungen), die Update-Datei ueberschreibt also nichts Neueres.
- Zeilenenden: MapParts/ScenicBuilder/WorldBuilder sind CRLF und bleiben CRLF (Diff nur die echten Aenderungen).

## Studio-Playbook "In Studio pruefen"
Einspielen (nie Rojo): Datei -> Aus Datei importieren -> `updates/HBBUpdate_MapStil_2026-10-20.rbxmx`, dann Inhalt von `updates/HBBUpdate_MapStil_2026-10-20_Befehl.lua` in die Befehlsleiste. Strg+Z macht es rueckgaengig.
Meshes (einmalig, 3D-Import geht nur per Dialog): Asset Manager -> Bulk Import, die drei FBX aus `assets/map/` (Materialien ignorieren, Importmassstab 1). Aus jedem Ergebnis die MeshParts `Map_*` in `ServerStorage.Assets` legen (Ordner anlegen, falls er fehlt; ReplicatedStorage.Assets geht auch). An jeder Vorlage `CollisionFidelity = Box` setzen. Falls die Teile weiss/grau erscheinen (Vertexfarben ignoriert): am Assets-Ordner Attribut `MapFarbenAusConfig = true` setzen, dann kommen die Farben aus den alten Configs.
Test: Play, Befehlsleiste (Server): `game.ServerScriptService.RBLDebug:Invoke("mapstyle", "info")` -> `fehlendeVorlagen` muss leer sein; dann `"on"` und `"off"` im Wechsel: Hub, Plot, Arena-Rand ansehen. Pruefen: Boden-Hoehe (kein Einsinken, kein Schweben), Baeume/Buesche stehen auf dem Boden, Laufwege/Kamera unveraendert, Tag/Nacht, Mobile-Ansicht (Emulator), `parts` und `mapstyle info` vor/nach. Rebirth danach: keine Reste (`dekoProName` bleibt gleich). Erst nach deiner Abnahme `MAP_STYLE_V2 = true` in `FeatureFlags` setzen.

## Annahmen / offen
- **Nicht in Studio gesehen.** Offen: Achsen/Ausrichtung nach dem Import (FBX mit Vorne -Z, Oben Y exportiert), Vertexfarben-Uebernahme, Massstab.
- A1: Kristall tuerkis/flieder statt Epilog-Magenta, A2: Facetten statt weicher Blobs (Wunsch 20.10.), A3: Vorlagen unter `ServerStorage.Assets` (neu).
- **Nicht eingebaut** (Meshes gebaut, Platzierung offen): Ufer gerade/Ecke (Ufer bleibt `GroundShore`), Stumpf, Blumengruppe, Grasbueschel. Kleine Baeume auf den Plots: im Code nicht gefunden (nur Randbuesche/-felsen). Keine neuen Instanzen ausser den Kristall-Neonteilen.
- Bounding-Box-Mitte in X/Z wird ignoert (nur Hoehe ausgeglichen): schiefe Staemme sitzen bis ca. 0,6 Studs neben dem Platz.
- Studio-Vorher/Nachher-Screenshots, Asset-Upload und Asset-IDs fehlen noch (Auftrag: erst nach Studio-Test hochladen; `MapStyleConfig.ASSET_IDS` ist leer).
- Debug-Umschalten baut die Hauptinsel neu; Plot-Beete und bereits gespawnte Plots wechseln erst beim Neuaufbau.
