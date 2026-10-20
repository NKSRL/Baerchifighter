--!strict
-- EpilogTerminalBuilder.luau
-- ServerScriptService/Util/MapBuild/EpilogTerminalBuilder.luau
--
-- Einzige Zustaendigkeit (Prompt 4 von 7, Final-Epilog):
--   - Das Start-Terminal mit dem grossen roten Knopf auf die Insel bauen (21 Teile,
--     deklarativ aus Modules/EpilogTerminalLayout), seinen Zustand als Attribut
--     `EpilogTerminalState` fuehren (idle, ready, armed, fired, done) und den
--     ProximityPrompt "Freigabe erteilen" (Halten 1,2 s) serverseitig bedienen.
--
-- Wie TerminalBuilder (Tower-Terminal): Der Server baut das Modell EINMAL und
-- schreibt nur Attribute. Bildschirmtext, Lampen, Klappe, Knopf-Bewegung und Glow
-- macht der Client (Controllers/EpilogTerminalController) aus dem Attribut. Das
-- alte Tower-Terminal wird nicht beruehrt.
--
-- Zustaende:
--   idle   Ruhe: Schirm "FREIGABE ERFORDERLICH", Lampen rot blinkend, Klappe zu
--   ready  Spieler < nearDistance: Lampen gelb, "BEREIT", Klappe ein Stueck offen
--   armed  Spieler haelt den Prompt: Klappe ganz auf (Loslassen -> zurueck)
--   fired  Halten abgeschlossen: Knopf gesenkt, Lampen gruen, "FREIGABE ERTEILT"
--   done   Prompt 6: "WELT 2 OFFEN", dauerhaft gruen
-- Dieses Modul speichert NICHTS. Was bei `fired` passiert, entscheidet der
-- Startwunsch-Handler (EpilogService.onLaunchRequested, Prompt 6).
--
-- Anti-Exploit: Der Prompt ist nur fuer den Plot-Besitzer, nur wenn `accessCheck`
-- (EpilogService: Flag an, state pending/seen) zustimmt und der Spieler lebt.
--
-- Cleanup: destroy/teardown zerstoert Modell, trennt Verbindungen, bricht den
-- Pruef-Faden ab. Mit der Insel (EpilogIslandBuilder.onTeardown) verschwindet auch
-- das Terminal. Dieses Modul kennt MapService NICHT.

local Players             = game:GetService("Players")
local Lighting            = game:GetService("Lighting")
local CollectionService   = game:GetService("CollectionService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")

local EpilogConfig = require(ReplicatedStorage.Config.EpilogConfig)
local Layout       = require(ReplicatedStorage.Modules.EpilogTerminalLayout)
local Loc          = require(ReplicatedStorage.Localization.Loc)
local WorldText    = require(ReplicatedStorage.Localization.WorldText)

local MapParts            = require(script.Parent.MapParts)
local EpilogMeshes         = require(script.Parent.EpilogMeshes)
local EpilogIslandBuilder = require(script.Parent.EpilogIslandBuilder)

local EpilogTerminalBuilder = {}

local T  = EpilogConfig.TERMINAL
local ST = T.STATE

type State = {
	owner  : Player,
	plot   : Model,
	folder : Folder,
	model  : Model,
	prompt : ProximityPrompt,
	knob   : BasePart,
	conns  : { RBXScriptConnection },
	thread : thread?,
	state  : string,
}

local _state: { [Player]: State } = {}
-- Zustand, der einen Neuaufbau des Plots (Rebirth) ueberlebt. destroy() loescht ihn.
local _memo: { [Player]: string } = {}
local _accessCheck: ((Player) -> boolean)? = nil
local _launchHandler: ((Player) -> ())? = nil

local VALID: { [string]: boolean } = {}
for _, v in ST do VALID[v] = true end

--------------------------------------------------------------------------------
-- Hilfen
--------------------------------------------------------------------------------

local function ownerOfPlot(plot: Model): Player?
	local id = plot:GetAttribute("PlotOwner")
	if typeof(id) ~= "number" then return nil end
	return Players:GetPlayerByUserId(id)
end

local function isNight(): boolean
	local t = Lighting.ClockTime
	return t < T.dayFrom or t >= T.dayTo
end

local function particleTexture(): string
	local A = EpilogConfig.ASSETS
	return if A.cloudTex ~= "" then A.cloudTex else A.particleFallback
end

local function localCFrame(piece: Layout.Piece): CFrame
	local cf = CFrame.new(piece.pos[1], piece.pos[2], piece.pos[3])
		* CFrame.Angles(piece.rot[1], piece.rot[2], piece.rot[3])
	if piece.kind == "Disc" then
		cf = cf * CFrame.Angles(0, 0, math.rad(90))   -- Achse = lokales Y
	end
	return cf
end

-- Teile mit Albedo-Textur (gebuerstetes Grau): Farbe wird dann zum Tint der Textur
local TEXTURED: { [string]: boolean } = {
	Epilog_Terminal_Sockel = true, Epilog_Terminal_Korpus = true, Epilog_Terminal_Konsole = true,
}
local TEXTURE_GREY = 0.6   -- mittlere Helligkeit der Albedo-Textur

-- Mesh-Teil aus der Vorlage (jedes Mesh ist im Teil-Koordinatensystem gebaut, Scheiben
-- mit Achse X): gleiche Lage/Ausrichtung wie das Primitiv, daher bleibt der Client unveraendert.
local function meshFor(piece: Layout.Piece, size: Vector3, cf: CFrame): MeshPart?
	if piece.hidden then return nil end
	local mesh = EpilogMeshes.meshPart(EpilogConfig.ASSETS.terminalTemplate, piece.name)
	if not mesh then return nil end
	EpilogMeshes.setup(mesh, piece.name, size, cf)
	mesh.Material = (Enum.Material :: any)[piece.material]
	local color = T.colors[piece.colorKey]
	if TEXTURED[piece.name] then
		local albedo = EpilogConfig.ASSETS.terminalAlbedo
		if albedo ~= "" then mesh.TextureID = albedo end
		if mesh.TextureID ~= "" then
			color = Color3.new(math.min(1, color.R / TEXTURE_GREY), math.min(1, color.G / TEXTURE_GREY),
				math.min(1, color.B / TEXTURE_GREY))
		end
	end
	mesh.Color = color
	-- CollisionFidelity laesst sich zur Laufzeit nicht setzen: steht an den Vorlagen-Teilen
	-- (Studio, Assets.EpilogTerminal) auf Box.
	return mesh
end

local function makePart(piece: Layout.Piece, mount: CFrame): BasePart
	local size: Vector3
	if piece.kind == "Disc" then
		size = Vector3.new(piece.size[1], piece.size[2], piece.size[2])
	elseif piece.kind == "Ball" then
		size = Vector3.new(piece.size[1], piece.size[1], piece.size[1])
	else
		size = Vector3.new(piece.size[1], piece.size[2], piece.size[3])
	end
	local cf = mount * localCFrame(piece)
	local part: BasePart? = meshFor(piece, size, cf)
	if not part then
		local prim = MapParts.newPart(piece.name, size, cf, T.colors[piece.colorKey],
			(Enum.Material :: any)[piece.material])
		if piece.kind == "Disc" then prim.Shape = Enum.PartType.Cylinder end
		if piece.kind == "Ball" then prim.Shape = Enum.PartType.Ball end
		part = prim
	end
	assert(part, "Terminalteil")
	part.CanCollide   = piece.collide
	part.CanTouch     = false
	part.CastShadow   = false
	part.Transparency = piece.transparency
	if not piece.collide and not piece.hidden then part.CanQuery = false end
	if piece.hidden then part.CanQuery = true end   -- der Prompt braucht die Flaeche
	return part
end

local function characterRoot(player: Player): (BasePart?, Humanoid?)
	local character = player.Character
	if not character then return nil, nil end
	local root = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if root and root:IsA("BasePart") and humanoid then return root, humanoid end
	return nil, nil
end

local function accessOk(player: Player): boolean
	local check = _accessCheck
	if not check then return false end   -- ohne Pruefung (EpilogService) ist der Prompt aus
	local ok, result = pcall(check, player)
	if not (ok and result == true) then return false end
	local root, humanoid = characterRoot(player)
	return root ~= nil and humanoid ~= nil and humanoid.Health > 0
end

local function promptWanted(state: State): boolean
	local s = state.state
	return (s == ST.IDLE or s == ST.READY or s == ST.ARMED) and accessOk(state.owner)
end

--------------------------------------------------------------------------------
-- Auskunft / Einstellungen
--------------------------------------------------------------------------------

-- Pruefung, ob der Spieler den Knopf bedienen darf (EpilogService).
function EpilogTerminalBuilder.setAccessCheck(check: (Player) -> boolean)
	_accessCheck = check
end

-- Wird gerufen, wenn der Prompt voll gehalten wurde (EpilogService.onLaunchRequested).
function EpilogTerminalBuilder.setLaunchHandler(handler: (Player) -> ())
	_launchHandler = handler
end

function EpilogTerminalBuilder.exists(player: Player): boolean
	local s = _state[player]
	return s ~= nil and s.model.Parent ~= nil
end

function EpilogTerminalBuilder.getState(player: Player): string?
	local s = _state[player]
	return if s then s.state else nil
end

function EpilogTerminalBuilder.countParts(player: Player): number
	local s = _state[player]
	if not s then return 0 end
	local n = 0
	for _, d in s.model:GetDescendants() do
		if d:IsA("BasePart") then n += 1 end
	end
	return n
end

--------------------------------------------------------------------------------
-- Zustand
--------------------------------------------------------------------------------

-- Setzt den Zustand (Attribut am Modell; der Client animiert). false bei
-- unbekanntem Zustand oder ohne Terminal. Speichert nichts.
function EpilogTerminalBuilder.setState(player: Player, newState: string): boolean
	local s = _state[player]
	if not s or s.model.Parent == nil or not VALID[newState] then return false end
	s.state = newState
	_memo[player] = newState
	s.model:SetAttribute(T.ATTRIBUTE, newState)
	s.prompt.Enabled = promptWanted(s)
	return true
end

-- Prompt 6: Countdown-Zahl (3, 2, 1; 0 = keine) als Attribut `EpilogCountdown`. Der Client
-- zeigt sie auf dem Bildschirm und schaltet die Lampen von Gelb auf Gruen. Speichert nichts.
function EpilogTerminalBuilder.setCountdown(player: Player, number: number): boolean
	local s = _state[player]
	if not s or s.model.Parent == nil then return false end
	s.model:SetAttribute(T.COUNTDOWN_ATTRIBUTE, math.max(0, math.floor(number)))
	return true
end

--------------------------------------------------------------------------------
-- Zerstoeren
--------------------------------------------------------------------------------

-- Wie destroy, aber der Zustand bleibt gemerkt (Neuaufbau des Plots).
local function teardown(player: Player)
	local s = _state[player]
	if not s then return end
	_state[player] = nil
	if s.thread then pcall(task.cancel, s.thread) end
	for _, conn in s.conns do conn:Disconnect() end
	if s.model.Parent ~= nil then s.model:Destroy() end
	if s.folder.Parent ~= nil and #s.folder:GetChildren() == 0 then s.folder:Destroy() end
end

function EpilogTerminalBuilder.destroy(player: Player)
	teardown(player)
	_memo[player] = nil
end

--------------------------------------------------------------------------------
-- Bauen
--------------------------------------------------------------------------------

-- Baut das Terminal auf den Mount der Insel (Insel muss stehen). `startState`
-- (Standard idle). Einzeiler: EpilogTerminalBuilder.build(plot)
function EpilogTerminalBuilder.build(plot: Model, startState: string?): Model?
	local owner = ownerOfPlot(plot)
	if not owner then return nil end
	if not EpilogIslandBuilder.exists(owner) then return nil end
	local mount = EpilogIslandBuilder.getTerminalMount(plot)
	if not mount then return nil end
	local folder = plot:FindFirstChild("Epilog")
	if not (folder and folder:IsA("Folder")) then return nil end
	teardown(owner)

	local layout = Layout.compute()
	local model = Instance.new("Model")
	model.Name = "Terminal"

	local parts: { [string]: BasePart } = {}
	for _, piece in layout.pieces do
		local part = makePart(piece, mount)
		part.Parent = model
		parts[piece.name] = part
	end
	local knob = parts["Epilog_Terminal_Knopf"]
	local korpus = parts["Epilog_Terminal_Korpus"]
	local trigger = parts["Epilog_Terminal_Ausloeser"]
	local pivot = parts["Epilog_Terminal_Sockel"]

	-- Scharnier der Klappe (Drehachse lokale X-Achse der Konsole): der Client dreht
	-- die Klappe darum.
	local hinge = Instance.new("Attachment")
	hinge.Name = "Scharnier"
	hinge.WorldCFrame = mount * CFrame.new(layout.hinge.pos[1], layout.hinge.pos[2], layout.hinge.pos[3])
		* CFrame.Angles(layout.hinge.rx, 0, 0)
	hinge.Parent = korpus

	-- Roter Glow-Kegel nach oben (ein Licht), nachts deutlicher
	local light = Instance.new("SpotLight")
	light.Name       = "Knopflicht"
	light.Face       = Enum.NormalId.Right       -- Zylinderachse = Konsolen-Normale
	light.Color      = T.colors.red
	light.Angle      = T.lightAngle
	light.Range      = T.lightRange
	light.Brightness = if isNight() then T.lightBrightnessNight else T.lightBrightnessDay
	light.Shadows    = false
	light.Parent     = knob

	-- Ein Emitter (aus bis fired/done; der Client schaltet ihn)
	local att = Instance.new("Attachment")
	att.Name = "Funken"
	att.Parent = knob
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name          = "Funken"
	emitter.Enabled       = false
	emitter.Texture       = particleTexture()
	emitter.Color         = ColorSequence.new(T.colors.gold)
	emitter.LightEmission = 0.8
	emitter.Size          = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency  = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	emitter.Lifetime      = NumberRange.new(0.8, 1.4)
	emitter.Speed         = NumberRange.new(3, 6)
	emitter.SpreadAngle   = Vector2.new(25, 25)
	emitter.EmissionDirection = Enum.NormalId.Right
	emitter.Rate          = 10
	emitter.Parent        = att

	-- Prompt: serverseitig, Halten 1,2 s, Distanz 8, ohne Sichtlinie
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name                  = "Freigabe"
	prompt.HoldDuration          = T.prompt.hold
	prompt.MaxActivationDistance = T.prompt.distance
	prompt.RequiresLineOfSight   = false
	prompt.ClickablePrompt       = true
	prompt.Exclusivity           = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.KeyboardKeyCode       = Enum.KeyCode.E
	prompt.Enabled               = false
	WorldText.set(prompt, Loc.msg("epilog.terminal.prompt_action"), "ActionText")
	WorldText.set(prompt, Loc.msg("epilog.terminal.prompt_object"), "ObjectText")
	prompt.Parent = trigger

	model.PrimaryPart = pivot
	local initial = startState or _memo[owner] or ST.IDLE
	if not VALID[initial] then initial = ST.IDLE end
	model:SetAttribute(T.ATTRIBUTE, initial)
	model:SetAttribute("PlotOwner", owner.UserId)
	CollectionService:AddTag(model, T.TAG)
	model.Parent = folder

	local state: State = {
		owner = owner, plot = plot, folder = folder, model = model, prompt = prompt, knob = knob,
		conns = {}, thread = nil, state = initial,
	}
	_state[owner] = state
	_memo[owner] = initial
	prompt.Enabled = promptWanted(state)

	-- Halten beginnt: Klappe auf. Loslassen vor Ablauf: zurueck.
	table.insert(state.conns, prompt.PromptButtonHoldBegan:Connect(function(who: Player)
		if who ~= owner or _state[owner] ~= state then return end
		if not promptWanted(state) then return end
		if state.state == ST.IDLE or state.state == ST.READY then
			EpilogTerminalBuilder.setState(owner, ST.ARMED)
		end
	end))
	table.insert(state.conns, prompt.PromptButtonHoldEnded:Connect(function(who: Player)
		if who ~= owner or _state[owner] ~= state then return end
		if state.state == ST.ARMED then   -- nach erfolgreichem Halten steht der Zustand schon auf fired
			EpilogTerminalBuilder.setState(owner, ST.READY)
		end
	end))
	table.insert(state.conns, prompt.Triggered:Connect(function(who: Player)
		if who ~= owner or _state[owner] ~= state then return end
		if not promptWanted(state) then return end
		local handler = _launchHandler
		if handler then
			local ok, err = pcall(handler, owner)
			if not ok then warn("[EpilogTerminalBuilder] Startwunsch fehlgeschlagen:", err) end
		end
	end))

	-- Annaeherung + Prompt-Freigabe: zweimal pro Sekunde, kein Frame-Loop.
	state.thread = task.spawn(function()
		while _state[owner] == state and model.Parent ~= nil do
			task.wait(T.checkSeconds)
			if _state[owner] ~= state then return end
			prompt.Enabled = promptWanted(state)
			local root = characterRoot(owner)
			if root and accessOk(owner) then
				local dist = (root.Position - knob.Position).Magnitude
				if state.state == ST.IDLE and dist < T.nearDistance then
					EpilogTerminalBuilder.setState(owner, ST.READY)
				elseif state.state == ST.READY and dist > T.farDistance then
					EpilogTerminalBuilder.setState(owner, ST.IDLE)
				end
			elseif state.state == ST.READY or state.state == ST.ARMED then
				EpilogTerminalBuilder.setState(owner, ST.IDLE)   -- tot, weg oder nicht mehr erlaubt
			end
		end
	end)

	-- Verschwindet die Insel, geht das Terminal mit (der Zustand bleibt fuer den Neuaufbau gemerkt).
	EpilogIslandBuilder.onTeardown(owner, function()
		if _state[owner] == state then teardown(owner) end
	end)
	return model
end

-- Nach einem Neuaufbau des Plots (Rebirth): Terminal im gemerkten Zustand wieder bauen.
function EpilogTerminalBuilder.restoreAfterRebuild(plot: Model)
	local owner = ownerOfPlot(plot)
	if not owner then return end
	local memo = _memo[owner]
	if not memo then return end
	EpilogTerminalBuilder.build(plot, memo)
end

return EpilogTerminalBuilder
