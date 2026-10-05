--!strict
-- IncubatorConfig.luau
-- ReplicatedStorage/Config/IncubatorConfig.luau
--
-- Einzige Zustaendigkeit:
--   - Alle Zahlen des Inkubators (Sammel-Update 05.10., Paket 8): Plaetze,
--     Brutzeiten, Ausbau-Kosten, Beschleunigen, Aussehen auf dem Plot.
--
-- Die Regeln (wie viele Plaetze, wann fertig, was kostet das Beschleunigen)
-- stehen als reine Funktionen in Modules/IncubatorRules — Server
-- (IncubatorService) und Client (IncubatorPanel/-Controller) rechnen damit.
--
-- Entscheidungen aus Abschnitt 11.6 (Standard, alle als ANNAHME benannt):
--   * Basis- und Zucker-Ei bleiben sofort oeffenbar (INSTANT_MAX_TIER = 2,
--     README: "alles ab Stufe Gold nur ueber den Inkubator").
--   * 1 Platz frei ab dem ersten Kampf.
--   * Beschleunigen mit GoldGummies: ja.

local IncubatorConfig = {}

-- Hoechstens so viele sichtbare Plaetze (Kuppeln auf dem Plot).
IncubatorConfig.MAX_SLOTS = 6

-- Plaetze aus dem Ausbau-Level (Level -> Plaetze ab diesem Level).
IncubatorConfig.SLOTS_BY_LEVEL = {
	{ level = 1,  slots = 1 },
	{ level = 10, slots = 2 },
	{ level = 25, slots = 3 },
}

-- +1 Platz ab diesem Rebirth (bleibt danach).
IncubatorConfig.REBIRTH_BONUS_FROM = 2

-- Index-Belohnungen (Pfad fertig) geben weitere Plaetze, siehe
-- IndexRewardConfig.incubatorSlots.

-- Ausbau: Level 1-60 wie die Gebaeude. Kosten = Gebaeude-Kurve
-- (EconomyConfig.HONEY_UPGRADE_COSTS) x COST_FACTOR — eine zweite Geldsenke
-- vor dem Rebirth (Paket 4.4, Entscheidung 11.5). Ein Rebirth setzt das Level
-- zurueck, die Eier in den Plaetzen bleiben.
IncubatorConfig.MAX_LEVEL   = 60
IncubatorConfig.COST_FACTOR = 0.6

-- Jedes Level ueber 1 bruetet um diesen Anteil schneller (Level 60: x2,18).
IncubatorConfig.SPEED_PER_LEVEL = 0.02

-- Brutzeit (Sekunden auf Level 1) nach Stufe des Eis (EggConfig.tier).
-- Basis-Ei 30 s, danach deutlich laenger nach oben. Stufe 0 = Sonder-Eier
-- (UFO-Jackpot). Niedrige Eier schluepfen damit schnell (Paket 6.5,
-- zweite Auslegung von "brueten").
IncubatorConfig.BREW_SECONDS_BY_TIER = {
	[0]  = 120,
	[1]  = 30,
	[2]  = 60,
	[3]  = 180,
	[4]  = 360,
	[5]  = 720,
	[6]  = 1200,
	[7]  = 1800,
	[8]  = 2700,
	[9]  = 3600,
	[10] = 5400,
	[11] = 7200,
} :: { [number]: number }

-- Eier bis zu dieser Stufe duerfen weiter SOFORT geoeffnet werden.
IncubatorConfig.INSTANT_MAX_TIER = 2

-- Beschleunigen: GoldGummies je angefangene Rest-Minute (mind. 1).
IncubatorConfig.SPEEDUP_GOLD_PER_MINUTE = 1

-- Kurz vor dem Schluepfen leuchtet die Kuppel (Client).
IncubatorConfig.GLOW_LAST_SECONDS = 10

-- Aussehen auf dem Plot (Plot-Koordinaten, siehe IncubatorBuilder). Steht
-- auf dem Beet links hinten, wo vorher nichts stand (Paket 8.2, Option 1:
-- der Plot bleibt, der Inkubator fuellt die Flaeche). Teile: Sockel 2 +
-- je Kuppel 3 = hoechstens 20 (PART_BUDGET).
IncubatorConfig.LOOK = {
	offset       = Vector3.new(-20, 0, 20),
	baseSize     = Vector3.new(19, 1.2, 12),
	baseColor    = Color3.fromRGB(122, 104, 204),
	trimColor    = Color3.fromRGB(255, 214, 90),
	columns      = 3,
	spacing      = Vector3.new(6, 0, 5.5),
	padSize      = Vector3.new(0.6, 4.2, 4.2),   -- Zylinder (liegend: X = Hoehe)
	padColor     = Color3.fromRGB(80, 70, 140),
	domeSize     = Vector3.new(4.2, 4.2, 4.2),
	domeColor    = Color3.fromRGB(190, 230, 255),
	domeTransparency = 0.55,
	lockedTransparency = 0.85,
	eggSize      = Vector3.new(1.7, 2.3, 1.7),
	signDistance = 80,
}
IncubatorConfig.PART_BUDGET = 20

IncubatorConfig.MODEL_NAME = "Incubator"

--------------------------------------------------------------------------------
-- INCUBATOR_BREED (Wunsch Projektinhaber 05.10.)
--------------------------------------------------------------------------------
-- Man setzt einen Baerchi in den Inkubator, und er bruetet im Takt seiner
-- Rarity zusaetzliche Eier — zusaetzlich zu denen des ausgeruesteten. Welche
-- Eier: seine eigene eggTable (wie beim Legen), gesperrte Eier rutschen wie
-- beim Legen auf den freien Vorgaenger (EggTree.resolveLaid).
--
-- Takt in Sekunden pro Ei auf Inkubator-Level 1, je Rarity. Hoehere Rarity =
-- schnellerer Takt (und bessere Eier aus der eigenen Tabelle). Der Ausbau
-- beschleunigt wie bisher (SPEED_PER_LEVEL). Bewusst langsamer als das Legen
-- des ausgeruesteten Baerchis (Common legt alle 2,5-3 min): der Inkubator ist
-- ein Zusatz, kein Ersatz. ANNAHME, zum Nachstellen.
IncubatorConfig.BREED_SECONDS_BY_RARITY = {
	Common    = 900,   -- 15 min
	Uncommon  = 840,
	Rare      = 780,
	Epic      = 720,   -- 12 min
	Legendary = 660,
	Mythic    = 600,   -- 10 min
	Divine    = 570,
	Cosmic    = 540,
	Secret    = 510,
	Godly     = 480,   -- 8 min
	Eternal   = 450,
	Omega     = 420,   -- 7 min
} :: { [string]: number }
IncubatorConfig.BREED_DEFAULT_SECONDS = 900

-- Gebruetete Eier fallen neben den Inkubator und werden wie gelegte Eier
-- durch Darueberlaufen eingesammelt. Eigene Obergrenze (zaehlt nicht gegen
-- EggConfig.MAX_UNCOLLECTED_EGGS); offline langsamer und kleiner gedeckelt,
-- wie beim Legen (EggConfig.OFFLINE_SLOWDOWN).
IncubatorConfig.BREED_MAX_LYING        = 8
IncubatorConfig.BREED_OFFLINE_MAX      = 4
-- Abstand der Eier von der Sockel-Mitte (Studs, Bereich) — knapp vor dem Rand.
IncubatorConfig.BREED_DROP_MIN         = 11
IncubatorConfig.BREED_DROP_MAX         = 13
-- Hoehe der Mini-Figur in der Kuppel (Studs).
IncubatorConfig.BREED_FIGURE_HEIGHT    = 2.6

return IncubatorConfig
