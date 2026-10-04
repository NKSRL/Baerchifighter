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
-- `baseDamage` ist OPTIONAL. Fehlt es, rechnet CombatCalculator mit 0 weiter.
--
-- ============================================================
-- SEIT DEM MEGA EGG TREE UPDATE (v14)
-- ============================================================
-- * Der Kampf laeuft rundenweise mit echten Status-Effekten (siehe
--   CombatCalculator, Kopf-Kommentar). Vorher hatten Shield, SpeedBuff,
--   DoT und AoeDamage gar keine Wirkung — sie setzten nur den Cooldown.
-- * Jeder Skill hat eine `category`:
--       "damage"  — macht Schaden (auch mit kleinem Zusatz wie Brand oder
--                   Finisher). Die grosse Mehrheit.
--       "utility" — heilt, schuetzt, kontrolliert, bufft oder wirkt
--                   ausserhalb des Kampfs. Bewusst selten.
-- * Jeder Skill hat einen dokumentierten NACHTEIL (`drawback`, nur Text fuer
--   die Doku und das UI). Ohne Nachteil gewinnt am Ende immer derselbe.
-- * Wie der Skill AUSSIEHT, steht nicht hier, sondern in SkillFXConfig
--   (Client-Baukasten). Hier steht nur, was er TUT.
--
-- Zeit-Einheit "Aktion": jede Dauer zaehlt die eigenen Aktionen dessen, der
-- den Status TRAEGT (ein Schild des Baerchis haelt 2 Baerchi-Aktionen, eine
-- Verlangsamung des Gegners haelt 3 Gegner-Aktionen). Wie oft jemand handelt,
-- haengt seit v14 an seiner SPD.

export type EffectType =
	| "Damage"          -- direkter Schaden
	| "AoeDamage"       -- im 1-gegen-1 wie Damage (Parameter damageMultiplier)
	| "Heal"            -- heilt den Angreifer
	| "Shield"          -- absorbiert einen Anteil des Schadens fuer N Aktionen
	| "SpeedBuff"       -- erhoeht die eigene SPD fuer N Aktionen
	| "SelfBuff"        -- SPD/PWR/ATK hoch fuer N Aktionen (kostet HP)
	| "Stun"            -- Gegner ueberspringt seine naechste Aktion
	| "Slow"            -- Gegner-SPD runter fuer N Gegner-Aktionen
	| "Weaken"          -- Gegner-ATK runter fuer N Gegner-Aktionen
	| "DoT"             -- Schaden ueber mehrere Gegner-Aktionen
	| "Revive"          -- belebt einmal mit X% HP
	| "LastStand"       -- ueberlebt einmal mit 1 HP, danach Feuerstoss
	| "Drain"           -- stiehlt HP vom Gegner
	| "InstantKill"     -- kleine Chance auf sofortigen K.O.
	| "Finisher"        -- Bonus, wenn der Gegner unter einer HP-Schwelle ist
	| "Opener"          -- erster Einsatz sehr stark, danach schwach
	| "Ramp"            -- jeder Einsatz staerker als der vorige
	| "MultiHit"        -- mehrere Treffer hintereinander (Salve)
	| "Passive"         -- keine Kampfwirkung (z.B. bessere Eier beim Legen)

export type SkillCategory = "damage" | "utility"

export type SkillDef = {
	id          : string,
	displayName : string,
	effectType  : EffectType,
	category    : SkillCategory,
	cooldown    : number,   -- (bis v14) alter Cooldown; seit v15 nur noch Doku, siehe charge
	-- v15: wie viele STOESSE der Baerchi braucht, bis die Faehigkeit geladen
	-- ist (siehe CHARGE unten). 0 = keine eigene Faehigkeit im Kampf
	-- (Grundschlag, Passiv, Letzte Chance).
	charge      : number,
	params      : { [string]: number },  -- EffectType-spezifische Werte
	description : string,
	drawback    : string,   -- der Preis fuer die Staerke (Doku/UI)
}

local SKILLS: { [string]: SkillDef } = {

	----------------------------------------------------------------------------
	-- Bestehende Skills (Zuordnung unveraendert, seit v14 mit echter Wirkung)
	----------------------------------------------------------------------------

	BasicPunch = {
		id = "BasicPunch", displayName = "Basis-Schlag",
		effectType = "Damage", category = "damage", cooldown = 0, charge = 0,
		params = { multiplier = 1.0 },
		description = "Ein einfacher Schlag. Immer da.",
		drawback = "Kein Ausschlag nach oben.",
	},
	SugarRush = {
		id = "SugarRush", displayName = "Zuckerrausch",
		effectType = "SpeedBuff", category = "utility", cooldown = 4, charge = 4,
		params = { speedMult = 2.0, duration = 2 },
		description = "Doppelte Angriffsgeschwindigkeit fuer 2 Aktionen.",
		drawback = "Macht selbst keinen Zusatzschaden, langer Cooldown.",
	},
	GummyShield = {
		id = "GummyShield", displayName = "Gummischild",
		effectType = "Shield", category = "utility", cooldown = 4, charge = 4,
		params = { absorbPercent = 0.5, duration = 2 },
		description = "Absorbiert 50% des Schadens fuer 2 Aktionen.",
		drawback = "Kein Schaden, Luecke zwischen den Schilden.",
	},
	IceSlam = {
		id = "IceSlam", displayName = "Eisschlag",
		effectType = "Stun", category = "damage", cooldown = 5, charge = 5,
		params = { damageMultiplier = 1.5, stunDuration = 1, baseDamage = 8 },
		description = "1.5x Schaden und betaeubt den Gegner fuer eine Aktion.",
		drawback = "Langer Cooldown.",
	},
	FireBite = {
		id = "FireBite", displayName = "Feuerbiss",
		effectType = "DoT", category = "damage", cooldown = 4, charge = 4,
		-- v14: der Brand skaliert mit ATK (vorher fest 15 Schaden — und
		-- wirkungslos, weil DoT nie ausgewertet wurde).
		params = { dotDamage = 5, dotMultiplier = 0.25, dotDuration = 3 },
		description = "Setzt den Gegner fuer 3 Aktionen in Brand.",
		drawback = "Der Schaden kommt erst spaeter, ein neuer Brand ersetzt den alten.",
	},
	SugarStorm = {
		id = "SugarStorm", displayName = "Zuckersturm",
		effectType = "AoeDamage", category = "damage", cooldown = 6, charge = 6,
		params = { damageMultiplier = 1.4, baseDamage = 10 },
		description = "Ein Wirbel aus Zucker trifft alles um den Baerchi.",
		drawback = "Langer Cooldown.",
	},
	ShardBlast = {
		id = "ShardBlast", displayName = "Splitterhagel",
		effectType = "Damage", category = "damage", cooldown = 3, charge = 3,
		params = { multiplier = 2.2, baseDamage = 14 },
		description = "2.2x Schaden. Langsam aufzuladen, aber verheerend.",
		drawback = "Cooldown 3.",
	},
	GoldRush = {
		id = "GoldRush", displayName = "Gold Rush",
		effectType = "Drain", category = "damage", cooldown = 5, charge = 5,
		params = { drainPercent = 0.25 },
		description = "Stiehlt 25% der gegnerischen HP und heilt sich damit.",
		drawback = "Schwach gegen fast besiegte Gegner.",
	},
	BlackHole = {
		id = "BlackHole", displayName = "Schwarzes Loch",
		effectType = "AoeDamage", category = "damage", cooldown = 7, charge = 7,
		params = { damageMultiplier = 2.4, baseDamage = 25 },
		description = "Saugt alles ein. Das staerkste AoE im Spiel.",
		drawback = "Sehr langer Cooldown.",
	},
	ChromaBlast = {
		id = "ChromaBlast", displayName = "Chroma-Blast",
		effectType = "Damage", category = "damage", cooldown = 4, charge = 4,
		params = { multiplier = 3.0, baseDamage = 30 },
		description = "3x Schaden. Alle Farben auf einmal.",
		drawback = "Cooldown 4.",
	},
	TitanMode = {
		id = "TitanMode", displayName = "Titan-Modus",
		effectType = "Shield", category = "utility", cooldown = 8, charge = 8,
		params = { absorbPercent = 0.9, duration = 3 },
		description = "Absorbiert 90% Schaden fuer 3 Aktionen. Unzerstoerbar.",
		drawback = "Kein Schaden, sehr langer Cooldown.",
	},
	BigBang = {
		id = "BigBang", displayName = "Big Bang",
		effectType = "InstantKill", category = "damage", cooldown = 10, charge = 10,
		params = { chance = 0.20, fallbackMultiplier = 2.5, baseDamage = 45 },
		description = "20% Chance auf sofortigen K.O. Sonst 2.5x Schaden.",
		drawback = "Glueckssache, Cooldown 10.",
	},
	BearHug = {
		id = "BearHug", displayName = "Baerchen-Umarmung",
		effectType = "Heal", category = "utility", cooldown = 4, charge = 4,
		params = { healPercent = 0.30 },
		description = "Heilt 30% der maximalen HP. Der freundlichste Skill.",
		drawback = "Kein Schaden.",
	},
	Revive = {
		id = "Revive", displayName = "Auferstehung",
		effectType = "Revive", category = "utility", cooldown = 0, charge = 0,
		params = { reviveHpPercent = 0.50 },
		description = "Kehrt einmal pro Kampf mit 50% HP zurueck.",
		drawback = "Nur einmal pro Kampf.",
	},

	----------------------------------------------------------------------------
	-- Mythic und Divine (v14): sechs der sieben sind KEIN Schaden
	----------------------------------------------------------------------------

	PhoenixRebirth = {
		id = "PhoenixRebirth", displayName = "Phoenix-Glut",
		effectType = "LastStand", category = "utility", cooldown = 0, charge = 0,
		params = { burstMultiplier = 2.0, baseDamage = 40 },
		description = "Ueberlebt einmal pro Kampf mit 1 HP und schlaegt mit einem Feuerstoss zurueck.",
		drawback = "Nur einmal pro Kampf, danach steht er mit 1 HP da.",
	},
	GlacierFrost = {
		id = "GlacierFrost", displayName = "Gletscherhauch",
		effectType = "Slow", category = "utility", cooldown = 4, charge = 4,
		params = { slowPercent = 0.40, duration = 3 },
		description = "Verlangsamt den Gegner um 40% fuer 3 seiner Aktionen.",
		drawback = "Kein Schaden.",
	},
	PhantomOmen = {
		id = "PhantomOmen", displayName = "Phantom-Omen",
		effectType = "Passive", category = "utility", cooldown = 0, charge = 0,
		params = {},
		description = "Passiv: gelegte Eier steigen mit 25% Chance eine Stufe auf.",
		drawback = "Im Kampf wirkungslos.",
	},
	SeraphGrace = {
		id = "SeraphGrace", displayName = "Seraphen-Segen",
		effectType = "Heal", category = "utility", cooldown = 4, charge = 4,
		params = { healPercent = 0.22 },
		description = "Heilt 22% der maximalen HP.",
		drawback = "Kein Schaden, PWR wirkt nicht auf Heilung.",
	},
	AuroraVeil = {
		id = "AuroraVeil", displayName = "Polarschleier",
		effectType = "SelfBuff", category = "utility", cooldown = 5, charge = 5,
		params = { spdMult = 1.5, pwrAdd = 0.30, atkMult = 1.0, duration = 3, hpCost = 0.08 },
		description = "+50% SPD und +30% PWR fuer 3 Aktionen.",
		drawback = "Kostet 8% der maximalen HP.",
	},
	EclipseShroud = {
		id = "EclipseShroud", displayName = "Finsternis",
		effectType = "Weaken", category = "utility", cooldown = 5, charge = 5,
		params = { atkReduce = 0.35, duration = 3 },
		description = "Senkt den Angriff des Gegners um 35% fuer 3 seiner Aktionen.",
		drawback = "Kein Schaden.",
	},

	----------------------------------------------------------------------------
	-- Cosmic bis Omega (v14): nur Schaden, die Show steckt in SkillFX
	----------------------------------------------------------------------------

	CometImpact = {
		id = "CometImpact", displayName = "Kometeneinschlag",
		effectType = "Opener", category = "damage", cooldown = 5, charge = 5,
		params = { openerMultiplier = 4.5, multiplier = 1.6, baseDamage = 60 },
		description = "Der erste Einschlag trifft mit 4.5x ATK, spaetere mit 1.6x.",
		drawback = "Nur der erste Einsatz ist stark.",
	},
	NebulaBurn = {
		id = "NebulaBurn", displayName = "Nebelbrand",
		effectType = "DoT", category = "damage", cooldown = 5, charge = 5,
		params = { dotDamage = 20, dotMultiplier = 0.45, dotDuration = 4, multiplier = 1.0 },
		description = "Huellt den Gegner in brennenden Nebel (4 Aktionen).",
		drawback = "Der Schaden kommt verzoegert.",
	},
	PulsarPulse = {
		id = "PulsarPulse", displayName = "Pulsstoss",
		effectType = "Ramp", category = "damage", cooldown = 3, charge = 3,
		params = { multiplier = 1.2, rampPerUse = 0.5, baseDamage = 30 },
		description = "Jeder Puls trifft staerker als der vorige.",
		drawback = "Schwacher Anfang.",
	},
	ShadeSlash = {
		id = "ShadeSlash", displayName = "Schattenhieb",
		effectType = "Finisher", category = "damage", cooldown = 3, charge = 3,
		params = { multiplier = 1.4, finisherMultiplier = 4.0, threshold = 0.30, baseDamage = 40 },
		description = "Unter 30% Gegner-HP trifft der Hieb mit 4x ATK.",
		drawback = "Gegen volle Gegner nur durchschnittlich.",
	},
	RiddleBeam = {
		id = "RiddleBeam", displayName = "Raetselstrahl",
		effectType = "Damage", category = "damage", cooldown = 4, charge = 4,
		params = { multiplier = 2.6, baseDamage = 50 },
		description = "Ein Strahl aus Symbolen, 2.6x Schaden.",
		drawback = "Cooldown 4.",
	},
	TitanFist = {
		id = "TitanFist", displayName = "Titanenfaust",
		effectType = "Damage", category = "damage", cooldown = 6, charge = 6,
		params = { multiplier = 3.6, baseDamage = 90 },
		description = "Eine Faust vom Himmel, 3.6x Schaden.",
		drawback = "Cooldown 6.",
	},
	GenesisWave = {
		id = "GenesisWave", displayName = "Schoepfungswelle",
		effectType = "Ramp", category = "damage", cooldown = 4, charge = 4,
		params = { multiplier = 1.4, rampPerUse = 0.6, baseDamage = 60 },
		description = "Jede Welle baut auf der letzten auf.",
		drawback = "Braucht lange Kaempfe.",
	},
	ChronosRift = {
		id = "ChronosRift", displayName = "Zeitriss",
		effectType = "Damage", category = "damage", cooldown = 5, charge = 5,
		params = { multiplier = 3.0, baseDamage = 120 },
		description = "Reisst die Zeit auf, 3x Schaden.",
		drawback = "Cooldown 5.",
	},
	InfinityBarrage = {
		id = "InfinityBarrage", displayName = "Unendlichkeits-Salve",
		effectType = "MultiHit", category = "damage", cooldown = 5, charge = 5,
		params = { hits = 5, multiplierPerHit = 0.6, baseDamage = 20 },
		description = "Fuenf Treffer hintereinander, je 0.6x ATK.",
		drawback = "Cooldown 5.",
	},
	OmegaStrike = {
		id = "OmegaStrike", displayName = "Omega-Schlag",
		effectType = "Damage", category = "damage", cooldown = 9, charge = 9,
		params = { multiplier = 7.0, baseDamage = 300 },
		description = "Ein einziger Schlag. 7x Schaden.",
		drawback = "Cooldown 9 — dazwischen nur normale Schlaege.",
	},
}

-- ============================================================
-- v15: AUFLADEN STATT COOLDOWN
-- ============================================================
-- Im Kampf laufen die Baerchis aufeinander zu und STOSSEN sich (normaler
-- Treffer, macht den Grundschaden = ATK). Jeder eigene Stoss laedt die
-- Faehigkeit auf:
--
--     Ladung pro Stoss = PER_HIT x (1 + PWR x PWR_FACTOR)
--
-- Ist die Ladung >= skill.charge, ist der naechste Zug die Faehigkeit — mit
-- ihrer vollen Show (SkillFX). Danach beginnt das Laden von vorn. Mehr als
-- voll geht nicht: ueberschuessige Ladung verfaellt. Ein Baerchi mit hoher PWR laedt also schneller, einer mit
-- hoher SPD stoesst oefter und laedt dadurch ebenfalls schneller.
--
-- Die Ladung bleibt ueber die Stages eines PIT-Laufs erhalten: der Baerchi
-- kommt "geladen" in die naechste Stage. Sonst kaemen Faehigkeiten mit hoher
-- Ladung in kurzen Stages nie zum Zug.
local CHARGE = {
	PER_HIT    = 1.0,
	PWR_FACTOR = 1.0,
}

local function getById(id: string): SkillDef?
	return SKILLS[id]
end

return {
	CHARGE  = CHARGE,
	data    = SKILLS,
	getById = getById,
}
