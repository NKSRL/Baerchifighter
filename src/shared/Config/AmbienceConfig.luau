--!strict
-- AmbienceConfig.luau
-- ReplicatedStorage/Config/AmbienceConfig.luau
--
-- Einzige Zustaendigkeit:
--   - Alle Zahlen fuer Himmel, Licht-Stimmung, Landschafts-Deko und die
--     Client-Atmosphaere (Wolken, Pollen, Schaum)
--
-- Reine Optik, keine Spielbalance. Gelesen von SkyBuilder und ScenicBuilder
-- (Server, einmal beim Start) und AmbienceController (Client, laufend).
-- Die Performance-Regler stehen unten: "QUALITAET".

local AmbienceConfig = {}

--------------------------------------------------------------------------------
-- HIMMEL UND LICHT ("goldene Stunde")
--------------------------------------------------------------------------------
-- Die Atmosphaere macht den Himmel: tiefblau oben, rosa-goldener Horizont.
-- Das kostet keine einzige Part und keine Textur.
AmbienceConfig.CLOCK_TIME        = 16.9    -- spaeter Nachmittag, lange weiche Schatten
AmbienceConfig.BRIGHTNESS        = 2.4
AmbienceConfig.AMBIENT           = Color3.fromRGB(120, 118, 150)
AmbienceConfig.OUTDOOR_AMBIENT   = Color3.fromRGB(150, 150, 185)
AmbienceConfig.COLOR_SHIFT_TOP   = Color3.fromRGB(255, 225, 190)
AmbienceConfig.DIFFUSE_SCALE     = 0.6
AmbienceConfig.SPECULAR_SCALE    = 0.5
AmbienceConfig.SHADOW_SOFTNESS   = 0.25
AmbienceConfig.GEO_LATITUDE      = 20

AmbienceConfig.ATMOSPHERE_DENSITY = 0.30
AmbienceConfig.ATMOSPHERE_OFFSET  = 0.25
AmbienceConfig.ATMOSPHERE_COLOR   = Color3.fromRGB(255, 200, 200)
AmbienceConfig.ATMOSPHERE_DECAY   = Color3.fromRGB(255, 140, 120)
AmbienceConfig.ATMOSPHERE_GLARE   = 0.5
AmbienceConfig.ATMOSPHERE_HAZE    = 1.6

AmbienceConfig.STAR_COUNT         = 2500
AmbienceConfig.SUN_SIZE           = 18
AmbienceConfig.MOON_SIZE          = 10

-- Echte Wolken (Terrain-Clouds): eine Zeile Instanz, GPU-seitig, praktisch gratis.
AmbienceConfig.CLOUDS_COVER   = 0.6
AmbienceConfig.CLOUDS_DENSITY = 0.65
AmbienceConfig.CLOUDS_COLOR   = Color3.fromRGB(255, 235, 235)

--------------------------------------------------------------------------------
-- MEERESBODEN UND SCHAUM (Server, je 1 Part pro Insel)
--------------------------------------------------------------------------------
-- Ohne Boden schaut man durch das Wasser ins Nichts. Der Boden liegt knapp
-- unter der Wasserunterkante und laesst das Wasser tuerkis tief wirken.
AmbienceConfig.SEABED_Y       = -13.2
AmbienceConfig.SEABED_COLOR   = Color3.fromRGB(52, 150, 168)
AmbienceConfig.SEABED_RADIUS  = 720

-- Schaumsaum: eine weisse, flache Scheibe je Insel, die ueber den Sand hinaus
-- ragt. Der Client laesst die Durchsichtigkeit leise atmen.
AmbienceConfig.FOAM_REACH         = 3.5    -- wie weit der Schaum ueber die Sandkante hinausreicht
AmbienceConfig.FOAM_COLOR         = Color3.fromRGB(255, 255, 255)
AmbienceConfig.FOAM_TRANSPARENCY  = 0.55
AmbienceConfig.FOAM_PULSE         = 0.2    -- +/- Schwankung
AmbienceConfig.FOAM_PULSE_PERIOD  = 4.5    -- Sekunden

--------------------------------------------------------------------------------
-- LANDSCHAFT (Server, einmal beim Start, deterministisch)
--------------------------------------------------------------------------------
AmbienceConfig.SCENERY_SEED = 20261004

-- Hauptinsel: Baeume, Buesche, Felsen, Pilze. Zwischen Event-Pit und Inselrand.
AmbienceConfig.TREE_COUNT     = 22
AmbienceConfig.BUSH_COUNT     = 26
AmbienceConfig.ROCK_COUNT     = 16
AmbienceConfig.MUSHROOM_COUNT = 12
AmbienceConfig.SCENERY_INNER  = 64      -- Abstand zur Mitte, ab dem Deko erlaubt ist (Pit = 50 + Ring)
AmbienceConfig.SCENERY_OUTER  = 108     -- bis hier (Insel = 120, Sandkante, Handler bei 108)
AmbienceConfig.LANE_MARGIN    = 9       -- Abstand zur Wegachse, den Deko freihaelt
AmbienceConfig.MERCHANT_CLEAR = 16      -- Freiraum um den versteckten Ei-Haendler

AmbienceConfig.TREE_TRUNK_COLOR   = Color3.fromRGB(122, 84, 52)
AmbienceConfig.TREE_CANOPY_COLORS = {
	Color3.fromRGB( 72, 170,  80),
	Color3.fromRGB( 96, 190,  92),
	Color3.fromRGB(255, 160, 190),   -- Bluetenbaum
}
AmbienceConfig.BUSH_COLORS = {
	Color3.fromRGB(64, 156, 72),
	Color3.fromRGB(84, 176, 84),
	Color3.fromRGB(110, 190, 90),
}
AmbienceConfig.ROCK_COLORS = {
	Color3.fromRGB(150, 150, 162),
	Color3.fromRGB(132, 132, 148),
}

-- Wege: helle Pflasterbahn von der Event-Pit-Kante bis zum Steg, acht Stueck.
-- Sie zeigen den Weg (wie die blumenfreien Gassen) und brechen das Gruen auf.
AmbienceConfig.PATH_WIDTH     = 10
AmbienceConfig.PATH_COLOR     = Color3.fromRGB(222, 196, 146)
AmbienceConfig.PATH_LIFT      = 0.14   -- ueber der Wiese (Karo liegt bei 0.08)

-- Laternen entlang der Wege (Pfosten + leuchtende Kugel, ohne PointLight).
AmbienceConfig.LAMP_RADII     = { 72, 100 }
AmbienceConfig.LAMP_SIDE      = 7.5
AmbienceConfig.LAMP_HEIGHT    = 6
AmbienceConfig.LAMP_POLE_COLOR = Color3.fromRGB(110, 76, 48)
AmbienceConfig.LAMP_GLOW_COLOR = Color3.fromRGB(255, 205, 110)

-- Stegpfosten: vier je Steg (an beiden Enden, beide Seiten) mit Leuchtkappe.
AmbienceConfig.BRIDGE_POST_HEIGHT = 4.6
AmbienceConfig.BRIDGE_POST_INSET  = 3

-- Plot-Inseln: Felsen und Schilf am Rand. Haelt die Stegachse frei.
AmbienceConfig.PLOT_RIM_COUNT   = 9
AmbienceConfig.PLOT_RIM_MIN     = 55
AmbienceConfig.PLOT_RIM_MAX     = 57
AmbienceConfig.PLOT_RIM_LANE    = 10    -- Halbbreite der freien Stegachse

--------------------------------------------------------------------------------
-- CLIENT-ATMOSPHAERE
--------------------------------------------------------------------------------
-- Wolkenpuffs und ferne Schwebeinseln: laufen nur beim Spieler, kosten den
-- Server nichts und werden nicht repliziert.
AmbienceConfig.CLOUD_PUFFS_HIGH   = 18
AmbienceConfig.CLOUD_PUFFS_LOW    = 8
AmbienceConfig.CLOUD_RING_MIN     = 750
AmbienceConfig.CLOUD_RING_MAX     = 1250
AmbienceConfig.CLOUD_HEIGHT_MIN   = 110
AmbienceConfig.CLOUD_HEIGHT_MAX   = 300
AmbienceConfig.CLOUD_COLOR        = Color3.fromRGB(255, 232, 236)
AmbienceConfig.CLOUD_DRIFT_SPEED  = 0.0035   -- Radiant pro Sekunde (eine Runde ~ 30 Minuten)

AmbienceConfig.FAR_ISLANDS_HIGH   = 5
AmbienceConfig.FAR_ISLANDS_LOW    = 2
AmbienceConfig.FAR_ISLAND_RING    = 1050
AmbienceConfig.FAR_ISLAND_HEIGHT  = 140

-- Pollen / Glitzer, der um die Kamera schwebt (ein ParticleEmitter).
AmbienceConfig.POLLEN_RATE        = 7
AmbienceConfig.POLLEN_COLOR       = Color3.fromRGB(255, 226, 140)

--------------------------------------------------------------------------------
-- QUALITAET
--------------------------------------------------------------------------------
-- Ab dieser Roblox-Grafikstufe (1..10) laeuft die "hohe" Variante. Darunter
-- (schwache Handys) gibt es weniger Wolken und keine Partikel. Auto-Qualitaet
-- (Stufe 0) zaehlt als hoch.
AmbienceConfig.HIGH_QUALITY_FROM  = 4

return AmbienceConfig
