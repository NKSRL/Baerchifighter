# Show „Omega-Schlag“ (Omega-Bärchi): UMGESETZT (2026-10-09)

Prompt 5 aus `OPUS_PROMPT_FAEHIGKEITEN_SHOW_2026-10-08.md`. Neu ist nur die **Show** von `OmegaStrike` (SkillConfig: Typ `Damage`, 7× Schaden, Ladung 9). Die Wirkung im Kampf ist unverändert.

**Nicht in Studio getestet.** Die Sitzung lief in der Cloud, ohne Studio und ohne Blender.

## Ablauf (volle Show, 5,8 s, Stufe 4)

| Zeit | Phase | Was passiert | Wer sieht/hört es |
|---|---|---|---|
| 0,00 | Aufladen (Stille vor dem Sturm) | Alle Geräusche werden ganz leise (`silence`, `level = 0.15`, bis 3,3 s) | Besitzer |
| 0,00 | | Die Welt verliert in 1,2 s fast alle Farbe (`sky`, Sättigung −0,92) | Besitzer |
| 0,00 | | Der Omega-Bärchi leuchtet hell (`spotlight`, Highlight) | Besitzer |
| 0,15 | | tiefes Bass-Brummen (`bass`, Tonhöhe 0,45) | alle in der Nähe |
| 1,00 | Sammeln | Über der Arena (34 Studs) zeichnet sich ein riesiges leuchtendes **Ω** Strich für Strich (`omega`, r 7) | alle (zur eigenen Kamera gedreht) |
| 1,00 bis 3,40 | | Kamera fährt in einem langsamen Halbkreis um den Bärchi (`cinematic` `orbitSelf`, 2,4 s), Blick leicht nach oben | Besitzer |
| 1,30 bis 3,10 | | Aus allen vier Himmelsrichtungen fliegen Lichtpunkte in den vier Pfadfarben ins Ω: Gold (N), Kristall-Blau (O), Void-Violett (S), Kosmos-Sternweiß (W) (`converge`, je 4) | alle |
| 3,30 | Schlag | Das Ω zieht sich **mit einem Ruck** (0,22 s) auf die Pfote des Bärchis zusammen. Dort blitzt ein reinweißer Punkt auf, der Ton kommt zurück. | alle |
| 3,55 | Einschlag | weißer Blitz, Wackeln | Besitzer |
| 3,55 | | Ein **Farbspektrum** läuft als Welle durchs Bild, dahinter bekommt die Welt ihre Farbe zurück (`wipe`) | Besitzer |
| 3,58 bis 3,82 | | Schockwelle in den vier Pfadfarben: vier flache Ringe nacheinander bis zum Arena-Zaun | alle |
| 3,60 bis 4,90 | | Eine **schmale Lichtsäule** (Breite 1,6, Höhe 160) steigt über der Arena auf (`pillar`, `global`) | **alle Spieler auf dem Server**, auch auf der Hauptinsel |
| 3,70 | | Das **Ω brennt sich** unter dem Gegner in den Boden, glüht weiß und verblasst bis 5,7 s nach Violett-Grau | alle |

Der Treffer liegt bei **3,55 s** (`impactAt`). `fight_timeline` meldet `OmegaStrike 3.55/5.8`. Die längste Wiedergabe sinkt leicht auf 68,3 s, die alte Show war 6,0 s lang.

**Echo** (0,65 s): Ein kleines Ω erscheint über dem Bärchi und ruckt auf die Pfote, danach die Schockwelle in vier Farben (r 10). Keine Entfärbung, keine Kamera, keine Lichtsäule.

## Die Lichtsäule für alle

- Bisher sahen Spieler weiter als `SPECTATOR_DISTANCE` (260 Studs) **gar nichts** von einer Show. Neu: Sie bekommen nur die Schritte mit `global = true`, und nur in der **vollen** Show. Für jede andere Show ändert sich nichts, weil sonst kein Schritt `global` ist.
- **Höchstens einmal pro Lauf:** Die volle Show läuft laut `PitArenaService` (`fxShownFull`) nur beim ersten Einsatz eines Laufs, das Echo hat keine Säule.
- **Kurz:** 1,3 s (unter 1,5 s), danach wird sie schmaler und verschwindet.
- **Nimmt niemandem die Sicht:** 1,6 Studs breit, halbdurchsichtig (`soft`), steht in der Arena-Mitte. Mit Bild ist sie ein Beam mit weichem Verlauf, unten kräftig und oben auslaufend.
- Fehlt das Modell bei weit entfernten Spielern (Streaming), nimmt die Säule die mitgeschickte Arena-Mitte.

## Was nicht ganz geht

- **„Nur der Omega-Bärchi bleibt farbig“:** Roblox kann einzelne Objekte nicht vom Farbfilter (`ColorCorrectionEffect`) ausnehmen. Ich entfärbe die Welt auf −0,92 und lege einen hellen Highlight-Schein auf den Bärchi (nur Besitzer). So hebt er sich als hellste Form klar ab, wird aber mit entfärbt. Für echte Farbe müsste man ohne Filter auskommen und stattdessen die Umgebung einzeln einfärben, also Material und Farbe hunderter Teile lokal tauschen. Das ist zu teuer und fehleranfällig, deshalb habe ich es nicht gebaut.
- **Wolken, Pollen und Schaum anhalten:** `AmbienceController` bietet dafür nichts an (kein Pause-Schalter, eine feste Heartbeat-Schleife). Wie vom Prompt erlaubt, reicht der Farbfilter, ich habe nichts dafür gebaut. Falls gewünscht: ein `AmbienceController.setFrozen(bool)`, das in der Heartbeat-Schleife `dt = 0` setzt und den Pollen-Emitter pausiert, wären etwa 10 Zeilen.
- **„Ein einziger Sprung, ein einziger Treffer“:** Den Sprung macht der Server im Stoß nach der Show. Wie bei den anderen Shows kommen Sprung und Schaden im HP-Balken erst nach Show-Ende an (siehe `SHOW_KOMETENEINSCHLAG_UMGESETZT_2026-10-09.md`).

## Neue und erweiterte Bausteine (in `SkillFXConfig` dokumentiert)

- Neue Bausteine:
  - `omega`: Ω Strich für Strich. `mode = "sky"`: hoch über der Arena, zur Kamera des Clients gedreht, ruckt bei `pullAt` auf die Pfote, weißer Punkt. `mode = "brand"`: flach eingebrannt, verblasst.
  - `converge`: Lichtpunkte aus vier Himmelsrichtungen, eine Farbe je Richtung, mit Schweif (Trail); Start per Tween-Verzögerung
  - `spotlight`: Highlight auf der Figur (nur Besitzer)
  - `wipe`: Spektrum-Welle als ScreenGui, dahinter tweent der Farbfilter auf neutral (nur Besitzer)
- Erweitert:
  - `silence`: `level` (leiser statt stumm)
  - `cinematic`: Stil `orbitSelf`
  - für alle Schritte: `color` (feste Farbe) und `global` (auch weit entfernte Spieler, nur volle Show)

## Effekt-Regeln

- Neue Teile: anchored, ohne Collide, Query, Touch und Schatten. **Keine** Light-Instanz und kein Emitter, das Leuchten kommt über Neon, Trail, Highlight und Beam.
- Kein Thread pro Objekt: Ω-Striche und Lichtpunkte laufen über verzögerte Tweens. Den Ruck startet **ein** verzögerter Aufruf für alle Striche.
- Alles hat ein `Debris`-Ende, spätestens bei 5,7 s (Show 5,8 s), also bevor der Turm zur nächsten Stage wächst. Stille und Farbfilter stellen sich selbst zurück, die Kamera springt nach 2,4 s zurück.
- Flackern: Blitz einmal, Spektrum-Welle einmal (0,9 s), kein Pulsieren.

## Teile und Emitter (volle Show)

| Grafikstufe | Besitzer (ca.) | Spieler weit weg |
|---|---|---|
| hoch | 64 (Ω 22 + Punkt, Lichtpunkte 16, Ringe 4, Säule 1 bis 2, Brandzeichen 16, Ton-Anker 3) | 1 bis 2 (nur Säule) |
| mittel | 52 (Ω 15, Lichtpunkte 12, Brand 11) | 1 bis 2 |
| niedrig | 41 (Ω 12, Lichtpunkte 8, Brand 12) | 1 bis 2 |

Emitter: 0. Echo: etwa 18 Teile.

## Texturen

`assets/vfx/omega_strike/`: `omega.png` (Ω-Ring), `spectrum.png` (Spektrum-Verlauf), `orb.png` (Lichtpunkt, wird je Pfadfarbe eingefärbt; die Vorschau zeigt alle vier), `brand.png` (Ω-Brandzeichen), `shockring.png` (Schockwellen-Ring), `column.png` (Verlauf für die Lichtsäule), dazu `preview.png`.

**Abweichung:** Ohne Blender sind die Bilder mit `tools/render_vfx_omega.py` (Pillow) gezeichnet.

**Upload (ging aus der Sitzung nicht):**
1. Asset Manager → Bulk Import → die 6 PNGs (ohne `preview.png`), in Studio ansehen.
2. IDs eintragen in `src/shared/Config/SkillFXConfig.luau`, Tabelle `TEXTURES.OmegaStrike`: `omega`, `spectrum`, `orb`, `brand`, `shockring`, `column`.

Ohne ID läuft der Rückfall:
- Ω aus Neon-Strichen
- Spektrum als Frame mit `UIGradient`
- Lichtpunkte als Neon-Kugeln mit Schweif
- Brandzeichen aus flachen Neon-Strichen
- Ringe aus Neon
- Säule als halbdurchsichtiger Neon-Zylinder

## Annahmen (änderbar)

- **Sounds:** `charge = bass` (tiefes Brummen in der Stille), `strike = whoosh` (Ruck), `impact = boom` (Treffer), Tonhöhe 0,45. Den alten `thunder` habe ich weggelassen, weil der Prompt „nicht laut“ verlangt.
- **Himmelsrichtungen:** N/O/S/W relativ zur Welt, nicht zur Kamera.
- **Ω-Ausrichtung:** Jeder Client dreht das Ω zu seiner Kamera beim Erscheinen. Während der Kamerafahrt dreht es nicht mit, es bleibt in seiner Lage stehen.
- **Lautstärke in der Stille:** 15 % aller laufenden Klänge. Für völlige Stille `level = 0`.
- **Pfadfarben:** Gold `255,200,60`, Kristall-Blau `110,200,255`, Void-Violett `150,80,255`, Kosmos-Sternweiß `235,235,255`.

## Abspielen und prüfen

**Im PIT:** Omega-Bärchi in einen Lauf schicken. Der 1. Einsatz zeigt die volle Show, jeder weitere das Echo. Prüfe die Lichtsäule mit einem zweiten Spieler auf der Hauptinsel (Studio: Test → Clients and Servers, 2 Spieler).
```lua
local D = game.ServerScriptService.RBLDebug
D:Invoke("add", "OmegaBaerchi", 20)
D:Invoke("skilltest", "OmegaBaerchi", 30)   -- Runden-Log, keine Show
```
**Show direkt** (Play-Modus, Befehlsleiste auf **Client**):
```lua
local SFX = require(game.Players.LocalPlayer.PlayerScripts.Controllers.SkillFXController)
local me = game.Players.LocalPlayer
SFX.play({ owner = me.UserId, skillId = "OmegaStrike", full = true,  attacker = me.Character })
SFX.play({ owner = me.UserId, skillId = "OmegaStrike", full = false, attacker = me.Character })
```

## Tests (alle grün)

- Syntax aller `.luau`, `check_locals` (191, unverändert)
- `guide_steps`, `unlock_rules`, `boss_tiers`, `combat_rating`, `gold_rules`, `map_layout`, `live_board`, `event_schedule`, `egg_press`, `honey_pond`, `shop`, `migration_hbb`, `endless`
- Sims: `progression_pacing`, `tower_calibration`, `egg_tree_check`, `fight_timeline` (`OmegaStrike 3.55/5.8`), `path_balance`
- `check_feedback`, `check_members` (keine Funde), `check_consistency`, `check_loc`, `check_decor`
- Lokalisierung: keine neuen Texte

## Nicht hier verfügbar / offen

- `claude/CONTEXT_BRIEFING.md` und `tools/make_update_rbxmx.py` fehlen im Repo, deshalb gibt es kein Update-rbxmx. Von Hand in Studio ersetzen:
  - `ReplicatedStorage/Config/SkillFXConfig` ← `src/shared/Config/SkillFXConfig.luau`
  - `StarterPlayer/StarterPlayerScripts/Controllers/SkillFXController` ← `src/client/Controllers/SkillFXController.luau`
- Studio-Playtest steht aus. Besonders zu prüfen: Lichtsäule bei einem zweiten Spieler auf der Hauptinsel, Stille, Spektrum-Welle, Lage des Ω während der Kamerafahrt.
