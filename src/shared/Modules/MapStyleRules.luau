--!strict
-- MapStyleRules.luau
-- ReplicatedStorage/Modules/MapStyleRules.luau
--
-- Einzige Zustaendigkeit:
--   - Reine Rechenregeln fuer den Map-Stil V2 (ohne Roblox-Instanzen, daher testbar):
--     Variante waehlen, Skalierung, Budget-Pruefung, Mittelpunkt-Versatz einer Vorlage.

local MapStyleRules = {}

-- Variante einer Bodenkachel aus ihrer Rasterposition (deterministisch, ohne Zufall).
function MapStyleRules.tileVariant(i: number, j: number, count: number): number
	return (i * 7 + j * 13) % count + 1
end

-- Element einer Liste aus einer Zahl r in [0, 1).
function MapStyleRules.pick<T>(list: { T }, r: number): T
	local index = math.clamp(math.floor(r * #list) + 1, 1, #list)
	return list[index]
end

-- Skalierung, die eine Vorlage der natuerlichen Breite `natural` auf `wanted` bringt.
function MapStyleRules.scaleForWidth(wanted: number, natural: number): number
	if natural <= 0 then return 1 end
	return wanted / natural
end

-- Hoehe des Mittelpunkts einer MeshPart ueber dem Pivot (Boden), wenn die Box von
-- zMin bis zMax reicht und die MeshPart die Hoehe `sizeY` hat (Massstab egal).
function MapStyleRules.centerOffsetY(zMin: number, zMax: number, sizeY: number): number
	local height = zMax - zMin
	if height <= 0 then return sizeY * 0.5 end
	return ((zMin + zMax) * 0.5) / height * sizeY
end

-- Passt ein Dreieckszaehler ins Budget?
function MapStyleRules.withinBudget(tris: number, limit: number): boolean
	return tris <= limit
end

-- Old-School-Boden (P1, 20.10.): Raster aus Bloecken, die in den Kreis passen.
-- levels = Kantenlaengen von grob nach fein (jede muss die vorige teilen), z.B. {40, 20, 10}.
-- Ein Block wird nur gesetzt, wenn alle vier Ecken innerhalb von radius - margin liegen;
-- Zellen am Rand werden feiner unterteilt, der Rest bleibt dem Zylinder darunter.
-- Rueckgabe: Liste { x, z, size } (x/z = Mitte der Zelle, relativ zur Inselmitte).
function MapStyleRules.groundCells(radius: number, levels: { number }, margin: number): { { x: number, z: number, size: number } }
	local out = {}
	local limit = radius - margin
	local function inside(x: number, z: number, s: number): boolean
		for _, dx in { 0, s } do
			for _, dz in { 0, s } do
				local px, pz = x + dx, z + dz
				if px * px + pz * pz > limit * limit then return false end
			end
		end
		return true
	end
	local function touches(x: number, z: number, s: number): boolean
		local nx = if x <= 0 and x + s >= 0 then 0 elseif x > 0 then x else x + s
		local nz = if z <= 0 and z + s >= 0 then 0 elseif z > 0 then z else z + s
		return nx * nx + nz * nz < limit * limit
	end
	local function rec(x: number, z: number, s: number, i: number)
		if inside(x, z, s) then
			table.insert(out, { x = x + s * 0.5, z = z + s * 0.5, size = s })
			return
		end
		if not touches(x, z, s) or i >= #levels then return end
		local nextSize = levels[i + 1]
		local n = math.floor(s / nextSize + 0.5)
		for a = 0, n - 1 do
			for b = 0, n - 1 do
				rec(x + a * nextSize, z + b * nextSize, nextSize, i + 1)
			end
		end
	end
	local top = levels[1]
	local n = math.floor(2 * radius / top) + 1
	local origin = -(n * top) * 0.5
	for a = 0, n - 1 do
		for b = 0, n - 1 do
			rec(origin + a * top, origin + b * top, top, 1)
		end
	end
	return out
end

return MapStyleRules
