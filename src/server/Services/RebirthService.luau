--!strict
-- RebirthService.luau
-- ServerScriptService/Services/RebirthService.luau
--
-- Einzige Zustaendigkeit:
--   - Rebirth-Requests validieren und ausfuehren
--   - Insel zuruecksetzen, Multiplikator neu setzen, Meilenstein-Eier vergeben
--
-- Was ein Rebirth kostet und was er einbringt:
--   Kosten     : EconomyConfig.getRebirthCost(rebirthCount)  (Gummies)
--   Verloren   : alle Gebaeude-Level, PIT-Turm-Fortschritt, laufende Bruten,
--                Gummies (zurueck auf REBIRTH_START_GUMMIES),
--                Baerchi-LEVEL und -XP (siehe unten)
--   Behalten   : alle Baerchis SELBST (inkl. wer gerade ausgeruestet ist,
--                Rarity, Skill, Fusion-Bonus), GoldGummies, Rang,
--                Statistiken, bereits verdiente AscensionEggs
--   Gewonnen   : hoeherer rebirthMult + ggf. AscensionEggs
--                (EconomyConfig.REBIRTH_ASCENSION_MILESTONES)
--
-- GoldGummies bleiben bewusst erhalten: sie sind die "harte" Waehrung fuer
-- die spaeten Gebaeude-Level und wuerden sonst jeden Rebirth entwerten.
--
-- Baerchis bleiben seit v8 als SAMMLUNG erhalten (vorher: komplett geloescht)
-- — das Sammeln ist der eigentliche langfristige Fortschritt im Spiel
-- (Grow-a-...-Fighter-Prinzip), ein Rebirth soll die Gebaeude-Spirale
-- zuruecksetzen, nicht die Sammlung wegnehmen. Ihr LEVEL faellt aber
-- weiterhin auf 1 zurueck: Honig-Fuettern (die einzige XP-Quelle, siehe
-- HoneyService) ist an die Gebaeude gekoppelt, die der Rebirth ja gerade
-- zuruecksetzt — bliebe das Level stehen, waere ein Rebirth am Ende ein
-- reiner Gewinn ohne jeden Rueckschritt, und nicht mehr der bewusste
-- Neustart-Trade-off, den das Spiel damit anbieten soll.

local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types            = require(ReplicatedStorage.Network.Types)
local Remotes          = require(ReplicatedStorage.Network.Remotes)
local EconomyConfig    = require(ReplicatedStorage.Config.EconomyConfig)
local BaerchiConfig    = require(ReplicatedStorage.Config.BaerchiConfig)
local CombatCalculator = require(ReplicatedStorage.Modules.CombatCalculator)

local PlayerService  = require(ServerScriptService.Services.PlayerService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local MapService     = require(ServerScriptService.Services.MapService)
local RateLimiter    = require(ServerScriptService.Util.RateLimiter)

-- Feier-Farbe fuer einen Rebirth (siehe MapService.celebrateBaerchi) — Weiss,
-- fuer den "frischer Neustart"-Blitz statt einer Rarity- oder Rollen-Farbe.
local REBIRTH_CELEBRATE_COLOR = Color3.fromRGB(255, 255, 255)

local RebirthService = {}

local function fail(player: Player, reason: string)
	Remotes.ActionFailed:FireClient(player, "RequestRebirth", reason)
end

-- Setzt Level und XP eines Baerchis auf den Werkszustand zurueck und heilt
-- ihn dabei komplett — sonst stuende er nach dem Rebirth auf Level 1 mit den
-- (viel zu hohen) HP seines alten Levels da, oder umgekehrt erschoepft, wenn
-- die alten HP ueber der neuen, kleineren maxHp lagen.
--
-- Unbekannter configId (kaputter/veralteter Datensatz): Level/XP trotzdem
-- zuruecksetzen, HP aber unangetastet lassen — ohne Basiswerte laesst sich
-- keine maxHp berechnen, und ein Absturz hier wuerde den gesamten Rebirth
-- abbrechen, obwohl schon Gummies abgebucht sind.
local function resetBaerchiToLevelOne(baerchi: Types.Baerchi)
	baerchi.level = 1
	baerchi.xp    = 0

	local def = BaerchiConfig.getById(baerchi.configId)
	if not def then
		warn("[RebirthService] Unbekannter configId beim Rebirth-Reset:", baerchi.configId)
		return
	end

	local stats = CombatCalculator.getEffectiveStats(baerchi, def.baseStats)
	baerchi.currentHp = stats.maxHp
end

function RebirthService.rebirth(player: Player)
	local data = PlayerService.getData(player)
	if not data then return end

	local cost = EconomyConfig.getRebirthCost(data.rebirthCount)
	if data.gummies < cost then
		fail(player, "Rebirth kostet " .. cost .. " Gummies (du hast " .. data.gummies .. ")")
		return
	end

	-- Abbuchen bevor irgendetwas zurueckgesetzt wird
	local ok, reason = EconomyService.spendGummies(player, cost)
	if not ok then
		fail(player, reason)
		return
	end

	-- Bereits verdiente AscensionEggs ueberleben den Reset —
	-- sie sind Belohnung frueherer Rebirths, nicht Fortschritt dieses Laufs.
	local keptAscensionEggs = data.island.eggStock.AscensionEgg or 0

	-- Baerchis (und wer davon gerade ausgeruestet ist) ueberleben den Reset
	-- ebenfalls — siehe Kopf-Kommentar. `equippedUid` einfach mit
	-- durchreichen statt neu zuzuweisen: zeigt der ausgeruestete Baerchi noch
	-- auf einen Eintrag in `keptBaerchis`, bleibt er nach dem Rebirth
	-- weiterhin ausgeruestet, MapService.rebuildIsland baut seine Figur ganz
	-- normal wieder mit auf.
	local keptBaerchis    = data.island.baerchis
	local keptEquippedUid = data.island.equippedUid

	-- Level und XP fallen trotzdem zurueck auf den Anfang — siehe Kopf-
	-- Kommentar. Die Baerchis selbst (Rarity, Skill, Fusion-Bonus, ...)
	-- bleiben dabei unangetastet, nur Fortschritt UEBER Level 1 hinaus geht
	-- verloren.
	for _, baerchi in keptBaerchis do
		resetBaerchiToLevelOne(baerchi)
	end

	-- Insel auf Werkszustand
	local freshIsland = PlayerService.buildDefaultIsland()
	freshIsland.eggStock.AscensionEgg = keptAscensionEggs
	freshIsland.baerchis    = keptBaerchis
	freshIsland.equippedUid = keptEquippedUid
	data.island = freshIsland

	-- Progression hochzaehlen
	data.rebirthCount += 1
	data.rebirthMult   = EconomyConfig.getRebirthMult(data.rebirthCount)
	data.stats.totalRebirths += 1

	-- Ueber EconomyService statt eines direkten Feld-Schreibzugriffs — nur
	-- der darf Waehrungen anfassen, auch beim Zuruecksetzen auf einen Fixwert.
	EconomyService.resetGummies(player, EconomyConfig.REBIRTH_START_GUMMIES)

	-- Meilenstein-Belohnung
	local eggReward = EconomyConfig.getAscensionEggReward(data.rebirthCount)
	if eggReward > 0 then
		local stock = data.island.eggStock.AscensionEgg or 0
		data.island.eggStock.AscensionEgg = stock + eggReward
	end

	-- Sichtbare Insel neu aufbauen (Gebaeude auf Level 1, PIT wieder Level 1).
	-- rebuildIsland behaelt den Insel-Slot — der Spieler soll nach dem Rebirth
	-- nicht ploetzlich an einer anderen Stelle der Map stehen.
	MapService.rebuildIsland(player, data.island)

	-- Sichtbar feiern — NACH rebuildIsland, sonst existiert die Figur (mit
	-- ihrem frisch auf Level 1 zurueckgesetzten Stand) noch gar nicht in der
	-- Welt. Nur wenn ueberhaupt einer ausgeruestet ist: direkt nach dem ALLER-
	-- ersten Ei (vor dem ersten Rebirth ueberhaupt) waere keptEquippedUid nil.
	if keptEquippedUid then
		MapService.celebrateBaerchi(player, keptEquippedUid, REBIRTH_CELEBRATE_COLOR)
	end

	local result: Types.RebirthResult = {
		newRebirthCount = data.rebirthCount,
		newMultiplier   = data.rebirthMult,
		ascensionEggs   = eggReward,
	}

	Remotes.RebirthResultReceived:FireClient(player, result)
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)

	print(
		"[RebirthService]", player.Name,
		"| Rebirth #", data.rebirthCount,
		"| Kosten:", cost,
		"| neuer Multi:", data.rebirthMult,
		"| AscensionEggs:", eggReward
	)
end

function RebirthService.init()
	RateLimiter.connect(Remotes.RequestRebirth, "RequestRebirth", function(player)
		RebirthService.rebirth(player)
	end)

	print("[RebirthService] Initialisiert")
end

return RebirthService
