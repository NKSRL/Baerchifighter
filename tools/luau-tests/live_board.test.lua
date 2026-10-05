-- live_board.test.lua — HBB Paket 6: Inhalt des Live-Kampf-Boards
-- python tools/luau-tests/run_local.py tools/luau-tests/live_board.test.lua

local LiveBoardText = rbxRequire("ReplicatedStorage/Modules/LiveBoardText")

local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else
		failures += 1
		print("FAIL " .. name .. (if detail then ": " .. tostring(detail) else ""))
	end
end

local title, lines, live = LiveBoardText.build({}, 8)
check("leer: kein Live", not live and #lines == 0 and title == "⚔ LIVE", title)

title, lines, live = LiveBoardText.build({
	{ name = "Anna", towerId = "I",   stage = 12, phase = "InPit" },
	{ name = "Ben",  towerId = "III", stage = 4,  phase = "InPit" },
	{ name = "Cem",  towerId = "II",  stage = nil, phase = "ToPit" },
	{ name = "Dora", towerId = "III", stage = 9,  phase = "InPit" },
	{ name = "Emil", towerId = "II",  stage = 30, phase = "Returning" },
}, 8)
check("Titel zaehlt nur Laufende", title == "⚔ LIVE · 4", title)
check("Live", live)
check("Rueckweg nicht gezeigt", #lines == 4, #lines)
check("hoechster Tower, hoechste Stage oben", lines[1] == "⚔  Dora   III · 9", lines[1])
check("dann gleicher Tower, kleinere Stage", lines[2] == "⚔  Ben   III · 4", lines[2])
check("Kaempfer vor Hinlaeufern", lines[3] == "⚔  Anna   I · 12", lines[3])
check("Hinlaeufer zuletzt", lines[4] == "➡  Cem   II", lines[4])

local many = {}
for i = 1, 12 do table.insert(many, { name = "P" .. i, towerId = "I", stage = i, phase = "InPit" }) end
title, lines = LiveBoardText.build(many, 8)
check("hoechstens maxLines Zeilen", #lines == 8, #lines)
check("Titel zeigt alle", title == "⚔ LIVE · 12", title)

if failures > 0 then error(failures .. " Fehler", 0) end
print("live_board: alle Tests gruen")
