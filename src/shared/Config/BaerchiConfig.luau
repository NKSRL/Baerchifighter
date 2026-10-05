--!strict
-- BaerchiConfig.luau
-- ReplicatedStorage/Config/BaerchiConfig.luau
--
-- Alle Baerchi-Typen mit Basiswerten.
-- Kein Service hat hardcodierte Stats — alles kommt von hier.
-- Neuer Baerchi = neuer Eintrag, kein Code aendern.
--
-- Enthaelt ausserdem die Baerchi-Progression (Level-Cap, XP-Kurve), die
-- Rarity-Kette und (v14) die Pfade des Ei-Baums.

local Types = require(script.Parent.Parent.Network.Types)

export type BaerchiDef = {
	id          : string,
	displayName : string,
	rarity      : Types.Rarity,
	-- ============================================================
	-- DIE VIER BASISWERTE
	-- ============================================================
	-- Es gibt bewusst KEINE Verteidigung mehr. Wer einen Tank will, baut einen
	-- Baerchi mit viel HP — das ist die ganze Regel. Der frueher vorhandene
	-- DEF-Wert (prozentuale Schadensreduktion) ist ersatzlos entfallen; seine
	-- Wirkung steckt jetzt in den HP-Grundwerten (siehe Kommentar bei BAERCHIS).
	--
	-- Jeder Baerchi hat seine EIGENEN Werte. Sie leiten sich ausdruecklich
	-- NICHT aus der Rarity ab: ein Common kann eine hoehere PWR haben als ein
	-- Epic. Die Rarity sagt, wie selten er ist und wie hoch seine Stat-Stufen
	-- steigen koennen (PromotionConfig.STAT_CAP) — nicht, wie er sich anfuehlt.
	baseStats   : {
		hp  : number,   -- Basis-Lebenspunkte bei Level 1
		atk : number,   -- Basis-Schaden pro Treffer
		spd : number,   -- Angriffs-Speed (Treffer pro Sekunde, z.B. 1.2)

		-- Ability-Staerke als ANTEIL (0.20 = +20%). Skaliert ausschliesslich
		-- den Schaden von Skills, nie den normalen Schlag — die Formel steht in
		-- CombatCalculator:
		--     Skill-Schaden = (ATK x Skill-Multiplikator + Skill-Basisschaden)
		--                     x (1 + PWR)
		-- Ein Baerchi mit hoher PWR und mittlerem ATK ist damit ein
		-- Ability-Baerchi, einer mit hohem ATK und niedriger PWR ein
		-- Dauerschlaeger. Genau dieser Unterschied ist der Sinn des Werts.
		pwr : number,
	},
	-- ============================================================
	-- EIER LEGEN
	-- ============================================================
	-- Der ausgeruestete Baerchi legt regelmaessig ein Ei dort ab, wo er
	-- gerade steht (siehe EggLayService). Zwei Werte steuern das, und beide
	-- gehoeren dem einzelnen Baerchi — NICHT seiner Rarity:
	--
	--   layIntervalSeconds  WIE OFT er legt (Sekunden pro Ei auf Level 1)
	--   eggTable            WAS er legt (gewichtete Chancen je Ei-Typ)
	--
	-- Ein Baerchi, der seltene Eier legt, legt dafuer langsamer. Das ist die
	-- einzige Regel, an die sich die Zahlen unten halten — welcher Baerchi
	-- welche Eier legt, ist ansonsten reine Charaktersache (der Zucker-Baerchi
	-- legt Zucker-Eier, der Kristall-Baerchi Kristall-Eier).
	--
	-- ASCENSION-EIER sind bewusst fast unerreichbar: nur die beiden Legendaries
	-- und der Mythic koennen ueberhaupt eines legen, und selbst bei denen mit
	-- kleinem Gewicht. Sie sollen verdient bleiben (siehe EggConfig: nicht
	-- kaufbar, sonst nur aus Rebirth-Meilensteinen).
	layIntervalSeconds : number,
	eggTable    : { { eggType: Types.EggType, weight: number } },

	-- v14: Chance (0..1), dass ein gelegtes Ei eine Stufe hoeher im Baum
	-- landet. Nur Void-Baerchis haben das (siehe Kommentar bei BAERCHIS).
	layUpgradeChance : number?,

	path        : Types.PathId,   -- v14: Pfad im Ei-Baum (siehe PATHS)
	defaultSkill: string,   -- SkillId aus SkillConfig
	-- Aus welchen Eiern hatchbar. Seit v14 BERECHNET (EggConfig traegt es beim
	-- Laden ein), in der Tabelle unten immer leer.
	eggSource   : { Types.EggType },
	description : string,   -- fuer Ingame-UI
}

-- Stat-Wachstum pro Level (Formel siehe Abschnitt "Progression" weiter unten):
-- hp  = baseStats.hp  * 1.1^(level - 1)
-- atk = baseStats.atk * 1.1^(level - 1)
-- Angewendet wird das in CombatCalculator.getEffectiveStats — die Zahlen
-- dahinter stehen aber hier, nicht dort.
--
-- ============================================================
-- WOHER DIE HP-GRUNDWERTE KOMMEN (DEF-AUSBAU)
-- ============================================================
-- Frueher hatte jeder Baerchi zusaetzlich einen DEF-Wert, der eingehenden
-- Schaden prozentual reduzierte. DEF ist ersatzlos entfallen — Zaehigkeit
-- laeuft jetzt ausschliesslich ueber HP.
--
-- Damit dabei niemand schwaecher wurde, sind die HP-Grundwerte umgerechnet
-- worden statt neu geraten:
--
--     neue_hp = alte_hp / (1 - altes_def)
--
-- Das ist genau die "effektive HP", die der Baerchi mit seiner alten DEF
-- hatte. Der AncientBaerchi (600 HP / 35% DEF) haelt mit 923 HP und ohne DEF
-- exakt so viele Treffer aus wie vorher; der YellowBaerchi (90 HP / 3% DEF)
-- kommt auf 93 und bleibt die Glaskanone, die er war. Die Reihenfolge der
-- Baerchis untereinander ist dadurch unveraendert geblieben, nur die Zahl auf
-- der Karte ist groesser.
--
-- Ein Rest bleibt: DEF wuchs frueher zusaetzlich mit dem LEVEL (+0.5% je
-- Level). Dieser Anteil ist ersatzlos weg, hohe Level sind also relativ
-- etwas zerbrechlicher als vorher. Ausgeglichen wurde das an den PIT-Gegnern
-- (siehe CombatConfig) statt hier — sonst wuerde jeder Baerchi HP bekommen,
-- die im PvP spaeter niemand haben soll.

-- ============================================================
-- v14: PFADE UND PFAD-PROFILE (Mega Egg Tree)
-- ============================================================
-- Jeder Baerchi gehoert zu einem Pfad. Ein Pfad ist KEIN Upgrade, sondern
-- ein Spielziel, mit echtem Preis:
--
--   Gold      das STAERKSTE Pet   hohe HP und ATK        niedrige SPD, mittleres Legen
--   Kristall  das SCHNELLSTE Pet  hohe SPD und PWR,      niedrige HP (Glaskanone)
--                                 schnelles Legen
--   Void      das SELTENSTE Pet   legt seltenere Eier,   schwacher Kampf, langsames Legen
--                                 Eier steigen auf
--   Kosmos    Allrounder          Mischung, hoechste     teuer zu erreichen, nirgends Nr. 1
--                                 Rarity
--   Stamm     Einstieg            —                      —
--
-- Innerhalb EINER Rarity hat kein Pfad das objektiv beste Pet. Geprueft wird
-- das von tools/sim/path_balance.lua (WP6).
--
-- `layUpgradeChance` (nur Void): Chance, dass ein gelegtes Ei eine Stufe
-- hoeher im Baum landet (siehe EggLayService). Das ist die Void-Identitaet.
--
-- eggSource wird seit v14 NICHT mehr von Hand gepflegt: EggConfig berechnet
-- die hatchTables aus Rarity-Verteilung und Pfad-Gewicht und traegt eggSource
-- hier nach. Die Listen unten bleiben deshalb leer.

local BAERCHIS: { [string]: BaerchiDef } = {

	-- ============================================================
	-- COMMON (Stamm)
	-- ============================================================

	RedBaerchi = {
		id = "RedBaerchi", displayName = "Roter Baerchi", rarity = "Common", path = "Stamm",
		baseStats = { hp = 105, atk = 10, spd = 1.0, pwr = 0.10 },
		layIntervalSeconds = 240,
		eggTable = {
			{ eggType = "BasicEgg", weight = 100 },
		},
		defaultSkill = "BasicPunch", eggSource = {},
		description = "Der Klassiker. Zuverlaessig, unaufgeregt.",
	},

	GreenBaerchi = {
		id = "GreenBaerchi", displayName = "Gruener Baerchi", rarity = "Common", path = "Stamm",
		baseStats = { hp = 130, atk = 8, spd = 0.9, pwr = 0.06 },
		layIntervalSeconds = 300,
		eggTable = {
			{ eggType = "BasicEgg", weight = 90 },
			{ eggType = "SugarEgg", weight = 10 },
		},
		defaultSkill = "GummyShield", eggSource = {},
		description = "Etwas zaehlebiger, dafuer langsamer.",
	},

	YellowBaerchi = {
		id = "YellowBaerchi", displayName = "Gelber Baerchi", rarity = "Common", path = "Stamm",
		baseStats = { hp = 93, atk = 12, spd = 1.2, pwr = 0.18 },
		layIntervalSeconds = 270,
		eggTable = {
			{ eggType = "BasicEgg", weight = 85 },
			{ eggType = "SugarEgg", weight = 15 },
		},
		defaultSkill = "SugarRush", eggSource = {},
		description = "Schnell aber zerbrechlich. Glaskanone.",
	},

	-- ============================================================
	-- UNCOMMON (Stamm)
	-- ============================================================

	BlueBaerchi = {
		id = "BlueBaerchi", displayName = "Blauer Baerchi", rarity = "Uncommon", path = "Stamm",
		baseStats = { hp = 156, atk = 14, spd = 1.0, pwr = 0.12 },
		layIntervalSeconds = 330,
		eggTable = {
			{ eggType = "BasicEgg", weight = 65 },
			{ eggType = "SugarEgg", weight = 35 },
		},
		defaultSkill = "IceSlam", eggSource = {},
		description = "Solide in allen Bereichen.",
	},

	OrangeBaerchi = {
		id = "OrangeBaerchi", displayName = "Oranger Baerchi", rarity = "Uncommon", path = "Stamm",
		baseStats = { hp = 117, atk = 18, spd = 1.1, pwr = 0.22 },
		layIntervalSeconds = 360,
		eggTable = {
			{ eggType = "BasicEgg", weight = 60 },
			{ eggType = "SugarEgg", weight = 40 },
		},
		defaultSkill = "FireBite", eggSource = {},
		description = "Hoher Schaden, mittlere Ausdauer.",
	},

	-- ============================================================
	-- RARE
	-- ============================================================

	SugarBaerchi = {
		id = "SugarBaerchi", displayName = "Zucker-Baerchi", rarity = "Rare", path = "Stamm",
		baseStats = { hp = 205, atk = 20, spd = 1.2, pwr = 0.20 },
		layIntervalSeconds = 420,
		-- v14: oeffnet beide Wege aus dem Stamm (Gold ueber Golden, Void ueber Nebel).
		eggTable = {
			{ eggType = "BasicEgg",  weight = 15 },
			{ eggType = "SugarEgg",  weight = 60 },
			{ eggType = "GoldenEgg", weight = 13 },
			{ eggType = "MistEgg",   weight = 12 },
		},
		defaultSkill = "SugarStorm", eggSource = {},
		description = "Smells like candy, hits like a truck.",
	},

	CrystalBaerchi = {
		id = "CrystalBaerchi", displayName = "Kristall-Baerchi", rarity = "Rare", path = "Kristall",
		-- v14: Kristall-Profil (Glaskanone, schnell). Vorher 250 HP / 0.9 SPD.
		baseStats = { hp = 165, atk = 17, spd = 1.45, pwr = 0.34 },
		layIntervalSeconds = 360,
		eggTable = {
			{ eggType = "SugarEgg",   weight = 45 },
			{ eggType = "GoldenEgg",  weight = 35 },
			{ eggType = "CrystalEgg", weight = 20 },
		},
		defaultSkill = "ShardBlast", eggSource = {},
		description = "Scharfkantig und blitzschnell. Zerbricht leicht.",
	},

	-- ============================================================
	-- EPIC
	-- ============================================================

	GoldenGrizzly = {
		id = "GoldenGrizzly", displayName = "Goldener Grizzly", rarity = "Epic", path = "Gold",
		baseStats = { hp = 420, atk = 40, spd = 0.85, pwr = 0.14 },
		layIntervalSeconds = 540,
		eggTable = {
			{ eggType = "SugarEgg",    weight = 15 },
			{ eggType = "GoldenEgg",   weight = 62 },
			{ eggType = "PlatinumEgg", weight = 15 },
			{ eggType = "CrystalEgg",  weight = 8 },
		},
		defaultSkill = "GoldRush", eggSource = {},
		description = "Selten, maechtig, und weiss es.",
	},

	VoidBaerchi = {
		id = "VoidBaerchi", displayName = "Void-Baerchi", rarity = "Epic", path = "Void",
		-- v14: Void-Profil (schwacher Kampf, seltene Eier). Vorher 278/45/1.4/0.30.
		baseStats = { hp = 290, atk = 32, spd = 1.05, pwr = 0.24 },
		layIntervalSeconds = 600,
		layUpgradeChance = 0.08,
		eggTable = {
			{ eggType = "SugarEgg", weight = 15 },
			{ eggType = "MistEgg",  weight = 55 },
			{ eggType = "VoidEgg",  weight = 20 },
			{ eggType = "GoldenEgg", weight = 10 },
		},
		defaultSkill = "BlackHole", eggSource = {},
		description = "Kommt aus dem Nichts. Verschwindet genauso.",
	},

	-- ============================================================
	-- LEGENDARY
	-- ============================================================

	RainbowBaerchi = {
		id = "RainbowBaerchi", displayName = "Regenbogen-Baerchi", rarity = "Legendary", path = "Kristall",
		baseStats = { hp = 440, atk = 54, spd = 1.5, pwr = 0.42 },
		layIntervalSeconds = 540,
		eggTable = {
			{ eggType = "GoldenEgg",    weight = 26 },
			{ eggType = "CrystalEgg",   weight = 55 },
			{ eggType = "PrismEgg",     weight = 15 },
			{ eggType = "AscensionEgg", weight = 4 },
		},
		defaultSkill = "ChromaBlast", eggSource = {},
		description = "Jede Farbe. Jede Kraft.",
	},

	AncientBaerchi = {
		id = "AncientBaerchi", displayName = "Uralter Baerchi", rarity = "Legendary", path = "Gold",
		baseStats = { hp = 1000, atk = 56, spd = 0.85, pwr = 0.08 },
		layIntervalSeconds = 660,
		eggTable = {
			{ eggType = "GoldenEgg",    weight = 30 },
			{ eggType = "PlatinumEgg",  weight = 50 },
			{ eggType = "SunEgg",       weight = 12 },
			{ eggType = "CrystalEgg",   weight = 5 },
			{ eggType = "AscensionEgg", weight = 3 },
		},
		defaultSkill = "TitanMode", eggSource = {},
		description = "War schon da bevor Gummies erfunden wurden.",
	},

	-- ============================================================
	-- MYTHIC
	-- ============================================================

	CosmicBaerchi = {
		-- v14: Anzeigename "Sternen-Baerchi" (die Rarity heisst jetzt Cosmic),
		-- die ID bleibt wegen bestehender Spielstaende.
		id = "CosmicBaerchi", displayName = "Sternen-Baerchi", rarity = "Mythic", path = "Kosmos",
		baseStats = { hp = 1100, atk = 80, spd = 1.25, pwr = 0.26 },
		layIntervalSeconds = 900,
		eggTable = {
			{ eggType = "PlatinumEgg",  weight = 25 },
			{ eggType = "PrismEgg",     weight = 25 },
			{ eggType = "VoidEgg",      weight = 25 },
			{ eggType = "CrystalEgg",   weight = 15 },
			{ eggType = "AscensionEgg", weight = 10 },
		},
		defaultSkill = "BigBang", eggSource = {},
		description = "Ein Stueck Sternenhimmel mit Fell.",
	},

	PhoenixBaerchi = {
		id = "PhoenixBaerchi", displayName = "Phoenix-Baerchi", rarity = "Mythic", path = "Gold",
		baseStats = { hp = 2100, atk = 142, spd = 0.85, pwr = 0.16 },
		layIntervalSeconds = 840,
		eggTable = {
			{ eggType = "PlatinumEgg",  weight = 40 },
			{ eggType = "SunEgg",       weight = 45 },
			{ eggType = "ZenithEgg",    weight = 10 },
			{ eggType = "AscensionEgg", weight = 5 },
		},
		defaultSkill = "PhoenixRebirth", eggSource = {},
		description = "Faellt einmal. Steht immer wieder auf.",
	},

	GlacierBaerchi = {
		id = "GlacierBaerchi", displayName = "Gletscher-Baerchi", rarity = "Mythic", path = "Kristall",
		baseStats = { hp = 880, atk = 84, spd = 1.6, pwr = 0.44 },
		layIntervalSeconds = 660,
		eggTable = {
			{ eggType = "CrystalEgg",   weight = 25 },
			{ eggType = "PrismEgg",     weight = 45 },
			{ eggType = "AuroraEgg",    weight = 25 },
			{ eggType = "AscensionEgg", weight = 5 },
		},
		defaultSkill = "GlacierFrost", eggSource = {},
		description = "Wo er hinschaut, wird alles langsam.",
	},

	PhantomBaerchi = {
		id = "PhantomBaerchi", displayName = "Phantom-Baerchi", rarity = "Mythic", path = "Void",
		baseStats = { hp = 980, atk = 70, spd = 1.05, pwr = 0.20 },
		layIntervalSeconds = 960,
		layUpgradeChance = 0.25,
		eggTable = {
			{ eggType = "MistEgg",      weight = 10 },
			{ eggType = "VoidEgg",      weight = 45 },
			{ eggType = "ShadowEgg",    weight = 40 },
			{ eggType = "AscensionEgg", weight = 5 },
		},
		defaultSkill = "PhantomOmen", eggSource = {},
		description = "Man sieht ihn kaum. Seine Eier schon.",
	},

	-- ============================================================
	-- DIVINE
	-- ============================================================

	SeraphBaerchi = {
		id = "SeraphBaerchi", displayName = "Seraph-Baerchi", rarity = "Divine", path = "Gold",
		baseStats = { hp = 2900, atk = 170, spd = 0.85, pwr = 0.18 },
		layIntervalSeconds = 1020,
		eggTable = {
			{ eggType = "SunEgg",       weight = 40 },
			{ eggType = "ZenithEgg",    weight = 50 },
			{ eggType = "CometEgg",     weight = 5 },
			{ eggType = "AscensionEgg", weight = 5 },
		},
		defaultSkill = "SeraphGrace", eggSource = {},
		description = "Sechs Fluegel, ein Herz aus Honig.",
	},

	NorthernLightBaerchi = {
		id = "NorthernLightBaerchi", displayName = "Polarlicht-Baerchi", rarity = "Divine", path = "Kristall",
		baseStats = { hp = 1450, atk = 128, spd = 1.65, pwr = 0.48 },
		layIntervalSeconds = 780,
		eggTable = {
			{ eggType = "PrismEgg",     weight = 30 },
			{ eggType = "AuroraEgg",    weight = 60 },
			{ eggType = "CometEgg",     weight = 5 },
			{ eggType = "AscensionEgg", weight = 5 },
		},
		defaultSkill = "AuroraVeil", eggSource = {},
		description = "Tanzt ueber den Himmel, schneller als das Auge.",
	},

	EclipseBaerchi = {
		id = "EclipseBaerchi", displayName = "Eklipse-Baerchi", rarity = "Divine", path = "Void",
		baseStats = { hp = 1650, atk = 104, spd = 1.05, pwr = 0.22 },
		layIntervalSeconds = 1140,
		layUpgradeChance = 0.12,
		eggTable = {
			{ eggType = "ShadowEgg",    weight = 45 },
			{ eggType = "AbyssEgg",     weight = 45 },
			{ eggType = "CometEgg",     weight = 5 },
			{ eggType = "AscensionEgg", weight = 5 },
		},
		defaultSkill = "EclipseShroud", eggSource = {},
		description = "Wenn er auftaucht, wird es mitten am Tag dunkel.",
	},

	-- ============================================================
	-- COSMIC (Kosmos)
	-- ============================================================

	CometBaerchi = {
		id = "CometBaerchi", displayName = "Kometen-Baerchi", rarity = "Cosmic", path = "Kosmos",
		baseStats = { hp = 3800, atk = 205, spd = 1.25, pwr = 0.30 },
		layIntervalSeconds = 1140,
		eggTable = {
			{ eggType = "ZenithEgg",    weight = 15 },
			{ eggType = "AuroraEgg",    weight = 15 },
			{ eggType = "AbyssEgg",     weight = 15 },
			{ eggType = "CometEgg",     weight = 45 },
			{ eggType = "NovaEgg",      weight = 5 },
			{ eggType = "AscensionEgg", weight = 5 },
		},
		defaultSkill = "CometImpact", eggSource = {},
		description = "Kommt mit einem Knall. Bleibt mit einem Krater.",
	},

	NebulaBaerchi = {
		id = "NebulaBaerchi", displayName = "Nebula-Baerchi", rarity = "Cosmic", path = "Kosmos",
		baseStats = { hp = 3600, atk = 195, spd = 1.3, pwr = 0.34 },
		layIntervalSeconds = 1140,
		eggTable = {
			{ eggType = "AbyssEgg",     weight = 20 },
			{ eggType = "CometEgg",     weight = 55 },
			{ eggType = "NovaEgg",      weight = 20 },
			{ eggType = "AscensionEgg", weight = 5 },
		},
		defaultSkill = "NebulaBurn", eggSource = {},
		description = "Ein Fell aus Sternenstaub, der brennt.",
	},

	PulsarBaerchi = {
		id = "PulsarBaerchi", displayName = "Pulsar-Baerchi", rarity = "Cosmic", path = "Kosmos",
		baseStats = { hp = 3700, atk = 200, spd = 1.3, pwr = 0.30 },
		layIntervalSeconds = 1140,
		eggTable = {
			{ eggType = "AuroraEgg",    weight = 20 },
			{ eggType = "CometEgg",     weight = 55 },
			{ eggType = "NovaEgg",      weight = 20 },
			{ eggType = "AscensionEgg", weight = 5 },
		},
		defaultSkill = "PulsarPulse", eggSource = {},
		description = "Tickt wie eine Uhr. Jeder Schlag lauter.",
	},

	-- ============================================================
	-- SECRET (Kosmos)
	-- ============================================================

	ShadeBaerchi = {
		id = "ShadeBaerchi", displayName = "Schemen-Baerchi", rarity = "Secret", path = "Kosmos",
		baseStats = { hp = 6200, atk = 310, spd = 1.35, pwr = 0.32 },
		layIntervalSeconds = 1320,
		eggTable = {
			{ eggType = "CometEgg",     weight = 30 },
			{ eggType = "NovaEgg",      weight = 55 },
			{ eggType = "GalaxyEgg",    weight = 10 },
			{ eggType = "AscensionEgg", weight = 5 },
		},
		defaultSkill = "ShadeSlash", eggSource = {},
		description = "Niemand hat ihn je ganz gesehen.",
	},

	RiddleBaerchi = {
		id = "RiddleBaerchi", displayName = "Raetsel-Baerchi", rarity = "Secret", path = "Kosmos",
		baseStats = { hp = 6400, atk = 295, spd = 1.3, pwr = 0.36 },
		layIntervalSeconds = 1320,
		eggTable = {
			{ eggType = "CometEgg",     weight = 20 },
			{ eggType = "NovaEgg",      weight = 60 },
			{ eggType = "GalaxyEgg",    weight = 15 },
			{ eggType = "AscensionEgg", weight = 5 },
		},
		defaultSkill = "RiddleBeam", eggSource = {},
		description = "Beantwortet jede Frage mit einer neuen.",
	},

	-- ============================================================
	-- GODLY (Kosmos)
	-- ============================================================

	TitanBaerchi = {
		id = "TitanBaerchi", displayName = "Titanen-Baerchi", rarity = "Godly", path = "Kosmos",
		baseStats = { hp = 11500, atk = 480, spd = 1.2, pwr = 0.30 },
		layIntervalSeconds = 1500,
		eggTable = {
			{ eggType = "NovaEgg",      weight = 45 },
			{ eggType = "GalaxyEgg",    weight = 50 },
			{ eggType = "AscensionEgg", weight = 5 },
		},
		defaultSkill = "TitanFist", eggSource = {},
		description = "Traegt Berge, als waeren es Gummibaerchen.",
	},

	GenesisBaerchi = {
		id = "GenesisBaerchi", displayName = "Genesis-Baerchi", rarity = "Godly", path = "Kosmos",
		baseStats = { hp = 10500, atk = 440, spd = 1.35, pwr = 0.36 },
		layIntervalSeconds = 1500,
		eggTable = {
			{ eggType = "NovaEgg",      weight = 40 },
			{ eggType = "GalaxyEgg",    weight = 55 },
			{ eggType = "AscensionEgg", weight = 5 },
		},
		defaultSkill = "GenesisWave", eggSource = {},
		description = "Am Anfang war der Baerchi.",
	},

	-- ============================================================
	-- ETERNAL (Kosmos)
	-- ============================================================

	ChronosBaerchi = {
		id = "ChronosBaerchi", displayName = "Chronos-Baerchi", rarity = "Eternal", path = "Kosmos",
		baseStats = { hp = 18500, atk = 690, spd = 1.4, pwr = 0.34 },
		layIntervalSeconds = 1800,
		eggTable = {
			{ eggType = "NovaEgg",      weight = 30 },
			{ eggType = "GalaxyEgg",    weight = 65 },
			{ eggType = "AscensionEgg", weight = 5 },
		},
		defaultSkill = "ChronosRift", eggSource = {},
		description = "Kommt immer genau rechtzeitig.",
	},

	InfinityBaerchi = {
		id = "InfinityBaerchi", displayName = "Unendlichkeits-Baerchi", rarity = "Eternal", path = "Kosmos",
		baseStats = { hp = 18000, atk = 660, spd = 1.45, pwr = 0.38 },
		layIntervalSeconds = 1800,
		eggTable = {
			{ eggType = "NovaEgg",      weight = 25 },
			{ eggType = "GalaxyEgg",    weight = 70 },
			{ eggType = "AscensionEgg", weight = 5 },
		},
		defaultSkill = "InfinityBarrage", eggSource = {},
		description = "Hoert nie auf. Wirklich nie.",
	},

	-- ============================================================
	-- OMEGA (Kosmos)
	-- ============================================================

	OmegaBaerchi = {
		id = "OmegaBaerchi", displayName = "Omega-Baerchi", rarity = "Omega", path = "Kosmos",
		baseStats = { hp = 31500, atk = 1050, spd = 1.5, pwr = 0.40 },
		layIntervalSeconds = 2100,
		eggTable = {
			{ eggType = "GalaxyEgg",    weight = 90 },
			{ eggType = "AscensionEgg", weight = 10 },
		},
		defaultSkill = "OmegaStrike", eggSource = {},
		description = "Der letzte Baerchi. Danach kommt nichts mehr.",
	},
}

--------------------------------------------------------------------------------
-- Progression (Level-Cap, Stat-Wachstum, XP-Kurve)
--------------------------------------------------------------------------------

local MAX_LEVEL = 50

-- Stat-Wachstum pro Level — die Zahlen dahinter wendet CombatCalculator an.
--
-- HP und ATK wachsen EXPONENTIELL: jedes Level gibt +10% auf den Wert des
-- vorherigen Levels, also stat = basis * 1.1^(level-1). Das ist auf Level 10
-- das 2,4-fache, auf Level 20 das 6,1-fache und auf Level 50 (Cap) das
-- 106-fache des Grundwerts. Die PIT-Gegner skalieren mit derselben Kurve
-- mit, sonst waere ab Level 15 jede Stage trivial.
--
-- SPD und PWR wachsen bewusst NICHT mit 10%, sondern klein und linear.
--
-- Beide sind Werte, bei denen ein Prozentwachstum entgleist: SPD ist die
-- Angriffsgeschwindigkeit (die rundenbasierte Simulation wertet sie aktuell
-- noch gar nicht aus), und PWR multipliziert den Skill-Schaden, der seinerseits
-- schon am exponentiell wachsenden ATK haengt — 10% pro Level darauf waere
-- exponentielles Wachstum auf exponentiellem Wachstum.
--
-- Auf Level 50 macht das +0.98 SPD und +0.147 PWR. Der Loewenanteil beider
-- Werte kommt also weiterhin vom Baerchi selbst und von seinen Stat-Stufen
-- (PromotionConfig), nicht vom Level.
local STAT_GROWTH_PER_LEVEL = 0.10
local SPD_PER_LEVEL         = 0.02
local PWR_PER_LEVEL         = 0.003

-- XP-Kurve: benoetigte XP um von `level` auf `level + 1` zu kommen.
--
-- Bewusst flach am Anfang: bis Level 6-7 soll ein Baerchi sehr schnell
-- kommen (zusammen ca. 730 XP), damit man frueh mehrere PIT-Stages am Stueck
-- schafft. Danach zieht die Kurve exponentiell an und wird zum Idle-Ziel.
-- XP gibt es NICHT mehr aus Kaempfen, sondern nur noch ueber Honig
-- (siehe HoneyService) — die Kurve haengt also direkt an der
-- Honig-Produktion der Gebaeude.
local XP_CURVE_BASE   = 60
local XP_CURVE_FACTOR = 1.28

local function xpForNextLevel(level: number): number
	return math.floor(XP_CURVE_BASE * math.pow(XP_CURVE_FACTOR, math.max(level, 1) - 1))
end

-- Paket 9 (FeatureFlags.ENDLESS): Endless-Level ueber Level 50 hinaus.
-- Zaehlt nur auf MAX_LEVEL, bleibt ueber Rebirths (RebirthService setzt nur
-- level/xp zurueck) und kommt aus Honig-XP (sobald Final 100 geschafft ist)
-- und aus jeder 10. Endless-Stage. +1 Endless-Level wirkt wie +1 Level
-- (CombatCalculator) und ist im Tower-Modell etwa +2 Endless-Stages wert.
-- Faktor per tools/sim/progression_pacing.lua abgestimmt.
local ENDLESS_XP_BASE   = 340     -- x xpForNextLevel(MAX_LEVEL)
local ENDLESS_XP_FACTOR = 1.02

local function xpForEndlessLevel(endlessLevel: number): number
	return math.floor(xpForNextLevel(MAX_LEVEL) * ENDLESS_XP_BASE * math.pow(ENDLESS_XP_FACTOR, math.max(endlessLevel, 0)))
end

--------------------------------------------------------------------------------
-- Rarity-Kette (Grundlage der Fusions-Regel)
--------------------------------------------------------------------------------

local RARITY_ORDER: { Types.Rarity } = {
	"Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic",
	"Divine", "Cosmic", "Secret", "Godly", "Eternal", "Omega",
}

-- Eine Farbe pro Rarity — benutzt von BEIDEN Seiten:
-- Server faerbt damit die Baerchi-Parts auf der Insel,
-- Client faerbt damit Rahmen, Badges und Karten im UI.
-- Deshalb hier und nicht im Client-Theme: sonst laufen die Farben auseinander.
local RARITY_COLORS: { [Types.Rarity]: Color3 } = {
	Common    = Color3.fromRGB(176, 190, 204),   -- Grau-Blau
	Uncommon  = Color3.fromRGB( 76, 217, 100),   -- Gruen
	Rare      = Color3.fromRGB( 46, 155, 255),   -- Blau
	Epic      = Color3.fromRGB(168,  85, 247),   -- Lila
	Legendary = Color3.fromRGB(255, 176,  32),   -- Gold
	Mythic    = Color3.fromRGB(255,  59, 107),   -- Pink-Rot
	Divine    = Color3.fromRGB(255, 244, 190),   -- Himmlisches Hellgold
	Cosmic    = Color3.fromRGB( 92,  72, 255),   -- Tiefes Indigo
	Secret    = Color3.fromRGB( 30,  34,  48),   -- Fast-Schwarz
	Godly     = Color3.fromRGB( 40, 235, 220),   -- Tuerkis-Leuchten
	Eternal   = Color3.fromRGB(255, 120,  40),   -- Gluehendes Orange
	Omega     = Color3.fromRGB(255, 255, 255),   -- Weiss
}

local function getRarityColor(rarity: Types.Rarity): Color3
	return RARITY_COLORS[rarity] or RARITY_COLORS.Common
end

--------------------------------------------------------------------------------
-- Mutation (ersetzt seit v11 das binaere Inverted-System)
--------------------------------------------------------------------------------

-- Ein MUTIERTER Baerchi ist derselbe Baerchi, nur durchweg besser — genau wie
-- vorher Inverted. Neu ist die STUFUNG: acht Stufen statt einem einzigen
-- Bonus, jede mit eigenem Multiplikator, eigener Farbe und eigener Seltenheit
-- (Vorbild: das Mutations-System aus "Steal a Brainrot"). Wie bei Inverted
-- ist es KEINE eigene Rarity und KEINE eigene Art: jeder configId kann jede
-- Stufe tragen, die Rarity bleibt dabei unveraendert.
--
-- ANNAHME, nicht vom Projektinhaber vorgegeben (Zahlen/Farben/Namen sind mein
-- Entwurf aus DESIGN_VORSCHLAG_TRENDANALYSE_2026-09-11.md, Abschnitt 3):
--
--   * `multiplier` ist der Anteil, um den HP/ATK/EGG steigen (multiplier - 1
--     als Bonus, siehe getMutationBonus) — SPD/PWR bekommen davon nur ein
--     Drittel, aus demselben Grund wie frueher bei INVERTED_BONUS (sie
--     multiplizieren sich bereits mit anderen Werten).
--   * `weight` ist ein Gewicht in einem Wurf ueber ALLE Stufen PLUS einem
--     riesigen "keine Mutation"-Gewicht (siehe rollMutation) — kein Wurf pro
--     Stufe einzeln. Die Summe aus allen Gewichten (inkl. "keine Mutation")
--     ist absichtlich eine runde Million, damit die Prozentzahlen unten
--     nachrechenbar bleiben.
--   * Celestial und Candy teilen sich denselben Multiplikator (4x), genau wie
--     Lava und Galaxy (6x) — das ist Absicht: zwei kosmetisch verschiedene
--     "Geschmacksrichtungen" derselben Machtstufe, kein Tippfehler.
--   * Rainbow bekommt eine einzelne repraesentative Farbe statt eines
--     echten Farbwechsels — ein zyklisches ColorSequence/Tween-Rainbow waere
--     ein separater Studio-Effekt und ist hier bewusst NICHT mit umgesetzt.
--
-- Wer andere Zahlen will: alles Balancing steckt ausschliesslich in dieser
-- Tabelle, nirgendwo sonst im Code.
export type MutationDef = {
	id          : Types.MutationId,
	displayName : string,
	badge       : string,    -- kurzes Kuerzel fuers Namensschild, z.B. "[GOLD]"
	multiplier  : number,    -- 1.25 = +25% auf HP/ATK/EGG (siehe getMutationBonus)
	color       : Color3,
	weight      : number,    -- Gewicht im Gesamtwurf (siehe rollMutation)
}

-- Reihenfolge = Seltenheits-/Staerke-Kette, genau wie RARITY_ORDER bei Rarity.
-- FusionService.pickHigherMutation vergleicht Baerchis ueber den Index hier.
local MUTATION_ORDER: { Types.MutationId } = {
	"Gold", "Diamond", "Bloodrot", "Celestial", "Candy", "Lava", "Galaxy", "Rainbow",
}

local MUTATIONS: { [Types.MutationId]: MutationDef } = {
	Gold = {
		id = "Gold", displayName = "Gold", badge = "[GOLD]",
		multiplier = 1.25, color = Color3.fromRGB(255, 215, 0), weight = 10000,
	},
	Diamond = {
		id = "Diamond", displayName = "Diamond", badge = "[DIA]",
		multiplier = 1.50, color = Color3.fromRGB(120, 224, 255), weight = 3000,
	},
	Bloodrot = {
		id = "Bloodrot", displayName = "Bloodrot", badge = "[BLOOD]",
		multiplier = 2.00, color = Color3.fromRGB(139, 0, 0), weight = 1200,
	},
	Celestial = {
		id = "Celestial", displayName = "Celestial", badge = "[CEL]",
		multiplier = 4.00, color = Color3.fromRGB(147, 112, 219), weight = 400,
	},
	Candy = {
		id = "Candy", displayName = "Candy", badge = "[CANDY]",
		multiplier = 4.00, color = Color3.fromRGB(255, 105, 180), weight = 300,
	},
	Lava = {
		id = "Lava", displayName = "Lava", badge = "[LAVA]",
		multiplier = 6.00, color = Color3.fromRGB(255, 69, 0), weight = 70,
	},
	Galaxy = {
		id = "Galaxy", displayName = "Galaxy", badge = "[GAL]",
		multiplier = 6.00, color = Color3.fromRGB(106, 27, 154), weight = 25,
	},
	Rainbow = {
		id = "Rainbow", displayName = "Rainbow", badge = "[RBW]",
		multiplier = 10.00, color = Color3.fromRGB(255, 0, 170), weight = 5,
	},
}

-- Gewicht des "gar keine Mutation"-Falls im Gesamtwurf (siehe rollMutation).
-- Zusammen mit den Gewichten oben ergibt das genau 1_000_000 — macht die
-- Gesamtchance auf IRGENDEINE Mutation genau 15_000 / 1_000_000 = 1.5%.
local NO_MUTATION_WEIGHT = 985000

-- Wuerfelt EINMAL ueber alle acht Stufen plus "keine Mutation" und gibt die
-- getroffene Stufe zurueck (nil = keine). Bewusst EIN Wurf und nicht "erst
-- pruefen OB, dann WELCHE": das mischt Gesamtchance und Stufen-Verteilung in
-- einer einzigen, leicht nachrechenbaren Tabelle, genau wie EggConfig.rollEggType
-- es fuer Ei-Typen macht.
--
-- Bewusst hier und nicht in EggService: die Chancen sind ein Konfig-Wert,
-- EggService ruft nur auf (dieselbe Aufteilung wie vorher bei rollInverted).
local function rollMutation(): Types.MutationId?
	local total = NO_MUTATION_WEIGHT
	for _, id in MUTATION_ORDER do
		total += MUTATIONS[id].weight
	end

	local roll = math.random() * total
	local cumulative = NO_MUTATION_WEIGHT

	if roll < cumulative then
		return nil
	end

	for _, id in MUTATION_ORDER do
		cumulative += MUTATIONS[id].weight
		if roll < cumulative then
			return id
		end
	end

	return nil   -- sollte durch Rundungsfehler praktisch nie erreicht werden
end

-- Wuerfelt eine Mutation OHNE die Moeglichkeit "keine": das Ergebnis ist
-- garantiert eine der acht Stufen, verteilt nach denselben Gewichten wie in
-- rollMutation (Gold am haeufigsten, Rainbow am seltensten).
--
-- Gebraucht vom Mutations-Sturm-Event (siehe EventConfig und
-- EventParticipationService): dort ist die Frage OB schon durch die
-- Event-Chance beantwortet, hier geht es nur noch um WELCHE Stufe. Mit
-- rollMutation waere das Ergebnis auch dann in 98.5% der Faelle nil und das
-- ganze Event praktisch wirkungslos.
local function rollMutationTier(): Types.MutationId
	local total = 0
	for _, id in MUTATION_ORDER do
		total += MUTATIONS[id].weight
	end

	local roll = math.random() * total
	local cumulative = 0

	for _, id in MUTATION_ORDER do
		cumulative += MUTATIONS[id].weight
		if roll < cumulative then
			return id
		end
	end

	-- Nur durch Rundungsfehler erreichbar: die haeufigste Stufe.
	return MUTATION_ORDER[1]
end

-- Die Fellfarbe/Leuchtfarbe einer Mutations-Stufe. Server (Figur auf der
-- Insel) und Client (Rahmen und Badges im UI) benutzen dieselbe Funktion —
-- genau wie bei getRarityColor, aus demselben Grund: zwei getrennte
-- Berechnungen laufen beim naechsten Farbwechsel auseinander.
--
-- nil (keine Mutation) gibt es hier bewusst nicht: der Aufrufer weiss selbst,
-- ob er ueberhaupt eine Farbe braucht (siehe `if baerchi.mutation then ...`
-- an jeder Aufrufstelle) — eine Fallback-Farbe hier waere eine zweite,
-- unnoetige Fallunterscheidung.
local function getMutationColor(mutation: Types.MutationId): Color3
	return MUTATIONS[mutation].color
end

local function getMutationDisplayName(mutation: Types.MutationId): string
	return MUTATIONS[mutation].displayName
end

local function getMutationBadge(mutation: Types.MutationId): string
	return MUTATIONS[mutation].badge
end

-- Der reine Multiplikator ("x1.25", "x10") fuer die Anzeige. 1.0 fuer nil
-- (keine Mutation) — dadurch kann ein Aufrufer immer damit multiplizieren,
-- ohne vorher auf nil zu pruefen.
local function getMutationMultiplier(mutation: Types.MutationId?): number
	if not mutation then
		return 1.0
	end
	return MUTATIONS[mutation].multiplier
end

-- Was eine Mutation an den vier Basiswerten PLUS Ei-Tempo aendert, als Anteil
-- (0.25 = +25%) — direkt einsetzbar wie zuvor INVERTED_BONUS.
--
-- HP/ATK/EGG bekommen den vollen Multiplikator-Anteil, SPD/PWR nur ein
-- Drittel davon — siehe Kommentar-Kopf, derselbe Grund wie beim alten
-- INVERTED_BONUS (hp/atk/egg = 15%, spd/pwr = 5%, exakt Faktor 3).
--
-- nil (keine Mutation) gibt einen Nullbonus zurueck — Aufrufer koennen das
-- Ergebnis deshalb IMMER anwenden, ohne vorher auf nil zu pruefen (siehe
-- CombatCalculator.getEffectiveStats).
local function getMutationBonus(mutation: Types.MutationId?): { hp: number, atk: number, spd: number, pwr: number, egg: number }
	local extra = getMutationMultiplier(mutation) - 1.0
	return {
		hp  = extra,
		atk = extra,
		spd = extra / 3,
		pwr = extra / 3,
		egg = extra,
	}
end

-- Index in MUTATION_ORDER (1 = Gold, ... 8 = Rainbow). 0 fuer nil (keine
-- Mutation) — dadurch ist "keine Mutation" garantiert die niedrigste Stufe
-- in jedem Vergleich, ohne dass der Aufrufer nil gesondert behandeln muss.
local function getMutationRank(mutation: Types.MutationId?): number
	if not mutation then
		return 0
	end
	for index, id in MUTATION_ORDER do
		if id == mutation then
			return index
		end
	end
	return 0
end

-- Die hoehere der beiden Mutationen (fuer FusionService, "das Bessere
-- gewinnt" — dieselbe Linie wie Regel A/B, nur jetzt gestuft statt binaer).
-- Bei Gleichstand (z.B. beide nil, oder beide dieselbe Stufe) gewinnt `a`.
local function pickHigherMutation(a: Types.MutationId?, b: Types.MutationId?): Types.MutationId?
	if getMutationRank(b) > getMutationRank(a) then
		return b
	end
	return a
end

-- v14: Fusion erhoeht die Rarity NICHT mehr (Wunsch des Projektinhabers:
-- "Fusionen sollen nur die Stats mergen"). Die fruehere Konstante
-- FUSION_MYTHIC_RESULT ist entfallen — Mythics fallen jetzt aus Eiern.

-- v14: die Pfade, in Anzeige-Reihenfolge, mit Farbe und Ziel. Server und
-- Client nutzen dieselbe Tabelle (Ei-Baum-Panel, Index, Panel-Badges).
local PATHS: { { id: Types.PathId, color: Color3, goal: string } } = {
	{ id = "Stamm",     color = Color3.fromRGB(238, 214, 170), goal = "start" },
	{ id = "Gold",      color = Color3.fromRGB(255, 196,  60), goal = "strong" },
	{ id = "Kristall",  color = Color3.fromRGB(120, 220, 255), goal = "fast" },
	{ id = "Void",      color = Color3.fromRGB(150,  90, 230), goal = "rare" },
	{ id = "Kosmos",    color = Color3.fromRGB( 92,  72, 255), goal = "all" },
	{ id = "Ascension", color = Color3.fromRGB(196, 128, 255), goal = "rebirth" },
	-- v17: Sonder-Eier aus Events (kein Baerchi hat diesen Pfad)
	{ id = "Event",     color = Color3.fromRGB(255, 214,  60), goal = "event" },
}

local function getPathColor(path: string?): Color3
	for _, p in PATHS do
		if p.id == path then return p.color end
	end
	return PATHS[1].color
end

local function getRarityIndex(rarity: Types.Rarity): number
	for i, r in RARITY_ORDER do
		if r == rarity then
			return i
		end
	end
	return 1
end

-- Naechsthoehere Rarity — nil wenn schon am Ende der Kette (Mythic)
local function getNextRarity(rarity: Types.Rarity): Types.Rarity?
	local idx = getRarityIndex(rarity)
	return RARITY_ORDER[idx + 1]
end

--------------------------------------------------------------------------------
-- Hilfsfunktionen fuer Services
--------------------------------------------------------------------------------

local function getById(id: string): BaerchiDef?
	return BAERCHIS[id]
end

local function getByRarity(rarity: Types.Rarity): { BaerchiDef }
	local result: { BaerchiDef } = {}
	for _, def in BAERCHIS do
		if def.rarity == rarity then
			table.insert(result, def)
		end
	end
	-- Deterministische Reihenfolge: die Iteration ueber eine Hash-Tabelle
	-- ist in Luau nicht garantiert stabil, ein Gacha-Roll darf davon nicht abhaengen.
	table.sort(result, function(a, b)
		return a.id < b.id
	end)
	return result
end

local function getByEggSource(eggType: Types.EggType): { BaerchiDef }
	local result: { BaerchiDef } = {}
	for _, def in BAERCHIS do
		for _, source in def.eggSource do
			if source == eggType then
				table.insert(result, def)
				break
			end
		end
	end
	table.sort(result, function(a, b)
		return a.id < b.id
	end)
	return result
end

return {
	data         = BAERCHIS,
	MAX_LEVEL    = MAX_LEVEL,

	STAT_GROWTH_PER_LEVEL = STAT_GROWTH_PER_LEVEL,
	SPD_PER_LEVEL         = SPD_PER_LEVEL,
	PWR_PER_LEVEL         = PWR_PER_LEVEL,

	MUTATIONS      = MUTATIONS,
	MUTATION_ORDER = MUTATION_ORDER,

	rollMutation            = rollMutation,
	rollMutationTier        = rollMutationTier,
	getMutationColor        = getMutationColor,
	getMutationDisplayName  = getMutationDisplayName,
	getMutationBadge        = getMutationBadge,
	getMutationMultiplier   = getMutationMultiplier,
	getMutationBonus        = getMutationBonus,
	getMutationRank         = getMutationRank,
	pickHigherMutation      = pickHigherMutation,

	RARITY_ORDER  = RARITY_ORDER,
	RARITY_COLORS = RARITY_COLORS,
	PATHS         = PATHS,
	getPathColor  = getPathColor,

	getRarityColor = getRarityColor,
	xpForNextLevel = xpForNextLevel,
	ENDLESS_XP_BASE   = ENDLESS_XP_BASE,
	ENDLESS_XP_FACTOR = ENDLESS_XP_FACTOR,
	xpForEndlessLevel = xpForEndlessLevel,
	getRarityIndex = getRarityIndex,
	getNextRarity  = getNextRarity,
	getById        = getById,
	getByRarity    = getByRarity,
	getByEggSource = getByEggSource,
}
