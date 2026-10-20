--!strict
-- EggTreeLayout.luau
-- StarterPlayerScripts/UI/EggTreeLayout.luau
--
-- Einzige Zustaendigkeit:
--   - WO im Ei-Baum etwas steht. Reine Daten in Pixeln des Fenster-Bildes
--     (UI2_eggtree_v2, 1844 x 853), keine Instanzen, keine Roblox-Typen.
--
-- 19.10.: Neues Template. Der Baum ist ins Bild gemalt (Stamm, Aeste, 27
-- Kelche); hier stehen nur die Mittelpunkte der Kelche. Das Bild hat drei
-- logische Zweige:
--   Mitte  (5)   Stamm von unten nach oben: Basis, Zucker, Komet, Nova, Galaxie
--   Links  (11)  Gold-Kette E-F-D-C, Kristall-Kette I-H-G, 3 freie Aeste, Sprung-Tor
--   Rechts (11)  Void-Kette E-F-D-C, Ascension I-H-G + A, 2 freie Aeste, Sprung-Tor
-- Die Aeste im Bild sind nur Zierde; welches Ei wann frei wird, steht in
-- EggConfig.TREE. Die Sprung-Tore (die Blaetter oben neben dem Stamm) zeigen
-- die moeglichen Zweigspruenge (EggConfig.JUMPS).
--
-- Koordinaten: (x, y) ist die Mitte des Kelchs, y waechst nach unten.

local EggTreeLayout = {}

export type Point = { x: number, y: number }

export type Slot = {
	id     : string,
	branch : string,   -- "Left" | "Middle" | "Right"
	x      : number,
	y      : number,
}

-- Alte Ast-Daten (Aeste sind jetzt im Bild); nur noch als Typ fuer die Lichtwelle
export type Edge = { from: string?, to: string, path: string, trunk: boolean? }

EggTreeLayout.SIZE = { x = 1844, y = 853 }

-- Kelchdurchmesser (innen dunkel) und Ei-Hoehe darin, in Bildpixeln
EggTreeLayout.NODE_D   = 84
EggTreeLayout.EGG_HEIGHT = 62

-- Eier -> Kelch
EggTreeLayout.NODES = {
	-- Mitte (Stamm)
	BasicEgg         = { x = 971,  y = 735 },
	SugarEgg         = { x = 970,  y = 580 },
	CometEgg         = { x = 971,  y = 443 },
	NovaEgg          = { x = 967,  y = 276 },
	GalaxyEgg        = { x = 966,  y = 138 },

	-- Links: Gold E-F-D-C
	GoldenEgg        = { x = 693,  y = 424 },
	PlatinumEgg      = { x = 592,  y = 535 },
	SunEgg           = { x = 472,  y = 400 },
	ZenithEgg        = { x = 345,  y = 313 },
	-- Links: Kristall I-H-G
	CrystalEgg       = { x = 749,  y = 610 },
	PrismEgg         = { x = 525,  y = 661 },
	AuroraEgg        = { x = 408,  y = 573 },

	-- Rechts: Void E-F-D-C
	MistEgg          = { x = 1252, y = 420 },
	VoidEgg          = { x = 1416, y = 522 },
	ShadowEgg        = { x = 1513, y = 378 },
	AbyssEgg         = { x = 1663, y = 306 },
	-- Rechts: Ascension I-H-G + Spitze
	AscensionEgg     = { x = 1247, y = 600 },
	TranscendenceEgg = { x = 1440, y = 665 },
	EternityEgg      = { x = 1594, y = 565 },
	OmegaEgg         = { x = 1527, y = 219 },
} :: { [string]: Point }

-- Freie Aeste (noch ohne Ei): "bald"
EggTreeLayout.EMPTY = {
	{ id = "L_A", branch = "Left",  x = 456,  y = 211 },
	{ id = "L_B", branch = "Left",  x = 618,  y = 275 },
	{ id = "L_K", branch = "Left",  x = 832,  y = 345 },
	{ id = "R_B", branch = "Right", x = 1321, y = 268 },
	{ id = "R_K", branch = "Right", x = 1107, y = 345 },
} :: { Slot }

-- Sprung-Tore: ein Blatt je Seite oben neben dem Stamm (Verbindung zum
-- mittleren Zweig). Left = Sprung Links -> Mitte, Right = Rechts -> Mitte.
EggTreeLayout.GATES = {
	Left  = { id = "G_Left",  branch = "Left",  x = 775,  y = 199 },
	Right = { id = "G_Right", branch = "Right", x = 1159, y = 197 },
} :: { [string]: Slot }

-- Klickflaechen im Fenster-Bild (x, y, Breite, Hoehe)
EggTreeLayout.TABS = {
	eggs  = { 30, 155, 135, 135 },
	paws  = { 30, 303, 135, 135 },
	star  = { 25, 445, 150, 140 },
	crown = { 30, 597, 135, 135 },
}
EggTreeLayout.CLOSE = { 1733, 20, 88, 88 }

-- Mittelpunkt eines Eis, Tors oder freien Asts (nil = unbekannt)
function EggTreeLayout.pointOf(id: string): Point?
	local n = EggTreeLayout.NODES[id]
	if n then return n end
	for _, g in EggTreeLayout.GATES do
		if g.id == id then return g end
	end
	for _, e in EggTreeLayout.EMPTY do
		if e.id == id then return e end
	end
	return nil
end

-- Es gibt keine gezeichneten Aeste mehr (sind im Bild): leere Listen halten
-- alte Aufrufer (Lichtwelle) am Laufen.
EggTreeLayout.EDGES = {} :: { any }
function EggTreeLayout.chain(_eggId: string): { any }
	return {}
end

return EggTreeLayout
