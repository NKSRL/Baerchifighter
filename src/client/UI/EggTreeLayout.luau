--!strict
-- EggTreeLayout.luau
-- StarterPlayerScripts/UI/EggTreeLayout.luau
--
-- Einzige Zustaendigkeit:
--   - WO im Ei-Baum etwas steht: Knoten (Kelche), geschwungene Aeste,
--     Stamm. Reine Daten in Design-Pixeln, keine Instanzen, keine Roblox-
--     Typen — deshalb auch im luau-CLI testbar
--     (tools/luau-tests/egg_tree_layout.test.lua) und von der Vorschau
--     (tools/art/preview_ui.py) lesbar.
--
-- Bild des Baums: unten in der Mitte der Stamm, Basis-Ei auf der linken
-- Wurzel, Zucker-Ei in der Astgabel. Von der Gabel wachsen die Pfade nach
-- aussen: Gold nach links, Kristall aus dem Gold nach oben links, Void nach
-- rechts, Kosmos mittig in die Krone. Ascension (Rebirth-Pfad) waechst als
-- eigener Ast aus der rechten Wurzel.
--
-- Koordinaten: (x, y) ist der Fusspunkt des Eis = Mitte des Kelchs.
-- y waechst nach unten (wie in Roblox).

local EggTreeLayout = {}

export type Point = { x: number, y: number }

export type Edge = {
	from  : string?,   -- Elternknoten (nil = waechst aus Stamm/Wurzel)
	to    : string,
	path  : string,    -- Astfarbe/-textur (Pfad-Id aus BaerchiConfig)
	start : Point?,    -- Startpunkt, falls nicht der Elternknoten
	bend  : number,    -- Auswoelbung quer zur Strecke (px, + = rechts der Laufrichtung)
	width : number,    -- Astdicke am Anfang (px)
	trunk : boolean?,  -- laeuft den Stamm hoch: nur Licht, kein eigener Ast
}

EggTreeLayout.SIZE = { x = 1500, y = 1110 }

-- Ei-Hoehe im Baum (Design-Pixel) und Ausrichtung der Kelch-Bilder
-- (tools/art/render_ui.py: CUP_ORTHO 5.0 vs. Ei 3.3 Einheiten, Kelchmitte
-- bei 62 % der Bildhoehe).
EggTreeLayout.EGG_HEIGHT = 84
EggTreeLayout.CUP_SCALE  = 5.0 / 3.3
EggTreeLayout.CUP_ANCHOR = 0.62
-- Der Ast endet etwas unter dem Kelch, damit er in ihn hineinwaechst.
EggTreeLayout.BRANCH_DROP = 22

-- Stamm-Bild (512 × 1024): Lage im Baum. Gabel-Enden siehe FORK_*.
EggTreeLayout.TRUNK = { x = 600, y = 500, w = 300, h = 600 }
local FORK_LEFT: Point  = { x = 642, y = 572 }
local FORK_RIGHT: Point = { x = 858, y = 572 }
local CROWN: Point      = { x = 750, y = 600 }
local ROOT_RIGHT: Point = { x = 862, y = 1072 }

EggTreeLayout.NODES = {
	BasicEgg         = { x = 606,  y = 1040 },
	SugarEgg         = { x = 750,  y = 646 },

	GoldenEgg        = { x = 520,  y = 486 },
	PlatinumEgg      = { x = 372,  y = 452 },
	SunEgg           = { x = 236,  y = 372 },
	ZenithEgg        = { x = 118,  y = 262 },

	CrystalEgg       = { x = 506,  y = 318 },
	PrismEgg         = { x = 418,  y = 196 },
	AuroraEgg        = { x = 300,  y = 118 },

	MistEgg          = { x = 980,  y = 486 },
	VoidEgg          = { x = 1128, y = 452 },
	ShadowEgg        = { x = 1264, y = 372 },
	AbyssEgg         = { x = 1382, y = 262 },

	CometEgg         = { x = 760,  y = 380 },
	NovaEgg          = { x = 694,  y = 246 },
	GalaxyEgg        = { x = 788,  y = 116 },

	AscensionEgg     = { x = 966,  y = 986 },
	TranscendenceEgg = { x = 1110, y = 930 },
	EternityEgg      = { x = 1248, y = 846 },
	OmegaEgg         = { x = 1380, y = 752 },
} :: { [string]: Point }

EggTreeLayout.EDGES = {
	{ from = "BasicEgg",  to = "SugarEgg",  path = "Stamm", bend = 0, width = 30, trunk = true },

	{ from = "SugarEgg",  to = "GoldenEgg",   path = "Gold", start = FORK_LEFT, bend = -26, width = 28 },
	{ from = "GoldenEgg", to = "PlatinumEgg", path = "Gold", bend = 22,  width = 24 },
	{ from = "PlatinumEgg", to = "SunEgg",    path = "Gold", bend = -20, width = 21 },
	{ from = "SunEgg",    to = "ZenithEgg",   path = "Gold", bend = 18,  width = 18 },

	{ from = "GoldenEgg", to = "CrystalEgg", path = "Kristall", bend = 30, width = 22 },
	{ from = "CrystalEgg", to = "PrismEgg",  path = "Kristall", bend = -22, width = 19 },
	{ from = "PrismEgg",  to = "AuroraEgg",  path = "Kristall", bend = 20, width = 16 },

	{ from = "SugarEgg",  to = "MistEgg",   path = "Void", start = FORK_RIGHT, bend = 26, width = 28 },
	{ from = "MistEgg",   to = "VoidEgg",   path = "Void", bend = -22, width = 24 },
	{ from = "VoidEgg",   to = "ShadowEgg", path = "Void", bend = 20,  width = 21 },
	{ from = "ShadowEgg", to = "AbyssEgg",  path = "Void", bend = -18, width = 18 },

	-- Kosmos: waechst sichtbar aus der Krone (freigeschaltet wird das
	-- Kometen-Ei ueber die Endeier, siehe EggConfig.TREE.CometEgg).
	{ from = "SugarEgg",  to = "CometEgg",  path = "Kosmos", start = CROWN, bend = 18, width = 24 },
	{ from = "CometEgg",  to = "NovaEgg",   path = "Kosmos", bend = -24, width = 20 },
	{ from = "NovaEgg",   to = "GalaxyEgg", path = "Kosmos", bend = 24,  width = 17 },

	{ from = nil, to = "AscensionEgg", path = "Ascension", start = ROOT_RIGHT, bend = 18, width = 26 },
	{ from = "AscensionEgg", to = "TranscendenceEgg", path = "Ascension", bend = -18, width = 22 },
	{ from = "TranscendenceEgg", to = "EternityEgg",  path = "Ascension", bend = 18,  width = 19 },
	{ from = "EternityEgg", to = "OmegaEgg",          path = "Ascension", bend = -16, width = 16 },
} :: { Edge }

-- Startpunkt des Lichts beim Freischalten: Stammfuss.
EggTreeLayout.WAVE_ORIGIN = { x = 750, y = 1080 } :: Point

--------------------------------------------------------------------------------
-- Rechnen
--------------------------------------------------------------------------------

local function branchEnd(eggId: string): Point
	local n = EggTreeLayout.NODES[eggId]
	return { x = n.x, y = n.y + EggTreeLayout.BRANCH_DROP }
end

function EggTreeLayout.edgeTo(eggId: string): Edge?
	for _, e in EggTreeLayout.EDGES do
		if e.to == eggId then return e end
	end
	return nil
end

-- Start-, Kontroll- und Endpunkte des Asts (kubische Bezier-Kurve).
function EggTreeLayout.controls(edge: Edge): (Point, Point, Point, Point)
	local p0: Point = edge.start or (if edge.from then branchEnd(edge.from) else EggTreeLayout.WAVE_ORIGIN)
	local p3 = branchEnd(edge.to)
	local dx, dy = p3.x - p0.x, p3.y - p0.y
	local len = math.max(1, math.sqrt(dx * dx + dy * dy))
	-- Normale rechts der Laufrichtung
	local nx, ny = -dy / len, dx / len
	local c1 = { x = p0.x + dx / 3 + nx * edge.bend, y = p0.y + dy / 3 + ny * edge.bend }
	local c2 = { x = p0.x + dx * 2 / 3 + nx * edge.bend * 0.6, y = p0.y + dy * 2 / 3 + ny * edge.bend * 0.6 }
	return p0, c1, c2, p3
end

-- Punkte entlang des Asts, etwa alle `step` Pixel (mindestens 3).
function EggTreeLayout.sample(edge: Edge, step: number): { Point }
	local p0, c1, c2, p3 = EggTreeLayout.controls(edge)
	local approx = math.sqrt((p3.x - p0.x) ^ 2 + (p3.y - p0.y) ^ 2) + math.abs(edge.bend)
	local n = math.max(3, math.ceil(approx / step))
	local out = {}
	for i = 0, n do
		local t = i / n
		local a, b, c, d = (1 - t) ^ 3, 3 * (1 - t) ^ 2 * t, 3 * (1 - t) * t * t, t ^ 3
		table.insert(out, {
			x = a * p0.x + b * c1.x + c * c2.x + d * p3.x,
			y = a * p0.y + b * c1.y + c * c2.y + d * p3.y,
		})
	end
	return out
end

-- Alle Aeste vom Stamm bis zu `eggId`, in Wuchsrichtung (fuer die Lichtwelle).
function EggTreeLayout.chain(eggId: string): { Edge }
	local list: { Edge } = {}
	local current: string? = eggId
	local guard = 0
	while current and guard < 32 do
		guard += 1
		local edge = EggTreeLayout.edgeTo(current)
		if not edge then break end
		table.insert(list, 1, edge)
		current = edge.from
	end
	return list
end

return EggTreeLayout
