--!strict
-- LaidEggMeshController.luau
-- StarterPlayerScripts/Controllers/LaidEggMeshController.luau
--
-- Einzige Zustaendigkeit:
--   - Das Ei-Mesh (EggMesh) auf dem Client ueber jeden gelegten Ei-Koerper legen.
--
-- Der Server baut je Ei einen schlichten Koerper und markiert ihn mit dem Tag
-- "LaidEggBody" (Fallback: Kugel). Ein EditableMesh wird nicht repliziert,
-- darum entsteht das feine Mesh hier: es folgt Groesse und Farbe des Koerpers,
-- der Koerper selbst wird lokal unsichtbar. Gurte, Steine, Beruehren und
-- Beschriftung bleiben beim Server-Koerper.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")

local EggMesh   = require(ReplicatedStorage.Modules.EggMesh)
local EggModels = require(ReplicatedStorage.Modules.EggModels)

local LaidEggMeshController = {}

local TAG = "LaidEggBody"

-- Ein frisch gelegtes Ei macht ganz leicht auf sich aufmerksam: es "poppt" kurz
-- auf (Groesse mit Ueberschwingen) und streut ein paar Funken. Bewusst klein.
local POP_TIME     = 0.45
local POP_START    = 0.35   -- Anfangsgroesse (Anteil)
local SPARK_COUNT  = 6
local SETTLE_TIME  = 4      -- so lange nach dem Start gelten vorhandene Eier als "alt"

local _seen: { [string]: boolean } = {}
local _settled = false

local function popIn(body: BasePart, mesh: MeshPart)
	local full = mesh.Size
	mesh.Size = full * POP_START
	TweenService:Create(mesh, TweenInfo.new(POP_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = full }):Play()

	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture       = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color         = ColorSequence.new(Color3.new(1, 1, 1):Lerp(body.Color, 0.3))
	sparks.Size          = NumberSequence.new(0.3, 0)
	sparks.Lifetime      = NumberRange.new(0.5, 0.9)
	sparks.Speed         = NumberRange.new(2, 4)
	sparks.SpreadAngle   = Vector2.new(180, 180)
	sparks.LightEmission = 1
	sparks.Rate          = 0
	sparks.Parent        = body
	sparks:Emit(SPARK_COUNT)
	task.delay(1.5, function() sparks:Destroy() end)
end

-- 14.10.: Eier mit fertigem Modell (Assets.Eggs). Der Server-Koerper bleibt als
-- unsichtbare Huelle (Touch, Attribut, Beschriftung), das Modell sitzt darauf.
-- Gibt true zurueck, wenn das Modell gesetzt wurde.
local function dressModel(body: BasePart): boolean
	local eggId = body:GetAttribute("EggId")
	if type(eggId) ~= "string" then return false end

	-- Assets koennen beim Beitritt kurz nach den Eiern ankommen: einmal warten.
	if EggModels.has(eggId) and not EggModels.getTemplate(eggId) then
		local assets = ReplicatedStorage:WaitForChild("Assets", 10)
		if assets then assets:WaitForChild("Eggs", 10) end
	end
	local template = EggModels.getTemplate(eggId)
	if not template or not template.PrimaryPart then return false end
	if body:FindFirstChild("EggModel") then return true end

	local model = template:Clone()
	model.Name = "EggModel"
	local baseHeight = (template.PrimaryPart :: BasePart).Size.Y
	EggModels.place(model, baseHeight, body, 1)
	model.Parent = body
	body.Transparency = 1

	local uid = body:GetAttribute("LaidEggUid")
	if type(uid) == "string" then
		local isNew = _settled and not _seen[uid]
		_seen[uid] = true
		if isNew then
			-- Pop wie beim Mesh-Ei: Groesse mit Ueberschwingen, Fuss bleibt am Boden.
			local value = Instance.new("NumberValue")
			value.Value = POP_START
			EggModels.place(model, baseHeight, body, POP_START)
			value.Changed:Connect(function(factor: number)
				if model.Parent then EggModels.place(model, baseHeight, body, factor) end
			end)
			local tween = TweenService:Create(value,
				TweenInfo.new(POP_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Value = 1 })
			tween.Completed:Once(function() value:Destroy() end)
			tween:Play()

			local sparks = Instance.new("ParticleEmitter")
			sparks.Texture       = "rbxasset://textures/particles/sparkles_main.dds"
			sparks.Color         = ColorSequence.new(Color3.new(1, 1, 1))
			sparks.Size          = NumberSequence.new(0.3, 0)
			sparks.Lifetime      = NumberRange.new(0.5, 0.9)
			sparks.Speed         = NumberRange.new(2, 4)
			sparks.SpreadAngle   = Vector2.new(180, 180)
			sparks.LightEmission = 1
			sparks.Rate          = 0
			sparks.Parent        = body
			sparks:Emit(SPARK_COUNT)
			task.delay(1.5, function() sparks:Destroy() end)
		end
	end
	return true
end

local function dress(body: Instance)
	if not body:IsA("BasePart") or body:FindFirstChild("EggMesh") then return end
	if dressModel(body) then return end

	local template = EggMesh.getTemplate()
	if not template then return end   -- Server-Kugel bleibt sichtbar

	local mesh = template:Clone()
	mesh.Name     = "EggMesh"
	mesh.Size     = body.Size
	mesh.CFrame   = body.CFrame
	mesh.Color    = body.Color
	mesh.Material = body.Material
	mesh.Parent   = body
	body.Transparency = 1

	local uid = body:GetAttribute("LaidEggUid")
	if type(uid) == "string" then
		local isNew = _settled and not _seen[uid]
		_seen[uid] = true
		if isNew then popIn(body, mesh) end
	end
end

function LaidEggMeshController.init()
	task.delay(SETTLE_TIME, function() _settled = true end)
	CollectionService:GetInstanceAddedSignal(TAG):Connect(dress)
	for _, body in CollectionService:GetTagged(TAG) do
		task.spawn(dress, body)
	end
end

return LaidEggMeshController
