--!strict
-- HatchFxConfig.luau
-- ReplicatedStorage/Config/HatchFxConfig.luau
--
-- Einzige Zustaendigkeit (R6, Ei-Schluepf-Animation):
--   - ALLE Zahlen, Zeiten, Stufen und Bild-IDs der Inszenierung (VFX/EggHatch).
--     Im Code stehen keine Dauer-, Shake- oder Partikelwerte.
--
-- Die Stufen haengen am Rarity-Index (BaerchiConfig.getRarityIndex: Common = 1 ...
-- Omega = 12). Zeiten sind Sekunden bei normalem Tempo; "Schnelles Oeffnen"
-- rechnet sie mit FAST_FACTOR herunter, die Effekte bleiben gleich.
-- Rarity-FARBEN kommen nicht von hier, sondern aus BaerchiConfig.RARITY_COLORS.

local HatchFxConfig = {}

--------------------------------------------------------------------------------
-- Bilder (selbst gezeichnet, Weiss auf Transparent; ImageColor3 faerbt sie ein)
--------------------------------------------------------------------------------
HatchFxConfig.ASSETS = {
	crack1   = "rbxassetid://72252695871764",
	crack2   = "rbxassetid://116267489007915",
	crack3   = "rbxassetid://136786987068474",
	ring     = "rbxassetid://85716858848562",
	rays     = "rbxassetid://99178417979054",
	glint    = "rbxassetid://117306862519879",
	paw      = "rbxassetid://97744058425813",
	drop     = "rbxassetid://116257181040446",
	shine    = "rbxassetid://92491696224104",
	vignette = "rbxassetid://114336731782111",
	shards   = "rbxassetid://87910733982758",   -- Atlas 510x340, 3x2 Zellen je 170 px
}
HatchFxConfig.SHARD_CELL  = 170
HatchFxConfig.SHARD_CELLS = { Vector2.new(0, 0), Vector2.new(170, 0), Vector2.new(340, 0), Vector2.new(0, 170), Vector2.new(170, 170), Vector2.new(340, 170) }

--------------------------------------------------------------------------------
-- Farben der Szene (Honig-Palette; die Rarity-Farbe kommt zusaetzlich)
--------------------------------------------------------------------------------
HatchFxConfig.COLORS = {
	honey  = Color3.fromRGB(255, 196, 40),
	cream  = Color3.fromRGB(255, 244, 214),
	choco  = Color3.fromRGB(70, 40, 20),
	white  = Color3.fromRGB(255, 255, 255),
}

--------------------------------------------------------------------------------
-- Allgemein
--------------------------------------------------------------------------------
HatchFxConfig.GENERAL = {
	skipAfter        = 1.0,    -- ab dieser Sekunde springt ein Tipp zur Enthuellung
	revealTapDelay   = 0.6,    -- so lange nach dem Reveal schliesst ein Tipp noch nicht
	resultTimeout    = 5.0,    -- ohne Server-Antwort Abbruch (HatchAnimation)
	revealAutoClose  = 12.0,   -- Sicherheitsnetz, falls niemand tippt
	fastFactor       = 0.4,    -- "Schnelles Oeffnen": Zeiten x 0,4
	mobileParticles  = 0.5,    -- Partikelfaktor auf Touch-Geraeten
	eggFraction      = 0.40,   -- Ei-Ansicht = Anteil der kuerzeren Bildschirmseite
	petFraction      = 0.46,   -- Baerchi-Ansicht, ebenso
	fovBase          = 30,
	fovPunch         = 2.5,    -- Grad, die die Kamera bei einem Schlag anzieht
	pendulumDegrees  = 18,     -- Baerchi pendelt um die Vorderansicht
	pendulumSpeed    = 1.1,    -- Radiant pro Sekunde
	slowMoScale      = 0.3,
	slowMoSeconds    = 0.55,
	hitStopSeconds   = 0.06,   -- wird je Stufe ueberschrieben
	batchStaggerSeconds = 0.08,
	dimAlpha         = 0.72,   -- Abdunkelung des Spiels hinter der Szene (Deckkraft)
}

--------------------------------------------------------------------------------
-- Intensitaetsstufen. Wird die Rarity nicht gefunden, gilt die erste Stufe.
-- maxIndex = hoechster Rarity-Index dieser Stufe (aufsteigend sortiert).
--------------------------------------------------------------------------------
export type Tier = {
	name         : string,
	maxIndex     : number,
	appear       : number,   -- Erscheinen
	hitInterval  : number,   -- Abstand der drei Wackelschlaege
	burst        : number,   -- Aufbruch bis Reveal
	revealIn     : number,   -- Bärchi steigt auf
	shake        : number,   -- Bildschirmzittern in Pixeln (0 = keins)
	particles    : number,
	rays         : number,   -- Anzahl Strahlen-Ebenen
	hitStop      : number,
	slowMo       : boolean,
	secondPulse  : boolean,
	confetti     : number,
	sound        : string,   -- "low" oder "high" (Varianten in SoundConfig)
}

HatchFxConfig.TIERS = {
	{ name = "low",  maxIndex = 3,  appear = 0.5, hitInterval = 0.50, burst = 0.30, revealIn = 0.9, shake = 0,  particles = 14, rays = 1, hitStop = 0.04, slowMo = false, secondPulse = false, confetti = 10, sound = "low" },
	{ name = "mid",  maxIndex = 6,  appear = 0.5, hitInterval = 0.55, burst = 0.35, revealIn = 1.0, shake = 7,  particles = 26, rays = 2, hitStop = 0.06, slowMo = false, secondPulse = false, confetti = 22, sound = "low" },
	{ name = "high", maxIndex = 9,  appear = 0.6, hitInterval = 0.65, burst = 0.40, revealIn = 1.2, shake = 12, particles = 40, rays = 3, hitStop = 0.08, slowMo = true,  secondPulse = false, confetti = 36, sound = "high" },
	{ name = "max",  maxIndex = 99, appear = 0.7, hitInterval = 0.80, burst = 0.50, revealIn = 1.5, shake = 18, particles = 56, rays = 4, hitStop = 0.10, slowMo = true,  secondPulse = true,  confetti = 52, sound = "high" },
} :: { Tier }

function HatchFxConfig.tierFor(rarityIndex: number): Tier
	for _, tier in HatchFxConfig.TIERS do
		if rarityIndex <= tier.maxIndex then return tier end
	end
	return HatchFxConfig.TIERS[#HatchFxConfig.TIERS]
end

--------------------------------------------------------------------------------
-- Kino-Szene (Video, z. B. fuer Omega). Leere videoId = aus, dann laeuft die normale
-- Animation. Das Video (Roblox-Video-Asset, Creator Hub) laeuft als Vollbild statt
-- Ei/Aufbruch und geht in den normalen Reveal ueber (Weiss-Blitz).
--------------------------------------------------------------------------------
HatchFxConfig.CINEMATIC = {
	videoId     = "",     -- "rbxassetid://<id>" des hochgeladenen Videos (omega.mp4)
	fromIndex   = 12,     -- ab diesem Rarity-Index (12 = Omega)
	revealAt    = 9.2,    -- Sekunde im Video, an der in den Reveal geblendet wird
	loadTimeout = 4,      -- so lange auf das Laden warten, sonst normale Animation
	volume      = 0.8,    -- der Videoton ersetzt hier die Einzelklaenge
}

--------------------------------------------------------------------------------
-- Klang-Namen (Eintraege in SoundConfig; leere ID = stumm, siehe dort)
--------------------------------------------------------------------------------
HatchFxConfig.SOUNDS = {
	appear = "hatchAppear",
	wobble = "hatchWobble",
	crack  = "hatchCrack",
	burst  = { low = "hatchBurst", high = "hatchBurstHigh" },
	reveal = { low = "hatchReveal", high = "hatchRevealHigh" },
}

return HatchFxConfig
