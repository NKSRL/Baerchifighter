--!strict
-- EggTreePanel.luau
-- StarterPlayerScripts/UI/EggTreePanel.luau
--
-- v14 (Mega Egg Tree, WP5) — Bilderbuch-Fassung: das Ei-Baum-Fenster als
-- echter, magischer Baum.
--
-- Links der Baum (UI/EggTreeLayout): dicker Stamm unten in der Mitte,
-- geschwungene Aeste je Pfad mit eigener Textur (Gold metallisch, Kristall
-- durchscheinend, Void mit Glut in den Ritzen, Kosmos voller Sterne), die
-- Eier in Bluetenkelchen. Jeder Knoten hat drei Zustaende:
--   gesperrt        dunkle Silhouette im geschlossenen Kelch, Ast grau, Schloss
--   freischaltbar   Ei pulsiert, Honiglicht kriecht den Ast zum Kelch
--                   (Elternknoten frei bzw. alle Bedingungen erfuellt)
--   freigeschaltet  volle Farbe, Ast leuchtet, offener Kelch mit Blaettern
-- Beim Freischalten laeuft eine Lichtwelle vom Stammfuss den Ast hoch, der
-- Kelch oeffnet sich, das Ei springt und landet mit einem Funkenring.
--
-- Rechts (bzw. auf schmalen Bildschirmen als Karte ueber dem Baum) die
-- Detail-Karte: grosses Ei, Pfad, Fortschritt, Bedingungen, Aktionen
-- (Oeffnen, Pressen, Blaupause) und Drop-Vorschau. Mit der Maus zeigt das
-- Darueberfahren eine kleine Infokarte.
--
-- Der Baum ist scroll- und zoombar (Knoepfe, Pinch, Strg + Mausrad).
--
-- Die Bedingungen rechnet Modules/EggTree — dieselbe Funktion, die der
-- Server zum Freischalten benutzt. Das Panel kann also nie etwas anderes
-- anzeigen, als der Server tut. Es aktualisiert sich live ueber ClientState.
--
-- Alle Bilder kommen ueber Icons.luau; ohne hochgeladene IDs zeichnet das
-- Panel einfache Frames (gleiche Bedienung, schlichter Look).
--
-- Freischalt-Animation testen (Studio, Client-Befehlsleiste):
--   game.Players.LocalPlayer:SetAttribute("EggTreeTestUnlock", "GoldenEgg")
-- oder bei offenem Baum in Studio die Taste U (spielt den gewaehlten Knoten).

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local Players           = game:GetService("Players")

local Types           = require(ReplicatedStorage.Network.Types)
local Remotes         = require(ReplicatedStorage.Network.Remotes)
local Loc             = require(ReplicatedStorage.Localization.Loc)
local Names           = require(ReplicatedStorage.Localization.Names)
local EggConfig       = require(ReplicatedStorage.Config.EggConfig)
local BaerchiConfig   = require(ReplicatedStorage.Config.BaerchiConfig)
local EggTree         = require(ReplicatedStorage.Modules.EggTree)
local IndexCalculator = require(ReplicatedStorage.Modules.IndexCalculator)

local Theme          = require(script.Parent.Theme)
local Icons          = require(script.Parent.Icons)
local EggIcon        = require(script.Parent.EggIcon)
local Layout         = require(script.Parent.EggTreeLayout)
local PanelManager   = require(script.Parent.PanelManager)
local EggPanelSkin = require(script.Parent.EggPanelSkin)   -- 13.10.: Honig-Template
local HatchAnimation = require(script.Parent.HatchAnimation)
local ClientState    = require(script.Parent.Parent.Controllers.ClientState)
local PetCapacity = require(game:GetService("ReplicatedStorage").Modules.PetCapacity)   -- 19.10.: Pet-Limit
local Toast = require(script.Parent.Toast)

local EggTreePanel = {}

local PANEL_NAME = "EggTree"
EggTreePanel.PANEL_NAME = PANEL_NAME

local DETAIL_W  = 290
local NARROW_W  = 860     -- schmaler (Handy quer): Detail als Karte ueber dem Baum
local SEG_STEP  = 26      -- Laenge der Ast-Stuecke (Design-Pixel)
local EGG_H     = Layout.EGG_HEIGHT
local NODE_FOOT = 0.82   -- Eifuss im Kelch (Anteil der Kelchhoehe)
local WAVE_SPEED = 900    -- Design-Pixel pro Sekunde

local HONEY_LIGHT = Color3.fromRGB(255, 206, 96)
local WAVE_LIGHT  = Color3.fromRGB(255, 246, 214)

local BRANCH_TEXTURE: { [string]: string } = {
	Stamm = "tree/branch_stamm", Gold = "tree/branch_gold", Kristall = "tree/branch_kristall",
	Void = "tree/branch_void", Kosmos = "tree/branch_kosmos", Ascension = "tree/branch_ascension",
	Anime = "tree/branch_ascension",
}

-- Ast-Faerbung je Zustand (multipliziert sich auf die Textur)
local FILL_TINT: { [string]: Color3 } = {
	locked = Color3.fromRGB(104, 98, 94),
	ready  = Color3.fromRGB(214, 204, 190),
	open   = Color3.new(1, 1, 1),
}

type State = string   -- "locked" | "ready" | "open"

type SegRec = { fill: GuiObject?, glow: GuiObject, s: number }

type EdgeRec = {
	edge   : Layout.Edge,
	segs   : { SegRec },
	length : number,
	state  : State,
	color  : Color3,
	phase  : number,
}

type NodeRec = {
	eggId     : string,
	frame     : Frame,
	cupBack   : GuiObject?,
	cupFront  : GuiObject?,
	eggHolder : Frame,
	eggScale  : UIScale,
	egg       : Frame,
	lock      : GuiObject,
	name      : TextLabel,
	count     : TextLabel,
	ring      : GuiObject,
	state     : State,
	phase     : number,
	glow      : GuiObject?,
	glowStroke: UIStroke?,
}

-- 19.10.: freie Aeste ("?") und Sprung-Tore
type ExtraRec = {
	id     : string,
	kind   : string,      -- "empty" | "gate"
	branch : string,
	frame  : Frame,
	ring   : GuiObject,
	icon   : GuiObject?,
	state  : State,
	phase  : number,
}

type Wave = { eggId: string, edges: { EdgeRec }, offsets: { number }, total: number, t0: number }

local _root: Frame?            = nil
local _body: Frame?            = nil
local _viewport: Frame?        = nil
local _content: Frame?         = nil
local _zoomScale: UIScale?     = nil
local _detailHost: Frame?      = nil
local _detail: ScrollingFrame? = nil
local _detailClose: TextButton? = nil
local _header: TextLabel?      = nil
local _infoCard: Frame?        = nil
local _fxLayer: Frame?         = nil
local _particles: { { obj: GuiObject, x: number, y: number, vy: number, amp: number, phase: number, size: number } } = {}
local _selected: Types.EggType = "BasicEgg"
local _nodes: { [string]: NodeRec } = {}
local _edges: { [string]: EdgeRec } = {}      -- nach Ziel-Ei
local _links: { { obj: GuiObject, from: string } } = {}
local _narrow = false
local _detailOpen = false
local _loop: RBXScriptConnection? = nil
local _extras: { [string]: ExtraRec } = {}
local _selectedGate: string? = nil          -- gewaehltes Sprung-Tor ("Left" | "Right") statt Ei
local _detailScale: UIScale? = nil
local _known: { [string]: boolean }? = nil    -- zuletzt gesehene Freischaltungen
local _queue: { string } = {}
local _wave: Wave? = nil
local _held: { [string]: State } = {}          -- Knoten in Animation: angezeigter Zustand
local _dropCache: { [string]: { any } } = {}

local function eggName(eggId: string): string
	return Names.egg(eggId)
end

local function rarityName(rarity: string): string
	return Loc.name("rarity." .. rarity, rarity)
end

local function pathName(path: string): string
	return Loc.name("path." .. path, path)
end

local function tween(obj: Instance, time: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local t = TweenService:Create(obj, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function setTransparency(obj: GuiObject, value: number)
	if obj:IsA("ImageLabel") then
		obj.ImageTransparency = value
	else
		obj.BackgroundTransparency = value
	end
end

local function setTint(obj: GuiObject, color: Color3)
	if obj:IsA("ImageLabel") then
		obj.ImageColor3 = color
	else
		obj.BackgroundColor3 = color
	end
end

local function capsule(obj: GuiObject)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = obj
end

local function layer(name: string, parent: Instance, z: number): Frame
	local f = Theme.container(name, parent)
	f.Size = UDim2.fromScale(1, 1)
	f.ZIndex = z
	return f
end

-- Produkt aller UIScales ueber `inst` (GlobalScale, Fenster-Fit ...)
local function ancestorScale(inst: Instance?): number
	local factor = 1
	local node = inst
	while node do
		for _, child in node:GetChildren() do
			if child:IsA("UIScale") then factor *= (child :: UIScale).Scale end
		end
		node = node.Parent
	end
	return math.max(factor, 0.05)
end

local function drops(eggId: string): { any }
	local cached = _dropCache[eggId]
	if cached then return cached end
	local list = {}
	for _, node in IndexCalculator.buildTree() do
		if node.eggId == eggId then list = node.drops end
	end
	_dropCache[eggId] = list
	return list
end

--------------------------------------------------------------------------------
-- Zustand eines Knotens
--------------------------------------------------------------------------------

local function nodeState(data: Types.PlayerDataUpdate, eggId: string, progress: EggTree.NodeProgress): State
	if progress.unlocked then return "open" end
	if progress.ready then return "ready" end
	local def = EggConfig.data[eggId :: Types.EggType]
	if def and def.parent then
		return if EggTree.isUnlocked(data.eggTree, def.parent) then "ready" else "locked"
	end
	local tree = EggConfig.TREE[eggId :: Types.EggType]
	if tree and tree.hatchAnyOf then
		for _, req in tree.hatchAnyOf.of do
			if EggTree.isUnlocked(data.eggTree, req.egg) then return "ready" end
		end
		return "locked"
	end
	return "ready"   -- Pfadanfang ohne Elternei (Ascension: nur Rebirth)
end

local function fraction(progress: EggTree.NodeProgress): number
	if progress.unlocked then return 1 end
	local n, sum = 0, 0
	for _, c in progress.conditions do
		n += 1
		sum += if c.done then 1 else math.clamp(c.have / math.max(1, c.need), 0, 1)
	end
	return if n == 0 then 0 else sum / n
end

local function statusText(state: State, progress: EggTree.NodeProgress): string
	if progress.unlocked then return Loc.t("ui.tree.unlocked") end
	if progress.ready then return Loc.t("ui.tree.ready") end
	if state == "ready" then return Loc.t("ui.tree.reachable") end
	return Loc.t("ui.tree.locked")
end

--------------------------------------------------------------------------------
-- Baum aufbauen (einmalig)
--------------------------------------------------------------------------------

local selectNode: (eggId: string) -> ()
local selectGate: (branch: string) -> ()
local showInfo: (eggId: string?, x: number?, y: number?) -> ()

local function makeRing(frame: Frame): Frame
	local ring = Instance.new("Frame")
	ring.Name = "Select"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(1.24, 1.24)
	ring.BackgroundTransparency = 1
	ring.BorderSizePixel = 0
	ring.ZIndex = 1
	ring.Visible = false
	ring.Parent = frame
	capsule(ring)
	local stroke = Instance.new("UIStroke")
	stroke.Color = WAVE_LIGHT
	stroke.Thickness = 5
	stroke.Transparency = 0.05
	stroke.Parent = ring
	return ring
end

local function makeClick(frame: Frame, onClick: () -> ()): TextButton
	local click = Instance.new("TextButton")
	click.Name = "Click"
	click.BackgroundTransparency = 1
	click.Text = ""
	click.AnchorPoint = Vector2.new(0.5, 0.5)
	click.Position = UDim2.fromScale(0.5, 0.5)
	click.Size = UDim2.fromScale(1.1, 1.1)
	click.ZIndex = 6
	click.Parent = frame
	click.Activated:Connect(onClick)
	return click
end

local function buildNode(nodeLayer: Frame, eggId: string)
	local p = Layout.NODES[eggId]
	local D = Layout.NODE_D
	local frame = Theme.container("Node_" .. eggId, nodeLayer)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromOffset(p.x, p.y)
	frame.Size = UDim2.fromOffset(D, D)

	local ring = makeRing(frame)

	-- Leuchtring (frei / freischaltbar), liegt auf dem gemalten Kelchrand
	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.fromScale(1.06, 1.06)
	glow.BackgroundTransparency = 1
	glow.BorderSizePixel = 0
	glow.ZIndex = 2
	glow.Visible = false
	glow.Parent = frame
	capsule(glow)
	local glowStroke = Instance.new("UIStroke")
	glowStroke.Color = HONEY_LIGHT
	glowStroke.Thickness = 4
	glowStroke.Transparency = 0.4
	glowStroke.Parent = glow

	local holder = Theme.container("EggHolder", frame)
	holder.AnchorPoint = Vector2.new(0.5, EggIcon.FOOT_Y)
	holder.Position = UDim2.fromScale(0.5, NODE_FOOT)
	holder.Size = UDim2.fromOffset(math.floor(EGG_H * 0.8), EGG_H)
	holder.ZIndex = 3
	local eggScale = Instance.new("UIScale")
	eggScale.Parent = holder
	local egg = EggIcon.make(holder, eggId, EGG_H, 3, { idle = true })

	local lock: GuiObject
	local lockImg = Icons.uiImage(frame, "tree/lock")
	if lockImg then
		lock = lockImg
		lock.Size = UDim2.fromOffset(34, 34)
	else
		local l = Theme.label("Lock", frame, Loc.t("ui.tree.lock_short"))
		l.Size = UDim2.fromOffset(60, 30)
		l.TextXAlignment = Enum.TextXAlignment.Center
		l.TextScaled = false
		l.TextSize = 22
		Theme.outlineText(l, 2)
		lock = l
	end
	lock.Name = "Lock"
	lock.AnchorPoint = Vector2.new(0.5, 0.5)
	lock.Position = UDim2.fromScale(0.5, 0.58)
	lock.ZIndex = 5

	local count = Theme.label("Count", frame, "")
	count.AnchorPoint = Vector2.new(0.5, 0.5)
	count.Position = UDim2.fromScale(0.86, 0.9)
	count.Size = UDim2.fromOffset(70, 28)
	count.TextXAlignment = Enum.TextXAlignment.Center
	count.TextScaled = false
	count.TextSize = 24
	count.TextColor3 = Theme.COLORS.honey
	count.ZIndex = 5
	Theme.outlineText(count, 2)

	local name = Theme.label("Name", frame, eggName(eggId))
	name.AnchorPoint = Vector2.new(0.5, 0)
	name.Position = UDim2.new(0.5, 0, 1, 2)
	name.Size = UDim2.fromOffset(210, 30)
	name.TextXAlignment = Enum.TextXAlignment.Center
	name.TextScaled = false
	name.TextSize = 24
	name.ZIndex = 5
	Theme.outlineText(name, 2)

	local click = makeClick(frame, function()
		selectNode(eggId)
	end)
	click.MouseEnter:Connect(function(x, y)
		if UserInputService:GetLastInputType() == Enum.UserInputType.Touch then return end
		showInfo(eggId, x, y)
	end)
	click.MouseLeave:Connect(function()
		showInfo(nil)
	end)

	_nodes[eggId] = {
		eggId = eggId, frame = frame, cupBack = nil, cupFront = nil,
		eggHolder = holder, eggScale = eggScale, egg = egg, lock = lock,
		name = name, count = count, ring = ring, state = "locked",
		phase = math.random() * 6, glow = glow, glowStroke = glowStroke,
	}
end

-- Freier Ast ohne Ei: dunkles "?"
local function buildEmpty(nodeLayer: Frame, slot: Layout.Slot)
	local D = Layout.NODE_D
	local frame = Theme.container("Empty_" .. slot.id, nodeLayer)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromOffset(slot.x, slot.y)
	frame.Size = UDim2.fromOffset(D, D)
	local mark = Theme.label("Mark", frame, "?")
	mark.AnchorPoint = Vector2.new(0.5, 0.5)
	mark.Position = UDim2.fromScale(0.5, 0.5)
	mark.Size = UDim2.fromScale(1, 1)
	mark.TextXAlignment = Enum.TextXAlignment.Center
	mark.TextScaled = false
	mark.TextSize = 46
	mark.TextColor3 = Theme.COLORS.textDim
	mark.TextTransparency = 0.45
	mark.ZIndex = 3
	makeClick(frame, function()
		Toast.info(Loc.t("ui.tree.slot_soon"))
	end)
	_extras[slot.id] = {
		id = slot.id, kind = "empty", branch = slot.branch, frame = frame,
		ring = makeRing(frame), icon = nil, state = "locked", phase = math.random() * 6,
	}
end

-- Sprung-Tor: Funke auf dem Blatt neben dem Stamm. Klick zeigt die Sprung-Regeln.
local function buildGate(nodeLayer: Frame, slot: Layout.Slot, branch: string)
	local D = Layout.NODE_D
	local frame = Theme.container("Gate_" .. branch, nodeLayer)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromOffset(slot.x, slot.y)
	frame.Size = UDim2.fromOffset(D, D)
	local ring = makeRing(frame)
	local icon: GuiObject
	local img = Icons.uiImage(frame, "fx/sparkle")
	if img then
		icon = img
	else
		local f = Instance.new("Frame")
		f.BackgroundColor3 = HONEY_LIGHT
		f.BorderSizePixel = 0
		f.Rotation = 45
		f.Parent = frame
		icon = f
	end
	icon.Name = "Spark"
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	icon.Size = UDim2.fromOffset(if img then 64 else 34, if img then 64 else 34)
	icon.ZIndex = 3
	makeClick(frame, function()
		selectGate(branch)
	end)
	_extras[slot.id] = {
		id = slot.id, kind = "gate", branch = branch, frame = frame,
		ring = ring, icon = icon, state = "locked", phase = math.random() * 6,
	}
end

local function buildTree(content: Frame)
	-- Ohne hochgeladenes Fenster-Bild: einfache dunkle Kelche, damit alles bedienbar bleibt
	if not EggPanelSkin.isReady("eggtree2") then
		local back = layer("Fallback", content, 1)
		local spots: { Layout.Point } = {}
		for _, p in Layout.NODES do table.insert(spots, p) end
		for _, e in Layout.EMPTY do table.insert(spots, e) end
		for _, g in Layout.GATES do table.insert(spots, g) end
		for _, p in spots do
			local c = Instance.new("Frame")
			c.AnchorPoint = Vector2.new(0.5, 0.5)
			c.Position = UDim2.fromOffset(p.x, p.y)
			c.Size = UDim2.fromOffset(Layout.NODE_D, Layout.NODE_D)
			c.BackgroundColor3 = Color3.fromRGB(70, 44, 28)
			c.BorderSizePixel = 0
			c.Parent = back
			capsule(c)
			Theme.stroke(c, Theme.COLORS.honeyDeep, 4)
		end
	end
	local nodeLayer = layer("Nodes", content, 7)
	_fxLayer = layer("Fx", content, 8)
	for _, slot in Layout.EMPTY do
		buildEmpty(nodeLayer, slot)
	end
	for branch, slot in Layout.GATES do
		buildGate(nodeLayer, slot, branch)
	end
	for eggId in Layout.NODES do
		if EggConfig.data[eggId :: Types.EggType] then
			buildNode(nodeLayer, eggId)
		end
	end
end

--------------------------------------------------------------------------------
-- Zustaende anzeigen
--------------------------------------------------------------------------------

local function swapCup(node: NodeRec, state: State)
	for _, part in { "back", "front" } do
		local obj = if part == "back" then node.cupBack else node.cupFront
		if not obj then continue end
		if obj:IsA("ImageLabel") then
			obj.Image = Icons.ui("tree/cup_" .. state .. "_" .. part) or obj.Image
		else
			obj.BackgroundColor3 = if state == "open" then Theme.COLORS.cream
				elseif state == "ready" then Theme.COLORS.honey
				else Theme.COLORS.disabled
		end
	end
end

local function showNodeState(node: NodeRec, state: State)
	node.state = state
	swapCup(node, state)
	EggIcon.setSilhouette(node.egg, state == "locked")
	node.lock.Visible = state == "locked"
	if node.glow then node.glow.Visible = state ~= "locked" end
	if node.glowStroke then node.glowStroke.Transparency = if state == "open" then 0.25 else 0.5 end
	node.name.TextColor3 = if state == "locked" then Theme.COLORS.textDim else Theme.COLORS.text
	if state ~= "ready" then node.eggScale.Scale = 1 end
end

local function showEdgeState(rec: EdgeRec, state: State)   -- (Aeste sind im Bild, _edges bleibt leer)
	rec.state = state
	for _, seg in rec.segs do
		if seg.fill then
			local fill = seg.fill :: GuiObject
			if fill:IsA("ImageLabel") then
				fill.ImageColor3 = FILL_TINT[state]
			else
				fill.BackgroundColor3 = if state == "locked" then Theme.COLORS.disabled
					else BaerchiConfig.getPathColor(rec.edge.path):Lerp(Color3.new(0, 0, 0), if state == "ready" then 0.25 else 0)
			end
		end
		if state == "locked" then setTransparency(seg.glow, 1) end
	end
end

--------------------------------------------------------------------------------
-- Animation: Takt, Lichtwelle, Bluete, Funkenring
--------------------------------------------------------------------------------

local function sparkRing(eggId: string)
	local fx = _fxLayer
	if not fx then return end
	local p = Layout.NODES[eggId]
	local ring = Icons.uiImage(fx, "fx/ring_soft")
	if ring then
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		ring.Position = UDim2.fromOffset(p.x, p.y - 6)
		ring.Size = UDim2.fromOffset(20, 10)
		ring.ImageColor3 = HONEY_LIGHT
		ring.ImageTransparency = 0.1
		tween(ring, 0.55, { Size = UDim2.fromOffset(170, 70), ImageTransparency = 1 })
		task.delay(0.6, function() ring:Destroy() end)
	end
	for i = 1, 12 do
		local a = (i / 12) * math.pi * 2
		local spark: GuiObject
		local img = Icons.uiImage(fx, "fx/sparkle")
		if img then
			spark = img
			img.ImageColor3 = if i % 2 == 0 then WAVE_LIGHT else HONEY_LIGHT
		else
			local f = Instance.new("Frame")
			f.BackgroundColor3 = HONEY_LIGHT
			f.BorderSizePixel = 0
			f.Rotation = 45
			f.Parent = fx
			spark = f
		end
		spark.AnchorPoint = Vector2.new(0.5, 0.5)
		spark.Position = UDim2.fromOffset(p.x, p.y - 8)
		spark.Size = UDim2.fromOffset(18, 18)
		local dist = 58 + (i % 3) * 10
		local target = UDim2.fromOffset(p.x + math.cos(a) * dist, p.y - 8 + math.sin(a) * dist * 0.5)
		local props: { [string]: any } = { Position = target, Size = UDim2.fromOffset(6, 6) }
		if spark:IsA("ImageLabel") then props.ImageTransparency = 1 else props.BackgroundTransparency = 1 end
		tween(spark, 0.55, props)
		task.delay(0.6, function() spark:Destroy() end)
	end
end

local function bloom(eggId: string)
	local node = _nodes[eggId]
	if not node then
		_held[eggId] = nil
		return
	end
	_held[eggId] = "open"
	showNodeState(node, "open")
	local edge = _edges[eggId]
	if edge then showEdgeState(edge, "open") end

	-- Kelch oeffnet sich wie eine Bluete
	for _, obj in { node.cupBack, node.cupFront } do
		if obj then
			-- Rueckfall-Schale (Frame) hat eigene Groesse; nur Bilder fuellen (1,1)
			local target = if obj:IsA("ImageLabel") then UDim2.fromScale(1, 1) else UDim2.fromScale(0.66, 0.17)
			obj.Size = UDim2.fromScale(target.X.Scale * 0.45, target.Y.Scale * 0.45)
			tween(obj, 0.5, { Size = target }, Enum.EasingStyle.Back)
		end
	end
	-- Ei springt einmal hoch und landet mit Funkenring
	local base = UDim2.fromScale(0.5, NODE_FOOT)
	local up = tween(node.eggHolder, 0.24, { Position = base - UDim2.fromOffset(0, 40) }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	up.Completed:Connect(function()
		local down = tween(node.eggHolder, 0.2, { Position = base }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		down.Completed:Connect(function()
			sparkRing(eggId)
			EggIcon.poke(node.egg)
			task.delay(0.6, function()
				_held[eggId] = nil
				EggTreePanel.refresh()
			end)
		end)
	end)
end

local function startNextWave()
	if _wave or #_queue == 0 then return end
	local eggId = table.remove(_queue, 1) :: string
	local chain = Layout.chain(eggId)
	local recs: { EdgeRec } = {}
	local offsets: { number } = {}
	local total = 0
	for _, e in chain do
		local rec = _edges[e.to]
		if rec then
			table.insert(recs, rec)
			table.insert(offsets, total)
			total += rec.length
		end
	end
	_wave = { eggId = eggId, edges = recs, offsets = offsets, total = total, t0 = os.clock() }
end

local function updateParticles(dt: number, now: number)
	for _, p in _particles do
		p.y -= p.vy * dt
		if p.y < -0.05 then
			p.y = 1.05
			p.x = math.random()
		end
		local x = p.x + math.sin(now * 0.6 + p.phase) * p.amp
		p.obj.Position = UDim2.fromScale(x, p.y)
		setTransparency(p.obj, 0.35 + 0.3 * (0.5 + 0.5 * math.sin(now * 1.7 + p.phase * 3)))
	end
end

local function step(dt: number)
	local now = os.clock()
	updateParticles(dt, now)

	-- Wellenkopf (Design-Pixel entlang der Kette)
	local wave = _wave
	local head = -1
	local waveEdges: { [EdgeRec]: number } = {}
	if wave then
		head = (now - wave.t0) * WAVE_SPEED
		for i, rec in wave.edges do waveEdges[rec] = wave.offsets[i] end
		if head > wave.total + 60 then
			_wave = nil
			bloom(wave.eggId)
			startNextWave()
		end
	end

	for _, rec in _edges do
		local state = rec.state
		local offset = waveEdges[rec]
		for _, seg in rec.segs do
			local tr = 1
			local color = rec.color
			if rec.edge.trunk then
				tr = 0.72 + 0.08 * math.sin(now * 1.6 - seg.s / 60)
				color = HONEY_LIGHT
			elseif state == "open" then
				tr = 0.48 + 0.12 * math.sin(now * 2.2 - seg.s / 45)
			elseif state == "ready" then
				-- Honiglicht kriecht vom Ast-Anfang zum Kelch
				local cycle = rec.length + 260
				local h = ((now * 260 + rec.phase * 100) % cycle) - 60
				local d = (seg.s - h) / 46
				tr = 1 - 0.85 * math.exp(-d * d)
				color = HONEY_LIGHT
			end
			if offset and head >= 0 then
				local d = (offset + seg.s - head) / 70
				local b = math.exp(-d * d)
				if offset + seg.s < head then b = math.max(b, 0.35) end
				if 1 - b < tr then
					tr = 1 - b
					color = WAVE_LIGHT
				end
			end
			setTransparency(seg.glow, tr)
			setTint(seg.glow, color)
		end
	end

	for _, node in _nodes do
		if node.state == "ready" and _held[node.eggId] == nil then
			node.eggScale.Scale = 1 + 0.05 * math.sin(now * 3.1 + node.phase)
			if node.glowStroke then
				node.glowStroke.Transparency = 0.35 + 0.35 * (0.5 + 0.5 * math.sin(now * 3.1 + node.phase))
			end
		end
	end
	for _, ex in _extras do
		local icon = ex.icon
		if ex.kind == "gate" and icon then
			local wave = 0.5 + 0.5 * math.sin(now * (if ex.state == "open" then 3 else 1.6) + ex.phase)
			setTransparency(icon, if ex.state == "open" then 0.05 + 0.2 * wave else 0.55 + 0.25 * wave)
		end
	end
end

local function startLoop()
	if _loop then return end
	_loop = RunService.Heartbeat:Connect(step)
end

local function stopLoop()
	if _loop then
		_loop:Disconnect()
		_loop = nil
	end
end

-- Freischalt-Animation fuer `eggId` abspielen (Welle → Bluete → Sprung).
-- Wird automatisch aufgerufen, wenn ein Knoten frei wird; zum Testen siehe
-- Kopf der Datei.
function EggTreePanel.playUnlock(eggId: string)
	local node = _nodes[eggId]
	if not node then return end
	_held[eggId] = "ready"
	showNodeState(node, "ready")
	local edge = _edges[eggId]
	if edge then showEdgeState(edge, "ready") end
	table.insert(_queue, eggId)
	startNextWave()
end

--------------------------------------------------------------------------------
-- Zoom
--------------------------------------------------------------------------------

local function fitContent()
	local vp, scale = _viewport, _zoomScale
	if not (vp and scale) then return end
	local size = vp.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then return end
	scale.Scale = math.min(size.X / Layout.SIZE.x, size.Y / Layout.SIZE.y) / ancestorScale(vp)
end

--------------------------------------------------------------------------------
-- Infokarte (Maus) und Detail-Karte
--------------------------------------------------------------------------------

local function pathChip(parent: Instance, path: string, pos: UDim2): Frame
	local chip = Instance.new("Frame")
	chip.Name = "PathChip"
	chip.Position = pos
	chip.Size = UDim2.fromOffset(110, 20)
	chip.BackgroundColor3 = BaerchiConfig.getPathColor(path)
	chip.BorderSizePixel = 0
	chip.Parent = parent
	capsule(chip)
	Theme.stroke(chip, Theme.COLORS.outline, 2)
	local label = Theme.label("Path", chip, pathName(path))
	label.Size = UDim2.fromScale(1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextScaled = false
	label.TextSize = 13
	Theme.outlineText(label, 1.5)
	return chip
end

function showInfo(eggId: string?, x: number?, y: number?)
	local card, root = _infoCard, _root
	if not (card and root) then return end
	for _, child in card:GetChildren() do
		if child:IsA("GuiObject") and child.Name ~= "Ornate" then child:Destroy() end
	end
	local data = ClientState.get()
	if not eggId or not data or not data.eggTree then
		card.Visible = false
		return
	end
	local def = EggConfig.data[eggId :: Types.EggType]
	if not def then return end
	local progress = EggTree.getProgress(data, eggId :: Types.EggType)
	local state = nodeState(data, eggId, progress)

	local egg = EggIcon.make(card, eggId, 96, card.ZIndex, { idle = true, pedestal = true })
	egg.Position = UDim2.fromOffset(18, 16)

	local title = Theme.label("Title", card, eggName(eggId))
	title.Position = UDim2.fromOffset(112, 18)
	title.Size = UDim2.new(1, -126, 0, 26)
	title.TextColor3 = def.color:Lerp(Color3.new(1, 1, 1), 0.25)
	Theme.outlineText(title, 2)

	pathChip(card, def.path, UDim2.fromOffset(112, 50))

	local status = Theme.label("Status", card, statusText(state, progress))
	status.Position = UDim2.fromOffset(112, 76)
	status.Size = UDim2.new(1, -126, 0, 18)
	status.TextScaled = false
	status.TextSize = 14
	status.TextColor3 = if progress.unlocked then Theme.COLORS.good else Theme.COLORS.honey

	local bar = Theme.progress(card, if progress.unlocked then Theme.COLORS.good else Theme.COLORS.honey)
	bar.track.Position = UDim2.fromOffset(16, 128)
	bar.track.Size = UDim2.new(1, -32, 0, 22)
	local frac = fraction(progress)
	bar.fill.Size = UDim2.fromScale(frac, 1)
	bar.text.Text = Loc.t("ui.tree.progress", { pct = math.floor(frac * 100 + 0.5) })

	local head = Theme.sectionLabel("Drops", card, Loc.t("ui.tree.drops"), Theme.COLORS.honey)
	head.Position = UDim2.fromOffset(18, 158)
	head.Size = UDim2.new(1, -36, 0, 16)
	local yy = 176
	for _, drop in drops(eggId) do   -- 21.10.: ALLE Pets zeigen (vorher nur die ersten 4)
		local bdef = BaerchiConfig.getById(drop.configId)
		if not bdef then continue end
		local known = data.discovered and data.discovered[drop.configId]
		local nm = if known then Loc.name("baerchi." .. drop.configId .. ".name", bdef.displayName) else "???"
		local pct = drop.chance * 100
		local pctText = if pct >= 10 then Loc.formatNumber(math.round(pct)) .. "%" elseif pct >= 1 then Loc.formatDecimal(pct, 1) .. "%" else Loc.formatDecimal(pct, 2) .. "%"
		local row = Theme.bodyText("Drop", card, string.format("%s  •  %s", pctText, nm))
		row.Position = UDim2.fromOffset(18, yy)
		row.Size = UDim2.new(1, -36, 0, 18)
		row.TextSize = 13
		row.TextColor3 = BaerchiConfig.getRarityColor(bdef.rarity)
		yy += 18
	end
	card.Size = UDim2.fromOffset(270, yy + 18)

	-- neben dem Mauszeiger, im Fenster gehalten
	local rp = root.AbsolutePosition
	local rs = root.AbsoluteSize
	local px = (x or 0) - rp.X + 22
	local py = (y or 0) - rp.Y - 20
	if px + 270 > rs.X then px = (x or 0) - rp.X - 292 end
	card.Position = UDim2.fromOffset(math.clamp(px, 8, math.max(8, rs.X - 278)), math.clamp(py, 8, math.max(8, rs.Y - yy - 26)))
	card.Visible = true
end

local function conditionText(c: EggTree.Condition): string
	if c.kind == "hatch" then
		return Loc.t("ui.tree.cond_hatch", { egg = eggName(c.egg :: string), have = c.have, need = c.need })
	elseif c.kind == "keyPet" then
		local names = {}
		for _, pet in (c.pets or {}) do
			local bdef = BaerchiConfig.getById(pet.id)
			if bdef then
				table.insert(names, Loc.name("baerchi." .. pet.id .. ".name", bdef.displayName))
			end
		end
		return Loc.t("ui.tree.cond_key", { pets = table.concat(names, " / ") })
	elseif c.kind == "hatchAny" then
		return Loc.t("ui.tree.cond_any", { have = c.have, need = c.need })
	elseif c.kind == "index" then
		return Loc.t("ui.tree.cond_index", { rarity = rarityName(c.rarity :: string), have = c.have, need = c.need })
	elseif c.kind == "rebirth" then
		return Loc.t("ui.tree.cond_rebirth", { have = c.have, need = c.need })
	elseif c.kind == "world2" then
		return Loc.t("ui.tree.cond_world2")   -- 20.10. P5d
	elseif c.kind == "blueprint" then
		return Loc.t("ui.tree.cond_blueprint")
	end
	return c.kind
end

local function addRow(parent: Instance, order: number, height: number): Frame
	local row = Theme.container("Row" .. order, parent)
	row.Size = UDim2.new(1, -8, 0, height)
	row.LayoutOrder = order
	return row
end

-- Zustand eines Sprung-Tors: offen, sobald eines der Sprung-Pets entdeckt ist
local function gateState(data: Types.PlayerDataUpdate, branch: string): State
	for _, jump in EggConfig.JUMPS do
		if jump.from == branch then
			for _, jp in jump.pets do
				if data.discovered and data.discovered[jp.pet] then return "open" end
			end
		end
	end
	return "locked"
end

local function buildGateDetail(detail: ScrollingFrame, data: Types.PlayerDataUpdate)
	local branch = _selectedGate :: string
	local order = 0
	local function nextOrder(): number order += 1 return order end
	local jump: any = nil
	for _, j in EggConfig.JUMPS do
		if j.from == branch then jump = j end
	end

	local top = addRow(detail, nextOrder(), 72)
	local spark = Icons.uiImage(top, "fx/sparkle")
	if spark then
		spark.Position = UDim2.fromOffset(10, 8)
		spark.Size = UDim2.fromOffset(56, 56)
		spark.ImageColor3 = HONEY_LIGHT
	end
	local title = Theme.label("Title", top, Loc.t("ui.tree.jump_title"))
	title.Position = UDim2.fromOffset(76, 6)
	title.Size = UDim2.new(1, -84, 0, 28)
	title.TextColor3 = HONEY_LIGHT
	Theme.outlineText(title)
	local toBranch = if jump then jump.to else "Middle"
	local route = Theme.label("Route", top, Loc.t("ui.tree.jump_route", {
		from = Loc.t("ui.tree.branch." .. branch), to = Loc.t("ui.tree.branch." .. toBranch),
	}))
	route.Position = UDim2.fromOffset(76, 38)
	route.Size = UDim2.new(1, -84, 0, 24)
	route.TextScaled = false
	route.TextSize = 14
	route.TextColor3 = Theme.COLORS.text

	if not jump then
		local none = Theme.bodyText("None", addRow(detail, nextOrder(), 56), Loc.t("ui.tree.jump_none"))
		none.Size = UDim2.fromScale(1, 1)
		return
	end

	local body = Theme.bodyText("Body", addRow(detail, nextOrder(), 56), Loc.t("ui.tree.jump_body"))
	body.Size = UDim2.fromScale(1, 1)

	local pct = Loc.formatDecimal(jump.chance, 1) .. "%"
	for _, jp in jump.pets do
		local bdef = BaerchiConfig.getById(jp.pet)
		local row = Theme.bodyText("Source", addRow(detail, nextOrder(), 38), Loc.t("ui.tree.jump_source", {
			chance = pct, pet = Names.baerchi(jp.pet), egg = eggName(jp.egg),
		}))
		row.Size = UDim2.fromScale(1, 1)
		row.TextSize = 13
		if bdef then row.TextColor3 = BaerchiConfig.getRarityColor(bdef.rarity) end
	end

	local target = Theme.label("Target", addRow(detail, nextOrder(), 24), Loc.t("ui.tree.jump_target", { egg = eggName(jump.target) }))
	target.Size = UDim2.fromScale(1, 1)
	target.TextScaled = false
	target.TextSize = 15
	target.TextColor3 = Theme.COLORS.honey
	if gateState(data, branch) == "open" then
		local done = Theme.label("Done", addRow(detail, nextOrder(), 24), Loc.t("ui.tree.jump_done"))
		done.Size = UDim2.fromScale(1, 1)
		done.TextScaled = false
		done.TextSize = 15
		done.TextColor3 = Theme.COLORS.good
	end
end

local _detailSig: string? = nil
local _detailSigHost: Instance? = nil

-- Signatur aller Werte, die das Detailfenster anzeigt. Aendert sie sich nicht,
-- wird nicht neu gebaut (sonst gehen Taps auf Knoepfe verloren).
local function detailSignature(data: Types.PlayerDataUpdate): string
	if _selectedGate then
		return "gate|" .. _selectedGate .. "|" .. gateState(data, _selectedGate) .. "|" .. Loc.t("ui.tree.jump_title")
	end
	local eggId = _selected
	local progress = EggTree.getProgress(data, eggId)
	local parts: { string } = { eggId, eggName(eggId), nodeState(data, eggId, progress) }
	local ok, enc = pcall(function() return HttpService:JSONEncode(progress) end)
	table.insert(parts, if ok then enc else tostring(os.clock()))
	table.insert(parts, tostring(data.island.eggStock[eggId] or 0))
	table.insert(parts, tostring(PetCapacity.isFull(data)))
	table.insert(parts, tostring(data.eggTree.blueprints or 0))
	table.insert(parts, tostring(EggTree.canUseBlueprint(data, eggId)))
	local nextEgg = EggConfig.getNextInPath(eggId)
	if nextEgg then table.insert(parts, tostring(EggTree.isUnlocked(data.eggTree, nextEgg))) end
	if eggId == "SugarEgg" then
		for _, path in { "Gold", "Void" } do
			local t = EggConfig.getNextInPath(eggId, path :: any)
			if t then table.insert(parts, tostring(EggTree.isUnlocked(data.eggTree, t))) end
		end
	end
	for _, drop in drops(eggId) do
		table.insert(parts, if data.discovered and data.discovered[drop.configId] then "1" else "0")
	end
	return table.concat(parts, "|")
end

local function buildDetail(detail: ScrollingFrame, data: Types.PlayerDataUpdate)
	local sig = detailSignature(data)
	if sig == _detailSig and _detailSigHost == detail then return end
	_detailSig = sig
	_detailSigHost = detail
	for _, child in detail:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end

	if _selectedGate then
		buildGateDetail(detail, data)
		return
	end

	local eggId = _selected
	local def = EggConfig.data[eggId]
	if not def then return end
	local progress = EggTree.getProgress(data, eggId)
	local state = nodeState(data, eggId, progress)
	local stock = data.island.eggStock[eggId] or 0
	local order = 0
	local function nextOrder(): number order += 1 return order end

	-- Kopf: grosses Ei auf Sockel, Name, Pfad, Zustand
	local top = addRow(detail, nextOrder(), 104)
	local egg = EggIcon.make(top, eggId, 76, nil, { idle = true, pedestal = true })
	egg.Position = UDim2.fromOffset(10, 0)
	local title = Theme.label("Title", top, eggName(eggId))
	title.Position = UDim2.fromOffset(90, 4)
	title.Size = UDim2.new(1, -92, 0, 28)
	title.TextColor3 = def.color:Lerp(Color3.new(1, 1, 1), 0.25)
	Theme.outlineText(title)
	pathChip(top, def.path, UDim2.fromOffset(90, 38))
	local status = Theme.label("Status", top, statusText(state, progress))
	status.Position = UDim2.fromOffset(90, 64)
	status.Size = UDim2.new(1, -92, 0, 20)
	status.TextScaled = false
	status.TextSize = 15
	status.TextColor3 = if progress.unlocked then Theme.COLORS.good else Theme.COLORS.honey

	local sub = Theme.bodyText("Sub", addRow(detail, nextOrder(), 36), Loc.t("ui.tree.path_line", {
		path = pathName(def.path),
		goal = Loc.name("path." .. def.path .. ".goal", ""),
		avg  = Loc.formatDecimal(EggTree.expectedRarity(eggId), 2),
	}))
	sub.Size = UDim2.fromScale(1, 1)
	if def.branch then
		local bl = Theme.bodyText("Branch", addRow(detail, nextOrder(), 20), Loc.t("ui.tree.branch_line", { branch = Loc.t("ui.tree.branch." .. def.branch) }))
		bl.Size = UDim2.fromScale(1, 1)
		bl.TextSize = 13
		bl.TextColor3 = Theme.COLORS.honey
	end

	-- Gesamtfortschritt
	if not progress.unlocked then
		local bar = Theme.progress(addRow(detail, nextOrder(), 24), Theme.COLORS.honey)
		bar.track.Size = UDim2.fromScale(1, 1)
		local frac = fraction(progress)
		bar.fill.Size = UDim2.fromScale(frac, 1)
		bar.text.Text = Loc.t("ui.tree.progress", { pct = math.floor(frac * 100 + 0.5) })
	end

	-- Bedingungen
	if not progress.unlocked and #progress.conditions > 0 then
		Theme.sectionLabel("CondHead", addRow(detail, nextOrder(), 16), Loc.t("ui.tree.needs"), Theme.COLORS.honey).Size = UDim2.fromScale(1, 1)
		for _, c in progress.conditions do
			local row = addRow(detail, nextOrder(), 26)
			local bar = Theme.progress(row, if c.done then Theme.COLORS.good else Theme.COLORS.accent)
			bar.track.Size = UDim2.fromScale(1, 1)
			bar.fill.Size = UDim2.fromScale(math.clamp(c.have / math.max(1, c.need), 0, 1), 1)
			bar.text.Text = conditionText(c)
			if c.parts then
				for _, part in c.parts do
					local prow = addRow(detail, nextOrder(), 20)
					local pl = Theme.bodyText("Part", prow, string.format("   %s %s  %d/%d",
						if part.done then "✓" else "·", eggName(part.egg), part.have, part.need))
					pl.Size = UDim2.fromScale(1, 1)
					pl.TextSize = 12
				end
			end
		end
	end

	-- Lager + Aktionen
	local stockRow = addRow(detail, nextOrder(), 22)
	local stockLabel = Theme.label("Stock", stockRow, Loc.t("ui.tree.in_stock", { n = stock }))
	stockLabel.Size = UDim2.fromScale(1, 1)
	stockLabel.TextColor3 = if stock > 0 then Theme.COLORS.good else Theme.COLORS.textDim

	local openRow = addRow(detail, nextOrder(), 40)
	local openBtn = Theme.sealButton("Open", openRow, Loc.t("ui.tree.open"))
	openBtn.Size = UDim2.new(1, -12, 1, -6)
	openBtn.Position = UDim2.fromOffset(6, 0)
	-- 19.10. (PET_LIMIT_V1): Lager voll = Knopf grau, Klick erklaert nur
	local limitFull = PetCapacity.isFull(data)
	Theme.setEnabled(openBtn, stock > 0 and not limitFull)
	openBtn.Activated:Connect(function()
		local now = ClientState.get()
		if not now or (now.island.eggStock[eggId] or 0) <= 0 then return end
		if PetCapacity.isFull(now) then
			Toast.info(Loc.msg("err.pet_limit_full"))
			return
		end
		HatchAnimation.request(eggId)
		Remotes.RequestHatchEgg:FireServer(eggId)
	end)

	-- Presse: beim Zucker-Ei zwei Wege (Gold / Void)
	if EggConfig.canPress(eggId :: any) then
		local targets: { { path: string?, egg: Types.EggType } } = {}
		if eggId == "SugarEgg" then
			for _, path in { "Gold", "Void" } do
				local t = EggConfig.getNextInPath(eggId, path :: any)
				if t then table.insert(targets, { path = path, egg = t }) end
			end
		else
			local t = EggConfig.getNextInPath(eggId)
			if t then table.insert(targets, { path = nil, egg = t }) end
		end
		for _, target in targets do
			local row = addRow(detail, nextOrder(), 32)
			local free = EggTree.isUnlocked(data.eggTree, target.egg)
			local btn = Theme.button("Press", row, Loc.t("ui.tree.press", {
				n = EggConfig.PRESS.cost, egg = eggName(target.egg),
			}), Theme.COLORS.goldGummy)
			btn.Size = UDim2.fromScale(1, 1)
			Theme.setEnabled(btn, free and stock >= EggConfig.PRESS.cost)
			btn.Activated:Connect(function()
				Remotes.RequestPressEggs:FireServer(eggId, target.path)
			end)
		end
	end

	-- Blaupause
	if EggTree.canUseBlueprint(data, eggId) then
		local row = addRow(detail, nextOrder(), 32)
		local btn = Theme.button("Blueprint", row, Loc.t("ui.tree.use_blueprint", { n = data.eggTree.blueprints }),
			BaerchiConfig.getPathColor("Kosmos"))
		btn.TextColor3 = Theme.COLORS.text
		btn.Size = UDim2.fromScale(1, 1)
		btn.Activated:Connect(function()
			Remotes.RequestUseBlueprint:FireServer(eggId)
		end)
	end

	-- Drop-Vorschau
	Theme.sectionLabel("DropHead", addRow(detail, nextOrder(), 16), Loc.t("ui.tree.drops"), Theme.COLORS.honey).Size = UDim2.fromScale(1, 1)
	for _, drop in drops(eggId) do
		local bdef = BaerchiConfig.getById(drop.configId)
		if bdef then
			local row = addRow(detail, nextOrder(), 20)
			local known = data.discovered and data.discovered[drop.configId]
			local name = if known then Names.baerchi(drop.configId) else "???"
			local pct = drop.chance * 100
			local pctText = if pct >= 10 then Loc.formatNumber(math.round(pct)) .. "%" elseif pct >= 1 then Loc.formatDecimal(pct, 1) .. "%" else Loc.formatDecimal(pct, 2) .. "%"
			local l = Theme.bodyText("Drop", row, string.format("%s  •  %s  •  %s", pctText, name, rarityName(bdef.rarity)))
			l.Size = UDim2.fromScale(1, 1)
			l.TextSize = 12
			l.TextColor3 = BaerchiConfig.getRarityColor(bdef.rarity)
		end
	end
end

--------------------------------------------------------------------------------
-- Breit / schmal
--------------------------------------------------------------------------------

local function applyLayout()
	local root, host, vp = _root, _detailHost, _viewport
	if not (root and host and vp) then return end
	_narrow = true
	fitContent()
	local size = vp.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then return end
	-- Detail-Karte schwebt ueber dem Baum, auf der Seite gegenueber dem gewaehlten Knoten
	local anc = ancestorScale(host.Parent)
	local cardScale = math.clamp(size.X * 0.31 / (DETAIL_W * anc), 0.45, 1.3)
	if _detailScale then _detailScale.Scale = cardScale end
	host.Size = UDim2.fromOffset(DETAIL_W, size.Y * 0.80 / (cardScale * anc))
	local sel: Layout.Point? = if _selectedGate then Layout.pointOf("G_" .. _selectedGate) else Layout.NODES[_selected]
	local right = sel == nil or sel.x < Layout.SIZE.x / 2
	host.AnchorPoint = Vector2.new(if right then 1 else 0, 0)
	host.Position = UDim2.fromScale(if right then 0.985 else 0.105, 0.13)
	host.Visible = _detailOpen
	if _detailClose then _detailClose.Visible = true end
end

function selectNode(eggId: string)
	_selected = eggId :: Types.EggType
	_selectedGate = nil
	_detailOpen = true
	showInfo(nil)
	applyLayout()
	EggTreePanel.refresh()
end

function selectGate(branch: string)
	_selectedGate = branch
	_detailOpen = true
	showInfo(nil)
	applyLayout()
	EggTreePanel.refresh()
end

--------------------------------------------------------------------------------
-- Aktualisieren
--------------------------------------------------------------------------------

function EggTreePanel.refresh()
	local root = _root
	if not root or not root.Visible then return end
	local data = ClientState.get()
	if not data or not data.eggTree then return end

	if _header then
		_header.Text = Loc.t("ui.tree.title_bp", { n = data.eggTree.blueprints or 0 })
	end

	local known = _known
	local fresh: { [string]: boolean } = {}
	for eggId, node in _nodes do
		local progress = EggTree.getProgress(data, eggId :: Types.EggType)
		local state = nodeState(data, eggId, progress)
		fresh[eggId] = progress.unlocked
		local stock = data.island.eggStock[eggId :: Types.EggType] or 0
		node.count.Text = if stock > 0 then "x" .. Loc.formatNumber(stock) else ""
		node.name.Text = eggName(eggId)
		node.ring.Visible = eggId == _selected and _selectedGate == nil

		-- Neu frei seit dem letzten Blick: Animation statt Sprung
		if known and progress.unlocked and not known[eggId] and _held[eggId] == nil then
			EggTreePanel.playUnlock(eggId)
		end
		local held = _held[eggId]
		if held then
			if node.state ~= held then showNodeState(node, held) end
		elseif node.state ~= state then
			showNodeState(node, state)
		end
		local edge = _edges[eggId]
		if edge and _held[eggId] == nil then
			showEdgeState(edge, if edge.edge.trunk then "open" else state)
		end
	end
	_known = fresh

	for _, ex in _extras do
		ex.ring.Visible = ex.kind == "gate" and _selectedGate == ex.branch
		if ex.kind == "gate" then
			local st = gateState(data, ex.branch)
			ex.state = st
			if ex.icon then
				setTint(ex.icon, if st == "open" then HONEY_LIGHT else Color3.fromRGB(150, 140, 130))
			end
		end
	end

	for _, link in _links do
		setTransparency(link.obj, if EggTree.isUnlocked(data.eggTree, link.from :: Types.EggType) then 0.1 else 0.7)
	end

	if _detail then
		buildDetail(_detail, data)
	end
end

local function openInternal(eggId: any)
	local root = _root
	if not root then return end
	if typeof(eggId) == "string" and EggConfig.data[eggId :: Types.EggType] then
		_selected = eggId :: Types.EggType
		_selectedGate = nil
		_detailOpen = true
	end
	root.Visible = true
	applyLayout()
	-- Erst im naechsten Frame hat das Fenster seine Groesse.
	task.defer(applyLayout)
	startLoop()
	EggTreePanel.refresh()
	startNextWave()
end

local function closeInternal()
	if _root then _root.Visible = false end
	showInfo(nil)
	stopLoop()
end

--------------------------------------------------------------------------------
-- Aufbau
--------------------------------------------------------------------------------

function EggTreePanel.init(screenGui: ScreenGui)
	local root = Theme.dialog("EggTreePanel", screenGui, Vector2.new(0.94, 0.9), Vector2.new(480, 300), Vector2.new(1280, 780))
	_root = root

	_header = Theme.dialogHeader(root, Loc.t("ui.tree.title"), function()
		PanelManager.close(PANEL_NAME)
	end)

	local body = Theme.dialogBody(root)
	_body = body
	Theme.ornateDialog(root)

	-- Baum: das Fenster-Bild ist der Baum, die Knoten liegen in Bildpixeln darauf
	local vp = Instance.new("Frame")
	vp.Name = "Viewport"
	vp.BackgroundTransparency = 1
	vp.Size = UDim2.fromScale(1, 1)
	vp.Parent = body
	_viewport = vp

	local content = Theme.container("Content", vp)
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.Size = UDim2.fromOffset(Layout.SIZE.x, Layout.SIZE.y)
	_content = content
	local scale = Instance.new("UIScale")
	scale.Parent = content
	_zoomScale = scale

	-- Detail-Karte (schwebt ueber dem Baum, wird in applyLayout skaliert und platziert)
	local host = Theme.panel("Detail", body, Theme.COLORS.forest)
	host.ZIndex = 10
	host.Visible = false
	Theme.ornate(host, "card", 0.45)
	_detailHost = host
	local hostScale = Instance.new("UIScale")
	hostScale.Parent = host
	_detailScale = hostScale
	local detail = Theme.scroller("List", host)
	detail.Position = UDim2.fromOffset(14, 14)
	detail.Size = UDim2.new(1, -24, 1, -28)
	detail.ScrollBarImageColor3 = Theme.COLORS.honey
	detail.ZIndex = 11
	local listLayout = Theme.listLayout(detail, 5)
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	_detail = detail

	local close = Theme.button("CloseDetail", host, "X", Theme.COLORS.bad)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -10, 0, 10)
	close.Size = UDim2.fromOffset(30, 28)
	close.TextColor3 = Theme.COLORS.text
	close.ZIndex = 12
	close.Activated:Connect(function()
		_detailOpen = false
		applyLayout()
	end)
	_detailClose = close

	-- Infokarte beim Darueberfahren
	local card = Instance.new("Frame")
	card.Name = "InfoCard"
	card.BackgroundColor3 = Theme.COLORS.forest
	card.BorderSizePixel = 0
	card.Size = UDim2.fromOffset(270, 260)
	card.Visible = false
	card.ZIndex = 30
	card.Active = false
	card.Parent = root
	Theme.corner(card, 14)
	Theme.stroke(card, Theme.COLORS.honeyDeep, 3)
	Theme.ornate(card, "card", 0.45)
	_infoCard = card

	buildTree(content)

	root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if root.Visible then applyLayout() end
	end)
	vp:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if root.Visible then applyLayout() end
	end)

	-- Menue im Honig-Template. Das alte root bleibt fuer PanelManager und Layout
	-- zustaendig (EggPanelSkin.adopt). Neues Fenster (Baum im Bild) wenn hochgeladen,
	-- sonst das alte Honig-Fenster.
	local variant: string? = nil
	if EggPanelSkin.isReady("eggtree2") then
		variant = "eggtree2"
	elseif EggPanelSkin.isReady("eggtree") then
		variant = "eggtree"
	end
	if variant then
		local TAB_PANELS = { eggs = "Hatch", paws = "Inventory", crown = "Leaderboard" }
		EggPanelSkin.adopt(screenGui, root, body, {
			variant = variant, maxWidth = if variant == "eggtree2" then 1500 else 1276, size = UDim2.fromScale(0.96, 0.9),
			onTab = function(tab: string)
				local target = TAB_PANELS[tab]
				if target then PanelManager.open(target) end
			end,
			onClose = function()
				PanelManager.close(PANEL_NAME)
			end,
		})
	end

	PanelManager.register(PANEL_NAME, { open = openInternal, close = closeInternal })

	ClientState.onChanged(function()
		EggTreePanel.refresh()
	end)
	Loc.onChanged(function()
		if _header then _header.Text = Loc.t("ui.tree.title") end
		EggTreePanel.refresh()
	end)

	-- Test-Ausloeser fuer die Freischalt-Animation (nur Studio)
	if RunService:IsStudio() then
		local player = Players.LocalPlayer
		player:GetAttributeChangedSignal("EggTreeTestUnlock"):Connect(function()
			local eggId = player:GetAttribute("EggTreeTestUnlock")
			if typeof(eggId) ~= "string" or not _nodes[eggId] then return end
			player:SetAttribute("EggTreeTestUnlock", nil)
			if not root.Visible then PanelManager.open(PANEL_NAME, eggId) end
			task.delay(0.3, function() EggTreePanel.playUnlock(eggId) end)
		end)
		UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
			if processed or not root.Visible then return end
			if input.KeyCode == Enum.KeyCode.U then
				EggTreePanel.playUnlock(_selected)
			end
		end)
	end

	print("[EggTreePanel] Initialisiert |", #EggConfig.getOrderedIds(), "Knoten |", variant or "ohne Fenster-Bild")
end

return EggTreePanel
