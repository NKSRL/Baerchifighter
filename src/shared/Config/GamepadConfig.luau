--!strict
-- GamepadConfig.luau
-- ReplicatedStorage/Config/GamepadConfig.luau
--
-- Einzige Zustaendigkeit:
--   - Die Controller-Belegung (Welt 1, Paket 6d) als Tabelle. Kein Code,
--     keine Logik: GamepadController liest sie, der Test prueft sie.
--
-- Zwei Ebenen: `panel` gilt, solange ein Fenster offen ist; `world`, solange
-- keins offen ist. Dieselbe Taste darf in beiden Ebenen etwas anderes tun
-- (L1/R1: Tabs im Fenster, Event/Fight in der Welt), aber nie zweimal in einer.
-- Verwendet werden nur Tasten, die Roblox auf Xbox UND PlayStation kennt.

local GamepadConfig = {}

export type Binding = {
	key   : string,   -- Name in Enum.KeyCode
	action: string,   -- Kennung, siehe GamepadController
	glyph : string,   -- Kurztext fuer Knopf-Beschriftung
}

GamepadConfig.WORLD = {
	{ key = "ButtonL1",    action = "event",    glyph = "L1" },    -- Event-Knopf der Pet-Leiste
	{ key = "ButtonR1",    action = "fight",    glyph = "R1" },    -- Fight-Knopf
	{ key = "DPadDown",    action = "recall",   glyph = "▼" },     -- Pet zurueckholen
	{ key = "ButtonY",     action = "menu",     glyph = "Y" },     -- Hauptmenue (Fokus auf die Menueleiste)
	{ key = "ButtonStart", action = "pause",    glyph = "≡" },     -- Einstellungen (Zahnrad/Audio)
	{ key = "ButtonR3",    action = "inspect",  glyph = "R3" },    -- Spieler anvisieren -> Profil
} :: { Binding }

GamepadConfig.PANEL = {
	{ key = "ButtonB",     action = "close",    glyph = "B" },     -- oberstes Fenster schliessen
	{ key = "ButtonY",     action = "menu",     glyph = "Y" },     -- Hauptmenue
	{ key = "ButtonX",     action = "primary",  glyph = "X" },     -- Kontextaktion: Hauptknopf des Fensters
	{ key = "ButtonL1",    action = "tabPrev",  glyph = "L1" },    -- Tab links
	{ key = "ButtonR1",    action = "tabNext",  glyph = "R1" },    -- Tab rechts
	{ key = "ButtonL2",    action = "pagePrev", glyph = "L2" },    -- Liste blaettern
	{ key = "ButtonR2",    action = "pageNext", glyph = "R2" },
	{ key = "ButtonStart", action = "pause",    glyph = "≡" },
} :: { Binding }

-- A bestaetigt immer (Roblox-Standard fuer die Auswahl), nicht neu gebunden.
GamepadConfig.CONFIRM_KEY = "ButtonA"

-- ProximityPrompts: Taste auf dem Controller (Haltedauer bleibt wie am PC).
GamepadConfig.PROMPT_KEY = "ButtonX"

-- Blaettern in Listen: Anteil der sichtbaren Hoehe je L2/R2
GamepadConfig.PAGE_FRACTION = 0.8

-- Name der Bindungen bei ContextActionService (immer paarweise Bind/Unbind)
GamepadConfig.ACTION_PREFIX = "HBB_Pad_"

-- Auswahl-Rahmen (SelectionImageObject): Honig-Gold, dick genug auf jedem Hintergrund
GamepadConfig.SELECTION_COLOR     = Color3.fromRGB(255, 196, 40)
GamepadConfig.SELECTION_THICKNESS = 4

-- Legende unten (nur Konsole): Kurztext-Schluessel in Loc
GamepadConfig.LEGEND = {
	{ glyph = "A", textKey = "ui.pad.confirm" },
	{ glyph = "B", textKey = "ui.pad.back" },
	{ glyph = "Y", textKey = "ui.pad.menu" },
}

return GamepadConfig
