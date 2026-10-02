# BÄRCHI FIGHTER — Promotion-, Charm- und Rarity-Stat-System (Opus-Auftrag)

> **Wie du das benutzt:** Kopiere dieses ganze Dokument in eine neue Claude-Session mit
> Modell **Opus** und Zugriff auf den Ordner `C:\Users\youpa\Documents\Claude Downloads\RBL`.
> Dieses Dokument ist ein ERSTER ENTWURF — der Projektinhaber hat drei Referenz-Screenshots
> aus einem anderen Spiel gezeigt und daraus in eigenen Worten beschrieben, was er für
> Bärchi Fighter will. Einiges daraus ist eindeutig, einiges ist eine begründete Annahme
> (siehe Abschnitt 7 "Offene Fragen"). **Bevor Opus zu bauen beginnt: dieses Dokument noch
> einmal mit dem Projektinhaber durchgehen und die offenen Fragen klären** — das ist der
> ganze Sinn dieses separaten Vorlauf-Dokuments, es soll NICHT blind umgesetzt werden.
>
> Nach Klärung: in Studio testen (`rojo build`/`rojo serve`), Abschlussbericht nach dem
> Vorbild von `claude/SCHRITT2_ABGESCHLOSSEN.md` bzw. `claude/TEIL_D_ABGESCHLOSSEN.md`.

---

## 1. Worum es geht

Der Projektinhaber will drei neue, zusammenhängende Bärchi-Systeme, die es heute noch gar
nicht gibt, angelehnt an drei Screenshots aus einem anderen Roblox-Spiel (nicht Bärchi
Fighter — nur Referenz für die UI-Idee, keine Zahlen daraus 1:1 übernehmen, siehe Abschnitt
7):

1. **Rarity-abhängige Stat-Obergrenzen** — jeder einzelne Stat eines Bärchis (HP, ATK, SPD,
   PWR) hat eine eigene, von der Rarity abhängige Obergrenze, und wächst innerhalb dieser
   Grenze durch Teilnahme an Map-Events (siehe Feature 1).
2. **Promotion-System** — einen Bärchi mit Duplikaten "befördern" (10 Stufen, als 5 Sterne
   dargestellt), schaltet dabei auch die Battle-Charm-Slots frei.
3. **Battle-Charms** — 8 Ausrüstungs-Plätze pro Bärchi für zufällig gewürfelte Boni,
   freigeschaltet über den Promotion-Fortschritt.
4. **Neue Fusions-Regeln** — Basiswerte und Stat-Level werden bei einer Fusion künftig
   Stat für Stat gemischt (immer das Bessere), UND der Spieler bekommt ein neues
   Fusions-Menü, in dem er eine von drei Eigenschaften (Ability/Level/Eier) gezielt von
   einem der beiden Eltern-Bärchis "sperren" kann (siehe Feature 4).

Das ist eine ZUSÄTZLICHE Progressions-Ebene oben auf dem bestehenden Level/XP-System
(`HoneyService`, siehe `claude/CONTEXT_BRIEFING.md`/frühere Dokumente) — Honig-Füttern bleibt
der Weg, wie ein Bärchi von Level 1 bis zu seinem Level-Cap wächst. Promotion und Charms sind
ein zweiter, unabhängiger Fortschritt, der zusätzliche Duplikate bzw. GoldGummies verbraucht
(**"Charm Dust" ist KEINE eigene dritte Währung** — siehe Feature 3 und Abschnitt 7, Punkt 4:
der Projektinhaber will das Ressourcen-System bewusst einfach halten, Charm-Rolls kosten
direkt GoldGummies).

**Wichtiger Rahmen für den gesamten Auftrag:** der Projektinhaber will zuerst ein stehendes
Basis-Spiel für diese drei/vier Features, KEIN ausgebautes Extra-AFK-System um die Events
herum — das kommt laut eigener Aussage später als eigener, separater Auftrag. Wo unten "so
einfach wie möglich" steht, ist das wörtlich gemeint: lieber eine schlichte, robuste
Version bauen, die sich später erweitern lässt, statt vorzugreifen.

---

## 2. Referenz-Screenshots — Klartext-Beschreibung

Der Projektinhaber hat drei Bilder gezeigt (liegen NICHT in diesem Repo, hier so genau wie
möglich in Worten beschrieben, damit Opus sie nicht braucht):

**Bild 1 — Bärchi-Detailkarte ("Eclipse Hen"-Beispiel aus dem Fremdspiel):**
Kopfzeile mit Name, Rarity-Badge ("Secret") und Level ("LVL 121"). Darunter "PROMOTIONS": 5
Sterne, alle fünf ausgefüllt/schwarz gefärbt (dieser Beispiel-Bärchi ist maximal befördert).
Darunter "BATTLE CHARMS": 8 sechseckige Slot-Icons nebeneinander, jedes mit einem
Rarity-Buchstaben (L=Legendary, U=Uncommon, C=Common) beschriftet — im Beispiel: L U C U C
C C L. Darunter 6 Stat-Zeilen als Balken mit Fortschrittszahl rechts:
HP `34.8M` (19/31), ATK `3.4M` (20/31), SPD `+14%` (17/31), PWR `+17%` (24/31), EGG `7m 48s`
(17/31), SKILL `Black Sun Cataclysm` (Text, kein Balken). Darunter drei Knöpfe: Ausrüsten
("Active"), Fusionieren ("Fuse"), Befördern ("Promote").

**Bild 2 — Battle-Charms-Popup:** Zeigt dieselben 8 Slots (I–VIII) oben, darunter eine
Tabelle "PROMOTION TIERS" — pro Zeile: Slot-Nummer (I–VIII), ein Rarity-Icon, ab welcher
Sterne-Zahl der Slot freigeschaltet wird, und welcher Bonus dort sitzt:

| Slot | Rarity-Icon | Freischaltung | Bonus |
|---|---|---|---|
| I   | L (Legendary) | von Anfang an aktiv | Crit DMG Boost +8% |
| II  | U (Uncommon)  | ab 2★ | Crit RES Boost +2.2% |
| III | C (Common)    | ab 4★ | Movement Speed +0.2 |
| IV  | U (Uncommon)  | ab 6★ | DMG Reduction +2.3% |
| V   | C (Common)    | ab 8★ | Ability Boost +1% |
| VI  | C (Common)    | ab 8★ | HP Boost +1.4% |
| VII | C (Common)    | ab 10★ | Ability Boost +1% |
| VIII| L (Legendary) | ab 10★ | ATK Boost +6.5% |

Unten: Bestand einer neuen Ressource "Charm Dust" (`11.59K`), ein Knopf "Roll Charms"
(kostet 20 Charm Dust) und ein Knopf "Auto Roll".

**Bild 3 — Charm-Odds-Erklärung:** "Rolling spends Charm Dust and rerolls every slot you
have not locked. Each slot rolls a rarity, then a stat." Darunter eine feste
Wahrscheinlichkeits-Tabelle für die Rarity, die ein Rolls in einem Slot ergibt: Common 49.8%,
Uncommon 26.9%, Rare 17.9%, Super Rare 4.3%, Legendary 1.0%, Ascended 0.1%.

---

## 3. Feature 1 — Rarity-abhängige Stat-Obergrenzen

Der Projektinhaber hat das für unser Spiel EXPLIZIT festgelegt (keine Annahme, das sind
seine eigenen Zahlen):

| Rarity | Stat-Cap-Stufe |
|---|---|
| Common | 8 |
| Uncommon | 12 |
| Rare | 16 |
| Epic | 20 |
| Legendary | 24 |
| Mythic | **offen — siehe Abschnitt 7** |

Wichtig: das ist NICHT `BaerchiConfig.MAX_LEVEL` (aktuell fix 50 für alle Rarities) — die
Formulierung "das soll mit jedem Stat so gehandhabt werden" bedeutet: **jeder einzelne Stat**
(HP, ATK, SPD, PWR — siehe Abschnitt 7 zur genauen Abgrenzung) bekommt eine EIGENE, von
dieser Tabelle abhängige Obergrenze, unabhängig vom allgemeinen Bärchi-Level-Cap.

**Wie ein einzelner Stat innerhalb seiner Obergrenze wächst (jetzt geklärt):** NICHT über
Honig-Füttern, sondern über **Teilnahme an Map-Events** — also über das bereits bestehende
Event-Pit-System in der Weltmitte (`EventService.luau`/`MapConfig.EVENT_PIT_*`, siehe
`claude/SPAWN_UND_EVENT_PIT_2026-09-08.md`). Das ist ein wichtiger Anschlusspunkt: das
Event-Pit hat bisher AUSDRÜCKLICH KEINE Spielauswirkung (siehe Kopf-Kommentar
`EventConfig.luau`: "Ein Event hat aktuell keine spielerische Auswirkung, nur einen Look und
einen Timer" und `EventService.getActive()`, das "aktuell niemand liest"). Dieser Auftrag ist
also der erste Ort, an dem `EventService.getActive()` tatsächlich etwas bewirkt.

**Teilnahme-Mechanik (jetzt vom Projektinhaber konkret festgelegt, keine Annahme mehr):**
Teilnahme ist eine EXPLIZITE Spieler-Aktion, kein passives AFK-Dabeisein. Ein neuer GUI-Knopf
("Send to Event" o.ä.) schickt den ausgerüsteten Bärchi in die Mitte der Map, in die
Event-Area (das bestehende Event-Pit). Solange ein Bärchi dort steht UND ein Event aktiv ist
(`EventService.getActive()` nicht nil), "tut" der Bärchi dort — je nach Event-Typ verschiedene
Dinge — die für den Event-Reward sorgen. Das bedeutet konkret für die Umsetzung:
  - `EventConfig.EventDef` braucht pro Event-Typ eine Definition, WELCHE Aktion der Bärchi
    ausführt (z.B. rein kosmetisch/als Idle-Animation reicht für diesen Auftrag — Hauptsache
    der Spieler sieht, dass sein Bärchi aktiv am Event teilnimmt) und welcher Stat-Fortschritt
    dabei anfällt.
  - Serverseitig prüft ein neuer Teil von `EventService` (oder ein neuer, kleiner
    `EventParticipationService`), ob der Bärchi tatsächlich in der Event-Area steht (Position
    bzw. ein serverseitig gesetztes "ist im Event"-Flag, NICHT nur Client-Meldung — sonst
    ließe sich der Fortschritt clientseitig fälschen) und zählt währenddessen den
    Stat-Fortschritt hoch, begrenzt durch die Rarity-Obergrenze aus der Tabelle oben.
  - Wie viel Stat-Fortschritt pro Event-Teilnahme genau anfällt, ist weiterhin offen (siehe
    Abschnitt 7, Punkt 1) — nur DASS es über einen bewussten Knopfdruck+Hinschicken passiert,
    ist jetzt klar, nicht mehr "einfach online sein reicht".

**Wichtige Abgrenzung für diesen Auftrag:** der Projektinhaber will hier bewusst nur das
BASISSPIEL für Feature 1 stehen haben — send-to-event-Knopf, Bärchi steht sichtbar in der
Event-Area, Stat-Fortschritt zählt hoch. Ein größeres, ausgebautes AFK-Grind-System um Events
herum (z.B. mehrere Bärchis gleichzeitig einsetzen, Auto-Send, Offline-Fortschritt) ist
AUSDRÜCKLICH NICHT Teil dieses Auftrags — das kommt laut Projektinhaber "später, aber das ist
Zukunftsmusik. Erstmal muss das base game stehen." Also: so einfach wie möglich bauen, nicht
vorgreifen.

---

## 4. Feature 2 — Promotion-System

**Mechanik (klar beschrieben):**
- Ein Bärchi lässt sich befördern, wenn man ihn "doppelt hat" — also Duplikate desselben
  `configId` besitzt. Promotion verbraucht eine bestimmte Anzahl Duplikate und erhöht den
  `promotionLevel` des Ziel-Bärchis um 1.
- **10 Promotion-Stufen insgesamt.** Visualisiert als **5 Sterne**. Naheliegendste Lesart
  (bitte in Abschnitt 7 bestätigen): Promotion 1–5 füllt die 5 Sterne nacheinander (leer →
  gefüllt), Promotion 6–10 färbt die bereits gefüllten Sterne EIN ZWEITES MAL um (z.B.
  Silber → Gold), einer nach dem anderen. Am Ende (Promotion 10) sind alle 5 Sterne in der
  zweiten Farbe — genau wie im Referenzbild ("alle 5 Sterne schwarz gefärbt" beim
  Level-121-Beispiel, das dort ersichtlich voll befördert ist).
- Wie viele Duplikate eine einzelne Promotion-Stufe kostet, hängt von der Rarity ab
  ("je nach Rarität braucht man ihn öfter oder weniger oft") — je seltener die Rarity, desto
  weniger Duplikate pro Stufe (spiegelbildlich dazu, wie viel schwerer ein seltener Bärchi
  überhaupt zu bekommen ist). Exakte Zahlen sind NICHT vom Projektinhaber vorgegeben —
  Vorschlag als Startpunkt (in `BaerchiConfig` oder einer neuen `PromotionConfig` als Tabelle,
  NICHT hartkodiert, und explizit als vorläufige Annahme im Abschlussbericht kennzeichnen):

  | Rarity | Duplikate für Promotion 1→2 | Duplikate für Promotion 9→10 |
  |---|---|---|
  | Common | 3 | 8 |
  | Uncommon | 2 | 6 |
  | Rare | 2 | 5 |
  | Epic | 1 | 4 |
  | Legendary | 1 | 3 |
  | Mythic | 1 | 2 |

  (linear oder leicht wachsend zwischen den beiden Endpunkten interpolieren — exakte Kurve
  ist Geschmackssache, Hauptsache: höhere Promotion-Stufen kosten spürbar mehr als die erste,
  und seltenere Rarity kostet durchgehend weniger als eine häufigere.)
- Das "Duplikat" wird beim Promoten vollständig verbraucht (verschwindet aus dem Inventar,
  ähnlich `RecycleService`, aber OHNE Gummy-Auszahlung — es ist Promotion-Material, kein
  Verwerten). Falls der Projektinhaber stattdessen eine Gummy-Teilrückzahlung wie beim
  Recyceln will, bitte vorher klären statt anzunehmen.

**Effekt einer Promotion:**
- Schaltet Charm-Slots frei (siehe Feature 3, Tabelle in Abschnitt 2 — Slot II ab 2★, III ab
  4★ usw.).
- Ob Promotion ZUSÄTZLICH die Basiswerte des Bärchis direkt erhöht (z.B. +X% HP/ATK pro
  Promotion-Stufe, ähnlich `fusionBonus` bei `FusionService`) hat der Projektinhaber nicht
  gesagt — siehe Abschnitt 7, Punkt 3.

**UI:** Neuer Knopf "Promote" auf der Bärchi-Detailkarte (analog zu "Fuse"), zeigt bei
Bedarf einen Bestätigungs-Dialog mit "Du verbrauchst N × [Bärchi-Name], Bärchi geht auf
Promotion X/10". Serverseitig ein neuer Service `PromotionService.luau` nach demselben
Muster wie `FusionService.luau`/`RecycleService.luau` (eigene Datei, eigenes Remote
`RequestPromoteBaerchi`, `RateLimiter`-Anbindung, `ActivityLock`-Prüfung falls der Ziel-
Bärchi der ausgerüstete ist — dieselbe Konvention wie bei Recycle/Fusion, siehe
`claude/OPUS_PROMPT_QUALITAET_GEBAEUDE_2026-09-07.md` Teil A Punkt 1 zu diesem Muster).

---

## 5. Feature 3 — Battle Charms

**Mechanik (aus den Screenshots abgeleitet):**
- 8 Ausrüstungs-Slots pro Bärchi (I–VIII), jeder einzeln über die Promotion-Sterne-Zahl des
  Bärchis freigeschaltet (Tabelle in Abschnitt 2).
- Jeder freigeschaltete, nicht gesperrte ("locked") Slot lässt sich neu würfeln ("Roll
  Charms" / "Auto Roll" für wiederholtes Würfeln). Ein Wurf pro Slot bestimmt zuerst eine
  Rarity (feste Tabelle, Bild 3: Common 49.8%, Uncommon 26.9%, Rare 17.9%, Super Rare 4.3%,
  Legendary 1.0%, Ascended 0.1%), danach einen Stat-Typ ("dann einen Stat").
- Ein Slot lässt sich sperren ("locked"), damit ein erneuter Roll ihn NICHT neu würfelt —
  so kann man einen einmal gut gewürfelten Slot behalten und nur die restlichen
  weiterwürfeln.
- Rolls kosten **GoldGummies**, keine neue Ressource (siehe Abschnitt 7, Punkt 4 — vom
  Projektinhaber jetzt so festgelegt, "Charm Dust" ist bewusst KEINE eigene Währung).

**GEKLÄRT (Abschnitt 7, Punkt 2): die Charm-Slots sind NICHT an einen festen Stat-Typ
gebunden.** Der Projektinhaber hat das ausdrücklich klargestellt: "die charm slots sind nicht
fest an einen stat typ gebunden. das wird auch gerollt." Das heißt, JEDER Slot würfelt bei
jedem Roll ZWEI unabhängige Zufallswerte: zuerst die Rarity (feste Odds-Tabelle aus Bild 3),
dann — unabhängig davon, welcher Slot-Index das ist — einen Stat-Typ aus dem Pool möglicher
Charm-Boni (Vorschlag, da vom Projektinhaber nicht einzeln benannt: dieselbe Art von Boni wie
im Referenzbild — z.B. Crit-Schaden, Crit-Resistenz, Lauftempo, Schadensreduktion,
Skill-Stärke, HP-Boost, ATK-Boost, XP-Boost — Liste bitte vor der Umsetzung mit dem
Projektinhaber kurz abstimmen, die genauen Bonus-Namen sind Geschmackssache). Die
"Promotion Tiers"-Tabelle aus Bild 2/Abschnitt 2 ist damit AUSSCHLIESSLICH ein
Freischalt-Fortschrittsanzeiger (welcher Slot-Index ab wie vielen Sternen nutzbar wird) —
KEINE feste Zuordnung Slot↔Stat-Typ. Für die Umsetzung heißt das: `CharmConfig.luau` braucht
keine "ein Stat-Typ pro Slot-Index"-Tabelle, sondern nur (a) die 8 Freischalt-Schwellen
(Sterne-Zahl pro Slot-Index, unverändert aus Bild 2) und (b) einen gemeinsamen Pool aller
möglichen Stat-Typen, aus dem JEDER Slot bei JEDEM Roll unabhängig zieht.

**UI:** Neues Popup `CharmPanel.luau` (Client), analog zu `BuildingPanel.luau`/
`FusionPanel.luau` im bestehenden Stil — 8 Slot-Icons, "Promotion Tiers"-Liste darunter
(zeigt nur die Freischalt-Schwelle je Slot, nicht mehr einen festen Stat-Typ), aktueller
GoldGummies-Bestand, "Roll Charms"-Knopf (mit Kosten in GoldGummies), "Auto Roll"-Knopf
(mehrfach würfeln bis Abbruch-Bedingung — z.B. bis GoldGummies aufgebraucht oder Spieler
stoppt manuell, bitte im Abschlussbericht die gewählte Variante nennen). Serverseitig ein
neuer Service `CharmService.luau`, neue Remotes (`RequestRollCharms`,
`RequestToggleCharmLock` o.ä.).

---

## 6. Feature 4 — Fusions-Regeln (neu, vom Projektinhaber in einer Folgenachricht ergänzt)

Der Projektinhaber hat `FusionService` bewusst NICHT als "bleibt wie es ist" stehen lassen,
sondern ihm konkrete neue Regeln gegeben, die auf Feature 1–3 aufbauen. Wichtig:
`FusionService.fuse` verlangt weiterhin zwei VERSCHIEDENE Bärchis DERSELBEN Rarity (das ist
bereits heute so, ändert sich nicht) — die neuen Regeln bestimmen nur, WELCHE Werte das
Ergebnis am Ende trägt, nicht mehr wann fusioniert werden darf.

**Regel 1 — Basiswerte: immer das Bessere, Stat für Stat.**
Bei gleicher Rarity (der einzige erlaubte Fall) werden die vier Basiswerte HP/ATK/SPD/DEF
NICHT mehr von EINEM der beiden Inputs übernommen, sondern JEDER EINZELN: das Ergebnis
bekommt pro Stat den höheren Wert der beiden Inputs (`max(a.hp, b.hp)`, `max(a.atk, b.atk)`,
usw. — nicht "Input A gewinnt komplett" oder "Input B gewinnt komplett"). Siehe Abschnitt 7,
Punkt 8 zur technischen Umsetzung (`baseStatOverride`-Feld nötig, da Basiswerte heute rein
am `configId` hängen).

**Regel 2 — Stat-Level (Feature 1) ebenfalls: immer das Bessere.**
Genauso wird für jeden der vier per-Stat-Fortschritte aus Feature 1 (Event-Teilnahme,
begrenzt durch die Rarity-Obergrenze) der HÖHERE der beiden Input-Werte übernommen, wieder
Stat für Stat einzeln, nicht pauschal "der levelhöhere Input gewinnt alles".

**Regel 3 — Neues Fusions-Menü: der Spieler darf EINE Sache sperren.**
Bisher entscheidet `FusionService` automatisch, welcher Skill übernommen wird (Skill des
level-höheren Inputs) und welches Level das Ergebnis bekommt (Durchschnitt, abgerundet). Das
soll durch eine echte Spieler-Entscheidung ersetzt werden: In einem neuen Fusions-Menü
(Vorschau beider Inputs nebeneinander, bevor der Spieler die Fusion bestätigt) kann der
Spieler **genau EINE** der folgenden drei Eigenschaften sperren ("locken") und dabei
festlegen, von WELCHEM der beiden Input-Bärchis sie kommen soll:
  1. **Ability** (der Skill/`skillId`)
  2. **Level** (der Bärchi-Level)
  3. **Eier, die der Bärchi legen kann** (der EGG-Stat/-Fortschritt aus Feature 1 — die
     Zahl, nicht eine tatsächliche Ei-Produktion, die gibt es ja laut Abschnitt 7, Punkt 6
     noch gar nicht als echte Mechanik)

Nur für die GESPERRTE Eigenschaft entscheidet der Spieler bewusst "von A" oder "von B" —
für die beiden NICHT gesperrten der drei Eigenschaften gilt weiterhin eine automatische
Standard-Regel (Vorschlag, da vom Projektinhaber nicht spezifiziert): Level → das höhere der
beiden (nicht mehr der Durchschnitt — konsistent mit "das Bessere gewinnt" aus Regel 1/2),
Ability → Skill des level-höheren Inputs (heutige Regel bleibt als Fallback), Eier → der
höhere der beiden Werte. Wichtig: das Sperren ist eine BEWUSSTE Ausnahme von "automatisch das
Bessere" — der Spieler kann damit auch das SCHLECHTERE Level oder die schlechtere Ability
eines Inputs erzwingen, wenn er das will (z.B. weil er unbedingt den Skill von Bärchi A will,
selbst wenn Bärchi B leveltechnisch weiter war). Genau das ist der Sinn dieser Regel — echte
Wahlfreiheit, nicht nur eine weitere Automatik.

**Was Regel 3 NICHT betrifft:** die vier rohen Basiswerte (Regel 1) und die vier
Stat-Level (Regel 2) — die werden IMMER automatisch Stat für Stat gemischt (das Bessere),
unabhängig davon, was der Spieler sperrt. Nur Ability/Level/Eier sind über das Fusions-Menü
wählbar.

**UI:** `FusionPanel.luau` (existiert vermutlich schon als einfache Zwei-Bärchi-Auswahl,
bitte den bestehenden Stand in Studio prüfen, bevor neu gebaut wird) bekommt eine dritte
Ansicht dazwischen: nachdem beide Bärchis gewählt sind, aber bevor bestätigt wird — drei
Zeilen (Ability/Level/Eier), jede mit den beiden Werten von Input A und B nebeneinander und
einem Umschalter "sperren: A / B / automatisch". Erst nach dieser Auswahl wird
`RequestFuseBaerchis` (Remote muss um die Sperr-Auswahl erweitert werden, z.B.
`lockedProperty: "ability" | "level" | "eggs" | nil` und `lockedFrom: "A" | "B" | nil`)
ausgelöst.

---

## 7. Offene Fragen — bitte VOR der Umsetzung mit dem Projektinhaber klären

Diese Liste ist der eigentliche Zweck dieses Dokuments. Für jeden Punkt: eine begründete
Standard-Annahme ist genannt, aber bitte nicht stillschweigend übernehmen, sondern aktiv
beim Projektinhaber bestätigen (oder, falls keine Rückmeldung möglich ist, die Annahme
verwenden UND im Abschlussbericht unübersehbar als offene Annahme auflisten — dieselbe
Konvention wie in den bisherigen Opus-Dokumenten dieses Projekts).

1. **GEKLÄRT: Ein einzelner Stat (HP/ATK/SPD/PWR) wächst innerhalb seiner Rarity-Obergrenze
   durch Teilnahme an Map-Events** (siehe Feature 1, oben) — NICHT durch Honig-Füttern. **Die
   Teilnahme-Mechanik ist jetzt ebenfalls geklärt:** ein GUI-Knopf schickt den ausgerüsteten
   Bärchi in die Event-Area in der Map-Mitte, dort tut er je nach Event-Typ etwas, das den
   Event-Reward erzeugt (siehe Feature 1, Abschnitt "Teilnahme-Mechanik"). Noch offen ist nur:
   - Wie viel Stat-Fortschritt pro Event-Teilnahme genau (fix pro abgeschlossenem Event, oder
     pro Sekunde Anwesenheit in der Event-Area, oder ein zufälliger Stat wird pro Event um 1
     erhöht)? Keine Vorgabe vom Projektinhaber — Vorschlag: pro abgeschlossenem Event genau
     EIN zufällig gewählter Stat (HP/ATK/SPD/PWR) des teilnehmenden Bärchis um 1 Stufe, bis
     zur Rarity-Obergrenze — hält das Balancing einfach und macht Events spürbar, ohne dass
     ein Spieler in kurzer Zeit alle Stats maximiert.
   - Gilt das nur für den AUSGERÜSTETEN Bärchi (der einzige, der überhaupt in die Event-Area
     geschickt werden kann, da nur er eine Figur in der Welt hat), oder soll es später einmal
     möglich sein, gezielt einen ANDEREN Bärchi aus dem Inventar zum Event zu schicken statt
     ihn erst auszurüsten? Empfehlung für DIESEN Auftrag: nur der aktuell ausgerüstete Bärchi
     — konsistent mit "nur eine Figur ist in der Welt sichtbar" (siehe
     `BaerchiAutopilotService`-Konvention), und passt zur ausdrücklichen Vorgabe des
     Projektinhabers, hier zunächst nur das Basisspiel zu bauen.
   - Was passiert, wenn der Bärchi in der Event-Area steht, aber gerade KEIN Event aktiv ist
     (`EventService.getActive()` gibt nil zurück, z.B. während der 300s-Pause zwischen
     Events)? Empfehlung: der Bärchi steht einfach dekorativ herum, kein Fortschritt, bis das
     nächste Event startet — kein Fehlerzustand, kein Zwang, ihn zurückzuholen.

2. **GEKLÄRT: die 8 Charm-Slots sind NICHT an einen festen Stat-Typ gebunden — sie sind
   komplett frei würfelbar.** Der Projektinhaber hat das explizit klargestellt (siehe Feature
   3): jeder Slot würfelt bei jedem Roll sowohl Rarity als auch Stat-Typ neu, unabhängig vom
   Slot-Index. Die frühere Annahme "fest gebunden" ist damit verworfen.

3. **Erhöht eine Promotion direkt die Basiswerte des Bärchis** (wie `fusionBonus` bei
   Fusion), oder ist ihr einziger Effekt, Charm-Slots freizuschalten? Empfehlung: JA, ein
   kleiner, gleichmäßiger Bonus pro Promotion-Stufe (z.B. +2% HP/ATK je Stufe, macht den
   "Promote"-Knopf für sich genommen lohnenswert, nicht nur als Voraussetzung für Charms).

4. **GEKLÄRT: "Charm Dust" ist KEINE eigene neue Währung.** Der Projektinhaber will das
   Ressourcen-System bewusst einfach halten ("ich denke ich will es so simpel wie möglich
   halten") — Charm-Rolls kosten direkt **GoldGummies**, die bereits bestehende zweite
   Währung aus PIT-Meilensteinen. Kein neues Feld auf `PlayerData`, kein neuer Service für
   eine Charm-Dust-Produktion. Der Name "Charm Dust" aus dem Referenzbild taucht in Bärchi
   Fighter gar nicht als eigenständiges Konzept auf — die UI zeigt stattdessen einfach den
   GoldGummies-Bestand als Roll-Kosten an.

5. **Mythic-Stat-Cap.** Die Tabelle des Projektinhabers endet bei Legendary (24). Empfehlung:
   Mythic = 28 (setzt das +4-Muster der übrigen Stufen fort) — bitte bestätigen. Betrifft
   auch, ob es analog zum Referenzspiel (das eine siebte Rarity "Secret" oberhalb der
   normalen Stufen hat) einen entsprechenden Ausblick für Bärchi Fighter geben soll — aktuell
   NICHT Teil dieses Auftrags, nur als Hinweis, falls das später gewünscht wird
   (`RARITY_ORDER` in `BaerchiConfig.luau` müsste dafür erweitert werden).

6. **EGG-Stat: bewusst ohne Funktion in diesem Durchlauf.** Der Projektinhaber hat
   ausdrücklich gesagt, dass das Eier-Legen der ausgerüsteten Bärchis ein SPÄTERER,
   separater Schritt ist. Für DIESEN Auftrag heißt das: der EGG-Stat-Balken darf in der UI
   auftauchen (Konsistenz mit den anderen 4 Stats/der Rarity-Cap-Tabelle), aber er darf
   NICHTS auslösen — keine tatsächliche Eiproduktion, kein neuer Timer, keine Anbindung an
   `EggService`. Rein kosmetisch, bis ein eigener zukünftiger Auftrag das Egg-System
   spezifiziert. Bitte im Code mit einem Kommentar klar als "noch ohne Funktion, siehe
   OPUS_PROMPT_PROMOTION_CHARMS" kennzeichnen, damit es niemand für einen vergessenen Bug
   hält.

7. **Fusion + Promotion/Charms — was passiert beim Fusionieren?** `FusionService` erzeugt
   beim Verschmelzen zweier Bärchis einen KOMPLETT NEUEN Bärchi (neue `uid`, siehe
   `BaerchiFactory.create` in `FusionService.fuse`). Offene Frage: verliert das
   Fusions-Ergebnis dabei automatisch seinen Promotion-Fortschritt und alle Charms (weil es
   technisch ein neuer Bärchi ist), oder soll das Ergebnis den HÖHEREN der beiden
   Input-Promotion-Stände + eine Auswahl der besseren Charms übernehmen? Empfehlung: Fusion
   und Promotion bewusst GETRENNT halten (Promotion/Charms fangen beim Ergebnis bei Null an)
   — einfacher und vermeidet, dass Charm-Werte durch Fusion "kopiert" werden können. **Die
   Fusions-MECHANIK selbst ändert sich dagegen jetzt doch** — siehe Feature 4, das der
   Projektinhaber in einer Folgenachricht ergänzt hat.

8. **Fusions-Regeln (Feature 4) — Details, die die Standard-Annahme braucht:**
   - Die Basiswerte (`baseStats.hp/atk/spd/def`) hängen heute ausschließlich am `configId`
     (`BaerchiConfig.BAERCHIS[configId].baseStats`) — eine einzelne Bärchi-Instanz hat keine
     eigenen, abweichenden Basiswerte. "Die besseren Base Stats übernehmen, jeder Stat
     einzeln" heißt deshalb: der fusionierte Bärchi braucht ein NEUES Feld auf
     `Types.Baerchi` (Vorschlag: `baseStatOverride: {hp: number?, atk: number?, spd: number?,
     def: number?}?`), das den per-Stat-Maximalwert der beiden Inputs UND des zufällig
     gewählten Ergebnis-`configId` festhält. `CombatCalculator.getEffectiveStats` muss dann
     `baseStatOverride`-Werte bevorzugen, wo gesetzt, statt blind `def.baseStats` zu nehmen —
     das ist ein Eingriff in eine bestehende, zentrale Funktion, bitte mit Bedacht und mit
     Tests für die bestehenden (nicht fusionierten) Bärchis, deren Verhalten sich NICHT
     ändern darf.
   - "Die höhere Stufe innerhalb einer Rarity-Obergrenze wird übernommen" bezieht sich auf
     die per-Stat-Fortschrittszahl aus Feature 1 (Event-Teilnahme) — auch hier: pro Stat das
     Maximum der beiden Inputs übernehmen, nicht nur bei den rohen Basiswerten.
   - Ergebnis-`configId` bleibt wie heute ein zufälliger Bärchi der nächsthöheren Rarity
     (`pickResultConfigId` unverändert) — nur WELCHE Werte dieser neue Bärchi am Ende trägt,
     ändert sich. Bitte bestätigen, dass das so gewollt ist (Alternative wäre: der Spieler
     wählt auch den Ergebnis-`configId` mit aus — das hat der Projektinhaber nicht erwähnt,
     also nicht annehmen).

---

## 8. Datenmodell-Skizze (Ausgangspunkt für `Types.luau`, an Klärung von Abschnitt 7 anpassen)

```lua
-- Types.Baerchi, neue Felder (Version hochzaehlen, Migration in
-- PlayerService/createDefaultPlayerData ergaenzen — bestehende Konvention):

promotionLevel : number,   -- 0-10
charms : {
	[number]: {   -- Slot-Index 1-8
		rarity : Types.CharmRarity,   -- "Common" | "Uncommon" | "Rare" | "SuperRare" | "Legendary" | "Ascended"
		value  : number,              -- gewuerfelter Bonus innerhalb der Rarity-Spanne
		locked : boolean,             -- vom Spieler gegen Reroll gesperrt
	}?,
},

-- Feature 1: per-Stat-Fortschritt durch Event-Teilnahme, gedeckelt durch die
-- Rarity-Stat-Cap-Tabelle (Feature 1). Getrennt von baerchi.level (Honig-XP) —
-- zwei unabhaengige Fortschrittsachsen.
statLevels : {
	hp  : number,
	atk : number,
	spd : number,
	pwr : number,
},

-- Feature 4, Regel 1: nur gesetzt fuer ein Fusions-Ergebnis, das per-Stat
-- hoehere Basiswerte als sein eigenes configId geerbt hat. CombatCalculator.
-- getEffectiveStats muss diese Werte bevorzugen, wo vorhanden, statt direkt
-- BaerchiConfig.getById(configId).baseStats zu nehmen — fuer JEDEN nicht
-- fusionierten Baerchi bleibt dieses Feld nil und das Verhalten unveraendert.
baseStatOverride : {
	hp  : number?,
	atk : number?,
	spd : number?,
	def : number?,
}?,

-- KEINE neue Waehrung noetig: Charm-Rolls kosten direkt goldGummies
-- (bestehendes PlayerData-Feld) -- "Charm Dust" ist bewusst kein eigenes
-- Konzept in Baerchi Fighter, siehe Abschnitt 7 Punkt 4.
```

Neue Config-Module (Vorschlag, Namen offen): `PromotionConfig.luau` (Duplikat-Kosten-Tabelle
pro Rarity/Stufe, Stat-Cap-Tabelle aus Feature 1), `CharmConfig.luau` (8 Slot-Definitionen:
Stat-Typ, Freischalt-Sterne-Zahl, Rarity-Odds-Tabelle, Wertebereich pro Rarity).

`Remotes.RequestFuseBaerchis` (Feature 4) braucht zwei zusätzliche, optionale Argumente für
die Sperr-Auswahl aus dem neuen Fusions-Menü:

```lua
-- FusionService.fuse(player, uidA, uidB, lockedProperty, lockedFrom)
lockedProperty : ("ability" | "level" | "eggs")?,   -- nil = alles automatisch (heutiges Verhalten)
lockedFrom     : ("A" | "B")?,                       -- nur relevant wenn lockedProperty gesetzt ist
```

---

## 9. Format-Erwartung an Opus

- Bei Code: **vollständige Dateien**, kein "Rest bleibt gleich" — mit Dateipfad als
  Kommentar in der ersten Zeile, im bestehenden Stil (`--!strict`, deutsche Kommentare,
  Konfig-Werte nie hartkodiert in Services).
- Neue Remotes ausschließlich über `Remotes.luau` (keine Magic Strings), neue Services in
  `GameManager.REGISTRY` eintragen inkl. Begründung der Reihenfolge im Kommentar.
- Nach Abschluss: kurzer Bericht (neue/geänderte Dateien, was für den Studio-Test nötig ist,
  welche der 8 offenen Fragen aus Abschnitt 7 wie beantwortet wurden) als
  `claude/PROMOTION_CHARMS_ABGESCHLOSSEN.md`.
- `rojo build` fehlerfrei, projekteigene Checks unter `tools/` (falls vorhanden) grün.
