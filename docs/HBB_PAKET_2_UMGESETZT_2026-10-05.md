# HBB Paket 2 umgesetzt – 05.10.2026

## Neu
- `Modules/GuideSteps` (rein, ohne requires): Schritt aus den Daten – `hatch` → `fight` → `collect` (falls ein gelegtes Ei liegt) → `event`; danach (Paket 5) `merchant`, wenn keine Eier mehr da sind. Veteranen (Rebirth ≥ 1 oder ≥ 4 Ketten-Quests) bekommen keine Führung.
- `Controllers/GuideController`: Welt-Ziele mit lokalem Beam (zwei Attachments, nur Client), UI-Ziele mit pulsierendem Rahmen und Pfeil. Nach 12 s ohne Fortschritt wird die Hervorhebung stärker. Kein Text.
- Quest-Tracker kompakt: Quest-Icon je Messgröße (`QuestConfig.METRIC_ICON`), Balken mit Zähler, Belohnung als Icon + Zahl, ✓ statt "Belohnung abholen", Tagesquests als "📜 1/3" bzw. "🎁". Antippen klappt den Volltext 6 s auf, zweites Antippen öffnet wie bisher das Quest-Fenster.
- Sprache: Globus-Knopf mit Sprachkürzel → kleines ⚙ an derselben Stelle (öffnet LanguagePanel).
- Wiedereinstieg: kein PitResumeDialog mehr. Mit gespeichertem Lauf startet Fight kostenlos ab 65 % ("Percent"), sonst von vorn. Der bezahlte Einstieg ab der letzten Stage ist ein kleiner Knopf "⏩ Stage · Preis" im Tower-Fenster (CombatPanel). Server unverändert.
- RebirthDialog: Zeilen als Icon + Zahl (x1,50 ➜ x1,68 · Gummies/Preis · +Eier); die Warnung bleibt ein kurzer Satz (`ui.rebirth.warn_short`, 4 Sprachen).
- Login-Bonus: Konten, die an diesem UTC-Tag angelegt wurden, sehen das Fenster erst nach dem ersten beendeten Kampf.
- Neuer Zähler `stats.totalEventsCompleted` (Event-Ende mit Belohnung), `PlayerDataUpdate` trägt jetzt `stats` und `createdAt`.

## Geänderte und neue Dateien
- neu: `shared/Modules/GuideSteps.luau`, `client/Controllers/GuideController.luau`, `tools/luau-tests/guide_steps.test.lua`
- geändert: `Network/Types` (stats.totalEventsCompleted, Update-Felder), `PlayerService` (Update-Felder), `EventParticipationService` (Zähler), `QuestConfig` (METRIC_ICON), `UI/QuestTracker`, `UI/Hud` (⚙), `UI/PetBar` (Anker, Wiedereinstieg), `UI/CombatPanel` (bezahlter Knopf), `UI/RebirthDialog`, `UI/DailyBonusPanel`, `Main.client`, Strings (+1 Schlüssel)

## Annahmen und Abweichungen
- **Reihenfolge der Schritte** weicht vom Vorschlag ab: ein frisches Konto hat keinen Bärchi und damit keine gelegten Eier. Deshalb erst öffnen, dann kämpfen; "einsammeln" kommt als Einschub, sobald ein Ei liegt.
- **Sprache:** Zahnrad statt Profilzeile – eine eigene Profilkarte gibt es nicht (ProfilePanel zeigt nur andere Spieler).
- **Event-Schritt** braucht einen Zähler: `stats.totalEventsCompleted` (Zähler, kein Tutorial-Feld). Alte Stände bekommen 0 über die bestehende Stats-Schleife in `applyDefaults`; Veteranen sind über die Veteranen-Regel ausgenommen.
- Optionaler "Anfeuern"-Tap nicht gebaut (optional, zuletzt).

## Prüfergebnisse
| Werkzeug | Ergebnis |
| --- | --- |
| `luau tools/luau-tests/guide_steps.test.lua` | grün (14 Fälle inkl. Monotonie) |
| luau-compile | grün |
| migration.test.lua (neuer Stats-Zähler) | **nicht gelaufen** – Fall muss zu Hause ergänzt werden |
| Studio | noch nicht gesehen |

## Studio-Testschritte für den Menschen
1. Update einspielen, Duplikate prüfen.
2. `snapshot`, `state fresh`: Rahmen + Pfeil an der Eier-Kachel. Ei öffnen → Pfeil springt auf "Fight". Kampf → Pfeil auf "Event" (Knopf erscheint erst jetzt, Paket 3). Liegt ein Ei auf dem Plot → gelber Beam vom Charakter zum Ei.
3. 12 s nichts tun → Rahmen pulsiert stärker.
4. Kein Login-Bonus-Popup vor dem ersten Kampf; danach erscheint es.
5. Quest-Karte: Icon + Zähler; antippen → Volltext; noch einmal → Quest-Fenster.
6. Fight mit gespeichertem Lauf → kein Dialog, Start ab 65 %. Tower-Fenster: Knopf "⏩ N  Preis" startet ab der letzten Stage.
7. Rebirth-Dialog: Icons, ein Warnsatz.
8. `UI_V2_GUIDE = false` → alles wie vorher.

## Offen
- Fertig-Kriterium "frischer Account ohne Text-Hinweis bis zum ersten Fight" in Studio.
- Fall `stats.totalEventsCompleted` in `migration.test.lua`.
