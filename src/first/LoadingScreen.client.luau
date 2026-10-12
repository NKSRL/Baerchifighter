--!strict
-- LoadingScreen.client.luau
-- ReplicatedFirst/LoadingScreen.client.luau
--
-- Einzige Zustaendigkeit:
--   - 12.10. (Playtest): eigener Ladebildschirm ab der ersten Sekunde, bis
--     die eigene Insel steht und die Oberflaeche bereit ist. Vorher sahen die
--     Kinder Roblox' grauen Standard-Bildschirm und danach eine Welt, die
--     sich vor ihren Augen zusammenbaut (Gras, Inseln, Deko) — der Moment, in
--     dem sie das Spiel wieder schliessen.
--
-- Warum ReplicatedFirst: nur Skripte hier laufen, BEVOR die Welt geladen
-- ist. Deshalb darf am Anfang nichts aus ReplicatedStorage gebraucht werden:
-- Hintergrund, Bärchi-Bild und Balken kommen sofort, die Texte (ueber Loc,
-- in der Sprache des Spielers) erscheinen, sobald ReplicatedStorage da ist.
--
-- Fertig ist es, wenn ALLES da ist (Reihenfolge = Balken-Schritte):
--   1. game:IsLoaded()
--   2. die eigene Insel (workspace.Plot_N mit PlotOwner = ich)
--   3. der eigene Charakter
--   4. die Oberflaeche (Player-Attribut HBB_ClientReady, gesetzt von Main)
--   5. die wichtigsten Bilder (ContentProvider:PreloadAsync)
-- danach SETTLE_SECONDS Ruhe (Client-Deko baut sich hinter dem Bild auf),
-- dann weiches Ausblenden. Sicherheitsnetz: nach MAX_SECONDS geht es in
-- jedem Fall los — lieber eine halb fertige Welt als ein Kind, das wartet.

local Players           = game:GetService("Players")
local ReplicatedFirst   = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local ContentProvider   = game:GetService("ContentProvider")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

local MIN_SECONDS    = 2.0    -- so lange steht er mindestens (kein Flackern)
local SETTLE_SECONDS = 1.5    -- nach "alles da": Deko baut sich dahinter auf
local MAX_SECONDS    = 30     -- Sicherheitsnetz
local FADE_SECONDS   = 0.6
local STEPS          = 5

-- Dieselben IDs wie UI/Icons (bear, honey, gummy): StarterPlayerScripts gibt
-- es hier noch nicht.
local BEAR_IMAGE  = "rbxassetid://122776209368174"
local PRELOAD     = {
	"rbxassetid://122776209368174",   -- bear
	"rbxassetid://73136954746111",    -- honey
	"rbxassetid://119048609020329",   -- gummy
	"rbxassetid://136964848925363",   -- egg
	"rbxassetid://138272803014747",   -- swords
	"rbxassetid://75799134348421",    -- ufo
}

-- Farben wie Theme.v2 (Honig, Creme, Schoko)
local HONEY_TOP    = Color3.fromRGB(255, 214, 100)
local HONEY_BOTTOM = Color3.fromRGB(255, 152, 24)
local CREAM        = Color3.fromRGB(255, 244, 220)
local INK          = Color3.fromRGB(74, 44, 23)
local GO           = Color3.fromRGB(72, 196, 70)

--------------------------------------------------------------------------------
-- Aufbau (sofort, ohne ReplicatedStorage)
--------------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "HBBLoading"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local root = Instance.new("CanvasGroup")
root.Name = "Root"
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = Color3.new(1, 1, 1)
root.BorderSizePixel = 0
root.Parent = gui
local bgGradient = Instance.new("UIGradient")
bgGradient.Rotation = 90
bgGradient.Color = ColorSequence.new(HONEY_TOP, HONEY_BOTTOM)
bgGradient.Parent = root

local function corner(parent: Instance, radius: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius)
	c.Parent = parent
end

local function stroke(parent: Instance, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = INK
	s.Thickness = thickness
	s.Parent = parent
	return s
end

-- Waben-Muster im Hintergrund: ein paar weiche, langsam steigende Waben
local bubbles: { { frame: Frame, speed: number, x: number, phase: number } } = {}
local random = Random.new(7)
for i = 1, 14 do
	local size = random:NextInteger(40, 110)
	local bubble = Instance.new("Frame")
	bubble.Name = "Comb" .. i
	bubble.AnchorPoint = Vector2.new(0.5, 0.5)
	bubble.Size = UDim2.fromOffset(size, size)
	bubble.Rotation = 30
	bubble.BackgroundColor3 = Color3.new(1, 1, 1)
	bubble.BackgroundTransparency = 0.8
	bubble.BorderSizePixel = 0
	bubble.Parent = root
	corner(bubble, math.floor(size * 0.28))
	table.insert(bubbles, { frame = bubble, speed = random:NextNumber(0.025, 0.06), x = random:NextNumber(0.03, 0.97), phase = random:NextNumber(0, 1) })
end

-- Alles Sichtbare in EINEM Block fester Groesse (DESIGN), der mit dem
-- Bildschirm skaliert: so bleibt die Anordnung am Handy quer genauso wie am
-- Monitor, nur kleiner (nichts schiebt sich uebereinander).
local DESIGN = Vector2.new(720, 640)
local block = Instance.new("Frame")
block.Name = "Block"
block.AnchorPoint = Vector2.new(0.5, 0.5)
block.Position = UDim2.fromScale(0.5, 0.5)
block.Size = UDim2.fromOffset(DESIGN.X, DESIGN.Y)
block.BackgroundTransparency = 1
block.Parent = root
local fit = Instance.new("UIScale")
fit.Parent = block
local function refit()
	local screen = gui.AbsoluteSize
	if screen.X <= 0 or screen.Y <= 0 then return end
	fit.Scale = math.clamp(math.min(screen.X * 0.92 / DESIGN.X, screen.Y * 0.92 / DESIGN.Y), 0.35, 1.6)
end
gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
refit()

-- Mitte: Bärchi auf einer Creme-Scheibe, hüpft
local center = Instance.new("Frame")
center.Name = "Center"
center.AnchorPoint = Vector2.new(0.5, 0)
center.Position = UDim2.fromOffset(DESIGN.X * 0.5, 20)
center.Size = UDim2.fromOffset(220, 220)
center.BackgroundColor3 = CREAM
center.BorderSizePixel = 0
center.Parent = block
corner(center, 110)
stroke(center, 6)
local bear = Instance.new("ImageLabel")
bear.Name = "Bear"
bear.AnchorPoint = Vector2.new(0.5, 0.5)
bear.Position = UDim2.fromScale(0.5, 0.5)
bear.Size = UDim2.fromScale(0.78, 0.78)
bear.BackgroundTransparency = 1
bear.Image = BEAR_IMAGE
bear.ScaleType = Enum.ScaleType.Fit
bear.Parent = center
local scale = Instance.new("UIScale")
scale.Parent = center

local function label(name: string, size: number, y: number, height: number): TextLabel
	local text = Instance.new("TextLabel")
	text.Name = name
	text.AnchorPoint = Vector2.new(0.5, 0)
	text.Position = UDim2.new(0.5, 0, 0, y)
	text.Size = UDim2.new(1, 0, 0, height)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.new(1, 1, 1)
	text.Text = ""
	text.Parent = block
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = size
	limit.Parent = text
	stroke(text, 4).ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	return text
end

local title  = label("Title", 64, 270, 72)
local status = label("Status", 32, 356, 40)
local tip    = label("Tip", 26, 470, 70)
tip.TextWrapped = true

-- Balken: Creme-Rinne mit grünem Füllstand (wie im Tower-Panel)
local track = Instance.new("Frame")
track.Name = "Track"
track.AnchorPoint = Vector2.new(0.5, 0)
track.Position = UDim2.new(0.5, 0, 0, 412)
track.Size = UDim2.fromOffset(520, 30)
track.BackgroundColor3 = CREAM
track.BorderSizePixel = 0
track.Parent = block
corner(track, 15)
stroke(track, 4)
local fill = Instance.new("Frame")
fill.Name = "Fill"
fill.Size = UDim2.fromScale(0.02, 1)
fill.BackgroundColor3 = GO
fill.BorderSizePixel = 0
fill.Parent = track
corner(fill, 14)

--------------------------------------------------------------------------------
-- Fortschritt
--------------------------------------------------------------------------------

local startedAt = os.clock()
local done = 0            -- erledigte Schritte (0..STEPS)
local shown = 0.02        -- angezeigter Balken (weich hinterher)
local statusKey = "ui.loading.world"
local finished = false

-- Texte: erst wenn ReplicatedStorage (Loc) da ist
local Loc: any = nil
local tipIndex = 1
local TIP_COUNT = 4
local lastTipAt = 0

local function refreshTexts()
	if not Loc then return end
	title.Text = Loc.t("ui.loading.title")
	status.Text = Loc.t(statusKey)
	tip.Text = Loc.t("ui.loading.tip" .. tipIndex)
end

task.spawn(function()
	local localization = ReplicatedStorage:WaitForChild("Localization", MAX_SECONDS)
	local module = localization and localization:WaitForChild("Loc", MAX_SECONDS)
	if module and module:IsA("ModuleScript") then
		local ok, result = pcall(require, module)
		if ok then
			Loc = result
			-- Sprache des Geraets, bis der Spielstand seine eigene meldet
			pcall(function()
				local code = result.fromLocaleId(localPlayer.LocaleId)
				if code then result.setLanguage(code) end
			end)
			refreshTexts()
		end
	end
end)

local function step(key: string)
	done = math.min(STEPS, done + 1)
	statusKey = key
	refreshTexts()
end

local function ownPlot(): Instance?
	for _, child in workspace:GetChildren() do
		if string.match(child.Name, "^Plot_%d+$") and child:GetAttribute("PlotOwner") == localPlayer.UserId then
			return child
		end
	end
	return nil
end

local function waitUntil(check: () -> boolean)
	while not check() and os.clock() - startedAt < MAX_SECONDS do
		task.wait(0.1)
	end
end

-- Bewegung: Bärchi hüpft, Waben steigen, Balken läuft weich nach.
-- Der Balken kriecht auch zwischen zwei Schritten langsam weiter (nie
-- ganz bis zum naechsten), damit er nie "haengt".
local connection = RunService.RenderStepped:Connect(function(dt)
	local t = os.clock() - startedAt
	scale.Scale = 1 + math.abs(math.sin(t * 3)) * 0.06
	bear.Rotation = math.sin(t * 2) * 6
	for _, b in bubbles do
		local y = 1.1 - ((t * b.speed + b.phase) % 1.2)
		b.frame.Position = UDim2.fromScale(b.x + math.sin(t + b.phase * 6) * 0.01, y)
	end
	local target = if finished then 1 else math.min((done + 0.85) / STEPS, done / STEPS + (t % 30) / 30 * 0.18)
	shown += (math.max(shown, target) - shown) * math.min(1, dt * 4)
	fill.Size = UDim2.fromScale(math.clamp(shown, 0.02, 1), 1)
	if Loc and t - lastTipAt > 4 then
		lastTipAt = t
		tipIndex = tipIndex % TIP_COUNT + 1
		tip.Text = Loc.t("ui.loading.tip" .. tipIndex)
	end
end)

--------------------------------------------------------------------------------
-- Ablauf
--------------------------------------------------------------------------------

if not game:IsLoaded() then
	game.Loaded:Wait()
end
step("ui.loading.island")

waitUntil(function() return ownPlot() ~= nil end)
step("ui.loading.bear")

waitUntil(function()
	local character = localPlayer.Character
	return character ~= nil and character:FindFirstChild("HumanoidRootPart") ~= nil
end)
step("ui.loading.ui")

waitUntil(function() return localPlayer:GetAttribute("HBB_ClientReady") == true end)
step("ui.loading.images")

pcall(function()
	ContentProvider:PreloadAsync(PRELOAD)
end)
step("ui.loading.ready")

-- Kurz Ruhe: die Client-Deko (Inseln, Gras, Leben) baut sich hinter dem Bild auf
task.wait(SETTLE_SECONDS)
local rest = MIN_SECONDS - (os.clock() - startedAt)
if rest > 0 then task.wait(rest) end

finished = true
task.wait(0.35)   -- Balken voll zeigen
local fade = TweenService:Create(root, TweenInfo.new(FADE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { GroupTransparency = 1 })
fade:Play()
fade.Completed:Wait()
connection:Disconnect()
gui:Destroy()
