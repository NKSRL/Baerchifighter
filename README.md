# Bärchi Fighter (RBL)

Roblox-Spiel: Idle-/Gacha-/Kampf-Hybrid im Stil von „Grow a Chicken Fighter",
mit Bärchen statt Hühnern. Bis zu 8 Spieler, jeder auf einer eigenen
Plot-Insel rund um eine gemeinsame Hauptinsel.

Die vollständige Beschreibung — Spielschleife, Weltaufbau, Architektur,
Datenmodell, Balance und offene Punkte — steht im **Context Briefing** im
Claude-Projekt (`claude/CONTEXT_BRIEFING.md`). Diese Datei hier ist nur der
Einstieg zum Starten.

## Loslegen

Place-Datei bauen:

```bash
rojo build -o "RBL.rbxlx"
```

`RBL.rbxlx` in Roblox Studio öffnen, dann den Rojo-Server starten:

```bash
rojo serve
```

Rojo 7.7.0, verwaltet über Aftman (`aftman.toml`). Doku: <https://rojo.space/docs>

**Zwei-Wege-Sync bleibt aus.** Die Dateien hier sind die einzige Wahrheit.
Änderungen, die nur in Studio gemacht werden, gehen verloren oder setzen —
mit Zwei-Wege-Sync — Dateien auf der Festplatte zurück.

## Vor dem Studio-Start und vor jedem Commit prüfen

```bash
cd tools/luau-tests && npm install      # einmalig
node check_syntax.mjs
node run.mjs loc.test.lua
node run.mjs client.test.lua
node run.mjs migration.test.lua
node run.mjs session_lock.test.lua
node run.mjs ../sim/egg_tree_check.lua
node run.mjs ../sim/path_balance.lua
node run.mjs ../sim/fight_timeline.lua
cd ../..
python tools/check_members.py
python tools/check_consistency.py
python tools/check_loc.py
python tools/check_decor.py
```

Was jede Prüfung abdeckt, steht in `tools/README.md`.

## Zwei Dinge, die Studio selbst braucht

* **`MaxPlayers` auf 8 setzen.** `MapConfig.PLOT_COUNT` ist 8; ein neunter
  Spieler bekäme keinen Plot.
* **Bärchi-Meshes** liegen in `src/shared/Assets/` (`BaerchiTemplate.rbxm`;
  ein eigenes Modell je Rarity als `BaerchiTemplate_<Rarity>.rbxm`).
  Roblox übernimmt beim glTF-Import keine Farben ohne Textur — die müssen
  nach dem Import von Hand gesetzt werden.

## Konventionen

`--!strict` in jeder Datei, deutsche Kommentare (das Warum, nicht die
Geschichte), Balance- und Tuning-Zahlen in `Config`-Modulen (reine Geometrie
und Optik als benannte Konstanten am Dateianfang), `Types.luau` und
`Remotes.luau` als einzige Quellen für Datenstrukturen und Remote-Namen.
Ausführlich im Context Briefing.
