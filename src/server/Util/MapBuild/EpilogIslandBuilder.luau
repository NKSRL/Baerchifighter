--!strict
-- EpilogIslandBuilder.luau
-- ServerScriptService/Util/MapBuild/EpilogIslandBuilder.luau
--
-- Einzige Zustaendigkeit (Prompt 3 von 7, Final-Epilog):
--   - Die kleine schwebende Insel ueber dem Gipfel bauen (Enthuellung aus Nebel),
--     die Bruecke dorthin Planke fuer Planke wachsen lassen — ERST NACH dem
--     gespeicherten Sieg —, beides wieder restlos abbauen, dem Avatar den Weg
--     (Wegpunkte) und dem Terminal (Prompt 4) seinen Platz (Mount) nennen.
--
-- Die Geometrie steht in Modules/EpilogIslandLayout (reine Rechnung, getestet),
-- die Masse in Config/EpilogConfig.ISLAND / .BRIDGE. Hier wird nur gebaut. Alle
-- Teile liegen im Ordner `Epilog` des Plots: Modell `Insel` (Koerper + Fangboden)
-- und Modell `Bruecke` (Planken, Gelaender). Das Modell `Bruecke` existiert erst,
-- wenn die erste Planke entsteht (Instance.new zur Wachstumszeit; vorher gibt es
-- weder Teile noch Kollision).
--
-- ANTI-EXPLOIT (Kern):
--   * growBridge / buildBridgeInstant bauen nur, wenn `guard(player)` (gesetzt von
--     EpilogService: epilog.state "pending"/"seen") es erlaubt. Ohne Guard: nie.
--   * growBridge verlangt zusaetzlich: Spieler lebt und steht im Radius des Gipfels.
--   * Die Insel liegt ausser jeder Sprungweite (Luft EpilogConfig.ISLAND.edgeGap).
--     Betritt jemand die Wiese vor der fertigen Bruecke, wird er zum Gipfel
--     zurueckgesetzt. Der Fangboden unter Bruecke und Insel holt Abgestuerzte
--     zurueck (zum Gipfel, bei fertiger Bruecke zum Brueckenansatz).
--   * Kein Teil der Bruecke liegt vorab versteckt im Workspace.
--
-- Dieses Modul kennt MapService NICHT (MapService benutzt es). Ein Spieler gehoert
-- zum Plot ueber das Attribut `PlotOwner` (UserId). Server baut und loescht;
-- Funken sind kurze Emit()-Stoesse (hoechstens maxEmitters gleichzeitig), das
-- Wippen der Deko macht der Client (Controllers/EpilogIslandFX, Tag `EpilogDeco`).

local Players             = game:GetService("Players")
local TweenService        = game:GetService("TweenService")
local CollectionService   = game:GetService("CollectionService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace           = game:GetService("Workspace")

local MapConfig    = require(ReplicatedStorage.Config.MapConfig)
local EpilogConfig = require(ReplicatedStorage.Config.EpilogConfig)
local Layout       = require(ReplicatedStorage.Modules.EpilogIslandLayout)

local MapParts             = require(script.Parent.MapParts)
local EpilogMeshes         = require(script.Parent.EpilogMeshes)
local EpilogSummitBuilder  = require(script.Parent.EpilogSummitBuilder)
local FigureFX             = require(ServerScriptService.Util.FigureFX)

local EpilogIslandBuilder = {}

-- Tags (fuer den Client und fuer `epilog scan`)
local TAG_ISLAND = "EpilogInsel"
local TAG_BRIDGE = "EpilogBruecke"
local TAG_DECO   = "EpilogDeco"

type State = {
	owner      : Player,
	plot       : Model,
	folder     : Folder,
	gipfel     : Model,
	layout     : Layout.Result,
	insel      : Model,
	body       : Model,
	wiese      : Part,
	rim        : Part,
	catchFloor : Part,
	bridge     : Model?,
	planks     : { BasePart },
	rails      : { Part },
	conns      : { RBXScriptConnection },
	cleanups   : { () -> () },
	thread     : thread?,
	revealed   : boolean,
	growing    : boolean,
	complete   : boolean,
	arrived    : boolean,
	removing   : boolean,
	emitters   : number,
	lastCatch  : number,
	rng        : Random,
}

local _state: { [Player]: State } = {}
-- Welche Stufe der Spieler hatte ("island" | "bridge"). Ueberlebt einen Neuaufbau
-- des Plots (Rebirth), damit die Teile danach wieder da sind. destroy() loescht ihn.
local _stage: { [Player]: string } = {}
local _guard: ((Player) -> boolean)? = nil
local _arrivalHandler: ((Player) -> ())? = nil

--------------------------------------------------------------------------------
-- Hilfen
--------------------------------------------------------------------------------

local function ownerOfPlot(plot: Model): Player?
	local id = plot:GetAttribute("PlotOwner")
	if typeof(id) ~= "number" then return nil end
	return Players:GetPlayerByUserId(id)
end

local function colorFor(key: string): Color3
	local I = EpilogConfig.ISLAND.colors :: { [string]: Color3 }
	local B = EpilogConfig.BRIDGE.colors :: { [string]: Color3 }
	return I[key] or B[key] or Color3.fromRGB(255, 255, 255)
end

local function particleTexture(): string
	local A = EpilogConfig.ASSETS
	return if A.cloudTex ~= "" then A.cloudTex else A.particleFallback
end

-- Ordner `Epilog` und Gipfel-Modell eines Plots (Gipfel liefert Mitte, Hoehe, Richtung).
local function gipfelOf(plot: Model): (Folder?, Model?)
	local folder = plot:FindFirstChild("Epilog")
	if not (folder and folder:IsA("Folder")) then return nil, nil end
	local gipfel = folder:FindFirstChild("Gipfel")
	if gipfel and gipfel:IsA("Model") then return folder, gipfel end
	return folder, nil
end

local function layoutOf(gipfel: Model): Layout.Result?
	local floorY = gipfel:GetAttribute("FloorY")
	local angle  = gipfel:GetAttribute("BridgeAngle")
	local rig = gipfel:FindFirstChild("Rig")
	if typeof(floorY) ~= "number" or typeof(angle) ~= "number" or not (rig and rig:IsA("BasePart")) then
		return nil
	end
	return Layout.compute(rig.Position.X, rig.Position.Z, floorY, angle, MapConfig.PIT_TOWER_RADIUS)
end

local function toVec(p: { number }): Vector3
	return Vector3.new(p[1], p[2], p[3])
end

local function cframeOf(piece: Layout.Piece): CFrame
	local cf = CFrame.new(piece.pos[1], piece.pos[2], piece.pos[3])
	if piece.kind == "Disc" then
		return cf * CFrame.Angles(0, 0, math.rad(90))
	end
	return cf * CFrame.Angles(0, piece.yaw, 0) * CFrame.Angles(0, 0, piece.pitch)
end

local function makePart(piece: Layout.Piece): Part
	local size: Vector3
	if piece.kind == "Disc" then
		size = Vector3.new(piece.size[1], piece.size[2], piece.size[2])
	elseif piece.kind == "Ball" then
		size = Vector3.new(piece.size[1], piece.size[1], piece.size[1])
	else
		size = Vector3.new(piece.size[1], piece.size[2], piece.size[3])
	end
	local part = MapParts.newPart(piece.name, size, cframeOf(piece), colorFor(piece.colorKey),
		(Enum.Material :: any)[piece.material])
	if piece.kind == "Disc" then part.Shape = Enum.PartType.Cylinder end
	if piece.kind == "Ball" then part.Shape = Enum.PartType.Ball end
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

-- Avatar sicher auf eine Stelle setzen (Geschwindigkeit null, nicht sitzend).
local function placeAvatar(player: Player, pos: Vector3, lookAt: Vector3): boolean
	local character, root, humanoid = characterOf(player)
	if not character or not root or not humanoid then return false end
	humanoid.Sit = false
	root.AssemblyLinearVelocity  = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	character:PivotTo(CFrame.lookAt(pos, Vector3.new(lookAt.X, pos.Y, lookAt.Z)))
	root.AssemblyLinearVelocity = Vector3.zero
	humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	return true
end

-- Figur auf eine Stelle stellen, Unterkante auf `bottomY`.
local function placeFigure(model: Model, x: number, z: number, bottomY: number, lookDir: Vector3)
	FigureFX.stopIdle(model)
	model:PivotTo(CFrame.lookAt(Vector3.new(x, bottomY + 2, z), Vector3.new(x, bottomY + 2, z) + lookDir))
	local boxCf, boxSize = model:GetBoundingBox()
	local bottom = boxCf.Position.Y - boxSize.Y / 2
	model:PivotTo(model:GetPivot() + Vector3.new(0, bottomY - bottom, 0))
	FigureFX.idleBob(model, { height = MapConfig.IDLE_BOB_HEIGHT, rate = MapConfig.IDLE_BOB_RATE })
end

local function isAlive(player: Player): boolean
	local _, root, humanoid = characterOf(player)
	return root ~= nil and humanoid ~= nil and humanoid.Health > 0
end

-- Steht der Spieler im Radius des Gipfels (Etage + Gipfelring, in Hoehe +-15)?
local function nearSummit(state: State): boolean
	local _, root = characterOf(state.owner)
	if not root then return false end
	local rig = state.gipfel:FindFirstChild("Rig")
	if not (rig and rig:IsA("BasePart")) then return false end
	local dx, dz = root.Position.X - rig.Position.X, root.Position.Z - rig.Position.Z
	local reach = MapConfig.PIT_TOWER_RADIUS + EpilogConfig.SUMMIT.extraRing + 2
	return math.sqrt(dx * dx + dz * dz) <= reach and math.abs(root.Position.Y - rig.Position.Y) <= 15
end

local function allowed(player: Player): boolean
	local guard = _guard
	if not guard then return false end   -- ohne Guard (EpilogService) wird nie gebaut
	local ok, result = pcall(guard, player)
	return ok and result == true
end

--------------------------------------------------------------------------------
-- Zustand / Aufraeumen
--------------------------------------------------------------------------------

-- Erlaubnis fuer Brueckenbau (EpilogService: state "pending" oder "seen").
function EpilogIslandBuilder.setGuard(guard: (Player) -> boolean)
	_guard = guard
end

-- Wird einmal gerufen, wenn der Avatar die Insel zum ersten Mal betritt
-- (Prompt 6: Terminal-Reveal).
function EpilogIslandBuilder.setArrivalHandler(handler: (Player) -> ())
	_arrivalHandler = handler
end

-- Registriert eine Aufraeum-Funktion, die beim Abbau/Zerstoeren der Insel laeuft.
-- false = keine Insel.
function EpilogIslandBuilder.onTeardown(player: Player, fn: () -> ()): boolean
	local state = _state[player]
	if not state then return false end
	table.insert(state.cleanups, fn)
	return true
end

function EpilogIslandBuilder.exists(player: Player): boolean
	local state = _state[player]
	return state ~= nil and state.insel.Parent ~= nil
end

function EpilogIslandBuilder.isComplete(player: Player): boolean
	local state = _state[player]
	return state ~= nil and state.complete
end

function EpilogIslandBuilder.isGrowing(player: Player): boolean
	local state = _state[player]
	return state ~= nil and state.growing
end

function EpilogIslandBuilder.stageOf(player: Player): string?
	return _stage[player]
end

-- Trennt Verbindungen, bricht den Faden ab und zerstoert die Teile. Die Stufe
-- bleibt gemerkt (Neuaufbau des Plots). Idempotent.
-- Weitere Teile der Insel (z. B. das Terminal aus Prompt 4) melden sich hier an,
-- damit sie mit der Insel verschwinden.
local function runCleanups(state: State)
	local list = state.cleanups
	state.cleanups = {}
	for _, fn in list do
		local ok, err = pcall(fn)
		if not ok then warn("[EpilogIslandBuilder] Aufraeumen fehlgeschlagen:", err) end
	end
end

local function teardown(player: Player)
	local state = _state[player]
	if not state then return end
	_state[player] = nil
	runCleanups(state)
	if state.thread then
		pcall(task.cancel, state.thread)
	end
	for _, conn in state.conns do
		conn:Disconnect()
	end
	if state.bridge and state.bridge.Parent ~= nil then state.bridge:Destroy() end
	if state.insel.Parent ~= nil then state.insel:Destroy() end
	if state.folder.Parent ~= nil and #state.folder:GetChildren() == 0 then
		state.folder:Destroy()
	end
end

-- Alles weg, sofort, und die Stufe vergessen (Leave, Reset, Abschluss).
function EpilogIslandBuilder.destroy(player: Player)
	teardown(player)
	_stage[player] = nil
end

--------------------------------------------------------------------------------
-- Funken (hoechstens maxEmitters gleichzeitig)
--------------------------------------------------------------------------------

local function sparks(state: State, part: BasePart)
	local B = EpilogConfig.BRIDGE
	if state.emitters >= B.maxEmitters then return end
	state.emitters += 1

	local rng = state.rng
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, B.plankThick / 2 + 0.2, 0)
	attachment.Parent = part

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture      = particleTexture()
	emitter.Color        = ColorSequence.new(B.colors.spark)
	emitter.LightEmission = 0.8
	emitter.Size         = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5 + rng:NextNumber() * 0.3),
		NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime     = NumberRange.new(B.sparkLife * 0.6, B.sparkLife)
	emitter.Speed        = NumberRange.new(5 + rng:NextNumber() * 3, 9 + rng:NextNumber() * 5)   -- Muster zufaellig
	emitter.SpreadAngle  = Vector2.new(30 + rng:NextNumber() * 60, 30 + rng:NextNumber() * 60)
	emitter.Acceleration = Vector3.new(0, -14, 0)
	emitter.Rate         = 0
	emitter.Parent       = attachment
	emitter:Emit(B.sparkCount + rng:NextInteger(-2, 2))

	task.delay(B.sparkLife + 0.1, function()
		state.emitters = math.max(0, state.emitters - 1)
		emitter:Destroy()
		attachment:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Insel
--------------------------------------------------------------------------------

-- Fangboden: wer faellt, wird zurueckgeholt (Gipfel; bei fertiger Bruecke zum Ansatz).
local function onCatch(state: State, hit: BasePart)
	local owner = state.owner
	if _state[owner] ~= state or state.removing then return end
	if Players:GetPlayerFromCharacter(hit.Parent) ~= owner then return end
	local now = os.clock()
	if now - state.lastCatch < EpilogConfig.ISLAND.catchCooldown then return end
	state.lastCatch = now
	if state.complete then
		local wp = state.layout.waypoints[3]   -- Ende des Brueckenansatzes
		local forward = toVec(state.layout.waypoints[4])
		placeAvatar(owner, toVec(wp) + Vector3.new(0, EpilogConfig.SUMMIT.spawnLift, 0), forward)
	else
		EpilogSummitBuilder.teleportPlayerToSummit(owner, nil)
	end
end

local function glowRim(state: State)
	local I = EpilogConfig.ISLAND
	TweenService:Create(state.rim, TweenInfo.new(I.glowSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ Color = I.colors.rimGlow }):Play()
	local light = state.wiese:FindFirstChild("Inselglanz")
	if light and light:IsA("PointLight") then
		TweenService:Create(light, TweenInfo.new(I.glowSeconds), { Brightness = I.lightBrightness * 1.8 }):Play()
	end
	state.insel:SetAttribute("Arrived", true)
end

local function onWiese(state: State, hit: BasePart)
	local owner = state.owner
	if _state[owner] ~= state or state.removing then return end
	if Players:GetPlayerFromCharacter(hit.Parent) ~= owner then return end
	if not state.complete then
		-- Insel vor der fertigen Bruecke betreten (Exploit): zurueck zum Gipfel
		local now = os.clock()
		if now - state.lastCatch < EpilogConfig.ISLAND.catchCooldown then return end
		state.lastCatch = now
		EpilogSummitBuilder.teleportPlayerToSummit(owner, nil)
		return
	end
	if state.arrived then return end
	state.arrived = true
	glowRim(state)
	local handler = _arrivalHandler
	if handler then task.spawn(handler, owner) end
end

-- Nebel-Puff waehrend der Enthuellung (ein Emitter).
local function cloudPuff(state: State, seconds: number)
	local I = EpilogConfig.ISLAND
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, 1, 0)
	attachment.Parent = state.wiese
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture      = particleTexture()
	emitter.Color        = ColorSequence.new(I.colors.cloud)
	emitter.LightEmission = 0.3
	emitter.Size         = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 14) })
	emitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime     = NumberRange.new(1.4, 2.2)
	emitter.Speed        = NumberRange.new(1, 3)
	emitter.SpreadAngle  = Vector2.new(180, 180)
	emitter.Rate         = 18
	emitter.Parent       = attachment
	task.delay(seconds, function()
		emitter.Enabled = false
		task.delay(2.4, function()
			emitter:Destroy()
			attachment:Destroy()
		end)
	end)
end

-- Baut die Insel. `opts.animate`: waechst in revealSeconds aus Nebel auf Vollgroesse
-- (Groessen-Tween, kein Mesh-Tausch); sonst steht sie sofort da (Wiederaufnahme).
-- Verlangt den Gipfel im Plot. Einzeiler: EpilogIslandBuilder.buildIsland(plot)
function EpilogIslandBuilder.buildIsland(plot: Model, opts: { animate: boolean? }?): Model?
	local owner = ownerOfPlot(plot)
	if not owner then return nil end
	local folder, gipfel = gipfelOf(plot)
	if not folder or not gipfel then return nil end
	local layout = layoutOf(gipfel)
	if not layout then return nil end
	teardown(owner)

	local I = EpilogConfig.ISLAND
	local animate = opts ~= nil and opts.animate == true

	local insel = Instance.new("Model")
	insel.Name = "Insel"
	local body = Instance.new("Model")
	body.Name = "Inselkoerper"

	-- Optional: Mesh-Huelle aus der Vorlage (Fels, Kristalle, Buesche, Wiesenmesh).
	-- Das Blender-Modell ist fuer Bruecke in +X gebaut; Roblox-yaw = -Brueckenwinkel.
	local A = EpilogConfig.ASSETS
	local bridgeAngle = math.atan2(layout.terminal.pos[3] - layout.center[3], layout.terminal.pos[1] - layout.center[1])
	local skin = EpilogMeshes.islandSkin(toVec(layout.center), -bridgeAngle, I.diameter, A.islandTemplate)

	local wiese: Part? = nil
	local rim: Part? = nil
	local pad: Part? = nil
	local catchFloor: Part? = nil
	for _, piece in layout.island do
		-- mit Huelle ersetzt sie Fels, Kristalle und Buesche (Primitive entfallen)
		if skin and (string.match(piece.name, "^Fels_") or string.match(piece.name, "^Kristall_")
			or string.match(piece.name, "^Busch_")) then
			continue
		end
		local part = makePart(piece)
		if piece.hidden then
			catchFloor = part
			part.CanTouch = true
			part.Parent = insel         -- ausserhalb des skalierten Koerpers
		else
			part.Parent = body
		end
		if piece.name == "Wiese" then
			wiese = part
			part.CanTouch = true
			if skin then part.Transparency = 1 end   -- bleibt als unsichtbarer Boden unter dem Wiesenmesh
		end
		if piece.name == "Inselrand" then rim = part end
		if piece.name == "Podest" then pad = part end
		if piece.deco then CollectionService:AddTag(part, TAG_DECO) end
	end
	if not (wiese and rim and pad and catchFloor) then
		insel:Destroy()
		body:Destroy()
		if skin then for _, c in skin do c.part:Destroy() end end
		return nil
	end
	if skin then
		local fromConfig = EpilogMeshes.colorsFromConfig(A.islandTemplate)
		local keys: { [string]: string } = {
			Epilog_Insel_Wiese = "grass", Epilog_Insel_Fels = "rock", Epilog_Insel_Kristall = "crystal",
			Epilog_Insel_Busch1 = "bush", Epilog_Insel_Busch2 = "bush", Epilog_Insel_Busch3 = "bush",
		}
		for _, c in skin do
			-- Vertexfarben der FBX bleiben unveraendert (Color weiss), ausser die Vorlage will Config-Farben
			c.part.Color = if fromConfig then colorFor(keys[c.name]) else Color3.new(1, 1, 1)
			c.part.Material = Enum.Material.SmoothPlastic
			c.part.Parent = body
			if c.name ~= "Epilog_Insel_Wiese" and c.name ~= "Epilog_Insel_Fels" then
				CollectionService:AddTag(c.part, TAG_DECO)
			end
		end
	end
	body.PrimaryPart = wiese
	body.Parent = insel

	-- Mount fuer das Terminal (Prompt 4) und sanftes Gold-Licht aus Richtung des Terminals
	local mount = Instance.new("Attachment")
	mount.Name = "TerminalMount"
	mount.WorldCFrame = CFrame.lookAt(toVec(layout.terminal.pos), toVec(layout.terminal.look))
	mount.Parent = pad
	local light = Instance.new("PointLight")
	light.Name       = "Inselglanz"
	light.Color      = I.lightColor
	light.Range      = I.lightRange
	light.Brightness = I.lightBrightness
	light.Shadows    = false
	light.Parent     = wiese

	insel:SetAttribute("Revealed", false)
	insel:SetAttribute("Arrived", false)
	CollectionService:AddTag(insel, TAG_ISLAND)

	local state: State = {
		owner = owner, plot = plot, folder = folder, gipfel = gipfel, layout = layout,
		insel = insel, body = body, wiese = wiese, rim = rim, catchFloor = catchFloor,
		bridge = nil, planks = {}, rails = {}, conns = {}, cleanups = {}, thread = nil,
		revealed = false, growing = false, complete = false, arrived = false, removing = false,
		emitters = 0, lastCatch = 0, rng = Random.new(),
	}
	_state[owner] = state
	_stage[owner] = "island"

	if animate then body:ScaleTo(I.revealStart) end
	insel.Parent = folder

	table.insert(state.conns, catchFloor.Touched:Connect(function(hit: BasePart) onCatch(state, hit) end))
	table.insert(state.conns, wiese.Touched:Connect(function(hit: BasePart) onWiese(state, hit) end))
	-- Faellt der Gipfel weg (Plot-Neuaufbau, Abbau), geht die Insel mit.
	table.insert(state.conns, gipfel.Destroying:Connect(function()
		task.defer(function()
			if _state[owner] == state then teardown(owner) end
		end)
	end))

	if not animate then
		state.revealed = true
		insel:SetAttribute("Revealed", true)
		return insel
	end

	-- Phase 1: aus dem Nebel aufwachsen (ease out)
	state.thread = task.spawn(function()
		cloudPuff(state, I.revealSeconds)
		for step = 1, I.revealSteps do
			if _state[owner] ~= state or state.removing then return end
			local t = step / I.revealSteps
			local eased = 1 - (1 - t) * (1 - t)
			body:ScaleTo(I.revealStart + (1 - I.revealStart) * eased)
			task.wait(I.revealSeconds / I.revealSteps)
		end
		if _state[owner] == state then
			body:ScaleTo(1)
			state.revealed = true
			insel:SetAttribute("Revealed", true)
		end
	end)
	return insel
end

--------------------------------------------------------------------------------
-- Bruecke
--------------------------------------------------------------------------------

local function ensureBridgeModel(state: State): Model
	local bridge = state.bridge
	if bridge and bridge.Parent ~= nil then return bridge end
	local model = Instance.new("Model")
	model.Name = "Bruecke"
	model:SetAttribute("Planks", 0)
	model:SetAttribute("Complete", false)
	CollectionService:AddTag(model, TAG_BRIDGE)
	model.Parent = state.folder
	state.bridge = model
	return model
end

local function plankCFrame(plank: Layout.Plank): CFrame
	return CFrame.new(plank.pos[1], plank.pos[2], plank.pos[3])
		* CFrame.Angles(0, plank.yaw, 0) * CFrame.Angles(0, 0, plank.pitch)
end

local function newPlank(state: State, plank: Layout.Plank, cf: CFrame): BasePart
	local size = Vector3.new(plank.size[1], plank.size[2], plank.size[3])
	local part: BasePart
	local mesh = EpilogMeshes.meshPart(EpilogConfig.ASSETS.plankTemplate, "Epilog_Plank")
	if mesh then
		-- Mesh-Planke (Holz mit Goldrand): Vertexfarben, ausser die Vorlage will Config-Farben
		EpilogMeshes.setup(mesh, "Planke_" .. plank.index, size, cf)
		mesh.Material = Enum.Material.WoodPlanks
		mesh.Color = if EpilogMeshes.colorsFromConfig(EpilogConfig.ASSETS.plankTemplate)
			then colorFor(plank.colorKey) else Color3.new(1, 1, 1)
		part = mesh
	else
		part = MapParts.newPart("Planke_" .. plank.index, size, cf, colorFor(plank.colorKey), Enum.Material.WoodPlanks)
	end
	part.CanCollide = false
	part.CanTouch   = false
	part.CanQuery   = true
	part.CastShadow = false
	part.Parent = ensureBridgeModel(state)
	table.insert(state.planks, part)
	return part
end

local function addRails(state: State, fadeIn: boolean)
	local B = EpilogConfig.BRIDGE
	local bridge = ensureBridgeModel(state)
	for _, piece in state.layout.rails do
		local part = makePart(piece)
		part.CanCollide = true
		part.Transparency = if fadeIn then 1 else B.railAlpha
		part.Parent = bridge
		table.insert(state.rails, part)
		if fadeIn then
			TweenService:Create(part, TweenInfo.new(B.railFade, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{ Transparency = B.railAlpha }):Play()
		end
	end
end

local function markComplete(state: State)
	state.complete = true
	_stage[state.owner] = "bridge"
	local bridge = state.bridge
	if bridge then
		bridge:SetAttribute("Planks", #state.planks)
		bridge:SetAttribute("Complete", true)
	end
end

-- Laesst die Bruecke Planke fuer Planke wachsen (Phase 2/3). `onDone` laeuft nach
-- dem Lichtimpuls. Gibt (false, Grund) zurueck, wenn eine Bedingung fehlt — der
-- Grund ist ein Code, kein Spielertext. Einzeiler: EpilogIslandBuilder.growBridge(plot, onDone)
function EpilogIslandBuilder.growBridge(plot: Model, onDone: (() -> ())?): (boolean, string)
	local owner = ownerOfPlot(plot)
	if not owner then return false, "no_owner" end
	local state = _state[owner]
	if not state then return false, "no_island" end
	if state.removing then return false, "removing" end
	if state.complete then return false, "already_complete" end
	if state.growing then return false, "already_growing" end
	if not state.revealed then return false, "island_not_revealed" end
	if not allowed(owner) then return false, "state_not_allowed" end
	if not isAlive(owner) then return false, "player_dead" end
	if not nearSummit(state) then return false, "player_not_at_summit" end

	state.growing = true
	ensureBridgeModel(state)

	local B = EpilogConfig.BRIDGE
	state.thread = task.spawn(function()
		if B.startDelay > 0 then task.wait(B.startDelay) end
		for i, plank in state.layout.planks do
			if _state[owner] ~= state or state.removing then return end
			local final = plankCFrame(plank)
			local part = newPlank(state, plank, final + Vector3.new(0, B.springDrop, 0))
			-- Aufsetz-Federn: faellt mit Overshoot (Back) auf seinen Platz
			TweenService:Create(part, TweenInfo.new(B.springSeconds, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ CFrame = final }):Play()
			task.delay(B.springSeconds, function()
				if _state[owner] ~= state or part.Parent == nil then return end
				part.CanCollide = true
				sparks(state, part)
			end)
			if state.bridge then state.bridge:SetAttribute("Planks", i) end
			if i < #state.layout.planks then task.wait(B.growInterval) end
		end
		task.wait(B.springSeconds)
		if _state[owner] ~= state or state.removing then return end

		-- Phase 3: Verbindung — Gelaender erscheint, Lichtimpuls laeuft zur Insel
		addRails(state, true)
		state.growing = false
		markComplete(state)

		local pulse = makePart(state.layout.pulse)
		pulse.Parent = ensureBridgeModel(state)
		local to = state.layout.pulseTo
		local n = state.layout.normal
		local target = CFrame.new(to[1] + n[1] * 0.2, to[2] + n[2] * 0.2, to[3] + n[3] * 0.2)
			* CFrame.Angles(0, state.layout.pulse.yaw, 0) * CFrame.Angles(0, 0, state.layout.pulse.pitch)
		local tween = TweenService:Create(pulse, TweenInfo.new(B.pulseSeconds, Enum.EasingStyle.Sine,
			Enum.EasingDirection.InOut), { CFrame = target })
		tween:Play()
		task.wait(B.pulseSeconds)
		if pulse.Parent ~= nil then pulse:Destroy() end
		if _state[owner] ~= state then return end
		if onDone then
			local ok, err = pcall(onDone)
			if not ok then warn("[EpilogIslandBuilder] onDone fehlgeschlagen:", err) end
		end
	end)
	return true, "ok"
end

-- Fertige Bruecke sofort (ohne Animation): Wiederaufnahme ("seen"/"pending") und
-- Neuaufbau des Plots. Gleiche Bedingung wie growBridge (Guard), aber ohne
-- Positionspruefung — der Spieler steht dabei noch nicht am Gipfel.
function EpilogIslandBuilder.buildBridgeInstant(plot: Model): (boolean, string)
	local owner = ownerOfPlot(plot)
	if not owner then return false, "no_owner" end
	local state = _state[owner]
	if not state then return false, "no_island" end
	if state.removing then return false, "removing" end
	if state.complete then return true, "already_complete" end
	if not allowed(owner) then return false, "state_not_allowed" end

	if state.thread then pcall(task.cancel, state.thread); state.thread = nil end
	state.growing = false
	state.revealed = true
	state.insel:SetAttribute("Revealed", true)
	state.body:ScaleTo(1)

	-- eventuell begonnene Planken ersetzen: sauber von vorn
	local bridge = state.bridge
	if bridge and bridge.Parent ~= nil then
		bridge:Destroy()
		state.bridge = nil
		table.clear(state.planks)
		table.clear(state.rails)
	end
	ensureBridgeModel(state)
	for _, plank in state.layout.planks do
		local part = newPlank(state, plank, plankCFrame(plank))
		part.CanCollide = true
	end
	addRails(state, false)
	markComplete(state)
	return true, "ok"
end

-- Baut nach einem Neuaufbau des Plots (Rebirth, Ausbau) wieder auf, was vorher
-- stand. Von MapService nach dem Gipfel-Bau gerufen.
function EpilogIslandBuilder.restoreAfterRebuild(plot: Model)
	local owner = ownerOfPlot(plot)
	if not owner then return end
	local stage = _stage[owner]
	teardown(owner)   -- alte Verweise lassen (Teile starben mit dem alten Plot)
	if not stage then return end
	if EpilogIslandBuilder.buildIsland(plot, { animate = false }) and stage == "bridge" then
		EpilogIslandBuilder.buildBridgeInstant(plot)
	end
end

--------------------------------------------------------------------------------
-- Abbau
--------------------------------------------------------------------------------

-- Baut Bruecke und Insel ab. `animated`: in umgekehrter Reihenfolge (Planken von
-- der Insel zum Gipfel, dann schrumpft die Insel), ca. removeSeconds; sonst sofort.
-- Nicht blockierend; `onDone` laeuft am Ende. Danach: 0 Reste.
function EpilogIslandBuilder.removeAll(plot: Model, animated: boolean, onDone: (() -> ())?)
	local owner = ownerOfPlot(plot)
	if not owner then return end
	local state = _state[owner]
	if not state then
		_stage[owner] = nil
		if onDone then task.defer(onDone) end
		return
	end
	if not animated then
		EpilogIslandBuilder.destroy(owner)
		if onDone then task.defer(onDone) end
		return
	end
	if state.removing then return end
	state.removing = true
	state.insel:SetAttribute("Revealed", false)   -- der Client hoert auf zu wippen
	if state.thread then pcall(task.cancel, state.thread); state.thread = nil end

	local B, I = EpilogConfig.BRIDGE, EpilogConfig.ISLAND
	state.thread = task.spawn(function()
		for _, rail in state.rails do rail:Destroy() end
		table.clear(state.rails)
		local count = #state.planks
		local plankTime = B.removeSeconds * 0.7
		for index = count, 1, -1 do
			local part = state.planks[index]
			if part and part.Parent ~= nil then
				part.CanCollide = false
				TweenService:Create(part, TweenInfo.new(0.25, Enum.EasingStyle.Sine, Enum.EasingDirection.In),
					{ Transparency = 1, CFrame = part.CFrame + Vector3.new(0, B.springDrop, 0) }):Play()
				task.delay(0.3, function() if part.Parent ~= nil then part:Destroy() end end)
			end
			task.wait(plankTime / math.max(1, count))
		end
		runCleanups(state)   -- Terminal u. a. verschwinden, bevor die Insel schrumpft
		local steps = I.revealSteps
		local shrinkTime = B.removeSeconds * 0.3
		for step = 1, steps do
			if _state[owner] ~= state then return end
			local t = step / steps
			state.body:ScaleTo(math.max(0.02, 1 - (1 - I.revealStart) * t * 1.0))
			task.wait(shrinkTime / steps)
		end
		if _state[owner] == state then
			EpilogIslandBuilder.destroy(owner)
		end
		if onDone then
			local ok, err = pcall(onDone)
			if not ok then warn("[EpilogIslandBuilder] onDone (Abbau) fehlgeschlagen:", err) end
		end
	end)
end

--------------------------------------------------------------------------------
-- Auskunft fuer Prompt 4-6
--------------------------------------------------------------------------------

-- Wegpunkte fuer den Avatar (Fusspunkte auf der Oberflaeche), vom Gipfel ueber
-- Ansatz und Planken bis vor das Terminal. Auch ohne gebaute Insel gueltig (der
-- Gipfel genuegt), damit Kamera/Wegfuehrung vorab planen koennen.
function EpilogIslandBuilder.getBridgeWaypoints(plot: Model): { Vector3 }
	local _, gipfel = gipfelOf(plot)
	if not gipfel then return {} end
	local layout = layoutOf(gipfel)
	if not layout then return {} end
	local list: { Vector3 } = {}
	for _, wp in layout.waypoints do
		table.insert(list, toVec(wp))
	end
	return list
end

-- Kamera- und Laufdaten fuer Prompt 5 (reine Zahlen-Tabellen {x, y, z}, gehen per
-- EpilogStart an den Client): Weg vom Avatar-Startpunkt auf dem Gipfel bis vor das
-- Terminal, Gipfelmitte (Avatar-Mitte nach dem Teleport), Brueckenrichtung, Inselmitte,
-- Terminal samt Blickziel. Auch ohne gebaute Insel gueltig (der Gipfel genuegt).
function EpilogIslandBuilder.getRouteInfo(plot: Model): {
	points : { { number } }, summit : { number }, dir : { number },
	island : { number }, terminalPos : { number }, terminalLook : { number },
}?
	local _, gipfel = gipfelOf(plot)
	if not gipfel then return nil end
	local layout = layoutOf(gipfel)
	if not layout then return nil end
	local angle = gipfel:GetAttribute("BridgeAngle")
	if typeof(angle) ~= "number" then return nil end
	local rig = gipfel:FindFirstChild("Rig")
	local spawnAtt = rig and rig:FindFirstChild("Spawn")
	local summit: Vector3
	if spawnAtt and spawnAtt:IsA("Attachment") then
		summit = spawnAtt.WorldPosition
	else
		local first = layout.waypoints[1]
		summit = Vector3.new(first[1], first[2] + EpilogConfig.SUMMIT.spawnLift, first[3])
	end
	local lift = EpilogConfig.SUMMIT.spawnLift
	local points: { { number } } = { { summit.X, summit.Y - lift, summit.Z } }
	for _, wp in layout.waypoints do
		table.insert(points, { wp[1], wp[2], wp[3] })
	end
	return {
		points = points,
		summit = { summit.X, summit.Y, summit.Z },
		dir = { math.cos(angle), 0, math.sin(angle) },
		island = { layout.center[1], layout.center[2], layout.center[3] },
		terminalPos = { layout.terminal.pos[1], layout.terminal.pos[2], layout.terminal.pos[3] },
		terminalLook = { layout.terminal.look[1], layout.terminal.look[2], layout.terminal.look[3] },
	}
end

-- Weltlage des Terminals (Prompt 4): Fusspunkt auf dem Podest, Blick zur Bruecke.
function EpilogIslandBuilder.getTerminalMount(plot: Model): CFrame?
	local _, gipfel = gipfelOf(plot)
	if not gipfel then return nil end
	local layout = layoutOf(gipfel)
	if not layout then return nil end
	return CFrame.lookAt(toVec(layout.terminal.pos), toVec(layout.terminal.look))
end

-- Setzt Avatar (und Begleiter-Baerchi) vor das Terminal auf die Insel. Nur bei
-- fertiger Bruecke (sonst koennte man die Insel vorab "teleportieren").
function EpilogIslandBuilder.teleportPlayerToIsland(player: Player, companion: Model?): boolean
	local state = _state[player]
	if not state or state.insel.Parent == nil or not state.complete then return false end
	local layout = state.layout
	local arrival = toVec(layout.waypoints[#layout.waypoints])
	local lookAt = toVec(layout.terminal.pos)
	if not placeAvatar(player, arrival + Vector3.new(0, EpilogConfig.SUMMIT.spawnLift, 0), lookAt) then
		return false
	end
	if companion and companion.Parent ~= nil then
		local dir = (lookAt - arrival) * Vector3.new(1, 0, 1)
		dir = if dir.Magnitude > 0.01 then dir.Unit else Vector3.new(1, 0, 0)
		local side = Vector3.new(-dir.Z, 0, dir.X) * EpilogConfig.SUMMIT.companionSide
		placeFigure(companion, arrival.X + side.X, arrival.Z + side.Z, layout.topY, dir)
	end
	return true
end

-- Teile fuer `parts` und `epilog scan`: (Insel, Bruecke).
function EpilogIslandBuilder.countParts(player: Player): (number, number)
	local state = _state[player]
	if not state then return 0, 0 end
	local function count(root: Instance?): number
		if not root then return 0 end
		local n = 0
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then n += 1 end
		end
		return n
	end
	return count(state.insel), count(state.bridge)
end

-- `epilog scan`: sucht im GANZEN Workspace nach Insel-/Brueckenresten, auch ohne
-- Zustand (vor dem Sieg muss alles 0 sein). Nur Debug.
function EpilogIslandBuilder.scanWorkspace(): { [string]: number }
	local islands, bridges, planks, parts, folders = 0, 0, 0, 0, 0
	for _, d in Workspace:GetDescendants() do
		if d:IsA("Folder") and d.Name == "Epilog" then
			folders += 1
		elseif d:IsA("Model") and d.Parent and d.Parent.Name == "Epilog" then
			if d.Name == "Insel" then islands += 1 elseif d.Name == "Bruecke" then bridges += 1 end
		elseif d:IsA("BasePart") then
			if string.match(d.Name, "^Planke_%d+$") then planks += 1 end
		end
	end
	for _, tag in { TAG_ISLAND, TAG_BRIDGE } do
		for _, tagged in CollectionService:GetTagged(tag) do
			for _, d in tagged:GetDescendants() do
				if d:IsA("BasePart") then parts += 1 end
			end
		end
	end
	return { inselModelle = islands, brueckenModelle = bridges, planken = planks,
		taggedTeile = parts, ordnerEpilog = folders }
end

return EpilogIslandBuilder
