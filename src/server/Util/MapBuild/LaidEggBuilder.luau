--!strict
-- LaidEggBuilder.luau
-- ServerScriptService/Util/MapBuild/LaidEggBuilder.luau
--
-- Einzige Zustaendigkeit:
--   - Die gelegten Eier eines Plots in der Welt zeigen und das Beruehren durch
--     den Besitzer an den eingehaengten Handler melden
--
-- Den Handler haengt EggLayService ueber MapService.setEggCollectHandler ein
-- (Pull-Callback statt require, sonst entstuende ein Ringschluss).
--
-- Teil von MapService: nur MapService (und die Builder untereinander)
-- benutzen dieses Modul. Es aendert keine Spielerdaten.

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local EggConfig        = require(ReplicatedStorage.Config.EggConfig)
local Types            = require(ReplicatedStorage.Network.Types)

local FigureFX         = require(ServerScriptService.Util.FigureFX)

local MapParts = require(ServerScriptService.Util.MapBuild.MapParts)

local LaidEggBuilder = {}

-- Wird aufgerufen, wenn der BESITZER eines Plots sein eigenes gelegtes Ei mit
-- der Spielfigur beruehrt. Ohne Handler sammelt Beruehren einfach nichts ein.
local _collectHandler: ((Player, string) -> ())? = nil

function LaidEggBuilder.setCollectHandler(handler: (Player, string) -> ())
	_collectHandler = handler
end

-- Attribut, das jedes gelegte Ei traegt. Der Client liest es beim Klick
-- (WorldController) — dieselbe Konvention wie "BaerchiUid" an den Figuren.
LaidEggBuilder.LAID_EGG_ATTRIBUTE = "LaidEggUid"

-- Ein gelegtes Ei in der Welt: eine kleine Kugel in der Farbe seines Ei-Typs,
-- mit einer kurzen Beschriftung darueber. Eingesammelt wird es, indem die
-- Spielfigur des BESITZERS hindurchlaeuft (Touched) — kein Klick mehr noetig.
--
-- Warum Touched statt ClickDetector: ein Ei anzuklicken heisst erst zielen,
-- dann treffen — bei bis zu zwoelf Eiern auf einem Plot ist das umstaendlich.
-- Der Spieler laesst seinen Baerchi ohnehin standig zum Honig-Teich und
-- zurueck laufen (siehe BaerchiAutopilotService) und hinterlaesst dabei eine
-- Spur aus Eiern — die sollen von selbst eingesammelt werden, sobald man
-- durchlaeuft.
--
-- Server-autoritativ, wie ueberall im Projekt: der Touch-Kontakt loest nicht
-- direkt EggLayService.collect aus (MapService kennt EggLayService nicht,
-- Ringschluss-Gefahr — siehe _collectHandler), sondern ruft nur den
-- eingehaengten Handler auf. Der entscheidet autoritativ, ob das Ei noch da
-- ist und wem es gehoert.
function LaidEggBuilder.buildLaidEgg(parent: Instance, egg: Types.LaidEgg, worldFoot: Vector3, owner: Player): Part?
	local def = EggConfig.data[egg.eggType]
	if not def then
		-- Ei-Typ aus der Config entfernt: still ueberspringen. Ein Ei ohne
		-- Farbe und Namen zu bauen waere schlimmer als keines.
		return nil
	end

	local size = EggConfig.LAY_EGG_SIZE

	local part = MapParts.newPart(
		"LaidEgg_" .. egg.uid,
		size,
		-- Unterkante auf den Fusspunkt: die Kugel liegt auf dem Boden, statt
		-- zur Haelfte darin zu stecken.
		CFrame.new(worldFoot + Vector3.new(0, size.Y * 0.5, 0)),
		def.color,
		Enum.Material.SmoothPlastic
	)
	part.Shape      = Enum.PartType.Ball
	part.CanCollide = false   -- man soll durch Eier laufen koennen, nicht ueber sie stolpern
	part.Parent     = parent

	part:SetAttribute(LaidEggBuilder.LAID_EGG_ATTRIBUTE, egg.uid)

	-- Nur EIN erfolgreicher Touch-Kontakt darf einsammeln: Touched feuert
	-- fuer jeden Frame, in dem die Figur noch im Part steckt, erneut. Ohne
	-- diese Sperre wuerde derselbe Durchlauf den Handler viele Male aufrufen
	-- (harmlos, weil EggLayService.collect bei einem bereits entfernten Ei
	-- einfach nichts tut — aber unnoetige Anfragen).
	local collected = false
	local touchConnection: RBXScriptConnection? = nil
	touchConnection = part.Touched:Connect(function(hit: BasePart)
		if collected then return end

		local character = hit.Parent
		if not character then return end

		local toucher = Players:GetPlayerFromCharacter(character)
		if not toucher then return end

		-- Nur der Besitzer des Plots sammelt sein eigenes Ei ein — ein
		-- durchlaufender Nachbar soll fremde Eier nicht mitnehmen koennen.
		if toucher ~= owner then return end

		collected = true
		if touchConnection then
			touchConnection:Disconnect()
		end

		-- Partikel-Stoss in der Ei-Farbe AN WORKSPACE, nicht am "LaidEggs"-
		-- Ordner: der wird gleich durch den Datenwechsel neu aufgebaut
		-- (renderLaidEggs zerstoert ihn komplett), der Burst soll das
		-- ueberleben statt mitten in der Animation zu verschwinden.
		FigureFX.burstAt(part.Position, def.color, workspace)

		local handler = _collectHandler
		if handler then
			handler(toucher, egg.uid)
		end
	end)

	local billboard = Instance.new("BillboardGui")
	billboard.Name        = "Label"
	billboard.Size        = UDim2.fromScale(4, 1.2)
	billboard.StudsOffset = Vector3.new(0, size.Y * 0.6 + 0.4, 0)
	billboard.AlwaysOnTop = false
	billboard.MaxDistance = EggConfig.LAY_LABEL_DISTANCE
	billboard.Adornee     = part
	billboard.Parent      = part

	local label = MapParts.newTextLabel("Name", billboard, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0))
	label.Text       = def.shortName
	label.TextColor3 = def.color

	return part
end

-- Baut ALLE herumliegenden Eier eines Plots neu.
--
-- Bewusst komplett neu statt einzeln nachzupflegen: es sind hoechstens
-- EggConfig.MAX_UNCOLLECTED_EGGS Stueck (zwoelf kleine Kugeln), und der
-- Vergleich "welches Ei ist neu, welches wurde eingesammelt" waere mehr Code
-- als der gesamte Neuaufbau. Die Baerchi-Figuren sind der Fall, wo sich der
-- Aufwand lohnt — ein Mesh ist um Groessenordnungen teurer als eine Kugel.
--
-- Die Positionen in den Daten sind PLOT-RELATIV (siehe Types.LaidEgg): hier
-- werden sie in Weltkoordinaten zurueckgerechnet.
function LaidEggBuilder.renderLaidEggs(plotModel: Model, slot: number, islandData: Types.IslandData, owner: Player)
	local old = plotModel:FindFirstChild("LaidEggs")
	if old then old:Destroy() end

	local folder = Instance.new("Folder")
	folder.Name   = "LaidEggs"
	folder.Parent = plotModel

	-- Typisiert statt direkt aus islandData gelesen: ein Datenpaket von einem
	-- aelteren Serverstand haette das Feld nicht, und ohne die Annotation
	-- verliert die Schleife darunter den Typ.
	local eggs: { Types.LaidEgg } = islandData.laidEggs or {}
	if #eggs == 0 then
		return
	end

	local plotCFrame = MapParts.plotCFrame(slot)
	if not plotCFrame then return end

	for _, egg in eggs do
		local worldFoot = plotCFrame:PointToWorldSpace(Vector3.new(egg.x, egg.y, egg.z))
		LaidEggBuilder.buildLaidEgg(folder, egg, worldFoot, owner)
	end
end

return LaidEggBuilder
