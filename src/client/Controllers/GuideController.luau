--!strict
-- GuideController.luau
-- StarterPlayerScripts/Controllers/GuideController.luau
--
-- Einzige Zustaendigkeit:
--   - Den aktuellen Fuehrungsschritt (Modules/GuideSteps) sichtbar machen:
--     Ziel in der Welt → leuchtender Beam vom Charakter zum Ziel,
--     Ziel in der Oberflaeche → pulsierender Rahmen und Pfeil am Knopf
--
-- Kontext: HBB Paket 2. Kein Text, hoechstens ein Icon. Passiert eine Weile
-- nichts (FeedbackConfig/GUIDE_HINT_SECONDS), wird die Hervorhebung staerker
-- ("Timed Hint").
--
-- Alles hier ist rein lokal: der Beam, die Attachments und der Rahmen
-- existieren nur auf diesem Client, ohne Kollision und ohne Remote.
--
-- Mit FeatureFlags.UI_V2_GUIDE = false zeigt dieses Modul nichts.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)
local GuideSteps   = require(ReplicatedStorage.Modules.GuideSteps)
local EggConfig    = require(ReplicatedStorage.Config.EggConfig)
local Loc          = require(ReplicatedStorage.Localization.Loc)   -- Sammel-Update 3.5
local PanelManager = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("PanelManager"))

local UI          = script.Parent.Parent:WaitForChild("UI")
local Theme       = require(UI:WaitForChild("Theme"))
local UiScale     = require(UI:WaitForChild("UiScale"))
local MenuBar     = require(UI:WaitForChild("MenuBar"))
local PetBar      = require(UI:WaitForChild("PetBar"))
local ClientState = require(script.Parent.ClientState)

local GuideController = {}

-- Nach so vielen Sekunden ohne Fortschritt wird die Hervorhebung staerker.
local HINT_AFTER_SECONDS = 12

-- Sammel-Update 05.10.:
-- 3.1 groessere Pfeile (vorher 40 px, Wippen 8/18 px)
local ARROW_SIZE   = 84
local ARROW_BOUNCE = 16
local ARROW_BOUNCE_STRONG = 30
-- 3.2 der Event-Schritt ist am Anfang unwichtig: er zeigt sich nur so lange
-- und verschwindet dann (bis zum naechsten Join).
local EVENT_STEP_SECONDS = 8
-- 3.5 ein Satz, was der Schritt bringt (Schluessel "guide.<step>")
local HINT_WIDTH = 300
local HIGHLIGHT_COLOR = Color3.fromRGB(255, 236, 140)
local BEAM_COLOR      = Color3.fromRGB(255, 220, 90)
local LAID_EGG_ATTRIBUTE = "LaidEggUid"

local _step: string? = nil
local _stepSince = 0
-- Welt-Ziel, im Takt von evaluate() gesucht (nicht jeden Frame: die Suche
-- laeuft ueber den Workspace)
local _worldTarget: BasePart? = nil

local _frame: Frame? = nil
local _stroke: UIStroke? = nil
local _arrow: TextLabel? = nil
local _hint: TextLabel? = nil

local _beam: Beam? = nil
local _from: Attachment? = nil
local _to: Attachment? = nil

--------------------------------------------------------------------------------
-- Ziele
--------------------------------------------------------------------------------

local function uiTarget(step: string): GuiObject?
	if step == "hatch" then
		return MenuBar.getTileAnchor("Hatch")
	elseif step == "fight" then
		return PetBar.getButton("Fight")
	elseif step == "event" then
		return PetBar.getButton("Event")
	elseif step == "upgrade" then
		-- HUD_ROW_V2: keine Kachel mehr, der Strahl zeigt zum Brunnen (worldTarget)
		if FeatureFlags.isOn("HUD_ROW_V2") then return nil end
		-- Sammel-Update 3.5: Gebaeude-Kachel rechts
		return MenuBar.getTileAnchor(PanelManager.buildingPanelName(
			if FeatureFlags.isOn("HONEY_POND_V2") then "HoneyPond" else "HoneyRefiner"))
	end
	return nil
end

local function characterRoot(): BasePart?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

-- Naechstes EIGENES gelegtes Ei (uid steht in den eigenen Daten).
local function nearestOwnEgg(): BasePart?
	local data = ClientState.get()
	local root = characterRoot()
	if not data or not root then return nil end
	local own: { [string]: boolean } = {}
	for _, egg in data.island.laidEggs do
		own[(egg :: any).uid] = true
	end
	local best: BasePart? = nil
	local bestDist = math.huge
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("BasePart") then
			local uid = descendant:GetAttribute(LAID_EGG_ATTRIBUTE)
			if typeof(uid) == "string" and own[uid] then
				local dist = (descendant.Position - root.Position).Magnitude
				if dist < bestDist then
					best, bestDist = descendant, dist
				end
			end
		end
	end
	return best
end

-- Theke des Ei-Haendlers (EggMerchantService baut das Model "EggMerchant")
local function merchantCounter(): BasePart?
	local model = Workspace:FindFirstChild("EggMerchant")
	local counter = if model then model:FindFirstChild("Counter") else nil
	return if counter and counter:IsA("BasePart") then counter else nil
end

-- Recycler auf dem EIGENEN Plot (Attribut PlotOwner am Plot-Model).
local function ownRecycler(): BasePart?
	for _, descendant in Workspace:GetDescendants() do
		if descendant.Name == "Recycler" and descendant:IsA("BasePart") then
			local model = descendant.Parent
			if model and model:GetAttribute("PlotOwner") == Players.LocalPlayer.UserId then
				return descendant
			end
		end
	end
	return nil
end

-- HUD_ROW_V2: Honig-Gebaeude auf dem EIGENEN Plot (Prompt "Verbessern").
local function ownHoneyBuilding(): BasePart?
	local id = if FeatureFlags.isOn("HONEY_POND_V2") then "HoneyPond" else "HoneyRefiner"
	for _, descendant in Workspace:GetDescendants() do
		if descendant.Name == id and descendant:IsA("BasePart") then
			local current: Instance? = descendant
			while current do
				local owner = current:GetAttribute("PlotOwner")
				if typeof(owner) == "number" then
					if owner == Players.LocalPlayer.UserId then return descendant end
					break
				end
				current = current.Parent
			end
		end
	end
	return nil
end

local function worldTarget(step: string): BasePart?
	if step == "upgrade" and FeatureFlags.isOn("HUD_ROW_V2") then
		return ownHoneyBuilding()
	elseif step == "collect" then
		return nearestOwnEgg()
	elseif step == "merchant" then
		return merchantCounter()
	elseif step == "combs" then
		-- Sammel-Update 3.5: mit Waben auf dem Kopf zum eigenen Recycler,
		-- sonst zu den Waben in die Mitte.
		local carried = Players.LocalPlayer:GetAttribute("CombsCarried")
		if typeof(carried) == "number" and carried > 0 then
			return ownRecycler()
		end
		local pit = Workspace:FindFirstChild("EventFloor", true)
		return if pit and pit:IsA("BasePart") then pit else nil
	end
	return nil
end

--------------------------------------------------------------------------------
-- Darstellung
--------------------------------------------------------------------------------

local function clearBeam()
	if _beam then _beam:Destroy() end
	if _from then _from:Destroy() end
	if _to then _to:Destroy() end
	_beam, _from, _to = nil, nil, nil
end

local function showBeam(target: BasePart)
	local root = characterRoot()
	if not root then
		clearBeam()
		return
	end
	if _to and _to.Parent == target and _from and _from.Parent == root then
		return
	end
	clearBeam()
	local from = Instance.new("Attachment")
	from.Name = "GuideFrom"
	from.Parent = root
	local to = Instance.new("Attachment")
	to.Name = "GuideTo"
	to.Position = Vector3.new(0, 1, 0)
	to.Parent = target
	local beam = Instance.new("Beam")
	beam.Name = "GuideBeam"
	beam.Attachment0 = from
	beam.Attachment1 = to
	beam.Color = ColorSequence.new(BEAM_COLOR)
	beam.LightEmission = 1
	beam.FaceCamera = true
	beam.Width0 = 0.5
	beam.Width1 = 0.5
	beam.Segments = 12
	beam.CurveSize0 = 4
	beam.Transparency = NumberSequence.new(0.15)
	beam.Parent = root
	_beam, _from, _to = beam, from, to
end

local function hideHighlight()
	if _frame then _frame.Visible = false end
	if _arrow then _arrow.Visible = false end
end

-- Sammel-Update 3.5: Satz zum Schritt, unten mittig ueber der Pet-Leiste.
local function showHint(step: string?)
	local hint = _hint
	if not hint then return end
	local key = if step then "guide." .. step else nil
	if key and Loc.has(key) then
		hint.Text = Loc.t(key)
		hint.Visible = true
	else
		hint.Visible = false
	end
end

local function showHighlight(target: GuiObject, strong: boolean, t: number)
	local frame, stroke, arrow = _frame, _stroke, _arrow
	if not frame or not stroke or not arrow then return end
	if not target.Visible then
		hideHighlight()
		return
	end
	-- Bildschirm-Pixel -> Oberflaechen-Einheiten (globale UiScale)
	local pos, size = UiScale.toGui(target.AbsolutePosition), UiScale.toGui(target.AbsoluteSize)
	local pad = 6
	frame.Position = UDim2.fromOffset(pos.X - pad, pos.Y - pad)
	frame.Size = UDim2.fromOffset(size.X + pad * 2, size.Y + pad * 2)
	frame.Visible = true

	local wave = (math.sin(t * (if strong then 9 else 5)) + 1) * 0.5
	stroke.Thickness = (if strong then 5 else 3) + wave * (if strong then 4 else 2)
	stroke.Transparency = 0.1 + (1 - wave) * 0.4

	-- Pfeil zeigt von oben auf den Knopf (die Kachelleiste rechts: von links)
	local screen = frame.Parent :: GuiObject
	local fromLeft = pos.X > UiScale.toGui(screen.AbsoluteSize.X) * 0.8
	local bounce = wave * (if strong then ARROW_BOUNCE_STRONG else ARROW_BOUNCE)
	arrow.Visible = true
	if fromLeft then
		-- "➡" statt "➜": "➜" kann die Spielschrift nicht darstellen.
		arrow.Text = "➡"
		arrow.Position = UDim2.fromOffset(pos.X - ARROW_SIZE - 6 - bounce, pos.Y + size.Y * 0.5 - ARROW_SIZE * 0.5)
	else
		arrow.Text = "⬇"
		arrow.Position = UDim2.fromOffset(pos.X + size.X * 0.5 - ARROW_SIZE * 0.5, pos.Y - ARROW_SIZE - 6 - bounce)
	end
end

--------------------------------------------------------------------------------
-- Takt
--------------------------------------------------------------------------------

local function evaluate()
	local data = ClientState.get()
	local step: string? = nil
	if data and FeatureFlags.isOn("UI_V2_GUIDE") then
		-- HBB Paket 5: Haendler-Schritt nur mit sichtbarem Haendler
		local options = if FeatureFlags.isOn("MAP_V2_MERCHANT")
			then { merchantPrice = EggConfig.MERCHANT.priceGummies }
			else nil
		step = GuideSteps.current(data :: any, options)
	end
	if step ~= _step then
		_step = step
		_stepSince = os.clock()
	end
	_worldTarget = if step then worldTarget(step) else nil
end

local function render()
	local step = _step
	local now = os.clock()
	-- Sammel-Update 3.2: Event-Schritt nur kurz
	if step == "event" and now - _stepSince > EVENT_STEP_SECONDS then
		step = nil
	end
	showHint(step)
	if not step then
		hideHighlight()
		clearBeam()
		return
	end
	local strong = now - _stepSince >= HINT_AFTER_SECONDS

	local target = uiTarget(step)
	if target then
		clearBeam()
		showHighlight(target, strong, now)
		return
	end
	hideHighlight()

	local part = _worldTarget
	if part and part.Parent then
		showBeam(part)
		local beam = _beam
		if beam then
			local w = if strong then 0.9 + math.sin(now * 8) * 0.3 else 0.5
			beam.Width0, beam.Width1 = w, w
		end
	else
		clearBeam()
	end
end

function GuideController.init(screenGui: ScreenGui)
	local frame = Theme.container("GuideHighlight", screenGui)
	frame.ZIndex = 40
	frame.Visible = false
	Theme.corner(frame, 16)
	local stroke = Instance.new("UIStroke")
	stroke.Color = HIGHLIGHT_COLOR
	stroke.Thickness = 3
	stroke.Parent = frame
	_frame, _stroke = frame, stroke

	local arrow = Theme.label("GuideArrow", screenGui, "⬇")
	arrow.Size = UDim2.fromOffset(ARROW_SIZE, ARROW_SIZE)
	local arrowLimit = arrow:FindFirstChildOfClass("UITextSizeConstraint")
	if arrowLimit then arrowLimit.MaxTextSize = ARROW_SIZE end
	arrow.TextXAlignment = Enum.TextXAlignment.Center
	arrow.TextColor3 = HIGHLIGHT_COLOR
	arrow.ZIndex = 41
	arrow.Visible = false
	Theme.outlineText(arrow, 3)
	_arrow = arrow

	-- Sammel-Update 3.5: ein Satz pro Schritt
	local hint = Theme.label("GuideHint", screenGui, "")
	hint.AnchorPoint = Vector2.new(0.5, 1)
	hint.Position = UDim2.new(0.5, 0, 1, -112)
	hint.Size = UDim2.fromOffset(HINT_WIDTH, 44)
	hint.TextXAlignment = Enum.TextXAlignment.Center
	hint.TextWrapped = true
	hint.TextColor3 = HIGHLIGHT_COLOR
	hint.ZIndex = 41
	hint.Visible = false
	Theme.outlineText(hint, 2)
	_hint = hint
	Loc.onChanged(function() showHint(_step) end)

	ClientState.onChanged(function()
		evaluate()
	end)

	-- Gelegte Eier tauchen ohne Datenaenderung auf/ab (Replikation): der
	-- Welt-Schritt wird deshalb im Takt neu gesucht, die Anzeige jeden Frame.
	local accumulator = 0
	RunService.RenderStepped:Connect(function(delta)
		accumulator += delta
		if accumulator >= 0.5 then
			accumulator = 0
			evaluate()
		end
		render()
	end)

	print("[GuideController] Initialisiert")
end

return GuideController
