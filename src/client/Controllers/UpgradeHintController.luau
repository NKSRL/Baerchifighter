--!strict
-- UpgradeHintController.luau
-- StarterPlayerScripts/Controllers/UpgradeHintController.luau
--
-- Einzige Zustaendigkeit:
--   - Ueber eigenen Gebaeuden ein kleines ⬆ zeigen, wenn der naechste Ausbau
--     gerade bezahlbar ist
--
-- Kontext: HBB Paket 3. Der Ausbau soll in der Welt auffallen, nicht in
-- einem Menue. Nur Client, berechnet aus dem Datenstand und
-- EconomyConfig.HONEY_UPGRADE_COSTS — kein Remote, keine Wahrheit: ob der
-- Ausbau klappt, entscheidet weiterhin der Server beim Klick.
--
-- Die Gebaeude-Koerper erkennt dieses Modul wie WorldController: Attribut
-- "BuildingLevel" am Teil, Besitzer ueber "PlotOwner" an einem Vorfahren,
-- Name = BuildingId.
--
-- Mit FeatureFlags.UI_V2_PROGRESSIVE = false zeigt dieses Modul nichts.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local EconomyConfig = require(ReplicatedStorage.Config.EconomyConfig)
local FeatureFlags  = require(ReplicatedStorage.Config.FeatureFlags)

local ClientState = require(script.Parent.ClientState)
local Theme       = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("Theme"))

local UpgradeHintController = {}

local LEVEL_ATTRIBUTE = "BuildingLevel"
local OWNER_ATTRIBUTE = "PlotOwner"
local TICK_SECONDS    = 1
local ARROW_COLOR     = Color3.fromRGB(110, 240, 120)

-- [Gebaeude-Teil] = Billboard
local _hints: { [BasePart]: BillboardGui } = {}

local function ownerOf(instance: Instance): number?
	local current: Instance? = instance
	while current do
		local owner = current:GetAttribute(OWNER_ATTRIBUTE)
		if typeof(owner) == "number" then return owner end
		current = current.Parent
	end
	return nil
end

local function ownBuildings(): { BasePart }
	local list: { BasePart } = {}
	local me = Players.LocalPlayer.UserId
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("BasePart") and typeof(descendant:GetAttribute(LEVEL_ATTRIBUTE)) == "number"
			and ownerOf(descendant) == me then
			table.insert(list, descendant)
		end
	end
	return list
end

local function hintFor(part: BasePart): BillboardGui
	local existing = _hints[part]
	if existing and existing.Parent then return existing end
	local gui = Instance.new("BillboardGui")
	gui.Name = "UpgradeHint"
	gui.Size = UDim2.fromOffset(46, 46)
	gui.StudsOffset = Vector3.new(0, part.Size.Y * 0.5 + 6, 0)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = part
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local label = Theme.label("Arrow", gui, "⬆")
	label.Size = UDim2.fromScale(1, 1)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextColor3 = ARROW_COLOR
	Theme.outlineText(label, 3)
	_hints[part] = gui
	return gui
end

local function tick()
	local data = ClientState.get()
	local active = FeatureFlags.isOn("UI_V2_PROGRESSIVE") and data ~= nil
	local seen: { [BasePart]: boolean } = {}

	if active and data then
		for _, part in ownBuildings() do
			local level = part:GetAttribute(LEVEL_ATTRIBUTE) :: number
			local cost = EconomyConfig.HONEY_UPGRADE_COSTS[level + 1]
			local affordable = cost ~= nil and level < EconomyConfig.MAX_BUILDING_LEVEL
				and data.gummies >= cost.gummies and data.goldGummies >= cost.goldGummies
			local gui = hintFor(part)
			gui.Enabled = affordable
			seen[part] = true
		end
	end

	-- Abgerissene oder neu gebaute Gebaeude: alte Schilder weg
	for part, gui in _hints do
		if not seen[part] or not part.Parent then
			gui:Destroy()
			_hints[part] = nil
		end
	end
end

function UpgradeHintController.init()
	task.spawn(function()
		while true do
			tick()
			task.wait(TICK_SECONDS)
		end
	end)
end

return UpgradeHintController
