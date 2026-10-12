# Studio ↔ Repo abgeglichen (08.10.2026)

## Was passiert war

Das Repo kannte nicht den ganzen Studio-Stand: In Studio gab es 14 Skripte,
die nie im Repo waren (Inkubator: `IncubatorService/-Panel/-Controller/
-Builder/-Config/-Rules`, `PitBrawlService`, `SpecialMilestoneService`,
`IndexRewardService/-Config`, `AreaSignController`, `CurrencyHint`, `HudRow`,
`RebirthButton`) und 68 Skripte, die in Studio weiter waren (Sammel-Updates
mit eigener Übersetzungsrunde, Inkubator-Anbindung). Rojo hat diesen Stand
beim Verbinden gelöscht; die erste Update-Datei hat ihn teilweise
überschrieben → Fehler `PitBrawlService … nil`, `SpecialMilestoneService …
nil`, `IncubatorService:505`.

## Was jetzt gilt

- Studio-Stand vor dem Update: `studio_export/Studio_Stand_2026-10-08.rbxlx`
  (Sicherung) und als Commit `8d1da3f` im Repo (Branch
  `studio-sync-2026-10-08`).
- Zusammengeführt mit UI-Qualität 1+2 und Handy-Fix (Commit `e6268b6`).
  Regel: Spiel-Logik und Texte aus Studio haben Vorrang; darauf wieder
  eingesetzt: Fenster passen auf kleine Bildschirme, Trefferfläche am X,
  Bärchi-Karte in der Fensterhülle (ein X statt zwei), Ausweichen vor der
  Touch-Steuerung, Welt-Texte (Event-/PIT-Tafel, Namensschild) über
  `WorldText`/`Names`, Sprachdateien vereinigt (Studio-Text gewinnt).
- Gegenprobe: jede Zeile, die Studio gegenüber dem alten Repo hinzugefügt
  hat, steht im Ergebnis — außer 40 bewusst ersetzten (Namen über `Names`,
  doppeltes X, feste Texte).
- `updates/HBBUpdate.rbxmx` (48 Skripte) ist gegen den Studio-Stand gebaut:
  `python tools/make_update_rbxmx.py studio-sync-2026-10-08`.

## Offen: Tests, die Studio-Regeln noch nicht kennen

Schon am reinen Studio-Stand rot (nicht durch das Zusammenführen):

| Test | Meldung |
|---|---|
| `guide_steps` | „gekämpft, keine Eier → event: erwartet event, bekommen combs“ |
| `unlock_rules` | „Veteran: alles außer Shop: erwartet 19, bekommen 17“ |
| `migration_hbb` | „C4 Rekord Tower I = 20: erwartet 20, bekommen 17“ |
| `progression_pacing` | „Normal: Rebirth 1 nach ~2–3 Spieltagen: 0.9 h“ |

Entweder sind die Tests veraltet (Studio hat die Regeln bewusst geändert)
oder die Studio-Änderung hat einen Fehler. Das muss die Person entscheiden,
die die Regeln geändert hat — besonders `migration_hbb` (Rekord 20 → 17
nach der Migration) und das Pacing (Rebirth nach 0,9 h statt 1,5–4,5 h).

## Künftig

Nie wieder Rojo gegen diesen Ort ohne vorherigen Export. Nach jeder Arbeit
direkt in Studio: Ort als `.rbxlx` nach `studio_export/` speichern und
pushen, damit das Repo nicht wieder zurückfällt.
