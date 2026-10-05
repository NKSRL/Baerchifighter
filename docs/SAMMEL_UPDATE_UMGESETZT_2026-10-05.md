# Sammel-Update – UMGESETZT (05.10.2026)

Grundlage: `OPUS_PROMPT_SAMMEL_UPDATE_2026-10-05.md` und `README_INKUBATOR_OFFLINE_ASCENSION_INDEX_PLAN_2026-10-05.md`.
Datenversion **15 → 16** (eine gemeinsame Migration). Branch `claude/eager-edison-nubixz`.

Alle Prüfungen grün (Cloud, Linux-luau): Syntax aller `.luau`, `check_locals` (MapConfig 192/200), Luau-Tests `guide_steps`, `unlock_rules`, `boss_tiers`, alle `run_local`-Tests (neu: `rebirth_rules`, `migration_v16`, `incubator`), alle zwölf Sims, `check_feedback/members/consistency/loc/decor`.
Nicht prüfbar hier: `--!strict`-Typprüfung, `client.test`, `loc.test`, `migration.test` (Heim-PC, Node). **In Studio ist nichts davon getestet.**

Neue Schalter in `FeatureFlags`: `INCUBATOR`, `INDEX_REWARDS`, `PIT_BRAWL`, `AREA_SIGNS` (alle an). Wenn ein Teil in Studio Probleme macht, lässt er sich einzeln abschalten.

---

## Entscheidungen aus Abschnitt 11 (jeweils der Standard)

| # | Frage | Umgesetzt |
|---|---|---|
| 1 | Offline | Rate 2,5 → **3,5** **und** Offline-Maximum **6** Eier |
| 2 | Besondere Ascension-Meilensteine | Tower III/60 → 1, Final 100 → 2, erster Boss-Sieg → 1, ganzer Index → 2 (Index-Belohnung) |
| 3 | Erster Rebirth | **Tower I Stage 30** |
| 4 | Spielzeit bis Rebirth 1 | Sim „Normal“: **52 min** aktiv (Fenster 0,5–1,5 h); „Gelegenheit“ (30 min/Tag): Tag 2 |
| 5 | Geldsenke vor dem Rebirth | **Inkubator-Ausbau** (Level 1–60, 60 % der Gebäudekurve). Ei-Händler-Stufen: siehe 6.3-Entwurf |
| 6 | Inkubator | **Umgebaut (Rückmeldung 05.10.):** Bärchi im Platz brütet zusätzliche Eier; alle Eier sofort öffenbar; 1 Platz ab dem ersten Kampf |
| 7 | Index-Belohnungen | alle vier Ebenen |
| 8 | „Brüten“ (6.5) | **beides**: Lege-Intervall (Common ×0,6, Uncommon ×0,7, Rare ×0,82) und der Inkubator (Bärchi brütet zusätzliche Eier im Rarity-Takt) |
| 9 | Waben | 30 Slots / 30 s Respawn / 10 s Tröpfeln |
| 10 | Kampf um die Mitte | Spieler wird nur gestoßen, wenn er **kein eigenes Bärchi** am Event hat |

Nachtrag Auftraggeber (Chat): „Der Sprung von Tower I geschafft zu Rebirth hat zu lange gedauert.“ → Der erste Rebirth ist jetzt **genau** „Tower I Stage 30 geschafft“. Danach ist er sofort möglich, ohne Gummy-Preis und ohne weitere Wartezeit, und der feste Rebirth-Knopf poppt in diesem Moment auf.

---

## Paket 1 – Fehler

| Punkt | Ursache / Lösung | Dateien |
|---|---|---|
| 1.1 UFO-Einfrieren | (a) Wer im selben UFO schon entführt war und wieder hingeschickt wurde, wurde vom UFO-Takt übersprungen und stand bis Event-Ende still. Er geht jetzt mit Hinweis heim. (b) `finishHome` rief `idleBob` auf, ohne vorher das alte Atmen abzumelden; die Figur sprang auf ihre alte Ruhelage im Pit zurück. (c) Die Entführung bricht ab, sobald die Teilnahme verloren ist (Rebirth, Neubau, Kampf). (d) Wächter: Hängt eine Entführung länger als Wartezeit + 30 s, wird der Bärchi heimgesetzt. (e) Duell-Ausfallschritte stoppen bei Entführung. `D:Invoke("petmode")` zeigt `lockHalter` und `entfuehrt`. | `EventHandlers`, `EventParticipationService`, `EventKit`, `DebugService` |
| 1.2 Figuren in Platten | `Model:GetBoundingBox()` ist am gedrehten `body` ausgerichtet, nicht an der Welt. Die Unterkante kommt jetzt aus den welt-ausgerichteten Grenzen aller sichtbaren Teile (`BaerchiMesh.worldBoundsY`, `FigurePlacement.footOf`). Alle Stellen, die den Fußpunkt lesen, benutzen dieselbe Funktion (sonst würde die Figur bei jedem Schritt wandern). | `BaerchiMesh`, `FigurePlacement`, `FigureFX`, `PitArenaService`, `EventParticipationService`, `EggLayService`, `BaerchiAutopilotService` |
| 1.3 Fusion B nicht wählbar | Die Inventar-Zeilen wurden bei **jedem** Datenstand (mehrmals pro Sekunde) zerstört und neu gebaut. Lag der Tipp dazwischen, kam `Activated` nie an (Handy). Die Zeilen bleiben jetzt pro uid stehen. Ein dritter Tipp ersetzt B, nie A. Gleiches Muster im Eier-Fenster. | `BaerchiInventory`, `HatchPanel` |
| 1.4 „Nächstes Ei in:“ | Schild 9 × 3,6 Studs statt 6 × 3, Ei-Timer ist die größte Zeile, Abstand ab der echten Oberkante (vorher saß das Schild im Kopf) | `FigureBuilder`, `MapConfig.FIGURE_LABEL` |

**Studio-Test:** `startevent Ufo`, Bärchi entführen lassen, danach wieder hinschicken → er geht mit Hinweis heim, legt weiter. Kleinster und größter Bärchi in jedem Tower-Look, mit Etagenwechsel. Fusion auf dem Handy: A von der Karte, B im Inventar.

## Paket 2 – Menüs, Eier-Öffnen, Übersetzung

* **2.1** Großes X (44 × 40) in jedem Fenster (`Theme.closeButton`, auch auf der Bärchi-Karte). Ein kurzer Tipp in die Welt schließt das offene Fenster (`PanelManager`, ein Wischen zählt nicht).
* **2.2** Das Ergebnis steht mindestens 2,5 s (mehr bei seltenen), schließt per Tipp ab 0,8 s oder nach 7 s. Der Bärchi dreht sich groß im Viewport. Nebenbei behoben: in `HatchAnimation` fehlte `require(Notify)`.
* **2.3** Kauf beim Ei-Händler öffnet das Ei sofort mit der großen Schlüpf-Animation.
* **2.4** Event-Toasts, Event-Ende, UFO-Belohnung, Pet-Leiste, Inventar, Bärchi-Karte, Fusion, Charms, Fortsetzungs-Frage, Gebäude-Menü, Eier-Fenster und Ei-Toasts laufen über `Loc`. `bonusText` ist jetzt eine `LocMsg`, Teile werden mit `Loc.join` verbunden. Was alle Spieler gleichzeitig sehen (Arena- und Event-Tafel, Figuren-Labels, Händler-Prompt, Recycler-Schild), ist sprachneutral mit Zeichen (⏱ ⏭ ✔ ⚔ 🛸 ⛏ 🍯 ⬡). Event-Namen: `event.<id>.name`. Offen (Heuristik von `check_loc --todo`): Beschreibungstexte in `SkillConfig`/`BaerchiConfig`/`EggConfig` (Bärchi- und Ei-Namen sind schon übersetzt) sowie Server-Logzeilen.
* **2.5** Charm-Effektzeilen 18 px statt 13 px, mit dunkler Kontur.
* **2.6** Am Honig-Teich kein Schild mehr, kein „Honig füttern“ (weder im Gebäude-Menü noch auf der Bärchi-Karte). Der Prompt heißt nur noch „Verbessern“. Ohne ihn gäbe es keinen Weg zum Ausbau, dazu gibt es jetzt die Kachel „Verbessern“. `RequestFeedHoney` bleibt.
* **2.7** Fester Rebirth-Knopf unten rechts (`RebirthButton`). Er ist unsichtbar bis zur ersten Rebirth-Möglichkeit, erscheint dann mit Pop-in und leuchtet, solange ein Rebirth möglich ist.
* **2.8** Im Fusions-Modus zeigt die Liste nach A nur dieselbe Rarity. Der Server prüft das weiterhin (`err.fuse_rarity_mismatch`).

## Paket 3 – Einführung

* **3.1** Pfeil 84 px statt 40 px, stärkeres Wippen.
* **3.2** Der Event-Schritt erscheint nur 8 s, dann verschwindet er. Reihenfolge jetzt: Eier → Kampf → … → Event.
* **3.3** „Verbessere ein Gebäude“ (Quest-Text).
* **3.4** `CurrencyHint`: einmalige Sprechblase an der Pille beim ersten Gummy-Gewinn bzw. bei den ersten GoldGummies, gemerkt in `uiSeen` (`hint_gummies`, `hint_gold`).
* **3.5** Einsteiger-Kette in `GuideSteps`: Ei öffnen → Kampf → (Eier einsammeln) → **Waben holen und im Recycler abgeben** → **Gebäude verbessern** → Event. Jeder Schritt hat einen Satz (`guide.<schritt>`) über der Pet-Leiste. Neuer Zähler `stats.totalCombsDelivered`. Neue Kachel „Verbessern“ (öffnet das Honig-Gebäude).
* **3.6** Satz im Gebäude-Menü („mehr Honig = mehr XP = höhere Stages“). Vorher/Nachher stand dort schon. Recycler-Schild „⬡ = 12 G“.
* **3.7** Stat-Zeile mit Symbolen, „?“ klappt je Stat einen Satz auf.
* **3.8** `AreaSignController`: Bereichs-Schilder (Event · Waben, Ei-Händler, Live-Kämpfe, Honig-Teich, Waben-Recycler, Ei-Inkubator, Tower-Arena). Sie werden **clientseitig** in der Sprache des Spielers gebaut und brauchen **0 Teile**.
* **3.9** Siehe 6.4, 6.5 und den Inkubator.
* **3.10** Die erste Kettenquest steht immer groß mit Volltext da. Die Tages-Quests erscheinen erst nach ihr.

## Paket 4 – Rebirth und Tower-Tempo

* **4.1** Rebirth kostet **keine Gummies** mehr. Bedingung: eine Tower-Stage **in diesem Leben** (`island.stageBest`, nicht die dauerhaften Rekorde, sonst könnte ein Veteran mehrere Rebirths am Stück machen). Stärkere Stages in anderen Towern zählen über die Äquivalenz. Tabelle `TowerConfig.REBIRTH_REQUIREMENT`:

  | Rebirth → | 1 | 2 | 3 | 4 | 5 | 6 | 7 … 15 | danach |
  |---|---|---|---|---|---|---|---|---|
  | Bedingung | I/30 | II/30 | II/40 | II/45 | III/40 | III/60 | Final 20 … 100 (+10) | Endless +20 je Rebirth |

  Deckel geändert (gemeinsam mit der Bedingung entworfen): R0 I/15 → **I/30**, R1 I/30 → **II/5** (damit Tower II offen ist), Final ab **R6** statt R7 (R6 hatte vorher denselben Deckel wie R5). Test `rebirth_rules.test.lua`: Jede Bedingung liegt in einem offenen Tower, sie fällt nie und steigt bis Final 100.
  Der Rebirth-Dialog zeigt die nötige und die geschaffte Stage, was verloren geht und was bleibt (jetzt mit Inkubator).
* **4.2** Tower I wächst je Stage um 1,15 statt 1,0 (Stage 30 ≈ alte 34). Ein frischer Bärchi endet deutlich vor 25 (`tower_calibration` grün). Tower I zahlt mit `rewardFactor` 0,3, sonst wäre das Einkommen durch den höheren Deckel gesprungen.
* **4.3** Tempo-Knopf über „Fight“, solange der Bärchi im Tower ist: ×1 → ×2 → ×4 → „Sofort“. Die Abrechnung bleibt identisch (`RequestPitSpeed`).
* **4.4** Geldsenke: Inkubator-Ausbau (siehe Paket 8).

**Pacing (`progression_pacing.lua`, Profil Normal 90 min/Tag):**

| | vorher | jetzt |
|---|---|---|
| Look 2 | 24 min | 20 min |
| Look 3 | 2,6 h | 2,1 h |
| Look 4 | 8,2 h | 4,2 h |
| Look 5 | 16,4 h | 10,7 h |
| Look 6 | 75,5 h | 71,4 h |
| Rebirth 1 | 1,9 h | **52 min** |
| Rebirth 2 / 3 / 5 / 10 | 7,8 / 13,9 / 24,9 / 73,7 h | 3,6 / 5,5 / 22,3 / 75,6 h |
| Final 100 | Woche 15 | Woche 15 |

Geänderte Ziele in der Sim (begründet im Code): Rebirth 1 jetzt 0,5–1,5 h (Entscheidung 11.4). Look 4 und Look 5 dürfen früher kommen („am Anfang passiert zu wenig“). Endless Woche 16 für „Viel“ 80–130.
**Bitte freigeben oder Zahlen nennen**, dann passe ich die Tabelle an.

## Paket 5 – Event, Waben, Mitte

* **5.1** Werte in `CombConfig`, `comb_respawn` grün. Mit 4–8 Spielern ist das Pit jetzt öfter leer (gewollt knapper). Die Event-Wabenwerte (`valueFactor`) sind unverändert.
* **5.2** `PitBrawlService` (ein Takt, kein Thread pro Bärchi): Freie Event-Bärchis stoßen Spieler **ohne eigenes Bärchi am Event**, die im Pit näher als 9 Studs kommen. Das gibt Rückstoß, 1,5 s Verlangsamung und 1,5 s Waben-Pause, aber keinen Schaden. Abklingzeit 4 s je Spieler und 2,5 s je Bärchi. Ein Bärchi, das gerade läuft oder kämpft, greift nicht an (Duelle gehen vor). Mit einem einzigen Spieler passiert nichts. Werte in `EventConfig.PIT_BRAWL`.
* **5.3** Die Pet-Leiste zeigt „🐝 Boss in X min“ bzw. „Boss LIVE“. Zahlen unverändert.

## Paket 6 – Ei-Wirtschaft

* **6.1** `OFFLINE_SLOWDOWN` 3,5, `OFFLINE_MAX_EGGS` 6. Der Bericht kommt auch bei 0 gelegten Eiern mit „Lager voll – öfter vorbeischauen!“.
* **6.2** `AscensionEgg` aus allen 19 `eggTable`s entfernt. `EggTree.resolveLaid` macht aus einem Ascensions-Pfad-Ei ein Zucker-Ei. `check_consistency.py` (Abschnitt 9) schlägt fehl, sobald ein Ascensions-Ei außerhalb von EconomyConfig, IndexRewardConfig oder Baum/Anzeige auftaucht. Besondere Meilensteine: `EconomyConfig.SPECIAL_MILESTONES` + `SpecialMilestoneService` (einmalig, rückwirkend, `data.specialClaimed`, neuer Zähler `stats.bossVictories`).
* **6.3** **Nicht gebaut**, Entwurf zur Freigabe: `docs/SAMMEL_6_3_EIKAUF_ENTWURF_2026-10-05.md`.
* **6.4** Start-Eier 3 → **6**.
* **6.5** `EggConfig.LAY_RARITY_FACTOR`. `egg_tree_sim`: Die Freischalt-Tage bleiben fast gleich (Void-Ei 6,2 → 8,1 h, weil Uncommon-Bärchis öfter Zucker statt Nebel legen).

## Paket 7 – Index-Belohnungen

`IndexRewardConfig` (berechnet aus EggConfig/BaerchiConfig) mit vier Ebenen:

* `egg:<Ei>`: Gummies 2.000 × 5^(Stufe−1) plus 2 Eier der Sorte. Ascensions-Pfad-Eier geben stattdessen 60 Gold.
* `path:<Pfad>`: GoldGummies, 1 Blaupause und **+1 Inkubator-Platz**.
* `rarity:<R>`: 20 Gold × Rarity-Index.
* `all`: 2 Ascensions-Eier und 500 Gold.

`IndexRewardService` prüft beim Abholen und zahlt aus (über EconomyService, `EggService.grantEggs` und `EggTreeService.grantBlueprint`). Abholen ist auch rückwirkend möglich. Ein Beobachter meldet neu fertige Reihen (mit `task.defer`, ohne `markDirty`). `data.indexClaimed` geht an den Client. Im Index: Abschnitt „Sammlungen“ oben, je Ei-Reihe ein Abholen-Knopf bzw. ✔, und ein „!“ am Reiter und an der Bärchi-Kachel. „Entdeckt“ bedeutet die Art, nicht die Mutation (Annahme).

## Paket 8 – Inkubator und Plot (umgebaut nach Rückmeldung 05.10.)

> **Umbau:** Der erste Entwurf (Eier ab Gold-Stufe mussten im Inkubator brüten) ist ersetzt. Jetzt setzt man einen **Bärchi** in den Inkubator, und der brütet im Takt seiner Rarity **zusätzliche** Eier aus seiner eigenen Ei-Tabelle. Alle Eier gehen wieder sofort auf.

* **Daten:** `island.incubator = { level, slots = { { slot, baerchiUid, lastEggAt, eggs = { EggType… } } } }`. Kein Timer pro Ei: fällig sind `floor((now - lastEggAt) / Takt)` Eier. Das gilt auch offline (gebremst mit `EggConfig.OFFLINE_SLOWDOWN`) und über Server-Neustarts hinweg. Höchstens `STORE_PER_SLOT = 5` Eier warten pro Platz; ist das Lager voll, läuft die Zeitmarke mit (keine angesammelte Wartezeit).
* **Migration:** Alte Ei-Einträge (`eggType`) gehen zurück ins Ei-Lager, der Platz wird frei (`migration_v16.test.lua`).
* **Regeln** (`Modules/IncubatorRules`, rein, getestet):
  * Frei ab dem ersten Kampf.
  * Plätze: 1, mit Level 10 → 2, mit Level 25 → 3, +1 ab Rebirth 2, +1 je fertigem Index-Pfad, höchstens 6.
  * Takt je Rarity (`IncubatorConfig.BREED_SECONDS_BY_RARITY`): Common 10 min, Uncommon 9, Rare 8, Epic 7, Legendary 6 … Omega 3 min. Level +2 % Tempo je Stufe.
  * `chances(baerchi, eggTree)`: welche Eier mit welcher Wahrscheinlichkeit kommen (gesperrte Eier schon auf ihren freien Vorgänger umgerechnet, wie beim Legen).
  * Ausbau: 60 % der Gebäudekurve (mehr Plätze, schnellerer Takt).
* **Server:** `IncubatorService` mit Takt alle 5 s: einsetzen (`RequestIncubatorStart`, uid), herausnehmen (`RequestIncubatorRemove`, Platz; wartende Eier gehen ins Lager), alle Eier abholen (`RequestIncubatorCollect`, ins Lager), ausbauen. Alles nur **in der Nähe** des Inkubators (30 Studs, `err.incubator_too_far`). Der ausgerüstete Bärchi darf nicht hinein. Wird ein Bärchi aus einem Platz ausgerüstet, verschmolzen, verwertet oder fehlt er nach einem Rebirth, räumt der Takt den Platz (Eier ins Lager). `autoEquipIfNone` nimmt Inkubator-Bärchis nur, wenn es keinen anderen gibt.
* **Rebirth:** Das Level fällt zurück, die Plätze bleiben (Plätze über der neuen Zahl werden geräumt).
* **Plot:** `IncubatorBuilder` baut Sockel und 6 Glaskuppeln links hinten auf dem Beet bei `(-20, 0, 20)`. Unter jeder belegten Kuppel steht der Bärchi verkleinert (`Figure_<n>`, Kuppel in Rarity-Farbe getönt), daneben ein Ei, wenn Eier warten. Über jeder belegten Kuppel zeigt `IncubatorController` die **Ei-Chancen** des Bärchis, „🥚 n/5“ und einen Balken bis zum nächsten Ei; die Kuppel leuchtet, solange Eier warten.
* **Bedienung durch Hingehen:** Am Sockel gibt es zwei Prompts: **E „Eier abholen (n)“** (nur sichtbar, wenn Eier warten, holt direkt ab) und **F „Bärchi einsetzen“** (öffnet `IncubatorPanel`: Plätze mit Takt, Chancen, Fortschritt und „Herausnehmen“, darunter die eigenen Bärchis zum Einsetzen, seltenste zuerst, und der Ausbau). Keine Seitenkachel mehr.
* **8.2:** Option 1 (Plot bleibt, der Inkubator füllt die Fläche). Option 2 (Radius 46) erst nach dem Bildschirmfoto.
* **Balance:** Die Sims (`progression_pacing`, `tower_calibration`) bilden den Inkubator nicht ab und bleiben grün. Zusätzliche Eier: bei 1 Common-Platz ~6 Eier/h online. Werte stehen in `IncubatorConfig` und lassen sich nach dem Playtest leicht drehen.

**Studio-Test:**
1. `D:Invoke("snapshot")`, `D:Invoke("state","fresh")`.
2. Ei öffnen und kämpfen, danach ist der Inkubator frei. Einen zweiten Bärchi schlüpfen lassen.
3. Zum Inkubator gehen, F drücken, den zweiten Bärchi einsetzen: Er steht unter der Kuppel, darüber die Ei-Chancen.
4. `D:Invoke("incubator","done")` füllt alle Plätze. Dann E „Eier abholen“: Die Eier landen im Lager.
5. Den Bärchi aus dem Inkubator ausrüsten: Nach höchstens 5 s ist der Platz frei, wartende Eier sind im Lager.
6. Aus der Ferne geht nichts (Server lehnt mit „Geh näher an den Inkubator“ ab).
7. Einmal Stop/Play: Die Zeit läuft weiter (offline gebremst).

## Rückmeldung 05.10. – weitere Änderungen

* **Honig-Fontäne:** kein Fenster mehr. Man verbessert sie nur direkt davor (Prompt „Verbessern“, Server prüft 30 Studs, `err.pond_too_far`). Über der Fontäne stehen nur Level und Kosten des nächsten Upgrades („Lv. 7“, „⬆ 12.500 G“).
* **Seitenleiste:** Verbessern, Inkubator und Shop sind weg, die übrigen Kacheln sind größer (70 px).
* **Oben links:** Die Quest-Karte steht nicht mehr dauerhaft im Bild. Rechts neben dem Zahnrad sitzt in einer Zeile ein kleiner **Quest-Knopf** (📜, rotes „!“, wenn etwas abholbereit ist) und rechts daneben der **Shop-Knopf** (🛒, „!“ = Gratis-Griff frei; erscheint über `tile_shop`). Neu: `src/client/UI/TopButtons.luau`.
* **Einführung:** Der Schritt „Verbessern“ zeigt in der Welt auf die Fontäne.
* Beibehalten: Der gezogene Bärchi wird beim Schlüpfen groß gezeigt.

---

## Neue und geänderte Dateien (Studio-Einspielung)

**Neu:**
* `src/shared/Config/IncubatorConfig.luau`
* `src/shared/Config/IndexRewardConfig.luau`
* `src/shared/Modules/IncubatorRules.luau`
* `src/server/Services/IncubatorService.luau`
* `src/server/Services/IndexRewardService.luau`
* `src/server/Services/SpecialMilestoneService.luau`
* `src/server/Services/PitBrawlService.luau`
* `src/server/Util/MapBuild/IncubatorBuilder.luau`
* `src/client/UI/RebirthButton.luau`
* `src/client/UI/IncubatorPanel.luau`
* `src/client/UI/CurrencyHint.luau`
* `src/client/Controllers/IncubatorController.luau`
* `src/client/Controllers/AreaSignController.luau`
* `src/client/UI/TopButtons.luau`
* Tests: `tools/luau-tests/rebirth_rules.test.lua`, `migration_v16.test.lua`, `incubator.test.lua`

**Geändert:** siehe `git diff 52f75c1 --stat -- src`. Die neuen Services stehen in `GameManager`, die neuen Remotes in `Remotes`/`NetworkConfig`.

## Für CONTEXT_BRIEFING (liegt nur auf dem Heim-PC, bitte dort nachtragen)

* Datenversion **16**. Neu: `island.stageBest`, `island.incubator`, `indexClaimed`, `specialClaimed`, `stats.bossVictories`, `stats.totalCombsDelivered`.
* **Ascension-Regel:** Ascensions-Eier haben genau zwei Quellen: Rebirth-Meilensteine und besondere Meilensteine (inkl. „ganzer Index“). Kein Bärchi legt sie.
* **Rebirth-Regel:** kein Gummy-Preis. Bedingung ist `TowerConfig.getRebirthRequirement` (Stage in diesem Leben, über Äquivalenz). Gummies verfallen weiterhin.
* **Offline:** Rate ×3,5, höchstens 6 liegende Eier (online 12).
* **Inkubator:** Ein Bärchi (nicht der ausgerüstete) brütet dort im Rarity-Takt zusätzliche Eier, höchstens 5 warten pro Platz. Alle Eier gehen sofort auf.
* `migration.test.lua` (Heim-PC): Fall v15 → v16 aus `migration_v16.test.lua` übernehmen.
