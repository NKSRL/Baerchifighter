--!strict
-- FightStartPrompt.luau
-- StarterPlayerScripts/UI/FightStartPrompt.luau
--
-- Einzige Zustaendigkeit:
--   - Das kleine Feld beim Fight-Klick (immer aktiv):
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
--
-- 08.10. (Paket C, "der bezahlte Knopf leuchtet, keiner nimmt den Gratis-
-- Start"): Hierarchie umgedreht. Oben gross und gruen der GRATIS-Start bei
-- Stage 1, darunter klein und gedaempft der bezahlte Einstieg (mit dem
-- Gamepass "Gratis (Pass)"). Keine falschen Countdowns: der Balken zeigt nur,
-- wann es von selbst gratis losgeht.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local Loc = require(ReplicatedStorage.Localization.Loc)

local Theme           = require(script.Parent.Theme)
local Icons           = require(script.Parent.Icons)
local Kit             = require(script.Parent.Kit)   -- 12.10.: kurze Zahlen (4,8M)
local PitResumeDialog = require(script.Parent.PitResumeDialog)
local ClientState     = require(script.Parent.Parent.Controllers.ClientState)

local FightStartPrompt = {}

FightStartPrompt.AUTO_SECONDS = 7

local _root: Frame? = nil
local _resume: TextButton? = nil
local _resumeText: TextLabel? = nil   -- 12.10.: eigene Beschriftung (links)
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
	local pass = PitResumeDialog.hasSkipPass()
	-- 12.10.: Preis kurz und hinter dem Text (vorher lag die lange Zahl
	-- ueber dem Wort "weiter")
	local label = _resumeText
	local text = if pass
		then Loc.t("ui.fight.resume_pass", { stage = stage })
		else "⏩ " .. Loc.t("ui.fight.resume", { stage = stage })
	if label then label.Text = text end
	cost.Text = if pass then "" else Kit.formatCompact(price)
	local affordable = price <= data.gummies
	Theme.setEnabled(resume, affordable)
	-- Auch zu teuer bleibt die Schrift lesbar (nur etwas gedaempft); der
	-- Preis wird rot, damit klar ist, warum der Knopf nicht geht.
	if label then label.TextColor3 = if affordable then Theme.COLORS.text else Color3.fromRGB(205, 200, 215) end
	cost.TextColor3 = if affordable then Theme.COLORS.text else Color3.fromRGB(255, 120, 120)
	local coin = resume:FindFirstChild("Icon")
	if coin and coin:IsA("GuiObject") then coin.Visible = not pass end

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
	-- 12.10. (Playtest "unter dem Start-Knopf liegt ein Knopf, den man nicht
	-- erkennt"): drei klare Zeilen statt Knopf + Balken nebeneinander —
	-- gruener Gratis-Start, darunter der bezahlte Einstieg ueber die ganze
	-- Breite (Text links, Preis rechts, nichts ueberlappt), unten der Balken.
	root.Size = UDim2.fromOffset(320, 126)
	root.Visible = false
	root.ZIndex = 6
	_root = root

	-- Ueber der Pet-Leiste, und mit ihr mitwandern: auf Touch-Geraeten sitzt
	-- sie nicht mittig, sondern im freien Streifen neben der Steuerung
	-- (TouchSafeArea), und ihr UIScale macht sie kleiner.
	local function follow()
		local barScale = anchorAbove:FindFirstChildOfClass("UIScale")
		local factor = if barScale then barScale.Scale else 1
		root.Position = UDim2.new(
			anchorAbove.Position.X.Scale, anchorAbove.Position.X.Offset,
			1, -(anchorAbove.Size.Y.Offset * factor + 26)
		)
	end
	anchorAbove:GetPropertyChangedSignal("Position"):Connect(follow)
	local barScale = anchorAbove:FindFirstChildOfClass("UIScale")
	if barScale then
		barScale:GetPropertyChangedSignal("Scale"):Connect(follow)
	end
	follow()

	-- Primaer: der Gratis-Start (gross, gruen)
	local fresh = Theme.bigButton("Fresh", root, Loc.t("ui.fight.fresh_free"), Theme.COLORS.good)
	fresh.Position = UDim2.new(0, 8, 0, 8)
	fresh.Size = UDim2.new(1, -16, 0, 46)
	fresh.TextColor3 = Theme.COLORS.text
	Theme.outlineText(fresh :: any, 2)
	Loc.bind(fresh, "ui.fight.fresh_free")
	fresh.Activated:Connect(function() finish("Fresh") end)

	-- Sekundaer: der bezahlte Einstieg (ganze Breite, ruhiger, kein Glanz)
	local resume = Theme.button("Resume", root, "", Theme.COLORS.panelLight)
	resume.Position = UDim2.new(0, 8, 0, 62)
	resume.Size = UDim2.new(1, -16, 0, 40)
	resume.TextColor3 = Theme.COLORS.text
	local shine = resume:FindFirstChild("Shine")
	if shine then shine:Destroy() end
	-- Beschriftung als eigenes Feld links, Preis rechts: feste Bereiche statt
	-- einer Polsterung, ueber die Preis und Text sich nicht ueberlappen koennen
	local resumeText = Theme.label("Text", resume, "")
	resumeText.AnchorPoint = Vector2.new(0, 0.5)
	resumeText.Position = UDim2.new(0, 10, 0.5, 0)
	resumeText.Size = UDim2.new(1, -110, 0, 26)
	resumeText.TextXAlignment = Enum.TextXAlignment.Left
	resumeText.TextScaled = true
	Theme.outlineText(resumeText, 2)
	_resumeText = resumeText
	resume.Activated:Connect(function()
		if resume.Active then finish("Last") end
	end)
	_resume = resume

	-- Kosten rechts im Knopf: Zahl + Gummi-Icon
	local coin = Icons.make(resume, "gummy", "G")
	coin.AnchorPoint = Vector2.new(1, 0.5)
	coin.Position = UDim2.new(1, -8, 0.5, 0)
	coin.Size = UDim2.fromOffset(24, 24)
	local cost = Theme.label("Cost", resume, "")
	cost.AnchorPoint = Vector2.new(1, 0.5)
	cost.Position = UDim2.new(1, -36, 0.5, 0)
	cost.Size = UDim2.fromOffset(58, 24)
	cost.TextXAlignment = Enum.TextXAlignment.Right
	Theme.outlineText(cost, 2)
	_cost = cost

	-- Ablaufbalken: zeigt, dass es gleich von selbst bei Stage 1 losgeht
	local track = Instance.new("Frame")
	track.Name = "Timer"
	track.BackgroundColor3 = Theme.COLORS.panelLight
	track.BorderSizePixel = 0
	track.Position = UDim2.new(0, 12, 0, 110)
	track.Size = UDim2.new(1, -24, 0, 8)
	track.Parent = root
	Theme.corner(track, 4)
	local bar = Instance.new("Frame")
	bar.BackgroundColor3 = Theme.COLORS.good
	bar.BorderSizePixel = 0
	bar.Size = UDim2.fromScale(1, 1)
	bar.Parent = track
	Theme.corner(bar, 4)
	_bar = bar

	RunService.RenderStepped:Connect(function()
		if not _onChoose then return end
		local left = math.clamp(1 - (os.clock() - _openedAt) / FightStartPrompt.AUTO_SECONDS, 0, 1)
		local b = _bar
		if b then b.Size = UDim2.fromScale(left, 1) end
	end)

end

return FightStartPrompt
