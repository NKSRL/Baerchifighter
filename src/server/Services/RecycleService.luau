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
local EconomyConfig = require(ReplicatedStorage.Config.EconomyConfig)

local PlayerService  = require(ServerScriptService.Services.PlayerService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local IslandService  = require(ServerScriptService.Services.IslandService)
local ActivityLock   = require(ServerScriptService.Util.ActivityLock)
local RateLimiter    = require(ServerScriptService.Util.RateLimiter)

local RecycleService = {}

local function fail(player: Player, reason: string)
	Remotes.ActionFailed:FireClient(player, "RequestRecycleBaerchi", reason)
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
		fail(player, "Baerchi nicht gefunden")
		return
	end

	-- Nur der AUSGERUESTETE Baerchi steht sichtbar in der Welt und kann
	-- deshalb mitten in einer Bewegung stecken (Kampf-Lauf in die Arena oder
	-- Weg zum Honig-Teich). Ihn dabei zu verwerten wuerde die laufende Figur
	-- einfach unter der Animation wegziehen — kein Absturz (FigureWalker und
	-- PitArenaService pruefen das), aber ein sichtbares Verschwinden mitten im
	-- Schritt statt eines sauberen Abbruchs.
	--
	-- Ein Baerchi aus dem Inventar hat keine Figur in der Welt: der darf
	-- jederzeit verwertet werden, auch waehrend der ausgeruestete unterwegs
	-- ist. Deshalb die uid-Pruefung und nicht nur ActivityLock.isFree.
	if data.island.equippedUid == baerchiUid and not ActivityLock.isFree(player) then
		fail(player, "Der Baerchi ist gerade unterwegs — kurz warten")
		return
	end

	local gummies = RecycleService.getRecycleValue(baerchi)

	-- Baerchi entfernen bevor gutgeschrieben wird: awardGummiesFlat loest
	-- markDirty aus, der Client soll die Liste schon ohne ihn sehen.
	local configId = baerchi.configId
	local rarity   = baerchi.rarity
	local wasEquipped = data.island.equippedUid == baerchiUid

	data.island.baerchis[baerchiUid] = nil
	data.stats.totalRecycled += 1

	-- War er ausgeruestet, uebernimmt automatisch ein anderer seinen Platz
	-- (falls noch welche da sind) — sonst bliebe der Plot leer, obwohl
	-- vielleicht noch Baerchis im Inventar sind.
	if wasEquipped then
		data.island.equippedUid = nil
		IslandService.autoEquipIfNone(data)
	end

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
