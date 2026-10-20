--!strict
-- AudioController.luau
-- StarterPlayerScripts/Controllers/AudioController.luau
--
-- Einzige Zustaendigkeit:
--   - Musik: drei Schleifen, leises Einblenden nach dem Laden, Ueberblendung
--     (2 s) beim Zonenwechsel, Absenken bei grossen Momenten
--   - Effekte: Cooldown, Tonhoehen-Streuung, Stimmen-Limit, Lautstaerke-Gruppen
--   - Die Regler (Musik / Effekte / Stumm) anwenden und speichern
--
-- Alle Ids und Zahlen stehen in ReplicatedStorage/Audio — hier nur Verhalten.
--
-- ============================================================
-- ZONEN (welche Musik laeuft)
-- ============================================================
--   menu  : irgendein Fenster offen (ausser dem Tower-Fenster "Combat")
--   fight : Tower-Fenster offen, oder das Pet ist unterwegs/im Tower
--   main  : sonst (Farm / Lobby)
-- Ein Fenster zu oeffnen blendet also von "main" nach "menu", Schliessen
-- zurueck. Gewechselt wird erst, wenn sich die Zone 0,6 s lang nicht mehr aendert.
--
-- ============================================================
-- LAUTSTAERKE
-- ============================================================
-- Zwei SoundGroups (HBB_Music, HBB_Sfx) unter SoundService. Der Regler setzt
-- nur deren Volume; die einzelnen Sounds behalten ihre Config-Lautstaerke.
-- Stumm = beide Gruppen 0 (die Musik laeuft stumm weiter, kein Neustart).

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService      = game:GetService("SoundService")
local TweenService      = game:GetService("TweenService")
local Debris            = game:GetService("Debris")
local Workspace         = game:GetService("Workspace")

local Audio   = require(ReplicatedStorage.Audio)
local Remotes = require(ReplicatedStorage.Network.Remotes)
local Types   = require(ReplicatedStorage.Network.Types)

local ClientState  = require(script.Parent.ClientState)
local PanelManager = require(script.Parent.Parent.UI.PanelManager)

local AudioController = {}

local T = Audio.TUNING

local _musicGroup: SoundGroup? = nil
local _sfxGroup: SoundGroup? = nil
local _tracks: { [string]: Sound } = {}
local _trackLevel: { [string]: number } = {}   -- 0..1 je Spur (Ein-/Ausblenden)
local _current: string? = nil                  -- Spur, die gerade eingeblendet ist
local _started = false

local _settings: Audio.Settings = Audio.sanitize(nil)
local _duckFactor = 1
local _duckToken = 0

local _lastPlayed: { [string]: number } = {}
local _routineTimes: { number } = {}
local _worldTimes: { number } = {}
local _listeners: { (Audio.Settings) -> () } = {}

--------------------------------------------------------------------------------
-- Gruppen / Lautstaerke
--------------------------------------------------------------------------------

local function applyVolumes()
	local music, sfx = _musicGroup, _sfxGroup
	local factor = if _settings.muted then 0 else 1
	if music then music.Volume = _settings.music * factor * _duckFactor end
	if sfx then sfx.Volume = _settings.sfx * factor end
end

local function makeGroup(name: string): SoundGroup
	local old = SoundService:FindFirstChild(name)
	if old then old:Destroy() end
	local group = Instance.new("SoundGroup")
	group.Name = name
	group.Parent = SoundService
	return group
end

--------------------------------------------------------------------------------
-- Musik
--------------------------------------------------------------------------------

local function trackVolume(name: string): number
	local def = Audio.MUSIC[name]
	return (if def then def.volume else 0) * (_trackLevel[name] or 0)
end

-- Zielstufe einer Spur in `seconds` ansteuern (Stufe 0..1, nicht Sound.Volume,
-- damit die Config-Lautstaerke einer Spur spaeter geaendert werden darf).
local _levelTweens: { [string]: thread } = {}
local function fadeTrack(name: string, target: number, seconds: number)
	local sound = _tracks[name]
	if not sound then return end
	local old = _levelTweens[name]
	if old then task.cancel(old) end

	local from = _trackLevel[name] or 0
	if target > 0 and not sound.IsPlaying then sound:Play() end   -- Pause → macht an der Stelle weiter
	_levelTweens[name] = task.spawn(function()
		local startTime = os.clock()
		while true do
			local alpha = if seconds <= 0 then 1 else math.clamp((os.clock() - startTime) / seconds, 0, 1)
			-- Gleichmaessiges Ein-/Ausblenden (sanfter Start und Ende)
			local eased = alpha * alpha * (3 - 2 * alpha)
			_trackLevel[name] = from + (target - from) * eased
			sound.Volume = trackVolume(name)
			if alpha >= 1 then break end
			task.wait()
		end
		_levelTweens[name] = nil
		if target <= 0 then sound:Pause() end
	end)
end

local function setTrack(name: string, seconds: number)
	if name == _current then return end
	local previous = _current
	_current = name
	if previous then fadeTrack(previous, 0, seconds) end
	fadeTrack(name, 1, seconds)
end

local function buildTracks()
	local group = _musicGroup
	if not group then return end
	for name, def in Audio.MUSIC do
		local id = Audio.resolve(def)
		if id ~= "" then
			local sound = Instance.new("Sound")
			sound.Name = "Music_" .. name
			sound.SoundId = id
			sound.Looped = true
			sound.Volume = 0
			sound.SoundGroup = group
			sound.Parent = group
			_tracks[name] = sound
			_trackLevel[name] = 0
		end
	end
end

--------------------------------------------------------------------------------
-- Zone bestimmen
--------------------------------------------------------------------------------

local _panelOpen: string? = nil
local _petState = "Home"
local _desiredZone = "main"
local _zoneStamp = 0

local function zoneNow(): string
	local panel = _panelOpen
	if panel and panel ~= PanelManager.ARENA_PANEL then return "menu" end
	if panel == PanelManager.ARENA_PANEL or _petState == "ToPit" or _petState == "InPit" then return "fight" end
	return "main"
end

local function onZoneInputChanged()
	local zone = zoneNow()
	if zone == _desiredZone then return end
	_desiredZone = zone
	_zoneStamp += 1
	local stamp = _zoneStamp
	task.delay(T.ZONE_SETTLE_SECONDS, function()
		if stamp ~= _zoneStamp or not _started then return end
		setTrack(_desiredZone, T.CROSSFADE_SECONDS)
	end)
end

--------------------------------------------------------------------------------
-- Absenken (Ducking)
--------------------------------------------------------------------------------

-- Senkt die Musik fuer `seconds` auf DUCK_LEVEL und blendet sie danach wieder ein.
function AudioController.duck(seconds: number)
	_duckToken += 1
	local token = _duckToken
	task.spawn(function()
		local from = _duckFactor
		local startTime = os.clock()
		while token == _duckToken do   -- runter
			local alpha = math.clamp((os.clock() - startTime) / T.DUCK_ATTACK, 0, 1)
			_duckFactor = from + (T.DUCK_LEVEL - from) * alpha
			applyVolumes()
			if alpha >= 1 then break end
			task.wait()
		end
		if token ~= _duckToken then return end
		task.wait(seconds)
		if token ~= _duckToken then return end
		startTime = os.clock()
		while token == _duckToken do   -- hoch
			local alpha = math.clamp((os.clock() - startTime) / T.DUCK_RELEASE, 0, 1)
			_duckFactor = T.DUCK_LEVEL + (1 - T.DUCK_LEVEL) * alpha
			applyVolumes()
			if alpha >= 1 then break end
			task.wait()
		end
	end)
end

--------------------------------------------------------------------------------
-- Effekte
--------------------------------------------------------------------------------

-- Gleitendes Fenster: darf noch eine Stimme starten?
local function takeSlot(times: { number }, window: number, maxCount: number): boolean
	local now = os.clock()
	local kept = 0
	for i = 1, #times do
		if now - times[i] < window then
			kept += 1
			times[kept] = times[i]
		end
	end
	for i = #times, kept + 1, -1 do times[i] = nil end
	if kept >= maxCount then return false end
	table.insert(times, now)
	return true
end

local function pitchFor(def: Audio.SfxDef): number
	if def.pitch <= 0 then return 1 end
	return 1 + (math.random() * 2 - 1) * def.pitch
end

-- Spielt einen Effekt (2D, nur fuer diesen Spieler). Gibt den Sound zurueck oder
-- nil, wenn er wegen Cooldown, Limit oder fehlender Id nicht gespielt wurde.
function AudioController.play(name: string, volumeScale: number?): Sound?
	local def = Audio.SFX[name]
	local group = _sfxGroup
	if not def or not group then return nil end
	local id = Audio.resolve(def)
	if id == "" then return nil end

	local now = os.clock()
	local last = _lastPlayed[name]
	if last and now - last < def.cooldown then return nil end
	if not def.special and not takeSlot(_routineTimes, T.ROUTINE_WINDOW, T.MAX_ROUTINE) then return nil end
	_lastPlayed[name] = now

	local sound = Instance.new("Sound")
	sound.Name = "Sfx_" .. name
	sound.SoundId = id
	sound.Volume = def.volume * (volumeScale or 1)
	sound.PlaybackSpeed = pitchFor(def)
	sound.SoundGroup = group
	sound.Parent = group
	sound:Play()
	sound.Ended:Once(function() sound:Destroy() end)
	Debris:AddItem(sound, 12)

	if def.special and def.duck then AudioController.duck(def.duck) end
	return sound
end

-- Fuer Klaenge anderer Spieler / der Welt (Faehigkeiten): Stimmen-Limit und
-- Pitch-Fenster. Liefert false, wenn jetzt kein weiterer Klang spielen soll.
function AudioController.takeWorldSlot(): boolean
	return takeSlot(_worldTimes, T.WORLD_WINDOW, T.MAX_WORLD)
end

function AudioController.clampWorldPitch(pitch: number): number
	return math.clamp(pitch, T.WORLD_PITCH_MIN, T.WORLD_PITCH_MAX)
end

-- Gruppe fuer Sounds, die andere Module selbst bauen (3D-Klaenge in der Welt):
-- so folgen sie dem Effekt-Regler und der Stumm-Taste.
function AudioController.sfxGroup(): SoundGroup?
	return _sfxGroup
end

--------------------------------------------------------------------------------
-- Einstellungen
--------------------------------------------------------------------------------

function AudioController.getSettings(): Audio.Settings
	return { music = _settings.music, sfx = _settings.sfx, muted = _settings.muted }
end

function AudioController.onSettingsChanged(callback: (Audio.Settings) -> ())
	table.insert(_listeners, callback)
end

local PENDING_SECONDS = 5
local _pendingUntil = 0
local _saveStamp = 0

local function notify()
	for _, callback in _listeners do
		task.spawn(callback, AudioController.getSettings())
	end
end

local function scheduleSave()
	_saveStamp += 1
	local stamp = _saveStamp
	_pendingUntil = os.clock() + PENDING_SECONDS
	task.delay(T.SAVE_DELAY_SECONDS, function()
		if stamp ~= _saveStamp then return end
		Remotes.RequestSetAudio:FireServer(_settings.music, _settings.sfx, _settings.muted)
	end)
end

-- Teilweise Aenderung (nur die gegebenen Felder). Wirkt sofort, gespeichert
-- wird verzoegert, wenn der Regler zur Ruhe gekommen ist.
function AudioController.set(change: { music: number?, sfx: number?, muted: boolean? })
	local merged = Audio.sanitize({
		music = if change.music ~= nil then change.music else _settings.music,
		sfx   = if change.sfx   ~= nil then change.sfx   else _settings.sfx,
		muted = if change.muted ~= nil then change.muted else _settings.muted,
	})
	if merged.music == _settings.music and merged.sfx == _settings.sfx and merged.muted == _settings.muted then
		return
	end
	_settings = merged
	applyVolumes()
	notify()
	scheduleSave()
end

local _seenServer = false
local function onData(update: Types.PlayerDataUpdate)
	local serverValue = (update :: any).audio
	if _seenServer and os.clock() < _pendingUntil then return end   -- eigene Wahl hat Vorrang
	if serverValue == nil then
		_seenServer = true
		return
	end
	local clean = Audio.sanitize(serverValue)
	if _seenServer and clean.music == _settings.music and clean.sfx == _settings.sfx and clean.muted == _settings.muted then
		return
	end
	_seenServer = true
	_settings = clean
	applyVolumes()
	notify()
end

--------------------------------------------------------------------------------
-- Welt-Klaenge vom Server (Kampf-Treffer) in die Effekt-Gruppe holen
--------------------------------------------------------------------------------

local function adoptWorldSound(instance: Instance)
	if instance:IsA("Sound") and instance.Name == "WorldSfx" then
		instance.SoundGroup = _sfxGroup
	end
end

--------------------------------------------------------------------------------
-- Start
--------------------------------------------------------------------------------

function AudioController.init()
	_musicGroup = makeGroup("HBB_Music")
	_sfxGroup   = makeGroup("HBB_Sfx")
	applyVolumes()
	buildTracks()

	Audio.setPlayer(AudioController.play)   -- gemeinsamer Code (VFX) spielt ueber Audio.play

	ClientState.onChanged(onData)

	PanelManager.onOpened(function(name)
		_panelOpen = name
		onZoneInputChanged()
	end)
	PanelManager.onClosed(function(name)
		if _panelOpen == name then _panelOpen = nil end
		onZoneInputChanged()
	end)
	Remotes.PetModeChanged.OnClientEvent:Connect(function(state: any)
		_petState = if typeof(state) == "string" then state else "Home"
		onZoneInputChanged()
	end)

	Workspace.DescendantAdded:Connect(adoptWorldSound)
	for _, descendant in Workspace:GetDescendants() do adoptWorldSound(descendant) end

	-- Musik beginnt erst nach dem Laden und blendet sehr langsam ein
	task.spawn(function()
		if not game:IsLoaded() then game.Loaded:Wait() end
		task.wait(T.START_DELAY_SECONDS)
		_started = true
		_desiredZone = zoneNow()
		setTrack(_desiredZone, T.START_FADE_SECONDS)
	end)

	-- Nur im Studio: Zugriff fuer Tests und zum Abstimmen der Lautstaerken, z.B.
	-- in der Befehlsleiste (Client): _G.HBBAudio.play("levelUp")
	if RunService:IsStudio() then
		(_G :: any).HBBAudio = AudioController
	end

	print("[AudioController] Initialisiert |", Players.LocalPlayer.Name)
end

return AudioController
