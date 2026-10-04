--!strict
-- FightTimeline.luau
-- ReplicatedStorage/Modules/FightTimeline.luau
--
-- Einzige Zustaendigkeit:
--   - Fuer EINE Stage eines PIT-Laufs ausrechnen, WELCHE Zuege in der Arena
--     gezeigt werden und in welchem TEMPO.
--
-- Reine Rechnung: kein Model, keine Instanz, kein Warten. Das Abspielen macht
-- PitArenaService, wie ein Stoss aussieht entscheidet FigureFX. Genau diese
-- Trennung erlaubt es, die Auswahl offline zu testen (tools/luau-tests).
--
-- ============================================================
-- DAS PROBLEM
-- ============================================================
-- Ein Lauf hat bis zu 60 Stages, eine Stage bis zu ein paar Dutzend Zuege.
-- Alles zu zeigen dauerte Minuten. Deshalb gibt es ein Zeitbudget pro Stage
-- (MapConfig.FIGHT_RUN_TARGET_SECONDS / Zahl der Stages, geklemmt) und eine
-- Rangfolge, was hineinkommt:
--   1. der LETZTE Zug (er entscheidet die Stage) und der ERSTE Faehigkeiten-
--      Zug — Pflicht, die werden nie ausgelassen;
--   2. weitere Faehigkeiten-Zuege;
--   3. normale Stoesse, gleichmaessig ueber die Stage verteilt.
-- Passen schon die Pflicht-Zuege nicht ins Budget, wird das Tempo erhoeht
-- (bis MapConfig.FIGHT_MIN_TEMPO) statt Pflicht-Zuege wegzulassen.
--
-- Ausgelassene Zuege sind nicht verloren: jeder gezeigte Zug traegt den
-- HP- und Ladestand NACH sich (Types.FightBeat), die Leisten springen also
-- einfach ein Stueck weiter. Die Wahrheit steht ohnehin im Server-Ergebnis.
--
-- Die Dauer der Faehigkeiten-SHOWS (SkillFX) gehoert NICHT in dieses Budget:
-- die volle Show laeuft genau einmal pro Lauf und soll ihre Zeit bekommen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig = require(ReplicatedStorage.Config.MapConfig)
local Types     = require(ReplicatedStorage.Network.Types)

local FightTimeline = {}

export type StagePlan = {
	tempo   : number,       -- Faktor auf alle Dauern (1 = normal, kleiner = schneller)
	indices : { number },   -- gezeigte Zuege (Index in der Beat-Liste), aufsteigend
}

-- Ist dieser Zug ein Faehigkeiten-Moment (bekommt Show und wuchtigen Stoss)?
function FightTimeline.isSkillBeat(beat: Types.FightBeat): boolean
	return beat.kind == "skill" or beat.kind == "burst"
end

-- Grunddauer eines Zugs bei Tempo 1.
function FightTimeline.beatSeconds(beat: Types.FightBeat): number
	if FightTimeline.isSkillBeat(beat) then
		return MapConfig.FIGHT_SKILL_BEAT_SECONDS
	end
	return MapConfig.FIGHT_BEAT_SECONDS
end

-- Zeitbudget einer Stage (ohne Faehigkeiten-Shows).
function FightTimeline.stageSeconds(stageCount: number): number
	return math.clamp(
		MapConfig.FIGHT_RUN_TARGET_SECONDS / math.max(1, stageCount),
		MapConfig.FIGHT_STAGE_MIN_SECONDS,
		MapConfig.FIGHT_STAGE_MAX_SECONDS
	)
end

-- Plant eine Stage. `won` = die Stage endet mit einem besiegten Gegner (dann
-- kostet sein Umkippen FIGHT_KO_SECONDS mit).
function FightTimeline.plan(beats: { Types.FightBeat }, stageCount: number, won: boolean): StagePlan
	local count = #beats
	if count == 0 then
		return { tempo = 1, indices = {} }
	end

	local budget = FightTimeline.stageSeconds(stageCount)
	local chosen: { [number]: boolean } = {}

	-- 1. Pflicht: letzter Zug und erster Faehigkeiten-Zug.
	chosen[count] = true
	local firstSkill: number? = nil
	for i, beat in beats do
		if FightTimeline.isSkillBeat(beat) then
			firstSkill = i
			break
		end
	end
	if firstSkill then
		chosen[firstSkill] = true
	end

	local fixed = MapConfig.FIGHT_ENEMY_INTRO_SECONDS + (if won then MapConfig.FIGHT_KO_SECONDS else 0)
	local mustCost = fixed
	for i in chosen do
		mustCost += FightTimeline.beatSeconds(beats[i])
	end

	-- Tempo: nur schneller, nie langsamer als normal.
	local tempo = math.clamp(budget / mustCost, MapConfig.FIGHT_MIN_TEMPO, 1)
	local remaining = budget - mustCost * tempo

	-- 2. Weitere Faehigkeiten-Zuege, der Reihe nach, solange Zeit bleibt.
	for i, beat in beats do
		if not chosen[i] and FightTimeline.isSkillBeat(beat) then
			local cost = FightTimeline.beatSeconds(beat) * tempo
			if cost <= remaining then
				chosen[i] = true
				remaining -= cost
			end
		end
	end

	-- 3. Normale Stoesse, gleichmaessig verteilt.
	local rest: { number } = {}
	for i = 1, count do
		if not chosen[i] then
			table.insert(rest, i)
		end
	end

	local hitCost = MapConfig.FIGHT_BEAT_SECONDS * tempo
	local fit = math.min(#rest, math.floor(remaining / hitCost + 1e-6))
	if fit > 0 then
		for k = 1, fit do
			-- Mitte des k-ten von `fit` gleich grossen Abschnitten.
			local pos = math.clamp(math.floor((k - 0.5) * #rest / fit) + 1, 1, #rest)
			chosen[rest[pos]] = true
		end
	end

	local indices: { number } = {}
	for i = 1, count do
		if chosen[i] then
			table.insert(indices, i)
		end
	end

	return { tempo = tempo, indices = indices }
end

return FightTimeline
