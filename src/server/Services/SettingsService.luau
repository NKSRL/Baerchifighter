--!strict
-- SettingsService.luau
-- ServerScriptService/Services/SettingsService.luau
--
-- Einzige Zustaendigkeit:
--   - Spieler-Einstellungen annehmen, pruefen und in den Spielerdaten ablegen
--     (aktuell: die gewaehlte Sprache)
--
-- Der Server kennt die Sprache eines Spielers NUR, um sie zu speichern und
-- beim naechsten Join zurueckzuschicken. Er formuliert nie einen Text in einer
-- Sprache (siehe Localization/Loc): Fehlermeldungen gehen als Schluessel +
-- Zahlen raus, der Client baut den Satz. Deshalb muss der Server keine
-- Sprachtabellen laden und kostet die Mehrsprachigkeit ihn keinen Speicher.
--
-- Nicht gespeichert wird die automatisch erkannte Sprache: nil bedeutet "folge
-- der Roblox-Einstellung des Clients". So wandert ein Spieler, der sein
-- Roblox-Konto spaeter umstellt, ohne eigenes Zutun mit.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes = require(ReplicatedStorage.Network.Remotes)
local Loc     = require(ReplicatedStorage.Localization.Loc)
local Audio   = require(ReplicatedStorage.Audio)

local PlayerService = require(ServerScriptService.Services.PlayerService)
local RateLimiter   = require(ServerScriptService.Util.RateLimiter)

local SettingsService = {}

-- Der Client darf hier nur eines: eine unterstuetzte Sprache oder "auto" (nil)
-- schicken. Alles andere wird still verworfen — der Wert landet im DataStore,
-- und ein beliebiger String dort waere eine unnoetige Angriffsflaeche.
function SettingsService.setLanguage(player: Player, language: any)
	local data = PlayerService.getData(player)
	if not data then return end

	local newValue: string? = nil
	if language == nil or language == "auto" then
		newValue = nil
	elseif Loc.isSupported(language) then
		newValue = language :: string
	else
		return
	end

	if data.language == newValue then
		return   -- nichts geaendert, kein Daten-Update noetig
	end

	data.language = newValue
	PlayerService.markDirty(player)
end

-- Audio-Rework 16.10.: Musik-/Effekt-Regler und Stumm-Taste. Der Client darf
-- nur drei Werte schicken; Audio.sanitize klemmt sie auf 0..1 (zwei
-- Nachkommastellen) bzw. true/false, alles andere wird zum Standardwert.
function SettingsService.setAudio(player: Player, music: any, sfx: any, muted: any)
	local data = PlayerService.getData(player)
	if not data then return end

	local clean = Audio.sanitize({ music = music, sfx = sfx, muted = muted })
	local old = (data :: any).audio
	if old and old.music == clean.music and old.sfx == clean.sfx and old.muted == clean.muted then
		return
	end

	(data :: any).audio = clean
	PlayerService.markDirty(player)
end

-- 21.10.: "Schwaches Geraet". Der Client darf nur true/false schicken; alles
-- andere wird still verworfen. false wird als nil gespeichert (kein Feld).
function SettingsService.setLowEnd(player: Player, value: any)
	local data = PlayerService.getData(player)
	if not data then return end
	if typeof(value) ~= "boolean" then return end

	local newValue: boolean? = if value then true else nil
	if data.lowEnd == newValue then return end

	data.lowEnd = newValue
	PlayerService.markDirty(player)
end

function SettingsService.init()
	RateLimiter.connect(Remotes.RequestSetLanguage, "RequestSetLanguage", function(player, language: any)
		SettingsService.setLanguage(player, language)
	end)
	RateLimiter.connect(Remotes.RequestSetAudio, "RequestSetAudio", function(player, music: any, sfx: any, muted: any)
		SettingsService.setAudio(player, music, sfx, muted)
	end)

	RateLimiter.connect(Remotes.RequestSetLowEnd, "RequestSetLowEnd", function(player, value: any)
		SettingsService.setLowEnd(player, value)
	end)

	print("[SettingsService] Initialisiert")
end

return SettingsService
