--!strict
-- CombatService.luau
-- ServerScriptService/Services/CombatService.luau
--
-- Einzige Zustaendigkeit:
--   - Einen PIT-LAUF validieren, durchsimulieren und (am Ende der Wiedergabe)
--     abrechnen
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
-- Kosten und Startstage rechnet EconomyConfig (dieselben Funktionen nutzt der
-- Client fuer die Anzeige). Der letzte Lauf steht in island.pitProgress und
-- gilt nur auf demselben PIT-Level.
--
-- Gegner-Werte kommen aus CombatConfig, Belohnungen aus EconomyConfig, die
-- Simulation aus CombatCalculator. rebirthMult wendet ausschliesslich
-- EconomyService.awardGummies an.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types            = require(ReplicatedStorage.Network.Types)
local Remotes          = require(ReplicatedStorage.Network.Remotes)
local BaerchiConfig    = require(ReplicatedStorage.Config.BaerchiConfig)
local CombatConfig     = require(ReplicatedStorage.Config.CombatConfig)
local EconomyConfig    = require(ReplicatedStorage.Config.EconomyConfig)
local CombatCalculator = require(ReplicatedStorage.Modules.CombatCalculator)

local PlayerService   = require(ServerScriptService.Services.PlayerService)
local EconomyService  = require(ServerScriptService.Services.EconomyService)
local PitArenaService = require(ServerScriptService.Services.PitArenaService)
local Loc           = require(ReplicatedStorage.Localization.Loc)

local CombatService = {}

export type ResumeChoice = "Fresh" | "Percent" | "Last"

local function fail(player: Player, reason: Types.LocMsg | string)
	Remotes.ActionFailed:FireClient(player, "RequestPetMode", reason)
end

-- Gegner-Snapshot fuer eine Stage. Die Werte selbst kommen komplett aus
-- CombatConfig — hier wird nur umgepackt.
local function buildEnemySnapshot(pitLevel: number, stage: number): CombatCalculator.CombatSnapshot
	local stats = CombatConfig.getEnemyStats(pitLevel, stage)

	return {
		uid    = string.format("enemy_p%d_s%d", pitLevel, stage),
		stats  = stats,
		hp     = stats.maxHp,
		charge = 0,
	}
end

-- Der gespeicherte letzte Lauf, sofern er fuer das AKTUELLE PIT-Level gilt.
function CombatService.getProgress(data: Types.PlayerData): Types.PitProgress?
	local progress = data.island.pitProgress
	if progress and progress.pitLevel == data.island.pitLevel and progress.reachedStage >= 1 then
		return progress
	end
	return nil
end

-- Startstage und Kosten fuer eine Fortsetzungs-Wahl. nil = Wahl ungueltig
-- (kein letzter Lauf auf diesem Level).
function CombatService.getResumeOffer(data: Types.PlayerData, choice: ResumeChoice): (number?, number)
	if choice == "Fresh" then
		return 1, 0
	end

	local progress = CombatService.getProgress(data)
	if not progress then
		return nil, 0
	end

	local startStage = if choice == "Last"
		then progress.reachedStage
		else EconomyConfig.getPitResumePercentStage(progress.reachedStage)

	startStage = math.clamp(startStage, 1, CombatConfig.MAX_STAGES_PER_RUN)
	return startStage, EconomyConfig.getPitResumeCost(data.island.pitLevel, startStage, data.rebirthMult)
end

-- Startet einen PIT-Lauf. Gibt true zurueck, wenn er losgeht — sonst hat der
-- Spieler bereits ein ActionFailed mit dem Grund bekommen.
function CombatService.startPitRun(player: Player, baerchiUid: string, choice: ResumeChoice?): boolean
	-- Ein zweiter Lauf darf nie in einen laufenden hineinstarten (die Figur
	-- wuerde sonst mitten in der Wiedergabe weggezogen).
	if PitArenaService.isRunning(player) then
		fail(player, Loc.msg("err.combat_busy"))
		return false
	end

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

	local pitLevel = data.island.pitLevel
	local startStage, cost = CombatService.getResumeOffer(data, choice or "Fresh")
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
	local lastStage = startStage + CombatConfig.MAX_STAGES_PER_RUN - 1

	-- v15: die Aufladung der Faehigkeit bleibt ueber die Stages erhalten.
	local charge = 0

	for stage = startStage, lastStage do
		local playerSnapshot: CombatCalculator.CombatSnapshot = {
			uid    = baerchi.uid,
			stats  = stats,
			hp     = hp,
			charge = charge,
		}
		local enemySnapshot = buildEnemySnapshot(pitLevel, stage)
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
			gummiesWon = if won then EconomyConfig.getPitStageReward(pitLevel, stage) else 0,
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
		local baseGummies = 0
		for index = 1, played do
			local stage = stages[index]
			table.insert(playedStages, stage)
			if stage.won then
				cleared += 1
				baseGummies += stage.gummiesWon
			end
		end

		local hpAfter = if played > 0 then playedStages[played].hpAfter else hpBefore

		-- Den aktuellen Spielstand holen: der Spieler kann waehrenddessen
		-- gegangen sein (dann laeuft das hier aus onPlayerLeaving, die Daten
		-- sind noch da).
		local current = PlayerService.getData(player)
		local result: Types.PitRunResult = {
			baerchiUid     = baerchiUid,
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

			local goldReward = EconomyConfig.getPitGoldReward(cleared, pitLevel)
			if goldReward > 0 then
				result.goldGummiesWon = EconomyService.awardGoldGummies(player, goldReward)
			end

			if cleared > 0 then
				current.stats.totalFightsWon += cleared
				if pitLevel > current.stats.highestPitLevel then
					current.stats.highestPitLevel = pitLevel
				end
			end
			if not playedStages[played].won then
				current.stats.totalFightsLost += 1
			end

			-- Fuer die Fortsetzungs-Frage: die letzte Stage, in die er
			-- eingetreten ist. Nur wenn das PIT-Level noch dasselbe ist — ein
			-- Ausbau mitten im Lauf macht den Eintrag sinnlos.
			if current.island.pitLevel == pitLevel then
				current.island.pitProgress = {
					pitLevel     = pitLevel,
					reachedStage = playedStages[played].stage,
				}
			end
		end

		PlayerService.markDirty(player)
		PlayerService.saveNow(player)

		print(
			"[CombatService]", player.Name,
			"| PIT", pitLevel, "ab Stage", startStage,
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

	-- Kosten sind schon abgezogen: syncen, damit die Anzeige stimmt.
	if cost > 0 then
		PlayerService.markDirty(player)
	end

	print("[CombatService]", player.Name, "| PIT-Lauf startet: PIT", pitLevel,
		"| ab Stage", startStage, "| Kosten:", cost, "| simuliert:", #stages, "Stages")

	return true
end

function CombatService.init()
	-- Seit v12 kein eigener Remote mehr: gestartet wird ueber die Pet-Leiste
	-- (PetModeService.RequestPetMode).
	print("[CombatService] Initialisiert")
end

return CombatService
