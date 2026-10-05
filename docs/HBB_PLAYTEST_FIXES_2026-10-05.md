# Playtest-Feedback 05.10.2026 – umgesetzt

| Rückmeldung | Ursache | Änderung |
| --- | --- | --- |
| UI auf seinem PC sehr klein, in Studio nicht | Alle Panels in festen Pixeln, keine globale Skalierung; großer Monitor = winzig | `UI/UiScale`: ein `UIScale` an der ScreenGui, wächst ab 820 px Höhe bis ×1,6 (nie kleiner). Pixel-Rechner (Guide-Pfeil, fliegende Belohnungen, Index-Popup, MenuBar, PetBar) rechnen über `UiScale.toGui` um. |
| Quest-Knöpfe berühren sich | „Abholen“ endete bei y 102, „Tagesbonus“ begann bei 100 | Karte 124 → 142 hoch, Abstände 6 px, Puls wächst mittig |
| 🏠 statt „Home“ | – | Knopf mit Wort (`ui.home.button`: Heim/Home/Maison/Casa), 104×56 |
| Daily-Bonus leblos | nur Textzeilen | je Tag großes Icon + große Zahl + Extras; heute: goldener Rand + Pulsieren; abgeholt: Haken; Tag 7: Krone + Geschenk |
| Bär-Menü klein | eine schmale Spalte (max. 500 px) | zwei Spalten (bis 920 px): links Identität/Stärker machen, rechts Zustand/Eier/Aktionen; Einzelwerte + Stat-Stufen im Aufklapper (Paket 4) |
| Fusion: 2. Bär nicht wählbar | „⬆ + 🐻“ öffnete das Fusions-Fenster direkt; dort gibt es keine Auswahl | öffnet das Inventar im Fusions-Modus mit diesem Bärchi als A; B antippen, dann „Fusionieren“ |
| Plot-Schild langgezogen, Schrift durch Pfosten | ein Pfosten mitten durchs Brett, Brett 16 breit | Brett 12 breit, zwei Pfosten hinter den Rändern, Leisten oben/unten |
| Händler zu stark (unendlich kaufen und hochpressen) | 5 Basis-Eier (je 50 G) → Zucker-Ei → … | Basis-Eier nicht pressbar (`PRESS_NO_BASIC_EGG`, Regel `EggConfig.canPress`, Test `egg_press.test.lua`) |
| Event-Schrift läuft durch den Mast und springt zwischen 1 und 2 Zeilen | Tafel 16 hoch im 33 hohen Mast; Zeit + Belohnung in einem Text, dessen Breite sich jede Sekunde änderte | Tafel auf 38 (über der Spitze); Titel, Zeit, Belohnung in drei festen Zeilen |
| „Woher kommen GoldGummies?“ | – | schon gelöst: Tages-Quests zeigen „+100 GoldGummies“ |

## Studio-Testschritte
1. Vollbild auf großem Monitor: UI deutlich größer; Guide-Pfeil zeigt genau auf die Kachel; fliegende Gummies landen in der Pille.
2. Quest-Karte: Abholen und Tagesbonus mit Abstand.
3. Daily-Bonus öffnen: Icons, heute pulsiert.
4. Bärchi-Karte: zwei Spalten, „▸ Einzelwerte“ klappt auf; „⬆ + 🐻“ → Inventar im Fusions-Modus, zweiten Bärchi antippen → Fusionieren.
5. Plot-Schild von vorn: Name frei lesbar.
6. Ei-Baum: Basis-Ei hat keinen Presse-Knopf mehr.
7. Event-Tafel über dem Mast, keine springende Zeile.

## Nachtrag: Lauf-Start immer bei Stage 1 (Entscheidung 05.10.)
Vorher startete der Fight-Knopf mit vorhandenem letzten Lauf **ohne Frage ab 65 %** und buchte dafür still Gummies ab (HBB Paket 2).
Jetzt (`FIGHT_RESUME_PROMPT`): Beim Klick erscheint über der Leiste ein kleines Feld „Ab Stage X weiter“ mit Gummi-Kosten und einem 7-Sekunden-Balken.
- Kein Klick → Feld weg, Lauf ab Stage 1.
- „Stage 1“ oder zweiter Fight-Klick → sofort ab Stage 1.
- Nicht bezahlbar → Knopf grau.

Kosten und Start-Stage kommen aus derselben Rechnung wie beim Server (`PitResumeDialog.offer` = `CombatService.getResumeOffer`). Stages schafft man damit durch stärkere Bärchis; der Sprung nach oben ist eine bewusste Entscheidung.
Studio: Lauf bis Stage 10 → zurück → Fight: Feld „Ab Stage 10 weiter“, 7 s warten → Lauf startet bei 1.
