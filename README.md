# Bärchi Fighter (RBL)

Roblox-Spiel: Idle-/Gacha-/Kampf-Hybrid im Stil von „Grow a Chicken Fighter",
mit Bärchen statt Hühnern. Bis zu 8 Spieler auf einer gemeinsamen Wiese.

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

## Neuer Rechner / Studio ist neuer als GitHub

Rojo installieren (einmalig, PowerShell im Projektordner):

```powershell
powershell -ExecutionPolicy Bypass -File tools\setup_rojo.ps1
```

Wurde direkt in Studio gearbeitet: In Studio *Datei → Als Datei speichern unter*
→ `RBL.rbxl` in diesen Ordner, dann

```powershell
powershell -ExecutionPolicy Bypass -File tools\sync_from_studio.ps1
```

Das sichert `src/`, schreibt den Studio-Stand per `rojo syncback` zurück, zeigt
die Änderungen und lädt sie nach Rückfrage auf GitHub hoch. Erst danach
`rojo serve` starten — sonst überschreibt Rojo die neueren Studio-Skripte.

## Vor dem Studio-Start prüfen

Im Ordner `tools/` liegen Skripte, die die häufigsten Fehler finden, bevor
Roblox sie beim Laden meldet — falsche Config-Feldnamen, auseinandergelaufene
Gebäude-IDs, schwebende Deko-Teile:

```bash
python3 tools/check_members.py
python3 tools/check_consistency.py
python3 tools/check_decor.py
```

Details und die Syntaxprüfung mit dem offiziellen Luau-Compiler stehen in
`tools/README.md`.

## Zwei Dinge, die Studio selbst braucht

* **`MaxPlayers` auf 8 setzen.** `MapConfig.PLOT_COUNT` ist 8; ein neunter
  Spieler bekäme keinen Plot.
* **Bärchi-Meshes importieren** nach `src/shared/Assets/` als
  `BaerchiTemplate.rbxm` (Standard) bzw. `BaerchiTemplate_<Rarity>.rbxm`.
  Roblox übernimmt beim glTF-Import keine Farben ohne Textur — die müssen
  nach dem Import von Hand gesetzt werden.

## Konventionen

`--!strict` in jeder Datei, deutsche Kommentare, alle Zahlen in `Config`-Modulen,
`Types.luau` und `Remotes.luau` als einzige Quellen für Datenstrukturen und
Remote-Namen. Ausführlich im Context Briefing.
