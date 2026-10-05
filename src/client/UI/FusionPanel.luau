--!strict
-- FusionPanel.luau
-- StarterPlayerScripts/UI/FusionPanel.luau
--
-- Einzige Zustaendigkeit:
--   - Zwei im Inventar markierte Baerchis bestaetigen und fusionieren
--   - Den Sperr-Schritt anbieten (Ability / Level / Eier von A oder B)
--   - Das Ergebnis kurz zeigen
--
-- Die Auswahl der beiden Baerchis passiert im Inventar (BaerchiInventory,
-- Fusions-Modus). Dieses Panel bekommt die beiden uids beim Oeffnen uebergeben
-- und haelt selbst nur noch die Sperr-Entscheidung.
--
-- ============================================================
-- DREI ANSICHTEN, WEIL DIE FUSION SEIT v8 EINE ENTSCHEIDUNG IST
-- ============================================================
--   1. Auswahl  — was kommt rein, was kommt heraus (Vorschau)
--   2. Sperren  — genau EINE von drei Eigenschaften festlegen
--   3. Ergebnis — was tatsaechlich herausgekommen ist
--
-- Der Sperr-Schritt liegt DAZWISCHEN und nicht in der Auswahl, weil er nur
-- Sinn hat, wenn beide Baerchis feststehen: erst dann gibt es zwei Werte zum
-- Vergleichen. Wer nichts sperren will, klickt einfach durch — "automatisch"
-- ist ueberall der Ausgangszustand.
--
-- ============================================================
-- ZUR VORSCHAU
-- ============================================================
-- Die Fusions-Regel steht verbindlich im Kopf von FusionService. Hier wird sie
-- NUR nachgelesen, um zu zeigen was herauskommt. Seit v14 steigt die Rarity
-- NICHT mehr: das Ergebnis ist die Art des levelhoeheren Baerchis (bei
-- Gleichstand A) in derselben Rarity, mit den besseren Stats beider.
--
-- Abgelehnt wird trotzdem serverseitig: die Vorschau kann veraltet sein.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types           = require(ReplicatedStorage.Network.Types)
local Remotes         = require(ReplicatedStorage.Network.Remotes)
local BaerchiConfig   = require(ReplicatedStorage.Config.BaerchiConfig)
local EconomyConfig   = require(ReplicatedStorage.Config.EconomyConfig)
local PromotionConfig = require(ReplicatedStorage.Config.PromotionConfig)
local SkillConfig     = require(ReplicatedStorage.Config.SkillConfig)

local Theme        = require(script.Parent.Theme)
local Toast        = require(script.Parent.Toast)
-- HBB Paket 1: Meldungen nach FeedbackConfig verteilen (Icon/Moment/Toast)
local Notify       = require(script.Parent.Notify)
local PanelManager = require(script.Parent.PanelManager)
local ClientState  = require(script.Parent.Parent.Controllers.ClientState)

local FusionPanel = {}

local PANEL_NAME = "Fusion"

local _root: Frame?             = nil
local _selectView: Frame?       = nil
local _lockView: Frame?         = nil
local _resultView: Frame?       = nil
local _slotLabels: { TextLabel } = {}
local _previewLabel: TextLabel? = nil
local _detailLabel: TextLabel?  = nil
local _nextButton: TextButton?  = nil
local _resultTitle: TextLabel?  = nil
local _resultSub: TextLabel?    = nil

local _uidA: string? = nil
local _uidB: string? = nil

-- Die Sperr-Entscheidung. Beide zusammen oder beide nil — der Server
-- verwirft eine halbe Auswahl ohnehin (siehe FusionService.init).
local _lockedProperty: string? = nil
local _lockedFrom: string?     = nil

--------------------------------------------------------------------------------
-- Die drei sperrbaren Eigenschaften
--------------------------------------------------------------------------------

-- `read` liefert den ANZEIGETEXT dieser Eigenschaft fuer einen Baerchi.
-- Was der Server daraus macht, steht in FusionService — hier wird nur gezeigt,
-- worueber man entscheidet.
type LockDef = {
	id    : string,
	label : string,
	read  : (Types.Baerchi) -> string,
}

local LOCK_DEFS: { LockDef } = {
	{
		id    = "ability",
		label = "Ability",
		read  = function(baerchi: Types.Baerchi): string
			local skill = SkillConfig.getById(baerchi.skillId)
			return if skill then skill.displayName else baerchi.skillId
		end,
	},
	{
		id    = "level",
		label = "Level",
		read  = function(baerchi: Types.Baerchi): string
			return "Lv. " .. baerchi.level
		end,
	},
	{
		id    = "eggs",
		label = "Eier",
		read  = function(baerchi: Types.Baerchi): string
			local levels = baerchi.statLevels
			local value  = if levels then (levels.egg or 0) else 0
			return string.format("Stufe %d", value)
		end,
	},
}

type LockRow = {
	def     : LockDef,
	valueA  : TextLabel,
	valueB  : TextLabel,
	buttons : { [string]: TextButton },   -- "auto" | "A" | "B"
}

local _lockRows: { LockRow } = {}

--------------------------------------------------------------------------------
-- Vorschau
--------------------------------------------------------------------------------

type Preview = {
	ok      : boolean,
	headline: string,
	detail  : string,
}

local function buildPreview(a: Types.Baerchi?, b: Types.Baerchi?): Preview
	local data = ClientState.get()
	if not data or not a or not b then
		return { ok = false, headline = "Zwei Baerchis auswaehlen", detail = "" }
	end

	if a.uid == b.uid then
		return { ok = false, headline = "Zwei verschiedene Baerchis noetig", detail = "" }
	end

	if a.rarity ~= b.rarity then
		return {
			ok = false,
			headline = "Rarity passt nicht",
			detail   = "Beide Baerchis muessen dieselbe Rarity haben (" .. a.rarity .. " / " .. b.rarity .. ").",
		}
	end

	-- Seit v8: das HOEHERE Level, nicht mehr der Durchschnitt (siehe
	-- FusionService, Regel C).
	local resultLevel = math.clamp(math.max(a.level, b.level), 1, BaerchiConfig.MAX_LEVEL)
	local bonus       = EconomyConfig.getFusionStatBonus()

	-- v14: keine hoehere Rarity mehr — die Art des levelhoeheren Inputs.
	local keep = if b.level > a.level then b else a
	local keepDef = BaerchiConfig.getById(keep.configId)
	local headline = string.format("%s  (%s)", keepDef and keepDef.displayName or keep.configId, keep.rarity)

	local detail = string.format(
		"Level %d  —  Stat-Bonus +%d%%\nDie Rarity bleibt gleich. Basiswerte und Stat-Stufen: pro Stat der bessere der beiden.\nPromotion und Charms fangen bei Null an.",
		resultLevel,
		math.floor(bonus * 100 + 0.5)
	)

	return { ok = true, headline = headline, detail = detail }
end

--------------------------------------------------------------------------------
-- Anzeige
--------------------------------------------------------------------------------

local function describe(baerchi: Types.Baerchi?): (string, Color3)
	if not baerchi then
		return "leer", Theme.COLORS.textDim
	end

	local def = BaerchiConfig.getById(baerchi.configId)
	return string.format(
		"%s  —  %s  —  Lv. %d",
		def and def.displayName or baerchi.configId,
		baerchi.rarity,
		baerchi.level
	), Theme.rarityColor(baerchi.rarity)
end

local function refreshLockRows(a: Types.Baerchi?, b: Types.Baerchi?)
	for _, lockRow in _lockRows do
		lockRow.valueA.Text = if a then lockRow.def.read(a) else "—"
		lockRow.valueB.Text = if b then lockRow.def.read(b) else "—"

		local isLocked = _lockedProperty == lockRow.def.id

		for choice, button in lockRow.buttons do
			local active =
				(choice == "auto" and not isLocked)
				or (isLocked and choice == _lockedFrom)

			-- Aktive Wahl faerbig, die anderen matt. Bewusst ueber die
			-- Hintergrundfarbe und nicht ueber setEnabled: alle drei bleiben
			-- klickbar, sonst koennte man eine Sperre nicht mehr aufheben.
			button.BackgroundColor3 = if active
				then Theme.COLORS.accent
				else Theme.COLORS.panelLight
			button.TextColor3 = if active then Theme.COLORS.outline else Theme.COLORS.text
		end
	end
end

function FusionPanel.refresh()
	local root = _root
	if not root or not root.Visible then return end

	local a = if _uidA then ClientState.getBaerchi(_uidA) else nil
	local b = if _uidB then ClientState.getBaerchi(_uidB) else nil

	local labelA, colorA = describe(a)
	local labelB, colorB = describe(b)

	if _slotLabels[1] then
		_slotLabels[1].Text      = "A:  " .. labelA
		_slotLabels[1].TextColor3 = colorA
	end
	if _slotLabels[2] then
		_slotLabels[2].Text      = "B:  " .. labelB
		_slotLabels[2].TextColor3 = colorB
	end

	local preview = buildPreview(a, b)

	if _previewLabel then
		_previewLabel.Text       = preview.headline
		_previewLabel.TextColor3 = if preview.ok then Theme.COLORS.text else Theme.COLORS.bad
	end
	if _detailLabel then
		_detailLabel.Text = preview.detail
	end
	if _nextButton then
		Theme.setEnabled(_nextButton, preview.ok)
	end

	refreshLockRows(a, b)
end

--------------------------------------------------------------------------------
-- Oeffnen / Schliessen
--------------------------------------------------------------------------------

local function showView(which: "select" | "lock" | "result")
	if _selectView then _selectView.Visible = which == "select" end
	if _lockView   then _lockView.Visible   = which == "lock"   end
	if _resultView then _resultView.Visible = which == "result" end
end

local function openInternal(...: any)
	local root = _root
	if not root then return end

	local argA, argB = ...

	_uidA = nil
	_uidB = nil
	if typeof(argA) == "string" then _uidA = argA :: string end
	if typeof(argB) == "string" then _uidB = argB :: string end

	-- Jede neue Fusion startet ohne Sperre: eine Auswahl von der letzten
	-- Fusion stillschweigend zu uebernehmen waere die Art Ueberraschung, bei
	-- der hinterher niemand weiss, warum das Ergebnis so aussieht.
	_lockedProperty = nil
	_lockedFrom     = nil

	showView("select")
	root.Visible = true
	FusionPanel.refresh()
end

local function closeInternal()
	local root = _root
	if root then root.Visible = false end
end

--------------------------------------------------------------------------------
-- Ergebnis
--------------------------------------------------------------------------------

local function showResult(result: Types.FusionResult)
	local baerchi = result.resultBaerchi
	local def     = BaerchiConfig.getById(baerchi.configId)
	local name    = def and def.displayName or baerchi.configId

	Notify.emit("fusion_result", function()
		Toast.success(string.format("Fusion: %s (%s) Lv. %d", name, baerchi.rarity, baerchi.level))
	end)

	local root = _root
	if not root or not root.Visible then return end

	if _resultTitle then
		_resultTitle.Text       = name
		_resultTitle.TextColor3 = Theme.rarityColor(baerchi.rarity)
	end
	if _resultSub then
		local levels = baerchi.statLevels
		local cap    = PromotionConfig.getStatCap(baerchi.rarity)

		_resultSub.Text = string.format(
			"%s  —  Level %d\nStat-Bonus +%d%%\nStat-Stufen: HP %d  ATK %d  SPD %d  DEF %d  (max %d)",
			baerchi.rarity,
			baerchi.level,
			math.floor((baerchi.fusionBonus or 0) * 100 + 0.5),
			if levels then levels.hp  else 0,
			if levels then levels.atk else 0,
			if levels then levels.spd else 0,
			if levels then levels.def else 0,
			cap
		)
	end

	showView("result")
end

--------------------------------------------------------------------------------
-- Aufbau
--------------------------------------------------------------------------------

function FusionPanel.init(screenGui: ScreenGui)
	local root = Theme.dialog(
		"FusionPanel", screenGui,
		Vector2.new(0.48, 0.56),
		Vector2.new(320, 320),
		Vector2.new(540, 460)
	)
	_root = root

	Theme.dialogHeader(root, "Fusion", function()
		PanelManager.close(PANEL_NAME)
	end)

	local body = Theme.dialogBody(root)

	-- ------------------------------------------------------- Auswahl-Ansicht
	local selectView = Theme.container("SelectView", body)
	selectView.Size = UDim2.fromScale(1, 1)
	_selectView = selectView

	for slot = 1, 2 do
		local label = Theme.label("Slot" .. slot, selectView, "")
		label.Position   = UDim2.new(0, 4, 0, (slot - 1) * 26)
		label.Size       = UDim2.new(1, -8, 0, 22)
		label.TextColor3  = Theme.COLORS.textDim
		_slotLabels[slot] = label
	end

	local arrow = Theme.label("Arrow", selectView, "wird zu")
	arrow.Position       = UDim2.new(0, 4, 0, 58)
	arrow.Size           = UDim2.new(1, -8, 0, 18)
	arrow.TextXAlignment = Enum.TextXAlignment.Center
	arrow.TextColor3     = Theme.COLORS.textDim

	local previewBox = Theme.panel("Preview", selectView, Theme.COLORS.panel)
	previewBox.Position = UDim2.new(0, 0, 0, 80)
	previewBox.Size     = UDim2.new(1, -8, 0, 106)

	local preview = Theme.label("Headline", previewBox, "")
	preview.Position       = UDim2.new(0, 10, 0, 8)
	preview.Size           = UDim2.new(1, -20, 0, 26)
	preview.TextXAlignment = Enum.TextXAlignment.Center
	_previewLabel = preview

	local detail = Theme.bodyText("Detail", previewBox, "")
	detail.Position       = UDim2.new(0, 10, 0, 36)
	detail.Size           = UDim2.new(1, -20, 0, 62)
	detail.TextXAlignment = Enum.TextXAlignment.Center
	_detailLabel = detail

	local back = Theme.button("Back", selectView, "Zurueck", Theme.COLORS.panelLight)
	back.AnchorPoint = Vector2.new(0, 1)
	back.Position    = UDim2.new(0, 0, 1, 0)
	back.Size        = UDim2.new(0.5, -6, 0, 36)
	back.TextColor3  = Theme.COLORS.text
	back.Activated:Connect(function()
		PanelManager.open("Inventory")
	end)

	local next_ = Theme.button("Next", selectView, "Weiter", Theme.COLORS.gummy)
	next_.AnchorPoint = Vector2.new(1, 1)
	next_.Position    = UDim2.new(1, -8, 1, 0)
	next_.Size        = UDim2.new(0.5, -6, 0, 36)
	_nextButton = next_
	next_.Activated:Connect(function()
		showView("lock")
		FusionPanel.refresh()
	end)

	-- -------------------------------------------------------- Sperr-Ansicht
	local lockView = Theme.container("LockView", body)
	lockView.Size    = UDim2.fromScale(1, 1)
	lockView.Visible = false
	_lockView = lockView

	local lockHint = Theme.bodyText("LockHint", lockView,
		"Genau EINE Eigenschaft darf von einem bestimmten Baerchi kommen — auch die schlechtere. "
		.. "Alles auf 'auto' nimmt jeweils das Bessere.")
	lockHint.Position = UDim2.new(0, 4, 0, 0)
	lockHint.Size     = UDim2.new(1, -8, 0, 40)

	for index, def in LOCK_DEFS do
		local y = 44 + (index - 1) * 52

		local rowFrame = Theme.panel("Lock_" .. def.id, lockView, Theme.COLORS.panel)
		rowFrame.Position = UDim2.new(0, 0, 0, y)
		rowFrame.Size     = UDim2.new(1, -8, 0, 46)

		local name = Theme.label("Name", rowFrame, def.label)
		name.Position   = UDim2.new(0, 10, 0, 2)
		name.Size       = UDim2.new(0, 70, 0, 20)
		name.TextScaled = false
		name.TextSize   = 15

		local valueA = Theme.label("ValueA", rowFrame, "—")
		valueA.Position   = UDim2.new(0, 10, 0, 22)
		valueA.Size       = UDim2.new(0, 110, 0, 18)
		valueA.TextScaled = false
		valueA.TextSize   = 12
		valueA.TextColor3 = Theme.COLORS.textDim

		local valueB = Theme.label("ValueB", rowFrame, "—")
		valueB.Position   = UDim2.new(0, 124, 0, 22)
		valueB.Size       = UDim2.new(0, 110, 0, 18)
		valueB.TextScaled = false
		valueB.TextSize   = 12
		valueB.TextColor3 = Theme.COLORS.textDim

		local buttons: { [string]: TextButton } = {}

		local choices = { "auto", "A", "B" }
		for order, choice in choices do
			local button = Theme.button("Choice_" .. choice, rowFrame, choice, Theme.COLORS.panelLight)
			button.AnchorPoint = Vector2.new(1, 0.5)
			button.Position    = UDim2.new(1, -8 - (3 - order) * 46, 0.5, 0)
			button.Size        = UDim2.new(0, 42, 0, 28)
			button.TextColor3  = Theme.COLORS.text

			button.Activated:Connect(function()
				if choice == "auto" then
					-- Nur die Sperre DIESER Zeile aufheben; eine Sperre in einer
					-- anderen Zeile bleibt bestehen.
					if _lockedProperty == def.id then
						_lockedProperty = nil
						_lockedFrom     = nil
					end
				else
					-- Es darf immer nur EINE Eigenschaft gesperrt sein: eine
					-- neue Wahl ersetzt deshalb die alte, statt sich dazu zu
					-- gesellen.
					_lockedProperty = def.id
					_lockedFrom     = choice
				end

				FusionPanel.refresh()
			end)

			buttons[choice] = button
		end

		table.insert(_lockRows, {
			def     = def,
			valueA  = valueA,
			valueB  = valueB,
			buttons = buttons,
		})
	end

	local lockBack = Theme.button("LockBack", lockView, "Zurueck", Theme.COLORS.panelLight)
	lockBack.AnchorPoint = Vector2.new(0, 1)
	lockBack.Position    = UDim2.new(0, 0, 1, 0)
	lockBack.Size        = UDim2.new(0.5, -6, 0, 36)
	lockBack.TextColor3  = Theme.COLORS.text
	lockBack.Activated:Connect(function()
		showView("select")
		FusionPanel.refresh()
	end)

	local confirm = Theme.button("Confirm", lockView, "Fusionieren", Theme.COLORS.gummy)
	confirm.AnchorPoint = Vector2.new(1, 1)
	confirm.Position    = UDim2.new(1, -8, 1, 0)
	confirm.Size        = UDim2.new(0.5, -6, 0, 36)
	confirm.Activated:Connect(function()
		local a, b = _uidA, _uidB
		if not a or not b then return end
		Remotes.RequestFuseBaerchis:FireServer(a, b, _lockedProperty, _lockedFrom)
	end)

	-- ------------------------------------------------------ Ergebnis-Ansicht
	local resultView = Theme.container("ResultView", body)
	resultView.Size    = UDim2.fromScale(1, 1)
	resultView.Visible = false
	_resultView = resultView

	local resultHint = Theme.label("Hint", resultView, "Fusion geglueckt")
	resultHint.Position       = UDim2.new(0, 4, 0, 6)
	resultHint.Size           = UDim2.new(1, -8, 0, 22)
	resultHint.TextXAlignment = Enum.TextXAlignment.Center
	resultHint.TextColor3     = Theme.COLORS.good

	local resultTitle = Theme.label("Title", resultView, "")
	resultTitle.Position       = UDim2.new(0, 4, 0, 40)
	resultTitle.Size           = UDim2.new(1, -8, 0, 34)
	resultTitle.TextXAlignment = Enum.TextXAlignment.Center
	_resultTitle = resultTitle

	local resultSub = Theme.bodyText("Sub", resultView, "")
	resultSub.Position       = UDim2.new(0, 4, 0, 80)
	resultSub.Size           = UDim2.new(1, -8, 0, 76)
	resultSub.TextXAlignment = Enum.TextXAlignment.Center
	_resultSub = resultSub

	local done = Theme.button("Done", resultView, "Zum Inventar", Theme.COLORS.accent)
	done.AnchorPoint = Vector2.new(0.5, 1)
	done.Position    = UDim2.new(0.5, -4, 1, 0)
	done.Size        = UDim2.new(1, -8, 0, 36)
	done.Activated:Connect(function()
		PanelManager.open("Inventory")
	end)

	PanelManager.register(PANEL_NAME, {
		open  = openInternal,
		close = closeInternal,
	})

	ClientState.onChanged(function()
		FusionPanel.refresh()
	end)

	Remotes.FusionResultReceived.OnClientEvent:Connect(function(result: any)
		if typeof(result) ~= "table" then return end
		showResult(result :: Types.FusionResult)
	end)

	print("[FusionPanel] Initialisiert")
end

return FusionPanel
