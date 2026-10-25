--!strict
-- Zuordnung Baerchi-ID -> Modellname in ReplicatedStorage.Assets.BaerchiModels.
-- Fehlt eine ID, nutzt BaerchiMesh wie bisher das Standardmodell (eingefaerbt).
return {
	MODEL_BY_ID = {
		AncientBaerchi = 'Pet_Uralter',
		BlueBaerchi = 'Bear_Eisbaer',
		AscendantBaerchi = 'Pet_Ascendant',   -- 20.10. P5d (FBX noch zu importieren)
		ChronosBaerchi = 'Pet_Chronos',
		CometBaerchi = 'Pet_Astronaut',
		CosmicBaerchi = 'Bear_Galaxiebaer',
		CrystalBaerchi = 'Pet_Detektiv',
		EclipseBaerchi = 'Excl_Teufel',
		GenesisBaerchi = 'Pet_Genesis',
		GlacierBaerchi = 'Pet_Gletscher',
		GoldenGrizzly = 'Pet_Grizzly',
		GreenBaerchi = 'Bear_Pandabaer',
		InfinityBaerchi = 'Pet_Infinity',
		NebulaBaerchi = 'Excl_UFO',
		NorthernLightBaerchi = 'Excl_Engel',
		OmegaBaerchi = 'Pet_Omega',
		OrangeBaerchi = 'Bear_Tigerbaer',
		PhantomBaerchi = 'Pet_Phantom',
		PhoenixBaerchi = 'Pet_Phoenix',
		PulsarBaerchi = 'Pet_Pulsar',
		RainbowBaerchi = 'Bear_Regenbogenbaer',
		RedBaerchi = 'Bear_Braunbaer',
		RiddleBaerchi = 'Pet_Raetsel',
		SeraphBaerchi = 'Pet_Seraph',
		ShadeBaerchi = 'Pet_Shade',
		SugarBaerchi = 'Pet_Zucker',
		TitanBaerchi = 'Pet_Titanen',
		VoidBaerchi = 'Pet_Ninja',
		YellowBaerchi = 'Bear_Honigbaer',
		GummiPirateBaerchi = 'Anime_Pirat',   -- 21.10. Anime-Pfad
		OrangeNinjaBaerchi = 'Anime_Ninja',
		StarWarriorBaerchi = 'Anime_Krieger',
		PlaidHunterBaerchi = 'Anime_Jaeger',
	} :: { [string]: string },
}
