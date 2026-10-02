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

function SettingsService.init()
	RateLimiter.connect(Remotes.RequestSetLanguage, "RequestSetLanguage", function(player, language: any)
		SettingsService.setLanguage(player, language)
	end)

	print("[SettingsService] Initialisiert")
end

return SettingsService
