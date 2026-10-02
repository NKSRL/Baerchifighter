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
local Loc           = require(ReplicatedStorage.Localization.Loc)
local MapConfig        = require(ReplicatedStorage.Config.MapConfig)
local EventConfig      = require(ReplicatedStorage.Config.EventConfig)
local EggConfig        = require(ReplicatedStorage.Config.EggConfig)
local BuildingBehavior = require(ReplicatedStorage.Config.BuildingBehavior)
local BaerchiConfig    = require(ReplicatedStorage.Config.BaerchiConfig)
local PromotionConfig  = require(ReplicatedStorage.Config.PromotionConfig)
local CombatCalculator = require(ReplicatedStorage.Modules.CombatCalculator)

local FigureWalker    = require(ServerScriptService.Util.FigureWalker)
local FigurePlacement = require(ServerScriptService.Util.FigurePlacement)
local FigureFX        = require(ServerScriptService.Util.FigureFX)
local ActivityLock    = require(ServerScriptService.Util.ActivityLock)
local RateLimiter     = require(ServerScriptService.Util.RateLimiter)
local PlayerService   = require(ServerScriptService.Services.PlayerService)
local EconomyService  = require(ServerScriptService.Services.EconomyService)
local MapService      = require(ServerScriptService.Services.MapService)
local EventService    = require(ServerScriptService.Services.EventService)

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
}

-- Spieler, deren Baerchi gerade AM Event steht (fertig angekommen).
local _present: { [Player]: Presence } = {}

-- Spieler, deren Baerchi gerade laeuft (hin oder zurueck). Verhindert, dass
-- zwei Laufbewegungen gleichzeitig an derselben Figur ziehen.
local _walking: { [Player]: boolean } = {}

--------------------------------------------------------------------------------
-- Hilfen
--------------------------------------------------------------------------------

local function fail(player: Player, action: string, reason: Types.LocMsg?)
	Remotes.ActionFailed:FireClient(player, action, reason or Loc.msg("err.unknown"))
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

function EventParticipationService.sendToEvent(player: Player)
	local data = PlayerService.getData(player)
	if not data then return end

	if _present[player] or _walking[player] then
		fail(player, "RequestSendToEvent", Loc.msg("err.event_already_away"))
		return
	end

	local uid = data.island.equippedUid
	if not uid or not data.island.baerchis[uid] then
		fail(player, "RequestSendToEvent", Loc.msg("err.event_no_equipped"))
		return
	end

	local figure = MapService.getBaerchiModel(player, uid)
	if not figure then
		fail(player, "RequestSendToEvent", Loc.msg("err.event_not_on_plot"))
		return
	end

	-- Ein laufender Kampf oder ein Weg zum Honig-Teich hat Vorrang: wir nehmen
	-- das Schloss NICHT weg (kein forceAcquire), sondern sagen es dem Spieler.
	-- Der Autopilot gibt es nach ein paar Sekunden von selbst wieder frei.
	if not ActivityLock.tryAcquire(player, LOCK_HOLDER) then
		fail(player, "RequestSendToEvent", Loc.msg("err.baerchi_busy"))
		return
	end

	_walking[player] = true

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
				isCancelled = cancelled,
			})

			if cancelled() then
				return
			end

			-- FigureWalker haelt die Y-Koordinate des STARTPUNKTES ueber die
			-- ganze Strecke (siehe dort). Das Event-Podest liegt hoeher als der
			-- Plot, also wird die Figur hier noch einmal sauber auf die
			-- Podest-Oberflaeche gesetzt — mit Blick zur Mitte.
			FigurePlacement.placeLookingAt(figure, standFoot, MapService.getEventPitPosition())

			_present[player] = {
				baerchiUid = uid,
				homeFoot   = homeFoot,
				standFoot  = standFoot,
				arrivedAt  = os.time(),
			}

			playEventMotion(figure)
			notifyPresence(player, true, uid)

			print("[EventParticipationService]", player.Name, "| am Event:", uid)
		end)

		_walking[player] = nil

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
end

function EventParticipationService.recall(player: Player)
	local presence = _present[player]
	if not presence then
		fail(player, "RequestRecallFromEvent", Loc.msg("err.event_not_at_event"))
		return
	end

	if _walking[player] then
		return   -- laeuft schon zurueck
	end

	local figure = MapService.getBaerchiModel(player, presence.baerchiUid)

	-- Figur ist weg (Equip-Wechsel, Rebirth, Insel neu gebaut): Zustand
	-- einfach aufraeumen statt einen Rueckweg zu erfinden.
	if not figure then
		_present[player] = nil
		ActivityLock.release(player, LOCK_HOLDER)
		notifyPresence(player, false, nil)
		return
	end

	_walking[player]  = true
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

			FigureWalker.walk(figure, presence.standFoot, presence.homeFoot, {
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
		ActivityLock.release(player, LOCK_HOLDER)

		if not ok then
			warn("[EventParticipationService] Rueckweg fehlgeschlagen:", err)
		end
	end)
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

		local eggType = bonus.eggType or "BasicEgg"
		data.island.eggStock[eggType] = (data.island.eggStock[eggType] or 0) + amount

		local eggDef = EggConfig.data[eggType]
		return string.format("+%dx %s", amount, if eggDef then eggDef.displayName else eggType), nil
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
		if math.random() >= (bonus.chance or 0) then
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

		local key                 = awardStatLevel(baerchi, finished.statFocus)
		local bonusText, mutation = awardBonus(player, data, baerchi, finished.bonus)

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

		local statText = "keine Stufe (alles am Cap)"
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

-- Steht der Baerchi dieses Spielers gerade am Event? Fuer andere Services
-- (aktuell liest das niemand — die Auskunft an den Client laeuft ueber
-- EventPresenceChanged).
function EventParticipationService.isAtEvent(player: Player): boolean
	return _present[player] ~= nil
end

function EventParticipationService.init()
	RateLimiter.connect(Remotes.RequestSendToEvent, "RequestSendToEvent", function(player)
		EventParticipationService.sendToEvent(player)
	end)

	RateLimiter.connect(Remotes.RequestRecallFromEvent, "RequestRecallFromEvent", function(player)
		EventParticipationService.recall(player)
	end)

	EventService.onEventEnded(onEventEnded)

	-- Beim Start eines Events die Bewegung der bereits Anwesenden umstellen —
	-- sonst nickt ein Baerchi weiter im Pausen-Takt, obwohl das Event laeuft.
	-- Bewusst ueber denselben Tick wie die Aufraeum-Pruefung: ein zweiter
	-- Callback in EventService waere mehr Mechanik als der Effekt wert ist.
	Players.PlayerRemoving:Connect(function(player)
		_present[player] = nil
		_walking[player] = nil
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
						if figure then
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
