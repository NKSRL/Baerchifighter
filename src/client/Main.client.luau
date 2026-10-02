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

local Players = game:GetService("Players")

local player    = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local root = script.Parent

local Controllers = root:WaitForChild("Controllers")
local UI          = root:WaitForChild("UI")

local ClientState        = require(Controllers:WaitForChild("ClientState"))
local ResultFeed         = require(Controllers:WaitForChild("ResultFeed"))
local WorldController    = require(Controllers:WaitForChild("WorldController"))
local EggTimerController = require(Controllers:WaitForChild("EggTimerController"))

local Toast            = require(UI:WaitForChild("Toast"))
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

--------------------------------------------------------------------------------
-- Oberflaeche
--------------------------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name             = "RBL"
screenGui.ResetOnSpawn     = false   -- ueberlebt den Tod des Charakters
screenGui.IgnoreGuiInset   = false   -- laesst Platz fuer die Roblox-Topbar
screenGui.ZIndexBehavior   = Enum.ZIndexBehavior.Sibling
screenGui.Parent           = playerGui

--------------------------------------------------------------------------------
-- Start
--------------------------------------------------------------------------------

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

Hud.init(screenGui)
MenuBar.init(screenGui)

ResultFeed.init()
WorldController.init()
EggTimerController.init()

print("[Client] Bereit")
