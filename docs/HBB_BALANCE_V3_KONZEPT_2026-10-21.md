# HBB Balance V3 (21.10.2026) – UMGESETZT (Schalter TOWER_BALANCE_V3 + DROPRATES_V2, beide an)

## 1. Epilog: Baerchi bleibt oben (UMGESETZT)
Ursache (aus dem Code, nicht in Studio bewiesen): `BaerchiAutopilotService` laesst den ausgeruesteten Baerchi alle 3 s zum Honigteich laufen, wenn der `ActivityLock` frei ist. Der Epilog nimmt keinen Lock -> der Baerchi lief auf dem Gipfel/der Insel los und kollidierte mit `FigurePlacement`/`walkCompanion`.
Fix: `epilogActive(player)` (hasSummit/hasIsland/hasTerminal) sperrt neue Zyklen UND bricht einen laufenden ab. Kein Lock noetig (ein Dauer-Lock haette `MapService.updateBaerchis` blockiert). In Studio testen: Epilog starten, Gipfel abwarten.

## 2. Messbefund (neue Sims `tools/sim/rarity_capability.lua`, `tools/sim/tower_rebalance_v3.lua`)
Hoechste Gegner-Aequivalenz, die eine Rarity schafft (Gegner wachsen +9 % HP/ATK je Aequivalenz-Punkt):
| Rarity | L30 P3 S30 | L40 P5 C S50 | L50 Max |
|---|---|---|---|
| Common | 31 | 44 | 59 |
| Rare | 39 | 53 | 69 |
| Epic | 50 | 62 | 78 |
| Legendary | 52 | 66 | 81 |
| Mythic | 57 | 72 | 89 |
| Divine | 76 | 92 | 109 |
| Cosmic | 71 | 86 | 104 |
| Godly | 83 | 98 | 116 |
| Eternal | 88 | 104 | 123 |
| Omega | 95 | 110 | 129 |
Aktuelle Tower-Enden: II 66,8 | III 90,4 | Final 100 = 82 | Endless-Start 132.
Erklaerung deiner Beobachtung: Tower III endet bei 90 -> mit L30-Baerchis braucht man Eternal (88). Zwischen Mythic und Divine liegt ein Sprung von ~+20 Aequivalenz (= 5x Gegnerstaerke). Jeder Tower-Endwert zwischen 72 und 91 heisst deshalb "Divine oder nichts". Endless startet bei 132 = ueber Omega mit Max-Ausbau (129) -> unmachbar.
Auffaelligkeit: Cosmic ist schwaecher als Divine (Pfad-/Stat-Streuung der Beispiel-Baerchis) – Rarity-Leiter nicht monoton, spaeter pruefen.
Offene Diskrepanz: laut Sim schafft Mythic Final 100 nie (L40: Stage 58 mit alter Kurve); dein "locker mit Mythic" passt nicht -> Studio-Stand/Team-Werte pruefen (Debug-Befehl fuer den echten Baerchi waere hilfreich).

## 3. Vorschlag Tower-Kurven (Schalter z. B. `TOWER_BALANCE_V3`, alt bleibt stehen)
| Tower | Stages | start | je Stage | Ende (Aequ.) | alt |
|---|---|---|---|---|---|
| I | 30 | 1 | 1,15 | 34,4 | gleich |
| II | 45 | 22 | 0,65 | 50,1 | 25/0,95 -> 66,8 |
| III | 60 | 41 | 0,45 | 67,6 | 55/0,6 -> 90,4 |
| Final | 100 | 58 | 0,265 | 84,2 | 52/0,303 -> 82 |
| Endless | 999 | 85 | 0,8 (statt 0,5, damit schwere Spieler nicht zu schnell durchlaufen) | – | 132/0,5 |
Monoton (jedes Ende < naechster Start). Final 100 (84) liegt knapp ueber dem heutigen III Stage 40 (78), den Mythic nicht schafft.
Sim-Ergebnis (Stages geschafft, L40 P5 Charms S50): Rare II 45 | Epic III 48 | Mythic III 60/60, Final 43 | Divine Final 100, Endless 13 | Omega Endless 49.
L30 P3 (schwaecher): Mythic III 33, Divine III 60, Final 65; Godly Final 79; Eternal Final 100.
L50 Max: Epic III 60, Mythic Final 100, Divine Endless 49, Omega Endless 87.
-> Tower I-III: Rare bis Mythic reichen. Final 100: Divine mit gutem Ausbau (oder Mythic mit Max-Ausbau). Endless: lang, waechst mit Rarity und Endless-Levels.
Belohnung: `rewardFactor` haengt an der Aequivalenz -> Final 10x, III etc. neu pruefen (`progression_pacing.lua` + `tower_calibration.lua` Pflicht, Ziele in tower_calibration anpassen).

## 4. Rarity-Prozente
Es gibt schon `DROPRATES_V2` (Standard AUS): seltenste Stufe je Ei 10 % / 5 % / 1 % / 0,1 %. Beispiele (alt -> V2): Zenith Mythic 64 / Divine 28 / Cosmic 8 -> 89,5 / 9,5 / 1; Abyss Divine 70/25/5 -> 89,5/9,5/1; Galaxy Secret/Godly/Eternal 72/23/5 -> 96,8/3,1/0,1; Omega-Ei Omega 30 -> 0,1.
Achtung: V2 hebt Basic-Ei Rare von 5 auf 10 % (falsche Richtung) und macht Omega 0,1 % (1 von 1000, evtl. zu hart). Vorschlag: V2 einschalten, Basic bei 5 % lassen, Omega-Ei auf ~3 %, Eternal-Ei ~0,5 %. Mit V3-Kurven gut kombinierbar, weil Tower I-III keine hohen Rarities mehr brauchen.

## 5. Naechste Schritte (nach deinem OK)
1. Flag `TOWER_BALANCE_V3` + Werte in TowerConfig, Endless-Anker, tower_calibration-Ziele anpassen.
2. DROPRATES_V2 mit den Korrekturen aus 4.
3. Alle Pflicht-Sims/Tests (progression_pacing, tower_calibration, endless, unlock_rules ...).
4. Studio: Team-Test Mythic/Divine an III und Final.

## Umgesetzt (21.10.)
- TowerConfig: V3-Werte (Endless 85 / 0,8). FeatureFlags: TOWER_BALANCE_V3 = true, DROPRATES_V2 = true.
- EggConfig.RAREST_PCT_V2: Basic 5 %, Galaxie/Transzendenz 0,5 %, Ewigkeit 0,3 %, Omega-Ei 3 %.
- tower_calibration.lua (ALLE ZIELE OK) und endless.test.lua auf V3 angepasst. Gruen: endless, combat_rating, gold_rules, map_layout, live_board, event_schedule, egg_press, honey_pond, shop, ui_texts, guide_steps, boss_tiers, boss_balance, pit_balance, check_loc.
- Rot, nicht von V3: migration_hbb (C4), unlock_rules (Veteran 19 vs 17).
- progression_pacing: vorher 7 Fehler, jetzt 8 (neu: Look 3 minimal frueh 1,4 h). Viel-Spieler: Endless Woche 16 = Stage 88 (Ziel 80-100 ok), aber Plateau ab Woche 6 bei ~86 (Sim-Spieler maxt aus) -> "Endless steht still" bleibt rot. Normal-Spieler Final 100 nach 32 h (Ziel >= 73,5 h) war schon vorher zu frueh.
- Offen: Studio-Team-Test Mythic/Divine, ggf. Rewards (progression_pacing) feintunen.
