--!strict
-- EpilogSummitBuilder.luau
-- ServerScriptService/Util/MapBuild/EpilogSummitBuilder.luau
--
-- Einzige Zustaendigkeit (Prompt 2 von 7, Final-Epilog):
--   - Den Gipfel auf der obersten Etage des Final-Run-Turms bauen, den Avatar
--     samt Begleiter-Baerchi dorthin setzen, bei der Abfahrt als Lift mit nach
--     unten nehmen und alles wieder restlos entfernen.
--
-- Die Geometrie steht in Modules/EpilogSummitLayout (reine Rechnung, getestet),
-- die Masse in Config/EpilogConfig.SUMMIT. Hier wird nur gebaut. Alle Teile
-- liegen im Modell `Gipfel` im Ordner `Epilog` des Plots (Vertrag: Epilog ->
-- Gipfel, Bruecke, Insel, Terminal). Der Server baut, der Client schaut nur zu.
--
-- Dieses Modul kennt MapService NICHT (MapService benutzt es). Den Turm selbst
-- (Etagen, Sperre) fuehrt MapService; hier wird er nur ueber `setLevel`
-- (Parameter von lowerWithPlayer) verkleinert.
--
-- Cleanup: destroy(player) zerstoert Modell, trennt alle Verbindungen und
-- bricht den Aufbau-Faden ab. Der Ordner `Epilog` geht mit, wenn nichts anderes
-- (Insel, Terminal aus Prompt 3/4) mehr darin liegt.

local Players           = game:GetService("Players")
local Lighting          = game:GetService("Lighting")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MapConfig    = require(ReplicatedStorage.Config.MapConfig)
local EpilogConfig = require(ReplicatedStorage.Config.EpilogConfig)
local TowerConfig  = require(ReplicatedStorage.Config.TowerConfig)
local Layout       = require(ReplicatedStorage.Modules.EpilogSummitLayout)

local MapParts = require(script.Parent.MapParts)
local FigureFX = require(ServerScriptService.Util.FigureFX)

local EpilogSummitBuilder = {}

type State = {
	owner    : Player,
	plot     : Model,
	folder   : Folder,
	model    : Model,
	layout   : Layout.Result,
	floorY   : number,
	center   : Vector3,
	bridgeDir: Vector3,
	conns    : { RBXScriptConnection },
	thread   : thread?,
	lowering : boolean,
	lastCatch: number,
}

local _state: { [Player]: State } = {}

--------------------------------------------------------------------------------
-- Hilfen
--------------------------------------------------------------------------------

-- Etagen des gehaltenen Turms: die oberste Etage des Final-Laufs bei Stage 100.
function EpilogSummitBuilder.holdFloors(): number
	local def = TowerConfig.get(EpilogConfig.TOWER_ID)
	return TowerConfig.getRunFloor(EpilogConfig.TOWER_ID, if def then def.stages else 100)
end

function EpilogSummitBuilder.floorYOf(level: number): number
	return MapConfig.PLATFORM_TOP_Y + math.max(0, level) * MapConfig.PIT_TOWER_STEP_HEIGHT
end

local function colorFor(key: string): Color3
	local colors = EpilogConfig.SUMMIT.colors :: { [string]: Color3 }
	if key == "crystal" then
		-- Look des Final-Towers (nicht fest verdrahtet)
		local def = TowerConfig.get(EpilogConfig.TOWER_ID)
		local look = if def then MapConfig.TOWER_LOOKS[def.look] else nil
		return if look then look.accent else colors.rim
	end
	return colors[key] or colors.plate
end

local function isNight(): boolean
	local t = Lighting.ClockTime
	return t < EpilogConfig.SUMMIT.dayFrom or t >= EpilogConfig.SUMMIT.dayTo
end

local function makePart(piece: Layout.Piece): Part
	local cf = CFrame.new(piece.pos[1], piece.pos[2], piece.pos[3])
	local size: Vector3
	if piece.kind == "Disc" then
		size = Vector3.new(piece.size[1], piece.size[2], piece.size[2])
		cf = cf * CFrame.Angles(0, 0, math.rad(90))
	else
		size = Vector3.new(piece.size[1], piece.size[2], piece.size[3])
		cf = cf * CFrame.Angles(0, piece.yaw, 0)
	end
	local part = MapParts.newPart(piece.name, size, cf, colorFor(piece.colorKey),
		(Enum.Material :: any)[piece.material])
	if piece.kind == "Disc" then part.Shape = Enum.PartType.Cylinder end
	part.CanCollide = piece.collide
	part.CanTouch   = false
	part.CastShadow = false
	if piece.hidden then
		part.Transparency = 1
		part.CanQuery     = false
	elseif not piece.collide then
		part.CanQuery = false
	end
	return part
end

local function characterOf(player: Player): (Model?, BasePart?, Humanoid?)
	local character = player.Character
	if not character then return nil, nil, nil end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and humanoid then
		return character, root, humanoid
	end
	return nil, nil, nil
end

-- Figur auf eine Stelle stellen, Unterkante auf `bottomY` (Figuren haben
-- unterschiedliche Pivots).
local function placeFigure(model: Model, x: number, z: number, bottomY: number, lookDir: Vector3)
	FigureFX.stopIdle(model)
	model:PivotTo(CFrame.lookAt(Vector3.new(x, bottomY + 2, z), Vector3.new(x, bottomY + 2, z) + lookDir))
	local boxCf, boxSize = model:GetBoundingBox()
	local bottom = boxCf.Position.Y - boxSize.Y / 2
	model:PivotTo(model:GetPivot() + Vector3.new(0, bottomY - bottom, 0))
	FigureFX.idleBob(model, { height = MapConfig.IDLE_BOB_HEIGHT, rate = MapConfig.IDLE_BOB_RATE })
end

--------------------------------------------------------------------------------
-- Teleport
--------------------------------------------------------------------------------

-- Setzt den Avatar (und den Begleiter-Baerchi) auf den Spawn in der Mitte des
-- Gipfels. Sicherheits-Reset: Geschwindigkeit null, nicht sitzend, Humanoid
-- steht auf. false = kein Gipfel oder kein Charakter.
function EpilogSummitBuilder.teleportPlayerToSummit(player: Player, companion: Model?): boolean
	local state = _state[player]
	if not state or state.model.Parent == nil then return false end
	local character, root, humanoid = characterOf(player)
	if not character or not root or not humanoid then return false end

	local spawn = state.layout.spawn
	local spawnPos = Vector3.new(spawn[1], spawn[2], spawn[3])
	humanoid.Sit = false
	root.AssemblyLinearVelocity  = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	character:PivotTo(CFrame.lookAt(spawnPos, spawnPos + state.bridgeDir))
	root.AssemblyLinearVelocity = Vector3.zero
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)

	if companion and companion.Parent ~= nil then
		local side = Vector3.new(-state.bridgeDir.Z, 0, state.bridgeDir.X) * EpilogConfig.SUMMIT.companionSide
		placeFigure(companion, state.center.X + side.X, state.center.Z + side.Z,
			state.layout.plateTop, state.bridgeDir)
	end
	return true
end

--------------------------------------------------------------------------------
-- Bauen
--------------------------------------------------------------------------------

function EpilogSummitBuilder.exists(player: Player): boolean
	local state = _state[player]
	return state ~= nil and state.model.Parent ~= nil
end

-- Raeumt Zustand, Verbindungen, Faden und Teile weg. Idempotent.
function EpilogSummitBuilder.destroy(player: Player)
	local state = _state[player]
	if not state then return end
	_state[player] = nil

	if state.thread then
		pcall(task.cancel, state.thread)
	end
	for _, conn in state.conns do
		conn:Disconnect()
	end
	if state.model.Parent ~= nil then
		state.model:Destroy()
	end
	-- Der Ordner Epilog geht mit, wenn Insel/Terminal (Prompt 3/4) nichts darin lassen.
	if state.folder.Parent ~= nil and #state.folder:GetChildren() == 0 then
		state.folder:Destroy()
	end
end

-- Baut den Gipfel auf die Etage `holdFloors()`. `opts.animate`: sanftes
-- Einblenden (1,5 s); sonst steht alles sofort da (Wiederaufnahme, Neuaufbau).
-- Einzeiler: EpilogSummitBuilder.build(plot, slot, owner)
function EpilogSummitBuilder.build(plot: Model, slot: number, owner: Player, opts: { animate: boolean? }?): Model
	EpilogSummitBuilder.destroy(owner)

	local C = EpilogConfig.SUMMIT
	local animate = opts ~= nil and opts.animate == true

	local center = MapParts.pitCenter(slot)
	local outward = MapParts.outwardDirection(slot)
	local bridgeAngle = math.atan2(outward.Z, outward.X) + math.rad(C.bridgeOutwardDeg)
	local floorY = EpilogSummitBuilder.floorYOf(EpilogSummitBuilder.holdFloors())
	local layout = Layout.compute(center.X, center.Z, floorY, MapConfig.PIT_TOWER_RADIUS, bridgeAngle)

	local folder = plot:FindFirstChild("Epilog")
	if not (folder and folder:IsA("Folder")) then
		folder = Instance.new("Folder")
		folder.Name   = "Epilog"
		folder.Parent = plot
	end

	local model = Instance.new("Model")
	model.Name = "Gipfel"
	model:SetAttribute("FloorY", floorY)
	model:SetAttribute("BridgeAngle", bridgeAngle)
	model:SetAttribute("Ready", false)

	local fadeParts: { BasePart } = {}
	local rig: Part? = nil
	local catchFloor: Part? = nil
	for _, piece in layout.pieces do
		local part = makePart(piece)
		part.Parent = model
		if piece.name == "Rig" then rig = part end
		if piece.name == "Fangboden" then
			catchFloor = part
			part.CanTouch = true
		end
		if not piece.hidden then
			table.insert(fadeParts, part)
			if animate then part.Transparency = 1 end
		end
	end

	-- Kamera- und Spawn-Anker (Prompt 5 liest sie am Teil "Rig").
	if rig then
		for _, anchor in layout.anchors do
			local att = Instance.new("Attachment")
			att.Name = anchor.name
			att.WorldCFrame = CFrame.lookAt(
				Vector3.new(anchor.pos[1], anchor.pos[2], anchor.pos[3]),
				Vector3.new(anchor.target[1], anchor.target[2], anchor.target[3])
			)
			att.Parent = rig
		end
		-- Ein weiches Licht; nachts staerker. Einmalig beim Bau, kein Dauerprozess.
		local light = Instance.new("PointLight")
		light.Name       = "Gipfellicht"
		light.Color      = C.colors.rim
		light.Range      = C.lightRange
		light.Brightness = if isNight() then C.lightBrightnessNight else C.lightBrightnessDay
		light.Shadows    = false
		light.Parent     = rig
	end

	model.PrimaryPart = rig
	model.Parent = folder

	local state: State = {
		owner = owner, plot = plot, folder = folder :: Folder, model = model, layout = layout,
		floorY = floorY, center = center,
		bridgeDir = Vector3.new(math.cos(bridgeAngle), 0, math.sin(bridgeAngle)),
		conns = {}, thread = nil, lowering = false, lastCatch = 0,
	}
	_state[owner] = state

	-- Fangboden: wer trotz Gelaender faellt, wird zum Gipfel zurueckgeholt.
	if catchFloor then
		table.insert(state.conns, catchFloor.Touched:Connect(function(hit: BasePart)
			if state.lowering or _state[owner] ~= state then return end
			local who = Players:GetPlayerFromCharacter(hit.Parent)
			if who ~= owner then return end
			local now = os.clock()
			if now - state.lastCatch < C.catchCooldown then return end
			state.lastCatch = now
			EpilogSummitBuilder.teleportPlayerToSummit(owner, nil)
		end))
	end

	-- Respawn: der Spieler steht wieder auf dem Gipfel (der Gipfel bleibt).
	table.insert(state.conns, owner.CharacterAdded:Connect(function(character)
		task.defer(function()
			if _state[owner] ~= state or state.lowering then return end
			if character:WaitForChild("HumanoidRootPart", 10) == nil then return end
			task.wait(0.2)
			if _state[owner] == state and owner.Character == character then
				EpilogSummitBuilder.teleportPlayerToSummit(owner, nil)
			end
		end)
	end))

	if not animate then
		model:SetAttribute("Ready", true)
		return model
	end

	-- Phase 1 halten, Phase 2 aufwerten (gestaffelt einblenden), Phase 3 bereit.
	state.thread = task.spawn(function()
		task.wait(C.holdSeconds)
		local count = #fadeParts
		local fadeTime = C.decorSeconds * 0.45
		local stagger = (C.decorSeconds - fadeTime) / math.max(1, count - 1)
		for i, part in fadeParts do
			if _state[owner] ~= state then return end
			TweenService:Create(part, TweenInfo.new(fadeTime, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{ Transparency = 0 }):Play()
			if i < count then task.wait(stagger) end
		end
		task.wait(fadeTime + C.readySeconds)
		if _state[owner] == state then
			model:SetAttribute("Ready", true)
		end
	end)
	return model
end

--------------------------------------------------------------------------------
-- Finale: Abfahrt mit dem Spieler als Lift
--------------------------------------------------------------------------------

-- Der Turm faehrt von `fromLevel` auf 0 (Dauer PIT_TOWER_FALL_SECONDS x
-- lowerFactor, ueberschreibbar). Gipfel, Avatar und Begleiter fahren mit.
-- `setLevel(level)` verkleinert die Etagen (MapService). Blockiert bis zum
-- Ende, danach ist der Gipfel zerstoert. Prompt 6 ruft MapService.lowerSummit,
-- das dies mit setLevel aufruft. false = kein Gipfel.
function EpilogSummitBuilder.lowerWithPlayer(
	player: Player, fromLevel: number, setLevel: (number) -> (),
	opts: { seconds: number?, companion: Model? }?
): boolean
	local state = _state[player]
	if not state or state.model.Parent == nil then return false end
	state.lowering = true

	local seconds = (opts and opts.seconds) or MapConfig.PIT_TOWER_FALL_SECONDS * EpilogConfig.SUMMIT.lowerFactor
	local companion = opts and opts.companion
	local steps = math.max(1, math.min(fromLevel, math.floor(seconds * 20)))
	local stepTime = seconds / steps
	local previous = fromLevel
	if companion then FigureFX.stopIdle(companion) end

	for step = 1, steps do
		if _state[player] ~= state then return false end
		local level = fromLevel - math.floor(fromLevel * step / steps + 0.5)
		setLevel(level)
		local dy = EpilogSummitBuilder.floorYOf(level) - EpilogSummitBuilder.floorYOf(previous)
		previous = level
		state.model:PivotTo(state.model:GetPivot() + Vector3.new(0, dy, 0))
		local character = player.Character
		if character and character.Parent ~= nil then
			character:PivotTo(character:GetPivot() + Vector3.new(0, dy, 0))
			local _, root = characterOf(player)
			if root then root.AssemblyLinearVelocity = Vector3.zero end
		end
		if companion and companion.Parent ~= nil then
			companion:PivotTo(companion:GetPivot() + Vector3.new(0, dy, 0))
		end
		task.wait(stepTime)
	end

	if companion and companion.Parent ~= nil then
		FigureFX.idleBob(companion, { height = MapConfig.IDLE_BOB_HEIGHT, rate = MapConfig.IDLE_BOB_RATE })
	end
	EpilogSummitBuilder.destroy(player)
	return true
end

-- Zaehlt Teile (fuer `parts` und `epilog scan`): Teile im Gipfel.
function EpilogSummitBuilder.countParts(player: Player): number
	local state = _state[player]
	if not state then return 0 end
	local n = 0
	for _, d in state.model:GetDescendants() do
		if d:IsA("BasePart") then n += 1 end
	end
	return n
end

return EpilogSummitBuilder
