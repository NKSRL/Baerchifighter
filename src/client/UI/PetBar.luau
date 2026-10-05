--!strict
-- PetBar.luau
-- StarterPlayerScripts/UI/PetBar.luau
--
-- Einzige Zustaendigkeit:
--   - Die untere Pet-Leiste: zwei grosse Knoepfe "Event" und "Fight", die den
--     ausgeruesteten Baerchi hinschicken bzw. zurueckholen.
--
-- Die Leiste ZEIGT nur an, was der Server meldet (PetModeChanged) — was ein
-- Klick bedeutet, entscheidet PetModeService. Der Client schickt nur, welcher
-- Knopf gedrueckt wurde, und beim Fight-Knopf ggf. die Wahl aus der
-- Fortsetzungs-Frage (PitResumeDialog).
--
-- Zustaende je Knopf:
--   normal        Normalfarbe, Klick schickt hin
--   unterwegs/da  leuchtet, Text "Zurueckholen"
--   wartet        der Baerchi geht erst heim und dann hierher; Klick bricht ab
--   gesperrt      grau, kleine Zeile mit dem Grund

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local FeatureFlags      = require(ReplicatedStorage.Config.FeatureFlags)

local Remotes          = require(ReplicatedStorage.Network.Remotes)
local EventConfig      = require(ReplicatedStorage.Config.EventConfig)
local BaerchiConfig    = require(ReplicatedStorage.Config.BaerchiConfig)
local CombatCalculator = require(ReplicatedStorage.Modules.CombatCalculator)
local TowerConfig      = require(ReplicatedStorage.Config.TowerConfig)

local Theme           = require(script.Parent.Theme)
local UiScale         = require(script.Parent.UiScale)
local Icons           = require(script.Parent.Icons)
local PitResumeDialog = require(script.Parent.PitResumeDialog)
local ClientState     = require(script.Parent.Parent.Controllers.ClientState)
local Unlock          = require(script.Parent.Unlock)

local PetBar = {}

local BUTTON_WIDTH  = 210
local BUTTON_HEIGHT = 68    -- Mindesthoehe 56 px fuer Touch
local GAP           = 14

local EVENT_COLOR = Color3.fromRGB(120, 190, 255)
local FIGHT_COLOR = Color3.fromRGB(255,  96,  96)
local GLOW_COLOR  = Color3.fromRGB(255, 236, 140)

type ButtonView = {
	button : TextButton,
	title  : TextLabel,
	sub    : TextLabel,
	stroke : UIStroke,
	color  : Color3,
	icon   : GuiObject,
}

local _event: ButtonView? = nil
local _fight: ButtonView? = nil

-- Letzte Server-Meldung (PetModeChanged)
local _state   = "Home"
local _pending: string? = nil
local _stage: number? = nil
local _tower: string? = nil   -- v15: Tower des laufenden Kampfs (vom Server)
local _from: string? = nil
local _abducting = false

-- Event-Zyklus (EventPhaseChanged)
local _eventId: string? = nil
local _nextEventId: string? = nil
local _phaseEndsAt = 0

--------------------------------------------------------------------------------
-- Hilfen
--------------------------------------------------------------------------------

-- HBB Paket 6: Icon je Event fuer den Timer am Knopf (Name aus UI/Icons,
-- sonst das Zeichen als Rueckfall). Die Wespenkoenigin bekommt ein eigenes.
local EVENT_ICON: { [string]: { name: string, fallback: string } } = {
	Ufo            = { name = "ufo",   fallback = "UFO" },
	HotEgg         = { name = "egg",   fallback = "🥚" },
	MutationsSturm = { name = "",      fallback = "🌪" },
	Koenigshuegel  = { name = "crown", fallback = "♛" },
	Schatzgraeber  = { name = "gift",  fallback = "💎" },
	WaspQueen      = { name = "",      fallback = "🐝" },
}

local function clock(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", math.floor(s / 60), s % 60)
end

local function eventLine(): string
	local remaining = _phaseEndsAt - os.clock()
	if _eventId then
		local def = EventConfig.getById(_eventId)
		return string.format("%s  %s", if def then def.displayName else _eventId, clock(remaining))
	end
	if _nextEventId then
		return "Naechstes Event in " .. clock(remaining)
	end
	return ""
end

-- "Tower II" fuer eine Tower-Id.
local function towerLabel(towerId: string?): string
	local def = TowerConfig.get(towerId or "") or TowerConfig.TOWERS[1]
	return "Tower " .. def.numeral
end

-- HP-Anteil des ausgeruesteten Baerchis (nil = keiner da) und der gewaehlte
-- Tower (v15, ersetzt das PIT-Level).
local function fighterInfo(): (number?, string)
	local data = ClientState.get()
	if not data then return nil, "I" end

	local tower = if data.towers then data.towers.selected else "I"
	local uid = data.island.equippedUid
	local baerchi = if uid then data.island.baerchis[uid] else nil
	local def = if baerchi then BaerchiConfig.getById(baerchi.configId) else nil
	if not baerchi or not def then
		return nil, tower
	end

	local maxHp = CombatCalculator.getEffectiveStats(baerchi, def.baseStats).maxHp
	local hp = math.clamp(baerchi.currentHp or maxHp, 0, maxHp)
	return hp / math.max(1, maxHp), tower
end

local function paint(view: ButtonView, title: string, sub: string, mode: "normal" | "active" | "waiting" | "disabled")
	view.title.Text = title
	view.sub.Text   = sub

	if mode == "disabled" then
		view.button.Active           = false
		view.button.AutoButtonColor  = false
		view.button.BackgroundColor3 = Theme.COLORS.disabled
		view.stroke.Color            = Theme.COLORS.outline
		view.stroke.Thickness        = Theme.OUTLINE_THICKNESS
		view.title.TextTransparency  = 0.35
		Icons.tint(view.icon, Color3.fromRGB(140, 140, 150))
		return
	end

	Icons.tint(view.icon, Color3.new(1, 1, 1))

	view.button.Active          = true
	view.button.AutoButtonColor = false
	view.title.TextTransparency = 0

	if mode == "active" then
		view.button.BackgroundColor3 = Theme.shade(view.color, 0.15)
		view.stroke.Color            = GLOW_COLOR
		view.stroke.Thickness        = 5
	elseif mode == "waiting" then
		view.button.BackgroundColor3 = Theme.shade(view.color, -0.25)
		view.stroke.Color            = GLOW_COLOR
		view.stroke.Thickness        = 3
	else
		view.button.BackgroundColor3 = view.color
		view.stroke.Color            = Theme.COLORS.outline
		view.stroke.Thickness        = Theme.OUTLINE_THICKNESS
	end
end

--------------------------------------------------------------------------------
-- Anzeige
--------------------------------------------------------------------------------

local _eventIconKey: string? = nil

-- Tauscht das Icon des Event-Knopfs gegen das des kommenden/laufenden Events.
local function setEventIcon(view: ButtonView, eventId: string?)
	local key = eventId or "Ufo"
	if _eventIconKey == key then return end
	_eventIconKey = key
	local look = EVENT_ICON[key] or EVENT_ICON.Ufo
	local old = view.icon
	local icon = Icons.make(view.button, look.name, look.fallback)
	icon.AnchorPoint = old.AnchorPoint
	icon.Position    = old.Position
	icon.Size        = old.Size
	icon.ZIndex      = old.ZIndex
	old:Destroy()
	view.icon = icon
end

local function refresh()
	local event, fight = _event, _fight
	if not event or not fight then return end

	-- HBB Paket 3: der Event-Knopf erscheint erst nach dem ersten Kampf
	Unlock.apply("button_event", event.button)

	local hpRatio, selectedTower = fighterInfo()
	local hasPet = hpRatio ~= nil

	-- --------------------------------------------------------------- Event
	if not hasPet then
		paint(event, "Event", "Kein Baerchi ausgeruestet", "disabled")
	elseif _abducting then
		paint(event, "Event", "Vom UFO entfuehrt …", "disabled")
	elseif _state == "ToEvent" then
		paint(event, "Zurueckholen", "laeuft hin • " .. eventLine(), "active")
	elseif _state == "AtEvent" then
		paint(event, "Zurueckholen", eventLine(), "active")
	elseif _pending == "Event" then
		paint(event, "wartet …", "erst heim, dann hin • Klick bricht ab", "waiting")
	elseif _state == "Returning" and _from == "Event" then
		paint(event, "Event", "kommt heim …", "normal")
	elseif FeatureFlags.isOn("EVENT_V2_TIMER") then
		-- HBB Paket 6: Icon des kommenden bzw. laufenden Events + Restzeit,
		-- keine Woerter.
		setEventIcon(event, _eventId or _nextEventId)
		paint(event, clock(_phaseEndsAt - os.clock()), "", "normal")
	else
		paint(event, "Event", eventLine(), "normal")
	end

	-- --------------------------------------------------------------- Fight
	local hpText = if hpRatio then string.format("HP %d%%  •  %s", math.floor(hpRatio * 100 + 0.5), towerLabel(selectedTower)) else ""

	if not hasPet then
		paint(fight, "Fight", "Kein Baerchi ausgeruestet", "disabled")
	elseif _state == "ToPit" then
		paint(fight, "Zurueckholen", "laeuft in den PIT …", "active")
	elseif _state == "InPit" then
		paint(fight, "Zurueckholen", if _stage then towerLabel(_tower or selectedTower) .. " · Stage " .. _stage else towerLabel(_tower or selectedTower), "active")
	elseif _pending == "Fight" then
		paint(fight, "wartet …", "erst heim, dann PIT • Klick bricht ab", "waiting")
	elseif _state == "Returning" and _from == "Fight" then
		paint(fight, "Fight", "kommt heim …", "normal")
	elseif (hpRatio or 0) <= 0 then
		paint(fight, "Fight", "Zu erschoepft — erst Honig", "disabled")
	else
		paint(fight, "Fight", hpText, "normal")
	end
end

--------------------------------------------------------------------------------
-- Klicks
--------------------------------------------------------------------------------

local function onEventClicked()
	Unlock.markSeen("button_event")
	Remotes.RequestPetMode:FireServer("Event")
end

local function onFightClicked()
	-- Zurueckholen oder einen vorgemerkten Wechsel abbrechen: keine Frage.
	if _state == "ToPit" or _state == "InPit" or _pending == "Fight" then
		Remotes.RequestPetMode:FireServer("Fight")
		return
	end

	-- Neuer Lauf: gibt es einen letzten Lauf in diesem Tower, zuerst die
	-- Fortsetzungs-Frage.
	local data = ClientState.get()

	-- HBB Paket 2: keine Frage mehr. Mit gespeichertem Lauf geht es
	-- kostenlos ab 65 % weiter; der bezahlte Einstieg ab der letzten Stage
	-- ist ein eigener kleiner Knopf im Tower-Fenster (CombatPanel). Der
	-- Server rechnet beide Wege unveraendert.
	if FeatureFlags.isOn("UI_V2_GUIDE") then
		local choice = if data and PitResumeDialog.getProgress(data) then "Percent" else "Fresh"
		Remotes.RequestPetMode:FireServer("Fight", choice)
		return
	end

	if data and PitResumeDialog.getProgress(data) then
		PitResumeDialog.open(function(choice)
			Remotes.RequestPetMode:FireServer("Fight", choice)
		end)
		return
	end

	Remotes.RequestPetMode:FireServer("Fight", "Fresh")
end

--------------------------------------------------------------------------------
-- HBB Paket 2: Anker fuer die Fuehrung (GuideController)
--------------------------------------------------------------------------------

function PetBar.getButton(mode: string): GuiObject?
	local view = if mode == "Fight" then _fight elseif mode == "Event" then _event else nil
	return if view then view.button else nil
end

--------------------------------------------------------------------------------
-- Aufbau
--------------------------------------------------------------------------------

local function buildButton(parent: Instance, name: string, color: Color3, order: number, onClick: () -> (), iconName: string, fallback: string): ButtonView
	local button = Theme.bigButton(name, parent, "", color)
	button.Size        = UDim2.fromOffset(BUTTON_WIDTH, BUTTON_HEIGHT)
	button.LayoutOrder = order

	local stroke = button:FindFirstChildOfClass("UIStroke") :: UIStroke

	-- Icon links, ragt oben ueber den Knopf hinaus
	local icon = Icons.make(button, iconName, fallback)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position    = UDim2.new(0, 6, 0.5, -6)
	icon.Size        = UDim2.fromOffset(60, 60)
	icon.ZIndex      = 4

	local title = Theme.label("Title", button, name)
	title.Position       = UDim2.new(0, 64, 0, 6)
	title.Size           = UDim2.new(1, -72, 0, 30)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextColor3     = Theme.COLORS.text
	Theme.outlineText(title)

	local sub = Theme.label("Sub", button, "")
	sub.Position       = UDim2.new(0, 64, 1, -26)
	sub.Size           = UDim2.new(1, -70, 0, 18)
	sub.TextXAlignment = Enum.TextXAlignment.Center
	sub.TextScaled     = false
	sub.TextSize       = 12
	sub.Font           = Theme.FONT_BODY
	sub.TextColor3     = Theme.COLORS.outline
	sub.TextTruncate   = Enum.TextTruncate.AtEnd

	button.Activated:Connect(function()
		if not button.Active then return end
		onClick()
	end)

	return { button = button, title = title, sub = sub, stroke = stroke, color = color, icon = icon }
end

function PetBar.init(screenGui: ScreenGui)
	local bar = Theme.container("PetBar", screenGui)
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position    = UDim2.new(0.5, 0, 1, -14)
	bar.Size        = UDim2.fromOffset(BUTTON_WIDTH * 2 + GAP, BUTTON_HEIGHT)
	bar.ZIndex      = 5

	-- Auf schmalen Bildschirmen (Handy) mitskalieren statt ueber den Rand
	local scale = Instance.new("UIScale")
	scale.Parent = bar
	local function rescale()
		local width = UiScale.toGui(screenGui.AbsoluteSize.X)
		scale.Scale = math.clamp((width - 32) / (BUTTON_WIDTH * 2 + GAP), 0.6, 1)
	end
	screenGui:GetPropertyChangedSignal("AbsoluteSize"):Connect(rescale)
	rescale()

	local layout = Theme.listLayout(bar, GAP, true)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	_event = buildButton(bar, "Event", EVENT_COLOR, 1, onEventClicked, "ufo", "UFO")
	_fight = buildButton(bar, "Fight", FIGHT_COLOR, 2, onFightClicked, "swords", "X")

	PitResumeDialog.init(screenGui)

	Remotes.PetModeChanged.OnClientEvent:Connect(function(state: any, pending: any, info: any)
		_state   = if typeof(state) == "string" then state else "Home"
		_pending = if typeof(pending) == "string" then pending else nil
		local typedInfo = if typeof(info) == "table" then info else {}
		_stage     = if typeof(typedInfo.stage) == "number" then typedInfo.stage else nil
		_tower     = if typeof(typedInfo.tower) == "string" then typedInfo.tower else nil
		_from      = if typeof(typedInfo.from) == "string" then typedInfo.from else nil
		_abducting = typedInfo.abducting == true

		-- Laeuft der Baerchi los, ist eine offene Fortsetzungs-Frage hinfaellig.
		if _state ~= "Home" and _state ~= "Returning" and PitResumeDialog.isOpen() then
			PitResumeDialog.close()
		end

		refresh()
	end)

	Remotes.EventPhaseChanged.OnClientEvent:Connect(function(eventId: any, remaining: any, nextEventId: any)
		_eventId     = if typeof(eventId) == "string" then eventId else nil
		_nextEventId = if typeof(nextEventId) == "string" then nextEventId else nil
		_phaseEndsAt = os.clock() + (if typeof(remaining) == "number" then remaining else 0)
		refresh()
	end)

	ClientState.onChanged(refresh)

	-- Restzeit des Events jede Sekunde nachziehen
	local accumulator = 0
	RunService.Heartbeat:Connect(function(delta)
		accumulator += delta
		if accumulator < 1 then return end
		accumulator = 0
		refresh()
	end)

	refresh()
	print("[PetBar] Initialisiert")
end

return PetBar
