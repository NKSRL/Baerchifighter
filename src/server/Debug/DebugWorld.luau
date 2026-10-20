--!strict
-- DebugWorld.luau
-- ServerScriptService/Debug/DebugWorld.luau
--
-- Studio-Testbefehle: Welt: Map-Stil, Screenshots, Tageszeit, Stimmungen.
-- Registriert sich beim require in DebugRegistry.commands; geladen nur von
-- DebugService.init() und nur in Studio (nie im Live-Spiel).

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local FeatureFlags              = require(ReplicatedStorage.Config.FeatureFlags)
local DebugRegistry = require(script.Parent.DebugRegistry)

local commands = DebugRegistry.commands

-- 20.10. Map-Stil V2. D:Invoke("mapstyle", "on" | "off" | "info")
--   on|off  Schalter MAP_STYLE_V2 fuer diese Studio-Sitzung, Bodenkacheln der Hauptinsel und Vegetation neu aufbauen
--   info    nur zaehlen: Teile gesamt, Mesh-Teile, Deko je Name, Dreiecke der Mesh-Teile, fehlende Vorlagen
commands.mapstyle = function(_player, _data, action: any)
	local MapMeshes      = require(ServerScriptService.Util.MapBuild.MapMeshes)
	local WorldBuilder   = require(ServerScriptService.Util.MapBuild.WorldBuilder)
	local MapStyleConfig = require(ReplicatedStorage.Config.MapStyleConfig)
	local act = tostring(action or "info")
	local note
	if act == "on" or act == "off" then
		FeatureFlags.FLAGS.MAP_STYLE_V2 = (act == "on")
		local tiles, veg = WorldBuilder.restyle()
		note = string.format("neu gebaut: %d Kacheln, %d Vegetationsteile (Plot-Beete beim naechsten Plot-Aufbau)", tiles, veg)
	elseif act ~= "info" then
		return { error = "mapstyle on|off|info" }
	end

	local counts: { [string]: number } = {}
	local total, meshParts, tris = 0, 0, 0
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") then
			total += 1
			if d:GetAttribute("MapStyle") == 2 then
				meshParts += 1
				tris += MapStyleConfig.TRIS[tostring(d:GetAttribute("MapTemplate"))] or 0
			end
			if d.Name == "GrassTile" or MapMeshes.VEGETATION_NAMES[d.Name] then
				counts[d.Name] = (counts[d.Name] or 0) + 1
			end
		end
	end

	local missing: { string } = {}
	for _, list in { MapStyleConfig.GROUND_TILES, MapStyleConfig.TREES, MapStyleConfig.BUSHES,
		MapStyleConfig.RIM_BUSHES, MapStyleConfig.ROCKS, MapStyleConfig.CRYSTALS } do
		for _, name in list do
			if not MapMeshes.template(name) then table.insert(missing, name) end
		end
	end

	return {
		schalter         = FeatureFlags.isOn("MAP_STYLE_V2"),
		hinweis          = note,
		teileGesamt      = total,
		meshTeile        = meshParts,
		meshDreiecke     = tris,
		dekoProName      = counts,
		fehlendeVorlagen = missing,
	}
end

-- Welt aufwerten: Debug-Signale an die Client-Controller (workspace-Attribute,
-- siehe WorldFXKit.onDebug). Ein Zaehler im Wert sorgt dafuer, dass derselbe
-- Befehl zweimal hintereinander auch zweimal ausloest.
local _worldSignal = 0
local function worldSignal(attribute: string, value: any)
	_worldSignal += 1
	workspace:SetAttribute(attribute, if value == nil then tostring(_worldSignal) else value)
end

commands.worldshots = function(_player, _data, index: any)
	local n = tonumber(index)
	if n == nil then
		local WorldFXConfig = require(ReplicatedStorage.Config.WorldFXConfig)
		local names = {}
		for _, shot in WorldFXConfig.WORLD_SHOTS do table.insert(names, shot.name) end
		return { hinweis = "worldshots <1..6> (0 = zurueck)", punkte = names }
	end
	_worldSignal += 1
	workspace:SetAttribute("DebugWorldShot", string.format("%d|%d", n, _worldSignal))
	return { punkt = n }
end

commands.daytime = function(_player, _data, hour: any)
	local h = tonumber(hour)
	workspace:SetAttribute("DebugDayTime", if h then h else -1)
	return { tageszeit = if h then h else "auto" }
end

commands.pitstate = function(_player, _data, state: any)
	local value = tostring(state or "auto")
	workspace:SetAttribute("DebugPitState", value)
	return { pit = value }
end

commands.neststate = function(_player, _data, state: any)
	local value = tostring(state or "auto")
	workspace:SetAttribute("DebugNestState", value)
	return { nest = value }
end

commands.arrival = function(_player, _data)
	worldSignal("DebugArrival", nil)
	return { ankunft = true }
end

commands.fish = function(_player, _data)
	worldSignal("DebugFish", nil)
	return { fisch = true }
end

-- Paket D: Insel-Stufe am Player-Attribut (wie PlotDisplayService), "auto"
-- rechnet sie aus dem Spielstand neu.
commands.islandstage = function(player, data, stage: any)
	local IslandStage = require(ReplicatedStorage.Modules.IslandStage)
	local n = tonumber(stage)
	local value = if n then math.clamp(math.floor(n), 1, IslandStage.MAX)
		else IslandStage.compute(data.towers and data.towers.records, data.rebirthCount or 0)
	player:SetAttribute("IslandStage", value)
	return { stufe = value }
end

-- Paket D: Teich voll (alle Honig-Lager voll, wie "honey"), damit der Ueberlauf laeuft
commands.pondfull = function(player, data)
	local result = commands.honey(player, data)
	return { teich = "voll", honig = result }
end

-- Paket E: Zuschauer-Baerchis an der eigenen Arena testen
commands.spectators = function(player, _data, mode: any)
	_worldSignal += 1
	workspace:SetAttribute("DebugSpectators", string.format("%d|%s|%d", player.UserId, tostring(mode or "hop"), _worldSignal))
	return { zuschauer = tostring(mode or "hop") }
end

-- Paket G: Welt-Moment wie vom Server erkannt an alle schicken (ohne den
-- Spielstand zu aendern). Erzwingt "gross", damit man jede Art sieht.
commands.moment = function(player, _data, kind: any, value: any)
	local WorldMomentService = require(ServerScriptService.Services.WorldMomentService)
	local k = tostring(kind or "hatch")
	local defaults = { hatch = "Cosmic", tower = "II", record = "I", rebirth = "1", mutation = "Galaxy" }
	local v = if value ~= nil then tostring(value) else defaults[k] or "?"
	WorldMomentService.announce(player, { kind = k :: any, value = v, number = 42 }, true)
	return { moment = k, wert = v }
end

-- Paket G: fuenf grosse Momente auf einmal (Client muss sie nacheinander zeigen)
commands.moments5 = function(player, _data)
	local WorldMomentService = require(ServerScriptService.Services.WorldMomentService)
	for _, m in { { "hatch", "Mythic" }, { "tower", "III" }, { "rebirth", "2" }, { "mutation", "Rainbow" }, { "hatch", "Omega" } } do
		WorldMomentService.announce(player, { kind = m[1] :: any, value = m[2], number = 2 }, true)
	end
	return { momente = 5 }
end

-- Paket E: Rekord-Moment am eigenen Schau-Turm
commands.record = function(player, _data)
	_worldSignal += 1
	workspace:SetAttribute("DebugRecord", string.format("%d|%d", player.UserId, _worldSignal))
	return { rekord = true }
end

return {}
