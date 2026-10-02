--!strict
-- CharmService.luau
-- ServerScriptService/Services/CharmService.luau
--
-- Einzige Zustaendigkeit:
--   - Battle-Charms eines Baerchis neu wuerfeln
--   - Einzelne Slots gegen erneutes Wuerfeln sperren/freigeben
--
-- ============================================================
-- WURF-REGEL (verbindlich, hier dokumentiert)
-- ============================================================
--   1. Ein Wurf betrifft ALLE Slots, die freigeschaltet UND nicht gesperrt
--      sind — genau wie in der Vorlage ("rerolls every slot you have not
--      locked"). Deshalb kostet ein WURF, nicht ein Slot.
--   2. Jeder betroffene Slot wuerfelt zweimal unabhaengig: erst eine Rarity
--      (CharmConfig.RARITY_ODDS), dann einen Stat-Typ (CharmConfig.STAT_POOL).
--      Ein Slot ist NICHT an einen Stat-Typ gebunden.
--   3. Freigeschaltet wird ueber den Promotions-Stand des Baerchis
--      (CharmConfig.SLOT_UNLOCK_PROMOTION). Ohne Promotion ist genau Slot I
--      offen.
--   4. Ein Wurf kostet CharmConfig.ROLL_COST_GOLD_GUMMIES GoldGummies.
--      KEINE eigene Waehrung — "Charm Dust" gibt es in Baerchi Fighter
--      bewusst nicht (siehe CharmConfig, Kopf-Kommentar).
--   5. Sind ALLE freigeschalteten Slots gesperrt, wird der Wurf abgelehnt
--      statt Geld fuer nichts zu nehmen.
--
-- ============================================================
-- WARUM "AUTO ROLL" EIN PAKET IST UND KEINE SCHLEIFE
-- ============================================================
-- Der Client schickt eine ANZAHL Wuerfe mit; der Server wuerfelt so oft
-- hintereinander, bis die Anzahl erreicht ist oder die GoldGummies nicht mehr
-- reichen, und meldet EIN Ergebnis zurueck. Ein Auto-Roll, der pro Wurf ein
-- Remote feuert, liefe sofort in den RateLimiter (NetworkConfig) und wuerde
-- entweder haengen oder halb durchlaufen.
--
-- Der Preis wird pro Wurf einzeln abgebucht (nicht als Summe vorab): so bricht
-- ein Paket sauber ab, sobald das Geld alle ist, statt vorher abzulehnen oder
-- ins Minus zu laufen.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types       = require(ReplicatedStorage.Network.Types)
local Remotes     = require(ReplicatedStorage.Network.Remotes)
local CharmConfig = require(ReplicatedStorage.Config.CharmConfig)

local PlayerService  = require(ServerScriptService.Services.PlayerService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local RateLimiter    = require(ServerScriptService.Util.RateLimiter)

local CharmService = {}

local function fail(player: Player, action: string, reason: string)
	Remotes.ActionFailed:FireClient(player, action, reason)
end

--------------------------------------------------------------------------------
-- Hilfen
--------------------------------------------------------------------------------

-- Charm eines Slots, oder nil. Baerchi.charms ist eine dichte LISTE (siehe
-- Types.Charm, Kommentar) — der Slot steht im Eintrag, nicht im Schluessel.
local function findCharm(baerchi: Types.Baerchi, slot: number): Types.Charm?
	for _, charm in baerchi.charms do
		if charm.slot == slot then
			return charm
		end
	end
	return nil
end

local function setCharm(baerchi: Types.Baerchi, charm: Types.Charm)
	for index, existing in baerchi.charms do
		if existing.slot == charm.slot then
			baerchi.charms[index] = charm
			return
		end
	end

	table.insert(baerchi.charms, charm)
	table.sort(baerchi.charms, function(a, b)
		return a.slot < b.slot
	end)
end

-- Die Slots, die ein Wurf tatsaechlich anfassen wuerde.
-- Oeffentlich, damit die UI dieselbe Liste anzeigen kann, die der Server
-- wuerfelt — eine nachgebaute Bedingung im Client waere die naechste Stelle,
-- an der Anzeige und Wirklichkeit auseinanderlaufen.
function CharmService.getRollableSlots(baerchi: Types.Baerchi): { number }
	local slots: { number } = {}

	for slot = 1, CharmConfig.SLOT_COUNT do
		if CharmConfig.isSlotUnlocked(slot, baerchi.promotionLevel or 0) then
			local existing = findCharm(baerchi, slot)
			if not (existing and existing.locked) then
				table.insert(slots, slot)
			end
		end
	end

	return slots
end

--------------------------------------------------------------------------------
-- Wuerfeln
--------------------------------------------------------------------------------

function CharmService.rollCharms(player: Player, baerchiUid: string, requestedRolls: number)
	local data = PlayerService.getData(player)
	if not data then return end

	local baerchi = data.island.baerchis[baerchiUid]
	if not baerchi then
		fail(player, "RequestRollCharms", "Baerchi nicht gefunden")
		return
	end

	-- Obergrenze serverseitig, nicht clientseitig: eine erfundene Zahl aus
	-- einem manipulierten Client darf hoechstens ein Auto-Roll-Paket ausloesen,
	-- nicht zehntausend Wuerfe in einem Tick.
	local rolls = math.clamp(math.floor(requestedRolls or 1), 1, CharmConfig.AUTO_ROLL_COUNT)

	if #CharmService.getRollableSlots(baerchi) == 0 then
		fail(player, "RequestRollCharms", "Kein freier Slot zum Wuerfeln — alles gesperrt oder noch nicht freigeschaltet")
		return
	end

	local cost = CharmConfig.ROLL_COST_GOLD_GUMMIES

	if data.goldGummies < cost then
		fail(player, "RequestRollCharms", string.format(
			"Ein Wurf kostet %d GoldGummies (du hast %d)", cost, data.goldGummies
		))
		return
	end

	local done  = 0
	local spent = 0

	for _ = 1, rolls do
		if data.goldGummies < cost then
			break   -- Paket endet hier, der Rest verfaellt
		end

		local ok = EconomyService.spendGoldGummies(player, cost)
		if not ok then
			break
		end
		spent += cost

		-- Slots JEDES MAL neu bestimmen: der Spieler kann waehrend eines
		-- Paketes nichts sperren, aber ein spaeterer Ausbau (mehrere Baerchis,
		-- Slots die sich zwischendurch aendern) soll hier nicht stillschweigend
		-- auf einer veralteten Liste weiterwuerfeln.
		for _, slot in CharmService.getRollableSlots(baerchi) do
			setCharm(baerchi, CharmConfig.rollCharm(slot))
		end

		done += 1
	end

	if done == 0 then
		-- Kann nur passieren, wenn EconomyService den ersten Abzug ablehnt
		-- (Zustand hat sich zwischen Pruefung und Buchung geaendert).
		fail(player, "RequestRollCharms", "Wurf konnte nicht abgerechnet werden")
		return
	end

	local result: Types.CharmRollResult = {
		baerchiUid       = baerchiUid,
		rolls            = done,
		goldGummiesSpent = spent,
		charms           = baerchi.charms,
	}

	Remotes.CharmRollResultReceived:FireClient(player, result)
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)

	print(
		"[CharmService]", player.Name,
		"|", baerchi.configId, "|", done, "Wurf/Wuerfe |", spent, "GoldGummies"
	)
end

--------------------------------------------------------------------------------
-- Sperren
--------------------------------------------------------------------------------

function CharmService.toggleLock(player: Player, baerchiUid: string, slot: number)
	local data = PlayerService.getData(player)
	if not data then return end

	local baerchi = data.island.baerchis[baerchiUid]
	if not baerchi then
		fail(player, "RequestToggleCharmLock", "Baerchi nicht gefunden")
		return
	end

	if slot < 1 or slot > CharmConfig.SLOT_COUNT then
		return   -- unsinniger Slot: still ignorieren, das kann nur ein Exploit sein
	end

	local charm = findCharm(baerchi, slot)
	if not charm then
		fail(player, "RequestToggleCharmLock", "In diesem Slot sitzt noch kein Charm")
		return
	end

	charm.locked = not charm.locked

	PlayerService.markDirty(player)
	PlayerService.saveNow(player)
end

function CharmService.init()
	RateLimiter.connect(Remotes.RequestRollCharms, "RequestRollCharms", function(player, baerchiUid: any, rolls: any)
		if typeof(baerchiUid) ~= "string" then return end

		local count = if typeof(rolls) == "number" then rolls else 1
		CharmService.rollCharms(player, baerchiUid, count)
	end)

	RateLimiter.connect(Remotes.RequestToggleCharmLock, "RequestToggleCharmLock", function(player, baerchiUid: any, slot: any)
		if typeof(baerchiUid) ~= "string" or typeof(slot) ~= "number" then return end
		CharmService.toggleLock(player, baerchiUid, math.floor(slot))
	end)

	print(
		"[CharmService] Initialisiert |", CharmConfig.SLOT_COUNT, "Slots |",
		CharmConfig.ROLL_COST_GOLD_GUMMIES, "GoldGummies pro Wurf"
	)
end

return CharmService
