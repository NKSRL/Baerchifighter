	-- ------------------------------------------------------------------
	-- 25.10.2026 Bauchrutscher (PolarSlide, Eisbaer, Uncommon, Stufe 2, ohne
	-- Kamerafahrt). Werte wie Eisschlag (balance-neutral), neue Show.
	-- Takte: 0,0 Eisbahn gefriert (0,55 s), Ducken | 0,55 Sprung auf den Bauch |
	-- 0,75-1,45 Rutschen mit Schneefahne und Pirouette | 1,5 Rums: Gegner im
	-- Eisblock (= Treffer, Stun) | 1,5-2,1 Purzeln heim, 2,25 Schuetteln |
	-- 2,35 Eisblock zerspringt | 2,8 Ende. Echo: kleiner Eisblock, zerspringt.
	-- ------------------------------------------------------------------
	PolarSlide = {
		tier = 2, duration = 2.8, impactAt = 1.5,
		color = Color3.fromRGB(160, 215, 255), color2 = Color3.fromRGB(70, 130, 210),
		pitch = 1.1,
		sounds = { charge = "whoosh", slide = "rumble", impact = "boom", shatter = "glass" },
		steps = {
			{ t = 0,    fx = "sound", slot = "charge" },
			{ t = 0,    fx = "icepath", draw = 0.55, width = 2.4, plates = 6, spikes = 8, slideAt = 0.75, slideEnd = 1.5, meltAt = 2.25, dur = 2.75 },
			{ t = 0,    fx = "moves", hold = 0.04, outline = Color3.fromRGB(70, 130, 210), keys = {
				{ t = 0.30, pitch = 0.04, scale = 0.93, ease = "out" },
				{ t = 0.55, dy = 0.9, dz = 1.3, pitch = -0.2, scale = 1, ease = "out", burst = 8 },
				{ t = 0.75, dz = 2.4, dy = -0.35, pitch = -0.22, ease = "in", smoke = 10 },
				{ t = 1.45, at = "land", dz = 0.3, dy = -0.35, pitch = -0.22, yaw = 1, ease = "in", trail = true },
				{ t = 1.50, at = "land", dz = -0.3, dy = -0.1, pitch = -0.16, yaw = 1, ease = "out", burst = 24, smoke = 14 },
				{ t = 2.10, at = "home", pitch = 0, yaw = 1, roll = 1, arc = 2.6, ease = "inout" },
				{ t = 2.25, at = "home", scale = 0.94, ease = "out", smoke = 8 },
				{ t = 2.45, at = "home", yaw = 1.08, scale = 1.02 },
				{ t = 2.62, at = "home", yaw = 0.96 },
				{ t = 2.72, at = "home", yaw = 1, scale = 1 },
			} },
			{ t = 0.75, fx = "sound", slot = "slide" },
			{ t = 1.5,  fx = "sound", slot = "impact" },
			{ t = 1.5,  fx = "iceblock", at = "target", appear = 0.12, breakAt = 0.85, dur = 1.25 },
			{ t = 1.5,  fx = "shake", power = 0.25, dur = 0.2 },
			{ t = 2.35, fx = "sound", slot = "shatter" },
		},
		echo = {
			{ t = 0,    fx = "sound", slot = "impact" },
			{ t = 0.06, fx = "iceblock", at = "target", appear = 0.06, breakAt = 0.26, dur = 0.38, small = true },
			{ t = 0.32, fx = "sound", slot = "shatter" },
		},
	},

	-- ------------------------------------------------------------------
	-- 25.10.2026 Tigersprung (TigerPounce, Tigerbaer, Uncommon, Stufe 2, ohne
	-- Kamerafahrt). Werte wie Feuerbiss (DoT), neue Show.
	-- Takte: 0,0-0,5 Anschleichen (Ducken, Wippen) | 0,5-0,95 Sprung im Bogen vor
	-- den Gegner | 1,0 / 1,14 / 1,28 drei Krallenhiebe (1,0 = Treffer), die
	-- Kratzer schwelen (= Brand) | 1,65 Pose | 1,65-2,3 Rueckwaerts-Salto heim |
	-- 2,6 Ende. Echo: ein Krallenhieb.
	-- ------------------------------------------------------------------
	TigerPounce = {
		tier = 2, duration = 2.6, impactAt = 1.0,
		color = Color3.fromRGB(255, 140, 40), color2 = Color3.fromRGB(255, 215, 90),
		pitch = 1.1,
		sounds = { charge = "lunge", strike = "slash", impact = "snap" },
		steps = {
			{ t = 0,    fx = "moves", outline = Color3.fromRGB(255, 120, 30), hold = 0.04, keys = {
				{ t = 0.30, dz = -0.3, scale = 0.9, ease = "out" },
				{ t = 0.42, dz = -0.25, dy = 0.08, scale = 0.92 },
				{ t = 0.50, dz = -0.3, dy = 0, scale = 0.9, ease = "in" },
				{ t = 0.95, at = "land", dz = -0.3, dxc = -1.0, dy = 0.5, pitch = -0.12, scale = 1.08, arc = 3.2, ease = "in", trail = true },
				{ t = 1.02, at = "land", dz = -0.05, dxc = -1.0, dy = 0, pitch = -0.04, scale = 1, ease = "out", burst = 18, smoke = 8 },
				{ t = 1.14, at = "land", dz = -0.05, dxc = -1.0, roll = -0.03, yaw = 0.03 },
				{ t = 1.28, at = "land", dz = -0.05, dxc = -1.0, roll = 0.03, yaw = -0.03 },
				{ t = 1.42, at = "land", dz = -0.05, dxc = -1.0, roll = 0, yaw = 0 },
				{ t = 1.65, at = "land", dz = -0.1, dxc = -1.0, pitch = 0.06, scale = 1.04, ease = "out" },
				{ t = 2.30, at = "home", pitch = 1.06, scale = 1, arc = 3.0, ease = "inout" },
				{ t = 2.45, at = "home", pitch = 1.0, scale = 0.96, ease = "out", smoke = 6 },
				{ t = 2.56, at = "home", scale = 1 },
			} },
			{ t = 0.5,  fx = "sound", slot = "charge" },
			{ t = 1.0,  fx = "clawmarks", at = "target", count = 3, every = 0.14, claws = 3, len = 2.6, draw = 0.07, fade = 0.3, dur = 1.55 },
			{ t = 1.0,  fx = "sound", slot = "strike" },
			{ t = 1.14, fx = "sound", slot = "strike" },
			{ t = 1.28, fx = "sound", slot = "strike" },
			{ t = 1.28, fx = "sound", slot = "impact" },
			{ t = 1.0,  fx = "shake", power = 0.2, dur = 0.3 },
		},
		echo = {
			{ t = 0.10, fx = "clawmarks", at = "target", count = 1, claws = 3, len = 2.2, draw = 0.06, fade = 0.12, dur = 0.34 },
			{ t = 0.10, fx = "sound", slot = "strike" },
		},
	},

	-- ------------------------------------------------------------------
	-- 25.10.2026 Brennglas (MagnifierBurn, Detektiv, Rare, Stufe 2, ohne
	-- Kamerafahrt). Werte wie Splitterhagel (2.2x + 14), neue Show.
	-- Takte: 0,0-0,65 Pfotenspuren erscheinen, 0,25-1,0 der Detektiv huepft ihnen
	-- in drei Spruengen nach | 1,1 die Lupe waechst aus seiner Pfote | 1,35
	-- Lichtstrahl, Brennpunkt sucht (Rauch, Gluehen) | 2,1 Flammenstoss (=
	-- Treffer), Spuren blitzen, "Aha"-Hopser | 2,45 Hut ziehen | 2,65-2,88
	-- Hopser heim | 3,0 Ende. Echo: kleine Lupe, kurzer Strahl, Flammenstoss.
	-- ------------------------------------------------------------------
	MagnifierBurn = {
		tier = 2, duration = 3.0, impactAt = 2.1,
		color = Color3.fromRGB(255, 214, 110), color2 = Color3.fromRGB(255, 120, 50),
		pitch = 1.0,
		sounds = { charge = "ping", strike = "flash", impact = "boom", aha = "ping" },
		steps = {
			{ t = 0,    fx = "sound", slot = "charge" },
			{ t = 0,    fx = "pawprints", count = 7, every = 0.09, sway = 0.38, gap = 2.4, pulseAt = 2.1, dur = 2.9 },
			{ t = 0,    fx = "moves", hat = "acc_dome,acc_peak,acc_hatband,acc_knob", hold = 0.05, gap = 2.4, keys = {
				{ t = 0.25, pitch = -0.03, scale = 0.95, ease = "out" },
				{ t = 0.50, u = 0.34, h = 0, dx = 0.3, arc = 0.9, ease = "out", scale = 1 },
				{ t = 0.75, u = 0.67, h = 0, dx = -0.3, arc = 0.9 },
				{ t = 1.00, u = 1.0, h = 0, dx = 0, arc = 0.9, smoke = 5 },
				{ t = 1.15, at = "land", pitch = 0.02, scale = 0.97, ease = "out" },
				{ t = 1.40, at = "land", pitch = 0.06, dy = 0.05, scale = 1 },
				{ t = 2.05, at = "land", pitch = 0.06, roll = 0.01 },
				{ t = 2.12, at = "land", pitch = 0.1, dy = 0.35, ease = "out", burst = 10 },
				{ t = 2.28, at = "land", pitch = 0.04, dy = 0, ease = "in" },
				{ t = 2.45, at = "land", pitch = 0.06, tip = 1, ease = "out" },
				{ t = 2.65, at = "land", pitch = 0, tip = 0 },
				{ t = 2.88, at = "home", arc = 1.8, ease = "inout" },
				{ t = 2.95, at = "home", scale = 0.98 },
			} },
			{ t = 1.1,  fx = "lensbeam", lens = 1.1, appear = 0.25, beamAt = 0.25, burnAt = 1.0, away = 0.25, dur = 1.5 },
			{ t = 1.35, fx = "sound", slot = "strike" },
			{ t = 2.05, fx = "sound", slot = "aha" },
			{ t = 2.1,  fx = "sound", slot = "impact" },
			{ t = 2.1,  fx = "shake", power = 0.2, dur = 0.2 },
		},
		echo = {
			{ t = 0,    fx = "lensbeam", lens = 0.7, appear = 0.05, beamAt = 0.05, burnAt = 0.18, away = 0.14, dur = 0.42, small = true },
			{ t = 0.18, fx = "sound", slot = "impact" },
		},
	},

	-- ------------------------------------------------------------------
	-- 25.10.2026 Bass-Drop (BassDrop, Zucker-DJ, Rare, Stufe 2, ohne
	-- Kamerafahrt). Werte wie Zuckersturm (AoE), neue Show.
	-- Takte: 0,0 Schallplatte ploppt unter dem DJ auf, Equalizer-Balken rund um
	-- die Arena | 0,5 / 1,0 / 1,5 drei Beats (Hopser, Bodenring, Balken zucken,
	-- Kopfhoerer leuchten) | 1,55-2,0 Build-up (Ducken, Balken steigen, Platte
	-- rast, Stille) | 2,0 DROP (= Treffer): Bass, Schockwelle bis zum Zaun,
	-- Sprung mit Drehung, Streusel am Gegner | 2,6 Landung, 2,8 Pose | 3,0 Ende.
	-- Echo: Bodenring + Welle + Bass.
	-- ------------------------------------------------------------------
	BassDrop = {
		tier = 2, duration = 3.0, impactAt = 2.0,
		color = Color3.fromRGB(255, 160, 211), color2 = Color3.fromRGB(218, 196, 255),
		pitch = 1.0,
		sounds = { beat = "snap", rise = "whoosh", drop = "bass", impact = "boom" },
		steps = {
			{ t = 0,    fx = "djset", beats = { 0.5, 1.0, 1.5 }, buildAt = 1.55, dropAt = 2.0, dur = 2.95, bars = 14, radius = 7.5, disc = 4.6 },
			{ t = 0,    fx = "moves", keys = {
				{ t = 0.20, dy = 0.15, ease = "out" },
				{ t = 0.50, dy = 0.45, ease = "out" },
				{ t = 0.70, dy = 0.15, ease = "in" },
				{ t = 1.00, dy = 0.45, roll = 0.02, ease = "out" },
				{ t = 1.20, dy = 0.15, ease = "in" },
				{ t = 1.50, dy = 0.45, roll = -0.02, ease = "out" },
				{ t = 1.70, dy = 0.15, ease = "in" },
				{ t = 1.95, dy = 0.1, scale = 0.9, pitch = 0.05, roll = 0 },
				{ t = 2.00, dy = 0.3, scale = 0.95, ease = "out" },
				{ t = 2.32, dy = 1.7, scale = 1.1, roll = 0.5, pitch = 0, ease = "out", burst = 30 },
				{ t = 2.60, dy = 0.15, roll = 1, scale = 0.94, ease = "in", smoke = 12 },
				{ t = 2.80, dy = 0.15, scale = 1, pitch = -0.04, yaw = 0.06, ease = "out" },
				{ t = 2.90, dy = 0.15, yaw = 0.06 },
			} },
			{ t = 0.5,  fx = "sound", slot = "beat" },
			{ t = 1.0,  fx = "sound", slot = "beat" },
			{ t = 1.5,  fx = "sound", slot = "beat" },
			{ t = 1.55, fx = "sound", slot = "rise" },
			{ t = 1.85, fx = "silence", dur = 0.15, level = 0.15 },
			{ t = 2.0,  fx = "sound", slot = "drop" },
			{ t = 2.0,  fx = "sound", slot = "impact" },
			{ t = 2.0,  fx = "shake", power = 0.5, dur = 0.35 },
			{ t = 2.0,  fx = "flash", dur = 0.12, tint = Color3.fromRGB(255, 200, 235) },
		},
		echo = {
			{ t = 0.02, fx = "ring", at = "self", ground = true, radius = 6, dur = 0.3 },
			{ t = 0.12, fx = "wave", at = "self", radius = 8, dur = 0.3 },
			{ t = 0.15, fx = "sound", slot = "drop" },
			{ t = 0.18, fx = "sparks", at = "target", count = 10, dur = 0.26 },
		},
	},
	-- ------------------------------------------------------------------
	-- 25.10.2026 Muenzregen (CoinShower, Goldener Grizzly, Epic, Stufe 3, ohne
	-- Kamerafahrt). Werte wie Gold Rush (Drain 25%), neue Show.
	-- Takte: 0,0-0,62 Aufbaeumen | 0,75 Stampfer: Bodenring, Gold-Riss laeuft zum
	-- Gegner (0,8-1,4) | 1,6 Muenzen spritzen aus dem Gegner (= Treffer, Drain)
	-- und fliegen bis 3,0 im Bogen zum Grizzly, der Haufen waechst, er wird
	-- groesser, Medaille blitzt | 3,0-3,45 Haufen sinkt, Pose | 3,6 Ende.
	-- Echo: 6 Muenzen, kleiner Haufen.
	-- ------------------------------------------------------------------
	CoinShower = {
		tier = 3, duration = 3.6, impactAt = 1.6,
		color = Color3.fromRGB(255, 200, 50), color2 = Color3.fromRGB(190, 150, 60),
		pitch = 0.95,
		sounds = { charge = "rumble", stomp = "boom", strike = "ping", impact = "glass" },
		steps = {
			{ t = 0,    fx = "sound", slot = "charge" },
			{ t = 0,    fx = "moves", hold = 0.05, outline = Color3.fromRGB(255, 170, 40), keys = {
				{ t = 0.45, pitch = 0.12, dy = 0.3, scale = 1.06, ease = "out" },
				{ t = 0.62, pitch = 0.15, dy = 0.4, scale = 1.08 },
				{ t = 0.75, pitch = -0.02, dy = 0, scale = 1.0, ease = "in", burst = 20, smoke = 16 },
				{ t = 0.95, pitch = 0, scale = 0.98, ease = "out" },
				{ t = 1.60, pitch = 0.02, scale = 1.0 },
				{ t = 2.30, pitch = 0.04, scale = 1.08, ease = "out" },
				{ t = 2.75, pitch = 0.06, scale = 1.14, ease = "out", burst = 12 },
				{ t = 3.10, pitch = 0, yaw = 0.05, scale = 1.14 },
				{ t = 3.35, yaw = -0.02, scale = 1.06 },
				{ t = 3.55, yaw = 0, scale = 1 },
			} },
			{ t = 0.75, fx = "sound", slot = "stomp" },
			{ t = 0.75, fx = "shake", power = 0.35, dur = 0.3 },
			{ t = 0.75, fx = "ring", at = "self", ground = true, radius = 5, dur = 0.5 },
			{ t = 0.8,  fx = "crack", dur = 0.6, linger = 2.2, segments = 7, amp = 0.8, width = 0.3 },
			{ t = 1.6,  fx = "sound", slot = "impact" },
			{ t = 1.6,  fx = "coinshower", count = 18, burstAt = 0, rise = 0.28, fly = 0.5, every = 0.035, dur = 2.0 },
			{ t = 1.7,  fx = "sound", slot = "strike" },
			{ t = 2.1,  fx = "sound", slot = "strike" },
			{ t = 1.6,  fx = "rise", at = "target", count = 10, dur = 0.8, toSelf = true, extra = true },
		},
		echo = {
			{ t = 0,    fx = "sound", slot = "impact" },
			{ t = 0.02, fx = "coinshower", count = 6, burstAt = 0, rise = 0.12, fly = 0.25, every = 0.03, dur = 0.52, small = true },
		},
	},

	-- ------------------------------------------------------------------
	-- 25.10.2026 Shuriken-Sturm (ShurikenStorm, Ninja, Epic, Stufe 3, ohne
	-- Kamerafahrt). Werte wie Schwarzes Loch (AoE 2.4x + 25), neue Show.
	-- Takte: 0,45 Rauch-Puff, der Ninja ist weg | 0,5 / 0,7 / 0,9 drei Schatten-
	-- klone erscheinen um den Gegner | 1,2 / 1,4 / 1,6 Shuriken-Wuerfe, bohren
	-- sich um den Gegner in den Boden | 2,0 alle Klone stuermen durch ihn (Puffs)
	-- | 2,27 der echte Ninja erscheint hinter dem Gegner, 2,3 Katana-Schnitt
	-- (= Treffer), Shuriken blitzen | 3,1 Puff, 3,5 Puff zu Hause | 3,8 Ende.
	-- Echo: ein Shuriken von self in den Boden vor dem Gegner.
	-- ------------------------------------------------------------------
	ShurikenStorm = {
		tier = 3, duration = 3.8, impactAt = 2.3,
		color = Color3.fromRGB(231, 63, 75), color2 = Color3.fromRGB(40, 32, 70),
		pitch = 1.05,
		sounds = { charge = "whoosh", throw = "snap", dash = "lunge", strike = "slash", impact = "hit" },
		steps = {
			{ t = 0,    fx = "moves", hold = 0.05, hat = "acc_blade,acc_grip,acc_guard", outline = Color3.fromRGB(231, 63, 75), keys = {
				{ t = 0.30, scale = 0.95, pitch = 0.02, ease = "out" },
				{ t = 0.45, scale = 0.9, dy = 0.1, smoke = 22, hidden = true },
				{ t = 2.24, at = "target", dz = 1.7, yaw = 0.5, scale = 1, dy = 0, hidden = true },
				{ t = 2.27, at = "target", dz = 1.7, yaw = 0.5, hidden = false, smoke = 18, burst = 10 },
				{ t = 2.34, at = "target", dz = 1.7, yaw = 0.5, roll = -0.05, pitch = -0.04, tip = 1, ease = "out" },
				{ t = 2.70, at = "target", dz = 1.7, yaw = 0.5, roll = 0, pitch = 0, tip = 1 },
				{ t = 2.95, at = "target", dz = 1.7, yaw = 0.5, tip = 0 },
				{ t = 3.10, at = "target", dz = 1.7, yaw = 0.5, hidden = true, smoke = 16 },
				{ t = 3.50, at = "home", yaw = 0, hidden = false, smoke = 14 },
				{ t = 3.60, at = "home", scale = 0.96, ease = "out" },
				{ t = 3.72, at = "home", scale = 1 },
			} },
			{ t = 0.45, fx = "sound", slot = "charge" },
			{ t = 0.5,  fx = "ninjaclones", count = 3, radius = 4.5, appearAt = 0, every = 0.2, throw... (truncated)