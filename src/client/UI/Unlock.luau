--!strict
-- Unlock.luau
-- StarterPlayerScripts/UI/Unlock.luau
--
-- Einzige Zustaendigkeit:
--   - Fuer die Oberflaeche beantworten: ist Element X schon sichtbar, ist es
--     neu (Badge), und es als gesehen melden — plus die kleine Pop-in-Animation
--
-- Kontext: HBB Paket 3. Die Regeln stehen in Modules/UnlockRules (rein,
-- getestet); hier wird nur der aktuelle Client-Stand hineingegeben. Hud,
-- MenuBar und PetBar fragen dieses Modul bei jeder Datenaenderung.
--
-- Mit FeatureFlags.UI_V2_PROGRESSIVE = false ist alles sichtbar und nichts
-- neu — das alte HUD.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local Remotes      = require(ReplicatedStorage.Network.Remotes)
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)
local UnlockRules  = require(ReplicatedStorage.Modules.UnlockRules)

local ClientState = require(script.Parent.Parent.Controllers.ClientState)

local Unlock = {}

-- Lokal schon gemeldet (der Server bestaetigt mit dem naechsten Datenpaket)
local _sent: { [string]: boolean } = {}
-- Lokal zuletzt sichtbar (fuer die Pop-in-Animation beim Wechsel)
local _wasVisible: { [string]: boolean } = {}

function Unlock.enabled(): boolean
	return FeatureFlags.isOn("UI_V2_PROGRESSIVE")
end

function Unlock.isVisible(id: string): boolean
	if not Unlock.enabled() then return true end
	local data = ClientState.get()
	if not data then return UnlockRules.ALWAYS[id] == true end
	return UnlockRules.isVisible(data :: any, id)
end

function Unlock.isNew(id: string): boolean
	if not Unlock.enabled() or UnlockRules.ALWAYS[id] or _sent[id] then return false end
	local data = ClientState.get()
	if not data then return false end
	local seen = (data :: any).uiSeen
	if seen and seen[id] then return false end
	return UnlockRules.isVisible(data :: any, id)
end

function Unlock.markSeen(id: string)
	if not Unlock.enabled() or _sent[id] then return end
	local data = ClientState.get()
	local seen = if data then (data :: any).uiSeen else nil
	if seen and seen[id] then return end
	_sent[id] = true
	Remotes.RequestMarkUiSeen:FireServer({ id })
end

-- Setzt Visible und spielt beim Erscheinen ein kurzes Aufploppen.
-- Gibt true zurueck, wenn das Element GERADE erschienen ist.
function Unlock.apply(id: string, gui: GuiObject): boolean
	local visible = Unlock.isVisible(id)
	local before = _wasVisible[id]
	_wasVisible[id] = visible
	gui.Visible = visible
	if visible and before == false then
		local scale = gui:FindFirstChild("PulseScale")
		if not scale then
			local created = Instance.new("UIScale")
			created.Name = "PulseScale"
			created.Parent = gui
			scale = created
		end
		local uiScale = scale :: UIScale
		uiScale.Scale = 0.2
		TweenService:Create(uiScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		return true
	end
	return false
end

return Unlock
