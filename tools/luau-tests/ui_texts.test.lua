-- ui_texts.test.lua — Spieler-Texte in allen vier Sprachen vollstaendig
-- python tools/luau-tests/run_local.py tools/luau-tests/ui_texts.test.lua
--
-- Prueft das, was check_loc.py/check_ui.py statisch nicht sehen koennen: die
-- zur LAUFZEIT zusammengesetzten Texte. Fuer de/en/fr/es:
--   1. Names: jeder Baerchi, jedes Ei, jeder Skill, jedes Event, jede
--      Mutation und jeder Charm-Wert hat Namen (und Beschreibung) — kein
--      Rueckfall auf die deutsche Config, kein "[schluessel]".
--   2. EventConfig.describeReward/describeBonus (LocMsg) loesen sich auf.
--   3. CharmConfig.describe und BuildingBehavior.describeEffect.
--   4. Verschachtelte Server-Nachrichten (Event-Belohnung, Tafeln) — so wie
--      EventParticipationService/PitArenaService sie bauen.
-- "Vollstaendig" heisst: kein "[" + Schluessel + "]" und kein "{platzhalter}".

local Loc              = rbxRequire("ReplicatedStorage/Localization/Loc")
local Names            = rbxRequire("ReplicatedStorage/Localization/Names")
local BaerchiConfig    = rbxRequire("ReplicatedStorage/Config/BaerchiConfig")
local EggConfig        = rbxRequire("ReplicatedStorage/Config/EggConfig")
local SkillConfig      = rbxRequire("ReplicatedStorage/Config/SkillConfig")
local EventConfig      = rbxRequire("ReplicatedStorage/Config/EventConfig")
local CharmConfig      = rbxRequire("ReplicatedStorage/Config/CharmConfig")
local BuildingBehavior = rbxRequire("ReplicatedStorage/Config/BuildingBehavior")

local failures = 0
local function check(name, ok, detail)
	if ok then return end
	failures += 1
	print("FAIL " .. name .. (if detail then ": " .. tostring(detail) else ""))
end

local function complete(text: any): boolean
	return type(text) == "string" and text ~= ""
		and string.find(text, "%[[%w_]+%.[%w_.]+%]") == nil
		and string.find(text, "{[%w_]+}") == nil
end

-- In en/fr/es darf nicht der deutsche Text stehen (vergessene Uebersetzung),
-- ausser er ist bewusst gleich und kurz (Eigennamen wie "Omega", "UFO").
-- Verglichen wird mit dem, was der deutsche Durchlauf angezeigt hat.
local _german: { [string]: string } = {}
local function notGermanFallback(lang: string, shown: string, id: string): boolean
	if lang == "de" then
		_german[id] = shown
		return true
	end
	local german = _german[id]
	return german == nil or shown ~= german or #german <= 6
end

local checked = 0
for _, lang in { "de", "en", "fr", "es" } do
	Loc.setLanguage(lang)

	-- 1. Namen und Beschreibungen
	for id in BaerchiConfig.data do
		local name, desc = Names.baerchi(id), Names.baerchiDesc(id)
		check(lang .. " baerchi " .. id, complete(name), name)
		check(lang .. " baerchi desc " .. id, complete(desc), desc)
		check(lang .. " baerchi desc uebersetzt " .. id, notGermanFallback(lang, desc, "b." .. id), desc)
		checked += 2
	end
	for id in EggConfig.data do
		for _, text in { Names.egg(id), Names.eggDesc(id), Names.eggShort(id) } do
			check(lang .. " egg " .. id, complete(text), text)
			checked += 1
		end
		check(lang .. " egg desc uebersetzt " .. id, notGermanFallback(lang, Names.eggDesc(id), "e." .. id))
	end
	for id in SkillConfig.data do
		for _, text in { Names.skill(id), Names.skillDesc(id), Names.skillDrawback(id) } do
			check(lang .. " skill " .. id, complete(text), text)
			checked += 1
		end
		check(lang .. " skill desc uebersetzt " .. id, notGermanFallback(lang, Names.skillDesc(id), "s." .. id))
	end
	for _, def in EventConfig.EVENTS do
		check(lang .. " event " .. def.id, complete(Names.event(def.id)), Names.event(def.id))
		-- 2. Belohnungszeile der Tafel
		local reward = Loc.resolve(EventConfig.describeReward(def))
		check(lang .. " reward " .. def.id, complete(reward), reward)
		checked += 2
	end
	for _, mutation in BaerchiConfig.MUTATION_ORDER do
		check(lang .. " mutation " .. tostring(mutation), complete(Names.mutation(mutation)))
	end
	for _, bonus in {
		{ kind = "honey", amount = 3 }, { kind = "eggs", amount = 2, eggPick = "jump" },
		{ kind = "eggs", amount = 1, eggPick = "highest" }, { kind = "eggs", amount = 1, eggType = "GoldenEgg" },
		{ kind = "gummies", amount = 50 }, { kind = "goldGummies", amount = 5 }, { kind = "mutation", chance = 0.2 },
	} do
		local text = Loc.resolve(EventConfig.describeBonus(bonus :: any))
		check(lang .. " bonus " .. bonus.kind, complete(text), text)
		checked += 1
	end

	-- 3. Charms und Gebaeude
	for _, stat in CharmConfig.STAT_POOL do
		local text = CharmConfig.describe({ slot = 1, rarity = "Rare", statId = stat.id, value = 0.034, locked = false } :: any)
		check(lang .. " charm " .. stat.id, complete(text) and not string.find(text, stat.displayName, 1, true) or lang == "de" or #stat.displayName <= 9, text)
		checked += 1
	end
	for _, id in { "Beehive", "HoneyRefiner", "HoneyPond" } do
		for _, level in { 1, 10, 60 } do
			local text = BuildingBehavior.describeEffect(id, level)
			check(lang .. " building " .. id .. " L" .. level, complete(text), text)
			checked += 1
		end
	end

	-- 4. Verschachtelte Server-Nachrichten
	local eggs = Loc.msg("fmt.append", {
		a = Loc.msg("ev.bonus.eggs_jump", { n = 1, egg = Names.msg.egg("CometEgg") }),
		b = Loc.msg("ev.bonus.blueprint"),
	})
	local line = Loc.msg("fmt.join", { a = eggs, b = Loc.msg("ev.bonus.mutation", { mutation = Names.msg.mutation("Gold") }) })
	local ufo = Loc.msg("ev.ufo.reward_line", { text = Loc.msg("fmt.join", {
		a = "+1 HP/ATK", b = Loc.msg("msg.event.rarity_up", { from = Loc.msg("rarity.Rare"), to = Loc.msg("rarity.Epic") }),
	}) })
	local boards = {
		Loc.msg("ui.eventboard.live", { event = Names.msg.event("WaspQueen") }),
		Loc.msg("ui.pitboard.stage", { tower = Loc.msg("ui.petbar.tower", { n = "III" }), stage = 42 }),
		Loc.msg("ui.world.figure_name", { badge = "", name = Names.msg.baerchi("OmegaBaerchi"), level = 50 }),
		Loc.msg("ui.world.sign_level", { name = Names.msg.building("HoneyPond"), level = 12 }),
		Loc.msg("ui.merchant.buy", { egg = Names.msg.egg("BasicEgg"), n = 120 }),
		Loc.msg("fmt.append", { a = "♛", b = Loc.msg("ui.world.owner_badge", { tower = "Tower I", record = 7 }) }),
	}
	for index, msg in { line, ufo, table.unpack(boards) } do
		local text = Loc.resolve(msg)
		check(lang .. " server-nachricht " .. index, complete(text), text)
		checked += 1
	end
end

print(string.format("ui_texts: %d Texte in 4 Sprachen geprueft, %d Fehler", checked, failures))
if failures > 0 then
	__log("FAIL", "ui_texts")
	error("ui_texts: " .. failures .. " Fehler", 0)
end
