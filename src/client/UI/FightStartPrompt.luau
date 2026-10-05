--!strict
-- FightStartPrompt.luau
-- StarterPlayerScripts/UI/FightStartPrompt.luau
--
-- Einzige Zustaendigkeit:
--   - Das kleine Feld beim Fight-Klick (FeatureFlags.FIGHT_RESUME_PROMPT):
--     "Ab Stage X weiter" gegen Gummies. Klickt der Spieler nichts, ist es
--     nach AUTO_SECONDS weg und der Lauf startet bei Stage 1.
--
-- Entscheidung Projektinhaber 05.10.: Stages schafft man durch STAERKERE
-- Baerchis. Der Einstieg weiter oben ist eine bewusste Spieler-Entscheidung
-- gegen Waehrung, nie der Standard. (Vorher startete der Fight-Knopf ohne
-- Frage ab 65 % des letzten Laufs und buchte dafuer Gummies ab.)
--
-- Kosten und Start-Stage rechnet PitResumeDialog.offer — dieselbe Rechnung,
-- mit der der Server abbucht. Bezahlbar entscheidet am Ende der Server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Loc = require(ReplicatedStorage.Localization.Loc)

local Theme           = require(script.Parent.Theme)
local Icons           = require(script.Parent.Icons)
local PitResumeDialog = require(script.Parent.PitResumeDialog)
local ClientState     = require(script.Parent.Parent.Controllers.ClientState)

local FightStartPrompt = {}

FightStartPrompt.AUTO_SECONDS = 7

local _root: Frame? = nil
local _resume: TextButton? = nil
local _cost: TextLabel? = nil
local _bar: Frame? = nil
local _onChoose: ((PitResumeDialog.Choice) -> ())? = nil
local _openedAt = 0
local _token = 0

local function finish(choice: PitResumeDialog.Choice)
	local callback = _onChoose
	_onChoose = nil
	_token += 1
	local root = _root
	if root then root.Visible = false end
	if callback then callback(choice) end
end

function FightStartPrompt.isOpen(): boolean
	return _onChoose ~= nil
end

-- Sofort mit Stage 1 starten (zweiter Fight-Klick waehrend das Feld offen ist)
function FightStartPrompt.chooseFresh()
	if _onChoose then finish("Fresh") end
end

-- Oeffnet das Feld, wenn es einen letzten Lauf ueber Stage 1 gibt. Gibt
-- false zurueck, wenn es nichts anzubieten gibt (Aufrufer startet dann
-- selbst bei Stage 1).
function FightStartPrompt.open(onChoose: (PitResumeDialog.Choice) -> ()): boolean
	local root, resume, cost = _root, _resume, _cost
	local data = ClientState.get()
	if not root or not resume or not cost or not data then return false end
	local reached = PitResumeDialog.getProgress(data)
	if not reached or reached <= 1 then return false end

	local stage, price = PitResumeDialog.offer(data, "Last")
	resume.Text = Loc.t("ui.fight.resume", { stage = stage })
	cost.Text = Theme.formatNumber(price)
	Theme.setEnabled(resume, price <= data.gummies)

	_onChoose = onChoose
	_openedAt = os.clock()
	_token += 1
	local token = _token
	root.Visible = true

	task.delay(FightStartPrompt.AUTO_SECONDS, function()
		if token == _token and _onChoose then
			finish("Fresh")
		end
	end)
	return true
end

function FightStartPrompt.init(screenGui: ScreenGui, anchorAbove: GuiObject)
	local root = Theme.panel("FightStartPrompt", screenGui, Theme.COLORS.panelDeep)
	root.AnchorPoint = Vector2.new(0.5, 1)
	root.Position = UDim2.new(0.5, 0, 1, -(anchorAbove.Size.Y.Offset + 26))
	root.Size = UDim2.fromOffset(300, 96)
	root.Visible = false
	root.ZIndex = 6
	_root = root

	local resume = Theme.bigButton("Resume", root, "", Theme.COLORS.goldGummy)
	resume.Position = UDim2.new(0, 8, 0, 8)
	resume.Size = UDim2.new(1, -16, 0, 44)
	resume.Activated:Connect(function()
		if resume.Active then finish("Last") end
	end)
	_resume = resume

	-- Kosten rechts im Knopf: Gummi-Icon + Zahl
	local coin = Icons.make(resume, "gummy", "G")
	coin.AnchorPoint = Vector2.new(1, 0.5)
	coin.Position = UDim2.new(1, -56, 0.5, 0)
	coin.Size = UDim2.fromOffset(24, 24)
	local cost = Theme.label("Cost", resume, "")
	cost.AnchorPoint = Vector2.new(1, 0.5)
	cost.Position = UDim2.new(1, -8, 0.5, 0)
	cost.Size = UDim2.fromOffset(46, 24)
	_cost = cost

	local fresh = Theme.button("Fresh", root, Loc.t("ui.fight.fresh"), Theme.COLORS.panelLight)
	fresh.Position = UDim2.new(0, 8, 0, 58)
	fresh.Size = UDim2.new(0.42, 0, 0, 26)
	fresh.TextColor3 = Theme.COLORS.text
	Loc.bind(fresh, "ui.fight.fresh")
	fresh.Activated:Connect(function() finish("Fresh") end)

	-- Ablaufbalken: zeigt, dass es gleich von selbst bei Stage 1 losgeht
	local track = Instance.new("Frame")
	track.Name = "Timer"
	track.BackgroundColor3 = Theme.COLORS.panelLight
	track.BorderSizePixel = 0
	track.Position = UDim2.new(0.42, 16, 0, 66)
	track.Size = UDim2.new(0.58, -24, 0, 10)
	track.Parent = root
	Theme.corner(track, 5)
	local bar = Instance.new("Frame")
	bar.BackgroundColor3 = Theme.COLORS.goldGummy
	bar.BorderSizePixel = 0
	bar.Size = UDim2.fromScale(1, 1)
	bar.Parent = track
	Theme.corner(bar, 5)
	_bar = bar

	RunService.RenderStepped:Connect(function()
		if not _onChoose then return end
		local left = math.clamp(1 - (os.clock() - _openedAt) / FightStartPrompt.AUTO_SECONDS, 0, 1)
		local b = _bar
		if b then b.Size = UDim2.fromScale(left, 1) end
	end)

end

return FightStartPrompt
