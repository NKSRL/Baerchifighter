# Final-Epilog · Prompt 3 von 7 — Schwebende Insel & Brücke (20.10.2026)

Stand: umgesetzt und lokal geprüft. **Nicht in Studio getestet** (kein Studio-Zugriff in dieser Sitzung), Blender-Assets inzwischen **erstellt** (siehe `docs/HBB_EPILOG_ASSETS_2026-10-20.md`), Studio-Import/Upload offen; bis dahin laufen die Primitive.

## Was gebaut wurde

Eine kleine Insel schwebt über dem Gipfel. Die Brücke dorthin existiert vorher nicht: Sie entsteht Planke für Planke erst nach dem gespeicherten Sieg (`epilog.state` = pending/seen). Alles ist server-autoritativ; der Client wippt nur die Deko.

| Datei | Zweck |
|---|---|
| `src/shared/Modules/EpilogIslandLayout.luau` (neu) | reine Geometrie (Zahlen), getestet |
| `src/server/Util/MapBuild/EpilogIslandBuilder.luau` (neu) | baut/zerstört Insel + Brücke, Anti-Exploit, Wegpunkte, Terminal-Mount |
| `src/client/Controllers/EpilogIslandFX.luau` (neu) | Deko wippt ±0,6 Studs / 4 s (nur lokal), Tag `EpilogDeco` |
| `tools/luau-tests/epilog_island.test.lua` (neu) | 264 Prüfungen, 6 Brückenrichtungen |
| `docs/screens/EPILOG_P3_seitenansicht.png` (neu) | Seitenansicht **aus den Layout-Zahlen** (keine Studio-Aufnahme) |
| `Config/EpilogConfig.luau` | neu: `ISLAND`, `BRIDGE`, `ASSETS` |
| `Services/MapService.luau` | Wrapper, Aufräumen bei Leave/`setSummit(false)`/`lowerSummit`, Wiederaufbau nach Plot-Neuaufbau |
| `Services/EpilogService.luau` | Guard, `runBridgeSequence`, `placeOnIsland`, Restore für pending/seen, `debugBridge`, erweiterter `scan` |
| `Services/DebugService.luau` | `epilog bridge | bridgeinstant | bridgeoff` |
| `src/client/Main.client.luau` | `EpilogIslandFX.init()` |

### Ablauf (Zeiten in `EpilogConfig`)
1. **Insel (3 s):** `buildIsland(plot, {animate=true})` baut die Insel (14 Teile) mit dem Sequenzstart, wächst per `Model:ScaleTo` (Start 12 %, 15 Schritte, ease-out) aus einem Nebel-Emitter. Kein Mesh-Tausch.
2. **Brücke (≈ 4,5 s):** 14 Planken, je 0,3 s Abstand. Jede wird erst jetzt per `Instance.new` erzeugt, fällt 2,6 Studs mit Ease **Back** (Overshoot, „klack") auf den Platz, wird danach erst begehbar und gibt einen Funkenstoß (Muster zufällig, Reihenfolge fest).
3. **Verbindung:** Glas-Geländer (4 Stücke) blendet ein, Neon-Lichtimpuls läuft zur Insel (1,2 s), dann `onDone`.
4. **Dauer:** Brücke bleibt bis Prompt 6. **Abbau** `removeAll(plot, true)`: Planken in umgekehrter Reihenfolge, dann schrumpft die Insel (3 s gesamt). `removeAll(plot, false)` sofort.
5. **Ankunft:** Betritt der Avatar die Wiese bei fertiger Brücke, leuchtet der Inselrand golden (`setArrivalHandler` für Prompt 6).

### Maße (Studs)
Insel Ø 24, Oberkante **+18** über der Gipfeletage, Brücke 8,4 breit, ≈ 72 lang (Steigung ≈ 14°), Geländer 8 hoch, Luft zwischen Brückenansatz und Inselrand **70**.

## Teile-Budget (aus dem Layout, Test grün)
- Insel: **14** (Wiese, Inselrand, 3 Felsschichten, 4 Kristalle, 3 Büsche, Podest, Fangboden) — Grenze 18
- Brücke: **18** dauerhaft (14 Planken + 4 Geländer), kurz 19 mit Lichtimpuls — Grenze 20
- Emitter: höchstens **3** gleichzeitig (Funken 0,55 s Lebensdauer, harte Zählgrenze im Code); Nebel nur während der Enthüllung
- Gesamtinsel (≤ 250): **nicht gemessen** — `D:Invoke("parts")` in Studio nötig. Rechnerisch kommen zu Gipfel (≤ 24) und Turm bis zu +33 Teile dazu.

## Anti-Exploit
- `growBridge`/`buildBridgeInstant` bauen nur, wenn der Guard (EpilogService: Flag an **und** state pending/seen) zustimmt; ohne Guard nie. `growBridge` prüft zusätzlich: Spieler lebt und steht im Radius des Gipfels (Etagenradius + Gipfelring, ±15 Höhe).
- Kein Brückenteil vorab im Workspace (`Bruecke`-Modell entsteht mit der ersten Planke). Kein Transparenz-Trick.
- Insel außer Sprungweite (70 Luft, +18 Höhe). Wiese vor fertiger Brücke betreten → Rücksetzen zum Gipfel.
- Fangboden (unsichtbar) unter Brücke und Insel: zurück zum Gipfel, bei fertiger Brücke zum Brückenansatz. Cooldown 1 s.
- `teleportPlayerToIsland` funktioniert nur bei fertiger Brücke.
- Cleanup: Leave, Reset, `setSummit(false)`, `lowerSummit`, Gipfel-Zerstörung → alle Verbindungen getrennt, Fäden abgebrochen, Ordner `Epilog` entfernt, wenn leer.

## Funktionen für Prompt 4–6
- `EpilogIslandBuilder.buildIsland(plot, {animate})` · `growBridge(plot, onDone) -> (ok, grund)` · `buildBridgeInstant(plot)` · `removeAll(plot, animated, onDone?)` · `getBridgeWaypoints(plot) -> {Vector3}` (18 Fußpunkte: Gipfel, Ansatz, Ansatz-Ende, 14 Planken-Enden, Ankunft vor dem Terminal) · `getTerminalMount(plot) -> CFrame` (Fußpunkt auf dem Podest, Blick zur Brücke; zusätzlich Attachment `TerminalMount` am Teil `Podest`) · `teleportPlayerToIsland(player, companion)` · `setGuard`, `setArrivalHandler`, `exists/isComplete/isGrowing`, `countParts`, `scanWorkspace`
- `MapService`: `buildIsland`, `growBridge`, `buildBridgeInstant`, `removeIsland`, `teleportToIsland`, `getBridgeWaypoints`, `getTerminalMount`, `hasIsland`, `isBridgeComplete`, `isBridgeGrowing`, `countIslandParts`
- `EpilogService`: `runBridgeSequence(player, onDone?)`, `placeOnIsland(player)`
- **Prompt 5:** `EpilogConfig.BRIDGE.autoStart` auf `false` stellen und `EpilogService.runBridgeSequence` zum Kamerazeitpunkt (Aufstieg 5–12 s) rufen. Bis dahin startet `beginFull` Insel + Brücke selbst direkt nach dem Teleport.
- Tags: `EpilogInsel`, `EpilogBruecke` (Modelle), `EpilogDeco` (wippende Teile). Attribute: `Insel.Revealed/Arrived`, `Bruecke.Planks/Complete`.

## Test in Studio
```lua
D:Invoke("epilog","on")       -- Schalter
D:Invoke("epilog","scan")     -- VOR dem Sieg: inselModelle/brueckenModelle/planken = 0
D:Invoke("epilog","start")    -- pending, Gipfel, Insel, Brücke wachsen
D:Invoke("epilog","bridge")   -- (nur bei pending/seen) Brücke erneut wachsen lassen
D:Invoke("epilog","bridgeoff")-- animierter Abbau, danach scan: inselTeile 0, brueckenTeile 0, reste false
D:Invoke("epilog","reset")    -- alles weg
```
Dazu `D:Invoke("parts")` vor/nach messen.

## Annahmen (bitte bestätigen)
1. **„70 Studs horizontal" = Luft zwischen Gipfel-Brückenansatz und Inselrand**, damit die Brücke ≈ 70 lang ist. Die Inselmitte liegt dadurch ≈ 114 Studs von der Gipfelmitte (nicht 70). Ändern: `ISLAND.edgeGap`.
2. **Auch „pending"-Restore baut Insel + fertige Brücke sofort** (Avatar bleibt am Gipfel), sonst hängt der Spieler ohne Kamerafahrt fest. „seen" setzt den Avatar vor das Terminal.
3. Die Wachstumszeit beträgt 14 × 0,3 = 4,2 s (+ Feder ≈ 4,5 s, mit Impuls ≈ 5,7 s) — die Vorgabe „0,3 s Abstand" gewinnt gegen „5 s".
4. Geländer ist ein 8 Studs hohes Glas (Transparenz 0,7), weil ein 4 Studs hohes überspringbar wäre. Es entsteht mit der letzten Planke; während des Wachsens fängt der Fangboden.
5. Nach dem Respawn steht der Avatar am Gipfel (Gipfel-Logik aus Prompt 2), auch im Zustand „seen".
6. Planken sind eine Teile-Art (Holz, Creme/Bernstein) ohne goldene Zierleiste (Platzhalter bis `Epilog_Plank.fbx`).

## Offen / nicht gemacht
- **Blender-Assets** `Epilog_Insel.fbx`, `Epilog_Plank.fbx`, `Epilog_Wolke.png` **erstellt** (`assets/epilog/`), Studio-Import und Upload **offen** → **Asset-IDs: keine**. Vorlagen werden über `ASSETS.islandTemplate/plankTemplate` (ReplicatedStorage.Assets) gefunden, `cloudTex` bleibt leer bis zum Upload (Standardtextur als Platzhalter). Details: `docs/HBB_EPILOG_ASSETS_2026-10-20.md`.
- Keine Studio-Vorschau, keine Teile-Messung, keine Studio-Screenshots (nur die Zahlen-Skizze oben), `make_update_rbxmx.py` **nicht** ausgeführt.
- Geländer-/Plank-Look, Funkenfarbe, Nebel-Textur sind ungesehen.
- Sound: Platzhalter folgt in Prompt 7.
- Kein Commit gemacht.

## Prüfungen (20.10., lokal)
`luau-compile --null` für alle geänderten Dateien ✔ · `check_locals` max 192 (MapConfig, unverändert) ✔ · `guide_steps`, `boss_tiers` ✔ · `epilog_state` 55 ✔, `epilog_summit` 94 ✔, `epilog_island` 264 ✔, `combat_rating`, `gold_rules`, `map_layout`, `live_board`, `event_schedule`, `egg_press`, `honey_pond`, `shop`, `endless` ✔ · `check_feedback`, `check_consistency`, `check_loc`, `check_ui`, `check_decor` ✔.
Bekannte Altfehler, **nicht von diesem Prompt**: `unlock_rules` (1 FAIL), `migration_hbb` C4 (erwartet 20, bekommt 17), `check_members` (2 Funde CombConfig in RecyclerBuilder).
