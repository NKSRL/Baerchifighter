--!strict
-- PetSellRules.luau
-- ReplicatedStorage/Modules/PetSellRules.luau
--
-- Einzige Zustaendigkeit:
--   - Die Regeln des Verkaufens als reine Funktionen: welches Baerchi darf nicht
--     verkauft werden (und warum), wie viele seltene stecken in einer Auswahl
--
-- Server (PetSellService, prueft ALLES neu) und Client (Markierung, Erklaerung
-- bei Klick) benutzen dieselben Regeln, damit sich beide nie widersprechen.
-- Gibt es spaeter Favoriten/Sperren fuer Baerchis, kommt der Grund hier dazu.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaerchiConfig  = require(ReplicatedStorage.Config.BaerchiConfig)
local PetLimitConfig = require(ReplicatedStorage.Config.PetLimitConfig)
local IncubatorRules = require(ReplicatedStorage.Modules.IncubatorRules)

local PetSellRules = {}

-- nil = verkaufbar, sonst der Loc-Schluessel der Erklaerung.
function PetSellRules.blockReason(data: any, uid: string): string?
	local baerchi = data.island.baerchis[uid]
	if not baerchi then return "err.sell_unknown" end

	-- Der ausgeruestete legt die Eier und steht auf dem Plot — nie verkaufbar
	-- (gleiche Regel wie beim Verwerten).
	if data.island.equippedUid == uid then return "err.sell_equipped" end

	-- Das Baerchi im Inkubator bruetet gerade Eier.
	local incubator = data.island.incubator
	if incubator and IncubatorRules.breederSlotOf(incubator.breeders, uid) then
		return "err.sell_incubator"
	end

	return nil
end

-- Ab dieser Rarity (inklusive) gilt ein Baerchi als selten.
function PetSellRules.isRare(rarity: string): boolean
	local threshold = BaerchiConfig.getRarityIndex(PetLimitConfig.SELL_WARN_MIN_RARITY :: any)
	return BaerchiConfig.getRarityIndex(rarity :: any) >= threshold
end

-- Wie viele seltene Baerchis stecken in dieser Auswahl?
function PetSellRules.countRare(data: any, uids: { string }): number
	local n = 0
	for _, uid in uids do
		local baerchi = data.island.baerchis[uid]
		if baerchi and PetSellRules.isRare(baerchi.rarity) then n += 1 end
	end
	return n
end

-- Verkaufserloes (Gummies) eines Baerchis. Heute ueberall 0.
function PetSellRules.payout(rarity: string): number
	return math.max(0, PetLimitConfig.SELL_PAYOUT_PER_RARITY[rarity] or 0)
end

return PetSellRules
