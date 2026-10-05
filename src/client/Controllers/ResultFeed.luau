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
local Loc     = require(ReplicatedStorage.Localization.Loc)

local Toast = require(script.Parent.Parent.UI.Toast)
-- HBB Paket 1: Meldungen nach FeedbackConfig verteilen (Icon/Moment/Toast)
local Notify        = require(script.Parent.Parent.UI.Notify)
local Feedback      = require(script.Parent.Parent.UI.Feedback)
local Moment        = require(script.Parent.Parent.UI.Moment)
local ReturnSummary = require(script.Parent.Parent.UI.ReturnSummary)
local Theme         = require(script.Parent.Parent.UI.Theme)

local ResultFeed = {}

function ResultFeed.init()
	Remotes.RecycleResultReceived.OnClientEvent:Connect(function(result: any)
		if typeof(result) ~= "table" then return end
		local typed = result :: Types.RecycleResult

		-- Gummies fliegen ueber den Datenstand (UI/Feedback), daher kein
		-- zweiter Weg fuer den neuen Pfad.
		Notify.emit("recycle_result", function()
			-- Zahlen formatiert Loc selbst (Trenner je nach Sprache)
			if typed.goldGummiesGained > 0 then
				Toast.success(Loc.t("msg.recycled_gold", { gummies = typed.gummiesGained, gold = typed.goldGummiesGained }))
			else
				Toast.success(Loc.t("msg.recycled", { gummies = typed.gummiesGained }))
			end
		end)
	end)

	Remotes.OfflineReportReceived.OnClientEvent:Connect(function(report: any)
		if typeof(report) ~= "table" then return end
		local typed = report :: Types.OfflineReport

		-- Kein Banner wenn nichts passiert ist: der Spieler war nur kurz weg
		-- oder die Lager waren schon voll.
		if typed.secondsAway <= 0 or typed.honeyGained <= 0 then return end

		Notify.emit("offline_honey", function()
			Toast.success(Loc.t("msg.offline_honey", {
				time  = Loc.formatDuration(typed.secondsAway),
				honey = typed.honeyGained,
			}))
		end, function()
			ReturnSummary.addHoney(typed.secondsAway, typed.honeyGained)
		end)
	end)

	Remotes.FeedResultReceived.OnClientEvent:Connect(function(result: any)
		if typeof(result) ~= "table" then return end
		local typed = result :: Types.FeedResult

		-- HBB Paket 1: die XP steigen als Zahl ueber dem Baerchi auf (der
		-- Autopilot fuettert still, dann kommt hier nur der Level-Up an).
		if (typed.xpGained or 0) > 0 then
			Notify.emit("feed", function() end, function()
				Feedback.gain("xp", typed.xpGained)
			end)
		end

		-- Jede Fuetterung als Text zu melden waere Dauerbeschuss — der HP- und
		-- der XP-Balken auf der Karte zeigen das ohnehin live. Nur der Level-Up
		-- ist ein Moment, den man nicht verpassen soll.
		if not typed.leveledUp then return end

		Notify.emit("level_up", function()
			Toast.success(Loc.t("msg.level_up", { level = typed.newLevel }))
		end, function()
			Feedback.gain("level", typed.newLevel)
		end)
	end)

	-- v14: ein Knoten im Ei-Baum ist frei geworden
	Remotes.EggTreeUnlocked.OnClientEvent:Connect(function(result: any)
		if typeof(result) ~= "table" or typeof(result.eggType) ~= "string" then return end
		local egg = Loc.name("egg." .. result.eggType .. ".name", result.eggType)
		Notify.emit("tree_unlocked", function()
			Toast.success(Loc.t("msg.tree_unlocked", { egg = egg }))
		end, function()
			Moment.show("unlock", Theme.COLORS.growth, "ui.moment.new")
		end)
	end)

	-- v14: Ei-Presse
	Remotes.EggPressResultReceived.OnClientEvent:Connect(function(result: any)
		if typeof(result) ~= "table" then return end
		local typed = result :: Types.EggPressResult
		-- Die Lagersumme sinkt beim Pressen (5 rein, 1 raus), die Erkennung am
		-- Datenstand sieht also keinen Gewinn: das neue Ei hier selbst zeigen.
		Notify.emit("egg_pressed", function()
			Toast.success(Loc.t("msg.pressed", {
				n    = typed.used,
				from = Loc.name("egg." .. typed.fromEgg .. ".name", typed.fromEgg),
				to   = Loc.name("egg." .. typed.toEgg .. ".name", typed.toEgg),
			}))
		end, function()
			Feedback.gain("eggs", 1)
		end)
	end)

	print("[ResultFeed] Initialisiert")
end

return ResultFeed
