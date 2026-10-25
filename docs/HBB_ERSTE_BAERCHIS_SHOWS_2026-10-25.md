# Erste Bärchis: 8 neue Fähigkeiten mit Shows (25.10.2026)

Auftrag: Neue Fähigkeiten für die Bärchis der Raritäten Uncommon, Rare, Epic und
Legendary – ohne Kamerafahrten, aber mit Detailpflege. Entscheidungen des
Nutzers: alle 8 Motive wie vorgeschlagen, Kampfwerte wie die alten Fähigkeiten
(balance-neutral), Stufe 2 für Uncommon/Rare (≤ 3 s), Stufe 3 für Epic/Legendary
(≤ 4 s, Farbfilter erlaubt, keine Kamerafahrt).

## Was gebaut wurde

| Bärchi (Id) | Rarity | Neue Fähigkeit (Id) | Show in Takten | Stufe / Dauer / Treffer |
|---|---|---|---|---|
| Eisbär (`BlueBaerchi`) | Uncommon | **Bauchrutscher** (`PolarSlide`, vorher Eisschlag) | Eisbahn gefriert zum Gegner (0,55 s), Sprung auf den Bauch (0,55), Rutschen mit Schneefahne und Pirouette (0,75–1,45), Rums: Gegner im Eisblock (1,5), Purzeln heim mit Rolle, Schütteln, Eisblock zerspringt (2,35) | 2 / 2,8 s / 1,5 s (Stun 1.5x + 8) |
| Tigerbär (`OrangeBaerchi`) | Uncommon | **Tigersprung** (`TigerPounce`, vorher Feuerbiss) | Anschleichen (Ducken, Wippen), Sprung im Bogen vor den Gegner (0,5–0,95), drei Krallenhiebe (1,0 / 1,14 / 1,28) als glühende Streifen, die zu schwelenden Kratzern werden (Brand), Pose, Rückwärtssalto heim | 2 / 2,6 s / 1,0 s (DoT) |
| Detektiv (`CrystalBaerchi`) | Rare | **Brennglas** (`MagnifierBurn`, vorher Splitterhagel) | Goldene Pfotenspuren erscheinen (0–0,65), der Detektiv hüpft ihnen in drei Sprüngen nach, seine Lupe wächst aus der Pfote zur großen Lupe (1,1), Lichtsäule von oben, Brennkegel sucht auf dem Gegner (Rauch, Glühen), Flammenstoß (2,1), Spuren blitzen, „Aha“-Hopser, Hut ziehen, Hopser heim | 2 / 3,0 s / 2,1 s (2.2x + 14) |
| Zucker-DJ (`SugarBaerchi`) | Rare | **Bass-Drop** (`BassDrop`, vorher Zuckersturm) | Schallplatte ploppt unter dem DJ auf, Equalizer-Balken rund um die Arena (Lücke zur Kamera), drei Beats (0,5/1,0/1,5: Hopser, Bodenring, Kopfhörer leuchten), Build-up mit Stille, Drop (2,0): Bass, Welle, Bodenring bis zum Zaun, Sprung mit Drehung, Streusel am Gegner, Pose | 2 / 3,0 s / 2,0 s (AoE 1.4x + 10) |
| Goldener Grizzly (`GoldenGrizzly`) | Epic | **Münzregen** (`CoinShower`, vorher Gold Rush) | Aufbäumen, Stampfer (0,75: Bodenring, Gold-Riss zum Gegner), Münzen spritzen aus dem Gegner (1,6) und fliegen im Bogen zum Grizzly, Goldhaufen wächst, er wird größer, Medaille/Rubin blitzen, Haufen sinkt | 3 / 3,6 s / 1,6 s (Drain 25 %) |
| Ninja (`VoidBaerchi`) | Epic | **Shuriken-Sturm** (`ShurikenStorm`, vorher Schwarzes Loch) | Rauch-Puff (0,45), drei Schattenklone (dunkel, rotes Stirnband) erscheinen hinter/neben dem Gegner (kameraabgewandt), werfen Shuriken, die sich um ihn in den Boden bohren (1,2/1,4/1,6), alle stürmen durch ihn (2,0), der echte Ninja erscheint hinter ihm, Katana-Lichtschnitt (2,3), Shuriken blitzen, Puff, Puff zu Hause | 3 / 3,8 s / 2,3 s (AoE 2.4x + 25) |
| Uralter Bärchi (`AncientBaerchi`) | Legendary | **Wurzelwall** (`RootBulwark`, vorher Titan-Modus) | Aufbäumen, Stampfer (0,45: Moosring), Wurzeln brechen rundum aus dem Boden und flechten sich über ihm zum Käfig (Rinde, Moosknoten), Spitzen treffen sich (1,4 = Schild): Puls, Blätter sprießen, Glühwürmchen, Blattkrone leuchtet, Grünfilter; Wurzeln sinken (3,0), Blätter stieben | 3 / 3,6 s / 1,4 s (Schild 90 % / 3) |
| Regenbogen-Bärchi (`RainbowBaerchi`) | Legendary | **Regenbogenbrücke** (`RainbowBridge`, vorher Chroma-Blast) | Regenbogen aus 6 Bändern zeichnet sich von ihm zum Landeplatz (0,1–0,7), Anlauf und Lauf den Bogen hoch (gleiche Kurve), Salto am Scheitel (1,85), Bauchrutscher hinab, Landung vor dem Gegner (2,4): Farbkleckse, Regenbogen-Splitter, Welle, Blitz, Farbsättigung; Regenbogen löst sich zu Glitzer auf, Hüpfer heim mit Doppelrolle | 3 / 3,9 s / 2,4 s (3x + 30) |

Alle acht haben eigene Echos (≤ 0,45 s bzw. ≤ 0,55 s, Treffer bei 0,18 bzw. 0,22 s)
und Texte in de/en/es/fr. Die alten Fähigkeiten bleiben für vorhandene Bärchis
und Fusionen erhalten (nur `defaultSkill` wurde umgestellt).

## Technik

- Neuer Baustein **`moves`**: der Bärchi selbst folgt Posen aus den DATEN
  (SkillFXConfig: `keys` mit t, at, dx/dy/dz, u + h/curve, pitch/yaw/roll in
  Umdrehungen, scale, ease, arc, trail, burst/smoke, hidden, tip, dxc). Alle 8
  Shows nutzen ihn, keine Show braucht mehr eine eigene Tanz-Funktion. Setzt
  `ctx.avatarCf/avatarScale/avatarModel` (neues Ctx-Feld `avatarModel` für
  Lupe, Kopfhörer, Medaille, Blattkrone, Katana).
- Neue Bausteine: `icepath`, `iceblock`, `clawmarks`, `pawprints`, `lensbeam`,
  `djset`, `coinshower`, `ninjaclones`, `katana`, `roots`, `rainbow`,
  `paintsplash`. Helfer in EINER Tabelle `LOW` (ease, groundY, fxAnchor,
  sprinkles, bridge, tube, shuriken) – die Modul-Ebene des Controllers hat
  weiterhin 139 lokale Namen (Grenze 200).
- Kamera-abhängig (einmal beim Start, F22/F44): Landeplatz-Versatz `dxc`
  (Tiger), Ebene der Krallen (Winkelhalbierende Angreifer/Kamera), Lücke der
  Equalizer-Balken, Ring der Schattenklone (kameraabgewandt), Katana-Schnitt.
- `rainbow` und `moves` (`curve`) nutzen dieselbe Brückenformel `LOW.bridge`
  (kubische Bezier wie ein Beam) – der Bärchi läuft auf den Bändern.
- Geändert in Studio: `SkillFXController` (+1.930 Zeilen), `SkillFXConfig`
  (+8 Einträge, Doku), `SkillConfig` (+8 Einträge), `BaerchiConfig` (8×
  `defaultSkill`), `Strings de/en/es/fr` (+24 Zeilen je Sprache).
- Backup: `ServerStorage.Backup_vor_ErsteBaerchis_2026-10-25` (8 Skripte).
- Repo: Code-Paket `updates/ErsteBaerchis_2026-10-25/` (README mit Ankern).
  Ein Gesamtabgleich Studio → Repo der fünf Fähigkeiten-Skripte steht weiter
  aus (sie liegen im Repo auf dem Stand vom 20.10.).

## Wie getestet

- Kompilier-Check (loadstring aller 8 Skripte), Config-Prüfung per Klon-require
  (Dauer, impactAt, Sounds, Bausteine, Schritt-Enden ≤ Dauer, Texte).
- Eingefrorene Bühnen mit Bildern (Tageslicht, ohne Farbfilter): Bauchrutscher
  (Rutschen, Eisblock), Tigersprung (Sprung, Hiebe aus der Kamera-Achse),
  Brennglas (Lupe + Brennpunkt, Echo), Bass-Drop (Beat 2, Drop), Münzregen,
  Shuriken-Sturm (Klone, Katana), Wurzelwall, Regenbogenbrücke (Lauf, Landung).
  Vorher/Nachher nach den Korrekturen.
- Messläufe: Klon-Positionen und Marker-Teile entlang der Zeit (Landung/Treffer
  bei impactAt ± 0,05 s, Rückkehr nach Hause, keine Reste).
- Echter PIT-Lauf je Fähigkeit mit dem Omega-Bärchi als Träger: je 1 volle Show
  + 4–9 Echos, 0 Warnungen, Kamera `Custom`, Originale wieder sichtbar,
  Farbfilter neutral, keine Reste; Omega danach auf `OmegaWorldsEnd`
  zurückgetauscht (per GetPlayerData geprüft).

## Befunde und Korrekturen (Vorher/Nachher)

- Eisbahn fast weiß, Reifkanten unsichtbar → satteres Eis, blaue Neon-Kanten,
  höhere Zacken, Eisbär mit dunkelblauem Umriss.
- Krallenhiebe vom Angreifer verdeckt → Tiger landet kameraabgewandt (`dxc`),
  Marken-Ebene zur Winkelhalbierenden Angreifer/Kamera, Streifen dicker.
- Lupe klebte am Gegner → Detektiv steht weiter weg (`gap` 2,4 in moves und
  pawprints), Lupe höher/vorn, Brennkegel kräftiger.
- Streusel zu klein, Kopfhörer-Muscheln blühten weiß → Stäbchen 0,55 × 0,16,
  sattes Pink.
- Regenbogen unsichtbar → Attachments müssen erst eingehängt werden, dann
  `WorldCFrame` (sonst relativ zu PARK); Bärchi lief 0,7 Studs über den Bändern
  → dy gesenkt.
- Schattenklone standen zwischen Kamera und Gegner → Ring relativ zur Kamera
  (180°/125°/235°).
- Münzen blass (Reflexion), spritzten im Gegner → satt, matt, größer, Start vor
  dem Gegner.
- Wurzelkäfig dünn → 10 Wurzeln, Moosknoten an jedem Gelenk, größere Blätter.

## Offen

- Sichtprüfung durch Nicklas im echten Kampf (er besitzt keinen Eisbär,
  Tigerbär, Detektiv oder Zucker-DJ; je 1 Grizzly, Ninja, Regenbogen und 3
  Uralte, alle Lv. 1 – Migration auf die neuen Fähigkeiten angeboten).
- Studio-Place speichern (Datei → Auf Roblox speichern).
- Gesamtabgleich Studio → Repo der Fähigkeiten-Skripte.
