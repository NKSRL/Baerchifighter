--!strict
-- PitV2Config.luau
-- ReplicatedStorage/Config/PitV2Config.luau
--
-- Einzige Zustaendigkeit:
--   - Daten des Honig-Kolosseums (Schalter PIT_V2): Vorlagen, Farbe und
--     Material je Mesh-Teil, unsichtbare Kollision und der Kollisionsring der
--     obersten Turm-Etage
--
-- Geometrie-Quelle: tools/pit/pit_kolosseum_scene.py (Blender, 1 Einheit = 1 Stud),
-- passend zu MapConfig (PIT_RADIUS 26, PIT_BASE_RADIUS 30, Ufer 38 / -1.35).
-- Arena-Koordinaten wie dort: x = quer, y = laengs (+ = Steg), Hoehe ueber der
-- Kampfflaeche; Winkel 0 = +x, 90 = Steg. Umrechnung: Modules/PitV2Rules,
-- Aufbau: Util/MapBuild/PitV2Builder.
-- Bericht: docs/Worldbuilding.md (Abschnitt Kampf-Pit V2)

local PitV2Config = {}

-- Vorlagen (FBX-Import 25.10.): ServerStorage.Assets.PitV2.Arena (6 Meshes,
-- Pivot = Arena-Mitte auf Kampfflaechen-Hoehe, -Z zum Steg) und .Stufe
-- (2 Meshes, Pivot = Etagen-Oberkante). Fehlt eine, bleibt das alte Pit.
PitV2Config.TEMPLATE_FOLDER = "PitV2"
PitV2Config.ARENA_TEMPLATE  = "Arena"
PitV2Config.STAGE_TEMPLATE  = "Stufe"

export type PartLook = {
	color    : Color3,
	material : Enum.Material,
	lane     : boolean?,   -- Farbe aus AmbienceConfig.LANE_COLORS[slot] (Wimpel, Banner)
	shadow   : boolean?,   -- false: flache oder leuchtende Teile werfen keinen Schatten
}

-- Studio verwirft die FBX-Farben, deshalb Farbe und Material je Teilname.
PitV2Config.PARTS = {
	Pit_Sandstein  = { color = Color3.fromRGB(238, 223, 192), material = Enum.Material.SmoothPlastic },
	Pit_Schiefer   = { color = Color3.fromRGB( 48,  43,  64), material = Enum.Material.SmoothPlastic },
	Pit_Gold       = { color = Color3.fromRGB(242, 188,  64), material = Enum.Material.Metal },
	Pit_Waben      = { color = Color3.fromRGB(236, 182,  82), material = Enum.Material.SmoothPlastic, shadow = false },
	Pit_Honig      = { color = Color3.fromRGB(255, 196,  56), material = Enum.Material.Neon, shadow = false },
	Pit_Wimpel     = { color = Color3.fromRGB(215,  60,  75), material = Enum.Material.SmoothPlastic, lane = true, shadow = false },
	Pit_Stufe_Rand = { color = Color3.fromRGB(238, 223, 192), material = Enum.Material.SmoothPlastic },
	Pit_Stufe_Gold = { color = Color3.fromRGB(242, 188,  64), material = Enum.Material.Metal, shadow = false },
} :: { [string]: PartLook }

-- Bestehende Teile im neuen Look: der Sockel ist zwischen Honigrinne und Mauer
-- und in den Toren zu sehen, die Kampfflaeche als Fugen zwischen den Waben.
PitV2Config.BASE_COLOR    = Color3.fromRGB(234, 212, 166)
PitV2Config.BASE_MATERIAL = Enum.Material.SmoothPlastic
PitV2Config.FLOOR_COLOR   = Color3.fromRGB(247, 236, 212)

export type ArcCollider = {
	inner    : number,   -- abzudeckendes Band (Radius)
	outer    : number,
	bottom   : number,   -- Hoehe ueber der Kampfflaeche
	top      : number,
	from     : number,   -- Winkel in Grad (Arena-Koordinaten)
	to       : number,
	segments : number,
}
export type BlockCollider = { x: number, y: number, size: number, bottom: number, top: number }

-- Unsichtbare Kollision. Die Meshes haben keine. Mauer und Tribuene sind EIN
-- Block je Bogenstueck: innen ab der Mauerkrone, aussen bis vor die Pilaster,
-- oben bis zur Goldkante (7.55 ist von der Kampfflaeche aus nicht erspringbar).
-- So kann niemand in die Tribuene fallen und darin stecken bleiben.
-- Die Boegen enden an den Torpfeilern (Tor-Halbwinkel 18 Grad um 90 und 270).
PitV2Config.ARC_COLLIDERS = {
	{ inner = 27.9, outer = 35.95, bottom = -1.35, top = 7.55, from = -72, to = 72,  segments = 12 },
	{ inner = 27.9, outer = 35.95, bottom = -1.35, top = 7.55, from = 108, to = 252, segments = 12 },
} :: { ArcCollider }

-- Torpfeiler (Sockel 2.4) und Ecktuerme (Sockel 3.0), Mitte in Arena-Koordinaten.
PitV2Config.BLOCK_COLLIDERS = {
	{ x =  8.84, y =  27.2, size = 2.4, bottom = -0.35, top = 10 },
	{ x = -8.84, y =  27.2, size = 2.4, bottom = -0.35, top = 10 },
	{ x =  8.84, y = -27.2, size = 2.4, bottom = -0.35, top = 10 },
	{ x = -8.84, y = -27.2, size = 2.4, bottom = -0.35, top = 10 },
	{ x =  36.4, y =  0,    size = 3.0, bottom = -1.35, top = 9.8 },
	{ x = -36.4, y =  0,    size = 3.0, bottom = -1.35, top = 9.8 },
} :: { BlockCollider }

-- Verlaengerung je Bogenstueck, damit zwischen zwei Bloecken keine Fuge bleibt.
PitV2Config.COLLIDER_OVERLAP = 0.2

-- Kollisionsring der obersten Turm-Etage (Gelaender aussen auf R 26.55..26.85,
-- Sims bis 27.1). 3 Studs hoch: verhindert das Herunterlaufen, ein gewollter
-- Sprung geht weiter. Auf dem gehaltenen Gipfel aus (dort fuehrt die Bruecke hinaus).
PitV2Config.TOWER_FENCE = {
	name     = "PitV2_TurmZaun",
	inner    = 26.5,
	outer    = 27.1,
	height   = 3,
	segments = 16,
}

return PitV2Config
