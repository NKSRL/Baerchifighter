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
-- v16 (Gletscher-Show) — neue Bausteine, alle relativ zu den Figuren (Fuesse
-- aus der Bounding-Box), stimmen also auf dem Tower in jeder Hoehe:
--   breath     Atemwolke vor dem Maul, 2 Stoesse (1 Emitter)  count, dur, tex
--   groundmark Boden friert im Kreis, Adern kriechen raus     radius, dur, veins, tex
--   crack      Zickzack-Riss am Boden von self zu target      dur, linger, segments, amp, width, tex
--   spikes     schraege Dornen brechen nacheinander entlang   count, dur, rise, minHeight, maxHeight, linger, tex
--              des letzten `crack` aus, jeder hoeher (Welle)
--   snowfall   Nachgluehen: Reifschimmer + sinkende Flocken  count, dur, tex
--              (1 Emitter)
-- Erweiterte Parameter bestehender Bausteine (v16):
--   frost  legs = true   Kristalle wachsen von den Fuessen bis zur Huefte
--          perch = true  kleine Kristalle auf Ohren und Schultern, glint = true
--                        laesst jede Kante EINMAL weiss aufleuchten
--   ring   ground = true flacher Ring auf dem Boden unter der Figur; tex
--
-- v16 (Seraph-Show) — neue Bausteine:
--   wings      Lichtfluegel hinter der Figur, Feder fuer Feder  count, span, dur, foldAt, tex, sparkTex
--              von innen nach aussen; bei foldAt falten und
--              in Funken zerfallen (1 Emitter, Beiwerk)
--   halo       Heiligenschein ueber dem Kopf, dreht langsam,    radius, lift, count, dur, tex
--              folgt der Figur
--   honeycomb  Wabenmuster laeuft Fuesse -> Kopf, zieht ein,  cols, rows, sweep, pull, hold, tex
--              warmer Schein bleibt `hold` s an der Figur
--              (folgt ihr auch beim Anlauf zum Stoss)
-- Erweiterte Parameter (v16):
--   ring     lift = n     Ring n Studs ueber der Figur (Wolkenloch), mit tex
--                        auch von unten sichtbar
--   pillar   feet = true  Fuss der Saeule unter der Figur; soft = true
--                        halbdurchsichtig; tex = Bild als Beam (weicher Verlauf)
--   snowfall noShell = true nur Emitter (z. B. rieselnde Federn); lift, size
--   alle     second = true Zweitfarbe (color2) statt Hauptfarbe
--
-- v16 (Kometen-Show) — neue Bausteine:
--   shadow  dunkler Kreis am Boden, waechst beschleunigt       from, radius, dur, fadeOut, toArena
--   comet   Punkt funkelt oben und waechst (`charge`), dann    height, size, charge, fall, cloudY,
--           faellt der Komet (Kopf, Kern, Schweif, Funken =     tex, tailTex, sparkTex
--           1 Emitter) auf den Gegner, letzte 30 % langsam;
--           Wolkenfetzen bei cloudY (Beiwerk)
--   crater  Glut-Risse im Boden, kuehlen Orange -> Violett ab  radius, count, dur, tex
--   dust    Sternstaub im Bogen (1 Emitter, Schwerkraft)       count, speed, dur, tex
-- Erweiterte Parameter (v16):
--   radius = "tower" | "fence"  Turmspitze bzw. bis zum Arena-Zaun (MapConfig),
--            gemessen ab der Arena-Mitte (ring, shadow, crater)
--   ring     toArena = true  Bodenring startet an der Figur, waechst um die
--            Arena-Mitte (Schockwelle bis zum Zaun)
--   shards   arc = true      Truemmer fliegen im Bogen und landen am Boden; tex
--   sky      fade = s        so lange dauert das Einfaerben (Standard 0,35)
--   cinematic style "chase"  Kamera schraeg hinter dem laufenden `comet`
--   alle     ownerOnly = true Schritt nur fuer den Besitzer (z. B. Sterne
--            als Teil seines Nachthimmels)
--
-- v16 (Schemen-Show) — neue Bausteine:
--   silhouette Schatten der Figur richtet sich als flache Tinten-       behind, rise, hold, dissolve,
--              Silhouette hinter ihr auf, zerfaellt in Rauch           tex, smokeTex
--              (Tinten-Klon der Figur, Tiefe gestaucht; 1 Emitter)
--   shades     Pfuetzen rund um die Figur, aus jeder steigt ein       count, distance, pool, rise,
--              Schatten-Baerchi (Tinten-Klon), loest sich auf        fadeAt, dissolve, tex, smokeTex
--   vanish     Figur wird blasser (LocalTransparencyModifier, nur     to, fadeIn, back
--              lokal) und steht bei `back` schlagartig wieder da
--   silence    der Ton geht ganz aus (nur Besitzer)                   dur
--   cut        ein duenner weisser Schnitt quer durchs Bild (an der   length, width, draw, tearAt,
--              Kamera jedes Clients ausgerichtet), reisst auf          angle, tex
-- Erweiterte Parameter (v16):
--   shards   tex  Bild auf beiden grossen Flaechen (Schattenfetzen)
--
-- v16 (Omega-Show) — neue Bausteine:
--   omega     Omega-Zeichen Strich fuer Strich. mode "sky": hoch     mode, radius, lift, segments, draw,
--             ueber der Arena, zur Kamera gedreht, zieht sich bei    pullAt, jerk, burnFor, fade, tex
--             `pullAt` mit einem Ruck auf die Pfote. mode "brand":
--             flach am Boden eingebrannt, verblasst.
--   converge  Lichtpunkte aus vier Himmelsrichtungen (eine Farbe     colors, perSide, from, lift,
--             je Richtung) fliegen in einen Punkt ueber der Arena    flight, stagger, tex
--   spotlight Figur leuchtet (Highlight, nur Besitzer)               dur, fill, strength
--   wipe      Spektrum laeuft als Welle durchs Bild, dahinter        dur, tex
--             kommt die Farbe zurueck (nur Besitzer)
-- Erweiterte Parameter (v16):
--   alle      color = Color3  feste Farbe fuer diesen Schritt
--   alle      global = true   auch Spieler AUSSERHALB der Zuschauer-
--             Reichweite sehen diesen Schritt (nur volle Show)
--   alle      bonus = true    Schritt laeuft nur, wenn der Server `bonus`
--             mitschickt (Finisher/Opener hat gegriffen, SkillFXPlay)
--   silence   level = 0..1    statt stumm nur leiser (0,15 = ganz leise)
--   cinematic style "orbitSelf"  langsamer Halbkreis um den eigenen Baerchi
-- Fuer jeden Schritt:
--   extra = true  Beiwerk — faellt auf niedriger Grafikstufe weg
--                 (PARTICLE_BUDGET.EXTRAS_MIN), der Kernmoment bleibt.
--   tex = "<key>" Bild aus TEXTURES[<Faehigkeit>][key]. Ist keine ID
--                 eingetragen (0), laeuft der Rueckfall (Neon-Teile,
--                 Standard-Partikel).
-- Fuer einen Eintrag:
--   echo     eigene Schritt-Liste fuer das Echo (ab dem 2. Einsatz im Lauf,
--            Laenge TIERS[tier].echo). Ohne `echo`: die ersten zwei
--            Welt-Effekte der Show, verkuerzt.
--   impactAt Sekunde, in der die Show den Gegner trifft (sonst geschaetzt,
--            siehe getImpactTime).
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
	-- v16: unter diesem Faktor fallen Schritte mit `extra = true` und das
	-- Beiwerk der Bausteine (Adern, Glitzer) weg. Niedrig = 0,35 (Besitzer);
	-- Zuschauer bekommen x0,6, sehen also nur auf hoher Stufe Beiwerk.
	EXTRAS_MIN = 0.5,
}

-- v16: Bilder je Faehigkeit (Asset-IDs). 0 = noch nicht hochgeladen -> der
-- Baustein nimmt seinen Rueckfall. Die PNGs liegen unter assets/vfx/<faehigkeit>/
-- (gezeichnet von tools/render_vfx_glacier.py).
local TEXTURES: { [string]: { [string]: number } } = {
	GlacierFrost = {
		breath    = 0,  -- assets/vfx/glacier_frost/breath.png     (breath)
		veins     = 0,  -- assets/vfx/glacier_frost/veins.png      (groundmark)
		crack     = 0,  -- assets/vfx/glacier_frost/crack.png      (crack)
		spike     = 0,  -- assets/vfx/glacier_frost/spike.png      (spikes)
		frostring = 0,  -- assets/vfx/glacier_frost/frostring.png  (ring)
		flake     = 0,  -- assets/vfx/glacier_frost/flake.png      (snowfall)
	},
	SeraphGrace = {
		feather   = 0,  -- assets/vfx/seraph_grace/feather.png     (wings, snowfall)
		halo      = 0,  -- assets/vfx/seraph_grace/halo.png        (halo)
		comb      = 0,  -- assets/vfx/seraph_grace/comb.png        (honeycomb)
		column    = 0,  -- assets/vfx/seraph_grace/column.png      (pillar, Beam)
		cloudrim  = 0,  -- assets/vfx/seraph_grace/cloudrim.png    (ring lift)
		spark     = 0,  -- assets/vfx/seraph_grace/spark.png       (wings: Funken)
	},
	CometImpact = {
		glow      = 0,  -- assets/vfx/comet_impact/glow.png        (comet: Glut des Kopfs)
		tail      = 0,  -- assets/vfx/comet_impact/tail.png        (comet: Schweif-Streifen)
		crater    = 0,  -- assets/vfx/comet_impact/crater.png      (crater: Bodenbild)
		stardust  = 0,  -- assets/vfx/comet_impact/stardust.png    (dust, comet-Funken)
		shockring = 0,  -- assets/vfx/comet_impact/shockring.png   (ring)
		debris    = 0,  -- assets/vfx/comet_impact/debris.png      (shards)
	},
	ShadeSlash = {
		silhouette = 0, -- assets/vfx/shade_slash/silhouette.png   (silhouette)
		shred      = 0, -- assets/vfx/shade_slash/shred.png        (shards: Schattenfetzen)
		cut        = 0, -- assets/vfx/shade_slash/cut.png          (cut: Schnittlinie)
		pool       = 0, -- assets/vfx/shade_slash/pool.png         (shades: Pfuetze)
		smoke      = 0, -- assets/vfx/shade_slash/smoke.png        (silhouette/shades: Rauch)
	},
	OmegaStrike = {
		omega     = 0,  -- assets/vfx/omega_strike/omega.png       (omega sky: Ω-Ring)
		spectrum  = 0,  -- assets/vfx/omega_strike/spectrum.png    (wipe: Spektrum-Verlauf)
		orb       = 0,  -- assets/vfx/omega_strike/orb.png         (converge: Lichtpunkt, je Pfadfarbe eingefaerbt)
		brand     = 0,  -- assets/vfx/omega_strike/brand.png       (omega brand: Ω-Brandzeichen)
		shockring = 0,  -- assets/vfx/omega_strike/shockring.png   (ring)
		column    = 0,  -- assets/vfx/omega_strike/column.png      (pillar: Lichtsaeule, Beam)
	},
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
	echo     : { Step }?,   -- v16: eigenes Echo (siehe oben)
	impactAt : number?,     -- v16: Treffer-Sekunde der vollen Show
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
		-- v16 (Show-Paket, Prompt 1): klar, kalt, unaufhaltsam.
		-- Aufladen: Atem, Boden friert, Reif-Adern, Kristalle auf Ohren und
		--   Schultern, Himmel kuehlt zu blassem Blaugrau (nur Besitzer).
		-- Schlag: Aufstampfen, Zickzack-Riss zum Gegner, Dornen-Welle.
		-- Einschlag (2,25 s): letzter Dorn trifft, Kristalle bis zur Huefte,
		--   Zeitlupe, Frostring, danach Reifschimmer und Schneeflocken.
		-- Farben: Gletscherblau, Eisweiss, tiefes Tuerkis (Dorn-Mix im
		--   Baustein), reines Weiss auf Kanten und Spitzen.
		tier = 3, duration = 3.6, color = C(150, 215, 245), color2 = C(235, 250, 255),
		sounds = { charge = "whoosh", strike = "boom", impact = "glass" }, pitch = 0.8,
		impactAt = 2.25,
		steps = {
			-- 1. Aufladen
			{ t = 0.00, fx = "sky",        tint = C(205, 220, 235), brightness = 0.02, saturation = -0.45, dur = 3.3 },
			{ t = 0.00, fx = "sound",      slot = "charge" },
			{ t = 0.00, fx = "breath",     at = "self", count = 10, dur = 1.0, tex = "breath", extra = true },
			{ t = 0.10, fx = "groundmark", at = "self", radius = 6, dur = 3.2, veins = 7, tex = "veins" },
			{ t = 0.45, fx = "frost",      at = "self", perch = true, count = 8, dur = 1.6, glint = true, extra = true },
			-- 2. Schlag (Aufstampfen bei 1,30)
			{ t = 1.30, fx = "ring",       at = "self", ground = true, radius = 3.5, dur = 0.35, tex = "frostring" },
			{ t = 1.30, fx = "shake",      power = 0.35, dur = 0.2 },
			{ t = 1.30, fx = "sound",      slot = "strike" },
			{ t = 1.35, fx = "crack",      dur = 0.45, linger = 1.9, segments = 7, amp = 0.9, tex = "crack" },
			{ t = 1.40, fx = "spikes",     count = 7, dur = 0.7, rise = 0.16, minHeight = 1.0, maxHeight = 3.4, linger = 1.6, tex = "spike" },
			-- 3. Einschlag (letzter Dorn: 1,40 + 0,7 x 6/7 + 0,16 = 2,16 .. 2,25)
			{ t = 2.25, fx = "frost",      at = "target", legs = true, count = 14, dur = 1.3 },
			{ t = 2.25, fx = "hitstop",    dur = 0.35 },
			{ t = 2.25, fx = "sound",      slot = "impact" },
			{ t = 2.28, fx = "ring",       at = "target", ground = true, radius = 11, dur = 0.9, tex = "frostring" },
			{ t = 2.45, fx = "snowfall",   at = "target", count = 16, dur = 1.15, tex = "flake", extra = true },
		},
		-- Echo (0,55 s): Aufstampfen, Zickzack-Riss, Kristalle am Gegner.
		echo = {
			{ t = 0.00, fx = "ring",  at = "self", ground = true, radius = 3, dur = 0.25 },
			{ t = 0.00, fx = "sound", slot = "strike" },
			{ t = 0.03, fx = "crack", dur = 0.2, linger = 0.4, segments = 5, amp = 0.7 },
			{ t = 0.23, fx = "frost", at = "target", legs = true, count = 8, dur = 0.6 },
			{ t = 0.23, fx = "sound", slot = "impact" },
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
		-- v16 (Show-Paket, Prompt 2): warm, feierlich, ruhig.
		-- Aufladen: Lichtfluegel entfalten sich Feder fuer Feder, Heiligenschein
		--   aus Honiggold dreht sich ueber dem Kopf, das Licht wird waermer
		--   (nur Besitzer).
		-- Schlag: rundes Wolkenloch mit leuchtendem Rand, breite Lichtsaeule
		--   faellt auf den Baerchi (nicht auf den Gegner), Federn rieseln.
		-- Einschlag: Wabenmuster laeuft von den Fuessen zum Kopf und zieht ein
		--   (fertig bei 3,4 s = Show-Ende), warmer Lichtpuls ueber den Boden,
		--   Fluegel falten sich und zerfallen in Funken.
		-- HP-Balken: seit 10.10. setzt PitArenaService ihn im Einschlag-
		--   Moment (impactAt = 3,4 s = Show-Ende), es gibt keinen Stoss danach
		--   mehr. Der warme Schein bleibt `hold` = 1,0 s an der Figur.
		tier = 3, duration = 3.4, color = C(255, 196, 70), color2 = C(255, 246, 225),
		sounds = { charge = "whoosh", strike = "ping", impact = "ping" }, pitch = 1.3,
		impactAt = 3.4,
		steps = {
			-- 1. Aufladen
			{ t = 0.00, fx = "sky",       tint = C(255, 236, 205), brightness = 0.08, saturation = 0.15, dur = 3.3 },
			{ t = 0.00, fx = "sound",     slot = "charge" },
			{ t = 0.00, fx = "wings",     at = "self", count = 7, span = 2.6, dur = 3.4, foldAt = 3.05, tex = "feather", sparkTex = "spark" },
			{ t = 0.30, fx = "halo",      at = "self", radius = 0.9, lift = 0.7, count = 14, dur = 3.0, tex = "halo" },
			-- 2. Schlag
			{ t = 1.15, fx = "ring",      at = "self", lift = 26, radius = 5, dur = 2.1, tex = "cloudrim", extra = true },
			{ t = 1.35, fx = "pillar",    at = "self", fromSky = true, feet = true, soft = true, second = true, height = 26, width = 4.5, dur = 1.5, tex = "column" },
			{ t = 1.35, fx = "sound",     slot = "strike" },
			{ t = 1.60, fx = "snowfall",  at = "self", noShell = true, lift = 3, size = 0.45, count = 8, dur = 1.6, tex = "feather", extra = true },
			-- 3. Einschlag (Waben fertig eingezogen bei 2,55 + 0,5 + 0,35 = 3,40)
			{ t = 2.55, fx = "honeycomb", at = "self", cols = 9, rows = 6, sweep = 0.5, pull = 0.35, hold = 1.0, tex = "comb" },
			{ t = 3.30, fx = "ring",      at = "self", ground = true, radius = 14, dur = 0.8 },
			{ t = 3.35, fx = "sound",     slot = "impact" },
		},
		-- Echo (0,55 s): schmale, kurze Lichtsaeule und das einziehende Wabenmuster.
		echo = {
			{ t = 0.00, fx = "pillar",    at = "self", fromSky = true, feet = true, soft = true, second = true, height = 18, width = 2.2, dur = 0.45, tex = "column" },
			{ t = 0.00, fx = "sound",     slot = "strike" },
			{ t = 0.12, fx = "honeycomb", at = "self", cols = 7, rows = 4, sweep = 0.18, pull = 0.18, hold = 0.9, tex = "comb" },
			{ t = 0.45, fx = "sound",     slot = "impact" },
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
		-- v16 (Show-Paket, Prompt 3): gewaltig, schnell, triumphal, nicht
		-- chaotisch — der Komet ist die ganze Zeit klar zu sehen.
		-- Aufladen: Himmel wird in 1 s zur Nacht, Sterne an (nur Besitzer);
		--   hoch oben funkelt ein Punkt und waechst; um den Gegner waechst ein
		--   dunkler Schattenkreis mit.
		-- Schlag (1,5 s): der Komet faellt, bricht durch die Wolkendecke,
		--   Funken vom Schweif, Kamera schraeg hinterher; kurz vor dem
		--   Aufprall Zeitlupe, der Schatten ist so gross wie der Turm.
		-- Einschlag (2,4 s): weisser Blitz (Besitzer), Krater aus Glut-Rissen,
		--   Truemmer und Sternstaub im Bogen, Schockwelle bis zum Arena-Zaun,
		--   Wackeln; der Krater glueht in Orange und Violett aus.
		-- Turm: alles relativ zu den Kaempfern bzw. zur Arena-Mitte. Alle
		--   Effekte sind spaetestens bei 4,8 s weg (Show 5,0 s), bevor der
		--   Turm zur naechsten Stage waechst.
		tier = 4, duration = 5.0, color = C(255, 150, 60), color2 = C(140, 90, 255),
		sounds = { charge = "rumble", strike = "rocket", impact = "boom" }, pitch = 0.9,
		impactAt = 2.4,
		steps = {
			-- 1. Aufladen
			{ t = 0.00, fx = "sky",       tint = C(70, 80, 150), brightness = -0.35, saturation = -0.3, dur = 4.4, fade = 1.0 },
			{ t = 0.00, fx = "starfield", count = 60, dur = 4.4, ownerOnly = true },
			{ t = 0.00, fx = "sound",     slot = "charge" },
			{ t = 0.25, fx = "shadow",    at = "target", from = 1.5, radius = "tower", dur = 2.15, fadeOut = 0.3, toArena = true },
			{ t = 0.30, fx = "comet",     height = 90, size = 3, charge = 1.2, fall = 0.9, cloudY = 45, tex = "glow", tailTex = "tail", sparkTex = "stardust" },
			-- 2. Schlag (Fall ab 1,5; Zeitlupe die letzten 0,27 s + Bild)
			{ t = 1.50, fx = "sound",     slot = "strike" },
			{ t = 1.50, fx = "cinematic", dur = 1.6, style = "chase" },
			{ t = 2.10, fx = "hitstop",   dur = 0.3 },
			-- 3. Einschlag
			{ t = 2.40, fx = "flash",     dur = 0.35 },
			{ t = 2.40, fx = "sound",     slot = "impact" },
			{ t = 2.40, fx = "shake",     power = 1.1, dur = 0.6 },
			{ t = 2.40, fx = "crater",    at = "target", radius = 7, count = 10, dur = 2.4, tex = "crater" },
			{ t = 2.42, fx = "ring",      at = "target", ground = true, toArena = true, radius = "fence", dur = 0.9, tex = "shockring" },
			{ t = 2.42, fx = "shards",    at = "target", arc = true, count = 16, size = 1.0, dur = 1.1, stone = true, tex = "debris" },
			{ t = 2.45, fx = "dust",      at = "target", count = 40, speed = 14, dur = 1.2, tex = "stardust", extra = true },
			-- Opener-Bonus (erster, starker Einschlag; nur mit `bonus` vom
			-- Server): zweite, violette Schockwelle, staerkeres Wackeln und ein
			-- Glutring direkt am Gegner.
			{ t = 2.40, fx = "shake",     power = 0.6, dur = 0.4, bonus = true },
			{ t = 2.40, fx = "ring",      at = "target", ground = true, radius = 5, dur = 0.45, color = C(255, 220, 140), bonus = true },
			{ t = 2.55, fx = "ring",      at = "target", ground = true, toArena = true, radius = "fence", dur = 1.1, second = true, bonus = true },
		},
		-- Echo (0,65 s): Komet von oben (ohne Nacht und Kamera) und gluehender Krater.
		echo = {
			{ t = 0.00, fx = "comet",  height = 40, size = 2.2, charge = 0, fall = 0.3, tex = "glow", tailTex = "tail" },
			{ t = 0.00, fx = "sound",  slot = "strike" },
			{ t = 0.30, fx = "crater", at = "target", radius = 5, count = 8, dur = 0.55, tex = "crater" },
			{ t = 0.30, fx = "sound",  slot = "impact" },
			-- Opener-Bonus: violette Schockwelle
			{ t = 0.30, fx = "ring",   at = "target", ground = true, radius = 9, dur = 0.35, second = true, bonus = true },
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
		-- v16 (Show-Paket, Prompt 4): lautlos, scharf, unheimlich; kein Blut.
		-- Aufladen: Licht kalt und grau (Besitzer); der Schatten des
		--   Baerchis richtet sich als flache Tinten-Silhouette hinter ihm auf;
		--   der Baerchi selbst wird fast durchsichtig (nur lokal).
		-- Schlag: Silhouette zerfaellt in Rauch; aus drei Schattenpfuetzen um
		--   den Gegner steigen drei Schatten-Baerchis; 0,3 s Stillstand, der
		--   Ton geht ganz aus (Besitzer); EIN duenner weisser Schnitt quer
		--   durchs Bild.
		-- Einschlag (2,65 s): Schnitt reisst auf, Schattenfetzen flattern weg,
		--   der Ton kommt mit einem scharfen Hieb zurueck, die Schatten loesen
		--   sich auf, der echte Baerchi steht schlagartig wieder voll da.
		-- Finisher-Bonus: kommt als `bonus` vom Server (SkillFXPlay); dann
		--   reisst der Schnitt violett statt weiss auf (Baustein `cut`).
		tier = 4, duration = 4.2, color = C(18, 14, 26), color2 = C(85, 50, 135),
		sounds = { charge = "ghost", strike = "whoosh", impact = "slash" }, pitch = 0.7,
		impactAt = 2.65,
		steps = {
			-- 1. Aufladen
			{ t = 0.00, fx = "sky",        tint = C(165, 165, 185), brightness = -0.25, saturation = -0.85, dur = 3.4, fade = 0.6 },
			{ t = 0.00, fx = "sound",      slot = "charge" },
			{ t = 0.10, fx = "silhouette", at = "self", behind = 1.4, rise = 1.0, hold = 0.45, dissolve = 0.4, tex = "silhouette", smokeTex = "smoke" },
			{ t = 0.20, fx = "vanish",     at = "self", to = 0.85, fadeIn = 1.1, back = 2.55 },
			-- 2. Schlag
			{ t = 1.55, fx = "shades",     at = "target", count = 3, distance = 3.4, pool = 1.7, rise = 0.5, fadeAt = 1.15, dissolve = 0.35, tex = "pool", smokeTex = "smoke" },
			{ t = 1.60, fx = "sound",      slot = "strike" },
			{ t = 2.20, fx = "silence",    dur = 0.45 },
			{ t = 2.20, fx = "hitstop",    dur = 0.3 },
			{ t = 2.25, fx = "cut",        at = "target", length = 22, width = 0.12, draw = 0.08, tearAt = 0.4, tex = "cut" },
			-- 3. Einschlag
			{ t = 2.65, fx = "sound",      slot = "impact" },
			{ t = 2.65, fx = "shards",     at = "target", count = 18, size = 0.5, dur = 0.9, tex = "shred" },
			{ t = 2.65, fx = "shake",      power = 0.4, dur = 0.25 },
		},
		-- Echo (0,65 s): nur die Stille (0,15 s) und der weisse Schnitt.
		echo = {
			{ t = 0.00, fx = "silence", dur = 0.15 },
			{ t = 0.02, fx = "cut",     at = "target", length = 16, width = 0.1, draw = 0.05, tearAt = 0.13, tex = "cut" },
			{ t = 0.15, fx = "sound",   slot = "impact" },
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
		-- v16 (Show-Paket, Prompt 5): die groesste Show. Erhaben, endgueltig,
		-- still vor dem Sturm — die Stille ist so wichtig wie der Schlag.
		-- Aufladen: alle Geraeusche werden leise, die Welt fast schwarz-weiss
		--   (Besitzer); der Baerchi leuchtet (Highlight) — ganz aus dem
		--   Filter nehmen kann Roblox ihn nicht. AmbienceController bietet
		--   kein Anhalten von Wolken/Pollen/Schaum -> nur Farbfilter.
		-- Sammeln: riesiges Omega am Himmel, Lichtpunkte in den vier
		--   Pfadfarben fliegen aus allen Himmelsrichtungen hinein; Kamera
		--   im langsamen Halbkreis um den Baerchi (2,4 s).
		-- Schlag (3,3 s): das Omega zieht sich mit einem Ruck auf die Pfote.
		-- Einschlag (3,55 s): Spektrum laeuft durchs Bild, die Farbe kommt
		--   zurueck; Schockwelle in den vier Pfadfarben bis zum Zaun; schmale
		--   Lichtsaeule fuer ALLE Spieler (`global`, 1,3 s, nur volle Show =
		--   hoechstens einmal pro Lauf); Omega brennt sich unter dem Gegner
		--   ein und verblasst.
		tier = 4, duration = 5.8, color = C(255, 255, 255), color2 = C(70, 60, 95),
		sounds = { charge = "bass", strike = "whoosh", impact = "boom" }, pitch = 0.45,
		impactAt = 3.55,
		steps = {
			-- 1. Aufladen (Stille vor dem Sturm)
			{ t = 0.00, fx = "silence",   level = 0.15, dur = 3.3 },
			{ t = 0.00, fx = "sky",       tint = C(255, 255, 255), brightness = -0.08, saturation = -0.92, dur = 5.5, fade = 1.2 },
			{ t = 0.00, fx = "spotlight", at = "self", dur = 3.6, strength = 0.35 },
			{ t = 0.15, fx = "sound",     slot = "charge" },
			-- 2. Sammeln
			{ t = 1.00, fx = "omega",     mode = "sky", at = "arena", radius = 7, lift = 34, segments = 20, draw = 0.9, pullAt = 2.3, jerk = 0.22, tex = "omega" },
			{ t = 1.00, fx = "cinematic", dur = 2.4, style = "orbitSelf" },
			{ t = 1.30, fx = "converge",  colors = { C(255, 200, 60), C(110, 200, 255), C(150, 80, 255), C(235, 235, 255) },
				perSide = 4, from = 45, lift = 34, flight = 0.9, stagger = 0.25, tex = "orb" },
			-- 3. Schlag: Ruck auf die Pfote (3,30 .. 3,52)
			{ t = 3.30, fx = "sound",     slot = "strike" },
			-- 4. Einschlag
			{ t = 3.55, fx = "flash",     dur = 0.4 },
			{ t = 3.55, fx = "sound",     slot = "impact" },
			{ t = 3.55, fx = "shake",     power = 0.9, dur = 0.5 },
			{ t = 3.55, fx = "wipe",      dur = 0.9, tex = "spectrum" },
			{ t = 3.58, fx = "ring",      at = "target", ground = true, toArena = true, radius = "fence", dur = 0.9, color = C(255, 200, 60), tex = "shockring" },
			{ t = 3.66, fx = "ring",      at = "target", ground = true, toArena = true, radius = "fence", dur = 0.9, color = C(110, 200, 255), tex = "shockring" },
			{ t = 3.74, fx = "ring",      at = "target", ground = true, toArena = true, radius = "fence", dur = 0.9, color = C(150, 80, 255), tex = "shockring" },
			{ t = 3.82, fx = "ring",      at = "target", ground = true, toArena = true, radius = "fence", dur = 0.9, color = C(235, 235, 255), tex = "shockring" },
			{ t = 3.60, fx = "pillar",    at = "arena", feet = true, soft = true, height = 160, width = 1.6, dur = 1.3, tex = "column", global = true },
			{ t = 3.70, fx = "omega",     mode = "brand", at = "target", radius = 2.2, segments = 14, draw = 0.2, burnFor = 0.5, fade = 1.5, tex = "brand" },
		},
		-- Echo (0,65 s): Ruck des Rings auf die Pfote und die Schockwelle —
		-- ohne Entfaerbung, Kamera und Lichtsaeule.
		echo = {
			{ t = 0.00, fx = "omega", mode = "sky", at = "self", radius = 2.5, lift = 6, segments = 12, draw = 0.12, pullAt = 0.16, jerk = 0.16, tex = "omega" },
			{ t = 0.16, fx = "sound", slot = "strike" },
			{ t = 0.32, fx = "ring",  at = "target", ground = true, radius = 10, dur = 0.4, color = C(255, 200, 60) },
			{ t = 0.35, fx = "ring",  at = "target", ground = true, radius = 10, dur = 0.4, color = C(110, 200, 255) },
			{ t = 0.38, fx = "ring",  at = "target", ground = true, radius = 10, dur = 0.4, color = C(150, 80, 255) },
			{ t = 0.41, fx = "ring",  at = "target", ground = true, radius = 10, dur = 0.4, color = C(235, 235, 255) },
			{ t = 0.32, fx = "sound", slot = "impact" },
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
	TEXTURES         = TEXTURES,
	SOUND_LIBRARY    = SOUND_LIBRARY,
	SOUND            = SOUND,
	data             = FX,
	get              = get,
	getDuration      = getDuration,
	getImpactTime    = getImpactTime,
}
