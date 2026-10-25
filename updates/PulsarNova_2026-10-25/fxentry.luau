    PulsarNova = {
        -- 25.10.2026 Pulsar-Nova (Pulsar-Baerchi, ersetzt PulsarPulse als
        -- defaultSkill): neue, bessere Fassung des Blender-Prototyps "Pulsstoss"
        -- (22.10., Vorbild-Video: Ring -> Sternbruch -> Kugel -> Impact-Frames
        -- -> Feuerkuppel -> Weissblende). Hauptmotiv: der Baerchi wird zum
        -- Pulsar - ein Leuchtturm aus Licht - und schlaegt als Neutronenstern
        -- ein ("Tickt wie eine Uhr. Jeder Schlag lauter."). Farben: Cyan aus
        -- Visier und Duesenflammen, Feuer-Orange, pinker Saum wie im Vorbild.
        -- Aufladen (0 .. 1,1): Welt kuehl-dunkel (Besitzer), Sterne; Bodenblitz,
        --   ein Lichtpunkt zeichnet den Ring um ihn (0 .. 0,35); er duckt sich
        --   (0,38), das Jetpack zuendet, er steigt mit Drehung auf (0,62 ..
        --   1,1), der Ring hebt mit ab und wird sein Orbit-Ring.
        -- Leuchtturm (1,05 .. 2,05): Lichtkegel aus Visier und Jetpack, er
        --   kreist immer schneller; der Visier-Kegel fegt bei 1,2 / 1,48 / 1,7 /
        --   1,86 / 2,01 durch die Kamera jedes Clients - Blitz + Ticken, jedes
        --   lauter (Besitzer: Bildschirm-Schleier). Kamera tief von unten
        --   (1,05 .. 3,55).
        -- Kollaps (2,05): Kegel und Ring stuerzen in ihn, er wird zum weiss-
        --   gluehenden Neutronenstern, Anime-Sternbruch, Funken; Pulse 2,15 /
        --   2,3; Stille 2,25 .. 2,45.
        -- Schlag (2,45): er schiesst als Komet in den Gegner (Schweif cyan ->
        --   orange, Nachbilder).
        -- Einschlag (2,9 = impactAt; Flug 2,45 + 0,43 = 2,88): kleine Kuppel,
        --   Impact-Frames (nur Besitzer: invertiert mit Silhouetten + Speed-
        --   lines, dann Weiss), Feuerkuppel (Radius 8) mit laufenden Flammen-
        --   baendern, Loechern, pinkem Saum, Flammenkranz, Truemmern;
        --   Bodenwellen bis zum Zaun; Pulse 3,45 / 3,95.
        -- Weissblende (4,35): die Kuppel flammt auf und vergeht (Besitzer:
        --   Weiss -> Rosa bis 5,46).
        -- Nachklang: er rollt sich aus dem Krater auf (4,42), Rueckwaerts-Salto
        --   heim (4,58 .. 5,3), der Ring blitzt um seine Fuesse; Flammen
        --   zuengeln am Gegner (Brand = DoT). Alles weg bis 5,65.
        -- Kein Bonus: DoT meldet nie `bonus`.
        tier = 4, duration = 5.7, color = C(70, 228, 255), color2 = C(255, 138, 40),
        sounds = { charge = "bass", ignite = "rocket", tick = "ping", collapse = "glass", pulse = "rumble",
            strike = "lunge", impact = "boom", after = "thunder", flare = "flash", home = "whoosh", land = "ping" },
        pitch = 1.0,
        impactAt = 2.9,
        steps = {
            -- 1. Aufladen
            { t = 0.00, fx = "sky",        tint = C(200, 236, 255), brightness = -0.2, saturation = 0.05, dur = 5.3, fade = 0.6 },
            { t = 0.00, fx = "starfield",  count = 40, dur = 5.0, ownerOnly = true, extra = true },
            { t = 0.00, fx = "pulsar",     ring = 3.6, draw = 0.35, crouchAt = 0.38, crouch = 0.24, rise = 0.48, height = 5.5,
                spins = 1, grow = 1.15, beamAt = 1.05, beamLen = 34, ticks = { 1.2, 1.48, 1.7, 1.86, 2.01 },
                collapseAt = 2.05, pulseAt = { 2.15, 2.3 }, windAt = 2.33, launchAt = 2.45, fly = 0.43,
                emergeAt = 4.42, emerge = 0.16, back = 0.72, settle = 0.35 },
            { t = 0.00, fx = "sound",      slot = "charge" },
            { t = 0.05, fx = "shake",      power = 0.15, dur = 0.2 },
            { t = 0.60, fx = "sound",      slot = "ignite" },
            { t = 0.62, fx = "shake",      power = 0.22, dur = 0.3 },
            -- 2. Leuchtturm: jeder Durchgang durch die Kamera blitzt und tickt
            -- (der Blitz selbst kommt aus `pulsar`), jeder lauter
            { t = 1.05, fx = "cinematic",  dur = 2.5, style = "pulsar" },
            { t = 1.20, fx = "sound",      slot = "tick" },
            { t = 1.20, fx = "shake",      power = 0.1, dur = 0.12 },
            { t = 1.48, fx = "sound",      slot = "tick" },
            { t = 1.48, fx = "shake",      power = 0.15, dur = 0.12 },
            { t = 1.70, fx = "sound",      slot = "tick" },
            { t = 1.70, fx = "shake",      power = 0.2, dur = 0.12 },
            { t = 1.86, fx = "sound",      slot = "tick" },
            { t = 1.86, fx = "shake",      power = 0.26, dur = 0.12 },
            { t = 2.01, fx = "sound",      slot = "tick" },
            { t = 2.01, fx = "shake",      power = 0.32, dur = 0.12 },
            -- 3. Kollaps zum Neutronenstern, Spannung
            { t = 2.05, fx = "sound",      slot = "collapse" },
            { t = 2.05, fx = "shake",      power = 0.45, dur = 0.25 },
            { t = 2.12, fx = "sound",      slot = "pulse" },
            { t = 2.25, fx = "silence",    level = 0.12, dur = 0.2 },
            -- 4. Schlag
            { t = 2.45, fx = "sound",      slot = "strike" },
            { t = 2.45, fx = "shake",      power = 0.4, dur = 0.3 },
            -- 5. Einschlag: Impact-Frames, Feuerkuppel
            { t = 2.90, fx = "firedome",   at = "target", radius = 8, mini = 3.2, miniFor = 0.07, grow = 0.12,
                pulseAt = { 0.55, 1.05 }, flareAt = 1.45, fade = 0.3, burn = 0.75, holes = 6, skirt = 18, chunks = 10 },
            { t = 2.93, fx = "novaframe",  invert = 0.045, white = 0.08, fade = 0.16, lines = 46 },
            { t = 2.90, fx = "sound",      slot = "impact" },
            { t = 2.90, fx = "shake",      power = 1.4, dur = 0.8 },
            { t = 2.92, fx = "ring",       at = "target", ground = true, toArena = true, radius = "fence", dur = 0.9, tex = "shockring" },
            { t = 3.00, fx = "ring",       at = "target", ground = true, toArena = true, radius = "fence", dur = 0.9, second = true, tex = "shockring" },
            { t = 3.00, fx = "sound",      slot = "after" },
            { t = 3.05, fx = "dust",       at = "target", count = 36, speed = 15, dur = 1.3, tex = "stardust", extra = true },
            -- 6. Die Kuppel pulst wie der Pulsar (rosa Schleier kommt aus `firedome`)
            { t = 3.45, fx = "sound",      slot = "pulse" },
            { t = 3.45, fx = "shake",      power = 0.3, dur = 0.25 },
            { t = 3.95, fx = "sound",      slot = "pulse" },
            { t = 3.95, fx = "shake",      power = 0.38, dur = 0.25 },
            -- 7. Weissblende (aus `firedome`) und Nachklang
            { t = 4.35, fx = "sound",      slot = "flare" },
            { t = 4.35, fx = "shake",      power = 0.6, dur = 0.4 },
            { t = 4.58, fx = "sound",      slot = "home" },
            { t = 5.30, fx = "sound",      slot = "land" },
        },
        -- Echo (0,65 s): ein kleiner Neutronenstern schiesst in den Gegner
        -- (Treffer 0,26 = TIERS[4].echo * 0,4), eine kleine Kuppel ploppt auf,
        -- Bodenring.
        echo = {
            { t = 0.00, fx = "novabolt",   at = "target", fly = 0.25, radius = 2.6, life = 0.34, size = 0.95 },
            { t = 0.00, fx = "sound",      slot = "strike" },
            { t = 0.25, fx = "sound",      slot = "impact" },
            { t = 0.27, fx = "ring",       at = "target", ground = true, radius = 8, dur = 0.35, second = true, tex = "shockring" },
        },
    },
