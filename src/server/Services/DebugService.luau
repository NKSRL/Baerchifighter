--!strict
-- DebugService.luau
-- ServerScriptService/Services/DebugService.luau
--
-- Einzige Zustaendigkeit:
--   - Test-Befehle aus der Studio Command Bar entgegennehmen
--
-- NUR IN STUDIO. GameManager laedt dieses Modul im Live-Spiel gar nicht; die
-- Befehle liegen in src/server/Debug/Debug*.luau (je Domaene ein Modul).
--
-- Warum eine BindableFunction und nicht einfach _G oder ein require?
--   Die Command Bar laeuft in einem eigenen Lua-VM. Sie hat deshalb
--     * ihren eigenen require-Cache  → require(PlayerService) liefert dort eine
--       ZWEITE, nie initialisierte Kopie mit leerem _playerData, und
--     * ihr eigenes _G               → im Server gesetzte Globals sind unsichtbar.
--   Aufrufe auf der Kopie laufen still ins Leere, was beim Testen extrem
--   verwirrend ist. Eine BindableFunction ist eine Instanz im DataModel:
--   ihr OnInvoke wurde vom echten Server-Script gesetzt und laeuft daher
--   garantiert im echten Server-VM, mit dem echten Zustand.
--
-- Benutzung (Command Bar, Server-Kontext, Play laeuft):
--   local D = game.ServerScriptService.RBLDebug
--   D:Invoke("info")
--   D:Invoke("give", 100000, 1000)
--   D:Invoke("add", "RedBaerchi", 10)
--   D:Invoke("add", "RedBaerchi", 10, "Rainbow")   -- Mutation (siehe BaerchiConfig.MUTATIONS)
--   D:Invoke("stats", uid)                    -- Kampfwerte inkl. PWR
--   D:Invoke("list")
--   D:Invoke("fuse", uidA, uidB)
--   D:Invoke("recycle", uid)
--   D:Invoke("building", "Beehive", 5)   -- Level 1-60 (v15), Look folgt automatisch
--   D:Invoke("building", "HoneyRefiner", 60)
--   D:Invoke("hatch", "BasicEgg")   -- legt ein Ei ins Lager und oeffnet es sofort (v12)
--   D:Invoke("egg", "GoldenEgg", 5) -- 5 Eier ins Lager legen (ohne zu oeffnen)
--   D:Invoke("pitprogress", 12)     -- letzten Lauf im gewaehlten Tower auf Stage 12 setzen (Fortsetzungs-Test)
--   D:Invoke("petmode")             -- aktueller Zustand der Pet-Leiste
--   D:Invoke("pm", "Fight", "Last")  -- wie ein Klick auf die Pet-Leiste
--   D:Invoke("honey")               -- alle Honig-Lager sofort voll
--   D:Invoke("feed", uid, 20)       -- 20x fuettern (heilt + gibt XP)
--   D:Invoke("fight", uid)          -- kompletter Lauf im gewaehlten Tower
--   D:Invoke("skill", "equipped", "OmegaStrike") -- Faehigkeit tauschen (Show-Test)
--   D:Invoke("rebirth")
--
-- v8 (Promotion / Charms / Event-Teilnahme):
--   D:Invoke("promote", uid)        -- braucht genug Duplikate, siehe "add"
--   D:Invoke("charms", uid)         -- alle acht Slots im Klartext
--   D:Invoke("roll", uid, 5)        -- 5x wuerfeln (kostet GoldGummies)
--   D:Invoke("lock", uid, 1)        -- Slot I sperren/freigeben
--   D:Invoke("event")               -- ausgeruesteten Baerchi zum Event schicken
--   D:Invoke("skipevent")           -- laufende Phase sofort beenden
--   D:Invoke("events")              -- Katalog: alle Events mit ihrer Belohnung
--   D:Invoke("startevent", "ZauberZirkel")  -- genau dieses Event sofort starten
--
-- v10 (Eier legen):
--   D:Invoke("eggs")            -- was liegt herum, wie schnell legt er, welche Chancen
--   D:Invoke("lay", 5)          -- 5 Eier sofort legen (ohne aufs Intervall zu warten)
--   D:Invoke("collect")         -- alles einsammeln
--   D:Invoke("eggtime", 60)     -- Zeitmarke 60 Minuten zurueck, Tick legt nach
--
-- v15 (Waben im Event-Pit, Recycler):
--   D:Invoke("combs", 20)           -- 20 Waben sofort ins Pit legen (Stand ausgeben)
--   D:Invoke("queue", 50)           -- 50 Wabeneinheiten in die Recycler-Warteschlange
--   D:Invoke("recycler", 5)         -- Recycler-Level setzen (ohne Kosten), Stand ausgeben
--
-- v15 (Tower, Gebaeude 1-60, Angeben, Login-Bonus):
--   D:Invoke("tower", "II", 20)     -- Tower II waehlen und ab Stage 20 kaempfen (Fortsetzung gratis)
--   D:Invoke("towerrecord", "III", 45) -- Rekord setzen (Meilensteine bis dorthin werden ausgezahlt)
--   D:Invoke("rebirthcap")          -- Deckel des aktuellen Rebirths in allen Towern
--   D:Invoke("stagebest", "I", 30)  -- Sammel-Update: beste Stage dieses Lebens (Rebirth-Bedingung)
--   D:Invoke("incubator")           -- Solo-Inkubator: Stufe, Lager, Baerchi
--   D:Invoke("incubator", "breed")  -- der Baerchi im Inkubator bruetet sofort ein Ei
--   D:Invoke("incubator", "level", 3) -- Stufe setzen (1-4)
--   D:Invoke("incubator", "fill")   -- Lager voll
--   D:Invoke("dailyshift", 1)       -- Login-Bonus: so tun, als waeren 1 Tag(e) vergangen
--   D:Invoke("lbflush")             -- Bestenlisten sofort schreiben und neu lesen
--   D:Invoke("parts")               -- Teile auf der eigenen Insel zaehlen (Budget 250)
--   D:Invoke("journey", "state"|"set"|"reset", n)  -- Reise (P3): Stand zeigen / bis Etappe n-1 abgeholt / zuruecksetzen
--   D:Invoke("rocketisland", "state"|"set", n)  -- Raketen-Insel (P4): Lage/Teile, Schild-Zustand 1..3
--   D:Invoke("mapstyle", "on")      -- Map-Stil V2 (Meshes) an/aus/info: alt gegen neu vergleichen
--   D:Invoke("v14save")             -- Spielstand im alten v14-Format simulieren + migrieren
--
-- 26.10. (Traenke, DebugPotions):
--   D:Invoke("potions")             -- laufende Traenke mit Restzeit
--   D:Invoke("potion", "SpeedII")   -- Trank ohne Kosten anwenden (Stapel-Regel gilt)
--   D:Invoke("potion", "CoinsI", 20) -- ... mit 20 s Laufzeit (Ablauf testen)
--   D:Invoke("potion", "clear")     -- alle Traenke austragen
--   D:Invoke("merchant")            -- Sortiment, Preise fuer diesen Spieler, Zeit bis zum Wechsel
--   D:Invoke("merchant", "next")    -- Fenster weiterschalten (neues Los, alle Clients bekommen es)
--
-- v17 (lebendige Events):
--   D:Invoke("startevent", "Ufo")   -- UFO-Patrouille mit Abwuerfen
--   D:Invoke("jackpot")             -- naechster UFO-Abwurf ist sicher ein Jackpot (Stand des Pity-Zaehlers)
--   D:Invoke("combtheme", "HotEgg") -- Wabenthema setzen ("off" = normal)
--   D:Invoke("launch", 10)          -- 10 Waben einfliegen lassen (Vulkan aus der Mitte)
--   D:Invoke("startevent", "WaspQueen") -- Boss-Event sofort (laeuft sonst nur jeden 2. Durchlauf)
--
-- v14 (Mega Egg Tree):
--   D:Invoke("tree")                 -- alle 20 Knoten mit Bedingungen und Stand
--   D:Invoke("unlock", "SunEgg")     -- einen Knoten freischalten ("all" = alle)
--   D:Invoke("hatched", "SugarEgg", 15) -- Hatch-Zaehler setzen (Freischalt-Test)
--   D:Invoke("blueprint", 1)         -- Blaupausen gutschreiben
--   D:Invoke("useblueprint", "PlatinumEgg")
--   D:Invoke("press", "SugarEgg", "Void") -- 5 Zucker-Eier -> 1 Nebel-Ei
--   D:Invoke("setrebirth", 10)       -- Rebirth-Zaehler setzen (ohne Reset)
--   D:Invoke("skilltest", "OmegaBaerchi", 30) -- einen Kampf mit Runden-Log
--   D:Invoke("snapshot")             -- Spielstand merken (fuer Tests)
--   D:Invoke("restore")              -- gemerkten Spielstand zurueckschreiben
--
-- Welt aufwerten (08.10.2026, nur Optik, setzt workspace-Attribute fuer die
-- Client-Controller; alle Test-Clients sehen dasselbe):
--   D:Invoke("worldshots", 1)        -- Kamera auf festen Punkt 1..6 (UI aus), 0 = zurueck
--   D:Invoke("daytime", 19)          -- Tageslauf auf feste Uhrzeit, "auto" = Zyklus
--   D:Invoke("pitstate", "soon")     -- Pit-Rahmen: idle | soon | live | auto
--   D:Invoke("neststate", "boss")    -- Wespen-Nest: calm | boss | auto
--   D:Invoke("arrival")              -- Ankunft (Blasen + Bienen) erneut abspielen
--   D:Invoke("fish")                 -- sofort einen Honig-Fisch springen lassen
--   D:Invoke("islandstage", 4)       -- Insel-Deko Stufe 1..4 zeigen ("auto" = aus dem Fortschritt)
--   D:Invoke("pondfull")             -- Teich bis zum Rand fuellen (Ueberlauf-Tropfen)
--   D:Invoke("spectators", "hop")    -- Zuschauer an der eigenen Arena: hop | cheer
--   D:Invoke("record")               -- Rekord-Moment am eigenen Schau-Turm (Flagge glaenzt, Jubel)
--   D:Invoke("moment", "hatch", "Cosmic") -- Welt-Moment an alle: hatch <Rarity> | tower <Id> | record | rebirth | mutation <Id>
--   D:Invoke("moments5")             -- fuenf grosse Momente gleichzeitig (Drosselung pruefen)
--   (Event-Start und Boss: D:Invoke("pitstate", "live") / D:Invoke("neststate", "boss"))
--
-- HBB Paket 0 (Test-Zustaende, erst "snapshot"):
--   D:Invoke("state", "fresh")       -- neues Konto, Trichter F01–F10 misst
--   D:Invoke("state", "hatch10")     -- dazu zehn geoeffnete Basis-Eier
--   D:Invoke("state", "tower1")      -- dazu Tower I geschafft (Rekord 30)
--
-- Ein kompletter Event-Durchlauf ohne acht Minuten Wartezeit:
--   D:Invoke("skipevent")   → Pause endet, Event laeuft
--   D:Invoke("event")       → Baerchi laeuft hin (ein paar Sekunden abwarten)
--   D:Invoke("skipevent")   → Event endet, Stat-Stufe wird vergeben
--
-- Rueckgaben sind einfache Tabellen/Zahlen — BindableFunctions kopieren
-- Werte ueber die VM-Grenze, Funktionen und Metatables kommen nicht durch.

local RunService          = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local DebugRegistry = require(ServerScriptService.Debug.DebugRegistry)

local DebugService = {}

local BINDABLE_NAME = "RBLDebug"

local commands = DebugRegistry.commands

local MODULES = { "DebugBasics", "DebugProgress", "DebugWorld", "DebugArena", "DebugBaerchi", "DebugEvents", "DebugState", "DebugBridge", "DebugPotions" }

--------------------------------------------------------------------------------
-- Hilfebefehl
--------------------------------------------------------------------------------

commands.help = function()
	return {
		"info", "give <gummies> <gold>", "list",
		"add <configId> <level> [mutation]", "stats <uid>",
		"building <id> <level>",
		"hatch <eggType>", "egg <eggType> [anzahl]", "pitprogress <stage>", "honey", "feed <uid> <times>",
		"fight <uid>", "skill <uid|equipped> <skillId>",
		"fuse <uidA> <uidB> [ability|level|eggs] [A|B]",
		"recycle <uid>", "upgrade <buildingId>", "rebirth",

		-- v8
		"promote <uid>", "charms <uid>", "roll <uid> [anzahl]", "lock <uid> <slot>",
		"event", "recall", "skipevent", "events", "startevent <eventId>",

		-- v10
		"eggs", "lay [anzahl]", "collect", "eggtime <minuten>",

		-- v12
		"petmode", "pm <Event|Fight|Home> [Fresh|Percent|Last]",

		-- v14
		"tree", "unlock <eggType|all>", "hatched <eggType> <n>", "blueprint [n]",
		"useblueprint <eggType>", "press <eggType> [Gold|Kristall|Void]", "setrebirth <n>",
		"skilltest <configId> [stage]", "snapshot", "restore",
		-- HBB Paket 0
		"state <fresh|hatch10|tower1>  (erst snapshot!)",

		-- v15
		"combs [anzahl]", "queue <einheiten>", "recycler [level]",

		-- v15 (Tower/Gebaeude/Angeben/Login-Bonus)
		"tower <I|II|III|Final> <stage>", "towerrecord <id> <stage>", "rebirthcap",
		"epilog <start|reset|state|launch [fast]|scan|summit|summitoff|bridge|bridgeinstant|bridgeoff|terminal [zustand]|speed N|audit|on|off>  (20.10. Final-Epilog)",
		"pass <on|off|reset> [KEY]  (08.10.: Gamepass Gratis-Skip testen)",
		"dailyshift <tage>", "lbflush", "parts", "v14save",
		"mapstyle <on|off|info>  (20.10. Map-Stil V2)",

		-- v17
		"jackpot", "combtheme <themeId|off>", "launch [anzahl]",

		-- Welt aufwerten
		"worldshots [1..6|0]", "daytime <uhrzeit|auto>", "pitstate <idle|soon|live|auto>",
		"neststate <calm|boss|auto>", "arrival", "fish",
		"islandstage <1..4|auto>", "pondfull", "spectators <hop|cheer>", "record",
		"moment <hatch|tower|record|rebirth|mutation> [wert]", "moments5",
	}
end

--------------------------------------------------------------------------------
-- Initialisierung
--------------------------------------------------------------------------------

function DebugService.init()
	if not RunService:IsStudio() then
		return   -- im Live-Spiel gibt es diesen Service schlicht nicht
	end

	for _, moduleName in MODULES do
		require((ServerScriptService.Debug :: Folder):FindFirstChild(moduleName) :: ModuleScript)
	end

	local existing = ServerScriptService:FindFirstChild(BINDABLE_NAME)
	if existing then existing:Destroy() end

	local bindable = Instance.new("BindableFunction")
	bindable.Name   = BINDABLE_NAME
	bindable.Parent = ServerScriptService

	bindable.OnInvoke = function(command: any, ...)
		local name = tostring(command or "help")
		local handler = commands[name]
		if not handler then
			return { error = "Unbekannter Befehl: " .. name, verfuegbar = commands.help() }
		end

		if name == "help" then
			return commands.help()
		end

		local player, data, reason = DebugRegistry.requireData()
		if not player or not data then
			return { error = reason }
		end

		local ok, result = pcall(handler, player, data, ...)
		if not ok then
			return { error = tostring(result) }
		end
		return result
	end

	print("[DebugService] Initialisiert | Command Bar: game.ServerScriptService." .. BINDABLE_NAME .. ":Invoke(\"help\")")
end

return DebugService
