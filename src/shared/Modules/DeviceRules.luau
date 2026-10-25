--!strict
-- DeviceRules.luau
-- ReplicatedStorage/Modules/DeviceRules.luau
--
-- Einzige Zustaendigkeit:
--   - Reine Regeln (ohne Roblox-Objekte, testbar) fuer das Geraete-Profil:
--     welcher Geraetetyp ist das, und welche Mindestmasse gelten dafuer?
--
-- Welt 1, Paket 6b (20.10.2026). Die Laufzeit-Huelle ist UI/DeviceProfile;
-- die Zahlen stehen NUR hier.
--
-- Geraetetypen:
--   phone    Touch ohne Tastatur, kurze Bildschirmseite < TABLET_SHORT_SIDE
--   tablet   Touch ohne Tastatur, kurze Seite >= TABLET_SHORT_SIDE
--   console  Gamepad ist die letzte Eingabe (oder die einzige vorhandene)
--   desktop  alles andere (Tastatur/Maus)

local DeviceRules = {}

export type Kind = "phone" | "tablet" | "desktop" | "console"

export type Input = {
	touch    : boolean,   -- UserInputService.TouchEnabled
	keyboard : boolean,   -- UserInputService.KeyboardEnabled
	gamepad  : boolean,   -- UserInputService.GamepadEnabled
	lastInput: string?,   -- "touch" | "gamepad" | "keyboard" | "mouse" | nil
	viewportX: number,
	viewportY: number,
}

export type Metrics = {
	kind         : Kind,
	minTouch     : number,   -- kleinste Touch-/Fokusflaeche in Bildschirm-Pixeln
	minMainTouch : number,   -- kleinste Flaeche fuer Hauptknoepfe
	minFontPx    : number,   -- kleinste Schrift in Bildschirm-Pixeln (bei 1080 Zeilen Hoehe)
	safeFraction : number,   -- Rand, den nichts Wichtiges beruehren soll (Anteil der Seite)
	maxPanelHeight: number,  -- groesster Anteil der Hoehe fuer ein Fenster
}

DeviceRules.TABLET_SHORT_SIDE = 600
DeviceRules.KINDS = { "phone", "tablet", "desktop", "console" }

-- Klassifiziert das Geraet.
function DeviceRules.classify(input: Input): Kind
	-- Controller zuletzt benutzt: Konsolen-Oberflaeche (auch am PC mit Gamepad).
	if input.lastInput == "gamepad" then
		return "console"
	end
	-- Nur Gamepad vorhanden (Konsole): kein Touch, keine Tastatur.
	if input.gamepad and not input.touch and not input.keyboard then
		return "console"
	end
	if input.touch and not input.keyboard then
		local shortSide = math.min(input.viewportX, input.viewportY)
		if shortSide > 0 and shortSide < DeviceRules.TABLET_SHORT_SIDE then
			return "phone"
		end
		return "tablet"
	end
	return "desktop"
end

-- Mindestmasse je Geraetetyp.
function DeviceRules.metrics(kind: Kind): Metrics
	if kind == "phone" then
		return { kind = kind, minTouch = 48, minMainTouch = 64, minFontPx = 14, safeFraction = 0, maxPanelHeight = 0.9 }
	elseif kind == "tablet" then
		return { kind = kind, minTouch = 48, minMainTouch = 64, minFontPx = 14, safeFraction = 0, maxPanelHeight = 0.95 }
	elseif kind == "console" then
		return { kind = kind, minTouch = 64, minMainTouch = 64, minFontPx = 24, safeFraction = 0.05, maxPanelHeight = 0.9 }
	end
	return { kind = "desktop", minTouch = 0, minMainTouch = 0, minFontPx = 0, safeFraction = 0, maxPanelHeight = 1 }
end

-- Ist eine Flaeche (Bildschirm-Pixel) gross genug zum Antippen/Anvisieren?
function DeviceRules.touchOk(kind: Kind, widthPx: number, heightPx: number, isMain: boolean?): boolean
	local m = DeviceRules.metrics(kind)
	local need = if isMain then m.minMainTouch else m.minTouch
	return math.min(widthPx, heightPx) >= need
end

-- Mindestschrift in Pixeln, auf die echte Bildschirmhoehe umgerechnet
-- (Konsole: 24 px bei 1080 Zeilen Hoehe).
function DeviceRules.minFontFor(kind: Kind, viewportY: number): number
	local m = DeviceRules.metrics(kind)
	if kind == "console" then
		return m.minFontPx * math.max(viewportY, 1) / 1080
	end
	return m.minFontPx
end

-- Rand in Pixeln fuer eine Bildschirmseite.
function DeviceRules.safeMargin(kind: Kind, sidePx: number): number
	return DeviceRules.metrics(kind).safeFraction * sidePx
end

return DeviceRules
