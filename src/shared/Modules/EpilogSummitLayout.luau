--!strict
-- EpilogSummitLayout.luau
-- ReplicatedStorage/Modules/EpilogSummitLayout.luau
--
-- Einzige Zustaendigkeit:
--   - Die Geometrie des Gipfels (Prompt 2, Final-Epilog) als reine Rechnung:
--     welche Teile wo stehen. Keine Roblox-Instanzen, nur Zahlen — damit
--     tools/luau-tests/epilog_summit.test.lua Teilezahl, Boden, Gelaender
--     und Luecke pruefen kann. EpilogSummitBuilder baut daraus die Teile.
--
-- Koordinaten: Welt (x, y, z). `floorY` = Oberkante der obersten Etage.
-- `bridgeAngle` (Bogenmass) = Richtung zur Insel in der XZ-Ebene (x = cos, z = sin).
-- Teil-Arten: "Disc" (liegende Scheibe: size = {Dicke, Durchmesser}),
--             "Block" (size = {x, y, z}, yaw dreht um Y; x zeigt dann entlang yaw).
--
-- Maße kommen aus EpilogConfig.SUMMIT, nichts ist fest verdrahtet.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EpilogConfig = require(ReplicatedStorage.Config.EpilogConfig)

local Layout = {}

export type Piece = {
	name     : string,
	kind     : string,          -- "Disc" | "Block"
	size     : { number },
	pos      : { number },      -- Mitte {x, y, z}
	yaw      : number,          -- Bogenmass um Y
	colorKey : string,          -- "rim" | "plate" | "cell" | "bridgeA" | "bridgeB" | "crystal" | "none"
	material : string,          -- Enum.Material-Name
	collide  : boolean,
	hidden   : boolean,         -- unsichtbar (Gelaender, Fangboden, Rig)
}

export type Anchor = {
	name   : string,
	pos    : { number },
	target : { number },        -- Blickziel (Welt)
}

export type Result = {
	pieces  : { Piece },
	anchors : { Anchor },       -- Attachments am Teil "Rig"
	spawn   : { number },       -- Mitte des Avatars
	plateTop: number,
	visibleCount : number,
	totalCount   : number,
}

local function polar(cx: number, cz: number, angle: number, r: number): (number, number)
	return cx + math.cos(angle) * r, cz + math.sin(angle) * r
end

-- yaw (Roblox: CFrame.Angles(0, yaw, 0)), bei dem die lokale X-Achse in
-- Richtung (dx, dz) zeigt.
local function yawAlong(dx: number, dz: number): number
	return math.atan2(-dz, dx)
end

-- radius = Etagenradius (MapConfig.PIT_TOWER_RADIUS).
function Layout.compute(cx: number, cz: number, floorY: number, radius: number, bridgeAngle: number): Result
	local C = EpilogConfig.SUMMIT
	local pieces: { Piece } = {}
	local function add(p: Piece) table.insert(pieces, p) end

	local plateTop = floorY + C.plateThickness

	-- 1. Randring (Neon, ragt rimWidth ueber die Etage) und Platte
	add({ name = "Randring", kind = "Disc", size = { C.rimThickness, (radius + C.rimWidth) * 2 },
		pos = { cx, floorY + C.rimThickness / 2, cz }, yaw = 0, colorKey = "rim", material = "Neon",
		collide = true, hidden = false })
	add({ name = "Bodenplatte", kind = "Disc", size = { C.plateThickness, radius * 2 },
		pos = { cx, floorY + C.plateThickness / 2, cz }, yaw = 0, colorKey = "plate", material = "Marble",
		collide = true, hidden = false })

	-- 2. Waben-Zellen: eine in der Mitte, sechs drumherum
	for i = 0, C.cellCount - 1 do
		local x, z = cx, cz
		if i > 0 then
			x, z = polar(cx, cz, bridgeAngle + math.rad(60 * (i - 1)), C.cellSpacing)
		end
		add({ name = "Zelle_" .. (i + 1), kind = "Disc", size = { C.cellThickness, C.cellRadius * 2 },
			pos = { x, plateTop + C.cellThickness / 2, z }, yaw = 0, colorKey = "cell", material = "SmoothPlastic",
			collide = false, hidden = false })
	end

	-- 3. Kristallsaeulen, weg von der Bruecke
	for i = 0, C.crystalCount - 1 do
		local angle = bridgeAngle + math.rad(45 + (360 / C.crystalCount) * i)
		local x, z = polar(cx, cz, angle, radius - C.crystalInset)
		add({ name = "Kristall_" .. (i + 1), kind = "Block", size = { C.crystalSize[1], C.crystalSize[2], C.crystalSize[3] },
			pos = { x, plateTop + C.crystalSize[2] / 2, z }, yaw = math.rad(45), colorKey = "crystal", material = "Neon",
			collide = false, hidden = false })
	end

	-- 4. Brueckenansatz: flache Platten entlang der Bruecke
	local bx, bz = math.cos(bridgeAngle), math.sin(bridgeAngle)
	for i = 0, C.bridgePlates - 1 do
		local from = radius - C.bridgeStartInset + i * (C.bridgePlateLen + 0.05)
		local x, z = polar(cx, cz, bridgeAngle, from + C.bridgePlateLen / 2)
		add({ name = "Bruecke_" .. (i + 1), kind = "Block", size = { C.bridgePlateLen, C.bridgeThickness, C.bridgeWidth },
			pos = { x, floorY + C.bridgeThickness / 2, z }, yaw = yawAlong(bx, bz),
			colorKey = if i % 2 == 0 then "bridgeA" else "bridgeB", material = "SmoothPlastic",
			collide = true, hidden = false })
	end

	-- 5. Rig: unsichtbarer Anker fuer Spawn und Kamera-Attachments
	add({ name = "Rig", kind = "Block", size = { 1, 1, 1 }, pos = { cx, plateTop + 0.5, cz }, yaw = 0,
		colorKey = "none", material = "SmoothPlastic", collide = false, hidden = true })

	-- 6. Gelaender: n-Eck mit Ecke Richtung Bruecke; die zwei Waende neben der
	--    Ecke sind dort gekuerzt (Luecke fuer die Bruecke).
	local n = C.railSides
	local apothem = radius + C.rimWidth + C.railGap + C.railThick / 2
	local fullLen = 2 * apothem * math.tan(math.pi / n)
	for k = 0, n - 1 do
		local phi = bridgeAngle + math.pi / n + k * (2 * math.pi / n)
		local tx, tz = -math.sin(phi), math.cos(phi)       -- Tangente
		local mx, mz = polar(cx, cz, phi, apothem)
		local len = fullLen + C.railThick                  -- Ecken ueberlappen
		if k == 0 then                                     -- Ende bei kleinerem Winkel liegt an der Bruecke
			len -= C.railOpenEnd + C.railThick / 2
			mx += tx * (C.railOpenEnd + C.railThick / 2) / 2
			mz += tz * (C.railOpenEnd + C.railThick / 2) / 2
		elseif k == n - 1 then
			len -= C.railOpenEnd + C.railThick / 2
			mx -= tx * (C.railOpenEnd + C.railThick / 2) / 2
			mz -= tz * (C.railOpenEnd + C.railThick / 2) / 2
		end
		add({ name = "Gelaender_" .. (k + 1), kind = "Block", size = { len, C.railHeight, C.railThick },
			pos = { mx, floorY + C.railHeight / 2, mz }, yaw = yawAlong(tx, tz), colorKey = "none",
			material = "SmoothPlastic", collide = true, hidden = true })
	end

	-- 7. Fangboden unter dem Rand
	add({ name = "Fangboden", kind = "Disc", size = { 0.4, (radius + C.catchExtra) * 2 },
		pos = { cx, floorY - C.catchDepth, cz }, yaw = 0, colorKey = "none", material = "SmoothPlastic",
		collide = true, hidden = true })

	-- Attachments (Welt)
	local sx, sz = cx, cz
	local spawn = { sx, plateTop + C.spawnLift, sz }
	local startX, startZ = polar(cx, cz, bridgeAngle, C.camStart.front)
	local bridgeX, bridgeZ = polar(cx, cz, bridgeAngle, radius + C.camBridge.out)
	local farX, farZ = polar(cx, cz, bridgeAngle, radius + C.camBridge.out + 40)
	local anchors: { Anchor } = {
		{ name = "Spawn",      pos = spawn, target = { cx + bx * 10, spawn[2], cz + bz * 10 } },
		{ name = "Cam_Start",  pos = { startX, plateTop + C.camStart.height, startZ }, target = { cx, plateTop + 2.5, cz } },
		{ name = "Cam_Orbit",  pos = { cx, plateTop + C.camOrbit.height, cz }, target = { cx, plateTop + 2.5, cz } },
		{ name = "Cam_Bridge", pos = { bridgeX, plateTop + C.camBridge.height, bridgeZ }, target = { farX, plateTop + 2, farZ } },
	}

	local visible = 0
	for _, p in pieces do
		if not p.hidden then visible += 1 end
	end
	return { pieces = pieces, anchors = anchors, spawn = spawn, plateTop = plateTop,
		visibleCount = visible, totalCount = #pieces }
end

return Layout
