# Audio-Rework (16.10.2026)

Musik, weiche Effekte, Lautstärke-Regler. Alles selbst synthetisiert (Node, keine KI-Dienste, keine fremden Samples).

## 1. Audit (Stand vor dem Umbau)
Im Place gab es **keine** Sound-Instanzen; alles lief per Skript mit Studio-Platzhaltern (`rbxasset://sounds/…`), keine Musik, kein Ton-Fenster.

| Klang | Auslöser | Häufigkeit | Lautstärke | Problem |
|---|---|---|---|---|
| `click`/`select`/`success`/`upgrade` (electronicpingshort) | `Kit.playSound` | jeder Knopf, jede Auswahl, jedes Upgrade | 0,15–0,45 | hoher Piepton, immer gleich, kein Cooldown |
| `lookUp`/`unlock` (bass.wav) | große Upgrades, Tower-Freischaltung | selten | 0,45–0,5 | dumpfer harter Schlag, lauteste UI-Stelle |
| Moment-Ping | `Moment.show` (Level-Up, Rebirth, Rarity …) | pro Moment | 0,4 | derselbe Ping wie jeder Klick |
| Kampf-Treffer (action_jump_land.mp3) | `PitArenaService` je Kampf-Beat, 3D für alle | jeder Beat jedes Kampfs | 0,25 (Skill ×1,6) | dumpfer Thump im Takt, stapelt über mehrere Kämpfe |
| Skill-Bibliothek (15 Roblox-Altklänge) | `SkillFXController` BLOCKS.sound | bis zu 3 je Skill, ~33 Skills | 0,35 / 0,12 | Glas, Raketenschuss, Blitz hart und schrill, Pitch 0,45–1,6 verzerrt, kein Limit |
| Ei-Schlüpfen (R6, `VFX/EggHatch`) | 7 Slots in `SoundConfig` | – | – | alle stumm (leere IDs) |

Dazu in Studio (nicht im Repo): `Soundscape` (6 Ambience-Schleifen, Volume ≈ 0,07, Gruppe `WorldAmbience`) – bleibt unverändert; Roblox-Standard-Schritte (Volume 0,65) sind nicht angefasst.

## 2. Was jetzt da ist
| Datei | Zweck |
|---|---|
| `src/shared/Audio.luau` (= `ReplicatedStorage.Audio`) | **ein** Modul: `MUSIC`, `SFX` (Id, Lautstärke, Cooldown, Pitch-Streuung, `special`/`duck`), `TUNING`, Standardwerte, `Audio.play()` für gemeinsamen Code |
| `src/client/Controllers/AudioController.luau` | Abspielen, Überblendung, Absenken, Cooldown/Stimmen-Limit, Regler anwenden und speichern |
| `src/client/UI/AudioPanel.luau` | Ton-Fenster (Musik, Effekte, Stumm) + 🔊-Knopf als 4. Knopf der Knopf-Zeile |
| `SettingsService.setAudio`, `Remotes.RequestSetAudio`, `data.audio` | Speichern pro Spieler (`{music, sfx, muted}`; Server klemmt die Werte, kein Migrationsschritt nötig) |
| `tools/audio/synth.js` | erzeugt 3 Musik-Schleifen und 33 Effekte (`node tools/audio/synth.js` → `tools/audio/out/`) |
| `tools/audio/analyze.js` | prüft Spitze, Lautheit, hohe Frequenzen, Schleifen-Naht |
| `tools/audio/install_studio_preview.ps1` | kopiert die WAVs in den Studio-Content für die lokale Vorschau |

### Musik (≈ −18 dB RMS, alle gleich laut, Tiefpass ~5 kHz, kein Hochton)
| Spur | Zone | BPM | Dauer | Aufbau |
|---|---|---|---|---|
| `main` | Farm/Lobby (nichts offen) | 92 | 104 s | Pad+Bass → +E-Piano-Arpeggio+Shaker → +Kalimba-Melodie → voll → dünner, dann zurück zum Anfang |
| `menu` | irgendein Fenster offen | 86 | 112 s | ruhig, keine Percussion, selten Melodie |
| `fight` | Tower-Fenster offen oder Pet im Tower (`ToPit`/`InPit`) | 100 | 96 s | Puls-Bass, weicher Kick, Marimba-Arpeggios |

Nahtlos: jede Schleife wird zweimal hintereinander gerendert (Hall und Ausklang laufen über die Naht) und die zweite Hälfte genommen.
Musik beginnt 2 s nach dem Laden und blendet 8 s lang ein. Zonenwechsel: erst nach 0,6 s Ruhe, dann 2 s Überblendung. Große Momente senken die Musik auf 35 % ab (0,25 s runter, Haltezeit je Klang, 1,2 s zurück).

### Effekte
- **Routine** (Lautstärke 0,22–0,32): `click`, `select`, `coin`, `hit`, `hitHeavy`, `eggCollect`, `upgrade`, `hatchCrack`, `hatchCommon`. Cooldown 0,08–0,3 s, Pitch ±4–10 %, global höchstens 4 in 0,35 s.
- **Besonders** (Lautstärke 0,6–0,85, immer gleich, senkt die Musik): `upgradeBig`, `unlock`, `moment`, `hatchRare`, `levelUp`, `rebirth`.
- **Fähigkeiten** `fx_*` (15 weiche Ersatzklänge für die Skill-Bibliothek): eigener Cooldown, höchstens 3 gleichzeitig in der Welt, Pitch auf 0,85–1,2 begrenzt.
- Kampf-Treffer: `hit` / `hitHeavy`, serverseitig höchstens ein Klang je 0,2 s und Ordner. Der Sound heißt `WorldSfx`; der Client hängt ihn in die Effekt-Gruppe, damit Regler und Stumm gelten.
- Moment-Zuordnung (`Audio.MOMENT_SFX`): `rebirth`→`rebirth`; `rarity`/`mutation`/`chest`→`hatchRare`; `milestone`/`record`→`levelUp`; `unlock`/`tower_unlocked`→`unlock`; Rest→`moment`.
- Münzen-Klang `coin`: ein Klang pro fliegendem HUD-Icon (`Feedback.launchFlyer`), durch Cooldown/Limit höchstens ~8 pro Sekunde.

## 3. Geänderte Dateien im Repo
`Kit.luau` (playSound → AudioController), `Moment.luau`, `Feedback.luau`, `HatchAnimation.luau`, `SkillFXController.luau`, `SkillFXConfig.luau` (`SOUND_LIBRARY` zeigt auf `fx_*`; `OWNER_VOLUME`/`SPECTATOR_VOLUME` sind jetzt Faktoren), `FigureFX.luau`, `PitArenaService.luau`, `MapConfig.luau` (`FIGHT_BUMP_SOUND` leer), `Main.client.luau`, `Remotes`, `Types`, `NetworkConfig`, `PlayerService`, `SettingsService`, Loc-Strings (`ui.audio.*`, 4 Sprachen). `SoundConfig.luau` bleibt liegen, wird nicht mehr gelesen.

### Nur in Studio gemacht (nicht im Repo, weil `VFX/EggHatch` dort fehlt)
`ReplicatedStorage.VFX.EggHatch`: `playSound` ruft jetzt `Audio.play` (Zuordnung `hatchCrack`→`hatchCrack`, `hatchBurst`→`hatchCommon`, `hatchBurstHigh`→`hatchRare`; Appear/Wobble/Reveal bleiben still) und `local Audio = require(ReplicatedStorage.Audio)`. Bitte beim nächsten Repo-Abgleich mit übernehmen.

## 4. Testen
1. Studio, Play. Musik beginnt nach ca. 2 s leise. (Erst `powershell -File tools/audio/install_studio_preview.ps1`, falls die Studio-Version gewechselt hat: dann spielen die Dateien aus dem Content-Ordner, ohne Upload.)
2. Fenster öffnen (z. B. Ei-Menü): nach 0,6 s blendet die Menü-Musik über. Schließen: zurück. Kampf starten: Kampf-Musik.
3. Befehlsleiste, Client (nur Studio): `_G.HBBAudio.play("levelUp")` zeigt Jingle und Absenkung; `_G.HBBAudio.set({ music = 0.3 })`, `_G.HBBAudio.set({ muted = true })`.
4. 🔊-Knopf (4. Knopf oben links): Musik- und Effekt-Regler, Stumm. Werte werden 0,8 s nach dem Loslassen gespeichert und beim nächsten Join geladen.
5. Spam-Test: schnell klicken – es sind höchstens 4 Klänge in 0,35 s zu hören.
Gemessen in Studio: Überblendung läuft (Musik 0,2→0, Zielspur 0→0,2), Absenken Musikgruppe 0,70→0,25 und zurück, 30 Klicks in 0,3 s → 6 gespielt, Mute setzt beide Gruppen auf 0.

## 5. Lautstärken abstimmen
Alles in `ReplicatedStorage.Audio` (`src/shared/Audio.luau`):
- Musik leiser/lauter: `MUSIC.<name>.volume` (Standard 0,20).
- Routine-Effekte: `SFX.<name>.volume` (0,22–0,32). Besondere Momente: 0,6–0,85. Reihenfolge einhalten: Musik < Routine < Besonders.
- Zu dicht/zu oft: `cooldown` hochsetzen, `TUNING.MAX_ROUTINE`/`ROUTINE_WINDOW` kleiner, `pitch` mehr Streuung.
- Absenken: `TUNING.DUCK_LEVEL` (0,35), `SFX.<name>.duck` (Sekunden).
- Überblendung/Start: `TUNING.CROSSFADE_SECONDS`, `START_FADE_SECONDS`.
- Startwerte der Regler: `Audio.DEFAULTS` (0,7 / 0,8).

## 6. Auf Roblox hochladen und einsetzen
Audio kann ich nicht hochladen (mein Werkzeug lädt nur Bilder). Du lädst die WAVs aus `tools/audio/out/` hoch (Creator Hub → Assets → Audio, oder Studio → Asset Manager → Bulk Import; mit `node tools/audio/synth.js` neu erzeugen, falls der Ordner fehlt). Je Datei die ID in **eine Zeile** eintragen, z. B. `click = { id = "rbxassetid://123456789", … }`. Leere `id` = im Studio Vorschau-Datei, im echten Spiel still.
- Format: Roblox nimmt MP3/OGG (und je nach Konto auch WAV/FLAC). Lehnt der Upload WAV ab: in Audacity als OGG exportieren. Die Musik-WAVs sind 12–14 MB (Grenze 20 MB je Datei).
- Neu erzeugen mit anderer Stimmung: `synth.js` (Akkorde `P`, Spuren `TRACKS`, Seeds) anpassen.

## 7. Credits / Lizenzen
Keine fremden Quellen. Musik und Effekte sind mit `tools/audio/synth.js` aus Sinus- und Rauschsynthese berechnet (Eigenwerk, keine Samples, kein KI-Audiodienst). Kein Nachweis nötig.

## 8. Offen / nicht geprüft
- Ich konnte nicht **hören**; geprüft wurden Pegel, Tiefpass, Schleifen-Naht und das Verhalten im Playtest. Klang, Lautstärkeverhältnis zu `Soundscape` und Geschmack bitte selbst anhören und über Abschnitt 5 nachziehen.
- Speichern (`data.audio`) ist nur im Code geprüft, nicht gegen einen echten DataStore.
- Python war auf dem Laptop nicht installiert: `check_locals.py`, `check_ui.py`, `check_loc.py` und die Luau-Tests sind **nicht** gelaufen. Studio hat alle geänderten Skripte fehlerfrei geladen (Konsole ohne Fehler).
- Die alte `HatchAnimation` hat ebenfalls Klänge bekommen; falls sie durch `VFX/EggHatch` nicht mehr benutzt wird, ist das harmlos.
