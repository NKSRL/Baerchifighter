# Welt aufwerten – Abschluss (Pakete 0, A–J, Abnahme 3)

Auftrag: `OPUS_PROMPT_WELT_AUFWERTEN_2026-10-08.md`. Umgesetzt in einer Cloud-Sitzung **ohne Studio**: Der Code ist geschrieben und geprüft (Syntax, Tests, Prüfskripte). Was nur Studio zeigen kann (Bilder, Teile-Zählung im laufenden Spiel, MicroProfiler, Upload), steht unten als **„In Studio prüfen“**. Zwischenabnahmen 1 (0, A–C) und 2 (D–F) sind erledigt, jetzt sind auch G–J fertig. Das ist der Stand für **Abnahme 3**. Was nur Studio messen kann (Paket J: Handy-Rundgang, 8 Spieler, MicroProfiler, Nachher-Bilder), steht als Prüfliste am Ende.

Leitbild umgesetzt als: alles Neue läuft **nur auf dem Client**, der Server baut **kein einziges neues Teil** (das Teile-Budget der Plot-Inseln bleibt unverändert). Jedes Paket hat einen eigenen Schalter.

| Paket | Schalter | Aus = |
|---|---|---|
| A Tageslauf | `AmbienceConfig.DAY_CYCLE` | fester Himmel 16,9 Uhr wie bisher |
| B Wasser und Küste | `FeatureFlags.WORLD_B_WATER` | Wasser wie bisher |
| C Hauptinsel | `FeatureFlags.WORLD_C_HUB` | Hauptinsel wie bisher |
| D Plot-Inseln | `FeatureFlags.WORLD_D_PLOTS` | Plot-Inseln wie bisher (das Attribut `IslandStage` setzt der Server trotzdem, es ist harmlos) |
| E Stege und Arena | `FeatureFlags.WORLD_E_ARENA` | Steg und Arena wie bisher |
| F Leben | `FeatureFlags.WORLD_F_LIFE` | keine Bienen, Schmetterlinge, Pfoten; Blumen und Pollen wie bisher |
| G Welt-Momente | `FeatureFlags.WORLD_G_MOMENTS` | Server meldet nichts, Client zeigt nichts |
| H Klang-Kulisse | `FeatureFlags.WORLD_H_SOUND` | still (ohne geprüfte Sound-IDs ist es das ohnehin) |
| I Licht nach Zonen | `FeatureFlags.WORLD_I_ZONES` | überall dasselbe Licht wie bisher |
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
| D: Insel-Deko „zählt ins Teile-Budget, also sparsam“ | – | Die Stufen-Deko baut **nur der Client**. Der Server schreibt bloß das Attribut `IslandStage` an den **Player** (nicht an das Plot-Model: das wird bei jedem Rebirth neu gebaut). Server-Teile pro Insel: weiterhin +0. |
| D: „Honig läuft sichtbar“ am Brunnen | Der Brunnen ist ein Gebäude-Look (Server), der Füllstand eine Neon-Scheibe | Ein Glanzfleck kreist auf der Honig-Oberfläche. Ist der Teich voll (Füllhöhe ≥ 97 %), laufen Tropfen über den Rand. Der Brunnen-Look selbst bleibt unverändert. |
| E: Laternen „an jedem zweiten Pfosten“ | Der äußere Steg hat keine Pfosten (nur Geländer) | 5 kleine Laternenpfosten je Seite auf dem Geländer, zusätzlich zu den 4 Endpfosten aus Paket B. |
| E: Rekord erkennen | Es gibt kein Rekord-Remote an andere Spieler | Der Schau-Turm wird bei einem neuen Rekord neu gebaut, und die Zahl am Ende seines Schilds steigt. Das liest der Client. Fähigkeiten über `SkillFXPlay` (geht an alle) mit `owner`. |
| E: Schau-Turm „steht an der Arena“ | Mit `MAP_V2_SHOWCASE` steht er am Brückenkopf auf der Hauptinsel | Die Flagge sitzt auf dem Turm, wo er steht. Zuschauer und Laternen bleiben an der Arena. |
| F: Pollenfarbe | Pollen gehört zu `AmbienceController` | Die Farbe führt `DayCycleController` nach (eine Kurve `pollenColor`; 16,9 Uhr = bisherige Farbe, Test). |
| F: MicroProfiler mit 8 Spielern | Keine Studio-Sitzung | Aufwand im Code begrenzt (ein Takt, `BulkMoveTo`, Sichtweite). Die Messung bleibt offen. |
| G: vorhandene Meldungen nutzen (`HatchResult`, `TowerUnlocked` …) | `HatchResultReceived`, `RebirthResultReceived` usw. gehen nur an den **Besitzer**, ein `TowerUnlocked` gibt es nicht | Neue gemeinsame Meldung **`WorldMoment`** (an alle). `WorldMomentService` erkennt die Momente aus dem **Spielstand** (Vergleich vorher/nachher bei jeder Datenänderung). So musste kein bestehender Service angefasst werden. Der Text für die Zeile läuft über `Loc` (Schlüssel + Rarity als `LocMsg`). |
| G: Schlüpfen ab Mythic | Fusion erzeugt auch neue Bärchis | Jeder **neue** Bärchi ab Mythic zählt (Schlüpfen und Fusion), Annahme 13. |
| G: „Inverted- oder seltene Mutation“ | Inverted gibt es seit v11 nicht mehr (8 Mutations-Stufen) | Selten = Celestial, Candy, Lava, Galaxy, Rainbow (Gewicht ≤ 400). Auch ein Mutations-Sturm auf eine dieser Stufen zählt. |
| G: Event-Start und Boss | Der Client sieht beides schon (Pit-Ring, Nest; Boss-Himmel macht `EventFXController.setBossSky` für alle) | Event-Start: ohne Server, `HubEventController` meldet den Wechsel auf „läuft“. Boss: unverändert vorhanden (Himmel, Nest-Puls aus C). Kein doppelter Himmel. |
| G: Schalter „Momente anderer Spieler“ | Es gibt **kein Einstellungs-Fenster** (nur Sprache) | Nicht gebaut, wie verlangt. Der Wert steht in `WorldFXConfig.MOMENTS.OTHERS_DEFAULT` (`on`/`small`/`off`), der Controller kann ihn schon. |
| H: Sounds in Studio geprüft | Keine Studio-Sitzung | Alle IDs leer, der Controller ist fertig und bleibt still. **Liste unten zum Eintragen.** |
| I: Atmosphäre je Zone | Die Atmosphäre führt der Tageslauf jeden Takt nach | Zonen setzen nur **Faktoren** (Dichte, Dunst), die der Tageslauf einrechnet. Farbe über einen eigenen Filter `ZoneGrade`. |
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

## Paket D: Plot-Inseln mit Persönlichkeit

**Gebaut:**
- `Modules/IslandStage` (neu, rein): Stufe 1–4 aus geschafften Towern (I/II/III) **oder** Rebirths (1/3/5, passend zu den Rebirth-Deckeln). Es zählt, was weiter ist. Test `island_stage.test.lua` (neu, 12 Prüfungen).
- `PlotDisplayService`: neue Signatur **STUFE**. Bei einem Wechsel `player:SetAttribute("IslandStage", n)` (überlebt jeden Insel-Neuaufbau). Kein Server-Teil.
- `Controllers/PlotLifeController` (neu, 15 Hz):
  - **Stufen-Deko** am Inselrand (Radius 53,5, Steg-Achsen ±25° frei). Stufe 2: 6 Blumengruppen. Stufe 3: + 2 Blumengruppen, 3 Pilzgruppen. Stufe 4: + Bienenhaus und **Bernstein-Stein** (das einzige leuchtende Insel-Teil, glüht mit dem Tageslauf). Deklarativ in `WorldFXConfig.ISLAND_KINDS`/`ISLAND_STAGE_ITEMS`, Neubau nur bei einem Stufenwechsel, aus ab 260 Studs.
  - **Honig-Teich:** Glanzfleck kreist auf der Honig-Oberfläche. Ist er voll, laufen 4 Tropfen über den Rand aufs Beet. Aus ab 120 Studs.
  - **Eigene Insel** (nur der Besitzer sieht es): warmer, halbtransparenter Neon-Ring auf dem Sandsaum (von weitem erkennbar) und warme Lichtpunkte über der Insel (ein Emitter). Auf der eigenen Insel fliegen zusätzlich 2 Bienenschwärme (Paket F).
  - **Leere Insel:** Schild „Freie Insel“ (in 4 Sprachen) mit Bärchi-Bild, 3 Blumengruppen, ein Schmetterling. Keine Gebäude. Verschwindet, sobald ein Spieler kommt.
- `check_decor.py` prüft jetzt auch jede Deko-Art (nichts im Boden, nichts schwebt) und jede Stufe gegen das Budget (Stufe 4: **57 von 60** Client-Teilen).
- `map_layout.test.lua`: jede Stufen-Deko frei von den Steg-Achsen, außerhalb von Beet und Zaun, auf der Insel. Winkel-Konvention geprüft.

**Debug:** `D:Invoke("islandstage", 4)` (1..4, `"auto"` = aus dem Spielstand), `D:Invoke("pondfull")`.

**Teile pro Insel:** Server unverändert (+0), also auch mit Stufe 4 und Look 6 unter 250. Bitte `D:Invoke("parts")` vor und nach `islandstage 4` vergleichen: muss gleich bleiben.

## Paket E: Stege und Arena

**Gebaut** (`Controllers/ArenaLifeController`, neu, 20 Hz nur in Sichtweite, pro besetztem Slot gepoolt):
- **Steg-Laternen:** 5 je Seite auf dem Geländer des äußeren Stegs, gedimmt (Glas, dunkles Bernstein). Startet ein Lauf (Arena-Tafel wird eingeblendet), gehen sie nacheinander vom Plot zur Arena an (0,16 s je Laterne). Nach dem Lauf sind sie wieder aus.
- **Torbogen:** zwei Holzpfosten auf dem Zaunring in der Zaunlücke (7,6 Studs neben der Mitte, also außerhalb des 12er-Stegs und der Geländer), Querbalken auf 9 Studs, leuchtende Wabe oben. Der Laufweg bleibt frei.
- **Zuschauer-Bärchis:** 6 je Arena auf dem Zaun (fern der Steg-Lücke), aus Teilen (Körper, Kopf, Ohren, Arme) in Rot/Grün/Gelb/Blau. Sie hüpfen kurz bei jeder Fähigkeit in dieser Arena (`SkillFXPlay`, `owner`) und jubeln mit Armen hoch, wenn der Lauf einen neuen Rekord bringt. Aus ab 160 Studs.
- **Flagge auf dem Schau-Turm:** Stange und wehende Flagge in der Farbe des Towers (Schildfarbe des Turms), beim Rekord glänzt sie 1,2 s auf (Neon).

**Debug:** `D:Invoke("spectators", "hop")`, `D:Invoke("spectators", "cheer")`, `D:Invoke("record")`. Laternen-Welle: einfach einen Lauf starten (`D:Invoke("fight", uid)`).

**In Studio prüfen:** Läuft der Bärchi ohne Hängenbleiben durch den Bogen? (Alles ist ohne Kollision, es kann also nur optisch eng werden.)

## Paket F: Leben in der Luft und im Gras

**Gebaut** (`Controllers/LifeController`, neu, 15 Hz, alles mit **einem** `BulkMoveTo`):
- **Bienen:** bis zu 6 Schwärme (3–5 Bienen) in Sichtweite, an festen Orten: Wiesen der Hauptinsel (16 Orte), Teich und Inselrand jeder besetzten Plot-Insel. Die nächsten Orte bekommen alle 2 s einen Schwarm, die eigene Insel zuerst und mit 2 Schwärmen extra. Flug als Acht, keine Physik.
- **Schmetterlinge:** 6 auf der Hauptinsel, langsam flatternd (rosa und lavendel), dazu je einer auf jeder freien Insel (Paket D).
- **Blumen im Wind:** Die 46 Server-Blumen der Hauptinsel nicken mit **einer** Windwelle, die über die Insel läuft (7°, 0,35 Hz). Läuft der eigene Charakter hindurch, kippen sie zur Seite weg und richten sich langsam wieder auf. Nur lokal gedreht, nichts wird repliziert.
- **Pollen:** Farbe folgt dem Tageslauf (gold → rosa im Abendrot → kühl-hell in der blauen Stunde).
- **Pfotenabdrücke:** Steht der eigene Charakter auf Sand (`Humanoid.FloorMaterial`), bleibt alle 2,2 Studs abwechselnd links/rechts ein Abdruck, der in 4 s verblasst. Pool von 20.
- **Niedrigste Grafikstufe:** alles aus Paket F aus (nur die Pollenfarbe läuft, der Pollen selbst ist auf niedriger Stufe ohnehin aus).

**In Studio prüfen:** MicroProfiler mit 8 Test-Clients (`WorldFX`-Takte unter `Heartbeat`), Zahl in den Bericht.

---

## Paket G: Die Welt reagiert auf die Spieler

**Gebaut:**
- `Modules/WorldMoments` (neu, rein): `snapshot`/`diff` erkennt aus zwei Spielständen: neuen Bärchi ab Mythic (der seltenste zählt), seltene Mutation, neuen Tower, neuen Rekord (nicht beim allerersten Lauf), Rebirth. `throttle`: je Spieler höchstens **ein großer Moment pro 30 s**, sonst klein. `Queue`: höchstens **ein großer Moment gleichzeitig**, bis zu 4 warten. Wer länger als 12 s wartet, kommt klein. Test `world_moments.test.lua` (neu, 17 Prüfungen, u. a. fünf gleichzeitige Momente laufen nacheinander, nie zwei große zugleich).
- `Services/WorldMomentService` (neu, Server): hängt an `PlayerService.onDataChanged`, Ausgangsstand beim Laden (was schon da war, ist kein Moment). Sendet `Remotes.WorldMoment` an alle: `{ userId, kind, value, number, big }`. Steht in der `GameManager`-Startliste.
- `Controllers/WorldMomentController` (neu, Client, 30 Hz nur solange ein Effekt läuft, alles aus Pools):

| Moment | wer sieht was |
|---|---|
| Bärchi ab **Mythic** | Lichtsäule in der Rarity-Farbe über der Insel (2,4 s). Alle anderen bekommen unten eine Zeile „<Name> hat einen <Rarity>-Bärchi!“ (4 Sprachen). Ab **Cosmic** zusätzlich ein Funkenring am Himmel. |
| **Neuer Tower** | Feuerwerk (3 Raketen, Funken in der Tower-Farbe) vom Schau-Turm. |
| **Neuer Rekord** | Flagge am Schau-Turm glänzt auf, die Zuschauer an der Arena jubeln (Paket E, nur in der Nähe). |
| **Rebirth** | Weiche Lichtwelle über die Insel, die Blumengruppen am Inselrand wiegen sich einmal stark (Paket D). |
| **Event startet** | Die Wabenkrone blinkt zweimal (2 Hz), die Bienen in Sicht fliegen 10 s zum Event-Pit, die Glocke läutet (still ohne geprüfte ID). |
| **Boss kommt** | wie bisher: Himmel leicht dunkler und ockerfarben (`EventFXController`), Nest pulsiert und mehr Wespen (Paket C). |
| **Seltene Mutation** | Funkenspirale um den Bärchi des Spielers, nur in der Nähe (180 Studs). |

- **Regeln eingehalten:** Momente anderer Spieler liegen in der Welt über deren Insel, kein Vollbild-Blitz, kein Farbfilter. Läuft die **eigene Fähigkeiten-Show** (Filter `SkillFX_Sky`), warten große Momente, bis sie vorbei ist (höchstens 12 s, dann klein).

**Debug:**
```lua
D:Invoke("moment", "hatch", "Cosmic")   -- auch: tower II | record | rebirth | mutation Galaxy
D:Invoke("moments5")                    -- fünf große Momente auf einmal → laufen nacheinander
D:Invoke("pitstate", "live")            -- Event-Start-Moment (vorher "idle", damit es ein Wechsel ist)
D:Invoke("neststate", "boss")
```

**In Studio prüfen:** zwei Test-Clients, `moment` beim einen auslösen: Der andere sieht Säule und Zeile, der Auslöser nur die Säule.

## Paket H: Klang-Kulisse

**Gebaut:**
- `Modules/SoundZones` (neu, rein): Gewicht 0..1 je Klang aus der Kamera-Position. **Ufer** (an der Küste und auf dem Wasser), **Wiese** tagsüber / **Grillen** in der blauen Stunde (Inselinneres), **Honigmast** (Tropfen, bis 45 Studs), **Event-Pit** (Stimmengewirr, nur während eines Events), **Wind** an der Arena und stärker in der Höhe. Alle Gewichte sind stetig. `audible` lässt höchstens **3** hörbar. Test `sound_zones.test.lua` (neu): richtige Zone an typischen Orten, Rundgang Mitte → Plot → Arena → Wasser ohne harte Übergänge (≤ 0,1 je Stud), Grillen statt Vögel, nie mehr als 3.
- `Controllers/SoundscapeController` (neu, 5 Hz): eine Schleife je Zone in der Sound-Gruppe `WorldAmbience`, Lautstärke folgt dem Ziel weich (~1,5 s). Ab und zu eine Möwe, wenn das Ufer zu hören ist. Glocke beim Event-Start. **Keine Musik.**
- Lautstärken (`WorldFXConfig.SOUND_VOLUME`): alle zwischen 0,06 und 0,1, also unter Zuschauer-Kampf (0,12) und Besitzer-Kampf (0,35).

**Sound-Liste (bitte in Studio prüfen und eintragen):** `WorldFXConfig.SOUNDS`

| Schlüssel | wofür | Art | ID |
|---|---|---|---|
| `waves` | Ufer | Schleife | **leer, bitte eintragen** |
| `gull` | Möwe am Ufer | Einzelklang | leer |
| `meadow` | Wiese tagsüber (Summen, Vögel) | Schleife | leer |
| `crickets` | Wiese in der blauen Stunde | Schleife | leer |
| `drip` | Honigmast | Schleife | leer |
| `crowd` | Event-Pit während eines Events | Schleife | leer |
| `wind` | Arena, Turm | Schleife | leer |
| `bell` | Event-Start (G) | Einzelklang | leer |
| `waspHum` | Wespen-Nest (C, positional am Nest) | Schleife | leer |

Vorgehen: Toolbox → Audio → kostenlos, in Studio anhören, ID als `"rbxassetid://…"` eintragen. Ein leerer Eintrag bleibt still, es entsteht dann keine Sound-Instanz.

## Paket I: Licht-Feinschliff nach Zonen

**Gebaut** (`Controllers/ZoneLightController`, neu, 10 Hz):
- **Insel:** wie bisher (Filter neutral).
- **Steg zur Arena und Arena:** Sättigung +0,08, Kontrast +0,07, Helligkeit +0,01 über den eigenen Filter `ZoneGrade`, weiche Kante (15 Studs), Übergang ~1,5 s.
- **Hoch oben auf dem Turm** (Kamera ab Etage 30 = 72 Studs, voll ab Etage 60): Dichte der Atmosphäre ×0,55, Dunst ×0,45, also klarer und mit weiterem Horizont. Der Tageslauf rechnet die Faktoren ein. Ist er aus, setzt der Controller die festen Werte mal Faktor.
- **Boss:** wie G (vorhandener Boss-Himmel).
- **Reihenfolge:** Roblox stapelt alle Farbfilter. `SkillFX_Sky` (Show) und `BossSky_Local` färben unverändert, `ZoneGrade` hebt nur Kontrast/Sättigung. Kein Filter überschreibt einen anderen, die Show verliert ihren Farbfilter also nie.
- **Nicht eingebaut:** Tiefenunschärfe und andere teure Effekte, auch nicht für PC.

## Paket J: Qualität, Messung, Abschluss

Was in der Cloud ging, ist erledigt: Qualitätsregler-Tabelle (unten, vollständig), alle Prüfungen grün, keine Zyklen zwischen den Client-Controllern (geprüft), jede Funktion mit Schalter und Qualitätsstufe. **Was Studio braucht, als Prüfliste:**

1. **Einspielen** (Heim-PC: `make_update_rbxmx.py 52f75c1`, oder pro Paket ab dem jeweiligen Commit). Output ohne Fehler, diese Zeilen müssen kommen: `[DayCycle] an`, `[Water] aktiv`, `[Hub] Wahrzeichen aktiv`, `[HubEvents] aktiv`, `[PlotLife] aktiv`, `[ArenaLife] aktiv`, `[Life] aktiv`, `[WorldMoments] aktiv`, `[Soundscape] still …`, `[ZoneLight] aktiv`, Server: `[WorldMomentService] Initialisiert`.
2. **Grundablauf:** Welt baut, Plot spawnt, Tower-Lauf, Event, Ei legen/einsammeln, keine doppelten Skripte.
3. **Teile:** `D:Invoke("parts")` vor und nach `islandstage 4`: gleich (Server +0).
4. **Handy:** Studio → Geräte-Emulation (kleines Handy), Grafikstufe 1: Rundgang und Tower-Lauf. Erwartet: Tageslauf, Licht, Glitzern, Krone, Wegweiser, Pit-Rahmen, Insel-Stufen; **aus** sind Glühwürmchen, Sterne, Fisch, Wespen, Bienen, Schmetterlinge, Blumen-Wind, Pfoten, Zuschauer, Funkenring. Ruckelt etwas, in `WorldFXConfig.MIN_QUALITY` auf 1 setzen.
5. **8 Spieler:** Test → Server + 8 Clients, MicroProfiler (Strg+F6) auf einem Client, Bildzeit und die Heartbeat-Anteile der Controller notieren, `#workspace.WorldFX_Local:GetDescendants()` im Client-Kontext. Vorher/Nachher: einmal alle Schalter A–I aus, einmal an.
6. **Nachher-Bilder:** `worldshots 1..6` → `claude/screens/welt_nachher/`, neben die Vorher-Bilder.

---

## Dateien je Paket (für `make_update_rbxmx.py`)

| Paket | neu | geändert |
|---|---|---|
| 0 + Grundlage | `Config/WorldFXConfig`, `Controllers/WorldFXKit`, `Controllers/WorldShotController`, `tools/textures/make_world_textures.py` | `Services/DebugService`, `Modules/MapLayout`, `Main.client`, `map_layout.test.lua` |
| A | `Modules/DayCycle`, `Controllers/DayCycleController`, `day_cycle.test.lua`, `assets/world/paket_a/*` | `Config/AmbienceConfig`, `Main.client` |
| B | `Controllers/WaterController`, `assets/world/paket_b/*` | `Controllers/AmbienceController`, `Config/FeatureFlags`, `Main.client` |
| C | `Controllers/HubLandmarkController`, `HubEventController`, `ArrivalController`, `assets/world/paket_c/*` | `Strings/{de,en,fr,es}`, `Config/FeatureFlags`, `Main.client` |
| D | `Modules/IslandStage`, `Controllers/PlotLifeController`, `island_stage.test.lua` | `Services/PlotDisplayService`, `Services/DebugService`, `Config/WorldFXConfig`, `Config/FeatureFlags`, `Modules/MapLayout`, `Main.client`, `check_decor.py`, `map_layout.test.lua` |
| E | `Controllers/ArenaLifeController`, `assets/world/paket_e/*` | `Main.client`, `make_world_textures.py` |
| F | `Controllers/LifeController`, `assets/world/paket_f/*` | `Controllers/DayCycleController`, `Main.client`, `day_cycle.test.lua` |
| G | `Modules/WorldMoments`, `Services/WorldMomentService`, `Controllers/WorldMomentController`, `world_moments.test.lua` | `Network/Remotes` (`WorldMoment`), `Core/GameManager` (Startliste), `Services/DebugService`, `Strings/*`, `Config/WorldFXConfig`, `Config/FeatureFlags`, `ArenaLife`/`PlotLife`/`Life`/`HubLandmark`/`HubEvent`/`DayCycle`-Controller (kleine Einstiege), `Main.client` |
| H | `Modules/SoundZones`, `Controllers/SoundscapeController`, `sound_zones.test.lua` | `HubEventController`, `WorldMomentController`, `Config/WorldFXConfig`, `Main.client` |
| I | `Controllers/ZoneLightController` | `DayCycleController`, `Config/WorldFXConfig`, `Main.client` |

Server-Dateien: `DebugService` (Befehle, nur in Studio aktiv), `PlotDisplayService` (Attribut `IslandStage` am Player), `WorldMomentService` (neu, nur Meldungen), `GameManager` (Startliste), `Remotes` (ein neues S→C-Event). **Kein MapBuild-Builder geändert, keine Datenstruktur geändert, keine Balance-Zahl geändert.**

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
| `paket_e/flag_fabric.png` | 256 | Muster auf der Schau-Turm-Flagge (Farbe vom Teil) | einfarbiger Stoff |
| `paket_f/paw_print.png` | 256 | Pfotenabdruck im Sand | flache dunkle Ellipse |

Für D gibt es bewusst keine Texturen: Blumen, Pilze, Bienenhaus und Stein sind Formen und sehen ohne Upload fertig aus. Weggelassen gegenüber dem Prompt: Laternenglas (Neon + Glas reicht), Zuschauer als Bild (aus Teilen gebaut, Annahme 9), Schmetterling/Blütenblatt als Flipbook (Teile-Flügel).

**Hochladen (wenn du willst, erst nach der Studio-Vorschau):** Studio → Asset Manager → Bulk Import → Ordner `assets/world/paket_a` bis `paket_f` (Typ Image). Die IDs als `"rbxassetid://…"` in `src/shared/Config/WorldFXConfig.luau` → `TEXTURE_IDS` beim gleichnamigen Schlüssel eintragen. Vorschau ohne Upload: das PNG in Studio als Decal auf ein Testteil ziehen (Studio lädt es dabei als temporäres Asset).

## Sounds

Siehe Paket H: neun Plätze, alle **leer**, bis eine ID in Studio geprüft ist. Ohne ID ist alles still und es entsteht keine Sound-Instanz.

## Messwerte

| | vorher | nachher | wie |
|---|---|---|---|
| Server-Teile pro Plot-Insel | 191–209 | **unverändert** | kein Server-Builder geändert. Bitte mit `D:Invoke("parts")` bestätigen |
| Client-Teile Hauptinsel (C) | 0 | ≈ 290 (Krone 16, Faden 6, Wegweiser 80, Händler 6, Tafeln 72, Pit-Rahmen 88, Nest 15, Bienen 18) | gezählt im Code. Bis auf die Krone alles mit Distanz-Abschaltung |
| Client-Teile Wasser (B) | 0 | Bojen 24, Fisch 7, je besetzter Arena 9 (max. 72) | ebenso |
| Emitter (neu) | 0 | 5 (Glühwürmchen, Sterne, Schleier, Spritzer, Blasen); niedrige Qualität: 2 | |
| Takte (Heartbeat) | – | DayCycle 5 Hz, Water 30 Hz, Hub 20 Hz, HubEvents 20 Hz, Culling 2 Hz | kein Thread pro Objekt |
| Client-Teile Plot-Inseln (D) | 0 | je Insel nach Stufe 0/24/50/57; eigene Insel +1 Ring; leere Insel 17 | `check_decor` |
| Client-Teile Arena (E) | 0 | je besetzter Arena 20 Laternen + 4 Bogen + 36 Zuschauer, Flagge 2 | im Code gezählt, Sichtweite |
| Client-Teile Leben (F) | 0 | Bienen bis 80 (8 Schwärme × 5 × 2), Schmetterlinge 12, Pfoten 20 | Pool |
| Emitter D–F | 0 | 1 (Lichtpunkte über der eigenen Insel) | |
| Takte D–F | – | PlotLife 15 Hz, ArenaLife 20 Hz (+ 4 Hz Zustand), Life 15 Hz | je ein Takt |
| Client-Teile Momente (G) | 0 | Pool: 1 Säule, 1 Welle, 48 Funken | nur während eines Moments in der Welt |
| Takte G–I | – | Momente 30 Hz (nur aktiv), Klang 5 Hz, Zonen-Licht 10 Hz | je ein Takt |
| Netzwerk (G) | – | ein `WorldMoment` je Moment an alle, je Spieler gedrosselt (30 s groß) | kein Takt |
| MicroProfiler | – | **offen (Studio, Paket J Schritt 5)** | |

## Qualitätsregler (vollständig, A–I)

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
| Insel-Stufen | 0 | | Zuschauer | 1 |
| Teich-Glanz, Überlauf | 1 | | Schau-Turm-Flagge | 0 |
| Eigene Insel | 0 | | Bienen, Schmetterlinge | 1 |
| Leere Insel | 0 | | Blumen im Wind | 1 |
| Steg-Laternen | 0 | | Pollenfarbe | 0 |
| Torbogen | 0 | | Pfotenabdrücke | 1 |
| Welt-Momente | 0 | | Funkenring (ab Cosmic) | 1 |
| Event-Start (Krone, Bienen) | 0 | | Klang-Kulisse | 0 |
| Licht nach Zonen | 0 | | | |

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
| 9 | Zuschauer-Bärchis aus Teilen (6 Teile je Bärchi), nicht als Bild: sehen aus jedem Winkel gleich aus und brauchen keinen Upload | `ArenaLifeController.buildSpectators` |
| 10 | Insel-Stufe: Tower I/II/III geschafft **oder** 1/3/5 Rebirths | `WorldFXConfig.ISLAND_STAGE` |
| 11 | Teich gilt als voll ab 97 % Füllhöhe | `POND_LIFE.FULL_RATIO` |
| 12 | Bienen: 6 Schwärme in Sicht + 2 auf der eigenen Insel | `WorldFXConfig.BEES` |
| 13 | Welt-Moment „Bärchi“: jeder neue ab **Mythic** (auch aus Fusion), Funkenring ab **Cosmic** | `MOMENTS.HATCH_MIN_RARITY`, `RING_MIN_RARITY` |
| 14 | Seltene Mutation = Celestial, Candy, Lava, Galaxy, Rainbow | `MOMENTS.RARE_MUTATIONS` |
| 15 | Rekord-Moment erst ab dem zweiten Lauf in einem Tower (der erste ist kein „Rekord“) | `WorldMoments.diff` |
| 16 | Schlange: 4 warten, 0,6 s Pause, nach 12 s klein | `MOMENTS.QUEUE_*`, `MAX_WAIT` |
| 17 | Arena-Licht: Sättigung +0,08, Kontrast +0,07; Turm ab Etage 30 klarer | `WorldFXConfig.ZONE_LIGHT` |

## Offen und bekannt

- **Alles Sichtbare ist ungetestet in Studio.** Bitte als Erstes: Welt baut, Plot spawnt, Tower-Lauf, Event, Ei legen und einsammeln, Output ohne Fehler (`[DayCycle] an`, `[Water] aktiv`, `[Hub] Wahrzeichen aktiv`, `[HubEvents] aktiv`, `[PlotLife] aktiv`, `[ArenaLife] aktiv`, `[Life] aktiv`).
- Die Typprüfung (`--!strict`) macht nur Studio. Lokal: Syntax aller Dateien, alle Lua-Tests und Prüfskripte grün.
- Screenshots `welt_vorher/`, `welt_nach_C/` und `welt_nach_F/` fehlen (keine Studio-Sitzung).
- Die Blumen der Hauptinsel sind Server-Teile, die der Client nur lokal dreht. Würde der Server sie je neu setzen, springen sie für einen Takt zurück. Heute setzt er sie nie.
- `make_update_rbxmx.py` fehlt im Repo: Update-Datei am Heim-PC bauen.
- Sound-IDs fehlen (H läuft still), Textur-IDs fehlen (alles mit Rückfall).
- Kein Einstellungs-Fenster: „Momente anderer Spieler“ nur über die Config.
- `claude/CONTEXT_BRIEFING.md` fehlt im Repo. Der neue Abschnitt 2 steht unten fertig zum Einfügen.

## Für `claude/CONTEXT_BRIEFING.md`, Abschnitt 2 „Die Welt“ (zum Einfügen)

> **Die Welt (Stand 09.10.2026, „Welt aufwerten“).** Hauptinsel mit Event-Pit und Honigmast in der Mitte, 8 Plot-Inseln auf Radius 212, je eine Arena-Insel dahinter, Wasser bis Radius 650. Der Server baut die feste Welt (`WorldBuilder`, `ScenicBuilder`, `SkyBuilder`) und pro Spieler Plot, Gebäude, Arena (≤ 250 Teile je Insel). **Alles Lebendige ist reine Client-Optik** in `StarterPlayerScripts/Controllers`, gebaut in `workspace.WorldFX_Local`, Zahlen in `Config/WorldFXConfig`, Bausteine in `WorldFXKit` (Qualität, Pools, Distanz-Abschaltung):
> - `DayCycleController`: Tageslauf 14,5–19 Uhr in 20 min aus der Serverzeit (`Modules/DayCycle`), Licht/Atmosphäre/Bloom/Pollen als Kurven, Leuchten von Laternen und Krone; hält bei Fähigkeiten-Shows an. Schalter `AmbienceConfig.DAY_CYCLE`.
> - `WaterController` (Glitzern, Schaum, Arena-Küste, Fisch, Bojen), `HubLandmarkController` (Wabenkrone, Honigfaden, Wegweiser, Händler-Deko, Tafelrahmen), `HubEventController` (Pit-Rahmen Ruhe/bald/läuft, Wespen-Nest), `ArrivalController` (Ankunft).
> - `PlotLifeController`: Insel-Stufen 1–4 (Server-Attribut `IslandStage` am Player, `Modules/IslandStage`), Teich-Glanz, eigene Insel, leere Inseln. `ArenaLifeController`: Steg-Laternen, Torbogen, Zuschauer, Flagge. `LifeController`: Bienen, Schmetterlinge, Blumen im Wind, Pfoten.
> - `WorldMomentController` + Server `WorldMomentService` (`Remotes.WorldMoment`, `Modules/WorldMoments`): große Momente für alle, gedrosselt.
> - `SoundscapeController` (`Modules/SoundZones`, still ohne geprüfte IDs), `ZoneLightController` (Arena-Kontrast, klare Luft oben).
> - Schalter `FeatureFlags.WORLD_B_WATER` … `WORLD_I_ZONES`; Qualitätsstufen `WorldFXConfig.MIN_QUALITY`; Studio-Debug `worldshots`, `daytime`, `pitstate`, `neststate`, `islandstage`, `moment`, `moments5` u. a. (siehe `DebugService`-Kopf).

## Prüfungen (alle grün)

`luau-compile --null` für alle `.luau` · `check_locals` (Höchstwert MapConfig 191, unverändert) · `guide_steps`, `unlock_rules`, `boss_tiers` · `run_local.py` für `combat_rating`, `gold_rules`, `map_layout` (erweitert), `live_board`, `event_schedule`, `egg_press`, `honey_pond`, `shop`, `migration_hbb`, `endless`, **`day_cycle` (neu)**, **`island_stage` (neu)**, **`world_moments` (neu)**, **`sound_zones` (neu)** · alle Sims unter `tools/sim` · `check_feedback`, `check_members`, `check_consistency`, `check_loc`, `check_decor` (erweitert um die Insel-Stufen).
