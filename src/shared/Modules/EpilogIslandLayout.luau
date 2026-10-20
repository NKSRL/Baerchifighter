--!strict
-- EpilogIslandLayout.luau
-- ReplicatedStorage/Modules/EpilogIslandLayout.luau
--
-- Einzige Zustaendigkeit:
--   - Die Geometrie der schwebenden Insel und der Bruecke (Prompt 3, Final-Epilog)
--     als reine Rechnung: welche Teile wo stehen, wohin der Avatar laeuft,
--     wo das Terminal steht. Keine Roblox-Instanzen, nur Zahlen — damit
--     tools/luau-tests/epilog_island.test.lua Teilezahl, Steigung, Luecken
--     und Abstand pruefen kann. EpilogIslandBuilder baut daraus die Teile.
--
-- Koordinaten: Welt (x, y, z). `floorY` = Oberkante der obersten Etage des Gipfels,
-- `bridgeAngle` (Bogenmass) = Richtung zur Insel in der XZ-Ebene (x = cos, z = sin).
-- Dieselben Eingaben wie EpilogSummitLayout.compute; der Brueckenansatz des
-- Gipfels endet bei `stubEnd` (hier aus EpilogConfig.SUMMIT berechnet).
--
-- Teil-Arten: "Disc" (liegende Scheibe: size = {Dicke, Durchmesser}),
--             "Block" (size = {x, y, z}; yaw dreht um Y, pitch um die lokale Z-Achse),
--             "Ball"  (size = {Durchmesser}).
-- Masse kommen aus EpilogConfig.ISLAND / .BRIDGE / .SUMMIT, nichts ist fest verdrahtet.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EpilogConfig = require(ReplicatedStorage.Config.EpilogConfig)

local Layout = {}

export type Piece = {
	name     : string,
	kind     : string,          -- "Disc" | "Block" | "Ball"
	size     : { number },
	pos      : { number },      -- Mitte {x, y, z}
	yaw      : number,          -- Bogenmass um Y
	pitch    : number,          -- Bogenmass, hebt die lokale X-Achse
	colorKey : string,
	material : string,          -- Enum.Material-Name
	collide  : boolean,
	hidden   : boolean,         -- unsichtbar (Fangboden)
	deco     : boolean,         -- wippt (nur Client, rein visuell)
}

export type Plank = {
	index    : number,
	size     : { number },      -- {Laenge, Dicke, Breite}
	pos      : { number },      -- Endlage (Mitte)
	yaw      : number,
	pitch    : number,
	colorKey : string,          -- "plankA" | "plankB"
	topStart : { number },      -- Oberflaeche am Anfang der Planke {x, y, z}
	topEnd   : { number },      -- Oberflaeche am Ende
}

export type Result = {
	island    : { Piece },
	planks    : { Plank },
	rails     : { Piece },
	pulse     : Piece,                 -- Lichtstreifen, laeuft nach der letzten Planke ueber die Bruecke
	pulseFrom : { number },            -- Oberflaeche am Beginn der Steigung
	pulseTo   : { number },            -- Oberflaeche am Inselrand
	waypoints : { { number } },        -- Fusspunkte (Oberflaeche), Gipfel -> Insel
	terminal  : { pos : { number }, look : { number } },   -- Fusspunkt + Blickziel (zur Bruecke hin)
	center    : { number },            -- Inselmitte, Oberkante der Wiese
	topY      : number,
	radius    : number,
	stubEnd   : number,                -- Abstand ab Gipfelmitte entlang der Bruecke
	edgeNear  : number,                -- Inselrand (Brueckenseite)
	normal    : { number },            -- Oberflaechen-Normale der Steigung
	slope     : { pitch : number, length : number, rise : number, run : number },
	bridgePieceCount : number,         -- Planken + Gelaender + Lichtstreifen
	islandPieceCount : number,
}

local function polar(cx: number, cz: number, angle: number, r: number): (number, number)
	return cx + math.cos(angle) * r, cz + math.sin(angle) * r
end

-- yaw (Roblox: CFrame.Angles(0, yaw, 0)), bei dem die lokale X-Achse in
-- Richtung (dx, dz) zeigt.
local function yawAlong(dx: number, dz: number): number
	return math.atan2(-dz, dx)
end
Layout.yawAlong = yawAlong

-- Ende des Brueckenansatzes am Gipfel (siehe EpilogSummitLayout, Abschnitt 4).
function Layout.stubEnd(radius: number): number
	local S = EpilogConfig.SUMMIT
	local from = radius - S.bridgeStartInset + (S.bridgePlates - 1) * (S.bridgePlateLen + 0.05)
	return from + S.bridgePlateLen
end

-- radius = Etagenradius (MapConfig.PIT_TOWER_RADIUS).
function Layout.compute(cx: number, cz: number, floorY: number, bridgeAngle: number, radius: number): Result
	local I = EpilogConfig.ISLAND
	local B = EpilogConfig.BRIDGE
	local S = EpilogConfig.SUMMIT
	local island: { Piece } = {}
	local function add(list: { Piece }, p: Piece) table.insert(list, p) end

	local bx, bz = math.cos(bridgeAngle), math.sin(bridgeAngle)
	local sideX, sideZ = -bz, bx                       -- quer zur Bruecke (links)
	local stubEnd = Layout.stubEnd(radius)
	local stubTopY = floorY + S.bridgeThickness        -- Oberflaeche des Ansatzes
	local islandR = I.diameter / 2
	local edgeNear = stubEnd + I.edgeGap               -- Inselrand (Brueckenseite)
	local centerAlong = edgeNear + islandR
	local topY = floorY + I.rise
	local icx, icz = polar(cx, cz, bridgeAngle, centerAlong)

	-- 1. Wiese (begehbar) und Inselrand (leuchtet bei Ankunft)
	add(island, { name = "Wiese", kind = "Disc", size = { I.grassThickness, I.diameter },
		pos = { icx, topY - I.grassThickness / 2, icz }, yaw = 0, pitch = 0, colorKey = "grass",
		material = "Grass", collide = true, hidden = false, deco = false })
	add(island, { name = "Inselrand", kind = "Disc", size = { I.rimThickness, I.diameter + I.rimWidth * 2 },
		pos = { icx, topY - I.grassThickness * 0.55, icz }, yaw = 0, pitch = 0, colorKey = "rimIdle",
		material = "Neon", collide = false, hidden = false, deco = false })

	-- 2. Fels: drei verjuengte Scheiben unter der Wiese
	local yTop = topY - I.grassThickness
	for i, layer in I.rockLayers do
		local frac, h = layer[1], layer[2]
		add(island, { name = "Fels_" .. i, kind = "Disc", size = { h, I.diameter * frac },
			pos = { icx, yTop - h / 2, icz }, yaw = 0, pitch = 0, colorKey = "rock",
			material = "Slate", collide = false, hidden = false, deco = false })
		yTop -= h
	end
	local rockBottom = yTop

	-- 3. Kristalle am unteren Fels (wippen)
	for i = 0, I.crystalCount - 1 do
		local angle = bridgeAngle + math.rad(30 + (360 / I.crystalCount) * i)
		local x, z = polar(icx, icz, angle, islandR * 0.34)
		add(island, { name = "Kristall_" .. (i + 1), kind = "Block",
			size = { I.crystalSize[1], I.crystalSize[2], I.crystalSize[3] },
			pos = { x, rockBottom + I.crystalSize[2] * 0.15, z }, yaw = math.rad(45), pitch = 0,
			colorKey = "crystal", material = "Neon", collide = false, hidden = false, deco = true })
	end

	-- 4. Buesche (wippen), weg von Bruecke und Terminal
	for i = 0, I.bushCount - 1 do
		local angle = bridgeAngle + math.rad(100 + 55 * i)
		local x, z = polar(icx, icz, angle, islandR * 0.62)
		add(island, { name = "Busch_" .. (i + 1), kind = "Ball", size = { I.bushSize },
			pos = { x, topY + I.bushSize * 0.35, z }, yaw = 0, pitch = 0, colorKey = "bush",
			material = "Grass", collide = false, hidden = false, deco = true })
	end

	-- 5. Podest fuer das Terminal (Prompt 4), auf der Seite abseits der Bruecke
	local tx, tz = polar(icx, icz, bridgeAngle, I.terminalBack)
	add(island, { name = "Podest", kind = "Disc", size = { I.padThickness, I.padRadius * 2 },
		pos = { tx, topY + I.padThickness / 2, tz }, yaw = 0, pitch = 0, colorKey = "pad",
		material = "Marble", collide = false, hidden = false, deco = false })

	-- 6. Fangboden unter Bruecke und Insel (unsichtbar): zurueck zum Gipfel bzw. zur Bruecke
	local catchFrom = stubEnd - 6
	local catchTo = centerAlong + islandR + I.catchExtra
	local catchLen = catchTo - catchFrom
	local mx, mz = polar(cx, cz, bridgeAngle, (catchFrom + catchTo) / 2)
	add(island, { name = "Fangboden", kind = "Block", size = { catchLen, 0.4, B.width + I.catchExtra * 2 },
		pos = { mx, floorY - I.catchDepth, mz }, yaw = yawAlong(bx, bz), pitch = 0, colorKey = "none",
		material = "SmoothPlastic", collide = true, hidden = true, deco = false })

	-- Bruecke: gleichmaessige Steigung vom Ansatz zum Inselrand
	local run = I.edgeGap
	local rise = topY - stubTopY
	local pitch = math.atan2(rise, run)
	local slopeLen = math.sqrt(run * run + rise * rise)
	local n = B.planks
	local segLen = slopeLen / n
	-- Oberflaechen-Normale der Steigung (zeigt nach oben und gegen die Laufrichtung)
	local nrmX, nrmY, nrmZ = -math.sin(pitch) * bx, math.cos(pitch), -math.sin(pitch) * bz
	local function surfaceAt(t: number): (number, number, number)
		local x, z = polar(cx, cz, bridgeAngle, stubEnd + run * t)
		return x, stubTopY + rise * t, z
	end

	local planks: { Plank } = {}
	for i = 1, n do
		local ax, ay, az = surfaceAt((i - 1) / n)
		local ex, ey, ez = surfaceAt(i / n)
		-- gerade Planken liegen 4 cm hoeher: die Ueberlappung hat kein Z-Fighting
		local lift = if i % 2 == 0 then 0.04 else 0
		local off = lift - B.plankThick / 2
		local mxs, mys, mzs = (ax + ex) / 2, (ay + ey) / 2, (az + ez) / 2
		planks[i] = {
			index = i, size = { segLen + B.plankOverlap, B.plankThick, B.width },
			pos = { mxs + nrmX * off, mys + nrmY * off, mzs + nrmZ * off },
			yaw = yawAlong(bx, bz), pitch = pitch, colorKey = if i % 2 == 1 then "plankA" else "plankB",
			topStart = { ax, ay, az }, topEnd = { ex, ey, ez },
		}
	end

	-- Gelaender: je Seite ein flaches Stueck ueber dem Ansatz und eines ueber der Steigung
	local rails: { Piece } = {}
	local railOff = B.width / 2 + B.railInset + B.railThick / 2
	local railStart = radius + S.rimWidth + B.railStubStart
	local flatLen = stubEnd - railStart
	local sx0, sy0, sz0 = surfaceAt(0.5)
	for _, sign in { -1, 1 } do
		local label = if sign < 0 then "L" else "R"
		local fx, fz = polar(cx, cz, bridgeAngle, railStart + flatLen / 2)
		add(rails, { name = "Gelaender_" .. label .. "1", kind = "Block", size = { flatLen, B.railHeight, B.railThick },
			pos = { fx + sideX * railOff * sign, stubTopY + B.railHeight / 2, fz + sideZ * railOff * sign },
			yaw = yawAlong(bx, bz), pitch = 0, colorKey = "rail", material = "Glass",
			collide = true, hidden = false, deco = false })
		local h = B.railHeight / 2
		add(rails, { name = "Gelaender_" .. label .. "2", kind = "Block", size = { slopeLen + 0.4, B.railHeight, B.railThick },
			pos = { sx0 + nrmX * h + sideX * railOff * sign, sy0 + nrmY * h, sz0 + nrmZ * h + sideZ * railOff * sign },
			yaw = yawAlong(bx, bz), pitch = pitch, colorKey = "rail", material = "Glass",
			collide = true, hidden = false, deco = false })
	end

	-- Lichtstreifen (quer ueber die Bruecke, laeuft vom Ansatz zur Insel)
	local p0x, p0y, p0z = surfaceAt(0)
	local p1x, p1y, p1z = surfaceAt(1)
	local pulse: Piece = {
		name = "Lichtimpuls", kind = "Block", size = { B.pulseSize[1], B.pulseSize[2], B.width - 0.8 },
		pos = { p0x + nrmX * 0.2, p0y + nrmY * 0.2, p0z + nrmZ * 0.2 }, yaw = yawAlong(bx, bz), pitch = pitch,
		colorKey = "pulse", material = "Neon", collide = false, hidden = false, deco = false,
	}

	-- Wegpunkte (Fusspunkte, Oberflaeche): Weg fuer Prompt 5/6
	local waypoints: { { number } } = {}
	local gx, gz = polar(cx, cz, bridgeAngle, radius - 6)
	table.insert(waypoints, { gx, floorY + S.plateThickness, gz })                 -- 1: Gipfel (Platte)
	local sx, sz = polar(cx, cz, bridgeAngle, radius - S.bridgeStartInset + 0.5)
	table.insert(waypoints, { sx, stubTopY, sz })                                  -- 2: Ansatz
	table.insert(waypoints, { p0x, p0y, p0z })                                     -- 3: Ende des Ansatzes
	for i = 1, n do
		local e = planks[i].topEnd
		table.insert(waypoints, { e[1], e[2], e[3] })                              -- 4..: Planken
	end
	local ax, az = polar(icx, icz, bridgeAngle, -1.5)
	table.insert(waypoints, { ax, topY, az })                                      -- letzter: vor dem Terminal

	return {
		island = island, planks = planks, rails = rails, pulse = pulse,
		pulseFrom = { p0x, p0y, p0z }, pulseTo = { p1x, p1y, p1z },
		waypoints = waypoints,
		terminal = { pos = { tx, topY + I.padThickness, tz }, look = { tx - bx * 10, topY + I.padThickness, tz - bz * 10 } },
		center = { icx, topY, icz }, topY = topY, radius = islandR,
		stubEnd = stubEnd, edgeNear = edgeNear, normal = { nrmX, nrmY, nrmZ },
		slope = { pitch = pitch, length = slopeLen, rise = rise, run = run },
		bridgePieceCount = n + #rails + 1,
		islandPieceCount = #island,
	}
end

return Layout
