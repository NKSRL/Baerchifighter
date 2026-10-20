# P1 – Old-School-Boden (20.10.2026)

**Status:** Code fertig, Tests gruen. Studio-Screenshots (vorher/nachher) stehen noch aus (siehe Offen).

## Analyse (2 Saetze)
Das Studio-Modell `Classic Baseplate` ist ein Block (512x20x512, Plastic, Farbe 99/95/98) mit `TopSurface = Studs`. Studs gibt es nur auf Bloecken, nicht auf Zylindern oder Meshes; deshalb wurde Variante A gewaehlt.

## Entscheidung: Variante A (Block-Raster)
- `MapStyleRules.groundCells(120, {40,20,10}, 1)` liefert ein Raster, das nur Bloecke setzt, deren vier Ecken im Kreis liegen; Randzellen werden auf 20 und 10 Studs verfeinert.
- **65 Bloecke** (Budget 120), decken ca. 87 % der Insel; der Zylinder `Ground` darunter bekommt dieselbe Farbe und fuellt den runden Rand. Sandkante `SHORE_*` unveraendert.
- B (Blender-Mesh) und C (eigene Textur) wurden **nicht** gebaut: A liefert die echten Noppen ohne Upload. Falls Screenshot-Vergleich in Studio etwas anderes zeigt, bleiben B/C Optionen.
- Bloecke: `CanCollide/CanQuery/CanTouch = false`, 5 cm ueber dem Zylinder (kein Z-Fighting); begehbar bleibt der Zylinder.
- Farbe `MapStyleConfig.GROUND.COLOR` (84,150,76), schwacher Zweiton +-4 % im 40er-Raster (`ALT_TON`, 0 = aus).

## Wo
- `Config/MapStyleConfig` (`GROUND`, `STUD_GROUND.MODERN = false`), `Modules/MapStyleRules.groundCells`, `Util/MapBuild/MapMeshes.groundOldschool` und `studGround` (Ordner `GroundStuds` im `Platform`-Modell).
- Schalter `MAP_GROUND_OLDSCHOOL` (aus = bisherige moderne Textur), plus `mapstyle on/off`: `off` raeumt `GroundStuds` weg und stellt Farbe/Material wieder her.
- Test: `map_style.test.lua` (5 neue Pruefungen).

## Studio
`Classic Baseplate` wurde aus dem Workspace nach `ServerStorage.Assets.Map_BodenAlt_Vorlage` verschoben (nichts geloescht).

## Offen
- Play-Test-Screenshots vorher/nachher, Abnahme der Optik (Kachelgroessen 40/20/10 evtl. anpassen).
- Update-Datei `updates/HBBUpdate_Boden_2026-10-20.rbxmx` per `make_update_rbxmx.py` erzeugen (wird mit P2-P4 gesammelt).
