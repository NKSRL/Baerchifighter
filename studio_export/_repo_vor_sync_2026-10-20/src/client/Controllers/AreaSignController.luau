--!strict
-- AreaSignController.luau
-- StarterPlayerScripts/Controllers/AreaSignController.luau
--
-- Einzige Zustaendigkeit:
--   - Grosse Bereichs-Schilder in der Welt (Sammel-Update 05.10., Paket 3.8):
--     zwei Woerter, was ein Bereich macht ("Waben-Feld", "Ei-Haendler", ...).
--
-- Rein clientseitig: ein BillboardGui pro Bereich, an ein schon vorhandenes
-- Teil gehaengt (Adornee) und in PlayerGui abgelegt — KEIN neues Teil in der
-- Welt, also nichts am Teile-Budget. Weil jeder Client sein eigenes Schild
-- baut, steht es in SEINER Sprache (Schluessel "area.<id>").
--
-- Plot-Schilder (Honig-Teich, Recycler, Inkubator, Arena) nur am eigenen Plot
-- — fremde Plots sind nicht das, was ein neuer Spieler verstehen muss.
--
-- Mit FeatureFlags.AREA_SIGNS = false baut dieses Modul nichts.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local Loc          = require(ReplicatedStorage.Localization.Loc)
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)

local AreaSignController = {}

local OWNER_ATTRIBUTE = "PlotOwner"
local SIGN_DISTANCE   = 220
local TEXT_COLOR      = Color3.fromRGB(255, 236, 170)

-- Teil-Name -> { Schluessel, nur eigener Plot?, Hoehe ueber dem Teil }
type SignDef = { key: string, own: boolean, lift: number, size: Vector2 }
local SIGNS: { [string]: SignDef } = {
	EventFloor = { key = "area.pit",       own = false, lift = 26, size = Vector2.new(22, 5) },
	Counter    = { key = "area.merchant",  own = false, lift = 11, size = Vector2.new(14, 3.4) },
	LiveBoard  = { key = "area.live",      own = false, lift = 12, size = Vector2.new(14, 3.4) },
	HoneyPond  = { key = "area.pond",      own = true,  lift = 14, size = Vector2.new(14, 3.4) },
	Recycler   = { key = "area.recycler",  own = true,  lift = 12, size = Vector2.new(14, 3.4) },
	Base       = { key = "area.incubator", own = true,  lift = 9,  size = Vector2.new(14, 3.4) },
	FightFloor = { key = "area.arena",     own = true,  lift = 16, size = Vector2.new(16, 3.8) },
}

local _container: Folder? = nil
local _signs: { [BasePart]: TextLabel } = {}

local function ownerOf(instance: Instance): number?
	local current: Instance? = instance
	while current do
		local owner = current:GetAttribute(OWNER_ATTRIBUTE)
		if typeof(owner) == "number" then return owner end
		current = current.Parent
	end
	return nil
end

local function matches(part: BasePart, def: SignDef): boolean
	-- "Counter" gibt es nur am Haendler, "Base" nur am Inkubator: Eltern pruefen
	if part.Name == "Counter" and (not part.Parent or part.Parent.Name ~= "EggMerchant") then return false end
	if part.Name == "Base" and (not part.Parent or part.Parent.Name ~= "Incubator") then return false end
	local owner = ownerOf(part)
	if def.own then
		return owner == Players.LocalPlayer.UserId
	end
	return true
end

local function attach(part: BasePart)
	local def = SIGNS[part.Name]
	local container = _container
	if not def or not container or _signs[part] or not matches(part, def) then return end

	local gui = Instance.new("BillboardGui")
	gui.Name = "AreaSign_" .. part.Name
	gui.Adornee = part
	gui.Size = UDim2.fromScale(def.size.X, def.size.Y)
	gui.StudsOffsetWorldSpace = Vector3.new(0, def.lift, 0)
	gui.MaxDistance = SIGN_DISTANCE
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Parent = container

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = TEXT_COLOR
	label.TextStrokeTransparency = 0
	label.TextStrokeColor3 = Color3.fromRGB(40, 28, 20)
	label.Text = Loc.t(def.key)
	label:SetAttribute("Key", def.key)
	label.Parent = gui

	_signs[part] = label
	part.AncestryChanged:Connect(function()
		if part.Parent == nil then
			_signs[part] = nil
			gui:Destroy()
		end
	end)
end

local function hook(instance: Instance)
	if instance:IsA("BasePart") and SIGNS[instance.Name] then
		-- Plot-Attribute und Eltern stehen beim Einhaengen evtl. noch nicht
		task.defer(attach, instance)
	end
end

function AreaSignController.init()
	if not FeatureFlags.isOn("AREA_SIGNS") then return end
	local folder = Instance.new("Folder")
	folder.Name = "AreaSigns"
	folder.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	_container = folder

	for _, descendant in Workspace:GetDescendants() do
		hook(descendant)
	end
	Workspace.DescendantAdded:Connect(hook)

	Loc.onChanged(function()
		for _, label in _signs do
			local key = label:GetAttribute("Key")
			if typeof(key) == "string" then label.Text = Loc.t(key) end
		end
	end)
end

return AreaSignController
