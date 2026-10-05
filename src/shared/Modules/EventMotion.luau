--!strict
-- EventMotion.luau
-- ReplicatedStorage/Modules/EventMotion.luau
--
-- Einzige Zustaendigkeit:
--   - Wo bewegte Event-Objekte (UFO, Wespenkoenigin, abgeworfene Kisten) zu
--     einem Zeitpunkt sind — als REINE Funktion der Serverzeit.
--
-- Server und Client rechnen mit denselben Funktionen: der Server fuer Beam,
-- Abwurf-Punkte und Attacken, der Client fuer die Optik (ein PivotTo pro
-- Model und Frame). Der Server repliziert dadurch nie CFrames pro Frame, er
-- schreibt nur einmal die Startzeit als Attribut. Zeiten sind immer
-- workspace:GetServerTimeNow().

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventConfig = require(ReplicatedStorage.Config.EventConfig)

local EventMotion = {}

-- Geometrie (nur Optik, aendert kein Spielverhalten)
EventMotion.UFO_HOVER_HEIGHT   = 40     -- Scheibe ueber dem Pit-Boden
EventMotion.QUEEN_HOVER_HEIGHT = 18     -- Koenigin ueber dem Pit-Boden
EventMotion.QUEEN_BOB_HEIGHT   = 1.5
EventMotion.QUEEN_BOB_RATE     = 1.3
EventMotion.DROP_FALL_HEIGHT   = 34     -- Kiste startet so hoch ueber dem Landepunkt

local TAU = math.pi * 2

--------------------------------------------------------------------------------
-- UFO
--------------------------------------------------------------------------------

-- Waagerechter Versatz der UFO-Bahn zur Pit-Mitte, `elapsed` Sekunden nach
-- Event-Start. Lissajous 3:2: deckt das Pit ab, ohne sich staendig zu wiederholen.
function EventMotion.ufoOffset(elapsed: number): Vector3
	local cfg = EventConfig.UFO
	local x = cfg.PATROL_RADIUS_X * math.sin(TAU * elapsed / cfg.PATROL_PERIOD_X)
	local z = cfg.PATROL_RADIUS_Z * math.sin(TAU * elapsed / cfg.PATROL_PERIOD_Z + math.pi / 4)
	return Vector3.new(x, 0, z)
end

-- Bodenpunkt unter dem UFO (= Mitte des Beam-Rings) zur Serverzeit `now`.
function EventMotion.ufoGround(center: Vector3, startTime: number, now: number): Vector3
	return center + EventMotion.ufoOffset(now - startTime)
end

--------------------------------------------------------------------------------
-- Wespenkoenigin
--------------------------------------------------------------------------------

-- Winkel auf ihrer Kreisbahn. Ab `phase2At` fliegt sie schneller; der Winkel
-- laeuft dabei stetig weiter (kein Sprung beim Phasenwechsel).
function EventMotion.queenAngle(startTime: number, now: number, phase2At: number?): number
	local cfg = EventConfig.WASP_QUEEN
	local t = math.max(0, now - startTime)
	if phase2At and now > phase2At then
		local before = math.max(0, phase2At - startTime)
		return TAU * (before / cfg.ORBIT_PERIOD + (now - phase2At) / cfg.ORBIT_PERIOD_PHASE2)
	end
	return TAU * t / cfg.ORBIT_PERIOD
end

-- Bodenpunkt unter der Koenigin.
function EventMotion.queenGround(center: Vector3, startTime: number, now: number, phase2At: number?): Vector3
	local angle = EventMotion.queenAngle(startTime, now, phase2At)
	local r = EventConfig.WASP_QUEEN.ORBIT_RADIUS
	return center + Vector3.new(math.cos(angle) * r, 0, math.sin(angle) * r)
end

-- Volle Pose der Koenigin (schwebt, wippt, schaut in Flugrichtung).
function EventMotion.queenPose(center: Vector3, startTime: number, now: number, phase2At: number?): CFrame
	local ground = EventMotion.queenGround(center, startTime, now, phase2At)
	local ahead  = EventMotion.queenGround(center, startTime, now + 0.2, phase2At)
	local bob = math.sin((now - startTime) * EventMotion.QUEEN_BOB_RATE * TAU) * EventMotion.QUEEN_BOB_HEIGHT
	local pos = ground + Vector3.new(0, EventMotion.QUEEN_HOVER_HEIGHT + bob, 0)
	local dir = Vector3.new(ahead.X - ground.X, 0, ahead.Z - ground.Z)
	if dir.Magnitude < 1e-3 then
		return CFrame.new(pos)
	end
	return CFrame.lookAt(pos, pos + dir)
end

--------------------------------------------------------------------------------
-- Abgeworfene Kiste
--------------------------------------------------------------------------------

-- Hoehe der Kiste ueber ihrem Landepunkt: faellt zwischen `releaseAt` und
-- `landAt` sanft (Fallschirm) von DROP_FALL_HEIGHT auf 0.
function EventMotion.dropHeight(releaseAt: number, landAt: number, now: number): number
	if now >= landAt then return 0 end
	local span = math.max(0.05, landAt - releaseAt)
	local k = math.clamp((now - releaseAt) / span, 0, 1)
	-- erst schnell (Abwurf), dann gebremst (Schirm offen)
	local eased = 1 - (1 - k) * (1 - k)
	return EventMotion.DROP_FALL_HEIGHT * (1 - eased)
end

return EventMotion
