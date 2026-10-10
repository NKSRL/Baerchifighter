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

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local Players           = game:GetService("Players")

local Types           = require(ReplicatedStorage.Network.Types)
local Remotes         = require(ReplicatedStorage.Network.Remotes)
local Loc             = require(ReplicatedStorage.Localization.Loc)
local EggConfig       = require(ReplicatedStorage.Config.EggConfig)
local BaerchiConfig   = require(ReplicatedStorage.Config.BaerchiConfig)
local EggTree         = require(ReplicatedStorage.Modules.EggTree)
local IndexCalculator = require(ReplicatedStorage.Modules.IndexCalculator)

local Theme          = require(script.Parent.Theme)
local Icons          = require(script.Parent.Icons)
local EggIcon        = require(script.Parent.EggIcon)
local Layout         = require(script.Parent.EggTreeLayout)
local PanelManager   = require(script.Parent.PanelManager)
local HatchAnimation = require(script.Parent.HatchAnimation)
local ClientState    = require(script.Parent.Parent.Controllers.ClientState)

local EggTreePanel = {}

local PANEL_NAME = "EggTree"
EggTreePanel.PANEL_NAME = PANEL_NAME

local DETAIL_W  = 290
local NARROW_W  = 860     -- schmaler (Handy quer): Detail als Karte ueber dem Baum
local ZOOM_MIN  = 0.35
local ZOOM_MAX  = 1.6
local SEG_STEP  = 26      -- Laenge der Ast-Stuecke (Design-Pixel)
local EGG_H     = Layout.EGG_HEIGHT
local CUP_W     = EGG_H * Layout.CUP_SCALE
local WAVE_SPEED = 900    -- Design-Pixel pro Sekunde

local HONEY_LIGHT = Color3.fromRGB(255, 206, 96)
local WAVE_LIGHT  = Color3.fromRGB(255, 246, 214)

local BRANCH_TEXTURE: { [string]: string } = {
	Stamm = "tree/branch_stamm", Gold = "tree/branch_gold", Kristall = "tree/branch_kristall",
	Void = "tree/branch_void", Kosmos = "tree/branch_kosmos", Ascension = "tree/branch_ascension",
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
}

type Wave = { eggId: string, edges: { EdgeRec }, offsets: { number }, total: number, t0: number }

local _root: Frame?            = nil
local _body: Frame?            = nil
local _viewport: Frame?        = nil
local _canvas: ScrollingFrame? = nil
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
local _zoom = 1
local _narrow = false
local _detailOpen = false
local _loop: RBXScriptConnection? = nil
local _known: { [string]: boolean }? = nil    -- zuletzt gesehene Freischaltungen
local _queue: { string } = {}
local _wave: Wave? = nil
local _held: { [string]: State } = {}          -- Knoten in Animation: angezeigter Zustand
local _dropCache: { [string]: { any } } = {}

local function eggName(eggId: string): string
	local def = EggConfig.data[eggId :: Types.EggType]
	return Loc.name("egg." .. eggId .. ".name", def and def.displayName or eggId)
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

local function buildTrunk(content: Frame)
	local t = Layout.TRUNK
	local trunk = Icons.uiImage(content, "tree/trunk")
	if trunk then
		trunk.Name = "Trunk"
		trunk.Position = UDim2.fromOffset(t.x, t.y)
		trunk.Size = UDim2.fromOffset(t.w, t.h)
		trunk.ZIndex = 2
		return
	end
	-- Rueckfall: Stamm aus Frames
	local stem = Instance.new("Frame")
	stem.Name = "Trunk"
	stem.AnchorPoint = Vector2.new(0.5, 1)
	stem.Position = UDim2.fromOffset(t.x + t.w / 2, t.y + t.h - 20)
	stem.Size = UDim2.fromOffset(t.w * 0.42, t.h * 0.86)
	stem.BackgroundColor3 = Theme.COLORS.walnut
	stem.BorderSizePixel = 0
	stem.ZIndex = 2
	stem.Parent = content
	Theme.corner(stem, 24)
	Theme.stroke(stem, Theme.COLORS.outline, 4)
	Theme.gradient(stem, Color3.new(1, 1, 1), Color3.fromRGB(150, 130, 120), 0)
end

local function buildEdge(layers: { [string]: Frame }, edge: Layout.Edge)
	local pts = Layout.sample(edge, SEG_STEP)
	local texture = Icons.ui(BRANCH_TEXTURE[edge.path] or "tree/branch_stamm")
	local glowId = Icons.ui("tree/branch_glow")
	local pathColor = BaerchiConfig.getPathColor(edge.path)
	local rec: EdgeRec = {
		edge = edge, segs = {}, length = 0, state = "locked",
		color = pathColor:Lerp(HONEY_LIGHT, 0.45), phase = math.random() * 2,
	}
	local s = 0
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local dx, dy = b.x - a.x, b.y - a.y
		local len = math.sqrt(dx * dx + dy * dy)
		local t = (i - 0.5) / (#pts - 1)
		local w = edge.width * (1 - 0.38 * t)
		local cx, cy = (a.x + b.x) / 2, (a.y + b.y) / 2
		local rot = math.deg(math.atan2(dy, dx))

		local fill: GuiObject? = nil
		if not edge.trunk then
			local outline = Instance.new("Frame")
			outline.Name = "Outline"
			outline.AnchorPoint = Vector2.new(0.5, 0.5)
			outline.Position = UDim2.fromOffset(cx, cy)
			outline.Size = UDim2.fromOffset(len + w + 6, w + 7)
			outline.Rotation = rot
			outline.BackgroundColor3 = Theme.COLORS.outline
			outline.BorderSizePixel = 0
			outline.Parent = layers.outlines
			capsule(outline)

			if texture then
				local img = Instance.new("ImageLabel")
				img.Image = texture
				img.ScaleType = Enum.ScaleType.Tile
				img.TileSize = UDim2.fromOffset(w * 4, w)
				img.BackgroundTransparency = 1
				fill = img
			else
				local f = Instance.new("Frame")
				f.BackgroundColor3 = pathColor
				Theme.gradient(f, Color3.new(1, 1, 1), Color3.fromRGB(150, 140, 140), 90)
				fill = f
			end
			local fl = fill :: GuiObject
			fl.Name = "Fill"
			fl.AnchorPoint = Vector2.new(0.5, 0.5)
			fl.Position = UDim2.fromOffset(cx, cy)
			fl.Size = UDim2.fromOffset(len + w, w)
			fl.Rotation = rot
			fl.BorderSizePixel = 0
			fl.Parent = layers.fills
			capsule(fl)
		end

		local glow: GuiObject
		if glowId then
			local img = Instance.new("ImageLabel")
			img.Image = glowId
			img.BackgroundTransparency = 1
			img.ImageTransparency = 1
			glow = img
		else
			local f = Instance.new("Frame")
			f.BackgroundTransparency = 1
			glow = f
		end
		glow.Name = "Glow"
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = UDim2.fromOffset(cx, cy)
		glow.Size = UDim2.fromOffset(len + w * 0.6, w * (if edge.trunk then 1.4 else 0.7))
		glow.Rotation = rot
		glow.BorderSizePixel = 0
		glow.Parent = if edge.trunk then layers.trunkGlow else layers.glows
		if not glowId then capsule(glow) end
		setTint(glow, rec.color)

		table.insert(rec.segs, { fill = fill, glow = glow, s = s + len / 2 })
		s += len
	end
	rec.length = s
	_edges[edge.to] = rec
end

-- Sternbild-Linien zum Kometen-Ei (es wird ueber die Endeier frei).
local function buildLinks(linkLayer: Frame)
	local comet = EggConfig.TREE.CometEgg
	if not (comet and comet.hatchAnyOf) then return end
	local target = Layout.NODES.CometEgg
	for _, req in comet.hatchAnyOf.of do
		local from = Layout.NODES[req.egg]
		if not from then continue end
		local dx, dy = target.x - from.x, target.y - from.y
		local len = math.sqrt(dx * dx + dy * dy)
		local n = math.floor(len / 28)
		for i = 1, n - 1 do
			local x = from.x + dx * i / n
			local y = from.y - 30 + (dy + 30) * i / n
			local dot = Icons.uiImage(linkLayer, "fx/sparkle")
			local obj: GuiObject
			if dot then
				obj = dot
				obj.Size = UDim2.fromOffset(12, 12)
			else
				local f = Instance.new("Frame")
				f.Size = UDim2.fromOffset(5, 5)
				f.BorderSizePixel = 0
				f.Parent = linkLayer
				capsule(f)
				obj = f
			end
			obj.AnchorPoint = Vector2.new(0.5, 0.5)
			obj.Position = UDim2.fromOffset(x, y)
			setTint(obj, Color3.fromRGB(176, 168, 255))
			table.insert(_links, { obj = obj, from = req.egg })
		end
	end
end

local function cupImage(parent: Instance, state: State, part: string): GuiObject?
	local img = Icons.uiImage(parent, "tree/cup_" .. state .. "_" .. part)
	if not img then return nil end
	img.Name = "Cup" .. part
	img.AnchorPoint = Vector2.new(0.5, Layout.CUP_ANCHOR)
	img.Position = UDim2.fromScale(0.5, Layout.CUP_ANCHOR)
	img.Size = UDim2.fromScale(1, 1)
	return img
end

local selectNode: (eggId: string) -> ()
local showInfo: (eggId: string?, x: number?, y: number?) -> ()

local function buildNode(nodeLayer: Frame, eggId: string)
	local p = Layout.NODES[eggId]
	local frame = Theme.container("Node_" .. eggId, nodeLayer)
	frame.AnchorPoint = Vector2.new(0.5, Layout.CUP_ANCHOR)
	frame.Position = UDim2.fromOffset(p.x, p.y)
	frame.Size = UDim2.fromOffset(CUP_W, CUP_W)

	-- Auswahl-Schein ganz hinten
	local ring: GuiObject
	local soft = Icons.uiImage(frame, "fx/ring_soft")
	if soft then
		soft.ImageTransparency = 0.35
		ring = soft
	else
		local f = Instance.new("Frame")
		f.BackgroundColor3 = Color3.new(1, 1, 1)
		f.BackgroundTransparency = 0.8
		f.BorderSizePixel = 0
		f.Parent = frame
		capsule(f)
		ring = f
	end
	ring.Name = "Select"
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.42)
	ring.Size = UDim2.fromScale(1.15, 1.15)
	ring.ZIndex = 1
	ring.Visible = false

	local cupBack = cupImage(frame, "locked", "back")
	if cupBack then cupBack.ZIndex = 2 end

	local holder = Theme.container("EggHolder", frame)
	holder.AnchorPoint = Vector2.new(0.5, EggIcon.FOOT_Y)
	holder.Position = UDim2.new(0.5, 0, Layout.CUP_ANCHOR, 4)
	holder.Size = UDim2.fromOffset(math.floor(EGG_H * 0.8), EGG_H)
	holder.ZIndex = 3
	local eggScale = Instance.new("UIScale")
	eggScale.Parent = holder
	local egg = EggIcon.make(holder, eggId, EGG_H, 3, { idle = true })

	local cupFront = cupImage(frame, "locked", "front")
	if cupFront then
		cupFront.ZIndex = 4
	else
		-- Rueckfall: flacher Kelch als Ellipse
		local bowl = Instance.new("Frame")
		bowl.Name = "Cupfront"
		bowl.AnchorPoint = Vector2.new(0.5, 0.5)
		bowl.Position = UDim2.new(0.5, 0, Layout.CUP_ANCHOR, 2)
		bowl.Size = UDim2.fromScale(0.66, 0.17)
		bowl.BorderSizePixel = 0
		bowl.ZIndex = 4
		bowl.Parent = frame
		capsule(bowl)
		Theme.stroke(bowl, Theme.COLORS.outline, 3)
		cupFront = bowl
	end

	local lock: GuiObject
	local lockImg = Icons.uiImage(frame, "tree/lock")
	if lockImg then
		lock = lockImg
		lock.Size = UDim2.fromOffset(34, 34)
	else
		local l = Theme.label("Lock", frame, Loc.t("ui.tree.lock_short"))
		l.Size = UDim2.fromOffset(34, 20)
		l.TextXAlignment = Enum.TextXAlignment.Center
		Theme.outlineText(l, 2)
		lock = l
	end
	lock.Name = "Lock"
	lock.AnchorPoint = Vector2.new(0.5, 0.5)
	lock.Position = UDim2.fromScale(0.74, 0.34)
	lock.ZIndex = 5

	local count = Theme.label("Count", frame, "")
	count.AnchorPoint = Vector2.new(0.5, 0.5)
	count.Position = UDim2.fromScale(0.22, 0.3)
	count.Size = UDim2.fromOffset(44, 20)
	count.TextXAlignment = Enum.TextXAlignment.Center
	count.TextColor3 = Theme.COLORS.honey
	count.ZIndex = 5
	Theme.outlineText(count, 2)

	local name = Theme.label("Name", frame, eggName(eggId))
	name.AnchorPoint = Vector2.new(0.5, 0)
	name.Position = UDim2.fromScale(0.5, 0.72)
	name.Size = UDim2.new(1, 34, 0, 20)
	name.TextXAlignment = Enum.TextXAlignment.Center
	name.TextScaled = false
	name.TextSize = 15
	name.ZIndex = 5
	Theme.outlineText(name, 2)

	local click = Instance.new("TextButton")
	click.Name = "Click"
	click.BackgroundTransparency = 1
	click.Text = ""
	click.AnchorPoint = Vector2.new(0.5, 0.5)
	click.Position = UDim2.fromScale(0.5, 0.45)
	click.Size = UDim2.fromScale(0.8, 0.85)
	click.ZIndex = 6
	click.Parent = frame
	click.Activated:Connect(function()
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
		eggId = eggId, frame = frame, cupBack = cupBack, cupFront = cupFront,
		eggHolder = holder, eggScale = eggScale, egg = egg, lock = lock,
		name = name, count = count, ring = ring, state = "locked",
		phase = math.random() * 6,
	}
end

local function buildTree(content: Frame)
	local links = layer("Links", content, 1)
	buildTrunk(content)
	local layers = {
		trunkGlow = layer("TrunkGlow", content, 3),
		outlines  = layer("Outlines", content, 4),
		fills     = layer("Fills", content, 5),
		glows     = layer("Glows", content, 6),
	}
	local nodeLayer = layer("Nodes", content, 7)
	_fxLayer = layer("Fx", content, 8)

	buildLinks(links)
	for _, edge in Layout.EDGES do
		buildEdge(layers, edge)
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
	node.name.TextColor3 = if state == "locked" then Theme.COLORS.textDim else Theme.COLORS.text
	if state ~= "ready" then node.eggScale.Scale = 1 end
end

local function showEdgeState(rec: EdgeRec, state: State)
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
			obj.Size = UDim2.fromScale(0.45, 0.45)
			tween(obj, 0.5, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Back)
		end
	end
	-- Ei springt einmal hoch und landet mit Funkenring
	local base = UDim2.new(0.5, 0, Layout.CUP_ANCHOR, 4)
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

local function fitZoom(): number
	local vp = _viewport
	if not vp then return 1 end
	local size = vp.AbsoluteSize
	return math.min(size.X / Layout.SIZE.x, size.Y / Layout.SIZE.y)
end

local function setZoom(z: number, focus: Vector2?)
	local canvas, scale, vp = _canvas, _zoomScale, _viewport
	if not (canvas and scale and vp) then return end
	local minZ = math.min(ZOOM_MIN, fitZoom())
	local newZ = math.clamp(z, minZ, ZOOM_MAX)
	local f = focus or vp.AbsoluteSize / 2
	local point = (canvas.CanvasPosition + f) / _zoom
	_zoom = newZ
	scale.Scale = newZ
	canvas.CanvasSize = UDim2.fromOffset(Layout.SIZE.x * newZ, Layout.SIZE.y * newZ)
	canvas.CanvasPosition = point * newZ - f
end

local function resetView()
	local canvas, vp = _canvas, _viewport
	if not (canvas and vp) then return end
	local fit = fitZoom()
	-- Handy: lieber etwas groesser und scrollen als winzig
	local z = math.clamp(math.max(fit, 0.55), ZOOM_MIN, 1)
	setZoom(z)
	local size = vp.AbsoluteSize
	canvas.CanvasPosition = Vector2.new(
		math.max(0, Layout.SIZE.x * z / 2 - size.X / 2),
		math.max(0, Layout.SIZE.y * z - size.Y))
end

local function focusNode(eggId: string)
	local canvas, vp = _canvas, _viewport
	local p = Layout.NODES[eggId]
	if not (canvas and vp and p) then return end
	local size = vp.AbsoluteSize
	canvas.CanvasPosition = Vector2.new(p.x * _zoom - size.X / 2, p.y * _zoom - size.Y / 2)
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
	for i, drop in drops(eggId) do
		if i > 4 then break end
		local bdef = BaerchiConfig.getById(drop.configId)
		if not bdef then continue end
		local known = data.discovered and data.discovered[drop.configId]
		local nm = if known then Loc.name("baerchi." .. drop.configId .. ".name", bdef.displayName) else "???"
		local pct = drop.chance * 100
		local pctText = if pct >= 10 then Loc.formatNumber(math.round(pct)) .. "%" else Loc.formatDecimal(pct, 1) .. "%"
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
	elseif c.kind == "hatchAny" then
		return Loc.t("ui.tree.cond_any", { have = c.have, need = c.need })
	elseif c.kind == "index" then
		return Loc.t("ui.tree.cond_index", { rarity = rarityName(c.rarity :: string), have = c.have, need = c.need })
	elseif c.kind == "rebirth" then
		return Loc.t("ui.tree.cond_rebirth", { have = c.have, need = c.need })
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

local function buildDetail(detail: ScrollingFrame, data: Types.PlayerDataUpdate)
	for _, child in detail:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
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
	local egg = EggIcon.make(top, eggId, 92, nil, { idle = true, pedestal = true })
	egg.Position = UDim2.fromOffset(4, 2)
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
	Theme.setEnabled(openBtn, stock > 0)
	openBtn.Activated:Connect(function()
		local now = ClientState.get()
		if not now or (now.island.eggStock[eggId] or 0) <= 0 then return end
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
			local name = if known then Loc.name("baerchi." .. drop.configId .. ".name", bdef.displayName) else "???"
			local pct = drop.chance * 100
			local pctText = if pct >= 10 then Loc.formatNumber(math.round(pct)) .. "%" else Loc.formatDecimal(pct, 1) .. "%"
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
	local root, vp, host = _root, _viewport, _detailHost
	if not (root and vp and host) then return end
	_narrow = root.AbsoluteSize.X < NARROW_W
	if _narrow then
		vp.Size = UDim2.fromScale(1, 1)
		host.Size = UDim2.new(0, math.min(DETAIL_W, math.floor(root.AbsoluteSize.X * 0.62)), 1, 0)
		host.Visible = _detailOpen
		host.ZIndex = 20
	else
		vp.Size = UDim2.new(1, -DETAIL_W - 10, 1, 0)
		host.Size = UDim2.new(0, DETAIL_W, 1, 0)
		host.Visible = true
	end
	if _detailClose then _detailClose.Visible = _narrow end
end

function selectNode(eggId: string)
	_selected = eggId :: Types.EggType
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
		node.count.Text = if stock > 0 then "x" .. stock else ""
		node.name.Text = eggName(eggId)
		node.ring.Visible = eggId == _selected

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
	local focus = false
	if typeof(eggId) == "string" and EggConfig.data[eggId :: Types.EggType] then
		_selected = eggId :: Types.EggType
		focus = true
	end
	root.Visible = true
	_detailOpen = not _narrow or focus
	applyLayout()
	-- Erst im naechsten Frame hat das Fenster seine Groesse.
	task.defer(function()
		resetView()
		if focus and Layout.NODES[eggId] then focusNode(eggId) end
	end)
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

local function buildBackground(vp: Frame)
	local bg = Icons.uiImage(vp, "tree/tree_bg")
	if bg then
		bg.Name = "Background"
		bg.Size = UDim2.fromScale(1, 1)
		bg.ScaleType = Enum.ScaleType.Crop
		bg.ZIndex = 1
	else
		local f = Instance.new("Frame")
		f.Name = "Background"
		f.Size = UDim2.fromScale(1, 1)
		f.BackgroundColor3 = Color3.fromRGB(70, 44, 26)
		f.BorderSizePixel = 0
		f.ZIndex = 1
		f.Parent = vp
		Theme.gradient(f, Color3.fromRGB(70, 60, 56), Color3.fromRGB(255, 220, 170), 90)
	end
	Theme.corner(vp, 12)

	-- Treibende Pollen und Honiglichter
	local motes = layer("Motes", vp, 2)
	for i = 1, 22 do
		local honey = i % 3 == 0
		local size = if honey then math.random(18, 34) else math.random(5, 11)
		local obj: GuiObject
		local img = Icons.uiImage(motes, if honey then "fx/honeylight" else "fx/pollen")
		if img then
			obj = img
		else
			local f = Instance.new("Frame")
			f.BackgroundColor3 = if honey then Theme.COLORS.honey else Theme.COLORS.cream
			f.BorderSizePixel = 0
			f.Parent = motes
			capsule(f)
			obj = f
			size = math.floor(size * 0.5)
		end
		obj.AnchorPoint = Vector2.new(0.5, 0.5)
		obj.Size = UDim2.fromOffset(size, size)
		table.insert(_particles, {
			obj = obj, x = math.random(), y = math.random(),
			vy = (if honey then 0.012 else 0.025) * (0.6 + math.random()),
			amp = 0.01 + math.random() * 0.02, phase = math.random() * 6, size = size,
		})
	end
end

local function zoomButton(parent: Instance, text: string, x: number, onClick: () -> ())
	local b = Theme.button("Zoom", parent, text, Theme.COLORS.honey)
	b.AnchorPoint = Vector2.new(0, 1)
	b.Position = UDim2.new(0, x, 1, -10)
	b.Size = UDim2.fromOffset(38, 38)
	b.ZIndex = 5
	b.Activated:Connect(onClick)
end

function EggTreePanel.init(screenGui: ScreenGui)
	local root = Theme.dialog("EggTreePanel", screenGui, Vector2.new(0.94, 0.9), Vector2.new(480, 300), Vector2.new(1280, 780))
	_root = root

	_header = Theme.dialogHeader(root, Loc.t("ui.tree.title"), function()
		PanelManager.close(PANEL_NAME)
	end)

	local body = Theme.dialogBody(root)
	_body = body
	Theme.ornateDialog(root)

	-- Baum-Fenster
	local vp = Instance.new("Frame")
	vp.Name = "Viewport"
	vp.BackgroundTransparency = 1
	vp.ClipsDescendants = true
	vp.Size = UDim2.new(1, -DETAIL_W - 10, 1, 0)
	vp.Parent = body
	_viewport = vp
	buildBackground(vp)

	local canvas = Instance.new("ScrollingFrame")
	canvas.Name = "Canvas"
	canvas.BackgroundTransparency = 1
	canvas.BorderSizePixel = 0
	canvas.ScrollBarThickness = 6
	canvas.ScrollBarImageColor3 = Theme.COLORS.honey
	canvas.ScrollingDirection = Enum.ScrollingDirection.XY
	canvas.ElasticBehavior = Enum.ElasticBehavior.Never
	canvas.Size = UDim2.fromScale(1, 1)
	canvas.ZIndex = 3
	canvas.Parent = vp
	_canvas = canvas

	local content = Theme.container("Content", canvas)
	content.Size = UDim2.fromOffset(Layout.SIZE.x, Layout.SIZE.y)
	_content = content
	local scale = Instance.new("UIScale")
	scale.Parent = content
	_zoomScale = scale

	zoomButton(vp, "+", 10, function() setZoom(_zoom * 1.25) end)
	zoomButton(vp, "−", 54, function() setZoom(_zoom / 1.25) end)
	zoomButton(vp, "⤢", 98, resetView)

	-- Detail-Karte
	local host = Theme.panel("Detail", body, Theme.COLORS.forest)
	host.AnchorPoint = Vector2.new(1, 0)
	host.Position = UDim2.new(1, 0, 0, 0)
	host.Size = UDim2.new(0, DETAIL_W, 1, 0)
	host.ZIndex = 10
	Theme.ornate(host, "card", 0.45)
	_detailHost = host
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
	close.Visible = false
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

	-- Zoom: Pinch (Handy) und Strg + Mausrad (PC)
	local pinchStart = 1
	UserInputService.TouchPinch:Connect(function(positions: { Vector2 }, s: number, _velocity: number, state: Enum.UserInputState)
		if not root.Visible then return end
		if state == Enum.UserInputState.Begin then
			pinchStart = _zoom
		elseif state == Enum.UserInputState.Change and #positions >= 2 then
			local mid = (positions[1] + positions[2]) / 2 - vp.AbsolutePosition
			setZoom(pinchStart * s, mid)
		end
	end)
	vp.InputChanged:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseWheel
			and (UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)) then
			local pos = Vector2.new(input.Position.X, input.Position.Y) - vp.AbsolutePosition
			setZoom(_zoom * (if input.Position.Z > 0 then 1.15 else 1 / 1.15), pos)
		end
	end)

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

	print("[EggTreePanel] Initialisiert |", #EggConfig.getOrderedIds(), "Knoten")
end

return EggTreePanel
