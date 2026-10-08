--!strict
-- TowerPanel.luau
-- StarterPlayerScripts/UI/TowerPanel.luau
--
-- Einzige Zustaendigkeit:
--   - Das Tower-Fenster im neuen Look (08.10., Paket D, FeatureFlags.
--     TOWER_PANEL_V2): Tower waehlen (Karten mit Zustand AKTIV / WAEHLEN /
--     NEU / GESPERRT) und von hier aus losschicken (Einstiegsleiste mit
--     Gratis-Start, bezahltem Skip und Gamepass-Knopf).
--
-- Geoeffnet vom Tower-Terminal an der Bruecke (Hauptweg), vom Prompt an der
-- Arena, vom Antippen des Tower-Namens in der Pet-Leiste. Es meldet sich
-- unter dem Namen "Combat" an (PanelManager.ARENA_PANEL) — alle bisherigen
-- Wege zur Tower-Wahl landen damit hier. Lauf-Ergebnis- und Meilenstein-
-- Meldungen bleiben im CombatPanel (die laufen auch bei geschlossenem
-- Fenster).
--
-- Gebaut ausschliesslich aus UI/Kit (Tokens Theme.v2). Der Server prueft
-- alles selbst (offen? bezahlbar? Pass?); die Karten rechnen mit denselben
-- Funktionen aus TowerConfig nur fuer die Anzeige.
--
-- Hierarchie (Kinder 7-14): der Blick soll zuerst auf den GRATIS-Start
-- fallen — groesster Knopf, kraeftigste Farbe, als einziges Element mit Puls.
-- Der bezahlte Skip ist klein, cremefarben, ohne Glanz und Puls. Keine
-- falschen Countdowns, nichts versteckt.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types          = require(ReplicatedStorage.Network.Types)
local Remotes        = require(ReplicatedStorage.Network.Remotes)
local Loc            = require(ReplicatedStorage.Localization.Loc)
local TowerConfig    = require(ReplicatedStorage.Config.TowerConfig)
local GamepassConfig = require(ReplicatedStorage.Config.GamepassConfig)
local FeatureFlags   = require(ReplicatedStorage.Config.FeatureFlags)

local Theme           = require(script.Parent.Theme)
local Kit             = require(script.Parent.Kit)
local Icons           = require(script.Parent.Icons)
local Notify          = require(script.Parent.Notify)
local Moment          = require(script.Parent.Moment)
local Toast           = require(script.Parent.Toast)
local PanelManager    = require(script.Parent.PanelManager)
local PitResumeDialog = require(script.Parent.PitResumeDialog)
local ClientState     = require(script.Parent.Parent.Controllers.ClientState)

local TowerPanel = {}

local T = Kit.T
local PANEL_NAME = PanelManager.ARENA_PANEL   -- "Combat"
local PASS_KEY   = "SKIP_PASS"

-- Masse (Oberflaechen-Einheiten, 8er-Raster)
local DESIGN     = Vector2.new(640, 688)
local MIN_HEIGHT = 316   -- Kopf + eine Karte + Leiste (kompakt)
local HEADER_H   = 84
local STATUS_H   = 40
local FOOTER_H   = 140
-- Kompakt (niedrige Bildschirme, Handy quer): kleinerer Kopf, ohne
-- Statuszeile und ohne die erste Leisten-Zeile (Gummies stehen ohnehin im
-- HUD); die Liste scrollt. Ab dieser Fensterhoehe:
local COMPACT_BELOW = 520
local HEADER_H_COMPACT = 60
local FOOTER_H_COMPACT = 104
local CARD_H     = 116
local PAD        = T.space.m
local BADGE      = 80
local RIGHT_W    = 140
-- Freie Raender: oben HUD-Luft, unten Pet-Leiste (68 + Abstand), rechts
-- Menueleiste (Kacheln bis 94 + Rand), links etwas Luft. Auf kurzen
-- Bildschirmen (Handy quer) stehen HUD-Pillen und Menueleiste neben dem
-- Fenster: dort links/rechts mehr Platz lassen, oben weniger.
local function reserve(screen: Vector2): Kit.Reserve
	if screen.Y < COMPACT_BELOW then
		return { top = 6, bottom = 90, left = 196, right = 84 }
	end
	-- Schmalere Bildschirme (Tablet, 1366): links an den HUD-Pillen vorbei
	local left = if screen.X < 1400 then 196 else 12
	return { top = 12, bottom = 96, left = left, right = 112 }
end
local _compact = false

type CardView = {
	def      : TowerConfig.TowerDef,
	card     : Kit.Card,
	badge    : Frame,
	lockIcon : GuiObject,
	title    : TextLabel,
	progress : Kit.Progress,
	reward   : TextLabel,
	rewardIcon : Frame,
	choose   : Kit.Button,
	active   : Frame,
	newBadge : Frame,
	lockChip : Frame,
	lockBar  : Kit.Progress,
	glimmer  : Frame,
	state    : string,
}

local _window: Kit.Window? = nil
local _status: { selected: Frame, record: Frame, nextOpen: Frame }? = nil
local _list: ScrollingFrame? = nil
local _cards: { [string]: CardView } = {}
local _order: { string } = {}
local _footer: Frame? = nil
local _gummyChip: Frame? = nil
local _hint: TextLabel? = nil
local _primary: Kit.Button? = nil
local _skip: Kit.Button? = nil
local _premium: Kit.Button? = nil
local _freeBadge: Frame? = nil
local _stopPulse: (() -> ())? = nil
local _stopLoop: (() -> ())? = nil
local _isOpen = false
local _petState = "Home"

--------------------------------------------------------------------------------
-- Hilfen
--------------------------------------------------------------------------------

local function towerName(id: string): string
	return Loc.t("tower." .. id .. ".name")
end

local function hasPass(): boolean
	return Players.LocalPlayer:GetAttribute(GamepassConfig.attributeName(PASS_KEY)) == true
end

local function cardState(def: TowerConfig.TowerDef, data: Types.PlayerDataUpdate): string
	local towers = data.towers
	if not towers then return if def.id == TowerConfig.FIRST_TOWER then "active" else "locked" end
	local open = TowerConfig.isOpen(data.rebirthCount, def.id, towers.records, (towers :: any).unlocked)
	if not open then return "locked" end
	if towers.selected == def.id then return "active" end
	if TowerConfig.isNew(def.id, towers :: any) then return "new" end
	return "open"
end

-- Naechster Meilenstein als (Icon-Name, Rueckfall, Text) fuer die Karte.
local function rewardHint(def: TowerConfig.TowerDef, data: Types.PlayerDataUpdate): (string?, string?, string?)
	local towers = data.towers
	local record = if towers then towers.records[def.id] or 0 else 0
	local claimed = if towers then towers.claimed[def.id] else nil
	local stage = TowerConfig.nextMilestoneStage(def.id, claimed, record + 1)
	if not stage then return nil, nil, nil end
	local m = TowerConfig.getMilestone(def.id, stage)
	if not m then return nil, nil, nil end
	if m.eggs > 0 then
		return "egg", "🥚", Loc.t("ui.tower2.reward_egg", { stage = stage, n = m.eggs })
	elseif m.goldGummies > 0 then
		return "goldgummy", "$", Loc.t("ui.tower2.reward_amount", { stage = stage, n = Theme.formatNumber(m.goldGummies) })
	elseif m.endlessLevels > 0 then
		return "trophy", "★", Loc.t("ui.tower2.reward_endless", { stage = stage, n = m.endlessLevels })
	end
	return "gummy", "G", Loc.t("ui.tower2.reward_amount", { stage = stage, n = Theme.formatNumber(m.gummies) })
end

--------------------------------------------------------------------------------
-- Karte
--------------------------------------------------------------------------------

local function buildCard(parent: Instance, def: TowerConfig.TowerDef, order: number): CardView
	local card = Kit.card("Tower_" .. def.id, parent, CARD_H)
	card.holder.LayoutOrder = order
	local face = card.face
	local endless = def.id == "Endless"
	if endless then
		-- Endless: besondere Karte in Rosa/Lila
		Kit.gradient(face, Color3.fromRGB(255, 236, 248), Color3.fromRGB(240, 214, 255))
	end

	local badge = Kit.towerBadge("Badge", face, def.look, def.color, def.numeral, BADGE)
	badge.AnchorPoint = Vector2.new(0, 0.5)
	badge.Position = UDim2.new(0, 14, 0.5, -1)

	local lockIcon = Kit.lockIcon(badge, 34)
	lockIcon.AnchorPoint = Vector2.new(1, 1)
	lockIcon.Position = UDim2.new(1, 8, 1, 8)
	lockIcon.ZIndex = 38

	local left = 14 + BADGE + 14
	local title = Kit.text("Title", face, towerName(def.id), T.text.cardTitle)
	title.Position = UDim2.fromOffset(left, 10)
	title.Size = UDim2.new(1, -(left + RIGHT_W + 12), 0, 30)
	title.ZIndex = 32

	local progress = Kit.progress("Record", face, 26)
	progress.track.Position = UDim2.fromOffset(left, 46)
	progress.track.Size = UDim2.new(1, -(left + RIGHT_W + 16), 0, 26)

	local rewardIcon = Kit.frame("RewardIcon", face)
	rewardIcon.Position = UDim2.fromOffset(left, 80)
	rewardIcon.Size = UDim2.fromOffset(24, 24)
	rewardIcon.ZIndex = 32
	local reward = Kit.text("Reward", face, "", T.text.small + 1, { color = T.color.inkSoft })
	reward.Position = UDim2.fromOffset(left + 30, 80)
	reward.Size = UDim2.new(1, -(left + 30 + RIGHT_W + 12), 0, 24)
	reward.ZIndex = 32

	-- Rechts: Waehlen-Knopf ...
	local choose = Kit.button("Choose", face, "choose", Loc.t("ui.tower2.choose"), 24)
	choose.button.AnchorPoint = Vector2.new(1, 0.5)
	choose.button.Position = UDim2.new(1, -14, 0.5, 0)
	choose.button.Size = UDim2.fromOffset(RIGHT_W - 8, 64)
	choose.button.Activated:Connect(function()
		if not choose.button.Active then return end
		Kit.playSound("select")
		Remotes.RequestSelectTower:FireServer(def.id)
	end)

	-- ... oder AKTIV-Band ...
	local active = Kit.badge("Active", face, Loc.t("ui.tower2.active"), T.color.active, 0)
	active.AnchorPoint = Vector2.new(1, 0.5)
	active.Position = UDim2.new(1, -18, 0.5, 0)
	active.Size = UDim2.fromOffset(0, 40)
	local activeLabel = active:FindFirstChild("Text") :: TextLabel
	activeLabel.TextSize = 22

	-- ... oder Fortschritt zur Freischaltung
	local lockChip = Kit.frame("LockInfo", face)
	lockChip.AnchorPoint = Vector2.new(1, 0.5)
	lockChip.Position = UDim2.new(1, -14, 0.5, 0)
	lockChip.Size = UDim2.fromOffset(RIGHT_W, 68)
	lockChip.ZIndex = 32
	local lockText = Kit.text("Text", lockChip, "", T.text.small + 1, { color = T.color.ink, align = Enum.TextXAlignment.Center, wrap = true })
	lockText.Size = UDim2.new(1, 0, 0, 36)
	lockText.ZIndex = 33
	local lockBar = Kit.progress("Bar", lockChip, 24, T.color.honey)
	lockBar.track.Position = UDim2.fromOffset(0, 40)

	-- NEU-Aufkleber oben links (schraeg) und Glanz fuer frisch freie Karten
	local newBadge = Kit.badge("New", card.holder, Loc.t("ui.tower2.new"), T.color.new, -10)
	newBadge.Position = UDim2.fromOffset(46, 4)
	newBadge.ZIndex = 45
	local newLabel = newBadge:FindFirstChild("Text") :: TextLabel
	newLabel.ZIndex = 46

	local glimmer = Kit.frame("Glimmer", face, T.color.white)
	glimmer.Size = UDim2.new(0.22, 0, 1, 0)
	glimmer.Rotation = 18
	glimmer.BackgroundTransparency = 0.6
	glimmer.ZIndex = 31
	glimmer.Visible = false
	local glimmerFade = Instance.new("UIGradient")
	glimmerFade.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.2), NumberSequenceKeypoint.new(1, 1),
	})
	glimmerFade.Parent = glimmer
	face.ClipsDescendants = false

	return {
		def = def, card = card, badge = badge, lockIcon = lockIcon, title = title,
		progress = progress, reward = reward, rewardIcon = rewardIcon, choose = choose,
		active = active, newBadge = newBadge, lockChip = lockChip, lockBar = lockBar,
		glimmer = glimmer, state = "",
	}
end

local function refreshCard(view: CardView, data: Types.PlayerDataUpdate)
	local def = view.def
	local towers = data.towers
	local state = cardState(def, data)
	view.state = state
	local record = if towers then towers.records[def.id] or 0 else 0
	local endless = def.id == "Endless"

	view.title.Text = if endless
		then towerName(def.id)
		else Loc.t("ui.tower2.title_stages", { tower = towerName(def.id), stages = def.stages })

	local locked = state == "locked"
	view.lockIcon.Visible = locked
	view.choose.button.Visible = state == "open" or state == "new"
	view.active.Visible = state == "active"
	view.newBadge.Visible = state == "new"
	view.lockChip.Visible = locked
	view.glimmer.Visible = state == "new"

	-- Rekord-Balken (Endless: ohne Ende, Balken zeigt das naechste Zehnerziel)
	if endless then
		local goal = math.max(10, (math.floor(record / 10) + 1) * 10)
		view.progress.set(record / goal, Loc.t("ui.tower2.record_endless", { record = record }))
	else
		view.progress.set(record / def.stages, Loc.t("ui.tower2.record", { record = record, stages = def.stages }))
	end
	view.progress.track.Visible = not locked or record > 0

	-- Meilenstein
	for _, child in view.rewardIcon:GetChildren() do child:Destroy() end
	local iconName, fallback, text = rewardHint(def, data)
	if iconName and text and not locked then
		local icon = Icons.make(view.rewardIcon, iconName, fallback)
		icon.Size = UDim2.fromScale(1, 1)
		icon.ZIndex = 33
		view.reward.Text = text
		view.reward.Visible = true
	else
		view.reward.Visible = locked
		view.reward.Text = if locked then "🔒 " .. Loc.t("ui.tower2.locked_hint") else ""
	end
	-- Gesperrt: Hinweis in die Mitte der Karte (dort stuende sonst der Balken)
	view.reward.Position = UDim2.fromOffset(14 + BADGE + 14 + (if locked then 0 else 30), if locked then 48 else 80)

	-- Gesperrt: gedaempft, aber lesbar
	if locked then
		local prev, have, need = TowerConfig.getUnlockProgress(def.id, if towers then towers.records else nil)
		local lockText = view.lockChip:FindFirstChild("Text") :: TextLabel
		lockText.Text = if prev
			then Loc.t("ui.tower2.unlock_by", { tower = towerName(prev) })
			else ""
		view.lockBar.set(if need > 0 then have / need else 0, string.format("%d/%d", have, need))
		Kit.gradient(view.card.face, T.color.cardLocked, T.color.sunk)
		Kit.gradient(view.badge, Theme.shade(def.color, 0.1):Lerp(T.color.lock, 0.6), T.color.lock)
	else
		if endless then
			Kit.gradient(view.card.face, Color3.fromRGB(255, 236, 248), Color3.fromRGB(240, 214, 255))
		else
			Kit.gradient(view.card.face, T.color.card, T.color.surface)
		end
		Kit.gradient(view.badge, Theme.shade(def.color, 0.35), Theme.shade(def.color, -0.12))
	end

	view.card.stroke.Color = if state == "active" then T.color.honeyBottom else T.color.outline
	view.card.stroke.Thickness = if state == "active" then T.stroke.card + 2 else T.stroke.card
	view.choose.label.Text = Loc.t("ui.tower2.choose")
	view.choose.setEnabled(true)
	local activeLabel = view.active:FindFirstChild("Text")
	if activeLabel and activeLabel:IsA("TextLabel") then activeLabel.Text = "✔ " .. Loc.t("ui.tower2.active") end
	local newLabel = view.newBadge:FindFirstChild("Text")
	if newLabel and newLabel:IsA("TextLabel") then newLabel.Text = Loc.t("ui.tower2.new") end
end

--------------------------------------------------------------------------------
-- Status und Einstiegsleiste
--------------------------------------------------------------------------------

local function refreshStatus(data: Types.PlayerDataUpdate)
	local status = _status
	if not status then return end
	local towers = data.towers
	local selected = if towers then towers.selected else TowerConfig.FIRST_TOWER
	local def = TowerConfig.get(selected) or TowerConfig.TOWERS[1]
	local record = if towers then towers.records[selected] or 0 else 0
	Kit.setChip(status.selected, Loc.t("ui.tower2.status_selected", { tower = towerName(selected) }))
	Kit.setChip(status.record, if def.id == "Endless"
		then Loc.t("ui.tower2.record_endless", { record = record })
		else Loc.t("ui.tower2.record", { record = record, stages = def.stages }))
	-- Naechste Freischaltung
	local nextText = Loc.t("ui.tower2.status_all_open")
	for _, other in TowerConfig.TOWERS do
		if not TowerConfig.isOpen(data.rebirthCount, other.id, if towers then towers.records else nil, if towers then (towers :: any).unlocked else nil) then
			local prev, have, need = TowerConfig.getUnlockProgress(other.id, if towers then towers.records else nil)
			if prev then
				nextText = Loc.t("ui.tower2.status_next", { tower = towerName(other.id), have = have, need = need })
			end
			break
		end
	end
	Kit.setChip(status.nextOpen, nextText)
end

-- Ordnet die Einstiegsleiste je nach Lage: mit/ohne gespeichertem Lauf,
-- mit/ohne Pass. Primaer ist immer der breiteste Knopf.
local function layoutFooter(showSkip: boolean, passOwned: boolean, footerWidth: number)
	local primary, skip, premium = _primary, _skip, _premium
	if not primary or not skip or not premium then return end
	local gap = T.space.s
	local inner = footerWidth - PAD * 2
	if passOwned and showSkip then
		-- Pass: Skip und Pass verschmelzen zu EINEM goldenen Knopf
		skip.button.Visible = false
		premium.button.Visible = true
		local w = math.floor(inner * 0.42)
		primary.button.Size = UDim2.fromOffset(inner - w - gap, 76)
		premium.button.Size = UDim2.fromOffset(w, 64)
		premium.button.Position = UDim2.new(0, PAD + inner - w, 1, -PAD - 64)
	elseif showSkip then
		skip.button.Visible = true
		premium.button.Visible = true
		local wSkip, wPrem = 160, 148
		primary.button.Size = UDim2.fromOffset(inner - wSkip - wPrem - gap * 2, 76)
		skip.button.Size = UDim2.fromOffset(wSkip, 64)
		skip.button.Position = UDim2.new(0, PAD + inner - wSkip - wPrem - gap, 1, -PAD - 64)
		premium.button.Size = UDim2.fromOffset(wPrem, 64)
		premium.button.Position = UDim2.new(0, PAD + inner - wPrem, 1, -PAD - 64)
	else
		skip.button.Visible = false
		premium.button.Visible = true
		local wPrem = 148
		primary.button.Size = UDim2.fromOffset(inner - wPrem - gap, 76)
		premium.button.Size = UDim2.fromOffset(wPrem, 64)
		premium.button.Position = UDim2.new(0, PAD + inner - wPrem, 1, -PAD - 64)
	end
	primary.button.Position = UDim2.new(0, PAD, 1, -PAD - 76)
end

local function refreshFooter(data: Types.PlayerDataUpdate)
	local primary, skip, premium, gummyChip, hint = _primary, _skip, _premium, _gummyChip, _hint
	local window = _window
	if not primary or not skip or not premium or not gummyChip or not hint or not window then return end

	Kit.setChip(gummyChip, Theme.formatNumber(data.gummies))

	local running = _petState == "ToPit" or _petState == "InPit"
	local reached = PitResumeDialog.getProgress(data)
	local showSkip = reached ~= nil and reached > 1 and not running
	local stage, price = 1, 0
	if showSkip then
		stage, price = PitResumeDialog.offer(data, "Last")
	end
	local passOwned = hasPass()
	local passReady = GamepassConfig.isReady(PASS_KEY)

	-- Primaer: Gratis-Start (die tatsaechliche freie Stage: immer 1,
	-- Entscheidung 05.10.)
	primary.label.Text = if running then Loc.t("ui.tower2.running") else Loc.t("ui.tower2.start")
	primary.sub.Text = if running then "" else Loc.t("ui.tower2.start_sub", { stage = 1 })
	primary.sub.Visible = not running
	primary.label.Size = UDim2.new(1, -20, 0, 34)
	primary.label.Position = UDim2.new(0.5, 0, 0, if running then 22 else 8)
	primary.label.AnchorPoint = Vector2.new(0.5, 0)
	primary.setEnabled(not running)
	if _freeBadge then _freeBadge.Visible = not running end

	-- Sekundaer: bezahlter Einstieg ab der letzten Stage
	skip.label.Text = Loc.t("ui.tower2.skip", { stage = stage })
	skip.sub.Text = Loc.t("ui.tower2.price", { price = Kit.formatCompact(price) })
	skip.sub.Visible = true
	skip.setEnabled(price <= data.gummies)

	-- Premium / Pass
	if passOwned and showSkip then
		premium.label.Text = Loc.t("ui.tower2.skip", { stage = stage })
		premium.sub.Text = Loc.t("ui.tower2.pass_free")
		premium.setEnabled(true)
	else
		premium.label.Text = "👑 " .. Loc.t("ui.pass.skip.name")
		premium.sub.Text = if passOwned then Loc.t("ui.tower2.pass_owned")
			elseif passReady then Loc.t("ui.tower2.pass_buy")
			else Loc.t("ui.pass.soon")
		premium.setEnabled(not passOwned)
	end
	premium.sub.Visible = true

	hint.Text = if running then Loc.t("ui.tower2.hint_running") else Loc.t("ui.tower2.hint_free")

	local size = window.root.Size
	layoutFooter(showSkip, passOwned, size.X.Offset)
end

function TowerPanel.refresh()
	if not _isOpen then return end
	local data = ClientState.get()
	if not data then return end
	refreshStatus(data)
	for _, view in _cards do
		refreshCard(view, data)
	end
	refreshFooter(data)
end

--------------------------------------------------------------------------------
-- Bewegung (eine Schleife, solange das Fenster offen ist)
--------------------------------------------------------------------------------

local function startLoop()
	if _stopLoop then return end
	local t0 = os.clock()
	_stopLoop = Kit.animate(function(now)
		local t = now - t0
		-- Glanz ueber neue Karten (sanft, alle ~2,6 s)
		local phase = (t % T.motion.glimmer) / T.motion.glimmer
		for _, view in _cards do
			if view.glimmer.Visible then
				view.glimmer.Position = UDim2.new(-0.3 + phase * 1.6, 0, 0, 0)
				view.glimmer.BackgroundTransparency = 0.55 + 0.45 * math.abs(phase - 0.5) * 2
			end
			if view.newBadge.Visible then
				view.newBadge.Rotation = -10 + math.sin(t * 4) * 4
			end
		end
		return true
	end)
end

local function stopLoop()
	if _stopLoop then _stopLoop() end
	_stopLoop = nil
	if _stopPulse then _stopPulse() end
	_stopPulse = nil
end

-- Karten laufen gestaffelt ein (von rechts, leicht vergroessert)
local function staggerCards()
	for index, id in _order do
		local view = _cards[id]
		local face = view.card.face
		face.Position = UDim2.fromOffset(4 + 40, 0)
		local delay = (index - 1) * T.motion.stagger
		task.delay(delay, function()
			if not _isOpen then
				face.Position = UDim2.fromOffset(4, 0)
				return
			end
			Kit.tween(face, T.motion.cardIn, { Position = UDim2.fromOffset(4, 0) }, Enum.EasingStyle.Back)
		end)
	end
end

local function scrollToSelected()
	local list, data = _list, ClientState.get()
	if not list or not data or not data.towers then return end
	local index = table.find(_order, data.towers.selected) or 1
	local y = math.max(0, (index - 2) * (CARD_H + T.space.s))
	list.CanvasPosition = Vector2.new(0, y)
end

--------------------------------------------------------------------------------
-- Oeffnen / Schliessen
--------------------------------------------------------------------------------

local function openInternal(...: any)
	local window = _window
	if not window then return end
	local refit = (window :: any).refit
	if refit then refit() end
	window.root.Visible = true
	_isOpen = true
	TowerPanel.refresh()
	scrollToSelected()
	Kit.popIn(window)
	staggerCards()
	startLoop()
	local primary = _primary
	if primary and not _stopPulse then
		_stopPulse = Kit.pulse(primary.face, 0.05)
	end
end

local function closeInternal()
	local window = _window
	if window then window.root.Visible = false end
	_isOpen = false
	stopLoop()
end

function TowerPanel.isOpen(): boolean
	return _isOpen
end

-- Fuer die Fuehrung (GuideController): der Waehlen-Knopf des ersten neuen Towers.
function TowerPanel.getGuideTarget(): GuiObject?
	if not _isOpen then return nil end
	for _, id in _order do
		local view = _cards[id]
		if view.state == "new" then
			return view.choose.button
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- Freischalt-Moment
--------------------------------------------------------------------------------

local function onUnlocked(towerId: string)
	local def = TowerConfig.get(towerId)
	if not def then return end
	Kit.playSound("unlock")
	Notify.emit("tower_unlocked", function()
		Toast.success(Loc.t("msg.tower_unlocked", { tower = towerName(towerId) }))
	end, function()
		Moment.show("tower_unlocked", def.color, "ui.moment.tower_unlocked")
	end)
	local view = _cards[towerId]
	local window = _window
	if _isOpen and view and window then
		TowerPanel.refresh()
		local face = view.card.face
		local rel = face.AbsolutePosition - window.body.AbsolutePosition
		-- AbsolutePosition sind Pixel; der Koerper ist mit FitScale und der
		-- globalen UiScale skaliert — fuer das Konfetti grob zurueckrechnen.
		local scale = window.body.AbsoluteSize.X / math.max(1, window.root.Size.X.Offset)
		Kit.confetti(window.content, Vector2.new(rel.X / scale + 60, rel.Y / scale + 40), 26)
	end
end

--------------------------------------------------------------------------------
-- Aufbau
--------------------------------------------------------------------------------

function TowerPanel.init(screenGui: ScreenGui)
	if not FeatureFlags.isOn("TOWER_PANEL_V2") then return end

	local window = Kit.window("TowerPanel", screenGui, {
		design = DESIGN, minHeight = MIN_HEIGHT, reserve = reserve,
	})
	_window = window
	Kit.mascot(window, 74)
	local title = Kit.header(window, Loc.t("ui.tower.title"), HEADER_H)
	Loc.bind(title, "ui.tower.title")
	Kit.closeButton(window, function()
		PanelManager.close(PANEL_NAME)
	end)

	local content = window.content

	-- Statuszeile
	local statusRow = Kit.frame("Status", content)
	statusRow.Position = UDim2.fromOffset(PAD, HEADER_H + 10)
	statusRow.Size = UDim2.new(1, -PAD * 2, 0, STATUS_H - 8)
	statusRow.ZIndex = 30
	local statusLayout = Instance.new("UIListLayout")
	statusLayout.FillDirection = Enum.FillDirection.Horizontal
	statusLayout.Padding = UDim.new(0, T.space.s)
	statusLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	statusLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statusLayout.Parent = statusRow
	local selectedChip = Kit.chip("Selected", statusRow, "", T.color.honeyTop)
	selectedChip.LayoutOrder = 1
	local recordChip = Kit.chip("Record", statusRow, "")
	recordChip.LayoutOrder = 2
	local nextChip = Kit.chip("Next", statusRow, "")
	nextChip.LayoutOrder = 3
	_status = { selected = selectedChip, record = recordChip, nextOpen = nextChip }

	-- Kartenliste
	local list = Kit.scroller("List", content)
	_list = list
	local listPad = Instance.new("UIPadding")
	listPad.PaddingTop = UDim.new(0, 14)   -- Platz fuer den NEU-Aufkleber
	listPad.PaddingRight = UDim.new(0, 10)
	listPad.Parent = list
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, T.space.s + 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	for order, def in TowerConfig.TOWERS do
		_cards[def.id] = buildCard(list, def, order)
		table.insert(_order, def.id)
	end

	-- Einstiegsleiste
	local footer = Kit.frame("Footer", content, T.color.white)
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.fromScale(0, 1)
	footer.Size = UDim2.new(1, 0, 0, FOOTER_H)
	footer.ZIndex = 31
	Kit.corner(footer, T.radius.panel)
	Kit.gradient(footer, T.color.surfaceDeep, Theme.shade(T.color.surfaceDeep, -0.06))
	_footer = footer
	local footerTop = Kit.frame("FooterTop", footer, T.color.white)
	footerTop.Size = UDim2.new(1, 0, 0, T.radius.panel)
	footerTop.ZIndex = 31
	Kit.gradient(footerTop, T.color.surfaceDeep, T.color.surfaceDeep)
	local footerLine = Kit.frame("FooterLine", footer, T.color.outline)
	footerLine.Size = UDim2.new(1, 0, 0, T.stroke.card)
	footerLine.ZIndex = 32

	-- Zeile 1: Gummy-Stand und ein ehrlicher Satz zum Gratis-Start
	local gummyChip = Kit.chip("Gummies", footer, "0", T.color.white)
	gummyChip.Position = UDim2.fromOffset(PAD, 10)
	-- Icon links in der Pille (die Polsterung macht ihm Platz)
	local gummyPad = gummyChip:FindFirstChildOfClass("UIPadding")
	if gummyPad then gummyPad.PaddingLeft = UDim.new(0, 36) end
	local gummyIcon = Icons.make(gummyChip, "gummy", "G")
	gummyIcon.Size = UDim2.fromOffset(28, 28)
	gummyIcon.AnchorPoint = Vector2.new(0, 0.5)
	gummyIcon.Position = UDim2.new(0, -32, 0.5, 0)
	gummyIcon.ZIndex = 34
	_gummyChip = gummyChip

	local hint = Kit.text("Hint", footer, "", T.text.small, { color = T.color.inkSoft, align = Enum.TextXAlignment.Right })
	hint.AnchorPoint = Vector2.new(1, 0)
	hint.Position = UDim2.new(1, -PAD, 0, 10)
	hint.Size = UDim2.new(0.6, 0, 0, 30)
	hint.ZIndex = 33
	_hint = hint

	-- Zeile 2: die drei Einstiege
	local primary = Kit.button("Start", footer, "primary", Loc.t("ui.tower2.start"), 30)
	primary.sub.Visible = true
	primary.sub.Size = UDim2.new(1, -20, 0, 20)
	primary.button.Activated:Connect(function()
		if not primary.button.Active then return end
		Kit.playSound("click")
		Remotes.RequestPetMode:FireServer("Fight", "Fresh")
		PanelManager.close(PANEL_NAME)
	end)
	_primary = primary
	local freeBadge = Kit.badge("Free", primary.button, Loc.t("ui.tower2.free"), T.color.gummy, 8)
	-- Oben rechts INNERHALB des Knopfs: links steht die Gummy-Pille, rechts
	-- daneben der naechste Knopf, in der Mitte die Beschriftung.
	freeBadge.AnchorPoint = Vector2.new(1, 0.5)
	freeBadge.Position = UDim2.new(1, -10, 0, 2)
	freeBadge.ZIndex = 44
	local freeLabel = freeBadge:FindFirstChild("Text") :: TextLabel
	freeLabel.ZIndex = 45
	_freeBadge = freeBadge

	local skip = Kit.button("Skip", footer, "secondary", "", 20)
	skip.label.Size = UDim2.new(1, -12, 0, 24)
	skip.label.AnchorPoint = Vector2.new(0.5, 0)
	skip.label.Position = UDim2.new(0.5, 0, 0, 6)
	skip.sub.Size = UDim2.new(1, -12, 0, 20)
	skip.button.Activated:Connect(function()
		if not skip.button.Active then return end
		Kit.playSound("click")
		Remotes.RequestPetMode:FireServer("Fight", "Last")
		PanelManager.close(PANEL_NAME)
	end)
	_skip = skip

	local premium = Kit.button("Pass", footer, "premium", "", 20)
	premium.label.Size = UDim2.new(1, -12, 0, 24)
	premium.label.AnchorPoint = Vector2.new(0.5, 0)
	premium.label.Position = UDim2.new(0.5, 0, 0, 6)
	premium.sub.Size = UDim2.new(1, -12, 0, 20)
	premium.button.Activated:Connect(function()
		if not premium.button.Active then return end
		Kit.playSound("click")
		if hasPass() then
			-- Mit Pass ist das der Gratis-Skip (der Server rechnet 0)
			Remotes.RequestPetMode:FireServer("Fight", "Last")
			PanelManager.close(PANEL_NAME)
		elseif GamepassConfig.isReady(PASS_KEY) then
			Remotes.RequestBuyGamepass:FireServer(PASS_KEY)
		else
			-- "Bald": kurzer Wackler statt eines Kaufs
			local face = premium.face
			Kit.tween(face, 0.06, { Rotation = 3 })
			task.delay(0.07, function() Kit.tween(face, 0.12, { Rotation = 0 }, Enum.EasingStyle.Back) end)
		end
	end)
	_premium = premium

	-- Groesse: Liste fuellt den Platz zwischen Status und Leiste; auf
	-- niedrigen Fenstern die kompakte Anordnung.
	window.setSize = function(size: Vector2)
		_compact = size.Y < COMPACT_BELOW
		local headerH = if _compact then HEADER_H_COMPACT else HEADER_H
		local statusH = if _compact then 0 else STATUS_H
		local footerH = if _compact then FOOTER_H_COMPACT else FOOTER_H
		local band = window.header
		if band then band.Size = UDim2.new(1, 0, 0, headerH) end
		statusRow.Visible = not _compact
		footer.Size = UDim2.new(1, 0, 0, footerH)
		gummyChip.Visible = not _compact
		hint.Visible = not _compact
		list.Position = UDim2.fromOffset(PAD, headerH + statusH + 4)
		list.Size = UDim2.new(1, -PAD * 2 + 10, 0, math.max(CARD_H * 0.6, size.Y - headerH - statusH - footerH - 8))
		if _isOpen then TowerPanel.refresh() end
	end

	PanelManager.register(PANEL_NAME, { open = openInternal, close = closeInternal })

	ClientState.onChanged(function() TowerPanel.refresh() end)
	Loc.onChanged(function() TowerPanel.refresh() end)
	Players.LocalPlayer:GetAttributeChangedSignal(GamepassConfig.attributeName(PASS_KEY)):Connect(function()
		TowerPanel.refresh()
	end)
	Remotes.PetModeChanged.OnClientEvent:Connect(function(state: any)
		_petState = if typeof(state) == "string" then state else "Home"
		TowerPanel.refresh()
	end)
	Remotes.TowerUnlocked.OnClientEvent:Connect(function(towerId: any)
		if typeof(towerId) == "string" then onUnlocked(towerId) end
	end)

	print("[TowerPanel] Initialisiert |", #_order, "Tower")
end

return TowerPanel
