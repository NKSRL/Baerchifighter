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
-- R1: der eine Fensterbereich
--------------------------------------------------------------------------------
-- ALLE Fenster (Theme.dialog, Kit.window, auch kuenftige) werden in diesem
-- Bereich zentriert und, wenn sie nicht hineinpassen, gleichmaessig verkleinert
-- (Seitenverhaeltnis bleibt). Es gibt keine Einzelpositionen pro Panel.
--
-- Der Bereich reicht von oben bis knapp ueber die Pet-Leiste (Event/Fight):
-- die beiden Knoepfe bleiben bei offenem Fenster sichtbar und antippbar. Wie
-- hoch die Leiste ist, meldet sie selbst (setBottomReserve) — dieses Modul
-- kennt keine UI-Bausteine.
--
-- Alle Masse in Oberflaechen-Einheiten (nach der globalen UiScale).
PanelManager.AREA = {
	top          = 12,     -- Luft nach oben (unter der Roblox-Topbar)
	sideFraction = 0.03,   -- Luft links/rechts als Anteil der Breite
	bottomMin    = 12,     -- Luft unten, wenn keine Pet-Leiste gemeldet wurde
}

export type Area = {
	center : Vector2,   -- Mitte des freien Bereichs
	size   : Vector2,   -- Breite/Hoehe des freien Bereichs
}

local _bottomReserve = 0
-- 21.10.: zusaetzlicher Platz unter dem Fenster (Verkaufsleiste der Baerchi-Liste haengt UNTER
-- dem Fenster). Das Fenster schrumpft dafuer; die Pet-Leiste bleibt unberuehrt.
local _extraBottom = 0
local _areaListeners: { () -> () } = {}

-- Die Pet-Leiste meldet, wie viel Hoehe unten (Rand + Leiste + Luft) belegt ist.
function PanelManager.setBottomReserve(units: number)
	if math.abs(units - _bottomReserve) < 0.5 then return end
	_bottomReserve = units
	for _, callback in _areaListeners do
		task.spawn(callback)
	end
end

-- Hoehe, die unten von der Pet-Leiste belegt ist (Rand + Leiste + Luft), in Oberflaechen-Einheiten.
function PanelManager.getBottomReserve(): number
	return math.max(PanelManager.AREA.bottomMin, _bottomReserve)
end

function PanelManager.setExtraBottom(units: number)
	if math.abs(units - _extraBottom) < 0.5 then return end
	_extraBottom = units
	for _, callback in _areaListeners do
		task.spawn(callback)
	end
end

-- Wird gerufen, wenn sich der Bereich aendert (Fenster rechnen sich neu).
function PanelManager.onAreaChanged(callback: () -> ())
	table.insert(_areaListeners, callback)
end

-- `screen` = Bildschirmgroesse in Oberflaechen-Einheiten.
function PanelManager.getArea(screen: Vector2): Area
	local top = PanelManager.AREA.top
	local side = screen.X * PanelManager.AREA.sideFraction
	local bottom = math.max(PanelManager.AREA.bottomMin, _bottomReserve) + _extraBottom
	local size = Vector2.new(math.max(1, screen.X - side * 2), math.max(1, screen.Y - top - bottom))
	return { center = Vector2.new(screen.X * 0.5, top + size.Y * 0.5), size = size }
end

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

-- W1-P6: welches Fenster ist gerade offen? (Gamepad: B schliesst das oberste)
function PanelManager.current(): string?
	return _openName
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

-- R1: Bereiche, die nie als "ausserhalb" zaehlen (Pet-Leiste inkl. der Luecke
-- zwischen den Knoepfen, die selbst kein Knopf ist). Der Besitzer meldet per
-- Funktion, ob ein Bildschirm-Punkt (Pixel, wie InputObject.Position) darin liegt.
local _tapGuards: { (Vector2) -> boolean } = {}

function PanelManager.addTapGuard(isProtected: (Vector2) -> boolean)
	table.insert(_tapGuards, isProtected)
end

local function isGuarded(position: Vector3): boolean
	local point = Vector2.new(position.X, position.Y)
	for _, guard in _tapGuards do
		local ok, result = pcall(guard, point)
		if ok and result then return true end
	end
	return false
end

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
	if isGuarded(input.Position) then return end
	PanelManager.close(name)
end)

return PanelManager
