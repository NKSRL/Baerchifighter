--!strict
-- QuestTracker.luau
-- StarterPlayerScripts/UI/QuestTracker.luau
--
-- Einzige Zustaendigkeit:
--   - Die kleine Quest-Karte links: immer EINE aktuelle Aufgabe mit Hinweis,
--     Fortschritt und (wenn geschafft) dem Abholen-Knopf
--   - Der Zugang zum Quest-Fenster (Karte antippen)
--   - Der Toast bei ausgezahlter Belohnung
--
-- Das ist die Antwort auf "was mache ich jetzt?": der Spieler muss nichts
-- oeffnen, die naechste sinnvolle Aufgabe steht immer im Bild. Die Karte
-- rechnet nichts, sie zeigt ClientState.get().quests.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local Types   = require(ReplicatedStorage.Network.Types)
local Remotes = require(ReplicatedStorage.Network.Remotes)
local Loc     = require(ReplicatedStorage.Localization.Loc)
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)
local QuestConfig  = require(ReplicatedStorage.Config.QuestConfig)

local Theme        = require(script.Parent.Theme)
local PanelManager = require(script.Parent.PanelManager)
local Toast        = require(script.Parent.Toast)
-- HBB Paket 1: Meldungen nach FeedbackConfig verteilen (Icon/Moment/Toast)
local Notify       = require(script.Parent.Notify)
local Icons        = require(script.Parent.Icons)
local QuestPanel   = require(script.Parent.QuestPanel)
local ClientState  = require(script.Parent.Parent.Controllers.ClientState)

local QuestTracker = {}

local CARD_W = 236
-- Playtest 05.10.: 124 liess "Abholen" und "Tagesbonus" ineinander laufen
local CARD_H = 142

local _card: Frame?          = nil
local _header: TextLabel?    = nil
local _title: TextLabel?     = nil
local _hint: TextLabel?      = nil
local _bar: Theme.Progress?  = nil
local _claim: TextButton?    = nil
local _daily: TextButton?    = nil
local _alert: Frame?         = nil
local _pulse: Tween?         = nil

local function dailyReady(quests: Types.QuestView): (number, number)
	local done, claimable = 0, 0
	for _, entry in quests.daily do
		if entry.claimed then
			done += 1
		elseif entry.progress >= entry.target then
			claimable += 1
		end
	end
	return done, claimable
end

local _bonusOpen = false

-- HBB Paket 2: kompakte Karte (Icon + Zaehler + Belohnungs-Icon). Antippen
-- klappt den Volltext fuer EXPAND_SECONDS auf; ein zweites Antippen oeffnet
-- wie bisher das Quest-Fenster.
local EXPAND_SECONDS = 6
local _expanded = false
local _expandToken = 0
local _questIcon: Frame? = nil
local _reward: Frame? = nil
local _rewardIcon: Frame? = nil
local _rewardLabel: TextLabel? = nil
local _claimCheck: GuiObject? = nil

local function compact(): boolean
	return FeatureFlags.isOn("UI_V2_GUIDE") and not _expanded
end

local function setIcon(holder: Frame?, name: string, fallback: string)
	if not holder then return end
	if holder:GetAttribute("IconName") == name then return end
	holder:SetAttribute("IconName", name)
	for _, child in holder:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	local icon = Icons.make(holder, name, fallback)
	icon.Size = UDim2.fromScale(1, 1)
	icon.ZIndex = 4
end

local function refresh(data: Types.PlayerDataUpdate)
	local quests = data.quests
	local header, title, hint, bar, claim, daily, alert =
		_header, _title, _hint, _bar, _claim, _daily, _alert
	if not quests or not header or not title or not hint or not bar or not claim or not daily or not alert then
		return
	end

	local chain = quests.chain
	if chain then
		local done = chain.progress >= chain.target
		header.Text = Loc.t("ui.quest.header", { done = quests.chainDone + 1, total = quests.chainTotal })
		title.Text  = QuestPanel.title(chain.id)
		hint.Text   = if done then QuestPanel.rewardText(chain.id) else QuestPanel.hint(chain.id)
		hint.TextColor3 = if done then Theme.COLORS.goldGummy else Theme.COLORS.textDim

		bar.track.Visible = not done
		claim.Visible     = done
		bar.fill.Size     = UDim2.fromScale(math.clamp(chain.progress / math.max(1, chain.target), 0, 1), 1)
		bar.text.Text     = Loc.formatNumber(chain.progress) .. " / " .. Loc.formatNumber(chain.target)

		claim:SetAttribute("QuestId", chain.id)
	else
		header.Text = Loc.t("ui.quest.panel_title")
		title.Text  = Loc.t("ui.quest.chain_done")
		hint.Text   = ""
		bar.track.Visible = false
		claim.Visible     = false
	end

	-- HBB Paket 2: kompakte Darstellung
	local isCompact = compact()
	header.Visible = not isCompact
	title.Visible  = not isCompact
	hint.Visible   = not isCompact
	local questIcon, reward, rewardIcon, rewardLabel, check = _questIcon, _reward, _rewardIcon, _rewardLabel, _claimCheck
	if questIcon and reward and rewardLabel and check then
		local def = if chain then QuestConfig.getById(chain.id) else nil
		questIcon.Visible = isCompact and def ~= nil
		reward.Visible    = isCompact and def ~= nil
		check.Visible     = isCompact and claim.Visible
		claim.TextTransparency = if isCompact then 1 else 0
		if def then
			setIcon(questIcon, QuestConfig.METRIC_ICON[def.metric] or "scroll", "?")
			if def.reward.eggType then
				setIcon(rewardIcon, "egg", "EI")
				rewardLabel.Text = "+" .. Loc.formatNumber(def.reward.gummies)
			else
				setIcon(rewardIcon, "gummy", "G")
				rewardLabel.Text = "+" .. Loc.formatNumber(def.reward.gummies)
			end
		end
		-- Der Abholen-Knopf bleibt, wo er ist (sein Puls-Tween setzt die Groesse).
		if isCompact then
			bar.track.Position = UDim2.new(0, 64, 0, 18)
			bar.track.Size     = UDim2.new(1, -74, 0, 22)
		else
			bar.track.Position = UDim2.new(0, 10, 0, 80)
			bar.track.Size     = UDim2.new(1, -20, 0, 18)
		end
	end

	local doneCount, claimable = dailyReady(quests)
	-- v15: ist der Login-Bonus noch nicht abgeholt, zeigt der untere Knopf
	-- darauf (und oeffnet das Bonus-Fenster statt der Quests).
	local bonusOpen = data.daily ~= nil and data.daily.claimable
	_bonusOpen = bonusOpen
	if isCompact then
		-- Nur Zeichen und Zahlen: Geschenk = Login-Bonus, Rolle = Tagesquests
		daily.Text = if bonusOpen then "🎁" else string.format("📜 %d/%d", doneCount, #quests.daily)
	else
		daily.Text = if bonusOpen
			then Loc.t("ui.daily.tracker_hint")
			else Loc.t("ui.quest.daily_link", { done = doneCount, total = #quests.daily })
	end

	-- Rotes "!" am Karten-Rand: irgendetwas ist abholbereit.
	local chainReady = chain ~= nil and chain.progress >= chain.target
	alert.Visible = chainReady or claimable > 0 or bonusOpen
end

function QuestTracker.init(screenGui: ScreenGui)
	local card = Theme.panel("QuestTracker", screenGui, Theme.COLORS.panelDeep)
	card.Position = UDim2.new(0.012, 12, 0, 148)
	card.Size     = UDim2.new(0, CARD_W, 0, CARD_H)
	card.ZIndex   = 2
	_card = card

	-- Die ganze Karte ist antippbar (oeffnet das Quest-Fenster); die Knoepfe
	-- darauf liegen hoeher und fangen ihre eigenen Klicks ab.
	local hit = Instance.new("TextButton")
	hit.Name                   = "Hit"
	hit.BackgroundTransparency = 1
	hit.Text                   = ""
	hit.Size                   = UDim2.fromScale(1, 1)
	hit.ZIndex                 = 2
	hit.Parent                 = card
	hit.Activated:Connect(function()
		-- HBB Paket 2: erst aufklappen (Volltext), dann erst das Fenster
		if compact() then
			_expanded = true
			_expandToken += 1
			local token = _expandToken
			local data = ClientState.get()
			if data then refresh(data) end
			task.delay(EXPAND_SECONDS, function()
				if token ~= _expandToken then return end
				_expanded = false
				local current = ClientState.get()
				if current then refresh(current) end
			end)
			return
		end
		PanelManager.toggle("Quests")
	end)

	-- Schriftrolle links oben, ragt ueber die Ecke der Karte hinaus
	local icon = Icons.make(card, "scroll", "?")
	icon.Position = UDim2.new(0, -10, 0, -12)
	icon.Size     = UDim2.fromOffset(40, 40)
	icon.ZIndex   = 4

	local header = Theme.label("Header", card, "")
	header.Position   = UDim2.new(0, 36, 0, 5)
	header.Size       = UDim2.new(1, -46, 0, 14)
	header.TextColor3 = Theme.COLORS.accent
	_header = header

	local title = Theme.label("Title", card, "")
	title.Position = UDim2.new(0, 36, 0, 20)
	title.Size     = UDim2.new(1, -46, 0, 22)
	Theme.outlineText(title, 2)
	_title = title

	local hint = Theme.bodyText("Hint", card, "")
	hint.Position  = UDim2.new(0, 10, 0, 44)
	hint.Size      = UDim2.new(1, -20, 0, 32)
	hint.TextSize  = 12
	_hint = hint

	local bar = Theme.progress(card, Theme.COLORS.accent)
	bar.track.Position = UDim2.new(0, 10, 0, 80)
	bar.track.Size     = UDim2.new(1, -20, 0, 18)
	bar.text.TextScaled = false
	bar.text.TextSize   = 12
	_bar = bar

	local claim = Theme.bigButton("Claim", card, "", Theme.COLORS.good)
	-- Mittig verankert: das Pulsieren waechst nach beiden Seiten statt nach rechts unten
	claim.AnchorPoint = Vector2.new(0.5, 0)
	claim.Position = UDim2.new(0.5, 0, 0, 78)
	claim.Size     = UDim2.new(1, -20, 0, 28)
	claim.ZIndex   = 3
	claim.Visible  = false
	Loc.bind(claim, "ui.quest.claim")
	_claim = claim
	claim.Activated:Connect(function()
		local id = claim:GetAttribute("QuestId")
		if typeof(id) == "string" then
			Remotes.RequestClaimQuest:FireServer("chain", id)
		end
	end)

	-- Sanftes Pulsieren, damit ein abholbarer Knopf auffaellt.
	_pulse = TweenService:Create(claim, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Size = UDim2.new(1, -14, 0, 30),
	})
	_pulse:Play()

	local daily = Theme.button("Daily", card, "", Theme.COLORS.panelLight)
	daily.Position   = UDim2.new(0, 10, 1, -30)
	daily.Size       = UDim2.new(1, -20, 0, 22)
	daily.TextColor3 = Theme.COLORS.text
	daily.ZIndex     = 3
	_daily = daily
	daily.Activated:Connect(function()
		PanelManager.toggle(if _bonusOpen then "DailyBonus" else "Quests")
	end)

	local alert = Theme.panel("Alert", card, Theme.COLORS.bad)
	alert.AnchorPoint = Vector2.new(1, 0)
	alert.Position    = UDim2.new(1, 6, 0, -6)
	alert.Size        = UDim2.new(0, 22, 0, 22)
	alert.Visible     = false
	alert.ZIndex      = 4
	Theme.corner(alert, 11)
	local bang = Theme.label("Bang", alert, "!")
	bang.Size           = UDim2.fromScale(1, 1)
	bang.TextXAlignment = Enum.TextXAlignment.Center
	bang.ZIndex         = 5
	_alert = alert

	-- HBB Paket 2: Elemente der kompakten Karte
	local questIcon = Theme.container("QuestIcon", card)
	questIcon.Position = UDim2.new(0, 8, 0, 8)
	questIcon.Size     = UDim2.fromOffset(50, 50)
	questIcon.ZIndex   = 3
	questIcon.Visible  = false
	_questIcon = questIcon

	local reward = Theme.container("Reward", card)
	reward.Position = UDim2.new(0, 64, 0, 46)
	reward.Size     = UDim2.new(1, -74, 0, 28)
	reward.ZIndex   = 3
	reward.Visible  = false
	_reward = reward
	local rewardIcon = Theme.container("Icon", reward)
	rewardIcon.Size = UDim2.fromOffset(28, 28)
	_rewardIcon = rewardIcon
	local rewardLabel = Theme.label("Amount", reward, "")
	rewardLabel.Position = UDim2.new(0, 34, 0, 2)
	rewardLabel.Size     = UDim2.new(1, -34, 1, -4)
	rewardLabel.TextColor3 = Theme.COLORS.goldGummy
	Theme.outlineText(rewardLabel, 2)
	_rewardLabel = rewardLabel

	local check = Icons.make(claim, "check", "✓")
	check.AnchorPoint = Vector2.new(0.5, 0.5)
	check.Position    = UDim2.fromScale(0.5, 0.5)
	check.Size        = UDim2.fromOffset(24, 24)
	check.ZIndex      = 4
	check.Visible     = false
	_claimCheck = check

	ClientState.onChanged(refresh)
	Loc.onChanged(function()
		local data = ClientState.get()
		if data then refresh(data) end
	end)

	Remotes.QuestRewardReceived.OnClientEvent:Connect(function(reward: Types.QuestReward)
		-- Gummies und Eier der Quest fliegen ueber den Datenstand.
		Notify.emit("quest_reward", function()
			Toast.success(Loc.t("ui.quest.toast", { text = QuestPanel.rewardText(reward.questId) }))
		end)
	end)

	print("[QuestTracker] Initialisiert")
end

return QuestTracker
