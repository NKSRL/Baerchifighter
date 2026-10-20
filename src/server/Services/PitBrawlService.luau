--!strict
-- PitBrawlService.luau
-- ServerScriptService/Services/PitBrawlService.luau
--
-- Einzige Zustaendigkeit:
--   1. Phase 3 — Echte Tower-Kaempfe zwischen Bärchis im Event-Pit (auch ausserhalb
--      von Events): sobald mindestens zwei freie Bärchis unterschiedlicher Spieler
--      im Event-Pit sind, laufen sie aufeinander zu (MapConfig.FIGHT_SPACING),
--      erhalten echte HP- und Charge-Leisten (FightBars) und tragen Zug um Zug ein
--      echtes Tower-Duell (CombatCalculator + FightTimeline + FigureFX.clash +
--      SkillFXPlay) aus. Das unterlegene Bärchi kippt bei 0 HP um
--      (FigureFX.defeatCollapse) und kehrt auf seinen Heimat-Plot zurueck.
--   2. Phase 4 — Aktive Spieler-Verfolgung & 1-Shot-Kill im Event-Pit: sobald kein
--      fremdes Bärchi mehr im Event-Pit steht, verfolgt ein freies Bärchi im Pit
--      jeden lebendigen fremden Spieler im Pit-Radius (50 Studs) aktiv mit
--      Verfolgungs-Tempo (CHASE_SPEED) und besiegt ihn in Standard-Angriffsreichweite
--      (ATTACK_RANGE = 7 Studs) mit einem wuchtigen 1-Shot (humanoid.Health = 0).

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local RunService          = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace           = game:GetService("Workspace")

local Audio            = require(ReplicatedStorage.Audio)
local BaerchiConfig    = require(ReplicatedStorage.Config.BaerchiConfig)
local EventConfig      = require(ReplicatedStorage.Config.EventConfig)
local FeatureFlags     = require(ReplicatedStorage.Config.FeatureFlags)
local MapConfig        = require(ReplicatedStorage.Config.MapConfig)
local SkillConfig      = require(ReplicatedStorage.Config.SkillConfig)
local SkillFXConfig    = require(ReplicatedStorage.Config.SkillFXConfig)
local CombatCalculator = require(ReplicatedStorage.Modules.CombatCalculator)
local FightTimeline    = require(ReplicatedStorage.Modules.FightTimeline)
local Remotes          = require(ReplicatedStorage.Network.Remotes)
local Types            = require(ReplicatedStorage.Network.Types)

local EventParticipationService = require(ServerScriptService.Services.EventParticipationService)
local MapService                = require(ServerScriptService.Services.MapService)
local PlayerService             = require(ServerScriptService.Services.PlayerService)
local FightBars                 = require(ServerScriptService.Util.FightBars)
local FigureFX                  = require(ServerScriptService.Util.FigureFX)
local FigurePlacement           = require(ServerScriptService.Util.FigurePlacement)
local FigureWalker              = require(ServerScriptService.Util.FigureWalker)

type Presence = EventParticipationService.Presence

type DuelBeat = {
	beat    : Types.FightBeat,
	chargeA : number,
	chargeB : number,
}

local PitBrawlService = {}

local _inDuel: { [Presence]: boolean } = {}
local _inChase: { [Presence]: boolean } = {}
local _stopChase: { [Presence]: boolean } = {}

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function flatDist(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function clampToPit(pos: Vector3, center: Vector3, radius: number,groundY: number): Vector3
	local rel = Vector3.new(pos.X - center.X, 0, pos.Z - center.Z)
	local maxR = math.max(4, radius - 4)
	if rel.Magnitude > maxR then
		rel = rel.Unit * maxR
	end
	return Vector3.new(center.X + rel.X, groundY, center.Z + rel.Z)
end

-- Effektive Kampfwerte eines Teilnehmers aus seinen echten Bärchi-Daten.
local function buildSnapshot(part: Presence, fallbackUid: string): CombatCalculator.CombatSnapshot
	local data = PlayerService.getData(part.player)
	local found = if data then data.island.baerchis[part.baerchiUid] else nil
	if found then
		local baerchi: Types.Baerchi = found
		local effLevel = EventParticipationService.getWeakenedLevel(part.baerchiUid, baerchi.level)
		if effLevel ~= baerchi.level then
			local copy = table.clone(baerchi)
			copy.level = effLevel
			baerchi = copy
		end
		local def = BaerchiConfig.getById(baerchi.configId)
		if def then
			local ok, stats = pcall(CombatCalculator.getEffectiveStats, baerchi, def.baseStats)
			if ok and stats then
				return {
					uid    = fallbackUid,
					stats  = stats,
					hp     = math.max(1, stats.maxHp),
					charge = 0,
				}
			end
		end
	end

	local fallbackStats: CombatCalculator.FighterStats = {
		maxHp   = 100,
		atk     = 15,
		spd     = 1.0,
		pwr     = 0,
		skillId = "BasicPunch",
	}
	return {
		uid    = fallbackUid,
		stats  = fallbackStats,
		hp     = 100,
		charge = 0,
	}
end

-- Baut die Zug-Liste samt beidseitigem Charge-Stand (A und B) fuer das Duell.
local function buildDuelBeats(
	log: { Types.RoundLogEntry },
	statsA: CombatCalculator.FighterStats,
	statsB: CombatCalculator.FighterStats
): ({ Types.FightBeat }, { DuelBeat })
	local maxHpA = math.max(1, statsA.maxHp)
	local maxHpB = math.max(1, statsB.maxHp)

	local skillB = SkillConfig.getById(statsB.skillId)
	local costB = if skillB then (skillB.charge or 0) else 0
	local canChargeB = skillB ~= nil and costB > 0 and skillB.effectType ~= "Passive"
		and skillB.effectType ~= "LastStand" and skillB.effectType ~= "Revive"
	local rawChargeB = 0

	local timelineBeats: { Types.FightBeat } = {}
	local duelBeats: { DuelBeat } = {}

	for _, entry in log do
		if entry.actor == "B" then
			if entry.kind == "skill" and canChargeB then
				rawChargeB = math.max(0, rawChargeB - costB)
			elseif entry.kind == "hit" and canChargeB then
				local gain = SkillConfig.CHARGE.PER_HIT * (1 + statsB.pwr * SkillConfig.CHARGE.PWR_FACTOR)
				rawChargeB = math.min(costB, rawChargeB + gain)
			end
		end
		local chargeRatioB = if canChargeB and costB > 0 then math.clamp(rawChargeB / costB, 0, 1) else 0

		local fb: Types.FightBeat = {
			actor   = entry.actor,
			kind    = entry.kind,
			selfHp  = math.clamp(entry.attackerHpAfter / maxHpA, 0, 1),
			enemyHp = math.clamp(entry.defenderHpAfter / maxHpB, 0, 1),
			charge  = entry.chargeA,
			skillId = entry.skillId,
		}
		table.insert(timelineBeats, fb)
		table.insert(duelBeats, {
			beat    = fb,
			chargeA = entry.chargeA,
			chargeB = chargeRatioB,
		})
	end

	return timelineBeats, duelBeats
end

--------------------------------------------------------------------------------
-- Phase 3: Echte Tower-Kaempfe zwischen Bärchis im Event-Pit
--------------------------------------------------------------------------------

function PitBrawlService.runDuel(a: Presence, b: Presence): (Presence, Presence)
	if a == b or a.player == b.player then
		return a, b
	end
	if _inDuel[a] or _inDuel[b] then
		return a, b
	end

	-- Laufende Spieler-Jagd oder Handler-Bewegung sofort unterbrechen
	_stopChase[a] = true
	_stopChase[b] = true
	a.cancelWalk  = true
	b.cancelWalk  = true

	-- Kurz warten, falls noch ein fremder Schritt (walkTo / Chase) den Frame abschliesst
	local waitStart = os.clock()
	while (a.busy or b.busy) and os.clock() - waitStart < 0.2 do
		RunService.Heartbeat:Wait()
	end

	if not EventParticipationService.stillHere(a) then
		return b, a
	end
	if not EventParticipationService.stillHere(b) then
		return a, b
	end

	_inDuel[a]   = true
	_inDuel[b]   = true
	a.busy       = true
	b.busy       = true
	a.cancelWalk = false
	b.cancelWalk = false

	local winner: Presence = a
	local loser: Presence  = b

	local figA = a.figure
	local figB = b.figure
	local fxFolder = Workspace:FindFirstChild("EventPitBrawlFX") :: Folder?
	if not fxFolder then
		local created = Instance.new("Folder")
		created.Name = "EventPitBrawlFX"
		created.Parent = Workspace
		fxFolder = created
	end

	local ok, err = pcall(function()
		FigureFX.stopIdle(figA)
		FigureFX.stopIdle(figB)

		local center  = MapService.getEventPitPosition()
		local radius  = MapService.getEventPitRadius()
		local footA   = FigurePlacement.footOf(figA)
		local footB   = FigurePlacement.footOf(figB)
		local groundY = center.Y

		local delta = flat(footB - footA)
		local dir   = if delta.Magnitude > 0.1 then delta.Unit else Vector3.new(1, 0, 0)
		local mid   = clampToPit((footA + footB) * 0.5, center, radius, groundY)

		local halfGap = MapConfig.FIGHT_SPACING * 0.5
		local posA    = clampToPit(mid - dir * halfGap, center, radius, groundY)
		local posB    = clampToPit(mid + dir * halfGap, center, radius, groundY)

		local function bothValid(): boolean
			return EventParticipationService.stillHere(a)
				and EventParticipationService.stillHere(b)
				and figA.Parent ~= nil
				and figB.Parent ~= nil
		end

		-- Beide Bärchis laufen gleichzeitig auf Kampfdistanz (FIGHT_SPACING) zusammen
		local doneA = false
		local doneB = false
		local walkSpeed = EventConfig.PIT_BRAWL.DUEL_WALK_SPEED

		task.spawn(function()
			FigureWalker.walk(figA, footA, posA, {
				speed       = walkSpeed,
				isCancelled = function(): boolean
					return not bothValid()
				end,
			})
			doneA = true
		end)
		task.spawn(function()
			FigureWalker.walk(figB, footB, posB, {
				speed       = walkSpeed,
				isCancelled = function(): boolean
					return not bothValid()
				end,
			})
			doneB = true
		end)

		while not (doneA and doneB) do
			RunService.Heartbeat:Wait()
		end

		if not bothValid() then
			if not EventParticipationService.stillHere(a) then
				winner, loser = b, a
			else
				winner, loser = a, b
			end
			return
		end

		-- Gegeneinander ausrichten und HP-/Charge-Balken wie im Tower anbringen
		FigurePlacement.placeLookingAt(figA, posA, posB)
		FigurePlacement.placeLookingAt(figB, posB, posA)

		local hpFillA     = FightBars.attachHealthBar(figA, MapConfig.FIGHT_BAR_SELF_COLOR)
		local chargeFillA = FightBars.attachChargeBar(figA)
		local hpFillB     = FightBars.attachHealthBar(figB, MapConfig.FIGHT_BAR_ENEMY_COLOR)
		local chargeFillB = FightBars.attachChargeBar(figB)

		FigureFX.idleBob(figA, {
			height = MapConfig.IDLE_BOB_HEIGHT,
			rate   = MapConfig.IDLE_BOB_RATE,
		})
		FigureFX.idleBob(figB, {
			height = MapConfig.IDLE_BOB_HEIGHT,
			rate   = MapConfig.IDLE_BOB_RATE,
		})

		-- Echte Kampf-Simulation mit den effektiven Werten beider Bärchis
		local snapA  = buildSnapshot(a, "A_" .. a.baerchiUid)
		local snapB  = buildSnapshot(b, "B_" .. b.baerchiUid)
		local statsA = snapA.stats
		local statsB = snapB.stats
		local sim    = CombatCalculator.simulate(snapA, snapB, true)
		local aWon   = sim.winnerUid == snapA.uid

		if aWon then
			winner, loser = a, b
		else
			winner, loser = b, a
		end

		local timelineBeats, duelBeats = buildDuelBeats(sim.log, statsA, statsB)
		if #timelineBeats == 0 then
			local fallbackBeat: Types.FightBeat = {
				actor   = if aWon then "A" else "B",
				kind    = "hit",
				selfHp  = if aWon then 0.5 else 0,
				enemyHp = if aWon then 0 else 0.5,
				charge  = 0,
				skillId = nil,
			}
			timelineBeats = { fallbackBeat }
			duelBeats = { { beat = fallbackBeat, chargeA = 0, chargeB = 0 } }
		end

		local plan  = FightTimeline.plan(timelineBeats, 1, true)
		local tempo = plan.tempo

		task.wait(MapConfig.FIGHT_ENEMY_INTRO_SECONDS * tempo)
		if not bothValid() then return end

		local shownFullA = false
		local shownFullB = false

		for _, beatIndex in plan.indices do
			local entry   = duelBeats[beatIndex]
			local beat    = entry.beat
			local isA     = beat.actor == "A"
			local attFig  = if isA then figA else figB
			local defFig  = if isA then figB else figA
			local attHome = if isA then posA else posB
			local defHome = if isA then posB else posA
			local attOwner = if isA then a.player else b.player
			local attChargeFill = if isA then chargeFillA else chargeFillB
			local isSkill = FightTimeline.isSkillBeat(beat)

			local function onImpact()
				local barSeconds = MapConfig.FIGHT_BEAT_SECONDS * tempo * 0.5
				FightBars.tweenFill(hpFillA, beat.selfHp, barSeconds)
				FightBars.tweenFill(hpFillB, beat.enemyHp, barSeconds)
				FightBars.setCharge(chargeFillA, entry.chargeA, barSeconds)
				FightBars.setCharge(chargeFillB, entry.chargeB, barSeconds)

				if defFig.Parent ~= nil then
					FigureFX.hitFlash(defFig, MapConfig.FIGHT_HIT_FLASH_COLOR, MapConfig.FIGHT_HIT_FLASH_SECONDS)
				end
				local contact = (posA + posB) * 0.5 + Vector3.new(0, 1.5, 0)
				if fxFolder and fxFolder.Parent ~= nil then
					FigureFX.burstAt(
						contact,
						MapConfig.FIGHT_HIT_FLASH_COLOR,
						fxFolder,
						MapConfig.FIGHT_BUMP_SPARKS * (if isSkill then 3 else 1)
					)
					local bumpName = if isSkill then "hitHeavy" else "hit"
					FigureFX.soundAt(
						contact,
						Audio.sfxId(bumpName),
						Audio.SFX[bumpName].volume,
						fxFolder,
						0.92 + math.random() * 0.16
					)
				end
			end

			if beat.kind == "stunned" then
				FightBars.setCharge(attChargeFill, if isA then entry.chargeA else entry.chargeB, 0.1)
				FigureFX.stagger(attFig, MapConfig.FIGHT_BEAT_SECONDS * tempo)
			else
				if isSkill then
					FightBars.setCharge(attChargeFill, 1, 0.1)
					local defaultSkill = if isA then statsA.skillId else statsB.skillId
					local showId = beat.skillId or defaultSkill
					if showId then
						local full = if isA then not shownFullA else not shownFullB
						if isA then
							shownFullA = true
						else
							shownFullB = true
						end
						Remotes.SkillFXPlay:FireAllClients({
							owner    = attOwner.UserId,
							skillId  = showId,
							full     = full,
							attacker = attFig,
							target   = defFig,
							center   = (posA + posB) * 0.5,
						})
						task.wait(SkillFXConfig.getDuration(showId, full) * (if full then 1 else tempo))
						if not bothValid() then return end
					end
				end

				local seconds = FightTimeline.beatSeconds(beat) * tempo
				FigureFX.clash(attFig, defFig, attHome, defHome, {
					seconds   = seconds,
					gap       = MapConfig.FIGHT_CONTACT_GAP,
					hop       = MapConfig.FIGHT_HOP_HEIGHT * (if isSkill then 1.6 else 1),
					knockback = if isSkill then MapConfig.FIGHT_SKILL_KNOCKBACK else MapConfig.FIGHT_KNOCKBACK,
					step      = MapConfig.FIGHT_ENEMY_STEP_SHARE,
					onImpact  = onImpact,
				})
			end

			if not bothValid() then return end
		end

		-- Endstand auf den Leisten setzen (Verlierer = 0 HP)
		local lastBeat = timelineBeats[#timelineBeats]
		FightBars.tweenFill(hpFillA, if aWon then math.max(0.05, lastBeat.selfHp) else 0, 0.15)
		FightBars.tweenFill(hpFillB, if aWon then 0 else math.max(0.05, lastBeat.enemyHp), 0.15)

		-- KO-Animation wie im Tower: Verlierer kippt sichtbar um
		local loserFig  = if aWon then figB else figA
		local loserSpot = if aWon then posB else posA
		if loserFig.Parent ~= nil then
			FigureFX.defeatCollapse(loserFig, MapConfig.FIGHT_KO_SECONDS * tempo)
		end

		-- Balken vor der Heimkehr entfernen und Verlierer fuer den Heimweg wieder aufrichten
		FightBars.removeHealthBar(figA)
		FightBars.removeHealthBar(figB)
		if loserFig.Parent ~= nil then
			FigureFX.stopIdle(loserFig)
			FigurePlacement.place(loserFig, loserSpot, loserFig:GetPivot().Rotation)
		end
	end)

	if not ok then
		warn("[PitBrawlService] Duell fehlgeschlagen:", err)
	end

	-- Sicherstellen, dass niemals Kampfbalken zurueckbleiben
	if figA.Parent ~= nil then
		FightBars.removeHealthBar(figA)
	end
	if figB.Parent ~= nil then
		FightBars.removeHealthBar(figB)
	end

	_inDuel[a] = nil
	_inDuel[b] = nil
	EventParticipationService.releaseBusy(a)
	EventParticipationService.releaseBusy(b)

	-- Besiegtes Bärchi zurueck auf seinen Heimat-Plot schicken
	if EventParticipationService.stillHere(loser) then
		EventParticipationService.recall(loser.player)
		if EventParticipationService.stillHere(loser) then
			EventParticipationService.finishHome(loser)
		end
	end

	-- Sieger bleibt im Event-Pit und geht sofort in den naechsten Zustand ueber
	if EventParticipationService.stillHere(winner) then
		EventParticipationService.playIdle(winner.figure)
	end

	return winner, loser
end

--------------------------------------------------------------------------------
-- Phase 4: Aktive Spieler-Verfolgung & 1-Shot-Kill im Event-Pit
--------------------------------------------------------------------------------

-- Prueft, ob sich mindestens ein fremdes Bärchi (anderer Besitzer) im Event-Pit befindet.
local function hasForeignBaerchi(hunter: Presence): boolean
	for _, part in EventParticipationService.getParticipants() do
		if part.player ~= hunter.player then
			return true
		end
	end
	return false
end

-- Sucht den naechsten lebendigen fremden Spieler innerhalb des Event-Pit-Radius (50 Studs).
local function findTargetPlayer(
	owner: Player,
	fromFoot: Vector3,
	center: Vector3,
	radius: number
): { player: Player, root: BasePart, humanoid: Humanoid }?
	local best: { player: Player, root: BasePart, humanoid: Humanoid }? = nil
	local bestDist = math.huge

	for _, other in Players:GetPlayers() do
		if other ~= owner then
			local character = other.Character
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
			if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
				if flatDist(root.Position, center) <= radius then
					local d = flatDist(root.Position, fromFoot)
					if d < bestDist then
						bestDist = d
						best = {
							player   = other,
							root     = root,
							humanoid = humanoid,
						}
					end
				end
			end
		end
	end

	return best
end

local function startChase(hunter: Presence)
	if _inChase[hunter] or _inDuel[hunter] or hunter.busy then
		return
	end

	_inChase[hunter]  = true
	_stopChase[hunter] = nil
	hunter.busy       = true
	hunter.cancelWalk = false

	task.spawn(function()
		local cfg    = EventConfig.PIT_BRAWL
		local figure = hunter.figure
		local fxFolder = Workspace:FindFirstChild("EventPitBrawlFX") :: Folder?
		if not fxFolder then
			local created = Instance.new("Folder")
			created.Name = "EventPitBrawlFX"
			created.Parent = Workspace
			fxFolder = created
		end

		local ok, err = pcall(function()
			FigureFX.stopIdle(figure)

			local center     = MapService.getEventPitPosition()
			local radius     = MapService.getEventPitRadius()
			local foot       = FigurePlacement.footOf(figure)
			local groundY    = foot.Y
			local traveled   = 0
			local bobHeight  = MapConfig.WALK_BOB_HEIGHT
			local bobPerStud = math.max(
				MapConfig.WALK_BOB_PER_STUD * MapConfig.WALK_SPEED / math.max(cfg.CHASE_SPEED, 1),
				1e-3
			)
			local leanRad    = math.rad(MapConfig.WALK_LEAN_DEGREES)

			while not _stopChase[hunter] and not hunter.cancelWalk and EventParticipationService.stillHere(hunter) do
				-- Sobald ein fremdes Bärchi das Pit betritt, haben Pet-Duelle Vorrang
				if hasForeignBaerchi(hunter) then
					break
				end

				local target = findTargetPlayer(hunter.player, foot, center, radius)
				if not target then
					break
				end

				local targetPos = Vector3.new(target.root.Position.X, groundY, target.root.Position.Z)
				local delta     = targetPos - foot
				local dist      = delta.Magnitude

				-- In Standard-Angriffsreichweite (7 Studs): Ausfallschritt + 1-Shot-Kill!
				if dist <= cfg.ATTACK_RANGE then
					FigurePlacement.placeLookingAt(figure, foot, targetPos)
					local impactPos = target.root.Position
					if fxFolder and fxFolder.Parent ~= nil then
						FigureFX.burstAt(
							impactPos,
							MapConfig.FIGHT_HIT_FLASH_COLOR,
							fxFolder,
							MapConfig.FIGHT_BUMP_SPARKS * 3
						)
						FigureFX.soundAt(
							impactPos,
							Audio.sfxId("hitHeavy"),
							Audio.SFX.hitHeavy.volume,
							fxFolder,
							0.95 + math.random() * 0.10
						)
					end
					if target.humanoid.Health > 0 then
						target.humanoid.Health = 0
					end
					FigureFX.attackLunge(figure, targetPos, cfg.LUNGE_DISTANCE, cfg.LUNGE_SECONDS)
					foot = FigurePlacement.footOf(figure)
					groundY = foot.Y
					continue
				end

				-- Einen Frame mit Verfolgungs-Tempo (CHASE_SPEED) auf den Spieler zulaufen
				local dt = RunService.Heartbeat:Wait()
				if _stopChase[hunter] or hunter.cancelWalk or not EventParticipationService.stillHere(hunter) then
					break
				end

				local livePos   = Vector3.new(target.root.Position.X, groundY, target.root.Position.Z)
				local liveDelta = livePos - foot
				local liveDist  = liveDelta.Magnitude
				if liveDist > 1e-2 then
					local dir    = liveDelta.Unit
					local step   = math.min(liveDist, cfg.CHASE_SPEED * dt)
					foot         = clampToPit(foot + dir * step, center, radius, groundY)
					traveled    += step
					local bob    = math.abs(math.sin(traveled * bobPerStud * math.pi)) * bobHeight
					local facing = CFrame.lookAt(Vector3.zero, dir)
					FigurePlacement.place(
						figure,
						foot + Vector3.new(0, bob, 0),
						facing * CFrame.Angles(leanRad, 0, 0)
					)
				end
			end

			-- Nach Ende der Jagd (Spieler besiegt oder aus dem Pit geflohen):
			-- zurueck zum eigenen Standplatz im Event-Pit laufen, sofern kein neues Duell wartet.
			if not _stopChase[hunter]
				and not hunter.cancelWalk
				and EventParticipationService.stillHere(hunter)
				and not hasForeignBaerchi(hunter)
			then
				local currentFoot = FigurePlacement.footOf(figure)
				local standFoot   = Vector3.new(hunter.standFoot.X, currentFoot.Y, hunter.standFoot.Z)
				if flatDist(currentFoot, standFoot) > 1.0 then
					FigureWalker.walk(figure, currentFoot, standFoot, {
						speed       = cfg.CHASE_SPEED,
						isCancelled = function(): boolean
							return _stopChase[hunter] == true
								or hunter.cancelWalk == true
								or not EventParticipationService.stillHere(hunter)
								or hasForeignBaerchi(hunter)
								or findTargetPlayer(hunter.player, FigurePlacement.footOf(figure), center, radius) ~= nil
						end,
					})
				end
				if EventParticipationService.stillHere(hunter) then
					FigurePlacement.placeLookingAt(figure, FigurePlacement.footOf(figure), center)
				end
			end
		end)

		if not ok then
			warn("[PitBrawlService] Spieler-Verfolgung fehlgeschlagen:", err)
		end

		_inChase[hunter]   = nil
		_stopChase[hunter] = nil
		EventParticipationService.releaseBusy(hunter)

		if EventParticipationService.stillHere(hunter) and not hunter.busy then
			EventParticipationService.playIdle(hunter.figure)
		end
	end)
end

--------------------------------------------------------------------------------
-- Zentraler Takt (laeuft durchgehend — auch ausserhalb von Events!)
--------------------------------------------------------------------------------

local function tick()
	local participants = EventParticipationService.getParticipants()
	if #participants == 0 then
		return
	end

	-- 1. Pruefen, ob Bärchis unterschiedlicher Spieler im Event-Pit stehen
	local firstOwner = participants[1].player
	local multipleOwners = false
	for i = 2, #participants do
		if participants[i].player ~= firstOwner then
			multipleOwners = true
			break
		end
	end

	if multipleOwners then
		-- Freie Bärchis unterschiedlicher Spieler sofort paarweise ins Tower-Duell schicken
		local paired: { [Presence]: boolean } = {}
		for i = 1, #participants do
			local a = participants[i]
			if paired[a] or a.busy or _inDuel[a] then
				continue
			end

			local bestB: Presence? = nil
			local bestDist = math.huge
			local footA = FigurePlacement.footOf(a.figure)

			for j = i + 1, #participants do
				local b = participants[j]
				if b.player ~= a.player and not paired[b] and not b.busy and not _inDuel[b] then
					local d = flatDist(footA, FigurePlacement.footOf(b.figure))
					if d < bestDist then
						bestDist = d
						bestB = b
					end
				end
			end

			if bestB then
				paired[a]     = true
				paired[bestB] = true
				local fighterA = a
				local fighterB = bestB
				task.spawn(function()
					PitBrawlService.runDuel(fighterA, fighterB)
				end)
			end
		end
		return
	end

	-- 2. Keine fremden Bärchis im Event-Pit: freie Bärchis jagen fremde Spieler im Pit!
	local center = MapService.getEventPitPosition()
	local radius = MapService.getEventPitRadius()

	for _, hunter in participants do
		if not hunter.busy and not _inDuel[hunter] and not _inChase[hunter] then
			local foot = FigurePlacement.footOf(hunter.figure)
			if findTargetPlayer(hunter.player, foot, center, radius) ~= nil then
				startChase(hunter)
			end
		end
	end
end

function PitBrawlService.init()
	EventParticipationService.setDuelRunner(PitBrawlService.runDuel)
end

function PitBrawlService.start()
	if not FeatureFlags.isOn("PIT_BRAWL") then return end
	task.spawn(function()
		while true do
			task.wait(EventConfig.PIT_BRAWL.TICK_SECONDS)
			local ok, err = pcall(tick)
			if not ok then
				warn("[PitBrawlService] Takt fehlgeschlagen:", err)
			end
		end
	end)
	print(
		"[PitBrawlService] Gestartet | Angriffsreichweite:",
		EventConfig.PIT_BRAWL.ATTACK_RANGE,
		"| Jagd-Tempo:",
		EventConfig.PIT_BRAWL.CHASE_SPEED
	)
end

return PitBrawlService
