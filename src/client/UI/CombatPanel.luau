--!strict
-- CombatPanel.luau
-- StarterPlayerScripts/UI/CombatPanel.luau
--
-- Einzige Zustaendigkeit:
--   - Den PIT-Lauf des ausgeruesteten Baerchis ausloesen
--   - Den Lauf Stage fuer Stage abspielen
--
-- Seit dem Equip-System kann nur noch der AUSGERUESTETE Baerchi kaempfen: nur
-- er steht auf dem Plot und laeuft selbststaendig zur Arena (siehe
-- PitArenaService). Die frueher hier gezeigte Liste "welchen Baerchi
-- schicken" gibt es deshalb nicht mehr — wer einen anderen kaempfen lassen
-- will, ruestet ihn in der Baerchi-Karte oder im Inventar aus.
--
-- Ein PIT-Lauf ist kein einzelner Kampf: der Baerchi kaempft weiter solange
-- er gewinnt, seine HP werden zwischen den Stages nicht zurueckgesetzt.
-- Danach ist er erschoepft und muss auf dem Plot mit Honig hochgefuettert
-- werden — Kaempfe selbst geben keine XP mehr.
--
-- Der Ergebnis-Listener haengt am Modul, nicht am Panel: ein Lauf kann auch
-- aus der Baerchi-Detailkarte gestartet werden, die Wiedergabe soll trotzdem
-- laufen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types            = require(ReplicatedStorage.Network.Types)
local Remotes          = require(ReplicatedStorage.Network.Remotes)
local BaerchiConfig    = require(ReplicatedStorage.Config.BaerchiConfig)
local EconomyConfig    = require(ReplicatedStorage.Config.EconomyConfig)
local CombatCalculator = require(ReplicatedStorage.Modules.CombatCalculator)

local Theme        = require(script.Parent.Theme)
local PanelManager = require(script.Parent.PanelManager)
local ClientState  = require(script.Parent.Parent.Controllers.ClientState)

local CombatPanel = {}

local PANEL_NAME = "Combat"
local ROW_HEIGHT = 40

local _root: Frame?              = nil
local _info: TextLabel?          = nil
local _scroller: ScrollingFrame? = nil
local _empty: TextLabel?         = nil
local _startButton: TextButton?  = nil

-- Kampf-Overlay (haengt am ScreenGui, damit es auch ohne offenes Panel geht)
local _fight: Frame?           = nil
local _fightTitle: TextLabel?  = nil
local _selfBar: Theme.Progress? = nil
local _enemyBar: Theme.Progress? = nil
local _resultLabel: TextLabel? = nil
local _rewardLabel: TextLabel? = nil
local _okButton: TextButton?   = nil
local _fightToken = 0

--------------------------------------------------------------------------------
-- Auswahl
--------------------------------------------------------------------------------

-- Kaempfen kann nur noch der ausgeruestete Baerchi — er ist der einzige, der
-- ueberhaupt auf dem Plot steht und zur Arena laufen kann.
local function equippedUid(): string?
	local data = ClientState.get()
	if not data then return nil end
	return data.island.equippedUid
end

--------------------------------------------------------------------------------
-- Anzeige des ausgeruesteten Baerchis
--------------------------------------------------------------------------------

local function buildRow(parent: Instance, baerchi: Types.Baerchi)
	local def   = BaerchiConfig.getById(baerchi.configId)
	local color = Theme.rarityColor(baerchi.rarity)

	local row = Theme.panel("Row_" .. baerchi.uid, parent, Theme.COLORS.panel)
	row.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)

	local stroke = row:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color     = Theme.COLORS.good
		stroke.Thickness = Theme.OUTLINE_THICKNESS + 2
	end

	local name = Theme.label("Name", row, string.format(
		"%s  Lv.%d",
		def and def.displayName or baerchi.configId,
		baerchi.level
	))
	name.Position   = UDim2.new(0, 12, 0.5, -10)
	name.Size       = UDim2.new(1, -110, 0, 20)
	name.TextColor3 = color

	local stats = if def then CombatCalculator.getEffectiveStats(baerchi, def.baseStats) else nil
	local statsLabel = Theme.label("Stats", row, if stats then string.format("HP %d  ATK %d", stats.maxHp, stats.atk) else "")
	statsLabel.AnchorPoint    = Vector2.new(1, 0.5)
	statsLabel.Position       = UDim2.new(1, -10, 0.5, 0)
	statsLabel.Size           = UDim2.new(0, 92, 0, 16)
	statsLabel.TextXAlignment = Enum.TextXAlignment.Right
	statsLabel.TextScaled     = false
	statsLabel.TextSize       = 13
	statsLabel.Font           = Theme.FONT_BODY
	statsLabel.TextColor3     = Theme.COLORS.textDim
end

function CombatPanel.refresh()
	local root     = _root
	local scroller = _scroller
	if not root or not scroller then return end
	if not root.Visible then return end

	local data = ClientState.get()
	if not data then return end

	local uid      = equippedUid()
	local baerchi  = if uid then ClientState.getBaerchi(uid) else nil

	local info = _info
	if info then
		info.Text = string.format(
			"PIT Level %d  —  Sieg bringt ca. %s Gummies",
			data.island.pitLevel,
			Theme.formatNumber(EconomyConfig.getPitReward(data.island.pitLevel, data.rebirthMult))
		)
	end

	for _, child in scroller:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local empty = _empty
	if empty then
		empty.Visible = baerchi == nil
	end

	if baerchi then
		buildRow(scroller, baerchi)
	end

	local startButton = _startButton
	if startButton then
		Theme.setEnabled(startButton, baerchi ~= nil)
	end
end

--------------------------------------------------------------------------------
-- Wiedergabe des Ergebnisses
--------------------------------------------------------------------------------

-- Spielt einen kompletten PIT-Lauf ab: Stage fuer Stage, mit dem HP-Balken
-- des Baerchis als durchgehendem Faden. Der Balken wird zwischen den Stages
-- bewusst NICHT zurueckgesetzt — genau das ist die neue Mechanik, und man
-- soll sehen wie die Luft ausgeht.
--
-- Der Server schickt keine einzelnen Runden mehr (bei bis zu 60 Stages waere
-- das ein Vielfaches der Nutzlast), sondern pro Stage eine Zusammenfassung.
-- Der Gegner-Balken ist deshalb eine Darstellung des Ausgangs, keine
-- Runden-fuer-Runden-Wiedergabe: gewonnen = leer, verloren = Rest bleibt.
local function playResult(result: Types.PitRunResult)
	local fight = _fight
	local selfBar, enemyBar = _selfBar, _enemyBar
	if not fight or not selfBar or not enemyBar then return end

	_fightToken += 1
	local token = _fightToken

	local baerchi = ClientState.getBaerchi(result.baerchiUid)
	local def     = if baerchi then BaerchiConfig.getById(baerchi.configId) else nil

	local maxHp = math.max(1, result.maxHp)

	if _fightTitle then
		_fightTitle.Text = if def then def.displayName .. " im PIT" else "PIT-Lauf"
	end
	if _resultLabel then
		_resultLabel.Text    = ""
		_resultLabel.Visible = false
	end
	if _rewardLabel then
		_rewardLabel.Text    = ""
		_rewardLabel.Visible = false
	end
	if _okButton then
		_okButton.Visible = false
	end

	selfBar.fill.Size  = UDim2.fromScale(math.clamp(result.hpBefore / maxHp, 0, 1), 1)
	selfBar.text.Text  = string.format("%d / %d HP", result.hpBefore, maxHp)
	enemyBar.fill.Size = UDim2.fromScale(1, 1)
	enemyBar.text.Text = "Stage 1"
	fight.Visible      = true

	-- Fehlt die Liste (Datenpaket von einem aelteren Serverstand), wird nur
	-- die Zusammenfassung gezeigt statt an der Laengen-Operation zu scheitern.
	local stages = if typeof(result.stages) == "table" then result.stages else {}

	-- Gesamtdauer deckeln: ein Lauf ueber 40 Stages darf nicht 40 Sekunden
	-- Zuschauen bedeuten.
	local stepTime = math.clamp(3.0 / math.max(1, #stages), 0.10, 0.45)

	task.spawn(function()
		task.wait(0.3)

		for _, stage in ipairs(stages) do
			if token ~= _fightToken then return end

			enemyBar.text.Text = string.format("Stage %d", stage.stage)
			enemyBar.fill.Size = UDim2.fromScale(1, 1)
			task.wait(stepTime * 0.4)

			if token ~= _fightToken then return end

			-- Gegner: bei Sieg leer, bei Niederlage bleibt ein Rest stehen
			enemyBar.fill.Size = UDim2.fromScale(if stage.won then 0 else 0.35, 1)

			-- Eigene HP nach dieser Stage
			local ratio = math.clamp(stage.hpAfter / maxHp, 0, 1)
			selfBar.fill.Size = UDim2.fromScale(ratio, 1)
			selfBar.text.Text = string.format("%d / %d HP", stage.hpAfter, maxHp)

			task.wait(stepTime * 0.6)
		end

		if token ~= _fightToken then return end

		local cleared = result.stagesCleared or 0

		if _resultLabel then
			_resultLabel.Text = if cleared > 0
				then string.format("%d Stages geschafft", cleared)
				else "Keine Stage geschafft"
			_resultLabel.TextColor3 = if cleared > 0 then Theme.COLORS.good else Theme.COLORS.bad
			_resultLabel.Visible    = true
		end

		if _rewardLabel then
			local parts = { "+" .. Theme.formatNumber(result.gummiesWon) .. " Gummies" }
			if result.goldGummiesWon > 0 then
				table.insert(parts, "+" .. Theme.formatNumber(result.goldGummiesWon) .. " GoldGummies")
			end
			table.insert(parts, string.format("%d / %d HP uebrig", result.hpAfter, maxHp))

			_rewardLabel.Text = table.concat(parts, "    ")
			_rewardLabel.Visible = true
		end

		if _okButton then
			_okButton.Visible = true
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
	CombatPanel.refresh()
end

local function closeInternal()
	local root = _root
	if root then root.Visible = false end
end

--------------------------------------------------------------------------------
-- Aufbau
--------------------------------------------------------------------------------

local function buildFightOverlay(screenGui: ScreenGui)
	local fight = Theme.dialog(
		"CombatOverlay", screenGui,
		Vector2.new(0.42, 0.40),
		Vector2.new(290, 230),
		Vector2.new(480, 320)
	)
	fight.ZIndex = 30
	_fight = fight

	local title = Theme.label("Title", fight, "Kampf im PIT")
	title.Position       = UDim2.new(0, 14, 0, 12)
	title.Size           = UDim2.new(1, -28, 0, 26)
	title.TextXAlignment = Enum.TextXAlignment.Center
	_fightTitle = title

	local selfBar = Theme.progress(fight, Theme.COLORS.good)
	selfBar.track.Position = UDim2.new(0, 14, 0, 46)
	selfBar.track.Size     = UDim2.new(1, -28, 0, 26)
	_selfBar = selfBar

	local enemyBar = Theme.progress(fight, Theme.COLORS.bad)
	enemyBar.track.Position = UDim2.new(0, 14, 0, 78)
	enemyBar.track.Size     = UDim2.new(1, -28, 0, 26)
	_enemyBar = enemyBar

	local resultLabel = Theme.label("Result", fight, "")
	resultLabel.Position       = UDim2.new(0, 14, 0, 116)
	resultLabel.Size           = UDim2.new(1, -28, 0, 34)
	resultLabel.TextXAlignment = Enum.TextXAlignment.Center
	resultLabel.Visible        = false
	_resultLabel = resultLabel

	local rewardLabel = Theme.label("Reward", fight, "")
	rewardLabel.Position       = UDim2.new(0, 14, 0, 152)
	rewardLabel.Size           = UDim2.new(1, -28, 0, 22)
	rewardLabel.TextXAlignment = Enum.TextXAlignment.Center
	rewardLabel.TextColor3     = Theme.COLORS.textDim
	rewardLabel.Visible        = false
	_rewardLabel = rewardLabel

	local ok = Theme.button("Ok", fight, "Weiter", Theme.COLORS.accent)
	ok.AnchorPoint = Vector2.new(0.5, 1)
	ok.Position    = UDim2.new(0.5, 0, 1, -12)
	ok.Size        = UDim2.new(1, -28, 0, 32)
	ok.Visible     = false
	_okButton = ok

	ok.Activated:Connect(function()
		_fightToken += 1   -- laufende Wiedergabe abbrechen
		fight.Visible = false
	end)
end

function CombatPanel.init(screenGui: ScreenGui)
	local root = Theme.dialog(
		"CombatPanel", screenGui,
		Vector2.new(0.46, 0.60),
		Vector2.new(300, 290),
		Vector2.new(520, 540)
	)
	_root = root

	Theme.dialogHeader(root, "Kampf", function()
		PanelManager.close(PANEL_NAME)
	end)

	local body = Theme.dialogBody(root)

	local info = Theme.label("Info", body, "")
	info.Size       = UDim2.new(1, -8, 0, 22)
	info.TextColor3 = Theme.COLORS.textDim
	_info = info

	local scroller = Theme.scroller("List", body)
	scroller.Position = UDim2.new(0, 0, 0, 28)
	scroller.Size     = UDim2.new(1, 0, 1, -74)
	_scroller = scroller

	local layout = Theme.listLayout(scroller, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left

	local empty = Theme.bodyText("Empty", body, "Noch kein Baerchi ausgeruestet. Ruest einen im Inventar aus.")
	empty.Position = UDim2.new(0, 4, 0, 36)
	empty.Size     = UDim2.new(1, -8, 0, 40)
	empty.Visible  = false
	_empty = empty

	local start = Theme.button("Start", body, "In den PIT", Theme.COLORS.bad)
	start.AnchorPoint = Vector2.new(0.5, 1)
	start.Position    = UDim2.new(0.5, 0, 1, 0)
	start.Size        = UDim2.new(1, -8, 0, 38)
	_startButton = start

	start.Activated:Connect(function()
		local uid = equippedUid()
		if not uid then return end
		Remotes.RequestStartCombat:FireServer(uid)
	end)

	buildFightOverlay(screenGui)

	PanelManager.register(PANEL_NAME, {
		open  = openInternal,
		close = closeInternal,
	})

	ClientState.onChanged(function()
		CombatPanel.refresh()
	end)

	Remotes.CombatResultReceived.OnClientEvent:Connect(function(result: any)
		if typeof(result) ~= "table" then return end
		playResult(result :: Types.PitRunResult)
	end)

	print("[CombatPanel] Initialisiert")
end

return CombatPanel