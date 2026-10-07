# Auftrag für Claude Cowork: Studio-Stand sichern und ins Repo exportieren

Du steuerst meinen Windows-PC. Hintergrund: Mein Roblox-Studio-Ort enthält
Code, der nicht im Git-Repo ist (z. B. `IncubatorService`, `IncubatorPanel`).
Das letzte Update (`updates/HBBUpdate.rbxmx`) hat deshalb Studio-Fassungen
überschrieben, und der Test brach mit Fehlern ab. Jetzt soll (1) der Stand
**vor** dem Update wiederhergestellt und (2) dieser Stand als lesbare Datei
ins Repo geschoben werden, damit Claude Code beides zusammenführen kann.

## Regeln

1. **Kein Rojo** (nicht verbinden, nicht `rojo serve`).
2. **Nicht auf Roblox speichern, nicht veröffentlichen.**
3. Nichts in Studio verändern — wir exportieren nur.
4. Keine Git-Befehle, die etwas verwerfen (`reset --hard`, `checkout -- .`,
   `clean`, `push --force`).
5. Bei Fehlern oder Unklarheit: anhalten und berichten (Text + Screenshot).

## Schritt 1 – Fehler vom letzten Test sichern (falls noch sichtbar)

Ist Studio mit dem Update-Stand noch offen und das Ausgabe-Fenster zeigt die
roten Fehler vom Test: **alle roten Zeilen samt den darunterliegenden
„Stack“-Zeilen kopieren** und in eine Textdatei speichern:
`Dokumente\Neuer Ordner\RBL\studio_export\Fehler_Test_2026-10-08.txt`
(Ordner `studio_export` anlegen, falls er fehlt). Sind die Fehler nicht mehr
sichtbar, diesen Schritt überspringen.

## Schritt 2 – Update-Stand verwerfen

Studio **schließen**. Fragt Studio nach dem Speichern: **„Nicht speichern“**.

## Schritt 3 – Sicherheitskopie öffnen und als XML speichern

1. In Studio: **Datei → Aus Datei öffnen** →
   `Dokumente\Claude Downloads\Backup_vor_HBBUpdate_2026-10-08.rbxl`.
2. Kurz prüfen, dass es der Stand **vor** dem Update ist: Im Explorer unter
   `StarterPlayer > StarterPlayerScripts > UI` darf es **kein**
   `TouchSafeArea` geben. Gibt es eins: anhalten und berichten.
3. **Datei → Speichern unter… / „Save to File As…“** →
   Ordner `Dokumente\Neuer Ordner\RBL\studio_export\`,
   Dateiname `Studio_Stand_2026-10-08`,
   **Dateityp „Roblox XML Place Files (*.rbxlx)“** (wichtig: rbxl**x**, nicht rbxl).
4. Studio schließen (nichts weiter speichern).

## Schritt 4 – Ins Repo schieben

Git Bash / PowerShell:

```bash
cd "$HOME/Documents/Neuer Ordner/RBL"
git status
git switch claude/trusting-albattani-or20rj
git pull
git add studio_export
git commit -m "Studio-Stand 08.10. (vor HBBUpdate) als rbxlx exportiert"
git push
```

- Zeigt `git status` vorher andere geänderte Dateien als `studio_export/`:
  diese **nicht** mit committen, nur `studio_export` hinzufügen (wie oben).
- Meldet `git push` einen Fehler (z. B. Datei zu groß, > 100 MB, oder keine
  Berechtigung): anhalten und die Meldung berichten.

## Schritt 5 – Bericht

Schick mir: die Ausgabe von `git push`, die Dateigröße der `.rbxlx`, und ob
`Fehler_Test_2026-10-08.txt` dabei ist. Danach nichts weiter tun.

## Danach (macht Claude Code)

Claude Code liest die `.rbxlx`, vergleicht jedes Skript mit dem Repo, übernimmt
alles, was nur in Studio existiert (Inkubator usw.), ins Repo, führt es mit den
UI-Änderungen zusammen und baut eine neue `updates/HBBUpdate.rbxmx`, die keine
Studio-Arbeit mehr überschreibt.
