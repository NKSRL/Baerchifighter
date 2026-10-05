--!strict
-- ShopService.luau
-- ServerScriptService/Services/ShopService.luau
--
-- Einzige Zustaendigkeit:
--   - Der Shop (HBB Paket 10, FeatureFlags.SHOP_V1): Gratis-Griff einmal pro
--     UTC-Tag (RequestClaimFreeGrab) und Robux-Goldpakete (Developer Products,
--     MarketplaceService.ProcessReceipt).
--
-- Regeln stehen in Modules/ShopRules (getestet), Zahlen in Config/ShopConfig.
-- Gold zahlt nur EconomyService aus.
--
-- ============================================================
-- ROBUX-KAEUFE: GENAU EINMAL AUSZAHLEN
-- ============================================================
-- Roblox ruft ProcessReceipt auf, bis einmal PurchaseGranted zurueckkommt —
-- auch nach Server-Absturz, auf einem anderen Server. Deshalb:
--   1. Kauf-ID schon im Spielstand gemerkt -> sofort Granted (nicht doppelt).
--   2. Sonst merken + auszahlen + SOFORT speichern (PlayerService.saveConfirmed).
--   3. Speichern gescheitert -> beides zuruecknehmen und NotProcessedYet:
--      Roblox fragt spaeter erneut, dann sauber von vorn.
-- Spieler nicht (mehr) auf diesem Server oder Stand nicht geladen ->
-- NotProcessedYet (Roblox wiederholt beim naechsten Join).
-- Es darf im ganzen Spiel nur EINEN ProcessReceipt-Callback geben: diesen.

local Players             = game:GetService("Players")
local MarketplaceService  = game:GetService("MarketplaceService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes      = require(ReplicatedStorage.Network.Remotes)
local Loc          = require(ReplicatedStorage.Localization.Loc)
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)
local ShopConfig   = require(ReplicatedStorage.Config.ShopConfig)
local ShopRules    = require(ReplicatedStorage.Modules.ShopRules)
local UnlockRules  = require(ReplicatedStorage.Modules.UnlockRules)

local PlayerService  = require(ServerScriptService.Services.PlayerService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local RateLimiter    = require(ServerScriptService.Util.RateLimiter)

local ShopService = {}

-- Kaeufe, die gerade verarbeitet werden (gegen gleichzeitige Doppelaufrufe)
local _inFlight: { [string]: boolean } = {}

local function fail(player: Player, key: string)
	Remotes.ActionFailed:FireClient(player, "RequestClaimFreeGrab", Loc.msg(key))
end

--------------------------------------------------------------------------------
-- Gratis-Griff
--------------------------------------------------------------------------------

local function claimFreeGrab(player: Player)
	local data = PlayerService.getData(player)
	if not data then return end

	if not ShopRules.claimFree(data.shop, os.time()) then
		fail(player, "err.shop_free_taken")
		return
	end

	local paid = EconomyService.awardGoldGummies(player, ShopConfig.FREE_GRAB_GOLD)
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)
	print("[ShopService]", player.Name, "Gratis-Griff | +", paid, "Gold")
end

--------------------------------------------------------------------------------
-- Robux-Kaeufe
--------------------------------------------------------------------------------

local function processReceipt(info: any): Enum.ProductPurchaseDecision
	local purchaseId = tostring(info.PurchaseId)
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local data = PlayerService.getData(player)
	if not data then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- 1. Schon ausgezahlt (Roblox meldet erneut) -> nur bestaetigen
	if ShopRules.hasReceipt(data.shop, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	if _inFlight[purchaseId] then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local product = ShopConfig.byProductId(info.ProductId)
	if not product then
		warn("[ShopService] Unbekannte Product-ID (ShopConfig pruefen):", info.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- 2. Merken, auszahlen, sofort speichern
	_inFlight[purchaseId] = true
	ShopRules.recordPurchase(data.shop, purchaseId, ShopConfig.MAX_RECEIPTS)
	local paid = EconomyService.awardGoldGummies(player, product.gold)
	local saved = PlayerService.saveConfirmed(player)
	_inFlight[purchaseId] = nil

	if saved then
		PlayerService.markDirty(player)
		print("[ShopService]", player.Name, "Kauf", product.key, "| +", paid, "Gold | Kauf-ID", purchaseId)
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	-- 3. Speichern gescheitert -> zuruecknehmen, Roblox fragt spaeter erneut
	ShopRules.forgetPurchase(data.shop, purchaseId)
	if paid > 0 then
		EconomyService.spendGoldGummies(player, paid)
	end
	warn("[ShopService] Speichern fehlgeschlagen, Kauf wird spaeter erneut verarbeitet:", purchaseId)
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

--------------------------------------------------------------------------------
-- Start
--------------------------------------------------------------------------------

function ShopService.init()
	if not FeatureFlags.isOn("SHOP_V1") then
		print("[ShopService] Aus (SHOP_V1 = false)")
		return
	end

	-- Shop-Kachel darf freigeschaltet werden (UnlockRules hat keine requires)
	UnlockRules.SHOP_ENABLED = true

	RateLimiter.connect(Remotes.RequestClaimFreeGrab, "RequestClaimFreeGrab", function(player)
		claimFreeGrab(player)
	end)

	MarketplaceService.ProcessReceipt = processReceipt

	local live = 0
	for _, product in ShopConfig.PRODUCTS do
		if product.productId ~= 0 then live += 1 end
	end
	print("[ShopService] Initialisiert | Robux-Pakete eingerichtet:", live, "von", #ShopConfig.PRODUCTS)
end

return ShopService
