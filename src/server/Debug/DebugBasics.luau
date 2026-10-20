--!strict
-- DebugBasics.luau
-- ServerScriptService/Debug/DebugBasics.luau
--
-- Studio-Testbefehle: Grundbefehle: Stand, Waehrung, Baerchis, Skills, Eier.
-- Registriert sich beim require in DebugRegistry.commands; geladen nur von
-- DebugService.init() und nur in Studio (nie im Live-Spiel).

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types            = require(ReplicatedStorage.Network.Types)
local EconomyConfig    = require(ReplicatedStorage.Config.EconomyConfig)
local BuildingBehavior = require(ReplicatedStorage.Config.BuildingBehavior)
local EggConfig        = require(ReplicatedStorage.Config.EggConfig)
local GiftService = require(game:GetService("ServerScriptService").Services.GiftService)
local BaerchiConfig    = require(ReplicatedStorage.Config.BaerchiConfig)
local BaerchiFactory   = require(ReplicatedStorage.Modules.BaerchiFactory)
local SkillConfig      = require(ReplicatedStorage.Config.SkillConfig)
local CombatCalculator = require(ReplicatedStorage.Modules.CombatCalculator)
local PlayerService  = require(ServerScriptService.Services.PlayerService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local EggService     = require(ServerScriptService.Services.EggService)
local MapService     = require(ServerScriptService.Services.MapService)
local DebugRegistry = require(script.Parent.DebugRegistry)

local commands = DebugRegistry.commands
local countBaerchis = DebugRegistry.countBaerchis

commands.info = function(player, data)
	local buildings: { [string]: number } = {}
	for id, building in data.island.buildings do
		buildings[id] = building.level
	end

	return {
		player       = player.Name,
		gummies      = data.gummies,
		goldGummies  = data.goldGummies,
		rebirthCount = data.rebirthCount,
		rebirthMult  = data.rebirthMult,
		baerchis     = countBaerchis(data),
		towers       = data.towers,
		towerProgress = data.island.towerProgress,
		buildings    = buildings,
		eggStock     = data.island.eggStock,
	}
end

-- Waehrung schenken. Ohne rebirthMult, du bekommst exakt die Zahl.
commands.give = function(player, _data, gummies: any, gold: any)
	EconomyService.awardGummiesFlat(player, tonumber(gummies) or 100000)
	EconomyService.awardGoldGummies(player, tonumber(gold) or 1000)
	return commands.info(player, PlayerService.getDataOrError(player))
end

-- Alle Baerchis als flache Liste (uid zum Weiterverwenden)
commands.list = function(_player, data)
	local out = {}
	for uid, baerchi in data.island.baerchis do
		table.insert(out, {
			uid      = uid,
			configId = baerchi.configId,
			rarity   = baerchi.rarity,
			level    = baerchi.level,
			xp       = baerchi.xp,
			fusion   = baerchi.isFusionResult,
			bonus    = baerchi.fusionBonus,

			-- v8: die zweite Fortschrittsachse. `charms` bewusst nur als Anzahl
			-- — die Detailwerte holt man sich ueber "charms <uid>", sonst wird
			-- die Liste in der Command Bar unlesbar.
			promo    = baerchi.promotionLevel or 0,
			stats    = baerchi.statLevels,
			charms   = #(baerchi.charms or {}),
			mutation = baerchi.mutation,
		})
	end
	table.sort(out, function(a, b) return a.uid < b.uid end)
	return out
end

-- Baerchi direkt erzeugen, ohne Ei.
--
-- Das dritte Argument setzt eine Mutation (siehe BaerchiConfig.MUTATIONS fuer
-- gueltige Namen: Gold/Diamond/Bloodrot/Celestial/Candy/Lava/Galaxy/Rainbow).
-- Ohne diesen Weg waeren Mutationen in Studio praktisch nicht testbar: die
-- Gesamtchance beim Schluepfen liegt bei 1.5%, die seltenste Stufe (Rainbow)
-- bei 0.0005% — man muesste also im Schnitt 200'000 Eier ausbrueten.
--   D:Invoke("add", "RedBaerchi", 10)              -- normal
--   D:Invoke("add", "RedBaerchi", 10, "Rainbow")   -- mit Mutation
commands.add = function(player, data, configId: any, level: any, mutation: any)
	local mutationId: any = nil
	if typeof(mutation) == "string" and BaerchiConfig.MUTATIONS[mutation :: any] then
		mutationId = mutation
	end

	local baerchi = BaerchiFactory.create(tostring(configId), {
		level    = tonumber(level) or 1,
		mutation = mutationId,
	})
	if not baerchi then
		return { error = "Unbekannter configId: " .. tostring(configId) }
	end

	data.island.baerchis[baerchi.uid] = baerchi
	PlayerService.markDirty(player)

	return {
		uid      = baerchi.uid,
		configId = baerchi.configId,
		rarity   = baerchi.rarity,
		level    = baerchi.level,
		mutation = baerchi.mutation,
	}
end

-- Faehigkeit eines Baerchis tauschen (zum Testen der Shows).
-- uid "equipped" (oder leer) = der ausgeruestete Baerchi.
--   D:Invoke("skill", "equipped", "OmegaStrike")
commands.skill = function(player, data, uid: any, skillId: any)
	local id = if uid == nil or uid == "equipped" then data.island.equippedUid else tostring(uid)
	local baerchi = if id then data.island.baerchis[id] else nil
	if not baerchi then
		return { error = "Kein Baerchi mit uid " .. tostring(id) }
	end
	if not SkillConfig.getById(tostring(skillId)) then
		return { error = "Unbekannte Faehigkeit: " .. tostring(skillId) }
	end
	local before = baerchi.skillId
	baerchi.skillId = tostring(skillId) :: any
	PlayerService.markDirty(player)
	return { uid = baerchi.uid, configId = baerchi.configId, vorher = before, jetzt = baerchi.skillId }
end

-- Die Kampfwerte eines Baerchis so, wie der Kampf sie sieht. Praktisch, um
-- Promotion, Stat-Stufen, Charms und Mutation gegeneinander nachzurechnen.
commands.stats = function(_player, data, uid: any)
	local baerchi = data.island.baerchis[tostring(uid)]
	if not baerchi then
		return { error = "Baerchi nicht gefunden: " .. tostring(uid) }
	end

	local def = BaerchiConfig.getById(baerchi.configId)
	if not def then
		return { error = "Unbekannter configId: " .. baerchi.configId }
	end

	local stats = CombatCalculator.getEffectiveStats(baerchi, def.baseStats)

	return {
		configId = baerchi.configId,
		level    = baerchi.level,
		mutation = baerchi.mutation,
		promo    = baerchi.promotionLevel or 0,
		maxHp    = stats.maxHp,
		atk      = stats.atk,
		spd      = stats.spd,
		pwrProzent = math.floor(stats.pwr * 100 + 0.5),
		skill    = stats.skillId,
	}
end

-- Gebaeude-Level direkt setzen (umgeht die Kosten)
commands.building = function(player, data, buildingId: any, level: any)
	local building = data.island.buildings[buildingId]
	if not building then
		return { error = "Unbekanntes Gebaeude: " .. tostring(buildingId) }
	end

	-- clampBuildingLevel rundet mit ab: ohne das landete eine 5.5 aus der
	-- Command Bar als Kommazahl in den Daten und jedes spaetere
	-- string.format("%d", level) wuerde daran scheitern.
	building.level = EconomyConfig.clampBuildingLevel(tonumber(level) or 1)
	MapService.updateBuildingLevel(player, buildingId, building.level)
	PlayerService.markDirty(player)

	return { building = buildingId, level = building.level, look = BuildingBehavior.getLook(building.level) }
end

-- v12: Ei ins Lager legen und sofort oeffnen (es gibt keine Brut mehr)
commands.hatch = function(player, data, eggType: any)
	local egg = tostring(eggType or "BasicEgg")
	if not EggConfig.data[egg :: Types.EggType] then
		return { error = "Unbekannter Egg-Typ: " .. egg }
	end

	data.island.eggStock[egg :: Types.EggType] = (data.island.eggStock[egg :: Types.EggType] or 0) + 1
	local result = EggService.openEgg(player, egg :: Types.EggType)
	if not result then
		return { error = "Oeffnen fehlgeschlagen" }
	end

	return {
		configId = result.baerchi.configId,
		rarity   = result.baerchi.rarity,
		mutation = result.baerchi.mutation,
		neu      = result.isNew,
	}
end

-- Ei verschenken (auch an einen anderen Spieler, im echten Spiel): kommt beim naechsten Laden
-- bzw. innerhalb von 30 s an, wenn er online ist.
--   D:Invoke("gift", 1542221687, "OmegaEgg", 1)
commands.gift = function(player, data, userId: any, eggType: any, count: any)
	local ok, text = GiftService.enqueue(tonumber(userId) or 0, tostring(eggType or "OmegaEgg"), tonumber(count) or 1)
	if not ok then return { error = text } end
	return { ok = text }
end

-- v12: Eier ins Lager legen, ohne sie zu oeffnen (fuer Tests im Ei-Menue)
commands.egg = function(player, data, eggType: any, count: any)
	local egg = tostring(eggType or "BasicEgg")
	if not EggConfig.data[egg :: Types.EggType] then
		return { error = "Unbekannter Egg-Typ: " .. egg }
	end

	local amount = math.clamp(tonumber(count) or 1, 1, 100)
	data.island.eggStock[egg :: Types.EggType] = (data.island.eggStock[egg :: Types.EggType] or 0) + amount
	PlayerService.markDirty(player)
	return { lager = data.island.eggStock }
end

return {}
