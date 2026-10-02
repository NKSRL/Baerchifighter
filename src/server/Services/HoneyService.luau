--!strict
-- HoneyService.luau
-- ServerScriptService/Services/HoneyService.luau
--
-- Einzige Zustaendigkeit:
--   - Honig-Produktion der Gebaeude nachrechnen
--   - Honig an einen Baerchi verfuettern: heilt ihn und gibt XP
--
-- ============================================================
-- DER KERN-LOOP DES SPIELS
-- ============================================================
--   PIT-Lauf → Baerchi kommt erschoepft zurueck (currentHp niedrig oder 0)
--   → auf dem Plot mit Honig hochfuettern → dabei steigt er im Level
--   → naechster Lauf geht tiefer.
--
-- Das ist die EINZIGE XP-Quelle im Spiel: Kaempfe geben seit v4 keine XP
-- mehr. Wer schneller leveln will, baut die Honig-Presse aus — deshalb haengt
-- die gesamte Progression an diesem Service.
--
-- DREI HONIG-SORTEN (seit v7):
-- Jedes Gebaeude hat eine eigene Rolle (siehe Config/BuildingBehavior). Fuer
-- diesen Service heisst das: WIE VIEL ein Honig heilt, haengt am Gebaeude, aus
-- dem er kommt; WIE VIEL XP er gibt, haengt am Level der Honig-Presse und ist
-- fuer jeden Honig gleich. Welches Gebaeude was kann, weiss dieser Service
-- nicht — er fragt BuildingBehavior und verzweigt nirgends nach einer id.
--
-- PRODUKTION OHNE TIMER:
-- Jedes Gebaeude merkt sich in `lastProducedAt`, bis wann sein Honig schon
-- angerechnet ist. Wie viel dazugekommen ist, wird daraus jedes Mal neu
-- ausgerechnet statt in einem Timer mitgezaehlt. Dadurch produzieren die
-- Gebaeude auch waehrend der Spieler offline ist, und ein verpasster Tick
-- kann keinen Honig verschlucken. Der Loop unten stoesst das nur regelmaessig
-- an, damit die Anzeige mitlaeuft — er ist nicht die Quelle der Wahrheit.
--
-- Das Lager pro Gebaeude ist gedeckelt (BuildingBehavior.getCapacity — der
-- Bienenstock lagert mit steigendem Level mehr als die anderen beiden). Wer
-- lange weg war, findet volle Lager vor, aber nicht mehr — genau das macht
-- das regelmaessige Zurueckkommen noetig.

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types            = require(ReplicatedStorage.Network.Types)
local Remotes          = require(ReplicatedStorage.Network.Remotes)
local Loc           = require(ReplicatedStorage.Localization.Loc)
local BaerchiConfig    = require(ReplicatedStorage.Config.BaerchiConfig)
local EconomyConfig    = require(ReplicatedStorage.Config.EconomyConfig)
local BuildingBehavior = require(ReplicatedStorage.Config.BuildingBehavior)
local CombatCalculator = require(ReplicatedStorage.Modules.CombatCalculator)

local PlayerService = require(ServerScriptService.Services.PlayerService)
local MapService     = require(ServerScriptService.Services.MapService)
local RateLimiter   = require(ServerScriptService.Util.RateLimiter)

-- Feier-Farbe fuer einen Level-Up (siehe MapService.celebrateBaerchi) — Gold,
-- derselbe Ton wie Theme.COLORS.goldGummy auf dem Client. Server und Client
-- duplizieren hier bewusst eine Zahl statt sich ein gemeinsames Modul zu
-- teilen: Theme ist UI-only (StarterPlayerScripts), MapService/HoneyService
-- laufen auf dem Server, ein Client→Server-Require ist in Rojo nicht moeglich.
local LEVEL_UP_CELEBRATE_COLOR = Color3.fromRGB(255, 196, 60)

local HoneyService = {}

local function fail(player: Player, reason: Types.LocMsg?)
	Remotes.ActionFailed:FireClient(player, "RequestFeedHoney", reason or Loc.msg("err.unknown"))
end

--------------------------------------------------------------------------------
-- Produktion
--------------------------------------------------------------------------------

-- Rechnet fuer alle Gebaeude eines Spielers nach, wie viel Honig seit
-- `lastProducedAt` dazugekommen ist. Gibt die Gesamtmenge zurueck, damit der
-- Aufrufer entscheiden kann ob sich ein Client-Sync ueberhaupt lohnt.
function HoneyService.accrue(data: Types.PlayerData, now: number): number
	local gained = 0

	for _, building in data.island.buildings do
		-- Pro Gebaeude eigenes Tempo UND eigenes Lager. WELCHES Gebaeude wovon
		-- abweicht, entscheidet BuildingBehavior — dieser Service verzweigt
		-- bewusst nirgends selbst nach einer BuildingId.
		local interval = BuildingBehavior.getIntervalSeconds(building.id, building.level)
		local capacity = BuildingBehavior.getCapacity(building.id, building.level)

		local honey = math.clamp(building.honey or 0, 0, capacity)
		building.honey = honey

		-- Volles Lager: die Uhr laeuft nicht weiter. Sonst haette ein Spieler
		-- nach langer Abwesenheit ein volles Lager UND zusaetzlich noch
		-- angesammelte Zeit gut, und die naechsten Honige kaemen sofort.
		if honey >= capacity then
			building.lastProducedAt = now
			continue
		end

		local last    = building.lastProducedAt or now
		local elapsed = now - last

		-- Uhr-Sprung oder frisch angelegtes Gebaeude: nicht rueckwaerts produzieren
		if elapsed < 0 then
			building.lastProducedAt = now
			continue
		end

		local produced = math.floor(elapsed / interval)
		if produced <= 0 then
			continue
		end

		local added = math.min(produced, capacity - honey)
		building.honey = honey + added

		-- Nur die verbrauchten Intervalle abziehen — der angefangene Rest
		-- bleibt stehen und geht nicht verloren.
		building.lastProducedAt = last + produced * interval
		gained += added
	end

	return gained
end

-- Gesamter Honig ueber alle Gebaeude (fuer Anzeige und Meldungen)
function HoneyService.getTotalHoney(data: Types.PlayerData): number
	local total = 0
	for _, building in data.island.buildings do
		total += building.honey or 0
	end
	return total
end

--------------------------------------------------------------------------------
-- Fuettern
--------------------------------------------------------------------------------

-- Das vom Spieler AUSGEWAEHLTE Gebaeude — nil, wenn es dort gerade keinen
-- Honig gibt.
local function pickRequestedBuilding(data: Types.PlayerData, buildingId: Types.BuildingId): Types.Building?
	-- Zwei getrennte Pruefungen statt einer verodeten: die zweite liest ein
	-- Feld des ersten, und so steht ohne Nachdenken da, dass sie nur laeuft
	-- wenn es das Gebaeude ueberhaupt gibt.
	local building = data.island.buildings[buildingId]
	if not building then
		return nil
	end
	if (building.honey or 0) <= 0 then
		return nil
	end

	return building
end

-- Die AUTOMATISCHE Wahl — nur fuer Aufrufer, die nicht fragen koennen.
--
-- Seit v7 gibt es drei unterschiedliche Honig-Sorten, und damit gibt es keine
-- immer richtige Antwort mehr: der Honigtopf heilt am meisten, die XP sind
-- ueberall gleich. Der Spieler waehlt deshalb im UI selbst (BaerchiPanel) —
-- diese Funktion ist fuer den Autopiloten, der von alleine essen geht, und fuer
-- den Studio-Debug-Befehl.
--
-- Die Regel in zwei Saetzen:
--   * Erschoepft (unter EconomyConfig.HONEY_AUTO_HEAL_HP_RATIO): der Honig, der
--     am meisten heilt. Genau dafuer hebt man den Honigtopf auf.
--   * Sonst: das VOLLSTE Lager zuerst — dort steht die Produktion still, und
--     jeder verfuetterte Honig startet sie wieder. Bei Gleichstand faellt die
--     Wahl bewusst auf den Honig, der am WENIGSTEN heilt: der Heil-Honig soll
--     fuer nach dem naechsten Kampf liegen bleiben.
local function pickAutoBuilding(data: Types.PlayerData, hpRatio: number): Types.Building?
	local needsHeal = hpRatio < EconomyConfig.HONEY_AUTO_HEAL_HP_RATIO

	local best: Types.Building? = nil
	local bestPrimary   = -math.huge
	local bestSecondary = -math.huge

	for _, building in data.island.buildings do
		local honey = building.honey or 0

		if honey > 0 then
			local heal = BuildingBehavior.getHealPercent(building.id, building.level)
			local cap  = math.max(1, BuildingBehavior.getCapacity(building.id, building.level))
			local fill = honey / cap

			local primary   = if needsHeal then heal else fill
			local secondary = if needsHeal then fill else -heal

			local better: boolean
			if best == nil then
				better = true
			else
				-- Letzter Ausweg ist die id: die Iteration ueber eine
				-- Hash-Tabelle ist nicht stabil, ohne sie spraenge die Auswahl
				-- bei Gleichstand von Aufruf zu Aufruf.
				local currentId = best.id

				if primary > bestPrimary then
					better = true
				elseif primary < bestPrimary then
					better = false
				elseif secondary > bestSecondary then
					better = true
				elseif secondary < bestSecondary then
					better = false
				else
					better = building.id < currentId
				end
			end

			if better then
				best          = building
				bestPrimary   = primary
				bestSecondary = secondary
			end
		end
	end

	return best
end

-- Versucht den Baerchi zu leveln wenn genug XP vorhanden.
-- Liegt hier, weil Honig die einzige XP-Quelle im Spiel ist.
local function tryLevelUp(baerchi: Types.Baerchi): boolean
	local leveled = false

	while baerchi.level < BaerchiConfig.MAX_LEVEL
		and baerchi.xp >= BaerchiConfig.xpForNextLevel(baerchi.level) do
		baerchi.xp    -= BaerchiConfig.xpForNextLevel(baerchi.level)
		baerchi.level += 1
		leveled        = true
	end

	-- Auf Max-Level sammelt sich sonst unendlich XP an
	if baerchi.level >= BaerchiConfig.MAX_LEVEL then
		baerchi.xp = 0
	end

	return leveled
end

-- `buildingId` ist optional: der Spieler waehlt im UI aus, welchen Honig er
-- verfuettert. Wer nicht fragen kann (BaerchiAutopilotService, DebugService),
-- laesst es weg und bekommt die automatische Wahl.
function HoneyService.feed(player: Player, baerchiUid: string, buildingId: Types.BuildingId?)
	local data = PlayerService.getData(player)
	if not data then return end

	local baerchi = data.island.baerchis[baerchiUid]
	if not baerchi then
		fail(player, Loc.msg("err.baerchi_not_found"))
		return
	end

	local def = BaerchiConfig.getById(baerchi.configId)
	if not def then
		warn("[HoneyService] Unbekannter configId:", baerchi.configId)
		fail(player, Loc.msg("err.baerchi_data_corrupt"))
		return
	end

	-- Erst nachrechnen: sonst faellt eine Fuetterung durch, obwohl genau
	-- jetzt ein Honig fertig geworden waere.
	HoneyService.accrue(data, os.time())

	local statsBefore = CombatCalculator.getEffectiveStats(baerchi, def.baseStats)
	local hpBefore    = math.clamp(baerchi.currentHp, 0, statsBefore.maxHp)
	local hpRatio     = if statsBefore.maxHp > 0 then hpBefore / statsBefore.maxHp else 1

	local chosen = if buildingId
		then pickRequestedBuilding(data, buildingId)
		else pickAutoBuilding(data, hpRatio)

	if not chosen then
		fail(player, Loc.msg(if buildingId then "err.feed_building_empty" else "err.feed_no_honey"))
		return
	end

	local building = chosen

	-- Geheilt wird nach dem Gebaeude, aus dem der Honig KOMMT (nur der
	-- Honigtopf steigert das). Die XP haengen dagegen nicht an der Herkunft,
	-- sondern am Level der Honig-Presse und gelten fuer jeden Honig gleich —
	-- deshalb bekommt getXpPerHoney alle Gebaeude und nicht nur dieses eine.
	local healPercent = BuildingBehavior.getHealPercent(building.id, building.level)

	local heal   = math.max(1, math.floor(statsBefore.maxHp * healPercent))
	local hpNow  = math.min(statsBefore.maxHp, hpBefore + heal)
	local xp     = BuildingBehavior.getXpPerHoney(data.island.buildings)

	building.honey    -= 1
	baerchi.currentHp  = hpNow
	baerchi.xp        += xp

	local leveled = tryLevelUp(baerchi)

	-- Nach einem Level-Up ist maxHp groesser. Die aktuellen HP bleiben stehen
	-- (kein Gratis-Vollheilung), der Baerchi ist danach also relativ gesehen
	-- staerker verletzt — genau deshalb lohnt weiterfuettern.
	local statsAfter = if leveled
		then CombatCalculator.getEffectiveStats(baerchi, def.baseStats)
		else statsBefore

	local result: Types.FeedResult = {
		baerchiUid = baerchiUid,
		buildingId = building.id,
		hpGained   = hpNow - hpBefore,
		xpGained   = xp,
		leveledUp  = leveled,
		newLevel   = baerchi.level,
		hpAfter    = baerchi.currentHp,
		maxHp      = statsAfter.maxHp,
	}

	Remotes.FeedResultReceived:FireClient(player, result)

	-- Sichtbar auf dem Plot feiern statt nur im Toast zu vermelden — alle
	-- Spieler auf dem Server sehen es mit, nicht nur der Besitzer (siehe
	-- DESIGN_VORSCHLAG_TRENDANALYSE_2026-09-11.md Abschnitt 4).
	if leveled then
		MapService.celebrateBaerchi(player, baerchiUid, LEVEL_UP_CELEBRATE_COLOR)
	end

	PlayerService.markDirty(player)

	print(
		"[HoneyService]", player.Name,
		"| fuettert:", baerchi.configId,
		"| aus:", building.id, "Lv.", building.level,
		"| +", result.hpGained, "HP, +", xp, "XP",
		leveled and ("| LEVEL UP → " .. baerchi.level) or ""
	)
end

--------------------------------------------------------------------------------
-- Loop und Offline-Ertrag
--------------------------------------------------------------------------------

local function tick()
	local now = os.time()

	for _, player in Players:GetPlayers() do
		local data = PlayerService.getData(player)
		if data then
			-- Nur syncen wenn wirklich Honig dazugekommen ist: markDirty
			-- zieht einen Client-Sync und alle onDataChanged-Beobachter nach
			-- sich, das soll nicht jede Sekunde ins Leere laufen.
			if HoneyService.accrue(data, now) > 0 then
				PlayerService.markDirty(player)
			end
		end
	end
end

local function startLoop()
	task.spawn(function()
		while true do
			task.wait(EconomyConfig.HONEY_INTERVAL_SECONDS)

			local ok, err = pcall(tick)
			if not ok then
				warn("[HoneyService] Tick fehlgeschlagen:", err)
			end
		end
	end)
end

-- Wird von PlayerService aufgerufen sobald die Daten geladen sind.
-- WICHTIG: laeuft bevor irgendetwas lastSeenAt ueberschreibt.
local function grantOfflineHoney(player: Player, data: Types.PlayerData)
	local now      = os.time()
	local lastSeen = data.lastSeenAt or now
	local away     = math.max(0, now - lastSeen)

	local gained = HoneyService.accrue(data, now)
	data.lastSeenAt = now

	if gained <= 0 then
		return
	end

	local report: Types.OfflineReport = {
		secondsAway = away,
		honeyGained = gained,
	}

	-- Kurz verzoegert feuern: beim Join haengt der Client sein UI erst noch
	-- an die Remotes, ein sofortiges FireClient ginge ins Leere.
	task.delay(3, function()
		if player.Parent then
			Remotes.OfflineReportReceived:FireClient(player, report)
		end
	end)

	print(
		"[HoneyService] Offline-Honig fuer", player.Name,
		"|", math.floor(away / 60), "min weg",
		"| +", gained, "Honig"
	)
end

function HoneyService.init()
	-- Muss VOR PlayerService.init() laufen, sonst verpasst der Callback die
	-- ersten Joins — siehe Reihenfolge im GameManager.
	PlayerService.onDataLoaded(grantOfflineHoney)

	RateLimiter.connect(Remotes.RequestFeedHoney, "RequestFeedHoney", function(player, baerchiUid: any, buildingId: any)
		if typeof(baerchiUid) ~= "string" then return end

		-- Ohne zweites Argument bleibt es bei der automatischen Wahl (aeltere
		-- Clients, und der Weg den der Autopilot ohnehin nimmt).
		if buildingId == nil then
			HoneyService.feed(player, baerchiUid)
			return
		end

		-- Ein Client-String wird nie ungeprueft als Types.BuildingId
		-- weitergereicht — dieselbe Konvention wie bei
		-- IslandService.upgradeBuilding. Ein unbekanntes Gebaeude wird
		-- abgelehnt statt stillschweigend zur Auto-Wahl zu werden: sonst
		-- verfuettert ein Tippfehler im Client den falschen Honig.
		if typeof(buildingId) ~= "string" then return end
		if not BuildingBehavior.isValidId(buildingId) then
			fail(player, Loc.msg("err.building_unknown"))
			return
		end

		HoneyService.feed(player, baerchiUid, buildingId :: Types.BuildingId)
	end)

	startLoop()

	print(
		"[HoneyService] Initialisiert",
		"| Basis: 1 Honig alle", EconomyConfig.HONEY_INTERVAL_SECONDS, "s,",
		"Lager", EconomyConfig.HONEY_CAPACITY,
		"| Abweichungen pro Gebaeude siehe BuildingBehavior"
	)
end

return HoneyService
