--!strict
-- fr.luau
-- ReplicatedStorage/Localization/Strings/fr.luau
--
-- Français. Mêmes clés et mêmes {placeholders} que de.luau — voir l'en-tête
-- de ce fichier pour les conventions. Les termes du jeu ("Baerchi", "Gummies",
-- "GoldGummies", "PIT", "Rebirth") restent identiques dans toutes les langues.
-- Pas de "œ" : la police du jeu ne le garantit pas, on écrit "oe".

return {
	----------------------------------------------------------------------------
	-- Langue
	----------------------------------------------------------------------------
	["ui.language.title"] = "Langue",
	["ui.language.auto"]  = "Automatique (Roblox)",

	----------------------------------------------------------------------------
	-- Temps
	----------------------------------------------------------------------------
	["time.s"]  = "{s} s",
	["time.ms"] = "{m} min {s} s",
	["time.hm"] = "{h} h {m} min",

	----------------------------------------------------------------------------
	-- Barre de menu
	----------------------------------------------------------------------------
	["ui.menu.eggs"]    = "Oeufs",
	["ui.menu.baerchis"] = "Baerchis",
	["ui.menu.fight"]   = "Combat",
	["ui.menu.arena"]   = "Arène",

	----------------------------------------------------------------------------
	-- Rebirth
	----------------------------------------------------------------------------
	["ui.rebirth.title"]   = "Rebirth",
	["ui.rebirth.status"]  = "Rebirth {count}  —  Multiplicateur x{mult:d2}",
	["ui.rebirth.cost"]    = "Coûte {cost} Gummies  (tu as {have})",
	["ui.rebirth.loss"]    = "Perdu : tous les niveaux de bâtiments, le niveau du PIT, les niveaux de tes Baerchis et tes Gummies (retour à {start}).\nConservé : tes Baerchis, tous les oeufs, l'Arbre des Oeufs, GoldGummies, rang et statistiques.",
	["ui.rebirth.reward"]  = "Ensuite : Multiplicateur x{mult:d2}",
	["ui.rebirth.reward_eggs.one"]   = "Ensuite : Multiplicateur x{mult:d2}  —  +{n} Oeuf d'Ascension",
	["ui.rebirth.reward_eggs.other"] = "Ensuite : Multiplicateur x{mult:d2}  —  +{n} Oeufs d'Ascension",
	["ui.rebirth.cancel"]  = "Annuler",
	["ui.rebirth.confirm"] = "Rebirth !",

	----------------------------------------------------------------------------
	-- Messages (toasts)
	----------------------------------------------------------------------------
	["msg.recycled"]       = "Recyclé : +{gummies} Gummies",
	["msg.recycled_gold"]  = "Recyclé : +{gummies} Gummies  et  +{gold} GoldGummies",
	["msg.offline_honey"]  = "Pendant ton absence ({time}) : +{honey} miel",
	["msg.level_up"]       = "Niveau supérieur !  Maintenant niveau {level}",
	["msg.rebirth_done"]   = "Rebirth {count} réussi : Multiplicateur x{mult:d2}",
	["msg.rebirth_done_eggs.one"]   = "Rebirth {count} réussi : Multiplicateur x{mult:d2} et {n} Oeuf d'Ascension",
	["msg.rebirth_done_eggs.other"] = "Rebirth {count} réussi : Multiplicateur x{mult:d2} et {n} Oeufs d'Ascension",

	----------------------------------------------------------------------------
	-- Oeufs dans le monde
	----------------------------------------------------------------------------
	["ui.egg.full"] = "Stock plein — ramasse d'abord !",
	["ui.egg.soon"] = "Prochain oeuf : bientôt !",
	["ui.egg.next"] = "Prochain oeuf : {time}",

	----------------------------------------------------------------------------
	-- Actions refusées
	----------------------------------------------------------------------------
	["err.unknown"]                 = "Action impossible",
	["err.player_not_loaded"]       = "Joueur non chargé",
	["err.baerchi_not_found"]       = "Baerchi introuvable",
	["err.baerchi_data_corrupt"]    = "Données du Baerchi corrompues",
	["err.baerchi_busy"]            = "Le Baerchi est en déplacement — attends un instant",
	["err.not_enough_gummies"]      = "Pas assez de Gummies (tu as {have}, il en faut {need})",
	["err.not_enough_gold_gummies"] = "Pas assez de GoldGummies (tu as {have}, il en faut {need})",
	["err.rebirth_cost"]            = "Le Rebirth coûte {cost} Gummies (tu as {have})",

	["err.building_missing"]        = "Bâtiment indisponible",
	["err.building_unknown"]        = "Bâtiment inconnu",
	["err.max_level"]               = "Niveau maximum atteint",
	["err.max_pit_level"]           = "Niveau de PIT maximum atteint",
	["err.no_pit_cost"]             = "Aucun coût défini pour le niveau de PIT {level}",

	["err.charm_roll_cost"]         = "Un tirage coûte {cost} GoldGummies (tu as {have})",
	["err.charm_no_free_slot"]      = "Aucun emplacement libre — tout est verrouillé ou pas encore débloqué",
	["err.charm_roll_failed"]       = "Le tirage n'a pas pu être payé",
	["err.charm_slot_empty"]        = "Cet emplacement ne contient pas encore de charme",

	["err.feed_building_empty"]     = "Ce bâtiment n'a pas de miel pour le moment",
	["err.feed_no_honey"]           = "Pas de miel — les bâtiments produisent encore",

	["err.promo_maxed"]             = "Déjà promu au maximum",
	["err.promo_need_material"]     = "Il te faut {cost} x {name} comme matériel (tu en as {have})",

	["err.event_already_away"]      = "Ton Baerchi est déjà en route",
	["err.event_no_equipped"]       = "Aucun Baerchi équipé",
	["err.event_not_on_plot"]       = "Le Baerchi n'est pas sur la parcelle en ce moment",
	["err.event_not_at_event"]      = "Ton Baerchi n'est pas à l'événement",

	["err.combat_busy"]             = "Le Baerchi combat encore dans le PIT",
	["err.combat_exhausted"]        = "Le Baerchi est épuisé — donne-lui d'abord du miel",
	["err.recycle_equipped"] = "Équipe d'abord un autre Baerchi, ensuite tu pourras recycler celui-ci",
	["err.honey_in_pit"] = "Le Baerchi combat actuellement dans le PIT",
	["err.event_ufo"] = "Ton Baerchi est en train d'être enlevé par l'OVNI",
	["err.combat_no_last_run"] = "Aucune dernière tentative sur ce niveau de PIT — recommence depuis le début",
	["err.fuse_equipped_away"] = "Le Baerchi équipé est en déplacement — attends un instant",
	["err.egg_none_in_stock"] = "Aucun {egg} en stock",

	["err.fuse_self"]               = "Un Baerchi ne peut pas fusionner avec lui-même",
	["err.fuse_rarity_mismatch"]    = "Les deux Baerchis doivent avoir la même rareté",
	["err.fuse_mythic"]             = "Mythique ne peut plus être fusionné",
	["err.fuse_no_higher"]          = "Aucune rareté supérieure",
	["err.fuse_none_defined"]       = "Aucun Baerchi de rareté {rarity} défini",
	["err.fuse_result_failed"]      = "Le résultat de la fusion n'a pas pu être créé",

	["err.egg_none_lying"]          = "Il n'y a aucun oeuf par terre pour le moment",
	["err.egg_slots_full"]          = "Les {slots} emplacements de couvaison sont occupés",
	["err.egg_gone"]                = "Cet oeuf n'existe plus",
	["err.egg_wait"]                = "Encore {seconds:dur} avant que l'oeuf soit prêt",
	["err.egg_type_gone"]           = "Ce type d'oeuf n'existe plus — tu reçois à la place : {egg}",
	["err.egg_internal"]            = "Erreur interne pendant l'éclosion",
	["err.egg_unknown_type"]        = "Type d'oeuf inconnu",
	["err.egg_not_buyable"]         = "Pas de {egg} en stock (impossible à acheter)",

	----------------------------------------------------------------------------
	-- Noms : raretés
	----------------------------------------------------------------------------
	["rarity.Common"]    = "Commun",
	["rarity.Uncommon"]  = "Peu commun",
	["rarity.Rare"]      = "Rare",
	["rarity.Epic"]      = "Épique",
	["rarity.Legendary"] = "Légendaire",
	["rarity.Mythic"]    = "Mythique",

	----------------------------------------------------------------------------
	-- Noms : Baerchis
	----------------------------------------------------------------------------
	["baerchi.RedBaerchi.name"]     = "Baerchi Rouge",
	["baerchi.GreenBaerchi.name"]   = "Baerchi Vert",
	["baerchi.YellowBaerchi.name"]  = "Baerchi Jaune",
	["baerchi.BlueBaerchi.name"]    = "Baerchi Bleu",
	["baerchi.OrangeBaerchi.name"]  = "Baerchi Orange",
	["baerchi.SugarBaerchi.name"]   = "Baerchi Sucré",
	["baerchi.CrystalBaerchi.name"] = "Baerchi de Cristal",
	["baerchi.GoldenGrizzly.name"]  = "Grizzly Doré",
	["baerchi.VoidBaerchi.name"]    = "Baerchi du Vide",
	["baerchi.RainbowBaerchi.name"] = "Baerchi Arc-en-ciel",
	["baerchi.AncientBaerchi.name"] = "Baerchi Ancestral",
	["baerchi.CosmicBaerchi.name"]  = "Baerchi Étoilé",

	----------------------------------------------------------------------------
	-- Noms : mutations
	----------------------------------------------------------------------------
	["mutation.Gold.name"]      = "Or",
	["mutation.Diamond.name"]   = "Diamant",
	["mutation.Bloodrot.name"]  = "Bloodrot",
	["mutation.Celestial.name"] = "Céleste",
	["mutation.Candy.name"]     = "Bonbon",
	["mutation.Lava.name"]      = "Lave",
	["mutation.Galaxy.name"]    = "Galaxie",
	["mutation.Rainbow.name"]   = "Arc-en-ciel",

	----------------------------------------------------------------------------
	-- Noms : oeufs
	----------------------------------------------------------------------------
	["egg.BasicEgg.name"]     = "Oeuf de base",
	["egg.SugarEgg.name"]     = "Oeuf de sucre",
	["egg.GoldenEgg.name"]    = "Oeuf doré",
	["egg.CrystalEgg.name"]   = "Oeuf de cristal",
	["egg.AscensionEgg.name"] = "Oeuf d'Ascension",

	----------------------------------------------------------------------------
	-- Noms : bâtiments
	----------------------------------------------------------------------------
	["building.Beehive.name"]      = "Ruche",
	["building.HoneyPot.name"]     = "Pot de miel",
	["building.HoneyPress.name"]   = "Presse à miel",
	["building.Beehive.short"]     = "Ruche",
	["building.HoneyPot.short"]    = "Pot",
	["building.HoneyPress.short"]  = "Presse",

	----------------------------------------------------------------------------
	-- Noms : rangs
	----------------------------------------------------------------------------
	["rank.1"] = "Petit Gummy",
	["rank.2"] = "Bagarreur Sucré",
	["rank.3"] = "Combattant de Cristal",
	["rank.4"] = "Champion Doré",
	["rank.5"] = "Légende Cosmique",

	----------------------------------------------------------------------------
	-- Noms : compétences
	----------------------------------------------------------------------------
	["skill.BasicPunch.name"]  = "Coup de base",
	["skill.SugarRush.name"]   = "Ruée sucrée",
	["skill.GummyShield.name"] = "Bouclier gummy",
	["skill.IceSlam.name"]     = "Choc glacial",
	["skill.FireBite.name"]    = "Morsure de feu",
	["skill.SugarStorm.name"]  = "Tempête de sucre",
	["skill.ShardBlast.name"]  = "Rafale d'éclats",
	["skill.GoldRush.name"]    = "Ruée vers l'or",
	["skill.BlackHole.name"]   = "Trou noir",

	----------------------------------------------------------------------------
	-- Index, Quests (v13)
	----------------------------------------------------------------------------
	["ui.inventory.tab_pets"] = "Mes Baerchis",
	["ui.inventory.tab_index"] = "Index",
	["ui.index.unknown"] = "???",
	["ui.index.drops_from"] = "Obtenu dans :",
	["ui.index.you_have"] = "Tu en as {n} en stock",
	["ui.index.no_source"] = "Aucun oeuf ne le donne pour l'instant.",
	["ui.index.progress"] = "Découverts {found}/{total}",
	["ui.quest.header"] = "Quête {done}/{total}",
	["ui.quest.chain_done"] = "Toutes les quêtes de départ sont finies !",
	["ui.quest.claim"] = "Récupérer la récompense",
	["ui.quest.daily_link"] = "Quêtes du jour {done}/{total}  >",
	["ui.quest.panel_title"] = "Quêtes",
	["ui.quest.section_chain"] = "Quêtes de départ",
	["ui.quest.section_daily"] = "Quêtes du jour",
	["ui.quest.resets_in"] = "Nouvelles quêtes du jour dans {time}",
	["ui.quest.claimed"] = "Terminé",
	["ui.quest.claim_short"] = "Récupérer",
	["ui.quest.reward_gummies"] = "+{n} Gummies",
	["ui.quest.reward_with_egg"] = "+{n} Gummies et un {egg}",
	["ui.quest.toast"] = "Quête terminée : {text}",
	["err.quest_unknown"] = "Quête inconnue",
	["err.quest_already_claimed"] = "Déjà récupérée",
	["err.quest_not_current"] = "Ce n'est pas la quête en cours",
	["err.quest_not_done"] = "Quête pas encore terminée",
	["quest.c_hatch1.title"] = "Ouvre ton premier oeuf",
	["quest.c_hatch1.hint"] = "Touche OEUFS à droite et ouvre un oeuf de ton stock.",
	["quest.c_pets3.title"] = "Possède 3 Baerchis",
	["quest.c_pets3.hint"] = "Continue d'ouvrir des oeufs - chaque oeuf donne un Baerchi.",
	["quest.c_fight1.title"] = "Gagne ton premier combat",
	["quest.c_fight1.hint"] = "Appuie sur Combat en bas pour envoyer ton Baerchi dans la PIT.",
	["quest.c_fight5.title"] = "Gagne 5 combats",
	["quest.c_fight5.hint"] = "Continue de te battre dans la PIT - chaque étape réussie compte.",
	["quest.c_upgrade.title"] = "Améliore un bâtiment",
	["quest.c_upgrade.hint"] = "Va près d'un bâtiment de ton terrain et appuie sur E pour l'améliorer.",
	["quest.c_hatch5.title"] = "Ouvre 5 oeufs",
	["quest.c_hatch5.hint"] = "Des oeufs traînent aussi sur ton terrain - marche dessus pour les ramasser.",
	["quest.c_discover5.title"] = "Découvre 5 Baerchis",
	["quest.c_discover5.hint"] = "Ouvre BAERCHIS > Index pour voir quel oeuf donne quoi.",
	["quest.c_fuse1.title"] = "Fusionne deux Baerchis",
	["quest.c_fuse1.hint"] = "Dans BAERCHIS, active la Fusion et choisis-en deux de même rareté.",
	["quest.c_pit2.title"] = "Améliore l'arène",
	["quest.c_pit2.hint"] = "Va à la plateforme de combat de ton terrain et appuie sur E.",
	["quest.c_discover8.title"] = "Découvre 8 Baerchis",
	["quest.c_discover8.hint"] = "Touche une silhouette noire dans l'Index pour voir quel oeuf il te faut.",
	["quest.c_fight25.title"] = "Gagne 25 combats",
	["quest.c_fight25.hint"] = "Des Baerchis plus forts vont plus loin. Fusionne, promeus, recommence.",
	["quest.c_discover10.title"] = "Découvre 10 Baerchis",
	["quest.c_discover10.hint"] = "Les oeufs supérieurs cachent les plus rares - vois les chances dans l'Index.",
	["quest.d_hatch3.title"] = "Ouvre 3 oeufs aujourd'hui",
	["quest.d_hatch3.hint"] = "Les oeufs du stock et ceux du terrain comptent.",
	["quest.d_fight8.title"] = "Gagne 8 combats aujourd'hui",
	["quest.d_fight8.hint"] = "Utilise le bouton Combat en bas.",
	["quest.d_earn.title"] = "Gagne 1 500 Gummies aujourd'hui",
	["quest.d_earn.hint"] = "Les combats et tes bâtiments rapportent des Gummies.",

	----------------------------------------------------------------------------
	-- v14: Mega Egg Tree (Ei-Baum, neue Eier, neue Baerchis, Faehigkeiten)
	----------------------------------------------------------------------------
	["ui.menu.tree"] = "Arbre",
	["ui.tree.title"] = "Arbre des Oeufs",
	["ui.tree.title_bp"] = "Arbre des Oeufs  —  Plans : {n}",
	["ui.tree.cond_hatch"] = "Ouvrir {egg} : {have}/{need}",
	["ui.tree.cond_any"] = "Oeufs finaux (6× chacun) : {have}/{need}",
	["ui.tree.cond_index"] = "{rarity} dans l'Index : {have}/{need}",
	["ui.tree.cond_rebirth"] = "Rebirth : {have}/{need}",
	["ui.tree.cond_blueprint"] = "Plan utilisé",
	["ui.tree.path_line"] = "Voie {path} — {goal}\nRareté moy. {avg}",
	["ui.tree.unlocked"] = "Débloqué",
	["ui.tree.ready"] = "Prêt — se débloque",
	["ui.tree.locked"] = "Verrouillé",
	["ui.tree.needs"] = "Encore nécessaire",
	["ui.tree.in_stock"] = "En stock : {n}",
	["ui.tree.open"] = "Ouvrir",
	["ui.tree.press"] = "Presser : {n} → 1 {egg}",
	["ui.tree.use_blueprint"] = "Utiliser un plan ({n} restants)",
	["ui.tree.drops"] = "Ce qui éclot",
	["ui.tree.lock_short"] = "fermé",
	["ui.tree.jump_hint"] = "Oeuf-saut d'un événement : il s'ouvre, mais ne débloque pas le noeud.",
	["msg.tree_unlocked"] = "Arbre des Oeufs : {egg} débloqué !",
	["msg.pressed"] = "Pressé : {n}× {from} → 1 {to}",
	["msg.rebirth_done_list"] = "Rebirth {count} réussi : multiplicateur x{mult:d2} et {eggs}",
	["ui.rebirth.reward_list"] = "Ensuite : multiplicateur x{mult:d2}  —  {eggs}",
	["err.press_blocked"] = "Les oeufs de la voie Ascension ne se pressent pas",
	["err.press_no_next"] = "Cet oeuf n'a pas de niveau suivant",
	["err.press_target_locked"] = "Débloque d'abord {egg} dans l'Arbre des Oeufs",
	["err.press_not_enough"] = "Il te faut {n}× {egg} (tu en as {have})",
	["err.blueprint_not_here"] = "Aucun plan ne convient ici pour l'instant",
	["rarity.Divine"] = "Divin",
	["rarity.Cosmic"] = "Cosmique",
	["rarity.Secret"] = "Secret",
	["rarity.Godly"] = "Céleste",
	["rarity.Eternal"] = "Éternel",
	["rarity.Omega"] = "Oméga",
	["path.Stamm"] = "Tronc",
	["path.Stamm.goal"] = "Départ",
	["path.Gold"] = "Or",
	["path.Gold.goal"] = "Le pet le plus fort",
	["path.Kristall"] = "Cristal",
	["path.Kristall.goal"] = "Le pet le plus rapide",
	["path.Void"] = "Néant",
	["path.Void.goal"] = "Le pet le plus rare",
	["path.Kosmos"] = "Cosmos",
	["path.Kosmos.goal"] = "Polyvalent",
	["path.Ascension"] = "Ascension",
	["path.Ascension.goal"] = "Seulement par Rebirth",
	["egg.PlatinumEgg.name"] = "Oeuf de Platine",
	["egg.SunEgg.name"] = "Oeuf Solaire",
	["egg.ZenithEgg.name"] = "Oeuf du Zénith",
	["egg.PrismEgg.name"] = "Oeuf Prisme",
	["egg.AuroraEgg.name"] = "Oeuf Aurore",
	["egg.MistEgg.name"] = "Oeuf de Brume",
	["egg.VoidEgg.name"] = "Oeuf du Néant",
	["egg.ShadowEgg.name"] = "Oeuf d'Ombre",
	["egg.AbyssEgg.name"] = "Oeuf des Abysses",
	["egg.CometEgg.name"] = "Oeuf Comète",
	["egg.NovaEgg.name"] = "Oeuf Nova",
	["egg.GalaxyEgg.name"] = "Oeuf Galaxie",
	["egg.TranscendenceEgg.name"] = "Oeuf de Transcendance",
	["egg.EternityEgg.name"] = "Oeuf d'Éternité",
	["egg.OmegaEgg.name"] = "Oeuf Oméga",
	["baerchi.PhoenixBaerchi.name"] = "Baerchi Phénix",
	["baerchi.GlacierBaerchi.name"] = "Baerchi Glacier",
	["baerchi.PhantomBaerchi.name"] = "Baerchi Fantôme",
	["baerchi.SeraphBaerchi.name"] = "Baerchi Séraphin",
	["baerchi.NorthernLightBaerchi.name"] = "Baerchi Aurore Boréale",
	["baerchi.EclipseBaerchi.name"] = "Baerchi Éclipse",
	["baerchi.CometBaerchi.name"] = "Baerchi Comète",
	["baerchi.NebulaBaerchi.name"] = "Baerchi Nébuleuse",
	["baerchi.PulsarBaerchi.name"] = "Baerchi Pulsar",
	["baerchi.ShadeBaerchi.name"] = "Baerchi Spectre",
	["baerchi.RiddleBaerchi.name"] = "Baerchi Énigme",
	["baerchi.TitanBaerchi.name"] = "Baerchi Titan",
	["baerchi.GenesisBaerchi.name"] = "Baerchi Genèse",
	["baerchi.ChronosBaerchi.name"] = "Baerchi Chronos",
	["baerchi.InfinityBaerchi.name"] = "Baerchi Infini",
	["baerchi.OmegaBaerchi.name"] = "Baerchi Oméga",
	["skill.ChromaBlast.name"] = "Chroma-Blast",
	["skill.TitanMode.name"] = "Mode Titan",
	["skill.BigBang.name"] = "Big Bang",
	["skill.PhoenixRebirth.name"] = "Braise du Phénix",
	["skill.GlacierFrost.name"] = "Souffle Glacial",
	["skill.PhantomOmen.name"] = "Présage Fantôme",
	["skill.SeraphGrace.name"] = "Bénédiction Séraphique",
	["skill.AuroraVeil.name"] = "Voile d'Aurore",
	["skill.EclipseShroud.name"] = "Éclipse",
	["skill.CometImpact.name"] = "Impact de Comète",
	["skill.NebulaBurn.name"] = "Brûlure Nébuleuse",
	["skill.PulsarPulse.name"] = "Pulsation",
	["skill.ShadeSlash.name"] = "Taillade d'Ombre",
	["skill.RiddleBeam.name"] = "Rayon Énigme",
	["skill.TitanFist.name"] = "Poing de Titan",
	["skill.GenesisWave.name"] = "Vague de Genèse",
	["skill.ChronosRift.name"] = "Faille Temporelle",
	["skill.InfinityBarrage.name"] = "Salve Infinie",
	["skill.OmegaStrike.name"] = "Frappe Oméga",
}
