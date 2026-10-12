--!strict
-- LaidEggBuilder.luau
-- ServerScriptService/Util/MapBuild/LaidEggBuilder.luau
--
-- Einzige Zustaendigkeit:
--   - Die gelegten Eier eines Plots in der Welt zeigen und das Beruehren durch
--     den Besitzer an den eingehaengten Handler melden
--
-- Den Handler haengt EggLayService ueber MapService.setEggCollectHandler ein
-- (Pull-Callback statt require, sonst entstuende ein Ringschluss).
--
-- Teil von MapService: nur MapService (und die Builder untereinander)
-- benutzen dieses Modul. Es aendert keine Spielerdaten.

local CollectionService   = game:GetService("CollectionService")
local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local EggConfig        = require(ReplicatedStorage.Config.EggConfig)
local EggLook          = require(ReplicatedStorage.Modules.EggLook)
local EggMesh          = require(ReplicatedStorage.Modules.EggMesh)
local Types            = require(ReplicatedStorage.Network.Types)
local Names     = require(ReplicatedStorage.Localization.Names)
local WorldText = require(ReplicatedStorage.Localization.WorldText)

local FigureFX         = require(ServerScriptService.Util.FigureFX)

local MapParts = require(ServerScriptService.Util.MapBuild.MapParts)

local LaidEggBuilder = {}

-- Wird aufgerufen, wenn der BESITZER eines Plots sein eigenes gelegtes Ei mit
-- der Spielfigur beruehrt. Ohne Handler sammelt Beruehren einfach nichts ein.
local _collectHandler: ((Player, string) -> ())? = nil

function LaidEggBuilder.setCollectHandler(handler: (Player, string) -> ())
	_collectHandler = handler
end

-- Attribut, das jedes gelegte Ei traegt. Der Client liest es beim Klick
-- (WorldController) — dieselbe Konvention wie "BaerchiUid" an den Figuren.
LaidEggBuilder.LAID_EGG_ATTRIBUTE = "LaidEggUid"

-- ============================================================================
-- Aussehen
-- ============================================================================
-- Ein gelegtes Ei ist ein GESTAPELTES Ei: ein Rotationsmesh mit sechs abgesetzten Stufen (siehe buildTemplate). Gurte in der Zweitfarbe liegen an den Naehten,
-- Stein-Punkte und eine kleine Spitze oben vervollstaendigen es; seltene Eier
-- bekommen einen Schimmer am Boden.
--
-- Die Ringe wechseln leicht die Helligkeit (Segment-Look), die Gurte setzen das
-- Muster des Pfads (EggLook): Stamm = Punkte, Gold = goldene Krone mit Steinen,
-- Kristall = drei Gurte, Void/Kosmos/Ascension/Event = Neon-Gurte + Leuchtpunkte.
--
-- Teile-Budget: Mesh-Koerper (1 Teil) + 0 bis 3 Gurte + 0 bis 3 Punkte + hoechstens
-- 1 Schimmer = 3 bis 8 Teile je Ei, bis zu 12 Eier je Plot.

local EGG_SCALE        = 0.85   -- gegenueber EggConfig.LAY_EGG_SIZE: Eier bleiben kleiner als ein Baerchi (BAERCHI_SCALE in BaerchiMesh)
local SPARKLE_RATE     = 3      -- Funken/Sekunde bei seltenen Eiern (ein Emitter je Ei)

local function shade(color: Color3, amount: number): Color3
	if amount >= 0 then return color:Lerp(Color3.new(1, 1, 1), amount) end
	return color:Lerp(Color3.new(0, 0, 0), -amount)
end

local function finish(part: Part, parent: Instance)
	part.CanCollide = false
	part.CanTouch   = false
	part.CanQuery   = false
	part.CastShadow = false
	part.Parent     = parent
end

-- Ein stehender Zylinder (Cylinder-Part liegt von Haus aus entlang X; um 90 Grad
-- um Z gekippt steht seine Achse senkrecht), Unterkante auf `y0`.
local function newRing(name: string, origin: CFrame, y0: number, h: number, r: number, color: Color3, material: Enum.Material): Part
	local part = MapParts.newPart(name, Vector3.new(h, r * 2, r * 2),
		origin * CFrame.new(0, y0 + h * 0.5, 0) * CFrame.Angles(0, 0, math.pi / 2), color, material)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- Ein runder Stein auf dem Mantel eines Rings.
local function newGem(origin: CFrame, y: number, r: number, angle: number, diameter: number, color: Color3, material: Enum.Material, parent: Instance)
	local dir = Vector3.new(math.sin(angle), 0, math.cos(angle))
	local pos = origin:PointToWorldSpace(Vector3.new(0, y, 0) + dir * (r + diameter * 0.05))
	local out = origin:VectorToWorldSpace(dir)
	local gem = MapParts.newPart("Gem", Vector3.new(diameter, diameter * 1.15, diameter * 0.3),
		CFrame.lookAt(pos, pos + out), color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent   = gem
	finish(gem, parent)
end

-- Baut Koerper, Gurte, Steine und Schimmer. Gibt die Wurzel (den Eikoerper)
-- zurueck; sie traegt Attribut und Touch-Kontakt (siehe buildLaidEgg), alle
-- anderen Teile haengen als Kinder daran.
local function buildEggBody(name: string, eggId: string, origin: CFrame, width: number, height: number, parent: Instance): Part
	local look   = EggLook.get(eggId)
	local matte  = Enum.Material.SmoothPlastic
	local trim   = if look.neon then Enum.Material.Neon elseif look.pattern == "band" then Enum.Material.Metal else matte

	-- Schlichter Koerper (Kugel-Mesh): das feine Ei-Mesh legt der Client
	-- darueber (LaidEggMeshController); ohne Client-Mesh bleibt die Kugel.
	local root = MapParts.newPart(name, Vector3.new(width, height, width),
		origin * CFrame.new(0, height * 0.5, 0), look.base, matte)
	local sphere = Instance.new("SpecialMesh")
	sphere.MeshType = Enum.MeshType.Sphere
	sphere.Parent   = root
	root.Parent     = parent
	CollectionService:AddTag(root, "LaidEggBody")

	root.CanCollide = false

	-- Gurte an den Naehten (Kanten 2 bis 4 der Stufen)
	local seams: { number } = {}
	if look.pattern == "band" then
		seams = { 3 }
	elseif look.pattern == "stripes" then
		seams = { 2, 3, 4 }
	elseif look.neon then
		seams = { 2, 4 }
	end
	for _, edge in seams do
		local t = EggMesh.TIER_EDGES[edge]
		finish(newRing("Band", origin, t * height - height * 0.02, height * 0.04,
			EggMesh.radius(t) * width * 0.985 + width * 0.01, look.accent, trim), root)
	end

	-- Steine / Punkte auf dem Bauch (Hoehe 0,41)
	local gemColor = if look.pattern == "band" then Color3.fromRGB(235, 40, 60) else look.accent
	local gemMat   = if look.pattern == "band" or look.neon then Enum.Material.Neon else matte
	if look.pattern == "spots" or look.neon or look.pattern == "band" then
		local count = if look.pattern == "band" then 2 else 3
		local size  = if look.pattern == "spots" then width * 0.26 elseif look.pattern == "band" then width * 0.15 else width * 0.14
		local t     = if look.pattern == "band" then 0.41 else 0.38
		local r     = EggMesh.radius(t) * width * 0.97
		for k = 1, count do
			newGem(origin, t * height, r, (k - 1) * (2 * math.pi / count) + 0.4, size, gemColor, gemMat, root)
		end
	end

	-- Schimmer am Boden und Funken bei seltenen Eiern
	if look.glow then
		root.Reflectance = 0.08
		local disc = MapParts.newPart("Glow", Vector3.new(0.05, width * 1.25, width * 1.25),
			origin * CFrame.new(0, 0.03, 0) * CFrame.Angles(0, 0, math.pi / 2),
			look.base:Lerp(look.accent, 0.5), Enum.Material.Neon)
		disc.Shape        = Enum.PartType.Cylinder
		disc.Transparency = 0.8
		finish(disc, root)

		local sparkle = Instance.new("ParticleEmitter")
		sparkle.Texture       = "rbxasset://textures/particles/sparkles_main.dds"
		sparkle.Color         = ColorSequence.new(look.accent)
		sparkle.Size          = NumberSequence.new(0.35, 0)
		sparkle.Lifetime      = NumberRange.new(0.9, 1.5)
		sparkle.Rate          = SPARKLE_RATE
		sparkle.Speed         = NumberRange.new(0.4, 1)
		sparkle.SpreadAngle   = Vector2.new(180, 180)
		sparkle.LightEmission = 1
		sparkle.Parent        = root
	end

	return root
end



-- Kleine Pruefsumme der uid fuer eine stabile Drehung: jedes Ei zeigt sein
-- Muster in eine andere Richtung, aber immer in dieselbe, solange es liegt
-- (der Plot wird bei jeder Aenderung neu gebaut).
local function yawFor(uid: string): number
	local sum = 0
	for index = 1, #uid do
		sum = (sum * 31 + string.byte(uid, index)) % 6283
	end
	return sum / 1000
end

-- Ein gelegtes Ei in der Welt. Eingesammelt wird es, indem die Spielfigur des
-- BESITZERS hindurchlaeuft (Touched) — kein Klick mehr noetig.
--
-- Warum Touched statt ClickDetector: ein Ei anzuklicken heisst erst zielen,
-- dann treffen — bei bis zu zwoelf Eiern auf einem Plot ist das umstaendlich.
-- Der Spieler laesst seinen Baerchi ohnehin standig zum Honig-Teich und
-- zurueck laufen (siehe BaerchiAutopilotService) und hinterlaesst dabei eine
-- Spur aus Eiern — die sollen von selbst eingesammelt werden, sobald man
-- durchlaeuft.
--
-- Server-autoritativ, wie ueberall im Projekt: der Touch-Kontakt loest nicht
-- direkt EggLayService.collect aus (MapService kennt EggLayService nicht,
-- Ringschluss-Gefahr — siehe _collectHandler), sondern ruft nur den
-- eingehaengten Handler auf. Der entscheidet autoritativ, ob das Ei noch da
-- ist und wem es gehoert.
function LaidEggBuilder.buildLaidEgg(parent: Instance, egg: Types.LaidEgg, worldFoot: Vector3, owner: Player): Part?
	local def = EggConfig.data[egg.eggType]
	if not def then
		-- Ei-Typ aus der Config entfernt: still ueberspringen. Ein Ei ohne
		-- Farbe und Namen zu bauen waere schlimmer als keines.
		return nil
	end

	local size   = EggConfig.LAY_EGG_SIZE
	local width  = size.X * EGG_SCALE
	local height = size.Y * EGG_SCALE
	local look   = EggLook.get(egg.eggType)
	local origin = CFrame.new(worldFoot) * CFrame.Angles(0, yawFor(egg.uid), 0)

	-- Wurzel: der breiteste Ring. Er traegt Attribut und Touch-Kontakt; alle
	-- anderen Teile haengen als Kinder daran und verschwinden mit ihm.
	local part = buildEggBody("LaidEgg_" .. egg.uid, egg.eggType, origin, width, height, parent)
	part.CanTouch   = true    -- man soll durch Eier laufen koennen, nicht ueber sie stolpern (CanCollide bleibt aus)
	part.CanQuery   = true
	part.CastShadow = true

	part:SetAttribute(LaidEggBuilder.LAID_EGG_ATTRIBUTE, egg.uid)

	-- Nur EIN erfolgreicher Touch-Kontakt darf einsammeln: Touched feuert
	-- fuer jeden Frame, in dem die Figur noch im Part steckt, erneut. Ohne
	-- diese Sperre wuerde derselbe Durchlauf den Handler viele Male aufrufen
	-- (harmlos, weil EggLayService.collect bei einem bereits entfernten Ei
	-- einfach nichts tut — aber unnoetige Anfragen).
	local collected = false
	local touchConnection: RBXScriptConnection? = nil
	touchConnection = part.Touched:Connect(function(hit: BasePart)
		if collected then return end

		local character = hit.Parent
		if not character then return end

		local toucher = Players:GetPlayerFromCharacter(character)
		if not toucher then return end

		-- Nur der Besitzer des Plots sammelt sein eigenes Ei ein — ein
		-- durchlaufender Nachbar soll fremde Eier nicht mitnehmen koennen.
		if toucher ~= owner then return end

		collected = true
		if touchConnection then
			touchConnection:Disconnect()
		end

		-- Partikel-Stoss in der Ei-Farbe AN WORKSPACE, nicht am "LaidEggs"-
		-- Ordner: der wird gleich durch den Datenwechsel neu aufgebaut
		-- (renderLaidEggs zerstoert ihn komplett), der Burst soll das
		-- ueberleben statt mitten in der Animation zu verschwinden.
		FigureFX.burstAt(part.Position, look.base, workspace)

		local handler = _collectHandler
		if handler then
			handler(toucher, egg.uid)
		end
	end)

	local billboard = Instance.new("BillboardGui")
	billboard.Name        = "Label"
	billboard.Size        = UDim2.fromScale(4.4, 1.3)
	billboard.StudsOffset = Vector3.new(0, height * 0.58 + 0.5, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = EggConfig.LAY_LABEL_DISTANCE
	billboard.Adornee     = part
	billboard.Parent      = part

	local label = MapParts.newTextLabel("Name", billboard, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0))
	WorldText.set(label, Names.msg.eggShort(def.id))
	label.TextColor3       = Color3.new(1, 1, 1)
	label.TextStrokeColor3 = look.base:Lerp(Color3.new(0, 0, 0), 0.65)
	label.TextStrokeTransparency = 0

	return part
end

-- Baut ALLE herumliegenden Eier eines Plots neu.
--
-- Bewusst komplett neu statt einzeln nachzupflegen: es sind hoechstens
-- EggConfig.MAX_UNCOLLECTED_EGGS Stueck (zwoelf kleine Kugeln), und der
-- Vergleich "welches Ei ist neu, welches wurde eingesammelt" waere mehr Code
-- als der gesamte Neuaufbau. Die Baerchi-Figuren sind der Fall, wo sich der
-- Aufwand lohnt — ein Mesh ist um Groessenordnungen teurer als eine Kugel.
--
-- Die Positionen in den Daten sind PLOT-RELATIV (siehe Types.LaidEgg): hier
-- werden sie in Weltkoordinaten zurueckgerechnet.
function LaidEggBuilder.renderLaidEggs(plotModel: Model, slot: number, islandData: Types.IslandData, owner: Player)
	local old = plotModel:FindFirstChild("LaidEggs")
	if old then old:Destroy() end

	local folder = Instance.new("Folder")
	folder.Name   = "LaidEggs"
	folder.Parent = plotModel

	-- Typisiert statt direkt aus islandData gelesen: ein Datenpaket von einem
	-- aelteren Serverstand haette das Feld nicht, und ohne die Annotation
	-- verliert die Schleife darunter den Typ.
	local eggs: { Types.LaidEgg } = islandData.laidEggs or {}
	if #eggs == 0 then
		return
	end

	local plotCFrame = MapParts.plotCFrame(slot)
	if not plotCFrame then return end

	for _, egg in eggs do
		local worldFoot = plotCFrame:PointToWorldSpace(Vector3.new(egg.x, egg.y, egg.z))
		LaidEggBuilder.buildLaidEgg(folder, egg, worldFoot, owner)
	end
end

return LaidEggBuilder
