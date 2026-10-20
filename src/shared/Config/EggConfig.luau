--!strict
-- EggConfig.luau
-- ReplicatedStorage/Config/EggConfig.luau
--
-- Egg-Typen mit Hatch-Wahrscheinlichkeiten.
-- Getrennt von BaerchiConfig: Egg-Balance != Baerchi-Balance.
-- GachaRoller liest die HatchTable.
--
-- Seit v12 (Ei-Baum Block A) gibt es weder Brutzeiten noch Kaufpreise: ein
-- Ei im Lager wird per Klick sofort geoeffnet, und kein Ei ist im Menue
-- kaufbar. Einzige Ausnahme ist das Basis-Ei beim versteckten Haendler
-- (MERCHANT ganz unten).
--
-- Seit v10 steht hier ausserdem alles, was das EI-LEGEN steuert (Abschnitt
-- ganz unten). Bewusst hier und nicht in einer eigenen Datei: es ist
-- dieselbe Domaene — welche Eier es gibt, woher sie kommen und was aus ihnen
-- schluepft. Was der EINZELNE Baerchi legt (Tempo und Chancen), gehoert
-- dagegen zu ihm und steht in BaerchiConfig.

local Types         = require(script.Parent.Parent.Network.Types)
-- v14: die hatchTables werden aus den Baerchis BERECHNET (Rarity + Pfad).
-- BaerchiConfig kennt EggConfig nicht, es gibt also keinen Ringschluss.
local BaerchiConfig = require(script.Parent.BaerchiConfig)

-- Wahrscheinlichkeiten muessen pro Egg genau 1.0 ergeben.
-- Format: { configId = Gewichtung }  (wird von GachaRoller normalisiert)
export type HatchTable = { [string]: number }

export type EggDef = {
	id          : Types.EggType,
	displayName : string,
	-- v14: BERECHNET aus RARITY_DIST und den Pfaden der Baerchis (siehe
	-- buildHatchTables). In der Tabelle unten steht deshalb nur {}.
	hatchTable  : HatchTable,
	path        : Types.PathId,    -- v14
	parent      : Types.EggType?,  -- v14: Vorgaenger im Baum
	tier        : number,          -- v14: Stufe (1 = Basis ... 11 = Omega), fuer Panel und Vergleiche
	-- Anzeige-Reihenfolge im Ei-Menue (aufsteigend). Ersetzt seit v12 die
	-- Sortierung nach Brutdauer, die es nicht mehr gibt.
	sortOrder   : number,
	description : string,

	-- Farbe des gelegten Eis in der Welt (MapService) und der Anzeige im UI.
	-- Steht hier statt im Client-Theme, weil Server und Client dieselbe Farbe
	-- brauchen — dieselbe Begruendung wie bei BaerchiConfig.RARITY_COLORS.
	color       : Color3,
	shortName   : string,   -- kurze Beschriftung ueber dem gelegten Ei

	-- v17: SONDER-EI ausserhalb des Baums (UFO-Jackpot). Hat keinen
	-- TREE-Eintrag, wird nie freigeschaltet, nie gelegt, nie gepresst und nie
	-- als "hoechstes Ei" oder Sprung-Ei gewaehlt. Man bekommt es nur direkt
	-- (Jackpot) und kann es wie jedes Ei aus dem Lager oeffnen.
	special     : boolean?,

	-- 19.10.: logischer Zweig im Baum ("Left" | "Middle" | "Right"), aus dem Pfad
	-- abgeleitet (BRANCH_OF_PATH). Sonder-Eier haben keinen.
	branch      : string?,
}

--------------------------------------------------------------------------------
-- v14: DER EI-BAUM (Mega Egg Tree)
--------------------------------------------------------------------------------
--
-- STAMM        Basis ──► Zucker ─┬──────────────────────────────┐
--                                │                              │
-- GOLD-PFAD                      ▼                              │
--                             Golden ──► Platin ──► Sonnen ──► Zenit ─────┐
--                                │                                          │
-- KRISTALL-PFAD                  ▼                                          │
--                             Kristall ──► Prisma ──► Aurora ───────────────┤
--                                                                           │
-- VOID-PFAD            Zucker ──► Nebel ──► Void ──► Schatten ──► Abyss ────┤
--                                                                           │
-- KOSMOS-PFAD          (zwei der drei Endeier Zenit / Aurora / Abyss)       ▼
--                                           Komet ──► Nova ──► Galaxie
--
-- ASCENSIONS-PFAD (nur Rebirth)   Ascension ──► Transzendenz ──► Ewigkeit ──► Omega
--
-- Jedes Ei hat:
--   path        Pfad (Types.PathId)
--   parent      Vorgaenger im Baum (nil = Wurzel). Fuer Lege-Fallback und
--               Ei-Presse: "eine Stufe tiefer" ist immer der parent.
--   rarityDist  Rarity-Verteilung in Prozent (jede Zeile = 100). Daraus
--               wird die hatchTable BERECHNET (siehe buildHatchTables) —
--               von Hand gepflegt wird nur noch diese eine Zeile pro Ei.
--
-- Wie ein Knoten frei wird, steht in TREE weiter unten.

local RARITY_DIST: { [Types.EggType]: { [string]: number } } = {
	BasicEgg         = { Common = 70, Uncommon = 25, Rare = 5 },
	SugarEgg         = { Uncommon = 50, Rare = 38, Epic = 12 },
	GoldenEgg        = { Rare = 42, Epic = 45, Legendary = 13 },
	PlatinumEgg      = { Epic = 40, Legendary = 50, Mythic = 10 },
	SunEgg           = { Legendary = 60, Mythic = 33, Divine = 7 },
	ZenithEgg        = { Mythic = 64, Divine = 28, Cosmic = 8 },
	CrystalEgg       = { Epic = 50, Legendary = 42, Mythic = 8 },
	PrismEgg         = { Legendary = 63, Mythic = 30, Divine = 7 },
	AuroraEgg        = { Mythic = 64, Divine = 28, Cosmic = 8 },
	MistEgg          = { Epic = 55, Legendary = 35, Mythic = 10 },
	VoidEgg          = { Legendary = 58, Mythic = 36, Divine = 6 },
	ShadowEgg        = { Mythic = 60, Divine = 32, Cosmic = 8 },
	AbyssEgg         = { Divine = 70, Cosmic = 25, Secret = 5 },
	CometEgg         = { Divine = 50, Cosmic = 40, Secret = 10 },
	NovaEgg          = { Cosmic = 62, Secret = 30, Godly = 8 },
	GalaxyEgg        = { Secret = 72, Godly = 23, Eternal = 5 },
	AscensionEgg     = { Legendary = 85, Mythic = 15 },
	TranscendenceEgg = { Secret = 60, Godly = 38, Eternal = 2 },
	EternityEgg      = { Godly = 80, Eternal = 19, Omega = 1 },
	OmegaEgg         = { Eternal = 70, Omega = 30 },
	-- v17: UFO-Jackpot (Sonder-Ei). Breit gestreut von Epic bis Godly: fuer
	-- Fruehspieler ein Riesensprung, fuer Spaetspieler eine echte Chance auf
	-- ein Late-Game-Pet (Cosmic+ 8 %). Ø ~ Mythic. ANNAHME, eine Zeile.
	UfoJackpotEgg    = { Epic = 30, Legendary = 30, Mythic = 20, Divine = 12, Cosmic = 5, Secret = 2.5, Godly = 0.5 },
}

-- Gewicht eines Baerchis innerhalb seiner Rarity: 3, wenn sein Pfad zum
-- Pfad des Eis passt, sonst 1. Ascensions-Eier sind neutral (alle 1).
local PATH_MATCH_WEIGHT = 3

--------------------------------------------------------------------------------
-- 19.10.: ZWEIGE UND ZWEIGSPRUENGE
--------------------------------------------------------------------------------
-- Der Baum hat drei logische Zweige (siehe UI/EggTreeLayout):
--   Middle  Stamm (Basis, Zucker) + Kosmos (Komet, Nova, Galaxie)
--   Left    Gold + Kristall
--   Right   Void + Ascension
local BRANCH_OF_PATH: { [string]: string } = {
	Stamm = "Middle", Kosmos = "Middle",
	Gold = "Left", Kristall = "Left",
	Void = "Right", Ascension = "Right",
}

-- ZWEIGSPRUNG: ein extrem seltenes Pet in einem Ei eines Zweigs schaltet ein Ei
-- eines ANDEREN Zweigs frei. Die Pets fallen NUR aus ihrem Quell-Ei und dort nur
-- mit `chance` Prozent pro Oeffnung (0,1 = jedes 1000. Ei). Sie fallen aus keinem
-- anderen Ei (auch nicht Komet/Nova/Ufo), sonst waere der Sprung nicht selten.
-- Die Schluessel-Pets des Ziel-Eis stehen in TREE (keyPets) und muessen mit den
-- Pets hier uebereinstimmen.
export type JumpPet = { egg: Types.EggType, pet: string }
export type JumpDef = {
	id     : string,
	from   : string,            -- Zweig, aus dem man springt
	to     : string,            -- Zweig, in den man springt
	target : Types.EggType,     -- Ei, das frei wird
	chance : number,            -- Prozent pro Oeffnung des Quell-Eis
	pets   : { JumpPet },
}
local JUMPS: { JumpDef } = {
	{
		id = "LeftToMiddle", from = "Left", to = "Middle", target = "CometEgg", chance = 0.1,
		pets = {
			{ egg = "ZenithEgg", pet = "PulsarBaerchi" },
			{ egg = "AuroraEgg", pet = "CometBaerchi" },
		},
	},
	-- Rechts -> Mitte: noch kein Pet dafuer (braucht ein eigenes Baerchi).
}

local EGGS: { [Types.EggType]: EggDef } = {

	-- ============================================================
	-- STAMM
	-- ============================================================
	BasicEgg = {
		id = "BasicEgg", displayName = "Basis-Ei", path = "Stamm", parent = nil, tier = 1, sortOrder = 1,
		description = "Ein ganz normales Ei. Was wird wohl raus kommen?",
		color = Color3.fromRGB(125, 215, 165), shortName = "Basis", hatchTable = {},
	},
	SugarEgg = {
		id = "SugarEgg", displayName = "Zucker-Ei", path = "Stamm", parent = "BasicEgg", tier = 2, sortOrder = 2,
		description = "Schmeckt suess. Der Inhalt auch.",
		color = Color3.fromRGB(255, 140, 195), shortName = "Zucker", hatchTable = {},
	},

	-- ============================================================
	-- GOLD-PFAD (stark)
	-- ============================================================
	GoldenEgg = {
		id = "GoldenEgg", displayName = "Goldenes Ei", path = "Gold", parent = "SugarEgg", tier = 3, sortOrder = 3,
		description = "Glitzert verdaechtig. Rare oder besser garantiert.",
		color = Color3.fromRGB(242, 205, 77), shortName = "Gold", hatchTable = {},
	},
	PlatinumEgg = {
		id = "PlatinumEgg", displayName = "Platin-Ei", path = "Gold", parent = "GoldenEgg", tier = 4, sortOrder = 4,
		description = "Schwer wie Blei, wertvoller als Gold.",
		color = Color3.fromRGB(240, 230, 205), shortName = "Platin", hatchTable = {},
	},
	SunEgg = {
		id = "SunEgg", displayName = "Blaze-Ei", path = "Gold", parent = "PlatinumEgg", tier = 5, sortOrder = 5,
		description = "Warm in der Hand. Sehr warm.",
		color = Color3.fromRGB(235, 90, 45), shortName = "Sonne", hatchTable = {},
	},
	ZenithEgg = {
		id = "ZenithEgg", displayName = "Zenit-Ei", path = "Gold", parent = "SunEgg", tier = 6, sortOrder = 6,
		description = "Der hoechste Punkt des Gold-Pfads.",
		color = Color3.fromRGB(245, 112, 84), shortName = "Zenit", hatchTable = {},
	},

	-- ============================================================
	-- KRISTALL-PFAD (schnell)
	-- ============================================================
	CrystalEgg = {
		id = "CrystalEgg", displayName = "Kristall-Ei", path = "Kristall", parent = "GoldenEgg", tier = 4, sortOrder = 7,
		description = "Durchsichtig. Man sieht schon fast was drin ist.",
		color = Color3.fromRGB(110, 185, 240), shortName = "Kristall", hatchTable = {},
	},
	PrismEgg = {
		id = "PrismEgg", displayName = "Frost-Ei", path = "Kristall", parent = "CrystalEgg", tier = 5, sortOrder = 8,
		description = "Bricht das Licht in sieben Farben.",
		color = Color3.fromRGB(125, 185, 240), shortName = "Frost", hatchTable = {},
	},
	AuroraEgg = {
		id = "AuroraEgg", displayName = "Aurora-Ei", path = "Kristall", parent = "PrismEgg", tier = 6, sortOrder = 9,
		description = "Leuchtet wie der Himmel im Norden.",
		color = Color3.fromRGB(140, 220, 150), shortName = "Aurora", hatchTable = {},
	},

	-- ============================================================
	-- VOID-PFAD (selten)
	-- ============================================================
	MistEgg = {
		id = "MistEgg", displayName = "Nebel-Ei", path = "Void", parent = "SugarEgg", tier = 3, sortOrder = 10,
		description = "Fuehlt sich kalt und feucht an.",
		color = Color3.fromRGB(185, 170, 240), shortName = "Nebel", hatchTable = {},
	},
	VoidEgg = {
		id = "VoidEgg", displayName = "Void-Ei", path = "Void", parent = "MistEgg", tier = 4, sortOrder = 11,
		description = "Schwaerzer als schwarz.",
		color = Color3.fromRGB(70, 45, 100), shortName = "Void", hatchTable = {},
	},
	ShadowEgg = {
		id = "ShadowEgg", displayName = "Schatten-Ei", path = "Void", parent = "VoidEgg", tier = 5, sortOrder = 12,
		description = "Wirft keinen Schatten. Es IST einer.",
		color = Color3.fromRGB(70, 66, 92), shortName = "Schatten", hatchTable = {},
	},
	AbyssEgg = {
		id = "AbyssEgg", displayName = "Abyss-Ei", path = "Void", parent = "ShadowEgg", tier = 6, sortOrder = 13,
		description = "Ganz unten. Darunter kommt nichts mehr.",
		color = Color3.fromRGB(20, 85, 140), shortName = "Abyss", hatchTable = {},
	},

	-- ============================================================
	-- KOSMOS-PFAD (Allrounder)
	-- ============================================================
	CometEgg = {
		id = "CometEgg", displayName = "Kometen-Ei", path = "Kosmos", parent = nil, tier = 7, sortOrder = 14,
		description = "Zieht einen Schweif aus Funken hinter sich her.",
		color = Color3.fromRGB(80, 70, 215), shortName = "Komet", hatchTable = {},
	},
	NovaEgg = {
		id = "NovaEgg", displayName = "Nova-Ei", path = "Kosmos", parent = "CometEgg", tier = 8, sortOrder = 15,
		description = "Kurz vor dem Explodieren.",
		color = Color3.fromRGB(122, 66, 200), shortName = "Nova", hatchTable = {},
	},
	GalaxyEgg = {
		id = "GalaxyEgg", displayName = "Galaxie-Ei", path = "Kosmos", parent = "NovaEgg", tier = 9, sortOrder = 16,
		description = "Ein ganzes Universum in einer Schale.",
		color = Color3.fromRGB(115, 65, 205), shortName = "Galaxie", hatchTable = {},
	},

	-- ============================================================
	-- ASCENSIONS-PFAD (nur Rebirth)
	-- ============================================================
	AscensionEgg = {
		id = "AscensionEgg", displayName = "Ascensions-Ei", path = "Ascension", parent = nil, tier = 5, sortOrder = 17,
		description = "Verdient, nicht gekauft. Legendary garantiert.",
		color = Color3.fromRGB(248, 223, 160), shortName = "Ascension", hatchTable = {},
	},
	TranscendenceEgg = {
		id = "TranscendenceEgg", displayName = "Transzendenz-Ei", path = "Ascension", parent = "AscensionEgg", tier = 9, sortOrder = 18,
		description = "Jenseits von allem, was man kaufen kann.",
		color = Color3.fromRGB(205, 200, 245), shortName = "Transz.", hatchTable = {},
	},
	EternityEgg = {
		id = "EternityEgg", displayName = "Ewigkeits-Ei", path = "Ascension", parent = "TranscendenceEgg", tier = 10, sortOrder = 19,
		description = "Es war schon immer da. Es bleibt fuer immer.",
		color = Color3.fromRGB(103, 210, 224), shortName = "Ewigkeit", hatchTable = {},
	},
	OmegaEgg = {
		id = "OmegaEgg", displayName = "Omega-Ei", path = "Ascension", parent = "EternityEgg", tier = 11, sortOrder = 20,
		description = "Das letzte Ei. 30% Omega.",
		color = Color3.fromRGB(115, 60, 170), shortName = "Omega", hatchTable = {},
	},

	-- ============================================================
	-- SONDER-EIER (v17, nicht im Baum)
	-- ============================================================
	UfoJackpotEgg = {
		id = "UfoJackpotEgg", displayName = "UFO-Jackpot-Ei", path = "Event", parent = nil, tier = 0, sortOrder = 21,
		description = "Vom UFO abgeworfen. Ein ganz seltener Fund.",
		color = Color3.fromRGB(96, 214, 98), shortName = "Jackpot", hatchTable = {},
		special = true,
	},
}

--------------------------------------------------------------------------------
-- Freischaltung (TREE)
--------------------------------------------------------------------------------
--
-- Ein Knoten wird frei, wenn ALLE Bedingungen gelten:
--   hatch     Vorgaenger-Eier so oft GEOEFFNET (eggTree.hatched). Bei
--             `hatchAnyOf` reicht es, wenn `need` der Eintraege erfuellt sind
--             (Kometen-Ei: zwei der drei Endeier).
--   index     so viele VERSCHIEDENE Baerchis dieser Rarity entdeckt (Index)
--   rebirth   mindestens so viele Rebirths
--
-- Eine Blaupause ersetzt hatch und index, NICHT das Rebirth-Gate.
-- Einmal frei, bleibt ein Knoten frei (auch nach Rebirth).
--
-- Die Hatch-Zahlen sind mit tools/sim/egg_tree_sim.lua gegen die echten
-- Lege-Intervalle bestimmt (siehe Bericht MEGA_EGG_TREE_UMGESETZT): die
-- Platzhalter aus dem Konzept (15, 12, 10, 6 ...) waren so klein, dass der
-- ganze Baum ohne Rebirth-Gates in ~16 Spielstunden frei war — die Eier
-- haetten nie gebremst. Jetzt braucht das Ei-Sammeln etwa die Haelfte bis
-- zwei Drittel der Zeit bis zum jeweiligen Rebirth-Gate, beides zaehlt.

export type HatchReq = { egg: Types.EggType, count: number }
export type TreeNode = {
	hatch      : { HatchReq }?,
	hatchAnyOf : { need: number, of: { HatchReq } }?,
	keyPets    : { string }?,     -- Balance 15.10.: Schluessel-Pet(s), eines davon ziehen = Ei frei
	keyNeed    : number?,         -- wie viele davon (Standard 1)
	index      : { rarity: Types.Rarity, count: number }?,
	rebirth    : number?,
	start      : boolean?,        -- von Anfang an frei
}

local TREE: { [Types.EggType]: TreeNode } = {
	BasicEgg    = { start = true },
	SugarEgg    = { start = true },

	-- Balance 15.10.: ein Ei wird frei, sobald man ein SCHLUESSEL-PET gezogen hat
	-- (keyPets, mindestens keyNeed davon entdeckt). Das Schluessel-Pet stammt aus
	-- dem Vorgaenger-Ei, ist dort klar seltener und legt das neue Ei selbst.
	GoldenEgg   = { keyPets = { "GoldenGrizzly" } },
	MistEgg     = { keyPets = { "VoidBaerchi" } },
	PlatinumEgg = { keyPets = { "AncientBaerchi" } },
	CrystalEgg  = { keyPets = { "RainbowBaerchi" } },
	SunEgg      = { keyPets = { "PhoenixBaerchi" } },
	PrismEgg    = { keyPets = { "GlacierBaerchi" } },
	VoidEgg     = { keyPets = { "PhantomBaerchi" } },
	ZenithEgg   = { keyPets = { "SeraphBaerchi" } },
	AuroraEgg   = { keyPets = { "NorthernLightBaerchi" } },
	ShadowEgg   = { keyPets = { "EclipseBaerchi" } },
	AbyssEgg    = { keyPets = { "NebulaBaerchi" } },

	-- Kometen-Ei: Schluessel-Pets stammen aus Zenit- bzw. Aurora-Ei.
	-- hatchAnyOf dient nur noch als Vorgaenger-Liste (Blaupause, Lege-Fallback).
	CometEgg    = {
		keyPets = { "PulsarBaerchi", "CometBaerchi" },
		hatchAnyOf = { need = 1, of = {
			{ egg = "ZenithEgg", count = 0 },
			{ egg = "AuroraEgg", count = 0 },
			{ egg = "AbyssEgg",  count = 0 },
		} },
	},
	NovaEgg     = { keyPets = { "RiddleBaerchi", "ShadeBaerchi" } },
	GalaxyEgg   = { keyPets = { "TitanBaerchi", "GenesisBaerchi" } },

	AscensionEgg     = { rebirth = 1 },
	TranscendenceEgg = { rebirth = 15 },
	EternityEgg      = { rebirth = 30 },
	OmegaEgg         = { rebirth = 50 },
}

-- Kinder je Ei (fuer Panel und "naechste Stufe"). Kometen-Ei hat keinen
-- parent, haengt im Panel aber an allen drei Endeiern.
local CHILDREN: { [string]: { Types.EggType } } = {}

--------------------------------------------------------------------------------
-- hatchTables BERECHNEN
--------------------------------------------------------------------------------

local JUMP_PET_EGG: { [string]: string } = {}
for _, jump in JUMPS do
	for _, jp in jump.pets do JUMP_PET_EGG[jp.pet] = jp.egg end
end

local function buildHatchTables()
	-- Baerchis je Rarity, deterministisch sortiert.
	local byRarity: { [string]: { any } } = {}
	for id, def in BaerchiConfig.data do
		byRarity[def.rarity] = byRarity[def.rarity] or {}
		table.insert(byRarity[def.rarity], def)
	end
	for _, list in byRarity do
		table.sort(list, function(a, b) return a.id < b.id end)
	end

	for eggId, egg in EGGS do
		local dist = RARITY_DIST[eggId]
		local hatch: HatchTable = {}
		for rarity, percent in dist do
			local pets = byRarity[rarity]
			assert(pets and #pets > 0, "EggConfig: keine Baerchis der Rarity " .. rarity .. " fuer " .. eggId)
			local total = 0
			local weights = {}
			for _, def in pets do
				if JUMP_PET_EGG[def.id] then continue end   -- 19.10.: Sprung-Pets nur aus ihrem Quell-Ei
				local w = 1
				if egg.path ~= "Ascension" and def.path == egg.path then
					w = PATH_MATCH_WEIGHT
				end
				weights[def.id] = w
				total += w
			end
			assert(total > 0, "EggConfig: Rarity " .. rarity .. " hat nur Sprung-Pets (" .. eggId .. ")")
			for id, w in weights do
				hatch[id] = (hatch[id] or 0) + percent * w / total
			end
		end
		-- 19.10.: Sprung-Pets des Quell-Eis mit fester Chance (Prozent) einsetzen
		local jumpTotal = 0
		for _, jump in JUMPS do
			for _, jp in jump.pets do
				if jp.egg == eggId then jumpTotal += jump.chance end
			end
		end
		if jumpTotal > 0 then
			for id, v in hatch do hatch[id] = v * (100 - jumpTotal) / 100 end
			for _, jump in JUMPS do
				for _, jp in jump.pets do
					if jp.egg == eggId then hatch[jp.pet] = jump.chance end
				end
			end
		end
		egg.hatchTable = hatch
		egg.branch = if egg.special then nil else BRANCH_OF_PATH[egg.path]
	end

	-- eggSource der Baerchis nachtragen (frueher von Hand gepflegt).
	for _, def in BaerchiConfig.data do
		table.clear(def.eggSource)
	end
	local eggIds = {}
	for eggId in EGGS do table.insert(eggIds, eggId) end
	table.sort(eggIds, function(a, b) return EGGS[a].sortOrder < EGGS[b].sortOrder end)
	for _, eggId in eggIds do
		for configId in EGGS[eggId].hatchTable do
			local def = BaerchiConfig.data[configId]
			if def then table.insert(def.eggSource, eggId) end
		end
	end

	for eggId, egg in EGGS do
		if egg.parent then
			CHILDREN[egg.parent] = CHILDREN[egg.parent] or {}
			table.insert(CHILDREN[egg.parent], eggId)
		end
	end
	for _, list in CHILDREN do
		table.sort(list, function(a, b) return EGGS[a].sortOrder < EGGS[b].sortOrder end)
	end
end

buildHatchTables()

-- Alle Ei-IDs des BAUMS in Anzeige-Reihenfolge (ohne Sonder-Eier: Baum,
-- Freischaltung, Sprung-Ei und Panel kennen nur diese).
local function getOrderedIds(): { Types.EggType }
	local ids: { Types.EggType } = {}
	for eggId, egg in EGGS do
		if not egg.special then table.insert(ids, eggId) end
	end
	table.sort(ids, function(a, b) return EGGS[a].sortOrder < EGGS[b].sortOrder end)
	return ids
end

local function getChildren(eggType: Types.EggType): { Types.EggType }
	return CHILDREN[eggType] or {}
end

-- Die "naechste Stufe" eines Eis im SELBEN Pfad (Ei-Presse, Lege-Aufstieg).
-- Golden hat zwei Kinder (Platin im eigenen Pfad, Kristall im naechsten):
-- bevorzugt wird das Kind im eigenen Pfad. Fuer Stamm-Eier (Zucker) und
-- Endeier gibt es mehrere bzw. keine — dann entscheidet `preferPath`
-- bzw. es gibt nil.
local function getNextInPath(eggType: Types.EggType, preferPath: string?): Types.EggType?
	local egg = EGGS[eggType]
	if not egg then return nil end
	local kids = CHILDREN[eggType]
	if not kids or #kids == 0 then return nil end
	local want = preferPath or egg.path
	for _, kid in kids do
		if EGGS[kid].path == want then return kid end
	end
	-- Zucker-Ei ohne Wunsch-Pfad: zwei Wege (Gold oder Void), keiner ist "der"
	-- naechste. Der Aufrufer muss einen Pfad angeben.
	return nil
end

--------------------------------------------------------------------------------
-- Ei-Presse (v14)
--------------------------------------------------------------------------------
-- 5 gleiche Eier werden zu 1 Ei der naechsten Stufe im selben Pfad gepresst.
-- Nur, wenn das Ziel-Ei schon freigeschaltet ist, und nie im Ascensions-Pfad
-- (dessen Eier gibt es nur ueber Rebirth-Meilensteine). Beim Zucker-Ei
-- waehlt der Spieler, ob Gold- oder Void-Pfad.
local PRESS = {
	cost          = 5,
	blockedPaths  = { Ascension = true, Event = true },
	-- Playtest 05.10. (Schalter entfernt): Basis-Eier gibt es beim
	-- Haendler unbegrenzt fuer Gummies. Waeren sie pressbar, liesse sich jedes
	-- Gummi-Polster ueber die Presse in immer bessere Eier tauschen.
	blockedEggs   = { BasicEgg = true } :: { [string]: boolean },
}

-- Darf `eggType` gepresst werden? Einzige Regel fuer Server (EggTreeService)
-- und Anzeige (EggTreePanel).
local function canPress(eggType: Types.EggType): boolean
	local egg = EGGS[eggType]
	if not egg or PRESS.blockedPaths[egg.path] then return false end
	if PRESS.blockedEggs[eggType] then return false end
	return true
end

-- Hilfsfunktion: Hatch-Table als normalisierte Gewichtungs-Liste
-- GachaRoller benutzt dies direkt
local function getNormalizedTable(eggType: Types.EggType): { configId: string, weight: number }
	local def = EGGS[eggType]
	assert(def, "EggConfig: unbekannter EggType " .. eggType)

	local total = 0
	for _, w in def.hatchTable do total += w end

	local result = {}
	for id, w in def.hatchTable do
		table.insert(result, { configId = id, weight = w / total })
	end
	return result
end

--------------------------------------------------------------------------------
-- EIER LEGEN
--------------------------------------------------------------------------------
--
-- Der ausgeruestete Baerchi legt regelmaessig ein Ei dort ab, wo er gerade
-- steht. Es bleibt als anklickbares Objekt in der Welt liegen, bis der Spieler
-- es einsammelt — dann landet es in island.eggStock und laesst sich wie ein
-- gekauftes Ei ausbrueten.
--
-- Die Zahlen HIER gelten fuer alle Baerchis. Was ein EINZELNER legt und wie
-- schnell, steht bei ihm in BaerchiConfig (layIntervalSeconds / eggTable).
--
-- ============================================================
-- WARUM DAS LEVEL HIER LINEAR WIRKT UND NICHT EXPONENTIELL
-- ============================================================
-- HP und ATK wachsen mit 1.1^(level-1), auf Level 50 also auf das 106-fache.
-- Das ist dort richtig, weil die PIT-Gegner mit derselben Kurve mitwachsen —
-- es gibt eine Gegenseite.
--
-- Beim Ei-Legen gibt es die nicht. Dieselbe Kurve wuerde bedeuten: ein
-- Level-50-Baerchi legt 106-mal so schnell, also alle zwei bis neun Sekunden.
-- Der individuelle Grundwert jedes Baerchis waere damit bedeutungslos, und die
-- Obergrenze unten waere binnen einer Minute erreicht — die ganze Mechanik
-- liefe leer.
--
-- Deshalb addiert jedes Level hier 10% des GRUNDWERTS statt 10% des Vorwerts:
-- auf Level 50 legt ein Baerchi knapp 6-mal so schnell wie auf Level 1. Das
-- ist spuerbar, laesst die Unterschiede zwischen den Baerchis aber bestehen.
--
-- Wer das doch exponentiell haben will: LAY_LEVEL_GAIN durch
-- CombatCalculator.getLevelGrowth ersetzen — es ist genau eine Zeile in
-- EggCalculator.
local LAY_LEVEL_GAIN = 0.10

-- Was eine EGG-Stat-Stufe bringt (waechst ueber Event-Teilnahme, gedeckelt
-- durch die Rarity — siehe PromotionConfig). Ein Legendary am Cap (24) legt
-- damit knapp dreimal so schnell.
--
-- Die Zahl steht bewusst NICHT in PromotionConfig.STAT_LEVEL_GAIN wie die
-- vier Kampf-Stats: die wirken alle in CombatCalculator, diese hier wirkt
-- ausschliesslich im Ei-System. Sie neben den Kampfwerten abzulegen waere die
-- naechste Stelle, an der jemand beim Balancing am falschen Wert dreht.
local LAY_STAT_LEVEL_GAIN = 0.08

-- Wie viel langsamer offline gelegt wird.
--
-- Die Produktion laeuft weiter, waehrend der Spieler weg ist (dasselbe
-- Zeitstempel-Verfahren wie beim Honig, kein Server-Loop noetig) — aber
-- gebremst. Anwesenheit soll sich lohnen, ohne dass Abwesenheit bestraft wird.
-- Sammel-Update 05.10. (Paket 6.1): 2,5 -> 3,5 (Offline-Rate 40 % -> ca. 29 %).
-- "Man kommt wieder und hat direkt ganz viele Eier. Wozu spielt man dann noch?"
local OFFLINE_SLOWDOWN = 3.5

-- Sammel-Update 05.10. (Paket 6.1): eigene Obergrenze fuers Offline-Legen.
-- Eine reine Prozent-Senkung verlaengert nur die Zeit bis "voll" — ein
-- starker Baerchi fuellt die 12 Plaetze trotzdem ueber Nacht. Offline legt er
-- deshalb hoechstens bis 6 liegende Eier, online weiter bis 12. Liegen schon
-- mehr als 6, kommt offline nichts dazu (es wird nichts weggenommen).
local OFFLINE_MAX_EGGS = 6

-- Sammel-Update 05.10. (Paket 6.5, Annahme "brueten" = LEGEN): niedrige
-- Rarities legen schneller, damit der Anfang nicht zaeh ist. Faktor auf das
-- Grundintervall (BaerchiConfig.layIntervalSeconds), fehlende Rarity = 1.
-- Common 240-300 s -> 144-180 s, Uncommon 330-360 s -> ca. 230-250 s,
-- Rare 360-420 s -> ca. 300-350 s. Ab Epic unveraendert, damit die
-- Freischalt-Zeiten im Ei-Baum (tools/sim/egg_tree_sim.lua) nicht kippen.
-- Balance 15.10.: kein Faktor mehr. Die Lege-Zeit steht direkt je Baerchi in
-- BaerchiConfig (80 s + 20 s pro Rarity-Stufe), kein Extra-Rabatt fuer
-- niedrige Rarities.
local LAY_RARITY_FACTOR: { [string]: number } = {
}

-- Wie viele NICHT eingesammelte Eier gleichzeitig herumliegen duerfen.
--
-- Ist die Grenze erreicht, hoert der Baerchi auf zu legen — genau wie ein
-- volles Honig-Lager die Produktion anhaelt. Laenger wegbleiben bringt also
-- nichts zusaetzlich, und der Plot wird nie zum Ei-Teppich.
local MAX_UNCOLLECTED_EGGS = 12

-- Absolute Untergrenze, egal wie viel Level, Stufen und Charms
-- zusammenkommen. Reines Sicherheitsnetz gegen eine Kombination, an die beim
-- Balancing niemand gedacht hat — kein Balancing-Wert.
local MIN_LAY_INTERVAL_SECONDS = 15

-- Wie weit ein gelegtes Ei seitlich neben dem Baerchi landet (Studs). Ohne
-- diesen Versatz laegen mehrere Eier exakt uebereinander, wenn der Baerchi
-- laenger an derselben Stelle steht.
local LAY_SCATTER_RADIUS = 4.5

-- Groesse des Eis in der Welt. Bewusst klein: es sollen bis zu zwoelf davon
-- auf einem Plot liegen koennen, ohne dass man den Baerchi nicht mehr sieht.
local LAY_EGG_SIZE = Vector3.new(1.7, 2.3, 1.7)

-- Ab welcher Entfernung die Beschriftung ueber einem Ei ausgeblendet wird.
local LAY_LABEL_DISTANCE = 60

-- Gewichtete Ei-Auswahl fuer einen Baerchi.
--
-- `eggTable` kommt aus BaerchiConfig und ist pro Baerchi verschieden. Die
-- Gewichte muessen sich zu nichts Bestimmtem addieren — hier wird normalisiert,
-- damit man in der Config mit runden Zahlen arbeiten kann.
--
-- Gibt nil zurueck, wenn die Tabelle leer oder unbrauchbar ist. Der Aufrufer
-- legt dann kein Ei, statt eines zu erfinden.
local function rollEggType(eggTable: { { eggType: Types.EggType, weight: number } }): Types.EggType?
	local total = 0
	for _, entry in eggTable do
		if entry.weight > 0 then
			total += entry.weight
		end
	end

	if total <= 0 then
		return nil
	end

	local roll        = math.random() * total
	local accumulated = 0

	for _, entry in eggTable do
		if entry.weight > 0 then
			accumulated += entry.weight
			if roll < accumulated then
				return entry.eggType
			end
		end
	end

	-- Rundungsrest: der letzte gueltige Eintrag.
	for i = #eggTable, 1, -1 do
		if eggTable[i].weight > 0 then
			return eggTable[i].eggType
		end
	end
	return nil
end

--------------------------------------------------------------------------------
-- VERSTECKTER BASIS-EI-HAENDLER (v12)
--------------------------------------------------------------------------------
--
-- Die einzige Kaufmoeglichkeit fuer ein Ei im ganzen Spiel. Bewusst ohne
-- Marker, ohne Menue-Eintrag und ohne HUD-Hinweis: die meisten Spieler
-- brauchen ihn nie, weil ihr ausgeruesteter Baerchi Eier legt und nie
-- verwertet werden kann. Er ist ein Notanker, kein Laden.
--
-- Lage: am Rand der Hauptinsel, genau zwischen zwei Plot-Stegen (die Stege
-- liegen bei 0, 45, 90 ... Grad, der Haendler bei 157,5 Grad, also mittig
-- dazwischen). Dort laeuft niemand auf dem Weg zum eigenen Plot vorbei.
-- ANNAHME: der genaue Ort war offen (EI_BAUM_KONZEPT, Abschnitt 12), das ist
-- mein Vorschlag und laesst sich hier mit zwei Zahlen verschieben.
local MERCHANT = {
	eggType          = "BasicEgg" :: Types.EggType,
	priceGummies     = 50,      -- heutiger Basis-Preis, anpassbar
	angleDegrees     = 157.5,   -- Winkel um die Weltmitte (siehe oben)
	radius           = 108,     -- Abstand zur Weltmitte, knapp vor der Sandkante (Inselradius 120)
	promptDistance   = 8,       -- ab hier erscheint "E" am Stand
	-- Der Server prueft die Entfernung zusaetzlich selbst: ein Kauf von weiter
	-- weg wird abgelehnt, egal was der Client behauptet. Etwas groesser als
	-- promptDistance, damit Latenz keinen ehrlichen Kauf scheitern laesst.
	maxBuyDistance   = 14,
}

-- HBB Paket 5 (MAP_V2_MERCHANT): sichtbarer Standort des Haendlers. Auf dem
-- Ring zwischen Event-Pit-Zaun (Radius 50) und Bestenlisten-Tafel (Radius 80,
-- 22,5 Grad), mittig zwischen zwei Stegen (alle 45 Grad, Luecke +-9 Grad):
-- jeder, der zum Event laeuft, kommt daran vorbei. Abstand zur Tafel ca. 59
-- Studs, zum Pit-Zaun ca. 16 Studs. Mit dem Flag aus gilt MERCHANT oben.
-- Das Schild ueber dem Stand zeigt nur ein Ei (Bild, kein Text).
local MERCHANT_V2 = {
	angleDegrees = 67.5,
	radius       = 66,
	signImage    = "rbxassetid://136964848925363",   -- dasselbe Ei wie UI/Icons.egg
	signHeight   = 9,
	signSize     = 5,     -- Studs
}

return {
	data               = EGGS,
	MERCHANT           = MERCHANT,
	MERCHANT_V2        = MERCHANT_V2,
	getNormalizedTable = getNormalizedTable,

	-- v14: Ei-Baum
	RARITY_DIST        = RARITY_DIST,
	PATH_MATCH_WEIGHT  = PATH_MATCH_WEIGHT,
	TREE               = TREE,
	PRESS              = PRESS,
	canPress           = canPress,
	getOrderedIds      = getOrderedIds,
	JUMPS              = JUMPS,
	BRANCH_OF_PATH     = BRANCH_OF_PATH,
	getBranch          = function(eggType: Types.EggType): string?
		local egg = EGGS[eggType]
		return egg and egg.branch
	end,
	getChildren        = getChildren,
	getNextInPath      = getNextInPath,
	isSpecial          = function(eggType: Types.EggType): boolean
		local egg = EGGS[eggType]
		return egg ~= nil and egg.special == true
	end,

	LAY_LEVEL_GAIN           = LAY_LEVEL_GAIN,
	LAY_STAT_LEVEL_GAIN      = LAY_STAT_LEVEL_GAIN,
	OFFLINE_SLOWDOWN         = OFFLINE_SLOWDOWN,
	OFFLINE_MAX_EGGS         = OFFLINE_MAX_EGGS,
	LAY_RARITY_FACTOR        = LAY_RARITY_FACTOR,
	MAX_UNCOLLECTED_EGGS     = MAX_UNCOLLECTED_EGGS,
	MIN_LAY_INTERVAL_SECONDS = MIN_LAY_INTERVAL_SECONDS,
	LAY_SCATTER_RADIUS       = LAY_SCATTER_RADIUS,
	LAY_EGG_SIZE             = LAY_EGG_SIZE,
	LAY_LABEL_DISTANCE       = LAY_LABEL_DISTANCE,

	rollEggType = rollEggType,
}
