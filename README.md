# Bärchi Fighter (RBL)

Roblox-Spiel: Idle-/Gacha-/Kampf-Hybrid im Stil von „Grow a Chicken Fighter",
mit Bärchen statt Hühnern. Bis zu 8 Spieler, jeder auf einer eigenen
Plot-Insel rund um eine gemeinsame Hauptinsel.

- Stand und offene Punkte: `docs/STATUS.md`
- Architektur und Modulkarte: `docs/ARCHITEKTUR.md`
- Alle Berichte: `docs/INDEX.md`
- Arbeitsregeln (auch für Claude Code): `CLAUDE.md`

Das ausführliche Context Briefing liegt im Claude-Projekt auf claude.ai
(nicht im Repo).

## Prüfen

```bash
python tools/check_all.py
```

Braucht Python 3 und die Luau-CLI in `luau-bin/` (Download siehe `CLAUDE.md`).
Was jede Prüfung abdeckt, steht in `tools/README.md`.

## In Studio bringen

```bash
python tools/make_update_rbxmx.py <seit-commit>
```

Dann `updates/HBBUpdate.rbxmx` in Studio importieren und
`updates/HBBUpdate_Befehl.lua` in die Befehlsleiste. **Kein `rojo serve`**:
Rojo löscht alles, was nur in Studio existiert. Studio ist für Modelle und
Assets die Quelle, das Repo für den Quelltext.

## Zwei Dinge, die Studio selbst braucht

* **`MaxPlayers` auf 8 setzen.** `MapConfig.PLOT_COUNT` ist 8; ein neunter
  Spieler bekäme keinen Plot.
* **Bärchi-Meshes** liegen in Studio unter `ReplicatedStorage/Assets`.
  Roblox übernimmt beim glTF-Import keine Farben ohne Textur — die müssen
  nach dem Import von Hand gesetzt werden.
