--!strict
-- CombatPanel.luau
-- StarterPlayerScripts/UI/CombatPanel.luau
--
-- Einzige Zustaendigkeit:
--   - Den ausgeruesteten Kaempfer und das PIT-Level anzeigen
--   - Nach einem Lauf eine kurze Ergebnis-Meldung zeigen (Toast)
--
-- SEIT v12 startet dieses Panel keinen Lauf mehr: gestartet und
-- zurueckgeholt wird ueber den Fight-Knopf der unteren Pet-Leiste (PetBar).
-- Das Ergebnis kommt erst NACH der Abrechnung (am Ende der Wiedergabe in der
-- Arena, bzw. nach dem Zurueckholen nur mit den gespielten Stages).
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
local Toast        = require(script.Parent.Toast)
local PanelManager = require(script.Parent.PanelManager)
local ClientState  = require(script.Parent.Parent.Controllers.ClientState)

local CombatPanel = {}

local PANEL_NAME = "Combat"
local ROW_HEIGHT = 40

local _root: Frame?              = nil
local _info: TextLabel?          = nil
local _scroller: ScrollingFrame? = nil
local _empty: TextLabel?         = nil

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
end

--------------------------------------------------------------------------------
-- Ergebnis des Laufs
--------------------------------------------------------------------------------

-- Frueher lief hier ein Kampf-Fenster mitten im Bildschirm mit HP-Balken.
-- Auf Wunsch entfernt: es verdeckte genau den Kampf in der Arena, den man
-- beobachten will (die Arena zeigt Stages, HP-Balken und Tafel ohnehin
-- selbst). Uebrig bleibt nur eine kurze Meldung am unteren Rand.
local function showResult(result: Types.PitRunResult)
	local cleared = result.stagesCleared or 0
	local parts = {
		if cleared > 0 then string.format("%d Stages geschafft", cleared) else "Keine Stage geschafft",
		"+" .. Theme.formatNumber(result.gummiesWon or 0) .. " Gummies",
	}
	if (result.goldGummiesWon or 0) > 0 then
		table.insert(parts, "+" .. Theme.formatNumber(result.goldGummiesWon) .. " GoldGummies")
	end
	if result.recalled then
		table.insert(parts, "zurueckgeholt")
	end

	local text = "PIT: " .. table.concat(parts, "  •  ")
	if cleared > 0 then Toast.success(text) else Toast.info(text) end
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

	local hint = Theme.bodyText("Hint", body, "In den PIT schickst du deinen Baerchi mit dem Fight-Knopf unten am Bildschirm. Nochmal druecken holt ihn zurueck.")
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position    = UDim2.new(0.5, 0, 1, 0)
	hint.Size        = UDim2.new(1, -8, 0, 40)

	PanelManager.register(PANEL_NAME, {
		open  = openInternal,
		close = closeInternal,
	})

	ClientState.onChanged(function()
		CombatPanel.refresh()
	end)

	Remotes.CombatResultReceived.OnClientEvent:Connect(function(result: any)
		if typeof(result) ~= "table" then return end
		local typed = result :: Types.PitRunResult

		-- Auf dem Hinweg zurueckgeholt: es gab keinen Kampf, also auch
		-- nichts abzuspielen.
		if typed.recalled and (typeof(typed.stages) ~= "table" or #typed.stages == 0) then
			return
		end

		showResult(typed)
	end)

	print("[CombatPanel] Initialisiert")
end

return CombatPanel