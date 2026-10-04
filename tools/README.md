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
    node run.mjs ../sim/egg_tree_check.lua   # Regeln des Ei-Baums
    node run.mjs ../sim/path_balance.lua     # Pfad-Profile (Gold/Kristall/Void)
    node run.mjs ../sim/fight_timeline.lua   # Zeitbudget der Kampf-Wiedergabe
    cd ../..
    python tools/check_members.py
    python tools/check_consistency.py
    python tools/check_loc.py
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
| `migration.test.lua` | Spielstände im Format v6, v10 und v13 laufen durch `PlayerMigration.applyDefaults`, ergeben die Struktur von `Types.PlayerData` und ändern sich beim zweiten Durchlauf nicht mehr |
| `session_lock.test.lua` | `SessionLock`: wann ein Spielstand als von einem anderen Server gehalten gilt |
| `sim/egg_tree_check.lua` | Verteilungen = 100 %, Ø steigt entlang jeder Kante, jeder Bärchi fällt aus einem Ei, jede Fähigkeit hat eine Show, Lege-Fallback landet auf freiem Ei |
| `sim/path_balance.lua` | kein Pfad gewinnt alle drei Ziele (Stärke, Tempo, Seltenheit) |
| `sim/fight_timeline.lua` | ein PIT-Lauf bleibt im Zeitbudget |
| `sim/pit_balance.lua` | Tabelle: erreichbare Stages je Rarity und PIT-Level (keine Prüfung) |
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
* Jeder Service mit `init()` steht in der Startliste.

## `check_loc.py` — Übersetzungen

Hat jede Sprache alle Schlüssel, stimmen die `{platzhalter}`, gibt es jeden im
Code verwendeten Schlüssel? `--todo` listet Texte, die noch fest im Code stehen.

## `check_decor.py` — Geometrie der Gebäude

Prüft `MapConfig.BUILDING_DECOR` / `CENTER_DECOR`: nichts steckt im Boden,
nichts schwebt, Deko bleibt im Grundriss und unter dem Schild.

## Vorschauen

* `render_decor.py decor_preview.html` — Gebäude als maßstabsgetreue Seitenansicht.
* `render_map.py map_preview.html` — Welt von oben, eine Plot-Insel in groß
  und ein senkrechter Schnitt von der Mitte bis zur Arena. Mit `--svg ordner/`
  stattdessen die nackten SVGs.
