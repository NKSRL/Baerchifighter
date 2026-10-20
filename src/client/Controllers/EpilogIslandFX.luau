--!strict
-- EpilogIslandFX.luau
-- StarterPlayerScripts/Controllers/EpilogIslandFX.luau
--
-- Einzige Zustaendigkeit (Prompt 3 von 7, Final-Epilog):
--   - Die Deko der schwebenden Insel (Kristalle, Buesche; Tag `EpilogDeco`) wippt
--     sanft: +-ISLAND.bobHeight Studs, ISLAND.bobPeriod Sekunden. Rein visuell,
--     lokal — der Server aendert nichts, die Kollision bleibt fest (die Deko
--     kollidiert ohnehin nicht).
--
-- Gewippt wird erst, wenn das Insel-Modell `Revealed` = true meldet (nach der
-- Enthuellung) und nur solange es besteht. Beim Abbau (`Revealed` = false) steht
-- die Deko wieder an ihrem Platz. Keine Schleife pro Frame: ein Tween pro Teil.
--
-- Mit FeatureFlags.FINAL_EPILOG = false baut der Server nichts — dann gibt es
-- auch nichts zu wippen.

local CollectionService = game:GetService("CollectionService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EpilogConfig = require(ReplicatedStorage.Config.EpilogConfig)

local EpilogIslandFX = {}

local TAG = "EpilogDeco"

type Bob = {
	tween : Tween,
	base  : CFrame,
}

local _bobs: { [BasePart]: Bob } = {}
local _conns: { [BasePart]: { RBXScriptConnection } } = {}

local function stop(part: BasePart)
	local bob = _bobs[part]
	if not bob then return end
	_bobs[part] = nil
	bob.tween:Cancel()
	if part.Parent ~= nil then
		part.CFrame = bob.base
	end
end

local function start(part: BasePart)
	if _bobs[part] then return end
	local I = EpilogConfig.ISLAND
	local base = part.CFrame
	-- Phase je Teil verschieden (aus dem Namen), damit nicht alles im Gleichtakt wippt
	local phase = 0
	for i = 1, #part.Name do phase += string.byte(part.Name, i) end
	local delay = (phase % 10) / 10 * I.bobPeriod / 2

	part.CFrame = base - Vector3.new(0, I.bobHeight, 0)
	local tween = TweenService:Create(part,
		TweenInfo.new(I.bobPeriod / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, delay),
		{ CFrame = base + Vector3.new(0, I.bobHeight, 0) })
	_bobs[part] = { tween = tween, base = base }
	tween:Play()
end

local function refresh(part: BasePart)
	local insel = part:FindFirstAncestor("Insel")
	if insel and insel:GetAttribute("Revealed") == true then
		start(part)
	else
		stop(part)
	end
end

local function forget(part: BasePart)
	stop(part)
	local list = _conns[part]
	if list then
		for _, conn in list do conn:Disconnect() end
		_conns[part] = nil
	end
end

local function onAdded(instance: Instance)
	if not instance:IsA("BasePart") then return end
	local part = instance
	if _conns[part] then return end
	local conns: { RBXScriptConnection } = {}
	_conns[part] = conns

	local function watchIsland()
		local insel = part:FindFirstAncestor("Insel")
		if insel then
			table.insert(conns, insel:GetAttributeChangedSignal("Revealed"):Connect(function() refresh(part) end))
		end
	end
	watchIsland()
	table.insert(conns, part.AncestryChanged:Connect(function(_, parent)
		if parent == nil then forget(part) end
	end))
	refresh(part)
end

function EpilogIslandFX.init()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(onAdded)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(instance)
		if instance:IsA("BasePart") then forget(instance) end
	end)
	for _, instance in CollectionService:GetTagged(TAG) do
		onAdded(instance)
	end
end

return EpilogIslandFX
