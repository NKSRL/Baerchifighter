# RBL / Honey Bear Brawl – Hinweise für Claude Code (Laptop)

Roblox-Spiel (Luau). Lies zuerst `docs/HBB_STATUS_2026-10-05.md`, dann den Bericht des Pakets, an dem du arbeitest (`docs/HBB_PAKET_*`).

## Struktur
- `src/shared` → ReplicatedStorage, `src/server` → ServerScriptService, `src/client` → StarterPlayerScripts
- Schalter: `src/shared/Config/FeatureFlags.luau`
- Regeln: `--!strict`, deutsche Kommentare, Texte nur über `Loc` (de/en/fr/es), Server ist autoritativ, nichts löschen.

## Prüfen (vor jedem Commit)
- `luau-compile --null <datei>` (Syntax)
- `luau tools/luau-tests/guide_steps.test.lua`, `unlock_rules.test.lua`, `boss_tiers.test.lua`
- `python tools/luau-tests/run_local.py tools/luau-tests/combat_rating.test.lua`
- `python tools/check_feedback.py`
- Luau-CLI: https://github.com/luau-lang/luau/releases (luau-windows.zip)

## In Studio bringen (kein Rojo auf dem Laptop)
Option A: Rojo installieren (`aftman`/Rojo 7.7.0), `rojo serve`, im Studio-Plugin verbinden.
ACHTUNG: `src/shared/Assets/BaerchiTemplate.rbxm` fehlt hier – vorher in Studio
ReplicatedStorage/Assets/BaerchiTemplate per Rechtsklick → „Als Datei speichern“ dorthin sichern, sonst löscht Rojo das Modell.
Option B: geänderte Skripte von Hand in Studio einfügen.

Nach Änderungen in Studio: Datei → Auf Roblox speichern.

## Nicht hier verfügbar
`tools/check_*.py`, `sim/*`, `migration.test.lua` liegen nur auf dem Heim-PC. Paket 8–10 brauchen `sim/progression_pacing.lua`.
