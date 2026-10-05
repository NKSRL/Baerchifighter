--!strict
-- UnlockRules.luau
-- ReplicatedStorage/Modules/UnlockRules.luau
--
-- Einzige Zustaendigkeit:
--   - Aus dem Spielstand ableiten, welche Bedienelemente ein Spieler schon
--     sieht (reine Funktion, keine Roblox-Dienste)
--
-- Kontext: HBB Paket 3 (progressive Freischaltung). Die erste Sitzung zeigt
-- eine Waehrung, zwei Kacheln (Eier, Baerchis) und den Fight-Knopf; alles
-- andere kommt, wenn der Spieler es braucht.
--
-- Die Freischaltung ist REIN KOSMETISCH. Der Server sperrt nichts; wer ein
-- Panel auf anderem Weg erreicht, darf es benutzen. Kein Spielstand-Wert
-- haengt an dieser Tabelle.
--
-- Jede Regel ist MONOTON: einmal frei, immer frei. Wo die Datenquelle das
-- nicht ist (Waehrung, Anzahl Baerchis), steht ein monotoner Ersatz (Zaehler
-- in stats) — und zusaetzlich gilt ein Element als frei, sobald es in
-- `uiSeen` steht (Latch, gesetzt von UiStateService).
--
-- Keine requires: laeuft unveraendert im Luau-Test
-- (tools/luau-tests/unlock_rules.test.lua).

export type View = {
	rebirthCount : number,
	goldGummies  : number,
	island : {
		baerchis      : { [string]: any },
		towerProgress : { [string]: number }?,
	},
	towers     : { records: { [string]: number } }?,
	discovered : { [string]: boolean }?,
	eggTree    : { unlocked: { [string]: boolean } }?,
	stats      : { [string]: number }?,
	uiSeen     : { [string]: boolean }?,
}

local UnlockRules = {}

-- Alle Element-IDs. Zugleich die Whitelist fuer RequestMarkUiSeen.
UnlockRules.ELEMENTS = {
	"pill_gummies", "tile_eggs", "tile_bears", "button_fight",
	"button_event", "tile_leaderboard", "tile_daily", "pill_gold",
	"tile_tree", "tab_upgrade", "charms", "recycling",
	"pill_rank", "pill_rebirth", "index", "tile_shop",
}

-- Schwellen (Default-Annahmen aus dem Plan, im Bericht benannt)
UnlockRules.TREE_HATCHED       = 10
UnlockRules.UPGRADE_HATCHED    = 2
UnlockRules.CHARMS_TOWER_I     = 15
UnlockRules.RECYCLE_HATCHED    = 21   -- "mehr als 20 Baerchis" (monotoner Ersatz)
UnlockRules.INDEX_DISCOVERED   = 3
-- Paket 10: Shop ab der zweiten Sitzung (stats.sessions, PlayerService zaehlt).
-- SHOP_ENABLED spiegelt FeatureFlags.SHOP_V1: dieses Modul hat bewusst keine
-- requires (laeuft im reinen Luau-Test), deshalb setzen ShopService (Server)
-- und ShopPanel (Client) den Wert beim Start.
UnlockRules.SHOP_ENABLED       = false
UnlockRules.SHOP_SESSIONS      = 2

local ALWAYS: { [string]: boolean } = {
	pill_gummies = true, tile_eggs = true, tile_bears = true, button_fight = true,
}
UnlockRules.ALWAYS = ALWAYS

local function count(map: { [any]: any }?): number
	local n = 0
	if map then
		for _ in map do n += 1 end
	end
	return n
end

local function stat(view: View, key: string): number
	local stats = view.stats
	return if stats then (stats[key] or 0) else 0
end

-- Erster beendeter Kampf: Rekord in irgendeinem Tower, gespeicherter
-- letzter Lauf, oder ein Kampf-Zaehler.
function UnlockRules.hasFought(view: View): boolean
	local towers = view.towers
	if towers and next(towers.records) ~= nil then return true end
	local progress = view.island.towerProgress
	if progress and next(progress) ~= nil then return true end
	return stat(view, "totalFightsWon") + stat(view, "totalFightsLost") > 0
end

-- Bedingung ohne Latch
local function condition(view: View, id: string): boolean
	if ALWAYS[id] then return true end
	local fought = UnlockRules.hasFought(view)
	local hatched = stat(view, "totalHatched")
	local rebirths = view.rebirthCount or 0

	if id == "button_event" or id == "tile_leaderboard" or id == "tile_daily" then
		return fought or rebirths > 0
	elseif id == "pill_gold" then
		return (view.goldGummies or 0) > 0
	elseif id == "tile_tree" then
		-- Start-Knoten sind BasicEgg und SugarEgg; mehr = erstes EggTreeUnlocked
		local unlocked = if view.eggTree then count(view.eggTree.unlocked) else 0
		return hatched >= UnlockRules.TREE_HATCHED or unlocked > 2 or rebirths > 0
	elseif id == "tab_upgrade" then
		return hatched >= UnlockRules.UPGRADE_HATCHED or rebirths > 0
	elseif id == "charms" then
		local towers = view.towers
		local recordI = if towers then (towers.records.I or 0) else 0
		return rebirths >= 1 or recordI >= UnlockRules.CHARMS_TOWER_I
	elseif id == "recycling" then
		return hatched >= UnlockRules.RECYCLE_HATCHED or rebirths > 0
	elseif id == "pill_rank" or id == "pill_rebirth" then
		return rebirths >= 1
	elseif id == "index" then
		return count(view.discovered) >= UnlockRules.INDEX_DISCOVERED
	elseif id == "tile_shop" then
		local stats = view.stats
		local sessions = if stats then (stats.sessions or 0) else 0
		return UnlockRules.SHOP_ENABLED and sessions >= UnlockRules.SHOP_SESSIONS
	end
	return false
end

function UnlockRules.isVisible(view: View, id: string): boolean
	local seen = view.uiSeen
	if seen and seen[id] then return true end
	return condition(view, id)
end

-- { [elementId] = sichtbar }
function UnlockRules.visible(view: View): { [string]: boolean }
	local result: { [string]: boolean } = {}
	for _, id in UnlockRules.ELEMENTS do
		result[id] = UnlockRules.isVisible(view, id)
	end
	return result
end

-- Hat der Spielstand schon Fortschritt? (Veteranen bekommen beim ersten
-- Laden alles Sichtbare als "gesehen", damit keine Badge-Flut entsteht.)
function UnlockRules.hasProgress(view: View): boolean
	return stat(view, "totalHatched") > 0 or (view.rebirthCount or 0) > 0 or UnlockRules.hasFought(view)
end

return UnlockRules
