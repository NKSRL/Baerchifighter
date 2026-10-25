-- power_old_matrix.lua — Welt 1 P5b: Ist-Matrix der Basis-Staerke je Rarity (altes Modell)
-- python tools/luau-tests/run_local.py tools/sim/power_old_matrix.lua
local BaerchiConfig = require(RS.Config.BaerchiConfig)
local SkillConfig   = require(RS.Config.SkillConfig)
__log("Rarity     | n | g-Median | g-min..max | hp/atk Spanne | Skills")
local prev
for _, r in BaerchiConfig.RARITY_ORDER do
	local list = BaerchiConfig.getByRarity(r)
	local gs, skills = {}, {}
	for _, d in list do
		table.insert(gs, math.sqrt(d.baseStats.hp * d.baseStats.atk))
		table.insert(skills, d.defaultSkill)
	end
	table.sort(gs)
	local med = gs[math.ceil(#gs / 2)] or 0
	__log(string.format("%-10s | %d | %8.1f | %6.1f..%-6.1f | x%.2f zum Vorgaenger | %s", r, #list, med, gs[1] or 0, gs[#gs] or 0, prev and med / prev or 1, table.concat(skills, ",")))
	if med > 0 then prev = med end
end
