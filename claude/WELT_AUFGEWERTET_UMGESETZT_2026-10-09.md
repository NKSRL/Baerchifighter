# Welt aufwerten – Stand Zwischenabnahme 1 (Pakete 0, A, B, C)

Auftrag: `OPUS_PROMPT_WELT_AUFWERTEN_2026-10-08.md`. Umgesetzt in einer Cloud-Sitzung **ohne Studio**: Der Code ist geschrieben und geprüft (Syntax, Tests, Prüfskripte). Was nur Studio zeigen kann (Bilder, Teile-Zählung im laufenden Spiel, MicroProfiler, Upload), steht unten als **„In Studio prüfen“**. Ich halte hier an, wie im Prompt verlangt, und warte auf dein Okay für D–F.

Leitbild umgesetzt als: alles Neue läuft **nur auf dem Client**, der Server baut **kein einziges neues Teil** (das Teile-Budget der Plot-Inseln bleibt unverändert). Jedes Paket hat einen eigenen Schalter.

| Paket | Schalter | Aus = |
|---|---|---|
| A Tageslauf | `AmbienceConfig.DAY_CYCLE` | fester Himmel 16,9 Uhr wie bisher |
| B Wasser und Küste | `FeatureFlags.WORLD_B_WATER` | Wasser wie bisher |
| C Hauptinsel | `FeatureFlags.WORLD_C_HUB` | Hauptinsel wie bisher |
| 0 Kamerapunkte | nur Studio (DebugService) | – |

---

## Was beim Prüfen anders war als im Prompt

| Prompt sagt | Im Code / in der Sitzung | Was ich gemacht habe |
|---|---|---|
| Zuerst `claude/CONTEXT_BRIEFING.md`, `SKYBOX_UND_MAP_POLISH_UMGESETZT_2026-10-04.md`, `DESIGN_VORSCHLAG_*`, `TOWER_TERMINAL_UI_UMGESETZT_2026-10-08.md` lesen | Diese Dateien gibt es im Repo nicht (nur `MAP_REDESIGN_ABGESCHLOSSEN.md`, `MAP_VERKLEINERT_UND_PIT_TURM_2026-09-08.md` u. a.) | Stand aus dem Code gelesen (`AmbienceConfig`, `SkyBuilder`, `ScenicBuilder`, `WorldBuilder`, `AmbienceController`, `EventMotion`, `MapLayout`, `SkillFXController`, `EventFXController`, `EventService`, `MapService`, `EggMerchantService`). Abschnitt 2 des Briefings konnte ich deshalb nicht nachziehen. |
| Screenshots in Studio, Textur-Vorschau in Studio, MicroProfiler, Upload | Cloud-Sitzung ohne Studio und ohne Blender | Kamerapunkte als Debug-Befehl `worldshots` gebaut, Notizen aus dem Code (unten). Texturen per Python-Zeichenskript (wie die Icons), Vorschau als Bild geprüft. Alles läuft ohne Upload mit Rückfall. |
| Update über `python tools/make_update_rbxmx.py <seit>` | Das Werkzeug liegt nicht im Repo (nur auf dem Heim-PC) | Pro Paket ein eigener Commit; die Dateiliste je Paket steht unten. Update-Datei bitte am Heim-PC mit `make_update_rbxmx.py <commit vor Paket 0>` bauen. |
| Welt-Texte über `Localization/WorldText` | Gibt es nicht. Texte laufen über `Loc` + `Strings/{de,en,fr,es}.luau` | Neue Schlüssel `world.sign.*` in allen vier Sprachen (`check_loc` grün). |
| Ankunft: Bienen fliegen „Richtung eigene Insel“ | Der Spieler spawnt seit dem Insel-Spawn bereits **auf seiner Insel** (`PLAYER_SPAWN_OFFSET`) | Steht er auf seiner Insel, fliegen die Bienen zum **Honigmast** (Herz der Welt: Event, Händler, Tafeln). Nur beim Not-Spawn (voller Server) zeigen sie zur eigenen Insel. |
| Event-Zustand aus „was der Client über Events schon weiß“ | `EventPhaseChanged` geht beim Beitritt an den ersten Zuhörer (PetBar); ein später verbundener Controller verpasst die Join-Meldung | Der Pit-Rahmen liest die Welt: Ring ist Neon = Event läuft (Farbe = Event-Farbe), Restzeit aus der Countdown-Tafel („in 0:45“). Das Wespen-Nest liest, ob der Server es leuchten lässt (Boss in ≤ 5 min oder läuft). Keine neue Server-Logik. |
| Händler-Stand: Stoffdach mit Streifen | Der Stand hat schon ein gestreiftes Dach und ein Ei-Schild (`EggMerchantService`) | Ergänzt nur Laterne und Eierkorb, sichtbar ab 55 Studs Nähe. |
| Schaumsaum mit „Schaumrand (kachelbar entlang einer Linie)“ | Der sichtbare Saum ist je Insel 3–9 % des Scheibenradius breit; ein Ring-Bild passt nicht auf alle drei | Kachelbare **Schaum-Spitze** (Blasen mit Lücken) auf der ganzen Scheibe. Auf dem schmalen Saum wirkt der Kreisrand dadurch ausgefranst. |
| Arena-Inseln/äußere Stege: Schaum und Pfosten „im Teile-Budget mitzählen“ | – | **Auf dem Client gebaut**, je besetztem Slot (9 Teile), zählt deshalb nicht ins Server-Budget. Aus ab 420 Studs. |
| Steg zur Arena „Blick auf Terminal“ | Ein Tower-Terminal gibt es im Code nicht (Bericht dazu fehlt) | Kamerapunkt 4 schaut vom äußeren Steg auf die Arena. |
| Fähigkeiten-Show überschreibt Himmel? | `SkillFXController` legt einen **eigenen** Farbfilter `SkillFX_Sky` an, der Boss-Himmel `BossSky_Local` | Der Tageslauf schreibt nur in die Basis-Effekte; die Filter stapeln sich, keiner überschreibt den anderen. Zusätzlich hält der Tageslauf an, solange `SkillFX_Sky` färbt, und kehrt in 2 s weich zurück. |

---

## Paket 0: Bestandsaufnahme

**Gebaut:** Debug-Befehl `worldshots` (Studio, Command Bar, Server-Kontext):

```lua
local D = game.ServerScriptService.RBLDebug
D:Invoke("worldshots")      -- Liste der Punkte
D:Invoke("worldshots", 1)   -- Kamera fest auf Punkt 1, UI aus → Screenshot
D:Invoke("worldshots", 0)   -- zurück zur normalen Kamera
D:Invoke("daytime", 16.9)   -- für Vergleichsbilder: feste Uhrzeit ("auto" = Zyklus)
```

Die Punkte werden aus `MapConfig`/`MapLayout` **gerechnet** (`WorldShotController.shots()`), nicht als feste Zahlen gespeichert. Verschiebt sich eine Insel, wandert der Bildpunkt mit. Slot 1 ist der Plot bei 0 Grad (+X); für die Punkte 3–5 muss der Testspieler auf Slot 1 sitzen (erster Spieler auf dem Server).

| # | Punkt | Auge → Ziel |
|---|---|---|
| 1 | Spawn → Honigmast | Spawn-Punkt Slot 1, Augenhöhe → Mastspitze |
| 2 | Hauptinsel schräg oben | (−150, 150, −150) → Weltmitte |
| 3 | Plot-Insel, Brunnen | 22 Studs hinter dem Bärchi-Platz → Honig-Teich |
| 4 | Steg zur Arena | Anfang äußerer Steg → Arena-Mitte |
| 5 | Arena mit Turm | seitlich erhöht → Turm-Mitte (vorher `D:Invoke("fight", uid)`) |
| 6 | Rand → Horizont | Wasserrand bei 22,5° → ferne Schwebeinsel |

**Notizen je Punkt (aus dem Code, Studio-Bild fehlt noch):**

| # | leer | flach | unruhig | liest sich schlecht |
|---|---|---|---|---|
| 1 | Wiese zwischen Steg und Mast ohne Ziel-Hinweis | Mast hat nur einen Neon-Tropfen als Spitze | – | Wohin zuerst? Keine Wegweiser |
| 2 | Ring zwischen Pit (r 50) und Laternen (r 72) | Pit im Ruhezustand matt braun, kein Rahmen | – | Event-Zustand nur auf der Tafel |
| 3 | – | Honig-Oberfläche ohne Bewegung | – | – |
| 4 | Wasser links/rechts | Wasser ist eine Fläche ohne Bewegung; Arena-Insel ohne Schaum, Steg ohne Pfosten | – | – |
| 5 | Zuschauer fehlen (Paket E) | – | Turm-Ringe und Funken | – |
| 6 | Wasser bis zum Rand ohne Leben, keine Grenze | Himmel fest 16,9 Uhr | – | Wo endet das Wasser? |

**Offen (Studio):** die sechs Bilder nach `claude/screens/welt_vorher/` legen (Anleitung dort in `README.md`). Am besten mit `daytime 16.9` und den Schaltern A/B/C aus, dann ist es der echte Vorher-Stand. Danach dieselben sechs mit Schaltern an nach `claude/screens/welt_nach_C/`.

---

## Paket A: Lebendiger Himmel und Tageslauf

**Gebaut:**
- `Modules/DayCycle` (neu, rein): Uhr als Kosinus-Pendel aus `workspace:GetServerTimeNow()`, Spanne 14,5 → 19,0 → 14,5 Uhr in 20 min. Dazu Kurven für jeden Licht-Wert über der „Dämmerung“ d = 0..1, weich interpoliert (smoothstep, kein Knick). Gleiche Serverzeit = gleiche Werte auf jedem Client.
- `Controllers/DayCycleController` (neu): ein Takt mit 5 Hz. Setzt Uhr, Brightness, Ambient, OutdoorAmbient, ColorShift, Exposure, die Atmosphäre, den Basis-Bloom, die Basis-Farbkorrektur, die Terrain-Wolken und die Farbe der Wolkenpuffs.
  - **Leuchten:** Laternen und Stegkappen der Szenerie, der Neon-Tropfen auf dem Mast und alle angemeldeten Teile (Mastkrone, Arena-Kappen, Händler-Laterne) werden mit dem Tageslauf heller. Umgefärbt wird nur, wenn sich das Leuchten um mehr als 1 % ändert.
  - **Glühwürmchen** (hohe Qualität): ein Emitter, der jede Sekunde auf offenes Wasser vor der Kamera gesetzt wird (`MapLayout.isOpenWater`), nur ab der späten Dämmerung.
  - **Sterne** (hohe Qualität): ein Emitter hoch über der Welt, nur in der blauen Stunde, mit langsamem Funkeln (weit unter 3 Hz).
  - **Wolkenschleier** (hohe Qualität, nur mit hochgeladenem Wolkenbild): weiche Puffs, Farbe folgt dem Abendrot.
  - **Show-Vorrang:** siehe Tabelle oben.
- `AmbienceConfig.DAY_CYCLE = true`, Zahlen in `WorldFXConfig.DAY` und `DAY_CURVES`.
- **16,9 Uhr ist ein Punkt im Zyklus:** Bei d = 0,5333 stehen exakt die bisherigen Werte (Test prüft 17 Werte).
- **Lesbarkeit:** Das Außenlicht bleibt in der blauen Stunde mindestens 85 % so hell wie am Nachmittag (nur blauer), Brightness nie unter 1,5 (Test). ExposureCompensation hebt die blaue Stunde um 0,3.

**Test:** `tools/luau-tests/day_cycle.test.lua` (neu, 51 Prüfungen): Spanne, keine Sprünge je Takt (Uhr < 0,005 h, jeder Wert < 0,5 % seiner Spannweite), gleiche Zeit = gleiche Werte, alter Look bei 16,9 Uhr, Kurven sortiert, Lesbarkeit.

**Debug:** `D:Invoke("daytime", 19)` (blaue Stunde), `D:Invoke("daytime", 14.5)`, `D:Invoke("daytime", "auto")`.

**In Studio prüfen:** einen vollen Zyklus mit `daytime auto` laufen lassen (20 min). Wirkt 19 Uhr zu dunkel, `CLOCK_MAX` auf 18,6 senken (Annahme 1). Eier und Waben in der blauen Stunde gegen den Nachmittag vergleichen. Kometen-Show (`skilltest`) bei `daytime 18` starten: Das Licht bleibt stehen und kehrt danach weich zurück.

## Paket B: Wasser und Küste

**Gebaut** (`Controllers/WaterController`, neu, ein Takt mit 30 Hz):
- **Glitzern + Wellenlinien:** zwei Texturen auf der Oberseite der Wasserscheibe, wandern in verschiedene Richtungen. Das Glitzern wird in der blauen Stunde schwächer und bläulicher (Kurven `glitter`, `glitterTint`). **Ohne hochgeladene ID kein Glitzern** (eine Standardtextur auf 1300 Studs sähe nach Fehler aus): Das Wasser bleibt dann wie heute.
- **Schaum:** alle Säume cremeweiß statt reinweiß. Mit Schaum-Bild wird die Scheibe unsichtbar und die Spitzen-Textur atmet (in `AmbienceController` umgestellt: atmet die Textur, wenn es eine gibt, sonst die Scheibe) und treibt kaum merklich.
- **Arena-Insel und äußerer Steg:** pro besetztem Slot (`Plot_N` in workspace) Schaum um die Arena-Insel und 4 Pfosten mit Leuchtkappe an den Stegenden, wie bei den inneren Stegen. Gepoolt: einmal gebaut, danach nur ein- und ausgehängt (frei/besetzt, Sichtweite 420).
- **Honig-Fisch** (hohe Qualität): rund, goldglänzend, springt alle 20–60 s im Bogen auf offenem Wasser vor der Kamera. Spritzer beim Absprung und Eintauchen (ein Emitter), wachsender Ring auf der Oberfläche. Immer nur einer.
- **Bonbon-Bojen:** 8 Stück (niedrige Qualität 4) bei Radius 560 in den Lücken zwischen den Stegen, weiß mit rosa Streifen, schaukeln langsam.
- `MapLayout.isOpenWater/plotCenter/pitCenter/pitRadius/buoys` (neu): gleiche Formeln wie `MapParts`, ohne Server-Abhängigkeit.

**Test:** `map_layout.test.lua` erweitert: Bojen auf offenem Wasser, Stichproben für Land/Steg/Wasser, Arena-Formel gleich dem Schau-Turm.

**Debug:** `D:Invoke("fish")`.

**In Studio prüfen:** Ich habe angenommen, dass bei der liegenden Wasserscheibe (Zylinder mit 90° um Z) die Fläche `Right` oben ist. Ist das Glitzern unsichtbar, in `WaterController` `TOP_FACE` auf `Left` stellen. Nähte der Kacheln (sollte keine geben: auf dem Torus gezeichnet).

## Paket C: Die Hauptinsel als Herz der Welt

**Gebaut** (drei Controller statt einem großen, je eine Zuständigkeit):

`HubLandmarkController` (feste Wahrzeichen):
- **Wabenkrone am Honigmast:** 2 versetzte Reihen à 8 Bernstein-Waben um den Tropfen (Höhe 29,6 über dem Podest). Neon in dunklem Bernstein, leuchtet mit dem Tageslauf auf. Immer sichtbar, von jeder Insel aus.
- **Honigfaden:** läuft am Mast herab (Winkel 198°, frei von den schrägen Querhölzern und gegenüber dem Nest), über eine Tülle in eine Schale neben dem Sockel. Alle 3,2 s wächst ein Tropfen, fällt mit echter Schwerkraft und zieht einen Ring über den Honig. Aus ab 260 Studs.
- **Wegweiser:** an jedem der 8 Wege, 8,2 Studs neben dem Pflaster (Test: die Schilder ragen nicht über den Weg). Drei Schilder in Bärchi-Form (Brett mit Ohren, mit Bild: nur das Bild): **„Deine Insel“** (honiggelb) bzw. „Insel von X“ bzw. „Freie Insel“, **„Event“** zur Mitte, **„Händler“ oder „Bestenliste“**, je nachdem, was näher ist. Texte vorn und hinten mit Pfeil auf der richtigen Seite, in der Sprache des Betrachters, neu beschriftet bei Sprachwechsel und wenn Plots kommen oder gehen.
- **Händler:** Laterne und Korb mit drei Eiern, erst ab 55 Studs Nähe sichtbar.
- **Tafeln:** Holzrahmen, Honig-Ecken und eine kleine Krone an allen Bestenlisten-Tafeln und am Live-Board. Auf Platz 1 der Bestenlisten wandert ein Glanzstreifen (UIGradient, keine Textur nötig).

`HubEventController` (Event-Zustände):
- **Pit-Rahmen:** 8 Masten in den Zaunfeldern, dazwischen eine Wimpelkette (40 Wimpel in Rosa/Butter/Creme) und eine Lichterkette (32 Lichter), Laterne auf jedem Mast.
  - **Ruhe:** Wimpel wehen leicht (6°), Laternen und Lichter aus.
  - **Event startet bald** (letzte 60 s der Pause): Wimpel wehen stärker (20°), Laternen an.
  - **Event läuft:** zusätzlich pulsiert die Lichterkette mit 0,5 Hz in der Event-Farbe.
  - Bewegt wird alles mit **einem** `BulkMoveTo`, nur in Sichtweite.
- **Wespen-Nest:** 3 Wespen kreisen langsam. Boss bald oder da: 7 Wespen, schneller, dazu ein dunkel-oranger Puls um das Nest (0,6 Hz). Summen nur, wenn eine in Studio geprüfte Sound-ID in `WorldFXConfig.SOUNDS.waspHum` steht (heute leer, also still), in einer eigenen Sound-Gruppe `WorldAmbience`.

`ArrivalController` (einmal pro Beitritt): Honigblasen steigen um den Spieler auf, 6 Bienen kreisen einmal und fliegen dann zum Ziel (siehe Abweichungstabelle).

**Test:** `map_layout.test.lua` erweitert: Wegweiser (neben dem Pflaster, Schilder nicht über dem Weg, frei von Laternen und Wahrzeichen, außerhalb des Pit-Rahmens), Pit-Masten (nicht in einer Steg-Lücke, außerhalb des Rings, frei von Wahrzeichen), Honigmast (Schale neben dem Sockel und auf dem Podest, Faden frei von den Querhölzern, gegenüber dem Nest, Krone über dem oberen Querholz).

**Debug:**
```lua
D:Invoke("pitstate", "idle")   -- | "soon" | "live" | "auto"
D:Invoke("neststate", "boss")  -- | "calm" | "auto"
D:Invoke("arrival")            -- Ankunft nochmal
```

**In Studio prüfen:** Die Pfeile `◀ ▶` auf den Schildern: Fehlt das Zeichen in der Schrift FredokaOne, auf `<`/`>` umstellen (`HubLandmarkController.arrowText`). Wimpelkette über den Pit-Eingängen: Mindesthöhe 6,5 über dem Boden, Zaun-Oberkante 7,3 liegt 1,8 Studs daneben. Optisch prüfen, ob sie zu tief hängt (`PIT_FRAME.SAG`, `POLE_HEIGHT`).

---

## Dateien je Paket (für `make_update_rbxmx.py`)

| Paket | neu | geändert |
|---|---|---|
| 0 + Grundlage | `Config/WorldFXConfig`, `Controllers/WorldFXKit`, `Controllers/WorldShotController`, `tools/textures/make_world_textures.py` | `Services/DebugService`, `Modules/MapLayout`, `Main.client`, `map_layout.test.lua` |
| A | `Modules/DayCycle`, `Controllers/DayCycleController`, `day_cycle.test.lua`, `assets/world/paket_a/*` | `Config/AmbienceConfig`, `Main.client` |
| B | `Controllers/WaterController`, `assets/world/paket_b/*` | `Controllers/AmbienceController`, `Config/FeatureFlags`, `Main.client` |
| C | `Controllers/HubLandmarkController`, `HubEventController`, `ArrivalController`, `assets/world/paket_c/*` | `Strings/{de,en,fr,es}`, `Config/FeatureFlags`, `Main.client` |

Server-Dateien: nur `DebugService` (Befehle setzen workspace-Attribute, nur in Studio aktiv). **Kein MapBuild-Builder geändert.**

---

## Texturen

Gezeichnet mit `python3 tools/textures/make_world_textures.py` (fester Seed, reproduzierbar), alle PNG mit transparentem Hintergrund. Kachelbare Bilder sind auf einem Torus gezeichnet und nahtlos weichgezeichnet. **Keine ist hochgeladen.** Ohne ID gilt der Rückfall in der letzten Spalte.

| Datei | Größe | wofür | ohne ID |
|---|---|---|---|
| `paket_a/cloud_puff_flipbook.png` | 512 | Wolkenschleier, 2 Varianten (2x2) | Schleier aus |
| `paket_a/firefly.png` | 256 | Glühwürmchen | Roblox-Funkeln |
| `paket_a/star_twinkle.png` | 256 | Sternfunkeln | Roblox-Funkeln |
| `paket_b/water_glitter.png` | 512 kachelbar | Wasserglitzern | kein Glitzern |
| `paket_b/water_waves.png` | 512 kachelbar | Wellenlinien | keine Wellen |
| `paket_b/foam_lace.png` | 256 kachelbar | Schaum-Spitze | cremefarbene Scheibe |
| `paket_b/splash_flipbook.png` | 256, 2x2 | Fisch-Spritzer | Roblox-Rauch |
| `paket_b/water_ring.png` | 256 | Ring auf dem Wasser | weiße Scheibe |
| `paket_c/amber_comb.png` | 256 | Wabe der Mastkrone | Neon-Bernstein |
| `paket_c/honey_drop.png` | 256 | (Reserve für D: Brunnen) | – |
| `paket_c/honey_bubble.png` | 256 | Ankunft-Blasen | Roblox-Funkeln |
| `paket_c/bee_flipbook.png` | 256, 2x2 | (Reserve für F: Bienen als Partikel) | Teile-Bienen |
| `paket_c/wasp_flipbook.png` | 256, 2x2 | (Reserve) | Teile-Wespen |
| `paket_c/pennant_fabric.png` | 256 | Wimpel | farbige Stoff-Rechtecke |
| `paket_c/stall_stripes.png` | 256 | (Reserve: Stand hat schon Streifen) | – |
| `paket_c/bear_sign.png` | 512 | Wegweiser in Bärchi-Form | Brett mit zwei Ohren |
| `paket_c/shine_strip.png` | 256 | (Reserve: Glanz läuft über UIGradient) | – |

**Hochladen (wenn du willst, erst nach der Studio-Vorschau):** Studio → Asset Manager → Bulk Import → Ordner `assets/world/paket_a` bis `paket_c` (Typ Image). Die IDs als `"rbxassetid://…"` in `src/shared/Config/WorldFXConfig.luau` → `TEXTURE_IDS` beim gleichnamigen Schlüssel eintragen. Vorschau ohne Upload: das PNG in Studio als Decal auf ein Testteil ziehen (Studio lädt es dabei als temporäres Asset).

## Sounds

Keine neuen Sounds. Der Wespen-Summton ist vorbereitet (`WorldFXConfig.SOUNDS.waspHum`, Lautstärke 0,08, im Boss-Fall 0,12, also nie über Zuschauer-Kampf 0,12), aber leer, bis eine ID in Studio geprüft ist. Die Klang-Kulisse kommt mit Paket H.

## Messwerte

| | vorher | nachher | wie |
|---|---|---|---|
| Server-Teile pro Plot-Insel | 191–209 | **unverändert** | kein Server-Builder geändert. Bitte mit `D:Invoke("parts")` bestätigen |
| Client-Teile Hauptinsel (C) | 0 | ≈ 290 (Krone 16, Faden 6, Wegweiser 80, Händler 6, Tafeln 72, Pit-Rahmen 88, Nest 15, Bienen 18) | gezählt im Code. Bis auf die Krone alles mit Distanz-Abschaltung |
| Client-Teile Wasser (B) | 0 | Bojen 24, Fisch 7, je besetzter Arena 9 (max. 72) | ebenso |
| Emitter (neu) | 0 | 5 (Glühwürmchen, Sterne, Schleier, Spritzer, Blasen); niedrige Qualität: 2 | |
| Takte (Heartbeat) | – | DayCycle 5 Hz, Water 30 Hz, Hub 20 Hz, HubEvents 20 Hz, Culling 2 Hz | kein Thread pro Objekt |
| MicroProfiler | – | **offen (Studio)** | |

## Qualitätsregler (Stand A–C)

`WorldFXConfig.MIN_QUALITY`: 0 = läuft immer, 1 = nur ab `AmbienceConfig.HIGH_QUALITY_FROM` (Grafikstufe 4, Automatisch zählt als hoch).

| Funktion | ab | | Funktion | ab |
|---|---|---|---|---|
| Tageslauf, Licht | 0 | | Bojen (niedrig: 4) | 0 |
| Laternen-Leuchten | 0 | | Mastkrone | 0 |
| Glühwürmchen | 1 | | Honigfaden + Tropfen | 1 |
| Sterne | 1 | | Ankunft | 0 |
| Wolkenschleier | 1 | | Wegweiser | 0 |
| Wasserglitzern | 0 | | Pit-Rahmen | 0 |
| Wellenlinien | 1 | | Wimpel wehen | 1 |
| Schaum-Textur | 0 | | Händler-Deko | 0 |
| Arena-Küste | 0 | | Wespen kreisen | 1 |
| Honig-Fisch | 1 | | Nest-Puls | 0 |
| | | | Tafelrahmen / Glanz | 0 / 1 |

## Annahmen (von mir, änderbar)

| # | Annahme | wo |
|---|---|---|
| 1 | Tageslauf 20 min, 14,5–19,0 Uhr wie vorgeschlagen; blaue Stunde mit Exposure +0,3 und hellem blauem Außenlicht statt engerer Spanne | `WorldFXConfig.DAY`, `DAY_CURVES` |
| 2 | Event „startet bald“ = letzte 60 s der Pause | `PIT_FRAME.SOON_SECONDS` |
| 3 | Boss „bald“ = solange der Server das Nest leuchten lässt (5 min vorher bis Ende) | `MapConfig.WASP_NEST.glowSeconds` |
| 4 | Ankunfts-Bienen zum Honigmast (Spieler steht schon auf seiner Insel) | `ArrivalController.target` |
| 5 | Wegweiser zeigen Insel, Event und das nähere von Händler/Bestenliste | `HubLandmarkController.sideTarget` |
| 6 | Glitzern nur mit hochgeladener Textur, kein Ersatzbild | `WaterController.setupWater` |
| 7 | Bojen bei Radius 560 (Wasser endet bei 650) | `WorldFXConfig.BUOYS.RADIUS` |
| 8 | Musik: keine | – |

## Offen und bekannt

- **Alles Sichtbare ist ungetestet in Studio.** Bitte als Erstes: Welt baut, Plot spawnt, Tower-Lauf, Event, Ei legen und einsammeln, Output ohne Fehler (`[DayCycle] an`, `[Water] aktiv`, `[Hub] Wahrzeichen aktiv`, `[HubEvents] aktiv`).
- Die Typprüfung (`--!strict`) macht nur Studio. Lokal: Syntax aller Dateien, alle Lua-Tests und Prüfskripte grün.
- Screenshots `welt_vorher/` und `welt_nach_C/` fehlen (keine Studio-Sitzung).
- `make_update_rbxmx.py` fehlt im Repo: Update-Datei am Heim-PC bauen.
- `claude/CONTEXT_BRIEFING.md` fehlt im Repo: Abschnitt „Die Welt“ dort nachziehen, sobald die Datei da ist. Kurzfassung: siehe oben, Pakete A–C.

## Prüfungen (alle grün)

`luau-compile --null` für alle `.luau` · `check_locals` (Höchstwert MapConfig 191, unverändert) · `guide_steps`, `unlock_rules`, `boss_tiers` · `run_local.py` für `combat_rating`, `gold_rules`, `map_layout` (erweitert), `live_board`, `event_schedule`, `egg_press`, `honey_pond`, `shop`, `migration_hbb`, `endless`, **`day_cycle` (neu)** · alle Sims unter `tools/sim` · `check_feedback`, `check_members`, `check_consistency`, `check_loc`, `check_decor`.
