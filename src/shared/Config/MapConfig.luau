--!strict
-- MapConfig.luau
-- ReplicatedStorage/Config/MapConfig.luau
--
-- Alle Positionen, Groessen und visuellen Werte fuer die Map.
-- MapService hat keine einzige hardcodierte Zahl.
--
-- ============================================================
-- WELT-AUFBAU: INSELN IM WASSER
-- ============================================================
-- Drei Ringe aus Inseln, alle mit Holzstegen verbunden, rundherum Wasser:
--
--                        (A)
--                         |
--                        [P]
--                         |
--             (A)—[P]— (( C )) —[P]—(A)      8 mal, alle 45 Grad
--                         |
--                        [P]
--                         |
--                        (A)
--
--   (( C ))  Hauptinsel: Spawn, Honigmast, freie Karo-Wiese. Hier landen
--            alle und hier laufen sich alle ueber den Weg.
--   [P]      Plot-Insel: eine pro Spieler, mit dem eigenen Beet, den drei
--            Gebaeuden und dem Honig-Teich.
--   (A)      Arena-Insel: die eigene PIT-Arena, ein Stueck weiter draussen.
--
-- WARUM INSELN STATT EINER PLATTFORM
-- Vorher war alles eine einzige 480 Studs breite Scheibe, auf der die Plots
-- als Rechtecke lagen. Das las sich aus der Spielerkamera als eine grosse
-- gruene Flaeche mit Markierungen darauf — man sah nicht, wo der eigene
-- Bereich anfaengt. Getrennte Inseln beantworten das ohne ein einziges
-- Schild: was zu mir gehoert, ist das, was am Ende MEINES Stegs liegt.
--
-- Alle drei Abstaende sind derselbe Wert (ISLAND_GAP) und damit auch alle
-- Stege gleich lang. Ein Steg ueberbrueckt IMMER genau eine Luecke — es gibt
-- keine zweite Laengen-Zahl mehr, die davon abweichen koennte.
--
-- Die Wiese ist KARIERT (zwei Gruentoene). Gebaut wird nur die helle Haelfte
-- als flache Teile auf der dunklen Inselscheibe; das Raster liegt in
-- Weltkoordinaten, laeuft also ueber alle Inseln durch. Die frueheren
-- Lego-Noppen sind dafuer weg: Noppen UND Karos uebereinander ergeben nur
-- Unruhe, und das Karo ist das, was die Flaeche gliedert.
--
-- ============================================================
-- PLOT-LOKALES KOORDINATENSYSTEM (wichtig!)
-- ============================================================
-- Jeder Plot bekommt in MapService ein eigenes CFrame, das zur Plattform-
-- MITTE schaut. Alle Offsets hier unten sind deshalb LOKAL zu diesem Plot:
--
--     lokales -Z  = Richtung Plattform-Mitte
--     lokales +Z  = nach aussen (Richtung Rand → Bruecke → PIT)
--     lokales +X  = seitlich (rechts, wenn man vom Plot zur Mitte schaut)
--
-- Nur dadurch stehen die Gebaeude bei allen 8 Winkeln richtig herum statt
-- verdreht. Das Y in den Offsets ist eine ZUSATZ-Hoehe ueber dem Plot-Boden;
-- die eigentliche Standhoehe rechnet MapService selbst aus der jeweiligen
-- Teilegroesse aus, damit nichts schwebt oder im Boden steckt.

--------------------------------------------------------------------------------
-- Hauptinsel, Wasser, Karo-Wiese
--------------------------------------------------------------------------------

local CENTER = Vector3.new(0, 0, 0)

-- Oberkante JEDER Insel. Alles andere wird relativ dazu berechnet —
-- die Welt laesst sich damit an einer einzigen Zahl hoch/runter schieben.
local PLATFORM_TOP_Y = 0

-- War 150. Von der eigenen Plot-Insel bis zur Mitte war das ein spuerbar
-- langer Fussmarsch quer ueber die Hauptinsel — genau die Strecke, die am
-- meisten zaehlt, weil man sie bei jedem Ei, jedem Ausruesten und jedem
-- Rebirth-Blick zur Mitte zuruecklegt. 120 kuerzt das um ein Fuenftel, ohne
-- die Hauptinsel eng wirken zu lassen (das Spawn-Pad ist 24 Studs breit,
-- bleibt also weiterhin ein kleiner Punkt darauf).
local PLATFORM_RADIUS = 120

-- Wie dick eine Insel ist. Sie steckt damit sichtbar im Wasser statt wie eine
-- Scheibe darauf zu liegen — bei 16 Studs sieht man von der Kamerahoehe eines
-- Spielers eine richtige Kante, keinen Strich.
local ISLAND_HEIGHT = 16

-- Abstand zwischen zwei Inseln UND damit die Laenge jedes Stegs. Ein Steg
-- ueberbrueckt immer genau eine Luecke, deshalb gibt es nur diese eine Zahl.
-- War 44 (rund drei Sekunden bei WALK_SPEED). 34 bleibt immer noch lang genug,
-- dass die Inseln spuerbar getrennt wirken, kuerzt aber jede der beiden
-- Bruecken pro Weg (Hauptinsel→Plot, Plot→Arena) um gut zwei Sekunden.
local ISLAND_GAP = 34

-- ============================================================
-- KARO-WIESE
-- ============================================================
-- Zwei Gruentoene im Schachbrett. Gebaut werden NUR die hellen Felder als
-- flache Teile — die dunkle Haelfte ist die Inselscheibe selbst. Das halbiert
-- die Teilezahl gegenueber "jedes Feld ein Teil" bei exakt demselben Bild.
--
-- GRASS_TILE gilt fuer die ganze Welt, und das Raster liegt in WELT-
-- Koordinaten mit Ursprung im Weltmittelpunkt: die Karos laufen dadurch ueber
-- alle Inseln durch, statt auf jeder neu anzusetzen. Nur die Plot-Beete
-- rastern plot-lokal (siehe unten) — sonst laege das Karo auf einem gedrehten
-- Beet schief.
--
-- 24 Studs sind bewusst gross: bei 12 wirkt die Wiese aus der Spielerkamera
-- wie ein Muster statt wie Felder, und die Teilezahl vervierfacht sich.
--
-- Das Beet auf der Plot-Insel rastert FEINER (PLOT_GRASS_TILE). Es ist die
-- Flaeche, auf der man selbst steht und auf die man die ganze Zeit schaut;
-- 24er-Felder waeren darauf nur drei Reihen und wuerden gar nicht mehr als
-- Karo lesen. Dieselbe Ueberlegung wie bei einem Teppich gegenueber einer
-- Wiese. 72 / 18 geht glatt auf, es bleibt kein Reststreifen an einer Kante.
local GRASS_TILE      = 24
local PLOT_GRASS_TILE = 18
local GRASS_HEIGHT    = 0.08   -- wie weit ein helles Feld ueber der Scheibe liegt
local GRASS_DARK      = Color3.fromRGB( 58, 140,  62)
local GRASS_LIGHT     = Color3.fromRGB( 92, 178,  82)

-- Sandkante am Wasser: eine BREITERE Scheibe, die ein Stueck tiefer liegt.
-- Ringsum bleibt dadurch ein Sandstreifen sichtbar, ohne dass dafuer ein Ring
-- aus Einzelteilen gebaut werden muesste.
--
-- SHORE_DROP und WATER_DROP bilden zusammen eine Treppe: Wiese 0, Sand -1,
-- Wasser -2.6. Beide Stufen sind niedrig genug, dass eine Roblox-Figur sie
-- ohne Springen hochgeht — wer ins Wasser faellt, laeuft einfach zurueck an
-- Land. Waeren sie hoeher, waere jeder Fehltritt eine Sackgasse.
local SHORE_WIDTH = 8
local SHORE_DROP  = 1.0
local SHORE_COLOR = Color3.fromRGB(238, 214, 158)

-- Das Wasser ist EINE grosse Scheibe unter allem.
--
-- Sie ist begehbar (CanCollide): wer vom Steg faellt, landet auf der
-- Oberflaeche und laeuft zurueck, statt ins Leere zu stuerzen. In einem Spiel,
-- in dem man staendig ueber schmale Stege laeuft, ist das die freundlichere
-- Loesung — ein Sturz waere reine Strafe ohne Spielinhalt.
--
-- WATER_RADIUS muss die aeusserste Arena mit Sandkante umschliessen; das
-- prueft MapService beim Start. War 700 — mit der kleineren Welt reicht 650
-- fuer denselben grosszuegigen Rand offenen Wassers dahinter.
local WATER_RADIUS       = 650
local WATER_DROP         = 2.6    -- wie weit unter Inselhoehe die Oberflaeche liegt
local WATER_HEIGHT       = 10
local WATER_COLOR        = Color3.fromRGB(64, 164, 214)
local WATER_TRANSPARENCY = 0.28

-- Not-Spawn in der Mitte der Wiese. Greift nur noch, wenn ein Spieler
-- ausnahmsweise KEINEN eigenen Plot bekommt (Server voll, siehe
-- MapService.spawnIsland) — der normale Weg ist seit dem Insel-Spawn
-- (siehe PLAYER_SPAWN_OFFSET unten) die eigene Insel, nicht mehr die Mitte.
-- Unsichtbar, damit sie nicht als zweiter Bodenbelag unter dem Event-Pit
-- durchscheint.
local SPAWN_SIZE = Vector3.new(10, 1, 10)
local SPAWN_COLOR = Color3.fromRGB(240, 230, 200)

-- ============================================================
-- EVENT-PIT: DER STALL IN DER MITTE
-- ============================================================
-- Ein rundes, eingezaeuntes Podest genau in der Weltmitte, unter dem
-- Honigmast. Normalerweise ein schlichter Holz-Stall — sobald ein Event
-- laeuft, faerbt EventService Boden, Zaun und Ring in dessen Farben um
-- (siehe MapService.setEventPitTheme) und die Anzeigetafel darueber zeigt
-- Name und Restzeit. Ausserhalb eines Events zeigt dieselbe Tafel den
-- Countdown bis zum naechsten (siehe MapService.setEventBanner).
--
-- Acht Zaunluecken statt einer (wie bei den Spieler-Arenen): das Pit steht
-- in der Mitte aller acht Stege, nicht am Ende von nur einem. Jede Luecke
-- liegt genau in der Aussenrichtung eines Plots — wer von seiner Bruecke
-- kommt, laeuft geradewegs hinein statt am Zaun entlang zu suchen.
--
-- Podesthoehe 2 Studs, derselbe Trick wie beim Plot-Beet (PLOT_SIZE.Y):
-- ein klarer Schritt nach oben statt eines Absenk-Tricks, niedrig genug zum
-- Hochlaufen ohne Springen.
local EVENT_PIT_RADIUS       = 50
local EVENT_PIT_FLOOR_HEIGHT = 2

-- Sicherheitsabstand zwischen dem Karo-Rasen (GRASS_HEIGHT ueber
-- PLATFORM_TOP_Y) und der Podest-Unterkante — derselbe Grundgedanke wie
-- BRIDGE_SINK/GRASS_HEIGHT selbst: ohne diesen Puffer laege die Unterkante
-- GENAU auf Rasenhoehe, und ein paar Karo-Kacheln direkt am Podestrand
-- wuerden mit der Unterkante flimmern bzw. leicht durchscheinen — genau der
-- "das Pit steckt teilweise im Boden"-Effekt. Mit dem Puffer liegt die
-- Unterkante immer sauber ueber dem Rasen, egal welche Kachel gerade
-- darunterliegt.
local EVENT_PIT_GROUND_CLEARANCE = 0.3

-- Stall-Look: gedeckte Stroh-/Holztoene, kein Glimmen. Erst ein Event macht
-- daraus etwas Auffaelliges (siehe EventConfig.EVENTS).
local EVENT_PIT_DEFAULT_FLOOR_COLOR = Color3.fromRGB(178, 150, 100)
local EVENT_PIT_DEFAULT_FENCE_COLOR = Color3.fromRGB(150, 105, 60)
local EVENT_PIT_DEFAULT_RING_COLOR  = Color3.fromRGB(120,  98,  70)

local EVENT_PIT_RING_OVERHANG = 1.6
local EVENT_PIT_RING_HEIGHT   = 0.7

local EVENT_PIT_FENCE_COUNT       = 28
local EVENT_PIT_FENCE_SIZE        = Vector3.new(1.0, 5.0, 1.0)
local EVENT_PIT_FENCE_GAP_DEGREES = 9     -- Oeffnung je Bruecken-Richtung, halber Winkel je Seite
local EVENT_PIT_FENCE_INSET       = 1.6

-- Anzeigetafel: anders als bei den Spieler-Arenen IMMER eingeblendet — sie
-- ist der einzige Ort, an dem der Event-Countdown steht.
-- Playtest 05.10.: bei 16 lag die Tafel im Honigmast (Spitze ~33) und die
-- Schrift lief durch ihn hindurch. 38 = Unterkante ueber dem Tropfen.
local EVENT_PIT_BANNER_HEIGHT   = 38
local EVENT_PIT_BANNER_SIZE     = Vector2.new(22, 6)
local EVENT_PIT_BANNER_DISTANCE = 300
local EVENT_PIT_BANNER_IDLE_COLOR = Color3.fromRGB(230, 220, 200)

--------------------------------------------------------------------------------
-- Spieler-Plots
--------------------------------------------------------------------------------

local PLOT_COUNT = 8

-- Jeder Plot ist eine eigene RUNDE Insel; darauf liegt das quadratische Beet.
--
-- PLOT_ISLAND_RADIUS muss die ECKEN des Beetes decken, nicht seine Kanten:
-- bei 72x72 liegt eine Ecke 50.9 Studs von der Mitte. 58 laesst also rund
-- 7 Studs Wiesenrand ums Beet, dahinter kommt die Sandkante. Zu knapp, und
-- das Beet ragt an vier Stellen ueber die Insel; MapService prueft das beim
-- Start.
local PLOT_ISLAND_RADIUS = 58

-- Abstand der Insel-MITTE zur Weltmitte. Ergibt sich aus den Radien und der
-- Luecke: Hauptinsel-Rand + Steg + halbe Plot-Insel.
--     120 + 34 + 58 = 212
-- MapService rechnet das beim Start nach und warnt, wenn es nicht passt.
-- PLOT_ISLAND_RADIUS selbst bleibt unangetastet: er haengt fest an PLOT_SIZE
-- (die Insel muss die Beet-Ecken decken) — an dieser Zahl zu drehen wuerde das
-- Beet ueber den Inselrand ragen lassen, nicht nur den Weg dorthin verkuerzen.
local PLOT_RING_RADIUS = 212
local PLOT_SIZE        = Vector3.new(72, 2, 72)

-- Der Wiesenrand der Plot-Insel, auf dem das Beet steht. Etwas dunkler als das
-- Karo, damit das Beet als eigene Flaeche liest und nicht mit der Insel
-- verschwimmt.
local PLOT_ISLAND_COLOR = Color3.fromRGB(70, 152, 70)

-- Zaun an den beiden SEITEN des Plots (lokales +X und -X). Vorne (+Z, Richtung
-- Bruecke) und hinten (-Z, Richtung Mitte) bleibt bewusst offen — sonst muesste
-- man ueber den Zaun springen um auf den eigenen Plot oder zur Bruecke zu kommen.
local FENCE_POST_SIZE    = Vector3.new(1.2, 5, 1.2)
local FENCE_POST_SPACING = 9
local FENCE_RAIL_HEIGHT  = 0.8
local FENCE_COLOR        = Color3.fromRGB(225, 215, 190)

-- Schild an der zur Mitte zeigenden Kante: zeigt, wem der Plot gehoert
local SIGN_POST_SIZE  = Vector3.new(0.8, 7, 0.8)
-- Playtest 05.10.: 16 breit wirkte langgezogen, und EIN Pfosten in der Mitte
-- ragte vorne durch die Schrift. Jetzt 12 breit, zwei Pfosten HINTER dem Brett
-- an den Raendern, dunkle Leisten oben und unten.
local SIGN_BOARD_SIZE = Vector3.new(12, 5.2, 0.6)
local SIGN_TRIM_COLOR = Color3.fromRGB(150, 105, 60)
local SIGN_POST_COLOR = Color3.fromRGB(150, 105, 60)
local SIGN_COLOR      = Color3.fromRGB(245, 235, 205)

-- Blumen auf der freien Wiese der Hauptinsel. Rein optisch, deterministisch
-- gesetzt (fester Zufallsstartwert), damit die Welt bei jedem Server-Start
-- gleich aussieht.
--
-- Weniger als vorher (90), weil die Hauptinsel nur noch ein Fuenftel der
-- frueheren Flaeche hat: dieselbe Zahl waere jetzt ein Blumenfeld, und die
-- Karos darunter waeren nicht mehr zu sehen.
local FLOWER_COUNT      = 46
local FLOWER_SEED       = 20260903
local FLOWER_STEM_SIZE  = Vector3.new(0.4, 3, 0.4)
local FLOWER_HEAD_SIZE  = 1.8
local FLOWER_STEM_COLOR = Color3.fromRGB(70, 150, 55)
local FLOWER_COLORS: { Color3 } = {
	Color3.fromRGB(255, 235, 120),
	Color3.fromRGB(255, 160, 190),
	Color3.fromRGB(180, 165, 255),
	Color3.fromRGB(255, 255, 255),
}

--------------------------------------------------------------------------------
-- Gebaeude auf dem Plot (Offsets im PLOT-LOKALEN Raum, siehe Kopf)
--------------------------------------------------------------------------------

-- Die zwei Honig-Gebaeude (v15: Bienenstock und Honig-Veredler) stehen ab dem
-- ersten Join auf dem Plot (siehe Types.createDefaultPlayerData). Der dritte
-- Ausbau, der Waben-Recycler, steht vorne am Steg (CombConfig.RECYCLER_OFFSET). Sie stehen in einer Reihe an der zur Mitte
-- zeigenden Seite (-Z), damit die vordere Haelfte des Plots (+Z) frei bleibt
-- fuer die Baerchis und den Weg zur Bruecke.
--
-- Der Part-Name ist die BuildingId — der Client findet darueber das Gebaeude
-- fuer den ProximityPrompt. Wer hier einen Schluessel aendert, muss ihn auch
-- in Types.BuildingId, BuildingBehavior und IslandService.VALID_BUILDINGS
-- aendern; tools/check_consistency.py prueft alle Listen gegeneinander.
-- displayName steht bewusst HIER und nicht im Client: das Schild in der Welt
-- (MapService) und das Gebaeude-Panel (BuildingPanel) benennen dasselbe
-- Objekt. Zwei getrennte Listen waeren die naechste Stelle, an der etwas
-- auseinanderlaeuft.
-- shortName steht aus demselben Grund hier wie displayName: seit v7 waehlt der
-- Spieler auf der Baerchi-Detailkarte aus, welchen Honig er verfuettert, und
-- auf einen Knopf von einem Drittel Kartenbreite passt "Honig-Presse" nicht.
-- Eine zweite Namensliste im Client waere die naechste Stelle, an der etwas
-- auseinanderlaeuft.
local BUILDING_OFFSETS: { [string]: { offset: Vector3, size: Vector3, color: Color3, displayName: string, shortName: string } } = {
	Beehive = {
		offset      = Vector3.new(-22, 0, -22),
		size        = Vector3.new(12, 11, 12),
		color       = Color3.fromRGB(240, 190, 70),    -- Bienenstock-Gelb
		displayName = "Bienenstock",
		shortName   = "Stock",
	},
	-- v15: Honigtopf + Honig-Presse -> Honig-Veredler ("Honig-Veredler" ist ein
	-- Platzhalter-Name). Steht dort, wo die Presse stand; die Mitte (frueher
	-- der Topf) bleibt frei.
	HoneyRefiner = {
		offset      = Vector3.new(22, 0, -22),
		size        = Vector3.new(12, 11, 12),
		color       = Color3.fromRGB(205, 135, 45),    -- Honig-Orange
		displayName = "Honig-Veredler",
		shortName   = "Veredler",
	},
	-- Honig-Teich (HONEY_POND_V2): ersetzt Stock und Veredler. Steht mitten im
	-- hinteren Plot-Teil (wo die beiden standen), damit sein Brunnen vom Steg
	-- aus zu sehen ist. Der Koerper ist so gross wie Becken + Steinkranz; die
	-- Look-Deko (BUILDING_LOOK_DECOR.HoneyPond) waechst darin bis zum
	-- Honig-Springbrunnen. Das Becken selbst baut PondBuilder an derselben Stelle.
	HoneyPond = {
		offset      = Vector3.new(0, 0, -14),
		size        = Vector3.new(20, 15, 20),
		color       = Color3.fromRGB(255, 190, 60),    -- Honig-Gold
		displayName = "Honig-Brunnen",
		shortName   = "Brunnen",
	},
}

-- Feste Reihenfolge fuer alles was die Gebaeude AUFLISTET (Panel, Schilder).
-- Die Gebaeude-Tabelle in IslandData ist eine Hash-Tabelle und damit nicht
-- stabil sortiert.
local BUILDING_ORDER: { string } = { "Beehive", "HoneyRefiner", "HoneyPond" }

--------------------------------------------------------------------------------
-- Aussehen der Gebaeude
--------------------------------------------------------------------------------

-- Die Part aus BUILDING_OFFSETS ist seit v5 nur noch der unsichtbare Koerper:
-- sie traegt Namen, Attribut und Schild, und der Client haengt seinen
-- ProximityPrompt daran. Sie kollidiert NICHT — dagegen laufen kann man nur
-- an den Teilen, die hier `solid = true` tragen. WIE ein Gebaeude aussieht
-- steht also hier, als reine Beschreibung, ohne eine Zeile Code.
--
-- Warum getrennt: der Klotz von vorher war der Grund, dass alle drei Gebaeude
-- gleich aussahen und man sie nur am Schild unterscheiden konnte. Wer die Form
-- aendern will, aendert diese Liste und fasst MapService nicht an.
--
-- Koordinaten sind GEBAEUDE-lokal: Ursprung ist die Mitte der Grundflaeche auf
-- Plot-Hoehe, +Y ist nach oben, -Z zeigt zur Plattform-Mitte (also zu der
-- Seite, von der der Spieler kommt) und +Z zu den Baerchis.
--
-- shape/rotation: ein Cylinder liegt in Roblox von Haus aus entlang X. Damit
-- er STEHT, braucht er rotation = Vector3.new(0, 0, 90) — die Size ist dann
-- (Hoehe, Durchmesser, Durchmesser). Das ist die haeufigste Stolperfalle hier.
-- solid: dagegen laeuft man. Standard ist false, weil die meisten Teile nur
-- Zierrat sind (Wimpel, Flugloch, Honig-Fuellung) und man daran sonst haengen
-- bliebe. Der KOERPER selbst kollidiert seit v5 nicht mehr: er ist ein Kasten
-- in der Groesse aus BUILDING_OFFSETS und passt damit nicht mehr zur
-- sichtbaren Form — bei der offenen Presse etwa wuerde man mitten in der Luft
-- zwischen den Pfosten stehenbleiben. Also markiert die Config genau die
-- Teile, die den Umriss ausmachen.
export type DecorPiece = {
	name     : string,
	shape    : Enum.PartType,
	size     : Vector3,
	offset   : Vector3,
	color    : Color3,
	material : Enum.Material?,
	rotation : Vector3?,   -- Grad, optional
	solid    : boolean?,   -- Standard: false
}

local UPRIGHT = Vector3.new(0, 0, 90)   -- macht aus einem liegenden einen stehenden Cylinder

local WOOD       = Color3.fromRGB(160, 110, 65)
local WOOD_DARK  = Color3.fromRGB(118,  80,  46)
local HONEY      = Color3.fromRGB(245, 175,  45)
local HONEY_DEEP = Color3.fromRGB(205, 135,  45)
local METAL      = Color3.fromRGB(150, 152, 158)

local BUILDING_DECOR: { [string]: { DecorPiece } } = {
	-- Klassischer Strohkorb: vier gestapelte Ringe, die nach oben schmaler
	-- werden, eine Kuppel obendrauf und ein dunkles Flugloch nach vorne.
	Beehive = {
		{ name = "Ring1",    shape = Enum.PartType.Cylinder, size = Vector3.new(3.0, 11.5, 11.5), offset = Vector3.new(0, 1.50, 0), color = Color3.fromRGB(238, 186,  70), rotation = UPRIGHT, solid = true },
		{ name = "Ring2",    shape = Enum.PartType.Cylinder, size = Vector3.new(2.5,  9.8,  9.8), offset = Vector3.new(0, 4.05, 0), color = Color3.fromRGB(244, 196,  84), rotation = UPRIGHT, solid = true },
		{ name = "Ring3",    shape = Enum.PartType.Cylinder, size = Vector3.new(2.1,  7.8,  7.8), offset = Vector3.new(0, 6.35, 0), color = Color3.fromRGB(238, 186,  70), rotation = UPRIGHT, solid = true },
		{ name = "Ring4",    shape = Enum.PartType.Cylinder, size = Vector3.new(1.7,  5.4,  5.4), offset = Vector3.new(0, 8.25, 0), color = Color3.fromRGB(244, 196,  84), rotation = UPRIGHT, solid = true },
		{ name = "Kuppel",   shape = Enum.PartType.Ball,     size = Vector3.new(3.4,  3.4,  3.4), offset = Vector3.new(0, 9.60, 0), color = Color3.fromRGB(238, 186,  70), solid = true },
		{ name = "Flugloch", shape = Enum.PartType.Block,    size = Vector3.new(2.4,  1.6,  0.8), offset = Vector3.new(0, 1.40, -5.6), color = Color3.fromRGB( 62,  44,  24) },
		{ name = "Brett",    shape = Enum.PartType.Block,    size = Vector3.new(3.6,  0.4,  1.6), offset = Vector3.new(0, 0.20, -5.6), color = WOOD_DARK, material = Enum.Material.Wood },
	},

	-- v15: Honig-Veredler. Die Spindelpresse von frueher (Grundplatte, vier
	-- Pfosten, Deckplatte, Spindel mit Querholz, unten ausgepresster Honig) mit
	-- dem kleinen Honigtopf obendrauf — beides steckt jetzt in einem Gebaeude.
	-- Platzhalter bis zu den Looks in Prompt 4.
	HoneyRefiner = {
		{ name = "Grundplatte", shape = Enum.PartType.Block,    size = Vector3.new(10.0, 1.4, 10.0), offset = Vector3.new(   0, 0.70,    0), color = WOOD,      material = Enum.Material.Wood, solid = true },
		{ name = "Sud",         shape = Enum.PartType.Block,    size = Vector3.new( 6.0, 0.4,  6.0), offset = Vector3.new(   0, 1.60,    0), color = HONEY,     material = Enum.Material.Neon },
		{ name = "Pfosten1",    shape = Enum.PartType.Block,    size = Vector3.new( 1.2, 7.0,  1.2), offset = Vector3.new(-3.9, 4.10, -3.9), color = WOOD_DARK, material = Enum.Material.Wood, solid = true },
		{ name = "Pfosten2",    shape = Enum.PartType.Block,    size = Vector3.new( 1.2, 7.0,  1.2), offset = Vector3.new( 3.9, 4.10, -3.9), color = WOOD_DARK, material = Enum.Material.Wood, solid = true },
		{ name = "Pfosten3",    shape = Enum.PartType.Block,    size = Vector3.new( 1.2, 7.0,  1.2), offset = Vector3.new(-3.9, 4.10,  3.9), color = WOOD_DARK, material = Enum.Material.Wood, solid = true },
		{ name = "Pfosten4",    shape = Enum.PartType.Block,    size = Vector3.new( 1.2, 7.0,  1.2), offset = Vector3.new( 3.9, 4.10,  3.9), color = WOOD_DARK, material = Enum.Material.Wood, solid = true },
		{ name = "Pressteller", shape = Enum.PartType.Block,    size = Vector3.new( 6.8, 0.9,  6.8), offset = Vector3.new(   0, 2.70,    0), color = WOOD_DARK, material = Enum.Material.Wood },
		{ name = "Spindel",     shape = Enum.PartType.Cylinder, size = Vector3.new( 6.2, 1.4,  1.4), offset = Vector3.new(   0, 5.30,    0), color = METAL,     material = Enum.Material.Metal, rotation = UPRIGHT },
		{ name = "Deckplatte",  shape = Enum.PartType.Block,    size = Vector3.new(10.0, 1.2, 10.0), offset = Vector3.new(   0, 8.20,    0), color = WOOD,      material = Enum.Material.Wood, solid = true },
		{ name = "Querholz",    shape = Enum.PartType.Cylinder, size = Vector3.new( 9.0, 0.9,  0.9), offset = Vector3.new(   0, 9.20,    0), color = WOOD_DARK, material = Enum.Material.Wood },
		{ name = "Topf",        shape = Enum.PartType.Ball,     size = Vector3.new( 2.6, 2.0,  2.6), offset = Vector3.new( 2.8, 9.60,  2.8), color = HONEY_DEEP },
		{ name = "Topfdeckel",  shape = Enum.PartType.Cylinder, size = Vector3.new( 0.4, 1.8,  1.8), offset = Vector3.new( 2.8, 10.70, 2.8), color = WOOD, material = Enum.Material.Wood, rotation = UPRIGHT },
	},

	-- Honig-Teich, Look 1: im Becken (PondBuilder) ein Holzpfahl mit Wabe. Alles
	-- steht auf Beet-Hoehe in der Beckenmitte; der Boden (0,45) und der Honig
	-- verdecken die Fuesse. Die Looks 2-6 bauen darum den Brunnen auf.
	HoneyPond = {
		{ name = "Pfahl",      shape = Enum.PartType.Cylinder, size = Vector3.new(2.4, 0.9, 0.9),   offset = Vector3.new(0, 1.20, 0), color = WOOD,  material = Enum.Material.Wood, rotation = UPRIGHT },
		{ name = "Wabe",       shape = Enum.PartType.Block,    size = Vector3.new(1.6, 1.2, 0.5),   offset = Vector3.new(0, 2.90, 0), color = HONEY, material = Enum.Material.Neon },
	},
}

-- ============================================================
-- v15: LOOK-STUFEN DER GEBAEUDE (Platzhalter bis Prompt 4)
-- ============================================================
-- Ein Gebaeude hat sechs Looks (Level 1-9 / 10-19 / 20-29 / 30-44 / 45-59 /
-- 60, siehe EconomyConfig.LOOK_THRESHOLDS). Bis die echten Modelle kommen,
-- bekommt jeder Look ein paar Zierteile DAZU: gebaut wird die Grund-Deko plus
-- alle Zusaetze bis zum aktuellen Look (getBuildingDecor). Die Regeln sind
-- dieselben wie oben (gebaeude-lokal, solid nur fuer den Umriss);
-- tools/check_decor.py prueft jeden Look einzeln und das Teile-Budget
-- (LOOK_PART_BUDGET). PlotDisplayService baut ein Gebaeude nur neu, wenn sich
-- der Look aendert — nicht bei jedem Level.
local GOLD_TRIM   = Color3.fromRGB(255, 205, 70)
local GLOW_AMBER  = Color3.fromRGB(255, 170, 40)
local CRYSTAL     = Color3.fromRGB(150, 225, 255)
local POND_STONE  = Color3.fromRGB(214, 204, 186)   -- heller Brunnenstein
local PENNANT_RED = Color3.fromRGB(220, 70, 60)

-- Hoechstens so viele Teile pro Look (Grund-Deko + Zusaetze), README 4.2.
local LOOK_PART_BUDGET: { number } = { 40, 40, 70, 70, 110, 110 }

local BUILDING_LOOK_DECOR: { [string]: { [number]: { DecorPiece } } } = {
	Beehive = {
		[2] = {
			{ name = "L2Stab",     shape = Enum.PartType.Block,    size = Vector3.new(0.3, 3.0, 0.3),   offset = Vector3.new( 4.4, 1.50,  4.4), color = WOOD_DARK, material = Enum.Material.Wood },
			{ name = "L2Wimpel",   shape = Enum.PartType.Block,    size = Vector3.new(0.1, 1.0, 1.6),   offset = Vector3.new( 4.4, 2.50,  5.2), color = PENNANT_RED },
		},
		[3] = {
			{ name = "L3Goldring", shape = Enum.PartType.Cylinder, size = Vector3.new(0.5, 12.0, 12.0), offset = Vector3.new(0, 0.25, 0), color = GOLD_TRIM, material = Enum.Material.Neon, rotation = UPRIGHT },
		},
		[4] = {
			{ name = "L4Krone",    shape = Enum.PartType.Cylinder, size = Vector3.new(0.6, 3.0, 3.0),   offset = Vector3.new(0, 11.20, 0), color = GOLD_TRIM, material = Enum.Material.Metal, rotation = UPRIGHT },
			{ name = "L4Zacke",    shape = Enum.PartType.Ball,     size = Vector3.new(1.0, 1.0, 1.0),   offset = Vector3.new(0, 11.90, 0), color = GOLD_TRIM, material = Enum.Material.Metal },
		},
		[5] = {
			{ name = "L5Band1",    shape = Enum.PartType.Cylinder, size = Vector3.new(0.3, 10.2, 10.2), offset = Vector3.new(0, 4.05, 0), color = GLOW_AMBER, material = Enum.Material.Neon, rotation = UPRIGHT },
			{ name = "L5Band2",    shape = Enum.PartType.Cylinder, size = Vector3.new(0.3, 8.2, 8.2),   offset = Vector3.new(0, 6.35, 0), color = GLOW_AMBER, material = Enum.Material.Neon, rotation = UPRIGHT },
		},
		[6] = {
			{ name = "L6Kristall1", shape = Enum.PartType.Block,   size = Vector3.new(1.2, 2.4, 1.2),   offset = Vector3.new(-4.4, 1.20,  4.4), color = CRYSTAL, material = Enum.Material.Glass, rotation = Vector3.new(0, 45, 0) },
			{ name = "L6Kristall2", shape = Enum.PartType.Block,   size = Vector3.new(1.2, 2.4, 1.2),   offset = Vector3.new( 4.4, 1.20, -4.4), color = CRYSTAL, material = Enum.Material.Glass, rotation = Vector3.new(0, 45, 0) },
		},
	},
	-- Honig-Teich -> Honig-Springbrunnen (HONEY_POND_V2). Jede Stufe kommt dazu:
	-- 2 Rinne mit Honigstrahl, 3 Steinsaeule + Schale, 4 zweite Schale, Goldring,
	-- Kaskaden, 5 goldene Bienen + Fontaene, 6 Riesentropfen mit Krone, sechs
	-- Honigfaelle, Kristalle. Neon-Honig leuchtet mit dem Bloom der Welt.
	HoneyPond = {
		[2] = {
			{ name = "L2Rinne",    shape = Enum.PartType.Block,    size = Vector3.new(0.6, 0.5, 3.2),   offset = Vector3.new(0, 2.55, -1.6), color = WOOD_DARK, material = Enum.Material.Wood },
			{ name = "L2Strahl",   shape = Enum.PartType.Cylinder, size = Vector3.new(2.3, 0.5, 0.5), offset = Vector3.new(0, 1.15, -3.0), color = HONEY, material = Enum.Material.Neon, rotation = UPRIGHT },
			{ name = "L2Topf",     shape = Enum.PartType.Ball,     size = Vector3.new(1.8, 1.6, 1.8),   offset = Vector3.new(5.5, 0.80, 3.0), color = HONEY_DEEP },
		},
		[3] = {
			{ name = "L3Saeule",   shape = Enum.PartType.Cylinder, size = Vector3.new(4.0, 4.0, 4.0),   offset = Vector3.new(0, 2.00, 0), color = POND_STONE, material = Enum.Material.Slate, rotation = UPRIGHT, solid = true },
			{ name = "L3Schale",   shape = Enum.PartType.Cylinder, size = Vector3.new(0.8, 9.0, 9.0),   offset = Vector3.new(0, 4.40, 0), color = POND_STONE, material = Enum.Material.Slate, rotation = UPRIGHT },
			{ name = "L3Honig",    shape = Enum.PartType.Cylinder, size = Vector3.new(0.2, 8.2, 8.2),   offset = Vector3.new(0, 4.90, 0), color = HONEY, material = Enum.Material.Neon, rotation = UPRIGHT },
		},
		[4] = {
			{ name = "L4Saeule",   shape = Enum.PartType.Cylinder, size = Vector3.new(2.4, 2.2, 2.2),   offset = Vector3.new(0, 6.20, 0), color = POND_STONE, material = Enum.Material.Slate, rotation = UPRIGHT },
			{ name = "L4Schale",   shape = Enum.PartType.Cylinder, size = Vector3.new(0.6, 5.6, 5.6),   offset = Vector3.new(0, 7.70, 0), color = POND_STONE, material = Enum.Material.Slate, rotation = UPRIGHT },
			{ name = "L4Honig",    shape = Enum.PartType.Cylinder, size = Vector3.new(0.15, 5.0, 5.0),  offset = Vector3.new(0, 8.075, 0), color = HONEY, material = Enum.Material.Neon, rotation = UPRIGHT },
			{ name = "L4Goldring", shape = Enum.PartType.Cylinder, size = Vector3.new(0.3, 9.4, 9.4),   offset = Vector3.new(0, 4.65, 0), color = GOLD_TRIM, material = Enum.Material.Neon, rotation = UPRIGHT },
			{ name = "L4Kaskade1", shape = Enum.PartType.Cylinder, size = Vector3.new(4.4, 0.6, 0.6),   offset = Vector3.new( 4.2, 2.60, 0), color = HONEY, material = Enum.Material.Neon, rotation = UPRIGHT },
			{ name = "L4Kaskade2", shape = Enum.PartType.Cylinder, size = Vector3.new(4.4, 0.6, 0.6),   offset = Vector3.new(-4.2, 2.60, 0), color = HONEY, material = Enum.Material.Neon, rotation = UPRIGHT },
		},
		[5] = {
			{ name = "L5Biene1",   shape = Enum.PartType.Ball,     size = Vector3.new(1.8, 1.5, 2.2),   offset = Vector3.new( 2.9, 5.55, -2.9), color = GOLD_TRIM, material = Enum.Material.Metal },
			{ name = "L5Biene2",   shape = Enum.PartType.Ball,     size = Vector3.new(1.8, 1.5, 2.2),   offset = Vector3.new(-2.9, 5.55,  2.9), color = GOLD_TRIM, material = Enum.Material.Metal },
			{ name = "L5Fluegel1", shape = Enum.PartType.Block,    size = Vector3.new(0.1, 0.9, 1.4),   offset = Vector3.new( 2.9, 6.65, -2.9), color = CRYSTAL, material = Enum.Material.Glass },
			{ name = "L5Fluegel2", shape = Enum.PartType.Block,    size = Vector3.new(0.1, 0.9, 1.4),   offset = Vector3.new(-2.9, 6.65,  2.9), color = CRYSTAL, material = Enum.Material.Glass },
			{ name = "L5Fontaene", shape = Enum.PartType.Cylinder, size = Vector3.new(3.0, 0.8, 0.8),   offset = Vector3.new(0, 9.65, 0), color = HONEY, material = Enum.Material.Neon, rotation = UPRIGHT },
			{ name = "L5Kuppe",    shape = Enum.PartType.Ball,     size = Vector3.new(1.8, 1.8, 1.8),   offset = Vector3.new(0, 11.50, 0), color = HONEY, material = Enum.Material.Neon },
		},
		[6] = {
			{ name = "L6Tropfen",  shape = Enum.PartType.Ball,     size = Vector3.new(3.4, 4.4, 3.4),   offset = Vector3.new(0, 13.70, 0), color = HONEY, material = Enum.Material.Neon },
			{ name = "L6Krone",    shape = Enum.PartType.Cylinder, size = Vector3.new(0.5, 3.0, 3.0),   offset = Vector3.new(0, 16.10, 0), color = GOLD_TRIM, material = Enum.Material.Metal, rotation = UPRIGHT },
			{ name = "L6Zacke1",   shape = Enum.PartType.Ball,     size = Vector3.new(0.7, 0.7, 0.7),   offset = Vector3.new( 1.2, 16.60, 0), color = GOLD_TRIM, material = Enum.Material.Metal },
			{ name = "L6Zacke2",   shape = Enum.PartType.Ball,     size = Vector3.new(0.7, 0.7, 0.7),   offset = Vector3.new(-1.2, 16.60, 0), color = GOLD_TRIM, material = Enum.Material.Metal },
			{ name = "L6Zacke3",   shape = Enum.PartType.Ball,     size = Vector3.new(0.7, 0.7, 0.7),   offset = Vector3.new(0, 16.60,  1.2), color = GOLD_TRIM, material = Enum.Material.Metal },
			{ name = "L6Zacke4",   shape = Enum.PartType.Ball,     size = Vector3.new(0.7, 0.7, 0.7),   offset = Vector3.new(0, 16.60, -1.2), color = GOLD_TRIM, material = Enum.Material.Metal },
			{ name = "L6Fall1",    shape = Enum.PartType.Cylinder, size = Vector3.new(4.6, 0.55, 0.55), offset = Vector3.new( 3.0, 2.50,  3.0), color = HONEY, material = Enum.Material.Neon, rotation = UPRIGHT },
			{ name = "L6Fall2",    shape = Enum.PartType.Cylinder, size = Vector3.new(4.6, 0.55, 0.55), offset = Vector3.new(-3.0, 2.50,  3.0), color = HONEY, material = Enum.Material.Neon, rotation = UPRIGHT },
			{ name = "L6Fall3",    shape = Enum.PartType.Cylinder, size = Vector3.new(4.6, 0.55, 0.55), offset = Vector3.new( 3.0, 2.50, -3.0), color = HONEY, material = Enum.Material.Neon, rotation = UPRIGHT },
			{ name = "L6Fall4",    shape = Enum.PartType.Cylinder, size = Vector3.new(4.6, 0.55, 0.55), offset = Vector3.new(-3.0, 2.50, -3.0), color = HONEY, material = Enum.Material.Neon, rotation = UPRIGHT },
			{ name = "L6Kristall1", shape = Enum.PartType.Block,   size = Vector3.new(0.7, 1.6, 0.7),   offset = Vector3.new( 2.0, 8.95, 0), color = CRYSTAL, material = Enum.Material.Glass, rotation = Vector3.new(0, 45, 0) },
			{ name = "L6Kristall2", shape = Enum.PartType.Block,   size = Vector3.new(0.7, 1.6, 0.7),   offset = Vector3.new(-2.0, 8.95, 0), color = CRYSTAL, material = Enum.Material.Glass, rotation = Vector3.new(0, 45, 0) },
		},
	},
	HoneyRefiner = {
		[2] = {
			{ name = "L2Stab",     shape = Enum.PartType.Block,    size = Vector3.new(0.3, 3.0, 0.3),   offset = Vector3.new(-5.4, 1.50,  5.4), color = WOOD_DARK, material = Enum.Material.Wood },
			{ name = "L2Wimpel",   shape = Enum.PartType.Block,    size = Vector3.new(0.1, 1.0, 1.6),   offset = Vector3.new(-5.4, 2.50,  4.6), color = PENNANT_RED },
		},
		[3] = {
			{ name = "L3Goldkante", shape = Enum.PartType.Block,   size = Vector3.new(10.4, 0.3, 10.4), offset = Vector3.new(0, 1.55, 0), color = GOLD_TRIM, material = Enum.Material.Neon },
		},
		[4] = {
			{ name = "L4Krone",    shape = Enum.PartType.Cylinder, size = Vector3.new(0.6, 2.4, 2.4),   offset = Vector3.new(0, 9.95, 0), color = GOLD_TRIM, material = Enum.Material.Metal, rotation = UPRIGHT },
			{ name = "L4Zacke",    shape = Enum.PartType.Ball,     size = Vector3.new(1.0, 1.0, 1.0),   offset = Vector3.new(0, 10.65, 0), color = GOLD_TRIM, material = Enum.Material.Metal },
		},
		[5] = {
			{ name = "L5Glut1",    shape = Enum.PartType.Block,    size = Vector3.new(1.4, 6.0, 0.2),   offset = Vector3.new(-3.9, 4.10, -4.6), color = GLOW_AMBER, material = Enum.Material.Neon },
			{ name = "L5Glut2",    shape = Enum.PartType.Block,    size = Vector3.new(1.4, 6.0, 0.2),   offset = Vector3.new( 3.9, 4.10, -4.6), color = GLOW_AMBER, material = Enum.Material.Neon },
		},
		[6] = {
			{ name = "L6Kristall1", shape = Enum.PartType.Block,   size = Vector3.new(1.2, 2.4, 1.2),   offset = Vector3.new(-5.0, 1.20, -5.0), color = CRYSTAL, material = Enum.Material.Glass, rotation = Vector3.new(0, 45, 0) },
			{ name = "L6Kristall2", shape = Enum.PartType.Block,   size = Vector3.new(1.2, 2.4, 1.2),   offset = Vector3.new( 5.0, 1.20,  5.0), color = CRYSTAL, material = Enum.Material.Glass, rotation = Vector3.new(0, 45, 0) },
		},
	},
}

-- Grund-Deko plus alle Look-Zusaetze bis `look` (fuer PlotBuilder und
-- RecyclerBuilder; der Recycler gibt seine eigenen Tabellen mit).
local function combineLookDecor(base: { DecorPiece }?, extras: { [number]: { DecorPiece } }?, look: number): { DecorPiece }
	local result: { DecorPiece } = {}
	for _, piece in base or {} do
		table.insert(result, piece)
	end
	for step = 2, math.max(1, math.floor(look)) do
		for _, piece in (extras and extras[step]) or {} do
			table.insert(result, piece)
		end
	end
	return result
end

local function getBuildingDecor(buildingId: string, look: number): { DecorPiece }
	return combineLookDecor(BUILDING_DECOR[buildingId], BUILDING_LOOK_DECOR[buildingId], look)
end

-- Honig-Tropfen am Fuss jedes Gebaeudes: einer pro eingelagertem Honig.
--
-- Ohne die muss man fuer die Frage "ist schon wieder was da?" das Schild lesen
-- oder ein Panel oeffnen. Mit ihnen sieht man es im Vorbeilaufen, und ein
-- volles Lager (alle Punkte an) faellt von weitem auf — was der Moment ist,
-- in dem die Produktion steht und man zurueckkommen sollte.
--
-- Sie werden EINMAL gebaut und danach nur noch ein- und ausgeblendet. Ein
-- Neuaufbau alle 20 Sekunden, mal drei Gebaeude, mal acht Spieler, waere fuer
-- reine Deko viel zu teuer.
--
-- Die Punkte liegen auf einem Bogen zur Plattform-Mitte hin (lokales -Z) —
-- also auf der Seite, von der der Spieler kommt.
local HONEY_DOT_SIZE   = 1.7      -- Durchmesser
local HONEY_DOT_RADIUS = 7.2      -- Abstand zur Gebaeudemitte
local HONEY_DOT_HEIGHT = 1.5      -- ueber dem Plot-Boden
-- Die Tropfen sitzen in festem WINKELABSTAND nebeneinander, bis der Bogen
-- voll ist — dann ruecken sie zusammen. Bis v6 hatte jedes Gebaeude genau 5
-- Plaetze und ein fester Bogen reichte; seit v7 hat der Bienenstock bis zu 12,
-- und die haetten sich bei festem Bogen ueberlappt. HONEY_DOT_SPACING ist
-- genau der bisherige Abstand (150 Grad auf 4 Luecken), fuenf Tropfen sehen
-- also unveraendert aus.
local HONEY_DOT_SPACING = 37.5    -- Grad zwischen zwei Tropfen
local HONEY_DOT_ARC     = 200     -- Grad, mehr als so breit wird es nie
local HONEY_DOT_COLOR  = Color3.fromRGB(255, 198, 62)
-- v15: hoechstens so viele Tropfen pro Gebaeude. Das Lager des Bienenstocks
-- waechst bis Level 60 auf 39 — ab hier steht ein Tropfen fuer einen ANTEIL
-- des Lagers (PlotBuilder.writeBuildingState), damit es keine 39 Kugeln werden.
local HONEY_DOT_MAX    = 14

--------------------------------------------------------------------------------
-- Honig-Teich
--------------------------------------------------------------------------------

-- Ein gemauertes Becken auf dem Plot, zu dem der ausgeruestete Baerchi
-- selbststaendig laeuft um zu essen (siehe BaerchiAutopilotService). Sein
-- Fuellstand zeigt den GESAMTEN Honig-Vorrat der Insel (alle drei Gebaeude
-- zusammen), nicht nur eines.
--
-- ============================================================
-- WARUM DER TEICH KOMPLETT NEU IST
-- ============================================================
-- Der alte bestand aus genau zwei Teilen: einer soliden grauen Scheibe
-- (Radius 6.5, Hoehe 1.4) und der Honig-Fuellung DARIN. Und zwar vollstaendig
-- darin — die Fuellung war bei vollem Lager 5.1 Studs im Radius und 0.9 hoch,
-- der Klotz 6.5 und 1.4. Vom Honig war also NIE etwas zu sehen, bei keinem
-- Fuellstand. Sichtbar war eine graue Scheibe im Gras, sonst nichts.
--
-- Der Teich war damit nicht nur haesslich, sondern als Anzeige schlicht
-- kaputt: er hat den Vorrat gemessen und dann nichts damit gezeigt.
--
-- ============================================================
-- WIE ER JETZT GEBAUT IST
-- ============================================================
-- Von aussen nach innen: eine feuchte Sandkante, darauf ein Kranz aus
-- Feldsteinen als Beckenwand, darin der abgesenkte dunkle Beckenboden und
-- darauf der Honig. Auf der Seite zum Baerchi-Platz bleibt eine Luecke im
-- Steinkranz, und dort liegen zwei Bohlen — da steht er beim Fressen.
--
-- Die Steine sind der einzige Weg zu einer sichtbaren Beckenwand: Roblox kennt
-- keinen Ring als Grundform, und der Trick "breitere Scheibe weiter unten"
-- (Sandkante, Insel-Ufer, Arena-Leuchtring) funktioniert nur, solange das
-- aeussere Teil TIEFER liegt. Eine Wand muss aber HOEHER sein als das, was sie
-- umschliesst — also braucht sie einzelne Teile.
--
-- Lage bewusst abseits der Gebaeude-Reihe (die steht bei negativem Z) und
-- abseits vom Baerchi-Zuhause, damit sich beim Hinlaufen nichts ueberlappt.
local POND_OFFSET = Vector3.new(22, 0, 16)   -- plot-lokal
local POND_RADIUS = 8.5                      -- Innenmass: Radius des Beckenbodens

-- Die beiden flachen Scheiben. Beide sind dicker als der Teil, den man sieht —
-- der Rest steckt im Beet und sorgt dafuer, dass unten nichts durchscheint.
-- Die Sandkante liegt TIEFER als der Beckenboden; nur deshalb sieht man sie
-- ringsum als Streifen, ohne dass ein Ring aus Einzelteilen noetig waere.
local POND_RIM_WIDTH   = 1.8    -- wie weit die Sandkante ueber das Becken hinausgeht
local POND_RIM_TOP     = 0.20   -- Oberkante der Sandkante ueber dem Beet
local POND_FLOOR_TOP   = 0.45   -- Oberkante des Beckenbodens
local POND_DISC_HEIGHT = 1.2
local POND_RIM_COLOR   = Color3.fromRGB(208, 178, 128)
local POND_FLOOR_COLOR = Color3.fromRGB( 96,  62,  34)

-- Der Steinkranz. Drei Groessen und drei Grautoene im Wechsel, damit es nach
-- gesammelten Feldsteinen aussieht und nicht nach einer Perlenkette; die
-- Reihenfolge ist fest, die Welt sieht also bei jedem Serverstart gleich aus.
local POND_STONE_COUNT       = 12
local POND_STONE_GAP_DEGREES = 30     -- Luecke zu den Bohlen, halber Winkel je Seite
local POND_STONE_SIZES: { number } = { 3.4, 2.6, 3.0, 2.4 }
local POND_STONE_COLORS: { Color3 } = {
	Color3.fromRGB(172, 166, 156),
	Color3.fromRGB(142, 136, 128),
	Color3.fromRGB(190, 184, 172),
}

-- Der Fuellstand waechst in BEIDE Richtungen: die Honigflaeche wird breiter
-- UND hoeher.
--
-- Nur hoeher waere aus der Spielerkamera — die von schraeg oben auf den Boden
-- schaut — kaum abzulesen, und genau daran ist der alte Teich gescheitert.
-- Nur breiter saehe aus wie ein Aufkleber. Zusammen liest man den Stand aus
-- jedem Winkel: eine kleine Pfuetze in der Mitte heisst fast leer, ein
-- randvolles Becken heisst alle Lager voll.
--
-- MAX_HEIGHT bleibt deutlich unter der Steinhoehe, sonst quillt der Honig
-- ueber die Wand.
local POND_FILL_MIN_SCALE    = 0.26   -- Radius-Anteil bei fast leerem Lager
local POND_FILL_MIN_HEIGHT   = 0.30
local POND_FILL_MAX_HEIGHT   = 1.05
local POND_FILL_INSET        = 0.4    -- wie weit der Honig hinter dem Beckenrand bleibt
local POND_FILL_COLOR        = Color3.fromRGB(255, 176, 44)
local POND_FILL_TRANSPARENCY = 0.12

-- Wo der Baerchi zum Fressen steht: vor der Luecke im Steinkranz, gemessen ab
-- dem Beckenrand. Die RICHTUNG steht hier bewusst nicht — die rechnet
-- MapService aus POND_OFFSET und BAERCHI_HOME_OFFSET aus. Steinluecke, Bohlen
-- und Standplatz haengen dadurch an EINER Rechnung und koennen nicht
-- auseinanderlaufen, wenn Teich oder Baerchi-Platz verschoben werden.
local POND_STAND_GAP = 3.2

-- Die Bohlen, auf denen er dabei steht.
--
-- Sie liegen fast buendig im Gras (Oberkante 0.06 statt einer richtigen
-- Steghoehe): FigureWalker setzt den Baerchi beim Laufen auf BEET-Hoehe, ein
-- aufgestaender Steg waere also eine Bohle, in der er bis zum Knie steckt.
local POND_PLANK_SIZE   = Vector3.new(8.4, 0.9, 2.4)
local POND_PLANK_GAP    = 0.2    -- Fuge zwischen den beiden Bohlen
local POND_PLANK_TOP    = 0.06   -- Oberkante ueber dem Beet
local POND_PLANK_COLORS: { Color3 } = {
	Color3.fromRGB(168, 118, 70),
	Color3.fromRGB(138,  94,  55),
}
local POND_PEG_SIZE   = Vector3.new(1.7, 0.9, 0.9)   -- Pflock, liegender Zylinder
local POND_PEG_SPREAD = 4.8                          -- Abstand der beiden Pfloecke zur Mitte

-- Reine Zierde am Becken. Die Offsets sind TEICH-lokal, mit derselben Regel
-- wie beim Plot: -Z zeigt dorthin, wo der Baerchi herkommt. Hier steht nur,
-- was NICHT an der Geometrie haengt — Becken, Steine und Bohlen baut
-- MapService, weil sie sich nach POND_RADIUS und dem Standplatz richten.
local POND_DECOR: { DecorPiece } = {
	-- Honigloeffel: der Kopf steckt mitten im Becken, der Stiel lehnt schraeg
	-- nach aussen ueber den Steinrand.
	--
	-- Der Stiel ist ein Zylinder — liegend entlang X, mit rotation.Z gekippt.
	-- Das Vorzeichen entscheidet, welches Ende oben ist: bei +55 zeigte der
	-- Stiel nach INNEN und der Kopf lag auf dem Rand, also ein Loeffel
	-- verkehrt herum.
	{ name = "LoeffelStiel", shape = Enum.PartType.Cylinder, size = Vector3.new(7.0, 0.7, 0.7), offset = Vector3.new(-6.2, 3.15, 0), color = WOOD,  material = Enum.Material.Wood, rotation = Vector3.new(0, 0, -55) },
	{ name = "LoeffelKopf",  shape = Enum.PartType.Ball,     size = Vector3.new(1.8, 1.8, 1.8), offset = Vector3.new(-4.2, 1.05, 0), color = HONEY, material = Enum.Material.Neon },

	-- Zwei Tropfen, die es auf die Sandkante geschafft haben
	{ name = "Tropfen1", shape = Enum.PartType.Ball, size = Vector3.new(1.3, 0.6, 1.3), offset = Vector3.new(7.4, 0.50, 6.2), color = HONEY, material = Enum.Material.Neon },
	{ name = "Tropfen2", shape = Enum.PartType.Ball, size = Vector3.new(0.9, 0.5, 0.9), offset = Vector3.new(9.2, 0.45, 3.4), color = HONEY, material = Enum.Material.Neon },
}

--------------------------------------------------------------------------------
-- Laufbewegung (Honig-Teich, PIT hin/zurueck)
--------------------------------------------------------------------------------

-- Geschwindigkeit, mit der ein Baerchi sich selbststaendig ueber den Plot
-- bzw. zur Arena bewegt (FigureWalker). Ein einziger Wert fuer beide Wege,
-- damit sich das Tempo ueberall gleich anfuehlt.
local WALK_SPEED = 13   -- Studs pro Sekunde

-- ============================================================
-- SPRUNG-ANIMATION BEIM LAUFEN (FigureWalker)
-- ============================================================
-- Diese drei Werte standen frueher als Vorgaben in FigureWalker selbst. Sie
-- sind hierher gewandert, weil man beim Ausprobieren genau an ihnen dreht —
-- und dafuer soll man nicht in ein Util greifen muessen.
--
-- WALK_BOB_PER_STUD ist der wichtigste: er sagt, wie viele Spruenge auf einen
-- zurueckgelegten Stud kommen. Hier lag das Zittern. Mit dem alten Wert 1.0
-- machte der Baerchi bei WALK_SPEED 13 dreizehn winzige Spruenge pro Sekunde —
-- das liest das Auge nicht als Huepfen, sondern als Vibrieren. 0.25 heisst ein
-- Sprung alle vier Studs, also gut drei pro Sekunde: langsam genug, dass man
-- jeden einzelnen sieht.
--
-- Und weil es weniger Spruenge sind, duerfen sie viel hoeher sein: aus 0.35
-- Studs (kaum sichtbar) werden 1.1 — bei einer rund vier Studs hohen Figur ein
-- richtiger Hopser. Wenig und hoch sieht nach Huepfen aus, viel und flach nach
-- Zittern; das ist dieselbe Regel wie bei jeder Cartoon-Animation.
local WALK_BOB_HEIGHT   = 1.1    -- Studs, Scheitelhoehe eines Sprungs
local WALK_BOB_PER_STUD = 0.25   -- Spruenge pro zurueckgelegtem Stud
local WALK_LEAN_DEGREES = 12     -- Vorlehnung in Laufrichtung (war 8)

-- Wie weit sich der Baerchi am Honig-Teich vorbeugt, waehrend er frisst
-- (FigureFX.leanForward). Die DAUER dafuer ist die ohnehin vorhandene
-- Fress-Pause im BaerchiAutopilotService — die Bewegung fuellt sie aus, statt
-- sie zu verlaengern.
local EAT_LEAN_DEGREES = 26

-- Der Honigmast in der Mitte der Wiese.
--
-- Zweck ist nicht Deko sondern Orientierung: von einer Plot-Insel aus sehen
-- alle acht Stege gleich aus, und die Hauptinsel ist ringsum gleich gruen.
-- Ohne einen Punkt, den man von ueberall sieht, laeuft man beim ersten Mal in
-- die falsche Richtung. Der leuchtende Tropfen ganz oben ist genau dafuer da —
-- er steht hoch genug, dass ihn keine Insel verdeckt.
--
-- Ursprung ist die Mitte des Spawn-Pads. Sockel und Mast sind `solid` — man
-- laeuft also dagegen und nicht hindurch. Genau deshalb ist der Sockel schmal
-- gehalten (6 Studs bei 24 Studs Pad): sonst koennte jemand darin spawnen.
local CENTER_DECOR: { DecorPiece } = {
	{ name = "Sockel",   shape = Enum.PartType.Cylinder, size = Vector3.new( 1.0,  6.0,  6.0), offset = Vector3.new( 0,  0.50, 0), color = Color3.fromRGB(225, 214, 186), rotation = UPRIGHT, solid = true },
	{ name = "Sockel2",  shape = Enum.PartType.Cylinder, size = Vector3.new( 0.8,  4.4,  4.4), offset = Vector3.new( 0,  1.40, 0), color = Color3.fromRGB(238, 229, 205), rotation = UPRIGHT, solid = true },
	{ name = "Mast",     shape = Enum.PartType.Cylinder, size = Vector3.new(26.0,  1.8,  1.8), offset = Vector3.new( 0, 14.80, 0), color = WOOD, material = Enum.Material.Wood, rotation = UPRIGHT, solid = true },

	-- Zwei gekreuzte Querhoelzer, damit der Mast aus jeder Richtung gleich
	-- aussieht — er wird ja aus acht verschiedenen Winkeln angeschaut.
	{ name = "QuerA1",   shape = Enum.PartType.Cylinder, size = Vector3.new(11.0,  0.7,  0.7), offset = Vector3.new( 0, 12.00, 0), color = WOOD_DARK, material = Enum.Material.Wood },
	{ name = "QuerA2",   shape = Enum.PartType.Cylinder, size = Vector3.new(11.0,  0.7,  0.7), offset = Vector3.new( 0, 12.00, 0), color = WOOD_DARK, material = Enum.Material.Wood, rotation = Vector3.new(0, 90, 0) },
	{ name = "QuerB1",   shape = Enum.PartType.Cylinder, size = Vector3.new( 7.6,  0.6,  0.6), offset = Vector3.new( 0, 19.00, 0), color = WOOD_DARK, material = Enum.Material.Wood, rotation = Vector3.new(0, 45, 0) },
	{ name = "QuerB2",   shape = Enum.PartType.Cylinder, size = Vector3.new( 7.6,  0.6,  0.6), offset = Vector3.new( 0, 19.00, 0), color = WOOD_DARK, material = Enum.Material.Wood, rotation = Vector3.new(0, 135, 0) },

	-- Wimpel an den unteren Querhoelzern
	{ name = "Wimpel1",  shape = Enum.PartType.Block,    size = Vector3.new( 2.8,  3.6,  0.3), offset = Vector3.new(-4.6, 10.00, 0), color = HONEY },
	{ name = "Wimpel2",  shape = Enum.PartType.Block,    size = Vector3.new( 2.8,  3.6,  0.3), offset = Vector3.new( 4.6, 10.00, 0), color = HONEY },
	{ name = "Wimpel3",  shape = Enum.PartType.Block,    size = Vector3.new( 0.3,  3.6,  2.8), offset = Vector3.new( 0, 10.00, -4.6), color = HONEY_DEEP },
	{ name = "Wimpel4",  shape = Enum.PartType.Block,    size = Vector3.new( 0.3,  3.6,  2.8), offset = Vector3.new( 0, 10.00,  4.6), color = HONEY_DEEP },

	{ name = "Krone",    shape = Enum.PartType.Cylinder, size = Vector3.new( 0.8,  5.0,  5.0), offset = Vector3.new( 0, 27.40, 0), color = WOOD_DARK, material = Enum.Material.Wood, rotation = UPRIGHT },
	{ name = "Tropfen",  shape = Enum.PartType.Ball,     size = Vector3.new( 6.0,  6.0,  6.0), offset = Vector3.new( 0, 29.60, 0), color = HONEY, material = Enum.Material.Neon },
}

--------------------------------------------------------------------------------
-- Baerchi-Aufstellung auf dem Plot
--------------------------------------------------------------------------------

-- Seit dem Equip-System steht nur noch EIN Baerchi sichtbar auf dem Plot —
-- der ausgeruestete. Frueher stand hier ein Raster fuer bis zu 25 Figuren;
-- das ist jetzt ein einzelner fester Platz (plot-lokal, Y = Zusatzhoehe
-- ueber dem Plot), vor den Gebaeuden, Richtung Rand/Bruecke.
local BAERCHI_HOME_OFFSET = Vector3.new(0, 0, 6)

-- Wo der SPIELER auf seinem eigenen Plot spawnt bzw. nach dem Tod
-- respawnt — plot-lokal, wie alles hier oben (siehe Kopf der Datei).
--
-- Bewusst abseits von allem anderen auf dem Plot: der Bienenstock deckt
-- x -28..-16 bei negativem Z, der Teich x 12..32 bei positivem Z, der
-- Baerchi steht bei (0, 6). (-20, 14) liegt mit Rand frei auf der karierten
-- Wiese dazwischen — Zahlen gegen BUILDING_OFFSETS/POND_OFFSET/
-- BAERCHI_HOME_OFFSET gegenpruefen, falls sich das Plot-Layout mal aendert.
local PLAYER_SPAWN_OFFSET = Vector3.new(-20, 0, 14)

-- Baerchi-Figur: das Mesh kommt aus Modules/BaerchiMesh (klont
-- ReplicatedStorage.Assets.BaerchiTemplate bzw. das Rarity-eigene Modell).
-- Fallback-Hoehe fuer den Billboard-Offset, falls das Template (noch) fehlt —
-- die echte Hoehe kommt sonst aus der Bounding-Box des geklonten Mesh.
local BAERCHI_FALLBACK_HEIGHT = 2

-- Klick-Reichweite fuer das Detail-Panel. Gilt auch als Sichtweite fuer die
-- Namensschilder ueber den Figuren — weiter weg waeren sie ohnehin Pixelbrei.
local BAERCHI_CLICK_DISTANCE = 40

-- Wie durchsichtig ein erschoepfter Baerchi (0 HP) dargestellt wird.
-- Bewusst nicht zu viel: er soll matt wirken, nicht wie ein Geist.
local BAERCHI_EXHAUSTED_TRANSPARENCY = 0.45

-- Nachgeholter Figuren-Neuaufbau.
--
-- Steckt die Figur gerade in einer Bewegung (Kampf oder Weg zum Honig-Teich,
-- beides haelt ActivityLock), verschiebt MapService.updateBaerchis den
-- Neuaufbau, statt sie mitten im Schritt zu ersetzen. Diese beiden Werte
-- steuern, wie danach nachgezogen wird:
--   * RETRY:   wie oft geprueft wird, ob die Bewegung vorbei ist. Klein genug,
--              dass die neue Beschriftung direkt nach dem Kampf dasteht.
--   * TIMEOUT: wann aufgegeben wird, falls das Schloss aus irgendeinem Grund
--              haengen bleibt. Deckt eine komplette PIT-Wiedergabe (Hinlauf +
--              Stages + Nachlauf + Ruecklauf) mit Reserve ab. Laeuft er ab,
--              bleibt die Beschriftung bis zur naechsten Datenaenderung
--              stehen — aber es dreht sich keine Endlosschleife.
local FIGURE_REBUILD_RETRY_SECONDS   = 0.25
local FIGURE_REBUILD_TIMEOUT_SECONDS = 30

-- Ruhe-Atmen (FigureFX.idleBob). Gilt fuer jede STEHENDE Figur: den
-- ausgeruesteten Baerchi auf dem Plot und die Gegner in der Arena.
--
-- GROESSER UND LANGSAMER als anfangs (0.16 bei 1.5/s): dieselbe Regel wie bei
-- der Lauf-Animation. Ein kleiner schneller Hub sieht aus, als flackere die
-- Figur; ein groesserer langsamer sieht aus, als atme sie. Bewusst weiterhin
-- ein weiches Auf und Ab und kein Huepfen — eine Figur, die im Stehen dauernd
-- springt, wird bei acht Plots nebeneinander sofort unruhig.
local IDLE_BOB_HEIGHT = 0.30   -- Studs Hub nach oben
local IDLE_BOB_RATE   = 1.0    -- Schwingungen pro Sekunde

-- Sichtweite der Gebaeude-Schilder. Groesser als bei den Figuren, weil man
-- schon von der Plattform-Mitte aus sehen soll, ob sich das Zurueckkommen lohnt.
local BUILDING_SIGN_DISTANCE = 130

--------------------------------------------------------------------------------
-- Holzstege zwischen den Inseln
--------------------------------------------------------------------------------

-- Es gibt 16 Stege, alle gleich: acht von der Hauptinsel zu den Plot-Inseln
-- und acht von dort weiter zur jeweiligen Arena-Insel. Eine LAENGE steht hier
-- bewusst nicht — ein Steg ueberbrueckt immer genau ISLAND_GAP, und MapService
-- rechnet seine Lage aus den Insel-Radien aus.
local BRIDGE_WIDTH  = 12
local BRIDGE_HEIGHT = 1.5
local BRIDGE_COLOR  = Color3.fromRGB(170, 120, 70)   -- Holz

-- Der Steg endet gerade, die Inseln sind rund: an den beiden aeusseren Ecken
-- klafft dadurch eine schmale Sichel (bei 12 Breite und 58 Insel-Radius rund
-- 0.3 Studs). Ein kuerzerer Steg hilft nicht — die Luecke ist der Abstand der
-- Inseln, die wandern nicht mit.
--
-- Stattdessen wird der Steg an BEIDEN Enden um BRIDGE_OVERLAP laenger gebaut
-- und schiebt sich unter die Inselraender. Damit die Oberflaechen dort nicht
-- exakt gleich hoch liegen und flimmern, liegt der Steg minimal tiefer —
-- 0.05 Studs sieht man nicht, und stolpern kann man darueber auch nicht.
local BRIDGE_OVERLAP = 2
local BRIDGE_SINK    = 0.05

-- Gelaender links und rechts, damit die Bruecke nicht wie ein Brett aussieht
local BRIDGE_RAIL_HEIGHT = 3
local BRIDGE_RAIL_WIDTH  = 1
local BRIDGE_RAIL_COLOR  = Color3.fromRGB(140, 95, 55)

--------------------------------------------------------------------------------
-- PIT-Arena (eine pro Spieler, auf der eigenen Arena-Insel)
--------------------------------------------------------------------------------

-- Flache runde Arena statt des frueheren Stufen-Turms: hier stehen spaeter die
-- kaempfenden Baerchis, eine ebene Flaeche ist dafuer brauchbarer als eine
-- Treppe. Das PIT-Level zeigt sich stattdessen an den Saeulen am Rand
-- (eine pro Level) — sichtbarer Fortschritt ohne dass die Kampfflaeche
-- staendig woanders liegt.
--
-- Die Arena ist der GOLDENE Punkt der Welt: goldener Boden, ein leuchtender
-- Ring am Sockelrand und ein Zaun aus leuchtenden Pfosten darum. Sie ist das
-- Ziel, auf das der Spieler hinspielt, und soll von der Hauptinsel aus als
-- heller Fleck am Horizont zu erkennen sein.
local PIT_RADIUS       = 26
local PIT_FLOOR_HEIGHT = 2
local PIT_FLOOR_COLOR  = Color3.fromRGB(240, 200, 90)

-- Der Sockel IST die Arena-Insel: gleiche Dicke (ISLAND_HEIGHT) und gleiche
-- Sandkante wie jede andere Insel, damit die Arena nicht wie ein Fremdkoerper
-- im Wasser steht. Deshalb steht hier auch keine eigene Hoehe mehr.
--
-- PIT_RIM_DROP ist der Grund, warum der Sockel etwas TIEFER liegt als die
-- Kampfflaeche. Laegen beide auf derselben Hoehe, waeren ihre Oberseiten im
-- Bereich der Kampfflaeche exakt deckungsgleich, und Roblox laesst zwei
-- deckungsgleiche Flaechen gegeneinander flimmern (Z-Fighting). Derselbe Grund
-- wie bei BRIDGE_SINK und GRASS_HEIGHT — hier steht die Zahl nur andersherum,
-- weil die Kampfflaeche oben liegt. Der Absatz ist klein genug, dass man ihn
-- im Vorbeigehen nicht als Stufe merkt.
local PIT_BASE_RADIUS = 30
local PIT_RIM_DROP    = 0.35
local PIT_BASE_COLOR  = Color3.fromRGB(150, 130, 100)

-- Leuchtender Ring am Sockelrand. Eine einzige Scheibe, die etwas breiter ist
-- als der Sockel und flach darunter liegt — sichtbar bleibt nur der
-- ueberstehende Rand, und der liest sich als glimmender Kreis. Ein echter Ring
-- aus Segmenten waere ein Dutzend Teile fuer dasselbe Bild.
local PIT_RING_OVERHANG = 1.6
local PIT_RING_HEIGHT   = 0.7
local PIT_RING_COLOR    = Color3.fromRGB(255, 214, 100)

-- Zaun um die Arena: leuchtende Pfoesten auf dem Sockelrand. Zur Steg-Seite
-- hin bleibt eine Luecke frei, sonst muesste man ueber den Zaun springen.
local PIT_FENCE_COUNT        = 22
local PIT_FENCE_SIZE         = Vector3.new(0.8, 4.4, 0.8)
local PIT_FENCE_GAP_DEGREES  = 34    -- Oeffnung zum Steg, halber Winkel je Seite
local PIT_FENCE_INSET        = 1.4   -- wie weit innerhalb des Sockelrandes
local PIT_FENCE_COLOR        = Color3.fromRGB(255, 232, 150)

-- (v15: die Saeulen am Arena-Rand — eine pro PIT-Level — sind mit dem
-- PIT-Level entfallen. Den Fortschritt zeigt jetzt der Tower-Turm, siehe
-- TOWER_SHOWCASE weiter unten.)

-- ============================================================
-- PIT-TURM: EINE ETAGE PRO GESCHAFFTER STAGE
-- ============================================================
-- Waehrend eines Laufs bekommt jede weitere Stage ihre eigene Etage: die
-- Kampfflaeche wird um PIT_TOWER_STEP_HEIGHT angehoben, und darunter waechst
-- sichtbar ein Ring in der Farbe dieser Etage nach. Bei einem kurzen Lauf
-- sieht man davon kaum etwas; bei einem langen faerbt sich ein richtiger Turm
-- unter den Kaempfern auf, gestreift wie aufgeschichtete Boden-Etagen.
--
-- Stage 1 kaempft noch auf der normalen Kampfflaeche (Etage 0, keine
-- zusaetzliche Scheibe) — erst AB Stage 2 kommt die erste Etage dazu. Das
-- macht den ersten Kampf jedes Laufs ununterscheidbar vom Boden, den man von
-- der Bruecke aus kennt, und der Turm entsteht sichtbar erst, wenn der Lauf
-- tatsaechlich in die Laenge geht.
--
-- Der Turm ist reine Wiedergabe wie die Kaempfer selbst: PitArenaService baut
-- ihn Stufe fuer Stufe waehrend der Stages und raeumt ihn wieder ab, sobald
-- der naechste Lauf beginnt (siehe MapService.setPitTowerLevel) — er bleibt
-- also NICHT zwischen zwei Laeufen stehen.
--
-- v15: bei bis zu 100 Stages wird er gestaucht (TowerConfig.getRunFloor,
-- hoechstens TowerConfig.RUN_MAX_FLOORS Etagen). Den STAENDIGEN Turm mit dem
-- Rekord zeigt TOWER_SHOWCASE.
local PIT_TOWER_STEP_HEIGHT = 2.4     -- Studs Anstieg pro Etage
-- Gleicher Radius wie die Kampfflaeche selbst, damit jede neue Etage nahtlos
-- unter der vorherigen sitzt statt als abgesetzter Absatz zu wirken.
local PIT_TOWER_RADIUS = PIT_RADIUS

-- Die Farben wechseln der Reihe nach durch, eine pro Etage — gedeckte,
-- erdige Toene, die als aufgeschichtete Baender lesbar bleiben, auch wenn der
-- Turm mal zwanzig Etagen hoch wird.
-- v12: FORTSETZUNG — DER TURM WAECHST BEIM EINSTIEG HOCH
-- Steigt der Baerchi bei Stage 30 ein, wachsen nach seiner Ankunft in der
-- Arena erst alle 29 Etagen darunter sichtbar hoch, und er faehrt oben mit.
-- Der Spieler soll sehen, wie weit oben er schon ist. Pro Etage
-- PIT_TOWER_RISE_SECONDS_PER_LEVEL, insgesamt hoechstens
-- PIT_TOWER_RISE_MAX_SECONDS (bei sehr hohen Tuermen wachsen mehrere Etagen
-- pro Schritt). Nach dem Lauf faehrt er in PIT_TOWER_FALL_SECONDS wieder
-- nach unten, bevor er heimlaeuft — sonst liefe er auf Turmhoehe durch die
-- Luft zum Plot.
local PIT_TOWER_RISE_SECONDS_PER_LEVEL = 0.07
local PIT_TOWER_RISE_MAX_SECONDS       = 3.0
local PIT_TOWER_FALL_SECONDS           = 0.8

local PIT_TOWER_COLORS: { Color3 } = {
	Color3.fromRGB(196, 168,  62),   -- Ocker
	Color3.fromRGB(140, 108,  58),   -- Braun
	Color3.fromRGB(150, 173,  95),   -- Salbeigruen
	Color3.fromRGB(196, 210, 205),   -- Hellblaugrau
	Color3.fromRGB(150, 120, 150),   -- Mauve
	Color3.fromRGB(196, 110,  60),   -- Terrakotta
	Color3.fromRGB(120,  96,  60),   -- Dunkelbraun
	Color3.fromRGB(210, 196, 160),   -- Creme
}

-- ============================================================
-- v15: DER TOWER-TURM (Angeberflaeche) auf der Arena-Insel
-- ============================================================
-- EIN Turm pro Spieler am aeusseren Rand seiner Arena-Insel (auf der Seite weg
-- vom Steg, auf einem eigenen Sockel, halb ueber dem Wasser). Sein LOOK zeigt
-- den hoechsten je erreichten Tower (Holz -> Stein -> Gold -> Kristall), seine
-- HOEHE den Rekord in diesem Tower (gestaucht auf hoechstens
-- TowerConfig.SHOWCASE_MAX_FLOORS Etagen). Darueber ein Schild "Name · Tower ·
-- Rekord". Die feinen Modelle kommen in Prompt 4 — hier stehen deklarative
-- Platzhalter: eine Etage aus wenigen Teilen, wiederholt, plus Spitze.
--
-- Gebaut wird nur, wenn sich Look oder Rekord aendern (PlotDisplayService,
-- Signatur). Teile-Budget: Sockel + 12 Etagen x Etagen-Teile + Spitze bleibt
-- unter 60 — die ganze Insel unter 250 (gezaehlt mit dem Debug-Befehl
-- "parts").
--
-- Koordinaten: Ursprung = Mitte des Turm-Fusses auf Arena-Hoehe
-- (PLATFORM_TOP_Y), +Y nach oben. Etagen-Teile sind relativ zur UNTERKANTE
-- ihrer Etage.
-- v15: Bestenlisten-Tafel auf der Hauptinsel (LeaderboardService schreibt,
-- MapService baut). Steht zwischen zwei Stegen auf dem Ring um das Event-Pit,
-- die Schrift zeigt nach aussen (zu den Plots, von wo man kommt).
local LEADERBOARD_BOARD = {
	angleDegrees = 22.5,                    -- zwischen zwei Stegen (alle 45 Grad)
	radius       = 80,                      -- Abstand zur Weltmitte
	size         = Vector3.new(20, 13, 0.8),
	postHeight   = 3,
	color        = Color3.fromRGB(92, 64, 40),
	textColor    = Color3.fromRGB(255, 236, 190),
	lines        = 10,
}

local TOWER_SHOWCASE = {
	distance     = 35,      -- Abstand der Turm-Mitte von der Arena-Mitte (nach aussen)
	radius       = 4.5,
	floorHeight  = 3.0,
	plinthHeight = 1.2,
	signGap      = 2.5,     -- Schild ueber der Spitze
	signDistance = 260,
	-- HBB Paket 5 (MAP_V2_SHOWCASE): der Turm steht am BRUECKENKOPF auf der
	-- Hauptinsel, wo alle vorbeilaufen, statt draussen auf der Arena-Insel.
	-- In Steg-Koordinaten: `along` = Abstand zur Weltmitte entlang des
	-- eigenen Stegs, `across` = seitlich davon (zum naechsten Plot hin).
	-- 18 haelt Steg (6), Laternen (7,5 bei r 100) und Deko-Gasse (15) frei;
	-- 106 + Sockelradius bleibt unter dem Inselrand (120).
	bridgeheadAlong  = 106,
	bridgeheadAcross = 18,
}

-- HBB Paket 5 (MAP_V2_BOARDS): drei FESTE Bestenlisten-Tafeln statt einer
-- wechselnden. Je eine in einer Luecke zwischen zwei Stegen (Mitte der
-- Luecke = 22,5 + k x 45 Grad), verteilt, damit jeder Plot eine in der
-- Naehe hat. 67,5 ist der Ei-Haendler, 202,5 das Live-Kampf-Board.
-- Masse wie LEADERBOARD_BOARD.
local LEADERBOARD_BOARDS_V2: { { listId: string, angleDegrees: number } } = {
	{ listId = "Tower",      angleDegrees = 22.5 },
	{ listId = "Rebirths",   angleDegrees = 157.5 },
	{ listId = "Collection", angleDegrees = 292.5 },
}

-- HBB Paket 6 (MAP_V2_LIVE_BOARD): Tafel "LIVE" auf der Hauptinsel. Zeigt,
-- wer gerade in welchem Tower kaempft — Zuschauen ohne Hinlaufen, und ein
-- Grund, selbst einen Lauf zu starten. Bau wie die Bestenlisten-Tafel.
local LIVE_BOARD = {
	angleDegrees = 202.5,
	radius       = 80,
	size         = Vector3.new(20, 11, 0.8),
	postHeight   = 3,
	color        = Color3.fromRGB(60, 42, 30),
	textColor    = Color3.fromRGB(255, 236, 190),
	liveColor    = Color3.fromRGB(255, 90, 70),
	lines        = 8,
	refreshSeconds = 1,
}

-- HBB Paket 6 (MAP_V2_WASP_NEST): Wespen-Nest am Honigmast. Zeigt die Zeit
-- bis zur naechsten Wespenkoenigin (Termin-Gefuehl: "in 12 min ist Boss")
-- und leuchtet in den letzten `glowSeconds` vor dem Boss und waehrenddessen.
-- `offset` relativ zum Mast-Fuss (Weltmitte, PLATFORM_TOP_Y): seitlich am
-- Mast (Radius 0,9) zwischen Wimpeln (bis y 11,8) und oberem Querholz (y 19).
local WASP_NEST = {
	offset       = Vector3.new(3.0, 16.0, 0),
	bodySize     = Vector3.new(4.2, 5.0, 4.2),
	color        = Color3.fromRGB(196, 168, 120),
	stripeColor  = Color3.fromRGB(70, 52, 34),
	glowColor    = Color3.fromRGB(255, 190, 40),
	glowSeconds  = 300,
	signGap      = 2.5,
	signDistance = 320,
}

-- HBB Paket 5 (MAP_V2_ARENA_SPRINT): der Baerchi sprintet den Weg zwischen
-- Plot und Arena (hin und zurueck) statt zu gehen — kuerzere Wartezeit pro
-- Lauf, ohne die Weltgeometrie (Stege, Inselringe) anzufassen.
local ARENA_WALK_SPEED = 21

export type TowerLook = {
	floor : { DecorPiece },   -- Teile EINER Etage (relativ zur Etagen-Unterkante)
	top   : { DecorPiece },   -- Spitze (relativ zur Oberkante der letzten Etage)
	plinth: Color3,
	accent: Color3,
}

local TOWER_LOOKS: { [string]: TowerLook } = {
	Wood = {
		plinth = Color3.fromRGB(120, 92, 62),
		accent = Color3.fromRGB(245, 175, 45),
		floor = {
			{ name = "Wand",  shape = Enum.PartType.Cylinder, size = Vector3.new(2.6, 8.4, 8.4), offset = Vector3.new(0, 1.3, 0), color = Color3.fromRGB(160, 110, 65), material = Enum.Material.Wood, rotation = UPRIGHT, solid = true },
			{ name = "Band",  shape = Enum.PartType.Cylinder, size = Vector3.new(0.4, 9.0, 9.0), offset = Vector3.new(0, 2.8, 0), color = Color3.fromRGB(118, 80, 46), material = Enum.Material.Wood, rotation = UPRIGHT },
		},
		top = {
			{ name = "Dach",  shape = Enum.PartType.Cylinder, size = Vector3.new(1.0, 10.0, 10.0), offset = Vector3.new(0, 0.5, 0), color = Color3.fromRGB(118, 80, 46), material = Enum.Material.Wood, rotation = UPRIGHT },
			{ name = "Honig", shape = Enum.PartType.Ball,     size = Vector3.new(3.0, 3.0, 3.0),   offset = Vector3.new(0, 2.2, 0), color = Color3.fromRGB(245, 175, 45), material = Enum.Material.Neon },
		},
	},
	Stone = {
		plinth = Color3.fromRGB(110, 112, 120),
		accent = Color3.fromRGB(200, 60, 60),
		floor = {
			{ name = "Wand",   shape = Enum.PartType.Cylinder, size = Vector3.new(2.6, 8.6, 8.6), offset = Vector3.new(0, 1.3, 0), color = Color3.fromRGB(150, 155, 165), material = Enum.Material.Slate, rotation = UPRIGHT, solid = true },
			{ name = "Sims",   shape = Enum.PartType.Cylinder, size = Vector3.new(0.4, 9.4, 9.4), offset = Vector3.new(0, 2.8, 0), color = Color3.fromRGB(120, 124, 132), material = Enum.Material.Slate, rotation = UPRIGHT },
			{ name = "Banner", shape = Enum.PartType.Block,    size = Vector3.new(0.2, 1.8, 1.4), offset = Vector3.new(0, 1.4, -4.4), color = Color3.fromRGB(200, 60, 60) },
		},
		top = {
			{ name = "Zinne",  shape = Enum.PartType.Cylinder, size = Vector3.new(1.2, 10.0, 10.0), offset = Vector3.new(0, 0.6, 0), color = Color3.fromRGB(120, 124, 132), material = Enum.Material.Slate, rotation = UPRIGHT },
			{ name = "Fahne",  shape = Enum.PartType.Block,    size = Vector3.new(0.3, 4.0, 0.3),   offset = Vector3.new(0, 3.2, 0), color = Color3.fromRGB(90, 70, 50), material = Enum.Material.Wood },
			{ name = "Tuch",   shape = Enum.PartType.Block,    size = Vector3.new(0.1, 1.2, 2.0),   offset = Vector3.new(0, 4.6, 1.0), color = Color3.fromRGB(200, 60, 60) },
		},
	},
	Gold = {
		plinth = Color3.fromRGB(150, 120, 60),
		accent = Color3.fromRGB(255, 205, 70),
		floor = {
			{ name = "Wand",   shape = Enum.PartType.Cylinder, size = Vector3.new(2.6, 8.6, 8.6), offset = Vector3.new(0, 1.3, 0), color = Color3.fromRGB(240, 200, 90), material = Enum.Material.Metal, rotation = UPRIGHT, solid = true },
			{ name = "Saeule1", shape = Enum.PartType.Block,   size = Vector3.new(0.8, 2.6, 0.8), offset = Vector3.new( 4.3, 1.3, 0), color = Color3.fromRGB(255, 235, 150), material = Enum.Material.Marble },
			{ name = "Saeule2", shape = Enum.PartType.Block,   size = Vector3.new(0.8, 2.6, 0.8), offset = Vector3.new(-4.3, 1.3, 0), color = Color3.fromRGB(255, 235, 150), material = Enum.Material.Marble },
			{ name = "Band",   shape = Enum.PartType.Cylinder, size = Vector3.new(0.4, 9.4, 9.4), offset = Vector3.new(0, 2.8, 0), color = Color3.fromRGB(255, 205, 70), material = Enum.Material.Neon, rotation = UPRIGHT },
		},
		top = {
			{ name = "Kuppel", shape = Enum.PartType.Ball,     size = Vector3.new(8.0, 5.0, 8.0),   offset = Vector3.new(0, 1.2, 0), color = Color3.fromRGB(255, 205, 70), material = Enum.Material.Metal },
			{ name = "Spitze", shape = Enum.PartType.Ball,     size = Vector3.new(1.6, 1.6, 1.6),   offset = Vector3.new(0, 4.2, 0), color = Color3.fromRGB(255, 245, 190), material = Enum.Material.Neon },
		},
	},
	Crystal = {
		plinth = Color3.fromRGB(70, 80, 120),
		accent = Color3.fromRGB(150, 225, 255),
		floor = {
			{ name = "Kern",   shape = Enum.PartType.Cylinder, size = Vector3.new(2.6, 7.4, 7.4), offset = Vector3.new(0, 1.3, 0), color = Color3.fromRGB(120, 140, 220), material = Enum.Material.Glass, rotation = UPRIGHT, solid = true },
			{ name = "Ring",   shape = Enum.PartType.Cylinder, size = Vector3.new(0.3, 9.6, 9.6), offset = Vector3.new(0, 2.6, 0), color = Color3.fromRGB(150, 225, 255), material = Enum.Material.Neon, rotation = UPRIGHT },
			{ name = "Splitter", shape = Enum.PartType.Block,  size = Vector3.new(0.8, 2.2, 0.8), offset = Vector3.new(3.8, 1.2, 0), color = Color3.fromRGB(190, 240, 255), material = Enum.Material.Glass, rotation = Vector3.new(0, 45, 20) },
		},
		top = {
			{ name = "Spitze", shape = Enum.PartType.Block,    size = Vector3.new(2.6, 6.0, 2.6),   offset = Vector3.new(0, 3.0, 0), color = Color3.fromRGB(190, 240, 255), material = Enum.Material.Glass, rotation = Vector3.new(0, 45, 0) },
			{ name = "Schweberring", shape = Enum.PartType.Cylinder, size = Vector3.new(0.3, 7.0, 7.0), offset = Vector3.new(0, 4.4, 0), color = Color3.fromRGB(150, 225, 255), material = Enum.Material.Neon, rotation = UPRIGHT },
		},
	},
}

-- Anzeigetafel ueber der Arena.
--
-- Sie beantwortet die Frage, die man beim Zuschauen sonst nicht beantworten
-- kann: die WIEVIELTE Stage laeuft hier gerade? Die HP-Balken zeigen nur den
-- aktuellen Kampf, und ein Lauf hat davon bis zu 60 hintereinander. Auch der
-- Nachbar, der ueber die Bruecke schaut, sieht damit was los ist.
--
-- Die Reichweite ist grosszuegiger als die der HP-Balken, aber bewusst KEINE
-- karteweite: die Arena liegt 384 Studs von der Weltmitte entfernt, und eine
-- 20 Studs breite Tafel waere von dort ohnehin nur noch ein Fleck. 260 deckt
-- das ab, was sich wirklich lesen laesst — die eigene Plot-Insel (132), den
-- eigenen Steg und die Nachbar-Arena (rund 294).
local PIT_BANNER_HEIGHT   = 15                        -- Studs ueber der Kampfflaeche
local PIT_BANNER_SIZE     = Vector2.new(20, 5)        -- Scale = Studs
local PIT_BANNER_DISTANCE = 260
local PIT_BANNER_RUNNING  = Color3.fromRGB(255, 226, 150)
local PIT_BANNER_WIN      = Color3.fromRGB(150, 235, 160)
local PIT_BANNER_LOSS     = Color3.fromRGB(245, 145, 135)

--------------------------------------------------------------------------------
-- Kampf-Darstellung in der Arena
--------------------------------------------------------------------------------

-- Waehrend eines PIT-Laufs steht der eigene Baerchi sichtbar in der Arena und
-- bekommt Stage fuer Stage einen neuen Gegner gegenueber. Der Kampf ist zu dem
-- Zeitpunkt serverseitig laengst ausgerechnet — das hier ist reine Wiedergabe.
-- Sie laeuft auf dem Server, damit Nachbarn auf der Plattform zuschauen koennen.

-- Abstand der beiden Kaempfer zur Arena-Mitte (sie stehen sich gegenueber)
local FIGHT_SPACING = 9

-- (Die Dauer der Wiedergabe steht seit v15 unten im Abschnitt
-- KAMPF-CHOREOGRAFIE: FIGHT_RUN_TARGET_SECONDS und folgende.)

-- Wie lange die Figuren nach der letzten Stage noch stehen bleiben
local FIGHT_LINGER_SECONDS = 1.6

-- Der Gegner benutzt immer das Standard-Modell, eingefaerbt in diese Farbe —
-- so ist auf einen Blick klar wer der eigene Baerchi ist.
local FIGHT_ENEMY_COLOR = Color3.fromRGB(105, 55, 70)

-- HP-Balken ueber den Kaempfern
local FIGHT_BAR_WIDTH        = 5      -- in Studs (BillboardGui-Scale)
local FIGHT_BAR_HEIGHT       = 0.7
-- Sichtweite. Ohne Grenze waeren die Balken aller acht Arenen quer ueber die
-- Karte zu sehen — und weil sie bewusst AlwaysOnTop sind, auch durch die
-- Landschaft hindurch.
local FIGHT_BAR_DISTANCE     = 120
local FIGHT_BAR_BACK_COLOR   = Color3.fromRGB(30, 28, 32)
local FIGHT_BAR_SELF_COLOR   = Color3.fromRGB(90, 220, 120)
local FIGHT_BAR_ENEMY_COLOR  = Color3.fromRGB(235, 90, 90)

-- Bewegung waehrend der Stages: seit v15 Zusammenprall statt Ausfallschritt
-- (siehe KAMPF-CHOREOGRAFIE weiter unten).

-- Treffer-Blitz auf dem Getroffenen. Warmes Weiss statt Rot: Rot ist
-- in dieser Szene schon die Farbe des gegnerischen HP-Balkens.
local FIGHT_HIT_FLASH_SECONDS = 0.22
local FIGHT_HIT_FLASH_COLOR   = Color3.fromRGB(255, 238, 200)

-- ============================================================
-- v15: KAMPF-CHOREOGRAFIE (Stoesse und Faehigkeiten)
-- ============================================================
-- Seit v15 wird jede Stage ZUG FUER ZUG gezeigt: die Baerchis rennen
-- aufeinander zu, springen sich an und stossen sich zurueck (FigureFX.clash).
-- Jeder eigene Stoss fuellt die Ladeleiste unter dem HP-Balken; ist sie voll,
-- kommt die Faehigkeit mit ihrer Show (SkillFX).
--
-- Damit ein Lauf ueber viele Stages nicht ewig dauert, gibt es ein
-- Zeitbudget: FIGHT_RUN_TARGET_SECONDS fuer den ganzen Lauf (ohne die
-- Faehigkeiten-Shows), daraus die Zeit pro Stage, geklemmt. Passen nicht
-- alle Zuege einer Stage hinein, werden Stoesse ausgelassen (die Leisten
-- springen dann etwas weiter) — Faehigkeiten und der letzte Zug werden nie
-- ausgelassen. Wer welche Zuege zeigt, rechnet Modules/FightTimeline.
--
-- Reicht das Budget nicht einmal fuer die Pflicht-Zuege, laeuft die Stage
-- schneller (Tempo bis FIGHT_MIN_TEMPO, also hoechstens gut doppelt so
-- schnell) — bei 60 Stages wird der Lauf so zur schnellen Montage statt
-- zu einer Minute Pflichtprogramm.
local FIGHT_RUN_TARGET_SECONDS  = 30
local FIGHT_STAGE_MIN_SECONDS   = 0.5
local FIGHT_STAGE_MAX_SECONDS   = 6.0
local FIGHT_MIN_TEMPO           = 0.40
local FIGHT_BEAT_SECONDS        = 0.95   -- ein Stoss (Anlauf, Sprung, Aufprall, zurueck)
local FIGHT_SKILL_BEAT_SECONDS  = 1.15   -- der Stoss nach einer Faehigkeit (wuchtiger)
local FIGHT_ENEMY_INTRO_SECONDS = 0.35   -- kurz stehen, wenn ein neuer Gegner erscheint
local FIGHT_KO_SECONDS          = 0.35   -- besiegter Gegner kippt, bevor der naechste kommt
local FIGHT_CONTACT_GAP         = 2.4    -- Abstand der Fusspunkte beim Aufprall (Studs)
local FIGHT_HOP_HEIGHT          = 1.6    -- Hoehe des Ansprungs
local FIGHT_KNOCKBACK           = 1.3    -- wie weit der Getroffene zurueckgestossen wird
local FIGHT_SKILL_KNOCKBACK     = 3.2    -- ... nach einer Faehigkeit
local FIGHT_ENEMY_STEP_SHARE    = 0.40   -- der Getroffene laeuft dem Angreifer entgegen (Treffen eher in der Mitte)

-- Ladeleiste (unter dem HP-Balken des eigenen Baerchis)
local FIGHT_CHARGE_BAR_HEIGHT   = 0.35
local FIGHT_CHARGE_COLOR        = Color3.fromRGB(120, 200, 255)
local FIGHT_CHARGE_FULL_COLOR   = Color3.fromRGB(255, 214, 70)

-- Aufprall: ein leiser, dumpfer Ton (Lautstaerke bewusst niedrig, er kommt
-- zweimal pro Sekunde) und ein kleiner Funkenstoss.
local FIGHT_BUMP_SOUND          = "rbxasset://sounds/action_jump_land.mp3"
local FIGHT_BUMP_VOLUME         = 0.25
local FIGHT_BUMP_SPARKS         = 6

-- Wie lange der Verlierer der LETZTEN Stage zum Umkippen braucht. Laeuft
-- innerhalb der Nachlauf-Pause (FIGHT_LINGER_SECONDS) ab, verlaengert die
-- Wiedergabe also nicht.
local FIGHT_COLLAPSE_SECONDS = 0.45

--------------------------------------------------------------------------------
-- Globale Beleuchtung ("Candy"-Look statt neutral)
--------------------------------------------------------------------------------
-- Einmalig in MapService.init() auf Lighting gesetzt, siehe
-- DESIGN_VORSCHLAG_TRENDANALYSE_2026-09-11.md Abschnitt 5. Bewusst dezent:
-- ein Simulator-Spiel soll die ganze Spielzeit ueber angenehm aussehen, nicht
-- nach einem einzelnen "Wow"-Moment blenden.
local LIGHTING_CLOCK_TIME        = 15.5   -- spaeter Nachmittag statt Mittag, waermeres Licht
local LIGHTING_BLOOM_INTENSITY   = 0.55
local LIGHTING_BLOOM_THRESHOLD   = 1.4
local LIGHTING_BLOOM_SIZE        = 20
local LIGHTING_SATURATION        = 0.15   -- ColorCorrectionEffect, leicht angehoben
local LIGHTING_CONTRAST          = 0.05
local LIGHTING_SUNRAYS_INTENSITY = 0.15
local LIGHTING_SUNRAYS_SPREAD    = 0.6

--------------------------------------------------------------------------------
-- Rarity-Auren an den Baerchi-Figuren
--------------------------------------------------------------------------------
-- Zusaetzlich zur bestehenden Koerperfarbe (BaerchiConfig.RARITY_COLORS):
-- ab Rare ein leichtes Glitzern, ab Epic ein PointLight, das die Figur auch
-- aus der Distanz als "besonders" erkennbar macht — genau das Prinzip, das
-- laut Trendanalyse bei Steal a Brainrot & Co. den Sammel-Reiz traegt.
-- Bewusst NICHT bei Common/Uncommon: sonst verliert das Leuchten seine
-- Bedeutung als Seltenheits-Signal.
local RARITY_AURA_MIN_SPARKLE: { [string]: boolean } = {
	Common    = false,
	Uncommon  = false,
	Rare      = true,
	Epic      = true,
	Legendary = true,
	Mythic    = true,
	Divine    = true,
	Cosmic    = true,
	Secret    = true,
	Godly     = true,
	Eternal   = true,
	Omega     = true,
}
local RARITY_AURA_MIN_LIGHT: { [string]: boolean } = {
	Common    = false,
	Uncommon  = false,
	Rare      = false,
	Epic      = true,
	Legendary = true,
	Mythic    = true,
	Divine    = true,
	Cosmic    = true,
	Secret    = true,
	Godly     = true,
	Eternal   = true,
	Omega     = true,
}

return {
	CENTER          = CENTER,
	PLATFORM_TOP_Y  = PLATFORM_TOP_Y,
	PLATFORM_RADIUS = PLATFORM_RADIUS,
	ISLAND_HEIGHT   = ISLAND_HEIGHT,
	ISLAND_GAP      = ISLAND_GAP,

	GRASS_TILE      = GRASS_TILE,
	PLOT_GRASS_TILE = PLOT_GRASS_TILE,
	GRASS_HEIGHT    = GRASS_HEIGHT,
	GRASS_DARK      = GRASS_DARK,
	GRASS_LIGHT     = GRASS_LIGHT,

	SHORE_WIDTH = SHORE_WIDTH,
	SHORE_DROP  = SHORE_DROP,
	SHORE_COLOR = SHORE_COLOR,

	WATER_RADIUS       = WATER_RADIUS,
	WATER_DROP         = WATER_DROP,
	WATER_HEIGHT       = WATER_HEIGHT,
	WATER_COLOR        = WATER_COLOR,
	WATER_TRANSPARENCY = WATER_TRANSPARENCY,

	SPAWN_SIZE  = SPAWN_SIZE,
	SPAWN_COLOR = SPAWN_COLOR,

	EVENT_PIT_RADIUS       = EVENT_PIT_RADIUS,
	EVENT_PIT_FLOOR_HEIGHT = EVENT_PIT_FLOOR_HEIGHT,
	EVENT_PIT_GROUND_CLEARANCE = EVENT_PIT_GROUND_CLEARANCE,

	EVENT_PIT_DEFAULT_FLOOR_COLOR = EVENT_PIT_DEFAULT_FLOOR_COLOR,
	EVENT_PIT_DEFAULT_FENCE_COLOR = EVENT_PIT_DEFAULT_FENCE_COLOR,
	EVENT_PIT_DEFAULT_RING_COLOR  = EVENT_PIT_DEFAULT_RING_COLOR,

	EVENT_PIT_RING_OVERHANG = EVENT_PIT_RING_OVERHANG,
	EVENT_PIT_RING_HEIGHT   = EVENT_PIT_RING_HEIGHT,

	EVENT_PIT_FENCE_COUNT       = EVENT_PIT_FENCE_COUNT,
	EVENT_PIT_FENCE_SIZE        = EVENT_PIT_FENCE_SIZE,
	EVENT_PIT_FENCE_GAP_DEGREES = EVENT_PIT_FENCE_GAP_DEGREES,
	EVENT_PIT_FENCE_INSET       = EVENT_PIT_FENCE_INSET,

	EVENT_PIT_BANNER_HEIGHT    = EVENT_PIT_BANNER_HEIGHT,
	EVENT_PIT_BANNER_SIZE      = EVENT_PIT_BANNER_SIZE,
	EVENT_PIT_BANNER_DISTANCE  = EVENT_PIT_BANNER_DISTANCE,
	EVENT_PIT_BANNER_IDLE_COLOR = EVENT_PIT_BANNER_IDLE_COLOR,

	PLOT_COUNT         = PLOT_COUNT,
	PLOT_RING_RADIUS   = PLOT_RING_RADIUS,
	PLOT_ISLAND_RADIUS = PLOT_ISLAND_RADIUS,
	PLOT_ISLAND_COLOR  = PLOT_ISLAND_COLOR,
	PLOT_SIZE          = PLOT_SIZE,

	FENCE_POST_SIZE    = FENCE_POST_SIZE,
	FENCE_POST_SPACING = FENCE_POST_SPACING,
	FENCE_RAIL_HEIGHT  = FENCE_RAIL_HEIGHT,
	FENCE_COLOR        = FENCE_COLOR,

	SIGN_POST_SIZE  = SIGN_POST_SIZE,
	SIGN_BOARD_SIZE = SIGN_BOARD_SIZE,
	SIGN_POST_COLOR = SIGN_POST_COLOR,
	SIGN_TRIM_COLOR = SIGN_TRIM_COLOR,
	SIGN_COLOR      = SIGN_COLOR,

	FLOWER_COUNT      = FLOWER_COUNT,
	FLOWER_SEED       = FLOWER_SEED,
	FLOWER_STEM_SIZE  = FLOWER_STEM_SIZE,
	FLOWER_HEAD_SIZE  = FLOWER_HEAD_SIZE,
	FLOWER_STEM_COLOR = FLOWER_STEM_COLOR,
	FLOWER_COLORS     = FLOWER_COLORS,

	BUILDING_OFFSETS = BUILDING_OFFSETS,
	BUILDING_ORDER   = BUILDING_ORDER,
	BUILDING_DECOR   = BUILDING_DECOR,
	BUILDING_LOOK_DECOR = BUILDING_LOOK_DECOR,
	LOOK_PART_BUDGET    = LOOK_PART_BUDGET,
	combineLookDecor    = combineLookDecor,
	getBuildingDecor    = getBuildingDecor,
	CENTER_DECOR     = CENTER_DECOR,

	HONEY_DOT_SIZE   = HONEY_DOT_SIZE,
	HONEY_DOT_RADIUS = HONEY_DOT_RADIUS,
	HONEY_DOT_HEIGHT = HONEY_DOT_HEIGHT,
	HONEY_DOT_SPACING = HONEY_DOT_SPACING,
	HONEY_DOT_ARC    = HONEY_DOT_ARC,
	HONEY_DOT_COLOR  = HONEY_DOT_COLOR,
	HONEY_DOT_MAX    = HONEY_DOT_MAX,

	POND_OFFSET      = POND_OFFSET,
	POND_RADIUS      = POND_RADIUS,
	POND_RIM_WIDTH   = POND_RIM_WIDTH,
	POND_RIM_TOP     = POND_RIM_TOP,
	POND_FLOOR_TOP   = POND_FLOOR_TOP,
	POND_DISC_HEIGHT = POND_DISC_HEIGHT,
	POND_RIM_COLOR   = POND_RIM_COLOR,
	POND_FLOOR_COLOR = POND_FLOOR_COLOR,

	POND_STONE_COUNT       = POND_STONE_COUNT,
	POND_STONE_GAP_DEGREES = POND_STONE_GAP_DEGREES,
	POND_STONE_SIZES       = POND_STONE_SIZES,
	POND_STONE_COLORS      = POND_STONE_COLORS,

	POND_FILL_MIN_SCALE    = POND_FILL_MIN_SCALE,
	POND_FILL_MIN_HEIGHT   = POND_FILL_MIN_HEIGHT,
	POND_FILL_MAX_HEIGHT   = POND_FILL_MAX_HEIGHT,
	POND_FILL_INSET        = POND_FILL_INSET,
	POND_FILL_COLOR        = POND_FILL_COLOR,
	POND_FILL_TRANSPARENCY = POND_FILL_TRANSPARENCY,

	POND_STAND_GAP    = POND_STAND_GAP,
	POND_PLANK_SIZE   = POND_PLANK_SIZE,
	POND_PLANK_GAP    = POND_PLANK_GAP,
	POND_PLANK_TOP    = POND_PLANK_TOP,
	POND_PLANK_COLORS = POND_PLANK_COLORS,
	POND_PEG_SIZE     = POND_PEG_SIZE,
	POND_PEG_SPREAD   = POND_PEG_SPREAD,
	POND_DECOR        = POND_DECOR,

	WALK_SPEED        = WALK_SPEED,
	WALK_BOB_HEIGHT   = WALK_BOB_HEIGHT,
	WALK_BOB_PER_STUD = WALK_BOB_PER_STUD,
	WALK_LEAN_DEGREES = WALK_LEAN_DEGREES,
	EAT_LEAN_DEGREES  = EAT_LEAN_DEGREES,

	PLAYER_SPAWN_OFFSET             = PLAYER_SPAWN_OFFSET,
	BAERCHI_HOME_OFFSET             = BAERCHI_HOME_OFFSET,
	BAERCHI_FALLBACK_HEIGHT         = BAERCHI_FALLBACK_HEIGHT,
	BAERCHI_CLICK_DISTANCE          = BAERCHI_CLICK_DISTANCE,
	BAERCHI_EXHAUSTED_TRANSPARENCY  = BAERCHI_EXHAUSTED_TRANSPARENCY,
	FIGURE_REBUILD_RETRY_SECONDS    = FIGURE_REBUILD_RETRY_SECONDS,
	FIGURE_REBUILD_TIMEOUT_SECONDS  = FIGURE_REBUILD_TIMEOUT_SECONDS,
	IDLE_BOB_HEIGHT                 = IDLE_BOB_HEIGHT,
	IDLE_BOB_RATE                   = IDLE_BOB_RATE,
	BUILDING_SIGN_DISTANCE          = BUILDING_SIGN_DISTANCE,

	BRIDGE_WIDTH       = BRIDGE_WIDTH,
	BRIDGE_HEIGHT      = BRIDGE_HEIGHT,
	BRIDGE_COLOR       = BRIDGE_COLOR,
	BRIDGE_OVERLAP     = BRIDGE_OVERLAP,
	BRIDGE_SINK        = BRIDGE_SINK,
	BRIDGE_RAIL_HEIGHT = BRIDGE_RAIL_HEIGHT,
	BRIDGE_RAIL_WIDTH  = BRIDGE_RAIL_WIDTH,
	BRIDGE_RAIL_COLOR  = BRIDGE_RAIL_COLOR,

	PIT_RADIUS        = PIT_RADIUS,
	PIT_FLOOR_HEIGHT  = PIT_FLOOR_HEIGHT,
	PIT_FLOOR_COLOR   = PIT_FLOOR_COLOR,
	PIT_BASE_RADIUS   = PIT_BASE_RADIUS,
	PIT_RIM_DROP      = PIT_RIM_DROP,
	PIT_BASE_COLOR    = PIT_BASE_COLOR,

	PIT_RING_OVERHANG = PIT_RING_OVERHANG,
	PIT_RING_HEIGHT   = PIT_RING_HEIGHT,
	PIT_RING_COLOR    = PIT_RING_COLOR,

	TOWER_SHOWCASE = TOWER_SHOWCASE,
	LEADERBOARD_BOARD = LEADERBOARD_BOARD,
	LEADERBOARD_BOARDS_V2 = LEADERBOARD_BOARDS_V2,
	LIVE_BOARD = LIVE_BOARD,
	WASP_NEST = WASP_NEST,
	ARENA_WALK_SPEED = ARENA_WALK_SPEED,
	TOWER_LOOKS    = TOWER_LOOKS,

	PIT_TOWER_STEP_HEIGHT = PIT_TOWER_STEP_HEIGHT,
	PIT_TOWER_RADIUS      = PIT_TOWER_RADIUS,
	PIT_TOWER_COLORS      = PIT_TOWER_COLORS,
	PIT_TOWER_RISE_SECONDS_PER_LEVEL = PIT_TOWER_RISE_SECONDS_PER_LEVEL,
	PIT_TOWER_RISE_MAX_SECONDS       = PIT_TOWER_RISE_MAX_SECONDS,
	PIT_TOWER_FALL_SECONDS           = PIT_TOWER_FALL_SECONDS,

	PIT_FENCE_COUNT       = PIT_FENCE_COUNT,
	PIT_FENCE_SIZE        = PIT_FENCE_SIZE,
	PIT_FENCE_GAP_DEGREES = PIT_FENCE_GAP_DEGREES,
	PIT_FENCE_INSET       = PIT_FENCE_INSET,
	PIT_FENCE_COLOR       = PIT_FENCE_COLOR,

	PIT_BANNER_HEIGHT   = PIT_BANNER_HEIGHT,
	PIT_BANNER_SIZE     = PIT_BANNER_SIZE,
	PIT_BANNER_DISTANCE = PIT_BANNER_DISTANCE,
	PIT_BANNER_RUNNING  = PIT_BANNER_RUNNING,
	PIT_BANNER_WIN      = PIT_BANNER_WIN,
	PIT_BANNER_LOSS     = PIT_BANNER_LOSS,

	FIGHT_SPACING             = FIGHT_SPACING,
	FIGHT_LINGER_SECONDS      = FIGHT_LINGER_SECONDS,
	FIGHT_ENEMY_COLOR         = FIGHT_ENEMY_COLOR,
	FIGHT_BAR_WIDTH           = FIGHT_BAR_WIDTH,
	FIGHT_BAR_HEIGHT          = FIGHT_BAR_HEIGHT,
	FIGHT_BAR_DISTANCE        = FIGHT_BAR_DISTANCE,
	FIGHT_BAR_BACK_COLOR      = FIGHT_BAR_BACK_COLOR,
	FIGHT_BAR_SELF_COLOR      = FIGHT_BAR_SELF_COLOR,
	FIGHT_BAR_ENEMY_COLOR     = FIGHT_BAR_ENEMY_COLOR,
	FIGHT_HIT_FLASH_SECONDS   = FIGHT_HIT_FLASH_SECONDS,
	FIGHT_HIT_FLASH_COLOR     = FIGHT_HIT_FLASH_COLOR,
	FIGHT_COLLAPSE_SECONDS    = FIGHT_COLLAPSE_SECONDS,

	-- v15
	FIGHT_RUN_TARGET_SECONDS  = FIGHT_RUN_TARGET_SECONDS,
	FIGHT_STAGE_MIN_SECONDS   = FIGHT_STAGE_MIN_SECONDS,
	FIGHT_STAGE_MAX_SECONDS   = FIGHT_STAGE_MAX_SECONDS,
	FIGHT_MIN_TEMPO           = FIGHT_MIN_TEMPO,
	FIGHT_KO_SECONDS          = FIGHT_KO_SECONDS,
	FIGHT_BEAT_SECONDS        = FIGHT_BEAT_SECONDS,
	FIGHT_SKILL_BEAT_SECONDS  = FIGHT_SKILL_BEAT_SECONDS,
	FIGHT_ENEMY_INTRO_SECONDS = FIGHT_ENEMY_INTRO_SECONDS,
	FIGHT_CONTACT_GAP         = FIGHT_CONTACT_GAP,
	FIGHT_HOP_HEIGHT          = FIGHT_HOP_HEIGHT,
	FIGHT_KNOCKBACK           = FIGHT_KNOCKBACK,
	FIGHT_SKILL_KNOCKBACK     = FIGHT_SKILL_KNOCKBACK,
	FIGHT_ENEMY_STEP_SHARE    = FIGHT_ENEMY_STEP_SHARE,
	FIGHT_CHARGE_BAR_HEIGHT   = FIGHT_CHARGE_BAR_HEIGHT,
	FIGHT_CHARGE_COLOR        = FIGHT_CHARGE_COLOR,
	FIGHT_CHARGE_FULL_COLOR   = FIGHT_CHARGE_FULL_COLOR,
	FIGHT_BUMP_SOUND          = FIGHT_BUMP_SOUND,
	FIGHT_BUMP_VOLUME         = FIGHT_BUMP_VOLUME,
	FIGHT_BUMP_SPARKS         = FIGHT_BUMP_SPARKS,

	LIGHTING_CLOCK_TIME        = LIGHTING_CLOCK_TIME,
	LIGHTING_BLOOM_INTENSITY   = LIGHTING_BLOOM_INTENSITY,
	LIGHTING_BLOOM_THRESHOLD   = LIGHTING_BLOOM_THRESHOLD,
	LIGHTING_BLOOM_SIZE        = LIGHTING_BLOOM_SIZE,
	LIGHTING_SATURATION        = LIGHTING_SATURATION,
	LIGHTING_CONTRAST          = LIGHTING_CONTRAST,
	LIGHTING_SUNRAYS_INTENSITY = LIGHTING_SUNRAYS_INTENSITY,
	LIGHTING_SUNRAYS_SPREAD    = LIGHTING_SUNRAYS_SPREAD,

	RARITY_AURA_MIN_SPARKLE     = RARITY_AURA_MIN_SPARKLE,
	RARITY_AURA_MIN_LIGHT       = RARITY_AURA_MIN_LIGHT,
	RARITY_AURA_PARTICLE_RATE   = 6,    -- Partikel/Sekunde, dezenter Dauer-Effekt (direkt hier: 200-Locals-Limit)
	RARITY_AURA_LIGHT_RANGE     = 10,
	RARITY_AURA_LIGHT_BRIGHTNESS = 2,
}
