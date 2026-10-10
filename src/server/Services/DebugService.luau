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
--   D:Invoke("building", "Beehive", 5)   -- Level 1-60 (v15), Look folgt automatisch
--   D:Invoke("building", "HoneyRefiner", 60)
--   D:Invoke("hatch", "BasicEgg")   -- legt ein Ei ins Lager und oeffnet es sofort (v12)
--   D:Invoke("egg", "GoldenEgg", 5) -- 5 Eier ins Lager legen (ohne zu oeffnen)
--   D:Invoke("pitprogress", 12)     -- letzten Lauf im gewaehlten Tower auf Stage 12 setzen (Fortsetzungs-Test)
--   D:Invoke("petmode")             -- aktueller Zustand der Pet-Leiste
--   D:Invoke("pm", "Fight", "Last")  -- wie ein Klick auf die Pet-Leiste
--   D:Invoke("honey")               -- alle Honig-Lager sofort voll
--   D:Invoke("feed", uid, 20)       -- 20x fuettern (heilt + gibt XP)
--   D:Invoke("fight", uid)          -- kompletter Lauf im gewaehlten Tower
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
-- v15 (Waben im Event-Pit, Recycler):
--   D:Invoke("combs", 20)           -- 20 Waben sofort ins Pit legen (Stand ausgeben)
--   D:Invoke("queue", 50)           -- 50 Wabeneinheiten in die Recycler-Warteschlange
--   D:Invoke("recycler", 5)         -- Recycler-Level setzen (ohne Kosten), Stand ausgeben
--
-- v15 (Tower, Gebaeude 1-60, Angeben, Login-Bonus):
--   D:Invoke("tower", "II", 20)     -- Tower II waehlen und ab Stage 20 kaempfen (Fortsetzung gratis)
--   D:Invoke("towerrecord", "III", 45) -- Rekord setzen (Meilensteine bis dorthin werden ausgezahlt)
--   D:Invoke("rebirthcap")          -- Deckel des aktuellen Rebirths in allen Towern
--   D:Invoke("stagebest", "I", 30)  -- Sammel-Update: beste Stage dieses Lebens (Rebirth-Bedingung)
--   D:Invoke("incubator", "done")   -- Sammel-Update: Inkubator-Stand, "done" = alle Eier fertig
--   D:Invoke("incubator", "breed")  -- INCUBATOR_BREED: jedes Baerchi im Inkubator bruetet sofort ein Ei
--   D:Invoke("dailyshift", 1)       -- Login-Bonus: so tun, als waeren 1 Tag(e) vergangen
--   D:Invoke("lbflush")             -- Bestenlisten sofort schreiben und neu lesen
--   D:Invoke("parts")               -- Teile auf der eigenen Insel zaehlen (Budget 250)
--   D:Invoke("v14save")             -- Spielstand im alten v14-Format simulieren + migrieren
--
-- v17 (lebendige Events):
--   D:Invoke("startevent", "Ufo")   -- UFO-Patrouille mit Abwuerfen
--   D:Invoke("jackpot")             -- naechster UFO-Abwurf ist sicher ein Jackpot (Stand des Pity-Zaehlers)
--   D:Invoke("combtheme", "HotEgg") -- Wabenthema setzen ("off" = normal)
--   D:Invoke("launch", 10)          -- 10 Waben einfliegen lassen (Vulkan aus der Mitte)
--   D:Invoke("startevent", "WaspQueen") -- Boss-Event sofort (laeuft sonst nur jeden 2. Durchlauf)
--
-- v14 (Mega Egg Tree):
--   D:Invoke("tree")                 -- alle 20 Knoten mit Bedingungen und Stand
--   D:Invoke("unlock", "SunEgg")     -- einen Knoten freischalten ("all" = alle)
--   D:Invoke("hatched", "SugarEgg", 15) -- Hatch-Zaehler setzen (Freischalt-Test)
--   D:Invoke("blueprint", 1)         -- Blaupausen gutschreiben
--   D:Invoke("useblueprint", "PlatinumEgg")
--   D:Invoke("press", "SugarEgg", "Void") -- 5 Zucker-Eier -> 1 Nebel-Ei
--   D:Invoke("setrebirth", 10)       -- Rebirth-Zaehler setzen (ohne Reset)
--   D:Invoke("skilltest", "OmegaBaerchi", 30) -- einen Kampf mit Runden-Log
--   D:Invoke("snapshot")             -- Spielstand merken (fuer Tests)
--   D:Invoke("restore")              -- gemerkten Spielstand zurueckschreiben
--
-- HBB Paket 0 (Test-Zustaende, erst "snapshot"):
--   D:Invoke("state", "fresh")       -- neues Konto, Trichter F01–F10 misst
--   D:Invoke("state", "hatch10")     -- dazu zehn geoeffnete Basis-Eier
--   D:Invoke("state", "tower1")      -- dazu Tower I geschafft (Rekord 30)
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
local Loc = require(ReplicatedStorage.Localization.Loc)   -- Belohnung ist eine LocMsg
local CharmConfig      = require(ReplicatedStorage.Config.CharmConfig)
local BaerchiConfig    = require(ReplicatedStorage.Config.BaerchiConfig)
local BaerchiFactory   = require(ReplicatedStorage.Modules.BaerchiFactory)
local CombatCalculator = require(ReplicatedStorage.Modules.CombatCalculator)
local EggCalculator    = require(ReplicatedStorage.Modules.EggCalculator)
local CombConfig       = require(ReplicatedStorage.Config.CombConfig)

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

-- v14
local EggTreeService            = require(ServerScriptService.Services.EggTreeService)
local EggTree                   = require(ReplicatedStorage.Modules.EggTree)
local CombatConfig              = require(ReplicatedStorage.Config.CombatConfig)

-- v12
local ActivityLock = require(ServerScriptService.Util.ActivityLock)  -- Paket 1.1: Lock-Halter ausgeben
local PetModeService            = require(ServerScriptService.Services.PetModeService)
local PitArenaService           = require(ServerScriptService.Services.PitArenaService)

-- v15 (Waben)
local CombService               = require(ServerScriptService.Services.CombService)
local CombRecyclerService       = require(ServerScriptService.Services.CombRecyclerService)

-- v15 (Tower, Angeben, Login-Bonus)
local TowerConfig               = require(ReplicatedStorage.Config.TowerConfig)
local TowerService              = require(ServerScriptService.Services.TowerService)
local GamepassService           = require(ServerScriptService.Services.GamepassService)   -- 08.10. Paket C
local LeaderboardService        = require(ServerScriptService.Services.LeaderboardService)
local LoginBonusService         = require(ServerScriptService.Services.LoginBonusService)
local PlayerMigration           = require(ServerScriptService.Util.PlayerMigration)

-- v17 (lebendige Events)
local JackpotRoll               = require(ServerScriptService.Util.JackpotRoll)

-- HBB Paket 0
local FunnelService             = require(ServerScriptService.Services.FunnelService)

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
		baerchis     = countBaerchis(data),
		towers       = data.towers,
		towerProgress = data.island.towerProgress,
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

	return { building = buildingId, level = building.level, look = BuildingBehavior.getLook(building.level) }
end

-- v12: Ei ins Lager legen und sofort oeffnen (es gibt keine Brut mehr)
commands.hatch = function(player, data, eggType: any)
	local egg = tostring(eggType or "BasicEgg")
	if not EggConfig.data[egg :: Types.EggType] then
		return { error = "Unbekannter Egg-Typ: " .. egg }
	end

	data.island.eggStock[egg :: Types.EggType] = (data.island.eggStock[egg :: Types.EggType] or 0) + 1
	local result = EggService.openEgg(player, egg :: Types.EggType)
	if not result then
		return { error = "Oeffnen fehlgeschlagen" }
	end

	return {
		configId = result.baerchi.configId,
		rarity   = result.baerchi.rarity,
		mutation = result.baerchi.mutation,
		neu      = result.isNew,
	}
end

-- v12: Eier ins Lager legen, ohne sie zu oeffnen (fuer Tests im Ei-Menue)
commands.egg = function(player, data, eggType: any, count: any)
	local egg = tostring(eggType or "BasicEgg")
	if not EggConfig.data[egg :: Types.EggType] then
		return { error = "Unbekannter Egg-Typ: " .. egg }
	end

	local amount = math.clamp(tonumber(count) or 1, 1, 100)
	data.island.eggStock[egg :: Types.EggType] = (data.island.eggStock[egg :: Types.EggType] or 0) + amount
	PlayerService.markDirty(player)
	return { lager = data.island.eggStock }
end

-- v12/v15: gespeicherten letzten Lauf im gewaehlten Tower setzen (0 = loeschen)
commands.pitprogress = function(player, data, stage: any)
	local reached = math.floor(tonumber(stage) or 0)
	local towerId = data.towers.selected
	data.island.towerProgress[towerId] = if reached > 0 then reached else nil
	PlayerService.markDirty(player)
	return { tower = towerId, towerProgress = data.island.towerProgress }
end

-- v15: Tower waehlen (auch einen noch geschlossenen) und ab `stage` kaempfen.
-- Die Fortsetzungs-Kosten werden vorher gutgeschrieben (Test ohne Grind).
commands.tower = function(player, data, towerId: any, stage: any)
	local id = tostring(towerId or "I")
	local def = TowerConfig.get(id)
	if not def then
		return { error = "Unbekannter Tower: " .. id .. " (I, II, III, Final)" }
	end
	local uid = data.island.equippedUid
	if not uid then
		return { error = "Kein Baerchi ausgeruestet" }
	end
	TowerService.debugOpenAll(data)
	data.towers.selected = id
	local start = math.clamp(math.floor(tonumber(stage) or 1), 1, def.stages)
	local choice = "Fresh"
	if start > 1 then
		data.island.towerProgress[id] = start
		local _, cost = CombatService.getResumeOffer(data, id, "Last")
		if cost > 0 then EconomyService.awardGummiesFlat(player, cost) end
		choice = "Last"
	end
	PlayerService.markDirty(player)
	task.spawn(PetModeService.request, player, "Fight", choice :: any)
	return {
		tower = id, ab = start, deckel = TowerConfig.getStageCap(data.rebirthCount, id, data.towers.records, data.towers.unlocked),
		gegnerStage1 = TowerConfig.getEnemyStats(id, start),
	}
end

-- 08.10. (Paket C): Gamepass-Besitz fuer diese Sitzung erzwingen.
-- D:Invoke("pass", "on")  /  ("pass", "off")  /  ("pass", "reset") = wieder Roblox
-- Optional mit Key: D:Invoke("pass", "on", "SKIP_PASS")
commands.pass = function(player, _data, mode: any, key: any)
	local passKey = tostring(key or "SKIP_PASS")
	local m = tostring(mode or "on")
	local value: boolean? = if m == "on" then true elseif m == "off" then false else nil
	GamepassService.debugSet(player, passKey, value)
	return { pass = passKey, besitz = GamepassService.owns(player, passKey) }
end

-- v15: Tower-Rekord direkt setzen (Meilensteine bis dorthin werden ausgezahlt)
commands.towerrecord = function(player, data, towerId: any, stage: any)
	local id = tostring(towerId or "I")
	if not TowerConfig.get(id) then
		return { error = "Unbekannter Tower: " .. id }
	end
	TowerService.debugSetRecord(player, id, tonumber(stage) or 0)
	return { towers = data.towers }
end

-- v15: Deckel des aktuellen Rebirths
commands.rebirthcap = function(_player, data)
	local caps: { [string]: number } = {}
	for _, def in TowerConfig.TOWERS do
		caps[def.id] = TowerConfig.getStageCap(data.rebirthCount, def.id, data.towers.records, data.towers.unlocked)
	end
	local capTower, capStage = TowerConfig.getCap(data.rebirthCount)
	return { rebirths = data.rebirthCount, deckelTower = capTower, deckelStage = capStage, proTower = caps }
end

-- Sammel-Update 05.10. (Paket 4.1): beste Stage dieses Lebens setzen und die
-- Rebirth-Bedingung zeigen. D:Invoke("stagebest", "I", 30)
commands.stagebest = function(player, data, towerId: any, stage: any)
	if typeof(towerId) == "string" and TowerConfig.get(towerId) then
		data.island.stageBest[towerId] = math.max(0, math.floor(tonumber(stage) or 0))
		PlayerService.markDirty(player)
	end
	local reqTower, reqStage = TowerConfig.getRebirthRequirement(data.rebirthCount, data.towers.records)
	return {
		stageBest  = data.island.stageBest,
		bedingung  = reqTower .. "/" .. reqStage,
		bereit     = TowerConfig.isRebirthReady(data.rebirthCount, data.island.stageBest, data.towers.records),
	}
end

-- Sammel-Update 05.10. (Paket 8): Inkubator-Stand; "done" macht alle Eier fertig.
commands.incubator = function(player, data, action: any)
	local incubator = data.island.incubator
	if action == "done" then
		for _, entry in incubator.slots do entry.finishAt = os.time() end
		PlayerService.markDirty(player)
	elseif action == "breed" then
		-- INCUBATOR_BREED: jedes Baerchi im Inkubator bruetet sofort ein Ei.
		-- Lazy require: kein weiterer Modul-Local (200er-Grenze).
		local made = require(ServerScriptService.Services.IncubatorService).breedNow(player)
		return { gebruetet = made, baerchis = incubator.breeders }
	end
	return { level = incubator.level, plaetze = incubator.slots, baerchis = incubator.breeders }
end

-- v15: Login-Bonus — so tun, als waeren `days` Tage vergangen
commands.dailyshift = function(player, _data, days: any)
	return LoginBonusService.debugShift(player, math.floor(tonumber(days) or 1))
end

-- v15: Bestenlisten sofort schreiben und neu lesen
commands.lbflush = function(_player, _data)
	return LeaderboardService.flush()
end

-- v15: Teile auf der eigenen Insel zaehlen (Budget: 250 ohne Baerchi-Figuren)
commands.parts = function(player, _data)
	return MapService.countParts(player) or { error = "kein Plot" }
end

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

commands.tree = function(_player, data)
	local out = { blueprints = data.eggTree.blueprints, rebirths = data.rebirthCount }
	for _, eggId in EggConfig.getOrderedIds() do
		local p = EggTree.getProgress(data, eggId)
		local parts = {}
		for _, c in p.conditions do
			local label = c.kind .. (if c.egg then ":" .. c.egg elseif c.rarity then ":" .. c.rarity else "")
			table.insert(parts, string.format("%s %d/%d%s", label, c.have, c.need, if c.done then " ok" else ""))
		end
		out[string.format("%02d %s", EggConfig.data[eggId].sortOrder, eggId)] = string.format("%s | hatched %d | lager %d | %s",
			if p.unlocked then "FREI" else "zu", data.eggTree.hatched[eggId] or 0,
			data.island.eggStock[eggId] or 0, table.concat(parts, ", "))
	end
	return out
end

commands.unlock = function(player, data, eggType: any)
	if eggType == "all" then
		for _, eggId in EggConfig.getOrderedIds() do
			EggTreeService.forceUnlock(player, data, eggId, "debug")
		end
	elseif typeof(eggType) == "string" and EggConfig.data[eggType :: Types.EggType] then
		EggTreeService.forceUnlock(player, data, eggType :: Types.EggType, "debug")
	else
		return { error = "Unbekanntes Ei: " .. tostring(eggType) }
	end
	PlayerService.markDirty(player)
	return commands.tree(player, data)
end

commands.hatched = function(player, data, eggType: any, count: any)
	if typeof(eggType) ~= "string" or not EggConfig.data[eggType :: Types.EggType] then
		return { error = "Unbekanntes Ei: " .. tostring(eggType) }
	end
	data.eggTree.hatched[eggType] = math.max(0, math.floor(tonumber(count) or 0))
	PlayerService.markDirty(player)
	return commands.tree(player, data)
end

commands.blueprint = function(player, data, amount: any)
	EggTreeService.grantBlueprint(player, data, tonumber(amount) or 1)
	PlayerService.markDirty(player)
	return { blueprints = data.eggTree.blueprints }
end

commands.useblueprint = function(player, data, eggType: any)
	local ok = EggTreeService.useBlueprint(player, eggType)
	return { ok = ok, tree = commands.tree(player, data) }
end

commands.press = function(player, data, eggType: any, path: any)
	local result = EggTreeService.press(player, eggType, path)
	return { result = result, stock = data.island.eggStock }
end

commands.setrebirth = function(player, data, count: any)
	data.rebirthCount = math.max(0, math.floor(tonumber(count) or 0))
	data.rebirthMult  = EconomyConfig.getRebirthMult(data.rebirthCount)
	PlayerService.markDirty(player)
	return commands.tree(player, data)
end

-- Spielstand fuer Tests sichern und zuruecksetzen. Die Kopie liegt nur im
-- Speicher dieses Servers (nicht im DataStore).
local HttpService = game:GetService("HttpService")
local _snapshot: string? = nil

commands.snapshot = function(_player, data)
	_snapshot = HttpService:JSONEncode(data)
	return { ok = true, bytes = #(_snapshot :: string) }
end

commands.restore = function(player, data)
	if not _snapshot then return { error = "Kein Snapshot" } end
	local saved = HttpService:JSONDecode(_snapshot :: string)
	for k in data :: any do (data :: any)[k] = nil end
	for k, v in saved do (data :: any)[k] = v end
	MapService.rebuildIsland(player, data.island)
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)
	return { ok = true }
end

-- HBB Paket 0: feste Test-Zustaende fuer Playtests und Studio-Testschritte.
--   fresh   = Startstand eines neuen Kontos (createdAt = jetzt → Trichter misst)
--   hatch10 = fresh + zehn geoeffnete Basis-Eier
--   tower1  = hatch10 + Tower I geschafft (Rekord 30, Meilensteine ausgezahlt)
--
-- Studio spielt gegen den ECHTEN DataStore. Deshalb verlangt der Befehl einen
-- vorherigen "snapshot"; zurueck geht es mit "restore". Der Snapshot liegt nur
-- im Speicher dieses Servers — vor "Stop" also restore aufrufen.
--
-- Der Baerchi sollte zu Hause stehen (kein Kampf, kein Event), sonst haelt ein
-- anderer Service noch die alte Figur.
local TEST_STATES = { fresh = true, hatch10 = true, tower1 = true }
local TEST_HATCH_COUNT = 10
local TEST_TOWER_RECORD = 30

commands.state = function(player, data, name: any)
	local stateName = tostring(name or "")
	if not TEST_STATES[stateName] then
		return { error = "Unbekannter Zustand: " .. stateName, verfuegbar = { "fresh", "hatch10", "tower1" } }
	end
	if not _snapshot then
		return { error = "Erst D:Invoke(\"snapshot\") — Studio schreibt in den echten Spielstand" }
	end

	-- 1. fresh: alles ersetzen ausser Sitzungs-Sperre und Sprache
	local session  = (data :: any).session
	local language = data.language
	local fresh = PlayerService.buildDefaultData()
	for k in data :: any do (data :: any)[k] = nil end
	for k, v in fresh :: any do (data :: any)[k] = v end
	;(data :: any).session = session
	data.language = language
	MapService.rebuildIsland(player, data.island)
	FunnelService.debugReset(player)

	-- 2. hatch10: ueber den echten Weg oeffnen, damit Zaehler, Index und
	-- Auto-Ausruesten genau wie im Spiel laufen.
	if stateName == "hatch10" or stateName == "tower1" then
		data.island.eggStock.BasicEgg = (data.island.eggStock.BasicEgg or 0) + TEST_HATCH_COUNT
		for _ = 1, TEST_HATCH_COUNT do
			EggService.openEgg(player, "BasicEgg")
		end
	end

	-- 3. tower1: Rekord setzen, Meilensteine wie bei "towerrecord"
	if stateName == "tower1" then
		TowerService.debugSetRecord(player, "I", TEST_TOWER_RECORD)
	end

	PlayerService.markDirty(player)
	PlayerService.saveNow(player)
	return {
		ok = true,
		zustand = stateName,
		baerchis = countBaerchis(data),
		lager = data.island.eggStock,
		rekorde = data.towers.records,
		hinweis = "Zurueck mit D:Invoke(\"restore\")",
	}
end

-- Ein einzelner Kampf mit Runden-Log (Faehigkeiten pruefen).
commands.skilltest = function(_player, _data, configId: any, stage: any)
	local b = BaerchiFactory.create(tostring(configId), { level = 20 })
	if not b then return { error = "Unbekannter Baerchi" } end
	local def = BaerchiConfig.getById(b.configId)
	local stats = CombatCalculator.getEffectiveStats(b, (def :: any).baseStats)
	local es = CombatConfig.getEnemyStats(1, tonumber(stage) or 20)
	local me = { uid = "me", stats = stats, hp = stats.maxHp, charge = 0 }
	local en = { uid = "en", stats = es, hp = es.maxHp, charge = 0 }
	local r = CombatCalculator.simulate(me, en)
	local lines = {}
	for i, e in r.log do
		if i > 40 then break end
		table.insert(lines, string.format("%s r%d %s dmg %d heal %d abs %d | A %d B %d %s",
			e.actor, e.roundNumber, e.skillId or "-", e.damage, e.heal, e.absorbed,
			e.attackerHpAfter, e.defenderHpAfter, if e.effects then table.concat(e.effects, ",") else ""))
	end
	return { winner = r.winnerUid, rounds = r.rounds, skillUses = r.skillUses, log = lines }
end

commands.help = function()
	return {
		"info", "give <gummies> <gold>", "list",
		"add <configId> <level> [mutation]", "stats <uid>",
		"building <id> <level>",
		"hatch <eggType>", "egg <eggType> [anzahl]", "pitprogress <stage>", "honey", "feed <uid> <times>",
		"fight <uid>",
		"fuse <uidA> <uidB> [ability|level|eggs] [A|B]",
		"recycle <uid>", "upgrade <buildingId>", "rebirth",

		-- v8
		"promote <uid>", "charms <uid>", "roll <uid> [anzahl]", "lock <uid> <slot>",
		"event", "recall", "skipevent", "events", "startevent <eventId>",

		-- v10
		"eggs", "lay [anzahl]", "collect", "eggtime <minuten>",

		-- v12
		"petmode", "pm <Event|Fight|Home> [Fresh|Percent|Last]",

		-- v14
		"tree", "unlock <eggType|all>", "hatched <eggType> <n>", "blueprint [n]",
		"useblueprint <eggType>", "press <eggType> [Gold|Kristall|Void]", "setrebirth <n>",
		"skilltest <configId> [stage]", "snapshot", "restore",
		-- HBB Paket 0
		"state <fresh|hatch10|tower1>  (erst snapshot!)",

		-- v15
		"combs [anzahl]", "queue <einheiten>", "recycler [level]",

		-- v15 (Tower/Gebaeude/Angeben/Login-Bonus)
		"tower <I|II|III|Final> <stage>", "towerrecord <id> <stage>", "rebirthcap",
		"pass <on|off|reset> [KEY]  (08.10.: Gamepass Gratis-Skip testen)",
		"dailyshift <tage>", "lbflush", "parts", "v14save",

		-- v17
		"jackpot", "combtheme <themeId|off>", "launch [anzahl]",
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
