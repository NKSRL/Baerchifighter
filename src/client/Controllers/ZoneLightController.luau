--!strict
-- ZoneLightController.luau
-- StarterPlayerScripts/Controllers/ZoneLightController.luau
--
-- Einzige Zustaendigkeit:
--   - Licht-Feinschliff nach Ort (Paket I, "Welt aufwerten"): auf der Insel
--     wie bisher; auf dem Steg zur Arena und in der Arena etwas mehr
--     Kontrast und Saettigung; hoch oben auf dem Turm (ab Etage 30) klarere
--     Luft und weiterer Horizont
--
-- Wie es wirkt:
--   * Ein EIGENER Farbfilter "ZoneGrade" (nur Kontrast/Saettigung/eine Spur
--     Helligkeit, keine Farbe). Filter stapeln sich in Roblox: der Show-Filter
--     "SkillFX_Sky" und der Boss-Himmel faerben weiter wie bisher, ZoneGrade
--     ueberschreibt nichts und wird von nichts ueberschrieben.
--   * Die Atmosphaere fuehrt der Tageslauf; hier kommen nur Faktoren auf
--     Dichte und Dunst dazu (DayCycleController.setAtmosphereScale). Ist der
--     Tageslauf aus, setzt dieser Controller die festen Werte mal Faktor selbst.
--   * Uebergaenge ueber BLEND_SECONDS (1,5 s), nur Client.
--   * Bewusst KEINE Tiefenunschaerfe (DepthOfField) und keine anderen teuren
--     Effekte — auch nicht fuer PC.

local Lighting          = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

local AmbienceConfig = require(ReplicatedStorage.Config.AmbienceConfig)
local MapConfig      = require(ReplicatedStorage.Config.MapConfig)
local WorldFXConfig  = require(ReplicatedStorage.Config.WorldFXConfig)
local FeatureFlags   = require(ReplicatedStorage.Config.FeatureFlags)
local MapLayout      = require(ReplicatedStorage.Modules.MapLayout)

local WorldFXKit         = require(script.Parent.WorldFXKit)
local DayCycleController = require(script.Parent.DayCycleController)

local ZoneLightController = {}

-- 0..1: wie sehr die Kamera "in der Arena" ist (Arena-Insel oder aeusserer
-- Steg), mit weicher Kante.
local function arenaWeight(p: Vector3): number
	local cfg = WorldFXConfig.ZONE_LIGHT
	local best = 0
	local islandEdge = MapConfig.PLOT_RING_RADIUS + MapConfig.PLOT_ISLAND_RADIUS
	for slot = 1, MapConfig.PLOT_COUNT do
		local pit = MapLayout.pitCenter(slot)
		local d = math.sqrt((p.X - pit.X) ^ 2 + (p.Z - pit.Z) ^ 2)
		best = math.max(best, math.clamp((cfg.ARENA_RADIUS - d) / 15, 0, 1))
		-- aeusserer Steg: entlang der Steg-Achse zwischen Plot-Insel und Arena
		local o = MapLayout.outward(slot)
		local along = (p.X - MapConfig.CENTER.X) * o.X + (p.Z - MapConfig.CENTER.Z) * o.Z
		local across = math.abs((p.X - MapConfig.CENTER.X) * o.Z - (p.Z - MapConfig.CENTER.Z) * o.X)
		if along > islandEdge - 4 and along < islandEdge + MapConfig.ISLAND_GAP + 4 then
			best = math.max(best, math.clamp((MapConfig.BRIDGE_WIDTH - across) / 6, 0, 1))
		end
	end
	return best
end

local function highWeight(p: Vector3): number
	local cfg = WorldFXConfig.ZONE_LIGHT
	local y = p.Y - MapConfig.PLATFORM_TOP_Y
	return math.clamp((y - cfg.HIGH_FROM) / (cfg.HIGH_FULL - cfg.HIGH_FROM), 0, 1)
end

function ZoneLightController.init()
	if not (FeatureFlags.isOn("WORLD_I_ZONES") and WorldFXKit.enabled("zoneLight")) then return end
	local cfg = WorldFXConfig.ZONE_LIGHT

	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "ZoneGrade"
	grade.Parent = Lighting

	local arena, high = 0, 0
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc < cfg.TICK then return end
		local step = acc
		acc = 0
		local camera = workspace.CurrentCamera
		if not camera then return end
		local p = camera.CFrame.Position

		-- weich zum Ziel (exponentiell, ~BLEND_SECONDS)
		local k = math.clamp(step / cfg.BLEND_SECONDS * 2.5, 0, 1)
		arena += (arenaWeight(p) - arena) * k
		high += (highWeight(p) - high) * k

		local island, ar = cfg.island, cfg.arena
		grade.Saturation = island.saturation + (ar.saturation - island.saturation) * arena
		grade.Contrast   = island.contrast + (ar.contrast - island.contrast) * arena
		grade.Brightness = island.brightness + (ar.brightness - island.brightness) * arena

		local density = 1 + (cfg.HIGH_DENSITY - 1) * high
		local haze = 1 + (cfg.HIGH_HAZE - 1) * high
		if not DayCycleController.setAtmosphereScale(density, haze) then
			-- Tageslauf aus: feste Werte mal Faktor
			local atm = Lighting:FindFirstChild("BaerchiAtmosphere")
			if atm and atm:IsA("Atmosphere") then
				atm.Density = AmbienceConfig.ATMOSPHERE_DENSITY * density
				atm.Haze    = AmbienceConfig.ATMOSPHERE_HAZE * haze
			end
		end
	end)

	print("[ZoneLight] aktiv")
end

return ZoneLightController
