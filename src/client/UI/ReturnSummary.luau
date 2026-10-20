--!strict
-- ReturnSummary.luau
-- StarterPlayerScripts/UI/ReturnSummary.luau
--
-- Einzige Zustaendigkeit:
--   - Beim Zurueckkommen zeigen, was in der Abwesenheit entstanden ist:
--     Uhr + Dauer, Ei + Anzahl, Honig + Anzahl. Nur Icons und Zahlen.
--
-- Kontext: HBB Paket 1. Das ist der wichtigste Moment fuer die Rueckkehr an
-- Tag 2: "Dein Baerchi hat weitergemacht, waehrend du weg warst."
--
-- Die zwei Berichte (OfflineReportReceived fuer Honig, OfflineEggReportReceived
-- fuer Eier) kommen getrennt. Die Karte sammelt beide kurz und erscheint dann
-- einmal. Antippen schliesst sie, sonst verschwindet sie von selbst.

local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loc            = require(ReplicatedStorage.Localization.Loc)
local FeedbackConfig = require(ReplicatedStorage.Config.FeedbackConfig)

local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)

local ReturnSummary = {}

local ROW_H = 46

local _screenGui: ScreenGui? = nil
local _pending = { seconds = 0, honey = 0, eggs = 0 }
local _scheduled = false

local function addRow(parent: Instance, order: number, iconName: string, fallback: string, text: string)
	local row = Theme.container("Row", parent)
	row.Size = UDim2.new(1, 0, 0, ROW_H)
	row.LayoutOrder = order

	local icon = Icons.make(row, iconName, fallback)
	icon.Size = UDim2.fromOffset(ROW_H - 4, ROW_H - 4)
	icon.Position = UDim2.fromOffset(4, 2)

	local value = Theme.label("Value", row, text)
	value.Position = UDim2.fromOffset(ROW_H + 10, 4)
	value.Size = UDim2.new(1, -(ROW_H + 14), 1, -8)
	Theme.outlineText(value, 2)
end

-- 14.10. (UI_HONEY_SKIN): Karte = fertiges Bild (Wecker-Zeile, Honigglas-Zeile), unverzerrt.
-- Anteile der Bildbreite/-hoehe (1397x906): Zahlenfeld rechts neben dem weissen Plus.
local PANEL_W = 380
local PANEL_H = math.floor(PANEL_W * 906 / 1397 + 0.5)
local BROWN = Color3.fromRGB(110, 70, 36)

local function honeyLabel(parent: Instance, x: number, y: number, w: number, h: number, text: string): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.FredokaOne
	l.Text = text
	l.TextColor3 = BROWN
	l.TextScaled = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Position = UDim2.fromScale(x, y)
	l.Size = UDim2.fromScale(w, h)
	l.ZIndex = 57
	local cap = Instance.new("UITextSizeConstraint")
	cap.MaxTextSize = 34
	cap.Parent = l
	l.Parent = parent
	return l
end

local function showHoney(gui: ScreenGui, report: { seconds: number, honey: number, eggs: number })
	local card = Instance.new("Frame")
	card.Name = "ReturnSummary"
	card.BackgroundTransparency = 1
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, 70)
	card.Size = UDim2.fromOffset(PANEL_W, PANEL_H)
	card.ZIndex = 55
	card.Parent = gui

	local art = Instance.new("ImageLabel")
	art.Name = "HoneySkin"
	art.BackgroundTransparency = 1
	art.Image = Icons.ui("honey/currency_panel") :: string
	art.ScaleType = Enum.ScaleType.Stretch
	art.Size = UDim2.fromScale(1, 1)
	art.ZIndex = 56
	art.Parent = card

	-- Zeile 1: Dauer (Wecker ist im Bild)
	honeyLabel(card, 0.50, 0.28, 0.32, 0.25, Loc.formatDuration(report.seconds))
	-- Zeile 2: Honig; Eier rechts daneben, wenn es welche gibt
	local honeyW = if report.eggs > 0 then 0.17 else 0.32
	honeyLabel(card, 0.50, 0.57, honeyW, 0.25, report.honey > 0 and Loc.formatNumber(report.honey) or "0")
	if report.eggs > 0 then
		local egg = Icons.make(card, "egg", "E")
		egg.AnchorPoint = Vector2.new(0, 0.5)
		egg.Position = UDim2.fromScale(0.67, 0.695)
		egg.Size = UDim2.fromScale(0.09, 0.14)
		if egg:IsA("ImageLabel") then egg.ScaleType = Enum.ScaleType.Fit end
		egg.ZIndex = 57
		honeyLabel(card, 0.76, 0.57, 0.09, 0.25, "+" .. Loc.formatNumber(report.eggs))
	end

	local hit = Instance.new("TextButton")
	hit.Name = "Close"
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 60
	hit.Parent = card

	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = card
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	local closed = false
	local function close()
		if closed then return end
		closed = true
		local tween = TweenService:Create(scale, TweenInfo.new(0.2), { Scale = 0 })
		tween:Play()
		tween.Completed:Wait()
		card:Destroy()
	end
	hit.Activated:Connect(close)
	task.delay(FeedbackConfig.RETURN_SHOW_SECONDS, close)
end

local function show()
	_scheduled = false
	local gui = _screenGui
	if not gui then return end
	local report = _pending
	_pending = { seconds = 0, honey = 0, eggs = 0 }
	if report.honey <= 0 and report.eggs <= 0 then return end

	local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)
	if FeatureFlags.isOn("UI_HONEY_SKIN") and Icons.hasUi("honey/currency_panel") then
		showHoney(gui, report)
		return
	end

	local rows = 1 + (if report.eggs > 0 then 1 else 0) + (if report.honey > 0 then 1 else 0)

	local card = Theme.panel("ReturnSummary", gui, Theme.COLORS.panelDeep)
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, 70)
	card.Size = UDim2.fromOffset(220, rows * (ROW_H + 6) + 16)
	card.ZIndex = 55
	Theme.padding(card, 8)

	-- Zeilen in einem eigenen Rahmen, damit das Listen-Layout den
	-- Schliessen-Knopf darueber nicht mit anordnet.
	local list = Theme.container("Rows", card)
	list.Size = UDim2.fromScale(1, 1)
	Theme.listLayout(list, 6)

	-- Die ganze Karte ist der Schliessen-Knopf: Kinder tippen sie einfach weg.
	local hit = Instance.new("TextButton")
	hit.Name = "Close"
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.Size = UDim2.fromScale(1, 1)
	hit.ZIndex = 60
	hit.Parent = card

	-- Uhr gibt es nicht als Bild; das Kuerzel ist sprachneutral.
	addRow(list, 1, "", "⏱", Loc.formatDuration(report.seconds))
	if report.eggs > 0 then
		addRow(list, 2, "egg", "🥚", "+" .. Loc.formatNumber(report.eggs))
	end
	if report.honey > 0 then
		addRow(list, 3, "honey", "H", "+" .. Loc.formatNumber(report.honey))
	end

	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = card
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()

	local closed = false
	local function close()
		if closed then return end
		closed = true
		local tween = TweenService:Create(scale, TweenInfo.new(0.2), { Scale = 0 })
		tween:Play()
		tween.Completed:Wait()
		card:Destroy()
	end
	hit.Activated:Connect(close)
	task.delay(FeedbackConfig.RETURN_SHOW_SECONDS, close)
end

local function schedule()
	if _scheduled then return end
	_scheduled = true
	task.delay(FeedbackConfig.RETURN_COLLECT_SECONDS, show)
end

function ReturnSummary.addHoney(secondsAway: number, honey: number)
	_pending.seconds = math.max(_pending.seconds, secondsAway)
	_pending.honey += honey
	schedule()
end

function ReturnSummary.addEggs(secondsAway: number, eggs: number)
	_pending.seconds = math.max(_pending.seconds, secondsAway)
	_pending.eggs += eggs
	schedule()
end

function ReturnSummary.init(screenGui: ScreenGui)
	_screenGui = screenGui
end

return ReturnSummary
