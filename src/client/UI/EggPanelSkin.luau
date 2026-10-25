--!nonstrict
-- EggPanelSkin.luau
-- StarterPlayerScripts/UI/EggPanelSkin.luau
--
-- Einzige Zustaendigkeit:
--   - Die Honig-Panels aus den PNG-Assets bauen (Rahmen, Tabs, X,
--     Inhaltsbereich, Leer-Zustand) und die Ei-Kachel. Keine Spiellogik.
--   - Varianten: "eggs" (Tabs als Einzelbilder), "bears" und "eggtree"
--     (Tabs + X im Bild). adopt() setzt ein bestehendes Theme.dialog-Menue
--     in ein Template-Panel.
--
-- Alle Masse sind Pixel des jeweiligen Bildausschnitts und werden in Scale
-- umgerechnet, damit alles mit dem Panel skaliert.

local TweenService = game:GetService("TweenService")
local PanelManager = require(script.Parent.PanelManager)   -- R1: zentraler Fensterbereich

local ASSETS = {
	PanelBase = "rbxassetid://127240858309726", -- panel_base.png
	Close = "rbxassetid://125818425638563", -- close_button.png
	EmptyIcon = "rbxassetid://73515176334425", -- icon_eggs_orange.png
	Tabs = {
		eggs = { active = "rbxassetid://96155278628634", inactive = "rbxassetid://92802332615306" },
		paws = { active = "rbxassetid://115895369528131", inactive = "rbxassetid://102380654083883" },
		star = { active = "rbxassetid://118375269710552", inactive = "rbxassetid://110063821068677" },
		crown = { active = "rbxassetid://139368244398525", inactive = "rbxassetid://83554057577483" },
	},
	-- 13.10. (UI-Templates 2): Stern-Tab wird zum Ei-Baum-Tab
	TabTreeInactive = "rbxassetid://71938721561771", -- UI2_tab_tree_inactive.png
	PanelBears = "rbxassetid://93788145994133", -- UI2_panel_bears.png (Tabs + X im Bild)
	PanelEggTree = "rbxassetid://70925071481581", -- UI2_panel_eggtree.png (Tabs + X im Bild)
	EggCard = "rbxassetid://122024086166803", -- UI2_egg_card.png (Kachel im Ei-Menue)
	-- 19.10.: neues Ei-Baum-Fenster (Baum ins Bild gemalt, 1844 x 853). Leer = noch nicht
	-- hochgeladen -> isReady("eggtree2") ist false, der Ei-Baum nimmt das alte Fenster.
	PanelEggTree2 = "rbxassetid://113227143674369", -- egg_tree_window_v2_transparent.png
}

local REF_W, REF_H = 1169, 754
local TAB_ORDER = { "eggs", "paws", "star", "crown" }
local SLOT_X, SLOT_W, SLOT_H = 64, 100, 101
local SLOT_Y = { eggs = 194, paws = 304, star = 414, crown = 524 }
local ACTIVE_W, ACTIVE_H = 140, 130
local ACTIVE_OFF_X, ACTIVE_OFF_Y = 60, 65
local CLOSE = { x = 1043, y = 53, w = 103, h = 110 }
local CONTENT = { x = 196, y = 182, w = 928, h = 530 }

-- Panels mit eingebauten Tabs (Bears, Egg Tree): nur Klickflaechen ueber den
-- Tabs, das X liegt als Bild darueber (fuer die Drueck-Animation).
-- Masse in Pixeln des jeweiligen Ausschnitts (vor dem Verkleinern auf 1024).
local BAKED = {
	bears = {
		image = "PanelBears", w = 1274, h = 756,
		tabs = {
			eggs = { 37, 189, 103, 100 }, paws = { 27, 299, 135, 106 },
			star = { 37, 409, 103, 105 }, crown = { 37, 529, 103, 98 },
		},
		close = { 1152, 59, 105, 110 },
		content = { 170, 195, 1070, 512 },
	},
	eggtree = {
		image = "PanelEggTree", w = 1276, h = 778,
		tabs = {
			eggs = { 37, 211, 110, 104 }, paws = { 37, 325, 110, 103 },
			star = { 27, 433, 140, 118 }, crown = { 37, 553, 110, 100 },
		},
		close = { 1155, 78, 102, 110 },
		content = { 175, 215, 1065, 535 },
	},
	-- 19.10.: Baum im Bild, Inhaltsbereich = ganzes Fenster; X ist im Bild (keine Button-Grafik darueber)
	eggtree2 = {
		image = "PanelEggTree2", w = 1844, h = 853,
		tabs = {
			eggs = { 30, 155, 135, 135 }, paws = { 30, 303, 135, 135 },
			star = { 25, 445, 150, 140 }, crown = { 30, 597, 135, 135 },
		},
		close = { 1733, 20, 88, 88 },
		content = { 0, 0, 1844, 853 },
		invisibleClose = true,
	},
}

-- Ei-Kachel (UI2_egg_card.png, 1912 x 352)
local CARD = { w = 1912, h = 352, slot = { 93, 62, 260, 257 }, button = { 1433, 157, 417, 145 }, text = { 385, 60, 1030, 232 } }

local TEXT_COLOR = Color3.fromRGB(255, 214, 120)
local SUBTEXT_COLOR = Color3.fromRGB(240, 190, 100)

local function pos(x: number, y: number): UDim2
	return UDim2.fromScale(x / REF_W, y / REF_H)
end

local function size(w: number, h: number): UDim2
	return UDim2.fromScale(w / REF_W, h / REF_H)
end

local function rect(r: { number }, w: number, h: number): (UDim2, UDim2)
	return UDim2.fromScale(r[1] / w, r[2] / h), UDim2.fromScale(r[3] / w, r[4] / h)
end

local function pressable(button: GuiButton)
	local scale = Instance.new("UIScale")
	scale.Parent = button
	local info = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local function to(v: number)
		TweenService:Create(scale, info, { Scale = v }):Play()
	end
	button.MouseEnter:Connect(function() to(1.05) end)
	button.MouseLeave:Connect(function() to(1) end)
	button.MouseButton1Down:Connect(function() to(0.92) end)
	button.MouseButton1Up:Connect(function() to(1.05) end)
end

local EggPanelSkin = {}
EggPanelSkin.__index = EggPanelSkin
EggPanelSkin.Assets = ASSETS

-- true, sobald die Bilder hochgeladen und oben eingetragen sind
function EggPanelSkin.isReady(variant: string?): boolean
	if variant == nil or variant == "eggs" then
		return ASSETS.PanelBase ~= "rbxassetid://0"
	end
	local v = BAKED[variant]
	return v ~= nil and ASSETS[v.image] ~= ""
end

function EggPanelSkin.cardReady(): boolean
	return ASSETS.EggCard ~= ""
end

-- opts.variant: "eggs" (Standard) | "bears" | "eggtree"
-- opts.layout: "grid" (Standard) | "list" | "none"
function EggPanelSkin.new(parent: Instance, opts)
	local o = opts or {}
	local self = setmetatable({}, EggPanelSkin)
	local variant = o.variant or "eggs"
	local baked = BAKED[variant]
	local refW = if baked then baked.w else REF_W
	local refH = if baked then baked.h else REF_H
	self.Variant = variant
	self._baked = baked

	self._tabChanged = Instance.new("BindableEvent")
	self._closed = Instance.new("BindableEvent")
	self.TabChanged = self._tabChanged.Event
	self.Closed = self._closed.Event

	local root = Instance.new("ImageLabel")
	root.Name = "EggPanel"
	root.BackgroundTransparency = 1
	root.Image = if baked then ASSETS[baked.image] else ASSETS.PanelBase
	root.ScaleType = Enum.ScaleType.Stretch
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = o.size or UDim2.fromScale(0.9, 0.72)
	root.Active = true
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = refW / refH
	aspect.Parent = root
	local maxSize = Instance.new("UISizeConstraint")
	local maxW = o.maxWidth or 980
	maxSize.MaxSize = Vector2.new(maxW, math.floor(maxW * refH / refW))
	maxSize.Parent = root
	root.Parent = parent
	self.Root = root

	local contentRect = if baked then baked.content else { CONTENT.x, CONTENT.y, CONTENT.w, CONTENT.h }
	local cPos, cSize = rect(contentRect, refW, refH)

	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Position = cPos
	content.Size = cSize
	content.CanvasSize = UDim2.new()
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.ScrollingDirection = Enum.ScrollingDirection.Y
	content.ScrollBarThickness = 6
	content.ScrollBarImageColor3 = Color3.fromRGB(255, 190, 60)
	content.ZIndex = 2
	content.Parent = root
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 8), UDim.new(0, 14)
	pad.Parent = content
	if o.layout == "list" then
		local list = Instance.new("UIListLayout")
		list.Padding = UDim.new(0, 8)
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = content
		self.Layout = list
	elseif o.layout == "none" then
		self.Layout = nil
	else
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.fromScale(0.23, 1)
		grid.CellPadding = UDim2.new(0.02, 0, 0, 10)
		grid.SortOrder = Enum.SortOrder.LayoutOrder
		grid.Parent = content
		local cellAspect = Instance.new("UIAspectRatioConstraint")
		cellAspect.AspectRatio = 0.8
		cellAspect.Parent = grid
		self.Layout = grid
	end
	self.Content = content
	-- 14.10.: AutomaticCanvasSize rechnet bei Kacheln mit UIAspectRatioConstraint
	-- (Hoehe 2000 -> per Seitenverhaeltnis verkleinert) falsch und laesst die
	-- Leinwand so hoch wie das Fenster: kein Scrollen mit dem Mausrad. Darum
	-- die Leinwandhoehe direkt aus dem Layout (tatsaechliche Inhaltshoehe).
	local activeLayout = self.Layout
	if activeLayout then
		content.AutomaticCanvasSize = Enum.AutomaticSize.None
		-- R1: AbsoluteContentSize sind Bildschirm-Pixel, CanvasSize zaehlt in den
		-- Einheiten VOR den UIScales (global, Fenster-Fit, Aufspringen). Ohne
		-- Umrechnung war die Leinwand bei verkleinerter Oberflaeche zu kurz und man
		-- kam nicht bis ans Listenende. Der Faktor ist das Produkt aller UIScales
		-- auf dem Weg nach oben.
		local function totalScale(): number
			local factor = 1
			local node: Instance? = content
			while node do
				for _, child in node:GetChildren() do
					if child:IsA("UIScale") then factor *= child.Scale end
				end
				node = node.Parent
			end
			return math.max(factor, 0.05)
		end
		local function fitCanvas()
			content.CanvasSize = UDim2.fromOffset(0, activeLayout.AbsoluteContentSize.Y / totalScale() + 16)
		end
		activeLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(fitCanvas)
		content:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitCanvas)
		fitCanvas()
	end
	if o.layout == "none" then
		content.Visible = false
	end

	-- Fester Bereich (ohne Scrollen) fuer Menues mit eigenem Aufbau (adopt)
	local bodyFrame = Instance.new("Frame")
	bodyFrame.Name = "Body"
	bodyFrame.BackgroundTransparency = 1
	bodyFrame.Position = cPos
	bodyFrame.Size = cSize
	bodyFrame.ZIndex = 2
	bodyFrame.Parent = root
	self.Body = bodyFrame

	local empty = Instance.new("Frame")
	empty.Name = "Empty"
	empty.BackgroundTransparency = 1
	empty.Position = cPos
	empty.Size = cSize
	empty.Visible = false
	empty.ZIndex = 2
	empty.Parent = root
	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.Image = ASSETS.EmptyIcon
	icon.ImageTransparency = 0.35
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.36)
	icon.Size = UDim2.fromScale(0.16, 0.34)
	icon.ScaleType = Enum.ScaleType.Fit
	icon.ZIndex = 2
	icon.Parent = empty
	local function label(text: string, y: number, h: number, color: Color3, font: Enum.Font): TextLabel
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.AnchorPoint = Vector2.new(0.5, 0)
		t.Position = UDim2.fromScale(0.5, y)
		t.Size = UDim2.fromScale(0.8, h)
		t.Font = font
		t.Text = text
		t.TextColor3 = color
		t.TextScaled = true
		t.TextWrapped = true
		t.ZIndex = 2
		t.Parent = empty
		return t
	end
	self.EmptyTitle = label(o.emptyTitle or "", 0.6, 0.08, TEXT_COLOR, Enum.Font.FredokaOne)
	self.EmptyText = label(o.emptyText or "", 0.72, 0.12, SUBTEXT_COLOR, Enum.Font.GothamMedium)
	self.EmptyFrame = empty

	local closeRect = if baked then baked.close else { CLOSE.x, CLOSE.y, CLOSE.w, CLOSE.h }
	local close = Instance.new("ImageButton")
	close.Name = "Close"
	close.BackgroundTransparency = 1
	close.Image = ASSETS.Close
	close.Position, close.Size = rect(closeRect, refW, refH)
	close.ZIndex = 5
	if baked and baked.invisibleClose then close.ImageTransparency = 1 end
	close.Parent = root
	pressable(close)
	close.Activated:Connect(function()
		self._closed:Fire()
	end)
	self.CloseButton = close

	self.TabButtons = {}
	for i, name in TAB_ORDER do
		local b = Instance.new("ImageButton")
		b.Name = "Tab_" .. name
		b.BackgroundTransparency = 1
		b.LayoutOrder = i
		if baked then
			-- Tab ist im Bild: unsichtbare Klickflaeche
			b.ImageTransparency = 1
			b.Position, b.Size = rect(baked.tabs[name], refW, refH)
			b.ZIndex = 4
		end
		b.Parent = root
		if not baked then pressable(b) end
		b.Activated:Connect(function()
			self:SetActiveTab(name)
		end)
		self.TabButtons[name] = b
	end

	self:SetActiveTab(o.startTab or (if variant == "bears" then "paws" elseif variant == "eggtree" or variant == "eggtree2" then "star" else "eggs"), true)
	return self
end

function EggPanelSkin:SetActiveTab(name: string, silent: boolean?)
	if not ASSETS.Tabs[name] then
		return
	end
	local changed = self.ActiveTab ~= name
	self.ActiveTab = name
	if not self._baked then
		for tab, b in self.TabButtons do
			local y = SLOT_Y[tab]
			if tab == name then
				b.Image = ASSETS.Tabs[tab].active
				b.Position = pos(SLOT_X + SLOT_W / 2 - ACTIVE_OFF_X, y + SLOT_H / 2 - ACTIVE_OFF_Y)
				b.Size = size(ACTIVE_W, ACTIVE_H)
				b.ZIndex = 4
			else
				local img = ASSETS.Tabs[tab].inactive
				if tab == "star" and ASSETS.TabTreeInactive ~= "" then
					img = ASSETS.TabTreeInactive
				end
				b.Image = img
				b.Position = pos(SLOT_X, y)
				b.Size = size(SLOT_W, SLOT_H)
				b.ZIndex = 3
			end
		end
	end
	if changed and not silent then
		self._tabChanged:Fire(name)
	end
end

function EggPanelSkin:SetEmpty(isEmpty: boolean)
	self.EmptyFrame.Visible = isEmpty
	self.Content.Visible = not isEmpty
end

function EggPanelSkin:Destroy()
	self._tabChanged:Destroy()
	self._closed:Destroy()
	self.Root:Destroy()
end

--------------------------------------------------------------------------------
-- Ei-Kachel (UI2_egg_card.png): Rahmen + Slot links + Honig-Knopf rechts.
-- Gibt { card, slot, info, button, buttonLabel } zurueck; der Aufrufer fuellt
-- slot (Ei-Bild) und info (Name, Text, Anzahl).
--------------------------------------------------------------------------------
function EggPanelSkin.makeCard(parent: Instance, name: string, order: number)
	local card = Instance.new("ImageLabel")
	card.Name = name
	card.BackgroundTransparency = 1
	card.Image = ASSETS.EggCard
	card.ScaleType = Enum.ScaleType.Stretch
	-- Breite gibt die Liste vor, Hoehe folgt dem Seitenverhaeltnis (Box
	-- absichtlich zu hoch, FitWithinMaxSize nimmt dann die Breite)
	card.Size = UDim2.new(1, -8, 0, 2000)
	card.LayoutOrder = order
	card.ZIndex = 2
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = CARD.w / CARD.h
	ar.DominantAxis = Enum.DominantAxis.Width
	ar.Parent = card
	card.Parent = parent

	local function sub(className: string, n: string, r: { number }): GuiObject
		local g = Instance.new(className) :: GuiObject
		g.Name = n
		g.BackgroundTransparency = 1
		g.Position, g.Size = rect(r, CARD.w, CARD.h)
		g.ZIndex = 3
		g.Parent = card
		return g
	end
	local slot = sub("Frame", "Slot", CARD.slot)
	local info = sub("Frame", "Info", CARD.text)
	local button = sub("ImageButton", "Button", CARD.button) :: ImageButton
	button.ImageTransparency = 1
	pressable(button)
	local bl = Instance.new("TextLabel")
	bl.Name = "Label"
	bl.BackgroundTransparency = 1
	bl.AnchorPoint = Vector2.new(0.5, 0.5)
	bl.Position = UDim2.fromScale(0.5, 0.47)
	bl.Size = UDim2.fromScale(0.8, 0.55)
	bl.Font = Enum.Font.FredokaOne
	bl.TextScaled = true
	bl.TextColor3 = Color3.fromRGB(110, 52, 10)
	bl.ZIndex = 4
	bl.Parent = button
	return { card = card, slot = slot, info = info, button = button, buttonLabel = bl }
end

--------------------------------------------------------------------------------
-- bindToArea: der Halter ist der zentrale Fensterbereich (PanelManager.getArea,
-- oberhalb der Pet-Leiste), nicht der ganze Bildschirm. Die gewuenschte Groesse
-- (Anteil des Bildschirms) wird auf diesen Bereich umgerechnet und nie groesser
-- als er; das Seitenverhaeltnis haelt die UIAspectRatioConstraint.
-- 21.10. Playtest: Eggs (HatchPanel) hing am ganzen Bildschirm, Bears (adopt) am
-- Fensterbereich, darum sassen beide je nach Aufloesung versetzt. Jetzt benutzen
-- ALLE Honig-Fenster diese eine Funktion.
--------------------------------------------------------------------------------
function EggPanelSkin.bindToArea(screenGui: Instance, holder: GuiObject, skin: any, size: UDim2?)
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	local function layoutHolder()
		local gui = screenGui :: any
		if not gui:IsA("LayerCollector") then return end
		local globalScale = gui:FindFirstChild("GlobalScale")
		local g = if globalScale and globalScale:IsA("UIScale") then math.max(globalScale.Scale, 0.01) else 1
		local screenUnits = gui.AbsoluteSize / g
		if screenUnits.X <= 0 or screenUnits.Y <= 0 then return end
		local area = PanelManager.getArea(screenUnits)
		holder.Position = UDim2.fromOffset(area.center.X, area.center.Y)
		holder.Size = UDim2.fromOffset(area.size.X, area.size.Y)
		local want = size or UDim2.fromScale(0.9, 0.72)
		skin.Root.Size = UDim2.fromScale(
			math.min(1, want.X.Scale * screenUnits.X / area.size.X),
			math.min(1, want.Y.Scale * screenUnits.Y / area.size.Y)
		)
	end
	PanelManager.onAreaChanged(layoutHolder)
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutHolder)
	local globalScaleNow = screenGui:FindFirstChild("GlobalScale")
	if globalScaleNow then
		globalScaleNow:GetPropertyChangedSignal("Scale"):Connect(layoutHolder)
	end
	-- GlobalScale kann erst nach dem Fenster angelegt werden
	screenGui.ChildAdded:Connect(function(child)
		if child.Name == "GlobalScale" and child:IsA("UIScale") then
			child:GetPropertyChangedSignal("Scale"):Connect(layoutHolder)
			layoutHolder()
		end
	end)
	layoutHolder()
end

--------------------------------------------------------------------------------
-- adopt: ein bestehendes Theme.dialog-Menue in ein Template-Panel setzen.
-- Das alte root bleibt die "Wahrheit" fuer PanelManager (Visible) und
-- Layout-Code (AbsoluteSize); es wird nur durchsichtig gemacht, seine
-- Kopfzeile/Rahmen versteckt und in den Inhaltsbereich gehaengt.
--   opts: variant, onTab(tab), onClose(), maxWidth, size
--------------------------------------------------------------------------------
function EggPanelSkin.adopt(screenGui: Instance, root: GuiObject, body: GuiObject, opts)
	local holder = Instance.new("Frame")
	holder.Name = root.Name .. "Skin"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = 10
	holder.Visible = root.Visible
	holder.Parent = screenGui

	local skin = EggPanelSkin.new(holder, {
		variant = opts.variant, layout = "none", maxWidth = opts.maxWidth, size = opts.size,
	})
	skin.Holder = holder

	EggPanelSkin.bindToArea(screenGui, holder, skin, opts.size)

	for _, child in root:GetChildren() do
		if child == body then continue end
		if child:IsA("GuiObject") then
			child.Visible = false
		elseif child:IsA("UIStroke") then
			child.Enabled = false
		elseif child:IsA("UISizeConstraint") or child:IsA("UIScale") or child:IsA("UIAspectRatioConstraint") then
			child:Destroy()
		end
	end
	root.BackgroundTransparency = 1
	if root:IsA("ImageLabel") or root:IsA("ImageButton") then
		local img: any = root
		img.ImageTransparency = 1
	end
	root.AnchorPoint = Vector2.zero
	root.Position = UDim2.new()
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = skin.Body
	-- R1: Das Setzen von Size oben loest in Theme.dialog noch einen Neuberechnung aus,
	-- solange root am Bildschirm haengt, und schiebt Position weg. Nach dem Umhaengen
	-- deshalb noch einmal sauber setzen.
	root.Position = UDim2.new()
	root.Size = UDim2.fromScale(1, 1)
	body.Position = UDim2.new()
	body.Size = UDim2.fromScale(1, 1)

	root:GetPropertyChangedSignal("Visible"):Connect(function()
		holder.Visible = root.Visible
	end)
	skin.TabChanged:Connect(function(tab: string)
		if opts.onTab then opts.onTab(tab) end
		skin:SetActiveTab(if opts.variant == "bears" then "paws" elseif opts.variant == "eggtree" or opts.variant == "eggtree2" then "star" else "eggs", true)
	end)
	skin.Closed:Connect(function()
		if opts.onClose then opts.onClose() end
	end)
	return skin
end

return EggPanelSkin
