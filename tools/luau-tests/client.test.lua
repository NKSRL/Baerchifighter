-- Rauchtest der Client-Oberflaeche mit Mock-Roblox (node run.mjs client.test.lua)
-- Prueft: Sprache aus der Roblox-Einstellung, Wechsel per Auswahl, Server-Bestaetigung,
-- Toasts aus LocMsg, HUD/Menueleiste/Rebirth-Dialog bei Sprachwechsel.
local Loc = require(RS.Localization.Loc)
local fails = 0
local function check(name, got, want)
  if got ~= want then fails += 1; __log("FAIL", name, "got=[" .. tostring(got) .. "] want=[" .. tostring(want) .. "]")
  else __log("ok  ", name) end
end
local function byName(name, class)
  local out = {}
  for _, inst in CREATED do
    if rawget(inst._props, "Name") == name and (class == nil or inst.ClassName == class) then table.insert(out, inst) end
  end
  return out
end
local function lastText(name) local l = byName(name, "TextLabel"); return l[#l] and l[#l].Text end

SetLocale("fr-fr")
local LC = require(CL.Controllers.LanguageController)
LC.init()
check("fr aus Roblox-Sprache", Loc.getLanguage(), "fr")

local Remotes = require(RS.Network.Remotes)
local gui = MockProxy("ScreenGui")
local Toast = require(CL.UI.Toast)
Toast.init(gui)
local ClientState = require(CL.Controllers.ClientState)
ClientState.init()

-- Toast: ActionFailed als LocMsg
local failedHandler = Remotes.ActionFailed.OnClientEvent._handlers[1]
failedHandler("RequestUpgradeBuilding", { k = "err.not_enough_gummies", a = { have = 1234, need = 5000 } })
check("toast fr", lastText("Text"), "Pas assez de Gummies (tu as 1\u{00A0}234, il en faut 5\u{00A0}000)")
failedHandler("X", "Alter fertiger Text")
check("toast legacy string", lastText("Text"), "Alter fertiger Text")
failedHandler("X", { k = "err.promo_need_material", a = { cost = 3, name = { k = "baerchi.RedBaerchi.name" }, have = 1 } })
check("toast nested name", lastText("Text"), "Il te faut 3 x Baerchi Rouge comme matériel (tu en as 1)")

-- Spielstand
local data = {
  gummies = 1234567, goldGummies = 12, rebirthCount = 2, rebirthMult = 2.25,
  rank = { tier = 3, name = "Crystal Fighter", points = 300 },
  island = {
    pitLevel = 1, baerchis = {}, eggStock = {}, hatchingEggs = {}, laidEggs = {}, lastEggAt = 0,
    buildings = {
      Beehive    = { id = "Beehive",    level = 1, honey = 5, lastProducedAt = 0 },
      HoneyPot   = { id = "HoneyPot",   level = 1, honey = 0, lastProducedAt = 0 },
      HoneyPress = { id = "HoneyPress", level = 1, honey = 0, lastProducedAt = 0 },
    },
  },
}
local pushData = Remotes.PlayerDataUpdated.OnClientEvent._handlers[1]

local Hud = require(CL.UI.Hud)
Hud.init(gui)
local Menu = require(CL.UI.MenuBar)
Menu.init(gui)
local Rebirth = require(CL.UI.RebirthDialog)
Rebirth.init(gui)
local LP = require(CL.UI.LanguagePanel)
LP.init(gui)
local Feed = require(CL.Controllers.ResultFeed)
Feed.init()

pushData(data)

local vals = byName("Value", "TextLabel")
check("hud gummies fr", vals[1].Text, "1\u{00A0}234\u{00A0}567")
check("hud gold", vals[2].Text, "12")
check("hud rank fr", vals[3].Text, "Combattant de Cristal")
check("hud mult fr", vals[4].Text, "x2,25  (2)")
local langBtn = byName("Language", "TextButton")[1]
check("lang button text", langBtn.Text, "FR")

local names = byName("Name", "TextLabel")
local labels = {}
for _, n in names do table.insert(labels, n.Text) end
check("menu fr", table.concat(labels, "|"), "Oeufs|Baerchis|Combat|Ruche|Pot|Presse|Arène")

-- Sprachwechsel per Auswahl: en
local PM = require(CL.UI.PanelManager)
PM.open("Language")
local row = byName("Lang_en", "TextButton")[1]
row.Activated._handlers[1]()
check("choose en", Loc.getLanguage(), "en")
local fired = FIRED[#FIRED]
check("remote fired", fired.name .. ":" .. tostring(fired.args[1]), "RequestSetLanguage:en")
vals = byName("Value", "TextLabel")
check("hud rank en", vals[3].Text, "Crystal Fighter")
check("hud mult en", vals[4].Text, "x2.25  (2)")
check("hud gummies en", vals[1].Text, "1,234,567")
check("lang button en", langBtn.Text, "EN")
labels = {}
for _, n in byName("Name", "TextLabel") do table.insert(labels, n.Text) end
check("menu en", table.concat(labels, "|"), "Eggs|Baerchis|Fight|Hive|Pot|Press|Arena")

-- Veralteter Server-Stand darf die Wahl nicht zurueckdrehen (pending)
data.language = nil
pushData(data)
check("pending bleibt en", Loc.getLanguage(), "en")
-- Server bestaetigt
data.language = "en"
pushData(data)
check("bestaetigt en", Loc.getLanguage(), "en")
-- Spaeter aendert sich der Server-Stand (anderes Geraet): wird uebernommen
CLOCK = 100
data.language = "es"
pushData(data)
check("server-wechsel es", Loc.getLanguage(), "es")
labels = {}
for _, n in byName("Name", "TextLabel") do table.insert(labels, n.Text) end
check("menu es", table.concat(labels, "|"), "Huevos|Baerchis|Combate|Colmena|Tarro|Prensa|Arena")

-- Automatisch → zurueck auf Roblox-Sprache (fr-fr)
byName("Lang_auto", "TextButton")[1].Activated._handlers[1]()
check("auto → fr", Loc.getLanguage(), "fr")
local f2 = FIRED[#FIRED]
check("auto sendet nil", f2.name .. ":" .. tostring(f2.args[1]), "RequestSetLanguage:nil")

-- Rebirth-Dialog offen, de
LC.choose("de")
PM.open("Rebirth")
check("rebirth status de", lastText("Status"), "Rebirth 2  —  Multiplikator x2,25")
__log("INFO cost:", lastText("Cost"))
__log("INFO loss:", lastText("Loss"))
__log("INFO reward:", lastText("Reward"))
LC.choose("en")
check("rebirth status en (live)", lastText("Status"), "Rebirth 2  —  Multiplier x2.25")

-- ResultFeed
local recycled = Remotes.RecycleResultReceived.OnClientEvent._handlers[1]
recycled({ gummiesGained = 1500, goldGummiesGained = 2 })
check("recycle toast en", lastText("Text"), "Recycled: +1,500 Gummies  and  +2 GoldGummies")
Remotes.OfflineReportReceived.OnClientEvent._handlers[1]({ secondsAway = 3725, honeyGained = 40 })
check("offline toast en", lastText("Text"), "While you were away (1h 02m): +40 honey")
Remotes.RebirthResultReceived.OnClientEvent._handlers[1]({ newRebirthCount = 3, newMultiplier = 3.375, ascensionEggs = 1 })
check("rebirth toast en", lastText("Text"), "Rebirth 3 done: Multiplier x3.38 and 1 Ascension Egg")
__log(fails == 0 and "ALLE OK" or (fails .. " FEHLER"))
