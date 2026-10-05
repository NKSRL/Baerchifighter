# HBB Paket 9 – Endless (Stage 101+) – ENTWURF zur Freigabe – 05.10.2026

**Stopp-Punkt:** Laut Plan wird Paket 9 erst nach Freigabe dieses Entwurfs gebaut. `FeatureFlags.ENDLESS` bleibt `false`. Am Ende stehen 4 Fragen.

## Problem (aus den Zahlen)
- Vielspieler (4 h/Tag) erreichen Final 100 in **Woche 6**, Normalspieler (90 min/Tag) in **Woche 15** (`progression_pacing.lua`).
- Danach steigt nichts mehr: Gebäude 60, Bärchi-Level 50, Ausbau-Bonus am Maximum. Es bleiben nur Rebirths alle **~7,4 h aktive Zeit** ohne sichtbares Ziel.
- Final 100 ist genau auf die Maximalstärke kalibriert (Äquivalenz 82 + 99 × 0,5 = 131,5; Maximum ≈ 132). **Ohne neue Wachstumsquelle wäre Stage 101 nie schaffbar.**

## Vorschlag
### 1. Endless-Turm = Final-Tower ab Stage 101, ohne Obergrenze
- Freigeschaltet, sobald Final 100 einmal geschafft ist (Rekord bleibt über Rebirths, wie alle Tower-Rekorde).
- Gegner wachsen weiter wie im Final-Tower (+0,5 Äquivalenz je Stage). Die Kampfregeln bleiben gleich, kein neues System.
- Ein Lauf startet bei Stage 101 (nicht bei 1) – sonst dauerte jeder Lauf über 100 Stages.

### 2. Neue Wachstumsquelle: „Honig-Krone“ (Endless-Stärke)
- Jeder Rebirth **nach** Rebirth 15 (dem Final-100-Deckel) gibt **+1 Krone**.
- 1 Krone = +1 Äquivalenz-Stufe für alle Bärchis = **+2 Endless-Stages**.
- Tempo: Vielspieler ~3,8 Rebirths/Woche → **~+8 Stages/Woche**, Normalspieler ~1,4/Woche → **~+3 Stages/Woche**. Wer weiterspielt, kommt immer weiter; niemand ist „fertig“.
- Optional: jede 10. Endless-Stage einmalig +1 Krone (Meilenstein), damit auch Läufe selbst stärker machen, nicht nur Rebirths.
- Anzeige: Kronen-Zahl neben dem Rebirth-Zähler.

### 3. Belohnungen (ohne Gold – Gold bleibt Tages-Quests/Shop)
| Endless-Stage | Belohnung |
| --- | --- |
| jede 5. | flache Gummies (wie Final-Meilensteine) |
| jede 10. | 1 höchstes freies Ei |
| jede 25. | Blaupause |
| 110 / 125 / 150 / 200 | Schau-Turm-Look „Endless“ (Regenbogen/Honig-Kristall) + Titel auf dem Plot-Schild |

### 4. Wettbewerb (der wichtigste Hebel für Endgame-Spieler)
- **Neue Bestenliste „Endless“** (höchste Endless-Stage) als vierte feste Tafel auf der Hauptinsel (freie Lücke 247,5°) und im Bestenlisten-Fenster.
- **Wochen-Rangliste**: dieselbe Zahl, jeden Montag 00:00 UTC zurückgesetzt (eigener OrderedDataStore pro Woche). Top 10 der Woche bekommen eine Kosmetik (Rahmen um den Namen) bis zur nächsten Woche. Wöchentliche Ranglisten sind auf Roblox ein bewährter Grund wiederzukommen, auch für Spieler, die die Allzeit-Spitze nie erreichen.

### 5. Technik (Umfang beim Bau)
- `TowerConfig`: Endless als Final ohne Stage-Deckel ab 101; `getEquivalent` unverändert.
- Spielstand: `towers.endlessRecord`, `crowns` (+ Migration, Test).
- `CombatService`/`PitArenaService`: Start-Stage 101; Anzeige „F · 137“ statt „F · 100“.
- `LeaderboardService`: Liste „Endless“ (+ Woche), `MapLayout`: vierte Tafel (Layout-Test erweitert).
- Sim: `progression_pacing` um Kronen und Endless-Stages bis Woche 16 erweitern; Ziel z. B. „Vielspieler Woche 16 ≈ Stage 180–200“.

## Fragen an dich
1. **Wachstum über Kronen pro Rebirth** (+1 Krone = +2 Stages) – passt das, oder lieber eine andere Quelle (z. B. Bärchi-Level über 50 hinaus)?
2. **Meilenstein-Kronen** (jede 10. Endless-Stage +1) zusätzlich – ja/nein?
3. **Wochen-Rangliste** mit Kosmetik für die Top 10 – ja/nein?
4. **Belohnungen** wie in der Tabelle – oder andere Wünsche (z. B. besondere Eier/Bärchis ab Stage 150)?

Nach deiner Freigabe baue ich Paket 9 hinter `ENDLESS` und stimme die Zahlen mit dem Sim ab.
