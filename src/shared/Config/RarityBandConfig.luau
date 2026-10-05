--!strict
-- RarityBandConfig.luau
-- ReplicatedStorage/Config/RarityBandConfig.luau
--
-- Einzige Zustaendigkeit:
--   - Die 12 Rarities fuer die ANZEIGE in 5 Farbbaender fassen
--
-- Kontext: HBB Paket 4. Zwoelf Farben kann ein Kind nicht auseinanderhalten,
-- fuenf schon. Nur Anzeige: Spielwerte, Drop-Tabellen und Caps haengen
-- weiter an der einzelnen Rarity. Die Farben je Band stehen in UI/Theme
-- (Theme.BAND_COLORS), der Rarity-Name bleibt als kurzer Text sichtbar.
--
-- Default-Annahme aus dem Plan:
--   1 Common–Uncommon · 2 Rare–Epic · 3 Legendary–Mythic ·
--   4 Divine–Cosmic–Secret · 5 Godly–Eternal–Omega

local BAND_OF: { [string]: number } = {
	Common = 1, Uncommon = 1,
	Rare = 2, Epic = 2,
	Legendary = 3, Mythic = 3,
	Divine = 4, Cosmic = 4, Secret = 4,
	Godly = 5, Eternal = 5, Omega = 5,
}

return {
	BAND_OF = BAND_OF,
	BAND_COUNT = 5,
	bandOf = function(rarity: string): number
		return BAND_OF[rarity] or 1
	end,
}
