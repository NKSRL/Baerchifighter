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
	["ui.rebirth.loss"]    = "Perdu : tous les Baerchis, tous les niveaux de bâtiments, le niveau du PIT, les couvées en cours et tes Gummies (retour à {start}).\nConservé : GoldGummies, rang, statistiques et Oeufs d'Ascension déjà gagnés.",
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
	["baerchi.CosmicBaerchi.name"]  = "Baerchi Cosmique",

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
}
