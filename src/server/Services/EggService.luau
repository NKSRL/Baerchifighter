--!strict
-- EggService.luau
-- ServerScriptService/Services/EggService.luau
--
-- Einzige Zustaendigkeit:
--   - Ei kaufen und in einen Brut-Slot legen (Timer startet)
--   - Fertige Eier claimen: Gacha-Roll und neuer Baerchi
--   - Kosten abziehen (via EconomyService)
--
-- Ablauf (zweistufig, seit hatchTime tatsaechlich benutzt wird):
--   RequestHatchEgg → Kosten weg, Eintrag in island.hatchingEggs mit readyAt
--   RequestClaimEgg → wenn os.time() >= readyAt: Roll, Baerchi, Eintrag weg
--
-- readyAt ist ein absoluter Timestamp. Dadurch laeuft die Brut auch waehrend
-- der Spieler offline ist weiter und braucht keinen Server-Loop.
--
-- Seit v4 gibt es kein Brueterei-Gebaeude mehr (die Gebaeude produzieren nur
-- noch Honig): die Anzahl paralleler Slots ist fest (EconomyConfig.HATCH_SLOTS)
-- und die Brutdauer ist die volle Zeit aus EggConfig, ohne Reduktion.
--
-- Geclaimt wird ueber die uid des Eis, NICHT ueber seinen Listenindex. Grund
-- steht bei Types.HatchingEgg: bei zwei schnellen Klicks verschiebt der erste
-- table.remove die Liste, und der zweite Klick wuerde ein anderes Ei treffen
-- als das, auf das der Spieler geklickt hat.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types          = require(ReplicatedStorage.Network.Types)
local Remotes        = require(ReplicatedStorage.Network.Remotes)
local Loc           = require(ReplicatedStorage.Localization.Loc)
local EggConfig      = require(ReplicatedStorage.Config.EggConfig)
local BaerchiConfig  = require(ReplicatedStorage.Config.BaerchiConfig)
local EconomyConfig  = require(ReplicatedStorage.Config.EconomyConfig)
local GachaRoller    = require(ReplicatedStorage.Modules.GachaRoller)
local BaerchiFactory = require(ReplicatedStorage.Modules.BaerchiFactory)

local PlayerService  = require(ServerScriptService.Services.PlayerService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local IslandService  = require(ServerScriptService.Services.IslandService)
local RateLimiter    = require(ServerScriptService.Util.RateLimiter)

local EggService = {}

local function fail(player: Player, action: string, reason: Types.LocMsg?)
	Remotes.ActionFailed:FireClient(player, action, reason or Loc.msg("err.unknown"))
end

-- Laufender Zaehler fuer Ei-uids. Gleiches Muster wie BaerchiFactory.newUid:
-- os.time() allein reicht nicht, weil zwei Eier in derselben Sekunde starten
-- koennen. Bewusst kein gemeinsames Uid-Modul — Eier entstehen ausschliesslich
-- hier, und die uid verlaesst diesen Service nur als Anzeige-/Claim-Schluessel.
local _eggCounter = 0

local function newEggUid(): string
	_eggCounter += 1
	return string.format("e_%d_%d_%d", os.time(), _eggCounter, math.random(1000, 9999))
end

--------------------------------------------------------------------------------
-- Hilfsfunktionen
--------------------------------------------------------------------------------

-- Wie viele Eier dieser Spieler gleichzeitig ausbrueten kann.
-- Fester Wert seit v4 — die Signatur behaelt trotzdem `data`, damit ein
-- spaeterer Ausbau (Gamepass, Rebirth-Bonus) hier andocken kann ohne dass
-- jeder Aufrufer angefasst werden muss.
function EggService.getSlotCount(_data: Types.PlayerData): number
	return EconomyConfig.HATCH_SLOTS
end

-- Brutdauer in Sekunden fuer diesen Ei-Typ (volle Zeit aus EggConfig)
function EggService.getHatchDuration(_data: Types.PlayerData, eggType: Types.EggType): number
	local def = EggConfig.data[eggType]
	if not def then return 0 end

	return math.max(0, math.floor(def.hatchTime))
end

-- Prueft ob der Spieler das Ei bezahlen kann und zieht die Kosten ab.
-- Reihenfolge: Lagerbestand zuerst, dann Gummies, dann GoldGummies.
-- Dadurch funktionieren AscensionEggs (nicht kaufbar, nur aus Rebirth)
-- ohne Sonderweg, und geschenkte Eier werden nicht doppelt bezahlt.
local function chargeForEgg(player: Player, eggType: Types.EggType): (boolean, Types.LocMsg?)
	local def = EggConfig.data[eggType]
	if not def then
		return false, Loc.msg("err.egg_unknown_type")
	end

	local data = PlayerService.getData(player)
	if not data then return false, Loc.msg("err.player_not_loaded") end

	local stock = data.island.eggStock[eggType] or 0
	if stock > 0 then
		data.island.eggStock[eggType] = stock - 1
		return true
	end

	if def.costGummies > 0 then
		return EconomyService.spendGummies(player, def.costGummies)
	end

	if def.costGoldGummies > 0 then
		return EconomyService.spendGoldGummies(player, def.costGoldGummies)
	end

	return false, Loc.msg("err.egg_not_buyable", { egg = Loc.msg("egg." .. eggType .. ".name") })
end

--------------------------------------------------------------------------------
-- Ei kaufen und Brut starten
--------------------------------------------------------------------------------

function EggService.startHatch(player: Player, eggType: Types.EggType)
	local data = PlayerService.getData(player)
	if not data then return end

	local slots = EggService.getSlotCount(data)
	if #data.island.hatchingEggs >= slots then
		fail(player, "RequestHatchEgg", Loc.msg("err.egg_slots_full", { slots = slots }))
		return
	end

	local success, reason = chargeForEgg(player, eggType)
	if not success then
		fail(player, "RequestHatchEgg", reason)
		return
	end

	local now      = os.time()
	local duration = EggService.getHatchDuration(data, eggType)

	local entry: Types.HatchingEgg = {
		uid       = newEggUid(),
		eggType   = eggType,
		startedAt = now,
		readyAt   = now + duration,
	}
	table.insert(data.island.hatchingEggs, entry)

	PlayerService.markDirty(player)
	PlayerService.saveNow(player)

	print("[EggService]", player.Name, "startet Brut:", eggType, "| fertig in", duration, "s")
end

--------------------------------------------------------------------------------
-- Fertiges Ei abholen
--------------------------------------------------------------------------------

function EggService.claimEgg(player: Player, eggUid: string)
	local data = PlayerService.getData(player)
	if not data then return end

	-- Index erst JETZT bestimmen — er darf nicht zwischengespeichert werden,
	-- weil jedes table.remove die Liste verschiebt.
	local slotIndex: number? = nil
	for index, candidate in data.island.hatchingEggs do
		if candidate.uid == eggUid then
			slotIndex = index
			break
		end
	end

	local entry = if slotIndex then data.island.hatchingEggs[slotIndex] else nil
	if not entry or not slotIndex then
		fail(player, "RequestClaimEgg", Loc.msg("err.egg_gone"))
		return
	end

	local remaining = entry.readyAt - os.time()
	if remaining > 0 then
		fail(player, "RequestClaimEgg", Loc.msg("err.egg_wait", { seconds = remaining }))
		return
	end

	-- Ein Ei-Typ, den es nicht mehr gibt, kommt aus einem alten Spielstand:
	-- startHatch laesst nur bekannte Typen herein, aber ein Ei kann jahrelang
	-- in hatchingEggs liegen und der Typ inzwischen aus EggConfig geflogen sein
	-- (genau das ist mit den Gebaeuden in v4 passiert). Ohne diese Pruefung
	-- wuerde getNormalizedTable unten assert-en: der Remote-Handler stirbt,
	-- der Spieler bekommt KEINE Fehlermeldung, und weil das Ei nie entfernt
	-- wird, ist der Brut-Slot dauerhaft blockiert. Also lieber sauber ablehnen.
	--
	-- Angenommene Entscheidung: der Slot wird geraeumt und der Spieler bekommt
	-- ein BasicEgg ins Lager. Ein stilles Loeschen waere Diebstahl, ein
	-- Dauer-Fehler waere ein blockierter Slot — der Ersatz ist der einzige
	-- Weg, der beides vermeidet.
	if not EggConfig.data[entry.eggType] then
		warn("[EggService] Unbekannter Ei-Typ im Spielstand:", player.Name, entry.eggType)

		table.remove(data.island.hatchingEggs, slotIndex)
		data.island.eggStock.BasicEgg = (data.island.eggStock.BasicEgg or 0) + 1

		PlayerService.markDirty(player)
		PlayerService.saveNow(player)

		fail(player, "RequestClaimEgg", Loc.msg("err.egg_type_gone", { egg = Loc.msg("egg.BasicEgg.name") }))
		return
	end

	-- Gacha-Roll
	local weightedTable = EggConfig.getNormalizedTable(entry.eggType)
	local entries: { GachaRoller.WeightedEntry } = {}
	for _, weighted in weightedTable do
		table.insert(entries, { configId = weighted.configId, weight = weighted.weight })
	end

	local wonConfigId = GachaRoller.roll(entries)

	-- ============================================================
	-- DER MUTATIONS-WURF
	-- ============================================================
	-- Das ist die EINZIGE Stelle im Spiel, an der ein Baerchi mit einer
	-- Mutation entstehen kann (die Fusion vererbt nur die hoehere der beiden
	-- weiter, siehe FusionService, Regel E). Bewusst hier und nicht in
	-- BaerchiFactory: dort wuerde jeder Aufruf wuerfeln — auch der
	-- Debug-Service und die Fusion.
	--
	-- Der Wurf ist UNABHAENGIG vom Gacha-Roll darueber: welcher Baerchi kommt
	-- und welche Mutation er hat, sind zwei getrennte Fragen. Ein Common kann
	-- Rainbow sein, ein Legendary ohne jede Mutation.
	local mutation = BaerchiConfig.rollMutation()

	-- Erst pruefen ob der Baerchi ueberhaupt erzeugbar ist — sonst waere
	-- das Ei bei einem Config-Tippfehler ersatzlos verloren.
	local newBaerchi = BaerchiFactory.create(wonConfigId, { mutation = mutation })
	if not newBaerchi then
		fail(player, "RequestClaimEgg", Loc.msg("err.egg_internal"))
		return
	end

	-- "Neu" = diese Art ist noch nicht auf der Insel
	local isNew = true
	for _, existing in data.island.baerchis do
		if existing.configId == wonConfigId then
			isNew = false
			break
		end
	end

	-- Slot leeren und Baerchi eintragen
	table.remove(data.island.hatchingEggs, slotIndex)
	data.island.baerchis[newBaerchi.uid] = newBaerchi

	-- Erster Baerchi ueberhaupt (oder der vorher ausgeruestete ist inzwischen
	-- weg): dann ruestet er sich automatisch aus, sonst bliebe der Plot leer.
	-- markDirty unten zieht den sichtbaren Neuaufbau selbst nach (die
	-- Struktur-Signatur in PlotDisplayService schliesst equippedUid mit ein).
	IslandService.autoEquipIfNone(data)

	local result: Types.HatchResult = {
		eggType = entry.eggType,
		baerchi = newBaerchi,
		isNew   = isNew,
	}

	Remotes.HatchResultReceived:FireClient(player, result)
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)

	print("[EggService]", player.Name, "hatched:", wonConfigId, "(", newBaerchi.rarity, ")",
		isNew and "| NEU" or "",
		mutation and ("| MUTATION: " .. mutation) or "")
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

		EggService.startHatch(player, eggType :: Types.EggType)
	end)

	RateLimiter.connect(Remotes.RequestClaimEgg, "RequestClaimEgg", function(player, eggUid: any)
		-- Nur noch uid (string). Eine Zahl waere ein alter Client — der wuerde
		-- ueber den Index claimen und damit genau den Fehler ausloesen, den
		-- die uid verhindert. Also still verwerfen statt hilfsweise deuten.
		if typeof(eggUid) ~= "string" then return end
		if #eggUid == 0 or #eggUid > 64 then return end

		EggService.claimEgg(player, eggUid)
	end)

	print("[EggService] Initialisiert")
end

return EggService
