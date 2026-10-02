--!strict
-- CombatService.luau
-- ServerScriptService/Services/CombatService.luau
--
-- Einzige Zustaendigkeit:
--   - Einen PIT-LAUF validieren, durchsimulieren und abrechnen
--
-- Ein Lauf ist kein einzelner Kampf mehr: der Baerchi kaempft Stage fuer
-- Stage weiter, solange er gewinnt, und seine HP werden zwischen den Stages
-- NICHT zurueckgesetzt. Der Lauf endet wenn er verliert oder bei 0 HP
-- ankommt — danach steht er erschoepft auf dem Plot und muss mit Honig
-- hochgefuettert werden (siehe HoneyService).
--
-- WICHTIG: Kaempfe geben KEINE XP mehr. XP kommt seit v4 ausschliesslich aus
-- verfuettertem Honig. Dieser Service fasst `xp` und `level` deshalb nicht an.
--
-- Gegner-Werte kommen aus CombatConfig, Belohnungen aus EconomyConfig,
-- die Simulation aus CombatCalculator. rebirthMult wird ausschliesslich von
-- EconomyService.awardGummies angewendet — dieser Service rechnet mit
-- Basiswerten.

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
local RateLimiter     = require(ServerScriptService.Util.RateLimiter)

local CombatService = {}

local function fail(player: Player, reason: string)
	Remotes.ActionFailed:FireClient(player, "RequestStartCombat", reason)
end

-- Gegner-Snapshot fuer eine Stage. Die Werte selbst kommen komplett aus
-- CombatConfig — hier wird nur umgepackt.
local function buildEnemySnapshot(pitLevel: number, stage: number): CombatCalculator.CombatSnapshot
	local stats = CombatConfig.getEnemyStats(pitLevel, stage)

	return {
		uid           = string.format("enemy_p%d_s%d", pitLevel, stage),
		stats         = stats,
		hp            = stats.maxHp,
		skillCooldown = 0,
	}
end

function CombatService.startPitRun(player: Player, baerchiUid: string)
	-- Der Cooldown auf RequestStartCombat (1s, NetworkConfig) ist kuerzer als
	-- eine volle PIT-Wiedergabe (Hinlauf + Stages + Nachlauf + Ruecklauf,
	-- leicht mehrere Sekunden). Ohne diese Sperre koennte ein zweiter Klick
	-- mitten in den ersten Lauf hineinstarten und der Figur buchstaeblich die
	-- Fuesse unter dem Koerper wegziehen.
	if PitArenaService.isRunning(player) then
		fail(player, "Der Baerchi kaempft noch im PIT")
		return
	end

	local data = PlayerService.getData(player)
	if not data then return end

	local baerchi = data.island.baerchis[baerchiUid]
	if not baerchi then
		fail(player, "Baerchi nicht gefunden")
		return
	end

	local def = BaerchiConfig.getById(baerchi.configId)
	if not def then
		warn("[CombatService] Unbekannter configId:", baerchi.configId)
		fail(player, "Baerchi-Daten defekt")
		return
	end

	local stats = CombatCalculator.getEffectiveStats(baerchi, def.baseStats)

	-- Der gespeicherte Wert kann ueber maxHp liegen, wenn der Baerchi seit dem
	-- letzten Lauf ein Level gestiegen ist — deshalb immer klemmen.
	local hp = math.clamp(baerchi.currentHp, 0, stats.maxHp)
	if hp <= 0 then
		fail(player, "Der Baerchi ist erschoepft — fuettere ihn erst mit Honig")
		return
	end

	local pitLevel = data.island.pitLevel
	local hpBefore = hp

	local stages: { Types.PitStageResult } = {}
	local stagesCleared = 0
	local baseGummies   = 0

	for stage = 1, CombatConfig.MAX_STAGES_PER_RUN do
		-- CombatCalculator.simulate veraendert die Snapshots die es bekommt —
		-- nach dem Aufruf steht in playerSnapshot.hp die Rest-HP des Baerchis.
		local playerSnapshot: CombatCalculator.CombatSnapshot = {
			uid           = baerchi.uid,
			stats         = stats,
			hp            = hp,
			skillCooldown = 0,
		}

		local result = CombatCalculator.simulate(playerSnapshot, buildEnemySnapshot(pitLevel, stage))
		local won    = result.winnerUid == baerchi.uid

		hp = math.clamp(playerSnapshot.hp, 0, stats.maxHp)

		-- Basiswert: der rebirthMult kommt erst ganz am Ende einmal drauf
		-- (siehe awardGummies weiter unten).
		local stageGummies = 0
		if won then
			stagesCleared += 1
			stageGummies = EconomyConfig.getPitStageReward(pitLevel, stage)
			baseGummies += stageGummies
		end

		table.insert(stages, {
			stage      = stage,
			won        = won,
			rounds     = result.rounds,
			hpAfter    = hp,
			gummiesWon = stageGummies,
		})

		-- Ein Sieg mit 0 HP kann vorkommen (bei Rundenlimit entscheidet der
		-- HP-Vergleich) — dann ist der Lauf trotzdem vorbei.
		if not won or hp <= 0 then
			break
		end
	end

	-- Erschoepfungszustand festhalten: DAS ist die Verbindung zum Fuettern.
	baerchi.currentHp = hp

	local gummiesWon = 0
	if baseGummies > 0 then
		gummiesWon = EconomyService.awardGummies(player, baseGummies)
	end

	local goldGummiesWon = 0
	local goldReward = EconomyConfig.getPitGoldReward(stagesCleared, pitLevel)
	if goldReward > 0 then
		goldGummiesWon = EconomyService.awardGoldGummies(player, goldReward)
	end

	if stagesCleared > 0 then
		data.stats.totalFightsWon += stagesCleared
		if pitLevel > data.stats.highestPitLevel then
			data.stats.highestPitLevel = pitLevel
		end
	end
	-- Ein Lauf endet immer mit genau einer verlorenen Stage — ausser der
	-- Baerchi hat das Stage-Limit erreicht, dann gab es keine Niederlage.
	if #stages > 0 and not stages[#stages].won then
		data.stats.totalFightsLost += 1
	end

	local runResult: Types.PitRunResult = {
		baerchiUid     = baerchiUid,
		stagesCleared  = stagesCleared,
		stages         = stages,
		gummiesWon     = gummiesWon,
		goldGummiesWon = goldGummiesWon,
		hpBefore       = hpBefore,
		hpAfter        = hp,
		maxHp          = stats.maxHp,
	}

	-- Den Client informiert NICHT dieser Service, sondern PitArenaService —
	-- und zwar erst, wenn der Baerchi sichtbar am Kampf-Spot angekommen ist.
	-- Wuerde hier sofort gefeuert, liefe CombatPanels Kampf-UI schon los,
	-- waehrend er noch zur Arena unterwegs waere.
	--
	-- Bewusst VOR markDirty: die Wiedergabe uebernimmt damit die Figur, bevor
	-- die Anzeige-Aktualisierung sie auf den Endzustand setzen wuerde. Sonst
	-- staende der Baerchi schon erschoepft in der Arena, bevor der Kampf
	-- ueberhaupt zu sehen war.
	PitArenaService.play(player, runResult)

	-- Immer syncen: HP und Statistik haben sich geaendert, und awardGummies
	-- kennt diese Aenderungen nicht.
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)

	print(
		"[CombatService]", player.Name,
		"| Baerchi:", baerchi.configId, "Lv.", baerchi.level,
		"| PIT-Level:", pitLevel,
		"| Stages geschafft:", stagesCleared,
		"| Rest-HP:", hp, "/", stats.maxHp,
		"| Gummies:", gummiesWon,
		"| GoldGummies:", goldGummiesWon
	)
end

function CombatService.init()
	RateLimiter.connect(Remotes.RequestStartCombat, "RequestStartCombat", function(player, baerchiUid: any)
		if typeof(baerchiUid) ~= "string" then return end
		CombatService.startPitRun(player, baerchiUid)
	end)

	print("[CombatService] Initialisiert")
end

return CombatService
