# Epilog-Sound-Briefing (2026-10-20)

Erzeugt mit `tools/audio/synth_epilog.py` (reine Synthese, keine Fremdquellen, keine Lizenzpflicht). Ausgabe: `assets/epilog/sound/*.ogg` (OGG, 44,1 kHz, SFX mono, Musik stereo, ca. -16 LUFS, Spitze <= -1,5 dB), WAVs unter `tools/audio/out/`.
Vorhoeren im Studio: `powershell -File tools/audio/install_studio_preview.ps1` (kopiert die WAVs als `sfx_epilog_<name>.wav` / `music_epilog.wav`), Studio neu starten.
Upload: nur den finalen Satz (12 Dateien) ueber Creator Hub -> Audio, danach IDs in `Config/SoundConfig` (`epilog_*`) eintragen. Bis dahin: Studio spielt die Vorschau, im Spiel ist es stumm.

| Cue | Datei | Laenge | Charakter | Zeitpunkt |
|---|---|---|---|---|
| epilog_hit | epilog_hit.ogg | 1,1 s | dumpfer Treffer + Glasbruch | Sequenz 0,0 s |
| epilog_flash | epilog_flash.ogg | 2,7 s | Aufwaerts-Sweep | 2,0 s |
| epilog_rise | epilog_rise.ogg | 4,9 s | Orchesterflaeche steigt | 5,0 s |
| epilog_reveal | epilog_reveal.ogg | 5,2 s | 0,4 s Stille, dann Fanfare | 8,8 s |
| epilog_run | epilog_run.ogg | 0,22 s | ein Schritt auf Holz, Takt 0,28 s, Tonhoehe +-5 % | ab 12 s waehrend des Laufs |
| epilog_terminal_idle | epilog_terminal_idle.ogg | 4,0 s | leises Summen, Schleife, 3D am Terminal | solange das Terminal wartet |
| epilog_ready | epilog_ready.ogg | 0,5 s | zwei Pieptoene | Terminal wird "bereit" |
| epilog_press | epilog_press.ogg | 0,3 s | hartes, leicht ironisches Klacken | Knopfdruck (Finale 0 s) |
| epilog_countdown | epilog_countdown.ogg | 0,45 s | Zaehlton je 3/2/1 | 1,2 / 2,5 / 3,8 s |
| epilog_launch | epilog_launch.ogg | 4,0 s | Rumpeln -> Zischen | 5,0 s |
| epilog_unlock | epilog_unlock.ogg | 3,0 s | Sieges-Jingle | 7,5 s |
| epilog_music | epilog_music.ogg | 76,8 s | 100 BPM: Intro (0-19 s), Aufbau (19-38), Hoehepunkt (38-58), ruhiges Finale (58-77), Schleife nahtlos | ab Sequenzstart; Spielmusik -10 dB, dann aus; nach dem Finale 2 s zurueck |
