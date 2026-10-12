# Architektur-Check – Stand 12.10.2026 (`main` @ 9cc3159)

Geprüft: `src/` (≈ 70 000 Zeilen Luau, 43 Server-Services, 29 Client-Controller,
44 UI-Module, 29 Configs, 27 geteilte Module), Abhängigkeitsgraph, Remotes,
Projektregeln. Maßstab: KISS, YAGNI, DRY, Single Responsibility, Schichtung,
Single Source of Truth, „Tell, don't ask“, Testbarkeit.
Es wurde **nichts am Code geändert** – dieser Bericht ist eine Liste.

## Gesamturteil

Die Architektur ist solide und für ein Roblox-Projekt überdurchschnittlich sauber.
Die Funde sind fast alle **lokal** (kleine Doppelungen, tote Reste), keine
strukturellen Brüche.

Stark:
- **Ein Startpunkt, drei Phasen** (`GameManager`: laden → `init` → `start`). Reihenfolge egal, kein Service startet einen anderen.
- **Keine require-Zyklen** im Server (geprüft per Graph). Wo ein Zyklus drohte, gibt es eingehängte Rückrufe (`MapService.setEggCollectHandler`, `PlayerService.setDailyViewProvider`) – sauberes Dependency Inversion.
- **Schichtung hält**: `shared` requiret nie `server`/`client`, `client` nie `server`.
- **Ein Eingang für Client-Anfragen**: alle Remotes laufen über `RateLimiter.connect`, kein einziges `OnServerEvent` ist direkt verbunden.
- **Server autoritativ**: Währungen werden nur in `EconomyService` geschrieben (geprüft, keine Ausnahme außer Migration/Debug).
- **Ein Client-Speicher**: nur `ClientState` hört auf `PlayerDataUpdated`, 36 Module lesen dort.
- **Daten getrennt von Ablauf**: Werte in `Config/*`, reine Regeln in `Modules/*` (testbar ohne Studio).
- Kopfkommentare je Modul („Einzige Zuständigkeit“, „Warum“) sind vorbildlich.
- Alle Prüfskripte grün (`check_feedback/members/consistency/loc/decor`).

## Funde

Priorität: **A** = bald machen (Fehlerquelle), **B** = beim nächsten Anfassen, **C** = aufräumen, wenn Zeit ist.

### 1. DRY – doppelt geschriebene Funktionen

| Prio | Was | Wo | Vorschlag |
| --- | --- | --- | --- |
| A | **Recycle-Wert** doppelt: Server rechnet `getBaerchiBaseValue × RECYCLE_RETURN` mit `math.floor`, die UI rechnet dieselbe Formel selbst nach. Der Kommentar in `RecycleService` sagt „damit die UI denselben Wert anzeigt“, der Client kann den Service aber gar nicht requiren. | `RecycleService.luau:40`, `BaerchiPanel.luau:431` | `EconomyConfig.getRecycleValue(baerchi)` in `shared`, beide Seiten rufen nur das. |
| B | **Plot-Besitzer suchen** (Attribut nach oben suchen), 6 Kopien unter 3 Namen | `CombController:130`, `EggTimerController:67`, `WorldController:369`, `IncubatorController:41`, `AreaSignController:47`, `UpgradeHintController:40` | Ein Helfer `PlotOwner.of(instance)` / `PlotOwner.isOwn(instance)` (z. B. in `ClientState` oder einem kleinen Modul). |
| B | **`fail()`** in 18 Server-Modulen fast gleich, aber uneinheitlich: mal `LocMsg`, mal `LocMsg \| string`, mal nur Schlüssel, mal fester Action-Name | u. a. `RebirthService:62`, `ShopService:47`, `HomeService:31`, `CombatService:81`, `EggService:43` | Eine Funktion `Remotes.fail(player, action, reason: LocMsg)` (bzw. in `RateLimiter`). Rohe Strings dann nicht mehr erlaubt → passt zur Regel „Texte nur über Loc“. |
| B | **Namen** an `Names` vorbei: `Loc.t("rarity." .. x)` 9×, obwohl `Names.rarity` existiert; `towerName` 3× lokal, `Names.tower` fehlt | `HatchAnimation:424`, `FusionPanel:150/164`, `BaerchiInventory:229`, `ProfilePanel:40`, `IncubatorPanel:232/294`, `IncubatorController:224`, `EggTreePanel:153`; `TerminalController:73`, `CombatPanel:83`, `TowerPanel:122` | `Names.tower(id)` ergänzen, alle Stellen auf `Names.*` umstellen. |
| C | `eggName()` 3× lokal, ist nur `Names.egg` und enthält eine **unbenutzte Zeile** `local def = EggConfig.data[...]` | `IncubatorController:183`, `IncubatorPanel:56`, `EggTreePanel:147` | Direkt `Names.egg` aufrufen. |
| C | `footPosOf()` 3× als reiner Durchreicher zu `FigurePlacement.footOf` | `BaerchiAutopilotService:61`, `EventParticipationService:180`, `EggLayService:99` | Direkt `FigurePlacement.footOf` aufrufen. |
| C | Zeit „m:ss“ 3× von Hand | `EventService:84`, `EggTimerController:91`, `PetBar:99` | `Loc.formatClock(seconds)` neben `Loc.formatDuration`. |
| C | `newPart()` 3× eigen, obwohl es `MapParts.newPart` (Server) und `WorldFXKit.part` (Client) gibt | `EggMerchantService:49`, `AmbienceController:60`, `SkillFXController:83` | Die vorhandenen Bausteine nutzen. |

### 2. YAGNI – Totes und Vorgehaltenes

| Prio | Was | Wo |
| --- | --- | --- |
| B | **Remote ohne Empfänger**: `EventPresenceChanged` wird 7× gefeuert, kein Client hört zu → Netzverkehr ohne Wirkung. | `EventParticipationService:176` |
| B | **Remote ohne Sender**: `RequestCollectEgg` hat einen Server-Handler, der Client feuert ihn nie (Einsammeln läuft seit Touch über `MapService`). Offene, ungenutzte Angriffsfläche. | `EggLayService:454`, `Remotes.luau:289`, `NetworkConfig:55` |
| B | **37 von 38 FeatureFlags stehen auf `true`**, jeweils mit dem alten Weg noch im Code (z. B. `HONEY_POND_V2` → Stock/Veredler 8 Stellen, `TOWER_PANEL_V2` → altes `CombatPanel` baut weiter ein unsichtbares Fenster). Flags sind gut für die Einführung, auf Dauer verdoppeln sie jede Stelle. | `FeatureFlags.luau` |
| C | `PACING_V2` wird nirgends abgefragt (toter Schalter). | `FeatureFlags.luau:70` |
| C | `DebugService` requiret 30 Services – okay, weil nur in Studio, sollte aber nie Spiellogik enthalten, die anderswo fehlt. | `DebugService.luau` |

Vorschlag für die Flags: Wenn ein Paket in Studio abgenommen ist, den Schalter
**ausbauen** (alten Weg löschen) – erst nach Sicherung/Tag, weil die
Projektregel „nichts löschen“ gilt. Bitte dafür eine bewusste Entscheidung treffen.

### 3. KISS / Single Responsibility

| Prio | Was | Wo | Vorschlag |
| --- | --- | --- | --- |
| B | `Network/Types.luau` enthält neben Typen auch **Logik** (`createDefaultPlayerData`, requiret `FeatureFlags` und `HoneyPondMode`). Ein Typ-Modul sollte nichts tun. | `Types.luau:988–1144` | `Modules/DefaultData.luau`. |
| B | **137 `:: any`-Casts**, ein Teil davon unnötig: `(data :: any).shop`, `.uiSeen`, `.indexClaimed` … obwohl diese Felder im Typ `PlayerData` stehen. Jeder Cast schaltet `--!strict` an dieser Stelle aus. | v. a. `PlayerService:372`, `PlayerMigration` (25, dort berechtigt), `DebugService` (15) | Casts außerhalb der Migration entfernen. |
| B | `CombatPanel` hat zwei Aufgaben: altes Tower-Fenster **und** Kampf-/Meilenstein-Meldungen. Mit `TOWER_PANEL_V2` lebt es nur noch wegen der Meldungen. | `CombatPanel.luau:359` | Meldungen in eigenes Modul (z. B. `CombatFeed`), Fenster dann entfernbar. |
| C | Sehr große Module: `SkillFXController` 2420 Z., `EventParticipationService` 1364, `DebugService` 1289, `EventHandlers` 1246, `MapService` 1054 (51 Funktionen). Kein Fehler, aber schwer zu überblicken. | | Beim nächsten Umbau aufteilen (z. B. SkillFX-Bausteine ↔ Ablauf). |
| C | `MapConfig.luau` hat **192 von 200** erlaubten lokalen Namen – die nächsten paar Konstanten brechen das Modul in Roblox. | `MapConfig.luau` | Konstanten in Untertabellen gruppieren, bevor es knallt. |
| C | Zwei UI-Bibliotheken nebeneinander: `Theme` (42 Nutzer) und `Kit`/`Theme.v2` (3 Nutzer). Gewollt als Übergang, darf aber nicht dauerhaft bleiben. 27 feste `Color3.fromRGB` in 11 UI-Modulen umgehen beide. | `UI/Theme`, `UI/Kit` | Panels schrittweise auf `Kit` umstellen, feste Farben in Tokens. |

### 4. Kommunikation Server ↔ Client

- **Vollbild statt Änderung**: Jeder `markDirty` (72 Aufrufstellen) schickt den kompletten Spielerzustand inkl. aller Bärchis. Das ist bewusst einfach (KISS) und bei der aktuellen Größe in Ordnung. Wenn es später ruckelt: mehrere `markDirty` im selben Frame zu einem Senden zusammenfassen (`task.defer`), bevor man an Deltas denkt.
- **Fehlerwege einheitlich**: `ActionFailed(action, reason)` ist ein guter, einziger Kanal. Uneinheitlich sind nur die `action`-Namen (`CombatService` meldet alles als `"RequestPetMode"`); bisher wertet nur `HatchPanel` den Namen aus, deshalb harmlos.
- **Lücken**: siehe die beiden Remotes in Abschnitt 2. Sonst hat jeder Remote Sender und Empfänger.

### 5. Weitere Regeln aus der Literatur

| Regel | Stand |
| --- | --- |
| **Dependency Inversion / keine Zyklen** | erfüllt (Rückruf-Einhängen statt Gegen-require). |
| **Law of Demeter** | meist erfüllt; Services greifen aber direkt tief in `data.island.baerchis[...]`. Bewusste Entscheidung („Daten direkt ändern, dann `markDirty`“) – einfach, aber jeder Service kennt das ganze Datenschema. |
| **Single Source of Truth** | gut (Configs, `Names`, `BaerchiConfig.RARITY_COLORS`); Ausnahmen siehe Abschnitt 1 (Recycle-Wert, Namen). |
| **Fail fast** | gut (`FeatureFlags.isOn` bricht in Studio bei Tippfehlern ab, `getDataOrError`). |
| **Testbarkeit** | reine Regeln in `Modules/*` sind getestet (23 Tests, 11 Sims). Services selbst sind ungetestet; Logik, die dort steckt (z. B. Event-Belohnungen), gehört mittelfristig in ein reines Modul. |
| **Automatisierte Prüfung** | Es gibt kein CI (`.github/` fehlt). Die Prüfliste aus `CLAUDE.md` läuft nur von Hand. Ein GitHub-Actions-Workflow mit `luau-compile`, `check_*.py` und den Tests würde jeden PR automatisch prüfen. |

### 6. Repo-Hygiene

- Im Wurzelordner liegen versehentlich: eine Datei namens **`--help`** (enthält die HTML-Deko-Vorschau) und **`lz4-4.4.5-…whl`** (1,4 MB Python-Paket).
- Berichte liegen an drei Orten: `docs/`, `claude/`, `OPUS_PROMPT_ROADMAP.md` im Wurzelordner.
- Generierte Dateien eingecheckt: `updates/*.rbxmx` (4 MB), `studio_export/*.rbxlx` (2,5 MB). Für den Studio-Weg ohne Rojo gewollt, sie wachsen aber mit jedem Stand in der Git-Historie.

## Empfohlene Reihenfolge

1. Recycle-Wert in `shared` (A, 10 Min).
2. Die zwei toten Remotes entfernen, `PACING_V2` klären (B, 15 Min).
3. `fail()` vereinheitlichen, `Names.tower` + Namen umstellen, Plot-Besitzer-Helfer (B, je ~30 Min).
4. Unnötige `:: any` entfernen, `createDefaultPlayerData` aus `Types` herausziehen (B).
5. CI-Workflow für die Prüfliste (B).
6. Für abgenommene Pakete Flags ausbauen; `MapConfig` entlasten (C).
