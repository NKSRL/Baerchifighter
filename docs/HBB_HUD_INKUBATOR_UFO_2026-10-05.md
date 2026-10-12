# HUD aufgeräumt, Inkubator mit Bärchi, UFO-Wiederkehr – 05.10.2026

Wünsche des Projektinhabers (Chat), umgesetzt auf dem Stand des Sammel-Updates (PR #3, Branch `claude/eager-edison-nubixz`). Drei neue Schalter in `FeatureFlags`, alle an. Auf `false` ist alles wie vorher.

| Schalter | Was |
| --- | --- |
| `HUD_ROW_V2` | Honig-Brunnen nur vor Ort verbessern, keine Kacheln „Verbessern“, „Inkubator“ und „Shop“ rechts, größere Kacheln, Knopf-Zeile ⚙ · Quests · Shop |
| `INCUBATOR_BREED` | Inkubator = Bärchi hineinsetzen, er brütet Eier. Eier gehen wieder sofort auf. |
| `UFO_REJOIN` | Bärchi darf mehrmals ins selbe UFO, nach dem Absetzen ist sein Level 60 s halbiert |

## 1. Honig-Brunnen (`HUD_ROW_V2`)
* Kein Fenster mehr. **E kurz halten (0,4 s) am Brunnen = direkt verbessern** (`Remotes.RequestUpgradeBuilding`, der Server prüft wie immer).
* Über dem Brunnen steht ein Schild: **„Lv. 12“** und darunter **„⬆ 1.234 Gummies“** (grün, wenn bezahlbar; „Höchste Stufe“ am Ende). Beim Level-Aufstieg hüpft das Schild kurz.
* Verbessern geht nur noch in der Nähe des Brunnens. Die Kachel „Verbessern“ ist weg.
* Die Einführung („Verbessere dein Honig-Gebäude“) zeigt jetzt mit dem Leuchtstrahl zum eigenen Brunnen statt auf die Kachel.
* Code: `WorldController` (Abschnitt „HUD_ROW_V2: Honig-Brunnen ohne Fenster“), `GuideController.ownHoneyBuilding`.

## 2. Leiste und Knöpfe (`HUD_ROW_V2`)
* Rechte Kachelleiste: Eier, Bärchis, Ei-Baum, Bestenliste, Login-Bonus. Die Kacheln sind größer (70 statt 54 px, Beschriftung 16 statt 14 px). Auf kleinen Fenstern schrumpft die Leiste wie bisher.
* Oben links eine Zeile: **⚙ (Sprache) · Quests · Shop**, je 38 px. Ein rotes „!“ zeigt Abholbares (Quest fertig bzw. Gratis-Griff im Shop). Der Shop-Knopf erscheint wie die alte Kachel ab der 2. Sitzung.
* Die große Quest-Karte ist versteckt. Der Quests-Knopf öffnet das Quest-Fenster. Die Belohnungs-Meldungen kommen weiter.
* Code: neu `UI/HudRow.luau` (in `Main.client` nach `QuestTracker`), `MenuBar` (Größen, ausgeblendete Kacheln).

## 3. Inkubator mit Bärchi (`INCUBATOR_BREED`)
* Man geht zum Inkubator, E („Baerchi einsetzen“) öffnet das Inkubator-Fenster. Dort stehen die Plätze, die eigenen Bärchis zum Einsetzen und der Ausbau. Andere Wege dorthin gibt es nicht mehr.
* Ein eingesetzter Bärchi **brütet im Takt seiner Rarity** zusätzliche Eier aus seiner eigenen Ei-Tabelle. Gesperrte Eier rutschen wie beim Legen auf den freien Vorgänger. Das kommt **zusätzlich** zu den Eiern des ausgerüsteten Bärchis.
* Der ausgerüstete Bärchi kann nicht hinein (er legt ja schon). Wird ein Bärchi aus dem Inkubator ausgerüstet, fusioniert oder verwertet, verlässt er den Platz automatisch (innerhalb von 5 s).
* Die Eier fallen **neben den Inkubator** und werden wie gelegte Eier durch Darüberlaufen eingesammelt. Es gibt eine eigene Grenze von **8** liegenden Inkubator-Eiern. Sie zählt nicht gegen die 12 des ausgerüsteten Bärchis.
* Offline wird auch gebrütet: langsamer (×3,5 wie beim Legen), höchstens 4 Eier.
* **In der Kuppel** steht eine kleine Figur des Bärchis. Darüber zeigt ein Schild Name, Rarity, die **Chancen je Ei** (die 4 häufigsten, z. B. „Basis-Ei 60 % / Zucker-Ei 30 % …“) und die Zeit bis zum nächsten Ei („voll – einsammeln!“, wenn die Grenze erreicht ist).
* Plätze und Ausbau wie bisher: 1 Platz, 2 ab Level 10, 3 ab Level 25, +1 ab Rebirth 2, +1 je Index-Pfad, höchstens 6. Ausbau macht +2 % Tempo je Level. Beim Rebirth bleiben die Bärchis sitzen. Plätze über der neuen Platz-Zahl brüten nicht („Platz gesperrt“), bis wieder ausgebaut ist.
* **Eier gehen wieder sofort auf**, auch Gold und höher. Eier, die noch im alten Ei-Inkubator lagen, kommen beim nächsten Join ins Lager. Niemand verliert eines.

**Takt (Sekunden pro Ei auf Level 1, `IncubatorConfig.BREED_SECONDS_BY_RARITY`) – Annahme, bitte freigeben oder Zahlen nennen:**

| Common | Uncommon | Rare | Epic | Legendary | Mythic | Divine | Cosmic | Secret | Godly | Eternal | Omega |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 15 min | 14 | 13 | 12 | 11 | 10 | 9,5 | 9 | 8,5 | 8 | 7,5 | 7 min |

Bewusst langsamer als das Legen des ausgerüsteten Bärchis (Common legt alle 2,5–3 min): Der Inkubator ist ein Zusatz. Die Pacing-Sims rechnen den Inkubator nicht mit. Sie bleiben grün, sagen über diese Zusatz-Eier aber nichts aus.

* Daten: `island.incubator.breeders = { { slot, uid, lastEggAt } }` (optional, `PlayerMigration` legt es an), `LaidEgg.fromIncubator`. Keine neue Datenversion: Das Feld wird nur ergänzt.
* Code: `IncubatorRules` (breedSeconds, breedDue, findBreeder, canBreed …), `IncubatorService` (putBaerchi, takeBaerchi, Takt, Offline-Nachholen), `IncubatorBuilder` (Figur, Attribute `BreederUid/LastEggAt/BreedSeconds`), `IncubatorController` (Schild), `IncubatorPanel` (`rebuildBreed`), `EggCalculator.getResolvedChances/countOwnLaid`, neues Remote `RequestIncubatorBaerchi` („put“, uid / „take“, Platz).

## 4. UFO (`UFO_REJOIN`)
* Wer vom UFO abgesetzt wurde, darf im selben Event wieder hin (vorher: „schon an Bord – geht heim“).
* Nach dem Absetzen ist der Bärchi **60 s geschwächt**: Sein Level zählt in Event-Duellen nur halb. Das gilt für die Kampfstärke (`api.power`) und für `api.level`. Über dem Kopf steht „💫 ½ Lv 42s“, der Spieler bekommt eine Meldung.
* Die gespeicherten Daten bleiben unberührt (es wird mit einer Kopie gerechnet). Die Schwächung gilt nur für Events, nicht für Tower-Kämpfe.
* Werte: `EventConfig.UFO.DROP_WEAKEN_SECONDS = 60`, `DROP_WEAKEN_LEVEL_FACTOR = 0.5`. Deine Nachricht nannte einmal „eine Minute“ und einmal „2 Minuten“. Ich habe 60 s genommen; für 2 Minuten nur die Zahl auf 120 ändern.

## Prüfungen (Cloud, Linux-luau)
Syntax aller `.luau`, `check_locals` (höchster Wert MapConfig 192/200), `guide_steps`, `unlock_rules`, `boss_tiers`, alle `run_local`-Tests (`incubator.test.lua` um 25 Brut-Prüfungen erweitert), alle elf Sims, `check_feedback/members/consistency/loc/decor`. **In Studio ist nichts davon getestet.**

## Studio-Testschritte
1. Am Brunnen: Schild „Lv. X / ⬆ Preis“, E halten → Level steigt, kein Fenster.
2. Rechts nur noch 5 große Kacheln. Oben links ⚙ · Quests · Shop in einer Zeile, keine Quest-Karte.
3. Inkubator: hingehen, E → Fenster. Einen nicht ausgerüsteten Bärchi einsetzen → Figur in der Kuppel, Schild mit Chancen und Zeit. `D:Invoke("incubator","breed")` → Ei fällt neben den Inkubator, drüberlaufen sammelt es ein.
4. Den eingesetzten Bärchi ausrüsten → er verlässt den Platz.
5. Gold-Ei im Eier-Fenster öffnen → geht sofort auf.
6. UFO-Event (`startevent Ufo`): entführen lassen, nach dem Absetzen wieder hinschicken → er darf mitmachen, „💫 ½ Lv“ läuft 60 s herunter.
7. Teile mit `D:Invoke("parts")` zählen (die Mini-Figuren kommen dazu).
