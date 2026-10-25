--!strict
-- BaerchiListPreview.luau
-- StarterPlayerScripts/UI/BaerchiListPreview.luau
--
-- Einzige Zustaendigkeit:
--   - Kleine Baerchi-Vorschauen (ViewportFrame) im Viereck jeder Listenzeile,
--     NACHGELADEN je nach Scroll-Position.
--
-- 21.10. Playtest: Im Viereck stand das Level; dort soll stattdessen eine kleine Vorschau des
-- Baerchis sitzen. Bei bis zu 100 Baerchis waere ein ViewportFrame mit Modell pro Zeile zu
-- schwer, nur die sichtbaren zu laden aber ruckelig beim Scrollen. Darum:
--   * geladen wird alles innerhalb von LOAD_PAGES Fensterhoehen um den sichtbaren Bereich
--     (die naechsten werden vor dem Scrollen schon fertig), nahe Zeilen zuerst;
--   * entladen wird erst jenseits von UNLOAD_PAGES (Hysterese, kein Hin und Her);
--   * pro Takt hoechstens BUILDS_PER_TICK neue Modelle (kein Ruckeln beim Oeffnen);
--   * ist die Liste zu, werden alle Vorschauen freigegeben.
-- Die Zeile legt nur den Halter (host) an; dieses Modul fuellt ihn.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local BaerchiConfig = require(ReplicatedStorage.Config.BaerchiConfig)
local BaerchiMesh   = require(ReplicatedStorage.Modules.BaerchiMesh)
local Theme         = require(script.Parent.Theme)

local BaerchiListPreview = {}

-- Tokens ----------------------------------------------------------------------
local LOAD_PAGES       = 1.0    -- so viele Fensterhoehen ueber/unter dem Sichtbereich werden vorgeladen
local UNLOAD_PAGES     = 2.0    -- erst weiter weg wird wieder entladen
local BUILDS_PER_TICK  = 2
local TICK_SECONDS     = 0.15
local FIELD_OF_VIEW    = 30

type Entry = {
	key     : string,
	config  : string,
	rarity  : string,
	mutation: string?,
	view    : ViewportFrame?,
	failed  : boolean,   -- Modell liess sich nicht bauen: nicht in jedem Takt erneut versuchen
}

local _entries: { [Frame]: Entry } = {}
local _scroller: ScrollingFrame? = nil
local _accum = 0

local function keyOf(configId: string, rarity: string, mutation: string?): string
	return configId .. "|" .. rarity .. "|" .. tostring(mutation)
end

-- Sichtbar = der Scroller und alle seine Vorfahren sind an.
local function isShown(inst: Instance): boolean
	local node: Instance? = inst
	while node do
		if node:IsA("GuiObject") and not node.Visible then return false end
		if node:IsA("ScreenGui") and not node.Enabled then return false end
		node = node.Parent
	end
	return true
end

local function unload(entry: Entry)
	local view = entry.view
	if view then
		view:Destroy()
		entry.view = nil
	end
end

local function load(host: Frame, entry: Entry)
	local view = Instance.new("ViewportFrame")
	view.Name                   = "Preview"
	view.BackgroundTransparency = 1
	view.Size                   = UDim2.fromScale(1, 1)
	-- Die Vorderseite der Figur zeigt nach -Z: Kamera davor (wie die Detailkarte)
	view.Ambient                = Color3.fromRGB(150, 150, 160)
	view.LightColor             = Color3.fromRGB(255, 248, 232)
	view.LightDirection         = Vector3.new(0.4, -0.6, 1.2)
	view.ZIndex                 = host.ZIndex

	local mutationColor = if entry.mutation then BaerchiConfig.getMutationColor(entry.mutation :: any) else nil
	local ok, built = pcall(function()
		return BaerchiMesh.build(Vector3.zero, Theme.rarityColor(entry.rarity :: any), entry.rarity :: any, mutationColor, entry.config)
	end)
	if not ok or not built then
		view:Destroy()
		entry.view   = nil
		entry.failed = true
		return
	end
	local model = built :: Model
	model.Parent = view

	local camera = Instance.new("Camera")
	camera.FieldOfView = FIELD_OF_VIEW
	local cf, size = model:GetBoundingBox()
	local radius   = math.max(size.X, size.Y, size.Z)
	local distance = radius / (2 * math.tan(math.rad(FIELD_OF_VIEW / 2))) * 1.05
	local dir      = Vector3.new(0.35, 0.3, -1).Unit
	camera.CFrame  = CFrame.lookAt(cf.Position + dir * distance, cf.Position)
	camera.Parent  = view
	view.CurrentCamera = camera

	view.Parent = host
	entry.view  = view
end

-- Ein Takt: ueber alle Halter gehen, entladen was weit weg ist, die naechsten laden.
local function step()
	local scroller = _scroller
	if not scroller or scroller.Parent == nil then return end

	if not isShown(scroller) then
		for _, entry in _entries do unload(entry) end
		return
	end

	local windowH = scroller.AbsoluteSize.Y
	if windowH <= 0 then return end
	local top        = scroller.AbsolutePosition.Y
	local loadMargin   = windowH * LOAD_PAGES
	local unloadMargin = windowH * UNLOAD_PAGES

	local want: { { host: Frame, entry: Entry, dist: number } } = {}
	for host, entry in _entries do
		if host.Parent == nil then
			_entries[host] = nil
			continue
		end
		local row = host.Parent
		local rowShown = row == nil or not row:IsA("GuiObject") or row.Visible
		local center = host.AbsolutePosition.Y - top + host.AbsoluteSize.Y * 0.5
		local dist = if center < 0 then -center elseif center > windowH then center - windowH else 0

		if entry.view then
			if dist > unloadMargin or not rowShown then unload(entry) end
		elseif rowShown and not entry.failed and dist <= loadMargin then
			table.insert(want, { host = host, entry = entry, dist = dist })
		end
	end

	if #want == 0 then return end
	table.sort(want, function(a, b) return a.dist < b.dist end)
	for i = 1, math.min(BUILDS_PER_TICK, #want) do
		load(want[i].host, want[i].entry)
	end
end

-- Legt (einmal) den Halter in der Zeile an und merkt sich, welcher Baerchi dort gezeigt wird.
-- Aendert sich der Baerchi (Art, Rarity, Mutation), wird die Vorschau neu gebaut.
function BaerchiListPreview.host(row: Frame, configId: string, rarity: string, mutation: string?, rect: { x: number, y: number, w: number, h: number }): Frame
	local host = row:FindFirstChild("PreviewHost") :: Frame?
	if not host then
		host = Instance.new("Frame")
		local created = host :: Frame
		created.Name                   = "PreviewHost"
		created.BackgroundTransparency = 1
		created.BorderSizePixel        = 0
		created.ClipsDescendants       = true
		created.ZIndex                 = 2
		created.Active                 = false
		created.Parent                 = row
	end
	local h = host :: Frame
	h.Position = UDim2.fromOffset(rect.x, rect.y)
	h.Size     = UDim2.fromOffset(rect.w, rect.h)

	local key = keyOf(configId, rarity, mutation)
	local entry = _entries[h]
	if not entry then
		_entries[h] = { key = key, config = configId, rarity = rarity, mutation = mutation, view = nil, failed = false }
		h.Destroying:Connect(function() _entries[h] = nil end)
	elseif entry.key ~= key then
		unload(entry)
		entry.key, entry.config, entry.rarity, entry.mutation = key, configId, rarity, mutation
		entry.failed = false
	end
	return h
end

-- Den Scroller der Liste melden (einmal beim Aufbau).
function BaerchiListPreview.bind(scroller: ScrollingFrame)
	_scroller = scroller
	scroller:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		_accum = TICK_SECONDS   -- beim Scrollen sofort im naechsten Takt pruefen
	end)
	RunService.Heartbeat:Connect(function(dt: number)
		_accum += dt
		if _accum < TICK_SECONDS then return end
		_accum = 0
		step()
	end)
end

-- Nach einem Neuaufbau der Zeilen sofort pruefen (statt auf den naechsten Takt zu warten).
function BaerchiListPreview.refresh()
	_accum = TICK_SECONDS
end

return BaerchiListPreview
