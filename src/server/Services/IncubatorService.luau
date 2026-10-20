--!strict
-- IncubatorService.luau
-- ServerScriptService/Services/IncubatorService.luau
--
-- Einzige Zustaendigkeit:
--   - Der Solo-Inkubator (15.10.2026): EIN Baerchi sitzt darin und bruetet im
--     Takt seiner Rarity Eier. Die Eier werden im Inkubator gesammelt
--     (Lager, Grenze je Stufe), per Abholen ins Ei-Lager gelegt. Ausbau auf
--     Stufe 2..4 gegen Rebirths + Gummies.
--
-- Vorher (05.10.): sechs Plaetze, Eier mit Brutzeit, Eier fielen neben den
-- Inkubator. Das gibt es nicht mehr; alte Plaetze/Eier in `slots` werden
-- ignoriert (Entscheidung: nichts migrieren).
--
-- Was NICHT hier passiert:
--   * Das Schluepfen: EggService.openEgg (Gacha, Mutation, Index, Quests).
--   * Waehrungen: nur ueber EconomyService.
--   * Anzeige: PlotDisplayService/MapService (Signatur), IncubatorBuilder
--     schreibt den Stand als Attribute, der Client rechnet den Takt selbst.
--
-- Kein Timer pro Baerchi: der Eintrag traegt lastEggAt (Zeitmarke wie beim
-- Legen); faellig wird nachgerechnet — auch offline (gebremst wie das Legen,
-- begrenzt durch das Lager).

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types           = require(ReplicatedStorage.Network.Types)
local Remotes         = require(ReplicatedStorage.Network.Remotes)
local Loc             = require(ReplicatedStorage.Localization.Loc)
local EggConfig       = require(ReplicatedStorage.Config.EggConfig)
local FeatureFlags    = require(ReplicatedStorage.Config.FeatureFlags)
local IncubatorConfig = require(ReplicatedStorage.Config.IncubatorConfig)
local IncubatorRules  = require(ReplicatedStorage.Modules.IncubatorRules)
local EggCalculator   = require(ReplicatedStorage.Modules.EggCalculator)
local EggTree         = require(ReplicatedStorage.Modules.EggTree)

local Players        = game:GetService("Players")
local PlayerService  = require(ServerScriptService.Services.PlayerService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local RateLimiter    = require(ServerScriptService.Util.RateLimiter)

local IncubatorService = {}

local SLOT = 1
local BREED_TICK_SECONDS = 5

-- Gluecks-Bonus (IncubatorConfig.LUCK): Startzeit je Spieler, nur im Speicher. Der
-- Client liest sie als Attribut "IncLuckStart" und rechnet die Anzeige selbst.
local _luckStart: { [Player]: number } = {}

local function setLuck(player: Player, startedAt: number?)
	_luckStart[player] = startedAt
	player:SetAttribute("IncLuckStart", startedAt)
end

local function luckPercentOf(player: Player?): number
	if not player then return 0 end
	return IncubatorRules.luckPercent(IncubatorRules.luckSeconds(_luckStart[player], os.time()))
end

local function fail(player: Player, action: string, reason: Types.LocMsg)
	Remotes.ActionFailed:FireClient(player, action, reason)
end

local function changed(player: Player, kind: string, count: number?)
	Remotes.IncubatorChanged:FireClient(player, { slot = SLOT, kind = kind, count = count })
end

-- Gemeinsame Vorpruefung. Gibt die Daten zurueck, wenn der Inkubator benutzbar ist.
local function usable(player: Player, action: string): Types.PlayerData?
	if not FeatureFlags.isOn("INCUBATOR") then return nil end
	local data = PlayerService.getData(player)
	if not data or not data.island.incubator then return nil end
	if not IncubatorRules.isUnlocked(data) then
		fail(player, action, Loc.msg("err.incubator_locked"))
		return nil
	end
	return data
end

local function breedersOf(data: Types.PlayerData): { Types.IncubatorBreeder }
	local incubator = data.island.incubator
	if not incubator.breeders then incubator.breeders = {} end
	return incubator.breeders :: { Types.IncubatorBreeder }
end

-- Raeumt Eintraege, deren Baerchi es nicht mehr gibt (Fusion, Verwerten) oder
-- der inzwischen ausgeruestet ist (der legt dann selbst), und alte Eintraege
-- ausserhalb des einen Platzes. Gibt true zurueck, wenn sich etwas geaendert hat.
local function cleanBreeders(data: Types.PlayerData): boolean
	local breeders = breedersOf(data)
	local changedAny = false
	for i = #breeders, 1, -1 do
		local entry = breeders[i]
		if entry.slot ~= SLOT or not data.island.baerchis[entry.uid] or data.island.equippedUid == entry.uid then
			table.remove(breeders, i)
			changedAny = true
		end
	end
	-- Level aus alten Staenden (Skala 1-60, vor dem Solo-Inkubator) zaehlt nicht
	-- mehr: wer darueber liegt, beginnt auf Stufe 1 (nichts wird migriert; die
	-- Ausbauten gibt es jetzt nur noch gegen Rebirths + Gummies).
	local incubator = data.island.incubator
	if typeof(incubator.level) ~= "number" or incubator.level > IncubatorConfig.MAX_LEVEL or incubator.level < 1 then
		incubator.level = 1
		changedAny = true
	end
	return changedAny
end

-- Bruetet die faelligen Eier des Baerchis ins Lager. Gibt die Zahl neuer Eier zurueck.
local function breed(data: Types.PlayerData, offline: boolean, player: Player?): number
	local incubator = data.island.incubator
	local entry = IncubatorRules.findBreeder(breedersOf(data), SLOT)
	local baerchi = if entry then data.island.baerchis[entry.uid] else nil
	if not entry or not baerchi then return 0 end

	local now = os.time()
	local level = IncubatorRules.levelOf(incubator)
	local seconds = IncubatorRules.breedSeconds(baerchi.rarity, level, if offline then EggConfig.OFFLINE_SLOWDOWN else nil)
	local free = IncubatorRules.storedFree(incubator)
	if free <= 0 then
		-- Lager voll: es sammelt sich nichts an, der Takt laeuft erst nach dem
		-- Abholen wieder los (wie beim Legen bei voller Obergrenze).
		entry.lastEggAt = now
		return 0
	end

	local due = IncubatorRules.breedDue(entry.lastEggAt, now, seconds)
	if due <= 0 then return 0 end

	local stored = IncubatorRules.storedOf(incubator)
	local produced = 0
	for _ = 1, math.min(due, free) do
		local rolled = EggCalculator.rollEggType(baerchi, if offline then 0 else luckPercentOf(player))
		if not rolled then break end
		local eggType = EggTree.resolveLaid(data.eggTree, rolled)
		stored[eggType] = (stored[eggType] or 0) + 1
		produced += 1
	end
	if produced >= free then
		entry.lastEggAt = now
	else
		-- Der angebrochene Rest bleibt fuer das naechste Ei erhalten.
		entry.lastEggAt += produced * seconds
	end
	return produced
end

--------------------------------------------------------------------------------
-- Baerchi hinein / heraus
--------------------------------------------------------------------------------

function IncubatorService.putBaerchi(player: Player, uid: string): boolean
	local data = usable(player, "RequestIncubatorBaerchi")
	if not data then return false end

	local ok, reason = IncubatorRules.canBreed(data.island, uid)
	if not ok then
		fail(player, "RequestIncubatorBaerchi", Loc.msg(reason or "err.unknown"))
		return false
	end

	-- Ein Baerchi sitzt schon darin: seine faelligen Eier zaehlen noch, dann
	-- tauscht der neue ihn aus.
	breed(data, false, player)
	local breeders = breedersOf(data)
	table.clear(breeders)
	table.insert(breeders, { slot = SLOT, uid = uid, lastEggAt = os.time() })
	setLuck(player, os.time())

	changed(player, "put")
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)
	return true
end

function IncubatorService.takeBaerchi(player: Player): boolean
	local data = usable(player, "RequestIncubatorBaerchi")
	if not data then return false end

	local breeders = breedersOf(data)
	if not IncubatorRules.findBreeder(breeders, SLOT) then
		fail(player, "RequestIncubatorBaerchi", Loc.msg("err.incubator_empty"))
		return false
	end
	breed(data, false, player)
	table.clear(breeders)
	setLuck(player, nil)

	changed(player, "take")
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)
	return true
end

--------------------------------------------------------------------------------
-- Eier abholen: Lager des Inkubators -> Ei-Lager
--------------------------------------------------------------------------------

function IncubatorService.collect(player: Player): number
	local data = usable(player, "RequestIncubatorCollect")
	if not data then return 0 end

	local incubator = data.island.incubator
	-- Was seit dem letzten Takt faellig wurde, zaehlt noch mit.
	breed(data, false, player)
	local stored = IncubatorRules.storedOf(incubator)
	local total = 0
	for eggType, count in stored do
		if count > 0 and EggConfig.data[eggType :: Types.EggType] then
			data.island.eggStock[eggType :: Types.EggType] = (data.island.eggStock[eggType :: Types.EggType] or 0) + count
			total += count
		end
	end
	if total <= 0 then
		fail(player, "RequestIncubatorCollect", Loc.msg("err.incubator_nothing_stored"))
		return 0
	end
	table.clear(stored)

	-- Ein volles Lager hat den Takt angehalten: er laeuft ab jetzt wieder.
	local entry = IncubatorRules.findBreeder(breedersOf(data), SLOT)
	if entry then entry.lastEggAt = os.time() end

	changed(player, "collect", total)
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)
	return total
end

--------------------------------------------------------------------------------
-- Ausbau (Stufe 2..4): Rebirths + Gummies. Geht beim Rebirth nicht verloren.
--------------------------------------------------------------------------------

function IncubatorService.upgrade(player: Player): boolean
	local data = usable(player, "RequestUpgradeIncubator")
	if not data then return false end

	local incubator = data.island.incubator
	local target = IncubatorRules.levelOf(incubator) + 1
	local cost = IncubatorRules.upgradeCost(target)
	if not cost then
		fail(player, "RequestUpgradeIncubator", Loc.msg("err.incubator_max"))
		return false
	end
	if (data.rebirthCount or 0) < cost.rebirths then
		fail(player, "RequestUpgradeIncubator", Loc.msg("err.incubator_needs_rebirth", { n = cost.rebirths }))
		return false
	end
	if data.gummies < cost.gummies then
		fail(player, "RequestUpgradeIncubator", Loc.msg("err.not_enough_gummies", { need = cost.gummies, have = data.gummies }))
		return false
	end

	local ok, reason = EconomyService.spendGummies(player, cost.gummies)
	if not ok then
		fail(player, "RequestUpgradeIncubator", reason or Loc.msg("err.unknown"))
		return false
	end

	-- Fertige Eier noch mit dem alten Tempo gutschreiben, dann hochstufen.
	breed(data, false, player)
	incubator.level = target
	changed(player, "upgrade")
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)
	return true
end

--------------------------------------------------------------------------------
-- Brut-Takt
--------------------------------------------------------------------------------

-- Spieler, deren Offline-Nachholen noch laeuft: der Online-Takt laesst sie aus,
-- sonst zaehlte die Offline-Zeit zum vollen Online-Tempo.
local _offlinePending: { [Player]: boolean } = {}

local function breedTick()
	for _, player in Players:GetPlayers() do
		if _offlinePending[player] then continue end
		local data = PlayerService.getData(player)
		if not data or not data.island.incubator then continue end
		local dirty = cleanBreeders(data)
		if not IncubatorRules.findBreeder(breedersOf(data), SLOT) then
			if _luckStart[player] then setLuck(player, nil) end
		elseif not _luckStart[player] then
			setLuck(player, os.time())
		end
		if breed(data, false, player) > 0 then dirty = true end
		if dirty then PlayerService.markDirty(player) end
	end
end

-- Nur fuer den Studio-Test (DebugService): der Baerchi im Inkubator bruetet
-- sofort ein Ei.
function IncubatorService.breedNow(player: Player): number
	local data = PlayerService.getData(player)
	if not data then return 0 end
	local entry = IncubatorRules.findBreeder(breedersOf(data), SLOT)
	local baerchi = if entry then data.island.baerchis[entry.uid] else nil
	if not entry or not baerchi then return 0 end
	entry.lastEggAt -= IncubatorRules.breedSeconds(baerchi.rarity, IncubatorRules.levelOf(data.island.incubator))
	local made = breed(data, false, player)
	PlayerService.markDirty(player)
	return made
end

--------------------------------------------------------------------------------
-- Initialisierung
--------------------------------------------------------------------------------

function IncubatorService.init()
	RateLimiter.connect(Remotes.RequestIncubatorCollect, "RequestIncubatorCollect", function(player)
		IncubatorService.collect(player)
	end)

	RateLimiter.connect(Remotes.RequestUpgradeIncubator, "RequestUpgradeIncubator", function(player)
		IncubatorService.upgrade(player)
	end)

	-- ("put", baerchiUid) / ("take")
	RateLimiter.connect(Remotes.RequestIncubatorBaerchi, "RequestIncubatorBaerchi", function(player, action: any, arg: any)
		if action == "put" and typeof(arg) == "string" then
			IncubatorService.putBaerchi(player, arg)
		elseif action == "take" then
			IncubatorService.takeBaerchi(player)
		end
	end)

	if not FeatureFlags.isOn("INCUBATOR") then return end

	-- Offline-Nachholen beim Laden: braucht keinen Ort mehr, die Eier gehen
	-- ins Lager des Inkubators (begrenzt durch dessen Groesse).
	PlayerService.onDataLoaded(function(player, data)
		if not data.island.incubator then return end
		_offlinePending[player] = true
		local dirty = cleanBreeders(data)
		if breed(data, true) > 0 then dirty = true end
		_offlinePending[player] = nil
		if IncubatorRules.findBreeder(breedersOf(data), SLOT) then setLuck(player, os.time()) end
		if dirty then PlayerService.markDirty(player) end
	end)

	Players.PlayerRemoving:Connect(function(player)
		_offlinePending[player] = nil
		_luckStart[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(BREED_TICK_SECONDS)
			local ok, err = pcall(breedTick)
			if not ok then
				warn("[IncubatorService] Brut-Takt fehlgeschlagen:", err)
			end
		end
	end)

	print("[IncubatorService] Initialisiert | Solo-Inkubator | Stufen:", IncubatorConfig.MAX_LEVEL)
end

return IncubatorService
