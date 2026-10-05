--!strict
-- Hud.luau
-- StarterPlayerScripts/UI/Hud.luau
--
-- Einzige Zustaendigkeit:
--   - Dauerhaft sichtbare Kopfzeile: Waehrungen, Rang, Rebirth-Multiplikator
--
-- Liest ausschliesslich aus ClientState und reagiert auf dessen onChanged —
-- die Anzeige rechnet nie selbst etwas hoch.
--
-- Die Rebirth-Pille rechts oben ist gleichzeitig der Knopf fuer den
-- Rebirth-Dialog: der Multiplikator ist genau die Zahl die ein Rebirth
-- erhoeht, also gehoert der Weg dorthin an dieselbe Stelle.
--
-- Die Y-Positionen der beiden Spalten sind bewusst Pixel-Offsets und keine
-- Scale-Werte: die MenuBar haengt direkt darunter und wuerde sonst je nach
-- Bildschirmhoehe in die Pillen rutschen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local Types = require(ReplicatedStorage.Network.Types)
local Loc   = require(ReplicatedStorage.Localization.Loc)
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)

local Theme        = require(script.Parent.Theme)
local PanelManager = require(script.Parent.PanelManager)
local Icons        = require(script.Parent.Icons)
local ClientState  = require(script.Parent.Parent.Controllers.ClientState)
local Unlock       = require(script.Parent.Unlock)

local Hud = {}

-- Merker auf die Labels, damit refresh() nicht jedes Mal suchen muss
local _gummyLabel: TextLabel?     = nil
local _goldLabel: TextLabel?      = nil
local _rankLabel: TextLabel?      = nil
local _multLabel: TextLabel?      = nil
local _languageButton: TextButton? = nil

-- HBB Paket 1: Ziel der fliegenden Icons (UI/Feedback). Schluessel = Art des
-- Gewinns ("gummies", "goldGummies", "rank", "rebirth").
local _pills: { [string]: Frame } = {}

-- HBB Paket 3: Pille → Element-Id der Freischaltung, und die "!"-Badges
local PILL_ELEMENT: { [string]: string } = {
	gummies = "pill_gummies", goldGummies = "pill_gold", rank = "pill_rank", rebirth = "pill_rebirth",
}
local _badges: { [string]: Frame } = {}
-- Eine Pille ohne Klick gilt nach so vielen Sekunden Sichtbarkeit als gesehen
local SEEN_AFTER_SECONDS = 4

local function makeBadge(pill: Frame): Frame
	local badge = Theme.panel("NewBadge", pill, Theme.COLORS.bad)
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position    = UDim2.new(1, 6, 0, -6)
	badge.Size        = UDim2.fromOffset(20, 20)
	badge.ZIndex      = 6
	badge.Visible     = false
	Theme.corner(badge, 10)
	local bang = Theme.label("Bang", badge, "!")
	bang.Size = UDim2.fromScale(1, 1)
	bang.TextXAlignment = Enum.TextXAlignment.Center
	bang.ZIndex = 7
	return badge
end

local function refreshUnlocks()
	for kind, pill in _pills do
		local id = PILL_ELEMENT[kind]
		if id then
			Unlock.apply(id, pill)
			local badge = _badges[kind]
			if badge then
				local isNew = Unlock.isNew(id)
				badge.Visible = isNew
				if isNew and not badge:GetAttribute("Timer") then
					badge:SetAttribute("Timer", true)
					task.delay(SEEN_AFTER_SECONDS, function()
						Unlock.markSeen(id)
					end)
				end
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Bausteine
--------------------------------------------------------------------------------

-- Eine "Pille": farbiger Kreis mit Symbol links, Wert rechts.
-- Gibt Wert-Label UND Pille zurueck — manche Pillen sind anklickbar.
local PILL_H = 40

-- Das Icon ragt links ueber den Rand der Pille hinaus (wie bei den grossen
-- Genre-Vorbildern): so wirkt die Zahl "an" das Symbol gehaengt statt in
-- einem Kasten zu stehen. Ohne Bild-Asset sitzt stattdessen ein farbiger
-- Kreis mit Kuerzel dort (Icons.make-Fallback).
local function makePill(parent: Instance, order: number, iconName: string, fallback: string, iconColor: Color3): (TextLabel, Frame)
	local pill = Theme.panel("Pill", parent, Theme.COLORS.panelDeep)
	pill.Size        = UDim2.new(1, 0, 0, PILL_H)
	pill.LayoutOrder = order

	local holder = Theme.container("IconHolder", pill)
	holder.AnchorPoint = Vector2.new(0, 0.5)
	holder.Position    = UDim2.new(0, -8, 0.5, 0)
	holder.Size        = UDim2.fromOffset(PILL_H + 12, PILL_H + 12)
	holder.ZIndex      = 4

	if Icons.has(iconName) then
		local icon = Icons.make(holder, iconName)
		icon.Size   = UDim2.fromScale(1, 1)
		icon.ZIndex = 4
	else
		local badge = Instance.new("Frame")
		badge.Name             = "Badge"
		badge.Size             = UDim2.fromScale(0.82, 0.82)
		badge.AnchorPoint      = Vector2.new(0.5, 0.5)
		badge.Position         = UDim2.fromScale(0.5, 0.5)
		badge.BackgroundColor3  = iconColor
		badge.BorderSizePixel   = 0
		badge.ZIndex            = 4
		badge.Parent            = holder
		Theme.corner(badge, 22)
		Theme.stroke(badge, Theme.COLORS.outline, 3)
		Theme.gradient(badge, Color3.fromRGB(255, 255, 255), Color3.fromRGB(190, 190, 200))

		local iconLabel = Icons.make(badge, iconName, fallback)
		iconLabel.Size     = UDim2.fromScale(0.7, 0.7)
		iconLabel.Position = UDim2.fromScale(0.15, 0.15)
		iconLabel.ZIndex   = 5
	end

	local value = Theme.label("Value", pill, "0")
	value.Position = UDim2.new(0, PILL_H + 8, 0, 3)
	value.Size     = UDim2.new(1, -(PILL_H + 16), 1, -6)
	value.ZIndex   = 3
	Theme.outlineText(value, 2)

	return value, pill
end

--------------------------------------------------------------------------------
-- Aktualisieren
--------------------------------------------------------------------------------

local function refresh(data: Types.PlayerDataUpdate)
	refreshUnlocks()
	if _gummyLabel then
		_gummyLabel.Text = Theme.formatNumber(data.gummies)
	end
	if _goldLabel then
		_goldLabel.Text = Theme.formatNumber(data.goldGummies)
	end
	if _rankLabel then
		-- Der Rang-NAME steht im Spielstand (englisch, als er vergeben wurde);
		-- angezeigt wird der uebersetzte Name zur Stufe, der gespeicherte nur
		-- als Rueckfall.
		_rankLabel.Text = Loc.name("rank." .. data.rank.tier, data.rank.name)
	end
	if _multLabel then
		_multLabel.Text = string.format("x%s  (%s)", Loc.formatDecimal(data.rebirthMult, 2), Loc.formatNumber(data.rebirthCount))
	end
end

-- Sprachwechsel: alles, was aus dem Spielstand gebaut wird, neu schreiben
-- und das Kuerzel auf dem Sprach-Knopf nachziehen.
local function onLanguageChanged()
	local data = ClientState.get()
	if data then
		refresh(data)
	end

	local button = _languageButton
	if button and not FeatureFlags.isOn("UI_V2_GUIDE") then
		button.Text = string.upper(Loc.getLanguage())
	end
end

--------------------------------------------------------------------------------
-- HBB Paket 1: Anker und Puls fuer fliegende Icons
--------------------------------------------------------------------------------

-- Die Pille, zu der ein Gewinn dieser Art fliegt (nil = keine Pille dafuer).
function Hud.getPillAnchor(kind: string): GuiObject?
	return _pills[kind]
end

-- Kurzes Aufpumpen der Pille, wenn ein Icon ankommt. Laeuft ueber eine
-- UIScale, damit Layout und Groesse der Pille unangetastet bleiben.
function Hud.pulse(kind: string)
	local pill = _pills[kind]
	if not pill then return end
	local scale = pill:FindFirstChild("PulseScale")
	if not scale then
		local created = Instance.new("UIScale")
		created.Name   = "PulseScale"
		created.Parent = pill
		scale = created
	end
	local uiScale = scale :: UIScale
	uiScale.Scale = 1.12
	TweenService:Create(uiScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

--------------------------------------------------------------------------------
-- Initialisierung
--------------------------------------------------------------------------------

function Hud.init(screenGui: ScreenGui)
	-- Links oben: Waehrungen
	local left = Theme.container("HudLeft", screenGui)
	left.AnchorPoint = Vector2.new(0, 0)
	-- +12 nach rechts: das Icon ragt links aus der Pille heraus
	left.Position    = UDim2.new(0.012, 12, 0, 12)
	left.Size        = UDim2.new(0.21, 0, 0, PILL_H * 2 + 6)

	local leftConstraint = Instance.new("UISizeConstraint")
	leftConstraint.MinSize = Vector2.new(150, 0)
	leftConstraint.MaxSize = Vector2.new(260, math.huge)
	leftConstraint.Parent  = left

	local leftLayout = Theme.listLayout(left, 6)
	leftLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left

	local gummyPill, goldPill
	_gummyLabel, gummyPill = makePill(left, 1, "gummy", "G", Theme.COLORS.gummy)
	_goldLabel, goldPill   = makePill(left, 2, "goldgummy", "$", Theme.COLORS.goldGummy)
	_pills.gummies     = gummyPill
	_pills.goldGummies = goldPill

	-- Rechts oben: Rang und Rebirth
	local right = Theme.container("HudRight", screenGui)
	right.AnchorPoint = Vector2.new(1, 0)
	right.Position    = UDim2.new(0.988, 0, 0, 12)
	right.Size        = UDim2.new(0.24, 0, 0, PILL_H * 2 + 6)

	local rightConstraint = Instance.new("UISizeConstraint")
	rightConstraint.MinSize = Vector2.new(160, 0)
	rightConstraint.MaxSize = Vector2.new(280, math.huge)
	rightConstraint.Parent  = right

	local rightLayout = Theme.listLayout(right, 6)
	rightLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right

	local rankPill
	_rankLabel, rankPill = makePill(right, 1, "crown", "R", Theme.COLORS.accent)
	_pills.rank = rankPill

	local multLabel, multPill = makePill(right, 2, "rebirth", "*", Theme.COLORS.good)
	_multLabel = multLabel
	_pills.rebirth = multPill

	-- Die Pille selbst ist der Rebirth-Knopf. Ein durchsichtiger Button
	-- darueber, damit der Aufbau der Pille unveraendert bleibt.
	local rebirthHit = Instance.new("TextButton")
	rebirthHit.Name                   = "RebirthHit"
	rebirthHit.BackgroundTransparency = 1
	rebirthHit.Text                   = ""
	rebirthHit.Size                   = UDim2.fromScale(1, 1)
	rebirthHit.ZIndex                 = 3
	rebirthHit.Parent                 = multPill

	rebirthHit.Activated:Connect(function()
		Unlock.markSeen("pill_rebirth")
		PanelManager.toggle("Rebirth")
	end)

	for kind, pill in _pills do
		_badges[kind] = makeBadge(pill)
	end

	-- Sprach-Knopf: direkt unter den Waehrungs-Pillen, klein und unauffaellig.
	-- Zeigt das Kuerzel der aktiven Sprache und oeffnet die Auswahl.
	local languageButton = Theme.button("Language", screenGui, string.upper(Loc.getLanguage()), Theme.COLORS.panelLight)
	languageButton.AnchorPoint = Vector2.new(0, 0)
	languageButton.Position    = UDim2.new(0.012, 12, 0, 106)
	languageButton.Size        = UDim2.new(0, 70, 0, 30)
	languageButton.TextColor3  = Theme.COLORS.text
	languageButton.TextXAlignment = Enum.TextXAlignment.Right
	Theme.padding(languageButton, 0).PaddingRight = UDim.new(0, 10)
	if Icons.has("globe") then
		local globe = Icons.make(languageButton, "globe")
		globe.AnchorPoint = Vector2.new(0, 0.5)
		globe.Position    = UDim2.new(0, 6, 0.5, 0)
		globe.Size        = UDim2.fromOffset(22, 22)
	end
	languageButton.Activated:Connect(function()
		PanelManager.toggle("Language")
	end)
	_languageButton = languageButton

	-- HBB Paket 2: kein Globus mit Sprachkuerzel im HUD mehr, sondern ein
	-- kleines Zahnrad (gleiche Stelle, gleiche Funktion). Die Standardsprache
	-- bleibt die Roblox-Sprache des Clients. Eine eigene Profilkarte, in die
	-- eine Sprach-Zeile passen wuerde, gibt es nicht (ProfilePanel zeigt nur
	-- andere Spieler).
	if FeatureFlags.isOn("UI_V2_GUIDE") then
		for _, child in languageButton:GetChildren() do
			if child.Name == "Icon" then child:Destroy() end
		end
		languageButton.Text = "⚙"
		languageButton.TextXAlignment = Enum.TextXAlignment.Center
		languageButton.Size = UDim2.new(0, 30, 0, 30)
		local padding = languageButton:FindFirstChildOfClass("UIPadding")
		if padding then padding.PaddingRight = UDim.new(0, 0) end
	end

	-- Sofort mit dem aktuellen Stand fuellen, danach bei jeder Aenderung
	ClientState.onChanged(refresh)
	Loc.onChanged(onLanguageChanged)

	print("[Hud] Initialisiert")
end

return Hud
