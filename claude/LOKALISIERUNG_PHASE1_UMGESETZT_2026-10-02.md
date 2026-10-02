# Lokalisierung (DE / EN / FR / ES) — Phase 1 umgesetzt (02.10.2026)

Ausgangsstand: Commit `9407ab3` auf GitHub (`NKSRL/Baerchifighter`, `main`) — der
komplette Stand vor dieser Änderung. Wer etwas zurückdrehen will, geht dorthin.

## Ziel und Grundregeln

Das Spiel läuft in der Sprache des Spielers: erst seine gespeicherte Wahl, sonst
die Roblox-Sprache seines Clients (`Player.LocaleId`), sonst Englisch. Unterstützt
sind Deutsch, Englisch, Französisch, Spanisch. Weitere Sprachen brauchen nur eine
neue Datei (siehe unten).

Vorgabe des Projektinhabers: **Architektur-Grundsätze einhalten, und das Spiel darf
nie laggy werden.** Das hat die Bauweise bestimmt.

## Architektur

```
src/shared/Localization/
  Loc.luau                  Einzige Zuständigkeit: Schlüssel + Argumente → Text
  Strings/de|en|fr|es.luau  Flache Tabellen { ["schluessel"] = "text" }
src/client/Controllers/LanguageController.luau   Welche Sprache gilt; Wahl an den Server
src/client/UI/LanguagePanel.luau                 Auswahl-Fenster (Knopf "DE" unter den Währungen)
src/server/Services/SettingsService.luau         Speichert die Wahl (data.language), nichts sonst
```

**Der Server formuliert nie einen Satz.** Er schickt `Types.LocMsg = { k, a }`
(Schlüssel + Zahlen/Namen). Der Client baut daraus den Text. Dadurch braucht der
Server keine Sprachtabellen, und eine Meldung erscheint in der Sprache, die der
Spieler *im Moment der Anzeige* eingestellt hat. Alle 67 `ActionFailed`-Stellen
(Rebirth, Recycle, Charms, Honig, Promotion, Event, Kampf, Fusion, Eier, Gebäude,
PIT, Ausrüsten) sind umgestellt. Ein einfacher String wird weiter unverändert
angezeigt (Altlast-Pfad), es bricht also nichts, was noch nicht umgestellt ist.

Argumente dürfen selbst Nachrichten sein: `Loc.msg("err.promo_need_material",
{ name = Loc.msg("baerchi.RedBaerchi.name"), ... })` — der Server nennt nur die
ID, der Client setzt den Namen in seiner Sprache ein.

### Wie ein Text aussieht

```lua
["err.not_enough_gummies"] = "Nicht genug Gummies (du hast {have}, du brauchst {need})",
["ui.rebirth.status"]      = "Rebirth {count}  —  Multiplikator x{mult:d2}",
["err.egg_wait"]           = "Noch {seconds:dur} bis das Ei fertig ist",
["msg.rebirth_done_eggs.one"]   = "... {n} Ascensions-Ei",
["msg.rebirth_done_eggs.other"] = "... {n} Ascensions-Eier",
```

* `{name}` — Zahlen bekommen automatisch den Tausendertrenner der Sprache
  (`1.234.567` / `1,234,567` / `1 234 567`).
* `{x:raw}` Zahl unverändert · `{x:dur}` Sekunden als Dauer · `{x:d2}` Dezimalzahl
  (Komma oder Punkt je nach Sprache). **Das Format steht im Text, nicht im Code** —
  eine Sprache kann es anders haben wollen, ohne dass ein Aufrufer etwas weiß.
* Mehrzahl: `Loc.tn("schluessel", n, args)` mit `.one` / `.other` (Französisch zählt
  0 und 1 als Einzahl).
* Namen von Config-Einträgen: `baerchi.<id>.name`, `rarity.<Name>`,
  `mutation.<id>.name`, `egg.<id>.name`, `building.<id>.name|short`, `rank.<tier>`,
  `skill.<id>.name`. `Loc.name(key, fallback)` fällt still auf den Config-Text
  zurück, solange ein Eintrag noch fehlt — so lässt sich schrittweise umstellen.

### Effizienz (die Lag-Regeln)

* Nur die **aktive** Sprache und die Rückfall-Sprachen (EN, DE) liegen im Speicher,
  lazy geladen. Der Server lädt nie Text.
* Ein Nachschlagen = ein Tabellenzugriff; ohne Argumente entsteht gar kein neues Objekt.
* **Keine Schleife, kein Polling.** Beim Sprachwechsel (ein Klick) werden gebundene
  Labels einmal neu beschriftet (`Loc.bind`), dynamische Texte hängen sich mit
  `Loc.onChanged` an und laufen ihre normale `refresh()` noch einmal.
* `LanguageController` vergleicht den Server-Wert nur, wenn er sich ändert — nicht bei
  jedem `PlayerDataUpdated` (das ist häufig).
* **Regel für neue UI:** Texte, die jeden Frame aktualisiert werden, nicht jeden Frame
  aus dem Schlüssel neu bauen, sondern nur wenn sich der Wert ändert (z. B. volle
  Sekunde). Der Ei-Timer macht das schon so (1-Sekunden-Takt).
* Kein neues Remote im Dauerbetrieb: `RequestSetLanguage` feuert nur bei einem Klick
  (Cooldown 1 s, Server whitelistet den Wert).

### Welche Sprache gilt, und warum die Wahl sofort wirkt

1. gespeicherte Wahl (`PlayerData.language`, `nil` = "automatisch")
2. `Player.LocaleId` des Clients (`de-de` → `de`, `es-mx` → `es`, `pt-br` → nicht
   unterstützt → weiter)
3. Englisch

Die Roblox-Sprache wird **vor** dem ersten Server-Sync ausgewertet (kein Aufblitzen
der falschen Sprache). Klickt der Spieler eine Sprache, wechselt die Oberfläche sofort
(reine Darstellungs-Einstellung, keine Spielwerte); ein noch unbestätigter Wert gewinnt
5 s lang gegen ein veraltetes Server-Paket, damit nichts zurückspringt.

Kein Versions-Sprung im Spielstand: `data.language` ist nil-sicher (wie `equippedUid`
in v6), ein alter Spielstand bedeutet automatisch "folge Roblox".

## Was in Phase 1 umgestellt ist

* Kern: `Loc`, vier Sprachdateien (je 120 Schlüssel), `LanguageController`,
  `LanguagePanel`, `SettingsService`, Remote `RequestSetLanguage`.
* `Types`: `LocMsg`/`LocArg`, `PlayerData.language`, `PlayerDataUpdate.language`.
* Alle abgelehnten Aktionen (siehe oben) in 12 Services + `EconomyService`
  (Rückgabewerte `(boolean, Types.LocMsg?)` statt `(boolean, string)`; Erfolg gibt
  `true` ohne Dummy-String zurück).
* `Theme.formatNumber` / `formatDuration` → delegieren an `Loc` (dadurch sind
  **alle** Zahlen im Spiel sofort sprachrichtig, auch in den noch nicht umgestellten
  Panels).
* UI: `Toast`, `Hud` (Rangname, Multiplikator, Sprach-Knopf), `MenuBar`,
  `RebirthDialog`, `ResultFeed`, `EggTimerController`.
* Namen bereits übersetzt hinterlegt (noch nicht überall eingebunden): Raritäten,
  12 Bärchis, 8 Mutationen, 5 Eier, 3 Gebäude, 5 Ränge, 9 Skills.

## Prüfungen (laufen ohne Studio)

* `python3 tools/check_loc.py` — Vollständigkeit aller vier Sprachen, gleiche
  Platzhalter, alle im Code verwendeten Schlüssel vorhanden. Meldet außerdem die
  noch festen Textstellen (`--todo`).
* `tools/luau-tests/` (Node.js, `npm install`): `check_syntax.mjs` kompiliert alle
  68 Dateien mit dem echten Luau-Parser (0 Fehler); `loc.test.lua` testet `Loc`
  (Zahlenformat je Sprache, Mehrzahl, Rückfall, verschachtelte Namen);
  `client.test.lua` fährt Toast, HUD, Menüleiste, Rebirth-Dialog und Sprach-Fenster
  mit Mock-Roblox durch (Roblox-Sprache erkannt, Wechsel, Server-Bestätigung,
  veralteter Server-Stand, "Automatisch").
* Bestehende Prüfungen `check_members.py` und `check_consistency.py`: grün.

**Nicht geprüft** (geht nur in Studio): die Typprüfung `--!strict`, das tatsächliche
Aussehen, Textlängen in den Layouts.

## In Studio testen (Checkliste)

1. Rojo wie gewohnt synchronisieren. Im Output darf `[Loc] Schluessel fehlt` nicht
   auftauchen.
2. Knopf **"DE"/"EN"/…** unter den Währungs-Pillen links oben → Fenster → alle vier
   Sprachen + "Automatisch". Beschriftung der Menüleiste rechts und der HUD-Rang
   wechseln sofort.
3. **Umlaute und Akzente** in der Schrift FredokaOne prüfen: `ä ö ü ß`, `é è ê à ç î`,
   `ñ ¿ ¡`. (Das französische `œ` wird bewusst als `oe` geschrieben.) Erscheint
   irgendwo ein Kästchen, bitte melden — dann stellen wir die Schreibweise um.
4. Eine abgelehnte Aktion auslösen (z. B. Rebirth ohne genug Gummies) in jeder
   Sprache → Toast in der gewählten Sprache, Zahlen mit dem passenden Trenner.
5. Spiel verlassen und neu betreten → die Wahl ist noch da. "Automatisch" wählen →
   folgt wieder der Roblox-Sprache.
6. Rebirth-Dialog bei geöffnetem Fenster die Sprache wechseln → Text zieht live nach.
7. Textlängen: im Französischen und Spanischen sind Texte oft 20–30 % länger.
   Rebirth-Dialog und Menüleiste ansehen; zu lange Stellen melden.

## Getroffene Annahmen (bitte bestätigen oder ändern)

* **Standardsprache Englisch**, wenn Roblox eine nicht unterstützte Sprache meldet.
* **Spielbegriffe bleiben in allen Sprachen stehen:** Baerchi, Gummies, GoldGummies,
  PIT, Rebirth. (Ändern = nur die Sprachdateien.)
* **Ränge, Raritäten, Skill-Namen werden übersetzt**, Mutationsnamen teils
  ("Bloodrot", "Candy" bleiben in DE).
* Informelle Anrede (du / tu / tú) in allen Sprachen — passend zur Zielgruppe.
* Neue Texte schreiben **mit** Umlauten (vorher überall `ae/oe/ue`); die Schrift
  unterstützt sie nach bisherigem Wissen — siehe Checkliste Punkt 3.

## Phase 2 — noch offen (nach `check_loc.py --todo`: ~145 feste Textstellen)

Reihenfolge nach Sichtbarkeit für den Spieler:

1. **Namensschilder und Welt-Texte, die der Server baut** (`MapService`,
   `FigureFX`): sie werden an ALLE Spieler repliziert und müssen deshalb auf dem
   Client lokalisiert werden. Plan: der Server setzt nur Attribute (`configId`,
   Level, Mutation), ein kleiner Client-Controller baut daraus den Text pro Spieler —
   per Attribut-Änderung, nie per Schleife. Betrifft auch Gebäude-Schilder, Event-Area,
   PIT-Anzeigen.
2. **Panels:** `BaerchiPanel` (24 Stellen), `BuildingPanel`, `CombatPanel`,
   `FusionPanel`, `BaerchiInventory`, `HatchPanel`, `CharmPanel`, Welt-Prompts in
   `WorldController`.
3. **Config-Texte:** `SkillConfig`, `BaerchiConfig` (Beschreibungen/Skill-Texte),
   `EventConfig` (Event-Namen und -Beschreibungen), `EggConfig`, `BuildingBehavior`,
   `CharmConfig.describe`. Die Anzeigenamen sind teils schon in den Sprachdateien —
   es fehlt das Umstellen der Aufrufer auf `Loc.name(...)`.
4. **Offen zu klären:** `DebugService`-Ausgaben bleiben deutsch (Entwickler-Werkzeug).
   Roblox-eigener Store-Text (Spielname, Beschreibung, Game-Passes) läuft über das
   Creator Dashboard und ist **nicht** Teil dieses Codes.

Jeden Schritt einzeln testen und committen — `check_loc.py` und
`tools/luau-tests` laufen nach jedem.
