--!strict
-- PitArenaService.luau
-- ServerScriptService/Services/PitArenaService.luau
--
-- Einzige Zustaendigkeit:
--   - Einen von CombatService fertig simulierten PIT-Lauf in der Arena
--     abspielen und dabei den Lauf ZEITLICH fuehren: Hinweg, Stage fuer Stage,
--     Rueckweg, Zurueckholen und Abbruch
--
-- Zum Fuehren gehoert, dass dieser Service entscheidet, WANN abgerechnet und
-- WANN das Ergebnis verschickt wird — beides haengt an der Wiedergabe:
--   - Abrechnung: CombatService gibt eine Funktion (settle) mit. Sie laeuft
--     GENAU EINMAL mit der Zahl der tatsaechlich gespielten Stages: alle bei
--     normalem Ende, bis einschliesslich der laufenden beim Zurueckholen
--     (requestRecall; vor der ersten Stage: 0), und beim Verlassen so, als
--     waere die begonnene Stage zu Ende gespielt (PlayerService.onPlayerLeaving).
--     WAS abgerechnet wird, weiss nur CombatService; dieser Service fasst
--     Spielerdaten selbst nicht an.
--   - Ergebnis: Remotes.CombatResultReceived geht erst raus, wenn abgerechnet
--     ist. sendResult() ist die einzige Stelle, die es abschickt, und
--     idempotent — alle Abbruch- und Erfolgspfade duerfen es aufrufen.
--   - Phase (ToPit / InPit / Returning) und laufende Stage meldet er fuer
--     die Pet-Leiste (PetModeService liest getPhase).
--
-- Warum auf dem SERVER und nicht im Client: die Arenen liegen in derselben
-- Welt wie alle Plots. Serverseitig kann ein Nachbar ueber den Steg kommen
-- und zuschauen.
--
-- Die Figur wird nicht kopiert, sondern die ECHTE Figur vom Plot wandert in
-- die Arena und danach exakt an ihren Platz zurueck. Eine zweite Kopie waere
-- sonst gleichzeitig auf dem Plot zu sehen.
--
-- ============================================================
-- HEIMKEHR — die eigentliche Schwierigkeit
-- ============================================================
-- Der Ausgangs-Pivot der Figur darf NICHT beim Start jeder Wiedergabe frisch
-- abgelesen werden: startet ein zweiter Lauf waehrend der erste noch laeuft,
-- stuende die Figur da schon in der Arena und wuerde spaeter genau dorthin
-- "zurueckgesetzt". Deshalb merkt sich dieser Service den Platz auf dem Plot
-- getrennt (_home) und raeumt einen laufenden Lauf IMMER erst komplett auf,
-- bevor ein neuer beginnt.
--
-- Abbrechen kann die Wiedergabe ausserdem: der Spieler geht, oder der Plot
-- wird neu gebaut (dann ist die Figur weg). Beides wird geprueft, und in
-- keinem Fall bleibt etwas Halbes stehen.
--
-- ============================================================
-- ZUG UM ZUG
-- ============================================================
-- CombatService gibt pro Stage die einzelnen Zuege mit (Types.FightBeat).
-- Jede Stage wird als Folge von Stoessen gezeigt: die Baerchis laufen
-- aufeinander zu und prallen zusammen (FigureFX.clash). Unter dem eigenen
-- HP-Balken laeuft eine Ladeleiste (Util/FightBars); ist sie voll, kommt die
-- Faehigkeit mit ihrer Show (SkillFX, beim ersten Mal voll, danach als Echo).
-- WELCHE Zuege in die Zeit passen, rechnet FightTimeline.
--
-- startPlayback ist bewusst EINE lange Funktion: sie erzaehlt den Ablauf
-- eines Laufs von vorn nach hinten, und ihre Schritte teilen viel Zustand.
-- Zerlegt in viele kleine Funktionen muesste man zum Verstehen hin und her
-- springen.

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local FeatureFlags    = require(ReplicatedStorage.Config.FeatureFlags)
local MapConfig   = require(ReplicatedStorage.Config.MapConfig)
local TowerConfig = require(ReplicatedStorage.Config.TowerConfig)
local SkillConfig = require(ReplicatedStorage.Config.SkillConfig)
local SkillFXConfig = require(ReplicatedStorage.Config.SkillFXConfig)
local BaerchiMesh = require(ReplicatedStorage.Modules.BaerchiMesh)
local FightTimeline = require(ReplicatedStorage.Modules.FightTimeline)
local Types       = require(ReplicatedStorage.Network.Types)
local Remotes     = require(ReplicatedStorage.Network.Remotes)

local PlayerService   = require(ServerScriptService.Services.PlayerService)
local MapService      = require(ServerScriptService.Services.MapService)
local FigureWalker    = require(ServerScriptService.Util.FigureWalker)
local FigurePlacement = require(ServerScriptService.Util.FigurePlacement)
local FigureFX        = require(ServerScriptService.Util.FigureFX)
local ActivityLock    = require(ServerScriptService.Util.ActivityLock)
local FightBars       = require(ServerScriptService.Util.FightBars)

-- Name unter dem PitArenaService das Bewegungs-Schloss haelt (siehe
-- ActivityLock) — verhindert dass BaerchiAutopilotService den Baerchi
-- waehrend eines Kampf-Laufs zum Honig-Teich abzieht.
local LOCK_HOLDER = "Kampf"

local PitArenaService = {}

-- HBB Paket 5 (MAP_V2_ARENA_SPRINT): auf dem Weg Plot <-> Arena sprintet der
-- Baerchi (MapConfig.ARENA_WALK_SPEED) statt zu gehen — weniger Warten je Lauf.
local function arenaWalkSpeed(): number
	return if FeatureFlags.isOn("MAP_V2_ARENA_SPRINT") then MapConfig.ARENA_WALK_SPEED else MapConfig.WALK_SPEED
end

-- Gleich viele Hopser pro SEKUNDE wie beim Gehen, dafuer weitere: schnelleres
-- Huepfen liest das Auge als Zittern (siehe MapConfig.WALK_BOB_PER_STUD).
local function arenaBobPerStud(): number
	return MapConfig.WALK_BOB_PER_STUD * MapConfig.WALK_SPEED / arenaWalkSpeed()
end

-- Laufende Wiedergabe pro Spieler. Startet ein neuer Lauf, wird der alte
-- Token ungueltig und die alte Schleife beendet sich beim naechsten Schritt.
local _runToken: { [Player]: number } = {}

-- Ergebnis, das der Client noch nicht bekommen hat. Wird gesetzt sobald ein
-- Lauf beginnt und erst gefeuert, wenn der Baerchi sichtbar am Kampf-Spot
-- angekommen ist (siehe sendResult) — vorher liefe die Kampf-UI schon,
-- waehrend er noch zur Arena unterwegs waere. Bleibt die Wiedergabe aus
-- irgendeinem Grund stecken (kein Plot, Fehler waehrend des Laufs), wird an
-- den Abbruchstellen trotzdem gesendet, damit der Client nie ganz ohne
-- Ergebnis dasteht.
--
-- Der Eintrag traegt seinen eigenen Token: `isRunning` verhindert zwar, dass
-- ueberhaupt ein zweiter Lauf waehrend eines laufenden startet, aber ohne den
-- Token wuerde selbst ein knapp daneben abgewiesener Request die
-- Abbruch-Fallbacks eines ANDEREN, spaeter gestarteten Laufs treffen und
-- dessen Ergebnis zu frueh verschicken — genau der Fehler, den sendResult
-- eigentlich beheben soll. sendResult prueft den Token deshalb mit.
-- v12: Abrechnung und Zustand des laufenden Laufs. `entered` = wie viele
-- Stages bereits BEGONNEN haben (fuer die Abrechnung bei Abbruch), `phase`
-- und `stage` fuer die Anzeige, `recall` = Spieler will zurueck.
export type SettleFn = (played: number, recalled: boolean) -> Types.PitRunResult
type Active = {
	token   : number,
	run     : Types.PitRunResult,
	settle  : SettleFn?,
	settled : Types.PitRunResult?,
	sent    : boolean,
	entered : number,
	recall  : boolean,
	beats   : { { Types.FightBeat } }?,   -- v15: Zuege je Stage (Index = Stage im Lauf)
	phase   : string,     -- "ToPit" | "InPit" | "Returning"
	stage   : number?,
}
local _active: { [Player]: Active } = {}

-- Wo die gerade kaempfende Figur auf dem Plot hingehoert. homeFoot ist der
-- Fusspunkt VOR dem Loslaufen (fuer den Weg zurueck), pivot der exakte
-- Ausgangszustand (fuer den abschliessenden Snap in restoreHome).
type Home = { model: Model, pivot: CFrame, homeFoot: Vector3 }
local _home: { [Player]: Home } = {}

--------------------------------------------------------------------------------
-- Hilfen
--------------------------------------------------------------------------------

-- Bringt eine noch in der Arena stehende Figur an ihren Platz auf dem Plot
-- zurueck und raeumt ihren Kampf-Balken weg. Idempotent: zweimal aufrufen
-- schadet nicht.
local function restoreHome(player: Player)
	local home = _home[player]
	if not home then return end

	_home[player] = nil

	local model = home.model
	if model.Parent ~= nil then
		FightBars.removeHealthBar(model)
		model:SetAttribute("InArena", nil)

		-- ZUERST abmelden, DANN heimsetzen — nie andersherum. Waehrend des
		-- Kampfs atmet die Figur am Kampf-Spot, ihre gemerkte Ruhelage ist also
		-- die Arena-Position. Ein spaeteres Abmelden wuerde sie genau dorthin
		-- zuruecksetzen und die Heimkehr wieder zunichtemachen.
		FigureFX.stopIdle(model)
		model:PivotTo(home.pivot)

		-- Zuhause angekommen und wieder in Ruhe: `home.pivot` ist garantiert
		-- die saubere Ruhelage, weil startPlayback das Atmen VOR dem Merken
		-- abgeschaltet hat.
		FigureFX.idleBob(model, {
			height = MapConfig.IDLE_BOB_HEIGHT,
			rate   = MapConfig.IDLE_BOB_RATE,
		})
	end
end

-- Alle Gegner-Figuren aus der Arena raeumen.
local function clearFighters(player: Player)
	local fighters = MapService.getFighterFolder(player)
	if not fighters then return end

	for _, child in fighters:GetChildren() do
		child:Destroy()
	end
end

-- Text auf der Anzeigetafel ueber der Arena. Die Tafel selbst gehoert
-- MapService; hier wird nur entschieden WAS draufsteht, weil nur dieser
-- Service den Verlauf des Laufs kennt.
-- v15: "Tower II · Stage 23"
local function stageTitle(towerId: string?, stage: number): string
	local def = TowerConfig.get(towerId or "") or TowerConfig.TOWERS[1]
	return string.format("Tower %s  ·  Stage %d", def.numeral, stage)
end

local function showStage(player: Player, towerId: string?, stage: Types.PitStageResult, cleared: number)
	MapService.setPitBanner(
		player,
		stageTitle(towerId, stage.stage),
		if cleared > 0
			then string.format("%d geschafft", cleared)
			else "erster Gegner",
		MapConfig.PIT_BANNER_RUNNING
	)
end

local function showSummary(player: Player, run: Types.PitRunResult)
	-- "Geschafft" ist die Zahl gewonnener Stages. Sie kann 0 sein — dann hat
	-- der Baerchi den ersten Gegner nicht ueberlebt, und genau das soll auch
	-- dastehen statt eines beschoenigenden "0 geschafft".
	local won = run.stagesCleared > 0

	MapService.setPitBanner(
		player,
		if won
			then string.format("%d Stages geschafft", run.stagesCleared)
			else "Keine Stage geschafft",
		string.format("%d Gummies", run.gummiesWon),
		if won then MapConfig.PIT_BANNER_WIN else MapConfig.PIT_BANNER_LOSS
	)
end

-- Schickt das Kampfergebnis an den Client — idempotent, weil mehrere
-- Abbruch- und Erfolgspfade das hier alle "auf gut Glueck" aufrufen koennen.
-- Erst danach darf CombatPanel seine Stage-Wiedergabe starten; siehe die
-- Aufrufstelle in startPlayback fuer den genauen Zeitpunkt (Ankunft am
-- Kampf-Spot).
-- `token` muss zu dem Lauf gehoeren, der sendResult aufruft — sonst koennte
-- der Abbruch-Fallback eines ueberholten Laufs A das laengst neu gesetzte
-- _pendingResult eines inzwischen gestarteten Laufs B verschicken, noch
-- bevor dessen eigener Baerchi angekommen ist.
-- v12: rechnet ab (einmal) und gibt das abgerechnete Ergebnis zurueck. Ohne
-- settle-Funktion (Altaufruf) zaehlt der volle Lauf.
local function settleActive(active: Active, played: number, recalled: boolean): Types.PitRunResult
	if active.settled then
		return active.settled
	end

	local settle = active.settle
	local result = active.run
	if settle then
		local ok, res = pcall(settle, played, recalled)
		if ok then
			result = res
		else
			warn("[PitArenaService] Abrechnung fehlgeschlagen:", res)
		end
	end

	active.settled = result
	return result
end

-- Schickt das ABGERECHNETE Ergebnis an den Client — idempotent und nur fuer
-- den Lauf, zu dem der Token gehoert. Wurde noch nicht abgerechnet (Abbruch),
-- wird hier mit den bereits begonnenen Stages abgerechnet.
local function sendResult(player: Player, token: number)
	local active = _active[player]
	if not active or active.token ~= token or active.sent then return end
	active.sent = true

	local result = settleActive(active, active.entered, active.recall)
	if player.Parent ~= nil then
		Remotes.CombatResultReceived:FireClient(player, result)
	end
end

-- Den Erschoepfungs-Zustand nachziehen, der waehrend der Wiedergabe
-- unterdrueckt war.
local function refreshState(player: Player)
	local data = PlayerService.getData(player)
	if data then
		MapService.updateBaerchiStates(player, data.island)
	end
end

--------------------------------------------------------------------------------
-- Wiedergabe
--------------------------------------------------------------------------------

-- Steht die Wiedergabe noch? Prueft alles was sie abbrechen kann:
-- ein neuer Lauf, der Spieler geht, der Plot wird neu gebaut (Figur weg),
-- oder das PIT wird ausgebaut (dann ist der Kaempfer-Ordner mit zerstoert
-- worden und neue Gegner landeten unsichtbar im Nirgendwo).
local function setPhase(player: Player, token: number, phase: string, stage: number?)
	local active = _active[player]
	if active and active.token == token then
		active.phase = phase
		active.stage = stage
	end
end

local function recallWanted(player: Player, token: number): boolean
	local active = _active[player]
	return active ~= nil and active.token == token and active.recall
end

local function stillValid(player: Player, token: number, figure: Model, fighters: Folder): boolean
	if _runToken[player] ~= token then return false end
	if player.Parent == nil then return false end
	if figure.Parent == nil then return false end
	if fighters.Parent == nil then return false end
	return true
end

-- v12: Laesst den Turm Etage fuer Etage von `fromLevel` auf `toLevel` wachsen
-- (oder schrumpfen) und haelt die Figur dabei immer oben auf der aktuellen
-- Etage. Bei sehr hohen Tuermen wachsen mehrere Etagen pro Schritt, damit es
-- nie laenger als `seconds` dauert. Die Figur darf waehrenddessen NICHT im
-- Idle-Loop sein (der Aufrufer meldet sie ab und danach wieder an).
-- Gibt false zurueck, wenn die Wiedergabe unterwegs ungueltig wurde.
local function rideTower(
	player: Player, token: number, figure: Model, fighters: Folder,
	fromLevel: number, toLevel: number, seconds: number,
	selfPos: Vector3, enemyPos: Vector3
): boolean
	local distance = math.abs(toLevel - fromLevel)
	if distance == 0 then return true end

	-- Hoechstens ~20 Schritte pro Sekunde: mehr sieht niemand, und jeder
	-- Schritt baut bzw. entfernt Teile.
	local steps    = math.max(1, math.min(distance, math.floor(seconds * 20)))
	local stepTime = seconds / steps

	for step = 1, steps do
		if not stillValid(player, token, figure, fighters) then return false end

		local level = fromLevel + math.floor((toLevel - fromLevel) * step / steps + 0.5)
		MapService.setPitTowerLevel(player, level)

		local y = MapService.getPitTowerFloorY(level)
		FigurePlacement.placeLookingAt(
			figure,
			Vector3.new(selfPos.X, y, selfPos.Z),
			Vector3.new(enemyPos.X, y, enemyPos.Z)
		)
		task.wait(stepTime)
	end

	return stillValid(player, token, figure, fighters)
end

local function startPlayback(player: Player, run: Types.PitRunResult, settle: SettleFn?, beats: { { Types.FightBeat } }?)
	-- Das Hochzaehlen des Tokens steht ganz oben und vor allem, was fehlschlagen
	-- kann. Ab hier gehoert die Wiedergabe fuer diesen Spieler UNS — und nur
	-- deshalb darf die Fehlerbehandlung in play() bedenkenlos aufraeumen. Stuende
	-- der Token weiter unten und etwas darueber wuerfe, wuerde play() den Zustand
	-- einer noch laufenden aelteren Wiedergabe zerlegen, die anschliessend
	-- munter weiterliefe: Figur zurueck auf dem Plot, aber weiter Gegner in der
	-- Arena und die Tafel wieder an.
	local token = (_runToken[player] or 0) + 1
	_runToken[player] = token

	-- Ab hier ist der Client faellig fuer dieses Ergebnis. Gefeuert wird es
	-- weiter unten erst bei Ankunft am Kampf-Spot — bricht die Wiedergabe
	-- vorher ab (kein Plot, Fehler), sorgen die Abbruchstellen selbst dafuer,
	-- dass es trotzdem noch rausgeht.
	_active[player] = {
		token   = token,
		run     = run,
		settle  = settle,
		settled = nil,
		sent    = false,
		entered = 0,
		recall  = false,
		beats   = beats,
		phase   = "ToPit",
		stage   = nil,
	}

	-- Ein Kampf hat immer Vorrang vor dem automatischen Weg zum Honig-Teich:
	-- forceAcquire nimmt das Bewegungs-Schloss notfalls dem Autopilot weg.
	-- Der bemerkt das selbst (sein isCancelled prueft den Besitzer) und bricht
	-- sein Hinlaufen sauber ab, statt mit dem Kampf um die Figur zu ringen.
	ActivityLock.forceAcquire(player, LOCK_HOLDER)

	-- Einen noch laufenden Lauf komplett aufraeumen. refreshState gehoert
	-- dazu: dessen Wiedergabe hatte den Zustand der Figur unterdrueckt und
	-- kommt wegen des neuen Tokens nicht mehr dazu, ihn nachzuziehen — der
	-- alte Baerchi staende sonst mit veralteter Beschriftung auf dem Plot.
	--
	-- Das passiert bewusst VOR den Abbruchgruenden unten: auch wenn diese
	-- Wiedergabe gar nicht erst startet, muss die alte sauber beendet sein.
	restoreHome(player)
	refreshState(player)
	clearFighters(player)
	MapService.setPitTowerLevel(player, 0)
	MapService.clearPitBanner(player)

	-- Es gibt keine Show — Ergebnis trotzdem rausschicken UND das Schloss
	-- wieder freigeben.
	--
	-- Das Freigeben stand hier frueher nicht: forceAcquire oben nimmt das
	-- Schloss immer, die beiden Abbruchgruende unten kamen aber ohne
	-- release() zurueck. Wer also einmal ohne Plot oder ohne gerenderte Figur
	-- in einen Lauf ging, behielt "Kampf" als Schloss-Besitzer fuer den Rest
	-- der Sitzung — der Autopilot ging nie wieder essen, und seit dem
	-- ActivityLock-Schutz wuerden auch Ausruesten, Verwerten und der
	-- Figuren-Neuaufbau dauerhaft abgelehnt. Nur der Fehler-Pfad
	-- (PitArenaService.play) hat freigegeben, der stille Abbruch nicht.
	local function abortPlayback()
		-- Keine Show moeglich: der Lauf zaehlt trotzdem voll (wie vor v12),
		-- er ist ja schon entschieden.
		local active = _active[player]
		if active and active.token == token then
			active.entered = #run.stages
		end
		sendResult(player, token)
		ActivityLock.release(player, LOCK_HOLDER)
		if _active[player] and _active[player].token == token then
			_active[player] = nil
		end
	end

	local center     = MapService.getPitPosition(player)
	local plotCFrame = MapService.getPlotCFrame(player)
	local fighters   = MapService.getFighterFolder(player)
	local figure     = MapService.getBaerchiModel(player, run.baerchiUid)

	-- Fehlt irgendetwas davon (kein Plot, kein Mesh-Template, Figur nicht
	-- gerendert), gibt es einfach keine Show. Der Lauf selbst ist davon
	-- unberuehrt — er ist laengst abgerechnet.
	if not center or not plotCFrame or not fighters or not figure then
		abortPlayback()
		return
	end

	-- typeof statt nur #: kaeme ein Lauf ohne stages-Tabelle herein, waere das
	-- sonst ein Fehler mitten in der Abrechnung statt einer stillen Nicht-Show.
	if typeof(run.stages) ~= "table" or #run.stages == 0 then
		abortPlayback()
		return
	end

	-- Ruhe-Atmen abschalten, BEVOR die Heimatposition gemessen wird: die Figur
	-- schwebt sonst gerade um einen Bruchteil ihres Hubs ueber der Ruhelage,
	-- und genau dieser Versatz wanderte dann in _home.pivot — nach jedem Kampf
	-- staende sie ein Stueckchen hoeher als vorher. stopIdle setzt sie dafuer
	-- selbst auf ihre Ruhelage zurueck.
	FigureFX.stopIdle(figure)

	local homeBox, homeSize = figure:GetBoundingBox()
	local homeFoot = Vector3.new(homeBox.Position.X, homeBox.Position.Y - homeSize.Y * 0.5, homeBox.Position.Z)
	_home[player] = { model = figure, pivot = figure:GetPivot(), homeFoot = homeFoot }

	local maxHp = math.max(1, run.maxHp)

	-- v14: welche Faehigkeit gezeigt wird (SkillFX). Die volle Show laeuft
	-- beim ersten Einsatz eines Laufs, danach nur ein kurzes Echo — sonst
	-- wuerde ein Lauf mit vielen Stages Minuten dauern.
	local fxData = PlayerService.getData(player)
	local fxBaerchi = fxData and fxData.island.baerchis[run.baerchiUid]
	local fxSkillId: string? = fxBaerchi and fxBaerchi.skillId
	local fxShownFull = false

	-- v15: Ladeleiste nur, wenn die Faehigkeit ueberhaupt aufgeladen wird
	-- (Passive und Grundschlag haben charge = 0).
	local fxSkill = fxSkillId and SkillConfig.getById(fxSkillId)
	local showsCharge = fxSkill ~= nil and (fxSkill.charge or 0) > 0

	-- Die beiden Kaempfer stehen sich quer zur Bruecke gegenueber, damit man
	-- sie beim Herueberlaufen von der Seite sieht statt hintereinander.
	local side     = plotCFrame.RightVector
	local selfPos  = center - side * MapConfig.FIGHT_SPACING
	local enemyPos = center + side * MapConfig.FIGHT_SPACING

	-- Die Figur gehoert jetzt uns: MapService laesst ihren Zustand in Ruhe,
	-- bis das Attribut wieder weg ist (sonst saehe sie mitten im Kampf
	-- erschoepft aus, weil die HP serverseitig schon final sind).
	figure:SetAttribute("InArena", true)

	-- Die Figur auf den Zustand VOR dem Lauf zuruecksetzen. Die gespeicherten
	-- HP stehen zu diesem Zeitpunkt schon auf dem Endwert — ohne diese Zeile
	-- stuende der Baerchi bereits blass und mit "erschoepft" beschriftet da,
	-- bevor der erste Gegner ueberhaupt erscheint.
	MapService.setFigureState(figure, run.hpBefore, maxHp)

	task.spawn(function()
		local selfFill: Frame? = nil
		local chargeFill: Frame? = nil

		local ok, err = pcall(function()
			-- Erst hinlaufen: der Kampf soll sichtbar ERST beginnen, wenn der
			-- Baerchi an der Plattform angekommen ist, nicht durch einen
			-- Teleport. FigureWalker haelt den Fusspunkt waehrenddessen exakt
			-- auf Plot-/Bruecken-Hoehe.
			FigureWalker.walk(figure, homeFoot, selfPos, {
				speed       = arenaWalkSpeed(),
				bobPerStud  = arenaBobPerStud(),
				isCancelled = function()
					return not stillValid(player, token, figure, fighters) or recallWanted(player, token)
				end,
			})
			if not stillValid(player, token, figure, fighters) then
				sendResult(player, token)
				return
			end

			-- v12: auf dem Hinweg zurueckgeholt — noch keine Stage begonnen.
			-- Abrechnung mit 0 Stages (erstattet eine bezahlte Fortsetzung),
			-- dann von hier aus heimlaufen.
			if recallWanted(player, token) then
				sendResult(player, token)
				setPhase(player, token, "Returning", nil)
				local box, size = figure:GetBoundingBox()
				local here = Vector3.new(box.Position.X, box.Position.Y - size.Y * 0.5, box.Position.Z)
				FigureWalker.walk(figure, here, homeFoot, {
					speed       = arenaWalkSpeed(),
					bobPerStud  = arenaBobPerStud(),
					isCancelled = function() return not stillValid(player, token, figure, fighters) end,
				})
				return
			end
			setPhase(player, token, "InPit", nil)

			-- Exakte Ausrichtung zum Gegner: der Lauf endet in Laufrichtung,
			-- gekaempft wird aber gegenueber.
			FigurePlacement.placeLookingAt(figure, selfPos, enemyPos)

			-- Ab hier steht der Baerchi am Kampf-Spot und atmet dort — auch
			-- zwischen den Stages und waehrend der Nachlauf-Pause, in der er
			-- sonst reglos herumstuende. Die Ausfallschritte melden ihn dafuer
			-- selbst kurz ab und danach wieder an (FigureFX.clash).
			FigureFX.idleBob(figure, {
				height = MapConfig.IDLE_BOB_HEIGHT,
				rate   = MapConfig.IDLE_BOB_RATE,
			})

			selfFill = FightBars.attachHealthBar(figure, MapConfig.FIGHT_BAR_SELF_COLOR)
			FightBars.tweenFill(selfFill, run.hpBefore / maxHp, 0.01)
			if showsCharge then
				chargeFill = FightBars.attachChargeBar(figure)
			end

			-- (v12: das Ergebnis geht erst nach der Abrechnung am Ende raus.)

			-- Der Gegner der VORHERIGEN Stage wird erst weggeraeumt wenn der
			-- naechste erscheint. Wuerde er am Ende seiner eigenen Stage
			-- verschwinden, waere die entscheidende letzte Niederlage nie zu
			-- sehen — und in der Nachlauf-Pause staende der eigene Baerchi
			-- allein in der Arena.
			local previousEnemy: Model? = nil

			-- Zaehlt die BEREITS gewonnenen Stages fuer die Anzeigetafel.
			-- Absichtlich nicht run.stagesCleared: das ist das Endergebnis und
			-- waere waehrend der Wiedergabe die halbe Spannung vorweggenommen.
			local cleared = 0

			-- Wo der eigene Baerchi zuletzt stand — auf Bodenhoehe, solange
			-- der Turm noch nicht gewachsen ist, sonst auf der aktuellen
			-- Etage. Der Rueckweg nach der letzten Stage startet von hier,
			-- nicht von der urspruenglichen (Boden-)selfPos.
			local finalSelfPos = selfPos

			-- Aktuelle Turmhoehe (Etagen), fuer den Abstieg am Ende.
			local towerNow = 0

			-- ============================================================
			-- v12: FORTSETZUNG — DER TURM WAECHST ERST BIS ZUR STARTSTAGE
			-- ============================================================
			-- Steigt der Baerchi bei Stage 30 ein, wachsen jetzt alle 29
			-- Etagen darunter sichtbar hoch und er faehrt oben mit. Danach
			-- kaempft er auf genau der Hoehe, auf der Stage 30 bei einem Lauf
			-- von vorn stattfinden wuerde — man sieht, wie weit oben man ist.
			-- v15: gestaucht (TowerConfig.getRunFloor), bei 100 Stages hoechstens
			-- RUN_MAX_FLOORS Etagen.
			local baseLevel = TowerConfig.getRunFloor(run.towerId or "I", run.startStage or 1)
			if baseLevel > 0 and not recallWanted(player, token) then
				MapService.setPitBanner(
					player,
					stageTitle(run.towerId, run.startStage or 1),
					"Der Turm waechst …",
					MapConfig.PIT_BANNER_RUNNING
				)

				local riseSeconds = math.min(
					MapConfig.PIT_TOWER_RISE_MAX_SECONDS,
					baseLevel * MapConfig.PIT_TOWER_RISE_SECONDS_PER_LEVEL
				)

				FigureFX.stopIdle(figure)
				if not rideTower(player, token, figure, fighters, 0, baseLevel, riseSeconds, selfPos, enemyPos) then
					return
				end
				FigureFX.idleBob(figure, {
					height = MapConfig.IDLE_BOB_HEIGHT,
					rate   = MapConfig.IDLE_BOB_RATE,
				})

				towerNow     = baseLevel
				finalSelfPos = Vector3.new(selfPos.X, MapService.getPitTowerFloorY(baseLevel), selfPos.Z)
			end

			for index, stage in run.stages do
				if not stillValid(player, token, figure, fighters) then return end

				-- v12: zurueckgeholt — die vorige Stage ist fertig gespielt,
				-- weitere beginnen nicht mehr.
				if recallWanted(player, token) then break end

				local active = _active[player]
				if active and active.token == token then
					active.entered = index
				end
				setPhase(player, token, "InPit", stage.stage)

				-- Etage dieser Stage: die erste Stage kaempft noch auf der
				-- normalen Kampfflaeche (Etage 0) — sichtbar identisch mit dem
				-- Boden, den man von der Bruecke kennt. Jede weitere Stage
				-- bekommt eine neue Turmetage obendrauf (siehe MapConfig,
				-- Abschnitt "PIT-TURM").
				-- v12: absolute Etage — bei einer Fortsetzung steht der Turm
				-- schon (siehe oben), Stage 30 kaempft auf Etage 29.
				local towerLevel = TowerConfig.getRunFloor(run.towerId or "I", stage.stage)
				MapService.setPitTowerLevel(player, towerLevel)
				towerNow = towerLevel

				local floorY        = MapService.getPitTowerFloorY(towerLevel)
				local stageSelfPos  = Vector3.new(selfPos.X, floorY, selfPos.Z)
				local stageEnemyPos = Vector3.new(enemyPos.X, floorY, enemyPos.Z)
				finalSelfPos = stageSelfPos

				-- Ist der Turm inzwischen gewachsen, steht der eigene Baerchi
				-- eine Etage tiefer als er jetzt muesste — er wird VOR dem
				-- naechsten Gegner mit hochgestellt. Ruhe-Atmen dafuer kurz
				-- abmelden und an der neuen Stelle neu anmelden, sonst zoegen
				-- Idle-Loop und diese Bewegung im selben Frame an derselben
				-- Figur (dieselbe Reihenfolge wie in restoreHome).
				if towerLevel > 0 then
					FigureFX.stopIdle(figure)
					FigurePlacement.placeLookingAt(figure, stageSelfPos, stageEnemyPos)
					FigureFX.idleBob(figure, {
						height = MapConfig.IDLE_BOB_HEIGHT,
						rate   = MapConfig.IDLE_BOB_RATE,
					})
				end

				showStage(player, run.towerId, stage, cleared)

				if previousEnemy and previousEnemy.Parent then
					previousEnemy:Destroy()
				end
				previousEnemy = nil

				local enemy = BaerchiMesh.buildEnemy(stageEnemyPos, MapConfig.FIGHT_ENEMY_COLOR)
				local enemyFill: Frame? = nil

				if enemy then
					FigurePlacement.placeLookingAt(enemy, stageEnemyPos, stageSelfPos)
					enemy.Parent = fighters
					enemyFill = FightBars.attachHealthBar(enemy, MapConfig.FIGHT_BAR_ENEMY_COLOR)
					previousEnemy = enemy

					-- Auch der Gegner soll nicht wie ein Standbild dastehen,
					-- solange er noch lebt.
					FigureFX.idleBob(enemy, {
						height = MapConfig.IDLE_BOB_HEIGHT,
						rate   = MapConfig.IDLE_BOB_RATE,
					})
				end

				-- ====================================================
				-- v15: DIE STAGE ZUG UM ZUG
				-- ====================================================
				local stageBeats: { Types.FightBeat } = (beats and beats[index]) or {}
				if #stageBeats == 0 then
					-- Ohne Zuege (aelterer Aufrufer): ein einziger Stoss, der
					-- das Ergebnis zeigt — wie vor v15.
					stageBeats = { {
						actor   = if stage.won then "A" else "B",
						kind    = "hit",
						selfHp  = stage.hpAfter / maxHp,
						enemyHp = if stage.won then 0 else 0.35,
						charge  = 0,
						skillId = nil,
					} }
				end

				local plan = FightTimeline.plan(stageBeats, #run.stages, stage.won)
				local tempo = plan.tempo

				-- Kurz stehen bleiben, damit man den neuen Gegner sieht.
				task.wait(MapConfig.FIGHT_ENEMY_INTRO_SECONDS * tempo)
				if not stillValid(player, token, figure, fighters) then return end

				for _, beatIndex in plan.indices do
					local beat = stageBeats[beatIndex]
					local isSelf = beat.actor == "A"
					local attacker: Model? = if isSelf then figure else enemy
					local target:   Model? = if isSelf then enemy else figure
					local attackerHome = if isSelf then stageSelfPos else stageEnemyPos
					local targetHome   = if isSelf then stageEnemyPos else stageSelfPos
					local isSkill = FightTimeline.isSkillBeat(beat)

					-- Leisten und Treffer-Rueckmeldung genau im Aufprall.
					local function onImpact()
						local barSeconds = MapConfig.FIGHT_BEAT_SECONDS * tempo * 0.5
						FightBars.tweenFill(selfFill, beat.selfHp, barSeconds)
						FightBars.tweenFill(enemyFill, beat.enemyHp, barSeconds)
						FightBars.setCharge(chargeFill, beat.charge, barSeconds)
						if target and target.Parent ~= nil then
							FigureFX.hitFlash(target, MapConfig.FIGHT_HIT_FLASH_COLOR, MapConfig.FIGHT_HIT_FLASH_SECONDS)
						end
						local contact = (stageSelfPos + stageEnemyPos) * 0.5 + Vector3.new(0, 1.5, 0)
						FigureFX.burstAt(contact, MapConfig.FIGHT_HIT_FLASH_COLOR, fighters,
							MapConfig.FIGHT_BUMP_SPARKS * (if isSkill then 3 else 1))
						FigureFX.soundAt(contact, MapConfig.FIGHT_BUMP_SOUND,
							MapConfig.FIGHT_BUMP_VOLUME * (if isSkill then 1.6 else 1), fighters,
							0.9 + math.random() * 0.25)
					end

					if beat.kind == "stunned" then
						-- Betaeubt: kein Stoss, die Figur taumelt.
						if attacker then
							FightBars.setCharge(chargeFill, beat.charge, 0.1)
							FigureFX.stagger(attacker, MapConfig.FIGHT_BEAT_SECONDS * tempo)
						else
							task.wait(MapConfig.FIGHT_BEAT_SECONDS * tempo)
						end
					else
						-- Faehigkeit: Leiste leuchtet voll auf, die Show laeuft,
						-- dann der wuchtige Stoss.
						if isSkill and isSelf then
							FightBars.setCharge(chargeFill, 1, 0.1)
							local showId = beat.skillId or fxSkillId
							if showId then
								local full = not fxShownFull
								fxShownFull = true
								Remotes.SkillFXPlay:FireAllClients({
									owner    = player.UserId,
									skillId  = showId,
									full     = full,
									attacker = figure,
									target   = enemy,
									center   = (stageSelfPos + stageEnemyPos) / 2,
								})
								task.wait(SkillFXConfig.getDuration(showId, full) * (if full then 1 else tempo))
								if not stillValid(player, token, figure, fighters) then return end
							end
						end

						local seconds = FightTimeline.beatSeconds(beat) * tempo
						if attacker then
							FigureFX.clash(attacker, target, attackerHome, targetHome, {
								seconds   = seconds,
								gap       = MapConfig.FIGHT_CONTACT_GAP,
								hop       = MapConfig.FIGHT_HOP_HEIGHT * (if isSkill then 1.6 else 1),
								knockback = if isSkill then MapConfig.FIGHT_SKILL_KNOCKBACK else MapConfig.FIGHT_KNOCKBACK,
								step      = MapConfig.FIGHT_ENEMY_STEP_SHARE,
								onImpact  = onImpact,
							})
						else
							-- Gegner-Mesh fehlt: nur Leisten und Funken.
							onImpact()
							task.wait(seconds)
						end
					end

					if not stillValid(player, token, figure, fighters) then return end
				end

				-- Leisten auf den echten Endstand der Stage (falls Zuege
				-- ausgelassen wurden, stimmt so trotzdem alles).
				FightBars.tweenFill(selfFill, stage.hpAfter / maxHp, 0.15)
				FightBars.tweenFill(enemyFill, if stage.won then 0 else stageBeats[#stageBeats].enemyHp, 0.15)

				if stage.won then
					cleared += 1

					-- Besiegter Gegner kippt um, bevor der naechste kommt.
					-- Beim letzten Gegner macht das die Nachlauf-Pause unten.
					if index < #run.stages and enemy and enemy.Parent ~= nil then
						FigureFX.defeatCollapse(enemy, MapConfig.FIGHT_KO_SECONDS * tempo)
					end
				end
			end

			-- v12: JETZT abrechnen — mit den tatsaechlich gespielten Stages —
			-- und das Ergebnis an den Client schicken.
			local active = _active[player]
			local finalRun = run
			if active and active.token == token then
				finalRun = settleActive(active, active.entered, active.recall)
			end
			sendResult(player, token)

			-- Der letzte Gegner steht waehrend der Nachlauf-Pause noch da;
			-- weggeraeumt wird er unten von clearFighters.
			showSummary(player, finalRun)

			-- Wer die LETZTE Stage verloren hat, kippt sichtbar um, statt
			-- einfach zu verschwinden bzw. unveraendert stehenzubleiben.
			--
			-- Der eigene Baerchi kippt nur, wenn er den Lauf wirklich
			-- erschoepft beendet (hpAfter <= 0). Sonst laeuft er gleich darauf
			-- selbst nach Hause — eine umgekippte Figur, die losmarschiert,
			-- waere schlechter als gar keine Animation. Zurueckgesetzt wird die
			-- Neigung ohnehin von restoreHome.
			local lastStage = finalRun.stages[#finalRun.stages]
			local loser: Model? = nil

			if lastStage and lastStage.won then
				loser = previousEnemy
			elseif finalRun.hpAfter <= 0 then
				loser = figure
			end

			-- Das Umkippen laeuft INNERHALB der Nachlauf-Pause ab, verlaengert
			-- die Wiedergabe also nicht.
			local collapseSeconds = math.min(
				MapConfig.FIGHT_COLLAPSE_SECONDS,
				MapConfig.FIGHT_LINGER_SECONDS
			)

			if loser and loser.Parent ~= nil then
				FigureFX.defeatCollapse(loser, collapseSeconds)
				task.wait(math.max(0, MapConfig.FIGHT_LINGER_SECONDS - collapseSeconds))
			else
				task.wait(MapConfig.FIGHT_LINGER_SECONDS)
			end

			if not stillValid(player, token, figure, fighters) then return end

			-- Ueberlebt (hpAfter > 0): der Baerchi laeuft selbststaendig zu
			-- seinem Platz zurueck. Erschoepft (hpAfter <= 0): er ist ausser
			-- Gefecht und steht einfach wieder normal auf dem Plot — die
			-- anschliessende restoreHome() setzt ihn dafuer direkt zurueck,
			-- ganz ohne Lauf-Animation.
			if finalRun.hpAfter > 0 then
				setPhase(player, token, "Returning", nil)

				-- Vor dem eigenen PivotTo abmelden: sonst zoegen Idle-Loop und
				-- Lauf-Animation im selben Frame an derselben Figur. Wieder
				-- angemeldet wird sie am Ende von restoreHome, auf ihrem Platz.
				FigureFX.stopIdle(figure)

				-- v12: erst mit dem Turm wieder nach unten fahren — sonst liefe
				-- er auf Turmhoehe durch die Luft nach Hause.
				if towerNow > 0 then
					clearFighters(player)
					if not rideTower(player, token, figure, fighters, towerNow, 0, MapConfig.PIT_TOWER_FALL_SECONDS, selfPos, enemyPos) then
						return
					end
					finalSelfPos = selfPos
				end

				FigureWalker.walk(figure, finalSelfPos, homeFoot, {
					speed       = arenaWalkSpeed(),
					bobPerStud  = arenaBobPerStud(),
					isCancelled = function() return not stillValid(player, token, figure, fighters) end,
				})
			end
		end)

		if not ok then
			warn("[PitArenaService] Wiedergabe fehlgeschlagen:", err)
		end

		-- Fallback: ist die Schleife oben aus irgendeinem Grund abgebrochen
		-- oder auf einen Fehler gelaufen, BEVOR der Baerchi angekommen ist,
		-- haette der Client sonst nie ein Ergebnis bekommen. sendResult ist
		-- idempotent — war es schon raus, passiert hier nichts mehr.
		sendResult(player, token)

		-- Nur aufraeumen wenn diese Wiedergabe noch die aktuelle ist —
		-- sonst wuerde man einem bereits gestarteten neuen Lauf die Figur
		-- unter den Fuessen wegziehen.
		if _runToken[player] == token then
			restoreHome(player)
			clearFighters(player)
			MapService.setPitTowerLevel(player, 0)
			MapService.clearPitBanner(player)
			refreshState(player)
			ActivityLock.release(player, LOCK_HOLDER)
			if _active[player] and _active[player].token == token then
				_active[player] = nil
			end
		end
	end)
end

-- Laeuft fuer diesen Spieler gerade eine Wiedergabe (Hinlauf, Stages,
-- Nachlauf oder Ruecklauf)? CombatService fragt das VOR einem neuen
-- RequestStartCombat ab: der Cooldown auf diesem Remote (1s,
-- NetworkConfig) ist kuerzer als eine volle Wiedergabe — ohne diese Sperre
-- koennte ein zweiter Lauf mitten in den ersten hineinstarten und ihm die
-- Figur unter den Fuessen wegziehen.
--
-- _home ist dafuer das richtige Signal: es wird exakt fuer die Dauer einer
-- Wiedergabe gesetzt (startPlayback) und von restoreHome() wieder geleert,
-- egal ob sie normal zu Ende lief oder abgebrochen wurde.
-- HBB Paket 6: alle laufenden Laeufe fuer das Live-Kampf-Board (nur lesen).
function PitArenaService.liveRuns(): { { name: string, towerId: string?, stage: number?, phase: string } }
	local list = {}
	for player, active in _active do
		table.insert(list, {
			name    = player.DisplayName,
			towerId = active.run.towerId,
			stage   = active.stage,
			phase   = active.phase,
		})
	end
	return list
end

function PitArenaService.isRunning(player: Player): boolean
	return _home[player] ~= nil
end

-- Spielt einen fertig ausgerechneten Lauf ab. Kehrt sofort zurueck — die
-- eigentliche Wiedergabe laeuft nebenher.
--
-- Wirft NIE. Der Aufrufer (CombatService) steht mitten in der Abrechnung
-- eines Laufs: ein Fehler in dieser reinen Darstellung darf ihn nicht daran
-- hindern, die Daten zu speichern und den Client zu synchronisieren. Und er
-- darf vor allem keine Figur mit gesetztem "InArena" zuruecklassen — die
-- waere fuer den Rest der Sitzung von jeder Zustands-Aktualisierung
-- ausgenommen.
-- v15: `beats` = die Zuege je Stage (Index wie run.stages). Fehlen sie, wird
-- jede Stage als ein einziger Stoss gezeigt.
function PitArenaService.play(player: Player, run: Types.PitRunResult, settle: SettleFn?, beats: { { Types.FightBeat } }?)
	local ok, err = pcall(startPlayback, player, run, settle, beats)
	if ok then return end

	warn("[PitArenaService] Wiedergabe konnte nicht starten:", err)

	-- Aufraeumen was der abgebrochene Start schon angefasst haben koennte.
	-- Das ist nur deshalb gefahrlos, weil startPlayback den Token als ALLERSTES
	-- hochzaehlt: es gibt an dieser Stelle keine fremde Wiedergabe mehr, der
	-- man etwas wegraeumen koennte.
	--
	-- sendResult zuerst: schlug startPlayback ab, noch bevor es das Ergebnis
	-- verschicken konnte, bekaeme der Client sonst nie eins. _runToken[player]
	-- ist an dieser Stelle bereits der Token DIESES Versuchs — startPlayback
	-- setzt ihn als allerersten Schritt, bevor irgendetwas werfen kann.
	sendResult(player, _runToken[player] or 0)
	restoreHome(player)
	clearFighters(player)
	MapService.setPitTowerLevel(player, 0)
	MapService.clearPitBanner(player)
	refreshState(player)
	ActivityLock.release(player, LOCK_HOLDER)
	_active[player] = nil
end

-- v12: Spieler holt den Baerchi zurueck (Pet-Leiste). Auf dem Hinweg kehrt
-- er sofort um; im Kampf endet der Lauf nach der laufenden Stage. Auf dem
-- Rueckweg ist nichts mehr zu tun. true = Anfrage angenommen.
function PitArenaService.requestRecall(player: Player): boolean
	local active = _active[player]
	if not active or active.phase == "Returning" then
		return false
	end
	active.recall = true
	return true
end

-- v12: Phase des laufenden Laufs fuer die Pet-Leiste: "ToPit", "InPit",
-- "Returning" oder nil (kein Lauf). Dazu die laufende Stage (nur im Kampf).
function PitArenaService.getPhase(player: Player): (string?, number?)
	local active = _active[player]
	if not active or _home[player] == nil then
		return nil, nil
	end
	return active.phase, active.stage
end

-- v12: Ist dieser Baerchi gerade in einem noch nicht abgerechneten Lauf?
-- HoneyService lehnt Fuettern dann ab — die Abrechnung setzt die HP am Ende
-- auf den Wert nach der letzten Stage und wuerde eine Heilung dazwischen
-- ueberschreiben.
function PitArenaService.isFighting(player: Player, baerchiUid: string): boolean
	local active = _active[player]
	return active ~= nil and active.settled == nil and active.run.baerchiUid == baerchiUid
end

function PitArenaService.init()
	-- Verlaesst ein Spieler den Server mitten in der Wiedergabe, macht der
	-- Token-Vergleich die laufende Schleife ungueltig. Sein Plot wird ohnehin
	-- despawnt, aufraeumen muss hier nichts mehr.
	Players.PlayerRemoving:Connect(function(player)
		_runToken[player] = nil
		_home[player]     = nil
		_active[player]   = nil
	end)

	-- v12: geht der Spieler mitten im Lauf, wird VOR dem Speichern
	-- abgerechnet — so, als waere die gerade begonnene Stage zu Ende gespielt.
	PlayerService.onPlayerLeaving(function(player)
		local active = _active[player]
		if active then
			settleActive(active, active.entered, active.recall)
		end
	end)

	print("[PitArenaService] Initialisiert")
end

return PitArenaService
