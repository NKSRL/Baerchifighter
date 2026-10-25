# Welt-1 Hub & Royal-Honey-Stilguide (Übergabe für neue Chats)

Diese Datei dient als kompakter Kontext- & Stil-Leitfaden, um in einem neuen Chat nahtlos im **Royal-Honey-Sanktuarium-Stil** (Welt-1-Hub-Redesign v3) weiterzubauen.

---

## 1. Visuelle DNA & Formensprache
- **Thema**: *Königliches Honig-Heiligtum* — eine harmonische Brücke zwischen den sauberen, gefasten Holz-/Stein-Meshes der **Epilog-Insel** (`Epilog_Insel_*`, `Epilog_Plank`) und der dunklen Schiefer-/Gold-Architektur von **Welt 2** (`Welt2Builder.luau`).
- **Geometrie-Regeln**:
  - Keine flachen Standard-Platten oder schmucklosen Zylinder („Slop“).
  - Jedes Bauwerk nutzt **gestufte Sockel (2–3 Stufen)**, **gefaste Kanten (Bevels)**, **verjüngte Pfeiler/Obelisken** mit **goldenen Eckleisten/Ringen** und **sechseckige Waben-Intarsien**.
  - Übergänge zwischen Höhen (z. B. Plaza $\leftrightarrow$ Allee oder Ufer $\leftrightarrow$ Brücke) werden durch **eingefasste Freitreppen mit Treppenwangen**, **Randsteine (`Curbs`)** und **sanfte Bögen** gelöst.
  - Leuchtende Akzente (Neon) werden gezielt als **eingelassene Honig-Rinnen**, **Waben-Kerne** oder **schwebende Kristalle/Kronen** eingesetzt.

---

## 2. Verbindliche Farb- & Materialpalette (Roblox & Blender)

| Rolle | Farbname im Code | RGB (`Color3.fromRGB`) | Roblox-Material | Einsatzbereich |
| :--- | :--- | :--- | :--- | :--- |
| **Hauptstein (Hell)** | `COL_CREAM_STONE` | `(238, 223, 192)` | `Enum.Material.Sandstone` | Plaza-Podeste, Treppenstufen, Allee-Bett, Brückenpfeiler |
| **Zierstein (Creme)** | `COL_CREAM_LIGHT` | `(247, 236, 212)` | `Enum.Material.Sandstone` | Innere Boden-Intarsien, Randstein-Fassungen |
| ** Kontraststein (Dunkel)** | `COL_DARK_SLATE` | `(48, 43, 64)` | `Enum.Material.Slate` | Obelisken, Zaunpfeiler, Schmiedegitter, Brunnenbecken, Randsteine |
| **Kontraststein (Mittel)** | `COL_MID_SLATE` | `(76, 70, 96)` | `Enum.Material.Slate` | Abwechselnde Allee-Trittplatten, Sektor-Füllungen |
| **Königsgold** | `COL_GOLD` | `(242, 188, 64)` | `Enum.Material.Metal` | Fassungen, Speerspitzen, Wabenringe, Endkappen, Handläufe |
| **Antikgold** | `COL_GOLD_DARK` | `(196, 142, 42)` | `Enum.Material.Metal` | Laternenketten, dunklere Metall-Beschläge |
| **Honig-Leuchten** | `COL_HONEY_GLOW` | `(255, 196, 56)` | `Enum.Material.Neon` | Honig-Rinnen, Waben-Kerne, Laternen, flüssiger Honig |
| **Kristall-Leuchten** | `COL_HONEY_BRIGHT` | `(255, 224, 115)` | `Enum.Material.Neon` | Schwebende Herz-Kristalle (`Tropfen`), Kronen-Ringe |
| **Warmes Deckholz** | `COL_WOOD_WARM` | `(162, 108, 64)` | `Enum.Material.WoodPlanks` | Brückenbohlen (abwechselnd mit `(148, 96, 56)`) |
| **Dunkles Bauholz** | `COL_WOOD_DARK` | `(104, 68, 42)` | `Enum.Material.Wood` | Laternenmasten, Brücken-Unterzüge, Dachbalken |

---

## 3. Wichtige Dateien & Assets im Projekt

### Blender & Exportierte `.fbx`-Meshes (`assets/map/`)
- **Blender-Quelldatei (1:1 Maßstab in Studs)**: `assets/map/Welt1_Hub_Entwurf.blend`
  - Collections: `2_Hub_Mitte_Plaza`, `3_Hub_Wege_Laternen`, `4_Bruecken_Entwurf`
- **Exportierte, nach Materialgruppen zusammengefügte `.fbx`-Dateien** (mit gebackenen `sRGB`-Vertexfarben `Col`, Export: `-Z Forward`, `Y Up`, `FBX_SCALE_ALL`):
  - `assets/map/Hub_Brunnen.fbx` (`Hub_Brunnen_Sandstein`, `_Schiefer`, `_Gold`, `_GoldNeon`, `_HonigNeon`, `_Tropfen`)
  - `assets/map/Hub_PlazaUndZaun.fbx` (`Hub_Plaza_Sandstein`, `_Randstein`, `_Schiefer`, `_Gold`, `_HonigNeon`, `Hub_Zaun_Schiefer`, `_Gold`, `_HonigNeon`)
  - `assets/map/Hub_Alleen.fbx` (`Hub_Allee_Schiefer`, `_Sandstein`, `_Randstein`, `_Gold`, `_HonigNeon`, `Hub_Laterne_Holz`)
  - `assets/map/Hub_Bruecke.fbx` (`Hub_Bruecke_HolzHell`, `_HolzMittel`, `_HolzDunkel`, `_Randstein`, `_Gold`, `_HonigNeon`, `_SlotAkzent`)

### Luau-Builder & Controller (`src/`)
- **`src/server/Util/MapBuild/HubPlazaBuilder.luau`**:
  - Zentrale Datei für das gesamte Welt-1-Hub-Design (Brunnen, Plaza, geschlossener Sanktuarium-Zaunring, Alleen, Imker-Laternen, Bogenbrücken, Brückenportale, Tafel-Pavillons).
  - Besitzt einen **automatischen `.fbx`-Fast-Path (`spawnMeshGroup`)**: Sobald die `.fbx`-Meshes in `ReplicatedStorage.Assets` liegen, lädt er die vereinigten `MeshPart`s + wenige unsichtbare Box-/Zylinder-Collider. Fehlen sie, greift nahtlos der prozedurale Part-Fallback.
- **Weitere angebundene Module**:
  - `src/server/Util/MapBuild/WorldBuilder.luau` & `ScenicBuilder.luau`
  - `src/server/Util/PlotRoutes.luau` (Wegpunkte über den Brückenbogen `BRIDGE_ARCH_HEIGHT = 1.35` und die 8 Plaza-Freitreppen)
  - `src/server/Services/MapService.luau` (`setEventPitTheme` färbt `EventFence_*` & `EventCompassRay_*`)
  - `src/client/Controllers/HubEventController.luau` & `HubLandmarkController.luau`

---

## 4. Technische Spiel-Randbedingungen (Unbedingt einhalten!)
1. **Höhen & Radien im Zentrum**:
   - `PLATFORM_TOP_Y = 0`, begehbare Plaza-Oberkante: **`floorY = 1.28`** (`EVENT_PIT_GROUND_CLEARANCE + EVENT_PIT_FLOOR_HEIGHT`).
   - Waben (`CombService.luau`) spawnen auf `Y = 1.28` zwischen **`R = 8` und `R = 44`**. Der zentrale Brunnen muss deshalb zwingend innerhalb von **$R \le 7{,}6$** bleiben!
   - Der geschlossene Sanktuarium-Zaunring liegt auf **$R = 46{,}0$** und lässt **nur die 8 Freitreppen an den Alleen** (`baseAngle ± 0.124 rad`) offen.
2. **Pflicht-Namen für Game-Services**:
   - `Platform.EventPit.EventFloor` (`CanCollide = true, CanQuery = true`), `EventRing` (`Metal` im Ruhemodus, `Neon` bei Live-Event), `EventBannerAnchor.Banner`.
   - `Platform.Honigmast.Tropfen` (plus unsichtbare `MapConfig.CENTER_DECOR`-Teile für `map_layout.test.lua`).
   - Brücken-Segmente müssen `"Bridge"` oder `"Plank"` im Namen tragen (`CanCollide = true, CanQuery = true`); Geländer/Überbauten müssen `"Rail"` oder `"Fence"` heißen und `CanQuery = false` haben (für `DebugBridge.luau`).
3. **Code-Qualität**:
   - Alle Dateien mit `--!strict` beginnen.
   - `MapConfig.luau` steht bei `192/200` lokalen Variablen (`tools/check_locals.py`) — dort **keine** neuen `local`-Variablen anlegen.
   - Vor Abschluss immer prüfen mit: `tools/check_members.py`, `tools/check_locals.py`, `tools/check_decor.py` und `tools/make_update_rbxmx.py`.

---

## 5. Copy-Paste Start-Prompt für einen neuen Chat
> Bitte lies zuerst `docs/HBB_WELT1_HUB_STILGUIDE.md` und `src/server/Util/MapBuild/HubPlazaBuilder.luau`. Wir bauen an unserem Roblox-Spiel im **Royal-Honey-Sanktuarium-Stil** (Creme-Sandstein, dunkler Schiefer, poliertes Gold, warme Holzbohlen und leuchtende Honig-Waben, kombiniert aus Blender-FBX-MeshParts + schlanken unsichtbaren Roblox-Collidern) weiter. Meine nächste Aufgabe ist: **[HIER AUFGABE EINTRAGEN]**
