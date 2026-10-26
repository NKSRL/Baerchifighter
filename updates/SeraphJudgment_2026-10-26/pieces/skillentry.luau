
	-- 26.10.2026 Himmelsgericht (Seraph-Baerchi, ersetzt SeraphGrace "Seraphen-
	-- Segen" als defaultSkill; SeraphGrace bleibt fuer alte Baerchis und Fusionen):
	-- aus dem Heiler wird ein Schlag. Opener wie Komet-Einschlag: der erste
	-- Einsatz je Gegner (je Stage) trifft voll, danach normal. Divine zwischen
	-- Mythic und Cosmic: erster Stoss 3.4x + 60, danach 1.8x + 60, Ladung 4 (wie
	-- vorher). Der Seraph ist der langsamste Divine (SPD 0.85, PWR 0.18) - je
	-- Sekunde bleibt Pulsar-Nova (Cosmic, ~2.85x + 120 bei Ladung 5) klar staerker.
	SeraphJudgment = {
		id = "SeraphJudgment", displayName = "Himmelsgericht",
		effectType = "Opener", category = "damage", cooldown = 4, charge = 4,
		params = { openerMultiplier = 3.4, multiplier = 1.8, baseDamage = 60 },
		description = "Sechs Fluegel aus Licht, ein Speer vom Himmel: der erste Stoss je Gegner 3.4x ATK + 60, danach 1.8x ATK + 60.",
		drawback = "Nur der erste Einsatz je Gegner trifft voll; heilt nicht mehr.",
	},