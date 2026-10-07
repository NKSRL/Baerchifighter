--!strict
-- BaerchiAutopilotService.luau
-- ServerScriptService/Services/BaerchiAutopilotService.luau
--
-- Einzige Zustaendigkeit:
--   - Den AUSGERUESTETEN Baerchi von sich aus zum Honig-Teich auf dem
--     eigenen Plot laufen und dort essen lassen, sobald welcher da ist —
--     auch bei vollen HP, solange noch Level drin sind (siehe shouldEat
--     unten). Das Spiel ist auf laengeres AFK-Grinden ausgelegt: wer online
--     ist, aber gerade nicht selbst spielt, soll trotzdem weiter Fortschritt
--     machen, solange Honig produziert wird.
--
-- Essen ist seit dem Equip-System die einzige automatische Aktion im Spiel:
-- Kaempfen, Ausbauen und Fusion loest weiterhin der Spieler selbst aus. Es
-- gibt nur noch EINEN Baerchi auf dem Plot zu sehen (siehe MapService,
-- IslandService) — ein Fuetter-Knopf am Gebaeude fuer "irgendeinen erschoepften
-- Baerchi" waere ohne die anderen sichtbaren Baerchis ohnehin bedeutungslos.
-- Stattdessen kuemmert sich der ausgeruestete Baerchi selbst darum.
--
-- Die eigentliche Heilung/XP-Vergabe passiert weiterhin in HoneyService.feed
-- (einzige Stelle die Honig verbraucht) — dieser Service entscheidet nur WANN
-- und spielt das Hinlaufen sichtbar ab.
--
-- ActivityLock verhindert, dass der Baerchi gleichzeitig zum Teich laeuft
-- UND in den PIT geschickt wird; ein Kampf hat dabei immer Vorrang
-- (PitArenaService nimmt das Schloss notfalls per forceAcquire weg).

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MapConfig        = require(ReplicatedStorage.Config.MapConfig)
local FigurePlacement  = require(ServerScriptService.Util.FigurePlacement)   -- Sammel-Update 1.2
local BaerchiConfig    = require(ReplicatedStorage.Config.BaerchiConfig)
local CombatCalculator = require(ReplicatedStorage.Modules.CombatCalculator)
local TowerConfig      = require(ReplicatedStorage.Config.TowerConfig)
local Types            = require(ReplicatedStorage.Network.Types)

local FigureWalker  = require(ServerScriptService.Util.FigureWalker)
local FigureFX      = require(ServerScriptService.Util.FigureFX)
local ActivityLock  = require(ServerScriptService.Util.ActivityLock)
local PlayerService = require(ServerScriptService.Services.PlayerService)
local MapService    = require(ServerScriptService.Services.MapService)
local HoneyService  = require(ServerScriptService.Services.HoneyService)

local BaerchiAutopilotService = {}

local LOCK_HOLDER = "Autopilot"

-- Wie oft nachgesehen wird, ob der ausgeruestete Baerchi essen gehen sollte.
-- Muss nicht schnell sein: das Fuettern selbst ist nicht zeitkritisch, nur
-- regelmaessig genug, dass es sich von alleine anfuehlt.
local CHECK_INTERVAL = 3

-- Wie lange am Teich "gegessen" wird, bevor es zurueckgeht — rein optisch,
-- der eigentliche Honig-Abzug passiert sofort beim Ankommen. Diese Zeit wird
-- von der Vorbeuge-Bewegung (FigureFX.leanForward) genau ausgefuellt, statt
-- sie einfach abzuwarten.
local EAT_PAUSE_SECONDS = 1.2

local function footPosOf(model: Model): Vector3
	return FigurePlacement.footOf(model)   -- Sammel-Update 1.2
end

-- Braucht der ausgeruestete Baerchi gerade Honig, und ist welcher da?
--
-- Seit v8 gilt das auch bei VOLLEN HP: Honig ist die einzige XP-Quelle im
-- Spiel (siehe HoneyService, Kopf-Kommentar), und das Spiel ist bewusst auf
-- laengeres AFK-Grinden ausgelegt — der ausgeruestete Baerchi soll von
-- alleine weiteressen und -leveln, solange er auf dem Plot steht, nicht nur
-- wenn er gerade verletzt aus dem PIT kommt. Einzige Grenze ist das
-- Maximal-Level: darueber hinaus braechte weiteressen nichts mehr, und der
-- Honig bleibt dann fuer die Heilung nach dem naechsten Kampf liegen.
local function shouldEat(data: Types.PlayerData, baerchi: Types.Baerchi): boolean
	local def = BaerchiConfig.getById(baerchi.configId)
	if not def then return false end

	local maxHp = CombatCalculator.getEffectiveStats(baerchi, def.baseStats).maxHp
	if maxHp <= 0 then return false end

	if HoneyService.getTotalHoney(data) <= 0 then
		return false
	end

	local hpRatio = math.clamp(baerchi.currentHp or maxHp, 0, maxHp) / maxHp
	if hpRatio < 1 then
		return true
	end

	-- Voll geheilt: nur noch fuers Leveln weiteressen, und nur solange das
	-- ueberhaupt noch etwas bringt (Paket 9: mit offenem Endless immer).
	return baerchi.level < BaerchiConfig.MAX_LEVEL or TowerConfig.isEndlessOpen(data.towers.records)
end

local function runEatCycle(player: Player, baerchiUid: string)
	if not ActivityLock.tryAcquire(player, LOCK_HOLDER) then
		return
	end

	task.spawn(function()
		-- Wird gesetzt, sobald feststeht welche Figur bewegt wird — damit sie
		-- nach der Sequenz (auch nach einem Fehler) wieder atmen darf.
		local moved: Model? = nil

		local ok, err = pcall(function()
			local figure = MapService.getBaerchiModel(player, baerchiUid)
			local pond   = MapService.getPondPosition(player)
			if not figure or not pond then
				return
			end

			-- Ruhe-Atmen abschalten, BEVOR der Heimat-Fusspunkt gemessen wird:
			-- sonst waere der gemerkte Punkt um einen Teil des Hubs zu hoch und
			-- der Baerchi kaeme jedes Mal ein Stueckchen ueber dem Boden an.
			-- Ausserdem wuerden sich Idle-Loop und Lauf sonst gegenseitig
			-- ueberschreiben.
			moved = figure
			FigureFX.stopIdle(figure)

			local homeFoot = footPosOf(figure)

			-- Bricht ab, sobald irgendetwas dem Baerchi das Schloss abnimmt
			-- (ein Kampf), er von der Karte verschwindet, oder gar nicht mehr
			-- der ausgeruestete Baerchi ist (equipBaerchi hat inzwischen die
			-- Figur ausgetauscht).
			local function cancelled(): boolean
				return ActivityLock.owner(player) ~= LOCK_HOLDER
					or player.Parent == nil
					or figure.Parent == nil
					or MapService.getBaerchiModel(player, baerchiUid) ~= figure
			end

			FigureWalker.walk(figure, homeFoot, pond, {
				speed       = MapConfig.WALK_SPEED,
				isCancelled = cancelled,
			})
			if cancelled() then return end

			-- HoneyService.feed prueft selbst nochmal ob es sich noch lohnt
			-- (Honig da, Baerchi nicht laengst anderweitig geheilt) — der
			-- Lauf zum Teich dauert ein paar Sekunden, in denen sich das
			-- theoretisch geaendert haben kann.
			if PlayerService.getData(player) then
				HoneyService.feed(player, baerchiUid)
			end

			-- Statt die Fress-Pause einfach abzuwarten: sich hinunterbeugen,
			-- kurz unten bleiben, wieder aufrichten. Dauert exakt so lange wie
			-- das bisherige task.wait — die Sequenz wird also nicht laenger,
			-- man sieht nur, dass er frisst.
			FigureFX.leanForward(figure, MapConfig.EAT_LEAN_DEGREES, EAT_PAUSE_SECONDS)
			if cancelled() then return end

			FigureWalker.walk(figure, pond, homeFoot, {
				speed       = MapConfig.WALK_SPEED,
				isCancelled = cancelled,
			})
		end)

		if not ok then
			warn("[BaerchiAutopilotService] Ess-Sequenz fehlgeschlagen:", err)
		end

		-- Wieder atmen lassen — aber NUR wenn die Figur noch uns gehoert.
		-- Wurde die Sequenz abgebrochen, weil ein Kampf das Schloss per
		-- forceAcquire uebernommen hat, bewegt PitArenaService die Figur
		-- gerade selbst; ein Idle-Loop wuerde ihm dabei dazwischenfunken.
		-- Dieselbe Bedingung, unter der auch das Schloss noch unseres ist.
		if moved and moved.Parent ~= nil and ActivityLock.owner(player) == LOCK_HOLDER then
			FigureFX.idleBob(moved, {
				height = MapConfig.IDLE_BOB_HEIGHT,
				rate   = MapConfig.IDLE_BOB_RATE,
			})
		end

		ActivityLock.release(player, LOCK_HOLDER)
	end)
end

local function tick()
	for _, player in Players:GetPlayers() do
		local data = PlayerService.getData(player)
		if not data then continue end

		local uid = data.island.equippedUid
		if not uid then continue end

		local baerchi = data.island.baerchis[uid]
		if not baerchi then continue end

		if ActivityLock.isFree(player) and shouldEat(data, baerchi) then
			runEatCycle(player, uid)
		end
	end
end

function BaerchiAutopilotService.init()
	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL)

			local ok, err = pcall(tick)
			if not ok then
				warn("[BaerchiAutopilotService] Tick fehlgeschlagen:", err)
			end
		end
	end)

	print("[BaerchiAutopilotService] Initialisiert | Intervall:", CHECK_INTERVAL, "s")
end

return BaerchiAutopilotService
