--!strict
-- DeviceProfile.luau
-- StarterPlayerScripts/UI/DeviceProfile.luau
--
-- Einzige Zustaendigkeit:
--   - Laufzeit-Huelle um die reinen Regeln (Modules/DeviceRules): liest
--     Eingabegeraete und Bildschirmgroesse, haelt das aktuelle Profil und
--     meldet jeden Wechsel (Controller angesteckt, Handy gedreht).
--
-- Welt 1, Paket 6b (20.10.2026), Schalter UI_ADAPTIVE_V1. Alle UI-Module lesen
-- NUR dieses Profil (kein eigenes UserInputService.TouchEnabled mehr in neuem
-- Code). Aus dem Schalter folgt nichts Eigenes: wer das Profil nutzt, fragt
-- `DeviceProfile.enabled()`; aus = Profil bleibt "desktop".
--
-- Erzwingen zum Testen: Spieler-Attribut "HBBDeviceForce" = phone|tablet|
-- console|desktop (setzt der Debug-Befehl `device`); leer/auto = echte Geraete.

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)
local DeviceRules  = require(ReplicatedStorage.Modules.DeviceRules)

local DeviceProfile = {}

export type Kind = DeviceRules.Kind
export type Metrics = DeviceRules.Metrics

local FORCE_ATTRIBUTE = "HBBDeviceForce"

local _kind: Kind = "desktop"
local _lastInput: string? = nil
local _listeners: { (Kind, Kind) -> () } = {}
local _started = false

local function inputName(inputType: Enum.UserInputType): string?
	local name = inputType.Name
	if name:find("^Gamepad") then return "gamepad" end
	if name == "Touch" then return "touch" end
	if name == "Keyboard" then return "keyboard" end
	if name:find("^Mouse") then return "mouse" end
	return nil
end

local function viewport(): (number, number)
	local camera = workspace.CurrentCamera
	if camera then
		return camera.ViewportSize.X, camera.ViewportSize.Y
	end
	return 0, 0
end

local function forced(): Kind?
	local value = Players.LocalPlayer:GetAttribute(FORCE_ATTRIBUTE)
	if value == "phone" or value == "tablet" or value == "console" or value == "desktop" then
		return value :: Kind
	end
	return nil
end

local function compute(): Kind
	if not FeatureFlags.isOn("UI_ADAPTIVE_V1") then return "desktop" end
	local override = forced()
	if override then return override end
	local x, y = viewport()
	return DeviceRules.classify({
		touch = UserInputService.TouchEnabled, keyboard = UserInputService.KeyboardEnabled,
		gamepad = UserInputService.GamepadEnabled, lastInput = _lastInput,
		viewportX = x, viewportY = y,
	})
end

local function refresh()
	local new = compute()
	if new == _kind then return end
	local old = _kind
	_kind = new
	for _, callback in _listeners do
		task.spawn(callback, new, old)
	end
end

-- Schalter UI_ADAPTIVE_V1 an? (aus: Profil bleibt desktop, nichts passt sich an)
function DeviceProfile.enabled(): boolean
	return FeatureFlags.isOn("UI_ADAPTIVE_V1")
end

function DeviceProfile.kind(): Kind
	return _kind
end

function DeviceProfile.metrics(): Metrics
	return DeviceRules.metrics(_kind)
end

function DeviceProfile.isConsole(): boolean return _kind == "console" end
function DeviceProfile.isTouch(): boolean return _kind == "phone" or _kind == "tablet" end

-- Meldet (neu, alt) bei jedem Wechsel. Gibt eine Trennfunktion zurueck.
function DeviceProfile.onChanged(callback: (Kind, Kind) -> ()): () -> ()
	table.insert(_listeners, callback)
	return function()
		local i = table.find(_listeners, callback)
		if i then table.remove(_listeners, i) end
	end
end

-- Mindestflaeche pruefen (Bildschirm-Pixel); fuer das Audit und fuer Panels.
function DeviceProfile.touchOk(widthPx: number, heightPx: number, isMain: boolean?): boolean
	return DeviceRules.touchOk(_kind, widthPx, heightPx, isMain)
end

-- Rand fuer Konsolen (Oberflaechen-Einheiten gleich Pixel/Skala): >= 5 % der
-- Seite, sonst 0. Aufrufer rechnen mit UiScale.toGui um.
function DeviceProfile.safeMarginPx(sidePx: number): number
	return DeviceRules.safeMargin(_kind, sidePx)
end

-- Audit (6a): alle sichtbaren Knoepfe unter dem Mindestmass fuer `kind`,
-- gerechnet in Bildschirm-Pixeln bei der Skala, die UiScale fuer die Hoehe
-- `screenHeight` liefert. Reine Lesefunktion fuer den Bericht.
function DeviceProfile.audit(root: Instance, kind: Kind, uiScale: number): { { name: string, w: number, h: number } }
	local m = DeviceRules.metrics(kind)
	local small = {}
	for _, d in root:GetDescendants() do
		if d:IsA("GuiButton") and d.Visible then
			local w, h = d.AbsoluteSize.X, d.AbsoluteSize.Y
			-- AbsoluteSize ist in echten Pixeln der AKTUELLEN Skala; auf `uiScale` umrechnen.
			local global = root:FindFirstChild("GlobalScale")
			local current = if global and global:IsA("UIScale") then math.max(global.Scale, 0.01) else 1
			local k = uiScale / current
			if w > 0 and h > 0 and math.min(w * k, h * k) < m.minTouch then
				table.insert(small, { name = d:GetFullName(), w = w * k, h = h * k })
			end
		end
	end
	return small
end

function DeviceProfile.init()
	if _started then return end
	_started = true
	_lastInput = inputName(UserInputService:GetLastInputType())
	UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		local name = inputName(inputType)
		if name and name ~= _lastInput then
			_lastInput = name
			refresh()
		end
	end)
	for _, prop in { "TouchEnabled", "KeyboardEnabled", "GamepadEnabled" } do
		UserInputService:GetPropertyChangedSignal(prop):Connect(refresh)
	end
	Players.LocalPlayer:GetAttributeChangedSignal(FORCE_ATTRIBUTE):Connect(refresh)
	local function watchCamera()
		local camera = workspace.CurrentCamera
		if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh) end
	end
	watchCamera()
	workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		watchCamera()
		refresh()
	end)
	refresh()
end

return DeviceProfile
