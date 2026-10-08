--!strict
-- PlotDisplayService.luau
-- ServerScriptService/Services/PlotDisplayService.luau
--
-- Einzige Zustaendigkeit:
--   - Entscheiden WANN die sichtbare Darstellung eines Plots nachgezogen
--     werden muss — und mit welchem der drei unterschiedlich teuren Wege.
--
-- Haengt an PlayerService.onDataChanged. Das feuert bei JEDER Aenderung, also
-- auch bei jedem einzelnen Gummy. Alles jedes Mal neu zu bauen waere
-- Verschwendung, deshalb merkt sich dieser Service drei Signaturen und
-- vergleicht sie:
--
--   STRUKTUR   (uid + Level jedes Baerchis)
--       → MapService.updateBaerchis: baut alle Mesh-Figuren neu. Teuer.
--         Noetig wenn ein Baerchi dazukommt, wegfaellt oder im Level steigt.
--
--   ZUSTAND    (uid + aktuelle HP)
--       → MapService.updateBaerchiStates: schreibt nur Beschriftung und
--         Erschoepfung an bestehende Figuren. Billig. HP aendern sich bei
--         jedem Fuettern und jedem PIT-Lauf — dafuer 25 Meshes neu zu bauen
--         waere absurd.
--
--   GEBAEUDE   (id + Level + Honig)
--       → MapService.updateBuildingSigns: schreibt die Schilder neu. Billig.
--         Honig aendert sich alle 20 Sekunden.
--
--   EIER       (uids der herumliegenden Eier)
--       → MapService.updateLaidEggs: baut die kleinen Kugeln neu. Billig —
--         es sind hoechstens zwoelf, und sie sind keine Meshes.
--         Aendert sich, wenn der Baerchi eines legt oder der Spieler eines
--         aufsammelt.
--
--   RECYCLER   (Level + Warteschlange des Waben-Recyclers)
--       → MapService.updateRecycler: schreibt Schild und Lampe. Billig.
--         Aendert sich jede Sekunde, solange der Recycler arbeitet.
--
--   LOOKS      (v15: Look-Stufe jedes Gebaeudes und des Recyclers)
--       → MapService.updateBuildingLooks: baut genau das Gebaeude neu, dessen
--         Look sich geaendert hat, mit kurzer Aufwertungs-Show. Haengt am
--         LOOK, nicht am Level — ein Ausbau innerhalb eines Looks schreibt nur
--         das Schild (GEBAEUDE oben).
--
--   TOWER      (v15: Look + Etagen + Schildtext des Tower-Turms)
--       → MapService.updateTowerShowcase (Neuaufbau des Turms, Show nur beim
--         Look-Wechsel) und MapService.setOwnerBadge (Symbol am Plot-Schild).
--         Aendert sich nur bei einem neuen Rekord oder Tower.
--
--   TERMINAL   (08.10.: Zustand, gewaehlter Tower, Rekord, Fortschritt)
--      → MapService.updateTerminal: schreibt nur Attribute, kein Neubau.
--
-- Die Figuren und Schilder selbst baut MapService — dieser Service entscheidet
-- nur WANN und WELCHE Tiefe.
--
-- EINE SACHE ENTSCHEIDET DIESER SERVICE BEWUSST NICHT: ob die Figur gerade
-- mitten in einer Bewegung steckt. Diese Sperre sitzt in
-- MapService.updateBaerchis selbst, damit sie fuer JEDEN Aufrufer gilt und
-- nicht an jeder Aufrufstelle wiederholt werden muss. Hier unten wird nur die
-- Quelle fuer frische Daten eingehaengt, mit der MapService den verschobenen
-- Neuaufbau spaeter nachholt (siehe init).
--
-- Wichtig fuer das Verstaendnis des Signatur-Vergleichs: eine verschobene
-- Darstellung gilt hier trotzdem sofort als "dargestellt". Das ist richtig, so
-- lange MapService das Nachholen uebernimmt — waere es andersherum, muesste
-- dieser Service den Zustand einer fremden Warteschlange mitverfolgen.
--
-- Ersetzt den frueheren BaerchiDisplayService, der nur die Figuren kannte und
-- inzwischen aus dem Projekt entfernt ist.

local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")

local Types            = require(ReplicatedStorage.Network.Types)
local BuildingBehavior = require(ReplicatedStorage.Config.BuildingBehavior)
local IncubatorRules = require(ReplicatedStorage.Modules.IncubatorRules)   -- Paket 8
local TowerConfig      = require(ReplicatedStorage.Config.TowerConfig)
local Loc       = require(ReplicatedStorage.Localization.Loc)

local PlayerService = require(ServerScriptService.Services.PlayerService)
local MapService    = require(ServerScriptService.Services.MapService)

local PlotDisplayService = {}

type Signatures = {
	incubator : string,   -- Sammel-Update Paket 8
	structure : string,
	state     : string,
	buildings : string,
	eggs      : string,
	recycler  : string,
	looks     : string,
	tower     : string,
	terminal  : string,   -- 08.10. Tower-Terminal
}

local _signatures: { [Player]: Signatures } = {}

--------------------------------------------------------------------------------
-- Signaturen
--------------------------------------------------------------------------------

-- Was sich aendern muss, damit die Figur neu gebaut wird: welche Baerchis es
-- gibt, auf welchem Level sie stehen (das Level aendert die Groesse der
-- Beschriftung und kann spaeter das Modell aendern) — UND wer gerade
-- ausgeruestet ist, seit nur noch dieser eine sichtbar gebaut wird. Ohne
-- equippedUid hier wuerde ein Equip-Wechsel auf einen gleich hochstufigen
-- Baerchi denselben String ergeben und die Signatur haelt die Aenderung
-- faelschlich fuer bereits dargestellt.
--
-- Die MUTATION gehoert aus demselben Grund dazu: sie bestimmt Fellfarbe, Aura
-- und das Kuerzel auf dem Namensschild (siehe MapService.buildBaerchiFigure).
-- Normalerweise aendert sie sich nie nach dem Schluepfen — der Mutations-Sturm
-- (EventParticipationService) kann sie aber mitten im Spiel anheben, und ohne
-- diesen Eintrag liefe die Figur bis zum naechsten Insel-Neuaufbau in der
-- alten Farbe weiter.
local function structureSignature(data: Types.PlayerData): string
	local parts: { string } = {}
	for uid, baerchi in data.island.baerchis do
		table.insert(parts, string.format("%s:%d:%s:%s", uid, baerchi.level, baerchi.mutation or "-", baerchi.rarity))
	end
	table.sort(parts)
	table.insert(parts, "equipped:" .. (data.island.equippedUid or ""))
	return table.concat(parts, "|")
end

-- Was sich aendern muss, damit die Beschriftung neu geschrieben wird.
local function stateSignature(data: Types.PlayerData): string
	local parts: { string } = {}
	for uid, baerchi in data.island.baerchis do
		table.insert(parts, uid .. ":" .. baerchi.currentHp)
	end
	table.sort(parts)
	return table.concat(parts, "|")
end

-- Was sich aendern muss, damit die Gebaeude-Schilder neu geschrieben werden.
local function buildingSignature(data: Types.PlayerData): string
	local parts: { string } = {}
	for id, building in data.island.buildings do
		table.insert(parts, string.format("%s:%d:%d", id, building.level, building.honey or 0))
	end
	table.sort(parts)
	return table.concat(parts, "|")
end

-- Was sich aendern muss, damit die Eier neu gebaut werden: WELCHE Eier
-- herumliegen. Die Position gehoert bewusst nicht dazu — ein gelegtes Ei
-- bewegt sich nie, es kommt nur dazu oder verschwindet.
local function eggSignature(data: Types.PlayerData): string
	local parts: { string } = {}
	for _, egg in data.island.laidEggs or {} do
		table.insert(parts, egg.uid)
	end
	table.sort(parts)
	return table.concat(parts, "|")
end

-- Was sich aendern muss, damit Schild und Lampe des Waben-Recyclers neu
-- geschrieben werden: Level und Warteschlange.
local function recyclerSignature(data: Types.PlayerData): string
	local recycler = data.island.recycler
	return string.format("%d:%d", recycler.level, recycler.queued)
end

-- v15: Look-Stufen. Bewusst NICHT das Level: ein Gebaeude wird nur neu
-- gebaut, wenn es einen neuen Look bekommt (README 4.2).
local function lookSignature(data: Types.PlayerData): string
	local parts: { string } = {}
	for id, building in data.island.buildings do
		table.insert(parts, string.format("%s:%d", id, BuildingBehavior.getLook(building.level)))
	end
	table.sort(parts)
	table.insert(parts, "Recycler:" .. BuildingBehavior.getLook(data.island.recycler.level))
	return table.concat(parts, "|")
end

-- v15: Tower-Turm: hoechster Tower (Look) und Rekord darin (Etagen + Schild).
local function towerSignature(data: Types.PlayerData): string
	local towerId, record = TowerConfig.bestRecord(data.towers)
	local highest = data.towers.highestTower
	if TowerConfig.getIndex(highest) > TowerConfig.getIndex(towerId) then
		towerId, record = highest, data.towers.records[highest] or 0
	end
	return string.format("%s:%d", towerId, record)
end

-- Sammel-Update Paket 8: Inkubator — belegte Plaetze (Ei + Zeitmarken),
-- Level und Platz-Zahl. Fortschritt rechnet der Client selbst.
local function incubatorSignature(data: Types.PlayerData): string
	local incubator = data.island.incubator
	if not incubator then return "" end
	local parts: { string } = { tostring(incubator.level), tostring(IncubatorRules.slotCountFor(data)) }
	for _, entry in incubator.slots do
		table.insert(parts, string.format("%d=%s@%d", entry.slot, entry.eggType, entry.finishAt))
	end
	-- INCUBATOR_BREED: Baerchis in den Plaetzen (Figur, Takt, letzte Brut)
	for _, entry in incubator.breeders or {} do
		local baerchi = data.island.baerchis[entry.uid]
		table.insert(parts, string.format("b%d=%s:%s:%s@%d", entry.slot, entry.uid,
			if baerchi then baerchi.rarity else "?", if baerchi then tostring(baerchi.mutation) else "",
			entry.lastEggAt))
	end
	return table.concat(parts, "|")
end

-- 08.10.: Tower-Terminal — Zustand, gewaehlter Tower, Rekord, Fortschritt.
local function terminalView(data: Types.PlayerData): { state: string, tower: string, record: number, nextTower: string, newTower: string, progress: number, needed: number }
	local towers = data.towers
	local nextTower, newTower = "", ""
	for _, def in TowerConfig.TOWERS do
		if newTower == "" and TowerConfig.isNew(def.id, towers) then
			newTower = def.id
		end
		if nextTower == "" and not TowerConfig.isUnlockedByClear(def.id, towers.records, towers.unlocked) then
			nextTower = def.id
		end
	end
	local _, progress, needed = TowerConfig.getUnlockProgress(nextTower, towers.records)
	return {
		state     = TowerConfig.terminalState(towers),
		tower     = towers.selected,
		record    = towers.records[towers.selected] or 0,
		nextTower = nextTower,
		newTower  = newTower,
		progress  = progress,
		needed    = needed,
	}
end

local function terminalSignature(data: Types.PlayerData): string
	local v = terminalView(data)
	return string.format("%s|%s|%d|%s|%s|%d|%d", v.state, v.tower, v.record, v.nextTower, v.newTower, v.progress, v.needed)
end

local function allSignatures(data: Types.PlayerData): Signatures
	return {
		terminal  = terminalSignature(data),
		incubator = incubatorSignature(data),
		structure = structureSignature(data),
		state     = stateSignature(data),
		buildings = buildingSignature(data),
		eggs      = eggSignature(data),
		recycler  = recyclerSignature(data),
		looks     = lookSignature(data),
		tower     = towerSignature(data),
	}
end

-- Turm und Plot-Symbol aus dem Tower-Stand (Signatur "Tower:Rekord").
local function applyTower(player: Player, signature: string, show: boolean)
	local towerId, recordText = string.match(signature, "^([^:]+):(%d+)$")
	local def = TowerConfig.get(towerId or "") or TowerConfig.TOWERS[1]
	local record = tonumber(recordText) or 0

	MapService.updateTowerShowcase(player, {
		look   = def.look,
		floors = TowerConfig.getShowcaseFloors(def.id, record),
		title  = Loc.msg("ui.world.showcase_title", {
			name = player.DisplayName, tower = Loc.msg("ui.petbar.tower", { n = def.numeral }), record = record,
		}),
		color  = def.color,
	}, show)
	MapService.setOwnerBadge(player, Loc.msg("ui.world.owner_badge", {
		tower = Loc.msg("ui.petbar.tower", { n = def.numeral }), record = record,
	}), def.color)
end

--------------------------------------------------------------------------------
-- Abgleich
--------------------------------------------------------------------------------

local function refresh(player: Player, data: Types.PlayerData)
	local current  = allSignatures(data)
	local previous = _signatures[player]

	if not previous then
		-- Noch keine Signatur (sollte nach onDataLoaded nicht vorkommen):
		-- einmal komplett nachziehen und merken.
		_signatures[player] = current
		MapService.updateBaerchis(player, data.island)
		MapService.updateBuildingSigns(player, data.island)
		MapService.updateLaidEggs(player, data.island)
		MapService.updateRecycler(player, data.island)
		return
	end

	if previous.structure ~= current.structure then
		-- Neuaufbau schreibt die Zustaende gleich mit — ein zusaetzliches
		-- updateBaerchiStates waere doppelte Arbeit.
		MapService.updateBaerchis(player, data.island)

	elseif previous.state ~= current.state then
		MapService.updateBaerchiStates(player, data.island)
	end

	if previous.buildings ~= current.buildings then
		MapService.updateBuildingSigns(player, data.island)
	end

	-- Bewusst UNABHAENGIG vom Struktur-Zweig oben: updateBaerchis baut die Eier
	-- zwar mit, kann aber wegen einer laufenden Bewegung verschoben worden sein
	-- (ActivityLock). Genau dann legt der Baerchi aber weiter — und ein frisch
	-- gelegtes Ei soll nicht darauf warten, dass er ankommt.
	if previous.eggs ~= current.eggs then
		MapService.updateLaidEggs(player, data.island)
	end

	if previous.recycler ~= current.recycler then
		MapService.updateRecycler(player, data.island)
	end

	if previous.incubator ~= current.incubator then
		MapService.updateIncubator(player, data.island, IncubatorRules.slotCountFor(data))
	end

	-- v15: neuer Look -> genau dieses Gebaeude neu bauen (mit Show). Nach einem
	-- Rebirth faellt der Look zurueck; rebuildIsland hat die Insel dann schon
	-- komplett neu gebaut, updateBuildingLooks findet nichts mehr zu tun.
	if previous.looks ~= current.looks then
		MapService.updateBuildingLooks(player, data.island, true)
	end

	if previous.terminal ~= current.terminal then
		MapService.updateTerminal(player, terminalView(data))
	end

	if previous.tower ~= current.tower then
		local oldTower = string.match(previous.tower, "^([^:]+):")
		local newTower = string.match(current.tower, "^([^:]+):")
		applyTower(player, current.tower, oldTower ~= newTower)
	end

	_signatures[player] = current
end

function PlotDisplayService.init()
	-- MapService darf PlayerService nicht requiren (PlayerService requiret
	-- bereits MapService — das waere ein Ringschluss). Deshalb bekommt es die
	-- Lesefunktion von hier: dieser Service kennt beide ohnehin schon.
	MapService.setIslandDataProvider(function(player: Player): Types.IslandData?
		local data = PlayerService.getData(player)
		return if data then data.island else nil
	end)
	-- Sammel-Update Paket 8: Platz-Zahl des Inkubators (Level, Rebirths, Index).
	MapService.setIncubatorSlotProvider(function(player: Player): number
		local data = PlayerService.getData(player)
		return if data then IncubatorRules.slotCountFor(data) else 1
	end)

	PlayerService.onPlayerReady(function(player, data)
		-- Die Figuren und Schilder stehen zu diesem Zeitpunkt schon
		-- (MapService.spawnIsland laeuft beim Join davor), aber die Daten
		-- haben sich seitdem noch geaendert: die onDataLoaded-Callbacks haben
		-- Offline-Honig gutgeschrieben und offline gelegte Eier eingetragen.
		-- Die Schilder zeigten sonst bis zum naechsten Honig-Tick den Stand von
		-- vor der Gutschrift, und die Eier laegen nur in den Daten.
		--
		-- Deshalb einmal aktiv nachziehen — und ERST DANN die Signatur
		-- merken, sonst haelt der Vergleich unten den Unterschied faelschlich
		-- fuer bereits dargestellt.
		MapService.updateBuildingSigns(player, data.island)
		MapService.updateBaerchiStates(player, data.island)
		MapService.updateLaidEggs(player, data.island)
		MapService.updateRecycler(player, data.island)
		MapService.updateIncubator(player, data.island, IncubatorRules.slotCountFor(data))

		local signatures = allSignatures(data)
		applyTower(player, signatures.tower, false)
		MapService.updateTerminal(player, terminalView(data))

		_signatures[player] = signatures
	end)

	PlayerService.onDataChanged(refresh)

	Players.PlayerRemoving:Connect(function(player)
		_signatures[player] = nil
	end)

	print("[PlotDisplayService] Initialisiert")
end

return PlotDisplayService
