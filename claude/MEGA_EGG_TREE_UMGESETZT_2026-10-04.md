# Mega Egg Tree: UMGESETZT (2026-10-04)

Setzt `EGG_TREE_MEGA_UPDATE_2026-10-03.md` um (WP1 bis WP11). Datenversion **14**. Die Code-Dateien liegen im RBL-Ordner. Die alten Versionen aller geänderten Dateien liegen in `RBL/_backup_vor_mega_egg_tree_2026-10-04/`.

## Deine Entscheidungen (aus dem Chat)

- **Fusion erhöht die Rarity nicht mehr.** Sie fasst nur noch die Stats zusammen (pro Stat der bessere Wert). Das Ergebnis hat die Art des Bärchis mit dem höheren Level (bei Gleichstand A) und dieselbe Rarity. Jede Rarity ist fusionierbar. Der feste Sprung Legendary + Legendary → Kosmischer Bärchi ist entfallen.
- **Ei-Presse: ja.** 5 gleiche Eier ergeben 1 Ei der nächsten Stufe im selben Pfad. Das Ziel-Ei muss schon frei sein. Beim Zucker-Ei wählst du zwischen Gold (Goldenes Ei) und Void (Nebel-Ei). Der Ascensions-Pfad lässt sich nicht pressen.
- **Rebirth-Kurve bis 100 mit Simulation:** siehe unten.

## Was jetzt im Spiel ist

**WP1 Fundament**
- 20 Eier (`Types.EggType`), 16 neue Bärchis, Pfad-Feld je Bärchi und Ei (Stamm, Gold, Kristall, Void, Kosmos, Ascension).
- `EggConfig` hat pro Ei nur noch eine Rarity-Verteilung (`RARITY_DIST`). Die `hatchTable` wird daraus berechnet (Gewicht 3 für den passenden Pfad, sonst 1). `eggSource` wird ebenfalls berechnet.
- Neuer Spielstand-Teil `eggTree` (frei, Hatch-Zähler, gepresst, Blaupausen, Bypass). Er liegt außerhalb der Insel und übersteht Rebirths.
- Migration v14: Knoten werden frei, wenn das Ei schon im Lager liegt. In Studio getestet: Goldenes Ei, Kristall-Ei und Ascension waren danach frei.

**WP2 Ei-Logik** (`EggTree.luau`, `EggTreeService.luau`)
- Jedes geöffnete Ei zählt. Freischaltung wird bei jeder Datenänderung geprüft, dazu kommt ein Toast „Ei-Baum: X freigeschaltet!“.
- Lege-Fallback: Ein gesperrtes Ei wird zum nächsten freien Vorgänger im selben Pfad. Beim Kometen-Ei ist das das beste freie Endei.
- Void-Identität: Void-Bärchis haben eine Chance, dass ein gelegtes Ei eine Stufe aufsteigt (Phantom 25 %, Eklipse 12 %, Void 8 %). Dabei läuft die Phantom-Omen-Show.

**WP3 Rebirth**
- Meilensteine liefern alle vier Ascensions-Eier (`REBIRTH_MILESTONES`). Bei Rebirth 15, 30 und 50 wird der Knoten zusätzlich freigeschaltet.
- Kurve ab Rebirth 6: Die Kosten steigen pro Rebirth ×1,13, der Multiplikator ×1,12. Rebirth 1 bis 5 bleiben wie bisher.
- **Neu:** Beim Rebirth bleiben alle Eier im Lager erhalten. Bisher blieben nur die Ascensions-Eier. Eier, die noch auf dem Plot liegen, wandern ins Lager.

| Rebirth | Kosten | Multi danach |
|---|---|---|
| 5 | 1.000.000 | ×8 |
| 10 | 1.840.000 | ×14,1 |
| 25 | 11.500.000 | ×77 |
| 50 | 245.000.000 | ×1.310 |
| 100 | 110.000.000.000 | ×379.000 |

**WP4 Simulation** (`tools/sim/egg_tree_sim.lua`)
- Die Platzhalter-Hatch-Zahlen waren zu klein. Ohne Rebirth-Gates war der ganze Baum nach etwa 16 Spielstunden frei. Deshalb sind die Zahlen angehoben (Platin 25, Zenit 40, Abyss 40, Komet je 30, Nova 120, Galaxie 200). Jetzt braucht das Eiersammeln etwa die Hälfte bis zwei Drittel der Zeit bis zum jeweiligen Rebirth-Gate.
- Ergebnis bei 2 Stunden pro Tag, Level 12, Rebirth 5 nach 8 Spielstunden (Annahme):

| Knoten | Spieltag |
|---|---|
| Golden, Nebel | 1 |
| Platin, Kristall | 2 |
| Void | 4 |
| Sonnen | 5 |
| Zenit, Aurora, Schatten | 13 |
| Abyss | 19 |
| Komet | 25 |
| Nova | 42 |
| Galaxie | 77 |
| Omega | etwa 180 |

- Prüfskript `tools/sim/egg_tree_check.lua` prüft:
  - jede Verteilung ergibt 100 %,
  - der Durchschnitt (Ø) steigt entlang jeder Kante,
  - das Kometen-Ei liegt über allen drei Endeiern,
  - jeder Bärchi fällt aus mindestens einem Ei,
  - jede Fähigkeit hat eine eigene Show mit Sound,
  - der Fallback landet immer auf einem freien Ei.
- Alle Prüfungen sind grün.

**WP5 Ei-Baum-Panel** (`EggTreePanel.luau`, Menü-Kachel „BAUM“, Knopf im Eier-Fenster)
- 20 Knoten mit Linien, Pfad-Reihen mit Ziel, Status (frei, gesperrt, bereit).
- Detail-Karte mit Fortschrittsbalken je Bedingung, Lagerbestand, Öffnen, Pressen, Blaupause und Drop-Vorschau. Unentdeckte Bärchis erscheinen als „???“.
- In Studio angeklickt und geprüft, keine Fehler.

**WP6 Pfad-Profile** (`tools/sim/path_balance.lua`, grün)
- Gold ist in jeder Rarity der stärkste, Kristall der schnellste (SPD und Eier pro Stunde), Void der seltenste (Ø Rarität der gelegten Eier). Kein Pfad gewinnt alle drei Ziele.
- Bestehende Bärchis, die angepasst wurden:
  - Kristall-Bärchi wird Glaskanone: 165 HP, SPD 1,45.
  - Goldener Grizzly: 420 / 40 / 0,85.
  - Void-Bärchi: 290 / 32 / 1,05.
  - Regenbogen: 440 / 54 / 1,5.
  - Uralter: 1000 / 56.
  - Kosmischer Bärchi heißt jetzt „Sternen-Bärchi“: 1100 / 80 / SPD 1,25.

**WP7 Kampf** (`CombatCalculator.luau`)
- Der Kampf läuft auf einer Zeitachse. SPD zählt jetzt: Wer doppelt so schnell ist, schlägt doppelt so oft zu.
- Echte Status-Effekte: Schild, Brand, Verlangsamen, ATK senken, Buff, Betäuben, Letzte Chance, Heilen, Lebensraub, Finisher, Eröffnung, Aufbau und Salve. Vorher hatten Schild, SpeedBuff, DoT und AoE gar keine Wirkung.
- Runden-Log je Aktion, serverseitig. Der Client bekommt pro Stage `skillUses` und `firstSkillRound`.
- Die Gegner-SPD wächst mit der Stage (+0,02), wie die SPD der Bärchis mit dem Level. Vergleich alt gegen neu für die 12 bestehenden Bärchis: höchstens ±5 Stages. Der Rote Bärchi weicht um höchstens 1 ab.

**WP8/WP9 SkillFX** (`SkillFXConfig.luau`, `SkillFXController.luau`)
- Baukasten mit 21 Bausteinen. Jede der 28 Fähigkeiten ist eine eigene Komposition mit 4 Spektakel-Stufen.
- Im PIT läuft die volle Show beim ersten Einsatz eines Laufs, danach nur ein kurzes Echo.
- Kamerafahrt gibt es nur auf Stufe 4 und nur für den Besitzer, höchstens 2,5 Sekunden. Farbfilter und Blitz sieht nur der Besitzer, Zuschauer sehen die Welt-Effekte.
- Das Partikel-Budget richtet sich nach der Grafikstufe.
- In Studio getestet:
  - PIT-Lauf mit Big Bang: Show lief, keine Fehler.
  - Omega, Komet, Phoenix, Gletscher, Titan-Modus und Splitterhagel direkt abgespielt: Die Kamerafahrt springt sauber zurück.
- Sounds sind eingebaute Roblox-Klänge, jeder in Studio geladen und geprüft. `swoosh.wav` gibt es nicht und wurde ersetzt.

**WP10 Events**
- Hot Egg gibt dein höchstes freies Ei.
- Königshügel gibt ein Sprung-Ei mit 10 % Chance auf eine Blaupause.
- Schatzgräber: ab 1 Fund dein höchstes Ei, ab 3 Funden 2 davon, ab 5 Funden ein Sprung-Ei plus Blaupausen-Chance.
- Notfall-Ei: 5 % Chance bei jeder Ei-Belohnung.

**WP11** Debug-Befehle: `tree`, `unlock`, `hatched`, `blueprint`, `useblueprint`, `press`, `setrebirth`, `skilltest`, `snapshot`, `restore`. Lokalisierung ist in DE, EN, FR und ES vollständig (`check_loc` grün). Alle bisherigen Tests sind grün; 3 veraltete Menü-Erwartungen im Client-Test habe ich korrigiert.

## Annahmen (von mir, änderbar)

- **Notfall-Ei:** Es gibt ein Basis-Ei *zusätzlich*, nicht statt des eigentlichen Eis. Änderbar in `EventConfig`.
- **Ascensions-Ei:** Es wird auch vor Rebirth 1 gelegt, wenn ein Bärchi es würfelt (wie bisher). Die anderen Eier gelten erst nach Freischaltung.
- **Fusions-Art:** Das Ergebnis hat die Art des Bärchis mit dem höheren Level.
- **Kamera:** Kamerafahrt nur auf Stufe 4. Abschaltbar mit `SkillFXConfig.CINEMATIC_CAMERA`.
- **Balance-Anpassungen:**
  - SugarStorm: Multiplikator 0,8 → 1,4.
  - BlackHole: Multiplikator 1,5 → 2,4. Beide AoE-Skills haben im 1-gegen-1 vorher praktisch nichts gemacht.
  - SugarRush: Cooldown 3 → 4.
  - FireBite: Der Brand skaliert jetzt mit ATK.

## Offen / bekannt

- **Nicht-Schaden-Fähigkeiten:** 9 von 28 statt 7. Grüner Bärchi (Gummischild) und Gelber Bärchi (Zuckerrausch) hatten schon vorher solche Skills. Laut Konzept bleiben bestehende Skills unverändert.
- **PIT bei hohen Rarities:** Hohe Rarities stoßen schon auf PIT 1 an die 60-Stage-Grenze. Auf PIT 8 reichen sie weiter. Für Divine bis Omega fehlt eine eigene Herausforderung.
- **Modelle:** Die 16 neuen Bärchis nutzen das eingefärbte Grundmodell.
- **Studio-Testdaten:** Ein Test vor dem Snapshot hat dem Studio-Spielstand 15 Zucker-Bärchis, 15 Zucker-Eier, 5 Goldene Eier und 1 Nebel-Ei gegeben. Außerdem hat er das Nebel-Ei und (per Blaupause) das Platin-Ei freigeschaltet. Alles danach wurde zurückgesetzt.
- **Rojo:** Während des Playtests hat Rojo nicht mehr synchronisiert. Die letzten zwei Änderungen (DebugService, SkillFXConfig) habe ich direkt in Studio eingetragen. Studio und Festplatte sind identisch, per Prüfsumme kontrolliert.
- **Git:** Kein Git-Commit auf dem PC, dafür hatte ich keine Shell.
- **Rebirth-Tempo:** Ist eine Annahme. Die echten Zeiten muss ein Playtest zeigen.
