--!strict
-- EggTreeService.luau
-- ServerScriptService/Services/EggTreeService.luau
--
-- Einzige Zustaendigkeit (v14, Mega Egg Tree):
--   - Knoten des Ei-Baums freischalten, sobald ihre Bedingungen erfuellt sind
--     (und dem Spieler davon erzaehlen)
--   - Die Ei-Presse: 5 gleiche Eier -> 1 Ei der naechsten Stufe im Pfad
--   - Blaupausen einsetzen (aus Events)
--
-- Was "erfuellt" heisst, rechnet ausschliesslich Modules/EggTree — dieselbe
-- Funktion, mit der das Ei-Baum-Panel im Client die Fortschrittsbalken malt.
--
-- ============================================================
-- WANN GEPRUEFT WIRD
-- ============================================================
-- Bei JEDER Datenaenderung (PlayerService.onDataChanged), genau wie
-- QuestService den Index nachzieht. Die Bedingungen haengen an drei Dingen:
-- Hatch-Zaehlern (EggService), dem Index (QuestService traegt ihn nach) und
-- dem Rebirth-Zaehler (RebirthService). Alle drei rufen ohnehin markDirty —
-- ein eigener Aufruf an jeder Stelle waere die naechste Stelle, die man
-- vergisst. Ein Durchlauf kostet 20 kleine Pruefungen, das ist nichts.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types     = require(ReplicatedStorage.Network.Types)
local Remotes   = require(ReplicatedStorage.Network.Remotes)
local Loc       = require(ReplicatedStorage.Localization.Loc)
local EggConfig = require(ReplicatedStorage.Config.EggConfig)
local EggTree   = require(ReplicatedStorage.Modules.EggTree)

local PlayerService = require(ServerScriptService.Services.PlayerService)
local RateLimiter   = require(ServerScriptService.Util.RateLimiter)

local EggTreeService = {}

local function fail(player: Player, action: string, reason: Types.LocMsg)
	Remotes.ActionFailed:FireClient(player, action, reason)
end

local function announce(player: Player, eggs: { Types.EggType }, reason: string)
	for _, eggType in eggs do
		local result: Types.EggUnlockResult = { eggType = eggType, reason = reason }
		Remotes.EggTreeUnlocked:FireClient(player, result)
		print("[EggTreeService]", player.Name, "| Knoten frei:", eggType, "(" .. reason .. ")")
	end
end

-- Prueft den Baum und meldet neue Knoten. Gibt die neuen Eier zurueck. Ruft
-- KEIN markDirty (laeuft auch aus onDataChanged heraus).
function EggTreeService.check(player: Player, data: Types.PlayerData, reason: string?): { Types.EggType }
	local newly = EggTree.evaluate(data)
	if #newly > 0 then
		announce(player, newly, reason or "tree")
	end
	return newly
end

-- Schaltet einen Knoten direkt frei (Rebirth-Meilenstein "schaltet das Ei
-- frei", Debug). Gibt true zurueck, wenn er vorher gesperrt war.
function EggTreeService.forceUnlock(player: Player, data: Types.PlayerData, eggType: Types.EggType, reason: string): boolean
	if not EggConfig.data[eggType] or data.eggTree.unlocked[eggType] then
		return false
	end
	data.eggTree.unlocked[eggType] = true
	announce(player, { eggType }, reason)
	return true
end

-- Eine Blaupause gutschreiben (Events, siehe WP10).
function EggTreeService.grantBlueprint(player: Player, data: Types.PlayerData, amount: number)
	data.eggTree.blueprints = math.max(0, (data.eggTree.blueprints or 0) + math.floor(amount))
	print("[EggTreeService]", player.Name, "| Blaupause +", amount, "=", data.eggTree.blueprints)
end

--------------------------------------------------------------------------------
-- Ei-Presse
--------------------------------------------------------------------------------

function EggTreeService.press(player: Player, eggType: Types.EggType, path: Types.PathId?): Types.EggPressResult?
	local data = PlayerService.getData(player)
	if not data then return nil end

	local egg = EggConfig.data[eggType]
	if not egg then
		fail(player, "RequestPressEggs", Loc.msg("err.egg_unknown_type"))
		return nil
	end

	if not EggConfig.canPress(eggType) then
		fail(player, "RequestPressEggs", Loc.msg("err.press_blocked"))
		return nil
	end

	local target = EggConfig.getNextInPath(eggType, path)
	if not target then
		fail(player, "RequestPressEggs", Loc.msg("err.press_no_next"))
		return nil
	end

	if not EggTree.isUnlocked(data.eggTree, target) then
		fail(player, "RequestPressEggs", Loc.msg("err.press_target_locked", { egg = Loc.msg("egg." .. target .. ".name") }))
		return nil
	end

	local cost  = EggConfig.PRESS.cost
	local stock = data.island.eggStock[eggType] or 0
	if stock < cost then
		fail(player, "RequestPressEggs", Loc.msg("err.press_not_enough", {
			n = cost, egg = Loc.msg("egg." .. eggType .. ".name"), have = stock,
		}))
		return nil
	end

	data.island.eggStock[eggType] = stock - cost
	data.island.eggStock[target]  = (data.island.eggStock[target] or 0) + 1
	data.eggTree.pressed[target]  = (data.eggTree.pressed[target] or 0) + 1

	local result: Types.EggPressResult = { fromEgg = eggType, toEgg = target, used = cost }
	Remotes.EggPressResultReceived:FireClient(player, result)
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)

	print("[EggTreeService]", player.Name, "| Presse:", cost, "x", eggType, "->", target)
	return result
end

--------------------------------------------------------------------------------
-- Blaupause einsetzen
--------------------------------------------------------------------------------

function EggTreeService.useBlueprint(player: Player, eggType: Types.EggType): boolean
	local data = PlayerService.getData(player)
	if not data then return false end

	if not EggTree.canUseBlueprint(data, eggType) then
		fail(player, "RequestUseBlueprint", Loc.msg("err.blueprint_not_here"))
		return false
	end

	data.eggTree.blueprints -= 1
	data.eggTree.bypass[eggType] = true

	-- Ist das Rebirth-Gate schon erfuellt, wird der Knoten sofort frei;
	-- sonst bleibt nur noch der Rebirth uebrig (Panel zeigt das an).
	local newly = EggTree.evaluate(data)
	announce(player, newly, "blueprint")

	PlayerService.markDirty(player)
	PlayerService.saveNow(player)
	return true
end

--------------------------------------------------------------------------------
-- Initialisierung
--------------------------------------------------------------------------------

function EggTreeService.init()
	PlayerService.onDataChanged(function(player, data)
		if not data.eggTree then return end
		local newly = EggTreeService.check(player, data, "tree")
		if #newly > 0 then
			-- Nicht direkt markDirty (wir laufen gerade in einem). Der zweite
			-- Durchlauf findet nichts Neues mehr und endet.
			task.defer(function()
				if player.Parent and PlayerService.getData(player) == data then
					PlayerService.markDirty(player)
					PlayerService.saveNow(player)
				end
			end)
		end
	end)

	RateLimiter.connect(Remotes.RequestPressEggs, "RequestPressEggs", function(player, eggType: any, path: any)
		if typeof(eggType) ~= "string" or not EggConfig.data[eggType :: Types.EggType] then return end
		local wantedPath: Types.PathId? = nil
		if typeof(path) == "string" and (path == "Gold" or path == "Kristall" or path == "Void"
			or path == "Kosmos" or path == "Stamm")
		then
			wantedPath = path :: Types.PathId
		end
		EggTreeService.press(player, eggType :: Types.EggType, wantedPath)
	end)

	RateLimiter.connect(Remotes.RequestUseBlueprint, "RequestUseBlueprint", function(player, eggType: any)
		if typeof(eggType) ~= "string" or not EggConfig.data[eggType :: Types.EggType] then return end
		EggTreeService.useBlueprint(player, eggType :: Types.EggType)
	end)

	print("[EggTreeService] Initialisiert |", #EggConfig.getOrderedIds(), "Eier im Baum")
end

return EggTreeService
