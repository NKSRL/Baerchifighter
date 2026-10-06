--!strict
-- EggTimerController.luau
-- StarterPlayerScripts/Controllers/EggTimerController.luau
--
-- Einzige Zustaendigkeit:
--   - Auf dem Feld, direkt am Namensschild des EIGENEN Baerchis, anzeigen,
--     wie lange es noch bis zum naechsten gelegten Ei dauert.
--
-- ============================================================
-- WARUM DAS REIN CLIENTSEITIG TICKT
-- ============================================================
-- Der Server schickt nur EINEN Zeitstempel (island.lastEggAt), keinen
-- laufenden Countdown — dasselbe Zeitmarken-Prinzip wie ueberall im Projekt
-- (Honig, Brut-Timer). Eine Anzeige, die jede Sekunde weiterzaehlt, braucht
-- dafuer keinen einzigen zusaetzlichen Netzwerk-Roundtrip: das Legeintervall
-- steht als reine Formel in EggCalculator (geteiltes Modul, ReplicatedStorage)
-- und ist auf dem Client genauso berechenbar wie auf dem Server.
--
-- Das ist eine bewusste Ausnahme von "der Client hat keinen eigenen
-- Wahrheitsstand" — hier wird nichts SIMULIERT, nur eine bereits bekannte
-- Formel auf einen bereits bekannten Zeitstempel angewendet. Sobald der
-- naechste PlayerDataUpdated hereinkommt (z.B. weil das Ei tatsaechlich
-- gelegt wurde), zeigt der naechste Tick automatisch wieder den echten Stand.
--
-- ============================================================
-- WARUM NUR DER EIGENE BAERCHI
-- ============================================================
-- PlayerDataUpdated liefert ausschliesslich die eigene Insel (siehe
-- ClientState-Kommentar-Kopf) — fuer die Baerchis anderer Spieler haette
-- dieser Client also gar keine Zahlen, mit denen er rechnen koennte.

local Players   = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EggConfig     = require(ReplicatedStorage.Config.EggConfig)
local EggCalculator = require(ReplicatedStorage.Modules.EggCalculator)
local Loc           = require(ReplicatedStorage.Localization.Loc)

local ClientState = require(script.Parent.ClientState)

local EggTimerController = {}

local OWNER_ATTRIBUTE = "PlotOwner"
local UID_ATTRIBUTE   = "BaerchiUid"
local TICK_SECONDS     = 1

-- Das aktuell bekannte Label des EIGENEN Baerchis, plus seine uid. Wird bei
-- jedem Neuaufbau der Figur (Level-Up, Equip-Wechsel) neu gefunden und
-- ersetzt automatisch den alten Eintrag.
local _label: TextLabel? = nil
local _uid: string? = nil

-- v12: Zustand der Pet-Leiste (PetModeChanged). Ist der Baerchi unterwegs
-- (Event/PIT), pausiert der Lege-Timer auf dem Server — dann zeigt das
-- Schild das an, statt herunterzuzaehlen.
local _petState = "Home"

--------------------------------------------------------------------------------
-- Wem gehoert der Plot, in dem dieses Teil steckt?
--
-- Dieselbe Logik wie in WorldController.findPlotOwner. Bewusst hier noch
-- einmal (kurz genug) statt geteilt, damit dieser Controller unabhaengig
-- bleibt und nichts von WorldControllers interner Struktur wissen muss.
--------------------------------------------------------------------------------
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

--------------------------------------------------------------------------------
-- Anzeige
--------------------------------------------------------------------------------

local function formatSeconds(totalSeconds: number): string
	local seconds = math.max(0, math.floor(totalSeconds))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- Schreibt den aktuellen Countdown in das gemerkte Label. Laeuft jede Sekunde
-- UND sofort nach dem Einhaengen eines neuen Labels, damit nicht bis zu einer
-- Sekunde lang "kein Text" zu sehen ist.
local function refresh()
	local label = _label
	local uid   = _uid
	if not label or not uid then return end

	if not label.Parent then
		-- Figur wurde inzwischen neu aufgebaut (altes Label zerstoert) — der
		-- naechste hook() findet das neue Label von selbst.
		_label = nil
		_uid   = nil
		return
	end

	local data = ClientState.get()
	if not data then return end

	-- Der Baerchi kann inzwischen umgeruestet worden sein, ohne dass diese
	-- Figur schon durch eine neue ersetzt wurde (kurzes Zeitfenster waehrend
	-- MapService neu baut) — dann lieber nichts anzeigen als etwas Falsches.
	if data.island.equippedUid ~= uid then
		label.Text = ""
		return
	end

	local baerchi = data.island.baerchis[uid]
	if not baerchi then
		label.Text = ""
		return
	end

	if _petState ~= "Home" then
		label.Text = Loc.t("ui.egg.paused_away")
		return
	end

	if #data.island.laidEggs >= EggConfig.MAX_UNCOLLECTED_EGGS then
		label.Text = Loc.t("ui.egg.full")
		return
	end

	local interval = EggCalculator.getLayIntervalSeconds(baerchi, false)
	if not interval then
		-- Dieser Baerchi legt grundsaetzlich keine Eier (kein layIntervalSeconds
		-- oder keine eggTable in seiner Config).
		label.Text = ""
		return
	end

	local nextAt      = (data.island.lastEggAt or os.time()) + interval
	local secondsLeft = nextAt - os.time()

	label.Text = if secondsLeft <= 0
		then Loc.t("ui.egg.soon")
		else Loc.t("ui.egg.next", { time = formatSeconds(secondsLeft) })
end

--------------------------------------------------------------------------------
-- Label finden
--------------------------------------------------------------------------------

-- Sucht am Modell der gerade angekommenen Part nach dem "EggTimer"-Label, das
-- MapService.buildBaerchiFigure im Namensschild mit anlegt. Nur fuer den
-- EIGENEN Plot — fuer fremde Baerchis gibt es weder Daten noch einen Grund,
-- deren Timer mitzuzaehlen.
local function tryHookFigurePart(part: BasePart): boolean
	local uid = part:GetAttribute(UID_ATTRIBUTE)
	if typeof(uid) ~= "string" then return false end
	if not isOwnPlot(part) then return false end

	local model = part:FindFirstAncestorWhichIsA("Model")
	if not model then return false end

	local label = model:FindFirstChild("EggTimer", true)
	if not (label and label:IsA("TextLabel")) then return false end

	_label = label
	_uid   = uid
	refresh()

	return true
end

local function hook(instance: Instance)
	if not instance:IsA("BasePart") then return end
	tryHookFigurePart(instance)
end

--------------------------------------------------------------------------------
-- Initialisierung
--------------------------------------------------------------------------------

function EggTimerController.init()
	for _, descendant in Workspace:GetDescendants() do
		hook(descendant)
	end

	-- Die Figuren werden bei jedem Struktur-Neuaufbau ersetzt (siehe
	-- PlotDisplayService) — also staendig neu einhaengen.
	Workspace.DescendantAdded:Connect(hook)

	-- Bei einem Sprachwechsel sofort neu beschriften statt bis zum naechsten
	-- Sekunden-Tick zu warten.
	Loc.onChanged(function()
		refresh()
	end)

	local Remotes = require(ReplicatedStorage.Network.Remotes)
	Remotes.PetModeChanged.OnClientEvent:Connect(function(state: any)
		_petState = if typeof(state) == "string" then state else "Home"
		pcall(refresh)
	end)

	task.spawn(function()
		while true do
			task.wait(TICK_SECONDS)

			local ok, err = pcall(refresh)
			if not ok then
				warn("[EggTimerController] Tick fehlgeschlagen:", err)
			end
		end
	end)

	print("[EggTimerController] Initialisiert")
end

return EggTimerController
