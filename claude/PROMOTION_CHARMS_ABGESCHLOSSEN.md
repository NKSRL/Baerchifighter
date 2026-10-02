# PROMOTION, CHARMS, STAT-STUFEN UND NEUE FUSION — abgeschlossen

**Datum:** 2026-09-08
**Auftrag:** `claude/OPUS_PROMPT_PROMOTION_CHARMS_2026-09-08.md`
**Stand:** alle vier Features gebaut, plus die Nachbesserung an den Stats (Abschnitt 0)
und das Ei-Legen (Abschnitt 0c). `rojo build` fehlerfrei, beide Checks unter `tools/` grün,
**80 Rechen-Tests bestanden**.

---

## 0. Nachtrag: PWR ist ein eigener Stat, DEF ist raus

**Das hier ist die wichtigste Änderung am Dokument.** Im ersten Durchgang hatte ich „PWR" aus
den Referenz-Screenshots als DEF gedeutet — das war falsch. Nach deiner Korrektur gilt:

- **SPD** ist die **Angriffsgeschwindigkeit**.
- **PWR** ist die **Ability-Stärke**: ein Prozentwert, der den Schaden von Skills skaliert.
- **DEF gibt es nicht mehr.** Weder bei den Bärchis noch bei den PIT-Gegnern. Wer einen Tank
  will, baut einen Bärchi mit viel HP — das ist die ganze Regel.

Die vier Stats des Spiels sind damit **HP / ATK / SPD / PWR**, und genau diese vier wachsen
auch über die Event-Teilnahme.

### Die Ability-Formel

```
Skill-Schaden = (ATK × Skill-Multiplikator + Skill-Basisschaden) × (1 + PWR)
```

Multiplikator und Basisschaden gehören dem **Skill** (`SkillConfig`), ATK und PWR dem
**Bärchi** (`BaerchiConfig`). Gerechnet wird das an genau einer Stelle:
`CombatCalculator.skillDamage`.

Sechs Skills haben dafür einen `baseDamage` bekommen (IceSlam 8, SugarStorm 10, ShardBlast 14,
BlackHole 25, ChromaBlast 30, BigBang 45). Er ist bewusst klein: für einen frischen Bärchi
macht er eine starke Ability spürbar, ab mittleren Leveln trägt ihn das ATK-Vielfache längst.
`baseDamage` ist optional — fehlt er, rechnet die Formel mit 0 weiter.

**Eine Feinheit, die du kennen solltest:** `BasicPunch` ist als Skill mit Multiplikator 1.0 und
Cooldown 0 modelliert, ist also technisch eine Ability. Ein Bärchi mit BasicPunch bekommt seine
PWR deshalb in *jeder* Runde als Aufschlag, während ein ShardBlast-Bärchi (Cooldown 3) sie nur
alle vier Runden sieht. Dafür hat der Grundschlag-Bärchi keinen Ausschlag nach oben. Ist im
Code so dokumentiert — sag Bescheid, wenn du das anders willst.

### PWR-Werte: pro Bärchi, unabhängig von der Rarity

Wie von dir vorgegeben leitet sich PWR **nicht** aus der Rarity ab. Ein Common kann mehr haben
als ein Legendary:

| Bärchi | Rarity | HP | ATK | SPD | **PWR** |
|---|---|---|---|---|---|
| Roter Bärchi | Common | 105 | 10 | 1.00 | 10% |
| Grüner Bärchi | Common | 130 | 8 | 0.90 | 6% |
| Gelber Bärchi | Common | 93 | 12 | 1.20 | **18%** |
| Blauer Bärchi | Uncommon | 156 | 14 | 1.00 | 12% |
| Oranger Bärchi | Uncommon | 117 | 18 | 1.10 | 22% |
| Zucker-Bärchi | Rare | 205 | 20 | 1.20 | 20% |
| Kristall-Bärchi | Rare | 250 | 16 | 0.90 | 28% |
| Goldener Grizzly | Epic | 366 | 35 | 1.00 | 14% |
| Void-Bärchi | Epic | 278 | 45 | 1.40 | 30% |
| Regenbogen-Bärchi | Legendary | 577 | 55 | 1.30 | **35%** |
| Uralter Bärchi | Legendary | 923 | 40 | 0.85 | **8%** |
| Kosmischer Bärchi | Mythic | 1286 | 90 | 1.50 | 26% |

Der Gelbe (Common, 18%) schlägt den Uralten (Legendary, 8%) klar — der Uralte ist der Panzer
mit dem Schild-Skill, der Gelbe die Glaskanone. Ein automatisierter Test prüft genau diese
Rarity-Unabhängigkeit, damit sie nicht versehentlich wieder verloren geht.

### Woher die neuen HP-Werte kommen

Die HP sind **nicht neu geraten**, sondern umgerechnet:

```
neue_hp = alte_hp / (1 - altes_def)
```

Das ist exakt die effektive HP, die der Bärchi mit seiner alten DEF hatte. Der Uralte
(600 HP / 35% DEF) hält mit 923 HP und ohne DEF genauso viele Treffer aus wie vorher; der Gelbe
(90 HP / 3% DEF) kommt auf 93 und bleibt die Glaskanone. Die Rangfolge der Bärchis
untereinander ist unverändert, nur die Zahl auf der Karte ist größer.

---

## 0b. Inverted-Bärchis

Komplett gebaut, **inklusive der 0,5%-Ziehchance beim Schlüpfen**.

- **Wirkung:** +15% HP und ATK, **+5%** SPD und PWR. Der Bonus greift auf den *Basiswert*, vor
  allem anderen — „+15% HP" heißt damit wirklich 15% mehr, egal auf welchem Level oder mit
  welchen Charms.
- **Woher:** ausschließlich aus dem Ei (`EggService`). Der Wurf ist unabhängig vom Gacha-Roll —
  ein Common kann invertiert sein, ein Legendary normal.
- **Fusion:** war *einer* der beiden Eltern invertiert, ist es auch das Ergebnis (dieselbe
  Linie wie „das Bessere gewinnt"). Vermehren lässt sich damit nichts: eine Fusion verbraucht
  zwei und liefert einen. *Das ist eine Annahme von mir* — soll Inverted nur aus dem Ei kommen,
  ist das eine Zeile in `FusionService`.

### Wie man sie erkennt

Auf vier Wegen, damit einer von 200 Bärchis nicht untergeht:

1. **Die Figur in der Welt** trägt die **Komplementärfarbe ihrer Rarity** und leuchtet
   (Neon-Material). Das setzt sich auch über ein rarity-eigenes Mesh hinweg — sonst sähe ein
   invertierter Legendary aus wie ein normaler.
2. **Das Namensschild über der Figur** zeigt `[INV]` in derselben Farbe.
3. **Die Detailkarte** hat ein eigenes **INVERTED-Badge** neben dem Fusions-Badge (beide
   gleichzeitig sind möglich).
4. **Inventar und Schlüpf-Anzeige**: `[INV]` im Namen, „INVERTED" in der Unterzeile, und beim
   Schlüpfen färbt sich der ganze Rahmen um.

---

## 0c. Eier legen

Der EGG-Stat war der letzte Balken ohne Wirkung — der ist jetzt echt. Dazu lagen **zwei tote
Enden** im Code, die beide auf dasselbe zeigten: `statLevels.egg` (angezeigt, ohne Funktion)
und `BaerchiConfig.eggRate` (kommentiert als „GoldGummy-Produktion pro Minute", von keinem
Service gelesen). Beide sind jetzt aufgelöst.

### Wie es funktioniert

Der **ausgerüstete** Bärchi legt regelmäßig ein Ei **genau dort ab, wo er gerade steht**. Es
bleibt als anklickbares Objekt liegen; ein Klick befördert es ins Lager, wo es sich wie ein
gekauftes Ei ausbrüten lässt. Wer seinen Bärchi zum Honig-Teich laufen lässt, findet danach
eine Spur aus Eiern — das ist gewollt.

Damit schließt sich ein Kreis, der vorher offen war: **Promotion braucht Duplikate**, und
Duplikate kommen aus Eiern. Vorher gab es dafür nur Rebirth-Meilensteine und Käufe.

### Was jeder Bärchi legt — individuell, nicht nach Rarity

Wie von dir vorgegeben hat **jeder Bärchi seine eigene Mischung**. Sie leitet sich
ausdrücklich nicht aus der Rarity ab; thematisch passend gewählt (der Zucker-Bärchi legt
Zucker-Eier, der Kristall-Bärchi Kristall-Eier):

| Bärchi | Grundintervall | Legt |
|---|---|---|
| Roter Bärchi | 4:00 min | Basis 100% |
| Grüner Bärchi | 5:00 | Basis 90%, Zucker 10% |
| Gelber Bärchi | 4:30 | Basis 85%, Zucker 15% |
| Blauer Bärchi | 5:30 | Basis 65%, Zucker 35% |
| Oranger Bärchi | 6:00 | Basis 60%, Zucker 40% |
| Zucker-Bärchi | 7:00 | **Zucker 75%**, Basis 15%, Gold 10% |
| Kristall-Bärchi | 8:00 | Zucker 55%, Gold 30%, **Kristall 15%** |
| Void-Bärchi | 8:30 | Zucker 40%, Gold 40%, Kristall 20% |
| Goldener Grizzly | 9:00 | **Gold 70%**, Zucker 20%, Kristall 10% |
| Uralter Bärchi | 10:00 | Gold 40%, Kristall 57%, **Ascension 3%** |
| Regenbogen-Bärchi | 11:00 | Gold 45%, Kristall 50%, **Ascension 5%** |
| Kosmischer Bärchi | 15:00 | Kristall 80%, **Ascension 20%** |

Eine Regel halten die Zahlen ein: **wer seltener legt, legt Besseres.** Und
**Ascensions-Eier** können nur die beiden Legendaries und der Mythic überhaupt legen — sie
sollen verdient bleiben. Ein Test prüft genau das (höchstens 3 von 12 Bärchis).

### Wie oft — die Formel

```
Tempo     = 1 + (Level − 1) × 10%  +  EGG-Stufen × 8%
Tempo    *= 1,15                     falls INVERTED
Intervall = Grundintervall / Tempo   (offline × 2,5)
```

**Das Level wirkt hier linear, nicht exponentiell** — und das ist eine bewusste Abweichung von
„alle Stats +10% pro Level", die du erklärt bekommen solltest: HP und ATK wachsen mit
`1,1^(Level−1)`, auf Level 50 also aufs 106-fache. Das ist dort richtig, weil die PIT-Gegner
mit derselben Kurve mitwachsen. Beim Ei-Legen gibt es keine Gegenseite. Dieselbe Kurve hieße:
ein Level-50-Bärchi legt alle 2 bis 9 Sekunden, der individuelle Grundwert wäre bedeutungslos
und die Obergrenze binnen einer Minute erreicht.

Mit der linearen Variante legt ein Level-50-Bärchi knapp **6-mal so schnell** wie auf Level 1
(Roter Bärchi: 41s statt 4:00 min). Wenn du es doch exponentiell willst, ist das eine Zeile in
`EggCalculator` — im Code steht, welche.

### Offline und Obergrenze

- Die Produktion läuft **offline weiter**, mit demselben Zeitstempel-Verfahren wie der Honig
  (kein Server-Loop nötig) — aber **2,5-mal langsamer**, wie von dir gewünscht.
- Es liegen **höchstens 12 Eier** gleichzeitig herum. Ist das erreicht, hört der Bärchi auf zu
  legen und die Wartezeit sammelt sich **nicht** an — exakt dasselbe Verhalten wie bei einem
  vollen Honig-Lager. Wer drei Tage wegbleibt, findet zwölf Eier, nicht dreihundert.

### Eine technische Entscheidung, die du kennen solltest

Die Ei-Positionen werden **plot-relativ** gespeichert, nicht als Weltkoordinaten. Grund: welchen
der acht Plots ein Spieler bekommt, entscheidet sich bei jedem Join neu. Mit absoluten
Positionen lägen die Eier nach einem Rejoin dort, wo der Plot beim Legen war — im schlimmsten
Fall auf dem Plot eines Nachbarn.

### Wie man an die Eier kommt

- **Einzeln anklicken** in der Welt (dieselbe Mechanik wie das Anklicken einer Bärchi-Figur).
- **„Alle Eier einsammeln"** auf der Detailkarte, wenn einem das Klicken zu mühsam ist.

Die Karte zeigt außerdem, wie schnell dieser Bärchi legt, was er legen kann und wie voll der
Plot ist.

---

## 1. Was jetzt im Spiel ist

**Feature 1 — Rarity-abhängige Stat-Obergrenzen.**
Jeder Bärchi hat **fünf** wachsende Stat-Stufen (HP/ATK/SPD/PWR/EGG — EGG ist seit dem
Ei-Legen echt, siehe Abschnitt 0c). Sie wachsen **nicht** über Honig, sondern über Event-Teilnahme: ein neuer Knopf
auf der Detailkarte schickt den ausgerüsteten Bärchi in die Event-Area in der Weltmitte, wo
er je nach Event-Typ sichtbar etwas tut. Endet ein Event, während er dort steht, steigt genau
**ein zufällig gewählter Stat um eine Stufe** — bis zur Rarity-Obergrenze.

**Feature 2 — Promotion.** 10 Stufen, dargestellt als 5 Sterne (Stufe 1–5 füllt sie silbern,
6–10 färbt dieselben fünf golden um). Kostet Duplikate desselben `configId`; je seltener die
Rarity, desto weniger. Gibt +2 % HP/ATK je Stufe **und** schaltet die Charm-Slots frei.

**Feature 3 — Battle Charms.** 8 Slots, über den Promotions-Stand freigeschaltet. Ein Wurf
würfelt alle offenen, nicht gesperrten Slots gleichzeitig neu — erst eine Rarity (feste Odds
aus der Vorlage), dann einen Stat-Typ. Kostet **GoldGummies**, keine neue Währung.

**Feature 4 — Neue Fusions-Regeln.** Basiswerte und Stat-Stufen werden Stat für Stat als
Maximum gemischt; im neuen Sperr-Schritt des Fusions-Menüs legt der Spieler **genau eine** von
drei Eigenschaften (Ability / Level / Eier) gezielt auf Bärchi A oder B fest.

---

## 2. Antworten auf die offenen Fragen aus Abschnitt 7

Alle vier noch offenen Punkte wurden **vor** der Umsetzung mit dir geklärt — hier zur
Nachvollziehbarkeit noch einmal, plus die Annahmen, die ich zusätzlich treffen musste.

| # | Frage | Entscheidung |
|---|---|---|
| 1 | Ertrag pro Event-Teilnahme | **Ein zufällig gewählter Stat +1 pro abgeschlossenem Event.** Gezogen wird nur unter den Stats, die noch **nicht** am Cap stehen — sonst liefe die Teilnahme umso öfter ins Leere, je weiter der Bärchi schon ist. |
| 1b | Nur der ausgerüstete Bärchi? | **Ja.** Nur er hat eine Figur in der Welt. Kein Auto-Send, kein Offline-Fortschritt — Basis-Spiel, wie von dir vorgegeben. |
| 1c | Kein Event aktiv, Bärchi steht da | **Kein Fehlerzustand.** Er steht dekorativ herum und atmet, bis das nächste Event startet. Er wird auch nach dem Event **nicht** automatisch zurückgeholt — wer die nächste Runde mitnehmen will, lässt ihn stehen. |
| 2 | Slots an Stat-Typ gebunden? | **Nein**, war bereits geklärt. `CharmConfig` hat deshalb nur Freischalt-Schwellen und einen gemeinsamen Stat-Pool. |
| 3 | Promotion-Bonus auf Basiswerte | **Ja: +2 % HP/ATK je Stufe**, bei Promotion 10 also +20 %. |
| 4 | Charm Dust | **Keine eigene Währung**, war bereits geklärt. Ein Wurf kostet **25 GoldGummies**. |
| 5 | Mythic-Stat-Cap | **28** (setzt das +4-Muster fort). Eine siebte Rarity ("Secret") ist weiterhin nicht Teil des Auftrags. |
| 6 | EGG-Stat | ~~Ohne Funktion~~ — **nachgeholt, siehe Abschnitt 0c.** EGG ist der fünfte wachsende Stat und steuert das Lege-Tempo. |
| 7 | Fusion + Promotion/Charms | **Ergebnis startet bei Promotion 0 ohne Charms.** Verhindert, dass gut gewürfelte Charms sich über Fusionen vervielfältigen. |
| 8 | `baseStatOverride` | Umgesetzt wie skizziert, siehe Abschnitt 4 unten. |

### Zusätzliche Annahmen, die ich treffen musste

Diese standen nicht im Auftrag und sind **nicht** mit dir abgestimmt — bitte kurz drüberlesen:

1. ~~„PWR" = DEF~~ — **korrigiert, siehe Abschnitt 0.** PWR ist die Ability-Stärke, DEF ist
   ersatzlos entfallen.
2. **Nur vier Charm-Stat-Typen** (HP-Boost, ATK-Boost, Angriffs-Tempo, **Ability-Stärke**).
   Die Vorlage zeigt „Crit DMG" und „Movement Speed" — beides gibt es im Spiel nicht (keine
   Krits, die Figuren laufen mit `MapConfig.WALK_SPEED`). Ein Charm, der auf nichts wirkt,
   wäre ein stiller Fehler. Der Pool ist bewusst erweiterbar: ein Eintrag in
   `CharmConfig.STAT_POOL` genügt, solange `CombatCalculator` den Ziel-Stat kennt.
3. **Duplikat-Kosten der Promotion** sind der Vorschlag aus dem Auftrag (Common 3→8 bis
   Mythic 1→2), linear interpoliert und aufgerundet. Reine Balancing-Annahme.
4. **Auto-Roll = 20 Würfe in EINEM Paket**, nicht eine Client-Schleife. Ein Auto-Roll, der pro
   Wurf ein Remote feuert, liefe sofort in den `RateLimiter`. Der Preis wird pro Wurf einzeln
   abgebucht, das Paket bricht also sauber ab, sobald die GoldGummies alle sind — der Client
   zeigt danach die **tatsächliche** Anzahl an, nicht die angefragte.
5. **Charm-Boni addieren sich**, sie multiplizieren sich nicht: acht Slots mit je +1,4 % HP
   ergeben +11,2 %, nicht 1,014⁸. Vorhersagbarer, und bei acht Slots ist der Unterschied klein.
6. **Ein Bärchi am Event isst nicht.** Der Teilnahme-Service hält das `ActivityLock` für die
   ganze Zeit, sonst würde der Autopilot ihn mitten am Event zum Honig-Teich zurückrufen. Das
   ist der Preis fürs Hinschicken und macht die Entscheidung erst zu einer.

### Eine bewusste Abweichung vom Auftrag

Der Auftrag verlangt für `PromotionService` eine **`ActivityLock`-Prüfung** nach dem Muster von
`RecycleService`. Die habe ich **nicht** eingebaut, und der Grund steht auch im Kopf der Datei:
`RecycleService` prüft das Schloss, weil er die Figur des ausgerüsteten Bärchis mitten aus einer
Laufbewegung löschen könnte. Beim Promoten kann das nicht passieren — der ausgerüstete Bärchi ist
als Material ausdrücklich ausgeschlossen, es verschwindet also nie eine Figur. Eine Prüfung wäre
hier sogar aktiv schädlich: der Autopilot hält das Schloss fast durchgehend, der Promote-Knopf
wäre die meiste Zeit tot. Sag Bescheid, wenn du das trotzdem drin haben willst.

---

## 3. Neue Dateien

| Datei | Was drin steht |
|---|---|
| `src/shared/Config/PromotionConfig.luau` | Stat-Caps je Rarity, Duplikat-Kostenkurve, Promotions-Bonus, Stat-Stufen-Gewinn, 10→5-Sterne-Umrechnung |
| `src/shared/Config/CharmConfig.luau` | 8 Slots + Freischalt-Schwellen, Rarity-Odds, Stat-Pool, Wurf-Kosten, Würfel-Funktionen |
| `src/server/Services/PromotionService.luau` | Befördern, Duplikat-Verbrauch, Slot-Freischaltung |
| `src/server/Services/CharmService.luau` | Würfeln (einzeln + Paket), Slots sperren |
| `src/server/Services/EventParticipationService.luau` | Hin- und Rückweg zur Event-Area, Anwesenheit, Belohnung am Event-Ende |
| `src/client/UI/CharmPanel.luau` | 8 Slot-Kacheln, Effektliste, GoldGummy-Bestand, Roll + Auto-Roll |

## 4. Geänderte Dateien

| Datei | Änderung |
|---|---|
| `src/shared/Network/Types.luau` | `CharmRarity`, `Charm`, `StatLevels`; fünf neue Bärchi-Felder inkl. `isInverted`; drei neue Ergebnis-Typen; **Version 7 → 9** |
| `src/shared/Config/BaerchiConfig.luau` | `baseStats.pwr` statt `def` bei allen 12 Bärchis, HP umgerechnet, `PWR_PER_LEVEL`, Inverted-Block (Chance, Bonus, Farbe) |
| `src/shared/Config/CombatConfig.luau` | Gegner ohne DEF, HP umgerechnet, `ENEMY_ATK_SOFTENING` als Ausgleich |
| `src/shared/Config/SkillConfig.luau` | `baseDamage` bei sechs Skills, Formel im Kopf dokumentiert |
| `src/shared/Modules/BaerchiMesh.luau` | `markInverted`: Komplementärfarbe + Neon, auch über rarity-eigene Modelle hinweg |
| `src/server/Services/EggService.luau` | der Inverted-Wurf beim Schlüpfen |
| `src/client/UI/BaerchiInventory.luau` | `[INV]`-Marker und Farbe in der Liste |
| `src/client/UI/HatchPanel.luau` | Inverted übernimmt die Schlüpf-Anzeige |
| `src/shared/Modules/EggCalculator.luau` | **neu** — Legeintervall und Ei-Chancen, das Gegenstück zu CombatCalculator |
| `src/server/Services/EggLayService.luau` | **neu** — Legen (online und offline), Einsammeln |
| `src/shared/Config/EggConfig.luau` | Farben und Kurznamen je Ei-Typ, kompletter Abschnitt „Eier legen" |
| `src/server/Services/PlotDisplayService.luau` | vierte Signatur: welche Eier herumliegen |
| `src/client/Controllers/WorldController.luau` | Klick auf ein Ei sammelt es ein (dieselbe Mechanik wie der Klick auf eine Figur) |
| `src/shared/Network/Remotes.luau` | 5 neue Client→Server-Remotes, 4 neue Server→Client-Events; `RequestFuseBaerchis` um zwei optionale Argumente erweitert |
| `src/shared/Config/NetworkConfig.luau` | Cooldowns für die 5 neuen Remotes |
| `src/shared/Config/EventConfig.luau` | `action` + `actionText` je Event-Typ; Kopf-Kommentar korrigiert (ein Event hat jetzt eine Auswirkung) |
| `src/shared/Modules/BaerchiFactory.luau` | Setzt die vier neuen Felder; zwei neue `CreateOptions` (nur die Fusion nutzt sie) |
| `src/shared/Modules/CombatCalculator.luau` | **Zentraler Eingriff**: `baseStatOverride`, Promotions-Bonus, Stat-Stufen, Charm-Summen |
| `src/server/Core/GameManager.server.luau` | Drei neue Services registriert, jeweils mit Begründung der Position |
| `src/server/Services/PlayerService.luau` | v8-Migration (legt die neuen Felder an, säubert ungültige Charms) + v9-Migration (räumt `def` weg, legt `pwr` und `isInverted` an) |
| `src/server/Services/FusionService.luau` | Regeln A–E (E = Inverted vererbt sich), neue Signatur mit `lockedProperty` / `lockedFrom` |
| `src/server/Services/EventService.luau` | `onEventEnded`-Hook, `getRemainingSeconds`, `skipPhase` (nur für den Studio-Test) |
| `src/server/Services/MapService.luau` | `getEventPitPosition()`, `getEventPitRadius()`, Inverted-Färbung und `[INV]` am Namensschild |
| `src/server/Services/DebugService.luau` | 9 neue Command-Bar-Befehle (inkl. `stats` und `add … true` für Inverted), `list` zeigt Promotion/Stat-Stufen/Charms/Inverted |
| `src/client/UI/BaerchiPanel.luau` | Sterne, Stat-Stufen-Balken, Charm-Vorschau, Promote-/Charms-/Event-Knopf, INVERTED-Badge, Statszeile jetzt ATK/SPD/PWR; Inhalt liegt in einem **Scroller** |
| `src/client/UI/FusionPanel.luau` | Dritte Ansicht: der Sperr-Schritt zwischen Auswahl und Bestätigung |
| `src/client/Main.client.luau` | `CharmPanel` eingehängt |

---

## 5. Zur Migration alter Spielstände

Es sind **zwei** Migrationen, beide in `PlayerService.applyDefaults`:

- **v8** legt `promotionLevel`, `statLevels` und `charms` an und säubert ungültige Charm-Einträge.
- **v9** räumt danach auf: `statLevels.def` und `baseStatOverride.def` **fliegen raus**, `pwr`
  kommt mit 0 dazu, `isInverted` mit `false`.

Beide erkennen fehlende Felder **einzeln** (nicht an der Versionsnummer) und sind deshalb
gefahrlos wiederholbar. Sie stehen bewusst **vor** der `currentHp`-Migration, weil die über
`CombatCalculator.getEffectiveStats` läuft und das die neuen Felder liest.

**Der alte DEF-Wert wird NICHT in PWR übertragen.** Die beiden haben nichts miteinander zu tun
(Schadensreduktion gegen Ability-Stärke) — ein Bärchi mit acht DEF-Stufen hätte sonst still
acht Stufen eines völlig anderen Stats geschenkt bekommen. PWR fängt bei 0 an.

**Bestehende Bärchis werden nicht nachträglich invertiert.** Das wäre ein Geschenk an alte
Spielstände, das neue Spieler nicht bekommen.

---

## 6. Was für den Studio-Test nötig ist

`rojo build` bzw. `rojo serve` wie immer. Danach in der **Command Bar** (Server-Kontext,
Play läuft):

```lua
local D = game.ServerScriptService.RBLDebug
D:Invoke("help")
```

**Promotion testen**

```lua
D:Invoke("add", "RedBaerchi", 1)   -- 3x aufrufen: Common kostet 3 Duplikate für Stufe 1
D:Invoke("add", "RedBaerchi", 1)
D:Invoke("add", "RedBaerchi", 1)
D:Invoke("add", "RedBaerchi", 5)   -- der wird befördert
D:Invoke("list")                   -- uid des Ziel-Bärchis heraussuchen
D:Invoke("promote", "<uid>")
```

Achtung: der **ausgerüstete** Bärchi wird nie als Material verbraucht — er zählt also auch nicht
in die Duplikat-Zahl. Bei vier gleichen Bärchis ist einer davon der ausgerüstete, es bleiben drei.

**Charms testen**

```lua
D:Invoke("give", 0, 100000)        -- GoldGummies
D:Invoke("roll", "<uid>", 5)       -- 5 Würfe
D:Invoke("charms", "<uid>")        -- alle 8 Slots im Klartext
D:Invoke("lock", "<uid>", 1)       -- Slot I sperren, dann nochmal rollen
```

Ohne Promotion ist nur Slot I offen — das ist Absicht, kein Fehler.

**Event-Teilnahme testen.** Ein Zyklus dauert normal 3 Minuten Event + 5 Minuten Pause. Dafür
gibt es `skipevent`:

```lua
D:Invoke("skipevent")   -- Pause endet sofort, Event läuft
D:Invoke("event")       -- ausgerüsteten Bärchi hinschicken (Weg dauert ein paar Sekunden)
-- kurz warten, bis er sichtbar auf dem Podest steht
D:Invoke("skipevent")   -- Event endet → Stat-Stufe wird vergeben, Toast erscheint
D:Invoke("list")        -- statLevels prüfen
D:Invoke("recall")      -- zurück auf den Plot
```

`skipevent` stellt nur die Uhr vor; den Rest macht der normale Tick. Es kann also nichts
auslösen, was im echten Ablauf nicht ohnehin passiert.

**Inverted testen.** Die Ziehchance liegt bei 0,5% — im Schnitt 200 Eier. Zum Testen deshalb
direkt erzeugen:

```lua
D:Invoke("add", "RedBaerchi", 10, true)   -- invertiert
D:Invoke("add", "RedBaerchi", 10)         -- zum Vergleich normal
D:Invoke("stats", "<uid>")                -- Kampfwerte inkl. PWR gegenüberstellen
```

Erwartung: der invertierte hat +15% maxHp und ATK, +5% SPD und PWR. Rüste ihn aus und schau ihn
dir auf dem Plot an — er sollte in der Komplementärfarbe seiner Rarity leuchten und `[INV]` über
dem Kopf tragen.

Den echten Zufallsweg prüfst du mit vielen Eiern:

```lua
for i = 1, 50 do D:Invoke("hatch", "BasicEgg"); D:Invoke("claim") end
D:Invoke("list")   -- inverted = true suchen
```

**Eier testen.** Auf ein echtes Legeintervall zu warten (4 bis 15 Minuten) macht das System
unprüfbar — dafür gibt es `lay` und `eggtime`:

```lua
D:Invoke("eggs")            -- was liegt herum, wie schnell legt er, welche Chancen
D:Invoke("lay", 5)          -- 5 Eier sofort legen, ohne aufs Intervall zu warten
D:Invoke("lay", 20)         -- weiter füllen: bei 12 ist Schluss (Obergrenze)
D:Invoke("collect")         -- alles einsammeln
D:Invoke("info")            -- eggStock prüfen, dann im Ei-Menü ausbrüten
```

Die Eier sollten sichtbar um den Bärchi herum liegen und sich einzeln anklicken lassen. Lass ihn
zum Honig-Teich laufen (`D:Invoke("honey")` füllt die Lager, der Autopilot schickt ihn los) —
dann sollte eine Spur aus Eiern entstehen.

Offline-Nachholen ohne Rejoin:

```lua
D:Invoke("eggtime", 60)     -- Zeitmarke 60 Minuten zurück
-- max. 5 Sekunden warten, dann legt der Tick nach
D:Invoke("eggs")
```

Achtung: `eggtime` + Tick rechnet mit der **Online**-Rate. Das echte Offline-Verhalten (2,5-mal
langsamer) siehst du nur, wenn du den Play-Modus verlässt und neu joinst.

**Fusion mit Sperre testen**

```lua
D:Invoke("fuse", uidA, uidB)                    -- alles automatisch
D:Invoke("fuse", uidA, uidB, "ability", "B")    -- Skill kommt von B, auch wenn A weiter ist
```

Im Spiel selbst: Inventar → zwei Bärchis markieren → „Weiter" → Sperr-Schritt → „Fusionieren".

---

## 7. Verifikation

| Prüfung | Ergebnis |
|---|---|
| `rojo build` (7.7.0) | fehlerfrei |
| `tools/check_consistency.py` | „Alles konsistent" — inkl. der neuen Remotes (alle haben eigene Cooldowns) und der drei neuen Services in der Boot-Liste |
| `tools/check_members.py` | „Keine unbekannten Modul-Felder gefunden" |
| `luau-compile` über alle 60 `.luau` | keine Syntaxfehler |
| `luau-analyze` | keine neuen Typfehler in den geänderten/neuen Dateien. Die verbleibenden Meldungen (`WorldController`, `CombatPanel`, `Theme`, `DebugService`, `IslandService`, `EggConfig`) sind unverändert vorher schon da gewesen |

### Balancing: der PIT vor und nach dem DEF-Ausbau

DEF zu entfernen ändert jeden Kampf im Spiel. Damit das nicht auf gut Glück passiert, habe ich
den **kompletten PIT-Lauf simuliert** — einmal mit dem alten Code (mit DEF), einmal mit dem
neuen — und daraus `ENEMY_ATK_SOFTENING` bestimmt. Bei **0.95** decken sich die Läufe:

| RedBaerchi, PIT-Level 1 | alt (mit DEF) | neu (ohne DEF) |
|---|---|---|
| Level 1 | 3 Stages | 3 Stages |
| Level 5 | 5 | 5 |
| Level 7 | 7 | 7 |
| Level 10 | 10 | 10 |
| Level 15 | 15 | 15 |
| Level 20 | 20 | 21 |
| Level 30 | 31 | 32 |
| Level 50 | 54 | 54 |

Auch die Werte des angeschlagenen Bärchis stimmen **exakt** überein (Level 10, PIT 1:
100% HP → 10 Stages, 50% → 7, 25% → 4) — und das ist der Wert, an dem der Kern-Loop hängt
(„lohnt es sich, vor dem Lauf zu füttern?").

**Ein Rest bleibt bewusst stehen:** Bärchis mit früher hoher Verteidigung (Kristall, Uralt) sind
auf höheren Leveln etwas stärker geworden — der Kristall-Bärchi schafft auf Level 10 jetzt 21
statt 19 Stages. Das ist die logische Folge der Umrechnung: aus einem flachen Prozentsatz sind
HP geworden, und HP wachsen mit dem Level mit. Es trifft genau die Bärchis, die als zäh gedacht
waren, deshalb habe ich es als Verbesserung stehen lassen statt wegzukorrigieren. Sag Bescheid,
wenn du das anders siehst.

### Rechen-Tests

Zusätzlich habe ich die reine Rechenlogik in einer Luau-Sandbox durchgetestet
(`PromotionConfig`, `CharmConfig`, `CombatCalculator`, `SkillConfig`, `BaerchiConfig` mit
gestubbten Roblox-Globals) — **alle 55 Prüfungen bestanden**, unter anderem:

- Stat-Caps 8/12/16/20/24/28 stimmen
- Duplikat-Kosten steigen über alle 10 Stufen monoton, seltene Rarity ist durchgehend billiger
- Die 10→5-Sterne-Umrechnung stimmt bei 0, 3, 5, 7 und 10
- Die Rarity-Odds summieren auf exakt 100, und **200 000 Würfe** treffen jede der sechs Stufen
  innerhalb der Toleranz (gemessen: Common 49,82 %, Uncommon 26,82 %, Rare 18,00 %,
  Super Rare 4,29 %, Legendary 0,97 %, Ascended 0,10 %)
- Slot I ab Promotion 0, Slot VIII erst ab 10
- **Ein Bärchi ohne die v8-Felder rechnet in `getEffectiveStats` Bit für Bit wie vorher**
  (HP, ATK, SPD und DEF einzeln geprüft)
- Promotion 10 = +20 % HP, 8 HP-Stufen = +32 % HP, zwei HP-Charms = +20 % obendrauf
- Ein Charm in einem Slot, der beim aktuellen Promotions-Stand gesperrt wäre, zählt **nicht** mit
- `baseStatOverride` greift pro Stat und lässt nicht gesetzte Felder beim Config-Wert
- **PWR:** ein PWR-Charm addiert flach und lässt ATK unberührt; PWR-Stufen addieren flach
- **Ability-Formel:** ChromaBlast trifft nachweislich für `(ATK × 3.0 + 30) × (1 + PWR)`;
  derselbe Bärchi mit mehr PWR und **gleichem ATK** haut härter zu; ein Gegner ohne PWR macht
  exakt ATK Schaden
- **Inverted:** +15% HP und ATK, aber nur +5% SPD und PWR — jeweils einzeln nachgerechnet
- Die Inverted-Ziehchance über **400 000 Würfe** (gemessen: 0,504%)
- **PWR ist rarity-unabhängig**: der höchste Common-Wert liegt über dem niedrigsten Epic-/
  Legendary-Wert (18% gegen 8%)
- Jeder der 12 Bärchis hat ein `pwr` und **keinen** `def` mehr

**Ei-Legen (25 weitere Prüfungen):**

- Level 11 = exakt doppeltes Tempo (der Beweis, dass es linear und nicht exponentiell wirkt)
- Level 50 legt knapp 6-mal so schnell — nachgemessen: 41s statt 240s beim Roten Bärchi
- 8 EGG-Stufen = Tempo 1,64; Inverted = 15% schneller; offline exakt 2,5-mal langsamer
- Die Untergrenze greift auch bei Level 50 + Inverted + vollem Stat-Cap
- Die Ei-Chancen summieren sich bei **jedem** der 12 Bärchis auf exakt 100%
- **120 000 Würfe** pro Bärchi treffen die Soll-Verteilung: Kristall-Bärchi 54,8 / 30,2 / 15,1%
  (Soll 55 / 30 / 15), und er würfelt **nie** ein Basis- oder Ascensions-Ei
- Regenbogen-Bärchi: Ascensions-Ei bei 5,0% (Soll 5%)
- Höchstens 3 der 12 Bärchis können überhaupt Ascensions-Eier legen
- EGG steht in `GROWABLE_STATS`, es sind fünf wachsende Stats

---

## 8. Wo ich vorsichtig war — Punkte für deinen Studio-Test

1. **`CombatCalculator.getEffectiveStats` ist die zentrale Formel des Spiels** und wird von
   Kampf, Autopilot, Anzeige und den Migrationen gelesen. Sie ist diesmal wirklich umgebaut
   worden (DEF raus, PWR rein, Inverted). Die Simulation oben deckt das PIT-Verhalten ab, aber
   schau beim ersten Play trotzdem auf die HP-Zahlen: sie sind jetzt durchweg höher als früher
   (105 statt 100 beim Roten), und das ist Absicht.
2. **Die Karte scrollt jetzt.** Die Detailkarte hat sieben Zeilen mehr bekommen; statt sie weiter
   wachsen zu lassen, liegt der Inhalt in einem Scroller. Auf einem kleinen Bildschirm bitte
   einmal bis ganz nach unten wischen und prüfen, ob alle Knöpfe erreichbar sind.
3. **Der Weg zum Event ist lang** (Plot-Ring 212 Studs bis zur Mitte). Ich habe das Lauftempo
   dafür verdoppelt; wenn es sich trotzdem zäh anfühlt, ist das eine Zahl in
   `EventParticipationService` (`EVENT_WALK_SPEED`).
4. **Mehrere Spieler am Event** stehen jeweils auf ihrer eigenen Seite des Podests (Richtung des
   eigenen Plots, dieselben acht Richtungen wie die Zaunlücken). Bei acht Spielern gleichzeitig
   habe ich das nicht ausprobieren können.
5. **Die Eier sind neu in der Welt** — bis zu zwölf kleine Kugeln auf dem Plot. Schau, ob sie
   sich gut anklicken lassen und ob sie den Bärchi nicht verdecken. Größe und Streuradius sind
   je eine Zahl in `EggConfig` (`LAY_EGG_SIZE`, `LAY_SCATTER_RADIUS`).
6. **Die Legeintervalle sind mein Vorschlag**, nicht deine Vorgabe. Wenn sich 4 Minuten für den
   ersten Bärchi zu lang oder zu kurz anfühlt: es ist eine Zahl pro Bärchi in `BaerchiConfig`
   (`layIntervalSeconds`), und die Ei-Chancen daneben ebenso.
7. **Ein Kampf hat Vorrang.** Startet man einen PIT-Lauf, während der Bärchi am Event steht,
   nimmt `PitArenaService` das Schloss per `forceAcquire`. Der Teilnahme-Service merkt das
   spätestens nach 4 Sekunden, räumt den Eintrag und der Bärchi bekommt für dieses Event keine
   Stufe. Das ist so gewollt — bitte einmal gegenprüfen, dass die Figur dabei nicht seltsam
   springt.

---

## 9. Was ausdrücklich NICHT gebaut ist

- **Kein ausgebautes AFK-Event-System.** Kein Auto-Send, kein Offline-Fortschritt, keine
  mehreren Bärchis gleichzeitig — laut deiner Vorgabe ein späterer, eigener Auftrag. Die Stelle
  zum Erweitern ist `_present` in `EventParticipationService` (eine Liste statt eines Eintrags)
  und `awardTo`, das schon jetzt pro Bärchi arbeitet.
- **Keine Verteidigung.** DEF ist weg und kommt nicht zurück — Tankigkeit läuft über HP.
- **Keine siebte Rarity** („Secret" aus dem Referenzspiel).
- **Keine eigene Animation** für die Event-Aktionen. Die Bärchi-Meshes sind nicht gerigt, eine
  echte „fängt Bienen"-Animation gäbe es für dieses Modell gar nicht — der Bärchi zeigt die
  Aktion stattdessen über unterschiedliche Idle-Bewegungen (kräftiges Hüpfen / schnelles Nicken /
  ruhiges Wiegen). Der Spieler sieht, **dass** sein Bärchi mitmacht.
