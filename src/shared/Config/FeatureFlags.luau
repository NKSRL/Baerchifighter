--!strict
-- FeatureFlags.luau
-- ReplicatedStorage/Config/FeatureFlags.luau
--
-- Einzige Zustaendigkeit:
--   - Schalter fuer jede sichtbare Aenderung aus dem Honey-Bear-Brawl-Plan
--
-- Jede neue Anzeige haengt an genau einem Schalter. `true` = neuer Weg,
-- `false` = das Spiel verhaelt sich wie vor dem jeweiligen Paket. So bleibt
-- jede Aenderung einzeln zuruecknehmbar, ohne Code anzufassen.
--
-- Liegt in ReplicatedStorage, weil Server UND Client dieselbe Antwort brauchen
-- (z.B. Boss-Stufen: Server zahlt aus, Client zeigt die Truhe).
--
-- Ein unbekannter Name ist ein Tippfehler. In Studio bricht isOn dann mit
-- einem Fehler ab, damit er sofort auffaellt; im Live-Spiel gilt der Schalter
-- still als aus, damit ein Tippfehler keinen Server abstuerzen laesst.

local RunService = game:GetService("RunService")

local FLAGS: { [string]: boolean } = {
	-- Paket 1: Icons und Zahlen statt Text-Toasts
	UI_V2_FEEDBACK    = true,
	-- Paket 2: Beam-Fuehrung, Quest-Tracker mit Icons, ruhige Dialoge
	UI_V2_GUIDE       = true,
	-- Paket 3: Elemente erscheinen erst, wenn man sie braucht
	UI_V2_PROGRESSIVE = true,
	-- Paket 4: Upgrade-Tab, Kampfwert-Zahl, Rarity-Baender
	UI_V2_UPGRADE_TAB = true,

	-- Paket 5: Map ohne Umbau
	MAP_V2_MERCHANT   = true,
	MAP_V2_HOME       = true,
	MAP_V2_SHOWCASE   = true,
	MAP_V2_BOARDS     = true,
	MAP_V2_ARENA_SPRINT = true,   -- Baerchi sprintet zur Arena und zurueck
	-- Paket 6
	MAP_V2_LIVE_BOARD = true,
	MAP_V2_WASP_NEST  = true,
	EVENT_V2_TIMER    = true,

	-- Honig-Teich statt Stock + Veredler: EIN Gebaeude, Looks bis zum
	-- Honig-Springbrunnen, Baerchi wohnt am Becken (kein Hin- und Herlaufen).
	-- Bericht: docs/HBB_HONIG_TEICH_2026-10-05.md
	HONEY_POND_V2      = true,

	-- Entscheidung 05.10.: Laeufe starten immer bei Stage 1. Ab der letzten
	-- Stage nur per Klick gegen Gummies (kleines Feld, 7 s, UI/FightStartPrompt).
	FIGHT_RESUME_PROMPT = true,

	-- HBB Paket 10: Shop mit Gratis-Griff (GoldGummies) und Robux-Paketen
	-- (Pakete erst sichtbar, wenn ShopConfig eine Product-ID hat).
	-- Bericht: docs/HBB_PAKET_10_SHOP_2026-10-05.md
	SHOP_V1            = true,

	-- Playtest 05.10.: Basis-Eier (unbegrenzt beim Haendler) nicht pressbar
	PRESS_NO_BASIC_EGG = true,

	-- Paket 7: Boss-Belohnung nach Stufen
	BOSS_TIERS        = true,

	-- GoldGummies nur noch aus Tages-Quests (spaeter: Gratis-Griff im Shop)
	-- und nur noch fuer Charms. Keine Gold-Kosten bei Gebaeuden/Recycler, kein
	-- Gold aus Tower-Laeufen, Meilensteinen oder Login-Bonus.
	-- Bericht: docs/HBB_GOLD_NUR_CHARMS_2026-10-05.md
	GOLD_CHARMS_ONLY  = true,

	-- Paket 8/9: neue Pacing-Werte. Bleibt aus, bis der Mensch die Tabelle
	-- freigegeben hat (Stopp-Punkt im Plan).
	PACING_V2         = false,
	-- Paket 9: Endless-Tower (Stage 101+), freigegeben 05.10.
	-- Bericht: docs/HBB_PAKET_9_ENDLESS_2026-10-05.md
	ENDLESS           = true,

	-- Sammel-Update 05.10. (docs/SAMMEL_UPDATE_UMGESETZT_2026-10-05.md):
	-- Paket 8: Inkubator auf dem Plot. Aus = Eier gehen wie vorher sofort auf,
	-- der Inkubator wird weder gebaut noch angeboten.
	INCUBATOR         = true,
	-- Paket 7: Index-Belohnungen (Abholen im Index).
	INDEX_REWARDS     = true,
	-- Paket 5.2: Kampf um die Mitte — gegnerische Event-Baerchis stossen
	-- Spieler ohne eigenen Baerchi im Event-Pit.
	PIT_BRAWL         = true,
	-- Paket 3.8: Bereichs-Schilder (zwei Woerter) auf der Hauptinsel.
	AREA_SIGNS        = true,
	-- Wunsch 05.10.: Baerchi darf mehrmals ins selbe UFO; nach dem Absetzen
	-- ist sein Level fuer EventConfig.UFO.DROP_WEAKEN_SECONDS halbiert.
	-- Aus = wie vorher (wer schon an Bord war, geht heim).
	UFO_REJOIN        = true,
	-- Wunsch 05.10.: aufgeraeumtes HUD. Honig-Brunnen nur vor Ort verbessern
	-- (E, kein Fenster, Schild mit Level und Preis), keine Kacheln "Verbessern"
	-- und "Inkubator" mehr, Quests als kleiner Knopf neben dem Zahnrad, Shop
	-- daneben (eine Zeile), groessere Kacheln rechts.
	HUD_ROW_V2        = true,
	-- Wunsch 05.10.: Inkubator = Baerchi hineinsetzen, er bruetet je nach
	-- Rarity im Takt zusaetzliche Eier (IncubatorConfig.BREED_*). Eier gehen
	-- wieder sofort auf (kein Brueten von Eiern mehr). Aus = Ei-Inkubator wie
	-- im Sammel-Update.
	INCUBATOR_BREED   = true,
}

local FeatureFlags = {}

FeatureFlags.FLAGS = FLAGS

function FeatureFlags.isOn(name: string): boolean
	local value = FLAGS[name]
	if value == nil then
		if RunService:IsStudio() then
			error("[FeatureFlags] Unbekannter Schalter: " .. tostring(name), 2)
		end
		return false
	end
	return value
end

return FeatureFlags
