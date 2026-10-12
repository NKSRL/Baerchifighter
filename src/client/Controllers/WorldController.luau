--!strict
-- WorldController.luau
-- StarterPlayerScripts/Controllers/WorldController.luau
--
-- Einzige Zustaendigkeit:
--   - Klicks und Naeherungs-Prompts an Objekten in der Welt in UI-Aktionen
--     uebersetzen
--
-- Es gibt drei Anker in der Welt:
--   1. Baerchi-Figuren (Attribut "BaerchiUid" an Koerper und Kopf)
--      → Detailkarte, ueber einen ClickDetector den der Server schon mitbaut
--   2. Gebaeude-Parts (Name = BuildingId, Attribute "BuildingLevel"/"HoneyPool")
--      → ein hier erzeugter ProximityPrompt (E) oeffnet das Gebaeude-Panel
--   3. Die Kampf-Plattform ("FightFloor" im Model "PitPlatform")
--      → v15: Tower-Wahl (CombatPanel), ueber einen hier erzeugten ProximityPrompt
--   4. v15: FREMDE Spieler (Charakter) und fremde Plot-Schilder
--      → Profilkarte (Inspektor, ProfilePanel), per Klick
--
-- Gelegte Eier sind ABSICHTLICH kein vierter Anker mehr: sie werden nicht
-- mehr angeklickt, sondern serverseitig per Touched eingesammelt, sobald die
-- eigene Spielfigur hindurchlaeuft (siehe MapService.buildLaidEgg). Dieser
-- Controller muss sie deshalb nicht mehr kennen — es gibt am Ei keinen
-- ClickDetector mehr, an den er sich haengen koennte.
--
-- Das Fuettern selbst ist seit dem Equip-/Honig-Teich-System keine manuelle
-- Aktion mehr: der ausgeruestete Baerchi laeuft von alleine zum Teich auf dem
-- Plot, sobald er Honig braucht (siehe BaerchiAutopilotService). Den
-- frueheren "Honig fuettern (E)"-Prompt am Gebaeude gibt es deshalb nicht
-- mehr — er waere jetzt ohnehin nur noch fuer den einen sichtbaren Baerchi
-- relevant gewesen.
--
-- Die Prompts entstehen bewusst auf dem Client: der Server braucht sie nicht
-- zu kennen, weil sie nur ein lokales Fenster oeffnen.
--
-- Besitzer-Pruefung: MapService schreibt das Attribut "PlotOwner" (UserId) an
-- jedes Plot-Model. Prompts entstehen nur am EIGENEN Plot. Vorher erschienen
-- sie auch an fremden Gebaeuden — ungefaehrlich, weil RequestUpgradeBuilding
-- und RequestStartCombat kein Insel-Argument haben und der Server immer auf
-- den Daten des anfragenden Spielers arbeitet, aber irrefuehrend: man haette
-- am Nachbar-Gebaeude sein eigenes ausgebaut.
--
-- Die Zuordnung der Baerchis laeuft ueber das Attribut "BaerchiUid", das
-- MapService an die Koerper-Part schreibt. Der Client braucht dafuer kein
-- eigenes Remote: er hat die vollstaendigen Baerchi-Daten bereits ueber
-- PlayerDataUpdated.
--
-- Ausserdem markiert dieser Controller den EIGENEN Plot mit einem Wegweiser
-- ueber dem Schild. Das gehoert bewusst hierher und nicht zu MapService: der
-- Server baut fuer alle dasselbe, aber "dein Plot" ist fuer jeden ein anderer.
-- Serverseitig muesste man dafuer acht verschiedene Schilder bauen — hier ist
-- es ein einziges Element, das nur der Besitzer sieht.

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Loc          = require(ReplicatedStorage.Localization.Loc)
local Remotes      = require(ReplicatedStorage.Network.Remotes)
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)
local BuildingBehavior = require(ReplicatedStorage.Config.BuildingBehavior)

local FeedbackConfig = require(ReplicatedStorage.Config.FeedbackConfig)

local Theme        = require(script.Parent.Parent.UI.Theme)
local ClientState  = require(script.Parent.Parent.Controllers.ClientState)
local BaerchiPanel = require(script.Parent.Parent.UI.BaerchiPanel)
local PanelManager = require(script.Parent.Parent.UI.PanelManager)

local WorldController = {}

local UID_ATTRIBUTE   = "BaerchiUid"
local LEVEL_ATTRIBUTE = "BuildingLevel"
local OWNER_ATTRIBUTE = "PlotOwner"
local PROMPT_DISTANCE = 14

-- v15 Inspektor: Klick auf fremde Spieler oder fremde Plot-Schilder oeffnet
-- die Profilkarte. Der ClickDetector entsteht nur lokal und heisst "Inspect",
-- damit hookClickable ihn nicht fuer eine Baerchi-Figur haelt.
local INSPECT_NAME     = "Inspect"
local INSPECT_DISTANCE = 60

-- Wegweiser auf den eigenen Plot. Die Plattform ist 480 Studs breit und
-- ueberall gleich gruen; ohne diese Marke sucht man beim ersten Join acht
-- Schilder ab, um das eigene zu finden. Reichweite deshalb so gross, dass sie
-- vom Spawn in der Mitte aus zu sehen ist (Plot-Ring: 165 Studs).
local HOME_MARKER_NAME     = "DeinPlot"
local HOME_MARKER_DISTANCE = 260
local HOME_MARKER_HEIGHT   = 7

-- Gebaeude-Part-Namen wie MapService sie vergibt (= Types.BuildingId)
local BUILDING_NAMES: { [string]: boolean } = {
	Beehive      = true,
	HoneyRefiner = true,
	HoneyPond    = true,
}

-- Bereits verbundene ClickDetectors, damit nichts doppelt haengt
local _connected: { [ClickDetector]: boolean } = {}

--------------------------------------------------------------------------------
-- Baerchi-Figuren
--------------------------------------------------------------------------------

-- Ein ClickDetector in der Welt gehoert einer Baerchi-Figur — Eier haben seit
-- dem Umstieg auf Beruehren-zum-Einsammeln keinen ClickDetector mehr (siehe
-- Kommentar-Kopf).
local function findTarget(detector: ClickDetector): string?
	local part = detector.Parent
	if not part then return nil end

	local baerchiUid = part:GetAttribute(UID_ATTRIBUTE)
	if typeof(baerchiUid) == "string" then
		return baerchiUid
	end

	return nil
end

local function tryHook(detector: ClickDetector): boolean
	if _connected[detector] then return true end

	if findTarget(detector) == nil then return false end

	_connected[detector] = true

	detector.MouseClick:Connect(function()
		-- Beim Klick NEU nachschlagen statt den Wert von oben zu benutzen: die
		-- Part kann inzwischen eine andere uid tragen (Figuren werden bei jedem
		-- Plot-Neuaufbau ersetzt).
		local current = findTarget(detector)
		if not current then return end

		BaerchiPanel.show(current)
	end)

	detector.Destroying:Connect(function()
		_connected[detector] = nil
	end)

	return true
end

local function hookClickable(instance: Instance)
	if not instance:IsA("ClickDetector") then return end
	if instance.Name == INSPECT_NAME then return end
	if tryHook(instance) then return end

	-- Replikation ist nicht sortiert: der ClickDetector kann beim Client
	-- ankommen bevor das Attribut seiner Part da ist. Deshalb einmal im
	-- naechsten Frame erneut versuchen und sonst auf eines der beiden Attribute
	-- warten — welches kommt, weiss man vorher nicht.
	task.defer(function()
		if tryHook(instance) then return end

		local part = instance.Parent
		if not part then return end

		local connection: RBXScriptConnection? = nil
		connection = part:GetAttributeChangedSignal(UID_ATTRIBUTE):Connect(function()
			if tryHook(instance) and connection then
				connection:Disconnect()
			end
		end)
	end)
end

--------------------------------------------------------------------------------
-- Gebaeude und Kampfplattform
--------------------------------------------------------------------------------

-- Beschriftung eines Prompts: liefert (ActionText, ObjectText) in der
-- aktiven Sprache. Als Funktion statt fertiger Texte, damit ein Sprachwechsel
-- alle Prompts neu beschriften kann (siehe Loc.onChanged in init).
type PromptLabels = () -> (string, string)

-- Weak: ein ersetzter Plot nimmt seine Prompts mit, ohne dass sie hier haengen bleiben.
local _promptLabels: { [ProximityPrompt]: PromptLabels } = setmetatable({}, { __mode = "k" }) :: any

local function applyPromptLabels(prompt: ProximityPrompt, labels: PromptLabels)
	local action, object = labels()
	prompt.ActionText = action
	prompt.ObjectText = object
end

-- Ein Prompt an einer Part. `name` dient als Schutz gegen doppeltes Anhaengen:
-- die Parts werden bei jedem Plot-Neuaufbau ersetzt, und ein zweiter Prompt
-- waere ein doppeltes Fenster.
local function addPrompt(
	part: BasePart,
	name: string,
	labels: PromptLabels,
	keyCode: Enum.KeyCode,
	onTriggered: () -> ()
): ProximityPrompt?
	if part:FindFirstChild(name) then return nil end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name                  = name
	applyPromptLabels(prompt, labels)
	_promptLabels[prompt] = labels
	prompt.KeyboardKeyCode       = keyCode
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight   = false
	prompt.Parent                = part

	prompt.Triggered:Connect(onTriggered)
	return prompt
end

local function addPanelPrompt(part: BasePart, labels: PromptLabels, panelName: string)
	addPrompt(part, "OpenPanel", labels, Enum.KeyCode.E, function()
		PanelManager.open(panelName)
	end)
end

--------------------------------------------------------------------------------
-- HUD_ROW_V2: Honig-Brunnen ohne Fenster
--------------------------------------------------------------------------------
-- Wunsch Projektinhaber 05.10.: Am Brunnen ploppt nichts mehr auf. E baut
-- direkt aus, und ueber dem Brunnen steht nur ein Schild mit Level und Preis
-- des naechsten Ausbaus. Verbessern geht nur noch vor Ort (keine Kachel
-- mehr). Der Server prueft wie immer selbst (IslandService).
--
-- 08.10. (Paket G): EIN Druck auf E (Antippen am Handy) statt Halten. Gegen
-- Doppelkauf sperrt sich der Prompt danach kurz (FeedbackConfig.UPGRADE_FX.
-- PROMPT_LOCK); der Server bleibt massgeblich (Kosten, Level-Cap,
-- RateLimiter). Den Erfolgs-Effekt zeigt UI/UpgradeFX, sobald der Server den
-- Ausbau gebucht hat.

local POND_SIGN_NAME   = "PondLevelSign"
local POND_PROMPT_HOLD = 0
local POND_SIGN_HEIGHT = 9
local POND_SIGN_DISTANCE = 90

type PondView = { part: BasePart, prompt: ProximityPrompt, level: TextLabel, cost: TextLabel, lastLevel: number, locked: boolean }
local _ponds: { PondView } = {}

local function pondState(buildingId: string): (number, any?)
	local data = ClientState.get()
	local building = if data then data.island.buildings[buildingId :: any] else nil
	local level = if building then building.level else 1
	return level, BuildingBehavior.getUpgrade(buildingId :: any, level + 1)
end

local function costText(cost: any): string
	local gummies = Theme.formatNumber(cost.costGummies or 0)
	local gold = cost.costGoldGummies or 0
	return if gold > 0
		then Loc.t("ui.recycler.cost_gg", { gummies = gummies, gold = gold })
		else Loc.t("ui.recycler.cost_g", { gummies = gummies })
end

local function writePond(view: PondView)
	local buildingId = view.part.Name
	local level, cost = pondState(buildingId)
	view.level.Text = "Lv. " .. level
	local data = ClientState.get()
	if cost then
		local affordable = data ~= nil and data.gummies >= (cost.costGummies or 0)
			and data.goldGummies >= (cost.costGoldGummies or 0)
		view.cost.Text = "⬆ " .. costText(cost)
		view.cost.TextColor3 = if affordable then Theme.COLORS.good else Theme.COLORS.text
		-- Preis steht im Prompt; reicht es nicht, steht dort, wie viel fehlt
		-- (der Standard-Prompt laesst sich nicht ausgrauen). Druecken geht
		-- trotzdem: der Server lehnt mit der bekannten Meldung ab.
		view.prompt.ActionText = if affordable
			then Loc.t("ui.upgrade.prompt_buy", { cost = Theme.formatNumber(cost.costGummies or 0) })
			else Loc.t("ui.upgrade.prompt_need", { missing = Theme.formatNumber(math.max(0, (cost.costGummies or 0) - (if data then data.gummies else 0))) })
		if not view.locked then
			view.prompt.Enabled = true
		end
	else
		view.cost.Text = Loc.t("ui.recycler.maxed")
		view.cost.TextColor3 = Theme.COLORS.goldGummy
		view.prompt.Enabled = false
	end
	view.prompt.ObjectText = Loc.name("building." .. buildingId .. ".name", buildingId) .. "  Lv." .. level

	-- Kleiner Huepfer am Schild, wenn das Level steigt (statt eines Fensters)
	if level > view.lastLevel and view.lastLevel > 0 then
		local gui = view.level.Parent
		if gui and gui:IsA("BillboardGui") then
			local base = gui.Size
			gui.Size = UDim2.new(base.X.Scale * 1.25, 0, base.Y.Scale * 1.25, 0)
			task.delay(0.25, function()
				if gui.Parent then gui.Size = base end
			end)
		end
	end
	view.lastLevel = level
end

local function attachPond(part: BasePart)
	if part:FindFirstChild(POND_SIGN_NAME) then return end

	local gui = Instance.new("BillboardGui")
	gui.Name        = POND_SIGN_NAME
	gui.Size        = UDim2.fromScale(12, 4)
	gui.StudsOffset = Vector3.new(0, POND_SIGN_HEIGHT, 0)
	gui.MaxDistance = POND_SIGN_DISTANCE
	gui.AlwaysOnTop = false
	gui.Adornee     = part
	gui.Parent      = part

	local level = Instance.new("TextLabel")
	level.Name                   = "Level"
	level.Size                   = UDim2.fromScale(1, 0.58)
	level.BackgroundTransparency = 1
	level.Font                   = Theme.FONT
	level.TextScaled             = true
	level.TextColor3             = Theme.COLORS.goldGummy
	level.TextStrokeTransparency = 0.1
	level.Parent                 = gui

	local cost = Instance.new("TextLabel")
	cost.Name                   = "Cost"
	cost.Position               = UDim2.fromScale(0, 0.6)
	cost.Size                   = UDim2.fromScale(1, 0.4)
	cost.BackgroundTransparency = 1
	cost.Font                   = Theme.FONT
	cost.TextScaled             = true
	cost.TextStrokeTransparency = 0.1
	cost.Parent                 = gui

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name                  = "OpenPanel"   -- gleicher Name: kein zweiter Prompt
	prompt.KeyboardKeyCode       = Enum.KeyCode.E
	prompt.HoldDuration          = POND_PROMPT_HOLD
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight   = false
	prompt.Parent                = part
	local buildingId = part.Name
	local view: PondView = { part = part, prompt = prompt, level = level, cost = cost, lastLevel = 0, locked = false }
	prompt.Triggered:Connect(function()
		if view.locked then return end
		view.locked = true
		prompt.Enabled = false
		Remotes.RequestUpgradeBuilding:FireServer(buildingId)
		task.delay(FeedbackConfig.UPGRADE_FX.PROMPT_LOCK, function()
			view.locked = false
			if prompt.Parent then writePond(view) end
		end)
	end)

	table.insert(_ponds, view)
	part.Destroying:Connect(function()
		local index = table.find(_ponds, view)
		if index then table.remove(_ponds, index) end
	end)
	writePond(view)
end

local function refreshPonds()
	for _, view in _ponds do
		writePond(view)
	end
end

local function usesPondSign(buildingId: string): boolean
	return FeatureFlags.isOn("HUD_ROW_V2") and buildingId == "HoneyPond"
end

--------------------------------------------------------------------------------
-- Wem gehoert der Plot, in dem dieses Teil steckt?
--
-- MapService setzt das Attribut am Plot-Model, nicht an jedem Teil — also
-- nach oben laufen bis es gefunden wird. Teile ausserhalb eines Plots (die
-- Plattform selbst, Blumen) haben keinen Besitzer und liefern nil.
local function findPlotOwner(instance: Instance): number?
	local current: Instance? = instance

	while current do
		local owner = current:GetAttribute(OWNER_ATTRIBUTE)
		if typeof(owner) == "number" then
			return owner
		end
		current = current.Parent
	end

	return nil
end

local function isOwnPlot(instance: Instance): boolean
	return findPlotOwner(instance) == Players.LocalPlayer.UserId
end

-- Der Wegweiser ueber dem eigenen Plot-Schild.
--
-- Rein lokal erzeugt: er landet nie beim Server und damit auch nie bei den
-- anderen sieben Spielern, die ja alle ihren eigenen sehen sollen. Beim
-- Neuaufbau des Plots verschwindet er mit dem Schild und wird von
-- DescendantAdded wieder angelegt — deshalb die Pruefung auf ein bereits
-- vorhandenes Exemplar.
local function addHomeMarker(board: BasePart)
	if board:FindFirstChild(HOME_MARKER_NAME) then return end

	local marker = Instance.new("BillboardGui")
	marker.Name        = HOME_MARKER_NAME
	marker.Size        = UDim2.fromScale(14, 4)
	marker.StudsOffset = Vector3.new(0, HOME_MARKER_HEIGHT, 0)
	marker.MaxDistance = HOME_MARKER_DISTANCE
	-- Durch die Landschaft hindurch sichtbar: genau dafuer ist er da. Vom
	-- Spawn aus liegt zwischen Spieler und Schild sonst der halbe Plot.
	marker.AlwaysOnTop = true
	marker.Adornee     = board
	marker.Parent      = board

	local label = Instance.new("TextLabel")
	label.Name                   = "Text"
	label.Size                   = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font                   = Theme.FONT
	label.TextScaled             = true
	label.Text                   = "\u{25BC} " .. Loc.t("ui.world.your_plot")
	label.TextColor3             = Theme.COLORS.goldGummy
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
	label.Parent                 = marker
end

--------------------------------------------------------------------------------
-- Inspektor (v15)
--------------------------------------------------------------------------------

-- Haengt einen lokalen ClickDetector an `parent` (Part oder Model), der die
-- Profilkarte von `userId` oeffnet. Der Server prueft selbst, ob der Spieler
-- auf diesem Server ist (ProfileService); hier geht es nur ums Oeffnen.
local function addInspector(parent: Instance, userId: number)
	if parent:FindFirstChild(INSPECT_NAME) then return end
	if userId == Players.LocalPlayer.UserId then return end

	local detector = Instance.new("ClickDetector")
	detector.Name                  = INSPECT_NAME
	detector.MaxActivationDistance = INSPECT_DISTANCE
	detector.Parent                = parent

	detector.MouseClick:Connect(function()
		-- Am Schild beim Klick neu nachschlagen: ein Plot kann inzwischen einem
		-- anderen Spieler gehoeren.
		local target = if parent:IsA("BasePart") then (findPlotOwner(parent) or userId) else userId
		if target == Players.LocalPlayer.UserId then return end
		PanelManager.open("Profile", target)
	end)
end

local function hookCharacter(other: Player, character: Model)
	addInspector(character, other.UserId)
end

local function hookPlayer(other: Player)
	if other == Players.LocalPlayer then return end
	if other.Character then
		hookCharacter(other, other.Character)
	end
	other.CharacterAdded:Connect(function(character)
		hookCharacter(other, character)
	end)
end

local function hookOwnedPart(instance: BasePart)
	if instance.Name == "SignBoard" then
		addHomeMarker(instance)
		return
	end

	if instance.Name == "FightFloor" then
		addPanelPrompt(instance, function()
			return Loc.t("ui.tower.prompt_action"), Loc.t("ui.tower.prompt_object")
		end, PanelManager.ARENA_PANEL)
		return
	end

	if not BUILDING_NAMES[instance.Name] then return end

	-- Fuettern passiert nicht mehr hier (siehe Kommentar-Kopf) — es bleibt nur
	-- noch das Ausbauen.
	--
	-- Jedes Gebaeude hat sein EIGENES Menue (siehe BuildingPanel), und der
	-- Prompt oeffnet genau dieses — nicht mehr eine Liste, in der man das
	-- angeklickte Gebaeude erst suchen muss.
	--
	-- Dasselbe Menue haengt auch an der Kachelleiste rechts. Der Prompt hier ist
	-- also nur noch die Abkuerzung fuer den, der ohnehin davorsteht; gehen MUSS
	-- niemand mehr.
	local buildingId = instance.Name

	-- Sammel-Update 2.6: am Honig-Teich gibt es kein Schild und kein
	-- "Honig essen"-Klicken mehr (der Baerchi isst selbst). Der Prompt hier
	-- ist nur noch "Verbessern" — dazu die Gebaeude-Kachel rechts (MenuBar).

	local function attach()
		if usesPondSign(buildingId) then
			attachPond(instance)
			return
		end
		addPrompt(instance, "OpenPanel", function()
			return Loc.t("ui.building.prompt_upgrade"), Loc.name("building." .. buildingId .. ".name", buildingId)
		end, Enum.KeyCode.E, function()
			PanelManager.open(PanelManager.buildingPanelName(buildingId))
		end)
	end

	-- Das Level-Attribut setzt MapService erst NACH dem Einhaengen der Part.
	-- Beim Client kann die Part deshalb kurz ohne Attribut ankommen —
	-- dann einmal warten statt das Gebaeude zu verpassen.
	if instance:GetAttribute(LEVEL_ATTRIBUTE) ~= nil then
		attach()
		return
	end

	local connection: RBXScriptConnection? = nil
	connection = instance:GetAttributeChangedSignal(LEVEL_ATTRIBUTE):Connect(function()
		attach()
		if connection then
			connection:Disconnect()
		end
	end)
end

local function hookWorldPart(instance: Instance)
	if not instance:IsA("BasePart") then return end

	-- Nur die eigenen Gebaeude und das eigene PIT bekommen einen Prompt.
	-- Vorher erschien er an jedem fremden Plot, was schon deshalb verwirrend
	-- war weil der Server die Anfrage ohnehin immer auf die Daten des
	-- ANFRAGENDEN Spielers anwendet — man haette also am Nachbar-Gebaeude
	-- sein eigenes ausgebaut.
	if isOwnPlot(instance) then
		hookOwnedPart(instance)
		return
	end

	-- v15: fremdes Plot-Schild → Profilkarte des Besitzers
	if instance.Name == "SignBoard" then
		local owner = findPlotOwner(instance)
		if owner then
			addInspector(instance, owner)
			return
		end
	end

	-- Besitzer noch unbekannt: das kann passieren wenn das Teil beim Client
	-- ankommt bevor sein Plot-Model komplett da ist. Einmal im naechsten
	-- Frame erneut versuchen, statt den Prompt fuer immer zu verlieren.
	if findPlotOwner(instance) == nil then
		task.defer(function()
			if not instance.Parent then return end
			if isOwnPlot(instance) then
				hookOwnedPart(instance)
			elseif instance.Name == "SignBoard" then
				local owner = findPlotOwner(instance)
				if owner then addInspector(instance, owner) end
			end
		end)
	end
end

--------------------------------------------------------------------------------
-- Initialisierung
--------------------------------------------------------------------------------

local function hook(instance: Instance)
	hookClickable(instance)
	hookWorldPart(instance)
end

function WorldController.init()
	-- Sprachwechsel: alle noch lebenden Prompts neu beschriften
	Loc.onChanged(function()
		for prompt, labels in _promptLabels do
			if prompt.Parent then applyPromptLabels(prompt, labels) end
		end
	end)

	-- Was schon da ist
	for _, descendant in Workspace:GetDescendants() do
		hook(descendant)
	end

	-- Und alles was der Server noch nachliefert. Die Figuren werden bei jeder
	-- Bestandsaenderung neu gebaut, also passiert das staendig.
	Workspace.DescendantAdded:Connect(hook)

	-- v15 Inspektor: fremde Spielfiguren anklickbar machen
	for _, other in Players:GetPlayers() do
		hookPlayer(other)
	end
	Players.PlayerAdded:Connect(hookPlayer)

	-- HUD_ROW_V2: Brunnen-Schild mit Level und Preis aktuell halten
	ClientState.onChanged(refreshPonds)
	Loc.onChanged(refreshPonds)

	print("[WorldController] Initialisiert")
end

return WorldController
