--!strict
-- DailyBonusPanel.luau
-- StarterPlayerScripts/UI/DailyBonusPanel.luau
--
-- Einzige Zustaendigkeit:
--   - Das Fenster des taeglichen Login-Bonus (v15): sieben Felder (heutiges
--     hervorgehoben, abgeholte abgehakt, kommende grau) und der Abholen-Knopf.
--
-- Oeffnet sich beim Join von selbst, wenn heute noch nicht abgeholt ist (der
-- Server liefert die Sicht im PlayerDataUpdate: Types.DailyView). Ob abgeholt
-- werden darf, entscheidet der Server (RequestClaimDailyBonus).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types            = require(ReplicatedStorage.Network.Types)
local Remotes          = require(ReplicatedStorage.Network.Remotes)
local Loc              = require(ReplicatedStorage.Localization.Loc)
local LoginBonusConfig = require(ReplicatedStorage.Config.LoginBonusConfig)
local FeatureFlags     = require(ReplicatedStorage.Config.FeatureFlags)
local GuideSteps       = require(ReplicatedStorage.Modules.GuideSteps)

local TweenService = game:GetService("TweenService")

local Theme        = require(script.Parent.Theme)
local Icons        = require(script.Parent.Icons)
local Toast        = require(script.Parent.Toast)
-- HBB Paket 1: Meldungen nach FeedbackConfig verteilen (Icon/Moment/Toast)
local Notify       = require(script.Parent.Notify)
local PanelManager = require(script.Parent.PanelManager)
local ClientState  = require(script.Parent.Parent.Controllers.ClientState)

local DailyBonusPanel = {}

local PANEL_NAME = "DailyBonus"

local _root: Frame? = nil
local _cells: { Frame } = {}
local _pulses: { [Frame]: Tween } = {}
local _claim: TextButton? = nil
local _status: TextLabel? = nil
local _autoOpened = false

-- Playtest 05.10.: statt reiner Textzeilen je Tag ein grosses Icon, eine
-- grosse Zahl und die Extras klein darunter. Hauptbild: Tag 7 Geschenk,
-- sonst Gummies, sonst Ei.
local function dayVisual(day: number): (string, string, string)
	local reward = LoginBonusConfig.getDay(day)
	local extras: { string } = {}
	if reward.eggs and reward.eggType then table.insert(extras, string.format("+%d %s", reward.eggs, Loc.t("ui.daily.egg"))) end
	if reward.highestEgg then table.insert(extras, Loc.t("ui.daily.best_egg")) end
	if reward.blueprintChance then table.insert(extras, Loc.t("ui.daily.blueprint_chance", { pct = math.floor(reward.blueprintChance * 100 + 0.5) })) end
	if reward.goldGummies then table.insert(extras, "+" .. Loc.formatNumber(reward.goldGummies) .. " GG") end

	local icon = if day == LoginBonusConfig.CYCLE_DAYS then "gift"
		elseif reward.gummies then "gummy"
		elseif reward.eggType then "egg"
		else "goldgummy"
	local amount = if reward.gummies then Theme.formatNumber(reward.gummies)
		elseif reward.eggs then string.format("%dx", reward.eggs)
		elseif reward.goldGummies then Loc.formatNumber(reward.goldGummies)
		else ""
	return icon, amount, table.concat(extras, "\n")
end

local function refresh()
	local data = ClientState.get()
	local view: Types.DailyView? = if data then data.daily else nil
	if not view then return end

	for day, cell in _cells do
		local done = day <= view.streak and not (view.claimable and day == view.day)
		local today = day == view.day
		local claimed = done or (today and not view.claimable)
		local open = today and view.claimable
		cell.BackgroundColor3 = if open then Theme.COLORS.goldGummy
			elseif claimed then Theme.COLORS.good
			elseif day == LoginBonusConfig.CYCLE_DAYS then Theme.shade(Theme.COLORS.goldGummy, -0.35)
			else Theme.COLORS.panelLight

		local mark = cell:FindFirstChild("Mark")
		if mark and mark:IsA("GuiObject") then
			mark.Visible = claimed
		end
		local stroke = cell:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = if open then Color3.fromRGB(255, 245, 190) else Theme.COLORS.outline
			stroke.Thickness = if open then 4 else Theme.OUTLINE_THICKNESS
		end
		-- Kommende Tage etwas gedaempft, damit "heute" heraussticht
		local icon = cell:FindFirstChild("Icon", true)
		if icon and icon:IsA("ImageLabel") then
			icon.ImageTransparency = if claimed or open then 0 else 0.25
		end
		local pulse = _pulses[cell]
		if pulse then
			if open then pulse:Play() else
				pulse:Cancel()
				local scale = cell:FindFirstChildOfClass("UIScale")
				if scale then scale.Scale = 1 end
			end
		end
	end

	local claim, status = _claim, _status
	if claim then
		claim.Text = if view.claimable then Loc.t("ui.daily.claim", { day = view.day }) else Loc.t("ui.daily.claimed")
		Theme.setEnabled(claim, view.claimable)
	end
	if status then
		status.Text = Loc.t("ui.daily.reset_in", { time = Loc.formatDuration(view.resetIn) })
	end

	-- HBB Paket 2: ein Konto, das an diesem UTC-Tag angelegt wurde, sieht
	-- in den ersten Minuten kein Popup. Das Fenster kommt erst nach dem
	-- ersten beendeten Kampf (dann aendern sich die Daten und refresh
	-- laeuft erneut). Server-Logik unveraendert, nur der Zeitpunkt.
	if view.claimable and not _autoOpened and FeatureFlags.isOn("UI_V2_GUIDE") and data then
		local createdAt = (data :: any).createdAt
		local today = math.floor(workspace:GetServerTimeNow() / 86400)
		local createdToday = typeof(createdAt) == "number" and math.floor(createdAt / 86400) == today
		if createdToday and not GuideSteps.hasFought(data :: any) then
			return
		end
	end

	-- Beim Join einmal von selbst oeffnen, wenn noch nicht abgeholt.
	if view.claimable and not _autoOpened then
		_autoOpened = true
		task.delay(2, function()
			PanelManager.open(PANEL_NAME)
		end)
	end
end

function DailyBonusPanel.init(screenGui: ScreenGui)
	local root = Theme.dialog("DailyBonusPanel", screenGui, Vector2.new(0.6, 0.46), Vector2.new(340, 280), Vector2.new(680, 380))
	_root = root

	Theme.dialogHeader(root, Loc.t("ui.daily.title"), function()
		PanelManager.close(PANEL_NAME)
	end)

	local body = Theme.dialogBody(root)

	local row = Theme.container("Days", body)
	row.Size = UDim2.new(1, 0, 0.62, 0)
	local layout = Theme.listLayout(row, 6, true)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	for day = 1, LoginBonusConfig.CYCLE_DAYS do
		local cell = Theme.panel("Day" .. day, row, Theme.COLORS.disabled)
		cell.Size = UDim2.new(1 / LoginBonusConfig.CYCLE_DAYS, -6, 1, 0)
		cell.LayoutOrder = day

		local iconName, amount, extra = dayVisual(day)
		local isBig = day == LoginBonusConfig.CYCLE_DAYS

		local head = Theme.label("Head", cell, Loc.t("ui.daily.day", { day = day }))
		head.Position = UDim2.new(0, 4, 0, 4)
		head.Size = UDim2.new(1, -8, 0, 18)
		head.TextXAlignment = Enum.TextXAlignment.Center

		-- Hauptgewinn: Krone ueber dem Tag-7-Feld
		if isBig then
			local crown = Icons.make(cell, "crown", "♛")
			crown.Name = "Crown"
			crown.AnchorPoint = Vector2.new(0.5, 0.5)
			crown.Position = UDim2.new(0.5, 0, 0, -4)
			crown.Size = UDim2.fromOffset(30, 30)
			crown.ZIndex = 4
		end

		local holder = Instance.new("Frame")
		holder.Name = "IconHolder"
		holder.BackgroundTransparency = 1
		holder.AnchorPoint = Vector2.new(0.5, 0)
		holder.Position = UDim2.new(0.5, 0, 0, 26)
		holder.Size = UDim2.new(if isBig then 0.95 else 0.8, 0, 0.38, 0)
		holder.Parent = cell
		local icon = Icons.make(holder, iconName, "★")
		icon.Size = UDim2.fromScale(1, 1)

		local amountLabel = Theme.label("Amount", cell, amount)
		amountLabel.AnchorPoint = Vector2.new(0.5, 0)
		amountLabel.Position = UDim2.new(0.5, 0, 0.38, 30)
		amountLabel.Size = UDim2.new(1, -6, 0, 22)
		amountLabel.TextXAlignment = Enum.TextXAlignment.Center

		local text = Theme.bodyText("Reward", cell, extra)
		text.Position = UDim2.new(0, 3, 0.38, 54)
		text.Size = UDim2.new(1, -6, 0.62, -58)
		text.TextSize = 11
		text.TextColor3 = Theme.COLORS.text
		text.TextXAlignment = Enum.TextXAlignment.Center

		-- Abgeholt: Haken oben rechts
		local mark = Icons.make(cell, "check", "✓")
		mark.Name = "Mark"
		mark.AnchorPoint = Vector2.new(1, 0)
		mark.Position = UDim2.new(1, 4, 0, -6)
		mark.Size = UDim2.fromOffset(24, 24)
		mark.ZIndex = 4
		mark.Visible = false

		-- Heute abholbar: sanftes Pulsieren
		local scale = Instance.new("UIScale")
		scale.Parent = cell
		_pulses[cell] = TweenService:Create(scale,
			TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.06 })

		table.insert(_cells, cell)
	end

	local claim = Theme.bigButton("Claim", body, "", Theme.COLORS.good)
	claim.AnchorPoint = Vector2.new(0.5, 1)
	claim.Position = UDim2.new(0.5, 0, 1, -22)
	claim.Size = UDim2.new(0.6, 0, 0, 40)
	claim.Activated:Connect(function()
		if not claim.Active then return end
		Remotes.RequestClaimDailyBonus:FireServer()
	end)
	_claim = claim

	local status = Theme.bodyText("Status", body, "")
	status.AnchorPoint = Vector2.new(0.5, 1)
	status.Position = UDim2.new(0.5, 0, 1, 0)
	status.Size = UDim2.new(1, 0, 0, 18)
	status.TextXAlignment = Enum.TextXAlignment.Center
	_status = status

	PanelManager.register(PANEL_NAME, {
		open = function()
			root.Visible = true
			refresh()
		end,
		close = function()
			root.Visible = false
		end,
	})

	ClientState.onChanged(function()
		refresh()
	end)

	Remotes.DailyBonusReceived.OnClientEvent:Connect(function(result: any)
		if typeof(result) ~= "table" then return end
		local typed = result :: Types.DailyBonusResult
		local parts: { string } = {}
		if typed.gummies > 0 then table.insert(parts, "+" .. Loc.formatNumber(typed.gummies) .. " Gummies") end
		if typed.goldGummies > 0 then table.insert(parts, "+" .. Loc.formatNumber(typed.goldGummies) .. " GoldGummies") end
		if typed.eggs > 0 and typed.eggType then
			table.insert(parts, string.format("+%d %s", typed.eggs, Loc.name("egg." .. typed.eggType .. ".name", typed.eggType)))
		end
		if typed.blueprint then table.insert(parts, Loc.t("msg.tower_blueprint")) end
		-- Inhalte (Gummies, GoldGummies, Eier) fliegen ueber den Datenstand.
		Notify.emit("daily_claimed", function()
			Toast.success(Loc.t("msg.daily_claimed", { day = typed.day, reward = table.concat(parts, ", ") }))
		end)
	end)

	print("[DailyBonusPanel] Initialisiert")
end

return DailyBonusPanel
