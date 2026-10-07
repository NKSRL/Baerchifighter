# UI-Qualität, Schritt 2: Fenster passen auf jeden Bildschirm (07.10.2026)

Vorgänger: `docs/HBB_UI_QUALITAET_1_TEXTE_2026-10-06.md`.

## Das Problem

Große Bildschirme waren seit dem Playtest 05.10. gelöst (`UI/UiScale`, wächst
bis ×1,6). Kleine Bildschirme nicht: jedes Fenster hat eine Mindestgröße in
Pixeln, und die war oft **größer als der Bildschirm**. Ein Handy quer hat ohne
Topbar rund 350 px Höhe:

| Fenster | Mindesthöhe | auf ~350 px |
|---|---|---|
| Charms, Kampf/Tower, Bestenliste | 420 | Kopf und Schließen-X außerhalb |
| Bärchi-Karte, Gebäude | 400 | abgeschnitten |
| Ei-Baum | 360 | knapp abgeschnitten |
| Shop, Quests, Eier, Fusion, Profil, Inventar | 300–340 | passt knapp / gerade so |

Dazu: das Schließen-X war 34×30 (Gebäude: 32×28) — auf dem Handy leicht
daneben getippt. Und die Bärchi-Karte hatte als einziges Menü eine eigene
Hülle ohne Kopfzeile und ohne X oben.

## Was jetzt gilt

1. **`Theme.dialog` passt sich an:** ein `UIScale` „FitScale“ am Fenster
   verkleinert es gleichmäßig, bis es in 94 % des Bildschirms passt (bei
   Größenänderung sofort neu). Das Layout bleibt wie gebaut, es wird nur
   kleiner — nichts wird abgeschnitten, nichts überlappt neu. Auf normalen
   Bildschirmen ist der Faktor 1 (keine Änderung). Wirkt auf alle 16 Fenster.
2. **`Theme.closeButton`:** sichtbares X 40×34 plus unsichtbare Trefferfläche
   52×52. Benutzt von `Theme.dialogHeader` (alle Fenster) und dem
   Gebäude-Menü.
3. **Bärchi-Karte auf `Theme.dialog`:** Name in der Kopfzeile, X oben rechts,
   der Titelbalken trägt die Rarity-Farbe (früher ein schmaler Streifen). Die
   P1-Ausnahme aus Schritt 1 ist weg.
4. **`Theme.dialogScale(gui)`:** für Code, der Bildschirm-Pixel in eine
   Position innerhalb eines Fensters zurückrechnet. `IndexView` (Popup neben
   der Index-Kachel) benutzt ihn — sonst säße das Popup auf dem Handy daneben.
5. **`check_ui.py` Regel P3:** Schließen-Knöpfe nur über `Theme.closeButton`.

Prüfstand: alles grün (Syntax, `check_locals` max. 191, alle Tests und Sims,
alle `check_*`). Gegenprobe P3 mit einem eingebauten „X“-Knopf: gemeldet.

## In Studio bringen (Option B)

Ersetzen: `StarterPlayerScripts/UI/{Theme, BaerchiPanel, BuildingPanel,
IndexView}`. (Werkzeuge: `tools/check_ui.py`, `tools/README.md`.)

## Studio-Testschritte

1. Test → Gerät (Device-Emulator) „iPhone“ quer: Charms, Kampf/Tower,
   Bestenliste, Bärchi-Karte, Gebäude, Ei-Baum öffnen — jedes Fenster ganz
   sichtbar, Kopfzeile und X erreichbar.
2. Zurück auf Desktop-Größe: Fenster wieder in voller Größe (kein Rest-Faktor).
3. Studio-Fenster während ein Menü offen ist kleiner/größer ziehen: das
   Fenster passt sich sofort an.
4. Bärchi-Karte: Name oben im farbigen Balken (Farbe = Rarity), X schließt.
5. Inventar → Index → Kachel antippen (auch im Handy-Emulator): Popup sitzt
   neben der Kachel.
6. X knapp daneben antippen (Handy): schließt trotzdem.

## Nächster Schritt (3)

UI-Prüfstand in Studio: öffnet jedes Fenster in jeder Sprache und meldet
automatisch abgeschnittenen Text (`TextFits`), Elemente außerhalb des
Fensters, Überlappungen und zu kleine Knöpfe — damit der Device-Emulator-Test
nicht mehr von Hand durchgeklickt werden muss.
