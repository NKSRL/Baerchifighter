--!strict
-- LiveBoardText.luau
-- ReplicatedStorage/Modules/LiveBoardText.luau
--
-- Einzige Zustaendigkeit:
--   - Aus den laufenden Tower-Laeufen den Inhalt des Live-Kampf-Boards machen
--     (HBB Paket 6). Rein, ohne Roblox-Dienste: tools/luau-tests/live_board.test.lua.
--
-- Sprachneutral (HBB Paket 1: Icons und Zahlen statt Text): die Tafel steht
-- in der Welt und wird von Spielern aller Sprachen gelesen.
--   Titel:  "⚔ LIVE · 3"            (ohne Kampf: "⚔ LIVE")
--   Zeile:  "⚔  Name   III · 14"   kaempft gerade in Tower III, Stage 14
--           "➡  Name   III"        laeuft zur Arena
-- Laeufe auf dem Rueckweg sind fertig und stehen nicht mehr da.
-- Reihenfolge: wer kaempft vor wer hinlaeuft, dann hoeherer Tower, dann
-- hoehere Stage — oben steht der spannendste Kampf.

local TowerConfig = require(script.Parent.Parent.Config.TowerConfig)

local LiveBoardText = {}

export type LiveRun = {
	name    : string,
	towerId : string?,
	stage   : number?,
	phase   : string,    -- "ToPit" | "InPit" | "Returning" (PitArenaService)
}

local function numeral(towerId: string?): string
	local def = TowerConfig.get(towerId or "") or TowerConfig.TOWERS[1]
	return def.numeral
end

local function towerIndex(towerId: string?): number
	local def = TowerConfig.get(towerId or "")
	return if def then def.index else 0
end

-- Gibt Titel, Zeilen (hoechstens maxLines) und "laeuft etwas?" zurueck.
function LiveBoardText.build(runs: { LiveRun }, maxLines: number): (string, { string }, boolean)
	local shown: { LiveRun } = {}
	for _, run in runs do
		if run.phase == "InPit" or run.phase == "ToPit" then
			table.insert(shown, run)
		end
	end

	table.sort(shown, function(a, b)
		if a.phase ~= b.phase then return a.phase == "InPit" end
		local ta, tb = towerIndex(a.towerId), towerIndex(b.towerId)
		if ta ~= tb then return ta > tb end
		if (a.stage or 0) ~= (b.stage or 0) then return (a.stage or 0) > (b.stage or 0) end
		return a.name < b.name
	end)

	local lines: { string } = {}
	for i = 1, math.min(#shown, maxLines) do
		local run = shown[i]
		if run.phase == "InPit" and run.stage then
			table.insert(lines, string.format("⚔  %s   %s · %d", run.name, numeral(run.towerId), run.stage))
		else
			table.insert(lines, string.format("➡  %s   %s", run.name, numeral(run.towerId)))
		end
	end

	local title = if #shown > 0 then string.format("⚔ LIVE · %d", #shown) else "⚔ LIVE"
	return title, lines, #shown > 0
end

return LiveBoardText
