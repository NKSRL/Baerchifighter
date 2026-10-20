-- epilog_terminal.test.lua — 20.10. Final-Epilog, Prompt 4 (Start-Terminal)
-- python tools/luau-tests/run_local.py tools/luau-tests/epilog_terminal.test.lua
--
-- Prueft die Terminal-Geometrie (Modules/EpilogTerminalLayout, reine Rechnung):
--   1. Teile-Budget <= 22, Namensschema Epilog_Terminal_*, eindeutige Namen
--   2. Masse: 5 Studs breit, Knopf Ø 2,2, drei Lampen, Konsole geneigt
--   3. Kollision: Sockel/Korpus/Konsole fest; Klappe und Knopf nicht
--   4. Palette: nur Farben aus TERMINAL.colors (Grau, Rot, Warngelb nur als Streifen, Gold)
--   5. Boden: Unterkante des Sockels bei 0, nichts darunter
--   6. Scharnier der Klappe liegt am hinteren Rand, Klappe schliesst ueber dem Knopf
--   7. Ausloeser: unsichtbar, Touch-Flaeche >= 64; Config: Prompt 8 / 1,2 s; <= 2 Emitter
--   8. Zustaende: genau idle/ready/armed/fired/done

local EpilogConfig = require(RS.Config.EpilogConfig)
local Layout       = require(RS.Modules.EpilogTerminalLayout)

local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else
		failures += 1
		print("FAIL " .. name .. (if detail ~= nil then ": " .. tostring(detail) else ""))
	end
end

local T = EpilogConfig.TERMINAL
local r = Layout.compute()
local byName = {}
for _, p in r.pieces do byName[p.name] = p end

local function halfY(p)
	-- vertikale Halbausdehnung eines (ggf. geneigten) Teils
	local rx = p.rot[1]
	if p.kind == "Ball" then return p.size[1] / 2 end
	if p.kind == "Disc" then
		return (math.abs(math.cos(rx)) * p.size[1] / 2) + math.abs(math.sin(rx)) * p.size[2] / 2
	end
	return math.abs(math.cos(rx)) * p.size[2] / 2 + math.abs(math.sin(rx)) * p.size[3] / 2
end

-- 1. Budget und Namen
check("Teile <= 22", r.count <= T.maxParts, r.count)
check("Teile = 21", r.count == 21, r.count)
local seen, namesOk, prefixOk = {}, true, true
for _, p in r.pieces do
	if seen[p.name] then namesOk = false end
	seen[p.name] = true
	if string.sub(p.name, 1, 16) ~= "Epilog_Terminal_" then prefixOk = false end
end
check("Namen eindeutig", namesOk)
check("Namensschema Epilog_Terminal_*", prefixOk)

-- 2. Masse
check("5 Studs breit (Korpus)", byName["Epilog_Terminal_Korpus"].size[1] == 5, byName["Epilog_Terminal_Korpus"].size[1])
check("Knopf Ø 2,2", math.abs(byName["Epilog_Terminal_Knopf"].size[2] - 2.2) < 1e-9)
check("drei Lampen", #r.lampNames == 3 and byName[r.lampNames[1]] ~= nil and byName[r.lampNames[3]] ~= nil)
check("Konsole leicht schraeg", math.abs(math.deg(byName["Epilog_Terminal_Konsole"].rot[1]) + T.tiltDeg) < 1e-6
	and T.tiltDeg > 5 and T.tiltDeg < 30)
check("Vorderkante der Konsole liegt tiefer als die Hinterkante",
	byName["Epilog_Terminal_Leiste"].pos[2] < byName["Epilog_Terminal_Bildschirm"].pos[2])
check("Bildschirm liegt hinter dem Knopf (+Z), Knopf vorn",
	byName["Epilog_Terminal_Bildschirm"].pos[3] > byName["Epilog_Terminal_Knopf"].pos[3])
check("Antenne hinter dem Knopf, Kabel verbindet", byName["Epilog_Terminal_Antenne"].pos[3] > 0
	and byName["Epilog_Terminal_Kabel"].pos[3] > 0)
check("Knopf passt auf das Gehaeuse", T.buttonDiam < T.baseDiam and T.baseDiam < T.ringDiam)
check("Gehaeuse liegt auf der Konsole (Breite)", T.ringDiam < T.width)

-- 3. Kollision
check("Sockel kollidiert", byName["Epilog_Terminal_Sockel"].collide)
check("Korpus kollidiert", byName["Epilog_Terminal_Korpus"].collide)
check("Konsole kollidiert", byName["Epilog_Terminal_Konsole"].collide)
check("Klappe kollidiert nicht", not byName["Epilog_Terminal_Klappe"].collide)
check("Knopf kollidiert nicht", not byName["Epilog_Terminal_Knopf"].collide)
check("Ausloeser kollidiert nicht", not byName["Epilog_Terminal_Ausloeser"].collide)
local collideCount = 0
for _, p in r.pieces do if p.collide then collideCount += 1 end end
check("nur die drei Bloecke kollidieren", collideCount == 3, collideCount)

-- 4. Palette
local paletteOk, yellowOk = true, true
for _, p in r.pieces do
	if T.colors[p.colorKey] == nil then paletteOk = false end
	if p.colorKey == "yellow" and not string.find(p.name, "Warn_") then yellowOk = false end
end
check("nur Farben aus der Palette", paletteOk)
check("Warngelb nur als Streifen", yellowOk)
check("Klappe rot und durchsichtig", byName["Epilog_Terminal_Klappe"].colorKey == "lid"
	and byName["Epilog_Terminal_Klappe"].transparency > 0.2)
check("Knopf signalrot", byName["Epilog_Terminal_Knopf"].colorKey == "red")
check("Gold nur an Kanten/Ring", byName["Epilog_Terminal_Leiste"].colorKey == "gold" and byName["Epilog_Terminal_Ring"].colorKey == "gold")

-- 5. Boden
local lowest = math.huge
for _, p in r.pieces do
	if p.name ~= "Epilog_Terminal_Ausloeser" then
		lowest = math.min(lowest, p.pos[2] - halfY(p))
	end
end
check("Unterkante des Sockels bei 0", math.abs(byName["Epilog_Terminal_Sockel"].pos[2] - byName["Epilog_Terminal_Sockel"].size[2] / 2) < 1e-9)
check("nichts unter dem Boden", lowest > -1e-6, lowest)
check("Pivot Mitte Sockelunterseite (Sockel mittig)", math.abs(byName["Epilog_Terminal_Sockel"].pos[1]) < 1e-9)
check("Vorderseite -Z: Warnstreifen vor dem Sockel", byName["Epilog_Terminal_Warn_Gelb"].pos[3] < byName["Epilog_Terminal_Sockel"].pos[3]
	- byName["Epilog_Terminal_Sockel"].size[3] / 2 + 0.2)

-- 6. Scharnier / Klappe
local lid = byName["Epilog_Terminal_Klappe"]
local knob = byName["Epilog_Terminal_Knopf"]
check("Scharnier hinter der Klappe", r.hinge.pos[3] > lid.pos[3])
check("Scharnier-Neigung = Konsole", math.abs(r.hinge.rx - byName["Epilog_Terminal_Konsole"].rot[1]) < 1e-9)
check("Klappe ueber dem Knopf (Hoehe)", lid.pos[2] > knob.pos[2] + halfY(knob))
check("Klappe deckt den Knopf (Breite)", lid.size[1] > T.buttonDiam and lid.size[3] > T.buttonDiam)
check("Knopf-Oberseite liegt unter der Klappe", r.buttonTop[2] < lid.pos[2])

-- 7. Ausloeser und Prompt
local trigger = byName["Epilog_Terminal_Ausloeser"]
check("Ausloeser unsichtbar", trigger.hidden and trigger.transparency == 1)
check("Touch-Flaeche >= 64", trigger.size[1] * trigger.size[3] >= 64, trigger.size[1] * trigger.size[3])
check("Prompt: Distanz 8, Halten 1,2 s", T.prompt.distance == 8 and T.prompt.hold == 1.2)
check("hoechstens 2 Emitter", T.maxEmitters <= 2)
check("Annaeherung 12 Studs, Hysterese groesser", T.nearDistance == 12 and T.farDistance > T.nearDistance)
check("Ladering: Halten 1,2 s > 0", T.prompt.hold > 0)
check("Knopf senkt sich 0,25", T.pressDepth == 0.25)

-- 8. Zustaende
local states = {}
for _, v in T.STATE do states[v] = true end
check("fuenf Zustaende", states.idle and states.ready and states.armed and states.fired and states.done)
local n = 0
for _ in T.STATE do n += 1 end
check("genau fuenf", n == 5, n)
check("Attribut EpilogTerminalState", T.ATTRIBUTE == "EpilogTerminalState")

print(failures == 0 and "ALLE OK" or ("FEHLER: " .. failures))
if failures > 0 then error("epilog_terminal: " .. failures .. " Fehler") end
