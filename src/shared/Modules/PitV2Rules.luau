--!strict
-- PitV2Rules.luau
-- ReplicatedStorage/Modules/PitV2Rules.luau
--
-- Einzige Zustaendigkeit:
--   - Reine Rechnung fuer das Honig-Kolosseum (PIT_V2): Lage und Masse der
--     unsichtbaren Kollisionsbloecke in Arena-Koordinaten. Keine Instanzen,
--     getestet in tools/luau-tests/pit_v2.test.lua.
--
-- Arena-Koordinaten wie im Blender-Prototyp: x = quer, y = laengs (+ = Steg),
-- h = Hoehe ueber der Kampfflaeche, Winkel 0 = +x, 90 = Steg. PitV2Builder
-- setzt einen Block bei (x, h, -y) mit Drehung `angle` um die Hochachse.

local PitV2Rules = {}

export type Block = {
	x      : number,   -- Mitte
	y      : number,
	h      : number,
	angle  : number,   -- Grad; die Block-Achse "radial" zeigt in diese Richtung
	radial : number,   -- Masse: entlang angle, Hoehe, quer dazu
	height : number,
	length : number,
}

export type Arc = { inner: number, outer: number, bottom: number, top: number, from: number, to: number, segments: number }
export type Box = { x: number, y: number, size: number, bottom: number, top: number }

-- Ein Bogen-Band [inner, outer] als gerade Bloecke. Damit das Band auch an den
-- Enden jedes Stuecks abgedeckt ist, reicht ein Block innen um den Kosinus des
-- halben Stueckwinkels tiefer; `overlap` verlaengert gegen Fugen.
function PitV2Rules.arcBlocks(arc: Arc, overlap: number): { Block }
	local step = (arc.to - arc.from) / arc.segments
	local half = math.rad(step * 0.5)
	local inner = arc.inner * math.cos(half)
	local mid = (inner + arc.outer) * 0.5
	local height = arc.top - arc.bottom
	local out: { Block } = {}
	for i = 1, arc.segments do
		local deg = arc.from + step * (i - 0.5)
		local a = math.rad(deg)
		table.insert(out, {
			x = mid * math.cos(a),
			y = mid * math.sin(a),
			h = arc.bottom + height * 0.5,
			angle = deg,
			radial = arc.outer - inner,
			height = height,
			length = 2 * arc.outer * math.sin(half) + overlap,
		})
	end
	return out
end

-- Ein quadratischer Block (Torpfeiler, Turm) ohne Drehung.
function PitV2Rules.block(box: Box): Block
	local height = box.top - box.bottom
	return { x = box.x, y = box.y, h = box.bottom + height * 0.5, angle = 0, radial = box.size, height = height, length = box.size }
end

-- Liegt der Grundriss-Punkt (x, y) im Block? (Tests: Gassen frei, Band dicht.)
function PitV2Rules.contains(b: Block, x: number, y: number): boolean
	local a = math.rad(b.angle)
	local dx, dy = x - b.x, y - b.y
	local along = dx * math.cos(a) + dy * math.sin(a)
	local across = -dx * math.sin(a) + dy * math.cos(a)
	return math.abs(along) <= b.radial * 0.5 and math.abs(across) <= b.length * 0.5
end

return PitV2Rules
