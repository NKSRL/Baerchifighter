--!strict
-- CombRecyclerService.luau
-- ServerScriptService/Services/CombRecyclerService.luau
--
-- Einzige Zustaendigkeit:
--   - Den Waben-Recycler auf dem Plot betreiben: abgegebene Waben in die
--     Warteschlange legen, sie zeitgesteuert in Gummies verwandeln und den
--     Ausbau des Recyclers verkaufen.
--
-- Nicht zu verwechseln mit RecycleService (verwertet einen Baerchi gegen
-- Gummies). Das hier ist die Maschine fuer die Waben aus dem Event-Pit
-- (siehe CombService und Config/CombConfig).
--
-- Die Verarbeitung laeuft ueber eine Zeitmarke (island.recycler.lastProcessedAt)
-- und nicht ueber einen Timer pro Spieler, genau wie Honig und Eierlegen: der
-- Recycler arbeitet damit auch weiter, waehrend der Spieler offline ist, und es
-- braucht keine Schleife pro Spieler. Der Takt unten verrechnet nur, was seit
-- der letzten Verrechnung dazugekommen ist.
--
-- Auszahlung ueber EconomyService.awardGummies, also MIT Rebirth-Multiplikator:
-- das ist Einkommen aus Arbeit, kein Gegenwert wie beim Verwerten eines
-- Baerchis (dort ist awardGummiesFlat richtig, siehe RecycleService).

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CombConfig = require(ReplicatedStorage.Config.CombConfig)
local Types      = require(ReplicatedStorage.Network.Types)
local Remotes    = require(ReplicatedStorage.Network.Remotes)
local Loc        = require(ReplicatedStorage.Localization.Loc)

local PlayerService  = require(ServerScriptService.Services.PlayerService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local RateLimiter    = require(ServerScriptService.Util.RateLimiter)

local CombRecyclerService = {}

--------------------------------------------------------------------------------
-- Verrechnung
--------------------------------------------------------------------------------

-- Rechnet die Zeit seit der letzten Verrechnung nach, schreibt die fertigen
-- Einheiten als Gummies gut und gibt zurueck, wie viele Einheiten fertig wurden.
--
-- Immer zuerst aufrufen, BEVOR sich Level oder Warteschlange aendern: sonst
-- wuerde die Zeit davor mit dem neuen Wert gerechnet (z.B. eine halbe Stunde
-- Leerlauf, die ploetzlich "Arbeit" waere, sobald eine Abgabe kommt).
local function settle(player: Player, data: Types.PlayerData): number
	local recycler = data.island.recycler
	local now = os.time()

	local elapsed = math.clamp(now - recycler.lastProcessedAt, 0, CombConfig.OFFLINE_MAX_SECONDS)
	recycler.lastProcessedAt = now

	if recycler.queued <= 0 then
		recycler.queued   = 0
		recycler.progress = 0
		return 0
	end
	if elapsed <= 0 then return 0 end

	recycler.progress += elapsed * CombConfig.getSpeed(recycler.level)

	local done = math.min(recycler.queued, math.floor(recycler.progress))
	if done <= 0 then return 0 end

	recycler.queued   -= done
	recycler.progress -= done
	if recycler.queued <= 0 then
		recycler.queued   = 0
		recycler.progress = 0
	end

	EconomyService.awardGummies(player, done * CombConfig.getPayPerUnit(recycler.level))
	return done
end

--------------------------------------------------------------------------------
-- Oeffentliche API
--------------------------------------------------------------------------------

-- Nimmt abgegebene Waben entgegen. Gibt false zurueck, wenn die Spieldaten
-- noch nicht geladen sind — CombService behaelt den Stapel dann und versucht es
-- spaeter noch einmal.
function CombRecyclerService.deposit(player: Player, units: number): boolean
	local data = PlayerService.getData(player)
	if not data then return false end
	if units <= 0 then return true end

	settle(player, data)

	local recycler = data.island.recycler
	recycler.queued += math.floor(units)

	PlayerService.markDirty(player)
	return true
end

-- Aktuelles Recycler-Level (1, solange die Daten nicht geladen sind). Fuer den
-- Respawn-Hook (CombConfig.getRespawnDelay).
function CombRecyclerService.getLevel(player: Player): number
	local data = PlayerService.getData(player)
	if not data then return 1 end
	return data.island.recycler.level
end

-- Kauft das naechste Level. Meldet Fehler als ActionFailed (wie IslandService).
function CombRecyclerService.upgrade(player: Player)
	local data = PlayerService.getData(player)
	if not data then return end

	local function fail(reason: Types.LocMsg)
		Remotes.ActionFailed:FireClient(player, "RequestUpgradeRecycler", reason)
	end

	-- Erst die laufende Arbeit nach dem ALTEN Level abrechnen.
	settle(player, data)

	local recycler = data.island.recycler
	local nextLevel = recycler.level + 1

	if nextLevel > CombConfig.RECYCLER_MAX_LEVEL then
		fail(Loc.msg("err.max_level"))
		return
	end

	local cost = CombConfig.getUpgradeCost(nextLevel)
	if not cost then
		fail(Loc.msg("err.max_level"))
		return
	end

	-- Erst pruefen, dann buchen (wie EconomyService.upgradeBuilding): sonst kann
	-- der erste Teilbetrag abgezogen werden, obwohl der zweite scheitert.
	if cost.gummies > 0 and data.gummies < cost.gummies then
		fail(Loc.msg("err.not_enough_gummies", { have = data.gummies, need = cost.gummies }))
		return
	end
	if cost.goldGummies > 0 and data.goldGummies < cost.goldGummies then
		fail(Loc.msg("err.not_enough_gold_gummies", { have = data.goldGummies, need = cost.goldGummies }))
		return
	end

	if cost.gummies > 0 then
		local ok, reason = EconomyService.spendGummies(player, cost.gummies)
		if not ok then
			fail(reason or Loc.msg("err.unknown"))
			return
		end
	end
	if cost.goldGummies > 0 then
		local ok, reason = EconomyService.spendGoldGummies(player, cost.goldGummies)
		if not ok then
			fail(reason or Loc.msg("err.unknown"))
			return
		end
	end

	recycler.level = nextLevel
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)

	Remotes.RecyclerUpgraded:FireClient(player, nextLevel)
	print("[CombRecyclerService]", player.Name, "| Recycler → Level", nextLevel)
end

--------------------------------------------------------------------------------
-- Initialisierung
--------------------------------------------------------------------------------

local function tickAll()
	for _, player in Players:GetPlayers() do
		local data = PlayerService.getData(player)
		if data and data.island.recycler.queued > 0 then
			-- settle() schreibt die fertigen Einheiten ueber awardGummies gut, und
			-- das loest markDirty aus: Hud, Schild und Lampe ziehen darueber nach.
			settle(player, data)
		end
	end
end

function CombRecyclerService.init()
	RateLimiter.connect(Remotes.RequestUpgradeRecycler, "RequestUpgradeRecycler", function(player)
		CombRecyclerService.upgrade(player)
	end)

	-- Offline-Arbeit beim Join: die Zeitmarke steht noch auf dem letzten
	-- Verlassen, settle() rechnet die Zwischenzeit nach (hoechstens
	-- OFFLINE_MAX_SECONDS).
	PlayerService.onDataLoaded(function(player, data)
		settle(player, data)
	end)

	-- Vor dem Speichern beim Verlassen noch einmal verrechnen, damit die
	-- Zeitmarke im Spielstand aktuell ist.
	PlayerService.onPlayerLeaving(function(player, data)
		settle(player, data)
	end)

	print("[CombRecyclerService] Initialisiert")
end

function CombRecyclerService.start()
	task.spawn(function()
		while true do
			task.wait(CombConfig.RECYCLER_TICK_SECONDS)
			local ok, err = pcall(tickAll)
			if not ok then
				warn("[CombRecyclerService] Tick fehlgeschlagen:", err)
			end
		end
	end)
end

return CombRecyclerService
