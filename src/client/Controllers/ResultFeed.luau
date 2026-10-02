--!strict
-- ResultFeed.luau
-- StarterPlayerScripts/Controllers/ResultFeed.luau
--
-- Einzige Zustaendigkeit:
--   - Server-Ergebnisse die nur eine kurze Meldung brauchen in Toasts uebersetzen
--
-- Hier landen genau die Events ohne eigene Oberflaeche:
--   RecycleResultReceived  — der Baerchi ist weg, es zaehlt nur der Erloes
--   OfflineReportReceived  — einmal beim Join, wenn die Gebaeude weiterliefen
--   FeedResultReceived     — nur der Level-Up ist eine Meldung wert; die
--                            Heilung sieht man direkt am HP-Balken der Karte
--
-- Alles mit eigener Anzeige haengt bewusst NICHT hier, sondern im jeweiligen
-- Panel: Hatch-Reveal in HatchPanel, Kampf-Wiedergabe in CombatPanel,
-- Fusions-Ergebnis in FusionPanel, Rebirth-Bestaetigung in RebirthDialog.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types   = require(ReplicatedStorage.Network.Types)
local Remotes = require(ReplicatedStorage.Network.Remotes)

local Theme = require(script.Parent.Parent.UI.Theme)
local Toast = require(script.Parent.Parent.UI.Toast)

local ResultFeed = {}

function ResultFeed.init()
	Remotes.RecycleResultReceived.OnClientEvent:Connect(function(result: any)
		if typeof(result) ~= "table" then return end
		local typed = result :: Types.RecycleResult

		local message = "Verwertet: +" .. Theme.formatNumber(typed.gummiesGained) .. " Gummies"
		if typed.goldGummiesGained > 0 then
			message ..= "  und  +" .. Theme.formatNumber(typed.goldGummiesGained) .. " GoldGummies"
		end

		Toast.success(message)
	end)

	Remotes.OfflineReportReceived.OnClientEvent:Connect(function(report: any)
		if typeof(report) ~= "table" then return end
		local typed = report :: Types.OfflineReport

		-- Kein Banner wenn nichts passiert ist: der Spieler war nur kurz weg
		-- oder die Lager waren schon voll.
		if typed.secondsAway <= 0 or typed.honeyGained <= 0 then return end

		Toast.success(string.format(
			"Waehrend du weg warst (%s): +%d Honig",
			Theme.formatDuration(typed.secondsAway),
			typed.honeyGained
		))
	end)

	Remotes.FeedResultReceived.OnClientEvent:Connect(function(result: any)
		if typeof(result) ~= "table" then return end
		local typed = result :: Types.FeedResult

		-- Jede Fuetterung zu melden waere Dauerbeschuss — der HP- und der
		-- XP-Balken auf der Karte zeigen das ohnehin live. Nur der Level-Up
		-- ist ein Moment, den man nicht verpassen soll.
		if not typed.leveledUp then return end

		Toast.success("Level Up!  Jetzt Level " .. typed.newLevel)
	end)

	print("[ResultFeed] Initialisiert")
end

return ResultFeed
