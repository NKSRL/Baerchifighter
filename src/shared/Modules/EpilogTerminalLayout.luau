--!strict
-- EpilogTerminalLayout.luau
-- ReplicatedStorage/Modules/EpilogTerminalLayout.luau
--
-- Einzige Zustaendigkeit:
--   - Die Geometrie des Start-Terminals (Prompt 4, Final-Epilog) als reine
--     Rechnung im LOKALEN System des Terminals: welche Teile wo stehen. Keine
--     Roblox-Instanzen — damit tools/luau-tests/epilog_terminal.test.lua Teilezahl,
--     Palette, Masse und Kollision pruefen kann. EpilogTerminalBuilder baut daraus
--     die Teile (Lage = Mount-CFrame * lokale Lage).
--
-- Lokales System (Vertrag): Ursprung Mitte Sockelunterseite, +Y oben, Vorderseite
-- -Z (der Spieler kommt aus -Z). Masse aus EpilogConfig.TERMINAL.
--
-- Teil-Arten: "Block" (size = {x, y, z}), "Disc" (liegend, size = {Dicke, Durchmesser};
-- Achse = lokales Y), "Ball" (size = {Durchmesser}). `rot` = Euler (rx, ry, rz) in
-- Bogenmass, angewandt als CFrame.Angles(rx, ry, rz) vor der Scheiben-Kippung.
--
-- Benennung: Epilog_Terminal_<Teil>.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EpilogConfig = require(ReplicatedStorage.Config.EpilogConfig)

local Layout = {}

export type Piece = {
	name         : string,
	kind         : string,        -- "Block" | "Disc" | "Ball"
	size         : { number },
	pos          : { number },    -- Mitte, lokal
	rot          : { number },    -- rx, ry, rz
	colorKey     : string,        -- Schluessel in TERMINAL.colors
	material     : string,        -- Enum.Material-Name
	collide      : boolean,
	transparency : number,
	hidden       : boolean,       -- unsichtbar (Ausloeser)
}

export type Result = {
	pieces     : { Piece },
	hinge      : { pos : { number }, rx : number },   -- Scharnier der Klappe (Drehachse = lokale X-Achse)
	lampNames  : { string },
	buttonTop  : { number },                          -- Mitte der Knopffläche, lokal
	count      : number,
	width      : number,
}

local PREFIX = "Epilog_Terminal_"

function Layout.compute(): Result
	local T = EpilogConfig.TERMINAL
	local pieces: { Piece } = {}
	local function add(p: Piece) table.insert(pieces, p) end

	local tilt = math.rad(T.tiltDeg)
	local cosT, sinT = math.cos(tilt), math.sin(tilt)
	local W = T.width

	-- Sockel und Korpus
	add({ name = PREFIX .. "Sockel", kind = "Block", size = { W + 0.6, 0.5, 4.8 }, pos = { 0, 0.25, 0.1 },
		rot = { 0, 0, 0 }, colorKey = "metal", material = "Metal", collide = true, transparency = 0, hidden = false })
	add({ name = PREFIX .. "Korpus", kind = "Block", size = { W, 1.25, 3.8 }, pos = { 0, 1.125, 0.3 },
		rot = { 0, 0, 0 }, colorKey = "concrete", material = "Concrete", collide = true, transparency = 0, hidden = false })

	-- Schraege Konsole (Vorderkante tiefer). Platten-Koordinaten (u, n, v):
	-- u = nach rechts, n = Normale (nach oben-vorn), v = Richtung "hinten/oben"
	local plateCenter = { 0, 2.15, -0.1 }
	local plateRx = -tilt
	local function onPlate(u: number, n: number, v: number): { number }
		return {
			plateCenter[1] + u,
			plateCenter[2] + n * cosT + v * sinT,
			plateCenter[3] - n * sinT + v * cosT,
		}
	end
	add({ name = PREFIX .. "Konsole", kind = "Block", size = { W, 0.35, 4.0 }, pos = plateCenter,
		rot = { plateRx, 0, 0 }, colorKey = "concrete", material = "Metal", collide = true, transparency = 0, hidden = false })

	-- Bildschirm hinten auf der Konsole (SurfaceGui kommt vom Client, Flaeche = oben)
	add({ name = PREFIX .. "Bildschirm", kind = "Block", size = { 3.4, 0.12, 0.8 }, pos = onPlate(0, 0.22, 1.15),
		rot = { plateRx, 0, 0 }, colorKey = "screen", material = "SmoothPlastic", collide = false, transparency = 0, hidden = false })

	-- Drei Statuslampen hinter dem Bildschirm
	local lampNames: { string } = {}
	for i = 1, T.lampCount do
		local name = PREFIX .. "Lampe" .. i
		table.insert(lampNames, name)
		add({ name = name, kind = "Ball", size = { T.lampDiam }, pos = onPlate((i - (T.lampCount + 1) / 2) * 0.9, 0.3, 1.78),
			rot = { 0, 0, 0 }, colorKey = "lampOff", material = "Neon", collide = false, transparency = 0, hidden = false })
	end

	-- Knopf: Goldring, Gehaeuse, Knopf (alles auf der Konsole, zur Vorderseite hin)
	local buttonV = -0.55
	add({ name = PREFIX .. "Ring", kind = "Disc", size = { 0.12, T.ringDiam }, pos = onPlate(0, 0.2, buttonV),
		rot = { plateRx, 0, 0 }, colorKey = "gold", material = "Metal", collide = false, transparency = 0, hidden = false })
	add({ name = PREFIX .. "KnopfBasis", kind = "Disc", size = { T.baseHeight, T.baseDiam },
		pos = onPlate(0, 0.175 + T.baseHeight / 2, buttonV),
		rot = { plateRx, 0, 0 }, colorKey = "metal", material = "Metal", collide = false, transparency = 0, hidden = false })
	local knobN = 0.175 + T.baseHeight + T.buttonHeight / 2 - 0.05
	add({ name = PREFIX .. "Knopf", kind = "Disc", size = { T.buttonHeight, T.buttonDiam }, pos = onPlate(0, knobN, buttonV),
		rot = { plateRx, 0, 0 }, colorKey = "red", material = "Neon", collide = false, transparency = 0, hidden = false })

	-- Klappe: transparent rot, schwebt ueber dem Knopf, Scharnier am hinteren Rand
	local lidN = 0.175 + T.baseHeight + T.buttonHeight + T.lidGap
	local hingeV = buttonV + T.baseDiam / 2              -- hinterer Rand des Gehaeuses
	local hingePos = onPlate(0, lidN, hingeV)
	add({ name = PREFIX .. "Klappe", kind = "Block", size = { T.lidSize[1], T.lidSize[2], T.lidSize[3] },
		pos = onPlate(0, lidN + T.lidSize[2] / 2, hingeV - T.lidSize[3] / 2),
		rot = { plateRx, 0, 0 }, colorKey = "lid", material = "Glass", collide = false, transparency = 0.45, hidden = false })

	-- Goldleiste an der Vorderkante der Konsole
	add({ name = PREFIX .. "Leiste", kind = "Block", size = { W, 0.12, 0.14 }, pos = onPlate(0, 0.24, -1.95),
		rot = { plateRx, 0, 0 }, colorKey = "gold", material = "Metal", collide = false, transparency = 0, hidden = false })

	-- Antenne hinten rechts, Spitze und Kabel dorthin
	add({ name = PREFIX .. "Antenne", kind = "Block", size = { 0.2, 3.2, 0.2 }, pos = { W / 2 - 0.5, 1.75 + 1.6, 1.9 },
		rot = { 0, 0, 0 }, colorKey = "metal", material = "Metal", collide = false, transparency = 0, hidden = false })
	add({ name = PREFIX .. "Spitze", kind = "Ball", size = { 0.45 }, pos = { W / 2 - 0.5, 1.75 + 3.2 + 0.1, 1.9 },
		rot = { 0, 0, 0 }, colorKey = "red", material = "Neon", collide = false, transparency = 0, hidden = false })
	add({ name = PREFIX .. "Kabel", kind = "Block", size = { 2.6, 0.12, 0.12 }, pos = { W / 2 - 0.5 - 1.3, 1.81, 2.05 },
		rot = { 0, 0, 0 }, colorKey = "cable", material = "SmoothPlastic", collide = false, transparency = 0, hidden = false })

	-- Warnstreifen am Sockel (vorn): gelbes Band mit vier schwarzen Schraegstreifen
	local frontZ = 0.1 - 2.4 - 0.05
	add({ name = PREFIX .. "Warn_Gelb", kind = "Block", size = { W + 0.4, 0.34, 0.1 }, pos = { 0, 0.25, frontZ },
		rot = { 0, 0, 0 }, colorKey = "yellow", material = "SmoothPlastic", collide = false, transparency = 0, hidden = false })
	for i = 1, 4 do
		add({ name = PREFIX .. "Warn_" .. i, kind = "Block", size = { 0.34, 0.5, 0.12 },
			pos = { (i - 2.5) * 1.15, 0.25, frontZ - 0.01 }, rot = { 0, 0, math.rad(35) },
			colorKey = "black", material = "SmoothPlastic", collide = false, transparency = 0, hidden = false })
	end

	-- Ausloeser: unsichtbare Touch-Flaeche (>= 64 Quadrat-Studs) vor dem Terminal, haelt den Prompt
	local hit = T.prompt.hitArea
	add({ name = PREFIX .. "Ausloeser", kind = "Block", size = { hit, 0.4, hit }, pos = { 0, 0.2, -2.4 - hit / 2 + 1.2 },
		rot = { 0, 0, 0 }, colorKey = "metal", material = "SmoothPlastic", collide = false, transparency = 1, hidden = true })

	local btn = onPlate(0, 0.175 + T.baseHeight + T.buttonHeight, buttonV)
	return {
		pieces = pieces, hinge = { pos = hingePos, rx = plateRx }, lampNames = lampNames,
		buttonTop = btn, count = #pieces, width = W,
	}
end

return Layout
