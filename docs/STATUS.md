# Stand des Spiels (fortlaufend, zuletzt 26.10.2026)

Diese Datei ist der Einstieg für jede Sitzung. Am Ende einer Sitzung fortschreiben,
höchstens 60 Zeilen. Details stehen in den Berichten (`docs/INDEX.md`).

## Bereiche

| Bereich | Stand | Letzter Bericht |
|---|---|---|
| Welt 1 (Hub, Plots, Brücken) | fertig, Plots seit 25.10. 1,5 Studs tiefer | `Worldbuilding.md`, `HBB_PLOT_TIEFER_2026-10-25.md` |
| Kampf-Pit V2 „Honig-Kolosseum“ | an (`PIT_V2`), Abnahme läuft | `Worldbuilding.md` (Abschnitt Kampf-Pit V2) |
| Tower, Balance | Balance v3 an (`TOWER_BALANCE_V3`, `DROPRATES_V2`), Pacing-Sims grün | `HBB_BALANCE_V3_KONZEPT_2026-10-21.md` |
| Final-Epilog → Welt 2 | abgenommen 20.10. (`FINAL_EPILOG`) | `HBB_EPILOG_ABNAHME_2026-10-20.md` |
| Welt 2 (Look, Anime-Ei) | an (`WELT2_LOOK`, `ANIME_EGG`) | `claude/HBB_W2_ANIME_SKALIERUNG_2026-10-21.md` |
| Fähigkeiten-Shows | 8 neue + Pulsar-Nova **nur in Studio** (siehe Offen 1) | `HBB_ERSTE_BAERCHIS_SHOWS_2026-10-25.md`, `HBB_PULSAR_NOVA_UMGESETZT_2026-10-25.md` |
| Geräte (Handy, Konsole) | an (`UI_ADAPTIVE_V1`, `CONSOLE_V1`) | `HBB_W1_P6_2026-10-20.md` |
| UI, Texte | Prüfer grün, 4 Sprachen | `HBB_UI_QUALITAET_1_TEXTE_2026-10-06.md` |
| Audio | Rework 16.10., Epilog-Sounds offen | `AUDIO_REWORK_2026-10-16.md` |
| Shop | Code fertig, Robux-IDs fehlen | `HBB_PAKET_10_SHOP_2026-10-05.md` |

## Studio ↔ Repo

- Letzter Studio-Stand im Repo: Studio-Sync 25.10. (Commits `51ffce2`, `27d9cf8`).
- Seitdem nur im Repo (noch nicht in Studio): Aufräumen 26.10. mit 17 Skripten
  (Feedback über `Notify`, Menüleisten-Fix, Texte über `Loc`, Kommentare).
  Einspielen: `python tools/make_update_rbxmx.py 70dab63`.
- In Studio neuer als im Repo: `SkillFXController`, `SkillFXConfig`, `SkillConfig`,
  `BaerchiConfig`, `Strings/*`. `make_update_rbxmx.py` hält diese Dateien zurück.

## Offen (nach Wichtigkeit)

1. **Gesamtabgleich Studio → Repo der Fähigkeiten-Skripte** (Liste oben). Bis dahin diese
   Dateien im Repo nicht ändern. Danach `STUDIO_VORAUS` in `make_update_rbxmx.py` leeren.
2. **Tageszyklus**: `AmbienceConfig.DAY_CYCLE` war bis 15.10. an und ging beim Merge verloren;
   jetzt ausdrücklich `false` (= heutiges Verhalten). Entscheiden: wieder an?
3. **Rebirth-Bedingung**: Test `rebirth_rules` rot. Mit Balance v3 ist die Bedingung für
   Rebirth 6 schwächer als für Rebirth 5 (Equivalent 63,0 statt ≥ 67,5). Wegen
   `REBIRTH_NEEDS_WORLD2` erst nach Welt 2 relevant. In `check_all.py` als „bekannt“ geführt.
4. `EggPanelSkin.luau` steht auf `--!nonstrict`; Umstellung auf strict braucht die Typprüfung in Studio.
5. Welt (aus `Worldbuilding.md` Abschnitt 8): W07 Spawn im Kernstrahl, W21 `Welt2Boden` rund,
   W06 Bärchi-Wege in Welt 2, Kolosseum-Mobiltest.
6. Anime-/Welt-1-Pets `Pet_Genesis`, `Pet_Infinity`, `Pet_Shade`, `Pet_Ascendant` ca. 100× zu groß.
7. Feature-Flags ausbauen, sobald abgenommen (Reihenfolge nach Abfragestellen:
   `UI_HONEY_SKIN` 27, `HONEY_POND_V2` 10, `INCUBATOR` 10, `UI_V2_GUIDE` 9, `SHOP_V1` 8).
8. Große Dateien teilen (`MapConfig` 192/200 Locals, `SkillFXController` nach Abgleich,
   `BaerchiPanel`, `MapService`). Vorschlag: `HBB_ARCHITEKTUR_TOKEN_CHECK_2026-10-26.md`.
9. Robux-Produkt-IDs für den Shop, Audio-IDs für den Epilog.
