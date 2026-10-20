--!strict
-- RecycleService.luau
-- ServerScriptService/Services/RecycleService.luau
--
-- Einzige Zustaendigkeit:
--   - Einen Baerchi endgueltig verwerten und dafuer Gummies gutschreiben
--
-- Rueckgabe-Formel (alle Zahlen aus EconomyConfig):
--   wert    = getBaerchiBaseValue(rarity, level)   -- Rarity-Basiswert * Level-Bonus
--   gummies = floor(wert * RECYCLE_RETURN)
--
-- Seit v4 gibt es kein Recycler-Gebaeude mehr (die Gebaeude produzieren nur
-- noch Honig): die Rueckgabequote ist fest, und die frueher levelabhaengige
-- GoldGummy-Chance entfaellt. GoldGummies kommen jetzt aus PIT-Meilensteinen.
--
-- Bewusst ueber EconomyService.awardGummiesFlat: der Recycler gibt einen
-- Gegenwert zurueck, kein Einkommen — rebirthMult darf hier nicht greifen,
-- sonst wird Kaufen-und-Verwerten zur Gummy-Druckerei.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types         = require(ReplicatedStorage.Network.Types)
local Remotes       = require(ReplicatedStorage.Network.Remotes)
local Loc           = require(ReplicatedStorage.Localization.Loc)
local EconomyConfig = require(ReplicatedStorage.Config.EconomyConfig)

local PlayerService  = require(ServerScriptService.Services.PlayerService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local RateLimiter    = require(ServerScriptService.Util.RateLimiter)

local RecycleService = {}

local function fail(player: Player, reason: Types.LocMsg?)
	Remotes.ActionFailed:FireClient(player, "RequestRecycleBaerchi", reason or Loc.msg("err.unknown"))
end

-- Wie viele Gummies dieser Baerchi beim Verwerten bringt.
-- Oeffentlich, damit die UI denselben Wert anzeigt den der Server auszahlt.
function RecycleService.getRecycleValue(baerchi: Types.Baerchi): number
	local baseValue = EconomyConfig.getBaerchiBaseValue(baerchi.rarity, baerchi.level)
	return math.floor(baseValue * EconomyConfig.RECYCLE_RETURN)
end

function RecycleService.recycle(player: Player, baerchiUid: string)
	local data = PlayerService.getData(player)
	if not data then return end

	local baerchi = data.island.baerchis[baerchiUid]
	if not baerchi then
		fail(player, Loc.msg("err.baerchi_not_found"))
		return
	end

	-- Pet-Regel seit v12 (Ei-Baum-Konzept, Abschnitt 5a): der AUSGERUESTETE
	-- Baerchi kann nie verwertet werden. Er ist der, der Eier legt — und weil
	-- Eier nicht mehr kaufbar sind, wuerde ein Spieler ohne ihn im
	-- schlimmsten Fall ohne Nachschub dastehen. Tauschen geht ueber
	-- "Ausruesten" bei einem anderen Baerchi. Diese Pruefung ist die
	-- eigentliche Regel; das Ausgrauen im BaerchiPanel ist nur Komfort.
	if data.island.equippedUid == baerchiUid then
		fail(player, Loc.msg("err.recycle_equipped"))
		return
	end

	local gummies = RecycleService.getRecycleValue(baerchi)

	-- Baerchi entfernen bevor gutgeschrieben wird: awardGummiesFlat loest
	-- markDirty aus, der Client soll die Liste schon ohne ihn sehen.
	local configId = baerchi.configId
	local rarity   = baerchi.rarity

	data.island.baerchis[baerchiUid] = nil
	data.stats.totalRecycled += 1

	local gummiesGained = EconomyService.awardGummiesFlat(player, gummies)

	local result: Types.RecycleResult = {
		consumedUid       = baerchiUid,
		gummiesGained     = gummiesGained,
		goldGummiesGained = 0,   -- GoldGummies gibt es nur noch aus PIT-Meilensteinen
	}

	Remotes.RecycleResultReceived:FireClient(player, result)
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)

	print(
		"[RecycleService]", player.Name,
		"| verwertet:", configId, "(", rarity, ")",
		"| +", gummiesGained, "Gummies"
	)
end

function RecycleService.init()
	RateLimiter.connect(Remotes.RequestRecycleBaerchi, "RequestRecycleBaerchi", function(player, baerchiUid: any)
		if typeof(baerchiUid) ~= "string" then return end
		RecycleService.recycle(player, baerchiUid)
	end)

	print("[RecycleService] Initialisiert")
end

return RecycleService
