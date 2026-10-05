# HBB Paket 1 umgesetzt – 05.10.2026

## Neu
- Toast-Inventar: 32 Anlässe klassifiziert (`FeedbackConfig`), davon 5 TOAST (16 %), 7 MOMENT, 17 ICON, 3 NONE.
- `UI/Feedback`: Gummies, GoldGummies und Eier werden **am Datenstand erkannt** (ClientState) und fliegen als Icon zur Pille bzw. zur Eier-Kachel, "+25" steigt auf, Pille pulsiert. XP, Level, Stat-Stufe, Waben und Ausbau erscheinen als Zahl über dem Bärchi bzw. dem eigenen Charakter. Zusammenfassen im 0,4-s-Fenster, max. 6 Icons, Pool + eine RenderStepped-Schleife.
- `UI/Moment`: großes Icon in der Mitte, Farbe, kurzer Ping, höchstens ein Wort (`ui.moment.*`, 4 Sprachen). Warteschlange max. 3.
- `UI/ReturnSummary`: Rückkehr-Karte aus Icons und Zahlen (⏱ Dauer, 🥚 +n, Honig +n), sammelt beide Offline-Berichte 1,2 s, Antippen schließt.
- `UI/Notify.emit(key, alt, neu)`: eine Stelle entscheidet nach Flag und Klasse. Alter Toast bleibt wörtlich erhalten (Flag aus = wie vorher).
- `Hud.getPillAnchor` / `Hud.pulse`, `MenuBar.getTileAnchor`.
- `tools/check_feedback.py`: schlägt fehl, wenn ein benutzter Schlüssel nicht klassifiziert ist, ein Toast ohne `Notify` steht oder TOAST > 20 %.

## Toast-Inventar
| Schlüssel | Datei | Auslöser | Häufigkeit | Klasse |
| --- | --- | --- | --- | --- |
| action_failed | UI/Toast | ActionFailed | oft | TOAST |
| hatch_failed | UI/HatchAnimation | Server antwortet nicht | selten | TOAST |
| event_notice_info | EventFXController | Event-Hinweis | mittel | TOAST |
| event_notice_big | EventFXController | Ansage an alle (Boss, fremder Jackpot) | selten | TOAST |
| event_mid | BaerchiPanel | Zwischenmeldung (Server-Text) | mittel | TOAST |
| event_mid_rarity | BaerchiPanel | UFO-Rarity-Aufstieg | selten | MOMENT |
| event_end_mutation | BaerchiPanel | Mutation am Event-Ende | selten | MOMENT |
| tree_unlocked | ResultFeed | EggTreeUnlocked | selten | MOMENT |
| tower_record | CombatPanel | neuer Rekord | mittel | MOMENT |
| tower_milestone | CombatPanel | Meilenstein | mittel | MOMENT |
| promotion_slot | BaerchiPanel | Charm-Slot frei | selten | MOMENT |
| rebirth_done | RebirthDialog | Rebirth | selten | MOMENT |
| recycle_result, egg_pressed, comb_delivered, recycler_upgraded, tower_result, promotion, egg_collected, egg_bought, egg_collected_all, event_end, daily_claimed, quest_reward, offline_honey, offline_eggs, level_up, feed, event_notice_good | div. | Zahlen/Belohnungen | oft–mittel | ICON |
| boss_hit, charm_roll, fusion_result | div. | sieht man ohnehin | oft | NONE |

## Geänderte und neue Dateien
- neu: `shared/Config/FeedbackConfig.luau`, `client/UI/Feedback.luau`, `client/UI/Moment.luau`, `client/UI/ReturnSummary.luau`, `client/UI/Notify.luau`, `tools/check_feedback.py`
- geändert: `UI/Toast` (ActionFailed über Notify), `UI/Hud` (Anker, Puls), `UI/MenuBar` (Anker), `Controllers/ResultFeed`, `Controllers/EventFXController`, `Controllers/CombController`, `UI/BaerchiPanel`, `UI/CombatPanel`, `UI/CharmPanel`, `UI/DailyBonusPanel`, `UI/FusionPanel`, `UI/QuestTracker`, `UI/RebirthDialog`, `UI/HatchAnimation`, `Main.client`, `Strings/de|en|fr|es` (+7 Schlüssel)

## Annahmen und Abweichungen
- Währungen/Eier über Datenstand statt Aufruf an jeder Belohnungsstelle: keine doppelten Icons, keine vergessene Stelle. Folge: auch stetiger Recycler-Ertrag erzeugt fliegende Gummies (zusammengefasst). Im Playtest prüfen, ob das zu unruhig ist.
- `event_notice_big` bleibt TOAST: das sind Ansagen an alle (Boss kommt, Jackpot eines anderen Spielers) – als eigener großer Moment wäre das irreführend.
- Ungenutzte Schlüssel nach der Umstellung (nur noch im alten Pfad): `msg.recycled`, `msg.recycled_gold`, `msg.offline_honey`, `msg.level_up`, `msg.tree_unlocked`, `msg.pressed`, `msg.comb_delivered`, `msg.recycler_upgraded`, `msg.tower_milestone`, `msg.daily_claimed`, `ui.quest.toast`, `msg.rebirth_done*`, `ui.boss.hit`. Nicht gelöscht (Flag-Rückweg).

## Prüfergebnisse
| Werkzeug | Ergebnis |
| --- | --- |
| luau-compile (alle Dateien) | grün |
| check_feedback.py | grün (32 Klassen, alle benutzt, TOAST 16 %) |
| Schlüssel-Vergleich de/en/fr/es (Ersatz für check_loc.py) | grün, gleiche Schlüsselmenge |
| check_members.py, check_consistency.py, client.test.lua | **nicht gelaufen** (tools/ nur auf dem Heim-PC) |
| Studio | **noch nicht gesehen** – Update liegt bereit (siehe unten) |

## Studio-Testschritte für den Menschen
1. Rojo bzw. Update-Datei einspielen, auf doppelte Skripte prüfen.
2. `snapshot`, `state fresh`: Ei öffnen → Bärchi erscheint, **kein** Text-Toast. Ei vom Plot einsammeln → Ei fliegt zur Eier-Kachel.
3. Fight → Gummies fliegen zur Gummy-Pille, Pille pulsiert. Neuer Rekord → Pokal-Moment mit "Rekord!".
4. Bärchi frisst Honig → "+XP" steigt über dem Bärchi auf.
5. Schnell 5 Eier hintereinander einsammeln → eine zusammengefasste Zahl, keine Überlappung.
6. Spiel verlassen, 10 min warten, wieder rein → Rückkehr-Karte mit Uhr, Ei, Honig.
7. Mobil-Emulator (Touch): Zahlen lesbar, Karte antippbar.
8. `FeatureFlags.UI_V2_FEEDBACK = false` → alte Toasts wie vorher.

## Offen
- Studio-Durchlauf "Join bis erster Fight ohne Text-Toast" (Fertig-Kriterium) steht aus.
- Test in `client.test.lua` (Klassifizierung) ist durch `check_feedback.py` ersetzt; beim Zusammenführen ggf. in client.test.lua übernehmen.
