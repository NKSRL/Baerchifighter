--!strict
-- CombConfig.luau
-- ReplicatedStorage/Config/CombConfig.luau
--
-- Einzige Zustaendigkeit:
--   - Alle Zahlen und Masse fuer Honigwaben im Event-Pit und fuer den
--     Waben-Recycler auf dem Plot.
--
-- ============================================================
-- DIE IDEE
-- ============================================================
-- Das Event-Pit ist die ganze Zeit begehbar, aber zwischen den Events passiert
-- dort nichts, und wer seinen Baerchi losgeschickt hat, wartet nur. Deshalb
-- liegen im Pit Honigwaben herum:
--
--   * Wer darueber laeuft, hebt sie auf. Sie stapeln sich ueber seinem Kopf.
--   * Jede Wabe macht ihn INNERHALB des Pits ein Stueck langsamer (SLOW_*).
--     Verlaesst er das Pit, laeuft er wieder normal — das Gewicht ist ein
--     Risiko im Pit, keine Dauerstrafe.
--   * Betritt er seine EIGENE Insel, gibt er den Stapel ab. Die Waben
--     wandern in die Warteschlange des Recyclers, der sie nach und nach in
--     Gummies verwandelt — auch waehrend der Spieler schon wieder in der
--     Mitte sammelt.
--   * Der Recycler laesst sich mit Gummies ausbauen: mehr Gummies pro Wabe und
--     schnellere Verarbeitung.
--
-- Die Waben sind KEIN Spielstand: was ein Spieler gerade traegt, geht beim
-- Tod oder Verlassen verloren. Nur die Warteschlange des Recyclers wird
-- gespeichert (IslandData.recycler).
--
-- BALANCE-HINWEIS: ein voller Stapel (MAX_CARRY) bringt auf Recycler-Level 1
-- etwa 75 Gummies, auf Level 10 etwa 6.000, auf Level 60 rund 1,4 Mio (vor dem
-- Rebirth-Multiplikator). Zum Vergleich: Tower I zahlt auf Stage 1 10 Gummies
-- (TowerConfig). Die Ausbaukosten kommen aus EconomyConfig.HONEY_UPGRADE_COSTS,
-- dieselbe Kurve wie bei den Honig-Gebaeuden (v15: Level 1-60).

local EconomyConfig = require(script.Parent.EconomyConfig)
local MapConfig     = require(script.Parent.MapConfig)

local CombConfig = {}

--------------------------------------------------------------------------------
-- Waben im Event-Pit: Entstehen
--------------------------------------------------------------------------------

-- Sekunden zwischen zwei neuen Waben, solange FREIE Slots da sind (Serverstart,
-- Limit eines Wabenthemas gestiegen, ein Spawn hat keinen Platz gefunden).
CombConfig.SPAWN_INTERVAL_SECONDS = 1.2

-- SLOT-ZAHL: so viele Waben gibt es hoechstens gleichzeitig — im Pit, auf
-- Koepfen getragen und in der Respawn-Warteschlange zusammen. Mehr liegen auch
-- nie im Pit. Haelt die Zahl der Teile klein und macht Waben knapp.
CombConfig.MAX_WORLD_COMBS = 40

--------------------------------------------------------------------------------
-- Waben im Event-Pit: Respawn (Slot-Modell)
--------------------------------------------------------------------------------
-- Eine aufgehobene Wabe behaelt ihren Slot (Besitzer = Spieler). Erst wenn sie
-- im Recycler abgegeben wird, kommt sie nach RESPAWN_DELAY_SECONDS an einer
-- freien Stelle im Pit zurueck. Der Wabenfluss haengt damit an der Abgabe-Rate.

-- Sekunden zwischen Abgabe und neuer Wabe im Pit.
CombConfig.RESPAWN_DELAY_SECONDS = 20

-- Hook: verkuerzt der Recycler-Level den Respawn? Faktor pro Level ueber 1
-- (1 = nein, 0.9 = je Level 10 % kuerzer). Absichtlich 1, Entscheidung offen.
CombConfig.RECYCLER_DELAY_FACTOR = 1

-- Geht ein Stapel verloren (Tod, Verlassen, neuer Charakter), werden seine
-- Slots nach dieser Zeit frei und die Waben kommen ins Pit zurueck.
CombConfig.ORPHAN_RELEASE_SECONDS = 60

-- Sicherheitsnetz: liegen weniger als MIN_WORLD_COMBS im Pit, kommt trotzdem
-- alle MIN_TRICKLE_SECONDS eine dazu (auch ueber die Slot-Zahl hinaus, aber nie
-- ueber das Limit im Pit), damit Neulinge nie ein leeres Pit sehen.
CombConfig.MIN_WORLD_COMBS     = 8
CombConfig.MIN_TRICKLE_SECONDS = 6

-- Takt der Respawn-Pruefung (ein Loop, kein Thread pro Wabe).
CombConfig.RESPAWN_TICK_SECONDS = 0.25

-- Beim Serverstart liegen schon so viele da, damit das Pit nicht leer wirkt.
CombConfig.INITIAL_COMBS = 24

-- Ringfoermiger Streifen um die Pit-Mitte, in dem Waben entstehen (Studs).
-- Innen bleibt die Mitte frei (Deko), aussen der Zaun (Radius 50).
CombConfig.SPAWN_RADIUS_MIN = 8
CombConfig.SPAWN_RADIUS_MAX = 44

-- Mindestabstand zwischen zwei Waben beim Entstehen.
CombConfig.SPAWN_MIN_DISTANCE = 4.5

-- Anteil goldener Waben und wie viel sie wert sind (in Wabeneinheiten, eine
-- normale Wabe ist 1).
CombConfig.GOLD_CHANCE = 0.08
CombConfig.GOLD_UNITS  = 5

--------------------------------------------------------------------------------
-- Wabenthemen (je Event, siehe CombService.setTheme)
--------------------------------------------------------------------------------
-- Ein Event kann den Waben im Pit fuer seine Dauer ein THEMA geben: anderes
-- Aussehen, anderer Wert, schnellerer Nachschub, mehr Slots, staerkere
-- Tragebremse. Der Wert wird beim AUFHEBEN festgeschrieben: wer bei
-- Event-Ende noch Lava-Waben traegt, gibt sie als Lava-Waben ab.
--
-- Schluessel = Event-id (EventConfig) bzw. Thema-id. Fehlt ein Eintrag, laeuft
-- das Event mit normalen Waben. Bewusst nur Hot Egg (Lava) und die
-- Wespenkoenigin (Koenigsgelee, Phase 2) — weitere Events koennen spaeter
-- ein Thema bekommen, ohne dass Code dazukommt.
export type CombTheme = {
	bodyColor      : Color3,
	cellColor      : Color3,
	goldBodyColor  : Color3,
	goldCellColor  : Color3,
	bodyMaterial   : Enum.Material,
	cellMaterial   : Enum.Material,
	valueFactor    : number,    -- Einheiten je Wabe (normal 1, Gold GOLD_UNITS) mal diesem Faktor
	spawnRateFactor: number,    -- Nachfuellen freier Slots so viel schneller
	limit          : number,    -- Slot-Zahl waehrend des Themas
	slowPerComb    : number?,   -- Tragebremse je Wabe dieses Themas (sonst SLOW_PER_COMB)
	burstColor     : Color3,    -- Farbe des Funken-Bursts beim Skin-Wechsel
}

CombConfig.THEMES = {
	-- Hot Egg: Vulkan-Waben. Basalt-Platte, glühende Zelle, dreifacher Wert
	-- (Lava-Gold 15), doppelt so schneller Nachschub, 60 Slots, schwerer.
	HotEgg = {
		bodyColor       = Color3.fromRGB( 58,  52,  50),
		cellColor       = Color3.fromRGB(255, 110,  30),
		goldBodyColor   = Color3.fromRGB( 90,  70,  50),
		goldCellColor   = Color3.fromRGB(255, 200,  80),
		bodyMaterial    = Enum.Material.Slate,
		cellMaterial    = Enum.Material.Neon,
		valueFactor     = 3,
		spawnRateFactor = 2,
		limit           = 60,
		slowPerComb     = 0.035,
		burstColor      = Color3.fromRGB(255, 120, 40),
	},
	-- Wespenkoenigin, Phase 2: Koenigsgelee. Cremig-weisse Waben, doppelter
	-- Wert; Slots und Tempo wie normal (der Waben-Regen des Bosses liefert sie).
	WaspQueen = {
		bodyColor       = Color3.fromRGB(250, 238, 200),
		cellColor       = Color3.fromRGB(255, 214,  90),
		goldBodyColor   = Color3.fromRGB(255, 230, 150),
		goldCellColor   = Color3.fromRGB(255, 255, 220),
		bodyMaterial    = Enum.Material.SmoothPlastic,
		cellMaterial    = Enum.Material.Neon,
		valueFactor     = 2,
		spawnRateFactor = 1,
		limit           = 40,
		slowPerComb     = nil,
		burstColor      = Color3.fromRGB(255, 230, 140),
	},
} :: { [string]: CombTheme }

-- Fliegende Waben (Vulkan-Ausbruch, Waben-Regen): Flugzeit und Bogenhoehe.
-- Erst nach der Landung lassen sie sich aufheben.
CombConfig.FLIGHT_SECONDS     = 1.4
CombConfig.FLIGHT_ARC_HEIGHT  = 18
-- Waben-Regen faellt aus dieser Hoehe ueber dem Landepunkt.
CombConfig.RAIN_DROP_HEIGHT   = 45

-- Funken-Burst beim Skin-Wechsel: EIN Emitter in der Pit-Mitte, so viele Funken.
CombConfig.THEME_BURST_COUNT  = 60

function CombConfig.getTheme(themeId: string?): CombTheme?
	if not themeId then return nil end
	return CombConfig.THEMES[themeId]
end

-- Wert einer Wabe in Einheiten (normal/Gold, mal Thema-Faktor).
function CombConfig.getUnits(isGold: boolean, themeId: string?): number
	local base = if isGold then CombConfig.GOLD_UNITS else 1
	local theme = CombConfig.getTheme(themeId)
	return base * (if theme then theme.valueFactor else 1)
end

-- Tragebremse einer Wabe dieses Themas.
function CombConfig.getSlowPerComb(themeId: string?): number
	local theme = CombConfig.getTheme(themeId)
	return if theme and theme.slowPerComb then theme.slowPerComb else CombConfig.SLOW_PER_COMB
end

--------------------------------------------------------------------------------
-- Einsammeln und Tragen
--------------------------------------------------------------------------------

-- Wie oft der Server prueft, wer auf einer Wabe steht.
CombConfig.PICKUP_CHECK_SECONDS = 0.1

-- Horizontaler Abstand zur Wabe, ab dem sie aufgehoben wird (Studs), und wie
-- weit sie hoechstens ueber/unter der Spielfigur liegen darf.
CombConfig.PICKUP_RADIUS     = 3.6
CombConfig.PICKUP_MAX_HEIGHT = 7

-- Wie viele Waben ein Spieler hoechstens traegt. Ist der Stapel voll, bleiben
-- weitere liegen.
CombConfig.MAX_CARRY = 25

--------------------------------------------------------------------------------
-- Tempo im Pit
--------------------------------------------------------------------------------

-- Laufgeschwindigkeit ohne Last. Das Spiel setzt sonst nirgends WalkSpeed,
-- das ist der Roblox-Standard.
CombConfig.BASE_WALK_SPEED = 16

-- Jede getragene Wabe nimmt diesen Anteil der Grundgeschwindigkeit (nicht
-- vom Rest: 25 Waben * 0.025 = 62,5 % weniger, also noch 37,5 %), nie weniger
-- als MIN_SPEED_FACTOR. Gilt NUR innerhalb des Pits.
CombConfig.SLOW_PER_COMB    = 0.025
CombConfig.MIN_SPEED_FACTOR = 0.35

--------------------------------------------------------------------------------
-- Abgabe auf der eigenen Insel
--------------------------------------------------------------------------------

-- Wer naeher als das an der Mitte SEINER Plot-Insel steht, hat die Insel
-- betreten. Etwas kleiner als MapConfig.PLOT_ISLAND_RADIUS (58), damit man
-- wirklich auf dem Gras steht und nicht noch auf dem Rand der Bruecke.
CombConfig.DELIVER_RADIUS = 54

--------------------------------------------------------------------------------
-- Optik der Wabe (Studs)
--------------------------------------------------------------------------------

-- Sechseck mit Umkreisradius R aus drei sich kreuzenden Platten: je 2R lang und
-- R*sqrt(3) breit, um 0, 60 und 120 Grad gedreht. Das ergibt exakt ein
-- regelmaessiges Sechseck, ohne dass dafuer ein Mesh noetig waere.
CombConfig.COMB_RADIUS    = 1.35
CombConfig.COMB_HEIGHT    = 0.55
CombConfig.CELL_RADIUS    = 0.72   -- die dunklere Honigzelle in der Mitte

-- Im Pit liegende Waben sind groesser, damit man sie von weitem sieht.
CombConfig.WORLD_SCALE    = 1.45
CombConfig.WORLD_HOVER    = 1.6    -- Hoehe ueber dem Boden

-- Stapel ueber dem Kopf: Abstand zwischen zwei Waben und Luft ueber dem Kopf.
CombConfig.STACK_STEP     = 0.62
CombConfig.STACK_HEAD_GAP = 0.9
-- Jede Wabe sitzt leicht versetzt/verdreht, damit der Turm wackelig-niedlich
-- aussieht statt wie eine Saeule. Ab der Wabe-Nummer wiederholt sich das Muster.
CombConfig.STACK_WOBBLE_STUDS   = 0.16
CombConfig.STACK_WOBBLE_DEGREES = 14

CombConfig.COMB_COLOR       = Color3.fromRGB(240, 186,  64)
CombConfig.CELL_COLOR       = Color3.fromRGB(214, 128,  28)
CombConfig.GOLD_COMB_COLOR  = Color3.fromRGB(255, 226, 110)
CombConfig.GOLD_CELL_COLOR  = Color3.fromRGB(255, 250, 190)

--------------------------------------------------------------------------------
-- Der Recycler
--------------------------------------------------------------------------------

-- v15: Level 1-60 wie die Honig-Gebaeude (gleiche Look-Stufen, siehe
-- BuildingBehavior.getLook; Faehigkeiten in BuildingBehavior.MILESTONES.Recycler).
CombConfig.RECYCLER_MAX_LEVEL = EconomyConfig.MAX_BUILDING_LEVEL

-- Gummies pro Wabeneinheit (VOR dem Rebirth-Multiplikator), je Recycler-Level.
-- Level 1-10 unveraendert; ab Level 11 waechst der Ertrag mit PAY_GROWTH pro
-- Level weiter (getPayPerUnit).
CombConfig.PAY_PER_UNIT = {
	[1]  = 3,
	[2]  = 5,
	[3]  = 8,
	[4]  = 13,
	[5]  = 21,
	[6]  = 34,
	[7]  = 55,
	[8]  = 90,
	[9]  = 145,
	[10] = 240,
} :: { [number]: number }

-- v15: Zuwachs des Ertrags pro Level ab Level 11 (Level 60 = 240 x 1.12^50 ≈
-- 69.000 je Einheit). ANNAHME, kalibriert mit tools/sim/progression_pacing.lua.
CombConfig.PAY_GROWTH = 1.12

-- Wabeneinheiten pro Sekunde, die der Recycler verarbeitet: Level 1 braucht
-- fuer einen vollen Stapel gut eine Minute, Level 10 ist in unter 10 s durch.
-- v15: danach linear weiter bis SPEED_LEVEL_60 (ein Stapel in ~4 s).
CombConfig.SPEED_LEVEL_1   = 0.4
CombConfig.SPEED_LEVEL_10  = 3.0
CombConfig.SPEED_LEVEL_60  = 6.0

-- Wie lange der Recycler offline hoechstens weiterarbeitet (Sekunden). Es kann
-- ohnehin nur die Warteschlange abgearbeitet werden, der Deckel schuetzt nur vor
-- Zeitmarken aus einer fernen Vergangenheit.
CombConfig.OFFLINE_MAX_SECONDS = 8 * 3600

-- Abstand der Zahlungs-Ticks auf dem Server.
CombConfig.RECYCLER_TICK_SECONDS = 1.0

--------------------------------------------------------------------------------
-- Der Recycler in der Welt (PLOT-LOKAL, siehe Kopf von MapConfig)
--------------------------------------------------------------------------------

-- Ganz vorne auf dem Gras der Plot-Insel: zwischen Wasserkante und Beet, auf der
-- Seite, von der der Spieler aus der Weltmitte kommt (lokales -Z). Das Beet
-- beginnt bei Z = -36, die Insel endet bei Z = -58. X seitlich neben der Bruecke
-- (die liegt auf X = 0), damit man beim Hereinlaufen nicht dagegen stoesst.
CombConfig.RECYCLER_OFFSET = Vector3.new(15, 0, -47)

-- Grosse des unsichtbaren Koerpers (Traeger fuer Name, Schild und Prompt).
CombConfig.RECYCLER_BODY_SIZE = Vector3.new(9, 8, 9)

CombConfig.RECYCLER_NAME = "Recycler"

-- Farbe der Betriebs-Lampe
CombConfig.LAMP_IDLE_COLOR   = Color3.fromRGB(190, 70, 60)
CombConfig.LAMP_ACTIVE_COLOR = Color3.fromRGB(90, 235, 110)

local UPRIGHT    = Vector3.new(0, 0, 90)
local WOOD       = Color3.fromRGB(160, 110, 65)
local WOOD_DARK  = Color3.fromRGB(118,  80,  46)
local METAL      = Color3.fromRGB(150, 152, 158)
local METAL_DARK = Color3.fromRGB( 96,  99, 106)
local GREEN      = Color3.fromRGB( 84, 178,  96)

-- Aussehen (Gebaeude-lokal, wie MapConfig.BUILDING_DECOR: Ursprung = Mitte der
-- Grundflaeche, +Y oben, -Z zur Weltmitte). Ein Trichter, in den die Waben
-- fallen, ein Maschinenkasten mit gruenem Recycling-Band, ein Auslaufrohr nach
-- vorne und die Betriebs-Lampe. "Lampe" wird vom Builder gefaerbt.
CombConfig.RECYCLER_DECOR = {
	{ name = "Sockel",     shape = Enum.PartType.Block,    size = Vector3.new(9.0, 1.2, 9.0),  offset = Vector3.new(0, 0.60, 0),     color = METAL_DARK, material = Enum.Material.Metal, solid = true },
	{ name = "Kasten",     shape = Enum.PartType.Block,    size = Vector3.new(7.0, 4.4, 7.0),  offset = Vector3.new(0, 3.40, 0),     color = WOOD,       material = Enum.Material.Wood, solid = true },
	{ name = "BandVorne",  shape = Enum.PartType.Block,    size = Vector3.new(7.2, 1.0, 7.2),  offset = Vector3.new(0, 3.40, 0),     color = GREEN,      material = Enum.Material.SmoothPlastic },
	{ name = "Deckel",     shape = Enum.PartType.Block,    size = Vector3.new(7.6, 0.7, 7.6),  offset = Vector3.new(0, 5.95, 0),     color = WOOD_DARK,  material = Enum.Material.Wood, solid = true },
	{ name = "TrichterU",  shape = Enum.PartType.Cylinder, size = Vector3.new(1.4, 4.2, 4.2),  offset = Vector3.new(0, 6.90, 0),     color = METAL,      material = Enum.Material.Metal, rotation = UPRIGHT, solid = true },
	{ name = "TrichterM",  shape = Enum.PartType.Cylinder, size = Vector3.new(1.4, 5.6, 5.6),  offset = Vector3.new(0, 8.10, 0),     color = METAL,      material = Enum.Material.Metal, rotation = UPRIGHT, solid = true },
	{ name = "TrichterO",  shape = Enum.PartType.Cylinder, size = Vector3.new(1.2, 7.0, 7.0),  offset = Vector3.new(0, 9.30, 0),     color = METAL,      material = Enum.Material.Metal, rotation = UPRIGHT, solid = true },
	{ name = "Fuellung",   shape = Enum.PartType.Cylinder, size = Vector3.new(0.3, 5.8, 5.8),  offset = Vector3.new(0, 9.85, 0),     color = Color3.fromRGB(240, 186, 64), material = Enum.Material.Neon, rotation = UPRIGHT },
	{ name = "Rohr",       shape = Enum.PartType.Cylinder, size = Vector3.new(3.0, 1.5, 1.5),  offset = Vector3.new(0, 2.40, -4.9), color = METAL_DARK, material = Enum.Material.Metal, rotation = Vector3.new(0, 90, 0) },
	{ name = "Lampe",      shape = Enum.PartType.Ball,     size = Vector3.new(1.3, 1.3, 1.3),  offset = Vector3.new(-2.4, 6.9, -2.4), color = Color3.fromRGB(190, 70, 60), material = Enum.Material.Neon },
} :: { MapConfig.DecorPiece }

-- v15: Look-Zusaetze des Recyclers (Platzhalter bis Prompt 4), Regeln wie
-- MapConfig.BUILDING_LOOK_DECOR: gebaut wird RECYCLER_DECOR plus alle Zusaetze
-- bis zum aktuellen Look (getDecor). Gleiche Look-Stufen wie die Gebaeude.
local GOLD_TRIM  = Color3.fromRGB(255, 205,  70)
local GLOW_GREEN = Color3.fromRGB(110, 255, 150)
local CRYSTAL    = Color3.fromRGB(150, 225, 255)
local PENNANT    = Color3.fromRGB(220,  70,  60)

CombConfig.RECYCLER_LOOK_DECOR = {
	[2] = {
		{ name = "L2Stab",     shape = Enum.PartType.Block,    size = Vector3.new(0.3, 3.0, 0.3),  offset = Vector3.new(-4.1, 1.50,  4.1), color = WOOD_DARK, material = Enum.Material.Wood },
		{ name = "L2Wimpel",   shape = Enum.PartType.Block,    size = Vector3.new(0.1, 1.0, 1.6),  offset = Vector3.new(-4.1, 2.50,  3.3), color = PENNANT },
	},
	[3] = {
		{ name = "L3Goldkante", shape = Enum.PartType.Block,   size = Vector3.new(9.4, 0.3, 9.4),  offset = Vector3.new(0, 1.35, 0), color = GOLD_TRIM, material = Enum.Material.Neon },
	},
	[4] = {
		{ name = "L4Krone",    shape = Enum.PartType.Cylinder, size = Vector3.new(0.5, 7.6, 7.6),  offset = Vector3.new(0, 10.15, 0), color = GOLD_TRIM, material = Enum.Material.Metal, rotation = UPRIGHT },
	},
	[5] = {
		{ name = "L5Glut1",    shape = Enum.PartType.Block,    size = Vector3.new(0.2, 3.6, 5.0),  offset = Vector3.new( 3.6, 3.40, 0), color = GLOW_GREEN, material = Enum.Material.Neon },
		{ name = "L5Glut2",    shape = Enum.PartType.Block,    size = Vector3.new(0.2, 3.6, 5.0),  offset = Vector3.new(-3.6, 3.40, 0), color = GLOW_GREEN, material = Enum.Material.Neon },
	},
	[6] = {
		{ name = "L6Kristall1", shape = Enum.PartType.Block,   size = Vector3.new(1.2, 2.4, 1.2),  offset = Vector3.new( 3.9, 2.40,  3.9), color = CRYSTAL, material = Enum.Material.Glass, rotation = Vector3.new(0, 45, 0) },
		{ name = "L6Kristall2", shape = Enum.PartType.Block,   size = Vector3.new(1.2, 2.4, 1.2),  offset = Vector3.new(-3.9, 2.40, -3.9), color = CRYSTAL, material = Enum.Material.Glass, rotation = Vector3.new(0, 45, 0) },
	},
} :: { [number]: { MapConfig.DecorPiece } }

-- Grund-Deko + Zusaetze bis zu diesem Look.
function CombConfig.getDecor(look: number): { MapConfig.DecorPiece }
	return MapConfig.combineLookDecor(CombConfig.RECYCLER_DECOR, CombConfig.RECYCLER_LOOK_DECOR, look)
end

-- v15: Faehigkeit "Sammelradius" (BuildingBehavior.MILESTONES.Recycler): ab dem
-- Freischalt-Level hebt der Spieler Waben aus so viel groesserem Abstand auf.
CombConfig.COLLECT_RADIUS_FACTOR = 1.6

--------------------------------------------------------------------------------
-- Rechen-Hilfen (Server UND Client benutzen dieselben, damit Anzeige und
-- Auszahlung nicht auseinanderlaufen)
--------------------------------------------------------------------------------

function CombConfig.clampLevel(level: number): number
	return math.clamp(math.floor(level), 1, CombConfig.RECYCLER_MAX_LEVEL)
end

-- Gummies pro Wabeneinheit auf diesem Level, vor dem Rebirth-Multiplikator.
function CombConfig.getPayPerUnit(level: number): number
	local clamped = CombConfig.clampLevel(level)
	local fixed = CombConfig.PAY_PER_UNIT[clamped]
	if fixed then return fixed end
	local last = CombConfig.PAY_PER_UNIT[10] or 1
	return math.floor(last * CombConfig.PAY_GROWTH ^ (clamped - 10) + 0.5)
end

-- Wabeneinheiten pro Sekunde: linear Level 1 -> 10, danach linear 10 -> 60.
function CombConfig.getSpeed(level: number): number
	local clamped = CombConfig.clampLevel(level)
	if clamped <= 10 then
		return CombConfig.SPEED_LEVEL_1
			+ (CombConfig.SPEED_LEVEL_10 - CombConfig.SPEED_LEVEL_1) * ((clamped - 1) / 9)
	end
	local span = math.max(1, CombConfig.RECYCLER_MAX_LEVEL - 10)
	return CombConfig.SPEED_LEVEL_10
		+ (CombConfig.SPEED_LEVEL_60 - CombConfig.SPEED_LEVEL_10) * ((clamped - 10) / span)
end

-- Kosten fuer den Ausbau AUF `targetLevel`; nil = es gibt dieses Level nicht.
-- Gleiche Kurve wie die Honig-Gebaeude (EconomyConfig.HONEY_UPGRADE_COSTS).
function CombConfig.getUpgradeCost(targetLevel: number): { gummies: number, goldGummies: number }?
	if targetLevel < 2 or targetLevel > CombConfig.RECYCLER_MAX_LEVEL then return nil end
	return EconomyConfig.HONEY_UPGRADE_COSTS[targetLevel]
end

-- Sekunden zwischen Abgabe und Respawn bei diesem Recycler-Level (Hook, siehe
-- RECYCLER_DELAY_FACTOR; mit Faktor 1 immer RESPAWN_DELAY_SECONDS).
function CombConfig.getRespawnDelay(recyclerLevel: number): number
	local steps = CombConfig.clampLevel(recyclerLevel) - 1
	return CombConfig.RESPAWN_DELAY_SECONDS * (CombConfig.RECYCLER_DELAY_FACTOR ^ steps)
end

-- Was ein VOLLER Stapel normaler Waben auf diesem Level ungefaehr bringt
-- (ohne goldene Waben und ohne Rebirth-Multiplikator). Nur fuer Anzeigen.
function CombConfig.estimateFullStackPay(level: number): number
	return CombConfig.MAX_CARRY * CombConfig.getPayPerUnit(level)
end

return CombConfig
