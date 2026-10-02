--!strict
-- HatchPanel.luau
-- StarterPlayerScripts/UI/HatchPanel.luau
--
-- Einzige Zustaendigkeit:
--   - Eier einlegen, laufende Bruten anzeigen, fertige Eier abholen
--   - Das Hatch-Ergebnis kurz auf einer Rarity-Karte zeigen
--
-- Die Brut-Timer laufen ueber absolute os.time()-Zeitstempel
-- (Types.HatchingEgg.startedAt/readyAt). Der Balken zwischen zwei
-- PlayerDataUpdated wird deshalb rein oertlich hochgezaehlt — das ist reine
-- Optik, geclaimt wird ausschliesslich ueber den Server, der die Zeit selbst
-- nochmal prueft.
--
-- Wie viele Slots es gibt (EconomyConfig.HATCH_SLOTS) und wie lange ein Ei
-- braucht (EggConfig.hatchTime) sind seit v4 feste Werte ohne Gebaeude
-- dahinter — der Client rechnet sie nur zur Anzeige nach, entschieden wird
-- es im EggService.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Types         = require(ReplicatedStorage.Network.Types)
local Remotes       = require(ReplicatedStorage.Network.Remotes)
local EggConfig     = require(ReplicatedStorage.Config.EggConfig)
local EconomyConfig = require(ReplicatedStorage.Config.EconomyConfig)
local BaerchiConfig = require(ReplicatedStorage.Config.BaerchiConfig)

local Theme        = require(script.Parent.Theme)
local PanelManager = require(script.Parent.PanelManager)
local ClientState  = require(script.Parent.Parent.Controllers.ClientState)

local HatchPanel = {}

local PANEL_NAME   = "Hatch"
local SLOT_HEIGHT  = 40
local EGG_HEIGHT   = 80
local TICK_SECONDS = 0.2    -- oefter als 5x pro Sekunde sieht niemand
local REVEAL_TIME  = 2.6

local _root: Frame?              = nil
local _scroller: ScrollingFrame? = nil

-- Anzeige-Elemente der Brut-Slots, damit der Tick sie nicht suchen muss
type SlotView = {
	index    : number,
	progress : Theme.Progress,
	claim    : TextButton,
	entry    : Types.HatchingEgg?,
}
local _slotViews: { SlotView } = {}

-- Reveal-Karte (haengt am ScreenGui, nicht am Panel: das Ergebnis soll auch
-- ankommen wenn der Spieler das Panel inzwischen zugemacht hat)
local _reveal: Frame?           = nil
local _revealTitle: TextLabel?  = nil
local _revealSub: TextLabel?    = nil
local _revealNew: TextLabel?    = nil
local _revealToken = 0

--------------------------------------------------------------------------------
-- Reihenfolge der Eier
--------------------------------------------------------------------------------

-- Nach Brutdauer aufsteigend: das ist genau die Reihenfolge in der die Eier
-- im Spiel freigeschaltet werden, und sie ist stabil (die Iteration ueber
-- EggConfig.data waere es nicht).
local function buildEggOrder(): { Types.EggType }
	local list: { Types.EggType } = {}
	for eggType in EggConfig.data do
		table.insert(list, eggType)
	end

	table.sort(list, function(a, b)
		local defA = EggConfig.data[a]
		local defB = EggConfig.data[b]
		if defA.hatchTime ~= defB.hatchTime then
			return defA.hatchTime < defB.hatchTime
		end
		return a < b
	end)

	return list
end

local EGG_ORDER = buildEggOrder()

--------------------------------------------------------------------------------
-- Kosten und Verfuegbarkeit (reine Anzeige-Vorschau, siehe Kopf)
--------------------------------------------------------------------------------

local function getStock(data: Types.PlayerDataUpdate, eggType: Types.EggType): number
	return data.island.eggStock[eggType] or 0
end

local function costText(eggType: Types.EggType, stock: number): string
	local def = EggConfig.data[eggType]

	if stock > 0 then
		return "Im Lager: " .. stock
	end
	if def.costGummies > 0 then
		return Theme.formatNumber(def.costGummies) .. " Gummies"
	end
	if def.costGoldGummies > 0 then
		return Theme.formatNumber(def.costGoldGummies) .. " GoldGummies"
	end
	return "Nur aus Rebirth"
end

local function canAfford(data: Types.PlayerDataUpdate, eggType: Types.EggType, stock: number): boolean
	local def = EggConfig.data[eggType]

	if stock > 0 then return true end
	if def.costGummies > 0 then return data.gummies >= def.costGummies end
	if def.costGoldGummies > 0 then return data.goldGummies >= def.costGoldGummies end
	return false   -- nicht kaufbar und nichts im Lager
end

-- Seit v4 gibt es kein Brueterei-Gebaeude mehr, das die Zeit verkuerzt —
-- die volle Zeit aus EggConfig gilt. Muss mit EggService.getHatchDuration
-- uebereinstimmen, sonst zeigt die UI etwas anderes als der Server macht.
local function getHatchSeconds(_data: Types.PlayerDataUpdate, eggType: Types.EggType): number
	local def = EggConfig.data[eggType]
	return math.max(0, math.floor(def.hatchTime))
end

--------------------------------------------------------------------------------
-- Zeilen bauen
--------------------------------------------------------------------------------

local function buildSectionLabel(parent: Instance, order: number, text: string)
	local label = Theme.label("Section", parent, text)
	label.Size        = UDim2.new(1, -8, 0, 22)
	label.LayoutOrder = order
	label.TextColor3  = Theme.COLORS.textDim
end

local function buildSlotRow(parent: Instance, order: number, index: number, entry: Types.HatchingEgg?)
	local row = Theme.panel("Slot_" .. index, parent, Theme.COLORS.panel)
	row.Size        = UDim2.new(1, -8, 0, SLOT_HEIGHT)
	row.LayoutOrder = order

	local title = Theme.label("Slot", row, "Slot " .. index)
	title.Position = UDim2.new(0, 10, 0.5, -10)
	title.Size     = UDim2.new(0, 54, 0, 20)

	local progress = Theme.progress(row, Theme.COLORS.gummy)
	progress.track.Position = UDim2.new(0, 68, 0.5, -11)
	progress.track.Size     = UDim2.new(1, -180, 0, 22)

	local claim = Theme.button("Claim", row, "Abholen", Theme.COLORS.good)
	claim.AnchorPoint = Vector2.new(1, 0.5)
	claim.Position    = UDim2.new(1, -10, 0.5, 0)
	claim.Size        = UDim2.new(0, 96, 0, 28)

	-- Geclaimt wird ueber die uid, nicht ueber den Slot-Index: zwei schnelle
	-- Klicks wuerden sonst nach dem ersten table.remove auf dem Server ein
	-- anderes Ei treffen als das angeklickte (siehe Types.HatchingEgg).
	-- `entry` ist hier bewusst der Stand vom Zeitpunkt des Zeichnens — die
	-- Zeile wird bei jeder Serverantwort komplett neu gebaut.
	claim.Activated:Connect(function()
		if not entry then return end
		Remotes.RequestClaimEgg:FireServer(entry.uid)
	end)

	table.insert(_slotViews, {
		index    = index,
		progress = progress,
		claim    = claim,
		entry    = entry,
	})
end

local function buildEggCard(parent: Instance, order: number, data: Types.PlayerDataUpdate, eggType: Types.EggType, slotsFree: boolean)
	local def   = EggConfig.data[eggType]
	local stock = getStock(data, eggType)

	local card = Theme.panel("Egg_" .. eggType, parent, Theme.COLORS.panel)
	card.Size        = UDim2.new(1, -8, 0, EGG_HEIGHT)
	card.LayoutOrder = order

	local name = Theme.label("Name", card, def.displayName)
	name.Position = UDim2.new(0, 10, 0, 6)
	name.Size     = UDim2.new(1, -140, 0, 22)

	local desc = Theme.bodyText("Desc", card, def.description)
	desc.Position = UDim2.new(0, 10, 0, 30)
	desc.Size     = UDim2.new(1, -140, 0, 42)

	local cost = Theme.label("Cost", card, costText(eggType, stock))
	cost.Position       = UDim2.new(1, -124, 0, 8)
	cost.Size           = UDim2.new(0, 114, 0, 18)
	cost.TextXAlignment = Enum.TextXAlignment.Right
	cost.TextColor3     = if stock > 0 then Theme.COLORS.good
		elseif def.costGoldGummies > 0 then Theme.COLORS.goldGummy
		else Theme.COLORS.gummy

	local duration = Theme.label("Duration", card, Theme.formatDuration(getHatchSeconds(data, eggType)))
	duration.Position       = UDim2.new(1, -124, 0, 27)
	duration.Size           = UDim2.new(0, 114, 0, 16)
	duration.TextXAlignment = Enum.TextXAlignment.Right
	duration.TextColor3     = Theme.COLORS.textDim

	local button = Theme.button("Start", card, "Einlegen", Theme.COLORS.accent)
	button.Position = UDim2.new(1, -124, 0, 46)
	button.Size     = UDim2.new(0, 114, 0, 28)

	-- Nur eine Vorwarnung — der Server prueft Slots und Kosten selbst
	Theme.setEnabled(button, slotsFree and canAfford(data, eggType, stock))

	button.Activated:Connect(function()
		Remotes.RequestHatchEgg:FireServer(eggType)
	end)
end

--------------------------------------------------------------------------------
-- Aktualisieren
--------------------------------------------------------------------------------

-- Zeichnet nur die Werte der bestehenden Slot-Zeilen neu (laeuft im Tick)
local function updateSlotValues()
	local now = os.time()

	for _, view in _slotViews do
		local entry = view.entry

		if not entry then
			view.progress.fill.Size = UDim2.fromScale(0, 1)
			view.progress.text.Text = "frei"
			view.claim.Visible      = false
			continue
		end

		local total   = math.max(1, entry.readyAt - entry.startedAt)
		local elapsed = now - entry.startedAt
		local ratio   = math.clamp(elapsed / total, 0, 1)
		local ready   = now >= entry.readyAt

		-- Rueckfall auf den rohen Typ-Namen: diese Schleife laeuft mehrmals
		-- pro Sekunde. Ein Ei-Typ der nicht (mehr) in EggConfig steht — etwa
		-- aus einem alten Spielstand — wuerde hier sonst dauerhaft Fehler ins
		-- Log schreiben, und die Zeile bliebe fuer immer eingefroren.
		local def         = EggConfig.data[entry.eggType]
		local displayName = if def then def.displayName else tostring(entry.eggType)

		view.progress.fill.Size = UDim2.fromScale(ratio, 1)
		view.progress.text.Text = if ready
			then displayName .. " — fertig"
			else displayName .. " — " .. Theme.formatDuration(entry.readyAt - now)

		view.claim.Visible = ready
	end
end

function HatchPanel.refresh()
	local scroller = _scroller
	local root     = _root
	if not scroller or not root then return end
	if not root.Visible then return end

	local data = ClientState.get()
	if not data then return end

	for _, child in scroller:GetChildren() do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	table.clear(_slotViews)

	local slots   = EconomyConfig.HATCH_SLOTS
	local running = #data.island.hatchingEggs

	buildSectionLabel(scroller, 1, string.format("Brut-Slots  (%d / %d belegt)", running, slots))

	-- Mindestens so viele Zeilen wie laufende Bruten: haette der Spieler die
	-- Brueterei nach dem Einlegen zurueckgesetzt (Rebirth), waeren sonst
	-- Eier da die er nicht mehr abholen koennte.
	for index = 1, math.max(slots, running) do
		buildSlotRow(scroller, 10 + index, index, data.island.hatchingEggs[index])
	end

	buildSectionLabel(scroller, 100, "Ei einlegen")

	local slotsFree = running < slots
	for order, eggType in EGG_ORDER do
		buildEggCard(scroller, 110 + order, data, eggType, slotsFree)
	end

	updateSlotValues()
end

--------------------------------------------------------------------------------
-- Reveal
--------------------------------------------------------------------------------

local function showReveal(result: Types.HatchResult)
	local reveal = _reveal
	if not reveal then return end

	local baerchi  = result.baerchi
	local def      = BaerchiConfig.getById(baerchi.configId)
	local mutation = baerchi.mutation

	-- Ein mutierter Baerchi uebernimmt die Anzeige komplett: Rahmen, Titel und
	-- Unterzeile (seit v11, ersetzt das binaere Inverted). Auch die
	-- HAEUFIGSTE Stufe ist noch ein 1-von-100-Moment — er soll sich nicht wie
	-- ein normaler Schluepfvorgang mit einem kleinen Zusatz anfuehlen.
	local color = if mutation
		then BaerchiConfig.getMutationColor(mutation)
		else Theme.rarityColor(baerchi.rarity)

	local stroke = reveal:FindFirstChildOfClass("UIStroke")
	if stroke then stroke.Color = color end

	if _revealTitle then
		_revealTitle.Text = (if mutation then BaerchiConfig.getMutationDisplayName(mutation):upper() .. "  " else "")
			.. (def and def.displayName or baerchi.configId)
		_revealTitle.TextColor3 = color
	end
	if _revealSub then
		local eggDef = EggConfig.data[result.eggType]

		_revealSub.Text = string.format(
			"%s%s  —  Lv. %d\naus %s",
			baerchi.rarity,
			if mutation then string.format(" (%s x%.2g)", BaerchiConfig.getMutationDisplayName(mutation), BaerchiConfig.getMutationMultiplier(mutation)) else "",
			baerchi.level,
			if eggDef then eggDef.displayName else tostring(result.eggType)
		)
	end
	if _revealNew then
		_revealNew.Visible = result.isNew
	end

	reveal.Visible = true

	_revealToken += 1
	local token = _revealToken
	task.delay(REVEAL_TIME, function()
		if token == _revealToken and _reveal then
			_reveal.Visible = false
		end
	end)
end

--------------------------------------------------------------------------------
-- Oeffnen / Schliessen
--------------------------------------------------------------------------------

local function openInternal(...: any)
	local root = _root
	if not root then return end

	root.Visible = true
	HatchPanel.refresh()
end

local function closeInternal()
	local root = _root
	if root then root.Visible = false end
end

--------------------------------------------------------------------------------
-- Aufbau
--------------------------------------------------------------------------------

local function buildReveal(screenGui: ScreenGui)
	local reveal = Theme.dialog(
		"HatchReveal", screenGui,
		Vector2.new(0.32, 0.30),
		Vector2.new(250, 180),
		Vector2.new(380, 260)
	)
	reveal.ZIndex = 30
	_reveal = reveal

	local newBadge = Theme.label("New", reveal, "NEU!")
	newBadge.Position       = UDim2.new(0, 0, 0, 12)
	newBadge.Size           = UDim2.new(1, 0, 0, 24)
	newBadge.TextXAlignment = Enum.TextXAlignment.Center
	newBadge.TextColor3     = Theme.COLORS.goldGummy
	newBadge.Visible        = false
	_revealNew = newBadge

	local title = Theme.label("Title", reveal, "")
	title.Position       = UDim2.new(0, 10, 0, 44)
	title.Size           = UDim2.new(1, -20, 0, 36)
	title.TextXAlignment = Enum.TextXAlignment.Center
	_revealTitle = title

	local sub = Theme.label("Sub", reveal, "")
	sub.Position       = UDim2.new(0, 10, 0, 86)
	sub.Size           = UDim2.new(1, -20, 0, 44)
	sub.TextXAlignment = Enum.TextXAlignment.Center
	sub.TextColor3     = Theme.COLORS.textDim
	sub.TextScaled     = false
	sub.TextSize       = 15
	sub.Font           = Theme.FONT_BODY
	_revealSub = sub
end

function HatchPanel.init(screenGui: ScreenGui)
	local root = Theme.dialog(
		"HatchPanel", screenGui,
		Vector2.new(0.52, 0.68),
		Vector2.new(320, 320),
		Vector2.new(560, 600)
	)
	_root = root

	Theme.dialogHeader(root, "Eier", function()
		PanelManager.close(PANEL_NAME)
	end)

	local body     = Theme.dialogBody(root)
	local scroller = Theme.scroller("List", body)
	scroller.Size = UDim2.fromScale(1, 1)
	_scroller = scroller

	local layout = Theme.listLayout(scroller, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left

	buildReveal(screenGui)

	PanelManager.register(PANEL_NAME, {
		open  = openInternal,
		close = closeInternal,
	})

	-- Neue Serverdaten: kompletter Neuaufbau (Slots und Preise koennen sich
	-- geaendert haben). Nur wenn sichtbar — sonst waere jede Kampfrunde ein
	-- Neuaufbau von einem Dutzend Karten.
	ClientState.onChanged(function()
		HatchPanel.refresh()
	end)

	-- Balken zwischen zwei Updates weiterlaufen lassen
	local accumulator = 0
	RunService.Heartbeat:Connect(function(delta: number)
		local current = _root
		if not current or not current.Visible then return end

		accumulator += delta
		if accumulator < TICK_SECONDS then return end
		accumulator = 0

		updateSlotValues()
	end)

	Remotes.HatchResultReceived.OnClientEvent:Connect(function(result: any)
		if typeof(result) ~= "table" then return end
		showReveal(result :: Types.HatchResult)
	end)

	print("[HatchPanel] Initialisiert")
end

return HatchPanel
