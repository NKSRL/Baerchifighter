# Final-Epilog, Prompt 2 von 7: Der Gipfel (20.10.2026)

Datenversion unverändert 18. Schalter `FINAL_EPILOG` bleibt **aus** (siehe P1). Nichts gelöscht,
keine Tower-Mathematik und keine Balance-Zahlen geändert. Kein Studio-Lauf möglich (siehe „Offen").

## Was gebaut ist

Nach dem Final-100-Sieg bleibt der gestauchte Run-Turm (30 Etagen, `getRunFloor("Final", 100)`)
stehen und bekommt den Gipfel; der Avatar steht in der Mitte der obersten Etage.

Ablauf (Phasen laut Auftrag):

1. **Halten (sofort, synchron):** `EpilogService.onFinalClear` ruft `MapService.setSummit(player, true, true)`.
   Das setzt die Haltesperre `_towerHold` (30 Etagen). Ab dann kann `MapService.setPitTowerLevel` den
   Turm nicht mehr unter 30 abbauen (gilt für alle Aufrufer: Lauf-Ende, Abbruch, Fehlerpfad).
   Der Baerchi fährt nicht mehr mit dem Turm hinunter (`PitArenaService`, Rückweg übersprungen);
   `restoreHome` setzt ihn heim. Ohne Epilog (state `none`/`launched`, Schalter aus) läuft alles
   exakt wie vorher.
2. **Aufwerten (0,2–1,2 s):** Teile werden gestaffelt eingeblendet (Transparenz-Tween, nichts wackelt).
3. **Bereitstellen (1,2–1,5 s):** Attribut `Ready = true` am Modell; Spawn und Kamera-Anker stehen
   von Anfang an (siehe unten).
4. **Sequenz-Start:** `EpilogStart` kommt erst **nach dem Speichern UND nach dem Ende der
   Kampf-Wiedergabe** (`PitArenaService.isRunning`, höchstens 60 s). Dann Teleport
   (`EpilogConfig.SUMMIT.teleportDelay`, Standard 0; Prompt 5 setzt ihn auf den Flash-Höhepunkt).
   *Das ändert das Timing aus Prompt 1* (dort kam `EpilogStart` direkt nach dem Speichern).
5. **Wiederaufnahme:** `EpilogService.restore` baut für „pending“ den Gipfel ohne Animation neu,
   hält den Turm und teleportiert, sobald der Charakter steht. „seen“ bleibt Stub für Prompt 3.

Gipfel (`Epilog/Gipfel`, ein Modell; **24 Teile**, Grenze 24): Randring (Neon, Honig-Gold), Bodenplatte
(Creme, Marmor), 7 Waben-Zellen (Bernstein), 4 Kristallsäulen (Farbe = `accent` des Final-Looks
„Crystal“, ohne Kollision), 3 Brückenplatten (8,4 breit, reichen bis Radius + 6), unsichtbar:
`Rig` (Anker), 6 Geländerwände, 1 Fangboden. Ein `PointLight` am Rig (nachts 2,6 statt 1,2 Helligkeit,
einmalig beim Bau gesetzt), keine Emitter. Bild: `docs/screens/EPILOG_P2_gipfel_vorher_nachher.png`
(aus den Layout-Zahlen gerendert, **kein Studio-Foto**).

Absturzschutz: Geländer = regelmäßiges Sechseck außerhalb des Randrings, an der Brücke
unterbrochen (Lücke 8,0 < Brücke 8,4). In den Sechseck-Ecken bleiben kleine Taschen; wer dort
trotzdem abstürzt, landet nach 6 Studs auf dem unsichtbaren Fangboden und wird über `Touched`
zum Gipfel zurückgeholt (Cooldown 1 s, nur der Besitzer).

## Wo es liegt

| Datei | Inhalt |
|---|---|
| `src/server/Util/MapBuild/EpilogSummitBuilder.luau` (neu) | `build`, `teleportPlayerToSummit`, `lowerWithPlayer`, `destroy`, `holdFloors`, `exists`, `countParts` |
| `src/shared/Modules/EpilogSummitLayout.luau` (neu) | reine Geometrie (testbar) |
| `src/shared/Config/EpilogConfig.luau` | neu: `SUMMIT` (alle Maße/Farben/Zeiten) |
| `MapService.luau` | Haltesperre, `setSummit`, `getTowerHold`, `hasSummit`, `teleportToSummit`, `lowerSummit`, Neuaufbau-Schutz, Cleanup |
| `PitArenaService.luau` | Rückweg bei gehaltenem Turm übersprungen; neuer Lauf beendet den Gipfel |
| `EpilogService.luau` | `beginFull`, `teleportWhenReady`, `restore` (pending), Debug |
| `DebugService.luau` | `epilog summit`, `epilog summitoff`, `epilog scan` erweitert |
| `tools/luau-tests/epilog_summit.test.lua` (neu) | je 15 Prüfungen für 6 Plot-Richtungen + Haltehöhe, 1,5 s, ×3 |

## Prüfungen

`luau-compile` aller Änderungen grün, `check_locals` 192 (MapConfig, unverändert). Neu grün:
`epilog_summit` (Budget ≤ 24, Unterkanten, nichts schwebt, Reichweite ≤ Radius + 6, Rand ringsum
geschlossen, Brücke frei, Fangboden). Weiterhin grün: `epilog_state`, `tower_unlock`, `map_layout`,
`honey_pond`, `guide_steps`, `boss_tiers`, `combat_rating`, `gold_rules`, `live_board`,
`event_schedule`, `egg_press`, `shop`, `endless`, `ui_texts`, `check_feedback/consistency/loc/ui/decor`.
`check_members`: unverändert die 2 alten Funde. **Vorher schon rot, unverändert:** `unlock_rules`,
`migration_hbb` C4. `check_decor.py` prüft nur die Config-Deko; die Boden-Regel für den Gipfel
steckt im neuen Test.

## Annahmen

1. Schalter aus; Studio: `D:Invoke("epilog","on")`.
2. Insel-Richtung: genau „nach außen“ vom Map-Mittelpunkt (`bridgeOutwardDeg = 0`, freier Himmel).
   Prompt 3 darf sie ändern (ein Wert).
3. Waben-Muster = 7 runde Zellen (Roblox hat kein Sechseck-Teil; Material statt Textur, wie verlangt).
4. Ein **neuer Lauf** während „pending“/„seen“ beendet den Gipfel (der Turm muss wieder wachsen
   können; Endless muss erreichbar bleiben). Der Zustand bleibt, `restore` baut ihn beim nächsten
   Join neu. Ein „Zurück zum Gipfel“ im Spiel gibt es noch nicht (Prompt 3/4).
5. **Respawn:** der Gipfel wird NICHT zerstört, sondern der Spieler wird erneut hinteleportiert
   (sonst wäre „pending“ nach einem Tod verloren). Abweichung vom Auftragstext „bei Respawn zerstört“.
6. Ordner `Epilog` liegt direkt im Plot-Modell (nicht in `PitPlatform`), damit `parts` ihn als
   eigenen Eintrag zählt und Prompt 3/4 dort Insel/Terminal ablegen.
7. Kamera-Anker (Welt, am Teil `Rig`): `Spawn`, `Cam_Start` (9 Studs vor dem Avatar, schaut ihn an),
   `Cam_Orbit` (7 über der Mitte), `Cam_Bridge` (12 hinter dem Rand, 9 hoch, schaut nach außen) — meine
   Annahme, Prompt 5 darf umhängen.

## Schnittstellen für Prompt 3/5/6

- Prompt 3: Ordner `plot.Epilog` (Modell `Gipfel` darin); Brücke beginnt an Radius + 6 in Richtung
  `Gipfel:GetAttribute("BridgeAngle")` auf Höhe `FloorY`; `EpilogService.setPlaceHandler` für „seen“.
- Prompt 5: Attachments `Spawn`, `Cam_Start`, `Cam_Orbit`, `Cam_Bridge` am Teil `Gipfel.Rig`;
  `EpilogConfig.SUMMIT.teleportDelay`; Attribut `Ready`.
- Prompt 6: `MapService.lowerSummit(player, companionUid?, seconds?)` fährt den Turm in
  `PIT_TOWER_FALL_SECONDS × 3` (2,4 s) ab (Spieler + Begleiter als Lift), danach fehlen Gipfel und
  Sperre. Direkt: `EpilogSummitBuilder.lowerWithPlayer(player, fromLevel, setLevel, {seconds, companion})`.
- Aufräumen: `MapService.setSummit(player, false)` bzw. `EpilogSummitBuilder.destroy(player)`;
  automatisch bei Leave (`despawnIsland`), Reset (`epilog reset`), `epilog launch`.

## Abnahme in Studio

1. `D:Invoke("epilog","on")`, `D:Invoke("epilog","summit")` → Gipfel blendet in 1,5 s ein, Avatar
   steht in der Mitte der obersten Etage. `D:Invoke("parts")` → Eintrag `Epilog` = 24.
2. `D:Invoke("epilog","summitoff")` → alles weg, `epilog scan` zeigt `reste = false`.
3. Echter Ablauf: `D:Invoke("epilog","reset")`, Final-100-Lauf: Turm bleibt, Baerchi geht heim,
   Avatar oben; Studio beenden, neu starten: `epilog state` = pending, Avatar steht oben.
4. Normaler Lauf bei state `none`/`launched`: Turm fährt wie bisher ab.

## Offen

- **Studio-Abnahme und echte Screenshots** (kein Studio-Zugriff in dieser Sitzung; die Teilezahl
  der Gesamtinsel ist nicht gemessen: Stand 191–209 + 24 ergibt rechnerisch 215–233, ohne die
  temporären Lauf-Etagen).
- Der Begleiter-Baerchi kann bei einem Figuren-Neuaufbau (`updateBaerchis`) oder durch den Autopilot
  wieder nach Hause springen; das sauber zu halten ist Teil von Prompt 3/5.
- Einspielen per `python tools/make_update_rbxmx.py` (nicht ausgeführt).
