--!strict
-- GuideSteps.luau
-- ReplicatedStorage/Modules/GuideSteps.luau
--
-- Einzige Zustaendigkeit:
--   - Aus dem Spielstand ableiten, welcher Fuehrungsschritt gerade dran ist
--     (reine Funktion, keine Roblox-Dienste, kein eigenes Feld im Spielstand)
--
-- Kontext: HBB Paket 2. Ein neues Kind soll ohne Text sehen, was als
-- Naechstes kommt. Der Client (GuideController) zeigt den Schritt als Beam in
-- der Welt oder als pulsierenden Pfeil am Knopf.
--
-- Jeder Schritt endet, sobald seine Bedingung aus den Daten erfuellt ist.
-- Ein Tutorial-Fortschritt wird nirgends gespeichert.
--
-- Reihenfolge (Abweichung vom Plan-Vorschlag, siehe Bericht): ein frisches
-- Konto hat noch keinen Baerchi und damit keine gelegten Eier. Deshalb zuerst
-- oeffnen, dann kaempfen; "gelegtes Ei einsammeln" kommt, sobald eines liegt.
--
-- Keine requires: das Modul laeuft unveraendert im Luau-Test
-- (tools/luau-tests/guide_steps.test.lua).

-- Sammel-Update 05.10. (Paket 3.5): Einsteiger-Kette Ei oeffnen -> kaempfen ->
-- Waben holen und im Recycler abgeben -> Gebaeude verbessern -> Event. Jeder
-- Schritt bekommt im Client einen Satz, was er bringt ("guide.<step>").
--
-- 08.10. (Tower-Terminal): nach dem ersten Schaffen von Tower I der Schritt
-- "tower": zum Terminal an der Bruecke, dort zur Karte von Tower II. Fertig,
-- sobald ein anderer Tower gewaehlt ist oder dort schon gekaempft wurde.
-- Ausnahme von der Veteranen-Regel (siehe towerSwitchPending).
export type Step = "hatch" | "fight" | "collect" | "merchant" | "combs" | "upgrade" | "event" | "tower"

-- Nur die Felder, die hier gelesen werden. PlayerDataUpdate (Client) und
-- PlayerData (Server) passen beide hinein.
export type View = {
	rebirthCount : number,
	island : {
		baerchis      : { [string]: any },
		eggStock      : { [string]: number },
		laidEggs      : { any },
		towerProgress : { [string]: number }?,
		buildings     : { [string]: { level: number } }?,   -- Sammel-Update 3.5
		recycler      : { level: number }?,
	},
	towers : { records: { [string]: number }, selected: string?, unlocked: { [string]: boolean }? }?,
	quests : { chainDone: number }?,
	stats  : { totalEventsCompleted: number?, totalCombsDelivered: number? }?,
	gummies : number?,
}

-- Optionen, die der Aufrufer aus Configs mitgibt (haelt das Modul frei von
-- requires). merchantPrice = Preis eines Basis-Eis beim Haendler; nil = der
-- Haendler-Schritt ist aus (Flag MAP_V2_MERCHANT).
export type Options = {
	merchantPrice : number?,
}

local GuideSteps = {}

-- Ab hier gilt ein Spielstand nicht mehr als neu: kein Schritt mehr.
GuideSteps.VETERAN_CHAIN_DONE = 4

local function isEmpty(map: { [any]: any }?): boolean
	return map == nil or next(map) == nil
end

local function countMap(map: { [any]: number }): number
	local total = 0
	for _, n in map do
		total += n
	end
	return total
end

function GuideSteps.isVeteran(view: View): boolean
	if (view.rebirthCount or 0) > 0 then return true end
	local quests = view.quests
	return quests ~= nil and (quests.chainDone or 0) >= GuideSteps.VETERAN_CHAIN_DONE
end

function GuideSteps.hasFought(view: View): boolean
	local towers = view.towers
	if towers and not isEmpty(towers.records) then return true end
	return not isEmpty(view.island.towerProgress)
end

-- Sammel-Update 3.5: irgendein Gebaeude (oder der Recycler) ueber Level 1.
function GuideSteps.hasUpgraded(view: View): boolean
	local recycler = view.island.recycler
	if recycler and (recycler.level or 1) > 1 then return true end
	for _, building in view.island.buildings or {} do
		if (building.level or 1) > 1 then return true end
	end
	return false
end

function GuideSteps.eventsDone(view: View): number
	local stats = view.stats
	return if stats then (stats.totalEventsCompleted or 0) else 0
end

-- 08.10.: Tower II ist frei (Tower I geschafft), aber der Spieler hat noch
-- nie gewechselt: weiter in Tower I gewaehlt und in keinem anderen Tower
-- gekaempft. Nur ohne Rebirth.
--
-- Bewusst VOR der Veteranen-Regel "4 Ketten-Quests": die ist nach fuenf
-- gewonnenen Kaempfen erfuellt, also lange bevor jemand Tower I schafft —
-- mit ihr saehe diesen Schritt praktisch niemand. Sie schuetzt alte Konten
-- vor der Einfuehrung; das Umstellen ist dagegen fuer jeden neu (Annahme,
-- im Bericht). Die Rebirth-Regel gilt weiter.
function GuideSteps.towerSwitchPending(view: View): boolean
	if (view.rebirthCount or 0) > 0 then return false end
	local towers = view.towers
	if not towers or not towers.unlocked or towers.unlocked.II ~= true then return false end
	if (towers.selected or "I") ~= "I" then return false end
	for towerId, record in towers.records do
		if towerId ~= "I" and record > 0 then return false end
	end
	return true
end

-- Der aktuelle Schritt oder nil (fertig bzw. kein neuer Spieler).
function GuideSteps.current(view: View, options: Options?): Step?
	if GuideSteps.towerSwitchPending(view) then
		return "tower"
	end
	if GuideSteps.isVeteran(view) then
		return nil
	end

	local island = view.island
	local hasBaerchi = not isEmpty(island.baerchis)
	local eggsInStock = countMap(island.eggStock)

	-- 1. Ei oeffnen: noch kein Baerchi, aber ein Ei im Lager
	if not hasBaerchi then
		if eggsInStock > 0 then
			return "hatch"
		end
		-- Kein Ei, kein Baerchi: zum Haendler, wenn es den Schritt gibt
		local price = if options then options.merchantPrice else nil
		if price and (view.gummies or 0) >= price then
			return "merchant"
		end
		return nil
	end

	-- 2. Erster Kampf
	if not GuideSteps.hasFought(view) then
		return "fight"
	end

	-- 3. Gelegtes Ei einsammeln (nur waehrend der Einfuehrung)
	local onboarding = GuideSteps.eventsDone(view) == 0
	if onboarding and #island.laidEggs > 0 then
		return "collect"
	end

	-- 4. Sammel-Update 3.5: Waben holen und im Recycler abgeben
	local stats = view.stats
	if onboarding and stats and (stats.totalCombsDelivered or 0) == 0 then
		return "combs"
	end

	-- 5. Sammel-Update 3.5: ein Gebaeude verbessern
	if onboarding and not GuideSteps.hasUpgraded(view) then
		return "upgrade"
	end

	-- 6. Erstes Event (der Client zeigt diesen Schritt nur kurz, Paket 3.2)
	if onboarding then
		return "event"
	end

	-- 5. Kein Ei mehr (weder im Lager noch auf dem Plot), Gummies reichen:
	-- zum Haendler (HBB Paket 5, nur solange der Spieler neu ist)
	local price = if options then options.merchantPrice else nil
	if price and eggsInStock == 0 and #island.laidEggs == 0 and (view.gummies or 0) >= price then
		return "merchant"
	end

	return nil
end

return GuideSteps
