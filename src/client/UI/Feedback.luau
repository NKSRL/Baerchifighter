--!strict
-- Feedback.luau
-- StarterPlayerScripts/UI/Feedback.luau
--
-- Einzige Zustaendigkeit:
--   - Gewinne ohne Text zeigen: Icon fliegt zur passenden Pille/Kachel,
--     eine Zahl ("+25") steigt auf, Honig/XP/Stufen als Zahl ueber dem Baerchi
--
-- Kontext: HBB Paket 1. Ein Kind soll Belohnungen sehen, nicht lesen.
--
-- Zwei Quellen:
--   1. Waehrungen und Eier erkennt dieses Modul selbst am Datenstand
--      (ClientState): steigt `gummies`, `goldGummies` oder die Summe im
--      Ei-Lager, fliegt ein Icon. So braucht keine Belohnungsstelle eigenen
--      Code, und nichts wird doppelt gezeigt.
--   2. Alles, was keine Pille hat (XP, Honig, Level, Stat-Stufe, Waben,
--      Ausbau), meldet der Aufrufer mit Feedback.gain(kind, amount, origin?).
--
-- Leistung: ein fester Pool wiederverwendeter Elemente und EINE Schleife pro
-- Frame. Kein Thread und kein Tween pro Icon.
--
-- Mit FeatureFlags.UI_V2_FEEDBACK = false zeigt dieses Modul nichts.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local GuiService        = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local Types          = require(ReplicatedStorage.Network.Types)
local FeedbackConfig = require(ReplicatedStorage.Config.FeedbackConfig)
local FeatureFlags   = require(ReplicatedStorage.Config.FeatureFlags)

local Theme       = require(script.Parent.Theme)
local UiScale     = require(script.Parent.UiScale)
local Icons       = require(script.Parent.Icons)
local Hud         = require(script.Parent.Hud)
local MenuBar     = require(script.Parent.MenuBar)
local ClientState = require(script.Parent.Parent.Controllers.ClientState)

local Feedback = {}

export type Origin = GuiObject | Vector3 | BasePart

-- Wie jede Art aussieht. `icon` = Name in Icons, `text` = Rueckfall/Praefix.
-- `me` = Zahl ueber dem eigenen Charakter statt ueber dem Baerchi.
local LOOK: { [string]: { icon: string?, text: string, color: Color3, float: boolean, me: boolean? } } = {
	gummies     = { icon = "gummy",     text = "G",  color = Theme.COLORS.gummy,     float = false },
	goldGummies = { icon = "goldgummy", text = "$",  color = Theme.COLORS.goldGummy, float = false },
	eggs        = { icon = "egg",       text = "🥚", color = Theme.COLORS.text,      float = false },
	xp          = { icon = nil,         text = "XP", color = Theme.COLORS.growth,    float = true },
	honey       = { icon = "honey",     text = "",   color = Theme.COLORS.volume,    float = true },
	level       = { icon = nil,         text = "Lv", color = Theme.COLORS.good,      float = true },
	stat        = { icon = nil,         text = "",   color = Theme.COLORS.accent,    float = true },
	comb        = { icon = "honey",     text = "",   color = Theme.COLORS.volume,    float = true, me = true },
	upgrade     = { icon = nil,         text = "⬆",  color = Theme.COLORS.good,      float = true, me = true },
	star        = { icon = nil,         text = "★",  color = Theme.COLORS.goldGummy, float = true },
}

-- Groesse eines fliegenden Icons (px)
local ICON_SIZE = 38
-- Wie hoch die Zahl ueber den Startpunkt steigt (px)
local NUMBER_RISE = 46
-- Wie hoch die Zahl ueber dem Baerchi steigt (Studs)
local FLOAT_RISE = 3
local FLOAT_BASE = 4

type Flyer = {
	frame  : Frame,
	icon   : GuiObject,
	number : TextLabel,
	busy   : boolean,
	t0     : number,
	from   : Vector2,
	to     : Vector2?,
	kind   : string,
	landed : boolean,
	spent  : boolean,   -- Paket G: Betrag fliegt AUS der Pille (keinen Puls am Ziel)
}

type Floater = {
	gui    : BillboardGui,
	label  : TextLabel,
	busy   : boolean,
	t0     : number,
}

local _layer: Frame? = nil
local _flyers: { Flyer } = {}
local _floaters: { Floater } = {}

-- Sammeln gleicher Gewinne im MERGE_WINDOW
local _pending: { [string]: { amount: number, origin: Origin?, due: number, suffix: string? } } = {}

-- Letzter bekannter Stand fuer die Erkennung aus ClientState
local _last: { gummies: number, goldGummies: number, eggs: number }? = nil

-- Zwischenspeicher fuer die Figur des ausgeruesteten Baerchis
local _bearPart: BasePart? = nil
local _bearUid: string? = nil

local function enabled(): boolean
	return FeatureFlags.isOn("UI_V2_FEEDBACK")
end

local function formatAmount(kind: string, amount: number, suffix: string?): string
	if suffix then
		return "+" .. Theme.formatNumber(amount) .. " " .. suffix
	end
	local look = LOOK[kind]
	local prefix = if look then look.text else ""
	if kind == "level" then
		return prefix .. " " .. Theme.formatNumber(amount)
	elseif kind == "upgrade" or kind == "star" then
		return prefix .. " " .. Theme.formatNumber(amount)
	elseif kind == "xp" then
		return "+" .. Theme.formatNumber(amount) .. " " .. prefix
	end
	return "+" .. Theme.formatNumber(amount)
end

--------------------------------------------------------------------------------
-- Positionen
--------------------------------------------------------------------------------

local function guiCenter(gui: GuiObject): Vector2
	-- Bildschirm-Pixel -> Oberflaechen-Einheiten (globale UiScale)
	return UiScale.toGui(gui.AbsolutePosition + gui.AbsoluteSize * 0.5)
end

local function worldToScreen(position: Vector3): Vector2?
	local camera = Workspace.CurrentCamera
	if not camera then return nil end
	local point, visible = camera:WorldToViewportPoint(position)
	if not visible then return nil end
	-- Die ScreenGui laesst Platz fuer die Topbar (IgnoreGuiInset = false):
	-- Viewport-Koordinaten muessen um diesen Rand verschoben werden.
	local inset = GuiService:GetGuiInset()
	return UiScale.toGui(Vector2.new(point.X, point.Y) - inset)
end

local function defaultOrigin(): Vector2
	local layer = _layer
	if not layer then return Vector2.zero end
	local size = UiScale.toGui(layer.AbsoluteSize)
	-- Ueber der Pet-Leiste, wo der Blick ohnehin ist
	return Vector2.new(size.X * 0.5, size.Y * 0.72)
end

local function resolveOrigin(origin: Origin?): Vector2
	if typeof(origin) == "Instance" then
		if origin:IsA("GuiObject") then
			return guiCenter(origin)
		elseif origin:IsA("BasePart") then
			return worldToScreen(origin.Position) or defaultOrigin()
		end
	elseif typeof(origin) == "Vector3" then
		return worldToScreen(origin) or defaultOrigin()
	end
	return defaultOrigin()
end

local function targetFor(kind: string): GuiObject?
	local anchor = Hud.getPillAnchor(kind)
	if anchor then return anchor end
	if kind == "eggs" then
		return MenuBar.getTileAnchor("Hatch")
	end
	return nil
end

local function pulseTarget(kind: string, target: GuiObject?)
	if Hud.getPillAnchor(kind) then
		Hud.pulse(kind)
	elseif target then
		local scale = target:FindFirstChild("PulseScale")
		if not scale then
			local created = Instance.new("UIScale")
			created.Name = "PulseScale"
			created.Parent = target
			scale = created
		end
		local uiScale = scale :: UIScale
		uiScale.Scale = 1.15
	end
end

-- Sucht die Figur des eigenen, ausgeruesteten Baerchis (Attribut BaerchiUid,
-- siehe WorldController). Bleibt zwischengespeichert, bis sie verschwindet.
local function findBearPart(): BasePart?
	local data = ClientState.get()
	local uid = if data then data.island.equippedUid else nil
	if not uid then return nil end
	local cached = _bearPart
	if cached and cached.Parent and _bearUid == uid then
		return cached
	end
	_bearPart = nil
	_bearUid = uid
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("BaerchiUid") == uid then
			_bearPart = descendant
			return descendant
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Pools
--------------------------------------------------------------------------------

local function makeFlyer(layer: Frame): Flyer
	local frame = Instance.new("Frame")
	frame.Name = "Flyer"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Visible = false
	frame.ZIndex = 60
	frame.Parent = layer

	local number = Theme.label("Number", layer, "")
	number.AnchorPoint = Vector2.new(0.5, 0.5)
	number.Size = UDim2.fromOffset(120, 34)
	number.TextXAlignment = Enum.TextXAlignment.Center
	number.ZIndex = 61
	number.Visible = false
	Theme.outlineText(number, 2)

	return {
		frame = frame, icon = frame, number = number, busy = false,
		t0 = 0, from = Vector2.zero, to = nil, kind = "", landed = false, spent = false,
	}
end

local function setFlyerLook(flyer: Flyer, kind: string)
	if flyer.kind == kind and flyer.icon ~= flyer.frame then return end
	if flyer.icon ~= flyer.frame then
		flyer.icon:Destroy()
	end
	local look = LOOK[kind]
	local iconName = if look then look.icon else nil
	local icon = Icons.make(flyer.frame, iconName or "", if look then look.text else "?")
	icon.Size = UDim2.fromScale(1, 1)
	icon.ZIndex = 60
	flyer.icon = icon
	flyer.kind = kind
end

local function makeFloater(): Floater
	local gui = Instance.new("BillboardGui")
	gui.Name = "FeedbackFloat"
	gui.Size = UDim2.fromOffset(160, 44)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Enabled = false
	gui.ResetOnSpawn = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	local label = Theme.label("Text", gui, "")
	label.Size = UDim2.fromScale(1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Center
	Theme.outlineText(label, 2)

	return { gui = gui, label = label, busy = false, t0 = 0 }
end

--------------------------------------------------------------------------------
-- Ausloesen
--------------------------------------------------------------------------------

local function launchFlyer(kind: string, amount: number, origin: Origin?)
	local free: Flyer? = nil
	for _, flyer in _flyers do
		if not flyer.busy then
			free = flyer
			break
		end
	end
	-- Alle belegt: die Pille zaehlt den Wert ohnehin hoch. Kein siebtes Icon.
	if not free then return end

	local target = targetFor(kind)
	local from = resolveOrigin(origin)
	setFlyerLook(free, kind)
	free.busy   = true
	free.landed = false
	free.spent  = false
	free.t0     = os.clock()
	free.from   = from
	free.to     = if target then guiCenter(target) else nil
	free.frame.Position = UDim2.fromOffset(from.X, from.Y)
	free.frame.Visible  = true

	local look = LOOK[kind]
	free.number.Text       = formatAmount(kind, amount)
	free.number.TextColor3 = if look then look.color else Theme.COLORS.text
	free.number.Position   = UDim2.fromOffset(from.X, from.Y - 20)
	free.number.TextTransparency = 0
	free.number.Visible    = true
end

local function characterPart(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and root:IsA("BasePart") then return root end
	return nil
end

local function launchFloater(kind: string, amount: number, suffix: string?)
	local look0 = LOOK[kind]
	local part = if look0 and look0.me then characterPart() else findBearPart()
	if not part then return end
	local free: Floater? = nil
	for _, floater in _floaters do
		if not floater.busy then
			free = floater
			break
		end
	end
	if not free then return end
	local look = LOOK[kind]
	free.busy = true
	free.t0 = os.clock()
	free.gui.Adornee = part
	free.gui.StudsOffset = Vector3.new(0, FLOAT_BASE, 0)
	free.gui.Enabled = true
	free.label.Text = formatAmount(kind, amount, suffix)
	free.label.TextColor3 = if look then look.color else Theme.COLORS.text
	free.label.TextTransparency = 0
end

local function flush(kind: string)
	local entry = _pending[kind]
	_pending[kind] = nil
	if not entry or entry.amount == 0 then return end
	local look = LOOK[kind]
	if look and look.float then
		launchFloater(kind, entry.amount, entry.suffix)
	else
		launchFlyer(kind, entry.amount, entry.origin)
	end
end

-- Oeffentlich: einen Gewinn zeigen. Gleiche Arten innerhalb des
-- MERGE_WINDOW werden zu einer Zahl addiert. Bei "level", "upgrade" und
-- "star" ist `amount` die neue Stufe (wird nicht addiert, sondern ersetzt).
-- `suffix`: kurzes Kuerzel hinter der Zahl ("+1 ATK"); nur Zahlen und
-- sprachneutrale Kuerzel, keine Woerter.
function Feedback.gain(kind: string, amount: number, origin: Origin?, suffix: string?)
	if not enabled() then return end
	if not LOOK[kind] then
		warn("[Feedback] Unbekannte Art:", kind)
		return
	end
	local entry = _pending[kind]
	if entry then
		if kind == "level" or kind == "upgrade" or kind == "star" then
			entry.amount = amount
		else
			entry.amount += amount
		end
		entry.origin = origin or entry.origin
		entry.suffix = suffix or entry.suffix
	else
		_pending[kind] = { amount = amount, origin = origin, due = os.clock() + FeedbackConfig.MERGE_WINDOW, suffix = suffix }
	end
end

-- Paket G (08.10.): einen BEZAHLTEN Betrag zeigen. Das Icon fliegt aus der
-- Pille zum Ziel in der Welt (z. B. dem ausgebauten Gebaeude), an der Pille
-- steigt "-1.234" auf. Nur aufrufen, wenn der Server die Ausgabe bestaetigt
-- hat (Datenstand), nie spekulativ.
function Feedback.spend(kind: string, amount: number, toWorld: Vector3?)
	if not enabled() or amount <= 0 then return end
	local pill = targetFor(kind)
	if not pill then return end
	local free: Flyer? = nil
	for _, flyer in _flyers do
		if not flyer.busy then
			free = flyer
			break
		end
	end
	if not free then return end
	local from = guiCenter(pill)
	setFlyerLook(free, kind)
	free.busy   = true
	free.landed = false
	free.spent  = true
	free.t0     = os.clock()
	free.from   = from
	free.to     = if toWorld then worldToScreen(toWorld) else nil
	free.frame.Position = UDim2.fromOffset(from.X, from.Y)
	free.frame.Visible  = true
	free.number.Text       = "-" .. Theme.formatNumber(amount)
	free.number.TextColor3 = Theme.COLORS.bad
	free.number.Position   = UDim2.fromOffset(from.X, from.Y + 20)
	free.number.TextTransparency = 0
	free.number.Visible    = true
	Hud.pulse(kind)
end

--------------------------------------------------------------------------------
-- Die eine Schleife
--------------------------------------------------------------------------------

local function easeOut(t: number): number
	return 1 - (1 - t) * (1 - t)
end

local function step()
	local now = os.clock()

	for kind, entry in _pending do
		if now >= entry.due then
			flush(kind)
		end
	end

	local fly = FeedbackConfig.FLY_SECONDS
	local rise = FeedbackConfig.NUMBER_SECONDS
	for _, flyer in _flyers do
		if not flyer.busy then continue end
		local t = now - flyer.t0

		-- Zahl: steigt am Startpunkt auf und blendet aus
		local tn = math.clamp(t / rise, 0, 1)
		-- Ausgaben (spend) sinken unter der Pille ab: die Pille sitzt oben
		-- am Rand, nach oben waere kein Platz.
		local dy = if flyer.spent then 26 + NUMBER_RISE * easeOut(tn) else -20 - NUMBER_RISE * easeOut(tn)
		flyer.number.Position = UDim2.fromOffset(flyer.from.X, flyer.from.Y + dy)
		flyer.number.TextTransparency = math.max(0, (tn - 0.6) / 0.4)

		-- Icon: Bogen zum Ziel (ohne Ziel: nur kurz aufsteigen)
		local tf = math.clamp(t / fly, 0, 1)
		local to = flyer.to or (flyer.from - Vector2.new(0, 80))
		local mid = (flyer.from + to) * 0.5 + Vector2.new(0, -90)
		local e = easeOut(tf)
		local a = flyer.from:Lerp(mid, e)
		local b = mid:Lerp(to, e)
		local p = a:Lerp(b, e)
		flyer.frame.Position = UDim2.fromOffset(p.X, p.Y)
		local size = ICON_SIZE * (1 - 0.35 * tf)
		flyer.frame.Size = UDim2.fromOffset(size, size)

		if tf >= 1 and not flyer.landed then
			flyer.landed = true
			flyer.frame.Visible = false
			if not flyer.spent then
				pulseTarget(flyer.kind, targetFor(flyer.kind))
			end
		end
		if tf >= 1 and tn >= 1 then
			flyer.busy = false
			flyer.number.Visible = false
		end
	end

	local floatTime = FeedbackConfig.FLOAT_SECONDS
	for _, floater in _floaters do
		if not floater.busy then continue end
		local t = math.clamp((now - floater.t0) / floatTime, 0, 1)
		floater.gui.StudsOffset = Vector3.new(0, FLOAT_BASE + FLOAT_RISE * easeOut(t), 0)
		floater.label.TextTransparency = math.max(0, (t - 0.6) / 0.4)
		if t >= 1 then
			floater.busy = false
			floater.gui.Enabled = false
			floater.gui.Adornee = nil
		end
	end

	-- Puls der Kacheln zurueckfedern (Pillen machen das selbst per Tween)
	local tile = MenuBar.getTileAnchor("Hatch")
	if tile then
		local scale = tile:FindFirstChild("PulseScale")
		if scale and scale:IsA("UIScale") and scale.Scale > 1 then
			scale.Scale = math.max(1, scale.Scale - 0.6 * (1 / 60))
		end
	end
end

--------------------------------------------------------------------------------
-- Erkennung aus dem Datenstand
--------------------------------------------------------------------------------

local function countEggs(data: Types.PlayerDataUpdate): number
	local total = 0
	for _, n in data.island.eggStock do
		total += n
	end
	return total
end

local function onData(data: Types.PlayerDataUpdate)
	local now = { gummies = data.gummies, goldGummies = data.goldGummies, eggs = countEggs(data) }
	local last = _last
	_last = now
	-- Erster Stand nach dem Join ist kein Gewinn
	if not last then return end
	if now.gummies > last.gummies then Feedback.gain("gummies", now.gummies - last.gummies) end
	if now.goldGummies > last.goldGummies then Feedback.gain("goldGummies", now.goldGummies - last.goldGummies) end
	if now.eggs > last.eggs then Feedback.gain("eggs", now.eggs - last.eggs) end
end

--------------------------------------------------------------------------------
-- Initialisierung
--------------------------------------------------------------------------------

function Feedback.init(screenGui: ScreenGui)
	local layer = Theme.container("FeedbackLayer", screenGui)
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = 60
	_layer = layer

	for _ = 1, FeedbackConfig.MAX_ICONS do
		table.insert(_flyers, makeFlyer(layer))
	end
	for _ = 1, FeedbackConfig.MAX_FLOATS do
		table.insert(_floaters, makeFloater())
	end

	ClientState.onChanged(onData)
	RunService.RenderStepped:Connect(step)

	print("[Feedback] Initialisiert")
end

return Feedback
