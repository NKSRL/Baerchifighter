--!strict
-- HoneyPondMode.luau
-- ReplicatedStorage/Modules/HoneyPondMode.luau
--
-- Einzige Zustaendigkeit:
--   - Die Honig-Gebaeude einer Insel auf den richtigen Modus bringen
--     (FeatureFlags.HONEY_POND_V2): EIN Honig-Teich ("HoneyPond") statt
--     Bienenstock + Veredler — und zurueck. Rein, ohne Roblox-Dienste:
--     tools/luau-tests/honey_pond.test.lua.
--
-- NICHTS GEHT VERLOREN: was gerade nicht gilt, liegt in
-- island.retiredBuildings und kommt beim Zurueckschalten unveraendert wieder.
--
-- Beim ERSTEN Wechsel auf den Teich startet er auf dem hoechsten Level der
-- alten Gebaeude und bekommt deren Honig (der Aufrufer deckelt ihn auf das
-- Lager). Ein Teich auf Level L leistet genau so viel wie Stock UND Veredler
-- auf Level L (siehe BuildingBehavior) — niemand faellt zurueck.
--
-- Aufrufer: Types.createDefaultPlayerData (neue Spieler, Rebirth) und
-- PlayerMigration.applyDefaults (jeder Join) — dort VOR dem Aufraeumen
-- unbekannter Gebaeude-Ids, sonst waeren die alten schon weg.
--
-- Bewusst ohne Types (any): Types ruft dieses Modul selbst auf.

local HoneyPondMode = {}

HoneyPondMode.POND = "HoneyPond"
HoneyPondMode.CLASSIC = { "Beehive", "HoneyRefiner" }

local function newBuilding(id: string, now: number): any
	return { id = id, level = 1, honey = 0, lastProducedAt = now }
end

-- Bringt `island` in den Modus `pondOn`. Idempotent: ein zweiter Aufruf
-- aendert nichts mehr. Gibt die Insel zurueck.
function HoneyPondMode.apply(island: any, pondOn: boolean, now: number): any
	local buildings = island.buildings
	if buildings == nil then
		buildings = {}
		island.buildings = buildings
	end
	local retired = island.retiredBuildings or {}

	local active: { string } = if pondOn then { HoneyPondMode.POND } else HoneyPondMode.CLASSIC
	local inactive: { string } = if pondOn then HoneyPondMode.CLASSIC else { HoneyPondMode.POND }

	-- 1. Was jetzt gilt und im Ruhestand liegt, kommt zurueck. Der Ruhestand
	--    gewinnt: ein Gebaeude gleichen Namens in `buildings` kann nur ein
	--    frisch angelegter Standardwert sein (im Ruhestand wird nicht gespielt).
	for _, id in active do
		if retired[id] ~= nil then
			buildings[id] = retired[id]
			retired[id] = nil
		elseif buildings[id] == nil then
			buildings[id] = newBuilding(id, now)
		end
	end

	-- 2. Erster Wechsel auf den Teich: alte Gebaeude stehen noch aktiv da.
	if pondOn then
		local pond = buildings[HoneyPondMode.POND]
		for _, id in HoneyPondMode.CLASSIC do
			local old = buildings[id]
			if old ~= nil then
				pond.level = math.max(pond.level or 1, old.level or 1)
				pond.honey = (pond.honey or 0) + math.max(0, old.honey or 0)
			end
		end
	end

	-- 3. Was nicht gilt, geht in den Ruhestand (ein vorhandener Eintrag dort
	--    bleibt — siehe 1.).
	for _, id in inactive do
		local building = buildings[id]
		if building ~= nil then
			if retired[id] == nil then
				retired[id] = building
			end
			buildings[id] = nil
		end
	end

	island.retiredBuildings = if next(retired) ~= nil then retired else nil
	return island
end

return HoneyPondMode
