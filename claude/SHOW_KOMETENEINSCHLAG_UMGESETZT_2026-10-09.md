# Show „Kometeneinschlag“ (Kometen-Bärchi): UMGESETZT (2026-10-09)

Prompt 3 aus `OPUS_PROMPT_FAEHIGKEITEN_SHOW_2026-10-08.md`. Neu ist nur die **Show** von `CometImpact` (SkillConfig: Typ `Opener`, erster Einsatz 4,5× ATK, spätere 1,6×). Die Wirkung im Kampf ist unverändert.

**Nicht in Studio getestet.** Die Sitzung lief in der Cloud, ohne Studio und ohne Blender.

## Ablauf (volle Show, 5,0 s, Stufe 4)

| Zeit | Phase | Was passiert | Wer sieht es |
|---|---|---|---|
| 0,00 | Aufladen | Himmel wird in **1 s** zur Nacht (`sky`, `fade = 1.0`, Nachtblau) | nur Besitzer |
| 0,00 | | Sterne gehen an (`starfield`, `ownerOnly`) | nur Besitzer |
| 0,25 | | Dunkler Schattenkreis um den Gegner, wächst beschleunigt mit (`shadow`) | alle |
| 0,30 | | Hoch oben (90 Studs) funkelt ein Punkt, wird 1,2 s lang größer und heller. Er pulsiert 2× pro Sekunde, also unter der 3/s-Grenze. | alle |
| 1,50 | Schlag | Der Komet fällt: glühender orangener Kopf, weißer Kern, langer Schweif (Orange → Violett), Funken lösen sich vom Schweif | alle |
| ~1,8 | | Er bricht durch die Wolkendecke (45 Studs), Wolkenfetzen stieben auseinander | alle (Beiwerk) |
| 1,50 bis 3,10 | | Kamera folgt schräg von hinten (`cinematic`, neuer Stil `chase`), 1,6 s, springt danach zurück | nur Besitzer |
| 2,10 bis 2,40 | | Zeitlupe: Der Komet wird auf den letzten 18 % des Wegs langsamer, dazu `hitstop`. Der Schatten ist jetzt so groß wie die Turmspitze (r 26, um die Arena-Mitte). | Bild: Besitzer; Komet und Schatten: alle |
| 2,40 | Einschlag | weißer Blitz (0,35 s, einmal) und Kamerawackeln | nur Besitzer |
| 2,40 | | Krater: strahlenförmige Glut-Risse auf dunkler Brandfläche (`crater`) | alle |
| 2,42 | | Schockwelle läuft flach vom Gegner bis zum **Arena-Zaun** (`ring` + `toArena`, `radius = "fence"`) | alle |
| 2,42 | | 16 Trümmerbrocken fliegen im Bogen nach außen und landen (`shards` + `arc`) | alle |
| 2,45 | | Sternstaub im Bogen (`dust`) | alle (Beiwerk) |
| 2,6 bis 4,8 | | Krater glüht von Orange nach Violett aus und verblasst | alle |

Der Treffer der Show liegt bei **2,4 s** (`impactAt`). `fight_timeline` meldet `CometImpact 2.40/5.0`.

**Echo** (0,65 s): Komet aus 40 Studs, sofort im Fall (0,3 s, ohne Funkeln, Nacht und Kamera), danach ein kurzer glühender Krater.

**Ton:** `charge = rumble`, `strike = rocket` (Fallbeginn), `impact = boom`. Alle aus der geprüften `SOUND_LIBRARY`.

## Prüfung: Stage 1 und hoher Einstieg (Turm)

- **Stage 1 (flacher Turm):** Etage 0 ist die normale Kampffläche mit demselben Radius (`PIT_TOWER_RADIUS = PIT_RADIUS = 26`). Alle Positionen kommen aus den Kämpfern (Füße aus der Bounding-Box) bzw. aus der Arena-Mitte, die `PitArenaService` als `center` mitschickt (Mitte zwischen den Kämpfern = Turmmitte). Schatten und Schockwelle passen also auf jede Etage.
- **Einstieg auf hoher Stage:** In `startPlayback` wächst der Turm mit `rideTower` **komplett, bevor** die erste Stage beginnt. Die Show kann erst in der Stage-Schleife kommen, eine Überschneidung mit dem Wachsen ist also ausgeschlossen.
- **Wachsen zwischen den Stages:** Der Turm wächst zu Beginn der nächsten Stage um eine Etage. Der Server wartet die ganze Show ab (5,0 s), dann kommen Stoß und Umkippen. Alle Effekte der vollen Show sind spätestens bei **4,8 s** weg, die Kamera ist bei 3,1 s zurück. Beim Echo ist der Krater nach etwa 0,95 s weg. Im ungünstigsten Fall (Tempo 0,4, Sieg im ersten Zug) wächst der Turm schon bei etwa 0,86 s. Dann liegt der Krater für 0,1 s **unter** der neuen Etage und ist nicht zu sehen. Er schwebt nie in der Luft.

## Wichtig: Der Schaden kommt erst nach der Show im Balken

Wie beim Seraphen-Segen: `PitArenaService` setzt die HP-Balken erst im wuchtigen Stoß **nach** der Show, also bei 5,0 s + 0,28 bis 0,69 s. Der Komet schlägt aber bei 2,4 s ein. Dazwischen liegen etwa 2,9 bis 3,3 s, in denen der Krater ausglüht, und danach rennt der Bärchi noch los und stößt.

Bei einer Schadens-Show fällt das deutlich mehr auf als bei der Heilung. Ich habe es nicht geändert, weil der Prompt nur die Komposition erlaubt. Vorschlag (kleine Server-Änderung in `PitArenaService`, gilt für alle Shows): Balken, Treffer-Blitz und Rückstoß des Gegners bei `SkillFXConfig.getImpactTime(showId, full)` noch während der Show auslösen und den Stoß danach weglassen oder nur als Rückweg zeigen. Das war laut `getImpactTime`-Kommentar und Sim `fight_timeline` („die Show IST der Angriff“) auch die ursprüngliche Absicht von v15.1.

## Was nicht geht (bewusst nicht gebaut)

- **Der Bärchi duckt sich und blickt nach oben.** Die Figur gehört dem Server und wird jeden Frame vom Idle-Wippen gesetzt. Der Client kann sie nicht bewegen. Nötig wäre eine Pose in `FigureFX` (z. B. `FigureFX.crouchLookUp(model, seconds)`), die `PitArenaService` während der Show aufruft.
- **Wolkendecke:** Es gibt keine echte Wolkenebene über der Arena. Ich zeige nur das Durchbrechen (Wolkenfetzen in 45 Studs Höhe).

## Neue und erweiterte Bausteine (wiederverwendbar, in `SkillFXConfig` dokumentiert)

- `shadow`: dunkler Bodenkreis, wächst beschleunigt, optional zur Arena-Mitte
- `comet`: Funkeln, dann Fall mit Kopf, Kern, Schweif (Trail), Funken (**1 Emitter**), Wolkenfetzen; **eine** RenderStepped-Verbindung
- `crater`: Glut-Risse mit Knick, kühlen Orange → Violett ab, Brandfläche
- `dust`: Sternstaub im Bogen (**1 Emitter**, Schwerkraft)
- `radius = "tower"` / `"fence"` (aus `MapConfig`) für `ring`, `shadow` und `crater`
- `ring`: `toArena`
- `shards`: `arc` (Bogen und Landung; Runter-Tweens aller Brocken aus **einem** verzögerten Aufruf), `tex`
- `sky`: `fade`
- `cinematic`: Stil `chase`
- für alle Schritte: `ownerOnly`

Neuer Codepfad: Der Controller lädt jetzt `MapConfig` (Turm- und Zaunradius).

## Effekt-Regeln

- Neue Teile: anchored, ohne Collide, Query, Touch und Schatten. **Keine** Light-Instanz. Der alte `meteor`-Baustein mit `PointLight`/`Fire` wird hier nicht mehr benutzt, das Leuchten kommt über Neon, Trail, BillboardGui und `LightEmission`.
- Höchstens 1 Emitter pro Effekt (Komet-Funken, Sternstaub).
- Kein Thread pro Objekt.
- Alles hat ein `Debris`-Ende. Die Kamera springt bei Kurven-Ende zurück. Endet der Komet vorzeitig (Teil weg), trennt sich seine Verbindung selbst.
- Flackern: Funkeln mit 2 Hz, Blitz einmal, kein Stroboskop.

## Teile und Emitter (volle Show, Besitzer)

| Grafikstufe | Faktor | Teile (ca.) | davon Sterne | Emitter |
|---|---|---|---|---|
| hoch | 1,0 | 118 | 60 | 2 |
| mittel | 0,65 | 85 | 39 | 2 |
| niedrig | 0,35 | 49 | 21 | 1 (Komet-Funken, Rate ×0,35) |

Ohne Sterne (Zuschauer sehen sie nicht): etwa 58, 46 und 28 Teile. Auf niedriger Stufe fallen Wolkenfetzen und Sternstaub weg; es bleiben mindestens 6 Risse. Echo: etwa 12 bis 20 Teile, 1 Emitter.

## Texturen

`assets/vfx/comet_impact/`: `glow.png` (Glut des Kometenkopfs mit weißem Kern), `tail.png` (Schweif-Streifen), `crater.png` (Krater-Risse, Bodenbild), `stardust.png` (Sternstaub-Funke), `shockring.png` (Schockwellen-Ring), `debris.png` (Trümmerbrocken), dazu `preview.png`.

**Abweichung:** Ohne Blender sind die Bilder mit `tools/render_vfx_comet.py` (Pillow) gezeichnet.

**Upload (ging aus der Sitzung nicht):**
1. Asset Manager → Bulk Import → die 6 PNGs (ohne `preview.png`), in Studio ansehen.
2. IDs eintragen in `src/shared/Config/SkillFXConfig.luau`, Tabelle `TEXTURES.CometImpact`: `glow`, `tail`, `crater`, `stardust`, `shockring`, `debris`. Dort steht jetzt überall `0`.

Ohne ID läuft der Rückfall: Glut als halbdurchsichtige Neon-Kugel, Schweif als Trail ohne Bild, Krater-Risse als Neon-Striche, Funken und Sternstaub mit `sparkles_main.dds`, Schockwelle als Neon-Ring, Trümmer aus Slate.

## Annahmen (änderbar)

- **Farben:** Hauptfarbe Orange `255,150,60` (Kopf, Glut), Zweitfarbe Violett `140,90,255` (Schweifende, Auskühlen). Nachtblau kommt über den Himmel.
- **Flugbahn:** Der Komet kommt von hinter dem Angreifer, leicht seitlich versetzt. So sieht die Verfolger-Kamera Kopf und Gegner zugleich.
- **Schweif-Bild:** Ich nehme an, dass Roblox die Textur so über den Trail legt, dass die linke Bildseite am Kopf liegt. Steht der Verlauf falsch herum, `tail.png` spiegeln.
- **Glut mit Bild** ist eine BillboardGui (immer zur Kamera gedreht). Bei 90 Studs Höhe wirkt sie dadurch auch als heller Stern.

## Abspielen und prüfen

**Im PIT:** Kometen-Bärchi in einen Lauf schicken, einmal ab Stage 1 und einmal mit hohem Einstieg (Fortsetzung). Der 1. Einsatz zeigt die volle Show, jeder weitere das Echo.
```lua
local D = game.ServerScriptService.RBLDebug
D:Invoke("add", "CometBaerchi", 20)
D:Invoke("skilltest", "CometBaerchi", 20)    -- Runden-Log, keine Show
D:Invoke("tower", "II", 20)                  -- Einstieg auf Stage 20 (Turm wächst vorher)
```

**Show direkt** (Play-Modus, Befehlsleiste auf **Client**, am besten auf der Kampffläche stehen):
```lua
local SFX = require(game.Players.LocalPlayer.PlayerScripts.Controllers.SkillFXController)
local me = game.Players.LocalPlayer
SFX.play({ owner = me.UserId, skillId = "CometImpact", full = true,  attacker = me.Character })
SFX.play({ owner = me.UserId, skillId = "CometImpact", full = false, attacker = me.Character })
```
Ohne `center` nimmt die Show die Mitte zwischen dir und dem Ziel (8 Studs vor dir) als Arena-Mitte. Schatten und Schockwelle wirken dann versetzt, im PIT stimmen sie.

## Tests (alle grün)

- Syntax aller `.luau`, `check_locals` (191, unverändert)
- `guide_steps`, `unlock_rules`, `boss_tiers`, `combat_rating`, `gold_rules`, `map_layout`, `live_board`, `event_schedule`, `egg_press`, `honey_pond`, `shop`, `migration_hbb`, `endless`
- Sims: `progression_pacing`, `tower_calibration`, `egg_tree_check`, `fight_timeline` (`CometImpact 2.40/5.0`, längste Wiedergabe unverändert 68,5 s), `path_balance`
- `check_feedback`, `check_members` (keine Funde), `check_consistency`, `check_loc`, `check_decor`
- Lokalisierung: keine neuen Texte

## Nicht hier verfügbar / offen

- `claude/CONTEXT_BRIEFING.md` und `tools/make_update_rbxmx.py` fehlen im Repo, deshalb gibt es kein Update-rbxmx. Von Hand in Studio ersetzen:
  - `ReplicatedStorage/Config/SkillFXConfig` ← `src/shared/Config/SkillFXConfig.luau`
  - `StarterPlayer/StarterPlayerScripts/Controllers/SkillFXController` ← `src/client/Controllers/SkillFXController.luau`
- Studio-Playtest, Sound-Check und Textur-Vorschau stehen noch aus.
