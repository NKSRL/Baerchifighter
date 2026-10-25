# apply_anime_egg.py - Welt 2 (21.10.2026): Anime-Ei verdrahten (Repo). Gezielte Textersetzung, wiederholbar (Marker pruefen), Backup vorher.
# Erzeugt ausserdem tools/anime/anime_edits.json fuer die Studio-Seite (gleiche Ersetzungen).
import json, os, shutil, sys
SRC = "src"
BACKUP = "backup_vor_animeei_2026-10-21"
L = {  # Sprache -> (Ei-Name, Ei-Beschreibung, Pfad-Ziel, 4 x (Name, Beschreibung))
 "de": ("Anime-Ei", "Ein Ei aus einer anderen Welt. Heldenhaft.", "Ab Welt 2",
   [("Gummi-Pirat","Sein Arm reicht bis zum Horizont."),("Orange-Ninja","Schnell, laut und immer hungrig."),("Sternenkrieger","Seine Haare trotzen jeder Schwerkraft."),("Karo-Jäger","Ein Schwert, ein Umhang, ein Versprechen.")]),
 "en": ("Anime Egg", "An egg from another world. Heroic.", "From World 2",
   [("Rubber Pirate","His arm reaches the horizon."),("Orange Ninja","Fast, loud and always hungry."),("Star Warrior","His hair defies gravity."),("Plaid Hunter","One sword, one cloak, one promise.")]),
 "fr": ("Oeuf Anime", "Un oeuf venu d'un autre monde. Héroïque.", "Dès le monde 2",
   [("Pirate Élastique","Son bras atteint l'horizon."),("Ninja Orange","Rapide, bruyant et toujours affamé."),("Guerrier des Étoiles","Ses cheveux défient la gravité."),("Chasseur à Carreaux","Une épée, une cape, une promesse.")]),
 "es": ("Huevo Anime", "Un huevo de otro mundo. Heroico.", "Desde el mundo 2",
   [("Pirata Elástico","Su brazo llega al horizonte."),("Ninja Naranja","Rápido, ruidoso y siempre hambriento."),("Guerrero Estelar","Su pelo desafía la gravedad."),("Cazador a Cuadros","Una espada, una capa, una promesa.")]),
}
PET_IDS = ["GummiPirateBaerchi", "OrangeNinjaBaerchi", "StarWarriorBaerchi", "PlaidHunterBaerchi"]
E = []  # (relpath, old, new)
def add(rel, old, new): E.append((rel, old, new))

add("shared/Network/Types.luau", '\t| "OmegaEgg"\n\t-- Sonder-Eier ausserhalb', '\t| "OmegaEgg"\n\t-- Anime-Pfad (ab Welt 2)\n\t| "AnimeEgg"\n\t-- Sonder-Eier ausserhalb')
add("shared/Network/Types.luau", '"Kosmos" | "Ascension"\n\t| "Event"', '"Kosmos" | "Ascension" | "Anime"\n\t| "Event"')
add("shared/Config/FeatureFlags.luau", '\tWELT2_LOOK        = true,\n',
    '\tWELT2_LOOK        = true,\n\t-- 21.10. (Welt 2): Anime-Ei (Pfad "Anime", 4 Pets), frei ab Welt 2 (Epilog gestartet). Aus = Ei bleibt gesperrt.\n\t-- Plan: nach Abnahme plus einem Release entfernen. Bericht: claude/HBB_W2_ANIME_EI_UMGESETZT_2026-10-21.md\n\tANIME_EGG         = true,\n')
add("shared/Config/BaerchiConfig.luau", '\t-- v17: Sonder-Eier aus Events (kein Baerchi hat diesen Pfad)\n',
    '\t-- 21.10. Welt 2: Anime-Pfad (Basis-Anime-Ei). Eigene Archetypen, keine Originalfiguren.\n\t{ id = "Anime",     color = Color3.fromRGB(255, 140,  50), goal = "world2" },\n\t-- v17: Sonder-Eier aus Events (kein Baerchi hat diesen Pfad)\n')
pets = '''
	-- ============================================================
	-- ANIME-PFAD (21.10. Welt 2, Basis-Anime-Ei). Fallen nur aus Anime-Eiern (EggConfig.buildHatchTables).
	-- Eigene Archetypen, keine Originalfiguren, keine Originalnamen (Recht: claude/HBB_W2_ANIME_EI_PROTOTYP_2026-10-21.md).
	-- Faehigkeiten: je Pet eine eigene (SkillConfig/SkillFXConfig), aus vorhandenen Effekt-Typen gebaut.
	-- ============================================================

	GummiPirateBaerchi = {
		id = "GummiPirateBaerchi", displayName = "Gummi-Pirat", rarity = "Mythic", path = "Anime",
		baseStats = { hp = 1500, atk = 110, spd = 1.1, pwr = 0.24 },
		layIntervalSeconds = 190,
		eggTable = {
			{ eggType = "AnimeEgg", weight = 100 },
		},
		defaultSkill = "RubberSmash", eggSource = {},
		description = "Sein Arm reicht bis zum Horizont.",
	},

	OrangeNinjaBaerchi = {
		id = "OrangeNinjaBaerchi", displayName = "Orange-Ninja", rarity = "Mythic", path = "Anime",
		baseStats = { hp = 1100, atk = 95, spd = 1.5, pwr = 0.30 },
		layIntervalSeconds = 185,
		eggTable = {
			{ eggType = "AnimeEgg", weight = 100 },
		},
		defaultSkill = "SpiralDash", eggSource = {},
		description = "Schnell, laut und immer hungrig.",
	},

	StarWarriorBaerchi = {
		id = "StarWarriorBaerchi", displayName = "Sternenkrieger", rarity = "Divine", path = "Anime",
		baseStats = { hp = 2400, atk = 150, spd = 1.1, pwr = 0.20 },
		layIntervalSeconds = 200,
		eggTable = {
			{ eggType = "AnimeEgg", weight = 100 },
		},
		defaultSkill = "StarBlast", eggSource = {},
		description = "Seine Haare trotzen jeder Schwerkraft.",
	},

	PlaidHunterBaerchi = {
		id = "PlaidHunterBaerchi", displayName = "Karo-Jäger", rarity = "Divine", path = "Anime",
		baseStats = { hp = 2000, atk = 140, spd = 1.3, pwr = 0.26 },
		layIntervalSeconds = 195,
		eggTable = {
			{ eggType = "AnimeEgg", weight = 100 },
		},
		defaultSkill = "PlaidSlash", eggSource = {},
		description = "Ein Schwert, ein Umhang, ein Versprechen.",
	},
'''
add("shared/Config/BaerchiConfig.luau", '\t\tdescription = "Der letzte Baerchi. Danach kommt nichts mehr.",\n\t},\n}\n',
    '\t\tdescription = "Der letzte Baerchi. Danach kommt nichts mehr.",\n\t},\n' + pets + '}\n')
add("shared/Config/BaerchiModels.luau", "\t\tYellowBaerchi = 'Bear_Honigbaer',\n",
    "\t\tYellowBaerchi = 'Bear_Honigbaer',\n\t\tGummiPirateBaerchi = 'Anime_Pirat',   -- 21.10. Anime-Pfad\n\t\tOrangeNinjaBaerchi = 'Anime_Ninja',\n\t\tStarWarriorBaerchi = 'Anime_Krieger',\n\t\tPlaidHunterBaerchi = 'Anime_Jaeger',\n")
EG = "shared/Config/EggConfig.luau"
add(EG, "\tOmegaEgg         = { Eternal = 70, Omega = 30 },\n", "\tOmegaEgg         = { Eternal = 70, Omega = 30 },\n\tAnimeEgg         = { Mythic = 75, Divine = 25 },   -- 21.10. Welt 2: Anime-Pfad, genau 4 Pets (2 Mythic, 2 Divine)\n")
add(EG, "\tGalaxyEgg = 0.5, TranscendenceEgg = 0.5, EternityEgg = 0.5, OmegaEgg = 0.5,\n", "\tGalaxyEgg = 0.5, TranscendenceEgg = 0.5, EternityEgg = 0.5, OmegaEgg = 0.5,\n\tAnimeEgg = 5,\n")
add(EG, '\tVoid = "Right", Ascension = "Right",\n', '\tVoid = "Right", Ascension = "Right", Anime = "Right",\n')
add(EG, "\t-- SONDER-EIER (v17, nicht im Baum)\n", '''\t-- ANIME-PFAD (21.10., ab Welt 2): Anime-Pets fallen NUR aus Anime-Eiern (siehe buildHatchTables)
\t-- ============================================================
\tAnimeEgg = {
\t\tid = "AnimeEgg", displayName = "Anime-Ei", path = "Anime", parent = nil, tier = 5, sortOrder = 22,
\t\tdescription = "Ein Ei aus einer anderen Welt. Heldenhaft.",
\t\tcolor = Color3.fromRGB(255, 140, 50), shortName = "Anime", hatchTable = {},
\t},

\t-- ============================================================
\t-- SONDER-EIER (v17, nicht im Baum)
''')
add(EG, "\tstart      : boolean?,        -- von Anfang an frei\n", "\tstart      : boolean?,        -- von Anfang an frei\n\tworld2     : boolean?,        -- 21.10. Anime-Ei: frei, sobald Welt 2 offen ist (Epilog gestartet) und Schalter ANIME_EGG an\n")
add(EG, '\tOmegaEgg         = { rebirth = 50, ascensionV2 = { keyPets = { "ChronosBaerchi", "InfinityBaerchi" } } },\n',
    '\tOmegaEgg         = { rebirth = 50, ascensionV2 = { keyPets = { "ChronosBaerchi", "InfinityBaerchi" } } },\n\n\t-- 21.10. Welt 2: das Anime-Ei ist ein eigener Pfad ohne Elternei, frei sobald Welt 2 offen ist.\n\tAnimeEgg         = { world2 = true },\n')
add(EG, "if EGG_PET_WHITELIST[eggId] and not EGG_PET_WHITELIST[eggId][def.id] then continue end   -- 21.10.\n",
    "if EGG_PET_WHITELIST[eggId] and not EGG_PET_WHITELIST[eggId][def.id] then continue end   -- 21.10.\n\t\t\t\tif (def.path == \"Anime\") ~= (egg.path == \"Anime\") then continue end   -- 21.10. Anime-Pets nur aus Anime-Eiern und umgekehrt\n")
add(EG, "\tblockedPaths  = { Ascension = true, Event = true },", "\tblockedPaths  = { Ascension = true, Event = true, Anime = true },")
ET = "shared/Modules/EggTree.luau"
add(ET, "\t\tlocal ascV2 = node.ascensionV2\n", '''\t\tif node.world2 then   -- 21.10. Anime-Ei: Welt 2 offen (Epilog gestartet) und Schalter ANIME_EGG
\t\t\tlocal open = FeatureFlags.isOn("ANIME_EGG") and input.epilog ~= nil and input.epilog.state == "launched"
\t\t\ttable.insert(conditions, { kind = "world2", have = if open then 1 else 0, need = 1, done = open })
\t\tend

\t\tlocal ascV2 = node.ascensionV2
''')
add(ET, 'if egg.path ~= "Ascension" and not egg.special and EggTree.isUnlocked(state, eggId) then', 'if egg.path ~= "Ascension" and egg.path ~= "Anime" and not egg.special and EggTree.isUnlocked(state, eggId) then')
add(ET, 'if egg.path ~= "Ascension" and not EggTree.isUnlocked(state, eggId) then', 'if egg.path ~= "Ascension" and egg.path ~= "Anime" and not EggTree.isUnlocked(state, eggId) then')
add("shared/Config/EconomyConfig.luau", '\t{ id = "epilog_launched", kind = "epilog", eggs = { { eggType = "AscensionEgg", count = 1 } } },\n',
    '\t{ id = "epilog_launched", kind = "epilog", eggs = { { eggType = "AscensionEgg", count = 1 } } },\n\t-- 21.10. Welt 2: Start-Eier fuer den Anime-Pfad (einmalig, ebenfalls mit dem Epilog-Knopf).\n\t{ id = "epilog_launched_anime", kind = "epilog", eggs = { { eggType = "AnimeEgg", count = 3 } } },\n')
add("client/UI/EggTreeLayout.luau", "\tOmegaEgg         = { x = 1527, y = 219 },\n", "\tOmegaEgg         = { x = 1527, y = 219 },\n\t-- Rechts: Anime (freier Kelch R_K, Welt 2)\n\tAnimeEgg         = { x = 1107, y = 345 },\n")
add("client/UI/EggTreeLayout.luau", '\t{ id = "R_K", branch = "Right", x = 1107, y = 345 },\n', "")
add("client/UI/EggTreePanel.luau", 'Kosmos = "tree/branch_kosmos", Ascension = "tree/branch_ascension",', 'Kosmos = "tree/branch_kosmos", Ascension = "tree/branch_ascension",\n\tAnime = "tree/branch_ascension",')
add("client/UI/Icons.luau", '\t["eggs/UfoJackpotEgg"]          = "",\n', '\t["eggs/UfoJackpotEgg"]          = "",\n\t["eggs/AnimeEgg"]               = "",\n')
add("shared/Modules/EggLook.luau", '\tEvent     = "stars",\n', '\tEvent     = "stars",\n\tAnime     = "swirl",\n')
add("shared/Modules/EggLook.luau", "\tEvent     = Color3.fromRGB(255, 255, 255),\n", "\tEvent     = Color3.fromRGB(255, 255, 255),\n\tAnime     = Color3.fromRGB(255, 170, 70),\n")

SK = "shared/Config/SkillConfig.luau"
add(SK, "\tGenesisWave = {\n", '''\t-- 21.10. Welt 2: Faehigkeiten der Anime-Pets (je Pet eine eigene, Effekt-Typen wie bei den bestehenden)
\tRubberSmash = {
\t\tid = "RubberSmash", displayName = "Gummi-Schlag",
\t\teffectType = "Damage", category = "damage", cooldown = 5, charge = 5,
\t\tparams = { multiplier = 3.0, baseDamage = 70 },
\t\tdescription = "Ein gedehnter Hieb, 3x Schaden.",
\t\tdrawback = "Cooldown 5.",
\t},
\tSpiralDash = {
\t\tid = "SpiralDash", displayName = "Wirbelsprint",
\t\teffectType = "Ramp", category = "damage", cooldown = 3, charge = 3,
\t\tparams = { multiplier = 1.1, rampPerUse = 0.5, baseDamage = 35 },
\t\tdescription = "Jeder Sprint trifft staerker als der vorige.",
\t\tdrawback = "Schwacher Anfang.",
\t},
\tStarBlast = {
\t\tid = "StarBlast", displayName = "Sternenblitz",
\t\teffectType = "Damage", category = "damage", cooldown = 5, charge = 5,
\t\tparams = { multiplier = 2.9, baseDamage = 80 },
\t\tdescription = "Ein gebuendelter Strahl, 2.9x Schaden.",
\t\tdrawback = "Cooldown 5.",
\t},
\tPlaidSlash = {
\t\tid = "PlaidSlash", displayName = "Karo-Schnitt",
\t\teffectType = "Finisher", category = "damage", cooldown = 3, charge = 3,
\t\tparams = { multiplier = 1.5, finisherMultiplier = 3.6, threshold = 0.30, baseDamage = 45 },
\t\tdescription = "Unter 30% Gegner-HP trifft der Schnitt mit 3.6x ATK.",
\t\tdrawback = "Gegen volle Gegner nur durchschnittlich.",
\t},
\tGenesisWave = {
''')
FXS = "shared/Config/SkillFXConfig.luau"
add(FXS, "\tAscendingLight = {   -- 20.10. P5d\n", '''\t-- 21.10. Welt 2: Anime-Pets, aus vorhandenen Effekt-Bausteinen (ohne neue Texturen)
\tRubberSmash = {
\t\ttier = 3, duration = 3.8, color = C(230, 70, 60), color2 = C(255, 220, 120),
\t\tsounds = { charge = "whoosh", strike = "boom", impact = "thunder" }, pitch = 0.9,
\t\tsteps = {
\t\t\t{ t = 0.00, fx = "sound",     slot = "charge" },
\t\t\t{ t = 0.00, fx = "ring",      at = "self", radius = 5, dur = 1.0 },
\t\t\t{ t = 0.30, fx = "cinematic", dur = 1.6, style = "orbit" },
\t\t\t{ t = 1.40, fx = "beam",      width = 1.6, dur = 0.5 },
\t\t\t{ t = 1.40, fx = "sound",     slot = "strike" },
\t\t\t{ t = 1.90, fx = "flash",     dur = 0.2 },
\t\t\t{ t = 1.90, fx = "wave",      at = "target", radius = 18, dur = 0.7 },
\t\t\t{ t = 1.90, fx = "sound",     slot = "impact" },
\t\t\t{ t = 1.90, fx = "shake",     power = 1.0, dur = 0.6 },
\t\t},
\t},

\tSpiralDash = {
\t\ttier = 2, duration = 3.0, color = C(255, 150, 50), color2 = C(60, 100, 220),
\t\tsounds = { charge = "whoosh", strike = "whoosh", impact = "ping" }, pitch = 1.3,
\t\tsteps = {
\t\t\t{ t = 0.00, fx = "sound",     slot = "charge" },
\t\t\t{ t = 0.00, fx = "ring",      at = "self", radius = 4, dur = 0.8 },
\t\t\t{ t = 0.20, fx = "ring",      at = "self", radius = 7, dur = 0.8 },
\t\t\t{ t = 0.80, fx = "cinematic", dur = 1.4, style = "orbit" },
\t\t\t{ t = 1.50, fx = "sound",     slot = "strike" },
\t\t\t{ t = 1.60, fx = "shards",    at = "target", count = 14, size = 0.7, dur = 0.8 },
\t\t\t{ t = 1.60, fx = "sound",     slot = "impact" },
\t\t\t{ t = 1.60, fx = "shake",     power = 0.5, dur = 0.3 },
\t\t},
\t},

\tStarBlast = {
\t\ttier = 4, duration = 4.0, color = C(255, 200, 80), color2 = C(255, 255, 255),
\t\tsounds = { charge = "rumble", strike = "rocket", impact = "boom" }, pitch = 1.0,
\t\tsteps = {
\t\t\t{ t = 0.00, fx = "sky",       tint = C(255, 235, 190), brightness = 0.1, saturation = 0.2, dur = 3.6 },
\t\t\t{ t = 0.00, fx = "sound",     slot = "charge" },
\t\t\t{ t = 0.00, fx = "shake",     power = 0.3, dur = 1.4 },
\t\t\t{ t = 0.00, fx = "ring",      at = "self", radius = 6, dur = 1.4 },
\t\t\t{ t = 0.50, fx = "cinematic", dur = 1.8, style = "up" },
\t\t\t{ t = 1.60, fx = "beam",      width = 3.0, dur = 1.1 },
\t\t\t{ t = 1.60, fx = "sound",     slot = "strike" },
\t\t\t{ t = 2.30, fx = "flash",     dur = 0.2 },
\t\t\t{ t = 2.30, fx = "wave",      at = "target", radius = 22, dur = 0.8 },
\t\t\t{ t = 2.30, fx = "sound",     slot = "impact" },
\t\t\t{ t = 2.30, fx = "shake",     power = 1.1, dur = 0.6 },
\t\t},
\t},

\tPlaidSlash = {
\t\ttier = 3, duration = 3.4, color = C(60, 170, 110), color2 = C(220, 230, 240),
\t\tsounds = { charge = "ping", strike = "whoosh", impact = "glass" }, pitch = 1.1,
\t\tsteps = {
\t\t\t{ t = 0.00, fx = "sound",     slot = "charge" },
\t\t\t{ t = 0.00, fx = "ring",      at = "self", radius = 5, dur = 1.0 },
\t\t\t{ t = 0.40, fx = "cinematic", dur = 1.6, style = "orbit" },
\t\t\t{ t = 1.50, fx = "sound",     slot = "strike" },
\t\t\t{ t = 1.60, fx = "beam",      width = 0.6, dur = 0.4 },
\t\t\t{ t = 2.00, fx = "shards",    at = "target", count = 18, size = 0.8, dur = 0.9 },
\t\t\t{ t = 2.00, fx = "sound",     slot = "impact" },
\t\t\t{ t = 2.00, fx = "shake",     power = 0.7, dur = 0.4 },
\t\t},
\t},

\tAscendingLight = {   -- 20.10. P5d
''')
SKILL_LOC = {
 "de": [("Gummi-Schlag","Ein gedehnter Hieb, 3x Schaden.","Cooldown 5."),("Wirbelsprint","Jeder Sprint trifft stärker als der vorige.","Schwacher Anfang."),("Sternenblitz","Ein gebündelter Strahl, 2.9x Schaden.","Cooldown 5."),("Karo-Schnitt","Unter 30% Gegner-HP trifft der Schnitt mit 3.6x ATK.","Gegen volle Gegner nur durchschnittlich.")],
 "en": [("Rubber Smash","A stretched strike, 3x damage.","Cooldown 5."),("Spiral Dash","Each dash hits harder than the last.","Weak start."),("Star Blast","A focused beam, 2.9x damage.","Cooldown 5."),("Plaid Slash","Below 30% enemy HP the slash hits for 3.6x ATK.","Only average against full-health enemies.")],
 "fr": [("Frappe Élastique","Un coup étiré, 3x dégâts.","Récupération 5."),("Sprint en Spirale","Chaque sprint frappe plus fort que le précédent.","Début faible."),("Éclair d'Étoile","Un rayon concentré, 2.9x dégâts.","Récupération 5."),("Coupe à Carreaux","Sous 30% de PV ennemis, la coupe frappe à 3.6x ATK.","Moyen contre les ennemis en pleine forme.")],
 "es": [("Golpe Elástico","Un golpe estirado, 3x de daño.","Enfriamiento 5."),("Carrera en Espiral","Cada carrera golpea más fuerte que la anterior.","Inicio débil."),("Destello Estelar","Un rayo concentrado, 2.9x de daño.","Enfriamiento 5."),("Corte a Cuadros","Con menos del 30% de PV enemigos, el corte golpea con 3.6x ATK.","Solo normal contra enemigos con vida completa.")],
}
SKILL_IDS = ["RubberSmash", "SpiralDash", "StarBlast", "PlaidSlash"]

def lineof(text, key):
    for ln in text.split("\n"):
        if ln.startswith('\t["%s"]' % key): return ln + "\n"
    raise SystemExit("Zeile fehlt: " + key)
for lang, (en, ed, goal, ps) in L.items():
    rel = "shared/Localization/Strings/%s.luau" % lang
    txt = open(os.path.join(SRC, rel), encoding="utf-8").read()
    for key, new in (("egg.UfoJackpotEgg.name", '\t["egg.AnimeEgg.name"]  = "%s",\n' % en),
                     ("egg.UfoJackpotEgg.desc", '\t["egg.AnimeEgg.desc"]            = "%s",\n' % ed),
                     ("egg.UfoJackpotEgg.short", '\t["egg.AnimeEgg.short"]           = "Anime",\n'),
                     ("path.Event.goal", '\t["path.Anime"]              = "Anime",\n\t["path.Anime.goal"]         = "%s",\n' % goal),
                     ("skill.TitanFist.name", "".join('\t["skill.%s.name"] = "%s",\n' % (sid, sk[0]) for sid, sk in zip(SKILL_IDS, SKILL_LOC[lang]))),
                     ("skill.TitanFist.desc", "".join('\t["skill.%s.desc"]            = "%s",\n' % (sid, sk[1]) for sid, sk in zip(SKILL_IDS, SKILL_LOC[lang]))),
                     ("skill.TitanFist.drawback", "".join('\t["skill.%s.drawback"]        = "%s",\n' % (sid, sk[2]) for sid, sk in zip(SKILL_IDS, SKILL_LOC[lang]))),
                     ("baerchi.AscendantBaerchi.desc", "".join('\t["baerchi.%s.name"] = "%s",\n\t["baerchi.%s.desc"] = "%s",\n' % (pid, n, pid, d) for pid, (n, d) in zip(PET_IDS, ps)))):
        old = lineof(txt, key)
        add(rel, old, old + new)

if "--apply" in sys.argv:
    done = set()
    for rel, old, new in E:
        p = os.path.join(SRC, rel); t = open(p, encoding="utf-8", newline="").read()
        if rel not in done:
            bp = os.path.join(BACKUP, rel); os.makedirs(os.path.dirname(bp), exist_ok=True)
            if not os.path.exists(bp): shutil.copy2(p, bp)
            done.add(rel)
        if "\r\n" in t: old = old.replace("\r\n", "\n").replace("\n", "\r\n"); new = new.replace("\r\n", "\n").replace("\n", "\r\n")
        assert t.count(old) == 1, "Anker nicht eindeutig/fehlt: %s: %r (%d)" % (rel, old[:60], t.count(old))
        t = t.replace(old, new); open(p, "w", encoding="utf-8", newline="").write(t)
    print("Repo angewendet:", len(E), "Ersetzungen")
json.dump([{"f": r, "o": o, "n": n} for r, o, n in E], open("tools/anime/anime_edits.json", "w", encoding="utf-8"), ensure_ascii=False)
print("edits:", len(E))
