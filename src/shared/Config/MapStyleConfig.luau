--!strict
-- MapStyleConfig.luau
-- ReplicatedStorage/Config/MapStyleConfig.luau
--
-- Einzige Zustaendigkeit:
--   - Alle Konstanten fuer den neuen Map-Stil V2 ("Epilog-Insel-Stil"): welche Mesh-
--     Vorlagen es gibt, wie sie gestreut und skaliert werden, Budgets, Asset-IDs.
--
-- Eigene Datei, weil MapConfig bei 192/200 lokalen Namen steht (Roblox-Grenze 200).
-- Schalter: FeatureFlags.MAP_STYLE_V2 (Standard AUS bis zur Abnahme).
-- Test in Studio: D:Invoke("mapstyle", "on" | "off" | "info")
-- Quellen der Meshes: assets/map/*.fbx, Blender-Skripte tools/map_assets/.

local MapStyleConfig = {}

-- Zufall fuer Variante, Drehung und Groesse: EIGENER Strom, damit die alten
-- Positionen (AmbienceConfig.SCENERY_SEED) exakt gleich bleiben.
MapStyleConfig.SEED = 20261020

-- Vorlagen liegen als MeshParts irgendwo unter ServerStorage.Assets (bevorzugt)
-- oder ReplicatedStorage.Assets und werden ueber ihren Namen rekursiv gefunden.
MapStyleConfig.TEMPLATE_PREFIX = "Map_"

MapStyleConfig.GROUND_TILES = { "Map_Wiese_A", "Map_Wiese_B" }
MapStyleConfig.TREES        = { "Map_Baum_A", "Map_Baum_B", "Map_Baum_C", "Map_Baum_D" }
MapStyleConfig.BUSHES       = { "Map_Busch_A", "Map_Busch_B", "Map_Busch_C", "Map_Busch_D", "Map_Busch_E" }
MapStyleConfig.RIM_BUSHES   = { "Map_RimBusch_A", "Map_RimBusch_B" }
MapStyleConfig.ROCKS        = { "Map_Randfels_A", "Map_Randfels_B" }
MapStyleConfig.CRYSTALS     = { "Map_Kristall_A", "Map_Kristall_B" }

-- Noch nicht eingebaut (Mesh ist gebaut, Platzierung folgt nach Abnahme):
MapStyleConfig.UNUSED = { "Map_Ufer_Gerade", "Map_Ufer_Ecke", "Map_Stumpf_A", "Map_Blumen_A", "Map_Gras_A", "Map_Gras_B" }

-- Groesse: +-12 % um die Vorlage (wie im Auftrag), Drehung frei um Y.
MapStyleConfig.SCALE_MIN = 0.88
MapStyleConfig.SCALE_MAX = 1.12

-- Natuerliche Breite der Vorlagen (Studs), um die alten Groessen-Zahlen aus
-- ScenicBuilder (Busch 4-6.5, Fels 3-6, RimBusch 2.6-3.8 ...) abzubilden.
MapStyleConfig.REF_WIDTH = {
	bush     = 6.0,
	rimBush  = 5.0,
	rock     = 5.5,
	rimRock  = 5.0,
}

-- Hoehe der Bodenkachel ueber der Scheibe: Unterkante liegt TILE_LIFT ueber der
-- Scheibe (flimmerfrei), Kollision bleibt bei Ground/PlotIsland.
MapStyleConfig.TILE_LIFT = 0.02

-- Bounding-Box der Vorlagen in Blender-Z (min, max): die MeshPart-Mitte liegt
-- in der Mitte der Box, der Pivot (Boden / Stammfuss) bei z = 0.
MapStyleConfig.MESH_Z = {
	Map_Wiese_A = { 0, 0.169 }, Map_Wiese_B = { 0, 0.17 },
	Map_Randfels_A = { 0, 2.274 }, Map_Randfels_B = { 0, 1.757 },
	Map_Kristall_A = { 0, 3.2 }, Map_Kristall_B = { 0, 3.2 },
	Map_Baum_A = { 0, 15.238 }, Map_Baum_B = { 0, 19.795 }, Map_Baum_C = { 0, 16.114 }, Map_Baum_D = { 0, 8.304 },
	Map_Busch_A = { -0.466, 2.99 }, Map_Busch_B = { -0.716, 3.712 }, Map_Busch_C = { -0.709, 2.831 },
	Map_Busch_D = { -0.496, 4.902 }, Map_Busch_E = { -0.267, 3.233 },
	Map_RimBusch_A = { -0.369, 1.968 }, Map_RimBusch_B = { -0.466, 1.714 },
}

-- Dreiecke je Vorlage (aus Blender gezaehlt, Stand 20.10.2026) und Budgets des Auftrags.
MapStyleConfig.TRIS = {
	Map_Wiese_A = 120, Map_Wiese_B = 120, Map_Ufer_Gerade = 60, Map_Ufer_Ecke = 30,
	Map_Randfels_A = 80, Map_Randfels_B = 80, Map_Kristall_A = 90, Map_Kristall_B = 90,
	Map_Baum_A = 168, Map_Baum_B = 148, Map_Baum_C = 168, Map_Baum_D = 141,
	Map_Stumpf_A = 95, Map_Blumen_A = 160,
	Map_Busch_A = 100, Map_Busch_B = 120, Map_Busch_C = 100, Map_Busch_D = 100, Map_Busch_E = 100,
	Map_RimBusch_A = 80, Map_RimBusch_B = 60, Map_Gras_A = 42, Map_Gras_B = 48,
}
MapStyleConfig.BUDGET = { tile = 400, tree = 320, bush = 120, rimBush = 120 }

-- Kleine Kristall-Akzente auf jedem n-ten Felsen der Hauptinsel (Neon, 1 Part je Gruppe).
MapStyleConfig.CRYSTAL_EVERY = 4

-- Farbvarianten: MeshPart.Color wird mit den Vertexfarben multipliziert, daher nur
-- leichte Toenung. Material bleibt SmoothPlastic.
MapStyleConfig.TINTS = {
	Color3.fromRGB(255, 255, 255),
	Color3.fromRGB(255, 246, 226),
	Color3.fromRGB(236, 255, 232),
	Color3.fromRGB(255, 238, 214),
}
-- Gedaempfte Farben (20.10.): helle Wiesenfelder naeher am dunklen Gras, Laub weniger neon.
MapStyleConfig.TILE_TINT = Color3.fromRGB(118, 158, 112)
MapStyleConfig.FOLIAGE_TINT = Color3.fromRGB(176, 196, 160)
-- Inselboden (Hauptinsel): Noppen-Muster der Classic Baseplate auf der runden Scheibe.
MapStyleConfig.STUD_GROUND = {
	COLOR = Color3.fromRGB(84, 168, 76),
	TEXTURE = "rbxassetid://6372755229",
	TILE = 8,
	TRANSPARENCY = 0.55,
	TEXTURE_COLOR = Color3.new(0.2, 0.2, 0.2),
	MODERN = false, -- true = moderne Textur (alter Weg, bleibt als Option); false = Old-School (P1)
}
-- Old-School-Boden (P1): echte Roblox-Noppen (TopSurface = Studs) auf einem Block-Raster.
-- Zylinder "Ground" darunter bekommt dieselbe Farbe und fuellt den runden Rand.
MapStyleConfig.GROUND = {
	COLOR = Color3.fromRGB(96, 170, 84), -- Baseplate-Noppen in Gruen: zwischen Wiesengruen (84,150,76) und hellem Gruen
	ALT_TON = 0, -- +-Helligkeit im Schachbrett der groessten Kacheln (0 = aus; Baseplate ist einfarbig)
	LEVELS = { 40, 20, 10 }, -- Kantenlaengen grob -> fein (jede teilt die vorige)
	MARGIN = 1, -- Abstand der Block-Ecken zum Inselrand
	THICKNESS = 1,
	LIFT = 0.05, -- Oberkante knapp ueber dem Zylinder (kein Z-Fighting)
	MAX_PARTS = 120,
	-- Die Classic Baseplate (Asset 9111382216) ist ein MODELL: ein Plastic-Block mit
	-- TopSurface = Studs, keine Textur. Darum echte Studs (TEXTURE = ""). Ein Bild
	-- aus einer Textur-ID hier einzutragen legt es stattdessen als Texture auf die Deckflaeche.
	TEXTURE = "",
	TILE = 10,
}
MapStyleConfig.CRYSTAL_COLORS = { Color3.fromRGB(80, 224, 204), Color3.fromRGB(184, 146, 238) }

-- Asset-IDs nach dem Upload (Name -> "rbxassetid://..."). Leer = Vorlagen kommen aus
-- dem Studio-Import unter Assets (Studio-Stand, wird mit dem Place gespeichert).
MapStyleConfig.ASSET_IDS = {} :: { [string]: string }

return MapStyleConfig
