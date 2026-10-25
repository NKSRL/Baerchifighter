# Anime-Baerchis: Skalierung und Aufraeumen (21.10.2026)

## Befund
- Im Workspace lagen vier graue Rohimporte `Anime_Pirat/Ninja/Krieger/Jaeger` (unverankert, ca. 235-365 Studs gross): beim Spielstart fielen sie auseinander (riesige weisse Formen im Himmel).
- In `ReplicatedStorage.Assets.BaerchiModels` lagen schon dieselben vier Modelle, bereits nach `build_w2_anime.py`/`studio_recolor_w2_anime.lua` gefaerbt (0 graue Teile), aber im Import-Massstab 100x zu gross. Referenz: `Bear_Braunbaer` 2.3 x 2.6 x 2.2 Studs, `Pet_Omega` 4.2 x 4.1 x 2.4. `BaerchiMesh` skaliert nur um `BAERCHI_SCALE` (1.15), normalisiert aber nicht.

## Gemacht (nur Studio, kein Repo-Code)
- Backup: `ServerStorage.Backup_vor_AnimeSkalierung_2026-10-21` mit `Bibliothek_vorher` (Klone der 4 Modelle) und `Workspace_Rohimport_grau` (die 4 grauen Modelle, aus dem Workspace verschoben, nichts geloescht).
- Die 4 Bibliotheksmodelle mit `ScaleTo(0.01)` skaliert (Model-Scale 0.01, Teile 1:1 mitskaliert).

## Geprueft
- `BaerchiMesh.buildFor` fuer alle 4 IDs (GummiPirate/OrangeNinja/StarWarrior/PlaidHunter): baut ohne Fehler, Hoehe 3.05 / 3.00 / 3.76 / 3.00 Studs (Braunbaer ca. 3.0, Omega 4.7), alle Teile verankert.
- Workspace ohne Riesenteile (ausser Platform-Inseln).

## Offen
- Sichtprobe in Studio (Schluepfen, Plot, Index): ungeprueft, die Screenshot-Funktion zeigt die 3D-Welt nicht.
- Gleiches Mass-Problem bei `Pet_Genesis`, `Pet_Infinity`, `Pet_Shade`, `Pet_Ascendant` (je ca. 235-310 Studs): noch nicht korrigiert.
- Studio speichern; Modelle als `.rbxm` nach `src/shared/Assets` exportieren (nur lokal vorhanden). Verdrahtung `ANIME_EGG` laut Plan weiterhin offen.
