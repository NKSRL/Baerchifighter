--!strict
-- BaerchiInventory.luau
-- StarterPlayerScripts/UI/BaerchiInventory.luau
--
-- Einzige Zustaendigkeit:
--   - Alle Baerchis des Spielers als scrollbare Liste zeigen
--   - Die Zwei-Slot-Auswahl fuer die Fusion verwalten
--   - Die zwei Reiter: "Meine Baerchis" (diese Liste) und "Index" (IndexView)
--
-- Die Liste kommt fertig sortiert aus ClientState.getBaerchiList()
-- (Rarity absteigend, dann Level) — hier wird nichts nachsortiert.
--
-- Die Fusions-Auswahl ist der einzige Zustand den dieses Modul selbst haelt.
-- Das ist erlaubt: welche zwei Zeilen gerade markiert sind, ist eine reine
-- Bedien-Information und kein Spielstand — sie steht in keinem Save und der
-- Server erfaehrt davon erst beim Bestaetigen in FusionPanel.
--
-- Neu aufgebaut wird die Liste nur wenn das Panel sichtbar ist. Kommt ein
-- Update waehrend es zu ist, wird nur ein Merker gesetzt und beim naechsten
-- Oeffnen nachgeholt — sonst baut jede Kampfrunde 25 Zeilen neu.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types            = require(ReplicatedStorage.Network.Types)
local Remotes          = require(ReplicatedStorage.Network.Remotes)   -- 19.10.: Ausruesten-Knopf in der Zeile
local Loc              = require(ReplicatedStorage.Localization.Loc)
local Names            = require(ReplicatedStorage.Localization.Names)
local BaerchiConfig    = require(ReplicatedStorage.Config.BaerchiConfig)
local CombatCalculator = require(ReplicatedStorage.Modules.CombatCalculator)

local Theme        = require(script.Parent.Theme)
local PanelManager = require(script.Parent.PanelManager)
local EggPanelSkin = require(script.Parent.EggPanelSkin)   -- 13.10.: Honig-Template
local Icons        = require(script.Parent.Icons)          -- 14.10.: bear-bar.png
local ClientState  = require(script.Parent.Parent.Controllers.ClientState)
local Unlock       = require(script.Parent.Unlock)   -- HBB Paket 3
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)
local CombatRating = require(ReplicatedStorage.Modules.CombatRating)
-- 19.10. (PET_LIMIT_V1 / PET_SELL_MODE_V1): Lager-Zaehler und Verkaufsmodus
local PetCapacity    = require(ReplicatedStorage.Modules.PetCapacity)
local PetSellRules   = require(ReplicatedStorage.Modules.PetSellRules)
local PetLimitConfig = require(ReplicatedStorage.Config.PetLimitConfig)
local PetSellConfirm = require(script.Parent.PetSellConfirm)
local HoneyButton    = require(script.Parent.HoneyButton)
local Toast          = require(script.Parent.Toast)

-- HBB Paket 4: "⚔ 1,2K" statt HP/ATK in der Zeile
local function ratingText(baerchi: Types.Baerchi): string
	local value, suffix = CombatRating.short(CombatRating.of(baerchi))
	local digits = if suffix ~= "" and value < 100 then 1 else 0
	return "⚔ " .. (if digits > 0 then Loc.formatDecimal(value, digits) else Loc.formatNumber(math.floor(value))) .. suffix
end
local IndexView    = require(script.Parent.IndexView)

local BaerchiInventory = {}

local PANEL_NAME  = "Inventory"
local ROW_HEIGHT  = 48
local TOOLBAR_H   = 32
local FOOTER_H    = 64
local TAB_H       = 32

local _root: Frame?               = nil
local _title: TextLabel?          = nil
local _scroller: ScrollingFrame?  = nil
local _empty: TextLabel?          = nil
local _footer: Frame?             = nil
local _slotLabels: { TextLabel }  = {}
local _fuseButton: TextButton?    = nil
local _modeButton: TextButton?    = nil
local _hint: TextLabel?           = nil
local _listPage: Frame?           = nil
local _tabButtons: { [string]: TextButton } = {}
local _tab = "Pets"   -- "Pets" | "Index"

local _fusionMode = false
local _selection: { string } = {}
local _dirty = true

-- Verkaufsmodus (19.10.): reine Bedien-Information wie die Fusions-Auswahl,
-- nichts davon steht in einem Save. Verkauft wird erst nach dem Bestaetigen.
local _sellToggle: HoneyButton.Handle? = nil
local _sellClear:  HoneyButton.Handle? = nil
local _sellGo:     HoneyButton.Handle? = nil
local _sellBar: Frame?        = nil
local _counter: TextLabel?    = nil
local _sellMode  = false
local _sellSel: { [string]: boolean } = {}
local _sellCount = 0
local _sellPending = false   -- Anfrage beim Server unterwegs: keine Doppelklicks
local _rightW = 0            -- Platz rechts in der Werkzeugleiste (Zaehler + Umschalter)
local TOGGLE_W = 124         -- Honig-Standardknopf ~3,85:1 bei 32 Pixeln Hoehe
local COUNTER_W = 90
local SELL_BAR_H = 54       -- schlanker als die Fusionsleiste: auf kleinen Fenstern bleibt Platz fuer die Liste
local SELL_BTN_H = 40

--------------------------------------------------------------------------------
-- Auswahl
--------------------------------------------------------------------------------

local function isSelected(uid: string): boolean
	return table.find(_selection, uid) ~= nil
end

local function toggleSelection(uid: string)
	local index = table.find(_selection, uid)
	if index then
		table.remove(_selection, index)
		return
	end

	-- Sammel-Update 2.8: B muss dieselbe Rarity wie A haben (der Server
	-- lehnt sonst ab, err.fuse_rarity_mismatch). Die Liste zeigt ohnehin nur
	-- passende — das hier ist das Netz fuer einen Klick waehrend eines Umbaus.
	local first = if _selection[1] then ClientState.getBaerchi(_selection[1]) else nil
	local picked = ClientState.getBaerchi(uid)
	if first and picked and first.rarity ~= picked.rarity then
		return
	end

	-- Sammel-Update 1.3: ein weiterer Klick ersetzt B, nie A — A ist der
	-- Baerchi, von dessen Karte der Spieler kam.
	if #_selection >= 2 then
		table.remove(_selection, 2)
	end
	table.insert(_selection, uid)
end

-- Sammel-Update 2.8: im Fusions-Modus mit gewaehltem A nur Baerchis
-- derselben Rarity zeigen (A selbst bleibt sichtbar, zum Abwaehlen).
local function visibleInFusion(baerchi: Types.Baerchi): boolean
	if not _fusionMode or not _selection[1] then return true end
	if isSelected(baerchi.uid) then return true end
	local first = ClientState.getBaerchi(_selection[1])
	return first == nil or first.rarity == baerchi.rarity
end

-- Sammel-Update 1.3 ("kann keinen 2. auswaehlen"): die Zeilen wurden bei JEDEM
-- Datenstand (Honig, Eier, ... mehrmals pro Sekunde) zerstoert und neu
-- gebaut. Lag ein Tipp gerade dazwischen (Finger runter, Zeile weg, Finger
-- hoch), kam Activated nie an — auf dem Handy fast jedes Mal. Jetzt bleibt
-- die Zeile samt Knopf pro uid stehen, nur der Inhalt wird erneuert.
local _rows: { [string]: Frame } = {}

-- Markierungen wegwerfen die es nicht mehr gibt (verwertet, fusioniert, Rebirth)
local function pruneSelection()
	for i = #_selection, 1, -1 do
		if not ClientState.getBaerchi(_selection[i]) then
			table.remove(_selection, i)
		end
	end
end

--------------------------------------------------------------------------------
-- Aufbau der Liste
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- Verkaufsmodus (19.10.)
--------------------------------------------------------------------------------

local function sellModeAvailable(): boolean
	return FeatureFlags.isOn("PET_SELL_MODE_V1")
end

-- nil = verkaufbar, sonst Loc-Schluessel (gleiche Regeln wie der Server)
local function blockedReason(uid: string): string?
	local data = ClientState.get()
	if not data then return "err.sell_unknown" end
	return PetSellRules.blockReason(data, uid)
end

-- Markierung/Sperre direkt an der Zeile — kein Neuaufbau der Liste pro Klick.
local function applySellVisual(row: Frame, uid: string)
	local marked  = _sellMode and _sellSel[uid] == true
	local blocked = _sellMode and not marked and blockedReason(uid) ~= nil

	local mark = row:FindFirstChild("SellMark")
	if marked and not mark then
		local m = Instance.new("Frame")
		m.Name                   = "SellMark"
		m.BackgroundColor3       = Theme.COLORS.goldGummy
		m.BackgroundTransparency = 0.8
		m.BorderSizePixel        = 0
		m.Size                   = UDim2.fromScale(1, 1)
		m.ZIndex                 = 4
		m.Parent                 = row
		Theme.corner(m, 14)
		Theme.stroke(m, Theme.COLORS.goldGummy, 4)
		local tick = Instance.new("TextLabel")
		tick.Name                   = "Tick"
		tick.BackgroundTransparency = 1
		tick.AnchorPoint            = Vector2.new(1, 0.5)
		tick.Position               = UDim2.new(1, -118, 0.5, 0)
		tick.Size                   = UDim2.fromOffset(30, 30)
		tick.Text                   = "\u{2713}"
		tick.Font                   = Theme.FONT
		tick.TextSize               = 26
		tick.TextColor3             = Theme.COLORS.goldGummy
		tick.ZIndex                 = 5
		tick.Active                 = false
		tick.Parent                 = m
		Theme.outlineText(tick, 2)
	elseif not marked and mark then
		mark:Destroy()
	end

	local block = row:FindFirstChild("SellBlock")
	if blocked and not block then
		local b = Instance.new("Frame")
		b.Name                   = "SellBlock"
		b.BackgroundColor3       = Color3.new(0, 0, 0)
		b.BackgroundTransparency = 0.55
		b.BorderSizePixel        = 0
		b.Size                   = UDim2.fromScale(1, 1)
		b.ZIndex                 = 5
		b.Active                 = false
		b.Parent                 = row
		Theme.corner(b, 14)
	elseif not blocked and block then
		block:Destroy()
	end
end

local function applySellVisualAll()
	for uid, row in _rows do
		applySellVisual(row, uid)
	end
end

local function refreshSellBar()
	local n = _sellCount
	local go = _sellGo
	if go then
		go.setEnabled(n > 0 and not _sellPending)
		go.setText(Loc.tn("ui.pets.sell.sell_button", n, { n = n }))
	end
	local clear = _sellClear
	if clear then
		clear.setEnabled(n > 0 and not _sellPending)
	end
end

-- Zaehler, Umschalter und Verkaufsleiste an den aktuellen Stand anpassen.
local function syncSellUi()
	local data = ClientState.get()
	local limitOn = PetCapacity.isActive() and data ~= nil
	local toggleOn = sellModeAvailable() and not _fusionMode

	local toggle = _sellToggle
	if toggle then
		toggle.holder.Visible = toggleOn
		toggle.setActive(_sellMode)
		toggle.setText(Loc.t(if _sellMode then "ui.pets.sell.toggle_active" else "ui.pets.sell.toggle"))
	end

	local counter = _counter
	if counter then
		counter.Visible = limitOn
		counter.Position = UDim2.new(1, if toggleOn then -(TOGGLE_W + 6) else 0, 0.5, 0)
		if limitOn and data then
			local state = PetCapacity.state(data)
			counter.Text = Loc.t("ui.pets.limit.counter", {
				n   = Loc.formatNumber(PetCapacity.count(data)),
				max = Loc.formatNumber(PetCapacity.getPetLimit(data)),
			})
			counter.TextColor3 = if state == "full" or state == "over" then Theme.COLORS.bad
				elseif state == "warn" then Color3.fromRGB(255, 214, 64)
				else Theme.COLORS.text
		end
	end

	_rightW = (if limitOn then COUNTER_W + 6 else 0) + (if toggleOn then TOGGLE_W + 6 else 0)

	local bar = _sellBar
	if bar then bar.Visible = _sellMode end
	refreshSellBar()
end

local function toggleSell(uid: string)
	if _sellPending then return end
	if _sellSel[uid] then
		_sellSel[uid] = nil
		_sellCount -= 1
	else
		local reason = blockedReason(uid)
		if reason then
			Toast.info(Loc.msg(reason))
			return
		end
		if _sellCount >= PetLimitConfig.SELL_MAX_PER_REQUEST then
			Toast.info(Loc.msg("err.sell_too_many"))
			return
		end
		_sellSel[uid] = true
		_sellCount += 1
	end
	local row = _rows[uid]
	if row then applySellVisual(row, uid) end
	refreshSellBar()
end

-- Markierungen wegwerfen die es nicht mehr gibt oder nicht mehr verkaufbar sind
-- (inzwischen ausgeruestet, im Inkubator, verwertet, Rebirth)
local function pruneSell()
	if _sellCount == 0 then return end
	for uid in _sellSel do
		if not ClientState.getBaerchi(uid) or blockedReason(uid) ~= nil then
			_sellSel[uid] = nil
			_sellCount -= 1
		end
	end
end

local function setSellMode(on: boolean)
	if on == _sellMode then return end
	if on and not sellModeAvailable() then return end
	_sellMode = on
	table.clear(_sellSel)
	_sellCount = 0
	_sellPending = false
	if on then
		-- Fusion und Verkaufen schliessen sich aus
		_fusionMode = false
		table.clear(_selection)
	else
		PetSellConfirm.close()
	end
	applySellVisualAll()
	-- Eine Neuaufbau-Runde beim Moduswechsel (Ausruesten-Knoepfe weg/da), nie pro Klick
	BaerchiInventory.refresh()
end

local function startSell()
	if _sellPending or _sellCount <= 0 then return end
	local data = ClientState.get()
	if not data then return end

	local before = _sellCount
	pruneSell()
	if _sellCount ~= before then
		-- Die Auswahl hat sich unter den Haenden geaendert: neu zeigen, neu fragen
		applySellVisualAll()
		refreshSellBar()
		return
	end

	local uids: { string } = {}
	for uid in _sellSel do table.insert(uids, uid) end
	if #uids == 0 then return end

	PetSellConfirm.open({ count = #uids, rare = PetSellRules.countRare(data, uids) }, function()
		if _sellPending then return end
		for _, uid in uids do
			if not _sellSel[uid] or blockedReason(uid) ~= nil then
				refreshSellBar()
				Toast.info(Loc.msg("err.sell_invalid"))
				return
			end
		end
		_sellPending = true
		refreshSellBar()
		Remotes.RequestSellBaerchis:FireServer(uids)
		-- Netz: kommt nie eine Antwort (Rate-Limit, Verbindung), nicht fuer immer sperren
		task.delay(6, function()
			if _sellPending then
				_sellPending = false
				refreshSellBar()
			end
		end)
	end)
end

-- Zeigt die AKTUELLEN HP, nicht nur das Maximum: seit die HP zwischen
-- PIT-Laeufen stehen bleiben, ist "wer kann ueberhaupt noch kaempfen" die
-- eigentliche Frage beim Durchscrollen der Liste.
local function describeStats(baerchi: Types.Baerchi): string
	local def = BaerchiConfig.getById(baerchi.configId)
	if not def then return "" end

	local stats = CombatCalculator.getEffectiveStats(baerchi, def.baseStats)
	-- `or stats.maxHp`: ohne den Rueckfall wuerde ein Baerchi ohne currentHp
	-- (Datenpaket von einem aelteren Serverstand) hier den Aufbau der GANZEN
	-- Liste abbrechen, weil dieser Aufruf mitten in der Zeilen-Schleife steht.
	local hp    = math.clamp(baerchi.currentHp or stats.maxHp, 0, stats.maxHp)

	return string.format("HP %d/%d\nATK %d", hp, stats.maxHp, stats.atk)
end

-- 14.10. (UI_HONEY_SKIN): bear-bar.png ist die Zeile. Ausschnitt ohne durchsichtigen
-- Rand (2120 x 440 ab 30/105), links Platz fuer das Level, rechts fuer die Power.
local HONEY_BAR_H = 64
local function honeyBarOn(): boolean
	return FeatureFlags.isOn("UI_HONEY_SKIN") and Icons.hasUi("honey/bear_bar")
end

local function honeyText(name: string, parent: Instance, text: string, size: number): TextLabel
	local label = Theme.label(name, parent, text)
	label.TextScaled     = false
	label.TextSize       = size
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextTruncate   = Enum.TextTruncate.AtEnd
	label.ZIndex         = 4
	Theme.outlineText(label, 2)
	return label
end

local function buildRow(parent: Instance, order: number, baerchi: Types.Baerchi)
	local honey = honeyBarOn()
	local upgradeUi = FeatureFlags.isOn("UI_V2_UPGRADE_TAB")
	-- HBB Paket 4: Farbband statt zwoelf Einzelfarben
	local color = if upgradeUi then Theme.bandColor(baerchi.rarity) else Theme.rarityColor(baerchi.rarity)
	local def   = BaerchiConfig.getById(baerchi.configId)

	local data     = ClientState.get()
	local equipped = data ~= nil and data.island.equippedUid == baerchi.uid

	local uid = baerchi.uid
	local row = _rows[uid]
	local fresh = row == nil or row.Parent == nil
	if fresh then
		row = Theme.panel("Row_" .. uid, parent, Theme.COLORS.panel)
		row.Size = UDim2.new(1, -8, 0, if honey then HONEY_BAR_H else ROW_HEIGHT)
		_rows[uid] = row :: Frame

		if honey then
			-- altes Zeilen-Aussehen weg, Bild darunter
			row.BackgroundTransparency = 1
			for _, child in row:GetChildren() do
				if child:IsA("UIStroke") or child:IsA("UIGradient") or child:IsA("UICorner") then
					child:Destroy()
				elseif child:IsA("GuiObject") then
					child.Visible = false
				end
			end
			local skin = Icons.honeyImage(row, "honey/bear_bar", Rect.new(250, 47, 764, 160), HONEY_BAR_H / 207,
				Vector2.new(14, 50), Vector2.new(1000, 207))   -- Bild ist auf 1024 x 341 verkleinert
			if skin then skin.ZIndex = 1 end
		end

		-- Die ganze Zeile ist der Knopf: ein durchsichtiger Button darueber.
		-- Er bleibt ueber alle Aktualisierungen bestehen (siehe _rows).
		local hit = Instance.new("TextButton")
		hit.Name                   = "Hit"
		hit.BackgroundTransparency = 1
		hit.Text                   = ""
		hit.Size                   = UDim2.fromScale(1, 1)
		hit.ZIndex                 = 3
		hit.Parent                 = row

		hit.Activated:Connect(function()
			if _sellMode then
				toggleSell(uid)
			elseif _fusionMode then
				toggleSelection(uid)
				BaerchiInventory.refresh()
			else
				PanelManager.open("Baerchi", uid)
			end
		end)
	end
	local frame = row :: Frame
	frame.LayoutOrder = order
	frame.Visible     = visibleInFusion(baerchi)
	for _, child in frame:GetChildren() do
		if child.Name == "Accent" or child.Name == "Name" or child.Name == "Sub" or child.Name == "Stats"
			or child.Name == "Lv" or child.Name == "Mark" or child.Name == "EquipBtn" then
			child:Destroy()
		end
	end
	row = frame
	applySellVisual(frame, uid)

	if honey then
		local mutation = baerchi.mutation
		local marked = _fusionMode and isSelected(uid)
		if marked then
			local mark = Instance.new("Frame")
			mark.Name                   = "Mark"
			mark.BackgroundTransparency = 1
			mark.Size                   = UDim2.fromScale(1, 1)
			mark.ZIndex                 = 2
			mark.Parent                 = row
			Theme.corner(mark, 14)
			Theme.stroke(mark, Theme.COLORS.gummy, 4)
		end

		-- Level im linken Feld
		local lv = honeyText("Lv", row, "Lv\n" .. baerchi.level, 14)
		lv.Position       = UDim2.new(0, 13, 0, 17)
		lv.Size           = UDim2.fromOffset(58, 32)
		lv.TextXAlignment = Enum.TextXAlignment.Center
		lv.TextYAlignment = Enum.TextYAlignment.Center

		-- Name auf dem Balken (golden = ausgeruestet)
		local name = honeyText("Name", row,
			(if equipped then "\u{2605} " else "")
			.. (if mutation then BaerchiConfig.getMutationBadge(mutation) .. " " else "")
			.. Names.baerchi(baerchi.configId), 16)
		name.Position   = UDim2.new(0, 82, 0, 10)
		name.Size       = UDim2.new(1, -82 - 92 - 108, 0, 22)
		name.TextColor3 = if equipped then Theme.COLORS.goldGummy else Color3.new(1, 1, 1)

		-- Rarity (+ Mutation) in Rarity-Farbe
		local sub = honeyText("Sub", row, Loc.t("rarity." .. baerchi.rarity)
			.. (if mutation then "  —  " .. Loc.name("mutation." .. mutation .. ".name", BaerchiConfig.getMutationDisplayName(mutation)):upper() else ""), 12)
		sub.Position   = UDim2.new(0, 82, 0, 33)
		sub.Size       = UDim2.new(1, -82 - 92 - 108, 0, 18)
		sub.TextColor3 = if mutation then BaerchiConfig.getMutationColor(mutation) else color

		-- Power rechts ueber dem Wabenmuster
		local stats = honeyText("Stats", row, if upgradeUi then ratingText(baerchi) else describeStats(baerchi), 18)
		stats.AnchorPoint    = Vector2.new(1, 0.5)
		stats.Position       = UDim2.new(1, -16, 0, 32)
		stats.Size           = UDim2.fromOffset(84, 30)
		stats.TextXAlignment = Enum.TextXAlignment.Right

		-- 19.10.: Ausruesten-Knopf links neben der Kampfzahl (nicht beim ausgeruesteten Baerchi, nicht im Fusionsmodus)
		if not equipped and not _fusionMode and not _sellMode then
			local btn = Instance.new("TextButton")
			btn.Name                   = "EquipBtn"
			btn.AutoButtonColor        = false
			btn.BackgroundTransparency = 1
			btn.Text                   = ""
			btn.AnchorPoint            = Vector2.new(1, 0.5)
			btn.Position               = UDim2.new(1, -16 - 84 - 8, 0, 32)
			btn.Size                   = UDim2.fromOffset(104, 33)
			btn.ZIndex                 = 6
			btn.Parent                 = row
			local skinId = Icons.ui("honey/equip_btn")
			if skinId then
				local skin = Instance.new("ImageLabel")
				skin.Name                   = "Skin"
				skin.BackgroundTransparency = 1
				skin.Image                  = skinId
				skin.Size                   = UDim2.fromScale(1, 1)
				skin.ZIndex                 = 6
				skin.Active                 = false
				skin.Parent                 = btn
			else
				btn.BackgroundTransparency = 0
				btn.BackgroundColor3       = Theme.COLORS.accent
				Theme.corner(btn, 10)
			end
			local text = honeyText("EquipText", btn, Loc.t("ui.card.equip"), 13)
			text.Size           = UDim2.fromScale(1, 1)
			text.Position       = UDim2.fromScale(0, 0)
			text.TextXAlignment = Enum.TextXAlignment.Center
			text.TextYAlignment = Enum.TextYAlignment.Center
			text.ZIndex         = 7
			btn.Activated:Connect(function()
				Remotes.RequestEquipBaerchi:FireServer(uid)
			end)
		end
		return
	end

	-- Markierte Zeilen bekommen einen farbigen Rand statt eines eigenen Symbols
	local stroke = row:FindFirstChildOfClass("UIStroke")
	if stroke then
		local marked = _fusionMode and isSelected(uid)
		stroke.Color     = if marked then Theme.COLORS.gummy else Theme.COLORS.outline
		stroke.Thickness = if marked then Theme.OUTLINE_THICKNESS + 2 else Theme.OUTLINE_THICKNESS
	end

	local accent = Instance.new("Frame")
	accent.Name             = "Accent"
	accent.Size             = UDim2.new(0, 6, 1, -14)
	accent.Position         = UDim2.new(0, 8, 0, 7)
	-- Der ausgeruestete Baerchi (der einzige, der auf dem Plot steht und
	-- kaempfen/essen kann) hebt sich hier golden ab statt in Rarity-Farbe —
	-- das ist auf einen Blick wichtiger als die Rarity.
	accent.BackgroundColor3  = if equipped then Theme.COLORS.goldGummy else color
	accent.BorderSizePixel   = 0
	accent.Parent            = row
	Theme.corner(accent, 3)

	-- Eine Mutation ist in einer langen Liste die Information, die man auf
	-- keinen Fall uebersehen darf: die haeufigste Stufe trifft trotzdem nur
	-- 1 von 100 Baerchis. Deshalb hier gleich zweimal — als Kuerzel im Namen
	-- und als Farbe der Unterzeile (seit v11, ersetzt das binaere Inverted).
	local mutation = baerchi.mutation

	local name = Theme.label("Name", row,
		(if equipped then "\u{2605} " else "")
		.. (if mutation then BaerchiConfig.getMutationBadge(mutation) .. " " else "")
		.. Names.baerchi(baerchi.configId))
	name.Position = UDim2.new(0, 22, 0, 5)
	name.Size     = UDim2.new(1, -120, 0, 21)

	local sub = Theme.label("Sub", row, string.format(
		"Lv. %d  —  %s%s",
		baerchi.level,
		Loc.t("rarity." .. baerchi.rarity),
		if mutation then "  —  " .. Loc.name("mutation." .. mutation .. ".name", BaerchiConfig.getMutationDisplayName(mutation)):upper() else ""
	))
	sub.Position   = UDim2.new(0, 22, 0, 26)
	sub.Size       = UDim2.new(1, -120, 0, 16)
	sub.TextColor3 = if mutation then BaerchiConfig.getMutationColor(mutation) else color

	local stats = Theme.label("Stats", row, if upgradeUi then ratingText(baerchi) else describeStats(baerchi))
	stats.AnchorPoint    = Vector2.new(1, 0.5)
	stats.Position       = UDim2.new(1, -10, 0.5, 0)
	stats.Size           = UDim2.new(0, 84, 1, -10)
	stats.TextXAlignment = Enum.TextXAlignment.Right
	stats.TextScaled     = false
	stats.TextSize       = if upgradeUi then 20 else 13
	stats.Font           = if upgradeUi then Theme.FONT else Theme.FONT_BODY
	stats.TextColor3     = if upgradeUi then Theme.COLORS.text else Theme.COLORS.textDim
end

--------------------------------------------------------------------------------
-- Aktualisieren
--------------------------------------------------------------------------------

local function updateFooter()
	syncSellUi()
	local footer = _footer
	if footer then
		footer.Visible = _fusionMode
	end

	local scroller = _scroller
	if scroller then
		local reserved = if _fusionMode then FOOTER_H + 6 elseif _sellMode then SELL_BAR_H + 6 else 0
		scroller.Size = UDim2.new(1, 0, 1, -(TOOLBAR_H + 6 + reserved))
	end

	for slot = 1, 2 do
		local label = _slotLabels[slot]
		if not label then continue end

		local uid = _selection[slot]
		local baerchi = if uid then ClientState.getBaerchi(uid) else nil

		if baerchi then
			local def = BaerchiConfig.getById(baerchi.configId)
			label.Text       = string.format("%s  Lv.%d", Names.baerchi(baerchi.configId), baerchi.level)
			label.TextColor3  = Theme.rarityColor(baerchi.rarity)
		else
			label.Text       = Loc.t("ui.fusion.slot_empty", { n = slot })
			label.TextColor3  = Theme.COLORS.textDim
		end
	end

	local fuseButton = _fuseButton
	if fuseButton then
		Theme.setEnabled(fuseButton, #_selection == 2)
	end

	local modeButton = _modeButton
	if modeButton then
		if FeatureFlags.isOn("FUSION_INVENTORY_TOGGLE") then
			modeButton.Text = Loc.t(if _fusionMode then "ui.fusion.mode_on" else "ui.fusion.mode_off")
		else
			-- 12.10.: Fusion startet nur von der Baerchi-Karte; hier nur Abbrechen
			modeButton.Visible = _fusionMode
			modeButton.Text = Loc.t("ui.common.cancel")
		end
	end
	local hint = _hint
	if hint then
		local shifted = modeButton ~= nil and modeButton.Visible
		hint.Position = UDim2.new(0, if shifted then 140 else 0, 0, 0)
		hint.Size     = UDim2.new(1, (if shifted then -140 else 0) - _rightW, 1, 0)
	end

	local hint = _hint
	if hint then
		hint.Text = if _sellMode then Loc.t("ui.pets.sell.hint")
			elseif not _fusionMode
			then Loc.t("ui.inventory.hint_card")
			elseif _selection[1] then Loc.t("ui.fusion.hint_pick_b")
			else Loc.t("ui.fusion.hint_pick_a")
	end
end

function BaerchiInventory.refresh()
	local scroller = _scroller
	local root     = _root
	if not scroller or not root then return end

	if not root.Visible then
		_dirty = true
		return
	end
	_dirty = false

	pruneSelection()
	pruneSell()

	local list = ClientState.getBaerchiList()

	-- Sammel-Update 1.3: nur Zeilen entfernen, deren Baerchi es nicht mehr gibt.
	local alive: { [string]: boolean } = {}
	for _, baerchi in list do alive[baerchi.uid] = true end
	for uid, row in _rows do
		if not alive[uid] then
			row:Destroy()
			_rows[uid] = nil
		end
	end

	local title = _title
	if title then
		title.Text = Loc.t("ui.inventory.title_count", { n = #list })
	end

	local empty = _empty
	if empty then
		empty.Visible = #list == 0
	end

	for order, baerchi in list do
		buildRow(scroller, order, baerchi)
	end

	updateFooter()
end

--------------------------------------------------------------------------------
-- Oeffnen / Schliessen
--------------------------------------------------------------------------------

local function applyTab()
	-- HBB Paket 3: der Index-Reiter erscheint ab drei entdeckten Arten
	local indexTab = _tabButtons.Index
	if indexTab then
		Unlock.apply("index", indexTab)
		if not indexTab.Visible and _tab == "Index" then _tab = "Pets" end
	end

	-- 19.10.: Reiterwechsel beendet den Verkaufsmodus
	if _tab ~= "Pets" then setSellMode(false) end

	local listPage = _listPage
	if listPage then
		listPage.Visible = _tab == "Pets"
	end
	IndexView.setVisible(_tab == "Index" and _root ~= nil and _root.Visible)

	for tab, button in _tabButtons do
		local active = tab == _tab
		button.BackgroundColor3 = if active then Theme.COLORS.accent else Theme.COLORS.panelLight
		button.TextColor3       = if active then Theme.COLORS.outline else Theme.COLORS.text
	end

	-- Sammel-Update 05.10. (Paket 7): "!" am Index-Reiter, solange eine
	-- Belohnung abholbar ist.
	local indexButton = _tabButtons.Index
	if indexButton then
		local badge = indexButton:FindFirstChild("RewardBadge")
		if badge and badge:IsA("GuiObject") then
			badge.Visible = IndexView.claimableCount() > 0
		end
	end

	if _tab == "Pets" then
		BaerchiInventory.refresh()
	end
end

local function openInternal(...: any)
	local root = _root
	if not root then return end

	-- PanelManager.open("Inventory", "Index") springt direkt in den Index
	-- (zum Beispiel aus einer Quest heraus).
	local wanted, uid = ...
	if wanted == "Index" or wanted == "Pets" then
		_tab = wanted
	elseif wanted == "Fuse" then
		-- Playtest 05.10.: Fusion von der Baerchi-Karte aus. Das Fusions-
		-- Fenster selbst hat keine Auswahl; ausgewaehlt wird hier. A ist
		-- dieser Baerchi, B tippt der Spieler in der Liste an.
		_tab = "Pets"
		setSellMode(false)
		_fusionMode = true
		table.clear(_selection)
		if typeof(uid) == "string" then table.insert(_selection, uid) end
	end

	root.Visible = true
	applyTab()
end

local function closeInternal()
	local root = _root
	if root then root.Visible = false end
	setSellMode(false)   -- 19.10.: Menue zu = Verkaufsmodus aus, Dialog zu
	-- 12.10.: eine offene Fusions-Auswahl endet mit dem Fenster
	if not FeatureFlags.isOn("FUSION_INVENTORY_TOGGLE") then
		_fusionMode = false
		table.clear(_selection)
	end
	IndexView.setVisible(false)
end

function BaerchiInventory.show()
	PanelManager.open(PANEL_NAME)
end

--------------------------------------------------------------------------------
-- Aufbau
--------------------------------------------------------------------------------

function BaerchiInventory.init(screenGui: ScreenGui)
	local root = Theme.dialog(
		"BaerchiInventory", screenGui,
		Vector2.new(0.46, 0.66),
		Vector2.new(300, 300),
		Vector2.new(520, 580)
	)
	_root  = root
	_title = Theme.dialogHeader(root, Loc.t("ui.menu.baerchis"), function()
		PanelManager.close(PANEL_NAME)
	end)

	local body = Theme.dialogBody(root)

	-- Reiter-Leiste: "Meine Baerchis" | "Index"
	local tabBar = Theme.container("Tabs", body)
	tabBar.Size = UDim2.new(1, 0, 0, TAB_H)
	local tabLayout = Theme.listLayout(tabBar, 8, true)
	tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left

	local function addTab(tab: string, key: string, order: number)
		local button = Theme.button("Tab_" .. tab, tabBar, "", Theme.COLORS.panelLight)
		button.Size        = UDim2.new(0, 150, 1, 0)
		button.LayoutOrder = order
		Loc.bind(button, key)
		button.Activated:Connect(function()
			if tab == "Index" then Unlock.markSeen("index") end
			_tab = tab
			applyTab()
		end)
		_tabButtons[tab] = button
	end
	addTab("Pets",  "ui.inventory.tab_pets",  1)
	addTab("Index", "ui.inventory.tab_index", 2)
	do
		local indexButton = _tabButtons.Index
		local badge = Theme.panel("RewardBadge", indexButton, Theme.COLORS.bad)
		badge.AnchorPoint = Vector2.new(1, 0)
		badge.Position = UDim2.new(1, 4, 0, -6)
		badge.Size = UDim2.fromOffset(20, 20)
		badge.ZIndex = 4
		badge.Visible = false
		Theme.corner(badge, 10)
		local bang = Theme.label("Bang", badge, "!")
		bang.Size = UDim2.fromScale(1, 1)
		bang.TextXAlignment = Enum.TextXAlignment.Center
		bang.ZIndex = 5
	end

	-- Beide Seiten teilen sich die Flaeche unter den Reitern.
	local pages = Theme.container("Pages", body)
	pages.Position = UDim2.new(0, 0, 0, TAB_H + 8)
	pages.Size     = UDim2.new(1, 0, 1, -(TAB_H + 8))

	local listPage = Theme.container("ListPage", pages)
	listPage.Size = UDim2.fromScale(1, 1)
	_listPage = listPage

	IndexView.build(pages, root)

	-- Werkzeugleiste: Fusions-Modus an/aus
	local toolbar = Theme.container("Toolbar", listPage)
	toolbar.Size = UDim2.new(1, 0, 0, TOOLBAR_H)

	local modeButton = Theme.button("FusionMode", toolbar, Loc.t("ui.fusion.mode_off"), Theme.COLORS.gummy)
	modeButton.Size = UDim2.new(0, 130, 1, 0)
	_modeButton = modeButton

	local hint = Theme.bodyText("Hint", toolbar, Loc.t("ui.inventory.hint_card"))
	_hint = hint
	hint.Position       = UDim2.new(0, 140, 0, 0)
	hint.Size           = UDim2.new(1, -140, 1, 0)
	hint.TextYAlignment = Enum.TextYAlignment.Center

	modeButton.Activated:Connect(function()
		setSellMode(false)
		_fusionMode = not _fusionMode
		if not _fusionMode then
			table.clear(_selection)
		end
		BaerchiInventory.refresh()
	end)

	-- 19.10.: Lager-Zaehler + Verkaufen-Umschalter rechts in der Werkzeugleiste
	local counter = Theme.label("PetCounter", toolbar, "")
	counter.AnchorPoint    = Vector2.new(1, 0.5)
	counter.Size           = UDim2.fromOffset(COUNTER_W, TOOLBAR_H)
	counter.TextXAlignment = Enum.TextXAlignment.Right
	counter.Visible        = false
	counter.ZIndex         = 3
	_counter = counter

	local toggle = HoneyButton.make(toolbar, "SellToggle", Loc.t("ui.pets.sell.toggle"), "dark", Theme.COLORS.panelLight)
	toggle.holder.AnchorPoint = Vector2.new(1, 0.5)
	toggle.holder.Position    = UDim2.new(1, 0, 0.5, 0)
	toggle.holder.Size        = UDim2.fromOffset(TOGGLE_W, TOOLBAR_H)
	toggle.holder.Visible     = false
	_sellToggle = toggle
	toggle.button.Activated:Connect(function()
		if _sellPending then return end
		setSellMode(not _sellMode)
	end)

	-- Liste
	local scroller = Theme.scroller("List", listPage)
	scroller.Position = UDim2.new(0, 0, 0, TOOLBAR_H + 6)
	scroller.Size     = UDim2.new(1, 0, 1, -(TOOLBAR_H + 6))
	_scroller = scroller

	local layout = Theme.listLayout(scroller, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left

	local empty = Theme.bodyText("Empty", listPage, Loc.t("ui.inventory.empty"))
	empty.Position = UDim2.new(0, 4, 0, TOOLBAR_H + 16)
	empty.Size     = UDim2.new(1, -8, 0, 40)
	empty.Visible  = false
	_empty = empty

	-- Fussleiste fuer die Fusions-Auswahl
	local footer = Theme.panel("FusionFooter", listPage, Theme.COLORS.panel)
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position    = UDim2.new(0, 0, 1, 0)
	footer.Size        = UDim2.new(1, -8, 0, FOOTER_H)
	footer.Visible     = false
	_footer = footer

	for slot = 1, 2 do
		local label = Theme.label("Slot" .. slot, footer, Loc.t("ui.fusion.slot_empty", { n = slot }))
		label.Position   = UDim2.new(0, 10, 0, 6 + (slot - 1) * 22)
		label.Size       = UDim2.new(1, -140, 0, 20)
		label.TextColor3  = Theme.COLORS.textDim
		_slotLabels[slot] = label
	end

	local fuseButton = Theme.button("Fuse", footer, Loc.t("ui.fusion.fuse"), Theme.COLORS.gummy)
	fuseButton.AnchorPoint = Vector2.new(1, 0.5)
	fuseButton.Position    = UDim2.new(1, -10, 0.5, 0)
	fuseButton.Size        = UDim2.new(0, 116, 0, 34)
	_fuseButton = fuseButton

	fuseButton.Activated:Connect(function()
		if #_selection < 2 then return end
		PanelManager.open("Fusion", _selection[1], _selection[2])
	end)

	-- 19.10.: Verkaufsleiste unten (wie die Fusionsleiste, nur im Verkaufsmodus)
	local sellBar = Theme.panel("SellBar", listPage, Theme.COLORS.panel)
	sellBar.AnchorPoint = Vector2.new(0, 1)
	sellBar.Position    = UDim2.new(0, 0, 1, 0)
	sellBar.Size        = UDim2.new(1, -8, 0, SELL_BAR_H)
	sellBar.Visible     = false
	_sellBar = sellBar

	local clear = HoneyButton.make(sellBar, "SellClear", Loc.t("ui.pets.sell.clear_all"), "light", Theme.COLORS.panelLight)
	clear.holder.AnchorPoint = Vector2.new(0, 0.5)
	clear.holder.Position    = UDim2.new(0, 8, 0.5, 0)
	clear.holder.Size        = UDim2.new(0.38, -12, 0, SELL_BTN_H)
	_sellClear = clear
	clear.button.Activated:Connect(function()
		if _sellPending then return end
		table.clear(_sellSel)
		_sellCount = 0
		applySellVisualAll()
		refreshSellBar()
	end)

	local go = HoneyButton.make(sellBar, "SellGo", "", "dark", Theme.COLORS.bad)
	go.holder.AnchorPoint = Vector2.new(1, 0.5)
	go.holder.Position    = UDim2.new(1, -8, 0.5, 0)
	go.holder.Size        = UDim2.new(0.62, -12, 0, SELL_BTN_H)
	_sellGo = go
	go.button.Activated:Connect(startSell)

	PetSellConfirm.init(screenGui)

	-- 13.10. (UI-Templates 2): Menue im Honig-Template. Das alte root bleibt
	-- fuer PanelManager und Layout zustaendig (EggPanelSkin.adopt).
	if EggPanelSkin.isReady("bears") then
		local TAB_PANELS = { eggs = "Hatch", star = "EggTree", crown = "Leaderboard" }
		EggPanelSkin.adopt(screenGui, root, body, {
			variant = "bears",
			onTab = function(tab: string)
				local target = TAB_PANELS[tab]
				if target then PanelManager.open(target) end
			end,
			onClose = function()
				PanelManager.close(PANEL_NAME)
			end,
		})
	end

	PanelManager.register(PANEL_NAME, {
		open  = openInternal,
		close = closeInternal,
	})

	-- 19.10.: Antwort des Servers auf RequestSellBaerchis (einmalige Verbindungen, kein Leck)
	Remotes.SellResultReceived.OnClientEvent:Connect(function(result: any)
		_sellPending = false
		local sold = if type(result) == "table" and type(result.sold) == "number" then result.sold else 0
		setSellMode(false)
		if sold > 0 then
			Toast.success(Loc.tn("ui.pets.sell.done", sold, { n = sold }))
		end
	end)
	Remotes.ActionFailed.OnClientEvent:Connect(function(action: any)
		if action == "RequestSellBaerchis" and _sellPending then
			_sellPending = false
			PetSellConfirm.close()
			pruneSell()
			applySellVisualAll()
			refreshSellBar()
		end
	end)

	-- Bestandsaenderungen: sichtbar sofort nachziehen, sonst nur merken
	ClientState.onChanged(function()
		local current = _root
		local indexButton = _tabButtons.Index
		local badge = if indexButton then indexButton:FindFirstChild("RewardBadge") else nil
		if badge and badge:IsA("GuiObject") then
			badge.Visible = IndexView.claimableCount() > 0
		end
		if current and current.Visible then
			BaerchiInventory.refresh()
		else
			_dirty = true
		end
	end)

	-- Sprachwechsel: Zeilen, Titel und Fusions-Leiste neu beschriften
	Loc.onChanged(function()
		_dirty = true
		BaerchiInventory.refresh()
	end)

	print("[BaerchiInventory] Initialisiert")
end

return BaerchiInventory
