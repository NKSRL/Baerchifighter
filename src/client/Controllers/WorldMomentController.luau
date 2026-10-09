--!strict
-- WorldMomentController.luau
-- StarterPlayerScripts/Controllers/WorldMomentController.luau
--
-- Einzige Zustaendigkeit:
--   - Grosse Momente sichtbar machen, die der ganze Server sieht (Paket G,
--     "Welt aufwerten"): Lichtsaeule (+ Funkenring) beim seltenen Baerchi,
--     Feuerwerk beim neuen Tower, Jubel beim Rekord, Lichtwelle beim Rebirth,
--     Funkenspirale bei seltener Mutation, und am Honigmast den Event-Start
--
-- Woher: Remotes.WorldMoment (WorldMomentService erkennt die Momente aus dem
-- Spielstand). Der Event-Start kommt vom Client selbst (HubEventController
-- sieht den Pit-Ring umschalten). Der Boss-Himmel ist schon da
-- (EventFXController.setBossSky), das Nest pulsiert (HubEventController).
--
-- Regeln (Leitbild):
--   * Hoechstens EIN grosser Moment gleichzeitig; weitere warten in einer
--     kurzen Schlange (Modules/WorldMoments.Queue), kleine laufen sofort.
--   * Momente anderer Spieler verdecken nie die eigene Sicht: kein
--     Vollbild-Blitz, kein Farbfilter, nichts vor der Kamera. Sie liegen
--     ueber der Insel des Spielers in der Welt.
--   * "Momente anderer Spieler": on | small | off (WorldFXConfig.MOMENTS).
--
-- PERFORMANCE: alle Teile aus festen Pools, ein Takt (30 Hz) nur waehrend
-- ein Effekt laeuft. Keine Lichter, kein Emitter.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local MapConfig     = require(ReplicatedStorage.Config.MapConfig)
local WorldFXConfig = require(ReplicatedStorage.Config.WorldFXConfig)
local FeatureFlags  = require(ReplicatedStorage.Config.FeatureFlags)
local BaerchiConfig = require(ReplicatedStorage.Config.BaerchiConfig)
local TowerConfig   = require(ReplicatedStorage.Config.TowerConfig)
local MapLayout     = require(ReplicatedStorage.Modules.MapLayout)
local WorldMoments  = require(ReplicatedStorage.Modules.WorldMoments)
local Remotes       = require(ReplicatedStorage.Network.Remotes)
local Loc           = require(ReplicatedStorage.Localization.Loc)

local WorldFXKit            = require(script.Parent.WorldFXKit)
local DayCycleController    = require(script.Parent.DayCycleController)
local ArenaLifeController   = require(script.Parent.ArenaLifeController)
local PlotLifeController    = require(script.Parent.PlotLifeController)
local LifeController        = require(script.Parent.LifeController)
local HubLandmarkController = require(script.Parent.HubLandmarkController)

local WorldMomentController = {}

local localPlayer = Players.LocalPlayer
local UPRIGHT = WorldFXKit.UPRIGHT
local TICK = 1 / 30
local TAU = math.pi * 2

type Payload = { userId: number, kind: string, value: string, number: number?, big: boolean }
-- Ein laufender Effekt: step(t 0..1) bis fertig, dann done()
type Effect = { start: number, duration: number, step: (number) -> (), done: () -> () }

local _folder: Folder? = nil
local _effects: { Effect } = {}
local _queue = WorldMoments.newQueue()
local _pending: { [number]: Payload } = {}
local _nextId = 0

-- Pools
local _column: BasePart? = nil
local _sparks: { BasePart } = {}
local _wave: BasePart? = nil
local _line: TextLabel? = nil
local _lineUntil = 0

--------------------------------------------------------------------------------
-- Pools
--------------------------------------------------------------------------------

local SPARK_POOL = 48

local function buildPools()
	_column = WorldFXKit.part("MomentColumn", nil, Vector3.new(1, 1, 1), CFrame.new(), Color3.new(1, 1, 1),
		Enum.Material.Neon, Enum.PartType.Cylinder)
	_wave = WorldFXKit.part("MomentWave", nil, Vector3.new(0.1, 1, 1), CFrame.new(), Color3.fromRGB(255, 226, 150),
		Enum.Material.Neon, Enum.PartType.Cylinder)
	for _ = 1, SPARK_POOL do
		table.insert(_sparks, WorldFXKit.ball("Spark", nil, 0.7, Vector3.zero, Color3.new(1, 1, 1), Enum.Material.Neon))
	end
end

-- `n` freie Funken (Parent nil) holen; weniger, wenn der Pool leer ist.
local function takeSparks(n: number): { BasePart }
	local out = {}
	for _, spark in _sparks do
		if #out >= n then break end
		if spark.Parent == nil and not spark:GetAttribute("Busy") then
			spark:SetAttribute("Busy", true)
			table.insert(out, spark)
		end
	end
	return out
end

local function releaseSparks(list: { BasePart })
	for _, spark in list do
		spark.Parent = nil
		spark:SetAttribute("Busy", nil)
	end
end

local function run(duration: number, step: (number) -> (), done: () -> ())
	table.insert(_effects, { start = os.clock(), duration = duration, step = step, done = done })
end

--------------------------------------------------------------------------------
-- Orte
--------------------------------------------------------------------------------

local function slotOfUser(userId: number): number?
	for slot = 1, MapConfig.PLOT_COUNT do
		local plot = workspace:FindFirstChild("Plot_" .. slot)
		if plot and plot:GetAttribute("PlotOwner") == userId then return slot end
	end
	return nil
end

local function figurePosition(slot: number): Vector3?
	local plot = workspace:FindFirstChild("Plot_" .. slot)
	local figures = plot and plot:FindFirstChild("Baerchis")
	if figures then
		for _, child in figures:GetChildren() do
			if child:IsA("Model") then return child:GetPivot().Position end
			if child:IsA("BasePart") then return child.Position end
		end
	end
	return nil
end

local function nearCamera(position: Vector3): boolean
	local camera = workspace.CurrentCamera
	return camera ~= nil and (camera.CFrame.Position - position).Magnitude <= WorldFXConfig.MOMENTS.NEAR_DISTANCE
end

--------------------------------------------------------------------------------
-- Die Bilder
--------------------------------------------------------------------------------

-- Lichtsaeule ueber der Insel (Rarity-Farbe), ab RING_MIN zusaetzlich Funkenring
local function playHatch(slot: number, rarity: string, big: boolean)
	local cfg = WorldFXConfig.MOMENTS
	local folder = _folder :: Folder
	local center = MapLayout.plotCenter(slot)
	local color = BaerchiConfig.RARITY_COLORS[rarity :: any] or Color3.new(1, 1, 1)
	local height = cfg.COLUMN_HEIGHT * (if big then 1 else 0.5)
	local duration = if big then cfg.DURATION.hatch else 1.2

	local column = _column
	if column and column.Parent == nil then   -- belegt (kleiner Moment parallel): nur Ring
		column.Color = color
		column.Parent = folder
		run(duration, function(t)
			local h = height * math.min(1, t * 3)
			local w = cfg.COLUMN_WIDTH * (1 - 0.4 * t)
			column.Size = Vector3.new(h, w, w)
			column.CFrame = CFrame.new(center + Vector3.new(0, h * 0.5, 0)) * UPRIGHT
			column.Transparency = 0.35 + 0.65 * t * t
		end, function()
			column.Parent = nil
		end)
	end

	local ringFrom = WorldMoments.rarityIndex(cfg.RING_MIN_RARITY)
	if big and WorldMoments.rarityIndex(rarity) >= ringFrom and WorldFXKit.enabled("momentRing") then
		local sparks = takeSparks(cfg.RING_SPARKS)
		for _, s in sparks do s.Color = color; s.Parent = folder end
		run(duration, function(t)
			local r = 6 + 26 * math.sin(t * math.pi * 0.5)
			for i, s in sparks do
				local a = i / #sparks * TAU + t * 1.5
				s.Position = center + Vector3.new(math.cos(a) * r, cfg.RING_HEIGHT + 4 * t, math.sin(a) * r)
				s.Transparency = t * t
			end
		end, function() releaseSparks(sparks) end)
	end
end

-- Feuerwerk vom Schau-Turm in der Farbe des neuen Towers
local function playTower(slot: number, towerId: string, big: boolean)
	local cfg = WorldFXConfig.MOMENTS
	local folder = _folder :: Folder
	local def = TowerConfig.get(towerId)
	local color = if def then def.color else Color3.fromRGB(255, 214, 110)
	local foot = MapLayout.showcaseFoot(slot) + Vector3.new(0, 12, 0)
	local rockets = if big then cfg.FIREWORK_ROCKETS else 1
	for r = 1, rockets do
		local delay = (r - 1) * 0.35
		local offset = Vector3.new(math.cos(r * 2.1) * 4, 0, math.sin(r * 2.1) * 4)
		local burst = foot + offset + Vector3.new(0, 22 + r * 3, 0)
		task.delay(delay, function()
			local rocket = takeSparks(1)
			local sparks = takeSparks(cfg.FIREWORK_SPARKS)
			for _, s in rocket do s.Color = Color3.fromRGB(255, 240, 200); s.Parent = folder end
			run(1.9, function(t)
				if t < 0.4 then
					local k = t / 0.4
					for _, s in rocket do s.Position = (foot + offset):Lerp(burst, 1 - (1 - k) * (1 - k)) end
				else
					for _, s in rocket do s.Parent = nil end
					local k = (t - 0.4) / 0.6
					for i, s in sparks do
						s.Color = color
						s.Parent = folder
						local a = i / #sparks * TAU
						local up = math.cos(i * 1.7) * 0.6
						local dir = Vector3.new(math.cos(a), up, math.sin(a))
						s.Position = burst + dir * (9 * math.sin(k * math.pi * 0.5)) - Vector3.new(0, 4 * k * k, 0)
						s.Transparency = k
					end
				end
			end, function()
				releaseSparks(rocket)
				releaseSparks(sparks)
			end)
		end)
	end
end

-- Weiche Lichtwelle ueber die Insel, Blumen wiegen sich
local function playRebirth(slot: number, big: boolean)
	local cfg = WorldFXConfig.MOMENTS
	local folder = _folder :: Folder
	local center = MapLayout.plotCenter(slot)
	local wave = _wave
	if wave and not wave.Parent then
		wave.Parent = folder
		local maxR = cfg.WAVE_RADIUS * (if big then 1 else 0.6)
		run(if big then cfg.DURATION.rebirth else 1.2, function(t)
			local r = 2 + maxR * t
			wave.Size = Vector3.new(0.1, r * 2, r * 2)
			wave.CFrame = CFrame.new(center.X, MapConfig.PLATFORM_TOP_Y + MapConfig.PLOT_SIZE.Y + 0.08, center.Z) * UPRIGHT
			wave.Transparency = 0.55 + 0.45 * t
		end, function() wave.Parent = nil end)
	end
	PlotLifeController.gust(slot)
end

-- Funkenspirale um den Baerchi (nur in der Naehe)
local function playMutation(slot: number, mutation: string, big: boolean)
	local cfg = WorldFXConfig.MOMENTS
	local at = figurePosition(slot)
	if not at or not nearCamera(at) then return end
	local folder = _folder :: Folder
	local def = (BaerchiConfig.MUTATIONS :: any)[mutation]
	local color = if def then def.color else Color3.new(1, 1, 1)
	local sparks = takeSparks(if big then cfg.SPIRAL_SPARKS else math.ceil(cfg.SPIRAL_SPARKS / 2))
	for _, s in sparks do s.Color = color; s.Parent = folder end
	run(cfg.DURATION.mutation, function(t)
		for i, s in sparks do
			local k = math.clamp(t * 1.4 - i / #sparks * 0.4, 0, 1)
			local a = k * TAU * 2 + i / #sparks * TAU
			local r = 3 - 1.5 * k
			s.Position = at + Vector3.new(math.cos(a) * r, 0.5 + k * 6, math.sin(a) * r)
			s.Transparency = k * k
		end
	end, function() releaseSparks(sparks) end)
end

-- Zeile unten fuer die anderen Spieler ("<Name> hat einen <Rarity>-Baerchi!")
local function showLine(userId: number, rarity: string)
	local label = _line
	if not label then return end
	local player = Players:GetPlayerByUserId(userId)
	label.Text = Loc.t("world.moment.hatch", {
		name = if player then player.DisplayName else "?",
		rarity = Loc.msg("rarity." .. rarity),
	})
	label.TextColor3 = BaerchiConfig.RARITY_COLORS[rarity :: any] or Color3.new(1, 1, 1)
	label.Visible = true
	_lineUntil = os.clock() + WorldFXConfig.MOMENTS.LINE_SECONDS
end

local function play(payload: Payload, big: boolean)
	local slot = slotOfUser(payload.userId)
	if not slot then return end
	local kind = payload.kind
	if kind == "hatch" then
		playHatch(slot, payload.value, big)
	elseif kind == "tower" then
		playTower(slot, payload.value, big)
	elseif kind == "record" then
		ArenaLifeController.celebrate(payload.userId)
	elseif kind == "rebirth" then
		playRebirth(slot, big)
	elseif kind == "mutation" then
		playMutation(slot, payload.value, big)
	end
end

--------------------------------------------------------------------------------
-- Eingang
--------------------------------------------------------------------------------

local function onMoment(raw: any)
	if typeof(raw) ~= "table" or typeof(raw.userId) ~= "number" or typeof(raw.kind) ~= "string" then return end
	local payload: Payload = {
		userId = raw.userId,
		kind = raw.kind,
		value = tostring(raw.value or ""),
		number = if typeof(raw.number) == "number" then raw.number else nil,
		big = raw.big == true,
	}
	local isSelf = payload.userId == localPlayer.UserId
	if not isSelf then
		local mode = WorldFXConfig.MOMENTS.OTHERS_DEFAULT
		if mode == "off" then return end
		if mode == "small" then payload.big = false end
		if payload.kind == "hatch" then showLine(payload.userId, payload.value) end
	end

	_nextId += 1
	local entry = { id = _nextId, kind = payload.kind, big = payload.big, at = os.clock() }
	if WorldMoments.push(_queue, entry) then
		play(payload, entry.big)
	else
		_pending[entry.id] = payload
	end
end

-- Event startet: Glocke (Krone blinkt zweimal), Bienen ziehen zum Event-Pit.
-- Aufrufer: HubEventController beim Wechsel auf "live".
function WorldMomentController.eventStarted()
	if not (FeatureFlags.isOn("WORLD_G_MOMENTS") and WorldFXKit.enabled("eventBell")) then return end
	HubLandmarkController.flashCrown()
	LifeController.rally(MapConfig.CENTER + Vector3.new(0, MapConfig.PLATFORM_TOP_Y, 0), 10)
end

function WorldMomentController.init()
	if not (FeatureFlags.isOn("WORLD_G_MOMENTS") and WorldFXKit.enabled("moments")) then return end
	local folder = WorldFXKit.folder("Moments", WorldFXKit.root())
	_folder = folder
	buildPools()

	-- Die Zeile unten (eigene kleine Oberflaeche, ueber nichts drueber)
	local gui = Instance.new("ScreenGui")
	gui.Name = "WorldMomentLine"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -96)
	label.Size = UDim2.fromOffset(520, 28)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextStrokeTransparency = 0.4
	label.Visible = false
	label.Parent = gui
	_line = label

	Remotes.WorldMoment.OnClientEvent:Connect(onMoment)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc < TICK then return end
		acc = 0
		local now = os.clock()

		-- naechster grosser Moment, sobald die Buehne frei ist — nicht waehrend
		-- die eigene Faehigkeiten-Show laeuft (wer zu lange wartet, kommt klein)
		local entry = if DayCycleController.showActive() and #_queue.waiting > 0
			and now - _queue.waiting[1].at <= WorldFXConfig.MOMENTS.MAX_WAIT
			then nil else WorldMoments.pop(_queue, now)
		if entry then
			local payload = _pending[entry.id]
			_pending[entry.id] = nil
			if payload then play(payload, entry.big) end
		end

		-- laufende Effekte
		for i = #_effects, 1, -1 do
			local e = _effects[i]
			local t = (now - e.start) / e.duration
			if t >= 1 then
				table.remove(_effects, i)
				e.done()
			else
				e.step(t)
			end
		end

		if label.Visible and now > _lineUntil then
			label.Visible = false
		end
	end)

	print("[WorldMoments] aktiv | andere Spieler:", WorldFXConfig.MOMENTS.OTHERS_DEFAULT)
end

return WorldMomentController
