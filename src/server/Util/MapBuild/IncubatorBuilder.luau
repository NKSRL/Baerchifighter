--!strict
-- IncubatorBuilder.luau
-- ServerScriptService/Util/MapBuild/IncubatorBuilder.luau
--
-- Einzige Zustaendigkeit:
--   - Den Inkubator auf dem Plot bauen (Sockel + Glaskuppeln) und den Stand
--     jeder Kuppel schreiben: der eingesetzte Baerchi steht verkleinert unter
--     seiner Kuppel, ein Ei daneben zeigt, dass Eier warten (Umbau nach
--     Rueckmeldung 05.10.).
--
-- Kontext: Sammel-Update 05.10., Paket 8. Teil von MapService, nur MapService
-- benutzt dieses Modul; es aendert keine Spielerdaten.
--
-- Teile-Budget (IncubatorConfig.PART_BUDGET = 20): Sockel 1 + Zierleiste 1 +
-- je Kuppel Polster, Glas, Ei (3 x 6), dazu je belegtem Platz die Figur
-- ("Figure_<n>", BaerchiMesh, verkleinert). Fortschritt, Chancen und
-- Leuchten macht der Client (IncubatorController) aus den Attributen.
--
-- Die Kuppeln heissen "Dome_<n>" und tragen die Attribute:
--   Slot (n), Unlocked (Platz verfuegbar), BaerchiUid ("" = leer),
--   LastEggAt (os.time), Interval (Sekunden pro Ei), Eggs (wartende Eier).

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types           = require(ReplicatedStorage.Network.Types)
local EggConfig       = require(ReplicatedStorage.Config.EggConfig)
local BaerchiConfig   = require(ReplicatedStorage.Config.BaerchiConfig)
local BaerchiMesh     = require(ReplicatedStorage.Modules.BaerchiMesh)
local IncubatorConfig = require(ReplicatedStorage.Config.IncubatorConfig)
local IncubatorRules  = require(ReplicatedStorage.Modules.IncubatorRules)

local MapParts = require(ServerScriptService.Util.MapBuild.MapParts)

local IncubatorBuilder = {}

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))   -- Zylinder stehend

-- Mitte der Kuppel `index` relativ zum Sockel (2 Reihen x 3 Spalten).
local function domeOffset(index: number): Vector3
	local look = IncubatorConfig.LOOK
	local cols = look.columns
	local col = (index - 1) % cols
	local row = math.floor((index - 1) / cols)
	local rows = math.ceil(IncubatorConfig.MAX_SLOTS / cols)
	return Vector3.new(
		(col - (cols - 1) * 0.5) * look.spacing.X,
		0,
		(row - (rows - 1) * 0.5) * look.spacing.Z
	)
end

-- Stellt die verkleinerte Figur des Baerchis unter die Kuppel (oder raeumt
-- sie weg). Neu gebaut wird nur, wenn ein anderer Baerchi im Platz sitzt.
local function placeFigure(model: Model, index: number, baerchi: Types.Baerchi?)
	local name = "Figure_" .. index
	local old = model:FindFirstChild(name)
	if old and baerchi and old:GetAttribute("BaerchiUid") == baerchi.uid then return end
	if old then old:Destroy() end
	if not baerchi then return end

	local pad = model:FindFirstChild("Pad_" .. index)
	if not (pad and pad:IsA("BasePart")) then return end
	local look = IncubatorConfig.LOOK
	local foot = pad.Position + Vector3.new(0, pad.Size.X * 0.5, 0)
	local figure = BaerchiMesh.build(foot, BaerchiConfig.getRarityColor(baerchi.rarity), baerchi.rarity,
		if baerchi.mutation then BaerchiConfig.getMutationColor(baerchi.mutation) else nil)
	if not figure then return end

	-- Auf Kuppel-Hoehe verkleinern und wieder auf das Polster stellen
	local bottom, top = BaerchiMesh.worldBoundsY(figure)
	local height = if bottom and top then top - bottom else 0
	if height > 0 then
		figure:ScaleTo(figure:GetScale() * (look.figureHeight / height))
	end
	local base = model.PrimaryPart
	local rotation = if base then base.CFrame.Rotation else CFrame.identity
	figure:PivotTo(CFrame.new(figure:GetPivot().Position) * rotation)
	local newBottom = BaerchiMesh.worldBottomY(figure)
	local box = figure:GetBoundingBox()
	if newBottom then
		figure:PivotTo(figure:GetPivot() + (foot - Vector3.new(box.Position.X, newBottom, box.Position.Z)))
	end
	for _, part in figure:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	figure.Name = name
	figure:SetAttribute("BaerchiUid", baerchi.uid)
	figure.Parent = model
end

-- Schreibt den Stand aller Kuppeln (billig, laeuft bei jeder Aenderung).
function IncubatorBuilder.writeState(model: Model, island: Types.IslandData, slotCount: number)
	local look = IncubatorConfig.LOOK
	local incubator = island.incubator
	model:SetAttribute("Level", incubator.level)
	model:SetAttribute("SlotCount", slotCount)
	for index = 1, IncubatorConfig.MAX_SLOTS do
		local dome = model:FindFirstChild("Dome_" .. index)
		if not (dome and dome:IsA("BasePart")) then continue end
		local entry = IncubatorRules.findSlot(incubator.slots, index)
		local baerchi = if entry then island.baerchis[entry.baerchiUid] else nil
		local unlocked = index <= slotCount
		dome:SetAttribute("Unlocked", unlocked)
		dome:SetAttribute("BaerchiUid", if entry and baerchi then entry.baerchiUid else "")
		dome:SetAttribute("LastEggAt", if entry then entry.lastEggAt else 0)
		dome:SetAttribute("Interval", if baerchi then IncubatorRules.breedSeconds(baerchi.rarity, incubator.level) else 0)
		dome:SetAttribute("Eggs", if entry then #entry.eggs else 0)
		dome.Transparency = if unlocked or entry then look.domeTransparency else look.lockedTransparency
		dome.Color = if baerchi then BaerchiConfig.getRarityColor(baerchi.rarity):Lerp(look.domeColor, 0.55) else look.domeColor

		placeFigure(model, index, baerchi)

		-- Ein Ei neben der Figur: hier warten Eier zum Abholen
		local egg = model:FindFirstChild("Egg_" .. index)
		if egg and egg:IsA("BasePart") then
			local last = if entry and #entry.eggs > 0 then entry.eggs[#entry.eggs] else nil
			local def = if last then EggConfig.data[last] else nil
			egg.Transparency = if def then 0 else 1
			if def then egg.Color = def.color end
		end
	end
end

-- Baut den Inkubator neu (ein alter wird ersetzt).
function IncubatorBuilder.build(plotModel: Model, slot: number, island: Types.IslandData, slotCount: number): Model
	local old = plotModel:FindFirstChild(IncubatorConfig.MODEL_NAME)
	if old then old:Destroy() end

	local look = IncubatorConfig.LOOK
	local model = Instance.new("Model")
	model.Name = IncubatorConfig.MODEL_NAME

	local ground = MapParts.plotCFrame(slot)
		* CFrame.new(look.offset.X, MapParts.plotSurfaceOffset() + look.offset.Y, look.offset.Z)

	local base = MapParts.newPart("Base", look.baseSize, ground * CFrame.new(0, look.baseSize.Y * 0.5, 0),
		look.baseColor, Enum.Material.SmoothPlastic)
	base.Parent = model
	model.PrimaryPart = base

	local trim = MapParts.newPart("Trim",
		Vector3.new(look.baseSize.X + 0.6, 0.3, look.baseSize.Z + 0.6),
		ground * CFrame.new(0, 0.15, 0), look.trimColor, Enum.Material.Neon)
	trim.CanCollide = false
	trim.Parent = model

	local top = look.baseSize.Y
	for index = 1, IncubatorConfig.MAX_SLOTS do
		local at = ground * CFrame.new(domeOffset(index))

		local pad = MapParts.newPart("Pad_" .. index, look.padSize,
			at * CFrame.new(0, top + look.padSize.X * 0.5, 0) * UPRIGHT, look.padColor, Enum.Material.SmoothPlastic)
		pad.Shape = Enum.PartType.Cylinder
		pad.CanCollide = false
		pad.Parent = model

		local padTop = top + look.padSize.X
		local egg = MapParts.newPart("Egg_" .. index, look.eggSize,
			at * CFrame.new(look.eggOffset.X, padTop + look.eggSize.Y * 0.5, look.eggOffset.Z), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
		egg.Shape = Enum.PartType.Ball
		egg.CanCollide = false
		egg.Transparency = 1
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = egg
		egg.Parent = model

		local dome = MapParts.newPart("Dome_" .. index, look.domeSize,
			at * CFrame.new(0, padTop + look.domeSize.Y * 0.35, 0), look.domeColor, Enum.Material.Glass)
		dome.Shape = Enum.PartType.Ball
		dome.CanCollide = false
		dome:SetAttribute("Slot", index)
		dome.Parent = model
	end

	model.Parent = plotModel
	IncubatorBuilder.writeState(model, island, slotCount)
	return model
end

return IncubatorBuilder
