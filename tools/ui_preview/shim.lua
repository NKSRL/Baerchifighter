-- shim.lua — Roblox-Attrappe fuer die UI-Vorschau (tools/ui_preview)
--
-- Genug von Roblox, damit die Client-UI-Module (Theme, Kit, TowerPanel,
-- CombatPanel, Hud, MenuBar, PetBar ...) ohne Studio laufen und ihren
-- Instanz-Baum bauen. Der Baum wird danach als JSON ausgegeben und von
-- render.js im Browser gezeichnet (Layout wie Roblox: UDim2, AnchorPoint,
-- UIListLayout, UIPadding, UIScale, UICorner, UIStroke, UIGradient,
-- TextScaled + UITextSizeConstraint).
--
-- Nicht nachgebaut: Physik, 3D, Netzwerk. Remotes sind Attrappen, deren
-- OnClientEvent der Treiber selbst feuert (z. B. PlayerDataUpdated).

local SOURCES = __SOURCES

--------------------------------------------------------------------------------
-- Datentypen
--------------------------------------------------------------------------------

local function typed(t, name, mt)
	t.__type = name
	return setmetatable(t, mt)
end

local UDimMT = {}
UDimMT.__index = UDimMT
UDimMT.__add = function(a, b) return UDim.new(a.Scale + b.Scale, a.Offset + b.Offset) end
UDim = { new = function(s, o) return typed({ Scale = s or 0, Offset = o or 0 }, "UDim", UDimMT) end }

local UDim2MT = {}
UDim2MT.__index = function(t, k)
	if k == "Width" then return rawget(t, "X") end
	if k == "Height" then return rawget(t, "Y") end
	return nil
end
UDim2MT.__add = function(a, b) return UDim2.new(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset) end
UDim2MT.__sub = function(a, b) return UDim2.new(a.X.Scale - b.X.Scale, a.X.Offset - b.X.Offset, a.Y.Scale - b.Y.Scale, a.Y.Offset - b.Y.Offset) end
UDim2 = {
	new = function(xs, xo, ys, yo)
		if type(xs) == "table" then
			return typed({ X = xs, Y = xo }, "UDim2", UDim2MT)
		end
		return typed({ X = UDim.new(xs, xo), Y = UDim.new(ys, yo) }, "UDim2", UDim2MT)
	end,
}
UDim2.fromScale = function(x, y) return UDim2.new(x, 0, y, 0) end
UDim2.fromOffset = function(x, y) return UDim2.new(0, x, 0, y) end

local V2MT = {}
local function v2(x, y) return typed({ X = x or 0, Y = y or 0 }, "Vector2", V2MT) end
V2MT.__index = function(a, k)
	if k == "Magnitude" then return math.sqrt(a.X ^ 2 + a.Y ^ 2) end
	if k == "Unit" then local m = math.sqrt(a.X ^ 2 + a.Y ^ 2); return v2(a.X / m, a.Y / m) end
	if k == "Lerp" then return function(self, b, t) return v2(self.X + (b.X - self.X) * t, self.Y + (b.Y - self.Y) * t) end end
	return nil
end
V2MT.__add = function(a, b) return v2(a.X + b.X, a.Y + b.Y) end
V2MT.__sub = function(a, b) return v2(a.X - b.X, a.Y - b.Y) end
V2MT.__unm = function(a) return v2(-a.X, -a.Y) end
V2MT.__mul = function(a, b)
	if type(a) == "number" then return v2(b.X * a, b.Y * a) end
	if type(b) == "number" then return v2(a.X * b, a.Y * b) end
	return v2(a.X * b.X, a.Y * b.Y)
end
V2MT.__div = function(a, b)
	if type(b) == "number" then return v2(a.X / b, a.Y / b) end
	return v2(a.X / b.X, a.Y / b.Y)
end
V2MT.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
Vector2 = { new = v2 }
Vector2.zero = v2(0, 0)
Vector2.one = v2(1, 1)

local V3MT = {}
local function v3(x, y, z) return typed({ X = x or 0, Y = y or 0, Z = z or 0 }, "Vector3", V3MT) end
V3MT.__index = function(a, k)
	if k == "Magnitude" then return math.sqrt(a.X ^ 2 + a.Y ^ 2 + a.Z ^ 2) end
	if k == "Unit" then local m = math.sqrt(a.X ^ 2 + a.Y ^ 2 + a.Z ^ 2); return v3(a.X / m, a.Y / m, a.Z / m) end
	return nil
end
V3MT.__add = function(a, b) return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3MT.__sub = function(a, b) return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3MT.__unm = function(a) return v3(-a.X, -a.Y, -a.Z) end
V3MT.__mul = function(a, b)
	if type(a) == "number" then return v3(b.X * a, b.Y * a, b.Z * a) end
	if type(b) == "number" then return v3(a.X * b, a.Y * b, a.Z * b) end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3MT.__div = function(a, b) return v3(a.X / b, a.Y / b, a.Z / b) end
Vector3 = { new = v3 }
Vector3.zero = v3(0, 0, 0)
Vector3.one = v3(1, 1, 1)

local C3MT = {}
local function c3(r, g, b) return typed({ R = r or 0, G = g or 0, B = b or 0 }, "Color3", C3MT) end
C3MT.__index = function(c, k)
	if k == "Lerp" then
		return function(self, o, t) return c3(self.R + (o.R - self.R) * t, self.G + (o.G - self.G) * t, self.B + (o.B - self.B) * t) end
	elseif k == "ToHSV" then
		return function(self)
			local r, g, b = self.R, self.G, self.B
			local mx, mn = math.max(r, g, b), math.min(r, g, b)
			local h, s, v = 0, 0, mx
			local d = mx - mn
			if mx > 0 then s = d / mx end
			if d > 0 then
				if mx == r then h = (g - b) / d % 6 elseif mx == g then h = (b - r) / d + 2 else h = (r - g) / d + 4 end
				h = h / 6
			end
			return h, s, v
		end
	end
	return nil
end
C3MT.__eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end
Color3 = {
	new = c3,
	fromRGB = function(r, g, b) return c3((r or 0) / 255, (g or 0) / 255, (b or 0) / 255) end,
	fromHSV = function(h, s, v)
		local i = math.floor(h * 6)
		local f = h * 6 - i
		local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
		i = i % 6
		if i == 0 then return c3(v, t, p) elseif i == 1 then return c3(q, v, p) elseif i == 2 then return c3(p, v, t)
		elseif i == 3 then return c3(p, q, v) elseif i == 4 then return c3(t, p, v) end
		return c3(v, p, q)
	end,
	fromHex = function(hex)
		hex = string.gsub(hex, "#", "")
		return c3(tonumber(string.sub(hex, 1, 2), 16) / 255, tonumber(string.sub(hex, 3, 4), 16) / 255, tonumber(string.sub(hex, 5, 6), 16) / 255)
	end,
}

ColorSequenceKeypoint = { new = function(t, c) return typed({ Time = t, Value = c }, "ColorSequenceKeypoint", {}) end }
ColorSequence = {
	new = function(a, b)
		if type(a) == "table" and a.__type == "Color3" then
			return typed({ Keypoints = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b or a) } }, "ColorSequence", {})
		end
		return typed({ Keypoints = a }, "ColorSequence", {})
	end,
}
NumberSequenceKeypoint = { new = function(t, v, e) return typed({ Time = t, Value = v, Envelope = e or 0 }, "NumberSequenceKeypoint", {}) end }
NumberSequence = {
	new = function(a, b)
		if type(a) == "number" then
			return typed({ Keypoints = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b or a) } }, "NumberSequence", {})
		end
		return typed({ Keypoints = a }, "NumberSequence", {})
	end,
}
NumberRange = { new = function(a, b) return typed({ Min = a, Max = b or a }, "NumberRange", {}) end }
TweenInfo = { new = function(...) return typed({ args = { ... } }, "TweenInfo", {}) end }
Rect = { new = function(...) return typed({ args = { ... } }, "Rect", {}) end }

local CFMT = {}
CFMT.__index = function(t, k)
	if k == "Position" then return rawget(t, "p") end
	if k == "LookVector" then return v3(0, 0, -1) end
	return function() return t end
end
CFMT.__mul = function(a, b) return a end
CFrame = {
	new = function(x, y, z) return typed({ p = if type(x) == "number" then v3(x, y, z) else (x or v3()) }, "CFrame", CFMT) end,
	Angles = function() return typed({ p = v3() }, "CFrame", CFMT) end,
	lookAt = function(p) return typed({ p = p }, "CFrame", CFMT) end,
	fromEulerAnglesXYZ = function() return typed({ p = v3() }, "CFrame", CFMT) end,
}
CFrame.identity = CFrame.new(0, 0, 0)

-- Enum: Enum.Font.FredokaOne → Token (gleiches Objekt bei gleichem Namen)
local _enumCache = {}
local EnumItemMT = { __tostring = function(e) return "Enum." .. e.EnumType .. "." .. e.Name end }
Enum = setmetatable({}, {
	__index = function(_, enumType)
		return setmetatable({}, {
			__index = function(_, name)
				local key = enumType .. "." .. name
				local item = _enumCache[key]
				if not item then
					item = setmetatable({ EnumType = enumType, Name = name, Value = 0, __type = "EnumItem" }, EnumItemMT)
					_enumCache[key] = item
				end
				return item
			end,
		})
	end,
})

--------------------------------------------------------------------------------
-- Signale und Aufgaben
--------------------------------------------------------------------------------

local SignalMT = {}
SignalMT.__index = SignalMT
function SignalMT:Connect(fn)
	local entry = { fn = fn, Connected = true }
	table.insert(self._fns, entry)
	return { Connected = true, Disconnect = function(c) entry.Connected = false; c.Connected = false end }
end
SignalMT.Once = SignalMT.Connect
function SignalMT:Fire(...)
	for _, e in self._fns do
		if e.Connected then
			local ok, err = pcall(e.fn, ...)
			if not ok then print("[shim] Signal-Fehler: " .. tostring(err)) end
		end
	end
end
function SignalMT:Wait() return nil end
local function newSignal() return setmetatable({ _fns = {} }, SignalMT) end

local _queue = {}
task = {
	spawn = function(fn, ...)
		if type(fn) == "thread" then return fn end
		local ok, err = pcall(fn, ...)
		if not ok then print("[shim] task.spawn-Fehler: " .. tostring(err)) end
		return nil
	end,
	defer = function(fn, ...) table.insert(_queue, { fn = fn, args = { ... } }) end,
	delay = function(_t, fn, ...) table.insert(_queue, { fn = fn, args = { ... } }) end,
	wait = function(t) return t or 0 end,
	cancel = function() end,
}
function __flushTasks()
	for _ = 1, 50 do
		if #_queue == 0 then return end
		local batch = _queue
		_queue = {}
		for _, job in batch do
			local ok, err = pcall(job.fn, table.unpack(job.args))
			if not ok then print("[shim] Aufgaben-Fehler: " .. tostring(err)) end
		end
	end
end
wait = function(t) return t or 0 end
delay = function(_t, fn) table.insert(_queue, { fn = fn, args = {} }) end
spawn = function(fn) pcall(fn) end
tick = os.clock
time = os.clock
warn = function(...) print("[warn]", ...) end

--------------------------------------------------------------------------------
-- Instanzen
--------------------------------------------------------------------------------

local IS_A = {
	GuiObject = { Frame = true, TextLabel = true, TextButton = true, ImageLabel = true, ImageButton = true, ScrollingFrame = true, CanvasGroup = true, TextBox = true },
	GuiButton = { TextButton = true, ImageButton = true },
	GuiBase2d = { Frame = true, TextLabel = true, TextButton = true, ImageLabel = true, ImageButton = true, ScrollingFrame = true, ScreenGui = true, BillboardGui = true, SurfaceGui = true },
	LayerCollector = { ScreenGui = true, BillboardGui = true, SurfaceGui = true },
	BasePart = { Part = true, MeshPart = true },
	LuaSourceContainer = {},
}

local DEFAULTS = {
	Visible = true, ZIndex = 1, BackgroundTransparency = 0, BorderSizePixel = 1,
	Rotation = 0, LayoutOrder = 0, Active = false, AutoButtonColor = true, Selectable = true,
	TextTransparency = 0, TextStrokeTransparency = 1, TextScaled = false, TextWrapped = false,
	TextSize = 14, RichText = false, ImageTransparency = 0, ClipsDescendants = false,
	Enabled = true, Thickness = 1, Transparency = 0, Scale = 1, Rotation_ = 0,
	Offset = nil, Interactable = true,
}

local CLASS_DEFAULTS = {
	Frame         = function() return { Size = UDim2.new(0, 100, 0, 100), BackgroundColor3 = Color3.fromRGB(163, 162, 165) } end,
	TextLabel     = function() return { Size = UDim2.new(0, 200, 0, 50), BackgroundColor3 = Color3.fromRGB(163, 162, 165), Text = "Label", TextColor3 = Color3.new(0, 0, 0), Font = Enum.Font.Legacy, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, TextStrokeColor3 = Color3.new(0, 0, 0) } end,
	TextButton    = function() return { Size = UDim2.new(0, 200, 0, 50), BackgroundColor3 = Color3.fromRGB(163, 162, 165), Text = "Button", TextColor3 = Color3.new(0, 0, 0), Font = Enum.Font.Legacy, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, Active = true, TextStrokeColor3 = Color3.new(0, 0, 0) } end,
	ImageLabel    = function() return { Size = UDim2.new(0, 100, 0, 100), BackgroundColor3 = Color3.fromRGB(163, 162, 165), Image = "", ImageColor3 = Color3.new(1, 1, 1) } end,
	ImageButton   = function() return { Size = UDim2.new(0, 100, 0, 100), BackgroundColor3 = Color3.fromRGB(163, 162, 165), Image = "", ImageColor3 = Color3.new(1, 1, 1), Active = true } end,
	ScrollingFrame = function() return { Size = UDim2.new(0, 100, 0, 100), BackgroundColor3 = Color3.fromRGB(163, 162, 165), CanvasPosition = Vector2.new(0, 0), CanvasSize = UDim2.new(0, 0, 2, 0), ClipsDescendants = true } end,
	UIStroke      = function() return { Color = Color3.new(0, 0, 0), Thickness = 1, Transparency = 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual } end,
	UICorner      = function() return { CornerRadius = UDim.new(0, 8) } end,
	UIGradient    = function() return { Color = ColorSequence.new(Color3.new(1, 1, 1)), Transparency = NumberSequence.new(0), Rotation = 0, Offset = Vector2.new(0, 0) } end,
	UIPadding     = function() return { PaddingTop = UDim.new(0, 0), PaddingBottom = UDim.new(0, 0), PaddingLeft = UDim.new(0, 0), PaddingRight = UDim.new(0, 0) } end,
	UIListLayout  = function() return { FillDirection = Enum.FillDirection.Vertical, Padding = UDim.new(0, 0), SortOrder = Enum.SortOrder.Name, HorizontalAlignment = Enum.HorizontalAlignment.Left, VerticalAlignment = Enum.VerticalAlignment.Top } end,
	UITextSizeConstraint = function() return { MaxTextSize = 100, MinTextSize = 1 } end,
	UISizeConstraint = function() return { MinSize = Vector2.new(0, 0), MaxSize = Vector2.new(math.huge, math.huge) } end,
	UIScale       = function() return { Scale = 1 } end,
	ScreenGui     = function() return { AbsoluteSize = Vector2.new(1920, 1044), Enabled = true } end,
}

local SIGNALS = {
	Activated = true, MouseButton1Down = true, MouseButton1Up = true, MouseButton1Click = true,
	MouseEnter = true, MouseLeave = true, InputBegan = true, InputEnded = true, InputChanged = true,
	Changed = true, ChildAdded = true, ChildRemoved = true, DescendantAdded = true, DescendantRemoving = true,
	Destroying = true, AttributeChanged = true, Triggered = true, TriggerEnded = true, PromptShown = true,
	OnClientEvent = true, OnServerEvent = true, Heartbeat = true, RenderStepped = true, Stepped = true,
	PlayerAdded = true, PlayerRemoving = true, CharacterAdded = true, CharacterRemoving = true,
	Completed = true, Ended = true, Played = true, FocusLost = true, Focused = true,
	TouchTap = true, LastInputTypeChanged = true, MouseClick = true, Died = true,
	PromptGamePassPurchaseFinished = true, WindowFocused = true,
}

local INST = {}
local _nextId = 0
local _allInstances = {}

local function isInstance(v) return type(v) == "table" and rawget(v, "__inst") == true end

local METHODS = {}

local function newInstance(className)
	_nextId += 1
	local props = {}
	local def = CLASS_DEFAULTS[className]
	if def then for k, v in def() do props[k] = v end end
	props.Name = className
	props.ClassName = className
	local inst = setmetatable({
		__inst = true, __id = _nextId, __props = props, __children = {}, __attrs = {},
		__signals = {}, __propSignals = {}, __attrSignals = {}, __parent = nil, __destroyed = false,
	}, INST)
	table.insert(_allInstances, inst)
	return inst
end

local function signalFor(inst, name)
	local s = inst.__signals[name]
	if not s then s = newSignal(); inst.__signals[name] = s end
	return s
end

INST.__index = function(self, k)
	local props = rawget(self, "__props")
	local v = props[k]
	if v ~= nil then return v end
	if k == "Parent" then return rawget(self, "__parent") end
	local m = METHODS[k]
	if m then return m end
	if SIGNALS[k] then return signalFor(self, k) end
	if DEFAULTS[k] ~= nil then return DEFAULTS[k] end
	-- Kind ueber den Namen (Instanz.Kind)
	for _, child in rawget(self, "__children") do
		if child.__props.Name == k then return child end
	end
	return nil
end

local function fireProp(self, k)
	local s = self.__propSignals[k]
	if s then s:Fire() end
	local changed = self.__signals.Changed
	if changed then changed:Fire(k) end
end

INST.__newindex = function(self, k, v)
	if k == "Parent" then
		local old = rawget(self, "__parent")
		if old == v then return end
		if old then
			local list = old.__children
			local i = table.find(list, self)
			if i then table.remove(list, i) end
		end
		rawset(self, "__parent", v)
		if v then
			table.insert(v.__children, self)
			local added = v.__signals.ChildAdded
			if added then added:Fire(self) end
			-- DescendantAdded nach oben melden
			local node = v
			while node do
				local s = node.__signals.DescendantAdded
				if s then s:Fire(self) end
				node = rawget(node, "__parent")
			end
		end
		fireProp(self, "Parent")
		return
	end
	self.__props[k] = v
	fireProp(self, k)
end
INST.__tostring = function(self) return self.__props.Name end

function METHODS.GetChildren(self) return table.clone(self.__children) end
function METHODS.GetDescendants(self)
	local out = {}
	local function walk(n) for _, c in n.__children do table.insert(out, c); walk(c) end end
	walk(self)
	return out
end
function METHODS.FindFirstChild(self, name, recursive)
	for _, c in self.__children do if c.__props.Name == name then return c end end
	if recursive then
		for _, c in self.__children do
			local f = METHODS.FindFirstChild(c, name, true)
			if f then return f end
		end
	end
	return nil
end
function METHODS.WaitForChild(self, name) return METHODS.FindFirstChild(self, name) end
function METHODS.IsA(self, class)
	local cn = self.__props.ClassName
	if cn == class or class == "Instance" then return true end
	local set = IS_A[class]
	return set ~= nil and set[cn] == true
end
function METHODS.FindFirstChildOfClass(self, class)
	for _, c in self.__children do if c.__props.ClassName == class then return c end end
	return nil
end
function METHODS.FindFirstChildWhichIsA(self, class)
	for _, c in self.__children do if METHODS.IsA(c, class) then return c end end
	return nil
end
function METHODS.FindFirstAncestorOfClass(self, class)
	local n = rawget(self, "__parent")
	while n do
		if n.__props.ClassName == class then return n end
		n = rawget(n, "__parent")
	end
	return nil
end
function METHODS.IsDescendantOf(self, other)
	local n = rawget(self, "__parent")
	while n do if n == other then return true end; n = rawget(n, "__parent") end
	return false
end
function METHODS.Destroy(self)
	local s = self.__signals.Destroying
	if s then s:Fire() end
	self.Parent = nil
	rawset(self, "__destroyed", true)
	for _, c in table.clone(self.__children) do METHODS.Destroy(c) end
end
METHODS.ClearAllChildren = function(self) for _, c in table.clone(self.__children) do METHODS.Destroy(c) end end
function METHODS.SetAttribute(self, k, v)
	self.__attrs[k] = v
	local s = self.__attrSignals[k]
	if s then s:Fire() end
	local a = self.__signals.AttributeChanged
	if a then a:Fire(k) end
end
function METHODS.GetAttribute(self, k) return self.__attrs[k] end
function METHODS.GetAttributes(self) return table.clone(self.__attrs) end
function METHODS.GetPropertyChangedSignal(self, k)
	local s = self.__propSignals[k]
	if not s then s = newSignal(); self.__propSignals[k] = s end
	return s
end
function METHODS.GetAttributeChangedSignal(self, k)
	local s = self.__attrSignals[k]
	if not s then s = newSignal(); self.__attrSignals[k] = s end
	return s
end
function METHODS.GetFullName(self) return self.__props.Name end
function METHODS.Clone(self)
	local c = newInstance(self.__props.ClassName)
	for k, v in self.__props do c.__props[k] = v end
	for _, child in self.__children do METHODS.Clone(child).Parent = c end
	return c
end
-- Dienste
function METHODS.FireServer() end
function METHODS.InvokeServer() return nil end
function METHODS.FireClient() end
function METHODS.PlayLocalSound() end
function METHODS.Play() end
function METHODS.Stop() end
function METHODS.Emit() end
function METHODS.GetGuiInset() return Vector2.new(0, 36), Vector2.new(0, 0) end
function METHODS.GetMouseLocation() return Vector2.new(0, 0) end
function METHODS.IsStudio() return true end
function METHODS.IsServer() return false end
function METHODS.IsClient() return true end
function METHODS.IsRunning() return true end
function METHODS.GetPlayers(self) return { self.LocalPlayer } end
function METHODS.GetPlayerByUserId(self) return self.LocalPlayer end
function METHODS.JSONEncode() return "{}" end
function METHODS.JSONDecode() return {} end
function METHODS.GenerateGUID() return "guid" end
function METHODS.WorldToViewportPoint() return Vector3.new(0, 0, 0), false end
function METHODS.PromptGamePassPurchase() end
function METHODS.UserOwnsGamePassAsync() return false end
function METHODS.Create(_, inst, _info, props)
	-- TweenService: Endzustand sofort setzen (Standbild)
	return {
		Play = function() for k, v in props do inst[k] = v end end,
		Cancel = function() end, Pause = function() end,
		Completed = newSignal(), Destroy = function() end,
	}
end
function METHODS.GetTextSize() return Vector2.new(100, 20) end

Instance = { new = function(className, parent)
	local inst = newInstance(className)
	if parent then inst.Parent = parent end
	return inst
end }

local _typeof = typeof
typeof = function(v)
	if type(v) == "table" then
		if rawget(v, "__inst") == true then return "Instance" end
		local t = rawget(v, "__type")
		if t then return t end
	end
	return _typeof(v)
end

--------------------------------------------------------------------------------
-- Modul-Pfade (script.Parent ...), require
--------------------------------------------------------------------------------

local cache = {}
local proxies = {}
local _remotes = {}

local function remoteFor(name)
	local r = _remotes[name]
	if not r then
		r = newInstance("RemoteEvent")
		r.Name = name
		_remotes[name] = r
	end
	return r
end
function __remote(name) return remoteFor(name) end

local PROXY_MT = {}
local function proxy(path)
	if proxies[path] then return proxies[path] end
	local p = setmetatable({ __path = path }, PROXY_MT)
	proxies[path] = p
	return p
end
PROXY_MT.__index = function(t, k)
	local path = rawget(t, "__path")
	if k == "Parent" then
		local parent = string.match(path, "^(.*)/[^/]+$")
		return if parent then proxy(parent) else nil
	elseif k == "Name" then
		return string.match(path, "([^/]+)$")
	elseif k == "WaitForChild" or k == "FindFirstChild" then
		return function(_, name)
			if string.find(path, "RemoteFolder", 1, true) then return remoteFor(name) end
			return proxy(path .. "/" .. name)
		end
	elseif k == "IsA" then
		return function() return false end
	elseif k == "GetChildren" or k == "GetDescendants" then
		return function() return {} end
	elseif SIGNALS[k] then
		return newSignal()
	end
	if string.find(path, "RemoteFolder", 1, true) then return remoteFor(k) end
	return proxy(path .. "/" .. k)
end

local function rbxRequire(target)
	local path = if type(target) == "string" then target else rawget(target, "__path")
	if path == nil then error("require: kein Modulpfad") end
	if cache[path] ~= nil then return cache[path] end
	local source = SOURCES[path]
	if not source then error("Modul nicht gefunden: " .. tostring(path)) end
	local chunk, err = loadstring(source, "=" .. path)
	if not chunk then error(err) end
	local env = setmetatable({ script = proxy(path), require = rbxRequire, game = game, workspace = workspace,
		typeof = typeof, task = task, warn = warn, Instance = Instance, Enum = Enum,
		Color3 = Color3, Vector3 = Vector3, Vector2 = Vector2, UDim = UDim, UDim2 = UDim2,
		ColorSequence = ColorSequence, ColorSequenceKeypoint = ColorSequenceKeypoint,
		NumberSequence = NumberSequence, NumberSequenceKeypoint = NumberSequenceKeypoint,
		NumberRange = NumberRange, CFrame = CFrame, TweenInfo = TweenInfo, Rect = Rect,
		tick = tick, time = time, wait = wait, delay = delay, spawn = spawn }, { __index = _G })
	setfenv(chunk, env)
	cache[path] = true   -- gegen Ringschluss waehrend des Ladens
	local result = chunk()
	cache[path] = result
	return result
end
__rbxRequire = rbxRequire

--------------------------------------------------------------------------------
-- Dienste
--------------------------------------------------------------------------------

local SERVICES = {}
local function service(name)
	local s = SERVICES[name]
	if s then return s end
	if name == "ReplicatedStorage" then
		s = proxy("ReplicatedStorage")
	else
		s = newInstance(name)
		s.Name = name
	end
	SERVICES[name] = s
	return s
end

local players = service("Players")
local localPlayer = newInstance("Player")
localPlayer.Name = "Tester"
localPlayer.DisplayName = "Tester"
localPlayer.UserId = 1
localPlayer.LocaleId = "de-de"
localPlayer.Parent = players
local playerGui = newInstance("PlayerGui")
playerGui.Name = "PlayerGui"
playerGui.Parent = localPlayer
local playerScripts = newInstance("PlayerScripts")
playerScripts.Name = "PlayerScripts"
playerScripts.Parent = localPlayer
players.LocalPlayer = localPlayer

local uis = service("UserInputService")
uis.TouchEnabled = false
uis.KeyboardEnabled = true
uis.MouseEnabled = true
uis.GamepadEnabled = false

local ws = service("Workspace")
local camera = newInstance("Camera")
camera.Name = "Camera"
camera.ViewportSize = Vector2.new(1920, 1080)
camera.Parent = ws
ws.CurrentCamera = camera
workspace = ws

game = newInstance("DataModel")
game.Name = "Game"
METHODS.GetService = function(_, name) return service(name) end
game.ReplicatedStorage = service("ReplicatedStorage")
game.Players = players
game.Workspace = ws

RS = proxy("ReplicatedStorage")
__localPlayer = localPlayer
__playerGui = playerGui
__allInstances = _allInstances
__isInstance = isInstance

--------------------------------------------------------------------------------
-- JSON-Ausgabe des UI-Baums
--------------------------------------------------------------------------------

local function enc(v, out)
	local t = type(v)
	if t == "nil" then table.insert(out, "null")
	elseif t == "boolean" then table.insert(out, tostring(v))
	elseif t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then table.insert(out, "0")
		else table.insert(out, string.format("%.4f", v)) end
	elseif t == "string" then
		local s = string.gsub(v, '[%c"\\]', function(c)
			if c == "\n" then return "\\n" elseif c == '"' then return '\\"' elseif c == "\\" then return "\\\\" end
			return string.format("\\u%04x", string.byte(c))
		end)
		table.insert(out, '"' .. s .. '"')
	elseif t == "table" then
		if isInstance(v) then table.insert(out, "null"); return end
		local ty = rawget(v, "__type")
		if ty == "EnumItem" then table.insert(out, '"' .. v.Name .. '"'); return end
		if ty == "Color3" then
			table.insert(out, string.format('[%.4f,%.4f,%.4f]', v.R, v.G, v.B)); return
		end
		if #v > 0 or next(v) == nil then
			table.insert(out, "[")
			for i, x in ipairs(v) do if i > 1 then table.insert(out, ",") end; enc(x, out) end
			table.insert(out, "]")
		else
			table.insert(out, "{")
			local first = true
			for k, x in v do
				if type(k) == "string" and k ~= "__type" then
					if not first then table.insert(out, ",") end
					first = false
					enc(k, out); table.insert(out, ":"); enc(x, out)
				end
			end
			table.insert(out, "}")
		end
	else
		table.insert(out, "null")
	end
end

local function nodeOf(inst)
	local node = { class = inst.__props.ClassName, name = inst.__props.Name, id = inst.__id, props = {}, children = {} }
	for k, v in inst.__props do
		if k ~= "Name" and k ~= "ClassName" and not isInstance(v) and type(v) ~= "function" then
			node.props[k] = v
		end
	end
	for _, c in inst.__children do table.insert(node.children, nodeOf(c)) end
	return node
end

function __dumpTree(root)
	local out = {}
	enc(nodeOf(root), out)
	return table.concat(out)
end
