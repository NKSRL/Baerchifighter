--!strict
-- IncubatorConfig.luau
-- ReplicatedStorage/Config/IncubatorConfig.luau
--
-- Einzige Zustaendigkeit:
--   - Alle Zahlen des Inkubators (Sammel-Update 05.10., Paket 8, Umbau
--     nach Rueckmeldung 05.10.): Plaetze, Brut-Takt je Rarity, Lager pro
--     Platz, Ausbau-Kosten, Aussehen auf dem Plot.
--
-- Die Regeln (wie viele Plaetze, wann fertig, was kostet das Beschleunigen)
-- stehen als reine Funktionen in Modules/IncubatorRules — Server
-- (IncubatorService) und Client (IncubatorPanel/-Controller) rechnen damit.
--
-- Entscheidungen (alle als ANNAHME benannt):
--   * 1 Platz frei ab dem ersten Kampf.
--   * Der ausgeruestete Baerchi kann nicht hinein (er legt schon selbst).
--   * Eier gehen wieder alle sofort auf; das fruehere Brutzeit-Modell (Ei
--     hineinlegen und warten) ist durch den Umbau ersetzt.

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
-- zurueck.
IncubatorConfig.MAX_LEVEL   = 60
IncubatorConfig.COST_FACTOR = 0.6

-- Jedes Level ueber 1 bruetet um diesen Anteil schneller (Level 60: x2,18).
IncubatorConfig.SPEED_PER_LEVEL = 0.02

-- Umbau nach Rueckmeldung 05.10.: in einen Platz kommt ein BAERCHI, der im
-- Takt seiner Rarity zusaetzliche Eier bruetet (aus seiner eigenen
-- Ei-Tabelle, wie beim Legen). Sekunden pro Ei auf Level 1. Seltenere
-- Baerchis brueten schneller UND bessere Eier — der Grund, einen guten
-- Zweit-Baerchi nicht zu verwerten. Zum Vergleich: der ausgeruestete legt
-- alle ~2,5-6 min ein Ei (EggConfig/BaerchiConfig).
IncubatorConfig.BREED_SECONDS_BY_RARITY = {
	Common    = 600,
	Uncommon  = 540,
	Rare      = 480,
	Epic      = 420,
	Legendary = 360,
	Mythic    = 320,
	Divine    = 290,
	Cosmic    = 260,
	Secret    = 240,
	Godly     = 220,
	Eternal   = 200,
	Omega     = 180,
} :: { [string]: number }
IncubatorConfig.BREED_SECONDS_FALLBACK = 600

-- So viele fertige Eier wartet ein Platz, dann pausiert er (wie
-- MAX_UNCOLLECTED_EGGS beim Legen: wer nicht abholt, sammelt nichts an).
IncubatorConfig.STORE_PER_SLOT = 5

-- Offline bruetet der Inkubator gebremst (gleiche Bremse wie das Legen).
-- Der Wert selbst steht in EggConfig.OFFLINE_SLOWDOWN.

-- Server-Takt in Sekunden (ein Durchlauf fuer alle Spieler).
IncubatorConfig.TICK_SECONDS = 5

-- Abholen/Einsetzen nur in der Naehe des Inkubators (Studs, Server prueft).
IncubatorConfig.USE_DISTANCE = 30

-- Aussehen auf dem Plot (Plot-Koordinaten, siehe IncubatorBuilder). Steht
-- auf dem Beet links hinten, wo vorher nichts stand (Paket 8.2, Option 1:
-- der Plot bleibt, der Inkubator fuellt die Flaeche). Teile: Sockel 2 +
-- je Kuppel 3 = hoechstens 20 (PART_BUDGET), dazu je belegtem Platz die
-- verkleinerte Baerchi-Figur (BaerchiMesh, eigenes Modell "Figure_<n>").
IncubatorConfig.LOOK = {
	offset       = Vector3.new(-20, 0, 20),
	baseSize     = Vector3.new(19, 1.2, 12),
	baseColor    = Color3.fromRGB(122, 104, 204),
	trimColor    = Color3.fromRGB(255, 214, 90),
	columns      = 3,
	spacing      = Vector3.new(6, 0, 5.5),
	padSize      = Vector3.new(0.6, 4.2, 4.2),   -- Zylinder (liegend: X = Hoehe)
	padColor     = Color3.fromRGB(80, 70, 140),
	domeSize     = Vector3.new(5, 5, 5),
	domeColor    = Color3.fromRGB(190, 230, 255),
	domeTransparency = 0.55,
	lockedTransparency = 0.85,
	eggSize      = Vector3.new(1.1, 1.5, 1.1),   -- zeigt: Eier warten im Platz
	eggOffset    = Vector3.new(1.3, 0, -1.3),      -- neben der Figur, zur Plot-Mitte
	figureHeight = 2.8,                            -- Figur passt unter die Kuppel
	signDistance = 80,
}
IncubatorConfig.PART_BUDGET = 20

IncubatorConfig.MODEL_NAME = "Incubator"

return IncubatorConfig
