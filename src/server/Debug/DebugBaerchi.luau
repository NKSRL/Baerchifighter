--!strict
-- DebugBaerchi.luau
-- ServerScriptService/Debug/DebugBaerchi.luau
--
-- Studio-Testbefehle: Baerchi-Pflege: Honig, Fuettern, Fusion, Charms.
-- Registriert sich beim require in DebugRegistry.commands; geladen nur von
-- DebugService.init() und nur in Studio (nie im Live-Spiel).

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BuildingBehavior = require(ReplicatedStorage.Config.BuildingBehavior)
local CharmConfig      = require(ReplicatedStorage.Config.CharmConfig)
local PlayerService  = require(ServerScriptService.Services.PlayerService)
local FusionService  = require(ServerScriptService.Services.FusionService)
local HoneyService   = require(ServerScriptService.Services.HoneyService)
local PromotionService          = require(ServerScriptService.Services.PromotionService)
local CharmService              = require(ServerScriptService.Services.CharmService)
local DebugRegistry = require(script.Parent.DebugRegistry)

local commands = DebugRegistry.commands

commands.honey = function(player, data)
	local filled: { [string]: number } = {}

	for _, building in data.island.buildings do
		-- Lager DIESES Gebaeudes auf DIESEM Level: der Bienenstock fasst seit
		-- v7 mehr als die anderen beiden.
		building.honey          = BuildingBehavior.getCapacity(building.id, building.level)
		building.lastProducedAt = os.time()
		filled[building.id]     = building.honey
	end

	PlayerService.markDirty(player)
	return { honey = filled }
end

-- Einen Baerchi fuettern (heilt + gibt XP), so oft wie angegeben
commands.feed = function(player, _data, uid: any, times: any)
	local count = math.clamp(tonumber(times) or 1, 1, 100)

	for _ = 1, count do
		HoneyService.feed(player, tostring(uid))
	end

	return commands.list(player, PlayerService.getDataOrError(player))
end

-- Fusion. Die beiden letzten Argumente sind der Sperr-Schritt aus dem
-- Fusions-Menue (siehe FusionService, Regel C) und duerfen weggelassen werden —
-- dann laeuft alles automatisch.
--   D:Invoke("fuse", uidA, uidB)                   -- alles automatisch
--   D:Invoke("fuse", uidA, uidB, "ability", "B")   -- Skill kommt von B
commands.fuse = function(player, _data, uidA: any, uidB: any, lockedProperty: any, lockedFrom: any)
	local property = if lockedProperty ~= nil then tostring(lockedProperty) else nil
	local from     = if lockedFrom ~= nil then tostring(lockedFrom) else nil

	FusionService.fuse(player, tostring(uidA), tostring(uidB), property :: any, from :: any)
	return commands.list(player, PlayerService.getDataOrError(player))
end

--------------------------------------------------------------------------------
-- v8: Promotion, Charms, Event-Teilnahme
--------------------------------------------------------------------------------

-- Befoerdern. Legt die noetigen Duplikate NICHT selbst an — wer testen will,
-- ruft vorher mehrfach "add <configId>" auf. Genau so merkt man, ob die
-- Material-Pruefung tut, was sie soll.
commands.promote = function(player, _data, uid: any)
	PromotionService.promote(player, tostring(uid))
	return commands.list(player, PlayerService.getDataOrError(player))
end

-- Charms wuerfeln. Kostet echte GoldGummies — vorher "give 0 100000".
commands.roll = function(player, _data, uid: any, times: any)
	CharmService.rollCharms(player, tostring(uid), tonumber(times) or 1)
	return commands.charms(player, PlayerService.getDataOrError(player), uid)
end

-- Alle acht Slots eines Baerchis im Klartext.
commands.charms = function(_player, data, uid: any)
	local baerchi = data.island.baerchis[tostring(uid)]
	if not baerchi then
		return { error = "Baerchi nicht gefunden: " .. tostring(uid) }
	end

	local bySlot: { [number]: any } = {}
	for _, charm in baerchi.charms or {} do
		bySlot[charm.slot] = charm
	end

	local out = {}
	for slot = 1, CharmConfig.SLOT_COUNT do
		local charm = bySlot[slot]
		out[slot] = {
			slot     = CharmConfig.SLOT_NUMERALS[slot],
			offen    = CharmConfig.isSlotUnlocked(slot, baerchi.promotionLevel or 0),
			abPromo  = CharmConfig.getUnlockPromotion(slot),
			rarity   = if charm then charm.rarity else nil,
			effekt   = if charm then CharmConfig.describe(charm) else nil,
			gesperrt = if charm then charm.locked else nil,
		}
	end

	return { promotion = baerchi.promotionLevel or 0, slots = out }
end

-- Einen Charm-Slot sperren/freigeben.
commands.lock = function(player, _data, uid: any, slot: any)
	CharmService.toggleLock(player, tostring(uid), tonumber(slot) or 1)
	return commands.charms(player, PlayerService.getDataOrError(player), uid)
end

return {}
