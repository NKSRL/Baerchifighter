--!strict
-- PanelManager.luau
-- StarterPlayerScripts/UI/PanelManager.luau
--
-- Einzige Zustaendigkeit:
--   - Wissen welches Panel gerade offen ist und immer nur eines offen lassen
--
-- Warum es dieses Modul gibt: die Panels muessen sich gegenseitig oeffnen
-- koennen (Inventar → Fusion, Inventar → Detailkarte, Welt-Klick → Kampf).
-- Wuerden sie sich dafuer direkt gegenseitig requiren, entstuenden Zyklen —
-- und Luau bricht bei zyklischen require-Ketten ab.
--
-- Deshalb: jedes Panel meldet sich hier unter einem Namen an, und alle
-- Oeffnen-Aufrufe laufen ueber diesen Namen. Dieses Modul selbst requirt
-- absichtlich nichts aus dem UI-Ordner.
--
-- Nur ein Panel gleichzeitig: auf einem Handy ist gestapeltes UI unbedienbar,
-- und der Spieler soll nie raten muessen welches Fenster gerade zuhoert.

local UserInputService = game:GetService("UserInputService")

local PanelManager = {}

-- open ist bewusst variadisch getypt: manche Panels brauchen Argumente
-- (Detailkarte: uid, Fusion: zwei uids), die meisten keine. Jedes Panel
-- schreibt deshalb `local function openInternal(...: any)` und prueft die
-- Argumente selbst — genau wie der Server es mit Client-Eingaben tut.
export type Panel = {
	open  : (...any) -> (),
	close : () -> (),
}

local _panels: { [string]: Panel } = {}
local _openName: string? = nil

-- HBB Paket 0: Beobachter fuer Messpunkte (UiEventLogger). Bekommen nur den
-- Namen bzw. Namen + offene Dauer; sie duerfen kein Panel steuern.
local _openedAt: number = 0
local _onOpened: { (string) -> () } = {}
local _onClosed: { (string, number) -> () } = {}

local function notifyClosed(name: string)
	local seconds = os.clock() - _openedAt
	for _, callback in _onClosed do
		task.spawn(callback, name, seconds)
	end
end

function PanelManager.onOpened(callback: (string) -> ())
	table.insert(_onOpened, callback)
end

function PanelManager.onClosed(callback: (string, number) -> ())
	table.insert(_onClosed, callback)
end

-- Seit jedes Gebaeude sein EIGENES Menue hat, brauchen drei Stellen denselben
-- Panel-Namen: BuildingPanel meldet ihn an, die Menueleiste oeffnet ihn, und
-- der Welt-Prompt am Gebaeude auch. Die Konvention steht deshalb hier — das
-- ist ohnehin das Modul, dem die Panel-Namen gehoeren, und keines der drei
-- muss dafuer eines der anderen requiren.
function PanelManager.buildingPanelName(buildingId: string): string
	return "Building_" .. buildingId
end

-- v15: der Prompt an der Kampfplattform oeffnet die Tower-Wahl im Kampf-Panel
-- ("Combat"). Das fruehere Ausbau-Menue der Arena (PIT-Level) gibt es nicht mehr.
PanelManager.ARENA_PANEL = "Combat"

--------------------------------------------------------------------------------
-- Anmeldung
--------------------------------------------------------------------------------

function PanelManager.register(name: string, panel: Panel)
	if _panels[name] then
		warn("[PanelManager] Panel doppelt angemeldet:", name)
	end
	_panels[name] = panel
end

--------------------------------------------------------------------------------
-- Steuern
--------------------------------------------------------------------------------

-- Schliesst alle anderen und oeffnet dieses. Zusaetzliche Argumente gehen
-- unveraendert an die open-Funktion des Panels (z.B. die uid einer Karte).
function PanelManager.open(name: string, ...: any)
	local panel = _panels[name]
	if not panel then
		warn("[PanelManager] Unbekanntes Panel:", name)
		return
	end

	for other, entry in _panels do
		if other ~= name then
			local ok, err = pcall(entry.close)
			if not ok then
				warn("[PanelManager] close fehlgeschlagen:", other, err)
			end
		end
	end

	-- Ein Wechsel schliesst das bisherige Panel implizit.
	local previous = _openName
	if previous and previous ~= name then
		notifyClosed(previous)
	end

	_openName = name
	panel.open(...)

	if previous ~= name then
		_openedAt = os.clock()
		for _, callback in _onOpened do
			task.spawn(callback, name)
		end
	end
end

function PanelManager.close(name: string)
	local panel = _panels[name]
	if not panel then return end

	panel.close()
	if _openName == name then
		_openName = nil
		notifyClosed(name)
	end
end

-- Fuer Menue-Buttons: nochmal draufdruecken schliesst wieder.
function PanelManager.toggle(name: string, ...: any)
	if _openName == name then
		PanelManager.close(name)
		return
	end
	PanelManager.open(name, ...)
end

--------------------------------------------------------------------------------
-- Sammel-Update 2.1: Tippen ausserhalb schliesst
--------------------------------------------------------------------------------
-- Ein kurzer Tipp/Klick in die WELT (nicht auf eine Oberflaeche: dann ist
-- gameProcessed true) schliesst das offene Fenster. Bewusst ueber
-- UserInputService statt eines bildschirmfuellenden Knopfs hinter dem
-- Fenster: der wuerde Menueleiste und HUD blockieren. Ein Wischen (Kamera
-- drehen) zaehlt nicht — nur kurz (< TAP_SECONDS) und kaum bewegt.
-- Fenster, die ausdruecklich offen bleiben muessen, stehen in KEEP_OPEN.
local TAP_SECONDS = 0.35
local TAP_MOVE_PX = 14
local KEEP_OPEN: { [string]: boolean } = { Hatch = true, Rebirth = true }

local _tapStart: { [any]: { at: number, pos: Vector3 } } = {}

local function isTapInput(input: InputObject): boolean
	return input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch
end

UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed or not isTapInput(input) or not _openName then return end
	_tapStart[input] = { at = os.clock(), pos = input.Position }
end)

UserInputService.InputEnded:Connect(function(input: InputObject, _processed: boolean)
	local start = _tapStart[input]
	_tapStart[input] = nil
	if not start then return end
	local name = _openName
	if not name or KEEP_OPEN[name] then return end
	if os.clock() - start.at > TAP_SECONDS then return end
	if (input.Position - start.pos).Magnitude > TAP_MOVE_PX then return end
	PanelManager.close(name)
end)

return PanelManager
