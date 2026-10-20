# Epilog: Blender-Assets (Insel, Planke, Wolke, Terminal) – 2026-10-20

## Stand
Alle Assets sind in Blender gebaut, per Render geprüft und exportiert (Ordner `assets/epilog/`, Quelle `Epilog_Assets.blend`). Die Roblox-Seite ist fertig verdrahtet (`Util/MapBuild/EpilogMeshes`), nutzt die Meshes aber erst, wenn die Vorlagen in Studio importiert sind. Bis dahin laufen unverändert die Primitive (Fallback). **Nicht in Studio getestet, keine Asset-IDs vergeben** – der Import und der Upload der Bilder gehen von hier nicht (Studio-Werkzeug lädt nur http-Bilder, 3D-Import nur per Dialog).

| Datei | Inhalt | Dreiecke | Maße |
|---|---|---|---|
| `Epilog_Insel.fbx` | 6 Objekte: Wiese (Vertexfarben, Gras/Rand/Erde), Fels, Kristall (4), Busch1–3 | 947 | Wiese 24,9 breit, Tiefe ca. 12 |
| `Epilog_Plank.fbx` | Holzplanke, 4 Latten, Goldleisten | 96 | 5,26 × 0,76 × 8,4 |
| `Epilog_Terminal.fbx` | 20 Teile `Epilog_Terminal_<Teil>`, jedes im eigenen Koordinatensystem (Scheiben mit Achse X, wie im Bau) | 864 | Teilmaße = Layout |
| `Epilog_Terminal_Albedo.png` | 512×512, gebürstetes Grau, Kratzer, Warnstreifen-Band, kein Alpha | – | – |
| `Epilog_Wolke.png` | 256×256 RGBA, weicher Nebelballen | – | – |
| `Epilog_Knopf` | nicht separat: der Knopf (konkaver Kopf, 144 Tris) ist Teil des Terminals | – | – |

Renders: `docs/screens/EPILOG_ASSET_*.png`.

## Import in Studio (einmalig)
1. 3D-Import (Asset Manager → Bulk Import oder Home → Import 3D) für die drei FBX, jeweils „Als Modell importieren“, Materialien ignorieren.
2. Ergebnis in `ReplicatedStorage.Assets` ablegen und exakt so benennen: `EpilogIsland`, `EpilogPlank`, `EpilogTerminal` (Aufbau Model > Model > MeshParts ist egal, es wird rekursiv nach dem Teilnamen gesucht).
3. Bilder hochladen, die IDs in `Config/EpilogConfig.ASSETS` eintragen: `cloudTex` (Wolke) und `terminalAlbedo`.
4. Falls Studio die Vertexfarben der Insel/Planke verwirft (Teile erscheinen weiß/grau): am jeweiligen Vorlagen-Modell das Attribut `FarbenAusConfig = true` setzen, dann färbt der Code aus der Config (Insel: ein Farbton je Teil, Planke: plankA/plankB).
5. Datei → Auf Roblox speichern.

## Wie die Builder die Vorlagen nutzen
- **Insel:** `EpilogMeshes.islandSkin` klont die 6 Teile und setzt sie über die Wiese als Referenz (Maßstab aus `Wiese.Size.X`, Drehung = −Brückenwinkel, Ursprung = Mitte Wiesenoberkante). Die Primitive Fels/Kristalle/Büsche entfallen, die Wiesen-Scheibe bleibt als unsichtbarer Boden (Kollision, Touched), Inselrand-Leuchten und Podest bleiben. Kristall und Büsche tragen `EpilogDeco` und wippen wie zuvor. Teile: 10 Layout-Teile + 6 Meshes = 16 (Budget 18).
- **Planke:** `Epilog_Plank` wird auf die Layout-Größe gesetzt (Länge × Dicke × Breite), Federn/Funken/Abbau unverändert.
- **Terminal:** jedes Mesh bekommt Größe und CFrame des Primitivs. Weil die Meshes im Teil-Koordinatensystem gebaut sind, funktionieren `RightVector` als Knopf-Normale, SpotLight/Emitter (Face Right), SurfaceGui (Top) und die Klappen-Drehung am Scharnier ohne Client-Änderung. Farben kommen aus `TERMINAL.colors` (Zustandsfarben der Lampen bleiben Client-Sache); Sockel/Korpus/Konsole bekommen `terminalAlbedo` als Textur, Farbe wird zum Tint. Der unsichtbare `Ausloeser` bleibt Primitiv.
- Fehlt eine Vorlage oder ein Teil darin → Primitiv. Nichts gelöscht, keine Balance-Zahl berührt.

## Geprüft
- Blender: Renders Insel (2 Ansichten), Planke, Terminal (Vorder-/Rückansicht, mit Albedo) angesehen.
- Luau-Compile der geänderten Dateien; `check_locals/members/consistency/loc/ui/decor/feedback`; Tests `epilog_state/summit/island/terminal`, `combat_rating`, `gold_rules`, `map_layout`, `live_board`, `event_schedule`, `egg_press`, `honey_pond`, `shop`, `migration_hbb`, `endless`, `ui_texts`, `guide_steps`, `boss_tiers` grün. Vorher schon offen und unverändert: `unlock_rules` 1 FAIL, `migration_hbb` C4 (20 erwartet, 17), `check_members` (CombConfig in RecyclerBuilder), `check_locals` MapConfig 192.

## Annahmen / offen (nicht in Studio verifiziert)
- Importmaßstab 1 Stud je Blender-Einheit (der Code rechnet ihn über die Wiesenbreite heraus; Terminal/Planke setzen `Size` direkt).
- Achsen: FBX mit Vorne −Z, Oben Y exportiert, Vorderseite des Terminals = Roblox −Z. Bitte nach dem Import einmal prüfen, ob das Terminal zur Brücke blickt.
- Vertexfarben von MeshParts: Annahme „werden gerendert“ (≈75 %), sonst Attribut `FarbenAusConfig`. Die Büsche haben dann keine rosa Blüten.
- Kollision der Terminal-Blöcke: `CollisionFidelity = Box`.
- Studio-Screenshots je Zustand und die `make_update_rbxmx.py`-Einspielung stehen aus.
