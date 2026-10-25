	-- 25.10.2026 Erste Baerchis (Uncommon/Rare): neue Shows, Werte wie die alten
	-- Faehigkeiten (balance-neutral). Die alten Eintraege bleiben fuer vorhandene
	-- Baerchis und Fusionen.
	PolarSlide = {
		id = "PolarSlide", displayName = "Bauchrutscher",
		effectType = "Stun", category = "damage", cooldown = 5, charge = 5,
		params = { damageMultiplier = 1.5, stunDuration = 1, baseDamage = 8 },
		description = "Rutscht auf dem Bauch in den Gegner: 1.5x Schaden, der Gegner steckt eine Aktion im Eis.",
		drawback = "Langer Cooldown.",
	},
	TigerPounce = {
		id = "TigerPounce", displayName = "Tigersprung",
		effectType = "DoT", category = "damage", cooldown = 4, charge = 4,
		params = { dotDamage = 5, dotDuration = 3, dotMultiplier = 0.25 },
		description = "Sprung und drei Krallenhiebe: die Kratzer brennen 3 Aktionen nach.",
		drawback = "Der Schaden kommt erst spaeter, ein neuer Brand ersetzt den alten.",
	},
	MagnifierBurn = {
		id = "MagnifierBurn", displayName = "Brennglas",
		effectType = "Damage", category = "damage", cooldown = 3, charge = 3,
		params = { multiplier = 2.2, baseDamage = 14 },
		description = "Buendelt Licht durch die Lupe auf den Gegner: 2.2x Schaden.",
		drawback = "Cooldown 3.",
	},
	BassDrop = {
		id = "BassDrop", displayName = "Bass-Drop",
		effectType = "AoeDamage", category = "damage", cooldown = 6, charge = 6,
		params = { damageMultiplier = 1.4, baseDamage = 10 },
		description = "Drei Beats, dann der Drop: eine Bass-Welle trifft alles um den DJ.",
		drawback = "Langer Cooldown.",
	},
	-- 25.10.2026 Erste Baerchis (Epic/Legendary): neue Shows, Werte wie die alten
	-- Faehigkeiten (balance-neutral).
	CoinShower = {
		id = "CoinShower", displayName = "Muenzregen",
		effectType = "Drain", category = "damage", cooldown = 5, charge = 5,
		params = { drainPercent = 0.25 },
		description = "Prasselt Goldmuenzen aus dem Gegner: stiehlt 25% seiner HP und heilt sich damit.",
		drawback = "Schwach gegen fast besiegte Gegner.",
	},
	ShurikenStorm = {
		id = "ShurikenStorm", displayName = "Shuriken-Sturm",
		effectType = "AoeDamage", category = "damage", cooldown = 7, charge = 7,
		params = { damageMultiplier = 2.4, baseDamage = 25 },
		description = "Schattenklone, Shuriken und ein Katana-Schnitt: das staerkste AoE im Spiel.",
		drawback = "Sehr langer Cooldown.",
	},
	RootBulwark = {
		id = "RootBulwark", displayName = "Wurzelwall",
		effectType = "Shield", category = "utility", cooldown = 8, charge = 8,
		params = { absorbPercent = 0.9, duration = 3 },
		description = "Wurzeln flechten sich zum Wall: absorbiert 90% Schaden fuer 3 Aktionen.",
		drawback = "Kein Schaden, sehr langer Cooldown.",
	},
	RainbowBridge = {
		id = "RainbowBridge", displayName = "Regenbogenbruecke",
		effectType = "Damage", category = "damage", cooldown = 4, charge = 4,
		params = { multiplier = 3, baseDamage = 30 },
		description = "Ueber den Regenbogen und mitten auf den Gegner: 3x Schaden.",
		drawback = "Cooldown 4.",
	},
