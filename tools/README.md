# tools — Prüfungen und Simulationen ohne Studio

Alles hier findet Fehler, bevor Roblox sie beim Start meldet, oder rechnet
Balance nach, ohne das Spiel zu starten. Gebraucht werden Python 3 und die
Luau-CLI in `luau-bin/` (Cloud: SessionStart-Hook, Laptop: `luau-windows.zip`
von https://github.com/luau-lang/luau/releases).

## Vor jedem Commit

    python tools/check_all.py             # alles, ca. 80 s, zeigt nur Rotes
    python tools/check_all.py --schnell   # ohne check_ui (~25 s)
    python tools/check_all.py -v          # auch gruene Zeilen

`check_all.py` laeuft parallel: Syntax aller `.luau` (`luau-compile`),
`check_locals`, alle `check_*.py`, Modulkarte (`make_modulkarte.py --check`),
jeder Test in `luau-tests/` und die Pruef-Sims. Rote Pruefungen, die bewusst
offen sind, stehen in `BEKANNT_ROT` (mit Grund, auch in `docs/STATUS.md`).

## Luau-Tests und Simulationen (`luau-tests/`, `sim/`)

Tests mit `require("../../src/...")` laufen direkt mit `luau`, alle anderen
ueber `luau-tests/run_local.py`: das baut aus `src/shared` und `src/server` ein
Buendel mit Roblox-Attrappen (`rbxRequire`, `RS.Config.X`). Einzeln:

    luau-bin/luau tools/luau-tests/guide_steps.test.lua
    python tools/luau-tests/run_local.py tools/luau-tests/shop.test.lua
    python tools/luau-tests/run_local.py tools/sim/progression_pacing.lua

Die Node-Tests vom Heim-PC (`run.mjs`, `loc.test.lua`, `client.test.lua`,
`migration.test.lua`, `session_lock.test.lua`, `login_bonus.test.lua`) lagen
nie im Repo.

| Sim | prueft / zeigt |
|---|---|
| `sim/egg_tree_check.lua` | Verteilungen = 100 %, Ø steigt entlang jeder Kante, jeder Bärchi fällt aus einem Ei, jede Fähigkeit hat eine Show, Lege-Fallback landet auf freiem Ei |
| `sim/path_balance.lua` | kein Pfad gewinnt alle drei Ziele (Stärke, Tempo, Seltenheit) |
| `sim/fight_timeline.lua` | ein PIT-Lauf bleibt im Zeitbudget |
| `sim/tower_calibration.lua` | Zielwerte der Tower je Rarity |
| `sim/progression_pacing.lua`, `sim/fortschritt_w1.lua` | Pacing-Ziele für 30/90/240 min pro Tag |
| `sim/boss_balance.lua`, `sim/drop_rates_v2.lua`, `sim/comb_respawn.lua` | Boss-Dauer, Drop-Raten, Waben |
| `sim/pit_balance.lua`, `sim/egg_tree_sim.lua`, `sim/power_*.lua`, `sim/pacing_v2_vorschlag.lua` | nur Tabellen/Erkundung, keine Pruefung (nicht in `check_all`; `power_sweep` braucht Minuten) |

Die Typprüfung (`--!strict`) machen diese Tests nicht, das bleibt Studio.

## `make_modulkarte.py` — Modulkarte

Schreibt `docs/ARCHITEKTUR.md` aus den Kopfkommentaren („Einzige
Zustaendigkeit“). Nach neuen oder umbenannten Modulen laufen lassen.

## `make_update_rbxmx.py` — Update-Datei fuer Studio

Ersetzt in Studio nur den Quelltext geaenderter Skripte, loescht nichts.
`STUDIO_VORAUS` haelt Dateien zurueck, die in Studio neuer sind.

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
