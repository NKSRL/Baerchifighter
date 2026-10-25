# Pulsar-Show „Pulsstoß“: Blender-Prototyp (22.10.2026)

**Wunsch:** die Fähigkeit aus dem Vorbild-Video vom 22.10. (Anime-Explosion: Ring → Funkenbruch → Kugel → riesige Feuerkuppel, mit Impact-Frames) als VFX für einen Endgame-Bärchi. Der Kreis vom Anfang soll sich **um den Bärchi herum** bilden. Gewählt (Nicklas): **Pulsar** (`PulsarBaerchi`, Cosmic, Kosmos-Pfad, Skill `PulsarPulse` „Pulsstoß“, Aufbau). Umfang dieses Schritts: nur Blender-Prototyp mit Vorschau. Import und Verdrahtung kommen nach Abnahme.

## Was im Vorbild passiert (30-fps-Analyse, Video 10,1 s, läuft als Schleife)
| Zeit | Vorbild | Feinheiten |
|---|---|---|
| 0,0–0,6 | Rest der vorigen Schleife | seitliche Explosion, violette Funken |
| 0,8–1,7 | Ring | flache helle Scheibe, kippt zum dünnen orangen Ring, schwebt, schrumpft leicht |
| 1,7–2,5 | Sternbruch | kleiner Anime-Stern mit 10–14 Zacken, flackert in Bildschritten, längliche Funken-„Pillen“ fliegen in Bögen raus, bei 2,2 s ein großer Zackenstern-Blitz |
| 2,5–3,1 | Kugel | kleine Kugel (weißer Kern, oranger Schein) driftet nach rechts unten |
| 3,1–3,2 | Impact-Frames | 1 Bild gelbweiße Halbkuppel, 1 Bild invertiert (rosa-weißer Grund, schwarze Speedlines/Silhouetten), 2–3 Bilder ganz weiß |
| 3,2–5,2 | Feuerkuppel | riesige Halbkugel, weißglühend, waagerechte orange Flammenstreifen, dunkelrote Löcher, pinker Saum, am Fuß kochende Flammen und dunkle Brocken; Pulse mit pinkem Hintergrund |
| 5,2–6,6 | Weißblende | Bild ganz weiß, kippt ins Rosa |
| 6,6–10 | Nachglühen | kleiner Ring bleibt (Start der nächsten Schleife), Hintergrund wird dunkel |

## Umsetzung für den Kampf (Prototyp, 5,8 s, Einschlag 2,50 s)
Das Vorbild ist ortsfest. Im PIT muss die Show vom Pulsar zum Gegner. Daher:

| Zeit | Phase | Was passiert |
|---|---|---|
| 0,00–0,20 | Bodenblitz | flache gelbe Scheibe ploppt um den Pulsar auf und verschwindet |
| 0,04–0,55 | **Ring um den Bärchi** | oranger Ring (R 3,6) + dünner weißer Innenring + Schein am Boden um den Pulsar, Überschwingen beim Aufploppen, drehen gegeneinander; 16 Funken-Pillen strömen von außen hinein; violetter Staub steigt auf |
| 0,55–0,85 | Ring steigt | Ring fährt am Körper hoch, kippt zur Kamera, schrumpft zum Halo über dem Kopf |
| 0,85–1,12 | Halo tickt | zwei Pulse (größer/heller), dann Kollaps zum Punkt mit weißem Blitz |
| 1,12–1,75 | Sternbruch | Vierzack-Kern + 2 Zackensätze (13 Spitzen), abwechselnd in 2-Bild-Schritten (kocht wie im Anime), 22 Funken-Pillen fliegen in Schwerkraft-Bögen, in Flugrichtung gedreht; 1,60–1,66 s großer Zackenstern-Blitz + Pink-Blitz + Wackeln |
| 1,72–2,25 | Kugel | Halo-Scheibe + weißer Kern + drehender Glanzstern; drei Pulse (1,25 / 1,4 / 1,6), jeder schickt einen dünnen Ring raus („jeder Schlag lauter“) |
| 2,25–2,50 | Flug | Bézier-Bogen zum Gegner, Beschleunigung, Schweif (zwei Lagen) + drei Nachbilder |
| 2,50 (Bild 76) | Impact-Frame 1 | gelbweiße Halbkuppel (R 3,6) mit orangem Rand am Gegner |
| 2,53 (Bild 77) | Impact-Frame 2 | invertiert: rosa-weißer Grund, Speedlines, Kuppel und Figuren schwarz (Compositor `PS_Comp`) |
| 2,57–2,70 | Weiß | 2 Bilder ganz weiß, dann schnell runter |
| 2,53–4,40 | **Feuerkuppel** | Halbkugel R 7,8 (deckend), Textur läuft um die Kuppel und nach oben, weißglühende Mitte, pinker Fresnel-Rand, rote Aura, Flammensaum am Fuß (flackert in 2-Bild-Schritten), Bodenschockwelle, Glut, 12 dunkle Brocken, 24 aufsteigende Glimmer; Pulse bei 3,3 und 3,9 s (Kuppel heller, Bild kurz pink, Wackeln); wächst langsam auf 122 % |
| 4,30–5,15 | Weißblende | Kuppel flammt weiß auf, Pink-Blitz, Bild 0,36 s ganz weiß, kippt ins Rosa |
| 4,5–5,8 | Nachglühen | kleiner Ring schwebt über dem Krater (dreht, pulst, steigt, schrumpft), 7 Rauchballen, 14 Asche-Funken rieseln, Glut verglimmt; Gegner trottet zurück |

Kamera: kein Flug, nur Wackeln (Bruch, Blitzstern, Einschlag stark, beide Pulse, Weißblende). Der Pulsar duckt sich beim Aufladen, stößt sich beim Bruch hoch und landet beim Flug der Kugel (Stauchung relativ zur FBX-Skalierung).

## Dateien (Repo)
- `assets/vfx/pulsar_pulsstoss/Pulsar_Pulsstoss.blend`: Prototyp, Sammlung `PS_VFX` (149 Objekte), Kamera `PS_Cam`, Compositor `PS_Comp`, Pulsar (`Export/Pet_Pulsar.fbx`) und Braunbär als Platzhalter (Abstand 18 Studs = `FIGHT_SPACING` 9).
- `assets/vfx/pulsar_pulsstoss/tex/*.png`: 11 Texturen (512 px): Ring, Scheibe, Funke, Stern, Kuppel, Saum, Speedlines, Rauch, Glut, Schweif, Blitzstern. Weiß, wo Roblox einfärben kann; farbig, wo zwei Töne zum Motiv gehören (Kuppel, Saum, Funke, Glut, Blitzstern).
- `assets/vfx/pulsar_pulsstoss/preview/`: `Pulsar_Pulsstoss_v2.mp4` (aktuelle Vorschau), `Pulsar_Pulsstoss_Vergleich_v2.mp4` (oben Vorbild, unten Prototyp), `Vorbild_2026-10-22.mp4`, Einzelbilder in `seq_v2/`, Kontrollbögen `_sheet_*.png`, Prüfbilder in `chk/`.
- `tools/vfx/pulsar_pulsstoss_tex.py` (zeichnet die Texturen) und `tools/vfx/pulsar_pulsstoss_scene.py` (baut Szene und Animation reproduzierbar neu). Alle Zeiten und Farben stehen dort je Phase.
- Hinweis Blender: Farben nur in „Rendered“/„Material Preview“. Blitze hängen an der Kamera (nur in Kamera-Ansicht, Num 0). Impact-Frame nur mit Compositor (im Viewport auf „Always“ gestellt).

## Technische Erkenntnisse (für die nächsten Prototypen)
- Blender 5.2: `Action.fcurves` gibt es nicht mehr, Keyframes liegen in `action.layers[].strips[].channelbags[].fcurves` (Helfer `fcurves()` im Skript).
- EEVEE „Blended“ sortiert nur nach Objektmitte: die Bodenglut wurde über die Kuppel gemalt. Deckende Effekte (Kuppel, Vorkuppel, Brocken) laufen jetzt als „Dithered“ (`opaque=True`), damit sie Tiefe schreiben. In Roblox entspricht das einem undurchsichtigen MeshPart.
- LayerWeight „Facing“ ist 0 in der Mitte und 1 am Rand (zuerst falsch herum benutzt: Rand-Glühen lag auf der Mitte).
- Emission über ~1 clippt mit Standard-Farbmanagement orange Streifen zu Weiß; die Kuppel läuft mit 0,95 und „hot“ (Mitte ×1,7, Rand ×0,65).
- `device_commit_files` hat das Szenen-Skript dreimal mit altem Inhalt geschrieben; nach jedem Commit MD5 vergleichen.

## Geplante Umsetzung in Roblox (nach Abnahme)
Mechanik bleibt (`SkillConfig` unverändert), nur die Show `PulsarPulse` in `SkillFXConfig` wird ersetzt. Richtwert: Stufe 4 (Cosmic, `maxDuration` 6 s), `duration` 5,8 s, `impactAt` 2,50 s, wie beim Teufel ohne `cinematic`.
- Bodenblitz, Ring-Schein, Schockwelle, Glut: Baustein `ring` mit `tex` / `ground`.
- Ring + Innenring (steigen, kippen, schrumpfen), Zacken, Kuppel (deckend, Material Neon oder Textur), Kuppelrand (ForceField für den Fresnel-Saum), Flammensaum (Zylindermantel mit Beam-Textur), Brocken: MeshParts aus FBX (`ReplicatedStorage.Assets.SkillFX.Pulsar`).
- Kugel, Kern, Glanzstern, Funken-Pillen, Blitzstern, Glimmer, Rauch, Asche: BillboardGui/ImageLabel bzw. je ein ParticleEmitter (Regel: höchstens ein Emitter pro Effekt). Funken-Pillen mit `Orientation = VelocityParallel`.
- Schweif: Trail oder Beam zwischen Kugel und Nachläufer-Attachment; Nachbilder drei Billboards mit Verzögerung.
- Impact-Frames (nur Besitzer): Bild 1 Vorkuppel-MeshPart; Bild 2 ColorCorrection (Saturation −1, Contrast 1, TintColor rosa) + Highlight schwarz auf beiden Figuren + ScreenGui-Bild der Speedlines; Bilder 3–4 weißer `flash`; über RenderStepped zählen, nicht über Wartezeiten.
- Pink-Pulse und Weißblende: `flash` mit `color`; Wackeln vorhanden.
- Neue Bausteine voraussichtlich wie beim Teufel geplant: `meshfx`, `billboard`, `impactframe`, `path` (Bahn der Kugel als Punkte relativ zu Besitzer/Gegner), dazu `trail`. Keine Lights, alles anchored ohne Collide/Query/Touch/Schatten.
- Echo (ab 2. Einsatz): Kugel fliegt direkt + kleine Kuppel (~0,7 s).
- Texturen müssen als Decals hochgeladen werden (IDs in `TEXTURES.PulsarPulse`), bis dahin Rückfall auf Neon.

## Geprüft
- Jede Phase als Einzelbild gerendert und gegen das Vorbild gelegt (Ring, Bruch, Kugel, Impact-Frames mit Histogramm-Messung der Invertierung, Kuppel in sechs Fassungen, Blende, Rest).
- v1 komplett gerendert (175 Bilder, EEVEE, 960×540) und als Kontrollbogen geprüft; danach Löcher der Kuppel verkleinert, Rückstoß des Gegners ins Bild geholt; v2 komplett neu gerendert.
- Nicht geprüft: nichts in Studio, kein FBX-Export, kein Code geändert.

## Offen
- Abnahme der Vorschau durch Nicklas (Tempo der Kuppel, Länge der Weißblende 0,36 s, Farbe der Kuppel).
- Danach: FBX-Export der Meshes, Decal-Upload, Verdrahtung in `SkillFXConfig`/`SkillFXController`, Playtest.
