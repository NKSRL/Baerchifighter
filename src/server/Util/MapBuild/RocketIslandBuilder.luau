--!strict
-- RocketIslandBuilder.luau
-- ServerScriptService/Util/MapBuild/RocketIslandBuilder.luau
--
-- Einzige Zustaendigkeit:
--   - P4 (20.10.): dauerhafte Mini-Insel mit Bruecke, Rakete auf Startrampe und Hinweisschild
--     "Welt 2" in Welt 1 bauen. Reine Deko + Schild; keine Interaktion, kein Startknopf (A7).
--
-- Lage (W1-P2): je Plot eine Insel hinter der Arena-Insel (Fight-Pit) auf der Plot-Achse
-- (RocketIslandRules.layout); optional Part "RaketenAnker_<slot>" im Workspace. Alles haengt am
-- Plot-Modell (wird mit dem Plot neu gebaut), Namensschema "RocketIsland_*". Teile-Budget RocketIslandConfig.PART_BUDGET.
--
-- Das Schild zeigt serverseitig nur den Platzhalter (gesperrt); den Zustand je Spieler setzt der
-- Client (Controllers/RocketIslandController) aus seinem Spielstand — die Welt gibt es nur einmal.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapConfig          = require(ReplicatedStorage.Config.MapConfig)
local FeatureFlags       = require(ReplicatedStorage.Config.FeatureFlags)
local MapStyleConfig     = require(ReplicatedStorage.Config.MapStyleConfig)
local RocketIslandConfig = require(ReplicatedStorage.Config.RocketIslandConfig)
local RocketIslandRules  = require(ReplicatedStorage.Modules.RocketIslandRules)
local Loc                = require(ReplicatedStorage.Localization.Loc)
local WorldText          = require(ReplicatedStorage.Localization.WorldText)

local MapParts  = require(script.Parent.MapParts)
local MapMeshes = require(script.Parent.MapMeshes)

local RocketIslandBuilder = {}

local P = RocketIslandConfig.NAME_PREFIX
local C = RocketIslandConfig.COLORS

local function part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, collide: boolean?): Part
	local p = MapParts.newPart(P .. name, size, cframe, color, material)
	p.CanCollide = collide == true
	p.CanQuery = collide == true
	p.CanTouch = false
	p.Parent = parent
	return p
end

-- Zylinder, der senkrecht steht (Roblox-Zylinder liegen von Haus aus entlang X).
local function cylinderUp(parent: Instance, name: string, height: number, diameter: number, baseCenter: Vector3, color: Color3, material: Enum.Material, collide: boolean?): Part
	local p = part(parent, name, Vector3.new(height, diameter, diameter),
		CFrame.new(baseCenter + Vector3.new(0, height * 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, material, collide)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- Baut die Raketen-Insel von `slot` als Kind von `parent` (dem Plot-Modell). Lage: auf der Achse des Plots hinter
-- der Arena-Insel (Fight-Pit): Event-Pit -> Plot -> Fight-Pit -> Rakete. Jeder Spieler hat seine eigene.
function RocketIslandBuilder.build(parent: Instance, slot: number): Folder?
	if not FeatureFlags.isOn("ROCKET_ISLAND") then return nil end
	local old = parent:FindFirstChild(P .. "Root")
	if old then old:Destroy() end

	-- Optionaler Anker je Slot (RaketenAnker_<slot>), sonst berechneter Platzhalter hinter dem Pit
	local anchor = workspace:FindFirstChild(RocketIslandConfig.ANCHOR_NAME .. "_" .. tostring(slot))
	local anchorPos: Vector3? = if anchor and anchor:IsA("BasePart") then anchor.Position else nil
	local layout = RocketIslandRules.layout(slot, anchorPos)
	local clearance = RocketIslandRules.clearanceToIslands(layout.center, slot)
	if clearance <= 0 then
		warn("[RocketIslandBuilder] Slot", slot, ": Raketen-Insel liegt zu nah an einer anderen Insel (Luft:", clearance, "Studs)")
	end

	local root = Instance.new("Folder")
	root.Name = P .. "Root"
	root:SetAttribute("Placeholder", layout.placeholder)
	root:SetAttribute("Slot", slot)
	root:SetAttribute("AngleDeg", layout.angleDeg)

	local R = RocketIslandConfig.ISLAND_RADIUS
	local center = layout.center
	local top = center + Vector3.new(0, MapConfig.PLATFORM_TOP_Y - center.Y, 0)

	-- Bruecke (gleiche Bauart wie die Stege)
	MapParts.buildSpan(root, P .. "Bridge", layout.outward, layout.fromRadius, layout.toRadius)

	-- Insel mit ruhiger Wiesen-Oberflaeche (passend zum Royal-Honey-Sanktuarium)
	local ground = MapParts.buildIsland(root, P .. "Ground", center, R, MapConfig.GRASS_DARK, Enum.Material.Grass)
	if FeatureFlags.isOn("MAP_GROUND_OLDSCHOOL") and MapMeshes.enabled() then
		MapMeshes.groundOldschool(root, ground, {
			center = center, radius = R,
			levels = RocketIslandConfig.GROUND_LEVELS, margin = RocketIslandConfig.GROUND_MARGIN,
			folderName = P .. "GroundStuds",
		})
	end

	-- Startrampe: Sockel + Gelaender-Pfosten
	local rampTop = Vector3.new(center.X, MapConfig.PLATFORM_TOP_Y + 1.6, center.Z)
	cylinderUp(root, "Ramp", 1.6, 13, Vector3.new(center.X, MapConfig.PLATFORM_TOP_Y, center.Z), C.ramp, Enum.Material.WoodPlanks, true)
	cylinderUp(root, "RampPlate", 0.3, 9.5, rampTop, C.rampMetal, Enum.Material.Metal, false)
	for i = 0, 3 do
		local a = math.rad(i * 90 + 45)
		part(root, "RampPost", Vector3.new(0.6, 2.6, 0.6),
			CFrame.new(center.X + math.cos(a) * 5.6, MapConfig.PLATFORM_TOP_Y + 1.6 + 1.3, center.Z + math.sin(a) * 5.6),
			C.signPost, Enum.Material.Wood, false)
	end

	-- Rakete (feststehend, nur Box-Kollision am Koerper): Sektionen weiss/rot, Nase aus drei Scheiben
	local base = Vector3.new(center.X, MapConfig.PLATFORM_TOP_Y + 1.9, center.Z)
	local d = RocketIslandConfig.ROCKET_RADIUS * 2
	local rocketParts: { Part } = {}
	local function add(p: Part) p:SetAttribute("RocketPart", true); table.insert(rocketParts, p) end
	add(cylinderUp(root, "RocketNozzle", 1.4, d * 0.6, base, Color3.fromRGB(70, 74, 84), Enum.Material.Metal, false))
	add(cylinderUp(root, "RocketBodyLow", 6.2, d, base + Vector3.new(0, 1.4, 0), C.rocketWhite, Enum.Material.SmoothPlastic, true))
	add(cylinderUp(root, "RocketBand", 3.2, d * 1.02, base + Vector3.new(0, 7.6, 0), C.rocketRed, Enum.Material.SmoothPlastic, false))
	add(cylinderUp(root, "RocketBodyHigh", 4.2, d, base + Vector3.new(0, 10.8, 0), C.rocketWhite, Enum.Material.SmoothPlastic, false))
	add(cylinderUp(root, "RocketNose1", 1.6, d * 0.8, base + Vector3.new(0, 15, 0), C.rocketRed, Enum.Material.SmoothPlastic, false))
	add(cylinderUp(root, "RocketNose2", 1.4, d * 0.5, base + Vector3.new(0, 16.6, 0), C.rocketRed, Enum.Material.SmoothPlastic, false))
	add(cylinderUp(root, "RocketNose3", 1.0, d * 0.22, base + Vector3.new(0, 18, 0), C.rocketRed, Enum.Material.SmoothPlastic, false))
	for i = 0, 2 do
		local a = math.rad(i * 120)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local fin = Instance.new("WedgePart")
		fin.Name = P .. "RocketFin"
		fin.Anchored = true
		fin.CanCollide = false
		fin.CanQuery = false
		fin.CanTouch = false
		fin.Size = Vector3.new(0.5, 4.4, 3.2)
		fin.Color = C.rocketRed
		fin.Material = Enum.Material.SmoothPlastic
		fin.CFrame = CFrame.lookAt(base + Vector3.new(0, 3.6, 0) + dir * (RocketIslandConfig.ROCKET_RADIUS + 1.4), base + Vector3.new(0, 3.6, 0) + dir * 40)
			* CFrame.Angles(0, math.rad(90), 0)
		fin.Parent = root
		add(fin)
	end
	-- Fenster (Neon-Gelb, Glimmen macht der Client mit +-10 %)
	local window = part(root, "RocketWindow", Vector3.new(0.5, 2.2, 2.2),
		CFrame.new(base + Vector3.new(0, 11.4, 0) + Vector3.new(RocketIslandConfig.ROCKET_RADIUS, 0, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		C.window, Enum.Material.Neon, false)
	window.Shape = Enum.PartType.Cylinder
	window:SetAttribute("RocketWindow", true)
	add(window)

	-- Hinweisschild (Text je Spieler vom Client)
	local signDir = Vector3.new(-layout.outward.Z, 0, layout.outward.X) -- seitlich der Bruecke
	local signPos = Vector3.new(center.X, MapConfig.PLATFORM_TOP_Y, center.Z) - layout.outward * (R - 3) + signDir * 5
	local face = CFrame.lookAt(signPos + Vector3.new(0, 4.5, 0), signPos + Vector3.new(0, 4.5, 0) - layout.outward)
	for _, side in { -1, 1 } do
		part(root, "SignPost", Vector3.new(0.7, 5, 0.7), CFrame.new(signPos + signDir * side * 3.4 + Vector3.new(0, 2.5, 0)), C.signPost, Enum.Material.Wood, false)
	end
	local board = part(root, "SignBoard", Vector3.new(8.4, 4.6, 0.6), face, C.sign, Enum.Material.WoodPlanks, false)
	board:SetAttribute("RocketSign", true)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "SignGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.Parent = board
	local title = MapParts.newTextLabel("SignText", gui, UDim2.fromScale(0.92, 0.62), UDim2.fromScale(0.04, 0.04))
	WorldText.set(title, Loc.msg(RocketIslandConfig.TEXT.locked))
	local progress = MapParts.newTextLabel("SignProgress", gui, UDim2.fromScale(0.92, 0.26), UDim2.fromScale(0.04, 0.68))
	progress.TextColor3 = C.gold
	WorldText.set(progress, Loc.msg(RocketIslandConfig.TEXT.progress, { stage = 0, total = 100 }))

	-- Zwei Laternen am Rand (Honig-Gold)
	for _, side in { -1, 1 } do
		local lp = Vector3.new(center.X, MapConfig.PLATFORM_TOP_Y, center.Z) - layout.outward * (R - 2.5) - signDir * side * 6.5
		part(root, "LampPost", Vector3.new(0.5, 4, 0.5), CFrame.new(lp + Vector3.new(0, 2, 0)), C.signPost, Enum.Material.Wood, false)
		local bulb = part(root, "Lamp", Vector3.new(1.2, 1.2, 1.2), CFrame.new(lp + Vector3.new(0, 4.4, 0)), C.lamp, Enum.Material.Neon, false)
		bulb.Shape = Enum.PartType.Ball
	end

	-- Drei kantige Felsen als Randdeko
	for i, ang in { 120, 200, 285 } do
		local a = math.rad(ang)
		local rp = Vector3.new(center.X + math.cos(a) * (R - 3), MapConfig.PLATFORM_TOP_Y + 0.6, center.Z + math.sin(a) * (R - 3))
		part(root, "Rock", Vector3.new(2.2 + i * 0.3, 1.6 + i * 0.2, 2.0), CFrame.new(rp) * CFrame.Angles(0, math.rad(ang * 2), math.rad(6 * i)), C.rock, Enum.Material.Slate, false)
	end

	root.Parent = parent

	local count = 0
	for _, d2 in root:GetDescendants() do
		if d2:IsA("BasePart") then count += 1 end
	end
	root:SetAttribute("PartCount", count)
	if count > RocketIslandConfig.PART_BUDGET then
		warn("[RocketIslandBuilder] Teile-Budget ueberschritten:", count, ">", RocketIslandConfig.PART_BUDGET)
	end
	print("[RocketIslandBuilder] Raketen-Insel Slot", slot, "gebaut |", count, "Teile | Lage", layout.center, "| Platzhalter:", layout.placeholder)
	return root
end

return RocketIslandBuilder
