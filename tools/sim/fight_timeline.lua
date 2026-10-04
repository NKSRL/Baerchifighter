-- fight_timeline.lua — misst, wie lange die v15-Wiedergabe eines PIT-Laufs
-- dauert (ohne Hin-/Rueckweg) und prueft die Regeln von FightTimeline.
-- Aufruf: cd tools/luau-tests && node run.mjs ../sim/fight_timeline.lua
local BaerchiConfig    = require(RS.Config.BaerchiConfig)
local CombatConfig     = require(RS.Config.CombatConfig)
local SkillFXConfig    = require(RS.Config.SkillFXConfig)
local MapConfig        = require(RS.Config.MapConfig)
local CombatCalculator = require(RS.Modules.CombatCalculator)
local BaerchiFactory   = require(RS.Modules.BaerchiFactory)
local FightTimeline    = require(RS.Modules.FightTimeline)

math.randomseed(77)
local failures = 0
local function check(ok, msg)
	if not ok then failures += 1; print("FEHLER: " .. msg) end
end

local function runOnce(b)
	local def = BaerchiConfig.getById(b.configId)
	local stats = CombatCalculator.getEffectiveStats(b, def.baseStats)
	local hp, charge = stats.maxHp, 0
	local stages = {}
	for stage = 1, CombatConfig.MAX_STAGES_PER_RUN do
		local es = CombatConfig.getEnemyStats(1, stage)
		local me = { uid = "me", stats = stats, hp = hp, charge = charge }
		local en = { uid = "en", stats = es, hp = es.maxHp, charge = 0 }
		local r = CombatCalculator.simulate(me, en, true)
		hp = math.clamp(me.hp, 0, stats.maxHp)
		charge = me.charge
		local beats = {}
		for _, e in r.log do
			table.insert(beats, { actor = e.actor, kind = e.kind, charge = e.chargeA, skillId = e.skillId, selfHp = 0, enemyHp = 0 })
		end
		local won = r.winnerUid == "me"
		table.insert(stages, { beats = beats, won = won })
		if not won or hp <= 0 then break end
	end

	local total, shown, all, skills, fullDone = 0, 0, 0, 0, false
	for _, st in stages do
		local plan = FightTimeline.plan(st.beats, #stages, st.won)
		local n = #st.beats
		check(#plan.indices > 0 or n == 0, "Stage ohne gezeigten Zug")
		if n > 0 then check(plan.indices[#plan.indices] == n, "letzter Zug fehlt") end
		check(plan.tempo >= MapConfig.FIGHT_MIN_TEMPO - 1e-9 and plan.tempo <= 1, "Tempo ausserhalb")
		total += MapConfig.FIGHT_ENEMY_INTRO_SECONDS * plan.tempo
		if st.won then total += MapConfig.FIGHT_KO_SECONDS * plan.tempo end
		for _, i in plan.indices do
			local beat = st.beats[i]
			total += FightTimeline.beatSeconds(beat) * plan.tempo
			if FightTimeline.isSkillBeat(beat) and beat.actor == "A" then
				skills += 1
				local id = beat.skillId or b.skillId
				local full = not fullDone
				fullDone = true
				total += SkillFXConfig.getDuration(id, full) * (if full then 1 else plan.tempo)
			end
		end
		shown += #plan.indices
		all += n
	end
	return #stages, total, shown, all, skills
end

local ids = {}
for id in BaerchiConfig.data do table.insert(ids, id) end
table.sort(ids)
print(string.format("%-22s %6s %8s %10s %7s", "Baerchi", "Stages", "Sekunden", "Zuege", "Skills"))
local worst = 0
for _, id in ids do
	for _, level in { 1, 30 } do
		local b = BaerchiFactory.create(id, { level = level })
		local stages, secs, shown, all, skills = runOnce(b)
		worst = math.max(worst, secs)
		if level == 30 then
			print(string.format("%-22s %6d %8.1f %4d/%-5d %7d", id, stages, secs, shown, all, skills))
		end
	end
end
print(string.format("laengste Wiedergabe: %.1f s", worst))
check(worst < 75, "Wiedergabe zu lang")
print(if failures == 0 then "fight_timeline: OK" else ("fight_timeline: " .. failures .. " Fehler"))
