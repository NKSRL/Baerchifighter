# luau-tests — Tests ohne Roblox Studio

Führt Luau-Code mit dem echten Luau-Compiler aus (npm-Paket `luau-web`,
WebAssembly). Braucht nur **Node.js** (ab Version 18).

Einmalig im Ordner `tools/luau-tests`:

    npm install

Dann:

    node check_syntax.mjs               # kompiliert JEDE .luau-Datei, meldet Syntaxfehler
    node run.mjs loc.test.lua           # Tests für Localization/Loc
    node run.mjs client.test.lua        # Rauchtest der Client-UI (Sprachwechsel, Toasts, HUD ...)
    node run.mjs migration.test.lua     # alte Spielstaende (v6, v10, v13) durch die Migration
    node run.mjs session_lock.test.lua  # Sitzungs-Sperre (welcher Server haelt den Spielstand)
    node run.mjs ../sim/egg_tree_check.lua   # Regeln des Ei-Baums
    node run.mjs ../sim/path_balance.lua     # Pfad-Profile
    node run.mjs ../sim/fight_timeline.lua   # Zeitbudget der Kampf-Wiedergabe
    node run.mjs ../sim/pit_balance.lua      # nur Tabelle, keine Pruefung
    node run.mjs ../sim/egg_tree_sim.lua     # nur Tabelle, keine Pruefung

Exit-Code 0 = alles in Ordnung, 1 = ein Test ist gescheitert.

## Was das kann — und was nicht

* `require()` funktioniert wie in Studio (`script.Parent.Parent.Network.Types`,
  `ReplicatedStorage.Config.X`). Die Dateien werden direkt aus `src/` gelesen.
* Roblox selbst gibt es nicht. `Instance`, `UDim2`, `Enum`, `Color3` usw. sind
  durchlässige Attrappen (`mock_roblox.lua`): jedes unbekannte Feld ist ein
  aufrufbares Objekt, gesetzte Eigenschaften (`Text`, `Visible`) merken sie sich.
  Das reicht, um **Logik und Texte** zu prüfen — nicht Layout, Physik oder
  Aussehen.
* `Network/Remotes` wird durch eine Attrappe ersetzt (`mock_remotes.lua`):
  `FireServer`-Aufrufe landen in `FIRED`, Server-Ereignisse löst ein Test aus,
  indem er den registrierten Handler selbst aufruft.
* Die Typprüfung (`--!strict`) macht das **nicht**. Das bleibt Studio.

## Einen eigenen Test schreiben

Siehe `client.test.lua` als Vorlage. Die globalen Hilfen:

* `RS` — der `ReplicatedStorage`-Baum, `CL` — der Client-Baum (`StarterPlayerScripts`),
  `SSS` — der Server-Baum (`ServerScriptService`, nur geladen, nichts gestartet;
  für reine Module wie `Util/PlayerMigration`)
* `CREATED` — Liste aller per `Instance.new` erzeugten Objekte
* `FIRED` — Protokoll der `FireServer`-Aufrufe
* `SetLocale("fr-fr")` — setzt die Roblox-Sprache des Test-Spielers
* `CLOCK` — die Uhr, die `os.clock()` liefert (zum Vorspulen)
* `__log(...)` — Ausgabe; eine Zeile, die mit `FAIL` beginnt, lässt den Lauf scheitern
