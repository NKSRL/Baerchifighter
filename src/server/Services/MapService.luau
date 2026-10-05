--!strict
-- MapService.luau
-- ServerScriptService/Services/MapService.luau
--
-- Einzige Zustaendigkeit:
--   - Die einzige Schnittstelle zur gebauten Welt: Welt beim Start bauen
--     lassen, Spieler-Plots vergeben, spawnen, neu aufbauen und despawnen,
--     und die sichtbaren Teile aktuell halten (Schilder, Figur, Teich, Eier,
--     Lauf-Turm, Tower-Turm, Event-Pit)
--
-- Das eigentliche BAUEN steht in den Modulen unter Util/MapBuild (MapParts,
-- WorldBuilder, PlotBuilder, PondBuilder, ArenaBuilder, FigureBuilder,
-- LaidEggBuilder). Dieser Service haelt den Zustand (welcher Spieler welchen
-- Slot und welches Plot-Model hat) und entscheidet, WANN gebaut wird. Andere
-- Services sprechen nur mit MapService, nie mit den Buildern.
--
-- Baut physische Roblox-Parts aus IslandData.
-- Kennt keine Spielerdaten ausser IslandData (und den Namen fuer das Schild).
--
-- Alle Masse, Farben und Offsets kommen aus MapConfig. Wie das plot-lokale
-- Koordinatensystem funktioniert (lokales -Z = Richtung Mitte, +Z = nach
-- aussen), steht im Kopf von MapConfig.
--
-- ZWEI ARTEN VON AKTUALISIERUNG — bewusst getrennt:
--   * NEU BAUEN (updateBaerchis, updateBuildingLooks, updateTowerShowcase):
--     teuer, nur wenn sich die Struktur aendert (ein Baerchi kommt dazu, faellt
--     weg oder steigt im Level; ein Gebaeude wechselt den Look; der Tower-Turm
--     bekommt einen neuen Look oder Rekord).
--   * IN-PLACE (updateBaerchiStates, updateBuildingSigns): billig, aendert nur
--     Beschriftung und Transparenz an bereits stehenden Teilen. Dafuer gibt es
--     die Trennung: HP und Honig aendern sich staendig, und dafuer jedes Mal
--     25 Mesh-Figuren neu zu bauen waere Verschwendung.
--   PlotDisplayService entscheidet welche der beiden noetig ist.
--
-- NEUAUFBAU WAEHREND EINER BEWEGUNG — die eine Sperre in dieser Datei:
-- updateBaerchis zerstoert die Figur und baut sie neu. Laeuft sie in dem
-- Moment gerade (Kampf-Lauf oder Weg zum Honig-Teich), verschwaende sie mitten
-- im Schritt. Die Pruefung dagegen steht EINMAL hier drin statt an jeder
-- Aufrufstelle — und der uebersprungene Neuaufbau wird nachgeholt, sobald das
-- Schloss frei ist (siehe scheduleRebuildWhenFree weiter unten). Ohne das
-- Nachholen bliebe die Beschriftung dauerhaft veraltet, weil der Aufrufer
-- (PlotDisplayService) den neuen Stand direkt danach als "dargestellt" merkt.

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local MapConfig = require(ReplicatedStorage.Config.MapConfig)
local CombConfig = require(ReplicatedStorage.Config.CombConfig)
local BuildingBehavior = require(ReplicatedStorage.Config.BuildingBehavior)
local Types     = require(ReplicatedStorage.Network.Types)

local ActivityLock = require(ServerScriptService.Util.ActivityLock)
local FigureFX     = require(ServerScriptService.Util.FigureFX)

local MapBuild       = ServerScriptService.Util.MapBuild
local MapParts       = require(MapBuild.MapParts)
local WorldBuilder   = require(MapBuild.WorldBuilder)
local PlotBuilder    = require(MapBuild.PlotBuilder)
local PondBuilder    = require(MapBuild.PondBuilder)
local ArenaBuilder   = require(MapBuild.ArenaBuilder)
local FigureBuilder  = require(MapBuild.FigureBuilder)
local LaidEggBuilder = require(MapBuild.LaidEggBuilder)
local RecyclerBuilder = require(MapBuild.RecyclerBuilder)

--------------------------------------------------------------------------------
-- Interner Zustand
--------------------------------------------------------------------------------

-- Welcher Slot gehoert welchem Spieler
local _playerSlot: { [Player]: number } = {}

-- Alle gespawnten Plot-Models, key = Player
local _plotModels: { [Player]: Model } = {}

-- Verfuegbare Slots (1 .. PLOT_COUNT), wird in init() gefuellt
local _freeSlots: { number } = {}

-- Fuer welche Spieler gerade ein Waechter darauf wartet, den wegen
-- ActivityLock uebersprungenen Figuren-Neuaufbau nachzuholen. Verhindert, dass
-- mehrere Datenaenderungen waehrend derselben Bewegung mehrere Warte-Schleifen
-- starten — eine reicht, sie liest am Ende ohnehin frische Daten.
local _pendingRebuild: { [Player]: boolean } = {}

-- Woher der nachgeholte Neuaufbau seine FRISCHEN IslandData bekommt.
--
-- Absichtlich als eingehaengte Funktion statt eines require(PlayerService):
-- PlayerService requiret bereits MapService, der umgekehrte Weg waere ein
-- Ringschluss. Ausserdem bleibt damit die Regel
-- im Kopf dieser Datei gueltig — MapService kennt weiterhin keine
-- Spielerdaten ausser IslandData. Eingehaengt wird sie von
-- PlotDisplayService.init(); ohne sie faellt nur das Nachholen aus.
local _islandDataProvider: ((Player) -> Types.IslandData?)? = nil

-- v15: zuletzt gesetzter Tower-Turm und Tower-Symbol am Plot-Schild pro
-- Spieler. MapService kennt die Tower-Daten nicht (sie liegen ausserhalb von
-- IslandData) — PlotDisplayService setzt beides; gemerkt wird es hier, damit
-- ein Neuaufbau des Plots (Rebirth) Turm und Symbol sofort wieder mitbaut.
local _showcase: { [Player]: ArenaBuilder.ShowcaseView } = {}
type Badge = { text: string, color: Color3 }
local _badge: { [Player]: Badge } = {}

--------------------------------------------------------------------------------
-- Plot-Inhalt
--------------------------------------------------------------------------------

-- Baut den kompletten Inhalt eines Plots (Gebaeude + Bruecke + PIT + Baerchis).
local function buildPlotContents(plotModel: Model, slot: number, islandData: Types.IslandData, owner: Player)
	local pool = PondBuilder.honeyPool(islandData)
	for _, building in islandData.buildings do
		PlotBuilder.buildBuilding(plotModel, slot, building, pool)
	end

	ArenaBuilder.buildBridge(plotModel, slot)
	ArenaBuilder.buildPit(plotModel, slot)
	PondBuilder.buildPond(plotModel, slot, islandData)
	RecyclerBuilder.build(plotModel, slot, islandData.recycler)
	FigureBuilder.renderBaerchis(plotModel, slot, islandData)
	LaidEggBuilder.renderLaidEggs(plotModel, slot, islandData, owner)

	-- v15: Tower-Turm und Symbol, falls schon bekannt (nach einem Rebirth).
	local view = _showcase[owner]
	if view then
		ArenaBuilder.buildShowcase(plotModel, slot, view)
	end
	local badge = _badge[owner]
	if badge then
		PlotBuilder.writeOwnerBadge(plotModel, badge.text, badge.color)
	end
end

--------------------------------------------------------------------------------
-- Oeffentliche API
--------------------------------------------------------------------------------

local MapService = {}

local function claimSlot(): number?
	if #_freeSlots == 0 then return nil end
	return table.remove(_freeSlots, 1)
end

local function releaseSlot(slot: number)
	table.insert(_freeSlots, slot)
	table.sort(_freeSlots)
end

function MapService.spawnIsland(player: Player, islandData: Types.IslandData)
	-- Alten Slot freigeben falls vorhanden (sollte nicht passieren, aber sicher)
	if _playerSlot[player] then
		MapService.despawnIsland(player)
	end

	local slot = claimSlot()
	if not slot then
		warn("[MapService] Kein freier Plot fuer Spieler:", player.Name)
		return
	end

	_playerSlot[player] = slot

	local plotModel = PlotBuilder.buildPlotBase(slot, player)
	_plotModels[player] = plotModel

	buildPlotContents(plotModel, slot, islandData, player)

	print("[MapService] Plot gespawnt fuer:", player.Name, "| Slot:", slot)
end

-- Baut den Plot eines Spielers komplett neu — behaelt aber seinen Slot,
-- damit er nach einem Rebirth an derselben Stelle der Map steht.
function MapService.rebuildIsland(player: Player, islandData: Types.IslandData)
	local slot = _playerSlot[player]
	if not slot then
		-- Noch kein Plot (z.B. Server voll) → normaler Spawn-Versuch
		MapService.spawnIsland(player, islandData)
		return
	end

	local oldModel = _plotModels[player]
	if oldModel then
		oldModel:Destroy()
	end

	local plotModel = PlotBuilder.buildPlotBase(slot, player)
	_plotModels[player] = plotModel

	buildPlotContents(plotModel, slot, islandData, player)

	print("[MapService] Plot neu aufgebaut fuer:", player.Name, "| Slot:", slot)
end

function MapService.despawnIsland(player: Player)
	-- Ein noch wartender Nachhol-Waechter hat hier nichts mehr zu tun. Er
	-- merkt das zwar selbst beim naechsten Durchlauf (kein Plot mehr), aber so
	-- bleibt kein Eintrag fuer einen laengst gegangenen Spieler stehen.
	_pendingRebuild[player] = nil
	_showcase[player] = nil
	_badge[player] = nil

	local model = _plotModels[player]
	if model then
		model:Destroy()
		_plotModels[player] = nil
	end

	local slot = _playerSlot[player]
	if slot then
		releaseSlot(slot)
		_playerSlot[player] = nil
	end
end

-- (v15: updatePitLevel ist entfallen — es gibt kein PIT-Level mehr. Der Turm
-- auf der Arena-Insel zeigt jetzt den Tower-Rekord, siehe updateTowerShowcase.)

-- v15: den Tower-Turm auf der Arena-Insel (neu) bauen. Aufrufer ist
-- PlotDisplayService, und nur wenn sich Look oder Rekord geaendert haben
-- (Signatur). `show` = der LOOK hat gewechselt: kurze Aufwertungs-Show (ein
-- Partikel-Stoss an der Spitze, < 2 s).
function MapService.updateTowerShowcase(player: Player, view: ArenaBuilder.ShowcaseView, show: boolean?)
	_showcase[player] = view

	local model = _plotModels[player]
	local slot  = _playerSlot[player]
	if not model or not slot then return end

	local built = ArenaBuilder.buildShowcase(model, slot, view)
	if show then
		local foot = ArenaBuilder.showcaseFoot(slot)
		local height = MapConfig.TOWER_SHOWCASE.plinthHeight + view.floors * MapConfig.TOWER_SHOWCASE.floorHeight
		FigureFX.burstAt(foot + Vector3.new(0, height + 2, 0), view.color, built, 60)
	end
end

-- v15: Tower-Symbol unter dem Namen auf dem Plot-Schild ("◆ III · 42").
function MapService.setOwnerBadge(player: Player, text: string, color: Color3)
	_badge[player] = { text = text, color = color }
	local model = _plotModels[player]
	if model then
		PlotBuilder.writeOwnerBadge(model, text, color)
	end
end

-- Farbe der kurzen Aufwertungs-Show beim Look-Wechsel (v15).
local LOOK_UPGRADE_COLOR = Color3.fromRGB(255, 220, 110)
local LOOK_UPGRADE_SPARKS = 40

-- v15: baut ein Gebaeude (oder den Recycler) NUR neu, wenn sich sein Look
-- geaendert hat (Attribut "Look" am Koerper gegen BuildingBehavior.getLook).
-- PlotDisplayService ruft das, wenn die Look-Signatur wechselt; Level-Aenderungen
-- innerhalb eines Looks laufen ueber das billige updateBuildingSigns.
-- `show` = kurze Aufwertungs-Show (ein Partikel-Stoss, < 2 s).
function MapService.updateBuildingLooks(player: Player, islandData: Types.IslandData, show: boolean?)
	local model = _plotModels[player]
	local slot  = _playerSlot[player]
	if not model or not slot then return end

	local pool = PondBuilder.honeyPool(islandData)
	for _, building in islandData.buildings do
		local part = model:FindFirstChild(building.id)
		local look = BuildingBehavior.getLook(building.level)
		if part and part:IsA("BasePart") and part:GetAttribute("Look") ~= look then
			local position = part.Position
			part:Destroy()
			PlotBuilder.buildBuilding(model, slot, building, pool)
			if show then
				FigureFX.burstAt(position, LOOK_UPGRADE_COLOR, model, LOOK_UPGRADE_SPARKS)
			end
		end
	end

	local body = model:FindFirstChild(CombConfig.RECYCLER_NAME)
	local recyclerLook = BuildingBehavior.getLook(islandData.recycler.level)
	if body and body:IsA("BasePart") and body:GetAttribute("Look") ~= recyclerLook then
		local position = body.Position
		body:Destroy()
		RecyclerBuilder.build(model, slot, islandData.recycler)
		if show then
			FigureFX.burstAt(position, LOOK_UPGRADE_COLOR, model, LOOK_UPGRADE_SPARKS)
		end
	end
end

-- Haengt die Quelle fuer frische IslandData ein (siehe _islandDataProvider).
-- Wird einmal beim Start von PlotDisplayService aufgerufen.
function MapService.setIslandDataProvider(provider: (Player) -> Types.IslandData?)
	_islandDataProvider = provider
end

-- Wartet, bis die Figur des Spielers nicht mehr in einer Bewegung steckt, und
-- baut sie dann mit FRISCH gelesenen Daten neu.
--
-- Frisch gelesen ist der entscheidende Teil: waehrend der Bewegung koennen
-- weitere Aenderungen anfallen (mehrere Level-Ups waehrend eines Ess-Zyklus),
-- und nach einem Rebirth ist die alte IslandData-Tabelle gar nicht mehr die
-- des Spielers — sie einfach aufzuheben und spaeter nochmal zu rendern wuerde
-- einen veralteten Stand in die Welt stellen.
local function scheduleRebuildWhenFree(player: Player)
	if _pendingRebuild[player] then return end
	_pendingRebuild[player] = true

	task.spawn(function()
		local interval = MapConfig.FIGURE_REBUILD_RETRY_SECONDS
		local waited   = 0

		while waited < MapConfig.FIGURE_REBUILD_TIMEOUT_SECONDS do
			task.wait(interval)
			waited += interval

			-- Spieler weg oder Plot abgeraeumt: es gibt nichts mehr nachzuholen.
			if player.Parent == nil or _plotModels[player] == nil then
				break
			end

			if ActivityLock.isFree(player) then
				local provider = _islandDataProvider
				local island   = if provider then provider(player) else nil

				-- Vor dem erneuten Aufruf freigeben: updateBaerchis darf, falls
				-- inzwischen doch wieder eine Bewegung laeuft, sauber einen
				-- neuen Waechter starten.
				_pendingRebuild[player] = nil

				if island then
					MapService.updateBaerchis(player, island)
				end
				return
			end
		end

		_pendingRebuild[player] = nil
	end)
end

-- Baut die sichtbaren Baerchis eines Spielers NEU. Teuer — nur aufrufen wenn
-- sich der Bestand oder ein Level geaendert hat (siehe PlotDisplayService).
--
-- Steckt die Figur gerade in einer Bewegung, wird der Neuaufbau verschoben
-- statt sie mitten im Schritt zu ersetzen (Begruendung im Kopf der Datei).
function MapService.updateBaerchis(player: Player, islandData: Types.IslandData)
	local model = _plotModels[player]
	if not model then return end

	local slot = _playerSlot[player]
	if not slot then return end

	if not ActivityLock.isFree(player) then
		scheduleRebuildWhenFree(player)
		return
	end

	FigureBuilder.renderBaerchis(model, slot, islandData)
	LaidEggBuilder.renderLaidEggs(model, slot, islandData, player)
end

-- Baut die herumliegenden Eier eines Spielers neu.
--
-- Anders als updateBaerchis KEINE ActivityLock-Pruefung: Eier bewegen sich
-- nicht und gehoeren niemandem, der sie gerade animiert. Sie duerfen deshalb
-- auch mitten in einem Kampf oder Weg zum Teich erscheinen und verschwinden —
-- genau das muss sogar sein, weil der Baerchi WAEHREND er laeuft legt.
function MapService.updateLaidEggs(player: Player, islandData: Types.IslandData)
	local model = _plotModels[player]
	if not model then return end

	local slot = _playerSlot[player]
	if not slot then return end

	LaidEggBuilder.renderLaidEggs(model, slot, islandData, player)
end

-- Haengt den Ei-Einsammel-Handler ein: er laeuft, wenn der BESITZER eines
-- Plots sein eigenes gelegtes Ei mit der Spielfigur beruehrt. Wird einmal
-- beim Start von EggLayService aufgerufen (Pull-Callback statt require:
-- EggLayService requiret bereits MapService, der umgekehrte Weg waere ein
-- Ringschluss). Ohne Handler sammelt Beruehren einfach nichts ein.
function MapService.setEggCollectHandler(handler: (Player, string) -> ())
	LaidEggBuilder.setCollectHandler(handler)
end

-- Rechnet eine Weltposition in das Koordinatensystem des Plots um.
--
-- Gelegte Eier werden PLOT-RELATIV gespeichert, nicht in Weltkoordinaten. Der
-- Grund: welchen der acht Plots ein Spieler bekommt, entscheidet sich bei
-- jedem Join neu (siehe _freeSlots). Absolute Positionen wuerden nach einem
-- Rejoin auf einem anderen Plot liegen — im schlimmsten Fall auf dem eines
-- Nachbarn.
function MapService.worldToPlot(player: Player, worldPosition: Vector3): Vector3?
	local slot = _playerSlot[player]
	if not slot then return nil end

	local plotCFrame = MapParts.plotCFrame(slot)
	if not plotCFrame then return nil end

	return plotCFrame:PointToObjectSpace(worldPosition)
end

-- Aktualisiert nur Beschriftung und Erschoepfung der bereits stehenden
-- Figuren. Billig — das ist der Weg fuer HP-Aenderungen.
function MapService.updateBaerchiStates(player: Player, islandData: Types.IslandData)
	local model = _plotModels[player]
	if not model then return end

	local folder = model:FindFirstChild("Baerchis")
	if not folder then return end

	for _, baerchi in islandData.baerchis do
		local figure = folder:FindFirstChild("Baerchi_" .. baerchi.uid)
		if figure and figure:IsA("Model") then
			FigureBuilder.writeBaerchiState(figure, baerchi, FigureBuilder.maxHpOf(baerchi))
		end
	end
end

-- Aktualisiert das Level-Attribut einer Gebaeude-Part (fuer Client-UI).
-- Wird nach einem Gebaeude-Upgrade aufgerufen; baut nichts neu.
function MapService.updateBuildingLevel(player: Player, buildingId: Types.BuildingId, level: number)
	local model = _plotModels[player]
	if not model then return end

	local part = model:FindFirstChild(buildingId)
	if part then
		part:SetAttribute("BuildingLevel", level)
	end
end

-- Wohin der Baerchi zum Fressen laeuft.
--
-- Das ist der Standplatz VOR dem Becken (auf den Bohlen), nicht mehr die
-- Beckenmitte. Bis der Teich ein richtiges Becken wurde, war beides dasselbe
-- — und der Baerchi stand mitten im Teich. Jetzt stuende er bis zum Bauch im
-- Beckenboden.
function MapService.getPondPosition(player: Player): Vector3?
	local slot = _playerSlot[player]
	if not slot then return nil end
	return PondBuilder.pondStand(slot).Position
end

-- Fuellstand des Teichs nachziehen. Billig — das ist der Weg fuer
-- Honig-Aenderungen (siehe MapService.updateBuildingSigns, das das mit
-- aufruft, weil beides an denselben Werten haengt).
function MapService.updatePondFill(player: Player, islandData: Types.IslandData)
	local model = _plotModels[player]
	if not model then return end

	local slot = _playerSlot[player]
	if not slot then return end

	local pond = model:FindFirstChild("Pond")
	if not pond then return end

	local fill = pond:FindFirstChild("Fuellung")
	if fill and fill:IsA("BasePart") then
		PondBuilder.writePondFill(fill, PondBuilder.pondGround(slot), PondBuilder.pondFillRatio(islandData))
	end
end

-- Schreibt Level und Honig-Lagerstand auf die Gebaeude-Schilder.
-- Billig — das ist der Weg fuer Honig-Aenderungen.
function MapService.updateBuildingSigns(player: Player, islandData: Types.IslandData)
	local model = _plotModels[player]
	if not model then return end

	local pool = PondBuilder.honeyPool(islandData)

	for _, building in islandData.buildings do
		local part = model:FindFirstChild(building.id)
		if part and part:IsA("BasePart") then
			part:SetAttribute("BuildingLevel", building.level)
			PlotBuilder.writeBuildingState(part, building, pool)
		end
	end

	-- Haengt an denselben Werten wie die Gebaeude-Schilder — deshalb hier
	-- gleich mit erledigt statt eines eigenen Aufrufers in PlotDisplayService.
	MapService.updatePondFill(player, islandData)
end

-- Schreibt Level, Warteschlange und Lampe des Waben-Recyclers neu.
-- Billig — der Weg fuer jede Aenderung der Warteschlange.
function MapService.updateRecycler(player: Player, islandData: Types.IslandData)
	local model = _plotModels[player]
	if not model then return end

	local body = model:FindFirstChild(CombConfig.RECYCLER_NAME)
	if body and body:IsA("BasePart") then
		RecyclerBuilder.writeState(body, islandData.recycler)
	end
end

-- Die Anzeigetafel ueber der Arena. Bewusst ueber den exakten Pfad gesucht und
-- nicht rekursiv: unter dem Plot haengen bis zu 25 importierte Mesh-Figuren,
-- deren Teilenamen aus einer .glb stammen und die wir nicht kontrollieren.
-- Eine rekursive Suche wuerde bei einem gleichnamigen Teil das Falsche finden
-- — und muesste bei jeder der bis zu 60 Stages den ganzen Baum durchlaufen.
local function findPitBanner(player: Player): BillboardGui?
	local model = _plotModels[player]
	if not model then return nil end

	local platform = model:FindFirstChild("PitPlatform")
	if not platform then return nil end

	local anchor = platform:FindFirstChild("PitBannerAnchor")
	if not anchor then return nil end

	local banner = anchor:FindFirstChild("Banner")
	return if banner and banner:IsA("BillboardGui") then banner else nil
end

-- Die Anzeigetafel ueber der Arena beschriften und einblenden.
-- Aufgerufen von PitArenaService waehrend einer Wiedergabe; MapService kennt
-- den Kampfverlauf nicht und entscheidet deshalb nichts ueber den Inhalt.
function MapService.setPitBanner(player: Player, title: string, subtitle: string, color: Color3)
	local banner = findPitBanner(player)
	if not banner then return end

	local titleLabel = banner:FindFirstChild("Title")
	if titleLabel and titleLabel:IsA("TextLabel") then
		titleLabel.Text       = title
		titleLabel.TextColor3 = color
	end

	local subLabel = banner:FindFirstChild("Sub")
	if subLabel and subLabel:IsA("TextLabel") then
		subLabel.Text = subtitle
	end

	banner.Enabled = true
end

-- Tafel wieder ausblenden. Idempotent — ein zweiter Aufruf schadet nicht.
function MapService.clearPitBanner(player: Player)
	local banner = findPitBanner(player)
	if banner then
		banner.Enabled = false
	end
end

--------------------------------------------------------------------------------
-- Event-Pit: Farbe und Anzeigetafel von aussen setzbar (EventService)
--------------------------------------------------------------------------------

-- Anders als findPitBanner gibt es das Event-Pit nur EINMAL fuer die ganze
-- Welt, nicht pro Spieler — keine Player-Suche noetig.
local function findEventPitContainer(): Model?
	local platform = workspace:FindFirstChild("Platform")
	if not platform then return nil end

	local pit = platform:FindFirstChild("EventPit")
	return if pit and pit:IsA("Model") then pit else nil
end

export type EventTheme = {
	floorColor : Color3,
	fenceColor : Color3,
	ringColor  : Color3,
}

-- Faerbt Boden, Zaun und Ring des Event-Pits um. Mit `theme = nil` kehrt es
-- zum schlichten Stall-Look zurueck (siehe MapConfig, EVENT_PIT_DEFAULT_*).
-- EventService ruft das genau zweimal pro Zyklus: einmal beim Start eines
-- Events mit dessen Farben, einmal beim Ende mit nil.
function MapService.setEventPitTheme(theme: EventTheme?)
	local container = findEventPitContainer()
	if not container then return end

	local floorColor = if theme then theme.floorColor else MapConfig.EVENT_PIT_DEFAULT_FLOOR_COLOR
	local fenceColor = if theme then theme.fenceColor else MapConfig.EVENT_PIT_DEFAULT_FENCE_COLOR
	local ringColor  = if theme then theme.ringColor  else MapConfig.EVENT_PIT_DEFAULT_RING_COLOR

	-- Material wechselt mit: Wood/SmoothPlastic im Stall-Look, Neon waehrend
	-- eines Events — sonst saehe man den Farbwechsel bei Zaun und Ring kaum,
	-- weil beide im Stall-Look bewusst matt sind.
	local activeMaterial = if theme then Enum.Material.Neon else Enum.Material.Wood
	local ringMaterial   = if theme then Enum.Material.Neon else Enum.Material.SmoothPlastic

	local floor = container:FindFirstChild("EventFloor")
	if floor and floor:IsA("BasePart") then
		floor.Color = floorColor
	end

	local ring = container:FindFirstChild("EventRing")
	if ring and ring:IsA("BasePart") then
		ring.Color    = ringColor
		ring.Material = ringMaterial
	end

	for _, child in container:GetChildren() do
		if child.Name:match("^EventFence_") and child:IsA("BasePart") then
			child.Color    = fenceColor
			child.Material = activeMaterial
		end
	end
end

-- Beschriftet die Countdown-Tafel ueber dem Event-Pit. Anders als
-- setPitBanner blendet das hier NICHT ein/aus — die Tafel steht permanent
-- (siehe buildEventPit): sie zeigt entweder den Countdown bis zum naechsten
-- Event oder Name + Restzeit des laufenden.
function MapService.setEventBanner(title: string, subtitle: string, color: Color3)
	local container = findEventPitContainer()
	if not container then return end

	local anchor = container:FindFirstChild("EventBannerAnchor")
	if not anchor then return end

	local banner = anchor:FindFirstChild("Banner")
	if not (banner and banner:IsA("BillboardGui")) then return end

	local titleLabel = banner:FindFirstChild("Title")
	if titleLabel and titleLabel:IsA("TextLabel") then
		titleLabel.Text       = title
		titleLabel.TextColor3 = color
	end

	local subLabel = banner:FindFirstChild("Sub")
	if subLabel and subLabel:IsA("TextLabel") then
		subLabel.Text = subtitle
	end
end

-- Weltposition der PODEST-OBERFLAECHE des Event-Pits in der Weltmitte.
--
-- Anders als getPitPosition NICHT pro Spieler: das Event-Pit gibt es einmal
-- fuer die ganze Welt (siehe findEventPitContainer). EventParticipationService
-- laesst die Figuren aller teilnehmenden Spieler auf dieselbe Flaeche laufen.
--
-- Der Y-Wert ist dieselbe Rechnung wie in buildEventPit (`floorY`), bewusst
-- aus MapConfig neu gerechnet statt aus der gebauten Geometrie gemessen: die
-- Zahl gehoert der Konfiguration, nicht dem Modell.
function MapService.getEventPitPosition(): Vector3
	local center = MapConfig.CENTER
	local floorY = MapConfig.PLATFORM_TOP_Y
		+ MapConfig.EVENT_PIT_GROUND_CLEARANCE
		+ MapConfig.EVENT_PIT_FLOOR_HEIGHT

	return Vector3.new(center.X, floorY, center.Z)
end

-- Radius der begehbaren Event-Flaeche. EventParticipationService prueft damit
-- serverseitig nach, ob eine Figur tatsaechlich noch dort steht, statt sich auf
-- ein gesetztes Flag zu verlassen.
function MapService.getEventPitRadius(): number
	return MapConfig.EVENT_PIT_RADIUS
end

-- Weltposition der Kampfflaeche dieses Spielers.
-- Wird von PitArenaService benoetigt um die Kaempfer zu platzieren.
function MapService.getPitPosition(player: Player): Vector3?
	local slot = _playerSlot[player]
	if not slot then return nil end
	return MapParts.pitCenter(slot)
end

-- Das CFrame des Plots (Blickrichtung zur Plattform-Mitte).
-- PitArenaService braucht es, um die Kaempfer sinnvoll auszurichten.
function MapService.getPlotCFrame(player: Player): CFrame?
	local slot = _playerSlot[player]
	if not slot then return nil end
	return MapParts.plotCFrame(slot)
end

-- Die stehende Figur eines Baerchis auf dem Plot, falls vorhanden.
-- PitArenaService schickt genau diese Figur in die Arena und wieder zurueck,
-- statt eine zweite Kopie zu bauen — sonst staende derselbe Baerchi doppelt
-- in der Welt.
function MapService.getBaerchiModel(player: Player, baerchiUid: string): Model?
	local model = _plotModels[player]
	if not model then return nil end

	local folder = model:FindFirstChild("Baerchis")
	if not folder then return nil end

	local figure = folder:FindFirstChild("Baerchi_" .. baerchiUid)
	if figure and figure:IsA("Model") then
		return figure
	end
	return nil
end

-- Feiert ein Ereignis (Level-Up, Promotion, Rebirth, ...) SICHTBAR auf dem
-- Plot: Partikel-Stoss, Huepfer, kurzes Aufleuchten (siehe FigureFX.celebrate).
--
-- Bewusst als eigene MapService-Funktion und nicht direkt FigureFX.celebrate
-- vom Aufrufer: der Aufrufer (HoneyService, PromotionService, RebirthService,
-- ...) soll keine Modelle aus der Welt heraussuchen muessen — genau wie bei
-- getBaerchiModel bleibt das MapServices Job. Steht die Figur gerade nicht in
-- der Welt (Plot noch nicht gebaut, Bewegung verzoegert den Neuaufbau), passiert
-- einfach nichts — kein Fehler, der Toast-Text kommt ja trotzdem an.
function MapService.celebrateBaerchi(player: Player, baerchiUid: string, color: Color3)
	local model = MapService.getBaerchiModel(player, baerchiUid)
	if not model then return end

	FigureFX.celebrate(model, color)
end

-- Beschriftung und Transparenz einer Figur mit einem AUSDRUECKLICH
-- angegebenen HP-Wert setzen — auch waehrend eines laufenden PIT-Kampfes.
--
-- Nur fuer PitArenaService: der muss die Figur beim Start der Wiedergabe auf
-- die HP zuruecksetzen, mit denen der Lauf BEGONNEN hat. Die gespeicherten HP
-- stehen zu dem Zeitpunkt laengst auf dem Endwert, der Baerchi saehe sonst
-- schon vor dem ersten Schlag erschoepft aus.
function MapService.setFigureState(model: Model, hp: number, maxHp: number)
	FigureBuilder.writeFigureState(model, hp, maxHp)
end

-- Der Ordner in der Arena, in den die Kampf-Figuren gehoeren.
function MapService.getFighterFolder(player: Player): Folder?
	local model = _plotModels[player]
	if not model then return nil end

	local pit = model:FindFirstChild("PitPlatform")
	if not pit then return nil end

	local fighters = pit:FindFirstChild("Fighters")
	if fighters and fighters:IsA("Folder") then
		return fighters
	end
	return nil
end

-- Baut den PIT-Turm auf genau `level` Etagen aus bzw. ab — idempotent: fehlt
-- eine Etage, wird sie ergaenzt; ist eine zu viel da, wird sie entfernt. Mit
-- `level = 0` verschwindet der Turm komplett.
--
-- PitArenaService ruft das bei jeder Stage mit der neuen Stufenzahl auf, und
-- mit 0 sobald ein Lauf zu Ende ist oder ein neuer beginnt — der Turm bleibt
-- also NIE zwischen zwei Laeufen stehen, genau wie die Kampf-Figuren selbst
-- (siehe clearFighters in PitArenaService).
--
-- Bewegt bei einem Aufbau auch die Anzeigetafel-Verankerung mit nach oben,
-- damit sie ueber dem gewachsenen Turm haengen bleibt statt mittendrin zu
-- stecken.
function MapService.setPitTowerLevel(player: Player, level: number)
	local slot  = _playerSlot[player]
	local model = _plotModels[player]
	if not slot or not model then return end

	local container = model:FindFirstChild("PitPlatform")
	if not container then return end

	local tower = container:FindFirstChild("Tower")
	if not (tower and tower:IsA("Folder")) then return end

	local wanted = math.max(0, math.floor(level))
	local center = MapParts.pitCenter(slot)

	for _, child in tower:GetChildren() do
		local index = tonumber(child.Name:match("^Ring_(%d+)$"))
		if not index or index > wanted then
			child:Destroy()
		end
	end

	for i = 1, wanted do
		if not tower:FindFirstChild("Ring_" .. i) then
			ArenaBuilder.buildTowerRing(tower, center, i)
		end
	end

	local anchor = container:FindFirstChild("PitBannerAnchor")
	if anchor and anchor:IsA("BasePart") then
		local topY = MapConfig.PLATFORM_TOP_Y
			+ wanted * MapConfig.PIT_TOWER_STEP_HEIGHT
			+ MapConfig.PIT_BANNER_HEIGHT
		anchor.CFrame = CFrame.new(center.X, topY, center.Z)
	end
end

-- Hoehe (Y ueber PLATFORM_TOP_Y) der Kampfflaeche bei `level` bereits
-- gewachsenen Etagen. PitArenaService braucht das, um die Kaempfer beim
-- Erklimmen jeder Stage auf die richtige Hoehe zu stellen — dieselbe Formel
-- wie in buildTowerRing, hier aber ohne selbst eine Etage zu bauen.
function MapService.getPitTowerFloorY(level: number): number
	return MapConfig.PLATFORM_TOP_Y + math.max(0, level) * MapConfig.PIT_TOWER_STEP_HEIGHT
end

-- v15: die Bestenlisten-Tafel beschriften (Titel + bis zu
-- LEADERBOARD_BOARD.lines Zeilen). Aufrufer ist LeaderboardService.
local _leaderboardBoard: BasePart? = nil

function MapService.writeLeaderboardBoard(title: string, lines: { string })
	local board = _leaderboardBoard
	if not board then return end
	local surface = board:FindFirstChild("Board")
	if not surface then return end

	local titleLabel = surface:FindFirstChild("Title")
	if titleLabel and titleLabel:IsA("TextLabel") then
		titleLabel.Text = title
	end
	for i = 1, MapConfig.LEADERBOARD_BOARD.lines do
		local line = surface:FindFirstChild("Line" .. i)
		if line and line:IsA("TextLabel") then
			line.Text = lines[i] or ""
		end
	end
end

-- v15: Teile auf der Insel eines Spielers zaehlen (Debug-Befehl "parts",
-- Budget <= 250 pro Insel ohne Baerchi-Mesh). Getrennt nach Bereichen, damit man
-- sieht, wo das Budget hingeht. Die Figuren (importierte Meshes) zaehlen extra.
function MapService.countParts(player: Player): { [string]: number }?
	local model = _plotModels[player]
	if not model then return nil end

	local result: { [string]: number } = { total = 0, figures = 0 }
	for _, child in model:GetChildren() do
		local count = if child:IsA("BasePart") then 1 else 0
		for _, descendant in child:GetDescendants() do
			if descendant:IsA("BasePart") then count += 1 end
		end
		local key = child.Name
		if key == "Baerchis" then
			result.figures += count
		else
			result[key] = (result[key] or 0) + count
			result.total += count
		end
	end
	return result
end

function MapService.init()
	-- Freie Slots einmalig aufbauen
	for slot = 1, MapConfig.PLOT_COUNT do
		table.insert(_freeSlots, slot)
	end

	-- ============================================================
	-- GEOMETRIE-PRUEFUNG
	-- ============================================================
	-- Die Weltgeometrie haengt an einem guten Dutzend Zahlen, die voneinander
	-- abhaengen. Faellt eine aus dem Rahmen, sieht man das im fertigen Spiel als
	-- Loch im Boden oder als Insel im Nichts — und sucht dann im Code statt in
	-- der Config. Diese vier Pruefungen sagen es beim Start, im Klartext.
	--
	-- Sie WARNEN nur und brechen nicht ab: eine Welt mit einer schiefen Zahl ist
	-- immer noch spielbar, und ein harter Abbruch beim Serverstart waere die
	-- schlechtere Rueckmeldung.

	-- 1. Passt das quadratische Beet auf die runde Plot-Insel? Entscheidend ist
	--    die ECKE, nicht die Kante — eine halbe Diagonale, nicht eine halbe Seite.
	local plateCorner = math.sqrt(
		(MapConfig.PLOT_SIZE.X * 0.5) ^ 2 + (MapConfig.PLOT_SIZE.Z * 0.5) ^ 2
	)
	if plateCorner > MapConfig.PLOT_ISLAND_RADIUS then
		warn(
			"[MapService] Das Beet ragt ueber die Plot-Insel:",
			"halbe Diagonale von PLOT_SIZE =", string.format("%.1f", plateCorner),
			"> PLOT_ISLAND_RADIUS =", MapConfig.PLOT_ISLAND_RADIUS
		)
	end

	-- 2. Liegt der Plot-Ring wirklich eine Steglaenge vor der Hauptinsel?
	--    Sonst waere der Steg entweder zu kurz (Luecke) oder zu lang (er endet
	--    auf der Insel).
	local expectedRing = MapConfig.PLATFORM_RADIUS + MapConfig.ISLAND_GAP + MapConfig.PLOT_ISLAND_RADIUS
	if math.abs(MapConfig.PLOT_RING_RADIUS - expectedRing) > 0.5 then
		warn(
			"[MapService] PLOT_RING_RADIUS passt nicht zur Luecke:",
			MapConfig.PLOT_RING_RADIUS, "sollte", expectedRing, "sein",
			"(PLATFORM_RADIUS + ISLAND_GAP + PLOT_ISLAND_RADIUS)"
		)
	end

	-- 3. Beruehren sich zwei benachbarte Plot-Inseln samt Sandkante?
	local shoreRadius = MapConfig.PLOT_ISLAND_RADIUS + MapConfig.SHORE_WIDTH
	local neighbourGap = 2 * MapConfig.PLOT_RING_RADIUS
		* math.sin(math.pi / MapConfig.PLOT_COUNT) - 2 * shoreRadius
	if neighbourGap <= 0 then
		warn(
			"[MapService] Die Plot-Inseln ueberlappen sich:",
			MapConfig.PLOT_COUNT, "Inseln mit Rand", shoreRadius,
			"auf Ring", MapConfig.PLOT_RING_RADIUS
		)
	end

	-- 4. Reicht das Wasser bis hinter die aeusserste Arena?
	local worldEdge = (MapParts.pitCenter(1) - MapConfig.CENTER).Magnitude
		+ MapConfig.PIT_BASE_RADIUS + MapConfig.SHORE_WIDTH
	if worldEdge > MapConfig.WATER_RADIUS then
		warn(
			"[MapService] Die Arenen ragen ueber den Wasserrand:",
			"Weltrand =", string.format("%.0f", worldEdge),
			"> WATER_RADIUS =", MapConfig.WATER_RADIUS
		)
	end

	WorldBuilder.buildPlatform()
	WorldBuilder.buildGlobalLighting()

	-- v15: Bestenlisten-Tafel (LeaderboardService beschriftet sie)
	local platform = workspace:FindFirstChild("Platform")
	_leaderboardBoard = WorldBuilder.buildLeaderboardBoard(platform or workspace)

	-- Sicherheitsnetz: falls PlayerService den Leave-Fall mal verpasst,
	-- bleibt sonst ein Slot dauerhaft belegt.
	Players.PlayerRemoving:Connect(function(player)
		if _playerSlot[player] then
			MapService.despawnIsland(player)
		end
	end)

	print("[MapService] Initialisiert | Plots:", MapConfig.PLOT_COUNT)
end

return MapService
