# Studio-Terminal-Merge (10.10.2026)

Branch `studio-terminal-merge-2026-10-10` = `origin/studio-welt-merge-2026-10-10`
+ `origin/claude/tower-terminal-ui-2026-10-08` (Basis e6268b6).

## Was gemacht ist

| Punkt | Stand |
|---|---|
| Merge | Erledigt, Konflikte wie erwartet (PlotDisplayService 4, check_decor 2, FeatureFlags, de/en/fr/es je 1). Überall bleiben **beide Seiten** erhalten: Signatur `stage` (Insel-Stufe) **und** `terminal`, beide Abgleiche in `update` und `onPlayerReady`; Schalter WORLD_B..I **und** TOWER_UNLOCK_BY_CLEAR/TOWER_TERMINAL/TOWER_PANEL_V2; Texte world.* **und** ui.tower2/ui.terminal/ui.upgrade; check_decor: Regel 6 = Insel-Stufen, Teich-Flächen wird Regel 7. |
| 2. Assets.rbxm | Die Fassung aus `sicherung-arbeitsstand-2026-10-10` ist die **neuere** und ist übernommen. Beleg: Im Studio-Export vom 08.10. (`studio_export/Studio_Stand_2026-10-08.rbxlx`) stehen alle 10 Mesh-IDs der Sicherungs-Fassung unter `ReplicatedStorage.Assets.BaerchiTemplate`; die Mesh-IDs der Terminal-Fassung (Repo-Stand vom 05.10.) gibt es dort nur noch unter `ServerStorage.BaerchiTemplate_ALT_2026-10-05`. |
| 3. Types v17 | Geplant und vorbereitet (siehe unten). |
| 4. Prüfungen | Alle gelaufen, nichts ist schlechter geworden (Tabelle unten). |
| 5. Update-Datei | `updates/HBBUpdate_Terminal_2026-10-10.rbxmx`, 39 Skripte, gebaut gegen `origin/studio-welt-merge-2026-10-10`. Der Einspiel-Befehl macht jetzt selbst ein Backup. |
| 1. Sounds | Erledigt (Nachtrag): die 9 IDs aus Studio (Pro Sound Effects, am 10.10. geprüft) stehen jetzt in `WorldFXConfig.SOUNDS`, Text 1:1 aus der Studio-Ausgabe. |
| 1. Texturen | **Offen.** Die 19 Welt-Texturen (`WorldFXConfig.TEXTURE_IDS`) und die 29 Show-Texturen (`SkillFXConfig` `TEXTURES`) gibt es nur in Studio, in keinem Branch. Befehl zum Auslesen siehe unten. |
| Schutz der IDs | Neu: `tools/check_asset_ids.py` zählt die gefüllten IDs, im Repo oder in einer Update-Datei. `make_update_rbxmx.py` bricht ab und schreibt **keine** Datei, wenn das Update WorldFXConfig oder SkillFXConfig mit leeren IDs enthalten würde. Die vorhandene `HBBUpdate_Terminal_2026-10-10.rbxmx` enthält keine der beiden Configs (geprüft, Exit 0) und kann die IDs in Studio deshalb nicht leeren. |
| 5. Einspielen/Play-Test | **Offen**, nur in Studio möglich. Die Prüfliste steht unten. |

## 1. Sounds

Nachtrag 10.10.: Der SOUNDS-Block wurde 1:1 aus Studio übernommen (waspHum, waves, gull,
meadow, crickets, drip, crowd, wind, bell). Repo und Studio sind damit gleich. Die
Update-Datei enthält WorldFXConfig weiterhin nicht, weil sie nicht nötig ist. Ab jetzt
kann `make_update_rbxmx.py` auch mit einer älteren Basis gebaut werden, ohne dass die
Sounds verloren gehen. Nach dem Nachtrag sind sound_zones, world_moments, day_cycle,
island_stage und alle check_* weiterhin grün (check_ui wie vorher: T2 1).

## 1b. Texturen aus Studio holen (bitte einmal ausführen)

```lua
local function block(src, startText, endText)
	local a = string.find(src, startText, 1, true)
	local b = string.find(src, endText, a, true)
	return string.sub(src, a, b + #endText - 1)
end
print(block(game.ReplicatedStorage.Config.WorldFXConfig.Source, "WorldFXConfig.TEXTURE_IDS = {", "} :: { [string]: string }"))
print(block(game.ReplicatedStorage.Config.SkillFXConfig.Source, "local TEXTURES", "\n}\n"))
```

Danach trage ich beide Blöcke ein. `python3 tools/check_asset_ids.py` muss dann
19/19 und 29/29 melden. Erst dann darf ein Update gebaut werden, das WorldFXConfig oder
SkillFXConfig enthält.

## 3. Types-Wechsel v16 → v17

- Studio-Types ist heute e6268b6 (v16) + `FightBeat.bonus`. Das ist zeichengleich mit
  `studio-welt-merge` (geprüft am Studio-Export, Unterschied nur der Zeilenumbruch am Ende).
  Der Merge-Stand hat `bonus` **und** `towers.unlocked`/`version = 17`.
- **Diese vier müssen zusammen kommen**, sie sind alle in derselben Update-Datei:
  `Types`, `PlayerMigration`, `TowerConfig`, `TowerService`.
  Grund: Die Migration setzt am Ende `data.version = Types.default.version`. Läuft die neue
  Migration mit altem Types (v16), bleibt die Version auf 16. Dann wird bei jedem Join die
  alte Rebirth-Regel neu in `unlocked` eingetragen, und die Regel „Freischaltung durch Schaffen“
  greift nie richtig.
- Migration: `towers.unlocked` wird angelegt, Tower I steht immer drin. Was nach der alten
  Regel (Rebirth-Deckel) offen war oder einen Rekord hat, bleibt offen (Bestandsschutz). Das
  läuft nur einmal (`version < 17`), Währung wird nicht angefasst. Ein Speicherstand v17, der
  von altem Code geladen wird, verliert nichts: Das Feld bleibt erhalten, die Version fällt
  auf 16, und beim nächsten v17-Laden kommen nur Freischaltungen dazu.
- Tests: `tower_unlock.test.lua` deckt v16 → v17 ab (R4 behält III, Rekord in Final hält
  Final offen, zweiter Durchlauf ändert nichts, Rebirth nach v17 öffnet nichts) und ist **grün**.
  Neu: `tools/luau-tests/migration_v17.test.lua` (läuft hier, **grün**, 13 Prüfungen) nimmt
  einen gespielten v16-Stand im Format der Studio-Types. Geprüft wird: Jeder alte Wert ist nach
  der Migration unverändert (Währung, Rekorde, Auswahl …). Neu sind nur `towers.unlocked` und
  `version`. Ein zweiter Durchlauf ändert nichts. Der Rückweg über das Backup (alter Code setzt
  16) verliert nichts.
  `migration.test.lua` gibt es in keinem Branch, nur am Heim-PC (Node). Er lief hier **nicht**. Bitte dort
  laufen lassen, der Fall ist im Terminal-Bericht beschrieben.
- Backup: `tools/einspielen.lua` legt vor dem Ersetzen eine Kopie **jedes** ersetzten
  Skripts unter `ServerStorage.Backup_vor_HBBUpdate_<Datum_Uhrzeit>` ab (gleiche
  Ordnerstruktur, Skripte ausgeschaltet). Darin liegt dann auch die alte Types-Fassung.
  Lokal mit einer Studio-Attrappe getestet: Types v16 → v17, Kopie v16 liegt im Backup.

## 4. Prüfungen (Merge-Stand im Vergleich zu beiden Eltern)

| Prüfung | welt-merge | terminal | **Merge** |
|---|---|---|---|
| luau-compile (alle geänderten) | – | – | ok |
| check_consistency/decor/feedback/loc/locals/members | ok | ok | ok (MapConfig 192/200 lokale Namen) |
| check_ui | T2 1 (`WorldFXConfig:691` „5 Arena mit Turm“) | ok | T2 1 (unverändert aus welt-merge, Kameranamen für Entwickler) |
| guide_steps | **rot** (2) | grün | **grün** |
| unlock_rules | rot: Veteran 19/17 | rot: Veteran | rot: Veteran (unverändert) |
| boss_tiers | grün | grün | grün |
| migration_hbb | rot: C4 20/17 | rot: C4 | rot: C4 (unverändert) |
| übrige 15 run_local-Tests (inkl. tower_unlock, sound_zones, world_moments, island_stage, day_cycle) | grün | grün | grün |
| tower_calibration + weitere Sims | ok | ok | ok |
| progression_pacing | 1 FAIL (Rebirth 1) | 5 FAIL | 5 FAIL = wie terminal |

`progression_pacing` hat im Merge dieselben 5 FAIL wie der Terminal-Branch: Look 4/5 zu früh,
Rebirth 1 und die Endless-Ziele. Das ist die bekannte Balance-Folge von „Freischaltung durch
Schaffen“ (`docs/TOWER_TERMINAL_UI_UMGESETZT_2026-10-08.md`, Abschnitt B, offene
Entscheidung 3) und kommt nicht vom Merge.

## 5. Einspielen und Play-Test (in Studio, noch offen)

1. Datei → Speichern unter … als `.rbxl`-Sicherung (zusätzlich zum Skript-Backup).
2. Datei → Roblox-Modell importieren → `updates/HBBUpdate_Terminal_2026-10-10.rbxmx`.
3. `tools/einspielen.lua` komplett in die Befehlsleiste, Enter. Erwartet werden 39 Skripte
   (ersetzt + neu). „neu:“ sollte für diese 8 kommen: TerminalController, Kit, TowerPanel,
   UpgradeFX, GamepassService, TerminalBuilder, GamepassConfig, SoundConfig. Dazu die Zeile
   mit dem Backup-Ordner.
4. Play. Zu prüfen:
   - Terminal an der Brücke sichtbar (Bildschirm, Lampe), Prompt „Tower wählen“.
   - Tower-Panel öffnet über das Terminal und über den Tower-Namen in der Pet-Leiste.
   - Welt-Effekte laufen. Im Output müssen stehen: `[DayCycle] an`, `[Water] aktiv`, `[Hub] …`,
     `[PlotLife]`, `[ArenaLife]`, `[Life]`, `[WorldMoments]`, `[ZoneLight]`, Server
     `[WorldMomentService] Initialisiert`.
   - Shows (Kometeneinschlag, Gletscherhauch, Schattenhieb, Seraphen-Segen, Omega-Schlag) mit
     Treffer im Einschlag-Moment.
   - Klang-Kulisse hörbar: Im Output muss `[Soundscape] aktiv | Schleifen mit ID: 6` stehen,
     **nicht** „still“.
   - Texturen: Im Output muss `[Water] … Glitzer-Bild: true` stehen. Die Shows zeigen ihre Bilder.
   - Nach dem Einspielen im Backup-Ordner nachsehen: WorldFXConfig und SkillFXConfig dürfen
     **nicht** darin liegen. Sie wurden nicht angefasst.
   - Insel-Stufen: Das Attribut `IslandStage` steht am Player.
   - Output ohne rote Fehler. Danach Datei → Auf Roblox speichern.
5. Zurück: die Skripte aus `ServerStorage.Backup_vor_HBBUpdate_…` an ihre Plätze ziehen
   (oder die `.rbxl`-Sicherung öffnen).
