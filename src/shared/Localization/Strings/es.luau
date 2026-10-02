--!strict
-- es.luau
-- ReplicatedStorage/Localization/Strings/es.luau
--
-- Español. Mismas claves y mismos {placeholders} que de.luau — ver la
-- cabecera de ese archivo para las convenciones. Los términos del juego
-- ("Baerchi", "Gummies", "GoldGummies", "PIT", "Rebirth") se mantienen
-- igual en todos los idiomas.

return {
	----------------------------------------------------------------------------
	-- Idioma
	----------------------------------------------------------------------------
	["ui.language.title"] = "Idioma",
	["ui.language.auto"]  = "Automático (Roblox)",

	----------------------------------------------------------------------------
	-- Tiempo
	----------------------------------------------------------------------------
	["time.s"]  = "{s} s",
	["time.ms"] = "{m} min {s} s",
	["time.hm"] = "{h} h {m} min",

	----------------------------------------------------------------------------
	-- Barra de menú
	----------------------------------------------------------------------------
	["ui.menu.eggs"]    = "Huevos",
	["ui.menu.baerchis"] = "Baerchis",
	["ui.menu.fight"]   = "Combate",
	["ui.menu.arena"]   = "Arena",

	----------------------------------------------------------------------------
	-- Rebirth
	----------------------------------------------------------------------------
	["ui.rebirth.title"]   = "Rebirth",
	["ui.rebirth.status"]  = "Rebirth {count}  —  Multiplicador x{mult:d2}",
	["ui.rebirth.cost"]    = "Cuesta {cost} Gummies  (tienes {have})",
	["ui.rebirth.loss"]    = "Se pierde: todos los Baerchis, todos los niveles de edificios, el nivel del PIT, las incubaciones en curso y tus Gummies (vuelven a {start}).\nSe conserva: GoldGummies, rango, estadísticas y Huevos de Ascensión ya ganados.",
	["ui.rebirth.reward"]  = "Después: Multiplicador x{mult:d2}",
	["ui.rebirth.reward_eggs.one"]   = "Después: Multiplicador x{mult:d2}  —  +{n} Huevo de Ascensión",
	["ui.rebirth.reward_eggs.other"] = "Después: Multiplicador x{mult:d2}  —  +{n} Huevos de Ascensión",
	["ui.rebirth.cancel"]  = "Cancelar",
	["ui.rebirth.confirm"] = "¡Rebirth!",

	----------------------------------------------------------------------------
	-- Mensajes (toasts)
	----------------------------------------------------------------------------
	["msg.recycled"]       = "Reciclado: +{gummies} Gummies",
	["msg.recycled_gold"]  = "Reciclado: +{gummies} Gummies  y  +{gold} GoldGummies",
	["msg.offline_honey"]  = "Mientras no estabas ({time}): +{honey} de miel",
	["msg.level_up"]       = "¡Subida de nivel!  Ahora nivel {level}",
	["msg.rebirth_done"]   = "Rebirth {count} conseguido: Multiplicador x{mult:d2}",
	["msg.rebirth_done_eggs.one"]   = "Rebirth {count} conseguido: Multiplicador x{mult:d2} y {n} Huevo de Ascensión",
	["msg.rebirth_done_eggs.other"] = "Rebirth {count} conseguido: Multiplicador x{mult:d2} y {n} Huevos de Ascensión",

	----------------------------------------------------------------------------
	-- Huevos en el mundo
	----------------------------------------------------------------------------
	["ui.egg.full"] = "Almacén lleno — ¡recoge primero!",
	["ui.egg.soon"] = "Próximo huevo: ¡enseguida!",
	["ui.egg.next"] = "Próximo huevo: {time}",

	----------------------------------------------------------------------------
	-- Acciones rechazadas
	----------------------------------------------------------------------------
	["err.unknown"]                 = "Acción no posible",
	["err.player_not_loaded"]       = "Jugador no cargado",
	["err.baerchi_not_found"]       = "Baerchi no encontrado",
	["err.baerchi_data_corrupt"]    = "Datos del Baerchi dañados",
	["err.baerchi_busy"]            = "El Baerchi está en movimiento — espera un momento",
	["err.not_enough_gummies"]      = "No tienes suficientes Gummies (tienes {have}, necesitas {need})",
	["err.not_enough_gold_gummies"] = "No tienes suficientes GoldGummies (tienes {have}, necesitas {need})",
	["err.rebirth_cost"]            = "El Rebirth cuesta {cost} Gummies (tienes {have})",

	["err.building_missing"]        = "Edificio no disponible",
	["err.building_unknown"]        = "Edificio desconocido",
	["err.max_level"]               = "Nivel máximo alcanzado",
	["err.max_pit_level"]           = "Nivel máximo del PIT alcanzado",
	["err.no_pit_cost"]             = "No hay coste definido para el nivel {level} del PIT",

	["err.charm_roll_cost"]         = "Una tirada cuesta {cost} GoldGummies (tienes {have})",
	["err.charm_no_free_slot"]      = "No hay ranura libre — todo está bloqueado o aún no desbloqueado",
	["err.charm_roll_failed"]       = "No se pudo cobrar la tirada",
	["err.charm_slot_empty"]        = "Esta ranura todavía no tiene ningún amuleto",

	["err.feed_building_empty"]     = "Este edificio no tiene miel ahora mismo",
	["err.feed_no_honey"]           = "No hay miel — los edificios aún están produciendo",

	["err.promo_maxed"]             = "Ya está ascendido al máximo",
	["err.promo_need_material"]     = "Necesitas {cost} x {name} como material (tienes {have})",

	["err.event_already_away"]      = "Tu Baerchi ya está en camino",
	["err.event_no_equipped"]       = "Ningún Baerchi equipado",
	["err.event_not_on_plot"]       = "El Baerchi no está en la parcela ahora mismo",
	["err.event_not_at_event"]      = "Tu Baerchi no está en el evento",

	["err.combat_busy"]             = "El Baerchi todavía está luchando en el PIT",
	["err.combat_exhausted"]        = "El Baerchi está agotado — dale miel primero",

	["err.fuse_self"]               = "Un Baerchi no puede fusionarse consigo mismo",
	["err.fuse_rarity_mismatch"]    = "Ambos Baerchis deben tener la misma rareza",
	["err.fuse_mythic"]             = "Mítico no se puede fusionar más",
	["err.fuse_no_higher"]          = "No hay una rareza superior",
	["err.fuse_none_defined"]       = "No hay Baerchis de rareza {rarity} definidos",
	["err.fuse_result_failed"]      = "No se pudo crear el resultado de la fusión",

	["err.egg_none_lying"]          = "No hay ningún huevo por ahí ahora mismo",
	["err.egg_slots_full"]          = "Las {slots} ranuras de incubación están ocupadas",
	["err.egg_gone"]                = "Este huevo ya no existe",
	["err.egg_wait"]                = "Faltan {seconds:dur} para que el huevo esté listo",
	["err.egg_type_gone"]           = "Este tipo de huevo ya no existe — recibes esto en su lugar: {egg}",
	["err.egg_internal"]            = "Error interno al eclosionar",
	["err.egg_unknown_type"]        = "Tipo de huevo desconocido",
	["err.egg_not_buyable"]         = "No hay {egg} en el almacén (no se puede comprar)",

	----------------------------------------------------------------------------
	-- Nombres: rarezas
	----------------------------------------------------------------------------
	["rarity.Common"]    = "Común",
	["rarity.Uncommon"]  = "Poco común",
	["rarity.Rare"]      = "Raro",
	["rarity.Epic"]      = "Épico",
	["rarity.Legendary"] = "Legendario",
	["rarity.Mythic"]    = "Mítico",

	----------------------------------------------------------------------------
	-- Nombres: Baerchis
	----------------------------------------------------------------------------
	["baerchi.RedBaerchi.name"]     = "Baerchi Rojo",
	["baerchi.GreenBaerchi.name"]   = "Baerchi Verde",
	["baerchi.YellowBaerchi.name"]  = "Baerchi Amarillo",
	["baerchi.BlueBaerchi.name"]    = "Baerchi Azul",
	["baerchi.OrangeBaerchi.name"]  = "Baerchi Naranja",
	["baerchi.SugarBaerchi.name"]   = "Baerchi de Azúcar",
	["baerchi.CrystalBaerchi.name"] = "Baerchi de Cristal",
	["baerchi.GoldenGrizzly.name"]  = "Grizzly Dorado",
	["baerchi.VoidBaerchi.name"]    = "Baerchi del Vacío",
	["baerchi.RainbowBaerchi.name"] = "Baerchi Arcoíris",
	["baerchi.AncientBaerchi.name"] = "Baerchi Ancestral",
	["baerchi.CosmicBaerchi.name"]  = "Baerchi Cósmico",

	----------------------------------------------------------------------------
	-- Nombres: mutaciones
	----------------------------------------------------------------------------
	["mutation.Gold.name"]      = "Oro",
	["mutation.Diamond.name"]   = "Diamante",
	["mutation.Bloodrot.name"]  = "Bloodrot",
	["mutation.Celestial.name"] = "Celestial",
	["mutation.Candy.name"]     = "Caramelo",
	["mutation.Lava.name"]      = "Lava",
	["mutation.Galaxy.name"]    = "Galaxia",
	["mutation.Rainbow.name"]   = "Arcoíris",

	----------------------------------------------------------------------------
	-- Nombres: huevos
	----------------------------------------------------------------------------
	["egg.BasicEgg.name"]     = "Huevo básico",
	["egg.SugarEgg.name"]     = "Huevo de azúcar",
	["egg.GoldenEgg.name"]    = "Huevo dorado",
	["egg.CrystalEgg.name"]   = "Huevo de cristal",
	["egg.AscensionEgg.name"] = "Huevo de Ascensión",

	----------------------------------------------------------------------------
	-- Nombres: edificios
	----------------------------------------------------------------------------
	["building.Beehive.name"]      = "Colmena",
	["building.HoneyPot.name"]     = "Tarro de miel",
	["building.HoneyPress.name"]   = "Prensa de miel",
	["building.Beehive.short"]     = "Colmena",
	["building.HoneyPot.short"]    = "Tarro",
	["building.HoneyPress.short"]  = "Prensa",

	----------------------------------------------------------------------------
	-- Nombres: rangos
	----------------------------------------------------------------------------
	["rank.1"] = "Gummy Novato",
	["rank.2"] = "Luchador de Azúcar",
	["rank.3"] = "Luchador de Cristal",
	["rank.4"] = "Campeón Dorado",
	["rank.5"] = "Leyenda Cósmica",

	----------------------------------------------------------------------------
	-- Nombres: habilidades
	----------------------------------------------------------------------------
	["skill.BasicPunch.name"]  = "Golpe básico",
	["skill.SugarRush.name"]   = "Subidón de azúcar",
	["skill.GummyShield.name"] = "Escudo gummy",
	["skill.IceSlam.name"]     = "Golpe helado",
	["skill.FireBite.name"]    = "Mordisco de fuego",
	["skill.SugarStorm.name"]  = "Tormenta de azúcar",
	["skill.ShardBlast.name"]  = "Ráfaga de fragmentos",
	["skill.GoldRush.name"]    = "Fiebre del oro",
	["skill.BlackHole.name"]   = "Agujero negro",
}
