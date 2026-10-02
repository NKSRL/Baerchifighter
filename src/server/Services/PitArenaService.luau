--!strict
-- PitArenaService.luau
-- ServerScriptService/Services/PitArenaService.luau
--
-- Einzige Zustaendigkeit:
--   - Einen bereits ausgerechneten PIT-Lauf in der Arena SICHTBAR abspielen
--
-- Dieser Service feuert auch `Remotes.CombatResultReceived` an den Client —
-- bewusst NICHT CombatService. Der Baerchi laeuft erst selbststaendig zum
-- Kampf-Spot; die Kampf-UI (CombatPanel) darf erst danach losgehen, sonst
-- liefe sie schon, waehrend er noch sichtbar unterwegs waere. sendResult()
-- ist der einzige Ort, der das Event abschickt, und idempotent — mehrere
-- Abbruch-/Erfolgspfade duerfen ihn gefahrlos alle aufrufen.
--
-- ============================================================
-- WAS DAS IST — UND WAS NICHT
-- ============================================================
-- Der Kampf ist zu dem Zeitpunkt, an dem dieser Service loslaeuft, komplett
-- entschieden: CombatService hat alle Stages simuliert, die Gummies sind
-- gutgeschrieben und die HP stehen schon auf dem Endwert. Dieser Service
-- aendert KEINE Spieldaten — er ist reine Darstellung.
--
-- Warum trotzdem auf dem SERVER und nicht im Client:
-- die Plattform ist gemeinsam, alle acht Spieler laufen auf derselben Wiese.
-- Ein Kampf, den nur der Besitzer sieht, waere in so einer Welt verschenkt —
-- serverseitig kann der Nachbar ueber die Bruecke kommen und zuschauen.
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

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local TweenService        = game:GetService("TweenService")

local MapConfig   = require(ReplicatedStorage.Config.MapConfig)
local BaerchiMesh = require(ReplicatedStorage.Modules.BaerchiMesh)
local Types       = require(ReplicatedStorage.Network.Types)
local Remotes     = require(ReplicatedStorage.Network.Remotes)

local PlayerService   = require(ServerScriptService.Services.PlayerService)
local MapService      = require(ServerScriptService.Services.MapService)
local FigureWalker    = require(ServerScriptService.Util.FigureWalker)
local FigurePlacement = require(ServerScriptService.Util.FigurePlacement)
local FigureFX        = require(ServerScriptService.Util.FigureFX)
local ActivityLock    = require(ServerScriptService.Util.ActivityLock)

-- Name unter dem PitArenaService das Bewegungs-Schloss haelt (siehe
-- ActivityLock) — verhindert dass BaerchiAutopilotService den Baerchi
-- waehrend eines Kampf-Laufs zum Honig-Teich abzieht.
local LOCK_HOLDER = "Kampf"

local PitArenaService = {}

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
local _pendingResult: { [Player]: { token: number, run: Types.PitRunResult } } = {}

-- Wo die gerade kaempfende Figur auf dem Plot hingehoert. homeFoot ist der
-- Fusspunkt VOR dem Loslaufen (fuer den Weg zurueck), pivot der exakte
-- Ausgangszustand (fuer den abschliessenden Snap in restoreHome).
type Home = { model: Model, pivot: CFrame, homeFoot: Vector3 }
local _home: { [Player]: Home } = {}

--------------------------------------------------------------------------------
-- Hilfen
--------------------------------------------------------------------------------

-- Das Aufstellen der Kaempfer (Fusspunkt exakt auf dem Boden, Blick zum
-- Gegner) macht FigurePlacement.placeLookingAt — dieselbe Funktion, die auch
-- FigureWalker jeden Frame benutzt. Sie stand hier frueher als eigene Kopie
-- (`placeModel`) und ist mit Teil C in das gemeinsame Util gewandert.
--
-- Wichtig fuer das Verstaendnis der Arena: die Ausrichtung wird dort ABSOLUT
-- gesetzt. Genau das ist hier richtig — die Figur vom Plot traegt bereits die
-- Plot-Drehung, und die soll in der Arena durch "schau den Gegner an"
-- ERSETZT werden, nicht mit ihr verrechnet.

-- HP-Balken ueber einer Figur. Gibt die Fuell-Flaeche zurueck, damit der
-- Aufrufer sie animieren kann.
local function attachHealthBar(model: Model, fillColor: Color3): Frame?
	local anchor = (model:FindFirstChild("head", true) :: BasePart?) or model.PrimaryPart
	if not anchor then return nil end

	local billboard = Instance.new("BillboardGui")
	billboard.Name        = "FightBar"
	billboard.Size        = UDim2.fromScale(MapConfig.FIGHT_BAR_WIDTH, MapConfig.FIGHT_BAR_HEIGHT)
	billboard.StudsOffset = Vector3.new(0, BaerchiMesh.getHeight(model) * 0.55 + 2.2, 0)
	billboard.AlwaysOnTop = true
	-- Ohne Reichweiten-Grenze waeren die Balken ueber ALLEN acht Arenen quer
	-- ueber die Karte zu sehen — und wegen AlwaysOnTop auch noch durch die
	-- Landschaft hindurch.
	billboard.MaxDistance = MapConfig.FIGHT_BAR_DISTANCE
	billboard.Adornee     = anchor
	billboard.Parent      = anchor

	local back = Instance.new("Frame")
	back.Name              = "Back"
	back.Size              = UDim2.fromScale(1, 1)
	back.BackgroundColor3  = MapConfig.FIGHT_BAR_BACK_COLOR
	back.BorderSizePixel   = 0
	back.Parent            = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.4, 0)
	corner.Parent       = back

	local fill = Instance.new("Frame")
	fill.Name              = "Fill"
	fill.Size              = UDim2.fromScale(1, 1)
	fill.BackgroundColor3  = fillColor
	fill.BorderSizePixel   = 0
	fill.Parent            = back

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0.4, 0)
	fillCorner.Parent       = fill

	return fill
end

local function removeHealthBar(model: Model)
	local bar = model:FindFirstChild("FightBar", true)
	if bar then
		bar:Destroy()
	end
end

local function tweenFill(fill: Frame?, ratio: number, seconds: number)
	if not fill then return end

	local goal = UDim2.fromScale(math.clamp(ratio, 0, 1), 1)
	local info = TweenInfo.new(math.max(seconds, 0.05), Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	TweenService:Create(fill, info, { Size = goal }):Play()
end

-- Bringt eine noch in der Arena stehende Figur an ihren Platz auf dem Plot
-- zurueck und raeumt ihren Kampf-Balken weg. Idempotent: zweimal aufrufen
-- schadet nicht.
local function restoreHome(player: Player)
	local home = _home[player]
	if not home then return end

	_home[player] = nil

	local model = home.model
	if model.Parent ~= nil then
		removeHealthBar(model)
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
local function showStage(player: Player, stage: Types.PitStageResult, cleared: number)
	MapService.setPitBanner(
		player,
		string.format("Stage %d", stage.stage),
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
local function sendResult(player: Player, token: number)
	local pending = _pendingResult[player]
	if not pending or pending.token ~= token then return end
	_pendingResult[player] = nil
	Remotes.CombatResultReceived:FireClient(player, pending.run)
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
local function stillValid(player: Player, token: number, figure: Model, fighters: Folder): boolean
	if _runToken[player] ~= token then return false end
	if player.Parent == nil then return false end
	if figure.Parent == nil then return false end
	if fighters.Parent == nil then return false end
	return true
end

local function startPlayback(player: Player, run: Types.PitRunResult)
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
	_pendingResult[player] = { token = token, run = run }

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
		sendResult(player, token)
		ActivityLock.release(player, LOCK_HOLDER)
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

		local ok, err = pcall(function()
			-- Erst hinlaufen: der Kampf soll sichtbar ERST beginnen, wenn der
			-- Baerchi an der Plattform angekommen ist, nicht durch einen
			-- Teleport. FigureWalker haelt den Fusspunkt waehrenddessen exakt
			-- auf Plot-/Bruecken-Hoehe.
			FigureWalker.walk(figure, homeFoot, selfPos, {
				speed       = MapConfig.WALK_SPEED,
				isCancelled = function() return not stillValid(player, token, figure, fighters) end,
			})
			if not stillValid(player, token, figure, fighters) then
				sendResult(player, token)
				return
			end

			-- Exakte Ausrichtung zum Gegner: der Lauf endet in Laufrichtung,
			-- gekaempft wird aber gegenueber.
			FigurePlacement.placeLookingAt(figure, selfPos, enemyPos)

			-- Ab hier steht der Baerchi am Kampf-Spot und atmet dort — auch
			-- zwischen den Stages und waehrend der Nachlauf-Pause, in der er
			-- sonst reglos herumstuende. Die Ausfallschritte melden ihn dafuer
			-- selbst kurz ab und danach wieder an (FigureFX.attackLunge).
			FigureFX.idleBob(figure, {
				height = MapConfig.IDLE_BOB_HEIGHT,
				rate   = MapConfig.IDLE_BOB_RATE,
			})

			selfFill = attachHealthBar(figure, MapConfig.FIGHT_BAR_SELF_COLOR)
			tweenFill(selfFill, run.hpBefore / maxHp, 0.01)

			-- Erst JETZT bekommt der Client sein Ergebnis: der Baerchi steht
			-- sichtbar am Kampf-Spot, die Kampf-UI darf jetzt erst losgehen.
			sendResult(player, token)

			local stageTime = math.clamp(
				MapConfig.FIGHT_TOTAL_SECONDS / #run.stages,
				MapConfig.FIGHT_MIN_STAGE_SECONDS,
				MapConfig.FIGHT_MAX_STAGE_SECONDS
			)

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

			for _, stage in run.stages do
				if not stillValid(player, token, figure, fighters) then return end

				-- Etage dieser Stage: die erste Stage kaempft noch auf der
				-- normalen Kampfflaeche (Etage 0) — sichtbar identisch mit dem
				-- Boden, den man von der Bruecke kennt. Jede weitere Stage
				-- bekommt eine neue Turmetage obendrauf (siehe MapConfig,
				-- Abschnitt "PIT-TURM").
				local towerLevel = math.max(0, stage.stage - 1)
				MapService.setPitTowerLevel(player, towerLevel)

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

				showStage(player, stage, cleared)

				if previousEnemy and previousEnemy.Parent then
					previousEnemy:Destroy()
				end
				previousEnemy = nil

				local enemy = BaerchiMesh.buildEnemy(stageEnemyPos, MapConfig.FIGHT_ENEMY_COLOR)
				local enemyFill: Frame? = nil

				if enemy then
					FigurePlacement.placeLookingAt(enemy, stageEnemyPos, stageSelfPos)
					enemy.Parent = fighters
					enemyFill = attachHealthBar(enemy, MapConfig.FIGHT_BAR_ENEMY_COLOR)
					previousEnemy = enemy

					-- Auch der Gegner soll nicht wie ein Standbild dastehen,
					-- solange er noch lebt.
					FigureFX.idleBob(enemy, {
						height = MapConfig.IDLE_BOB_HEIGHT,
						rate   = MapConfig.IDLE_BOB_RATE,
					})
				end

				-- Kurz stehen bleiben, damit man den neuen Gegner sieht,
				-- bevor die Balken laufen.
				task.wait(stageTime * 0.35)
				if not stillValid(player, token, figure, fighters) then return end

				-- WER zuschlaegt und WER getroffen wird, entscheidet sich hier —
				-- WIE ein Schlag oder ein Treffer aussieht, steht in FigureFX.
				-- Fehlt das Gegner-Mesh, faellt nur die Bewegung aus, die Stage
				-- laeuft normal weiter.
				local attacker: Model?  = if stage.won then figure else enemy
				local target:   Model?  = if stage.won then enemy else figure
				local towards:  Vector3 = if stage.won then stageEnemyPos else stageSelfPos

				if target then
					FigureFX.hitFlash(
						target,
						MapConfig.FIGHT_HIT_FLASH_COLOR,
						MapConfig.FIGHT_HIT_FLASH_SECONDS
					)
				end

				-- Der Gegner faellt bei einem Sieg auf 0; bei einer Niederlage
				-- bleibt ein Rest stehen. Der Server schickt keine Gegner-HP
				-- mit — das ist die ehrliche Darstellung von "geschafft" bzw.
				-- "nicht geschafft".
				--
				-- Die Balken laufen waehrend des Ausfallschritts: tweenFill
				-- kehrt sofort zurueck, die eigentliche Bewegung darunter
				-- blockiert.
				tweenFill(enemyFill, if stage.won then 0 else 0.35, stageTime * 0.5)
				tweenFill(selfFill, stage.hpAfter / maxHp, stageTime * 0.5)

				if stage.won then
					cleared += 1
				end

				if attacker then
					-- Die Dauer des Ausfallschritts geht von der Stage-Pause ab,
					-- damit die Wiedergabe insgesamt nicht laenger wird als
					-- FIGHT_TOTAL_SECONDS. Zusaetzlich auf die halbe Stage
					-- geklemmt: bei vielen Stages ist eine Stage nur
					-- FIGHT_MIN_STAGE_SECONDS lang, und zwei ueberlappende
					-- Ausfallschritte auf derselben Figur wuerden sich
					-- gegenseitig ueberschreiben.
					local lungeSeconds = math.min(MapConfig.FIGHT_LUNGE_SECONDS, stageTime * 0.5)

					FigureFX.attackLunge(attacker, towards, MapConfig.FIGHT_LUNGE_DISTANCE, lungeSeconds)
					task.wait(math.max(0, stageTime * 0.65 - lungeSeconds))
				else
					task.wait(stageTime * 0.65)
				end
			end

			-- Der letzte Gegner steht waehrend der Nachlauf-Pause noch da;
			-- weggeraeumt wird er unten von clearFighters.
			showSummary(player, run)

			-- Wer die LETZTE Stage verloren hat, kippt sichtbar um, statt
			-- einfach zu verschwinden bzw. unveraendert stehenzubleiben.
			--
			-- Der eigene Baerchi kippt nur, wenn er den Lauf wirklich
			-- erschoepft beendet (hpAfter <= 0). Sonst laeuft er gleich darauf
			-- selbst nach Hause — eine umgekippte Figur, die losmarschiert,
			-- waere schlechter als gar keine Animation. Zurueckgesetzt wird die
			-- Neigung ohnehin von restoreHome.
			local lastStage = run.stages[#run.stages]
			local loser: Model? = nil

			if lastStage and lastStage.won then
				loser = previousEnemy
			elseif run.hpAfter <= 0 then
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
			if run.hpAfter > 0 then
				-- Vor dem eigenen PivotTo abmelden: sonst zoegen Idle-Loop und
				-- Lauf-Animation im selben Frame an derselben Figur. Wieder
				-- angemeldet wird sie am Ende von restoreHome, auf ihrem Platz.
				FigureFX.stopIdle(figure)

				FigureWalker.walk(figure, finalSelfPos, homeFoot, {
					speed       = MapConfig.WALK_SPEED,
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
function PitArenaService.play(player: Player, run: Types.PitRunResult)
	local ok, err = pcall(startPlayback, player, run)
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
end

function PitArenaService.init()
	-- Verlaesst ein Spieler den Server mitten in der Wiedergabe, macht der
	-- Token-Vergleich die laufende Schleife ungueltig. Sein Plot wird ohnehin
	-- despawnt, aufraeumen muss hier nichts mehr.
	Players.PlayerRemoving:Connect(function(player)
		_runToken[player]      = nil
		_home[player]          = nil
		_pendingResult[player] = nil
	end)

	print("[PitArenaService] Initialisiert")
end

return PitArenaService
