# Erste Bärchis – neue Fähigkeiten mit Shows (25.10.2026)

Code-Paket zum Stand in Studio. Das Repo hinkt bei den Fähigkeiten-Skripten
(`SkillFXController`, `SkillFXConfig`, `SkillConfig`, `BaerchiConfig`,
`Localization/Strings`) hinter Studio her (alle Shows seit VoidCrown liegen nur
in Studio). Dieses Paket enthält genau die Stücke, die diese Sitzung in Studio
eingebaut hat, mit den Ankern zum Einfügen.

| Datei | Ziel-Skript | Anker |
|---|---|---|
| `controller_low_block.luau` | `src/client/Controllers/SkillFXController.luau` | VOR dem Kopf `-- Abspielen` (Zeile `---…---\n-- Abspielen`) einfügen |
| `controller_ctx_zeile.txt` | ebenda, `type Ctx = { … }` | nach `novaRadius : number?,` |
| `skillfxconfig_doku.txt` | `src/shared/Config/SkillFXConfig.luau` | vor `--\n-- Fuer jeden Schritt:` |
| `skillfxconfig_eintraege.luau` | ebenda, Tabelle `FX` | vor dem schließenden `}` der Tabelle (`\n}\n\n-- Unbekannte Faehigkeit`) |
| `skillconfig_eintraege.luau` | `src/shared/Config/SkillConfig.luau` | vor dem schließenden `}` der Tabelle (vor `-- v15: AUFLADEN STATT COOLDOWN`) |
| `baerchiconfig_defaultskill.txt` | `src/shared/Config/BaerchiConfig.luau` | je Bärchi die Zeile `defaultSkill = …` ersetzen |
| `strings_<de/en/es/fr>.txt` | `src/shared/Localization/Strings/<lang>.luau` | neben `["skill.IceSlam.name"]` einfügen (Umlaute als `\u{…}`-Escapes, kommen als UTF-8 an) |

Fähigkeiten (Ids), Bärchi, Werte wie die alte Fähigkeit (balance-neutral):

| Id | Bärchi | Rarity | Stufe/Dauer/Treffer | Effekt (unverändert) |
|---|---|---|---|---|
| `PolarSlide` Bauchrutscher | Eisbär `BlueBaerchi` | Uncommon | 2 / 2,8 s / 1,5 s | Stun 1.5x + 8, Ladung 5 |
| `TigerPounce` Tigersprung | Tigerbär `OrangeBaerchi` | Uncommon | 2 / 2,6 s / 1,0 s | DoT 3 Aktionen, Ladung 4 |
| `MagnifierBurn` Brennglas | Detektiv `CrystalBaerchi` | Rare | 2 / 3,0 s / 2,1 s | Schaden 2.2x + 14, Ladung 3 |
| `BassDrop` Bass-Drop | Zucker-DJ `SugarBaerchi` | Rare | 2 / 3,0 s / 2,0 s | AoE 1.4x + 10, Ladung 6 |
| `CoinShower` Münzregen | Goldener Grizzly `GoldenGrizzly` | Epic | 3 / 3,6 s / 1,6 s | Drain 25 %, Ladung 5 |
| `ShurikenStorm` Shuriken-Sturm | Ninja `VoidBaerchi` | Epic | 3 / 3,8 s / 2,3 s | AoE 2.4x + 25, Ladung 7 |
| `RootBulwark` Wurzelwall | Uralter Bärchi `AncientBaerchi` | Legendary | 3 / 3,6 s / 1,4 s | Schild 90 % / 3 Aktionen, Ladung 8 |
| `RainbowBridge` Regenbogenbrücke | Regenbogen-Bärchi `RainbowBaerchi` | Legendary | 3 / 3,9 s / 2,4 s | Schaden 3x + 30, Ladung 4 |

Die alten Fähigkeiten (`IceSlam`, `FireBite`, `ShardBlast`, `SugarStorm`,
`GoldRush`, `BlackHole`, `TitanMode`, `ChromaBlast`) bleiben für vorhandene
Bärchis und Fusionen erhalten.

Backup in Studio: `ServerStorage.Backup_vor_ErsteBaerchis_2026-10-25`.
Bericht: `claude/HBB_ERSTE_BAERCHIS_SHOWS_2026-10-25.md` (Projekt).
