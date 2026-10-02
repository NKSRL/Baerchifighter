# Spawn-Fix und Event-Pit — 2026-09-08

Zweite Änderungsrunde am selben Tag wie die Map-Verkleinerung und der PIT-Turm
(siehe `MAP_VERKLEINERT_UND_PIT_TURM_2026-09-08.md`). Zwei Wünsche:

1. Spieler sollen IMMER auf ihrer eigenen generierten Insel spawnen, nie in
   der Weltmitte.
2. In der Weltmitte soll ein Event-Pit stehen: sieht normalerweise wie ein
   normaler Stall aus, nimmt aber während eines Events die Farben des
   jeweiligen Events an, mit einer Countdown-Anzeige darüber (nächstes Event /
   verbleibende Zeit).

---

## 1. Spawn auf eigener Insel

**Problem vorher:** Roblox spawnt neue Spieler standardmäßig auf einem
zufälligen `SpawnLocation` in der Welt (oder am Ursprung, falls keins
existiert) — bisher gab es nur einen einzigen Spawn-Pad in der Weltmitte.

**Lösung — der Standard-Roblox-Weg, dreiteilig:**

- `src/server/Core/GameManager.server.luau`: `Players.CharacterAutoLoads = false`
  ganz am Dateianfang, noch vor jedem `require()`. Das verhindert, dass
  Roblox überhaupt automatisch einen Charakter erzeugt, bevor die eigene
  Insel bereitsteht.
- `src/server/Services/MapService.luau`, `buildPlotBase(slot, owner)`: jede
  Insel bekommt jetzt ihr eigenes `SpawnLocation` (`"PlayerSpawn"`, unsichtbar,
  `CanCollide=false`, `CanQuery=false`, `Duration=0` — rein als
  Spawn-Anker, kein Deko-Teil). Position über die neue Config
  `MapConfig.PLAYER_SPAWN_OFFSET` (`Vector3.new(-20, 0, 14)`, plot-lokal —
  seitlich versetzt vom Baerchi-Bereich, damit sich niemand hineinspawnt).
  Direkt danach: `owner.RespawnLocation = spawnLocation`.
- `src/server/Services/PlayerService.luau`, `onPlayerAdded`: unmittelbar
  nachdem `MapService.spawnIsland(player, data.island)` die Insel gebaut und
  damit `RespawnLocation` gesetzt hat, ruft der Service `player:LoadCharacter()`
  auf — das ist jetzt der EINZIGE Ort, an dem ein Charakter entsteht.

Roblox' eingebautes Respawn-nach-Tod-Verhalten benutzt immer
`Player.RespawnLocation`, unabhängig von `CharacterAutoLoads` (das steuert nur
den allerersten Spawn beim Join) — nach einem Kampf-Tod landet man also
automatisch wieder auf der eigenen Insel, ohne zusätzlichen Code.

Der alte zentrale Spawn-Pad wurde entfernt (siehe Punkt 2) und durch ein
unsichtbares `"FallbackSpawn"` in der Mitte ersetzt, nur als Sicherheitsnetz
falls `RespawnLocation` aus irgendeinem Grund einmal nicht gesetzt ist.

## 2. Event-Pit in der Mitte

Der alte zentrale Spawn-Pad-Platz wird jetzt vom Event-Pit eingenommen — das
passt gut, weil Spieler dort ja ohnehin nicht mehr spawnen.

**Geometrie** (`MapService.buildEventPit`, neue Konstanten in `MapConfig.luau`):
- Runder Boden (`EVENT_PIT_RADIUS = 32`), leicht erhöhter Rand-Ring
  (`EVENT_PIT_RING_OVERHANG`/`EVENT_PIT_RING_HEIGHT`).
- 28 Zaunpfosten (`EVENT_PIT_FENCE_COUNT`) rundherum, mit 8 Lücken — eine pro
  Insel-Richtung, exakt an den 8 Brücken ausgerichtet (gleiche
  Winkel-Formel `outwardDirection(slot)` wie beim Bauen der Brücken selbst,
  also garantiert passend). Zaunpfosten sind `CanCollide=false`/
  `CanQuery=false`, wie die Spieler-Arena-Zäune auch — rein optisch, blockiert
  niemanden.
- Der Honigmast (`Honigmast`/Beehive-Landmark) steht weiterhin in der Mitte,
  jetzt einfach auf `PLATFORM_TOP_Y + EVENT_PIT_FLOOR_HEIGHT` versetzt.
- Countdown-Tafel (`EventBannerAnchor`/`Banner`, BillboardGui, immer sichtbar)
  über dem Pit.

**Look-Wechsel:** Standardmäßig sieht das Pit aus wie ein normaler Stall
(neutrale Erd-/Holztöne, `EVENT_PIT_DEFAULT_*`-Farben). Ein neuer Service,
`src/server/Services/EventService.luau`, fährt einen einfachen Rundlauf:

```
Pause (5 Min) → Event (3 Min) → Pause (5 Min) → ...
```

- Bei Event-Start: `MapService.setEventPitTheme({floorColor, fenceColor,
  ringColor})` färbt Boden/Ring/Zaun in die Event-Farbe um.
- Bei Event-Ende: `MapService.setEventPitTheme(nil)` setzt auf die
  Standard-Farben zurück.
- Jede Sekunde: `MapService.setEventBanner(titel, untertitel, farbe)`
  aktualisiert die Tafel — `"Hot Egg • LIVE" / "noch 2:51"` während eines
  Events, `"Naechstes Event" / "in 4:12"` in der Pause. Zeitrechnung über
  `os.time()`-Zielzeitpunkt statt Herunterzählen, damit ein ausgesetzter
  Server-Tick die Uhr nicht verschiebt.

**Event-Katalog** (`src/shared/Config/EventConfig.luau`, NEU) — 3
Platzhalter-Events, der Reihe nach im Kreis (kein Zufall):

| Event | Farbe |
|---|---|
| Hot Egg | Rot/Orange |
| Honig-Rausch | Gelb/Gold |
| Goldener Schwarm | Helles Gold |

**Bewusste Scope-Entscheidung:** Ein Event ist aktuell **rein optisch + ein
Timer** — keine spielerische Auswirkung (kein Bonus, kein Buff, kein
Sonder-Loot). `EventService.getActive()` gibt das aktuell laufende Event
zurück und ist als Anknüpfungspunkt für später gedacht, falls Events einmal
etwas bewirken sollen — aktuell liest das niemand.

---

## Offene Annahmen — bitte gegenchecken

- **Event-Katalog/Timing sind Platzhalter:** 3 Beispiel-Events, 3 Minuten
  aktiv / 5 Minuten Pause, feste Reihenfolge statt Zufall. Passt das, oder
  sollen es andere/mehr Events, andere Zeiten, oder zufällige statt
  fester Reihenfolge sein?
- **Kein Spiel-Effekt:** Soll ein Event später einen echten Bonus bringen
  (z.B. mehr Honig, bessere Drops), oder bleibt es bewusst rein kosmetisch?
- **Spawn-Position auf der Insel:** `PLAYER_SPAWN_OFFSET` wurde so gewählt,
  dass der Spieler seitlich neben dem Baerchi-Bereich steht, nicht mittendrin
  — bei Gelegenheit in Studio gegenchecken, ob die Position gut sitzt.

## Verifikation

- `tools/check_members.py`, `tools/check_consistency.py`,
  `tools/check_decor.py`: alle grün.
- `tools/render_map.py`: alle 4 Geometrie-Invarianten weiterhin im grünen
  Bereich (das Script kennt das Event-Pit selbst noch nicht, prüft aber
  weiterhin Ring-Radien/Abstände, die durch diese Änderung nicht angefasst
  wurden).
- Eigene Top-down-Visualisierung (Python/SVG, Werte live aus `MapConfig.luau`
  gelesen) zur Kontrolle gebaut: alle 8 Zaun-Lücken sitzen exakt auf den 8
  Brücken-Richtungen, Event-Pit sitzt zentriert in der Hauptinsel.
- Kein Zugriff auf `luau-compile`/`luau-analyze` in dieser Session (wie
  schon bei der vorigen Änderung) — Klammer-/Struktur-Balance manuell
  geprüft.
