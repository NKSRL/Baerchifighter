# HBB Umsetzung – Stand 05.10.2026

| Paket | Stand | In Studio getestet |
| --- | --- | --- |
| 0 Flags, Funnel | fertig | ja – F01–F09 im Output, 0 Fehler |
| 1 Feedback | Code fertig | nein (Laptop gesperrt) |
| 2 Führung | Code fertig | nein |
| 3 Freischaltung | Code fertig | nein |
| 4 Upgrade/Kampfwert | Code fertig (zweispaltige Karte, Einzelwerte im Aufklapper; kein eigener Tab) | nein |
| 5 Map | Code fertig (Händler, Heim-Knopf, Schau-Turm, 3 Tafeln, Arena-Sprint) – `docs/HBB_PAKET_5_6_MAP_2026-10-05.md` | nein |
| 6 Timer/Board | Code fertig (Timer, erste Pause, Live-Board, Wespen-Nest) | nein |
| 7 Boss-Stufen | Code fertig | nein |
| 8 Pacing | Entscheidungen umgesetzt: Gold nur Charms (`GOLD_CHARMS_ONLY`), Look 2 Ziel 20–45 min, Zeitmessung im Funnel. Charm-Gold: 12 Würfe/Tag (`docs/HBB_GOLD_NUR_CHARMS_2026-10-05.md`) | nein |
| 9 Endless | Code fertig (Tower ∞ ab Final 100, Endless-Level je Bärchi, Bestenliste Endless + Woche mit Krone) – `docs/HBB_PAKET_9_ENDLESS_2026-10-05.md`; `ENDLESS` an | nein |
| 10 Shop | Code fertig (Gratis-Griff, Robux-Pakete vorbereitet, IDs fehlen) – `docs/HBB_PAKET_10_SHOP_2026-10-05.md` | nein |

## Playtest 05.10.2026
Rückmeldungen umgesetzt: `docs/HBB_PLAYTEST_FIXES_2026-10-05.md`. Stock/Veredler → Honig-Teich mit Brunnen-Looks: `docs/HBB_HONIG_TEICH_2026-10-05.md`.

## Nachtrag Cloud-Sitzung 05.10.2026
- Repo enthält jetzt auch `tools/sim/*` und `tools/check_*.py` (vom Heim-PC); es fehlen weiterhin `tools/luau-tests/run.mjs`, `migration.test.lua` und die übrigen Node-Tests.
- `run_local.py` führt alle `tools/sim/*.lua` aus (alle zehn grün) und meldet `FAIL` per Exit-Code 1.
- `check_feedback.py` war rot (Fehlalarm durch den längeren Paket-7-Rückruf): Belohnungs-Momente nach `EventFXController.playRewardMoment` ausgelagert, Verhalten gleich.
- Alle Prüfungen grün: Syntax (alle `.luau`), 5 Luau-Tests (neu: `gold_rules.test.lua`), alle Sims, `check_feedback/members/consistency/loc/decor`.
- Studio-Einspielung offen: geänderte Skripte seit dem Laptop-Export siehe `git diff a85f360 --stat -- src`.

## Welt aufwerten (09.10.2026, Cloud-Sitzung)
Pakete 0, A (Tageslauf), B (Wasser), C (Hauptinsel) als reine Client-Optik umgesetzt, Schalter `AmbienceConfig.DAY_CYCLE`, `WORLD_B_WATER`, `WORLD_C_HUB`. Kein Server-Teil neu. Nicht in Studio getestet. Bericht und Zwischenabnahme 1: `claude/WELT_AUFGEWERTET_UMGESETZT_2026-10-09.md`.

## Wo der Code liegt
- Laptop: `Dokumente\Neuer Ordner\RBL` (Git-Repo, Tag `pre-ui-v2` = Stand vor HBB).
- Studio-Einspielung: `Dokumente\Neuer Ordner\HBBUpdate_P1-P7.rbxmx` über *Datei → Roblox-Modell importieren*, dann den Einspiel-Befehl in der Befehlsleiste (verteilt die Skripte an ihre Plätze).
- Tests ohne Studio: `luau tools/luau-tests/guide_steps.test.lua`, `unlock_rules.test.lua`, `boss_tiers.test.lua`; `python tools/luau-tests/run_local.py tools/luau-tests/combat_rating.test.lua`; `python tools/check_feedback.py`.

## Zusammenführen mit dem Heim-Repo
Nur `src/`, `tools/check_feedback.py`, `tools/luau-tests/*` und `docs/` übernehmen. `default.project.json` ist rekonstruiert – die vom Heim-PC behalten. Danach dort alle Prüfwerkzeuge laufen lassen und in `migration.test.lua` die Fälle `uiSeen` und `stats.totalEventsCompleted` ergänzen.
