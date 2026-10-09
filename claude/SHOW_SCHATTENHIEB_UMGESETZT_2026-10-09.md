# Show „Schattenhieb“ (Schemen-Bärchi): UMGESETZT (2026-10-09)

Prompt 4 aus `OPUS_PROMPT_FAEHIGKEITEN_SHOW_2026-10-08.md`. Neu ist nur die **Show** von `ShadeSlash` (SkillConfig: Typ `Finisher`; unter 30 % Gegner-HP 4,0× ATK, sonst 1,4×). Die Wirkung im Kampf ist unverändert.

**Nicht in Studio getestet.** Die Sitzung lief in der Cloud, ohne Studio und ohne Blender.

## Ablauf (volle Show, 4,2 s, Stufe 4)

| Zeit | Phase | Was passiert | Wer sieht/hört es |
|---|---|---|---|
| 0,00 | Aufladen | Licht wird kalt und grau (`sky`, Sättigung −0,85, in 0,6 s) | nur Besitzer |
| 0,00 | | leiser Geister-Ton (`ghost`, tief) | alle in der Nähe |
| 0,10 | | Der Schatten des Bärchis liegt flach hinter ihm am Boden und richtet sich in 1,0 s als **flache, tintenschwarze Silhouette** auf (`silhouette`) | alle |
| 0,20 | | Der Bärchi wird in 1,1 s blasser, bis er fast durchsichtig ist (`vanish`, 85 %) | alle (jeder Client lokal) |
| 1,55 | Schlag | Silhouette zerfällt in Rauch | alle |
| 1,55 | | Drei Schattenpfützen erscheinen rund um den Gegner, aus jeder steigt gleichzeitig ein **Schatten-Bärchi** und schaut ihn an (`shades`), dazu ein Rauchstoß | alle |
| 2,20 | | Alles friert 0,3 s ein (`hitstop`), der **Ton geht ganz aus** (`silence`, 0,45 s bis zum Hieb) | Bild/Ton: nur Besitzer |
| 2,25 | | Ein einziger dünner, weißer Schnitt zieht in 0,08 s quer durchs Bild durch den Gegner (`cut`) | alle (jeder an seiner Kamera ausgerichtet) |
| 2,65 | Einschlag | Der Schnitt reißt auf: zwei weiße Ränder weichen auseinander, dazwischen dunkles Violett. Schattenfetzen flattern nach außen, der Ton kommt mit einem scharfen Hieb zurück (`slash`), leichtes Wackeln. | alle (Wackeln nur Besitzer) |
| 2,70 | | Die drei Schatten-Bärchis lösen sich in Rauch auf | alle |
| 2,75 | | Der echte Bärchi steht schlagartig wieder voll sichtbar da, als wäre er nie weg gewesen | alle |

Der Treffer liegt bei **2,65 s** (`impactAt`). `fight_timeline` meldet `ShadeSlash 2.65/4.2`. Bis 3,4 s ist alles weg (Show 4,2 s).

**Echo** (0,65 s): nur die Stille (0,15 s, Besitzer) und der weiße Schnitt (aufgerissen bei 0,15 s), dazu der Hieb-Ton.

**Gefühl:** Es gibt kein Blut und keinen Blitz. Der Schnitt ist das einzige Weiß der Show. Farben: Tintenschwarz `18,14,26`, kaltes Dunkelviolett `85,50,135`, grauer Schleier über den Himmel.

## Finisher-Bonus sichtbar machen? (geprüft: geht nicht ohne Server)

Der **Server** weiß es: `CombatCalculator` hängt bei gegriffenem Bonus `"finisher"` an die `effects` des Log-Eintrags.
Der **Client** erfährt es nicht:
- `SkillFXPlay` schickt nur `owner`, `skillId`, `full`, Modelle und Mitte.
- Die Züge (`Types.FightBeat`) bleiben auf dem Server und haben ohnehin kein Effekt-Feld.
- `skillUses` und `firstSkillRound` liest der Client nirgends.

Ich habe das nicht eingebaut. Dafür wäre nötig:
1. `Types.FightBeat` bekommt ein Feld `bonus: boolean?`. `CombatService` setzt es beim Bauen der Züge, wenn `entry.effects` `"finisher"` enthält (beim Kometen genauso `"opener"`).
2. `PitArenaService` gibt es in `SkillFXPlay` mit: `bonus = beat.bonus`.
3. `SkillFXController.play` übernimmt `req.bonus` in `ctx`. `cut` färbt den Schnitt dann beim Aufreißen kurz violett (`ctx.fx.color2`). Ein neuer Baustein `shatter` lässt den Gegner beim Umkippen in Schattenfetzen zerfallen. Weil der Gegner dem Server gehört, ginge das nur lokal über `LocalTransparencyModifier` am Gegner plus Fetzen.

Aufwand: klein (etwa 15 Zeilen Server, 20 Zeilen Client).

## Technik: Wie die Schatten aussehen

- **Silhouette und Schatten-Bärchis sind lokale Klone des echten Bärchi-Modells** (`inkBear`). Sie sind tintenschwarz gefärbt, ohne Texturen, Decals, Sounds, Lichter oder Skripte, und anchored ohne Kollision. Der Umriss ist damit genau der unseres Modells, auch bei den 16 eingefärbten Bärchis.
- Die Silhouette ist **flach**: Die Tiefe des Klons ist entlang der Blickrichtung auf 12 % gestaucht. Sie liegt zuerst wie ein Schatten nach hinten auf dem Boden und kippt dann hoch.
- Lässt sich das Modell nicht klonen, nimmt die Show einen einfachen Kugel-Bärchi (Körper, Kopf, zwei Ohren) in derselben Größe.
- **Verblassen** über `LocalTransparencyModifier`: Das ist eine rein lokale Eigenschaft, die nie zum Server geht, und der Server-Idle (`PivotTo`) überschreibt sie nicht. Nach `back` steht sie wieder auf 0, auch wenn das Modell vorher verschwindet (die Verbindung endet dann).
- **Stille:** Alle gerade spielenden Klänge in `workspace`, `SoundService` und `PlayerGui` werden lokal auf 0 gesetzt und danach zurückgestellt (außer der Server hat die Lautstärke inzwischen geändert). Es gibt keine SoundGroups im Spiel, deshalb geht es nur so. Das Durchsuchen der Instanzen passiert einmal pro Einsatz und nur beim Besitzer.
- **Schnitt:** Jeder Client richtet die Linie an **seiner** Kamera aus, 18° geneigt. So zieht sie für jeden quer durchs Bild.

## Neue und erweiterte Bausteine (in `SkillFXConfig` dokumentiert)

- Neue Bausteine:
  - `silhouette`: flache Tinten-Silhouette steigt hinter der Figur auf, zerfällt in Rauch (**1 Emitter**, Rauch ist Beiwerk)
  - `shades`: Pfützen und aufsteigende Schatten-Klone (**eine** Verbindung für alle, **1 Emitter**)
  - `vanish`: Figur lokal fast durchsichtig, kommt bei `back` schlagartig zurück
  - `silence`: Ton aus (nur Besitzer)
  - `cut`: weißer Schnitt quer durchs Bild, reißt auf
- Erweitert: `shards` mit `tex` (Fetzen-Bild auf beiden Seiten, eingefärbt)
- Intern:
  - `inkBear`: Tinten-Klon oder Rückfall, optional flach
  - `fadeModel`: blendet ein ganzes Modell aus
  - `smokeAt`: ein Emitter, der an mehreren Stellen ausstößt

## Effekt-Regeln

- Klone und Teile: anchored, ohne Collide, Query, Touch und Schatten. **Keine** Light-Instanz, Lichter werden vom Klon entfernt.
- Höchstens 1 Emitter pro Effekt (Silhouette-Rauch, Schatten-Rauch).
- Kein Thread pro Objekt: Klone bewegen sich über **eine** RenderStepped-Verbindung pro Baustein, Ausblenden läuft über Tweens.
- Alles hat ein `Debris`-Ende (spätestens etwa 3,4 s). `vanish` stellt in jedem Fall zurück. Bei einem Abbruch verschwindet alles von selbst.
- Positionen: Füße und Größe aus den Figuren. Pfützen um den Gegner auf dessen Bodenhöhe, die Schatten steigen aus dem Boden (darunter versteckt die Turmetage sie).
- Flackern: Es gibt keinen Blitz. Der Schnitt erscheint einmal und reißt einmal auf.

## Teile und Emitter (volle Show, Besitzer)

Ein Klon hat so viele Teile wie das Bärchi-Modell (P, nach den Namen in `BaerchiMesh` etwa 15).

| Grafikstufe | Teile (ca., P = 15) | Emitter |
|---|---|---|
| hoch | 4·P + 29 ≈ 89 (Silhouette P, 3 Schatten 3·P, Pfützen 3, Rauch-Anker 2, Schnitt 3, Fetzen 18, Ton-Anker 3) | 2 |
| mittel | ≈ 83 (Fetzen 12) | 2 |
| niedrig | ≈ 77 (Fetzen 6, kein Rauch) | 0 aktiv |

Die drei Schatten-Bärchis bleiben auch auf niedriger Stufe, sie sind der Kernmoment. Wird es auf Handys zu schwer, `count = 2` setzen. Echo: 3 Teile, kein Emitter.

## Texturen

`assets/vfx/shade_slash/`: `silhouette.png` (Bärchi-Umriss von vorn, Rauchrand), `shred.png` (Schattenfetzen), `cut.png` (Schnittlinie mit ausgefransten Rändern), `pool.png` (Schattenpfütze), `smoke.png` (Rauchschwade), dazu `preview.png`.

**Abweichungen:**
- Ohne Blender sind die Bilder mit `tools/render_vfx_shade.py` (Pillow) gezeichnet.
- Das Mesh des Bärchis liegt hier nicht als lesbare Geometrie vor (`BaerchiTemplate.rbxm` fehlt). Den Umriss habe ich deshalb nach dem Icon `assets/icons/bear.png` gezeichnet.
- **Empfehlung:** `silhouette` auf `0` lassen. Dann nimmt die Show den flachen Klon mit dem **exakten** Modell-Umriss.

**Upload (ging aus der Sitzung nicht):** Asset Manager → Bulk Import → die PNGs (ohne `preview.png`). Die IDs trägst du in `src/shared/Config/SkillFXConfig.luau` ein, Tabelle `TEXTURES.ShadeSlash`: `silhouette`, `shred`, `cut`, `pool`, `smoke`.

Ohne ID läuft der Rückfall: Silhouette und Schatten als Klone, Pfützen als dunkle Scheiben, Schnitt als weiße Neon-Linie, Fetzen als Ink- und Violett-Splitter, Rauch mit `smoke_main.dds`.

## Annahmen (änderbar)

- **Kamera:** Der Prompt nennt keine Kamerafahrt, deshalb gibt es keine (die alte Show hatte `low`). Der Schnitt richtet sich an der Kamera aus und braucht ein ruhiges Bild.
- **Stille dauert 0,45 s statt 0,3 s:** Das Bild steht 0,3 s still (`hitstop`). Der Ton bleibt aus, bis der Schnitt aufreißt und der Hieb ihn zurückbringt, so wie im Ablauf des Prompts. Für genau 0,3 s: `silence.dur = 0.3`.
- **Sounds:** `charge = ghost`, `strike = whoosh` (Schatten steigen auf, leise), `impact = slash` (scharfer Hieb), Tonhöhe 0,7. Alle stehen in der geprüften `SOUND_LIBRARY`.
- **Klon-Kosten:** Pro Einsatz entstehen 4 Klone. Sie leben höchstens 2,3 s.

## Abspielen und prüfen

**Im PIT:** Schemen-Bärchi in einen Lauf schicken. Der 1. Einsatz zeigt die volle Show, jeder weitere das Echo.
```lua
local D = game.ServerScriptService.RBLDebug
D:Invoke("add", "ShadeBaerchi", 20)
D:Invoke("skilltest", "ShadeBaerchi", 20)   -- Runden-Log: "finisher" in den Effekten = Bonus gegriffen
```
**Show direkt** (Play-Modus, Befehlsleiste auf **Client**):
```lua
local SFX = require(game.Players.LocalPlayer.PlayerScripts.Controllers.SkillFXController)
local me = game.Players.LocalPlayer
SFX.play({ owner = me.UserId, skillId = "ShadeSlash", full = true,  attacker = me.Character })
SFX.play({ owner = me.UserId, skillId = "ShadeSlash", full = false, attacker = me.Character })
```
Mit `attacker = me.Character` klont die Show deinen Avatar, sofern er klonbar ist. Im PIT ist es der Bärchi.

## Tests (alle grün)

- Syntax aller `.luau`, `check_locals` (191, unverändert)
- `guide_steps`, `unlock_rules`, `boss_tiers`, `combat_rating`, `gold_rules`, `map_layout`, `live_board`, `event_schedule`, `egg_press`, `honey_pond`, `shop`, `migration_hbb`, `endless`
- Sims: `progression_pacing`, `tower_calibration`, `egg_tree_check`, `fight_timeline` (`ShadeSlash 2.65/4.2`), `path_balance`
- `check_feedback`, `check_members` (keine Funde), `check_consistency`, `check_loc`, `check_decor`
- Lokalisierung: keine neuen Texte

## Nicht hier verfügbar / offen

- `claude/CONTEXT_BRIEFING.md` und `tools/make_update_rbxmx.py` fehlen im Repo, deshalb gibt es kein Update-rbxmx. Von Hand in Studio ersetzen:
  - `ReplicatedStorage/Config/SkillFXConfig` ← `src/shared/Config/SkillFXConfig.luau`
  - `StarterPlayer/StarterPlayerScripts/Controllers/SkillFXController` ← `src/client/Controllers/SkillFXController.luau`
- Studio-Playtest steht aus. Besonders zu prüfen: Klon des Bärchi-Modells (Archivable, Teilezahl), Stille, Ausrichtung des Schnitts.
- Wie bei Komet und Seraph: Der Schaden kommt im HP-Balken erst im Stoß nach der Show an (siehe `SHOW_KOMETENEINSCHLAG_UMGESETZT_2026-10-09.md`).
