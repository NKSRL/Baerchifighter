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
| 8 Pacing | **Tabelle fertig, wartet auf Freigabe** (`docs/HBB_PAKET_8_TABELLE_2026-10-05.md`, 3 Fragen); `PACING_V2` aus | – (reine Config) |
| 9, 10 | warten auf Freigabe Paket 8 | – |

## Nachtrag Cloud-Sitzung 05.10.2026
- Repo enthält jetzt auch `tools/sim/*` und `tools/check_*.py` (vom Heim-PC); es fehlen weiterhin `tools/luau-tests/run.mjs`, `migration.test.lua` und die übrigen Node-Tests.
- `run_local.py` führt alle `tools/sim/*.lua` aus (alle zehn grün) und meldet `FAIL` per Exit-Code 1.
- `check_feedback.py` war rot (Fehlalarm durch den längeren Paket-7-Rückruf): Belohnungs-Momente nach `EventFXController.playRewardMoment` ausgelagert, Verhalten gleich.
- Alle Prüfungen grün: Syntax (alle `.luau`), 4 Luau-Tests, `check_feedback/members/consistency/loc/decor`.

## Wo der Code liegt
- Laptop: `Dokumente\Neuer Ordner\RBL` (Git-Repo, Tag `pre-ui-v2` = Stand vor HBB).
- Studio-Einspielung: `Dokumente\Neuer Ordner\HBBUpdate_P1-P7.rbxmx` über *Datei → Roblox-Modell importieren*, dann den Einspiel-Befehl in der Befehlsleiste (verteilt die Skripte an ihre Plätze).
- Tests ohne Studio: `luau tools/luau-tests/guide_steps.test.lua`, `unlock_rules.test.lua`, `boss_tiers.test.lua`; `python tools/luau-tests/run_local.py tools/luau-tests/combat_rating.test.lua`; `python tools/check_feedback.py`.

## Zusammenführen mit dem Heim-Repo
Nur `src/`, `tools/check_feedback.py`, `tools/luau-tests/*` und `docs/` übernehmen. `default.project.json` ist rekonstruiert – die vom Heim-PC behalten. Danach dort alle Prüfwerkzeuge laufen lassen und in `migration.test.lua` die Fälle `uiSeen` und `stats.totalEventsCompleted` ergänzen.
