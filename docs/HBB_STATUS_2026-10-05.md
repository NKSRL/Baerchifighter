# HBB Umsetzung – Stand 05.10.2026

| Paket | Stand | In Studio getestet |
| --- | --- | --- |
| 0 Flags, Funnel | fertig | ja – F01–F09 im Output, 0 Fehler |
| 1 Feedback | Code fertig | nein (Laptop gesperrt) |
| 2 Führung | Code fertig | nein |
| 3 Freischaltung | Code fertig | nein |
| 4 Upgrade/Kampfwert | Teil (kein echter Tab, kein Aufklapper) | nein |
| 5 Map | Teil (Händler, Heim-Knopf); Schau-Turm, 3 Tafeln, Weg zur Arena offen | nein |
| 6 Timer/Board | Teil (Timer, erste Pause); Live-Board offen | nein |
| 7 Boss-Stufen | Code fertig | nein |
| 8 Pacing | **blockiert**: `sim/progression_pacing.lua` liegt nur auf dem Heim-PC; danach Stopp für die Freigabe der Tabelle | – |
| 9, 10 | warten auf Paket 8 | – |

## Wo der Code liegt
- Laptop: `Dokumente\Neuer Ordner\RBL` (Git-Repo, Tag `pre-ui-v2` = Stand vor HBB).
- Studio-Einspielung: `Dokumente\Neuer Ordner\HBBUpdate_P1-P7.rbxmx` über *Datei → Roblox-Modell importieren*, dann den Einspiel-Befehl in der Befehlsleiste (verteilt die Skripte an ihre Plätze).
- Tests ohne Studio: `luau tools/luau-tests/guide_steps.test.lua`, `unlock_rules.test.lua`, `boss_tiers.test.lua`; `python tools/luau-tests/run_local.py tools/luau-tests/combat_rating.test.lua`; `python tools/check_feedback.py`.

## Zusammenführen mit dem Heim-Repo
Nur `src/`, `tools/check_feedback.py`, `tools/luau-tests/*` und `docs/` übernehmen. `default.project.json` ist rekonstruiert – die vom Heim-PC behalten. Danach dort alle Prüfwerkzeuge laufen lassen und in `migration.test.lua` die Fälle `uiSeen` und `stats.totalEventsCompleted` ergänzen.
