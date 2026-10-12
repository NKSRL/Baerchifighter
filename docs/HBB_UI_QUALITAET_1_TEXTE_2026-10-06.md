# UI-Qualität, Schritt 1: Prüf-Tor + alle Spieler-Texte übersetzt (06.10.2026)

Ziel: Menüs (die Fenster hinter den Knöpfen) und alles, was der Spieler liest,
dauerhaft in Ordnung halten — nicht durch einmaliges Aufräumen, sondern durch
eine Prüfung, die jeden Rückfall vor dem Commit meldet.

## Was das Problem war

| Ursache | Beispiel | Umfang |
|---|---|---|
| Feste Texte in Menüs | „Fusion“, „Battle Charms“, „Zurueck“, „Zustand“, „Ausruesten“ | ~100 Stellen in 20 Client-Dateien |
| Config-Texte direkt angezeigt (immer Deutsch) | Skill-/Ei-/Bärchi-Beschreibungen, Event-Namen, Gebäude-Effekte, Charm-Werte | 34 Lesestellen, 150 Texte ohne Schlüssel |
| Server schreibt fertige deutsche Sätze in die Welt | Arena-/Event-Tafel, Gebäude-/Recycler-Schild, Namensschild der Figuren, „ENTFUEHRT!“, Händler-Prompt | ~40 Stellen; **jeder** Spieler sah sie auf Deutsch |
| Event-Meldungen als fertige Strings | „UFO: Dein Baerchi wird entfuehrt!“, „+1x Goldenes Ei (Sprung-Ei!)“ | ~25 Stellen |
| `check_loc.py --todo` rät per Signalwort | „Zustand“, „Kampf gewonnen!“, `section("…")`, `paint(…)` blieben unsichtbar | — |

Nebenbei gefunden (echter Fehler): der Ergebnis-Bildschirm der **Fusion** las
`levels.def` — das Feld gibt es seit dem Wegfall der Verteidigung nicht mehr,
`string.format("%d", nil)` brach ab, der Ergebnis-Bildschirm erschien nie.
Jetzt zeigt er die fünf echten Stat-Stufen (HP/ATK/SPD/PWR/EGG).

## Was jetzt gilt

1. **`tools/check_ui.py`** (neu, Exit 1 bei Funden) — Regeln T1–T5, P1–P2,
   Beschreibung in `tools/README.md`. Erkennt Text-Senken auch über
   Hilfsfunktionen und Modulgrenzen hinweg (`section(...)`, `paint(...)`,
   `EventKit.setLabel`, `MapService.setPitBanner`, lokale Aliase) und prüft,
   dass jeder `Loc`-Aufruf alle `{platzhalter}` übergibt (455 Aufrufe).
   Ausnahme nur mit `-- ui-ok: <Grund>` (zwei Stück: BaerchiPanel-Hülle →
   Schritt 2; Ei-Baum-Leinwand scrollt XY).
2. **`Localization/Names`** (neu) — einziger Leser von `displayName`,
   `description`, `drawback`, `shortName`. Deutsch bleibt als Rückfall in den
   Configs stehen. `Names.msg.*` liefert dieselben Namen als Nachricht für
   den Server.
3. **`Localization/WorldText`** (neu) — Server-Texte in der Welt: der Server
   hängt die Nachricht (`Loc.msg`) als Attribut `Loc_Text` /
   `Loc_ActionText` / `Loc_ObjectText` an und taggt die Instanz `LocText`;
   jeder Client löst sie in seiner Sprache auf (auch beim Sprachwechsel).
   Gestartet in `Main.client.luau` direkt nach dem `LanguageController`.
4. **Event-Belohnungen** sind verschachtelte Nachrichten (`fmt.join`,
   `fmt.append`); `EventStatGain.bonusText` ist `string | LocMsg`, der Client
   nimmt `Loc.resolve`. `EventConfig.describeBonus/describeReward` liefern
   jetzt eine `LocMsg`.
5. **Sprachwechsel bei offenem Menü**: Bärchi-Karte, Inventar, Fusion,
   Charms, Gebäude, PIT-Einstieg, Pet-Leiste und Welt-Prompts beschriften sich
   neu (`Loc.onChanged`/`Loc.bind`).
6. **`luau-tests/ui_texts.test.lua`** (neu) — 996 Laufzeit-Texte in
   de/en/fr/es: kein `[schlüssel]`, kein `{platzhalter}`, keine vergessene
   deutsche Übersetzung.
7. Sprachdateien: +334 Schlüssel je Sprache (de/en/fr/es, Abschnitte
   „UI-Qualitaet: …“ am Dateiende). Deutsche Texte jetzt mit Umlauten.
8. Icon-Rückfall „EI“ (deutsch) → 🥚.

## Prüfstand (alle grün)

`luau-compile` aller Dateien, `check_locals.py` (max. 191), die drei
`luau`-Tests, alle elf `run_local`-Tests inkl. `ui_texts`, `progression_pacing`,
`tower_calibration`, `check_feedback/members/consistency/loc/ui/decor`.
Gegenprobe: ein eingebauter fester Text bzw. ein fehlender Platzhalter wird von
`check_ui.py` gemeldet.

## In Studio bringen (Option B, von Hand)

Neu anlegen (ModuleScript):
- `ReplicatedStorage/Localization/Names`
- `ReplicatedStorage/Localization/WorldText`

Ersetzen: alle vier `ReplicatedStorage/Localization/Strings/*`,
`ReplicatedStorage/Network/Types`, `ReplicatedStorage/Config/{BuildingBehavior,
CharmConfig, EventConfig}`, `StarterPlayerScripts/Main`,
`StarterPlayerScripts/Controllers/{EggTimerController, WorldController}`,
`StarterPlayerScripts/UI/{BaerchiInventory, BaerchiPanel, BuildingPanel,
CharmPanel, CombatPanel, EggTreePanel, Feedback, FusionPanel, HatchAnimation,
HatchPanel, IndexView, LeaderboardPanel, PetBar, PitResumeDialog, ProfilePanel,
QuestTracker, RebirthDialog, ReturnSummary}`,
`ServerScriptService/Services/{DebugService, EggMerchantService,
EventHandlers, EventParticipationService, EventService, MapService,
PetModeService, PitArenaService, PlotDisplayService}`,
`ServerScriptService/Util/EventKit`,
`ServerScriptService/Util/MapBuild/{ArenaBuilder, FigureBuilder,
LaidEggBuilder, PlotBuilder, RecyclerBuilder}`.

## Studio-Testschritte

1. Sprache auf Französisch stellen (Globus oben): Bärchi-Karte, Inventar,
   Fusion (bis zum Ergebnis-Bildschirm!), Charms, Gebäude, Eier, Ei-Baum,
   PIT-Einstieg — kein deutsches Wort mehr.
2. Mit offenem Menü die Sprache wechseln: Texte ändern sich sofort.
3. Welt: Arena-Tafel während eines Laufs, Event-Tafel (Countdown, Belohnung),
   Gebäude-/Recycler-Schild, Namensschild über dem Bärchi, Beschriftung über
   gelegten Eiern, Händler-Prompt — alles in der gewählten Sprache. Zwei
   Spieler mit verschiedenen Sprachen sehen dieselbe Tafel jeweils in ihrer.
4. Ein Event mitmachen (UFO/Schatzgräber): Marken über der Figur und Toasts
   übersetzt; Abschluss-Toast „… terminé : …“.
5. Ausgabe-Fenster: keine `[Loc] Schluessel fehlt`-Warnungen.

## Nächster Schritt (2)

`Theme.dialog`/`dialogHeader`/`dialogBody` mitskalieren lassen (Kopfzeile,
Schließen-X mind. 44 px, Abstände), BaerchiPanel auf `Theme.dialog` umbauen
(dann entfällt die P1-Ausnahme), danach UI-Prüfstand in Studio
(Auflösungen × Sprachen × Zustände, automatische Überlauf-/Überlappungs-Funde).
