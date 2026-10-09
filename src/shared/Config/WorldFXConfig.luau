--!strict
-- WorldFXConfig.luau
-- ReplicatedStorage/Config/WorldFXConfig.luau
--
-- Einzige Zustaendigkeit:
--   - Alle Optik-Zahlen fuer "Welt aufwerten" (Auftrag 08.10.2026): Tageslauf,
--     Wasser und Kueste, Hauptinsel, Texturen, Qualitaetsstufen, feste
--     Kamerapunkte fuer Screenshots
--
-- Reine Optik, keine Spielbalance. Gelesen von Modules/DayCycle und den
-- Client-Controllern DayCycleController, WaterController, HubController und
-- WorldShotController. Nichts davon laeuft auf dem Server (ausser der
-- Debug-Befehl, der nur Attribute setzt).
--
-- Warum nicht AmbienceConfig: die bleibt fuer den festen Himmel und die
-- Server-Landschaft (SkyBuilder/ScenicBuilder). Der Hauptschalter DAY_CYCLE
-- steht trotzdem dort, weil er den festen Himmel abloest.
-- Warum nicht MapConfig: die steht bei 191 von 200 lokalen Namen.

local WorldFXConfig = {}

--------------------------------------------------------------------------------
-- TEXTUREN
--------------------------------------------------------------------------------
-- Gezeichnet von tools/textures/make_world_textures.py, abgelegt unter
-- assets/world/<paket>/. Hochladen: Studio → Asset Manager → Bulk Import (Typ
-- Image), dann die ID hier eintragen ("rbxassetid://123").
--
-- Leerer String = noch nicht hochgeladen: dann gilt FALLBACK (eine eingebaute
-- Roblox-Textur) oder der Aufrufer laesst das Bild ganz weg und zeigt nur
-- Farbe/Neon. Alles laeuft also auch ohne Upload.
WorldFXConfig.TEXTURE_IDS = {
	-- Paket A
	cloud_puff_flipbook = "",
	firefly             = "",
	star_twinkle        = "",
	-- Paket B
	water_glitter       = "",
	water_waves         = "",
	foam_lace           = "",
	splash_flipbook     = "",
	water_ring          = "",
	-- Paket C
	amber_comb          = "",
	honey_drop          = "",
	honey_bubble        = "",
	bee_flipbook        = "",
	wasp_flipbook       = "",
	pennant_fabric      = "",
	stall_stripes       = "",
	bear_sign           = "",
	shine_strip         = "",
	-- Paket E–F (D braucht keine: Blumen, Pilze, Bienenhaus sind Formen)
	flag_fabric         = "",
	paw_print           = "",
} :: { [string]: string }

-- Eingebaute Roblox-Texturen als Rueckfall fuer Partikel. Was hier fehlt, hat
-- keinen Bild-Rueckfall (der Aufrufer zeigt dann nur Farbe).
WorldFXConfig.TEXTURE_FALLBACK = {
	firefly         = "rbxasset://textures/particles/sparkles_main.dds",
	star_twinkle    = "rbxasset://textures/particles/sparkles_main.dds",
	splash_flipbook = "rbxasset://textures/particles/smoke_main.dds",
	honey_bubble    = "rbxasset://textures/particles/sparkles_main.dds",
} :: { [string]: string }

-- Ob die Textur ein Flipbook (2x2) ist. Nur dann setzt der Aufrufer das
-- Layout; mit dem Rueckfall-Bild bleibt es ein Einzelbild.
WorldFXConfig.FLIPBOOKS = {
	cloud_puff_flipbook = true,
	splash_flipbook     = true,
	bee_flipbook        = true,
	wasp_flipbook       = true,
} :: { [string]: boolean }

--------------------------------------------------------------------------------
-- QUALITAET
--------------------------------------------------------------------------------
-- Ab welcher Stufe eine Funktion laeuft. Stufe 0 = niedrig (schwaches Handy,
-- Grafikstufe unter AmbienceConfig.HIGH_QUALITY_FROM), Stufe 1 = hoch.
-- Grundstimmung (Tageslauf, Licht, Wasser-Glitzern) laeuft immer; Beiwerk
-- faellt auf niedriger Stufe weg. Diese Tabelle ist zugleich die Liste fuer
-- den Bericht (Paket J).
WorldFXConfig.MIN_QUALITY = {
	dayCycle      = 0,   -- A: Uhrzeit, Licht, Atmosphaere, Bloom, Farbe
	lampGlow      = 0,   -- A: Laternen/Tropfen leuchten in der blauen Stunde
	fireflies     = 1,   -- A: Gluehwuermchen ueber dem Wasser
	stars         = 1,   -- A: funkelnde Sterne in der blauen Stunde
	cloudWisps    = 1,   -- A: weiche Wolkenschleier mit rosa Rand
	waterGlitter  = 0,   -- B: Glitzer-Textur auf dem Wasser
	waterWaves    = 1,   -- B: zweites Wellenmuster
	foamTexture   = 0,   -- B: Schaum-Textur auf den Saeumen
	arenaCoast    = 0,   -- B: Schaum + Pfosten an Arena-Insel und aeusserem Steg
	fish          = 1,   -- B: springender Honig-Fisch
	buoys         = 0,   -- B: Bonbon-Bojen (niedrig: halb so viele)
	mastCrown     = 0,   -- C: Wabenkrone am Honigmast
	honeyThread   = 1,   -- C: Honigfaden, Tropfen, Ringe in der Schale
	arrival       = 0,   -- C: Ankunft (Blasen + Bienen), einmal pro Server
	signposts     = 0,   -- C: Wegweiser
	pitFrame      = 0,   -- C: Wimpelkette und Lichter am Event-Pit
	pitFlutter    = 1,   -- C: Wimpel flattern (niedrig: haengen still)
	stallDecor    = 0,   -- C: Laterne und Eierkorb am Haendler
	waspSwarm     = 1,   -- C: kreisende Wespen am Nest
	waspPulse     = 0,   -- C: Nest pulsiert vor/waehrend des Boss
	boardFrames   = 0,   -- C: Holzrahmen + Krone an den Tafeln
	boardShine    = 1,   -- C: Glanzstreifen auf Platz 1
	islandDecor   = 0,   -- D: Insel-Stufen (Blumen, Pilze, Bienenhaus, Bernstein)
	pondShine     = 1,   -- D: Glanz auf dem Honig, Tropfen ueber den Rand
	homeGlow      = 0,   -- D: warmer Schimmer ueber der eigenen Insel
	freeIsland    = 0,   -- D: Schild "Frei", Blumen, Schmetterling auf leeren Inseln
	bridgeLamps   = 0,   -- E: Laternen am Steg zur Arena (Welle beim Lauf)
	arenaArch     = 0,   -- E: Torbogen an der Arena
	spectators    = 1,   -- E: Zuschauer-Baerchis auf dem Zaun
	showcaseFlag  = 0,   -- E: Flagge auf dem Schau-Turm (weht nur ab Stufe 1)
	bees          = 1,   -- F: Bienenschwaerme
	butterflies   = 1,   -- F: Schmetterlinge
	flowerSway    = 1,   -- F: Blumen nicken im Wind, weichen dem Spieler aus
	pollenTint    = 0,   -- F: Pollenfarbe folgt dem Tageslauf
	footprints    = 1,   -- F: Pfotenabdruecke im Sand
}

--------------------------------------------------------------------------------
-- PAKET A: TAGESLAUF
--------------------------------------------------------------------------------
-- Die Uhr pendelt weich (Kosinus) zwischen CLOCK_MIN und CLOCK_MAX und wieder
-- zurueck, ein voller Hin- und Rueckweg dauert PERIOD Sekunden. Gerechnet aus
-- workspace:GetServerTimeNow(): alle Spieler eines Servers sehen dieselbe
-- Tageszeit, und es gibt nie einen Sprung (Kosinus ist ueberall glatt).
WorldFXConfig.DAY = {
	PERIOD      = 20 * 60,
	CLOCK_MIN   = 14.5,    -- goldener Nachmittag
	CLOCK_MAX   = 19.0,    -- blaue Stunde (nie richtige Nacht)
	TICK        = 0.2,     -- so oft wird Lighting nachgefuehrt (Sekunden)
	RETURN_SECONDS = 2.0,  -- weicher Rueckweg nach einer Faehigkeiten-Show
}

-- Kurven ueber "Daemmerung" d = 0 (14,5 Uhr) .. 1 (19 Uhr). Jede Kurve ist
-- eine Liste {d, Wert}, aufsteigend; dazwischen wird weich (smoothstep)
-- interpoliert. Bei d = 0.5333 (= 16,9 Uhr, der bisherige feste Himmel)
-- stehen genau die alten Werte aus AmbienceConfig/MapConfig — der Test
-- day_cycle.test.lua prueft das, damit der bekannte Look Teil des Zyklus bleibt.
local BASE = 2.4 / 4.5   -- 16,9 Uhr

WorldFXConfig.DAY_BASE_D = BASE

WorldFXConfig.DAY_CURVES = {
	-- Lighting
	brightness = { { 0, 2.6 }, { BASE, 2.4 }, { 0.8, 2.1 }, { 1, 1.7 } },
	ambient = {
		{ 0, Color3.fromRGB(126, 122, 146) }, { BASE, Color3.fromRGB(120, 118, 150) },
		{ 1, Color3.fromRGB(112, 116, 168) },
	},
	-- Aussenlicht bleibt in der blauen Stunde HELL (nur blauer): Eier, Waben
	-- und Prompts muessen so gut lesbar sein wie am Nachmittag.
	outdoorAmbient = {
		{ 0, Color3.fromRGB(158, 156, 176) }, { BASE, Color3.fromRGB(150, 150, 185) },
		{ 0.8, Color3.fromRGB(162, 146, 182) }, { 1, Color3.fromRGB(150, 160, 214) },
	},
	colorShiftTop = {
		{ 0, Color3.fromRGB(255, 236, 205) }, { BASE, Color3.fromRGB(255, 225, 190) },
		{ 0.8, Color3.fromRGB(255, 188, 160) }, { 1, Color3.fromRGB(196, 204, 255) },
	},
	exposure = { { 0, 0 }, { BASE, 0 }, { 0.8, 0.1 }, { 1, 0.3 } },

	-- Atmosphaere: Horizont gold → korallenrosa → tiefblau
	atmDensity = { { 0, 0.27 }, { BASE, 0.30 }, { 1, 0.34 } },
	atmOffset  = { { 0, 0.22 }, { BASE, 0.25 }, { 1, 0.30 } },
	atmColor = {
		{ 0, Color3.fromRGB(255, 214, 196) }, { BASE, Color3.fromRGB(255, 200, 200) },
		{ 0.8, Color3.fromRGB(255, 168, 170) }, { 1, Color3.fromRGB(150, 160, 232) },
	},
	atmDecay = {
		{ 0, Color3.fromRGB(255, 168, 130) }, { BASE, Color3.fromRGB(255, 140, 120) },
		{ 0.8, Color3.fromRGB(255, 108, 118) }, { 1, Color3.fromRGB(92, 92, 172) },
	},
	atmGlare = { { 0, 0.4 }, { BASE, 0.5 }, { 0.8, 0.9 }, { 1, 0.2 } },
	atmHaze  = { { 0, 1.4 }, { BASE, 1.6 }, { 0.8, 2.0 }, { 1, 1.8 } },

	-- Post-Processing (die Basis-Effekte aus WorldBuilder.buildGlobalLighting)
	bloomIntensity = { { 0, 0.5 }, { BASE, 0.55 }, { 1, 0.85 } },
	bloomThreshold = { { 0, 1.5 }, { BASE, 1.4 }, { 1, 1.05 } },
	bloomSize      = { { 0, 20 }, { BASE, 20 }, { 1, 24 } },
	ccSaturation   = { { 0, 0.15 }, { BASE, 0.15 }, { 0.8, 0.2 }, { 1, 0.1 } },
	ccContrast     = { { 0, 0.05 }, { BASE, 0.05 }, { 1, 0.08 } },
	ccTint = {
		{ 0, Color3.fromRGB(255, 252, 244) }, { BASE, Color3.fromRGB(255, 255, 255) },
		{ 0.8, Color3.fromRGB(255, 242, 236) }, { 1, Color3.fromRGB(238, 242, 255) },
	},

	-- Wolken (Client-Puffs und Terrain-Wolken): rosa Raender im Abendrot
	cloudColor = {
		{ 0, Color3.fromRGB(255, 240, 236) }, { BASE, Color3.fromRGB(255, 232, 236) },
		{ 0.8, Color3.fromRGB(255, 196, 208) }, { 1, Color3.fromRGB(176, 176, 222) },
	},
	terrainCloudColor = {
		{ 0, Color3.fromRGB(255, 240, 238) }, { BASE, Color3.fromRGB(255, 235, 235) },
		{ 0.8, Color3.fromRGB(255, 200, 206) }, { 1, Color3.fromRGB(170, 172, 220) },
	},

	-- 0..1: wie stark Laternen, Mastkrone und Honigtropfen leuchten
	glow = { { 0, 0 }, { BASE, 0.15 }, { 0.75, 0.5 }, { 1, 1 } },
	-- 0..1: Gluehwuermchen und Sterne
	fireflies = { { 0, 0 }, { 0.7, 0 }, { 0.88, 0.6 }, { 1, 1 } },
	stars     = { { 0, 0 }, { 0.75, 0 }, { 1, 1 } },

	-- Pollen (Paket F): goldgelb am Tag, warm-rosa im Abendrot, kuehl-hell in der blauen Stunde
	pollenColor = {
		{ 0, Color3.fromRGB(255, 230, 140) }, { BASE, Color3.fromRGB(255, 226, 140) },
		{ 0.8, Color3.fromRGB(255, 200, 170) }, { 1, Color3.fromRGB(220, 230, 255) },
	},

	-- Wasser (Paket B): Glitzern wird in der blauen Stunde schwaecher, blaeulicher
	glitter = { { 0, 1 }, { BASE, 1 }, { 0.8, 0.8 }, { 1, 0.45 } },
	glitterTint = {
		{ 0, Color3.fromRGB(255, 250, 230) }, { BASE, Color3.fromRGB(255, 246, 226) },
		{ 0.8, Color3.fromRGB(255, 226, 204) }, { 1, Color3.fromRGB(196, 214, 255) },
	},
}

-- Laternen-Leuchten: Farbe bei glow = 0 und glow = 1. Neon leuchtet immer
-- etwas; dunkleres Bernstein am Tag heisst "an, aber ruhig".
WorldFXConfig.LAMP_DAY   = Color3.fromRGB(226, 168, 84)
WorldFXConfig.LAMP_NIGHT = Color3.fromRGB(255, 220, 130)
-- Diese Namen unter workspace.Platform.Scenery werden nachgefuehrt.
WorldFXConfig.LAMP_NAMES = { LampGlow = true, BridgeCap = true }

-- Gluehwuermchen: ein Emitter, wandert mit der Kamera auf offenes Wasser
WorldFXConfig.FIREFLY_RATE     = 6
WorldFXConfig.FIREFLY_COLOR    = Color3.fromRGB(255, 240, 160)
WorldFXConfig.FIREFLY_AHEAD    = 55      -- Studs vor der Kamera
WorldFXConfig.FIREFLY_BOX      = Vector3.new(90, 5, 90)

-- Sterne: ein Emitter auf einer grossen Schale hoch ueber der Welt
WorldFXConfig.STAR_RATE        = 3
WorldFXConfig.STAR_HEIGHT      = 520
WorldFXConfig.STAR_BOX         = Vector3.new(1600, 80, 1600)

-- Wolkenschleier: ein Emitter auf dem Wolkenring, weiche Puffs
WorldFXConfig.WISP_RATE        = 0.5
WorldFXConfig.WISP_HEIGHT      = 190
WorldFXConfig.WISP_BOX         = Vector3.new(2000, 120, 2000)

--------------------------------------------------------------------------------
-- PAKET B: WASSER UND KUESTE
--------------------------------------------------------------------------------
WorldFXConfig.WATER = {
	GLITTER_TILE         = 48,      -- Studs pro Kachel
	GLITTER_SPEED        = Vector2.new(0.9, 0.35),   -- Studs/s
	GLITTER_TRANSPARENCY = 0.35,    -- bei glitter = 1
	WAVES_TILE           = 90,
	WAVES_SPEED          = Vector2.new(-0.45, 0.8),
	WAVES_TRANSPARENCY   = 0.8,     -- sehr schwach
	TICK                 = 1 / 30,  -- Takt fuer Textur-Versatz
	FOAM_TILE            = 10,      -- Studs pro Kachel der Schaum-Spitze
	FOAM_DRIFT           = 0.25,    -- Studs/s, kaum merklich
	-- Ohne Glitzer-Textur: kein Ersatzbild (eine Standardtextur auf 1300
	-- Studs Wasser saehe nach Fehler aus) — dann bleibt das Wasser wie heute.
}

-- Schaum: Cremeweiss statt reinem Weiss (Leitbild)
WorldFXConfig.FOAM_COLOR = Color3.fromRGB(255, 249, 236)

-- Arena-Insel und aeusserer Steg (nur Client, pro besetztem Slot)
WorldFXConfig.ARENA_COAST = {
	POST_HEIGHT   = 4.6,
	POST_DIAMETER = 1.3,
	CAP_SIZE      = 1.9,
	INSET         = 3,
	SHOW_DISTANCE = 420,    -- weiter weg: aus
}

-- Honig-Fisch: einer gleichzeitig, in Sichtweite, zufaellige Pausen
WorldFXConfig.FISH = {
	PAUSE_MIN   = 20,
	PAUSE_MAX   = 60,
	JUMP_TIME   = 1.3,
	JUMP_HEIGHT = 5,
	JUMP_LENGTH = 9,
	DIST_MIN    = 35,      -- Abstand zur Kamera
	DIST_MAX    = 110,
	WATER_MARGIN = 6,      -- Abstand zu Inseln/Stegen
	COLOR       = Color3.fromRGB(255, 186, 52),
	FIN_COLOR   = Color3.fromRGB(240, 140, 40),
	RING_TIME   = 1.6,
	RING_SIZE   = 7,
}

-- Bonbon-Bojen weit draussen zwischen den Inseln (Winkel = Luecken zwischen
-- zwei Stegen, 22,5 + k x 45 Grad)
WorldFXConfig.BUOYS = {
	RADIUS       = 560,
	SIZE         = 5,
	BODY_COLOR   = Color3.fromRGB(255, 250, 244),
	STRIPE_COLOR = Color3.fromRGB(246, 136, 168),
	ROCK_DEGREES = 9,
	ROCK_RATE    = 0.32,   -- Schwingungen pro Sekunde
	BOB_HEIGHT   = 0.5,
}

--------------------------------------------------------------------------------
-- PAKET C: HAUPTINSEL
--------------------------------------------------------------------------------
-- Honigmast: alle Hoehen relativ zum Mast-Fuss (Oberkante Event-Pit-Podest).
WorldFXConfig.MAST = {
	CROWN_HEIGHT    = 29.6,   -- Mitte der Wabenkrone (= Mitte des Tropfens)
	CROWN_RADIUS    = 4.1,
	CROWN_CELLS     = 8,      -- je Reihe, zwei Reihen versetzt
	CROWN_ROW_GAP   = 2.3,
	CELL_SIZE       = 2.5,
	CELL_DEPTH      = 1.0,
	CELL_DAY        = Color3.fromRGB(196, 112, 26),
	CELL_NIGHT      = Color3.fromRGB(255, 196, 80),
	THREAD_ANGLE    = 198,    -- Grad: zwischen den Querhoelzern (180/225)
	THREAD_TOP      = 26.6,
	THREAD_BOTTOM   = 8.0,    -- dort sitzt die Tuelle
	THREAD_RADIUS   = 1.05,   -- Abstand zur Mastachse (Mast-Radius 0,9)
	THREAD_WIDTH    = 0.22,
	SPOUT_REACH     = 4.9,    -- Tuelle reicht bis hierher (ueber die Schale)
	BOWL_RADIUS     = 1.8,
	BOWL_HEIGHT     = 0.9,
	HONEY_COLOR     = Color3.fromRGB(245, 170, 40),
	BOWL_COLOR      = Color3.fromRGB(150, 100, 58),
	DROP_INTERVAL   = 3.2,    -- Sekunden zwischen zwei Tropfen
	DROP_GROW       = 1.2,    -- so lange waechst der Tropfen an der Tuelle
	DROP_SIZE       = 0.55,
	RING_TIME       = 1.1,
	SHOW_DISTANCE   = 260,    -- Faden/Tropfen; die Krone sieht man immer
}

-- Ankunft (einmal pro Server-Beitritt, nur fuer den Spieler selbst)
WorldFXConfig.ARRIVAL = {
	BUBBLES     = 14,
	BEES        = 6,
	CIRCLE_TIME = 2.6,     -- so lange kreisen die Bienen um den Spieler
	CIRCLE_RADIUS = 5,
	FLY_TIME    = 3.2,     -- dann fliegen sie zum Ziel
	BEE_COLOR   = Color3.fromRGB(255, 206, 40),
	STRIPE_COLOR = Color3.fromRGB(46, 34, 20),
}

-- Wegweiser: an jedem Steg, wo der Pflasterweg am Event-Pit beginnt
WorldFXConfig.SIGNPOST = {
	RADIUS       = 60,     -- Abstand zur Weltmitte
	SIDE         = 8.2,    -- seitlich vom Weg (Pflaster ist 10 breit, Schild 5,2 lang)
	POST_HEIGHT  = 7.5,
	BOARD_SIZE   = Vector3.new(5.2, 1.5, 0.3),
	BOARD_GAP    = 1.9,
	WOOD         = Color3.fromRGB(176, 122, 72),
	WOOD_DARK    = Color3.fromRGB(120, 80, 44),
	TEXT_COLOR   = Color3.fromRGB(70, 44, 24),
	HOME_COLOR   = Color3.fromRGB(255, 214, 110),   -- Schild "Deine Insel"
	SHOW_DISTANCE = 160,
}

-- Event-Pit-Rahmen: Wimpelkette zwischen Masten in den Zaunfeldern
WorldFXConfig.PIT_FRAME = {
	POLE_HEIGHT    = 10,
	POLE_RADIUS    = 52.5,   -- knapp ausserhalb des Podests (50) + Ring
	PENNANTS       = 5,      -- je Feld zwischen zwei Masten
	LIGHTS         = 4,      -- je Feld
	SAG            = 1.6,    -- Durchhang der Kette
	PENNANT_SIZE   = Vector3.new(1.4, 1.6, 0.12),
	PENNANT_COLORS = { Color3.fromRGB(246, 150, 176), Color3.fromRGB(255, 214, 110), Color3.fromRGB(255, 246, 236) },
	POLE_COLOR     = Color3.fromRGB(150, 105, 60),
	LANTERN_OFF    = Color3.fromRGB(120, 92, 60),
	LANTERN_ON     = Color3.fromRGB(255, 206, 110),
	LIGHT_OFF      = Color3.fromRGB(170, 150, 120),
	SOON_SECONDS   = 60,     -- "Event startet bald": letzte Minute der Pause
	FLUTTER_CALM   = 6,      -- Grad
	FLUTTER_SOON   = 20,
	FLUTTER_RATE   = 0.8,    -- Schwingungen pro Sekunde
	PULSE_RATE     = 0.5,    -- Lichterkette beim Event (Hz, weit unter 3)
	SHOW_DISTANCE  = 320,
}

-- Haendler-Deko: Laterne und Eierkorb, nur in der Naehe sichtbar
WorldFXConfig.STALL = {
	SHOW_DISTANCE = 55,
	LANTERN_COLOR = Color3.fromRGB(255, 206, 110),
	BASKET_COLOR  = Color3.fromRGB(176, 128, 72),
	EGG_COLORS    = { Color3.fromRGB(255, 246, 228), Color3.fromRGB(255, 214, 120), Color3.fromRGB(248, 186, 206) },
}

-- Wespen-Nest: kreisende Wespen, Puls vor und waehrend des Boss
WorldFXConfig.WASP_NEST = {
	WASPS_CALM    = 3,
	WASPS_BOSS    = 7,
	ORBIT_RADIUS  = 4.5,
	ORBIT_SPEED   = 0.35,   -- Umdrehungen pro Sekunde (jede Wespe etwas anders)
	WASP_COLOR    = Color3.fromRGB(196, 132, 32),
	STRIPE_COLOR  = Color3.fromRGB(26, 20, 14),
	PULSE_COLOR   = Color3.fromRGB(196, 92, 20),
	PULSE_RATE    = 0.6,    -- Hz
	SHOW_DISTANCE = 220,
}

-- Tafeln: Holzrahmen mit Honig-Ecken, kleine Krone, Glanz auf Platz 1
WorldFXConfig.BOARD_FRAME = {
	BEAM          = 0.6,
	WOOD          = Color3.fromRGB(130, 88, 50),
	CORNER_COLOR  = Color3.fromRGB(245, 175, 45),
	CORNER_SIZE   = 1.3,
	CROWN_COLOR   = Color3.fromRGB(255, 205, 70),
	SHINE_PERIOD  = 3.2,    -- Sekunden fuer einmal Durchwandern
	SHOW_DISTANCE = 200,
}

--------------------------------------------------------------------------------
-- PAKET D: PLOT-INSELN MIT PERSOENLICHKEIT
--------------------------------------------------------------------------------
-- Stufe der Insel-Deko (Modules/IslandStage): es zaehlt, was weiter ist —
-- geschaffte Tower ODER Rebirths. Index = Stufe (2..4).
WorldFXConfig.ISLAND_STAGE = {
	TOWERS_FOR   = { [2] = 1, [3] = 2, [4] = 3 },   -- I / II / III geschafft
	REBIRTHS_FOR = { [2] = 1, [3] = 3, [4] = 5 },   -- passend zu den Rebirth-Deckeln
	RIM_RADIUS   = 53.5,     -- Abstand zur Inselmitte (Beet-Ecke 50,9, Inselrand 58)
	SHOW_DISTANCE = 260,
}

-- Was ab welcher Stufe am Inselrand steht. `angle` in Grad, plot-lokal:
-- 0 = Richtung Arena-Steg, 90 = zum naechsten Slot, 180 = zur Hauptinsel.
-- Die Steg-Achsen (0 und 180, je +-25 Grad) bleiben frei (Test: map_layout).
WorldFXConfig.ISLAND_STAGE_ITEMS = {
	{ stage = 2, kind = "Flowers",   angle =  40 },
	{ stage = 2, kind = "Flowers",   angle = 145 },
	{ stage = 2, kind = "Flowers",   angle = 215 },
	{ stage = 2, kind = "Flowers",   angle = 320 },
	{ stage = 2, kind = "Flowers",   angle =  75 },
	{ stage = 2, kind = "Flowers",   angle = 285 },
	{ stage = 3, kind = "Flowers",   angle = 110 },
	{ stage = 3, kind = "Flowers",   angle = 250 },
	{ stage = 3, kind = "Mushrooms", angle =  58 },
	{ stage = 3, kind = "Mushrooms", angle = 302 },
	{ stage = 3, kind = "Mushrooms", angle = 128 },
	{ stage = 4, kind = "Beehive",   angle =  92 },
	{ stage = 4, kind = "AmberStone", angle = 268 },
}

-- Deklarative Deko je Art, Ursprung = Boden am Platz, -Z zeigt zur Inselmitte.
-- Eine Zeile je Teil (tools/check_decor.py liest genau diese Form: nichts im
-- Boden, nichts schwebt). Blumen als GRUPPE (Blattkranz + drei Koepfe).
local UPRIGHT = Vector3.new(0, 0, 90)
local PINK     = Color3.fromRGB(246, 150, 176)
local BUTTER   = Color3.fromRGB(255, 222, 110)
local LAVENDER = Color3.fromRGB(190, 160, 236)
WorldFXConfig.FLOWER_COLORS = { PINK, BUTTER, LAVENDER }

WorldFXConfig.ISLAND_KINDS = {
	Flowers = {
		{ name = "Leaves", shape = Enum.PartType.Cylinder, size = Vector3.new(0.30, 2.8, 2.8), offset = Vector3.new( 0.0, 0.15,  0.0), color = Color3.fromRGB(86, 168, 74), rotation = UPRIGHT },
		{ name = "HeadA",  shape = Enum.PartType.Ball,     size = Vector3.new(0.90, 0.9, 0.9), offset = Vector3.new( 0.6, 0.75,  0.2), color = PINK },
		{ name = "HeadB",  shape = Enum.PartType.Ball,     size = Vector3.new(0.85, 0.85, 0.85), offset = Vector3.new(-0.5, 0.70,  0.4), color = BUTTER },
		{ name = "HeadC",  shape = Enum.PartType.Ball,     size = Vector3.new(0.80, 0.8, 0.8), offset = Vector3.new( 0.0, 0.70, -0.6), color = LAVENDER },
	},
	Mushrooms = {
		{ name = "Stem",   shape = Enum.PartType.Cylinder, size = Vector3.new(1.40, 0.7, 0.7), offset = Vector3.new( 0.0, 0.70,  0.0), color = Color3.fromRGB(250, 240, 220), rotation = UPRIGHT },
		{ name = "Cap",    shape = Enum.PartType.Ball,     size = Vector3.new(1.80, 1.8, 1.8), offset = Vector3.new( 0.0, 1.50,  0.0), color = Color3.fromRGB(226, 76, 76) },
		{ name = "DotA",   shape = Enum.PartType.Ball,     size = Vector3.new(0.35, 0.35, 0.35), offset = Vector3.new( 0.45, 2.20,  0.2), color = Color3.fromRGB(255, 250, 240) },
		{ name = "DotB",   shape = Enum.PartType.Ball,     size = Vector3.new(0.30, 0.30, 0.30), offset = Vector3.new(-0.35, 2.25, -0.3), color = Color3.fromRGB(255, 250, 240) },
		{ name = "Stem2",  shape = Enum.PartType.Cylinder, size = Vector3.new(0.90, 0.5, 0.5), offset = Vector3.new( 1.1, 0.45,  0.5), color = Color3.fromRGB(250, 240, 220), rotation = UPRIGHT },
		{ name = "Cap2",   shape = Enum.PartType.Ball,     size = Vector3.new(1.10, 1.1, 1.1), offset = Vector3.new( 1.1, 0.95,  0.5), color = Color3.fromRGB(226, 76, 76) },
	},
	Beehive = {
		{ name = "Stand",  shape = Enum.PartType.Block,    size = Vector3.new(2.6, 0.6, 2.6), offset = Vector3.new( 0.0, 0.30,  0.0), color = Color3.fromRGB(120, 80, 44) },
		{ name = "Box",    shape = Enum.PartType.Block,    size = Vector3.new(2.2, 2.4, 2.2), offset = Vector3.new( 0.0, 1.80,  0.0), color = Color3.fromRGB(196, 146, 86) },
		{ name = "Band",   shape = Enum.PartType.Block,    size = Vector3.new(2.3, 0.3, 2.3), offset = Vector3.new( 0.0, 2.10,  0.0), color = Color3.fromRGB(245, 175, 45) },
		{ name = "Roof",   shape = Enum.PartType.Block,    size = Vector3.new(2.9, 0.4, 2.9), offset = Vector3.new( 0.0, 3.20,  0.0), color = Color3.fromRGB(150, 98, 58) },
		{ name = "Hole",   shape = Enum.PartType.Ball,     size = Vector3.new(0.6, 0.6, 0.6), offset = Vector3.new( 0.0, 1.40, -1.05), color = Color3.fromRGB(46, 30, 20) },
	},
	AmberStone = {
		{ name = "Rock",   shape = Enum.PartType.Cylinder, size = Vector3.new(0.8, 2.6, 2.6), offset = Vector3.new( 0.0, 0.40,  0.0), color = Color3.fromRGB(140, 132, 120), rotation = UPRIGHT },
		{ name = "Stone",  shape = Enum.PartType.Ball,     size = Vector3.new(1.8, 1.8, 1.8), offset = Vector3.new( 0.0, 1.60,  0.0), color = Color3.fromRGB(255, 176, 50) },
	},
}
-- Einzige leuchtende Insel-Deko (Leitbild): der Bernstein-Stein.
WorldFXConfig.ISLAND_GLOW_PIECE = "Stone"
-- Obergrenze je Insel fuer Stufe 4 (Client-Teile, check_decor prueft sie)
WorldFXConfig.ISLAND_DECOR_BUDGET = 60

-- Honig-Brunnen: Glanz auf der Oberflaeche, bei vollem Teich Tropfen ueber den Rand
WorldFXConfig.POND_LIFE = {
	SHINE_PERIOD   = 7,       -- Sekunden fuer eine Runde des Glanzflecks
	SHINE_SIZE     = Vector3.new(0.05, 1.6, 0.8),
	FULL_RATIO     = 0.97,    -- ab hier gilt der Teich als voll
	OVERFLOW_DROPS = 4,
	DROP_INTERVAL  = 1.6,
	DROP_SIZE      = 0.45,
	SHOW_DISTANCE  = 120,
}

-- Eigene Insel (nur der Besitzer sieht es)
WorldFXConfig.HOME_GLOW = {
	COLOR        = Color3.fromRGB(255, 214, 120),
	RING_TRANSPARENCY = 0.82,  -- duenner warmer Ring auf dem Sandsaum
	MOTE_RATE    = 5,          -- warme Lichtpunkte ueber der Insel
	MOTE_HEIGHT  = 14,
}

-- Leere Insel: Schild "Frei", ein paar Blumen, ein Schmetterling
WorldFXConfig.FREE_ISLAND = {
	SIGN_HEIGHT  = 4,
	FLOWER_ANGLES = { 150, 205, 240 },
	SHOW_DISTANCE = 220,
}

--------------------------------------------------------------------------------
-- PAKET E: STEGE UND ARENA
--------------------------------------------------------------------------------
WorldFXConfig.BRIDGE_LAMPS = {
	PER_SIDE     = 5,
	POST_HEIGHT  = 3.4,
	GLASS_SIZE   = 0.9,
	OFF_COLOR    = Color3.fromRGB(150, 116, 70),
	ON_COLOR     = Color3.fromRGB(255, 210, 110),
	WAVE_STEP    = 0.16,     -- Sekunden zwischen zwei Laternen der Welle
	SHOW_DISTANCE = 300,
}

WorldFXConfig.ARENA_ARCH = {
	HALF_WIDTH   = 7.6,      -- Steg 12 breit + Gelaender: Pfosten ausserhalb
	HEIGHT       = 9,
	POST_DIAMETER = 1.1,
	COMB_SIZE    = 3.2,
	WOOD         = Color3.fromRGB(150, 105, 60),
}

WorldFXConfig.SPECTATORS = {
	COUNT        = 6,
	COLORS       = { Color3.fromRGB(226, 70, 70), Color3.fromRGB(80, 190, 90), Color3.fromRGB(255, 210, 60), Color3.fromRGB(80, 140, 230) },
	SCALE        = 1.0,
	HOP_HEIGHT   = 1.2,
	HOP_TIME     = 0.45,
	CHEER_TIME   = 2.4,
	SHOW_DISTANCE = 160,
}

WorldFXConfig.SHOWCASE_FLAG = {
	POLE_HEIGHT  = 4,
	FLAG_SIZE    = Vector3.new(2.6, 1.6, 0.1),
	WAVE_DEGREES = 14,
	WAVE_RATE    = 0.9,
	SHINE_TIME   = 1.2,
	SHOW_DISTANCE = 260,
}

--------------------------------------------------------------------------------
-- PAKET F: LEBEN IN DER LUFT UND IM GRAS
--------------------------------------------------------------------------------
WorldFXConfig.BEES = {
	MAX_SWARMS   = 6,        -- gleichzeitig in Sichtweite
	PER_SWARM    = { 3, 5 },
	SITE_RADIUS  = 6,
	SPEED        = 0.22,     -- Umlaeufe pro Sekunde
	HOME_EXTRA   = 2,        -- zusaetzliche Schwaerme auf der eigenen Insel
	VIEW_DISTANCE = 180,
	COLOR        = Color3.fromRGB(255, 206, 40),
	STRIPE_COLOR = Color3.fromRGB(46, 34, 20),
}

WorldFXConfig.BUTTERFLIES = {
	COUNT        = 6,
	COLORS       = { Color3.fromRGB(246, 150, 186), Color3.fromRGB(190, 160, 236) },
	FLAP_RATE    = 3.2,      -- Fluegelschlaege pro Sekunde (Bewegung, kein Flackern)
	WANDER       = 7,
	HEIGHT       = 2.5,
	VIEW_DISTANCE = 140,
}

WorldFXConfig.FLOWER_SWAY = {
	DEGREES      = 7,
	RATE         = 0.35,     -- Hz der Windwelle
	WAVELENGTH   = 60,       -- Studs: die Welle laeuft ueber die Insel
	DODGE_RADIUS = 3.5,
	DODGE_DEGREES = 28,
	VIEW_DISTANCE = 140,
	TICK         = 1 / 15,
}

WorldFXConfig.FOOTPRINTS = {
	MAX          = 20,
	STEP         = 2.2,      -- Studs zwischen zwei Abdruecken
	FADE         = 4,        -- Sekunden bis unsichtbar
	SIZE         = 0.9,
	COLOR        = Color3.fromRGB(196, 168, 112),   -- etwas dunkler als der Sand
}

-- Klaenge: nur IDs, die in Studio geprueft sind. Leer = kein Klang (die
-- Sound-Pakete H und der Wespen-Summton warten auf eine geprufte ID).
WorldFXConfig.SOUNDS = {
	waspHum = "",
} :: { [string]: string }
WorldFXConfig.SOUND_VOLUME = { waspHum = 0.08 }   -- immer unter Kampf (0,12/0,35)

--------------------------------------------------------------------------------
-- PAKET 0: FESTE KAMERAPUNKTE ("worldshots")
--------------------------------------------------------------------------------
-- Gerechnet in WorldShotController aus MapConfig, damit sie mit der Welt
-- mitwandern. Hier nur die Parameter je Punkt (Slot 1 = Plot bei 0 Grad).
WorldFXConfig.WORLD_SHOTS = {
	{ name = "1 Spawn → Honigmast",       fov = 70 },
	{ name = "2 Hauptinsel schraeg oben", fov = 60 },
	{ name = "3 Plot-Insel, Brunnen",     fov = 70 },
	{ name = "4 Steg zur Arena",          fov = 70 },
	{ name = "5 Arena mit Turm",          fov = 65 },
	{ name = "6 Rand → Horizont",         fov = 70 },
}

return WorldFXConfig
