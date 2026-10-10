# Show „Seraphen-Segen“ (Seraph-Bärchi): UMGESETZT (2026-10-09)

Prompt 2 aus `OPUS_PROMPT_FAEHIGKEITEN_SHOW_2026-10-08.md`. Neu ist nur die **Show** von `SeraphGrace` (SkillConfig: „Seraphen-Segen“, Typ `Heal`, 22 % der max. HP). Die Wirkung im Kampf ist unverändert.

**Nicht in Studio getestet.** Die Sitzung lief in der Cloud, ohne Studio und ohne Blender.

## Wann zeigt der HP-Balken die Heilung? (geprüft)

`FightTimeline` plant nur, welche Züge gezeigt werden. Den Balken setzt `PitArenaService`, und zwar im `onImpact` von `FigureFX.clash`. Ablauf bei einem Fähigkeiten-Zug:

1. `SkillFXPlay` an alle Clients, dann wartet der Server die **ganze** Show ab (`getDuration`, voll = 3,4 s).
2. Danach kommt der wuchtige Stoß (`FIGHT_SKILL_BEAT_SECONDS` 1,15 s × Tempo). Bei `CLASH_IMPACT_AT` = 60 % davon setzt `onImpact` die Balken.

→ **Der Balken heilt bei 3,4 s + 0,69 s × Tempo**, also bei 3,68 s (Tempo 0,4) bis 4,09 s (Tempo 1). Das Tempo kennt der Client nicht.

Die Show richtet sich danach:
- Das Wabenmuster zieht **genau zum Show-Ende (3,40 s)** ein (`impactAt = 3.4`).
- Der warme Goldschein danach bleibt **1,0 s an der Figur** (`hold`). Er folgt ihr auch beim Anlauf zum Stoß und reicht damit bis 4,3 s. Wenn der Balken springt, leuchtet der Bärchi also noch.
- Beim Echo genauso: der Balken heilt bei etwa 0,5 bis 1,24 s, der Schein hält bis etwa 1,33 s.

**Exakt im selben Frame geht es ohne Server-Änderung nicht**, weil der Balken erst im Stoß nach der Show kommt. Nebenbei: Der Kommentar bei `SkillFXConfig.getImpactTime` behauptet, PitArenaService setze die Leisten in genau diesem Moment. Das stimmt im Code nicht, `getImpactTime` nutzt nur die Sim `fight_timeline`. Wenn du es framegenau willst, wäre eine kleine Änderung in `PitArenaService` nötig. Bei Fähigkeiten ohne Schaden würde dann `onImpact` (nur Balken, ohne Funken) nach `getImpactTime(showId, full)` noch während der Show aufgerufen. Das habe ich nicht gebaut, weil der Prompt sagt: die Show anpassen, nicht umgekehrt.

## Ablauf (volle Show, 3,4 s, Stufe 3)

| Zeit | Phase | Was passiert | Wer sieht es |
|---|---|---|---|
| 0,00 | Aufladen | Licht wird wärmer (`sky`, Bernstein-Weiß) | nur Besitzer |
| 0,00 | | Zwei Flügel aus 7 langen Lichtfedern je Seite entfalten sich hinter dem Bärchi, von innen nach außen (`wings`) | alle |
| 0,30 | | Ring aus Honiggold über dem Kopf, dreht sich langsam, folgt der Figur (`halo`) | alle |
| 1,15 | Schlag | Hoch über dem Bärchi (26 Studs) öffnet sich ein rundes Wolkenloch mit leuchtendem Rand (`ring` + `lift`) | alle (Beiwerk) |
| 1,35 | | Breite, weiche Lichtsäule fällt aus dem Loch **auf den Bärchi** (`pillar`, Fuß unter seinen Füßen), heller Glockenton | alle |
| 1,60 | | Einzelne Lichtfedern rieseln langsam herab (`snowfall` ohne Hülle, Feder-Bild) | alle (Beiwerk) |
| 2,55 | Einschlag | Wabenmuster aus Gold läuft in 0,5 s von den Füßen bis zum Kopf und zieht in 0,35 s in ihn ein (`honeycomb`) | alle |
| 3,05 | | Flügel falten sich (außen zuerst) und zerfallen in Funken | alle (Funken = Beiwerk) |
| 3,30 | | Warmer Lichtpuls läuft flach über den Boden nach außen (r 14) | alle |
| 3,35 | | tieferer Glockenton | alle |
| 3,40 bis 4,40 | | Goldschein bleibt am Bärchi, bis der HP-Balken die Heilung zeigt | alle |

**Echo** (0,55 s): eine schmale, kurze Lichtsäule (Breite 2,2 statt 4,5, Höhe 18 statt 26) und das einziehende Wabenmuster (4 Reihen), dazu zwei Glockentöne.

**Ton:** `charge = whoosh` (Flügel), `strike = ping` (Säule), `impact = ping` (Waben, durch den Slot-Faktor tiefer). Tonhöhe 1,3. Die Klänge stehen schon in der geprüften `SOUND_LIBRARY`.

## Was nicht geht (bewusst nicht gebaut)

- **Der Bärchi schwebt und landet weich.** Die Figur gehört dem Server. Während der Show bewegt `FigureFX.idleBob` sie jeden Frame, eine Bewegung auf dem Client würde sofort überschrieben. Dafür bräuchte es einen Server-Baustein (z. B. `FigureFX.hover(model, height, seconds)`), den `PitArenaService` während der Show aufruft. Ersatzweise tragen die Flügel und der Heiligenschein das Bild „er steigt auf“.
- **Der Gegner hebt geblendet den Kopf.** Gleicher Grund, das Gegner-Modell wird vom Server bewegt. Dafür bräuchte es eine kurze Kopf- bzw. Neigungs-Animation in `FigureFX`.

## Neue und erweiterte Bausteine (wiederverwendbar, in `SkillFXConfig` dokumentiert)

- `wings`: Lichtflügel, Feder für Feder, falten sich bei `foldAt` und zerfallen in Funken (1 Emitter)
- `halo`: Heiligenschein über dem Kopf, dreht sich und folgt der Figur
- `honeycomb`: Wabenmuster Füße → Kopf, zieht ein, Schein bleibt `hold` s an der Figur
- `ring`: `lift = n` (n Studs über der Figur, mit Bild auch von unten sichtbar)
- `pillar`: `feet` (Fuß unter der Figur), `soft` (halbdurchsichtig), `tex` (Säule als Beam mit Verlaufsbild)
- `snowfall`: `noShell`, `lift`, `size`
- für alle Bausteine: `second = true` (Zweitfarbe)
- intern: `followModel` hält Effekte an einer Figur, die sich bewegt. **Eine** RenderStepped-Verbindung pro Effekt, Ende nach Ablauf oder wenn die Figur weg ist.

Die anderen Shows bleiben unverändert. Ohne die neuen Parameter verhalten sich `ring`, `pillar` und `snowfall` wie vorher.

## Effekt-Regeln

- Neue Teile: anchored, ohne Collide, Query, Touch und Schatten. **Keine** Light-Instanz, das Leuchten kommt über Neon, ForceField und `LightEmission`.
- Emitter: höchstens 1 pro Effekt (Funken der Flügel, rieselnde Federn).
- Kein Thread pro Objekt: Federn und Waben laufen über verzögerte Tweens. Pro Baustein gibt es höchstens ein `task.delay` und eine Folge-Verbindung.
- Alles hat ein `Debris`-Ende (spätestens 4,4 s nach Start). Bricht ein Lauf ab oder verschwindet die Figur, endet auch die Folge-Verbindung.
- Positionen: Füße und Größe aus der Bounding-Box, Wolkenloch relativ zur Figur (+26). Die Show stimmt auf dem Tower in jeder Höhe.
- Flackern: nichts blinkt, alles blendet weich ein und aus. Kein weißer Blitz (Stufe 3).

## Teile und Emitter (volle Show, Besitzer)

| Grafikstufe | Faktor | Teile (ca.) | Emitter |
|---|---|---|---|
| hoch | 1,0 | 92 (Federn 14, Funken-Anker 1, Schein-Perlen 14, Wolkenloch 1, Säule 1 bis 2, Feder-Anker 1, Waben 54 + Schein 1, Puls 1, Ton-Anker 3) | 2 |
| mittel | 0,65 | etwa 57 (Federn 10, Waben 6×4) | 2 |
| niedrig | 0,35 | etwa 42 (kein Wolkenloch, keine Funken, keine rieselnden Federn; Federn 8, Perlen 8, Waben 5×4) | 0 |

Die Waben (bis 54 Teile) leben nur 0,85 s. Zuschauer bekommen ×0,6, Beiwerk also nur auf hoher Stufe. Echo: etwa 22 bis 31 Teile, kein Emitter.

## Texturen

`assets/vfx/seraph_grace/`: `feather.png` (Lichtfeder), `halo.png` (Heiligenschein-Ring), `comb.png` (Waben-Glanzmuster), `column.png` (Lichtsäule mit weichem Verlauf), `cloudrim.png` (Rand des Wolkenlochs), `spark.png` (Lichtfunke), dazu `preview.png` als Vorschau.

**Abweichung:** Ohne Blender sind die Bilder mit `tools/render_vfx_seraph.py` (Pillow) gezeichnet. Sie sind hell auf transparentem Grund, die Farbe (Honiggold, Elfenbein) kommt in Roblox dazu.

**Upload (ging aus der Sitzung nicht):**
1. Asset Manager → Bulk Import → die 6 PNGs (ohne `preview.png`), in Studio ansehen.
2. IDs eintragen in `src/shared/Config/SkillFXConfig.luau`, Tabelle `TEXTURES.SeraphGrace`: `feather`, `halo`, `comb`, `column`, `cloudrim`, `spark`. Dort steht jetzt überall `0`.

Ohne ID läuft der Rückfall: Federn als Neon-Streifen, Heiligenschein aus 14 Neon-Perlen, Waben als Neon-Scheiben, Säule als halbdurchsichtiger Neon-Zylinder, Wolkenloch als Neon-Ring, Funken und Federn mit `rbxasset://textures/particles/sparkles_main.dds`.

## Annahmen (änderbar)

- **Farben:** Hauptfarbe Honiggold `255,196,70`, Zweitfarbe Elfenbein `255,246,225`. Bernstein steckt im Himmel-Farbton und im Emitter-Verlauf.
- **Säule mit Bild:** Mit `column`-ID wird die Säule ein `Beam` (FaceCamera). Er sieht aus jedem Blickwinkel weich aus, wirft aber kein Neon-Leuchten mehr.
- **Waben-Bild:** Eine Wabe pro Kachel. Die Ausrichtung auf der Kachel (Front = nach außen) ist ungeprüft.
- **Heiligenschein-Höhe:** 0,7 Studs über der Bounding-Box. Bei Modellen mit hohen Ohren eventuell `lift` anheben.

## Abspielen und prüfen

**Im PIT:** Seraph-Bärchi in einen Lauf schicken. Der 1. Einsatz zeigt die volle Show, jeder weitere das Echo. Achte auf den HP-Balken: Er soll springen, solange der Goldschein noch am Bärchi liegt.
```lua
local D = game.ServerScriptService.RBLDebug
D:Invoke("add", "SeraphBaerchi", 20)
D:Invoke("skilltest", "SeraphBaerchi", 20)   -- Runden-Log (wann geheilt wird), keine Show
```
**Show direkt** (Play-Modus, Befehlsleiste auf **Client**):
```lua
local SFX = require(game.Players.LocalPlayer.PlayerScripts.Controllers.SkillFXController)
local me = game.Players.LocalPlayer
SFX.play({ owner = me.UserId, skillId = "SeraphGrace", full = true,  attacker = me.Character })
SFX.play({ owner = me.UserId, skillId = "SeraphGrace", full = false, attacker = me.Character })
```
Niedrige Grafikstufe: Esc → Einstellungen → Grafikqualität manuell auf 1 bis 3.

## Tests (alle grün)

- Syntax aller `.luau`, `check_locals` (191, unverändert)
- `guide_steps`, `unlock_rules`, `boss_tiers`, `combat_rating`, `gold_rules`, `map_layout`, `live_board`, `event_schedule`, `egg_press`, `honey_pond`, `shop`, `migration_hbb`, `endless`
- Sims: `progression_pacing`, `tower_calibration`, `egg_tree_check`, `fight_timeline` (`SeraphGrace 3.40/3.4`), `path_balance`
- `check_feedback`, `check_members` (keine Funde), `check_consistency`, `check_loc`, `check_decor`
- Lokalisierung: keine neuen Texte

## Nicht hier verfügbar / offen

- `claude/CONTEXT_BRIEFING.md` und `tools/make_update_rbxmx.py` fehlen im Repo, deshalb gibt es kein Update-rbxmx. Von Hand in Studio ersetzen:
  - `ReplicatedStorage/Config/SkillFXConfig` ← `src/shared/Config/SkillFXConfig.luau`
  - `StarterPlayer/StarterPlayerScripts/Controllers/SkillFXController` ← `src/client/Controllers/SkillFXController.luau`
- Studio-Playtest, Sound-Check und Textur-Vorschau stehen noch aus.
