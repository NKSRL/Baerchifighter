--!strict
-- EggService.luau
-- ServerScriptService/Services/EggService.luau
--
-- Einzige Zustaendigkeit:
--   - Ein Ei aus dem Lager oeffnen: Gacha-Roll, Mutations-Wurf, neuer Baerchi
--   - Den Kauf eines Basis-Eis beim versteckten Haendler abrechnen
--   - v17: Eier als Belohnung ins Lager legen (grantEggs, z.B. UFO-Abwurf),
--     damit Event-Code nie selbst in island.eggStock schreibt
--   - 19.10. (PET_LIMIT_V1): bei vollem Baerchi-Lager (PetCapacity) wird kein
--     Ei geoeffnet. Das ist die EINZIGE Stelle, an der ein Ei zum Baerchi wird
--     (Einzel, xN, Haendler); das Ei bleibt im Lager, nichts geht verloren.
--
-- Seit v12 (Ei-Baum-Konzept, Block A) gibt es KEINE Brutzeit mehr: ein Klick
-- auf "Oeffnen" nimmt ein Ei aus island.eggStock und liefert sofort das
-- Ergebnis. Es gibt auch keinen Kauf ueber das Menue mehr. Eier kommen aus
-- Legen, Events, Rebirth-Meilensteinen und — als einzige Kaufmoeglichkeit —
-- vom Basis-Ei-Haendler (EggMerchantService ruft buyFromMerchant auf).
--
-- Das Oeffnen ist bewusst EIN Schritt auf dem Server: Bestand pruefen,
-- abziehen, wuerfeln, eintragen. Der Client spielt waehrenddessen schon die
-- Ei-Animation ab (HatchAnimation) und bekommt das Ergebnis per
-- HatchResultReceived. Entscheiden tut ausschliesslich dieser Service.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types          = require(ReplicatedStorage.Network.Types)
local Remotes        = require(ReplicatedStorage.Network.Remotes)
local EggConfig      = require(ReplicatedStorage.Config.EggConfig)
local FeatureFlags   = require(ReplicatedStorage.Config.FeatureFlags)
local IncubatorRules = require(ReplicatedStorage.Modules.IncubatorRules)   -- Sammel-Update 8
local BaerchiConfig  = require(ReplicatedStorage.Config.BaerchiConfig)
local GachaRoller    = require(ReplicatedStorage.Modules.GachaRoller)
local BaerchiFactory = require(ReplicatedStorage.Modules.BaerchiFactory)
local PetCapacity    = require(ReplicatedStorage.Modules.PetCapacity)   -- 19.10.: Pet-Limit
local PotionRules    = require(ReplicatedStorage.Modules.PotionRules)   -- 26.10.: Gluecks-Trank

local PlayerService  = require(ServerScriptService.Services.PlayerService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local IslandService  = require(ServerScriptService.Services.IslandService)
local RateLimiter    = require(ServerScriptService.Util.RateLimiter)
local FunnelService = require(ServerScriptService.Services.FunnelService)  -- HBB: Messpunkte
local Loc           = require(ReplicatedStorage.Localization.Loc)

local EggService = {}

local function fail(player: Player, action: string, reason: Types.LocMsg | string)
	Remotes.ActionFailed:FireClient(player, action, reason)
end

--------------------------------------------------------------------------------
-- Ei oeffnen
--------------------------------------------------------------------------------

-- Oeffnet ein Ei des Typs aus dem Lager. Gibt das Ergebnis zurueck (fuer den
-- DebugService) oder nil, wenn es nicht ging — der Spieler bekommt dann
-- ein ActionFailed.
--
-- Sammel-Update 05.10. (Paket 8): Eier ab Gold-Stufe gehen nur noch ueber den
-- Inkubator auf (IncubatorRules.requiresIncubator). Der Inkubator selbst ruft
-- diese Funktion beim Abholen mit `fromIncubator = true` — das Schluepfen
-- (Gacha, Mutation, Index, Quests, Auto-Ausruesten) bleibt so an EINER Stelle.
-- `quiet` (15.10., "10 oeffnen"): kein eigenes Ergebnis-Event und kein Speichern;
-- der Aufrufer (openEggs) sammelt die Ergebnisse und speichert einmal.
function EggService.openEgg(player: Player, eggType: Types.EggType, fromIncubator: boolean?, quiet: boolean?): Types.HatchResult?
	local data = PlayerService.getData(player)
	if not data then return nil end

	if not EggConfig.data[eggType] then
		fail(player, "RequestHatchEgg", Loc.msg("err.egg_unknown_type"))
		return nil
	end

	if not fromIncubator and FeatureFlags.isOn("INCUBATOR") and not FeatureFlags.isOn("INCUBATOR_BREED")
		and IncubatorRules.requiresIncubator(eggType, IncubatorRules.isUnlocked(data)) then
		fail(player, "RequestHatchEgg", Loc.msg("err.egg_needs_incubator", { egg = Loc.msg("egg." .. eggType .. ".name") }))
		return nil
	end

	local stock = data.island.eggStock[eggType] or 0
	if stock <= 0 then
		fail(player, "RequestHatchEgg", Loc.msg("err.egg_none_in_stock", { egg = Loc.msg("egg." .. eggType .. ".name") }))
		return nil
	end

	-- 19.10. (PET_LIMIT_V1): Lager voll -> nichts oeffnen. Die Pruefung steht VOR
	-- dem Wurf und dem Abziehen des Eis, damit kein halber Zustand entsteht. Sie
	-- gilt auch fuer jeden anderen Aufrufer (Haendler, Debug) und ist zugleich der
	-- Schutz gegen ein direkt aufgerufenes Remote.
	if PetCapacity.isFull(data) then
		fail(player, "RequestHatchEgg", Loc.msg("err.pet_limit_full"))
		return nil
	end

	-- Gacha-Roll
	local weightedTable = EggConfig.getNormalizedTable(eggType)
	local entries: { GachaRoller.WeightedEntry } = {}
	for _, weighted in weightedTable do
		table.insert(entries, { configId = weighted.configId, weight = weighted.weight })
	end

	-- 26.10. (POTIONS_V1): Gluecks-Trank — alles ausser dem haeufigsten
	-- Ergebnis bekommt das x-fache Gewicht (PotionRules.applyLuck). Der
	-- Mutations-Wurf darunter bleibt unberuehrt.
	if FeatureFlags.isOn("POTIONS_V1") then
		local luck = PotionRules.multiplier((data :: any).potions, "luck", os.time())
		if luck ~= 1 then
			entries = PotionRules.applyLuck(entries, luck)
		end
	end

	local wonConfigId = GachaRoller.roll(entries)

	-- ============================================================
	-- DER MUTATIONS-WURF
	-- ============================================================
	-- Die EINZIGE Stelle im Spiel, an der ein Baerchi mit einer Mutation
	-- entstehen kann (Fusion vererbt nur, Events werten nur auf). Bewusst hier
	-- und nicht in BaerchiFactory: dort wuerde jeder Aufruf wuerfeln — auch der
	-- Debug-Service und die Fusion. Unabhaengig vom Gacha-Roll darueber.
	local mutation = BaerchiConfig.rollMutation()

	-- Erst pruefen, ob der Baerchi erzeugbar ist, und ERST DANN das Ei
	-- abziehen — sonst waere es bei einem Config-Tippfehler ersatzlos weg.
	local newBaerchi = BaerchiFactory.create(wonConfigId, { mutation = mutation })
	if not newBaerchi then
		fail(player, "RequestHatchEgg", Loc.msg("err.egg_internal"))
		return nil
	end

	-- "Neu" = diese Art ist noch nicht auf der Insel
	local isNew = true
	for _, existing in data.island.baerchis do
		if existing.configId == wonConfigId then
			isNew = false
			break
		end
	end

	data.island.eggStock[eggType] = stock - 1
	data.island.baerchis[newBaerchi.uid] = newBaerchi
	-- v13: Zaehler fuer die Quests (siehe QuestProgress)
	data.stats.totalHatched += 1
	-- v14: Zaehler fuer den Ei-Baum. Zaehlt auch bei einem noch gesperrten
	-- Ei (Sprung-Ei aus einem Event) — der Fortschritt geht nicht verloren.
	-- Ob dadurch ein Knoten frei wird, prueft EggTreeService bei der
	-- naechsten Datenaenderung (markDirty unten loest sie aus).
	data.eggTree.hatched[eggType] = (data.eggTree.hatched[eggType] or 0) + 1

	-- Erster Baerchi ueberhaupt: dann ruestet er sich automatisch aus, sonst
	-- bliebe der Plot leer.
	IslandService.autoEquipIfNone(data)

	local result: Types.HatchResult = {
		eggType = eggType,
		baerchi = newBaerchi,
		isNew   = isNew,
	}

	if not quiet then
		Remotes.HatchResultReceived:FireClient(player, result)
	end
	FunnelService.step(player, "F03_FirstEggOpened")
	PlayerService.markDirty(player)
	if not quiet then
		PlayerService.saveNow(player)
	end

	print("[EggService]", player.Name, "oeffnet", eggType, "->", wonConfigId, "(", newBaerchi.rarity, ")",
		isNew and "| NEU" or "",
		mutation and ("| MUTATION: " .. mutation) or "")

	return result
end

-- 15.10.: bis zu BATCH_MAX Eier derselben Sorte auf einmal oeffnen. Jedes Ei
-- laeuft durch dieselbe openEgg-Logik (Roll, Mutation, Index, Quests); die
-- Ergebnisse gehen gesammelt in EINEM Event an den Client, gespeichert wird einmal.
local BATCH_MAX = 10

function EggService.openEggs(player: Player, eggType: Types.EggType, count: number): { Types.HatchResult }
	local results: { Types.HatchResult } = {}
	local wanted = math.clamp(math.floor(count), 1, BATCH_MAX)
	local data = PlayerService.getData(player)
	local stock = if data then (data.island.eggStock[eggType] or 0) else 0
	wanted = math.max(1, math.min(wanted, stock))

	-- 19.10. (PET_LIMIT_V1): nur so viele Eier oeffnen, wie Platz im Lager ist.
	-- Der Rest bleibt im Eier-Lager; eine Meldung sagt es dem Spieler. Ist gar
	-- kein Platz, wird wie beim Einzel-Oeffnen abgelehnt (ohne Animation).
	local limited = false
	if data then
		local free = PetCapacity.getFree(data)
		if free <= 0 then
			fail(player, "RequestHatchEggs", Loc.msg("err.pet_limit_full"))
			return results
		end
		if wanted > free then
			wanted = free
			limited = true
		end
	end

	for _ = 1, wanted do
		local result = EggService.openEgg(player, eggType, false, true)
		if not result then break end
		table.insert(results, result)
	end
	if #results > 0 then
		Remotes.HatchBatchReceived:FireClient(player, { eggType = eggType, results = results })
		PlayerService.saveNow(player)
		if limited then
			-- Anderer Aktionsname als RequestHatchEggs: die laufende Animation
			-- soll NICHT abgebrochen werden, nur die Meldung kommen.
			fail(player, "RequestHatchEggsLimit", Loc.msg("err.pet_limit_partial", { n = #results }))
		end
	end
	return results
end

--------------------------------------------------------------------------------
-- Haendler-Kauf (einzige Kaufmoeglichkeit)
--------------------------------------------------------------------------------

-- Bucht den Kauf eines Basis-Eis ab und legt es ins Lager. Die
-- Entfernungspruefung macht der Aufrufer (EggMerchantService), weil nur er
-- weiss, wo der Haendler steht.
function EggService.buyFromMerchant(player: Player): boolean
	local data = PlayerService.getData(player)
	if not data then return false end

	-- 19.10. (PET_LIMIT_V1): bei vollem Lager gar nicht erst kaufen — das Ei
	-- wuerde sofort geoeffnet und das ginge nicht; so wird nichts abgebucht.
	if PetCapacity.isFull(data) then
		fail(player, "BuyBasicEgg", Loc.msg("err.pet_limit_full"))
		return false
	end

	local merchant = EggConfig.MERCHANT
	local ok, reason = EconomyService.spendGummies(player, merchant.priceGummies)
	if not ok then
		fail(player, "BuyBasicEgg", reason)
		return false
	end

	data.island.eggStock[merchant.eggType] = (data.island.eggStock[merchant.eggType] or 0) + 1
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)

	print("[EggService]", player.Name, "kauft", merchant.eggType, "beim Haendler fuer", merchant.priceGummies)
	return true
end

--------------------------------------------------------------------------------
-- v17: Eier als Belohnung ins Lager
--------------------------------------------------------------------------------

-- Legt `amount` Eier dieser Sorte ins Lager (gesperrte Baum-Eier und
-- Sonder-Eier inklusive: oeffnen geht immer, siehe openEgg). Gibt false, wenn
-- die Daten fehlen oder die Sorte unbekannt ist.
function EggService.grantEggs(player: Player, eggType: Types.EggType, amount: number): boolean
	local data = PlayerService.getData(player)
	if not data then return false end
	if not EggConfig.data[eggType] then
		warn("[EggService] grantEggs: unbekannte Sorte", eggType)
		return false
	end
	local n = math.max(0, math.floor(amount))
	if n <= 0 then return true end

	data.island.eggStock[eggType] = (data.island.eggStock[eggType] or 0) + n
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)
	return true
end

--------------------------------------------------------------------------------
-- Initialisierung
--------------------------------------------------------------------------------

function EggService.init()
	RateLimiter.connect(Remotes.RequestHatchEgg, "RequestHatchEgg", function(player, eggType: any)
		-- Typ-Validierung (Client-Input immer misstrauen)
		if typeof(eggType) ~= "string" then return end
		if not EggConfig.data[eggType :: Types.EggType] then
			fail(player, "RequestHatchEgg", Loc.msg("err.egg_unknown_type"))
			return
		end

		EggService.openEgg(player, eggType :: Types.EggType)
	end)

	RateLimiter.connect(Remotes.RequestHatchEggs, "RequestHatchEggs", function(player, eggType: any, count: any)
		if typeof(eggType) ~= "string" or typeof(count) ~= "number" then return end
		if count ~= count then return end   -- NaN
		if not EggConfig.data[eggType :: Types.EggType] then
			fail(player, "RequestHatchEggs", Loc.msg("err.egg_unknown_type"))
			return
		end
		EggService.openEggs(player, eggType :: Types.EggType, count)
	end)

	print("[EggService] Initialisiert")
end

return EggService
