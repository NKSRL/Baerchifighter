# Ei-Menü & Ei-Baum (Bilderbuch-Stil) – Cowork-Prompt zum Einbauen

Stand 2026-10-10. Code und Bilder liegen in `main`. Hochgeladen ist noch NICHTS:
alle neuen Bild-IDs in `src/client/UI/Icons.luau` (Tabelle `UI_IDS`) sind leer.
Ohne IDs zeichnet das UI einen einfachen Rückfall (Frames, Farben, Text) und
bleibt voll bedienbar.

Vorschau (Mockups aus den echten PNGs, keine Studio-Screenshots):
`docs/preview_ei_ui/` (1 PC, 2 drei Knoten-Zustände, 3 Freischalt-Animation,
4 Ei-Fenster + MenuBar-Kachel, 5 Handy 844×390, 6 ganzer Baum).

## Was sich geändert hat

| Datei im Repo | Ort in Studio | Art |
|---|---|---|
| `src/client/UI/EggIcon.luau` | StarterPlayer › StarterPlayerScripts › UI › EggIcon | ModuleScript, ersetzt |
| `src/client/UI/EggTreePanel.luau` | … › UI › EggTreePanel | ModuleScript, ersetzt |
| `src/client/UI/EggTreeLayout.luau` | … › UI › **EggTreeLayout** | ModuleScript, **NEU** |
| `src/client/UI/HatchPanel.luau` | … › UI › HatchPanel | ModuleScript, ersetzt |
| `src/client/UI/MenuBar.luau` | … › UI › MenuBar | ModuleScript, ersetzt |
| `src/client/UI/Theme.luau` | … › UI › Theme | ModuleScript, ersetzt |
| `src/client/UI/Icons.luau` | … › UI › Icons | ModuleScript, ersetzt (hier kommen die IDs rein) |
| `src/shared/Modules/EggLook.luau` | ReplicatedStorage › Modules › EggLook | ModuleScript, ersetzt |
| `src/shared/Localization/Strings/de/en/fr/es.luau` | ReplicatedStorage › Localization › Strings › de/en/fr/es | ModuleScripts, ersetzt |

Bilder: `assets/ui/eggs/` (21 Eier + `egg_mask`), `assets/ui/tree/` (Stamm,
Äste, Kelche, Schloss, Hintergrund), `assets/ui/fx/` (Lichtkränze, Funke,
Pollen, Honiglicht), `assets/ui/frames/` (9-Slice-Rahmen, Siegel, Sockel) –
zusammen 48 PNGs. Neu zeichnen: `python tools/art/render_eggs.py` und
`python tools/art/render_ui.py` (Blender als `pip install bpy`).

## Freischalt-Animation testen

Im Play-Test von Studio die Befehlsleiste auf **Client** stellen
(Registerkarte Test → „Aktuell: Server“ anklicken, bis „Client“ steht) und eingeben:

```lua
game.Players.LocalPlayer:SetAttribute("EggTreeTestUnlock", "GoldenEgg")
```

Der Baum öffnet sich und spielt Welle → Blüte → Sprung → Funkenring für das Ei.
Alternativ bei offenem Ei-Baum die Taste **U** drücken: Dann läuft die Animation
für den gewählten Knoten. Beides funktioniert nur in Studio. Im echten Spiel
läuft die Animation von selbst, wenn ein Knoten frei wird, und wenn der Baum
dabei zu war, beim nächsten Öffnen.

---

## Prompt für Cowork (kopieren)

```text
Du arbeitest an meinem Roblox-Spiel "Honey Bear Brawl" (Bärchi-Spiel). Das
Git-Repo ist mein Ordner "Baerchifighter" auf diesem Laptop, die Spielstätte
ist in Roblox Studio geöffnet bzw. öffnest du sie über "Zuletzt verwendet".
Lies zuerst im Repo CLAUDE.md und docs/HBB_COWORK_EI_UI_PROMPT.md (Tabelle
"Was sich geändert hat"). Arbeite die Schritte der Reihe nach ab und mach nach
jedem Schritt einen kurzen Haken in deiner Antwort.

1. REPO AKTUALISIEREN
   Im Ordner Baerchifighter: `git checkout main` und `git pull`. Prüfe, dass
   docs/preview_ei_ui/ und assets/ui/eggs/BasicEgg.png existieren.

2. SICHERUNG
   In Studio: Datei → "Kopie speichern unter…" als
   Baerchifighter_vor_EiUI_<Datum>.rbxl auf den Desktop.
   Rechtsklick auf ReplicatedStorage › Assets › BaerchiTemplate → "Als Datei
   speichern" nach Baerchifighter/src/shared/Assets/BaerchiTemplate.rbxm
   (sonst löscht Rojo das Modell, siehe CLAUDE.md).

3. CODE IN STUDIO BRINGEN
   Wenn Rojo installiert ist (`rojo --version`): `rojo serve` im Repo starten
   und im Studio-Rojo-Plugin verbinden. Sonst von Hand: für jede Zeile der
   Tabelle in docs/HBB_COWORK_EI_UI_PROMPT.md das Skript in Studio öffnen,
   den Inhalt komplett durch den Inhalt der Datei aus dem Repo ersetzen.
   EggTreeLayout ist NEU: in StarterPlayer › StarterPlayerScripts › UI einen
   ModuleScript "EggTreeLayout" anlegen und den Dateiinhalt einfügen.
   Danach im Ausgabefenster nach roten Fehlern suchen.

4. TEST OHNE BILDER (Rückfall)
   Play drücken. Prüfen: Ei-Fenster (MenuBar-Kachel "Eier") und Ei-Baum (Kachel
   "Ei-Baum" oder Knopf im Ei-Fenster) öffnen sich ohne Fehler, Knoten lassen
   sich antippen, Zoom-Knöpfe +, −, ↺ funktionieren. Ausgabe auf Fehler prüfen.
   Stop.

5. BILDER HOCHLADEN
   Studio → Ansicht → Asset Manager → "Bulk Import". Alle 48 PNGs aus
   Baerchifighter/assets/ui/eggs, assets/ui/tree, assets/ui/fx und
   assets/ui/frames hochladen (Typ Image). Warte, bis alle durch die
   Moderation sind (kein Uhr-Symbol mehr). Sollte ein Bild abgelehnt werden:
   melde mir den Namen und mach mit den anderen weiter.

6. IDS EINTRAGEN
   Für jedes hochgeladene Bild im Asset Manager: Rechtsklick → "ID kopieren".
   Trag die ID im Repo in src/client/UI/Icons.luau in der Tabelle UI_IDS ein:
   Schlüssel = Ordner/Dateiname ohne .png, Wert = "rbxassetid://<ID>".
   Beispiel: ["eggs/BasicEgg"] = "rbxassetid://1234567890",
   Achtung: "tree/lock" ist das NEUE Schloss; der alte Eintrag `lock` in der
   Tabelle IDS bleibt unverändert. Keine anderen Zeilen ändern, nichts löschen.
   Danach im Repo prüfen, dass kein Eintrag in UI_IDS mehr "" ist, und
   `luau-compile --null src/client/UI/Icons.luau` laufen lassen, falls der
   luau-CLI da ist. Das neue Icons.luau in Studio übernehmen (Rojo macht das
   automatisch, sonst Inhalt einfügen wie in Schritt 3).

7. TEST MIT BILDERN + SCREENSHOTS
   Play drücken und Screenshots machen (Ablage: Baerchifighter/docs/studio_ei_ui/):
   a) Ei-Baum ganz (Knopf ↺), PC-Fenster, darin sichtbar: gesperrte Knoten
      (dunkle Silhouette + Schloss), freischaltbare (Honigkelch, Ei pulsiert,
      Licht kriecht den Ast entlang) und freigeschaltete (offene Blüte).
   b) Maus über einem Knoten: Infokarte.
   c) Freischalt-Animation: Befehlsleiste auf "Client" stellen und
      game.Players.LocalPlayer:SetAttribute("EggTreeTestUnlock", "GoldenEgg")
      ausführen, 2–3 Screenshots während der Animation.
   d) Ei-Fenster mit mindestens zwei Eiern im Lager (Eier auf Sockeln,
      "Öffnen"-Siegel) und die MenuBar-Kachel "Eier".
   e) Handy: Test → Gerät → iPhone 14 (quer, 844×390) wählen, Ei-Baum öffnen,
      einen Knoten antippen (Detail-Karte mit X), Screenshot; dazu einmal
      das Ei-Fenster.
   Schau dir jeden Screenshot an und vergleiche mit docs/preview_ei_ui/. Melde
   mir Abweichungen (verrutschte Rahmen, abgeschnittene Texte, fehlende Bilder,
   Fehler in der Ausgabe). Kleine Lage-Korrekturen darfst du selbst machen
   (z. B. Positionen in EggTreeLayout.luau), große nicht.

8. MEIN OK ABHOLEN
   Zeig mir die Screenshots aus Schritt 7 und warte auf mein OK, bevor du
   speicherst.

9. SPEICHERN UND EINCHECKEN
   Studio: Datei → "Auf Roblox speichern". Im Repo: `git checkout -b
   ei-ui-ids`, dann `git add src/client/UI/Icons.luau docs/studio_ei_ui` und
   `git commit -m "Ei-UI: Asset-IDs eingetragen + Studio-Screenshots"`, dann
   `git push -u origin ei-ui-ids`. Sag mir, wenn das durch ist. Auf main merge
   ich das dann selbst oder lass es Claude machen.
```
