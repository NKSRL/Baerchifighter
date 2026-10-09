# RBL / Honey Bear Brawl – Hinweise für Claude Code (Laptop)

Roblox-Spiel (Luau). Lies zuerst `docs/HBB_STATUS_2026-10-05.md`, dann den Bericht des Pakets, an dem du arbeitest (`docs/HBB_PAKET_*`).

## Struktur
- `src/shared` → ReplicatedStorage, `src/server` → ServerScriptService, `src/client` → StarterPlayerScripts
- Schalter: `src/shared/Config/FeatureFlags.luau`
- Regeln: `--!strict`, deutsche Kommentare, Texte nur über `Loc` (de/en/fr/es), Server ist autoritativ, nichts löschen.

## Prüfen (vor jedem Commit)
- `luau-compile --null <datei>` (Syntax)
- `python tools/check_locals.py` (Roblox erlaubt max. 200 lokale Namen pro Modul-Ebene; der luau-CLI meldet das NICHT)
- `luau tools/luau-tests/guide_steps.test.lua`, `unlock_rules.test.lua`, `boss_tiers.test.lua`
- `python tools/luau-tests/run_local.py tools/luau-tests/<name>.test.lua` für `combat_rating`, `gold_rules`, `map_layout`, `live_board`, `event_schedule`, `egg_press`, `honey_pond`, `shop`, `migration_hbb`, `endless`, `day_cycle`, `island_stage`
- `python tools/check_feedback.py` (plus `check_members.py`, `check_consistency.py`, `check_loc.py`, `check_decor.py`); `check_members.py` endet auch bei Funden mit 0, Ausgabe lesen
- Sims ohne Node: `python tools/luau-tests/run_local.py tools/sim/<name>.lua` (Exit 1 bei `FAIL`); Pflicht bei Balance-Änderungen: `progression_pacing.lua`, `tower_calibration.lua`
- Luau-CLI: https://github.com/luau-lang/luau/releases (luau-windows.zip; Linux/Cloud: luau-ubuntu.zip)

## In Studio bringen (kein Rojo auf dem Laptop)
Option A: Rojo installieren (`aftman`/Rojo 7.7.0), `rojo serve`, im Studio-Plugin verbinden.
ACHTUNG: `src/shared/Assets/BaerchiTemplate.rbxm` fehlt hier – vorher in Studio
ReplicatedStorage/Assets/BaerchiTemplate per Rechtsklick → „Als Datei speichern“ dorthin sichern, sonst löscht Rojo das Modell.
Option B: geänderte Skripte von Hand in Studio einfügen.

Nach Änderungen in Studio: Datei → Auf Roblox speichern.

## Nicht hier verfügbar
`tools/luau-tests/run.mjs` und die Node-Tests (`migration.test.lua`, `client.test.lua`, `loc.test.lua` …) liegen nur auf dem Heim-PC.
`tools/sim/*` und `tools/check_*.py` sind da. Paket 8: umgesetzt (`docs/HBB_GOLD_NUR_CHARMS_2026-10-05.md`, 12 Charm-Würfe/Tag).
