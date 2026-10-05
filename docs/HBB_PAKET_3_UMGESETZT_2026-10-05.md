# HBB Paket 3 umgesetzt – 05.10.2026

## Neu
- `Modules/UnlockRules` (rein): `visible(data)`, `isVisible`, `hasProgress`, `ELEMENTS` (zugleich Whitelist). Jede Regel monoton; nicht monotone Quellen über Zähler in `stats` oder den Latch `uiSeen`.
- Neues Feld `uiSeen: {[string]: boolean}` in `PlayerData` (Default `{}` in `applyDefaults`), im Client-Update enthalten.
- `UiStateService` + `RequestMarkUiSeen(ids)` (Whitelist, max. 16 Ids, Cooldown 0,3 s). Saat beim ersten Laden: Stand mit Fortschritt → alles Sichtbare gilt als gesehen (keine Badge-Flut); frisches Konto → nur Grundelemente.
- Client `UI/Unlock`: `apply` (Sichtbarkeit + Pop-in), `isNew` (Badge), `markSeen`. Angewendet auf HUD-Pillen (Gold, Rang, Rebirth), Menü-Kacheln (Eier, Bärchis, Ei-Baum, Bestenliste, Bonus), Event-Knopf, Charms- und Verwerten-Knopf auf der Bärchi-Karte, Index-Reiter.
- `Controllers/UpgradeHintController`: grünes ⬆ über eigenen Gebäuden, wenn der nächste Ausbau bezahlbar ist (nur Client, aus `EconomyConfig.HONEY_UPGRADE_COSTS`).

## Freischalt-Tabelle (umgesetzt)
| Element | Sichtbar ab |
| --- | --- |
| Gummies, 🥚, 🐻, Fight | immer |
| Event-Knopf, 🏆, 🎁 | erster Kampf (Rekord, gespeicherter Lauf oder Kampf-Zähler) oder Rebirth ≥ 1 |
| GoldGummies-Pille | Besitz > 0, danach Latch |
| 🌳 Ei-Baum | 10 geöffnete Eier, mehr als die 2 Start-Knoten frei, oder Rebirth ≥ 1 |
| Upgrade (Paket 4) | 2 geöffnete Eier (monotoner Ersatz für "2 Bärchis") |
| Charms | Rebirth ≥ 1 oder Tower-I-Rekord ≥ 15 |
| Verwerten | 21 geöffnete Eier (Ersatz für "mehr als 20 Bärchis") |
| Rang- und Rebirth-Pille | Rebirth ≥ 1 |
| Index-Reiter | 3 Arten in `discovered` |
| 🛒 Shop (Paket 10) | vorerst aus |

## Geänderte und neue Dateien
- neu: `shared/Modules/UnlockRules.luau`, `server/Services/UiStateService.luau`, `client/UI/Unlock.luau`, `client/Controllers/UpgradeHintController.luau`, `tools/luau-tests/unlock_rules.test.lua`
- geändert: `Network/Types` (uiSeen), `Util/PlayerMigration` (Default), `PlayerService` (Update), `Remotes`, `NetworkConfig`, `GameManager`, `UI/Hud`, `UI/MenuBar`, `UI/PetBar`, `UI/BaerchiPanel`, `UI/BaerchiInventory`, `Main.client`

## Annahmen und Abweichungen
- Monotone Ersatzwerte für Bärchi-Anzahl: `stats.totalHatched` (geöffnete Eier).
- Badge für Pillen ohne Klick verschwindet nach 4 s Sichtbarkeit, Kacheln beim ersten Antippen.
- Rebirth ≥ 1 schaltet Event/Bestenliste/Bonus/Baum/Upgrade/Verwerten frei (Veteranen-Absicherung).

## Prüfergebnisse
| Werkzeug | Ergebnis |
| --- | --- |
| `luau tools/luau-tests/unlock_rules.test.lua` | grün (frisch = 4 Elemente, hatch10, Tower-Rekord, Veteran, Latch, Monotonie über 200 Zufallsfolgen) |
| luau-compile | grün |
| migration.test.lua (uiSeen) | **nicht gelaufen** – Fall zu Hause ergänzen |
| Studio | noch nicht gesehen |

## Studio-Testschritte für den Menschen
1. Update einspielen, Duplikate prüfen.
2. `state fresh`: genau 1 Pille (Gummies), 2 Kacheln (🥚 🐻), Fight-Knopf.
3. `state hatch10`: Ei-Baum-Kachel ploppt mit "!" auf; Index-Reiter da.
4. `state tower1`: Event-Knopf, 🏆, 🎁 erscheinen mit Pop-in; Charms auf der Karte.
5. `restore` (Veteran): alles sichtbar, **keine** Badge-Flut.
6. Genug Gummies → ⬆ über Bienenstock/Veredler.
7. Mobil-Emulator. `UI_V2_PROGRESSIVE = false` → altes HUD.

## Offen
- Fall `uiSeen` in `migration.test.lua`.
