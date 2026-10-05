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
	["ui.rebirth.loss"]    = "Weg: alle Gebäude-Level, die Level deiner Baerchis und deine Gummies (zurück auf {start}).\nBleibt: deine Baerchis, alle Eier, der Ei-Baum, Tower-Rekorde, GoldGummies, Rang und Statistiken.",
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
	["err.recycle_equipped"] = "Rüste zuerst einen anderen Baerchi aus, dann kannst du diesen verwerten",
	["err.honey_in_pit"] = "Der Baerchi kämpft gerade im PIT",
	["err.event_ufo"] = "Dein Baerchi wird gerade vom UFO entführt",
	["err.combat_no_last_run"] = "Kein letzter Lauf auf diesem PIT-Level — starte von vorn",
	["err.fuse_equipped_away"] = "Der ausgerüstete Baerchi ist gerade unterwegs — kurz warten",
	["err.egg_none_in_stock"] = "Kein {egg} im Lager",

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
	["baerchi.CosmicBaerchi.name"]  = "Sternen-Baerchi",

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
	["building.HoneyRefiner.name"] = "Honig-Raffinerie",
	["building.Beehive.short"]     = "Stock",
	["building.HoneyRefiner.short"] = "Raffinerie",
	["building.HoneyPond.name"]    = "Honig-Brunnen",
	["building.HoneyPond.short"]   = "Brunnen",

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

	----------------------------------------------------------------------------
	-- Index, Quests (v13)
	----------------------------------------------------------------------------
	["ui.inventory.tab_pets"] = "Meine Baerchis",
	["ui.inventory.tab_index"] = "Index",
	["ui.index.unknown"] = "???",
	["ui.index.drops_from"] = "Faellt aus:",
	["ui.index.you_have"] = "Du hast {n} im Lager",
	["ui.index.no_source"] = "Aus keinem Ei zu bekommen.",
	["ui.index.progress"] = "Entdeckt {found}/{total}",
	["ui.quest.header"] = "Quest {done}/{total}",
	["ui.quest.chain_done"] = "Alle Einsteiger-Quests geschafft!",
	["ui.quest.claim"] = "Belohnung abholen",
	["ui.quest.daily_link"] = "Tages-Quests {done}/{total}  >",
	["ui.quest.panel_title"] = "Quests",
	["ui.quest.section_chain"] = "Einsteiger-Quests",
	["ui.quest.section_daily"] = "Tages-Quests",
	["ui.quest.resets_in"] = "Neue Tages-Quests in {time}",
	["ui.quest.claimed"] = "Erledigt",
	["ui.quest.claim_short"] = "Abholen",
	["ui.quest.reward_gummies"] = "+{n} Gummies",
	["ui.quest.reward_with_egg"] = "+{n} Gummies und ein {egg}",
	["ui.quest.reward_gold"] = "+{n} GoldGummies",
	["ui.quest.toast"] = "Quest geschafft: {text}",
	["err.quest_unknown"] = "Unbekannte Quest",
	["err.quest_already_claimed"] = "Schon abgeholt",
	["err.quest_not_current"] = "Das ist nicht die aktuelle Quest",
	["err.quest_not_done"] = "Quest noch nicht geschafft",
	["quest.c_hatch1.title"] = "Oeffne dein erstes Ei",
	["quest.c_hatch1.hint"] = "Tippe rechts auf EIER und oeffne ein Ei aus dem Lager.",
	["quest.c_pets3.title"] = "Besitze 3 Baerchis",
	["quest.c_pets3.hint"] = "Oeffne weiter Eier - jedes Ei gibt dir einen Baerchi.",
	["quest.c_fight1.title"] = "Gewinne deinen ersten Kampf",
	["quest.c_fight1.hint"] = "Druecke unten auf Kampf, um deinen Baerchi in die PIT zu schicken.",
	["quest.c_fight5.title"] = "Gewinne 5 Kaempfe",
	["quest.c_fight5.hint"] = "Kaempfe weiter in der PIT - jede geschaffte Stage zaehlt.",
	["quest.c_upgrade.title"] = "Baue ein Gebaeude aus",
	["quest.c_upgrade.hint"] = "Geh zu einem Gebaeude auf deinem Plot und druecke E zum Ausbauen.",
	["quest.c_hatch5.title"] = "Oeffne 5 Eier",
	["quest.c_hatch5.hint"] = "Eier liegen auch auf deinem Plot herum - lauf drueber, um sie einzusammeln.",
	["quest.c_discover5.title"] = "Entdecke 5 Baerchis",
	["quest.c_discover5.hint"] = "Oeffne BAERCHIS > Index und sieh nach, welches Ei was bringt.",
	["quest.c_fuse1.title"] = "Fusioniere zwei Baerchis",
	["quest.c_fuse1.hint"] = "Schalte in BAERCHIS die Fusion an und waehle zwei derselben Rarity.",
	["quest.c_tower10.title"] = "Schaffe Stage 10 im Tower",
	["quest.c_tower10.hint"] = "Schick deinen Bärchi mit dem Kampf-Knopf in den Tower und fütter ihn vorher mit Honig.",
	["quest.c_discover8.title"] = "Entdecke 8 Baerchis",
	["quest.c_discover8.hint"] = "Tippe im Index eine schwarze Silhouette an, um zu sehen, welches Ei du brauchst.",
	["quest.c_fight25.title"] = "Gewinne 25 Kaempfe",
	["quest.c_fight25.hint"] = "Staerkere Baerchis kommen weiter. Fusionieren, befoerdern, wiederholen.",
	["quest.c_discover10.title"] = "Entdecke 10 Baerchis",
	["quest.c_discover10.hint"] = "Hoehere Eier enthalten die seltenen - schau im Index nach den Chancen.",
	["quest.d_hatch3.title"] = "Oeffne heute 3 Eier",
	["quest.d_hatch3.hint"] = "Eier aus dem Lager und vom Plot zaehlen beide.",
	["quest.d_fight8.title"] = "Gewinne heute 8 Kaempfe",
	["quest.d_fight8.hint"] = "Nutze den Kampf-Knopf unten.",
	["quest.d_earn.title"] = "Verdiene heute 1.500 Gummies",
	["quest.d_earn.hint"] = "Kaempfe und deine Gebaeude zahlen Gummies aus.",

	----------------------------------------------------------------------------
	-- v14: Mega Egg Tree (Ei-Baum, neue Eier, neue Baerchis, Faehigkeiten)
	----------------------------------------------------------------------------
	["ui.menu.tree"] = "Ei-Baum",
	["ui.tree.title"] = "Ei-Baum",
	["ui.tree.title_bp"] = "Ei-Baum  —  Blaupausen: {n}",
	["ui.tree.cond_hatch"] = "{egg} öffnen: {have}/{need}",
	["ui.tree.cond_any"] = "Endeier (je 6×): {have}/{need}",
	["ui.tree.cond_index"] = "{rarity} im Index: {have}/{need}",
	["ui.tree.cond_rebirth"] = "Rebirth: {have}/{need}",
	["ui.tree.cond_blueprint"] = "Blaupause eingesetzt",
	["ui.tree.path_line"] = "Pfad {path} — {goal}\nØ Rarity {avg}",
	["ui.tree.unlocked"] = "Freigeschaltet",
	["ui.tree.ready"] = "Bereit — wird gleich frei",
	["ui.tree.locked"] = "Gesperrt",
	["ui.tree.needs"] = "Noch nötig",
	["ui.tree.in_stock"] = "Im Lager: {n}",
	["ui.tree.open"] = "Öffnen",
	["ui.tree.press"] = "Pressen: {n} → 1 {egg}",
	["ui.tree.use_blueprint"] = "Blaupause einsetzen ({n} übrig)",
	["ui.tree.drops"] = "Was rauskommt",
	["ui.tree.lock_short"] = "zu",
	["ui.tree.jump_hint"] = "Sprung-Ei aus einem Event: lässt sich öffnen, schaltet den Knoten aber nicht frei.",
	["msg.tree_unlocked"] = "Ei-Baum: {egg} freigeschaltet!",
	["msg.pressed"] = "Gepresst: {n}× {from} → 1 {to}",
	["msg.rebirth_done_list"] = "Rebirth {count} geschafft: Multiplikator x{mult:d2} und {eggs}",
	["ui.rebirth.reward_list"] = "Danach: Multiplikator x{mult:d2}  —  {eggs}",
	["err.press_blocked"] = "Eier aus dem Ascensions-Pfad lassen sich nicht pressen",
	["err.press_no_next"] = "Für dieses Ei gibt es keine nächste Stufe",
	["err.press_target_locked"] = "Schalte zuerst {egg} im Ei-Baum frei",
	["err.press_not_enough"] = "Du brauchst {n}× {egg} (du hast {have})",
	["err.blueprint_not_here"] = "Hier passt gerade keine Blaupause",
	["rarity.Divine"] = "Göttlich",
	["rarity.Cosmic"] = "Kosmisch",
	["rarity.Secret"] = "Geheim",
	["rarity.Godly"] = "Gottgleich",
	["rarity.Eternal"] = "Ewig",
	["rarity.Omega"] = "Omega",
	["path.Stamm"] = "Stamm",
	["path.Stamm.goal"] = "Einstieg",
	["path.Gold"] = "Gold",
	["path.Gold.goal"] = "Das stärkste Pet",
	["path.Kristall"] = "Kristall",
	["path.Kristall.goal"] = "Das schnellste Pet",
	["path.Void"] = "Void",
	["path.Void.goal"] = "Das seltenste Pet",
	["path.Kosmos"] = "Kosmos",
	["path.Kosmos.goal"] = "Allrounder",
	["path.Ascension"] = "Ascension",
	["path.Ascension.goal"] = "Nur über Rebirth",
	["egg.PlatinumEgg.name"] = "Platin-Ei",
	["egg.SunEgg.name"] = "Sonnen-Ei",
	["egg.ZenithEgg.name"] = "Zenit-Ei",
	["egg.PrismEgg.name"] = "Prisma-Ei",
	["egg.AuroraEgg.name"] = "Aurora-Ei",
	["egg.MistEgg.name"] = "Nebel-Ei",
	["egg.VoidEgg.name"] = "Void-Ei",
	["egg.ShadowEgg.name"] = "Schatten-Ei",
	["egg.AbyssEgg.name"] = "Abyss-Ei",
	["egg.CometEgg.name"] = "Kometen-Ei",
	["egg.NovaEgg.name"] = "Nova-Ei",
	["egg.GalaxyEgg.name"] = "Galaxie-Ei",
	["egg.TranscendenceEgg.name"] = "Transzendenz-Ei",
	["egg.EternityEgg.name"] = "Ewigkeits-Ei",
	["egg.OmegaEgg.name"] = "Omega-Ei",
	["baerchi.PhoenixBaerchi.name"] = "Phoenix-Baerchi",
	["baerchi.GlacierBaerchi.name"] = "Gletscher-Baerchi",
	["baerchi.PhantomBaerchi.name"] = "Phantom-Baerchi",
	["baerchi.SeraphBaerchi.name"] = "Seraph-Baerchi",
	["baerchi.NorthernLightBaerchi.name"] = "Polarlicht-Baerchi",
	["baerchi.EclipseBaerchi.name"] = "Eklipse-Baerchi",
	["baerchi.CometBaerchi.name"] = "Kometen-Baerchi",
	["baerchi.NebulaBaerchi.name"] = "Nebula-Baerchi",
	["baerchi.PulsarBaerchi.name"] = "Pulsar-Baerchi",
	["baerchi.ShadeBaerchi.name"] = "Schemen-Baerchi",
	["baerchi.RiddleBaerchi.name"] = "Rätsel-Baerchi",
	["baerchi.TitanBaerchi.name"] = "Titanen-Baerchi",
	["baerchi.GenesisBaerchi.name"] = "Genesis-Baerchi",
	["baerchi.ChronosBaerchi.name"] = "Chronos-Baerchi",
	["baerchi.InfinityBaerchi.name"] = "Unendlichkeits-Baerchi",
	["baerchi.OmegaBaerchi.name"] = "Omega-Baerchi",
	["skill.ChromaBlast.name"] = "Chroma-Blast",
	["skill.TitanMode.name"] = "Titan-Modus",
	["skill.BigBang.name"] = "Big Bang",
	["skill.PhoenixRebirth.name"] = "Phoenix-Glut",
	["skill.GlacierFrost.name"] = "Gletscherhauch",
	["skill.PhantomOmen.name"] = "Phantom-Omen",
	["skill.SeraphGrace.name"] = "Seraphen-Segen",
	["skill.AuroraVeil.name"] = "Polarschleier",
	["skill.EclipseShroud.name"] = "Finsternis",
	["skill.CometImpact.name"] = "Kometeneinschlag",
	["skill.NebulaBurn.name"] = "Nebelbrand",
	["skill.PulsarPulse.name"] = "Pulsstoß",
	["skill.ShadeSlash.name"] = "Schattenhieb",
	["skill.RiddleBeam.name"] = "Rätselstrahl",
	["skill.TitanFist.name"] = "Titanenfaust",
	["skill.GenesisWave.name"] = "Schöpfungswelle",
	["skill.ChronosRift.name"] = "Zeitriss",
	["skill.InfinityBarrage.name"] = "Unendlichkeits-Salve",
	["skill.OmegaStrike.name"] = "Omega-Schlag",

	----------------------------------------------------------------------------
	-- Waben im Event-Pit und Recycler (v15)
	----------------------------------------------------------------------------
	["ui.comb.carry"]  = "Waben {n}/{max}",
	["ui.comb.full"]   = "Stapel voll!  Bring sie zum Recycler",
	["ui.comb.slow"]   = "Schwer beladen: im Pit langsamer",
	["msg.comb_delivered.one"]   = "{n} Wabe an den Recycler abgegeben",
	["msg.comb_delivered.other"] = "{n} Waben an den Recycler abgegeben",
	["ui.recycler.name"]     = "Recycler",
	["ui.recycler.upgrade"]  = "Ausbauen  ({cost})",
	["ui.recycler.maxed"]    = "Höchste Stufe",
	["ui.recycler.cost_g"]   = "{gummies} Gummies",
	["ui.recycler.cost_gg"]  = "{gummies} Gummies + {gold} GoldGummies",
	["msg.recycler_upgraded"] = "Recycler jetzt Level {level}",

	----------------------------------------------------------------------------
	-- v17: Lebendige Events (UFO-Abwurf, Lava-Waben, Wespenkoenigin)
	----------------------------------------------------------------------------
	["egg.UfoJackpotEgg.name"]  = "UFO-Jackpot-Ei",
	["path.Event"]              = "Event",
	["path.Event.goal"]         = "Sonder-Eier aus Events",
	["msg.ufo.patrol"]          = "Das UFO patrouilliert! Alle 30 s wirft es eine Kiste ab — lauf hin und schnapp sie dir",
	["msg.ufo.drop_picked"]     = "Kiste geschnappt: +1 {egg}",
	["msg.ufo.jackpot_drop"]    = "JACKPOT! Das UFO wirft eine goldene Kiste ab!",
	["msg.ufo.jackpot_picked"]  = "{player} hat die goldene UFO-Kiste geschnappt!",
	["msg.hotegg.lava"]         = "Hot Egg: Die Waben werden zu Lava — dreifacher Wert!",
	["msg.boss.announce"]       = "Die Wespenkönigin naht! In {seconds} Sekunden beginnt der Kampf — schick deinen Baerchi zum Event",
	["msg.boss.fight"]          = "Kampf! Weiche den roten Flächen aus — dein Baerchi kämpft",
	["msg.boss.phase2"]         = "Die Königin wird wütend! Königsgelee regnet herab",
	["msg.boss.victory"]        = "Die Wespenkönigin ist besiegt!",
	["msg.boss.fled"]           = "Die Wespenkönigin ist entkommen — es gibt eine Teilbelohnung",
	["msg.boss.too_little"]     = "Zu wenig Schaden für eine Boss-Belohnung (mindestens {min} %)",
	["msg.boss.reward"]         = "Boss-Belohnung: Rang {rank} mit {share} % des Schadens",
	["msg.boss.jackpot"]        = "JACKPOT! {player} bekommt ein UFO-Jackpot-Ei von der Königin!",
	["ui.boss.name"]            = "Wespenkönigin",
	["ui.boss.hp"]              = "Wespenkönigin  {hp} / {max}",
	["ui.boss.hit"]             = "Getroffen! Dein Baerchi setzt kurz aus",
	["msg.event.gummies"]       = "Event-Belohnung: +{n} Gummies",
	["msg.event.combs"]         = "Event-Belohnung: +{n} Waben für den Recycler",
	["msg.event.rarity_up"]     = "RARITY UP: {from} → {to}!",

	-- v15: Tower, Gebaeude-Looks, Bestenliste, Profil, Login-Bonus
	["ui.tower.title"]                 = "Tower",
	["ui.tower.hint"]                  = "Wähle einen Tower. Jeder Lauf startet bei Stage 1 (oder beim Wiedereinstieg). Belohnung und Rekord zählen bis zum Deckel deines Rebirths.",
	["ui.tower.prompt_action"]         = "Kämpfen",
	["ui.tower.prompt_object"]         = "Tower",
	["ui.tower.record_cap"]            = "Rekord {record} / Deckel {cap} (von {stages})",
	["ui.tower.next_milestone"]        = "Nächster Meilenstein: Stage {stage}",
	["ui.tower.selected"]              = "Gewählt",
	["ui.tower.choose"]                = "Wählen",
	["ui.tower.locked"]                = "Öffnet ab Rebirth {rebirths}",
	["ui.tower.locked_short"]          = "Gesperrt",
	["ui.tower.cap_line"]              = "Rebirth {rebirths}: Deckel {tower} · Stage {stage}",
	["ui.tower.cap_reached"]           = "Deckel erreicht (Stage {stage}). Ein Rebirth hebt ihn an!",
	["ui.tower.to_rebirth"]            = "Zum Rebirth",
	["tower.I.name"]                   = "Tower I",
	["tower.II.name"]                  = "Tower II",
	["tower.III.name"]                 = "Tower III",
	["tower.Final.name"]               = "Final-Tower",
	["msg.tower_cleared.one"]          = "{n} Stage geschafft",
	["msg.tower_cleared.other"]        = "{n} Stages geschafft",
	["msg.tower_new_record"]           = "Neuer Rekord: Stage {stage}!",
	["msg.tower_recalled"]             = "Zurückgerufen",
	["msg.tower_blueprint"]            = "+1 Blaupause",
	["msg.tower_milestone"]            = "Tower {tower} · Stage {stage}: {reward}",
	["err.tower_unknown"]              = "Unbekannter Tower",
	["err.tower_locked"]               = "Dieser Tower öffnet ab Rebirth {rebirths}",
	["msg.pit_refund"]                 = "Das PIT-Level ist jetzt der Tower! Erstattung: +{amount} Gummies",
	["ui.building.level_look"]         = "Level {level}/{max} · Look {look}",
	["ui.ability.soon"]                = "bald",
	["ability.AutoHarvest"]            = "Auto-Abnahme",
	["ability.GoldenDrops"]            = "Goldtropfen",
	["ability.RefinerBoost"]           = "Raffinerie-Boost",
	["ability.RoyalJelly"]             = "Gelée Royale",
	["ability.NectarOfAges"]           = "Nektar der Zeitalter",
	["ability.CollectRadius"]          = "Sammelradius",
	["ability.AutoDeposit"]            = "Auto-Abgabe",
	["ui.menu.leaderboard"]            = "Bestenliste",
	["ui.menu.daily"]                  = "Täglich",
	["ui.leaderboard.title"]           = "Bestenliste",
	["ui.leaderboard.loading"]         = "Lädt …",
	["ui.leaderboard.own_rank"]        = "Dein Rang: #{rank} ({value})",
	["ui.leaderboard.own_unranked"]    = "Noch nicht in der Liste ({value})",
	["ui.leaderboard.list.Tower"]      = "Tower",
	["ui.leaderboard.list.Rebirths"]   = "Rebirths",
	["ui.leaderboard.list.Collection"] = "Sammlung",
	["ui.profile.title"]               = "Profil",
	["ui.profile.unavailable"]         = "Profil nicht verfügbar (Spieler nicht auf diesem Server)",
	["ui.profile.equipped"]            = "Ausgerüstet: {baerchi}",
	["ui.profile.tower"]               = "Bester Tower: {tower} · Stage {stage}",
	["ui.profile.rebirths"]            = "Rebirths: {n}",
	["ui.profile.index"]               = "Index: {have}/{total}",
	["ui.profile.top"]                 = "Top-Baerchis:",
	["ui.home.button"]                  = "Heim",
	["ui.card.details"]                 = "Einzelwerte",
	["ui.daily.title"]                 = "Täglicher Bonus",
	["ui.daily.day"]                   = "Tag {day}",
	["ui.daily.egg"]                   = "Ei",
	["ui.daily.best_egg"]              = "Bestes Ei",
	["ui.daily.blueprint_chance"]      = "{pct}% Blaupause",
	["ui.daily.claim"]                 = "Tag {day} abholen",
	["ui.daily.claimed"]               = "Heute abgeholt",
	["ui.daily.reset_in"]              = "Neuer Tag in {time}",
	["ui.daily.tracker_hint"]          = "Täglicher Bonus bereit!",
	["msg.daily_claimed"]              = "Tag {day}: {reward}",
	["err.daily_claimed"]              = "Heute schon abgeholt",

	----------------------------------------------------------------------------
	-- HBB Paket 1: grosse Momente (ein Wort)
	----------------------------------------------------------------------------
	["ui.moment.record"]    = "Rekord!",
	["ui.moment.new"]       = "Neu!",
	["ui.moment.milestone"] = "Meilenstein!",
	["ui.moment.mutation"]  = "Mutation!",
	["ui.moment.rarity"]    = "Aufstieg!",
	["ui.moment.rebirth"]   = "Rebirth!",
	["ui.moment.jackpot"]   = "Jackpot!",
	-- HBB Paket 2: Rebirth-Warnung als ein kurzer Satz (der Rest sind Icons)
	["ui.rebirth.warn_short"] = "Gummies, Gebäude- und Baerchi-Level gehen zurück auf Start.",
	-- HBB Paket 7: Boss-Belohnungsstufe (Client zeigt eine Truhe statt des Texts)
	["msg.boss.tier"] = "Boss-Truhe Stufe {tier}!",
	-- HBB Paket 5: Heim-Knopf
	["err.home_carrying"]    = "Erst die Waben abgeben!",
	["err.home_unavailable"] = "Dein Plot ist gerade nicht erreichbar",
}
