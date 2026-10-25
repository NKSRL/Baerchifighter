--!strict
-- BadgeRules.luau
-- ReplicatedStorage/Modules/BadgeRules.luau
--
-- Einzige Zustaendigkeit:
--   - Reine Regeln des Rang-Billboards (Paket 3): aus Spielstand-Werten die Anzeige-Daten ableiten,
--     den Text-Schluessel je Tower waehlen und die Ausblend-Staerke nach Entfernung berechnen.
--
-- Keine Instanzen, kein Speichern. Test: tools/luau-tests/badge_rules.test.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BadgeConfig = require(ReplicatedStorage.Config.BadgeConfig)
local TowerConfig = require(ReplicatedStorage.Config.TowerConfig)

export type Info = {
	towerId : string,   -- "" = Neuling (noch kein Rekord)
	record  : number,
	rebirth : number,
}

local BadgeRules = {}

-- Anzeige-Daten aus Tower-Rekorden und Rebirth-Zahl. Kein Rekord > 0 -> Neuling.
function BadgeRules.info(towers: any, rebirthCount: number?): Info
	local towerId, record = TowerConfig.bestRecord(towers)
	if record <= 0 then towerId = "" end
	return { towerId = towerId, record = math.max(record, 0), rebirth = math.max(math.floor(rebirthCount or 0), 0) }
end

-- Aus den Spieler-Attributen (Client): fehlende/falsche Werte werden zu "Neuling, R0".
function BadgeRules.fromAttributes(tower: any, record: any, rebirth: any): Info
	local id = if typeof(tower) == "string" and TowerConfig.isValidId(tower) then tower else ""
	local rec = if typeof(record) == "number" then math.max(math.floor(record), 0) else 0
	if rec <= 0 then id = "" end
	return { towerId = id, record = rec, rebirth = if typeof(rebirth) == "number" then math.max(math.floor(rebirth), 0) else 0 }
end

-- Text-Schluessel und Argumente der Plakette: I/II/III -> "Tower {n} . {stage}", Final, Endless, sonst Neuling.
function BadgeRules.plaque(info: Info): (string, { [string]: any }?)
	local T = BadgeConfig.TEXT
	if info.towerId == "" then return T.rookie, nil end
	local def = TowerConfig.get(info.towerId)
	if not def then return T.rookie, nil end
	if def.id == "Final" then return T.final, { stage = info.record } end
	if def.id == "Endless" then return T.endless, { stage = info.record } end
	return T.tower, { tower = def.numeral, stage = info.record }
end

-- Rebirth-Teil nur zeigen, wenn es einen gibt ("R0" wird nie angezeigt).
function BadgeRules.showRebirth(info: Info): boolean
	return info.rebirth > 0
end

-- Deckkraft 1..0 nach Entfernung: voll bis FADE_START, dann linear bis MAX_DISTANCE.
function BadgeRules.alphaAt(distance: number): number
	local from, to = BadgeConfig.FADE_START, BadgeConfig.MAX_DISTANCE
	if distance <= from then return 1 end
	if distance >= to then return 0 end
	return 1 - (distance - from) / (to - from)
end

-- Die `maxVisible` naechsten Eintraege (Entfernung <= MAX_DISTANCE); gibt die Schluessel zurueck.
function BadgeRules.pickVisible(distances: { [any]: number }, maxVisible: number): { [any]: boolean }
	local list: { { key: any, d: number } } = {}
	for key, d in distances do
		if d <= BadgeConfig.MAX_DISTANCE then table.insert(list, { key = key, d = d }) end
	end
	table.sort(list, function(a, b) return a.d < b.d end)
	local out: { [any]: boolean } = {}
	for i = 1, math.min(maxVisible, #list) do out[list[i].key] = true end
	return out
end

return BadgeRules
