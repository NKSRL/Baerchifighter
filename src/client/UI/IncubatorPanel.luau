--!strict
-- IncubatorPanel.luau
-- StarterPlayerScripts/UI/IncubatorPanel.luau
--
-- Einzige Zustaendigkeit:
--   - Das Fenster des Inkubators (Sammel-Update 05.10., Paket 8, Umbau nach
--     Rueckmeldung 05.10.): belegte Plaetze mit Baerchi, Takt, Fortschritt,
--     wartenden Eiern und Ei-Chancen (Herausnehmen), Abholen, die eigenen
--     Baerchis zum Einsetzen, Ausbau mit Vorher/Nachher.
--
-- Oeffnet NUR am Inkubator (Prompt aus IncubatorController) — kein
-- Seitenknopf. Rechnet mit Modules/IncubatorRules (dieselben Regeln wie der
-- Server) und workspace:GetServerTimeNow() als "jetzt" (die Zeitmarken sind
-- os.time() des Servers). Entscheiden tut der Server (IncubatorService).
--
-- Neu gebaut wird nur, wenn sich der Inhalt aendert (Signatur); der
-- Fortschritt laeuft in einer eigenen Schleife. So geht ein Tipp nicht
-- verloren, weil die Zeile gerade neu gebaut wurde (siehe Sammel-Update 1.3).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local Types           = require(ReplicatedStorage.Network.Types)
local Remotes         = require(ReplicatedStorage.Network.Remotes)
local Loc             = require(ReplicatedStorage.Localization.Loc)
local EggConfig       = require(ReplicatedStorage.Config.EggConfig)
local BaerchiConfig   = require(ReplicatedStorage.Config.BaerchiConfig)
local IncubatorConfig = require(ReplicatedStorage.Config.IncubatorConfig)
local IncubatorRules  = require(ReplicatedStorage.Modules.IncubatorRules)

local Theme        = require(script.Parent.Theme)
local PanelManager = require(script.Parent.PanelManager)
local EggIcon      = require(script.Parent.EggIcon)
local ClientState  = require(script.Parent.Parent.Controllers.ClientState)

local IncubatorPanel = {}

local PANEL_NAME = "Incubator"
IncubatorPanel.PANEL_NAME = PANEL_NAME

local SLOT_H    = 112
local PICK_H    = 52
local MAX_PICKS = 40   -- so viele Baerchis zur Auswahl (die seltensten zuerst)
local MAX_CHANCES = 4  -- so viele Ei-Chancen pro Platz

local _root: Frame? = nil
local _scroller: ScrollingFrame? = nil
local _signature = ""
-- Zeilen der Plaetze: Fortschritt laeuft ohne Neubau
type SlotRow = { slot: number, interval: number, bar: Theme.Progress }
local _slotRows: { SlotRow } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function eggName(eggType: string): string
	local def = EggConfig.data[eggType :: Types.EggType]
	return Loc.name("egg." .. eggType .. ".name", if def then def.displayName else eggType)
end

local function baerchiName(baerchi: Types.Baerchi): string
	local def = BaerchiConfig.getById(baerchi.configId)
	return Loc.name("baerchi." .. baerchi.configId .. ".name", if def then def.displayName else baerchi.configId)
end

-- "Basis-Ei 70 % · Zucker-Ei 25 % · ..." — was dieser Baerchi bruetet.
function IncubatorPanel.chanceText(baerchi: Types.Baerchi, eggTree: Types.EggTreeState?): string
	local parts: { string } = {}
	for i, entry in IncubatorRules.chances(baerchi, eggTree) do
		if i > MAX_CHANCES then break end
		local digits = if entry.percent < 10 then 1 else 0
		table.insert(parts, string.format("%s %s %%", eggName(entry.eggType), Loc.formatDecimal(entry.percent, digits)))
	end
	return table.concat(parts, " · ")
end

local function signatureOf(data: any): string
	local incubator = data.island.incubator
	if not incubator then return "none" end
	local parts = { tostring(incubator.level), tostring(IncubatorRules.slotCountFor(data)),
		tostring(data.gummies), tostring(data.goldGummies), Loc.getLanguage(), tostring(data.island.equippedUid) }
	for _, entry in incubator.slots do
		table.insert(parts, string.format("%d=%s@%d#%d", entry.slot, entry.baerchiUid, entry.lastEggAt, #entry.eggs))
	end
	local uids = {}
	for uid in data.island.baerchis do table.insert(uids, uid) end
	table.sort(uids)
	table.insert(parts, table.concat(uids, ","))
	return table.concat(parts, "|")
end

--------------------------------------------------------------------------------
-- Fortschritt (laeuft jede halbe Sekunde, baut nichts neu)
--------------------------------------------------------------------------------

local function tickRows()
	local data = ClientState.get()
	if not data or not data.island.incubator then return end
	local t = now()
	for _, row in _slotRows do
		local entry = IncubatorRules.findSlot(data.island.incubator.slots, row.slot)
		if not entry then continue end
		local full = #entry.eggs >= IncubatorConfig.STORE_PER_SLOT
		row.bar.fill.Size = UDim2.fromScale(IncubatorRules.progress(entry, row.interval, t), 1)
		row.bar.text.Text = if full
			then Loc.t("ui.incubator.full_store")
			else Loc.t("ui.incubator.next_egg", { time = Loc.formatDuration(math.max(0, math.ceil(entry.lastEggAt + row.interval - t))) })
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

	local island = data.island
	local incubator = island.incubator
	local count = IncubatorRules.slotCountFor(data)
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	-- Plaetze ---------------------------------------------------------------
	sectionRow(scroller, nextOrder(), Loc.t("ui.incubator.slots", { used = #incubator.slots, total = count }))
	for index = 1, count do
		local entry = IncubatorRules.findSlot(incubator.slots, index)
		local baerchi = if entry then island.baerchis[entry.baerchiUid] else nil
		local row = Theme.panel("Slot_" .. index, scroller, Theme.COLORS.panel)
		row.LayoutOrder = nextOrder()

		if entry and baerchi then
			row.Size = UDim2.new(1, -8, 0, SLOT_H)
			local color = BaerchiConfig.getRarityColor(baerchi.rarity)
			local interval = IncubatorRules.breedSeconds(baerchi.rarity, incubator.level)

			local name = Theme.label("Name", row, string.format("%s  ·  %s", baerchiName(baerchi),
				Loc.name("rarity." .. baerchi.rarity, baerchi.rarity)))
			name.Position = UDim2.new(0, 10, 0, 4)
			name.Size = UDim2.new(1, -150, 0, 24)
			name.TextColor3 = color
			Theme.outlineText(name, 2)

			local pace = Theme.bodyText("Pace", row, Loc.t("ui.incubator.pace", {
				time = Loc.formatDuration(interval), n = #entry.eggs, max = IncubatorConfig.STORE_PER_SLOT }))
			pace.Position = UDim2.new(0, 10, 0, 28)
			pace.Size = UDim2.new(1, -150, 0, 18)

			local chances = Theme.bodyText("Chances", row, "🥚 " .. IncubatorPanel.chanceText(baerchi, data.eggTree))
			chances.Position = UDim2.new(0, 10, 0, 48)
			chances.Size = UDim2.new(1, -20, 0, 32)
			chances.TextWrapped = true
			chances.TextColor3 = Theme.COLORS.goldGummy

			local bar = Theme.progress(row, color)
			bar.track.Position = UDim2.new(0, 10, 1, -26)
			bar.track.Size = UDim2.new(1, -20, 0, 18)
			bar.text.TextScaled = false
			bar.text.TextSize = 12

			local out = Theme.button("Remove", row, Loc.t("ui.incubator.remove"), Theme.COLORS.panelLight)
			out.AnchorPoint = Vector2.new(1, 0)
			out.Position = UDim2.new(1, -8, 0, 8)
			out.Size = UDim2.fromOffset(128, 34)
			out.TextColor3 = Theme.COLORS.text
			out.Activated:Connect(function()
				Remotes.RequestIncubatorRemove:FireServer(index)
			end)

			table.insert(_slotRows, { slot = index, interval = interval, bar = bar })
		else
			row.Size = UDim2.new(1, -8, 0, 44)
			local free = Theme.bodyText("Free", row, Loc.t("ui.incubator.free"))
			free.Position = UDim2.new(0, 12, 0, 0)
			free.Size = UDim2.new(1, -24, 1, 0)
			free.TextYAlignment = Enum.TextYAlignment.Center
		end
	end

	-- Abholen ------------------------------------------------------------------
	local stored = IncubatorRules.storedCount(incubator.slots)
	if stored > 0 then
		local allRow = Theme.container("CollectAll", scroller)
		allRow.Size = UDim2.new(1, -8, 0, 44)
		allRow.LayoutOrder = nextOrder()
		local all = Theme.bigButton("All", allRow, Loc.t("ui.incubator.collect_all", { n = stored }), Theme.COLORS.good)
		all.Size = UDim2.fromScale(1, 1)
		all.Activated:Connect(function()
			Remotes.RequestIncubatorCollect:FireServer()
		end)
	end

	-- Baerchis zum Einsetzen ------------------------------------------------------
	sectionRow(scroller, nextOrder(), Loc.t("ui.incubator.pick"))
	local freeSlot = IncubatorRules.firstFree(incubator.slots, count) ~= nil
	local picks: { Types.Baerchi } = {}
	for uid, baerchi in island.baerchis do
		if uid ~= island.equippedUid and not IncubatorRules.slotOf(incubator.slots, uid) then
			table.insert(picks, baerchi)
		end
	end
	table.sort(picks, function(a, b)
		local ra, rb = BaerchiConfig.getRarityIndex(a.rarity), BaerchiConfig.getRarityIndex(b.rarity)
		if ra ~= rb then return ra > rb end
		return a.uid < b.uid
	end)
	if #picks == 0 then
		local empty = Theme.bodyText("Empty", scroller, Loc.t("ui.incubator.no_baerchis"))
		empty.Size = UDim2.new(1, -8, 0, 40)
		empty.LayoutOrder = nextOrder()
	end
	for i, baerchi in picks do
		if i > MAX_PICKS then break end
		local row = Theme.panel("Pick_" .. i, scroller, Theme.COLORS.panel)
		row.Size = UDim2.new(1, -8, 0, PICK_H)
		row.LayoutOrder = nextOrder()

		local name = Theme.label("Name", row, string.format("%s  ·  %s", baerchiName(baerchi),
			Loc.name("rarity." .. baerchi.rarity, baerchi.rarity)))
		name.Position = UDim2.new(0, 10, 0, 4)
		name.Size = UDim2.new(1, -150, 0, 22)
		name.TextColor3 = BaerchiConfig.getRarityColor(baerchi.rarity)
		Theme.outlineText(name, 2)

		local pace = Theme.bodyText("Pace", row, Loc.t("ui.incubator.pace_short", {
			time = Loc.formatDuration(IncubatorRules.breedSeconds(baerchi.rarity, incubator.level)) }))
		pace.Position = UDim2.new(0, 10, 0, 26)
		pace.Size = UDim2.new(1, -150, 0, 20)

		local put = Theme.button("Put", row, Loc.t("ui.incubator.put"), Theme.COLORS.accent)
		put.AnchorPoint = Vector2.new(1, 0.5)
		put.Position = UDim2.new(1, -8, 0.5, 0)
		put.Size = UDim2.fromOffset(128, 36)
		Theme.setEnabled(put, freeSlot)
		local uid = baerchi.uid
		put.Activated:Connect(function()
			Remotes.RequestIncubatorStart:FireServer(uid)
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
			if root.Visible then tickRows() end
		end
	end)

	print("[IncubatorPanel] Initialisiert | Plaetze max", IncubatorConfig.MAX_SLOTS)
end

return IncubatorPanel
