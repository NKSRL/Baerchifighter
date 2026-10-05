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
local EggTree   = require(ReplicatedStorage.Modules.EggTree)
local FeatureFlags   = require(ReplicatedStorage.Config.FeatureFlags)
local IncubatorRules = require(ReplicatedStorage.Modules.IncubatorRules)   -- Sammel-Update 8

local Theme          = require(script.Parent.Theme)
local PanelManager   = require(script.Parent.PanelManager)
local EggIcon        = require(script.Parent.EggIcon)
local HatchAnimation = require(script.Parent.HatchAnimation)
local ClientState    = require(script.Parent.Parent.Controllers.ClientState)

local HatchPanel = {}

local PANEL_NAME = "Hatch"
local EGG_HEIGHT = 84

local _root: Frame?              = nil
local _scroller: ScrollingFrame? = nil
local _signature = ""

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

local function buildEggCard(parent: Instance, order: number, eggType: Types.EggType, stock: number)
	local def = EggConfig.data[eggType]

	local card = Theme.panel("Egg_" .. eggType, parent, Theme.COLORS.panel)
	card.Size        = UDim2.new(1, -8, 0, EGG_HEIGHT)
	card.LayoutOrder = order

	-- Das Ei links in Farbe und Muster seines Pfads (EggIcon), damit man die
	-- Sorte ohne Lesen erkennt — genau so liegt es auch auf dem Plot.
	local icon = EggIcon.make(card, eggType, 62, 3)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position    = UDim2.new(0, 10, 0.5, 0)

	local name = Theme.label("Name", card, Loc.name("egg." .. eggType .. ".name", def.displayName))
	name.Position = UDim2.new(0, 68, 0, 8)
	name.Size     = UDim2.new(1, -200, 0, 22)

	-- v14: ein noch gesperrtes Ei im Lager ist ein Sprung-Ei aus einem Event.
	local data = ClientState.get()
	local locked = data ~= nil and not EggTree.isUnlocked(data.eggTree, eggType)
	local desc = Theme.bodyText("Desc", card, if locked then Loc.t("ui.tree.jump_hint") else def.description)
	desc.Position = UDim2.new(0, 68, 0, 32)
	desc.Size     = UDim2.new(1, -200, 0, 40)

	local count = Theme.label("Count", card, "x" .. stock)
	count.Position       = UDim2.new(1, -128, 0, 8)
	count.Size           = UDim2.new(0, 116, 0, 22)
	count.TextXAlignment = Enum.TextXAlignment.Right
	count.TextColor3     = Theme.COLORS.good

	-- Sammel-Update 05.10. (Paket 8): Eier ab Gold-Stufe gehen in den
	-- Inkubator statt sofort auf (gleiche Regel wie der Server).
	local toIncubator = FeatureFlags.isOn("INCUBATOR") and not FeatureFlags.isOn("INCUBATOR_BREED") and data ~= nil
		and IncubatorRules.requiresIncubator(eggType, IncubatorRules.isUnlocked(data))
	local button = Theme.bigButton("Open", card,
		if toIncubator then Loc.t("ui.hatch.to_incubator") else Loc.t("ui.hatch.open"),
		if toIncubator then Theme.COLORS.growth else Theme.COLORS.accent)
	button.Position = UDim2.new(1, -128, 0, 38)
	button.Size     = UDim2.new(0, 116, 0, 32)

	button.Activated:Connect(function()
		if toIncubator then
			Remotes.RequestIncubatorStart:FireServer(eggType)
			PanelManager.open("Incubator")
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
	local parts = { Loc.getLanguage(), tostring(IncubatorRules.isUnlocked(data)) }
	for _, eggType in EGG_ORDER do
		local n = data.island.eggStock[eggType] or 0
		if n > 0 then table.insert(parts, eggType .. n) end
	end
	local signature = table.concat(parts, "|")
	if signature == _signature then return end
	_signature = signature

	for _, child in scroller:GetChildren() do
		if child:IsA("Frame") or child:IsA("TextLabel") then
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

	if shown == 0 then
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
	if root then root.Visible = false end
end

--------------------------------------------------------------------------------
-- Aufbau
--------------------------------------------------------------------------------

function HatchPanel.init(screenGui: ScreenGui)
	HatchAnimation.init(screenGui)

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
	treeButton.Position = UDim2.new(1, -40, 0.5, 0)
	treeButton.Size = UDim2.new(0, 92, 0, 26)
	treeButton.Activated:Connect(function()
		PanelManager.open("EggTree")
	end)
	Loc.onChanged(function()
		treeButton.Text = Loc.t("ui.menu.tree")
	end)

	local body     = Theme.dialogBody(root)
	local scroller = Theme.scroller("List", body)
	scroller.Size = UDim2.fromScale(1, 1)
	_scroller = scroller

	local layout = Theme.listLayout(scroller, 6)
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Left

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

	-- Abgelehnt (z.B. Lager inzwischen leer): die Animation ohne Ergebnis
	-- beenden. Die Meldung selbst zeigt der Toast (ActionFailed).
	Remotes.ActionFailed.OnClientEvent:Connect(function(action: any, reason: any)
		if action == "RequestHatchEgg" then
			HatchAnimation.reject(tostring(reason))
		end
	end)

	print("[HatchPanel] Initialisiert")
end

return HatchPanel
