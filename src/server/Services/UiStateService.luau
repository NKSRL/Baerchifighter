--!strict
-- UiStateService.luau
-- ServerScriptService/Services/UiStateService.luau
--
-- Einzige Zustaendigkeit:
--   - Den Anzeigestand speichern: welche Bedienelemente der Spieler schon
--     gesehen hat (data.uiSeen)
--
-- Kontext: HBB Paket 3 (progressive Freischaltung). Neue Elemente bekommen
-- im Client ein "!"-Badge, bis der Spieler sie gesehen hat. Das ist rein
-- kosmetisch: dieser Service sperrt nichts, und kein anderer Wert im
-- Spielstand haengt an uiSeen.
--
-- Beim ersten Laden eines Stands mit leerem uiSeen:
--   * Stand mit Fortschritt (Veteran): alles, was laut UnlockRules gerade
--     sichtbar ist, gilt als gesehen — keine Badge-Flut nach dem Update.
--   * frisches Konto: nur die immer sichtbaren Grundelemente.
-- Danach ist uiSeen nie wieder leer, die Saat laeuft also genau einmal.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes     = require(ReplicatedStorage.Network.Remotes)
local UnlockRules = require(ReplicatedStorage.Modules.UnlockRules)

local PlayerService = require(ServerScriptService.Services.PlayerService)
local RateLimiter   = require(ServerScriptService.Util.RateLimiter)

local UiStateService = {}

-- Mehr Ids pro Aufruf nimmt der Server nicht an (Spam-Schutz)
local MAX_IDS_PER_CALL = 16

local VALID: { [string]: boolean } = {}
for _, id in UnlockRules.ELEMENTS do
	VALID[id] = true
end

local function seed(data: any)
	if next(data.uiSeen) ~= nil then return end
	if UnlockRules.hasProgress(data) then
		for id, visible in UnlockRules.visible(data) do
			if visible then data.uiSeen[id] = true end
		end
	else
		for id in UnlockRules.ALWAYS do
			data.uiSeen[id] = true
		end
	end
end

local function onMarkSeen(player: Player, ids: any)
	local data = PlayerService.getData(player)
	if not data then return end

	local list: { any } = if typeof(ids) == "table" then ids else { ids }
	local changed = false
	for index, id in list do
		if index > MAX_IDS_PER_CALL then break end
		if typeof(id) == "string" and VALID[id] and not data.uiSeen[id] then
			data.uiSeen[id] = true
			changed = true
		end
	end
	if changed then
		PlayerService.markDirty(player)
	end
end

function UiStateService.init()
	RateLimiter.connect(Remotes.RequestMarkUiSeen, "RequestMarkUiSeen", onMarkSeen)

	-- onDataLoaded darf den Stand noch aendern (vor dem ersten Client-Sync)
	PlayerService.onDataLoaded(function(_player, data)
		seed(data)
	end)
end

return UiStateService
