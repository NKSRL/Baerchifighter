--!strict
-- GuideArrowRules.luau
-- ReplicatedStorage/Modules/GuideArrowRules.luau
--
-- Reine Rechnung (ohne Roblox) fuer die Tutorial-Pfeile aus Partikeln:
-- statt eines Beams fliegen Pfeil-Partikel vom Spieler zum Ziel.
--
-- Methode (Wunsch 21.10.):
--   - Beschleunigung je Achse = Abstand in Studs / 10
--     (28 Studs nach links -> X = -2.8; vorwaerts ist -Z)
--   - Drag = Abstand / 10 / DRAG_DIVISOR (urspruenglich 10: 28 Studs -> 0.28;
--     jetzt 24, damit die Pfeile schneller sind als der laufende Spieler)
--   - Speed 24. Der Ausgang wandert mit dem Spieler: laeuft er aufs Ziel zu,
--     ruecken die Pfeile zusammen (Abstand = (Speed - Laufgeschwindigkeit) / Rate).
--     Darum wird die Rate nachgefuehrt: Rate = (Speed - Laufgeschwindigkeit) / Abstand.
--     So bleibt der Abstand der Pfeile immer gleich (0.8 normal, 1.6 schwaches Geraet).
--     Ausgesendet wird per Emit() mit eigenem Zaehler (Rate des Emitters bleibt 0).
-- Beschleunigung / Drag = Endgeschwindigkeit = Speed, also kommen die Pfeile
-- bei jedem Abstand gleich schnell am Ziel an.

local GuideArrowRules = {}

GuideArrowRules.SPEED = 24       -- Startspeed = Endgeschwindigkeit; Spieler laeuft 16, man holt die Pfeile nicht ein
-- Abstand der Pfeile in Studs. Die Rate wird daraus berechnet (siehe rate), damit der
-- Abstand gleich bleibt, egal ob der Spieler steht oder laeuft.
GuideArrowRules.SPACING_HIGH = 0.8    -- normal: Pfeilkette, die Pfeile beruehren sich leicht (bei 0.35 wird sie ein glatter Balken)
GuideArrowRules.SPACING_LOW = 1.6     -- Option "Schwaches Geraet": deutlich weniger Pfeile
GuideArrowRules.MIN_RATE = 4
GuideArrowRules.MAX_RATE = 60
GuideArrowRules.MIN_RELATIVE_SPEED = 4   -- Untergrenze fuer Speed minus Laufgeschwindigkeit
GuideArrowRules.ACCEL_DIVISOR = 10
GuideArrowRules.DRAG_DIVISOR = 24 -- zweite Teilung fuer den Drag; = Endgeschwindigkeit (war 10, jetzt schneller)
-- Naeher als das gibt es keinen Pfeil (man steht schon am Ziel).
GuideArrowRules.HIDE_WITHIN = 6
-- Lebensdauer in Sekunden (Abstand / Speed), damit Pfeile am Ziel enden.
GuideArrowRules.MIN_LIFETIME = 0.6
GuideArrowRules.MAX_LIFETIME = 8

-- lowEnd: Option "Schwaches Geraet" (oder niedrige Roblox-Grafikstufe)
-- closingSpeed: Geschwindigkeit des Ausgangs in Richtung Ziel in Studs/s (0 = Spieler steht)
function GuideArrowRules.rate(lowEnd: boolean, closingSpeed: number?): number
	local spacing = if lowEnd then GuideArrowRules.SPACING_LOW else GuideArrowRules.SPACING_HIGH
	local relative = math.max(GuideArrowRules.SPEED - (closingSpeed or 0), GuideArrowRules.MIN_RELATIVE_SPEED)
	return math.clamp(relative / spacing, GuideArrowRules.MIN_RATE, GuideArrowRules.MAX_RATE)
end

export type Motion = {
	accelX: number,
	accelY: number,
	accelZ: number,
	drag: number,
	lifetime: number,
	distance: number,
	visible: boolean,
}

-- dx/dz: Versatz zum Ziel in Welt-Studs (X: rechts +, links -; Z: vorwaerts -).
-- Die Aufteilung "so viele Studs nach vorne, so viele zur Seite" ergibt
-- genau diesen Welt-Versatz, auch wenn der Spieler sich dreht.
-- Y bleibt 0: die Pfeile fliegen flach ueber dem Boden.
function GuideArrowRules.motion(dx: number, dz: number): Motion
	local distance = math.sqrt(dx * dx + dz * dz)
	local ax = dx / GuideArrowRules.ACCEL_DIVISOR
	local az = dz / GuideArrowRules.ACCEL_DIVISOR
	local drag = distance / GuideArrowRules.ACCEL_DIVISOR / GuideArrowRules.DRAG_DIVISOR
	local life = math.clamp(distance / GuideArrowRules.SPEED,
		GuideArrowRules.MIN_LIFETIME, GuideArrowRules.MAX_LIFETIME)
	return {
		accelX = ax, accelY = 0, accelZ = az,
		drag = drag, lifetime = life, distance = distance,
		visible = distance > GuideArrowRules.HIDE_WITHIN,
	}
end

return GuideArrowRules
