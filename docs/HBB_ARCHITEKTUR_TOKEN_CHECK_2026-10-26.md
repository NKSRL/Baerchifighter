# Struktur- und Architektur-Check mit Blick auf Token-Verbrauch (26.10.2026)

Geprüft: das ganze Repo auf Branch `claude/happy-mccarthy-ncbqht` (Stand `70dab63`, 119 Commits seit 02.10.).
Maßstab: Was kostet eine künftige Claude-Sitzung an Tokens, bevor sie produktiv wird, und was treibt die Kosten beim Lesen, Ändern und Prüfen?
**Am Code wurde nichts geändert.** Dieser Bericht ist eine priorisierte Liste mit Vorschlägen; die Entscheidungen (besonders alles, was Löschen betrifft) liegen beim Projektinhaber.

Der Architektur-Check vom 12.10. (`HBB_ARCHITEKTUR_CHECK_2026-10-12.md`, beim Merge am 15.10. verloren, siehe Fund 7) bleibt inhaltlich gültig: Schichtung hält, ein Startpunkt (`GameManager`), alle Remotes über `RateLimiter`, Server autoritativ, Daten in `Config`, Regeln in `Modules`. Dieser Bericht wiederholt das nicht, sondern schaut auf das, was Tokens kostet.

## 1. Zahlen

| Bereich | Umfang | Anteil am Repo |
|---|---|---|
| `src/` | 289 `.luau`, 98 389 Zeilen (shared 28,5 k / server 32,2 k / client 37,6 k) | 3,8 MB |
| `docs/` | 55 Berichte (≈ 80 k Tokens) + 72 Bilder | 26 MB |
| `claude/` | 16 Berichte und Prompts (≈ 47 k Tokens) | 0,2 MB |
| `tools/` | 7 Python-Checks, 36 Luau-Tests, 19 Sims, Render-/Build-Skripte | 0,8 MB |
| `assets/` + `Export/` | 890 PNG, 60 FBX, 11 Blender, 10 MP4 | 536 MB |
| Backups, `studio_export/`, `updates/`, Root-Dateien | 35 + 110 + 24 + 6 Dateien | 18 MB |
| `.git` | | 490 MB |

Code und Berichte sind zusammen 5 MB; die übrigen 578 MB sind Binärdateien und Kopien.

**Was ein einzelnes Lesen kostet (Bytes / 4):**

| Datei | Zeilen | ≈ Tokens | Bemerkung |
|---|---|---|---|
| `CLAUDE.md` | 40 | 750 | wird jede Sitzung geladen, gut |
| `docs/HBB_STATUS_2026-10-05.md` | 33 | 750 | Pflichtlektüre laut CLAUDE.md, Stand 05.10. |
| `docs/Worldbuilding.md` | 606 | 16 700 | |
| `Config/MapConfig.luau` | 1 682 | 24 900 | 201 Schlüssel, 58 Abhängige, 192 von 200 erlaubten Locals |
| `Controllers/SkillFXController.luau` | 2 440 | 24 700 | größte Datei |
| `Strings/de.luau` (je Sprache gleich) | 1 315 | 19 900 | 4 Dateien, je 31-mal geändert (meistgeänderte Dateien) |
| `UI/BaerchiPanel.luau` | 1 633 | 16 300 | |
| `Services/MapService.luau` | 1 472 | 15 200 | |
| `Network/Types.luau` | 1 204 | 12 300 | 101 Abhängige |

Größenverteilung: Median 209 Zeilen (gut), aber 31 Dateien über 800 Zeilen und 49 zwischen 400 und 800. Kommentare sind 19 % der Zeilen und rund 29 % der Bytes (≈ 295 k der ≈ 1 005 k Tokens in `src/`).

## 2. Was gut ist und bleiben soll

- Klare Schichten und Ordner (`Config` / `Modules` / `Services` / `Util` / `Controllers` / `UI`), Dateiname = Modulname = Zuständigkeit. Suchen nach Begriff trifft fast immer eine Datei.
- `Types.luau` und `Remotes.luau` als einzige Quellen; `FeatureFlags.isOn` als einziger Schalter-Zugriff (93 Module, einheitlicher Alias).
- Prüfwerkzeuge ohne Studio (`check_*.py`, Luau-Tests, Sims) und `make_update_rbxmx.py` als verlustfreier Weg nach Studio.
- Kopfkommentar „Einzige Zuständigkeit“ je Modul. Er ist die Grundlage für die Modulkarte (Vorschlag 1c).
- Kurze, aktuelle `CLAUDE.md` (750 Tokens).

## 3. Funde, nach Token-Hebel sortiert

### Fund 1 – Orientierung: jede Sitzung sucht sich den Stand neu zusammen (größter Hebel)

- `CLAUDE.md` nennt als Pflichtlektüre den Status vom **05.10.**; seither gab es 10 Paket-Welten (W1, Epilog, Welt 2, Pit v2, Balance v3). Der tatsächliche Stand steckt verteilt in 55 + 16 datierten Berichten ohne Index. Eine Sitzung, die „den Stand“ wissen will, liest entweder zu viel (bis 127 k Tokens) oder das Falsche.
- `README.md` widerspricht `CLAUDE.md`: empfiehlt `rojo serve` („Dateien hier sind die einzige Wahrheit“) und listet Node-Tests (`run.mjs`, `loc.test.lua` …), die im Repo nie lagen. `CLAUDE.md` warnt vor Rojo (löscht Studio-Inhalte) und empfiehlt Option C. `tools/README.md` listet dieselben fehlenden Node-Tests als „vor jedem Commit“.
- 9 tote Verweise auf Berichte (u. a. in `FeatureFlags.luau` fünfmal, `README.md` → `claude/CONTEXT_BRIEFING.md`, `Icons.luau`, `PitV2Config.luau`). Wer dem Verweis folgt, sucht umsonst.
- `OPUS_PROMPT_ROADMAP.md` (Root, 14 KB) beschreibt den September-Stand („init.client.luau – NUR Hello world“).

**Vorschlag 1a – `docs/STATUS.md` ohne Datum im Namen.** Höchstens 60 Zeilen: je Bereich (Welt 1, Welt 2, Epilog, Pit, Balance, UI, Audio, Shop) eine Zeile Stand + Verweis auf den letzten Bericht, dazu „offen“ und „zuletzt in Studio eingespielt“. Wird am Ende jeder Sitzung fortgeschrieben; die datierten Berichte bleiben als Historie. `CLAUDE.md` zeigt nur noch darauf.

**Vorschlag 1b – `docs/INDEX.md`.** Eine Zeile pro Bericht: Datum, Thema, gilt noch / abgelöst durch. 71 Berichte ≈ 75 Zeilen ≈ 1,5 k Tokens statt 127 k. Alte Prompts (`OPUS_PROMPT_*`, `MASTER_PROMPT_*`, `COWORK_*`) in `claude/archiv/`, damit `claude/` nur noch Gültiges enthält.

**Vorschlag 1c – `docs/ARCHITEKTUR.md` als Modulkarte.** Pro Datei eine Zeile „Pfad – Zuständigkeit“, erzeugt aus den „Einzige Zuständigkeit“-Kopfzeilen (`tools/make_modulkarte.py`, damit sie nie veraltet). 290 Zeilen ≈ 5 k Tokens ersetzen das Durchsuchen von 290 Dateien. Dazu zehn Zeilen Datenfluss: `GameManager` lädt → `init()` → `start()`; Client-Anfragen nur über `RateLimiter.connect`; `ClientState` einziger Client-Speicher; Werte in `Config`, Regeln in `Modules`, Welt-Bau in `Util/MapBuild`.

**Vorschlag 1d – `CLAUDE.md` neu schreiben** (Entwurf in Abschnitt 5), `README.md` angleichen, tote Verweise reparieren oder die Berichte zurückholen (Fund 7).

### Fund 2 – Lese-Gewohnheiten: ganze Dateien statt Ausschnitte (kostenlos zu beheben)

Es gibt keine Regel, wie gelesen werden soll. Ein `Read` von `MapConfig` kostet 25 k Tokens, obwohl meist ein Schlüssel gesucht wird. Ein Textfix berührt vier Sprachdateien à 20 k Tokens.

**Vorschlag 2 – Lese-Regeln in `CLAUDE.md`:**
- Erst `Grep` nach Begriff oder Schlüssel, dann `Read` mit `offset`/`limit` auf den Treffer. Dateien über 400 Zeilen nie komplett lesen, außer die Aufgabe verlangt es.
- `Strings/*.luau` nur per Grep nach Schlüssel ansprechen; Änderungen per `Edit` am Schlüssel, nie die Datei lesen.
- `Worldbuilding.md` nur den benötigten Abschnitt (Überschriften mit Grep `^##`).
- Bilder (`docs/screens`, `assets`) nie öffnen, außer der Nutzer bittet um Sichtprüfung.
- Prüfwerkzeuge nur mit `| tail -n 5` bzw. gefiltert lesen.
- Berichte nur über `INDEX.md` auswählen, nie „alle Pakete lesen“.

### Fund 3 – Große Dateien mit hoher Abhängigkeit

Dateien, die oft gebraucht werden und viel kosten (Fan-in = Zahl der Module, die sie requiren; Änderungen = Commits seit 02.10.):

| Datei | Zeilen | Fan-in | Änderungen | Vorschlag Aufteilung |
|---|---|---|---|---|
| `Config/MapConfig.luau` | 1 682 | 58 | 21 | `MapConfig` (Raster, Plots, Brücken) / `MapDecorConfig` (`BUILDING_DECOR`, `CENTER_DECOR`) / `PondConfig` (Teich ab Z. 676). Zusätzlich dringend wegen 192 von 200 Locals (`check_locals`). |
| `Controllers/SkillFXController.luau` | 2 440 | – | 9 | Ordner `Controllers/SkillFX/`: `Kit.luau` (newPart, tween, fadeAndDestroy …) + ein Modul je Show; der Controller nur noch Verteiler. Der 154-Zeilen-Kopf von `SkillFXConfig` in einen Bericht. |
| `UI/BaerchiPanel.luau` | 1 633 | – | 18 | Tabs/Abschnitte als Untermodule (`BaerchiPanel/Karte`, `/Upgrade`, `/Charms`). |
| `Services/MapService.luau` | 1 472 | 21 | 21 | Welt-2- und Pit-v2-Zweige (Z. 138–386, 1 063 ff.) in eigene Services oder `MapBuild`. |
| `Services/EventParticipationService.luau` | 1 490 | – | 14 | Hazard-/Telegraph-Teil abtrennen. |
| `UI/EggTreePanel.luau` | 1 436 | – | – | Layout ist schon ausgelagert (`EggTreeLayout`); Knoten-Rendering und Freischalt-Animation trennen. |
| `Services/EventHandlers.luau`, `EpilogService`, `PitArenaService`, `Util/MapBuild/HubPlazaBuilder` | 1 180–1 580 | | | je ein Schnitt entlang der Banner-Kommentare. |

Ziel: keine Datei über 800 Zeilen. Option C (`make_update_rbxmx.py`) legt neue Skripte an, die Studio-Einspielung bleibt möglich. `Types.luau` (1 204 Zeilen, 101 Abhängige) kann bleiben: eine Quelle ist hier wichtiger als Kürze.

### Fund 4 – Kommentare als Geschichtsbuch

956 datierte Kommentare („`-- 20.10. P5b`“, „`Sammel-Update 05.10. (Paket 4.1)`“) in 158 Dateien; Kopfkommentare bis 154 Zeilen (`SkillFXConfig` 154, `DebugService` 128, `PlotDisplayService` 74, `MapConfig` 63). Das „Warum“ im Kopf ist richtig und gelobt; die Datumsspur ist Historie und steht schon in Git und in den Berichten. Sie kostet bei jedem Lesen einer Hot-Datei 20–30 %.

**Vorschlag 4:** Regel in `CLAUDE.md`: keine Datums- oder Paketnummern im Code, Kopfkommentar höchstens 25 Zeilen („Einzige Zuständigkeit“ + „Warum so“), Historie gehört in Commit und Bericht. Bestand beim nächsten Anfassen einer Datei kürzen, nicht in einem Rutsch (Diff-Rauschen).

### Fund 5 – Lokalisierung: vier Dateien pro Text

Jeder Spieler-Text existiert viermal (de/en/fr/es, je ≈ 80 KB). Jede Textänderung heißt: vier Dateien finden, vier Edits, `check_loc` gegen Drift. Die vier Dateien sind die meistgeänderten Dateien des Repos (je 31 Commits).

**Vorschlag 5 – eine Quelle, vier erzeugte Dateien.** `tools/loc/strings.tsv` (Spalten: Schlüssel, de, en, fr, es, Kommentar) + `tools/loc/build_strings.py`, der die vier `Strings/*.luau` schreibt. `Loc.luau` und das Laufzeitverhalten (lazy require je Sprache) bleiben unverändert; `check_loc.py` prüft weiter die Ausgabe. Eine Textänderung = ein Grep + ein Edit in einer Zeile. Mindestlösung ohne Umbau: Regel aus Fund 2 (nur Grep + Edit am Schlüssel).

### Fund 6 – Feature-Flags: 48 von 52 an, alte Pfade bleiben im Code

220 Abfragestellen. Die am meisten verzweigten Schalter sind seit Wochen an: `UI_HONEY_SKIN` 27 Stellen, `HONEY_POND_V2` 10, `INCUBATOR` 10, `UI_V2_GUIDE` 9, `SHOP_V1` 8, `TOWER_TERMINAL` 7, `BOSS_TIERS` 7. Jeder Schalter hält einen zweiten Codepfad am Leben, der gelesen und mitgedacht werden muss. Der Check vom 12.10. hat das schon vorgeschlagen; für `PIT_V2` steht der Plan („nach Abnahme plus einem Release entfernen“) bereits im Flag-Kommentar.

**Vorschlag 6:** Regel: Flag + alter Pfad werden ausgebaut, sobald das Paket in Studio abgenommen und ein Release draußen ist. Reihenfolge nach Abfragestellen (Liste oben). Bleiben: die vier ausgeschalteten (`POWER_MODEL_V2`, `MAP_GROUND_OLDSCHOOL`, `BAERCHI_KIT_V1`, `FUSION_INVENTORY_TOGGLE`) und `PIT_V2`, solange die Abnahme läuft.

### Fund 7 – Verlorene Dateien beim Merge am 15.10. (`e8f7935`)

Der Merge „Lokalen Stand uebernehmen“ hat den Baum des Heim-PCs komplett übernommen. Gegenüber dem damaligen `main` (`78a7593`) fehlen seither:
- 14 Berichte: `docs/HBB_ARCHITEKTUR_CHECK_2026-10-12.md`, `HBB_PLAYTEST_2026-10-12.md`, `SAMMEL_UPDATE_UMGESETZT_2026-10-05.md`, `HBB_COWORK_EI_UI_PROMPT.md`, `HBB_HUD_INKUBATOR_UFO_2026-10-05.md`, `SAMMEL_6_3_EIKAUF_ENTWURF_2026-10-05.md`, sieben `claude/SHOW_*`/`WELT_AUFGEWERTET_*`/`STUDIO_TERMINAL_MERGE_*` (die toten Verweise aus Fund 1).
- 10 Luau-Tests: `day_cycle`, `egg_tree_layout`, `incubator`, `island_stage`, `migration_v16`, `migration_v17`, `rebirth_rules`, `recycler`, `sound_zones`, `world_moments`.
- Werkzeuge: `check_asset_ids.py`, `einspielen.lua`, `render_vfx_*.py` (5), `tools/art/*` (4), `tools/textures/make_world_textures.py`.
- 21 Quelldateien (15 Client-Controller, 5 Shared-Module, `EggTreeLayout`) wurden am 16.10. repariert („Reparatur nach Gemini-Sync“) und sind wieder da.

Alles liegt in `78a7593` und ist per `git checkout 78a7593 -- <pfad>` wiederherstellbar. Die Tests sind wertvoll, weil sie die Module ohne Studio prüfen; ob sie zum heutigen Code passen, zeigt ein Lauf nach dem Zurückholen.

### Fund 8 – Prüfwerkzeuge: drei von sieben rot, Ausgabe zu laut, Luau-CLI fehlt

Lauf heute (alle `tools/check_*.py`):

| Werkzeug | Ergebnis | Dauer |
|---|---|---|
| `check_locals` | grün, Höchstwert 192/200 (`MapConfig`) | 0,1 s |
| `check_feedback` | **rot**, 8 „Toast ohne Notify.emit“ (`EggTreePanel`, `HatchPanel`, `BaerchiInventory`) | 0,1 s |
| `check_members` | 2 verdächtige Zugriffe (`AmbienceConfig.DAY_CYCLE`, `IncubatorRules.isReady`), Exit 0 | 1,8 s |
| `check_consistency` | **rot**, 3 (DebugService nicht in Boot-Liste, `EggPanelSkin` `--!nonstrict`, `GetDataStore` in `GiftService`) | 1,3 s |
| `check_loc` | grün, aber 67 Zeilen Ausgabe | 1,2 s |
| `check_ui` | **rot**, 43 Funde (T2 31, davon 20 in `server/Debug/*`; T3 8, P2 2, P3 1, T1 1) | **70 s** |
| `check_decor` | grün | 0,1 s |

Syntax (`luau-compile`) über alle 289 Dateien: 0 Fehler. `guide_steps.test.lua` grün, `progression_pacing.lua` „ALLE ZIELE OK“.

Rote Checks kosten jede Sitzung Tokens: Ausgabe lesen, entscheiden, ob der Fund „schon bekannt“ ist. Dazu gibt `CLAUDE.md` acht einzelne Befehle vor, jeder mit eigener Ausgabe. Die Luau-CLI ist in der Cloud nicht installiert; jede Sitzung muss sie selbst besorgen oder die Luau-Tests auslassen.

**Vorschlag 8a – alles grün oder bewusst ausgenommen.** Die 8 + 3 + 2 Funde beheben oder mit `-- ui-ok: <Grund>` bzw. einer Ausnahmeliste im Werkzeug markieren (Debug-Module von T2 ausnehmen: Studio-only, nie Spielertext). Danach gilt: rot = neu.

**Vorschlag 8b – `tools/check_all.py`.** Ein Befehl: Syntax, `check_locals`, alle `check_*.py`, alle Luau-Tests, Pflicht-Sims. Eine Zeile pro Prüfung, Details nur bei Fehlern, Exit 1 bei einem roten Posten. `check_loc` gibt bei grün nur die Schlusszeile aus. `CLAUDE.md` enthält dann einen Befehl statt acht.

**Vorschlag 8c – SessionStart-Hook für die Luau-CLI.** Der Download von `luau-ubuntu.zip` (7,7 MB) funktioniert aus der Cloud-Sitzung (heute getestet, alle Tests liefen). Ein Hook in `.claude/settings.json` lädt sie beim Start nach `luau-bin/` (schon in `.gitignore`) und setzt `LUAU`. Beispiel:

```json
{
  "hooks": {
    "SessionStart": [{ "hooks": [{ "type": "command",
      "command": "test -x luau-bin/luau || (mkdir -p luau-bin && curl -sSL -o luau-bin/luau.zip https://github.com/luau-lang/luau/releases/latest/download/luau-ubuntu.zip && cd luau-bin && unzip -oq luau.zip && chmod +x luau luau-compile luau-analyze); echo 'export LUAU=$PWD/luau-bin/luau PATH=$PWD/luau-bin:$PATH' >> \"$CLAUDE_ENV_FILE\"" }] }]
  }
}
```

Die Skill `session-start-hook` kann das einrichten und prüfen.

### Fund 9 – Repo-Ballast: 578 von 583 MB sind Binärdateien und Kopien

- `assets/` 479 MB (davon `assets/vfx` 410 MB: Blender-Quellen, MP4-Vorschauen, Textur-Sheets), `Export/` 58 MB FBX samt `.fbm`-Texturen, `docs/screens` 20 MB Screenshots, Root: drei `.blend`, ein `.fbx`, ein PNG (6 MB).
- Kopien, die Git schon kennt: fünf `backup_vor_*`-Ordner (35 Luau-Dateien; das `.gitignore`-Muster `/_backup_*/` greift nicht, weil die Ordner `backup_vor_*` heißen), `studio_export/_repo_vor_sync_2026-10-20/` (99 Dateien, nur 1 davon identisch mit heute) und `_merge_konflikt_reste`, `updates/_backup_vor_epilog/` und `updates/Reparatur_2026-10-19/` (4,4 MB `.rbxmx`, trotz Ignore-Regel, weil die nur auf der obersten Ebene greift), `ufo_event/`.
- Versehentliche Datei `--help` im Root (eine HTML-Deko-Vorschau, seit 05.10.).
- „Studio-Sync“-Commits mit über 200 Dateien verstecken Code-Änderungen im `git log --stat`.

Folgen für Tokens: `Glob`/`Grep` liefern Rauschen, `git log`/`git status` werden lang, jede Cloud-Sitzung klont 490 MB (Zeit, nicht Tokens).

**Vorschlag 9:**
- Git LFS für `*.png *.jpg *.blend *.fbx *.mp4 *.ogg *.rbxm *.rbxmx *.rbxl *.rbxlx *.bundle`, oder Blender-/Render-Quellen in ein eigenes Asset-Repo. Spielrelevant im Code-Repo sind nur `assets/icons` (0,6 MB) und wenige Referenzbilder.
- Vor dem Aufräumen Tag `vor-aufraeumen-2026-10-26`; dann entfernen: `--help`, `backup_vor_*` (5), `studio_export/_repo_vor_sync*` und `_merge_konflikt_reste`, `updates/_backup_vor_epilog`, `updates/Reparatur_2026-10-19/*.rbxmx`; Root-Modelle nach `assets/`. Regel „nichts löschen“ betrifft Spielinhalte; das hier sind Kopien, deren Original in Git liegt. Entscheidung bitte ausdrücklich.
- `.gitignore`: `/backup_vor_*/`, `/updates/**/*.rbxmx`, `/updates/**/*_Befehl.lua`.
- Optional `.claude/settings.json` mit `permissions.deny` für `Read(./assets/**)`, `Read(./Export/**)`, `Read(./docs/screens/**)`, damit kein Werkzeug versehentlich Binärdateien liest.
- Code-Commits und Asset-Commits trennen („Studio-Sync: Quelltext“ / „Studio-Sync: Assets“ ist schon der richtige Ansatz).

### Fund 10 – Kleinigkeiten

- `Main.client.luau` requiret 71 Module von Hand; eine Liste wie in `GameManager` (Name + Modul) würde Reihenfolge und Vollständigkeit prüfbar machen (`check_consistency` kann das wie beim Server).
- `DebugProgress.luau` requiret 28 Module, `DebugService` wird außerhalb der Boot-Liste gestartet (Fund von `check_consistency`): eine Zeile Ausnahme im Werkzeug oder Aufnahme in die Liste.
- `src/shared/Assets.rbxm` liegt im Repo, `src/shared/Assets/BaerchiTemplate.rbxm` fehlt (CLAUDE.md warnt davor). Entweder sichern oder die Warnung streichen.

## 4. Reihenfolge und Aufwand

| # | Maßnahme | Ersparnis (Schätzung) | Aufwand | Risiko |
|---|---|---|---|---|
| 1 | `STATUS.md`, `INDEX.md`, `ARCHITEKTUR.md`, `CLAUDE.md` neu, `README` angleichen, tote Verweise | 10–30 k Tokens je Sitzung (weniger Suchen und Fehllesen) | 1 Sitzung | keins |
| 2 | Lese-Regeln in `CLAUDE.md` | 10–50 k je Sitzung bei großen Dateien | 10 Minuten | keins |
| 3 | `check_all.py`, Checks grün, SessionStart-Hook, Tests aus `78a7593` zurück | 3–8 k je Commit, Luau-Tests laufen ohne Nachfrage | 1 Sitzung | gering |
| 4 | Aufräumen + `.gitignore` + LFS | Clone 490 MB → ~10 MB, kürzere Glob/Log-Ausgaben | 1 Sitzung | Entscheidung „löschen“ nötig |
| 5 | Loc-Generator (eine Quelle) | 15–20 k je Textänderung | 1 Sitzung | gering, Ausgabe bleibt gleich |
| 6 | Splits: `MapConfig`, `SkillFXController`, `BaerchiPanel`, `MapService` | 10–20 k je Lesen einer Hot-Datei; `MapConfig` vor dem 200-Locals-Limit | 2–3 Sitzungen | Studio-Einspielung (neue Dateien, Option C kann das) |
| 7 | Kommentar-Diät, Flags ausbauen | 20–30 % je Lesen, laufend | beim Anfassen | gering |

## 5. Entwurf für eine neue `CLAUDE.md`

```markdown
# Honey Bear Brawl (RBL) – Hinweise für Claude Code

Roblox-Spiel (Luau, Rojo-Layout). Einstieg in dieser Reihenfolge, nicht mehr:
1. `docs/STATUS.md` (Stand je Bereich, offen, zuletzt eingespielt)
2. `docs/ARCHITEKTUR.md` (Modulkarte: eine Zeile je Datei)
3. Nur den Bericht aus `docs/INDEX.md`, den die Aufgabe braucht

## Struktur
`src/shared` → ReplicatedStorage (Config = Werte, Modules = reine Regeln, Network/Types+Remotes = einzige Quellen, Localization)
`src/server` → ServerScriptService (Core/GameManager startet alles; Services; Util/MapBuild baut die Welt; Debug nur Studio)
`src/client` → StarterPlayerScripts (Main.client lädt; Controllers = Welt/Verhalten; UI = Fenster; ClientState einziger Speicher)
Schalter: `FeatureFlags.isOn("NAME")`. Spieler-Texte nur über `Loc` (Config-Namen: `Localization/Names`, Welt-Texte: `Localization/WorldText`).

## Regeln
- `--!strict`, deutsche Kommentare (Warum, nicht Geschichte: keine Daten, keine Paketnummern im Code; Kopf ≤ 25 Zeilen).
- Server ist autoritativ; Währungen schreibt nur EconomyService; Remotes nur über RateLimiter.connect.
- Keine Datei über 800 Zeilen; neue Zuständigkeit = neue Datei.
- Nichts aus Studio löschen. Flag + alter Pfad werden nach Abnahme + 1 Release ausgebaut.

## Sparsam lesen (wichtig)
- Erst Grep, dann Read mit offset/limit. Dateien > 400 Zeilen nie komplett lesen.
- `Strings/*.luau` nur per Grep nach Schlüssel, Änderung per Edit am Schlüssel.
- Bilder und `assets/` nie öffnen. Prüf-Ausgaben nur `tail`/gefiltert.
- Am Ende der Sitzung `docs/STATUS.md` fortschreiben (max. 60 Zeilen), Bericht nur bei neuem Paket.

## Prüfen (vor jedem Commit, ein Befehl)
`python tools/check_all.py` – Syntax, Locals (max. 200), check_*, Luau-Tests, Pflicht-Sims. Nur rote Zeilen lesen.
Luau-CLI kommt per SessionStart-Hook nach `luau-bin/` (`LUAU` ist gesetzt).

## In Studio bringen
`python tools/make_update_rbxmx.py [<seit-commit>]` → `updates/HBBUpdate.rbxmx` importieren, `updates/HBBUpdate_Befehl.lua` in die Befehlsleiste. Kein Rojo (löscht Studio-Inhalte). Danach Datei → Auf Roblox speichern.
```

## 6. Was dieser Bericht nicht geprüft hat

Laufzeitverhalten in Studio, Netzlast der Remotes, Balance-Werte (Sims liefen grün). Die Funde aus dem Check vom 12.10. (DRY-Doppelungen, tote Remotes) wurden nicht erneut einzeln verifiziert.
