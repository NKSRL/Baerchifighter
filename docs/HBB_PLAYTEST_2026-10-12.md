# Playtest 12.10.2026 – umgesetzt

Studio-Einspielung: `updates/HBBUpdate_seit_340668f.rbxmx` importieren, dann `tools/einspielen.lua` in die Befehlsleiste. Nicht in Studio getestet.

| Rückmeldung | Ursache | Änderung |
|---|---|---|
| Terminal muss Rebirths berücksichtigen: nach dem Rebirth darf man nicht direkt in Tower II | Freischaltung hing an den **Rekorden**, die einen Rebirth überdauern | Neuer Schalter `TOWER_UNLOCK_PER_LIFE` (an): Freischaltung gilt **pro Leben**. Gezählt wird `island.stageBest`. Ein Rebirth setzt `towers.unlocked = { I }` und wählt Tower I. Terminal („Schaffe Tower I x/30“), Panel, Server und Join-Migration nutzen `TowerConfig.unlockRecords`. Rekorde, Meilensteine und Bestenliste bleiben. |
| Bärchi läuft durch die Brücke, schlechte Laufwege | Gerade Linie vom Plot zum seitlichen Kampfplatz: am Arena-Ende durchs Geländer. Dazu Beet-Höhe (2 Studs) über den ganzen Weg, auf dem Rückweg durchs Beet | `FigureWalker.walkPath` + `PitArenaService.arenaRoute`: Beet-Kante → Wiese → Stegmitte → Steg-Ende → Arena → Platz, mit Höhe je Abschnitt. Zurückholen auf dem Hinweg nimmt den Rest des Wegs rückwärts. |
| Man kann den Turm nicht hochfliegen | Die Turm-Ringe sind eine 2,4-Stud-Wand pro Etage | Leuchtendes **Flugfeld** am Rand der eigenen Arena (Steg-Seite, neben dem Laufweg). Steht der Turm, fliegt der Charakter im Bogen auf die Spitze (`TowerFlightController`, Client-Physik; Server schreibt nur `PitPlatform.TowerTopY/TowerLevel`). Zahlen in `WorldFXConfig.TOWER_FLIGHT`. |
| Grafik 1: Brücke bugged im Sand | Die **Bohlen am Honig-Teich** hatten Oberkante 0,20 = Sandkante 0,20 → Z-Fighting | Bohlen 0,32 dick. `check_decor.py` meldet gleich hohe Bohle/Sandkante jetzt. |
| Recycler zu schwach; nur Geld-Multiplikator anzeigen; Waben sofort auszahlen | – | Grundwert `BASE_PAY_PER_UNIT = 10` × Level-Multiplikator (alte Kurve / 3) = **×3,3 auf jedem Level**. `INSTANT_PAYOUT`: Abgabe zahlt sofort, alte Warteschlangen werden beim Join ausgezahlt. Schild zeigt nur „×N“ (×1, ×1,7 … ×80 … ×23K), Prompt „Recycler ×12 ➡ ×17“. Die Pacing-Sim rechnet den Recycler nicht mit – Stärke im Playtest prüfen. |
| Ei-Baum und X direkt aneinander | Ei-Baum-Knopf endete genau an der Kante des X (Trefferfläche 56 überlappte) | 18 px weiter links. |
| Start-Knopf über den anderen Knöpfen, darunter ein unlesbarer Knopf | Das 7-s-Feld am Kampf-Knopf: Preis-Zahl lag über „Ab Stage 23 weiter“, ausgegraut kaum lesbar | Drei klare Zeilen: grüner Gratis-Start, bezahlter Einstieg über die ganze Breite (Text links, kurzer Preis rechts, zu teuer = Preis rot), Balken unten. Vorschau: `preview.py --fight-prompt`. |
| Wegweiser: Pfahl vor den Pfeilen, Schrift schlecht lesbar | Schilder mittig auf dem Pfahl | Schilder hängen **außen** am Pfahl und zeigen von ihm weg; der Pfahl steht auf der Wegseite, zu der der dritte Arm zeigt (ragt nicht übers Pflaster, Test in `map_layout`). Helle Schrift mit dunkler Kontur, nachts unverändert hell. |
| Fusion-Knopf in „Bärchis“ entfernen, Fusion über die Karte des einzelnen Bärchis | – | Schalter `FUSION_INVENTORY_TOGGLE` (aus): kein „Fusion: an/aus“ mehr. „Stärker machen → Fusion“ auf der Bärchi-Karte bleibt; in der Auswahl steht dort nur „Abbrechen“. |

## Balance
`progression_pacing.lua` mit Freischaltung pro Leben: Rebirth 2 2,5 h → 2,7 h, Look 3 88 → 96 min, sonst ±0,1 h. Der schnelle Fortschritt bleibt; an der Bärchi-Stärke musste nichts geändert werden. Rot war vorher schon: „Look 4 Woche 1“ (2,2 h, zu schnell) und die Endless-Ziele. `tower_calibration.lua` grün.

## Prüfungen
Syntax, `check_locals`, alle Luau-Tests (neu: `recycler.test.lua`, erweitert: `tower_unlock`, `map_layout`), `check_feedback/members/consistency/loc/decor` grün. `check_ui.py` meldet 3 Funde, die schon vorher da waren.

## In Studio prüfen
1. `D:Invoke("towerrecord","I",30)`, dann Rebirth → Terminal rot „Schaffe Tower I 0/30“, Panel: Tower II gesperrt.
2. Kampf starten: Bärchi läuft mittig über den Steg, steigt an der Beet-Kante ab/auf.
3. Während ein Lauf den Turm wachsen lässt: aufs gelbe Feld am Arena-Rand → Flug auf die Spitze.
4. Teich von der Seite: Bohlen flimmern nicht mehr.
5. Waben abgeben → Gummies sofort; Schild „×N“.
6. Wegweiser auf der Hauptinsel, Ei-Fenster (X/Ei-Baum), Kampf-Knopf mit gespeichertem Lauf.

## Nachtrag: Ladebildschirm, PC-Größe, UI-Ausschnitte

**Ladebildschirm** (`src/first/LoadingScreen.client.luau` → **ReplicatedFirst**, neu in `default.project.json`, `make_update_rbxmx.py`, `einspielen.lua`): ersetzt Roblox' grauen Standard-Bildschirm ab der ersten Sekunde. Honig-Verlauf, hüpfender Bärchi, steigende Waben, Titel, Status-Zeile, Balken, wechselnde Tipps (4 Sprachen, `ui.loading.*`). Weg erst, wenn Spiel geladen, eigene Insel da, Charakter da, Oberfläche bereit (`HBB_ClientReady`, gesetzt am Ende von `Main`) und Bilder vorgeladen sind, plus 1,5 s Ruhe für die Deko. Sicherheitsnetz 30 s. Ein Block skaliert mit dem Bildschirm (Handy quer bis 4K). Bilder: `docs/screens/ladebildschirm_*.png`.

**PC größer** (`UI/UiScale`): mit Maus + Tastatur wächst die UI früher (1080p 1,27 → 1,49, 1440p 1,6 → 1,85, Deckel über die Breite). Handy und Tablet (Touch ohne Tastatur) rechnen unverändert. Bild: `docs/screens/pc_skalierung_1080p.png`.

**UI-Ausschnitte** (`UI/Icons.luau`, Tabelle `CUTOUTS`): fünf Plätze, leer = alte Optik.

| Schlüssel | Bild | ersetzt |
|---|---|---|
| `tile_baerchis` | rote Kachel mit Bärchi | Menü-Kachel „Bärchis“ |
| `tile_quests` | blaue Kachel mit Schriftrolle | Rolle an der Quest-Karte |
| `button_settings` | grüne Kachel mit Zahnrad | Zahnrad oben links (40 px) |
| `banner_rank` | grünes Banner mit Krone | Rang-Pille rechts oben — **ohne Schrift hochladen**, der Rang-Name bleibt Text (wechselt, 4 Sprachen) |
| `button_rebirth` | „Rebirth!“ | Rebirth-Knopf (168 × 52) |

Einbauen: PNG in Studio hochladen (Asset-Manager → Bilder), ID als `"rbxassetid://<id>"` bei `id` eintragen.
