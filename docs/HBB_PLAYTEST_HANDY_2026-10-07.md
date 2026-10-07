# Playtest 07.10.2026 (Handy) – Knöpfe vs. Touch-Steuerung

Rückmeldung (Freund, Stand **vor** UI-Qualität Schritt 1/2): „Fight- und
Event-Knopf kommen auf dem Handy mit der Steuerung in die Quere.“

## Ursache

Roblox legt auf Touch-Geräten eigene Steuerung unten auf den Bildschirm
(PlayerModule): den Bewegungs-Stick links (reagiert in den linken 40 % der
Breite, untere zwei Drittel) und den Sprung-Knopf unten rechts (70 px auf
kleinen Bildschirmen, 120 px auf großen). Rechnung für ein Handy quer
(844×390):

| Element | lag bei | Konflikt |
|---|---|---|
| Pet-Leiste (Event/Fight), 434 breit, unten mittig | x 205–639 | Event-Knopf zur Hälfte in der Stick-Zone (bis x 338): wer laufen will, schickt den Bärchi zum Event |
| Heim-Knopf, unten links | x 16–120 | komplett in der Stick-Zone |
| Menü-Leiste rechts (auf niedrigen Bildschirmen bis unten gestreckt) | bis y 378 | über dem Sprung-Knopf (x 749–819, y 300–370): Springen öffnete ein Menü |

## Änderung

- **`UI/TouchSafeArea`** (neu): kennt die Zonen der Touch-Steuerung und
  liefert den freien Streifen unten zwischen Stick und Sprung-Knopf
  (`zone`) sowie den Platz, den rechts unten der Sprung-Knopf braucht
  (`rightBottomReserve`). Ohne Touch (PC, Konsole, Tablet mit Tastatur):
  `nil` → alles bleibt wie bisher.
- **Pet-Leiste:** auf Touch im freien Streifen zentriert und passend
  verkleinert (844×390: x 354–733, 87 %).
- **Kampf-Start-Fenster** (über der Leiste) wandert mit der Leiste mit.
- **Heim-Knopf:** auf Touch im freien Streifen über der Pet-Leiste.
- **Menü-Leiste:** endet auf Touch über dem Sprung-Knopf. Würden die
  Kacheln dafür in einer Spalte kleiner als 70 %, werden es zwei Spalten
  (844×390: 2×3 Kacheln, 75 % ≈ 40 px, Ende bei y 279). Am PC unverändert
  einspaltig.

Prüfstand: alles grün (Syntax, `check_locals`, alle Tests, alle `check_*`).

## In Studio bringen (Option B)

Neu: `StarterPlayerScripts/UI/TouchSafeArea` (ModuleScript).
Ersetzen: `StarterPlayerScripts/UI/{PetBar, HomeButton, FightStartPrompt, MenuBar}`.
Achtung: das kommt **zusätzlich** zu den noch nicht hochgeladenen Schritten 1
und 2 (`docs/HBB_UI_QUALITAET_1_TEXTE_2026-10-06.md`,
`docs/HBB_UI_QUALITAET_2_FENSTER_2026-10-07.md`).

## Testschritte

1. Studio → Test → Device-Emulator, Handy quer (z. B. iPhone 14): Event- und
   Fight-Knopf liegen rechts von der Stick-Zone und links vom Sprung-Knopf;
   mit dem Stick laufen, ohne einen Knopf auszulösen.
2. Weit vom Plot weglaufen: Heim-Knopf erscheint über der Pet-Leiste, nicht
   unten links.
3. Menü-Leiste rechts: zwei Spalten, endet über dem Sprung-Knopf; Springen
   öffnet kein Menü.
4. Fight antippen (mit gespeichertem Lauf): das Kampf-Start-Fenster sitzt über
   der Leiste.
5. Emulator aus (PC): alles wie vorher (Leiste mittig, Heim-Knopf unten
   links, Menü einspaltig).
6. Am echten Handy gegenprüfen: die Zonen der Steuerung sind aus dem
   Roblox-Standard nachgebildet, ein abweichendes Gerät kann leicht anders
   liegen.
