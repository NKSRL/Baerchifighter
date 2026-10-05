# HBB Paket 7 umgesetzt – 05.10.2026

## Neu
- `Modules/BossTiers.tierFor(damage, potential, activeRecently, won)` → 0–4 (rein). Stufe 1 ab 1 Schaden; 2/3/4 ab 5/25/60 % des **eigenen Potenzials**; gemeinsamer Sieg +1 (max. 4); nicht aktiv in den letzten 60 s → höchstens 1 (nach dem Sieg-Bonus).
- `WaspQueenEvent`: Potenzial = DPS des eigenen Bärchis × Zeit am Boss; Aktivität alle 2 s (> 4 Studs bewegt, serverseitig, ohne `Player.Idled`). Stufen-Belohnung **zusätzlich** zur bisherigen Anteils-Belohnung (Top 3, Sieg-Ei unverändert). Mit Flag entfällt die "zu wenig Schaden"-Meldung.
- Auszahlung in `EventParticipationService` über vorhandene Bausteine: Gummies (`EconomyService`), Waben (`CombRecyclerService`), Basis-Eier (`EggService.grantEggs`), Mutations-Wurf (Weg des Mutations-Sturms).
- Anzeige: Truhe in vier Farben (`Moment.show("chest")`), danach fliegen die Inhalte über den Datenstand in die Pillen. Text nur im alten Pfad (`msg.boss.tier`, 4 Sprachen).

## Belohnungstabelle (`EventConfig.BOSS_TIERS`)
| Stufe | Gummies (Basis) | Waben | Basis-Eier | Mutations-Wurf |
| --- | --- | --- | --- | --- |
| 1 | 40 | 3 | 0 | – |
| 2 | 60 | 4 | 1 | – |
| 3 | 80 | 5 | 2 | – |
| 4 | 100 | 6 | 2 | 20 % × Rarity-Dämpfung |

## Erwarteter Wert (Gummi-Gegenwert, Basis-Ei = 50 G Händlerpreis)
| | Recycler L1 (3 G/Wabe) | Recycler L10 (240 G/Wabe) |
| --- | --- | --- |
| Stufe 1 | 49 G | 760 G |
| Stufe 2 | 122 G | 1.070 G |
| Stufe 3 | 195 G | 1.380 G |
| Stufe 4 | 218 G + Mutations-Wurf | 1.640 G + Mutations-Wurf |
| Heutiger Sieg (Durchschnitt) | 345 G + höchstes Ei | 3.900 G + höchstes Ei |

Stufe 4 liegt unter der heutigen Siegbelohnung. AFK (immer Stufe 1): höchstens 760 G pro Boss bei Recycler L10, ein Boss alle 91 min – kein lohnendes Farming.

## Prüfergebnisse
| Werkzeug | Ergebnis |
| --- | --- |
| `luau tools/luau-tests/boss_tiers.test.lua` | grün (0 → 0, 1 → 1, Schwellen, AFK nie > 1, Sieg +1 mit Deckel 4, Monotonie) |
| luau-compile | grün |
| sim/boss_balance.lua | nicht vorhanden (Heim-PC); Tabelle oben von Hand gerechnet |

## Annahmen und Abweichungen
- "Wabe aufgehoben" zählt noch nicht als Aktivität (nur Bewegung); Bewegung im Pit deckt den Normalfall.
- Neue `Reward`-Felder `bossTier`, `tierBonus`, `tierEggs` (EventKit).

## Studio-Testschritte
1. Drei Konten: AFK (Charakter steht still außerhalb des Pits), aktiv (läuft im Pit), stark.
2. `startevent WaspQueen`, alle Bärchis hinschicken, Kampf laufen lassen bzw. `skipevent`.
3. Output: `[WaspQueen] <Name> | Stufe n | Schaden / Potenzial | aktiv`. Erwartet AFK = 1, aktiv ≥ 2, Sieg +1.
4. Client: Truhe in der Stufenfarbe, danach fliegende Gummies/Eier.
5. `BOSS_TIERS = false` → alte Auszahlung.
