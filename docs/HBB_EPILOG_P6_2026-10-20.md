# Final-Epilog · Prompt 6 von 7 – Knopf-Finale, Welt 2, Rückweg (20.10.2026)

**Status:** Code fertig, kompiliert, alle Prüfungen und Tests grün (bekannte Altbefunde unverändert: MapConfig 192, CombConfig, unlock_rules, migration_hbb C4). **In Studio nicht gespielt** – Kamera-Gefühl, Raketen-Flug, Shockwave und Portal sind ungetestet.

## Was gebaut wurde
- **Server (`EpilogService`)**: `startFinale` ist der einzige Weg zu „launched“. Prüft Flag, State pending/seen, kein laufendes Finale (doppelt = no-op), lebender Avatar, Terminal vorhanden, Abstand < 14 Studs, Rate-Limit 1/s. Dann EINE Mutation (`applyLaunch`: launched + `launchedAt` + `worlds.unlocked.World2`), Speichern, `World2Unlocked`, `EpilogLaunchResult{phase="start", token, startAt, route, rocketBase}`. Eingänge: Terminal-Prompt (`onLaunchRequested`, Halten 1,2 s) und `RequestPressLaunch` (nur mit gültigem Token). Ein Druck vor `EpilogSeen` holt pending→seen nach.
- **Zeitplan (f = Sek. seit Druck)**: Countdown 3/2/1 bei 1,2/2,5/3,8 · 0,3 s Stille (4,7) · Start 5,0 · Feier 7,5 · Ende 9,0 · Rückweg: Flash, Avatar+Begleiter auf den Gipfel (9,2), Brücke/Insel/Terminal bauen sich ab (3 s), Turm fährt 3 s ab (Lift) ≈ 6 s. Danach `placeOnPlotIfFar`, `EpilogLaunchResult{phase="end"}`.
- **Skip**: ab Sekunde 5 (Ring/E/Gamepad X), Server prüft Token und Zeit, springt zum Rückweg.
- **Abbruch**: Tod, Charakterwechsel, Fehler → sofort alles weg (Rakete, Gipfel, Insel, Terminal), Avatar auf den Plot, Zustand bleibt „launched“. Verlassen: `cancelFinale`; beim Join mit „launched“ räumt `restore` auf (ohne Effekte).
- **`WorldService`** (neu, nur lesen): `isUnlocked`, `isWorld2Unlocked`.
- **Rakete** (`Util/MapBuild/EpilogFinaleBuilder`, neu): Schacht + Rakete neben dem Terminal, 2 Emitter, ohne Kollision; Mesh-Vorlage `EpilogRakete` oder Primitive (≤ 8 Teile). Hängt am Insel-Teardown.
- **Client**: `EpilogController` (Finale-Phasen, Skip, Steuerung/HUD paarweise, `audit`), `UI/EpilogFinaleFX` (neu: Raketen-Tween, Shockwave, Portal-Silhouette, Himmel-Tint, Bloom 1,5→0,8, Kamera-Schütteln 0,3→0,8 über `Humanoid.CameraOffset`), `EpilogOverlay` (Countdown-Zahl, Banner, Hinweis, 3 Salven, Konfetti-Regen). `EpilogTerminalController` zeigt die Zahl und schaltet die Lampen Gelb→Grün.
- **Dauerhaft**: Plot-Abzeichen „Welt 2“ (`PlotDisplayService`, Signatur `:W2`), Profil-Zeile (`world2` in der Profilkarte).
- **Texte** (de/en/fr/es): `epilog.finale.banner`, `epilog.finale.hint_world2`, `epilog.world2.badge`, `ui.moment.world2`, `ui.world.owner_badge_w2`, `ui.profile.world2`. **Cues** (Platzhalter): `epilog_press/countdown/launch/unlock`.
- **Debug**: `epilog launch` spielt das Finale (baut bei Bedarf alles sofort), `epilog launch fast` wie bisher nur Spielstand; `epilog scan` zeigt `finaleLaeuft`, `raketeTeile`.
- **Fix aus Prompt 5**: Die Fahrt hatte die ganze `RBL`-ScreenGui abgeschaltet, dabei wäre der Moment-Banner „TOWER GESCHAFFT!“ mit verschwunden. Jetzt werden nur die Elemente außer `Moment` ausgeblendet und danach wiederhergestellt.
- **Assets** (`assets/epilog/`): `Epilog_Rakete.fbx` (394 Tris, Pivot Unterseite, Vertexfarben; `.blend` daneben), `Epilog_Shockwave.png` und `Epilog_Portal.png` (512², Alpha). Vorschau: `docs/screens/EPILOG_P6_RAKETE_vorn.png`, `EPILOG_P6_RAKETE_seite.png`, `EPILOG_P6_ASSETS.png`.
- **Test**: `tools/luau-tests/epilog_finale.test.lua` (Zeitplan, Budgets, Spielstandregeln, Cues) grün.

## Annahmen / Abweichungen
1. Rückweg über „Zurück“-Teleport mit Flash statt Rücklauf (laut Prompt erlaubt; hält die ~6 s).
2. Das Terminal hat keine Antenne (P4) – „Antenne dreht schneller“ entfällt; Lampen/Zahl zeigen den Countdown.
3. Banner „WELT 2 FREIGESCHALTET“ als Overlay-Text; `Moment` zeigt Icon + kurzes Wort „WELT 2!“ (Moment kann nur ein Wort).
4. Die Kamera bleibt die normale Spielerkamera mit Schütteln (kein Scriptable-Flug); Rakete kann außerhalb des Blickfelds starten.
5. Remote-Druck ohne gehaltenen Prompt ist mit Token + Abstand erlaubt (Fehlklickschutz liegt im Prompt).
6. Controls sind während des Finales deaktiviert (paarweise wieder an).

## Offen
- **Asset-IDs fehlen**: PNGs/FBX müssen von Hand hochgeladen bzw. importiert werden; IDs in `Config/EpilogConfig.ASSETS` (`shockwaveTex`, `portalTex`, `rocketTemplate` = Vorlagenname). Ohne sie laufen Primitive/Frames.
- `make_update_rbxmx.py` nicht ausgeführt, nichts committet, nichts in Studio getestet (auch nicht: Vertexfarben der Rakete, Flossen-Ausrichtung der Primitive, Portal-Größe/Entfernung).
- `epilog audit` nach einem Durchlauf und `epilog scan` (0 Reste, Teile ≤ 250) bitte in Studio prüfen.
- Audio: Platzhalter, füllt Prompt 7.
