--!strict
-- de.luau
-- ReplicatedStorage/Localization/Strings/de.luau
--
-- Deutsch — die Ursprungssprache des Projekts und deshalb die letzte
-- Rueckfall-Stufe: hier muss JEDER Schluessel stehen. `tools/check_loc.py`
-- prueft, dass en/fr/es nichts enthalten, was hier fehlt, und umgekehrt.
--
-- Konventionen (gelten fuer alle Sprachdateien):
--   * Platzhalter {name} muessen in jeder Sprache dieselben Namen tragen.
--   * Mehrzahl: Schluessel `.one` / `.other`, die Zahl steht als {n} bereit.
--   * "Baerchi", "Gummies", "GoldGummies", "PIT", "Rebirth" sind feste
--     Spielbegriffe und bleiben in allen Sprachen stehen.
--   * Reihenfolge der Abschnitte ist in allen Dateien gleich — so lassen sich
--     die Dateien nebeneinander lesen.

return {
	----------------------------------------------------------------------------
	-- Sprache
	----------------------------------------------------------------------------
	["ui.language.title"] = "Sprache",
	["ui.language.auto"]  = "Automatisch (Roblox)",

	----------------------------------------------------------------------------
	-- Zeit (Theme.formatDuration) — Werte kommen vorformatiert (z.B. "05")
	----------------------------------------------------------------------------
	["time.s"]  = "{s}s",
	["time.ms"] = "{m}m {s}s",
	["time.hm"] = "{h}h {m}m",

	----------------------------------------------------------------------------
	-- Menueleiste
	----------------------------------------------------------------------------
	["ui.menu.eggs"]    = "Eier",
	["ui.menu.baerchis"] = "Baerchis",
	["ui.menu.fight"]   = "Kampf",
	["ui.menu.arena"]   = "Arena",

	----------------------------------------------------------------------------
	-- Rebirth
	----------------------------------------------------------------------------
	["ui.rebirth.title"]   = "Rebirth",
	["ui.rebirth.status"]  = "Rebirth {count}  —  Multiplikator x{mult:d2}",
	["ui.rebirth.cost"]    = "Kostet {cost} Gummies  (du hast {have})",
	["ui.rebirth.loss"]    = "Weg: alle Baerchis, alle Gebäude-Level, das PIT-Level, laufende Bruten und deine Gummies (zurück auf {start}).\nBleibt: GoldGummies, Rang, Statistiken und schon verdiente Ascensions-Eier.",
	["ui.rebirth.reward"]  = "Danach: Multiplikator x{mult:d2}",
	["ui.rebirth.reward_eggs.one"]   = "Danach: Multiplikator x{mult:d2}  —  +{n} Ascensions-Ei",
	["ui.rebirth.reward_eggs.other"] = "Danach: Multiplikator x{mult:d2}  —  +{n} Ascensions-Eier",
	["ui.rebirth.cancel"]  = "Abbrechen",
	["ui.rebirth.confirm"] = "Rebirth!",

	----------------------------------------------------------------------------
	-- Meldungen (Toasts)
	----------------------------------------------------------------------------
	["msg.recycled"]       = "Verwertet: +{gummies} Gummies",
	["msg.recycled_gold"]  = "Verwertet: +{gummies} Gummies  und  +{gold} GoldGummies",
	["msg.offline_honey"]  = "Während du weg warst ({time}): +{honey} Honig",
	["msg.level_up"]       = "Level Up!  Jetzt Level {level}",
	["msg.rebirth_done"]   = "Rebirth {count} geschafft: Multiplikator x{mult:d2}",
	["msg.rebirth_done_eggs.one"]   = "Rebirth {count} geschafft: Multiplikator x{mult:d2} und {n} Ascensions-Ei",
	["msg.rebirth_done_eggs.other"] = "Rebirth {count} geschafft: Multiplikator x{mult:d2} und {n} Ascensions-Eier",

	----------------------------------------------------------------------------
	-- Eier in der Welt (Timer ueber dem Baerchi)
	----------------------------------------------------------------------------
	["ui.egg.full"] = "Lager voll — erst einsammeln!",
	["ui.egg.soon"] = "Nächstes Ei: gleich!",
	["ui.egg.next"] = "Nächstes Ei: {time}",

	----------------------------------------------------------------------------
	-- Abgelehnte Aktionen (Server → Client, siehe Types.LocMsg)
	----------------------------------------------------------------------------
	["err.unknown"]                 = "Aktion nicht möglich",
	["err.player_not_loaded"]       = "Spieler nicht geladen",
	["err.baerchi_not_found"]       = "Baerchi nicht gefunden",
	["err.baerchi_data_corrupt"]    = "Baerchi-Daten defekt",
	["err.baerchi_busy"]            = "Der Baerchi ist gerade unterwegs — kurz warten",
	["err.not_enough_gummies"]      = "Nicht genug Gummies (du hast {have}, du brauchst {need})",
	["err.not_enough_gold_gummies"] = "Nicht genug GoldGummies (du hast {have}, du brauchst {need})",
	["err.rebirth_cost"]            = "Rebirth kostet {cost} Gummies (du hast {have})",

	["err.building_missing"]        = "Gebäude nicht vorhanden",
	["err.building_unknown"]        = "Unbekanntes Gebäude",
	["err.max_level"]               = "Maximales Level erreicht",
	["err.max_pit_level"]           = "Maximales PIT-Level erreicht",
	["err.no_pit_cost"]             = "Keine Kosten für PIT-Level {level}",

	["err.charm_roll_cost"]         = "Ein Wurf kostet {cost} GoldGummies (du hast {have})",
	["err.charm_no_free_slot"]      = "Kein freier Slot zum Würfeln — alles gesperrt oder noch nicht freigeschaltet",
	["err.charm_roll_failed"]       = "Wurf konnte nicht abgerechnet werden",
	["err.charm_slot_empty"]        = "In diesem Slot sitzt noch kein Charm",

	["err.feed_building_empty"]     = "In diesem Gebäude ist gerade kein Honig",
	["err.feed_no_honey"]           = "Kein Honig da — die Gebäude produzieren noch",

	["err.promo_maxed"]             = "Schon voll befördert",
	["err.promo_need_material"]     = "Du brauchst {cost} x {name} als Material (du hast {have})",

	["err.event_already_away"]      = "Dein Baerchi ist schon unterwegs",
	["err.event_no_equipped"]       = "Kein Baerchi ausgerüstet",
	["err.event_not_on_plot"]       = "Der Baerchi steht gerade nicht auf dem Plot",
	["err.event_not_at_event"]      = "Dein Baerchi ist nicht am Event",

	["err.combat_busy"]             = "Der Baerchi kämpft noch im PIT",
	["err.combat_exhausted"]        = "Der Baerchi ist erschöpft — füttere ihn erst mit Honig",

	["err.fuse_self"]               = "Ein Baerchi kann nicht mit sich selbst fusioniert werden",
	["err.fuse_rarity_mismatch"]    = "Beide Baerchis müssen dieselbe Rarity haben",
	["err.fuse_mythic"]             = "Mythic lässt sich nicht weiter fusionieren",
	["err.fuse_no_higher"]          = "Keine höhere Rarity vorhanden",
	["err.fuse_none_defined"]       = "Keine Baerchis der Rarity {rarity} definiert",
	["err.fuse_result_failed"]      = "Fusions-Ergebnis konnte nicht erzeugt werden",

	["err.egg_none_lying"]          = "Es liegt gerade kein Ei herum",
	["err.egg_slots_full"]          = "Alle {slots} Brut-Slots sind belegt",
	["err.egg_gone"]                = "Dieses Ei gibt es nicht mehr",
	["err.egg_wait"]                = "Noch {seconds:dur} bis das Ei fertig ist",
	["err.egg_type_gone"]           = "Diesen Ei-Typ gibt es nicht mehr — du bekommst stattdessen: {egg}",
	["err.egg_internal"]            = "Interner Fehler beim Ausbrüten",
	["err.egg_unknown_type"]        = "Unbekannter Ei-Typ",
	["err.egg_not_buyable"]         = "Kein {egg} im Lager (nicht kaufbar)",

	----------------------------------------------------------------------------
	-- Namen: Raritaeten
	----------------------------------------------------------------------------
	["rarity.Common"]    = "Gewöhnlich",
	["rarity.Uncommon"]  = "Ungewöhnlich",
	["rarity.Rare"]      = "Selten",
	["rarity.Epic"]      = "Episch",
	["rarity.Legendary"] = "Legendär",
	["rarity.Mythic"]    = "Mythisch",

	----------------------------------------------------------------------------
	-- Namen: Baerchis
	----------------------------------------------------------------------------
	["baerchi.RedBaerchi.name"]     = "Roter Baerchi",
	["baerchi.GreenBaerchi.name"]   = "Grüner Baerchi",
	["baerchi.YellowBaerchi.name"]  = "Gelber Baerchi",
	["baerchi.BlueBaerchi.name"]    = "Blauer Baerchi",
	["baerchi.OrangeBaerchi.name"]  = "Oranger Baerchi",
	["baerchi.SugarBaerchi.name"]   = "Zucker-Baerchi",
	["baerchi.CrystalBaerchi.name"] = "Kristall-Baerchi",
	["baerchi.GoldenGrizzly.name"]  = "Goldener Grizzly",
	["baerchi.VoidBaerchi.name"]    = "Void-Baerchi",
	["baerchi.RainbowBaerchi.name"] = "Regenbogen-Baerchi",
	["baerchi.AncientBaerchi.name"] = "Uralter Baerchi",
	["baerchi.CosmicBaerchi.name"]  = "Kosmischer Baerchi",

	----------------------------------------------------------------------------
	-- Namen: Mutationen
	----------------------------------------------------------------------------
	["mutation.Gold.name"]      = "Gold",
	["mutation.Diamond.name"]   = "Diamant",
	["mutation.Bloodrot.name"]  = "Bloodrot",
	["mutation.Celestial.name"] = "Himmlisch",
	["mutation.Candy.name"]     = "Candy",
	["mutation.Lava.name"]      = "Lava",
	["mutation.Galaxy.name"]    = "Galaxie",
	["mutation.Rainbow.name"]   = "Regenbogen",

	----------------------------------------------------------------------------
	-- Namen: Eier
	----------------------------------------------------------------------------
	["egg.BasicEgg.name"]     = "Basis-Ei",
	["egg.SugarEgg.name"]     = "Zucker-Ei",
	["egg.GoldenEgg.name"]    = "Goldenes Ei",
	["egg.CrystalEgg.name"]   = "Kristall-Ei",
	["egg.AscensionEgg.name"] = "Ascensions-Ei",

	----------------------------------------------------------------------------
	-- Namen: Gebaeude
	----------------------------------------------------------------------------
	["building.Beehive.name"]      = "Bienenstock",
	["building.HoneyPot.name"]     = "Honigtopf",
	["building.HoneyPress.name"]   = "Honig-Presse",
	["building.Beehive.short"]     = "Stock",
	["building.HoneyPot.short"]    = "Topf",
	["building.HoneyPress.short"]  = "Presse",

	----------------------------------------------------------------------------
	-- Namen: Raenge (Types.Rank.tier)
	----------------------------------------------------------------------------
	["rank.1"] = "Gummi-Schlüpfling",
	["rank.2"] = "Zucker-Raufbold",
	["rank.3"] = "Kristall-Kämpfer",
	["rank.4"] = "Goldener Champion",
	["rank.5"] = "Kosmische Legende",

	----------------------------------------------------------------------------
	-- Namen: Faehigkeiten
	----------------------------------------------------------------------------
	["skill.BasicPunch.name"]  = "Basis-Schlag",
	["skill.SugarRush.name"]   = "Zuckerrausch",
	["skill.GummyShield.name"] = "Gummischild",
	["skill.IceSlam.name"]     = "Eisschlag",
	["skill.FireBite.name"]    = "Feuerbiss",
	["skill.SugarStorm.name"]  = "Zuckersturm",
	["skill.ShardBlast.name"]  = "Splitterhagel",
	["skill.GoldRush.name"]    = "Gold Rush",
	["skill.BlackHole.name"]   = "Schwarzes Loch",
}
