# BÄRCHI FIGHTER — Opus-Build-Auftrag (3-Schritt-Roadmap)

> **Wie du das benutzt:** Kopiere dieses ganze Dokument in eine neue Claude-Session mit
> Modell **Opus** und Zugriff auf den Ordner `C:\Users\youpa\Documents\Claude Downloads\RBL`.
> Sag Opus dabei explizit, **welchen Schritt** (1, 2 oder 3) es jetzt bearbeiten soll — jeder
> Schritt ist einzeln beauftragbar. Nach jedem Schritt: in Studio testen (`rojo build` /
> `rojo serve`), erst dann den nächsten Schritt starten.
>
> **AUFTRAG FÜR DIESEN LAUF:** _[hier eintragen: "Bearbeite Schritt 1" / "Bearbeite Schritt 2" / "Bearbeite Schritt 3"]_

---

## 1. Projektkontext (Pflichtlektüre für Opus)

**Was für ein Spiel:** Ein Idle-/Kampf-Spiel im Stil von "Grow a Chicken Fighter", Thema
Bärchis ("Baerchis") statt Hühner. Spieler hatchen Eier zu Bärchis (Gacha), leveln sie hoch,
lassen sie in einer Kampfgrube ("PIT") gegen Gegner kämpfen, verdienen Gummies/GoldGummies,
upgraden Gebäude auf ihrer Insel, machen irgendwann Rebirth für einen Dauer-Multiplikator.
Bis zu 8 Spieler gleichzeitig, jeder mit eigener Insel in einem Ring um eine zentrale
Event-Insel, alles über einer Wasserfläche.

**Tech-Stack:** Rojo 7.7.0 (via Aftman), Luau mit `--!strict` überall, `DataStoreService`
für Persistenz, `RemoteEvent`/`RemoteFunction` für Client-Server-Kommunikation.

**Ordnerstruktur (aktuell):**
```
RBL/
  default.project.json    -- Rojo-Mapping: src/shared→ReplicatedStorage, src/server→ServerScriptService, src/client→StarterPlayerScripts
  aftman.toml
  src/
    client/
      init.client.luau     -- NUR "Hello world" — hier fehlt komplett alles
    server/
      init.server.luau     -- NUR "Hello world", startet nichts (GameManager läuft separat als Core-Script)
      Core/
        GameManager.server.luau   -- Boot-Reihenfolge aller Services
      Services/
        MapService.luau
        EconomyService.luau
        EggService.luau
        CombatService.luau
        PlayerService.luau
    shared/
      Config/
        BaerchiConfig.luau   -- 12 Bärchis über 6 Raritäten (Common..Mythic)
        EconomyConfig.luau   -- Rebirth-Kosten/Multi, Gebäude-Upgrades, PIT-Kosten/Rewards, Rang-Tiers
        EggConfig.luau       -- 5 Ei-Typen mit Hatch-Tables
        MapConfig.luau       -- Insel-Positionen, Wasser, PIT-Geometrie
        SkillConfig.luau     -- 13 Skills, 10 EffectTypes
      Modules/
        CombatCalculator.luau  -- reine Kampf-Simulation, rundenbasiert
        GachaRoller.luau       -- gewichtetes Zufalls-Ziehen
      Network/
        Types.luau    -- EINZIGE Quelle aller Datenstrukturen (Baerchi, IslandData, PlayerData, ...)
        Remotes.luau  -- EINZIGE Quelle aller Remote-Namen
```

**Architektur-Prinzipien — zwingend beibehalten, nicht neu erfinden:**
- Ein Service = eine klar benannte Zuständigkeit (steht als Kommentarblock oben in jeder Datei — neue Services folgen dem gleichen Muster).
- Alle Zahlen/Balance-Werte leben in `Config`-Modulen, niemals hardcoded in einem Service.
- `Types.luau` ist die einzige Wahrheit für Datenstrukturen — neue Felder gehören dort rein, inklusive Migration in `PlayerService.applyDefaults`.
- `Remotes.luau` ist die einzige Stelle für Remote-Namen — keine Magic Strings.
- Nur `PlayerService` fasst den DataStore an. Nur `EconomyService` ändert `gummies`/`goldGummies`.
- `GameManager.server.luau` bestimmt die Boot-Reihenfolge — neue Services müssen dort eingetragen werden, Reihenfolge beachten (Abhängigkeiten stehen im Kommentar).
- Kommentare im Code sind durchgehend deutsch — Stil beibehalten.
- `--!strict` in jeder neuen Datei.

**Bereits fertig und funktionsfähig (Server-seitig):**
- Vollständiges Datenmodell + Default-Fabrik (`Types.lua`)
- Insel-Spawning für 8 Spieler im Ring-Layout inkl. Wasserfläche und wachsender PIT-Plattform (`MapService`)
- DataStore laden/speichern inkl. Auto-Save-Loop, Migration alter Daten, Save-on-Leave/Shutdown (`PlayerService`)
- Währungs-Transaktionen mit Validierung + Gebäude-Upgrade-Kauf (`EconomyService`)
- Ei kaufen → Gacha-Roll → neuer Bärchi (aktuell **instant**, kein Timer) (`EggService`)
- Rundenbasierte PIT-Kampf-Simulation gegen generierte Gegner, inkl. XP/Level-Up/Gummy-Reward (`CombatService`, `CombatCalculator`)

**Bekannte Lücken / tote Enden im aktuellen Code (wichtig — nicht übersehen):**
- `Remotes.GetPlayerData` (RemoteFunction) existiert, hat aber **nirgendwo** einen `OnServerInvoke`-Handler → Reconnect-Fall ist kaputt.
- `FusionLab`-Gebäude ist in `EconomyConfig`/`MapConfig` vollständig bepreist, `Types.FusionResult` existiert, `BaerchiConfig` hat extra ein Mythic ("nur durch Fusion erhältlich") — aber es gibt **keinen** FusionService und keine Fusion-Logik irgendwo.
- `EconomyConfig.PIT_UPGRADE_COSTS` und `MapService.updatePitLevel` existieren beide, aber **kein Remote/Service-Call verbindet sie** — ein Spieler kann sein PIT-Level aktuell gar nicht kaufen.
- `Recycler`-Gebäude hat Upgrade-Kosten/Effekt-Texte, aber **keine tatsächliche Recycle-Funktion**.
- Kein Rebirth-Executor, obwohl `EconomyConfig.REBIRTH_COST_GUMMIES`/`REBIRTH_MULTIPLIERS` fertig da sind und `PlayerData` die Felder `rebirthCount`/`rebirthMult` schon führt.
- `EggConfig.hatchTime` wird nirgendwo genutzt — Hatchen ist aktuell instant statt zeitbasiert, obwohl Hatchery-Upgrades explizit "-X% Hatch-Zeit" versprechen.
- Keine passive `GummyFarm`-Produktion trotz Gebäude, das genau dafür da ist ("+N GoldGummy/min" in den Upgrade-Texten).
- `lastSeenAt` wird gespeichert, aber nie für Offline-Progress (Idle-Ertrag während Abwesenheit) verwendet — für ein Idle-Game ein zentrales fehlendes Feature.
- Kein Rate-Limiting auf den `Request*`-Remotes (Spam-/Exploit-Risiko).
- **Client ist komplett leer.** Kein UI, keine sichtbaren Bärchis, keine Möglichkeit für einen Spieler, irgendetwas außerhalb der Studio-Command-Bar zu tun.

---

## 2. Nächster Schritt — Einordnung

Die Server-Architektur ist sauber und konsequent durchgezogen (Config-driven, ein Service =
eine Verantwortung, striktes Typing). Der aktuelle Flaschenhals ist **nicht** fehlender Inhalt,
sondern zwei Dinge: (a) der Spiel-Loop ist serverseitig an mehreren Stellen unvollständig
verdrahtet (Fusion/Rebirth/PIT-Kauf/Recycler/passives Einkommen existieren nur als Zahlen,
nicht als Funktion), und (b) es gibt **buchstäblich keinen Client** — man kann das Spiel
aktuell nicht spielen, nur simulieren. Deshalb ist die Reihenfolge unten bewusst: erst den
Loop backend-seitig schließen (klein, risikoarm, baut auf Bestehendem auf), dann den Client
bauen (größter Umfang, macht das Spiel zum ersten Mal tatsächlich spielbar), dann Content/Polish.

---

## 3. Die 3 Schritte

### SCHRITT 1 — Spiel-Loop im Backend schließen

**Ziel:** Jeder Mechanismus, den Configs/Types bereits *versprechen*, ist über einen Remote
tatsächlich auslösbar und persistiert korrekt — Testbarkeit über Studio Command Bar reicht,
UI kommt erst in Schritt 2.

**Deliverables:**
1. **RebirthService** (neu, `src/server/Services/RebirthService.luau`): `RequestRebirth`-Remote (neu in `Remotes.luau`). Prüft Kosten via `EconomyConfig.getRebirthCost(data.rebirthCount)`, resettet Insel (Bärchis leeren, Gebäude auf Level 1, Gummies auf Start), erhöht `rebirthCount`, setzt `rebirthMult` via `EconomyConfig.getRebirthMult`, vergibt bei sinnvollen Meilensteinen ein `AscensionEgg` ins `eggStock`.
2. **FusionService** (neu): `RequestFuseBaerchis`-Remote, nimmt 2 Bärchi-UIDs. Leite aus `BaerchiConfig` eine sinnvolle Fusionsregel ab (dort gibt es je 2 Einträge pro Rarity Common–Legendary + 1 Mythic "nur Fusion") — z. B. zwei gleiche Rarity + `FusionLab`-Level-Check → ein Bärchi der nächsthöheren Rarity, zwei bestimmte Legendaries → `CosmicBaerchi`. Regel explizit dokumentieren, konsumiert Input-Bärchis, setzt `isFusionResult = true`.
3. **PIT-Level-Kauf**: Neuer Remote `RequestUpgradePit` (oder Erweiterung von `RequestUpgradeBuilding`), zieht Kosten aus `EconomyConfig.PIT_UPGRADE_COSTS`, ruft `MapService.updatePitLevel` und persistiert `island.pitLevel`.
4. **Recycler-Funktion**: `RequestRecycleBaerchi`-Remote, entfernt Bärchi aus `island.baerchis`, gibt Gummies zurück basierend auf Rarity/Level × Recycler-Level-%-Satz (die `effect`-Strings in `EconomyConfig.BUILDING_UPGRADES.Recycler` müssen in echte Zahlen übersetzt werden, nicht nur Anzeigetext bleiben).
5. **Passive GummyFarm-Produktion**: Loop (z. B. alle 60s), die GoldGummies nach `GummyFarm`-Level gutschreibt — Rate ebenfalls aus Text in echte Zahlen übersetzen bzw. eigene Ratentabelle in `EconomyConfig` ergänzen.
6. **Offline-Progress**: beim Join Differenz `lastSeenAt` vs. `os.time()` berechnen, GummyFarm-Ertrag für die Offline-Zeit gutschreiben (gedeckelt, z. B. max. 8–12h, als Konstante konfigurierbar).
7. **Hatch-Timer + Multi-Slot**: `EggConfig.hatchTime` tatsächlich nutzen. Neues Feld in `IslandData` (z. B. `hatchingEggs: {eggType, readyAt}[]`), Gacha-Roll erst nach Ablauf bzw. per Claim-Request. Hatchery-Level bestimmt Slot-Anzahl und Zeit-Reduktion.
8. **`GetPlayerData` implementieren**: `OnServerInvoke`-Handler in `PlayerService` für den Reconnect-Fall.
9. **Rate-Limiting**: einfache gemeinsame Utility für Cooldowns pro Spieler pro Remote, auf alle `Request*`-Events angewendet.
10. **Types.luau erweitern** wo nötig (z. B. `hatchingEggs`), Rückwärtskompatibilität über `PlayerService.applyDefaults` sicherstellen.

**Akzeptanzkriterien:** Jeder in `EconomyConfig`/`EggConfig`/`BaerchiConfig` versprochene Mechanismus ist per Remote auslösbar und persistiert korrekt. Kein Service greift auf Währungsfelder außer über `EconomyService` zu. `GameManager` startet neue Services in korrekter Reihenfolge. `rojo build` kompiliert ohne Fehler, `--!strict` sauber.

---

### SCHRITT 2 — Client: komplettes Spiel-UI von Null

**Ziel:** Ein Spieler kann das gesamte Spiel bedienen, ohne die Studio Command Bar zu benutzen.

**Deliverables:**
1. Client-Architektur aufsetzen (`src/client/Controllers/`, `src/client/UI/`, analog zur Server-Struktur), `init.client.luau` wird zum Bootstrap wie `GameManager` es serverseitig ist.
2. **HUD**: Gummies/GoldGummies live über `PlayerDataUpdated`, Rebirth-Button mit aktuellem Multiplikator, Rang-Anzeige.
3. **Insel-Ansicht**: sichtbare Bärchi-Platzhalter auf der Insel (Part-basiert reicht fürs Erste, echte Meshes später), Klick/ProximityPrompt öffnet Detail-Panel (Level/XP/Skill/Rarity).
4. **Hatch-UI**: Ei-Auswahl mit Preisen (Client darf `EggConfig` direkt lesen, liegt unter `ReplicatedStorage`), Fortschrittsbalken für laufende Hatch-Timer aus Schritt 1, Claim-Button, Reveal-Animation nach Rarity bei `HatchResultReceived`.
5. **Kampf-UI**: "Kämpfen"-Button an der PIT-Plattform, Health-Bars für beide Kämpfer, clientseitige **Wiedergabe** der Runden aus `CombatResult` mit Verzögerung statt Sofort-Ergebnis (fühlt sich sonst wie Betrug an), Sieg/Niederlage-Screen mit Belohnungen.
6. **Gebäude-UI**: Klick öffnet Upgrade-Panel (aktuelles Level, Kosten, Effekt-Text, Kauf-Button, disabled wenn zu teuer).
7. **Bärchi-Inventar**: scrollbare Liste, sortierbar nach Rarity/Level, von dort Auswahl für Kampf/Fusion (Multi-Select)/Recycler.
8. **Fusion-UI**: 2-Slot-Auswahl + Ergebnisvorschau + Bestätigung.
9. **Rebirth-Dialog**: zeigt klar was verloren geht und was gewonnen wird, vor Bestätigung.
10. Alle UI-States reagieren ausschließlich auf `PlayerDataUpdated` — kein eigener Client-State als Wahrheit.

**Akzeptanzkriterien:** Kompletter Loop (Ei kaufen → hatchen → claimen → kämpfen → Gummies verdienen → Gebäude upgraden → Rebirth) ist rein über UI spielbar. UI funktioniert auf Mobile (Scale-basierte `UDim2`, kein reines Pixel-Layout). Client zeigt nur an, validiert nichts autoritativ — jeder Request wird serverseitig erneut geprüft.

---

### SCHRITT 3 — Content, Polish & Live-Ops

**Ziel:** Aus dem spielbaren Prototyp ein veröffentlichbares Spiel machen.

**Deliverables:**
1. Sound/VFX: Hatch-Sound+Partikel je Rarity, Treffer-Sound im Kampf, Level-Up-Effekt, Rebirth-Effekt.
2. Mehr Content (aktuell 12 Bärchis, 13 Skills, 5 Eier) + Balancing-Pass — aktuelle Zahlen (PIT-Rewards, Rebirth-Kosten, Gacha-Raten) wirken grob geschätzt und sind nicht gegeneinander durchgerechnet.
3. **Echtes PvP/Arena**: aktuell kämpft man nur gegen serverseitig generierte PIT-Gegner (`buildPitEnemy`), kein echter Spieler-vs-Spieler trotz vorhandenem Rang-System. Empfehlung: **asynchrones PvP** (Kampf gegen gespeicherten Snapshot eines anderen Spielers) statt Live-Matchmaking — robuster umzusetzen, passt zu `RANK_TIERS`.
4. **Tower-Modus**: `highestTowerFloor` existiert in den Stats, aber es gibt kein Konzept dahinter — entweder implementieren oder bewusst aus den Daten entfernen.
5. Leaderboards (höchstes PIT-Level, meiste Gummies, Rebirths) via `OrderedDataStore`.
6. Monetarisierung: Gamepasses (z. B. 2× Gummies, Auto-Hatch, weitere Insel-Slots) über `MarketplaceService`.
7. Anti-Exploit-Härtung: alle Requests nochmal auf serverseitige Plausibilität prüfen, Rate-Limiting aus Schritt 1 verifizieren/verschärfen.
8. Playtest-Runde + Zahlen-Balancing im Vergleich zu ähnlichen Spielen (Grow a Garden, Anime-Fighting-Sims).

---

## 4. Format-Erwartung an Opus

- Bei Code: **vollständige Dateien**, kein "Rest bleibt gleich" — mit Dateipfad als Kommentar in der ersten Zeile, im bestehenden Stil.
- Am Ende jedes Schritts: kurze Zusammenfassung, was neu/geändert ist, plus was für den Studio-Test nötig ist (z. B. "GameManager.server.luau muss RebirthService in der Liste ergänzen").
- Bei offenen Balance-Entscheidungen (z. B. genaue Fusionsregeln, Hatch-Slot-Zahlen, Offline-Cap): lieber eine sinnvolle Default-Annahme treffen **und explizit benennen**, statt implizit zu raten oder den Lauf mit einer Rückfrage zu blockieren.
