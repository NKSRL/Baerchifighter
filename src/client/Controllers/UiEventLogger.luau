--!strict
-- UiEventLogger.luau
-- StarterPlayerScripts/Controllers/UiEventLogger.luau
--
-- Einzige Zustaendigkeit:
--   - Wenige UI-Messpunkte an den Server melden (RequestLogUiEvent)
--
-- Kontext: HBB Paket 0. Gemessen wird, was ein neuer Spieler mit der
-- Oberflaeche macht: welches Panel er oeffnet, ob er es sofort wieder
-- schliesst (nicht verstanden) und ob er lange still steht (weiss nicht
-- weiter). Der Server prueft Namen und Menge (FunnelService); dieser
-- Controller ist nur der Zulieferer.
--
-- Stillstand wird pro Ruhephase einmal gemeldet. Ein Spieler, der vor dem
-- Bildschirm einschlaeft, erzeugt also nicht alle 20 s ein Ereignis.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes      = require(ReplicatedStorage.Network.Remotes)
local FunnelConfig = require(ReplicatedStorage.Config.FunnelConfig)

local PanelManager = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("PanelManager"))

local UiEventLogger = {}

-- Takt der Stillstands-Pruefung. Grob reicht: gemessen wird "mehr als 20 s".
local IDLE_CHECK_INTERVAL = 1
-- Unter dieser Strecke pro Takt gilt der Charakter als stehend (Studs).
local IDLE_MOVE_EPSILON = 0.5

-- Abstand zwischen zwei Sendungen. Etwas ueber dem Server-Cooldown
-- (NetworkConfig.RequestLogUiEvent), sonst verwirft der RateLimiter das
-- zweite Ereignis, wenn z.B. ein Panel ein anderes ersetzt.
local SEND_GAP = 0.25
-- Mehr als das wartet nie: der Server nimmt pro Sitzung ohnehin nur
-- FunnelConfig.MAX_UI_EVENTS_PER_SESSION an.
local MAX_QUEUE = 10

local _queue: { { kind: string, name: string? } } = {}
local _sending = false

local function flush()
	_sending = true
	while #_queue > 0 do
		local entry = table.remove(_queue, 1)
		if not entry then break end
		Remotes.RequestLogUiEvent:FireServer(entry.kind, entry.name)
		task.wait(SEND_GAP)
	end
	_sending = false
end

local function send(kind: string, name: string?)
	if #_queue >= MAX_QUEUE then return end
	table.insert(_queue, { kind = kind, name = name })
	if not _sending then
		task.spawn(flush)
	end
end

local function watchIdle()
	local player = Players.LocalPlayer
	local lastPos: Vector3? = nil
	local stillFor = 0
	local reported = false

	while true do
		task.wait(IDLE_CHECK_INTERVAL)
		local character = player.Character
		local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
		if not root or not root:IsA("BasePart") then
			lastPos = nil
			continue
		end

		local pos = root.Position
		if lastPos and (pos - lastPos).Magnitude < IDLE_MOVE_EPSILON then
			stillFor += IDLE_CHECK_INTERVAL
		else
			stillFor = 0
			reported = false
		end
		lastPos = pos

		if not reported and stillFor >= FunnelConfig.IDLE_SECONDS then
			reported = true
			send("IdleStanding", nil)
		end
	end
end

function UiEventLogger.init()
	PanelManager.onOpened(function(name)
		send("PanelOpened", name)
	end)
	PanelManager.onClosed(function(name, seconds)
		if seconds < FunnelConfig.QUICK_CLOSE_SECONDS then
			send("PanelQuickClose", name)
		end
	end)
	task.spawn(watchIdle)
end

return UiEventLogger
