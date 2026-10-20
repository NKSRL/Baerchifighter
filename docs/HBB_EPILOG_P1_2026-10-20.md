# Final-Epilog, Prompt 1 von 7: Siegeslogik, Absicherung, Datenmodell (20.10.2026)

Datenversion **18**. Schalter `FeatureFlags.FINAL_EPILOG` (Standard **aus**, siehe Annahme 1).
Nichts gelöscht, keine Balance-Zahlen angefasst, keine UI/Effekte/Kameras/Welt-2-Inhalte.

## Was gebaut ist

Der Sieg über Final 100 und die Endless-Freischaltung werden **synchron in einer Mutation**
gespeichert, bevor irgendein Effekt beginnt:

1. `CombatService` rechnet den Lauf ab → `TowerService.recordRun` setzt den Rekord (wie bisher,
   Meilensteine und Belohnungen unverändert, einmalig über `claimed`).
2. Direkt danach (gleicher Aufruf, kein `task.wait`) ruft `recordRun` `EpilogService.onFinalClear`.
   Das setzt `towers.unlocked.Endless = true`, `epilog.state = "pending"` (nur wenn bisher `"none"`)
   und `epilog.firstClearAt = os.time()`.
3. Der Aufruf steht **außerhalb** von `counted > previous`: Nach `epilog reset` (Rekord steht schon
   auf 100) löst ein erneuter Sieg die Sequenz wieder aus; ein zweiter Sieg ohne Reset nicht
   (Zustand ist dann nicht mehr `none`).
4. `CombatService` speichert wie bisher (`saveNow`). Zusätzlich plant `onFinalClear` per
   `task.defer` ein `saveConfirmed` **nach** der Abrechnung und schickt erst danach
   `EpilogStart` (`{ token, mode = "full", state = "pending" }`) an den Client.
5. `towerrecord` (Debug) geht nicht über `recordRun` und löst den Epilog nicht aus.

Endless-Meldung: `TowerService.applyUnlocks` fragt vor `TowerUnlocked` bei
`EpilogService.deferUnlockNotice` nach. Läuft die Sequenz (Flag an, `pending`/`seen`), wird die
Meldung zurückgestellt und erst bei `EpilogService.releaseDeferred(player)` gesendet
(automatisch bei `launched`, Notfall-Timer 600 s).

Wiederaufnahme: `EpilogService.restore(player)` läuft nach allen `onDataLoaded`
(`onPlayerReady`), nur bei `pending`/`seen`. Es ruft den Platzier-Handler (Prompt 2/3) und
schickt ein frisches Token (`EpilogStart`, `mode = "restore"`).

## Wo es liegt

| Datei | Inhalt |
|---|---|
| `src/shared/Config/EpilogConfig.luau` (neu) | Zustands-/Remote-Namen, Zeitleiste, Token-Fenster, Debounce |
| `src/shared/Modules/EpilogRules.luau` (neu) | reine Regeln: Übergänge, Final-Clear, Launch, Migration, Token-Prüfung |
| `src/server/Services/EpilogService.luau` (neu) | Verdrahtung: Remotes, Token-Speicher, Restore, Deferral, Debug |
| `TowerService.luau` | Hook in `recordRun`, Deferral in `applyUnlocks`, Endless-Absicherung beim Join |
| `PlayerMigration.luau` | v18: `epilog`/`worlds`, Endless-Absicherung, Final ≥ 100 → `pending` |
| `Types.luau` | `EpilogState`, `WorldsState`, `PlayerData.epilog/worlds`, Standard v18, View-Felder |
| `Remotes.luau`, `NetworkConfig.luau` | 6 neue Remotes, Cooldowns |
| `PlayerService.luau` | `epilog`/`worlds` im Client-Update (nur lesen) |
| `GameManager.server.luau` | `EpilogService` nach `TowerService` registriert |
| `DebugService.luau` | `epilog start|reset|state|launch|scan|on|off` |
| `FeatureFlags.luau` | `FINAL_EPILOG = false` |
| `tools/luau-tests/epilog_state.test.lua` (neu) | 55 Fälle zu Automat, Token, Doppel-Clear, Migration |
| `tools/luau-tests/migration_hbb.test.lua` | Block K: v17 → v18 |
| `tools/luau-tests/tower_unlock.test.lua` | Versions-Erwartung 17 → „aktuelle Version“ |

## Spielstand v18

`epilog = { state = "none"|"pending"|"seen"|"launched", firstClearAt?, launchedAt? }`,
`worlds = { unlocked = { World2 = true } }`. Nur der Server schreibt. Migration: Final-Rekord ≥ 100
und noch kein gültiger `epilog` → `pending`; gültige Stände (`seen`/`launched`) bleiben; Müll wird
repariert; `launched` stellt `World2` sicher; idempotent (Test K2).

## Anti-Exploit

Token = GUID, im Server-Speicher, gebunden an `UserId` + Ausgabezeit. `EpilogSeen`: Zustand
`pending`, Token passt, frühestens 20 s und höchstens 900 s nach Ausgabe, nur einmal.
`EpilogSkip` ändert den Zustand nie. `RequestPressLaunch`: Zustand `seen` + Token. Ungültiges wird
still verworfen (Zähler, höchstens 5 Logzeilen pro Spieler, kein Kick). Race: Zustand schützt,
zusätzlich 5 s Debounce. Beim Verlassen wird alles im Speicher freigegeben.

## Prüfungen (20.10., Luau 0.7xx Linux)

Alle neuen/geänderten Dateien: `luau-compile --null` grün. `check_locals.py` höchster Wert 192
(MapConfig, unverändert). `epilog_state` grün, `migration_hbb` Block K grün, `tower_unlock`,
`guide_steps`, `boss_tiers`, `combat_rating`, `gold_rules`, `map_layout`, `live_board`,
`event_schedule`, `egg_press`, `honey_pond`, `shop`, `endless`, `ui_texts` grün.
`check_feedback/consistency/loc/ui/decor` grün. `check_members.py` meldet weiter die 2 alten Funde
(`CombConfig.INSTANT_PAYOUT`, `formatMultiplier` im `RecyclerBuilder`), nichts Neues.
**Vorher schon rot, unverändert:** `unlock_rules` (Veteran 19 vs. 17) und `migration_hbb` C4
(Rekord 20 vs. 17), siehe `HBB_STUDIO_ABGLEICH_2026-10-08.md`.
Nicht gelaufen (kein Node hier): `migration.test.lua` und die anderen Heim-PC-Tests.
Der `EpilogService` selbst (Remotes, Speichern) ist nur in Studio prüfbar (siehe unten).

## Annahmen

1. **Schalter aus.** Prompt 2–6 fehlen noch; mit „an“ würden Spieler `pending` bekommen und
   `EpilogStart` ginge an einen Client ohne Anzeige. Zum Testen: `D:Invoke("epilog","on")`.
   Die Migration setzt `pending` trotzdem (Daten, kein Verhalten).
2. `EpilogSeen` frühestens nach 20 s (Lauf über die Brücke endet bei ca. 24 s).
3. `RequestPressLaunch` prüft nur Token + Zustand; den Ablauf liefert Prompt 6 über
   `setPressHandler`. `markLaunched` setzt `launched` + `World2` in einer Mutation.
4. Endless-Meldung wird höchstens 600 s zurückgehalten, falls niemand sie freigibt.
5. Beim Join wird `Endless` aus Final ≥ 100 immer nachgetragen (auch bei Flag aus; ändert kein
   Verhalten, Endless war über den Rekord ohnehin offen).
6. `check_members.py` braucht keine Eintragung (liest die Module selbst).
7. Die Arbeitskopie hat überall CRLF (HEAD hat LF); alle Änderungen behalten CRLF.

## Schnittstellen/Stubs für Prompt 2–6

- `EpilogService.setPlaceHandler(fn(player, data, state))` Prompt 2/3: Spieler auf Gipfel
  (`pending`) bzw. Insel (`seen`) setzen, Teile bei Bedarf aufbauen.
- `EpilogService.restore(player)` ruft den Handler beim Join (fertig verdrahtet).
- `EpilogService.setPressHandler(fn(player, data))` Prompt 6: Finale nach gültigem Knopfdruck.
- `EpilogService.markLaunched(player)` Prompt 6: `seen → launched` + `World2` + `World2Unlocked`
  + `releaseDeferred`.
- `EpilogService.releaseDeferred(player)` Prompt 5/6: Endless-Meldung freigeben.
- `EpilogService.deferUnlockNotice`, `isSequenceActive(player)`, `getState(data)`.
- Remotes: `EpilogStart` `{token, mode, state}`, `EpilogSeen(token)`, `EpilogSkip(token)`,
  `RequestPressLaunch(token)`, `EpilogLaunchResult` (ungenutzt bis Prompt 6), `World2Unlocked(worldId)`.
- Client liest `epilog`/`worlds` aus `PlayerDataUpdated`.
- Ordner `Epilog` (Gipfel/Bruecke/Insel/Terminal) pro Plot: nicht angelegt (Prompt 2–4).

## Abnahme in Studio

1. `D:Invoke("epilog","on")`, `D:Invoke("epilog","state")` → `none`, `token = nil`.
2. Final 100 spielen (oder Rekord vorher auf 99 stellen, 100 erkämpfen): `epilog state` →
   `pending`, `endless = true`, `firstClearAt` gesetzt; im Output kein `TowerUnlocked`-Toast.
3. Studio mitten drin beenden, neu starten: `epilog state` → weiter `pending`.
4. Zweiter Final-100-Sieg: unverändert. `epilog reset`, Sieg → wieder `pending`.
5. `epilog scan` → `luecke = false`. `epilog launch` → `launched`, Welt 2 frei.

## Offen

Studio-Lauf der Abnahme (nicht möglich hier), Einspielen per `python tools/make_update_rbxmx.py`
(Option C; nicht ausgeführt, Update-Datei des Nutzers nicht überschrieben), Heim-PC-Tests,
Platzierung/Teile/Kamera/Knopf/Texte/Audio in Prompt 2–7.
