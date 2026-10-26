# Himmelsgericht (`SeraphJudgment`) – Code-Paket 26.10.2026

Stand: gebaut und headless geprüft auf dem Laptop (Claude Code) gegen den Studio-Stand aus `261026aktuell.rbxl` (gespeichert 26.10. 00:11). **Am 26.10. um ca. 15:10 per MCP in Studio eingespielt** (13 Stücke in 8 Skripten, Backup `ServerStorage/Backup_vor_Himmelsgericht_2026-10-26`; der eigene `quake` und der impactframe-Patch entfielen, weil Studio sie seit dem Vormittag schon hat – Gletscherblick/Himmelsgeläut) – der Studio-MCP war in der Sitzung nicht angebunden (Anleitung im Bericht `docs/HBB_HIMMELSGERICHT_2026-10-26.md`). Bühnen, Messlauf, echter Lauf und Review-Vorlage stehen aus.

| Id | Bärchi | Rarity | Stufe / Dauer / Treffer | Effekt |
|---|---|---|---|---|
| `SeraphJudgment` „Himmelsgericht“ | Seraph-Baerchi `SeraphBaerchi` (vorher `SeraphGrace`, Heal 22 %) | Divine | 4 / 5,9 s / 3,28 s; Echo 0,65 / 0,26; Kamerafahrt 1,05–3,55 „seraph“ | Opener: 1. Einsatz je Gegner 3,4× ATK + 60, sonst 1,8× + 60, Ladung 4 |

## Einspielen (Studio, Edit-Modus)

**Weg 1 (empfohlen, löscht nichts, verträgt zwischenzeitliche Änderungen):** `Einfuegen_Befehl.lua` komplett in die Befehlsleiste. Der Befehl
1. legt `ServerStorage/Backup_vor_Himmelsgericht_2026-10-26` an (8 Skript-Klone, Namen `Config_SkillFXConfig`, `Controllers_SkillFXController`, `Strings_de` …),
2. prüft auf dem LIVE-Quelltext jeden Anker (genau 1×) und jeden neuen Namen (0×) – bei MISS/DUP wird **nichts** geändert,
3. baut die neuen Quelltexte, prüft sie mit `loadstring`,
4. speichert per `ScriptEditorService:UpdateSourceAsync` (Rückfall `.Source =`), zwei Waypoints → Strg+Z macht alles rückgängig.
Erwartete Ausgabe: 13× `ok`, „Himmelsgericht eingefuegt: 13 Stuecke in 8 Skripten“ (Nutzlast-Hashes werden vorher geprüft). Headless simuliert: erzeugt byteidentisch die geprüften Quelltexte (`_pruefsummen.json`, `md5_nachher`).

**Weg 2 (Rückfall, ganze Quelltexte):** `HBBUpdate_Himmelsgericht_2026-10-26.rbxmx` in Studio importieren (landet als `workspace.HBBUpdate_Himmelsgericht`), dann `HBBUpdate_Himmelsgericht_2026-10-26_Befehl.lua` in die Befehlsleiste. Ersetzt ein Skript nur, wenn sein Live-Quelltext noch dem Stand von 00:11 entspricht (Hash `(h·31 + Byte) mod 2^31`, Werte in `_pruefsummen.json` → `hash_vorher`); geänderte Skripte werden übersprungen und gemeldet (dann Weg 1).

Danach: Datei → Auf Roblox speichern. Dann Phase 4/5 des VFX-Skills (Bühnen, Messlauf, echter Lauf).

## Anker (auf dem Studio-Stand 26.10. 00:11; Einrückung Tabs)

| Datei | Stück | Modus | Anker |
|---|---|---|---|
| `Controllers/SkillFXController` | `pieces/ctxfields.luau` | hinter der 1. Ankerzeile | `\tavatarModel: Model?,\n}\n` |
| `Controllers/SkillFXController` | `local seraphSide = 0` | hinter | `\tlocal chaseEye: Vector3? = nil\n` |
| `Controllers/SkillFXController` | `pieces/cinematic.luau` | vor | `\t\telse\n\t\t\tlocal a = k * math.pi * 0.9\n` |
| `Controllers/SkillFXController` | `pieces/impactframe_palette.luau` | vor | `\tlocal function look(kind: string)\n\t\tlocal darkK = kind == "d"\n\t\tcc.Saturation = -1\n` |
| `Controllers/SkillFXController` | Tint-Zeile | ersetzen | `cc.TintColor = if darkK then Color3.fromRGB(255, 55, 55) else Color3.new(1, 1, 1)` → `… darkTint else lightTint` |
| `Controllers/SkillFXController` | Fill-Zeile | ersetzen | `h.FillColor = if darkK then Color3.fromRGB(170, 0, 12) else Color3.new(0, 0, 0)` → `… darkFill else Color3.new(0, 0, 0)` |
| `Controllers/SkillFXController` | `pieces/blocks.luau` (SER, quake, seraphwings, seraphspear, halogate, seraphmark, lightnuke) | vor | `-----…-----\n-- Abspielen\n` |
| `Config/SkillFXConfig` | `pieces/fxdoc.txt` | hinter | `--   Helfer (LOW): bridge (Bruecken-Punkt), tube (Zylinder-Stueck), shuriken (Vierstern).\n` |
| `Config/SkillFXConfig` | `pieces/textures.luau` | hinter | `\t\tshockring = 94175665045126,  -- wie CometImpact.shockring (ring)\n\t},\n` |
| `Config/SkillFXConfig` | `pieces/fxentry.luau` | vor | `\n}\n\n-- Unbekannte Faehigkeit` |
| `Config/SkillConfig` | `pieces/skillentry.luau` | vor | `\n}\n\n-- ====…\n-- v15: AUFLADEN STATT COOLDOWN` |
| `Config/BaerchiConfig` | `pieces/baerchiconfig_defaultskill.txt` | ersetzen | `\t\tdefaultSkill = "SeraphGrace", eggSource = {},\n` |
| `Strings/de,en,es,fr` | `pieces/strings_<sprache>.txt` | hinter | die Zeile `["skill.SeraphGrace.name"] = "…",` |

Neue Namen (müssen vorher 0× vorkommen): `local SER`, `BLOCKS.quake/seraphwings/seraphspear/halogate/seraphmark/lightnuke`, `seraphGate`, `seraphHit`, `seraphSide`, `SkillFXQuake`, `style == "seraph"`, `darkTint/lightTint/darkFill`, `SeraphJudgment`.

Namensbudget Controller nach dem Einbau: 141 lokale Namen auf Modulebene (vorher 140; alle Helfer in der Tabelle `SER`).

## Geprüft (ohne Studio)

`luau-compile --null` aller 8 Dateien ok · `egg_tree_check`, `fight_timeline`, `ui_texts` (1312 Texte, 0 Fehler), `combat_rating`, `tower_calibration` (alle Ziele, Divine Final 100), `boss_balance`, `rarity_capability` auf dem Baum „Studio + Himmelsgericht“ ok · Anker/Namen-Prüfung ok · keine Verdeckung von Modul-Helfern (F57) · Befehl headless simuliert (byteidentisch). Review durch fünf unabhängige Prüfer: siehe Bericht.

## Werkzeuge (`tools/`)

- `rbxl_extract_scripts.py <place.rbxl> <ordner>` – alle Skripte einer binären Place-Datei (zstd-Chunks) als Dateien + `_INDEX.txt` (braucht `pip install --user zstandard`).
- `rbxl_dump_subtree.py <place.rbxl> <Pfad> <out>` – Instanzbaum mit Größen, Farben, CFrames (z. B. `ReplicatedStorage/Assets/BaerchiModels/Pet_Seraph`).
- `apply_seraph.py <studio_src> <pieces> <out>` – Anker-Einfügung in Kopien (1×/0×-Prüfung), Quelle der Wahrheit für den Befehl.
- `make_seraph_package.py <studio_src> <studio_mod> <pieces> <out>` – erzeugt `Einfuegen_Befehl.lua`, die rbxmx und `_Befehl.lua`, `_pruefsummen.json`.

Bericht: `docs/HBB_HIMMELSGERICHT_2026-10-26.md`.
