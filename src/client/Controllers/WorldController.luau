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
--      → Arena-Ausbau-Menue (die Kampf-Auswahl liegt in der PetBar), ueber einen hier erzeugten ProximityPrompt
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

local Theme        = require(script.Parent.Parent.UI.Theme)
local BaerchiPanel = require(script.Parent.Parent.UI.BaerchiPanel)
local PanelManager = require(script.Parent.Parent.UI.PanelManager)

local WorldController = {}

local UID_ATTRIBUTE   = "BaerchiUid"
local LEVEL_ATTRIBUTE = "BuildingLevel"
local OWNER_ATTRIBUTE = "PlotOwner"
local PROMPT_DISTANCE = 14

-- Wegweiser auf den eigenen Plot. Die Plattform ist 480 Studs breit und
-- ueberall gleich gruen; ohne diese Marke sucht man beim ersten Join acht
-- Schilder ab, um das eigene zu finden. Reichweite deshalb so gross, dass sie
-- vom Spawn in der Mitte aus zu sehen ist (Plot-Ring: 165 Studs).
local HOME_MARKER_NAME     = "DeinPlot"
local HOME_MARKER_DISTANCE = 260
local HOME_MARKER_HEIGHT   = 7

-- Gebaeude-Part-Namen wie MapService sie vergibt (= Types.BuildingId)
local BUILDING_NAMES: { [string]: boolean } = {
	Beehive    = true,
	HoneyPot   = true,
	HoneyPress = true,
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

-- Ein Prompt an einer Part. `name` dient als Schutz gegen doppeltes Anhaengen:
-- die Parts werden bei jedem Plot-Neuaufbau ersetzt, und ein zweiter Prompt
-- waere ein doppeltes Fenster.
local function addPrompt(
	part: BasePart,
	name: string,
	actionText: string,
	objectText: string,
	keyCode: Enum.KeyCode,
	onTriggered: () -> ()
): ProximityPrompt?
	if part:FindFirstChild(name) then return nil end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name                  = name
	prompt.ActionText            = actionText
	prompt.ObjectText            = objectText
	prompt.KeyboardKeyCode       = keyCode
	prompt.MaxActivationDistance = PROMPT_DISTANCE
	prompt.RequiresLineOfSight   = false
	prompt.Parent                = part

	prompt.Triggered:Connect(onTriggered)
	return prompt
end

local function addPanelPrompt(part: BasePart, actionText: string, objectText: string, panelName: string)
	addPrompt(part, "OpenPanel", actionText, objectText, Enum.KeyCode.E, function()
		PanelManager.open(panelName)
	end)
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
	label.Text                   = "\u{25BC} Dein Plot"
	label.TextColor3             = Theme.COLORS.goldGummy
	label.TextStrokeTransparency = 0.2
	label.TextStrokeColor3       = Color3.fromRGB(0, 0, 0)
	label.Parent                 = marker
end

local function hookOwnedPart(instance: BasePart)
	if instance.Name == "SignBoard" then
		addHomeMarker(instance)
		return
	end

	if instance.Name == "FightFloor" then
		addPanelPrompt(instance, "Ausbauen", "Kampfplattform", PanelManager.ARENA_PANEL)
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

	local function attach()
		addPrompt(instance, "OpenPanel", "Ausbauen", buildingId, Enum.KeyCode.E, function()
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

	-- Besitzer noch unbekannt: das kann passieren wenn das Teil beim Client
	-- ankommt bevor sein Plot-Model komplett da ist. Einmal im naechsten
	-- Frame erneut versuchen, statt den Prompt fuer immer zu verlieren.
	if findPlotOwner(instance) == nil then
		task.defer(function()
			if instance.Parent and isOwnPlot(instance) then
				hookOwnedPart(instance)
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
	-- Was schon da ist
	for _, descendant in Workspace:GetDescendants() do
		hook(descendant)
	end

	-- Und alles was der Server noch nachliefert. Die Figuren werden bei jeder
	-- Bestandsaenderung neu gebaut, also passiert das staendig.
	Workspace.DescendantAdded:Connect(hook)

	print("[WorldController] Initialisiert")
end

return WorldController
