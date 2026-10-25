--!strict
-- EggHatch.luau
-- ReplicatedStorage/VFX/EggHatch.luau
--
-- Einzige Zustaendigkeit (R6):
--   - Die Ei-Schluepf-Inszenierung abspielen: Ei-MODELL erscheint, laedt in drei
--     Schlaegen auf (Risse), bricht auf (Blitz, Ring, Strahlen, Splitter), das Baerchi
--     steigt in VORDERANSICHT aus dem Licht, Name/Rarity/Level/Mutation/NEU.
--   - Eine gemeinsame Hilfe, die ein Baerchi im ViewportFrame zeigt: Start in
--     Vorderansicht, dann sanftes Pendeln (attachPet) — fuer Reveal, Batch-Karten,
--     Pet-Fenster, Inventar, Index.
--
-- Reine Client-Optik. Der Server rollt, die Animation spielt das fertige Ergebnis nur ab
-- (HatchAnimation uebergibt es). Alle Zahlen in Config/HatchFxConfig.
--
-- Warum "Vorderansicht": die Baerchi-Figur blickt nach -Z (Pivot.LookVector). Die alten
-- Kameras starteten bei +Z (hinter dem Baeren) und drehten sich erst herum.
--
-- Leistung: EINE Schleife (RenderStepped) fuer alles; Partikel sind Bilder aus einem
-- kleinen Pool; ein Ei-Klon und ein Baerchi-Klon gleichzeitig; alles wird bei Ende,
-- Ueberspringen und Spieler-Verlassen zerstoert.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local SoundService      = game:GetService("SoundService")
local UserInputService  = game:GetService("UserInputService")
local ContentProvider   = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Cfg           = require(ReplicatedStorage.Config.HatchFxConfig)
local SoundConfig   = require(ReplicatedStorage.Config.SoundConfig)
local Audio         = require(ReplicatedStorage.Audio)
local BaerchiConfig = require(ReplicatedStorage.Config.BaerchiConfig)
local EggConfig     = require(ReplicatedStorage.Config.EggConfig)
local EggModels     = require(ReplicatedStorage.Modules.EggModels)
local BaerchiMesh   = require(ReplicatedStorage.Modules.BaerchiMesh)
local Loc           = require(ReplicatedStorage.Localization.Loc)
local Names         = require(ReplicatedStorage.Localization.Names)
local HatchBorderShimmer = require(script.Parent.HatchBorderShimmer)

local G = Cfg.GENERAL
local C = Cfg.COLORS

local EggHatch = {}

export type Params = {
	parent    : Instance,        -- ScreenGui, in das die Szene kommt
	eggType   : string,
	rarity    : string,
	configId  : string,
	level     : number,
	mutation  : string?,
	isNew     : boolean,
	fast      : boolean?,        -- nil = die gemerkte Einstellung "Schnell"
	burstOnly : boolean?,        -- nur Ei bis Aufbruch (Batch); Szene bleibt bis destroy()
	queued    : (() -> boolean)?,-- true = es warten weitere Eier (Reveal kuerzer)
}

export type Handle = {
	root       : GuiObject,
	stage      : Frame,
	skip       : () -> (),
	destroy    : () -> (),
	onFinished : RBXScriptSignal,
	finished   : boolean,
}

-- Einstellung "Schnelles Oeffnen" (nur Client, gilt bis zum Neustart)
EggHatch.fast = false

--------------------------------------------------------------------------------
-- Hilfen
--------------------------------------------------------------------------------

local function easeOutBack(x: number): number
	local c1, c3 = 1.70158 * 1.4, 1.70158 * 1.4 + 1
	return 1 + c3 * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

local function easeOutCubic(x: number): number
	return 1 - (1 - x) ^ 3
end

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

-- Audio-Rework 16.10.: die Schluepf-Klaenge kommen aus ReplicatedStorage/Audio
-- (weich, mit Musik-Absenkung beim grossen Moment); SoundConfig-Slots bleiben ungenutzt.
local HATCH_TO_AUDIO: { [string]: string } = {
	hatchCrack     = "hatchCrack",
	hatchBurst     = "hatchCommon",
	hatchBurstHigh = "hatchRare",
}
local function playSound(name: string)
	local audioName = HATCH_TO_AUDIO[name]
	if audioName then Audio.play(audioName) end
end

local function image(parent: Instance, key: string, z: number): ImageLabel
	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.Image = (Cfg.ASSETS :: any)[key]
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.ZIndex = z
	img.Active = false
	img.Parent = parent
	return img
end

local function rarityColor(rarity: string): Color3
	return BaerchiConfig.RARITY_COLORS[rarity] or C.honey
end

-- Bilder einmal vorladen (frisch hochgeladene Bilder erscheinen sonst erst nach Sekunden)
local _preloaded = false
function EggHatch.preload()
	if _preloaded then return end
	_preloaded = true
	task.spawn(function()
		local list = {}
		for _, id in Cfg.ASSETS do
			local img = Instance.new("ImageLabel")
			img.Image = id
			table.insert(list, img)
		end
		if Cfg.CINEMATIC.videoId ~= "" then
			local v = Instance.new("VideoFrame")
			v.Video = Cfg.CINEMATIC.videoId
			table.insert(list, v)
		end
		pcall(function() ContentProvider:PreloadAsync(list) end)
		for _, img in list do img:Destroy() end
	end)
end

-- Faktor aus der globalen UiScale (Pixel -> Oberflaechen-Einheiten)
local function guiUnits(screenGui: Instance): Vector2
	local layer = screenGui:IsA("LayerCollector") and (screenGui :: LayerCollector) or nil
	if not layer then return Vector2.new(800, 450) end
	local global = layer:FindFirstChild("GlobalScale")
	local g = if global and global:IsA("UIScale") then math.max(global.Scale, 0.01) else 1
	return layer.AbsoluteSize / g
end

--------------------------------------------------------------------------------
-- Baerchi im ViewportFrame: Vorderansicht + Pendeln (gemeinsame Stelle)
--------------------------------------------------------------------------------

-- Haengt `model` in `view`, richtet die Kamera auf die VORDERSEITE (-Z des Pivots) und
-- pendelt leicht um sie. Rueckgabe: Aufraeumfunktion. opts.yawOffset(t) -> Zusatzdrehung
-- (Radiant, z. B. die einmalige Drehung im Reveal), opts.riseOffset(t) -> Hoehenversatz.
function EggHatch.attachPet(view: ViewportFrame, model: Model, opts: { sway: boolean?, yaw: ((number) -> number)?, lift: ((number) -> number)? }?): () -> ()
	local o = opts or {}
	model.Parent = view
	local cf, size = model:GetBoundingBox()
	local front = model:GetPivot().LookVector
	-- Wie im Index: echte Vorderseite ueber Nase/Schnauze bestimmen (Pivot kann bei neuen Modellen falsch liegen)
	local face: BasePart? = nil
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			local nm = p.Name:lower()
			if nm:sub(-4) == "nose" or nm:sub(-5) == "snout" then face = p break end
		end
	end
	if face then
		local f = (face.Position - cf.Position) * Vector3.new(1, 0, 1)
		if f.Magnitude > 0.05 then front = f.Unit end
	end
	local camera = Instance.new("Camera")
	camera.FieldOfView = G.fovBase
	camera.Parent = view
	view.CurrentCamera = camera
	local radius = math.max(size.X, size.Y, size.Z)
	local distance = radius / (2 * math.tan(math.rad(camera.FieldOfView / 2))) * 1.15
	local center = cf.Position
	local basePivot = model:GetPivot()
	local start = os.clock()
	local swing = math.rad(G.pendulumDegrees)
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		if not view.Parent then
			if conn then conn:Disconnect() end
			return
		end
		local t = os.clock() - start
		local yaw = if o.sway ~= false then math.sin(t * G.pendulumSpeed) * swing else 0
		if o.yaw then yaw += o.yaw(t) end
		local lift = if o.lift then o.lift(t) else 0
		if lift ~= 0 then
			model:PivotTo(basePivot + Vector3.new(0, lift * size.Y, 0))
		end
		local dir = (CFrame.Angles(0, yaw, 0) * CFrame.new(front * distance + Vector3.new(0, size.Y * 0.28, 0))).Position
		camera.CFrame = CFrame.lookAt(center + dir, center)
	end)
	return function()
		if conn then conn:Disconnect() conn = nil end
	end
end

--------------------------------------------------------------------------------
-- Die Inszenierung
--------------------------------------------------------------------------------

type Particle = {
	gui: GuiObject, x: number, y: number, vx: number, vy: number,
	age: number, life: number, rot: number, vr: number, size: number, grow: number, gravity: number, fade: boolean,
}

function EggHatch.play(params: Params): Handle
	local parent = params.parent
	local rIndex = BaerchiConfig.getRarityIndex(params.rarity :: any) or 1
	local tier = Cfg.tierFor(rIndex)
	local accent = rarityColor(params.rarity)
	local fast = if params.fast ~= nil then params.fast else EggHatch.fast
	local f = if fast then G.fastFactor else 1
	local isTouch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local pFactor = if isTouch then G.mobileParticles else 1
	local unit = guiUnits(parent)
	local minSide = math.min(unit.X, unit.Y)

	-- Zeitplan (Sekunden, nach Tempo)
	local tAppear = tier.appear * f
	local interval = tier.hitInterval * f
	local tBurst = tAppear + 3 * interval
	local tReveal = tBurst + tier.burst * f
	local revealIn = tier.revealIn * f

	local finishedEvent = Instance.new("BindableEvent")
	local finished = false
	local destroyed = false
	local connections: { RBXScriptConnection } = {}
	local particles: { Particle } = {}
	local cleanupPet: (() -> ())? = nil

	-- Randschimmer: Phase 1 neutral ab Start; Rarity-Farbe ab dem ersten Hinweis (giveHint)
	local shimmer = HatchBorderShimmer.start(parent)
	local hintGiven = false
	local shimmerStopped = false
	local function giveHint()
		if hintGiven then return end
		hintGiven = true
		shimmer:setRarity(params.rarity)
	end
	local function stopShimmer(immediate: boolean?)
		if shimmerStopped and not immediate then return end
		shimmerStopped = true
		shimmer:stop(immediate)
	end

	-- Wurzel: faengt Tipps, fuellt den Bildschirm
	local root = Instance.new("TextButton")
	root.Name = "EggHatch"
	root.Text = ""
	root.AutoButtonColor = false
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.ZIndex = 50
	root.Parent = parent

	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.BorderSizePixel = 0
	dim.Size = UDim2.fromScale(1, 1)
	dim.ZIndex = 50
	dim.Active = false
	dim.Parent = root

	-- 21.10. Playtest: das Haupt-ScreenGui laesst Platz fuer die Topbar (CoreUISafeInsets),
	-- dort fehlte die Abdunklung. Eigenes ScreenGui ohne Inset, direkt UNTER dem Haupt-GUI
	-- (dort ist an dieser Stelle nichts von RBL gezeichnet), Transparenz folgt dim.
	local dimGui = Instance.new("ScreenGui")
	dimGui.Name = "EggHatchDimFull"
	dimGui.ResetOnSpawn = false
	dimGui.IgnoreGuiInset = true
	dimGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local baseGui = if parent:IsA("ScreenGui") then parent else parent:FindFirstAncestorWhichIsA("ScreenGui")
	dimGui.DisplayOrder = (if baseGui then (baseGui :: ScreenGui).DisplayOrder else 0) - 1
	local dimFull = Instance.new("Frame")
	dimFull.Name = "Dim"
	dimFull.BackgroundColor3 = Color3.new(0, 0, 0)
	dimFull.BorderSizePixel = 0
	dimFull.Size = UDim2.fromScale(1, 1)
	dimFull.BackgroundTransparency = dim.BackgroundTransparency
	dimFull.Active = false
	dimFull.Parent = dimGui
	dimGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	dim:GetPropertyChangedSignal("BackgroundTransparency"):Connect(function()
		dimFull.BackgroundTransparency = dim.BackgroundTransparency
	end)
	root.Destroying:Connect(function()
		dimGui:Destroy()
	end)

	local vignette = image(root, "vignette", 50)
	vignette.Position = UDim2.fromScale(0.5, 0.5)
	vignette.Size = UDim2.fromScale(1.15, 1.15)
	vignette.ImageColor3 = Color3.new(0, 0, 0)
	vignette.ImageTransparency = 1

	local stage = Instance.new("Frame")
	stage.Name = "Stage"
	stage.BackgroundTransparency = 1
	stage.Size = UDim2.fromScale(1, 1)
	stage.ZIndex = 51
	stage.Active = false
	stage.Parent = root

	local cx, cy = 0.5, 0.45
	local function center(): Vector2 return Vector2.new(unit.X * cx, unit.Y * cy) end

	-- Lichtkranz + Strahlen (Rarity-Farbe, wachsen mit der Stufe)
	local halo = Instance.new("Frame")
	halo.Name = "Halo"
	halo.BackgroundColor3 = C.honey
	halo.BackgroundTransparency = 1
	halo.AnchorPoint = Vector2.new(0.5, 0.5)
	halo.Position = UDim2.fromScale(cx, cy)
	halo.Size = UDim2.fromOffset(minSide * 0.8, minSide * 0.8)
	halo.ZIndex = 51
	halo.Active = false
	halo.Parent = stage
	local haloCorner = Instance.new("UICorner")
	haloCorner.CornerRadius = UDim.new(0.5, 0)
	haloCorner.Parent = halo

	local rayLayers: { ImageLabel } = {}
	for i = 1, tier.rays do
		local ray = image(stage, "rays", 51)
		ray.Position = UDim2.fromScale(cx, cy)
		local s = minSide * (1.1 + 0.35 * i)
		ray.Size = UDim2.fromOffset(s, s)
		ray.ImageColor3 = if i % 2 == 0 then C.honey else accent
		ray.ImageTransparency = 1
		ray.Rotation = i * 17
		table.insert(rayLayers, ray)
	end

	-- Ei: Halter (wackelt/hoppt/quetscht), darin Modell-Ansicht oder Ellipse als Rueckfall
	local eggSize = minSide * G.eggFraction
	local eggHolder = Instance.new("Frame")
	eggHolder.Name = "Egg"
	eggHolder.BackgroundTransparency = 1
	eggHolder.AnchorPoint = Vector2.new(0.5, 0.88)
	eggHolder.Position = UDim2.fromScale(cx, cy + 0.2)
	eggHolder.Size = UDim2.fromOffset(0, 0)
	eggHolder.ZIndex = 53
	eggHolder.Active = false
	eggHolder.Parent = stage

	local template = EggModels.getTemplate(params.eggType)
	local eggCamera: Camera? = nil
	if template then
		local view = Instance.new("ViewportFrame")
		view.Name = "EggView"
		view.BackgroundTransparency = 1
		view.Size = UDim2.fromScale(1, 1)
		view.ZIndex = 53
		view.Ambient = Color3.fromRGB(190, 190, 200)
		view.LightColor = Color3.new(1, 1, 1)
		view.LightDirection = Vector3.new(-0.4, -0.7, -0.6)
		local clone = template:Clone()
		clone:PivotTo(CFrame.new())
		clone.Parent = view
		local primary = clone.PrimaryPart
		local cf, size = clone:GetBoundingBox()
		local front = if primary then primary.CFrame.LookVector else Vector3.new(0, 0, -1)
		local camera = Instance.new("Camera")
		camera.FieldOfView = G.fovBase
		-- 21.10. Playtest: Beim Mist Egg sass das Ei nicht mittig im Kreis und die Risse
		-- hingen daneben. Grund: Die Huelle (GetBoundingBox) ragt bei manchen Eiern seitlich
		-- ueber den Koerper hinaus (Mist: 0,2 Studs), die Kamera zielte auf deren Mitte.
		-- Jetzt wird nur seitlich auf den Ei-Koerper (PrimaryPart) zentriert; Hoehe/Tiefe
		-- bleiben wie bisher, damit die anderen Eier unveraendert aussehen.
		local target = cf.Position
		if primary then
			local right = primary.CFrame.RightVector
			target = cf.Position - right * (cf.Position - primary.Position):Dot(right)
		end
		camera.CFrame = CFrame.lookAt(target + front * size.Y * 2.1 + Vector3.new(0, size.Y * 0.1, 0), target)
		camera.Parent = view
		view.CurrentCamera = camera
		eggCamera = camera
		view.Parent = eggHolder
	else
		local def = EggConfig.data[params.eggType :: any]
		local blob = Instance.new("Frame")
		blob.BackgroundColor3 = if def then def.color else C.cream
		blob.AnchorPoint = Vector2.new(0.5, 0.5)
		blob.Position = UDim2.fromScale(0.5, 0.5)
		blob.Size = UDim2.fromScale(0.62, 0.8)
		blob.ZIndex = 53
		blob.Active = false
		blob.Parent = eggHolder
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = blob
		local stroke = Instance.new("UIStroke")
		stroke.Color = C.choco
		stroke.Thickness = 4
		stroke.Parent = blob
	end

	-- Risse: Leuchtlage in Rarity-Farbe + weisser Kern, drei Stufen
	local crackGlow: ImageLabel = image(eggHolder, "crack1", 55)
	crackGlow.Position = UDim2.fromScale(0.5, 0.52)
	crackGlow.Size = UDim2.fromScale(1.0, 1.0)
	crackGlow.ImageColor3 = accent
	crackGlow.ImageTransparency = 1
	local crackCore: ImageLabel = image(eggHolder, "crack1", 56)
	crackCore.Position = crackGlow.Position
	crackCore.Size = UDim2.fromScale(0.94, 0.94)
	crackCore.ImageTransparency = 1
	local crackStage = 0
	local function setCrackStage(n: number)
		crackStage = n
		if n == 1 then giveHint() end   -- erster Rarity-Hinweis: Riss leuchtet in Rarity-Farbe
		local key = "crack" .. n
		crackGlow.Image = (Cfg.ASSETS :: any)[key]
		crackCore.Image = (Cfg.ASSETS :: any)[key]
		crackGlow.ImageTransparency = 0.1
		crackCore.ImageTransparency = 0
	end

	-- Blitz
	local flashFrame = Instance.new("Frame")
	flashFrame.BackgroundColor3 = Color3.new(1, 1, 1)
	flashFrame.BackgroundTransparency = 1
	flashFrame.BorderSizePixel = 0
	flashFrame.Size = UDim2.fromScale(1, 1)
	flashFrame.ZIndex = 60
	flashFrame.Active = false
	flashFrame.Parent = root

	----------------------------------------------------------------------------
	-- Partikel (ein kleiner Pool; alle in der einen Schleife bewegt)
	----------------------------------------------------------------------------
	local function emit(kind: string, count: number, origin: Vector2, speed: number, color: Color3?, lifeMul: number?)
		local n = math.max(1, math.floor(count * pFactor))
		for _ = 1, n do
			local gui: GuiObject
			local size = 10 + math.random() * 16
			local life = (0.6 + math.random() * 0.5) * (lifeMul or 1)
			local gravity = 0
			if kind == "spark" then
				local img = image(stage, "glint", 58)
				img.ImageColor3 = if math.random() < 0.4 then Color3.new(1, 1, 1) else (color or C.honey)
				gui = img
			elseif kind == "paw" then
				local img = image(stage, "paw", 57)
				img.ImageColor3 = color or C.honey
				gui = img
				size = 22 + math.random() * 14
				gravity = 260
			elseif kind == "drop" then
				local img = image(stage, "drop", 57)
				img.ImageColor3 = C.honey
				gui = img
				size = 16 + math.random() * 12
				gravity = 520
			elseif kind == "shard" then
				local img = image(stage, "shards", 59)
				local cell = Cfg.SHARD_CELLS[math.random(1, #Cfg.SHARD_CELLS)]
				img.ImageRectOffset = cell
				img.ImageRectSize = Vector2.new(Cfg.SHARD_CELL, Cfg.SHARD_CELL)
				img.ImageColor3 = if math.random() < 0.5 then C.cream else C.honey
				gui = img
				size = 38 + math.random() * 40
				gravity = 700
			else -- confetti
				local fr = Instance.new("Frame")
				fr.BorderSizePixel = 0
				fr.AnchorPoint = Vector2.new(0.5, 0.5)
				fr.BackgroundColor3 = ({ color or accent, C.honey, C.cream, Color3.new(1, 1, 1) })[math.random(1, 4)]
				fr.ZIndex = 58
				fr.Active = false
				fr.Parent = stage
				gui = fr
				size = 8 + math.random() * 8
				gravity = 640
			end
			local angle = math.random() * math.pi * 2
			local sp = speed * (0.4 + math.random() * 0.8)
			if kind == "confetti" then angle = -math.pi / 2 + (math.random() - 0.5) * 2.4 end
			gui.Size = UDim2.fromOffset(size, if kind == "confetti" then size * 1.5 else size)
			gui.Position = UDim2.fromOffset(origin.X, origin.Y)
			table.insert(particles, {
				gui = gui, x = origin.X, y = origin.Y,
				vx = math.cos(angle) * sp, vy = math.sin(angle) * sp,
				age = 0, life = life, rot = math.random() * 360, vr = (math.random() - 0.5) * 720,
				size = size, grow = if kind == "spark" then -0.6 else 0, gravity = gravity, fade = true,
			})
		end
	end

	local function updateParticles(dt: number)
		local i = 1
		while i <= #particles do
			local p = particles[i]
			p.age += dt
			if p.age >= p.life or not p.gui.Parent then
				p.gui:Destroy()
				table.remove(particles, i)
			else
				p.vy += p.gravity * dt
				p.x += p.vx * dt
				p.y += p.vy * dt
				p.rot += p.vr * dt
				local k = p.age / p.life
				p.gui.Position = UDim2.fromOffset(p.x, p.y)
				p.gui.Rotation = p.rot
				local s = p.size * (1 + p.grow * k)
				p.gui.Size = UDim2.fromOffset(s, if p.gui:IsA("Frame") then s * 1.5 else s)
				if p.gui:IsA("ImageLabel") then
					p.gui.ImageTransparency = if k > 0.6 then (k - 0.6) / 0.4 else 0
				else
					p.gui.BackgroundTransparency = if k > 0.6 then (k - 0.6) / 0.4 else 0
				end
				i += 1
			end
		end
	end

	----------------------------------------------------------------------------
	-- Zustand der Zeitlinie
	----------------------------------------------------------------------------
	local t = 0                 -- Szenenzeit (haelt beim Hit-Stop, laeuft bei Slow-Mo langsamer)
	local real = 0              -- echte Zeit seit Start
	local burstDone = false
	local hitStopLeft = 0
	local impactDone = { false, false, false }
	local impactAt = { 0, 0, 0 }
	local punch = 0             -- FOV-Schlag, klingt ab
	local shakeLeft = 0
	local ringGui: ImageLabel? = nil
	local ringT = -1
	local pulse2Done = false
	local slowStart, slowEnd = -1, -1
	local revealBuilt = false
	local revealT0 = 0
	local infoParts: { [string]: GuiObject } = {}
	local petView: ViewportFrame? = nil
	local petScale: UIScale? = nil
	local closing = false
	local closeT = 0
	local shineImg: ImageLabel? = nil

	for k = 1, 3 do impactAt[k] = tAppear + (k - 1) * interval + interval * 0.6 end

	-- 21.10. Playtest-Bug "Animation wird uebersprungen": Wer auf onFinished:Wait()
	-- wartet, kann das Signal verlieren (Fire + sofortiges Destroy des BindableEvents).
	-- Darum zusaetzlich das Feld handle.finished, das man abfragen kann.
	local handleRef: any = nil

	local function finish()
		if finished then return end
		finished = true
		if handleRef then handleRef.finished = true end
		finishedEvent:Fire()
	end

	local function destroy()
		if destroyed then return end
		destroyed = true
		stopShimmer()
		for _, c in connections do c:Disconnect() end
		table.clear(connections)
		if cleanupPet then cleanupPet() cleanupPet = nil end
		for _, p in particles do p.gui:Destroy() end
		table.clear(particles)
		root:Destroy()
		finish()
		-- nicht sofort zerstoeren: sonst kann ein wartender Thread das Signal verpassen
		task.delay(2, function() finishedEvent:Destroy() end)
	end

	local function doFlash(strength: number, seconds: number)
		flashFrame.BackgroundTransparency = 1 - strength
		flashFrame:SetAttribute("FlashT", 0)
		flashFrame:SetAttribute("FlashD", seconds)
		flashFrame:SetAttribute("FlashS", strength)
	end

	local function doRing(scaleMul: number)
		local r = ringGui or image(stage, "ring", 58)
		ringGui = r
		r.Position = UDim2.fromScale(cx, cy)
		r.ImageColor3 = accent
		r:SetAttribute("Mul", scaleMul)
		ringT = 0
	end

	local function buildReveal()
		revealBuilt = true
		revealT0 = t
		eggHolder.Visible = false
		crackGlow.Visible = false
		crackCore.Visible = false
		if params.burstOnly then
			giveHint()
			stopShimmer()
			finish()
			return
		end
		giveHint()
		shimmer:pulse()   -- Top-Stufen: ein kurzer Extra-Puls beim Reveal
		local petSize = minSide * G.petFraction
		local view = Instance.new("ViewportFrame")
		view.Name = "PetView"
		view.BackgroundTransparency = 1
		view.AnchorPoint = Vector2.new(0.5, 0.5)
		view.Position = UDim2.fromScale(cx, cy - 0.02)
		view.Size = UDim2.fromOffset(petSize, petSize)
		view.ZIndex = 54
		view.Ambient = Color3.fromRGB(200, 200, 210)
		view.LightColor = Color3.fromRGB(255, 250, 235)
		view.Parent = stage
		local scale = Instance.new("UIScale")
		scale.Scale = 0.4
		scale.Parent = view
		petView = view
		petScale = scale
		local mutationColor = if params.mutation then BaerchiConfig.getMutationColor(params.mutation :: any) else nil
		local okModel, model = pcall(function()
			return BaerchiMesh.build(Vector3.zero, accent, params.rarity :: any, mutationColor, params.configId)
		end)
		if okModel and model then
			local born = os.clock()
			cleanupPet = EggHatch.attachPet(view, model, {
				sway = true,
				-- einmal elegant drehen und in der Vorderansicht ankommen
				yaw = function(_) 
					local k = clamp01((os.clock() - born) / math.max(revealIn, 0.2))
					return (1 - easeOutCubic(k)) * math.pi * 2
				end,
				lift = function(_)
					local k = clamp01((os.clock() - born) / math.max(revealIn * 0.8, 0.2))
					return -(1 - easeOutBack(k)) * 0.9
				end,
			})
		end

		-- Info-Elemente
		local function label(name: string, text: string, y: number, h: number, color: Color3, z: number): TextLabel
			local l = Instance.new("TextLabel")
			l.Name = name
			l.BackgroundTransparency = 1
			l.AnchorPoint = Vector2.new(0.5, 0)
			l.Position = UDim2.fromScale(cx, y)
			l.Size = UDim2.fromOffset(math.clamp(unit.X * 0.6, 260, 520), h)
			l.Font = Enum.Font.FredokaOne
			l.Text = text
			l.TextColor3 = color
			l.TextScaled = true
			l.TextTransparency = 1
			l.ZIndex = z
			l.Active = false
			l.Parent = stage
			local limit = Instance.new("UITextSizeConstraint")
			limit.MaxTextSize = math.floor(h * 0.9)
			limit.MinTextSize = 10
			limit.Parent = l
			local stroke = Instance.new("UIStroke")
			stroke.Color = C.choco
			stroke.Thickness = 3
			stroke.Transparency = 1
			stroke.Parent = l
			return l
		end
		local mutationColor2 = mutationColor
		local color = mutationColor2 or accent
		local title = (if params.mutation then Loc.name("mutation." .. params.mutation .. ".name", BaerchiConfig.getMutationDisplayName(params.mutation :: any)):upper() .. "  " else "")
			.. Names.baerchi(params.configId)
		infoParts.title = label("Title", title, 0.69, 40, color, 62)

		-- Rarity-Banner mit einmaligem Glanzstreifen
		local banner = Instance.new("Frame")
		banner.Name = "Banner"
		banner.AnchorPoint = Vector2.new(0.5, 0)
		banner.Position = UDim2.fromScale(cx, 0.69)
		banner.Size = UDim2.fromOffset(math.clamp(unit.X * 0.38, 200, 360), 34)
		banner.BackgroundColor3 = accent
		banner.BackgroundTransparency = 1
		banner.BorderSizePixel = 0
		banner.ClipsDescendants = true
		banner.ZIndex = 61
		banner.Active = false
		banner.Parent = stage
		local bc = Instance.new("UICorner")
		bc.CornerRadius = UDim.new(0, 10)
		bc.Parent = banner
		local bs = Instance.new("UIStroke")
		bs.Color = C.choco
		bs.Thickness = 3
		bs.Transparency = 1
		bs.Parent = banner
		infoParts.banner = banner
		local bannerText = Instance.new("TextLabel")
		bannerText.BackgroundTransparency = 1
		bannerText.Size = UDim2.fromScale(1, 1)
		bannerText.Font = Enum.Font.FredokaOne
		bannerText.Text = string.upper(Loc.t("rarity." .. params.rarity))
		bannerText.TextColor3 = Color3.new(1, 1, 1)
		bannerText.TextScaled = true
		bannerText.TextTransparency = 1
		bannerText.ZIndex = 63
		bannerText.Parent = banner
		local bt = Instance.new("UITextSizeConstraint"); bt.MaxTextSize = 24; bt.MinTextSize = 10; bt.Parent = bannerText
		local btStroke = Instance.new("UIStroke"); btStroke.Color = C.choco; btStroke.Thickness = 2; btStroke.Transparency = 1; btStroke.Parent = bannerText
		infoParts.bannerText = bannerText
		local shine = image(banner, "shine", 64)
		shine.Size = UDim2.fromScale(0.7, 1.4)
		shine.Position = UDim2.fromScale(-0.5, 0.5)
		shine.ImageTransparency = 0.1
		shine.Visible = false
		shineImg = shine

		-- Level / Ei (und Mutations-Faktor) in einer Zeile
		local sub = Loc.t("ui.hatch.sub", {
			level = params.level,
			mutation = if params.mutation then string.format("  •  %s x%.2g", Loc.name("mutation." .. params.mutation .. ".name", BaerchiConfig.getMutationDisplayName(params.mutation :: any)), BaerchiConfig.getMutationMultiplier(params.mutation :: any)) else "",
			egg = Loc.name("egg." .. params.eggType .. ".name", params.eggType),
		})
		local subLabel = label("Sub", sub, 0.76, 26, C.cream, 62)
		subLabel.Font = Enum.Font.GothamBold
		infoParts.sub = subLabel
		infoParts.tap = label("Tap", Loc.t("ui.hatch.tap_close"), 0.92, 18, C.cream, 62)
		local tapLabel = infoParts.tap :: TextLabel
		tapLabel.Font = Enum.Font.GothamMedium

		if params.isNew then
			local new = label("New", Loc.t("ui.hatch.new"), 0.16, 34, C.honey, 62)
			new.Position = UDim2.fromScale(cx, 0.16)
			infoParts.new = new
		end

		emit("confetti", tier.confetti, center() + Vector2.new(0, -minSide * 0.3), minSide * 1.1, accent, 1.6)
		emit("spark", tier.particles * 0.5, center(), minSide * 0.9, accent)
		playSound(Cfg.SOUNDS.reveal[tier.sound])
	end

	local function doBurst()
		burstDone = true
		giveHint()   -- Rueckfall, falls uebersprungen wurde, bevor ein Riss kam
		hitStopLeft = tier.hitStop * (if fast then 0.6 else 1)
		doFlash(0.95, 0.35)
		doRing(1)
		shakeLeft = 0.45
		eggHolder.Visible = false
		crackGlow.Visible = false
		crackCore.Visible = false
		emit("shard", 10, center(), minSide * 1.0)
		emit("spark", tier.particles, center(), minSide * 1.3, accent)
		emit("drop", 8, center(), minSide * 0.8)
		emit("paw", 6, center(), minSide * 0.9, accent)
		for i, ray in rayLayers do
			ray:SetAttribute("On", real)
		end
		playSound(Cfg.SOUNDS.burst[tier.sound])
	end

	-- Kino-Szene (Video): ersetzt Ei und Aufbruch, endet im Weiss-Blitz und geht in den Reveal
	local cin = Cfg.CINEMATIC
	local video: VideoFrame? = nil
	local cinematicState = "off"   -- "loading" | "playing" | "off"
	local vStart = 0
	if not fast and not params.burstOnly and rIndex >= cin.fromIndex and cin.videoId ~= "" then
		local v = Instance.new("VideoFrame")
		v.Name = "Cinematic"
		v.Video = cin.videoId
		v.Looped = false
		v.Volume = cin.volume
		v.BackgroundColor3 = Color3.new(0, 0, 0)
		v.BorderSizePixel = 0
		v.Size = UDim2.fromScale(1, 1)
		v.ZIndex = 52
		v.Active = false
		v.Visible = false
		v.Parent = root
		video = v
		cinematicState = "loading"
		eggHolder.Visible = false
		halo.Visible = false
		for _, ray in rayLayers do ray.Visible = false end
	end

	local function endCinematic(toReveal: boolean)
		local v = video
		cinematicState = "off"
		if v then
			pcall(function() v:Pause() end)
			v:Destroy()
			video = nil
		end
		halo.Visible = true
		for _, ray in rayLayers do ray.Visible = true end
		if toReveal and not revealBuilt then
			burstDone = true
			t = tReveal
			doFlash(1, 0.6)
			buildReveal()
		else
			eggHolder.Visible = true   -- Laden fehlgeschlagen: normale Animation von vorn
			t = 0
		end
	end

	local function skipNow()
		if cinematicState ~= "off" then
			endCinematic(true)
			return
		end
		if finished and not params.burstOnly then return end
		if not revealBuilt then
			-- direkt zur Enthuellung: Rest der Vorbereitung ueberspringen
			if not burstDone then
				t = tBurst
				doBurst()
			end
			t = tReveal
			hitStopLeft = 0
			buildReveal()
		end
	end

	root.Activated:Connect(function()
		if destroyed then return end
		if not revealBuilt then
			if real >= G.skipAfter * (if fast then G.fastFactor else 1) then skipNow() end
		elseif not params.burstOnly and not closing and (t - revealT0) >= G.revealTapDelay then
			closing = true
			closeT = 0
		end
	end)

	-- Einstellung "Schnell" (Chip oben rechts)
	local fastChip = Instance.new("TextButton")
	fastChip.Name = "FastChip"
	fastChip.AnchorPoint = Vector2.new(1, 0)
	fastChip.Position = UDim2.new(1, -14, 0, 14)
	fastChip.Size = UDim2.fromOffset(104, 34)
	fastChip.Font = Enum.Font.FredokaOne
	fastChip.TextSize = 18
	fastChip.ZIndex = 65
	fastChip.AutoButtonColor = false
	fastChip.Parent = root
	local fcCorner = Instance.new("UICorner"); fcCorner.CornerRadius = UDim.new(0, 12); fcCorner.Parent = fastChip
	local fcStroke = Instance.new("UIStroke"); fcStroke.Color = C.choco; fcStroke.Thickness = 3; fcStroke.Parent = fastChip
	local function paintChip()
		fastChip.Text = "⏩ " .. Loc.t("ui.hatch.fast")
		fastChip.BackgroundColor3 = if EggHatch.fast then C.honey else Color3.fromRGB(110, 90, 70)
		fastChip.TextColor3 = if EggHatch.fast then C.choco else C.cream
	end
	paintChip()
	fastChip.Activated:Connect(function()
		EggHatch.fast = not EggHatch.fast
		paintChip()
	end)
	if params.burstOnly then fastChip.Visible = false end

	----------------------------------------------------------------------------
	-- Die eine Schleife
	----------------------------------------------------------------------------
	local function frame(dtReal: number)
		if destroyed then return end
		real += dtReal

		-- Hit-Stop / Slow-Mo bestimmen die Szenenzeit
		local scale = 1
		if hitStopLeft > 0 then
			hitStopLeft -= dtReal
			scale = 0
		elseif tier.slowMo and revealBuilt and slowStart >= 0 and t >= slowStart and t < slowEnd then
			scale = G.slowMoScale
		end
		local dt = dtReal * scale
		t += dt

		updateParticles(dtReal)

		-- Kino-Szene
		if cinematicState == "loading" then
			local v = video
			if v and v.IsLoaded then
				cinematicState = "playing"
				giveHint()
				vStart = real
				v.Visible = true
				v:Play()
			elseif real >= cin.loadTimeout then
				endCinematic(false)   -- Video nicht ladbar: normale Animation
			end
			return
		elseif cinematicState == "playing" then
			local v = video
			local vt = real - vStart
			if not v or vt >= cin.revealAt or (v.TimeLength > 0 and v.TimePosition >= v.TimeLength - 0.05) then
				endCinematic(true)
			end
			return
		end

		-- Blitz ausblenden
		local fs = flashFrame:GetAttribute("FlashS")
		if typeof(fs) == "number" then
			local ft = (flashFrame:GetAttribute("FlashT") :: number) + dtReal
			local fd = flashFrame:GetAttribute("FlashD") :: number
			flashFrame:SetAttribute("FlashT", ft)
			flashFrame.BackgroundTransparency = 1 - fs * (1 - clamp01(ft / fd))
		end
		-- Ring
		if ringGui and ringT >= 0 then
			ringT += dtReal
			local k = clamp01(ringT / 0.55)
			local mul = (ringGui:GetAttribute("Mul") :: number) or 1
			local s = minSide * (0.15 + 1.3 * easeOutCubic(k)) * mul
			ringGui.Size = UDim2.fromOffset(s, s)
			ringGui.ImageTransparency = k
			if k >= 1 then ringT = -1 end
		end
		-- Strahlen
		for i, ray in rayLayers do
			local on = ray:GetAttribute("On")
			if typeof(on) == "number" then
				local k = clamp01((real - on) / 0.3)
				ray.ImageTransparency = 1 - 0.85 * k * (1 - 0.25 * (i - 1))
				ray.Rotation += dtReal * (14 + 9 * i) * (if i % 2 == 0 then -1 else 1)
			end
		end
		-- Bildschirmzittern
		if shakeLeft > 0 and tier.shake > 0 then
			shakeLeft -= dtReal
			local amp = tier.shake * clamp01(shakeLeft / 0.45)
			stage.Position = UDim2.fromOffset(math.random(-amp, amp), math.random(-amp, amp))
		elseif stage.Position ~= UDim2.new() then
			stage.Position = UDim2.new()
		end

		-- Abblenden und Schliessen
		if closing then
			stopShimmer()   -- Ergebnis wird geschlossen: Schimmer blendet ca. 0,4 s aus
			closeT += dtReal
			local k = clamp01(closeT / 0.3)
			local view = petView
			if view then
				view.Position = UDim2.fromScale(cx, cy - 0.02 + 0.55 * k * k)
				if petScale then petScale.Scale = 1 - 0.8 * k end
			end
			dim.BackgroundTransparency = (1 - G.dimAlpha) + G.dimAlpha * k
			for _, part in infoParts do
				if part:IsA("TextLabel") then part.TextTransparency = k end
			end
			if k >= 1 then
				destroy()
			end
			return
		end

		if not revealBuilt then
			-- Abdunkeln und Lichtkranz
			dim.BackgroundTransparency = 1 - G.dimAlpha * clamp01(t / math.max(tAppear, 0.05))
			vignette.ImageTransparency = 1 - 0.8 * clamp01(t / math.max(tAppear, 0.05))
			halo.BackgroundTransparency = 1 - 0.28 * clamp01(t / math.max(tAppear, 0.05))
			halo.Size = UDim2.fromOffset(minSide * (0.8 + 0.1 * math.sin(real * 3)), minSide * (0.8 + 0.1 * math.sin(real * 3)))

			-- 1. Erscheinen: Pop mit Squash & Stretch
			local x = clamp01(t / math.max(tAppear, 0.05))
			local pop = easeOutBack(x)
			local squash = 1 + 0.18 * math.sin(x * math.pi) * (1 - x)
			local w = eggSize * pop / squash
			local h = eggSize * pop * squash
			local hop = 0
			local roll = 0

			-- 2. Aufladen: drei Schlaege
			for k = 1, 3 do
				local t0 = tAppear + (k - 1) * interval
				if t >= t0 and t < t0 + interval then
					local u = (t - t0) / interval
					local amp = 4 + 4 * k
					if u < 0.6 then
						-- Ausholen
						roll = -amp * 0.7 * math.sin(u / 0.6 * math.pi / 2)
						h *= 1 - 0.05 * (u / 0.6) * k
					else
						local v = u - 0.6
						roll = amp * math.exp(-5 * v) * math.cos(v * 24)
						hop = -eggSize * 0.06 * k * math.sin(math.clamp(v * 7, 0, math.pi))
					end
					if u >= 0.6 and not impactDone[k] then
						impactDone[k] = true
						setCrackStage(k)
						punch = 1
						emit("spark", tier.particles * 0.3, center() + Vector2.new(0, eggSize * 0.05), minSide * 0.55, accent)
						emit("drop", 2 + k, center(), minSide * 0.4)
						playSound(Cfg.SOUNDS.crack)
					end
				end
			end
			if t >= tAppear and t < tAppear + 0.02 then playSound(Cfg.SOUNDS.wobble) end

			punch = math.max(0, punch - dtReal * 4)
			if eggCamera then eggCamera.FieldOfView = G.fovBase - G.fovPunch * punch end
			eggHolder.Size = UDim2.fromOffset(math.max(w, 0), math.max(h, 0))
			eggHolder.Rotation = roll
			eggHolder.Position = UDim2.fromScale(cx, cy + 0.2) + UDim2.fromOffset(0, hop)
			if t < 0.02 then playSound(Cfg.SOUNDS.appear) end

			-- 3. Aufbruch
			if t >= tBurst and not burstDone then
				doBurst()
			end
			if burstDone and t >= tReveal and not revealBuilt then
				buildReveal()
			end
		else
			-- 4. Enthuellung
			local tr = t - revealT0
			if burstDone then
				dim.BackgroundTransparency = 1 - G.dimAlpha
				halo.BackgroundTransparency = 1 - 0.28 * clamp01(1 - tr / 1.2)
			end
			local petS = petScale
			if petS then petS.Scale = 0.4 + 0.6 * easeOutBack(clamp01(tr / math.max(revealIn * 0.8, 0.1))) end
			if tier.slowMo and slowStart < 0 then
				slowStart = revealT0 + revealIn * 0.35
				slowEnd = slowStart + G.slowMoSeconds
			end
			if tier.secondPulse and not pulse2Done and tr >= revealIn * 0.9 then
				pulse2Done = true
				shimmer:pulse()
				doFlash(0.7, 0.5)
				doRing(1.7)
				shakeLeft = 0.45
				emit("confetti", tier.confetti, center() + Vector2.new(0, -minSide * 0.3), minSide * 1.3, accent, 1.8)
				playSound(Cfg.SOUNDS.burst.high)
			end
			-- Info einblenden (gestaffelt)
			local function fade(part: GuiObject?, delay: number)
				if not part then return end
				local a = clamp01((tr - delay) / 0.25)
				if part:IsA("TextLabel") then
					part.TextTransparency = 1 - a
					local st = part:FindFirstChildOfClass("UIStroke")
					if st then st.Transparency = 1 - a end
				elseif part:IsA("Frame") then
					part.BackgroundTransparency = 1 - a
					local st = part:FindFirstChildOfClass("UIStroke")
					if st then st.Transparency = 1 - a end
				end
			end
			local title = infoParts.title
			local banner = infoParts.banner
			-- Titel steht ueber dem Banner: Banner direkt darunter schieben
			if title and banner then
				title.Position = UDim2.fromScale(cx, 0.65)
				banner.Position = UDim2.fromScale(cx, 0.65) + UDim2.fromOffset(-0, 46)
				infoParts.sub.Position = UDim2.fromScale(cx, 0.65) + UDim2.fromOffset(0, 46 + 42)
			end
			fade(title, 0.35)
			fade(banner, 0.5)
			local bt = infoParts.bannerText
			if bt then
				local a = clamp01((tr - 0.5) / 0.25)
				local btLabel = bt :: TextLabel
				btLabel.TextTransparency = 1 - a
				local st = bt:FindFirstChildOfClass("UIStroke")
				if st then st.Transparency = 1 - a end
			end
			fade(infoParts.sub, 0.7)
			fade(infoParts.new, 0.6)
			fade(infoParts.tap, 1.2)
			local shine = shineImg
			if shine and tr >= 0.75 then
				shine.Visible = true
				local k = clamp01((tr - 0.75) / 0.6)
				shine.Position = UDim2.fromScale(-0.4 + 1.8 * k, 0.5)
			end
			if infoParts.new then
				local s = 1 + 0.06 * math.sin(real * 6)
				infoParts.new.Rotation = -6 + 3 * math.sin(real * 4)
				infoParts.new.Size = UDim2.fromOffset(math.clamp(unit.X * 0.6, 260, 520) * s, 34 * s)
			end
			if tr >= G.revealAutoClose and not closing then
				closing = true
				closeT = 0
			end
		end
	end

	table.insert(connections, RunService.RenderStepped:Connect(frame))
	table.insert(connections, Players.LocalPlayer.AncestryChanged:Connect(function()
		stopShimmer(true)
		destroy()
	end))
	EggHatch.preload()

	local handle: Handle = {
		root = root,
		stage = stage,
		skip = skipNow,
		destroy = destroy,
		onFinished = finishedEvent.Event,
		finished = false,
	}
	handleRef = handle
	return handle
end

return EggHatch
