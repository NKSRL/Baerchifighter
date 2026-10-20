--!strict
-- EpilogConfig.luau
-- ReplicatedStorage/Config/EpilogConfig.luau
--
-- Einzige Zustaendigkeit:
--   - Konstanten des Final-Epilogs (Stage 100 im Final-Tower, Welt-2-Freischaltung):
--     Zustandsnamen, Remote-Namen, Zeitleiste, Token-Fenster.
--
-- Eigenes Modul, weil MapConfig bei 192 von max. 200 lokalen Namen steht.
-- Prompt 2-6 ergaenzen hier ihre Masse (Gipfel, Insel, Bruecke, Terminal,
-- Kamera). Hier nur: was Prompt 1 (Siegeslogik/Datenmodell) braucht.
--
-- Wichtig: In diesem Modul stehen KEINE Balance-Zahlen.

local EpilogConfig = {}

-- Schalter in FeatureFlags (aus = Verhalten wie vor dem Epilog).
EpilogConfig.FLAG = "FINAL_EPILOG"

-- Welcher Sieg den Epilog ausloest: Tower-Id. Die Stage-Zahl kommt aus
-- TowerConfig (def.stages = 100), steht bewusst NICHT doppelt hier.
EpilogConfig.TOWER_ID = "Final"

-- Zustaende von data.epilog.state. none -> pending -> seen -> launched.
EpilogConfig.STATE = {
	NONE     = "none",
	PENDING  = "pending",   -- Final 100 geschafft, Knopf noch nicht erreicht
	SEEN     = "seen",      -- Spieler stand auf der Insel (Terminal erreicht)
	LAUNCHED = "launched",  -- Knopf gedrueckt, Welt 2 frei (endgueltig)
}

-- Welt-Id fuer data.worlds.unlocked.
EpilogConfig.WORLD2_ID = "World2"

-- Remote-Namen (Vertrag aller 7 Prompts, siehe Network/Remotes).
EpilogConfig.REMOTES = {
	START         = "EpilogStart",          -- S->C  Token + Parameter
	SEEN          = "EpilogSeen",           -- C->S  Token
	SKIP          = "EpilogSkip",           -- C->S  Token
	PRESS_LAUNCH  = "RequestPressLaunch",   -- C->S  Token
	LAUNCH_RESULT = "EpilogLaunchResult",   -- S->C
	WORLD2        = "World2Unlocked",       -- S->C
}

-- Art des Starts (Parameter von EpilogStart).
EpilogConfig.MODE = {
	FULL    = "full",      -- erster Sieg: komplette Kamerafahrt
	RESTORE = "restore",   -- Wiedereinstieg ohne Kamerafahrt (pending -> Gipfel, seen -> Insel)
}

-- Zeitleiste in Sekunden (Vertrag der Prompts 2-6, nur zur Referenz).
EpilogConfig.TIMELINE = {
	VICTORY_END   = 2,
	TELEPORT_END  = 5,
	REVEAL_END    = 12,
	BRIDGE_END    = 24,
	ARRIVAL_END   = 34,   -- ab hier hat der Spieler die Kontrolle
	FINALE        = 9,
	RETURN_WALK   = 6,
}

-- Prompt 2: der Gipfel auf der obersten Etage des Final-Run-Turms. Masse in
-- Studs, Winkel in Grad. Etagenradius (PIT_TOWER_RADIUS) und Etagenzahl
-- (TowerConfig.getRunFloor) kommen NICHT von hier. Die Farbe der Kristall-
-- saeulen kommt aus dem Look des Final-Towers (TowerConfig -> MapConfig.TOWER_LOOKS),
-- der Rest ist Honig-Gold, Bernstein und Creme.
EpilogConfig.SUMMIT = {
	-- Reichweite ueber den Etagenradius hinaus (Brueckenansatz).
	extraRing = 6,
	-- Richtung zur Insel in Grad relativ zu "vom Map-Mittelpunkt nach aussen"
	-- (0 = genau nach aussen, dort ist freier Himmel). Prompt 3 baut Insel und
	-- Bruecke in diese Richtung.
	bridgeOutwardDeg = 0,

	-- Aufbau (Sekunden): 0-0,2 halten, 0,2-1,2 aufwerten, 1,2-1,5 bereitstellen.
	holdSeconds  = 0.2,
	decorSeconds = 1.0,
	readySeconds = 0.3,
	-- Finale: die Abfahrt dauert PIT_TOWER_FALL_SECONDS x diesen Faktor.
	lowerFactor  = 3,

	-- Boden: Randring (Neon, ragt rimWidth ueber die Etage), Platte, Waben-Zellen.
	rimWidth       = 0.6,
	rimThickness   = 0.2,
	plateThickness = 0.3,
	cellCount      = 7,      -- 1 Mitte + 6 drumherum
	cellRadius     = 5.6,
	cellSpacing    = 11.6,
	cellThickness  = 0.12,

	-- Kristallsaeulen am Rand (ohne Kollision).
	crystalCount = 4,
	crystalInset = 1.8,      -- Abstand vom Rand nach innen
	crystalSize  = { 1.7, 7, 1.7 },

	-- Brueckenansatz: flache Platten auf der Inselseite.
	bridgePlates     = 3,
	bridgePlateLen   = 2.3,
	bridgeWidth      = 8.4,
	bridgeThickness  = 0.5,
	bridgeStartInset = 1.0,  -- beginnt so weit innerhalb des Randes

	-- Unsichtbares Gelaender: regelmaessiges n-Eck ausserhalb des Randrings; an
	-- der Bruecke bleibt eine Luecke (Enden der zwei Nachbarwaende gekuerzt).
	railSides   = 6,
	railHeight  = 8,
	railThick   = 1,
	railGap     = 0.1,       -- Abstand zwischen Randring und Gelaender
	railOpenEnd = 4.6,       -- so viel wird an der Bruecke von jeder Nachbarwand abgeschnitten

	-- Fangboden: faellt jemand trotzdem, landet er nach catchDepth auf einer
	-- unsichtbaren Scheibe und wird zum Gipfel zurueckgeholt.
	catchDepth    = 6,
	catchExtra    = 14,
	catchCooldown = 1.0,

	-- Spawn und Kamera-Anker (Prompt 5 liest die Attachments am Teil "Rig").
	spawnLift     = 3.4,     -- Mitte des Avatars ueber der Platte
	companionSide = 3.6,     -- Begleiter-Baerchi steht so weit neben dem Avatar
	camStart  = { front = 9,  height = 2.5 },   -- vor dem Avatar, schaut ihn an
	camOrbit  = { height = 7 },                 -- Drehpunkt ueber der Mitte
	camBridge = { out = 12,   height = 9 },     -- ueber der Bruecke, schaut nach aussen

	-- Teleport erst X Sekunden nach EpilogStart (Prompt 5: Flash-Hoehepunkt).
	teleportDelay = 0,

	colors = {
		rim     = Color3.fromRGB(255, 196,  60),   -- Honig-Gold (Neon)
		plate   = Color3.fromRGB(246, 232, 200),   -- Creme
		cell    = Color3.fromRGB(226, 160,  50),   -- Bernstein
		bridgeA = Color3.fromRGB(246, 232, 200),
		bridgeB = Color3.fromRGB(226, 160,  50),
	},
	-- Nachts (Lighting.ClockTime ausserhalb der Spanne) leuchtet das Licht staerker.
	dayFrom = 6, dayTo = 18,
	lightBrightnessDay = 1.2, lightBrightnessNight = 2.6, lightRange = 44,
}

-- Prompt 3: schwebende Insel und Bruecke. Masse in Studs, Zeiten in Sekunden.
-- ANNAHME: "70 Studs horizontal" ist der Abstand zwischen dem Ende des
-- Brueckenansatzes am Gipfel und dem Inselrand; dann ist die Bruecke ca. 70 lang
-- (wie verlangt). Die Inselmitte liegt dadurch ca. 114 Studs von der Gipfelmitte.
EpilogConfig.ISLAND = {
	edgeGap   = 70,      -- Luft zwischen Brueckenansatz und Inselrand (= Brueckenlaenge)
	rise      = 18,      -- Inseloberkante ueber der Oberkante der Gipfeletage
	diameter  = 24,      -- Durchmesser der Wiese

	-- Enthuellung: die Insel waechst in revealSeconds aus Nebel auf Vollgroesse
	-- (Groessen-Tween ueber Model:ScaleTo, kein Mesh-Tausch).
	revealSeconds = 3,
	revealStart   = 0.12,   -- Startgroesse (Anteil)
	revealSteps   = 15,

	-- Wiese, Fels darunter (drei verjuengte Scheiben), Kristalle, Buesche
	grassThickness = 1.2,
	rimWidth       = 0.7,    -- Inselrand (leuchtet golden bei Ankunft)
	rimThickness   = 0.25,
	rockLayers     = { { 0.82, 3.2 }, { 0.58, 3.4 }, { 0.32, 3.0 } },   -- {Anteil des Durchmessers, Hoehe}
	crystalCount   = 4,
	crystalSize    = { 1.4, 4.2, 1.4 },
	bushCount      = 3,
	bushSize       = 2.6,
	padRadius      = 5,      -- Podest fuer das Terminal (Prompt 4)
	padThickness   = 0.2,
	terminalBack   = 3.5,    -- Terminal steht so weit hinter der Inselmitte (von der Bruecke weg)

	-- Fangboden unter Insel und Bruecke: wer faellt, wird zurueckgeholt.
	catchDepth  = 10,
	catchExtra  = 18,
	catchCooldown = 1.0,

	-- Inselrand leuchtet, wenn der Avatar den Boden betritt.
	glowSeconds = 1.2,

	-- Rein visuelles Wippen der Deko (Kollision bleibt fest, nur Client).
	bobHeight = 0.6,
	bobPeriod = 4,

	colors = {
		grass   = Color3.fromRGB(120, 200,  90),    -- Gruen
		rock    = Color3.fromRGB(150, 130, 160),    -- warmes Violettgrau
		rimIdle = Color3.fromRGB(246, 232, 200),    -- Wolkenweiss
		rimGlow = Color3.fromRGB(255, 196,  60),    -- Honig-Gold
		crystal = Color3.fromRGB(255, 170, 230),    -- Endless-Rosa (255,170,230)
		bush    = Color3.fromRGB(90, 180,  80),
		pad     = Color3.fromRGB(246, 232, 200),
		cloud   = Color3.fromRGB(235, 245, 255),    -- Himmelblau-Weiss
	},
	lightColor = Color3.fromRGB(255, 214, 120), lightBrightness = 1.4, lightRange = 40,
}

EpilogConfig.BRIDGE = {
	planks        = 14,
	width         = 8.4,     -- >= 8 (Mobile)
	plankThick    = 0.7,
	plankOverlap  = 0.1,
	growInterval  = 0.3,     -- Abstand zwischen zwei Planken
	springSeconds = 0.28,    -- Aufsetz-Federn (Ease Back)
	springDrop    = 2.6,     -- Planke faellt von so weit oben
	sparkCount    = 7,       -- Funken pro Planke (Muster zufaellig)
	sparkLife     = 0.55,    -- Emitter-Lebensdauer: hoechstens 3 gleichzeitig
	startDelay    = 0,       -- zusaetzliche Wartezeit vor der ersten Planke
	-- true: EpilogService.beginFull laesst Insel und Bruecke selbst nacheinander
	-- entstehen (Standard bis Prompt 5). Prompt 5 stellt es auf false und ruft
	-- EpilogService.runBridgeSequence zum Kamera-Zeitpunkt (Aufstieg 5-12 s).
	autoStart     = true,
	retrySeconds  = 10,      -- so lange wartet runBridgeSequence auf Spieler/Gipfel

	-- Gelaender (entsteht mit der letzten Planke) und Lichtimpuls
	railHeight  = 8,         -- wie das Gipfel-Gelaender: hoeher als jeder Sprung
	railAlpha   = 0.7,       -- Glas-Gelaender (entsteht erst mit der letzten Planke)
	railThick   = 0.5,
	railStubStart = 1.8,     -- Gelaender beginnt so weit hinter dem Randring des Gipfels
	railInset   = 0.2,       -- Abstand zum Plankenrand nach aussen
	railFade    = 0.5,
	pulseSeconds = 1.2,
	pulseSize    = { 1.2, 0.25, 5 },

	-- Abbau in umgekehrter Reihenfolge
	removeSeconds = 3,

	-- Nur auf der Bruecke / Insel: Teile, die der Server hoechstens anlegt.
	maxIslandParts = 18,
	maxBridgeParts = 20,
	maxEmitters    = 3,

	colors = {
		plankA = Color3.fromRGB(246, 232, 200),   -- Creme
		plankB = Color3.fromRGB(226, 160,  50),   -- Bernstein
		rail   = Color3.fromRGB(135, 206, 250),   -- Himmelblau
		pulse  = Color3.fromRGB(255, 196,  60),   -- Honig-Gold (Neon)
		spark  = Color3.fromRGB(255, 205,  80),
	},
}

-- Hochgeladene Blender-Assets (Praefix Epilog_). Leer = Platzhalter aus
-- Primitiven. Die Datei Epilog_Wolke.png (256x256, Alpha) wuerde hier als
-- Partikeltextur eingetragen; bis dahin dient die Standardtextur nur als Platzhalter.
EpilogConfig.ASSETS = {
	-- Mesh-Vorlagen (Modelle in ReplicatedStorage.Assets, Studio-Import der FBX aus
	-- assets/epilog/). Fehlt eine Vorlage, bauen die Builder die Primitive (EpilogMeshes).
	islandTemplate   = "EpilogIsland",     -- Epilog_Insel.fbx     (Blender erstellt, Studio-Import offen)
	plankTemplate    = "EpilogPlank",      -- Epilog_Plank.fbx     (Blender erstellt, Studio-Import offen)
	terminalTemplate = "EpilogTerminal",   -- Epilog_Terminal.fbx  (Blender erstellt, Studio-Import offen)
	-- Hochgeladene Bild-Assets (rbxassetid://..., Bild-IDs, NICHT die Decal-IDs aus dem Creator Hub). Leer = Fallback.
	cloudTex       = "rbxassetid://88194991349907",   -- Epilog_Wolke.png            (256x256, Alpha) -> Partikeltextur
	terminalAlbedo = "rbxassetid://131095774075742",   -- Epilog_Terminal_Albedo.png  (512x512) -> TextureID von Sockel/Korpus/Konsole
	-- Prompt 5 (Bildschirmrand-Effekte, UI-Schicht). Leer = Frame-Ersatz aus Primitiven/Gradienten.
	sparkTex     = "rbxassetid://103024913797898",   -- Epilog_Funke.png      128x128, Alpha, vierzackiger Stern mit Glow
	confettiTex  = "rbxassetid://74729177669682",   -- Epilog_Konfetti.png   256x64, 4 Varianten a 64x64
	speedLineTex = "rbxassetid://88362945149920",   -- Epilog_SpeedLine.png  512x64, weicher Streifen
	lensFlareTex = "rbxassetid://133099540158493",   -- Epilog_LensFlare.png  512x512
	-- Vignette: bewusst kein Bild (vier UI-Verlaeufe am Rand genuegen, siehe EpilogOverlay).
	particleFallback = "rbxasset://textures/particles/sparkles_main.dds",
}

-- Prompt 4: Start-Terminal mit grossem rotem Knopf auf der Insel. Masse in
-- Studs, Winkel in Grad, Zeiten in Sekunden. Lokales Koordinatensystem des
-- Terminals = Mount von EpilogIslandBuilder.getTerminalMount: Ursprung Mitte
-- Sockelunterseite, +Y oben, Vorderseite -Z (Blick Richtung Bruecke).
EpilogConfig.TERMINAL = {
	-- Zustaende (Attribut EpilogTerminalState am Modell `Terminal`)
	STATE = { IDLE = "idle", READY = "ready", ARMED = "armed", FIRED = "fired", DONE = "done" },
	ATTRIBUTE = "EpilogTerminalState",
	COUNTDOWN_ATTRIBUTE = "EpilogCountdown",   -- Prompt 6: 3, 2, 1 (0 = aus) waehrend des Finales
	TAG = "EpilogTerminal",

	width        = 5,       -- Breite des Blocks
	tiltDeg      = 18,      -- Neigung der Konsole (Vorderkante tiefer)
	buttonDiam   = 2.2,     -- Knopf
	buttonHeight = 0.55,
	baseDiam     = 2.6,     -- Knopfgehaeuse
	baseHeight   = 0.5,
	ringDiam     = 2.8,     -- glaenzender Goldring
	lidSize      = { 2.7, 0.12, 2.8 },
	lidGap       = 0.7,     -- Klappe schwebt so hoch ueber dem Gehaeuse (geschlossen)
	lampCount    = 3,
	lampDiam     = 0.42,
	maxParts     = 22,
	maxEmitters  = 2,

	-- Annaeherung (Server prueft 2x pro Sekunde, kein Frame-Loop)
	nearDistance = 12,
	farDistance  = 14,      -- Hysterese: erst weiter weg faellt es auf idle zurueck
	checkSeconds = 0.5,

	-- ProximityPrompt
	prompt = { distance = 8, hold = 1.2, hitArea = 8 },   -- hitArea: Kantenlaenge der Touch-Flaeche (8x8 = 64)

	-- Bewegung (Client)
	lidReadyDeg = 25,  lidOpenDeg = 105,
	lidReadySeconds = 0.5, lidOpenSeconds = 0.45, lidCloseSeconds = 0.5,
	pressDepth = 0.25, pressSeconds = 0.12, releaseSeconds = 0.35,
	pulseSeconds = 1.2, pulseAmount = 0.15,
	lampStepSeconds = 0.2, blinkSeconds = 1.0, blinkJitter = 0.1,
	fireFlashSeconds = 0.6,

	-- Debug: Pause zwischen armed und fired bei `epilog terminal fired`
	debugArmedSeconds = 0.8,

	colors = {
		concrete = Color3.fromRGB(138, 140, 146),   -- Beton / Mittelgrau
		metal    = Color3.fromRGB( 86,  89,  96),   -- dunkles Metall
		screen   = Color3.fromRGB( 28,  32,  38),
		red      = Color3.fromRGB(226,  44,  44),   -- Signalrot (Knopf)
		lid      = Color3.fromRGB(255,  90,  90),   -- transparente rote Klappe
		yellow   = Color3.fromRGB(255, 205,  40),   -- Warngelb (nur Streifen, Lampe gelb)
		black    = Color3.fromRGB( 30,  30,  32),
		gold     = Color3.fromRGB(255, 196,  60),   -- Honig-Gold an den Kanten
		green    = Color3.fromRGB( 70, 220, 110),
		lampOff  = Color3.fromRGB( 70,  50,  50),
		cable    = Color3.fromRGB( 40,  40,  44),
	},
	-- Licht: roter Glow-Kegel nach oben; nachts deutlicher
	dayFrom = 6, dayTo = 18,
	lightBrightnessDay = 1.6, lightBrightnessNight = 3.4, lightRange = 22, lightAngle = 60,
}

-- Token (Anti-Exploit). Annahme: EpilogSeen kommt fruehestens, wenn der
-- Lauf ueber die Bruecke vorbei sein kann (ARRIVAL ~24 s); 20 s Mindestzeit
-- laesst Netz-Schwankungen Luft und blockiert trotzdem einen Sofort-Spam.
EpilogConfig.SEEN_MIN_SECONDS = 20
EpilogConfig.SEEN_MAX_SECONDS = 900   -- danach ist das Token fuer EpilogSeen abgelaufen

-- Verzoegerte Endless-Meldung (TowerUnlocked): hoechstens so lange zurueckhalten,
-- falls niemand sie freigibt (z. B. Client ohne Epilog-Anzeige). Dann geht sie
-- trotzdem raus. Prompt 5/6 rufen EpilogService.releaseDeferred frueher auf.
EpilogConfig.DEFER_MAX_SECONDS = 600

-- Mindestabstand zwischen zwei Start-Entscheidungen pro Spieler (Race-Schutz).
EpilogConfig.START_DEBOUNCE_SECONDS = 5

-- Prompt 5: Kamerafahrt und Bildschirmrand-Effekte. Alle Zeiten in Sekunden der
-- Sequenz (0 = EpilogStart), Winkel in Grad, Masse in Studs. Rein visuell: nichts
-- davon ruehrt Balance oder Spielstand an.
EpilogConfig.SEQUENCE = {
	enabled = true,        -- false: alter Ablauf (Teleport + Bruecke sofort, ohne Kamerafahrt)
	-- Zeitplan (Vertrag: 0-2 Sieg, 2-5 Flash+Teleport, 5-12 Aufstieg, 12-24 Lauf, 24-34 Ankunft)
	teleportAt = 2.25,     -- Flash-Hoehepunkt (0,25 s Flash ab 2,0): hier steht der Avatar neu
	bridgeAt   = 5,        -- Insel waechst, danach die Bruecke (runBridgeSequence)
	walkAt     = 12,       -- Avatar laeuft los
	arriveAt   = 24,       -- Avatar steht vor dem Terminal
	endAt      = 34,       -- Spielerkontrolle zurueck, EpilogSeen
	-- Skip: beim ersten Mal nicht vor Sekunde 12, danach Halten (1 s). Springt zur Ankunft.
	skipFromSeconds = 12,
	skipHoldSeconds = 1.0,
	skipTolerance   = 0.75,   -- Netz-Luft fuer die Server-Pruefung
	blendBackSeconds    = 1.2,   -- Kamera blendet zur Standardansicht
	restoreFlashSeconds = 1.2,   -- Wiederaufnahme ohne Fahrt: nur Einblend-Flash
	companionAhead = 3,          -- Begleiter-Baerchi laeuft so weit voraus
	arriveRadius   = 10,         -- Wachhund: weiter weg als das vom Ziel -> Server setzt den Avatar um
	-- Lauftempo: {von, bis, Faktor} in Sekunden seit walkAt (muss genau arriveAt-walkAt abdecken).
	-- Der Mittelwert wird auf die Wegstrecke normiert; die Tempo-Wechsel loesen die Speed-Lines aus.
	walkFactors = { { 0, 1.5, 0.7 }, { 1.5, 4, 1.1 }, { 4, 6, 1.25 }, { 6, 8.5, 0.9 }, { 8.5, 10.5, 1.2 }, { 10.5, 12, 0.7 } },
	walkMinSpeed = 4,
	walkMaxSpeed = 32,
	-- Debug-Zeitraffer (epilog speed N)
	minSpeed = 0.5,
	maxSpeed = 5,
	-- Zweiter Beat vor dem Reveal: 0,4 s Stille (Musik gedaempft) vor jedem Wow-Moment
	silenceSeconds = 0.4,
}

-- Zeitlupe als Kamerazeit-Abbildung {reale Zeit, Kamerazeit}: stueckweise linear, monoton,
-- trifft bei 2 s und 12 s wieder genau die reale Zeit. 0-0,15 s Hit-Freeze (Kamera steht),
-- 0,15-0,95 s mit 0,4x, danach Aufholen; 7,6-9,6 s mit 0,5x (Insel gleitet ins Bild).
EpilogConfig.TIME_WARP = {
	{ 0, 0 }, { 0.15, 0 }, { 0.95, 0.32 }, { 2.0, 2.0 },
	{ 7.6, 7.6 }, { 9.6, 8.6 }, { 12, 12 },
}

-- Kamera: Segmente je Phase. Positionen als Abstand/Hoehe zu festen Bezugspunkten
-- (Cam_Start/Cam_Orbit/Cam_Bridge des Gipfels = Gipfelmitte + Bruecken-Richtung; Avatar;
-- Insel; Terminal). Kameraweg fest, nichts Zufaelliges.
EpilogConfig.CAMERA = {
	-- Phase 1: ruckartiger Zoom auf FOV 55, kurzes Heranruecken an den Avatar
	jerkFov = 55, jerkAt = 0.15, jerkSeconds = 0.25, pushFraction = 0.25, headHeight = 1.6,
	-- Phase 2: nach dem Schnitt (teleportAt) vor dem Avatar, schaut ihn an, leichtes Heranfahren
	-- (Hoehen relativ zur Avatar-Mitte; Cam_Start des Gipfels liegt ca. 3,4 Studs darunter ueber der Platte)
	start = { front0 = 9, front1 = 6.5, height0 = -0.9, height1 = -1.8, fov0 = 62, fov1 = 70, lookUp = 0.6 },
	-- Phase 3: Spirale aus Bodennaehe nach oben, dann Schwenk zur Insel (Kamerazeit)
	spiral = { radius0 = 6.5, radius1 = 9.5, height0 = -1.8, height1 = 15, turns = 1.5,
		fov0 = 70, fovPeak = 85, fovPeakAt = 10, fov1 = 78, panFrom = 8.0, panTo = 10.5, islandLookUp = 3,
		followBlend = 2.0 },   -- Blickziel gleitet ab Sekunde 12 von der Insel zum Weg voraus
	-- Phase 4: relativ zum Avatar auf dem Weg: hinter ihm (back), seitlich (side), ueber der
	-- Wurzel (up), Blickziel `ahead` Studs voraus. Bis zum naechsten Eintrag weich ueberblendet.
	follow = {
		{ t = 12.0, back = 9.5, side = 0,  up = 15,   ahead = 6,  look = 1.5, fov = 78 },
		{ t = 14.0, back = 8.0, side = 0,  up = 4.2,  ahead = 8,  look = 2.0, fov = 72 },
		{ t = 16.0, back = 7.5, side = 1.5, up = 3.4, ahead = 9,  look = 2.0, fov = 72 },
		{ t = 17.2, back = 3.0, side = 11, up = 3.0,  ahead = 2,  look = 1.5, fov = 68 },   -- Schiene seitlich
		{ t = 19.5, back = -3.0, side = 11, up = 2.4, ahead = 0,  look = 1.0, fov = 66 },
		{ t = 20.3, back = 2.0, side = 7,  up = -2.3, ahead = 4,  look = 0.8, fov = 76 },   -- Low-Angle ueber der Planke
		{ t = 21.8, back = -1.0, side = 7, up = -2.3, ahead = 5,  look = 1.0, fov = 76 },
		{ t = 22.8, back = 8.0, side = 0,  up = 4.5,  ahead = 8,  look = 2.0, fov = 72 },
		{ t = 24.0, back = 9.0, side = 0,  up = 5.0,  ahead = 10, look = 2.0, fov = 70 },
	},
	-- Phase 5: langsam um die Insel (Bruecke zu), dann Dolly-Zoom auf das Terminal
	orbit = { from = 24, to = 30, radius0 = 17, radius1 = 15, height0 = 9, height1 = 7,
		sweepDeg = 120, lookUp = 2, crossFade = 1.2 },
	dolly = { from = 30, to = 34, distance0 = 9, fov0 = 70, fov1 = 38, height = 3.2, targetUp = 2.4, crossFade = 1.0 },
}

-- Bildschirmrand-Effekte (UI-Schicht) und Licht. "reduced" halbiert die Teilchen, kein
-- Dolly-Zoom, keine Letterbox.
EpilogConfig.FX = {
	maxSprites = 60,               -- harte Obergrenze aller UI-Teilchen zusammen
	pools = { sparks = 12, veil = 16, speed = 8, burst = 14, cloud = 6 },   -- Summe 56
	reducedFactor = 0.5,
	-- Vollbild-Flash 0,25 s: Hoehepunkt genau bei SEQUENCE.teleportAt (dort wird teleportiert)
	flash = { color = Color3.fromRGB(255, 244, 214), upSeconds = 0.12, downSeconds = 0.13, at = 2.13 },
	skipFlashSeconds = 0.35,
	colors = {
		gold    = Color3.fromRGB(255, 196,  60),
		white   = Color3.fromRGB(255, 255, 255),
		sky     = Color3.fromRGB(150, 205, 255),
		pink    = Color3.fromRGB(255, 130, 200),
		magenta = Color3.fromRGB(226,  70, 170),
		red     = Color3.fromRGB(226,  44,  44),   -- Terminal-Knopf
	},
	-- Fenster {von, bis} fuer einzelne Effekte (Sequenzzeit)
	speedLines = { { 12.2, 13.8 }, { 16.4, 17.6 }, { 19.6, 20.6 }, { 22.0, 23.0 } },
	clouds     = { 2.25, 5.0 },       -- Wolkenfetzen-Overlay
	sparks     = { 2.0, 34.0 },       -- goldene Eckfunken
	veil       = { { 5.0, 12.0 }, { 30.0, 34.0 } },   -- aufsteigende Konfetti-Schleier links/rechts
	lensFlare  = { 8.4, 10.6 },       -- Insel-Reveal, oberer Rand
	letterbox  = { 5.0, 34.0, 0.6 },  -- von, bis, Einblenden (nur "full")
	vignetteGold = { 0.0, 2.0 },      -- goldene Vignette pulsiert im Sieg-Beat
	vignetteDark = { 28.0, 34.0 },    -- Rand dunkelt ab, Knopf pulsiert in der Mitte
	confettiBurstAt = 0.4,            -- Konfetti-Burst vom unteren Rand
	momentAt = 1.0,                   -- "TOWER GESCHAFFT!" (Moment)
	-- Licht (Kurven {Sekunde, Wert}, stueckweise linear; nachts hebt der Glow um nightBoost an)
	bloom      = { { 0, 0 }, { 0.3, 0.6 }, { 8, 1.2 }, { 34, 1.0 }, { 35.2, 0 } },
	sunRays    = { { 0, 0 }, { 4, 0 }, { 8.5, 0.28 }, { 34, 0.22 }, { 35.2, 0 } },
	grade      = { { 0, 0 }, { 1, 1 }, { 34, 1 }, { 35.2, 0 } },   -- Faktor fuer Saettigung/Kontrast
	saturation = 0.15, contrast = 0.1,
	nightBoost = 1.2,
	dayFrom = 6, dayTo = 18,
}

-- Platzhalter-Cues (Audio, Prompt 7 fuellt sie): Namen in Config/SoundConfig, leer = stumm.
EpilogConfig.CUES = {
	hit = "epilog_hit", flash = "epilog_flash", rise = "epilog_rise", run = "epilog_run", reveal = "epilog_reveal",
	press = "epilog_press", countdown = "epilog_countdown", launch = "epilog_launch", unlock = "epilog_unlock",   -- Prompt 6
	ready = "epilog_ready", terminal_idle = "epilog_terminal_idle",   -- Prompt 7: Terminal bereit / Summen
}
-- Prompt 7: Schritt-Takt auf der Bruecke (Sekunden) und wie spaet ein Cue noch hoerbar sein darf
-- (nach Skip/Sprung bleiben veraltete Cues stumm).
EpilogConfig.STEP_INTERVAL = 0.28
EpilogConfig.CUE_LATE_SECONDS = 0.5
-- Zeitpunkte der Cues (Sekunde der Sequenz)
EpilogConfig.CUE_TIMES = {
	{ 0.0, "hit" }, { 2.0, "flash" }, { 5.0, "rise" }, { 12.0, "run" }, { 8.8, "reveal" },
}

-- Prompt 6: Knopf-Finale, Welt-2-Freischaltung, Rueckweg. Zeiten in Sekunden seit dem
-- gueltigen Knopfdruck (f = 0). Rein visuell; gespeichert wird nur "launched" + Welt 2.
EpilogConfig.FINALE = {
	enabled = true,
	-- Anti-Exploit (Server)
	pressMaxDistance = 14,       -- Abstand Avatar-Terminal
	pressCooldownSeconds = 1,    -- Rate-Limit pro Spieler
	-- Zeitplan
	countTimes = { 1.2, 2.5, 3.8 },   -- 3 ... 2 ... 1 (Terminal + Bildschirmrand)
	silenceAt  = 4.7,                 -- 0,3 s Stille vor dem Start
	launchAt   = 5.0,                 -- Rakete steigt, Flash, Shockwave
	launchEnd  = 7.5,
	celebrateAt = 7.5,                -- Banner, Himmel, Portal
	returnAt   = 9.0,                 -- Ende des Finales, Rueckweg beginnt
	skipFromSeconds = 5,              -- Finale erst ab hier skippbar (springt zu returnAt)
	skipTolerance   = 0.75,
	minSpeed = 0.5, maxSpeed = 5,     -- Debug-Zeitraffer wie SEQUENCE
	-- Rueckweg: Flash, Avatar+Begleiter werden auf den Gipfel gesetzt ("Zurueck"), die
	-- Bruecke baut sich ab (BRIDGE.removeSeconds), danach faehrt der Turm ab.
	returnFlashSeconds = 0.35,
	returnTeleportAt   = 9.2,
	lowerSeconds       = 3,
	hintSeconds        = 4,           -- "Welt 2: Weg folgt bald"
	plotMaxDistance    = 60,          -- weiter weg vom Plot-Spawn: am Ende dorthin setzen
	-- Kamera-Schuetteln (Humanoid.CameraOffset): Amplitude in Studs, sinusfoermig
	shake = { from = 0.3, to = 0.8, hz = 7 },
	-- Salven (Funken/Konfetti) beim Start
	salvos = 3, salvoGap = 0.4,
	confettiMax = 150, emittersMax = 4,
	-- Licht
	bloomPeak = 1.5, bloomRest = 0.8, bloomSeconds = 2,
	skyTint = Color3.fromRGB(226, 150, 255),     -- Welt-2-Platzhalter: Violett-Rosa
	skyTintSeconds = 1.5, skyHoldSeconds = 1.5,
	-- Rakete (ein Mesh/Part-Gruppe, 2 Emitter, ohne Kollision)
	rocket = {
		height = 7, radius = 1.3, rise = 150, sideOffset = 7.5, alongOffset = 1.5,
		parts = 8,
		bodyColor = Color3.fromRGB(246, 240, 232), noseColor = Color3.fromRGB(226, 44, 44),
		finColor = Color3.fromRGB(226, 44, 44), windowColor = Color3.fromRGB(150, 205, 255),
		shaftColor = Color3.fromRGB(40, 40, 46),
	},
	shockwave = { seconds = 1.6, startSize = 4, endSize = 120, height = 0.6 },
	portal = { distance = 320, height = 70, size = 150, seconds = 3 },
}
EpilogConfig.ASSETS.rocketTemplate = "EpilogRakete"   -- Vorlage ReplicatedStorage.Assets.EpilogRakete (fehlt sie: Primitive)
EpilogConfig.ASSETS.shockwaveTex = "rbxassetid://86935325388588"     -- Epilog_Shockwave.png (rbxassetid, leer = Ring aus Teilen)
EpilogConfig.ASSETS.portalTex = "rbxassetid://90183387502766"        -- Epilog_Portal.png (leer = Frame-Silhouette)

return EpilogConfig
