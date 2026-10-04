--!strict
-- EventParticipationService.luau
-- ServerScriptService/Services/EventParticipationService.luau
--
-- Einzige Zustaendigkeit:
--   - Den ausgeruesteten Baerchi eines Spielers auf Knopfdruck in die
--     Event-Area in der Weltmitte schicken und wieder zurueckholen
--   - Beim ENDE eines Events an jeden dort tatsaechlich anwesenden Baerchi
--     die Belohnung dieses Events auszahlen
--
-- WAS es gibt, steht ausschliesslich in EventConfig (Stat-Fokus und Bonus je
-- Event) — hier steht nur, WIE es ausgezahlt wird. Waehrungen laufen dabei
-- ueber EconomyService, nie ueber einen direkten Feldzugriff: die Projektregel
-- "nur EconomyService aendert Waehrungen" gilt auch fuer Event-Belohnungen.
--
-- ============================================================
-- WARUM DAS EIN EIGENER SERVICE IST
-- ============================================================
-- EventService faehrt den Zyklus und weiss nichts von Spielern. MapService
-- baut Geometrie. BaerchiAutopilotService laesst die Figur zum Honig-Teich
-- laufen. Die Teilnahme braucht alle drei, gehoert aber in keinen davon: sie
-- ist die erste Stelle im Projekt, an der eine Spieleraktion, ein Weltzustand
-- (laeuft ein Event?) und Spielerdaten (Stat-Level) zusammenkommen.
--
-- ============================================================
-- WARUM DIE ANWESENHEIT SERVERSEITIG FESTGESTELLT WIRD
-- ============================================================
-- Der Client schickt ausschliesslich "ich moechte hin" bzw. "hol ihn zurueck".
-- WO die Figur danach steht, bestimmt allein dieser Service (er bewegt sie
-- selbst) und er prueft es beim Verteilen der Belohnung noch einmal an der
-- tatsaechlichen Weltposition nach. Ein Client, der "ich bin am Event"
-- behauptet, bekommt davon nichts — sonst waere der Stat-Fortschritt in fuenf
-- Minuten nachgebaut.
--
-- ============================================================
-- BEWUSST EINFACH GEHALTEN (Vorgabe des Projektinhabers)
-- ============================================================
-- Genau EIN Baerchi pro Spieler (der ausgeruestete — nur er hat ueberhaupt
-- eine Figur in der Welt), kein Auto-Send, kein Offline-Fortschritt, keine
-- mehrfache Belegung. Das groessere AFK-Grind-System um Events herum ist laut
-- Projektinhaber ausdruecklich ein spaeterer, eigener Auftrag. Wer das hier
-- erweitert: die Stelle dafuer ist _present (eine Liste statt eines Eintrags)
-- und awardStatLevel/awardBonus (die schon jetzt pro Baerchi arbeiten).

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types            = require(ReplicatedStorage.Network.Types)
local Remotes          = require(ReplicatedStorage.Network.Remotes)
local MapConfig        = require(ReplicatedStorage.Config.MapConfig)
local EventConfig      = require(ReplicatedStorage.Config.EventConfig)
local EggConfig        = require(ReplicatedStorage.Config.EggConfig)
local BuildingBehavior = require(ReplicatedStorage.Config.BuildingBehavior)
local BaerchiConfig    = require(ReplicatedStorage.Config.BaerchiConfig)
local PromotionConfig  = require(ReplicatedStorage.Config.PromotionConfig)
local CombatCalculator = require(ReplicatedStorage.Modules.CombatCalculator)
local EggTree          = require(ReplicatedStorage.Modules.EggTree)

local FigureWalker    = require(ServerScriptService.Util.FigureWalker)
local FigurePlacement = require(ServerScriptService.Util.FigurePlacement)
local FigureFX        = require(ServerScriptService.Util.FigureFX)
local ActivityLock    = require(ServerScriptService.Util.ActivityLock)
local RateLimiter     = require(ServerScriptService.Util.RateLimiter)
local PlayerService   = require(ServerScriptService.Services.PlayerService)
local EconomyService  = require(ServerScriptService.Services.EconomyService)
local MapService      = require(ServerScriptService.Services.MapService)
local EventService    = require(ServerScriptService.Services.EventService)
local EventHandlers   = require(ServerScriptService.Services.EventHandlers)
local EggTreeService  = require(ServerScriptService.Services.EggTreeService)
local Loc           = require(ReplicatedStorage.Localization.Loc)

local EventParticipationService = {}

--------------------------------------------------------------------------------
-- Konstanten
--------------------------------------------------------------------------------

-- Halter-Name fuer ActivityLock. Wird fuer die GESAMTE Zeit gehalten, in der
-- der Baerchi unterwegs zum Event ist oder dort steht — sonst wuerde ihn der
-- Autopilot mitten am Event zum Honig-Teich zurueckrufen.
--
-- Bewusste Folge: waehrend der Teilnahme isst der Baerchi nicht. Das ist der
-- Preis fuers Hinschicken und macht die Entscheidung erst zu einer.
local LOCK_HOLDER = "EventParticipation"

-- Der Weg von einem Plot (Ring-Radius 212) in die Mitte ist lang. Mit der
-- normalen MapConfig.WALK_SPEED waere man ueber zehn Sekunden unterwegs —
-- deshalb hier doppeltes Tempo: sichtbar hinlaufen ja, Geduldsprobe nein.
local EVENT_WALK_SPEED = MapConfig.WALK_SPEED * 2

-- Wie weit vom Mittelpunkt entfernt ein Baerchi auf dem Podest steht, als
-- Anteil des Podest-Radius. Bewusst nicht 0: bei mehreren Spielern staenden
-- sonst alle Figuren ineinander. Jeder steht auf SEINER Seite (Richtung des
-- eigenen Plots, siehe standPosition) — dieselben acht Richtungen, in denen
-- auch die Zaunluecken sitzen.
local STAND_RADIUS_FACTOR = 0.55

-- Wie oft nachgesehen wird, ob eine Teilnahme noch gilt (Figur weg, Schloss
-- von einem Kampf uebernommen, Baerchi nicht mehr ausgeruestet). Muss nicht
-- schnell sein — es geht nur darum, dass ein ungueltiger Zustand nicht bis zum
-- Event-Ende liegen bleibt.
local CHECK_INTERVAL = 4

-- Wie sich der Baerchi waehrend eines Events bewegt. Die Zuordnung zum
-- Event-Typ steht in EventConfig.EventDef.action — hier nur, wie sich das in
-- Zahlen der Ruhe-Animation uebersetzt.
--
-- Bewusst ueber die vorhandene Idle-Bewegung statt ueber eigene Animationen:
-- die Baerchi-Meshes sind nicht gerigt (siehe FigureWalker, Kopf-Kommentar),
-- eine echte "faengt Bienen"-Animation gaebe es fuer dieses Modell gar nicht.
-- Der Spieler soll sehen, DASS sein Baerchi mitmacht — mehr ist fuer das
-- Basis-Spiel nicht gefordert.
local ACTION_MOTION: { [string]: { height: number, rate: number } } = {
	bounce = { height = 1.60, rate = 2.20 },   -- kraeftiges Huepfen
	lean   = { height = 0.35, rate = 3.00 },   -- schnelles, flaches Nicken
	spin   = { height = 0.80, rate = 1.10 },   -- ruhiges Wiegen
}

--------------------------------------------------------------------------------
-- Zustand
--------------------------------------------------------------------------------

type Presence = {
	baerchiUid : string,
	homeFoot   : Vector3,   -- wohin zurueckgelaufen wird
	standFoot  : Vector3,   -- wo auf dem Podest gestanden wird
	arrivedAt  : number,    -- os.time(), nur fuers Log

	-- Von Event-Handlern genutzt (siehe buildApi):
	player     : Player?,
	figure     : Model?,
	busy       : boolean?,        -- Figur laeuft gerade (walkTo)
	cancelWalk : boolean?,        -- laufende Bewegung abbrechen
	abducting  : boolean?,        -- UFO hat die Figur gerade
}

-- Spieler, deren Baerchi gerade AM Event steht (fertig angekommen).
local _present: { [Player]: Presence } = {}

-- Spieler, deren Baerchi gerade laeuft (hin oder zurueck). Verhindert, dass
-- zwei Laufbewegungen gleichzeitig an derselben Figur ziehen.
local _walking: { [Player]: boolean } = {}

-- Laufender Event-Handler (siehe Services/EventHandlers) samt Token. Der Token
-- steigt bei jedem Start/Ende; api.running() vergleicht damit.
local _session: any = nil
local _sessionToken = 0

-- Spieler, die waehrend einer Handler-Bewegung "zurueck" gedrueckt haben.
local _recallPending: { [Player]: boolean } = {}

-- v12: Richtung des laufenden Wegs ("to" = zum Event, "back" = heim) fuer die
-- Pet-Leiste, und der Wunsch, einen Hinweg abzubrechen (Zurueckholen, bevor
-- der Baerchi angekommen ist).
local _walkDir: { [Player]: string } = {}
local _cancelTo: { [Player]: boolean } = {}

--------------------------------------------------------------------------------
-- Hilfen
--------------------------------------------------------------------------------

local function fail(player: Player, action: string, reason: Types.LocMsg | string)
	Remotes.ActionFailed:FireClient(player, action, reason)
end

local function notifyPresence(player: Player, atEvent: boolean, baerchiUid: string?)
	Remotes.EventPresenceChanged:FireClient(player, atEvent, baerchiUid)
end

local function footPosOf(model: Model): Vector3
	local box, size = model:GetBoundingBox()
	return Vector3.new(box.Position.X, box.Position.Y - size.Y * 0.5, box.Position.Z)
end

-- Der Standplatz dieses Spielers auf dem Podest: auf der Seite, aus der er
-- kommt. Ohne Plot-Information (sollte nicht vorkommen) faellt es auf die
-- Mitte zurueck — lieber uebereinander stehen als gar nicht ankommen.
local function standPosition(player: Player): Vector3
	local center = MapService.getEventPitPosition()
	local plot   = MapService.getPlotCFrame(player)

	if not plot then
		return center
	end

	local flat = Vector3.new(plot.Position.X - center.X, 0, plot.Position.Z - center.Z)
	if flat.Magnitude < 1e-3 then
		return center
	end

	return center + flat.Unit * (MapService.getEventPitRadius() * STAND_RADIUS_FACTOR)
end

-- Steht diese Figur tatsaechlich (noch) auf dem Podest?
-- Das ist die Pruefung, die den Fortschritt vor gefaelschten Client-Meldungen
-- schuetzt — siehe Kopf-Kommentar.
local function isOnEventFloor(model: Model): boolean
	local center = MapService.getEventPitPosition()
	local foot   = footPosOf(model)
	local flat   = Vector3.new(foot.X - center.X, 0, foot.Z - center.Z)

	return flat.Magnitude <= MapService.getEventPitRadius()
end

-- Die Bewegung, die der Baerchi waehrend des laufenden Events zeigt.
local function playEventMotion(model: Model)
	local active = EventService.getActive()
	local motion = if active then ACTION_MOTION[active.action] else nil

	if not motion then
		-- Kein Event aktiv: der Baerchi steht einfach dekorativ herum und
		-- atmet. Ausdrueckliche Vorgabe — das ist kein Fehlerzustand, und
		-- niemand muss ihn deshalb zurueckholen.
		FigureFX.idleBob(model, {
			height = MapConfig.IDLE_BOB_HEIGHT,
			rate   = MapConfig.IDLE_BOB_RATE,
		})
		return
	end

	FigureFX.idleBob(model, { height = motion.height, rate = motion.rate })
end

--------------------------------------------------------------------------------
-- Hin und zurueck
--------------------------------------------------------------------------------

-- Gibt true zurueck, wenn der Baerchi losgeht.
function EventParticipationService.sendToEvent(player: Player): boolean
	local data = PlayerService.getData(player)
	if not data then return false end

	if _present[player] or _walking[player] then
		fail(player, "RequestPetMode", Loc.msg("err.event_already_away"))
		return false
	end

	local uid = data.island.equippedUid
	if not uid or not data.island.baerchis[uid] then
		fail(player, "RequestPetMode", Loc.msg("err.event_no_equipped"))
		return false
	end

	local figure = MapService.getBaerchiModel(player, uid)
	if not figure then
		fail(player, "RequestPetMode", Loc.msg("err.event_not_on_plot"))
		return false
	end

	-- v12: ein vom Spieler ausgeloester Weg zum Event hat Vorrang vor dem
	-- Honig-Autopilot (wie der Kampf). Dem Autopilot wird das Schloss
	-- abgenommen — er bemerkt das selbst und bricht sauber ab. Haelt es
	-- jemand anderes (Kampf), wird weiter abgelehnt; die Reihenfolge regelt
	-- dann PetModeService.
	if ActivityLock.owner(player) == "Autopilot" then
		ActivityLock.forceAcquire(player, LOCK_HOLDER)
	elseif not ActivityLock.tryAcquire(player, LOCK_HOLDER) then
		fail(player, "RequestPetMode", Loc.msg("err.baerchi_busy"))
		return false
	end

	_walking[player]  = true
	_walkDir[player]  = "to"
	_cancelTo[player] = nil

	task.spawn(function()
		local ok, err = pcall(function()
			FigureFX.stopIdle(figure)

			local homeFoot  = footPosOf(figure)
			local standFoot = standPosition(player)

			local function cancelled(): boolean
				return ActivityLock.owner(player) ~= LOCK_HOLDER
					or player.Parent == nil
					or figure.Parent == nil
					or MapService.getBaerchiModel(player, uid) ~= figure
			end

			FigureWalker.walk(figure, homeFoot, standFoot, {
				speed       = EVENT_WALK_SPEED,
				isCancelled = function(): boolean
					return cancelled() or _cancelTo[player] == true
				end,
			})

			if cancelled() then
				return
			end

			-- v12: auf dem Hinweg zurueckgeholt — von hier aus umkehren.
			if _cancelTo[player] then
				_cancelTo[player] = nil
				_walkDir[player]  = "back"
				FigureWalker.walk(figure, footPosOf(figure), homeFoot, {
					speed       = EVENT_WALK_SPEED,
					isCancelled = cancelled,
				})
				if not cancelled() then
					FigurePlacement.place(figure, homeFoot, figure:GetPivot().Rotation)
					FigureFX.idleBob(figure, {
						height = MapConfig.IDLE_BOB_HEIGHT,
						rate   = MapConfig.IDLE_BOB_RATE,
					})
				end
				return
			end

			-- FigureWalker haelt die Y-Koordinate des STARTPUNKTES ueber die
			-- ganze Strecke (siehe dort). Das Event-Podest liegt hoeher als der
			-- Plot, also wird die Figur hier noch einmal sauber auf die
			-- Podest-Oberflaeche gesetzt — mit Blick zur Mitte.
			FigurePlacement.placeLookingAt(figure, standFoot, MapService.getEventPitPosition())

			_present[player] = {
				player     = player,
				baerchiUid = uid,
				homeFoot   = homeFoot,
				standFoot  = standFoot,
				arrivedAt  = os.time(),
			}

			playEventMotion(figure)
			notifyPresence(player, true, uid)

			print("[EventParticipationService]", player.Name, "| am Event:", uid)
		end)


		_walking[player]  = nil
		_walkDir[player]  = nil
		_cancelTo[player] = nil

		if not ok then
			warn("[EventParticipationService] Hinweg fehlgeschlagen:", err)
		end

		-- Nicht angekommen (abgebrochen oder Fehler): Schloss wieder freigeben,
		-- sonst bliebe der Spieler dauerhaft blockiert.
		if not _present[player] then
			ActivityLock.release(player, LOCK_HOLDER)
			notifyPresence(player, false, nil)
		end
	end)

	return true
end

-- Gibt true zurueck, wenn der Rueckweg angestossen wurde (oder schon laeuft).
function EventParticipationService.recall(player: Player): boolean
	local presence = _present[player]
	if not presence then
		-- v12: noch auf dem Hinweg — umkehren lassen.
		if _walking[player] and _walkDir[player] == "to" then
			_cancelTo[player] = true
			return true
		end
		return _walking[player] == true
	end

	if presence.abducting then
		fail(player, "RequestPetMode", Loc.msg("err.event_ufo"))
		return false
	end

	-- Ein Event-Handler bewegt die Figur gerade: Bewegung abbrechen, der
	-- Rueckweg startet direkt danach (siehe walkTo in buildApi).
	if presence.busy then
		_recallPending[player] = true
		presence.cancelWalk = true
		return true
	end

	if _walking[player] then
		return true   -- laeuft schon zurueck
	end

	local figure = MapService.getBaerchiModel(player, presence.baerchiUid)

	-- Figur ist weg (Equip-Wechsel, Rebirth, Insel neu gebaut): Zustand
	-- einfach aufraeumen statt einen Rueckweg zu erfinden.
	if not figure then
		_present[player] = nil
		ActivityLock.release(player, LOCK_HOLDER)
		notifyPresence(player, false, nil)
		return true
	end

	_walking[player]  = true
	_walkDir[player]  = "back"
	_present[player]  = nil
	notifyPresence(player, false, presence.baerchiUid)

	task.spawn(function()
		local ok, err = pcall(function()
			FigureFX.stopIdle(figure)

			local function cancelled(): boolean
				return ActivityLock.owner(player) ~= LOCK_HOLDER
					or player.Parent == nil
					or figure.Parent == nil
			end

			FigureWalker.walk(figure, footPosOf(figure), presence.homeFoot, {
				speed       = EVENT_WALK_SPEED,
				isCancelled = cancelled,
			})

			if cancelled() then
				return
			end

			FigurePlacement.place(figure, presence.homeFoot, figure:GetPivot().Rotation)
			FigureFX.idleBob(figure, {
				height = MapConfig.IDLE_BOB_HEIGHT,
				rate   = MapConfig.IDLE_BOB_RATE,
			})
		end)

		_walking[player] = nil
		_walkDir[player] = nil
		ActivityLock.release(player, LOCK_HOLDER)

		if not ok then
			warn("[EventParticipationService] Rueckweg fehlgeschlagen:", err)
		end
	end)

	return true
end

--------------------------------------------------------------------------------
-- Belohnung am Event-Ende
--------------------------------------------------------------------------------

-- Vergibt EINE Stat-Stufe an diesen Baerchi.
--
-- `focus` ist der Stat, auf den das laufende Event ausgelegt ist
-- (EventConfig.EventDef.statFocus) — bei den Trainings-Events also fest, bei
-- allen anderen nil.
--
-- Reihenfolge:
--   1. Der Fokus-Stat, sofern er noch unter der Rarity-Obergrenze liegt.
--   2. Sonst zufaellig unter allen Stats, die noch Luft haben. Wuerde man
--      blind aus allen fuenf ziehen, liefe eine Teilnahme umso oefter ins
--      Leere, je weiter der Baerchi schon ist — und ausgerechnet dann, wenn
--      der Spieler am meisten Zeit investiert hat.
--
-- Dass ein gedeckelter Fokus-Stat auf Zufall zurueckfaellt statt nichts zu tun,
-- ist Absicht: sonst waere ein Trainings-Event fuer genau die Spieler wertlos,
-- die es am laengsten besucht haben.
--
-- Gibt den gewaehlten Stat-Schluessel zurueck, oder nil wenn schon ALLES am
-- Anschlag ist.
local function awardStatLevel(baerchi: Types.Baerchi, focus: string?): string?
	local cap = PromotionConfig.getStatCap(baerchi.rarity)

	-- Einmal auf `any` umgebogen und ab dann unter eigenem Namen benutzt: die
	-- Stat-Schluessel kommen als String herein (PromotionConfig.GROWABLE_STATS
	-- bzw. EventConfig.statFocus), und Types.StatLevels hat feste Felder.
	-- Ausserdem darf so keine Zuweisung mehr mit "(" beginnen — eine Zeile, die
	-- mit einer Klammer anfaengt, liest Luau als Fortsetzung der vorherigen.
	local levels = baerchi.statLevels :: any

	if focus and (levels[focus] or 0) < cap then
		levels[focus] = (levels[focus] or 0) + 1
		return focus
	end

	local candidates: { string } = {}
	for _, key in PromotionConfig.GROWABLE_STATS do
		if (levels[key] or 0) < cap then
			table.insert(candidates, key)
		end
	end

	if #candidates == 0 then
		return nil
	end

	local key = candidates[math.random(1, #candidates)]
	levels[key] = (levels[key] or 0) + 1

	return key
end

-- Zahlt den Zusatz-Ertrag eines Events aus (EventConfig.EventDef.bonus).
--
-- Gibt zurueck:
--   1. einen fertigen Anzeigetext ("+1x Goldenes Ei"), oder nil wenn es
--      nichts zu melden gibt (Event ohne Bonus, oder Mutations-Wurf daneben),
--   2. die neue Mutation, falls dieses Event dem Baerchi eine verschafft hat.
--
-- Der Baerchi wird hier NUR beim Mutations-Bonus angefasst; alles andere geht
-- an den Spieler (Lager, Waehrung) und nicht an die Figur.
local function awardBonus(
	player: Player,
	data: Types.PlayerData,
	baerchi: Types.Baerchi,
	bonus: EventConfig.EventBonus?
): (string?, Types.MutationId?)

	if not bonus then
		return nil, nil
	end

	local amount = math.max(0, math.floor(bonus.amount or 0))

	-- HONIG in JEDES Gebaeude, gedeckelt auf dessen Lager. Der Ueberlauf
	-- verfaellt bewusst, statt sich anzusammeln: die Lagergroesse ist die
	-- Bremse des ganzen Honig-Systems (siehe BuildingBehavior), und ein Event
	-- darf sie nicht aushebeln.
	if bonus.kind == "honey" then
		local added = 0

		for _, building in data.island.buildings do
			local capacity = BuildingBehavior.getCapacity(building.id, building.level)
			local before   = building.honey or 0
			local after    = math.min(capacity, before + amount)

			added += after - before
			building.honey = after
		end

		if added <= 0 then
			return "Honig-Lager waren schon voll", nil
		end
		return string.format("+%d Honig", added), nil
	end

	-- EIER ins Lager, nicht in einen Brut-Slot: die Brut startet der Spieler
	-- selbst (die Slots koennen gerade belegt sein), und im Lager geht nichts
	-- verloren.
	if bonus.kind == "eggs" then
		if amount <= 0 then
			return nil, nil
		end

		-- v14 (WP10): Sorte nach dem Ei-Baum des Spielers waehlen.
		local eggType: Types.EggType = bonus.eggType or "BasicEgg"
		local isJump = false
		if bonus.eggPick == "jump" then
			local jump = EggTree.pickJumpEgg(data.eggTree)
			if jump then
				eggType = jump
				isJump = true
			else
				eggType = EggTree.highestUnlocked(data.eggTree)
			end
		elseif bonus.eggPick == "highest" then
			eggType = EggTree.highestUnlocked(data.eggTree)
		end
		data.island.eggStock[eggType] = (data.island.eggStock[eggType] or 0) + amount

		local eggDef = EggConfig.data[eggType]
		local text = string.format("+%dx %s", amount, if eggDef then eggDef.displayName else eggType)
		if isJump then
			text ..= " (Sprung-Ei!)"
		end

		-- Blaupause (Koenigshuegel, Schatzgraeber mit 5 Funden)
		if (bonus.blueprintChance or 0) > 0 and math.random() < (bonus.blueprintChance :: number) then
			EggTreeService.grantBlueprint(player, data, 1)
			text ..= "  +1 Blaupause!"
		end

		-- Notfall-Ei (zusaetzlich, siehe EventConfig.EMERGENCY_BASIC_EGG_CHANCE)
		if math.random() < EventConfig.EMERGENCY_BASIC_EGG_CHANCE then
			data.island.eggStock.BasicEgg = (data.island.eggStock.BasicEgg or 0) + 1
			text ..= "  +1 Basis-Ei"
		end

		return text, nil
	end

	-- WAEHRUNG immer ueber EconomyService: der rebirthMult gehoert dorthin und
	-- nirgendwo sonst hin (awardGummies wendet ihn an, awardGoldGummies
	-- bewusst nicht — GoldGummies sind die Premium-Waehrung).
	if bonus.kind == "gummies" then
		local final = EconomyService.awardGummies(player, amount)
		if final <= 0 then
			return nil, nil
		end
		return string.format("+%d Gummies", final), nil
	end

	if bonus.kind == "goldGummies" then
		local final = EconomyService.awardGoldGummies(player, amount)
		if final <= 0 then
			return nil, nil
		end
		return string.format("+%d GoldGummies", final), nil
	end

	-- MUTATION: zwei getrennte Wuerfe. Erst die Event-Chance (kommt ueberhaupt
	-- etwas?), dann die Stufe (welche?). Der zweite Wurf benutzt bewusst
	-- rollMutationTier und NICHT rollMutation: sonst waere das Ergebnis auch
	-- nach einem Treffer noch in 98.5% der Faelle "keine Mutation".
	if bonus.kind == "mutation" then
		-- Die Chance sinkt mit der Rarity (EventConfig.MUTATION_RARITY_FACTOR).
		local chance = (bonus.chance or 0) * EventConfig.getMutationFactor(baerchi.rarity)
		if math.random() >= chance then
			return nil, nil   -- daneben — der Normalfall, kein Text noetig
		end

		local rolled = BaerchiConfig.rollMutationTier()
		local better = BaerchiConfig.pickHigherMutation(baerchi.mutation, rolled)

		-- Nur nach OBEN: wer schon Lava traegt, kann sie hier nie gegen Gold
		-- eintauschen. Der Fehlversuch wird trotzdem gemeldet — ein Treffer,
		-- der nichts veraendert, saehe sonst aus wie ein verschlucktes Ergebnis.
		if better == baerchi.mutation then
			return string.format(
				"Mutations-Wurf: %s — schwaecher als seine, bleibt wie es ist",
				BaerchiConfig.getMutationDisplayName(rolled)
			), nil
		end

		baerchi.mutation = better
		return string.format(
			"MUTATION: %s!",
			BaerchiConfig.getMutationDisplayName(better :: Types.MutationId)
		), better
	end

	return nil, nil
end

local function onEventEnded(finished: EventConfig.EventDef)
	-- Handler zuerst beenden: er liefert, wer was bekommt.
	local results: any = {}
	if _session then
		local ok, res = pcall(_session.stop)
		if ok and res then
			results = res
		else
			warn("[EventParticipationService] Handler-stop fehlgeschlagen:", res)
		end
		_session = nil
	end
	_sessionToken += 1

	for player, presence in _present do
		local data = PlayerService.getData(player)
		if not data then continue end

		local baerchi = data.island.baerchis[presence.baerchiUid]
		if not baerchi then continue end

		-- Zweite, unabhaengige Pruefung: steht die Figur wirklich noch dort?
		-- _present allein wuerde reichen, solange sich niemand dazwischen an der
		-- Figur zu schaffen macht — aber genau das kann passieren (Kampf, der
		-- das Schloss uebernimmt). Die Weltposition ist die Wahrheit.
		local figure = MapService.getBaerchiModel(player, presence.baerchiUid)
		if not figure or not isOnEventFloor(figure) then
			continue
		end

		-- maxHp kann durch den neuen Stat-Level steigen — und seit dem
		-- Mutations-Sturm sogar sprunghaft (eine Mutation multipliziert die
		-- Basiswerte, siehe BaerchiConfig.getMutationBonus). Die Differenz wird
		-- gutgeschrieben, damit ein Fortschritt den Baerchi nicht relativ
		-- SCHWAECHER macht (mehr maxHp bei gleichen currentHp waere ein
		-- leererer Balken als vorher).
		--
		-- Deshalb steht der Messpunkt VOR beiden Belohnungen und wird erst
		-- NACH beiden ausgewertet: Stat-Stufe und Mutation koennen in
		-- derselben Teilnahme zusammenkommen.
		local def      = BaerchiConfig.getById(baerchi.configId)
		local beforeHp = if def then CombatCalculator.getEffectiveStats(baerchi, def.baseStats).maxHp else 0

		-- Nur wer im Handler-Ergebnis steht, bekommt etwas (Stat-Stufen gibt es
		-- nur beim UFO, und dort sofort beim Absetzen, nicht hier).
		local result = results[player]
		if not result then
			continue
		end

		local bonus: EventConfig.EventBonus? = nil
		if result.egg then
			bonus = result.egg
		elseif result.mutationRoll then
			bonus = finished.bonus
		end

		local key: string? = nil
		local bonusText, mutation = awardBonus(player, data, baerchi, bonus)

		-- Weder eine Stufe (alles am Rarity-Cap) noch ein Bonus: dann gibt es
		-- auch nichts zu melden und nichts zu speichern.
		if not key and not bonusText then
			continue
		end

		if def then
			local afterHp = CombatCalculator.getEffectiveStats(baerchi, def.baseStats).maxHp
			baerchi.currentHp = math.clamp(
				(baerchi.currentHp or 0) + math.max(0, afterHp - beforeHp),
				0,
				afterHp
			)
		end

		local gain: Types.EventStatGain = {
			baerchiUid = presence.baerchiUid,
			eventId    = finished.id,
			statKey    = key,
			newLevel   = if key then (baerchi.statLevels :: any)[key] else 0,
			cap        = PromotionConfig.getStatCap(baerchi.rarity),
			bonusText  = bonusText,
			mutation   = mutation,
		}

		Remotes.EventStatGained:FireClient(player, gain)
		PlayerService.markDirty(player)
		PlayerService.saveNow(player)

		-- Eine frisch gewonnene Mutation aendert Fellfarbe UND Aura der Figur.
		-- Beides zieht der normale Weg nach: markDirty oben laesst
		-- PlotDisplayService die Figur neu bauen, sobald das ActivityLock frei
		-- ist (die Mutation steht dafuer in dessen Struktur-Signatur). "Sobald
		-- frei" heisst hier: wenn der Baerchi vom Event zurueck ist — waehrend
		-- er dort steht, haelt DIESER Service das Schloss.
		--
		-- Damit der Moment trotzdem sofort sichtbar ist, gibt es hier einen
		-- Partikel-Stoss in der Farbe der neuen Stufe. Die Figur umzubauen,
		-- waehrend sie auf dem Podest steht, waere die schlechtere Loesung: sie
		-- wuerde dabei an ihren Platz auf dem Plot zurueckspringen.
		if mutation then
			MapService.celebrateBaerchi(
				player,
				presence.baerchiUid,
				BaerchiConfig.getMutationColor(mutation)
			)
		end

		local statText = "keine Stat-Stufe (nur das UFO gibt welche)"
		if key then
			statText = string.format("%s Stufe %d/%d", key, gain.newLevel, gain.cap)
		end

		print(
			"[EventParticipationService]", player.Name,
			"|", finished.id,
			"→", statText,
			if bonusText then "| " .. bonusText else ""
		)
	end

	-- Nach dem Event weiter dekorativ herumstehen (siehe playEventMotion):
	-- der Baerchi wird NICHT automatisch zurueckgeschickt. Wer die naechste
	-- Runde mitnehmen will, laesst ihn einfach stehen.
	for player, presence in _present do
		local figure = MapService.getBaerchiModel(player, presence.baerchiUid)
		if figure then
			playEventMotion(figure)
		end
	end
end

--------------------------------------------------------------------------------
-- Schnittstelle fuer die Event-Handler (Services/EventHandlers)
--------------------------------------------------------------------------------

-- Meldung an den Spieler waehrend eines Events (Toast beim Client).
local function toast(player: Player, text: string)
	if player.Parent == nil then
		return
	end
	local gain: any = {
		baerchiUid = "",
		eventId    = "",
		statKey    = nil,
		newLevel   = 0,
		cap        = 0,
		bonusText  = text,
		mutation   = nil,
		midEvent   = true,
	}
	Remotes.EventStatGained:FireClient(player, gain)
end

-- Setzt die Figur wieder aufs Plot und beendet die Teilnahme (UFO-Absetzen).
local function finishHome(presence: any)
	local player: Player = presence.player
	local figure = MapService.getBaerchiModel(player, presence.baerchiUid)

	if _present[player] == presence then
		_present[player] = nil
	end

	if figure then
		FigurePlacement.place(figure, presence.homeFoot, figure:GetPivot().Rotation)
		FigureFX.idleBob(figure, {
			height = MapConfig.IDLE_BOB_HEIGHT,
			rate   = MapConfig.IDLE_BOB_RATE,
		})
	end

	ActivityLock.release(player, LOCK_HOLDER)
	if player.Parent ~= nil then
		notifyPresence(player, false, nil)
	end
end

-- UFO-Belohnung beim Absetzen: +1 auf alle Stats (begrenzt durch STAT_CAP)
-- und der Rarity-Up-Wurf (EventConfig.RARITY_UP_CHANCE).
local function applyUfoReward(presence: any)
	local player: Player = presence.player
	local data = PlayerService.getData(player)
	if not data then return end

	local baerchi = data.island.baerchis[presence.baerchiUid]
	if not baerchi then return end

	local def      = BaerchiConfig.getById(baerchi.configId)
	local beforeHp = if def then CombatCalculator.getEffectiveStats(baerchi, def.baseStats).maxHp else 0

	local cap    = PromotionConfig.getStatCap(baerchi.rarity)
	local levels = baerchi.statLevels :: any
	local gained: { string } = {}

	for _, key in PromotionConfig.GROWABLE_STATS do
		local old = levels[key] or 0
		if old < cap then
			levels[key] = math.min(cap, old + EventConfig.UFO.STAT_GAIN_PER_STAT)
			table.insert(gained, PromotionConfig.STAT_LABELS[key] or key)
		end
	end

	-- Rarity-Up: nur eine Stufe, Chance sinkt mit der aktuellen Rarity.
	local oldRarity = baerchi.rarity
	local rarityUp: string? = nil
	local chance = EventConfig.getRarityUpChance(oldRarity)
	if chance > 0 and math.random() < chance then
		local nextRarity = BaerchiConfig.getNextRarity(oldRarity)
		if nextRarity then
			baerchi.rarity = nextRarity
			rarityUp = nextRarity
		end
	end

	-- Mehr maxHp (Stat-Stufe, hoehere Rarity): Differenz gutschreiben.
	if def then
		local afterHp = CombatCalculator.getEffectiveStats(baerchi, def.baseStats).maxHp
		baerchi.currentHp = math.clamp(
			(baerchi.currentHp or 0) + math.max(0, afterHp - beforeHp),
			0,
			afterHp
		)
	end

	local parts: { string } = {}
	if #gained > 0 then
		table.insert(parts, "+1 " .. table.concat(gained, "/"))
	else
		table.insert(parts, "alle Stats am Maximum")
	end
	if rarityUp then
		table.insert(parts, string.format("RARITY UP: %s -> %s!", oldRarity, rarityUp))
	end

	local gain: any = {
		baerchiUid = presence.baerchiUid,
		eventId    = "Ufo",
		statKey    = nil,
		newLevel   = 0,
		cap        = PromotionConfig.getStatCap(baerchi.rarity),
		bonusText  = "UFO: " .. table.concat(parts, "  •  "),
		mutation   = nil,
		midEvent   = true,
		rarityUp   = rarityUp,
	}
	Remotes.EventStatGained:FireClient(player, gain)

	PlayerService.markDirty(player)
	PlayerService.saveNow(player)

	MapService.celebrateBaerchi(player, presence.baerchiUid, BaerchiConfig.getRarityColor(baerchi.rarity))

	print("[EventParticipationService]", player.Name, "| UFO:", table.concat(parts, " | "))
end

local function buildApi(token: number): any
	local api: any = {}

	api.center = MapService.getEventPitPosition()
	api.radius = MapService.getEventPitRadius()

	api.running = function(): boolean
		return _sessionToken == token
	end

	api.footOf = footPosOf

	-- Alle Teilnehmer, die gerade am Event stehen und deren Figur existiert.
	-- Entfuehrte (abducting) sind nicht dabei.
	api.participants = function(): { any }
		local list = {}
		for player, presence in _present do
			local figure = MapService.getBaerchiModel(player, presence.baerchiUid)
			if figure and not presence.abducting then
				presence.player = player
				presence.figure = figure
				table.insert(list, presence)
			end
		end
		return list
	end

	api.stillHere = function(part: any): boolean
		return part.player ~= nil and _present[part.player] == part
	end

	api.plotPosition = function(player: Player): Vector3?
		local cf = MapService.getPlotCFrame(player)
		return if cf then cf.Position else nil
	end

	api.level = function(part: any): number
		local data = PlayerService.getData(part.player)
		local baerchi = if data then data.island.baerchis[part.baerchiUid] else nil
		return if baerchi then baerchi.level else 1
	end

	-- Kampfstaerke fuer Duelle: ATK * maxHp (wie CombatCalculator).
	api.power = function(part: any): number
		local data = PlayerService.getData(part.player)
		local baerchi = if data then data.island.baerchis[part.baerchiUid] else nil
		if not baerchi then return 1 end
		local def = BaerchiConfig.getById(baerchi.configId)
		if def then
			local ok, stats = pcall(CombatCalculator.getEffectiveStats, baerchi, def.baseStats)
			if ok and stats then
				local s: any = stats
				return math.max(1, s.atk or 1) * math.max(1, s.maxHp or 1)
			end
		end
		return math.max(1, baerchi.level)
	end

	api.toast = toast

	api.recall = function(player: Player)
		EventParticipationService.recall(player)
	end

	api.finishHome = finishHome
	api.ufoReward  = applyUfoReward

	-- Laeuft die Figur zu `target` (nur X/Z, Y bleibt). Blockiert bis zur
	-- Ankunft oder bis die Bewegung abgebrochen wurde. true = angekommen.
	api.walkTo = function(part: any, target: Vector3): boolean
		local figure: Model? = part.figure
		if not figure or not figure.Parent or part.busy or _present[part.player] ~= part then
			return false
		end

		part.busy       = true
		part.cancelWalk = false

		local ok, err = pcall(function()
			FigureFX.stopIdle(figure)
			local from = footPosOf(figure)
			FigureWalker.walk(figure, from, Vector3.new(target.X, from.Y, target.Z), {
				speed       = EVENT_WALK_SPEED,
				isCancelled = function(): boolean
					return part.cancelWalk == true
						or _present[part.player] ~= part
						or figure.Parent == nil
				end,
			})
		end)
		if not ok then
			warn("[EventParticipationService] walkTo fehlgeschlagen:", err)
		end

		local cancelled = part.cancelWalk == true or _present[part.player] ~= part
		part.busy       = false
		part.cancelWalk = false

		-- Der Spieler wollte waehrenddessen zurueck: jetzt ausfuehren.
		if _recallPending[part.player] and _present[part.player] == part then
			_recallPending[part.player] = nil
			EventParticipationService.recall(part.player)
			return false
		end

		return ok and not cancelled
	end

	return api
end

local function onEventStarted(def: EventConfig.EventDef)
	if _session then
		pcall(_session.stop)
		_session = nil
	end

	_sessionToken += 1

	local handler = (EventHandlers :: any)[def.handler]
	if not handler then
		warn("[EventParticipationService] Kein Handler fuer Event:", def.id, def.handler)
		return
	end

	local ok, session = pcall(handler, buildApi(_sessionToken), def)
	if ok then
		_session = session
	else
		warn("[EventParticipationService] Handler-Start fehlgeschlagen:", session)
	end
end

--------------------------------------------------------------------------------
-- Aufraeumen
--------------------------------------------------------------------------------

-- Eine Teilnahme kann auf drei Wegen ungueltig werden, ohne dass jemand
-- "zurueck" gedrueckt hat: ein Kampf nimmt das Schloss per forceAcquire, die
-- Figur verschwindet (Rebirth, Insel-Neuaufbau), oder der Baerchi ist nicht
-- mehr der ausgeruestete. In allen drei Faellen wird der Eintrag hier still
-- geraeumt — die Figur selbst gehoert dann bereits jemand anderem.
local function tick()
	for player, presence in _present do
		local data = PlayerService.getData(player)

		local lost = data == nil
			or player.Parent == nil
			or ActivityLock.owner(player) ~= LOCK_HOLDER
			or (data :: Types.PlayerData).island.equippedUid ~= presence.baerchiUid
			or MapService.getBaerchiModel(player, presence.baerchiUid) == nil

		if lost then
			_present[player] = nil
			ActivityLock.release(player, LOCK_HOLDER)

			if player.Parent ~= nil then
				notifyPresence(player, false, nil)
			end
		end
	end
end

--------------------------------------------------------------------------------
-- Oeffentliche API
--------------------------------------------------------------------------------

-- v12: Phase fuer die Pet-Leiste: "ToEvent", "AtEvent", "Returning" oder nil.
function EventParticipationService.getPhase(player: Player): string?
	if _present[player] then
		return "AtEvent"
	end
	if _walking[player] then
		return if _walkDir[player] == "to" and not _cancelTo[player] then "ToEvent" else "Returning"
	end
	return nil
end

-- v12: wird der Baerchi gerade vom UFO entfuehrt? (Event-Knopf gesperrt)
function EventParticipationService.isAbducting(player: Player): boolean
	local presence = _present[player]
	return presence ~= nil and presence.abducting == true
end

function EventParticipationService.init()
	-- (v12: Hinschicken und Zurueckholen laufen ueber PetModeService /
	-- RequestPetMode, nicht mehr ueber eigene Remotes.)

	EventService.onEventStarted(onEventStarted)
	EventService.onEventEnded(onEventEnded)

	-- Beim Start eines Events die Bewegung der bereits Anwesenden umstellen —
	-- sonst nickt ein Baerchi weiter im Pausen-Takt, obwohl das Event laeuft.
	-- Bewusst ueber denselben Tick wie die Aufraeum-Pruefung: ein zweiter
	-- Callback in EventService waere mehr Mechanik als der Effekt wert ist.
	Players.PlayerRemoving:Connect(function(player)
		_present[player]  = nil
		_walking[player]  = nil
		_walkDir[player]  = nil
		_cancelTo[player] = nil
	end)

	task.spawn(function()
		local lastEventId: string? = nil

		while true do
			task.wait(CHECK_INTERVAL)

			local ok, err = pcall(function()
				tick()

				local active  = EventService.getActive()
				local nowId   = if active then active.id else nil

				if nowId ~= lastEventId then
					lastEventId = nowId
					for player, presence in _present do
						local figure = MapService.getBaerchiModel(player, presence.baerchiUid)
						if figure and not presence.busy and not presence.abducting then
							playEventMotion(figure)
						end
					end
				end
			end)

			if not ok then
				warn("[EventParticipationService] Tick fehlgeschlagen:", err)
			end
		end
	end)

	print("[EventParticipationService] Initialisiert | Intervall:", CHECK_INTERVAL, "s")
end

return EventParticipationService
