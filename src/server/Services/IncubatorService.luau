--!strict
-- IncubatorService.luau
-- ServerScriptService/Services/IncubatorService.luau
--
-- Einzige Zustaendigkeit:
--   - Der Inkubator (Sammel-Update 05.10., Paket 8): Eier aus dem Lager in
--     freie Plaetze legen, fertige abholen (Schluepfen anstossen),
--     beschleunigen (GoldGummies) und ausbauen (Gummies).
--
-- Kontext: "Mein Plot ist so gross, aber es passiert hier so wenig." Eier ab
-- der Gold-Stufe brauchen jetzt Brutzeit; man legt sie hinein, kommt zurueck
-- und holt das Baerchi ab. Basis- und Zucker-Ei gehen weiter sofort auf
-- (IncubatorRules.requiresIncubator).
--
-- Was NICHT hier passiert:
--   * Das Schluepfen selbst: EggService.openEgg (Gacha, Mutation, Index,
--     Quests, Auto-Ausruesten bleiben an einer Stelle). Zum Abholen legt
--     dieser Service das Ei kurz zurueck ins Lager und ruft openEgg mit
--     fromIncubator = true — geht dabei etwas schief, liegt das Ei im Lager
--     und ist nicht verloren.
--   * Waehrungen: nur ueber EconomyService.
--   * Anzeige: PlotDisplayService/MapService (Signatur), der Client rechnet
--     Fortschritt und "fertig" selbst aus den Zeitmarken.
--
-- Kein Timer pro Ei: jeder Platz traegt startedAt/finishAt (Zeitmarken wie
-- Honig und Recycler) und ist fertig, sobald os.time() >= finishAt — auch
-- offline und ueber Server-Neustarts hinweg.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types           = require(ReplicatedStorage.Network.Types)
local Remotes         = require(ReplicatedStorage.Network.Remotes)
local Loc             = require(ReplicatedStorage.Localization.Loc)
local EggConfig       = require(ReplicatedStorage.Config.EggConfig)
local FeatureFlags    = require(ReplicatedStorage.Config.FeatureFlags)
local IncubatorConfig = require(ReplicatedStorage.Config.IncubatorConfig)
local IncubatorRules  = require(ReplicatedStorage.Modules.IncubatorRules)

local PlayerService  = require(ServerScriptService.Services.PlayerService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local EggService     = require(ServerScriptService.Services.EggService)
local RateLimiter    = require(ServerScriptService.Util.RateLimiter)

local IncubatorService = {}

local function fail(player: Player, action: string, reason: Types.LocMsg)
	Remotes.ActionFailed:FireClient(player, action, reason)
end

local function changed(player: Player, slot: number, kind: string)
	Remotes.IncubatorChanged:FireClient(player, { slot = slot, kind = kind })
end

-- Gemeinsame Vorpruefung. Gibt die Daten zurueck, wenn der Inkubator benutzbar ist.
local function usable(player: Player, action: string): Types.PlayerData?
	if not FeatureFlags.isOn("INCUBATOR") then return nil end
	local data = PlayerService.getData(player)
	if not data then return nil end
	if not IncubatorRules.isUnlocked(data) then
		fail(player, action, Loc.msg("err.incubator_locked"))
		return nil
	end
	return data
end

--------------------------------------------------------------------------------
-- Einlegen
--------------------------------------------------------------------------------

function IncubatorService.start(player: Player, eggType: Types.EggType): boolean
	local data = usable(player, "RequestIncubatorStart")
	if not data then return false end

	local egg = EggConfig.data[eggType]
	if not egg then
		fail(player, "RequestIncubatorStart", Loc.msg("err.egg_unknown_type"))
		return false
	end

	local stock = data.island.eggStock[eggType] or 0
	if stock <= 0 then
		fail(player, "RequestIncubatorStart", Loc.msg("err.egg_none_in_stock", { egg = Loc.msg("egg." .. eggType .. ".name") }))
		return false
	end

	local incubator = data.island.incubator
	local count = IncubatorRules.slotCountFor(data)
	local index = IncubatorRules.firstFree(incubator.slots, count)
	if not index then
		fail(player, "RequestIncubatorStart", Loc.msg("err.incubator_full"))
		return false
	end

	local now = os.time()
	data.island.eggStock[eggType] = stock - 1
	table.insert(incubator.slots, {
		slot      = index,
		eggType   = eggType,
		startedAt = now,
		finishAt  = now + IncubatorRules.brewSeconds(eggType, incubator.level),
	})
	table.sort(incubator.slots, function(a, b) return a.slot < b.slot end)

	changed(player, index, "start")
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)
	return true
end

--------------------------------------------------------------------------------
-- Abholen
--------------------------------------------------------------------------------

function IncubatorService.collect(player: Player, index: number): Types.HatchResult?
	local data = usable(player, "RequestIncubatorCollect")
	if not data then return nil end

	local incubator = data.island.incubator
	local entry, position = IncubatorRules.findSlot(incubator.slots, index)
	if not entry or not position then
		fail(player, "RequestIncubatorCollect", Loc.msg("err.incubator_empty"))
		return nil
	end
	if not IncubatorRules.isReady(entry, os.time()) then
		fail(player, "RequestIncubatorCollect", Loc.msg("err.incubator_not_ready", {
			time = Loc.formatDuration(IncubatorRules.remaining(entry, os.time())),
		}))
		return nil
	end

	-- Ei zurueck ins Lager und ueber den normalen Weg oeffnen (siehe Kopf).
	table.remove(incubator.slots, position)
	local stock = data.island.eggStock
	stock[entry.eggType] = (stock[entry.eggType] or 0) + 1

	local result = EggService.openEgg(player, entry.eggType, true)
	changed(player, index, "collect")
	if not result then
		-- openEgg hat schon gemeldet; das Ei liegt im Lager.
		PlayerService.markDirty(player)
	end
	return result
end

-- Alle fertigen auf einmal (Plot-Prompt).
function IncubatorService.collectAll(player: Player)
	local data = usable(player, "RequestIncubatorCollect")
	if not data then return end
	local now = os.time()
	local ready: { number } = {}
	for _, entry in data.island.incubator.slots do
		if IncubatorRules.isReady(entry, now) then table.insert(ready, entry.slot) end
	end
	if #ready == 0 then
		fail(player, "RequestIncubatorCollect", Loc.msg("err.incubator_none_ready"))
		return
	end
	for _, index in ready do
		IncubatorService.collect(player, index)
	end
end

--------------------------------------------------------------------------------
-- Beschleunigen
--------------------------------------------------------------------------------

function IncubatorService.speedUp(player: Player, index: number): boolean
	local data = usable(player, "RequestIncubatorSpeedUp")
	if not data then return false end

	local entry = IncubatorRules.findSlot(data.island.incubator.slots, index)
	if not entry then
		fail(player, "RequestIncubatorSpeedUp", Loc.msg("err.incubator_empty"))
		return false
	end

	local now = os.time()
	local cost = IncubatorRules.speedUpCost(entry, now)
	if cost <= 0 then return true end

	local ok, reason = EconomyService.spendGoldGummies(player, cost)
	if not ok then
		fail(player, "RequestIncubatorSpeedUp", reason or Loc.msg("err.unknown"))
		return false
	end

	entry.finishAt = now
	changed(player, index, "speedup")
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)
	return true
end

--------------------------------------------------------------------------------
-- Ausbauen (Geldsenke vor dem Rebirth, Paket 4.4)
--------------------------------------------------------------------------------

function IncubatorService.upgrade(player: Player): boolean
	local data = usable(player, "RequestUpgradeIncubator")
	if not data then return false end

	local incubator = data.island.incubator
	local target = incubator.level + 1
	local cost = IncubatorRules.upgradeCost(target)
	if not cost then
		fail(player, "RequestUpgradeIncubator", Loc.msg("err.incubator_max"))
		return false
	end
	if data.gummies < cost.gummies then
		fail(player, "RequestUpgradeIncubator", Loc.msg("err.not_enough_gummies", { need = cost.gummies, have = data.gummies }))
		return false
	end
	if data.goldGummies < cost.goldGummies then
		fail(player, "RequestUpgradeIncubator", Loc.msg("err.not_enough_gold_gummies", { need = cost.goldGummies, have = data.goldGummies }))
		return false
	end

	local ok, reason = EconomyService.spendGummies(player, cost.gummies)
	if not ok then
		fail(player, "RequestUpgradeIncubator", reason or Loc.msg("err.unknown"))
		return false
	end
	if cost.goldGummies > 0 then
		local okGold, reasonGold = EconomyService.spendGoldGummies(player, cost.goldGummies)
		if not okGold then
			-- Gummies zurueck: die Pruefung oben hat schon gesagt, dass es reicht,
			-- das hier ist nur das Netz fuer einen gleichzeitigen zweiten Abzug.
			EconomyService.awardGummiesFlat(player, cost.gummies)
			fail(player, "RequestUpgradeIncubator", reasonGold or Loc.msg("err.unknown"))
			return false
		end
	end

	incubator.level = target
	-- Laufende Bruten behalten ihre Zeit (sie wurde beim Einlegen festgelegt);
	-- das neue Tempo gilt fuer die naechsten Eier.
	changed(player, 0, "upgrade")
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)
	return true
end

--------------------------------------------------------------------------------
-- Initialisierung
--------------------------------------------------------------------------------

function IncubatorService.init()
	RateLimiter.connect(Remotes.RequestIncubatorStart, "RequestIncubatorStart", function(player, eggType: any)
		if typeof(eggType) ~= "string" or not EggConfig.data[eggType :: Types.EggType] then return end
		IncubatorService.start(player, eggType :: Types.EggType)
	end)

	RateLimiter.connect(Remotes.RequestIncubatorCollect, "RequestIncubatorCollect", function(player, index: any)
		if index == "all" then
			IncubatorService.collectAll(player)
			return
		end
		if typeof(index) ~= "number" or index ~= math.floor(index) or index < 1 or index > IncubatorConfig.MAX_SLOTS then return end
		IncubatorService.collect(player, index)
	end)

	RateLimiter.connect(Remotes.RequestIncubatorSpeedUp, "RequestIncubatorSpeedUp", function(player, index: any)
		if typeof(index) ~= "number" or index ~= math.floor(index) or index < 1 or index > IncubatorConfig.MAX_SLOTS then return end
		IncubatorService.speedUp(player, index)
	end)

	RateLimiter.connect(Remotes.RequestUpgradeIncubator, "RequestUpgradeIncubator", function(player)
		IncubatorService.upgrade(player)
	end)

	print("[IncubatorService] Initialisiert | Plaetze max", IncubatorConfig.MAX_SLOTS)
end

return IncubatorService
