# Pulsar-Nova – neue Fähigkeit für den Pulsar-Bärchi (umgesetzt 25.10.2026)

## Was
- Neue Fähigkeit `PulsarNova` („Pulsar-Nova“) für `PulsarBaerchi` (Cosmic). Neue, bessere Fassung des Blender-Prototyps „Pulsstoß“ vom 22.10. (`docs/HBB_PULSAR_PULSSTOSS_PROTOTYP_2026-10-22.md`). `defaultSkill` ist jetzt `PulsarNova` (gilt für neue Pulsare). `PulsarPulse` bleibt für alte Bärchis und Fusionen.
- Motiv „Leuchtturm-Pulsar“ (Wahl des Nutzers): Der Bärchi wird zum Pulsar, einem Leuchtturm aus Licht, der immer schneller tickt, und schlägt als Neutronenstern ein. Aus dem Vorbild übernommen: Ring am Boden, Sternbruch, Kugel, Impact-Frames, Feuerkuppel, Weißblende.
- Farben (Wahl des Nutzers): Cyan (70, 228, 255) aus Visier und Düsen, Feuer-Orange (255, 138, 40), Weiß, pinker Saum wie im Vorbild.
- Kampfwerte (Wahl des Nutzers: Brand/DoT, wie Nebelbrand und Höllensiegel): sofort 1,8× ATK + 60, danach Brand 3 Aktionen je (20 + 0,35× ATK) × (1 + PWR), Ladung 5. Gesamt etwa 2,85× ATK + 120. Ein neuer Brand ersetzt den alten.

## Ablauf der Show
Stufe 4, 5,7 s, Treffer (`impactAt`) 2,9 s. Echo 0,65 s, Treffer 0,26 s.

| Zeit (s) | Takt |
|---|---|
| 0–0,35 | Welt kühl-dunkel (nur Besitzer), Sterne. Bodenblitz, ein Lichtpunkt zeichnet den Ring mit 12 Tick-Strichen um den Pulsar. |
| 0,38–1,1 | Er duckt sich, das Jetpack zündet, Aufstieg mit Drehung. Der Ring hebt mit ab und wird sein Orbit-Ring. |
| 1,05–2,05 | Leuchtturm: Lichtkegel aus Visier und Jetpack. Er dreht immer schneller, der Visier-Kegel fegt bei 1,2 / 1,48 / 1,7 / 1,86 / 2,01 durch die Kamera jedes Spielers (Blitz, Ticken, jedes Mal lauter). Kamerafahrt von unten (1,05–3,55, nur Besitzer). |
| 2,05–2,45 | Kollaps zum weißglühenden Neutronenstern, Anime-Sternbruch, Funken, zwei Pulse, kurze Stille. |
| 2,45–2,9 | Schlag als Komet in den Gegner (Schweif Cyan → Orange, Nachbilder). |
| 2,9 | Einschlag: kleine gleißende Kuppel, Impact-Frames (nur Besitzer: rosa Grund, tintenschwarze Silhouetten, Speedlines, dann Weiß), Feuerkuppel (Radius 8) mit laufenden Flammenbändern, Löchern, pinkem Saum, Flammenkranz und Trümmern. Bodenwellen bis zum Zaun. |
| 3,45 / 3,95 | Die Kuppel pulst (Besitzer: rosa Schleier). |
| 4,35 | Weißblende: Die Kuppel flammt auf und vergeht. |
| 4,42–5,65 | Er rollt sich aus dem Krater auf, Rückwärts-Salto nach Hause, der Ring blitzt an seinen Füßen. Flammen züngeln am Gegner (Brand). |
| Echo | Ein kleiner Neutronenstern schießt in den Gegner, eine kleine Feuerkuppel ploppt auf, Bodenring. |

## Umsetzung (in Studio)
- `SkillFXController`:
  - Neue Bausteine:
    - `pulsar`: Bärchi-Klon, Ring, Jetpack, Leuchtturm, Neutronenstern, Flug, Rückkehr.
    - `firedome`: Feuerkuppel und Brand.
    - `novaframe`: Impact-Frames über ein ViewportFrame.
    - `novabolt`: Echo.
  - Neue Helfer:
    - `novaRing`: Kreis aus 4 Bezier-Beams, mit Zeichnen, Lücken und Farbverlauf.
    - `novaVeil`: Bildschirm-Schleier, nur für den Besitzer.
    - `novaFlames`: Flammenzungen aus Beams.
    - `pulsarJet`: Jetpack-Flammen und Visier aus den Modellteilen `acc_flame`, `acc_nozzle`, `acc_visor` und `acc_jetpack`.
    - `novaInk`: Silhouetten für das Impact-Frame.
  - Neuer Kamera-Stil `pulsar`.
  - Neue ctx-Felder: `pulsarHover`, `pulsarCam`, `novaT0`, `novaCenter`, `novaRadius`.
  - Test-Parameter: `freezeAt`, `trailLife`.
- `SkillFXConfig`: Eintrag `PulsarNova` mit Kopfkommentar, Doku der Bausteine und `TEXTURES.PulsarNova`. Die Bilder sind wiederverwendet, es gibt keine neuen Uploads.
- `SkillConfig` (`PulsarNova`), `BaerchiConfig` (`defaultSkill`), Texte de/en/es/fr (`skill.PulsarNova.name/desc/drawback`).
- Backup in `ServerStorage.Backup_vor_PulsarNova_2026-10-25`: Controller, 3 Configs, 4 Sprachen.
- Eingefügt mit `ScriptEditorService:UpdateSourceAsync`, mit Ankerzählung auf dem jeweils neuesten Quelltext. Grund: Gleichzeitig arbeitete eine zweite Sitzung (Höllensiegel) in denselben Skripten. Deren Code ist unberührt.
- Lokale Namen auf Modul-Ebene im Controller: etwa 139 von 200 erlaubten, davon 17 für Pulsar-Nova.

## Getestet
- **Kompilieren:**
  - `loadstring` aller 8 Skripte in Studio, `luau-compile --null` lokal.
  - Config über einen Klon geprüft: Dauer 5,7 / 0,65 s, Treffer 2,9 / 0,26 s, alle Klänge, Slots und Bausteine vorhanden.
- **Eingefrorene Bühnen**, mit Screenshots aus der Achse der Spielkamera, von der Seite, aus der Nähe und von weit weg:
  - Ring zeichnen, Aufstieg, Leuchtturm-Tick, Flug, Einschlag, Kuppel, Puls, Weißblende, Salto mit Brand, Echo-Flug.
  - Impact-Frame 30 s lang gehalten.
- **Befunde und Korrekturen (Runde 1):**
  - Die Flammenbänder waren unter der Highlight-Füllung der Kuppel fast unsichtbar. Grund: Ein Highlight malt seine Füllung auch über durchsichtige Teile davor (Beams schreiben keine Tiefe). Jetzt ist die Füllung nur noch schwach (0,82). Das Aufleuchten über die Füllung kommt nur noch bei den Pulsen und der Weißblende.
  - 7 breite, waagerechte Bänder wirkten wie ein Wasserball, und ein kleiner Ring oben stand von der Seite als roter Balken ab. Jetzt: 4 schmalere, leicht gekippte Bänder mit Verlauf zum Rot, ohne hohe Breiten.
  - Der Leuchtturm-Blitz war vor hellem Himmel zu schwach (das Schein-Bild allein verschwindet). Jetzt gibt es zusätzlich einen Neon-Kern (bis 3,7 Studs, Transparenz ≥ 0,3) und ein größeres Funkeln bei jedem Tick.
  - Die Brandflammen waren nur 1,5 Studs hoch und gingen hinter dem Gegner unter. Jetzt reichen sie bis über den Kopf.
  - Der Echo-Stern ist größer (0,95) und hat einen längeren Schweif.
- **Messlauf** (echte Show auf Dummys):
  - Stern sichtbar ab 2,14 s.
  - Letzte Flugposition 2,88 s, Einschlag (kleine Kuppel) 2,91 s, bei `impactAt` 2,9.
  - Impact-Frame 2,94–3,24 s, große Kuppel ab 2,98 s.
  - Kamera Scriptable 1,05–3,57 s, danach Custom.
  - Kuppel weg bei 4,75 s, Klon weg und Original wieder sichtbar bei 5,69 s.
  - Danach 0 Reste.
- **Echter PIT-Lauf** (Fähigkeit vorübergehend auf dem ausgerüsteten Rätsel-Bärchi):
  - 1 volle Show und 8 Echos, 0 Warnungen auf Client und Server.
  - Originale sichtbar, Kamera Custom, keine Klone.
  - Danach zurückgetauscht auf `RiddleAvalanche` und per `GetPlayerData` geprüft.
- **Nicht geprüft:**
  - Sicht der Zuschauer in einem echten Mehrspieler-Spiel. Gebaut ist sie so, dass Zuschauer nur die Welt-Effekte sehen.
  - Niedrige Grafik (2 Bänder, 3 Löcher) nicht fotografiert.

## Offen
- Datei → Auf Roblox speichern.
- Sichtprüfung im eigenen Kampf: Auf Wunsch liegt seit 25.10. ein Pulsar Lv. 50 im Inventar (uid b_1792950844_1_9744, Fähigkeit PulsarNova, per `RBLDebug add`, geprüft mit `RBLDebug stats`; nicht ausgerüstet).
- Repo:
  - Die Fähigkeiten-Skripte stehen im Repo weiter auf dem Stand vom 20./21.10. (offener Punkt „Gesamtabgleich Studio → Repo“).
  - Der Pulsar-Nova-Code liegt als Paket mit Einfüge-Anleitung in `updates/PulsarNova_2026-10-25/`.
- Doppelte Helfer, parallel zur Höllensiegel-Sitzung entstanden:
  - `novaRing` und `hellRing` machen dasselbe (Kreis aus 4 Bezier-Beams, Trick aus `worldglobe`). Wenn beide Sitzungen fertig sind, zu einem Helfer zusammenlegen.
  - `novaframe` (ViewportFrame, invertiertes Bild) und `impactframe` (Farbfilter) sind zwei Techniken für Impact-Frames. Beide bleiben vorerst.
