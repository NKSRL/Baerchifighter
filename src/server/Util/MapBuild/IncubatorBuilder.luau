--!strict
-- IncubatorBuilder.luau
-- ServerScriptService/Util/MapBuild/IncubatorBuilder.luau
--
-- Einzige Zustaendigkeit:
--   - Den Inkubator auf dem Plot bauen (Sockel + Glaskuppeln) und den Stand
--     jeder Kuppel schreiben (Ei sichtbar, Zeitmarken als Attribute).
--
-- Kontext: Sammel-Update 05.10., Paket 8. Teil von MapService, nur MapService
-- benutzt dieses Modul; es aendert keine Spielerdaten.
--
-- Teile-Budget (IncubatorConfig.PART_BUDGET = 20): Sockel 1 + Zierleiste 1 +
-- je Kuppel Polster, Glas, Ei (3 x 6). Fortschrittsbalken und Leuchten macht
-- der Client (IncubatorController) aus den Attributen StartedAt/FinishAt —
-- ohne Server-Takt pro Ei.
--
-- Die Kuppeln heissen "Dome_<n>" und tragen die Attribute:
--   Slot (n), Unlocked (Platz verfuegbar), EggType ("" = leer),
--   StartedAt, FinishAt (os.time, 0 = leer).

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types           = require(ReplicatedStorage.Network.Types)
local EggConfig       = require(ReplicatedStorage.Config.EggConfig)
local IncubatorConfig = require(ReplicatedStorage.Config.IncubatorConfig)
local IncubatorRules  = require(ReplicatedStorage.Modules.IncubatorRules)
local BaerchiConfig   = require(ReplicatedStorage.Config.BaerchiConfig)
local BaerchiMesh     = require(ReplicatedStorage.Modules.BaerchiMesh)
local FeatureFlags    = require(ReplicatedStorage.Config.FeatureFlags)

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

-- INCUBATOR_BREED: kleine Figur des Baerchis in der Kuppel. Wird nur neu
-- gebaut, wenn ein anderer Baerchi im Platz sitzt (Attribut "Uid"). Die Teile
-- der Figur zaehlen nicht zum PART_BUDGET des Sockels (wie die Plot-Figuren).
local function placeBreederFigure(model: Model, index: number, baerchi: Types.Baerchi?)
	local name = "Breeder_" .. index
	local old = model:FindFirstChild(name)
	if old and baerchi and old:GetAttribute("Uid") == baerchi.uid then return end
	if old then old:Destroy() end
	if not baerchi then return end

	local pad = model:FindFirstChild("Pad_" .. index)
	if not (pad and pad:IsA("BasePart")) then return end
	local look = IncubatorConfig.LOOK
	local foot = pad.Position + Vector3.new(0, look.padSize.X * 0.5, 0)
	local mutationColor = if baerchi.mutation then BaerchiConfig.getMutationColor(baerchi.mutation) else nil
	local ok, figure = pcall(BaerchiMesh.build, foot, BaerchiConfig.getRarityColor(baerchi.rarity), baerchi.rarity, mutationColor)
	if not ok or not figure then return end

	-- Auf Kuppel-Groesse schrumpfen, dann wieder auf das Polster stellen.
	local height = BaerchiMesh.getHeight(figure)
	if height > 0 then
		figure:ScaleTo(figure:GetScale() * IncubatorConfig.BREED_FIGURE_HEIGHT / height)
	end
	local bottom = BaerchiMesh.worldBottomY(figure)
	if bottom then
		figure:PivotTo(figure:GetPivot() + Vector3.new(0, foot.Y - bottom, 0))
	end
	for _, part in figure:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
		end
	end
	figure.Name = name
	figure:SetAttribute("Uid", baerchi.uid)
	figure.Parent = model
end

-- Schreibt den Stand aller Kuppeln (billig, laeuft bei jeder Aenderung).
function IncubatorBuilder.writeState(model: Model, incubator: Types.IncubatorData, slotCount: number,
	baerchis: { [string]: Types.Baerchi }?)
	local breed = FeatureFlags.isOn("INCUBATOR_BREED")
	local look = IncubatorConfig.LOOK
	model:SetAttribute("Level", incubator.level)
	model:SetAttribute("SlotCount", slotCount)
	for index = 1, IncubatorConfig.MAX_SLOTS do
		local dome = model:FindFirstChild("Dome_" .. index)
		if not (dome and dome:IsA("BasePart")) then continue end
		local entry = IncubatorRules.findSlot(incubator.slots, index)
		local unlocked = index <= slotCount
		dome:SetAttribute("Unlocked", unlocked)
		dome:SetAttribute("EggType", if entry then entry.eggType else "")
		dome:SetAttribute("StartedAt", if entry then entry.startedAt else 0)
		dome:SetAttribute("FinishAt", if entry then entry.finishAt else 0)
		dome.Transparency = if unlocked or entry then look.domeTransparency else look.lockedTransparency

		local egg = model:FindFirstChild("Egg_" .. index)
		if egg and egg:IsA("BasePart") then
			local def = if entry then EggConfig.data[entry.eggType] else nil
			egg.Transparency = if def then 0 else 1
			if def then egg.Color = def.color end
		end

		-- INCUBATOR_BREED: Baerchi im Platz. Attribute fuer die Anzeige
		-- (IncubatorController): BreederUid, LastEggAt, BreedSeconds.
		local breeder = if breed then IncubatorRules.findBreeder(incubator.breeders, index) else nil
		local baerchi = if breeder and baerchis then baerchis[breeder.uid] else nil
		dome:SetAttribute("BreederUid", if baerchi then baerchi.uid else "")
		dome:SetAttribute("LastEggAt", if breeder then breeder.lastEggAt else 0)
		dome:SetAttribute("BreedSeconds", if baerchi then IncubatorRules.breedSeconds(baerchi.rarity, incubator.level) else 0)
		if baerchi then
			dome.Transparency = look.domeTransparency
		end
		placeBreederFigure(model, index, baerchi)
	end
end

-- Baut den Inkubator neu (ein alter wird ersetzt).
function IncubatorBuilder.build(plotModel: Model, slot: number, incubator: Types.IncubatorData, slotCount: number,
	baerchis: { [string]: Types.Baerchi }?): Model
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
			at * CFrame.new(0, padTop + look.eggSize.Y * 0.5, 0), Color3.new(1, 1, 1), Enum.Material.SmoothPlastic)
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
	IncubatorBuilder.writeState(model, incubator, slotCount, baerchis)
	return model
end

return IncubatorBuilder
