# Tower-Terminal, Freischaltung, Einstiegs-Knöpfe, neues Tower-Panel – umgesetzt (08.10.2026)

Auftrag: `OPUS_PROMPT_TOWER_TERMINAL_UI_RECYCLER_2026-10-08.md`. Gebaut: **A, G, B, C, D**.
**Nicht gebaut: E (Recycler-Multiplikatoren) und F (Wabenmodell)** – laut Prompt
Abschnitt 9 Stopp nach D mit Zwischenabnahme. Branch
`claude/tower-terminal-ui-2026-10-08` (Basis `ee9edd4`), Datenversion **17**.

## 0. Was beim Prüfen anders war als im Prompt

| Annahme im Prompt | Ist im Code | Folge |
|---|---|---|
| Studio = Repo-Stand | In Studio waren 5 Skripte noch auf dem ALTEN Repo-Stand (vor dem Studio-Abgleich): `Types` (ohne Inkubator, Version 15!), `EggMerchantService`, `EventHandlers`, `PetModeService`, `EggTimerController`. Gemessen per Quelltext-Hash aller 170 Skripte. | Die neue Update-Datei ist gegen `737ab94` gebaut und bringt diese 5 mit (98 Skripte, ersetzt nur Quelltext). |
| „Fight startet kostenlos ab 65 %“ | Seit der Entscheidung 05.10. (`FIGHT_RESUME_PROMPT`) startet jeder Lauf **gratis bei Stage 1**; „ab Stage X“ kostet (auch „Percent“ kostet 35 %). | Der Gratis-Start zeigt die echte freie Stage: **„START · ab Stage 1“**. Die 65-%-Regel wird nicht wieder eingeführt (Annahme, Entscheidung 3). |
| Endless = „kommt bald“ | Endless ist umgesetzt (HBB Paket 9, `ENDLESS` an). | Endless ist eine normale Karte mit eigenem Look (∞, rosa/lila), Freischaltung „Final 100 geschafft“ wie gefordert. |
| Rebirth-Bedingung nach Stage = Sammel-Update 4.1, nicht hier | Ist schon im Code (`REBIRTH_REQUIREMENT`). | Unverändert gelassen. Die neue Freischaltung passt dazu: jede Rebirth-Bedingung liegt in einem Tower, der zu dem Zeitpunkt offen ist. |
| Tutorial ohne Text | Die bestehenden Schritte zeigen seit 3.5 einen Satz (`guide.<step>`). | Der neue Schritt „tower“ hat **keinen** Satz (Schlüssel fehlt absichtlich) – nur Strahl + Rahmen. |
| Veteranen-Regel bleibt | „4 Ketten-Quests“ ist nach 5 gewonnenen Kämpfen erfüllt – lange vor Tower I/30. Mit ihr sähe den neuen Schritt niemand. | Der Schritt „tower“ gilt für alle **ohne Rebirth**; die Ketten-Regel gilt für ihn nicht (Entscheidung 2b). |

Vorher schon rot (nicht durch diesen Auftrag, siehe `HBB_STUDIO_ABGLEICH_2026-10-08.md`):
`unlock_rules` (Veteran 19 vs. 17), `migration_hbb` C4 (Rekord 20 vs. 17),
`progression_pacing` (Rebirth 1 nach 0,9 h; Endless-Ziele). `guide_steps` war
ebenfalls rot, weil der Test die Studio-Kette (Waben → Verbessern → Event) noch
nicht kannte – **die drei Erwartungen sind an die im Code dokumentierte Kette
angepasst**, Rest unverändert.

## A – Brunnen-Stelzen im Boden

Gemeint sind die beiden **Pflöcke** und **Bohlen** vor dem Honig-Brunnen (Steg,
auf dem der Bärchi frisst) und die Brunnen-Teile im Becken.

- **Ursache Pflock:** `CFrame.Angles(0, 0, 90)` stellt den Zylinder **aufrecht**
  (Länge = Size.X = 1,7), der Kommentar sprach von „liegend“, und die Höhe kam
  aus `Size.Y * 0.4` (Durchmesser). Mittelpunkt 0,36 → 0,49 Studs im Beet
  (in Studio gemessen: Unterkante 1,51 bei Beet 2,00). Jetzt
  `Size.X * POND_PEG_LIFT` mit `POND_PEG_LIFT = 0.5` → steht auf dem Beet.
- **Ursache Bohlen:** 0,9 dick mit Oberkante 0,06 → 0,84 im Beet. Jetzt 0,2 dick,
  Unterkante = Beet (der Bärchi steht auf Beet-Höhe, sein Fuß sinkt 0,2 ein).
- **Brunnen im Becken** (`Pfahl`, `L2Topf`, `L3Saeule`): standen auf Beet-Höhe,
  also 0,45 im Beckenboden. Jetzt Unterkante = `POND_FLOOR_TOP`, Oberkanten
  unverändert (Schale, Säule oben bleiben wo sie waren).
- **Dauerhaft geprüft:** `check_decor.py` Regel 6 – meldete vor der Korrektur
  5 Funde (Bohle 0,84, Pflock, Pfahl/Topf/Säule je 0,45), jetzt grün für alle
  Looks 1–6. Neon-Teile (Honigstrahlen, -fälle) dürfen in den Honig tauchen;
  die Steine des Kranzes sind bewusst eingegraben.
- Bild: `docs/screens/A_teich_steg_vorher_nachher.png` (Seitenansicht aus den
  Config-Zahlen; ein Studio-Foto war nicht möglich, siehe „Studio“ unten).

## G – Ausbau mit einem Druck + Erfolgs-Moment

- Prompts Honig-Brunnen und Recycler: `HoldDuration = 0`. Nach einem Druck
  sperrt sich der Prompt 0,4 s (`FeedbackConfig.UPGRADE_FX.PROMPT_LOCK`) –
  Doppelklick kauft nur einmal; der Server bleibt maßgeblich.
- Prompt-Text zeigt den Preis („Verbessern · 1.234 Gummies“); reicht es nicht:
  „Es fehlen 567 Gummies“. **Ausgrauen kann der Standard-Prompt nicht** – der
  Text übernimmt das; ein Druck zeigt dann die bekannte Ablehnung.
- Neuer `UI/UpgradeFX` (eine Heartbeat-Schleife, kein Thread pro Effekt):
  Auslöser **nur der Datenstand** (Level +1 → Server hat gebucht), egal ob per
  Prompt oder Menü. Effekt ≤ 1,15 s: Gebäude springt auf und federt zurück
  (lokal skaliert, danach exakt zurückgesetzt), EIN Emitter mit Funken in
  Gebäudefarbe (danach weg), schwebende Zahl „Level 7 ➡ 8“, Klang, und der
  bezahlte Betrag fliegt aus der Gummy-Pille zum Gebäude (`Feedback.spend`, neu,
  nutzt den Pool aus HBB Paket 1). Look-Wechsel (L10/20/30/45/60): große
  Variante (mehr Funken, „NEUER LOOK!“), wartet auf den Neubau des Servers.
- Umgestellt: Brunnen, Recycler, **Terminal** (neu, ohne Halten). Unverändert:
  Inkubator (öffnet nur ein Fenster, hatte kein Halten), Arena-Prompt (öffnet
  das Panel, kein Halten). Prompts mit Halten als Schutz gibt es keine.
- Klänge: neue `Config/SoundConfig` (Platzhalter = eingebaute Studio-Klänge,
  leerer Eintrag = stumm), abgespielt über `Kit.playSound`.

## B – Freischaltung durch Schaffen, Terminal, Tutorial

**Regel** (`FeatureFlags.TOWER_UNLOCK_BY_CLEAR`, aus = alte Rebirth-Regel):
Tower N+1 ist offen, sobald Rekord(N) ≥ Stage-Zahl(N): II nach I/30, III nach
II/45, Final nach III/60, Endless nach Final/100 (`TowerConfig.UNLOCK_AFTER`).
Offen ist auch, wo schon ein Rekord steht. Jeder offene Tower zahlt seine
**volle** Stage-Zahl (kein Deckel, kein Rebirth-Hinweis mehr).

- **Daten v17:** `towers.unlocked = { [towerId] = true }` (trägt Meldung und
  Bestandsschutz). Migration: was nach der ALTEN Regel offen war oder einen
  Rekord hat, wird eingetragen – niemand verliert Zugang. Nur einmal
  (Version), keine Währung angefasst.
- **Server:** `RequestSelectTower` lehnt gesperrte Tower mit
  `err.tower_locked_clear` ab („Schaffe zuerst Tower I (Stage 30)“). Neue
  Meldung **`TowerUnlocked`** (Tower-Id) beim ersten Schaffen (auch per Debug
  `towerrecord`). Beim Join wird still nachgetragen.
- **Nebenwirkungen geprüft:** RebirthDialog/RebirthService nutzen die
  Rebirth-Bedingung (unverändert), Bestenliste die Rekorde (unverändert), Quests
  `towerStage` (unverändert), `getEquivalent` (unverändert). Der alte
  Deckel-Hinweis im CombatPanel kommt nicht mehr (`capReached` immer false).
  Das alte Panel zeigt ohne `TOWER_PANEL_V2` noch „Öffnet ab Rebirth“ – nur ein
  Text, nur mit Schalter aus.

**Balance-Folge** (Äquivalenz-Modell aus `TowerConfig`, Gummies je Lauf ohne
Rebirth-Multiplikator, gerechnet mit `tools/sim/*`-Funktionen):

| Stärke (Äquiv.) | Tower I | Tower II | Tower III | Final |
|---:|---|---|---|---|
| 30,0 | 26 Stages / 0,50 Mio | 6 / 1,24 Mio | – | – |
| **34,4** (= I/30 geschafft) | 30 / 0,98 Mio | **10 / 2,76 Mio** | – | – |
| 42 | 30 / 0,98 Mio | 18 / 8,5 Mio | – | – |
| 55 | 30 / 0,98 Mio | 32 / 34,7 Mio | 1 / 2,8 Mio | – |
| 67 | 30 / 0,98 Mio | 45 / 90 Mio | 21 / 89 Mio | – |
| 82 | | | 46 / 360 Mio | 1 / 17 Mio |
| 100 | | | 60 / 693 Mio | 37 / 1,2 Mrd |
| 131,5 | | | | 100 / 10 Mrd |

Tower II lohnt sich **sofort** nach I/30 (2,8 × Tower I je Lauf, weil I nur
`rewardFactor 0.3` zahlt). `progression_pacing.lua` (Profil Normal, 90 min/Tag),
alte Regel → neue Regel:

| Ziel | alt | neu |
|---|---|---|
| Look 3 (Tag 2–3) | 2,1 h | 1,5 h |
| **Look 4 (~Woche 1, 6–13,5 h)** | 10,0 h ✔ | **2,1 h ✘** |
| **Look 5 (Woche 2–3, 13,5–31,5 h)** | 18,2 h ✔ | **10,6 h ✘** |
| Look 6 (Woche 5–8) | 71,4 h | 71,4 h |
| Final 100 nicht vor Woche 8 | ✔ | ✔ (gegnerstärke-gebremst) |

**Keine Zahl geändert.** Die Mitte des Spiels wird deutlich schneller (die
Rebirth-Deckel bremsten das Einkommen). Gegenproben ohne Commit: Tower II
`rewardFactor` 0,3 → Look 4 bei 3,2 h, Look 5 bei 13,9 h – reicht allein nicht.
Optionen zur Entscheidung: (a) so lassen, (b) Belohnung (nicht Freischaltung)
weiter pro Rebirth deckeln, (c) `rewardFactor` II/III senken **und** die
Gebäude-Kosten L20–45 anheben. Achtung: die Simulation rechnet Rebirths noch mit
dem alten Gummi-Modell (Rebirth 1 schon vorher rot) – die absoluten Zeiten sind
Annahmen; der Vergleich alt/neu ist belastbar.

**Terminal** (`MapConfig.TOWER_TERMINAL`, `Util/MapBuild/TerminalBuilder`,
`Controllers/TerminalController`): Kiosk als Bärchi-Kopf (Ohren, Dach, Antenne
mit Lampe, Knopf, Bildschirm) am Stegbeginn zur Arena, plot-lokal (11, 0, 45),
36° zum Weg gedreht – außerhalb des Beets, neben dem Laufweg, auf der Insel.
**16 Teile** (Budget ~30; Insel vorher 175–193 → 191–209 von 250). Einmal mit
dem Plot gebaut; Zustand nur als Attribute (State, Tower, Record, NextTower,
NewTower, Progress, Needed), geschrieben von PlotDisplayService bei geänderter
Signatur. Der Client macht daraus den Bildschirm (SurfaceGui, Sprache des
Betrachters), die Lampe (rot / grün blinkend / honiggelb), das „!“ (nur am
eigenen Terminal, Zustand „bereit“) und den Prompt „Tower wählen“ (gesperrt:
Hinweis statt Fenster).

- **Arena-Prompt: bleibt** und öffnet jetzt das neue Panel (selber Name
  „Combat“) – wer an der Arena steht, will dort oft umstellen.
- **Pet-Leiste:** Antippen von „HP 100% · Tower I“ öffnet das Panel (im Kampf
  bleibt es der Zurückholen-Knopf).
- **Tutorial:** `GuideSteps` „tower“ = Tower II frei, nie gewechselt, nie
  woanders gekämpft, ohne Rebirth. Strahl zum Terminal-Bildschirm, im Panel
  Rahmen um „WÄHLEN“ von Tower II. Fertig, sobald ein anderer Tower gewählt ist
  oder dort schon gekämpft wurde. Kein Auto-Wechsel; Feier-Moment über
  `TowerUnlocked` (Moment „NEUER TOWER!“, Konfetti auf der Karte, „NEU!“).
- **Quest-Schritt „Wechsle den Tower“:** nicht eingebaut. Die Kette ist nach
  Position gespeichert (`chainClaimed`); ein neuer Schritt in der Mitte
  verschiebt alle danach. Vorschlag: als letzter Kettenschritt, wenn gewünscht.

## C – Drei Einstiegs-Knöpfe, Gamepass-Platzhalter

- Im neuen Panel unten: **START** (grün, größter Knopf, einziger mit Puls,
  „ab Stage 1“, Aufkleber „GRATIS“), **⏩ Stage X** (cremefarben, Kontur, kein
  Glanz, kein Puls, Preis kurz „293K Gummies“), **👑 Gratis-Skip** (ruhiges
  Gold, „Bald“ solange id = 0). Mit Pass verschmelzen Skip und Pass zu einem
  goldenen „⏩ Stage X · Gratis (Pass)“. Ohne gespeicherten Lauf fällt der
  Skip weg. Läuft ein Kampf: „KAMPF LÄUFT“.
- Auch das 7-s-Feld am Fight-Knopf (`FightStartPrompt`) ist umgedreht: oben
  groß und grün „▶ Stage 1 · GRATIS“, darunter klein der bezahlte Einstieg.
- `Config/GamepassConfig` (SKIP_PASS, id = 0), `Services/GamepassService`
  (Besitz per `UserOwnsGamePassAsync` mit pcall beim Join und nach
  `PromptGamePassPurchaseFinished`, Kauf-Dialog über `RequestBuyGamepass`,
  Besitz nicht in PlayerData, Anzeige über Player-Attribut `Pass_SKIP_PASS`).
  **Kosten rechnet nur der Server:** `CombatService` fragt
  `GamepassService.owns` → `TowerConfig.getResumeCost(..., hasPass)` = 0.
  id = 0: niemand besitzt den Pass, Kaufwunsch wird still verworfen, kein Fehler.
- Debug: `D:Invoke("pass", "on" | "off" | "reset")`.
- Tests: `tower_unlock.test.lua` (Kosten 0 mit Pass, > 0 ohne).

## D – Neues Tower-Panel (Theme.v2 + UI/Kit)

Aufbau: Honig-Kopf mit Titel und Maskottchen-Bärchi, das über die Kante lugt;
Statuszeile (Gewählt · Rekord · Nächster Tower x/y); Kartenliste (scrollt, springt
zum gewählten Tower); Einstiegsleiste fest unten mit Gummy-Stand.
Karte: Tower-Abzeichen in Look-Farbe mit Material-Zeichen (Holz-Maserung,
Stein-Fugen, Gold-Funkeln, Kristall-Raute, Endless-Ring – ohne Bild-Upload),
„Tower II · 45 Stages“, Rekord-Balken, nächster Meilenstein (Icon + Zahl),
Zustand **AKTIV** (Honig-Rand + Band) / **WÄHLEN** (blau) / **NEU!** (pinker
Aufkleber, Glanz läuft über die Karte) / **GESPERRT** (gedämpft, Schloss am
Abzeichen, „Schaffe Tower I“ + Balken 12/30).

**Das X** ist ein eigenes Geschwister des Panel-Körpers, Mittelpunkt 10
Einheiten innerhalb der Ecke (×Skalierung, in allen Größen dx = dy), 52 groß,
64 Trefferfläche. Der Kopf hat denselben Eckradius wie der Körper und liegt
bündig darin. **Ursache des alten Fehlers:** das X saß in der Kopfzeile, die 14
px eingerückt war, der lila Balken aber nur 6 px – rechts vom X blieben 4 px
Balken stehen. Messung im Bild (Pixel in Balkenfarbe rechts vom X):
alt 11–20, neu 0 in allen vier Größen. `docs/screens/D_x_ecke_vorher_nachher.png`.

### Tokens (`Theme.v2`, Palette in Minuten tauschbar)

| Token | Wert | Token | Wert |
|---|---|---|---|
| surface / surfaceDeep | 255,244,220 / 246,226,190 (Creme) | ink / inkSoft | 74,44,23 / 122,84,53 |
| card / cardLocked | 255,252,243 / 236,226,210 | outline | 59,34,18 |
| honeyTop / honeyBottom | 255,214,100 / 255,152,24 | gummy | 255,92,154 |
| go / goTop / goEdge | 72,196,70 / 120,230,100 / 30,128,44 | sky / skyDeep | 76,195,255 / 22,120,190 |
| quiet / quietEdge | 255,248,232 / 214,190,150 | gold / goldTop / goldEdge | 255,222,128 / 255,243,200 / 206,150,30 |
| active / new / lock | 255,196,40 / 255,92,154 / 150,132,112 | progress | 72,196,70 |
| radius | panel 26, card 18, button 16, badge 14 | stroke | panel 4, card 3, button 3, text 3 |
| space | 4 / 8 / 16 / 24 / 32 | text | title 40, card 26, number 30, body 18, button 26, **small 15** |
| motion | open 0,32 s (Back), stagger 0,05, cardIn 0,28, press 0,10, pulse 1,6, glimmer 2,6, confetti 1,2 | font | FredokaOne |

**Kontraste** (WCAG): ink auf surface 11,6:1, ink auf card 12,3:1, inkSoft auf
card 6,5:1, ink auf goldTop 9,6:1. Weiße Schrift auf Grün/Blau/Honig liegt bei
2,1–4,3:1 und trägt deshalb **immer** eine 3-px-Kontur in ink (14,8:1 zur
Kontur) – der übliche Simulator-Look; große Zahlen ≥ 3:1 erfüllt.

**Schrift:** kleinste Schrift 19 px bei 1080p (15 Einheiten × 1,27), 15 px bei
1366×768/1024×768, 11,5 pt am Handy quer (kompakte Ansicht, s. u.). Kein Text
abgeschnitten (alle Größen, DE/FR/ES geprüft; zu lange Texte werden kleiner,
nie kürzer). **Touch:** X 52/64, START 76, Skip/Pass 64, WÄHLEN 64 Einheiten
(≥ 48 px ab Skalierung 0,75).

### Kritik-Runden

1. **Fassung 1:** Karten wirkten braun-trüb (die 3D-Kante war Kind der
   Kartenfläche und lag in Roblox *über* ihr), „NEU!“ links abgeschnitten,
   Gummy-Pille und „GRATIS“-Aufkleber überlappten, Gold-Abzeichen sah
   „durchgestrichen“ aus. → Kante als Geschwister, Aufkleber nach innen,
   Leiste höher, Funkel-Rauten statt Streifen.
2. **Fassung 2:** Pass-Knopf zu grell (zog den Blick neben START), Handy quer
   nur 0,6-fach skaliert und unter den HUD-Pillen, Tablet überdeckte die
   Gummy-Pille. → ruhiges Gold, Ränder je Bildschirmklasse, **kompakte Ansicht**
   unter 520 Höhe (kleinerer Kopf, ohne Statuszeile/Stand-Zeile, Liste scrollt).
3. **Fassung 3:** „GRATIS“ deckte das Wort START ab; Preis 3.127.227.972 sprengte
   den Skip-Knopf; gesperrte Karte mit leerer Mitte. → Aufkleber oben rechts im
   Knopf, kurze Zahlen (`Kit.formatCompact`: 293K, 3,1B), Sperrhinweis in die
   Kartenmitte, WÄHLEN auf 64 hoch.

Ehrliche Restkritik: Am Handy quer ist alles klein (11,5 pt) und es passt nur
eine Karte – brauchbar, aber eine eigene Quer-Anordnung (Liste links, Knöpfe
rechts) wäre besser. Bewegung (Aufspringen, Einlaufen, Puls, Glanz, Konfetti)
ist im Standbild nicht zu beurteilen – in Studio ansehen. Die Gummy-Pille in der
Leiste doppelt die HUD-Pille (vom Prompt gewünscht).

**Leistung:** ~690 Instanzen im ganzen UI; 50× öffnen/schließen: 691 → 691,
laufende Animationen nach dem Schließen 0 (`preview.py --leak`). Eine
RenderStepped-Verbindung (Kit) nur, solange etwas animiert.

### Screenshots (`docs/screens/`)

Ohne Studio entstanden (Studio war ab Mittag zu) mit dem neuen Werkzeug
`tools/ui_preview` – es lässt die echten Lua-Module laufen und zeichnet den
UI-Baum nach Roblox-Regeln; das alte Panel sieht darin aus wie im
Playtest-Foto. `D_vorher_nachher_1920.png`, `D_groesse_*.png` (4 Größen mit HUD),
`D_vorher_*.png`, `D_zustand_*.png` (nur Tower I + Kampf läuft, Tower II NEU,
alles offen, Endless, FR, FR Handy, ES 1366, Pass besessen, Pass kaufbar),
`D_x_ecke_vorher_nachher.png`.

## Entscheidungen (Abschnitt 10)

| # | Frage | umgesetzt |
|---|---|---|
| 1 | Freischaltung | Rekord N ≥ Stages N öffnet N+1; kein Deckel; Bestandsschutz (v17) |
| 2 | Auto-Wechsel | nein; Tutorial führt zum Terminal |
| 2b | Veteranen-Regel | Schritt „tower“ ohne Rebirth für alle (Ketten-Regel gilt hier nicht) |
| 3 | Gratis-Start | zeigt die echte freie Stage = 1 (Entscheidung 05.10.), 65 % nicht wieder gratis |
| 4 | Gamepass | id = 0, „Bald“, Besitz nur im Service |
| 5 | Multiplikatoren | **offen (Paket E nicht gebaut)** |
| 6 | Wabenmodell | **offen (Paket F nicht gebaut)** |
| 7 | Palette | warm: Creme/Schoko/Honig/Pink/Himmelblau + Grün für „los“, Tokens |
| 8 | Arena-Prompt | bleibt, öffnet das neue Panel |

## Überschneidungen mit dem Sammel-Update

4.1 Rebirth nach Stage: schon im Code, die neue Freischaltung passt dazu (siehe
B). 5.1 Waben drosseln: unberührt (E/F offen). 3.6/3.8 Erklärung/Schilder: das
Terminal ist ein neues Welt-Schild. 4.3 Tempo-Knopf: unverändert über dem
Fight-Knopf. 2.7 fester Rebirth-Knopf: unverändert; der Deckel-Hinweis „Zum
Rebirth“ entfällt.

## In Studio bringen und prüfen

1. `updates/HBBUpdate.rbxmx` importieren, `updates/HBBUpdate_Befehl.lua` in die
   Befehlsleiste (98 Skripte: ersetzt Quelltext, legt 8 neue an, löscht nichts).
2. `D = game.ServerScriptService.RBLDebug`; vor Tests `D:Invoke("snapshot")`.
3. `D:Invoke("state", "fresh")` → Terminal an der Brücke rot, Bildschirm
   „GESPERRT · Schaffe Tower I 0/30“, Prompt zeigt Hinweis.
4. `D:Invoke("towerrecord", "I", 30)` → Moment „NEUER TOWER!“, Terminal grün
   blinkend mit „!“, Strahl zum Terminal; E → Panel, Rahmen um WÄHLEN (Tower II).
5. WÄHLEN → Terminal ruhig, zeigt Tower II; Führung weg.
6. Panel in 1920×1080, 1366×768, Tablet, Handy quer (Gerätesimulator); Sprache
   EN/FR/ES (Zahnrad). `D:Invoke("pass", "on")` / `"off"`.
7. Brunnen-Prompt: einmal E → Ausbau + Effekt; Doppel-E → nur ein Level;
   zu wenig Gummies → „Es fehlen …“, kein Effekt; `D:Invoke("building",
   "HoneyPond", 9)` dann E → große Variante (Look 2). Recycler genauso.
8. `D:Invoke("parts")` → Insel ≤ 250.
9. `D:Invoke("restore")`. Danach **Datei → Auf Roblox speichern**.

## Assets

Kein Upload nötig: alle benutzten Icons sind hochgeladen (bear, lock, gummy,
goldgummy, egg, trophy, crown). Optional: eigene Bilder für die Tower-Abzeichen
(Holz/Stein/Gold/Kristall/Endless, 256×256, Cartoon mit dunkler Kontur) und
eigene Klänge (Klick, Erfolg, Ausbau, Freischalten) → IDs in
`Icons.luau` bzw. `SoundConfig.luau`.

## Für den Heim-PC

`migration.test.lua`: Fall v16 → v17 (R4 behält III, Rekord in Final hält
Final offen, Rebirth nach v17 öffnet nichts) – steht schon in
`tools/luau-tests/tower_unlock.test.lua` und kann übernommen werden.
`client.test.lua`/`loc.test.lua` laufen nur dort. `progression_pacing.lua` gibt
jetzt die Rekorde an `getStageCap` (sonst sieht die Simulation keine Tower
außer I).

## Was der Auftraggeber entscheiden muss

1. **Palette** (Tokens oben) – passt sie? 2. **Übertragung** von Kit/Theme.v2 auf
die anderen Panels. 3. **Balance:** schnellere Spielmitte akzeptieren oder
Option b/c (siehe B). 4. **E und F freigeben** (Recycler-Multiplikatoren,
Wabenmodell). 5. Quest-Schritt „Wechsle den Tower“ am Ketten-Ende ja/nein.
