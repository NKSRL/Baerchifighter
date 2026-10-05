--!strict
-- CombatService.luau
-- ServerScriptService/Services/CombatService.luau
--
-- Einzige Zustaendigkeit:
--   - Einen TOWER-LAUF validieren, durchsimulieren und (am Ende der
--     Wiedergabe) abrechnen
--
-- v15: Es gibt kein PIT-Level mehr. Gekaempft wird im gewaehlten Tower
-- (TowerService.getSelected); Gegner und Stage-Gummies kommen aus TowerConfig,
-- Rekord, Meilensteine und Deckel fuehrt TowerService (recordRun). Bis zu 100
-- Stages werden IN PORTIONEN simuliert (SIM_STAGES_PER_STEP pro task.wait),
-- damit ein langer Lauf keinen Frame-Spike auf dem Server macht.
--
-- Ein Lauf ist kein einzelner Kampf: der Baerchi kaempft Stage fuer Stage
-- weiter, solange er gewinnt, und seine HP werden zwischen den Stages NICHT
-- zurueckgesetzt. Kaempfe geben KEINE XP (die kommt nur aus Honig).
--
-- ============================================================
-- SEIT v12: SIMULATION SOFORT, ABRECHNUNG SPAETER
-- ============================================================
-- Der Lauf wird weiterhin KOMPLETT im Voraus simuliert. Der Server kennt das
-- Ergebnis also, bevor die Figur losgeht — der Client kann am Ausgang nichts
-- drehen. Neu ist nur, WANN abgerechnet wird: nicht mehr vor der Wiedergabe,
-- sondern erst, wenn PitArenaService weiss, wie viele Stages tatsaechlich
-- gespielt wurden. Der Spieler kann den Baerchi naemlich zurueckholen
-- (PetBar, Knopf "Fight" nochmal): dann endet der Lauf nach der aktuellen
-- Stage, und es zaehlen nur die bis dahin geschafften.
--
-- Dafuer bekommt PitArenaService eine Abrechnungs-Funktion (settle) mit. Sie
-- laeuft genau einmal — am Ende der Wiedergabe, beim Zurueckholen, bei einem
-- Abbruch oder, wenn der Spieler mitten im Lauf geht, ueber
-- PlayerService.onPlayerLeaving (dann so, als waere die aktuelle Stage zu Ende
-- gespielt).
--
-- ============================================================
-- FORTSETZUNG (v12)
-- ============================================================
-- Vor dem Lauf kann der Spieler weiter oben einsteigen (PitResumeDialog):
--   "Fresh"   Stage 1, kostenlos
--   "Percent" bei 65 % der Stage-Tiefe seines letzten Laufs
--   "Last"    bei der letzten erreichten Stage
-- Kosten und Startstage rechnet TowerConfig (dieselben Funktionen nutzt der
-- Client fuer die Anzeige). Der letzte Lauf steht pro Tower in
-- island.towerProgress (v15).
--
-- Gegner-Werte und Belohnungen kommen aus TowerConfig, die Simulation aus
-- CombatCalculator. rebirthMult wendet ausschliesslich
-- EconomyService.awardGummies an. Der weiche Deckel: ueber den Deckel hinaus
-- wird gekaempft, Stage-Gummies und GoldGummies gibt es aber nur bis dorthin.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types            = require(ReplicatedStorage.Network.Types)
local Remotes          = require(ReplicatedStorage.Network.Remotes)
local BaerchiConfig    = require(ReplicatedStorage.Config.BaerchiConfig)
local TowerConfig      = require(ReplicatedStorage.Config.TowerConfig)
local CombatCalculator = require(ReplicatedStorage.Modules.CombatCalculator)

local PlayerService   = require(ServerScriptService.Services.PlayerService)
local EconomyService  = require(ServerScriptService.Services.EconomyService)
local PitArenaService = require(ServerScriptService.Services.PitArenaService)
local TowerService    = require(ServerScriptService.Services.TowerService)
local FunnelService = require(ServerScriptService.Services.FunnelService)  -- HBB: Messpunkte
local Loc           = require(ReplicatedStorage.Localization.Loc)

local CombatService = {}

-- So viele Stages werden am Stueck simuliert, dann gibt der Server einen
-- Frame frei (task.wait). Rein technisch, kein Balancing-Wert.
local SIM_STAGES_PER_STEP = 10

-- Spieler, deren Lauf gerade simuliert wird (die Simulation yieldet jetzt —
-- ein zweiter Knopfdruck darf nicht dazwischen einen zweiten Lauf starten).
local _simulating: { [Player]: boolean } = {}

export type ResumeChoice = "Fresh" | "Percent" | "Last"

local function fail(player: Player, reason: Types.LocMsg | string)
	Remotes.ActionFailed:FireClient(player, "RequestPetMode", reason)
end

-- Gegner-Snapshot fuer eine Stage. Die Werte selbst kommen komplett aus
-- TowerConfig — hier wird nur umgepackt.
local function buildEnemySnapshot(towerId: string, stage: number): CombatCalculator.CombatSnapshot
	local stats = TowerConfig.getEnemyStats(towerId, stage)

	return {
		uid    = string.format("enemy_%s_s%d", towerId, stage),
		stats  = stats,
		hp     = stats.maxHp,
		charge = 0,
	}
end

-- Letzte erreichte Stage in diesem Tower (0 = kein Lauf gespeichert).
function CombatService.getProgress(data: Types.PlayerData, towerId: string): number
	local reached = data.island.towerProgress[towerId]
	return if typeof(reached) == "number" and reached >= 1 then reached else 0
end

-- Startstage und Kosten fuer eine Fortsetzungs-Wahl. nil = Wahl ungueltig
-- (kein letzter Lauf in diesem Tower).
function CombatService.getResumeOffer(data: Types.PlayerData, towerId: string, choice: ResumeChoice): (number?, number)
	if choice == "Fresh" then
		return 1, 0
	end

	local reached = CombatService.getProgress(data, towerId)
	if reached <= 0 then
		return nil, 0
	end

	local startStage = if choice == "Last"
		then reached
		else TowerConfig.getResumePercentStage(reached)

	local def = TowerConfig.get(towerId)
	startStage = math.clamp(startStage, 1, if def then def.stages else 1)
	return startStage, TowerConfig.getResumeCost(towerId, startStage, data.rebirthMult)
end

-- Startet einen Tower-Lauf. Gibt true zurueck, wenn er losgeht — sonst hat
-- der Spieler bereits ein ActionFailed mit dem Grund bekommen.
function CombatService.startPitRun(player: Player, baerchiUid: string, choice: ResumeChoice?): boolean
	-- Ein zweiter Lauf darf nie in einen laufenden hineinstarten (die Figur
	-- wuerde sonst mitten in der Wiedergabe weggezogen).
	if PitArenaService.isRunning(player) or _simulating[player] then
		fail(player, Loc.msg("err.combat_busy"))
		return false
	end
	_simulating[player] = true
	local ok, started = pcall(CombatService._startRun, player, baerchiUid, choice)
	_simulating[player] = nil
	if not ok then
		warn("[CombatService] Lauf konnte nicht starten:", started)
		return false
	end
	return started
end

function CombatService._startRun(player: Player, baerchiUid: string, choice: ResumeChoice?): boolean

	local data = PlayerService.getData(player)
	if not data then return false end

	local baerchi = data.island.baerchis[baerchiUid]
	if not baerchi then
		fail(player, Loc.msg("err.baerchi_not_found"))
		return false
	end

	local def = BaerchiConfig.getById(baerchi.configId)
	if not def then
		warn("[CombatService] Unbekannter configId:", baerchi.configId)
		fail(player, Loc.msg("err.baerchi_data_corrupt"))
		return false
	end

	local stats = CombatCalculator.getEffectiveStats(baerchi, def.baseStats)

	-- Der gespeicherte Wert kann ueber maxHp liegen, wenn der Baerchi seit dem
	-- letzten Lauf ein Level gestiegen ist — deshalb immer klemmen.
	local hp = math.clamp(baerchi.currentHp, 0, stats.maxHp)
	if hp <= 0 then
		fail(player, Loc.msg("err.combat_exhausted"))
		return false
	end

	local towerId = TowerService.getSelected(data)
	local tower = TowerConfig.get(towerId)
	if not tower then
		fail(player, Loc.msg("err.tower_unknown"))
		return false
	end
	-- Deckel beim START festhalten: ein Rebirth waehrend des Laufs ist
	-- unmoeglich (der Lauf gehoert zur Insel), sicher ist sicher.
	local capStage = TowerService.getStageCap(data, towerId)

	local startStage, cost = CombatService.getResumeOffer(data, towerId, choice or "Fresh")
	if not startStage then
		fail(player, Loc.msg("err.combat_no_last_run"))
		return false
	end

	if cost > 0 then
		local ok, reason = EconomyService.spendGummies(player, cost)
		if not ok then
			fail(player, reason)
			return false
		end
	end

	local hpBefore = hp

	-- ============================================================
	-- SIMULATION (komplett im Voraus)
	-- ============================================================
	local stages: { Types.PitStageResult } = {}
	-- v15: pro Stage die einzelnen Zuege fuer die Wiedergabe (Stoesse,
	-- Faehigkeiten). Bleibt auf dem Server — PitArenaService spielt sie ab,
	-- der Client sieht nur das Ergebnis in der Welt.
	local beats: { { Types.FightBeat } } = {}
	local lastStage = tower.stages

	-- v15: die Aufladung der Faehigkeit bleibt ueber die Stages erhalten.
	local charge = 0
	local simulatedInStep = 0

	for stage = startStage, lastStage do
		-- In Portionen: nach SIM_STAGES_PER_STEP Stages einen Frame freigeben.
		simulatedInStep += 1
		if simulatedInStep > SIM_STAGES_PER_STEP then
			simulatedInStep = 1
			task.wait()
			if player.Parent == nil then
				-- Gegangen, waehrend simuliert wurde: bezahlte Fortsetzung zurueck.
				if cost > 0 then EconomyService.awardGummiesFlat(player, cost) end
				return false
			end
		end

		local playerSnapshot: CombatCalculator.CombatSnapshot = {
			uid    = baerchi.uid,
			stats  = stats,
			hp     = hp,
			charge = charge,
		}
		local enemySnapshot = buildEnemySnapshot(towerId, stage)
		local enemyMax = math.max(1, enemySnapshot.stats.maxHp)

		local result = CombatCalculator.simulate(playerSnapshot, enemySnapshot, true)
		local won    = result.winnerUid == baerchi.uid

		hp = math.clamp(playerSnapshot.hp, 0, stats.maxHp)
		charge = playerSnapshot.charge or 0

		local stageBeats: { Types.FightBeat } = {}
		for _, entry in result.log do
			table.insert(stageBeats, {
				actor   = entry.actor,
				kind    = entry.kind,
				selfHp  = math.clamp(entry.attackerHpAfter / math.max(1, stats.maxHp), 0, 1),
				enemyHp = math.clamp(entry.defenderHpAfter / enemyMax, 0, 1),
				charge  = entry.chargeA,
				skillId = entry.skillId,
			})
		end
		table.insert(beats, stageBeats)

		table.insert(stages, {
			stage      = stage,
			won        = won,
			rounds     = result.rounds,
			hpAfter    = hp,
			-- Basiswert ohne rebirthMult; ausgezahlt wird erst in settle.
			-- Weicher Deckel: ueber dem Deckel gibt es nichts.
			gummiesWon = if won and stage <= capStage then TowerConfig.getStageReward(towerId, stage) else 0,
			-- v14: fuer die Faehigkeiten-Show (PitArenaService -> SkillFX)
			skillUses       = result.skillUses,
			firstSkillRound = result.firstSkillRound,
		})

		-- Ein Sieg mit 0 HP kann vorkommen (bei Rundenlimit entscheidet der
		-- HP-Vergleich) — dann ist der Lauf trotzdem vorbei.
		if not won or hp <= 0 then
			break
		end
	end

	local fullRun: Types.PitRunResult = {
		baerchiUid     = baerchiUid,
		towerId        = towerId,
		capStage       = capStage,
		startStage     = startStage,
		recalled       = false,
		stagesCleared  = 0,
		stages         = stages,
		gummiesWon     = 0,
		goldGummiesWon = 0,
		hpBefore       = hpBefore,
		hpAfter        = hpBefore,
		maxHp          = stats.maxHp,
	}

	-- ============================================================
	-- ABRECHNUNG (laeuft genau einmal, aufgerufen von PitArenaService)
	-- ============================================================
	-- played = wie viele Stages tatsaechlich gespielt wurden (0..#stages).
	-- recalled = der Spieler hat zurueckgeholt.
	local settled: Types.PitRunResult? = nil

	local function settle(played: number, recalled: boolean): Types.PitRunResult
		if settled then
			return settled
		end

		played = math.clamp(math.floor(played), 0, #stages)

		local playedStages: { Types.PitStageResult } = {}
		local cleared     = 0
		local paidCleared = 0   -- geschaffte Stages bis zum Deckel (GoldGummies)
		local highestWon  = 0
		local baseGummies = 0
		for index = 1, played do
			local stage = stages[index]
			table.insert(playedStages, stage)
			if stage.won then
				cleared += 1
				baseGummies += stage.gummiesWon
				highestWon = math.max(highestWon, stage.stage)
				if stage.stage <= capStage then
					paidCleared += 1
				end
			end
		end

		local hpAfter = if played > 0 then playedStages[played].hpAfter else hpBefore

		-- Den aktuellen Spielstand holen: der Spieler kann waehrenddessen
		-- gegangen sein (dann laeuft das hier aus onPlayerLeaving, die Daten
		-- sind noch da).
		local current = PlayerService.getData(player)
		local result: Types.PitRunResult = {
			baerchiUid     = baerchiUid,
			towerId        = towerId,
			capStage       = capStage,
			startStage     = startStage,
			recalled       = recalled,
			corrected      = played < #stages,
			stagesCleared  = cleared,
			stages         = playedStages,
			gummiesWon     = 0,
			goldGummiesWon = 0,
			hpBefore       = hpBefore,
			hpAfter        = hpAfter,
			maxHp          = stats.maxHp,
		}

		if not current then
			settled = result
			return result
		end

		if played == 0 then
			-- Zurueckgeholt, bevor die erste Stage begann: nichts passiert.
			-- Eine bezahlte Fortsetzung wird erstattet — der Spieler hat
			-- nichts davon gehabt.
			if cost > 0 then
				EconomyService.awardGummiesFlat(player, cost)
			end
		else
			local fighter = current.island.baerchis[baerchiUid]
			if fighter then
				-- Erschoepfungszustand festhalten: DAS ist die Verbindung zum
				-- Fuettern.
				fighter.currentHp = hpAfter
			end

			if baseGummies > 0 then
				result.gummiesWon = EconomyService.awardGummies(player, baseGummies)
			end

			local goldReward = TowerConfig.getRunGold(towerId, paidCleared)
			if goldReward > 0 then
				result.goldGummiesWon = EconomyService.awardGoldGummies(player, goldReward)
			end

			if cleared > 0 then
				current.stats.totalFightsWon += cleared
			end
			if not playedStages[played].won then
				current.stats.totalFightsLost += 1
			end

			-- v15: Rekord, Meilensteine, Deckel-Hinweis (TowerService).
			local newRecord, capReached = TowerService.recordRun(player, current, towerId, highestWon)
			result.newRecord  = newRecord
			result.capReached = capReached

			-- Fuer die Fortsetzungs-Frage: die letzte Stage, in die er
			-- eingetreten ist — pro Tower.
			current.island.towerProgress[towerId] = playedStages[played].stage
		end

		FunnelService.step(player, "F06_FirstFightEnded")
		PlayerService.markDirty(player)
		PlayerService.saveNow(player)

		print(
			"[CombatService]", player.Name,
			"| Tower", towerId, "ab Stage", startStage,
			"| gespielt:", played, "/", #stages,
			if recalled then "(zurueckgeholt)" else "",
			"| geschafft:", cleared,
			"| HP:", hpAfter, "/", stats.maxHp,
			"| Gummies:", result.gummiesWon,
			"| Gold:", result.goldGummiesWon
		)

		settled = result
		return result
	end

	-- Den Client informiert NICHT dieser Service, sondern PitArenaService — am
	-- Ende der Wiedergabe mit dem abgerechneten Ergebnis.
	PitArenaService.play(player, fullRun, settle, beats)
	FunnelService.step(player, "F05_FirstFightStarted")

	-- Kosten sind schon abgezogen: syncen, damit die Anzeige stimmt.
	if cost > 0 then
		PlayerService.markDirty(player)
	end

	print("[CombatService]", player.Name, "| Tower-Lauf startet: Tower", towerId,
		"| ab Stage", startStage, "| Kosten:", cost, "| simuliert:", #stages, "Stages")

	return true
end

function CombatService.init()
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		_simulating[player] = nil
	end)

	-- Seit v12 kein eigener Remote mehr: gestartet wird ueber die Pet-Leiste
	-- (PetModeService.RequestPetMode).
	print("[CombatService] Initialisiert")
end

return CombatService
