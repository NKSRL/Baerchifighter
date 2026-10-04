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

local Types = require(ReplicatedStorage.Network.Types)

local PlayerService = require(ServerScriptService.Services.PlayerService)
local MapService    = require(ServerScriptService.Services.MapService)

local PlotDisplayService = {}

type Signatures = {
	structure : string,
	state     : string,
	buildings : string,
	eggs      : string,
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

local function allSignatures(data: Types.PlayerData): Signatures
	return {
		structure = structureSignature(data),
		state     = stateSignature(data),
		buildings = buildingSignature(data),
		eggs      = eggSignature(data),
	}
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

		_signatures[player] = allSignatures(data)
	end)

	PlayerService.onDataChanged(refresh)

	Players.PlayerRemoving:Connect(function(player)
		_signatures[player] = nil
	end)

	print("[PlotDisplayService] Initialisiert")
end

return PlotDisplayService
