--!strict
-- SkillFXConfig.luau
-- ReplicatedStorage/Config/SkillFXConfig.luau
--
-- v14 (Mega Egg Tree, WP8/WP9): WIE jede Faehigkeit aussieht.
--
-- Was ein Skill TUT, steht in SkillConfig. Hier steht nur die Show — als
-- reine DATEN. Der Client (Controllers/SkillFXController) kennt eine Handvoll
-- Bausteine und spielt eine Faehigkeit ab, indem er ihre Schritte der Reihe
-- nach ausfuehrt. Eine neue Faehigkeit = ein neuer Eintrag hier, kein Code.
--
-- ============================================================
-- AUFBAU EINES EINTRAGS
-- ============================================================
--   tier      Spektakel-Stufe 1..4 (siehe TIERS): steuert, wie viel erlaubt
--             ist (Himmel faerben, Kamerafahrt) und wie lange die Show ist.
--   duration  Sekunden, die der PIT fuer die volle Show anhaelt.
--   color     Hauptfarbe, color2 Zweitfarbe.
--   sounds    { charge = id, strike = id, impact = id } (siehe SOUNDS).
--   steps     Liste { t = Startzeit, fx = Baustein, ...Parameter }.
--             Drei Phasen nach Konzept: Aufladen (t klein), Schlag (Mitte),
--             Einschlag (Ende). `at` sagt, wo: "self" (der Baerchi),
--             "target" (der Gegner), "between", "arena" (Mitte zwischen beiden).
--
-- BAUSTEINE (Client):
--   aura      Leuchtkugel + Licht um eine Figur        size, dur
--   ring      flacher Ring, der sich ausbreitet          radius, dur
--   pillar    Lichtsaeule                                 height, width, dur
--   projectile Kugel mit Schweif von self zu target       size, dur
--   meteor    Kugel faellt von oben auf target            size, height, dur
--   beam      Strahl zwischen self und target             width, dur
--   wave      Kugel-Schockwelle                           radius, dur
--   shards    Splitter fliegen auseinander                count, size, dur
--   sparks    Funken-Partikel                             count, dur
--   bubble    Schild-Blase um eine Figur                  size, dur
--   rise      aufsteigende Lichter (Heilung, Buff)        count, dur
--   spiral    Partikel werden eingesaugt (Vortex)         radius, count, dur
--   frost     Eiskristalle auf einer Figur                count, dur
--   starfield Sternenhimmel ueber der Arena               count, dur
--   sky       Farbfilter (nur Besitzer)                   tint, brightness, saturation, dur
--   spectrum  Farbspektrum laeuft durch (nur Besitzer)    dur
--   flash     weisser Bildschirmblitz (nur Besitzer)      dur
--   shake     Kamerawackeln (nur Besitzer)                power, dur
--   hitstop   Treffer-Stillstand ("Zeitlupe")            dur
--   cinematic kurze Kamerafahrt (nur Besitzer, Stufe 4)  dur
--   sound     ein Sound-Slot                              slot = "charge"|"strike"|"impact"
--
-- Jede Faehigkeit ist eine EIGENE Komposition (andere Bausteine, Reihenfolge,
-- Formen und Farben). Geprueft: tools/sim/egg_tree_check.lua meldet doppelte
-- Kompositionen.
--
-- ============================================================
-- KAMERA (offene Entscheidung 1 aus dem Konzept)
-- ============================================================
-- ANNAHME: Der Spieler behaelt seine Kamera. Nur auf Stufe 4 (Cosmic bis
-- Omega) gibt es eine KURZE Kamerafahrt (hoechstens 2,5 s), danach springt
-- die Kamera zurueck. Abschaltbar ueber CINEMATIC_CAMERA. Zuschauer (andere
-- Spieler) sehen nur die Effekte in der Welt, nie Kamera oder Farbfilter.

local CINEMATIC_CAMERA = true

-- Spektakel-Stufen. `echo` = wie lange die kurze Wiederholung dauert, wenn
-- der Skill im selben Lauf noch einmal kommt (die volle Show laeuft nur beim
-- ersten Einsatz eines Laufs — sonst wuerde ein Lauf mit 40 Stages Minuten
-- dauern).
local TIERS = {
	[1] = { name = "Sauber",     maxDuration = 1.5, sky = false, cinematic = false, echo = 0.35 },
	[2] = { name = "Gross",      maxDuration = 3.0, sky = false, cinematic = false, echo = 0.45 },
	[3] = { name = "Himmel",     maxDuration = 4.0, sky = true,  cinematic = false, echo = 0.55 },
	[4] = { name = "Kosmisch",   maxDuration = 6.0, sky = true,  cinematic = true,  echo = 0.65 },
}

-- Partikel-Budget: Faktor auf alle Stueckzahlen je Grafikstufe (1..10 in
-- Roblox). Auf Handys mit niedriger Stufe bleibt die Show erkennbar, aber
-- leichter. Unter MIN_COUNT faellt keine Zahl.
local PARTICLE_BUDGET = {
	low    = 0.35,  -- Grafikstufe 1..3
	medium = 0.65,  -- 4..6
	high   = 1.0,   -- 7..10
	MIN_COUNT = 2,
}

-- ============================================================
-- SOUNDS
-- ============================================================
-- Sound-Slots je Faehigkeit. Die Werte sind Asset-IDs (Zahl) oder ein
-- eingebauter Roblox-Sound ("rbxasset://..."). Fehlt ein Eintrag, bleibt
-- der Slot still — der Baukasten kennt die Slots trotzdem (Konzept: Platz-
-- halter erlaubt). Die Bibliothek unten ist in SOUND_LIBRARY benannt, die
-- Faehigkeiten verweisen nur auf Namen.
local SOUND_LIBRARY: { [string]: string } = {
	-- Eingebaute Roblox-Klaenge (immer vorhanden, kein Upload noetig).
	whoosh    = "rbxasset://sounds/unsheath.wav",
	hit       = "rbxasset://sounds/hit.wav",
	ping      = "rbxasset://sounds/electronicpingshort.wav",
	boom      = "rbxasset://sounds/collide.wav",
	glass     = "rbxasset://sounds/glassbreak.wav",
	splat     = "rbxasset://sounds/splat.wav",
	snap      = "rbxasset://sounds/snap.mp3",
	rocket    = "rbxasset://sounds/Rocket shot.wav",
	rumble    = "rbxasset://sounds/Rocket whoosh 01.wav",
	slash     = "rbxasset://sounds/swordslash.wav",
	lunge     = "rbxasset://sounds/swordlunge.wav",
	thunder   = "rbxasset://sounds/HalloweenThunder.wav",
	ghost     = "rbxasset://sounds/HalloweenGhost.wav",
	bass      = "rbxasset://sounds/bass.wav",
	flash     = "rbxasset://sounds/flashbulb.wav",
}
-- (Alle Eintraege in Studio mit ContentProvider:PreloadAsync geprueft:
-- laden. "swoosh.wav" gibt es nicht — deshalb unsheath.wav.)

-- v15: Lautstaerke. Die eingebauten Klaenge sind laut und hart (Donner,
-- Rakete, Glas) — in v14 klangen manche Shows aggressiv. Deshalb leiser,
-- jeder Ton wird nach MAX_SECONDS ausgeblendet (FADE_SECONDS lang), und ein
-- Echo (jeder weitere Einsatz im Lauf) ist noch einmal leiser.
-- Zuschauer hoeren deutlich leiser als der Besitzer, ROLLOFF_* sorgt dafuer,
-- dass ein Kampf auf der Nachbar-Insel kaum durchdringt.
local SOUND = {
	OWNER_VOLUME     = 0.35,
	SPECTATOR_VOLUME = 0.12,
	ECHO_FACTOR      = 0.6,
	MAX_SECONDS      = 1.6,
	FADE_SECONDS     = 0.4,
	ROLLOFF_MIN      = 10,
	ROLLOFF_MAX      = 90,
}

export type Step = { [string]: any }
export type SkillFX = {
	tier     : number,
	duration : number,
	color    : Color3,
	color2   : Color3,
	sounds   : { charge: string?, strike: string?, impact: string? },
	-- Tonhoehe je Slot, damit dieselbe Datei je Faehigkeit anders klingt.
	pitch    : number?,
	steps    : { Step },
}

local C = Color3.fromRGB

local FX: { [string]: SkillFX } = {

	----------------------------------------------------------------------------
	-- Welle 1: Common bis Rare — sauber und kurz (1 bis 1,5 s)
	----------------------------------------------------------------------------

	BasicPunch = {
		tier = 1, duration = 1.0, color = C(255, 236, 200), color2 = C(255, 180, 120),
		sounds = { strike = "lunge", impact = "hit" }, pitch = 1.1,
		steps = {
			{ t = 0.00, fx = "aura",  at = "self", size = 3, dur = 0.35 },
			{ t = 0.35, fx = "sound", slot = "strike" },
			{ t = 0.45, fx = "ring",  at = "target", radius = 4, dur = 0.35 },
			{ t = 0.45, fx = "sound", slot = "impact" },
			{ t = 0.50, fx = "sparks", at = "target", count = 10, dur = 0.4 },
		},
	},

	GummyShield = {
		tier = 1, duration = 1.2, color = C(110, 230, 120), color2 = C(200, 255, 200),
		sounds = { charge = "ping", strike = "splat" }, pitch = 0.9,
		steps = {
			{ t = 0.00, fx = "sound",  slot = "charge" },
			{ t = 0.00, fx = "rise",   at = "self", count = 8, dur = 0.5 },
			{ t = 0.40, fx = "bubble", at = "self", size = 6, dur = 0.8 },
			{ t = 0.45, fx = "sound",  slot = "strike" },
			{ t = 0.50, fx = "ring",   at = "self", radius = 5, dur = 0.4 },
		},
	},

	SugarRush = {
		tier = 1, duration = 1.2, color = C(255, 220, 60), color2 = C(255, 120, 200),
		sounds = { charge = "whoosh", strike = "ping" }, pitch = 1.4,
		steps = {
			{ t = 0.00, fx = "sound", slot = "charge" },
			{ t = 0.00, fx = "spiral", at = "self", radius = 4, count = 10, dur = 0.5, outward = true },
			{ t = 0.30, fx = "aura",   at = "self", size = 4, dur = 0.8 },
			{ t = 0.45, fx = "sound", slot = "strike" },
			{ t = 0.50, fx = "rise",   at = "self", count = 12, dur = 0.6 },
		},
	},

	IceSlam = {
		tier = 1, duration = 1.4, color = C(150, 220, 255), color2 = C(230, 250, 255),
		sounds = { charge = "whoosh", strike = "glass", impact = "boom" }, pitch = 1.2,
		steps = {
			{ t = 0.00, fx = "sound",  slot = "charge" },
			{ t = 0.00, fx = "aura",   at = "self", size = 3.5, dur = 0.45 },
			{ t = 0.40, fx = "meteor", at = "target", size = 2.2, height = 14, dur = 0.35 },
			{ t = 0.75, fx = "sound",  slot = "strike" },
			{ t = 0.75, fx = "frost",  at = "target", count = 8, dur = 0.6 },
			{ t = 0.78, fx = "shards", at = "target", count = 8, size = 0.6, dur = 0.5 },
		},
	},

	FireBite = {
		tier = 1, duration = 1.3, color = C(255, 110, 30), color2 = C(255, 220, 80),
		sounds = { strike = "snap", impact = "rumble" }, pitch = 1.1,
		steps = {
			{ t = 0.00, fx = "aura",   at = "self", size = 3, dur = 0.4 },
			{ t = 0.35, fx = "sound",  slot = "strike" },
			{ t = 0.40, fx = "projectile", size = 1.2, dur = 0.3 },
			{ t = 0.70, fx = "sparks", at = "target", count = 16, dur = 0.6 },
			{ t = 0.70, fx = "sound",  slot = "impact" },
			{ t = 0.75, fx = "rise",   at = "target", count = 8, dur = 0.55 },
		},
	},

	SugarStorm = {
		tier = 1, duration = 1.5, color = C(255, 160, 210), color2 = C(255, 255, 255),
		sounds = { charge = "rumble", impact = "splat" }, pitch = 1.3,
		steps = {
			{ t = 0.00, fx = "sound",  slot = "charge" },
			{ t = 0.00, fx = "spiral", at = "self", radius = 6, count = 14, dur = 0.7, outward = true },
			{ t = 0.60, fx = "wave",   at = "self", radius = 10, dur = 0.5 },
			{ t = 0.75, fx = "shards", at = "target", count = 12, size = 0.4, dur = 0.6 },
			{ t = 0.75, fx = "sound",  slot = "impact" },
		},
	},

	ShardBlast = {
		tier = 1, duration = 1.4, color = C(120, 220, 255), color2 = C(200, 140, 255),
		sounds = { charge = "ping", strike = "rocket", impact = "glass" }, pitch = 1.5,
		steps = {
			{ t = 0.00, fx = "sound",  slot = "charge" },
			{ t = 0.00, fx = "shards", at = "self", count = 6, size = 0.5, dur = 0.4, inward = true },
			{ t = 0.40, fx = "sound",  slot = "strike" },
			{ t = 0.40, fx = "projectile", size = 0.8, dur = 0.25, count = 3 },
			{ t = 0.70, fx = "shards", at = "target", count = 14, size = 0.6, dur = 0.6 },
			{ t = 0.70, fx = "sound",  slot = "impact" },
		},
	},

	----------------------------------------------------------------------------
	-- Welle 2: Epic und Legendary — Bodenringe, Lichtsaeulen, Wackeln (2 bis 3 s)
	----------------------------------------------------------------------------

	GoldRush = {
		tier = 2, duration = 2.2, color = C(255, 200, 50), color2 = C(255, 250, 200),
		sounds = { charge = "ping", strike = "rumble", impact = "boom" }, pitch = 0.9,
		steps = {
			{ t = 0.00, fx = "sound",  slot = "charge" },
			{ t = 0.00, fx = "ring",   at = "self", radius = 7, dur = 0.7 },
			{ t = 0.20, fx = "pillar", at = "self", height = 18, width = 3, dur = 0.9 },
			{ t = 0.90, fx = "beam",   width = 1.2, dur = 0.7 },
			{ t = 0.90, fx = "sound",  slot = "strike" },
			{ t = 1.20, fx = "rise",   at = "target", count = 14, dur = 0.8, toSelf = true },
			{ t = 1.50, fx = "shake",  power = 0.4, dur = 0.3 },
			{ t = 1.50, fx = "sound",  slot = "impact" },
		},
	},

	BlackHole = {
		tier = 2, duration = 2.8, color = C(80, 30, 140), color2 = C(10, 5, 20),
		sounds = { charge = "rumble", strike = "boom" }, pitch = 0.6,
		steps = {
			{ t = 0.00, fx = "sound",  slot = "charge" },
			{ t = 0.00, fx = "aura",   at = "target", size = 2, dur = 1.6, dark = true },
			{ t = 0.10, fx = "spiral", at = "target", radius = 12, count = 30, dur = 1.6 },
			{ t = 0.20, fx = "ring",   at = "target", radius = 9, dur = 1.4, shrink = true },
			{ t = 1.70, fx = "wave",   at = "target", radius = 12, dur = 0.5 },
			{ t = 1.70, fx = "shake",  power = 0.7, dur = 0.5 },
			{ t = 1.70, fx = "sound",  slot = "strike" },
			{ t = 1.75, fx = "shards", at = "target", count = 18, size = 0.5, dur = 0.8 },
		},
	},

	ChromaBlast = {
		tier = 2, duration = 2.6, color = C(255, 60, 120), color2 = C(60, 200, 255),
		sounds = { charge = "ping", strike = "rocket", impact = "boom" }, pitch = 1.2,
		steps = {
			{ t = 0.00, fx = "sound",  slot = "charge" },
			{ t = 0.00, fx = "aura",   at = "self", size = 5, dur = 1.0, rainbow = true },
			{ t = 0.10, fx = "ring",   at = "self", radius = 8, dur = 0.9, rainbow = true },
			{ t = 1.00, fx = "beam",   width = 2.2, dur = 0.8, rainbow = true },
			{ t = 1.00, fx = "sound",  slot = "strike" },
			{ t = 1.30, fx = "pillar", at = "target", height = 22, width = 4, dur = 0.8, rainbow = true },
			{ t = 1.30, fx = "shake",  power = 0.5, dur = 0.35 },
			{ t = 1.30, fx = "sound",  slot = "impact" },
		},
	},

	TitanMode = {
		tier = 2, duration = 2.4, color = C(200, 170, 110), color2 = C(255, 240, 200),
		sounds = { charge = "rumble", strike = "boom" }, pitch = 0.7,
		steps = {
			{ t = 0.00, fx = "sound",  slot = "charge" },
			{ t = 0.00, fx = "shake",  power = 0.3, dur = 0.8 },
			{ t = 0.00, fx = "ring",   at = "self", radius = 10, dur = 0.8 },
			{ t = 0.30, fx = "pillar", at = "self", height = 26, width = 6, dur = 1.0 },
			{ t = 1.00, fx = "bubble", at = "self", size = 9, dur = 1.3, hex = true },
			{ t = 1.00, fx = "sound",  slot = "strike" },
			{ t = 1.10, fx = "shards", at = "self", count = 12, size = 0.9, dur = 0.7, stone = true },
		},
	},

	----------------------------------------------------------------------------
	-- Welle 3: Mythic und Divine — Himmel verfaerbt sich, Zeitlupe (3 bis 4 s)
	----------------------------------------------------------------------------

	BigBang = {
		tier = 3, duration = 3.6, color = C(255, 255, 255), color2 = C(140, 120, 255),
		sounds = { charge = "rumble", strike = "boom", impact = "rocket" }, pitch = 0.8,
		steps = {
			{ t = 0.00, fx = "sound",  slot = "charge" },
			{ t = 0.00, fx = "sky",    tint = C(150, 140, 255), brightness = -0.15, saturation = -0.3, dur = 3.0 },
			{ t = 0.00, fx = "spiral", at = "arena", radius = 18, count = 36, dur = 1.4 },
			{ t = 1.40, fx = "flash",  dur = 0.35 },
			{ t = 1.40, fx = "hitstop", dur = 0.3 },
			{ t = 1.70, fx = "wave",   at = "arena", radius = 30, dur = 0.8 },
			{ t = 1.70, fx = "sound",  slot = "strike" },
			{ t = 1.75, fx = "sparks", at = "arena", count = 50, dur = 1.2, stars = true },
			{ t = 1.75, fx = "shake",  power = 1.0, dur = 0.6 },
		},
	},

	PhoenixRebirth = {
		tier = 3, duration = 3.4, color = C(255, 120, 30), color2 = C(255, 230, 100),
		sounds = { charge = "rumble", strike = "rocket", impact = "boom" }, pitch = 1.0,
		steps = {
			{ t = 0.00, fx = "sky",    tint = C(255, 170, 120), brightness = 0.05, saturation = 0.2, dur = 3.0 },
			{ t = 0.00, fx = "sound",  slot = "charge" },
			{ t = 0.00, fx = "pillar", at = "self", height = 30, width = 5, dur = 1.4 },
			{ t = 0.20, fx = "rise",   at = "self", count = 24, dur = 1.4, wings = true },
			{ t = 1.50, fx = "hitstop", dur = 0.25 },
			{ t = 1.70, fx = "projectile", size = 2.5, dur = 0.4, flame = true },
			{ t = 1.70, fx = "sound",  slot = "strike" },
			{ t = 2.10, fx = "wave",   at = "target", radius = 12, dur = 0.6 },
			{ t = 2.10, fx = "sound",  slot = "impact" },
			{ t = 2.10, fx = "shake",  power = 0.7, dur = 0.4 },
		},
	},

	GlacierFrost = {
		tier = 3, duration = 3.2, color = C(170, 230, 255), color2 = C(255, 255, 255),
		sounds = { charge = "whoosh", strike = "glass" }, pitch = 0.8,
		steps = {
			{ t = 0.00, fx = "sky",    tint = C(190, 225, 255), brightness = 0.1, saturation = -0.4, dur = 2.8 },
			{ t = 0.00, fx = "sound",  slot = "charge" },
			{ t = 0.00, fx = "ring",   at = "self", radius = 14, dur = 1.2, ice = true },
			{ t = 0.60, fx = "spiral", at = "target", radius = 8, count = 20, dur = 1.0, snow = true },
			{ t = 1.50, fx = "frost",  at = "target", count = 18, dur = 1.4 },
			{ t = 1.50, fx = "hitstop", dur = 0.4 },
			{ t = 1.50, fx = "sound",  slot = "strike" },
		},
	},

	PhantomOmen = {
		-- Passiv: im Kampf nie ausgeloest. Die Show laeuft beim Legen eines
		-- aufgestiegenen Eis (EggLayService feuert SkillFXPlay).
		tier = 3, duration = 2.0, color = C(150, 90, 230), color2 = C(40, 20, 70),
		sounds = { charge = "ghost", strike = "ping" }, pitch = 0.6,
		steps = {
			{ t = 0.00, fx = "sound",  slot = "charge" },
			{ t = 0.00, fx = "aura",   at = "self", size = 6, dur = 1.2, dark = true },
			{ t = 0.30, fx = "spiral", at = "self", radius = 5, count = 16, dur = 1.0, outward = true },
			{ t = 1.20, fx = "pillar", at = "self", height = 12, width = 1.5, dur = 0.7 },
			{ t = 1.20, fx = "sound",  slot = "strike" },
		},
	},

	SeraphGrace = {
		tier = 3, duration = 3.4, color = C(255, 245, 190), color2 = C(255, 255, 255),
		sounds = { charge = "flash", strike = "ping" }, pitch = 1.6,
		steps = {
			{ t = 0.00, fx = "sky",    tint = C(255, 248, 210), brightness = 0.2, saturation = 0.1, dur = 3.0 },
			{ t = 0.00, fx = "sound",  slot = "charge" },
			{ t = 0.00, fx = "pillar", at = "self", height = 40, width = 7, dur = 2.2, fromSky = true },
			{ t = 0.50, fx = "rise",   at = "self", count = 30, dur = 1.8 },
			{ t = 1.20, fx = "ring",   at = "self", radius = 9, dur = 1.0 },
			{ t = 1.20, fx = "sound",  slot = "strike" },
			{ t = 1.30, fx = "aura",   at = "self", size = 7, dur = 1.5 },
		},
	},

	AuroraVeil = {
		tier = 3, duration = 3.3, color = C(90, 255, 180), color2 = C(170, 110, 255),
		sounds = { charge = "whoosh", strike = "ping" }, pitch = 1.2,
		steps = {
			{ t = 0.00, fx = "sky",    tint = C(170, 255, 220), brightness = -0.05, saturation = 0.4, dur = 3.0 },
			{ t = 0.00, fx = "sound",  slot = "charge" },
			{ t = 0.00, fx = "beam",   width = 6, dur = 2.0, curtain = true },
			{ t = 0.40, fx = "spiral", at = "self", radius = 6, count = 22, dur = 1.4, outward = true },
			{ t = 1.60, fx = "aura",   at = "self", size = 6, dur = 1.4, rainbow = true },
			{ t = 1.60, fx = "sound",  slot = "strike" },
			{ t = 1.70, fx = "rise",   at = "self", count = 16, dur = 1.0 },
		},
	},

	EclipseShroud = {
		tier = 3, duration = 3.5, color = C(30, 20, 50), color2 = C(255, 180, 80),
		sounds = { charge = "ghost", strike = "bass" }, pitch = 0.5,
		steps = {
			{ t = 0.00, fx = "sky",    tint = C(110, 90, 140), brightness = -0.35, saturation = -0.5, dur = 3.2 },
			{ t = 0.00, fx = "sound",  slot = "charge" },
			{ t = 0.20, fx = "meteor", at = "target", size = 7, height = 30, dur = 1.4, dark = true, slow = true },
			{ t = 1.60, fx = "ring",   at = "target", radius = 7, dur = 1.0, corona = true },
			{ t = 1.60, fx = "hitstop", dur = 0.35 },
			{ t = 1.70, fx = "aura",   at = "target", size = 5, dur = 1.4, dark = true },
			{ t = 1.70, fx = "sound",  slot = "strike" },
		},
	},

	----------------------------------------------------------------------------
	-- Welle 4: Cosmic bis Omega — reine Schaden-Show (4 bis 6 s)
	----------------------------------------------------------------------------

	CometImpact = {
		tier = 4, duration = 4.4, color = C(120, 180, 255), color2 = C(255, 255, 255),
		sounds = { charge = "rumble", strike = "rocket", impact = "boom" }, pitch = 0.9,
		steps = {
			{ t = 0.00, fx = "sky",       tint = C(140, 160, 255), brightness = -0.25, saturation = -0.2, dur = 4.0 },
			{ t = 0.00, fx = "starfield", count = 60, dur = 4.0 },
			{ t = 0.00, fx = "cinematic", dur = 2.2, style = "up" },
			{ t = 0.00, fx = "sound",     slot = "charge" },
			{ t = 0.60, fx = "meteor",    at = "target", size = 5, height = 80, dur = 1.6, tail = true },
			{ t = 2.20, fx = "flash",     dur = 0.3 },
			{ t = 2.20, fx = "hitstop",   dur = 0.3 },
			{ t = 2.25, fx = "wave",      at = "target", radius = 26, dur = 0.8 },
			{ t = 2.25, fx = "sound",     slot = "impact" },
			{ t = 2.25, fx = "shake",     power = 1.2, dur = 0.8 },
			{ t = 2.30, fx = "shards",    at = "target", count = 30, size = 1.0, dur = 1.2, stone = true },
		},
	},

	NebulaBurn = {
		tier = 4, duration = 4.6, color = C(255, 90, 200), color2 = C(90, 120, 255),
		sounds = { charge = "whoosh", strike = "rumble", impact = "snap" }, pitch = 0.8,
		steps = {
			{ t = 0.00, fx = "sky",       tint = C(230, 150, 255), brightness = -0.1, saturation = 0.5, dur = 4.2 },
			{ t = 0.00, fx = "starfield", count = 50, dur = 4.2, nebula = true },
			{ t = 0.00, fx = "sound",     slot = "charge" },
			{ t = 0.20, fx = "spiral",    at = "arena", radius = 20, count = 40, dur = 2.0, outward = true, cloud = true },
			{ t = 0.40, fx = "cinematic", dur = 2.0, style = "orbit" },
			{ t = 2.30, fx = "wave",      at = "target", radius = 10, dur = 1.0, cloud = true },
			{ t = 2.30, fx = "sound",     slot = "strike" },
			{ t = 2.60, fx = "sparks",    at = "target", count = 40, dur = 1.8, ember = true },
			{ t = 2.60, fx = "sound",     slot = "impact" },
		},
	},

	PulsarPulse = {
		tier = 4, duration = 4.2, color = C(80, 240, 255), color2 = C(255, 255, 255),
		sounds = { charge = "ping", strike = "boom" }, pitch = 1.3,
		steps = {
			{ t = 0.00, fx = "sky",       tint = C(160, 240, 255), brightness = -0.2, saturation = 0.1, dur = 3.8 },
			{ t = 0.00, fx = "starfield", count = 40, dur = 3.8 },
			{ t = 0.00, fx = "sound",     slot = "charge" },
			{ t = 0.00, fx = "pillar",    at = "self", height = 50, width = 1.4, dur = 3.4, beacon = true },
			{ t = 0.40, fx = "ring",      at = "self", radius = 8, dur = 0.5 },
			{ t = 1.00, fx = "ring",      at = "self", radius = 12, dur = 0.5 },
			{ t = 1.60, fx = "ring",      at = "self", radius = 16, dur = 0.5 },
			{ t = 1.60, fx = "cinematic", dur = 1.6, style = "side" },
			{ t = 2.20, fx = "beam",      width = 3, dur = 0.8 },
			{ t = 2.20, fx = "sound",     slot = "strike" },
			{ t = 2.20, fx = "shake",     power = 0.9, dur = 0.5 },
			{ t = 2.30, fx = "wave",      at = "target", radius = 14, dur = 0.6 },
		},
	},

	ShadeSlash = {
		tier = 4, duration = 4.4, color = C(30, 30, 40), color2 = C(200, 40, 80),
		sounds = { charge = "whoosh", strike = "slash", impact = "boom" }, pitch = 0.7,
		steps = {
			{ t = 0.00, fx = "sky",       tint = C(90, 80, 110), brightness = -0.45, saturation = -0.7, dur = 4.0 },
			{ t = 0.00, fx = "sound",     slot = "charge" },
			{ t = 0.00, fx = "aura",      at = "self", size = 8, dur = 1.5, dark = true },
			{ t = 1.20, fx = "cinematic", dur = 1.6, style = "low" },
			{ t = 1.50, fx = "beam",      width = 0.5, dur = 0.25, slash = true },
			{ t = 1.50, fx = "sound",     slot = "strike" },
			{ t = 1.80, fx = "beam",      width = 0.5, dur = 0.25, slash = true, cross = true },
			{ t = 2.10, fx = "hitstop",   dur = 0.5 },
			{ t = 2.60, fx = "shards",    at = "target", count = 26, size = 0.7, dur = 1.0 },
			{ t = 2.60, fx = "sound",     slot = "impact" },
			{ t = 2.60, fx = "shake",     power = 1.0, dur = 0.5 },
		},
	},

	RiddleBeam = {
		tier = 4, duration = 4.3, color = C(200, 255, 120), color2 = C(255, 120, 255),
		sounds = { charge = "ping", strike = "rocket", impact = "glass" }, pitch = 1.1,
		steps = {
			{ t = 0.00, fx = "sky",       tint = C(220, 255, 200), brightness = -0.15, saturation = 0.3, dur = 4.0 },
			{ t = 0.00, fx = "sound",     slot = "charge" },
			{ t = 0.00, fx = "ring",      at = "self", radius = 6, dur = 1.6, glyphs = true },
			{ t = 0.30, fx = "ring",      at = "self", radius = 9, dur = 1.4, glyphs = true },
			{ t = 0.60, fx = "cinematic", dur = 2.0, style = "orbit" },
			{ t = 1.80, fx = "beam",      width = 2.5, dur = 1.2, rainbow = true },
			{ t = 1.80, fx = "sound",     slot = "strike" },
			{ t = 2.40, fx = "shards",    at = "target", count = 20, size = 0.8, dur = 1.0, glyphs = true },
			{ t = 2.40, fx = "sound",     slot = "impact" },
			{ t = 2.40, fx = "shake",     power = 0.8, dur = 0.4 },
		},
	},

	TitanFist = {
		tier = 4, duration = 4.8, color = C(220, 160, 90), color2 = C(255, 240, 200),
		sounds = { charge = "rumble", strike = "boom", impact = "thunder" }, pitch = 0.55,
		steps = {
			{ t = 0.00, fx = "sky",       tint = C(255, 210, 160), brightness = -0.2, saturation = 0.1, dur = 4.4 },
			{ t = 0.00, fx = "sound",     slot = "charge" },
			{ t = 0.00, fx = "shake",     power = 0.35, dur = 1.6 },
			{ t = 0.00, fx = "cinematic", dur = 2.4, style = "up" },
			{ t = 0.40, fx = "meteor",    at = "target", size = 9, height = 90, dur = 1.8, fist = true },
			{ t = 2.20, fx = "flash",     dur = 0.25 },
			{ t = 2.20, fx = "hitstop",   dur = 0.4 },
			{ t = 2.60, fx = "wave",      at = "target", radius = 34, dur = 0.9 },
			{ t = 2.60, fx = "ring",      at = "target", radius = 24, dur = 1.0, crack = true },
			{ t = 2.60, fx = "sound",     slot = "impact" },
			{ t = 2.60, fx = "shake",     power = 1.5, dur = 0.9 },
			{ t = 2.65, fx = "shards",    at = "target", count = 36, size = 1.4, dur = 1.4, stone = true },
		},
	},

	GenesisWave = {
		tier = 4, duration = 5.0, color = C(120, 255, 140), color2 = C(255, 250, 220),
		sounds = { charge = "whoosh", strike = "rumble", impact = "boom" }, pitch = 0.9,
		steps = {
			{ t = 0.00, fx = "sky",       tint = C(200, 255, 210), brightness = 0.15, saturation = 0.4, dur = 4.6 },
			{ t = 0.00, fx = "starfield", count = 50, dur = 4.6 },
			{ t = 0.00, fx = "sound",     slot = "charge" },
			{ t = 0.00, fx = "rise",      at = "arena", count = 40, dur = 2.0 },
			{ t = 0.40, fx = "cinematic", dur = 2.4, style = "orbit" },
			{ t = 1.80, fx = "wave",      at = "self", radius = 12, dur = 0.6 },
			{ t = 2.30, fx = "wave",      at = "self", radius = 22, dur = 0.7 },
			{ t = 2.30, fx = "sound",     slot = "strike" },
			{ t = 2.90, fx = "wave",      at = "self", radius = 34, dur = 0.8 },
			{ t = 2.90, fx = "sound",     slot = "impact" },
			{ t = 2.90, fx = "shake",     power = 1.1, dur = 0.6 },
		},
	},

	ChronosRift = {
		tier = 4, duration = 5.2, color = C(255, 200, 80), color2 = C(80, 60, 160),
		sounds = { charge = "rumble", strike = "glass", impact = "boom" }, pitch = 0.65,
		steps = {
			{ t = 0.00, fx = "sky",       tint = C(255, 230, 170), brightness = -0.1, saturation = -0.6, dur = 4.8 },
			{ t = 0.00, fx = "sound",     slot = "charge" },
			{ t = 0.00, fx = "ring",      at = "arena", radius = 16, dur = 2.0, clock = true },
			{ t = 0.40, fx = "cinematic", dur = 2.4, style = "side" },
			{ t = 1.20, fx = "hitstop",   dur = 0.8 },
			{ t = 2.00, fx = "beam",      width = 0.6, dur = 0.8, rift = true },
			{ t = 2.00, fx = "sound",     slot = "strike" },
			{ t = 2.80, fx = "spiral",    at = "target", radius = 10, count = 30, dur = 0.8 },
			{ t = 3.40, fx = "flash",     dur = 0.3 },
			{ t = 3.40, fx = "wave",      at = "target", radius = 20, dur = 0.7 },
			{ t = 3.40, fx = "sound",     slot = "impact" },
			{ t = 3.40, fx = "shake",     power = 1.2, dur = 0.6 },
		},
	},

	InfinityBarrage = {
		tier = 4, duration = 5.0, color = C(255, 120, 40), color2 = C(255, 255, 160),
		sounds = { charge = "ping", strike = "rocket", impact = "hit" }, pitch = 1.4,
		steps = {
			{ t = 0.00, fx = "sky",       tint = C(255, 200, 150), brightness = -0.15, saturation = 0.3, dur = 4.6 },
			{ t = 0.00, fx = "sound",     slot = "charge" },
			{ t = 0.00, fx = "ring",      at = "self", radius = 7, dur = 1.0, infinity = true },
			{ t = 0.40, fx = "cinematic", dur = 2.2, style = "side" },
			{ t = 1.20, fx = "projectile", size = 1.4, dur = 0.35, count = 1 },
			{ t = 1.45, fx = "projectile", size = 1.4, dur = 0.35, count = 1 },
			{ t = 1.70, fx = "projectile", size = 1.4, dur = 0.35, count = 1 },
			{ t = 1.95, fx = "projectile", size = 1.4, dur = 0.35, count = 1 },
			{ t = 2.20, fx = "projectile", size = 2.4, dur = 0.45, count = 1 },
			{ t = 1.20, fx = "sound",     slot = "strike" },
			{ t = 2.65, fx = "sparks",    at = "target", count = 60, dur = 1.4 },
			{ t = 2.65, fx = "sound",     slot = "impact" },
			{ t = 2.65, fx = "shake",     power = 1.0, dur = 0.7 },
		},
	},

	OmegaStrike = {
		-- "Ein Moment, den man filmt und teilt": die Arena friert ein, ein
		-- Farbspektrum laeuft durch, dann EIN Schlag.
		tier = 4, duration = 6.0, color = C(255, 255, 255), color2 = C(0, 0, 0),
		sounds = { charge = "bass", strike = "thunder", impact = "boom" }, pitch = 0.45,
		steps = {
			{ t = 0.00, fx = "sound",     slot = "charge" },
			{ t = 0.00, fx = "sky",       tint = C(255, 255, 255), brightness = -0.3, saturation = -1.0, dur = 1.8 },
			{ t = 0.00, fx = "hitstop",   dur = 1.4 },
			{ t = 0.00, fx = "cinematic", dur = 2.5, style = "orbit" },
			{ t = 0.20, fx = "starfield", count = 80, dur = 5.6 },
			{ t = 1.60, fx = "spectrum",  dur = 1.8 },
			{ t = 1.60, fx = "aura",      at = "self", size = 10, dur = 1.8, rainbow = true },
			{ t = 3.40, fx = "beam",      width = 5, dur = 0.5 },
			{ t = 3.40, fx = "flash",     dur = 0.5 },
			{ t = 3.40, fx = "sound",     slot = "strike" },
			{ t = 3.50, fx = "pillar",    at = "target", height = 120, width = 10, dur = 1.6, fromSky = true },
			{ t = 3.50, fx = "wave",      at = "target", radius = 45, dur = 1.2 },
			{ t = 3.50, fx = "shake",     power = 2.0, dur = 1.2 },
			{ t = 3.55, fx = "sound",     slot = "impact" },
			{ t = 3.60, fx = "shards",    at = "target", count = 50, size = 1.2, dur = 1.6, rainbow = true },
		},
	},
}

-- Unbekannte Faehigkeit: neutrale Kurz-Show statt gar nichts.
local FALLBACK: SkillFX = FX.BasicPunch

local function get(skillId: string?): SkillFX
	return (skillId and FX[skillId]) or FALLBACK
end

-- Wie lange der Server die Stage fuer die Show anhaelt.
local function getDuration(skillId: string?, full: boolean): number
	local fx = get(skillId)
	if not full then
		return TIERS[fx.tier].echo
	end
	return math.min(fx.duration, TIERS[fx.tier].maxDuration)
end

-- v15.1: WANN die Show den Gegner trifft (Sekunden ab Start). In genau
-- diesem Moment setzt PitArenaService die HP- und Ladeleisten und laesst den
-- Gegner zurueckfliegen — der Schaden soll sichtbar MIT dem Treffer kommen,
-- nicht erst nach der Show.
--
-- Regel: die Shows sind auf ihre Klaenge geschnitten — der "impact"-Ton
-- sitzt auf dem Einschlag (Omega: Strahl + Saeule), wo es keinen gibt, der
-- "strike"-Ton (Schwarzes Loch: die Welle). Hat eine Show keinen von beiden,
-- zaehlt der erste Effekt am Gegner. Eine Show kann das mit `impactAt` selbst
-- setzen.
local HIT_BLOCKS: { [string]: boolean } = {
	beam = true, pillar = true, ring = true, sparks = true, shards = true,
	frost = true, wave = true, spiral = true, rise = true,
}

local function firstSound(fx: SkillFX, slot: string): number?
	for _, step in fx.steps do
		if step.fx == "sound" and step.slot == slot then
			return step.t or 0
		end
	end
	return nil
end

local function getImpactTime(skillId: string?, full: boolean): number
	local fx = get(skillId)
	if not full then
		return TIERS[fx.tier].echo * 0.4
	end
	local limit = getDuration(skillId, true)
	local explicit = (fx :: any).impactAt
	if typeof(explicit) == "number" then
		return math.clamp(explicit, 0, limit)
	end
	local best = firstSound(fx, "impact") or firstSound(fx, "strike")
	if not best then
		for _, step in fx.steps do
			local t = step.t or 0
			if HIT_BLOCKS[step.fx] and (step.at == "target" or step.fx == "beam") then
				if not best or t < best then best = t end
			end
		end
	end
	return math.clamp(best or limit * 0.5, 0, limit)
end

return {
	CINEMATIC_CAMERA = CINEMATIC_CAMERA,
	TIERS            = TIERS,
	PARTICLE_BUDGET  = PARTICLE_BUDGET,
	SOUND_LIBRARY    = SOUND_LIBRARY,
	SOUND            = SOUND,
	data             = FX,
	get              = get,
	getDuration      = getDuration,
	getImpactTime    = getImpactTime,
}
