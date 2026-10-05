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

local FeatureFlags    = require(ReplicatedStorage.Config.FeatureFlags)
local BaerchiConfig   = require(ReplicatedStorage.Config.BaerchiConfig)
local EggCalculator   = require(ReplicatedStorage.Modules.EggCalculator)

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

local function breedOn(): boolean
	return FeatureFlags.isOn("INCUBATOR_BREED")
end

-- INCUBATOR_BREED: Inhalt haengt an Plaetzen, Baerchis und Ausbau
local function breedSignature(data: any): string
	local incubator = data.island.incubator
	local parts = { "breed", tostring(incubator.level), tostring(IncubatorRules.slotCountFor(data)),
		tostring(data.gummies), tostring(data.goldGummies), Loc.getLanguage(), tostring(data.island.equippedUid) }
	for _, entry in incubator.breeders or {} do
		table.insert(parts, string.format("%d=%s", entry.slot, entry.uid))
	end
	local uids = {}
	for uid, baerchi in data.island.baerchis do
		table.insert(uids, uid .. ":" .. baerchi.rarity .. ":" .. tostring(baerchi.mutation))
	end
	table.sort(uids)
	table.insert(parts, table.concat(uids, ","))
	return table.concat(parts, "|")
end

local function signatureOf(data: any): string
	local incubator = data.island.incubator
	if not incubator then return "none" end
	if breedOn() then return breedSignature(data) end
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

-- INCUBATOR_BREED: Zeit bis zum naechsten Ei je Platz
type BreedRow = { slot: number, timeLabel: TextLabel }
local _breedRows: { BreedRow } = {}

local function tickBreedRows(data: any)
	local incubator = data.island.incubator
	local t = now()
	for _, row in _breedRows do
		local entry = IncubatorRules.findBreeder(incubator.breeders, row.slot)
		local baerchi = if entry then data.island.baerchis[entry.uid] else nil
		if not entry or not baerchi then continue end
		local seconds = IncubatorRules.breedSeconds(baerchi.rarity, incubator.level)
		local left = math.max(0, entry.lastEggAt + seconds - t)
		row.timeLabel.Text = Loc.t("ui.incubator.next_egg", { time = Loc.formatDuration(math.ceil(left)) })
	end
end

local function tickRows()
	local data = ClientState.get()
	if not data or not data.island.incubator then return end
	if breedOn() then
		tickBreedRows(data)
		return
	end
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

local function baerchiName(baerchi: any): string
	local def = BaerchiConfig.getById(baerchi.configId)
	return Loc.name("baerchi." .. baerchi.configId .. ".name", if def then def.displayName else baerchi.configId)
end

-- Kurze Chancen-Zeile: "Basis-Ei 60% · Zucker-Ei 30% · ..."
local function oddsLine(baerchi: any, eggTree: any, maxEntries: number): string
	local parts: { string } = {}
	for i, entry in EggCalculator.getResolvedChances(baerchi, eggTree) do
		if i > maxEntries then break end
		local percent = if entry.percent >= 10 then string.format("%d", math.floor(entry.percent + 0.5))
			else Loc.formatDecimal(entry.percent, 1)
		table.insert(parts, string.format("%s %s%%", eggName(entry.eggType), percent))
	end
	return table.concat(parts, " · ")
end

local function upgradeSection(scroller: ScrollingFrame, data: any, count: number, nextOrder: () -> number)
	local incubator = data.island.incubator
	sectionRow(scroller, nextOrder(), Loc.t("ui.incubator.upgrade_title", { level = incubator.level }))
	local cost = IncubatorRules.upgradeCost(incubator.level + 1)
	local upRow = Theme.panel("Upgrade", scroller, Theme.COLORS.panel)
	upRow.Size = UDim2.new(1, -8, 0, 70)
	upRow.LayoutOrder = nextOrder()
	local effect = Theme.bodyText("Effect", upRow, "")
	effect.Position = UDim2.new(0, 10, 0, 4)
	effect.Size = UDim2.new(1, -160, 1, -8)
	if cost then
		local nextCount = IncubatorRules.slotCount(incubator.level + 1, data.rebirthCount or 0, data.indexClaimed)
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
end

-- INCUBATOR_BREED: Plaetze mit Baerchi (Chancen, naechstes Ei, Herausnehmen),
-- darunter die Baerchis zum Einsetzen und der Ausbau.
local function rebuildBreed(scroller: ScrollingFrame, data: any)
	table.clear(_breedRows)
	local incubator = data.island.incubator
	local breeders = incubator.breeders or {}
	local count = IncubatorRules.slotCountFor(data)
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	local hint = Theme.bodyText("Hint", scroller, Loc.t("ui.incubator.breed_hint"))
	hint.Size = UDim2.new(1, -8, 0, 40)
	hint.LayoutOrder = nextOrder()

	sectionRow(scroller, nextOrder(), Loc.t("ui.incubator.slots", { used = #breeders, total = count }))
	local highest = count
	for _, entry in breeders do highest = math.max(highest, entry.slot) end
	for index = 1, highest do
		local entry = IncubatorRules.findBreeder(breeders, index)
		local baerchi = if entry then data.island.baerchis[entry.uid] else nil
		local row = Theme.panel("Slot_" .. index, scroller, Theme.COLORS.panel)
		row.Size = UDim2.new(1, -8, 0, if baerchi then 86 else ROW_H)
		row.LayoutOrder = nextOrder()

		if entry and baerchi then
			local name = Theme.label("Name", row, string.format("%s · %s · Lv.%d",
				baerchiName(baerchi), Loc.name("rarity." .. baerchi.rarity, baerchi.rarity), baerchi.level))
			name.Position = UDim2.new(0, 10, 0, 4)
			name.Size = UDim2.new(1, -150, 0, 22)
			name.TextColor3 = BaerchiConfig.getRarityColor(baerchi.rarity)

			local odds = Theme.bodyText("Odds", row, oddsLine(baerchi, data.eggTree, 4))
			odds.Position = UDim2.new(0, 10, 0, 28)
			odds.Size = UDim2.new(1, -150, 0, 34)
			odds.TextWrapped = true

			local timeLabel = Theme.label("Time", row, "")
			timeLabel.Position = UDim2.new(0, 10, 0, 62)
			timeLabel.Size = UDim2.new(1, -150, 0, 20)
			timeLabel.Font = Theme.FONT_BODY
			timeLabel.TextColor3 = Theme.COLORS.textDim
			if index > count then
				timeLabel.Text = "🔒 " .. Loc.t("ui.incubator.slot_locked")
			else
				table.insert(_breedRows, { slot = index, timeLabel = timeLabel })
			end

			local take = Theme.button("Take", row, Loc.t("ui.incubator.take"), Theme.COLORS.panelLight)
			take.AnchorPoint = Vector2.new(1, 0.5)
			take.Position = UDim2.new(1, -8, 0.5, 0)
			take.Size = UDim2.fromOffset(128, 40)
			take.Activated:Connect(function()
				Remotes.RequestIncubatorBaerchi:FireServer("take", index)
			end)
		else
			local free = Theme.bodyText("Free", row, Loc.t("ui.incubator.free_breed"))
			free.Position = UDim2.new(0, 12, 0, 0)
			free.Size = UDim2.new(1, -24, 1, 0)
			free.TextYAlignment = Enum.TextYAlignment.Center
		end
	end

	-- Baerchis zum Einsetzen --------------------------------------------------
	sectionRow(scroller, nextOrder(), Loc.t("ui.incubator.pick"))
	local freeSlot = IncubatorRules.firstFreeBreeder(breeders, count) ~= nil
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
			time = Loc.formatDuration(IncubatorRules.breedSeconds(baerchi.rarity, incubator.level)) })
			.. "\n" .. oddsLine(baerchi, data.eggTree, 3))
		info.Position = UDim2.new(0, 10, 0, 26)
		info.Size = UDim2.new(1, -150, 0, 40)
		info.TextWrapped = true

		local put = Theme.button("Put", row, Loc.t("ui.incubator.put_baerchi"), Theme.COLORS.accent)
		put.AnchorPoint = Vector2.new(1, 0.5)
		put.Position = UDim2.new(1, -8, 0.5, 0)
		put.Size = UDim2.fromOffset(128, 40)
		Theme.setEnabled(put, freeSlot)
		local uid = baerchi.uid
		put.Activated:Connect(function()
			Remotes.RequestIncubatorBaerchi:FireServer("put", uid)
		end)
	end

	upgradeSection(scroller, data, count, nextOrder)
	tickBreedRows(data)
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

	if breedOn() then
		rebuildBreed(scroller, data)
		return
	end

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
