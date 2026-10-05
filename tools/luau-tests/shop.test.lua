-- shop.test.lua — HBB Paket 10: Shop-Regeln und Spielstand
-- python tools/luau-tests/run_local.py tools/luau-tests/shop.test.lua
--
-- 1. Gratis-Griff: einmal pro UTC-Tag, Wechsel genau um 00:00 UTC.
-- 2. Robux-Kauf: jede Kauf-ID zahlt genau einmal; Liste begrenzt; nach
--    gescheitertem Speichern vergessen -> zweiter Versuch zahlt.
-- 3. Konfiguration: Paket mit ID 0 ist "nicht eingerichtet"; Gold-Budget
--    3 Tages-Quests + Gratis-Griff = 300 (12 Charm-Wuerfe); Shop-Kachel ab
--    der 2. Sitzung und nur mit Schalter.
-- 4. Migration: shop wird angelegt/repariert, sessions fuer Veteranen = 1.

local ShopRules       = rbxRequire("ReplicatedStorage/Modules/ShopRules")
local ShopConfig      = rbxRequire("ReplicatedStorage/Config/ShopConfig")
local QuestConfig     = rbxRequire("ReplicatedStorage/Config/QuestConfig")
local CharmConfig     = rbxRequire("ReplicatedStorage/Config/CharmConfig")
local Types           = rbxRequire("ReplicatedStorage/Network/Types")
local PlayerMigration = rbxRequire("ServerScriptService/Util/PlayerMigration")

local failures = 0
local function check(name, ok, detail)
	if ok then print("ok   " .. name) else
		failures += 1
		print("FAIL " .. name .. (if detail then ": " .. tostring(detail) else ""))
	end
end

-- 1. Gratis-Griff
local DAY = 86400
local t0 = 20000 * DAY + 3600          -- 01:00 UTC eines Tages
local shop = ShopRules.newState()
check("neu: Griff bereit", ShopRules.freeReady(shop, t0))
check("erster Griff klappt", ShopRules.claimFree(shop, t0))
check("zweiter am selben Tag nicht", not ShopRules.claimFree(shop, t0 + 3600 * 20))
check("23:59:59 noch derselbe Tag", not ShopRules.freeReady(shop, 20001 * DAY - 1))
check("00:00 UTC wieder bereit", ShopRules.freeReady(shop, 20001 * DAY))
check("Restzeit bis Mitternacht", ShopRules.secondsUntilNextDay(t0) == DAY - 3600)

-- 2. Kaeufe
local s2 = ShopRules.newState()
check("Kauf neu", ShopRules.recordPurchase(s2, "A", 3))
check("gleiche ID kein zweites Mal", not ShopRules.recordPurchase(s2, "A", 3))
ShopRules.recordPurchase(s2, "B", 3); ShopRules.recordPurchase(s2, "C", 3); ShopRules.recordPurchase(s2, "D", 3)
check("Liste begrenzt, aelteste raus", #s2.receipts == 3 and not ShopRules.hasReceipt(s2, "A") and ShopRules.hasReceipt(s2, "D"))
ShopRules.forgetPurchase(s2, "D")
check("vergessen -> erneut auszahlbar", ShopRules.recordPurchase(s2, "D", 3))

-- 3. Konfiguration
check("ID 0 = nicht eingerichtet", ShopConfig.byProductId(0) == nil)
local daily = 0
for _, def in QuestConfig.DAILY do daily += QuestConfig.goldReward(def) end
local perDay = daily + ShopConfig.FREE_GRAB_GOLD
check("Gold pro Tag = 12 Wuerfe", perDay == 12 * CharmConfig.ROLL_COST_GOLD_GUMMIES, perDay)
local UnlockRules = rbxRequire("ReplicatedStorage/Modules/UnlockRules")
local function shopVisible(sessions, enabled)
	local before = UnlockRules.SHOP_ENABLED
	UnlockRules.SHOP_ENABLED = enabled
	local view = { rebirthCount = 0, goldGummies = 0, island = { baerchis = {} }, stats = { sessions = sessions }, uiSeen = {} }
	local visible = UnlockRules.isVisible(view, "tile_shop")
	UnlockRules.SHOP_ENABLED = before
	return visible
end
check("Shop-Kachel: Sitzung 1 aus", not shopVisible(1, true))
check("Shop-Kachel: Sitzung 2 an", shopVisible(2, true))
check("Shop-Kachel: Schalter aus = aus", not shopVisible(5, false))

-- 4. Migration
local fresh = Types.createDefaultPlayerData()
check("Standard hat shop", fresh.shop ~= nil and fresh.shop.freeGrabDay == -1 and #fresh.shop.receipts == 0)
check("Standard sessions = 0", fresh.stats.sessions == 0)

local old = Types.createDefaultPlayerData()
old.shop = nil
old.stats.sessions = nil
old.createdAt = os.time() - 3 * DAY
PlayerMigration.applyDefaults(old)
check("alter Stand: shop angelegt", old.shop ~= nil and old.shop.freeGrabDay == -1)
check("Veteran: sessions = 1", old.stats.sessions == 1, old.stats.sessions)

local newbie = Types.createDefaultPlayerData()
newbie.stats.sessions = nil
PlayerMigration.applyDefaults(newbie)
check("frisches Konto: sessions = 0", newbie.stats.sessions == 0, newbie.stats.sessions)

local broken = Types.createDefaultPlayerData()
broken.shop = { freeGrabDay = "x", receipts = 5 } :: any
PlayerMigration.applyDefaults(broken)
check("kaputter shop repariert", broken.shop.freeGrabDay == -1 and typeof(broken.shop.receipts) == "table")

if failures > 0 then error(failures .. " Fehler", 0) end
print("shop: alle Tests gruen")
