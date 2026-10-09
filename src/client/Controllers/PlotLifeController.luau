--!strict
-- PlotLifeController.luau
-- StarterPlayerScripts/Controllers/PlotLifeController.luau
--
-- Einzige Zustaendigkeit:
--   - Plot-Inseln mit Persoenlichkeit (Paket D, "Welt aufwerten"):
--     Deko am Inselrand je Fortschritts-Stufe (Blumen, Pilze, Bienenhaus,
--     Bernstein-Stein), Glanz und Ueberlauf am Honig-Teich, warmer Schimmer
--     ueber der EIGENEN Insel, und leere Inseln mit Schild "Frei", Blumen und
--     Schmetterling
--
-- Die Stufe rechnet der Server (Modules/IslandStage) und schreibt sie als
-- Attribut "IslandStage" an den Player (PlotDisplayService). Gebaut wird
-- hier, nur auf dem Client: kein Server-Teil, das Teile-Budget der Insel
-- (250) bleibt unberuehrt. Neubau nur bei einem Stufenwechsel.
--
-- PERFORMANCE: EIN Takt (15x pro Sekunde) fuer Teich-Glanz, Ueberlauf und
-- Schmetterlinge, nur fuer Gruppen in Sichtweite (WorldFXKit.cullGroup).
-- Die Stufen-Deko steht still. Ein Emitter (Lichtpunkte ueber der eigenen
-- Insel). Feste Pools fuer Tropfen und Schmetterlinge.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local MapConfig     = require(ReplicatedStorage.Config.MapConfig)
local WorldFXConfig = require(ReplicatedStorage.Config.WorldFXConfig)
local FeatureFlags  = require(ReplicatedStorage.Config.FeatureFlags)
local MapLayout     = require(ReplicatedStorage.Modules.MapLayout)
local Loc           = require(ReplicatedStorage.Localization.Loc)

local WorldFXKit         = require(script.Parent.WorldFXKit)
local DayCycleController = require(script.Parent.DayCycleController)
local Icons              = require(script.Parent.Parent.UI.Icons)

local PlotLifeController = {}

local localPlayer = Players.LocalPlayer
local UPRIGHT = WorldFXKit.UPRIGHT
local TICK = 1 / 15
local TAU = math.pi * 2

type Drop = { part: BasePart, phase: number }
type PlotState = {
	slot: number,
	decor: Folder?,
	uncull: (() -> ())?,
	stage: number,
	pondGroup: Folder,
	shine: BasePart,
	drops: { Drop },
	ownerConn: RBXScriptConnection?,
}
type FreeState = { group: Folder, wings: { BasePart }, phase: number, uncull: (() -> ())? }

local _folder: Folder? = nil
local _plots: { [number]: PlotState } = {}
local _free: { [number]: FreeState } = {}
local _homeSlot: number? = nil
local _homeGroup: Folder? = nil

--------------------------------------------------------------------------------
-- Deklarative Deko (WorldFXConfig.ISLAND_KINDS, wie MapParts.buildDecor)
--------------------------------------------------------------------------------

local function buildKind(parent: Instance, kind: string, ground: CFrame)
	local pieces = (WorldFXConfig.ISLAND_KINDS :: any)[kind]
	if not pieces then return end
	for _, piece in pieces do
		local cf = ground * CFrame.new(piece.offset)
		local rot = piece.rotation
		if rot then
			cf = cf * CFrame.Angles(math.rad(rot.X), math.rad(rot.Y), math.rad(rot.Z))
		end
		local glow = piece.name == WorldFXConfig.ISLAND_GLOW_PIECE
		local part = WorldFXKit.part(piece.name, parent, piece.size, cf, piece.color,
			if glow then Enum.Material.Neon else Enum.Material.SmoothPlastic, piece.shape)
		if piece.name == "Box" or piece.name == "Roof" or piece.name == "Stand" then
			part.Material = Enum.Material.Wood
		elseif piece.name == "Rock" then
			part.Material = Enum.Material.Slate
		end
		if glow then
			DayCycleController.registerGlow(part, piece.color, Color3.fromRGB(255, 214, 110))
		end
	end
end

-- Boden-CFrame an einem Randpunkt: -Z zeigt zur Inselmitte.
local function rimGround(slot: number, angle: number, radius: number): CFrame
	local p, toCenter = MapLayout.islandRimPoint(slot, angle, radius)
	local ground = Vector3.new(p.X, MapConfig.PLATFORM_TOP_Y, p.Z)
	return CFrame.lookAt(ground, ground + toCenter)
end

--------------------------------------------------------------------------------
-- Stufen-Deko einer besetzten Insel
--------------------------------------------------------------------------------

local function ownerOf(slot: number): Player?
	local plot = workspace:FindFirstChild("Plot_" .. slot)
	local id = plot and plot:GetAttribute("PlotOwner")
	return if typeof(id) == "number" then Players:GetPlayerByUserId(id) else nil
end

local function stageOf(slot: number): number
	local owner = ownerOf(slot)
	local stage = owner and owner:GetAttribute("IslandStage")
	return if typeof(stage) == "number" then stage else 1
end

local function rebuildDecor(state: PlotState)
	if not WorldFXKit.enabled("islandDecor") then return end
	local stage = stageOf(state.slot)
	if stage == state.stage and state.decor then return end
	state.stage = stage

	local old = state.decor
	local uncull = state.uncull
	if uncull then uncull() end
	if old then old:Destroy() end
	local folder = _folder :: Folder
	local group = WorldFXKit.folder("IslandDecor_" .. state.slot, folder)
	for _, item in WorldFXConfig.ISLAND_STAGE_ITEMS do
		if item.stage <= stage then
			buildKind(group, item.kind, rimGround(state.slot, item.angle, WorldFXConfig.ISLAND_STAGE.RIM_RADIUS))
		end
	end
	state.decor = group
	state.uncull = WorldFXKit.cullGroup(group, MapLayout.plotCenter(state.slot), WorldFXConfig.ISLAND_STAGE.SHOW_DISTANCE)
end

--------------------------------------------------------------------------------
-- Honig-Teich: Glanz und Ueberlauf
--------------------------------------------------------------------------------

local function findFill(slot: number): BasePart?
	local plot = workspace:FindFirstChild("Plot_" .. slot)
	local pond = plot and plot:FindFirstChild("Pond")
	local fill = pond and pond:FindFirstChild("Fuellung")
	return if fill and fill:IsA("BasePart") then fill else nil
end

-- Fuellstand 0..1 aus der Hoehe der Fuellung (PondBuilder.writePondFill).
local function fillRatio(fill: BasePart): number
	if fill.Transparency >= 1 then return 0 end
	local span = MapConfig.POND_FILL_MAX_HEIGHT - MapConfig.POND_FILL_MIN_HEIGHT
	return math.clamp((fill.Size.X - MapConfig.POND_FILL_MIN_HEIGHT) / span, 0, 1)
end

local function buildPondLife(slot: number): (Folder, BasePart, { Drop })
	local cfg = WorldFXConfig.POND_LIFE
	local group = WorldFXKit.folder("PondLife_" .. slot, _folder :: Folder)
	local shine = WorldFXKit.part("Shine", nil, cfg.SHINE_SIZE, CFrame.new(), Color3.new(1, 1, 1),
		Enum.Material.Neon, Enum.PartType.Cylinder)
	shine.Transparency = 0.55
	local drops: { Drop } = {}
	for i = 1, cfg.OVERFLOW_DROPS do
		local part = WorldFXKit.ball("Drop", nil, cfg.DROP_SIZE, Vector3.zero, MapConfig.POND_FILL_COLOR, Enum.Material.Glass)
		table.insert(drops, { part = part, phase = (i - 1) / cfg.OVERFLOW_DROPS })
	end
	-- Sichtweite um den Teich (gerechnet wie MapLayout.pondOffset, plot-lokal)
	local center = MapLayout.plotCenter(slot)
	local plotCF = CFrame.lookAt(center, Vector3.new(MapConfig.CENTER.X, center.Y, MapConfig.CENTER.Z))
	WorldFXKit.cullGroup(group, (plotCF * CFrame.new(MapLayout.pondOffset())).Position, cfg.SHOW_DISTANCE)
	return group, shine, drops
end

local function stepPond(state: PlotState, clock: number)
	if not state.pondGroup.Parent then return end
	local cfg = WorldFXConfig.POND_LIFE
	local fill = findFill(state.slot)
	local ratio = if fill then fillRatio(fill) else 0

	if not fill or ratio <= 0 then
		state.shine.Parent = nil
		for _, drop in state.drops do drop.part.Parent = nil end
		return
	end

	local center = fill.Position
	local topY = center.Y + fill.Size.X * 0.5
	local radius = fill.Size.Y * 0.5

	-- Glanzfleck kreist langsam auf der Oberflaeche
	if WorldFXKit.enabled("pondShine") then
		local a = clock / cfg.SHINE_PERIOD * TAU
		local p = Vector3.new(center.X + math.cos(a) * radius * 0.45, topY + 0.03, center.Z + math.sin(a) * radius * 0.45)
		state.shine.CFrame = CFrame.lookAt(p, p + Vector3.new(-math.sin(a), 0, math.cos(a))) * UPRIGHT
		state.shine.Parent = state.pondGroup
	end

	-- Voll: Tropfen laufen ueber den Rand und fallen aufs Beet
	local full = ratio >= cfg.FULL_RATIO
	local rimRadius = MapConfig.POND_RADIUS + MapConfig.POND_RIM_WIDTH * 0.6
	local groundY = topY - MapConfig.POND_FILL_MAX_HEIGHT - MapConfig.POND_FLOOR_TOP + MapConfig.POND_RIM_TOP
	for i, drop in state.drops do
		if not full then
			drop.part.Parent = nil
		else
			local t = ((clock / cfg.DROP_INTERVAL) + drop.phase) % 1
			local a = (i / #state.drops) * TAU + 0.6
			local dir = Vector3.new(math.cos(a), 0, math.sin(a))
			local p: Vector3
			if t < 0.6 then
				-- ueber den Rand gleiten
				local k = t / 0.6
				p = Vector3.new(center.X, topY, center.Z) + dir * (radius + (rimRadius - radius) * k)
			else
				-- hinunter fallen
				local k = (t - 0.6) / 0.4
				p = Vector3.new(center.X, topY - (topY - groundY) * k * k, center.Z) + dir * rimRadius
			end
			drop.part.Position = p
			drop.part.Parent = state.pondGroup
		end
	end
end

--------------------------------------------------------------------------------
-- Eigene Insel
--------------------------------------------------------------------------------

local function buildHome(slot: number)
	local old = _homeGroup
	if old then old:Destroy() end
	_homeGroup = nil
	_homeSlot = slot
	if not WorldFXKit.enabled("homeGlow") then return end
	local cfg = WorldFXConfig.HOME_GLOW
	local group = WorldFXKit.folder("HomeGlow", _folder :: Folder)
	local center = MapLayout.plotCenter(slot)

	-- Warmer Ring auf dem Sandsaum: die Inselplatte deckt die Mitte ab, sichtbar
	-- ist nur der Streifen zwischen Wiese und Wasser — von weitem erkennbar.
	local radius = MapConfig.PLOT_ISLAND_RADIUS + MapConfig.SHORE_WIDTH * 0.75
	local y = MapConfig.PLATFORM_TOP_Y - MapConfig.SHORE_DROP + 0.04
	local ring = WorldFXKit.part("HomeRing", group, Vector3.new(0.05, radius * 2, radius * 2),
		CFrame.new(center.X, y, center.Z) * UPRIGHT, cfg.COLOR, Enum.Material.Neon, Enum.PartType.Cylinder)
	ring.Transparency = cfg.RING_TRANSPARENCY

	-- Warme Lichtpunkte ueber der Insel (ein Emitter)
	local anchor = WorldFXKit.anchor("HomeMotes", group,
		Vector3.new(MapConfig.PLOT_ISLAND_RADIUS * 1.6, 4, MapConfig.PLOT_ISLAND_RADIUS * 1.6),
		center + Vector3.new(0, cfg.MOTE_HEIGHT, 0))
	local emitter = Instance.new("ParticleEmitter")
	if WorldFXKit.applyParticleTexture(emitter, "firefly") then
		emitter.Color = ColorSequence.new(cfg.COLOR)
		emitter.LightEmission = 0.8
		emitter.Rate = cfg.MOTE_RATE
		emitter.Lifetime = NumberRange.new(5, 8)
		emitter.Speed = NumberRange.new(0.2, 0.8)
		emitter.SpreadAngle = Vector2.new(180, 180)
		emitter.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.5), NumberSequenceKeypoint.new(1, 0),
		})
		emitter.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.3), NumberSequenceKeypoint.new(1, 1),
		})
		emitter.Parent = anchor
	else
		emitter:Destroy()
	end
	_homeGroup = group
end

-- Fuer andere Controller (Paket F: mehr Bienen auf der eigenen Insel).
function PlotLifeController.homeSlot(): number?
	return _homeSlot
end

--------------------------------------------------------------------------------
-- Leere Insel
--------------------------------------------------------------------------------

local function buildFree(slot: number): FreeState
	local cfg = WorldFXConfig.FREE_ISLAND
	local group = WorldFXKit.folder("FreeIsland_" .. slot, _folder :: Folder)
	local center = MapLayout.plotCenter(slot)
	local facing = CFrame.lookAt(center, Vector3.new(MapConfig.CENTER.X, center.Y, MapConfig.CENTER.Z))

	-- Schild "Frei" mit Baerchi-Silhouette, zur Hauptinsel gedreht
	local wood = WorldFXConfig.SIGNPOST.WOOD
	for _, side in { -1, 1 } do
		WorldFXKit.pole("SignPost", group, (facing * CFrame.new(side * 2.4, 0, 0.3)).Position, cfg.SIGN_HEIGHT + 1, 0.4,
			WorldFXConfig.SIGNPOST.WOOD_DARK, Enum.Material.Wood)
	end
	local board = WorldFXKit.part("SignBoard", group, Vector3.new(6, 3, 0.3),
		facing * CFrame.new(0, cfg.SIGN_HEIGHT, 0), wood, Enum.Material.Wood)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.PixelsPerStud = 40
	gui.Parent = board
	local icon = Icons.make(gui, "bear", "🐻")
	icon.Size = UDim2.fromScale(0.3, 0.8)
	icon.Position = UDim2.fromScale(0.04, 0.1)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(0.62, 0.8)
	label.Position = UDim2.fromScale(0.36, 0.1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = WorldFXConfig.SIGNPOST.TEXT_COLOR
	label.Parent = gui
	Loc.bind(label, "world.sign.free")

	-- Ein paar Blumen am Rand
	for _, angle in cfg.FLOWER_ANGLES do
		buildKind(group, "Flowers", rimGround(slot, angle, WorldFXConfig.ISLAND_STAGE.RIM_RADIUS - 8))
	end

	-- Ein Schmetterling: zwei Fluegel, Schlag im gemeinsamen Takt
	local wings: { BasePart } = {}
	local color = WorldFXConfig.BUTTERFLIES.COLORS[(slot % #WorldFXConfig.BUTTERFLIES.COLORS) + 1]
	for _ = 1, 2 do
		table.insert(wings, WorldFXKit.part("Wing", group, Vector3.new(0.7, 0.05, 0.5), CFrame.new(center), color))
	end

	return { group = group, wings = wings, phase = slot * 1.3,
		uncull = WorldFXKit.cullGroup(group, center, cfg.SHOW_DISTANCE) }
end

local function stepFree(state: FreeState, slot: number, clock: number)
	if not state.group.Parent then return end
	local cfg = WorldFXConfig.BUTTERFLIES
	local center = MapLayout.plotCenter(slot)
	local t = clock * 0.25 + state.phase
	local pos = center + Vector3.new(math.cos(t) * cfg.WANDER, cfg.HEIGHT + math.sin(t * 2.3) * 0.8, math.sin(t * 1.4) * cfg.WANDER)
	local ahead = Vector3.new(-math.sin(t), 0, math.cos(t) * 1.4)
	local body = CFrame.lookAt(pos, pos + (if ahead.Magnitude > 1e-3 then ahead else Vector3.new(0, 0, 1)))
	local flap = math.rad(55) * math.sin(clock * cfg.FLAP_RATE * TAU)
	state.wings[1].CFrame = body * CFrame.Angles(0, 0, flap) * CFrame.new(-0.35, 0, 0)
	state.wings[2].CFrame = body * CFrame.Angles(0, 0, -flap) * CFrame.new(0.35, 0, 0)
end

--------------------------------------------------------------------------------
-- Besetzung
--------------------------------------------------------------------------------

local function setOccupied(slot: number, occupied: boolean)
	local free = _free[slot]
	if occupied then
		if free then
			-- aus der Distanz-Abschaltung nehmen, sonst haengt sie ihn wieder ein
			local uncull = free.uncull
			if uncull then uncull() end
			free.uncull = nil
			free.group.Parent = nil
		end
		local state = _plots[slot]
		if not state then
			local group, shine, drops = buildPondLife(slot)
			state = { slot = slot, decor = nil, uncull = nil, stage = 0, pondGroup = group, shine = shine, drops = drops, ownerConn = nil }
			_plots[slot] = state
		end
		local st = state :: PlotState
		-- Stufe des Besitzers beobachten
		local conn = st.ownerConn
		if conn then conn:Disconnect() end
		st.ownerConn = nil
		task.spawn(function()
			local owner: Player? = nil
			for _ = 1, 20 do
				owner = ownerOf(slot)
				if owner then break end
				task.wait(0.5)
			end
			if owner then
				st.ownerConn = owner:GetAttributeChangedSignal("IslandStage"):Connect(function()
					rebuildDecor(st)
				end)
				if owner == localPlayer then
					buildHome(slot)
				end
			end
			st.stage = 0
			rebuildDecor(st)
		end)
	else
		local state = _plots[slot]
		if state then
			local conn = state.ownerConn
			if conn then conn:Disconnect() end
			state.ownerConn = nil
			local decor = state.decor
			local uncull = state.uncull
			if uncull then uncull() end
			state.uncull = nil
			if decor then decor:Destroy() end
			state.decor = nil
			state.stage = 0
		end
		if _homeSlot == slot then
			local home = _homeGroup
			if home then home:Destroy() end
			_homeGroup = nil
			_homeSlot = nil
		end
		if WorldFXKit.enabled("freeIsland") then
			if not free then
				_free[slot] = buildFree(slot)
			elseif not free.uncull then
				free.group.Parent = _folder
				free.uncull = WorldFXKit.cullGroup(free.group, MapLayout.plotCenter(slot), WorldFXConfig.FREE_ISLAND.SHOW_DISTANCE)
			end
		end
	end
end

local function slotOf(child: Instance): number?
	local n = string.match(child.Name, "^Plot_(%d+)$")
	return if n then tonumber(n) else nil
end

--------------------------------------------------------------------------------
-- Einstieg
--------------------------------------------------------------------------------

function PlotLifeController.init()
	if not FeatureFlags.isOn("WORLD_D_PLOTS") then return end
	_folder = WorldFXKit.folder("PlotLife", WorldFXKit.root())

	for slot = 1, MapConfig.PLOT_COUNT do
		setOccupied(slot, workspace:FindFirstChild("Plot_" .. slot) ~= nil)
	end
	workspace.ChildAdded:Connect(function(child)
		local slot = slotOf(child)
		if slot then setOccupied(slot, true) end
	end)
	workspace.ChildRemoved:Connect(function(child)
		local slot = slotOf(child)
		if slot and not workspace:FindFirstChild(child.Name) then setOccupied(slot, false) end
	end)

	-- Debug: "islandstage" setzt das Player-Attribut (wie der Server), der
	-- Neubau laeuft dann ueber denselben Weg wie im Spiel.
	local acc, clock = 0, 0
	RunService.Heartbeat:Connect(function(dt: number)
		clock += dt
		acc += dt
		if acc < TICK then return end
		acc = 0
		for _, state in _plots do
			stepPond(state, clock)
		end
		for slot, free in _free do
			stepFree(free, slot, clock)
		end
	end)

	print("[PlotLife] aktiv")
end

return PlotLifeController
