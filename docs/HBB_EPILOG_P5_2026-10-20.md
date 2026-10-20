# Final-Epilog · Prompt 5 von 7 – Kamerafahrt & Bildschirmrand-Effekte (20.10.2026)

**Status:** Code fertig, kompiliert, alle Luau-/Python-Prüfungen grün. **In Studio noch nicht gespielt** (kein Playtest möglich) – bitte zuerst `epilog speed 2` und `epilog start` testen.

## Was gebaut wurde
- **Zeitplan (Server, `EpilogService`)**: Teleport bei 2,25 s (Flash-Höhepunkt), Insel+Brücke ab 5 s, Begleiter-Lauf ab 12 s, Wachhund bei 24,5 s, Ende 34 s. `EpilogStart` trägt jetzt `{token, mode, state, speed, startAt, skipFrom, route}`.
- **Kamera (rein rechnerisch, testbar)**: `Modules/EpilogCameraPath` (Phasen 1–5, Zeitlupe/Hit-Freeze/Aufholen, Dolly-Zoom mit konstanter Objektgröße, Rückblende in die Standardansicht), `Modules/EpilogRoute` (Weg, Projektion, Lauf-Tempoprofil).
- **Client**: `Controllers/EpilogController` (eine `Kit.animate`-Schleife; Kamera, Avatar-Lauf per `Humanoid:MoveTo`, Bloom/SunRays/ColorCorrection `Epilog*`, HUD aus/an, Steuerung nur paarweise aus/an, Moment „TOWER GESCHAFFT!“, Cue-Platzhalter, Skip, `EpilogSeen` bei 34 s, Wiederaufnahme-Flash, Aufräumen bei Tod/Respawn/Verlassen/Fehler) und `UI/EpilogOverlay` (Flash, Vignette aus UI-Verläufen, Funken, Konfetti-Schleier/-Burst, Speed-Lines, Wolken, Linsenreflex, Letterbox, Skip-Ring aus 12 Punkten). 56 UI-Teilchen (≤ 60), „reduced“ halbiert sie, kein Dolly-Zoom.
- **Skip**: ab Sekunde 12, Halten 1 s (Ring unten rechts / E / Gamepad X / Tippen). Server prüft Token, laufende Fahrt und Mindestzeit, setzt dann Insel/Brücke/Terminal/Avatar sofort.
- **Debug**: `epilog speed N` (0,5–5), `epilog audit` (Client+Server-Zähler: Kamera, FOV, Lichteffekte, Steuerung, Verbindungen, Animationen, WalkSpeed, HUD).
- **Texte**: `ui.moment.tower_cleared` in de/en/fr/es. **Sounds**: `epilog_hit/flash/rise/run/reveal` als leere Platzhalter in `SoundConfig`.
- **Bilder** (`assets/epilog/`): `Epilog_Funke.png` 128², `Epilog_Konfetti.png` 256×64, `Epilog_SpeedLine.png` 512×64, `Epilog_LensFlare.png` 512². Vorschau: `docs/screens/EPILOG_P5_ASSETS.png`. Vignette ist bewusst **kein Bild** (UI-Verläufe).

## Prüfungen
luau-compile aller geänderten Dateien ok · check_locals (nur bekannte MapConfig 192) · check_members (nur bekannte CombConfig) · check_consistency · check_loc · check_ui · check_decor · check_feedback · Tests epilog_state/summit/island/terminal/camera, combat_rating, gold_rules, map_layout, live_board, event_schedule, egg_press, honey_pond, shop, endless, ui_texts, guide_steps, boss_tiers · unlock_rules/migration_hbb: bekannte, nicht von mir stammende Befunde.

## Annahmen
1. Keyframes als Segmente + Follow-Keyframes statt wörtlich `{t, CFrame, fov, ease}`.
2. Kamera-Anker kommen aus der `EpilogStart`-Route (Gipfel/Insel/Terminal), nicht aus den `Cam_*`-Attachments.
3. Keine ParticleEmitter (erlaubt ≤ 2).
4. Hauptoberfläche `RBL` wird während der Fahrt ausgeblendet.
5. Wiederaufnahme: `EpilogSeen`, sobald der Avatar nahe am Terminal steht.
6. Planken leuchten nur clientseitig golden auf (Namen `Epilog_Plank*`).

## Offen
- **Asset-IDs fehlen**: PNGs und FBX müssen von Hand hochgeladen werden (Studio-Upload nimmt von hier nur http-URLs); IDs dann in `Config/EpilogConfig.ASSETS` (`sparkTex`, `confettiTex`, `speedLineTex`, `lensFlareTex`, Templates). Bis dahin laufen Frame-Fallbacks.
- `make_update_rbxmx.py` nicht ausgeführt; nichts committet.
- Nichts in Studio getestet (Kamera-Gefühl, Lauftempo, Vertex-Farben der Meshes ungeprüft).
- Audio: Platzhalter, füllt Prompt 7.
