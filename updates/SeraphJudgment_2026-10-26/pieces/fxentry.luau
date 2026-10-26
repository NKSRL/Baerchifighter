
	-- ------------------------------------------------------------------
	-- 26.10.2026 Himmelsgericht (SeraphJudgment, Seraph-Baerchi, Divine, Stufe 4,
	-- eine Kamerafahrt 1,05-3,55). Ersetzt Seraphen-Segen (Heal) als defaultSkill;
	-- neue Werte: Opener 3,4x + 60 (erster Einsatz je Gegner), sonst 1,8x + 60.
	-- Dopamin-Plan: Rhythmus beim Aufladen (drei Fluegel-Schnapper), Senkrechte
	-- (Himmelstor), Heldenmoment (Flug, Speer), Urteil (Ticks, Stille, Sturz),
	-- Wucht (Impact-Frames, Hitstop, Beben, Knall nach Blitz), Nachklang (Saeule,
	-- Kuppel, fallende Ringe, Federregen) und eine Pointe (schiefer Heiligenschein
	-- auf dem Gegner, ploppt).
	-- Takte: 0-1,0 Aufladen: Welt warm-golden, Marke unter dem Seraph, er duckt
	--   sich, die sechs Fluegel schnappen Paar fuer Paar auf (0,22/0,44/0,66,
	--   Funken, Lichtfedern), 0,8 Heiligenschein zuendet | 1,0-1,7 Absprung mit
	--   zwei Drehungen und Nachbildern auf 12 Studs, 1,1 das Himmelstor oeffnet
	--   sich 24 Studs ueber der Arena (klein, dann gross), 1,45 Lichtschaefte,
	--   Federn rieseln | 1,9-2,35 der Speer aus Licht sinkt vom Tor in die Pfoten,
	--   2,3 Zielmarke unter dem Gegner, er schaut hoch und zittert, Lichtfaden vom
	--   Tor, Ticks 2,35/2,55/2,70 (Marke schrumpft, Tor pulst) | 2,95 Ausholen,
	--   Stille | 3,02 Sturz spearvoraus mit Nachbildern | 3,27 Landung, 3,28 Treffer
	--   (impactAt) | 3,28-3,46 Schlag (Tabelle unten) | 3,40-3,8 Saeule bis zum
	--   Tor, Druckwelle bis zum Zaun, Federtruemmer, Brandfleck mit Siegel |
	--   3,8-4,35 die Torringe fallen die Saeule herab und werden zu Kondensringen,
	--   Welt dunkler und golden, 3,88 die Kuppel waechst | 4,0 Federregen |
	--   4,35 der Seraph zieht den Speer, er zerfaellt zu Federn | 4,75-5,4
	--   Rueckwaerts-Salto heim | 5,05 die Krone des Tors landet schief auf dem
	--   Gegner (Pointe), 5,65 ploppt sie | 5,9 Ende.
	-- Schlag-Tabelle (T = 3,28; Welt = alle, Schirm = Besitzer):
	--   T-0,33  Stille (silence 0,1), Marke eng, Tor pulst       | Kamera haelt   | -
	--   T-0,26  Sturz (k^2), Nachbilder                          | Peitsche       | lunge
	--   T-0,02  Blitz (flash gold 0,08)                          | Schnitt tief   | -
	--   T       4 Impact-Frames hell/indigo (0,20), hitstop 0,18 | steht, FOV -12 | hit
	--           kleiner Kern (<= 3,2 Koerperradius), Speer steckt|                |
	--   T+0,10  Knall NACH dem Blitz                             |                | boom, bass
	--   T+0,12  Saeule schiesst hoch, Brandfleck, Risse          | quake 1,0      | -
	--   T+0,15  Lichtwand bis zum Zaun, Federn, Staub, Bodenring |                | rumble
	--   T+0,27  Kamerafahrt endet (Custom)                       | Schnitt        |
	--   T+0,42  Wand erreicht die Kamera: Blitz, zweites Beben   | quake 0,5      | -
	--   T+0,5.. Ringe fallen, Kuppel, Federregen, Welt -0,18     | eigene Kamera  | thunder, ping x3
	-- Echo (0,65 s, Treffer 0,26): Lichtspeer faellt von oben in die Zielmarke,
	--   1 Impact-Frame, Hitstop 0,06, Beben 0,4, Bodenring, Federn; Opener-Bonus:
	--   Lichtsaeule (global) + Zaunring.
	-- ------------------------------------------------------------------
	SeraphJudgment = {
		tier = 4, duration = 5.9, impactAt = 3.28,
		color = C(255, 214, 110), color2 = C(255, 246, 225),
		pitch = 1.1,
		sounds = {
			charge = "whoosh", snap = "snap", halo = "ping", launch = "rocket", gate = "thunder",
			forge = "glass", tick = "ping", dive = "lunge", impact = "hit", boom = "boom", bass = "bass",
			rumble = "rumble", feathers = "whoosh", ring = "ping", pull = "snap", pop = "snap",
		},
		steps = {
			-- 1. Aufladen (0 .. 1,0)
			{ t = 0.00, fx = "sky",         tint = C(255, 236, 200), brightness = 0.05, saturation = 0.12, dur = 5.6, fade = 0.5 },
			{ t = 0.00, fx = "sound",       slot = "charge" },
			{ t = 0.00, fx = "moves", hold = 0.1, outline = C(214, 150, 30), keys = {
				{ t = 0.30, pitch = 0.03, scale = 0.93, dy = -0.05, ease = "out" },
				{ t = 0.70, pitch = 0.04, scale = 0.90 },
				{ t = 0.92, scale = 0.88, dy = -0.1, ease = "in" },
				{ t = 1.00, dy = 1.2, scale = 1.0, pitch = -0.02, ease = "out", trail = true, burst = 24, smoke = 16 },
				{ t = 1.45, dy = 12.8, yaw = 2, scale = 1.18, ease = "out", trail = true },
				{ t = 1.70, dy = 12.0, scale = 1.2, pitch = 0, ease = "inout" },
				{ t = 2.05, dy = 12.3, pitch = -0.03, ease = "inout" },
				{ t = 2.40, dy = 12.0, pitch = 0.07, ease = "inout" },
				{ t = 2.75, dy = 12.15, pitch = 0.09, ease = "inout" },
				{ t = 2.95, dy = 12.7, pitch = -0.05, scale = 1.22, ease = "out" },
				{ t = 3.02, dy = 12.7, pitch = -0.05 },
				{ t = 3.27, at = "land", dy = 0, pitch = -0.14, scale = 1.1, ease = "in", trail = true, burst = 40, smoke = 22 },
				{ t = 3.50, at = "land", pitch = 0.05, scale = 1.02, ease = "out" },
				{ t = 3.95, at = "land", pitch = 0.02, scale = 1.0, ease = "inout" },
				{ t = 4.30, at = "land", dy = 0.45, pitch = -0.04, ease = "out" },
				{ t = 4.45, at = "land", dy = 0, pitch = 0.02, ease = "in", burst = 10 },
				{ t = 4.75, at = "land", pitch = 0 },
				{ t = 5.15, at = "home", arc = 4.5, pitch = 1.0, ease = "inout", trail = true },
				{ t = 5.28, at = "home", pitch = 1.0, scale = 0.95, ease = "out", burst = 8, smoke = 8 },
				{ t = 5.40, at = "home", scale = 1.0 },
			} },
			{ t = 0.02, fx = "seraphwings", snapAt = { 0.2, 0.42, 0.64 }, haloAt = 0.78, launchAt = 0.98, diveAt = 3.0, landAt = 3.25, foldAt = 4.2, dur = 5.4 },
			{ t = 0.10, fx = "ring",        at = "self", ground = true, radius = 3.2, dur = 1.0, tex = "halo" },
			{ t = 0.22, fx = "sound",       slot = "snap" },
			{ t = 0.44, fx = "sound",       slot = "snap" },
			{ t = 0.66, fx = "sound",       slot = "snap" },
			{ t = 0.66, fx = "quake",       trauma = 0.22 },
			{ t = 0.80, fx = "sound",       slot = "halo" },
			{ t = 0.95, fx = "sound",       slot = "launch" },
			{ t = 1.00, fx = "dust",        at = "self", count = 22, speed = 10, dur = 0.8, tex = "stardust" },
			-- 2. Aufstieg und Himmelstor (1,0 .. 1,9)
			{ t = 1.05, fx = "cinematic",   style = "seraph", dur = 2.5 },
			{ t = 1.10, fx = "halogate",    at = "arena", lift = 24, radius = 16, open = 0.55, raysAt = 0.35, ticks = { 1.25, 1.45, 1.60 }, offAt = 2.18, fallAt = 2.70, fallFor = 0.55, popAt = 4.55, dur = 4.6, global = true },
			{ t = 1.15, fx = "sound",       slot = "gate" },
			{ t = 1.30, fx = "snowfall",    at = "arena", noShell = true, lift = 20, size = 0.5, count = 16, dur = 2.4, tex = "feather", extra = true },
			-- 3. Speer und Zielmarke (1,9 .. 2,95)
			{ t = 1.90, fx = "seraphspear", formAt = 0, form = 0.35, grabAt = 0.45, plantAt = 1.38, pullAt = 2.45, length = 8, dur = 2.7 },
			{ t = 1.95, fx = "sound",       slot = "forge" },
			{ t = 2.30, fx = "seraphmark",  at = "target", radius = 5.5, shrinkTo = 1.6, ticks = { 0.05, 0.25, 0.40 }, releaseAt = 0.96, dur = 1.0 },
			{ t = 2.35, fx = "sound",       slot = "tick" },
			{ t = 2.36, fx = "quake",       trauma = 0.15 },
			{ t = 2.55, fx = "sound",       slot = "tick" },
			{ t = 2.56, fx = "quake",       trauma = 0.2 },
			{ t = 2.70, fx = "sound",       slot = "tick" },
			{ t = 2.71, fx = "quake",       trauma = 0.25 },
			-- 4. Stille und Sturz (2,95 .. 3,28)
			{ t = 2.95, fx = "silence",     dur = 0.33, level = 0.1 },
			{ t = 3.02, fx = "sound",       slot = "dive" },
			-- 5. Einschlag T = 3,28 (Landung 3,27, Speer steckt 3,28 = 1,90 + 1,38)
			{ t = 3.26, fx = "flash",       tint = C(255, 240, 200), dur = 0.08 },
			{ t = 3.28, fx = "impactframe", pattern = "ldld", hold = 0.05, dark = C(70, 50, 160), fill = C(40, 24, 110), light = C(255, 250, 235) },
			{ t = 3.28, fx = "hitstop",     dur = 0.18 },
			{ t = 3.28, fx = "sound",       slot = "impact" },
			{ t = 3.28, fx = "lightnuke",   at = "target", core = 0.2, columnAt = 0.12, height = 160, waveAt = 0.15, domeAt = 0.6, dome = 11, domeFor = 0.7, scorch = 3.6, dur = 2.5, global = true },
			{ t = 3.38, fx = "sound",       slot = "boom" },
			{ t = 3.40, fx = "sound",       slot = "bass" },
			{ t = 3.42, fx = "quake",       trauma = 1.0 },
			{ t = 3.43, fx = "ring",        at = "target", ground = true, toArena = true, radius = "fence", dur = 0.55 },
			{ t = 3.45, fx = "shards",      at = "target", arc = true, count = 14, size = 0.7, dur = 1.2, tex = "feather" },
			{ t = 3.45, fx = "dust",        at = "target", count = 40, speed = 16, dur = 1.0, tex = "stardust" },
			{ t = 3.55, fx = "sound",       slot = "rumble" },
			{ t = 3.70, fx = "quake",       trauma = 0.5 },
			{ t = 3.70, fx = "flash",       tint = C(255, 228, 170), dur = 0.12 },
			-- 6. Nachklang: Ringe fallen, Kuppel, Federregen, Pointe
			{ t = 3.80, fx = "sound",       slot = "gate" },
			{ t = 3.85, fx = "sky",         tint = C(255, 214, 150), brightness = -0.18, saturation = 0.1, dur = 1.6, fade = 0.25 },
			{ t = 4.00, fx = "snowfall",    at = "arena", noShell = true, lift = 16, size = 0.55, count = 30, dur = 1.5, tex = "feather" },
			{ t = 4.00, fx = "sound",       slot = "feathers" },
			{ t = 4.30, fx = "sound",       slot = "ring" },
			{ t = 4.35, fx = "sound",       slot = "pull" },
			{ t = 4.55, fx = "sound",       slot = "ring" },
			{ t = 4.80, fx = "sound",       slot = "ring" },
			{ t = 5.05, fx = "sound",       slot = "halo" },
			{ t = 5.65, fx = "sound",       slot = "pop" },
			{ t = 5.65, fx = "sparks",      at = "target", count = 10, dur = 0.25, stars = true },
		},
		echo = {
			{ t = 0.00, fx = "sound",       slot = "forge" },
			{ t = 0.00, fx = "pillar",      at = "target", fromSky = true, feet = true, height = 22, width = 2.4, dur = 0.5, tex = "column" },
			{ t = 0.00, fx = "ring",        at = "target", ground = true, radius = 2.2, dur = 0.3, tex = "halo" },
			{ t = 0.24, fx = "flash",       tint = C(255, 240, 200), dur = 0.06 },
			{ t = 0.26, fx = "impactframe", pattern = "l", hold = 0.05, dark = C(70, 50, 160), fill = C(40, 24, 110), light = C(255, 250, 235) },
			{ t = 0.26, fx = "hitstop",     dur = 0.06 },
			{ t = 0.26, fx = "sound",       slot = "impact" },
			{ t = 0.27, fx = "quake",       trauma = 0.4 },
			{ t = 0.27, fx = "pillar",      at = "target", feet = true, height = 60, width = 5, dur = 0.38, tex = "column", bonus = true, global = true },
			{ t = 0.28, fx = "ring",        at = "target", ground = true, toArena = true, radius = 9, dur = 0.3 },
			{ t = 0.28, fx = "ring",        at = "target", ground = true, toArena = true, radius = "fence", dur = 0.36, second = true, bonus = true },
			{ t = 0.28, fx = "shards",      at = "target", count = 8, size = 0.5, dur = 0.32, tex = "feather" },
			{ t = 0.30, fx = "sparks",      at = "target", count = 12, dur = 0.3, stars = true },
			{ t = 0.33, fx = "sound",       slot = "boom" },
		},
	},