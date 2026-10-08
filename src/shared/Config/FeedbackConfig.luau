--!strict
-- FeedbackConfig.luau
-- ReplicatedStorage/Config/FeedbackConfig.luau
--
-- Einzige Zustaendigkeit:
--   - Zuordnung "Meldungs-Anlass → Darstellungs-Klasse" (HBB Paket 1)
--
-- Daten statt Code: wer einen Anlass anders zeigen will, aendert hier eine
-- Zeile, ohne Logik anzufassen. Jede Stelle im Client, die frueher einen
-- Toast ausloeste, meldet sich jetzt ueber UI/Notify mit einem Schluessel
-- aus dieser Tabelle. tools/check_feedback.py schlaegt fehl, wenn ein
-- benutzter Schluessel hier fehlt.
--
-- Klassen:
--   ICON   Zahl/Belohnung: fliegendes Icon und Zahl (UI/Feedback)
--   MOMENT selten und wichtig: grosses Icon in der Mitte (UI/Moment)
--   TOAST  Fehler und Hinweise, die man lesen muss: bleibt Text
--   NONE   sieht man ohnehin (Panel, Balken, Figur): entfaellt
--
-- Mit FeatureFlags.UI_V2_FEEDBACK = false wird jeder Anlass wieder als
-- Toast gezeigt, genau wie vorher.

export type Class = "ICON" | "MOMENT" | "TOAST" | "NONE"

local CLASSES: { [string]: Class } = {
	-- Fehler und Hinweise
	action_failed      = "TOAST",   -- ActionFailed vom Server (Toast.init)
	hatch_failed       = "TOAST",   -- Server antwortet nicht beim Oeffnen (HatchAnimation)
	event_notice_info  = "TOAST",   -- Event-Hinweis zum Mitmachen ("Gib das heisse Ei weiter")
	event_notice_big   = "TOAST",   -- Ansage an alle: Boss kommt/besiegt, Jackpot eines anderen
	event_mid          = "TOAST",   -- Zwischenmeldung waehrend eines Events (Server-Text)

	-- Seltene Momente
	event_mid_rarity   = "MOMENT",  -- UFO: Rarity-Aufstieg
	event_end_mutation = "MOMENT",  -- Event-Ende mit neuer Mutation
	tree_unlocked      = "MOMENT",  -- Ei-Baum: neues Ei frei
	tower_record       = "MOMENT",  -- neuer Tower-Rekord
	tower_milestone    = "MOMENT",  -- Tower-Meilenstein (alle 5 Stages)
	promotion_slot     = "MOMENT",  -- Befoerderung schaltet Charm-Slot frei
	rebirth_done       = "MOMENT",

	-- Zahlen und Belohnungen
	recycle_result     = "ICON",
	offline_honey      = "ICON",    -- Rueckkehr-Anzeige
	offline_eggs       = "ICON",    -- Rueckkehr-Anzeige
	level_up           = "ICON",    -- "Lv 5" ueber dem Baerchi
	feed               = "ICON",    -- XP-Zahl ueber dem Baerchi
	egg_pressed        = "ICON",
	-- Sammel-Update 05.10.
	index_reward       = "MOMENT",  -- Paket 7: Index-Belohnung abgeholt
	special_milestone  = "MOMENT",  -- Paket 6.2: Ascensions-Ei aus besonderem Meilenstein
	incubator          = "ICON",    -- Paket 8: Ei in den Inkubator gelegt / beschleunigt
	comb_delivered     = "ICON",
	recycler_upgraded  = "ICON",
	tower_unlocked     = "MOMENT",  -- 08.10.: neuer Tower frei (Tower-Terminal)
	terminal_locked    = "TOAST",   -- 08.10.: Terminal noch gesperrt (Hinweis statt Panel)
	tower_result       = "ICON",
	promotion          = "ICON",
	egg_collected      = "ICON",
	egg_bought         = "ICON",
	egg_collected_all  = "ICON",
	event_end          = "ICON",    -- Stat-Stufe +1 ueber dem Baerchi
	daily_claimed      = "ICON",
	quest_reward       = "ICON",
	event_notice_good  = "ICON",    -- Event-Belohnung (Gummies/Waben/Fund); Rarity-Aufstieg als Moment

	-- Sieht man ohnehin
	boss_hit           = "NONE",    -- Rueckstoss + Verlangsamung sind deutlich genug
	charm_roll         = "NONE",    -- das Charm-Panel zeigt das Ergebnis
	fusion_result      = "NONE",    -- das Fusions-Panel zeigt das Ergebnis
}

local FeedbackConfig = {}

FeedbackConfig.CLASSES = CLASSES

-- Fliegende Icons
FeedbackConfig.MERGE_WINDOW   = 0.4   -- gleiche Gewinne in diesem Fenster → eine Zahl
FeedbackConfig.MAX_ICONS      = 6     -- gleichzeitig fliegende Icons
FeedbackConfig.FLY_SECONDS    = 0.65
FeedbackConfig.NUMBER_SECONDS = 0.9   -- Aufsteigen der Zahl "+25"
FeedbackConfig.FLOAT_SECONDS  = 1.1   -- Zahl ueber dem Baerchi
FeedbackConfig.MAX_FLOATS     = 4

-- Grosser Moment
FeedbackConfig.MOMENT_SECONDS = 1.6
FeedbackConfig.MOMENT_QUEUE   = 3     -- mehr wartet nie (aeltere fallen weg)
FeedbackConfig.MOMENT_SOUND   = "rbxasset://sounds/electronicpingshort.wav"
FeedbackConfig.MOMENT_VOLUME  = 0.4

-- Rueckkehr-Anzeige: beide Offline-Berichte kommen getrennt; so lange wird
-- gesammelt, bevor die Karte erscheint.
FeedbackConfig.RETURN_COLLECT_SECONDS = 1.2
FeedbackConfig.RETURN_SHOW_SECONDS    = 6

-- 08.10. (Paket G): Erfolgs-Effekt nach einem BESTAETIGTEN Ausbau
-- (UI/UpgradeFX). Alles zusammen bleibt unter 1,2 s.
FeedbackConfig.UPGRADE_FX = {
	POP_SECONDS      = 0.32,   -- Aufspringen und Zurueckfedern des Gebaeudes
	POP_SCALE        = 1.12,   -- groesster Faktor beim Aufspringen
	POP_SCALE_BIG    = 1.18,   -- dasselbe beim Look-Wechsel
	SPARKS           = 14,     -- Funken (EIN Emitter, einmal ausgeloest)
	SPARKS_BIG       = 34,
	SPARK_LIFETIME   = 0.9,
	NUMBER_SECONDS   = 1.15,   -- schwebende Zahl "Level 7 ➜ 8"
	NUMBER_RISE      = 5,      -- Studs
	NUMBER_SIZE      = Vector2.new(260, 64),   -- px
	NUMBER_SIZE_BIG  = Vector2.new(360, 110),
	LOOK_WAIT        = 1.0,    -- so lange auf den Neubau beim Look-Wechsel warten
	PROMPT_LOCK      = 0.4,    -- Prompt nach einem Druck kurz sperren (kein Doppelkauf)
}

function FeedbackConfig.classOf(key: string): Class?
	return CLASSES[key]
end

return FeedbackConfig
