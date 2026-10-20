--!strict
-- EpilogMeshes: optionale Mesh-Vorlagen fuer Insel, Planke und Terminal (Epilog).
--
-- Die Vorlagen liegen als Modelle in ReplicatedStorage.Assets (Studio-Import der
-- FBX aus assets/epilog/, siehe docs/HBB_EPILOG_ASSETS_2026-10-20.md):
--   EpilogIsland   -> MeshParts Epilog_Insel_Wiese/_Fels/_Kristall/_Busch1-3
--   EpilogPlank    -> MeshPart  Epilog_Plank
--   EpilogTerminal -> MeshParts Epilog_Terminal_<Teil> (Namen wie EpilogTerminalLayout)
-- Fehlt eine Vorlage (oder ein Teil darin), liefert dieses Modul nil und der Aufrufer
-- baut wie bisher die Primitive. Es wird nie etwas veraendert oder geloescht.
--
-- Massstab ist egal: Insel und Planke werden ueber ihre bekannten Referenzmasse
-- angepasst, das Terminal ueber die Teilgroessen aus dem Layout (Size wird gesetzt).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EpilogMeshes = {}

-- Breite der Wiese im Blender-Modell (Epilog_Insel_Wiese, Studs bei Importmassstab 1).
local WIESE_REF_BREITE = 24.86
-- Nenndurchmesser, auf den das Blender-Modell gebaut ist (EpilogConfig.ISLAND.diameter).
local INSEL_REF_DURCHMESSER = 24

local ISLAND_PARTS = {
	"Epilog_Insel_Wiese", "Epilog_Insel_Fels", "Epilog_Insel_Kristall",
	"Epilog_Insel_Busch1", "Epilog_Insel_Busch2", "Epilog_Insel_Busch3",
}

function EpilogMeshes.template(name: string): Instance?
	if name == "" then return nil end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then return nil end
	return assets:FindFirstChild(name)
end

-- Klon des MeshParts `partName` aus der Vorlage `templateName` (nil, wenn es fehlt
-- oder kein Mesh hat).
function EpilogMeshes.meshPart(templateName: string, partName: string): MeshPart?
	local root = EpilogMeshes.template(templateName)
	if not root then return nil end
	for _, d in root:GetDescendants() do
		if d.Name == partName and d:IsA("MeshPart") and d.MeshId ~= "" then
			return d:Clone()
		end
	end
	return nil
end

-- Gemeinsame Grundeinstellung fuer ein Mesh-Teil im Epilog.
function EpilogMeshes.setup(part: MeshPart, name: string, size: Vector3, cframe: CFrame)
	part.Name          = name
	part.Size          = size
	part.CFrame        = cframe
	part.Anchored      = true
	part.CanCollide    = false
	part.CanTouch      = false
	part.CastShadow    = false
	part.TopSurface    = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
end

-- true, wenn die Vorlage die Farben aus der Config will (Attribut FarbenAusConfig):
-- fuer den Fall, dass Studio die Vertexfarben der FBX nicht uebernimmt.
function EpilogMeshes.colorsFromConfig(templateName: string): boolean
	local root = EpilogMeshes.template(templateName)
	return root ~= nil and root:GetAttribute("FarbenAusConfig") == true
end

-- Insel-Huelle: Klone der sechs Teile, passend auf die Insel gesetzt.
--   top    = Mitte der Wiesenoberkante
--   yaw    = Drehung um Y (Blender-Modell: Bruecke liegt in +X, Roblox yaw = -Bruecken-Winkel)
--   diameter = Durchmesser der Wiese
-- Gibt eine Liste { name, MeshPart } zurueck oder nil, wenn die Vorlage unvollstaendig ist.
function EpilogMeshes.islandSkin(top: Vector3, yaw: number, diameter: number, templateName: string)
	: { { name: string, part: MeshPart } }?
	local clones: { { name: string, part: MeshPart } } = {}
	for _, name in ISLAND_PARTS do
		local m = EpilogMeshes.meshPart(templateName, name)
		if not m then
			for _, c in clones do c.part:Destroy() end
			return nil
		end
		table.insert(clones, { name = name, part = m })
	end
	local wiese = clones[1].part
	local importScale = wiese.Size.X / WIESE_REF_BREITE        -- Studs je Blender-Einheit
	local f = (diameter / INSEL_REF_DURCHMESSER) / importScale  -- Faktor auf die Vorlagenmasse
	local originCF = CFrame.new(wiese.CFrame:PointToWorldSpace(Vector3.new(0, wiese.Size.Y / 2, 0)))
		* wiese.CFrame.Rotation
	local target = CFrame.new(top) * CFrame.Angles(0, yaw, 0)
	for _, c in clones do
		local part = c.part
		local rel = originCF:ToObjectSpace(part.CFrame)
		local size = part.Size * f
		local cf = target * CFrame.new(rel.Position * f) * rel.Rotation
		EpilogMeshes.setup(part, c.name, size, cf)
	end
	return clones
end

return EpilogMeshes
