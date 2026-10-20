--!strict
-- CombBuilder.luau
-- ServerScriptService/Util/CombBuilder.luau
--
-- Einzige Zustaendigkeit:
--   - Eine Honigwabe als Teile-Gruppe bauen: einmal fuer die im Event-Pit
--     liegenden Waben, einmal fuer den Stapel ueber dem Kopf des Spielers.
--
-- Eine Wabe ist ein regelmaessiges Sechseck aus drei sich kreuzenden Platten
-- (siehe CombConfig.COMB_RADIUS) plus einer dunkleren Honigzelle in der Mitte.
-- Kein Mesh, kein Asset: laeuft in jedem Place ohne Upload.
--
-- Dieses Modul kennt weder Spieler noch Spielstand. Wohin die Teile kommen
-- (in die Welt oder an den Kopf) entscheidet CombService.
--
-- Wabenthemen (CombConfig.THEMES, z.B. Lava im Hot-Egg-Event) aendern nur
-- Farben und Material. Das Thema steht als Attribut "Theme" am Model, damit
-- auch der Client es kennt, ohne Zustand aus der Replikationsreihenfolge.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CombConfig = require(ReplicatedStorage.Config.CombConfig)
local FeatureFlags = require(ReplicatedStorage.Config.FeatureFlags)

local CombBuilder = {}

export type CombParts = {
	body  : { Part },   -- die drei Sechseck-Platten
	cell  : Part,       -- die Honigzelle
}

local SQRT3 = math.sqrt(3)

-- NEW_MODELS_V3: Mesh-Waben aus ReplicatedStorage.Assets.Combs. EIN MeshPart
-- pro Wabe, vier Varianten auf demselben Mesh. Aus = alte Platten-Optik.
-- Mesh ist 3.3 x 1.0 x 3.0 Studs gross (alte Wabe: 2.7 x 0.55).
local NEW_WORLD_SCALE = 1.2    -- ~4 Studs im Pit (alt: 3.9)
local NEW_STACK_SCALE = 0.85   -- ~2.8 Studs ueber dem Kopf (alt: 2.7)
local THEME_VARIANT = { HotEgg = "Comb_Lava", WaspQueen = "Comb_RoyalJelly" }

local function newTemplate(isGold: boolean, themeId: string?): Model?
	if not FeatureFlags.isOn("NEW_MODELS_V3") then
		return nil
	end
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local folder = assets and assets:FindFirstChild("Combs")
	if not folder then
		return nil
	end
	local name = (themeId and THEME_VARIANT[themeId]) or (if isGold then "Comb_Gold" else "Comb_Normal")
	local tpl = folder:FindFirstChild(name)
	if tpl and tpl:IsA("Model") then
		return tpl
	end
	return nil
end

-- Klon der Vorlage als sauberes Model; Teile bleiben so, wie sie sind.
local function cloneComb(tpl: Model, name: string, scale: number): Model
	local model = tpl:Clone()
	model.Name = name
	model.WorldPivot = tpl.WorldPivot
	if scale ~= 1 then
		model:ScaleTo(scale)
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch   = false
			d.CanQuery   = false
			d.CastShadow = false
			d.Massless   = true
		end
	end
	return model
end

local function basePart(name: string, size: Vector3, color: Color3, material: Enum.Material): Part
	local part = Instance.new("Part")
	part.Name          = name
	part.Size          = size
	part.Color         = color
	part.Material      = material
	part.TopSurface    = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide    = false
	part.CanTouch      = false
	part.CanQuery      = false
	part.CastShadow    = false
	part.Massless      = true
	return part
end

-- Erzeugt die Teile einer Wabe, MITTELPUNKT im Ursprung, flach liegend (Y oben).
-- `scale` skaliert alles gleichmaessig. Die Teile sind noch nirgends eingehaengt
-- und nicht verankert — der Aufrufer entscheidet, ob er sie verankert (Welt)
-- oder an einen Kopf schweisst (Stapel).
function CombBuilder.createParts(isGold: boolean, scale: number, themeId: string?): CombParts
	local r = CombConfig.COMB_RADIUS * scale
	local h = CombConfig.COMB_HEIGHT * scale

	local theme = CombConfig.getTheme(themeId)
	local bodyColor, cellColor, material, cellMaterial
	if theme then
		bodyColor    = if isGold then theme.goldBodyColor else theme.bodyColor
		cellColor    = if isGold then theme.goldCellColor else theme.cellColor
		material     = theme.bodyMaterial
		cellMaterial = theme.cellMaterial
	else
		bodyColor    = if isGold then CombConfig.GOLD_COMB_COLOR else CombConfig.COMB_COLOR
		cellColor    = if isGold then CombConfig.GOLD_CELL_COLOR else CombConfig.CELL_COLOR
		material     = if isGold then Enum.Material.Metal else Enum.Material.SmoothPlastic
		cellMaterial = Enum.Material.Neon
	end

	local body: { Part } = {}
	for i = 0, 2 do
		local plate = basePart("Wabe" .. (i + 1), Vector3.new(r * 2, h, r * SQRT3), bodyColor, material)
		plate.CFrame = CFrame.Angles(0, math.rad(60 * i), 0)
		table.insert(body, plate)
	end

	-- Die Zelle steht minimal ueber der Oberseite (0.04), sonst flimmert sie
	-- gegen die Platten — dieselbe Regel wie bei GRASS_HEIGHT in MapConfig.
	local cellRadius = CombConfig.CELL_RADIUS * scale
	local cell = basePart(
		"Zelle",
		Vector3.new(0.12 * scale, cellRadius * 2, cellRadius * 2),
		cellColor,
		cellMaterial
	)
	cell.Shape  = Enum.PartType.Cylinder
	cell.CFrame = CFrame.new(0, h * 0.5 + 0.04, 0) * CFrame.Angles(0, 0, math.rad(90))

	return { body = body, cell = cell }
end

-- Setzt alle Teile mit `placement` (Weltposition der Wabenmitte) um und
-- gibt sie als Liste zurueck. Die Platten behalten ihre Drehung relativ zur
-- Mitte. Liefert die Teile in fester Reihenfolge: Platten, dann Zelle.
function CombBuilder.place(parts: CombParts, placement: CFrame): { Part }
	local result: { Part } = {}
	for _, plate in parts.body do
		plate.CFrame = placement * plate.CFrame
		table.insert(result, plate)
	end
	parts.cell.CFrame = placement * parts.cell.CFrame
	table.insert(result, parts.cell)
	return result
end

-- Eine im Pit liegende Wabe als Model. Verankert, schwebt `WORLD_HOVER` ueber
-- dem Boden. Attribute: "Units" (Wert), "Phase" (fuer die Wipp-Animation im
-- Client, damit nicht alle Waben im Gleichtakt wippen), "Pos"/"Yaw" (Ruhelage).
--
-- WARUM "Pos"/"Yaw": Der Client animiert die Wabe relativ zu ihrer Ruhelage.
-- Liest er die Ruhelage per GetPivot(), bevor alle Teile repliziert sind,
-- bekommt er den Weltursprung und schiebt die Wabe jedes Frame dorthin (unter
-- den Pit-Boden: "unsichtbare Waben"). Attribute kommen garantiert mit dem
-- Model selbst an, die Replikationsreihenfolge der Teile spielt dann keine Rolle.
function CombBuilder.buildWorldComb(position: Vector3, yaw: number, isGold: boolean, units: number, phase: number, themeId: string?): Model
	local model = Instance.new("Model")
	model.Name = "Comb"
	model:SetAttribute("Units", units)
	model:SetAttribute("Phase", phase)
	model:SetAttribute("Gold", isGold)
	if themeId then
		model:SetAttribute("Theme", themeId)
	end

	local center = position + Vector3.new(0, CombConfig.WORLD_HOVER, 0)
	model:SetAttribute("Pos", center)
	model:SetAttribute("Yaw", yaw)

	local tpl = newTemplate(isGold, themeId)
	if tpl then
		local mesh = cloneComb(tpl, "Comb", NEW_WORLD_SCALE)
		mesh:PivotTo(CFrame.new(center) * CFrame.Angles(0, yaw, 0))
		for _, d in mesh:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		mesh.PrimaryPart = mesh:FindFirstChildWhichIsA("BasePart", true)
		for k, v in model:GetAttributes() do
			mesh:SetAttribute(k, v)
		end
		return mesh
	end

	local parts = CombBuilder.createParts(isGold, CombConfig.WORLD_SCALE, themeId)
	local placed = CombBuilder.place(
		parts,
		CFrame.new(center) * CFrame.Angles(0, yaw, 0)
	)

	for _, part in placed do
		part.Anchored = true
		part.Parent   = model
	end
	model.PrimaryPart = placed[1]

	-- Goldene Waben leuchten, damit man sie im Gewimmel sofort sieht. Nur ohne
	-- Thema: Themen-Waben gluehen ueber ihre Neon-Zelle und Bloom (kein Licht,
	-- kein Emitter pro Wabe).
	if isGold and not themeId then
		local light = Instance.new("PointLight")
		light.Color      = CombConfig.GOLD_COMB_COLOR
		light.Range      = 9
		light.Brightness = 1.4
		light.Parent     = placed[#placed]

		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = CombConfig.GOLD_CELL_COLOR
		sparkles.Parent       = placed[#placed]
	end

	return model
end

-- Eine Wabe im Stapel: schon an den Kopf geschweisst. `slot` zaehlt von 1 (die
-- unterste). `parent` ist der Ordner am Charakter, in den die Wabe kommt.
function CombBuilder.buildStackComb(head: BasePart, slot: number, isGold: boolean, parent: Instance, themeId: string?): Model
	local model = Instance.new("Model")
	model.Name = "CombStackItem"
	model.Parent = parent   -- zuerst einhaengen: WeldConstraint merkt sich den Versatz erst dann sicher

	local wobbleSign = if slot % 2 == 0 then 1 else -1
	local wobbleStep = (slot % 3) - 1   -- -1, 0, 1

	local localY = head.Size.Y * 0.5
		+ CombConfig.STACK_HEAD_GAP
		+ (slot - 1) * CombConfig.STACK_STEP

	local offset = CFrame.new(
		wobbleSign * CombConfig.STACK_WOBBLE_STUDS * wobbleStep,
		localY,
		-wobbleSign * CombConfig.STACK_WOBBLE_STUDS * (1 - math.abs(wobbleStep))
	) * CFrame.Angles(0, math.rad(wobbleSign * CombConfig.STACK_WOBBLE_DEGREES * (slot % 4)), 0)

	-- Der Kopf dreht sich mit dem Charakter; der Stapel soll aufrecht bleiben.
	-- Deshalb Schweissung relativ zum Kopf und die Wabe in Kopf-Ausrichtung
	-- platziert: Kopf-CFrame * offset, dann WeldConstraint (behaelt den Versatz).
	local tpl = newTemplate(isGold, themeId)
	if tpl then
		local mesh = cloneComb(tpl, "CombStackItem", NEW_STACK_SCALE)
		-- Unterseite sitzt auf dem Stapelpunkt: Mesh-Hoehe/2 nach oben.
		local half = select(2, mesh:GetBoundingBox()).Y * 0.5
		mesh:PivotTo(head.CFrame * offset * CFrame.new(0, half - CombConfig.COMB_HEIGHT * 0.5, 0))
		mesh.Parent = parent
		model:Destroy()
		for _, d in mesh:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = false
				local weld = Instance.new("WeldConstraint")
				weld.Part0  = head
				weld.Part1  = d
				weld.Parent = d
			end
		end
		mesh.PrimaryPart = mesh:FindFirstChildWhichIsA("BasePart", true)
		return mesh
	end

	local parts  = CombBuilder.createParts(isGold, 1, themeId)
	local placed = CombBuilder.place(parts, head.CFrame * offset)

	for _, part in placed do
		part.Anchored = false
		part.Parent   = model

		local weld = Instance.new("WeldConstraint")
		weld.Part0  = head
		weld.Part1  = part
		weld.Parent = part
	end
	model.PrimaryPart = placed[1]

	return model
end

-- Einmaliger Funken-Burst (Skin-Wechsel bei Thema-Start/-Ende): EIN Emitter
-- an einem unsichtbaren Traeger, ein Emit, danach weg. Nie pro Wabe.
function CombBuilder.themeBurst(position: Vector3, color: Color3, parent: Instance)
	local holder = Instance.new("Part")
	holder.Name         = "CombThemeBurst"
	holder.Size         = Vector3.new(1, 1, 1)
	holder.Transparency = 1
	holder.Anchored     = true
	holder.CanCollide   = false
	holder.CanQuery     = false
	holder.CanTouch     = false
	holder.CastShadow   = false
	holder.Position     = position
	holder.Parent       = parent

	local emitter = Instance.new("ParticleEmitter")
	emitter.Color         = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Size          = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.9),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Lifetime      = NumberRange.new(0.8, 1.6)
	emitter.Speed         = NumberRange.new(25, 45)
	emitter.SpreadAngle   = Vector2.new(70, 70)
	emitter.Acceleration  = Vector3.new(0, -30, 0)
	emitter.Rate          = 0
	emitter.EmissionDirection = Enum.NormalId.Top
	emitter.Parent        = holder
	emitter:Emit(CombConfig.THEME_BURST_COUNT)

	task.delay(2, function()
		holder:Destroy()
	end)
end

return CombBuilder
