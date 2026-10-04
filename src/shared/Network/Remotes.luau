--!strict
-- Remotes.luau
-- ReplicatedStorage/Network/Remotes.luau
--
-- Alle RemoteEvents und RemoteFunctions als benannte Konstanten.
-- Kein Magic-String im gesamten Projekt.
-- Server und Client importieren von hier.
--
-- Konvention: der Feldname hier ist gleichzeitig der Schluessel in
-- NetworkConfig.REMOTE_COOLDOWNS — RateLimiter verlaesst sich darauf.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")

-- ============================================================
-- WARUM DIE FALLUNTERSCHEIDUNG SERVER/CLIENT
-- ============================================================
-- Nur der SERVER legt die Remotes an. Der Client wartet ausschliesslich
-- darauf, dass sie repliziert werden.
--
-- Ohne diese Trennung koennte ein Client-Skript, das laeuft bevor der Ordner
-- bei ihm angekommen ist, sich selbst einen EIGENEN "RemoteFolder" mit
-- eigenen, rein lokalen RemoteEvents bauen. Die kommen nie beim Server an
-- und der Server erreicht sie nie — das Spiel saehe vollstaendig normal aus
-- und wuerde einfach gar nichts tun, ohne eine einzige Fehlermeldung. Das ist
-- eine der unangenehmsten Fehlerarten ueberhaupt, deshalb hier explizit.
local IS_SERVER = RunService:IsServer()

local folder: Instance
if IS_SERVER then
	local existing = ReplicatedStorage:FindFirstChild("RemoteFolder")
	if existing then
		folder = existing
	else
		local created = Instance.new("Folder")
		created.Name   = "RemoteFolder"
		created.Parent = ReplicatedStorage
		folder = created
	end
else
	folder = ReplicatedStorage:WaitForChild("RemoteFolder")
end

local function getOrCreateEvent(name: string): RemoteEvent
	if not IS_SERVER then
		return folder:WaitForChild(name) :: RemoteEvent
	end

	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("RemoteEvent") then
		return existing
	end
	local remote  = Instance.new("RemoteEvent")
	remote.Name   = name
	remote.Parent = folder
	return remote
end

local function getOrCreateFunction(name: string): RemoteFunction
	if not IS_SERVER then
		return folder:WaitForChild(name) :: RemoteFunction
	end

	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA("RemoteFunction") then
		return existing
	end
	local remote  = Instance.new("RemoteFunction")
	remote.Name   = name
	remote.Parent = folder
	return remote
end

-- ============================================================
-- Server → Client Events
-- ============================================================

-- Wird nach jeder Zustandsaenderung gefeuert
-- Args: PlayerDataUpdate
local PlayerDataUpdated = getOrCreateEvent("PlayerDataUpdated")

-- Kampfergebnis anzeigen (Animation auf Client)
-- Args: CombatResult
local CombatResultReceived = getOrCreateEvent("CombatResultReceived")

-- Hatch-Ergebnis anzeigen (Gacha-Animation auf Client)
-- Args: HatchResult
local HatchResultReceived = getOrCreateEvent("HatchResultReceived")

-- Fusions-Ergebnis anzeigen
-- Args: FusionResult
local FusionResultReceived = getOrCreateEvent("FusionResultReceived")

-- Recycling-Ergebnis anzeigen
-- Args: RecycleResult
local RecycleResultReceived = getOrCreateEvent("RecycleResultReceived")

-- Rebirth durchgefuehrt
-- Args: RebirthResult
local RebirthResultReceived = getOrCreateEvent("RebirthResultReceived")

-- Offline-Ertrag beim Join
-- Args: OfflineReport
local OfflineReportReceived = getOrCreateEvent("OfflineReportReceived")

-- Ein Honig wurde verfuettert: Heilung, XP und ggf. Level-Up
-- Args: FeedResult
local FeedResultReceived = getOrCreateEvent("FeedResultReceived")

-- Ein Baerchi wurde befoerdert
-- Args: PromotionResult
local PromotionResultReceived = getOrCreateEvent("PromotionResultReceived")

-- Charms wurden neu gewuerfelt (ein Wurf oder ein Auto-Roll-Paket)
-- Args: CharmRollResult
local CharmRollResultReceived = getOrCreateEvent("CharmRollResultReceived")

-- Ein Stat-Level ist durch Event-Teilnahme gestiegen
-- Args: EventStatGain
local EventStatGained = getOrCreateEvent("EventStatGained")

-- Der ausgeruestete Baerchi ist am Event angekommen bzw. wieder zuhause.
-- Reiner Anzeige-Zustand fuer den "Zum Event"-Knopf — die Wahrheit darueber,
-- wer am Event steht, liegt ausschliesslich serverseitig
-- (EventParticipationService), dieser Event teilt sie nur mit.
-- Args: atEvent: boolean, baerchiUid: string?
local EventPresenceChanged = getOrCreateEvent("EventPresenceChanged")

-- Der Event-Zyklus hat die Phase gewechselt: ein Event hat begonnen oder ist
-- vorbei. Geht an ALLE Spieler (der Zyklus ist fuer alle derselbe) und beim
-- Join zusaetzlich einmal gezielt an den neuen Spieler.
--
-- Uebertragen wird nur die eventId, NICHT die Belohnung: den Katalog kennt der
-- Client selbst (EventConfig liegt in ReplicatedStorage), und ein zweiter
-- Uebertragungsweg fuer dieselben Zahlen waere genau die Art Doppelung, die
-- beim naechsten Balancing auseinander laeuft.
--
-- Args: eventId: string?  (nil = gerade Pause),
--       secondsRemaining: number,
--       nextEventId: string  (was als naechstes laeuft — waehrend der Pause
--                             die eigentlich wichtige Angabe, weil der Spieler
--                             danach entscheidet, ob er seinen Baerchi
--                             losschickt)
local EventPhaseChanged = getOrCreateEvent("EventPhaseChanged")

-- Ein gelegtes Ei wurde eingesammelt und liegt jetzt im Lager
-- Args: EggCollectResult
local EggCollectedReceived = getOrCreateEvent("EggCollectedReceived")

-- Beim Join: wie viele Eier waehrend der Abwesenheit dazugekommen sind
-- Args: OfflineEggReport
local OfflineEggReportReceived = getOrCreateEvent("OfflineEggReportReceived")

-- v12: Zustand des ausgeruesteten Baerchis fuer die untere Pet-Leiste
-- (PetBar). Die Wahrheit liegt ausschliesslich in PetModeService, dieser
-- Event teilt sie nur mit.
-- Args: state: string  ("Home" | "ToEvent" | "AtEvent" | "ToPit" | "InPit" | "Returning"),
--       pending: string? ("Event" | "Fight" — vorgemerktes Ziel beim Wechsel),
--       info: { stage: number? }?  (laufende Stage im PIT, fuer die Beschriftung)
local PetModeChanged = getOrCreateEvent("PetModeChanged")

-- Eine Anfrage wurde serverseitig abgelehnt — Client zeigt Toast/Fehlertext.
-- Args: action: string, reason: Types.LocMsg  (Schluessel + Zahlen, KEIN fertiger
--       Satz: der Client baut den Text in der Sprache des Spielers, siehe
--       Localization/Loc. Ein einfacher String wird als Altlast unveraendert
--       angezeigt.)
-- v13: Quest-Belohnung wurde ausgezahlt (Toast). Args: reward: Types.QuestReward
local QuestRewardReceived = getOrCreateEvent("QuestRewardReceived")

local ActionFailed = getOrCreateEvent("ActionFailed")

-- v14 (Mega Egg Tree): Ei-Baum, Ei-Presse, Blaupausen, Faehigkeiten-Show
local EggTreeUnlocked        = getOrCreateEvent("EggTreeUnlocked")        -- S->C (Types.EggUnlockResult)
local EggPressResultReceived = getOrCreateEvent("EggPressResultReceived") -- S->C (Types.EggPressResult)
local SkillFXPlay            = getOrCreateEvent("SkillFXPlay")            -- S->C (alle Clients, siehe PitArenaService)
local RequestPressEggs       = getOrCreateEvent("RequestPressEggs")       -- C->S (eggType, path?)
local RequestUseBlueprint    = getOrCreateEvent("RequestUseBlueprint")    -- C->S (eggType)

-- ============================================================
-- Client → Server Events (Anfragen)
-- ============================================================

-- Spieler oeffnet ein Ei aus seinem Lager (seit v12 sofort, ohne Brutzeit
-- und ohne Kauf). Ergebnis kommt ueber HatchResultReceived.
-- Args: eggType: string
local RequestHatchEgg = getOrCreateEvent("RequestHatchEgg")

-- v13: Quest-Belohnung abholen. Der Server prueft selbst, ob die Quest erledigt ist.
-- Args: kind: "chain" | "daily", questId: string
local RequestClaimQuest = getOrCreateEvent("RequestClaimQuest")

-- v12: Pet-Leiste. Der Client sagt nur, welcher Knopf gedrueckt wurde — was
-- daraus folgt (hinschicken, zurueckholen, wechseln), entscheidet
-- PetModeService.
-- Args: mode: "Event" | "Fight" | "Home",
--       resume: ("Fresh" | "Percent" | "Last")?  (nur bei "Fight": Wahl aus der
--               Fortsetzungs-Frage; nil = von vorn)
local RequestPetMode = getOrCreateEvent("RequestPetMode")

-- Spieler will ein Gebaeude upgraden
-- Args: buildingId: string
local RequestUpgradeBuilding = getOrCreateEvent("RequestUpgradeBuilding")

-- Spieler will die Kampfplattform um eine Schicht erhoehen
-- Args: (keine)
local RequestUpgradePit = getOrCreateEvent("RequestUpgradePit")

-- Spieler will zwei Baerchis fusionieren
--
-- Args: uidA: string, uidB: string,
--       lockedProperty: ("ability" | "level" | "eggs")?,   -- nil = alles automatisch
--       lockedFrom:     ("A" | "B")?                        -- nur wenn lockedProperty gesetzt
--
-- Die beiden letzten Argumente kommen aus dem Sperr-Schritt des Fusions-Menues
-- (siehe FusionPanel). Sie sind optional: ein Aufruf ohne sie verhaelt sich wie
-- vor der Erweiterung, alles automatisch nach der Standard-Regel.
local RequestFuseBaerchis = getOrCreateEvent("RequestFuseBaerchis")

-- Spieler will einen Baerchi mit Duplikaten befoerdern
-- Args: baerchiUid: string
local RequestPromoteBaerchi = getOrCreateEvent("RequestPromoteBaerchi")

-- Spieler will die Charms eines Baerchis neu wuerfeln.
-- `rolls` ist die Anzahl der Wuerfe in EINEM Paket (1 = "Roll Charms",
-- CharmConfig.AUTO_ROLL_COUNT = "Auto Roll"). Siehe CharmConfig, Kommentar bei
-- AUTO_ROLL_COUNT, warum das ein Paket ist und keine Schleife auf dem Client.
-- Args: baerchiUid: string, rolls: number?
local RequestRollCharms = getOrCreateEvent("RequestRollCharms")

-- Spieler will einen Charm-Slot gegen erneutes Wuerfeln sperren/freigeben
-- Args: baerchiUid: string, slot: number
local RequestToggleCharmLock = getOrCreateEvent("RequestToggleCharmLock")

-- Spieler sammelt ein gelegtes Ei auf, das in der Welt liegt.
-- Args: eggUid: string  (Types.LaidEgg.uid — NICHT die Position: die aendert
--       sich nicht, aber eine uid ist eindeutig auch dann noch, wenn zwei Eier
--       uebereinander liegen.)
local RequestCollectEgg = getOrCreateEvent("RequestCollectEgg")

-- Spieler sammelt ALLE herumliegenden Eier auf einmal auf.
-- Args: (keine)
local RequestCollectAllEggs = getOrCreateEvent("RequestCollectAllEggs")

-- Spieler will einen Baerchi verwerten
-- Args: baerchiUid: string
local RequestRecycleBaerchi = getOrCreateEvent("RequestRecycleBaerchi")

-- Spieler will einen Baerchi mit einem Honig fuettern (heilt + gibt XP).
-- Aus welchem Gebaeude der Honig kommt, entscheidet der Server (bestes zuerst).
-- Args: baerchiUid: string
local RequestFeedHoney = getOrCreateEvent("RequestFeedHoney")

-- Spieler will einen Baerchi ausruesten. Es steht immer nur EINER auf dem
-- Plot — die anderen bleiben im Inventar. Siehe IslandService.equipBaerchi.
-- Args: baerchiUid: string
local RequestEquipBaerchi = getOrCreateEvent("RequestEquipBaerchi")

-- Spieler will Rebirth machen
-- Args: (keine)
local RequestRebirth = getOrCreateEvent("RequestRebirth")

-- Spieler waehlt seine Sprache. nil/"auto" = zurueck auf die Roblox-Sprache.
-- Args: language: string?   ("de" | "en" | "fr" | "es")
local RequestSetLanguage = getOrCreateEvent("RequestSetLanguage")

-- ============================================================
-- Client → Server Functions (brauchen eine Antwort)
-- ============================================================

-- Spieler fragt seine aktuellen Daten an (z.B. nach Reconnect)
-- Returns: PlayerDataUpdate?
local GetPlayerData = getOrCreateFunction("GetPlayerData")

return {
	-- Server → Client
	PlayerDataUpdated     = PlayerDataUpdated,
	CombatResultReceived  = CombatResultReceived,
	HatchResultReceived   = HatchResultReceived,
	FusionResultReceived  = FusionResultReceived,
	RecycleResultReceived = RecycleResultReceived,
	RebirthResultReceived = RebirthResultReceived,
	OfflineReportReceived = OfflineReportReceived,
	FeedResultReceived    = FeedResultReceived,
	PromotionResultReceived = PromotionResultReceived,
	CharmRollResultReceived = CharmRollResultReceived,
	EventStatGained         = EventStatGained,
	EventPresenceChanged    = EventPresenceChanged,
	EventPhaseChanged       = EventPhaseChanged,
	EggCollectedReceived    = EggCollectedReceived,
	OfflineEggReportReceived = OfflineEggReportReceived,
	PetModeChanged          = PetModeChanged,
	QuestRewardReceived     = QuestRewardReceived,
	ActionFailed          = ActionFailed,

	EggTreeUnlocked        = EggTreeUnlocked,
	EggPressResultReceived = EggPressResultReceived,
	SkillFXPlay            = SkillFXPlay,
	RequestPressEggs       = RequestPressEggs,
	RequestUseBlueprint    = RequestUseBlueprint,

	-- Client → Server
	RequestHatchEgg        = RequestHatchEgg,
	RequestClaimQuest      = RequestClaimQuest,
	RequestPetMode         = RequestPetMode,
	RequestUpgradeBuilding = RequestUpgradeBuilding,
	RequestUpgradePit      = RequestUpgradePit,
	RequestFuseBaerchis    = RequestFuseBaerchis,
	RequestRecycleBaerchi  = RequestRecycleBaerchi,
	RequestFeedHoney       = RequestFeedHoney,
	RequestEquipBaerchi    = RequestEquipBaerchi,
	RequestRebirth         = RequestRebirth,
	RequestSetLanguage     = RequestSetLanguage,
	RequestPromoteBaerchi  = RequestPromoteBaerchi,
	RequestRollCharms      = RequestRollCharms,
	RequestToggleCharmLock = RequestToggleCharmLock,
	RequestCollectEgg      = RequestCollectEgg,
	RequestCollectAllEggs  = RequestCollectAllEggs,

	-- Functions
	GetPlayerData          = GetPlayerData,
}
