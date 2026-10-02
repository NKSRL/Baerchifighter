--!strict
-- RebirthDialog.luau
-- StarterPlayerScripts/UI/RebirthDialog.luau
--
-- Einzige Zustaendigkeit:
--   - Vor dem Rebirth klar sagen was verloren geht und was bleibt
--   - Den Rebirth ausloesen und das Ergebnis bestaetigen
--
-- Der Text unten muss zu RebirthService passen — dort steht die verbindliche
-- Liste. Stand jetzt:
--   verloren : alle Baerchis, alle Gebaeude-Level, PIT-Level, laufende Bruten,
--              Gummies (zurueck auf EconomyConfig.REBIRTH_START_GUMMIES)
--   behalten : GoldGummies, Rang, Statistiken, bereits verdiente AscensionEggs
--   gewonnen : hoeherer Multiplikator, ggf. AscensionEggs (Meilenstein)
-- Wer den Service aendert, aendert diesen Text mit.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types         = require(ReplicatedStorage.Network.Types)
local Remotes       = require(ReplicatedStorage.Network.Remotes)
local EconomyConfig = require(ReplicatedStorage.Config.EconomyConfig)
local Loc           = require(ReplicatedStorage.Localization.Loc)

local Theme        = require(script.Parent.Theme)
local Toast        = require(script.Parent.Toast)
local PanelManager = require(script.Parent.PanelManager)
local ClientState  = require(script.Parent.Parent.Controllers.ClientState)

local RebirthDialog = {}

local PANEL_NAME = "Rebirth"

local _root: Frame?               = nil
local _statusLabel: TextLabel?    = nil
local _costLabel: TextLabel?      = nil
local _lossLabel: TextLabel?      = nil
local _rewardLabel: TextLabel?    = nil
local _confirmButton: TextButton? = nil

--------------------------------------------------------------------------------
-- Inhalt
--------------------------------------------------------------------------------

function RebirthDialog.refresh()
	local root = _root
	if not root or not root.Visible then return end

	local data = ClientState.get()
	if not data then return end

	local cost    = EconomyConfig.getRebirthCost(data.rebirthCount)
	local nextMult = EconomyConfig.getRebirthMult(data.rebirthCount + 1)
	local eggs    = EconomyConfig.getAscensionEggReward(data.rebirthCount + 1)
	local enough  = data.gummies >= cost

	-- Zahlen uebergibt der Code als Zahlen: Loc formatiert sie je nach Sprache
	-- ("1.500" / "1,500" / "1 500"), der Text legt das Dezimalformat fest ({mult:d2}).
	if _statusLabel then
		_statusLabel.Text = Loc.t("ui.rebirth.status", {
			count = data.rebirthCount,
			mult  = data.rebirthMult,
		})
	end

	if _costLabel then
		_costLabel.Text = Loc.t("ui.rebirth.cost", { cost = cost, have = data.gummies })
		_costLabel.TextColor3 = if enough then Theme.COLORS.good else Theme.COLORS.bad
	end

	if _lossLabel then
		_lossLabel.Text = Loc.t("ui.rebirth.loss", { start = EconomyConfig.REBIRTH_START_GUMMIES })
	end

	if _rewardLabel then
		_rewardLabel.Text = if eggs > 0
			then Loc.tn("ui.rebirth.reward_eggs", eggs, { mult = nextMult })
			else Loc.t("ui.rebirth.reward", { mult = nextMult })
	end

	if _confirmButton then
		Theme.setEnabled(_confirmButton, enough)
	end
end

--------------------------------------------------------------------------------
-- Oeffnen / Schliessen
--------------------------------------------------------------------------------

local function openInternal(...: any)
	local root = _root
	if not root then return end

	root.Visible = true
	RebirthDialog.refresh()
end

local function closeInternal()
	local root = _root
	if root then root.Visible = false end
end

--------------------------------------------------------------------------------
-- Aufbau
--------------------------------------------------------------------------------

function RebirthDialog.init(screenGui: ScreenGui)
	local root = Theme.dialog(
		"RebirthDialog", screenGui,
		Vector2.new(0.46, 0.50),
		Vector2.new(300, 270),
		Vector2.new(520, 400)
	)
	_root = root

	local title = Theme.dialogHeader(root, "", function()
		PanelManager.close(PANEL_NAME)
	end)
	Loc.bind(title, "ui.rebirth.title")

	local body = Theme.dialogBody(root)

	local status = Theme.label("Status", body, "")
	status.Size = UDim2.new(1, -8, 0, 24)
	_statusLabel = status

	local cost = Theme.label("Cost", body, "")
	cost.Position = UDim2.new(0, 0, 0, 28)
	cost.Size     = UDim2.new(1, -8, 0, 22)
	_costLabel = cost

	local loss = Theme.bodyText("Loss", body, "")
	loss.Position = UDim2.new(0, 2, 0, 56)
	loss.Size     = UDim2.new(1, -8, 0, 86)
	_lossLabel = loss

	local reward = Theme.label("Reward", body, "")
	reward.Position   = UDim2.new(0, 0, 0, 146)
	reward.Size       = UDim2.new(1, -8, 0, 24)
	reward.TextColor3 = Theme.COLORS.goldGummy
	_rewardLabel = reward

	local cancel = Theme.button("Cancel", body, "", Theme.COLORS.panelLight)
	Loc.bind(cancel, "ui.rebirth.cancel")
	cancel.AnchorPoint = Vector2.new(0, 1)
	cancel.Position    = UDim2.new(0, 0, 1, 0)
	cancel.Size        = UDim2.new(0.5, -6, 0, 38)
	cancel.TextColor3  = Theme.COLORS.text
	cancel.Activated:Connect(function()
		PanelManager.close(PANEL_NAME)
	end)

	local confirm = Theme.button("Confirm", body, "", Theme.COLORS.gummy)
	Loc.bind(confirm, "ui.rebirth.confirm")
	confirm.AnchorPoint = Vector2.new(1, 1)
	confirm.Position    = UDim2.new(1, -8, 1, 0)
	confirm.Size        = UDim2.new(0.5, -6, 0, 38)
	_confirmButton = confirm

	confirm.Activated:Connect(function()
		Remotes.RequestRebirth:FireServer()
	end)

	PanelManager.register(PANEL_NAME, {
		open  = openInternal,
		close = closeInternal,
	})

	ClientState.onChanged(function()
		RebirthDialog.refresh()
	end)

	-- Sprachwechsel bei offenem Dialog: die Texte aus dem Spielstand neu setzen
	-- (die gebundenen Beschriftungen — Titel, Knoepfe — zieht Loc selbst nach)
	Loc.onChanged(function()
		RebirthDialog.refresh()
	end)

	Remotes.RebirthResultReceived.OnClientEvent:Connect(function(result: any)
		if typeof(result) ~= "table" then return end
		local typed = result :: Types.RebirthResult

		local args = { count = typed.newRebirthCount, mult = typed.newMultiplier }

		Toast.success(if typed.ascensionEggs > 0
			then Loc.tn("msg.rebirth_done_eggs", typed.ascensionEggs, args)
			else Loc.t("msg.rebirth_done", args))

		PanelManager.close(PANEL_NAME)
	end)

	print("[RebirthDialog] Initialisiert")
end

return RebirthDialog
