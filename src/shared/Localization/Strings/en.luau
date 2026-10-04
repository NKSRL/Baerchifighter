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
	["ui.rebirth.loss"]    = "Lost: all building levels, the PIT level, your Baerchis' levels and your Gummies (reset to {start}).\nKept: your Baerchis, all eggs, the Egg Tree, GoldGummies, rank and stats.",
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
	["err.recycle_equipped"] = "Equip a different Baerchi first, then you can recycle this one",
	["err.honey_in_pit"] = "The Baerchi is fighting in the PIT right now",
	["err.event_ufo"] = "Your Baerchi is being abducted by the UFO right now",
	["err.combat_no_last_run"] = "No previous run on this PIT level — start from the beginning",
	["err.fuse_equipped_away"] = "The equipped Baerchi is on the move — wait a moment",
	["err.egg_none_in_stock"] = "No {egg} in storage",

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
	["baerchi.CosmicBaerchi.name"]  = "Star Baerchi",

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

	----------------------------------------------------------------------------
	-- Index, Quests (v13)
	----------------------------------------------------------------------------
	["ui.inventory.tab_pets"] = "My Baerchis",
	["ui.inventory.tab_index"] = "Index",
	["ui.index.unknown"] = "???",
	["ui.index.drops_from"] = "Drops from:",
	["ui.index.you_have"] = "You have {n} in stock",
	["ui.index.no_source"] = "No egg drops this one yet.",
	["ui.index.progress"] = "Discovered {found}/{total}",
	["ui.quest.header"] = "Quest {done}/{total}",
	["ui.quest.chain_done"] = "All starter quests done!",
	["ui.quest.claim"] = "Claim reward",
	["ui.quest.daily_link"] = "Daily quests {done}/{total}  >",
	["ui.quest.panel_title"] = "Quests",
	["ui.quest.section_chain"] = "Starter quests",
	["ui.quest.section_daily"] = "Daily quests",
	["ui.quest.resets_in"] = "New daily quests in {time}",
	["ui.quest.claimed"] = "Done",
	["ui.quest.claim_short"] = "Claim",
	["ui.quest.reward_gummies"] = "+{n} Gummies",
	["ui.quest.reward_with_egg"] = "+{n} Gummies and a {egg}",
	["ui.quest.toast"] = "Quest complete: {text}",
	["err.quest_unknown"] = "Unknown quest",
	["err.quest_already_claimed"] = "Already claimed",
	["err.quest_not_current"] = "That quest is not the current one",
	["err.quest_not_done"] = "Quest not finished yet",
	["quest.c_hatch1.title"] = "Open your first egg",
	["quest.c_hatch1.hint"] = "Tap EGGS on the right and open an egg from your stock.",
	["quest.c_pets3.title"] = "Own 3 Baerchis",
	["quest.c_pets3.hint"] = "Keep opening eggs - every egg gives you a Baerchi.",
	["quest.c_fight1.title"] = "Win your first fight",
	["quest.c_fight1.hint"] = "Press the Fight button at the bottom to send your Baerchi into the PIT.",
	["quest.c_fight5.title"] = "Win 5 fights",
	["quest.c_fight5.hint"] = "Keep fighting in the PIT - every cleared stage counts.",
	["quest.c_upgrade.title"] = "Upgrade a building",
	["quest.c_upgrade.hint"] = "Walk to a building on your plot and press E to upgrade it.",
	["quest.c_hatch5.title"] = "Open 5 eggs",
	["quest.c_hatch5.hint"] = "Eggs also lie around your plot - walk over them to collect them.",
	["quest.c_discover5.title"] = "Discover 5 Baerchis",
	["quest.c_discover5.hint"] = "Open BAERCHIS > Index to see which egg drops what.",
	["quest.c_fuse1.title"] = "Fuse two Baerchis",
	["quest.c_fuse1.hint"] = "In BAERCHIS turn Fusion on and pick two of the same rarity.",
	["quest.c_pit2.title"] = "Upgrade the arena",
	["quest.c_pit2.hint"] = "Walk to the fighting platform on your plot and press E.",
	["quest.c_discover8.title"] = "Discover 8 Baerchis",
	["quest.c_discover8.hint"] = "Tap a black silhouette in the Index to see which egg you need.",
	["quest.c_fight25.title"] = "Win 25 fights",
	["quest.c_fight25.hint"] = "Stronger Baerchis get further. Fuse, promote, repeat.",
	["quest.c_discover10.title"] = "Discover 10 Baerchis",
	["quest.c_discover10.hint"] = "Higher eggs hold the rare ones - check the odds in the Index.",
	["quest.d_hatch3.title"] = "Open 3 eggs today",
	["quest.d_hatch3.hint"] = "Eggs from your stock or collected on your plot both count.",
	["quest.d_fight8.title"] = "Win 8 fights today",
	["quest.d_fight8.hint"] = "Use the Fight button at the bottom.",
	["quest.d_earn.title"] = "Earn 1,500 Gummies today",
	["quest.d_earn.hint"] = "Fights and your buildings pay out Gummies.",

	----------------------------------------------------------------------------
	-- v14: Mega Egg Tree (Ei-Baum, neue Eier, neue Baerchis, Faehigkeiten)
	----------------------------------------------------------------------------
	["ui.menu.tree"] = "Egg Tree",
	["ui.tree.title"] = "Egg Tree",
	["ui.tree.title_bp"] = "Egg Tree  —  Blueprints: {n}",
	["ui.tree.cond_hatch"] = "Open {egg}: {have}/{need}",
	["ui.tree.cond_any"] = "End eggs (6× each): {have}/{need}",
	["ui.tree.cond_index"] = "{rarity} in Index: {have}/{need}",
	["ui.tree.cond_rebirth"] = "Rebirth: {have}/{need}",
	["ui.tree.cond_blueprint"] = "Blueprint used",
	["ui.tree.path_line"] = "Path {path} — {goal}\nAvg. rarity {avg}",
	["ui.tree.unlocked"] = "Unlocked",
	["ui.tree.ready"] = "Ready — unlocking now",
	["ui.tree.locked"] = "Locked",
	["ui.tree.needs"] = "Still needed",
	["ui.tree.in_stock"] = "In storage: {n}",
	["ui.tree.open"] = "Open",
	["ui.tree.press"] = "Press: {n} → 1 {egg}",
	["ui.tree.use_blueprint"] = "Use blueprint ({n} left)",
	["ui.tree.drops"] = "What hatches",
	["ui.tree.lock_short"] = "lock",
	["ui.tree.jump_hint"] = "Jump egg from an event: you can open it, but it does not unlock the node.",
	["msg.tree_unlocked"] = "Egg Tree: {egg} unlocked!",
	["msg.pressed"] = "Pressed: {n}× {from} → 1 {to}",
	["msg.rebirth_done_list"] = "Rebirth {count} done: multiplier x{mult:d2} and {eggs}",
	["ui.rebirth.reward_list"] = "Afterwards: multiplier x{mult:d2}  —  {eggs}",
	["err.press_blocked"] = "Eggs from the Ascension path can't be pressed",
	["err.press_no_next"] = "This egg has no next tier",
	["err.press_target_locked"] = "Unlock {egg} in the Egg Tree first",
	["err.press_not_enough"] = "You need {n}× {egg} (you have {have})",
	["err.blueprint_not_here"] = "A blueprint doesn't fit here right now",
	["rarity.Divine"] = "Divine",
	["rarity.Cosmic"] = "Cosmic",
	["rarity.Secret"] = "Secret",
	["rarity.Godly"] = "Godly",
	["rarity.Eternal"] = "Eternal",
	["rarity.Omega"] = "Omega",
	["path.Stamm"] = "Trunk",
	["path.Stamm.goal"] = "Start",
	["path.Gold"] = "Gold",
	["path.Gold.goal"] = "The strongest pet",
	["path.Kristall"] = "Crystal",
	["path.Kristall.goal"] = "The fastest pet",
	["path.Void"] = "Void",
	["path.Void.goal"] = "The rarest pet",
	["path.Kosmos"] = "Cosmos",
	["path.Kosmos.goal"] = "All-rounder",
	["path.Ascension"] = "Ascension",
	["path.Ascension.goal"] = "Rebirth only",
	["egg.PlatinumEgg.name"] = "Platinum Egg",
	["egg.SunEgg.name"] = "Sun Egg",
	["egg.ZenithEgg.name"] = "Zenith Egg",
	["egg.PrismEgg.name"] = "Prism Egg",
	["egg.AuroraEgg.name"] = "Aurora Egg",
	["egg.MistEgg.name"] = "Mist Egg",
	["egg.VoidEgg.name"] = "Void Egg",
	["egg.ShadowEgg.name"] = "Shadow Egg",
	["egg.AbyssEgg.name"] = "Abyss Egg",
	["egg.CometEgg.name"] = "Comet Egg",
	["egg.NovaEgg.name"] = "Nova Egg",
	["egg.GalaxyEgg.name"] = "Galaxy Egg",
	["egg.TranscendenceEgg.name"] = "Transcendence Egg",
	["egg.EternityEgg.name"] = "Eternity Egg",
	["egg.OmegaEgg.name"] = "Omega Egg",
	["baerchi.PhoenixBaerchi.name"] = "Phoenix Baerchi",
	["baerchi.GlacierBaerchi.name"] = "Glacier Baerchi",
	["baerchi.PhantomBaerchi.name"] = "Phantom Baerchi",
	["baerchi.SeraphBaerchi.name"] = "Seraph Baerchi",
	["baerchi.NorthernLightBaerchi.name"] = "Northern Light Baerchi",
	["baerchi.EclipseBaerchi.name"] = "Eclipse Baerchi",
	["baerchi.CometBaerchi.name"] = "Comet Baerchi",
	["baerchi.NebulaBaerchi.name"] = "Nebula Baerchi",
	["baerchi.PulsarBaerchi.name"] = "Pulsar Baerchi",
	["baerchi.ShadeBaerchi.name"] = "Shade Baerchi",
	["baerchi.RiddleBaerchi.name"] = "Riddle Baerchi",
	["baerchi.TitanBaerchi.name"] = "Titan Baerchi",
	["baerchi.GenesisBaerchi.name"] = "Genesis Baerchi",
	["baerchi.ChronosBaerchi.name"] = "Chronos Baerchi",
	["baerchi.InfinityBaerchi.name"] = "Infinity Baerchi",
	["baerchi.OmegaBaerchi.name"] = "Omega Baerchi",
	["skill.ChromaBlast.name"] = "Chroma Blast",
	["skill.TitanMode.name"] = "Titan Mode",
	["skill.BigBang.name"] = "Big Bang",
	["skill.PhoenixRebirth.name"] = "Phoenix Ember",
	["skill.GlacierFrost.name"] = "Glacier Breath",
	["skill.PhantomOmen.name"] = "Phantom Omen",
	["skill.SeraphGrace.name"] = "Seraph Blessing",
	["skill.AuroraVeil.name"] = "Aurora Veil",
	["skill.EclipseShroud.name"] = "Eclipse",
	["skill.CometImpact.name"] = "Comet Impact",
	["skill.NebulaBurn.name"] = "Nebula Burn",
	["skill.PulsarPulse.name"] = "Pulsar Pulse",
	["skill.ShadeSlash.name"] = "Shade Slash",
	["skill.RiddleBeam.name"] = "Riddle Beam",
	["skill.TitanFist.name"] = "Titan Fist",
	["skill.GenesisWave.name"] = "Genesis Wave",
	["skill.ChronosRift.name"] = "Time Rift",
	["skill.InfinityBarrage.name"] = "Infinity Barrage",
	["skill.OmegaStrike.name"] = "Omega Strike",
}
