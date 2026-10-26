--!strict
-- PotionBar.luau
-- StarterPlayerScripts/UI/PotionBar.luau
--
-- Einzige Zustaendigkeit:
--   - Laufende Traenke im HUD zeigen (26.10., FeatureFlags.POTIONS_V1): je
--     Sorte ein Chip mit Zeichen, Faktor und Restzeit, links unter der
--     Knopf-Zeile. Dazu der Hinweis beim Kauf (PotionActivated).
--
-- Liest nur den Datenstand (PlayerDataUpdate.potions: Restzeit ab Empfang)
-- und zaehlt lokal im Sekundentakt herunter — der Server traegt den Effekt
-- selbst aus und schickt dann einen neuen Stand. Erreicht der lokale Zaehler
-- 0, verschwindet der Chip sofort (nicht erst mit dem naechsten Paket).
-- Kein Heartbeat: eine Schleife mit task.wait(1), die nur laeuft, solange
-- mindestens ein Trank wirkt (Loc-Regel: Texte nur bei voller Sekunde bauen).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types        = require(ReplicatedStorage.Network.Types)
local Remotes      = require(ReplicatedStorage.Network.Remotes)
local Loc          = require(ReplicatedStorage.Localization.Loc)
local Names        = require(ReplicatedStorage.Localization.Names)
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)
local PotionConfig = require(ReplicatedStorage.Config.PotionConfig)

local Theme  = require(script.Parent.Theme)
local Icons  = require(script.Parent.Icons)
local Toast  = require(script.Parent.Toast)
local Notify = require(script.Parent.Notify)
local Moment = require(script.Parent.Moment)
local ClientState = require(script.Parent.Parent.Controllers.ClientState)

local PotionBar = {}

local HONEY = FeatureFlags.isOn("UI_HONEY_SKIN")
local CHIP_W = 186   -- so breit wie die Knopf-Zeile / die goldene Rebirth-Leiste
local CHIP_H = 30
local GAP = 4

type Chip = { frame: Frame, glyph: GuiObject, text: TextLabel }
type Effect = { kind: string, potionId: string, multiplier: number, endsAt: number }

local _root: Frame? = nil
local _chips: { [string]: Chip } = {}
local _effects: { Effect } = {}
local _running = false

local function colorOf(potionId: string, kind: string): Color3
	local def = PotionConfig.byId(potionId)
	if def then return def.color end
	for _, candidate in PotionConfig.POTIONS do
		if candidate.kind == kind then return candidate.color end
	end
	return Theme.COLORS.accent
end

local function chipFor(kind: string): Chip
	local chip = _chips[kind]
	if chip then return chip end
	local root = _root :: Frame
	local frame = Theme.panel("Chip_" .. kind, root, Theme.COLORS.panelDeep)
	frame.Size = UDim2.fromOffset(CHIP_W, CHIP_H)
	frame.LayoutOrder = table.find(PotionConfig.KINDS, kind :: any) or 99
	frame.Visible = false

	local holder = Theme.container("IconHolder", frame)
	holder.Position = UDim2.fromOffset(4, 3)
	holder.Size = UDim2.fromOffset(CHIP_H - 6, CHIP_H - 6)
	local glyph = Icons.make(holder, "", PotionConfig.GLYPH[kind] or "?")
	glyph.Size = UDim2.fromScale(1, 1)

	local text = Theme.label("Text", frame, "")
	text.Position = UDim2.fromOffset(CHIP_H + 2, 2)
	text.Size = UDim2.new(1, -(CHIP_H + 8), 1, -4)
	text.TextXAlignment = Enum.TextXAlignment.Left
	Theme.outlineText(text, 2)
	local cap = text:FindFirstChildOfClass("UITextSizeConstraint")
	if cap then cap.MaxTextSize = 16 end

	chip = { frame = frame, glyph = glyph, text = text }
	_chips[kind] = chip
	return chip
end

-- Alle Chips nach dem lokalen Zaehler schreiben. Gibt true, solange noch
-- etwas laeuft.
local function render(): boolean
	local now = os.clock()
	local shown: { [string]: boolean } = {}
	local any = false
	for _, effect in _effects do
		local left = math.ceil(effect.endsAt - now)
		if left > 0 then
			any = true
			shown[effect.kind] = true
			local chip = chipFor(effect.kind)
			chip.frame.BackgroundColor3 = colorOf(effect.potionId, effect.kind)
			chip.text.Text = Names.potionKind(effect.kind) .. "  " .. Loc.t("ui.potion.hud", { mult = effect.multiplier, time = Loc.formatDuration(left) })
			chip.frame.Visible = true
		end
	end
	for kind, chip in _chips do
		if not shown[kind] then chip.frame.Visible = false end
	end
	local root = _root
	if root then root.Visible = any end
	return any
end

local function ensureLoop()
	if _running then return end
	_running = true
	task.spawn(function()
		while render() do
			task.wait(1)
		end
		_running = false
	end)
end

local function onData(data: Types.PlayerDataUpdate)
	local list = (data :: any).potions
	local effects: { Effect } = {}
	if typeof(list) == "table" then
		local now = os.clock()
		for _, view in list do
			if typeof(view) == "table" and typeof(view.kind) == "string" and typeof(view.remaining) == "number" then
				table.insert(effects, {
					kind       = view.kind,
					potionId   = tostring(view.potionId),
					multiplier = tonumber(view.multiplier) or 1,
					endsAt     = now + math.max(0, view.remaining),
				})
			end
		end
	end
	_effects = effects
	if render() then ensureLoop() end
end

function PotionBar.init(screenGui: ScreenGui)
	if not FeatureFlags.isOn("POTIONS_V1") then return end

	-- Unter der Knopf-Zeile (HudRow) und, mit Honig-Skin, unter der goldenen
	-- Rebirth-Leiste (RebirthButton: y Zeile + 60 + 3, 44 hoch).
	local rowY = if HONEY then 129 else 106
	local y = rowY + 60 + 3 + (if HONEY then 44 + 6 else 6)
	local root = Theme.container("PotionBar", screenGui)
	root.Position = UDim2.new(0.012, 12, 0, y)
	root.Size = UDim2.fromOffset(CHIP_W, (CHIP_H + GAP) * #PotionConfig.KINDS)
	root.Visible = false
	local layout = Theme.listLayout(root, GAP)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	_root = root

	ClientState.onChanged(onData)
	Loc.onChanged(function() render() end)

	-- Kauf bestaetigt: grosser Moment in der Trank-Farbe (alter Weg: Toast mit
	-- Name, Faktor und Dauer). Faktor und Restzeit stehen danach im Chip.
	Remotes.PotionActivated.OnClientEvent:Connect(function(result: any)
		if typeof(result) ~= "table" then return end
		local typed = result :: Types.PotionActivatedResult
		Notify.emit("potion_bought", function()
			Toast.success(Loc.t("msg.potion_on", {
				name = Names.potion(typed.potionId),
				mult = typed.multiplier,
				time = Loc.formatDuration(typed.remaining),
			}))
		end, function()
			Moment.show("potion", colorOf(typed.potionId, typed.kind), "ui.moment.potion")
		end)
	end)

	print("[PotionBar] Initialisiert")
end

return PotionBar
