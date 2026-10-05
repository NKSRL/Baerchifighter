--!strict
-- SkyBuilder.luau
-- ServerScriptService/Util/MapBuild/SkyBuilder.luau
--
-- Einzige Zustaendigkeit:
--   - Himmel und Licht-Stimmung setzen: Atmosphaere, Sonne/Sterne, echte
--     Terrain-Wolken und die Lighting-Eigenschaften
--
-- Wird nur von WorldBuilder.buildGlobalLighting aufgerufen, einmal beim
-- Serverstart. Alle Zahlen in AmbienceConfig. Bloom, Farbkorrektur und
-- Sonnenstrahlen setzt weiterhin WorldBuilder (MapConfig.LIGHTING_*).
--
-- Warum keine Skybox-Bilder: ein Bild-Himmel braucht sechs hochgeladene
-- Texturen. Die Atmosphaere liefert denselben Effekt (Verlauf, Glanz an der
-- Sonne, Dunst am Horizont) ohne Asset, ohne Ladezeit und ohne Speicher.

local Lighting          = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AmbienceConfig = require(ReplicatedStorage.Config.AmbienceConfig)

local SkyBuilder = {}

local ATMOSPHERE_NAME = "BaerchiAtmosphere"
local SKY_NAME        = "BaerchiSky"

function SkyBuilder.build()
	-- Idempotent wie der Rest der Welt: ein zweiter Aufruf legt nichts doppelt an.
	if Lighting:FindFirstChild(ATMOSPHERE_NAME) then
		return
	end

	Lighting.ClockTime                = AmbienceConfig.CLOCK_TIME
	Lighting.Brightness               = AmbienceConfig.BRIGHTNESS
	Lighting.Ambient                  = AmbienceConfig.AMBIENT
	Lighting.OutdoorAmbient           = AmbienceConfig.OUTDOOR_AMBIENT
	Lighting.ColorShift_Top           = AmbienceConfig.COLOR_SHIFT_TOP
	Lighting.EnvironmentDiffuseScale  = AmbienceConfig.DIFFUSE_SCALE
	Lighting.EnvironmentSpecularScale = AmbienceConfig.SPECULAR_SCALE
	Lighting.ShadowSoftness           = AmbienceConfig.SHADOW_SOFTNESS
	Lighting.GeographicLatitude       = AmbienceConfig.GEO_LATITUDE

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Name    = ATMOSPHERE_NAME
	atmosphere.Density = AmbienceConfig.ATMOSPHERE_DENSITY
	atmosphere.Offset  = AmbienceConfig.ATMOSPHERE_OFFSET
	atmosphere.Color   = AmbienceConfig.ATMOSPHERE_COLOR
	atmosphere.Decay   = AmbienceConfig.ATMOSPHERE_DECAY
	atmosphere.Glare   = AmbienceConfig.ATMOSPHERE_GLARE
	atmosphere.Haze    = AmbienceConfig.ATMOSPHERE_HAZE
	atmosphere.Parent  = Lighting

	local sky = Instance.new("Sky")
	sky.Name             = SKY_NAME
	sky.StarCount        = AmbienceConfig.STAR_COUNT
	sky.SunAngularSize   = AmbienceConfig.SUN_SIZE
	sky.MoonAngularSize  = AmbienceConfig.MOON_SIZE
	sky.Parent           = Lighting

	-- Wolken haengen am Terrain-Objekt; es existiert in jedem Place.
	local terrain = workspace.Terrain
	if not terrain:FindFirstChildOfClass("Clouds") then
		local clouds = Instance.new("Clouds")
		clouds.Cover   = AmbienceConfig.CLOUDS_COVER
		clouds.Density = AmbienceConfig.CLOUDS_DENSITY
		clouds.Color   = AmbienceConfig.CLOUDS_COLOR
		clouds.Parent  = terrain
	end
end

return SkyBuilder
