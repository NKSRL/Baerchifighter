--!strict
-- DebugBridge.luau
-- ServerScriptService/Debug/DebugBridge.luau
--
-- Studio-Testbefehl (Welt 1, Paket 1): laeuft mit JEDEM Pet (alle Eintraege von BaerchiConfig.data) die Wege ueber
-- Stege ab und misst den Abstand Fusspunkt - Oberflaeche. Registriert sich beim require in DebugRegistry.commands;
-- geladen nur von DebugService.init() und nur in Studio.
--
--   D:Invoke("bridgetest")             -- alle Pets, Honigteich-Steg + Steg zur Mitte + Steg zur Arena, Hin und Zurueck
--   D:Invoke("bridgetest", "pond")     -- nur Honigteich ("event" / "arena" ebenso)
--   D:Invoke("bridgetest", "pond", "RedBaerchi")   -- nur dieses Pet
--   D:Invoke("bridgetest", "pond", "all", "old")   -- zum Vergleich: der alte Lauf (FigureWalker.walk, flache Hoehe)
--   D:Invoke("bridgetest", "all", "x", "route")    -- nur die Wegpunkte mit der Flaeche darunter
-- ACHTUNG: alle 28 Pets dauern einige Minuten (Befehlsleiste/Tool-Aufruf laeuft laenger als 60 s).
--
-- Soll: kleinster Abstand >= -0.1 (nichts steckt in der Oberflaeche), groesster <= 0.6 (ohne Huepfer, bobHeight = 0).
-- Aufraeumen: der Test baut nur Figuren in einen eigenen Ordner und entfernt sie wieder (Spielstand bleibt unveraendert).

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local RunService          = game:GetService("RunService")

local MapConfig      = require(ReplicatedStorage.Config.MapConfig)
local BaerchiConfig  = require(ReplicatedStorage.Config.BaerchiConfig)
local BaerchiFactory = require(ReplicatedStorage.Modules.BaerchiFactory)
local MapService     = require(ServerScriptService.Services.MapService)
local FigureBuilder  = require(ServerScriptService.Util.MapBuild.FigureBuilder)
local FigureWalker   = require(ServerScriptService.Util.FigureWalker)
local FigurePlacement = require(ServerScriptService.Util.FigurePlacement)
local PlotRoutes     = require(ServerScriptService.Util.PlotRoutes)
local DebugRegistry  = require(script.Parent.DebugRegistry)

local commands = DebugRegistry.commands

local MIN_OK = -0.1
local MAX_OK = 0.6
local TEST_SPEED = 45   -- schneller als im Spiel; die Hoehenfuehrung haengt nicht vom Tempo ab

type Stat = { min: number, max: number, samples: number, deep: number, worst: string, highest: string, rim: number }

local function newStat(): Stat
	return { min = math.huge, max = -math.huge, samples = 0, deep = 0, worst = "", highest = "", rim = math.huge }
end

-- Oberflaeche unter einem Fusspunkt: Strahl nach unten (Stege, Wiese, Beet) oder, am Honigteich, die
-- Steg-Planken des Brunnens (CanQuery = false, darum rechnerisch).
local function surfaceAt(p: Vector3, params: RaycastParams, planks: { BasePart }): (number, string)
	local best = -math.huge
	local what = ""
	-- Kein Boden: gelegte Eier, Figuren/Spieler, Zaun, Schilder. Solche Treffer werden uebersprungen.
	local skip: { Instance } = table.clone(params.FilterDescendantsInstances)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local origin = p + Vector3.new(0, 4, 0)
	for _ = 1, 8 do
		rp.FilterDescendantsInstances = skip
		local hit = workspace:Raycast(origin, Vector3.new(0, -12, 0), rp)
		if not hit then break end
		local inst = hit.Instance
		local model = inst:FindFirstAncestorOfClass("Model")
		local notGround = (model ~= nil and model:FindFirstChildOfClass("Humanoid") ~= nil)
			or string.find(inst.Name, "Fence") ~= nil or string.find(inst.Name, "Rail") ~= nil
			or inst:FindFirstAncestor("LaidEggs") ~= nil or inst:GetAttribute("BaerchiUid") ~= nil
		if notGround then
			table.insert(skip, inst)
		else
			best = hit.Position.Y
			what = inst:GetFullName()
			break
		end
	end
	-- Steg-Planken des Brunnens (CanQuery = false, darum rechnerisch)
	for _, plank in planks do
		local l = plank.CFrame:PointToObjectSpace(p)
		if math.abs(l.X) <= plank.Size.X * 0.5 and math.abs(l.Z) <= plank.Size.Z * 0.5 then
			local top = (plank.CFrame * Vector3.new(0, plank.Size.Y * 0.5, 0)).Y
			if top > best then best = top what = "Plank " .. plank.Name end
		end
	end
	return best, what
end

local function footOf(model: Model): Vector3
	local cf, size = model:GetBoundingBox()
	return Vector3.new(cf.Position.X, cf.Position.Y - size.Y * 0.5, cf.Position.Z)
end

-- Laeuft `points` ab und misst waehrend dessen jeden Frame.
-- transition: Aufstieg/Abstieg am Steg (zwei Punkte); dort zaehlt nur die Tiefe, nicht die Hoehe.
-- Auf den Stegen (Brett "...Bridge", Planken des Honigteichs) gilt die Vorgabe. Absaetze am Inselrand
-- (Wiese/Beet, 2 Studs Stufe) werden nur als Info gefuehrt (stat.rim).
local function walkAndMeasure(model: Model, points: { Vector3 }, old: boolean, params: RaycastParams, planks: { BasePart }, stat: Stat, transition: { Vector3 }?)
	local running = true
	local conn = RunService.Heartbeat:Connect(function()
		if not running then return end
		local foot = footOf(model)
		local ground, what = surfaceAt(foot, params, planks)
		if ground == -math.huge then return end
		local diff = foot.Y - ground
		stat.samples += 1
		if not (string.find(what, "Bridge") or string.find(what, "Plank")) then
			stat.rim = math.min(stat.rim, diff)
			return
		end
		if diff < stat.min then stat.worst = string.format("%s foot(%.1f, %.2f, %.1f) flaeche %.2f", what, foot.X, foot.Y, foot.Z, ground) end
		local inTransition = false
		if transition then
			local a, b = transition[1], transition[2]
			local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
			local t = Vector3.new(foot.X - a.X, 0, foot.Z - a.Z):Dot(ab) / math.max(ab:Dot(ab), 1e-6)
			inTransition = t >= -0.05 and t <= 1.05
		end
		stat.min = math.min(stat.min, diff)
		if diff < MIN_OK then stat.deep += 1 end
		if not inTransition then
			if diff > stat.max then stat.highest = string.format("%s foot(%.1f, %.2f, %.1f) flaeche %.2f", what, foot.X, foot.Y, foot.Z, ground) end
			stat.max = math.max(stat.max, diff)
		end
	end)
	if old then
		-- alter Lauf: nur Start und Ziel, Hoehe des Startpunkts gilt fuer den ganzen Weg
		FigureWalker.walk(model, points[1], points[#points], { speed = TEST_SPEED, bobHeight = 0 })
	else
		FigureWalker.walkPath(model, points, { speed = TEST_SPEED, bobHeight = 0 })
	end
	running = false
	conn:Disconnect()
end

local function reversed(points: { Vector3 }): { Vector3 }
	local out: { Vector3 } = {}
	for i = #points, 1, -1 do table.insert(out, points[i]) end
	return out
end

commands.bridgetest = function(player, _data, which: any, only: any, mode: any)
	local leg = tostring(which or "all")
	local old = mode == "old"
	local home = MapService.getBaerchiHome(player)
	local plotCFrame = MapService.getPlotCFrame(player)
	local pondStand = MapService.getPondPosition(player)
	if not home or not plotCFrame then return { error = "Plot nicht bereit" } end

	local folder = Instance.new("Folder")
	folder.Name = "_BridgeTest"
	folder.Parent = workspace

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { folder }
	for _, d in workspace:GetDescendants() do
		if d.Name == "Baerchis" and d:IsA("Folder") then table.insert(exclude, d) end   -- echte Figuren der Spieler
	end
	params.FilterDescendantsInstances = exclude

	-- Steg-Planken des Brunnens dieses Spielers
	local planks: { BasePart } = {}
	local fountain = workspace:FindFirstChild("Fountain", true)
	if fountain then
		for _, d in fountain:GetDescendants() do
			if d:IsA("BasePart") and string.sub(d.Name, 1, 11) == "Jetty_Plank" then table.insert(planks, d) end
		end
	end

	local ramp = MapService.getPondRampPoints(player)
	local bridgeOut = MapConfig.PLOT_ISLAND_RADIUS + MapConfig.ISLAND_GAP + 1
	local legs: { { name: string, there: { Vector3 }, planks: { BasePart } } } = {}
	if leg == "all" or leg == "pond" then
		if pondStand then
			local there: { Vector3 } = { home }
			for _, p in ramp do table.insert(there, p) end
			table.insert(there, pondStand)
			table.insert(legs, { name = "Honigteich", there = there, planks = planks })
		end
	end
	if leg == "all" or leg == "event" then
		local target = (plotCFrame * CFrame.new(0, 0, -(bridgeOut + 10))).Position
		table.insert(legs, { name = "Steg Mitte", there = PlotRoutes.route(plotCFrame, home, target), planks = {} })
	end
	if leg == "all" or leg == "arena" then
		local target = (plotCFrame * CFrame.new(0, 0, bridgeOut + 10)).Position
		table.insert(legs, { name = "Steg Arena", there = PlotRoutes.route(plotCFrame, home, target), planks = {} })
	end

	if mode == "route" then
		local lines: { string } = {}
		for _, l in legs do
			table.insert(lines, "== " .. l.name)
			for i, pt in l.there do
				local s, w = surfaceAt(pt, params, l.planks)
				table.insert(lines, string.format("%d (%.1f, %.2f, %.1f) flaeche %.2f %s", i, pt.X, pt.Y, pt.Z, s, w))
			end
		end
		folder:Destroy()
		return { zeilen = lines, fehler = {}, getestet = 0, modus = "route" }
	end

	local ids: { string } = {}
	for id in BaerchiConfig.data :: any do table.insert(ids, id :: string) end
	table.sort(ids)

	local rows: { string } = {}
	local fails: { string } = {}
	local tested = 0
	local lookAt = pondStand or home + Vector3.new(0, 0, 1)

	for _, id in ids do
		if typeof(only) == "string" and only ~= "all" and only ~= id then continue end
		local baerchi = BaerchiFactory.create(id, { level = 1 })
		if not baerchi then
			table.insert(fails, id .. ": BaerchiFactory.create = nil")
			continue
		end
		local facing = CFrame.lookAt(home, Vector3.new(lookAt.X, home.Y, lookAt.Z))
		local figure = FigureBuilder.buildBaerchiFigure(folder, baerchi, home, facing)
		if not figure then
			table.insert(fails, id .. ": keine Figur")
			continue
		end
		FigurePlacement.place(figure, home, facing.Rotation)
		tested += 1

		for _, l in legs do
			local stat = newStat()
			local ok, err = pcall(function()
				local trans = if l.name == "Honigteich" and #ramp >= 2 then { ramp[1], ramp[2] } else nil
				walkAndMeasure(figure, l.there, old, params, l.planks, stat, trans)
				walkAndMeasure(figure, reversed(l.there), old, params, l.planks, stat, trans)
			end)
			if not ok then
				table.insert(fails, id .. " / " .. l.name .. ": Fehler " .. tostring(err))
			else
				local pass = stat.min >= MIN_OK and stat.max <= MAX_OK
				table.insert(rows, string.format("%-18s %-11s min %+.2f  max %+.2f  Rand-min %+.2f  tief %d/%d  %s  %s",
					id, l.name, stat.min, stat.max, stat.rim, stat.deep, stat.samples, if pass then "OK" else "FEHLER",
					if pass then "" else (if stat.min < MIN_OK then "TIEF: " .. stat.worst else "HOCH: " .. stat.highest)))
				if not pass then table.insert(fails, id .. " / " .. l.name) end
			end
		end
		figure:Destroy()
	end

	folder:Destroy()
	return { getestet = tested, fehler = fails, zeilen = rows, modus = if old then "alt" else "neu" }
end

return {}
