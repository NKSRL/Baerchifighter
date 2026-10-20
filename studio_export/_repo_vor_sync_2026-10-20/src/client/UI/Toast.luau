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
