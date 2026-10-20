# Final-Epilog: Abnahme (Prompt 7 von 7), 2026-10-20

## Umgesetzt
- **Audio**: `Audio.SFX.epilog_*` + `Audio.MUSIC.epilog` (Ids aus `Config/SoundConfig`), Cues in `EpilogController` (hit 0 s, flash 2 s, rise 5 s, reveal 8,8 s, Schritte im 0,28-s-Takt mit +-5 % Tonhoehe, press/countdown/launch/unlock im Finale), Terminal: Summen (3D-Schleife) + Piepton bei "bereit". Veraltete Cues nach Skip bleiben stumm. Max. 6 Epilog-Stimmen, Regler/Stumm gelten ueber die SoundGroup.
- **Musik**: `AudioController.epilogMusic(on)`: Spielmusik -10 dB (1 s), Epilog-Spur blendet in 4 s ein, Spielmusik laeuft dabei ganz aus (Annahme: zwei Schleifen gleichzeitig klingen schlecht); aus = 2 s zurueck. Bei jedem Abbruch (`cleanup`, `endFinale`) und per Waechter (Avatar > 160 Studs vom Terminal) wird zurueckgefahren.
- **Texte**: neu `ui.moment.endless_open`, `epilog.skip.hint` (Hinweis am Skip-Ring), `epilog.finale.count_1..3` in de/en/fr/es. Alle uebrigen Schluessel aus Prompt 5/6 waren vollstaendig. Wortmarken (Moment-Texte, Badge) <= 18 Zeichen; die vorgegebenen Terminal-Bildschirmtexte sind laenger und laufen mit TextScaled.
- **Gefundene Fehler (behoben)**: (1) Epilog-Cues spielten nie (Namen nicht in `Audio.SFX`, leere SoundConfig-Ids). (2) `startFinale` setzte das Rate-Limit VOR der Pruefung, ein echter Knopfdruck waere immer `rate_limit` gewesen (nur Debug-`force` ging). (3) `EpilogController` suchte das Terminal per Name `Epilog_Terminal`, es heisst `Terminal` (Tag `EpilogTerminal`); Wiederaufnahme-Waechter fand es nie. Regel `EpilogRules.checkPress` ist jetzt rein und getestet.

## Pruefungen
| Pruefung | Ergebnis |
|---|---|
| epilog_state / camera / finale / island / summit / terminal Tests | gruen |
| **epilog_rules.test.lua** (neu: Token, Abstand < 14, Rate-Limit, Doppeldruck, Doppel-Clear, Spoofing) | gruen |
| Migration v17->v18 (Final >= 100 -> pending) | gruen (`epilog_state`, Block 6) |
| ui_texts, tower_unlock, endless, guide_steps, unlock_rules, boss_tiers, combat_rating, gold_rules, map_layout, live_board, event_schedule, egg_press, honey_pond, shop | gruen |
| migration_hbb | **C4 rot, schon vor dem Epilog-Projekt** (Commit f8a9831 identisch: Tower-I-Rekord 17 statt 20), nicht Epilog |
| check_loc, check_locals (MapConfig 192/200), check_decor | gruen |
| check_ui, check_consistency, check_feedback, check_members | rot, **keine Treffer in Epilog-Dateien** (EggPanelSkin, GiftService, EggTreePanel, BaerchiInventory usw., aus dem Studio-Sync) |
| Studio-Playtest: Cue-Zeiten (hit 0,98 / flash 2,88 / rise 5,87 / reveal 9,66 / Lauf ab 13,15 s, Start ca. 1 s vor Log-Null) | +-0,2 s zum Plan |
| Musik: Spielmusik 0,2 -> 0,063 (-10 dB), Epilog 0 -> 0,22, Rueckweg ohne Sprung | ok |
| 10 Durchlaeufe (Zeitraffer 8x, reset/start/launch) + `epilog audit` danach | Musik aus, Faktor 1, 0 Stimmen, 0 Licht-Effekte, Kamera Custom, WalkSpeed 16, Verbindungen 0, `reste=false` |

## Haertung
1. Bruecke nie vor dem Sieg: `epilog scan` leer vor `start` (Server baut erst in der Sequenz). 2. Teleport/Speed-Hack: Abstand-Regel (`checkPress`, < 14 Studs) + Server-Rueckholung aus Prompt 2-6. 3. Remote-Spoofing: Token-Tests in `epilog_rules`. 4-8. Leave/Tod/Doppel-Clear/Wasser/Serverwechsel: Regeln im Test, Laufzeit-Szenarien siehe Playbook (Schritt 4-8, **von dir im Studio zu pruefen**). 9. Welt-2-Flag: einziger Schreiber `EpilogRules.applyLaunch` (+ Migration, die nur ein bereits `launched` abbildet), aufgerufen nur ueber `EpilogService.markLaunched` aus `startFinale` (Quellen: `onLaunchRequested` = Prompt, `handlePress` = Remote mit Token, Debug). Hinweis: die Remote-Quelle kommt zusaetzlich zur Vorgabe "nur onLaunchRequested", beide gehen durch dieselbe Pruefung. 10. `FINAL_EPILOG` aus: Schalter in `isEnabled()`, Endless-Moment-Text nur mit Schalter an (`TowerPanel`).

## Asset-IDs / Teile
Bilder (Prompt 1-6): cloudTex 88194991349907, terminalAlbedo 131095774075742, sparkTex 103024913797898, confettiTex 74729177669682, speedLineTex 88362945149920, lensFlareTex 133099540158493, shockwaveTex 86935325388588, portalTex 90183387502766. **Audio: noch keine IDs** (Upload offen, siehe `HBB_EPILOG_SOUND_BRIEFING.md`). Teile (Scan): Gipfel 24, Insel 10, Bruecke 18 (14 Planken), Terminal 21, Rakete 0 nach dem Finale.

## Offen
- Audio hochladen, IDs in `SoundConfig` eintragen; WAV-Vorschau per `install_studio_preview.ps1` (Windows) installieren und anhoeren.
- Studio: Strg+S. Repo-Aenderungen sind nicht committet.
- Schritte beim Lauf ueber die Bruecke: siehe Rueckmeldung im Chat (Laufgefuehl).
- Vorbestehende rote Pruefer/Tests (oben) separat bereinigen.

## "Weg nach Welt 2" braucht spaeter
Ziel-Place/Teleport nach `worlds.unlocked.World2`; Welt-2-Karte und Spawn; Loesung fuer den Hinweis "Weg folgt bald"; Rueckkehr nach Welt 1; eigene Musik/Zonen; Balance/Fortschritt fuer Welt 2; Plot-Abzeichen "Welt 2" ist schon da.

## Studio-Playbook "In Studio pruefen"
Vorher: Play. Befehle in der Befehlsleiste (Server): `game.ServerScriptService.RBLDebug:Invoke("epilog", "<befehl>")`.
1. `on`, `reset`, `scan` -> keine Bruecke/Insel (leer).
2. `start`: Cues hoeren (Treffer, Flash, Aufstieg, Fanfare, Schritte), Musik duckt und der Epilog-Titel blendet ein.
3. Terminal erreicht: Piepton, Summen davor; Knopf 1,2 s halten, 3-2-1, Start, Jingle; nach dem Finale 2 s Spielmusik zurueck.
4. Mitten in der Sequenz Play beenden und neu starten: pending -> Gipfel, seen -> Insel, launched -> Plot.
5. Am Gipfel/auf der Bruecke sterben: Rueckholung, Musik zurueck.
6. Zweimal schnell Final-100 schaffen (oder `start` doppelt): nur eine Sequenz.
7. Von der Insel ins Wasser fallen: Rueckholung.
8. Serverwechsel/Teleport waehrend der Sequenz: `state` konsistent, Endless offen.
9. `audit` nach jedem Lauf: Musik aus, 0 Stimmen, 0 Effekte, `reste=false`; zehnmal wiederholen (`speed 8` beschleunigt).
10. `FINAL_EPILOG` aus: Turm baut ab wie frueher, kein Epilog, Endless oeffnet.
