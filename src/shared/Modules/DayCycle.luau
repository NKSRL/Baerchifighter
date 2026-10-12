--!strict
-- DayCycle.luau
-- ReplicatedStorage/Modules/DayCycle.luau
--
-- Einzige Zustaendigkeit:
--   - Tageszeit und Licht-Werte des Tageslaufs als REINE Funktion der
--     Serverzeit (Paket A, "Welt aufwerten")
--
-- Wie Modules/EventMotion: kein Zustand, keine Instanzen. Der Client
-- (DayCycleController) fragt mit workspace:GetServerTimeNow() und setzt das
-- Ergebnis; zwei Clients bekommen fuer dieselbe Serverzeit genau dieselben
-- Zahlen. Testbar ohne Roblox (tools/luau-tests/day_cycle.test.lua).

local Config = script.Parent.Parent.Config
local WorldFXConfig = require(Config.WorldFXConfig)

local DayCycle = {}

local TAU = math.pi * 2

export type Curve = { { any } }

-- Uhrzeit zur Serverzeit `now`: Kosinus-Pendel CLOCK_MIN → CLOCK_MAX → CLOCK_MIN.
-- Bei now = 0 (und jedem Vielfachen der Periode) steht sie auf CLOCK_MIN.
function DayCycle.clockAt(now: number): number
	local cfg = WorldFXConfig.DAY
	local phase = (now % cfg.PERIOD) / cfg.PERIOD
	local k = (1 - math.cos(TAU * phase)) * 0.5
	return cfg.CLOCK_MIN + (cfg.CLOCK_MAX - cfg.CLOCK_MIN) * k
end

-- "Daemmerung" 0..1 zu einer Uhrzeit (0 = goldener Nachmittag, 1 = blaue Stunde).
function DayCycle.duskOf(clock: number): number
	local cfg = WorldFXConfig.DAY
	return math.clamp((clock - cfg.CLOCK_MIN) / (cfg.CLOCK_MAX - cfg.CLOCK_MIN), 0, 1)
end

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

local function lerpValue(a: any, b: any, t: number): any
	if typeof(a) == "number" then
		return a + (b - a) * t
	end
	-- Color3 (die einzige andere Art in den Kurven)
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

-- Wert einer Kurve bei `d`. Zwischen zwei Stuetzpunkten weich (smoothstep):
-- die Steigung ist an jedem Stuetzpunkt null, es gibt also keinen Knick.
function DayCycle.sample(curve: Curve, d: number): any
	local first = curve[1]
	if d <= first[1] then
		return first[2]
	end
	for i = 2, #curve do
		local b = curve[i]
		if d <= b[1] then
			local a = curve[i - 1]
			local span = b[1] - a[1]
			local t = if span > 0 then (d - a[1]) / span else 1
			return lerpValue(a[2], b[2], smooth(t))
		end
	end
	return curve[#curve][2]
end

-- Alle Kurven bei `d` in einer Tabelle (Schluessel wie WorldFXConfig.DAY_CURVES).
function DayCycle.valuesAt(d: number): { [string]: any }
	local out = {}
	for name, curve in WorldFXConfig.DAY_CURVES :: any do
		out[name] = DayCycle.sample(curve, d)
	end
	return out
end

-- Mischt zwei Wertetabellen (fuer den weichen Rueckweg nach einer Show).
function DayCycle.blend(a: { [string]: any }, b: { [string]: any }, t: number): { [string]: any }
	local out = {}
	for name, value in b do
		local from = a[name]
		out[name] = if from ~= nil then lerpValue(from, value, t) else value
	end
	return out
end

return DayCycle
