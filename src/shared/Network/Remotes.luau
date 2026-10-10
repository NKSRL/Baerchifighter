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

-- v15: Der Spieler hat seinen Waben-Stapel auf der eigenen Insel abgegeben.
-- Reiner Anzeige-Anlass (Meldung); die Waben gehen serverseitig direkt in die
-- Warteschlange des Recyclers (CombRecyclerService).
-- Args: count: number (Waben), units: number (Wabeneinheiten, goldene zaehlen mehr)
local CombDelivered = getOrCreateEvent("CombDelivered")

-- v15: Der Waben-Recycler wurde ausgebaut.
-- Args: newLevel: number
local RecyclerUpgraded = getOrCreateEvent("RecyclerUpgraded")

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

-- v17 (lebendige Events): Meldung waehrend eines Events, als LocMsg (der
-- Client uebersetzt). Geht an einen Spieler oder an alle (Jackpot, Boss).
-- Args: msg: Types.LocMsg, style: ("info" | "good" | "big")?
local EventNotice = getOrCreateEvent("EventNotice")

-- v17: Telegraph einer Boss-Attacke (an alle). Args: Types.HazardTelegraph
local EventTelegraph = getOrCreateEvent("EventTelegraph")

-- v17: Der eigene Charakter wurde von einer Boss-Attacke getroffen.
-- Args: Types.HazardHit
local EventHazardHit = getOrCreateEvent("EventHazardHit")

-- v15 (Tower): ein Tower-Meilenstein wurde ausgezahlt (Toast).
-- Args: Types.TowerMilestoneReward
local TowerMilestoneReceived = getOrCreateEvent("TowerMilestoneReceived")
-- 08.10.: ein Tower ist durch Schaffen des vorherigen frei geworden
-- (Server → Client, Argument: TowerId). Feier-Moment + "NEU"-Abzeichen.
local TowerUnlocked = getOrCreateEvent("TowerUnlocked")

-- v15: Login-Bonus ausgezahlt (Toast). Args: Types.DailyBonusResult
local DailyBonusReceived = getOrCreateEvent("DailyBonusReceived")

-- v14 (Mega Egg Tree): Ei-Baum, Ei-Presse, Blaupausen, Faehigkeiten-Show
local EggTreeUnlocked        = getOrCreateEvent("EggTreeUnlocked")        -- S->C (Types.EggUnlockResult)
local EggPressResultReceived = getOrCreateEvent("EggPressResultReceived") -- S->C (Types.EggPressResult)
local SkillFXPlay            = getOrCreateEvent("SkillFXPlay")            -- S->C (alle Clients, siehe PitArenaService)
-- Welt aufwerten, Paket G: ein grosser Moment eines Spielers, an ALLE Clients.
-- Der Server sagt nur WAS passiert ist; wie es aussieht entscheidet der Client
-- (WorldMomentController). Args: { userId, kind, value, number?, big }
-- (kind: "hatch" | "tower" | "record" | "rebirth" | "mutation", siehe Modules/WorldMoments)
local WorldMoment            = getOrCreateEvent("WorldMoment")            -- S->C (alle Clients, siehe WorldMomentService)
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

-- (v15: RequestUpgradePit ist entfallen — es gibt kein PIT-Level mehr.)

-- v15: Tower waehlen, in den der Fight-Knopf schickt. Der Server prueft, ob
-- der Tower beim aktuellen Rebirth offen ist (TowerConfig.isOpen).
-- Args: towerId: string
local RequestSelectTower = getOrCreateEvent("RequestSelectTower")
-- 08.10. (Paket C): Kauf-Dialog fuer einen Gamepass (Argument: Pass-Key aus
-- GamepassConfig). Der Server prueft Id und Besitz.
local RequestBuyGamepass = getOrCreateEvent("RequestBuyGamepass")

-- v15: taeglichen Login-Bonus abholen. Der Server prueft UTC-Tag,
-- Gnadenfrist und doppelte Abholung (Modules/LoginBonusCalc).
-- Args: (keine)
local RequestClaimDailyBonus = getOrCreateEvent("RequestClaimDailyBonus")

-- v15: Waben-Recycler ausbauen (kein Argument: es gibt nur einen pro Insel)
local RequestUpgradeRecycler = getOrCreateEvent("RequestUpgradeRecycler")

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

-- HBB Paket 0: Messpunkte der Oberflaeche (Panel geoeffnet, Panel schnell
-- wieder geschlossen, Spieler steht still). Reine Statistik, aendert nichts
-- am Spielstand. Der Server prueft Art und Panel-Namen gegen
-- FunnelConfig und deckelt die Anzahl pro Sitzung.
-- Args: kind: "PanelOpened" | "PanelQuickClose" | "IdleStanding",
--       panelName: string?
local RequestLogUiEvent = getOrCreateEvent("RequestLogUiEvent")

-- HBB Paket 3: Bedienelemente als "gesehen" markieren (Badge verschwindet).
-- Rein kosmetisch; der Server prueft nur die Ids gegen UnlockRules.ELEMENTS.
-- Args: ids: string | { string }
local RequestMarkUiSeen = getOrCreateEvent("RequestMarkUiSeen")

-- HBB Paket 5: Heim-Knopf. Der Server teleportiert auf den eigenen Plot,
-- ausser der Spieler traegt Waben (dann ActionFailed).
-- Args: (keine)
local RequestGoHome = getOrCreateEvent("RequestGoHome")
-- HBB Paket 10: Shop — Gratis-Griff (Client -> Server, keine Argumente)
local RequestClaimFreeGrab = getOrCreateEvent("RequestClaimFreeGrab")

-- ============================================================
-- Sammel-Update 05.10.
-- ============================================================
-- Paket 4.3: Tower-Wiedergabe beschleunigen. Args: speed (1 | 2 | 4 | 0 = sofort)
local RequestPitSpeed = getOrCreateEvent("RequestPitSpeed")
-- Paket 7: Index-Belohnung abholen. Args: rewardId (IndexRewardConfig)
local RequestClaimIndexReward = getOrCreateEvent("RequestClaimIndexReward")
-- Paket 7: Belohnung ausgezahlt (S->C, Toast). Args: Types.IndexRewardResult
local IndexRewardReceived = getOrCreateEvent("IndexRewardReceived")
-- Paket 6.2: besonderer Meilenstein ausgezahlt (S->C). Args: Types.SpecialMilestoneResult
local SpecialMilestoneReceived = getOrCreateEvent("SpecialMilestoneReceived")
-- Paket 8: Inkubator. Start (eggType), Abholen (slot), Beschleunigen (slot),
-- Ausbauen (keine Args). Das Schluepfen meldet HatchResultReceived.
local RequestIncubatorStart   = getOrCreateEvent("RequestIncubatorStart")
local RequestIncubatorCollect = getOrCreateEvent("RequestIncubatorCollect")
local RequestIncubatorSpeedUp = getOrCreateEvent("RequestIncubatorSpeedUp")
local RequestUpgradeIncubator = getOrCreateEvent("RequestUpgradeIncubator")
-- INCUBATOR_BREED: ("put", baerchiUid) / ("take", platz)
local RequestIncubatorBaerchi = getOrCreateEvent("RequestIncubatorBaerchi")
-- Paket 8: S->C Hinweis "Platz belegt / fertig / abgeholt" (Feedback, Ton).
-- Args: { slot: number, kind: "start" | "ready" | "collect" | "speedup" | "upgrade" }
local IncubatorChanged = getOrCreateEvent("IncubatorChanged")

-- ============================================================
-- Client → Server Functions (brauchen eine Antwort)
-- ============================================================

-- Spieler fragt seine aktuellen Daten an (z.B. nach Reconnect)
-- Returns: PlayerDataUpdate?
local GetPlayerData = getOrCreateFunction("GetPlayerData")

-- v15: eine Bestenliste (LeaderboardService, gecacht).
-- Args: listId: "Tower" | "Rebirths" | "Collection"
-- Returns: Types.LeaderboardView?
local GetLeaderboard = getOrCreateFunction("GetLeaderboard")

-- v15: Profilkarte eines anderen Spielers auf DIESEM Server (Inspektor).
-- Args: userId: number
-- Returns: Types.PlayerProfileCard?
local GetPlayerProfile = getOrCreateFunction("GetPlayerProfile")

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
	CombDelivered           = CombDelivered,
	RecyclerUpgraded        = RecyclerUpgraded,
	QuestRewardReceived     = QuestRewardReceived,
	ActionFailed          = ActionFailed,
	EventNotice           = EventNotice,
	EventTelegraph        = EventTelegraph,
	EventHazardHit        = EventHazardHit,

	TowerMilestoneReceived = TowerMilestoneReceived,
	TowerUnlocked          = TowerUnlocked,
	DailyBonusReceived     = DailyBonusReceived,

	EggTreeUnlocked        = EggTreeUnlocked,
	EggPressResultReceived = EggPressResultReceived,
	SkillFXPlay            = SkillFXPlay,
	WorldMoment            = WorldMoment,
	RequestPressEggs       = RequestPressEggs,
	RequestUseBlueprint    = RequestUseBlueprint,

	-- Client → Server
	RequestHatchEgg        = RequestHatchEgg,
	RequestClaimQuest      = RequestClaimQuest,
	RequestPetMode         = RequestPetMode,
	RequestUpgradeBuilding = RequestUpgradeBuilding,
	RequestSelectTower     = RequestSelectTower,
	RequestBuyGamepass     = RequestBuyGamepass,
	RequestClaimDailyBonus = RequestClaimDailyBonus,
	RequestUpgradeRecycler = RequestUpgradeRecycler,
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
	RequestLogUiEvent      = RequestLogUiEvent,
	RequestMarkUiSeen      = RequestMarkUiSeen,
	RequestGoHome          = RequestGoHome,
	RequestClaimFreeGrab   = RequestClaimFreeGrab,

	-- Sammel-Update 05.10.
	RequestPitSpeed          = RequestPitSpeed,
	RequestClaimIndexReward  = RequestClaimIndexReward,
	IndexRewardReceived      = IndexRewardReceived,
	SpecialMilestoneReceived = SpecialMilestoneReceived,
	RequestIncubatorStart    = RequestIncubatorStart,
	RequestIncubatorCollect  = RequestIncubatorCollect,
	RequestIncubatorSpeedUp  = RequestIncubatorSpeedUp,
	RequestUpgradeIncubator  = RequestUpgradeIncubator,
	RequestIncubatorBaerchi  = RequestIncubatorBaerchi,
	IncubatorChanged         = IncubatorChanged,

	-- Functions
	GetPlayerData          = GetPlayerData,
	GetLeaderboard         = GetLeaderboard,
	GetPlayerProfile       = GetPlayerProfile,
}
