--!strict
-- WorldFXKit.luau
-- StarterPlayerScripts/Controllers/WorldFXKit.luau
--
-- Einzige Zustaendigkeit:
--   - Gemeinsame Bausteine der Welt-Controller ("Welt aufwerten"): Qualitaet,
--     Deko-Teile, Texturen mit Rueckfall, Distanz-Abschaltung, Debug-Signale
--
-- Kein eigener Takt, kein Zustand ausser der Liste der Distanz-Gruppen. Die
-- Controller (DayCycle, Water, Hub, WorldShot) rufen nur Funktionen auf.
--
-- PERFORMANCE-REGELN fuer alles, was hier entsteht:
--   * Anchored, ohne Kollision, Query, Touch und Schatten.
--   * Keine Light-Instanzen: Leuchten ueber Neon + Bloom.
--   * Distanz-Gruppen werden zweimal pro Sekunde geprueft (nicht pro Frame)
--     und mit Hysterese ein- und ausgehaengt (Parent), damit nichts flackert.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local AmbienceConfig = require(ReplicatedStorage.Config.AmbienceConfig)
local WorldFXConfig  = require(ReplicatedStorage.Config.WorldFXConfig)

local WorldFXKit = {}

--------------------------------------------------------------------------------
-- Qualitaet
--------------------------------------------------------------------------------

-- 1 = hoch, 0 = niedrig. Wie AmbienceController: Grafikstufe des Spielers,
-- "Automatisch" zaehlt als hoch. Einmal beim Start gelesen.
local _quality: number? = nil

function WorldFXKit.quality(): number
	local cached = _quality
	if cached then
		return cached
	end
	local ok, level = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel.Value
	end)
	local q = if not ok or level == 0 or level >= AmbienceConfig.HIGH_QUALITY_FROM then 1 else 0
	_quality = q
	return q
end

-- Laeuft die Funktion `name` (WorldFXConfig.MIN_QUALITY) auf diesem Geraet?
function WorldFXKit.enabled(name: string): boolean
	local need = (WorldFXConfig.MIN_QUALITY :: any)[name]
	if need == nil then
		warn("[WorldFXKit] unbekannte Funktion in MIN_QUALITY:", name)
		return false
	end
	return WorldFXKit.quality() >= need
end

--------------------------------------------------------------------------------
-- Texturen
--------------------------------------------------------------------------------

-- Hochgeladene ID oder nil.
function WorldFXKit.textureId(name: string): string?
	local id = WorldFXConfig.TEXTURE_IDS[name]
	if id and id ~= "" then
		return id
	end
	return nil
end

-- Bild fuer einen Partikel-Emitter: hochgeladen, sonst eingebauter Rueckfall,
-- sonst nil. Zweiter Wert: ob es das (2x2-)Flipbook ist.
function WorldFXKit.particleTexture(name: string): (string?, boolean)
	local id = WorldFXKit.textureId(name)
	if id then
		return id, WorldFXConfig.FLIPBOOKS[name] == true
	end
	return WorldFXConfig.TEXTURE_FALLBACK[name], false
end

-- Setzt Bild (und ggf. Flipbook-Layout) eines Emitters. Gibt false zurueck,
-- wenn es weder Bild noch Rueckfall gibt (Aufrufer laesst den Effekt weg).
function WorldFXKit.applyParticleTexture(emitter: ParticleEmitter, name: string): boolean
	local image, flipbook = WorldFXKit.particleTexture(name)
	if not image then
		return false
	end
	emitter.Texture = image
	if flipbook then
		emitter.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid2x2
		emitter.FlipbookMode   = Enum.ParticleFlipbookMode.Loop
		emitter.FlipbookFramerate = NumberRange.new(8, 10)
		emitter.FlipbookStartRandom = true
	end
	return true
end

--------------------------------------------------------------------------------
-- Deko-Teile
--------------------------------------------------------------------------------

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))
WorldFXKit.UPRIGHT = UPRIGHT

function WorldFXKit.part(
	name: string,
	parent: Instance?,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material?,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Name          = name
	part.Anchored      = true
	part.CanCollide    = false
	part.CanQuery      = false
	part.CanTouch      = false
	part.CastShadow    = false
	part.Size          = size
	part.CFrame        = cframe
	part.Color         = color
	part.Material      = material or Enum.Material.SmoothPlastic
	part.Shape         = shape or Enum.PartType.Block
	part.TopSurface    = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent        = parent
	return part
end

-- Senkrechter Zylinder: Fuss bei `base`, Hoehe `height`.
function WorldFXKit.pole(name: string, parent: Instance?, base: Vector3, height: number, diameter: number, color: Color3, material: Enum.Material?): Part
	return WorldFXKit.part(name, parent, Vector3.new(height, diameter, diameter),
		CFrame.new(base + Vector3.new(0, height * 0.5, 0)) * UPRIGHT, color, material, Enum.PartType.Cylinder)
end

function WorldFXKit.ball(name: string, parent: Instance?, diameter: number, position: Vector3, color: Color3, material: Enum.Material?): Part
	return WorldFXKit.part(name, parent, Vector3.one * diameter, CFrame.new(position), color, material, Enum.PartType.Ball)
end

-- Laenglicher Koerper (Fisch, Biene, Wespe): Block mit Kugel-Mesh. Ein Ball-
-- Teil wird von Roblox auf gleiche Achsen gezwungen, das Mesh nicht.
function WorldFXKit.ellipsoid(name: string, parent: Instance?, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local part = WorldFXKit.part(name, parent, size, cframe, color, material)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- Unsichtbarer Anker fuer einen Emitter (Box-Form, Groesse = Spawn-Volumen).
function WorldFXKit.anchor(name: string, parent: Instance?, size: Vector3, position: Vector3): Part
	local part = WorldFXKit.part(name, parent, size, CFrame.new(position), Color3.new(1, 1, 1))
	part.Transparency = 1
	return part
end

function WorldFXKit.folder(name: string, parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

-- Gemeinsamer Wurzelordner aller Welt-Effekte (lokal, wird nie repliziert).
local _root: Folder? = nil
function WorldFXKit.root(): Folder
	local root = _root
	if root and root.Parent then
		return root
	end
	local created = WorldFXKit.folder("WorldFX_Local", workspace)
	_root = created
	return created
end

--------------------------------------------------------------------------------
-- Distanz-Abschaltung
--------------------------------------------------------------------------------
-- Eine Gruppe ist ein Container (Folder/Model) mit Mittelpunkt und
-- Sichtweite. Ist die Kamera weiter weg als `distance`, wird der Container
-- aus der Welt genommen (Parent = nil); naeher als 90 % davon kommt er
-- zurueck. `onChange(visible)` erlaubt dem Controller, seinen Takt fuer die
-- Gruppe auszusetzen.

type Group = { container: Instance, parent: Instance, center: Vector3, distance: number, visible: boolean, onChange: ((boolean) -> ())? }

local _groups: { Group } = {}
local _cullStarted = false
local CULL_TICK = 0.5
local HYSTERESIS = 0.9

local function cullOnce()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local eye = camera.CFrame.Position
	for _, group in _groups do
		local d = (group.center - eye).Magnitude
		local want = if group.visible then d <= group.distance else d <= group.distance * HYSTERESIS
		if want ~= group.visible then
			group.visible = want
			group.container.Parent = if want then group.parent else nil
			local cb = group.onChange
			if cb then
				task.spawn(cb, want)
			end
		end
	end
end

-- Meldet eine Gruppe an. Rueckgabe: Funktion zum Abmelden (der Container wird
-- dabei NICHT zerstoert, das macht der Aufrufer).
function WorldFXKit.cullGroup(container: Instance, center: Vector3, distance: number, onChange: ((boolean) -> ())?): () -> ()
	local group: Group = {
		container = container,
		parent = container.Parent or WorldFXKit.root(),
		center = center,
		distance = distance,
		visible = true,
		onChange = onChange,
	}
	table.insert(_groups, group)

	if not _cullStarted then
		_cullStarted = true
		local acc = 0
		RunService.Heartbeat:Connect(function(dt: number)
			acc += dt
			if acc >= CULL_TICK then
				acc = 0
				cullOnce()
			end
		end)
	end
	cullOnce()

	return function()
		local index = table.find(_groups, group)
		if index then
			table.remove(_groups, index)
		end
	end
end

-- Ist die Gruppe des Containers gerade sichtbar? (Fuer Takte, die sparen wollen.)
function WorldFXKit.isShown(container: Instance): boolean
	return container.Parent ~= nil
end

--------------------------------------------------------------------------------
-- Debug-Signale (nur Studio)
--------------------------------------------------------------------------------
-- DebugService setzt Attribute an workspace (repliziert an alle Test-Clients).
-- Name → Rueckruf bei jeder Aenderung, mit dem aktuellen Wert.
-- `isState` = true: ein schon gesetzter Wert gilt auch fuer einen spaeter
-- beitretenden Test-Client (Zustaende wie "daytime"). false: nur ein
-- Ausloeser (Fisch, Ankunft, Kamera), ein alter Wert wird beim Start ignoriert.

function WorldFXKit.onDebug(attribute: string, callback: (any) -> (), isState: boolean?)
	if not RunService:IsStudio() then
		return
	end
	workspace:GetAttributeChangedSignal(attribute):Connect(function()
		callback(workspace:GetAttribute(attribute))
	end)
	local current = workspace:GetAttribute(attribute)
	if current ~= nil and isState ~= false then
		task.defer(callback, current)
	end
end

--------------------------------------------------------------------------------
-- Mathe
--------------------------------------------------------------------------------

function WorldFXKit.lerpColor(a: Color3, b: Color3, t: number): Color3
	return a:Lerp(b, math.clamp(t, 0, 1))
end

return WorldFXKit
