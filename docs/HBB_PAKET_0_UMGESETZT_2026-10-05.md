# HBB Paket 0 umgesetzt – 05.10.2026

## Neu
- `FeatureFlags` mit allen 13 Schaltern und `isOn(name)`; unbekannter Name → Fehler in Studio, still `false` live.
- `FunnelService` meldet den Onboarding-Trichter F01–F10 (je Schritt einmal pro Sitzung, nur Konten < 24 h; F10 bis 48 h).
- UI-Messpunkte über einen neuen Remote `RequestLogUiEvent`: Panel geöffnet, Panel nach < 3 s geschlossen, Spieler steht > 20 s still (Whitelist, Cooldown, max. 50 pro Sitzung).
- Debug-Befehl `state <fresh|hatch10|tower1>` (verlangt vorher `snapshot`, zurück mit `restore`).
- Rückweg: Git-Repo im exportierten Ordner, Tag `pre-ui-v2` = Stand vor allen HBB-Änderungen.

## Geänderte und neue Dateien
- `src/shared/Config/FeatureFlags.luau` – neu, Schalter
- `src/shared/Config/FunnelConfig.luau` – neu, Schrittnamen, Whitelists, Grenzen
- `src/server/Services/FunnelService.luau` – neu, Trichter + UI-Ereignisse + F02-Messung
- `src/client/Controllers/UiEventLogger.luau` – neu, Client-Zulieferer (mit Sendewarteschlange)
- `src/client/UI/PanelManager.luau` – Beobachter `onOpened`/`onClosed` (kein Umbau)
- `src/client/Main.client.luau` – UiEventLogger starten
- `src/server/Core/GameManager.server.luau` – FunnelService in der Startliste
- `src/shared/Network/Remotes.luau`, `src/shared/Config/NetworkConfig.luau` – `RequestLogUiEvent` + Cooldown 0,2 s
- `src/shared/Config/DebugConfig.luau` – `FUNNEL_LOG`
- je eine Zeile in `EggService` (F03), `CombatService` (F05, F06), `HoneyService` (F07), `PetModeService` (F08), `EventParticipationService` (F09)
- `src/server/Services/PlayerService.luau` – `buildDefaultData()` (Default-Fabrik bleibt in PlayerService)
- `src/server/Services/DebugService.luau` – Befehl `state`

## Annahmen und Abweichungen
- **API:** `AnalyticsService:LogOnboardingFunnelStepEvent(player, step, stepName)` statt `LogFunnelStepEvent`. Laut Creator-Doku ist das der Trichter-Typ für einmalige Abläufe und braucht keine `funnelSessionId`. UI-Ereignisse über `LogCustomEvent` (Panel-Name als CustomField01).
- **F04** über einen `onDataChanged`-Beobachter statt einer Zeile in `IslandService`: der erste Bärchi wird über `autoEquipIfNone` ohne Remote ausgerüstet, das hätte die Zeile nie erreicht. Der Beobachter schreibt nichts zurück.
- **F02** misst der Server selbst (Charakter ≥ 6 Studs vom ersten gemessenen Punkt), kein Remote.
- **F10** gilt, wenn das Konto beim Join ≥ 10 min alt ist; Fenster 48 h statt 24 h, damit eine Rückkehr am nächsten Nachmittag zählt.
- **`tower1`** = Rekord Tower I / 30 (Meilensteine ausgezahlt), Rebirth bleibt 0.
- `PACING_V2` und `ENDLESS` stehen auf `false` (Stopp-Punkte im Plan), alle anderen Flags `true` (noch ohne Wirkung, bis ihr Paket gebaut ist).
- In Studio gehen keine echten Analytics-Events raus (Roblox nimmt sie nur im veröffentlichten Spiel an); Studio loggt nur.

## Prüfergebnisse
| Werkzeug | Ergebnis |
| --- | --- |
| `luau-compile` (alle 137 Dateien) | grün |
| `check_members.py`, `check_consistency.py`, `check_loc.py`, `*.test.lua` | **nicht gelaufen** – `tools/` liegt nur auf dem Heim-PC |
| Studio-Playtest (selbst durchgeführt per Bildschirmsteuerung) | F01–F09 nacheinander im Output, 0 Fehler, 1 Warnung (RateLimiter bei zwei UI-Events in 0,05 s → mit Sendewarteschlange behoben, noch nicht erneut gespielt) |
| `state hatch10` / `tower1` / `restore` | liefen fehlerfrei, Stand danach wiederhergestellt |

## Studio-Testschritte für den Menschen
1. Auf dem Heim-PC: Ordner `RBL/src` aus dem Export mit dem Repo zusammenführen, Rojo-Verbindung prüfen, auf doppelte Dateien prüfen.
2. Play → Command Bar (Server): `D=game.ServerScriptService.RBLDebug D:Invoke("snapshot") D:Invoke("state","fresh")` – im Output `F01_Join`.
3. Laufen, Ei öffnen, Fight, Event-Knopf, `startevent`/`skipevent` – erwartet F02 … F09 der Reihe nach.
4. `D:Invoke("restore")` vor Stop.
5. Nach dem Veröffentlichen: im Creator-Dashboard unter Analytics → Funnels prüfen, ob der Onboarding-Trichter erscheint.

## Offen
- Prüfwerkzeuge aus `tools/` auf dem Heim-PC laufen lassen.
