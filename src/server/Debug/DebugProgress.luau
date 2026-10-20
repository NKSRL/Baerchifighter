--!strict
-- DebugProgress.luau
-- ServerScriptService/Debug/DebugProgress.luau
--
-- Studio-Testbefehle: Fortschritt: Pit, Tower, Epilog, Inkubator, Reise, Raketeninsel.
-- Registriert sich beim require in DebugRegistry.commands; geladen nur von
-- DebugService.init() und nur in Studio (nie im Live-Spiel).

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local PlayerService  = require(ServerScriptService.Services.PlayerService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local CombatService  = require(ServerScriptService.Services.CombatService)
local MapService     = require(ServerScriptService.Services.MapService)
local PetModeService            = require(ServerScriptService.Services.PetModeService)
local TowerConfig               = require(ReplicatedStorage.Config.TowerConfig)
local TowerService              = require(ServerScriptService.Services.TowerService)
local GamepassService           = require(ServerScriptService.Services.GamepassService)   -- 08.10. Paket C
local LeaderboardService        = require(ServerScriptService.Services.LeaderboardService)
local LoginBonusService         = require(ServerScriptService.Services.LoginBonusService)
local EpilogService             = require(ServerScriptService.Services.EpilogService)   -- 20.10. Final-Epilog
local FeatureFlags              = require(ReplicatedStorage.Config.FeatureFlags)
local DebugRegistry = require(script.Parent.DebugRegistry)

local commands = DebugRegistry.commands

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
		tower = id, ab = start, deckel = TowerConfig.getStageCap(data.rebirthCount, id, TowerConfig.unlockRecords(data.towers, data.island), data.towers.unlocked),
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

-- 20.10. Final-Epilog (Prompt 1). D:Invoke("epilog", "start|reset|state|launch|scan|on|off")
--   start  neue Sequenz erzwingen (state none -> pending, EpilogStart), unabhaengig vom Rekord
--   reset  state zurueck auf none (Endless/Welt 2 bleiben; danach loest ein Final-100-Sieg wieder aus)
--   state  Zustand + Token-Vorschau
--   launch pending/seen -> launched (Welt 2 frei), ohne Sequenz
--   summit / summitoff  Gipfel bauen+teleportieren bzw. entfernen (ohne Zustandswechsel)
--   scan   Final-Rekord >= 100 aber state none? (Luecke) + Zaehler verworfener Anfragen
--          + Prompt 3: Insel-/Brueckenteile (Spieler und ganzer Workspace)
--   terminal [idle|ready|armed|fired|done|off]  Prompt 4: Start-Terminal bauen und Zustand setzen
--   bridge / bridgeinstant / bridgeoff  Prompt 3: Insel + Bruecke wachsen lassen /
--          sofort bauen / animiert abbauen (verlangt state pending/seen: erst `epilog start`)
--   speed N  Prompt 5: Zeitraffer 0,5..5 fuer den naechsten `start`
--   audit    Prompt 5: Client-Zustand (Kamera, FOV, Lighting, Steuerung, Verbindungen) - muss sauber sein
--   on|off Schalter FINAL_EPILOG fuer diese Studio-Sitzung
commands.epilog = function(player, data, action: any, argument: any)
	local act = tostring(action or "state")
	local FLAGS = FeatureFlags.FLAGS
	if act == "on" or act == "off" then
		FLAGS.FINAL_EPILOG = (act == "on")
	elseif act == "start" then
		local started, note = EpilogService.debugStart(player)
		return { gestartet = started, hinweis = note, epilog = data.epilog }
	elseif act == "reset" then
		EpilogService.debugReset(player)
	elseif act == "launch" then
		return { gestartet = EpilogService.debugLaunch(player, if argument ~= nil then tostring(argument) else nil), epilog = data.epilog, worlds = data.worlds }
	elseif act == "scan" then
		return EpilogService.debugScan(player, data)
	elseif act == "bridge" or act == "bridgeinstant" or act == "bridgeoff" then
		local ok, note = EpilogService.debugBridge(player, act)
		return { ok = ok, hinweis = note, teile = MapService.countParts(player) }
	elseif act == "terminal" then
		-- Prompt 4: D:Invoke("epilog","terminal") -> ready; ("epilog","terminal","fired") spielt die Ausloese-Animation;
		-- idle|ready|armed|fired|done setzen den Zustand, "off" entfernt das Terminal.
		local ok, note = EpilogService.debugTerminal(player, if argument ~= nil then tostring(argument) else nil)
		return { ok = ok, hinweis = note, teile = MapService.countParts(player) }
	elseif act == "speed" then
		-- Prompt 5: Zeitraffer fuer den naechsten Start (0,5..5), z. B. D:Invoke("epilog","speed",3)
		return { zeitraffer = EpilogService.debugSpeed(player, argument) }
	elseif act == "audit" then
		-- Prompt 5: Zustand von Kamera, Lighting, Steuerung, Verbindungen (muss nach jedem Durchlauf sauber sein)
		return EpilogService.debugAudit(player)
	elseif act == "summit" or act == "summitoff" then
		return { ok = EpilogService.debugSummit(player, act == "summit"), teile = MapService.countParts(player) }
	elseif act ~= "state" then
		return { error = "epilog start|reset|state|launch [fast]|scan|summit|summitoff|bridge|bridgeinstant|bridgeoff|terminal|speed|audit|on|off" }
	end
	return {
		schalter = FeatureFlags.isOn("FINAL_EPILOG"),
		epilog   = data.epilog,
		worlds   = data.worlds,
		endless  = data.towers.unlocked.Endless == true,
		token    = EpilogService.debugToken(player),
	}
end

-- v15: Deckel des aktuellen Rebirths
commands.rebirthcap = function(_player, data)
	local caps: { [string]: number } = {}
	for _, def in TowerConfig.TOWERS do
		caps[def.id] = TowerConfig.getStageCap(data.rebirthCount, def.id, TowerConfig.unlockRecords(data.towers, data.island), data.towers.unlocked)
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
		TowerService.debugApplyUnlocks(player, towerId)   -- 12.10.: Tower pro Leben
	end
	local reqTower, reqStage = TowerConfig.getRebirthRequirement(data.rebirthCount, data.towers.records)
	return {
		stageBest  = data.island.stageBest,
		bedingung  = reqTower .. "/" .. reqStage,
		bereit     = TowerConfig.isRebirthReady(data.rebirthCount, data.island.stageBest, data.towers.records),
	}
end

-- Sammel-Update 05.10. (Paket 8): Inkubator-Stand; "done" macht alle Eier fertig.
commands.incubator = function(player, data, action: any, arg: any)
	local incubator = data.island.incubator
	local Rules = require(game:GetService("ReplicatedStorage").Modules.IncubatorRules)
	if action == "breed" then
		-- Der Baerchi im Inkubator bruetet sofort ein Ei.
		-- Lazy require: kein weiterer Modul-Local (200er-Grenze).
		local made = require(ServerScriptService.Services.IncubatorService).breedNow(player)
		return { gebruetet = made, lager = Rules.storedTotal(incubator) }
	elseif action == "level" and typeof(arg) == "number" then
		incubator.level = math.clamp(math.floor(arg), 1, 4)
		PlayerService.markDirty(player)
	elseif action == "fill" then
		local stored = Rules.storedOf(incubator)
		stored.BasicEgg = (stored.BasicEgg or 0) + Rules.storedFree(incubator)
		PlayerService.markDirty(player)
	end
	local level = Rules.levelOf(incubator)
	return { level = level, lager = Rules.storedTotal(incubator) .. "/" .. Rules.capacity(level),
		eier = incubator.stored, baerchi = incubator.breeders }
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

-- 20.10. P3 Reise. D:Invoke("journey", "state" | "set" | "reset", n)
--   state  Stand der Reise (abgeholt/uebersprungen/aktuelle Etappe laut Spielstand)
--   set n  Etappen 1..n-1 als abgeholt markieren (ohne Auszahlung), Rest offen
--   reset  Reise zuruecksetzen (alles offen, sichtbar)
commands.journey = function(player, _data, action: any, n: any)
	local PlayerService  = require(ServerScriptService.Services.PlayerService)
	local OnboardingRules  = require(ReplicatedStorage.Modules.OnboardingRules)
	local OnboardingConfig = require(ReplicatedStorage.Config.OnboardingConfig)
	local data = PlayerService.getData(player)
	if not data then return { error = "kein Spielstand" } end
	local act = tostring(action or "state")
	if act == "reset" then
		(data :: any).journey = OnboardingRules.defaultJourney()
		PlayerService.markDirty(player)
	elseif act == "set" then
		local j = OnboardingRules.defaultJourney()
		for i = 1, math.clamp(math.floor(tonumber(n) or 1) - 1, 0, OnboardingConfig.MAX_STAGE) do
			j.claimed[OnboardingConfig.STAGES[i].id] = true
		end
		(data :: any).journey = j
		PlayerService.markDirty(player)
	elseif act ~= "state" then
		return { error = "journey state|set <n>|reset" }
	end
	local journey = OnboardingRules.sanitize((data :: any).journey)
	local id, index, done = OnboardingRules.current(data :: any, journey)
	return { aktuell = id, index = index, erfuellt = done, abgeholt = journey.claimed, uebersprungen = journey.skipped, ausgeblendet = journey.hidden }
end

-- 20.10. P4 Raketen-Insel. D:Invoke("rocketisland", "state" | "set", 1|2|3)
--   state  Teile, Lage, Platzhalter ja/nein, Spielstand-Zustand
--   set n  Schild-Zustand fuer alle Clients erzwingen (1 gesperrt, 2 bereit, 3 gestartet; 0 = aus dem Spielstand)
commands.rocketisland = function(player, _data, action: any, n: any)
	local PlayerService = require(ServerScriptService.Services.PlayerService)
	local RocketIslandRules = require(ReplicatedStorage.Modules.RocketIslandRules)
	local act = tostring(action or "state")
	if act == "set" then
		local v = math.floor(tonumber(n) or 0)
		workspace:SetAttribute("RocketIslandDebugState", if v >= 1 and v <= 3 then v else nil)
	elseif act ~= "state" then
		return { error = "rocketisland state|set 0..3" }
	end
	local platform = workspace:FindFirstChild("Platform")
	local root = if platform then platform:FindFirstChild("RocketIsland_Root") else nil
	local data = PlayerService.getData(player)
	return {
		gebaut = root ~= nil,
		teile = if root then root:GetAttribute("PartCount") else nil,
		platzhalter = if root then root:GetAttribute("Placeholder") else nil,
		zustandSpielstand = if data then RocketIslandRules.state(data :: any) else nil,
		erzwungen = workspace:GetAttribute("RocketIslandDebugState"),
	}
end

return {}
