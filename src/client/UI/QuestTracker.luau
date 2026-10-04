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

local Theme        = require(script.Parent.Theme)
local PanelManager = require(script.Parent.PanelManager)
local Toast        = require(script.Parent.Toast)
local QuestPanel   = require(script.Parent.QuestPanel)
local ClientState  = require(script.Parent.Parent.Controllers.ClientState)

local QuestTracker = {}

local CARD_W = 236
local CARD_H = 124

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

	local doneCount, claimable = dailyReady(quests)
	daily.Text = Loc.t("ui.quest.daily_link", { done = doneCount, total = #quests.daily })

	-- Rotes "!" am Karten-Rand: irgendetwas ist abholbereit.
	local chainReady = chain ~= nil and chain.progress >= chain.target
	alert.Visible = chainReady or claimable > 0
end

function QuestTracker.init(screenGui: ScreenGui)
	local card = Theme.panel("QuestTracker", screenGui, Theme.COLORS.panelDeep)
	card.Position = UDim2.new(0.012, 0, 0, 136)
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
		PanelManager.toggle("Quests")
	end)

	local header = Theme.label("Header", card, "")
	header.Position   = UDim2.new(0, 10, 0, 5)
	header.Size       = UDim2.new(1, -20, 0, 14)
	header.TextColor3 = Theme.COLORS.accent
	_header = header

	local title = Theme.label("Title", card, "")
	title.Position = UDim2.new(0, 10, 0, 20)
	title.Size     = UDim2.new(1, -20, 0, 22)
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
	claim.Position = UDim2.new(0, 10, 0, 76)
	claim.Size     = UDim2.new(1, -20, 0, 26)
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
		Size = UDim2.new(1, -14, 0, 28),
	})
	_pulse:Play()

	local daily = Theme.button("Daily", card, "", Theme.COLORS.panelLight)
	daily.Position   = UDim2.new(0, 10, 1, -24)
	daily.Size       = UDim2.new(1, -20, 0, 20)
	daily.TextColor3 = Theme.COLORS.text
	daily.ZIndex     = 3
	_daily = daily
	daily.Activated:Connect(function()
		PanelManager.toggle("Quests")
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

	ClientState.onChanged(refresh)
	Loc.onChanged(function()
		local data = ClientState.get()
		if data then refresh(data) end
	end)

	Remotes.QuestRewardReceived.OnClientEvent:Connect(function(reward: Types.QuestReward)
		Toast.success(Loc.t("ui.quest.toast", { text = QuestPanel.rewardText(reward.questId) }))
	end)

	print("[QuestTracker] Initialisiert")
end

return QuestTracker
