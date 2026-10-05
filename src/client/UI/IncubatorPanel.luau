--!strict
-- IncubatorPanel.luau
-- StarterPlayerScripts/UI/IncubatorPanel.luau
--
-- Einzige Zustaendigkeit:
--   - Das Fenster des Inkubators (Sammel-Update 05.10., Paket 8): Plaetze mit
--     Ei und Restzeit (Abholen / Beschleunigen), Eier aus dem Lager zum
--     Einlegen, Ausbau mit Vorher/Nachher.
--
-- Rechnet mit Modules/IncubatorRules (dieselben Regeln wie der Server) und
-- workspace:GetServerTimeNow() als "jetzt" — die Zeitmarken der Plaetze sind
-- os.time() des Servers. Entscheiden tut der Server (IncubatorService).
--
-- Neu gebaut wird nur, wenn sich der Inhalt aendert (Signatur); die Restzeiten
-- laufen in einer eigenen Schleife. So geht ein Tipp nicht verloren, weil die
-- Zeile gerade neu gebaut wurde (siehe Sammel-Update 1.3).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local Types           = require(ReplicatedStorage.Network.Types)
local Remotes         = require(ReplicatedStorage.Network.Remotes)
local Loc             = require(ReplicatedStorage.Localization.Loc)
local EggConfig       = require(ReplicatedStorage.Config.EggConfig)
local IncubatorConfig = require(ReplicatedStorage.Config.IncubatorConfig)
local IncubatorRules  = require(ReplicatedStorage.Modules.IncubatorRules)

local Theme        = require(script.Parent.Theme)
local PanelManager = require(script.Parent.PanelManager)
local EggIcon      = require(script.Parent.EggIcon)
local ClientState  = require(script.Parent.Parent.Controllers.ClientState)

local IncubatorPanel = {}

local PANEL_NAME = "Incubator"
IncubatorPanel.PANEL_NAME = PANEL_NAME

local ROW_H = 64

local _root: Frame? = nil
local _scroller: ScrollingFrame? = nil
local _signature = ""
-- Zeilen der Plaetze: Restzeit-Label und Knoepfe, damit die Uhr ohne Neubau laeuft
type SlotRow = { slot: number, timeLabel: TextLabel, collect: TextButton, speed: TextButton }
local _slotRows: { SlotRow } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function eggName(eggType: string): string
	local def = EggConfig.data[eggType :: Types.EggType]
	return Loc.name("egg." .. eggType .. ".name", if def then def.displayName else eggType)
end

local function signatureOf(data: any): string
	local incubator = data.island.incubator
	if not incubator then return "none" end
	local parts = { tostring(incubator.level), tostring(IncubatorRules.slotCountFor(data)),
		tostring(data.gummies), tostring(data.goldGummies), Loc.getLanguage() }
	for _, entry in incubator.slots do
		table.insert(parts, string.format("%d=%s@%d", entry.slot, entry.eggType, entry.finishAt))
	end
	local stock = {}
	for eggType, count in data.island.eggStock do
		if count > 0 then table.insert(stock, eggType .. "x" .. count) end
	end
	table.sort(stock)
	table.insert(parts, table.concat(stock, ","))
	return table.concat(parts, "|")
end

--------------------------------------------------------------------------------
-- Restzeiten (laeuft jede halbe Sekunde, baut nichts neu)
--------------------------------------------------------------------------------

local function tickRows()
	local data = ClientState.get()
	if not data or not data.island.incubator then return end
	local t = now()
	for _, row in _slotRows do
		local entry = IncubatorRules.findSlot(data.island.incubator.slots, row.slot)
		if not entry then continue end
		local ready = IncubatorRules.isReady(entry, t)
		row.timeLabel.Text = if ready
			then Loc.t("ui.incubator.ready")
			else Loc.t("ui.incubator.left", { time = Loc.formatDuration(IncubatorRules.remaining(entry, t)) })
		row.timeLabel.TextColor3 = if ready then Theme.COLORS.good else Theme.COLORS.textDim
		row.collect.Visible = ready
		row.speed.Visible = not ready
		row.speed.Text = Loc.t("ui.incubator.speedup", { gold = IncubatorRules.speedUpCost(entry, t) })
	end
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

local function rebuild()
	local scroller = _scroller
	if not scroller then return end
	local data = ClientState.get()
	if not data or not data.island.incubator then return end

	for _, child in scroller:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	table.clear(_slotRows)

	local incubator = data.island.incubator
	local count = IncubatorRules.slotCountFor(data)
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	-- Plaetze ---------------------------------------------------------------
	sectionRow(scroller, nextOrder(), Loc.t("ui.incubator.slots", { used = #incubator.slots, total = count }))
	local readyCount = 0
	for index = 1, math.max(count, #incubator.slots) do
		local entry = IncubatorRules.findSlot(incubator.slots, index)
		local row = Theme.panel("Slot_" .. index, scroller, Theme.COLORS.panel)
		row.Size = UDim2.new(1, -8, 0, ROW_H)
		row.LayoutOrder = nextOrder()

		if entry then
			local icon = EggIcon.make(row, entry.eggType, 48, 2)
			icon.AnchorPoint = Vector2.new(0, 0.5)
			icon.Position = UDim2.new(0, 8, 0.5, 0)

			local name = Theme.label("Name", row, eggName(entry.eggType))
			name.Position = UDim2.new(0, 64, 0, 6)
			name.Size = UDim2.new(1, -200, 0, 24)

			local timeLabel = Theme.label("Time", row, "")
			timeLabel.Position = UDim2.new(0, 64, 0, 32)
			timeLabel.Size = UDim2.new(1, -200, 0, 22)
			timeLabel.Font = Theme.FONT_BODY

			local collect = Theme.bigButton("Collect", row, Loc.t("ui.incubator.collect"), Theme.COLORS.good)
			collect.AnchorPoint = Vector2.new(1, 0.5)
			collect.Position = UDim2.new(1, -8, 0.5, 0)
			collect.Size = UDim2.fromOffset(128, 40)
			collect.Activated:Connect(function()
				Remotes.RequestIncubatorCollect:FireServer(index)
			end)

			local speed = Theme.button("Speed", row, "", Theme.COLORS.goldGummy)
			speed.AnchorPoint = Vector2.new(1, 0.5)
			speed.Position = UDim2.new(1, -8, 0.5, 0)
			speed.Size = UDim2.fromOffset(128, 40)
			speed.TextColor3 = Theme.COLORS.outline
			speed.Activated:Connect(function()
				Remotes.RequestIncubatorSpeedUp:FireServer(index)
			end)

			table.insert(_slotRows, { slot = index, timeLabel = timeLabel, collect = collect, speed = speed })
			if IncubatorRules.isReady(entry, now()) then readyCount += 1 end
		else
			local free = Theme.bodyText("Free", row, Loc.t("ui.incubator.free"))
			free.Position = UDim2.new(0, 12, 0, 0)
			free.Size = UDim2.new(1, -24, 1, 0)
			free.TextYAlignment = Enum.TextYAlignment.Center
		end
	end

	if readyCount > 1 then
		local allRow = Theme.container("CollectAll", scroller)
		allRow.Size = UDim2.new(1, -8, 0, 40)
		allRow.LayoutOrder = nextOrder()
		local all = Theme.bigButton("All", allRow, Loc.t("ui.incubator.collect_all", { n = readyCount }), Theme.COLORS.good)
		all.Size = UDim2.fromScale(1, 1)
		all.Activated:Connect(function()
			Remotes.RequestIncubatorCollect:FireServer("all")
		end)
	end

	-- Eier aus dem Lager --------------------------------------------------------
	sectionRow(scroller, nextOrder(), Loc.t("ui.incubator.stock"))
	local freeSlot = IncubatorRules.firstFree(incubator.slots, count) ~= nil
	local ids: { Types.EggType } = {}
	for eggType, n in data.island.eggStock do
		if n > 0 and EggConfig.data[eggType] then table.insert(ids, eggType) end
	end
	table.sort(ids, function(a, b) return EggConfig.data[a].sortOrder < EggConfig.data[b].sortOrder end)
	if #ids == 0 then
		local empty = Theme.bodyText("Empty", scroller, Loc.t("ui.incubator.no_eggs"))
		empty.Size = UDim2.new(1, -8, 0, 40)
		empty.LayoutOrder = nextOrder()
	end
	for _, eggType in ids do
		local row = Theme.panel("Egg_" .. eggType, scroller, Theme.COLORS.panel)
		row.Size = UDim2.new(1, -8, 0, 52)
		row.LayoutOrder = nextOrder()

		local icon = EggIcon.make(row, eggType, 40, 2)
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 8, 0.5, 0)

		local name = Theme.label("Name", row, string.format("%s  x%d", eggName(eggType), data.island.eggStock[eggType] or 0))
		name.Position = UDim2.new(0, 56, 0, 4)
		name.Size = UDim2.new(1, -200, 0, 22)

		local brew = Theme.bodyText("Brew", row, Loc.t("ui.incubator.brew_time", {
			time = Loc.formatDuration(IncubatorRules.brewSeconds(eggType, incubator.level)) }))
		brew.Position = UDim2.new(0, 56, 0, 26)
		brew.Size = UDim2.new(1, -200, 0, 20)

		local put = Theme.button("Put", row, Loc.t("ui.incubator.put"), Theme.COLORS.accent)
		put.AnchorPoint = Vector2.new(1, 0.5)
		put.Position = UDim2.new(1, -8, 0.5, 0)
		put.Size = UDim2.fromOffset(128, 36)
		Theme.setEnabled(put, freeSlot)
		put.Activated:Connect(function()
			Remotes.RequestIncubatorStart:FireServer(eggType)
		end)
	end

	-- Ausbau -------------------------------------------------------------------
	sectionRow(scroller, nextOrder(), Loc.t("ui.incubator.upgrade_title", { level = incubator.level }))
	local cost = IncubatorRules.upgradeCost(incubator.level + 1)
	local upRow = Theme.panel("Upgrade", scroller, Theme.COLORS.panel)
	upRow.Size = UDim2.new(1, -8, 0, 70)
	upRow.LayoutOrder = nextOrder()
	local effect = Theme.bodyText("Effect", upRow, "")
	effect.Position = UDim2.new(0, 10, 0, 4)
	effect.Size = UDim2.new(1, -160, 1, -8)
	if cost then
		local nextCount = IncubatorRules.slotCount(incubator.level + 1, data.rebirthCount or 0, (data :: any).indexClaimed)
		effect.Text = Loc.t("ui.incubator.upgrade_effect", {
			speedNow  = Loc.formatDecimal(IncubatorRules.speed(incubator.level), 2),
			speedNext = Loc.formatDecimal(IncubatorRules.speed(incubator.level + 1), 2),
			slotsNow  = count,
			slotsNext = nextCount,
		})
		local up = Theme.bigButton("Up", upRow, Loc.t("ui.incubator.upgrade_cost", {
			gummies = cost.gummies, gold = cost.goldGummies }), Theme.COLORS.gummy)
		up.AnchorPoint = Vector2.new(1, 0.5)
		up.Position = UDim2.new(1, -8, 0.5, 0)
		up.Size = UDim2.fromOffset(140, 48)
		Theme.setEnabled(up, data.gummies >= cost.gummies and data.goldGummies >= cost.goldGummies)
		up.Activated:Connect(function()
			Remotes.RequestUpgradeIncubator:FireServer()
		end)
	else
		effect.Text = Loc.t("ui.incubator.max_level")
	end

	tickRows()
end

local function refresh()
	local root = _root
	if not root or not root.Visible then return end
	local data = ClientState.get()
	if not data then return end
	local signature = signatureOf(data)
	if signature == _signature then return end
	_signature = signature
	rebuild()
end

--------------------------------------------------------------------------------
-- Aufbau
--------------------------------------------------------------------------------

function IncubatorPanel.init(screenGui: ScreenGui)
	local root = Theme.dialog("IncubatorPanel", screenGui, Vector2.new(0.5, 0.7), Vector2.new(320, 340), Vector2.new(560, 640))
	_root = root
	local header = Theme.dialogHeader(root, Loc.t("ui.incubator.title"), function()
		PanelManager.close(PANEL_NAME)
	end)
	Loc.onChanged(function()
		header.Text = Loc.t("ui.incubator.title")
		_signature = ""
		refresh()
	end)

	local body = Theme.dialogBody(root)
	local scroller = Theme.scroller("List", body)
	scroller.Size = UDim2.fromScale(1, 1)
	_scroller = scroller
	Theme.listLayout(scroller, 6).HorizontalAlignment = Enum.HorizontalAlignment.Left

	PanelManager.register(PANEL_NAME, {
		open = function()
			root.Visible = true
			_signature = ""
			refresh()
		end,
		close = function()
			root.Visible = false
		end,
	})

	ClientState.onChanged(refresh)

	task.spawn(function()
		while true do
			task.wait(0.5)
			if root.Visible then
				-- Ein fertig gewordener Platz aendert die Knoepfe: einmal neu
				-- bauen, wenn sich die Zahl der fertigen aendert.
				local data = ClientState.get()
				if data and data.island.incubator then
					local ready = 0
					for _, entry in data.island.incubator.slots do
						if IncubatorRules.isReady(entry, now()) then ready += 1 end
					end
					if root:GetAttribute("Ready") ~= ready then
						root:SetAttribute("Ready", ready)
						_signature = ""
						refresh()
					end
				end
				tickRows()
			end
		end
	end)

	print("[IncubatorPanel] Initialisiert | Plaetze max", IncubatorConfig.MAX_SLOTS)
end

return IncubatorPanel
