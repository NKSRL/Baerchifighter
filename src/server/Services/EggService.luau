--!strict
-- EggService.luau
-- ServerScriptService/Services/EggService.luau
--
-- Einzige Zustaendigkeit:
--   - Ein Ei aus dem Lager oeffnen: Gacha-Roll, Mutations-Wurf, neuer Baerchi
--   - Den Kauf eines Basis-Eis beim versteckten Haendler abrechnen
--   - v17: Eier als Belohnung ins Lager legen (grantEggs, z.B. UFO-Abwurf),
--     damit Event-Code nie selbst in island.eggStock schreibt
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
local BaerchiConfig  = require(ReplicatedStorage.Config.BaerchiConfig)
local GachaRoller    = require(ReplicatedStorage.Modules.GachaRoller)
local BaerchiFactory = require(ReplicatedStorage.Modules.BaerchiFactory)

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
function EggService.openEgg(player: Player, eggType: Types.EggType): Types.HatchResult?
	local data = PlayerService.getData(player)
	if not data then return nil end

	if not EggConfig.data[eggType] then
		fail(player, "RequestHatchEgg", Loc.msg("err.egg_unknown_type"))
		return nil
	end

	local stock = data.island.eggStock[eggType] or 0
	if stock <= 0 then
		fail(player, "RequestHatchEgg", Loc.msg("err.egg_none_in_stock", { egg = Loc.msg("egg." .. eggType .. ".name") }))
		return nil
	end

	-- Gacha-Roll
	local weightedTable = EggConfig.getNormalizedTable(eggType)
	local entries: { GachaRoller.WeightedEntry } = {}
	for _, weighted in weightedTable do
		table.insert(entries, { configId = weighted.configId, weight = weighted.weight })
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

	Remotes.HatchResultReceived:FireClient(player, result)
	FunnelService.step(player, "F03_FirstEggOpened")
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)

	print("[EggService]", player.Name, "oeffnet", eggType, "->", wonConfigId, "(", newBaerchi.rarity, ")",
		isNew and "| NEU" or "",
		mutation and ("| MUTATION: " .. mutation) or "")

	return result
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

	print("[EggService] Initialisiert")
end

return EggService
