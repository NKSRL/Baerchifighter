# HBB Paket 8 – Pacing-Tabelle zur Freigabe – 05.10.2026

> **Nachtrag (Entscheidungen):** Gold nur noch aus Tages-Quests und nur für Charms → `docs/HBB_GOLD_NUR_CHARMS_2026-10-05.md` (umgesetzt, neue Pacing-Zahlen dort).
> Frage 1: Look-2-Ziel jetzt 20–45 min. Frage 2: A hinfällig, B nicht mehr empfohlen (Look 4 fiele auf 5,1 h).
> Frage 3: ja, umgesetzt: `FunnelService` meldet Sekunden seit Join je Schritt und für `P_FirstUpgrade`/`P_Look2` (Custom Event `SecondsSinceJoin`).
> Der Rest dieses Dokuments ist der Stand **vor** diesen Entscheidungen.

**STOPP-PUNKT.** Keine Spielzahl wurde geändert, `PACING_V2` bleibt `false`.
Der Mensch entscheidet über die drei Fragen unten; erst danach werden Werte eingebaut.

## Nachrechnen (ohne Node, ohne Studio)
    python tools/luau-tests/run_local.py tools/sim/progression_pacing.lua                                   # Ist
    python tools/luau-tests/run_local.py tools/sim/pacing_v2_vorschlag.lua tools/sim/progression_pacing.lua # Vorschlag
`run_local.py` kann jetzt alle `tools/sim/*.lua` ausführen (`RS`, `SSS`, `__log`, `REAL_CLOCK` wie `run.mjs`). Eine `FAIL`-Zeile ergibt Exit-Code 1.
Alle zehn Sims laufen grün; Vorschlag: genau ein FAIL (die Look-2-Grenze, siehe Frage 1).

## Ist-Stand (v15-Configs) – alle sieben Pacing-Ziele grün
Aktive Spielzeit; in Klammern der Spieltag.

| Meilenstein | Gelegenheit 30 min/Tag | Normal 90 min/Tag | Viel 240 min/Tag |
| --- | --- | --- | --- |
| Look 2 (L10) | 32 min (**Tag 2**) | 32 min (Tag 1) | 32 min (Tag 1) |
| Rebirth 1 | 3,5 h (**Tag 8**) | 3,5 h (Tag 3) | 3,6 h (Tag 1) |
| Look 3 (L20) | 4,4 h (Tag 9) | 4,5 h (Tag 3) | 4,5 h (Tag 2) |
| Look 4 (L30) | 6,9 h (Tag 14) | 7,0 h (Tag 5) | 7,0 h (Tag 2) |
| Look 5 (L45) | 19,0 h (Tag 38) | 19,1 h (Tag 13) | 19,1 h (Tag 5) |
| Look 6 (L60) | – | 61,0 h (Tag 41) | 61,1 h (Tag 16) |
| Rebirth 10 | – | 76,6 h (Tag 52) | 76,6 h (Tag 20) |
| Final Stage 100 | – | 156,9 h (Tag 105) | 156,9 h (Tag 40) |

## Befunde
1. **Erste Sitzung verfehlt.** Bei Roblox entscheidet die erste Sitzung über D1 (typische Sitzung 20–30 min). Look 2 kommt nach 32 min: Wer 30 min spielt, sieht den ersten großen Moment erst an Tag 2.
   Engpass laut Sim: **GoldGummies** für L5–10. Gummi-Kosten sind kein Hebel (L2–10 × 0,4 → weiterhin 32 min). Gold × 0,7 → 28 min. Darunter begrenzt das Laufmodell (2-min-Läufe); der Sim ist für die ersten 10 min zu grob.
2. **Lange Strecke ohne Meilenstein für Gelegenheitsspieler:** zwischen Tag 2 und Tag 8 (Rebirth 1) taucht in der Tabelle nichts auf. Das ist das D7-Fenster.
3. **Wände durch Stärke, nicht durch Preis:** Leben 5 (14,4 h), Leben 14 (17,3 h), Leben 15 (27,2 h ≈ 18 Spieltage bei Normal) hängen am Tower-Deckel bzw. an der Bärchi-Stärke (laut `EconomyConfig` so gewollt). Billigere Rebirths ändern hier nichts.
4. **Endgame leer:** Profil Viel hat ab Woche 6 Final 100, Gebäude 60, Bärchi-Level 50 und Ausbau-Bonus 82 erreicht, danach folgen nur noch Rebirths alle ~7 h. Damit ist Paket 9 (Endless 101+) begründet. Bei Normal tritt das ab Woche 15 ein.
5. Bärchi-Level 50 (Maximum) ist bei Normal ab Woche 2 erreicht; danach trägt nur noch der Ausbau-Bonus.

## Vorschlag (`tools/sim/pacing_v2_vorschlag.lua`)
| Wert | Ist | Vorschlag |
| --- | --- | --- |
| GoldGummies L5/6/7/8/9/10 | 3/8/16/30/55/95 | 2/5/11/21/38/66 (× 0,7; L11+ unverändert) |
| Rebirth 1 (Gummies) | 1.500.000 | 750.000 (Rebirth 2+ unverändert) |

| Meilenstein | Gelegenheit | Normal | Viel |
| --- | --- | --- | --- |
| Look 2 | 28 min (**Tag 1**) | 28 min | 28 min |
| Rebirth 1 | 2,4 h (**Tag 5**) | 2,4 h (Tag 2) | 2,4 h (Tag 1) |
| Look 3 | 3,4 h (Tag 7) | 3,5 h (Tag 3) | 3,5 h (Tag 1) |
| Look 4 | 6,0 h (Tag 12) | 6,0 h (Tag 5) | 6,1 h (Tag 2) |
| Look 5 / 6 | 17,9 h / – | 18,0 h / 61,0 h | 18,0 h / 61,1 h |
| Rebirth 10 / Final 100 | – | unverändert 76,6 h / 156,9 h | unverändert |

Langzeitziele (Look 5/6, Final 100 nicht vor Woche 8) bleiben unberührt.

## Fragen an den Menschen
1. **Look-2-Ziel** von 30–75 min auf **20–45 min** senken? (Ohne das ist Vorschlag A ein FAIL im Sim.)
2. **Vorschlag A** (Gold L5–10 × 0,7) und **B** (Rebirth 1 = 750.000) freigeben, einzeln oder zusammen?
3. **Erste 10 Minuten** nicht im Sim drehen, sondern mit dem Funnel aus Paket 0 (F01–F09) in Studio/Live messen? Empfehlung: ja, der Sim kann das nicht auflösen.

## Nach der Freigabe (für den nächsten Agenten)
- Werte in `EconomyConfig` als V2-Variante hinter `FeatureFlags.isOn("PACING_V2")` ablegen. Achtung: Die Gold-Kosten ab L11 werden aus `HONEY_UPGRADE_COSTS[10].goldGummies` erzeugt. Die Basis für L11+ muss deshalb 95 bleiben.
- Zielgrenze in `tools/sim/progression_pacing.lua` (`within("Normal: Look 2 …")`) anpassen; der Sim muss die V2-Werte lesen (Flag im Sim auf `true` setzen oder Vorspann übernehmen).
- `default.project.json`/Studio: keine Änderung nötig, reine Config.
