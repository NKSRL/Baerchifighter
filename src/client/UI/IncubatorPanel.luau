--!strict
-- IncubatorPanel.luau
-- StarterPlayerScripts/UI/IncubatorPanel.luau
--
-- Einzige Zustaendigkeit:
--   - Das Fenster des Solo-Inkubators (15.10.2026): gesammelte Eier mit
--     Abholen, der EINE Baerchi-Platz (Herausnehmen / anderen einsetzen) und
--     der Ausbau (Stufe 1-4: Lager, Tempo, Rebirths + Gummies).
--
-- Bewusst schlicht gehalten: das Fenster wird spaeter mit dem neuen UI-Look
-- (UI/Kit) umgebaut. Die Inhalte und Remotes bleiben dabei gleich.
--
-- Rechnet mit Modules/IncubatorRules (dieselben Regeln wie der Server) und
-- workspace:GetServerTimeNow() als "jetzt". Entscheiden tut der Server
-- (IncubatorService). Neu gebaut wird nur, wenn sich der Inhalt aendert
-- (Signatur); die Restzeit laeuft in einer eigenen Schleife.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local Remotes         = require(ReplicatedStorage.Network.Remotes)
local Loc             = require(ReplicatedStorage.Localization.Loc)
local Names           = require(ReplicatedStorage.Localization.Names)
local EggConfig       = require(ReplicatedStorage.Config.EggConfig)
local IncubatorConfig = require(ReplicatedStorage.Config.IncubatorConfig)
local IncubatorRules  = require(ReplicatedStorage.Modules.IncubatorRules)
local BaerchiConfig   = require(ReplicatedStorage.Config.BaerchiConfig)
local EggCalculator   = require(ReplicatedStorage.Modules.EggCalculator)

local Theme        = require(script.Parent.Theme)
local PanelManager = require(script.Parent.PanelManager)
local ClientState  = require(script.Parent.Parent.Controllers.ClientState)
local Icons        = require(script.Parent.Icons)
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)
local EggIcon      = require(script.Parent.EggIcon)
local Kit          = require(script.Parent.Kit)
local EggLook      = require(ReplicatedStorage.Modules.EggLook)
local BaerchiMesh  = require(ReplicatedStorage.Modules.BaerchiMesh)
local RunService   = game:GetService("RunService")
local Players      = game:GetService("Players")

local IncubatorPanel = {}

local PANEL_NAME = "Incubator"
IncubatorPanel.PANEL_NAME = PANEL_NAME

local _root: Frame? = nil
local _scroller: ScrollingFrame? = nil
local _signature = ""
local _timeLabel: TextLabel? = nil
local _honey = false
local _honeyTick: (() -> ())? = nil
local _honeyRebuild: (() -> ())? = nil
local _honeyReset: (() -> ())? = nil

local function now(): number
	return Workspace:GetServerTimeNow()
end

-- Inhalt haengt an Stufe, Lager, Baerchi, Waehrung und Rebirths
local function signatureOf(data: any): string
	local incubator = data.island.incubator
	if not incubator then return "none" end
	local parts = { tostring(IncubatorRules.levelOf(incubator)), tostring(data.gummies), tostring(data.rebirthCount or 0),
		Loc.getLanguage(), tostring(data.island.equippedUid) }
	for _, entry in incubator.breeders or {} do
		table.insert(parts, string.format("b=%s", entry.uid))
	end
	local stored = {}
	for eggType, count in IncubatorRules.storedOf(incubator) do
		if count > 0 then table.insert(stored, eggType .. "x" .. count) end
	end
	table.sort(stored)
	table.insert(parts, table.concat(stored, ","))
	local uids = {}
	for uid, baerchi in data.island.baerchis do
		table.insert(uids, uid .. ":" .. baerchi.rarity .. ":" .. tostring(baerchi.mutation))
	end
	table.sort(uids)
	table.insert(parts, table.concat(uids, ","))
	return table.concat(parts, "|")
end

-- Zeit bis zum naechsten Ei (laeuft jede halbe Sekunde, baut nichts neu)
local function tick()
	if _honeyTick then _honeyTick() return end
	local label = _timeLabel
	local data = ClientState.get()
	if not label or not data or not data.island.incubator then return end
	local incubator = data.island.incubator
	local entry = IncubatorRules.findBreeder(incubator.breeders, 1)
	local baerchi = if entry then data.island.baerchis[entry.uid] else nil
	if not entry or not baerchi then return end
	if IncubatorRules.storedFree(incubator) <= 0 then
		label.Text = "🥚 " .. Loc.t("ui.incubator.breed_full")
		return
	end
	local seconds = IncubatorRules.breedSeconds(baerchi.rarity, IncubatorRules.levelOf(incubator))
	local left = math.max(0, entry.lastEggAt + seconds - now())
	label.Text = Loc.t("ui.incubator.next_egg", { time = Loc.formatDuration(math.ceil(left)) })
end

--------------------------------------------------------------------------------
-- Aufbau des Inhalts
--------------------------------------------------------------------------------

local function sectionRow(parent: Instance, order: number, text: string)
	local holder = Theme.container("Section", parent)
	holder.Size = UDim2.new(1, -8, 0, 20)
	holder.LayoutOrder = order
	Theme.sectionLabel("Label", holder, text).Size = UDim2.fromScale(1, 1)
end

local function baerchiName(baerchi: any): string
	return Names.baerchi(baerchi.configId)
end

-- Kurze Chancen-Zeile: "Basis-Ei 60% · Zucker-Ei 30% · ..."
local function oddsLine(baerchi: any, eggTree: any, maxEntries: number): string
	local parts: { string } = {}
	for i, entry in EggCalculator.getResolvedChances(baerchi, eggTree) do
		if i > maxEntries then break end
		local percent = if entry.percent >= 10 then string.format("%d", math.floor(entry.percent + 0.5))
			else Loc.formatDecimal(entry.percent, 1)
		table.insert(parts, string.format("%s %s%%", Names.egg(entry.eggType), percent))
	end
	return table.concat(parts, " · ")
end

local function rebuild()
	local scroller = _scroller
	if not scroller then return end
	local data = ClientState.get()
	if not data or not data.island.incubator then return end
	local incubator = data.island.incubator

	for _, child in scroller:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	_timeLabel = nil

	local level = IncubatorRules.levelOf(incubator)
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local hint = Theme.bodyText("Hint", scroller, Loc.t("ui.incubator.breed_hint"))
	hint.Size = UDim2.new(1, -8, 0, 60)
	hint.LayoutOrder = nextOrder()

	-- Gesammelte Eier ---------------------------------------------------------
	local total = IncubatorRules.storedTotal(incubator)
	local capacity = IncubatorRules.capacity(level)
	sectionRow(scroller, nextOrder(), Loc.t("ui.incubator.stored", { n = total, cap = capacity }))
	local storedRow = Theme.panel("Stored", scroller, Theme.COLORS.panel)
	storedRow.Size = UDim2.new(1, -8, 0, 76)
	storedRow.LayoutOrder = nextOrder()
	local types: { string } = {}
	for eggType, count in IncubatorRules.storedOf(incubator) do
		if count > 0 and EggConfig.data[eggType :: any] then table.insert(types, eggType) end
	end
	table.sort(types, function(a, b) return EggConfig.data[a :: any].sortOrder < EggConfig.data[b :: any].sortOrder end)
	local lines: { string } = {}
	for _, eggType in types do
		table.insert(lines, string.format("%s x%d", Names.egg(eggType), IncubatorRules.storedOf(incubator)[eggType]))
	end
	local content = Theme.bodyText("Content", storedRow, if #lines > 0 then table.concat(lines, " · ") else Loc.t("ui.incubator.stored_empty"))
	content.Position = UDim2.new(0, 10, 0, 4)
	content.Size = UDim2.new(1, -160, 1, -8)
	content.TextWrapped = true
	local collect = Theme.bigButton("Collect", storedRow, Loc.t("ui.incubator.collect"), Theme.COLORS.good)
	collect.AnchorPoint = Vector2.new(1, 0.5)
	collect.Position = UDim2.new(1, -8, 0.5, 0)
	collect.Size = UDim2.fromOffset(140, 48)
	Theme.setEnabled(collect, total > 0)
	collect.Activated:Connect(function()
		Remotes.RequestIncubatorCollect:FireServer()
	end)

	-- Der eine Baerchi-Platz -----------------------------------------------------
	sectionRow(scroller, nextOrder(), Loc.t("ui.incubator.slots", { used = #(incubator.breeders or {}), total = 1 }))
	local entry = IncubatorRules.findBreeder(incubator.breeders, 1)
	local sitting = if entry then data.island.baerchis[entry.uid] else nil
	local slotRow = Theme.panel("Slot", scroller, Theme.COLORS.panel)
	slotRow.Size = UDim2.new(1, -8, 0, if sitting then 86 else 56)
	slotRow.LayoutOrder = nextOrder()
	if sitting then
		local name = Theme.label("Name", slotRow, string.format("%s · %s · Lv.%d",
			baerchiName(sitting), Loc.name("rarity." .. sitting.rarity, sitting.rarity), sitting.level))
		name.Position = UDim2.new(0, 10, 0, 4)
		name.Size = UDim2.new(1, -150, 0, 22)
		name.TextColor3 = BaerchiConfig.getRarityColor(sitting.rarity)

		local odds = Theme.bodyText("Odds", slotRow, oddsLine(sitting, data.eggTree, 4))
		odds.Position = UDim2.new(0, 10, 0, 28)
		odds.Size = UDim2.new(1, -150, 0, 34)
		odds.TextWrapped = true

		local timeLabel = Theme.label("Time", slotRow, "")
		timeLabel.Position = UDim2.new(0, 10, 0, 62)
		timeLabel.Size = UDim2.new(1, -150, 0, 20)
		timeLabel.Font = Theme.FONT_BODY
		timeLabel.TextColor3 = Theme.COLORS.textDim
		_timeLabel = timeLabel

		local take = Theme.button("Take", slotRow, Loc.t("ui.incubator.take"), Theme.COLORS.panelLight)
		take.AnchorPoint = Vector2.new(1, 0.5)
		take.Position = UDim2.new(1, -8, 0.5, 0)
		take.Size = UDim2.fromOffset(128, 40)
		take.Activated:Connect(function()
			Remotes.RequestIncubatorBaerchi:FireServer("take")
		end)
	else
		local free = Theme.bodyText("Free", slotRow, Loc.t("ui.incubator.free_breed"))
		free.Position = UDim2.new(0, 12, 0, 0)
		free.Size = UDim2.new(1, -24, 1, 0)
		free.TextYAlignment = Enum.TextYAlignment.Center
	end

	-- Baerchis zum Einsetzen (ersetzt den sitzenden) -------------------------------
	sectionRow(scroller, nextOrder(), Loc.t("ui.incubator.pick"))
	local list: { any } = {}
	for uid, baerchi in data.island.baerchis do
		if IncubatorRules.canBreed(data.island, uid) then table.insert(list, baerchi) end
	end
	local rank: { [string]: number } = {}
	for i, rarity in BaerchiConfig.RARITY_ORDER do rank[rarity] = i end
	table.sort(list, function(a, b)
		local ra, rb = rank[a.rarity] or 0, rank[b.rarity] or 0
		if ra ~= rb then return ra > rb end
		if a.level ~= b.level then return a.level > b.level end
		return a.uid < b.uid
	end)
	if #list == 0 then
		local empty = Theme.bodyText("Empty", scroller, Loc.t("ui.incubator.no_baerchis"))
		empty.Size = UDim2.new(1, -8, 0, 40)
		empty.LayoutOrder = nextOrder()
	end
	for _, baerchi in list do
		local row = Theme.panel("Pick_" .. baerchi.uid, scroller, Theme.COLORS.panel)
		row.Size = UDim2.new(1, -8, 0, 70)
		row.LayoutOrder = nextOrder()

		local name = Theme.label("Name", row, string.format("%s · %s · Lv.%d",
			baerchiName(baerchi), Loc.name("rarity." .. baerchi.rarity, baerchi.rarity), baerchi.level))
		name.Position = UDim2.new(0, 10, 0, 4)
		name.Size = UDim2.new(1, -150, 0, 22)
		name.TextColor3 = BaerchiConfig.getRarityColor(baerchi.rarity)

		local info = Theme.bodyText("Info", row, Loc.t("ui.incubator.breed_rate", {
			time = Loc.formatDuration(IncubatorRules.breedSeconds(baerchi.rarity, level)) })
			.. "\n" .. oddsLine(baerchi, data.eggTree, 3))
		info.Position = UDim2.new(0, 10, 0, 26)
		info.Size = UDim2.new(1, -150, 0, 40)
		info.TextWrapped = true

		local put = Theme.button("Put", row, Loc.t("ui.incubator.put_baerchi"), Theme.COLORS.accent)
		put.AnchorPoint = Vector2.new(1, 0.5)
		put.Position = UDim2.new(1, -8, 0.5, 0)
		put.Size = UDim2.fromOffset(128, 40)
		local uid = baerchi.uid
		put.Activated:Connect(function()
			Remotes.RequestIncubatorBaerchi:FireServer("put", uid)
		end)
	end

	-- Ausbau ----------------------------------------------------------------------
	sectionRow(scroller, nextOrder(), Loc.t("ui.incubator.level_label", { level = level, max = IncubatorConfig.MAX_LEVEL }))
	local cost = IncubatorRules.upgradeCost(level + 1)
	local upRow = Theme.panel("Upgrade", scroller, Theme.COLORS.panel)
	upRow.Size = UDim2.new(1, -8, 0, 84)
	upRow.LayoutOrder = nextOrder()
	local effect = Theme.bodyText("Effect", upRow, "")
	effect.Position = UDim2.new(0, 10, 0, 4)
	effect.Size = UDim2.new(1, -170, 1, -8)
	effect.TextWrapped = true
	if cost then
		local rebirths = data.rebirthCount or 0
		local rebirthOk = rebirths >= cost.rebirths
		effect.Text = Loc.t("ui.incubator.upgrade_effect2", {
			capNow    = capacity,
			capNext   = IncubatorRules.capacity(level + 1),
			speedNow  = Loc.formatDecimal(IncubatorRules.speed(level), 2),
			speedNext = Loc.formatDecimal(IncubatorRules.speed(level + 1), 2),
		}) .. "\n" .. Loc.t("ui.incubator.upgrade_need", { n = cost.rebirths })
		local up = Theme.bigButton("Up", upRow, Loc.t("ui.incubator.upgrade_cost2", { gummies = cost.gummies }), Theme.COLORS.gummy)
		up.AnchorPoint = Vector2.new(1, 0.5)
		up.Position = UDim2.new(1, -8, 0.5, 0)
		up.Size = UDim2.fromOffset(150, 48)
		Theme.setEnabled(up, rebirthOk and data.gummies >= cost.gummies)
		up.Activated:Connect(function()
			Remotes.RequestUpgradeIncubator:FireServer()
		end)
	else
		effect.Text = Loc.t("ui.incubator.max_level")
	end

	tick()
end

local function refresh()
	local root = _root
	if not root or not root.Visible then return end
	local data = ClientState.get()
	if not data then return end
	local signature = signatureOf(data)
	if signature == _signature then return end
	_signature = signature
	if _honeyRebuild then _honeyRebuild() else rebuild() end
end

--------------------------------------------------------------------------------
-- Aufbau
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Honig-UI (15.10.): Fenster = Bild "honey/incubator_window"
--------------------------------------------------------------------------------
-- Das Bild ist ganz ausgeschnitten (1506 x 937 Bildpixel, Alpha-Rand). Alle Masse
-- sind Bildpixel; hx/hy rechnen in Fenster-Einheiten um (Fenster 760 x 473).
-- Belegung der Flaechen:
--   Holzbalken oben links ... Titel            dunkle Leiste oben rechts ... Ausbau
--   grosses Feld links ...... Baerchi (Name + 3D-Figur)
--   gruen / rot ............. Tauschen (oeffnet die Auswahl) / Entfernen
--   Feld unten links ........ moegliche Eier mit Chancen (inkl. Gluecks-Bonus)
--   4 x 2 Kacheln ........... gesammelte Eier (scrollt; im Tauschen-Modus: Baerchi-Auswahl)
--   lila / gruen / blau ..... naechstes Ei / Gluecks-Bonus / Ei-Lager
--   goldene Leiste .......... Eier abholen
local WIN_W, WIN_H = 760, 473
local HS = WIN_W / 1506
local function hx(x: number): number return x * HS end
local function hy(y: number): number return y * HS end
local function place(obj: GuiObject, x0: number, y0: number, x1: number, y1: number)
	obj.Position = UDim2.fromOffset(hx(x0), hy(y0))
	obj.Size     = UDim2.fromOffset(hx(x1 - x0), hy(y1 - y0))
end

local INK        = Color3.fromRGB(255, 244, 214)
local INK_DIM    = Color3.fromRGB(205, 170, 120)
local INK_STROKE = Color3.fromRGB(58, 30, 8)
local DARK       = Color3.fromRGB(44, 22, 8)
local HONEY      = Color3.fromRGB(255, 176, 40)
local GREEN      = Color3.fromRGB(150, 235, 90)

local H: { [string]: any } = {}
local _pick = false
local _lastLuckKey = ""

local function hlabel(parent: Instance, name: string, x0: number, y0: number, x1: number, y1: number,
	maxSize: number, align: Enum.TextXAlignment?, z: number?): TextLabel
	local label = Instance.new("TextLabel")
	label.Name                   = name
	label.BackgroundTransparency = 1
	label.Font                   = Theme.FONT
	label.Text                   = ""
	label.TextScaled             = true
	label.TextWrapped            = true
	label.TextColor3             = INK
	label.TextStrokeColor3       = INK_STROKE
	label.TextStrokeTransparency = 0.35
	label.TextXAlignment         = align or Enum.TextXAlignment.Center
	label.ZIndex                 = z or 6
	label.Active                 = false
	label.Parent                 = parent
	place(label, x0, y0, x1, y1)
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize
	limit.MinTextSize = 6
	limit.Parent = label
	return label
end

local function hbutton(parent: Instance, name: string, x0: number, y0: number, x1: number, y1: number): TextButton
	local button = Instance.new("TextButton")
	button.Name                   = name
	button.BackgroundTransparency = 1
	button.Text                   = ""
	button.AutoButtonColor        = false
	button.ZIndex                 = 9
	button.Parent                 = parent
	place(button, x0, y0, x1, y1)
	return button
end

local function hcover(parent: Instance, name: string, x0: number, y0: number, x1: number, y1: number, radius: number): Frame
	local frame = Instance.new("Frame")
	frame.Name                   = name
	frame.BackgroundColor3       = Color3.fromRGB(30, 15, 5)
	frame.BackgroundTransparency = 0.45
	frame.BorderSizePixel        = 0
	frame.ZIndex                 = 8
	frame.Active                 = false
	frame.Visible                = false
	frame.Parent                 = parent
	place(frame, x0, y0, x1, y1)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius * HS)
	corner.Parent = frame
	return frame
end

local function hscroll(parent: Instance, name: string, x0: number, y0: number, x1: number, y1: number): ScrollingFrame
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name                   = name
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel        = 0
	scroll.ScrollBarThickness     = 4
	scroll.ScrollBarImageColor3   = HONEY
	scroll.AutomaticCanvasSize    = Enum.AutomaticSize.Y
	scroll.CanvasSize             = UDim2.new()
	scroll.ScrollingDirection     = Enum.ScrollingDirection.Y
	scroll.ZIndex                 = 6
	scroll.Parent                 = parent
	place(scroll, x0, y0, x1, y1)
	return scroll
end

local function clearChildren(container: Instance)
	for _, child in container:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
end

local function fmtClock(totalSeconds: number): string
	local s = math.max(0, math.floor(totalSeconds))
	local h, m, sec = s // 3600, (s % 3600) // 60, s % 60
	if h > 0 then return string.format("%d:%02d:%02d", h, m, sec) end
	return string.format("%02d:%02d", m, sec)
end

local function percentText(percent: number): string
	return if percent >= 10 then string.format("%d%%", math.floor(percent + 0.5)) else Loc.formatDecimal(percent, 1) .. "%"
end

local function sitterOf(data: any): (any?, any?)
	local incubator = data.island.incubator
	local entry = IncubatorRules.findBreeder(incubator.breeders, 1)
	local baerchi = if entry then data.island.baerchis[entry.uid] else nil
	return entry, baerchi
end

-- Aktueller Gluecks-Bonus (Prozent) und die Sekunden dazu
local function luckNow(entry: any?): (number, number)
	local start = Players.LocalPlayer:GetAttribute("IncLuckStart")
	local seconds = if entry and typeof(start) == "number" then IncubatorRules.luckSeconds(start, now()) else 0
	return IncubatorRules.luckPercent(seconds), seconds
end

-- Auswahl-Modus (Tauschen): die Kachel-Flaeche zeigt Baerchis statt Eier
local function applyPick()
	if not H.stored then return end
	H.stored.Visible = not _pick
	H.storedEmpty.Visible = (not _pick) and (H.storedCount or 0) == 0
	H.pick.Visible = _pick
	H.pickEmpty.Visible = _pick and (H.pickCount or 0) == 0
	H.swapLabel.Text = Loc.t(if _pick then "ui.incubator.h_back" elseif H.hasSitter then "ui.incubator.h_swap" else "ui.incubator.h_put")
end

local function rebuildOdds()
	local scroller = H.odds
	if not scroller then return end
	clearChildren(scroller)
	local data = ClientState.get()
	local sitting = H.sitting
	if not data or not sitting then return end
	local entry = IncubatorRules.findBreeder(data.island.incubator.breeders, 1)
	local luck = luckNow(entry)
	for i, chance in EggCalculator.getResolvedChances(sitting, data.eggTree, luck) do
		local row = Instance.new("Frame")
		row.Name = "Odds_" .. chance.eggType
		row.BackgroundColor3 = EggLook.get(chance.eggType).base
		row.BorderSizePixel = 0
		row.ZIndex = 7
		row.LayoutOrder = i
		row.Size = UDim2.new(1, -6, 0, hy(38))
		row.Parent = scroller
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = row
		local stroke = Instance.new("UIStroke")
		stroke.Color = INK_STROKE
		stroke.Thickness = 1.5
		stroke.Parent = row

		local nameLabel = Instance.new("TextLabel")
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Theme.FONT
		nameLabel.Text = Names.egg(chance.eggType)
		nameLabel.TextScaled = true
		nameLabel.TextColor3 = INK
		nameLabel.TextStrokeColor3 = INK_STROKE
		nameLabel.TextStrokeTransparency = 0.3
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Position = UDim2.fromScale(0.04, 0.1)
		nameLabel.Size = UDim2.fromScale(0.64, 0.8)
		nameLabel.ZIndex = 8
		nameLabel.Parent = row
		local c1 = Instance.new("UITextSizeConstraint")
		c1.MaxTextSize = 15
		c1.MinTextSize = 6
		c1.Parent = nameLabel

		local pct = Instance.new("TextLabel")
		pct.BackgroundTransparency = 1
		pct.Font = Theme.FONT
		pct.Text = percentText(chance.percent)
		pct.TextScaled = true
		pct.TextColor3 = INK
		pct.TextStrokeColor3 = INK_STROKE
		pct.TextStrokeTransparency = 0.3
		pct.TextXAlignment = Enum.TextXAlignment.Right
		pct.Position = UDim2.fromScale(0.68, 0.1)
		pct.Size = UDim2.fromScale(0.28, 0.8)
		pct.ZIndex = 8
		pct.Parent = row
		local c2 = Instance.new("UITextSizeConstraint")
		c2.MaxTextSize = 15
		c2.MinTextSize = 6
		c2.Parent = pct
	end
end

local function rebuildHoney()
	local data = ClientState.get()
	if not data or not data.island.incubator then return end
	local incubator = data.island.incubator
	local level = IncubatorRules.levelOf(incubator)
	local capacity = IncubatorRules.capacity(level)
	local total = IncubatorRules.storedTotal(incubator)
	local _, sitting = sitterOf(data)
	H.sitting = sitting
	H.hasSitter = sitting ~= nil

	-- Baerchi links
	if sitting then
		H.name.Text = Names.baerchi(sitting.configId)
		H.name.TextColor3 = INK
		H.emptyText.Visible = false
		H.view.Visible = true
		H.setModel(sitting)
	else
		H.name.Text = ""
		H.emptyText.Text = Loc.t("ui.incubator.h_empty")
		H.emptyText.Visible = true
		H.view.Visible = false
	end
	H.removeLabel.Text = Loc.t("ui.incubator.h_remove")
	H.removeCover.Visible = sitting == nil

	-- Feste Beschriftungen
	H.possible.Text = Loc.t("ui.incubator.h_possible")
	H.nextTitle.Text = Loc.t("ui.incubator.h_next")
	H.luckTitle.Text = Loc.t("ui.incubator.h_luck")
	H.luckReset.Text = Loc.t("ui.incubator.h_luck_reset")
	H.storageTitle.Text = Loc.t("ui.incubator.h_storage")
	H.storageValue.Text = string.format("%d / %d", total, capacity)
	H.storageValue.TextColor3 = if total >= capacity then Color3.fromRGB(255, 190, 120) else INK
	H.pickEmpty.Text = Loc.t("ui.incubator.no_baerchis")
	H.storedEmpty.Text = Loc.t("ui.incubator.h_no_eggs")

	-- Eier abholen
	H.claimLabel.Text = Loc.t("ui.incubator.h_claim") .. (if total > 0 then string.format("  (%d)", total) else "")
	H.claimCover.Visible = total <= 0

	-- Ausbau (dunkle Leiste oben rechts)
	local cost = IncubatorRules.upgradeCost(level + 1)
	local rebirths = data.rebirthCount or 0
	if not cost then
		H.upLabel.Text = Loc.t("ui.incubator.h_max")
		H.upLabel.TextColor3 = INK_DIM
		H.upButton.Active = false
	elseif rebirths < cost.rebirths then
		H.upLabel.Text = Loc.t("ui.incubator.h_need_rebirth", { level = level + 1, n = cost.rebirths })
		H.upLabel.TextColor3 = INK_DIM
		H.upButton.Active = true
	else
		H.upLabel.Text = Loc.t("ui.incubator.h_upgrade", { level = level + 1, cost = Kit.formatCompact(cost.gummies) })
		H.upLabel.TextColor3 = if data.gummies >= cost.gummies then INK else Color3.fromRGB(255, 150, 130)
		H.upButton.Active = true
	end

	-- Gesammelte Eier (Kacheln)
	local stored: any = H.stored
	clearChildren(stored)
	local types: { string } = {}
	for eggType, count in IncubatorRules.storedOf(incubator) do
		if count > 0 and EggConfig.data[eggType :: any] then table.insert(types, eggType) end
	end
	table.sort(types, function(a, b) return EggConfig.data[a :: any].sortOrder < EggConfig.data[b :: any].sortOrder end)
	H.storedCount = #types
	for i, eggType in types do
		local count = IncubatorRules.storedOf(incubator)[eggType]
		local tile = Instance.new("Frame")
		tile.Name = "Egg_" .. eggType
		tile.BackgroundColor3 = DARK
		tile.BorderSizePixel = 0
		tile.ZIndex = 7
		tile.LayoutOrder = i
		tile.Parent = stored
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, hx(22))
		corner.Parent = tile
		local stroke = Instance.new("UIStroke")
		stroke.Color = HONEY
		stroke.Thickness = 2
		stroke.Parent = tile

		local icon = EggIcon.make(tile, eggType, hy(88), 8)
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, hy(10))

		local countLabel = Instance.new("TextLabel")
		countLabel.BackgroundTransparency = 1
		countLabel.Font = Theme.FONT
		countLabel.Text = "x" .. count
		countLabel.TextScaled = true
		countLabel.TextColor3 = INK
		countLabel.TextStrokeColor3 = INK_STROKE
		countLabel.TextStrokeTransparency = 0.2
		countLabel.TextXAlignment = Enum.TextXAlignment.Right
		countLabel.AnchorPoint = Vector2.new(1, 0)
		countLabel.Position = UDim2.new(1, -4, 0, 3)
		countLabel.Size = UDim2.fromOffset(hx(80), hy(34))
		countLabel.ZIndex = 9
		countLabel.Parent = tile
		local cl = Instance.new("UITextSizeConstraint")
		cl.MaxTextSize = 16
		cl.MinTextSize = 8
		cl.Parent = countLabel

		local nameLabel = Instance.new("TextLabel")
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Theme.FONT
		nameLabel.Text = Names.egg(eggType)
		nameLabel.TextScaled = true
		nameLabel.TextColor3 = INK
		nameLabel.TextStrokeColor3 = INK_STROKE
		nameLabel.TextStrokeTransparency = 0.3
		nameLabel.AnchorPoint = Vector2.new(0.5, 1)
		nameLabel.Position = UDim2.new(0.5, 0, 1, -2)
		nameLabel.Size = UDim2.new(1, -8, 0, hy(30))
		nameLabel.ZIndex = 9
		nameLabel.Parent = tile
		local nl = Instance.new("UITextSizeConstraint")
		nl.MaxTextSize = 12
		nl.MinTextSize = 6
		nl.Parent = nameLabel
	end

	-- Baerchi-Auswahl (Tauschen)
	local pick: any = H.pick
	clearChildren(pick)
	local list: { any } = {}
	for uid, baerchi in data.island.baerchis do
		if IncubatorRules.canBreed(data.island, uid) then table.insert(list, baerchi) end
	end
	local rank: { [string]: number } = {}
	for i, rarity in BaerchiConfig.RARITY_ORDER do rank[rarity] = i end
	table.sort(list, function(a, b)
		local ra, rb = rank[a.rarity] or 0, rank[b.rarity] or 0
		if ra ~= rb then return ra > rb end
		if a.level ~= b.level then return a.level > b.level end
		return a.uid < b.uid
	end)
	H.pickCount = #list
	for i, baerchi in list do
		local row = Instance.new("TextButton")
		row.Name = "Pick_" .. baerchi.uid
		row.Text = ""
		row.AutoButtonColor = false
		row.BackgroundColor3 = DARK
		row.BorderSizePixel = 0
		row.ZIndex = 7
		row.LayoutOrder = i
		row.Size = UDim2.new(1, -10, 0, hy(60))
		row.Parent = pick
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, hx(16))
		corner.Parent = row
		local stroke = Instance.new("UIStroke")
		stroke.Color = HONEY
		stroke.Thickness = 1.5
		stroke.Parent = row

		local nameLabel = Instance.new("TextLabel")
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Theme.FONT
		nameLabel.Text = string.format("%s · %s · Lv.%d", baerchiName(baerchi), Loc.name("rarity." .. baerchi.rarity, baerchi.rarity), baerchi.level)
		nameLabel.TextScaled = true
		nameLabel.TextColor3 = BaerchiConfig.getRarityColor(baerchi.rarity)
		nameLabel.TextStrokeColor3 = INK_STROKE
		nameLabel.TextStrokeTransparency = 0.3
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Position = UDim2.fromScale(0.03, 0.06)
		nameLabel.Size = UDim2.fromScale(0.94, 0.46)
		nameLabel.ZIndex = 8
		nameLabel.Parent = row
		local c1 = Instance.new("UITextSizeConstraint")
		c1.MaxTextSize = 15
		c1.MinTextSize = 6
		c1.Parent = nameLabel

		local info = Instance.new("TextLabel")
		info.BackgroundTransparency = 1
		info.Font = Theme.FONT_BODY
		info.Text = Loc.t("ui.incubator.breed_rate", { time = Loc.formatDuration(IncubatorRules.breedSeconds(baerchi.rarity, level)) })
			.. " · " .. oddsLine(baerchi, data.eggTree, 2)
		info.TextScaled = true
		info.TextColor3 = INK_DIM
		info.TextXAlignment = Enum.TextXAlignment.Left
		info.Position = UDim2.fromScale(0.03, 0.54)
		info.Size = UDim2.fromScale(0.94, 0.38)
		info.ZIndex = 8
		info.Parent = row
		local c2 = Instance.new("UITextSizeConstraint")
		c2.MaxTextSize = 12
		c2.MinTextSize = 6
		c2.Parent = info

		local uid = baerchi.uid
		row.Activated:Connect(function()
			Remotes.RequestIncubatorBaerchi:FireServer("put", uid)
			_pick = false
			applyPick()
		end)
	end

	applyPick()
	rebuildOdds()
	if _honeyTick then _honeyTick() end
end

local function buildHoney(root: Frame)
	-- ------------------------------------------------------------ Baerchi (grosses Feld links)
	H.name = hlabel(root, "BearName", 150, 182, 478, 226, 22)
	H.emptyText = hlabel(root, "BearEmpty", 160, 280, 470, 400, 20)
	H.emptyText.TextColor3 = INK_DIM

	local view = Instance.new("ViewportFrame")
	view.Name                   = "Portrait"
	view.BackgroundTransparency = 1
	view.Ambient                = Color3.fromRGB(150, 150, 160)
	view.LightColor             = Color3.fromRGB(255, 248, 232)
	view.LightDirection         = Vector3.new(0.4, -0.6, 1.2)
	view.ZIndex                 = 3
	view.Parent                 = root
	place(view, 150, 228, 478, 490)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 30
	camera.Parent = view
	view.CurrentCamera = camera
	H.view = view

	local model: Model? = nil
	local modelKey = ""
	local center = Vector3.zero
	local distance = 10
	RunService.RenderStepped:Connect(function()
		if not root.Visible or not model or not view.Visible then return end
		local angle = math.sin(os.clock() * 0.8) * 0.7
		local dir = Vector3.new(math.sin(angle), 0.28, -math.cos(angle)).Unit
		camera.CFrame = CFrame.lookAt(center + dir * distance, center)
	end)
	H.setModel = function(baerchi: any)
		local key = baerchi.configId .. "|" .. baerchi.rarity .. "|" .. tostring(baerchi.mutation)
		if key == modelKey then return end
		modelKey = key
		if model then model:Destroy() model = nil end
		local mutationColor = if baerchi.mutation then BaerchiConfig.getMutationColor(baerchi.mutation) else nil
		local ok, built = pcall(function()
			return BaerchiMesh.build(Vector3.zero, Theme.rarityColor(baerchi.rarity), baerchi.rarity, mutationColor, baerchi.configId)
		end)
		if not ok or not built then return end
		local newModel = built :: Model
		newModel.Parent = view
		model = newModel
		local cf, size = newModel:GetBoundingBox()
		center = cf.Position
		local radius = math.max(size.X, size.Y, size.Z)
		distance = radius / (2 * math.tan(math.rad(camera.FieldOfView / 2))) * 1.05
	end

	-- ------------------------------------------------------------ Tauschen / Entfernen
	H.swapLabel = hlabel(root, "SwapText", 70, 520, 305, 600, 26)
	H.swapLabel.TextStrokeTransparency = 0.2
	hbutton(root, "Swap", 70, 520, 305, 600).Activated:Connect(function()
		_pick = not _pick
		applyPick()
	end)
	H.removeLabel = hlabel(root, "RemoveText", 318, 520, 552, 600, 26)
	H.removeLabel.TextStrokeTransparency = 0.2
	H.removeCover = hcover(root, "RemoveCover", 318, 520, 552, 600, 22)
	hbutton(root, "Remove", 318, 520, 552, 600).Activated:Connect(function()
		if not H.hasSitter then return end
		_pick = false
		applyPick()
		Remotes.RequestIncubatorBaerchi:FireServer("take")
	end)

	-- ------------------------------------------------------------ Moegliche Eier (unten links)
	H.possible = hlabel(root, "PossibleTitle", 70, 650, 548, 692, 18)
	H.odds = hscroll(root, "Odds", 72, 696, 548, 860)
	local oddsLayout = Instance.new("UIListLayout")
	oddsLayout.Padding = UDim.new(0, 3)
	oddsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	oddsLayout.Parent = H.odds

	-- ------------------------------------------------------------ Eier-Kacheln / Auswahl
	H.stored = hscroll(root, "Stored", 597, 195, 1411, 503)
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(hx(185), hy(143))
	grid.CellPadding = UDim2.fromOffset(hx(20), hy(22))
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = H.stored
	H.storedEmpty = hlabel(root, "StoredEmpty", 640, 300, 1370, 400, 22)
	H.storedEmpty.TextColor3 = INK_DIM

	H.pick = hscroll(root, "Pick", 597, 195, 1411, 503)
	H.pick.Visible = false
	local pickLayout = Instance.new("UIListLayout")
	pickLayout.Padding = UDim.new(0, 4)
	pickLayout.SortOrder = Enum.SortOrder.LayoutOrder
	pickLayout.Parent = H.pick
	H.pickEmpty = hlabel(root, "PickEmpty", 640, 300, 1370, 400, 22)
	H.pickEmpty.TextColor3 = INK_DIM
	H.pickEmpty.Visible = false

	-- ------------------------------------------------------------ Naechstes Ei (lila)
	H.nextTitle = hlabel(root, "NextTitle", 600, 550, 843, 592, 20)
	H.nextTime = hlabel(root, "NextTime", 600, 600, 843, 680, 40)

	-- ------------------------------------------------------------ Gluecks-Bonus (gruen)
	H.luckTitle = hlabel(root, "LuckTitle", 886, 548, 1134, 588, 20)
	H.luckPct = hlabel(root, "LuckPct", 886, 586, 1134, 636, 30)
	local bar = Instance.new("Frame")
	bar.Name = "LuckBar"
	bar.BackgroundColor3 = Color3.fromRGB(28, 12, 4)
	bar.BorderSizePixel = 0
	bar.ZIndex = 6
	bar.Parent = root
	place(bar, 900, 640, 1120, 664)
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0.5, 0)
	barCorner.Parent = bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.BackgroundColor3 = GREEN
	fill.BorderSizePixel = 0
	fill.ZIndex = 7
	fill.Size = UDim2.fromScale(0, 1)
	fill.Parent = bar
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.5, 0)
	fillCorner.Parent = fill
	H.luckFill = fill
	H.luckMin = hlabel(root, "LuckMin", 900, 640, 1120, 664, 12, nil, 8)
	H.luckReset = hlabel(root, "LuckReset", 890, 666, 1130, 690, 10)
	H.luckReset.TextStrokeTransparency = 0.5

	-- ------------------------------------------------------------ Ei-Lager (blau)
	H.storageTitle = hlabel(root, "StorageTitle", 1177, 550, 1430, 592, 20)
	H.storageValue = hlabel(root, "StorageValue", 1177, 600, 1430, 680, 40)

	-- ------------------------------------------------------------ Eier abholen (goldene Leiste)
	H.claimCover = hcover(root, "ClaimCover", 668, 740, 1370, 862, 40)
	H.claimLabel = hlabel(root, "ClaimText", 700, 750, 1340, 852, 40)
	H.claimLabel.TextStrokeTransparency = 0.15
	hbutton(root, "Claim", 668, 740, 1370, 862).Activated:Connect(function()
		local data = ClientState.get()
		if not data or IncubatorRules.storedTotal(data.island.incubator) <= 0 then return end
		Remotes.RequestIncubatorCollect:FireServer()
	end)

	-- ------------------------------------------------------------ Ausbau (dunkle Leiste oben rechts)
	H.upLabel = hlabel(root, "UpgradeText", 850, 48, 1290, 94, 20)
	H.upButton = hbutton(root, "Upgrade", 830, 42, 1305, 98)
	H.upButton.Activated:Connect(function()
		Remotes.RequestUpgradeIncubator:FireServer()
	end)

	_honeyRebuild = rebuildHoney
	_honeyTick = function()
		local data = ClientState.get()
		if not data or not data.island.incubator then return end
		local incubator = data.island.incubator
		local entry, baerchi = sitterOf(data)
		if entry and baerchi then
			if IncubatorRules.storedFree(incubator) <= 0 then
				H.nextTime.Text = Loc.t("ui.incubator.h_full")
			else
				local seconds = IncubatorRules.breedSeconds(baerchi.rarity, IncubatorRules.levelOf(incubator))
				H.nextTime.Text = fmtClock(math.ceil(math.max(0, entry.lastEggAt + seconds - now())))
			end
		else
			H.nextTime.Text = "--:--"
		end
		local percent, seconds = luckNow(entry)
		local maxSeconds = IncubatorConfig.LUCK.MAX_SECONDS
		H.luckPct.Text = "+" .. Loc.formatDecimal(percent, 1) .. "%"
		H.luckMin.Text = Loc.t("ui.incubator.h_luck_min", { n = math.floor(seconds / 60), max = maxSeconds // 60 })
		H.luckFill.Size = UDim2.fromScale(math.clamp(seconds / maxSeconds, 0, 1), 1)
		local key = string.format("%.1f", percent)
		if key ~= _lastLuckKey then
			_lastLuckKey = key
			rebuildOdds()
		end
	end
	_honeyReset = function()
		_pick = false
		applyPick()
	end
end

function IncubatorPanel.init(screenGui: ScreenGui)
	local honeyReady = FeatureFlags.isOn("UI_HONEY_SKIN") and Icons.hasUi("honey/incubator_window")
	local root = Theme.dialog(
		"IncubatorPanel", screenGui,
		Vector2.new(0.5, 0.7),
		if honeyReady then Vector2.new(WIN_W, WIN_H) else Vector2.new(320, 340),
		if honeyReady then Vector2.new(WIN_W, WIN_H) else Vector2.new(560, 640)
	)
	_root = root
	_honey = honeyReady and Icons.honeyWindow(root, "honey/incubator_window", WIN_W, WIN_H) ~= nil
	local header = Theme.dialogHeader(root, Loc.t("ui.incubator.title"), function()
		PanelManager.close(PANEL_NAME)
	end)
	Loc.onChanged(function()
		header.Text = Loc.t("ui.incubator.title")
		_signature = ""
		refresh()
	end)

	if _honey then
		-- Titel in den Holzbalken, Kreuz auf das Kreuz im Bild
		Icons.honeyHeader(root, Rect.new(hx(180), hy(42), hx(550), hy(98)), hx(1433), hy(78), 84 * HS)
		header.TextScaled = true
		local limit = Instance.new("UITextSizeConstraint")
		limit.MaxTextSize = 24
		limit.MinTextSize = 8
		limit.Parent = header
		buildHoney(root)
	else
		local body = Theme.dialogBody(root)
		local scroller = Theme.scroller("List", body)
		scroller.Size = UDim2.fromScale(1, 1)
		_scroller = scroller
		Theme.listLayout(scroller, 6).HorizontalAlignment = Enum.HorizontalAlignment.Left
	end

	PanelManager.register(PANEL_NAME, {
		open = function()
			root.Visible = true
			if _honeyReset then _honeyReset() end
			_signature = ""
			refresh()
		end,
		close = function()
			root.Visible = false
			if _honeyReset then _honeyReset() end
		end,
	})

	ClientState.onChanged(refresh)

	task.spawn(function()
		while true do
			task.wait(0.5)
			if root.Visible then
				tick()
			end
		end
	end)

	print("[IncubatorPanel] Initialisiert | Solo-Inkubator, Stufen", IncubatorConfig.MAX_LEVEL)
end

return IncubatorPanel
