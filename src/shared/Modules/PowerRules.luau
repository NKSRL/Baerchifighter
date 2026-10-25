--!strict
-- PowerRules.luau
-- ReplicatedStorage/Modules/PowerRules.luau
--
-- Welt 1, Paket 5b: reine, getestete Funktionen des Staerke-Modells V2.
--   * roll(uid, rarityIndex)      deterministischer Wurf aus der uid (keine Migration, kein neues Feld)
--   * applyV2(base, rarityIndex, uid) normalisiert die Basiswerte auf die Rarity-Basis und wendet den Wurf an
--   * grade(quality)              Text-Schluessel fuer die Anzeige
-- Server und Client rechnen identisch. Test: tools/luau-tests/power_rules.test.lua

local Cfg = require(script.Parent.Parent.Config.PowerConfig)

local PowerRules = {}

export type Roll = {
	total   : number,   -- Gesamtstaerke T (Faktor auf g = sqrt(hp * atk))
	hp      : number,
	atk     : number,
	spd     : number,
	pwr     : number,
	quality : number,   -- 0..1 innerhalb der Spanne der Rarity
	grade   : string,   -- Schluessel aus PowerConfig.GRADES
}

-- 32-Bit-Multiplikation ohne Praezisionsverlust (Doubles tragen nur 53 Bit).
local function mul32(a: number, b: number): number
	local hi = bit32.rshift(a, 16)
	local lo = bit32.band(a, 0xFFFF)
	return bit32.band(bit32.lshift(bit32.band(hi * b, 0xFFFF), 16) + lo * b, 0xFFFFFFFF)
end

-- FNV-1a (32 Bit) ueber die uid, mit Salz; liefert 0..1.
local function hash01(text: string, salt: number): number
	local h = bit32.band(2166136261 + salt * 40503, 0xFFFFFFFF)
	for i = 1, #text do
		h = mul32(bit32.bxor(h, string.byte(text, i)), 16777619)
	end
	h = bit32.bxor(h, bit32.rshift(h, 15))
	h = mul32(h, 2246822519)
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = mul32(h, 3266489917)
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h / 4294967296
end

-- Zeitstempel aus der uid ("b_<zeit>_<zaehler>_<zufall>"); nil, wenn nicht lesbar.
function PowerRules.uidTime(uid: string): number?
	local t = string.match(uid, "^b_(%d+)_")
	return if t then tonumber(t) else nil
end

function PowerRules.range(rankIndex: number): (number, number)
	local lo = 1 - Cfg.SPREAD + Cfg.FLOOR_PER_RARITY * rankIndex
	local hi = 1 + Cfg.SPREAD_UP
	lo = math.min(lo, hi - 0.05)
	return lo, hi
end

function PowerRules.grade(quality: number): string
	for _, g in Cfg.GRADES do
		if quality <= g.max then return g.key end
	end
	return Cfg.GRADES[#Cfg.GRADES].key
end

-- rankIndex: 0 = Common ... 11 = Omega.
function PowerRules.rollWith(uid: string, rankIndex: number, cutoff: number): Roll
	local lo, hi = PowerRules.range(rankIndex)
	local u1, u2, u3 = hash01(uid, 1), hash01(uid, 2), hash01(uid, 3)
	local total = lo + (hi - lo) * math.pow(u1, Cfg.SHAPE)
	if cutoff > 0 then
		local t = PowerRules.uidTime(uid)
		if t ~= nil and t < cutoff then total = math.max(total, 1.0) end   -- Bestandsschutz
	end
	local w = (u2 * 2 - 1) * Cfg.SKEW
	local quality = math.clamp(math.pow(math.clamp((total - lo) / (hi - lo), 0, 1), 1 / Cfg.SHAPE), 0, 1)   -- Perzentil
	return {
		total = total,
		hp    = math.pow(total, 1 + w),
		atk   = math.pow(total, 1 - w),
		spd   = 1 + (total - 1) * Cfg.SPD_FOLLOW,
		pwr   = (1 + (total - 1) * Cfg.PWR_FOLLOW) * (1 + (u3 * 2 - 1) * Cfg.SKILL_SPREAD),
		quality = quality,
		grade = PowerRules.grade(quality),
	}
end

function PowerRules.roll(uid: string, rankIndex: number): Roll
	return PowerRules.rollWith(uid, rankIndex, Cfg.LEGACY_CUTOFF_TIME)
end

-- Rarity-Basis g(k) = G_REF * (1 + p)^k.
function PowerRules.baseG(rankIndex: number): number
	return Cfg.G_REF * math.pow(1 + Cfg.POWER_PER_RARITY, rankIndex)
end

export type Base = { hp: number, atk: number, spd: number, pwr: number }

-- Basiswerte (alt: pro Pet fest) -> V2: HP/ATK-Verhaeltnis (Tank/Glaskanone) bleibt, die Gesamtstaerke kommt aus
-- Rarity-Basis * Wurf. SPD/PWR bleiben pro Pet, mit kleinem Wurf-Einfluss.
function PowerRules.applyV2(base: Base, rankIndex: number, uid: string): Base
	local g = math.sqrt(math.max(base.hp, 1) * math.max(base.atk, 1))
	local gt = PowerRules.baseG(rankIndex)
	local r = PowerRules.roll(uid, rankIndex)
	return {
		hp  = (base.hp  / g) * gt * r.hp,
		atk = (base.atk / g) * gt * r.atk,
		spd = base.spd * r.spd,
		pwr = base.pwr * r.pwr,
	}
end

-- Anzeige: 0..5 Punkte je Wert (Wurf-Faktor 0,75 .. 1,25 auf 0..5 abgebildet).
function PowerRules.dots(factor: number): number
	return math.clamp(math.floor((factor - 0.75) / 0.5 * 5 + 0.5), 0, 5)
end

-- "HP ●●●○○  ATK ●●○○○ ..." — rein darstellend, keine Lokalisierung noetig (Kuerzel wie auf der Karte).
function PowerRules.meterText(r: Roll): string
	local function bar(label: string, factor: number): string
		local n = PowerRules.dots(factor)
		return label .. " " .. string.rep("●", n) .. string.rep("○", 5 - n)
	end
	return bar("HP", r.hp) .. "  " .. bar("ATK", r.atk) .. "  " .. bar("SPD", r.spd) .. "  " .. bar("PWR", r.pwr)
end

return PowerRules
