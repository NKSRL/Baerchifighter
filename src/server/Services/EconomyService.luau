--!strict
-- EconomyService.luau
-- ServerScriptService/Services/EconomyService.luau
--
-- Einzige Zustaendigkeit:
--   - Gummies und GoldGummies aendern
--   - Alle Transaktionen validieren (nie ins Minus gehen)
--   - Kosten-Transaktionen fuer Gebaeude-Upgrades (v15: PIT-Level entfallen)
--   - Kein anderer Service aendert Waehrungen direkt
--
-- rebirthMult wird GENAU HIER angewendet (awardGummies) und nirgendwo sonst.
-- Wer einen Betrag schon multipliziert hat, benutzt awardGummiesFlat.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local BuildingBehavior = require(ReplicatedStorage.Config.BuildingBehavior)
local Types            = require(ReplicatedStorage.Network.Types)
local Loc              = require(ReplicatedStorage.Localization.Loc)

local PlayerService = require(ServerScriptService.Services.PlayerService)

local EconomyService = {}

-- Interne Hilfsfunktion — validiert und bucht ab
local function charge(player: Player, field: "gummies" | "goldGummies", amount: number): (boolean, Types.LocMsg?)
	assert(amount > 0, "[EconomyService] Betrag muss positiv sein")

	local data = PlayerService.getData(player)
	if not data then return false, Loc.msg("err.player_not_loaded") end

	local wallet = data :: any
	if wallet[field] < amount then
		return false, Loc.msg(if field == "gummies" then "err.not_enough_gummies" else "err.not_enough_gold_gummies", { have = wallet[field], need = amount })
	end

	wallet[field] -= amount
	PlayerService.markDirty(player)
	return true
end

local function credit(player: Player, field: "gummies" | "goldGummies", amount: number)
	assert(amount > 0, "[EconomyService] Betrag muss positiv sein")

	local data = PlayerService.getData(player)
	if not data then return end

	local wallet = data :: any
	wallet[field] += amount
	PlayerService.markDirty(player)
end

-- ============================================================
-- Oeffentliche API — Waehrung
-- ============================================================

function EconomyService.spendGummies(player: Player, amount: number): (boolean, Types.LocMsg?)
	return charge(player, "gummies", amount)
end

function EconomyService.spendGoldGummies(player: Player, amount: number): (boolean, Types.LocMsg?)
	return charge(player, "goldGummies", amount)
end

-- Gutschrift MIT rebirthMult. Gibt den tatsaechlich gutgeschriebenen
-- Betrag zurueck — Aufrufer melden diesen Wert an den Client, nicht den Basiswert.
function EconomyService.awardGummies(player: Player, baseAmount: number): number
	local data = PlayerService.getData(player)
	if not data then return 0 end
	if baseAmount <= 0 then return 0 end

	local final = math.max(1, math.floor(baseAmount * data.rebirthMult))
	credit(player, "gummies", final)

	data.stats.totalGummiesEarned += final
	return final
end

-- Gutschrift OHNE rebirthMult.
-- Fuer Betraege die kein Einkommen sind, sondern ein Gegenwert:
-- Recycling gibt den Wert eines Baerchis zurueck — ein Rebirth-Multiplikator
-- darauf wuerde eine Endlosschleife aus Kaufen und Verwerten oeffnen.
function EconomyService.awardGummiesFlat(player: Player, amount: number): number
	if amount <= 0 then return 0 end

	local data = PlayerService.getData(player)
	if not data then return 0 end

	local final = math.floor(amount)
	credit(player, "gummies", final)

	data.stats.totalGummiesEarned += final
	return final
end

function EconomyService.awardGoldGummies(player: Player, amount: number): number
	if amount <= 0 then return 0 end

	local final = math.floor(amount)
	if final <= 0 then return 0 end

	credit(player, "goldGummies", final)
	return final
end

-- Setzt Gummies fest auf einen Wert statt einen Betrag zu verrechnen — nur
-- fuer den Rebirth-Reset gedacht, wo "danach hast du genau X" gemeint ist,
-- nicht "zieh X ab" oder "gib X dazu". Bleibt trotzdem die einzige Stelle,
-- die das Feld anfasst: RebirthService darf `data.gummies` selbst nicht
-- direkt schreiben.
function EconomyService.resetGummies(player: Player, amount: number)
	local data = PlayerService.getData(player)
	if not data then return end

	data.gummies = math.max(0, amount)
	PlayerService.markDirty(player)
end

-- ============================================================
-- Oeffentliche API — Kosten-Transaktionen
-- ============================================================

-- Gebaeude upgraden (prueft Kosten, zieht ab, erhoeht Level)
function EconomyService.upgradeBuilding(player: Player, buildingId: Types.BuildingId): (boolean, Types.LocMsg?)
	local data = PlayerService.getData(player)
	if not data then return false, Loc.msg("err.player_not_loaded") end

	local building = data.island.buildings[buildingId]
	if not building then return false, Loc.msg("err.building_missing") end

	local nextLevel  = building.level + 1
	local upgradeDef = BuildingBehavior.getUpgrade(buildingId, nextLevel)
	if not upgradeDef then return false, Loc.msg("err.max_level") end

	-- Erst pruefen, dann buchen: sonst kann der erste Teilbetrag abgezogen
	-- werden obwohl der zweite scheitert.
	if upgradeDef.costGummies > 0 and data.gummies < upgradeDef.costGummies then
		return false, Loc.msg("err.not_enough_gummies", { have = data.gummies, need = upgradeDef.costGummies })
	end
	if upgradeDef.costGoldGummies > 0 and data.goldGummies < upgradeDef.costGoldGummies then
		return false, Loc.msg("err.not_enough_gold_gummies", { have = data.goldGummies, need = upgradeDef.costGoldGummies })
	end

	if upgradeDef.costGummies > 0 then
		local ok, reason = EconomyService.spendGummies(player, upgradeDef.costGummies)
		if not ok then return false, reason end
	end
	if upgradeDef.costGoldGummies > 0 then
		local ok, reason = EconomyService.spendGoldGummies(player, upgradeDef.costGoldGummies)
		if not ok then return false, reason end
	end

	building.level = nextLevel
	PlayerService.markDirty(player)

	return true
end

function EconomyService.init()
	print("[EconomyService] Initialisiert")
end

return EconomyService
