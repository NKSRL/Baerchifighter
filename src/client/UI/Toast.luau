--!strict
-- Toast.luau
-- StarterPlayerScripts/UI/Toast.luau
--
-- Einzige Zustaendigkeit:
--   - Kurze Meldungen am unteren Bildschirmrand einblenden
--
-- Wichtigster Zweck: die ActionFailed-Antworten des Servers sichtbar machen.
-- Ohne das wirkt jede abgelehnte Aktion ("nicht genug Gummies", "Brut-Slots
-- belegt") wie ein kaputter Button — der Server lehnt still ab und der
-- Spieler sieht nichts.

local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types   = require(ReplicatedStorage.Network.Types)
local Remotes = require(ReplicatedStorage.Network.Remotes)
local Loc     = require(ReplicatedStorage.Localization.Loc)
local Theme   = require(script.Parent.Theme)
local Notify  = require(script.Parent.Notify)
local Icons   = require(script.Parent.Icons)
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)

local Toast = {}

local LIFETIME   = 3.0    -- Sekunden bis eine Meldung verschwindet
local MAX_STACK  = 4      -- mehr als so viele gleichzeitig sehen niemand an

local _container: Frame? = nil
local _active: { Frame } = {}

-- LayoutOrder muss eine ganze Zahl sein — ein Zeitstempel taugt dafuer nicht
local _order = 0

--------------------------------------------------------------------------------
-- Anzeigen
--------------------------------------------------------------------------------

local function removeToast(toast: Frame)
	for i, existing in _active do
		if existing == toast then
			table.remove(_active, i)
			break
		end
	end
	toast:Destroy()
end

-- `message` ist entweder ein fertiger String (Texte, die der Client selbst
-- baut) oder eine LocMsg vom Server. Aufgeloest wird HIER, im Moment der
-- Anzeige — so erscheint auch eine Meldung, die noch vor dem Sprachwechsel
-- gesendet wurde, in der aktuellen Sprache.
function Toast.show(message: string | Types.LocMsg, color: Color3?)
	local container = _container
	if not container then return end

	local text = Loc.resolve(message)

	-- Aelteste rauswerfen wenn der Stapel voll ist
	while #_active >= MAX_STACK do
		removeToast(_active[1])
	end

	_order += 1

	-- Honig-Skin: die Meldung ist ein Bild-Knopf (dunkel = Fehler, hell = Erfolg/Info), 9-Slice
	-- gedehnt auf Textbreite. Ohne Schalter/Bild bleibt der alte Kasten (Rueckfall unten).
	local isError = (color == nil) or (color == Theme.COLORS.bad)
	local artName = if isError then "honey/btn_dark" else "honey/btn_light"
	if FeatureFlags.isOn("UI_HONEY_SKIN") and Icons.hasUi(artName) then
		local HEIGHT = 56
		local honeyToast = Instance.new("Frame")
		honeyToast.Name                   = "Toast"
		honeyToast.BackgroundTransparency = 1
		honeyToast.BorderSizePixel        = 0
		honeyToast.Size                   = UDim2.new(1, 0, 0, HEIGHT)
		honeyToast.LayoutOrder            = _order
		honeyToast.Parent                 = container

		-- Bildausschnitt wie in Icons.CROPS (btn_dark 1011x262 ab (4,116), btn_light 1008x265 ab (8,116))
		local cropOffset = if isError then Vector2.new(4, 116) else Vector2.new(8, 116)
		local cropSize   = if isError then Vector2.new(1011, 262) else Vector2.new(1008, 265)
		local art = Icons.honeyImage(honeyToast, artName,
			Rect.new(120, 60, cropSize.X - 120, cropSize.Y - 60), HEIGHT / cropSize.Y, cropOffset, cropSize)
		if art then
			art.ZIndex = 1

			local honeyLabel = Instance.new("TextLabel")
			honeyLabel.Name                   = "Text"
			honeyLabel.BackgroundTransparency = 1
			honeyLabel.Position               = UDim2.new(0, 26, 0, 6)
			honeyLabel.Size                   = UDim2.new(1, -52, 1, -12)
			honeyLabel.Font                   = Enum.Font.FredokaOne
			honeyLabel.Text                   = text
			honeyLabel.TextScaled             = true
			honeyLabel.TextColor3             = Color3.new(1, 1, 1)
			honeyLabel.TextStrokeColor3       = Color3.fromRGB(60, 30, 10)
			honeyLabel.TextStrokeTransparency = 0.2
			honeyLabel.ZIndex                 = 2
			honeyLabel.Parent                 = honeyToast
			local limit = Instance.new("UITextSizeConstraint")
			limit.MaxTextSize = 22
			limit.MinTextSize = 10
			limit.Parent      = honeyLabel

			table.insert(_active, honeyToast)

			art.ImageTransparency            = 1
			honeyLabel.TextTransparency      = 1
			honeyLabel.TextStrokeTransparency = 1
			TweenService:Create(art, TweenInfo.new(0.15), { ImageTransparency = 0 }):Play()
			TweenService:Create(honeyLabel, TweenInfo.new(0.15), { TextTransparency = 0, TextStrokeTransparency = 0.2 }):Play()

			task.delay(LIFETIME, function()
				if honeyToast.Parent == nil then return end
				local fade = TweenService:Create(art, TweenInfo.new(0.25), { ImageTransparency = 1 })
				TweenService:Create(honeyLabel, TweenInfo.new(0.25), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
				fade:Play()
				fade.Completed:Wait()
				removeToast(honeyToast)
			end)
			return
		end
		honeyToast:Destroy()
	end

	local toast = Theme.panel("Toast", container, Theme.COLORS.panelDeep)
	toast.Size         = UDim2.new(1, 0, 0, 34)
	toast.LayoutOrder  = _order
	toast.BackgroundTransparency = 0.05

	local accent = Instance.new("Frame")
	accent.Name             = "Accent"
	accent.Size             = UDim2.new(0, 6, 1, -12)
	accent.Position         = UDim2.new(0, 8, 0, 6)
	accent.BackgroundColor3  = color or Theme.COLORS.bad
	accent.BorderSizePixel   = 0
	accent.Parent            = toast
	Theme.corner(accent, 3)

	local label = Theme.label("Text", toast, text)
	label.Position   = UDim2.new(0, 22, 0, 4)
	label.Size       = UDim2.new(1, -30, 1, -8)
	label.TextColor3 = Theme.COLORS.text

	table.insert(_active, toast)

	-- Einblenden
	toast.BackgroundTransparency = 1
	label.TextTransparency       = 1
	TweenService:Create(toast, TweenInfo.new(0.15), { BackgroundTransparency = 0.05 }):Play()
	TweenService:Create(label, TweenInfo.new(0.15), { TextTransparency = 0 }):Play()

	task.delay(LIFETIME, function()
		if toast.Parent == nil then return end
		local fade = TweenService:Create(toast, TweenInfo.new(0.25), { BackgroundTransparency = 1 })
		TweenService:Create(label, TweenInfo.new(0.25), { TextTransparency = 1 }):Play()
		fade:Play()
		fade.Completed:Wait()
		removeToast(toast)
	end)
end

function Toast.success(message: string | Types.LocMsg)
	Toast.show(message, Theme.COLORS.good)
end

function Toast.info(message: string | Types.LocMsg)
	Toast.show(message, Theme.COLORS.accent)
end

--------------------------------------------------------------------------------
-- Initialisierung
--------------------------------------------------------------------------------

function Toast.init(screenGui: ScreenGui)
	local container = Theme.container("ToastStack", screenGui)
	container.AnchorPoint = Vector2.new(0.5, 1)
	-- v12: ueber der unteren Pet-Leiste (PetBar, ~76 px hoch) statt darauf
	container.Position    = UDim2.new(0.5, 0, 1, -96)
	container.Size        = UDim2.fromScale(0.45, 0.25)

	-- Ueber allem anderen: Panels liegen auf ZIndex 10, die Kampf- und
	-- Hatch-Overlays auf 30. Eine Fehlermeldung DAHINTER waere sinnlos —
	-- und genau der haeufigste Fall ("Kein Honig da") entsteht bei offener
	-- Baerchi-Karte, also waehrend ein Panel im Weg steht.
	container.ZIndex = 50

	local layout = Theme.listLayout(container, 6)
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom

	-- Auf schmalen Bildschirmen (Handy) mehr Breite zulassen
	local constraint = Instance.new("UISizeConstraint")
	constraint.MinSize = Vector2.new(260, 0)
	constraint.Parent  = container

	_container = container

	-- Der eigentliche Grund fuer dieses Modul
	-- `reason` ist eine LocMsg (Schluessel + Zahlen) — oder, bei Altlasten, ein
	-- fertiger String. Loc.resolve nimmt beides.
	Remotes.ActionFailed.OnClientEvent:Connect(function(action: any, reason: any)
		Notify.emit("action_failed", function()
			Toast.show(Loc.resolve(reason), Theme.COLORS.bad)
		end)
	end)

	print("[Toast] Initialisiert")
end

return Toast
