--!strict
-- PotionRules.luau
-- ReplicatedStorage/Modules/PotionRules.luau
--
-- Einzige Zustaendigkeit:
--   - Die Regeln der Traenke (26.10.) als reine Funktionen: laufende Effekte
--     je Sorte (anlegen, verlaengern, ersetzen, ablehnen, austragen), der
--     Multiplikator fuer die Spiel-Systeme, die Preisformel, das Glueck beim
--     Ei-Oeffnen und das Los fuer das wechselnde Sortiment des Haendlers.
--     Test: tools/luau-tests/potions.test.lua.
--
-- Bewusst ohne Roblox-Dienste, ohne FeatureFlags und ohne Random: der Test
-- laeuft ohne Attrappe, und das Sortiment ist aus dem Zeitfenster
-- reproduzierbar (gleiches Fenster = gleiches Los auf jedem Server). Der
-- Trank-Teil des Spielstands wird als `any` behandelt (wie ShopRules), damit
-- kaputte alte Eintraege nicht den Typpruefer, sondern die Migration beschaeftigen.
--
-- Wer den Schalter POTIONS_V1 prueft, ist der Aufrufer (Service); hier gilt:
-- kein Effekt = Faktor 1.

local PotionConfig = require(script.Parent.Parent.Config.PotionConfig)

local PotionRules = {}

export type Effect = { potionId: string, multiplier: number, expiresAt: number }
export type EffectView = { kind: string, potionId: string, multiplier: number, remaining: number }

-- Ergebnis von check(): was ein Kauf mit dem laufenden Effekt derselben Sorte macht
PotionRules.NEW     = "new"       -- nichts laeuft: neuer Effekt
PotionRules.EXTEND  = "extend"    -- gleicher Multiplikator: Zeit anhaengen
PotionRules.REPLACE = "replace"   -- staerker: ersetzt den laufenden
PotionRules.WEAKER  = "weaker"    -- schwaecher als der laufende: abgelehnt
PotionRules.MAXTIME = "maxtime"   -- Restzeit wuerde die Grenze sprengen: abgelehnt

local function orderOf(kind: string): number
	return table.find(PotionConfig.KINDS, kind :: any) or 99
end

--------------------------------------------------------------------------------
-- Zustand
--------------------------------------------------------------------------------

function PotionRules.newState(): any
	return { active = {}, bought = 0 }
end

-- Laufender Effekt einer Sorte oder nil (abgelaufene gelten als nicht da,
-- auch wenn prune noch nicht lief).
function PotionRules.get(state: any, kind: string, now: number): Effect?
	if typeof(state) ~= "table" or typeof(state.active) ~= "table" then return nil end
	local effect = state.active[kind]
	if typeof(effect) ~= "table" then return nil end
	if typeof(effect.expiresAt) ~= "number" or effect.expiresAt <= now then return nil end
	if typeof(effect.multiplier) ~= "number" then return nil end
	return effect
end

-- Faktor fuer die Spiel-Systeme. 1 = kein Trank (auch bei fehlendem Zustand).
function PotionRules.multiplier(state: any, kind: string, now: number): number
	local effect = PotionRules.get(state, kind, now)
	return if effect then math.max(1, effect.multiplier) else 1
end

function PotionRules.remaining(state: any, kind: string, now: number): number
	local effect = PotionRules.get(state, kind, now)
	return if effect then math.max(0, effect.expiresAt - now) else 0
end

-- Abgelaufene Effekte austragen. Gibt die Sorten zurueck, die weggefallen sind.
function PotionRules.prune(state: any, now: number): { string }
	local removed: { string } = {}
	if typeof(state) ~= "table" or typeof(state.active) ~= "table" then return removed end
	for kind, effect in state.active do
		if typeof(effect) ~= "table" or typeof(effect.expiresAt) ~= "number" or effect.expiresAt <= now then
			state.active[kind] = nil
			table.insert(removed, kind)
		end
	end
	table.sort(removed, function(a, b) return orderOf(a) < orderOf(b) end)
	return removed
end

-- Was ein Kauf dieses Tranks bewirken wuerde (siehe Konstanten oben).
-- `maxRemaining` = PotionConfig.MAX_REMAINING_SECONDS (als Parameter, damit
-- der Test die Grenze setzen kann).
function PotionRules.check(state: any, def: PotionConfig.PotionDef, now: number, maxRemaining: number): string
	local active = PotionRules.get(state, def.kind, now)
	if not active then
		return if def.durationSeconds > maxRemaining then PotionRules.MAXTIME else PotionRules.NEW
	end
	if def.multiplier > active.multiplier then
		return if def.durationSeconds > maxRemaining then PotionRules.MAXTIME else PotionRules.REPLACE
	end
	if def.multiplier < active.multiplier then
		return PotionRules.WEAKER
	end
	local remaining = active.expiresAt - now
	if remaining + def.durationSeconds > maxRemaining then
		return PotionRules.MAXTIME
	end
	return PotionRules.EXTEND
end

-- Trank anwenden. false = abgelehnt (Grund = check-Ergebnis), nichts geaendert.
-- Der Aufrufer bucht den Preis erst NACH einem true ab? Nein — umgekehrt:
-- erst check, dann bezahlen, dann apply (apply kann dann nicht mehr scheitern).
function PotionRules.apply(state: any, def: PotionConfig.PotionDef, now: number, maxRemaining: number): (boolean, string, Effect?)
	local outcome = PotionRules.check(state, def, now, maxRemaining)
	if outcome == PotionRules.WEAKER or outcome == PotionRules.MAXTIME then
		return false, outcome, nil
	end
	if typeof(state.active) ~= "table" then state.active = {} end

	local effect: Effect
	if outcome == PotionRules.EXTEND then
		local active = state.active[def.kind]
		effect = { potionId = def.id, multiplier = active.multiplier, expiresAt = active.expiresAt + def.durationSeconds }
	else
		effect = { potionId = def.id, multiplier = def.multiplier, expiresAt = now + def.durationSeconds }
	end
	state.active[def.kind] = effect
	state.bought = (tonumber(state.bought) or 0) + 1
	return true, outcome, effect
end

-- Sicht fuer den Client (PlayerDataUpdate.potions): nur laufende Effekte,
-- in der Reihenfolge von PotionConfig.KINDS, mit Restzeit statt Zeitpunkt
-- (die Uhr des Clients ist nicht die des Servers).
function PotionRules.view(state: any, now: number): { EffectView }
	local list: { EffectView } = {}
	for _, kind in PotionConfig.KINDS do
		local effect = PotionRules.get(state, kind, now)
		if effect then
			table.insert(list, {
				kind       = kind,
				potionId   = effect.potionId,
				multiplier = effect.multiplier,
				remaining  = effect.expiresAt - now,
			})
		end
	end
	return list
end

--------------------------------------------------------------------------------
-- Preis
--------------------------------------------------------------------------------

-- `reference` = Pfotenmuenzen je Stage auf der besten Stage dieses Lebens,
-- schon mal rebirthMult (PotionService.priceReference). Nie unter minPrice.
function PotionRules.price(def: PotionConfig.PotionDef, reference: number): number
	local scaled = math.floor(def.stagePrice * math.max(0, reference))
	return math.max(def.minPrice, scaled)
end

--------------------------------------------------------------------------------
-- Glueck beim Ei-Oeffnen
--------------------------------------------------------------------------------

-- Neue Gewichtsliste: der haeufigste Eintrag (hoechstes Gewicht, bei
-- Gleichstand der erste) bleibt, alle anderen bekommen das `multiplier`-fache.
-- Dieselbe Idee wie EggCalculator.luckWeights beim Inkubator. Die Eingabe
-- wird nicht veraendert.
function PotionRules.applyLuck<T>(entries: { T }, multiplier: number): { T }
	if multiplier <= 1 or #entries <= 1 then return entries end
	local topIndex, topWeight = 1, -math.huge
	for index, entry in entries do
		local weight = (entry :: any).weight
		if typeof(weight) == "number" and weight > topWeight then
			topIndex, topWeight = index, weight
		end
	end
	local out: { T } = {}
	for index, entry in entries do
		local copy = table.clone(entry :: any)
		if index ~= topIndex and typeof(copy.weight) == "number" and copy.weight > 0 then
			copy.weight *= multiplier
		end
		out[index] = copy :: any
	end
	return out
end

--------------------------------------------------------------------------------
-- Sortiment des Haendlers
--------------------------------------------------------------------------------

function PotionRules.windowOf(now: number, rotateSeconds: number): number
	return math.floor(now / rotateSeconds)
end

function PotionRules.secondsUntilRotation(now: number, rotateSeconds: number): number
	return rotateSeconds - (now % rotateSeconds)
end

-- Kleiner, exakter Zufallsgenerator (Park-Miller, 31 Bit) auf doubles: alle
-- Zwischenwerte bleiben unter 2^53. Kein Random.new, damit der Test ohne
-- Roblox laeuft und jeder Server zum selben Fenster dasselbe Los zieht.
local M = 2147483647
local A = 48271

local function seedFrom(window: number): number
	local seed = (math.floor(window) * 2654435761 + 97) % M
	return if seed <= 0 then 1 else seed
end

local function nextRand(seed: number): number
	return (seed * A) % M
end

-- Zieht `min..max` verschiedene Traenke aus dem Pool, gewichtet (weight),
-- deterministisch zum Fenster. Reihenfolge = Ziehreihenfolge. Pool leer = {}.
function PotionRules.rollAssortment(window: number, pool: { PotionConfig.PotionDef }, minSlots: number, maxSlots: number): { string }
	local picked: { string } = {}
	if #pool == 0 then return picked end
	local lo = math.max(0, math.floor(minSlots))
	local hi = math.max(lo, math.floor(maxSlots))
	hi = math.min(hi, #pool)
	lo = math.min(lo, hi)

	local seed = seedFrom(window)
	seed = nextRand(seed)
	local slots = lo + (seed % (hi - lo + 1))

	local remaining = table.clone(pool)
	for _ = 1, slots do
		local total = 0
		for _, def in remaining do total += math.max(0, def.weight) end
		if total <= 0 then break end
		seed = nextRand(seed)
		local roll = (seed / M) * total
		local chosen = #remaining
		local cumulative = 0
		for index, def in remaining do
			cumulative += math.max(0, def.weight)
			if roll < cumulative then
				chosen = index
				break
			end
		end
		table.insert(picked, remaining[chosen].id)
		table.remove(remaining, chosen)
	end
	return picked
end

return PotionRules
