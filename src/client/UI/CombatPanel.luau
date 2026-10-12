--!strict
-- CombatPanel.luau
-- StarterPlayerScripts/UI/CombatPanel.luau
--
-- Einzige Zustaendigkeit:
--   - Die Tower-Wahl zeigen (v15): eine Karte pro Tower mit Look-Farbe,
--     Rekord, Deckel des aktuellen Rebirths und naechstem Meilenstein
--   - Nach einem Lauf eine kurze Ergebnis-Meldung zeigen (Toast), am Deckel den
--     Rebirth-Hinweis mit Knopf zum RebirthDialog, und Meilenstein-Toasts
--
-- Gestartet und zurueckgeholt wird weiterhin ueber den Fight-Knopf der unteren
-- Pet-Leiste (PetBar). Dieses Panel waehlt nur, WOHIN er schickt
-- (RequestSelectTower). Ob ein Tower offen ist, prueft der Server; die Karten
-- rechnen mit denselben Funktionen aus TowerConfig nur fuer die Anzeige.
--
-- Der Ergebnis-Listener haengt am Modul, nicht am Panel: ein Lauf soll seine
-- Meldung auch bringen, wenn das Panel zu ist.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types       = require(ReplicatedStorage.Network.Types)
local Remotes     = require(ReplicatedStorage.Network.Remotes)
local Loc         = require(ReplicatedStorage.Localization.Loc)
local Names       = require(ReplicatedStorage.Localization.Names)
local TowerConfig = require(ReplicatedStorage.Config.TowerConfig)
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)
local EggConfig   = require(ReplicatedStorage.Config.EggConfig)

local Theme        = require(script.Parent.Theme)
local Toast        = require(script.Parent.Toast)
-- HBB Paket 1: Meldungen nach FeedbackConfig verteilen (Icon/Moment/Toast)
local Notify       = require(script.Parent.Notify)
local Moment       = require(script.Parent.Moment)
local PanelManager = require(script.Parent.PanelManager)
local PitResumeDialog = require(script.Parent.PitResumeDialog)
local Icons        = require(script.Parent.Icons)
local ClientState  = require(script.Parent.Parent.Controllers.ClientState)

local CombatPanel = {}

local PANEL_NAME   = "Combat"
local REBIRTH_PANEL = "Rebirth"
local CARD_HEIGHT  = 78

type Card = {
	frame  : Frame,
	stroke : UIStroke?,
	title  : TextLabel,
	info   : TextLabel,
	button : TextButton,
}

local _root: Frame?        = nil
local _info: TextLabel?    = nil
local _hint: Frame?        = nil
local _cards: { [string]: Card } = {}

-- HBB Paket 2: bezahlter Wiedereinstieg ab der letzten Stage als kleiner
-- Knopf (frueher eine Option im PitResumeDialog). Der kostenlose Einstieg
-- ab 65 % laeuft jetzt ohne Frage ueber den Fight-Knopf.
local _resume: TextButton? = nil
local _resumeHint: TextLabel? = nil

local function refreshResume(data: Types.PlayerDataUpdate)
	local button, hintText = _resume, _resumeHint
	if not button or not hintText then return end
	local reached = PitResumeDialog.getProgress(data)
	local towerId = if data.towers then data.towers.selected else TowerConfig.FIRST_TOWER
	local cost = if reached then TowerConfig.getResumeCost(towerId, reached, data.rebirthMult) else 0
	local show = FeatureFlags.isOn("UI_V2_GUIDE") and reached ~= nil and reached > 1 and cost > 0
	button.Visible = show
	hintText.Visible = not show
	if show then
		button.Text = string.format("⏩ %d   %s", reached :: number, Theme.formatNumber(cost))
		Theme.setEnabled(button, cost <= data.gummies)
	end
end

--------------------------------------------------------------------------------
-- Karten
--------------------------------------------------------------------------------

local function towerName(def: TowerConfig.TowerDef): string
	return Loc.t("tower." .. def.id .. ".name")
end

local function buildCard(parent: Instance, def: TowerConfig.TowerDef, order: number): Card
	local frame = Theme.panel("Tower_" .. def.id, parent, Theme.COLORS.panel)
	frame.Size        = UDim2.new(1, -8, 0, CARD_HEIGHT)
	frame.LayoutOrder = order

	-- Farbstreifen links in der Look-Farbe des Towers
	local stripe = Theme.panel("Stripe", frame, def.color)
	stripe.Size     = UDim2.new(0, 14, 1, -12)
	stripe.Position = UDim2.new(0, 6, 0, 6)

	local title = Theme.label("Title", frame, "")
	title.Position   = UDim2.new(0, 28, 0, 6)
	title.Size       = UDim2.new(1, -150, 0, 26)
	title.TextColor3 = Theme.shade(def.color, -0.1)
	Theme.outlineText(title)

	local info = Theme.bodyText("Info", frame, "")
	info.Position = UDim2.new(0, 28, 0, 34)
	info.Size     = UDim2.new(1, -150, 0, CARD_HEIGHT - 38)
	info.TextSize = 13

	local button = Theme.bigButton("Choose", frame, "", def.color)
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position    = UDim2.new(1, -10, 0.5, 0)
	button.Size        = UDim2.new(0, 110, 0, 40)
	button.Activated:Connect(function()
		if not button.Active then return end
		Remotes.RequestSelectTower:FireServer(def.id)
	end)

	return {
		frame  = frame,
		stroke = frame:FindFirstChildOfClass("UIStroke"),
		title  = title,
		info   = info,
		button = button,
	}
end

local function refreshCard(card: Card, def: TowerConfig.TowerDef, data: Types.PlayerDataUpdate)
	local towers = data.towers
	local record = if towers then towers.records[def.id] or 0 else 0
	local cap    = TowerConfig.getStageCap(data.rebirthCount, def.id, if towers then towers.records else nil)
	local open   = cap > 0
	local selected = towers ~= nil and towers.selected == def.id
	local endless = def.id == "Endless"   -- HBB Paket 9: ohne Obergrenze

	card.title.Text = if endless then towerName(def) else string.format("%s  (%d)", towerName(def), def.stages)

	if open then
		local claimed = if towers then towers.claimed[def.id] else nil
		local nextStage = TowerConfig.nextMilestoneStage(def.id, claimed, record + 1)
		local lines = {
			if endless
				then Loc.t("ui.tower.record_endless", { record = record })
				else Loc.t("ui.tower.record_cap", { record = record, cap = cap, stages = def.stages }),
		}
		if nextStage then
			table.insert(lines, Loc.t("ui.tower.next_milestone", { stage = nextStage }))
		end
		card.info.Text = table.concat(lines, "\n")
		card.button.Text = if selected then Loc.t("ui.tower.selected") else Loc.t("ui.tower.choose")
		Theme.setEnabled(card.button, not selected)
	else
		card.info.Text = if endless
			then Loc.t("ui.tower.locked_endless")
			else Loc.t("ui.tower.locked", { rebirths = TowerConfig.getOpeningRebirth(def.id) })
		card.button.Text = Loc.t("ui.tower.locked_short")
		Theme.setEnabled(card.button, false)
	end

	local stroke = card.stroke
	if stroke then
		stroke.Color     = if selected then Theme.COLORS.good else Theme.COLORS.outline
		stroke.Thickness = if selected then Theme.OUTLINE_THICKNESS + 2 else Theme.OUTLINE_THICKNESS
	end
end

function CombatPanel.refresh()
	local root = _root
	if not root or not root.Visible then return end

	local data = ClientState.get()
	if not data then return end

	local capTower, capStage = TowerConfig.getCap(data.rebirthCount)
	local capDef = TowerConfig.get(capTower) or TowerConfig.TOWERS[1]
	local info = _info
	if info then
		info.Text = Loc.t("ui.tower.cap_line", { rebirths = data.rebirthCount, tower = towerName(capDef), stage = capStage })
	end

	refreshResume(data)

	for _, def in TowerConfig.TOWERS do
		local card = _cards[def.id]
		if card then refreshCard(card, def, data) end
	end
end

--------------------------------------------------------------------------------
-- Ergebnis des Laufs
--------------------------------------------------------------------------------

local function showCapHint(result: Types.PitRunResult)
	local hint = _hint
	if not hint then return end
	local label = hint:FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		label.Text = Loc.t("ui.tower.cap_reached", { stage = result.capStage or 0 })
	end
	hint.Visible = true
	task.delay(12, function()
		hint.Visible = false
	end)
end

local function showResult(result: Types.PitRunResult)
	local cleared = result.stagesCleared or 0
	local def = TowerConfig.get(result.towerId or "") or TowerConfig.TOWERS[1]
	local parts = {
		"Tower " .. def.numeral,
		Loc.tn("msg.tower_cleared", cleared),
		"+" .. Theme.formatNumber(result.gummiesWon or 0) .. " Gummies",
	}
	if (result.goldGummiesWon or 0) > 0 then
		table.insert(parts, "+" .. Theme.formatNumber(result.goldGummiesWon) .. " GoldGummies")
	end
	if result.newRecord then
		table.insert(parts, Loc.t("msg.tower_new_record", { stage = result.newRecord }))
	end
	if result.recalled then
		table.insert(parts, Loc.t("msg.tower_recalled"))
	end

	local text = table.concat(parts, "  •  ")
	-- Gummies/GoldGummies fliegen ueber den Datenstand (UI/Feedback); der
	-- neue Rekord ist der Moment, den man sehen soll.
	Notify.emit("tower_result", function()
		if cleared > 0 then Toast.success(text) else Toast.info(text) end
	end, function()
		if result.newRecord then
			Notify.emit("tower_record", function() end, function()
				Moment.show("record", Theme.COLORS.goldGummy, "ui.moment.record")
			end)
		end
	end)

	if result.capReached then
		showCapHint(result)
	end
end

local function showMilestone(reward: Types.TowerMilestoneReward)
	local def = TowerConfig.get(reward.towerId) or TowerConfig.TOWERS[1]
	local parts: { string } = {}
	if reward.gummies > 0 then table.insert(parts, "+" .. Theme.formatNumber(reward.gummies) .. " Gummies") end
	if reward.goldGummies > 0 then table.insert(parts, "+" .. Theme.formatNumber(reward.goldGummies) .. " GoldGummies") end
	if reward.eggType and reward.eggs > 0 then
		table.insert(parts, string.format("+%d %s", reward.eggs, Names.egg(reward.eggType)))
	end
	if reward.blueprints > 0 then table.insert(parts, Loc.t("msg.tower_blueprint")) end
	if (reward.endlessLevels or 0) > 0 then
		table.insert(parts, Loc.t("msg.tower_endless_level", { n = reward.endlessLevels or 0 }))
	end
	Notify.emit("tower_milestone", function()
		Toast.success(Loc.t("msg.tower_milestone", { tower = def.numeral, stage = reward.stage, reward = table.concat(parts, ", ") }))
	end, function()
		Moment.show("milestone", Theme.COLORS.goldGummy, "ui.moment.milestone")
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

function CombatPanel.init(screenGui: ScreenGui)
	local root = Theme.dialog(
		"CombatPanel", screenGui,
		Vector2.new(0.50, 0.70),
		Vector2.new(320, 420),
		Vector2.new(560, 600)
	)
	_root = root

	Theme.dialogHeader(root, Loc.t("ui.tower.title"), function()
		PanelManager.close(PANEL_NAME)
	end)

	local body = Theme.dialogBody(root)

	local info = Theme.bodyText("Info", body, "")
	info.Size = UDim2.new(1, -8, 0, 34)
	_info = info

	local scroller = Theme.scroller("List", body)
	scroller.Position = UDim2.new(0, 0, 0, 38)
	scroller.Size     = UDim2.new(1, 0, 1, -84)

	local layout = Theme.listLayout(scroller, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left

	for order, def in TowerConfig.TOWERS do
		_cards[def.id] = buildCard(scroller, def, order)
	end

	local hintText = Theme.bodyText("Hint", body, Loc.t("ui.tower.hint"))
	hintText.AnchorPoint = Vector2.new(0.5, 1)
	hintText.Position    = UDim2.new(0.5, 0, 1, 0)
	hintText.Size        = UDim2.new(1, -8, 0, 40)
	_resumeHint = hintText

	local resume = Theme.bigButton("ResumeLast", body, "", Theme.COLORS.goldGummy)
	resume.AnchorPoint = Vector2.new(0.5, 1)
	resume.Position    = UDim2.new(0.5, 0, 1, -2)
	resume.Size        = UDim2.new(0, 200, 0, 40)
	resume.Visible     = false
	if Icons.has("gummy") then
		local coin = Icons.make(resume, "gummy")
		coin.AnchorPoint = Vector2.new(1, 0.5)
		coin.Position    = UDim2.new(1, -6, 0.5, 0)
		coin.Size        = UDim2.fromOffset(28, 28)
		coin.ZIndex      = 4
	end
	resume.Activated:Connect(function()
		if not resume.Active then return end
		Remotes.RequestPetMode:FireServer("Fight", "Last")
		PanelManager.close(PANEL_NAME)
	end)
	_resume = resume

	-- Rebirth-Hinweis am Deckel: eigenes kleines Fenster unten in der Mitte,
	-- unabhaengig davon, ob das Panel offen ist.
	local hint = Theme.panel("CapHint", screenGui, Theme.COLORS.panel)
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position    = UDim2.new(0.5, 0, 1, -110)
	hint.Size        = UDim2.fromOffset(420, 70)
	hint.Visible     = false
	hint.ZIndex      = 15
	_hint = hint

	local hintLabel = Theme.bodyText("Text", hint, "")
	hintLabel.Position = UDim2.new(0, 10, 0, 8)
	hintLabel.Size     = UDim2.new(1, -140, 1, -16)
	hintLabel.TextColor3 = Theme.COLORS.text

	local rebirthButton = Theme.bigButton("Rebirth", hint, Loc.t("ui.tower.to_rebirth"), Theme.COLORS.goldGummy)
	rebirthButton.AnchorPoint = Vector2.new(1, 0.5)
	rebirthButton.Position    = UDim2.new(1, -10, 0.5, 0)
	rebirthButton.Size        = UDim2.new(0, 116, 0, 44)
	rebirthButton.Activated:Connect(function()
		hint.Visible = false
		PanelManager.open(REBIRTH_PANEL)
	end)

	-- 08.10. (Paket D): mit TOWER_PANEL_V2 meldet sich das neue Tower-Panel
	-- (UI/TowerPanel) unter demselben Namen an; dieses Fenster bleibt dann
	-- unsichtbar, die Ergebnis-/Meilenstein-Meldungen unten laufen weiter.
	if not FeatureFlags.isOn("TOWER_PANEL_V2") then
		PanelManager.register(PANEL_NAME, {
			open  = openInternal,
			close = closeInternal,
		})
	end

	ClientState.onChanged(function()
		CombatPanel.refresh()
	end)

	Loc.onChanged(function()
		CombatPanel.refresh()
	end)

	Remotes.CombatResultReceived.OnClientEvent:Connect(function(result: any)
		if typeof(result) ~= "table" then return end
		local typed = result :: Types.PitRunResult

		-- Auf dem Hinweg zurueckgeholt: es gab keinen Kampf.
		if typed.recalled and (typeof(typed.stages) ~= "table" or #typed.stages == 0) then
			return
		end

		showResult(typed)
	end)

	Remotes.TowerMilestoneReceived.OnClientEvent:Connect(function(reward: any)
		if typeof(reward) ~= "table" then return end
		showMilestone(reward :: Types.TowerMilestoneReward)
	end)

	print("[CombatPanel] Initialisiert |", #TowerConfig.TOWERS, "Tower")
end

return CombatPanel
