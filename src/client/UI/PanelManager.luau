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

-- Seit jedes Gebaeude sein EIGENES Menue hat, brauchen drei Stellen denselben
-- Panel-Namen: BuildingPanel meldet ihn an, die Menueleiste oeffnet ihn, und
-- der Welt-Prompt am Gebaeude auch. Die Konvention steht deshalb hier — das
-- ist ohnehin das Modul, dem die Panel-Namen gehoeren, und keines der drei
-- muss dafuer eines der anderen requiren.
function PanelManager.buildingPanelName(buildingId: string): string
	return "Building_" .. buildingId
end

-- Das Menue der Kampfplattform (Ausbauen). Der Kampf selbst hat ein eigenes
-- Panel ("Combat") — hier geht es nur um die Stufe der Arena.
PanelManager.ARENA_PANEL = "Arena"

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

function PanelManager.getOpen(): string?
	return _openName
end

function PanelManager.closeAll()
	for name, panel in _panels do
		local ok, err = pcall(panel.close)
		if not ok then
			warn("[PanelManager] close fehlgeschlagen:", name, err)
		end
	end
	_openName = nil
end

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

	_openName = name
	panel.open(...)
end

function PanelManager.close(name: string)
	local panel = _panels[name]
	if not panel then return end

	panel.close()
	if _openName == name then
		_openName = nil
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

return PanelManager
