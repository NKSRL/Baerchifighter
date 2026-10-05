--!strict
-- Moment.luau
-- StarterPlayerScripts/UI/Moment.luau
--
-- Einzige Zustaendigkeit:
--   - Seltene, wichtige Ereignisse als grosses Icon in der Bildschirmmitte
--     zeigen (neuer Rekord, Freischaltung, Mutation, Rebirth …)
--
-- Kontext: HBB Paket 1. Hoechstens EIN kurzes Wort, Farbe der Rarity oder
-- des Ereignisses, ein kurzer Klang. Kein Ersatz fuer HatchAnimation: das
-- Schluepfen bleibt, wie es ist.
--
-- Momente kommen nacheinander, nie uebereinander. Die Warteschlange ist kurz
-- (FeedbackConfig.MOMENT_QUEUE); wer mehr ausloest, verliert die aeltesten.

local TweenService      = game:GetService("TweenService")
local SoundService      = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loc            = require(ReplicatedStorage.Localization.Loc)
local FeedbackConfig = require(ReplicatedStorage.Config.FeedbackConfig)
local FeatureFlags   = require(ReplicatedStorage.Config.FeatureFlags)

local Theme = require(script.Parent.Theme)
local Icons = require(script.Parent.Icons)

local Moment = {}

-- Art → Icon. Unbekannte Arten bekommen den Stern.
local ICON_FOR: { [string]: string } = {
	record    = "trophy",
	milestone = "trophy",
	unlock    = "tree",
	rebirth   = "rebirth",
	mutation  = "bear",
	rarity    = "crown",
	jackpot   = "egg",
	slot      = "check",
	boss      = "swords",
	chest     = "gift",
}

local ICON_SIZE = 150

type Job = { kind: string, color: Color3, shortKey: string? }

local _root: Frame? = nil
local _ring: Frame? = nil
local _iconHolder: Frame? = nil
local _word: TextLabel? = nil
local _scale: UIScale? = nil
local _queue: { Job } = {}
local _running = false

local function playSound()
	local sound = Instance.new("Sound")
	sound.SoundId = FeedbackConfig.MOMENT_SOUND
	sound.Volume  = FeedbackConfig.MOMENT_VOLUME
	SoundService:PlayLocalSound(sound)
	task.delay(3, function()
		sound:Destroy()
	end)
end

local function showOne(job: Job)
	local root, ring, holder, word, scale = _root, _ring, _iconHolder, _word, _scale
	if not root or not ring or not holder or not word or not scale then return end

	for _, child in holder:GetChildren() do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	local icon = Icons.make(holder, ICON_FOR[job.kind] or "", "★")
	icon.Size = UDim2.fromScale(1, 1)
	icon.ZIndex = 72

	ring.BackgroundColor3 = job.color
	word.Text = if job.shortKey then Loc.t(job.shortKey) else ""
	word.TextColor3 = job.color
	word.Visible = job.shortKey ~= nil

	root.Visible = true
	ring.BackgroundTransparency = 0.25
	word.TextTransparency = 0
	scale.Scale = 0.2
	playSound()

	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.wait(FeedbackConfig.MOMENT_SECONDS)
	local fadeTime = 0.3
	TweenService:Create(scale, TweenInfo.new(fadeTime), { Scale = 1.25 }):Play()
	TweenService:Create(ring, TweenInfo.new(fadeTime), { BackgroundTransparency = 1 }):Play()
	TweenService:Create(word, TweenInfo.new(fadeTime), { TextTransparency = 1 }):Play()
	if icon:IsA("ImageLabel") then
		TweenService:Create(icon, TweenInfo.new(fadeTime), { ImageTransparency = 1 }):Play()
	end
	task.wait(fadeTime)
	root.Visible = false
end

local function run()
	_running = true
	while #_queue > 0 do
		local job = table.remove(_queue, 1)
		if not job then break end
		showOne(job)
	end
	_running = false
end

-- kind: siehe ICON_FOR. color: Rarity-/Ereignisfarbe. shortKey: optionaler
-- Loc-Schluessel fuer EIN Wort (ui.moment.*).
function Moment.show(kind: string, color: Color3, shortKey: string?)
	if not FeatureFlags.isOn("UI_V2_FEEDBACK") then return end
	while #_queue >= FeedbackConfig.MOMENT_QUEUE do
		table.remove(_queue, 1)
	end
	table.insert(_queue, { kind = kind, color = color, shortKey = shortKey })
	if not _running then
		task.spawn(run)
	end
end

function Moment.init(screenGui: ScreenGui)
	local root = Theme.container("Moment", screenGui)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.42)
	root.Size = UDim2.fromOffset(ICON_SIZE + 60, ICON_SIZE + 110)
	root.ZIndex = 70
	root.Visible = false

	local scale = Instance.new("UIScale")
	scale.Parent = root

	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(0.5, 0)
	ring.Position = UDim2.new(0.5, 0, 0, 0)
	ring.Size = UDim2.fromOffset(ICON_SIZE + 50, ICON_SIZE + 50)
	ring.BorderSizePixel = 0
	ring.ZIndex = 70
	ring.Parent = root
	Theme.corner(ring, (ICON_SIZE + 50) // 2)
	Theme.stroke(ring, Theme.COLORS.outline, 4)

	local holder = Theme.container("Icon", ring)
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromOffset(ICON_SIZE, ICON_SIZE)
	holder.ZIndex = 71

	local word = Theme.label("Word", root, "")
	word.AnchorPoint = Vector2.new(0.5, 1)
	word.Position = UDim2.new(0.5, 0, 1, 0)
	word.Size = UDim2.new(1, 80, 0, 50)
	word.TextXAlignment = Enum.TextXAlignment.Center
	word.ZIndex = 72
	Theme.outlineText(word, 3)
	local limit = word:FindFirstChildOfClass("UITextSizeConstraint")
	if limit then limit.MaxTextSize = 44 end

	_root, _ring, _iconHolder, _word, _scale = root, ring, holder, word, scale
	print("[Moment] Initialisiert")
end

return Moment
