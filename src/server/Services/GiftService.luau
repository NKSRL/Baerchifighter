--!strict
-- GiftService.luau
-- ServerScriptService/Services/GiftService.luau
--
-- Einzige Zustaendigkeit:
--   - Eier verschenken: ein Admin (nur ueber den Studio-Debug-Befehl "gift")
--     legt ein Geschenk in eine DataStore-Warteschlange; der Empfaenger bekommt
--     es beim Laden und danach alle POLL_SECONDS, solange er im Spiel ist.
--
-- Kontext: kein Remote, kein Chat-Befehl, kein Client-Zugriff. enqueue() wird
-- nur von DebugService aufgerufen (laeuft nur im Studio). Das Abholen ist
-- atomar (UpdateAsync leert die Liste), also kommt nichts doppelt an, auch
-- wenn mehrere Server laufen. Eier landen in data.island.eggStock.

local DataStoreService    = game:GetService("DataStoreService")
local Players             = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")

local EggConfig     = require(ReplicatedStorage.Config.EggConfig)
local PlayerService = require(ServerScriptService.Services.PlayerService)

local STORE_NAME   = "EggGifts_v2"
local POLL_SECONDS = 30
local MAX_PER_GIFT = 100
local CRYSTAL_KEY  = "HoneyCrystal" -- Geschenk-Typ fuer Honey Crystals (goldGummies)
local MAX_CRYSTALS = 1000000

local GiftService = {}

type Gift = { egg: string, count: number, at: number }

local store: DataStore? = nil
local claiming: { [number]: boolean } = {}

local function getStore(): DataStore?
	if store then return store end
	local ok, result = pcall(function() return DataStoreService:GetDataStore(STORE_NAME) end)
	if ok then store = result end
	return store
end

-- Geschenk in die Warteschlange legen. Gibt (ok, Text) zurueck.
function GiftService.enqueue(userId: number, eggType: string, count: number): (boolean, string)
	if type(userId) ~= "number" or userId <= 0 or userId % 1 ~= 0 then return false, "Ungueltige UserId" end
	local isCrystal = eggType == CRYSTAL_KEY
	if not isCrystal and not EggConfig.data[eggType :: any] then return false, "Unbekannter Egg-Typ: " .. tostring(eggType) end
	local amount = math.clamp(math.floor(count), 1, if isCrystal then MAX_CRYSTALS else MAX_PER_GIFT)
	local ds = getStore()
	if not ds then return false, "DataStore nicht verfuegbar" end   -- ui-ok: Rueckmeldung nur fuer den Debug-Befehl
	local ok, err = pcall(function()
		ds:UpdateAsync(tostring(userId), function(old: any)
			local list: { Gift } = if type(old) == "table" then old else {}
			table.insert(list, { egg = eggType, count = amount, at = os.time() })
			return list
		end)
	end)
	if not ok then return false, "Speichern fehlgeschlagen: " .. tostring(err) end
	return true, string.format("%dx %s fuer %d vorgemerkt", amount, eggType, userId)   -- ui-ok: Rueckmeldung nur fuer den Debug-Befehl
end

-- Abholen und gutschreiben. Spielstand muss geladen sein, sonst bleibt alles liegen.
local function claim(player: Player)
	if claiming[player.UserId] then return end
	local data = PlayerService.getData(player)
	local ds = getStore()
	if not (data and ds) then return end
	claiming[player.UserId] = true

	local taken: { Gift }? = nil
	local ok = pcall(function()
		ds:UpdateAsync(tostring(player.UserId), function(old: any)
			if type(old) == "table" and #old > 0 then
				taken = old
				return {}
			end
			return nil -- nichts zu tun, nicht schreiben
		end)
	end)
	claiming[player.UserId] = nil
	if not ok or not taken then return end
	local gifts = taken :: { Gift }

	-- Spieler koennte waehrenddessen gegangen sein: dann Geschenke zurueck in die Warteschlange
	local current = PlayerService.getData(player)
	if not (current and player.Parent) then
		pcall(function()
			ds:UpdateAsync(tostring(player.UserId), function(old: any)
				local list: { Gift } = if type(old) == "table" then old else {}
				for _, gift in gifts do table.insert(list, gift) end
				return list
			end)
		end)
		return
	end
	for _, gift in gifts do
		if gift.egg == CRYSTAL_KEY then
			current.goldGummies = (current.goldGummies or 0) + math.clamp(gift.count, 1, MAX_CRYSTALS)
		else
			local egg = gift.egg :: any
			if EggConfig.data[egg] then
				current.island.eggStock[egg] = (current.island.eggStock[egg] or 0) + math.clamp(gift.count, 1, MAX_PER_GIFT)
			end
		end
	end
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)
	print(string.format("[GiftService] %d Geschenk(e) an %s ausgeliefert", #gifts, player.Name))
end

function GiftService.init()
	PlayerService.onPlayerReady(function(player: Player) task.spawn(claim, player) end)
end

function GiftService.start()
	task.spawn(function()
		while true do
			task.wait(POLL_SECONDS)
			for _, player in Players:GetPlayers() do task.spawn(claim, player) end
		end
	end)
end

return GiftService
