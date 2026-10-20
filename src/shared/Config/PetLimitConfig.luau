--!strict
-- PetLimitConfig.luau
-- ReplicatedStorage/Config/PetLimitConfig.luau
--
-- Einzige Zustaendigkeit:
--   - Alle Zahlen fuer das Pet-Limit (Lager voll) und den Verkaufsmodus
--
-- Liegt in ReplicatedStorage, weil Server (setzt durch) und Client (zeigt den
-- Zaehler, graut Knoepfe aus) dieselben Werte brauchen. Autoritativ ist nur
-- der Server. Schalter: FeatureFlags.PET_LIMIT_V1 / PET_SELL_MODE_V1.

local PetLimitConfig = {}

-- Wie viele Baerchis ein Spieler maximal besitzen darf (Basiswert). Spaeter
-- erweiterbar (Rebirth, Gamepass, Upgrade) ueber PetCapacity.getPetLimit.
PetLimitConfig.BASE_LIMIT = 100

-- Ab diesem Anteil des Limits faerbt sich der Zaehler gelb (voll = rot).
PetLimitConfig.WARN_FRACTION = 0.9

-- Hoechstens so viele Baerchis pro Verkaufs-Anfrage. Bewusst etwas ueber dem
-- Limit, damit auch ein Bestandsspieler ueber dem Limit in einem Rutsch
-- aufraeumen kann, ein Exploit aber keine riesige Liste schicken kann.
PetLimitConfig.SELL_MAX_PER_REQUEST = 250

-- Ab dieser Rarity zeigt das Bestaetigungsfenster eine zusaetzliche Warnzeile
-- mit der Zahl seltener Baerchis in der Auswahl.
PetLimitConfig.SELL_WARN_MIN_RARITY = "Epic"

-- Verkaufserloes je Baerchi (Gummies). Heute ueberall 0 = Verkaufen loescht nur.
-- Haken fuer spaeter; der Ablauf (PetSellService) rechnet schon damit.
PetLimitConfig.SELL_PAYOUT_PER_RARITY = {
	Common    = 0,
	Uncommon  = 0,
	Rare      = 0,
	Epic      = 0,
	Legendary = 0,
	Mythic    = 0,
	Divine    = 0,
	Cosmic    = 0,
	Secret    = 0,
	Godly     = 0,
	Eternal   = 0,
	Omega     = 0,
} :: { [string]: number }

return PetLimitConfig
