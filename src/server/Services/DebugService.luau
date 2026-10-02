--!strict
-- DebugService.luau
-- ServerScriptService/Services/DebugService.luau
--
-- Einzige Zustaendigkeit:
--   - Test-Befehle aus der Studio Command Bar entgegennehmen
--
-- NUR IN STUDIO. Im veroeffentlichten Spiel macht init() nichts und die
-- BindableFunction existiert nicht.
--
-- Warum eine BindableFunction und nicht einfach _G oder ein require?
--   Die Command Bar laeuft in einem eigenen Lua-VM. Sie hat deshalb
--     * ihren eigenen require-Cache  → require(PlayerService) liefert dort eine
--       ZWEITE, nie initialisierte Kopie mit leerem _playerData, und
--     * ihr eigenes _G               → im Server gesetzte Globals sind unsichtbar.
--   Aufrufe auf der Kopie laufen still ins Leere, was beim Testen extrem
--   verwirrend ist. Eine BindableFunction ist eine Instanz im DataModel:
--   ihr OnInvoke wurde vom echten Server-Script gesetzt und laeuft daher
--   garantiert im echten Server-VM, mit dem echten Zustand.
--
-- Benutzung (Command Bar, Server-Kontext, Play laeuft):
--   local D = game.ServerScriptService.RBLDebug
--   D:Invoke("info")
--   D:Invoke("give", 100000, 1000)
--   D:Invoke("add", "RedBaerchi", 10)
--   D:Invoke("add", "RedBaerchi", 10, "Rainbow")   -- Mutation (siehe BaerchiConfig.MUTATIONS)
--   D:Invoke("stats", uid)                    -- Kampfwerte inkl. PWR
--   D:Invoke("list")
--   D:Invoke("fuse", uidA, uidB)
--   D:Invoke("recycle", uid)
--   D:Invoke("building", "Beehive", 5)
--   D:Invoke("pit", 5)
--   D:Invoke("hatch", "BasicEgg")   -- legt ein Ei und macht es sofort fertig
--   D:Invoke("claim")               -- holt das erste fertige Ei
--   D:Invoke("honey")               -- alle Honig-Lager sofort voll
--   D:Invoke("feed", uid, 20)       -- 20x fuettern (heilt + gibt XP)
--   D:Invoke("fight", uid)          -- kompletter PIT-Lauf ueber alle Stages
--   D:Invoke("rebirth")
--
-- v8 (Promotion / Charms / Event-Teilnahme):
--   D:Invoke("promote", uid)        -- braucht genug Duplikate, siehe "add"
--   D:Invoke("charms", uid)         -- alle acht Slots im Klartext
--   D:Invoke("roll", uid, 5)        -- 5x wuerfeln (kostet GoldGummies)
--   D:Invoke("lock", uid, 1)        -- Slot I sperren/freigeben
--   D:Invoke("event")               -- ausgeruesteten Baerchi zum Event schicken
--   D:Invoke("skipevent")           -- laufende Phase sofort beenden
--   D:Invoke("events")              -- Katalog: alle Events mit ihrer Belohnung
--   D:Invoke("startevent", "ZauberZirkel")  -- genau dieses Event sofort starten
--
-- v10 (Eier legen):
--   D:Invoke("eggs")            -- was liegt herum, wie schnell legt er, welche Chancen
--   D:Invoke("lay", 5)          -- 5 Eier sofort legen (ohne aufs Intervall zu warten)
--   D:Invoke("collect")         -- alles einsammeln
--   D:Invoke("eggtime", 60)     -- Zeitmarke 60 Minuten zurueck, Tick legt nach
--
-- Ein kompletter Event-Durchlauf ohne acht Minuten Wartezeit:
--   D:Invoke("skipevent")   → Pause endet, Event laeuft
--   D:Invoke("event")       → Baerchi laeuft hin (ein paar Sekunden abwarten)
--   D:Invoke("skipevent")   → Event endet, Stat-Stufe wird vergeben
--
-- Rueckgaben sind einfache Tabellen/Zahlen — BindableFunctions kopieren
-- Werte ueber die VM-Grenze, Funktionen und Metatables kommen nicht durch.

local Players             = game:GetService("Players")
local RunService          = game:GetService("RunService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types            = require(ReplicatedStorage.Network.Types)
local EconomyConfig    = require(ReplicatedStorage.Config.EconomyConfig)
local BuildingBehavior = require(ReplicatedStorage.Config.BuildingBehavior)
local EggConfig        = require(ReplicatedStorage.Config.EggConfig)
local EventConfig      = require(ReplicatedStorage.Config.EventConfig)
local CharmConfig      = require(ReplicatedStorage.Config.CharmConfig)
local BaerchiConfig    = require(ReplicatedStorage.Config.BaerchiConfig)
local BaerchiFactory   = require(ReplicatedStorage.Modules.BaerchiFactory)
local CombatCalculator = require(ReplicatedStorage.Modules.CombatCalculator)
local EggCalculator    = require(ReplicatedStorage.Modules.EggCalculator)

local PlayerService  = require(ServerScriptService.Services.PlayerService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local IslandService  = require(ServerScriptService.Services.IslandService)
local EggService     = require(ServerScriptService.Services.EggService)
local CombatService  = require(ServerScriptService.Services.CombatService)
local FusionService  = require(ServerScriptService.Services.FusionService)
local RecycleService = require(ServerScriptService.Services.RecycleService)
local RebirthService = require(ServerScriptService.Services.RebirthService)
local HoneyService   = require(ServerScriptService.Services.HoneyService)
local MapService     = require(ServerScriptService.Services.MapService)

-- v8
local PromotionService          = require(ServerScriptService.Services.PromotionService)
local CharmService              = require(ServerScriptService.Services.CharmService)
local EventService              = require(ServerScriptService.Services.EventService)
local EventParticipationService = require(ServerScriptService.Services.EventParticipationService)

-- v10
local EggLayService             = require(ServerScriptService.Services.EggLayService)

local DebugService = {}

local BINDABLE_NAME = "RBLDebug"

--------------------------------------------------------------------------------
-- Hilfsfunktionen
--------------------------------------------------------------------------------

-- Der erste Spieler im Server. Fuer Solo-Tests in Studio genau richtig.
local function firstPlayer(): Player?
	return Players:GetPlayers()[1]
end

local function requireData(): (Player?, Types.PlayerData?, string?)
	local player = firstPlayer()
	if not player then
		return nil, nil, "Kein Spieler im Spiel — laeuft der Play-Modus?"
	end

	local data = PlayerService.getData(player)
	if not data then
		return player, nil, "Daten fuer " .. player.Name .. " noch nicht geladen"
	end

	return player, data, nil
end

local function countBaerchis(data: Types.PlayerData): number
	local n = 0
	for _ in data.island.baerchis do n += 1 end
	return n
end

--------------------------------------------------------------------------------
-- Befehle
--------------------------------------------------------------------------------

local commands: { [string]: (Player, Types.PlayerData, ...any) -> any } = {}

commands.info = function(player, data)
	local buildings: { [string]: number } = {}
	for id, building in data.island.buildings do
		buildings[id] = building.level
	end

	return {
		player       = player.Name,
		gummies      = data.gummies,
		goldGummies  = data.goldGummies,
		rebirthCount = data.rebirthCount,
		rebirthMult  = data.rebirthMult,
		pitLevel     = data.island.pitLevel,
		baerchis     = countBaerchis(data),
		hatching     = #data.island.hatchingEggs,
		hatchSlots   = EggService.getSlotCount(data),
		buildings    = buildings,
		eggStock     = data.island.eggStock,
	}
end

-- Waehrung schenken. Ohne rebirthMult, du bekommst exakt die Zahl.
commands.give = function(player, _data, gummies: any, gold: any)
	EconomyService.awardGummiesFlat(player, tonumber(gummies) or 100000)
	EconomyService.awardGoldGummies(player, tonumber(gold) or 1000)
	return commands.info(player, PlayerService.getDataOrError(player))
end

-- Alle Baerchis als flache Liste (uid zum Weiterverwenden)
commands.list = function(_player, data)
	local out = {}
	for uid, baerchi in data.island.baerchis do
		table.insert(out, {
			uid      = uid,
			configId = baerchi.configId,
			rarity   = baerchi.rarity,
			level    = baerchi.level,
			xp       = baerchi.xp,
			fusion   = baerchi.isFusionResult,
			bonus    = baerchi.fusionBonus,

			-- v8: die zweite Fortschrittsachse. `charms` bewusst nur als Anzahl
			-- — die Detailwerte holt man sich ueber "charms <uid>", sonst wird
			-- die Liste in der Command Bar unlesbar.
			promo    = baerchi.promotionLevel or 0,
			stats    = baerchi.statLevels,
			charms   = #(baerchi.charms or {}),
			mutation = baerchi.mutation,
		})
	end
	table.sort(out, function(a, b) return a.uid < b.uid end)
	return out
end

-- Baerchi direkt erzeugen, ohne Ei.
--
-- Das dritte Argument setzt eine Mutation (siehe BaerchiConfig.MUTATIONS fuer
-- gueltige Namen: Gold/Diamond/Bloodrot/Celestial/Candy/Lava/Galaxy/Rainbow).
-- Ohne diesen Weg waeren Mutationen in Studio praktisch nicht testbar: die
-- Gesamtchance beim Schluepfen liegt bei 1.5%, die seltenste Stufe (Rainbow)
-- bei 0.0005% — man muesste also im Schnitt 200'000 Eier ausbrueten.
--   D:Invoke("add", "RedBaerchi", 10)              -- normal
--   D:Invoke("add", "RedBaerchi", 10, "Rainbow")   -- mit Mutation
commands.add = function(player, data, configId: any, level: any, mutation: any)
	local mutationId: any = nil
	if typeof(mutation) == "string" and BaerchiConfig.MUTATIONS[mutation :: any] then
		mutationId = mutation
	end

	local baerchi = BaerchiFactory.create(tostring(configId), {
		level    = tonumber(level) or 1,
		mutation = mutationId,
	})
	if not baerchi then
		return { error = "Unbekannter configId: " .. tostring(configId) }
	end

	data.island.baerchis[baerchi.uid] = baerchi
	PlayerService.markDirty(player)

	return {
		uid      = baerchi.uid,
		configId = baerchi.configId,
		rarity   = baerchi.rarity,
		level    = baerchi.level,
		mutation = baerchi.mutation,
	}
end

-- Die Kampfwerte eines Baerchis so, wie der Kampf sie sieht. Praktisch, um
-- Promotion, Stat-Stufen, Charms und Mutation gegeneinander nachzurechnen.
commands.stats = function(_player, data, uid: any)
	local baerchi = data.island.baerchis[tostring(uid)]
	if not baerchi then
		return { error = "Baerchi nicht gefunden: " .. tostring(uid) }
	end

	local def = BaerchiConfig.getById(baerchi.configId)
	if not def then
		return { error = "Unbekannter configId: " .. baerchi.configId }
	end

	local stats = CombatCalculator.getEffectiveStats(baerchi, def.baseStats)

	return {
		configId = baerchi.configId,
		level    = baerchi.level,
		mutation = baerchi.mutation,
		promo    = baerchi.promotionLevel or 0,
		maxHp    = stats.maxHp,
		atk      = stats.atk,
		spd      = stats.spd,
		pwrProzent = math.floor(stats.pwr * 100 + 0.5),
		skill    = stats.skillId,
	}
end

-- Gebaeude-Level direkt setzen (umgeht die Kosten)
commands.building = function(player, data, buildingId: any, level: any)
	local building = data.island.buildings[buildingId]
	if not building then
		return { error = "Unbekanntes Gebaeude: " .. tostring(buildingId) }
	end

	-- clampBuildingLevel rundet mit ab: ohne das landete eine 5.5 aus der
	-- Command Bar als Kommazahl in den Daten und jedes spaetere
	-- string.format("%d", level) wuerde daran scheitern.
	building.level = EconomyConfig.clampBuildingLevel(tonumber(level) or 1)
	MapService.updateBuildingLevel(player, buildingId, building.level)
	PlayerService.markDirty(player)

	return { building = buildingId, level = building.level }
end

-- PIT-Level direkt setzen (umgeht die Kosten) und Plattform neu bauen
commands.pit = function(player, data, level: any)
	data.island.pitLevel = math.clamp(tonumber(level) or 1, 1, EconomyConfig.MAX_PIT_LEVEL)
	MapService.updatePitLevel(player, data.island.pitLevel)
	PlayerService.markDirty(player)

	return { pitLevel = data.island.pitLevel }
end

-- Ei in einen Brut-Slot legen und den Timer sofort ablaufen lassen
commands.hatch = function(player, data, eggType: any)
	local egg = tostring(eggType or "BasicEgg")
	if not EggConfig.data[egg :: Types.EggType] then
		return { error = "Unbekannter Egg-Typ: " .. egg }
	end

	-- Bestand aufstocken damit der Kauf nie an Gummies scheitert
	data.island.eggStock[egg :: Types.EggType] = (data.island.eggStock[egg :: Types.EggType] or 0) + 1

	-- Vorher merken wie viele Eier drin lagen. startHatch legt bei vollen
	-- Slots naemlich gar nichts an — ohne diesen Vergleich wuerde die Zeile
	-- unten das LETZTE bereits bruetende Ei sofort fertig machen, also ein
	-- fremdes Ei kaputt testen.
	local before = #data.island.hatchingEggs
	EggService.startHatch(player, egg :: Types.EggType)

	if #data.island.hatchingEggs == before then
		return { error = "Alle Brut-Slots belegt — erst 'claim' aufrufen" }
	end

	local slot = data.island.hatchingEggs[#data.island.hatchingEggs]
	if slot then
		slot.readyAt = os.time() - 1   -- sofort abholbereit
		PlayerService.markDirty(player)
	end

	return {
		slots   = #data.island.hatchingEggs,
		hinweis = "jetzt 'claim' aufrufen — ohne Argument wird das aelteste fertige Ei geholt",
	}
end

-- Ohne Argument: das ERSTE fertige Ei. Der Debug-Befehl soll bequem sein, und
-- ueber eine uid abzutippen waere er das nicht. Mit Argument geht auch die uid,
-- damit sich ein konkreter Slot gezielt testen laesst.
commands.claim = function(player, data, eggUid: any)
	if eggUid ~= nil then
		EggService.claimEgg(player, tostring(eggUid))
		return commands.list(player, PlayerService.getDataOrError(player))
	end

	local now = os.time()
	for _, egg in data.island.hatchingEggs do
		if now >= egg.readyAt then
			EggService.claimEgg(player, egg.uid)
			return commands.list(player, PlayerService.getDataOrError(player))
		end
	end

	return { error = "Kein fertiges Ei da — erst 'hatch' aufrufen" }
end

commands.fight = function(player, _data, uid: any)
	CombatService.startPitRun(player, tostring(uid))
	return commands.info(player, PlayerService.getDataOrError(player))
end

-- Alle Honig-Lager sofort fuellen (umgeht die Wartezeit).
-- Ohne das dauert jeder Level-Test 20 Sekunden pro Honig.
commands.honey = function(player, data)
	local filled: { [string]: number } = {}

	for _, building in data.island.buildings do
		-- Lager DIESES Gebaeudes auf DIESEM Level: der Bienenstock fasst seit
		-- v7 mehr als die anderen beiden.
		building.honey          = BuildingBehavior.getCapacity(building.id, building.level)
		building.lastProducedAt = os.time()
		filled[building.id]     = building.honey
	end

	PlayerService.markDirty(player)
	return { honey = filled }
end

-- Einen Baerchi fuettern (heilt + gibt XP), so oft wie angegeben
commands.feed = function(player, _data, uid: any, times: any)
	local count = math.clamp(tonumber(times) or 1, 1, 100)

	for _ = 1, count do
		HoneyService.feed(player, tostring(uid))
	end

	return commands.list(player, PlayerService.getDataOrError(player))
end

-- Fusion. Die beiden letzten Argumente sind der Sperr-Schritt aus dem
-- Fusions-Menue (siehe FusionService, Regel C) und duerfen weggelassen werden —
-- dann laeuft alles automatisch.
--   D:Invoke("fuse", uidA, uidB)                   -- alles automatisch
--   D:Invoke("fuse", uidA, uidB, "ability", "B")   -- Skill kommt von B
commands.fuse = function(player, _data, uidA: any, uidB: any, lockedProperty: any, lockedFrom: any)
	local property = if lockedProperty ~= nil then tostring(lockedProperty) else nil
	local from     = if lockedFrom ~= nil then tostring(lockedFrom) else nil

	FusionService.fuse(player, tostring(uidA), tostring(uidB), property :: any, from :: any)
	return commands.list(player, PlayerService.getDataOrError(player))
end

--------------------------------------------------------------------------------
-- v8: Promotion, Charms, Event-Teilnahme
--------------------------------------------------------------------------------

-- Befoerdern. Legt die noetigen Duplikate NICHT selbst an — wer testen will,
-- ruft vorher mehrfach "add <configId>" auf. Genau so merkt man, ob die
-- Material-Pruefung tut, was sie soll.
commands.promote = function(player, _data, uid: any)
	PromotionService.promote(player, tostring(uid))
	return commands.list(player, PlayerService.getDataOrError(player))
end

-- Charms wuerfeln. Kostet echte GoldGummies — vorher "give 0 100000".
commands.roll = function(player, _data, uid: any, times: any)
	CharmService.rollCharms(player, tostring(uid), tonumber(times) or 1)
	return commands.charms(player, PlayerService.getDataOrError(player), uid)
end

-- Alle acht Slots eines Baerchis im Klartext.
commands.charms = function(_player, data, uid: any)
	local baerchi = data.island.baerchis[tostring(uid)]
	if not baerchi then
		return { error = "Baerchi nicht gefunden: " .. tostring(uid) }
	end

	local bySlot: { [number]: any } = {}
	for _, charm in baerchi.charms or {} do
		bySlot[charm.slot] = charm
	end

	local out = {}
	for slot = 1, CharmConfig.SLOT_COUNT do
		local charm = bySlot[slot]
		out[slot] = {
			slot     = CharmConfig.SLOT_NUMERALS[slot],
			offen    = CharmConfig.isSlotUnlocked(slot, baerchi.promotionLevel or 0),
			abPromo  = CharmConfig.getUnlockPromotion(slot),
			rarity   = if charm then charm.rarity else nil,
			effekt   = if charm then CharmConfig.describe(charm) else nil,
			gesperrt = if charm then charm.locked else nil,
		}
	end

	return { promotion = baerchi.promotionLevel or 0, slots = out }
end

-- Einen Charm-Slot sperren/freigeben.
commands.lock = function(player, _data, uid: any, slot: any)
	CharmService.toggleLock(player, tostring(uid), tonumber(slot) or 1)
	return commands.charms(player, PlayerService.getDataOrError(player), uid)
end

-- Den ausgeruesteten Baerchi zum Event schicken bzw. zurueckholen.
commands.event = function(player, _data)
	EventParticipationService.sendToEvent(player)
	return { unterwegs = true }
end

commands.recall = function(player, _data)
	EventParticipationService.recall(player)
	return { unterwegs = true }
end

--------------------------------------------------------------------------------
-- v10: Eier legen
--------------------------------------------------------------------------------

-- Legt sofort ein Ei, ohne auf das Intervall zu warten. Mehrfach aufrufen, um
-- den Plot zu fuellen und die Obergrenze zu pruefen.
commands.lay = function(player, _data, times: any)
    local count  = math.clamp(tonumber(times) or 1, 1, 30)
    local laid   = 0

    for _ = 1, count do
        if EggLayService.layNow(player) then
            laid += 1
        else
            break   -- Obergrenze erreicht oder kein Baerchi ausgeruestet
        end
    end

    return commands.eggs(player, PlayerService.getDataOrError(player))
end

-- Was gerade herumliegt, plus die Werte des ausgeruesteten Legers.
commands.eggs = function(_player, data)
    local out = {}
    for _, egg in data.island.laidEggs or {} do
        table.insert(out, { uid = egg.uid, typ = egg.eggType })
    end

    local uid     = data.island.equippedUid
    local baerchi = if uid then data.island.baerchis[uid] else nil

    local rate: any = "kein Baerchi ausgeruestet"
    local chancen: any = nil

    if baerchi then
        local online  = EggCalculator.getLayIntervalSeconds(baerchi, false)
        local offline = EggCalculator.getLayIntervalSeconds(baerchi, true)

        rate = {
            configId       = baerchi.configId,
            level          = baerchi.level,
            eggStufe       = (baerchi.statLevels :: any).egg or 0,
            mutation       = baerchi.mutation,
            sekundenOnline = if online then math.floor(online + 0.5) else nil,
            sekundenOffline= if offline then math.floor(offline + 0.5) else nil,
        }

        chancen = {}
        for _, chance in EggCalculator.getChances(baerchi) do
            table.insert(chancen, string.format("%s %.0f%%", chance.eggType, chance.percent))
        end
    end

    return {
        liegen  = #out,
        maximum = EggConfig.MAX_UNCOLLECTED_EGGS,
        eier    = out,
        lager   = data.island.eggStock,
        leger   = rate,
        chancen = chancen,
    }
end

-- Alle herumliegenden Eier einsammeln (dasselbe wie der Knopf auf der Karte).
commands.collect = function(player, _data)
    EggLayService.collectAll(player)
    return commands.eggs(player, PlayerService.getDataOrError(player))
end

-- Die Zeitmarke kuenstlich in die Vergangenheit setzen und danach nachrechnen
-- lassen — so laesst sich das OFFLINE-Nachholen pruefen, ohne den Server zu
-- verlassen. Der naechste Tick (max. 5s) legt dann die faelligen Eier.
--
-- Achtung: der Tick rechnet mit der ONLINE-Rate. Das echte Offline-Verhalten
-- (langsamer, siehe EggConfig.OFFLINE_SLOWDOWN) sieht man nur beim Rejoin.
commands.eggtime = function(player, data, minutes: any)
    local back = math.clamp(tonumber(minutes) or 30, 1, 10000)
    data.island.lastEggAt = os.time() - back * 60
    PlayerService.markDirty(player)

    return { zurueckgestellt = back .. " Minuten", hinweis = "naechster Tick legt nach (max. 5s)" }
end

-- Die laufende Phase sofort beenden. Zweimal aufgerufen bekommt man also aus
-- der Pause heraus ein vollstaendiges Event samt Belohnung, ohne acht Minuten
-- zu warten:
--   D:Invoke("skipevent")   -- Pause vorbei, Event laeuft
--   D:Invoke("event")       -- Baerchi hinschicken, ankommen lassen
--   D:Invoke("skipevent")   -- Event vorbei → Stat-Stufe wird vergeben
commands.skipevent = function(_player, _data)
	EventService.skipPhase()

	local active = EventService.getActive()
	return {
		laeuftJetzt  = if active then active.displayName else "Pause",
		belohnung    = if active then EventConfig.describeReward(active) else nil,
		naechstes    = EventService.getNext().displayName,
		restSekunden = EventService.getRemainingSeconds(),
	}
end

-- Der ganze Katalog mit Belohnung, in der Reihenfolge, in der die Events
-- laufen. Praktisch, um die ids fuer "startevent" nachzuschlagen.
commands.events = function(_player, _data)
	local katalog = {}
	for index, def in EventConfig.EVENTS do
		table.insert(katalog, string.format(
			"%d. %s (%s) — %s",
			index, def.displayName, def.id, EventConfig.describeReward(def)
		))
	end

	local active = EventService.getActive()
	return {
		laeuftJetzt  = if active then active.displayName else "Pause",
		restSekunden = EventService.getRemainingSeconds(),
		naechstes    = EventService.getNext().displayName,
		takt         = string.format(
			"%ds Event / %ds Pause",
			EventConfig.EVENT_DURATION_SECONDS, EventConfig.EVENT_GAP_SECONDS
		),
		katalog      = katalog,
	}
end

-- Ein BESTIMMTES Event sofort starten, statt sich durch den Zyklus zu warten.
-- Ein voller Durchlauf durch alle zehn Events dauert 80 Minuten — ohne diesen
-- Befehl waere z.B. der Mutations-Sturm praktisch nicht testbar.
--
-- Laeuft gerade ein anderes Event, wird es vorher ordentlich beendet (die
-- Anwesenden bekommen also noch ihre Belohnung, siehe EventService.startById).
commands.startevent = function(_player, _data, id: any)
	local eventId = tostring(id or "")

	if not EventService.startById(eventId) then
		local ids = {}
		for _, def in EventConfig.EVENTS do
			table.insert(ids, def.id)
		end
		return { error = "Unbekannte Event-id: " .. eventId, verfuegbar = ids }
	end

	local active = EventService.getActive()
	return {
		gestartet    = if active then active.displayName else "?",
		belohnung    = if active then EventConfig.describeReward(active) else nil,
		restSekunden = EventService.getRemainingSeconds(),
		hinweis      = "jetzt 'event' aufrufen, um den Baerchi hinzuschicken — er muss beim ENDE dort stehen",
	}
end

commands.recycle = function(player, _data, uid: any)
	RecycleService.recycle(player, tostring(uid))
	return commands.info(player, PlayerService.getDataOrError(player))
end

commands.upgrade = function(player, _data, buildingId: any)
	IslandService.upgradeBuilding(player, buildingId)
	return commands.info(player, PlayerService.getDataOrError(player))
end

commands.rebirth = function(player, _data)
	RebirthService.rebirth(player)
	return commands.info(player, PlayerService.getDataOrError(player))
end

commands.help = function()
	return {
		"info", "give <gummies> <gold>", "list",
		"add <configId> <level> [mutation]", "stats <uid>",
		"building <id> <level>", "pit <level>",
		"hatch <eggType>", "claim [eggUid]", "honey", "feed <uid> <times>",
		"fight <uid>",
		"fuse <uidA> <uidB> [ability|level|eggs] [A|B]",
		"recycle <uid>", "upgrade <buildingId>", "rebirth",

		-- v8
		"promote <uid>", "charms <uid>", "roll <uid> [anzahl]", "lock <uid> <slot>",
		"event", "recall", "skipevent", "events", "startevent <eventId>",

		-- v10
		"eggs", "lay [anzahl]", "collect", "eggtime <minuten>",
	}
end

--------------------------------------------------------------------------------
-- Initialisierung
--------------------------------------------------------------------------------

function DebugService.init()
	if not RunService:IsStudio() then
		return   -- im Live-Spiel gibt es diesen Service schlicht nicht
	end

	local existing = ServerScriptService:FindFirstChild(BINDABLE_NAME)
	if existing then existing:Destroy() end

	local bindable = Instance.new("BindableFunction")
	bindable.Name   = BINDABLE_NAME
	bindable.Parent = ServerScriptService

	bindable.OnInvoke = function(command: any, ...)
		local name = tostring(command or "help")
		local handler = commands[name]
		if not handler then
			return { error = "Unbekannter Befehl: " .. name, verfuegbar = commands.help() }
		end

		if name == "help" then
			return commands.help()
		end

		local player, data, reason = requireData()
		if not player or not data then
			return { error = reason }
		end

		local ok, result = pcall(handler, player, data, ...)
		if not ok then
			return { error = tostring(result) }
		end
		return result
	end

	print("[DebugService] Initialisiert | Command Bar: game.ServerScriptService." .. BINDABLE_NAME .. ":Invoke(\"help\")")
end

return DebugService
