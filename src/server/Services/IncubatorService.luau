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

local EggCalculator   = require(ReplicatedStorage.Modules.EggCalculator)
local EggTree         = require(ReplicatedStorage.Modules.EggTree)

local Players        = game:GetService("Players")
local PlayerService  = require(ServerScriptService.Services.PlayerService)
local MapService     = require(ServerScriptService.Services.MapService)
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
	-- INCUBATOR_BREED: Eier werden nicht mehr gebruetet, sie gehen sofort auf.
	if FeatureFlags.isOn("INCUBATOR_BREED") then return false end
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
-- INCUBATOR_BREED: Baerchis bruehten Eier (Wunsch Projektinhaber 05.10.)
--------------------------------------------------------------------------------
-- Ein Baerchi im Inkubator bruetet im Takt seiner Rarity Eier aus seiner
-- eigenen Tabelle (IncubatorRules.breedSeconds, EggCalculator.rollEggType).
-- Die Eier fallen neben den Inkubator in island.laidEggs (fromIncubator) und
-- werden wie gelegte Eier durch Darueberlaufen eingesammelt. Kein Timer pro
-- Baerchi: jeder Platz traegt lastEggAt, faellig wird nachgerechnet — auch
-- offline (gebremst wie das Legen, eigene kleinere Obergrenze).

local BREED_TICK_SECONDS = 5
local _breedCounter = 0

local function breeding(): boolean
	return FeatureFlags.isOn("INCUBATOR") and FeatureFlags.isOn("INCUBATOR_BREED")
end

local function breedersOf(data: Types.PlayerData): { Types.IncubatorBreeder }
	local incubator = data.island.incubator
	if not incubator.breeders then incubator.breeders = {} end
	return incubator.breeders :: { Types.IncubatorBreeder }
end

local function lyingFromIncubator(data: Types.PlayerData): number
	local n = 0
	for _, egg in data.island.laidEggs do
		if egg.fromIncubator then n += 1 end
	end
	return n
end

-- Ort fuer ein gebruetetes Ei (plot-relativ wie alle gelegten Eier), oder nil.
local function dropPosition(player: Player): Vector3?
	local model = MapService.getIncubatorModel(player)
	local base = if model then model.PrimaryPart else nil
	if not base then return nil end
	local angle = math.random() * math.pi * 2
	local radius = IncubatorConfig.BREED_DROP_MIN
		+ math.random() * (IncubatorConfig.BREED_DROP_MAX - IncubatorConfig.BREED_DROP_MIN)
	local ground = base.Position.Y - base.Size.Y * 0.5
	local world = Vector3.new(base.Position.X + math.cos(angle) * radius, ground, base.Position.Z + math.sin(angle) * radius)
	return MapService.worldToPlot(player, world)
end

-- Raeumt Plaetze, deren Baerchi es nicht mehr gibt (Fusion, Verwerten) oder
-- der inzwischen ausgeruestet ist (der legt dann selbst). Gibt true zurueck,
-- wenn sich etwas geaendert hat.
local function cleanBreeders(data: Types.PlayerData): boolean
	local breeders = breedersOf(data)
	local changedAny = false
	for i = #breeders, 1, -1 do
		local entry = breeders[i]
		if not data.island.baerchis[entry.uid] or data.island.equippedUid == entry.uid then
			table.remove(breeders, i)
			changedAny = true
		end
	end
	return changedAny
end

-- Bruetet die faelligen Eier aller Plaetze. Gibt die Zahl neuer Eier zurueck.
local function breed(player: Player, data: Types.PlayerData, offline: boolean): number
	local incubator = data.island.incubator
	local breeders = breedersOf(data)
	local now = os.time()
	local cap = if offline then IncubatorConfig.BREED_OFFLINE_MAX else IncubatorConfig.BREED_MAX_LYING
	local lying = lyingFromIncubator(data)
	local made = 0
	local count = IncubatorRules.slotCountFor(data)

	for _, entry in breeders do
		local baerchi = data.island.baerchis[entry.uid]
		if not baerchi then continue end
		-- Platz ueber der aktuellen Platz-Zahl (Rebirth setzt das Level
		-- zurueck): der Baerchi sitzt noch, bruetet aber nicht.
		if entry.slot > count then
			entry.lastEggAt = now
			continue
		end
		local seconds = IncubatorRules.breedSeconds(baerchi.rarity, incubator.level,
			if offline then EggConfig.OFFLINE_SLOWDOWN else nil)
		local due = IncubatorRules.breedDue(entry.lastEggAt, now, seconds)
		if due <= 0 then continue end

		local produced = 0
		for _ = 1, due do
			if lying >= cap then break end
			local rolled = EggCalculator.rollEggType(baerchi)
			local position = if rolled then dropPosition(player) else nil
			if not rolled or not position then break end
			produced += 1
			_breedCounter += 1
			table.insert(data.island.laidEggs, {
				uid           = string.format("e_inc_%d_%d_%d", now, _breedCounter, math.random(1000, 9999)),
				eggType       = EggTree.resolveLaid(data.eggTree, rolled),
				laidAt        = now,
				x             = position.X,
				y             = position.Y,
				z             = position.Z,
				fromIncubator = true,
			})
			lying += 1
			made += 1
		end
		-- Wie beim Legen: bei voller Obergrenze sammelt sich nichts an.
		-- Sonst bleibt der angebrochene Rest fuer das naechste Ei erhalten.
		-- Ohne Inkubator-Modell (Plot im Neubau) nur das Gebruetete abziehen,
		-- der Rest kommt im naechsten Takt.
		if lying >= cap then
			entry.lastEggAt = now
		else
			entry.lastEggAt += produced * seconds
		end
	end
	return made
end

function IncubatorService.putBaerchi(player: Player, uid: string): boolean
	if not breeding() then return false end
	local data = usable(player, "RequestIncubatorBaerchi")
	if not data then return false end

	local ok, reason = IncubatorRules.canBreed(data.island, uid)
	if not ok then
		fail(player, "RequestIncubatorBaerchi", Loc.msg(reason or "err.unknown"))
		return false
	end
	local breeders = breedersOf(data)
	local index = IncubatorRules.firstFreeBreeder(breeders, IncubatorRules.slotCountFor(data))
	if not index then
		fail(player, "RequestIncubatorBaerchi", Loc.msg("err.incubator_full"))
		return false
	end

	table.insert(breeders, { slot = index, uid = uid, lastEggAt = os.time() })
	table.sort(breeders, function(a, b) return a.slot < b.slot end)

	changed(player, index, "put")
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)
	return true
end

function IncubatorService.takeBaerchi(player: Player, index: number): boolean
	if not breeding() then return false end
	local data = usable(player, "RequestIncubatorBaerchi")
	if not data then return false end

	local _, position = IncubatorRules.findBreeder(breedersOf(data), index)
	if not position then
		fail(player, "RequestIncubatorBaerchi", Loc.msg("err.incubator_empty"))
		return false
	end
	table.remove(breedersOf(data), position)

	changed(player, index, "take")
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)
	return true
end

-- Umstieg auf INCUBATOR_BREED: Eier aus dem alten Ei-Inkubator gehen ins
-- Lager zurueck (sie oeffnen jetzt sofort). Niemand verliert ein Ei.
local function returnBrewingEggs(data: Types.PlayerData): boolean
	local slots = data.island.incubator.slots
	if #slots == 0 then return false end
	local stock = data.island.eggStock
	for _, entry in slots do
		stock[entry.eggType] = (stock[entry.eggType] or 0) + 1
	end
	table.clear(slots)
	return true
end

-- Spieler, deren Offline-Nachholen noch auf den Plot wartet: der Online-Takt
-- laesst sie aus, sonst zaehlte die Offline-Zeit zum vollen Online-Tempo.
local _offlinePending: { [Player]: boolean } = {}

local function breedTick()
	for _, player in Players:GetPlayers() do
		if _offlinePending[player] then continue end
		local data = PlayerService.getData(player)
		if not data or not data.island.incubator then continue end
		local dirty = cleanBreeders(data)
		if breed(player, data, false) > 0 then dirty = true end
		if dirty then PlayerService.markDirty(player) end
	end
end

-- Nur fuer den Studio-Test (DebugService): jedes Baerchi im Inkubator
-- bruetet sofort ein Ei.
function IncubatorService.breedNow(player: Player): number
	local data = PlayerService.getData(player)
	if not data then return 0 end
	for _, entry in breedersOf(data) do
		local baerchi = data.island.baerchis[entry.uid]
		if baerchi then
			entry.lastEggAt -= IncubatorRules.breedSeconds(baerchi.rarity, data.island.incubator.level)
		end
	end
	local made = breed(player, data, false)
	PlayerService.markDirty(player)
	return made
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

	-- INCUBATOR_BREED
	RateLimiter.connect(Remotes.RequestIncubatorBaerchi, "RequestIncubatorBaerchi", function(player, action: any, arg: any)
		if action == "put" and typeof(arg) == "string" then
			IncubatorService.putBaerchi(player, arg)
		elseif action == "take" and typeof(arg) == "number" and arg == math.floor(arg)
			and arg >= 1 and arg <= IncubatorConfig.MAX_SLOTS then
			IncubatorService.takeBaerchi(player, arg)
		end
	end)

	if breeding() then
		PlayerService.onDataLoaded(function(player, data)
			if not data.island.incubator then return end
			local dirty = returnBrewingEggs(data)
			if cleanBreeders(data) then dirty = true end
			if dirty then PlayerService.markDirty(player) end
			-- Offline-Nachholen, sobald der Inkubator auf dem Plot steht
			-- (die Eier brauchen einen Ort). Hoechstens 30 s warten.
			_offlinePending[player] = true
			task.spawn(function()
				for _ = 1, 60 do
					if MapService.getIncubatorModel(player) or player.Parent == nil then break end
					task.wait(0.5)
				end
				_offlinePending[player] = nil
				if player.Parent == nil then return end
				if not MapService.getIncubatorModel(player) then
					-- Kein Ort fuer Eier: die Offline-Zeit verfaellt (wie volles Lager)
					for _, entry in breedersOf(data) do entry.lastEggAt = os.time() end
					return
				end
				if breed(player, data, true) > 0 then PlayerService.markDirty(player) end
			end)
		end)

		Players.PlayerRemoving:Connect(function(player)
			_offlinePending[player] = nil
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
	end

	print("[IncubatorService] Initialisiert | Plaetze max", IncubatorConfig.MAX_SLOTS,
		"| Baerchi-Brut:", breeding())
end

return IncubatorService
