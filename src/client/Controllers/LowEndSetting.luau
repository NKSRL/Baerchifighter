--!strict
-- LowEndSetting.luau
-- StarterPlayerScripts/Controllers/LowEndSetting.luau
--
-- Einzige Zustaendigkeit:
--   - Die Option "Schwaches Geraet" halten: lesen, setzen, Aenderungen melden
--     und im Spielstand speichern (data.lowEnd, Remote RequestSetLowEnd)
--
-- Wer Partikel oder andere Effekte sparen will, fragt LowEndSetting.get().
-- Klinkt sich beim Laden selbst in ClientState ein, braucht keinen init-Aufruf.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Network.Remotes)
local Types   = require(ReplicatedStorage.Network.Types)

local ClientState = require(script.Parent.ClientState)

local LowEndSetting = {}

-- Eine eigene Wahl hat kurz Vorrang vor dem Server-Stand (er kennt sie noch nicht).
local PENDING_SECONDS = 5

local _low = false
local _pendingUntil = 0
local _listeners: { (boolean) -> () } = {}

function LowEndSetting.get(): boolean
	return _low
end

function LowEndSetting.onChanged(callback: (boolean) -> ())
	table.insert(_listeners, callback)
end

local function notify()
	for _, callback in _listeners do
		task.spawn(callback, _low)
	end
end

function LowEndSetting.set(value: boolean)
	if value == _low then return end
	_low = value
	_pendingUntil = os.clock() + PENDING_SECONDS
	notify()
	Remotes.RequestSetLowEnd:FireServer(value)
end

ClientState.onChanged(function(update: Types.PlayerDataUpdate)
	if os.clock() < _pendingUntil then return end
	local server = update.lowEnd == true
	if server ~= _low then
		_low = server
		notify()
	end
end)

return LowEndSetting
