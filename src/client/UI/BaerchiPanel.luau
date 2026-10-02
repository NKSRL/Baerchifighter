--!strict
-- BaerchiPanel.luau
-- StarterPlayerScripts/UI/BaerchiPanel.luau
--
-- Einzige Zustaendigkeit:
--   - Detailkarte eines einzelnen Baerchis anzeigen
--   - Die Aktionen die genau diesen Baerchi betreffen ausloesen: ausruesten,
--     befoerdern, zum Event schicken, in den PIT schicken, mit Honig fuettern
--     und verwerten
--
-- FUETTERN IST SEIT v7 EINE ENTSCHEIDUNG, kein einzelner Knopf mehr: die drei
-- Gebaeude liefern unterschiedlichen Honig (siehe Config/BuildingBehavior).
-- Deshalb steht hier pro Gebaeude ein eigener Knopf mit seinem eigenen
-- Bestand, in derselben Farbe wie seine Karte im Gebaeude-Panel. Welchen Honig
-- der Spieler verfuettert, entscheidet er — nicht mehr der Server.
--
-- SEIT v8 zeigt die Karte die ZWEITE Fortschrittsachse mit: fuenf Sterne
-- (Promotion), acht Charm-Slots und ein Balken je Stat-Level. Damit wuchs sie
-- ueber die Hoehe eines Handy-Bildschirms hinaus — der Inhalt liegt deshalb
-- jetzt in einem Scroller statt direkt im Rahmen. Das ist der Grund, warum
-- `body` hier eine ScrollingFrame ist und die Zeilen `1, -8` breit sind.
--
-- Wird von WorldController geoeffnet, wenn der Spieler eine Figur auf seiner
-- Insel anklickt, und aus dem Inventar heraus. Die Karte liest ihre Daten
-- ueber die uid aus ClientState — kein zusaetzlicher Server-Roundtrip noetig.
--
-- Die Karte bleibt beim Datenwechsel offen und aktualisiert sich mit (z.B.
-- waehrend eines Kampfes steigt XP), und schliesst sich automatisch wenn der
-- Baerchi verschwindet (verwertet oder fusioniert).
--
-- Die Kampf-Wiedergabe gehoert bewusst NICHT hierher: sie haengt am
-- CombatResultReceived-Listener in CombatPanel und laeuft deshalb egal von
-- wo der Kampf gestartet wurde.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types            = require(ReplicatedStorage.Network.Types)
local Remotes          = require(ReplicatedStorage.Network.Remotes)
local BaerchiConfig    = require(ReplicatedStorage.Config.BaerchiConfig)
local SkillConfig      = require(ReplicatedStorage.Config.SkillConfig)
local EconomyConfig    = require(ReplicatedStorage.Config.EconomyConfig)
local MapConfig        = require(ReplicatedStorage.Config.MapConfig)
local PromotionConfig  = require(ReplicatedStorage.Config.PromotionConfig)
local CharmConfig      = require(ReplicatedStorage.Config.CharmConfig)
local EventConfig      = require(ReplicatedStorage.Config.EventConfig)
local CombatCalculator = require(ReplicatedStorage.Modules.CombatCalculator)
local EggCalculator    = require(ReplicatedStorage.Modules.EggCalculator)
local EggConfig        = require(ReplicatedStorage.Config.EggConfig)

local Theme        = require(script.Parent.Theme)
local Toast        = require(script.Parent.Toast)
local PanelManager = require(script.Parent.PanelManager)
local ClientState  = require(script.Parent.Parent.Controllers.ClientState)

local BaerchiPanel = {}

local PANEL_NAME = "Baerchi"

local _root: Frame?      = nil
local _openUid: string?  = nil

-- Referenzen auf die Felder der Karte
local _titleLabel: TextLabel?  = nil
local _rarityLabel: TextLabel? = nil
local _levelLabel: TextLabel?  = nil
local _statsLabel: TextLabel?  = nil
local _skillLabel: TextLabel?  = nil
local _valueLabel: TextLabel?  = nil
local _xpFill: Frame?          = nil
local _xpText: TextLabel?      = nil
local _hpFill: Frame?          = nil
local _hpText: TextLabel?      = nil
local _accentBar: Frame?       = nil
local _fusionBadge: Frame?         = nil
local _mutationBadge: Frame?       = nil
local _mutationBadgeText: TextLabel? = nil
local _fightButton: TextButton? = nil
local _equipButton: TextButton? = nil

-- v8: Promotion, Stat-Level, Charms
local _stars: { Frame }            = {}
local _promoteButton: TextButton?  = nil
local _promoteHint: TextLabel?     = nil
type CharmTile = {
	tile   : Frame,
	letter : TextLabel,
}
local _charmSlots: { CharmTile }   = {}
local _charmButton: TextButton?    = nil
local _eventButton: TextButton?    = nil
local _eventHint: TextLabel?       = nil

-- v10: Eier legen
local _eggRateLabel: TextLabel?    = nil
local _eggChanceLabel: TextLabel?  = nil
local _eggCountLabel: TextLabel?   = nil
local _collectButton: TextButton?  = nil

type StatRow = {
	key  : string,
	fill : Frame,
	text : TextLabel,
}
local _statRows: { StatRow } = {}

-- Wer gerade am Event steht — kommt ausschliesslich vom Server
-- (EventPresenceChanged). Der Client raet das nicht selbst: nur der Server
-- weiss, ob die Figur tatsaechlich angekommen ist.
local _eventUid: string? = nil

-- Welches Event gerade laeuft (nil = Pause) und welches als naechstes kommt —
-- ebenfalls ausschliesslich vom Server (EventPhaseChanged). Der Client kennt
-- den Katalog selbst (EventConfig liegt in ReplicatedStorage) und schlaegt die
-- Belohnung dort nach; uebertragen werden nur die beiden ids.
local _activeEventId: string? = nil
local _nextEventId: string?   = nil

-- Ein Fuetter-Knopf pro Gebaeude, key = BuildingId. Text und Verfuegbarkeit
-- ziehen bei jedem Datenwechsel nach (siehe fill).
local _feedButtons: { [string]: TextButton } = {}

--------------------------------------------------------------------------------
-- Inhalt fuellen
--------------------------------------------------------------------------------

-- Wie viele Duplikate fuer die naechste Promotion da sind. Dieselbe Bedingung
-- wie PromotionService.getMaterials: gleicher configId, andere uid, nicht der
-- ausgeruestete Baerchi.
local function countMaterials(target: Types.Baerchi): number
	local data = ClientState.get()
	if not data then return 0 end

	local count = 0
	for uid, baerchi in data.island.baerchis do
		if uid ~= target.uid
			and baerchi.configId == target.configId
			and uid ~= data.island.equippedUid
		then
			count += 1
		end
	end
	return count
end

local function fillPromotion(baerchi: Types.Baerchi)
	local promotion = baerchi.promotionLevel or 0
	local states    = PromotionConfig.getStarStates(promotion)

	for index, star in _stars do
		star.BackgroundColor3 = PromotionConfig.STAR_COLORS[states[index]]
			or PromotionConfig.STAR_COLORS.empty
	end

	local maxed = promotion >= PromotionConfig.MAX_PROMOTION

	if _promoteHint then
		if maxed then
			_promoteHint.Text       = string.format("Promotion %d/%d — voll befoerdert",
				promotion, PromotionConfig.MAX_PROMOTION)
			_promoteHint.TextColor3 = Theme.COLORS.goldGummy
		else
			local cost = PromotionConfig.getDuplicateCost(baerchi.rarity, promotion + 1)
			local have = countMaterials(baerchi)

			_promoteHint.Text = string.format(
				"Promotion %d/%d  —  naechste Stufe: %d Duplikate (du hast %d)",
				promotion, PromotionConfig.MAX_PROMOTION, cost, have
			)
			_promoteHint.TextColor3 = if have >= cost then Theme.COLORS.good else Theme.COLORS.textDim
		end
	end

	if _promoteButton then
		local ready = false
		if not maxed then
			local cost = PromotionConfig.getDuplicateCost(baerchi.rarity, promotion + 1)
			ready = countMaterials(baerchi) >= cost
		end

		_promoteButton.Text = if maxed then "Voll befoerdert" else "Befoerdern"
		Theme.setEnabled(_promoteButton, ready)
	end
end

local function fillStatLevels(baerchi: Types.Baerchi)
	local cap    = PromotionConfig.getStatCap(baerchi.rarity)
	local levels = baerchi.statLevels

	for _, row in _statRows do
		local value = if levels then (((levels :: any)[row.key]) or 0) else 0
		local ratio = if cap > 0 then math.clamp(value / cap, 0, 1) else 0

		row.fill.Size = UDim2.fromScale(ratio, 1)

		-- EGG hebt sich farblich ab: es ist der einzige der fuenf Stats, der
		-- nichts mit dem Kampf zu tun hat, sondern mit dem Ei-Legen.
		row.fill.BackgroundColor3 = if row.key == "egg"
			then Theme.COLORS.goldGummy
			else Theme.rarityColor(baerchi.rarity)

		local label = PromotionConfig.STAT_LABELS[row.key] or string.upper(row.key)
		row.text.Text = string.format("%s  %d / %d", label, value, cap)
	end
end

local function fillCharms(baerchi: Types.Baerchi)
	local promotion = baerchi.promotionLevel or 0

	-- `or {}`: ein Datenpaket von einem aelteren Serverstand haette das Feld
	-- nicht (dieselbe Vorsichtsmassnahme wie bei currentHp weiter unten).
	local charms: { Types.Charm } = baerchi.charms or {}

	local bySlot: { [number]: Types.Charm } = {}
	for _, charm in charms do
		bySlot[charm.slot] = charm
	end

	local unlocked = 0

	for slot, entry in _charmSlots do
		local isOpen = CharmConfig.isSlotUnlocked(slot, promotion)
		local charm  = if isOpen then bySlot[slot] else nil

		if isOpen then unlocked += 1 end

		if not isOpen then
			entry.letter.Text          = "-"
			entry.letter.TextColor3    = Theme.COLORS.textDim
			entry.tile.BackgroundColor3 = Theme.COLORS.disabled
		elseif not charm then
			entry.letter.Text          = "?"
			entry.letter.TextColor3    = Theme.COLORS.text
			entry.tile.BackgroundColor3 = Theme.COLORS.panelLight
		else
			entry.letter.Text          = CharmConfig.RARITY_LETTER[charm.rarity] or "?"
			entry.letter.TextColor3    = Theme.COLORS.outline
			entry.tile.BackgroundColor3 = CharmConfig.RARITY_COLORS[charm.rarity]
				or Theme.COLORS.panelLight
		end
	end

	if _charmButton then
		_charmButton.Text = string.format("Charms (%d/%d offen)", unlocked, CharmConfig.SLOT_COUNT)
		Theme.setEnabled(_charmButton, true)
	end
end

-- Der Ei-Abschnitt: wie schnell dieser Baerchi legt und was dabei herauskommen
-- kann. Beide Zahlen kommen aus EggCalculator — dieselbe Rechnung, die der
-- Server benutzt. Eine nachgebaute Formel hier waere beim naechsten Balancing
-- sofort falsch.
local function fillEgg(baerchi: Types.Baerchi)
	local data     = ClientState.get()
	local equipped = data ~= nil and data.island.equippedUid == baerchi.uid

	if _eggRateLabel then
		local interval = EggCalculator.getLayIntervalSeconds(baerchi, false)

		if not interval then
			_eggRateLabel.Text       = "Dieser Baerchi legt keine Eier."
			_eggRateLabel.TextColor3 = Theme.COLORS.textDim
		else
			_eggRateLabel.Text = string.format(
				"Legt alle %s%s",
				Theme.formatDuration(interval),
				if equipped then "" else "  (nur der ausgeruestete legt wirklich)"
			)
			_eggRateLabel.TextColor3 = if equipped then Theme.COLORS.goldGummy else Theme.COLORS.textDim
		end
	end

	if _eggChanceLabel then
		local chances = EggCalculator.getChances(baerchi)

		if #chances == 0 then
			_eggChanceLabel.Text = ""
		else
			local parts: { string } = {}
			for _, chance in chances do
				local def = EggConfig.data[chance.eggType]
				table.insert(parts, string.format(
					"%s %d%%",
					if def then def.shortName else chance.eggType,
					math.floor(chance.percent + 0.5)
				))
			end
			_eggChanceLabel.Text = table.concat(parts, "   ")
		end
	end

	if _eggCountLabel then
		local laid = if data then #(data.island.laidEggs or {}) else 0

		_eggCountLabel.Text = string.format(
			"%d / %d Eier liegen auf deinem Plot",
			laid, EggConfig.MAX_UNCOLLECTED_EGGS
		)
		_eggCountLabel.TextColor3 = if laid >= EggConfig.MAX_UNCOLLECTED_EGGS
			then Theme.COLORS.bad
			else Theme.COLORS.textDim
	end

	if _collectButton then
		local laid = if data then #(data.island.laidEggs or {}) else 0
		_collectButton.Text = if laid > 0
			then string.format("Alle %d Eier einsammeln", laid)
			else "Keine Eier da"
		Theme.setEnabled(_collectButton, laid > 0)
	end
end

local function fillEvent(baerchi: Types.Baerchi)
	local data     = ClientState.get()
	local equipped = data ~= nil and data.island.equippedUid == baerchi.uid
	local atEvent  = _eventUid == baerchi.uid

	if _eventButton then
		_eventButton.Text = if atEvent then "Vom Event holen" else "Zum Event schicken"
		-- Nur der ausgeruestete Baerchi hat ueberhaupt eine Figur in der Welt,
		-- die irgendwohin laufen koennte — bei allen anderen waere der Knopf
		-- eine Einladung zu einer Ablehnung.
		Theme.setEnabled(_eventButton, equipped)
	end

	-- Der Hinweis nennt IMMER die konkrete Belohnung: seit es zehn Events mit
	-- unterschiedlichem Ertrag gibt (EventConfig), ist "es steigt ein Stat"
	-- keine Entscheidungsgrundlage mehr. Waehrend der Pause steht deshalb da,
	-- was als naechstes kommt — der Weg in die Mitte dauert selbst ein paar
	-- Sekunden, die Entscheidung faellt also VOR dem Start.
	if _eventHint then
		local activeId  = _activeEventId
		local nextId    = _nextEventId
		local activeDef = if activeId then EventConfig.getById(activeId) else nil
		local nextDef   = if nextId   then EventConfig.getById(nextId)   else nil

		if not equipped then
			_eventHint.Text = "Nur der ausgeruestete Baerchi kann zum Event."

		elseif activeDef then
			_eventHint.Text = string.format(
				"%s: %s\nBis zum Ende dableiben: %s",
				if atEvent then "Er ist beim laufenden Event" else "Laeuft gerade",
				activeDef.displayName,
				EventConfig.describeReward(activeDef)
			)

		elseif nextDef then
			_eventHint.Text = string.format(
				"%s Naechstes Event: %s\n%s",
				if atEvent then "Er wartet schon am Pit." else "Gerade Pause.",
				nextDef.displayName,
				EventConfig.describeReward(nextDef)
			)

		else
			_eventHint.Text = "Am Event teilnehmen — dafuer isst er dort keinen Honig."
		end
	end
end

local function fill(baerchi: Types.Baerchi)
	local def = BaerchiConfig.getById(baerchi.configId)
	local color = Theme.rarityColor(baerchi.rarity)

	if _accentBar   then _accentBar.BackgroundColor3 = color end
	if _titleLabel  then _titleLabel.Text  = def and def.displayName or baerchi.configId end
	if _rarityLabel then
		_rarityLabel.Text       = string.upper(baerchi.rarity)
		_rarityLabel.TextColor3 = color
	end
	if _levelLabel then
		_levelLabel.Text = string.format("Level %d / %d", baerchi.level, BaerchiConfig.MAX_LEVEL)
	end

	-- Nur der ausgeruestete Baerchi steht auf dem Plot, kaempft und isst von
	-- alleine am Teich — der Knopf zeigt, ob das dieser hier ist, und ruestet
	-- ihn sonst aus.
	if _equipButton then
		local data     = ClientState.get()
		local equipped = data ~= nil and data.island.equippedUid == baerchi.uid

		_equipButton.Text = if equipped then "Ausgeruestet" else "Ausruesten"
		Theme.setEnabled(_equipButton, not equipped)
	end

	-- Kampfwerte inklusive Fusions-Bonus, damit die Karte zeigt was im PIT zaehlt.
	-- Bewusst ueber CombatCalculator.getEffectiveStats: das ist dieselbe Funktion
	-- die der Server fuer den Kampf benutzt — eine nachgebaute Formel hier waere
	-- beim naechsten Balancing sofort falsch. Seit v8 stecken darin auch
	-- Promotion, Stat-Level und Charms.
	local stats = if def then CombatCalculator.getEffectiveStats(baerchi, def.baseStats) else nil

	if _statsLabel and stats then
		-- Eine Verteidigung gibt es nicht mehr (siehe BaerchiConfig): die drei
		-- Zahlen, die einen Kampf entscheiden, sind Schaden pro Treffer,
		-- Angriffstempo und Ability-Staerke.
		_statsLabel.Text = string.format("ATK %d    SPD %.2f    PWR %d%%",
			stats.atk, stats.spd, math.floor(stats.pwr * 100 + 0.5))
	end

	-- HP-Balken. Die HP bleiben zwischen PIT-Laeufen stehen: ein leerer Balken
	-- heisst erschoepft, und dann geht kein neuer Lauf mehr los bevor
	-- gefuettert wurde. Das ist die wichtigste Zahl auf dieser Karte.
	if _hpFill and _hpText and stats then
		-- `or stats.maxHp`: currentHp gibt es erst seit v4. Ein Datenpaket von
		-- einem aelteren Serverstand haette das Feld nicht, und math.clamp
		-- wuerde an nil scheitern statt den Baerchi einfach voll anzuzeigen.
		local hp    = math.clamp(baerchi.currentHp or stats.maxHp, 0, stats.maxHp)
		local ratio = if stats.maxHp > 0 then hp / stats.maxHp else 0

		_hpFill.Size = UDim2.fromScale(ratio, 1)
		_hpFill.BackgroundColor3 = if ratio <= 0
			then Theme.COLORS.bad
			elseif ratio < 0.34 then Theme.COLORS.goldGummy
			else Theme.COLORS.good

		_hpText.Text = if hp <= 0
			then string.format("erschoepft  —  0 / %d HP", stats.maxHp)
			else string.format("%d / %d HP", hp, stats.maxHp)
	end

	-- Mit 0 HP lehnt der Server den Lauf ohnehin ab. Das schon am Knopf zu
	-- zeigen erspart den Klick ins Leere und beantwortet die Frage "warum
	-- passiert nichts?" bevor sie entsteht.
	if _fightButton and stats then
		local ready = math.clamp(baerchi.currentHp or stats.maxHp, 0, stats.maxHp) > 0

		_fightButton.Text = if ready then "In den PIT" else "Zu erschoepft"
		Theme.setEnabled(_fightButton, ready)
	end

	if _skillLabel then
		local skill = SkillConfig.getById(baerchi.skillId)
		_skillLabel.Text = skill and (skill.displayName .. " — " .. skill.description)
			or baerchi.skillId
	end

	-- XP-Balken
	local needed = BaerchiConfig.xpForNextLevel(baerchi.level)
	local ratio  = if baerchi.level >= BaerchiConfig.MAX_LEVEL
		then 1
		else math.clamp(baerchi.xp / math.max(needed, 1), 0, 1)

	if _xpFill then
		_xpFill.Size            = UDim2.fromScale(ratio, 1)
		_xpFill.BackgroundColor3 = color
	end
	if _xpText then
		_xpText.Text = if baerchi.level >= BaerchiConfig.MAX_LEVEL
			then "MAX"
			else string.format("%d / %d XP", baerchi.xp, needed)
	end

	-- Verwertungs-Wert, damit man vor dem Verwerten weiss was es bringt.
	-- Feste Quote seit v4 (kein Recycler-Gebaeude mehr).
	if _valueLabel then
		local value = math.floor(
			EconomyConfig.getBaerchiBaseValue(baerchi.rarity, baerchi.level)
			* EconomyConfig.RECYCLE_RETURN
		)
		_valueLabel.Text = "Verwerten bringt: " .. Theme.formatNumber(value) .. " Gummies"
	end

	if _fusionBadge then
		_fusionBadge.Visible = baerchi.isFusionResult
	end

	if _mutationBadge then
		local mutation = baerchi.mutation
		_mutationBadge.Visible = mutation ~= nil
		if mutation then
			_mutationBadge.BackgroundColor3 = BaerchiConfig.getMutationColor(mutation)
			if _mutationBadgeText then
				_mutationBadgeText.Text = BaerchiConfig.getMutationDisplayName(mutation):upper()
			end
		end
	end

	fillPromotion(baerchi)
	fillStatLevels(baerchi)
	fillCharms(baerchi)
	fillEgg(baerchi)
	fillEvent(baerchi)

	-- Fuetter-Knoepfe: jeder zeigt seinen EIGENEN Bestand und ist nur
	-- anklickbar, wenn dort auch etwas liegt. Leere Lager auszugrauen erspart
	-- den Klick ins Leere — abgelehnt wuerde er ohnehin, aber erst nach dem
	-- Weg zum Server.
	local data = ClientState.get()

	for id, button in _feedButtons do
		local honey = 0
		if data then
			local building = data.island.buildings[id :: Types.BuildingId]
			honey = if building then (building.honey or 0) else 0
		end

		local config = MapConfig.BUILDING_OFFSETS[id]
		button.Text = string.format("%s %d", if config then config.shortName else id, honey)
		Theme.setEnabled(button, honey > 0)
	end
end

--------------------------------------------------------------------------------
-- Oeffnen / Schliessen
--------------------------------------------------------------------------------

local function closeInternal()
	_openUid = nil
	local root = _root
	if root then root.Visible = false end
end

local function showInternal(...: any)
	local argument = ...
	if typeof(argument) ~= "string" then return end

	local uid = argument :: string
	local baerchi = ClientState.getBaerchi(uid)
	if not baerchi then
		-- unbekannte uid (fremde Insel oder veralteter Klick)
		PanelManager.close(PANEL_NAME)
		return
	end

	_openUid = uid
	fill(baerchi)

	local root = _root
	if root then root.Visible = true end
end

function BaerchiPanel.close()
	PanelManager.close(PANEL_NAME)
end

function BaerchiPanel.show(uid: string)
	-- Gehoert der Baerchi gar nicht diesem Spieler (Klick auf die Figur eines
	-- Nachbarn auf der gemeinsamen Plattform), passiert einfach nichts.
	--
	-- Frueher lief der Aufruf trotzdem durch: PanelManager.open schliesst
	-- zuerst alle anderen Panels und showInternal machte danach mangels
	-- Daten wieder zu — dem Spieler verschwand also sein gerade offenes
	-- Fenster, sobald er einen fremden Baerchi anklickte.
	if not ClientState.getBaerchi(uid) then
		return
	end

	PanelManager.open(PANEL_NAME, uid)
end

--------------------------------------------------------------------------------
-- Aufbau
--------------------------------------------------------------------------------

function BaerchiPanel.init(screenGui: ScreenGui)
	local root = Theme.panel("BaerchiPanel", screenGui, Theme.COLORS.panelDeep)
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position    = UDim2.fromScale(0.5, 0.5)
	root.Size        = UDim2.fromScale(0.46, 0.72)
	root.Visible     = false
	root.ZIndex      = 10

	-- Seit v8 passt der Inhalt nicht mehr garantiert in den Rahmen (Sterne,
	-- fuenf Stat-Balken, acht Charm-Slots kamen dazu). Statt die Karte immer
	-- weiter wachsen zu lassen, scrollt sie: die Mindesthoehe muss deshalb nur
	-- noch fuer eine bequem lesbare Flaeche reichen, nicht mehr fuer JEDE
	-- Zeile gleichzeitig.
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(300, 420)
	sizeConstraint.MaxSize = Vector2.new(500, 720)
	sizeConstraint.Parent  = root

	-- Farbiger Rarity-Streifen am oberen Rand
	local accent = Instance.new("Frame")
	accent.Name             = "Accent"
	accent.Size             = UDim2.new(1, 0, 0, 10)
	accent.BackgroundColor3  = Theme.COLORS.accent
	accent.BorderSizePixel   = 0
	accent.Parent            = root
	Theme.corner(accent, 10)
	_accentBar = accent

	local shell = Theme.container("Body", root)
	shell.Position = UDim2.new(0, 0, 0, 16)
	shell.Size     = UDim2.new(1, 0, 1, -16)
	Theme.padding(shell, 14)

	local body = Theme.scroller("Content", shell)
	body.Size = UDim2.fromScale(1, 1)

	local layout = Theme.listLayout(body, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left

	local nextOrder = 0
	local function row(height: number): Frame
		nextOrder += 1
		local entry = Theme.container("Row", body)
		-- -8: Platz fuer den Scrollbalken, sonst ragt jede Zeile darunter
		-- (Konvention aus Theme.scroller).
		entry.Size        = UDim2.new(1, -8, 0, height)
		entry.LayoutOrder = nextOrder
		return entry
	end

	local function section(text: string)
		local holder = row(16)
		local label  = Theme.sectionLabel("Section", holder, text)
		label.Size = UDim2.fromScale(1, 1)
	end

	-- Name
	local titleRow = row(34)
	_titleLabel = Theme.label("Title", titleRow, "—")
	_titleLabel.Size = UDim2.fromScale(1, 1)

	-- Rarity + Fusions-Badge nebeneinander
	local rarityRow = row(22)
	_rarityLabel = Theme.label("Rarity", rarityRow, "—")
	_rarityLabel.Size       = UDim2.new(0.6, 0, 1, 0)
	_rarityLabel.Font       = Theme.FONT
	_rarityLabel.TextColor3 = Theme.COLORS.accent

	local badge = Theme.panel("FusionBadge", rarityRow, Theme.COLORS.gummy)
	badge.AnchorPoint = Vector2.new(1, 0.5)
	badge.Position    = UDim2.new(1, 0, 0.5, 0)
	badge.Size        = UDim2.new(0, 76, 0, 20)
	badge.Visible     = false
	local badgeText = Theme.label("Text", badge, "FUSION")
	badgeText.Size           = UDim2.fromScale(1, 1)
	badgeText.TextXAlignment = Enum.TextXAlignment.Center
	badgeText.TextColor3     = Theme.COLORS.outline
	_fusionBadge = badge

	-- Mutations-Badge (seit v11, ersetzt das binaere INVERTED-Badge). Sitzt
	-- LINKS neben dem Fusions-Badge statt an derselben Stelle: ein Baerchi
	-- kann beides gleichzeitig sein (die hoehere Mutations-Stufe zweier
	-- Inputs vererbt sich an das Fusions-Ergebnis, siehe FusionService
	-- Regel E). Etwas breiter als frueher, weil "CELESTIAL"/"BLOODROT" laenger
	-- sind als "INVERTED".
	local mutBadge = Theme.panel("MutationBadge", rarityRow, Theme.COLORS.accent)
	mutBadge.AnchorPoint = Vector2.new(1, 0.5)
	mutBadge.Position    = UDim2.new(1, -86, 0.5, 0)
	mutBadge.Size        = UDim2.new(0, 96, 0, 20)
	mutBadge.Visible     = false
	local mutText = Theme.label("Text", mutBadge, "MUTATION")
	mutText.Size           = UDim2.fromScale(1, 1)
	mutText.TextXAlignment = Enum.TextXAlignment.Center
	mutText.TextColor3     = Theme.COLORS.outline
	_mutationBadge     = mutBadge
	_mutationBadgeText = mutText

	-- Level
	local levelRow = row(22)
	_levelLabel = Theme.label("Level", levelRow, "—")
	_levelLabel.Size = UDim2.fromScale(1, 1)

	-- Ausruesten: nur der ausgeruestete Baerchi steht auf dem Plot. Steht
	-- gleich unter dem Level, weil es die erste Entscheidung ist, die man bei
	-- einem neuen Baerchi trifft.
	local equipRow = row(28)
	local equip = Theme.button("Equip", equipRow, "Ausruesten", Theme.COLORS.accent)
	equip.Size = UDim2.new(1, 0, 1, 0)
	_equipButton = equip
	equip.Activated:Connect(function()
		local uid = _openUid
		if not uid then return end
		Remotes.RequestEquipBaerchi:FireServer(uid)
	end)

	-- ---------------------------------------------------------------- Promotion
	section("Promotion")

	-- Fuenf Sterne. Zehn Stufen werden darauf abgebildet, indem die Sterne ein
	-- zweites Mal umgefaerbt werden (siehe PromotionConfig.getStarStates) —
	-- diese Umrechnung passiert dort, nicht hier.
	local starRow = row(26)
	local starLayout = Theme.listLayout(starRow, 6, true)
	starLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left

	for index = 1, PromotionConfig.STAR_COUNT do
		local star = Theme.panel("Star_" .. index, starRow, PromotionConfig.STAR_COLORS.empty)
		star.Size        = UDim2.new(0, 26, 0, 26)
		star.LayoutOrder = index
		Theme.corner(star, 13)
		table.insert(_stars, star)
	end

	local promoteHintRow = row(30)
	_promoteHint = Theme.bodyText("PromoteHint", promoteHintRow, "")
	_promoteHint.Size = UDim2.fromScale(1, 1)

	local promoteRow = row(32)
	local promote = Theme.button("Promote", promoteRow, "Befoerdern", Theme.COLORS.goldGummy)
	promote.Size = UDim2.new(1, 0, 1, 0)
	_promoteButton = promote
	promote.Activated:Connect(function()
		local uid = _openUid
		if not uid then return end
		Remotes.RequestPromoteBaerchi:FireServer(uid)
	end)

	-- ------------------------------------------------------------ Battle Charms
	section("Battle Charms")

	local charmRow = row(30)
	local charmLayout = Theme.listLayout(charmRow, 4, true)
	charmLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left

	for slot = 1, CharmConfig.SLOT_COUNT do
		local tile = Theme.panel("Charm_" .. slot, charmRow, Theme.COLORS.disabled)
		tile.Size        = UDim2.new(0, 28, 0, 28)
		tile.LayoutOrder = slot
		Theme.corner(tile, 8)

		local letter = Theme.label("Letter", tile, "-")
		letter.Size           = UDim2.fromScale(1, 1)
		letter.TextXAlignment = Enum.TextXAlignment.Center
		letter.TextScaled     = false
		letter.TextSize       = 14

		table.insert(_charmSlots, { tile = tile, letter = letter })
	end

	local charmButtonRow = row(30)
	local charms = Theme.button("Charms", charmButtonRow, "Charms", Theme.COLORS.growth)
	charms.Size = UDim2.new(1, 0, 1, 0)
	_charmButton = charms
	charms.Activated:Connect(function()
		local uid = _openUid
		if not uid then return end
		PanelManager.open("Charms", uid)
	end)

	-- ------------------------------------------------------------------- Werte
	section("Zustand")

	-- HP-Balken (steht bewusst ueber dem XP-Balken: ob der Baerchi kaempfen
	-- kann, ist die haeufigere Frage als wie weit er zum naechsten Level ist)
	local hpRow = row(22)
	local hp = Theme.progress(hpRow)
	hp.track.Size = UDim2.new(1, 0, 1, 0)
	_hpFill = hp.fill
	_hpText = hp.text

	-- XP-Balken
	local xpRow = row(22)
	local xp = Theme.progress(xpRow)
	xp.track.Size = UDim2.new(1, 0, 1, 0)
	_xpFill = xp.fill
	_xpText = xp.text

	-- Kampfwerte
	local statsRow = row(22)
	_statsLabel = Theme.label("Stats", statsRow, "—")
	_statsLabel.Size      = UDim2.fromScale(1, 1)
	_statsLabel.TextColor3 = Theme.COLORS.textDim

	-- ------------------------------------------------------------- Stat-Level
	section("Stat-Stufen (Event-Teilnahme)")

	for _, key in PromotionConfig.ALL_STATS do
		local statRow = row(20)
		local bar     = Theme.progress(statRow)
		bar.track.Size = UDim2.new(1, 0, 1, 0)
		bar.text.TextScaled = false
		bar.text.TextSize   = 13

		table.insert(_statRows, { key = key, fill = bar.fill, text = bar.text })
	end

	-- Skill
	section("Skill")
	local skillRow = row(40)
	_skillLabel = Theme.bodyText("Skill", skillRow, "—")
	_skillLabel.Size = UDim2.fromScale(1, 1)

	-- -------------------------------------------------------------------- Eier
	section("Eier legen")

	local eggRateRow = row(20)
	_eggRateLabel = Theme.label("EggRate", eggRateRow, "")
	_eggRateLabel.Size       = UDim2.fromScale(1, 1)
	_eggRateLabel.TextScaled = false
	_eggRateLabel.TextSize   = 14

	local eggChanceRow = row(20)
	_eggChanceLabel = Theme.label("EggChances", eggChanceRow, "")
	_eggChanceLabel.Size       = UDim2.fromScale(1, 1)
	_eggChanceLabel.TextScaled = false
	_eggChanceLabel.TextSize   = 13
	_eggChanceLabel.TextColor3 = Theme.COLORS.textDim

	local eggCountRow = row(18)
	_eggCountLabel = Theme.label("EggCount", eggCountRow, "")
	_eggCountLabel.Size       = UDim2.fromScale(1, 1)
	_eggCountLabel.TextScaled = false
	_eggCountLabel.TextSize   = 13

	local collectRow = row(30)
	local collect = Theme.button("CollectEggs", collectRow, "Alle Eier einsammeln", Theme.COLORS.goldGummy)
	collect.Size = UDim2.new(1, 0, 1, 0)
	_collectButton = collect
	collect.Activated:Connect(function()
		-- Ohne uid: der Server nimmt alles, was gerade herumliegt. Einzelne
		-- Eier sammelt man durch Anklicken in der Welt ein (WorldController).
		Remotes.RequestCollectAllEggs:FireServer()
	end)

	-- ------------------------------------------------------------------ Event
	section("Event")

	-- Zwei Zeilen hoch: der Hinweis nennt jetzt Event UND Belohnung (siehe
	-- fillEvent), das passt nicht mehr in eine Zeile.
	local eventHintRow = row(42)
	_eventHint = Theme.bodyText("EventHint", eventHintRow, "")
	_eventHint.Size = UDim2.fromScale(1, 1)

	local eventRow = row(32)
	local event = Theme.button("Event", eventRow, "Zum Event schicken", Theme.COLORS.accent)
	event.Size = UDim2.new(1, 0, 1, 0)
	_eventButton = event
	event.Activated:Connect(function()
		local uid = _openUid
		if not uid then return end

		-- Zwei Remotes statt eines Umschalters: der Server soll nie raten
		-- muessen, was gemeint war. Welcher der beiden dran ist, entscheidet
		-- der zuletzt vom Server gemeldete Zustand.
		if _eventUid == uid then
			Remotes.RequestRecallFromEvent:FireServer()
		else
			Remotes.RequestSendToEvent:FireServer()
		end
	end)

	-- ----------------------------------------------------------------- Aktionen
	section("Aktionen")

	-- Verwertungs-Wert
	local valueRow = row(20)
	_valueLabel = Theme.label("Value", valueRow, "—")
	_valueLabel.Size       = UDim2.fromScale(1, 1)
	_valueLabel.TextColor3 = Theme.COLORS.textDim

	-- Die beiden Aktionen des Kern-Loops: kaempfen bis erschoepft,
	-- dann mit Honig wieder hochfuettern.
	local actionRow = row(36)

	local fight = Theme.button("Fight", actionRow, "In den PIT", Theme.COLORS.bad)
	fight.Size = UDim2.new(1, 0, 1, 0)
	_fightButton = fight
	fight.Activated:Connect(function()
		local uid = _openUid
		if not uid then return end
		Remotes.RequestStartCombat:FireServer(uid)
	end)

	-- Ein Fuetter-Knopf pro Gebaeude statt eines einzigen: die drei liefern
	-- unterschiedlichen Honig, und welchen man verfuettert, ist seit v7 eine
	-- echte Entscheidung. Reihenfolge und Namen kommen aus MapConfig, die
	-- Farben aus Theme — dieselben wie auf den Karten im Gebaeude-Panel, damit
	-- man Knopf und Gebaeude sofort zusammenbringt.
	local feedHint = row(18)
	local hint = Theme.label("FeedHint", feedHint, "Fuettern — Honig aus dem Topf heilt am meisten")
	hint.Size       = UDim2.fromScale(1, 1)
	hint.TextColor3 = Theme.COLORS.textDim

	local feedRow = row(38)
	Theme.listLayout(feedRow, 6, true)

	for _, id in MapConfig.BUILDING_ORDER do
		-- Text und Verfuegbarkeit setzt fill() — hier steht nur ein Platzhalter,
		-- damit der Knopf nicht ohne Beschriftung aufblitzt.
		local button = Theme.button("Feed_" .. id, feedRow, "—", Theme.buildingColor(id))
		button.Size = UDim2.new(1 / 3, -6, 1, 0)

		button.Activated:Connect(function()
			local uid = _openUid
			if not uid then return end
			Remotes.RequestFeedHoney:FireServer(uid, id)
		end)

		_feedButtons[id] = button
	end

	-- Verwerten und Schliessen: beides beendet die Karte
	local exitRow = row(36)

	local recycle = Theme.button("Recycle", exitRow, "Verwerten", Theme.COLORS.panelLight)
	recycle.Size       = UDim2.new(1, 0, 1, 0)
	recycle.TextColor3 = Theme.COLORS.text
	recycle.Activated:Connect(function()
		local uid = _openUid
		if not uid then return end

		Remotes.RequestRecycleBaerchi:FireServer(uid)

		-- Sofort zumachen: bei Erfolg waere die Karte gleich leer, bei
		-- Ablehnung sagt es der Toast. Die Erfolgsmeldung kommt aus
		-- ResultFeed (RecycleResultReceived).
		BaerchiPanel.close()
	end)

	-- Schliessen
	local closeRow = row(34)
	local close = Theme.button("Close", closeRow, "Schliessen", Theme.COLORS.panelLight)
	close.Size       = UDim2.new(1, 0, 1, 0)
	close.TextColor3 = Theme.COLORS.text
	close.Activated:Connect(BaerchiPanel.close)

	_root = root

	PanelManager.register(PANEL_NAME, {
		open  = showInternal,
		close = closeInternal,
	})

	-- Offene Karte mitziehen: XP steigt im Kampf, und ein verwerteter oder
	-- fusionierter Baerchi existiert nicht mehr — dann zumachen.
	ClientState.onChanged(function()
		local uid = _openUid
		if not uid then return end

		local baerchi = ClientState.getBaerchi(uid)
		if baerchi then
			fill(baerchi)
		else
			BaerchiPanel.close()
		end
	end)

	-- Wer am Event steht, weiss nur der Server (die Figur muss dort erst
	-- angekommen sein). Der Client merkt sich ausschliesslich die letzte
	-- Meldung und rechnet nichts selbst dazu.
	Remotes.EventPresenceChanged.OnClientEvent:Connect(function(atEvent: any, uid: any)
		_eventUid = if atEvent == true and typeof(uid) == "string" then uid else nil

		local open = _openUid
		if not open then return end

		local baerchi = ClientState.getBaerchi(open)
		if baerchi then
			fill(baerchi)
		end
	end)

	-- Welches Event laeuft und welches als naechstes kommt. Kommt beim Join
	-- einmal gezielt und danach bei jedem Phasenwechsel (EventService) — die
	-- Restzeit wird bewusst NICHT mitgezaehlt: die steht auf der Tafel in der
	-- Weltmitte, hier geht es nur darum, WAS es zu holen gibt.
	Remotes.EventPhaseChanged.OnClientEvent:Connect(function(eventId: any, _remaining: any, nextEventId: any)
		_activeEventId = if typeof(eventId)     == "string" then eventId     else nil
		_nextEventId   = if typeof(nextEventId) == "string" then nextEventId else nil

		local open = _openUid
		if not open then return end

		local baerchi = ClientState.getBaerchi(open)
		if baerchi then
			fill(baerchi)
		end
	end)

	Remotes.PromotionResultReceived.OnClientEvent:Connect(function(result: any)
		if typeof(result) ~= "table" then return end
		local typed = result :: Types.PromotionResult

		if #typed.unlockedSlots > 0 then
			local numerals: { string } = {}
			for _, slot in typed.unlockedSlots do
				table.insert(numerals, CharmConfig.SLOT_NUMERALS[slot] or tostring(slot))
			end

			Toast.success(string.format(
				"Promotion %d/%d  —  Charm-Slot %s frei",
				typed.newPromotion, PromotionConfig.MAX_PROMOTION,
				table.concat(numerals, ", ")
			))
		else
			Toast.success(string.format(
				"Promotion %d/%d", typed.newPromotion, PromotionConfig.MAX_PROMOTION
			))
		end
	end)

	Remotes.EggCollectedReceived.OnClientEvent:Connect(function(result: any)
		if typeof(result) ~= "table" then return end
		local typed = result :: Types.EggCollectResult
		local def   = EggConfig.data[typed.eggType]

		-- Leere eggUid heisst "alles auf einmal" (siehe EggLayService.collectAll):
		-- dann steht in inStock die ANZAHL der eingesammelten Eier, nicht der
		-- Lagerbestand einer Sorte.
		if typed.eggUid == "" then
			Toast.success(string.format("%d Eier eingesammelt", typed.inStock))
		else
			Toast.success(string.format(
				"%s eingesammelt  (%d im Lager)",
				if def then def.displayName else typed.eggType,
				typed.inStock
			))
		end
	end)

	Remotes.OfflineEggReportReceived.OnClientEvent:Connect(function(report: any)
		if typeof(report) ~= "table" then return end
		local typed = report :: Types.OfflineEggReport

		Toast.success(string.format(
			"%d Eier waehrend deiner Abwesenheit gelegt%s",
			typed.laid,
			if typed.skipped then " (Platz war voll)" else ""
		))
	end)

	Remotes.EventStatGained.OnClientEvent:Connect(function(gain: any)
		if typeof(gain) ~= "table" then return end
		local typed = gain :: Types.EventStatGain

		-- Die Meldung wird aus bis zu zwei Teilen zusammengesetzt: Stat-Stufe
		-- und Bonus. Beide koennen einzeln fehlen — `statKey` ist nil, wenn
		-- schon jeder Stat am Rarity-Cap steht (dann gab es nur den Bonus),
		-- `bonusText` fehlt bei den reinen Trainings-Events. Deshalb hier
		-- zusammensetzen statt eines festen Satzes.
		local eventDef  = EventConfig.getById(typed.eventId)
		local eventName = if eventDef then eventDef.displayName else typed.eventId

		local parts: { string } = {}

		local statKey = typed.statKey
		if statKey then
			table.insert(parts, string.format(
				"%s Stufe %d / %d",
				PromotionConfig.STAT_LABELS[statKey] or statKey,
				typed.newLevel, typed.cap
			))
		end

		if typed.bonusText then
			table.insert(parts, typed.bonusText)
		end

		if #parts == 0 then
			table.insert(parts, "alle Stats stehen schon am Maximum")
		end

		Toast.success(string.format(
			"%s vorbei: %s",
			eventName,
			table.concat(parts, "  •  ")
		))
	end)

	print("[BaerchiPanel] Initialisiert")
end

return BaerchiPanel
