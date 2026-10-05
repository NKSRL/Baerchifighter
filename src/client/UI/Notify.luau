--!strict
-- Notify.luau
-- StarterPlayerScripts/UI/Notify.luau
--
-- Einzige Zustaendigkeit:
--   - Einen Meldungs-Anlass nach FeedbackConfig auf Toast, Icon, Moment
--     oder nichts verteilen
--
-- Kontext: HBB Paket 1. Jede Stelle, die frueher direkt einen Toast zeigte,
-- ruft jetzt:
--   Notify.emit("schluessel", function() Toast.success(...) end, function(class) ... end)
-- Der erste Rueckruf ist der alte Weg (Toast), der zweite der neue. Welcher
-- laeuft, entscheiden FeatureFlags.UI_V2_FEEDBACK und die Klasse des
-- Schluessels. So steht die Entscheidung an EINER Stelle, und der alte Weg
-- bleibt Wort fuer Wort erhalten (Flag aus = Verhalten wie vorher).
--
-- Die Toast-API selbst bleibt unveraendert.

local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FeedbackConfig = require(ReplicatedStorage.Config.FeedbackConfig)
local FeatureFlags   = require(ReplicatedStorage.Config.FeatureFlags)

local Notify = {}

-- legacy: der alte Toast. modern: Icon/Moment (bekommt die Klasse). Fehlt
-- `modern`, passiert bei ICON/MOMENT nichts Zusaetzliches — z.B. weil
-- UI/Feedback Waehrungen und Eier schon selbst am Datenstand erkennt.
function Notify.emit(key: string, legacy: () -> (), modern: ((FeedbackConfig.Class) -> ())?)
	if not FeatureFlags.isOn("UI_V2_FEEDBACK") then
		legacy()
		return
	end

	local class = FeedbackConfig.classOf(key)
	if not class then
		-- Nicht klassifiziert: lieber der alte Text als gar nichts. In Studio
		-- laut, damit die Tabelle nachgezogen wird.
		if RunService:IsStudio() then
			warn("[Notify] Schluessel fehlt in FeedbackConfig:", key)
		end
		legacy()
		return
	end

	if class == "TOAST" then
		legacy()
	elseif class == "NONE" then
		return
	elseif modern then
		modern(class)
	end
end

return Notify
