--!strict
-- HatchPanel.luau
-- StarterPlayerScripts/UI/HatchPanel.luau
--
-- Einzige Zustaendigkeit:
--   - Die Eier im Lager auflisten und per "Oeffnen" sofort oeffnen lassen
--
-- Seit v12 (Ei-Baum-Konzept, Block A) gibt es keine Brut-Slots, keine
-- Brutzeit und keine Preise mehr: das Menue ist nur noch eine Liste der Eier
-- im Lager. Ein Klick auf "Oeffnen" startet sofort die Ei-Animation
-- (HatchAnimation) und schickt die Anfrage an den Server, der allein
-- entscheidet, was herauskommt.
--
-- Eier kommen aus Legen, Events und Rebirth-Meilensteinen. Kaufen kann man
-- nur das Basis-Ei, und das nur beim versteckten Haendler in der Welt —
-- bewusst ohne Hinweis hier.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types     = require(ReplicatedStorage.Network.Types)
local Remotes   = require(ReplicatedStorage.Network.Remotes)
local EggConfig = require(ReplicatedStorage.Config.EggConfig)
local Loc       = require(ReplicatedStorage.Localization.Loc)
local Names     = require(ReplicatedStorage.Localization.Names)
local EggTree   = require(ReplicatedStorage.Modules.EggTree)
local FeatureFlags   = require(ReplicatedStorage.Config.FeatureFlags)
local IncubatorRules = require(ReplicatedStorage.Modules.IncubatorRules)   -- Sammel-Update 8

local Theme          = require(script.Parent.Theme)
local Icons          = require(script.Parent.Icons)
local PanelManager   = require(script.Parent.PanelManager)
local EggIcon        = require(script.Parent.EggIcon)
local HatchAnimation = require(script.Parent.HatchAnimation)
local EggPanelSkin   = require(script.Parent.EggPanelSkin)   -- 13.10.: Honig-Look aus PNGs
local ClientState    = require(script.Parent.Parent.Controllers.ClientState)
local PetCapacity    = require(ReplicatedStorage.Modules.PetCapacity)   -- 19.10.: Pet-Limit
local Toast          = require(script.Parent.Toast)
local Notify         = require(script.Parent.Notify)

local HatchPanel = {}

local PANEL_NAME = "Hatch"
local BATCH_SIZE = 10   -- 15.10.: "Oeffnen x10"
local EGG_HEIGHT = 92

local _root: Frame?              = nil
local _scroller: ScrollingFrame? = nil
local _skin: any = nil   -- EggPanelSkin, wenn die Bilder eingetragen sind
local _signature = ""
local _savedScrollY = 0   -- Scrollposition der Ei-Liste (bleibt beim Neuaufbau und Wiederoeffnen)

--------------------------------------------------------------------------------
-- Reihenfolge der Eier
--------------------------------------------------------------------------------

-- Nach EggConfig.sortOrder: stabil (die Iteration ueber EggConfig.data waere
-- es nicht) und unabhaengig von der frueheren Brutdauer.
local function buildEggOrder(): { Types.EggType }
	local list: { Types.EggType } = {}
	for eggType in EggConfig.data do
		table.insert(list, eggType)
	end

	table.sort(list, function(a, b)
		local orderA = EggConfig.data[a].sortOrder or 999
		local orderB = EggConfig.data[b].sortOrder or 999
		if orderA ~= orderB then
			return orderA < orderB
		end
		return a < b
	end)

	return list
end

local EGG_ORDER = buildEggOrder()

--------------------------------------------------------------------------------
-- Zeilen bauen
--------------------------------------------------------------------------------

-- 13.10. (UI-Templates 2): Ei-Kachel aus UI2_egg_card.png. Gleiche Logik wie
-- buildEggCard, nur im Honig-Look; Ei-Bild per UIScale an den Slot angepasst.
local ICON_REF = 100
local function fitText(label: TextLabel, maxSize: number)
	label.TextScaled = true
	label.TextWrapped = true
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = maxSize
	c.Parent = label
end

local function buildTileCard(parent: Instance, order: number, eggType: Types.EggType, stock: number)
	local def = EggConfig.data[eggType]
	local c = EggPanelSkin.makeCard(parent, "Egg_" .. eggType, order)

	local icon = EggIcon.make(c.slot, eggType, ICON_REF, 4, { idle = true })
	icon.AnchorPoint = Vector2.new(0.5, 0.5)
	icon.Position = UDim2.fromScale(0.5, 0.5)
	local fit = Instance.new("UIScale")
	fit.Parent = icon
	local function refit()
		local h = c.slot.AbsoluteSize.Y
		if h > 0 then fit.Scale = h * 0.8 / ICON_REF end
	end
	c.slot:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	refit()

	local name = Theme.label("Name", c.info, Names.egg(eggType))
	name.Position = UDim2.fromScale(0, 0)
	name.Size = UDim2.fromScale(0.68, 0.38)
	name.TextXAlignment = Enum.TextXAlignment.Left
	name.TextColor3 = def.color:Lerp(Color3.new(1, 1, 1), 0.3)
	name.ZIndex = 4
	fitText(name, 30)
	Theme.outlineText(name, 2)

	local count = Theme.label("Count", c.info, "x" .. stock)
	count.Position = UDim2.fromScale(0.7, 0)
	count.Size = UDim2.fromScale(0.3, 0.38)
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.TextColor3 = Theme.COLORS.honey
	count.ZIndex = 4
	fitText(count, 30)
	Theme.outlineText(count, 2)

	local data = ClientState.get()
	local locked = data ~= nil and not EggTree.isUnlocked(data.eggTree, eggType)
	local desc = Theme.bodyText("Desc", c.info, if locked then Loc.t("ui.tree.jump_hint") else Names.eggDesc(eggType))
	desc.Position = UDim2.fromScale(0, 0.44)
	desc.Size = UDim2.fromScale(if stock >= 2 then 0.54 else 1, 0.5)
	desc.TextColor3 = Theme.COLORS.cream
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.TextYAlignment = Enum.TextYAlignment.Top
	desc.ZIndex = 4
	fitText(desc, 20)

	local toIncubator = FeatureFlags.isOn("INCUBATOR") and not FeatureFlags.isOn("INCUBATOR_BREED") and data ~= nil
		and IncubatorRules.requiresIncubator(eggType, IncubatorRules.isUnlocked(data))
	c.buttonLabel.Text = if toIncubator then Loc.t("ui.hatch.to_incubator") else Loc.t("ui.hatch.open")

	-- 19.10. (PET_LIMIT_V1): Platz im Lager. Voll = Knopf gedimmt, Klick erklaert nur.
	-- getFree ist math.huge, wenn das Feature aus ist.
	local free = if data then PetCapacity.getFree(data) else math.huge
	local full = free <= 0 and not toIncubator
	if full then
		-- Das Knopf-Bild liegt auf der Karte (nicht auf dem Button): grauer Schleier darueber
		c.buttonLabel.TextTransparency = 0.55
		local veil = Instance.new("Frame")
		veil.Name = "FullVeil"
		veil.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
		veil.BackgroundTransparency = 0.35
		veil.BorderSizePixel = 0
		veil.Size = UDim2.fromScale(1, 1)
		veil.ZIndex = c.buttonLabel.ZIndex + 1
		veil.Active = false
		veil.Parent = c.button
		local vc = Instance.new("UICorner")
		vc.CornerRadius = UDim.new(0.3, 0)
		vc.Parent = veil
	end

	-- 15.10.: "Oeffnen xN" (bis 10 auf einmal) im Honig-Knopf-Template
	if not toIncubator and stock >= 2 and not full then
		local n = math.min(stock, BATCH_SIZE, free)   -- nie mehr als Platz ist
		local multi = Instance.new("TextButton")
		multi.Name = "OpenMany"
		multi.Text = ""
		multi.AutoButtonColor = false
		multi.BackgroundTransparency = 1
		multi.AnchorPoint = Vector2.new(1, 1)
		multi.Position = UDim2.fromScale(1, 1)
		multi.Size = UDim2.fromScale(0.44, 0.55)
		multi.ZIndex = 5
		multi.Parent = c.info
		local ratio = Instance.new("UIAspectRatioConstraint")
		ratio.AspectRatio = 855 / 196
		ratio.AspectType = Enum.AspectType.FitWithinMaxSize
		ratio.DominantAxis = Enum.DominantAxis.Width
		ratio.Parent = multi
		local word = Icons.skinLabelButton(multi, "honey/res_bar_gold", Loc.t("ui.hatch.open_n", { n = n }))
		if word then
			word.AnchorPoint = Vector2.new(0.5, 0.5)
			word.Position = UDim2.fromScale(0.5, 0.5)
			word.Size = UDim2.fromScale(0.7, 0.5)
			word.ZIndex = 7
		else
			multi.Text = Loc.t("ui.hatch.open_n", { n = n })
			multi.Font = Enum.Font.FredokaOne
			multi.TextScaled = true
			multi.TextColor3 = Color3.new(1, 1, 1)
		end
		multi.Activated:Connect(function()
			HatchAnimation.requestBatch(eggType)
			Remotes.RequestHatchEggs:FireServer(eggType, n)
		end)
	end

	c.button.Activated:Connect(function()
		if toIncubator then
			Remotes.RequestIncubatorStart:FireServer(eggType)
			PanelManager.open("Incubator")
			return
		end
		if full then
			Notify.emit("action_failed", function() Toast.info(Loc.msg("err.pet_limit_full")) end)
			return
		end
		HatchAnimation.request(eggType)
		Remotes.RequestHatchEgg:FireServer(eggType)
	end)
end

local function buildEggCard(parent: Instance, order: number, eggType: Types.EggType, stock: number)
	if _skin and EggPanelSkin.cardReady() then
		buildTileCard(parent, order, eggType, stock)
		return
	end
	local def = EggConfig.data[eggType]

	local card = Theme.panel("Egg_" .. eggType, parent, Theme.COLORS.panel)
	card.Size        = UDim2.new(1, -8, 0, EGG_HEIGHT)
	card.LayoutOrder = order
	-- Bilderbuch-Rahmen (frames/frame_card); ohne Bild Waldgruen mit Honigrand
	Theme.ornate(card, "card", 0.4)

	-- Das Ei links auf einem kleinen Sockel, in Farbe und Muster seines Pfads
	-- (EggIcon), damit man die Sorte ohne Lesen erkennt. Es wackelt ab und
	-- zu, wie ein Ei, das gleich schluepfen will.
	local icon = EggIcon.make(card, eggType, 58, 3, { idle = true, pedestal = true })
	icon.Position = UDim2.fromOffset(16, 7)

	local name = Theme.label("Name", card, Names.egg(eggType))
	name.Position = UDim2.new(0, 76, 0, 12)
	name.Size     = UDim2.new(1, -212, 0, 22)
	name.TextColor3 = def.color:Lerp(Color3.new(1, 1, 1), 0.3)
	Theme.outlineText(name, 2)

	-- v14: ein noch gesperrtes Ei im Lager ist ein Sprung-Ei aus einem Event.
	local data = ClientState.get()
	local locked = data ~= nil and not EggTree.isUnlocked(data.eggTree, eggType)
	local desc = Theme.bodyText("Desc", card, if locked then Loc.t("ui.tree.jump_hint") else Names.eggDesc(eggType))
	desc.Position = UDim2.new(0, 76, 0, 36)
	desc.Size     = UDim2.new(1, if stock >= 2 then -336 else -212, 0, 44)
	desc.TextColor3 = Theme.COLORS.cream

	local count = Theme.label("Count", card, "x" .. stock)
	count.Position       = UDim2.new(1, -136, 0, 10)
	count.Size           = UDim2.new(0, 116, 0, 22)
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.TextColor3     = Theme.COLORS.honey
	Theme.outlineText(count, 2)

	-- Sammel-Update 05.10. (Paket 8): Eier ab Gold-Stufe gehen in den
	-- Inkubator statt sofort auf (gleiche Regel wie der Server).
	local toIncubator = FeatureFlags.isOn("INCUBATOR") and not FeatureFlags.isOn("INCUBATOR_BREED") and data ~= nil
		and IncubatorRules.requiresIncubator(eggType, IncubatorRules.isUnlocked(data))
	-- "Oeffnen" als Honigtropfen-Siegel
	local button = Theme.sealButton("Open", card,
		if toIncubator then Loc.t("ui.hatch.to_incubator") else Loc.t("ui.hatch.open"))
	button.Position = UDim2.new(1, -138, 0, 40)
	button.Size     = UDim2.new(0, 120, 0, 36)

	-- 19.10. (PET_LIMIT_V1): voll = Knopf grau
	local free = if data then PetCapacity.getFree(data) else math.huge
	local full = free <= 0 and not toIncubator
	if full then Theme.setEnabled(button, false) end

	if not toIncubator and stock >= 2 and not full then
		local n = math.min(stock, BATCH_SIZE, free)
		local many = Theme.sealButton("OpenMany", card, Loc.t("ui.hatch.open_n", { n = n }))
		many.Position = UDim2.new(1, -262, 0, 40)
		many.Size     = UDim2.new(0, 120, 0, 36)
		many.Activated:Connect(function()
			HatchAnimation.requestBatch(eggType)
			Remotes.RequestHatchEggs:FireServer(eggType, n)
		end)
	end

	button.Activated:Connect(function()
		if toIncubator then
			Remotes.RequestIncubatorStart:FireServer(eggType)
			PanelManager.open("Incubator")
			return
		end
		if full then
			Notify.emit("action_failed", function() Toast.info(Loc.msg("err.pet_limit_full")) end)
			return
		end
		-- Animation zuerst: der Klick soll sich sofort anfuehlen. Was
		-- herauskommt, kommt trotzdem ausschliesslich vom Server.
		HatchAnimation.request(eggType)
		Remotes.RequestHatchEgg:FireServer(eggType)
	end)
end

--------------------------------------------------------------------------------
-- Aktualisieren
--------------------------------------------------------------------------------

function HatchPanel.refresh()
	local scroller = _scroller
	local root     = _root
	if not scroller or not root then return end
	if not root.Visible then return end

	local data = ClientState.get()
	if not data then return end

	-- Sammel-Update 1.3-Muster: nur neu bauen, wenn sich das Lager (oder die
	-- Sprache) aendert — sonst zerstoert jeder Datenstand den Knopf unter dem
	-- Finger, und der Tipp kommt nicht an.
	local parts = { Loc.getLanguage(), tostring(IncubatorRules.isUnlocked(data)), "free" .. math.min(PetCapacity.getFree(data), 9999) }
	for _, eggType in EGG_ORDER do
		local n = data.island.eggStock[eggType] or 0
		if n > 0 then table.insert(parts, eggType .. n) end
	end
	local signature = table.concat(parts, "|")
	if signature == _signature then return end
	_signature = signature

	-- Scrollposition merken: nach dem Oeffnen eines Eis wird die Liste neu gebaut,
	-- soll aber an derselben Stelle stehen bleiben.
	_savedScrollY = scroller.CanvasPosition.Y

	for _, child in scroller:GetChildren() do
		if child:IsA("Frame") or child:IsA("TextLabel") or child:IsA("ImageLabel") then
			child:Destroy()
		end
	end

	local shown = 0
	for order, eggType in EGG_ORDER do
		local stock = data.island.eggStock[eggType] or 0
		if stock > 0 then
			buildEggCard(scroller, order, eggType, stock)
			shown += 1
		end
	end

	-- Position wiederherstellen (Canvas-Groesse steht erst nach dem Layout fest)
	local targetY = _savedScrollY
	if targetY > 0 then
		local function restore()
			if not scroller.Parent then return end
			local maxY = math.max(0, scroller.AbsoluteCanvasSize.Y - scroller.AbsoluteWindowSize.Y)
			scroller.CanvasPosition = Vector2.new(scroller.CanvasPosition.X, math.min(targetY, maxY))
		end
		restore()
		task.defer(restore)
		task.delay(0.1, restore)
	end

	if _skin then
		_skin:SetEmpty(shown == 0)
	elseif shown == 0 then
		local empty = Theme.bodyText("Empty", scroller, Loc.t("ui.hatch.empty"))
		empty.Size        = UDim2.new(1, -8, 0, 60)
		empty.LayoutOrder = 1
	end
end

--------------------------------------------------------------------------------
-- Oeffnen / Schliessen
--------------------------------------------------------------------------------

local function openInternal(...: any)
	local root = _root
	if not root then return end

	root.Visible = true
	_signature = ""
	HatchPanel.refresh()
end

local function closeInternal()
	local root = _root
	if _scroller and root and root.Visible then _savedScrollY = _scroller.CanvasPosition.Y end
	if root then root.Visible = false end
end

--------------------------------------------------------------------------------
-- Aufbau
--------------------------------------------------------------------------------

function HatchPanel.init(screenGui: ScreenGui)
	HatchAnimation.init(screenGui)

	if EggPanelSkin.isReady() then
	-- 13.10.: neuer Honig-Look (EggPanelSkin). Die Tabs links oeffnen die
	-- verwandten Menues; der Ei-Tab ist dieses Panel selbst.
	local holder = Instance.new("Frame")
	holder.Name = "HatchPanel"
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.fromScale(1, 1)
	holder.ZIndex = 10   -- wie Theme.dialog: ueber HUD (Fight/Timer)
	holder.Visible = false
	holder.Parent = screenGui
	_root = holder

	local skin = EggPanelSkin.new(holder, { layout = "list", emptyTitle = Loc.t("ui.hatch.empty") })
	EggPanelSkin.bindToArea(screenGui, holder, skin, nil)   -- 21.10.: gleicher Fensterbereich wie Bears
	skin.EmptyText.Visible = false
	_skin = skin
	_scroller = skin.Content

	local TAB_PANELS = { paws = "Inventory", star = "EggTree", crown = "Leaderboard" }
	skin.TabChanged:Connect(function(tab: string)
		local target = TAB_PANELS[tab]
		skin:SetActiveTab("eggs", true)
		if target then PanelManager.open(target) end
	end)
	skin.Closed:Connect(function()
		PanelManager.close(PANEL_NAME)
	end)
	Loc.onChanged(function()
		skin.EmptyTitle.Text = Loc.t("ui.hatch.empty")
		_signature = ""
		HatchPanel.refresh()
	end)
	else
	local root = Theme.dialog(
		"HatchPanel", screenGui,
		Vector2.new(0.52, 0.68),
		Vector2.new(320, 320),
		Vector2.new(560, 600)
	)
	_root = root

	local header = Theme.dialogHeader(root, Loc.t("ui.menu.eggs"), function()
		PanelManager.close(PANEL_NAME)
	end)

	-- v14: Knopf zum Ei-Baum (Presse, Freischaltung, Drop-Vorschau)
	local treeButton = Theme.button("TreeButton", header.Parent :: Instance, Loc.t("ui.menu.tree"), Theme.COLORS.growth)
	treeButton.AnchorPoint = Vector2.new(1, 0.5)
	-- 12.10. (Playtest): klebte direkt am X (X: 44 breit, ragt 4 hinaus,
	-- Trefferflaeche 56). Jetzt 12 Luft bis zur Trefferflaeche des X.
	treeButton.Position = UDim2.new(1, -58, 0.5, 0)
	treeButton.Size = UDim2.new(0, 92, 0, 26)
	treeButton.Activated:Connect(function()
		PanelManager.open("EggTree")
	end)
	Loc.onChanged(function()
		treeButton.Text = Loc.t("ui.menu.tree")
		header.Text = Loc.t("ui.menu.eggs")
		HatchPanel.refresh()
	end)

	local body     = Theme.dialogBody(root)
	-- Bilderbuch-Rahmen wie der Ei-Baum (Theme.ornateDialog)
	Theme.ornateDialog(root)
	local scroller = Theme.scroller("List", body)
	scroller.Size = UDim2.fromScale(1, 1)
	_scroller = scroller

	local layout = Theme.listLayout(scroller, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	end

	PanelManager.register(PANEL_NAME, {
		open  = openInternal,
		close = closeInternal,
	})

	-- Neue Serverdaten: Lagerbestand neu zeichnen. Nur wenn sichtbar.
	ClientState.onChanged(function()
		HatchPanel.refresh()
	end)

	Remotes.HatchResultReceived.OnClientEvent:Connect(function(result: any)
		if typeof(result) ~= "table" then return end
		HatchAnimation.deliver(result :: Types.HatchResult)
	end)

	Remotes.HatchBatchReceived.OnClientEvent:Connect(function(payload: any)
		HatchAnimation.deliverBatch(payload)
	end)

	-- Abgelehnt (z.B. Lager inzwischen leer): die Animation ohne Ergebnis
	-- beenden. Die Meldung selbst zeigt der Toast (ActionFailed).
	Remotes.ActionFailed.OnClientEvent:Connect(function(action: any, reason: any)
		if action == "RequestHatchEgg" then
			HatchAnimation.reject(tostring(reason))
		elseif action == "RequestHatchEggs" then
			HatchAnimation.rejectBatch(tostring(reason))
		end
	end)

	print("[HatchPanel] Initialisiert")
end

return HatchPanel
