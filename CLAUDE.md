# RBL / Honey Bear Brawl – Hinweise für Claude Code

Roblox-Spiel (Luau). Einstieg in dieser Reihenfolge, nicht mehr:
1. `docs/STATUS.md` – Stand je Bereich, offene Punkte, was zwischen Studio und Repo abweicht
2. `docs/ARCHITEKTUR.md` – Modulkarte (eine Zeile je Datei); per Grep nach Begriff durchsuchen
3. Nur den Bericht aus `docs/INDEX.md`, den die Aufgabe braucht

## Struktur
- `src/shared` → ReplicatedStorage: `Config` (Werte), `Modules` (reine, testbare Regeln), `Network/Types` + `Network/Remotes` (einzige Quellen), `Localization`
- `src/server` → ServerScriptService: `Core/GameManager` startet alles; `Services`; `Util/MapBuild` baut die Welt; `Debug` nur Studio
- `src/client` → StarterPlayerScripts: `Main.client` lädt; `Controllers` (Welt, Verhalten); `UI` (Fenster); `ClientState` ist der einzige Client-Speicher
- Schalter: `FeatureFlags.isOn("NAME")` in `src/shared/Config/FeatureFlags.luau`

## Regeln
- `--!strict`, deutsche Kommentare: das Warum, nicht die Geschichte (keine Daten oder Paketnummern im Code; Kopfkommentar höchstens 25 Zeilen). Bestehendes beim Anfassen kürzen.
- Texte nur über `Loc` (de/en/fr/es). Config-Namen/-Beschreibungen nur über `Localization/Names`, Server-Texte in der Welt nur über `Localization/WorldText` mit `Loc.msg`. Meldungen an den Spieler über `Notify.emit`.
- Server ist autoritativ; Währungen schreibt nur `EconomyService`; Remotes nur über `RateLimiter.connect`.
- Neue Zuständigkeit = neue Datei; keine Datei über 800 Zeilen wachsen lassen.
- Nichts aus Studio löschen. Kopien und Sicherungen gehören nicht ins Repo (Git ist die Sicherung; Ordner `backup_vor_*` sind ignoriert).
- Dateien, die laut `docs/STATUS.md` in Studio neuer sind, im Repo nicht ändern.

## Sparsam lesen
- Erst Grep, dann Read mit offset/limit auf den Treffer. Dateien über 400 Zeilen nie komplett lesen, außer die Aufgabe verlangt es.
- `Localization/Strings/*.luau` (je 80 KB) nur per Grep nach Schlüssel; ändern per Edit am Schlüssel.
- `docs/Worldbuilding.md` nur den nötigen Abschnitt (Überschriften per Grep `^##`).
- Bilder, `assets/`, `Export/`, `studio_export/` nicht öffnen, außer der Nutzer will eine Sichtprüfung.
- Am Ende der Sitzung `docs/STATUS.md` fortschreiben; neuer Bericht nur bei neuem Paket, dann eine Zeile in `docs/INDEX.md`.

## Prüfen (vor jedem Commit)
`python tools/check_all.py` – Syntax, Locals (Roblox erlaubt max. 200 je Modul-Ebene), alle `check_*.py`, Modulkarte, alle Luau-Tests, Pflicht-Sims. Zeigt nur Rotes; `--schnell` ohne `check_ui` (spart ~70 s), `-v` zeigt alles.
- Neue oder umbenannte Module: `python tools/make_modulkarte.py` (sonst meldet `check_all` die Karte als veraltet).
- Luau-CLI: in Cloud-Sitzungen legt der SessionStart-Hook sie nach `luau-bin/`. Auf dem Laptop von https://github.com/luau-lang/luau/releases (`luau-windows.zip`) nach `luau-bin/` entpacken.
- Balance-Änderungen: die Sims in `check_all` müssen grün bleiben (`progression_pacing`, `tower_calibration` u. a.).

## In Studio bringen
Empfohlen, löscht nichts: `python tools/make_update_rbxmx.py [<seit-commit>]` → `updates/HBBUpdate.rbxmx` in Studio importieren, dann `updates/HBBUpdate_Befehl.lua` in die Befehlsleiste. Ersetzt nur den Quelltext geänderter Skripte, legt neue an; Strg+Z macht es rückgängig. Hält Dateien zurück, die in Studio neuer sind (`STUDIO_VORAUS`).
Danach in Studio: Datei → Auf Roblox speichern.

**Kein Rojo**: `rojo serve` macht ReplicatedStorage/ServerScriptService/StarterPlayerScripts exakt zum Repo-Stand und löscht alles, was nur in Studio existiert (07.10. ging so ein Studio-Inhalt verloren). `src/shared/Assets/BaerchiTemplate.rbxm` fehlt im Repo.
