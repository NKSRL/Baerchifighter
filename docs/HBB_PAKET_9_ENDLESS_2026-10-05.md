# HBB Paket 9 – Endless (Stage 101+) – 05.10.2026

Schalter: `FeatureFlags.ENDLESS` (an). Aus = alles wie vorher (kein Tower ∞, keine Tafeln, Endless-Level wirkungslos, weil nie offen).
Entwurf und Fragen: `docs/HBB_PAKET_9_ENTWURF_2026-10-05.md` (überholt). Antworten: Bärchi-Level über 50 statt Kronen, Meilenstein-Bonus ja, Wochen-Rangliste mit Kosmetik ja, Sonder-Belohnungen später.

## Was der Spieler erlebt
- **Tower ∞ „Endless“** öffnet, sobald Final 100 einmal geschafft ist (Rekord bleibt über Rebirths). Stage 1 im Endless = „Stage 101“: Gegner wachsen weiter +0,5 Äquivalenz je Stage, 999 Stages.
- **Endless-Level je Bärchi** (`Baerchi.endlessLevel`): Auf Level 50 fließen Honig-XP nicht mehr ins Leere, sondern ins Endless-Level (nur wenn Endless offen). Anzeige auf der Bärchi-Karte: „Level 50 / 50  ∞ +N“, XP-Balken zeigt den Weg zum nächsten.
  - +1 Endless-Level wirkt wie +1 Level (Werte ×1,10), ≈ +2 Endless-Stages.
  - Zählt nur auf Level 50, bleibt über Rebirth (Rebirth setzt nur Level/XP zurück), Fusion übernimmt das höhere.
  - XP-Kosten: `xpForNextLevel(50) × 340 × 1,02^N` (`BaerchiConfig.ENDLESS_XP_BASE/FACTOR`).
- **Meilensteine** im Endless: wie Final (flache Gummies, Ei jede 10., Blaupause jede 25., kein Gold) und **jede 10. Stage +1 Endless-Level** für den ausgerüsteten Bärchi.
- **Bestenlisten**: „Endless“ (Allzeit-Rekord) und „Endless Woche“ (beste Stage seit Montag 00:00 UTC, eigener OrderedDataStore je Woche). Zwei neue feste Tafeln in den freien Lücken 112,5° und 247,5°, zwei neue Reiter im Bestenlisten-Fenster.
- **Krone ♛** vor dem Plot-Symbol für die Top 10 der **Vorwoche**, eine Woche lang. In Studio ohne DataStore: Top 10 der laufenden Sitzung (damit testbar).

## Zahlen (`tools/sim/progression_pacing.lua`)
| Woche | Vielspieler (4 h/Tag): Endless-Level / Endless-Stage |
| --- | --- |
| 6 | 2 / 5 (Final 100 geschafft) |
| 8 | 12 / 25 |
| 10 | 22 / 45 |
| 12 | 32 / 65 |
| 16 | 46 / 93 (≈ „Stage 193“) |
Normalspieler (90 min/Tag) erreichen Endless erst in Woche 16. Neue Sim-Ziele: Vielspieler Woche 16 bei Endless 80–100 und jede Woche Fortschritt. Ein höherer Faktor (≥ 1,05) lief in eine Wand (Stillstand ab Woche 10) – deshalb flache Kurve mit hohem Grundpreis.

## Technik
- `TowerConfig`: Endless-Eintrag (nur mit Schalter), `isEndlessOpen(records)`, `getStageCap/isOpen(…, records?)`, `displayStages`, Meilenstein-Feld `endlessLevels`, `ENDLESS_LEVEL_EVERY = 10`.
- `CombatCalculator.getCombatLevel` (Level + Endless-Level auf Max), von `getEffectiveStats` benutzt.
- `HoneyService.tryLevelUp(…, endlessOpen)`, Autopilot frisst mit offenem Endless weiter, `FusionService` übernimmt das Maximum, `TowerService` (Meilenstein, Wochenbestwert `towers.endlessWeek`).
- `LeaderboardConfig` (Listen, `weekOf`, `storeName`, `CROWN_TOP_N`), `LeaderboardService` (Stores nach Namen, Krone), `MapService.setOwnerCrown`, `MapConfig.LEADERBOARD_BOARDS_V2` (Feld `flag`), `LeaderboardPanel` (5 Reiter).
- Spielstand: nur optionale Felder (`Baerchi.endlessLevel`, `TowerState.endlessWeek`) – keine Migration nötig.
- Test: `tools/luau-tests/endless.test.lua`.

## In Studio prüfen
1. Debug (Befehlsleiste, siehe Kopf von `DebugService`): `towerrecord Final 100` (ggf. vorher `rebirthcap`) → Kampf-Fenster zeigt Tower ∞ offen; ohne Final 100 gesperrt mit Hinweis.
2. Bärchi auf 50, füttern → Karte zeigt XP-Balken für Endless, später „∞ +1“; Kampfwerte steigen.
3. Endless Stage 10 schaffen → Meldung „+1 Endless-Level“.
4. Tafeln bei 112,5°/247,5° stehen frei (kein Steg, keine Laterne), werden beschriftet; Reiter im Fenster.
5. Nach `lbflush` in Studio: eigene Plot-Plakette zeigt „♛ ◆ Tower ∞ · N“, wenn man in der Sitzungsliste der Woche ist.
