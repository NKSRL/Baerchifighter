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

	-- Sammel-Update 05.10. (Paket 7): Index-Belohnung abgeholt
	Remotes.IndexRewardReceived.OnClientEvent:Connect(function(result: any)
		if typeof(result) ~= "table" or typeof(result.rewardId) ~= "string" then return end
		local typed = result :: Types.IndexRewardResult
		local parts: { string } = {}
		if typed.eggs > 0 and typed.eggType then
			table.insert(parts, string.format("+%d %s", typed.eggs, Loc.name("egg." .. typed.eggType .. ".name", typed.eggType)))
		end
		if typed.gummies > 0 then table.insert(parts, "+" .. Loc.formatNumber(typed.gummies) .. " Gummies") end
		if typed.goldGummies > 0 then table.insert(parts, "+" .. Loc.formatNumber(typed.goldGummies) .. " GoldGummies") end
		if typed.blueprints > 0 then table.insert(parts, Loc.t("ui.index_reward.blueprint", { n = typed.blueprints })) end
		if typed.incubatorSlots > 0 then table.insert(parts, Loc.t("ui.index_reward.slot", { n = typed.incubatorSlots })) end
		Notify.emit("index_reward", function()
			Toast.success(Loc.t("msg.index_reward", { text = table.concat(parts, "  ·  ") }))
		end, function()
			Moment.show("milestone", Theme.COLORS.goldGummy, "ui.moment.milestone")
		end)
	end)

	-- Sammel-Update 05.10. (Paket 6.2): besonderer Meilenstein (Ascensions-Eier)
	Remotes.SpecialMilestoneReceived.OnClientEvent:Connect(function(result: any)
		if typeof(result) ~= "table" or typeof(result.id) ~= "string" then return end
		local typed = result :: Types.SpecialMilestoneResult
		local n, eggType = 0, "AscensionEgg"
		for _, entry in typed.eggs do
			n += entry.count
			eggType = entry.eggType
		end
		Notify.emit("special_milestone", function()
			Toast.success(Loc.t("msg.special_milestone", {
				name = Loc.t("milestone." .. typed.id),
				n    = n,
				egg  = Loc.name("egg." .. eggType .. ".name", eggType),
			}))
		end, function()
			Moment.show("milestone", Theme.COLORS.goldGummy, "ui.moment.milestone")
		end)
	end)

	-- Sammel-Update 05.10. (Paket 8, Umbau): Inkubator — kurze Bestaetigung
	-- beim Einsetzen/Herausnehmen/Abholen/Ausbauen
	Remotes.IncubatorChanged.OnClientEvent:Connect(function(info: any)
		if typeof(info) ~= "table" then return end
		local kind = info.kind
		if kind == "insert" or kind == "remove" or kind == "collect" or kind == "upgrade" then
			local count = if typeof(info.count) == "number" then info.count else 0
			Notify.emit("incubator", function()
				Toast.info(Loc.t("msg.incubator." .. kind, { n = count }))
			end)
		end
	end)

	print("[ResultFeed] Initialisiert")
end

return ResultFeed
