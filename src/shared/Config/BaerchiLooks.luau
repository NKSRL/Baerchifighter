--!strict
-- BaerchiLooks.luau
-- ReplicatedStorage/Config/BaerchiLooks.luau
--
-- Einzige Zustaendigkeit (R3, Baerchi-Baukasten):
--   - Pro Baerchi-ID beschreiben, wie die EINE Base-Figur
--     (Assets.BaerchiTemplate) aussieht: Fellfarbe, Muster, Zubehoer an den
--     Andockpunkten ("Slot_<Name>" als Attachment am Koerper).
--   - Zubehoer-Definitionen (Slot, Groesse, Versatz). Die Modelle liegen in
--     ReplicatedStorage.Assets.Accessories (Name = Zubehoer-ID, Front -Z).
--
-- Reine Daten + Pruefung. Gebaut wird in Modules/BaerchiMesh.build (die einzige
-- Stelle, die einen Baerchi baut). Fehlt ein Eintrag → Rueckfall auf die
-- Rarity-Faerbung (heutiger Look), kein Fehler. Schalter: BAERCHI_KIT_V1.
--
-- Alle Masse sind Anteile/Studs am Template-Massstab 1 und werden mit der
-- Figur skaliert.

local BaerchiLooks = {}

-- Feste Andockpunkte (je Slot nur 1 Zubehoerteil gleichzeitig)
BaerchiLooks.SLOTS = { "Kopf", "OhrLinks", "OhrRechts", "Hals", "Ruecken", "Schwanz", "Fuesse", "Gesicht" }

export type Accessory = {
	slot   : string,
	scale  : number?,     -- Faktor auf das Modell (Standard 1)
	offset : Vector3?,    -- Versatz in Template-Studs, im Slot-Raum (Front = -Z des Zubehoers)
}

export type Look = {
	furColor    : Color3?,                  -- nil = Rarity-Farbe
	pattern     : string?,                  -- Schluessel in PATTERNS
	accessories : { [string]: string }?,    -- Slot -> Zubehoer-ID
}

-- Muster: Textur auf dem Koerper (Fellfarbe tint die Textur). `texture` leer = noch kein Bild.
BaerchiLooks.PATTERNS = {} :: { [string]: { texture: string } }

BaerchiLooks.ACCESSORIES = {
	-- Platzhalter-Kit (aus Ei-Teilen), ersetzt in R3b durch das echte Kit
	Krone_Gold     = { slot = "Kopf",    scale = 1.35, offset = Vector3.new(0, 0.05, 0) },
	Krone_Kristall = { slot = "Kopf",    scale = 1.35, offset = Vector3.new(0, 0.05, 0) },
	Halo_Gold      = { slot = "Kopf",    scale = 0.55, offset = Vector3.new(0, 0.45, 0) },
	Halo_Kosmos    = { slot = "Kopf",    scale = 0.55, offset = Vector3.new(0, 0.45, 0) },
	Stern_Kosmos   = { slot = "Ruecken", scale = 2.2,  offset = Vector3.new(0, 0.2, 0) },
	Stern_Void     = { slot = "Ruecken", scale = 2.2,  offset = Vector3.new(0, 0.2, 0) },
} :: { [string]: Accessory }

local GOLD, CRYSTAL, VOID, COSMOS = { Kopf = "Krone_Gold" }, { Kopf = "Krone_Kristall" }, { Ruecken = "Stern_Void" }, { Kopf = "Halo_Kosmos" }
local COSMOS_TOP = { Kopf = "Halo_Kosmos", Ruecken = "Stern_Kosmos" }

BaerchiLooks.LOOKS = {
	-- Stamm (Honig/Wald): Rarity-Faerbung, Zubehoer folgt mit dem Kit (R3b)
	RedBaerchi = {}, GreenBaerchi = {}, YellowBaerchi = {}, BlueBaerchi = {}, OrangeBaerchi = {}, SugarBaerchi = {},
	-- Gold
	GoldenGrizzly = { accessories = GOLD }, AncientBaerchi = { accessories = GOLD },
	PhoenixBaerchi = { accessories = GOLD }, SeraphBaerchi = { accessories = { Kopf = "Halo_Gold" } },
	-- Kristall
	CrystalBaerchi = { accessories = CRYSTAL }, RainbowBaerchi = { accessories = CRYSTAL },
	GlacierBaerchi = { accessories = CRYSTAL }, NorthernLightBaerchi = { accessories = CRYSTAL },
	-- Void
	VoidBaerchi = { accessories = VOID }, PhantomBaerchi = { accessories = VOID }, EclipseBaerchi = { accessories = VOID },
	-- Kosmos
	CosmicBaerchi = { accessories = COSMOS }, CometBaerchi = { accessories = COSMOS },
	NebulaBaerchi = { accessories = COSMOS }, PulsarBaerchi = { accessories = COSMOS },
	RiddleBaerchi = { accessories = COSMOS_TOP }, ShadeBaerchi = { accessories = COSMOS_TOP },
	GenesisBaerchi = { accessories = COSMOS_TOP }, TitanBaerchi = { accessories = COSMOS_TOP },
	ChronosBaerchi = { accessories = COSMOS_TOP }, InfinityBaerchi = { accessories = COSMOS_TOP },
	OmegaBaerchi = { accessories = COSMOS_TOP },
} :: { [string]: Look }

function BaerchiLooks.get(configId: string): Look?
	return BaerchiLooks.LOOKS[configId]
end

-- Konsistenz-Test: jede Muster-/Zubehoer-ID existiert, der Slot passt, und jeder
-- Baerchi aus `allConfigIds` hat einen Look. `accessoryExists(id)` prueft das Modell
-- (nur im Spiel/Studio moeglich, in reinen Tests weglassen). Gibt Fehlertexte zurueck.
function BaerchiLooks.validate(allConfigIds: { string }, accessoryExists: ((string) -> boolean)?): { string }
	local problems: { string } = {}
	local validSlot: { [string]: boolean } = {}
	for _, slot in BaerchiLooks.SLOTS do validSlot[slot] = true end

	for id, def in BaerchiLooks.ACCESSORIES do
		if not validSlot[def.slot] then
			table.insert(problems, "Zubehoer " .. id .. ": unbekannter Slot " .. def.slot)
		end
		if accessoryExists and not accessoryExists(id) then
			table.insert(problems, "Zubehoer " .. id .. ": Modell fehlt")
		end
	end
	for _, configId in allConfigIds do
		if not BaerchiLooks.LOOKS[configId] then
			table.insert(problems, "Baerchi " .. configId .. ": kein Look")   -- ui-ok: Pruefmeldung fuer Log und Test
		end
	end
	for configId, look in BaerchiLooks.LOOKS do
		if look.pattern and not BaerchiLooks.PATTERNS[look.pattern] then
			table.insert(problems, configId .. ": unbekanntes Muster " .. look.pattern)
		end
		for slot, accId in look.accessories or {} do
			local def = BaerchiLooks.ACCESSORIES[accId]
			if not def then
				table.insert(problems, configId .. ": unbekanntes Zubehoer " .. accId)
			elseif def.slot ~= slot then
				table.insert(problems, configId .. ": " .. accId .. " gehoert in Slot " .. def.slot .. ", nicht " .. slot)   -- ui-ok: Pruefmeldung fuer Log und Test
			end
		end
	end
	return problems
end

return BaerchiLooks
