# Map-Redesign abgeschlossen — Inseln, Wasser, Karo-Wiese, goldene Arena

Stand: 2026-09-08 · Vorlage: dein Screenshot aus dem Referenzspiel

---

## Was du gesagt hast, und was daraus geworden ist

> „orientiere dich an dieser Map beim building und dem GUI"
> „Die silos/fässer sind als futter für die hühner in diesem spiel gedacht.
> Ich wollte die idee als inspiration nutzen und habe deshalb ja einen honig
> teich haben wollen. Ja zum map design btw."

Umgesetzt ist deshalb **das Map-Design**, nicht die Gebäudeformen. Die Fässer
und Silos bleiben draußen — die sind im Referenzspiel das Hühnerfutter, und
dieselbe Rolle hat bei dir längst der Honig-Teich. Bienenstock, Honigtopf und
Presse behalten ihre eigenen Formen.

Vom Map-Design übernommen:

| Aus der Vorlage | Bei uns |
|---|---|
| Getrennte Inseln statt einer Fläche | Hauptinsel + 8 Plot-Inseln + 8 Arena-Inseln |
| Holzstege dazwischen | 16 Stege, alle gleich lang |
| Karierte Wiese in zwei Grüntönen | Ja, auf allen Inseln und auf jedem Beet |
| Sandkante zum Wasser | Ja, 8 Studs breit, ringsum |
| Wasser rundherum | Ja, und begehbar |
| Goldener Kampfplatz mit Leuchtring | Ja, plus leuchtender Zaun |

---

## Die Welt jetzt

```
                        (A)
                         |
                        [P]
                         |
             (A)—[P]— (( C )) —[P]—(A)      8 mal, alle 45 Grad
                         |
                        [P]
                         |
                        (A)
```

Drei Ringe, alle 44 Studs auseinander:

| | Radius | Was drauf ist |
|---|---|---|
| **Hauptinsel** | 150 | Spawn, Honigmast, freie Karo-Wiese, 46 Blumen |
| **Plot-Inseln** (8x) | 58, auf Ring **252** | Beet 72x72, Zaun, Schild, 3 Gebäude, Honig-Teich |
| **Arena-Inseln** (8x) | 30, auf Ring **384** | Goldene Kampffläche, Leuchtring, Zaun, Säulen |

61 Studs Wasser zwischen zwei benachbarten Plot-Inseln, 278 Studs offenes
Wasser hinter den Arenen bis zum Horizont.

**Warum getrennte Inseln.** Vorher war alles eine einzige 480 Studs breite
Scheibe, auf der die Plots als Rechtecke lagen. Aus der Spielerkamera las sich
das als eine große grüne Fläche mit Markierungen darauf — man sah nicht, wo der
eigene Bereich anfängt. Getrennte Inseln beantworten das ohne ein einziges
Schild: was zu mir gehört, ist das, was am Ende **meines** Stegs liegt.

**Der Weg zur Arena ist gleich geblieben:** 126 Studs vom Bärchi-Platz (vorher
rund 135). Die Kampf-Wiedergabe fühlt sich also genauso an wie bisher.

---

## Die einzelnen Stücke

### Karo-Wiese

Zwei Grüntöne im Schachbrett. Gebaut werden **nur die hellen Felder** als
flache Teile — die dunkle Hälfte ist die Inselscheibe selbst. Das halbiert die
Teilezahl bei exakt demselben Bild: **112 Teile** für die ganze Welt inklusive
aller acht Beete.

Das Weltraster (24 Studs) hat seinen Ursprung im Weltmittelpunkt, die Karos
laufen also über alle Inseln durch statt auf jeder neu anzusetzen. Ein Feld
wird nur gesetzt, wenn **alle vier Ecken** in der Scheibe liegen — am Ufer
bleibt dadurch ein unregelmäßiger dunkler Saum stehen, und genau der lässt die
Wiese auslaufen statt abgeschnitten zu wirken.

Die Beete rastern **feiner** (18 Studs, also 4x4 Felder): das ist die Fläche,
auf der man selbst steht: 24er-Felder wären darauf nur drei Reihen und würden
gar nicht mehr als Karo lesen. 72 / 18 geht glatt auf, es bleibt kein
Reststreifen an einer Kante.

Die **Lego-Noppen sind weg**. Noppen und Karos übereinander ergeben nur Unruhe,
und das Karo ist das, was die Fläche gliedert.

### Sandkante

Kein Ring aus Segmenten, sondern eine **breitere Scheibe, die tiefer liegt** —
sichtbar bleibt nur ihr überstehender Rand. Ein echter Ring wären ein Dutzend
Teile für dasselbe Bild, und an jeder Naht eine Kante, an der man hängen bleibt.

### Wasser

Eine einzige Scheibe unter allem, **begehbar**. Wer vom Steg fällt, landet auf
der Oberfläche und läuft zurück, statt ins Leere zu stürzen. In einem Spiel, in
dem man ständig über schmale Stege läuft, ist das die freundlichere Lösung — ein
Sturz wäre reine Strafe ohne Spielinhalt.

Wiese 0 → Sand −1.0 → Wasser −2.6. Beide Stufen sind niedrig genug, dass eine
Roblox-Figur sie ohne Springen hochgeht.

### Stege

**Eine** Funktion baut alle 16. Der innere Steg (Hauptinsel → Plot) und der
äußere (Plot → Arena) unterscheiden sich nur in zwei Radien. Vorher gab es eine
`BRIDGE_LENGTH`, die nur für den äußeren gedacht war — genau die Sorte Zahl, die
irgendwann nicht mehr zur Welt passt. Ein Steg überbrückt jetzt immer genau
`ISLAND_GAP`.

### Goldene Arena

Die Arena-Insel ist eine Insel wie jede andere (gleiche Dicke, gleiche
Sandkante), damit sie nicht wie ein Fremdkörper im Wasser steht. Darauf:

* die **goldene Kampffläche** (Radius 26), einen kleinen Absatz erhöht
* ein **leuchtender Ring** am Sockelrand — wieder eine breitere Scheibe, die
  flach darunter liegt, ein Teil statt eines Dutzends Segmente
* ein **Zaun aus 22 leuchtenden Pfosten**, mit einer 34 Studs breiten Lücke zum
  Steg hin (der Steg ist 12 breit — man läuft also bequem hinein)
* die **Säulen** wie bisher, eine pro PIT-Level

### Blumenfreie Gassen

Von der Spawn-Mitte führt zu jedem der acht Stege eine blumenlose Bahn. Nicht
weil Blumen im Weg wären — sie kollidieren nicht — sondern weil die freien
Bahnen den Weg **zeigen**. Auf einer ringsum gleich grünen Insel ist das neben
dem Honigmast die einzige Orientierung, und sie kostet keine einzige
zusätzliche Part.

---

## Was die Landschaft nicht mehr dem Spieler gehört

Die **Plot-Inseln und die inneren Stege entstehen einmal beim Serverstart**,
nicht mit dem Plot-Model eines Spielers. Würden sie mit ihm entstehen und
vergehen, wäre die Welt bei zwei Spielern ein Ozean mit zwei Inseln darin, und
beim Verlassen verschwände mitten im Bild ein Stück Land. Auf einer leeren
Insel steht dann eben nichts — den Weg dorthin gibt es trotzdem.

Was dem Spieler gehört (Beet, Zaun, Schild, Gebäude, Teich, äußerer Steg,
Arena), kommt weiterhin mit ihm.

---

## Vorher / nachher an den Zahlen

| | vorher | jetzt |
|---|---|---|
| Zentrale Fläche | Scheibe Radius 240 | Insel Radius 150 |
| Plots | Rechtecke auf der Scheibe, Ring 165 | eigene Inseln, Ring 252 |
| Arena | Ring 300 | Ring 384 |
| Stege | 8, je 34 Studs | 16, je 44 Studs |
| Boden | Lego-Noppen-Textur | Karo-Wiese aus zwei Grüntönen |
| Plot-Boden | Grau (91,91,91) | dunkles Grün mit hellen Karos |
| Wasser | keins | Scheibe Radius 700, begehbar |
| Blumen | 90 | 46 (die Insel ist ein Fünftel so groß) |

---

## Geprüft

Ohne Studio, aber nicht ungeprüft:

**Sichtprüfung.** `tools/render_map.py` war seit dem Equip-System kaputt (es
suchte noch das alte 25er-Bärchi-Raster `BAERCHI_AREA`, das es seit dem
Equip-System nicht mehr gibt). Repariert und um eine dritte Ansicht erweitert:
einen **senkrechten Schnitt** von der Weltmitte bis zur Arena. Das ist die
Ansicht, die der Grundriss nicht zeigen kann — und genau dort hat sie auch
etwas gefunden (siehe unten). Die drei Ansichten habe ich als Bilder gerendert
und angeschaut, nicht nur erzeugt.

**Ein echter Fehler, gefunden im Schnitt:** Sockel und Kampffläche der Arena
lagen beide auf Höhe 0. Zwei deckungsgleiche Oberflächen flimmern in Roblox
gegeneinander (Z-Fighting) — von oben sieht man davon nichts, im Schnitt sofort.
Der Sockel liegt jetzt 0.35 Studs tiefer (`PIT_RIM_DROP`), derselbe Trick wie
bei `BRIDGE_SINK` und `GRASS_HEIGHT`.

**Rechnerisch.** Vier Prüfungen laufen beim Serverstart in `MapService.init`
und warnen im Klartext: passt das quadratische Beet auf die runde Insel (die
**Ecke** zählt, nicht die Kante)? Liegt der Plot-Ring wirklich eine Steglänge
vor der Hauptinsel? Berühren sich zwei Nachbarinseln? Reicht das Wasser bis
hinter die Arenen? Dieselben Zusammenhänge stehen als Tabelle in der Vorschau.

**Neues Prüfskript `verify_f.py`**, das MapConfig im echten Luau **ausführt**
(nicht nur die Zahlen nachbaut) und die Invarianten an den echten Werten
nachrechnet — inklusive: ist die Zaunlücke breiter als der Steg? Geht
`PLOT_SIZE / PLOT_GRASS_TILE` glatt auf?

**Blumen simuliert:** 2000 Durchläufe, jedes Mal werden alle 46 Blumen gesetzt
(Radius 31 bis 138, Median 93) — die acht freien Gassen fressen die
Versuchszahl nicht auf.

**Alles andere unverändert bestanden:** `luau-compile` über alle 50 Dateien,
`check_members`, `check_consistency`, `check_decor`, sowie `verify`,
`verify_b`, `verify_d`, `verify_e` aus den vorherigen Durchgängen.
`luau-analyze` meldet **keine neue Meldungs-Kategorie**.

---

## Was als Nächstes anstehen könnte

* **Im Studio anschauen.** Die Vorschau kennt Farben und Maße, aber nicht das
  Licht. Wenn das Wasser zu grell oder die Karos zu kontrastreich wirken,
  stehen alle Werte nebeneinander in `MapConfig` (`GRASS_DARK`, `GRASS_LIGHT`,
  `WATER_COLOR`, `WATER_TRANSPARENCY`).
* **Rebirth während eines PIT-Laufs** reißt weiterhin den ganzen Plot ab
  (`MapService.rebuildIsland` fragt `ActivityLock` nicht) — offen seit Teil A.
* **3D-Wünsche pro Gebäude** (Stockwerke am Bienenstock, sich füllender Topf,
  bewegte Presse) brauchen Exporte aus Studio von dir.
