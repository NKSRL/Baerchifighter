# Final-Epilog · Prompt 4 von 7 — Start-Terminal mit rotem Knopf (20.10.2026)

Stand: umgesetzt und lokal geprüft. **Nicht in Studio getestet**, Blender-Assets inzwischen **erstellt** (siehe `docs/HBB_EPILOG_ASSETS_2026-10-20.md`), Studio-Import/Upload offen (Primitive als Fallback), Zustands-Bild ist nur eine **grobe Skizze aus den Layout-Zahlen**, keine Studio-Aufnahme.

## Was gebaut wurde
Auf dem Podest der Insel (Mount aus `EpilogIslandBuilder.getTerminalMount`) steht ein grauer Kontroll-Block mit schräger Konsole, rotem Knopf (Ø 2,2) unter durchsichtiger roter Schutzklappe, drei Statuslampen, Bildschirm, Antenne + Kabel, Goldkanten und gelb-schwarzem Warnstreifen am Sockel. Das alte Tower-Terminal ist **unverändert** (nur Zeilenenden-Differenz im Git-Status, Inhalt gleich).

| Datei | Zweck |
|---|---|
| `src/shared/Modules/EpilogTerminalLayout.luau` (neu) | reine Geometrie im lokalen System (Ursprung Sockelunterseite, Front −Z), 21 Teile `Epilog_Terminal_*` |
| `src/server/Util/MapBuild/EpilogTerminalBuilder.luau` (neu) | baut Modell `Epilog/Terminal`, führt `EpilogTerminalState`, serverseitiger ProximityPrompt, Annäherungs-Prüfung, `build/setState/destroy` |
| `src/client/Controllers/EpilogTerminalController.luau` (neu) | Bildschirm (Loc), Lampen, Klappe (Scharnier, Back), Knopf (Puls, Senken), Funken-Emitter |
| `tools/luau-tests/epilog_terminal.test.lua` (neu) | 44 Prüfungen |
| `docs/screens/EPILOG_P4_terminal_zustaende.png` (neu) | grobe Zustands-Skizze |
| `Config/EpilogConfig.luau` | neu: `TERMINAL` (Maße, Zeiten, Palette, Zustände), `ASSETS` um 3 Einträge |
| `Util/MapBuild/EpilogIslandBuilder.luau` | Haken `onTeardown` (Terminal verschwindet mit der Insel, auch vor dem Schrumpfen beim animierten Abbau) |
| `Services/MapService.luau` | Wrapper `buildTerminal/setTerminalState/getTerminalState/hasTerminal/countTerminalParts`, Aufräumen, Wiederaufbau nach Plot-Neuaufbau |
| `Services/EpilogService.luau` | Zugriffsprüfung, `onLaunchRequested` (Stub), `debugTerminal`, Terminal in Restore + nach Brückenbau, `scan` erweitert |
| `Services/DebugService.luau` | `epilog terminal [zustand]` |
| `Localization/Strings/{de,en,fr,es}.luau` | `epilog.terminal.*` (5 Schirmtexte, Prompt-Aktion, Prompt-Objekt) |
| `src/client/Main.client.luau` | `EpilogTerminalController.init()` |

## Zustände (Attribut `EpilogTerminalState` am Modell `Terminal`)
| Zustand | Auslöser | Darstellung |
|---|---|---|
| `idle` | Standard | Schirm „FREIGABE ERFORDERLICH" (rot), Lampen rot blinkend (±0,1 s Mikro-Offset), Klappe zu |
| `ready` | Besitzer < 12 Studs (Hysterese 14), Server prüft 2×/s | Lampen der Reihe nach gelb, „BEREIT", Klappe 25° (0,5 s, Back), Knopf pulsiert ±15 % / 1,2 s |
| `armed` | Prompt-Halten beginnt | Klappe ganz auf (105°), Lampen gelb flackernd, „HALTEN …"; Loslassen vor Ablauf → zurück auf `ready` |
| `fired` | Prompt voll gehalten → `onLaunchRequested` | Knopf senkt sich 0,25 (Quad, „Klack"), Lampen blitzen grün, „FREIGABE ERTEILT", Funken |
| `done` | **Prompt 6** | „WELT 2 OFFEN", dauerhaft grün |

## Prompt
Serverseitig am unsichtbaren `Epilog_Terminal_Ausloeser` (8 × 8 = 64 Studs Touch-Fläche): `HoldDuration` 1,2 s (nativer Ladering), Distanz 8, `RequiresLineOfSight = false`. Text über `WorldText` + `Loc.msg`. **Prompt ist nur an**, wenn Flag an und `epilog.state` pending/seen, Spieler lebt und Zustand idle/ready/armed; nur der Besitzer löst aus.

## Schnittstelle für Prompt 6
`EpilogService.onLaunchRequested(player) -> boolean`: **STUB**. Verlangt Zustand `armed`, setzt `fired`, **speichert nichts**. Prompt 6 füllt: Welt 2 schreiben (`markLaunched`), Finale, danach `MapService.setTerminalState(player, "done")`. Weitere Haken: `EpilogTerminalBuilder.setAccessCheck`, `setLaunchHandler`, `setState`, `getState`, `exists`; `MapService.buildTerminal(player, startState?)`.

## Test in Studio
```lua
D:Invoke("epilog","on"); D:Invoke("epilog","start")     -- pending, Insel, Brücke, Terminal (idle)
D:Invoke("epilog","terminal")                           -- Zustand ready
D:Invoke("epilog","terminal","armed")                   -- idle|ready|armed|fired|done|off
D:Invoke("epilog","terminal","fired")                   -- armed -> (0,8 s) -> fired: Auslöse-Animation
D:Invoke("epilog","scan")                               -- terminal, terminalZustand, terminalTeile
D:Invoke("parts")                                       -- Gesamtinsel (≤ 250) messen
```
Echtes Halten: zum Terminal laufen (< 8 Studs), E / Tippen halten 1,2 s.

## Teile / Budget
Terminal **21** (Grenze 22), 1 Emitter (Grenze 2), 1 SpotLight, keine Texturen. Gesamtinsel (≤ 250) **nicht gemessen**: Gipfel + Insel (14) + Brücke (18) + Terminal (21) kommen zum Turm dazu — in Studio mit `D:Invoke("parts")` messen.

## Annahmen (bitte bestätigen)
1. **Annäherung wird serverseitig geprüft** (zweimal pro Sekunde, kein Frame-Loop), nicht im Client, weil der Zustand ein Server-Attribut ist.
2. **`armed` = Halten läuft** (Klappe öffnet sich während des Ladens), `fired` = Halten abgeschlossen.
3. Die Klappe **schwebt** 0,7 Studs über dem Gehäuse (kein Rahmen, Budget); der Scharnier-Drehpunkt ist ein Attachment am Korpus.
4. **Kein Sound** (laut Vorgabe Platzhalter, Prompt 7); der „Klack" ist nur die harte Quad-Bewegung.
5. Das Terminal entsteht, sobald die Brücke fertig ist (bzw. sofort bei Restore). Der eigentliche Terminal-Reveal gehört zu Prompt 5/6.
6. Palette: Beton/Metall-Grau, Signalrot, Warngelb nur an Streifen/Lampe, Honig-Gold an Ring und Leiste, Lampengrün nur im Zustand fired/done.

## Offen
- **Blender-Assets erstellt** (`Epilog_Terminal.fbx` inkl. Knopf als Teil, `Epilog_Terminal_Albedo.png` 512²); Studio-Import und Upload **offen** → **Asset-IDs: keine**. Vorlage `ASSETS.terminalTemplate`, Bild `ASSETS.terminalAlbedo` (leer bis Upload). Primitive bleiben Fallback. Details: `docs/HBB_EPILOG_ASSETS_2026-10-20.md`.
- Keine Studio-Vorschau, keine Screenshots je Zustand, kein Handy-Test (Daumen-Auslösen), Optik und Lampenfarben ungesehen.
- `make_update_rbxmx.py` nicht ausgeführt, kein Commit.

## Prüfungen (lokal)
`luau-compile --null` aller geänderten Dateien ✔ · `check_locals` max 192 (MapConfig) ✔ · `guide_steps`, `boss_tiers` ✔ · `epilog_state` 55, `epilog_summit` 94, `epilog_island` 264, `epilog_terminal` 44 ✔ · `combat_rating`, `gold_rules`, `map_layout`, `live_board`, `event_schedule`, `egg_press`, `honey_pond`, `shop`, `endless`, `ui_texts` ✔ · `check_feedback/consistency/loc/ui/decor` ✔.
Bekannte Altfehler (nicht von diesem Prompt): `unlock_rules` (1 FAIL), `migration_hbb` C4, `check_members` (2× CombConfig in RecyclerBuilder).
