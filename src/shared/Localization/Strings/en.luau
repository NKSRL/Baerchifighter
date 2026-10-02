--!strict
-- en.luau
-- ReplicatedStorage/Localization/Strings/en.luau
--
-- English. Same keys and the same {placeholders} as de.luau — see the header
-- there for the conventions. Game terms ("Baerchi", "Gummies", "GoldGummies",
-- "PIT", "Rebirth") stay as they are in every language.

return {
	----------------------------------------------------------------------------
	-- Language
	----------------------------------------------------------------------------
	["ui.language.title"] = "Language",
	["ui.language.auto"]  = "Automatic (Roblox)",

	----------------------------------------------------------------------------
	-- Time
	----------------------------------------------------------------------------
	["time.s"]  = "{s}s",
	["time.ms"] = "{m}m {s}s",
	["time.hm"] = "{h}h {m}m",

	----------------------------------------------------------------------------
	-- Menu bar
	----------------------------------------------------------------------------
	["ui.menu.eggs"]    = "Eggs",
	["ui.menu.baerchis"] = "Baerchis",
	["ui.menu.fight"]   = "Fight",
	["ui.menu.arena"]   = "Arena",

	----------------------------------------------------------------------------
	-- Rebirth
	----------------------------------------------------------------------------
	["ui.rebirth.title"]   = "Rebirth",
	["ui.rebirth.status"]  = "Rebirth {count}  —  Multiplier x{mult:d2}",
	["ui.rebirth.cost"]    = "Costs {cost} Gummies  (you have {have})",
	["ui.rebirth.loss"]    = "Lost: all Baerchis, all building levels, the PIT level, running hatches and your Gummies (reset to {start}).\nKept: GoldGummies, rank, stats and Ascension Eggs you already earned.",
	["ui.rebirth.reward"]  = "After: Multiplier x{mult:d2}",
	["ui.rebirth.reward_eggs.one"]   = "After: Multiplier x{mult:d2}  —  +{n} Ascension Egg",
	["ui.rebirth.reward_eggs.other"] = "After: Multiplier x{mult:d2}  —  +{n} Ascension Eggs",
	["ui.rebirth.cancel"]  = "Cancel",
	["ui.rebirth.confirm"] = "Rebirth!",

	----------------------------------------------------------------------------
	-- Messages (toasts)
	----------------------------------------------------------------------------
	["msg.recycled"]       = "Recycled: +{gummies} Gummies",
	["msg.recycled_gold"]  = "Recycled: +{gummies} Gummies  and  +{gold} GoldGummies",
	["msg.offline_honey"]  = "While you were away ({time}): +{honey} honey",
	["msg.level_up"]       = "Level Up!  Now level {level}",
	["msg.rebirth_done"]   = "Rebirth {count} done: Multiplier x{mult:d2}",
	["msg.rebirth_done_eggs.one"]   = "Rebirth {count} done: Multiplier x{mult:d2} and {n} Ascension Egg",
	["msg.rebirth_done_eggs.other"] = "Rebirth {count} done: Multiplier x{mult:d2} and {n} Ascension Eggs",

	----------------------------------------------------------------------------
	-- Eggs in the world
	----------------------------------------------------------------------------
	["ui.egg.full"] = "Storage full — collect first!",
	["ui.egg.soon"] = "Next egg: any moment!",
	["ui.egg.next"] = "Next egg: {time}",

	----------------------------------------------------------------------------
	-- Rejected actions
	----------------------------------------------------------------------------
	["err.unknown"]                 = "Action not possible",
	["err.player_not_loaded"]       = "Player not loaded",
	["err.baerchi_not_found"]       = "Baerchi not found",
	["err.baerchi_data_corrupt"]    = "Baerchi data is corrupt",
	["err.baerchi_busy"]            = "The Baerchi is on the move — wait a moment",
	["err.not_enough_gummies"]      = "Not enough Gummies (you have {have}, you need {need})",
	["err.not_enough_gold_gummies"] = "Not enough GoldGummies (you have {have}, you need {need})",
	["err.rebirth_cost"]            = "Rebirth costs {cost} Gummies (you have {have})",

	["err.building_missing"]        = "Building not available",
	["err.building_unknown"]        = "Unknown building",
	["err.max_level"]               = "Maximum level reached",
	["err.max_pit_level"]           = "Maximum PIT level reached",
	["err.no_pit_cost"]             = "No cost defined for PIT level {level}",

	["err.charm_roll_cost"]         = "One roll costs {cost} GoldGummies (you have {have})",
	["err.charm_no_free_slot"]      = "No free slot to roll — everything is locked or not unlocked yet",
	["err.charm_roll_failed"]       = "The roll could not be paid for",
	["err.charm_slot_empty"]        = "There is no charm in this slot yet",

	["err.feed_building_empty"]     = "This building has no honey right now",
	["err.feed_no_honey"]           = "No honey — the buildings are still producing",

	["err.promo_maxed"]             = "Already fully promoted",
	["err.promo_need_material"]     = "You need {cost} x {name} as material (you have {have})",

	["err.event_already_away"]      = "Your Baerchi is already on its way",
	["err.event_no_equipped"]       = "No Baerchi equipped",
	["err.event_not_on_plot"]       = "The Baerchi is not on the plot right now",
	["err.event_not_at_event"]      = "Your Baerchi is not at the event",

	["err.combat_busy"]             = "The Baerchi is still fighting in the PIT",
	["err.combat_exhausted"]        = "The Baerchi is exhausted — feed it honey first",

	["err.fuse_self"]               = "A Baerchi cannot be fused with itself",
	["err.fuse_rarity_mismatch"]    = "Both Baerchis must have the same rarity",
	["err.fuse_mythic"]             = "Mythic cannot be fused any further",
	["err.fuse_no_higher"]          = "There is no higher rarity",
	["err.fuse_none_defined"]       = "No Baerchis of rarity {rarity} defined",
	["err.fuse_result_failed"]      = "The fusion result could not be created",

	["err.egg_none_lying"]          = "There are no eggs lying around right now",
	["err.egg_slots_full"]          = "All {slots} hatching slots are in use",
	["err.egg_gone"]                = "This egg no longer exists",
	["err.egg_wait"]                = "{seconds:dur} until the egg is ready",
	["err.egg_type_gone"]           = "This egg type no longer exists — you get this instead: {egg}",
	["err.egg_internal"]            = "Internal error while hatching",
	["err.egg_unknown_type"]        = "Unknown egg type",
	["err.egg_not_buyable"]         = "No {egg} in storage (cannot be bought)",

	----------------------------------------------------------------------------
	-- Names: rarities
	----------------------------------------------------------------------------
	["rarity.Common"]    = "Common",
	["rarity.Uncommon"]  = "Uncommon",
	["rarity.Rare"]      = "Rare",
	["rarity.Epic"]      = "Epic",
	["rarity.Legendary"] = "Legendary",
	["rarity.Mythic"]    = "Mythic",

	----------------------------------------------------------------------------
	-- Names: Baerchis
	----------------------------------------------------------------------------
	["baerchi.RedBaerchi.name"]     = "Red Baerchi",
	["baerchi.GreenBaerchi.name"]   = "Green Baerchi",
	["baerchi.YellowBaerchi.name"]  = "Yellow Baerchi",
	["baerchi.BlueBaerchi.name"]    = "Blue Baerchi",
	["baerchi.OrangeBaerchi.name"]  = "Orange Baerchi",
	["baerchi.SugarBaerchi.name"]   = "Sugar Baerchi",
	["baerchi.CrystalBaerchi.name"] = "Crystal Baerchi",
	["baerchi.GoldenGrizzly.name"]  = "Golden Grizzly",
	["baerchi.VoidBaerchi.name"]    = "Void Baerchi",
	["baerchi.RainbowBaerchi.name"] = "Rainbow Baerchi",
	["baerchi.AncientBaerchi.name"] = "Ancient Baerchi",
	["baerchi.CosmicBaerchi.name"]  = "Cosmic Baerchi",

	----------------------------------------------------------------------------
	-- Names: mutations
	----------------------------------------------------------------------------
	["mutation.Gold.name"]      = "Gold",
	["mutation.Diamond.name"]   = "Diamond",
	["mutation.Bloodrot.name"]  = "Bloodrot",
	["mutation.Celestial.name"] = "Celestial",
	["mutation.Candy.name"]     = "Candy",
	["mutation.Lava.name"]      = "Lava",
	["mutation.Galaxy.name"]    = "Galaxy",
	["mutation.Rainbow.name"]   = "Rainbow",

	----------------------------------------------------------------------------
	-- Names: eggs
	----------------------------------------------------------------------------
	["egg.BasicEgg.name"]     = "Basic Egg",
	["egg.SugarEgg.name"]     = "Sugar Egg",
	["egg.GoldenEgg.name"]    = "Golden Egg",
	["egg.CrystalEgg.name"]   = "Crystal Egg",
	["egg.AscensionEgg.name"] = "Ascension Egg",

	----------------------------------------------------------------------------
	-- Names: buildings
	----------------------------------------------------------------------------
	["building.Beehive.name"]      = "Beehive",
	["building.HoneyPot.name"]     = "Honey Pot",
	["building.HoneyPress.name"]   = "Honey Press",
	["building.Beehive.short"]     = "Hive",
	["building.HoneyPot.short"]    = "Pot",
	["building.HoneyPress.short"]  = "Press",

	----------------------------------------------------------------------------
	-- Names: ranks
	----------------------------------------------------------------------------
	["rank.1"] = "Gummy Hatchling",
	["rank.2"] = "Sugar Brawler",
	["rank.3"] = "Crystal Fighter",
	["rank.4"] = "Golden Champion",
	["rank.5"] = "Cosmic Legend",

	----------------------------------------------------------------------------
	-- Names: skills
	----------------------------------------------------------------------------
	["skill.BasicPunch.name"]  = "Basic Punch",
	["skill.SugarRush.name"]   = "Sugar Rush",
	["skill.GummyShield.name"] = "Gummy Shield",
	["skill.IceSlam.name"]     = "Ice Slam",
	["skill.FireBite.name"]    = "Fire Bite",
	["skill.SugarStorm.name"]  = "Sugar Storm",
	["skill.ShardBlast.name"]  = "Shard Blast",
	["skill.GoldRush.name"]    = "Gold Rush",
	["skill.BlackHole.name"]   = "Black Hole",
}
