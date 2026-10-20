-- epilog_island.test.lua — 20.10. Final-Epilog, Prompt 3 (Insel & Bruecke)
-- python tools/luau-tests/run_local.py tools/luau-tests/epilog_island.test.lua
--
-- Prueft die Geometrie (Modules/EpilogIslandLayout, reine Rechnung):
--   1. Teile-Budget: Insel <= 18, Bruecke <= 20 (14 Planken + Gelaender + Licht)
--   2. Abstand: Insel liegt ausser jeder Sprungweite (Luft >= 50, Hoehe >= 15)
--   3. Bruecke: lueckenlose Planken in gleichmaessiger Steigung, begehbar,
--      >= 8 Studs breit, passt an Ansatz (Gipfel) und Inselrand
--   4. Gelaender: hoch genug, ausserhalb der Planken, auf beiden Seiten
--   5. Insel: Fels stapelt sich lueckenlos, Deko auf der Wiese, Podest auf der Insel
--   6. Fangboden: unter allem, deckt Bruecke und Insel ab
--   7. Wegpunkte: lueckenlos, steigen, enden vor dem Terminal
-- fuer mehrere Brueckenrichtungen (jede Plot-Lage ist anders gedreht).

local EpilogConfig = require(RS.Config.EpilogConfig)
local MapConfig    = require(RS.Config.MapConfig)
local Layout       = require(RS.Modules.EpilogIslandLayout)

local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else
		failures += 1
		print("FAIL " .. name .. (if detail ~= nil then ": " .. tostring(detail) else ""))
	end
end

local I, B, S = EpilogConfig.ISLAND, EpilogConfig.BRIDGE, EpilogConfig.SUMMIT
local R = MapConfig.PIT_TOWER_RADIUS
local FLOOR_Y = 72
local CX, CZ = 1000, -500
local MAX_JUMP_REACH = 50   -- grosszuegig: Sprung + Speed-Exploit ueber Luft
local MAX_JUMP_HEIGHT = 15  -- doppelt so hoch wie der hoechste Standardsprung

local function dist3(a, b)
	return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
end
-- Abstand ab Gipfelmitte entlang der Bruecke / quer dazu
local function alongOf(p, a)
	return (p[1] - CX) * math.cos(a) + (p[3] - CZ) * math.sin(a)
end
local function acrossOf(p, a)
	return (p[1] - CX) * -math.sin(a) + (p[3] - CZ) * math.cos(a)
end

local function runFor(angleDeg)
	local label = string.format("[%d°] ", angleDeg)
	local a = math.rad(angleDeg)
	local r = Layout.compute(CX, CZ, FLOOR_Y, a, R)

	-- 1. Budget
	check(label .. "Insel <= 18 Teile", r.islandPieceCount <= B.maxIslandParts, r.islandPieceCount)
	check(label .. "Bruecke <= 20 Teile", r.bridgePieceCount <= B.maxBridgeParts, r.bridgePieceCount)
	check(label .. "14 Planken", #r.planks == 14 and B.planks == 14, #r.planks)
	check(label .. "Gelaender: 4 Stuecke", #r.rails == 4, #r.rails)

	-- 2. Abstand zur Insel
	local nearEdgeAlong = r.stubEnd + I.edgeGap
	local islandCenterAlong = alongOf(r.center, a)
	check(label .. "Inselmitte liegt Rand + Radius hinter dem Ansatz",
		math.abs(islandCenterAlong - (nearEdgeAlong + I.diameter / 2)) < 0.01, islandCenterAlong)
	check(label .. "Luft >= 50 (ausser Sprungweite)", I.edgeGap >= MAX_JUMP_REACH, I.edgeGap)
	check(label .. "Insel >= 15 hoeher als der Gipfel", r.topY - FLOOR_Y >= MAX_JUMP_HEIGHT, r.topY - FLOOR_Y)
	check(label .. "Insel quer genau in der Achse", math.abs(acrossOf(r.center, a)) < 0.01, acrossOf(r.center, a))
	check(label .. "Ansatz endet bei 32", math.abs(r.stubEnd - 32.0) < 0.01, r.stubEnd)

	-- 3. Bruecke
	check(label .. "Breite >= 8", B.width >= 8, B.width)
	local first, last = r.planks[1], r.planks[#r.planks]
	local stubTop = FLOOR_Y + S.bridgeThickness
	check(label .. "erste Planke beginnt am Ansatz (Hoehe)", math.abs(first.topStart[2] - stubTop) < 0.01, first.topStart[2])
	check(label .. "erste Planke beginnt am Ansatz (Abstand)", math.abs(alongOf(first.topStart, a) - r.stubEnd) < 0.01)
	check(label .. "letzte Planke endet am Inselrand (Abstand)", math.abs(alongOf(last.topEnd, a) - nearEdgeAlong) < 0.01)
	check(label .. "letzte Planke endet auf Wiesenhoehe", math.abs(last.topEnd[2] - r.topY) < 0.01, last.topEnd[2])
	local gapsOk, slopeOk, heightOk, thickOk = true, true, true, true
	local worstSlope = 0
	for i, p in r.planks do
		if i > 1 then
			if dist3(r.planks[i - 1].topEnd, p.topStart) > 0.001 then gapsOk = false end
		end
		local run = math.sqrt((p.topEnd[1] - p.topStart[1]) ^ 2 + (p.topEnd[3] - p.topStart[3]) ^ 2)
		local rise = p.topEnd[2] - p.topStart[2]
		local ang = math.deg(math.atan2(rise, run))
		worstSlope = math.max(worstSlope, ang)
		if ang <= 0 or ang > 30 then slopeOk = false end
		if rise > 3 then heightOk = false end
		-- Oberflaeche in der Mitte der Planke: Mitte + Normale * Dicke/2 liegt auf der Strecke
		local n = r.normal
		local lift = if i % 2 == 0 then 0.04 else 0
		local topMid = { p.pos[1] + n[1] * (p.size[2] / 2 - lift), p.pos[2] + n[2] * (p.size[2] / 2 - lift),
			p.pos[3] + n[3] * (p.size[2] / 2 - lift) }
		local mid = { (p.topStart[1] + p.topEnd[1]) / 2, (p.topStart[2] + p.topEnd[2]) / 2, (p.topStart[3] + p.topEnd[3]) / 2 }
		if dist3(topMid, mid) > 0.01 then thickOk = false end
		if p.size[3] < 8 then thickOk = false end
		if p.size[1] < dist3(p.topStart, p.topEnd) then gapsOk = false end   -- Planke deckt ihr Stueck ganz
	end
	check(label .. "Planken lueckenlos und deckend", gapsOk)
	check(label .. "Steigung 0..30 Grad (begehbar), schlimmster " .. string.format("%.1f", worstSlope), slopeOk)
	check(label .. "keine Stufe > 3 Studs pro Planke", heightOk)
	check(label .. "Plankenlage passt zur Oberflaeche, Breite >= 8", thickOk)
	check(label .. "gleichmaessige Steigung", math.abs(math.deg(r.slope.pitch)
		- math.deg(math.atan2(r.slope.rise, r.slope.run))) < 0.001)
	check(label .. "Bruecke ca. 70 lang", math.abs(r.slope.run - 70) < 0.5 and r.slope.length < 75, r.slope.length)

	-- 4. Gelaender
	local railsOk, sidesOk, hiOk = true, true, true
	local left, right = 0, 0
	for _, p in r.rails do
		if not p.collide then railsOk = false end
		if p.size[2] < 8 then hiOk = false end
		local off = math.abs(acrossOf(p.pos, a))
		if off < B.width / 2 + B.railThick / 2 - 0.001 then sidesOk = false end
		if acrossOf(p.pos, a) > 0 then left += 1 else right += 1 end
	end
	check(label .. "Gelaender begehbar-blockierend", railsOk)
	check(label .. "Gelaender >= 8 hoch (nicht uebersprungen)", hiOk)
	check(label .. "Gelaender ausserhalb der Planken", sidesOk)
	check(label .. "Gelaender beidseitig", left == 2 and right == 2, left .. "/" .. right)

	-- 5. Insel
	local byName = {}
	for _, p in r.island do byName[p.name] = p end
	local wiese = byName["Wiese"]
	check(label .. "Wiese begehbar auf Hoehe topY", wiese ~= nil and wiese.collide
		and math.abs(wiese.pos[2] + I.grassThickness / 2 - r.topY) < 0.001)
	check(label .. "Wiese ca. 24 Durchmesser", wiese ~= nil and math.abs(wiese.size[2] - 24) < 0.01)
	local yTop = r.topY - I.grassThickness
	local stackOk = true
	for i = 1, #I.rockLayers do
		local f = byName["Fels_" .. i]
		if not f then stackOk = false break end
		local topF = f.pos[2] + f.size[1] / 2
		if math.abs(topF - yTop) > 0.001 then stackOk = false end
		if f.collide then stackOk = false end
		yTop -= f.size[1]
	end
	check(label .. "Fels stapelt lueckenlos unter der Wiese", stackOk)
	local decoOk, decoCount = true, 0
	for _, p in r.island do
		if p.deco then
			decoCount += 1
			if p.collide then decoOk = false end
			local dx, dz = p.pos[1] - r.center[1], p.pos[3] - r.center[3]
			if math.sqrt(dx * dx + dz * dz) > r.radius then decoOk = false end
		end
	end
	check(label .. "Deko ohne Kollision, auf der Insel", decoOk and decoCount == I.crystalCount + I.bushCount, decoCount)
	local pad = byName["Podest"]
	local tdx, tdz = r.terminal.pos[1] - r.center[1], r.terminal.pos[3] - r.center[3]
	check(label .. "Podest/Terminal liegt ganz auf der Insel",
		pad ~= nil and math.sqrt(tdx * tdx + tdz * tdz) + I.padRadius <= r.radius + 0.001)
	check(label .. "Terminal liegt hinter der Mitte (weg von der Bruecke)", alongOf(r.terminal.pos, a) > islandCenterAlong)
	check(label .. "Terminal schaut zur Bruecke", alongOf(r.terminal.look, a) < alongOf(r.terminal.pos, a))
	check(label .. "Terminal steht auf dem Podest (Hoehe)", math.abs(r.terminal.pos[2] - (r.topY + I.padThickness)) < 0.001)

	-- 6. Fangboden
	local catch = byName["Fangboden"]
	local lowest = math.huge
	for _, p in r.island do
		if not p.hidden then
			local h = if p.kind == "Disc" then p.size[1] elseif p.kind == "Ball" then p.size[1] else p.size[2]
			lowest = math.min(lowest, p.pos[2] - h / 2)
		end
	end
	check(label .. "Fangboden unter allen Teilen der Insel", catch ~= nil and catch.pos[2] < lowest - 1, lowest)
	check(label .. "Fangboden unsichtbar, fest", catch ~= nil and catch.hidden and catch.collide)
	check(label .. "Fangboden unter dem Ansatz-Ende (unter dem Gipfel-Rand)", catch ~= nil
		and catch.pos[2] < FLOOR_Y - 1 and alongOf(catch.pos, a) - catch.size[1] / 2 < r.stubEnd)
	check(label .. "Fangboden reicht hinter die Insel", catch ~= nil
		and alongOf(catch.pos, a) + catch.size[1] / 2 > nearEdgeAlong + I.diameter)
	check(label .. "Fangboden breiter als die Bruecke", catch ~= nil and catch.size[3] > B.width + 10)

	-- 7. Wegpunkte
	local wp = r.waypoints
	check(label .. "18 Wegpunkte", #wp == 18, #wp)
	local stepsOk, climbs = true, true
	for i = 2, #wp do
		if dist3(wp[i - 1], wp[i]) > 12 then stepsOk = false end
		if alongOf(wp[i], a) <= alongOf(wp[i - 1], a) then climbs = false end
	end
	check(label .. "Wegpunkte ohne Spruenge (<= 12)", stepsOk)
	check(label .. "Wegpunkte laufen strikt nach aussen", climbs)
	check(label .. "letzter Wegpunkt auf der Wiese", math.abs(wp[#wp][2] - r.topY) < 0.001)
	local ldx, ldz = wp[#wp][1] - r.center[1], wp[#wp][3] - r.center[3]
	check(label .. "letzter Wegpunkt liegt auf der Insel", math.sqrt(ldx * ldx + ldz * ldz) < r.radius)

	-- Lichtstreifen
	check(label .. "Lichtimpuls beginnt am Ansatz und endet am Inselrand",
		math.abs(alongOf(r.pulseFrom, a) - r.stubEnd) < 0.01 and math.abs(alongOf(r.pulseTo, a) - nearEdgeAlong) < 0.01)
end

for _, deg in { 0, 37, 90, 180, 251, 300 } do
	runFor(deg)
end

-- Konfig: Mobile-Breite, Emitter-Grenze, Bruecken-Zeit
check("Config: Bruecke >= 8 breit", B.width >= 8)
check("Config: hoechstens 3 Emitter", B.maxEmitters == 3)
check("Config: Funken-Lebensdauer erlaubt <= 3 gleichzeitige Emitter",
	math.ceil(B.sparkLife / B.growInterval) <= B.maxEmitters, B.sparkLife / B.growInterval)
-- 14 Planken x 0,3 s = 4,2 s Wachstum + Feder 0,28 s = ca. 4,5 s; mit dem Lichtimpuls (1,2 s) ca. 5,7 s ("ca. 5 s")
check("Config: Bruecke waechst in ca. 5 s", math.abs(B.planks * B.growInterval + B.springSeconds - 5) < 1, B.planks * B.growInterval)
check("Config: Enthuellung 3 s, Abbau 3 s", I.revealSeconds == 3 and B.removeSeconds == 3)
check("Config: Wippen +-0,6 in 4 s", I.bobHeight == 0.6 and I.bobPeriod == 4)

print(failures == 0 and "ALLE OK" or ("FEHLER: " .. failures))
if failures > 0 then error("epilog_island: " .. failures .. " Fehler") end
