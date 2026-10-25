--!strict
-- BadgeConfig.luau
-- ReplicatedStorage/Config/BadgeConfig.luau
--
-- Einzige Zustaendigkeit:
--   - Namen der Spieler-Attribute und Masse/Farben des Rang-Billboards (Welt 1, Paket 3, Schalter RANK_BADGE_V2).
--
-- Nichts davon gehoert in MapConfig (steht bei 192/200 lokalen Namen).

local BadgeConfig = {}

-- Der Server setzt diese Attribute am Player, der Client zeichnet daraus das Billboard.
BadgeConfig.ATTR_TOWER   = "BadgeTower"     -- Tower-Id des hoechsten Rekords ("" = Neuling)
BadgeConfig.ATTR_RECORD  = "BadgeRecord"    -- Rekord-Stage dieses Towers
BadgeConfig.ATTR_REBIRTH = "BadgeRebirth"   -- Rebirth-Zahl

BadgeConfig.GUI_NAME = "RankBadgeV2"

-- Fruehere Bildschirm-Groesse (Pixel). Seit dem 21.10. NICHT mehr benutzt, bleibt als Referenz:
-- das Schild hatte beim Herauszoomen immer dieselbe Pixelgroesse und wirkte dadurch gegenueber
-- dem Charakter riesig.
BadgeConfig.SIZE_OTHER = Vector2.new(190, 54)
BadgeConfig.SIZE_SELF  = Vector2.new(220, 62)
-- 21.10. Playtest: Das Schild soll eine FESTE Groesse in der Welt haben (Studs): beim Herauszoomen
-- wird es kleiner, beim Naehern groesser, wie ein echtes Objekt. Werte entsprechen den alten
-- Pixelmassen bei normalem Kameraabstand (ca. 14 Studs, Full-HD).
BadgeConfig.WORLD_SIZE_OTHER = Vector2.new(3.6, 1.02)
BadgeConfig.WORLD_SIZE_SELF  = Vector2.new(4.1, 1.17)
BadgeConfig.TOUCH_SCALE = 1.2                -- Handy/Tablet eine Stufe groesser

BadgeConfig.MAX_DISTANCE = 80                -- ab hier unsichtbar
BadgeConfig.FADE_START   = 60                -- ab hier weiches Ausblenden
BadgeConfig.FADE_TIME    = 0.25
BadgeConfig.MAX_VISIBLE  = 8                 -- hoechstens so viele Billboards gleichzeitig
BadgeConfig.UPDATE_STEP  = 0.2               -- Sekunden zwischen zwei Abstands-Pruefungen (kein Frame-Loop)
BadgeConfig.HEAD_CLEARANCE = 1.6             -- Studs ueber der Kopfoberkante

BadgeConfig.COLORS = {
	outline  = Color3.fromRGB(24, 20, 38),   -- dunkle Kontur (Theme.COLORS.outline)
	name     = Color3.fromRGB(236, 232, 226),
	rookie   = Color3.fromRGB(176, 190, 204),
	rebirth  = Color3.fromRGB(255, 105, 150),
	plaqueBg = Color3.fromRGB(38, 34, 58),
}

BadgeConfig.TEXT = {
	rookie  = "ui.badge.rookie",
	tower   = "ui.badge.tower",     -- "Tower II · 37"
	final   = "ui.badge.final",     -- "Final · 100"
	endless = "ui.badge.endless",   -- "Endlos · 40"
	rebirth = "ui.badge.rebirth",   -- "R5"
	hint    = "ui.badge.hint",      -- Hinweis zur Plakette
}

return BadgeConfig
