--!strict
-- IncubatorBuilder.luau
-- ServerScriptService/Util/MapBuild/IncubatorBuilder.luau
--
-- Einzige Zustaendigkeit:
--   - Den Solo-Inkubator auf dem Plot bauen (Teile der Stufe aus
--     Config/IncubatorModels) und seinen Stand als Attribute schreiben
--     (Baerchi, Takt, Lager).
--
-- Kontext: Teil von MapService, nur MapService benutzt dieses Modul; es aendert
-- keine Spielerdaten. Die Stufe bestimmt das Modell: wechselt sie, wird neu
-- gebaut (needsRebuild); sonst schreibt writeState nur Attribute und setzt
-- bei Bedarf die Baerchi-Figur um.
--
-- Teile-Budget (IncubatorConfig.PART_BUDGET = 20): die Teile der Stufe. Die
-- Figur des Baerchis zaehlt nicht dazu (wie die Plot-Figuren).
--
-- Attribute am Model "Incubator": Level, SlotCount (1), Stored, Capacity.
-- Attribute an der Kuppel "Dome_1": Slot (1), Unlocked (true), Level, Stored,
-- Capacity, BreederUid ("" = leer), LastEggAt, BreedSeconds.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types           = require(ReplicatedStorage.Network.Types)
local IncubatorConfig = require(ReplicatedStorage.Config.IncubatorConfig)
local IncubatorModels = require(ReplicatedStorage.Config.IncubatorModels)
local IncubatorRules  = require(ReplicatedStorage.Modules.IncubatorRules)
local BaerchiConfig   = require(ReplicatedStorage.Config.BaerchiConfig)
local BaerchiMesh     = require(ReplicatedStorage.Modules.BaerchiMesh)

local MapParts = require(ServerScriptService.Util.MapBuild.MapParts)

local IncubatorBuilder = {}

local SLOT = 1

-- Kleine Figur des Baerchis in der Kuppel, auf der Standflaeche. Wird nur neu
-- gebaut, wenn ein anderer Baerchi sitzt (Attribut "Uid").
local function placeBreederFigure(model: Model, baerchi: Types.Baerchi?)
	local name = "Breeder_" .. SLOT
	local old = model:FindFirstChild(name)
	if old and baerchi and old:GetAttribute("Uid") == baerchi.uid then return end
	if old then old:Destroy() end
	if not baerchi then return end

	local pad = model:FindFirstChild("Pad_" .. SLOT)
	if not (pad and pad:IsA("BasePart")) then return end
	-- Standflaeche: stehender Zylinder, Dicke = size.X
	local foot = pad.Position + Vector3.new(0, pad.Size.X * 0.5, 0)
	local mutationColor = if baerchi.mutation then BaerchiConfig.getMutationColor(baerchi.mutation) else nil
	local ok, figure = pcall(BaerchiMesh.buildFor, baerchi.configId, foot, BaerchiConfig.getRarityColor(baerchi.rarity), baerchi.rarity, mutationColor, baerchi.configId)
	if not ok or not figure then return end

	-- Auf Kuppel-Groesse bringen, dann wieder auf die Standflaeche stellen.
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

-- Bilder auf ein Teil legen: Decal oder gekachelte Texture je Seite, Aufkleber als SurfaceGui,
-- Funkeln (Sparkle) als Partikel auf der Standflaeche.
local function dress(part: BasePart, piece: IncubatorModels.Piece)
	for _, deco in piece.decals or {} do
		local image: Decal
		if deco.tile then
			local texture = Instance.new("Texture")
			texture.StudsPerTileU = deco.tile.X
			texture.StudsPerTileV = deco.tile.Y
			image = texture
		else
			image = Instance.new("Decal")
		end
		image.Texture = "rbxassetid://" .. deco.id
		image.Face = deco.face
		if deco.color then image.Color3 = deco.color end
		image.Parent = part
	end
	if piece.sticker then
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 100
		gui.LightInfluence = 0.3
		gui.Parent = part
		local label = Instance.new("ImageLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Image = piece.sticker
		label.Parent = gui
	end
	if piece.name == "Pad_1" then
		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Texture = "rbxassetid://" .. IncubatorModels.IMAGES.Sparkle
		sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 226, 120))
		sparkle.LightEmission = 1
		sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.7), NumberSequenceKeypoint.new(1, 0) })
		sparkle.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.1), NumberSequenceKeypoint.new(1, 1) })
		sparkle.Lifetime = NumberRange.new(1.5, 2.5)
		sparkle.Rate = 3
		sparkle.Speed = NumberRange.new(0.4, 0.9)
		sparkle.SpreadAngle = Vector2.new(35, 35)
		sparkle.EmissionDirection = Enum.NormalId.Right
		sparkle.Rotation = NumberRange.new(0, 360)
		sparkle.Parent = part
	end
end

-- Passt das gebaute Modell noch zur Stufe?
function IncubatorBuilder.needsRebuild(model: Model, incubator: Types.IncubatorData): boolean
	return model:GetAttribute("Level") ~= IncubatorRules.levelOf(incubator)
end

-- Schreibt den Stand (billig, laeuft bei jeder Aenderung).
function IncubatorBuilder.writeState(model: Model, incubator: Types.IncubatorData, slotCount: number,
	baerchis: { [string]: Types.Baerchi }?)
	local level = IncubatorRules.levelOf(incubator)
	local stored = IncubatorRules.storedTotal(incubator)
	local capacity = IncubatorRules.capacity(level)
	model:SetAttribute("Level", level)
	model:SetAttribute("SlotCount", slotCount)
	model:SetAttribute("Stored", stored)
	model:SetAttribute("Capacity", capacity)

	local dome = model:FindFirstChild("Dome_" .. SLOT)
	if not (dome and dome:IsA("BasePart")) then return end
	local breeder = IncubatorRules.findBreeder(incubator.breeders, SLOT)
	local baerchi = if breeder and baerchis then baerchis[breeder.uid] else nil
	dome:SetAttribute("Slot", SLOT)
	dome:SetAttribute("Unlocked", true)
	dome:SetAttribute("Level", level)
	dome:SetAttribute("Stored", stored)
	dome:SetAttribute("Capacity", capacity)
	dome:SetAttribute("BreederUid", if baerchi then baerchi.uid else "")
	dome:SetAttribute("LastEggAt", if breeder then breeder.lastEggAt else 0)
	dome:SetAttribute("BreedSeconds", if baerchi then IncubatorRules.breedSeconds(baerchi.rarity, level) else 0)
	placeBreederFigure(model, baerchi)
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

	for _, piece in IncubatorModels.LEVELS[IncubatorRules.levelOf(incubator)] do
		local cframe = ground * CFrame.new(piece.offset)
		if piece.rotation then
			cframe = cframe * CFrame.Angles(math.rad(piece.rotation.X), math.rad(piece.rotation.Y), math.rad(piece.rotation.Z))
		end
		local part = MapParts.newPart(piece.name, piece.size, cframe, piece.color, piece.material)
		part.Shape = piece.shape
		part.CanCollide = piece.solid == true
		part.CanQuery = piece.name == "Base" or piece.name == "Dome_1"
		part.CanTouch = false
		if piece.transparency then part.Transparency = piece.transparency end
		dress(part, piece)
		part.Parent = model
		if piece.name == "Base" then model.PrimaryPart = part end
	end

	model.Parent = plotModel
	IncubatorBuilder.writeState(model, incubator, slotCount, baerchis)
	return model
end

return IncubatorBuilder
