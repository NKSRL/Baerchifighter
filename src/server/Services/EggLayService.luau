--!strict
-- EggLayService.luau
-- ServerScriptService/Services/EggLayService.luau
--
-- Einzige Zustaendigkeit:
--   - Den ausgeruesteten Baerchi regelmaessig ein Ei dort ablegen lassen, wo
--     er gerade steht
--   - Diese Eier einsammeln lassen (dann landen sie im Lager und sind
--     ausbruetbar)
--
-- ============================================================
-- WIE DAS LEGEN GETAKTET IST
-- ============================================================
-- Wie bei den Honig-Gebaeuden laeuft KEIN Timer pro Ei. Stattdessen steht auf
-- der Insel eine Zeitmarke (island.lastEggAt), und wie viele Eier faellig sind,
-- wird daraus nachgerechnet. Das hat drei Vorteile:
--
--   1. Es laeuft auch waehrend der Spieler offline ist weiter (langsamer, siehe
--      EggConfig.OFFLINE_SLOWDOWN) — ohne dass dafuer irgendwo ein Server
--      laufen muesste.
--   2. Ein ausgesetzter Tick (Server-Ruckler) verschiebt nichts.
--   3. Es gibt nur EINE Rechnung fuer online und offline, naemlich
--      EggCalculator — nicht zwei, die beim naechsten Balancing auseinander
--      laufen.
--
-- ============================================================
-- WARUM DIE PRODUKTION BEI VOLLEM LAGER ANHAELT
-- ============================================================
-- Liegen bereits EggConfig.MAX_UNCOLLECTED_EGGS Eier herum, wird die Zeitmarke
-- trotzdem auf jetzt gesetzt. Die Wartezeit sammelt sich also NICHT an, und wer
-- nach drei Tagen zurueckkommt, findet zwoelf Eier — nicht dreihundert.
--
-- Das ist exakt dasselbe Verhalten wie beim vollen Honig-Lager (siehe
-- HoneyService): laenger wegbleiben bringt nichts zusaetzlich. Wer mehr will,
-- kommt oefter vorbei und sammelt ein.
--
-- ============================================================
-- SEIT v12: GELEGT WIRD NUR AUF DEM PLOT
-- ============================================================
-- Ist der Baerchi am Event oder im PIT (oder auf dem Weg dorthin bzw.
-- zurueck), PAUSIERT der Lege-Timer: island.lastEggAt wird in jedem Tick um
-- die vergangene Zeit nach vorne geschoben. Kommt er heim, laeuft der Timer
-- von dort weiter, der bisherige Fortschritt bleibt — und es entsteht kein
-- Nachholen fuer die Zeit unterwegs. Der Weg zum Honig-Teich zaehlt als zu
-- Hause (PetModeService.isHome). Ist die Figur gerade nicht sichtbar (Neubau),
-- wird in dem Tick nicht gelegt; faellige Eier kommen im naechsten.

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types         = require(ReplicatedStorage.Network.Types)
local Remotes       = require(ReplicatedStorage.Network.Remotes)
local Loc           = require(ReplicatedStorage.Localization.Loc)
local EggConfig     = require(ReplicatedStorage.Config.EggConfig)
local MapConfig     = require(ReplicatedStorage.Config.MapConfig)
local EggCalculator = require(ReplicatedStorage.Modules.EggCalculator)
local EggTree       = require(ReplicatedStorage.Modules.EggTree)
local BaerchiConfig = require(ReplicatedStorage.Config.BaerchiConfig)

local PlayerService = require(ServerScriptService.Services.PlayerService)
local MapService    = require(ServerScriptService.Services.MapService)
local IslandService = require(ServerScriptService.Services.IslandService)
local RateLimiter   = require(ServerScriptService.Util.RateLimiter)
-- v12: nur fuer "ist der Baerchi zu Hause?"
local PetModeService = require(ServerScriptService.Services.PetModeService)

local EggLayService = {}

--------------------------------------------------------------------------------
-- Konstanten
--------------------------------------------------------------------------------

-- Wie oft nachgesehen wird, ob ein Ei faellig ist. Muss nicht schnell sein:
-- das kuerzeste moegliche Intervall ist EggConfig.MIN_LAY_INTERVAL_SECONDS
-- (15s), und faellige Eier gehen nicht verloren — sie werden beim naechsten
-- Tick aus der Zeitmarke nachgerechnet.
local CHECK_INTERVAL = 5

-- Laufender Zaehler fuer die Ei-uid. os.time() allein reicht nicht: bei einem
-- Offline-Nachholen entstehen mehrere Eier in derselben Sekunde.
local _eggCounter = 0

-- v12: Zeitpunkt des letzten Ticks pro Spieler (fuer die Pause) und ob der
-- Baerchi im letzten Tick unterwegs war (fuer den einen Sync bei der Rueckkehr).
local _lastTick: { [Player]: number } = {}
local _wasAway: { [Player]: boolean } = {}

local function newEggUid(): string
	_eggCounter += 1
	return string.format("e_laid_%d_%d_%d", os.time(), _eggCounter, math.random(1000, 9999))
end

--------------------------------------------------------------------------------
-- Wohin das Ei faellt
--------------------------------------------------------------------------------

local function footPosOf(model: Model): Vector3
	local box, size = model:GetBoundingBox()
	return Vector3.new(box.Position.X, box.Position.Y - size.Y * 0.5, box.Position.Z)
end

-- Der Ort, an dem das naechste Ei landet: neben dem Baerchi, wo er GERADE
-- steht. Laeuft er zum Honig-Teich, liegen die Eier auf dem Weg dorthin.
--
-- Der seitliche Versatz ist Zufall im Umkreis von LAY_SCATTER_RADIUS — ohne
-- ihn laegen mehrere Eier exakt uebereinander, wenn der Baerchi laenger an
-- derselben Stelle steht, und man koennte nur das oberste anklicken.
--
-- ============================================================
-- DAS ERGEBNIS IST PLOT-RELATIV, NICHT ABSOLUT
-- ============================================================
-- Welchen der acht Plots ein Spieler bekommt, entscheidet sich bei jedem Join
-- neu. Eine Weltposition zu speichern hiesse: nach einem Rejoin liegen die
-- Eier dort, wo der Plot BEIM LEGEN war — moeglicherweise auf dem Plot eines
-- Nachbarn. Deshalb rechnet MapService.worldToPlot sie in Plot-Koordinaten um,
-- und beim Bauen wieder zurueck.
--
-- Gibt nil zurueck, wenn es gerade keine Figur und keinen Plot gibt. Dann wird
-- schlicht nicht gelegt.
local function pickDropPosition(player: Player, baerchiUid: string): Vector3?
	local figure = MapService.getBaerchiModel(player, baerchiUid)

	local origin: Vector3
	if figure then
		origin = footPosOf(figure)
	else
		-- Kein sichtbarer Baerchi (typisch beim Offline-Nachholen, bevor der
		-- Plot fertig ist): um den Plot-Mittelpunkt herum ablegen.
		local plot = MapService.getPlotCFrame(player)
		if not plot then
			return nil
		end
		origin = plot.Position
	end

	local angle    = math.random() * math.pi * 2
	local distance = math.random() * EggConfig.LAY_SCATTER_RADIUS

	local dx, dz = math.cos(angle) * distance, math.sin(angle) * distance
	local world = Vector3.new(origin.X + dx, origin.Y, origin.Z + dz)

	-- Seit der Baerchi am Becken wohnt (HONEY_POND_V2), koennte ein Ei im
	-- Honig landen. Dann auf die andere Seite des Baerchis spiegeln — dort
	-- ist es immer weiter vom Becken weg als der Baerchi selbst.
	local pond = MapService.getPondCenter(player)
	if pond then
		local keepOut = MapConfig.POND_RADIUS + MapConfig.POND_RIM_WIDTH + 1.5
		if Vector3.new(world.X - pond.X, 0, world.Z - pond.Z).Magnitude < keepOut then
			world = Vector3.new(origin.X - dx, origin.Y, origin.Z - dz)
		end
	end

	return MapService.worldToPlot(player, world)
end

--------------------------------------------------------------------------------
-- Legen
--------------------------------------------------------------------------------

-- Legt EIN Ei, wenn Platz ist. Gibt true zurueck wenn es geklappt hat.
--
-- Aendert die Daten, aber loest KEIN markDirty aus: beim Offline-Nachholen
-- entstehen mehrere Eier hintereinander, und ein Sync pro Ei waere sinnlose
-- Netzlast. Der Aufrufer synchronisiert einmal am Ende.
local function layOne(player: Player, data: Types.PlayerData, baerchi: Types.Baerchi, cap: number?): boolean
	local island = data.island

	-- cap: Offline-Nachholen legt nur bis EggConfig.OFFLINE_MAX_EGGS (Paket 6.1).
	if #island.laidEggs >= (cap or EggConfig.MAX_UNCOLLECTED_EGGS) then
		return false
	end

	local rolled = EggCalculator.rollEggType(baerchi)
	if not rolled then
		return false
	end

	-- v14: gesperrtes Ei -> naechster freier Vorgaenger im selben Pfad
	-- (EggTree.resolveLaid). Nichts geht verloren, nichts wird uebersprungen.
	local eggType = EggTree.resolveLaid(data.eggTree, rolled)

	-- v14: Void-Identitaet — mit layUpgradeChance steigt das Ei eine Stufe
	-- auf, falls die naechste Stufe schon frei ist.
	local def = BaerchiConfig.getById(baerchi.configId)
	if def and def.layUpgradeChance and def.layUpgradeChance > 0 and math.random() < def.layUpgradeChance then
		local up = EggTree.upgradeTarget(data.eggTree, eggType, def.path)
		if up then
			eggType = up
			-- Sichtbar machen: das Omen des Phantoms (volle Show nur beim
			-- Phantom selbst, sonst ein kurzes Echo).
			local figure = MapService.getBaerchiModel(player, baerchi.uid)
			if figure then
				Remotes.SkillFXPlay:FireAllClients({
					owner    = player.UserId,
					skillId  = "PhantomOmen",
					full     = baerchi.skillId == "PhantomOmen",
					attacker = figure,
					target   = nil,
				})
			end
		end
	end

	local position = pickDropPosition(player, baerchi.uid)
	if not position then
		return false
	end

	table.insert(island.laidEggs, {
		uid     = newEggUid(),
		eggType = eggType,
		laidAt  = os.time(),
		x       = position.X,
		y       = position.Y,
		z       = position.Z,
	})

	return true
end

-- Rechnet nach, wie viele Eier seit island.lastEggAt faellig geworden sind,
-- und legt sie. Gibt zurueck, wie viele es tatsaechlich wurden und ob die
-- Obergrenze dabei gebremst hat.
--
-- `offline` steuert nur die Rate (siehe EggCalculator) — die Rechnung selbst
-- ist fuer beide Faelle dieselbe.
local function catchUp(player: Player, data: Types.PlayerData, offline: boolean): (number, boolean)
	local island  = data.island
	local uid     = island.equippedUid
	local baerchi = if uid then island.baerchis[uid] else nil

	-- Kein ausgeruesteter Baerchi: es legt niemand. Die Zeitmarke wird
	-- trotzdem nachgezogen, sonst wuerde beim naechsten Ausruesten die ganze
	-- Zwischenzeit auf einmal gutgeschrieben — fuer einen Baerchi, der da noch
	-- gar nicht stand.
	if not baerchi then
		island.lastEggAt = os.time()
		return 0, false
	end

	local interval = EggCalculator.getLayIntervalSeconds(baerchi, offline)
	if not interval then
		island.lastEggAt = os.time()
		return 0, false
	end

	local now     = os.time()
	local elapsed = now - (island.lastEggAt or now)
	if elapsed <= 0 then
		return 0, false
	end

	local due = math.floor(elapsed / interval)
	if due <= 0 then
		return 0, false
	end

	local laid    = 0
	local blocked = false

	local cap = if offline then EggConfig.OFFLINE_MAX_EGGS else EggConfig.MAX_UNCOLLECTED_EGGS
	for _ = 1, due do
		if layOne(player, data, baerchi, cap) then
			laid += 1
		else
			blocked = true
			break
		end
	end

	-- Zeitmarke immer auf jetzt — auch wenn die Obergrenze gebremst hat.
	-- Genau das ist die Stelle, an der sich die Wartezeit NICHT ansammelt
	-- (siehe Kopf-Kommentar).
	island.lastEggAt = now

	return laid, blocked
end

--------------------------------------------------------------------------------
-- Einsammeln
--------------------------------------------------------------------------------

local function fail(player: Player, action: string, reason: Types.LocMsg?)
	Remotes.ActionFailed:FireClient(player, action, reason or Loc.msg("err.unknown"))
end

-- Nimmt EIN Ei aus der Liste und schreibt es dem Lager gut.
-- Gibt den Ei-Typ zurueck, oder nil wenn es das Ei nicht (mehr) gibt.
local function takeEgg(data: Types.PlayerData, eggUid: string): Types.EggType?
	local island = data.island

	for index, egg in island.laidEggs do
		if egg.uid == eggUid then
			table.remove(island.laidEggs, index)

			local stock = island.eggStock
			stock[egg.eggType] = (stock[egg.eggType] or 0) + 1

			return egg.eggType
		end
	end

	return nil
end

function EggLayService.collect(player: Player, eggUid: string)
	local data = PlayerService.getData(player)
	if not data then return end

	local eggType = takeEgg(data, eggUid)
	if not eggType then
		-- Kein Fehler des Spielers: zwei schnelle Klicks auf dasselbe Ei, oder
		-- ein Klick auf ein Ei, das der "alles einsammeln"-Knopf gerade
		-- weggeraeumt hat. Still ignorieren statt einen Toast zu werfen.
		return
	end

	local result: Types.EggCollectResult = {
		eggUid  = eggUid,
		eggType = eggType,
		inStock = data.island.eggStock[eggType] or 0,
	}

	Remotes.EggCollectedReceived:FireClient(player, result)
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)
end

function EggLayService.collectAll(player: Player)
	local data = PlayerService.getData(player)
	if not data then return end

	local eggs = data.island.laidEggs
	if #eggs == 0 then
		fail(player, "RequestCollectAllEggs", Loc.msg("err.egg_none_lying"))
		return
	end

	-- Ueber eine Kopie der uids laufen: takeEgg entfernt aus derselben Liste,
	-- ueber die wir sonst iterieren wuerden.
	local uids: { string } = {}
	for _, egg in eggs do
		table.insert(uids, egg.uid)
	end

	local last: Types.EggType? = nil
	local count = 0

	for _, uid in uids do
		local eggType = takeEgg(data, uid)
		if eggType then
			last  = eggType
			count += 1
		end
	end

	if count == 0 then
		return
	end

	-- Ein Ergebnis fuer den ganzen Schwung. `eggUid` bleibt leer: es war nicht
	-- EIN Ei, und ein erfundener Wert waere schlimmer als ein leerer.
	local result: Types.EggCollectResult = {
		eggUid  = "",
		eggType = last :: Types.EggType,
		inStock = count,
	}

	Remotes.EggCollectedReceived:FireClient(player, result)
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)

	print("[EggLayService]", player.Name, "| alle Eier eingesammelt:", count)
end

--------------------------------------------------------------------------------
-- Oeffentliche API
--------------------------------------------------------------------------------

-- Legt sofort ein Ei, unabhaengig von der Zeitmarke. NUR fuer den Studio-Test
-- (DebugService): auf ein echtes Intervall zu warten macht das Ei-System sonst
-- praktisch unpruefbar.
function EggLayService.layNow(player: Player): boolean
	local data = PlayerService.getData(player)
	if not data then return false end

	local uid     = data.island.equippedUid
	local baerchi = if uid then data.island.baerchis[uid] else nil
	if not baerchi then return false end

	local ok = layOne(player, data, baerchi)
	if ok then
		PlayerService.markDirty(player)
	end
	return ok
end

--------------------------------------------------------------------------------
-- Takt
--------------------------------------------------------------------------------

local function tick()
	for _, player in Players:GetPlayers() do
		local data = PlayerService.getData(player)
		if not data then continue end

		local now = os.time()
		local dt  = now - (_lastTick[player] or now)
		_lastTick[player] = now

		-- v12: unterwegs (Event/PIT) -> Timer einfrieren.
		if not PetModeService.isHome(player) then
			if dt > 0 then
				data.island.lastEggAt = math.min(now, (data.island.lastEggAt or now) + dt)
			end
			_wasAway[player] = true
			continue
		end

		-- Gerade heimgekommen: einmal syncen, damit die Countdown-Anzeige
		-- (EggTimerController) die verschobene Zeitmarke bekommt.
		if _wasAway[player] then
			_wasAway[player] = nil
			PlayerService.markDirty(player)
		end

		-- Nur legen, wenn die Figur wirklich auf dem Plot steht.
		local uid = data.island.equippedUid
		if uid and not MapService.getBaerchiModel(player, uid) then
			continue
		end

		local laid = catchUp(player, data, false)
		if laid > 0 then
			-- markDirty zieht die sichtbaren Eier ueber PlotDisplayService nach.
			PlayerService.markDirty(player)
		end
	end
end

function EggLayService.init()
	-- Einsammeln per Beruehrung: MapService baut an jedem gelegten Ei einen
	-- Touched-Handler, kennt aber EggLayService nicht (Ringschluss-Gefahr,
	-- siehe MapService._eggCollectHandler). Deshalb haengt sich hier die
	-- eigentliche Sammel-Funktion ein — derselbe Weg fuehrt seit jeher zum
	-- Klick-Remote unten, nur der Ausloeser ist jetzt Beruehren statt Klicken.
	MapService.setEggCollectHandler(function(player: Player, eggUid: string)
		EggLayService.collect(player, eggUid)
	end)

	RateLimiter.connect(Remotes.RequestCollectEgg, "RequestCollectEgg", function(player, eggUid: any)
		if typeof(eggUid) ~= "string" then return end
		EggLayService.collect(player, eggUid)
	end)

	RateLimiter.connect(Remotes.RequestCollectAllEggs, "RequestCollectAllEggs", function(player)
		EggLayService.collectAll(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		_lastTick[player] = nil
		_wasAway[player]  = nil
	end)

	-- Offline-Nachholen beim Join.
	PlayerService.onDataLoaded(function(player, data)
		-- Gelegt wird vom AUSGERUESTETEN Baerchi. Ein alter Spielstand kann
		-- beim Laden noch keinen (gueltigen) haben; IslandService ruestet in
		-- seinem eigenen onDataLoaded zwar nach, aber die Reihenfolge der
		-- Callbacks ist nicht zugesichert. autoEquipIfNone ist idempotent,
		-- der zweite Aufruf tut nichts.
		IslandService.autoEquipIfNone(data)

		local secondsAway = os.time() - (data.lastSeenAt or os.time())
		local laid, blocked = catchUp(player, data, true)

		-- Paket 6.1: auch melden, wenn die Offline-Grenze alles gebremst hat
		-- (0 gelegt, Lager voll) — sonst wundert sich der Spieler, warum nichts kam.
		if laid > 0 or (blocked and secondsAway >= 60) then
			local report: Types.OfflineEggReport = {
				laid        = laid,
				skipped     = blocked,
				secondsAway = math.max(0, secondsAway),
			}
			Remotes.OfflineEggReportReceived:FireClient(player, report)

			print(
				"[EggLayService]", player.Name,
				"| offline gelegt:", laid,
				if blocked then "| Obergrenze erreicht" else ""
			)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(CHECK_INTERVAL)

			local ok, err = pcall(tick)
			if not ok then
				warn("[EggLayService] Tick fehlgeschlagen:", err)
			end
		end
	end)

	print(
		"[EggLayService] Initialisiert | Intervall:", CHECK_INTERVAL, "s |",
		"max", EggConfig.MAX_UNCOLLECTED_EGGS, "Eier gleichzeitig"
	)
end

return EggLayService
