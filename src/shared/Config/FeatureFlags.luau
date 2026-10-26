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

	-- HBB Paket 10: Shop mit Gratis-Griff (GoldGummies) und Robux-Paketen
	-- (Pakete erst sichtbar, wenn ShopConfig eine Product-ID hat).
	-- Bericht: docs/HBB_PAKET_10_SHOP_2026-10-05.md
	SHOP_V1            = true,

	-- Playtest 05.10.: Basis-Eier (unbegrenzt beim Haendler) nicht pressbar

	-- Paket 7: Boss-Belohnung nach Stufen
	BOSS_TIERS        = true,

	-- GoldGummies nur noch aus Tages-Quests (spaeter: Gratis-Griff im Shop)
	-- und nur noch fuer Charms. Keine Gold-Kosten bei Gebaeuden/Recycler, kein
	-- Gold aus Tower-Laeufen, Meilensteinen oder Login-Bonus.
	-- Bericht: docs/HBB_GOLD_NUR_CHARMS_2026-10-05.md
	GOLD_CHARMS_ONLY  = true,

	-- Paket 8/9: neue Pacing-Werte. Bleibt aus, bis der Mensch die Tabelle
	-- freigegeben hat (Stopp-Punkt im Plan).
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
	-- Paket 3.8: Bereichs-Schilder (zwei Woerter) auf der Hauptinsel.
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
	-- Welt aufwerten (08.10.2026), je Paket ein Schalter. Reine Client-Optik.
	-- Paket A (Tageslauf) haengt am Schalter AmbienceConfig.DAY_CYCLE.
	-- Bericht: claude/WELT_AUFGEWERTET_UMGESETZT_2026-10-09.md
	WORLD_C_HUB       = true,   -- Mastkrone, Honigfaden, Ankunft, Wegweiser, Pit-Rahmen, Haendler, Nest, Tafeln
	WORLD_F_LIFE      = true,   -- Bienen, Schmetterlinge, Blumen im Wind, Pollenfarbe, Pfotenabdruecke
	WORLD_G_MOMENTS   = true,   -- Welt-Momente: Lichtsaeule, Feuerwerk, Welle, Spirale, Event-Glocke
	-- 21.10. (Welt 2): Plot im Welt-2-Look (Boden, Saeulen, Krone, Fusionsmaschine, neue Modelle fuer
	-- Brunnen/Inkubator/Recycler/Terminal) fuer Spieler mit worlds.unlocked.World2. Vorlagen: ServerStorage.Assets.Welt2.
	-- Aus oder Vorlage fehlt = alter Look. Stand: docs/Worldbuilding.md (Abschnitt Welt 2)
	WELT2_LOOK        = true,
	-- 21.10. (Welt 2): Anime-Ei (Pfad "Anime", 4 Pets), frei ab Welt 2 (Epilog gestartet). Aus = Ei bleibt gesperrt.
	-- Plan: nach Abnahme plus einem Release entfernen. Bericht: claude/HBB_W2_ANIME_EI_PROTOTYP_2026-10-21.md
	ANIME_EGG         = true,

	-- 08.10. (Tower-Terminal): Tower N+1 oeffnet, sobald Tower N geschafft ist
	-- (Rekord >= Stage-Zahl), statt ueber Rebirths. Der Deckel pro Rebirth
	-- begrenzt dann nichts mehr. Aus = alte Regel (STAGE_CAP_BY_REBIRTH).
	TOWER_UNLOCK_BY_CLEAR = true,
	-- 12.10. (Playtest): die Freischaltung gilt pro LEBEN. Ein Rebirth setzt
	-- sie zurueck (towers.unlocked = { I }), gezaehlt wird die beste Stage
	-- dieses Lebens (island.stageBest), nicht der Rekord. Sonst kaempft ein
	-- Level-1-Baerchi direkt nach dem Rebirth in Tower II. Aus = Rekorde
	-- oeffnen fuer immer (Stand 08.10.).
	TOWER_UNLOCK_PER_LIFE = true,
	-- 12.10. (Playtest): Fusion vorerst nur von der Karte des einzelnen
	-- Baerchis ("Staerker machen"). Aus = kein "Fusion: an/aus"-Knopf in der
	-- Sammlung; waehrend einer Fusions-Auswahl steht dort "Abbrechen".
	FUSION_INVENTORY_TOGGLE = false,
	-- 08.10.: Tower-Terminal an der Bruecke (Paket B2)
	TOWER_TERMINAL    = true,
	-- 08.10.: neues Tower-Panel im Look Theme.v2 (Paket D); aus = altes CombatPanel
	TOWER_PANEL_V2    = true,

	-- 13.10.: neue Mesh-Modelle (Waben, Recycler, Honig-Brunnen) aus
	-- ReplicatedStorage.Assets. Aus = alte Parts-Optik aus den Buildern.
	NEW_MODELS_V3     = true,

	-- 14.10.: neues Honig-UI mit den eigenen Bildern (Menue-Knoepfe, Schliessen-
	-- Knopf, Zahnrad, Quest-Fenster/-Leiste, Baerchi-Leiste). Aus = altes UI.
	UI_HONEY_SKIN     = true,

	-- 14.10.: fertige Ei-Modelle (GLB-Import, ReplicatedStorage.Assets.Eggs) fuer
	-- gelegte Eier in der Welt. Aus = alter Look (EggMesh + Gurte/Steine).
	-- Modelle und Zuordnung: Modules/EggModels.
	EGG_MODELS_V1     = true,

	-- R3 (16.10.): Baerchi-Baukasten (Looks: Fellfarbe, Muster, Zubehoer an Andockpunkten).
	-- Aus = heutiger Look (Rarity-Faerbung). Daten: Config/BaerchiLooks.
	BAERCHI_KIT_V1    = false,

	-- 19.10.: Pet-Limit (Config/PetLimitConfig): bei vollem Baerchi-Lager lassen
	-- sich keine Eier mehr oeffnen. Aus = unbegrenzt wie vorher.
	PET_LIMIT_V1      = true,
	-- 19.10.: Verkaufsmodus im Baerchis-Menue (markieren, bestaetigen, loeschen).
	-- Aus = kein Knopf, der Server lehnt RequestSellBaerchis ab.
	PET_SELL_MODE_V1  = true,

	-- 20.10. (Final-Epilog, Prompt 1): Sieg ueber Final 100 speichert Endless
	-- und epilog.state = "pending" atomar, startet die Sequenz (EpilogStart) und
	-- haelt die Endless-Meldung zurueck. Aus = Verhalten wie vor dem Epilog
	-- (die Daten-Migration v18 laeuft trotzdem, sie aendert kein Verhalten).
	-- 20.10. AN (Prompts 1-6 stehen): ohne diesen Schalter loeste Final 100 keine Sequenz aus.
	-- Aus = Verhalten wie vor dem Epilog; in Studio ausserdem: D:Invoke("epilog","on"|"off").
	-- Bericht: docs/HBB_EPILOG_P1_2026-10-20.md
	FINAL_EPILOG      = true,

	-- 20.10. (Map-Stil V2): Boden-Kacheln, Baeume, Buesche, Rand-Buesche und Felsen
	-- als Meshes im Epilog-Insel-Stil (Config/MapStyleConfig, Util/MapBuild/MapMeshes).
	-- Fehlt eine Vorlage, baut der Builder das alte Primitiv. Bleibt AUS bis zur
	-- Abnahme; in Studio: D:Invoke("mapstyle", "on").
	MAP_STYLE_V2      = true,

	-- 20.10. P1: Hauptinsel-Boden wie die alte Classic Baseplate (echte Noppen),
	-- eingefaerbt. Aus = bisheriger Boden (moderne Textur). Bericht: docs/HBB_BODEN_ALT_2026-10-20.md
	-- 22.10.: Deaktiviert zugunsten des Royal-Honey-Sanktuarium-Inselbodens & Gartens.
	MAP_GROUND_OLDSCHOOL = false,

	-- 20.10. P2: Final-Tower Stage 100 ohne Omega-Pet schaffbar (Kurve von Final und
	-- Tower III sinkt, Belohnung gleicht aus). Aus = alte Werte. Endless bleibt fix auf 132.
	-- Bericht: docs/HBB_TOWER_F_BALANCE_2026-10-20.md
	TOWER_F_EASIER = true,

	-- 21.10. Balance V3: Tower I-III brauchen keine Extrem-Rarities mehr (III = Mythic), Final 100 ~ Divine mit
	-- gutem Ausbau, Endless direkt hinter Final und machbar. Ueberschreibt TOWER_F_EASIER. Aus = Stand 20.10.
	-- Bericht: docs/HBB_BALANCE_V3_KONZEPT_2026-10-21.md
	TOWER_BALANCE_V3 = true,

	-- 20.10. P3: "Reise" (Ziel-Leiste, Etappen von Bearchi bis Final 100). Setzt UI_V2_GUIDE
	-- voraus; aus = heutige Fuehrung. Bericht: docs/HBB_ONBOARDING_2026-10-20.md
	ONBOARDING_V2 = true,

	-- 21.10.: Tutorial-Laser aus Pfeil-Partikeln (GuideArrowRules) statt Beam. Aus = alter Beam.
	GUIDE_ARROW_PARTICLES = true,

	-- 20.10. P4: dauerhafte Raketen-Insel mit Bruecke in Welt 1 (Hinweis auf Welt 2; Start
	-- bleibt im Epilog). Aus = Welt wie vorher. Bericht: docs/HBB_RAKETENINSEL_2026-10-20.md
	ROCKET_ISLAND = true,

	-- 20.10. (Welt 1, Paket 3): Rang ueber dem Kopf neu (Name, Plakette "Tower II · 37", Rebirth "R5", "Neuling").
	-- Server setzt nur Spieler-Attribute, der Client baut das Billboard. Aus = altes Abzeichen (PlayerBadgeService).
	-- Bericht: docs/HBB_W1_P3_2026-10-20.md
	RANK_BADGE_V2 = true,

	-- 20.10. (Welt 1, Paket 5a): Rebirth erst nach Welt 2 (data.epilog.state == "launched").
	-- Wer schon einmal rebirthed hat, behaelt den Zugang (Bestandsschutz). Inkubator-Ausbau
	-- haengt dann am Tower-Sieg statt an Rebirths. Aus = alte Regel. Bericht: docs/HBB_W1_P5_2026-10-20.md
	REBIRTH_NEEDS_WORLD2 = true,

	-- 20.10. (Welt 1, Paket 5b): Staerke-Modell V2: Rarity = moderate Basis (+6 %/Stufe), dazu ein individueller Wurf
	-- aus der uid (PowerRules/PowerConfig), Tower-Gegner skaliert (PowerConfig.TOWER_ENEMY_SCALE). Aus = altes Modell.
	POWER_MODEL_V2 = false,

	-- 20.10. (Welt 1, Paket 5c): Drop-Raten V2: seltenstes Pet je Ei 10 % / 5 % / 1 % / 0,1 % nach Fortschritt
	-- (EggConfig.RARITY_DIST_V2). Aus = alte Verteilung (RARITY_DIST). Standard AUS bis bestaetigt.
	DROPRATES_V2 = true,   -- 21.10.: an (seltenste Stufe je Ei 5-10 % / 1 % / 0,1-3 %, siehe EggConfig.RAREST_PCT_V2)

	-- 20.10. (Welt 1, Paket 5d): Ascension-Pfad per Fortschritt statt Rebirth (Welt 2 offen + Schluessel-Pet des
	-- Vorgaengers) und das Hoffnungs-Pet (1 % im Ascension-Ei). Aus = Rebirth-Gates, Pet faellt nirgends.
	ASCENSION_V2 = true,

	-- 20.10. (Welt 1, Paket 6): Geraete-Profil (phone/tablet/desktop/console) und adaptive Oberflaeche
	-- (Mindest-Touchflaechen, Konsolen-Rand, Glyphen). Aus = Oberflaeche wie vor Paket 6.
	UI_ADAPTIVE_V1 = true,
	-- 20.10. (Welt 1, Paket 6d): Gamepad-Steuerung (Fokus, B schliesst, SchulterTasten, Prompt-Taste X).
	-- Wirkt nur, solange das Geraet ein Gamepad nutzt. Aus = bisherige Eingabe.
	CONSOLE_V1 = true,

	-- 25.10.: Honig-Kolosseum als neues Kampf-Pit (Mauer, Tribuenen, Tore, Waben-Boden) und
	-- Zaun aussen an jeder Turm-Etage samt Kollision der obersten Etage. Vorlagen:
	-- ServerStorage.Assets.PitV2. Aus oder Vorlage fehlt = altes Pit. Plan: nach Abnahme
	-- plus einem Release entfernen. Bericht: docs/Worldbuilding.md (Abschnitt Kampf-Pit V2)
	PIT_V2 = true,
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
