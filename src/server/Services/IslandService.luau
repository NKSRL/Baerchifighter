--!strict
-- IslandService.luau
-- ServerScriptService/Services/IslandService.luau
--
-- Einzige Zustaendigkeit:
--   - Insel-Struktur veraendern: Gebaeude-Level, PIT-Level und welcher
--     Baerchi ausgeruestet ist
--   - Die zugehoerigen Client-Requests entgegennehmen und validieren
--   - Nach einer Aenderung die sichtbare Insel via MapService nachziehen
--
-- Die Waehrungs-Transaktion selbst liegt in EconomyService — dieser Service
-- entscheidet nur WAS gekauft wird und was danach in der Welt passieren muss.
--
-- Equip-Baerchi gehoert hier rein statt in einen eigenen Service: es ist
-- genau wie die Gebaeude- und PIT-Upgrades eine Aenderung an der
-- Insel-STRUKTUR (welcher Baerchi ueberhaupt in der Welt steht), keine neue
-- Zustaendigkeit fuer sich.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types         = require(ReplicatedStorage.Network.Types)
local Remotes       = require(ReplicatedStorage.Network.Remotes)
local Loc           = require(ReplicatedStorage.Localization.Loc)
local EconomyConfig = require(ReplicatedStorage.Config.EconomyConfig)

local PlayerService  = require(ServerScriptService.Services.PlayerService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local MapService     = require(ServerScriptService.Services.MapService)
local ActivityLock   = require(ServerScriptService.Util.ActivityLock)
local RateLimiter    = require(ServerScriptService.Util.RateLimiter)

local IslandService = {}

-- Gueltige BuildingIds als Menge — Client-Strings duerfen nie ungeprueft
-- als Types.BuildingId weiterverwendet werden.
local VALID_BUILDINGS: { [string]: boolean } = {
	Beehive    = true,
	HoneyPot   = true,
	HoneyPress = true,
}

local function fail(player: Player, action: string, reason: Types.LocMsg?)
	Remotes.ActionFailed:FireClient(player, action, reason or Loc.msg("err.unknown"))
end

--------------------------------------------------------------------------------
-- Gebaeude-Upgrade
--------------------------------------------------------------------------------

function IslandService.upgradeBuilding(player: Player, buildingId: Types.BuildingId)
	local data = PlayerService.getData(player)
	if not data then return end

	local ok, reason = EconomyService.upgradeBuilding(player, buildingId)
	if not ok then
		fail(player, "RequestUpgradeBuilding", reason)
		return
	end

	local newLevel = data.island.buildings[buildingId].level

	-- Level-Attribut an der Gebaeude-Part nachziehen (Client liest es direkt)
	MapService.updateBuildingLevel(player, buildingId, newLevel)
	PlayerService.saveNow(player)

	print("[IslandService]", player.Name, "| Gebaeude:", buildingId, "→ Level", newLevel)
end

--------------------------------------------------------------------------------
-- PIT-Level-Kauf
--------------------------------------------------------------------------------

function IslandService.upgradePit(player: Player)
	local ok, reason, newLevel = EconomyService.upgradePit(player)
	if not ok then
		fail(player, "RequestUpgradePit", reason)
		return
	end

	-- Plattform sichtbar hochziehen
	MapService.updatePitLevel(player, newLevel)
	PlayerService.saveNow(player)

	print("[IslandService]", player.Name, "| PIT-Level →", newLevel,
		"| Kosten:", EconomyConfig.getPitUpgradeCost(newLevel))
end

--------------------------------------------------------------------------------
-- Baerchi ausruesten
--------------------------------------------------------------------------------

-- Setzt automatisch einen ausgeruesteten Baerchi, falls gerade keiner steht
-- aber welche im Inventar sind. Oeffentlich, weil EggService (erster Hatch,
-- damit der Plot nicht leer bleibt) und RecycleService (der ausgeruestete
-- wird verwertet) das brauchen — und weil es hier beim Laden jedes
-- Spielstands als Sicherheitsnetz laeuft (siehe init unten).
--
-- Reine Datenfunktion ohne Remote-Antwort: der Aufrufer entscheidet selbst,
-- ob danach ein MapService.updateBaerchis noetig ist.
function IslandService.autoEquipIfNone(data: Types.PlayerData)
	local island = data.island

	if island.equippedUid and island.baerchis[island.equippedUid] then
		return   -- schon einer da, und der existiert auch wirklich
	end

	-- Deterministisch nach uid statt "irgendeiner": sonst wuerde bei jedem
	-- Aufruf ein anderer Baerchi gewinnen, weil die Iteration ueber eine
	-- Hash-Tabelle nicht stabil ist.
	local bestUid: string? = nil
	for uid in island.baerchis do
		if not bestUid or uid < bestUid then
			bestUid = uid
		end
	end

	island.equippedUid = bestUid
end

function IslandService.equipBaerchi(player: Player, baerchiUid: string)
	local data = PlayerService.getData(player)
	if not data then return end

	if not data.island.baerchis[baerchiUid] then
		fail(player, "RequestEquipBaerchi", Loc.msg("err.baerchi_not_found"))
		return
	end

	if data.island.equippedUid == baerchiUid then
		return   -- schon ausgeruestet, nichts zu tun
	end

	-- Ein Equip-Wechsel ersetzt die Figur, die JETZT auf dem Plot steht. Steckt
	-- genau die gerade in einer Bewegung (Kampf-Lauf oder Weg zum Honig-Teich,
	-- beides haelt ActivityLock), wuerde sie mitten im Schritt verschwinden.
	--
	-- Anders als beim Verwerten haengt das nicht an der uebergebenen uid: der
	-- neue Baerchi ist nie der beschaeftigte — der ALTE ist es. Deshalb hier
	-- kein uid-Vergleich, sondern nur die Frage, ob ueberhaupt gerade eine
	-- Bewegung laeuft. Ohne ausgeruesteten Baerchi laeuft auch keine, das
	-- Schloss ist dann frei und der erste Equip geht wie bisher sofort durch.
	if not ActivityLock.isFree(player) then
		fail(player, "RequestEquipBaerchi", Loc.msg("err.baerchi_busy"))
		return
	end

	data.island.equippedUid = baerchiUid

	-- Struktur-Aenderung (es steht jetzt eine ANDERE Figur auf dem Plot),
	-- kein reiner Zustandswert — deshalb der teurere Neuaufbau.
	MapService.updateBaerchis(player, data.island)
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)

	print("[IslandService]", player.Name, "| ausgeruestet:", baerchiUid)
end

--------------------------------------------------------------------------------
-- Initialisierung
--------------------------------------------------------------------------------

function IslandService.init()
	RateLimiter.connect(Remotes.RequestUpgradeBuilding, "RequestUpgradeBuilding", function(player, buildingId: any)
		if typeof(buildingId) ~= "string" then return end
		if not VALID_BUILDINGS[buildingId] then
			fail(player, "RequestUpgradeBuilding", Loc.msg("err.building_unknown"))
			return
		end
		IslandService.upgradeBuilding(player, buildingId :: Types.BuildingId)
	end)

	RateLimiter.connect(Remotes.RequestUpgradePit, "RequestUpgradePit", function(player)
		IslandService.upgradePit(player)
	end)

	RateLimiter.connect(Remotes.RequestEquipBaerchi, "RequestEquipBaerchi", function(player, baerchiUid: any)
		if typeof(baerchiUid) ~= "string" then return end
		IslandService.equipBaerchi(player, baerchiUid)
	end)

	-- Sicherheitsnetz: ein alter Spielstand ohne equippedUid (oder einer
	-- dessen ausgeruesteter Baerchi inzwischen weg ist) bekommt beim Laden
	-- automatisch den naechstbesten. Muss vor PlayerService.init() stehen —
	-- siehe PlayerService.onDataLoaded.
	PlayerService.onDataLoaded(function(_player, data)
		IslandService.autoEquipIfNone(data)
	end)

	print("[IslandService] Initialisiert")
end

return IslandService
