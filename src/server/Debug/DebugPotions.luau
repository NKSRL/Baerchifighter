--!strict
-- DebugPotions.luau
-- ServerScriptService/Debug/DebugPotions.luau
--
-- Studio-Testbefehle: Traenke und Haendler-Sortiment (26.10.).
-- Registriert sich beim require in DebugRegistry.commands; geladen nur von
-- DebugService.init() und nur in Studio (nie im Live-Spiel).

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PotionConfig  = require(ReplicatedStorage.Config.PotionConfig)
local PotionRules   = require(ReplicatedStorage.Modules.PotionRules)
local PotionService = require(ServerScriptService.Services.PotionService)
local PlayerService = require(ServerScriptService.Services.PlayerService)
local DebugRegistry = require(script.Parent.DebugRegistry)

local commands = DebugRegistry.commands

-- Laufende Traenke mit Restzeit (Sekunden)
commands.potions = function(_player, data)
	local out = {}
	for _, view in PotionRules.view((data :: any).potions, os.time()) do
		table.insert(out, string.format("%s: %s x%.2f, %ds left", view.kind, view.potionId, view.multiplier, view.remaining))
	end
	return { active = out, bought = (data :: any).potions.bought }
end

-- Trank ohne Kosten anwenden. D:Invoke("potion", "SpeedII" [, sekunden]) /
-- D:Invoke("potion", "clear") traegt alle aus.
commands.potion = function(player, data, potionId: any, seconds: any)
	if potionId == "clear" then
		(data :: any).potions.active = {}
		PlayerService.markDirty(player)
		return commands.potions(player, data)
	end
	local id = tostring(potionId or "")
	-- Auch die Sorte reicht: "speed" -> kleiner Trank dieser Sorte
	if not PotionConfig.byId(id) then
		for _, def in PotionConfig.POTIONS do
			if def.kind == id and def.tier == 1 then id = def.id end
		end
	end
	if not PotionConfig.byId(id) then
		local ids = {}
		for _, def in PotionConfig.POTIONS do table.insert(ids, def.id) end
		return { error = "unknown potion: " .. id, potions = ids }
	end
	local ok, outcome = PotionService.grant(player, id, tonumber(seconds))
	return { ok = ok, outcome = outcome, state = commands.potions(player, PlayerService.getDataOrError(player)) }
end

-- Sortiment des Haendlers. D:Invoke("merchant") / D:Invoke("merchant", "next")
commands.merchant = function(player, _data, action: any)
	if action == "next" then
		PotionService.debugShiftWindow(1)
	end
	local view = PotionService.debugView(player)
	if not view then return { error = "no view (data not loaded)" } end
	local offers = {}
	for _, offer in view.offers do
		table.insert(offers, string.format("%d. %s  %d coins  (%s)", offer.slot, offer.potionId, offer.price, offer.action))
	end
	return {
		window    = view.window,
		rotatesIn = view.rotatesIn,
		egg       = string.format("%s  %d coins (always)", view.eggType, view.eggPrice),
		offers    = offers,
		reference = PotionService.priceReference(PlayerService.getDataOrError(player)),
	}
end

return {}
