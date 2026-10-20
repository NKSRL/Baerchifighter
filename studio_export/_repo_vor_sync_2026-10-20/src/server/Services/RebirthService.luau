--!strict
-- RebirthService.luau
-- ServerScriptService/Services/RebirthService.luau
--
-- Einzige Zustaendigkeit:
--   - Rebirth-Requests validieren und ausfuehren
--   - Insel zuruecksetzen, Multiplikator neu setzen, Meilenstein-Eier vergeben
--
-- Was ein Rebirth kostet und was er einbringt:
--   Bedingung  : (Sammel-Update 05.10.) eine Tower-Stage in diesem Leben,
--                TowerConfig.getRebirthRequirement — KEINE Gummies mehr
--   Verloren   : alle Gebaeude-Level, der Fortsetzen-Stand der Tower,
--                Gummies (zurueck auf REBIRTH_START_GUMMIES),
--                Baerchi-LEVEL und -XP (siehe unten)
--   Behalten   : alle Baerchis SELBST (inkl. wer gerade ausgeruestet ist,
--                Rarity, Skill, Fusion-Bonus), GoldGummies, Rang,
--                Statistiken, der Ei-Baum (v14), Tower-Rekorde und
--                Meilensteine (v15) und ALLE Eier im Lager
--                (v14 — vorher nur die Ascensions-Eier; seit kein Ei mehr
--                kaufbar ist, waere jedes andere Ei ein echter Verlust).
--                Herumliegende Eier wandern beim Rebirth ins Lager.
--   Gewonnen   : hoeherer rebirthMult + ggf. Meilenstein-Eier
--                (EconomyConfig.REBIRTH_MILESTONES, v14: alle vier
--                Ascensions-Eier, teils mit Freischaltung im Ei-Baum)
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
local Loc           = require(ReplicatedStorage.Localization.Loc)
local EconomyConfig    = require(ReplicatedStorage.Config.EconomyConfig)
local TowerConfig      = require(ReplicatedStorage.Config.TowerConfig)   -- Paket 4.1: Rebirth nach Stage
local BaerchiConfig    = require(ReplicatedStorage.Config.BaerchiConfig)
local CombatCalculator = require(ReplicatedStorage.Modules.CombatCalculator)

local PlayerService  = require(ServerScriptService.Services.PlayerService)
local EconomyService = require(ServerScriptService.Services.EconomyService)
local MapService     = require(ServerScriptService.Services.MapService)
local RateLimiter    = require(ServerScriptService.Util.RateLimiter)
local EggTreeService = require(ServerScriptService.Services.EggTreeService)

-- Feier-Farbe fuer einen Rebirth (siehe MapService.celebrateBaerchi) — Weiss,
-- fuer den "frischer Neustart"-Blitz statt einer Rarity- oder Rollen-Farbe.
local REBIRTH_CELEBRATE_COLOR = Color3.fromRGB(255, 255, 255)

local RebirthService = {}

local function fail(player: Player, reason: Types.LocMsg?)
	Remotes.ActionFailed:FireClient(player, "RequestRebirth", reason or Loc.msg("err.unknown"))
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

	-- Sammel-Update 05.10. (Paket 4.1): kein Gummy-Preis mehr. Bedingung ist
	-- eine Tower-Stage, in DIESEM Leben geschafft (island.stageBest, siehe
	-- TowerConfig.getRebirthRequirement). Gummies verfallen beim Rebirth
	-- trotzdem (resetGummies unten) — wer vorher alles ausgibt, verliert nichts.
	if not TowerConfig.isRebirthReady(data.rebirthCount, data.island.stageBest, data.towers.records) then
		local towerId, stage = TowerConfig.getRebirthRequirement(data.rebirthCount, data.towers.records)
		local def = TowerConfig.get(towerId)
		fail(player, Loc.msg("err.rebirth_stage", {
			tower = if def then def.numeral else towerId,
			stage = stage,
			have  = (data.island.stageBest or {})[towerId] or 0,
		}))
		return
	end
	local cost = 0   -- nur noch fuer das Protokoll unten

	-- v14: ALLE Eier ueberleben den Reset (vorher nur Ascension). Seit kein
	-- Ei mehr kaufbar ist, waere jedes andere ein echter Verlust. Was noch
	-- auf dem Plot liegt, wandert mit ins Lager.
	local keptStock: { [Types.EggType]: number } = {}
	for eggType, count in data.island.eggStock do
		keptStock[eggType] = count
	end
	for _, egg in data.island.laidEggs do
		keptStock[egg.eggType] = (keptStock[egg.eggType] or 0) + 1
	end

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
	-- Die Start-Basis-Eier gibt es nur fuer neue Spieler, nicht pro Rebirth.
	freshIsland.eggStock = keptStock
	freshIsland.baerchis    = keptBaerchis
	freshIsland.equippedUid = keptEquippedUid
	-- Sammel-Update Paket 8: Eier im Inkubator bleiben (wie das Ei-Lager),
	-- das Ausbau-Level faellt zurueck (Geldsenke vor dem Rebirth). Plaetze
	-- ueber der neuen Platz-Zahl lassen sich noch abholen, aber nicht neu belegen.
	local oldIncubator = data.island.incubator
	if oldIncubator and freshIsland.incubator then
		freshIsland.incubator.slots = oldIncubator.slots
		-- INCUBATOR_BREED: die Baerchis bleiben sitzen (die Sammlung bleibt
		-- beim Rebirth); IncubatorService raeumt fehlende im naechsten Takt.
		freshIsland.incubator.breeders = oldIncubator.breeders or {}
	end
	data.island = freshIsland

	-- Progression hochzaehlen
	data.rebirthCount += 1
	data.rebirthMult   = EconomyConfig.getRebirthMult(data.rebirthCount)
	data.stats.totalRebirths += 1

	-- Ueber EconomyService statt eines direkten Feld-Schreibzugriffs — nur
	-- der darf Waehrungen anfassen, auch beim Zuruecksetzen auf einen Fixwert.
	EconomyService.resetGummies(player, EconomyConfig.REBIRTH_START_GUMMIES)

	-- Meilenstein-Belohnung (v14: alle vier Ascensions-Eier)
	local eggReward = 0
	local milestoneEggs: { { eggType: Types.EggType, count: number } } = {}
	local milestone = EconomyConfig.getRebirthMilestone(data.rebirthCount)
	if milestone then
		for _, entry in milestone.eggs do
			local stock = data.island.eggStock[entry.eggType] or 0
			data.island.eggStock[entry.eggType] = stock + entry.count
			eggReward += entry.count
			table.insert(milestoneEggs, { eggType = entry.eggType, count = entry.count })
		end
		for _, eggType in (milestone.unlock or {}) do
			EggTreeService.forceUnlock(player, data, eggType, "rebirth")
		end
	end
	-- Rebirth-Gates im Baum (Sonnen-Ei ab Rebirth 3 usw.)
	EggTreeService.check(player, data, "rebirth")

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
		milestoneEggs   = milestoneEggs,
	}

	Remotes.RebirthResultReceived:FireClient(player, result)
	PlayerService.markDirty(player)
	PlayerService.saveNow(player)

	print(
		"[RebirthService]", player.Name,
		"| Rebirth #", data.rebirthCount,
		"| Kosten:", cost,
		"| neuer Multi:", data.rebirthMult,
		"| Meilenstein-Eier:", eggReward
	)
end

function RebirthService.init()
	RateLimiter.connect(Remotes.RequestRebirth, "RequestRebirth", function(player)
		RebirthService.rebirth(player)
	end)

	print("[RebirthService] Initialisiert")
end

return RebirthService
