--!strict
-- IncubatorModels.luau
-- ReplicatedStorage/Config/IncubatorModels.luau
--
-- Einzige Zustaendigkeit:
--   - Die Teile der vier Inkubator-Modelle (Stufe 1..4), uebernommen aus
--     EggIncubator_L1_ready / L2 / L3 / L4_breeding.glb (15.10.2026):
--     Baumstumpf, Honigplatte, Kuppel mit Baerchi-Ohren, Honigtropfen,
--     Sechskant-Nieten, ab Stufe 4 eine Krone.
--
-- Positionen sind relativ zur Bodenmitte des Inkubators (Y = 0 ist der
-- Boden). Zylinder stehen (Roblox-Zylinder liegen in X, daher Drehung Z = 90);
-- die Ohren sind Scheiben mit Achse Z. Gebaut wird in Util/MapBuild/
-- IncubatorBuilder; Teilenamen, die dort gebraucht werden:
--   Base (Stumpf, solid, PrimaryPart), Pad_1 (Standflaeche), Dome_1 (Kuppel).
-- Nicht uebernommen: Kontur-Huellen und der Bienen-Aufkleber (Bild fehlt).

export type Piece = {
	name         : string,
	shape        : Enum.PartType,
	size         : Vector3,
	offset       : Vector3,
	color        : Color3,
	material     : Enum.Material,
	rotation     : Vector3?,
	transparency : number?,
	solid        : boolean?,
	decals       : { Deco }?,
	sticker      : string?,   -- Bild-ID: duenne Flaeche mit Aufkleber (SurfaceGui)
}

-- Bild auf einer Seite des Teils (Decal) oder gekachelt (Texture, tile = Studs pro Kachel)
export type Deco = { id: number, face: Enum.NormalId, tile: Vector2?, color: Color3? }

-- Bilder (Asset Manager, 15.10.2026). 20.10.: Das waren Decal-IDs (Asset-Typ 13); sie laden weder als Decal.Texture
-- noch als Bild ("Asset type does not match requested type"). Hier stehen jetzt die Image-IDs dahinter
-- (InsertService:LoadAsset(<decalId>) -> Decal.Texture). Alte Decal-IDs im Kommentar je Zeile.
local IMG = {
	Bark = 117335543708569,          -- Decal 114888432264786
	BeeSticker = 94482730024992,     -- Decal 73015920974297
	GlowRing = 91854870308136,       -- Decal 136391997379517
	Honeycomb = 117223102024916,     -- Decal 84016842651629
	HoneyDripTrim = 89680454074594,  -- Decal 99699962232406
	Sign = 122830236597585,          -- Decal 106270284386721
	Sparkle = 71432124214267,        -- Decal 122651035050334
	WoodRings = 121669955699632,     -- Decal 97067726944869
}

local IncubatorModels = {}
IncubatorModels.IMAGES = IMG

local UP   = Vector3.new(0, 0, 90)   -- stehender Zylinder
local FACE = Vector3.new(0, 90, 0)   -- Scheibe mit Achse Z (Ohren)

local BARK   = Color3.fromRGB(133, 78, 39)
local DARK   = Color3.fromRGB(78, 42, 20)
local HONEY  = Color3.fromRGB(255, 182, 39)
local DRIP   = Color3.fromRGB(255, 215, 90)
local PINK   = Color3.fromRGB(255, 111, 176)
local STUD   = Color3.fromRGB(255, 241, 201)
local PLASTIC = Enum.Material.SmoothPlastic

local TOP = Enum.NormalId.Right -- Deckflaeche eines stehenden Zylinders (UP)

local function cyl(name: string, height: number, diameter: number, at: Vector3, color: Color3,
	material: Enum.Material?, rotation: Vector3?, solid: boolean?): Piece
	return {
		name = name, shape = Enum.PartType.Cylinder,
		size = Vector3.new(height, diameter, diameter), offset = at,
		color = color, material = material or PLASTIC, rotation = rotation or UP, solid = solid,
	}
end

local function y(value: number): Vector3 return Vector3.new(0, value, 0) end

-- Gemeinsame Teile (je Stufe mit kleinen Unterschieden zusammengesetzt)
local function with(piece: Piece, decals: { Deco }): Piece
	piece.decals = decals
	return piece
end

local function glow(diameter: number): Piece
	return with(cyl("Glow", 0.1, diameter, y(0.05), Color3.fromRGB(232, 146, 42), Enum.Material.Neon),
		{ { id = IMG.GlowRing, face = TOP } })
end
local FLARE = cyl("Flare", 0.7, 13.0, y(0.45), BARK, Enum.Material.Wood, UP, true)
local BASE  = with(cyl("Base", 2.2, 11.4, y(1.9), BARK, Enum.Material.Wood, UP, true),
	{ { id = IMG.Bark, face = Enum.NormalId.Front }, { id = IMG.Bark, face = Enum.NormalId.Back } })
local STICKER: Piece = {
	name = "BeeSticker", shape = Enum.PartType.Block, size = Vector3.new(2.7, 1.8, 0.08),
	offset = Vector3.new(0, 1.8, -5.75), color = BARK, material = PLASTIC, transparency = 1,
	sticker = "rbxassetid://" .. IMG.BeeSticker,
}
local LIP   = cyl("Lip", 0.3, 11.8, y(2.85), DARK)
local function plate(color: Color3, deco: Deco): Piece return with(cyl("Plate", 0.6, 12.6, y(3.3), color), { deco }) end
local WOOD_PLATE: Deco = { id = IMG.WoodRings, face = TOP }
local HONEY_PLATE: Deco = { id = IMG.Honeycomb, face = TOP, tile = Vector2.new(3.46, 2) }
local RING  = cyl("PadRing", 0.25, 6.6, y(3.725), DARK)
local PAD   = cyl("Pad_1", 0.3, 5.8, y(3.75), Color3.fromRGB(233, 211, 166))
local DOME: Piece = {
	name = "Dome_1", shape = Enum.PartType.Ball, size = Vector3.new(6.4, 6.4, 6.4), offset = y(5.6),
	color = Color3.fromRGB(255, 199, 106), material = Enum.Material.Glass, transparency = 0.72,
}
local EARS: { Piece } = {
	cyl("EarL", 0.5, 1.6, Vector3.new(-2.25, 8.15, 0.2), DARK, PLASTIC, FACE),
	cyl("EarR", 0.5, 1.6, Vector3.new(2.25, 8.15, 0.2), DARK, PLASTIC, FACE),
	cyl("EarInnerL", 0.06, 0.75, Vector3.new(-2.25, 8.15, -0.08), PINK, PLASTIC, FACE),
	cyl("EarInnerR", 0.06, 0.75, Vector3.new(2.25, 8.15, -0.08), PINK, PLASTIC, FACE),
}
local DRIPS: { Piece } = {
	cyl("Drip1", 1.395, 1.0,  Vector3.new(-1.991, 2.603, 5.469), DRIP),
	cyl("Drip2", 2.17,  0.8,  Vector3.new(-5.563, 2.215, 2.025), DRIP),
	cyl("Drip3", 1.085, 0.65, Vector3.new(4.911, 2.757, 3.439), DRIP),
	cyl("Drip4", 2.635, 0.6,  Vector3.new(-4.612, 1.982, -3.87), DRIP),
}
local function stud(name: string, x: number, z: number, color: Color3): Piece
	return cyl(name, 0.16, 0.7, Vector3.new(x, 3.68, z), color)
end

local function join(...: { Piece } | Piece): { Piece }
	local out: { Piece } = {}
	for _, item in { ... } do
		if (item :: any).name then
			table.insert(out, item :: Piece)
		else
			for _, piece in item :: { Piece } do table.insert(out, piece) end
		end
	end
	return out
end

-- Stufe -> Teile. Je Stufe hoechstens IncubatorConfig.PART_BUDGET (20).
IncubatorModels.LEVELS = {
	-- Stufe 1 "ready": nackter Stumpf mit Kuppel
	[1] = join(glow(12.384), BASE, LIP, plate(Color3.fromRGB(201, 138, 78), WOOD_PLATE), STICKER, RING, PAD, DOME, EARS),
	-- Stufe 2: breiterer Fuss, zwei Honigtropfen, Honigplatte
	[2] = join(glow(14.4), FLARE, BASE, LIP, plate(HONEY, HONEY_PLATE), STICKER, DRIPS[1], DRIPS[2], RING, PAD, DOME, EARS),
	-- Stufe 3: alle vier Tropfen, drei Nieten
	[3] = join(glow(14.4), FLARE, BASE, LIP, plate(HONEY, HONEY_PLATE), STICKER, DRIPS, RING, PAD, DOME, EARS,
		stud("Stud1", 3.96, -3.96, STUD), stud("Stud2", 3.96, 3.96, STUD), stud("Stud3", -3.96, 3.96, STUD)),
	-- Stufe 4: breiterer Ring, goldene Nieten, Krone auf der Kuppel
	[4] = join(glow(15.552), FLARE, BASE, plate(HONEY, HONEY_PLATE), STICKER, DRIPS, RING, PAD, DOME, EARS,
		stud("Stud2", 3.96, 3.96, Color3.fromRGB(255, 194, 26)), stud("Stud4", -3.96, -3.96, Color3.fromRGB(255, 194, 26)),
		cyl("CrownBand", 0.7, 2.3, y(9.05), DRIP),
		{ name = "CrownGem", shape = Enum.PartType.Ball, size = Vector3.new(0.8, 0.8, 0.8), offset = y(9.72), color = PINK, material = Enum.Material.Neon }),
} :: { [number]: { Piece } }

return IncubatorModels
