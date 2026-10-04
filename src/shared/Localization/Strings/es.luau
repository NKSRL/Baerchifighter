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
	["ui.rebirth.loss"]    = "Se pierde: todos los niveles de edificios, el nivel del PIT, los niveles de tus Baerchis y tus Gummies (vuelven a {start}).\nSe conserva: tus Baerchis, todos los huevos, el Árbol de Huevos, GoldGummies, rango y estadísticas.",
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
	["err.recycle_equipped"] = "Equipa primero otro Baerchi, entonces podrás reciclar este",
	["err.honey_in_pit"] = "El Baerchi está luchando en el PIT ahora mismo",
	["err.event_ufo"] = "Tu Baerchi está siendo abducido por el OVNI",
	["err.combat_no_last_run"] = "No hay una última partida en este nivel de PIT — empieza desde el principio",
	["err.fuse_equipped_away"] = "El Baerchi equipado está en movimiento — espera un momento",
	["err.egg_none_in_stock"] = "No hay {egg} en el almacén",

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
	["baerchi.CosmicBaerchi.name"]  = "Baerchi Estelar",

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

	----------------------------------------------------------------------------
	-- Index, Quests (v13)
	----------------------------------------------------------------------------
	["ui.inventory.tab_pets"] = "Mis Baerchis",
	["ui.inventory.tab_index"] = "Índice",
	["ui.index.unknown"] = "???",
	["ui.index.drops_from"] = "Sale de:",
	["ui.index.you_have"] = "Tienes {n} en el almacén",
	["ui.index.no_source"] = "Ningún huevo lo da todavía.",
	["ui.index.progress"] = "Descubiertos {found}/{total}",
	["ui.quest.header"] = "Misión {done}/{total}",
	["ui.quest.chain_done"] = "¡Todas las misiones iniciales completadas!",
	["ui.quest.claim"] = "Recoger recompensa",
	["ui.quest.daily_link"] = "Misiones diarias {done}/{total}  >",
	["ui.quest.panel_title"] = "Misiones",
	["ui.quest.section_chain"] = "Misiones iniciales",
	["ui.quest.section_daily"] = "Misiones diarias",
	["ui.quest.resets_in"] = "Nuevas misiones diarias en {time}",
	["ui.quest.claimed"] = "Hecho",
	["ui.quest.claim_short"] = "Recoger",
	["ui.quest.reward_gummies"] = "+{n} Gummies",
	["ui.quest.reward_with_egg"] = "+{n} Gummies y un {egg}",
	["ui.quest.toast"] = "Misión completada: {text}",
	["err.quest_unknown"] = "Misión desconocida",
	["err.quest_already_claimed"] = "Ya recogida",
	["err.quest_not_current"] = "Esa no es la misión actual",
	["err.quest_not_done"] = "La misión aún no está completa",
	["quest.c_hatch1.title"] = "Abre tu primer huevo",
	["quest.c_hatch1.hint"] = "Toca HUEVOS a la derecha y abre un huevo de tu almacén.",
	["quest.c_pets3.title"] = "Ten 3 Baerchis",
	["quest.c_pets3.hint"] = "Sigue abriendo huevos: cada huevo te da un Baerchi.",
	["quest.c_fight1.title"] = "Gana tu primer combate",
	["quest.c_fight1.hint"] = "Pulsa Combate abajo para enviar a tu Baerchi a la PIT.",
	["quest.c_fight5.title"] = "Gana 5 combates",
	["quest.c_fight5.hint"] = "Sigue luchando en la PIT: cada etapa superada cuenta.",
	["quest.c_upgrade.title"] = "Mejora un edificio",
	["quest.c_upgrade.hint"] = "Ve a un edificio de tu parcela y pulsa E para mejorarlo.",
	["quest.c_hatch5.title"] = "Abre 5 huevos",
	["quest.c_hatch5.hint"] = "También hay huevos por tu parcela: pasa por encima para recogerlos.",
	["quest.c_discover5.title"] = "Descubre 5 Baerchis",
	["quest.c_discover5.hint"] = "Abre BAERCHIS > Índice para ver qué huevo da qué.",
	["quest.c_fuse1.title"] = "Fusiona dos Baerchis",
	["quest.c_fuse1.hint"] = "En BAERCHIS activa la Fusión y elige dos de la misma rareza.",
	["quest.c_pit2.title"] = "Mejora la arena",
	["quest.c_pit2.hint"] = "Ve a la plataforma de combate de tu parcela y pulsa E.",
	["quest.c_discover8.title"] = "Descubre 8 Baerchis",
	["quest.c_discover8.hint"] = "Toca una silueta negra del Índice para ver qué huevo necesitas.",
	["quest.c_fight25.title"] = "Gana 25 combates",
	["quest.c_fight25.hint"] = "Los Baerchis más fuertes llegan más lejos. Fusiona, asciende, repite.",
	["quest.c_discover10.title"] = "Descubre 10 Baerchis",
	["quest.c_discover10.hint"] = "Los huevos superiores guardan los raros: mira las probabilidades en el Índice.",
	["quest.d_hatch3.title"] = "Abre 3 huevos hoy",
	["quest.d_hatch3.hint"] = "Cuentan los huevos del almacén y los de la parcela.",
	["quest.d_fight8.title"] = "Gana 8 combates hoy",
	["quest.d_fight8.hint"] = "Usa el botón Combate de abajo.",
	["quest.d_earn.title"] = "Gana 1.500 Gummies hoy",
	["quest.d_earn.hint"] = "Los combates y tus edificios dan Gummies.",

	----------------------------------------------------------------------------
	-- v14: Mega Egg Tree (Ei-Baum, neue Eier, neue Baerchis, Faehigkeiten)
	----------------------------------------------------------------------------
	["ui.menu.tree"] = "Árbol",
	["ui.tree.title"] = "Árbol de Huevos",
	["ui.tree.title_bp"] = "Árbol de Huevos  —  Planos: {n}",
	["ui.tree.cond_hatch"] = "Abrir {egg}: {have}/{need}",
	["ui.tree.cond_any"] = "Huevos finales (6× cada uno): {have}/{need}",
	["ui.tree.cond_index"] = "{rarity} en el Índice: {have}/{need}",
	["ui.tree.cond_rebirth"] = "Rebirth: {have}/{need}",
	["ui.tree.cond_blueprint"] = "Plano usado",
	["ui.tree.path_line"] = "Ruta {path} — {goal}\nRareza media {avg}",
	["ui.tree.unlocked"] = "Desbloqueado",
	["ui.tree.ready"] = "Listo — se desbloquea",
	["ui.tree.locked"] = "Bloqueado",
	["ui.tree.needs"] = "Aún falta",
	["ui.tree.in_stock"] = "En almacén: {n}",
	["ui.tree.open"] = "Abrir",
	["ui.tree.press"] = "Prensar: {n} → 1 {egg}",
	["ui.tree.use_blueprint"] = "Usar plano (quedan {n})",
	["ui.tree.drops"] = "Qué sale",
	["ui.tree.lock_short"] = "cerr.",
	["ui.tree.jump_hint"] = "Huevo-salto de un evento: se puede abrir, pero no desbloquea el nodo.",
	["msg.tree_unlocked"] = "Árbol de Huevos: ¡{egg} desbloqueado!",
	["msg.pressed"] = "Prensado: {n}× {from} → 1 {to}",
	["msg.rebirth_done_list"] = "Rebirth {count} logrado: multiplicador x{mult:d2} y {eggs}",
	["ui.rebirth.reward_list"] = "Después: multiplicador x{mult:d2}  —  {eggs}",
	["err.press_blocked"] = "Los huevos de la ruta Ascensión no se pueden prensar",
	["err.press_no_next"] = "Este huevo no tiene siguiente nivel",
	["err.press_target_locked"] = "Primero desbloquea {egg} en el Árbol de Huevos",
	["err.press_not_enough"] = "Necesitas {n}× {egg} (tienes {have})",
	["err.blueprint_not_here"] = "Aquí no encaja ningún plano ahora mismo",
	["rarity.Divine"] = "Divino",
	["rarity.Cosmic"] = "Cósmico",
	["rarity.Secret"] = "Secreto",
	["rarity.Godly"] = "Celestial",
	["rarity.Eternal"] = "Eterno",
	["rarity.Omega"] = "Omega",
	["path.Stamm"] = "Tronco",
	["path.Stamm.goal"] = "Inicio",
	["path.Gold"] = "Oro",
	["path.Gold.goal"] = "La mascota más fuerte",
	["path.Kristall"] = "Cristal",
	["path.Kristall.goal"] = "La mascota más rápida",
	["path.Void"] = "Vacío",
	["path.Void.goal"] = "La mascota más rara",
	["path.Kosmos"] = "Cosmos",
	["path.Kosmos.goal"] = "Todoterreno",
	["path.Ascension"] = "Ascensión",
	["path.Ascension.goal"] = "Solo por Rebirth",
	["egg.PlatinumEgg.name"] = "Huevo de Platino",
	["egg.SunEgg.name"] = "Huevo Solar",
	["egg.ZenithEgg.name"] = "Huevo Cénit",
	["egg.PrismEgg.name"] = "Huevo Prisma",
	["egg.AuroraEgg.name"] = "Huevo Aurora",
	["egg.MistEgg.name"] = "Huevo de Niebla",
	["egg.VoidEgg.name"] = "Huevo del Vacío",
	["egg.ShadowEgg.name"] = "Huevo Sombrío",
	["egg.AbyssEgg.name"] = "Huevo Abisal",
	["egg.CometEgg.name"] = "Huevo Cometa",
	["egg.NovaEgg.name"] = "Huevo Nova",
	["egg.GalaxyEgg.name"] = "Huevo Galaxia",
	["egg.TranscendenceEgg.name"] = "Huevo de Trascendencia",
	["egg.EternityEgg.name"] = "Huevo de Eternidad",
	["egg.OmegaEgg.name"] = "Huevo Omega",
	["baerchi.PhoenixBaerchi.name"] = "Baerchi Fénix",
	["baerchi.GlacierBaerchi.name"] = "Baerchi Glaciar",
	["baerchi.PhantomBaerchi.name"] = "Baerchi Fantasma",
	["baerchi.SeraphBaerchi.name"] = "Baerchi Serafín",
	["baerchi.NorthernLightBaerchi.name"] = "Baerchi Aurora Boreal",
	["baerchi.EclipseBaerchi.name"] = "Baerchi Eclipse",
	["baerchi.CometBaerchi.name"] = "Baerchi Cometa",
	["baerchi.NebulaBaerchi.name"] = "Baerchi Nebulosa",
	["baerchi.PulsarBaerchi.name"] = "Baerchi Púlsar",
	["baerchi.ShadeBaerchi.name"] = "Baerchi Espectro",
	["baerchi.RiddleBaerchi.name"] = "Baerchi Enigma",
	["baerchi.TitanBaerchi.name"] = "Baerchi Titán",
	["baerchi.GenesisBaerchi.name"] = "Baerchi Génesis",
	["baerchi.ChronosBaerchi.name"] = "Baerchi Cronos",
	["baerchi.InfinityBaerchi.name"] = "Baerchi Infinito",
	["baerchi.OmegaBaerchi.name"] = "Baerchi Omega",
	["skill.ChromaBlast.name"] = "Chroma Blast",
	["skill.TitanMode.name"] = "Modo Titán",
	["skill.BigBang.name"] = "Big Bang",
	["skill.PhoenixRebirth.name"] = "Brasa del Fénix",
	["skill.GlacierFrost.name"] = "Aliento Glaciar",
	["skill.PhantomOmen.name"] = "Presagio Fantasma",
	["skill.SeraphGrace.name"] = "Bendición Seráfica",
	["skill.AuroraVeil.name"] = "Velo de Aurora",
	["skill.EclipseShroud.name"] = "Eclipse",
	["skill.CometImpact.name"] = "Impacto de Cometa",
	["skill.NebulaBurn.name"] = "Quemadura Nebular",
	["skill.PulsarPulse.name"] = "Pulso",
	["skill.ShadeSlash.name"] = "Tajo Sombrío",
	["skill.RiddleBeam.name"] = "Rayo Enigma",
	["skill.TitanFist.name"] = "Puño de Titán",
	["skill.GenesisWave.name"] = "Ola Génesis",
	["skill.ChronosRift.name"] = "Grieta Temporal",
	["skill.InfinityBarrage.name"] = "Ráfaga Infinita",
	["skill.OmegaStrike.name"] = "Golpe Omega",
}
