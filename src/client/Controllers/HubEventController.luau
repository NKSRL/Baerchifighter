--!strict
-- HubEventController.luau
-- StarterPlayerScripts/Controllers/HubEventController.luau
--
-- Einzige Zustaendigkeit:
--   - Die Hauptinsel zeigt den Event-Zustand (Paket C, "Welt aufwerten"):
--     Wimpelkette und Lichter am Event-Pit (Ruhe / startet bald / laeuft),
--     kreisende Wespen und Puls am Wespen-Nest (ruhig / Boss bald oder da)
--
-- Der Client erfindet keine Event-Logik. Er liest, was der Server ohnehin in
-- die Welt schreibt:
--   * Event laeuft     = der Ring des Event-Pits ist Neon (MapService.setEventPitTheme),
--                        seine Farbe ist die Event-Farbe
--   * Restzeit         = die Countdown-Tafel ueber dem Pit ("in 0:45"), jede
--                        Sekunde vom Server beschrieben (EventService.tick)
--   * Boss bald/da     = das Wespen-Nest leuchtet (MapService.setWaspNest,
--                        WASP_NEST.glowSeconds vor dem Boss und waehrenddessen)
-- Warum nicht EventPhaseChanged: die Join-Meldung landet in der Warteschlange
-- und geht an den ersten Zuhoerer (PetBar), dieser Controller kaeme zu spaet.
--
-- PERFORMANCE: EIN Takt (20x pro Sekunde); die Wimpel bewegt EIN
-- workspace:BulkMoveTo, nur wenn der Pit-Rahmen in Sichtweite ist. Keine
-- Lichter, kein Emitter. Puls weit unter 3 Hz.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local SoundService      = game:GetService("SoundService")

local MapConfig     = require(ReplicatedStorage.Config.MapConfig)
local WorldFXConfig = require(ReplicatedStorage.Config.WorldFXConfig)
local FeatureFlags  = require(ReplicatedStorage.Config.FeatureFlags)
local MapLayout     = require(ReplicatedStorage.Modules.MapLayout)

local WorldFXKit = require(script.Parent.WorldFXKit)
-- Paket G: Event-Start als Welt-Moment (Krone blinkt, Bienen ziehen los)
local WorldMomentController = require(script.Parent.WorldMomentController)

local HubEventController = {}

local TICK = 0.05
local TAU = math.pi * 2

export type PitState = "idle" | "soon" | "live"

type Pennant = { part: BasePart, hang: CFrame, phase: number }

local _pitGroup: Instance? = nil
local _pennants: { Pennant } = {}
local _pennantParts: { BasePart } = {}
local _lanterns: { BasePart } = {}
local _lights: { BasePart } = {}
local _pitState: PitState = "idle"
local _pitStateKnown = false   -- erst nach dem ersten Lesen: ein Beitritt mitten im Event ist kein Start
local _pitOverride: PitState? = nil
local _eventColor = Color3.fromRGB(255, 214, 110)

local _nestGroup: Instance? = nil
local _nestCenter = Vector3.zero
local _wasps: { Model } = {}
local _pulse: BasePart? = nil
local _hum: Sound? = nil
local _nestBoss = false
local _nestOverride: boolean? = nil

--------------------------------------------------------------------------------
-- Event-Zustand aus der Welt lesen
--------------------------------------------------------------------------------

local _ring: BasePart? = nil
local _sub: TextLabel? = nil

local function findPitSources()
	local platform = workspace:WaitForChild("Platform", 60)
	local pit = platform and platform:WaitForChild("EventPit", 30)
	if not pit then return end
	local ring = pit:WaitForChild("EventRing", 30)
	if ring and ring:IsA("BasePart") then _ring = ring end
	local anchor = pit:WaitForChild("EventBannerAnchor", 30)
	local banner = anchor and anchor:WaitForChild("Banner", 30)
	local sub = banner and banner:WaitForChild("Sub", 30)
	if sub and sub:IsA("TextLabel") then _sub = sub end
end

-- Restzeit aus "noch 3:12" / "in 0:45" (Sprache egal: nur die Uhrzeit zaehlt).
local function remainingSeconds(): number?
	local sub = _sub
	if not sub then return nil end
	local m, s = string.match(sub.Text, "(%d+):(%d%d)")
	if not (m and s) then return nil end
	return (tonumber(m) :: number) * 60 + (tonumber(s) :: number)
end

local function readPitState(): PitState
	local override = _pitOverride
	if override then return override end
	local ring = _ring
	if ring and ring.Material == Enum.Material.Neon then
		_eventColor = ring.Color
		return "live"
	end
	local left = remainingSeconds()
	if left and left <= WorldFXConfig.PIT_FRAME.SOON_SECONDS then
		return "soon"
	end
	return "idle"
end

--------------------------------------------------------------------------------
-- Pit-Rahmen
--------------------------------------------------------------------------------

local function pitFloorY(): number
	return MapConfig.PLATFORM_TOP_Y + MapConfig.EVENT_PIT_GROUND_CLEARANCE
end

local function buildPitFrame(folder: Instance)
	local cfg = WorldFXConfig.PIT_FRAME
	local group = WorldFXKit.folder("PitFrame", folder)
	local pennantId = WorldFXKit.textureId("pennant_fabric")

	local count = MapConfig.PLOT_COUNT
	local tops: { Vector3 } = {}
	for k = 0, count - 1 do
		-- Masten in den Zaunfeldern zwischen zwei Stegen (Test: map_layout)
		local foot = MapLayout.atAngle(180 / count + k * (360 / count), cfg.POLE_RADIUS)
		foot = Vector3.new(foot.X, pitFloorY() - 0.3, foot.Z)
		WorldFXKit.pole("Pole", group, foot, cfg.POLE_HEIGHT, 0.5, cfg.POLE_COLOR, Enum.Material.Wood)
		local top = foot + Vector3.new(0, cfg.POLE_HEIGHT, 0)
		table.insert(tops, top)
		table.insert(_lanterns, WorldFXKit.ball("Lantern", group, 1.2, top + Vector3.new(0, 0.5, 0), cfg.LANTERN_OFF, Enum.Material.SmoothPlastic))
	end

	-- Kette zwischen zwei Nachbarmasten, mit Durchhang
	local colorIndex = 0
	for k = 1, count do
		local a, b = tops[k], tops[k % count + 1]
		local chord = b - a
		local along = Vector3.new(chord.X, 0, chord.Z).Unit
		local function hangAt(t: number): Vector3
			return a + chord * t - Vector3.new(0, cfg.SAG * 4 * t * (1 - t), 0)
		end
		for i = 1, cfg.PENNANTS do
			local t = i / (cfg.PENNANTS + 1)
			local hang = CFrame.fromMatrix(hangAt(t), along, Vector3.yAxis)
			colorIndex += 1
			local color = cfg.PENNANT_COLORS[(colorIndex - 1) % #cfg.PENNANT_COLORS + 1]
			local part = WorldFXKit.part("Pennant", group, cfg.PENNANT_SIZE,
				hang * CFrame.new(0, -cfg.PENNANT_SIZE.Y * 0.5, 0), color, Enum.Material.Fabric)
			if pennantId then
				part.Transparency = 1
				for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
					local decal = Instance.new("Decal")
					decal.Texture = pennantId
					decal.Face = face
					decal.Color3 = color
					decal.Parent = part
				end
			end
			table.insert(_pennants, { part = part, hang = hang, phase = k * 0.9 + i * 0.55 })
			table.insert(_pennantParts, part)
		end
		for i = 1, cfg.LIGHTS do
			local t = (i - 0.5) / cfg.LIGHTS
			table.insert(_lights, WorldFXKit.ball("Light", group, 0.45, hangAt(t) + Vector3.new(0, 0.15, 0),
				cfg.LIGHT_OFF, Enum.Material.SmoothPlastic))
		end
	end

	_pitGroup = group
	WorldFXKit.cullGroup(group, MapConfig.CENTER, cfg.SHOW_DISTANCE)
end

local function applyPitState(state: PitState)
	local cfg = WorldFXConfig.PIT_FRAME
	for _, lantern in _lanterns do
		local on = state ~= "idle"
		lantern.Color = if on then cfg.LANTERN_ON else cfg.LANTERN_OFF
		lantern.Material = if on then Enum.Material.Neon else Enum.Material.SmoothPlastic
	end
	if state ~= "live" then
		for _, light in _lights do
			light.Color = cfg.LIGHT_OFF
			light.Material = Enum.Material.SmoothPlastic
		end
	else
		for _, light in _lights do
			light.Material = Enum.Material.Neon
		end
	end
end

local function stepPit(clock: number)
	local group = _pitGroup
	if not (group and group.Parent) then return end
	local cfg = WorldFXConfig.PIT_FRAME

	-- Wimpel: ein gemeinsamer Wind, je Wimpel versetzt; ein BulkMoveTo
	if WorldFXKit.enabled("pitFlutter") then
		local amp = math.rad(if _pitState == "idle" then cfg.FLUTTER_CALM else cfg.FLUTTER_SOON)
		local cframes = table.create(#_pennants)
		for i, p in _pennants do
			local swing = amp * math.sin(clock * cfg.FLUTTER_RATE * TAU + p.phase)
			cframes[i] = p.hang * CFrame.Angles(swing, 0, 0) * CFrame.new(0, -cfg.PENNANT_SIZE.Y * 0.5, 0)
		end
		workspace:BulkMoveTo(_pennantParts, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end

	-- Lichterkette pulsiert langsam in der Event-Farbe
	if _pitState == "live" then
		local k = 0.5 + 0.5 * math.sin(clock * cfg.PULSE_RATE * TAU)
		local color = cfg.LIGHT_OFF:Lerp(_eventColor, 0.35 + 0.65 * k)
		for _, light in _lights do
			light.Color = color
		end
	end
end

--------------------------------------------------------------------------------
-- Wespen-Nest
--------------------------------------------------------------------------------

local function buildNest(folder: Instance)
	local platform = workspace:WaitForChild("Platform", 60)
	local nest = platform and platform:WaitForChild("WaspNest", 30)
	if not nest then return end
	local cfg = WorldFXConfig.WASP_NEST
	local group = WorldFXKit.folder("NestLife", folder)
	_nestCenter = MapLayout.waspNestCenter()

	if WorldFXKit.enabled("waspSwarm") then
		for i = 1, cfg.WASPS_BOSS do
			local model = Instance.new("Model")
			model.Name = "Wasp"
			local body = WorldFXKit.ellipsoid("Body", model, Vector3.new(0.38, 0.38, 0.62), CFrame.new(), cfg.WASP_COLOR,
				Enum.Material.SmoothPlastic)
			WorldFXKit.part("Stripe", model, Vector3.new(0.4, 0.12, 0.2), CFrame.new(0, 0, 0.05), cfg.STRIPE_COLOR, Enum.Material.SmoothPlastic)
			model.PrimaryPart = body
			model.Parent = if i <= cfg.WASPS_CALM then group else nil
			table.insert(_wasps, model)
		end
	end

	if WorldFXKit.enabled("waspPulse") then
		local body = nest:FindFirstChild("Body")
		local size = if body and body:IsA("BasePart") then body.Size * 1.18 else Vector3.new(5, 6, 5)
		local pulse = WorldFXKit.ellipsoid("Pulse", group, size, CFrame.new(_nestCenter), cfg.PULSE_COLOR,
			Enum.Material.Neon)
		pulse.Transparency = 1
		_pulse = pulse

		local humId = WorldFXConfig.SOUNDS.waspHum
		if humId ~= "" then
			local soundGroup = SoundService:FindFirstChild("WorldAmbience")
			if not soundGroup then
				local created = Instance.new("SoundGroup")
				created.Name = "WorldAmbience"
				created.Parent = SoundService
				soundGroup = created
			end
			local hum = Instance.new("Sound")
			hum.SoundId = humId
			hum.Looped = true
			hum.Volume = WorldFXConfig.SOUND_VOLUME.waspHum
			hum.RollOffMaxDistance = 60
			hum.RollOffMinDistance = 8
			hum.SoundGroup = soundGroup :: SoundGroup
			hum.Parent = pulse
			hum:Play()
			_hum = hum
		end
	end

	_nestGroup = group
	WorldFXKit.cullGroup(group, _nestCenter, cfg.SHOW_DISTANCE)

	-- Boss bald/da: das Nest leuchtet (Server)
	local body = nest:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		local function refresh()
			_nestBoss = body.Material == Enum.Material.Neon
		end
		body:GetPropertyChangedSignal("Material"):Connect(refresh)
		refresh()
	end
end

local function stepNest(clock: number)
	local group = _nestGroup
	if not (group and group.Parent) then return end
	local cfg = WorldFXConfig.WASP_NEST
	local boss = if _nestOverride ~= nil then _nestOverride else _nestBoss

	local count = if boss then cfg.WASPS_BOSS else cfg.WASPS_CALM
	for i, wasp in _wasps do
		local show = i <= count
		if show ~= (wasp.Parent ~= nil) then
			wasp.Parent = if show then group else nil
		end
		if show then
			local speed = cfg.ORBIT_SPEED * (1 + 0.18 * i) * (if boss then 1.6 else 1)
			local a = clock * speed * TAU + i * TAU / count
			local r = cfg.ORBIT_RADIUS + 0.7 * math.sin(clock * 1.3 + i)
			local pos = _nestCenter + Vector3.new(math.cos(a) * r, math.sin(clock * 2 + i * 1.7) * 1.2, math.sin(a) * r)
			local ahead = Vector3.new(-math.sin(a), 0, math.cos(a))
			wasp:PivotTo(CFrame.lookAt(pos, pos + ahead))
		end
	end

	local pulse = _pulse
	if pulse then
		pulse.Transparency = if boss then 0.6 + 0.25 * math.sin(clock * cfg.PULSE_RATE * TAU) else 1
	end
	local hum = _hum
	if hum then
		hum.Volume = WorldFXConfig.SOUND_VOLUME.waspHum * (if boss then 1.5 else 1)
	end
end

--------------------------------------------------------------------------------
-- Einstieg
--------------------------------------------------------------------------------

function HubEventController.init()
	if not FeatureFlags.isOn("WORLD_C_HUB") then return end
	local folder = WorldFXKit.folder("HubEvents", WorldFXKit.root())

	if WorldFXKit.enabled("pitFrame") then
		buildPitFrame(folder)
		task.spawn(findPitSources)
	end
	task.spawn(buildNest, folder)

	-- Debug (Studio): Zustaende erzwingen, "auto" = aus der Welt lesen
	WorldFXKit.onDebug("DebugPitState", function(value: any)
		_pitOverride = if value == "idle" or value == "soon" or value == "live" then value else nil
		if _pitOverride == "live" then
			_eventColor = Color3.fromRGB(255, 140, 240)
		end
	end)
	WorldFXKit.onDebug("DebugNestState", function(value: any)
		_nestOverride = if value == "boss" then true elseif value == "calm" then false else nil
	end)

	local acc, stateAcc, clock = 0, 1, 0
	RunService.Heartbeat:Connect(function(dt: number)
		clock += dt
		acc += dt
		stateAcc += dt
		if stateAcc >= 0.5 then
			stateAcc = 0
			local state = readPitState()
			if state ~= _pitState then
				if state == "live" and _pitStateKnown then
					WorldMomentController.eventStarted()
				end
				_pitState = state
				applyPitState(state)
			end
			_pitStateKnown = _ring ~= nil or _pitOverride ~= nil
		end
		if acc < TICK then return end
		acc = 0
		stepPit(clock)
		stepNest(clock)
	end)

	print("[HubEvents] aktiv")
end

return HubEventController
