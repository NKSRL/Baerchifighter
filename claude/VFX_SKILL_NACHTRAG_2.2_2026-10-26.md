# Nachtrag zum Skill `roblox-skill-vfx` – Vorschlag 2.2 (26.10.2026, Sitzung „Himmelsgericht“)

Kurzfassung statt kompletter SKILL.md (Wunsch des Nutzers: schnell fertig werden). Beim nächsten Skill-Gespräch in die SKILL.md einarbeiten (Phase 7.7: ganze Datei vorschlagen).

## Changelog 2.2
- Sitzung „Himmelsgericht“ (Seraph-Baerchi, Divine, Stufe 4) in Claude Code auf dem Laptop, **ohne** Studio-MCP: Studio-Wahrheit aus der Place-Datei gelesen (Abschnitt C neu), gebaut, headless geprüft, Paket + Einfüge-Befehl erzeugt; Studio-Phasen 4/5 offen.
- Neue Bausteine: `quake` (Trauma-Shake, Schlag-Paket Punkt 10.2 teilweise erledigt), `seraphwings`, `seraphspear`, `halogate`, `seraphmark`, `lightnuke`; `impactframe` mit Palette `dark/light/fill`; Kamera-Stil `seraph`; ctx `seraphGate/seraphGateR/seraphHit`; Helfer in Tabelle `SER` (Controller 141 lokale Namen).
- Erstmals Choreografie einer Stufe-4-Show komplett mit `moves` (20 Posen) statt eigener Tanz-Funktion – Accessoire-Bausteine (`seraphwings`) posieren die Teile des `moves`-Klons relativ zu `GetPivot()` je Bild (BulkMoveTo; Reihenfolge mit `moves` egal, weil PivotTo relative Lagen mitnimmt).

## Neue Fehler-/Lehren-Einträge
| ID | Symptom | Ursache | Regel |
|---|---|---|---|
| F59 (C) | Claude Code auf dem Laptop hat keine Roblox-Werkzeuge; „please use the Roblox Studio MCP“ war nicht erfüllbar | Die Studio-Tools (`list_roblox_studios`, `execute_luau` …) sind Studios eingebauter MCP-Server (lokal, stdio `%LOCALAPPDATA%\Roblox\mcp.bat`), kein claude.ai-Connector; in Claude Code muss er einmal registriert werden | Studio: Assistant → … → Manage MCP Servers → „Enable Studio as MCP server“; Terminal: `claude mcp add --transport stdio --scope user Roblox_Studio -- cmd.exe /c C:\Users\admin\AppData\Local\Roblox\mcp.bat`; `claude mcp list` → Connected; Claude Code neu starten (`claude -c`). Dem Nutzer sofort melden, nicht lange probieren (F21) |
| F60 (C) | Ohne MCP keine Studio-Wahrheit (Repo hinkt) | Place-Datei `.rbxl` ist binär (zstd-Chunks) | Extraktor `rbxl_extract_scripts.py` (alle Skripte + Index) und `rbxl_dump_subtree.py` (Instanzbaum mit `size`, `Color3uint8`, CFrame – exakte Modellgeometrie) im Paket `updates/SeraphJudgment_2026-10-26/tools`; braucht `pip install --user zstandard`, Aufruf mit `python -I` + `site.getusersitepackages()`. Stand = letzte Speicherung, nicht die laufende Sitzung |
| F61 (C) | `luau-compile`: „Ambiguous syntax“ | Anweisung begann mit `(decal :: Decal).Transparency = …` direkt nach einem Funktionsaufruf | In Luau nie eine Anweisung mit `(` beginnen – Zwischenvariable oder `;` davor |
| F62 (A) | Gestrichelter Ring mit 25 Stützpunkten hätte zur Laufzeit geworfen | NumberSequence erlaubt höchstens 20 Keypoints | Muster für `novaRing.pattern` auf ≤ 20 Stützen halten (4 Striche je Viertel = 17) |
| F63 (C) | Repo-Strings hatten die Tränke-Texte, Studio die 25.10.-Skilltexte – ein rbxmx-Import aus dem Repo hätte Studio-Texte gelöscht | Zwei Quellen, die beide Neues haben | Repo-Abgleich nur als 3-Wege-Merge (`git merge-file`, Basis = letzter Studio-Sync-Commit, ours = Repo, theirs = Studio) – lief für 8 Dateien konfliktfrei; `\u{…}`-Escapes danach in echte Zeichen wandeln, sonst meldet `check_loc.py` Platzhalter |
| F64 (C) | Ein 5-Prüfer-Review-Workflow kostete > 1 M Token und lief nach einer Nutzungsgrenze neu an; der Nutzer brach ab („stop reviewing … finish soon“) | Ultracode-Verhalten + Workflows ohne Journal-Ergebnis | Bei diesem Nutzer höchstens EIN Lese-Workflow, keine adversarialen Verifikationsstufen; Review durch die Studio-Sichtung ersetzen; Paket und Zusammenfassung früh liefern |

## Projektkarte – Ergänzungen
- Schlag-Bausteine: `quake` (Besitzer; power = Trauma, decay 1,1/s, angle 4°, offset 0,4, freq 22, optional fov – nicht mit `hitstop` kombinieren); Amplitude in Studio noch nicht gemessen → danach `shake` in den alten Shows auf `quake` umstellen (10.1/10.2).
- `impactframe` Palette: `dark`, `light`, `fill` (Color3); Standard = Höllensiegel-Rot.
- Pet_Seraph (aus der Place-Datei): 23 MeshParts `Pet_Seraph_<teil>`, Höhe 3,4; Halo `acc_halo` 2,0 über der Körpermitte; sechs Flügel `acc_wing10/11/12` (links) und `acc_wing-10/-11/-12` (rechts) 1,05 hinter dem Körper, Rotation Identität; Farben Weiß + Honiggold (255,237,149) + Rosa.
- Einspielen ohne MCP: `updates/SeraphJudgment_2026-10-26/Einfuegen_Befehl.lua` (Anker 1×, Namen 0×, loadstring, Backup, UpdateSourceAsync) – Muster für künftige Pakete (`make_seraph_package.py`).

## Register – neue Zeile
| SeraphJudgment „Himmelsgericht“ (26.10., Laptop) | Seraph `SeraphBaerchi` (Divine) | Opener 3,4×+60 (1. Einsatz je Gegner), sonst 1,8×+60, Ladung 4, 5,9 s, impactAt 3,28, Fahrt „seraph“ 1,05–3,55 | Gebaut + headless geprüft; Studio-Einbau, Bühnen, Messlauf, echter Lauf, Review-Vorlage offen. Bericht `docs/HBB_HIMMELSGERICHT_2026-10-26.md`. |

## Vorlieben – Ergänzung
- Fordert Aufträge auch auf Englisch mit Superlativen („extraordinary“, „most dopamine“, „next level“) – als Stufe 4 mit vollem Schlag-Rezept und Nuke-Grammatik lesen, Dopamin-Plan im Entwurf benennen (Rhythmus, Senkrechte, Heldenmoment, Urteil, Wucht, Nachklang, Pointe).
- Will schnell fertige Ergebnisse; große Review-Workflows abbrechen, wenn er es sagt (F64).

## Offene Vorhaben – Ergänzung
10. Himmelsgericht in Studio einspielen und testen (Phase 4/5), `quake` messen, danach VoidCrown/Weltenende nachrüsten; Spielstand: eigene Seraph-Bärchis migrieren bzw. Lv. 50 ins Inventar (nach Zustimmung).
