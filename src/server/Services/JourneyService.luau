--!strict
-- JourneyService.luau
-- ServerScriptService/Services/JourneyService.luau
--
-- Einzige Zustaendigkeit:
--   - Die "Reise" (P3, Tower-Tutorial): Etappen-Belohnungen genau einmal auszahlen,
--     Etappen ueberspringen, die Leiste aus-/einblenden.
--
-- Der Server prueft ALLES aus dem echten Spielstand (Modules/OnboardingRules): ein Client kann
-- nur eine Etappe nennen; ob sie erfuellt und noch nicht abgeholt ist, entscheidet der Server.
-- Erst wird "abgeholt" gesetzt, dann ausgezahlt (Doppelklick/Spoof findet "schon abgeholt" vor).

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes          = require(ReplicatedStorage.Network.Remotes)
local FeatureFlags     = require(ReplicatedStorage.Config.FeatureFlags)
local OnboardingConfig = require(ReplicatedStorage.Config.OnboardingConfig)
local OnboardingRules  = require(ReplicatedStorage.Modules.OnboardingRules)

local PlayerService  = require(ServerScriptService.Services.PlayerService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local RateLimiter    = require(ServerScriptService.Util.RateLimiter)

local JourneyService = {}

local function stageById(id: string): OnboardingConfig.Stage?
	for _, stage in OnboardingConfig.STAGES do
		if stage.id == id then return stage end
	end
	return nil
end

-- Verarbeitet eine Anfrage. Gibt (ok, grund) zurueck; testbar ohne Remote.
function JourneyService.handle(player: Player, action: any, stageId: any): (boolean, string?)
	if not FeatureFlags.isOn("ONBOARDING_V2") then return false, "flag" end
	local data = PlayerService.getData(player)
	if not data then return false, "nodata" end
	local journey = OnboardingRules.sanitize((data :: any).journey)
	;(data :: any).journey = journey

	if action == "hide" or action == "show" then
		journey.hidden = (action == "hide")
		PlayerService.markDirty(player)
		return true, nil
	end

	if action == "skip" then
		if not OnboardingRules.canSkip(stageId, journey) then return false, "skip" end
		journey.skipped[stageId :: string] = true
		PlayerService.markDirty(player)
		return true, nil
	end

	if action == "claim" then
		if not OnboardingRules.canClaim(stageId, data :: any, journey) then return false, "claim" end
		local stage = stageById(stageId :: string)
		if not stage then return false, "unknown" end
		-- erst markieren, dann auszahlen
		journey.claimed[stage.id] = true
		journey.skipped[stage.id] = nil
		local r = stage.reward
		if (r.goldGummies or 0) > 0 then EconomyService.awardGoldGummies(player, r.goldGummies :: number) end
		if (r.gummies or 0) > 0 then EconomyService.awardGummiesFlat(player, r.gummies :: number) end
		PlayerService.markDirty(player)
		PlayerService.saveNow(player)
		print("[JourneyService]", player.Name, "| Etappe", stage.id, "| Gold:", r.goldGummies or 0)
		return true, nil
	end

	return false, "action"
end

function JourneyService.init()
	RateLimiter.connect(Remotes.RequestJourney, "RequestJourney", function(player, action, stageId)
		JourneyService.handle(player, action, stageId)
	end)
	print("[JourneyService] Initialisiert |", OnboardingConfig.MAX_STAGE, "Etappen")
end

return JourneyService
