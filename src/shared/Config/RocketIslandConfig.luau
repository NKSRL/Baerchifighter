--!strict
-- RocketIslandConfig.luau
-- ReplicatedStorage/Config/RocketIslandConfig.luau
--
-- Einzige Zustaendigkeit:
--   - Maße, Farben und Text-Schluessel der dauerhaften Raketen-Insel in Welt 1 (P4, 20.10.):
--     kleine Bruecke -> Mini-Insel -> Rakete auf Startrampe + Hinweisschild "Welt 2".
--
-- Nur Hinweis + Deko. Gestartet wird die Rakete weiter ausschliesslich im Epilog (A7).
-- Nichts davon gehoert in MapConfig (steht bei 192/200 lokalen Namen).
-- Schalter: FeatureFlags.ROCKET_ISLAND.

local RocketIslandConfig = {}

-- 20.10. (Welt 1, Paket 2, Entscheidung des Spielleiters): JEDER Spieler hat seine EIGENE Raketen-Insel, von der Mitte
-- nach aussen: Event-Pit, Spieler-Plot, Fight-Pit (Arena-Insel), Rakete. Die Insel liegt auf der Achse des Plots, hinter
-- der Arena-Insel, mit derselben Luecke wie die uebrigen Stege (ISLAND_GAP) und einer Bruecke vom Arena-Rand.
-- Sie gehoert zum Plot-Model des Spielers (entsteht und vergeht mit ihm).
-- Anker (optional, pro Slot): Part "RaketenAnker_<slot>" im Workspace gibt die Mitte vor (ersetzt die berechnete Lage).
RocketIslandConfig.ANCHOR_NAME = "RaketenAnker"
RocketIslandConfig.GAP_FROM_ARENA = 34             -- Wasserluecke Arena-Rand -> Raketen-Insel-Rand (Studs), wie ISLAND_GAP
RocketIslandConfig.PLACEHOLDER_ANGLE_DEG = 22.5   -- ALT (P4, eine Insel zwischen zwei Plots); nicht mehr benutzt
-- Entdeckung (Paket 2): Annaeherung an die Insel-Mitte auf <= DISCOVER_DISTANCE Studs. Einmalig, der Server prueft
-- die Position (JourneyService, Aktion "island") und merkt es in journey.islandSeen (optionales Feld, keine Migration).
RocketIslandConfig.DISCOVER_DISTANCE = 40
RocketIslandConfig.ISLAND_RADIUS = 12
RocketIslandConfig.MIN_GAP_FROM_MAIN = 10          -- ALT (P4); jetzt gilt GAP_FROM_ARENA
RocketIslandConfig.PLATFORM_RADIUS_SAFETY = 8      -- Mindest-Luft zu Nachbar-Inseln (Rules.clearanceToIslands)

-- Old-School-Boden der Mini-Insel (gleiche Funktion wie die Hauptinsel, kleinere Kacheln)
RocketIslandConfig.GROUND_LEVELS = { 8, 4, 2 }
RocketIslandConfig.GROUND_MARGIN = 0.5

RocketIslandConfig.COLORS = {
	rocketWhite = Color3.fromRGB(240, 240, 236),
	rocketRed   = Color3.fromRGB(214, 70, 64),
	window      = Color3.fromRGB(255, 232, 80),   -- Neon-Gelb
	ramp        = Color3.fromRGB(150, 130, 100),  -- Holzbraun
	rampMetal   = Color3.fromRGB(120, 124, 134),
	sign        = Color3.fromRGB(160, 112, 66),
	signPost    = Color3.fromRGB(116, 80, 48),
	gold        = Color3.fromRGB(255, 196, 60),
	rock        = Color3.fromRGB(128, 136, 148),
	lamp        = Color3.fromRGB(255, 214, 120),
}

RocketIslandConfig.ROCKET_HEIGHT = 18
RocketIslandConfig.ROCKET_RADIUS = 3.4
RocketIslandConfig.PART_BUDGET = 60
RocketIslandConfig.GLOW_PERIOD = 3     -- Sekunden
RocketIslandConfig.GLOW_AMOUNT = 0.10  -- +-10 %

-- Text-Schluessel (WorldText/Strings: world.rocket.*)
RocketIslandConfig.TEXT = {
	locked   = "world.rocket.locked",
	ready    = "world.rocket.ready",
	launched = "world.rocket.launched",
	progress = "world.rocket.progress",
}

-- Zustaende (Debug "rocketisland set 1|2|3")
RocketIslandConfig.STATE_LOCKED   = 1
RocketIslandConfig.STATE_READY    = 2
RocketIslandConfig.STATE_LAUNCHED = 3

-- Namen im Workspace/Platform
RocketIslandConfig.NAME_PREFIX = "RocketIsland_"

return RocketIslandConfig
