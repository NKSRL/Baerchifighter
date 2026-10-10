--!strict
-- WorldShotController.luau
-- StarterPlayerScripts/Controllers/WorldShotController.luau
--
-- Einzige Zustaendigkeit:
--   - Die sechs festen Kamerapunkte fuer Vorher-/Nachher-Screenshots
--     (Paket 0, "Welt aufwerten") anfahren und wieder freigeben
--
-- NUR IN STUDIO. Ausgeloest ueber den Debug-Befehl "worldshots"
-- (DebugService setzt workspace-Attribut "DebugWorldShot" = "<n>|<zaehler>").
-- n = 1..6: Kamera fest auf Punkt n, UI aus (saubere Bilder). n = 0: zurueck.
--
-- Die Punkte werden aus MapConfig/MapLayout GERECHNET, nicht als feste
-- Koordinaten gespeichert: wandert eine Insel, wandert der Bildpunkt mit, und
-- "vorher" und "nachher" zeigen trotzdem dieselbe Stelle der Welt.
-- Slot 1 = Plot bei 0 Grad (+X).

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AmbienceConfig = require(ReplicatedStorage.Config.AmbienceConfig)
local MapConfig     = require(ReplicatedStorage.Config.MapConfig)
local WorldFXConfig = require(ReplicatedStorage.Config.WorldFXConfig)
local MapLayout     = require(ReplicatedStorage.Modules.MapLayout)

local WorldFXKit = require(script.Parent.WorldFXKit)

local WorldShotController = {}

local localPlayer = Players.LocalPlayer

-- Wie MapParts.buildPlotCFrame (Server): Plot schaut zur Weltmitte.
local function plotCFrame(slot: number): CFrame
	local p = MapLayout.plotCenter(slot)
	return CFrame.lookAt(p, Vector3.new(MapConfig.CENTER.X, p.Y, MapConfig.CENTER.Z))
end

-- Die sechs Punkte: { Augenpunkt, Blickziel }.
function WorldShotController.shots(): { { eye: Vector3, target: Vector3 } }
	local slot = 1
	local plot = plotCFrame(slot)
	local surface = MapConfig.PLATFORM_TOP_Y + MapConfig.PLOT_SIZE.Y
	local mastTop = MapConfig.CENTER + Vector3.new(0, MapConfig.PLATFORM_TOP_Y + 30, 0)
	local outward = MapLayout.outward(slot)
	local pit = MapLayout.pitCenter(slot)
	local islandEdge = MapConfig.PLOT_RING_RADIUS + MapConfig.PLOT_ISLAND_RADIUS

	-- 1 Spawn → Honigmast (Augenhoehe ueber dem Spawn-Punkt)
	local spawn = plot * CFrame.new(MapConfig.PLAYER_SPAWN_OFFSET.X, 0, MapConfig.PLAYER_SPAWN_OFFSET.Z)
	local eye1 = spawn.Position + Vector3.new(0, surface + 5, 0)

	-- 2 Hauptinsel schraeg von oben (ganze Insel im Bild)
	local eye2 = MapConfig.CENTER + Vector3.new(-150, 150, -150)

	-- 3 Plot-Insel aus Spielerhoehe: hinter dem Baerchi-Platz, Blick auf den Brunnen
	local pond = plot * CFrame.new(MapLayout.pondOffset())
	local facing = plot:VectorToWorldSpace(MapLayout.pondFacing())
	local eye3 = pond.Position + facing * 22 + Vector3.new(0, surface + 5.5, 0)
	local target3 = pond.Position + Vector3.new(0, surface + 1.5, 0)

	-- 4 Auf dem Steg zur Arena, Blick auf die Arena
	local eye4 = MapConfig.CENTER + outward * (islandEdge + 4) + Vector3.new(0, MapConfig.PLATFORM_TOP_Y + 5.5, 0)
	local target4 = pit + Vector3.new(0, 4, 0)

	-- 5 Arena mit Turm (seitlich, erhoeht)
	local side = MapLayout.side(slot)
	local eye5 = pit - outward * 30 + side * 45 + Vector3.new(0, 32, 0)
	local target5 = pit + Vector3.new(0, 22, 0)

	-- 6 Vom Rand der Welt zum Horizont (zwischen zwei Stegen)
	local edge = MapLayout.atAngle(22.5, MapConfig.WATER_RADIUS - 60)
	local eye6 = edge + Vector3.new(0, 7, 0)
	local target6 = MapLayout.atAngle(22.5, AmbienceConfig.FAR_ISLAND_RING) + Vector3.new(0, 70, 0)

	return {
		{ eye = eye1, target = mastTop },
		{ eye = eye2, target = MapConfig.CENTER + Vector3.new(0, 4, 0) },
		{ eye = eye3, target = target3 },
		{ eye = eye4, target = target4 },
		{ eye = eye5, target = target5 },
		{ eye = eye6, target = target6 },
	}
end

local _savedFov: number? = nil
local _hiddenGuis: { ScreenGui } = {}

local function release()
	local camera = workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
		local fov = _savedFov
		if fov then camera.FieldOfView = fov end
	end
	_savedFov = nil
	for _, gui in _hiddenGuis do
		gui.Enabled = true
	end
	table.clear(_hiddenGuis)
end

local function show(index: number)
	local camera = workspace.CurrentCamera
	local shot = WorldShotController.shots()[index]
	local meta = WorldFXConfig.WORLD_SHOTS[index]
	if not (camera and shot and meta) then return end

	if not _savedFov then
		_savedFov = camera.FieldOfView
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(shot.eye, shot.target)
	camera.FieldOfView = meta.fov

	-- UI aus fuer saubere Bilder
	if #_hiddenGuis == 0 then
		for _, gui in localPlayer:WaitForChild("PlayerGui"):GetChildren() do
			if gui:IsA("ScreenGui") and gui.Enabled then
				gui.Enabled = false
				table.insert(_hiddenGuis, gui)
			end
		end
	end
	print(string.format("[WorldShot] %s | jetzt Screenshot machen, zurueck mit worldshots 0", meta.name))
end

function WorldShotController.init()
	WorldFXKit.onDebug("DebugWorldShot", function(value: any)
		if typeof(value) ~= "string" then return end
		local n = tonumber(string.match(value, "^(%d+)")) or 0
		if n >= 1 and n <= #WorldFXConfig.WORLD_SHOTS then
			show(n)
		else
			release()
		end
	end, false)
end

return WorldShotController
