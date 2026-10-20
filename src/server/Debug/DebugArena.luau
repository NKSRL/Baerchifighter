--!strict
-- DebugArena.luau
-- ServerScriptService/Debug/DebugArena.luau
--
-- Studio-Testbefehle: Arena und Pets: Speicherstand-Tests, Pet-Modus, Kampf, Waben, Jackpot.
-- Registriert sich beim require in DebugRegistry.commands; geladen nur von
-- DebugService.init() und nur in Studio (nie im Live-Spiel).

local ReplicatedStorage   = game:GetService("ReplicatedStorage")

local ServerScriptService = game:GetService("ServerScriptService")
local EventConfig      = require(ReplicatedStorage.Config.EventConfig)
local CombConfig       = require(ReplicatedStorage.Config.CombConfig)
local PlayerService  = require(ServerScriptService.Services.PlayerService)
local IslandService  = require(ServerScriptService.Services.IslandService)
local CombatService  = require(ServerScriptService.Services.CombatService)
local MapService     = require(ServerScriptService.Services.MapService)
local EventParticipationService = require(ServerScriptService.Services.EventParticipationService)
local ActivityLock = require(ServerScriptService.Util.ActivityLock)  -- Paket 1.1: Lock-Halter ausgeben
local PetModeService            = require(ServerScriptService.Services.PetModeService)
local PitArenaService           = require(ServerScriptService.Services.PitArenaService)
local CombService               = require(ServerScriptService.Services.CombService)
local CombRecyclerService       = require(ServerScriptService.Services.CombRecyclerService)
local PlayerMigration           = require(ServerScriptService.Util.PlayerMigration)
local JackpotRoll               = require(ServerScriptService.Util.JackpotRoll)
local DebugRegistry = require(script.Parent.DebugRegistry)

local commands = DebugRegistry.commands

-- v15: den aktuellen Spielstand in ein v14-Format zuruckverwandeln (Topf L7,
-- Presse L4, PIT 5, letzter Lauf Stage 12) und durch die Migration schicken —
-- das Ergebnis wird NICHT uebernommen, nur angezeigt (Migrations-Probe).
commands.v14save = function(_player, data)
	local HttpServiceLocal = game:GetService("HttpService")
	local copy = HttpServiceLocal:JSONDecode(HttpServiceLocal:JSONEncode(data))
	copy.version = 14
	copy.towers = nil
	copy.daily = nil
	copy.island.towerProgress = nil
	copy.island.pitRefund = nil
	copy.island.pitLevel = 5
	copy.island.pitProgress = { pitLevel = 5, reachedStage = 12 }
	copy.island.buildings.HoneyRefiner = nil
	copy.island.buildings.HoneyPot   = { id = "HoneyPot",   level = 7, honey = 4, lastProducedAt = os.time() }
	copy.island.buildings.HoneyPress = { id = "HoneyPress", level = 4, honey = 5, lastProducedAt = os.time() }
	local migrated = PlayerMigration.applyDefaults(copy)
	return {
		version   = migrated.version,
		veredler  = migrated.island.buildings.HoneyRefiner,
		erstattung = migrated.island.pitRefund,
		rekorde   = migrated.towers.records,
	}
end

commands.petmode = function(player, data)
	local pitPhase, stage = PitArenaService.getPhase(player)
	return {
		zuHause     = PetModeService.isHome(player),
		pit         = pitPhase,
		stage       = stage,
		event       = EventParticipationService.getPhase(player),
		-- Sammel-Update Paket 1.1: wer haelt die Figur gerade? (UFO-Einfrieren)
		lockHalter  = ActivityLock.owner(player) or "frei",
		entfuehrt   = EventParticipationService.isAbducting(player),
		towerProgress = data.island.towerProgress,
		eggStock    = data.island.eggStock,
		gummies     = data.gummies,
		lastEggAt   = data.island.lastEggAt,
	}
end

commands.pm = function(player, data, mode: any, resume: any)
	PetModeService.request(player, tostring(mode or "Home"), if resume then tostring(resume) :: any else nil)
	return commands.petmode(player, data)
end

-- 14.10. Test der Bewegung: Zustand, Position, Abstand zum Heimplatz.
--   D:Invoke("probe")
commands.probe = function(player, data)
	local FigurePlacement = require(ServerScriptService.Util.FigurePlacement)
	local uid = data.island.equippedUid
	local figure = if uid then MapService.getBaerchiModel(player, uid) else nil
	local homeFoot = MapService.getBaerchiHome(player)
	local foot = if figure then FigurePlacement.footOf(figure) else nil
	local baerchi = if uid then data.island.baerchis[uid] else nil
	local uids = {}
	for id, b in data.island.baerchis do table.insert(uids, id .. ":" .. b.configId .. ":L" .. b.level) end
	table.sort(uids)
	local pitPhase, stage = PitArenaService.getPhase(player)
	return {
		pit      = pitPhase,
		stage    = stage,
		event    = EventParticipationService.getPhase(player),
		lock     = ActivityLock.owner(player),
		equipped = uid,
		hp       = if baerchi then baerchi.currentHp else nil,
		level    = if baerchi then baerchi.level else nil,
		gummies  = data.gummies,
		won      = data.stats.totalFightsWon,
		lost     = data.stats.totalFightsLost,
		foot     = if foot then string.format("%.1f, %.1f, %.1f", foot.X, foot.Y, foot.Z) else nil,
		toHome   = if foot and homeFoot then math.floor((foot - homeFoot).Magnitude * 10) / 10 else nil,
		figure   = if figure then figure.Name else nil,
		bears    = uids,
	}
end

-- Ausruesten wie ueber die Inventar-Oberflaeche.   D:Invoke("equipbear", uid)
commands.equipbear = function(player, data, uid: any)
	local IslandService = require(ServerScriptService.Services.IslandService)
	IslandService.equipBaerchi(player, tostring(uid))
	return commands.probe(player, data)
end

commands.fight = function(player, _data, uid: any)
	CombatService.startPitRun(player, tostring(uid))
	return commands.info(player, PlayerService.getDataOrError(player))
end

-- Alle Honig-Lager sofort fuellen (umgeht die Wartezeit).
-- Ohne das dauert jeder Level-Test 20 Sekunden pro Honig.

-- v15: Waben im Event-Pit legen und Zustand ausgeben
commands.combs = function(player, data, n: any)
	local count = if typeof(n) == "number" then math.clamp(math.floor(n), 0, 100) else 0
	if count > 0 then
		CombService.debugSpawn(count)
	end

	local recycler = data.island.recycler
	local slots = CombService.getSlotInfo()
	return {
		wabenImPit    = CombService.getWorldCount(),
		getragen      = CombService.getCarriedCount(player),
		getragenAlle  = slots.held,
		respawnQueue  = slots.queued,
		slotLimit     = slots.limit,
		recyclerLevel = recycler.level,
		warteschlange = recycler.queued,
	}
end

-- v17: naechsten UFO-Abwurf als Jackpot erzwingen; Stand des Pity-Zaehlers
commands.jackpot = function(_player, _data)
	JackpotRoll.ufo.forceNext = true
	return {
		naechsterIstJackpot = true,
		abwuerfeSeitJackpot = JackpotRoll.ufo.sinceLast,
		abwuerfeGesamt      = JackpotRoll.ufo.total,
		jackpotsGesamt      = JackpotRoll.ufo.jackpots,
		pity                = EventConfig.UFO.JACKPOT_PITY_DROPS,
	}
end

-- v17: Wabenthema setzen ("off" = normal)
commands.combtheme = function(_player, _data, themeId: any)
	local id = if typeof(themeId) == "string" and themeId ~= "off" then themeId else nil
	CombService.setTheme(id)
	local slots = CombService.getSlotInfo()
	return { thema = CombService.getTheme() or "normal", wabenImPit = slots.world, slotLimit = slots.limit }
end

-- v17: Waben einfliegen lassen (wie ein Vulkan-Ausbruch aus der Pit-Mitte)
commands.launch = function(_player, _data, n: any)
	local count = if typeof(n) == "number" then math.clamp(math.floor(n), 1, 30) else 10
	local origin = MapService.getEventPitPosition() + Vector3.new(0, 2, 0)
	return { gestartet = CombService.launchCombs(count, origin), slots = CombService.getSlotInfo() }
end

-- v15: Wabeneinheiten direkt in die Warteschlange des Recyclers legen
commands.queue = function(player, data, n: any)
	local units = if typeof(n) == "number" then math.clamp(math.floor(n), 0, 100000) else 0
	if units > 0 then
		CombRecyclerService.deposit(player, units)
	end

	local recycler = data.island.recycler
	return {
		warteschlange = recycler.queued,
		level         = recycler.level,
		gummies       = data.gummies,
	}
end

-- v15: Recycler-Level direkt setzen (ohne Kosten)
commands.recycler = function(player, data, level: any)
	local recycler = data.island.recycler
	if typeof(level) == "number" then
		recycler.level = CombConfig.clampLevel(level)
		PlayerService.markDirty(player)
	end

	return {
		level         = recycler.level,
		gummiesJeEinheit = CombConfig.getPayPerUnit(recycler.level),
		einheitenProSek  = CombConfig.getSpeed(recycler.level),
		warteschlange = recycler.queued,
	}
end

return {}
