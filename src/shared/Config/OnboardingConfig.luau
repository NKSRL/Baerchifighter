--!strict
-- OnboardingConfig.luau
-- ReplicatedStorage/Config/OnboardingConfig.luau
--
-- Einzige Zustaendigkeit:
--   - Die Etappen der "Reise" (P3, 20.10.): Bearchi bekommen -> Tower I -> ... -> Final 100
--     (Rakete). Reihenfolge, Texte (Loc-Schluessel), Icons, kleine Belohnungen.
--
-- Die Etappen leiten sich NUR aus dem echten Spielstand ab (Modules/OnboardingRules); hier
-- steht kein Zaehler. Belohnungen sind absichtlich klein und werden vom Server genau einmal
-- pro Etappe ausgezahlt (JourneyService, Spielstand-Feld journey.claimed).
-- Schalter: FeatureFlags.ONBOARDING_V2 (setzt UI_V2_GUIDE voraus).

local OnboardingConfig = {}

export type Reward = { goldGummies: number?, gummies: number? }

export type Stage = {
	id      : string,
	textKey : string,   -- ein Satz, <= 12 Woerter (Coach-Text)
	icon    : string,   -- Icons.make-Name (Fallback-Kuerzel, falls kein Bild)
	accent  : Color3,   -- Tower-Farbe als Etappen-Akzent
	reward  : Reward,
}

OnboardingConfig.STAGES = {
	{ id = "hatch",        textKey = "ui.journey.hatch",        icon = "egg",     accent = Color3.fromRGB(255, 214, 120), reward = { goldGummies = 3 } },
	{ id = "equip",        textKey = "ui.journey.equip",        icon = "bear", accent = Color3.fromRGB(255, 190, 90),  reward = { goldGummies = 3 } },
	{ id = "tower1_enter", textKey = "ui.journey.tower1_enter", icon = "swords",   accent = Color3.fromRGB(196, 140, 80),  reward = { goldGummies = 5 } },
	{ id = "tower1_clear", textKey = "ui.journey.tower1_clear", icon = "swords",   accent = Color3.fromRGB(196, 140, 80),  reward = { goldGummies = 10 } },
	{ id = "tower3_open",  textKey = "ui.journey.tower3_open",  icon = "trophy",   accent = Color3.fromRGB(255, 196, 60),  reward = { goldGummies = 15 } },
	{ id = "final_open",   textKey = "ui.journey.final_open",   icon = "crown",   accent = Color3.fromRGB(150, 220, 255), reward = { goldGummies = 20 } },
	{ id = "final_clear",  textKey = "ui.journey.final_clear",  icon = "globe",  accent = Color3.fromRGB(255, 120, 110), reward = { goldGummies = 30 } },
} :: { Stage }

-- Schwellen (aus TowerConfig abgeleitet bzw. fest; Tower I hat 30 Stages)
OnboardingConfig.TOWER1_CLEAR_STAGE = 30
OnboardingConfig.FINAL_CLEAR_STAGE  = 100

-- Panel: Einblendung (Quad, 0,3 s), Leerlauf bis ein Hinweis wiederkehrt
OnboardingConfig.PANEL_TWEEN_SECONDS = 0.3

-- Debug-Namen fuer D:Invoke("journey", ...)
OnboardingConfig.MAX_STAGE = #OnboardingConfig.STAGES

return OnboardingConfig
