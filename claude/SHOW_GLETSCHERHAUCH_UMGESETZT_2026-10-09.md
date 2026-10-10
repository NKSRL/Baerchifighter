# Show „Gletscherhauch“ (Gletscher-Bärchi): UMGESETZT (2026-10-09)

Prompt 1 aus `OPUS_PROMPT_FAEHIGKEITEN_SHOW_2026-10-08.md`. Neu ist nur die **Show** von `GlacierFrost` (SkillConfig: „Gletscherhauch“, Typ `Slow`, 40 % für 3 Aktionen). Wirkung im Kampf, `SkillConfig` und `CombatCalculator` sind unverändert.

**Nicht in Studio getestet.** Diese Sitzung lief in der Cloud, ohne Studio und ohne Blender. Bitte vor dem Veröffentlichen einmal abspielen (siehe unten).

## Ablauf (volle Show, 3,6 s, Stufe 3)

| Zeit | Phase | Was passiert | Wer sieht es |
|---|---|---|---|
| 0,00 | Aufladen | Himmel kühlt zu blassem Blaugrau ab (`sky`, Sättigung −0,45) | nur Besitzer |
| 0,00 | | Atemwolke vor dem Maul, zwei Atemstöße (`breath`) | alle (Beiwerk) |
| 0,10 | | Boden friert im Kreis (r 6), Reif-Adern verzweigen sich nach außen (`groundmark`) | alle |
| 0,45 | | kleine Eiskristalle auf Ohren und Schultern, jede Kante leuchtet einmal weiß auf (`frost` + `perch`/`glint`) | alle (Beiwerk) |
| 1,30 | Schlag | Aufstampfen: kleiner Frostring am Boden, kurzes Kamerawackeln, dumpfer Ton | Ring alle, Wackeln Besitzer |
| 1,35 | | Zickzack-Riss läuft in 0,45 s über den Boden zum Gegner (`crack`) | alle |
| 1,40 | | 7 schräge Eisdornen brechen nacheinander entlang des Risses aus, jeder höher (1,0 → 3,4 Studs), jeder blitzt einmal weiß auf (`spikes`) | alle |
| 2,25 | Einschlag | letzter Dorn am Gegner. Kristalle wachsen von den Füßen bis zur Hüfte (`frost` + `legs`), Zeitlupe 0,35 s, Glas-Ton | Kristalle alle, Zeitlupe Besitzer |
| 2,28 | | flacher Frostring läuft über den Boden nach außen (r 11) | alle |
| 2,45 | Nachglühen | Reifschimmer um den Gegner, Schneeflocken sinken langsam herab (`snowfall`) | alle (Beiwerk) |

Der Treffer liegt fest bei **2,25 s** (`impactAt`). `fight_timeline` meldet `GlacierFrost 2.25/3.6`.

**Echo** (ab dem 2. Einsatz im Lauf, 0,55 s): Aufstampfen (kleiner Ring und Ton), kurzer Zickzack-Riss, Kristalle an den Beinen des Gegners und Glas-Ton. Kein Himmel, keine Zeitlupe, keine Dornen.

**Ton:** `charge = whoosh` (Atem), `strike = boom` (Aufstampfen), `impact = glass` (Eis). Alle drei stehen schon in der `SOUND_LIBRARY` und wurden im Mega-Egg-Tree-Paket in Studio geprüft. Die Lautstärken kommen aus `SkillFXConfig.SOUND`, Tonhöhe 0,8.

## Status-Effekt (Reifschimmer, solange die Verlangsamung wirkt)

**Geht mit dem jetzigen Baukasten nicht.** Der Client bekommt nur `SkillFXPlay` (`owner`, `skillId`, `full`, Modelle, Mitte). Er erfährt nicht, wie lange die Verlangsamung dauert, und auch nicht, wann sie endet. Deshalb gibt es Reifschimmer und Schneeflocken wie gewünscht nur in der Einschlag-Phase (etwa 1,2 s).

Für einen dauerhaften Status-Effekt wäre nötig:
1. **Server:** `CombatService`/`FightTimeline` müssten je Zug mitschicken, ob der Gegner noch verlangsamt ist. Das ginge zum Beispiel über ein neues Feld `enemyStatus = { slow = true }` in `Types.FightBeat`, abgeleitet aus dem Runden-Log (`effects`).
2. **PitArenaService:** Wechselt der Status, ein Remote wie `SkillFXStatus:FireAllClients({ target = enemy, status = "slow", on = true/false })` senden.
3. **Client:** ein neuer Baustein `status`, der eine Hülle und einen Emitter am Gegner hält, bis `on = false` kommt, der Gegner verschwindet oder die Stage wechselt. Dazu ein Aufräumen pro Gegner-Modell.

Ich habe das nicht gebaut, weil es Server-Protokoll und Kampf-Wiedergabe ändert.

## Neue und erweiterte Bausteine (wiederverwendbar, dokumentiert in `SkillFXConfig`)

- `breath`: Atemwolke vor dem Maul, 2 Stöße, **1 Emitter**
- `groundmark`: Bodenkreis plus Reif-Adern (Adern sind Beiwerk)
- `crack`: Zickzack-Riss von self zu target. Merkt sich die Linie für `spikes`.
- `spikes`: Dornen-Welle entlang des Risses, jeder Dorn höher
- `snowfall`: Reifschimmer-Hülle plus sinkende Flocken, **1 Emitter**
- `frost`: neue Parameter `legs` (Füße bis Hüfte), `perch` (Ohren `ear_left`/`ear_right` und Schultern; ohne benannte Teile wird über die Bounding-Box geschätzt) und `glint`
- `ring`: neuer Parameter `ground` (flach auf dem Boden unter der Figur)
- Für jeden Schritt: `extra = true` (Beiwerk) und `tex = "<key>"` (Bild mit Rückfall)
- Für jeden Eintrag: `echo` (eigene Echo-Liste) und `impactAt` (jetzt auch im Typ)
- `PARTICLE_BUDGET.EXTRAS_MIN = 0.5` und die Tabelle `TEXTURES`

Die anderen 27 Shows laufen unverändert. Ohne `echo` gilt das alte Echo, und `ring` ohne `ground` verhält sich wie bisher.

## Effekt-Regeln

- Alle neuen Teile: anchored, ohne Collide, Query, Touch und Schatten (`newPart`/`prepPart`). **Keine** Light-Instanz in den neuen Bausteinen. Das Leuchten kommt über Neon und Ice.
- Höchstens 1 Emitter pro Effekt (`breath`, `snowfall`).
- Kein Thread pro Objekt: Dornen, Riss-Stücke, Adern und Kristalle wachsen und verblassen über Tweens mit `delayTime`. Pro Baustein gibt es höchstens ein `task.delay` (zweiter Atemstoß).
- Jedes Teil hat ein `Debris`-Ende (spätestens etwa 3,4 s nach Start). Bricht der Lauf ab, verschwindet alles von selbst. Verlässt der Spieler den Server, gehen die Teile mit seinem Client, denn alles ist nur lokal.
- Positionen: Füße = Mitte der Bounding-Box minus halbe Höhe, Richtung = waagerecht von self zu target. Es gibt keine Arena-Bodenhöhe, die Show stimmt also auf dem Tower in jeder Höhe.
- Flackern: jede Kante bzw. jeder Dorn leuchtet genau **einmal** auf (0,16 bis 0,2 s hin und zurück). Zeitlupe und Wackeln kommen je einmal. Nichts wiederholt sich öfter als 3-mal pro Sekunde.

## Teile und Emitter (volle Show, Besitzer)

| Grafikstufe | Faktor | Teile (ca.) | Emitter |
|---|---|---|---|
| hoch (7 bis 10) | 1,0 | 59 (Boden 1 + Adern 14, Ohr/Schulter 8, Atem-Anker 1, Ringe 2, Riss 7, Dornen 7, Bein-Kristalle 14, Schnee-Anker + Hülle 2, Ton-Anker 3) | 2 |
| mittel (4 bis 6) | 0,65 | etwa 50 (weniger Adern und Kristalle) | 2 |
| niedrig (1 bis 3) | 0,35 | etwa 23 (kein Atem, keine Adern, keine Ohr-Kristalle, kein Schneefall, kein Glitzern; mindestens 4 Dornen und 6 Bein-Kristalle) | 0 |

Zuschauer bekommen ×0,6. Beiwerk sehen sie nur auf hoher Grafikstufe. Den Kern (Boden, Riss, Dornen, Kristalle, Ringe) sehen sie immer.
Echo: etwa 15 Teile, kein Emitter.

## Texturen

`assets/vfx/glacier_frost/`: `breath.png`, `veins.png`, `crack.png`, `spike.png`, `frostring.png`, `flake.png`, dazu `preview.png` als Kontaktbogen.

**Abweichung:** Hier gab es kein Blender. Die Bilder sind deshalb mit `tools/render_vfx_glacier.py` (Pillow) prozedural gezeichnet: weiß bzw. hell auf transparentem Grund, damit sie sich über `Decal.Color3`/`ParticleEmitter.Color` einfärben lassen. Wenn du sie in Blender neu zeichnest, lass Namen und Größen gleich.

**Upload (ging aus der Sitzung nicht):**
1. In Studio: Asset Manager → Bulk Import → die 6 PNGs (nicht `preview.png`).
2. Jedes Bild einmal als Decal in eine Testszene legen und ansehen.
3. Die Bild-IDs (rechte Maustaste → Copy Asset ID) in `src/shared/Config/SkillFXConfig.luau` eintragen, Tabelle `TEXTURES.GlacierFrost`: `breath`, `veins`, `crack`, `spike`, `frostring`, `flake`. Dort steht jetzt überall `0`.

Ohne ID (0) läuft der Rückfall: Neon- und Ice-Teile, Adern als Neon-Striche, Atem mit `rbxasset://textures/particles/smoke_main.dds`, Schnee mit `rbxasset://textures/particles/sparkles_main.dds`. Beide sind eingebaute Roblox-Texturen. **Annahme:** Sie laden, ich konnte das hier nicht prüfen.

## Annahmen (änderbar)

- **Sounds:** `strike` ist jetzt `boom` (Aufstampfen) statt `glass`, `glass` sitzt auf dem Einschlag. Neue Klänge gibt es nicht.
- **Dorn-Form:** `CornerWedgePart` mit Ice-Material (Facetten ohne Mesh). Ein `spike`-Bild liegt als Decal auf der Vorderseite.
- **Decal-Ausrichtung** des Riss-Bilds auf den Riss-Stücken (`Top`-Fläche) ist ungeprüft. Steht es quer, `crack.png` um 90° drehen.
- **Idle-Wippen:** Die Figuren wippen leicht. Die Füße werden zum Start der Show gemessen, die Effekte können also bis zu `IDLE_BOB_HEIGHT` über dem Boden schweben.
- **Sehr kurze Distanz:** Stehen die Kämpfer sehr nah beieinander, rücken die Dornen eng zusammen. Mindestens 4 Dornen bleiben.

## Abspielen und prüfen

**Im PIT (echter Ablauf):** Gletscher-Bärchi holen und in einen Lauf schicken. Der 1. Einsatz zeigt die volle Show, jeder weitere das Echo.
```lua
local D = game.ServerScriptService.RBLDebug
D:Invoke("add", "GlacierBaerchi", 20)
D:Invoke("skilltest", "GlacierBaerchi", 20)   -- Runden-Log: wann Gletscherhauch kommt
```
`skilltest` rechnet nur den Kampf (Runden-Log, `skillUses`), es spielt keine Show ab.

**Show direkt abspielen** (Play-Modus, Befehlsleiste auf **Client** umstellen):
```lua
local SFX = require(game.Players.LocalPlayer.PlayerScripts.Controllers.SkillFXController)
local me = game.Players.LocalPlayer
-- volle Show (ohne Gegner: Ziel 8 Studs vor dir)
SFX.play({ owner = me.UserId, skillId = "GlacierFrost", full = true, attacker = me.Character })
-- Echo
SFX.play({ owner = me.UserId, skillId = "GlacierFrost", full = false, attacker = me.Character })
```
Mit Gegner: `target = workspace...` (ein beliebiges Model) zusätzlich angeben.
Niedrige Grafikstufe prüfen: Esc → Einstellungen → Grafikqualität manuell auf 1 bis 3.

## Tests (alle grün)

- Syntax: alle `.luau` unter `src/` (`luau-compile --null`)
- `check_locals` (höchster Wert 191, MapConfig, unverändert)
- `guide_steps`, `unlock_rules`, `boss_tiers`
- `combat_rating`, `gold_rules`, `map_layout`, `live_board`, `event_schedule`, `egg_press`, `honey_pond`, `shop`, `migration_hbb`, `endless`
- Sims: `progression_pacing`, `tower_calibration`, `egg_tree_check` (eigene Komposition, Dauer ≤ Stufe, Sound-Slot), `fight_timeline` (Treffer vor Show-Ende), `path_balance`
- `check_feedback`, `check_members` (keine Funde), `check_consistency`, `check_loc`, `check_decor`
- Lokalisierung: keine neuen Texte. Der Name kommt weiter aus `skill.GlacierFrost.name`.

## Nicht hier verfügbar / offen

- `claude/CONTEXT_BRIEFING.md` und `tools/make_update_rbxmx.py` liegen nicht im Repo (nur auf dem Heim-PC?). Die Effekt-Regeln habe ich aus dem Prompt übernommen. **Ein Update-rbxmx konnte ich nicht bauen.** Geänderte Skripte für Studio (Option B, von Hand einfügen):
  - `ReplicatedStorage/Config/SkillFXConfig` ← `src/shared/Config/SkillFXConfig.luau`
  - `StarterPlayer/StarterPlayerScripts/Controllers/SkillFXController` ← `src/client/Controllers/SkillFXController.luau`
- Studio-Playtest, Sound-Check und Textur-Vorschau stehen noch aus.
