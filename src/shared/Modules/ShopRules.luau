--!strict
-- ShopRules.luau
-- ReplicatedStorage/Modules/ShopRules.luau
--
-- Einzige Zustaendigkeit:
--   - Die Regeln des Shops (HBB Paket 10) als reine Funktionen auf dem
--     Shop-Teil des Spielstands: Gratis-Griff pro UTC-Tag und das Merken von
--     Robux-Kaeufen (jeder Kauf zahlt genau einmal aus).
--     Test: tools/luau-tests/shop.test.lua. ShopService ruft nur diese auf.
--
-- Bewusst ohne Roblox-Dienste und ohne Types (Shop-Teil als any), damit der
-- Test ohne Attrappe laeuft.

local ShopRules = {}

local SECONDS_PER_DAY = 86400

function ShopRules.dayOf(unixTime: number): number
	return math.floor(unixTime / SECONDS_PER_DAY)
end

function ShopRules.secondsUntilNextDay(unixTime: number): number
	return SECONDS_PER_DAY - (unixTime % SECONDS_PER_DAY)
end

-- Neuer, leerer Shop-Teil fuer den Spielstand.
function ShopRules.newState(): any
	return { freeGrabDay = -1, receipts = {} }
end

function ShopRules.freeReady(shop: any, now: number): boolean
	return shop.freeGrabDay ~= ShopRules.dayOf(now)
end

-- Gratis-Griff nehmen. false = heute schon genommen (nichts geaendert).
function ShopRules.claimFree(shop: any, now: number): boolean
	if not ShopRules.freeReady(shop, now) then return false end
	shop.freeGrabDay = ShopRules.dayOf(now)
	return true
end

function ShopRules.hasReceipt(shop: any, purchaseId: string): boolean
	return table.find(shop.receipts, purchaseId) ~= nil
end

-- Kauf merken. false = schon bekannt (nicht noch einmal auszahlen).
-- Haelt die Liste auf `maxReceipts` (aelteste fliegen raus).
function ShopRules.recordPurchase(shop: any, purchaseId: string, maxReceipts: number): boolean
	if ShopRules.hasReceipt(shop, purchaseId) then return false end
	table.insert(shop.receipts, purchaseId)
	while #shop.receipts > maxReceipts do
		table.remove(shop.receipts, 1)
	end
	return true
end

-- Kauf wieder vergessen (Speichern ist gescheitert: Roblox meldet den Kauf
-- spaeter erneut, dann soll er normal ausgezahlt werden).
function ShopRules.forgetPurchase(shop: any, purchaseId: string)
	local index = table.find(shop.receipts, purchaseId)
	if index then table.remove(shop.receipts, index) end
end

return ShopRules
