--!strict
-- DebugEvents.luau
-- ServerScriptService/Debug/DebugEvents.luau
--
-- Studio-Testbefehle: Events, Eier legen, Umbau, Rebirth.
-- Registriert sich beim require in DebugRegistry.commands; geladen nur von
-- DebugService.init() und nur in Studio (nie im Live-Spiel).

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local EggConfig        = require(ReplicatedStorage.Config.EggConfig)
local EventConfig      = require(ReplicatedStorage.Config.EventConfig)
local Loc = require(ReplicatedStorage.Localization.Loc)   -- Belohnung ist eine LocMsg
local EggCalculator    = require(ReplicatedStorage.Modules.EggCalculator)
local PlayerService  = require(ServerScriptService.Services.PlayerService)
local IslandService  = require(ServerScriptService.Services.IslandService)
local RecycleService = require(ServerScriptService.Services.RecycleService)
local RebirthService = require(ServerScriptService.Services.RebirthService)
local EventService              = require(ServerScriptService.Services.EventService)
local EventParticipationService = require(ServerScriptService.Services.EventParticipationService)
local EggLayService             = require(ServerScriptService.Services.EggLayService)
local DebugRegistry = require(script.Parent.DebugRegistry)

local commands = DebugRegistry.commands

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
		belohnung    = if active then Loc.resolve(EventConfig.describeReward(active)) else nil,
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
			index, def.displayName, def.id, Loc.resolve(EventConfig.describeReward(def))
		))
	end

	local active = EventService.getActive()
	return {
		laeuftJetzt  = if active then active.displayName else "Pause",
		restSekunden = EventService.getRemainingSeconds(),
		naechstes    = EventService.getNext().displayName,
		takt         = string.format(
			"individuelle Dauer je Event / %ds Pause",
			EventConfig.EVENT_GAP_SECONDS
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
		belohnung    = if active then Loc.resolve(EventConfig.describeReward(active)) else nil,
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

--------------------------------------------------------------------------------
-- v14: Ei-Baum
--------------------------------------------------------------------------------

return {}
