--!strict
-- CombService.luau
-- ServerScriptService/Services/CombService.luau
--
-- Einzige Zustaendigkeit:
--   - Honigwaben im Event-Pit: entstehen lassen, vom Spieler aufsammeln lassen,
--     als Stapel ueber seinem Kopf zeigen, ihn innerhalb des Pits verlangsamen
--     und den Stapel abgeben, sobald er seine eigene Insel betritt.
--
-- Was mit den abgegebenen Waben passiert (Warteschlange, Gummies, Ausbau),
-- gehoert CombRecyclerService. Dieser Service reicht sie nur dorthin durch
-- (CombRecyclerService.deposit) und kennt weder Gummies noch den Spielstand.
--
-- Was ein Spieler gerade TRAEGT, ist bewusst kein Spielstand: es lebt nur hier,
-- im Arbeitsspeicher, und geht beim Tod oder Verlassen verloren. Das haelt das
-- Sammeln spannend (nicht im Pit sterben!) und erspart dem DataStore eine
-- Zahl, die sich zehnmal pro Sekunde aendert. Alle Zahlen: Config/CombConfig.
--
-- WARUM DER SERVER DAS ALLES MACHT: Der Stapel soll fuer ALLE sichtbar sein
-- (jeder sieht, wer schwer beladen durchs Pit schleicht), und das Einsammeln
-- darf kein Client behaupten koennen. Der Server prueft deshalb im Takt
-- (PICKUP_CHECK_SECONDS) die Position jedes Spielers gegen die Waben — ein
-- Touched-Event pro Wabe waere bei bis zu 40 Waben und 8 Spielern unzuverlaessiger
-- und teurer.
--
-- Anzeige beim Client: Player-Attribute "CombsCarried" / "CombsMax" / "CombsUnits"
-- (CombController zeigt sie an) und das Remote CombDelivered fuer die Abgabe.
--
-- NACHSCHUB (Slot-Modell, Rechnung in Util/CombSlots): eine aufgehobene Wabe
-- behaelt ihren Slot. Erst die Abgabe (deliver) oder der Verlust eines Stapels
-- traegt sie in die Respawn-Warteschlange ein; ein Takt-Loop spawnt faellige
-- Waben, fuellt freie Slots nach und laesst bei fast leerem Pit troepfeln.
-- Die Abgabe kennt dieser Service selbst (er ruft CombRecyclerService.deposit),
-- deshalb plant er den Respawn hier ein: kein Rueckruf vom Recycler noetig,
-- kein Zirkelbezug.
--
-- WABENTHEMEN (CombConfig.THEMES): ein Event setzt per setTheme/clearTheme ein
-- Thema (Lava im Hot Egg, Koenigsgelee beim Boss). Das Thema bestimmt Skin,
-- Wert, Slot-Zahl, Nachschub-Tempo und Tragebremse. Der Wert einer Wabe wird
-- beim Aufheben festgeschrieben. launchCombs laesst Waben einfliegen
-- (Vulkan-Ausbruch, Waben-Regen): der Server legt Landepunkt und Flugzeit
-- fest und schreibt beides als Attribute, der Client zeichnet den Flug.

local Players             = game:GetService("Players")
local Workspace           = game:GetService("Workspace")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CombConfig = require(ReplicatedStorage.Config.CombConfig)
local BuildingBehavior = require(ReplicatedStorage.Config.BuildingBehavior)
local Remotes    = require(ReplicatedStorage.Network.Remotes)

local CombBuilder = require(ServerScriptService.Util.CombBuilder)
local CombSlots   = require(ServerScriptService.Util.CombSlots)

local MapService          = require(ServerScriptService.Services.MapService)
local CombRecyclerService = require(ServerScriptService.Services.CombRecyclerService)

local CombService = {}

--------------------------------------------------------------------------------
-- Zustand
--------------------------------------------------------------------------------

type WorldComb = {
	model       : Model,
	position    : Vector3,   -- Bodenpunkt unter der Wabe
	units       : number,
	isGold      : boolean,
	themeId     : string?,
	yaw         : number,
	phase       : number,
	availableAt : number,    -- os.clock(); fliegende Waben erst nach der Landung
}

type CarriedItem = { isGold: boolean, units: number, themeId: string?, slow: number }

type Carried = {
	items  : { CarriedItem },
	models : { Model },
	units  : number,
	folder : Folder?,
}

local WORLD_FOLDER_NAME = "EventPitCombs"
local STACK_FOLDER_NAME = "CombStack"

local _worldFolder: Folder? = nil
local _world: { WorldComb } = {}

local _carried: { [Player]: Carried } = {}

-- Fuer welche Spieler wir WalkSpeed veraendert haben. Nur dann fassen wir ihn
-- wieder an: ein Spieler, der nie Waben getragen hat, behaelt, was immer ein
-- anderes System ihm gesetzt hat.
local _slowed: { [Player]: boolean } = {}

local _random = Random.new()

-- Respawn-Warteschlange und Zeitgeber (Zeitbasis: os.clock, nur Server).
local _slots = CombSlots.new()

-- Aktives Wabenthema (CombConfig.THEMES), nil = normale Waben.
local _themeId: string? = nil

--------------------------------------------------------------------------------
-- Hilfen
--------------------------------------------------------------------------------

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function getCarried(player: Player): Carried
	local carried = _carried[player]
	if not carried then
		carried = { items = {}, models = {}, units = 0, folder = nil }
		_carried[player] = carried
	end
	return carried
end

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	if not character then return nil end
	return character:FindFirstChildOfClass("Humanoid")
end

local function publishCarried(player: Player)
	local carried = getCarried(player)
	player:SetAttribute("CombsCarried", #carried.items)
	player:SetAttribute("CombsMax", CombConfig.MAX_CARRY)
	player:SetAttribute("CombsUnits", carried.units)
end

-- Wie schnell der Spieler IM PIT mit diesem Stapel laeuft. Jede Wabe bremst
-- mit dem Wert ihres Themas (Lava ist schwerer).
local function pitWalkSpeed(carried: Carried): number
	local slow = 0
	for _, item in carried.items do
		slow += item.slow
	end
	local factor = math.max(CombConfig.MIN_SPEED_FACTOR, 1 - slow)
	return CombConfig.BASE_WALK_SPEED * factor
end

local function restoreSpeed(player: Player)
	if not _slowed[player] then return end
	_slowed[player] = nil

	local humanoid = getHumanoid(player)
	if humanoid then
		humanoid.WalkSpeed = CombConfig.BASE_WALK_SPEED
	end
end

--------------------------------------------------------------------------------
-- Waben in der Welt
--------------------------------------------------------------------------------

-- Wie viele Waben gerade auf Koepfen getragen werden (belegen ihre Slots).
local function heldTotal(): number
	local total = 0
	for _, carried in _carried do
		total += #carried.items
	end
	return total
end

-- Aktuelle Slot-Zahl (= Hoechstzahl im Pit).
local function currentLimit(): number
	local theme = CombConfig.getTheme(_themeId)
	return if theme then theme.limit else CombConfig.MAX_WORLD_COMBS
end

-- Abstand beim Nachfuellen freier Slots (ein Thema kann es beschleunigen).
local function refillInterval(): number
	local theme = CombConfig.getTheme(_themeId)
	local factor = if theme then math.max(0.1, theme.spawnRateFactor) else 1
	return CombConfig.SPAWN_INTERVAL_SECONDS / factor
end

local function tooCloseToOthers(position: Vector3): boolean
	for _, comb in _world do
		if flatDistance(comb.position, position) < CombConfig.SPAWN_MIN_DISTANCE then
			return true
		end
	end
	return false
end

-- Freie Stelle im Ring des Pits (gleichmaessig ueber die Flaeche, sqrt, sonst
-- klumpen die Waben in der Mitte), bis zu 8 Versuche gegen Ueberlappung.
local function findFreeGround(): Vector3?
	local center = MapService.getEventPitPosition()
	local minR2 = CombConfig.SPAWN_RADIUS_MIN * CombConfig.SPAWN_RADIUS_MIN
	local maxR2 = CombConfig.SPAWN_RADIUS_MAX * CombConfig.SPAWN_RADIUS_MAX

	for _ = 1, 8 do
		local radius = math.sqrt(minR2 + (maxR2 - minR2) * _random:NextNumber())
		local angle  = _random:NextNumber() * math.pi * 2
		local ground = Vector3.new(
			center.X + math.cos(angle) * radius,
			center.Y,
			center.Z + math.sin(angle) * radius
		)
		if not tooCloseToOthers(ground) then
			return ground
		end
	end
	return nil
end

-- Baut das Model einer Wabe im Pit (aktuelles Thema).
local function buildModel(comb: WorldComb): Model
	local model = CombBuilder.buildWorldComb(comb.position, comb.yaw, comb.isGold, comb.units, comb.phase, comb.themeId)
	-- Fuer den Auftauch-Effekt im Client (CombController), vor dem
	-- Einhaengen gesetzt, damit es mit dem Model ankommt.
	model:SetAttribute("SpawnTime", Workspace:GetServerTimeNow())
	return model
end

-- Legt eine neue Wabe auf `ground`. `flight` = Flug von `from` ueber
-- `seconds` (Client zeichnet ihn aus den Attributen, aufheben erst danach).
local function placeComb(ground: Vector3, flight: { from: Vector3, seconds: number }?): boolean
	local folder = _worldFolder
	if not folder then return false end

	-- Gold-Chance bleibt pro Spawn gleich (8 %), auch bei Respawn und Thema.
	local isGold = _random:NextNumber() < CombConfig.GOLD_CHANCE
	local comb: WorldComb = {
		model       = nil :: any,
		position    = ground,
		units       = CombConfig.getUnits(isGold, _themeId),
		isGold      = isGold,
		themeId     = _themeId,
		yaw         = _random:NextNumber() * math.pi * 2,
		phase       = _random:NextNumber() * math.pi * 2,
		availableAt = 0,
	}

	local model = buildModel(comb)
	if flight then
		local now = Workspace:GetServerTimeNow()
		model:SetAttribute("FlyFrom", flight.from)
		model:SetAttribute("FlyStart", now)
		model:SetAttribute("FlyEnd", now + flight.seconds)
		comb.availableAt = os.clock() + flight.seconds
	end
	model.Parent = folder
	comb.model = model

	table.insert(_world, comb)
	return true
end

local function spawnComb(): boolean
	if not _worldFolder then return false end
	if #_world >= currentLimit() then return false end

	local ground = findFreeGround()
	if not ground then return false end
	return placeComb(ground, nil)
end

-- Baut alle Waben im Pit mit dem aktuellen Thema neu (Skin + Wert).
local function reskinWorld()
	local folder = _worldFolder
	if not folder then return end
	for _, comb in _world do
		comb.themeId = _themeId
		comb.units   = CombConfig.getUnits(comb.isGold, _themeId)
		local old = comb.model
		local model = buildModel(comb)
		-- Kein Auftauch-Effekt beim Umfaerben: nur der Burst in der Mitte.
		model:SetAttribute("SpawnTime", 0)
		if comb.availableAt > os.clock() then
			for _, name in { "FlyFrom", "FlyStart", "FlyEnd" } do
				model:SetAttribute(name, old:GetAttribute(name))
			end
		end
		model.Parent = folder
		comb.model = model
		old:Destroy()
	end
end

local function removeWorldComb(index: number)
	local comb = _world[index]
	comb.model:Destroy()
	table.remove(_world, index)
end

--------------------------------------------------------------------------------
-- Der Stapel ueber dem Kopf
--------------------------------------------------------------------------------

local function ensureStackFolder(player: Player, carried: Carried): Folder?
	local character = player.Character
	if not character then return nil end

	local existing = carried.folder
	if existing and existing.Parent == character then
		return existing
	end

	local folder = Instance.new("Folder")
	folder.Name   = STACK_FOLDER_NAME
	folder.Parent = character
	carried.folder = folder
	return folder
end

local function clearStack(player: Player)
	local carried = _carried[player]
	if not carried then return end

	if carried.folder then
		carried.folder:Destroy()
	end
	carried.folder = nil
	table.clear(carried.items)
	table.clear(carried.models)
	carried.units = 0

	publishCarried(player)
end

-- Der Stapel geht verloren (Tod, Verlassen, neuer Charakter): seine Slots
-- werden nach ORPHAN_RELEASE_SECONDS frei, die Waben kommen ins Pit zurueck.
local function releaseOrphans(carried: Carried?)
	if not carried then return end
	local count = #carried.items
	if count > 0 then
		CombSlots.schedule(_slots, os.clock() + CombConfig.ORPHAN_RELEASE_SECONDS, count)
	end
end

local function loseStack(player: Player)
	releaseOrphans(_carried[player])
	clearStack(player)
end

local function addToStack(player: Player, comb: WorldComb): boolean
	local carried = getCarried(player)
	if #carried.items >= CombConfig.MAX_CARRY then return false end

	local character = player.Character
	local head = if character then character:FindFirstChild("Head") else nil
	if not head or not head:IsA("BasePart") then return false end

	local folder = ensureStackFolder(player, carried)
	if not folder then return false end

	-- Wert und Gewicht werden HIER festgeschrieben: endet das Thema, behaelt
	-- die getragene Wabe beides.
	table.insert(carried.items, {
		isGold  = comb.isGold,
		units   = comb.units,
		themeId = comb.themeId,
		slow    = CombConfig.getSlowPerComb(comb.themeId),
	})
	carried.units += comb.units

	local model = CombBuilder.buildStackComb(head, #carried.items, comb.isGold, folder, comb.themeId)
	table.insert(carried.models, model)

	publishCarried(player)
	return true
end

--------------------------------------------------------------------------------
-- Der Takt: aufsammeln, bremsen, abgeben
--------------------------------------------------------------------------------

local function tryPickup(player: Player, root: BasePart)
	local carried = getCarried(player)
	if #carried.items >= CombConfig.MAX_CARRY then return end

	-- v15: Recycler-Faehigkeit "Sammelradius" (BuildingBehavior.MILESTONES).
	local radius = CombConfig.PICKUP_RADIUS
	if BuildingBehavior.hasAbility("Recycler", CombRecyclerService.getLevel(player), "CollectRadius") then
		radius *= CombConfig.COLLECT_RADIUS_FACTOR
	end

	-- Rueckwaerts, weil beim Aufheben Eintraege aus der Liste verschwinden.
	local now = os.clock()
	for i = #_world, 1, -1 do
		local comb = _world[i]
		local dy = math.abs(root.Position.Y - comb.position.Y)

		if comb.availableAt <= now
			and dy <= CombConfig.PICKUP_MAX_HEIGHT
			and flatDistance(root.Position, comb.position) <= radius
		then
			if addToStack(player, comb) then
				removeWorldComb(i)
			end

			if #carried.items >= CombConfig.MAX_CARRY then return end
		end
	end
end

local function deliver(player: Player)
	local carried = getCarried(player)
	local count   = #carried.items
	local units   = carried.units
	if count == 0 then return end

	-- Erst abgeben, dann leeren: scheitert die Abgabe (Spieldaten noch nicht
	-- geladen), behaelt der Spieler seinen Stapel und es wird beim naechsten
	-- Takt erneut versucht.
	if not CombRecyclerService.deposit(player, units) then return end

	-- Jede abgegebene Wabe kommt nach der Respawn-Zeit zurueck ins Pit.
	local delay = CombConfig.getRespawnDelay(CombRecyclerService.getLevel(player))
	CombSlots.schedule(_slots, os.clock() + delay, count)

	clearStack(player)
	restoreSpeed(player)

	Remotes.CombDelivered:FireClient(player, count, units)
end

local function checkPlayer(player: Player)
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = getHumanoid(player)
	if not root or not root:IsA("BasePart") or not humanoid or humanoid.Health <= 0 then return end

	local carried = _carried[player]
	local count   = if carried then #carried.items else 0

	local center = MapService.getEventPitPosition()
	local inPit  = flatDistance(root.Position, center) <= MapService.getEventPitRadius()

	if inPit then
		tryPickup(player, root)
		count = #getCarried(player).items
	end

	-- Tempo: nur im Pit und nur mit Last. Ausserhalb wieder normal.
	if inPit and count > 0 then
		_slowed[player] = true
		humanoid.WalkSpeed = pitWalkSpeed(getCarried(player))
	else
		restoreSpeed(player)
	end

	-- Abgabe: eigene Insel betreten.
	if count > 0 then
		local plotCFrame = MapService.getPlotCFrame(player)
		if plotCFrame and flatDistance(root.Position, plotCFrame.Position) <= CombConfig.DELIVER_RADIUS then
			deliver(player)
		end
	end
end

--------------------------------------------------------------------------------
-- Spieler- und Charakter-Lebenszyklus
--------------------------------------------------------------------------------

local function hookCharacter(player: Player, character: Model)
	-- Neuer Charakter = leerer Stapel. Der alte Stapel haengt am alten
	-- Charakter und verschwindet mit ihm; hier nur die Buchfuehrung nachziehen.
	-- Hatte er noch Waben (Charakter ohne Tod ersetzt), werden die Slots frei.
	releaseOrphans(_carried[player])
	_carried[player] = { items = {}, models = {}, units = 0, folder = nil }
	_slowed[player] = nil
	publishCarried(player)

	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.Died:Connect(function()
			-- Wer im Pit stirbt, verliert seine Waben (siehe Kopf der Datei).
			loseStack(player)
			_slowed[player] = nil
		end)
	end
end

local function hookPlayer(player: Player)
	player.CharacterAdded:Connect(function(character)
		hookCharacter(player, character)
	end)

	if player.Character then
		task.spawn(hookCharacter, player, player.Character)
	else
		publishCarried(player)
	end
end

--------------------------------------------------------------------------------
-- Oeffentliche API
--------------------------------------------------------------------------------

-- Wie viele Waben liegen gerade im Pit (fuer Debug und Tests).
function CombService.getWorldCount(): number
	return #_world
end

-- Wie viele Waben dieser Spieler gerade traegt.
function CombService.getCarriedCount(player: Player): number
	local carried = _carried[player]
	return if carried then #carried.items else 0
end

-- Nur fuer den Studio-Test (DebugService): sofort `n` Waben ins Pit legen
-- (am Slot-Modell vorbei, aber nie ueber das Limit im Pit).
function CombService.debugSpawn(n: number)
	for _ = 1, n do
		spawnComb()
	end
end

-- Setzt das Wabenthema (CombConfig.THEMES[themeId]) oder hebt es auf (nil).
-- Bestehende Waben im Pit wechseln sofort Skin und Wert (ein Funken-Burst in
-- der Pit-Mitte); getragene behalten ihren Wert. Endet ein Thema mit mehr
-- Waben im Pit als normal erlaubt, verschwinden die ueberzaehligen (ihre Slots
-- gab es nur waehrend des Themas).
function CombService.setTheme(themeId: string?)
	if themeId and not CombConfig.getTheme(themeId) then
		warn("[CombService] Unbekanntes Wabenthema:", themeId)
		themeId = nil
	end
	if themeId == _themeId then return end

	local previous = CombConfig.getTheme(_themeId)
	_themeId = themeId

	local limit = currentLimit()
	while #_world > limit do
		removeWorldComb(_random:NextInteger(1, #_world))
	end

	reskinWorld()

	local theme = CombConfig.getTheme(themeId) or previous
	local folder = _worldFolder
	if theme and folder then
		local center = MapService.getEventPitPosition()
		CombBuilder.themeBurst(center + Vector3.new(0, 3, 0), theme.burstColor, folder)
	end
	print("[CombService] Wabenthema:", themeId or "normal", "| Slots", limit)
end

function CombService.clearTheme()
	CombService.setTheme(nil)
end

function CombService.getTheme(): string?
	return _themeId
end

-- Laesst bis zu `count` Waben einfliegen und landen (Vulkan-Ausbruch aus
-- `origin`, Waben-Regen von oben, wenn origin nil ist). Nie ueber das Limit im
-- Pit; die gelandeten Waben sind ganz normale Waben im Slot-Modell. Gibt die
-- Zahl der gestarteten Waben zurueck.
function CombService.launchCombs(count: number, origin: Vector3?): number
	local launched = 0
	for _ = 1, math.max(0, math.floor(count)) do
		if #_world >= currentLimit() then break end
		local ground = findFreeGround()
		if ground then
			local landing = ground + Vector3.new(0, CombConfig.WORLD_HOVER, 0)
			local from = origin or (landing + Vector3.new(0, CombConfig.RAIN_DROP_HEIGHT, 0))
			if placeComb(ground, { from = from, seconds = CombConfig.FLIGHT_SECONDS }) then
				launched += 1
			end
		end
	end
	return launched
end

-- Stand des Slot-Modells (fuer DebugService und Tests).
function CombService.getSlotInfo(): { world: number, held: number, queued: number, limit: number }
	return {
		world  = #_world,
		held   = heldTotal(),
		queued = CombSlots.pending(_slots),
		limit  = currentLimit(),
	}
end

-- Ein Takt des Nachschubs: so viele Waben spawnen, wie das Slot-Modell sagt.
local function respawnTick()
	local count = CombSlots.tick(_slots, {
		now            = os.clock(),
		world          = #_world,
		held           = heldTotal(),
		limit          = currentLimit(),
		refillInterval = refillInterval(),
		minWorld       = CombConfig.MIN_WORLD_COMBS,
		trickleSeconds = CombConfig.MIN_TRICKLE_SECONDS,
	})
	for _ = 1, count do
		spawnComb()
	end
end

function CombService.init()
	-- nichts anzumelden; alles Zeitabhaengige laeuft in start()
	print("[CombService] Initialisiert | max.", CombConfig.MAX_WORLD_COMBS, "Waben im Pit")
end

-- Erst in start(): dann steht die Welt (das Event-Pit baut MapService.init) und
-- Spieler werden geladen.
function CombService.start()
	local folder = Instance.new("Folder")
	folder.Name   = WORLD_FOLDER_NAME
	folder.Parent = Workspace
	_worldFolder  = folder

	for _ = 1, CombConfig.INITIAL_COMBS do
		spawnComb()
	end

	Players.PlayerAdded:Connect(hookPlayer)
	for _, player in Players:GetPlayers() do
		hookPlayer(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		releaseOrphans(_carried[player])
		_carried[player] = nil
		_slowed[player] = nil
	end)

	-- Nachschub (Slot-Modell): Respawn, Nachfuellen, Troepfeln
	task.spawn(function()
		while true do
			task.wait(CombConfig.RESPAWN_TICK_SECONDS)
			local ok, err = pcall(respawnTick)
			if not ok then
				warn("[CombService] Spawn fehlgeschlagen:", err)
			end
		end
	end)

	-- Aufsammeln, bremsen, abgeben
	task.spawn(function()
		while true do
			task.wait(CombConfig.PICKUP_CHECK_SECONDS)
			for _, player in Players:GetPlayers() do
				local ok, err = pcall(checkPlayer, player)
				if not ok then
					warn("[CombService] Pruefung fehlgeschlagen:", err)
				end
			end
		end
	end)
end

return CombService
