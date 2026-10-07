# Auftrag für Claude Cowork: UI-Update in Roblox Studio einspielen (ohne Rojo)

Du steuerst meinen Windows-PC. Ziel: die neuen Skripte aus dem Git-Branch
`claude/trusting-albattani-or20rj` in meinen Roblox-Studio-Ort „Grow a Baerchi“
einspielen, **ohne dass irgendetwas in Studio verloren geht**. Arbeite die
Schritte der Reihe nach ab und halte dich an die Regeln.

## Regeln (wichtig, nicht verhandelbar)

1. **Niemals Rojo benutzen.** Kein `rojo serve`, kein Klick auf „Connect“ im
   Rojo-Plugin. Rojo hat am 08.10. Inhalte in Studio gelöscht (den Inkubator).
2. **Nichts in Studio löschen** außer dem Hilfsordner `HBBUpdate`, den der
   Einspiel-Befehl selbst entfernt.
3. **Nicht veröffentlichen** („Publish to Roblox“ / „Auf Roblox veröffentlichen“)
   und **nicht „Auf Roblox speichern“**, bevor ich es ausdrücklich bestätigt habe.
4. **Bei jeder Fehlermeldung oder Unklarheit anhalten** und mir berichten
   (Screenshot + Text), statt etwas auszuprobieren.
5. Keine Git-Befehle, die etwas verwerfen (`reset --hard`, `checkout -- .`,
   `clean`, `push --force`).

## Schritt 1 – Git: neuesten Stand holen

In der Git Bash oder PowerShell im Projektordner (`Dokumente\Neuer Ordner\RBL`
— falls dort kein Git-Repo ist, frag mich nach dem richtigen Ordner):

```bash
cd "$HOME/Documents/Neuer Ordner/RBL"
git status
```

- Zeigt `git status` geänderte Dateien („Changes not staged“ o. ä.): **anhalten
  und mir die Liste zeigen.**
- Sonst weiter:

```bash
git fetch origin
git switch claude/trusting-albattani-or20rj
git pull
git log --oneline -1
```

Prüfen: Im Ordner gibt es jetzt `updates\HBBUpdate.rbxmx` und
`updates\HBBUpdate_Befehl.lua`. Fehlen sie: anhalten und berichten.

## Schritt 2 – Studio öffnen und Ausgangslage prüfen

1. Roblox Studio öffnen und den Ort „Grow a Baerchi“ **von Roblox** öffnen
   (Startseite → Meine Spiele), nicht eine lokale Datei.
2. Prüfen, dass der **Inkubator** wieder da ist (ich habe Version 112
   wiederhergestellt). Suche im Explorer (Ansicht → Explorer) nach „Inkubator“
   bzw. „Incubator“ (Suchfeld oben im Explorer). **Notiere den vollständigen
   Pfad**, z. B. `Workspace > … > Inkubator`. Findest du ihn nicht: anhalten
   und berichten.
3. Sicherheitskopie: **Datei → Kopie speichern unter… / „Save to File As…“**
   → `Dokumente\Neuer Ordner\Backup_vor_HBBUpdate_<Datum>.rbxl`.
4. Prüfen, dass das Ausgabe-Fenster offen ist (Ansicht → Ausgabe / Output).

## Schritt 3 – Update-Datei einfügen

1. Im Explorer **Rechtsklick auf „Workspace“ → „Aus Datei einfügen…“ /
   „Insert from File…“**.
2. Datei wählen: `Dokumente\Neuer Ordner\RBL\updates\HBBUpdate.rbxmx`.
3. Prüfen: Unter Workspace erscheint ein Ordner **`HBBUpdate`** (darin
   `ReplicatedStorage`, `ServerScriptService`, `StarterPlayerScripts`).

## Schritt 4 – Einspiel-Befehl ausführen

1. Befehlsleiste öffnen: Reiter **Ansicht → Befehlsleiste** („Command Bar“),
   erscheint unten.
2. Den kompletten Inhalt von `updates\HBBUpdate_Befehl.lua` (eine lange Zeile)
   in die Befehlsleiste kopieren und **Enter** drücken.
3. Im Ausgabe-Fenster muss am Ende stehen:
   `HBBUpdate: 51 Skripte ersetzt, … neu angelegt, nichts geloescht`
   (die Summe aus „ersetzt“ + „neu angelegt“ ist 51; neu angelegt werden
   mindestens `Names`, `WorldText`, `TouchSafeArea`).
4. Der Ordner `HBBUpdate` im Workspace ist danach verschwunden.
5. Gelbe Warnungen `HBBUpdate: andere Skript-Art …` oder rote Fehler: **anhalten
   und mir den genauen Text schicken.** (Rückgängig: Strg+Z.)

## Schritt 5 – Testen (ohne zu speichern)

1. Prüfen, dass der Inkubator noch an derselben Stelle ist wie in Schritt 2.
2. **Play** (F5) drücken, ca. 20 Sekunden warten.
3. Ausgabe-Fenster: alle **roten** Zeilen kopieren. Wenn es rote Zeilen gibt:
   Stop drücken und mir alles schicken.
4. Kurzer Rundgang, je ein Screenshot:
   - Bärchi anklicken → Bärchi-Karte (Name oben im farbigen Balken, X oben rechts).
   - Eier-Menü, Charms, ein Gebäude-Menü, Ei-Baum.
   - Sprache auf Französisch stellen (Globus-Knopf links oben), ein Menü öffnen:
     keine deutschen Wörter mehr.
   - Arena-Tafel / Event-Tafel in der Welt ansehen.
5. Handy-Test: **Stop**, dann Reiter **Test → Gerät** (Device-Emulator) auf ein
   Handy quer stellen (z. B. iPhone 14), wieder **Play**: Event- und
   Fight-Knopf liegen rechts von der Laufsteuerung (links) und links vom
   Sprung-Knopf; Menü-Leiste rechts zweispaltig, endet über dem Sprung-Knopf.
   Screenshot machen. Danach Emulator wieder aus.
6. **Stop** drücken.

## Schritt 6 – Bericht an mich

Schick mir:
- die Ausgabe von Schritt 4 (Zeile „HBBUpdate: …“),
- alle roten Fehler aus Schritt 5 (oder „keine“),
- die Screenshots,
- den Pfad des Inkubators aus Schritt 2.

Dann **warten**. Speichern auf Roblox erst, wenn ich „speichern“ sage —
dann: Datei → Auf Roblox speichern (nicht veröffentlichen).

## Falls etwas schiefgeht

- Direkt nach dem Befehl: **Strg+Z** macht den Einspiel-Schritt rückgängig.
- Später: Studio schließen **ohne zu speichern** und den Ort neu öffnen, oder
  die Sicherheitskopie aus Schritt 2 öffnen.
- Auf create.roblox.com → Spiel → Configure → Places → Ort → Version History
  liegen alle früheren Versionen (Restore löscht nichts).
