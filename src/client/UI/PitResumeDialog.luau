--!strict
-- PitResumeDialog.luau
-- StarterPlayerScripts/UI/PitResumeDialog.luau
--
-- Einzige Zustaendigkeit:
--   - Vor einem PIT-Lauf fragen, wo eingestiegen wird: von vorn, ab 65 % des
--     letzten Laufs oder ab der letzten erreichten Stage (gegen Gummies).
--
-- v15: pro Tower. Erscheint nur, wenn es im GEWAEHLTEN Tower einen
-- gespeicherten letzten Lauf gibt (island.towerProgress), auch nach einer
-- Niederlage oder einem Zurueckholen. Startstage und Kosten rechnet
-- TowerConfig — dieselben
-- Funktionen benutzt der Server beim Abbuchen. Nicht bezahlbare Optionen sind
-- sichtbar, aber nicht klickbar. Abbrechen schliesst den Dialog, der Baerchi
-- bleibt zu Hause.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types            = require(ReplicatedStorage.Network.Types)
local TowerConfig      = require(ReplicatedStorage.Config.TowerConfig)
local BaerchiConfig    = require(ReplicatedStorage.Config.BaerchiConfig)
local CombatCalculator = require(ReplicatedStorage.Modules.CombatCalculator)
local Loc              = require(ReplicatedStorage.Localization.Loc)

local Theme       = require(script.Parent.Theme)
local ClientState = require(script.Parent.Parent.Controllers.ClientState)

local PitResumeDialog = {}

export type Choice = "Fresh" | "Percent" | "Last"

local _root: Frame? = nil
local _hpLabel: TextLabel? = nil
local _options: { [Choice]: TextButton } = {}
local _onChoose: ((Choice) -> ())? = nil

local function selectedTower(data: Types.PlayerDataUpdate): string
	return if data.towers then data.towers.selected else TowerConfig.FIRST_TOWER
end

-- Die letzte erreichte Stage im gewaehlten Tower (nil = kein Lauf gespeichert).
function PitResumeDialog.getProgress(data: Types.PlayerDataUpdate): number?
	local progress = data.island.towerProgress
	local reached = if progress then progress[selectedTower(data)] else nil
	if typeof(reached) == "number" and reached >= 1 then
		return reached
	end
	return nil
end

-- Start-Stage und Gummi-Kosten einer Option — dieselbe Rechnung wie
-- CombatService.getResumeOffer (TowerConfig). Oeffentlich fuer FightStartPrompt.
local function offer(data: Types.PlayerDataUpdate, choice: Choice): (number, number)
	if choice == "Fresh" then
		return 1, 0
	end
	local reached = PitResumeDialog.getProgress(data)
	if not reached then
		return 1, 0
	end
	local towerId = selectedTower(data)
	local def = TowerConfig.get(towerId)
	local stage = if choice == "Last"
		then reached
		else TowerConfig.getResumePercentStage(reached)
	stage = math.clamp(stage, 1, if def then def.stages else 1)
	return stage, TowerConfig.getResumeCost(towerId, stage, data.rebirthMult)
end

-- Loc-Schluessel der drei Optionen
local LABELS: { [Choice]: string } = {
	Fresh   = "ui.pit_resume.fresh",
	Percent = "ui.pit_resume.percent",
	Last    = "ui.pit_resume.last",
}

local function fill()
	local data = ClientState.get()
	if not data then return end

	for choice, button in _options do
		local stage, cost = offer(data, choice)
		local affordable = cost <= data.gummies

		button.Text = Loc.t("ui.pit_resume.option", {
			label = Loc.t(LABELS[choice]),
			stage = stage,
			cost  = if cost > 0 then Loc.t("event.bonus.gummies", { n = cost }) else Loc.t("ui.common.free"),
		})
		Theme.setEnabled(button, affordable)
	end

	local hpLabel = _hpLabel
	if hpLabel then
		local uid = data.island.equippedUid
		local baerchi = if uid then data.island.baerchis[uid] else nil
		local def = if baerchi then BaerchiConfig.getById(baerchi.configId) else nil
		local reached = PitResumeDialog.getProgress(data)
		if baerchi and def then
			local maxHp = CombatCalculator.getEffectiveStats(baerchi, def.baseStats).maxHp
			local hp = math.clamp(baerchi.currentHp or maxHp, 0, maxHp)
			hpLabel.Text = Loc.t("ui.pit_resume.status", {
				tower = (TowerConfig.get(selectedTower(data)) or TowerConfig.TOWERS[1]).numeral,
				stage = reached or 0,
				hp = hp, max = maxHp, pct = math.floor(hp / math.max(1, maxHp) * 100 + 0.5),
			})
		end
	end
end

function PitResumeDialog.offer(data: Types.PlayerDataUpdate, choice: Choice): (number, number)
	return offer(data, choice)
end

function PitResumeDialog.close()
	_onChoose = nil
	local root = _root
	if root then root.Visible = false end
end

-- Oeffnet den Dialog. `onChoose` bekommt die gewaehlte Option.
function PitResumeDialog.open(onChoose: (Choice) -> ())
	local root = _root
	if not root then return end
	_onChoose = onChoose
	fill()
	root.Visible = true
end

function PitResumeDialog.isOpen(): boolean
	return _root ~= nil and (_root :: Frame).Visible
end

function PitResumeDialog.init(screenGui: ScreenGui)
	local root = Theme.dialog(
		"PitResumeDialog", screenGui,
		Vector2.new(0.46, 0.42),
		Vector2.new(300, 280),
		Vector2.new(520, 340)
	)
	root.ZIndex = 20
	_root = root

	local title = Theme.dialogHeader(root, "", PitResumeDialog.close)
	Loc.bind(title, "ui.pit_resume.title")

	local body = Theme.dialogBody(root)
	local layout = Theme.listLayout(body, 8)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local hp = Theme.bodyText("Hp", body, "")
	hp.Size        = UDim2.new(1, 0, 0, 20)
	hp.LayoutOrder = 0
	_hpLabel = hp

	local colors: { [Choice]: Color3 } = {
		Fresh   = Theme.COLORS.accent,
		Percent = Theme.COLORS.goldGummy,
		Last    = Theme.COLORS.bad,
	}

	for order, choice in { "Fresh", "Percent", "Last" } :: { Choice } do
		local button = Theme.bigButton("Option_" .. choice, body, Loc.t(LABELS[choice]), colors[choice])
		button.Size        = UDim2.new(1, 0, 0, 44)
		button.LayoutOrder = order
		button.Activated:Connect(function()
			if not button.Active then return end
			local callback = _onChoose
			PitResumeDialog.close()
			if callback then callback(choice) end
		end)
		_options[choice] = button
	end

	local cancel = Theme.button("Cancel", body, "", Theme.COLORS.panelLight)
	Loc.bind(cancel, "ui.common.cancel")
	cancel.Size        = UDim2.new(1, 0, 0, 34)
	cancel.LayoutOrder = 10
	cancel.TextColor3  = Theme.COLORS.text
	cancel.Activated:Connect(PitResumeDialog.close)

	ClientState.onChanged(function()
		if PitResumeDialog.isOpen() then fill() end
	end)
	Loc.onChanged(function()
		if PitResumeDialog.isOpen() then fill() end
	end)

	print("[PitResumeDialog] Initialisiert")
end

return PitResumeDialog
