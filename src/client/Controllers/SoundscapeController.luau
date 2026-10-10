--!strict
-- SoundscapeController.luau
-- StarterPlayerScripts/Controllers/SoundscapeController.luau
--
-- Einzige Zustaendigkeit:
--   - Die leise Klang-Kulisse (Paket H, "Welt aufwerten"): je Ort ein
--     Klangteppich (Ufer, Wiese/Grillen, Honigmast, Event-Pit, Arena-Wind),
--     weich ineinander geblendet nach der Kamera-Position; dazu ab und zu
--     eine Moewe am Ufer und die Glocke beim Event-Start (Paket G)
--
-- Wie laut welche Zone ist, rechnet Modules/SoundZones (rein, getestet).
-- Hier laufen nur die Schleifen: hoechstens MAX_AUDIBLE gleichzeitig hoerbar,
-- jede folgt ihrem Ziel weich (kein harter Schnitt), alle in der Sound-Gruppe
-- "WorldAmbience" und immer leiser als die Kampf-Sounds.
--
-- Nur Klaenge mit einer in Studio GEPRUEFTEN ID (WorldFXConfig.SOUNDS). Ist
-- eine ID leer, bleibt diese Zone still — ohne IDs laeuft gar nichts, und
-- es entsteht keine einzige Sound-Instanz.
--
-- PERFORMANCE: ein Takt (5 Hz), eine Sound-Instanz je Zone (nicht positional,
-- die Mischung macht der Takt). Keine Musik (eigene Entscheidung spaeter).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local SoundService      = game:GetService("SoundService")

local WorldFXConfig = require(ReplicatedStorage.Config.WorldFXConfig)
local FeatureFlags  = require(ReplicatedStorage.Config.FeatureFlags)
local SoundZones    = require(ReplicatedStorage.Modules.SoundZones)

local WorldFXKit         = require(script.Parent.WorldFXKit)
local DayCycleController = require(script.Parent.DayCycleController)

local SoundscapeController = {}

local LOOPS = { "waves", "meadow", "crickets", "drip", "crowd", "wind" }

local _group: SoundGroup? = nil
local _loops: { [string]: Sound } = {}
local _volumes: { [string]: number } = {}
local _gull: Sound? = nil
local _bell: Sound? = nil
local _nextGull = 0
local _eventLive = false

local function soundGroup(): SoundGroup
	local existing = _group or SoundService:FindFirstChild("WorldAmbience")
	if existing and existing:IsA("SoundGroup") then
		_group = existing
		return existing
	end
	local created = Instance.new("SoundGroup")
	created.Name = "WorldAmbience"
	created.Parent = SoundService
	_group = created
	return created
end

local function newSound(key: string, looped: boolean): Sound?
	local id = WorldFXConfig.SOUNDS[key]
	if not id or id == "" then return nil end
	local sound = Instance.new("Sound")
	sound.Name = "Ambience_" .. key
	sound.SoundId = id
	sound.Looped = looped
	sound.Volume = 0
	sound.SoundGroup = soundGroup()
	sound.Parent = SoundService
	return sound
end

-- Glocke beim Event-Start (Paket G). Still ohne gepruefte ID.
function SoundscapeController.bell()
	local bell = _bell
	if bell then
		bell.Volume = (WorldFXConfig.SOUND_VOLUME :: any).bell or 0.1
		bell:Play()
	end
end

-- Laeuft gerade ein Event? (HubEventController meldet den Pit-Zustand.)
function SoundscapeController.setEventLive(live: boolean)
	_eventLive = live
end

function SoundscapeController.init()
	if not (FeatureFlags.isOn("WORLD_H_SOUND") and WorldFXKit.enabled("soundscape")) then return end

	for _, key in LOOPS do
		local sound = newSound(key, true)
		if sound then
			_loops[key] = sound
			_volumes[key] = 0
		end
	end
	_gull = newSound("gull", false)
	_bell = newSound("bell", false)

	if next(_loops) == nil and not _gull then
		print("[Soundscape] still: keine gepruefte Sound-ID in WorldFXConfig.SOUNDS")
		return
	end

	local cfg = WorldFXConfig.SOUNDSCAPE
	local random = Random.new()
	_nextGull = os.clock() + random:NextNumber(cfg.GULL_EVERY[1], cfg.GULL_EVERY[2])
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc < cfg.TICK then return end
		acc = 0
		local camera = workspace.CurrentCamera
		if not camera then return end

		local weights = SoundZones.weights(camera.CFrame.Position, DayCycleController.dusk(), _eventLive)
		local target = SoundZones.audible(weights)
		for key, sound in _loops do
			local max = (WorldFXConfig.SOUND_VOLUME :: any)[key] or 0.06
			local goal = max * (target[key] or 0)
			local v = _volumes[key] + (goal - _volumes[key]) * cfg.FADE * (cfg.TICK / 0.2)
			if math.abs(v - goal) < 0.002 then v = goal end
			_volumes[key] = v
			sound.Volume = v
			if v > 0 and not sound.IsPlaying then
				sound:Play()
			elseif v == 0 and sound.IsPlaying then
				sound:Stop()
			end
		end

		-- Moewe: ab und zu, nur wenn das Ufer gerade zu hoeren ist
		local gull = _gull
		if gull and os.clock() >= _nextGull then
			_nextGull = os.clock() + random:NextNumber(cfg.GULL_EVERY[1], cfg.GULL_EVERY[2])
			if (weights.waves or 0) > 0.5 then
				gull.Volume = (WorldFXConfig.SOUND_VOLUME :: any).gull * weights.waves
				gull:Play()
			end
		end
	end)

	local count = 0
	for _ in _loops do count += 1 end
	print("[Soundscape] aktiv | Schleifen mit ID:", count, "| Moewe:", _gull ~= nil)
end

return SoundscapeController
