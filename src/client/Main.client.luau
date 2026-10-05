--!strict
-- Main.client.luau
-- StarterPlayerScripts/Main.client.luau
--
-- Bootstrap des Clients — das Gegenstueck zu GameManager auf dem Server.
-- Einzige Stelle die die Startreihenfolge der Client-Module kennt.
--
-- ACHTUNG beim Umbenennen: die Datei darf NICHT "init.client.luau" heissen.
-- Rojo macht aus einem Ordner mit init-Datei ein Script statt eines
-- Containers — auf StarterPlayerScripts angewandt heisst das, dass der
-- gesamte Client-Teilbaum nie im Spiel ankommt. Genau das hat den
-- Server-Sync schon einmal lahmgelegt.
--
-- Reihenfolge:
--   1. ScreenGui anlegen — alle UI-Module haengen sich dort ein.
--   2. Toast zuerst, damit fruehe Fehlermeldungen schon sichtbar sind.
--   3. ClientState VOR den datengetriebenen UIs: die registrieren sich per
--      onChanged und bekommen den aktuellen Stand sofort nachgereicht.
--   4. Die Panels. Jedes meldet sich in seinem init beim PanelManager an —
--      erst danach duerfen Module laufen die Panels oeffnen wollen.
--   5. Hud und MenuBar: beide sind reine Ausloeser und brauchen die
--      angemeldeten Panels (Rebirth-Pille, Menue-Knoepfe).
--   6. ResultFeed — Toast-Meldungen fuer Recycling und Offline-Ertrag.
--      Muss vor dem ersten Serverpaket stehen, sonst geht der Offline-Report
--      des Joins verloren.
--   7. WorldController zuletzt — er braucht Panel und PanelManager.
--   8. EggTimerController — unabhaengig von allen anderen, braucht nur
--      ClientState (schon initialisiert) und die Figuren in der Welt.
--   9. SkillFXController (v14) — hoert nur auf Remotes.SkillFXPlay.
--
-- Davor, ganz am Anfang: LanguageController. Er legt die Sprache fest, bevor
-- irgendein Text gebaut wird (er braucht ClientState erst, wenn es dort
-- Daten gibt — onChanged meldet den aktuellen Stand sofort nach).

local Players = game:GetService("Players")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local root = script.Parent

local Controllers = root:WaitForChild("Controllers")
local UI          = root:WaitForChild("UI")

local ClientState        = require(Controllers:WaitForChild("ClientState"))
local LanguageController = require(Controllers:WaitForChild("LanguageController"))
local ResultFeed         = require(Controllers:WaitForChild("ResultFeed"))
local WorldController    = require(Controllers:WaitForChild("WorldController"))
local EggTimerController = require(Controllers:WaitForChild("EggTimerController"))
local SkillFXController  = require(Controllers:WaitForChild("SkillFXController"))
local CombController     = require(Controllers:WaitForChild("CombController"))
local AmbienceController = require(Controllers:WaitForChild("AmbienceController"))
local EventFXController  = require(Controllers:WaitForChild("EventFXController"))
local LaidEggMeshController = require(Controllers:WaitForChild("LaidEggMeshController"))
local UiEventLogger      = require(Controllers:WaitForChild("UiEventLogger"))
local GuideController    = require(Controllers:WaitForChild("GuideController"))
local UpgradeHintController = require(Controllers:WaitForChild("UpgradeHintController"))
local IncubatorController   = require(Controllers:WaitForChild("IncubatorController"))   -- Sammel-Update 8
local AreaSignController    = require(Controllers:WaitForChild("AreaSignController"))    -- Sammel-Update 3.8

local Toast            = require(UI:WaitForChild("Toast"))
local UiScale          = require(UI:WaitForChild("UiScale"))
local ShopPanel        = require(UI:WaitForChild("ShopPanel"))
local Hud              = require(UI:WaitForChild("Hud"))
local MenuBar          = require(UI:WaitForChild("MenuBar"))
local BaerchiPanel     = require(UI:WaitForChild("BaerchiPanel"))
local BaerchiInventory = require(UI:WaitForChild("BaerchiInventory"))
local HatchPanel       = require(UI:WaitForChild("HatchPanel"))
local CombatPanel      = require(UI:WaitForChild("CombatPanel"))
local BuildingPanel    = require(UI:WaitForChild("BuildingPanel"))
local FusionPanel      = require(UI:WaitForChild("FusionPanel"))
local CharmPanel       = require(UI:WaitForChild("CharmPanel"))
local RebirthDialog    = require(UI:WaitForChild("RebirthDialog"))
local LanguagePanel    = require(UI:WaitForChild("LanguagePanel"))
local PetBar           = require(UI:WaitForChild("PetBar"))
local QuestPanel       = require(UI:WaitForChild("QuestPanel"))
local QuestTracker     = require(UI:WaitForChild("QuestTracker"))
local HudRow           = require(UI:WaitForChild("HudRow"))
local EggTreePanel     = require(UI:WaitForChild("EggTreePanel"))
local LeaderboardPanel = require(UI:WaitForChild("LeaderboardPanel"))
local ProfilePanel     = require(UI:WaitForChild("ProfilePanel"))
local DailyBonusPanel  = require(UI:WaitForChild("DailyBonusPanel"))
local Feedback         = require(UI:WaitForChild("Feedback"))
local Moment           = require(UI:WaitForChild("Moment"))
local ReturnSummary    = require(UI:WaitForChild("ReturnSummary"))
local HomeButton       = require(UI:WaitForChild("HomeButton"))
local RebirthButton    = require(UI:WaitForChild("RebirthButton"))   -- Sammel-Update 2.7
local IncubatorPanel   = require(UI:WaitForChild("IncubatorPanel"))  -- Sammel-Update 8
local CurrencyHint     = require(UI:WaitForChild("CurrencyHint"))    -- Sammel-Update 3.4

--------------------------------------------------------------------------------
-- Oberflaeche
--------------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name             = "RBL"
screenGui.ResetOnSpawn     = false   -- ueberlebt den Tod des Charakters
screenGui.IgnoreGuiInset   = false   -- laesst Platz fuer die Roblox-Topbar
screenGui.ZIndexBehavior   = Enum.ZIndexBehavior.Sibling
screenGui.Parent           = playerGui

-- Playtest 05.10.: auf grossen Monitoren mitwachsen (siehe UI/UiScale)
UiScale.init(screenGui)

--------------------------------------------------------------------------------
-- Start
--------------------------------------------------------------------------------

-- Sprache ALLERERSTES: ab hier liefert Loc den Text in der Roblox-Sprache des
-- Spielers. Ohne das haetten Toast und alle Beschriftungen, die beim Aufbau
-- gesetzt werden, einen Moment lang die Standardsprache.
LanguageController.init()

Toast.init(screenGui)
ClientState.init()

BaerchiPanel.init(screenGui)
BaerchiInventory.init(screenGui)
HatchPanel.init(screenGui)
CombatPanel.init(screenGui)
BuildingPanel.init(screenGui)
FusionPanel.init(screenGui)
-- Nach BaerchiPanel: die Detailkarte oeffnet dieses Panel ueber den
-- PanelManager, es muss dafuer angemeldet sein. Die Reihenfolge der init-Aufrufe
-- entscheidet das zwar nicht (geoeffnet wird erst per Klick), aber die Liste
-- hier soll den Aufrufweg widerspiegeln.
CharmPanel.init(screenGui)
RebirthDialog.init(screenGui)
LanguagePanel.init(screenGui)
QuestPanel.init(screenGui)
-- v14: Ei-Baum (oeffnet sich aus dem Ei-Menue)
EggTreePanel.init(screenGui)
-- v15: Bestenliste, Spieler-Profil (Inspector) und Login-Bonus. Vor MenuBar,
-- damit die Menue-Kacheln die Panels schon angemeldet vorfinden.
LeaderboardPanel.init(screenGui)
ProfilePanel.init(screenGui)
DailyBonusPanel.init(screenGui)
ShopPanel.init(screenGui)          -- HBB Paket 10 (nur mit SHOP_V1)
IncubatorPanel.init(screenGui)     -- Sammel-Update Paket 8

Hud.init(screenGui)
MenuBar.init(screenGui)

-- HBB Paket 1: fliegende Icons, grosse Momente, Rueckkehr-Karte. Nach Hud
-- und MenuBar (Ziele der Icons), vor ResultFeed (der Offline-Bericht des
-- Joins kommt sonst an, bevor die Karte bereit ist).
Feedback.init(screenGui)
Moment.init(screenGui)
ReturnSummary.init(screenGui)
-- HBB Paket 5: Heim-Knopf (erscheint nur weit weg vom eigenen Plot)
HomeButton.init(screenGui)
RebirthButton.init(screenGui)   -- Sammel-Update 2.7: fester Rebirth-Knopf
CurrencyHint.init(screenGui)    -- Sammel-Update 3.4: Waehrungs-Hinweise

-- v13: Quest-Karte links (braucht das Quest-Fenster, das oben angemeldet wird)
QuestTracker.init(screenGui)
-- HUD_ROW_V2: Zahnrad · Quests · Shop in einer Zeile (versteckt die Quest-Karte)
HudRow.init(screenGui)

-- v12: untere Pet-Leiste (Event / Fight), legt auch den PitResumeDialog an
PetBar.init(screenGui)

ResultFeed.init()
WorldController.init()
EggTimerController.init()
IncubatorController.init()   -- Sammel-Update Paket 8
AreaSignController.init()    -- Sammel-Update Paket 3.8
-- v14: Faehigkeiten-Show im PIT (unabhaengig von allem anderen)
SkillFXController.init()
-- v15: Waben im Event-Pit und Recycler (braucht Toast, ClientState und die Welt)
CombController.init(screenGui)
-- v16: Himmels-Kulisse (Wolken, Schwebeinseln, Pollen, Schaum) nur auf dem Client
AmbienceController.init()
-- v17: lebendige Events (UFO-Patrouille, Abwuerfe, Boss, Telegraphen); braucht Toast
EventFXController.init()
-- v18: Ei-Mesh der gelegten Eier (EditableMesh gibt es nur auf dem Client)
LaidEggMeshController.init()
-- HBB Paket 0: Messpunkte der Oberflaeche (Panel auf/zu, Stillstand)
UiEventLogger.init()
-- HBB Paket 2: Fuehrung ohne Text (braucht MenuBar und PetBar als Anker)
GuideController.init(screenGui)
-- HBB Paket 3: ⬆ ueber bezahlbaren eigenen Gebaeuden
UpgradeHintController.init()

print("[Client] Bereit")
