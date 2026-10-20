--!strict
-- EggLook.luau
-- ReplicatedStorage/Modules/EggLook.luau
--
-- Einzige Zustaendigkeit:
--   - Das AUSSEHEN eines Eis als reine Daten: Grundfarbe, Zweitfarbe, Muster,
--     Leuchten. Keine Instanzen, keine Spielregeln.
--
-- Server (gelegte Eier in der Welt, LaidEggBuilder) und Client (EggIcon im
-- UI) lesen dieselbe Beschreibung — ein Ei sieht im Eier-Fenster so aus wie
-- auf der Wiese. Aendert sich der Look eines Pfads, aendert er sich hier.
--
-- Die Grundfarbe bleibt `EggConfig.data[id].color`; hier kommt nur dazu,
-- WIE sie aufgetragen wird.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EggConfig = require(ReplicatedStorage.Config.EggConfig)

local EggLook = {}

export type Pattern = "spots" | "band" | "stripes" | "stars" | "swirl"

export type Look = {
	base    : Color3,
	accent  : Color3,    -- Farbe des Musters
	pattern : Pattern,
	glow    : boolean,   -- seltene Eier bekommen einen Schimmer
	neon    : boolean,   -- Muster leuchtet (Neon) statt matt
	tier    : number,
}

-- Muster je Pfad (EggConfig: Stamm, Gold, Kristall, Void, Kosmos, Ascension,
-- Event). Jedes Ei eines Pfads teilt Muster und Stimmung, unterscheidet sich
-- aber in der Grundfarbe — man erkennt Pfad UND Stufe auf einen Blick.
local PATH_PATTERN: { [string]: Pattern } = {
	Stamm     = "spots",
	Gold      = "band",
	Kristall  = "stripes",
	Void      = "swirl",
	Kosmos    = "stars",
	Ascension = "stars",
	Event     = "stars",
}

-- Feste Musterfarben, wo "heller oder dunkler als die Grundfarbe" nicht reicht.
local PATH_ACCENT: { [string]: Color3 } = {
	Void      = Color3.fromRGB(190, 120, 255),
	Ascension = Color3.fromRGB(255, 232, 140),
	Event     = Color3.fromRGB(255, 255, 255),
}

-- Ab dieser Stufe schimmert ein Ei (Sonne, Prisma, Schatten ... Omega).
local GLOW_FROM_TIER = 6

local DEFAULT_COLOR = Color3.fromRGB(238, 232, 214)

local function luminance(c: Color3): number
	return c.R * 0.299 + c.G * 0.587 + c.B * 0.114
end

-- Zweitfarbe: helle Eier bekommen ein dunkleres Muster, dunkle ein helleres.
local function deriveAccent(base: Color3, path: string): Color3
	local fixed = PATH_ACCENT[path]
	if fixed then return fixed end

	if path == "Gold" or path == "Kristall" then
		return base:Lerp(Color3.new(1, 1, 1), 0.65)
	end
	if luminance(base) > 0.62 then
		return base:Lerp(Color3.new(0, 0, 0), 0.28)
	end
	return base:Lerp(Color3.new(1, 1, 1), 0.5)
end

local _cache: { [string]: Look } = {}

function EggLook.get(eggId: string): Look
	local cached = _cache[eggId]
	if cached then return cached end

	local def = EggConfig.data[eggId]
	local base: Color3 = if def then def.color else DEFAULT_COLOR
	local path: string = if def then def.path else "Stamm"
	local tier: number = if def then def.tier else 1

	local look: Look = {
		base    = base,
		accent  = deriveAccent(base, path),
		pattern = PATH_PATTERN[path] or "spots",
		glow    = tier >= GLOW_FROM_TIER or path == "Ascension" or path == "Event",
		neon    = path == "Void" or path == "Kosmos" or path == "Ascension" or path == "Event",
		tier    = tier,
	}
	_cache[eggId] = look
	return look
end

return EggLook
