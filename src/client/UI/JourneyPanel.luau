--!strict
-- JourneyPanel.luau
-- StarterPlayerScripts/UI/JourneyPanel.luau
--
-- Einzige Zustaendigkeit:
--   - Die "Reise" (P3): kleine, einklappbare Ziel-Leiste mit der aktuellen Etappe
--     (ein Satz, Fortschrittsbalken, Abholen-Knopf, "Spaeter") und der Etappen-Reihe.
--
-- Der Client rechnet nichts: Etappe und Fortschritt kommen aus OnboardingRules ueber den
-- Server-Stand (ClientState). Abholen/Ueberspringen/Ausblenden sind nur Anfragen an den
-- Server (Remotes.RequestJourney); der entscheidet. Kein Dauer-Loop: Aktualisierung nur bei
-- ClientState.onChanged. Kein Modal, nicht gesperrt.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local Remotes          = require(ReplicatedStorage.Network.Remotes)
local Loc              = require(ReplicatedStorage.Localization.Loc)
local FeatureFlags     = require(ReplicatedStorage.Config.FeatureFlags)
local OnboardingConfig = require(ReplicatedStorage.Config.OnboardingConfig)
local OnboardingRules  = require(ReplicatedStorage.Modules.OnboardingRules)

local Theme       = require(script.Parent.Theme)
local Icons       = require(script.Parent.Icons)
local ClientState = require(script.Parent.Parent.Controllers.ClientState)

local JourneyPanel = {}

local WIDTH, HEIGHT_OPEN, HEIGHT_CLOSED = 250, 118, 40

local _root: Frame? = nil
local _body: Frame? = nil
local _title: TextLabel? = nil
local _text: TextLabel? = nil
local _bar: Theme.Progress? = nil
local _claim: TextButton? = nil
local _skip: TextButton? = nil
local _toggle: TextButton? = nil
local _iconHolder: Frame? = nil
local _dots: { Frame } = {}
local _collapsed = false
local _lastStageId: string? = nil

local function setIcon(name: string)
	local holder = _iconHolder
	if not holder or holder:GetAttribute("IconName") == name then return end
	holder:SetAttribute("IconName", name)
	for _, child in holder:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	local icon = Icons.make(holder, name, "?")
	icon.Size = UDim2.fromScale(1, 1)
end

local function applySize(animate: boolean)
	local root, body = _root, _body
	if not root or not body then return end
	body.Visible = not _collapsed
	local goal = UDim2.fromOffset(WIDTH, if _collapsed then HEIGHT_CLOSED else HEIGHT_OPEN)
	if animate then
		TweenService:Create(root, TweenInfo.new(OnboardingConfig.PANEL_TWEEN_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = goal }):Play()
	else
		root.Size = goal
	end
	if _toggle then _toggle.Text = if _collapsed then "+" else "–" end
end

local function refresh(data: any)
	local root = _root
	if not root then return end
	if not FeatureFlags.isOn("ONBOARDING_V2") or not FeatureFlags.isOn("UI_V2_GUIDE") then
		root.Visible = false
		return
	end
	local journey = OnboardingRules.sanitize(data.journey)
	local id, index, done = OnboardingRules.current(data, journey)
	if journey.hidden or id == nil then
		root.Visible = false
		return
	end
	root.Visible = true

	local stage = OnboardingConfig.STAGES[index]
	local title, text, bar, claim, skip = _title, _text, _bar, _claim, _skip
	if not stage or not title or not text or not bar or not claim or not skip then return end

	title.Text = Loc.t("ui.journey.title") .. " · " .. Loc.t("ui.journey.step", { n = index, total = OnboardingConfig.MAX_STAGE })
	text.Text = Loc.t(stage.textKey)
	local cur, target = OnboardingRules.progress(id, data)
	bar.fill.Size = UDim2.fromScale(math.clamp(cur / math.max(1, target), 0, 1), 1)
	bar.fill.BackgroundColor3 = stage.accent
	bar.text.Text = if target > 1 then (Loc.formatNumber(cur) .. " / " .. Loc.formatNumber(target)) else ""
	claim.Visible = done
	claim.Text = Loc.t("ui.journey.claim") .. " +" .. tostring(stage.reward.goldGummies or stage.reward.gummies or 0)
	-- 21.10. Playtest: Kein "Spaeter"-Knopf. Wer eine Etappe wegklickt, kommt nie wieder zu ihr
	-- zurueck. Der Server versteht "skip" weiterhin (nichts geloescht), der Knopf wird nur nicht
	-- mehr gezeigt.
	skip.Visible = false
	claim:SetAttribute("StageId", id)
	skip:SetAttribute("StageId", id)
	setIcon(stage.icon)

	for i, dot in _dots do
		local s = OnboardingConfig.STAGES[i]
		local over = journey.claimed[s.id] == true
		dot.BackgroundColor3 = if over then s.accent elseif i == index then Theme.COLORS.text else Theme.COLORS.panelDeep
	end

	if _lastStageId ~= id then
		_lastStageId = id
		-- weiche Einblendung bei neuer Etappe (Quad, 0,3 s)
		root.BackgroundTransparency = 0.6
		TweenService:Create(root, TweenInfo.new(OnboardingConfig.PANEL_TWEEN_SECONDS, Enum.EasingStyle.Quad), { BackgroundTransparency = 0 }):Play()
	end
end

function JourneyPanel.init(screenGui: ScreenGui)
	if _root then return end
	local root = Theme.panel("JourneyPanel", screenGui, Theme.COLORS.panel)
	root.AnchorPoint = Vector2.new(0, 0.5)
	-- 21.10. (Playtest 2): tiefer, damit das Fenster nicht in die Knopf-Zeile oben ragt
	root.Position = UDim2.new(0, 12, 0.5, 100)
	root.Size = UDim2.fromOffset(WIDTH, HEIGHT_OPEN)
	root.Visible = false
	root.ZIndex = 5
	_root = root

	-- Kopfzeile: Icon, Titel, Einklappen, Ausblenden (je >= 44 px Trefferflaeche reicht fuer Touch ueber die Zeile)
	local iconHolder = Instance.new("Frame")
	iconHolder.Name = "Icon"
	iconHolder.BackgroundTransparency = 1
	iconHolder.Position = UDim2.fromOffset(6, 4)
	iconHolder.Size = UDim2.fromOffset(32, 32)
	iconHolder.Parent = root
	_iconHolder = iconHolder

	local title = Theme.label("Title", root, "")
	title.Position = UDim2.fromOffset(44, 4)
	title.Size = UDim2.new(1, -44 - 56, 0, 32)
	_title = title

	local toggle = Theme.button("Toggle", root, "–", Theme.COLORS.panelLight)
	toggle.Size = UDim2.fromOffset(40, 32)
	toggle.Position = UDim2.new(1, -86, 0, 4)
	toggle.MouseButton1Click:Connect(function()
		_collapsed = not _collapsed
		applySize(true)
	end)
	_toggle = toggle
	-- 21.10. (Playtest 2): kein Minimieren-Knopf, nur Schliessen (Code bleibt, Knopf ist aus)
	toggle.Visible = false
	_collapsed = false

	-- Ausblenden: Schliessen-Knopf (Server merkt es, bleibt nach Rejoin erhalten)
	local hide = Theme.closeButton(root, function()
		Remotes.RequestJourney:FireServer("hide")
	end)
	hide.Position = UDim2.new(1, -2, 0, 20)

	local body = Instance.new("Frame")
	body.Name = "Body"
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(0, 40)
	body.Size = UDim2.new(1, 0, 1, -40)
	body.Parent = root
	_body = body

	local text = Theme.bodyText("Text", body, "")
	text.Position = UDim2.fromOffset(8, 0)
	text.Size = UDim2.new(1, -16, 0, 34)
	_text = text

	local bar = Theme.progress(body, Theme.COLORS.accent)
	bar.track.Position = UDim2.fromOffset(8, 38)
	bar.track.Size = UDim2.new(1, -16 - 96, 0, 22)
	_bar = bar

	local claim = Theme.button("Claim", body, "", Theme.COLORS.goldGummy)
	claim.Position = UDim2.new(1, -8 - 88, 0, 34)
	claim.Size = UDim2.fromOffset(88, 30)
	claim.Visible = false
	claim.MouseButton1Click:Connect(function()
		local id = claim:GetAttribute("StageId")
		if typeof(id) == "string" then Remotes.RequestJourney:FireServer("claim", id) end
	end)
	_claim = claim

	local skip = Theme.button("Skip", body, Loc.t("ui.journey.skip"), Theme.COLORS.panelLight)
	skip.Position = UDim2.new(1, -8 - 88, 0, 34)
	skip.Size = UDim2.fromOffset(88, 30)
	skip.MouseButton1Click:Connect(function()
		local id = skip:GetAttribute("StageId")
		if typeof(id) == "string" then Remotes.RequestJourney:FireServer("skip", id) end
	end)
	_skip = skip

	-- Etappen-Punkte
	local dotRow = Instance.new("Frame")
	dotRow.Name = "Dots"
	dotRow.BackgroundTransparency = 1
	dotRow.Position = UDim2.fromOffset(8, 70)
	dotRow.Size = UDim2.new(1, -16, 0, 10)
	dotRow.Parent = body
	local layout = Theme.listLayout(dotRow, 6, true)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	for i = 1, OnboardingConfig.MAX_STAGE do
		local dot = Instance.new("Frame")
		dot.Name = "Dot" .. i
		dot.Size = UDim2.fromOffset(10, 10)
		dot.BackgroundColor3 = Theme.COLORS.panelDeep
		dot.BorderSizePixel = 0
		dot.LayoutOrder = i
		dot.Parent = dotRow
		Theme.corner(dot, 5)
		table.insert(_dots, dot)
	end

	applySize(false)
	ClientState.onChanged(refresh)
	local current = ClientState.get()
	if current then refresh(current) end
end

return JourneyPanel
