--!strict
-- EpilogFinaleBuilder.luau
-- ServerScriptService/Util/MapBuild/EpilogFinaleBuilder.luau
--
-- Einzige Zustaendigkeit (Prompt 6 von 7, Final-Epilog):
--   - Die kleine Cartoon-Rakete samt Schacht neben dem Terminal bauen (Server-Teile,
--     ohne Kollision, 2 Emitter) und wieder zerstoeren. Die Bewegung (Aufstieg in die
--     Wolken) macht der Client per Tween auf seiner Kopie; der Server steuert nur
--     Sichtbarkeit und Emitter (`launch`).
--   - Alles haengt am Epilog-Ordner des Plots und geht mit der Insel (onTeardown) weg.
--
-- Mit Mesh-Vorlage (ReplicatedStorage.Assets.EpilogRakete, MeshPart Epilog_Rakete, Pivot
-- Unterseite) ein Teil + Schacht; ohne Vorlage Primitive (hoechstens FINALE.rocket.parts).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EpilogConfig = require(ReplicatedStorage.Config.EpilogConfig)

local EpilogMeshes        = require(script.Parent.EpilogMeshes)
local EpilogIslandBuilder = require(script.Parent.EpilogIslandBuilder)

local EpilogFinaleBuilder = {}

local R = EpilogConfig.FINALE.rocket

type State = {
	model    : Model,
	rocket   : Model,
	base     : CFrame,      -- Fuss der Rakete (Mitte Schacht)
	emitters : { ParticleEmitter },
	lamp     : PointLight,
}

local _state: { [Player]: State } = {}

local function particleTexture(): string
	local A = EpilogConfig.ASSETS
	return if A.cloudTex ~= "" then A.cloudTex else A.particleFallback
end

local function part(name: string, size: Vector3, cf: CFrame, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

function EpilogFinaleBuilder.exists(player: Player): boolean
	local s = _state[player]
	return s ~= nil and s.model.Parent ~= nil
end

function EpilogFinaleBuilder.countParts(player: Player): number
	local s = _state[player]
	if not s then return 0 end
	local n = 0
	for _, d in s.model:GetDescendants() do
		if d:IsA("BasePart") then n += 1 end
	end
	return n
end

function EpilogFinaleBuilder.destroy(player: Player)
	local s = _state[player]
	if not s then return end
	_state[player] = nil
	if s.model.Parent ~= nil then s.model:Destroy() end
end

-- Baut Schacht und Rakete (Rakete steht im Schacht, Emitter aus). nil ohne Insel.
function EpilogFinaleBuilder.build(plot: Model, owner: Player): Model?
	if not EpilogIslandBuilder.exists(owner) then return nil end
	local info = EpilogIslandBuilder.getRouteInfo(plot)
	local folder = plot:FindFirstChild("Epilog")
	if not info or not (folder and folder:IsA("Folder")) then return nil end
	EpilogFinaleBuilder.destroy(owner)

	local dir = Vector3.new(info.dir[1], 0, info.dir[3])
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local island = Vector3.new(info.island[1], info.island[2], info.island[3])
	-- Schacht neben der Insel-Mitte (Terminal steht hinter der Mitte, Rakete seitlich davon)
	local foot = island + side * R.sideOffset + dir * R.alongOffset
	local base = CFrame.lookAt(foot, foot + dir)

	local model = Instance.new("Model")
	model.Name = "Rakete"
	local rocket = Instance.new("Model")
	rocket.Name = "Epilog_Rakete"
	rocket.Parent = model

	-- Schacht: dunkle Scheibe in der Wiese mit goldenem Rand (liegend, Zylinderachse = Y)
	local lay = CFrame.Angles(0, 0, math.rad(90))
	local c = EpilogConfig.TERMINAL.colors
	local shaft = part("Epilog_Rakete_Schacht", Vector3.new(0.3, 4.2, 4.2), base * CFrame.new(0, 0.05, 0) * lay, R.shaftColor, model)
	shaft.Shape = Enum.PartType.Cylinder
	local rim = part("Epilog_Rakete_Rand", Vector3.new(0.2, 4.9, 4.9), base * CFrame.new(0, 0.02, 0) * lay, c.gold, model)
	rim.Shape = Enum.PartType.Cylinder

	local tex = EpilogMeshes.meshPart(EpilogConfig.ASSETS.rocketTemplate, "Epilog_Rakete")
	local anchor: BasePart
	if tex then
		-- Vorlage: Groesse auf R.height skalieren (Pivot der Vorlage = Unterseite, das
		-- MeshPart selbst steht mit der Mitte auf halber Hoehe)
		local k = R.height / math.max(0.01, tex.Size.Y)
		EpilogMeshes.setup(tex, "Epilog_Rakete_Huelle", tex.Size * k, base * CFrame.new(0, R.height / 2 + 0.1, 0))
		tex.CanQuery = false
		tex.Parent = rocket
		anchor = tex
	else
		local h, r = R.height, R.radius
		-- Rumpf (Zylinder, Achse nach oben), Nase (Kugel), Bullauge, drei Flossen
		local body = part("Epilog_Rakete_Rumpf", Vector3.new(h * 0.62, r * 2, r * 2),
			base * CFrame.new(0, h * 0.31 + 0.1, 0) * lay, R.bodyColor, rocket)
		body.Shape = Enum.PartType.Cylinder
		local nose = part("Epilog_Rakete_Nase", Vector3.new(r * 2, r * 2, r * 2),
			base * CFrame.new(0, h * 0.62 + r * 0.6 + 0.1, 0), R.noseColor, rocket)
		nose.Shape = Enum.PartType.Ball
		local win = part("Epilog_Rakete_Bullauge", Vector3.new(r * 0.9, r * 0.9, r * 0.5),
			base * CFrame.new(0, h * 0.45 + 0.1, -r * 0.85), R.windowColor, rocket)
		win.Shape = Enum.PartType.Ball
		win.Material = Enum.Material.Neon
		for i = 0, 2 do
			local fin = Instance.new("WedgePart")
			fin.Name = "Epilog_Rakete_Flosse" .. (i + 1)
			fin.Size = Vector3.new(0.3, r * 1.6, r * 1.6)
			fin.CFrame = base * CFrame.Angles(0, math.rad(120 * i), 0)
				* CFrame.new(0, r * 0.8 + 0.1, -r - 0.5)
			fin.Color = R.finColor
			fin.Material = Enum.Material.SmoothPlastic
			fin.Anchored, fin.CanCollide, fin.CanTouch, fin.CanQuery, fin.CastShadow = true, false, false, false, false
			fin.Parent = rocket
		end
		anchor = body
	end
	rocket.PrimaryPart = anchor

	-- Zwei Emitter am Fuss: Feuer und Rauch (aus, bis `launch`)
	local attach = Instance.new("Attachment")
	attach.Name = "Duese"
	attach.CFrame = anchor.CFrame:ToObjectSpace(base * CFrame.new(0, 0.1, 0) * CFrame.Angles(math.pi, 0, 0))   -- Y zeigt nach unten
	attach.Parent = anchor
	local fire = Instance.new("ParticleEmitter")
	fire.Name = "Feuer"
	fire.Texture = particleTexture()
	fire.Color = ColorSequence.new(Color3.fromRGB(255, 196, 60), Color3.fromRGB(226, 44, 44))
	fire.LightEmission = 1
	fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3.2), NumberSequenceKeypoint.new(1, 0.4) })
	fire.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	fire.Lifetime = NumberRange.new(0.3, 0.55)
	fire.Speed = NumberRange.new(18, 26)
	fire.SpreadAngle = Vector2.new(8, 8)
	fire.Rate = 70
	fire.Enabled = false
	fire.Parent = attach
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "Rauch"
	smoke.Texture = particleTexture()
	smoke.Color = ColorSequence.new(Color3.fromRGB(246, 240, 232))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 9) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(1.0, 1.8)
	smoke.Speed = NumberRange.new(6, 12)
	smoke.SpreadAngle = Vector2.new(20, 20)
	smoke.Rate = 30
	smoke.Enabled = false
	smoke.Parent = attach
	local lamp = Instance.new("PointLight")
	lamp.Color = Color3.fromRGB(255, 160, 60)
	lamp.Range = 24
	lamp.Brightness = 0
	lamp.Parent = anchor

	model:SetAttribute("EpilogRocketBase", base.Position)
	model.Parent = folder

	_state[owner] = { model = model, rocket = rocket, base = base, emitters = { fire, smoke }, lamp = lamp }
	EpilogIslandBuilder.onTeardown(owner, function()
		EpilogFinaleBuilder.destroy(owner)
	end)
	return model
end

-- Fuss der Rakete als Zahlen-Tabelle {x, y, z} (fuer den Client), nil ohne Rakete.
function EpilogFinaleBuilder.getBase(player: Player): { number }?
	local s = _state[player]
	if not s then return nil end
	local p = s.base.Position
	return { p.X, p.Y, p.Z }
end

-- Feuer an/aus (der Client steuert die Bewegung selbst).
function EpilogFinaleBuilder.launch(player: Player, on: boolean)
	local s = _state[player]
	if not s then return end
	for _, e in s.emitters do e.Enabled = on end
	s.lamp.Brightness = if on then 3 else 0
	s.model:SetAttribute("EpilogRocketLaunched", on)
end

return EpilogFinaleBuilder
