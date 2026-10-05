--!strict
-- ShopConfig.luau
-- ReplicatedStorage/Config/ShopConfig.luau
--
-- Einzige Zustaendigkeit:
--   - Alle Zahlen des Shops (HBB Paket 10, FeatureFlags.SHOP_V1): Gratis-Griff,
--     Robux-Pakete, Freischaltung. Texte stehen in den Sprachdateien
--     (ui.shop.*), die Regeln in Modules/ShopRules.
--
-- ============================================================
-- GOLD-BUDGET: 12 CHARM-WUERFE PRO TAG
-- ============================================================
-- Entscheidung 05.10.: 12 Wuerfe x 25 Gold = 300 Gold pro Tag ohne Robux.
-- Mit Shop: 3 Tages-Quests x 75 (QuestConfig) + Gratis-Griff 75 = 300.
--
-- ============================================================
-- ROBUX-PAKETE (Developer Products)
-- ============================================================
-- productId = 0 heisst "nicht eingerichtet": das Paket wird weder angezeigt
-- noch ausgezahlt. Einrichten: Creator Dashboard -> Spiel -> Monetization ->
-- Developer Products -> Produkt anlegen (Name, Preis in Robux) -> die ID hier
-- eintragen. Preis-Vorschlag steht nur als Kommentar; massgeblich ist der
-- Preis im Dashboard.
-- ACHTUNG Pay-to-Win: Gold kauft Charm-Wuerfe = Kampfkraft. Deshalb nur
-- kleine Pakete (hoechstens ~3 Tage Gratis-Gold je Kauf).

local ShopConfig = {}

-- Gratis-Griff: einmal pro UTC-Tag (gleicher Tageswechsel wie Quests/Login-Bonus)
ShopConfig.FREE_GRAB_GOLD = 75

-- So viele Kauf-IDs merkt sich ein Spielstand (gegen doppelte Auszahlung,
-- falls Roblox einen Kauf erneut meldet). Aeltere fallen heraus.
ShopConfig.MAX_RECEIPTS = 100

export type Product = {
	key       : string,   -- Text: ui.shop.pack.<key>
	productId : number,   -- Developer-Product-ID, 0 = nicht eingerichtet
	gold      : number,
	icon      : string,   -- Name aus UI/Icons
}

ShopConfig.PRODUCTS = {
	{ key = "small",  productId = 0, gold = 150, icon = "goldgummy" },  -- Vorschlag ~25 R$
	{ key = "medium", productId = 0, gold = 400, icon = "goldgummy" },  -- Vorschlag ~60 R$
	{ key = "large",  productId = 0, gold = 900, icon = "goldgummy" },  -- Vorschlag ~120 R$
} :: { Product }

-- Paket zu einer Developer-Product-ID (nil = unbekannt oder nicht eingerichtet)
function ShopConfig.byProductId(productId: number): Product?
	if productId == 0 then return nil end
	for _, product in ShopConfig.PRODUCTS do
		if product.productId == productId then return product end
	end
	return nil
end

return ShopConfig
