# Himmelsgericht (`SeraphJudgment`) – neue Fähigkeit für den Seraph-Bärchi (gebaut 26.10.2026, Studio-Einbau offen)

Auftrag des Nutzers (Englisch): „create an extraordinary skill for the seraph bear, which will get the most dopamine out of every kid playing this game … really get on to the next level with this one“ – mit dem Zusatz, den Roblox-Studio-MCP zu nutzen, und „studio is always up to date, git may miss out on some informations“.

Stand dieser Sitzung (Claude Code, Laptop): Der Studio-MCP war in dieser Sitzung **nicht angebunden** (siehe „Studio-Anbindung“). Gebaut und geprüft wurde deshalb gegen den Studio-Stand aus der Place-Datei `261026aktuell.rbxl` (gespeichert 26.10. 00:11, ausgelesen per eigenem Extraktor). Der Einbau in Studio geschieht mit `updates/SeraphJudgment_2026-10-26/Einfuegen_Befehl.lua` (Anker-Einfügung auf dem Live-Quelltext, prüft alles vorher). Bühnen-Tests, Messlauf, echter Lauf und die Review-Vorlage stehen noch aus (Abschnitt „Offen“).

## Was

- Neue Fähigkeit `SeraphJudgment` („Himmelsgericht“, en „Heaven's Judgment“, es „Juicio Celestial“, fr „Jugement Céleste“) für `SeraphBaerchi` (Divine, Pfad Gold, HP 2900 / ATK 170 / SPD 0,85 / PWR 0,18). `defaultSkill` umgestellt (vorher `SeraphGrace` „Seraphen-Segen“, Heal 22 %); `SeraphGrace` bleibt für vorhandene Bärchis und Fusionen.
- Kampfwerte: `effectType = "Opener"`, Ladung 4 (wie vorher), `openerMultiplier 3.4`, `multiplier 1.8`, `baseDamage 60`. Der erste Einsatz je Gegner (je Stage, `opened` wird je `simulate` zurückgesetzt) trifft mit 3,4× ATK + 60, jeder weitere im selben Kampf mit 1,8× ATK + 60. Nachteil: nur der erste Einsatz je Gegner trifft voll, keine Heilung mehr. Einordnung: Divine zwischen Mythic und Cosmic (Höllensiegel ≈ 2,7×+105, Pulsar-Nova Cosmic ≈ 2,85×+120 bei Ladung 5); der Seraph ist der langsamste Divine, je Sekunde bleibt Pulsar-Nova klar stärker. Opener-Bonus liefert zusätzlich `bonus = true` beim ersten Einsatz – die volle Show (erster Einsatz im Lauf) hat ihn damit immer, das Echo bekommt im Bonusfall die globale Lichtsäule.
- Motiv (Dopamin-Plan für Kinder): Rhythmus beim Aufladen (drei hörbare Flügel-Schnapper), Senkrechte (ein Himmelstor so groß wie das halbe Pit), Heldenmoment (der Bärchi selbst fliegt und bekommt einen Speer aus Licht), Urteil (Ticks, Zielmarke schrumpft, Stille), Wucht (4 Impact-Frames, Hitstop, Trauma-Shake mit Drehung, Knall nach dem Blitz), Nachklang nach der Nuke-Grammatik 2.5 (Säule, Druckwelle, Kuppel, fallende Kondensringe, Federregen, Brandsiegel) und eine Pointe (die kleine Krone des Tors landet schief auf dem Gegner und ploppt).
- Farben: Honiggold (255, 214, 110) + warmes Weiß (255, 246, 225), Akzent dunkles Honiggold (230, 160, 40); Impact-Frames Indigo (70, 50, 160) / Warmweiß. Umriss des Klons dunkles Gold (214, 150, 30) (F37/F54).

## Ablauf der Show

Stufe 4, 5,9 s, Treffer (`impactAt`) 3,28 s. Eine Kamerafahrt 1,05–3,55 (Stil `seraph`). Echo 0,65 s, Treffer 0,26 s.

| Zeit (s) | Takt |
|---|---|
| 0,00 | Welt warm-golden (Besitzer), goldene Marke unter dem Seraph (`ring` mit Bild `halo`), er duckt sich (`moves`) |
| 0,20 / 0,42 / 0,64 | die drei Flügelpaare schnappen von oben nach unten auf (`seraphwings`: Funken an den Spitzen, Lichtfedern als Beams, Flügel werden ForceField-Licht), je ein `snap` |
| 0,78 | Heiligenschein (`acc_halo`) zündet (Neon, dreht, pulst), `ping` |
| 1,00 | Absprung mit Staub, 1,45 oben: 12,8 Studs, zwei Drehungen, Schweif und goldene Nachbilder |
| 1,05–3,55 | Kamerafahrt: tief vorn-seitlich, steigt mit, kippt hoch; Push-in beim Zielen; Peitsche im Sturz; harter Schnitt in die Untersicht am Einschlag; Ende Custom |
| 1,10 | Himmelstor öffnet sich 24 Studs über der Arena-Mitte (`halogate`: drei Ringe aus Bezier-Beams, Radius 16, erst klein, dann groß), `thunder`; 1,45 Lichtschäfte; 1,30 Federn rieseln |
| 1,90–2,35 | Speer aus Licht entsteht am Tor und sinkt in die Pfoten (`seraphspear`), `glass` |
| 2,30 | Zielmarke unter dem Gegner schrumpft (`seraphmark`), Gegner-Klon schaut hoch und zittert, Lichtfaden vom Tor; Ticks 2,35 / 2,55 / 2,70 (`ping`, Mini-Beben, Tor pulst) |
| 2,95 | Ausholen, Stille (`silence` 0,1) |
| 3,02 | Sturz speervoraus (k², Nachbilder, Flügel angelegt), `lunge` |
| 3,26 | Blitz (gold, 0,08) |
| **3,28** | **Treffer**: Landung vor dem Gegner, Speer steckt an seinen Füßen; 4 Impact-Frames hell/indigo (0,20 s), Hitstop 0,18 (FOV −12), `hit`; kleiner getönter Kern (`lightnuke`, ≤ 3,2 Körperradius) |
| 3,38 / 3,40 | Knall nach dem Blitz (`boom`, `bass`) |
| 3,40–3,46 | Lichtsäule schießt 160 Studs hoch (global), Brandfleck mit goldenem Siegel und sechs Rissen; 3,42 `quake` 1,0 |
| 3,43–3,55 | Lichtwand bis zum Zaun (zwei Wellen), Bodenring, Federtrümmer, Staub, `rumble` |
| 3,70 | Wand erreicht die Kamera: Blitz + zweites Beben (`quake` 0,5) |
| 3,80–4,35 | die Torringe stürzen die Säule herab und werden zu Kondensringen (14 / 9,5 / 5 Studs über dem Einschlag, dehnen sich, verblassen), Welt −0,18 dunkler und golden |
| 3,88–5,0 | goldene Kuppel (ForceField, zwei Schalen, Radius 11) wächst und verblasst, Glut |
| 4,00 | Federregen über der Arena |
| 4,35 | der Seraph zieht den Speer, er zerfällt zu Federn und Funken |
| 4,75–5,40 | Rückwärtssalto heim, Landung |
| 5,05 | die kleine Krone des Tors landet schief über dem Kopf des Gegners (`ping`) |
| 5,65 | sie ploppt (Funken, `snap`); 5,9 Ende |
| Echo | Lichtspeer fällt von oben in die Zielmarke (0,5 s), 0,26 ein Impact-Frame + Hitstop 0,06 + Beben 0,4, Bodenring, Federn, Sterne; Bonus: Lichtsäule 60 Studs (global) + Zaunring |

Schlag-Tabelle (2.4) steht im Kopfkommentar des Eintrags.

## Umsetzung

`SkillFXController` (Studio-Stand 13.182 Zeilen → 14.294, lokale Namen auf Modulebene 140 → 141):
- Neue Bausteine vor „-- Abspielen“, alle Helfer in EINER Tabelle `SER` (F51): `quake` (Trauma-Shake: Stärke = Trauma², Drehung per `math.noise` 4° bei Trauma 1, Versatz 0,4, Abklingen 1,1/s, `BindToRenderStep` Camera + 2 = letzter Offset nach Spielkamera, Fahrt und `shake`; optionaler FOV-Stoß), `seraphwings` (sechs `acc_wing*`-Teile und `acc_halo` des `moves`-Klons: Schnapper, Schlag, Lichtfedern, Nachbilder per `chronoGhost`, Spreizen/Anlegen je Phase), `seraphspear` (Speer: Neon-Kern, ForceField-Hülle, Keil-Klinge, Parierscheibe, Troddeln; Entstehen am Tor, Griff an `avatarCf`, Zielen, Sturz, Stecken, Ziehen; setzt `ctx.seraphHit`), `halogate` (drei `novaRing`-Ringe + Lichtschäfte, Ticks, Fall zur Säule, Kondensringe, Krone; setzt `ctx.seraphGate/seraphGateR`), `seraphmark` (Zielmarke als `halo`-Decal, Lichtfaden, Gegner-Klon mit `hideFigure`, Freigabe bei 3,26 für den Server-Rückstoß, F15), `lightnuke` (Kern, Säule aus zwei `column`-Beams, Lichtwand per `hellRing`, Brandfleck + Siegel + `groundStroke`-Risse, Kuppel, Glut; `far` = nur Kern + Säule).
- `impactframe`: optionale Palette `dark`, `light`, `fill` (Standard unverändert = Höllensiegel-Rot).
- `BLOCKS.cinematic`: Stil `seraph` (+ `local seraphSide`), Kamera-Seite aus `oldCf`.
- `type Ctx`: `seraphGate`, `seraphGateR`, `seraphHit`.
- Bewegung des Seraphs komplett als Daten (`moves`, 20 Posen); `moves` ist unverändert.

`SkillFXConfig`: Eintrag `SeraphJudgment` (Kopfkommentar mit Takten und Schlag-Tabelle), `TEXTURES.SeraphJudgment` (nur wiederverwendete Bilder: SeraphGrace `feather/halo/column/spark`, CometImpact `stardust`), Doku der Bausteine im Dateikopf. `SkillConfig`: Eintrag vor dem v15-Kopf. `BaerchiConfig`: `defaultSkill`. `Strings de/en/es/fr`: `skill.SeraphJudgment.name/.desc/.drawback` neben `skill.SeraphGrace.name`.

Werkzeuge dieser Sitzung (im Paket): `rbxl_extract_scripts.py` (liest alle Skripte aus einer binären Place-Datei, zstd), `rbxl_dump_subtree.py` (Instanzbaum mit Größen/Farben/CFrames – so kam die exakte Seraph-Geometrie: 23 MeshParts, Halo 2,0 über der Körpermitte, Flügel 1,05 hinter dem Körper), `apply_seraph.py` (Anker-Einfügung mit 1×/0×-Prüfung), `make_seraph_package.py` (erzeugt Befehl und rbxmx).

## Getestet (ohne Studio)

- `luau-compile --null` für alle acht geänderten Skripte: ok (Controller 14 KLOC → 523 KB Bytecode).
- Lokale Namen auf Modulebene des Controllers: 141 (Grenze 200, Warnung ab 180). Keine Verdeckung von Modul-Helfern durch neue lokale Namen (F57, automatisch geprüft). Alle `fx`-Namen des Eintrags existieren als `BLOCKS.*`, alle Sound-Slots in `sounds`.
- Sims und Prüfungen des Projekts auf einem Scratch-Baum „Studio-Stand + Himmelsgericht“ (`run_local.py` mit eigenem ROOT): `egg_tree_check` (FX-Eintrag vorhanden, Komposition eindeutig, Dauer ≤ 6,0, Sound-Schritt), `fight_timeline` (Treffer 3,28 / 5,9, Zeitbudget OK), `ui_texts` (1312 Texte in 4 Sprachen, 0 Fehler), `combat_rating` (rho ≥ 0,85 OK), `tower_calibration` (alle Ziele OK, „L50 P5 Divine schafft Final 100“), `boss_balance` (OK, „Stark“ = Seraph 50.181 DPS), `rarity_capability` (Tabelle).
- Der Studio-Befehl wurde headless gegen die extrahierten Quelltexte simuliert: 16 Stücke in 8 Skripten, `loadstring` grün, Ergebnis byteidentisch mit den geprüften Dateien (Hash-Vergleich).
- Adversarial Review durch fünf unabhängige Prüfer (API, Luau-Logik, Regelwerk, Budget, Geometrie) mit Gegenprüfung je Befund: siehe Abschnitt „Befunde des Reviews“.

Nicht geprüft (braucht Studio): Bilder, eingefrorene Bühnen, Messlauf (Landung 3,27 ± 0,05, Shake-Amplitude, Farbfilter-Reihenfolge), echter PIT-Lauf, Echo, Zuschauer-Sicht, Aufräum-Check, Klang.

## Befunde des Reviews

Das Review mit fünf unabhängigen Prüfern wurde auf Wunsch des Nutzers abgebrochen (Token-Aufwand). Es liegt kein Review-Ergebnis vor; die Sichtprüfung in Studio (Phase 4/5) ersetzt es. Beim eigenen Durchgang behoben: eine Zeile, die mit `(x :: T).Prop =` nach einem Aufruf begann (Luau: „Ambiguous syntax“), die NumberSequence-Grenze von 20 Stützpunkten im gestrichelten Torring, die Troddel-Attachments der Parierscheibe (lokale Achsen der gedrehten Scheibe) und `CFrame.fromMatrix` mit zwei Achsen für den Speer.

## Repo-Abgleich (26.10., in dieser Sitzung)

Die acht Skripte (Controller, SkillFXConfig, SkillConfig, BaerchiConfig, Strings de/en/es/fr) wurden per 3-Wege-Merge (Basis = Commit `51ffce2` „Studio-Sync 2026-10-25“, Repo-Stand mit Tränke-Texten, Studio-Stand 00:11 + Himmelsgericht) ins Repo übernommen – ohne Konflikte; Tränke-Texte, die 25.10.-Shows und das Himmelsgericht sind jetzt alle im Repo. Die `\u{…}`-Escapes der 25.10.-Texte wurden dabei in echte Zeichen umgesetzt (sonst meldet `check_loc.py` sie als Platzhalter). Prüfungen im Repo: `luau-compile` ok, `check_locals` (Controller 141), `check_loc` 0 Fehler, `check_ui` unverändert (41 bekannte Stellen), `ui_texts` 0 Fehler, `egg_tree_check`, `tower_calibration`, `progression_pacing` OK. Nicht committet.

Achtung für den Tränke-Einbau: Die Repo-Strings enthielten vor dem Merge die 25.10.-Skilltexte nicht; ein `HBBUpdate.rbxmx` aus dem alten Repo-Stand hätte sie in Studio gelöscht. Jetzt ist der Repo-Stand vollständig.

## Studio-Anbindung (warum der MCP fehlte)

Die Werkzeuge `list_roblox_studios`, `execute_luau`, `script_read` … kommen aus Studios eingebautem MCP-Server (lokal, stdio: `%LOCALAPPDATA%\Roblox\mcp.bat` → `StudioMCP.exe`), nicht aus einem claude.ai-Connector. In Claude Code muss er einmal registriert werden:
1. Studio: Assistant → „…“ → Manage MCP Servers → „Enable Studio as MCP server“ einschalten (Studio offen lassen).
2. In einem normalen Terminal (nicht in der laufenden Claude-Sitzung), PowerShell:
   `claude mcp add --transport stdio --scope user Roblox_Studio -- cmd.exe /c C:\Users\admin\AppData\Local\Roblox\mcp.bat`
3. `claude mcp list` → „Connected“; Claude Code neu starten (`claude -c` setzt diese Unterhaltung fort); `/mcp` zeigt den Server. Werkzeuge heißen dann `mcp__Roblox_Studio__<tool>`.

## Nachtrag 26.10. nachmittags: Einbau und Migration

- Per Studio-MCP eingespielt (13 Stücke in 8 Skripten; eigener `quake` und impactframe-Patch entfielen, weil die Sitzungen „Gletscherblick“/„Himmelsgeläut“ vom Vormittag beide schon in Studio hatten – die Show nutzt deren `quake` mit `trauma`). Verifiziert: Bausteine je 1×, Controller 144 lokale Namen, Configs laden (5,9 s / 3,28 s, Echo 0,65 / 0,26), Texte in 4 Sprachen, Backup mit 9 Skripten.
- Auf Wunsch des Nutzers („ALL seraph bears“): Lade-Migration `stepSeraphSkill` in `ServerScriptService/Util/PlayerMigration` (Studio und Repo): jeder Bärchi mit `skillId = "SeraphGrace"` bekommt beim Laden `SeraphJudgment` (am Feld erkennbar, wiederholbar; `SeraphGrace` bleibt in `SkillConfig`). `migration_golden` 27 Fälle OK; `migration_hbb` scheitert vorher wie nachher an „C4 Rekord Tower I“ (bekannt, unabhängig).

## Offen

1. Einbau in Studio (Edit-Modus): `updates/SeraphJudgment_2026-10-26/Einfuegen_Befehl.lua` in die Befehlsleiste – legt `ServerStorage/Backup_vor_Himmelsgericht_2026-10-26` an, prüft Anker (1×) und neue Namen (0×) auf dem Live-Quelltext, `loadstring`, speichert nur, wenn alles passt; Strg+Z macht es rückgängig. Rückfall: `HBBUpdate_Himmelsgericht_2026-10-26.rbxmx` + `_Befehl.lua` (ganze Quelltexte, ersetzt nur Skripte mit unverändertem Hash). Danach Datei → Auf Roblox speichern.
2. Phase 4/5 in Studio (mit MCP): Bühnen (0,7 Flügel offen · 1,7 Schweben + Tor · 2,4 Speer gegriffen · 2,9 Marke eng · T 3,28 Impact-Frame · T + 0,15 Säule/Wand · T + 0,6 Kuppel · 4,35 Kondensringe · 5,05 Krone · Echo 0,27), Messlauf (Landung ± 0,05, `quake`-Delta je Bild in Grad, Farbfilter-Rücksprünge, Emitter-TimeScale im Hitstop), echter Lauf (1 + Echos, 0 Warnungen, Kamera Custom, FOV 70), Aufräum-Check.
3. Review-Vorlage (2.8) nach der eigenen Sichtung des Nutzers; Antworten ins Register.
4. Spielstand: eigene Seraph-Bärchis migrieren (`RBLDebug('skill', uid, 'SeraphJudgment')`) bzw. einen Lv.-50-Seraph ins Inventar (`('add', 'SeraphBaerchi', 50)`) – nur nach Zustimmung.
5. Klang: Schichten aus der 15er-Bibliothek; Riser/Tape-Stop/Sub-Boom bleiben Wunsch an den Sound-Skill.
6. `shake` → `quake` für die älteren Shows umstellen, sobald `quake` in Studio gemessen ist (offener Punkt 10.1/10.2 des Skills).
