# Plot tiefergelegt (25.10.2026)

**Auftrag (Nicklas):** „Das Plot steht hier etwas hoch ab und das auf allen Seiten, wir müssen es ein wenig tieferlegen.“ (Bild vom Außensteg auf die Welt-2-Platte.)
**Entscheidungen:** 1,5 Studs tiefer (Platte auf 0,5), für alle Plots (eine Zahl), Stufen-Deko bei Welt 2 auf die Platte in der Farbe des Plattenbodens.
**Ergebnis:** abgenommen („du hast das Plot vernünftig tiefergelegt, ich bin zufrieden“).

## Was geändert wurde (Studio und Repo, gleiche Anker-Edits)
| Datei | Änderung |
|---|---|
| `shared/Config/MapConfig.luau` | `PLOT_SIZE = Vector3.new(72, 0.5, 72)` statt `(72, 2, 72)`; Kommentar mit Grund und Rückweg (2). Keine neue `local` (192/200). |
| `server/Util/MapBuild/PlotBuilder.luau` | Welt-1-Treppe anteilig an der Beet-Höhe (bei 2 wie früher 0,72 / 1,38), bei Beet-Höhe ≤ 1 keine Stufen: flache Stufen hätten die Vorplatz-Bordsteine (bis 0,39) durchstechen lassen. Goldkante bleibt. |
| `shared/Config/WorldFXConfig.luau` | `ISLAND_STAGE.WELT2 = { RIM_RADIUS 52.5, FLOOR_DROP 0.15, COLOR (62,54,82), MATERIAL Slate }`. |
| `client/Controllers/PlotLifeController.luau` | Welt-2-Plots (Attribut `World2` + Schalter `WELT2_LOOK`): Stufen-Deko steht auf dem Plattenboden (R 52,5, y = PLOT_SIZE.Y − 0,15), Farbe und Material des Bodens, ohne Neon/Tag-Nacht-Leuchten. Insel-Deko unter der Platte (`Platform.PlotIslandDecor_<slot>` komplett, Scenery-Teile mit Mitte im Inselradius: Randbüsche/-felsen) lokal per `LocalTransparencyModifier` aus, solange die Platte steht; wird der Plot frei oder verliert er Welt 2, wieder an. Reagiert auf späteres Setzen des Attributs (Epilog-Umbau). |

Automatisch mitgewandert (alles rechnet mit `PLOT_SIZE.Y` / `MapParts.plotSurfaceOffset()`): Beet/`Base`, Bordsteine, Zaun, Schild-Tor, Spawn, Brunnen/Teich, Inkubator, Recycler, Terminal, Fusionsmaschine, Bärchi-Figuren, Bärchi-Wege (`PlotRoutes.beetTop`), Welt-2-Vorlage samt Lichtstrahlen, `Welt2Boden`, `Welt2Rampe`, Client-Kamerapunkte (`WorldShotController`) und Welle (`WorldMomentController`).

Kein neuer Schalter: der Rückweg ist die eine Zahl (`PLOT_SIZE.Y = 2` ergibt exakt die alte Geometrie, auch die Treppe). Die neue Welt-2-Deko-Logik hängt am bestehenden `WELT2_LOOK`.

## Maße nachher (Slot 1, Welt 2)
- Laufhöhe Plot 0,5 (vorher 2,0); Figur steht bei y 3,34.
- Welt-2-Platte: Boden-Außenring −0,15…0,35, Innenscheibe (R 30) bis 0,5, Goldrand (R 54,8–58) −0,15…0,55, Schürze bis −6,15.
- Kante Innenbrücke → Platte 0,5 (vorher 2), Arena-Seite Rampe 0,5 → 0,08.
- Welt-1-Beet: 72 × 0,5 × 72, Bordstein 0,58, Ecksteine 0,83, Goldkante 0,46–0,60, keine Treppe.
- Alles auf dem Plot exakt −1,50 (Messung vorher/nachher je Kind von `Plot_1`); Stege, Arena, Raketen-Insel, Vitrine unverändert.

## Wie getestet
- `luau-compile --null` (4 Dateien), `check_locals.py` (MapConfig weiter 192, Rest unkritisch), `check_consistency/decor/members/feedback/loc/ui`: nur Altbefunde, nichts in den geänderten Stellen.
- Tests grün: guide_steps, unlock_rules, boss_tiers, map_layout, honey_pond, tower_unlock, pit_v2, rocket_island, map_style, combat_rating, gold_rules, live_board, event_schedule, egg_press, shop, migration_hbb, endless, ui_texts.
- Playtest: Konsole ohne Fehler; Hash Studio = Repo (MapConfig 9a6ca5eb, WorldFXConfig 8acebaf8, PlotLifeController ad014b44; PlotBuilder war schon verschieden, gleicher Zuwachs).
- Lauftests (im Client-DataModel): Innenbrücke → Platte und zurück ohne Sprung, Platte → Außensteg über die Rampe.
- Bärchi läuft und hüpft auf dem neuen Boden (Unterkante 0,58 bei Bodenkontakt).
- Client: 57 Deko-Teile in (62,54,82) Slate, kein Neon; 107 + 10 verdeckte Teile ausgeblendet; leere Insel (Slot 2) unberührt, Frei-Schild kommt nach Test-Plot zurück.
- Welt 1: Test-Plot mit Platzhalter-Besitzer auf dem leeren Slot 2 gebaut, fotografiert, entfernt (RespawnLocation des Spielers unverändert).
- Bilder: `docs/screens/plot_tiefer/2026-10-25/` (00 vorher = Bild des Nutzers, 05/06 = Kamera-Set wie vorher, 24 Nutzerblick vom Steg, 25 Rand-Deko, 26/27 Welt-1-Beet).

## Backups
- Studio: `ServerStorage.Backup_vor_PlotTiefer_2026-10-25` (MapConfig, WorldFXConfig, PlotBuilder, PlotLifeController).
- Repo: `backup_vor_plottiefer_2026-10-25/` (Repo-Stände; PlotBuilder dort ist der ältere Repo-Stand, der Studio-Stand liegt im Studio-Backup).

## Offen
- **Speichern:** Datei → Auf Roblox speichern.
- Eier, die schon liegen, haben ihre alte Höhe gespeichert und schweben bis zum Einsammeln 1,5 Studs zu hoch (sammelbar, Touched). Neue Eier liegen richtig.
- `Welt2Boden` ist ein Quader 108 × 108, die Platte aber rund (R 58): an den Diagonalen geht der unsichtbare Boden bis R 76 über Sand und Wasser (begehbare Luft, schon vorher). Vorschlag: Zylinder-Collider R 58.
- Bärchi-Wege (`PlotRoutes`) laufen zwischen Beet-Kante und Plattenrand weiter auf y 0, jetzt aber höchstens 0,35–0,5 statt 2 im Boden (Worldbuilding W06).
