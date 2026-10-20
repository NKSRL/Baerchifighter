--!strict
-- PetSellService.luau
-- ServerScriptService/Services/PetSellService.luau
--
-- Einzige Zustaendigkeit:
--   - Der Verkaufsmodus (PET_SELL_MODE_V1): mehrere Baerchis auf Wunsch des
--     Spielers ENDGUELTIG loeschen
--
-- Anders als das Verwerten (RecycleService, ein Baerchi, zahlt Gummies) gibt es
-- hier standardmaessig KEINEN Erloes: Verkaufen loescht nur. Der Haken
-- PetLimitConfig.SELL_PAYOUT_PER_RARITY ist vorbereitet (heute ueberall 0).
--
-- SICHERHEIT: der Client schickt nur eine Liste von uids. Der Server prueft
-- ALLES neu (Typen, Groesse, Duplikate, Besitz, ausgeruestet, Inkubator) und
-- arbeitet ALLES-ODER-NICHTS: eine ungueltige uid lehnt die ganze Anfrage ab, es
-- wird nie nur ein Teil geloescht. Der Index bleibt unberuehrt (data.discovered).
--
-- Ablauf ohne Unterbrechung zwischen Pruefen und Loeschen (kein Yield), dann ein
-- einziges Speichern, dann erst die Rueckmeldung an den Client.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types          = require(ReplicatedStorage.Network.Types)
local Remotes        = require(ReplicatedStorage.Network.Remotes)
local Loc            = require(ReplicatedStorage.Localization.Loc)
local FeatureFlags   = require(ReplicatedStorage.Config.FeatureFlags)
local PetLimitConfig = require(ReplicatedStorage.Config.PetLimitConfig)
local PetSellRules   = require(ReplicatedStorage.Modules.PetSellRules)

local PlayerService  = require(ServerScriptService.Services.PlayerService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local RateLimiter    = require(ServerScriptService.Util.RateLimiter)

local PetSellService = {}

local ACTION = "RequestSellBaerchis"
local MAX_UID_LENGTH = 64   -- Schutz vor absurd langen Strings aus dem Client

local function fail(player: Player, reason: Types.LocMsg)
	Remotes.ActionFailed:FireClient(player, ACTION, reason)
end

-- Macht aus dem rohen Client-Argument eine saubere uid-Liste, oder nil + Grund.
-- Erlaubt ist genau ein Array aus Strings ohne Duplikate.
local function parseUids(raw: any): ({ string }?, string?)
	if typeof(raw) ~= "table" then return nil, "err.sell_invalid" end

	local count = 0
	for _ in raw do count += 1 end
	if count == 0 then return nil, "err.sell_invalid" end
	if count > PetLimitConfig.SELL_MAX_PER_REQUEST then return nil, "err.sell_too_many" end
	-- Nur ein echtes Array (1..count lueckenlos), keine Schluessel-Tabelle.
	if #(raw :: { any }) ~= count then return nil, "err.sell_invalid" end

	local seen: { [string]: boolean } = {}
	local uids: { string } = {}
	for i = 1, count do
		local uid = (raw :: { any })[i]
		if typeof(uid) ~= "string" or #uid == 0 or #uid > MAX_UID_LENGTH then
			return nil, "err.sell_invalid"
		end
		if seen[uid] then return nil, "err.sell_invalid" end
		seen[uid] = true
		table.insert(uids, uid)
	end
	return uids, nil
end

function PetSellService.sell(player: Player, raw: any): number
	if not FeatureFlags.isOn("PET_SELL_MODE_V1") then
		fail(player, Loc.msg("err.sell_disabled"))
		return 0
	end

	local data = PlayerService.getData(player)
	if not data then return 0 end

	local uids, parseError = parseUids(raw)
	if not uids then
		fail(player, Loc.msg(parseError or "err.sell_invalid"))
		return 0
	end

	-- Alles pruefen, BEVOR irgendetwas geloescht wird.
	local payout = 0
	for _, uid in uids do
		local reason = PetSellRules.blockReason(data, uid)
		if reason then
			fail(player, Loc.msg(reason))
			return 0
		end
		payout += PetSellRules.payout(data.island.baerchis[uid].rarity)
	end

	-- Loeschen. Der Index (data.discovered) bleibt: entdeckt bleibt entdeckt.
	for _, uid in uids do
		data.island.baerchis[uid] = nil
	end

	if payout > 0 then
		EconomyService.awardGummiesFlat(player, payout)
	end

	PlayerService.markDirty(player)
	PlayerService.saveNow(player)

	Remotes.SellResultReceived:FireClient(player, { sold = #uids, soldUids = uids })

	print("[PetSellService]", player.Name, "| verkauft:", #uids, "| Erloes:", payout)
	return #uids
end

function PetSellService.init()
	RateLimiter.connect(Remotes.RequestSellBaerchis, ACTION, function(player, uids: any)
		PetSellService.sell(player, uids)
	end)

	print("[PetSellService] Initialisiert")
end

return PetSellService
