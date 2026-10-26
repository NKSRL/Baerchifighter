# Vorher-Bilder (Paket 0, Welt aufwerten)

Sechs Bilder von festen Kamerapunkten, hier ablegen als `1.png` … `6.png`.
Nachher-Bilder genauso nach `../welt_nach_C/`, `../welt_nach_F/` und `../welt_nachher/`.

In Studio (Play, Command Bar im **Server**-Kontext):

```lua
local D = game.ServerScriptService.RBLDebug
D:Invoke("daytime", 16.9)     -- gleiche Uhrzeit fuer alle Vergleichsbilder
D:Invoke("worldshots", 1)     -- Kamera auf Punkt 1, UI aus → Screenshot
D:Invoke("worldshots", 2)     -- … bis 6
D:Invoke("worldshots", 0)     -- zurueck
```

Echter Vorher-Stand: vorher `AmbienceConfig.DAY_CYCLE = false` und in
`FeatureFlags` `WORLD_B_WATER`/`WORLD_C_HUB` auf `false`.
Punkt 5 (Arena mit Turm) waehrend eines Laufs: erst `D:Invoke("fight", uid)`.
Der Testspieler muss auf Slot 1 sitzen (erster Spieler auf dem Server).

Notizen je Punkt: siehe `claude/WELT_AUFGEWERTET_UMGESETZT_2026-10-09.md`, Paket 0.
