# tools — Prüfungen und Simulationen ohne Studio

Alles hier findet Fehler, bevor Roblox sie beim Start meldet, oder rechnet
Balance nach, ohne das Spiel zu starten. Gebraucht werden Python 3 und
Node.js (ab 18).

## Vor jedem Commit

Aus dem Projektordner:

    cd tools/luau-tests
    npm install                              # einmalig
    node check_syntax.mjs                    # alle .luau-Dateien kompilieren
    node run.mjs loc.test.lua                # Lokalisierung
    node run.mjs client.test.lua             # Rauchtest der Client-UI
    node run.mjs migration.test.lua          # alte Spielstände → aktuelle Version
    node run.mjs session_lock.test.lua       # Sitzungs-Sperre beim Speichern
    node run.mjs login_bonus.test.lua        # Login-Bonus (Tageswechsel, Gnadenfrist, Reset, UTC)
    node run.mjs ../sim/progression_pacing.lua  # Pacing: Looks, Rebirths, Final-Tower (v15)
    node run.mjs ../sim/tower_calibration.lua   # Tower-Kalibrierung je Rarity (v15)
    node run.mjs ../sim/egg_tree_check.lua   # Regeln des Ei-Baums
    node run.mjs ../sim/path_balance.lua     # Pfad-Profile (Gold/Kristall/Void)
    node run.mjs ../sim/fight_timeline.lua   # Zeitbudget der Kampf-Wiedergabe
    cd ../..
    python tools/check_members.py
    python tools/check_consistency.py
    python tools/check_loc.py
    python tools/check_ui.py
    python tools/check_decor.py

Alle Befehle enden mit Exit-Code 0, wenn alles in Ordnung ist, und mit 1 bei
einem Fehler.

## Luau-Tests und Simulationen (`luau-tests/`, `sim/`)

Führen Luau-Code mit dem echten Compiler aus (npm-Paket `luau-web`). Roblox
selbst ist durch Attrappen ersetzt. Details: `luau-tests/README.md`.

| Datei | prüft / zeigt |
|---|---|
| `check_syntax.mjs` | jede `.luau`-Datei unter `src/` kompiliert |
| `loc.test.lua` | `Loc`: Sprachwahl, Platzhalter, Plural, Fallbacks |
| `client.test.lua` | Client-UI startet, Sprachwechsel, Toasts, HUD, Menü |
| `migration.test.lua` | Spielstände im Format v6, v10, v13 und v14 laufen durch `PlayerMigration.applyDefaults`, ergeben die Struktur von `Types.PlayerData` und ändern sich beim zweiten Durchlauf nicht mehr |
| `login_bonus.test.lua` | `LoginBonusCalc`: Tageswechsel, Gnadenfrist (1 Tag), Reset, Doppelklick, Wechsel genau 00:00 UTC, Zyklus 1..7 |
| `session_lock.test.lua` | `SessionLock`: wann ein Spielstand als von einem anderen Server gehalten gilt |
| `sim/egg_tree_check.lua` | Verteilungen = 100 %, Ø steigt entlang jeder Kante, jeder Bärchi fällt aus einem Ei, jede Fähigkeit hat eine Show, Lege-Fallback landet auf freiem Ei |
| `sim/path_balance.lua` | kein Pfad gewinnt alle drei Ziele (Stärke, Tempo, Seltenheit) |
| `sim/fight_timeline.lua` | ein PIT-Lauf bleibt im Zeitbudget |
| `sim/pit_balance.lua` | Tabelle: erreichbare Stages je Rarity und Tower (keine Prüfung) |
| `sim/tower_calibration.lua` | Zielwerte der Tower (L1 Common ~3 Stages, Omega max Final 70–100, 100 Stages < 50 ms) |
| `sim/progression_pacing.lua` | Pacing-Ziele (Look 2–6, Rebirth 1, Final 100 nicht vor Woche 8) für 30/90/240 min pro Tag |
| `sim/egg_tree_sim.lua` | Tabelle: Spieltage bis zur Freischaltung je Knoten (keine Prüfung) |

Die Typprüfung (`--!strict`) machen diese Tests nicht, das bleibt Studio.

## `check_members.py` — unbekannte Modul-Felder

Findet Zugriffe wie `MapConfig.GIBT_ES_NICHT`. Ein Wert wird in einer Config
umbenannt, und eine Stelle greift noch auf den alten Namen zu; Luau meldet
das nicht, weil die Configs einfache Tabellen zurückgeben.

## `check_consistency.py` — verteilte Wahrheiten

* Die Gebäude-IDs sind in allen neun Listen identisch (`MapConfig.BUILDING_OFFSETS`,
  `BUILDING_ORDER`, `BuildingBehavior.BEHAVIORS`, `BUILDING_UPGRADES`,
  `Theme.BUILDING_COLORS`, `IslandService.VALID_BUILDINGS`,
  `WorldController.BUILDING_NAMES`, `BuildingPanel.BUILDINGS`,
  `Types.createDefaultPlayerData`) und gleich `Types.BuildingId`.
* `RateLimiter.connect`: Remote-Objekt und Cooldown-Schlüssel heißen gleich,
  und jedes verbundene Remote hat einen eigenen Cooldown in `NetworkConfig`.
* Jedes Modul in der `GameManager`-Startliste existiert als Datei.
* Jeder Service mit `init()` oder `start()` steht in der Startliste.
* Jede `.luau`-Datei unter `src/` beginnt mit `--!strict`.

## `check_loc.py` — Übersetzungen

Hat jede Sprache alle Schlüssel, stimmen die `{platzhalter}`, gibt es jeden im
Code verwendeten Schlüssel? `--todo` listet Texte, die noch fest im Code stehen.

## `check_ui.py` — Qualitäts-Tor für Spieler-Texte und Menüs

Zerlegt den Code in Tokens und weiß deshalb, wo ein String landet (statt
anhand von Signalwörtern zu raten wie `check_loc --todo`). Jede Regel ist ein
Fehler:

| Regel | findet |
|---|---|
| T1 | fester Text in einer Anzeige (`.Text =`, `Theme.label/button/…`, Toast, Prompt-Texte, `Icons.make`-Ersatztext, Tabellenfelder wie `label =`) — auch über Hilfsfunktionen, deren Parameter in einer Anzeige landen (`section("…")`, `EventKit.setLabel`, `MapService.setPitBanner`, lokale Aliase) |
| T2 | Text mit Wörtern ohne `Loc` (Client) bzw. deutscher Text (Server/Shared) außerhalb von Logs |
| T3 | `.displayName` / `.description` / `.drawback` / `.shortName` direkt gelesen statt über `Localization/Names` |
| T4 | Config-Eintrag (Bärchi, Ei, Skill, Event, Charm) ohne seine Loc-Schlüssel |
| T5 | `Loc.t/tn/msg/bind`-Aufruf übergibt nicht alle `{platzhalter}` des Textes |
| P1 | Panel ohne `Theme.dialog`-Hülle |
| P2 | `ScrollingFrame` ohne `Theme.scroller` |
| P3 | Schließen-Knopf ohne `Theme.closeButton` (große Trefferfläche) |

Bewusste Ausnahme: Kommentar `-- ui-ok: <Grund>` am Zeilenende (ohne Grund
zählt sie nicht).

`luau-tests/ui_texts.test.lua` ergänzt das zur Laufzeit: alle Namen,
Beschreibungen, Event-Belohnungen, Charm-/Gebäude-Effekte und verschachtelte
Server-Nachrichten in de/en/fr/es — kein `[schlüssel]`, kein `{platzhalter}`,
kein vergessener deutscher Text.

## `check_decor.py` — Geometrie der Gebäude

Prüft `MapConfig.BUILDING_DECOR` / `CENTER_DECOR`: nichts steckt im Boden,
nichts schwebt, Deko bleibt im Grundriss und unter dem Schild.

## Vorschauen

* `render_decor.py decor_preview.html` — Gebäude als maßstabsgetreue Seitenansicht.
* `render_map.py map_preview.html` — Welt von oben, eine Plot-Insel in groß
  und ein senkrechter Schnitt von der Mitte bis zur Arena. Mit `--svg ordner/`
  stattdessen die nackten SVGs.
