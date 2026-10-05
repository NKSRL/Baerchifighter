--!strict
-- EggMesh.luau
-- ReplicatedStorage/Modules/EggMesh.luau
--
-- Einzige Zustaendigkeit:
--   - Die Form des gestapelten Eis: Profilkurve (Zahlen, auch fuer den Server)
--     und das Mesh selbst (nur auf dem Client baubar).
--
-- WARUM CLIENT: ein EditableMesh wird nicht repliziert. Auf dem Server gebaut,
-- zeigt der Client ein rot-gruenes Schachbrett (fehlende Textur). Darum baut
-- der Client das Mesh selbst (LaidEggMeshController) und legt es ueber den
-- Server-Koerper; der Server nutzt hier nur eggRadius/TIER_EDGES fuer Gurte.
--
-- Das Mesh ist ein Rotationskoerper: Superellipse (runde Pole), unten etwas
-- breiter, in Stufen zerlegt, die sich nach oben verjuengen und an der Naht
-- nach aussen springen; Kanten leicht gefast. Eigene Eckpunkte je
-- Profilsegment halten die Stufenkanten scharf, waehrend die Flaechen
-- rundherum glatt schattiert sind. Mass: 1 breit, 1 hoch, um den Ursprung
-- zentriert.

local EggMesh = {}

local MESH_SEGMENTS = 40
local TIER_TAPER    = 0.08                                  -- Verjuengung je Stufe nach oben
local EGG_TILT      = 0.12                                  -- unten breiter als oben
local EGG_POLE      = 2.5                                   -- Superellipse: >2 macht die Pole runder

EggMesh.TIER_EDGES = { 0, 0.15, 0.32, 0.50, 0.67, 0.83, 1 }
local TIER_SHADE   = { 0.86, 1.0, 0.93, 1.0, 0.9, 0.96 }    -- Helligkeit je Stufe (Segment-Look)

local function eggCurve(t: number): number
	local u = (t - 0.5) * 2
	return math.max(0, 1 - math.abs(u) ^ EGG_POLE) ^ (1 / EGG_POLE) * (1 - EGG_TILT * u)
end

local EGG_NORM = 0
for step = 0, 200 do EGG_NORM = math.max(EGG_NORM, eggCurve(step / 200)) end

-- Radius (Anteil der Eibreite, Maximum 0,5) auf Hoehe t (0 bis 1), ohne Stufen
function EggMesh.radius(t: number): number
	return 0.5 * eggCurve(t) / EGG_NORM
end

local _template: MeshPart? = nil
local _failed = false

local function build(): MeshPart
	local AssetService = game:GetService("AssetService")
	local edges = EggMesh.TIER_EDGES

	local profile: { { number } } = {}
	local LS    = { 0, 0.06, 0.5, 0.94, 1 }
	local BEVEL = { 0.96, 1, 1, 1, 0.96 }
	for tierIndex = 1, #edges - 1 do
		local a, b = edges[tierIndex], edges[tierIndex + 1]
		for k, l in LS do
			local t = a + (b - a) * l
			local r = EggMesh.radius(t) * (1 - TIER_TAPER * l) * BEVEL[k]
			if tierIndex == 1 and k == 1 then r = 0 end
			if tierIndex == #edges - 1 and k == #LS then r = 0 end
			table.insert(profile, { t, r, tierIndex })
		end
	end

	local mesh = AssetService:CreateEditableMesh()
	local colorIds: { number } = {}
	for tierIndex, v in TIER_SHADE do
		colorIds[tierIndex] = mesh:AddColor(Color3.new(v, v, v), 1)
	end

	for index = 1, #profile - 1 do
		local p1, p2 = profile[index], profile[index + 1]
		local y1, r1, y2, r2 = p1[1], p1[2], p2[1], p2[2]
		if r1 > 0 or r2 > 0 then
			local n2 = Vector2.new(y2 - y1, -(r2 - r1)).Unit
			local colorId = colorIds[p2[3]]

			for j = 0, MESH_SEGMENTS - 1 do
				local a1 = j / MESH_SEGMENTS * math.pi * 2
				local a2 = (j + 1) / MESH_SEGMENTS * math.pi * 2
				local c1, s1, c2, s2 = math.cos(a1), math.sin(a1), math.cos(a2), math.sin(a2)

				local function vert(r: number, y: number, c: number, s: number)
					return mesh:AddVertex(Vector3.new(r * s, y - 0.5, r * c))
				end
				local function norm(c: number, s: number)
					return mesh:AddNormal(Vector3.new(n2.X * s, n2.Y, n2.X * c).Unit)
				end

				local v1a, v1b = vert(r1, y1, c1, s1), vert(r1, y1, c2, s2)
				local v2a, v2b = vert(r2, y2, c1, s1), vert(r2, y2, c2, s2)
				local na, nb = norm(c1, s1), norm(c2, s2)

				local function tri(va: number, vb: number, vc: number, nA: number, nB: number, nC: number)
					local f = mesh:AddTriangle(va, vb, vc)
					mesh:SetFaceNormals(f, { nA, nB, nC })
					mesh:SetFaceColors(f, { colorId, colorId, colorId })
				end
				tri(v1a, v2b, v2a, na, nb, na)
				tri(v1a, v1b, v2b, na, nb, nb)
			end
		end
	end

	local part = AssetService:CreateMeshPartAsync(Content.fromObject(mesh))
	part.Anchored   = true
	part.CanCollide = false
	part.CanTouch   = false
	part.CanQuery   = false
	part.CastShadow = true
	return part
end

-- Die Vorlage (nur CLIENT): nil, wenn EditableMesh nicht erlaubt ist
function EggMesh.getTemplate(): MeshPart?
	if _template then return _template end
	if _failed then return nil end
	local ok, result = pcall(build)
	if ok then
		_template = result
		return result
	end
	_failed = true
	warn("[EggMesh] Ei-Mesh nicht verfuegbar:", result)
	return nil
end

return EggMesh
