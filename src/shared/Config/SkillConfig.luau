--!strict
-- SkillConfig.luau
-- ReplicatedStorage/Config/SkillConfig.luau
--
-- Alle Skills. CombatCalculator liest EffectType und Params.
-- Neuer Skill = neuer Eintrag. CombatCalculator hat einen
-- Handler pro EffectType — nicht pro SkillId.
--
-- ============================================================
-- WORAUS SICH DER SCHADEN EINER ABILITY ZUSAMMENSETZT
-- ============================================================
--     Skill-Schaden = (ATK x multiplier + baseDamage) x (1 + PWR)
--
-- Die beiden linken Zahlen gehoeren dem SKILL und stehen hier; ATK und PWR
-- gehoeren dem BAERCHI und stehen in BaerchiConfig. Gerechnet wird das an
-- genau einer Stelle: CombatCalculator.skillDamage.
--
-- `multiplier` ist der ATK-Anteil — er macht den Skill mit dem Baerchi stark.
-- `baseDamage` ist ein fester Sockel obendrauf. Er ist bewusst klein gehalten
-- (8 bis 45 gegenueber ATK-Werten ab 10): fuer einen frischen Baerchi macht er
-- eine starke Ability spuerbar, ab mittleren Leveln traegt ihn das ATK-Vielfache
-- laengst. Ohne diesen Sockel waere eine 3.0x-Ability auf Level 1 exakt so
-- langweilig wie auf Level 50, nur mit kleineren Zahlen.
--
-- `baseDamage` ist OPTIONAL. Fehlt es, rechnet CombatCalculator mit 0 weiter —
-- ein Skill ohne eigenen Sockel ist voellig in Ordnung (BasicPunch hat
-- bewusst keinen: er IST der normale Schlag).

export type EffectType =
	| "Damage"          -- direkter Schaden
	| "Heal"            -- heilt den Angreifer
	| "Shield"          -- absorbiert Schaden fuer N Runden
	| "SpeedBuff"       -- erhoeht SPD temporaer
	| "AoeDamage"       -- Schaden auf alle Gegner (PvP/Boss)
	| "Stun"            -- Gegner ueberspringt naechsten Angriff
	| "DoT"             -- Schaden ueber mehrere Runden (Damage over Time)
	| "Revive"          -- belebt mit 50% HP wenn besiegt
	| "Drain"           -- stiehlt HP vom Gegner
	| "InstantKill"     -- kleine Chance auf sofortigen K.O.

export type SkillDef = {
	id          : string,
	displayName : string,
	effectType  : EffectType,
	cooldown    : number,   -- Runden bis der Skill wieder einsetzbar ist
	params      : { [string]: number },  -- EffectType-spezifische Werte
	description : string,
}

local SKILLS: { [string]: SkillDef } = {

	BasicPunch = {
		id = "BasicPunch", displayName = "Basis-Schlag",
		effectType = "Damage", cooldown = 0,
		params = { multiplier = 1.0 },
		description = "Ein einfacher Schlag. Immer da.",
	},
	SugarRush = {
		id = "SugarRush", displayName = "Zuckerrausch",
		effectType = "SpeedBuff", cooldown = 3,
		params = { speedMult = 2.0, duration = 2 },
		description = "Doppelte Angriffsgeschwindigkeit fuer 2 Runden.",
	},
	GummyShield = {
		id = "GummyShield", displayName = "Gummischild",
		effectType = "Shield", cooldown = 4,
		params = { absorbPercent = 0.5, duration = 2 },
		description = "Absorbiert 50% des Schadens fuer 2 Runden.",
	},
	IceSlam = {
		id = "IceSlam", displayName = "Eisschlag",
		effectType = "Stun", cooldown = 5,
		params = { damageMultiplier = 1.5, stunDuration = 1, baseDamage = 8 },
		description = "1.5x Schaden und betaeubt den Gegner 1 Runde.",
	},
	FireBite = {
		id = "FireBite", displayName = "Feuerbiss",
		effectType = "DoT", cooldown = 4,
		params = { dotDamage = 15, dotDuration = 3 },
		description = "Brennt fuer 15 Schaden ueber 3 Runden.",
	},
	SugarStorm = {
		id = "SugarStorm", displayName = "Zuckersturm",
		effectType = "AoeDamage", cooldown = 6,
		params = { damageMultiplier = 0.8, baseDamage = 10 },
		description = "80% Schaden an alle Gegner gleichzeitig.",
	},
	ShardBlast = {
		id = "ShardBlast", displayName = "Splitterhagel",
		effectType = "Damage", cooldown = 3,
		params = { multiplier = 2.2, baseDamage = 14 },
		description = "2.2x Schaden. Langsam aufzuladen, aber verheerend.",
	},
	GoldRush = {
		id = "GoldRush", displayName = "Gold Rush",
		effectType = "Drain", cooldown = 5,
		params = { drainPercent = 0.25 },
		description = "Stiehlt 25% der gegnerischen HP und heilt sich damit.",
	},
	BlackHole = {
		id = "BlackHole", displayName = "Schwarzes Loch",
		effectType = "AoeDamage", cooldown = 7,
		params = { damageMultiplier = 1.5, baseDamage = 25 },
		description = "1.5x Schaden an alle. Das Stärkste AoE im Spiel.",
	},
	ChromaBlast = {
		id = "ChromaBlast", displayName = "Chroma-Blast",
		effectType = "Damage", cooldown = 4,
		params = { multiplier = 3.0, baseDamage = 30 },
		description = "3x Schaden. Alle Farben auf einmal.",
	},
	TitanMode = {
		id = "TitanMode", displayName = "Titan-Modus",
		effectType = "Shield", cooldown = 8,
		params = { absorbPercent = 0.9, duration = 3 },
		description = "Absorbiert 90% Schaden fuer 3 Runden. Unzerstoerbar.",
	},
	BigBang = {
		id = "BigBang", displayName = "Big Bang",
		effectType = "InstantKill", cooldown = 10,
		params = { chance = 0.20, fallbackMultiplier = 2.5, baseDamage = 45 },
		description = "20% Chance auf sofortigen K.O. Sonst 2.5x Schaden.",
	},
	BearHug = {
		id = "BearHug", displayName = "Baerchen-Umarmung",
		effectType = "Heal", cooldown = 4,
		params = { healPercent = 0.30 },
		description = "Heilt 30% der maximalen HP. Der freundlichste Skill.",
	},
	Revive = {
		id = "Revive", displayName = "Auferstehung",
		effectType = "Revive", cooldown = 0,   -- einmalig pro Kampf
		params = { reviveHpPercent = 0.50 },
		description = "Kehrt einmal pro Kampf mit 50% HP zurueck.",
	},
}

local function getById(id: string): SkillDef?
	return SKILLS[id]
end

return {
	data    = SKILLS,
	getById = getById,
}
