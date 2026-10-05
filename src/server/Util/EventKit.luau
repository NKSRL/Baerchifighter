--!strict
-- EventKit.luau
-- ServerScriptService/Util/EventKit.luau
--
-- Einzige Zustaendigkeit:
--   - Gemeinsame Typen und kleine Werkzeuge der Event-Handler (Teilnehmer,
--     Api, Belohnung, Effekt-Teile, Textmarke ueber der Figur).
--
-- Aus EventHandlers herausgezogen, als das sechste Event (Wespenkoenigin,
-- Util/WaspQueenEvent) dazukam: beide brauchen dieselben Typen und Werkzeuge,
-- und ein gegenseitiges require waere ein Ringschluss. Der Code ist
-- unveraendert aus EventHandlers uebernommen.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EventConfig      = require(ReplicatedStorage.Config.EventConfig)
local Types            = require(ReplicatedStorage.Network.Types)
local CombatCalculator = require(ReplicatedStorage.Modules.CombatCalculator)

local EventKit = {}

--------------------------------------------------------------------------------
-- Typen
--------------------------------------------------------------------------------

-- Ein Teilnehmer, wie EventParticipationService ihn liefert (dort: Presence).
-- Die Handler lesen ihn und setzen nur die drei Steuerfelder unten.
export type Part = {
	player     : Player,
	figure     : Model,
	baerchiUid : string,
	homeFoot   : Vector3,
	standFoot  : Vector3,
	busy       : boolean?,   -- Figur laeuft gerade (walkTo)
	cancelWalk : boolean?,   -- laufende Bewegung abbrechen
	abducting  : boolean?,   -- UFO hat die Figur gerade
	abductedAt : number?,    -- Sammel-Update 1.1: os.clock() beim Start der Entfuehrung (Waechter)
}

-- Was EventParticipationService den Handlern bereitstellt (buildApi).
export type Api = {
	center       : Vector3,
	radius       : number,
	running      : () -> boolean,
	footOf       : (Model) -> Vector3,
	participants : () -> { Part },
	stillHere    : (Part) -> boolean,
	plotPosition : (Player) -> Vector3?,
	level        : (Part) -> number,
	power        : (Part) -> number,
	-- Sammel-Update 2.4: Text als LocMsg (der Client uebersetzt). Ein
	-- einfacher string bleibt fuer Altstellen erlaubt.
	toast        : (Player, string | Types.LocMsg) -> (),
	recall       : (Player) -> (),
	finishHome   : (Part) -> (),
	ufoReward    : (Part) -> (),
	walkTo       : (Part, Vector3) -> boolean,

	-- v17 (lebendige Events)
	grantEgg     : (Player, Types.EggType, number) -> boolean,
	notify       : (Player, Types.LocMsg, string?) -> (),
	announce     : (Types.LocMsg, string?) -> (),
	fightStats   : (Part) -> CombatCalculator.FighterStats?,
	finishEarly  : () -> (),
}

-- Belohnung eines Spielers am Event-Ende.
export type Reward = {
	egg          : EventConfig.EventBonus?,
	mutationRoll : boolean?,

	-- v17 (Boss): Zusatz-Belohnungen, ausgezahlt von EventParticipationService
	-- ueber EconomyService / CombRecyclerService.
	gummies        : number?,                   -- Basisbetrag (mit Rebirth-Multiplikator)
	combUnits      : number?,                   -- Wabeneinheiten in den Recycler
	extraEgg       : EventConfig.EventBonus?,   -- zweites Ei (Top-Rang: Sprung-Ei)
	rarityUpFactor : number?,                   -- Rarity-Up-Wurf: Faktor auf EventConfig.RARITY_UP_CHANCE
	notice         : Types.LocMsg?,             -- Zusammenfassung fuer den Spieler
	-- HBB Paket 7: Boss-Stufe (0-4) und ihr Zusatz-Wurf (Mutation)
	bossTier       : number?,
	tierBonus      : EventConfig.EventBonus?,
	tierEggs       : number?,                   -- Basis-Eier der Stufe
}

export type Session = {
	stop : () -> { [Player]: Reward },
}

export type Handler = (Api, EventConfig.EventDef) -> Session

--------------------------------------------------------------------------------
-- Optik der Textmarke (keine Balance)
--------------------------------------------------------------------------------

-- Textmarke ueber der Figur
local LABEL_SIZE              = UDim2.fromOffset(120, 26)
local LABEL_OFFSET            = Vector3.new(0, 6, 0)
local LABEL_MAX_DISTANCE      = 220
local LABEL_BACK_TRANSPARENCY = 0.35
local LABEL_BACK_COLOR        = Color3.fromRGB(20, 20, 30)
local LABEL_TEXT_COLOR        = Color3.new(1, 1, 1)

--------------------------------------------------------------------------------
-- Werkzeuge
--------------------------------------------------------------------------------

function EventKit.flatDist(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Eigenschaften per Tabelle setzen. Ueber `any`, weil der Klassenname erst
-- zur Laufzeit feststeht und --!strict die Felder sonst nicht kennt.
function EventKit.make(className: string, props: { [string]: any }, parent: Instance): Instance
	local inst: any = Instance.new(className)
	for key, value in props do
		inst[key] = value
	end
	inst.Parent = parent
	return inst
end

function EventKit.fxPart(props: { [string]: any }, parent: Instance): BasePart
	props.Anchored   = true
	props.CanCollide = false
	props.CanQuery   = false
	props.CanTouch   = false
	props.CastShadow = false
	return EventKit.make("Part", props, parent) :: BasePart
end

function EventKit.rootOf(figure: Model): BasePart?
	return figure.PrimaryPart or figure:FindFirstChildWhichIsA("BasePart", true)
end

-- Kleine Textmarke ueber der Figur (Fortschritt, "Ei!", ...). nil entfernt sie.
function EventKit.setLabel(part: Part, text: string?)
	local figure = part.figure
	if not figure or not figure.Parent then
		return
	end

	local gui = figure:FindFirstChild("EventLabel")
	if not text then
		if gui then
			gui:Destroy()
		end
		return
	end

	if not gui then
		local root = EventKit.rootOf(figure)
		if not root then
			return
		end
		local created = EventKit.make("BillboardGui", {
			Name         = "EventLabel",
			Size         = LABEL_SIZE,
			StudsOffset  = LABEL_OFFSET,
			AlwaysOnTop  = true,
			Adornee      = root,
			MaxDistance  = LABEL_MAX_DISTANCE,
		}, figure)
		EventKit.make("TextLabel", {
			Name                   = "Text",
			Size                   = UDim2.fromScale(1, 1),
			BackgroundTransparency = LABEL_BACK_TRANSPARENCY,
			BackgroundColor3       = LABEL_BACK_COLOR,
			TextColor3             = LABEL_TEXT_COLOR,
			TextScaled             = true,
			Font                   = Enum.Font.GothamBold,
		}, created)
		gui = created
	end

	local label = (gui :: Instance):FindFirstChild("Text")
	if label and label:IsA("TextLabel") then
		label.Text = text
	end
end

function EventKit.newFolder(name: string): Folder
	local folder = Instance.new("Folder")
	folder.Name   = name
	folder.Parent = workspace
	return folder
end

return EventKit
